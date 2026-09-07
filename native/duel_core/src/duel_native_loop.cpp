#include "duel_native_resolution_stack.h"

#include "duel_native_compact_kernel_internal.h"

#include <algorithm>
#include <cstdint>
#include <unordered_map>
#include <unordered_set>

namespace godot::duel_native_internal {
namespace {

constexpr uint8_t LOOP_OCCURRENCE_LIMIT = 20;
constexpr uint64_t RESOLUTION_STEP_CEILING = 1'000'000;

class FingerprintWriter {
public:
	void value(uint64_t item) {
		first ^= item + 0x9e3779b97f4a7c15ULL + (first << 6) + (first >> 2);
		first *= 1099511628211ULL;
		second ^= item + 0x517cc1b727220a95ULL + (second << 7) + (second >> 3);
		second *= 14029467366897019727ULL;
	}

	void integer(int64_t item) {
		value(static_cast<uint64_t>(item));
	}

	void boolean(bool item) {
		value(item ? 0xf00dULL : 0x0badULL);
	}

	void name(const StringName &item) {
		value(static_cast<uint64_t>(item.hash()));
	}

	void text(const String &item) {
		value(static_cast<uint64_t>(item.hash()));
	}

	void variant(const Variant &item) {
		value(static_cast<uint64_t>(item.hash()));
	}

	void card(int32_t raw_index) {
		if (raw_index < 0) {
			value(0xffffffffffffffffULL);
			return;
		}
		const auto found = canonical_cards.find(raw_index);
		if (found != canonical_cards.end()) {
			value(found->second);
			return;
		}
		const uint64_t canonical = canonical_cards.size();
		canonical_cards.emplace(raw_index, canonical);
		value(canonical);
	}

	std::pair<uint64_t, uint64_t> finish() const {
		return {first, second};
	}

private:
	uint64_t first = 1469598103934665603ULL;
	uint64_t second = 1099511628211ULL;
	std::unordered_map<int32_t, uint64_t> canonical_cards;
};

template <typename T>
void hash_integer_vector(FingerprintWriter &writer, const std::vector<T> &values) {
	writer.integer(static_cast<int64_t>(values.size()));
	for (const T &value : values) writer.integer(static_cast<int64_t>(value));
}

void hash_card_vector(FingerprintWriter &writer, const std::vector<int32_t> &values) {
	writer.integer(static_cast<int64_t>(values.size()));
	for (const int32_t value : values) writer.card(value);
}

template <typename Records>
void hash_flip_records(FingerprintWriter &writer, const Records &records) {
	writer.integer(static_cast<int64_t>(records.size()));
	for (const auto &record : records) {
		writer.card(record.card_index);
		writer.integer(record.previous_owner);
	}
}

template <typename Context>
void hash_event_context(FingerprintWriter &writer, const Context &context, bool causal) {
	writer.integer(context.ability_source_cell);
	writer.integer(context.ability_source_zone);
	writer.integer(context.ability_source_logical_index);
	writer.card(context.ability_source_card_index);
	writer.integer(context.ability_source_owner);
	writer.integer(context.trigger_cell);
	writer.card(context.trigger_card_index);
	writer.integer(context.trigger_owner);
	writer.integer(context.trigger_previous_owner);
	writer.integer(context.trigger_zone);
	writer.integer(context.trigger_logical_index);
	writer.integer(context.attacker_cell);
	writer.card(context.attacker_card_index);
	writer.integer(context.attacker_owner);
	writer.integer(context.attacked_cell);
	writer.card(context.attacked_card_index);
	writer.integer(context.attacked_owner);
	writer.integer(context.new_owner);
	writer.boolean(context.trigger_was_on_board);
	writer.boolean(context.attack_flipped_enemy);
	if (!causal) {
		writer.integer(context.previous_ki);
		writer.integer(context.ki);
	}
	writer.integer(context.moving_source_cell);
	writer.integer(context.moving_origin_cell);
	writer.integer(context.moving_target_cell);
	writer.card(context.moving_card_index);
	writer.integer(context.moving_owner);
	writer.integer(context.discard_owner);
	writer.integer(context.discard_batch_size);
	writer.integer(context.turn_owner);
	writer.integer(context.activation_owner);
	writer.integer(context.activation_source_cell);
	writer.card(context.activation_source_card_index);
	writer.name(context.activation_target_kind);
	writer.integer(context.activation_target_index);
	writer.boolean(context.repeat_attack);
	hash_integer_vector(writer, context.winning_owners);
	hash_flip_records(writer, context.attack_flips);
	writer.name(context.attack_reason);
	writer.name(context.flip_reason);
	writer.name(context.exile_reason);
	writer.name(context.discard_batch_id);
}

template <typename Group>
void hash_event_group(FingerprintWriter &writer, const Group &group) {
	writer.integer(group.source_cell);
	writer.integer(group.source_zone);
	writer.integer(group.source_logical_index);
	writer.card(group.source_card_index);
	writer.integer(group.source_owner);
	writer.integer(group.ability_index);
	// ability_handle contains allocation identity. The source/reference relation and
	// catalog-local ability index carry the rule meaning needed by this fingerprint.
	writer.integer(group.trigger_index);
}

template <typename Context>
void hash_action_context(FingerprintWriter &writer, const Context &context) {
	writer.integer(context.ability_source_cell);
	writer.integer(context.ability_source_zone);
	writer.integer(context.ability_source_logical_index);
	writer.card(context.ability_source_card_index);
	writer.integer(context.ability_source_owner);
	writer.card(context.action_subject_card_index);
	writer.integer(context.action_subject_owner);
	writer.integer(context.action_subject_zone);
	writer.integer(context.action_subject_logical_index);
	writer.card(context.selected_card_index);
	writer.integer(context.selected_card_owner);
	writer.integer(context.selected_card_zone);
	writer.integer(context.selected_card_logical_index);
	writer.name(context.activation_target_kind);
	writer.integer(context.activation_target_index);
	writer.boolean(context.record_direct_board_changes);
	writer.card(context.trigger_card_index);
	writer.card(context.attacker_card_index);
	writer.name(context.event_id);
	writer.integer(context.discovery_ability_index);
	writer.integer(context.trigger_index);
	hash_flip_records(writer, context.attack_flips);
}

template <typename State>
void hash_execution_state(FingerprintWriter &writer, const State &state) {
	writer.integer(state.last_discard_batch_size);
	writer.integer(state.current_source_cell);
	writer.card(state.last_summoned_card_index);
	writer.integer(state.last_summoned_cell);
	hash_card_vector(writer, state.departed_card_indices);
}

template <typename Requests>
void hash_extra_plays(FingerprintWriter &writer, const Requests &requests) {
	writer.integer(static_cast<int64_t>(requests.size()));
	for (const auto &request : requests) {
		writer.integer(request.owner_id);
		writer.card(request.source_card_index);
		writer.integer(request.source_cell);
		writer.integer(request.amount);
	}
}

template <typename Resolution>
void hash_resolution_control(FingerprintWriter &writer, const Resolution &resolution) {
	writer.boolean(resolution.supported);
	writer.boolean(resolution.flip_prevented);
	hash_extra_plays(writer, resolution.extra_play_requests);
}

template <typename Policy>
void hash_attack_policy(FingerprintWriter &writer, const Policy &policy) {
	writer.integer(static_cast<int64_t>(policy.target_policy));
	writer.integer(policy.capture_owner_id);
	writer.boolean(policy.specified);
}

template <typename Request>
void hash_attack_request(FingerprintWriter &writer, const Request &request) {
	writer.integer(request.attacker_cell);
	writer.card(request.attacker_card_index);
	writer.integer(request.attacker_owner);
	hash_attack_policy(writer, request.requested_policy);
	writer.boolean(request.targeted);
	writer.integer(request.locked_target_cell);
	writer.card(request.locked_target_card_index);
	writer.integer(request.locked_target_owner);
	writer.boolean(request.repeat_attack);
	writer.name(request.reason);
}

template <typename Request>
void hash_summon_request(FingerprintWriter &writer, const Request &request) {
	writer.integer(request.summon_cell);
	writer.card(request.card_index);
	writer.integer(request.owner_id);
	writer.name(request.summon_reason);
	writer.name(request.attack_reason);
	hash_card_vector(writer, request.attack_redirect_source_card_indices);
	writer.boolean(request.attack_redirect_snapshot_taken);
}

template <typename Action>
void hash_compiled_action(FingerprintWriter &writer, const Action &action) {
	writer.boolean(action.declaration_valid);
	writer.name(action.declaration_type);
	writer.integer(static_cast<int64_t>(action.opcode));
	writer.integer(static_cast<int64_t>(action.card_ref));
	writer.integer(static_cast<int64_t>(action.from_card_ref));
	writer.integer(static_cast<int64_t>(action.to_card_ref));
	writer.boolean(action.card_ref_explicit);
	writer.integer(action.amount);
	writer.boolean(action.amount_is_hand_count);
	writer.integer(static_cast<int64_t>(action.amount_owner));
	writer.integer(static_cast<int64_t>(action.new_owner));
	writer.integer(static_cast<int64_t>(action.recipient_owner));
	writer.integer(action.granted_ability_index);
	writer.boolean(action.preserve_instance);
	writer.boolean(action.repeat_attack);
	writer.boolean(action.target_policy_specified);
	writer.integer(static_cast<int64_t>(action.target_policy));
	writer.integer(static_cast<int64_t>(action.resource));
	writer.integer(static_cast<int64_t>(action.fallback_resource));
	writer.integer(static_cast<int64_t>(action.recipient));
	writer.integer(static_cast<int64_t>(action.reveal_filter));
	writer.integer(static_cast<int64_t>(action.card_spec));
	writer.integer(static_cast<int64_t>(action.cell_spec));
	writer.integer(static_cast<int64_t>(action.summon_card_ref));
	writer.integer(static_cast<int64_t>(action.summon_cell_card_ref));
	writer.integer(static_cast<int64_t>(action.summon_owner));
	writer.integer(static_cast<int64_t>(action.summon_board_owner));
	writer.name(action.change_reason);
	writer.text(action.weapon);
	writer.boolean(action.stop_rule_on_invalid_context);
	writer.name(action.power_change_batch_group);
	writer.name(action.card_id);
}

} // namespace

void ResolutionEngine::reset_loop_detection() {
	loop_occurrences.clear();
	resolution_loop_detected = false;
	resolution_aborted = false;
	resolution_loop_output = DuelNativeCompactKernel::Resolution();
	resolution_step_count = 0;
}

std::pair<uint64_t, uint64_t> ResolutionEngine::inspect_loop_key_for_test(
	const DuelNativeCompactKernel::NativeState &state,
	const StringName &event_id,
	const DuelNativeCompactKernel::EventContext &context
) {
	resolution_frames.clear();
	push_event_frame(event_id, context);
	const LoopFingerprint fingerprint = fingerprint_loop_key(state);
	resolution_frames.clear();
	return {fingerprint.first, fingerprint.second};
}

ResolutionEngine::LoopFingerprint ResolutionEngine::fingerprint_frame_range(
	const DuelNativeCompactKernel::NativeState &state,
	size_t begin,
	size_t end,
	bool causal
) const {
	(void)state;
	FingerprintWriter writer;
	writer.integer(static_cast<int64_t>(end - begin));
	for (size_t index = begin; index < end; ++index) {
		const ResolutionFrame &entry = *resolution_frames[index];
		writer.integer(static_cast<int64_t>(entry.kind));
		if (causal) {
			writer.value(entry.causal_board_first);
			writer.value(entry.causal_board_second);
		}
		switch (entry.kind) {
			case FrameKind::EVENT: {
				const EventFrame &frame = entry.event;
				writer.integer(static_cast<int64_t>(frame.stage));
				writer.name(frame.event_id);
				hash_event_context(writer, frame.context, causal);
				writer.integer(frame.group_index);
				writer.integer(frame.groups.size());
				for (const auto &group : frame.groups) hash_event_group(writer, group);
				hash_resolution_control(writer, frame.resolution);
				break;
			}
			case FrameKind::ACTION_SEQUENCE: {
				const ActionSequenceFrame &frame = entry.actions;
				writer.integer(static_cast<int64_t>(frame.stage));
				writer.value(reinterpret_cast<uintptr_t>(frame.actions));
				hash_event_group(writer, frame.group);
				hash_event_context(writer, frame.event_context, causal);
				hash_action_context(writer, frame.action_context);
				hash_execution_state(writer, frame.execution_state);
				writer.integer(frame.action_index);
				writer.integer(static_cast<int64_t>(frame.aggregate));
				writer.boolean(frame.defer_power_change_batch);
				writer.integer(frame.active_action_index);
				hash_card_vector(writer, frame.selected_cards);
				writer.integer(frame.selected_card_index);
				writer.integer(static_cast<int64_t>(frame.selected_aggregate));
				writer.integer(static_cast<int64_t>(frame.pending_outcome));
				writer.integer(frame.child_target_cell);
				writer.boolean(frame.update_source_after_swap);
				if (
					frame.stage == ActionStage::NEXT_KI_EVENT
					|| frame.stage == ActionStage::WAIT_KI_EVENT
				) {
					writer.integer(frame.ki_event_index);
					writer.integer(frame.ki_resolution_start);
				}
				if (frame.stage == ActionStage::WAIT_RETURN_EXILE) {
					writer.integer(frame.return_previous_event_count);
				}
				if (frame.resolution != nullptr) {
					hash_resolution_control(writer, *frame.resolution);
				}
				break;
			}
			case FrameKind::EXILE: {
				const ExileFrame &frame = entry.exile;
				writer.integer(static_cast<int64_t>(frame.stage));
				writer.card(frame.card_index);
				writer.integer(frame.source_cell);
				writer.card(frame.ability_source_card_index);
				writer.boolean(frame.self_removal);
				writer.name(frame.exile_reason);
				hash_event_context(writer, frame.parent_context, causal);
				writer.boolean(frame.record_exile_index);
				writer.boolean(frame.guard_pushed);
				writer.integer(frame.initial_zone);
				writer.integer(frame.initial_owner);
				writer.integer(frame.initial_index);
				writer.integer(frame.exiled_cell);
				writer.boolean(frame.success);
				break;
			}
			case FrameKind::FLIP: {
				const FlipFrame &frame = entry.flip;
				writer.integer(static_cast<int64_t>(frame.stage));
				writer.integer(frame.attacker_cell);
				writer.card(frame.attacker_card_index);
				writer.integer(frame.target_cell);
				writer.card(frame.target_card_index);
				writer.integer(frame.new_owner);
				hash_event_context(writer, frame.context, causal);
				writer.boolean(frame.record_capture_index);
				writer.integer(frame.required_attacker_owner);
				hash_integer_vector(writer, frame.remove_before_after_flip);
				hash_integer_vector(writer, frame.remove_after_after_flip);
				writer.boolean(frame.success);
				break;
			}
			case FrameKind::DRAW: {
				const DrawFrame &frame = entry.draw;
				writer.integer(static_cast<int64_t>(frame.stage));
				writer.integer(frame.owner);
				writer.integer(frame.source_cell);
				writer.integer(frame.amount);
				writer.text(frame.weapon_filter);
				hash_event_context(writer, frame.draw_context, causal);
				writer.integer(frame.draw_index);
				writer.boolean(frame.success);
				break;
			}
			case FrameKind::DISCARD: {
				const DiscardFrame &frame = entry.discard;
				writer.integer(static_cast<int64_t>(frame.stage));
				hash_event_group(writer, frame.group);
				hash_card_vector(writer, frame.locked_cards);
				hash_event_context(writer, frame.event_context, causal);
				hash_action_context(writer, frame.action_context);
				writer.integer(frame.records.size());
				for (const auto &record : frame.records) {
					writer.card(record.card_index);
					writer.integer(record.logical_hand_index);
					writer.integer(record.hand_slot_index);
				}
				writer.integer(frame.record_index);
				writer.integer(frame.owner);
				writer.integer(frame.source_cell);
				writer.integer(static_cast<int64_t>(frame.outcome));
				break;
			}
			case FrameKind::MOVE: {
				const MoveFrame &frame = entry.move;
				writer.integer(static_cast<int64_t>(frame.stage));
				writer.integer(frame.source_cell);
				writer.integer(frame.origin_cell);
				writer.integer(frame.target_cell);
				writer.card(frame.moving_card_index);
				writer.integer(frame.moving_owner);
				writer.boolean(frame.resolve_before_event);
				hash_resolution_control(writer, frame.movement_resolution);
				writer.integer(static_cast<int64_t>(frame.outcome));
				break;
			}
			case FrameKind::SWAP: {
				const SwapFrame &frame = entry.swap;
				writer.integer(static_cast<int64_t>(frame.stage));
				writer.card(frame.source_card_index);
				writer.integer(frame.source_owner);
				writer.integer(frame.source_cell);
				writer.card(frame.target_card_index);
				writer.integer(frame.target_owner);
				writer.integer(frame.target_cell);
				hash_resolution_control(writer, frame.swap_resolution);
				writer.integer(static_cast<int64_t>(frame.outcome));
				break;
			}
			case FrameKind::SUMMON: {
				const SummonFrame &frame = entry.summon;
				writer.integer(static_cast<int64_t>(frame.stage));
				hash_summon_request(writer, frame.request);
				hash_card_vector(writer, frame.attack_redirect_source_card_indices);
				hash_event_context(writer, frame.summon_context, causal);
				hash_resolution_control(writer, frame.resolution);
				writer.integer(frame.after_summoned_cell);
				break;
			}
			case FrameKind::ATTACK: {
				const AttackFrame &frame = entry.attack;
				writer.integer(static_cast<int64_t>(frame.stage));
				hash_attack_request(writer, frame.request);
				hash_attack_policy(writer, frame.attack_policy);
				hash_integer_vector(writer, frame.target_cells);
				writer.integer(frame.target_index);
				hash_resolution_control(writer, frame.resolution);
				writer.boolean(frame.attack_started);
				writer.boolean(frame.attack_flipped_enemy);
				hash_flip_records(writer, frame.attack_flips);
				writer.integer(frame.attacker_cell);
				writer.integer(frame.attacked_cell);
				writer.card(frame.attacked_card_index);
				writer.integer(frame.attacked_owner);
				writer.integer(frame.resolved_capture_owner);
				writer.integer(frame.flipped_previous_owner);
				writer.boolean(frame.stop_after_current_target);
				if (frame.stage == AttackStage::WAIT_FLIP) {
					writer.integer(frame.flip_event_start);
				}
				hash_event_context(writer, frame.attack_context, causal);
				break;
			}
			case FrameKind::DISTRIBUTE_KI: {
				const DistributeKiFrame &frame = entry.distribute_ki;
				writer.integer(static_cast<int64_t>(frame.stage));
				hash_event_group(writer, frame.group);
				hash_compiled_action(writer, frame.action);
				hash_event_context(writer, frame.event_context, causal);
				hash_action_context(writer, frame.action_context);
				hash_execution_state(writer, frame.execution_state);
				hash_action_context(writer, frame.selector_context);
				hash_card_vector(writer, frame.selected_cards);
				writer.card(frame.distributor);
				writer.integer(frame.distributor_zone);
				writer.integer(frame.distributor_owner);
				writer.integer(frame.distributor_logical_index);
				writer.integer(frame.recipient_index);
				writer.boolean(frame.transferred_in_round);
				if (
					frame.stage == DistributeKiStage::NEXT_KI_EVENT
					|| frame.stage == DistributeKiStage::WAIT_KI_EVENT
				) {
					writer.integer(frame.ki_event_index);
					writer.integer(frame.ki_event_end);
				}
				writer.integer(static_cast<int64_t>(frame.outcome));
				break;
			}
			case FrameKind::POWER_CHANGE: {
				const PowerChangeFrame &frame = entry.power_change;
				writer.integer(static_cast<int64_t>(frame.stage));
				hash_event_group(writer, frame.group);
				hash_compiled_action(writer, frame.action);
				hash_event_context(writer, frame.event_context, causal);
				hash_action_context(writer, frame.action_context);
				writer.integer(frame.source_cell);
				writer.integer(static_cast<int64_t>(frame.outcome));
				break;
			}
			case FrameKind::TRANSFER_RESOURCE: {
				const TransferResourceFrame &frame = entry.transfer_resource;
				writer.integer(static_cast<int64_t>(frame.stage));
				hash_event_group(writer, frame.group);
				hash_compiled_action(writer, frame.action);
				hash_event_context(writer, frame.event_context, causal);
				hash_action_context(writer, frame.action_context);
				writer.integer(frame.source_cell);
				writer.card(frame.donor);
				writer.integer(frame.donor_owner);
				writer.card(frame.receiver);
				writer.integer(frame.receiver_owner);
				writer.integer(static_cast<int64_t>(frame.outcome));
				break;
			}
			case FrameKind::FINISH_ACTION: {
				const FinishActionFrame &frame = entry.finish_action;
				writer.integer(static_cast<int64_t>(frame.stage));
				writer.integer(frame.moving_owner);
				writer.card(frame.played_card_index);
				hash_extra_plays(writer, frame.extra_play_requests);
				hash_resolution_control(writer, frame.resolution);
				writer.integer(frame.previous_owner);
				writer.integer(frame.turn_owner);
				break;
			}
		}
	}
	const auto result = writer.finish();
	return {result.first, result.second};
}

ResolutionEngine::LoopFingerprint ResolutionEngine::fingerprint_loop_key(
	const DuelNativeCompactKernel::NativeState &state
) const {
	const LoopFingerprint board_turn = fingerprint_board_turn(state);
	FingerprintWriter writer;
	writer.value(board_turn.first);
	writer.value(board_turn.second);
	const LoopFingerprint stack = fingerprint_frame_range(
		state,
		0,
		resolution_frames.size(),
		false
	);
	writer.value(stack.first);
	writer.value(stack.second);
	const auto result = writer.finish();
	return {result.first, result.second};
}

ResolutionEngine::LoopFingerprint ResolutionEngine::fingerprint_board_turn(
	const DuelNativeCompactKernel::NativeState &state
) const {
	FingerprintWriter writer;
	writer.integer(state.scalars.size() > 1 ? state.scalars[1] : 0);
	writer.integer(state.board_card_indices.size());
	for (size_t cell = 0; cell < state.board_card_indices.size(); ++cell) {
		const int32_t card_index = state.board_card_indices[cell];
		if (
			card_index < 0
			|| card_index >= static_cast<int32_t>(state.card_ids.size())
		) {
			writer.value(0xffffffffffffffffULL);
			writer.integer(0);
			continue;
		}
		writer.name(state.card_ids[card_index]);
		writer.integer(state.board_owners[cell]);
	}
	const auto result = writer.finish();
	return {result.first, result.second};
}

bool ResolutionEngine::has_repeated_causal_suffix(
	const DuelNativeCompactKernel::NativeState &state
) const {
	const size_t stack_size = resolution_frames.size();
	if (stack_size < LOOP_OCCURRENCE_LIMIT) return false;
	// The newest causal cycle can have one active, not-yet-suspended tail frame.
	// Search every suffix after trimming such a partial tail rather than requiring
	// the repeated block to end at the physical top on this exact step.
	for (size_t end = stack_size; end >= LOOP_OCCURRENCE_LIMIT; --end) {
		const size_t max_block_size = end / LOOP_OCCURRENCE_LIMIT;
		for (size_t block_size = 1; block_size <= max_block_size; ++block_size) {
			const size_t suffix_begin = end - block_size * LOOP_OCCURRENCE_LIMIT;
			const LoopFingerprint expected = fingerprint_frame_range(
				state,
				suffix_begin,
				suffix_begin + block_size,
				true
			);
			bool all_equal = true;
			for (size_t repeat = 1; repeat < LOOP_OCCURRENCE_LIMIT; ++repeat) {
				const size_t begin = suffix_begin + repeat * block_size;
				if (!(fingerprint_frame_range(state, begin, begin + block_size, true) == expected)) {
					all_equal = false;
					break;
				}
			}
			if (all_equal) return true;
		}
	}
	return false;
}

DuelNativeCompactKernel::Resolution ResolutionEngine::collect_partial_resolution() const {
	DuelNativeCompactKernel::Resolution result;
	std::unordered_set<const DuelNativeCompactKernel::Resolution *> seen;
	auto append = [&](const DuelNativeCompactKernel::Resolution *resolution) {
		if (resolution == nullptr || !seen.insert(resolution).second) return;
		kernel.append_resolution(result, *resolution);
	};
	for (const auto &entry_pointer : resolution_frames) {
		const ResolutionFrame &entry = *entry_pointer;
		switch (entry.kind) {
			case FrameKind::EVENT: append(&entry.event.resolution); break;
			case FrameKind::ACTION_SEQUENCE: append(entry.actions.resolution); break;
			case FrameKind::EXILE: append(entry.exile.resolution); break;
			case FrameKind::FLIP: append(entry.flip.resolution); break;
			case FrameKind::DRAW: append(entry.draw.resolution); break;
			case FrameKind::DISCARD: append(entry.discard.resolution); break;
			case FrameKind::MOVE:
				append(entry.move.resolution);
				append(&entry.move.movement_resolution);
				break;
			case FrameKind::SWAP:
				append(entry.swap.resolution);
				append(&entry.swap.swap_resolution);
				break;
			case FrameKind::SUMMON: append(&entry.summon.resolution); break;
			case FrameKind::ATTACK: append(&entry.attack.resolution); break;
			case FrameKind::DISTRIBUTE_KI: append(entry.distribute_ki.resolution); break;
			case FrameKind::POWER_CHANGE: append(entry.power_change.resolution); break;
			case FrameKind::TRANSFER_RESOURCE: append(entry.transfer_resource.resolution); break;
			case FrameKind::FINISH_ACTION: append(&entry.finish_action.resolution); break;
		}
	}
	return result;
}

bool ResolutionEngine::detect_resolution_loop(
	DuelNativeCompactKernel::NativeState &state
) {
	if (!loop_detection_active || resolution_frames.empty()) return false;
	const LoopFingerprint causal_board = fingerprint_board_turn(state);
	for (const auto &entry : resolution_frames) {
		if (entry->causal_board_initialized) continue;
		entry->causal_board_first = causal_board.first;
		entry->causal_board_second = causal_board.second;
		entry->causal_board_initialized = true;
	}
	resolution_step_count += 1;
	if (resolution_step_count > RESOLUTION_STEP_CEILING) {
		resolution_loop_output = collect_partial_resolution();
		resolution_loop_output.supported = false;
		resolution_loop_output.reason = "Resolution step ceiling exceeded";
		resolution_aborted = true;
		resolution_frames.clear();
		return true;
	}
	const LoopFingerprint key = fingerprint_loop_key(state);
	uint8_t &occurrences = loop_occurrences[key];
	occurrences = static_cast<uint8_t>(std::min<int32_t>(occurrences + 1, 255));
	if (occurrences < LOOP_OCCURRENCE_LIMIT && !has_repeated_causal_suffix(state)) {
		return false;
	}
	resolution_loop_output = collect_partial_resolution();
	resolution_loop_detected = true;
	if (state.scalars.size() > 14) {
		state.scalars[14] = static_cast<int32_t>(
			DuelNativeCompactKernel::TerminalReason::RESOLUTION_LOOP
		);
	}
	resolution_frames.clear();
	return true;
}

} // namespace godot::duel_native_internal
