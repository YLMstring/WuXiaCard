#include "duel_native_compact_kernel_internal.h"

namespace godot {
using namespace duel_native_internal;

int32_t DuelNativeCompactKernel::find_runtime_ability_index(
	const NativeState &value,
	int32_t card_index,
	uint64_t ability_handle,
	int32_t preferred_index
) const {
	if (
		card_index < 0
		|| card_index >= static_cast<int32_t>(value.card_runtime_abilities.size())
		|| ability_handle == 0
	) {
		return -1;
	}
	const std::vector<RuntimeAbilityEntry> &entries = value.card_runtime_abilities[card_index];
	if (
		preferred_index >= 0
		&& preferred_index < static_cast<int32_t>(entries.size())
		&& entries[preferred_index].handle == ability_handle
	) {
		return preferred_index;
	}
	for (size_t index = 0; index < entries.size(); ++index) {
		if (entries[index].handle == ability_handle) return static_cast<int32_t>(index);
	}
	return -1;
}

bool DuelNativeCompactKernel::card_has_enabled_activation(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id
) const {
	if (!card_effects_enabled(value, card_index, owner_id)) {
		return false;
	}
	for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[card_index].size(); ++ability_index) {
		const CompiledAbility *ability = runtime_ability(value, card_index, static_cast<int32_t>(ability_index));
		if (
			ability != nullptr
			&& ability->has_activation
			&& ability->activation.declaration_valid
		) return true;
	}
	return false;
}

const DuelNativeCompactKernel::CompiledActivation *DuelNativeCompactKernel::get_activation_at(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id,
	int32_t activation_index
) const {
	if (
		activation_index < 0
		|| !card_effects_enabled(value, card_index, owner_id)
		|| card_index < 0
		|| card_index >= static_cast<int32_t>(value.card_runtime_abilities.size())
	) {
		return nullptr;
	}
	int32_t current_activation_index = 0;
	for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[card_index].size(); ++ability_index) {
		const CompiledAbility *ability = runtime_ability(
			value,
			card_index,
			static_cast<int32_t>(ability_index)
		);
		if (ability == nullptr || !ability->has_activation) continue;
		if (current_activation_index == activation_index) {
			return ability->activation.declaration_valid ? &ability->activation : nullptr;
		}
		++current_activation_index;
	}
	return nullptr;
}

bool DuelNativeCompactKernel::can_pay_activation_cost(
	const NativeState &value,
	int32_t source_card_index,
	const CompiledActivation &activation
) const {
	return (
		activation.declaration_valid
		&& source_card_index >= 0
		&& source_card_index < static_cast<int32_t>(value.card_ki.size())
		&& activation.required_ki > 0
		&& value.card_ki[source_card_index] >= activation.required_ki
	);
}

bool DuelNativeCompactKernel::activation_targets_hand(
	const CompiledActivation &activation
) const {
	return (
		activation.target_rule == TargetRuleOpcode::ENEMY_HAND_CARD
		|| activation.target_rule == TargetRuleOpcode::ALLY_HAND_CARD
	);
}

bool DuelNativeCompactKernel::activation_target_matches(
	const NativeState &value,
	int32_t owner_id,
	int32_t target_cell,
	TargetRuleOpcode target_rule
) const {
	if (
		target_cell < 0
		|| target_cell >= static_cast<int32_t>(value.board_card_indices.size())
	) return false;
	const int32_t target_card_index = value.board_card_indices[target_cell];
	switch (target_rule) {
		case TargetRuleOpcode::ADJACENT_EMPTY_BOARD:
		case TargetRuleOpcode::ANY_EMPTY_BOARD:
			return target_card_index < 0;
		case TargetRuleOpcode::ADJACENT_ALLY_BOARD:
		case TargetRuleOpcode::OTHER_ALLY_BOARD:
			return target_card_index >= 0 && value.board_owners[target_cell] == owner_id;
		case TargetRuleOpcode::ADJACENT_ENEMY_BOARD:
		case TargetRuleOpcode::ANY_ENEMY_BOARD:
			return target_card_index >= 0 && value.board_owners[target_cell] != owner_id;
		default:
			return false;
	}
}

int32_t DuelNativeCompactKernel::count_activation_target_indices(
	const NativeState &value,
	int32_t owner_id,
	int32_t source_cell,
	const CompiledActivation &activation
) const {
	if (
		owner_id < 1 || owner_id > 2
		|| source_cell < 0
		|| source_cell >= static_cast<int32_t>(value.board_card_indices.size())
		|| value.board_card_indices[source_cell] < 0
		|| value.board_owners[source_cell] != owner_id
		|| !activation.declaration_valid
	) return 0;
	if (activation_targets_hand(activation)) {
		const int32_t target_owner = (
			activation.target_rule == TargetRuleOpcode::ENEMY_HAND_CARD
			? other_owner(owner_id)
			: owner_id
		);
		const int32_t zone_index = target_owner - 1;
		return (
			zone_index >= 0 && zone_index < static_cast<int32_t>(value.zones.size())
			? static_cast<int32_t>(value.zones[zone_index].size())
			: 0
		);
	}
	int32_t count = 0;
	if (
		activation.target_rule == TargetRuleOpcode::OTHER_ALLY_BOARD
		|| activation.target_rule == TargetRuleOpcode::ANY_EMPTY_BOARD
		|| activation.target_rule == TargetRuleOpcode::ANY_ENEMY_BOARD
	) {
		for (size_t target_cell = 0; target_cell < value.board_card_indices.size(); ++target_cell) {
			if (
				static_cast<int32_t>(target_cell) != source_cell
				&& activation_target_matches(
					value,
					owner_id,
					static_cast<int32_t>(target_cell),
					activation.target_rule
				)
			) count += 1;
		}
		return count;
	}
	for (int32_t direction = 0; direction < 4; ++direction) {
		if (activation_target_matches(
			value,
			owner_id,
			neighbor_index(source_cell, direction),
			activation.target_rule
		)) count += 1;
	}
	return count;
}

std::vector<int32_t> DuelNativeCompactKernel::get_activation_target_indices(
	const NativeState &value,
	int32_t owner_id,
	int32_t source_cell,
	const CompiledActivation &activation
) const {
	std::vector<int32_t> targets;
	if (
		owner_id < 1 || owner_id > 2
		|| source_cell < 0
		|| source_cell >= static_cast<int32_t>(value.board_card_indices.size())
		|| value.board_card_indices[source_cell] < 0
		|| value.board_owners[source_cell] != owner_id
		|| !activation.declaration_valid
	) {
		return targets;
	}
	if (activation_targets_hand(activation)) {
		const int32_t target_owner = (
			activation.target_rule == TargetRuleOpcode::ENEMY_HAND_CARD
			? other_owner(owner_id)
			: owner_id
		);
		const int32_t zone_index = target_owner - 1;
		if (zone_index < 0 || zone_index >= static_cast<int32_t>(value.zones.size())) {
			return targets;
		}
		targets.reserve(value.zones[zone_index].size());
		for (size_t index = 0; index < value.zones[zone_index].size(); ++index) {
			targets.push_back(static_cast<int32_t>(index));
		}
		return targets;
	}

	if (
		activation.target_rule == TargetRuleOpcode::OTHER_ALLY_BOARD
		|| activation.target_rule == TargetRuleOpcode::ANY_EMPTY_BOARD
		|| activation.target_rule == TargetRuleOpcode::ANY_ENEMY_BOARD
	) {
		for (size_t target_cell = 0; target_cell < value.board_card_indices.size(); ++target_cell) {
			if (
				static_cast<int32_t>(target_cell) != source_cell
				&& activation_target_matches(
					value,
					owner_id,
					static_cast<int32_t>(target_cell),
					activation.target_rule
				)
			) targets.push_back(static_cast<int32_t>(target_cell));
		}
		return targets;
	}
	for (int32_t direction = 0; direction < 4; ++direction) {
		const int32_t target_cell = neighbor_index(source_cell, direction);
		if (activation_target_matches(
			value,
			owner_id,
			target_cell,
			activation.target_rule
		)) targets.push_back(target_cell);
	}
	return targets;
}

bool DuelNativeCompactKernel::card_has_enabled_modifiers(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id
) const {
	if (!card_effects_enabled(value, card_index, owner_id)) {
		return false;
	}
	for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[card_index].size(); ++ability_index) {
		const CompiledAbility *ability = runtime_ability(value, card_index, static_cast<int32_t>(ability_index));
		if (ability != nullptr && !ability->modifiers.empty()) return true;
	}
	return false;
}

bool DuelNativeCompactKernel::card_has_enabled_event(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id,
	const StringName &event_id
) const {
	if (!card_effects_enabled(value, card_index, owner_id)) {
		return false;
	}
	for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[card_index].size(); ++ability_index) {
		const CompiledAbility *ability = runtime_ability(value, card_index, static_cast<int32_t>(ability_index));
		if (ability == nullptr) continue;
		for (const CompiledTriggerRule &rule : ability->triggers) {
			if (rule.event_id == event_id) return true;
		}
	}
	return false;
}

bool DuelNativeCompactKernel::card_has_unsupported_enabled_modifier(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id
) const {
	if (!card_effects_enabled(value, card_index, owner_id)) return false;
	for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[card_index].size(); ++ability_index) {
		const CompiledAbility *ability = runtime_ability(value, card_index, static_cast<int32_t>(ability_index));
		if (ability == nullptr) continue;
		for (const CompiledModifier &modifier : ability->modifiers) {
			if (modifier.opcode == ModifierOpcode::UNSUPPORTED) return true;
		}
	}
	return false;
}

bool DuelNativeCompactKernel::card_has_modifier(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id,
	ModifierOpcode opcode,
	int32_t *out_value
) const {
	if (!card_effects_enabled(value, card_index, owner_id)) return false;
	bool found = false;
	for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[card_index].size(); ++ability_index) {
		const CompiledAbility *ability = runtime_ability(value, card_index, static_cast<int32_t>(ability_index));
		if (ability == nullptr) continue;
		for (const CompiledModifier &modifier : ability->modifiers) {
			if (modifier.opcode == opcode) {
				found = true;
				if (out_value != nullptr) *out_value = modifier.value;
			}
		}
	}
	return found;
}

bool DuelNativeCompactKernel::card_modifier_has_flag(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id,
	ModifierOpcode opcode,
	int32_t flag
) const {
	if (!card_effects_enabled(value, card_index, owner_id)) return false;
	for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[card_index].size(); ++ability_index) {
		const CompiledAbility *ability = runtime_ability(value, card_index, static_cast<int32_t>(ability_index));
		if (ability == nullptr) continue;
		for (const CompiledModifier &modifier : ability->modifiers) {
			if (modifier.opcode == opcode && (modifier.value & flag) != 0) return true;
		}
	}
	return false;
}

int32_t DuelNativeCompactKernel::count_owned(
	const NativeState &value,
	int32_t owner_id
) const {
	int32_t count = 0;
	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		if (value.board_card_indices[cell] >= 0 && value.board_owners[cell] == owner_id) ++count;
	}
	return count;
}

bool DuelNativeCompactKernel::attack_is_prohibited(
	const NativeState &value,
	int32_t attacker_owner
) const {
	if (attacker_owner != 1 && attacker_owner != 2) return true;
	const int32_t turn_owner = value.scalars[0];
	if (turn_owner == attacker_owner) return false;
	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		const int32_t source_card_index = value.board_card_indices[cell];
		if (source_card_index < 0 || value.board_owners[cell] != turn_owner) continue;
		if (card_has_modifier(
			value,
			source_card_index,
			turn_owner,
			ModifierOpcode::ENEMY_CANNOT_ATTACK_DURING_OWNER_TURN
		)) return true;
	}
	return false;
}

std::vector<int32_t> DuelNativeCompactKernel::snapshot_summon_attack_redirect_sources(
	const NativeState &value,
	int32_t summon_cell,
	int32_t summoning_owner
) const {
	std::vector<int32_t> sources;
	for (int32_t direction = 0; direction < 4; ++direction) {
		const int32_t source_cell = neighbor_index(summon_cell, direction);
		if (source_cell < 0) continue;
		const int32_t source_card_index = value.board_card_indices[source_cell];
		const int32_t source_owner = value.board_owners[source_cell];
		if (source_card_index < 0 || source_owner == summoning_owner) continue;
		if (card_has_modifier(
			value,
			source_card_index,
			source_owner,
			ModifierOpcode::ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES
		)) sources.push_back(source_card_index);
	}
	return sources;
}

DuelNativeCompactKernel::AttackPolicy DuelNativeCompactKernel::get_summon_attack_policy(
	const NativeState &value,
	int32_t summoned_cell,
	int32_t summoning_owner,
	const std::vector<int32_t> &source_card_indices
) const {
	AttackPolicy policy;
	for (const int32_t source_card_index : source_card_indices) {
		const int32_t source_cell = find_board_card(value, source_card_index);
		if (source_cell < 0) continue;
		const int32_t row_delta = std::abs(source_cell / 3 - summoned_cell / 3);
		const int32_t column_delta = std::abs(source_cell % 3 - summoned_cell % 3);
		if (row_delta + column_delta != 1) continue;
		const int32_t source_owner = value.board_owners[source_cell];
		if (source_owner == summoning_owner) continue;
		if (!card_has_modifier(
			value,
			source_card_index,
			source_owner,
			ModifierOpcode::ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES
		)) continue;
		policy.target_policy = AttackTargetPolicy::ALLIES_ONLY;
		policy.specified = true;
		return policy;
	}
	return policy;
}

DuelNativeCompactKernel::AttackPolicy DuelNativeCompactKernel::get_standard_attack_policy(
	const NativeState &value,
	int32_t attacker_cell,
	int32_t attacker_card_index,
	int32_t attacker_owner,
	const AttackPolicy &requested_policy
) const {
	if (
		attacker_cell >= 0
		&& attacker_cell < static_cast<int32_t>(value.board_card_indices.size())
		&& value.board_card_indices[attacker_cell] == attacker_card_index
		&& card_has_modifier(
			value,
			attacker_card_index,
			attacker_owner,
			ModifierOpcode::SELF_ATTACKS_ALL
		)
	) {
		AttackPolicy policy;
		policy.target_policy = AttackTargetPolicy::ALL;
		policy.specified = true;
		return policy;
	}
	if (requested_policy.specified) return requested_policy;
	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		const int32_t source_card_index = value.board_card_indices[cell];
		const int32_t source_owner = value.board_owners[cell];
		if (source_card_index < 0 || source_owner == attacker_owner) continue;
		if (!card_has_modifier(
			value,
			source_card_index,
			source_owner,
			ModifierOpcode::ENEMY_ATTACKS_ALL
		)) continue;
		AttackPolicy policy;
		policy.target_policy = AttackTargetPolicy::ALL;
		policy.capture_owner_id = source_owner;
		policy.specified = true;
		return policy;
	}
	return AttackPolicy();
}

std::vector<int32_t> DuelNativeCompactKernel::get_attack_targets(
	const NativeState &value,
	int32_t source_cell,
	const AttackPolicy &policy
) const {
	std::vector<int32_t> targets;
	if (
		source_cell < 0
		|| source_cell >= static_cast<int32_t>(value.board_card_indices.size())
		|| value.board_card_indices[source_cell] < 0
	) return targets;
	const int32_t source_card_index = value.board_card_indices[source_cell];
	const int32_t source_owner = value.board_owners[source_cell];
	const bool unlimited_range = card_has_modifier(
		value,
		source_card_index,
		source_owner,
		ModifierOpcode::UNLIMITED_ATTACK_RANGE
	);
	std::vector<int32_t> candidates;
	if (unlimited_range) {
		for (int32_t cell = 0; cell < static_cast<int32_t>(value.board_card_indices.size()); ++cell) {
			if (cell != source_cell) candidates.push_back(cell);
		}
	} else {
		for (int32_t direction = 0; direction < 4; ++direction) {
			const int32_t adjacent_cell = neighbor_index(source_cell, direction);
			if (adjacent_cell < 0) continue;
			candidates.push_back(adjacent_cell);
			const int32_t distance_two_cell = neighbor_index(adjacent_cell, direction);
			if (distance_two_cell >= 0) candidates.push_back(distance_two_cell);
		}
	}
	const bool first_legal_only = card_has_modifier(
		value,
		source_card_index,
		source_owner,
		ModifierOpcode::STANDARD_ATTACK_FIRST_LEGAL_TARGET
	);
	for (const int32_t target_cell : candidates) {
		if (!can_attack_target(value, source_cell, target_cell, policy, false)) continue;
		targets.push_back(target_cell);
		if (first_legal_only) break;
	}
	return targets;
}

bool DuelNativeCompactKernel::can_attack_target(
	const NativeState &value,
	int32_t source_cell,
	int32_t target_cell,
	const AttackPolicy &policy,
	bool skip_power_comparison
) const {
	if (
		source_cell < 0
		|| source_cell >= static_cast<int32_t>(value.board_card_indices.size())
		|| value.board_card_indices[source_cell] < 0
	) return false;
	const int32_t source_card_index = value.board_card_indices[source_cell];
	const int32_t source_owner = value.board_owners[source_cell];
	if (
		card_has_modifier(
			value,
			source_card_index,
			source_owner,
			ModifierOpcode::ATTACK_REQUIRES_OTHER_ALLY
		)
		&& count_owned(value, source_owner) < 2
	) return false;
	return is_target_in_attack_range(
		value,
		source_cell,
		target_cell,
		policy,
		skip_power_comparison
	);
}

bool DuelNativeCompactKernel::is_target_in_attack_range(
	const NativeState &value,
	int32_t source_cell,
	int32_t target_cell,
	const AttackPolicy &policy,
	bool skip_power_comparison
) const {
	if (
		source_cell < 0
		|| source_cell >= static_cast<int32_t>(value.board_card_indices.size())
		|| target_cell < 0
		|| target_cell >= static_cast<int32_t>(value.board_card_indices.size())
		|| source_cell == target_cell
		|| value.board_card_indices[source_cell] < 0
		|| value.board_card_indices[target_cell] < 0
	) return false;
	const int32_t source_card_index = value.board_card_indices[source_cell];
	const int32_t target_card_index = value.board_card_indices[target_cell];
	const int32_t source_owner = value.board_owners[source_cell];
	const int32_t target_owner = value.board_owners[target_cell];
	if (
		(policy.target_policy == AttackTargetPolicy::ENEMIES_ONLY && source_owner == target_owner)
		|| (policy.target_policy == AttackTargetPolicy::ALLIES_ONLY && source_owner != target_owner)
	) return false;

	const int32_t source_row = source_cell / 3;
	const int32_t source_column = source_cell % 3;
	const int32_t target_row = target_cell / 3;
	const int32_t target_column = target_cell % 3;
	const int32_t row_delta = target_row - source_row;
	const int32_t column_delta = target_column - source_column;
	const bool same_axis = row_delta == 0 || column_delta == 0;
	const bool unlimited_range = card_has_modifier(
		value,
		source_card_index,
		source_owner,
		ModifierOpcode::UNLIMITED_ATTACK_RANGE
	);
	if (!same_axis && !unlimited_range) return false;
	if (
		!same_axis
		&& !card_has_modifier(
			value,
			source_card_index,
			source_owner,
			ModifierOpcode::NON_ORTHOGONAL_ATTACK_ANY_AXIS
		)
	) return false;

	int32_t direction = -1;
	int32_t distance = 0;
	if (same_axis) {
		if (row_delta < 0) direction = 0;
		else if (column_delta > 0) direction = 1;
		else if (row_delta > 0) direction = 2;
		else if (column_delta < 0) direction = 3;
		distance = std::max(std::abs(row_delta), std::abs(column_delta));
	}
	if (!unlimited_range && distance > 2) return false;
	if (!unlimited_range && distance == 2) {
		if (!card_has_modifier(
			value,
			source_card_index,
			source_owner,
			ModifierOpcode::ORTHOGONAL_ATTACK_RANGE_TWO
		)) return false;
		const int32_t intervening_cell = neighbor_index(source_cell, direction);
		const int32_t intervening_card_index = value.board_card_indices[intervening_cell];
		if (intervening_card_index >= 0) {
			const bool intervening_is_ally = value.board_owners[intervening_cell] == source_owner;
			const int32_t required_flag = intervening_is_ally ? 1 : 2;
			if (!card_modifier_has_flag(
				value,
				source_card_index,
				source_owner,
				ModifierOpcode::ORTHOGONAL_ATTACK_RANGE_TWO,
				required_flag
			)) return false;
		}
	}
	if (skip_power_comparison) return true;

	const bool comparison_reversed = (
		card_has_modifier(
			value,
			source_card_index,
			source_owner,
			ModifierOpcode::POWER_COMPARISON_REVERSED
		)
		|| card_has_modifier(
			value,
			target_card_index,
			target_owner,
			ModifierOpcode::POWER_COMPARISON_REVERSED
		)
	);
	static constexpr int32_t opposite[4] = {2, 3, 0, 1};
	if (same_axis) {
		return power_pair_wins(
			value,
			source_card_index,
			source_owner,
			target_card_index,
			target_owner,
			direction,
			opposite[direction],
			comparison_reversed
		);
	}
	const int32_t vertical_direction = row_delta < 0 ? 0 : 2;
	const int32_t horizontal_direction = column_delta < 0 ? 3 : 1;
	return (
		power_pair_wins(
			value,
			source_card_index,
			source_owner,
			target_card_index,
			target_owner,
			vertical_direction,
			opposite[vertical_direction],
			comparison_reversed
		)
		|| power_pair_wins(
			value,
			source_card_index,
			source_owner,
			target_card_index,
			target_owner,
			horizontal_direction,
			opposite[horizontal_direction],
			comparison_reversed
		)
	);
}

bool DuelNativeCompactKernel::power_pair_wins(
	const NativeState &value,
	int32_t source_card_index,
	int32_t source_owner,
	int32_t target_card_index,
	int32_t target_owner,
	int32_t attacking_direction,
	int32_t defending_direction,
	bool comparison_reversed
) const {
	if (is_special_negative(value, source_card_index)) return false;
	const int32_t attacking_power = value.card_powers[source_card_index * 4 + attacking_direction];
	if (is_special_negative(value, target_card_index)) return attacking_power >= 0;
	const int32_t defending_power = (
		card_has_modifier(
			value,
			source_card_index,
			source_owner,
			ModifierOpcode::DEFENDING_POWER_USES_MINIMUM_SIDE
		)
		? minimum_effective_defending_power(value, target_card_index, target_owner)
		: effective_defending_power(value, target_card_index, target_owner, defending_direction)
	);
	return comparison_reversed ? attacking_power < defending_power : attacking_power > defending_power;
}

void DuelNativeCompactKernel::append_resolution(
	Resolution &destination,
	const Resolution &addition
) const {
	if (!addition.supported) {
		destination.supported = false;
		if (destination.reason.is_empty()) destination.reason = addition.reason;
	}
	const int64_t event_offset = destination.events.size();
	destination.events.append_array(addition.events);
	for (const auto &range : addition.protected_power_batch_ranges) {
		destination.protected_power_batch_ranges.push_back({
			range.first + event_offset,
			range.second + event_offset,
		});
	}
	if (include_presentation_payloads) {
		for (int64_t index = 0; index < addition.captures.size(); ++index) {
			const Variant value = addition.captures[index];
			if (destination.captures.find(value) < 0) destination.captures.append(value);
		}
		for (int64_t index = 0; index < addition.exiles.size(); ++index) {
			const Variant value = addition.exiles[index];
			if (destination.exiles.find(value) < 0) destination.exiles.append(value);
		}
	}
	destination.extra_play_requests.insert(
		destination.extra_play_requests.end(),
		addition.extra_play_requests.begin(),
		addition.extra_play_requests.end()
	);
	destination.flip_prevented = destination.flip_prevented || addition.flip_prevented;
}

bool DuelNativeCompactKernel::resolution_has_output(const Resolution &resolution) const {
	return (
		!resolution.events.is_empty()
		|| !resolution.captures.is_empty()
		|| !resolution.exiles.is_empty()
	);
}


} // namespace godot
