#include "duel_native_compact_kernel_internal.h"

namespace godot {
using namespace duel_native_internal;

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::resolve_movement_event(
	NativeState &value,
	const StringName &event_id,
	int32_t source_cell,
	int32_t origin_cell,
	int32_t target_cell,
	int32_t moving_card_index,
	int32_t moving_owner,
	std::vector<int32_t> &exile_stack
) const {
	EventContext context;
	context.trigger_cell = source_cell;
	context.trigger_card_index = moving_card_index;
	context.trigger_owner = moving_owner;
	context.trigger_zone = 0;
	context.trigger_logical_index = source_cell;
	context.trigger_was_on_board = true;
	context.moving_source_cell = source_cell;
	context.moving_origin_cell = origin_cell;
	context.moving_target_cell = target_cell;
	context.moving_card_index = moving_card_index;
	context.moving_owner = moving_owner;
	return resolve_event(value, event_id, context, exile_stack);
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::move_card_between_cells(
	NativeState &value,
	int32_t source_cell,
	int32_t origin_cell,
	int32_t target_cell,
	int32_t moving_card_index,
	int32_t moving_owner,
	bool resolve_before_event,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	if (
		source_cell < 0
		|| target_cell < 0
		|| source_cell >= static_cast<int32_t>(value.board_card_indices.size())
		|| target_cell >= static_cast<int32_t>(value.board_card_indices.size())
		|| value.board_card_indices[source_cell] != moving_card_index
		|| value.board_owners[source_cell] != moving_owner
		|| value.board_card_indices[target_cell] >= 0
	) return ActionOutcome::NO_EFFECT;

	Resolution movement_resolution;
	if (resolve_before_event) {
		Resolution before = resolve_movement_event(
			value,
			StringName("card_before_moved"),
			source_cell,
			origin_cell,
			target_cell,
			moving_card_index,
			moving_owner,
			exile_stack
		);
		if (!before.supported) {
			resolution.reason = before.reason;
			return ActionOutcome::UNSUPPORTED;
		}
		append_resolution(movement_resolution, before);
		if (
			find_board_card(value, moving_card_index, source_cell) != source_cell
			|| value.board_owners[source_cell] != moving_owner
			|| value.board_card_indices[target_cell] >= 0
		) {
			append_resolution(resolution, movement_resolution);
			return resolution_has_output(movement_resolution)
				? ActionOutcome::APPLIED
				: ActionOutcome::NO_EFFECT;
		}
	}

	const Variant moving_extra = value.board_slot_extras[source_cell];
	value.board_card_indices[source_cell] = -1;
	value.board_owners[source_cell] = 0;
	value.board_slot_extras[source_cell] = Dictionary();
	value.board_card_indices[target_cell] = moving_card_index;
	value.board_owners[target_cell] = static_cast<uint8_t>(moving_owner);
	value.board_slot_extras[target_cell] = moving_extra;

	Dictionary moved;
	moved["type"] = StringName("card_moved");
	moved["source_cell"] = source_cell;
	moved["target_cell"] = target_cell;
	moved["owner_id"] = moving_owner;
	moved["instance_id"] = value.card_instance_ids[moving_card_index];
	movement_resolution.events.append(moved);
	Resolution after = resolve_movement_event(
		value,
		StringName("card_after_moved"),
		target_cell,
		origin_cell,
		target_cell,
		moving_card_index,
		moving_owner,
		exile_stack
	);
	if (!after.supported) {
		resolution.reason = after.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	append_resolution(movement_resolution, after);
	append_resolution(resolution, movement_resolution);
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::swap_action_subject_with_ability_source(
	NativeState &value,
	const EventGroup &group,
	const EventContext &event_context,
	const ActionContext &action_context,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	(void)event_context;
	const int32_t source_card_index = group.source_card_index;
	const int32_t target_card_index = action_context.action_subject_card_index;
	if (
		source_card_index < 0
		|| target_card_index < 0
		|| source_card_index == target_card_index
	) return ActionOutcome::NO_EFFECT;
	const int32_t source_owner = action_context.ability_source_owner;
	const int32_t target_owner = action_context.action_subject_owner;
	int32_t source_cell = find_board_card(value, source_card_index, group.source_cell);
	int32_t target_cell = find_board_card(
		value,
		target_card_index,
		action_context.action_subject_logical_index
	);
	if (
		source_cell < 0
		|| target_cell < 0
		|| value.board_owners[source_cell] != source_owner
		|| value.board_owners[target_cell] != target_owner
	) return ActionOutcome::NO_EFFECT;
	bool adjacent = false;
	for (int32_t direction = 0; direction < 4; ++direction) {
		if (neighbor_index(source_cell, direction) == target_cell) {
			adjacent = true;
			break;
		}
	}
	if (!adjacent) return ActionOutcome::NO_EFFECT;

	Resolution source_before = resolve_movement_event(
		value,
		StringName("card_before_moved"),
		source_cell,
		source_cell,
		target_cell,
		source_card_index,
		source_owner,
		exile_stack
	);
	if (!source_before.supported) {
		resolution.reason = source_before.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	if (
		find_board_card(value, source_card_index, source_cell) != source_cell
		|| value.board_owners[source_cell] != source_owner
		|| find_board_card(value, target_card_index, target_cell) != target_cell
		|| value.board_owners[target_cell] != target_owner
	) {
		append_resolution(resolution, source_before);
		return resolution_has_output(source_before)
			? ActionOutcome::APPLIED
			: ActionOutcome::NO_EFFECT;
	}

	const Variant reserved_target_extra = value.board_slot_extras[target_cell];
	value.board_card_indices[target_cell] = -1;
	value.board_owners[target_cell] = 0;
	value.board_slot_extras[target_cell] = Dictionary();

	Resolution swap_resolution;
	append_resolution(swap_resolution, source_before);
	const ActionOutcome source_move_outcome = move_card_between_cells(
		value,
		source_cell,
		source_cell,
		target_cell,
		source_card_index,
		source_owner,
		false,
		exile_stack,
		swap_resolution
	);
	if (source_move_outcome == ActionOutcome::UNSUPPORTED) {
		resolution.reason = swap_resolution.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	if (source_move_outcome != ActionOutcome::APPLIED) {
		append_resolution(resolution, swap_resolution);
		return source_move_outcome;
	}
	if (
		find_board_card(value, source_card_index, target_cell) != target_cell
		|| value.board_owners[target_cell] != source_owner
	) {
		resolution.reason = "First swap leg was invalidated after movement";
		return ActionOutcome::UNSUPPORTED;
	}

	const Variant reserved_source_extra = value.board_slot_extras[target_cell];
	value.board_card_indices[target_cell] = target_card_index;
	value.board_owners[target_cell] = static_cast<uint8_t>(target_owner);
	value.board_slot_extras[target_cell] = reserved_target_extra;
	Resolution target_before = resolve_movement_event(
		value,
		StringName("card_before_moved"),
		target_cell,
		target_cell,
		source_cell,
		target_card_index,
		target_owner,
		exile_stack
	);
	if (!target_before.supported) {
		resolution.reason = target_before.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	if (
		find_board_card(value, target_card_index, target_cell) != target_cell
		|| value.board_owners[target_cell] != target_owner
	) {
		value.board_card_indices[source_cell] = source_card_index;
		value.board_owners[source_cell] = static_cast<uint8_t>(source_owner);
		value.board_slot_extras[source_cell] = reserved_source_extra;
		value.board_card_indices[target_cell] = target_card_index;
		value.board_owners[target_cell] = static_cast<uint8_t>(target_owner);
		value.board_slot_extras[target_cell] = reserved_target_extra;
		return ActionOutcome::NO_EFFECT;
	}
	append_resolution(swap_resolution, target_before);

	const ActionOutcome target_move_outcome = move_card_between_cells(
		value,
		target_cell,
		target_cell,
		source_cell,
		target_card_index,
		target_owner,
		false,
		exile_stack,
		swap_resolution
	);
	if (target_move_outcome == ActionOutcome::UNSUPPORTED) {
		resolution.reason = swap_resolution.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	if (target_move_outcome != ActionOutcome::APPLIED) {
		resolution.reason = "Second swap leg could not move its exact instance";
		return ActionOutcome::UNSUPPORTED;
	}

	value.board_card_indices[target_cell] = source_card_index;
	value.board_owners[target_cell] = static_cast<uint8_t>(source_owner);
	value.board_slot_extras[target_cell] = reserved_source_extra;
	append_resolution(resolution, swap_resolution);
	return ActionOutcome::APPLIED;
}


Dictionary DuelNativeCompactKernel::restore_runtime_card(
	const NativeState &value,
	int32_t card_index
) const {
	const int32_t template_index = value.card_template_indices[card_index];
	Dictionary card = Dictionary(value.card_template_pool[template_index]).duplicate(true);
	const uint8_t flags = value.card_runtime_flags[card_index];
	if ((flags & (1 << 0)) != 0) {
		card["instance_id"] = value.card_instance_ids[card_index];
	}
	if ((flags & (1 << 1)) != 0) {
		Array powers;
		for (int32_t direction = 0; direction < 4; ++direction) {
			powers.append(value.card_powers[card_index * 4 + direction]);
		}
		card["powers"] = powers;
	}
	if ((flags & (1 << 2)) != 0) {
		card["original_owner"] = value.card_original_owners[card_index];
	}
	if ((flags & (1 << 3)) != 0) {
		card["ki"] = value.card_ki[card_index];
	}
	if ((flags & (1 << 4)) != 0) {
		Array active_abilities;
		for (const RuntimeAbilityEntry &entry : value.card_runtime_abilities[card_index]) {
			if (
				entry.compiled_ability_index >= 0
				&& entry.compiled_ability_index < static_cast<int32_t>(ability_declaration_pool.size())
			) {
				active_abilities.append(ability_declaration_pool[entry.compiled_ability_index]);
			}
		}
		card["active_abilities"] = active_abilities;
	}
	if ((flags & (1 << 5)) != 0) {
		Array audiences;
		switch (value.card_reveal_codes[card_index]) {
			case 1:
				audiences.append(1);
				break;
			case 2:
				audiences.append(2);
				break;
			case 3:
				audiences.append(1);
				audiences.append(2);
				break;
			case 4:
				audiences.append(2);
				audiences.append(1);
				break;
			default:
				break;
		}
		card["revealed_to_owner_ids"] = audiences;
	}
	if ((flags & (1 << 6)) != 0) {
		card["temporary_suppression_batches"] = materialize_suppression_batches(
			value,
			card_index
		);
	}
	if ((flags & (1 << 7)) != 0) {
		card["hand_slot_index"] = value.card_hand_slots[card_index];
	}
	return card;
}

int32_t DuelNativeCompactKernel::leftmost_empty_hand_slot(
	const NativeState &value,
	int32_t owner_id
) const {
	bool occupied[5] = {false, false, false, false, false};
	for (const int32_t card_index : value.zones[owner_id - 1]) {
		const int32_t slot = value.card_hand_slots[card_index];
		if (slot >= 0 && slot < 5) {
			occupied[slot] = true;
		}
	}
	for (int32_t slot = 0; slot < 5; ++slot) {
		if (!occupied[slot]) {
			return slot;
		}
	}
	return -1;
}

bool DuelNativeCompactKernel::owner_has_legal_play(
	const NativeState &value,
	int32_t owner_id
) const {
	const int32_t hand_zone_index = owner_id - 1;
	if (
		hand_zone_index < 0
		|| hand_zone_index >= static_cast<int32_t>(value.zones.size())
		|| value.zones[hand_zone_index].empty()
	) {
		return false;
	}
	return std::find(
		value.board_card_indices.begin(),
		value.board_card_indices.end(),
		-1
	) != value.board_card_indices.end();
}

bool DuelNativeCompactKernel::owner_has_legal_action(
	const NativeState &value,
	int32_t owner_id
) const {
	if (owner_has_legal_play(value, owner_id)) return true;
	if (owner_id == value.scalars[0] && value.scalars[5] > 0) return false;
	return board_has_enabled_activation_for_owner(value, owner_id);
}

bool DuelNativeCompactKernel::is_terminal(const NativeState &value) const {
	if (value.scalars[5] > 0 && owner_has_legal_play(value, value.scalars[0])) {
		return false;
	}
	if (value.scalars[1] >= value.scalars[7]) {
		return true;
	}
	const Array repetition_hashes = value.side_payload.get("repetition_hashes", Array());
	Dictionary counts;
	for (int64_t index = 0; index < repetition_hashes.size(); ++index) {
		const String signature = repetition_hashes[index];
		const int64_t count = static_cast<int64_t>(counts.get(signature, 0)) + 1;
		if (count >= 5) {
			return true;
		}
		counts[signature] = count;
	}
	if (std::find(value.board_card_indices.begin(), value.board_card_indices.end(), -1)
		== value.board_card_indices.end()) {
		return true;
	}
	return !owner_has_legal_action(value, 1) && !owner_has_legal_action(value, 2);
}

void DuelNativeCompactKernel::apply_extra_card_play_requests(
	NativeState &value,
	int32_t moving_owner,
	const std::vector<Resolution::ExtraPlayRequest> &requests,
	Resolution &resolution
) const {
	if (value.scalars[13] != 0) return;
	Array source_instance_ids;
	for (const Resolution::ExtraPlayRequest &request : requests) {
		if (
			request.owner_id != moving_owner
			|| request.amount <= 0
			|| request.source_card_index < 0
			|| request.source_card_index >= static_cast<int32_t>(value.card_instance_ids.size())
		) continue;
		source_instance_ids.append(value.card_instance_ids[request.source_card_index]);
	}
	if (source_instance_ids.is_empty()) return;
	value.scalars[13] = 1;
	value.scalars[5] = std::max(value.scalars[5], 1);
	Dictionary granted;
	granted["type"] = StringName("extra_card_play_granted");
	granted["owner_id"] = moving_owner;
	granted["amount"] = 1;
	granted["request_count"] = source_instance_ids.size();
	granted["source_instance_ids"] = source_instance_ids;
	resolution.events.append(granted);
}

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::resolve_before_full_board_end(
	NativeState &value,
	std::vector<int32_t> &exile_stack
) const {
	Resolution resolution;
	if (
		std::find(value.board_card_indices.begin(), value.board_card_indices.end(), -1)
		!= value.board_card_indices.end()
	) return resolution;
	int32_t owner_one_count = 0;
	int32_t owner_two_count = 0;
	for (const uint8_t owner : value.board_owners) {
		if (owner == 1) owner_one_count += 1;
		else if (owner == 2) owner_two_count += 1;
	}
	EventContext context;
	if (owner_one_count > owner_two_count) context.winning_owners.push_back(1);
	else if (owner_two_count > owner_one_count) context.winning_owners.push_back(2);
	return resolve_event(value, StringName("before_duel_end"), context, exile_stack);
}

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::finish_action(
	NativeState &value,
	int32_t moving_owner,
	int32_t played_card_index,
	const std::vector<Resolution::ExtraPlayRequest> &extra_play_requests,
	std::vector<int32_t> &exile_stack
) const {
	Resolution resolution;
	if (
		played_card_index >= 0
		&& played_card_index < static_cast<int32_t>(value.card_instance_ids.size())
	) {
		Dictionary last_hand_plays = value.side_payload.get(
			"last_hand_play_by_owner",
			Dictionary()
		);
		last_hand_plays = last_hand_plays.duplicate(true);
		Dictionary last_hand_play;
		last_hand_play["played_by_owner_id"] = moving_owner;
		last_hand_play["card_id"] = value.card_ids[played_card_index];
		last_hand_play["instance_id"] = value.card_instance_ids[played_card_index];
		last_hand_plays[moving_owner] = last_hand_play;
		value.side_payload["last_hand_play_by_owner"] = last_hand_plays;
	}

	value.scalars[1] += 1;
	value.scalars[12] += 1;
	apply_extra_card_play_requests(
		value,
		moving_owner,
		extra_play_requests,
		resolution
	);
	if (value.scalars[5] > 0 && owner_has_legal_play(value, moving_owner)) {
		value.scalars[0] = moving_owner;
		return resolution;
	}
	value.scalars[5] = 0;

	if (value.scalars[6] == 0) {
		EventContext end_context;
		end_context.turn_owner = moving_owner;
		Resolution end_resolution = resolve_event(
			value,
			StringName("end_owner_turn"),
			end_context,
			exile_stack
		);
		if (!end_resolution.supported) return end_resolution;
		append_resolution(resolution, end_resolution);
		value.scalars[6] = 1;
		apply_extra_card_play_requests(
			value,
			moving_owner,
			end_resolution.extra_play_requests,
			resolution
		);
	}

	Resolution before_end = resolve_before_full_board_end(value, exile_stack);
	if (!before_end.supported) return before_end;
	append_resolution(resolution, before_end);
	if (value.scalars[5] > 0 && owner_has_legal_play(value, moving_owner)) {
		value.scalars[0] = moving_owner;
		return resolution;
	}
	value.scalars[5] = 0;

	append_resolution(resolution, complete_owner_turn_boundary(value));
	if (is_terminal(value)) return resolution;

	int32_t previous_owner = moving_owner;
	while (true) {
		const int32_t turn_owner = other_owner(previous_owner);
		value.scalars[0] = turn_owner;
		EventContext start_context;
		start_context.turn_owner = turn_owner;
		Resolution start_resolution = resolve_event(
			value,
			StringName("start_owner_turn"),
			start_context,
			exile_stack
		);
		if (!start_resolution.supported) return start_resolution;
		append_resolution(resolution, start_resolution);
		if (owner_has_legal_action(value, turn_owner)) return resolution;

		EventContext empty_end_context;
		empty_end_context.turn_owner = turn_owner;
		Resolution empty_end_resolution = resolve_event(
			value,
			StringName("end_owner_turn"),
			empty_end_context,
			exile_stack
		);
		if (!empty_end_resolution.supported) return empty_end_resolution;
		append_resolution(resolution, empty_end_resolution);
		value.scalars[6] = 1;
		apply_extra_card_play_requests(
			value,
			turn_owner,
			empty_end_resolution.extra_play_requests,
			resolution
		);
		Resolution empty_before_end = resolve_before_full_board_end(value, exile_stack);
		if (!empty_before_end.supported) return empty_before_end;
		append_resolution(resolution, empty_before_end);
		if (value.scalars[5] > 0 && owner_has_legal_play(value, turn_owner)) {
			return resolution;
		}
		value.scalars[5] = 0;
		append_resolution(resolution, complete_owner_turn_boundary(value));
		if (is_terminal(value)) return resolution;
		previous_owner = turn_owner;
	}
	return resolution;
}

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::complete_owner_turn_boundary(
	NativeState &value
) const {
	Resolution resolution = restore_temporary_abilities(value, value.scalars[2]);
	value.scalars[2] += 1;
	value.scalars[3] = 0;
	value.scalars[4] = 0;
	value.scalars[6] = 0;
	value.scalars[13] = 0;
	Array repetition_hashes = value.side_payload.get("repetition_hashes", Array());
	repetition_hashes = repetition_hashes.duplicate(true);
	repetition_hashes.append(board_repetition_signature(value));
	value.side_payload["repetition_hashes"] = repetition_hashes;
	return resolution;
}

String DuelNativeCompactKernel::board_repetition_signature(const NativeState &value) const {
	String result;
	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		if (cell > 0) {
			result += "|";
		}
		const int32_t card_index = value.board_card_indices[cell];
		if (card_index < 0) {
			result += "empty";
			continue;
		}
		const String card_id = String(value.card_ids[card_index]);
		const CharString card_id_bytes = card_id.utf8();
		result += "card:";
		result += String::num_int64(card_id_bytes.length());
		result += ":";
		result += bytes_to_hex(card_id_bytes);
		result += ":owner:";
		result += String::num_int64(value.board_owners[cell]);
	}
	return result;
}

Dictionary DuelNativeCompactKernel::to_variant_payload(const NativeState &value) const {
	Dictionary payload;
	payload["format_version"] = 1;
	payload["scalars"] = to_packed_int32_array(value.scalars);
	payload["board_card_indices"] = to_packed_int32_array(value.board_card_indices);
	payload["board_owners"] = to_packed_byte_array(value.board_owners);
	payload["board_slot_extras"] = value.board_slot_extras;
	Array zones;
	for (const std::vector<int32_t> &zone : value.zones) {
		zones.append(to_packed_int32_array(zone));
	}
	payload["zones"] = zones;
	Array instance_ids;
	for (const StringName &instance_id : value.card_instance_ids) {
		instance_ids.append(instance_id);
	}
	payload["card_instance_ids"] = instance_ids;
	payload["card_template_indices"] = to_packed_int32_array(value.card_template_indices);
	payload["card_runtime_flags"] = to_packed_byte_array(value.card_runtime_flags);
	payload["card_powers"] = to_packed_int32_array(value.card_powers);
	payload["card_original_owners"] = to_packed_byte_array(value.card_original_owners);
	payload["card_ki"] = to_packed_int32_array(value.card_ki);
	Array materialized_pool = value.active_ability_set_pool.duplicate();
	std::vector<int32_t> materialized_indices = value.card_active_ability_set_indices;
	for (size_t card_index = 0; card_index < value.card_instance_ids.size(); ++card_index) {
		Array derived;
		for (const RuntimeAbilityEntry &entry : value.card_runtime_abilities[card_index]) {
			if (
				entry.compiled_ability_index >= 0
				&& entry.compiled_ability_index < static_cast<int32_t>(ability_declaration_pool.size())
			) {
				derived.append(ability_declaration_pool[entry.compiled_ability_index]);
			}
		}
		int32_t derived_index = -1;
		for (int64_t pool_index = 0; pool_index < materialized_pool.size(); ++pool_index) {
			if (Variant(materialized_pool[pool_index]) == Variant(derived)) {
				derived_index = static_cast<int32_t>(pool_index);
				break;
			}
		}
		if (derived_index < 0) {
			derived_index = static_cast<int32_t>(materialized_pool.size());
			materialized_pool.append(derived);
		}
		materialized_indices[card_index] = derived_index;
	}
	payload["card_active_ability_set_indices"] = to_packed_int32_array(materialized_indices);
	payload["card_reveal_codes"] = to_packed_byte_array(value.card_reveal_codes);
	Array materialized_suppression_pool = value.suppression_set_pool.duplicate();
	std::vector<int32_t> materialized_suppression_indices = value.card_suppression_set_indices;
	for (size_t card_index = 0; card_index < value.card_instance_ids.size(); ++card_index) {
		if ((value.card_runtime_flags[card_index] & (1 << 6)) == 0) {
			materialized_suppression_indices[card_index] = -1;
			continue;
		}
		const Array derived = materialize_suppression_batches(
			value,
			static_cast<int32_t>(card_index)
		);
		int32_t derived_index = -1;
		for (int64_t pool_index = 0; pool_index < materialized_suppression_pool.size(); ++pool_index) {
			if (Variant(materialized_suppression_pool[pool_index]) == Variant(derived)) {
				derived_index = static_cast<int32_t>(pool_index);
				break;
			}
		}
		if (derived_index < 0) {
			derived_index = static_cast<int32_t>(materialized_suppression_pool.size());
			materialized_suppression_pool.append(derived);
		}
		materialized_suppression_indices[card_index] = derived_index;
	}
	payload["card_suppression_set_indices"] = to_packed_int32_array(
		materialized_suppression_indices
	);
	payload["card_hand_slots"] = to_packed_int32_array(value.card_hand_slots);
	payload["card_template_pool"] = value.card_template_pool;
	payload["active_ability_set_pool"] = materialized_pool;
	payload["suppression_set_pool"] = materialized_suppression_pool;
	payload["fresh_card_prototypes"] = value.fresh_card_prototype_pool;
	payload["empty_deck_draw_prototype_index"] = value.empty_deck_draw_prototype_index;
	payload["side_payload"] = value.side_payload;
	return payload;
}

uint64_t DuelNativeCompactKernel::checksum(const NativeState &value) const {
	uint64_t hash = 1469598103934665603ULL;
	hash_values(hash, value.scalars);
	hash_values(hash, value.board_card_indices);
	hash_values(hash, value.board_owners);
	for (const std::vector<int32_t> &zone : value.zones) {
		hash_values(hash, zone);
	}
	hash_values(hash, value.card_template_indices);
	hash_values(hash, value.card_runtime_flags);
	hash_values(hash, value.card_powers);
	hash_values(hash, value.card_original_owners);
	hash_values(hash, value.card_ki);
	for (const std::vector<RuntimeAbilityEntry> &abilities : value.card_runtime_abilities) {
		for (const RuntimeAbilityEntry &entry : abilities) {
			hash ^= static_cast<uint64_t>(entry.compiled_ability_index);
			hash *= 1099511628211ULL;
		}
	}
	for (const std::vector<RuntimeSuppressionBatch> &batches : value.card_runtime_suppression_batches) {
		for (const RuntimeSuppressionBatch &batch : batches) {
			hash ^= static_cast<uint64_t>(batch.expires_after_turn);
			hash *= 1099511628211ULL;
			for (const RuntimeSuppressionEntry &entry : batch.entries) {
				hash ^= static_cast<uint64_t>(entry.original_index);
				hash *= 1099511628211ULL;
				hash ^= static_cast<uint64_t>(entry.compiled_ability_index);
				hash *= 1099511628211ULL;
			}
		}
	}
	hash_values(hash, value.card_reveal_codes);
	hash_values(hash, value.card_suppression_set_indices);
	hash_values(hash, value.card_hand_slots);
	for (const StringName &instance_id : value.card_instance_ids) {
		hash ^= static_cast<uint64_t>(instance_id.hash());
		hash *= 1099511628211ULL;
	}
	return hash;
}

} // namespace godot
