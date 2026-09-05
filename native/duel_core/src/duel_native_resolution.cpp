#include "duel_native_compact_kernel_internal.h"

namespace godot {
using namespace duel_native_internal;

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::resolve_attack_request(
	NativeState &value,
	const AttackRequest &request,
	std::vector<int32_t> &exile_stack
) const {
	Resolution resolution;
	const int32_t initial_attack_cell = find_board_card(
		value,
		request.attacker_card_index,
		request.attacker_cell
	);
	if (
		initial_attack_cell < 0
		|| value.board_owners[initial_attack_cell] != request.attacker_owner
		|| value.scalars[request.attacker_owner == 1 ? 3 : 4] >= 20
		|| attack_is_prohibited(value, request.attacker_owner)
	) {
		return resolution;
	}
	const AttackPolicy attack_policy = get_standard_attack_policy(
		value,
		initial_attack_cell,
		request.attacker_card_index,
		request.attacker_owner,
		request.requested_policy
	);
	std::vector<int32_t> target_cells;
	if (request.targeted) {
		const int32_t target_cell = find_board_card(
			value,
			request.locked_target_card_index,
			request.locked_target_cell
		);
		if (
			target_cell == request.locked_target_cell
			&& target_cell >= 0
			&& value.board_owners[target_cell] == request.locked_target_owner
			&& can_attack_target(
				value,
				initial_attack_cell,
				target_cell,
				attack_policy,
				false
			)
		) target_cells.push_back(target_cell);
	} else {
		target_cells = get_attack_targets(
			value,
			initial_attack_cell,
			attack_policy
		);
	}
	if (!target_cells.empty()) {
		value.scalars[request.attacker_owner == 1 ? 3 : 4] += 1;
	}
	bool attack_started = false;
	bool attack_flipped_enemy = false;
	std::vector<EventContext::AttackFlipRecord> attack_flips;
	auto resolution_flipped_attacker = [&](const Resolution &candidate) -> bool {
		const StringName attacker_instance_id = value.card_instance_ids[request.attacker_card_index];
		for (int64_t event_index = 0; event_index < candidate.events.size(); ++event_index) {
			if (candidate.events[event_index].get_type() != Variant::DICTIONARY) continue;
			const Dictionary event = candidate.events[event_index];
			if (
				StringName(event.get("type", StringName())) == StringName("card_flipped")
				&& StringName(event.get("instance_id", StringName())) == attacker_instance_id
			) return true;
		}
		return false;
	};
	for (const int32_t locked_cell : target_cells) {
		bool stop_after_current_target = false;
		const int32_t attacker_cell = find_board_card(
			value,
			request.attacker_card_index,
			request.attacker_cell
		);
		if (
			attacker_cell < 0
			|| value.board_owners[attacker_cell] != request.attacker_owner
		) break;
		const int32_t attacked_card_index = value.board_card_indices[locked_cell];
		if (attacked_card_index < 0) continue;
		const int32_t attacked_cell = locked_cell;
		if (!can_attack_target(value, attacker_cell, attacked_cell, attack_policy, true)) continue;
		const int32_t attacked_owner = value.board_owners[attacked_cell];
		const StringName attacked_instance_id = value.card_instance_ids[attacked_card_index];

		Dictionary attack_event;
		attack_event["type"] = StringName("attack_started");
		attack_event["source_cell"] = attacker_cell;
		attack_event["source_instance_id"] = value.card_instance_ids[request.attacker_card_index];
		attack_event["source_owner_id"] = request.attacker_owner;
		attack_event["target_cell"] = attacked_cell;
		attack_event["target_instance_id"] = attacked_instance_id;
		attack_event["target_owner_id"] = attacked_owner;
		attack_event["attack_reason"] = request.reason;
		resolution.events.append(attack_event);
		attack_started = true;

		EventContext attack_context;
		attack_context.attacker_cell = attacker_cell;
		attack_context.attacker_card_index = request.attacker_card_index;
		attack_context.attacker_owner = request.attacker_owner;
		attack_context.attacked_cell = attacked_cell;
		attack_context.attacked_card_index = attacked_card_index;
		attack_context.attacked_owner = attacked_owner;
		attack_context.trigger_cell = attacked_cell;
		attack_context.trigger_card_index = attacked_card_index;
		attack_context.trigger_owner = attacked_owner;
		attack_context.trigger_previous_owner = attacked_owner;
		attack_context.trigger_zone = 0;
		attack_context.trigger_logical_index = attacked_cell;
		attack_context.trigger_was_on_board = true;
		attack_context.attack_reason = request.reason;
		Resolution be_attacked = resolve_event(
			value,
			StringName("card_be_attacked"),
			attack_context,
			exile_stack
		);
		if (!be_attacked.supported) return be_attacked;
		stop_after_current_target = resolution_flipped_attacker(be_attacked);
		append_resolution(resolution, be_attacked);
		const int32_t current_attacker_cell = find_board_card(
			value,
			request.attacker_card_index,
			attacker_cell
		);
		const int32_t current_attacked_cell = find_board_card(
			value,
			attacked_card_index,
			attacked_cell
		);
		if (
			current_attacker_cell < 0
			|| value.board_owners[current_attacker_cell] != request.attacker_owner
		) break;
		if (current_attacked_cell < 0) {
			if (stop_after_current_target) break;
			continue;
		}
		if (!can_attack_target(
			value,
			current_attacker_cell,
			current_attacked_cell,
			attack_policy,
			true
		)) {
			if (stop_after_current_target) break;
			continue;
		}
		int32_t resolved_capture_owner = request.attacker_owner;
		if (value.board_owners[current_attacked_cell] == request.attacker_owner) {
			resolved_capture_owner = (
				attack_policy.capture_owner_id != 0
				? attack_policy.capture_owner_id
				: other_owner(request.attacker_owner)
			);
		}
		if (resolved_capture_owner == value.board_owners[current_attacked_cell]) {
			if (stop_after_current_target) break;
			continue;
		}
		EventContext before_context = attack_context;
		before_context.attacker_cell = current_attacker_cell;
		before_context.attacked_cell = current_attacked_cell;
		before_context.attacked_owner = value.board_owners[current_attacked_cell];
		before_context.trigger_cell = current_attacked_cell;
		before_context.trigger_owner = value.board_owners[current_attacked_cell];
		before_context.new_owner = resolved_capture_owner;
		before_context.flip_reason = request.reason;
		Resolution before_flip = resolve_event(
			value,
			StringName("card_before_flipped"),
			before_context,
			exile_stack
		);
		if (!before_flip.supported) return before_flip;
		stop_after_current_target = (
			stop_after_current_target || resolution_flipped_attacker(before_flip)
		);
		append_resolution(resolution, before_flip);
		if (before_flip.flip_prevented) {
			Dictionary prevented;
			prevented["type"] = StringName("card_flip_prevented");
			prevented["source_cell"] = current_attacker_cell;
			prevented["target_cell"] = current_attacked_cell;
			prevented["owner_id"] = attacked_owner;
			prevented["new_owner_id"] = resolved_capture_owner;
			prevented["instance_id"] = attacked_instance_id;
			resolution.events.append(prevented);
			Resolution after_prevented = resolve_event(
				value,
				StringName("card_flip_prevented"),
				before_context,
				exile_stack
			);
			if (!after_prevented.supported) return after_prevented;
			stop_after_current_target = (
				stop_after_current_target || resolution_flipped_attacker(after_prevented)
			);
			append_resolution(resolution, after_prevented);
			if (stop_after_current_target) break;
			continue;
		}
		const int32_t post_before_attacker_cell = find_board_card(
			value,
			request.attacker_card_index,
			current_attacker_cell
		);
		const int32_t post_before_attacked_cell = find_board_card(
			value,
			attacked_card_index,
			current_attacked_cell
		);
		if (
			post_before_attacker_cell < 0
			|| value.board_owners[post_before_attacker_cell] != request.attacker_owner
		) break;
		if (
			post_before_attacked_cell < 0
			|| value.board_owners[post_before_attacked_cell] == resolved_capture_owner
		) {
			if (stop_after_current_target) break;
			continue;
		}
		const int32_t flipped_previous_owner = value.board_owners[post_before_attacked_cell];
		Resolution flip_resolution;
		if (!flip_card(
			value,
			post_before_attacker_cell,
			request.attacker_card_index,
			post_before_attacked_cell,
			attacked_card_index,
			resolved_capture_owner,
			before_context,
			exile_stack,
			flip_resolution
		)) return flip_resolution;
		stop_after_current_target = (
			stop_after_current_target || resolution_flipped_attacker(flip_resolution)
		);
		append_resolution(resolution, flip_resolution);
		attack_flipped_enemy = (
			attack_flipped_enemy
			|| flipped_previous_owner != request.attacker_owner
		);
		EventContext::AttackFlipRecord flip_record;
		flip_record.card_index = attacked_card_index;
		flip_record.previous_owner = flipped_previous_owner;
		attack_flips.push_back(flip_record);
		if (stop_after_current_target) break;
	}
	if (attack_started) {
		EventContext after_attack_context;
		after_attack_context.attacker_cell = find_board_card(
			value,
			request.attacker_card_index,
			request.attacker_cell
		);
		after_attack_context.attacker_card_index = request.attacker_card_index;
		after_attack_context.attacker_owner = request.attacker_owner;
		after_attack_context.attack_flipped_enemy = attack_flipped_enemy;
		after_attack_context.attack_flips = attack_flips;
		after_attack_context.repeat_attack = request.repeat_attack;
		Resolution after_attack = resolve_event(
			value,
			StringName("card_after_attack"),
			after_attack_context,
			exile_stack
		);
		if (!after_attack.supported) return after_attack;
		append_resolution(resolution, after_attack);
	}
	return resolution;
}

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::resolve_summon_lifecycle(
	NativeState &value,
	const SummonRequest &request,
	std::vector<int32_t> &exile_stack
) const {
	Resolution resolution;
	const std::vector<int32_t> summon_attack_redirect_sources = (
		request.attack_redirect_snapshot_taken
		? request.attack_redirect_source_card_indices
		: snapshot_summon_attack_redirect_sources(
			value,
			request.summon_cell,
			request.owner_id
		)
	);
	EventContext summon_context;
	summon_context.trigger_cell = request.summon_cell;
	summon_context.trigger_card_index = request.card_index;
	summon_context.trigger_owner = request.owner_id;
	summon_context.trigger_previous_owner = request.owner_id;
	summon_context.trigger_zone = 0;
	summon_context.trigger_logical_index = request.summon_cell;
	summon_context.trigger_was_on_board = true;
	Resolution before_summoned = resolve_event(
		value,
		StringName("card_before_summoned"),
		summon_context,
		exile_stack
	);
	if (!before_summoned.supported) return before_summoned;
	append_resolution(resolution, before_summoned);
	resolution.events.append_array(request.buffered_placement_events);

	Resolution summoned = resolve_event(
		value,
		StringName("card_summoned"),
		summon_context,
		exile_stack
	);
	if (!summoned.supported) return summoned;
	append_resolution(resolution, summoned);

	const int32_t after_cell = find_board_card(value, request.card_index, request.summon_cell);
	if (after_cell >= 0) {
		EventContext after_context = summon_context;
		after_context.trigger_cell = after_cell;
		after_context.trigger_owner = value.board_owners[after_cell];
		after_context.trigger_logical_index = after_cell;
		Resolution after_summoned = resolve_event(
			value,
			StringName("card_after_summoned"),
			after_context,
			exile_stack
		);
		if (!after_summoned.supported) return after_summoned;
		append_resolution(resolution, after_summoned);
	}

	AttackRequest attack_request;
	attack_request.attacker_cell = after_cell;
	attack_request.attacker_card_index = request.card_index;
	attack_request.attacker_owner = request.owner_id;
	const int32_t initial_attack_cell = find_board_card(
		value,
		request.card_index,
		request.summon_cell
	);
	if (initial_attack_cell >= 0) {
		attack_request.requested_policy = get_summon_attack_policy(
			value,
			initial_attack_cell,
			request.owner_id,
			summon_attack_redirect_sources
		);
	}
	attack_request.reason = request.attack_reason.is_empty()
		? StringName("summon_standard_attack")
		: request.attack_reason;
	Resolution attack_resolution = resolve_attack_request(
		value,
		attack_request,
		exile_stack
	);
	if (!attack_resolution.supported) return attack_resolution;
	append_resolution(resolution, attack_resolution);
	return resolution;
}

bool DuelNativeCompactKernel::board_has_enabled_event(
	const NativeState &value,
	const StringName &event_id
) const {
	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		const int32_t card_index = value.board_card_indices[cell];
		if (
			card_index >= 0
			&& card_has_enabled_event(value, card_index, value.board_owners[cell], event_id)
		) {
			return true;
		}
	}
	return false;
}

bool DuelNativeCompactKernel::board_has_enabled_activation_for_owner(
	const NativeState &value,
	int32_t owner_id
) const {
	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		const int32_t card_index = value.board_card_indices[cell];
		if (card_index < 0 || value.board_owners[cell] != owner_id) continue;
		if (!card_effects_enabled(value, card_index, owner_id)) continue;
		for (
			size_t ability_index = 0;
			ability_index < value.card_runtime_abilities[card_index].size();
			++ability_index
		) {
			const CompiledAbility *ability = runtime_ability(
				value,
				card_index,
				static_cast<int32_t>(ability_index)
			);
			if (
				ability == nullptr
				|| !ability->has_activation
				|| !ability->activation.declaration_valid
			) continue;
			const CompiledActivation &activation = ability->activation;
			if (
				can_pay_activation_cost(value, card_index, activation)
				&& count_activation_target_indices(
					value,
					owner_id,
					static_cast<int32_t>(cell),
					activation
				) > 0
			) return true;
		}
	}
	return false;
}

bool DuelNativeCompactKernel::is_special_negative(
	const NativeState &value,
	int32_t card_index
) const {
	if (card_index < 0 || card_index >= static_cast<int32_t>(value.card_instance_ids.size())) return false;
	for (int32_t direction = 0; direction < 4; ++direction) {
		if (value.card_powers[card_index * 4 + direction] != -1) return false;
	}
	return true;
}

bool DuelNativeCompactKernel::powers_supported(
	const NativeState &value,
	int32_t card_index
) const {
	if (is_special_negative(value, card_index)) return true;
	for (int32_t direction = 0; direction < 4; ++direction) {
		if (value.card_powers[card_index * 4 + direction] < 0) return false;
	}
	return true;
}

bool DuelNativeCompactKernel::can_change_powers(
	const NativeState &value,
	int32_t card_index
) const {
	return !is_special_negative(value, card_index);
}

int32_t DuelNativeCompactKernel::effective_defending_power(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id,
	int32_t direction
) const {
	int32_t result = value.card_powers[card_index * 4 + direction];
	card_has_modifier(
		value,
		card_index,
		owner_id,
		ModifierOpcode::DEFENDING_POWER_OVERRIDE,
		&result
	);
	return result;
}

int32_t DuelNativeCompactKernel::minimum_effective_defending_power(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id
) const {
	int32_t result = effective_defending_power(value, card_index, owner_id, 0);
	for (int32_t direction = 1; direction < 4; ++direction) {
		result = std::min(
			result,
			effective_defending_power(value, card_index, owner_id, direction)
		);
	}
	return result;
}

int32_t DuelNativeCompactKernel::find_board_card(
	const NativeState &value,
	int32_t card_index,
	int32_t hint
) const {
	if (
		hint >= 0
		&& hint < static_cast<int32_t>(value.board_card_indices.size())
		&& value.board_card_indices[hint] == card_index
	) return hint;
	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		if (value.board_card_indices[cell] == card_index) return static_cast<int32_t>(cell);
	}
	return -1;
}

bool DuelNativeCompactKernel::locate_card(
	const NativeState &value,
	int32_t card_index,
	int32_t &zone_kind,
	int32_t &owner_id,
	int32_t &logical_index
) const {
	const int32_t board_cell = find_board_card(value, card_index);
	if (board_cell >= 0) {
		zone_kind = 0;
		owner_id = value.board_owners[board_cell];
		logical_index = board_cell;
		return true;
	}
	static constexpr int32_t zone_kinds[8] = {1, 1, 2, 2, 3, 3, 4, 4};
	for (int32_t zone_index = 0; zone_index < static_cast<int32_t>(value.zones.size()); ++zone_index) {
		const std::vector<int32_t> &zone = value.zones[zone_index];
		const auto found = std::find(zone.begin(), zone.end(), card_index);
		if (found == zone.end()) continue;
		zone_kind = zone_kinds[zone_index];
		owner_id = zone_index % 2 + 1;
		logical_index = static_cast<int32_t>(std::distance(zone.begin(), found));
		return true;
	}
	return false;
}


bool DuelNativeCompactKernel::exile_card(
	NativeState &value,
	int32_t card_index,
	int32_t source_cell,
	int32_t ability_source_card_index,
	bool self_removal,
	const StringName &exile_reason,
	const EventContext &parent_context,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution,
	bool record_exile_index
) const {
	if (card_index < 0 || card_index >= static_cast<int32_t>(value.card_instance_ids.size())) return true;
	if (std::find(exile_stack.begin(), exile_stack.end(), card_index) != exile_stack.end()) return true;
	int32_t initial_zone = -1;
	int32_t initial_owner = 0;
	int32_t initial_index = -1;
	if (!locate_card(value, card_index, initial_zone, initial_owner, initial_index)) return true;
	if (initial_zone != 0 && initial_zone != 1 && initial_zone != 3) return true;

	if (initial_zone == 0 || initial_zone == 1) {
		exile_stack.push_back(card_index);
		EventContext before_context = parent_context;
		before_context.trigger_cell = initial_zone == 0 ? initial_index : -1;
		before_context.trigger_card_index = card_index;
		before_context.trigger_owner = initial_owner;
		before_context.trigger_zone = initial_zone;
		before_context.trigger_logical_index = initial_index;
		before_context.trigger_was_on_board = initial_zone == 0;
		before_context.exile_reason = exile_reason;
		Resolution before = resolve_event(value, StringName("card_before_exiled"), before_context, exile_stack);
		exile_stack.pop_back();
		if (!before.supported) {
			resolution.reason = before.reason;
			return false;
		}
		resolution.events.append_array(before.events);
		resolution.captures.append_array(before.captures);
		resolution.exiles.append_array(before.exiles);
	}

	int32_t zone = -1;
	int32_t current_owner = 0;
	int32_t logical_index = -1;
	if (!locate_card(value, card_index, zone, current_owner, logical_index)) return true;
	if (zone != initial_zone || current_owner != initial_owner || logical_index != initial_index) return true;
	const int32_t previous_hand_size = zone == 1
		? static_cast<int32_t>(value.zones[current_owner - 1].size())
		: -1;
	if (zone == 0) {
		value.board_card_indices[logical_index] = -1;
		value.board_owners[logical_index] = 0;
		if (logical_index < value.board_slot_extras.size()) value.board_slot_extras[logical_index] = Dictionary();
	} else {
		const int32_t zone_index = zone == 1 ? current_owner - 1 : current_owner + 3;
		std::vector<int32_t> &subject_zone = value.zones[zone_index];
		if (logical_index < 0 || logical_index >= static_cast<int32_t>(subject_zone.size()) || subject_zone[logical_index] != card_index) return true;
		subject_zone.erase(subject_zone.begin() + logical_index);
		if (zone == 1) {
			value.card_runtime_flags[card_index] &= static_cast<uint8_t>(~(1 << 7));
			value.card_hand_slots[card_index] = -1;
		}
	}
	int32_t original_owner = value.card_original_owners[card_index];
	if (original_owner != 1 && original_owner != 2) original_owner = current_owner;
	value.zones[original_owner + 5].push_back(card_index);

	Dictionary event;
	event["type"] = StringName("card_exiled");
	event["source_cell"] = source_cell;
	event["source_instance_id"] = ability_source_card_index >= 0 ? value.card_instance_ids[ability_source_card_index] : StringName();
	event["target_cell"] = zone == 0 ? logical_index : -1;
	event["owner_id"] = current_owner;
	event["original_owner"] = original_owner;
	event["instance_id"] = value.card_instance_ids[card_index];
	event["self_removal"] = self_removal;
	event["zone"] = zone == 0 ? StringName("board") : (zone == 1 ? StringName("hand") : StringName("discard"));
	event["logical_index"] = logical_index;
	event["exile_reason"] = exile_reason;
	resolution.events.append(event);
	const int32_t exiled_cell = zone == 0 ? logical_index : -1;
	if (previous_hand_size >= 0) {
		Resolution hand_change = resolve_difficulty_hand_change(
			value,
			current_owner,
			previous_hand_size,
			static_cast<int32_t>(value.zones[current_owner - 1].size()),
			source_cell,
			exile_stack
		);
		if (!hand_change.supported) {
			resolution.reason = hand_change.reason;
			return false;
		}
		append_resolution(resolution, hand_change);
	}

	EventContext after_context = parent_context;
	after_context.trigger_cell = zone == 0 ? logical_index : -1;
	after_context.trigger_card_index = card_index;
	after_context.trigger_owner = current_owner;
	after_context.trigger_zone = zone;
	after_context.trigger_logical_index = logical_index;
	after_context.trigger_was_on_board = zone == 0;
	after_context.exile_reason = exile_reason;
	Resolution after = resolve_event(value, StringName("card_after_exiled"), after_context, exile_stack);
	if (!after.supported) {
		resolution.reason = after.reason;
		return false;
	}
	resolution.events.append_array(after.events);
	resolution.captures.append_array(after.captures);
	resolution.exiles.append_array(after.exiles);
	if (
		include_presentation_payloads
		&& record_exile_index
		&& resolution.exiles.find(exiled_cell) < 0
	) {
		resolution.exiles.append(exiled_cell);
	}
	return true;
}

bool DuelNativeCompactKernel::flip_card(
	NativeState &value,
	int32_t attacker_cell,
	int32_t attacker_card_index,
	int32_t target_cell,
	int32_t target_card_index,
	int32_t new_owner,
	const EventContext &context,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution,
	bool record_capture_index
) const {
	const int32_t current_target_cell = find_board_card(value, target_card_index, target_cell);
	if (current_target_cell < 0 || value.board_owners[current_target_cell] == new_owner) return true;
	std::vector<uint64_t> remove_before_after_flip;
	std::vector<uint64_t> remove_after_after_flip;
	for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[target_card_index].size(); ++ability_index) {
		const CompiledAbility *ability = runtime_ability(value, target_card_index, static_cast<int32_t>(ability_index));
		if (ability == nullptr || ability->retained_on_flip) continue;
		const uint64_t handle = value.card_runtime_abilities[target_card_index][ability_index].handle;
		if (ability->isolated_self_after_flip) {
			remove_after_after_flip.push_back(handle);
		} else {
			remove_before_after_flip.push_back(handle);
		}
	}
	value.board_owners[current_target_cell] = static_cast<uint8_t>(new_owner);
	Dictionary flipped;
	flipped["type"] = StringName("card_flipped");
	flipped["source_cell"] = attacker_cell;
	flipped["target_cell"] = current_target_cell;
	flipped["owner_id"] = new_owner;
	flipped["instance_id"] = value.card_instance_ids[target_card_index];
	resolution.events.append(flipped);
	clear_runtime_suppression(value, target_card_index);
	for (const uint64_t ability_handle : remove_before_after_flip) {
		remove_ability_with_event(value, target_card_index, ability_handle, attacker_cell, attacker_card_index, current_target_cell, new_owner, resolution.events);
	}
	if (include_presentation_payloads && record_capture_index) {
		resolution.captures.append(current_target_cell);
	}
	EventContext after_context = context;
	after_context.trigger_cell = current_target_cell;
	after_context.trigger_card_index = target_card_index;
	after_context.trigger_previous_owner = context.trigger_owner;
	after_context.trigger_owner = context.trigger_owner;
	after_context.trigger_zone = 0;
	after_context.trigger_logical_index = current_target_cell;
	Resolution after = resolve_event(value, StringName("card_after_flipped"), after_context, exile_stack);
	if (!after.supported) {
		resolution.reason = after.reason;
		return false;
	}
	resolution.events.append_array(after.events);
	resolution.captures.append_array(after.captures);
	resolution.exiles.append_array(after.exiles);
	const int32_t post_cell = find_board_card(value, target_card_index, current_target_cell);
	if (post_cell >= 0) {
		for (const uint64_t ability_handle : remove_after_after_flip) {
			remove_ability_with_event(value, target_card_index, ability_handle, attacker_cell, attacker_card_index, post_cell, new_owner, resolution.events);
		}
	}
	return true;
}


} // namespace godot
