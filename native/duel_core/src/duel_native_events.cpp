#include "duel_native_compact_kernel_internal.h"

namespace godot {
using namespace duel_native_internal;

bool DuelNativeCompactKernel::conditions_match(
	const NativeState &value,
	const EventGroup &group,
	const CompiledTriggerRule &rule,
	const EventContext &context,
	bool &supported
) const {
	supported = true;
	for (const CompiledCondition &condition : rule.conditions) {
		bool matched = false;
		switch (condition.opcode) {
			case ConditionOpcode::TRIGGER_CARD_IS_SELF:
				matched = context.trigger_card_index == group.source_card_index;
				break;
			case ConditionOpcode::TRIGGER_CARD_IS_ALLY:
			case ConditionOpcode::TRIGGER_CARD_IS_ENEMY: {
				const int32_t trigger_cell = find_board_card(
					value,
					context.trigger_card_index,
					context.trigger_cell
				);
				matched = (
					trigger_cell == context.trigger_cell
					&& trigger_cell >= 0
					&& (
						(value.board_owners[trigger_cell] == group.source_owner)
						== (condition.opcode == ConditionOpcode::TRIGGER_CARD_IS_ALLY)
					)
				);
				break;
			}
			case ConditionOpcode::TRIGGER_CARD_IN_RANGE: {
				const int32_t trigger_cell = find_board_card(
					value,
					context.trigger_card_index,
					context.trigger_cell
				);
				AttackPolicy policy;
				matched = (
					trigger_cell == context.trigger_cell
					&& trigger_cell >= 0
					&& is_target_in_attack_range(
						value,
						group.source_cell,
						trigger_cell,
						policy,
						false
					)
				);
				break;
			}
			case ConditionOpcode::TRIGGER_CARD_ADJACENT_TO_SOURCE:
				for (int32_t direction = 0; direction < 4; ++direction) {
					if (neighbor_index(group.source_cell, direction) == context.trigger_cell) {
						matched = true;
						break;
					}
				}
				break;
			case ConditionOpcode::TRIGGER_CARD_OUTSIDE_SOURCE_OWNER_HAND:
				matched = !(context.trigger_zone == 1 && context.trigger_owner == group.source_owner);
				break;
			case ConditionOpcode::TRIGGER_CARD_REVEALED_TO_SELF:
				if (
					context.trigger_card_index >= 0
					&& context.trigger_card_index < static_cast<int32_t>(value.card_reveal_codes.size())
					&& find_board_card(value, context.trigger_card_index, context.trigger_cell)
						== context.trigger_cell
				) {
					const uint8_t reveal_code = value.card_reveal_codes[context.trigger_card_index];
					matched = group.source_owner == 1
						? (reveal_code == 1 || reveal_code == 3 || reveal_code == 4)
						: (reveal_code == 2 || reveal_code == 3 || reveal_code == 4);
				}
				break;
			case ConditionOpcode::TRIGGER_CARD_WAS_ENEMY: {
				const int32_t previous_owner = (
					context.trigger_previous_owner != 0
					? context.trigger_previous_owner
					: context.trigger_owner
				);
				matched = previous_owner != 0 && previous_owner != group.source_owner;
				break;
			}
			case ConditionOpcode::TRIGGER_CARD_ORIGINAL_OWNER_IS_SELF:
				matched = (
					context.trigger_card_index >= 0
					&& context.trigger_card_index < static_cast<int32_t>(value.card_original_owners.size())
					&& find_board_card(value, context.trigger_card_index, context.trigger_cell) >= 0
					&& value.card_original_owners[context.trigger_card_index] == group.source_owner
				);
				break;
			case ConditionOpcode::ATTACKED_CARD_IS_SELF:
				matched = context.attacked_card_index == group.source_card_index;
				break;
			case ConditionOpcode::ATTACKER_CARD_IS_SELF:
				matched = context.attacker_card_index == group.source_card_index;
				break;
			case ConditionOpcode::ATTACKER_CARD_IS_ENEMY:
				matched = context.attacker_owner != 0 && context.attacker_owner != group.source_owner;
				break;
			case ConditionOpcode::ATTACKER_CARD_IS_OTHER_ALLY:
				matched = (
					context.attacker_card_index >= 0
					&& context.attacker_card_index != group.source_card_index
					&& context.attacker_owner == group.source_owner
				);
				break;
			case ConditionOpcode::ATTACK_IS_NOT_REPEAT:
				matched = !context.repeat_attack;
				break;
			case ConditionOpcode::ACTIVATION_OWNER_IS_ALLY:
				matched = (
					(context.activation_owner == 1 || context.activation_owner == 2)
					&& context.activation_owner == group.source_owner
				);
				break;
			case ConditionOpcode::TRIGGER_CARD_WAS_ON_BOARD:
				matched = context.trigger_was_on_board;
				break;
			case ConditionOpcode::ATTACK_FLIPPED_ENEMY:
				matched = context.attack_flipped_enemy;
				break;
			case ConditionOpcode::ATTACK_FLIPPED_ALLY_IN_RANGE: {
				AttackPolicy policy;
				for (const EventContext::AttackFlipRecord &record : context.attack_flips) {
					if (record.previous_owner != group.source_owner) continue;
					const int32_t target_cell = find_board_card(value, record.card_index, -1);
					if (
						target_cell >= 0
						&& is_target_in_attack_range(
							value,
							group.source_cell,
							target_cell,
							policy,
							false
						)
					) {
						matched = true;
						break;
					}
				}
				break;
			}
			case ConditionOpcode::TRIGGER_CARD_POWERS_COULD_CHANGE:
				matched = context.trigger_card_index >= 0 && can_change_powers(value, context.trigger_card_index);
				break;
			case ConditionOpcode::DRAWN_CARD_IS_ENEMY:
				matched = context.trigger_owner != 0 && context.trigger_owner != group.source_owner;
				break;
			case ConditionOpcode::TURN_OWNER_IS_SELF:
				matched = context.turn_owner != 0 && context.turn_owner == group.source_owner;
				break;
			case ConditionOpcode::OWNER_DID_NOT_WIN:
				matched = std::find(
					context.winning_owners.begin(),
					context.winning_owners.end(),
					group.source_owner
				) == context.winning_owners.end();
				break;
			case ConditionOpcode::KI_AT_LEAST:
				matched = value.card_ki[group.source_card_index] >= condition.amount;
				break;
			case ConditionOpcode::KI_CHANGED_CARD_IS_SELF:
				matched = context.trigger_card_index == group.source_card_index && context.trigger_cell == group.source_cell;
				break;
			case ConditionOpcode::KI_REACHED_ZERO:
				matched = context.previous_ki > 0 && context.ki == 0;
				break;
			case ConditionOpcode::MOVING_CARD_IS_SELF:
				matched = (
					context.moving_card_index == group.source_card_index
					&& context.moving_source_cell == group.source_cell
				);
				break;
			case ConditionOpcode::MOVING_CARD_IS_ALLY:
				matched = (
					context.moving_card_index >= 0
					&& (context.moving_owner == 1 || context.moving_owner == 2)
					&& context.moving_owner == group.source_owner
				);
				break;
			case ConditionOpcode::DISCARD_OWNER_IS_SELF:
				matched = context.discard_owner != 0 && context.discard_owner == group.source_owner;
				break;
			case ConditionOpcode::SOURCE_HAS_ADJACENT_EMPTY_CELL:
				for (int32_t direction = 0; direction < 4; ++direction) {
					const int32_t candidate = neighbor_index(group.source_cell, direction);
					if (candidate >= 0 && value.board_card_indices[candidate] < 0) {
						matched = true;
						break;
					}
				}
				break;
			case ConditionOpcode::SOURCE_HAS_EMPTY_BETWEEN_ENEMY:
				for (int32_t direction = 0; direction < 4; ++direction) {
					const int32_t middle = neighbor_index(group.source_cell, direction);
					if (middle < 0 || value.board_card_indices[middle] >= 0) continue;
					const int32_t far = neighbor_index(middle, direction);
					if (
						far >= 0
						&& value.board_card_indices[far] >= 0
						&& value.board_owners[far] != group.source_owner
					) {
						matched = true;
						break;
					}
				}
				break;
			default:
				supported = false;
				return false;
		}
		if (!matched) return false;
	}
	return true;
}

std::vector<DuelNativeCompactKernel::EventGroup> DuelNativeCompactKernel::discover_event(
	const NativeState &value,
	const StringName &event_id,
	const EventContext &context,
	bool &supported,
	String &reason
) const {
	std::vector<EventGroup> groups;
	supported = true;
	auto discover_card = [&](int32_t card_index, int32_t owner_id, int32_t source_cell, int32_t source_zone, int32_t logical_index) -> bool {
		if (!card_effects_enabled(value, card_index, owner_id)) return true;
		for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[card_index].size(); ++ability_index) {
			const CompiledAbility *ability = runtime_ability(value, card_index, static_cast<int32_t>(ability_index));
			if (ability == nullptr) continue;
			for (size_t trigger_index = 0; trigger_index < ability->triggers.size(); ++trigger_index) {
				const CompiledTriggerRule &rule = ability->triggers[trigger_index];
				if (rule.event_id != event_id) continue;
				EventGroup group;
				group.source_cell = source_cell;
				group.source_zone = source_zone;
				group.source_logical_index = logical_index;
				group.source_card_index = card_index;
				group.source_owner = owner_id;
				group.ability_index = static_cast<int32_t>(ability_index);
				group.ability_handle = value.card_runtime_abilities[card_index][ability_index].handle;
				group.trigger_index = static_cast<int32_t>(trigger_index);
				bool condition_supported = true;
				if (conditions_match(value, group, rule, context, condition_supported)) {
					groups.push_back(group);
				} else if (!condition_supported) {
					supported = false;
					reason = "Relevant event uses an unsupported trigger condition";
					return false;
				}
			}
		}
		return true;
	};
	if (event_id == StringName("card_after_discarded")) {
		int32_t zone = -1;
		int32_t owner_id = 0;
		int32_t logical_index = -1;
		if (
			context.trigger_card_index >= 0
			&& locate_card(value, context.trigger_card_index, zone, owner_id, logical_index)
			&& zone == 3
			&& owner_id == context.trigger_owner
		) {
			discover_card(context.trigger_card_index, owner_id, -1, 3, logical_index);
		}
		return groups;
	}
	if (event_id == StringName("card_before_summoned")) {
		const int32_t trigger_cell = find_board_card(
			value,
			context.trigger_card_index,
			context.trigger_cell
		);
		if (trigger_cell == context.trigger_cell && trigger_cell >= 0) {
			discover_card(
				context.trigger_card_index,
				value.board_owners[trigger_cell],
				trigger_cell,
				0,
				trigger_cell
			);
		}
		return groups;
	}
	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		const int32_t card_index = value.board_card_indices[cell];
		if (card_index < 0) continue;
		discover_card(
			card_index,
			value.board_owners[cell],
			static_cast<int32_t>(cell),
			0,
			static_cast<int32_t>(cell)
		);
		if (!supported) return groups;
	}
	return groups;
}

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::resolve_event(
	NativeState &value,
	const StringName &event_id,
	const EventContext &context,
	std::vector<int32_t> &exile_stack
) const {
	Resolution resolution;
	bool discovery_supported = true;
	String discovery_reason;
	const std::vector<EventGroup> groups = discover_event(
		value,
		event_id,
		context,
		discovery_supported,
		discovery_reason
	);
	if (!discovery_supported) {
		resolution.supported = false;
		resolution.reason = discovery_reason;
		return resolution;
	}
	for (const EventGroup &discovered_group : groups) {
		EventGroup group = discovered_group;
		const int32_t current_ability_index = find_runtime_ability_index(
			value,
			group.source_card_index,
			group.ability_handle,
			group.ability_index
		);
		bool source_is_current = false;
		int32_t current_logical_index = group.source_logical_index;
		if (group.source_zone == 3) {
			int32_t current_zone = -1;
			int32_t current_owner = 0;
			source_is_current = (
				locate_card(
					value,
					group.source_card_index,
					current_zone,
					current_owner,
					current_logical_index
				)
				&& current_zone == 3
				&& current_owner == group.source_owner
			);
		} else {
			const int32_t current_source_cell = find_board_card(
				value,
				group.source_card_index,
				group.source_cell
			);
			if (
				current_source_cell >= 0
				&& current_source_cell != group.source_cell
				&& group.source_card_index == context.trigger_card_index
			) {
				group.source_cell = current_source_cell;
				group.source_logical_index = current_source_cell;
				current_logical_index = current_source_cell;
			}
			source_is_current = (
				find_board_card(value, group.source_card_index, group.source_cell) == group.source_cell
				&& value.board_owners[group.source_cell] == group.source_owner
			);
		}
		if (
			!source_is_current
			|| !card_effects_enabled(value, group.source_card_index, group.source_owner)
			|| current_ability_index < 0
		) continue;
		const CompiledAbility *ability = runtime_ability(
			value,
			group.source_card_index,
			current_ability_index
		);
		if (
			ability == nullptr
			|| group.trigger_index < 0
			|| group.trigger_index >= static_cast<int32_t>(ability->triggers.size())
		) continue;
		const CompiledTriggerRule &rule = ability->triggers[group.trigger_index];
		bool condition_supported = true;
		if (!conditions_match(value, group, rule, context, condition_supported)) {
			if (!condition_supported) {
				resolution.supported = false;
				resolution.reason = "Relevant event uses an unsupported trigger condition";
				return resolution;
			}
			continue;
		}
		Dictionary triggered;
		triggered["type"] = StringName("ability_triggered");
		triggered["source_cell"] = group.source_cell;
		triggered["source_instance_id"] = value.card_instance_ids[group.source_card_index];
		triggered["source_owner_id"] = group.source_owner;
		resolution.events.append(triggered);
		ActionContext action_context;
		if (context.ability_source_card_index >= 0) {
			action_context.ability_source_cell = context.ability_source_cell;
			action_context.ability_source_zone = context.ability_source_zone;
			action_context.ability_source_logical_index = context.ability_source_logical_index;
			action_context.ability_source_card_index = context.ability_source_card_index;
			action_context.ability_source_owner = context.ability_source_owner;
		} else {
			action_context.ability_source_cell = group.source_cell;
			action_context.ability_source_zone = group.source_zone;
			action_context.ability_source_logical_index = current_logical_index;
			action_context.ability_source_card_index = group.source_card_index;
			action_context.ability_source_owner = group.source_owner;
		}
		action_context.action_subject_card_index = group.source_card_index;
		action_context.action_subject_owner = group.source_owner;
		action_context.action_subject_zone = group.source_zone;
		action_context.action_subject_logical_index = current_logical_index;
		action_context.trigger_card_index = context.trigger_card_index;
		action_context.attacker_card_index = context.attacker_card_index;
		action_context.activation_target_kind = context.activation_target_kind;
		action_context.activation_target_index = context.activation_target_index;
		action_context.event_id = event_id;
		action_context.discovery_ability_index = group.ability_index;
		action_context.trigger_index = group.trigger_index;
		action_context.attack_flips = context.attack_flips;
		const ActionOutcome outcome = execute_actions(
			value,
			group,
			rule.actions,
			context,
			action_context,
			exile_stack,
			resolution
		);
		if (outcome == ActionOutcome::UNSUPPORTED) {
			resolution.supported = false;
			if (resolution.reason.is_empty()) resolution.reason = "Relevant event uses an unsupported action";
			return resolution;
		}
	}
	return resolution;
}


} // namespace godot
