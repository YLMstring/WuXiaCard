#include "duel_native_compact_kernel_internal.h"

namespace godot {
using namespace duel_native_internal;

bool DuelNativeCompactKernel::draw_cards(
	NativeState &value,
	int32_t owner_id,
	int32_t source_cell,
	int32_t amount,
	const String &weapon_filter,
	const EventContext &draw_context,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	if (owner_id != 1 && owner_id != 2) return true;
	std::vector<int32_t> &hand = value.zones[owner_id - 1];
	std::vector<int32_t> &deck = value.zones[owner_id + 1];
	const Dictionary audiences_by_owner = value.side_payload.get("future_draw_reveal_audiences", Dictionary());
	const Variant audiences_value = audiences_by_owner.get(owner_id, Array());
	if (audiences_value.get_type() != Variant::ARRAY) {
		resolution.reason = "Future-draw reveal audiences are not an Array";
		return false;
	}
	const Array reveal_audiences = audiences_value;
	for (int32_t draw_index = 0; draw_index < amount; ++draw_index) {
		if (hand.size() >= 5) break;
		int32_t card_index = -1;
		if (!weapon_filter.is_empty()) {
			auto matching = std::find_if(deck.begin(), deck.end(), [&](const int32_t candidate) {
				if (
					candidate < 0
					|| candidate >= static_cast<int32_t>(value.card_template_indices.size())
				) return false;
				const int32_t template_index = value.card_template_indices[candidate];
				if (template_index < 0 || template_index >= value.card_template_pool.size()) return false;
				const Variant template_value = value.card_template_pool[template_index];
				if (template_value.get_type() != Variant::DICTIONARY) return false;
				return String(Dictionary(template_value).get("weapon", String())) == weapon_filter;
			});
			if (matching == deck.end()) break;
			card_index = *matching;
			deck.erase(matching);
		} else if (!deck.empty()) {
			card_index = deck.front();
			deck.erase(deck.begin());
		} else {
			if (
				value.empty_deck_draw_prototype_index < 0
				|| value.empty_deck_draw_prototype_index
					>= static_cast<int32_t>(value.fresh_card_prototypes.size())
			) {
				resolution.reason = "Draw has no generated empty-deck fallback prototype";
				return false;
			}
			const StringName fallback_id = value.fresh_card_prototypes[
				value.empty_deck_draw_prototype_index
			].card_id;
			String append_reason;
			card_index = append_fresh_board_card(
				value,
				fallback_id,
				make_generated_instance_id(value, fallback_id),
				owner_id,
				append_reason
			);
			if (card_index < 0) {
				resolution.reason = append_reason;
				return false;
			}
		}
		const int32_t slot = leftmost_empty_hand_slot(value, owner_id);
		if (slot < 0) break;
		const int32_t previous_hand_size = static_cast<int32_t>(hand.size());
		value.card_runtime_flags[card_index] |= static_cast<uint8_t>(1 << 7);
		value.card_hand_slots[card_index] = slot;
		hand.push_back(card_index);
		const int32_t logical_hand_index = static_cast<int32_t>(hand.size()) - 1;
		Dictionary event;
		event["type"] = StringName("card_drawn");
		event["source_cell"] = source_cell;
		event["owner_id"] = owner_id;
		event["card_id"] = value.card_ids[card_index];
		event["instance_id"] = value.card_instance_ids[card_index];
		event["logical_hand_index"] = logical_hand_index;
		event["hand_slot_index"] = slot;
		if (include_presentation_payloads) {
			event["card"] = restore_runtime_card(value, card_index);
		}
		resolution.events.append(event);
		for (int64_t audience_index = 0; audience_index < reveal_audiences.size(); ++audience_index) {
			const Variant observer_value = reveal_audiences[audience_index];
			if (observer_value.get_type() != Variant::INT) {
				resolution.reason = "Future-draw reveal audience is not an owner integer";
				return false;
			}
			const int32_t observer_owner = static_cast<int32_t>(static_cast<int64_t>(observer_value));
			if (observer_owner != 1 && observer_owner != 2) continue;
			uint8_t &reveal_code = value.card_reveal_codes[card_index];
			const bool already_revealed = (
				(observer_owner == 1 && (reveal_code == 1 || reveal_code == 3 || reveal_code == 4))
				|| (observer_owner == 2 && (reveal_code == 2 || reveal_code == 3 || reveal_code == 4))
			);
			if (already_revealed) continue;
			if (observer_owner == 1) reveal_code = reveal_code == 2 ? 4 : 1;
			else reveal_code = reveal_code == 1 ? 3 : 2;
			Dictionary revealed;
			revealed["type"] = StringName("card_revealed");
			revealed["source_cell"] = source_cell;
			revealed["owner_id"] = owner_id;
			revealed["observer_owner_id"] = observer_owner;
			revealed["card_id"] = value.card_ids[card_index];
			revealed["instance_id"] = value.card_instance_ids[card_index];
			revealed["logical_hand_index"] = logical_hand_index;
			resolution.events.append(revealed);
		}

		Resolution hand_change = resolve_difficulty_hand_change(
			value,
			owner_id,
			previous_hand_size,
			static_cast<int32_t>(hand.size()),
			source_cell,
			exile_stack
		);
		if (!hand_change.supported) {
			resolution.reason = hand_change.reason;
			return false;
		}
		append_resolution(resolution, hand_change);

		EventContext after_draw_context = draw_context;
		after_draw_context.trigger_cell = -1;
		after_draw_context.trigger_card_index = card_index;
		after_draw_context.trigger_owner = owner_id;
		after_draw_context.trigger_previous_owner = owner_id;
		after_draw_context.trigger_zone = 1;
		after_draw_context.trigger_logical_index = logical_hand_index;
		after_draw_context.trigger_was_on_board = false;
		Resolution after_drawn = resolve_event(
			value,
			StringName("card_after_drawn"),
			after_draw_context,
			exile_stack
		);
		if (!after_drawn.supported) {
			resolution.reason = after_drawn.reason;
			return false;
		}
		append_resolution(resolution, after_drawn);
	}
	return true;
}

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::resolve_difficulty_hand_change(
	NativeState &value,
	int32_t owner_id,
	int32_t previous_size,
	int32_t current_size,
	int32_t source_cell,
	std::vector<int32_t> &exile_stack
) const {
	Resolution resolution;
	if (
		owner_id != 2
		|| previous_size == current_size
		|| current_size != 1
		|| value.scalars[11] != 0
		|| value.scalars[10] < 8
	) return resolution;
	value.scalars[11] = 1;
	const std::vector<int32_t> &hand = value.zones[1];
	if (hand.empty()) return resolution;
	const int32_t source_card_index = hand.front();
	EventContext context;
	context.ability_source_cell = -1;
	context.ability_source_zone = 1;
	context.ability_source_logical_index = 0;
	context.ability_source_card_index = source_card_index;
	context.ability_source_owner = owner_id;
	if (!draw_cards(value, owner_id, source_cell, 1, String(), context, exile_stack, resolution)) {
		resolution.supported = false;
	}
	return resolution;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::discard_locked_cards(
	NativeState &value,
	const EventGroup &group,
	const std::vector<int32_t> &locked_card_indices,
	const EventContext &event_context,
	const ActionContext &action_context,
	ActionExecutionState &execution_state,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	execution_state.last_discard_batch_size = 0;
	struct DiscardRecord {
		int32_t card_index = -1;
		int32_t logical_hand_index = -1;
		int32_t hand_slot_index = -1;
	};
	std::vector<int32_t> candidates;
	int32_t owner_id = 0;
	for (const int32_t card_index : locked_card_indices) {
		int32_t zone = -1;
		int32_t candidate_owner = 0;
		int32_t logical_index = -1;
		if (!locate_card(value, card_index, zone, candidate_owner, logical_index) || zone != 1) continue;
		if (owner_id == 0) owner_id = candidate_owner;
		if (candidate_owner != owner_id) continue;
		candidates.push_back(card_index);
	}
	if (owner_id < 1 || owner_id > 2 || candidates.empty()) return ActionOutcome::NO_EFFECT;

	std::vector<int32_t> &hand = value.zones[owner_id - 1];
	std::vector<int32_t> &discard_pile = value.zones[owner_id + 3];
	const int32_t previous_hand_size = static_cast<int32_t>(hand.size());
	const int32_t discard_size_before = static_cast<int32_t>(discard_pile.size());
	const StringName source_instance_id = (
		action_context.ability_source_card_index >= 0
		? value.card_instance_ids[action_context.ability_source_card_index]
		: StringName()
	);
	const StringName batch_id = StringName(
		String("discard:")
		+ String(source_instance_id)
		+ ":" + String::num_int64(owner_id)
		+ ":" + String::num_int64(value.scalars[1])
		+ ":" + String::num_int64(discard_size_before)
	);
	std::vector<DiscardRecord> records;
	std::vector<int32_t> discarded_slots;
	for (const int32_t card_index : candidates) {
		int32_t zone = -1;
		int32_t current_owner = 0;
		int32_t logical_index = -1;
		if (
			!locate_card(value, card_index, zone, current_owner, logical_index)
			|| zone != 1
			|| current_owner != owner_id
			|| logical_index < 0
			|| logical_index >= static_cast<int32_t>(hand.size())
			|| hand[logical_index] != card_index
		) continue;
		DiscardRecord record;
		record.card_index = card_index;
		record.logical_hand_index = logical_index;
		record.hand_slot_index = value.card_hand_slots[card_index] >= 0
			? value.card_hand_slots[card_index]
			: logical_index;
		hand.erase(hand.begin() + logical_index);
		value.card_runtime_flags[card_index] &= static_cast<uint8_t>(~(1 << 7));
		value.card_hand_slots[card_index] = -1;
		discard_pile.push_back(card_index);
		records.push_back(record);
		discarded_slots.push_back(record.hand_slot_index);
	}
	execution_state.last_discard_batch_size = static_cast<int32_t>(records.size());
	if (records.empty()) return ActionOutcome::NO_EFFECT;

	int32_t source_cell = find_board_card(
		value,
		action_context.ability_source_card_index,
		action_context.ability_source_cell
	);
	if (source_cell < 0) source_cell = execution_state.current_source_cell;
	execution_state.current_source_cell = source_cell;
	for (const DiscardRecord &record : records) {
		Dictionary discarded;
		discarded["type"] = StringName("card_discarded");
		discarded["source_cell"] = source_cell;
		discarded["source_instance_id"] = source_instance_id;
		discarded["owner_id"] = owner_id;
		discarded["instance_id"] = value.card_instance_ids[record.card_index];
		discarded["zone"] = StringName("hand");
		discarded["logical_hand_index"] = record.logical_hand_index;
		discarded["hand_slot_index"] = record.hand_slot_index;
		discarded["discard_batch_id"] = batch_id;
		discarded["discard_batch_size"] = static_cast<int32_t>(records.size());
		if (include_presentation_payloads) {
			discarded["card"] = restore_runtime_card(value, record.card_index);
		}
		resolution.events.append(discarded);
	}

	std::sort(discarded_slots.begin(), discarded_slots.end());
	struct SlotMove {
		int32_t card_index = -1;
		int32_t from_slot = -1;
		int32_t to_slot = -1;
	};
	std::vector<SlotMove> slot_moves;
	for (const int32_t card_index : hand) {
		const int32_t from_slot = value.card_hand_slots[card_index];
		if (from_slot < 0) continue;
		const int32_t removed_before = static_cast<int32_t>(std::count_if(
			discarded_slots.begin(),
			discarded_slots.end(),
			[&](int32_t discarded_slot) { return discarded_slot < from_slot; }
		));
		const int32_t to_slot = from_slot - removed_before;
		if (to_slot == from_slot) continue;
		slot_moves.push_back({card_index, from_slot, to_slot});
		value.card_hand_slots[card_index] = to_slot;
	}
	std::sort(slot_moves.begin(), slot_moves.end(), [](const SlotMove &left, const SlotMove &right) {
		return left.from_slot < right.from_slot;
	});
	if (!slot_moves.empty()) {
		Array moves;
		for (const SlotMove &move : slot_moves) {
			Dictionary move_payload;
			move_payload["instance_id"] = value.card_instance_ids[move.card_index];
			move_payload["from_slot"] = move.from_slot;
			move_payload["to_slot"] = move.to_slot;
			moves.append(move_payload);
		}
		Dictionary shifted;
		shifted["type"] = StringName("hand_cards_shifted");
		shifted["source_cell"] = source_cell;
		shifted["source_instance_id"] = source_instance_id;
		shifted["owner_id"] = owner_id;
		shifted["moves"] = moves;
		resolution.events.append(shifted);
	}
	Resolution hand_change = resolve_difficulty_hand_change(
		value,
		owner_id,
		previous_hand_size,
		static_cast<int32_t>(hand.size()),
		source_cell,
		exile_stack
	);
	if (!hand_change.supported) {
		resolution.reason = hand_change.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	append_resolution(resolution, hand_change);

	for (const DiscardRecord &record : records) {
		int32_t trigger_zone = -1;
		int32_t trigger_owner = 0;
		int32_t trigger_logical_index = -1;
		if (!locate_card(
			value,
			record.card_index,
			trigger_zone,
			trigger_owner,
			trigger_logical_index
		)) continue;
		EventContext discard_context = event_context;
		discard_context.ability_source_cell = action_context.ability_source_cell;
		discard_context.ability_source_zone = action_context.ability_source_zone;
		discard_context.ability_source_logical_index = action_context.ability_source_logical_index;
		discard_context.ability_source_card_index = action_context.ability_source_card_index;
		discard_context.ability_source_owner = action_context.ability_source_owner;
		discard_context.trigger_cell = -1;
		discard_context.trigger_card_index = record.card_index;
		discard_context.trigger_owner = owner_id;
		discard_context.trigger_zone = trigger_zone;
		discard_context.trigger_logical_index = trigger_logical_index;
		discard_context.discard_owner = owner_id;
		discard_context.discard_batch_id = batch_id;
		discard_context.discard_batch_size = static_cast<int32_t>(records.size());
		Resolution after_discard = resolve_event(
			value,
			StringName("card_after_discarded"),
			discard_context,
			exile_stack
		);
		if (!after_discard.supported) {
			resolution.reason = after_discard.reason;
			return ActionOutcome::UNSUPPORTED;
		}
		resolution.events.append_array(after_discard.events);
		resolution.captures.append_array(after_discard.captures);
		resolution.exiles.append_array(after_discard.exiles);
	}

	EventContext batch_context;
	batch_context.ability_source_cell = action_context.ability_source_cell;
	batch_context.ability_source_zone = action_context.ability_source_zone;
	batch_context.ability_source_logical_index = action_context.ability_source_logical_index;
	batch_context.ability_source_card_index = action_context.ability_source_card_index;
	batch_context.ability_source_owner = action_context.ability_source_owner;
	batch_context.discard_owner = owner_id;
	batch_context.discard_batch_id = batch_id;
	batch_context.discard_batch_size = static_cast<int32_t>(records.size());
	Resolution batch_finished = resolve_event(
		value,
		StringName("discard_batch_finished"),
		batch_context,
		exile_stack
	);
	if (!batch_finished.supported) {
		resolution.reason = batch_finished.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	resolution.events.append_array(batch_finished.events);
	resolution.captures.append_array(batch_finished.captures);
	resolution.exiles.append_array(batch_finished.exiles);
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::transform_card(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	const ActionExecutionState &execution_state,
	Resolution &resolution
) const {
	int32_t target = -1;
	if (action.card_ref == CardRefOpcode::SELECTED_CARD) target = action_context.selected_card_index;
	else if (action.card_ref == CardRefOpcode::TRIGGER_CARD) target = event_context.trigger_card_index;
	else if (action.card_ref == CardRefOpcode::ABILITY_SOURCE) target = action_context.ability_source_card_index;
	else if (action.card_ref == CardRefOpcode::ATTACKER_CARD) target = event_context.attacker_card_index;
	else return ActionOutcome::UNSUPPORTED;
	if (target < 0) return ActionOutcome::NO_EFFECT;

	const FreshCardPrototype *prototype = nullptr;
	for (const FreshCardPrototype &candidate : value.fresh_card_prototypes) {
		if (candidate.card_id == action.card_id) {
			prototype = &candidate;
			break;
		}
	}
	if (prototype == nullptr) {
		resolution.reason = "Transform target has no reachable fresh-card prototype";
		return ActionOutcome::UNSUPPORTED;
	}
	if (
		prototype->active_ability_set_index < 0
		|| prototype->active_ability_set_index >= static_cast<int32_t>(compiled_ability_sets.size())
		|| !compiled_ability_sets[prototype->active_ability_set_index].declaration_valid
	) {
		resolution.reason = "Transform target has an invalid compiled ability set";
		return ActionOutcome::UNSUPPORTED;
	}

	int32_t zone = -1;
	int32_t owner_id = 0;
	int32_t logical_index = -1;
	if (!locate_card(value, target, zone, owner_id, logical_index)) return ActionOutcome::NO_EFFECT;
	const StringName old_card_id = value.card_ids[target];
	value.card_template_indices[target] = prototype->template_index;
	value.card_ids[target] = prototype->card_id;
	for (int32_t direction = 0; direction < 4; ++direction) {
		value.card_powers[target * 4 + direction] = prototype->powers[direction];
	}
	value.card_ki[target] = prototype->ki;
	value.card_active_ability_set_indices[target] = prototype->active_ability_set_index;
	value.card_runtime_abilities[target].clear();
	for (const int32_t compiled_ability_index : compiled_ability_sets[prototype->active_ability_set_index].ability_pool_indices) {
		RuntimeAbilityEntry entry;
		entry.compiled_ability_index = compiled_ability_index;
		entry.handle = value.next_ability_handle++;
		value.card_runtime_abilities[target].push_back(entry);
	}
	clear_runtime_suppression(value, target);
	uint8_t &reveal_code = value.card_reveal_codes[target];
	if (owner_id == 1 && reveal_code == 0) reveal_code = 1;
	else if (owner_id == 1 && reveal_code == 2) reveal_code = 4;
	else if (owner_id == 2 && reveal_code == 0) reveal_code = 2;
	else if (owner_id == 2 && reveal_code == 1) reveal_code = 3;

	Dictionary transformed;
	transformed["type"] = StringName("card_transformed");
	transformed["source_cell"] = execution_state.current_source_cell;
	transformed["source_instance_id"] = (
		action_context.ability_source_card_index >= 0
		? value.card_instance_ids[action_context.ability_source_card_index]
		: StringName()
	);
	transformed["target_cell"] = zone == 0 ? logical_index : -1;
	transformed["owner_id"] = owner_id;
	transformed["zone"] = (
		zone == 0 ? StringName("board")
		: (zone == 1 ? StringName("hand")
		: (zone == 2 ? StringName("deck")
		: (zone == 3 ? StringName("discard") : StringName("removed"))))
	);
	transformed["logical_index"] = logical_index;
	transformed["instance_id"] = value.card_instance_ids[target];
	transformed["old_card_id"] = old_card_id;
	transformed["card_id"] = prototype->card_id;
	if (include_presentation_payloads) {
		transformed["card"] = restore_runtime_card(value, target);
	}
	resolution.events.append(transformed);
	return ActionOutcome::APPLIED;
}

void DuelNativeCompactKernel::remove_ability_with_event(
	NativeState &value,
	int32_t card_index,
	uint64_t ability_handle,
	int32_t source_cell,
	int32_t source_card_index,
	int32_t target_cell,
	int32_t owner_id,
	Array &events
) const {
	const int32_t ability_index = find_runtime_ability_index(
		value,
		card_index,
		ability_handle
	);
	if (ability_index < 0) return;
	std::vector<RuntimeAbilityEntry> &entries = value.card_runtime_abilities[card_index];
	entries.erase(entries.begin() + ability_index);
	Dictionary event;
	event["type"] = StringName("ability_lost");
	event["source_instance_id"] = source_card_index >= 0 ? value.card_instance_ids[source_card_index] : StringName();
	event["source_cell"] = source_cell;
	event["target_cell"] = target_cell;
	event["owner_id"] = owner_id;
	event["instance_id"] = value.card_instance_ids[card_index];
	events.append(event);
}

void DuelNativeCompactKernel::clear_runtime_suppression(
	NativeState &value,
	int32_t card_index
) const {
	if (
		card_index < 0
		|| card_index >= static_cast<int32_t>(value.card_runtime_suppression_batches.size())
	) return;
	value.card_runtime_suppression_batches[card_index].clear();
	value.card_runtime_flags[card_index] &= static_cast<uint8_t>(~(1 << 6));
	value.card_suppression_set_indices[card_index] = -1;
}

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::consume_pending_hand_play_suppression(
	NativeState &value,
	int32_t card_index,
	int32_t owner_id,
	int32_t cell
) const {
	Resolution resolution;
	if (
		owner_id < 1
		|| owner_id > 2
		|| card_index < 0
		|| card_index >= static_cast<int32_t>(value.card_runtime_abilities.size())
		|| card_is_heart_method(value, card_index)
	) return resolution;
	const int32_t scalar_index = owner_id == 1 ? 8 : 9;
	if (value.scalars[scalar_index] <= 0) return resolution;
	value.scalars[scalar_index] -= 1;

	Dictionary consumed;
	consumed["type"] = StringName("non_retained_suppression_consumed");
	consumed["source_cell"] = cell;
	consumed["target_cell"] = cell;
	consumed["owner_id"] = owner_id;
	consumed["instance_id"] = value.card_instance_ids[card_index];
	consumed["pending_count"] = value.scalars[scalar_index];
	resolution.events.append(consumed);

	std::vector<RuntimeAbilityEntry> retained_entries;
	retained_entries.reserve(value.card_runtime_abilities[card_index].size());
	for (const RuntimeAbilityEntry &entry : value.card_runtime_abilities[card_index]) {
		const bool retained = (
			entry.compiled_ability_index >= 0
			&& entry.compiled_ability_index < static_cast<int32_t>(compiled_ability_pool.size())
			&& compiled_ability_pool[entry.compiled_ability_index].retained_on_flip
		);
		if (retained) {
			retained_entries.push_back(entry);
			continue;
		}
		Dictionary lost;
		lost["type"] = StringName("ability_lost");
		lost["source_instance_id"] = StringName();
		lost["source_cell"] = cell;
		lost["target_cell"] = cell;
		lost["owner_id"] = owner_id;
		lost["instance_id"] = value.card_instance_ids[card_index];
		lost["zone"] = StringName("board");
		lost["logical_index"] = cell;
		lost["permanent"] = true;
		resolution.events.append(lost);
	}
	value.card_runtime_abilities[card_index] = retained_entries;
	clear_runtime_suppression(value, card_index);
	return resolution;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::temporarily_remove_non_retained_abilities(
	NativeState &value,
	const ActionContext &action_context,
	int32_t source_cell,
	Resolution &resolution
) const {
	const int32_t card_index = action_context.action_subject_card_index;
	if (
		card_index < 0
		|| card_index >= static_cast<int32_t>(value.card_runtime_abilities.size())
	) return ActionOutcome::NO_EFFECT;
	int32_t zone = -1;
	int32_t owner_id = 0;
	int32_t logical_index = -1;
	if (
		!locate_card(value, card_index, zone, owner_id, logical_index)
		|| owner_id != action_context.action_subject_owner
	) return ActionOutcome::NO_EFFECT;

	RuntimeSuppressionBatch batch;
	batch.expires_after_turn = value.scalars[2];
	std::vector<RuntimeAbilityEntry> retained_entries;
	const std::vector<RuntimeAbilityEntry> active_entries = value.card_runtime_abilities[card_index];
	retained_entries.reserve(active_entries.size());
	for (size_t ability_index = 0; ability_index < active_entries.size(); ++ability_index) {
		const RuntimeAbilityEntry &entry = active_entries[ability_index];
		const bool retained = (
			entry.compiled_ability_index >= 0
			&& entry.compiled_ability_index < static_cast<int32_t>(compiled_ability_pool.size())
			&& compiled_ability_pool[entry.compiled_ability_index].retained_on_flip
		);
		if (retained) {
			retained_entries.push_back(entry);
			continue;
		}
		RuntimeSuppressionEntry suppressed_entry;
		suppressed_entry.original_index = static_cast<int32_t>(ability_index);
		suppressed_entry.compiled_ability_index = entry.compiled_ability_index;
		suppressed_entry.handle = entry.handle;
		batch.entries.push_back(suppressed_entry);

		const int32_t cell = zone == 0 ? logical_index : -1;
		Dictionary lost;
		lost["type"] = StringName("ability_lost");
		lost["source_instance_id"] = (
			action_context.ability_source_card_index >= 0
			&& action_context.ability_source_card_index
				< static_cast<int32_t>(value.card_instance_ids.size())
			? value.card_instance_ids[action_context.ability_source_card_index]
			: StringName()
		);
		lost["source_cell"] = source_cell;
		lost["target_cell"] = cell;
		lost["owner_id"] = owner_id;
		lost["instance_id"] = value.card_instance_ids[card_index];
		lost["zone"] = (
			zone == 0 ? StringName("board")
			: (zone == 1 ? StringName("hand")
			: (zone == 2 ? StringName("deck")
			: (zone == 3 ? StringName("discard") : StringName("removed"))))
		);
		lost["logical_index"] = logical_index;
		lost["temporary"] = true;
		resolution.events.append(lost);
	}
	if (batch.entries.empty()) return ActionOutcome::NO_EFFECT;
	value.card_runtime_abilities[card_index] = retained_entries;
	value.card_runtime_suppression_batches[card_index].push_back(batch);
	value.card_runtime_flags[card_index] |= static_cast<uint8_t>(1 << 6);
	value.card_suppression_set_indices[card_index] = -1;
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::restore_temporary_abilities(
	NativeState &value,
	int32_t completed_turn
) const {
	Resolution resolution;
	auto restore_card = [&](
		int32_t card_index,
		int32_t owner_id,
		const StringName &zone,
		int32_t logical_index
	) {
		if (
			card_index < 0
			|| card_index >= static_cast<int32_t>(value.card_runtime_suppression_batches.size())
		) return;
		const std::vector<RuntimeSuppressionBatch> batches =
			value.card_runtime_suppression_batches[card_index];
		if (batches.empty()) return;
		std::vector<RuntimeSuppressionBatch> remaining_batches;
		for (int32_t batch_index = static_cast<int32_t>(batches.size()) - 1; batch_index >= 0; --batch_index) {
			const RuntimeSuppressionBatch &batch = batches[batch_index];
			if (batch.expires_after_turn > completed_turn) {
				remaining_batches.insert(remaining_batches.begin(), batch);
				continue;
			}
			std::vector<RuntimeSuppressionEntry> entries = batch.entries;
			std::sort(entries.begin(), entries.end(), [](const RuntimeSuppressionEntry &left, const RuntimeSuppressionEntry &right) {
				return left.original_index < right.original_index;
			});
			std::vector<RuntimeAbilityEntry> &active = value.card_runtime_abilities[card_index];
			for (const RuntimeSuppressionEntry &entry : entries) {
				const int32_t insert_index = std::clamp(
					entry.original_index,
					0,
					static_cast<int32_t>(active.size())
				);
				RuntimeAbilityEntry restored_entry;
				restored_entry.compiled_ability_index = entry.compiled_ability_index;
				restored_entry.handle = entry.handle;
				active.insert(active.begin() + insert_index, restored_entry);

				const int32_t cell = zone == StringName("board") ? logical_index : -1;
				Dictionary gained;
				gained["type"] = StringName("ability_gained");
				gained["source_cell"] = cell;
				gained["target_cell"] = cell;
				gained["owner_id"] = owner_id;
				gained["instance_id"] = value.card_instance_ids[card_index];
				gained["zone"] = zone;
				gained["logical_index"] = logical_index;
				gained["temporary"] = true;
				resolution.events.append(gained);
			}
		}
		value.card_runtime_suppression_batches[card_index] = remaining_batches;
		if (remaining_batches.empty()) {
			clear_runtime_suppression(value, card_index);
		} else {
			value.card_runtime_flags[card_index] |= static_cast<uint8_t>(1 << 6);
		}
	};

	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		const int32_t card_index = value.board_card_indices[cell];
		if (card_index < 0) continue;
		restore_card(
			card_index,
			value.board_owners[cell],
			StringName("board"),
			static_cast<int32_t>(cell)
		);
	}
	for (int32_t owner_id : {1, 2}) {
		const std::array<std::pair<int32_t, StringName>, 4> zones = {{
			{owner_id - 1, StringName("hand")},
			{owner_id + 1, StringName("deck")},
			{owner_id + 3, StringName("discard")},
			{owner_id + 5, StringName("removed")},
		}};
		for (const auto &zone_entry : zones) {
			const std::vector<int32_t> &cards = value.zones[zone_entry.first];
			for (size_t logical_index = 0; logical_index < cards.size(); ++logical_index) {
				restore_card(
					cards[logical_index],
					owner_id,
					zone_entry.second,
					static_cast<int32_t>(logical_index)
				);
			}
		}
	}
	return resolution;
}

Array DuelNativeCompactKernel::materialize_suppression_batches(
	const NativeState &value,
	int32_t card_index
) const {
	Array batches;
	if (
		card_index < 0
		|| card_index >= static_cast<int32_t>(value.card_runtime_suppression_batches.size())
	) return batches;
	for (const RuntimeSuppressionBatch &batch : value.card_runtime_suppression_batches[card_index]) {
		Array entries;
		for (const RuntimeSuppressionEntry &entry : batch.entries) {
			if (
				entry.compiled_ability_index < 0
				|| entry.compiled_ability_index >= static_cast<int32_t>(ability_declaration_pool.size())
			) continue;
			Dictionary materialized_entry;
			materialized_entry["index"] = entry.original_index;
			materialized_entry["ability"] = ability_declaration_pool[entry.compiled_ability_index];
			entries.append(materialized_entry);
		}
		Dictionary materialized_batch;
		materialized_batch["expires_after_turn"] = batch.expires_after_turn;
		materialized_batch["entries"] = entries;
		batches.append(materialized_batch);
	}
	return batches;
}

bool DuelNativeCompactKernel::resolve_selector_source(
	const NativeState &value,
	const ActionContext &context,
	int32_t &zone,
	int32_t &owner,
	int32_t &logical_index
) const {
	int32_t live_zone = -1;
	int32_t live_owner = 0;
	int32_t live_index = -1;
	if (
		locate_card(
			value,
			context.ability_source_card_index,
			live_zone,
			live_owner,
			live_index
		)
		&& live_zone != 2
		&& live_zone != 4
	) {
		zone = live_zone;
		owner = live_owner;
		logical_index = live_index;
		return true;
	}
	if (context.ability_source_owner != 1 && context.ability_source_owner != 2) return false;
	zone = context.ability_source_zone;
	owner = context.ability_source_owner;
	logical_index = context.ability_source_logical_index;
	return zone >= 0;
}

bool DuelNativeCompactKernel::action_declarations_can_spend_ki(const Variant &value) const {
	if (value.get_type() != Variant::ARRAY) return false;
	const Array actions = value;
	for (int64_t index = 0; index < actions.size(); ++index) {
		const Variant action_value = actions[index];
		if (action_value.get_type() != Variant::DICTIONARY) continue;
		const Dictionary action = action_value;
		const StringName type = action.get("type", StringName());
		if (type == StringName("spend_ki")) return true;
		if (action_declarations_can_spend_ki(action.get("actions", Variant()))) return true;
	}
	return false;
}

bool DuelNativeCompactKernel::card_declarations_can_spend_ki(
	const NativeState &value,
	int32_t card_index
) const {
	if (card_index < 0 || card_index >= static_cast<int32_t>(value.card_runtime_abilities.size())) return false;
	for (const RuntimeAbilityEntry &entry : value.card_runtime_abilities[card_index]) {
		if (
			entry.compiled_ability_index < 0
			|| entry.compiled_ability_index >= static_cast<int32_t>(ability_declaration_pool.size())
			|| ability_declaration_pool[entry.compiled_ability_index].get_type() != Variant::DICTIONARY
		) continue;
		const Dictionary ability = ability_declaration_pool[entry.compiled_ability_index];
		const Variant activation_value = ability.get("activation", Variant());
		if (activation_value.get_type() == Variant::DICTIONARY) {
			const Dictionary activation = activation_value;
			if (
				action_declarations_can_spend_ki(activation.get("costs", Variant()))
				|| action_declarations_can_spend_ki(activation.get("actions", Variant()))
			) return true;
		}
		const Variant triggers_value = ability.get("triggers", Variant());
		if (triggers_value.get_type() != Variant::ARRAY) continue;
		const Array triggers = triggers_value;
		for (int64_t trigger_index = 0; trigger_index < triggers.size(); ++trigger_index) {
			if (triggers[trigger_index].get_type() != Variant::DICTIONARY) continue;
			const Dictionary trigger = triggers[trigger_index];
			if (action_declarations_can_spend_ki(trigger.get("actions", Variant()))) return true;
		}
	}
	return false;
}

bool DuelNativeCompactKernel::card_is_heart_method(
	const NativeState &value,
	int32_t card_index
) const {
	if (
		card_index < 0
		|| card_index >= static_cast<int32_t>(value.card_template_indices.size())
	) return false;
	const int32_t template_index = value.card_template_indices[card_index];
	if (template_index < 0 || template_index >= value.card_template_pool.size()) return false;
	const Variant template_value = value.card_template_pool[template_index];
	if (template_value.get_type() != Variant::DICTIONARY) return false;
	const Dictionary card_template = template_value;
	return String(card_template.get("weapon", String())) == String::utf8("心法");
}

bool DuelNativeCompactKernel::selector_conditions_match(
	const NativeState &value,
	int32_t candidate_card_index,
	int32_t candidate_zone,
	int32_t candidate_owner,
	int32_t candidate_logical_index,
	const CompiledSelector &selector,
	const ActionContext &context,
	bool &supported
) const {
	supported = true;
	if (!selector.declaration_valid || candidate_card_index < 0) {
		supported = false;
		return false;
	}
	int32_t source_zone = -1;
	int32_t source_owner = 0;
	int32_t source_index = -1;
	if (!resolve_selector_source(value, context, source_zone, source_owner, source_index)) return false;
	for (const CompiledSelectorCondition &condition : selector.conditions) {
		bool matched = false;
		switch (condition.opcode) {
			case SelectorConditionOpcode::IS_ALLY:
				matched = candidate_owner == source_owner;
				break;
			case SelectorConditionOpcode::IS_ENEMY:
				matched = candidate_owner != source_owner;
				break;
			case SelectorConditionOpcode::WEAPON_IS: {
				const int32_t template_index = value.card_template_indices[candidate_card_index];
				if (template_index < 0 || template_index >= value.card_template_pool.size()) break;
				const Dictionary card_template = value.card_template_pool[template_index];
				matched = String(card_template.get("weapon", String())) == condition.weapon;
				break;
			}
			case SelectorConditionOpcode::IS_NOT_SOURCE:
				matched = candidate_card_index != context.ability_source_card_index;
				break;
			case SelectorConditionOpcode::ADJACENT_TO_SOURCE:
				matched = (
					candidate_zone == 0 && source_zone == 0
					&& (
						neighbor_index(candidate_logical_index, 0) == source_index
						|| neighbor_index(candidate_logical_index, 1) == source_index
						|| neighbor_index(candidate_logical_index, 2) == source_index
						|| neighbor_index(candidate_logical_index, 3) == source_index
					)
				);
				break;
			case SelectorConditionOpcode::SURROUNDED_BY_ALLIES: {
				if (candidate_zone != 0 || source_zone != 0) break;
				int32_t neighbor_count = 0;
				matched = true;
				for (int32_t direction = 0; direction < 4; ++direction) {
					const int32_t cell = neighbor_index(candidate_logical_index, direction);
					if (cell < 0) continue;
					++neighbor_count;
					if (value.board_card_indices[cell] < 0 || value.board_owners[cell] != source_owner) {
						matched = false;
						break;
					}
				}
				matched = matched && neighbor_count > 0;
				break;
			}
			case SelectorConditionOpcode::ORIGINAL_OWNER_IS_SELF:
				matched = value.card_original_owners[candidate_card_index] == source_owner;
				break;
			case SelectorConditionOpcode::ORIGINAL_OWNER_IS_ENEMY:
				matched = value.card_original_owners[candidate_card_index] != source_owner;
				break;
			case SelectorConditionOpcode::FLIPPED_BY_CURRENT_ATTACK:
				for (const EventContext::AttackFlipRecord &record : context.attack_flips) {
					if (record.card_index == candidate_card_index && record.previous_owner != source_owner) {
						matched = true;
						break;
					}
				}
				break;
			case SelectorConditionOpcode::POWERS_CAN_CHANGE:
				matched = can_change_powers(value, candidate_card_index);
				break;
			case SelectorConditionOpcode::HAS_NONZERO_POWER:
				for (int32_t direction = 0; direction < 4; ++direction) {
					if (value.card_powers[candidate_card_index * 4 + direction] != 0) {
						matched = true;
						break;
					}
				}
				break;
			case SelectorConditionOpcode::IS_PREVIOUS_HAND_PLAY: {
				int32_t played_by = 0;
				if (condition.relative_owner == RelativeOwnerOpcode::ABILITY_SOURCE) played_by = source_owner;
				else if (condition.relative_owner == RelativeOwnerOpcode::OPPONENT_OF_ABILITY_SOURCE) played_by = other_owner(source_owner);
				else {
					supported = false;
					return false;
				}
				const Dictionary records = value.side_payload.get("last_hand_play_by_owner", Dictionary());
				const Variant record_value = records.get(played_by, Dictionary());
				if (record_value.get_type() == Variant::DICTIONARY) {
					const Dictionary record = record_value;
					matched = (
						static_cast<int32_t>(static_cast<int64_t>(record.get("played_by_owner_id", 0))) == played_by
						&& StringName(record.get("instance_id", StringName())) == value.card_instance_ids[candidate_card_index]
					);
				}
				break;
			}
			case SelectorConditionOpcode::CAN_SPEND_KI:
				matched = (
					card_effects_enabled(value, candidate_card_index, candidate_owner)
					&& card_declarations_can_spend_ki(value, candidate_card_index)
				);
				break;
			case SelectorConditionOpcode::CAN_TRANSFER_RESOURCE: {
				auto has_resource = [&](ResourceOpcode resource) {
					if (resource == ResourceOpcode::KI) return value.card_ki[candidate_card_index] >= condition.amount;
					if (resource == ResourceOpcode::POWERS) {
						if (!can_change_powers(value, candidate_card_index)) return false;
						for (int32_t direction = 0; direction < 4; ++direction) {
							if (value.card_powers[candidate_card_index * 4 + direction] > 0) return true;
						}
						return false;
					}
					return false;
				};
				if (condition.resource == ResourceOpcode::UNSUPPORTED || condition.fallback_resource == ResourceOpcode::UNSUPPORTED) {
					supported = false;
					return false;
				}
				matched = has_resource(condition.resource) || has_resource(condition.fallback_resource);
				break;
			}
			default:
				supported = false;
				return false;
		}
		if (!matched) return false;
	}
	return true;
}

std::vector<int32_t> DuelNativeCompactKernel::snapshot_selected_cards(
	const NativeState &value,
	const CompiledSelector &selector,
	const ActionContext &context,
	bool &supported
) const {
	std::vector<int32_t> selected;
	supported = selector.declaration_valid;
	if (!supported) return selected;
	int32_t source_zone = -1;
	int32_t source_owner = 0;
	int32_t source_index = -1;
	if (!resolve_selector_source(value, context, source_zone, source_owner, source_index)) return selected;
	std::vector<uint8_t> observed(value.card_instance_ids.size(), 0);
	auto consider = [&](int32_t card_index, int32_t zone, int32_t owner, int32_t logical_index) {
		if (card_index < 0 || card_index >= static_cast<int32_t>(observed.size()) || observed[card_index] != 0) return false;
		observed[card_index] = 1;
		bool condition_supported = true;
		if (!selector_conditions_match(value, card_index, zone, owner, logical_index, selector, context, condition_supported)) {
			if (!condition_supported) supported = false;
			return false;
		}
		selected.push_back(card_index);
		return selector.limit > 0 && static_cast<int32_t>(selected.size()) >= selector.limit;
	};
	bool reached_limit = false;
	for (const SelectorZoneOpcode zone : selector.zones) {
		if (!supported || reached_limit) break;
		if (zone == SelectorZoneOpcode::BOARD) {
			for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
				const int32_t card_index = value.board_card_indices[cell];
				if (card_index >= 0 && consider(card_index, 0, value.board_owners[cell], static_cast<int32_t>(cell))) {
					reached_limit = true;
					break;
				}
			}
			continue;
		}
		const int32_t first_owner = source_owner;
		const int32_t second_owner = other_owner(source_owner);
		for (const int32_t owner : {first_owner, second_owner}) {
			if (!supported || reached_limit) break;
			int32_t zone_index = -1;
			int32_t zone_kind = -1;
			if (zone == SelectorZoneOpcode::HAND) {
				zone_index = owner - 1;
				zone_kind = 1;
			} else if (zone == SelectorZoneOpcode::DISCARD) {
				zone_index = owner + 3;
				zone_kind = 3;
			} else if (zone == SelectorZoneOpcode::REMOVED) {
				zone_index = owner + 5;
				zone_kind = 4;
			}
			if (zone_index < 0 || zone_index >= static_cast<int32_t>(value.zones.size())) continue;
			const std::vector<int32_t> &cards = value.zones[zone_index];
			std::vector<int32_t> logical_indices(cards.size());
			for (size_t index = 0; index < cards.size(); ++index) logical_indices[index] = static_cast<int32_t>(index);
			if (zone == SelectorZoneOpcode::HAND) {
				std::stable_sort(logical_indices.begin(), logical_indices.end(), [&](int32_t first, int32_t second) {
					const int32_t first_slot = value.card_hand_slots[cards[first]] >= 0 ? value.card_hand_slots[cards[first]] : first;
					const int32_t second_slot = value.card_hand_slots[cards[second]] >= 0 ? value.card_hand_slots[cards[second]] : second;
					return first_slot == second_slot ? first < second : first_slot < second_slot;
				});
				if (selector.hand_right_to_left) std::reverse(logical_indices.begin(), logical_indices.end());
			}
			for (const int32_t logical_index : logical_indices) {
				if (consider(cards[logical_index], zone_kind, owner, logical_index)) {
					reached_limit = true;
					break;
				}
			}
		}
	}
	if (selector.required_count > 0 && static_cast<int32_t>(selected.size()) != selector.required_count) {
		selected.clear();
	}
	return selected;
}

void DuelNativeCompactKernel::assign_power_change_batch(
	const NativeState &value,
	Resolution &resolution,
	int64_t first_event_index,
	const EventGroup &group,
	const CompiledAction &action,
	const ActionContext &context,
	int32_t action_index
) const {
	auto event_is_protected = [&](int64_t event_index) {
		for (const auto &range : resolution.protected_power_batch_ranges) {
			if (event_index >= range.first && event_index < range.second) return true;
		}
		return false;
	};
	bool has_power_change = false;
	for (int64_t index = first_event_index; index < resolution.events.size(); ++index) {
		if (event_is_protected(index)) continue;
		const Variant event_value = resolution.events[index];
		if (event_value.get_type() == Variant::DICTIONARY) {
			const Dictionary event = event_value;
			if (StringName(event.get("type", StringName())) == StringName("powers_changed")) {
			has_power_change = true;
			break;
			}
		}
	}
	if (!has_power_change) return;
	const String suffix = (
		action.power_change_batch_group.is_empty()
		? String::num_int64(action_index)
		: String(action.power_change_batch_group)
	);
	const StringName batch_id = StringName(
		String(value.card_instance_ids[group.source_card_index]) + "|"
		+ String(context.event_id.is_empty() ? StringName("direct") : context.event_id) + "|"
		+ String::num_int64(context.discovery_ability_index) + "|"
		+ String::num_int64(context.trigger_index) + "|" + suffix
	);
	for (int64_t index = first_event_index; index < resolution.events.size(); ++index) {
		if (event_is_protected(index)) continue;
		const Variant event_value = resolution.events[index];
		if (event_value.get_type() != Variant::DICTIONARY) continue;
		Dictionary event = event_value;
		const StringName type = event.get("type", StringName());
		if (type == StringName("powers_changed") || type == StringName("card_exiled")) {
			event["power_change_batch_id"] = batch_id;
		}
	}
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::change_powers(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	int32_t source_cell,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	int32_t target_card_index = -1;
	int32_t expected_owner = 0;
	if (action.card_ref == CardRefOpcode::SELECTED_CARD) {
		target_card_index = action_context.selected_card_index;
		expected_owner = action_context.selected_card_owner != 0
			? action_context.selected_card_owner
			: action_context.action_subject_owner;
	} else if (action.card_ref == CardRefOpcode::ABILITY_SOURCE) {
		target_card_index = action_context.ability_source_card_index;
		expected_owner = action_context.ability_source_owner;
	} else if (action.card_ref == CardRefOpcode::TRIGGER_CARD) {
		target_card_index = event_context.trigger_card_index;
		expected_owner = event_context.trigger_owner;
	} else if (action.card_ref == CardRefOpcode::ATTACKER_CARD) {
		target_card_index = event_context.attacker_card_index;
		expected_owner = event_context.attacker_owner;
	} else {
		return ActionOutcome::UNSUPPORTED;
	}
	int32_t zone = -1;
	int32_t owner = 0;
	int32_t logical_index = -1;
	if (
		target_card_index < 0
		|| !locate_card(value, target_card_index, zone, owner, logical_index)
		|| zone == 2
		|| (expected_owner != 0 && owner != expected_owner)
		|| !can_change_powers(value, target_card_index)
	) return ActionOutcome::NO_EFFECT;

	int32_t amount = action.amount;
	if (action.amount_is_hand_count) {
		int32_t count_owner = 0;
		if (action.amount_owner == RelativeOwnerOpcode::CARD_CURRENT) {
			count_owner = owner;
		} else if (action.amount_owner == RelativeOwnerOpcode::ABILITY_SOURCE) {
			int32_t source_zone = -1;
			int32_t source_index = -1;
			if (
				!locate_card(value, action_context.ability_source_card_index, source_zone, count_owner, source_index)
				|| source_zone == 2
			) return ActionOutcome::NO_EFFECT;
		} else {
			return ActionOutcome::UNSUPPORTED;
		}
		amount = static_cast<int32_t>(value.zones[count_owner - 1].size());
	}
	if (amount == 0) {
		return action.amount_is_hand_count ? ActionOutcome::NO_EFFECT : ActionOutcome::UNSUPPORTED;
	}
	Array previous_powers;
	Array resulting_powers;
	bool all_zero = true;
	for (int32_t direction = 0; direction < 4; ++direction) {
		const int32_t previous = value.card_powers[target_card_index * 4 + direction];
		const int32_t resulting = std::max(0, previous + amount);
		previous_powers.append(previous);
		resulting_powers.append(resulting);
		value.card_powers[target_card_index * 4 + direction] = resulting;
		all_zero = all_zero && resulting == 0;
	}
	Dictionary event;
	event["type"] = StringName("powers_changed");
	event["source_cell"] = source_cell;
	event["target_cell"] = zone == 0 ? logical_index : -1;
	event["owner_id"] = owner;
	event["instance_id"] = value.card_instance_ids[target_card_index];
	event["ability_source_instance_id"] = value.card_instance_ids[group.source_card_index];
	event["previous_powers"] = previous_powers;
	event["powers"] = resulting_powers;
	event["amount"] = amount;
	event["change_reason"] = StringName("change_powers");
	event["zone"] = zone == 0 ? StringName("board") : (zone == 1 ? StringName("hand") : (zone == 3 ? StringName("discard") : StringName("removed")));
	event["logical_index"] = logical_index;
	resolution.events.append(event);
	if (amount < 0 && all_zero) {
		if (!exile_card(
			value,
			target_card_index,
			source_cell,
			group.source_card_index,
			target_card_index == group.source_card_index,
			StringName("power_reached_zero"),
			event_context,
			exile_stack,
			resolution,
			action_context.record_direct_board_changes
		)) return ActionOutcome::UNSUPPORTED;
	}
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::change_ki(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	int32_t source_cell,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	(void)group;
	(void)source_cell;
	(void)exile_stack;
	int32_t target = action_context.action_subject_card_index;
	int32_t expected_owner = action_context.action_subject_owner;
	if (action.card_ref_explicit) {
		if (action.card_ref == CardRefOpcode::SELECTED_CARD) {
			target = action_context.selected_card_index;
			expected_owner = action_context.selected_card_owner != 0
				? action_context.selected_card_owner
				: action_context.action_subject_owner;
		} else if (action.card_ref == CardRefOpcode::ABILITY_SOURCE) {
			target = action_context.ability_source_card_index;
			expected_owner = action_context.ability_source_owner;
		} else if (action.card_ref == CardRefOpcode::TRIGGER_CARD) {
			target = event_context.trigger_card_index;
			expected_owner = event_context.trigger_owner;
		} else if (action.card_ref == CardRefOpcode::ATTACKER_CARD) {
			target = event_context.attacker_card_index;
			expected_owner = event_context.attacker_owner;
		} else return ActionOutcome::UNSUPPORTED;
	}
	int32_t zone = -1;
	int32_t owner = 0;
	int32_t logical_index = -1;
	if (
		target < 0 || !locate_card(value, target, zone, owner, logical_index) || zone == 2
		|| (expected_owner != 0 && owner != expected_owner)
	) return ActionOutcome::NO_EFFECT;
	const int32_t previous = value.card_ki[target];
	const int32_t delta = action.opcode == ActionOpcode::SPEND_KI ? -action.amount : action.amount;
	if (delta == 0 || previous + delta < 0) return ActionOutcome::NO_EFFECT;
	value.card_ki[target] = previous + delta;
	const int32_t current_cell = zone == 0 ? logical_index : -1;
	Dictionary event;
	event["type"] = StringName("ki_changed");
	event["source_cell"] = current_cell;
	event["target_cell"] = current_cell;
	event["owner_id"] = owner;
	event["instance_id"] = value.card_instance_ids[target];
	event["previous_ki"] = previous;
	event["ki"] = value.card_ki[target];
	event["change_reason"] = !action.change_reason.is_empty()
		? action.change_reason
		: (action.opcode == ActionOpcode::SPEND_KI ? StringName("spend_ki") : StringName("gain_ki"));
	event["zone"] = zone == 0 ? StringName("board") : (zone == 1 ? StringName("hand") : (zone == 3 ? StringName("discard") : StringName("removed")));
	event["logical_index"] = logical_index;
	resolution.events.append(event);
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::flip_action_subject(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	(void)event_context;
	const int32_t target = action_context.action_subject_card_index;
	const int32_t target_cell = find_board_card(value, target, action_context.action_subject_logical_index);
	if (target_cell < 0 || value.board_owners[target_cell] != action_context.action_subject_owner) return ActionOutcome::NO_EFFECT;
	int32_t new_owner = 0;
	if (action.new_owner == RelativeOwnerOpcode::ABILITY_SOURCE) new_owner = action_context.ability_source_owner;
	else if (action.new_owner == RelativeOwnerOpcode::OPPONENT_OF_ABILITY_SOURCE) new_owner = other_owner(action_context.ability_source_owner);
	else return ActionOutcome::UNSUPPORTED;
	if (new_owner == value.board_owners[target_cell]) return ActionOutcome::NO_EFFECT;
	EventContext flip_context;
	flip_context.trigger_cell = target_cell;
	flip_context.trigger_card_index = target;
	flip_context.trigger_owner = value.board_owners[target_cell];
	flip_context.trigger_was_on_board = true;
	flip_context.new_owner = new_owner;
	flip_context.flip_reason = StringName("ability_non_attack_flip");
	Resolution before = resolve_event(value, StringName("card_before_flipped"), flip_context, exile_stack);
	if (!before.supported) {
		resolution.reason = before.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	resolution.events.append_array(before.events);
	resolution.captures.append_array(before.captures);
	resolution.exiles.append_array(before.exiles);
	if (before.flip_prevented) {
		Dictionary prevented;
		prevented["type"] = StringName("card_flip_prevented");
		prevented["source_cell"] = -1;
		prevented["target_cell"] = target_cell;
		prevented["owner_id"] = flip_context.trigger_owner;
		prevented["new_owner_id"] = new_owner;
		prevented["instance_id"] = value.card_instance_ids[target];
		resolution.events.append(prevented);
		Resolution after_prevented = resolve_event(value, StringName("card_flip_prevented"), flip_context, exile_stack);
		if (!after_prevented.supported) {
			resolution.reason = after_prevented.reason;
			return ActionOutcome::UNSUPPORTED;
		}
		resolution.events.append_array(after_prevented.events);
		resolution.captures.append_array(after_prevented.captures);
		resolution.exiles.append_array(after_prevented.exiles);
		return ActionOutcome::APPLIED;
	}
	Resolution flipped;
	if (!flip_card(
		value,
		-1,
		-1,
		target_cell,
		target,
		new_owner,
		flip_context,
		exile_stack,
		flipped,
		action_context.record_direct_board_changes
	)) {
		resolution.reason = flipped.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	resolution.events.append_array(flipped.events);
	resolution.captures.append_array(flipped.captures);
	resolution.exiles.append_array(flipped.exiles);
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::grant_ability_to_subject(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const ActionContext &action_context,
	int32_t event_source_card_index,
	int32_t source_cell,
	Resolution &resolution
) const {
	if (
		action.granted_ability_index < 0
		|| action.granted_ability_index >= static_cast<int32_t>(compiled_ability_pool.size())
	) {
		resolution.reason = String("Granted native ability index is invalid: ")
			+ String::num_int64(action.granted_ability_index);
		return ActionOutcome::UNSUPPORTED;
	}
	if (
		event_source_card_index < 0
		|| event_source_card_index >= static_cast<int32_t>(value.card_instance_ids.size())
	) {
		resolution.reason = String("Granted ability event source index is invalid: ")
			+ String::num_int64(event_source_card_index);
		return ActionOutcome::UNSUPPORTED;
	}
	const int32_t target = action_context.action_subject_card_index;
	int32_t zone = -1;
	int32_t owner = 0;
	int32_t logical_index = -1;
	if (
		target < 0 || !locate_card(value, target, zone, owner, logical_index) || zone == 2
		|| owner != action_context.action_subject_owner
	) return ActionOutcome::NO_EFFECT;
	std::vector<RuntimeAbilityEntry> &entries = value.card_runtime_abilities[target];
	for (const RuntimeAbilityEntry &entry : entries) {
		if (entry.compiled_ability_index == action.granted_ability_index) return ActionOutcome::NO_EFFECT;
	}
	if (compiled_ability_pool[action.granted_ability_index].has_activation) {
		entries.erase(std::remove_if(entries.begin(), entries.end(), [&](const RuntimeAbilityEntry &entry) {
			return compiled_ability_pool[entry.compiled_ability_index].has_activation;
		}), entries.end());
	}
	RuntimeAbilityEntry entry;
	entry.compiled_ability_index = action.granted_ability_index;
	entry.handle = value.next_ability_handle++;
	entries.push_back(entry);
	Dictionary event;
	event["type"] = StringName("ability_gained");
	event["source_cell"] = source_cell;
	event["source_instance_id"] = value.card_instance_ids[event_source_card_index];
	event["target_cell"] = zone == 0 ? logical_index : -1;
	event["owner_id"] = owner;
	event["instance_id"] = value.card_instance_ids[target];
	event["zone"] = zone == 0 ? StringName("board") : (zone == 1 ? StringName("hand") : (zone == 3 ? StringName("discard") : StringName("removed")));
	event["logical_index"] = logical_index;
	resolution.events.append(event);
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::execute_actions(
	NativeState &value,
	const EventGroup &group,
	const std::vector<CompiledAction> &actions,
	const EventContext &event_context,
	const ActionContext &action_context,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution,
	bool defer_power_change_batch
) const {
	ActionExecutionState execution_state;
	execution_state.current_source_cell = group.source_cell;
	return execute_actions_with_state(
		value,
		group,
		actions,
		event_context,
		action_context,
		execution_state,
		exile_stack,
		resolution,
		defer_power_change_batch
	);
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::execute_actions_with_state(
	NativeState &value,
	const EventGroup &group,
	const std::vector<CompiledAction> &actions,
	const EventContext &event_context,
	const ActionContext &action_context,
	ActionExecutionState &execution_state,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution,
	bool defer_power_change_batch
) const {
	ActionOutcome aggregate = ActionOutcome::NO_EFFECT;
	for (size_t action_index = 0; action_index < actions.size(); ++action_index) {
		const CompiledAction &action = actions[action_index];
		const int64_t first_event_index = resolution.events.size();
		ActionOutcome outcome = execute_action(
			value,
			group,
			action,
			event_context,
			action_context,
			execution_state,
			exile_stack,
			resolution
		);
		const int64_t direct_event_end = resolution.events.size();
		if (
			direct_event_end > first_event_index
			&& (
				action.opcode == ActionOpcode::ATTACK_TRIGGER_CARD
				|| action.opcode == ActionOpcode::STANDARD_ATTACK_WITH_SELF
				|| action.opcode == ActionOpcode::STANDARD_ATTACK_WITH_CARD
				|| action.opcode == ActionOpcode::FLIP_SELF
				|| action.opcode == ActionOpcode::SUMMON_CARD
				|| action.opcode == ActionOpcode::RESUMMON_CARD_IN_PLACE
			)
		) {
			resolution.protected_power_batch_ranges.push_back({
				first_event_index,
				direct_event_end,
			});
		}
		for (int64_t event_index = first_event_index;
			action.opcode != ActionOpcode::DISTRIBUTE_KI && event_index < direct_event_end;
			++event_index
		) {
			const Variant event_value = resolution.events[event_index];
			if (event_value.get_type() != Variant::DICTIONARY) continue;
			const Dictionary ki_event = event_value;
			if (StringName(ki_event.get("type", StringName())) != StringName("ki_changed")) continue;
			EventContext ki_context;
			ki_context.trigger_cell = static_cast<int32_t>(static_cast<int64_t>(ki_event.get("target_cell", -1)));
			const StringName instance_id = ki_event.get("instance_id", StringName());
			for (size_t card_index = 0; card_index < value.card_instance_ids.size(); ++card_index) {
				if (value.card_instance_ids[card_index] == instance_id) {
					ki_context.trigger_card_index = static_cast<int32_t>(card_index);
					break;
				}
			}
			ki_context.trigger_owner = static_cast<int32_t>(static_cast<int64_t>(ki_event.get("owner_id", 0)));
			ki_context.previous_ki = static_cast<int32_t>(static_cast<int64_t>(ki_event.get("previous_ki", 0)));
			ki_context.ki = static_cast<int32_t>(static_cast<int64_t>(ki_event.get("ki", -1)));
			Resolution ki_resolution = resolve_event(value, StringName("card_ki_changed"), ki_context, exile_stack);
			if (!ki_resolution.supported) {
				resolution.reason = ki_resolution.reason;
				return ActionOutcome::UNSUPPORTED;
			}
			const int64_t ki_resolution_start = resolution.events.size();
			append_resolution(resolution, ki_resolution);
			const int64_t ki_resolution_end = resolution.events.size();
			if (ki_resolution_end > ki_resolution_start) {
				resolution.protected_power_batch_ranges.push_back({
					ki_resolution_start,
					ki_resolution_end,
				});
			}
		}
		if (!defer_power_change_batch) {
			assign_power_change_batch(
				value,
				resolution,
				first_event_index,
				group,
				action,
				action_context,
				static_cast<int32_t>(action_index)
			);
		}
		if (outcome == ActionOutcome::UNSUPPORTED) {
			if (resolution.reason.is_empty()) {
				resolution.reason = String("Unsupported compiled action opcode ")
					+ String::num_int64(static_cast<int64_t>(action.opcode))
					+ String(" type=") + String(action.declaration_type);
			}
			return outcome;
		}
		if (outcome == ActionOutcome::INVALID_CONTEXT) return outcome;
		if (outcome == ActionOutcome::NO_EFFECT && action.stop_rule_on_invalid_context) {
			return ActionOutcome::INVALID_CONTEXT;
		}
		if (outcome == ActionOutcome::APPLIED) aggregate = ActionOutcome::APPLIED;
	}
	return aggregate;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::execute_for_each_selected_card(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	ActionExecutionState &execution_state,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	bool selection_supported = true;
	const std::vector<int32_t> selected = snapshot_selected_cards(
		value,
		action.selector,
		action_context,
		selection_supported
	);
	if (!selection_supported) return ActionOutcome::UNSUPPORTED;
	ActionOutcome aggregate = ActionOutcome::NO_EFFECT;
	for (const int32_t selected_card_index : selected) {
		int32_t zone = -1;
		int32_t owner = 0;
		int32_t logical_index = -1;
		if (!locate_card(value, selected_card_index, zone, owner, logical_index) || zone == 2) continue;
		bool condition_supported = true;
		if (!selector_conditions_match(
			value,
			selected_card_index,
			zone,
			owner,
			logical_index,
			action.selector,
			action_context,
			condition_supported
		)) {
			if (!condition_supported) return ActionOutcome::UNSUPPORTED;
			continue;
		}
		ActionContext nested_context = action_context;
		nested_context.action_subject_card_index = selected_card_index;
		nested_context.action_subject_owner = owner;
		nested_context.action_subject_zone = zone;
		nested_context.action_subject_logical_index = logical_index;
		nested_context.selected_card_index = selected_card_index;
		nested_context.selected_card_owner = owner;
		nested_context.selected_card_zone = zone;
		nested_context.selected_card_logical_index = logical_index;
		ActionExecutionState nested_execution_state = execution_state;
		nested_execution_state.current_source_cell = zone == 0 ? logical_index : -1;
		const ActionOutcome outcome = execute_actions_with_state(
			value,
			group,
			action.child_actions,
			event_context,
			nested_context,
			nested_execution_state,
			exile_stack,
			resolution,
			true
		);
		if (outcome == ActionOutcome::UNSUPPORTED || outcome == ActionOutcome::INVALID_CONTEXT) return outcome;
		if (outcome == ActionOutcome::APPLIED) aggregate = ActionOutcome::APPLIED;
	}
	return aggregate;
}

bool DuelNativeCompactKernel::action_conditions_match(
	const NativeState &value,
	const std::vector<CompiledCondition> &conditions,
	const ActionContext &action_context,
	const ActionExecutionState &execution_state,
	bool &supported
) const {
	supported = true;
	if (conditions.empty()) return false;
	for (const CompiledCondition &condition : conditions) {
		bool matched = false;
		switch (condition.opcode) {
			case ConditionOpcode::SOURCE_OWNER_HAND_EMPTY:
				if (
					action_context.ability_source_owner < 1
					|| action_context.ability_source_owner > 2
				) {
					supported = false;
					return false;
				}
				matched = value.zones[action_context.ability_source_owner - 1].empty();
				break;
			case ConditionOpcode::LAST_DISCARD_BATCH_SIZE_AT_LEAST:
				matched = execution_state.last_discard_batch_size >= condition.amount;
				break;
			default:
				supported = false;
				return false;
		}
		if (!matched) return false;
	}
	return true;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::execute_action(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	ActionExecutionState &execution_state,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	if (!action.declaration_valid) return ActionOutcome::UNSUPPORTED;
	const int32_t action_source_cell = execution_state.current_source_cell;
	switch (action.opcode) {
		case ActionOpcode::DRAW_CARDS: {
			EventContext draw_context = event_context;
			draw_context.ability_source_cell = action_context.ability_source_cell;
			draw_context.ability_source_zone = action_context.ability_source_zone;
			draw_context.ability_source_logical_index = action_context.ability_source_logical_index;
			draw_context.ability_source_card_index = action_context.ability_source_card_index;
			draw_context.ability_source_owner = action_context.ability_source_owner;
			return draw_cards(
				value,
				action_context.action_subject_owner,
				action_source_cell,
				action.amount,
				action.weapon,
				draw_context,
				exile_stack,
				resolution
			)
				? ActionOutcome::APPLIED
				: ActionOutcome::UNSUPPORTED;
		}
		case ActionOpcode::DISCARD_CARD: {
			execution_state.last_discard_batch_size = 0;
			int32_t target = -1;
			if (action.card_ref == CardRefOpcode::SELECTED_CARD) target = action_context.selected_card_index;
			else if (action.card_ref == CardRefOpcode::TRIGGER_CARD) target = event_context.trigger_card_index;
			else if (action.card_ref == CardRefOpcode::ABILITY_SOURCE) target = action_context.ability_source_card_index;
			else if (action.card_ref == CardRefOpcode::ATTACKER_CARD) target = event_context.attacker_card_index;
			else return ActionOutcome::UNSUPPORTED;
			return discard_locked_cards(
				value,
				group,
				target >= 0 ? std::vector<int32_t>{target} : std::vector<int32_t>{},
				event_context,
				action_context,
				execution_state,
				exile_stack,
				resolution
			);
		}
		case ActionOpcode::DISCARD_CARDS: {
			execution_state.last_discard_batch_size = 0;
			bool selection_supported = true;
			const std::vector<int32_t> selected = snapshot_selected_cards(
				value,
				action.selector,
				action_context,
				selection_supported
			);
			if (!selection_supported) return ActionOutcome::UNSUPPORTED;
			return discard_locked_cards(
				value,
				group,
				selected,
				event_context,
				action_context,
				execution_state,
				exile_stack,
				resolution
			);
		}
		case ActionOpcode::EXILE_SELF:
			return exile_card(value, action_context.action_subject_card_index, action_source_cell, action_context.action_subject_card_index, true, StringName("ability_exile_self"), event_context, exile_stack, resolution, action_context.record_direct_board_changes)
				? ActionOutcome::APPLIED
				: ActionOutcome::UNSUPPORTED;
		case ActionOpcode::EXILE_CARD: {
			int32_t target = -1;
			if (action.card_ref == CardRefOpcode::SELECTED_CARD) target = action_context.selected_card_index;
			else if (action.card_ref == CardRefOpcode::TRIGGER_CARD) target = event_context.trigger_card_index;
			else if (action.card_ref == CardRefOpcode::ABILITY_SOURCE) target = action_context.ability_source_card_index;
			else if (action.card_ref == CardRefOpcode::ATTACKER_CARD) target = event_context.attacker_card_index;
			else return ActionOutcome::UNSUPPORTED;
			if (target < 0) return ActionOutcome::NO_EFFECT;
			return exile_card(value, target, action_source_cell, action_context.ability_source_card_index, target == action_context.ability_source_card_index, StringName("ability_exile_card"), event_context, exile_stack, resolution, action_context.record_direct_board_changes)
				? ActionOutcome::APPLIED
				: ActionOutcome::UNSUPPORTED;
		}
		case ActionOpcode::PREVENT_TRIGGER_FLIP:
			if (event_context.trigger_card_index < 0 || event_context.new_owner < 1 || event_context.new_owner > 2) {
				return ActionOutcome::NO_EFFECT;
			}
			resolution.flip_prevented = true;
			return ActionOutcome::APPLIED;
		case ActionOpcode::REMOVE_THIS_ABILITY: {
			const int32_t current_cell = find_board_card(value, group.source_card_index, group.source_cell);
			if (current_cell >= 0 && value.board_owners[current_cell] == group.source_owner) {
				const int32_t current_ability_index = find_runtime_ability_index(
					value,
					group.source_card_index,
					group.ability_handle,
					group.ability_index
				);
				if (current_ability_index < 0) return ActionOutcome::NO_EFFECT;
				remove_ability_with_event(value, group.source_card_index, group.ability_handle, current_cell, group.source_card_index, current_cell, group.source_owner, resolution.events);
				return ActionOutcome::APPLIED;
			}
			return ActionOutcome::NO_EFFECT;
		}
		case ActionOpcode::FOR_EACH_SELECTED_CARD:
			return execute_for_each_selected_card(value, group, action, event_context, action_context, execution_state, exile_stack, resolution);
		case ActionOpcode::IF: {
			bool conditions_supported = true;
			if (!action_conditions_match(
				value,
				action.conditions,
				action_context,
				execution_state,
				conditions_supported
			)) {
				return conditions_supported ? ActionOutcome::NO_EFFECT : ActionOutcome::UNSUPPORTED;
			}
			return execute_actions_with_state(
				value,
				group,
				action.child_actions,
				event_context,
				action_context,
				execution_state,
				exile_stack,
				resolution
			);
		}
		case ActionOpcode::CHANGE_POWERS:
			return change_powers(value, group, action, event_context, action_context, action_source_cell, exile_stack, resolution);
		case ActionOpcode::GAIN_KI:
		case ActionOpcode::SPEND_KI: {
			if (action.card_ref_explicit && action.card_ref == CardRefOpcode::LAST_SUMMONED_CARD) {
				const int32_t target = execution_state.last_summoned_card_index;
				int32_t zone = -1;
				int32_t owner = 0;
				int32_t logical_index = -1;
				if (target < 0 || !locate_card(value, target, zone, owner, logical_index)) {
					return ActionOutcome::NO_EFFECT;
				}
				CompiledAction selected_action = action;
				selected_action.card_ref = CardRefOpcode::SELECTED_CARD;
				ActionContext selected_context = action_context;
				selected_context.selected_card_index = target;
				selected_context.selected_card_owner = owner;
				selected_context.action_subject_owner = owner;
				return change_ki(
					value,
					group,
					selected_action,
					event_context,
					selected_context,
					action_source_cell,
					exile_stack,
					resolution
				);
			}
			return change_ki(value, group, action, event_context, action_context, action_source_cell, exile_stack, resolution);
		}
		case ActionOpcode::FLIP_SELF:
			return flip_action_subject(value, group, action, event_context, action_context, exile_stack, resolution);
		case ActionOpcode::GRANT_TRIGGER_CARD_ABILITY: {
			if (event_context.trigger_card_index < 0) return ActionOutcome::NO_EFFECT;
			ActionContext trigger_context = action_context;
			trigger_context.action_subject_card_index = event_context.trigger_card_index;
			trigger_context.action_subject_owner = event_context.trigger_owner;
			trigger_context.action_subject_zone = event_context.trigger_zone;
			trigger_context.action_subject_logical_index = event_context.trigger_logical_index;
			return grant_ability_to_subject(
				value,
				group,
				action,
				trigger_context,
				action_context.action_subject_card_index,
				action_source_cell,
				resolution
			);
		}
		case ActionOpcode::GRANT_ABILITY_TO_SELF:
			return grant_ability_to_subject(
				value,
				group,
				action,
				action_context,
				action_context.action_subject_card_index,
				action_source_cell,
				resolution
			);
		case ActionOpcode::TRANSFORM_CARD:
			return transform_card(value, group, action, event_context, action_context, execution_state, resolution);
		case ActionOpcode::RETURN_CARD_TO_HAND:
			return return_card_to_hand(value, group, action, event_context, action_context, exile_stack, resolution);
		case ActionOpcode::SELF_SWAPPED_WITH_ABILITY_SOURCE:
			return swap_action_subject_with_ability_source(value, group, event_context, action_context, exile_stack, resolution);
		case ActionOpcode::SWAP_SELF_WITH_TRIGGER_CARD: {
			if (event_context.trigger_card_index < 0) return ActionOutcome::NO_EFFECT;
			ActionContext trigger_context = action_context;
			trigger_context.action_subject_card_index = event_context.trigger_card_index;
			trigger_context.action_subject_owner = event_context.trigger_owner;
			trigger_context.action_subject_zone = 0;
			trigger_context.action_subject_logical_index = event_context.trigger_cell;
			return swap_action_subject_with_ability_source(
				value,
				group,
				event_context,
				trigger_context,
				exile_stack,
				resolution
			);
		}
		case ActionOpcode::MOVE_SELF_TO_TARGET: {
			if (action_context.activation_target_kind != StringName("board_cell")) {
				return ActionOutcome::NO_EFFECT;
			}
			const int32_t target_cell = action_context.activation_target_index;
			const int32_t moving_card_index = action_context.action_subject_card_index;
			const int32_t moving_owner = action_context.action_subject_owner;
			if (
				target_cell < 0
				|| target_cell >= static_cast<int32_t>(value.board_card_indices.size())
				|| value.board_card_indices[target_cell] >= 0
			) return ActionOutcome::NO_EFFECT;
			const int32_t current_cell = find_board_card(
				value,
				moving_card_index,
				action_source_cell
			);
			if (
				current_cell != action_source_cell
				|| current_cell < 0
				|| value.board_owners[current_cell] != moving_owner
			) return ActionOutcome::NO_EFFECT;
			bool adjacent = false;
			for (int32_t direction = 0; direction < 4; ++direction) {
				if (neighbor_index(current_cell, direction) == target_cell) {
					adjacent = true;
					break;
				}
			}
			if (!adjacent) return ActionOutcome::NO_EFFECT;
			const ActionOutcome outcome = move_card_between_cells(
				value,
				current_cell,
				current_cell,
				target_cell,
				moving_card_index,
				moving_owner,
				true,
				exile_stack,
				resolution
			);
			if (outcome == ActionOutcome::APPLIED) {
				execution_state.current_source_cell = find_board_card(
					value,
					group.source_card_index,
					target_cell
				);
			}
			return outcome;
		}
		case ActionOpcode::SWAP_SELF_WITH_TARGET: {
			if (action_context.activation_target_kind != StringName("board_cell")) {
				return ActionOutcome::NO_EFFECT;
			}
			const int32_t target_cell = action_context.activation_target_index;
			const int32_t target_card_index = action_context.selected_card_index;
			const int32_t target_owner = action_context.selected_card_owner;
			if (
				target_cell < 0
				|| target_cell >= static_cast<int32_t>(value.board_card_indices.size())
				|| target_card_index < 0
				|| value.board_card_indices[target_cell] != target_card_index
				|| value.board_owners[target_cell] != target_owner
			) return ActionOutcome::NO_EFFECT;
			ActionContext target_context = action_context;
			target_context.action_subject_card_index = target_card_index;
			target_context.action_subject_owner = target_owner;
			target_context.action_subject_zone = 0;
			target_context.action_subject_logical_index = target_cell;
			const ActionOutcome outcome = swap_action_subject_with_ability_source(
				value,
				group,
				event_context,
				target_context,
				exile_stack,
				resolution
			);
			if (outcome == ActionOutcome::APPLIED) {
				execution_state.current_source_cell = find_board_card(
					value,
					group.source_card_index,
					target_cell
				);
			}
			return outcome;
		}
		case ActionOpcode::ATTACK_TRIGGER_CARD:
		case ActionOpcode::STANDARD_ATTACK_WITH_SELF:
		case ActionOpcode::STANDARD_ATTACK_WITH_CARD: {
			int32_t source_zone = -1;
			int32_t source_owner = 0;
			int32_t source_logical_index = -1;
			const int32_t attacker_card_index = action.opcode == ActionOpcode::STANDARD_ATTACK_WITH_CARD
				? resolve_action_card_reference(
					action.card_ref,
					event_context,
					action_context,
					execution_state
				)
				: action_context.action_subject_card_index;
			if (
				attacker_card_index < 0
				|| !locate_card(
					value,
					attacker_card_index,
					source_zone,
					source_owner,
					source_logical_index
				)
				|| source_zone != 0
				|| (
					action.opcode != ActionOpcode::STANDARD_ATTACK_WITH_CARD
					&& source_owner != action_context.action_subject_owner
				)
			) return ActionOutcome::NO_EFFECT;
			AttackRequest request;
			request.attacker_cell = source_logical_index;
			request.attacker_card_index = attacker_card_index;
			request.attacker_owner = source_owner;
			if (action.opcode == ActionOpcode::ATTACK_TRIGGER_CARD) {
				const int32_t target_cell = find_board_card(
					value,
					event_context.trigger_card_index,
					event_context.trigger_cell
				);
				if (target_cell != event_context.trigger_cell || target_cell < 0) {
					return ActionOutcome::NO_EFFECT;
				}
				request.targeted = true;
				request.locked_target_cell = target_cell;
				request.locked_target_card_index = event_context.trigger_card_index;
				request.locked_target_owner = value.board_owners[target_cell];
				request.reason = StringName("card_summoned_reaction");
			} else {
				request.repeat_attack = action.repeat_attack;
				request.reason = StringName("activated_ability");
				if (action.target_policy_specified) {
					request.requested_policy.specified = true;
					request.requested_policy.target_policy = action.target_policy;
				}
			}
			Resolution nested = resolve_attack_request(value, request, exile_stack);
			if (!nested.supported) {
				resolution.reason = nested.reason;
				return ActionOutcome::UNSUPPORTED;
			}
			const bool applied = resolution_has_output(nested);
			append_resolution(resolution, nested);
			return applied ? ActionOutcome::APPLIED : ActionOutcome::NO_EFFECT;
		}
		case ActionOpcode::MOVE_SELF_TO_FIRST_ADJACENT_EMPTY: {
			int32_t source_zone = -1;
			int32_t source_owner = 0;
			int32_t current_cell = -1;
			const int32_t moving_card_index = action_context.action_subject_card_index;
			if (
				moving_card_index < 0
				|| !locate_card(value, moving_card_index, source_zone, source_owner, current_cell)
				|| source_zone != 0
				|| source_owner != action_context.action_subject_owner
			) return ActionOutcome::NO_EFFECT;
			for (int32_t target_cell = 0; target_cell < static_cast<int32_t>(value.board_card_indices.size()); ++target_cell) {
				if (value.board_card_indices[target_cell] >= 0) continue;
				bool adjacent = false;
				for (int32_t direction = 0; direction < 4; ++direction) {
					if (neighbor_index(current_cell, direction) == target_cell) {
						adjacent = true;
						break;
					}
				}
				if (!adjacent) continue;
				const ActionOutcome outcome = move_card_between_cells(
					value,
					current_cell,
					current_cell,
					target_cell,
					moving_card_index,
					source_owner,
					true,
					exile_stack,
					resolution
				);
				if (outcome == ActionOutcome::APPLIED) {
					execution_state.current_source_cell = find_board_card(
						value,
						group.source_card_index,
						target_cell
					);
				}
				return outcome;
			}
			return ActionOutcome::NO_EFFECT;
		}
		case ActionOpcode::MOVE_SELF_TO_FIRST_EMPTY_BETWEEN_ENEMY: {
			int32_t source_zone = -1;
			int32_t source_owner = 0;
			int32_t current_cell = -1;
			const int32_t moving_card_index = action_context.action_subject_card_index;
			if (
				moving_card_index < 0
				|| !locate_card(value, moving_card_index, source_zone, source_owner, current_cell)
				|| source_zone != 0
				|| source_owner != action_context.action_subject_owner
			) return ActionOutcome::NO_EFFECT;
			for (int32_t middle_cell = 0; middle_cell < static_cast<int32_t>(value.board_card_indices.size()); ++middle_cell) {
				if (value.board_card_indices[middle_cell] >= 0) continue;
				for (int32_t direction = 0; direction < 4; ++direction) {
					if (neighbor_index(current_cell, direction) != middle_cell) continue;
					const int32_t far_cell = neighbor_index(middle_cell, direction);
					if (
						far_cell < 0
						|| value.board_card_indices[far_cell] < 0
						|| value.board_owners[far_cell] == source_owner
					) continue;
					const ActionOutcome outcome = move_card_between_cells(
						value,
						current_cell,
						current_cell,
						middle_cell,
						moving_card_index,
						source_owner,
						true,
						exile_stack,
						resolution
					);
					if (outcome == ActionOutcome::APPLIED) {
						execution_state.current_source_cell = find_board_card(value, group.source_card_index, middle_cell);
					}
					return outcome;
				}
			}
			return ActionOutcome::NO_EFFECT;
		}
		case ActionOpcode::TRANSFER_CARD_RESOURCE: {
			auto resolve_ref = [&](CardRefOpcode reference) -> int32_t {
				if (reference == CardRefOpcode::SELECTED_CARD) return action_context.selected_card_index;
				if (reference == CardRefOpcode::TRIGGER_CARD) return event_context.trigger_card_index;
				if (reference == CardRefOpcode::ABILITY_SOURCE) return action_context.ability_source_card_index;
				if (reference == CardRefOpcode::ATTACKER_CARD) return event_context.attacker_card_index;
				return -1;
			};
			const int32_t donor = resolve_ref(action.from_card_ref);
			const int32_t receiver = resolve_ref(action.to_card_ref);
			if (donor < 0 || receiver < 0 || donor == receiver) return ActionOutcome::NO_EFFECT;
			int32_t donor_zone = -1;
			int32_t donor_owner = 0;
			int32_t donor_index = -1;
			int32_t receiver_zone = -1;
			int32_t receiver_owner = 0;
			int32_t receiver_index = -1;
			if (
				!locate_card(value, donor, donor_zone, donor_owner, donor_index)
				|| !locate_card(value, receiver, receiver_zone, receiver_owner, receiver_index)
				|| donor_zone == 2
				|| receiver_zone == 2
			) return ActionOutcome::NO_EFFECT;
			auto can_donate = [&](ResourceOpcode resource) {
				if (resource == ResourceOpcode::KI) return value.card_ki[donor] >= action.amount;
				if (resource != ResourceOpcode::POWERS || !can_change_powers(value, donor)) return false;
				for (int32_t direction = 0; direction < 4; ++direction) {
					if (value.card_powers[donor * 4 + direction] > 0) return true;
				}
				return false;
			};
			auto can_receive = [&](ResourceOpcode resource) {
				return resource == ResourceOpcode::KI
					|| (resource == ResourceOpcode::POWERS && can_change_powers(value, receiver));
			};
			for (const ResourceOpcode resource : {action.resource, action.fallback_resource}) {
				if (!can_donate(resource)) continue;
				if (!can_receive(resource)) return ActionOutcome::NO_EFFECT;
				if (resource == ResourceOpcode::KI) {
					CompiledAction donor_action;
					donor_action.opcode = ActionOpcode::SPEND_KI;
					donor_action.card_ref_explicit = true;
					donor_action.card_ref = CardRefOpcode::SELECTED_CARD;
					donor_action.amount = action.amount;
					donor_action.change_reason = StringName("transfer_card_resource");
					ActionContext donor_context = action_context;
					donor_context.selected_card_index = donor;
					donor_context.selected_card_owner = donor_owner;
					donor_context.action_subject_owner = donor_owner;
					const ActionOutcome donor_outcome = change_ki(
						value, group, donor_action, event_context, donor_context,
						action_source_cell, exile_stack, resolution
					);
					if (donor_outcome != ActionOutcome::APPLIED) return donor_outcome;
					CompiledAction receiver_action = donor_action;
					receiver_action.opcode = ActionOpcode::GAIN_KI;
					ActionContext receiver_context = action_context;
					receiver_context.selected_card_index = receiver;
					receiver_context.selected_card_owner = receiver_owner;
					receiver_context.action_subject_owner = receiver_owner;
					return change_ki(
						value, group, receiver_action, event_context, receiver_context,
						action_source_cell, exile_stack, resolution
					);
				}
				CompiledAction donor_action;
				donor_action.opcode = ActionOpcode::CHANGE_POWERS;
				donor_action.card_ref = CardRefOpcode::SELECTED_CARD;
				donor_action.amount = -action.amount;
				ActionContext donor_context = action_context;
				donor_context.selected_card_index = donor;
				donor_context.selected_card_owner = donor_owner;
				donor_context.action_subject_owner = donor_owner;
				const ActionOutcome donor_outcome = change_powers(
					value, group, donor_action, event_context, donor_context,
					action_source_cell, exile_stack, resolution
				);
				if (donor_outcome != ActionOutcome::APPLIED) return donor_outcome;
				CompiledAction receiver_action = donor_action;
				receiver_action.amount = action.amount;
				ActionContext receiver_context = action_context;
				receiver_context.selected_card_index = receiver;
				receiver_context.selected_card_owner = receiver_owner;
				receiver_context.action_subject_owner = receiver_owner;
				return change_powers(
					value, group, receiver_action, event_context, receiver_context,
					action_source_cell, exile_stack, resolution
				);
			}
			return ActionOutcome::NO_EFFECT;
		}
		case ActionOpcode::DISTRIBUTE_KI: {
			const int32_t distributor = resolve_action_card_reference(
				action.from_card_ref,
				event_context,
				action_context,
				execution_state
			);
			int32_t distributor_zone = -1;
			int32_t distributor_owner = 0;
			int32_t distributor_logical_index = -1;
			if (
				distributor < 0
				|| !locate_card(
					value,
					distributor,
					distributor_zone,
					distributor_owner,
					distributor_logical_index
				)
				|| distributor_zone == 2
			) return ActionOutcome::NO_EFFECT;

			ActionContext selector_context = action_context;
			selector_context.ability_source_card_index = distributor;
			selector_context.ability_source_owner = distributor_owner;
			selector_context.ability_source_zone = distributor_zone;
			selector_context.ability_source_logical_index = distributor_logical_index;
			selector_context.ability_source_cell = distributor_zone == 0
				? distributor_logical_index
				: -1;
			bool selection_supported = true;
			const std::vector<int32_t> selected = snapshot_selected_cards(
				value,
				action.selector,
				selector_context,
				selection_supported
			);
			if (!selection_supported) return ActionOutcome::UNSUPPORTED;

			ActionOutcome aggregate = ActionOutcome::NO_EFFECT;
			while (true) {
				if (
					!locate_card(
						value,
						distributor,
						distributor_zone,
						distributor_owner,
						distributor_logical_index
					)
					|| distributor_zone == 2
					|| value.card_ki[distributor] < action.amount
				) break;
				bool transferred_in_round = false;
				for (const int32_t recipient : selected) {
					if (
						!locate_card(
							value,
							distributor,
							distributor_zone,
							distributor_owner,
							distributor_logical_index
						)
						|| distributor_zone == 2
						|| value.card_ki[distributor] < action.amount
					) break;
					int32_t recipient_zone = -1;
					int32_t recipient_owner = 0;
					int32_t recipient_logical_index = -1;
					if (
						!locate_card(
							value,
							recipient,
							recipient_zone,
							recipient_owner,
							recipient_logical_index
						)
						|| recipient_zone == 2
					) continue;
					selector_context.ability_source_owner = distributor_owner;
					selector_context.ability_source_zone = distributor_zone;
					selector_context.ability_source_logical_index = distributor_logical_index;
					selector_context.ability_source_cell = distributor_zone == 0
						? distributor_logical_index
						: -1;
					bool condition_supported = true;
					if (!selector_conditions_match(
						value,
						recipient,
						recipient_zone,
						recipient_owner,
						recipient_logical_index,
						action.selector,
						selector_context,
						condition_supported
					)) {
						if (!condition_supported) return ActionOutcome::UNSUPPORTED;
						continue;
					}

					const int64_t transfer_event_start = resolution.events.size();
					CompiledAction donor_action;
					donor_action.opcode = ActionOpcode::SPEND_KI;
					donor_action.card_ref_explicit = true;
					donor_action.card_ref = CardRefOpcode::SELECTED_CARD;
					donor_action.amount = action.amount;
					donor_action.change_reason = StringName("transfer_card_resource");
					ActionContext donor_context = action_context;
					donor_context.selected_card_index = distributor;
					donor_context.selected_card_owner = distributor_owner;
					donor_context.action_subject_owner = distributor_owner;
					const ActionOutcome donor_outcome = change_ki(
						value, group, donor_action, event_context, donor_context,
						action_source_cell, exile_stack, resolution
					);
					if (donor_outcome != ActionOutcome::APPLIED) continue;
					CompiledAction receiver_action = donor_action;
					receiver_action.opcode = ActionOpcode::GAIN_KI;
					ActionContext receiver_context = action_context;
					receiver_context.selected_card_index = recipient;
					receiver_context.selected_card_owner = recipient_owner;
					receiver_context.action_subject_owner = recipient_owner;
					const ActionOutcome receiver_outcome = change_ki(
						value, group, receiver_action, event_context, receiver_context,
						action_source_cell, exile_stack, resolution
					);
					if (receiver_outcome != ActionOutcome::APPLIED) return receiver_outcome;

					const int64_t transfer_event_end = resolution.events.size();
					for (
						int64_t event_index = transfer_event_start;
						event_index < transfer_event_end;
						++event_index
					) {
						Dictionary ki_event = resolution.events[event_index];
						ki_event["ki_trigger_resolved"] = true;
						resolution.events[event_index] = ki_event;
						EventContext ki_context;
						ki_context.trigger_cell = static_cast<int32_t>(static_cast<int64_t>(ki_event.get("target_cell", -1)));
						const StringName instance_id = ki_event.get("instance_id", StringName());
						for (size_t card_index = 0; card_index < value.card_instance_ids.size(); ++card_index) {
							if (value.card_instance_ids[card_index] == instance_id) {
								ki_context.trigger_card_index = static_cast<int32_t>(card_index);
								break;
							}
						}
						ki_context.trigger_owner = static_cast<int32_t>(static_cast<int64_t>(ki_event.get("owner_id", 0)));
						ki_context.previous_ki = static_cast<int32_t>(static_cast<int64_t>(ki_event.get("previous_ki", 0)));
						ki_context.ki = static_cast<int32_t>(static_cast<int64_t>(ki_event.get("ki", -1)));
						Resolution ki_resolution = resolve_event(
							value,
							StringName("card_ki_changed"),
							ki_context,
							exile_stack
						);
						if (!ki_resolution.supported) {
							resolution.reason = ki_resolution.reason;
							return ActionOutcome::UNSUPPORTED;
						}
						append_resolution(resolution, ki_resolution);
					}
					transferred_in_round = true;
					aggregate = ActionOutcome::APPLIED;
				}
				if (!transferred_in_round) break;
			}
			return aggregate;
		}
		case ActionOpcode::ADD_CARD_TO_HAND: {
			int32_t source_zone = -1;
			int32_t source_owner = 0;
			int32_t source_logical_index = -1;
			const int32_t source_card_index = action_context.action_subject_card_index;
			if (
				source_card_index < 0
				|| !locate_card(
					value,
					source_card_index,
					source_zone,
					source_owner,
					source_logical_index
				)
				|| source_owner != action_context.action_subject_owner
			) return ActionOutcome::NO_EFFECT;
			if (action.recipient == RecipientOpcode::UNSUPPORTED) return ActionOutcome::UNSUPPORTED;
			const int32_t recipient_owner = action.recipient == RecipientOpcode::SELF
				? source_owner
				: other_owner(source_owner);
			std::vector<int32_t> &hand = value.zones[recipient_owner - 1];
			if (hand.size() >= 5) return ActionOutcome::NO_EFFECT;
			const int32_t hand_slot = leftmost_empty_hand_slot(value, recipient_owner);
			if (hand_slot < 0) return ActionOutcome::NO_EFFECT;

			int32_t copied_card_index = -1;
			StringName card_id = action.card_id;
			if (card_id.is_empty()) {
				copied_card_index = resolve_action_card_reference(
					action.summon_card_ref,
					event_context,
					action_context,
					execution_state
				);
				if (
					copied_card_index < 0
					|| copied_card_index >= static_cast<int32_t>(value.card_ids.size())
				) return ActionOutcome::NO_EFFECT;
				card_id = value.card_ids[copied_card_index];
			}
			const StringName instance_id = make_generated_instance_id(value, card_id);
			String append_reason;
			const int32_t added_card_index = action.card_spec == CardSpecOpcode::PERFECT_COPY
				? append_perfect_copy_board_card(
					value,
					copied_card_index,
					instance_id,
					append_reason
				)
				: append_fresh_board_card(
					value,
					card_id,
					instance_id,
					recipient_owner,
					append_reason
				);
			if (added_card_index < 0) {
				if (
					action.card_spec != CardSpecOpcode::PERFECT_COPY
					&& find_fresh_card_prototype(value, card_id) == nullptr
				) return ActionOutcome::NO_EFFECT;
				resolution.reason = append_reason;
				return ActionOutcome::UNSUPPORTED;
			}
			value.card_runtime_flags[added_card_index] |= static_cast<uint8_t>(1 << 7);
			value.card_hand_slots[added_card_index] = hand_slot;
			const int32_t previous_hand_size = static_cast<int32_t>(hand.size());
			hand.push_back(added_card_index);

			const int32_t observer_owner = other_owner(recipient_owner);
			uint8_t &reveal_code = value.card_reveal_codes[added_card_index];
			const bool already_revealed = (
				(observer_owner == 1 && (reveal_code == 1 || reveal_code == 3 || reveal_code == 4))
				|| (observer_owner == 2 && (reveal_code == 2 || reveal_code == 3 || reveal_code == 4))
			);
			if (!already_revealed) {
				if (observer_owner == 1) reveal_code = reveal_code == 2 ? 4 : 1;
				else reveal_code = reveal_code == 1 ? 3 : 2;
			}
			const int32_t current_source_cell = source_zone == 0 ? source_logical_index : -1;
			Dictionary added;
			added["type"] = StringName("card_added_to_hand");
			added["source_cell"] = current_source_cell;
			added["source_instance_id"] = value.card_instance_ids[source_card_index];
			added["owner_id"] = recipient_owner;
			added["card_id"] = card_id;
			added["instance_id"] = instance_id;
			added["logical_hand_index"] = static_cast<int32_t>(hand.size()) - 1;
			added["hand_slot_index"] = hand_slot;
			if (include_presentation_payloads) {
				added["card"] = restore_runtime_card(value, added_card_index);
			}
			resolution.events.append(added);
			if (!already_revealed) {
				Dictionary revealed;
				revealed["type"] = StringName("card_revealed");
				revealed["source_cell"] = current_source_cell;
				revealed["source_instance_id"] = value.card_instance_ids[source_card_index];
				revealed["owner_id"] = recipient_owner;
				revealed["observer_owner_id"] = observer_owner;
				revealed["card_id"] = card_id;
				revealed["instance_id"] = instance_id;
				revealed["logical_hand_index"] = static_cast<int32_t>(hand.size()) - 1;
				resolution.events.append(revealed);
			}
			Resolution hand_change = resolve_difficulty_hand_change(
				value,
				recipient_owner,
				previous_hand_size,
				static_cast<int32_t>(hand.size()),
				action_source_cell,
				exile_stack
			);
			if (!hand_change.supported) {
				resolution.reason = hand_change.reason;
				return ActionOutcome::UNSUPPORTED;
			}
			append_resolution(resolution, hand_change);
			return ActionOutcome::APPLIED;
		}
		case ActionOpcode::REVEAL_HAND_CARDS: {
			const int32_t observer_owner = action_context.action_subject_owner;
			if (observer_owner != 1 && observer_owner != 2) return ActionOutcome::NO_EFFECT;
			const int32_t hand_owner = action.recipient == RecipientOpcode::SELF
				? observer_owner
				: other_owner(observer_owner);
			if (action.recipient == RecipientOpcode::UNSUPPORTED) return ActionOutcome::UNSUPPORTED;
			Array remembered;
			if (action.reveal_filter == RevealFilterOpcode::REMEMBERED) {
				const Dictionary remembered_by_owner = value.side_payload.get(
					"remembered_glyphs_by_owner",
					Dictionary()
				);
				const Variant remembered_value = remembered_by_owner.get(observer_owner, Array());
				if (remembered_value.get_type() != Variant::ARRAY) return ActionOutcome::UNSUPPORTED;
				remembered = remembered_value;
			} else if (action.reveal_filter != RevealFilterOpcode::ALL) {
				return ActionOutcome::UNSUPPORTED;
			}
			bool applied = false;
			const std::vector<int32_t> &hand = value.zones[hand_owner - 1];
			for (size_t hand_index = 0; hand_index < hand.size(); ++hand_index) {
				const int32_t card_index = hand[hand_index];
				if (action.reveal_filter == RevealFilterOpcode::REMEMBERED) {
					const int32_t template_index = value.card_template_indices[card_index];
					if (
						template_index < 0
						|| template_index >= value.card_template_pool.size()
					) return ActionOutcome::UNSUPPORTED;
					const Dictionary card_template = value.card_template_pool[template_index];
					if (remembered.find(String(card_template.get("glyph", String()))) < 0) continue;
				}
				uint8_t &code = value.card_reveal_codes[card_index];
				const bool already_revealed = (
					(observer_owner == 1 && (code == 1 || code == 3 || code == 4))
					|| (observer_owner == 2 && (code == 2 || code == 3 || code == 4))
				);
				if (already_revealed) continue;
				if (observer_owner == 1) code = code == 2 ? 4 : 1;
				else code = code == 1 ? 3 : 2;
				Dictionary revealed;
				revealed["type"] = StringName("card_revealed");
				revealed["source_cell"] = action_source_cell;
				revealed["owner_id"] = hand_owner;
				revealed["observer_owner_id"] = observer_owner;
				revealed["card_id"] = value.card_ids[card_index];
				revealed["instance_id"] = value.card_instance_ids[card_index];
				revealed["logical_hand_index"] = static_cast<int32_t>(hand_index);
				resolution.events.append(revealed);
				applied = true;
			}
			return applied ? ActionOutcome::APPLIED : ActionOutcome::NO_EFFECT;
		}
		case ActionOpcode::REVEAL_CARD: {
			const int32_t target = resolve_action_card_reference(
				action.card_ref,
				event_context,
				action_context,
				execution_state
			);
			int32_t zone = -1;
			int32_t owner = 0;
			int32_t logical_index = -1;
			if (target < 0 || !locate_card(value, target, zone, owner, logical_index)) {
				return ActionOutcome::NO_EFFECT;
			}
			int32_t expected_owner = 0;
			if (action.card_ref == CardRefOpcode::SELECTED_CARD) {
				expected_owner = action_context.selected_card_owner;
			} else if (action.card_ref == CardRefOpcode::TRIGGER_CARD) {
				expected_owner = event_context.trigger_owner;
			} else if (action.card_ref == CardRefOpcode::ABILITY_SOURCE) {
				expected_owner = action_context.ability_source_owner;
			} else if (action.card_ref == CardRefOpcode::ATTACKER_CARD) {
				expected_owner = event_context.attacker_owner;
			}
			if (expected_owner != 0 && owner != expected_owner) return ActionOutcome::NO_EFFECT;
			const int32_t observer_owner = resolve_relative_owner(
				value,
				action.recipient_owner,
				action_context,
				target
			);
			if (observer_owner != 1 && observer_owner != 2) return ActionOutcome::NO_EFFECT;
			StringName zone_name;
			if (zone == 0) zone_name = StringName("board");
			else if (zone == 1) zone_name = StringName("hand");
			else if (zone == 3) zone_name = StringName("discard");
			else if (zone == 4) zone_name = StringName("removed");
			else return ActionOutcome::NO_EFFECT;
			uint8_t &code = value.card_reveal_codes[target];
			const bool already_revealed = (
				(observer_owner == 1 && (code == 1 || code == 3 || code == 4))
				|| (observer_owner == 2 && (code == 2 || code == 3 || code == 4))
			);
			if (already_revealed) return ActionOutcome::NO_EFFECT;
			if (observer_owner == 1) code = code == 2 ? 4 : 1;
			else code = code == 1 ? 3 : 2;
			Dictionary revealed;
			revealed["type"] = StringName("card_revealed");
			revealed["source_cell"] = action_source_cell;
			revealed["owner_id"] = owner;
			revealed["observer_owner_id"] = observer_owner;
			revealed["card_id"] = value.card_ids[target];
			revealed["instance_id"] = value.card_instance_ids[target];
			revealed["zone"] = zone_name;
			revealed["logical_hand_index"] = zone == 1 ? logical_index : -1;
			revealed["target_cell"] = zone == 0 ? logical_index : -1;
			resolution.events.append(revealed);
			return ActionOutcome::APPLIED;
		}
		case ActionOpcode::GRANT_EXTRA_CARD_PLAY: {
			int32_t source_card_index = action_context.action_subject_card_index;
			int32_t source_owner = action_context.action_subject_owner;
			int32_t source_cell = action_source_cell;
			if (action.card_ref_explicit) {
				if (action.card_ref == CardRefOpcode::SELECTED_CARD) source_card_index = action_context.selected_card_index;
				else if (action.card_ref == CardRefOpcode::TRIGGER_CARD) source_card_index = event_context.trigger_card_index;
				else if (action.card_ref == CardRefOpcode::ABILITY_SOURCE) source_card_index = action_context.ability_source_card_index;
				else if (action.card_ref == CardRefOpcode::ATTACKER_CARD) source_card_index = event_context.attacker_card_index;
				else if (action.card_ref == CardRefOpcode::LAST_SUMMONED_CARD) source_card_index = execution_state.last_summoned_card_index;
				else return ActionOutcome::UNSUPPORTED;
				int32_t zone = -1;
				int32_t logical_index = -1;
				if (!locate_card(value, source_card_index, zone, source_owner, logical_index)) {
					return ActionOutcome::NO_EFFECT;
				}
				source_cell = zone == 0 ? logical_index : action_source_cell;
			}
			if (
				source_card_index < 0
				|| source_card_index >= static_cast<int32_t>(value.card_instance_ids.size())
				|| (source_owner != 1 && source_owner != 2)
				|| action.amount <= 0
			) return ActionOutcome::NO_EFFECT;
			Resolution::ExtraPlayRequest request;
			request.owner_id = source_owner;
			request.source_card_index = source_card_index;
			request.source_cell = source_cell;
			request.amount = action.amount;
			resolution.extra_play_requests.push_back(request);
			return ActionOutcome::APPLIED;
		}
		case ActionOpcode::ADD_PENDING_NON_RETAINED_SUPPRESSION: {
			const int32_t source_owner = action_context.action_subject_owner;
			if (
				(source_owner != 1 && source_owner != 2)
				|| action_context.action_subject_card_index < 0
				|| action_context.action_subject_card_index >= static_cast<int32_t>(value.card_instance_ids.size())
			) return ActionOutcome::NO_EFFECT;
			if (action.recipient == RecipientOpcode::UNSUPPORTED) return ActionOutcome::UNSUPPORTED;
			const int32_t recipient_owner = action.recipient == RecipientOpcode::SELF
				? source_owner
				: other_owner(source_owner);
			const int32_t scalar_index = recipient_owner == 1 ? 8 : 9;
			value.scalars[scalar_index] += action.amount;
			Dictionary added;
			added["type"] = StringName("non_retained_suppression_added");
			added["source_cell"] = action_source_cell;
			added["source_instance_id"] = value.card_instance_ids[action_context.action_subject_card_index];
			added["owner_id"] = recipient_owner;
			added["amount"] = action.amount;
			added["pending_count"] = value.scalars[scalar_index];
			resolution.events.append(added);
			return ActionOutcome::APPLIED;
		}
		case ActionOpcode::TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES:
			return temporarily_remove_non_retained_abilities(
				value,
				action_context,
				action_source_cell,
				resolution
			);
		case ActionOpcode::ENABLE_FUTURE_DRAW_REVEAL: {
			const int32_t observer_owner = action_context.action_subject_owner;
			if (observer_owner != 1 && observer_owner != 2) return ActionOutcome::NO_EFFECT;
			const int32_t hand_owner = action.recipient == RecipientOpcode::SELF
				? observer_owner
				: other_owner(observer_owner);
			if (action.recipient == RecipientOpcode::UNSUPPORTED) return ActionOutcome::UNSUPPORTED;
			Dictionary audiences_by_owner = value.side_payload.get(
				"future_draw_reveal_audiences",
				Dictionary()
			);
			const Variant audiences_value = audiences_by_owner.get(hand_owner, Array());
			if (audiences_value.get_type() != Variant::ARRAY) return ActionOutcome::UNSUPPORTED;
			Array audiences = audiences_value;
			if (audiences.find(observer_owner) >= 0) return ActionOutcome::NO_EFFECT;
			audiences.append(observer_owner);
			audiences_by_owner[hand_owner] = audiences;
			value.side_payload["future_draw_reveal_audiences"] = audiences_by_owner;
			return ActionOutcome::APPLIED;
		}
		case ActionOpcode::SUMMON_CARD:
			return summon_card(
				value,
				group,
				action,
				event_context,
				action_context,
				execution_state,
				exile_stack,
				resolution
			);
		case ActionOpcode::RESUMMON_CARD_IN_PLACE:
			return resummon_card_in_place(
				value,
				group,
				action,
				event_context,
				action_context,
				execution_state,
				exile_stack,
				resolution
			);
		case ActionOpcode::DEPART_CARD_FOR_RESUMMON:
			return depart_card_for_resummon(
				value,
				action,
				event_context,
				action_context,
				execution_state,
				resolution
			);
		default:
			return ActionOutcome::UNSUPPORTED;
	}
}

int32_t DuelNativeCompactKernel::resolve_action_card_reference(
	CardRefOpcode reference,
	const EventContext &event_context,
	const ActionContext &action_context,
	const ActionExecutionState &execution_state
) const {
	if (reference == CardRefOpcode::SELECTED_CARD) return action_context.selected_card_index;
	if (reference == CardRefOpcode::TRIGGER_CARD) return event_context.trigger_card_index;
	if (reference == CardRefOpcode::ABILITY_SOURCE) return action_context.ability_source_card_index;
	if (reference == CardRefOpcode::ATTACKER_CARD) return event_context.attacker_card_index;
	if (reference == CardRefOpcode::LAST_SUMMONED_CARD) return execution_state.last_summoned_card_index;
	return -1;
}

int32_t DuelNativeCompactKernel::initial_cell_for_reference(
	CardRefOpcode reference,
	const EventContext &event_context,
	const ActionContext &action_context,
	const ActionExecutionState &execution_state
) const {
	if (reference == CardRefOpcode::ABILITY_SOURCE) {
		return action_context.ability_source_zone == 0
			? action_context.ability_source_logical_index
			: action_context.ability_source_cell;
	}
	if (reference == CardRefOpcode::SELECTED_CARD) {
		if (action_context.selected_card_zone == 0) {
			return action_context.selected_card_logical_index;
		}
		return action_context.action_subject_card_index == action_context.selected_card_index
			&& action_context.action_subject_zone == 0
			? action_context.action_subject_logical_index
			: -1;
	}
	if (reference == CardRefOpcode::TRIGGER_CARD) {
		return event_context.trigger_zone == 0
			? event_context.trigger_logical_index
			: event_context.trigger_cell;
	}
	if (reference == CardRefOpcode::ATTACKER_CARD) return event_context.attacker_cell;
	if (reference == CardRefOpcode::LAST_SUMMONED_CARD) return execution_state.last_summoned_cell;
	return -1;
}

int32_t DuelNativeCompactKernel::resolve_relative_owner(
	const NativeState &value,
	RelativeOwnerOpcode reference,
	const ActionContext &action_context,
	int32_t referenced_card_index
) const {
	if (reference == RelativeOwnerOpcode::ABILITY_SOURCE) return action_context.ability_source_owner;
	if (reference == RelativeOwnerOpcode::OPPONENT_OF_ABILITY_SOURCE) {
		return action_context.ability_source_owner == 1 || action_context.ability_source_owner == 2
			? other_owner(action_context.ability_source_owner)
			: 0;
	}
	if (referenced_card_index < 0) referenced_card_index = action_context.action_subject_card_index;
	if (
		referenced_card_index < 0
		|| referenced_card_index >= static_cast<int32_t>(value.card_instance_ids.size())
	) return 0;
	if (reference == RelativeOwnerOpcode::CARD_ORIGINAL) {
		return value.card_original_owners[referenced_card_index];
	}
	if (reference == RelativeOwnerOpcode::CARD_CURRENT) {
		int32_t zone = -1;
		int32_t owner = 0;
		int32_t logical_index = -1;
		return locate_card(value, referenced_card_index, zone, owner, logical_index) ? owner : 0;
	}
	return 0;
}

const DuelNativeCompactKernel::FreshCardPrototype *DuelNativeCompactKernel::find_fresh_card_prototype(
	const NativeState &value,
	const StringName &card_id
) const {
	for (const FreshCardPrototype &prototype : value.fresh_card_prototypes) {
		if (prototype.card_id == card_id) return &prototype;
	}
	return nullptr;
}

StringName DuelNativeCompactKernel::make_generated_instance_id(
	const NativeState &value,
	const StringName &card_id
) const {
	auto located = [&](const StringName &candidate) {
		for (const int32_t card_index : value.board_card_indices) {
			if (card_index >= 0 && value.card_instance_ids[card_index] == candidate) return true;
		}
		for (const std::vector<int32_t> &zone : value.zones) {
			for (const int32_t card_index : zone) {
				if (value.card_instance_ids[card_index] == candidate) return true;
			}
		}
		return false;
	};
	for (int64_t serial = 1; ; ++serial) {
		const StringName candidate(
			String("generated_") + String(card_id) + "_" + String::num_int64(serial)
		);
		if (!located(candidate)) return candidate;
	}
}

int32_t DuelNativeCompactKernel::append_fresh_board_card(
	NativeState &value,
	const StringName &card_id,
	const StringName &instance_id,
	int32_t owner_id,
	String &reason
) const {
	const FreshCardPrototype *prototype_pointer = find_fresh_card_prototype(value, card_id);
	if (prototype_pointer == nullptr) {
		reason = "Summoned card has no fresh-card prototype";
		return -1;
	}
	const FreshCardPrototype prototype = *prototype_pointer;
	if (
		prototype.active_ability_set_index < 0
		|| prototype.active_ability_set_index >= static_cast<int32_t>(compiled_ability_sets.size())
	) {
		reason = "Summoned card prototype has no compiled ability set";
		return -1;
	}
	const int32_t card_index = static_cast<int32_t>(value.card_instance_ids.size());
	value.card_instance_ids.push_back(instance_id);
	value.card_template_indices.push_back(prototype.template_index);
	static constexpr uint8_t fresh_runtime_flags = (
		(1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5)
	);
	value.card_runtime_flags.push_back(fresh_runtime_flags);
	for (const int32_t power : prototype.powers) value.card_powers.push_back(power);
	value.card_original_owners.push_back(static_cast<uint8_t>(owner_id));
	value.card_ki.push_back(prototype.ki);
	value.card_active_ability_set_indices.push_back(prototype.active_ability_set_index);
	std::vector<RuntimeAbilityEntry> runtime_entries;
	const std::vector<int32_t> &ability_indices = compiled_ability_sets[
		prototype.active_ability_set_index
	].ability_pool_indices;
	runtime_entries.reserve(ability_indices.size());
	for (const int32_t compiled_ability_index : ability_indices) {
		RuntimeAbilityEntry entry;
		entry.compiled_ability_index = compiled_ability_index;
		entry.handle = value.next_ability_handle++;
		runtime_entries.push_back(entry);
	}
	value.card_runtime_abilities.push_back(runtime_entries);
	value.card_runtime_suppression_batches.push_back({});
	value.card_reveal_codes.push_back(static_cast<uint8_t>(owner_id));
	value.card_suppression_set_indices.push_back(-1);
	value.card_hand_slots.push_back(-1);
	value.card_ids.push_back(card_id);
	return card_index;
}

int32_t DuelNativeCompactKernel::append_perfect_copy_board_card(
	NativeState &value,
	int32_t copied_card_index,
	const StringName &instance_id,
	String &reason
) const {
	if (
		copied_card_index < 0
		|| copied_card_index >= static_cast<int32_t>(value.card_instance_ids.size())
	) {
		reason = "Perfect-copy summon has no copied runtime card";
		return -1;
	}
	const int32_t card_index = static_cast<int32_t>(value.card_instance_ids.size());
	value.card_instance_ids.push_back(instance_id);
	value.card_template_indices.push_back(value.card_template_indices[copied_card_index]);
	value.card_runtime_flags.push_back(
		value.card_runtime_flags[copied_card_index] & static_cast<uint8_t>(~(1 << 7))
	);
	for (int32_t direction = 0; direction < 4; ++direction) {
		value.card_powers.push_back(value.card_powers[copied_card_index * 4 + direction]);
	}
	value.card_original_owners.push_back(value.card_original_owners[copied_card_index]);
	value.card_ki.push_back(value.card_ki[copied_card_index]);
	value.card_active_ability_set_indices.push_back(
		value.card_active_ability_set_indices[copied_card_index]
	);
	std::vector<RuntimeAbilityEntry> runtime_entries;
	runtime_entries.reserve(value.card_runtime_abilities[copied_card_index].size());
	for (const RuntimeAbilityEntry &copied_entry : value.card_runtime_abilities[copied_card_index]) {
		RuntimeAbilityEntry entry;
		entry.compiled_ability_index = copied_entry.compiled_ability_index;
		entry.handle = value.next_ability_handle++;
		runtime_entries.push_back(entry);
	}
	value.card_runtime_abilities.push_back(runtime_entries);
	std::vector<RuntimeSuppressionBatch> suppression_batches;
	suppression_batches.reserve(value.card_runtime_suppression_batches[copied_card_index].size());
	for (const RuntimeSuppressionBatch &copied_batch : value.card_runtime_suppression_batches[copied_card_index]) {
		RuntimeSuppressionBatch batch;
		batch.expires_after_turn = copied_batch.expires_after_turn;
		batch.entries.reserve(copied_batch.entries.size());
		for (const RuntimeSuppressionEntry &copied_entry : copied_batch.entries) {
			RuntimeSuppressionEntry entry;
			entry.original_index = copied_entry.original_index;
			entry.compiled_ability_index = copied_entry.compiled_ability_index;
			entry.handle = value.next_ability_handle++;
			batch.entries.push_back(entry);
		}
		suppression_batches.push_back(batch);
	}
	value.card_runtime_suppression_batches.push_back(suppression_batches);
	value.card_reveal_codes.push_back(value.card_reveal_codes[copied_card_index]);
	value.card_suppression_set_indices.push_back(
		value.card_suppression_set_indices[copied_card_index]
	);
	value.card_hand_slots.push_back(-1);
	value.card_ids.push_back(value.card_ids[copied_card_index]);
	return card_index;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::summon_card(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	ActionExecutionState &execution_state,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	const int32_t source_owner = action_context.ability_source_owner;
	if (source_owner != 1 && source_owner != 2) return ActionOutcome::NO_EFFECT;
	const int32_t source_card_index = action_context.ability_source_card_index;
	int32_t source_cell = find_board_card(value, source_card_index, execution_state.current_source_cell);

	int32_t referenced_card_index = -1;
	int32_t existing_zone = -1;
	int32_t existing_owner = 0;
	int32_t existing_logical_index = -1;
	StringName card_id;
	if (action.card_spec == CardSpecOpcode::TOP_DISCARD) {
		existing_owner = resolve_relative_owner(value, action.summon_owner, action_context);
		if (existing_owner != 1 && existing_owner != 2) return ActionOutcome::NO_EFFECT;
		std::vector<int32_t> &discard = value.zones[existing_owner + 3];
		if (discard.empty()) return ActionOutcome::NO_EFFECT;
		referenced_card_index = discard.back();
		if (!locate_card(value, referenced_card_index, existing_zone, existing_owner, existing_logical_index)) {
			return ActionOutcome::NO_EFFECT;
		}
	} else {
		referenced_card_index = resolve_action_card_reference(
			action.summon_card_ref,
			event_context,
			action_context,
			execution_state
		);
		if (
			referenced_card_index < 0
			|| referenced_card_index >= static_cast<int32_t>(value.card_ids.size())
		) return ActionOutcome::NO_EFFECT;
		if (action.card_spec == CardSpecOpcode::EXISTING_REFERENCE) {
			if (!locate_card(value, referenced_card_index, existing_zone, existing_owner, existing_logical_index)) {
				return ActionOutcome::NO_EFFECT;
			}
		}
	}
	card_id = value.card_ids[referenced_card_index];
	if (card_id.is_empty()) return ActionOutcome::NO_EFFECT;

	int32_t target_cell = -1;
	if (action.cell_spec == CellSpecOpcode::INITIAL_CARD_CELL) {
		target_cell = initial_cell_for_reference(
			action.summon_cell_card_ref,
			event_context,
			action_context,
			execution_state
		);
	} else if (action.cell_spec == CellSpecOpcode::ACTIVATION_TARGET) {
		if (action_context.activation_target_kind != StringName("board_cell")) {
			return ActionOutcome::NO_EFFECT;
		}
		target_cell = action_context.activation_target_index;
	} else if (
		action.cell_spec == CellSpecOpcode::FIRST_ADJACENT_EMPTY
		|| action.cell_spec == CellSpecOpcode::FIRST_ADJACENT_OR_ANY_EMPTY
	) {
		const int32_t anchor_card_index = resolve_action_card_reference(
			action.summon_cell_card_ref,
			event_context,
			action_context,
			execution_state
		);
		const int32_t anchor_cell = find_board_card(value, anchor_card_index);
		if (anchor_cell < 0) return ActionOutcome::NO_EFFECT;
		std::vector<int32_t> empty_neighbors;
		for (int32_t direction = 0; direction < 4; ++direction) {
			const int32_t neighbor = neighbor_index(anchor_cell, direction);
			if (neighbor >= 0 && value.board_card_indices[neighbor] < 0) empty_neighbors.push_back(neighbor);
		}
		if (!empty_neighbors.empty()) {
			std::sort(empty_neighbors.begin(), empty_neighbors.end());
			target_cell = empty_neighbors.front();
		} else if (action.cell_spec == CellSpecOpcode::FIRST_ADJACENT_OR_ANY_EMPTY) {
			for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
				if (value.board_card_indices[cell] < 0) {
					target_cell = static_cast<int32_t>(cell);
					break;
				}
			}
		}
	} else if (action.cell_spec == CellSpecOpcode::FIRST_EMPTY_ADJACENT_TO_ENEMY) {
		const int32_t reference_owner = resolve_relative_owner(
			value,
			action.summon_owner,
			action_context
		);
		if (reference_owner != 1 && reference_owner != 2) return ActionOutcome::NO_EFFECT;
		for (size_t cell = 0; cell < value.board_card_indices.size() && target_cell < 0; ++cell) {
			if (value.board_card_indices[cell] >= 0) continue;
			for (int32_t direction = 0; direction < 4; ++direction) {
				const int32_t neighbor = neighbor_index(static_cast<int32_t>(cell), direction);
				if (
					neighbor >= 0
					&& value.board_card_indices[neighbor] >= 0
					&& value.board_owners[neighbor] != reference_owner
				) {
					target_cell = static_cast<int32_t>(cell);
					break;
				}
			}
		}
	}
	if (
		target_cell < 0
		|| target_cell >= static_cast<int32_t>(value.board_card_indices.size())
		|| value.board_card_indices[target_cell] >= 0
	) return ActionOutcome::NO_EFFECT;

	int32_t summoned_card_index = referenced_card_index;
	StringName instance_id;
	StringName from_hand_instance_id;
	StringName from_removed_instance_id;
	StringName from_discard_instance_id;
	int32_t previous_hand_size = -1;
	if (action.card_spec == CardSpecOpcode::EXISTING_REFERENCE || action.card_spec == CardSpecOpcode::TOP_DISCARD) {
		if (existing_zone != 1 && existing_zone != 3 && existing_zone != 4) return ActionOutcome::NO_EFFECT;
		if ((existing_zone == 1 || existing_zone == 4) && existing_owner != source_owner) {
			return ActionOutcome::NO_EFFECT;
		}
		const int32_t zone_index = existing_zone == 1
			? existing_owner - 1
			: (existing_zone == 3 ? existing_owner + 3 : existing_owner + 5);
		std::vector<int32_t> &zone = value.zones[zone_index];
		if (
			existing_logical_index < 0
			|| existing_logical_index >= static_cast<int32_t>(zone.size())
			|| zone[existing_logical_index] != summoned_card_index
		) return ActionOutcome::NO_EFFECT;
		if (existing_zone == 1) previous_hand_size = static_cast<int32_t>(zone.size());
		zone.erase(zone.begin() + existing_logical_index);
		instance_id = value.card_instance_ids[summoned_card_index];
		if (existing_zone == 1) {
			from_hand_instance_id = instance_id;
			value.card_runtime_flags[summoned_card_index] &= static_cast<uint8_t>(~(1 << 7));
			value.card_hand_slots[summoned_card_index] = -1;
		} else if (existing_zone == 3) {
			from_discard_instance_id = instance_id;
		} else {
			from_removed_instance_id = instance_id;
		}
	} else {
		instance_id = make_generated_instance_id(value, card_id);
		String append_reason;
		summoned_card_index = action.card_spec == CardSpecOpcode::PERFECT_COPY
			? append_perfect_copy_board_card(value, referenced_card_index, instance_id, append_reason)
			: append_fresh_board_card(value, card_id, instance_id, source_owner, append_reason);
		if (summoned_card_index < 0) {
			if (
				action.card_spec != CardSpecOpcode::PERFECT_COPY
				&& find_fresh_card_prototype(value, card_id) == nullptr
			) return ActionOutcome::NO_EFFECT;
			resolution.reason = append_reason;
			return ActionOutcome::UNSUPPORTED;
		}
	}

	value.board_card_indices[target_cell] = summoned_card_index;
	value.board_owners[target_cell] = static_cast<uint8_t>(source_owner);
	if (target_cell < value.board_slot_extras.size()) value.board_slot_extras[target_cell] = Dictionary();
	Dictionary summoned_event;
	summoned_event["type"] = StringName("card_summoned");
	summoned_event["source_cell"] = source_cell;
	summoned_event["source_instance_id"] = source_card_index >= 0
		? value.card_instance_ids[source_card_index]
		: StringName();
	summoned_event["target_cell"] = target_cell;
	summoned_event["owner_id"] = source_owner;
	summoned_event["card_id"] = card_id;
	summoned_event["instance_id"] = instance_id;
	if (include_presentation_payloads) {
		summoned_event["card"] = restore_runtime_card(value, summoned_card_index);
	}
	summoned_event["from_hand_instance_id"] = from_hand_instance_id;
	summoned_event["from_removed_instance_id"] = from_removed_instance_id;
	summoned_event["from_discard_instance_id"] = from_discard_instance_id;
	const StringName summon_reason = from_discard_instance_id.is_empty()
		? StringName("ability_fresh_copy")
		: StringName("ability_discard_summon");
	summoned_event["summon_reason"] = summon_reason;

	SummonRequest request;
	request.summon_cell = target_cell;
	request.card_index = summoned_card_index;
	request.owner_id = source_owner;
	request.summon_reason = summon_reason;
	request.attack_reason = StringName("generated_summon_standard_attack");
	request.buffered_placement_events.append(summoned_event);
	if (previous_hand_size >= 0) {
		Resolution hand_change = resolve_difficulty_hand_change(
			value,
			source_owner,
			previous_hand_size,
			static_cast<int32_t>(value.zones[source_owner - 1].size()),
			target_cell,
			exile_stack
		);
		if (!hand_change.supported) {
			resolution.reason = hand_change.reason;
			return ActionOutcome::UNSUPPORTED;
		}
		request.buffered_placement_events.append_array(hand_change.events);
		hand_change.events = Array();
		append_resolution(resolution, hand_change);
	}
	Resolution nested = resolve_summon_lifecycle(value, request, exile_stack);
	if (!nested.supported) {
		resolution.reason = nested.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	append_resolution(resolution, nested);
	execution_state.last_summoned_card_index = summoned_card_index;
	execution_state.last_summoned_cell = target_cell;
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::resummon_card_in_place(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	ActionExecutionState &execution_state,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	const int32_t source_card_index = action_context.action_subject_card_index;
	const int32_t source_owner = action_context.action_subject_owner;
	const int32_t source_cell = find_board_card(value, source_card_index, execution_state.current_source_cell);
	if (source_cell < 0 || value.board_owners[source_cell] != source_owner) return ActionOutcome::NO_EFFECT;
	const int32_t target_card_index = resolve_action_card_reference(
		action.card_ref,
		event_context,
		action_context,
		execution_state
	);
	const int32_t target_cell = find_board_card(value, target_card_index);
	if (target_cell < 0) return ActionOutcome::NO_EFFECT;
	const StringName card_id = value.card_ids[target_card_index];
	const StringName old_instance_id = value.card_instance_ids[target_card_index];
	const StringName new_instance_id = make_generated_instance_id(value, card_id);
	value.board_card_indices[target_cell] = -1;
	value.board_owners[target_cell] = 0;
	if (target_cell < value.board_slot_extras.size()) value.board_slot_extras[target_cell] = Dictionary();

	Dictionary departed;
	departed["type"] = StringName("card_departed_for_resummon");
	departed["source_cell"] = source_cell;
	departed["source_instance_id"] = value.card_instance_ids[source_card_index];
	departed["target_cell"] = target_cell;
	departed["owner_id"] = source_owner;
	departed["old_instance_id"] = old_instance_id;
	departed["card_id"] = card_id;
	resolution.events.append(departed);

	String append_reason;
	const int32_t new_card_index = append_fresh_board_card(
		value,
		card_id,
		new_instance_id,
		source_owner,
		append_reason
	);
	if (new_card_index < 0) {
		resolution.reason = append_reason;
		return ActionOutcome::UNSUPPORTED;
	}
	value.board_card_indices[target_cell] = new_card_index;
	value.board_owners[target_cell] = static_cast<uint8_t>(source_owner);
	const int32_t summon_source_cell = find_board_card(
		value,
		source_card_index,
		source_cell
	);
	Dictionary summoned_event;
	summoned_event["type"] = StringName("card_summoned");
	summoned_event["source_cell"] = summon_source_cell;
	summoned_event["source_instance_id"] = value.card_instance_ids[source_card_index];
	summoned_event["target_cell"] = target_cell;
	summoned_event["owner_id"] = source_owner;
	summoned_event["card_id"] = card_id;
	summoned_event["instance_id"] = new_instance_id;
	if (include_presentation_payloads) {
		summoned_event["card"] = restore_runtime_card(value, new_card_index);
	}
	summoned_event["from_hand_instance_id"] = StringName();
	summoned_event["from_removed_instance_id"] = StringName();
	summoned_event["from_discard_instance_id"] = StringName();
	summoned_event["summon_reason"] = StringName("ability_resummon_in_place");
	SummonRequest request;
	request.summon_cell = target_cell;
	request.card_index = new_card_index;
	request.owner_id = source_owner;
	request.summon_reason = StringName("ability_resummon_in_place");
	request.attack_reason = StringName("generated_summon_standard_attack");
	request.buffered_placement_events.append(summoned_event);
	Resolution nested = resolve_summon_lifecycle(value, request, exile_stack);
	if (!nested.supported) {
		resolution.reason = nested.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	append_resolution(resolution, nested);
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::depart_card_for_resummon(
	NativeState &value,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	ActionExecutionState &execution_state,
	Resolution &resolution
) const {
	const int32_t target_card_index = resolve_action_card_reference(
		action.card_ref,
		event_context,
		action_context,
		execution_state
	);
	const int32_t target_cell = find_board_card(value, target_card_index);
	if (target_cell < 0) return ActionOutcome::NO_EFFECT;
	const int32_t target_owner = value.board_owners[target_cell];
	value.board_card_indices[target_cell] = -1;
	value.board_owners[target_cell] = 0;
	if (target_cell < value.board_slot_extras.size()) value.board_slot_extras[target_cell] = Dictionary();
	Dictionary departed;
	departed["type"] = StringName("card_departed_for_resummon");
	departed["source_cell"] = action_context.ability_source_cell;
	departed["source_instance_id"] = action_context.ability_source_card_index >= 0
		? value.card_instance_ids[action_context.ability_source_card_index]
		: StringName();
	departed["target_cell"] = target_cell;
	departed["owner_id"] = target_owner;
	departed["old_instance_id"] = value.card_instance_ids[target_card_index];
	departed["card_id"] = value.card_ids[target_card_index];
	resolution.events.append(departed);
	execution_state.current_source_cell = find_board_card(
		value,
		action_context.action_subject_card_index,
		execution_state.current_source_cell
	);
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::return_card_to_hand(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	int32_t target_card_index = -1;
	if (action.card_ref == CardRefOpcode::SELECTED_CARD) {
		target_card_index = action_context.selected_card_index;
	} else if (action.card_ref == CardRefOpcode::TRIGGER_CARD) {
		target_card_index = event_context.trigger_card_index;
	} else if (action.card_ref == CardRefOpcode::ABILITY_SOURCE) {
		target_card_index = action_context.ability_source_card_index;
	} else if (action.card_ref == CardRefOpcode::ATTACKER_CARD) {
		target_card_index = event_context.attacker_card_index;
	} else {
		return ActionOutcome::UNSUPPORTED;
	}
	if (
		target_card_index < 0
		|| target_card_index >= static_cast<int32_t>(value.card_instance_ids.size())
	) {
		return ActionOutcome::NO_EFFECT;
	}

	int32_t target_zone = -1;
	int32_t target_owner = 0;
	int32_t target_cell = -1;
	if (
		!locate_card(value, target_card_index, target_zone, target_owner, target_cell)
		|| (action.preserve_instance ? target_zone != 3 : target_zone != 0)
	) {
		return ActionOutcome::NO_EFFECT;
	}

	int32_t recipient_owner = 0;
	if (action.recipient_owner == RelativeOwnerOpcode::CARD_CURRENT) {
		recipient_owner = target_owner;
	} else if (action.recipient_owner == RelativeOwnerOpcode::CARD_ORIGINAL) {
		recipient_owner = value.card_original_owners[target_card_index];
	} else if (action.recipient_owner == RelativeOwnerOpcode::ABILITY_SOURCE) {
		recipient_owner = action_context.ability_source_owner;
	} else if (action.recipient_owner == RelativeOwnerOpcode::OPPONENT_OF_ABILITY_SOURCE) {
		recipient_owner = other_owner(action_context.ability_source_owner);
	} else {
		return ActionOutcome::UNSUPPORTED;
	}
	if (recipient_owner != 1 && recipient_owner != 2) {
		return ActionOutcome::NO_EFFECT;
	}

	const int32_t source_current_cell = [&]() {
		const int32_t current = find_board_card(
			value,
			action_context.ability_source_card_index,
			action_context.ability_source_cell
		);
		return current >= 0 ? current : action_context.ability_source_cell;
	}();
	std::vector<int32_t> &recipient_hand = value.zones[recipient_owner - 1];
	const int32_t recipient_previous_hand_size = static_cast<int32_t>(recipient_hand.size());
	if (recipient_hand.size() >= 5) {
		const int64_t previous_event_count = resolution.events.size();
		if (!exile_card(
			value,
			target_card_index,
			source_current_cell,
			action_context.ability_source_card_index,
			target_card_index == action_context.ability_source_card_index,
			StringName("return_to_full_hand"),
			event_context,
			exile_stack,
			resolution,
			action_context.record_direct_board_changes
		)) {
			return ActionOutcome::UNSUPPORTED;
		}
		return resolution.events.size() > previous_event_count
			? ActionOutcome::APPLIED
			: ActionOutcome::NO_EFFECT;
	}

	const StringName card_id = value.card_ids[target_card_index];
	if (action.preserve_instance) {
		std::vector<int32_t> &discard_pile = value.zones[target_owner + 3];
		if (
			target_cell < 0
			|| target_cell >= static_cast<int32_t>(discard_pile.size())
			|| discard_pile[target_cell] != target_card_index
		) return ActionOutcome::NO_EFFECT;
		const int32_t hand_slot = leftmost_empty_hand_slot(value, recipient_owner);
		if (hand_slot < 0) return ActionOutcome::NO_EFFECT;
		discard_pile.erase(discard_pile.begin() + target_cell);
		value.card_runtime_flags[target_card_index] |= static_cast<uint8_t>(1 << 7);
		value.card_hand_slots[target_card_index] = hand_slot;
		recipient_hand.push_back(target_card_index);

		const int32_t observer_owner = other_owner(recipient_owner);
		uint8_t &reveal_code = value.card_reveal_codes[target_card_index];
		const bool already_revealed = (
			(observer_owner == 1 && (reveal_code == 1 || reveal_code == 3 || reveal_code == 4))
			|| (observer_owner == 2 && (reveal_code == 2 || reveal_code == 3 || reveal_code == 4))
		);
		if (!already_revealed) {
			if (observer_owner == 1) reveal_code = reveal_code == 2 ? 4 : 1;
			else reveal_code = reveal_code == 1 ? 3 : 2;
		}
		const StringName source_instance_id = (
			action_context.ability_source_card_index >= 0
			? value.card_instance_ids[action_context.ability_source_card_index]
			: StringName()
		);
		Dictionary returned;
		returned["type"] = StringName("card_returned_to_hand");
		returned["source_cell"] = source_current_cell;
		returned["source_instance_id"] = source_instance_id;
		returned["target_cell"] = -1;
		returned["old_instance_id"] = value.card_instance_ids[target_card_index];
		returned["owner_id"] = recipient_owner;
		returned["card_id"] = card_id;
		returned["instance_id"] = value.card_instance_ids[target_card_index];
		returned["logical_hand_index"] = static_cast<int32_t>(recipient_hand.size()) - 1;
		returned["hand_slot_index"] = hand_slot;
		if (include_presentation_payloads) {
			returned["card"] = restore_runtime_card(value, target_card_index);
		}
		resolution.events.append(returned);
		if (!already_revealed) {
			Dictionary revealed;
			revealed["type"] = StringName("card_revealed");
			revealed["source_cell"] = source_current_cell;
			revealed["source_instance_id"] = source_instance_id;
			revealed["owner_id"] = recipient_owner;
			revealed["observer_owner_id"] = observer_owner;
			revealed["card_id"] = card_id;
			revealed["instance_id"] = value.card_instance_ids[target_card_index];
			revealed["logical_hand_index"] = static_cast<int32_t>(recipient_hand.size()) - 1;
			resolution.events.append(revealed);
		}
		Resolution hand_change = resolve_difficulty_hand_change(
			value,
			recipient_owner,
			recipient_previous_hand_size,
			static_cast<int32_t>(recipient_hand.size()),
			source_current_cell,
			exile_stack
		);
		if (!hand_change.supported) {
			resolution.reason = hand_change.reason;
			return ActionOutcome::UNSUPPORTED;
		}
		append_resolution(resolution, hand_change);
		return ActionOutcome::APPLIED;
	}

	const FreshCardPrototype *prototype = nullptr;
	for (const FreshCardPrototype &candidate : value.fresh_card_prototypes) {
		if (candidate.card_id == card_id) {
			prototype = &candidate;
			break;
		}
	}
	if (prototype == nullptr) {
		return ActionOutcome::NO_EFFECT;
	}
	if (
		prototype->active_ability_set_index < 0
		|| prototype->active_ability_set_index >= static_cast<int32_t>(compiled_ability_sets.size())
	) {
		resolution.reason = "Return card prototype has no compiled ability set";
		return ActionOutcome::UNSUPPORTED;
	}

	auto instance_id_is_located = [&](const StringName &candidate) {
		for (const int32_t card_index : value.board_card_indices) {
			if (card_index >= 0 && value.card_instance_ids[card_index] == candidate) return true;
		}
		for (const std::vector<int32_t> &zone : value.zones) {
			for (const int32_t card_index : zone) {
				if (value.card_instance_ids[card_index] == candidate) return true;
			}
		}
		return false;
	};
	StringName new_instance_id;
	for (int64_t serial = 1; ; ++serial) {
		const StringName candidate(
			String("generated_") + String(card_id) + "_" + String::num_int64(serial)
		);
		if (!instance_id_is_located(candidate)) {
			new_instance_id = candidate;
			break;
		}
	}
	const int32_t hand_slot = leftmost_empty_hand_slot(value, recipient_owner);
	if (hand_slot < 0) return ActionOutcome::NO_EFFECT;

	value.board_card_indices[target_cell] = -1;
	value.board_owners[target_cell] = 0;
	if (target_cell < value.board_slot_extras.size()) {
		value.board_slot_extras[target_cell] = Dictionary();
	}

	const int32_t new_card_index = static_cast<int32_t>(value.card_instance_ids.size());
	value.card_instance_ids.push_back(new_instance_id);
	value.card_template_indices.push_back(prototype->template_index);
	static constexpr uint8_t fresh_runtime_flags = (
		(1 << 0) | (1 << 1) | (1 << 2) | (1 << 3)
		| (1 << 4) | (1 << 5) | (1 << 7)
	);
	value.card_runtime_flags.push_back(fresh_runtime_flags);
	for (const int32_t power : prototype->powers) value.card_powers.push_back(power);
	value.card_original_owners.push_back(static_cast<uint8_t>(recipient_owner));
	value.card_ki.push_back(prototype->ki);
	value.card_active_ability_set_indices.push_back(prototype->active_ability_set_index);
	std::vector<RuntimeAbilityEntry> runtime_entries;
	const std::vector<int32_t> &ability_indices = compiled_ability_sets[
		prototype->active_ability_set_index
	].ability_pool_indices;
	runtime_entries.reserve(ability_indices.size());
	for (const int32_t compiled_ability_index : ability_indices) {
		RuntimeAbilityEntry entry;
		entry.compiled_ability_index = compiled_ability_index;
		entry.handle = value.next_ability_handle++;
		runtime_entries.push_back(entry);
	}
	value.card_runtime_abilities.push_back(runtime_entries);
	value.card_runtime_suppression_batches.push_back({});
	value.card_reveal_codes.push_back(static_cast<uint8_t>(recipient_owner == 1 ? 3 : 4));
	value.card_suppression_set_indices.push_back(-1);
	value.card_hand_slots.push_back(hand_slot);
	value.card_ids.push_back(card_id);
	recipient_hand.push_back(new_card_index);

	const StringName source_instance_id = (
		action_context.ability_source_card_index >= 0
		&& action_context.ability_source_card_index < static_cast<int32_t>(value.card_instance_ids.size())
		? value.card_instance_ids[action_context.ability_source_card_index]
		: StringName()
	);
	Dictionary returned;
	returned["type"] = StringName("card_returned_to_hand");
	returned["source_cell"] = source_current_cell;
	returned["source_instance_id"] = source_instance_id;
	returned["target_cell"] = target_cell;
	returned["old_instance_id"] = value.card_instance_ids[target_card_index];
	returned["owner_id"] = recipient_owner;
	returned["card_id"] = card_id;
	returned["instance_id"] = new_instance_id;
	returned["logical_hand_index"] = static_cast<int32_t>(recipient_hand.size()) - 1;
	returned["hand_slot_index"] = hand_slot;
	if (include_presentation_payloads) {
		returned["card"] = restore_runtime_card(value, new_card_index);
	}
	resolution.events.append(returned);

	Dictionary revealed;
	revealed["type"] = StringName("card_revealed");
	revealed["source_cell"] = source_current_cell;
	revealed["source_instance_id"] = source_instance_id;
	revealed["owner_id"] = recipient_owner;
	revealed["observer_owner_id"] = other_owner(recipient_owner);
	revealed["card_id"] = card_id;
	revealed["instance_id"] = new_instance_id;
	revealed["logical_hand_index"] = static_cast<int32_t>(recipient_hand.size()) - 1;
	resolution.events.append(revealed);
	Resolution hand_change = resolve_difficulty_hand_change(
		value,
		recipient_owner,
		recipient_previous_hand_size,
		static_cast<int32_t>(recipient_hand.size()),
		source_current_cell,
		exile_stack
	);
	if (!hand_change.supported) {
		resolution.reason = hand_change.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	append_resolution(resolution, hand_change);
	return ActionOutcome::APPLIED;
}


} // namespace godot
