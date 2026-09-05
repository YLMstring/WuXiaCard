#include "duel_native_compact_kernel_internal.h"

namespace godot {
using namespace duel_native_internal;

bool DuelNativeCompactKernel::validate_shape() {
	const size_t card_count = state.card_instance_ids.size();
	if (state.scalars.size() != 14) {
		last_error = "Compact scalar count must be 13";
		return false;
	}
	if (state.board_card_indices.size() != state.board_owners.size()) {
		last_error = "Board card and owner arrays differ in size";
		return false;
	}
	if (state.zones.size() != 8) {
		last_error = "Compact zone count must be 8";
		return false;
	}
	if (
		state.card_template_indices.size() != card_count
		|| state.card_runtime_flags.size() != card_count
		|| state.card_powers.size() != card_count * 4
		|| state.card_original_owners.size() != card_count
		|| state.card_ki.size() != card_count
		|| state.card_active_ability_set_indices.size() != card_count
		|| state.card_reveal_codes.size() != card_count
		|| state.card_suppression_set_indices.size() != card_count
		|| state.card_hand_slots.size() != card_count
	) {
		last_error = "Compact card arrays differ in length";
		return false;
	}
	for (const FreshCardPrototype &prototype : state.fresh_card_prototypes) {
		if (prototype.card_id.is_empty()) {
			last_error = "Fresh-card prototype card ID cannot be empty";
			return false;
		}
		if (
			prototype.template_index < 0
			|| prototype.template_index >= state.card_template_pool.size()
		) {
			last_error = "Fresh-card prototype template index is out of range";
			return false;
		}
		if (
			prototype.active_ability_set_index < 0
			|| prototype.active_ability_set_index >= state.active_ability_set_pool.size()
		) {
			last_error = "Fresh-card prototype ability-set index is out of range";
			return false;
		}
	}
	if (
		state.empty_deck_draw_prototype_index < -1
		|| state.empty_deck_draw_prototype_index
			>= static_cast<int32_t>(state.fresh_card_prototypes.size())
	) {
		last_error = "Empty-deck fallback prototype index is out of range";
		return false;
	}
	return true;
}

// Native declarations are compiled once at root load. Runtime cards only retain
// small indices into these immutable structures.
DuelNativeCompactKernel::CompiledCondition DuelNativeCompactKernel::compile_condition(
	const Variant &value
) const {
	CompiledCondition compiled;
	if (value.get_type() != Variant::DICTIONARY) return compiled;
	const Dictionary condition = value;
	const StringName type = condition.get("type", StringName());
	if (
		type == StringName("ki_at_least") && condition.size() == 2
		&& Variant(condition.get("amount", 0)).get_type() == Variant::INT
	) {
		compiled.opcode = ConditionOpcode::KI_AT_LEAST;
		compiled.amount = static_cast<int32_t>(static_cast<int64_t>(condition.get("amount", 0)));
		return compiled;
	}
	if (
		type == StringName("last_discard_batch_size_at_least")
		&& condition.size() == 2
		&& Variant(condition.get("amount", 0)).get_type() == Variant::INT
		&& static_cast<int64_t>(condition.get("amount", 0)) > 0
	) {
		compiled.opcode = ConditionOpcode::LAST_DISCARD_BATCH_SIZE_AT_LEAST;
		compiled.amount = static_cast<int32_t>(static_cast<int64_t>(condition.get("amount", 0)));
		return compiled;
	}
	if (condition.size() != 1) return compiled;
	if (type == StringName("trigger_card_is_self")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_IS_SELF;
	else if (type == StringName("trigger_card_is_ally")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_IS_ALLY;
	else if (type == StringName("trigger_card_is_enemy")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_IS_ENEMY;
	else if (type == StringName("trigger_card_in_range")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_IN_RANGE;
	else if (type == StringName("trigger_card_adjacent_to_source")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_ADJACENT_TO_SOURCE;
	else if (type == StringName("trigger_card_outside_source_owner_hand")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_OUTSIDE_SOURCE_OWNER_HAND;
	else if (type == StringName("trigger_card_revealed_to_self")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_REVEALED_TO_SELF;
	else if (type == StringName("trigger_card_was_enemy")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_WAS_ENEMY;
	else if (type == StringName("trigger_card_original_owner_is_self")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_ORIGINAL_OWNER_IS_SELF;
	else if (type == StringName("attacked_card_is_self")) compiled.opcode = ConditionOpcode::ATTACKED_CARD_IS_SELF;
	else if (type == StringName("attacker_card_is_self")) compiled.opcode = ConditionOpcode::ATTACKER_CARD_IS_SELF;
	else if (type == StringName("attacker_card_is_enemy")) compiled.opcode = ConditionOpcode::ATTACKER_CARD_IS_ENEMY;
	else if (type == StringName("attacker_card_is_other_ally")) compiled.opcode = ConditionOpcode::ATTACKER_CARD_IS_OTHER_ALLY;
	else if (type == StringName("attack_is_not_repeat")) compiled.opcode = ConditionOpcode::ATTACK_IS_NOT_REPEAT;
	else if (type == StringName("activation_owner_is_ally")) compiled.opcode = ConditionOpcode::ACTIVATION_OWNER_IS_ALLY;
	else if (type == StringName("trigger_card_was_on_board")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_WAS_ON_BOARD;
	else if (type == StringName("attack_flipped_enemy")) compiled.opcode = ConditionOpcode::ATTACK_FLIPPED_ENEMY;
	else if (type == StringName("attack_flipped_ally_in_range")) compiled.opcode = ConditionOpcode::ATTACK_FLIPPED_ALLY_IN_RANGE;
	else if (type == StringName("trigger_card_powers_could_change")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_POWERS_COULD_CHANGE;
	else if (type == StringName("drawn_card_is_enemy")) compiled.opcode = ConditionOpcode::DRAWN_CARD_IS_ENEMY;
	else if (type == StringName("turn_owner_is_self")) compiled.opcode = ConditionOpcode::TURN_OWNER_IS_SELF;
	else if (type == StringName("owner_did_not_win")) compiled.opcode = ConditionOpcode::OWNER_DID_NOT_WIN;
	else if (type == StringName("ki_changed_card_is_self")) compiled.opcode = ConditionOpcode::KI_CHANGED_CARD_IS_SELF;
	else if (type == StringName("ki_reached_zero")) compiled.opcode = ConditionOpcode::KI_REACHED_ZERO;
	else if (type == StringName("moving_card_is_self")) compiled.opcode = ConditionOpcode::MOVING_CARD_IS_SELF;
	else if (type == StringName("moving_card_is_ally")) compiled.opcode = ConditionOpcode::MOVING_CARD_IS_ALLY;
	else if (type == StringName("source_owner_hand_empty")) compiled.opcode = ConditionOpcode::SOURCE_OWNER_HAND_EMPTY;
	else if (type == StringName("source_has_adjacent_empty_cell")) compiled.opcode = ConditionOpcode::SOURCE_HAS_ADJACENT_EMPTY_CELL;
	else if (type == StringName("source_has_empty_between_enemy")) compiled.opcode = ConditionOpcode::SOURCE_HAS_EMPTY_BETWEEN_ENEMY;
	else if (type == StringName("discard_owner_is_self")) compiled.opcode = ConditionOpcode::DISCARD_OWNER_IS_SELF;
	return compiled;
}

DuelNativeCompactKernel::CompiledSelectorCondition DuelNativeCompactKernel::compile_selector_condition(
	const Variant &value
) const {
	CompiledSelectorCondition compiled;
	if (value.get_type() != Variant::DICTIONARY) {
		compiled.declaration_valid = false;
		return compiled;
	}
	const Dictionary condition = value;
	const StringName type = condition.get("type", StringName());
	if (condition.size() == 1) {
		if (type == StringName("selected_card_is_ally")) compiled.opcode = SelectorConditionOpcode::IS_ALLY;
		else if (type == StringName("selected_card_is_enemy")) compiled.opcode = SelectorConditionOpcode::IS_ENEMY;
		else if (type == StringName("selected_card_is_not_source")) compiled.opcode = SelectorConditionOpcode::IS_NOT_SOURCE;
		else if (type == StringName("selected_card_adjacent_to_source")) compiled.opcode = SelectorConditionOpcode::ADJACENT_TO_SOURCE;
		else if (type == StringName("selected_card_surrounded_by_allies")) compiled.opcode = SelectorConditionOpcode::SURROUNDED_BY_ALLIES;
		else if (type == StringName("selected_card_original_owner_is_self")) compiled.opcode = SelectorConditionOpcode::ORIGINAL_OWNER_IS_SELF;
		else if (type == StringName("selected_card_original_owner_is_enemy")) compiled.opcode = SelectorConditionOpcode::ORIGINAL_OWNER_IS_ENEMY;
		else if (type == StringName("selected_card_flipped_by_current_attack")) compiled.opcode = SelectorConditionOpcode::FLIPPED_BY_CURRENT_ATTACK;
		else if (type == StringName("selected_card_powers_can_change")) compiled.opcode = SelectorConditionOpcode::POWERS_CAN_CHANGE;
		else if (type == StringName("selected_card_has_nonzero_power")) compiled.opcode = SelectorConditionOpcode::HAS_NONZERO_POWER;
		else if (type == StringName("selected_card_can_spend_ki")) compiled.opcode = SelectorConditionOpcode::CAN_SPEND_KI;
	} else if (
		type == StringName("selected_card_weapon_is")
		&& condition.size() == 2
		&& (
			Variant(condition.get("weapon", Variant())).get_type() == Variant::STRING
			|| Variant(condition.get("weapon", Variant())).get_type() == Variant::STRING_NAME
		)
	) {
		compiled.opcode = SelectorConditionOpcode::WEAPON_IS;
		compiled.weapon = String(condition.get("weapon", String()));
	} else if (
		type == StringName("selected_card_is_previous_hand_play")
		&& condition.size() == 2
	) {
		compiled.opcode = SelectorConditionOpcode::IS_PREVIOUS_HAND_PLAY;
		const StringName owner = condition.get("played_by", StringName());
		if (owner == StringName("ability_source")) compiled.relative_owner = RelativeOwnerOpcode::ABILITY_SOURCE;
		else if (owner == StringName("opponent_of_ability_source")) compiled.relative_owner = RelativeOwnerOpcode::OPPONENT_OF_ABILITY_SOURCE;
	} else if (
		type == StringName("selected_card_can_transfer_resource")
		&& (condition.size() == 3 || condition.size() == 4)
		&& Variant(condition.get("amount", 0)).get_type() == Variant::INT
		&& static_cast<int64_t>(condition.get("amount", 0)) > 0
	) {
		compiled.opcode = SelectorConditionOpcode::CAN_TRANSFER_RESOURCE;
		compiled.amount = static_cast<int32_t>(static_cast<int64_t>(condition.get("amount", 0)));
		auto compile_resource = [](const StringName &resource) {
			if (resource == StringName("ki")) return ResourceOpcode::KI;
			if (resource == StringName("powers")) return ResourceOpcode::POWERS;
			if (resource.is_empty()) return ResourceOpcode::NONE;
			return ResourceOpcode::UNSUPPORTED;
		};
		compiled.resource = compile_resource(condition.get("resource", StringName()));
		compiled.fallback_resource = compile_resource(condition.get("fallback_resource", StringName()));
	}
	if (compiled.opcode == SelectorConditionOpcode::UNSUPPORTED) {
		compiled.declaration_valid = false;
	}
	return compiled;
}

DuelNativeCompactKernel::CompiledSelector DuelNativeCompactKernel::compile_selector(
	const Variant &value
) const {
	CompiledSelector compiled;
	if (value.get_type() != Variant::DICTIONARY) {
		compiled.declaration_valid = false;
		return compiled;
	}
	const Dictionary selector = value;
	const Array keys = selector.keys();
	for (int64_t key_index = 0; key_index < keys.size(); ++key_index) {
		const StringName key = keys[key_index];
		if (
			key != StringName("zones") && key != StringName("conditions")
			&& key != StringName("limit") && key != StringName("required_count")
			&& key != StringName("order")
		) {
			compiled.declaration_valid = false;
		}
	}
	const Variant zones_value = selector.get("zones", Array());
	const Variant conditions_value = selector.get("conditions", Array());
	if (zones_value.get_type() != Variant::ARRAY || conditions_value.get_type() != Variant::ARRAY) {
		compiled.declaration_valid = false;
		return compiled;
	}
	const Array zones = zones_value;
	for (int64_t index = 0; index < zones.size(); ++index) {
		const StringName zone = zones[index];
		if (zone == StringName("hand")) compiled.zones.push_back(SelectorZoneOpcode::HAND);
		else if (zone == StringName("board")) compiled.zones.push_back(SelectorZoneOpcode::BOARD);
		else if (zone == StringName("discard")) compiled.zones.push_back(SelectorZoneOpcode::DISCARD);
		else if (zone == StringName("removed")) compiled.zones.push_back(SelectorZoneOpcode::REMOVED);
		else compiled.declaration_valid = false;
	}
	const Array conditions = conditions_value;
	for (int64_t index = 0; index < conditions.size(); ++index) {
		const CompiledSelectorCondition condition = compile_selector_condition(conditions[index]);
		if (!condition.declaration_valid) compiled.declaration_valid = false;
		compiled.conditions.push_back(condition);
	}
	for (const char *field : {"limit", "required_count"}) {
		const Variant field_value = selector.get(field, 0);
		if (field_value.get_type() != Variant::INT || static_cast<int64_t>(field_value) < 0) {
			compiled.declaration_valid = false;
		}
	}
	compiled.limit = static_cast<int32_t>(static_cast<int64_t>(selector.get("limit", 0)));
	compiled.required_count = static_cast<int32_t>(static_cast<int64_t>(selector.get("required_count", 0)));
	const Variant order_value = selector.get("order", StringName());
	if (order_value.get_type() != Variant::STRING_NAME && order_value.get_type() != Variant::STRING) {
		compiled.declaration_valid = false;
	} else {
		const StringName order = order_value;
		if (order == StringName("hand_right_to_left")) compiled.hand_right_to_left = true;
		else if (!order.is_empty()) compiled.declaration_valid = false;
	}
	return compiled;
}

DuelNativeCompactKernel::CompiledAction DuelNativeCompactKernel::compile_action(
	const Variant &value
) {
	CompiledAction compiled;
	if (value.get_type() != Variant::DICTIONARY) {
		compiled.declaration_valid = false;
		return compiled;
	}
	const Dictionary action = value;
	const StringName type = action.get("type", StringName());
	compiled.declaration_type = type;
	const Variant invalid_policy = action.get("on_invalid_context", Variant());
	if (invalid_policy.get_type() != Variant::NIL) {
		if (invalid_policy.get_type() != Variant::STRING_NAME || StringName(invalid_policy) != StringName("stop_rule")) {
			compiled.declaration_valid = false;
			return compiled;
		}
		compiled.stop_rule_on_invalid_context = true;
	}
	const Variant batch_group = action.get("power_change_batch_group", Variant());
	if (batch_group.get_type() != Variant::NIL) {
		if (batch_group.get_type() != Variant::STRING_NAME && batch_group.get_type() != Variant::STRING) {
			compiled.declaration_valid = false;
			return compiled;
		}
		compiled.power_change_batch_group = StringName(batch_group);
	}

	const int64_t generic_field_count = (
		(action.has("on_invalid_context") ? 1 : 0)
		+ (action.has("power_change_batch_group") ? 1 : 0)
	);
	auto compile_card_ref = [](const StringName &card_ref) {
		if (card_ref == StringName("selected_card")) return CardRefOpcode::SELECTED_CARD;
		if (card_ref == StringName("trigger_card")) return CardRefOpcode::TRIGGER_CARD;
		if (card_ref == StringName("ability_source")) return CardRefOpcode::ABILITY_SOURCE;
		if (card_ref == StringName("attacker_card")) return CardRefOpcode::ATTACKER_CARD;
		if (card_ref == StringName("last_summoned_card")) return CardRefOpcode::LAST_SUMMONED_CARD;
		return CardRefOpcode::UNSUPPORTED;
	};
	auto compile_resource = [](const StringName &resource) {
		if (resource == StringName("ki")) return ResourceOpcode::KI;
		if (resource == StringName("powers")) return ResourceOpcode::POWERS;
		if (resource.is_empty()) return ResourceOpcode::NONE;
		return ResourceOpcode::UNSUPPORTED;
	};
	auto compile_relative_owner = [](const StringName &owner) {
		if (owner == StringName("ability_source")) return RelativeOwnerOpcode::ABILITY_SOURCE;
		if (owner == StringName("opponent_of_ability_source")) return RelativeOwnerOpcode::OPPONENT_OF_ABILITY_SOURCE;
		if (owner == StringName("card_current_owner")) return RelativeOwnerOpcode::CARD_CURRENT;
		if (owner == StringName("card_original_owner")) return RelativeOwnerOpcode::CARD_ORIGINAL;
		return RelativeOwnerOpcode::UNSUPPORTED;
	};
	if (
		type == StringName("draw_cards")
		&& (action.size() == 2 + generic_field_count || action.size() == 3 + generic_field_count)
		&& Variant(action.get("amount", 0)).get_type() == Variant::INT
		&& static_cast<int64_t>(action.get("amount", 0)) > 0
		&& (
			!action.has("weapon")
			|| Variant(action.get("weapon", Variant())).get_type() == Variant::STRING
			|| Variant(action.get("weapon", Variant())).get_type() == Variant::STRING_NAME
		)
	) {
		compiled.opcode = ActionOpcode::DRAW_CARDS;
		compiled.amount = static_cast<int32_t>(static_cast<int64_t>(action.get("amount", 0)));
		compiled.weapon = String(action.get("weapon", String()));
	} else if (type == StringName("discard_card") && action.size() == 2 + generic_field_count) {
		compiled.opcode = ActionOpcode::DISCARD_CARD;
		compiled.card_ref = compile_card_ref(action.get("card", StringName()));
	} else if (
		type == StringName("discard_cards")
		&& action.size() == 2 + generic_field_count
		&& Variant(action.get("selector", Variant())).get_type() == Variant::DICTIONARY
	) {
		compiled.opcode = ActionOpcode::DISCARD_CARDS;
		compiled.selector = compile_selector(action.get("selector", Dictionary()));
		if (!compiled.selector.declaration_valid) compiled.declaration_valid = false;
	} else if (type == StringName("exile_card") && action.size() == 2 + generic_field_count) {
		compiled.opcode = ActionOpcode::EXILE_CARD;
		compiled.card_ref = compile_card_ref(action.get("card", StringName()));
	} else if (type == StringName("exile_self") && action.size() == 1 + generic_field_count) {
		compiled.opcode = ActionOpcode::EXILE_SELF;
	} else if (type == StringName("prevent_trigger_flip") && action.size() == 1 + generic_field_count) {
		compiled.opcode = ActionOpcode::PREVENT_TRIGGER_FLIP;
	} else if (type == StringName("remove_this_ability") && action.size() == 1 + generic_field_count) {
		compiled.opcode = ActionOpcode::REMOVE_THIS_ABILITY;
	} else if (
		type == StringName("for_each_selected_card")
		&& action.size() == 3 + generic_field_count
		&& Variant(action.get("selector", Variant())).get_type() == Variant::DICTIONARY
		&& Variant(action.get("actions", Variant())).get_type() == Variant::ARRAY
	) {
		compiled.opcode = ActionOpcode::FOR_EACH_SELECTED_CARD;
		compiled.selector = compile_selector(action.get("selector", Dictionary()));
		if (!compiled.selector.declaration_valid) compiled.declaration_valid = false;
		const Array children = action.get("actions", Array());
		compiled.child_actions.reserve(static_cast<size_t>(children.size()));
		for (int64_t child_index = 0; child_index < children.size(); ++child_index) {
			const CompiledAction child = compile_action(children[child_index]);
			if (!child.declaration_valid) compiled.declaration_valid = false;
			compiled.child_actions.push_back(child);
		}
	} else if (
		type == StringName("if")
		&& action.size() == 3 + generic_field_count
		&& Variant(action.get("conditions", Variant())).get_type() == Variant::ARRAY
		&& Variant(action.get("actions", Variant())).get_type() == Variant::ARRAY
	) {
		compiled.opcode = ActionOpcode::IF;
		const Array conditions = action.get("conditions", Array());
		const Array children = action.get("actions", Array());
		if (conditions.is_empty() || children.is_empty()) compiled.declaration_valid = false;
		compiled.conditions.reserve(static_cast<size_t>(conditions.size()));
		for (int64_t condition_index = 0; condition_index < conditions.size(); ++condition_index) {
			const CompiledCondition condition = compile_condition(conditions[condition_index]);
			if (condition.opcode == ConditionOpcode::UNSUPPORTED) compiled.declaration_valid = false;
			compiled.conditions.push_back(condition);
		}
		compiled.child_actions.reserve(static_cast<size_t>(children.size()));
		for (int64_t child_index = 0; child_index < children.size(); ++child_index) {
			const CompiledAction child = compile_action(children[child_index]);
			if (!child.declaration_valid) compiled.declaration_valid = false;
			compiled.child_actions.push_back(child);
		}
	} else if (type == StringName("change_powers") && action.size() == 3 + generic_field_count) {
		compiled.opcode = ActionOpcode::CHANGE_POWERS;
		compiled.card_ref = compile_card_ref(action.get("card", StringName()));
		const Variant amount = action.get("amount", Variant());
		if (amount.get_type() == Variant::INT && static_cast<int64_t>(amount) != 0) {
			compiled.amount = static_cast<int32_t>(static_cast<int64_t>(amount));
		} else if (amount.get_type() == Variant::DICTIONARY) {
			const Dictionary spec = amount;
			if (
				spec.size() == 3
				&& StringName(spec.get("type", StringName())) == StringName("card_count")
				&& StringName(spec.get("zone", StringName())) == StringName("hand")
			) {
				compiled.amount_is_hand_count = true;
				const StringName owner = spec.get("owner", StringName());
				if (owner == StringName("ability_source")) compiled.amount_owner = RelativeOwnerOpcode::ABILITY_SOURCE;
				else if (owner == StringName("card_current_owner")) compiled.amount_owner = RelativeOwnerOpcode::CARD_CURRENT;
			}
		}
	} else if (
		(type == StringName("gain_ki") || type == StringName("spend_ki"))
		&& (action.size() == 2 + generic_field_count || action.size() == 3 + generic_field_count)
		&& Variant(action.get("amount", 0)).get_type() == Variant::INT
		&& static_cast<int64_t>(action.get("amount", 0)) > 0
	) {
		compiled.opcode = type == StringName("gain_ki") ? ActionOpcode::GAIN_KI : ActionOpcode::SPEND_KI;
		compiled.amount = static_cast<int32_t>(static_cast<int64_t>(action.get("amount", 0)));
		compiled.card_ref_explicit = action.has("card");
		if (compiled.card_ref_explicit) compiled.card_ref = compile_card_ref(action.get("card", StringName()));
	} else if (type == StringName("flip_self") && action.size() == 2 + generic_field_count) {
		compiled.opcode = ActionOpcode::FLIP_SELF;
		const StringName owner = action.get("new_owner", StringName());
		if (owner == StringName("ability_source")) compiled.new_owner = RelativeOwnerOpcode::ABILITY_SOURCE;
		else if (owner == StringName("opponent_of_ability_source")) compiled.new_owner = RelativeOwnerOpcode::OPPONENT_OF_ABILITY_SOURCE;
	} else if (
		(type == StringName("grant_trigger_card_ability") || type == StringName("grant_ability_to_self"))
		&& action.size() == 2 + generic_field_count
	) {
		compiled.opcode = type == StringName("grant_trigger_card_ability")
			? ActionOpcode::GRANT_TRIGGER_CARD_ABILITY
			: ActionOpcode::GRANT_ABILITY_TO_SELF;
		const Variant granted = action.get("ability", Variant());
		if (granted.get_type() == Variant::DICTIONARY && !Dictionary(granted).is_empty()) {
			compiled.granted_ability_index = intern_compiled_ability(granted);
			if (!compiled_ability_pool[compiled.granted_ability_index].declaration_valid) {
				compiled.declaration_valid = false;
			}
		} else {
			compiled.declaration_valid = false;
		}
	} else if (type == StringName("transform_card") && action.size() == 3 + generic_field_count) {
		compiled.opcode = ActionOpcode::TRANSFORM_CARD;
		compiled.card_ref = compile_card_ref(action.get("card", StringName()));
		const Variant card_id_value = action.get("card_id", Variant());
		if (
			card_id_value.get_type() != Variant::STRING_NAME
			&& card_id_value.get_type() != Variant::STRING
		) {
			compiled.declaration_valid = false;
		} else {
			compiled.card_id = StringName(card_id_value);
			if (compiled.card_id.is_empty()) compiled.declaration_valid = false;
		}
	} else if (
		type == StringName("return_card_to_hand")
		&& (
			action.size() == 3 + generic_field_count
			|| action.size() == 4 + generic_field_count
		)
		&& (
			!action.has("preserve_instance")
			|| Variant(action.get("preserve_instance", false)).get_type() == Variant::BOOL
		)
	) {
		compiled.opcode = ActionOpcode::RETURN_CARD_TO_HAND;
		compiled.card_ref = compile_card_ref(action.get("card", StringName()));
		compiled.preserve_instance = static_cast<bool>(action.get("preserve_instance", false));
		const StringName recipient = action.get("recipient", StringName());
		if (recipient == StringName("card_current_owner")) {
			compiled.recipient_owner = RelativeOwnerOpcode::CARD_CURRENT;
		} else if (recipient == StringName("card_original_owner")) {
			compiled.recipient_owner = RelativeOwnerOpcode::CARD_ORIGINAL;
		} else if (recipient == StringName("ability_source")) {
			compiled.recipient_owner = RelativeOwnerOpcode::ABILITY_SOURCE;
		} else if (recipient == StringName("opponent_of_ability_source")) {
			compiled.recipient_owner = RelativeOwnerOpcode::OPPONENT_OF_ABILITY_SOURCE;
		}
	} else if (
		type == StringName("self_swapped_with_ability_source")
		&& action.size() == 1 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::SELF_SWAPPED_WITH_ABILITY_SOURCE;
	} else if (
		type == StringName("swap_self_with_trigger_card")
		&& action.size() == 1 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::SWAP_SELF_WITH_TRIGGER_CARD;
	} else if (
		type == StringName("attack_trigger_card")
		&& action.size() == 1 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::ATTACK_TRIGGER_CARD;
	} else if (
		type == StringName("standard_attack_with_self")
		&& action.size() >= 1 + generic_field_count
		&& action.size() <= 3 + generic_field_count
		&& (
			!action.has("repeat_attack")
			|| Variant(action.get("repeat_attack", false)).get_type() == Variant::BOOL
		)
		&& (
			!action.has("target_policy")
			|| Variant(action.get("target_policy", Variant())).get_type() == Variant::STRING_NAME
			|| Variant(action.get("target_policy", Variant())).get_type() == Variant::STRING
		)
	) {
		compiled.opcode = ActionOpcode::STANDARD_ATTACK_WITH_SELF;
		const Array keys = action.keys();
		for (int64_t key_index = 0; key_index < keys.size(); ++key_index) {
			const StringName key = keys[key_index];
			if (
				key != StringName("type")
				&& key != StringName("repeat_attack")
				&& key != StringName("target_policy")
				&& key != StringName("on_invalid_context")
				&& key != StringName("power_change_batch_group")
			) compiled.declaration_valid = false;
		}
		compiled.repeat_attack = static_cast<bool>(action.get("repeat_attack", false));
		if (action.has("target_policy")) {
			compiled.target_policy_specified = true;
			const StringName policy = action.get("target_policy", StringName());
			if (policy == StringName("enemies_only")) compiled.target_policy = AttackTargetPolicy::ENEMIES_ONLY;
			else if (policy == StringName("allies_only")) compiled.target_policy = AttackTargetPolicy::ALLIES_ONLY;
			else if (policy == StringName("all")) compiled.target_policy = AttackTargetPolicy::ALL;
			else compiled.declaration_valid = false;
		}
	} else if (
		type == StringName("standard_attack_with_card")
		&& action.size() == 2 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::STANDARD_ATTACK_WITH_CARD;
		compiled.card_ref = compile_card_ref(action.get("card", StringName()));
		if (compiled.card_ref == CardRefOpcode::UNSUPPORTED) {
			compiled.declaration_valid = false;
		}
	} else if (
		type == StringName("move_self_to_target")
		&& action.size() == 1 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::MOVE_SELF_TO_TARGET;
	} else if (
		type == StringName("swap_self_with_target")
		&& action.size() == 1 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::SWAP_SELF_WITH_TARGET;
	} else if (
		type == StringName("move_self_to_first_adjacent_empty")
		&& action.size() == 1 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::MOVE_SELF_TO_FIRST_ADJACENT_EMPTY;
	} else if (
		type == StringName("move_self_to_first_empty_between_enemy")
		&& action.size() == 1 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::MOVE_SELF_TO_FIRST_EMPTY_BETWEEN_ENEMY;
	} else if (
		type == StringName("transfer_card_resource")
		&& action.size() == 6 + generic_field_count
		&& Variant(action.get("amount", 0)).get_type() == Variant::INT
		&& static_cast<int64_t>(action.get("amount", 0)) > 0
	) {
		compiled.opcode = ActionOpcode::TRANSFER_CARD_RESOURCE;
		compiled.from_card_ref = compile_card_ref(action.get("from", StringName()));
		compiled.to_card_ref = compile_card_ref(action.get("to", StringName()));
		compiled.amount = static_cast<int32_t>(static_cast<int64_t>(action.get("amount", 0)));
		compiled.resource = compile_resource(action.get("resource", StringName()));
		compiled.fallback_resource = compile_resource(action.get("fallback_resource", StringName()));
		if (
			compiled.from_card_ref == CardRefOpcode::UNSUPPORTED
			|| compiled.to_card_ref == CardRefOpcode::UNSUPPORTED
			|| compiled.resource == ResourceOpcode::NONE
			|| compiled.resource == ResourceOpcode::UNSUPPORTED
			|| compiled.fallback_resource == ResourceOpcode::NONE
			|| compiled.fallback_resource == ResourceOpcode::UNSUPPORTED
			|| compiled.resource == compiled.fallback_resource
		) compiled.declaration_valid = false;
	} else if (
		type == StringName("distribute_ki")
		&& action.size() == 4 + generic_field_count
		&& Variant(action.get("amount", 0)).get_type() == Variant::INT
		&& static_cast<int64_t>(action.get("amount", 0)) > 0
		&& Variant(action.get("selector", Variant())).get_type() == Variant::DICTIONARY
	) {
		compiled.opcode = ActionOpcode::DISTRIBUTE_KI;
		compiled.from_card_ref = compile_card_ref(action.get("from", StringName()));
		compiled.amount = static_cast<int32_t>(static_cast<int64_t>(action.get("amount", 0)));
		compiled.selector = compile_selector(action.get("selector", Dictionary()));
		if (
			compiled.from_card_ref == CardRefOpcode::UNSUPPORTED
			|| !compiled.selector.declaration_valid
		) compiled.declaration_valid = false;
	} else if (
		type == StringName("add_card_to_hand")
		&& action.size() == 3 + generic_field_count
		&& (action.has("card_id") != action.has("card"))
	) {
		compiled.opcode = ActionOpcode::ADD_CARD_TO_HAND;
		const StringName recipient = action.get("recipient", StringName());
		if (recipient == StringName("self")) compiled.recipient = RecipientOpcode::SELF;
		else if (recipient == StringName("opponent")) compiled.recipient = RecipientOpcode::OPPONENT;
		else compiled.declaration_valid = false;
		if (action.has("card_id")) {
			const Variant card_id_value = action.get("card_id", Variant());
			if (
				card_id_value.get_type() != Variant::STRING_NAME
				&& card_id_value.get_type() != Variant::STRING
			) {
				compiled.declaration_valid = false;
			} else {
				compiled.card_id = StringName(card_id_value);
				compiled.card_spec = CardSpecOpcode::FRESH_COPY;
			}
		} else {
			const Variant card_value = action.get("card", Variant());
			if (card_value.get_type() != Variant::DICTIONARY) {
				compiled.declaration_valid = false;
			} else {
				const Dictionary card_spec = card_value;
				const StringName card_spec_type = card_spec.get("type", StringName());
				if (
					(card_spec_type == StringName("fresh_copy") || card_spec_type == StringName("perfect_copy"))
					&& card_spec.size() == 2
				) {
					compiled.card_spec = card_spec_type == StringName("fresh_copy")
						? CardSpecOpcode::FRESH_COPY
						: CardSpecOpcode::PERFECT_COPY;
					compiled.summon_card_ref = compile_card_ref(card_spec.get("of", StringName()));
					if (compiled.summon_card_ref == CardRefOpcode::UNSUPPORTED) {
						compiled.declaration_valid = false;
					}
				} else {
					compiled.declaration_valid = false;
				}
			}
		}
	} else if (
		type == StringName("reveal_hand_cards")
		&& action.size() == 3 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::REVEAL_HAND_CARDS;
		const StringName recipient = action.get("recipient", StringName());
		if (recipient == StringName("self")) compiled.recipient = RecipientOpcode::SELF;
		else if (recipient == StringName("opponent")) compiled.recipient = RecipientOpcode::OPPONENT;
		const StringName filter = action.get("filter", StringName());
		if (filter == StringName("all")) compiled.reveal_filter = RevealFilterOpcode::ALL;
		else if (filter == StringName("remembered")) compiled.reveal_filter = RevealFilterOpcode::REMEMBERED;
		if (
			compiled.recipient == RecipientOpcode::UNSUPPORTED
			|| compiled.reveal_filter == RevealFilterOpcode::UNSUPPORTED
		) compiled.declaration_valid = false;
	} else if (
		type == StringName("reveal_card")
		&& action.size() == 3 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::REVEAL_CARD;
		compiled.card_ref = compile_card_ref(action.get("card", StringName()));
		compiled.recipient_owner = compile_relative_owner(
			action.get("observer", StringName())
		);
		if (
			compiled.card_ref == CardRefOpcode::UNSUPPORTED
			|| compiled.recipient_owner == RelativeOwnerOpcode::UNSUPPORTED
		) compiled.declaration_valid = false;
	} else if (
		type == StringName("grant_extra_card_play")
		&& (action.size() == 2 + generic_field_count || action.size() == 3 + generic_field_count)
		&& Variant(action.get("amount", 0)).get_type() == Variant::INT
		&& static_cast<int64_t>(action.get("amount", 0)) > 0
	) {
		compiled.opcode = ActionOpcode::GRANT_EXTRA_CARD_PLAY;
		compiled.amount = static_cast<int32_t>(static_cast<int64_t>(action.get("amount", 0)));
		compiled.card_ref_explicit = action.has("card");
		if (compiled.card_ref_explicit) {
			compiled.card_ref = compile_card_ref(action.get("card", StringName()));
			if (compiled.card_ref == CardRefOpcode::UNSUPPORTED) compiled.declaration_valid = false;
		}
	} else if (
		type == StringName("add_pending_non_retained_suppression")
		&& action.size() == 3 + generic_field_count
		&& Variant(action.get("amount", 0)).get_type() == Variant::INT
		&& static_cast<int64_t>(action.get("amount", 0)) > 0
	) {
		compiled.opcode = ActionOpcode::ADD_PENDING_NON_RETAINED_SUPPRESSION;
		compiled.amount = static_cast<int32_t>(static_cast<int64_t>(action.get("amount", 0)));
		const StringName recipient = action.get("recipient", StringName());
		if (recipient == StringName("self")) compiled.recipient = RecipientOpcode::SELF;
		else if (recipient == StringName("opponent")) compiled.recipient = RecipientOpcode::OPPONENT;
		else compiled.declaration_valid = false;
	} else if (
		type == StringName("temporarily_remove_non_retained_abilities")
		&& action.size() == 1 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES;
	} else if (
		type == StringName("enable_future_draw_reveal")
		&& action.size() == 2 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::ENABLE_FUTURE_DRAW_REVEAL;
		const StringName recipient = action.get("recipient", StringName());
		if (recipient == StringName("self")) compiled.recipient = RecipientOpcode::SELF;
		else if (recipient == StringName("opponent")) compiled.recipient = RecipientOpcode::OPPONENT;
		else compiled.declaration_valid = false;
	} else if (
		type == StringName("summon_card")
		&& action.size() == 3 + generic_field_count
		&& Variant(action.get("cell", Variant())).get_type() == Variant::DICTIONARY
	) {
		compiled.opcode = ActionOpcode::SUMMON_CARD;
		const Variant card_value = action.get("card", Variant());
		if (card_value.get_type() == Variant::STRING_NAME || card_value.get_type() == Variant::STRING) {
			compiled.card_spec = CardSpecOpcode::EXISTING_REFERENCE;
			compiled.summon_card_ref = compile_card_ref(StringName(card_value));
			if (compiled.summon_card_ref == CardRefOpcode::UNSUPPORTED) compiled.declaration_valid = false;
		} else if (card_value.get_type() == Variant::DICTIONARY) {
			const Dictionary card_spec = card_value;
			const StringName card_spec_type = card_spec.get("type", StringName());
			if (
				(card_spec_type == StringName("fresh_copy") || card_spec_type == StringName("perfect_copy"))
				&& card_spec.size() == 2
			) {
				compiled.card_spec = card_spec_type == StringName("fresh_copy")
					? CardSpecOpcode::FRESH_COPY
					: CardSpecOpcode::PERFECT_COPY;
				compiled.summon_card_ref = compile_card_ref(card_spec.get("of", StringName()));
				if (compiled.summon_card_ref == CardRefOpcode::UNSUPPORTED) compiled.declaration_valid = false;
			} else if (card_spec_type == StringName("top_discard") && card_spec.size() == 2) {
				compiled.card_spec = CardSpecOpcode::TOP_DISCARD;
				compiled.summon_owner = compile_relative_owner(card_spec.get("owner", StringName()));
				if (compiled.summon_owner == RelativeOwnerOpcode::UNSUPPORTED) compiled.declaration_valid = false;
			} else {
				compiled.declaration_valid = false;
			}
		} else {
			compiled.declaration_valid = false;
		}

		const Dictionary cell_spec = action.get("cell", Dictionary());
		const StringName cell_type = cell_spec.get("type", StringName());
		if (cell_type == StringName("initial_card_cell") && cell_spec.size() == 2) {
			compiled.cell_spec = CellSpecOpcode::INITIAL_CARD_CELL;
			compiled.summon_cell_card_ref = compile_card_ref(cell_spec.get("card", StringName()));
		} else if (cell_type == StringName("activation_target") && cell_spec.size() == 1) {
			compiled.cell_spec = CellSpecOpcode::ACTIVATION_TARGET;
		} else if (cell_type == StringName("first_adjacent_empty") && cell_spec.size() == 2) {
			compiled.cell_spec = CellSpecOpcode::FIRST_ADJACENT_EMPTY;
			compiled.summon_cell_card_ref = compile_card_ref(cell_spec.get("card", StringName()));
		} else if (cell_type == StringName("first_adjacent_or_any_empty") && cell_spec.size() == 2) {
			compiled.cell_spec = CellSpecOpcode::FIRST_ADJACENT_OR_ANY_EMPTY;
			compiled.summon_cell_card_ref = compile_card_ref(cell_spec.get("card", StringName()));
		} else if (cell_type == StringName("first_empty_adjacent_to_enemy") && cell_spec.size() == 2) {
			compiled.cell_spec = CellSpecOpcode::FIRST_EMPTY_ADJACENT_TO_ENEMY;
			compiled.summon_owner = compile_relative_owner(cell_spec.get("owner", StringName()));
		} else {
			compiled.declaration_valid = false;
		}
		if (
			(compiled.cell_spec == CellSpecOpcode::INITIAL_CARD_CELL
				|| compiled.cell_spec == CellSpecOpcode::FIRST_ADJACENT_EMPTY
				|| compiled.cell_spec == CellSpecOpcode::FIRST_ADJACENT_OR_ANY_EMPTY)
			&& compiled.summon_cell_card_ref == CardRefOpcode::UNSUPPORTED
		) compiled.declaration_valid = false;
		if (
			compiled.cell_spec == CellSpecOpcode::FIRST_EMPTY_ADJACENT_TO_ENEMY
			&& compiled.summon_owner == RelativeOwnerOpcode::UNSUPPORTED
		) compiled.declaration_valid = false;
	} else if (
		type == StringName("resummon_card_in_place")
		&& action.size() == 2 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::RESUMMON_CARD_IN_PLACE;
		compiled.card_ref = compile_card_ref(action.get("card", StringName()));
		if (compiled.card_ref == CardRefOpcode::UNSUPPORTED) compiled.declaration_valid = false;
	} else if (
		type == StringName("depart_card_for_resummon")
		&& action.size() == 2 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::DEPART_CARD_FOR_RESUMMON;
		compiled.card_ref = compile_card_ref(action.get("card", StringName()));
		if (compiled.card_ref == CardRefOpcode::UNSUPPORTED) compiled.declaration_valid = false;
	}
	if (compiled.opcode == ActionOpcode::UNSUPPORTED) compiled.declaration_valid = false;
	return compiled;
}

DuelNativeCompactKernel::CompiledModifier DuelNativeCompactKernel::compile_modifier(
	const Variant &value
) const {
	CompiledModifier compiled;
	if (value.get_type() != Variant::DICTIONARY) return compiled;
	const Dictionary modifier = value;
	const StringName type = modifier.get("type", StringName());
	if (
		type == StringName("defending_power_override")
		&& modifier.size() == 2
		&& Variant(modifier.get("value", 0)).get_type() == Variant::INT
	) {
		compiled.opcode = ModifierOpcode::DEFENDING_POWER_OVERRIDE;
		compiled.value = static_cast<int32_t>(static_cast<int64_t>(modifier.get("value", 0)));
	} else if (
		type == StringName("orthogonal_attack_range_two")
		&& (modifier.size() == 2 || modifier.size() == 3)
		&& Variant(modifier.get("allow_intervening_ally", false)).get_type() == Variant::BOOL
		&& (
			!modifier.has("allow_intervening_enemy")
			|| Variant(modifier.get("allow_intervening_enemy", false)).get_type() == Variant::BOOL
		)
	) {
		compiled.opcode = ModifierOpcode::ORTHOGONAL_ATTACK_RANGE_TWO;
		compiled.value = (
			(static_cast<bool>(modifier.get("allow_intervening_ally", false)) ? 1 : 0)
			| (static_cast<bool>(modifier.get("allow_intervening_enemy", false)) ? 2 : 0)
		);
	} else if (type == StringName("enemy_attacks_all") && modifier.size() == 1) {
		compiled.opcode = ModifierOpcode::ENEMY_ATTACKS_ALL;
	} else if (modifier.size() == 1) {
		if (type == StringName("attack_requires_other_ally")) compiled.opcode = ModifierOpcode::ATTACK_REQUIRES_OTHER_ALLY;
		else if (type == StringName("defending_power_uses_minimum_side")) compiled.opcode = ModifierOpcode::DEFENDING_POWER_USES_MINIMUM_SIDE;
		else if (type == StringName("power_comparison_reversed")) compiled.opcode = ModifierOpcode::POWER_COMPARISON_REVERSED;
		else if (type == StringName("adjacent_enemy_summon_attacks_allies")) compiled.opcode = ModifierOpcode::ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES;
		else if (type == StringName("unlimited_attack_range")) compiled.opcode = ModifierOpcode::UNLIMITED_ATTACK_RANGE;
		else if (type == StringName("non_orthogonal_attack_any_axis")) compiled.opcode = ModifierOpcode::NON_ORTHOGONAL_ATTACK_ANY_AXIS;
		else if (type == StringName("standard_attack_first_legal_target")) compiled.opcode = ModifierOpcode::STANDARD_ATTACK_FIRST_LEGAL_TARGET;
		else if (type == StringName("enemy_cannot_attack_during_owner_turn")) compiled.opcode = ModifierOpcode::ENEMY_CANNOT_ATTACK_DURING_OWNER_TURN;
		else if (type == StringName("self_attacks_all")) compiled.opcode = ModifierOpcode::SELF_ATTACKS_ALL;
	}
	return compiled;
}

DuelNativeCompactKernel::CompiledTriggerRule DuelNativeCompactKernel::compile_trigger_rule(
	const Variant &value,
	bool &valid
) {
	CompiledTriggerRule compiled;
	if (value.get_type() != Variant::DICTIONARY) {
		valid = false;
		return compiled;
	}
	const Dictionary rule = value;
	compiled.event_id = rule.get("event", StringName());
	const Variant conditions_value = rule.get("conditions", Array());
	const Variant actions_value = rule.get("actions", Array());
	if (conditions_value.get_type() != Variant::ARRAY || actions_value.get_type() != Variant::ARRAY) {
		valid = false;
		return compiled;
	}
	const Array conditions = conditions_value;
	for (int64_t index = 0; index < conditions.size(); ++index) {
		const CompiledCondition condition = compile_condition(conditions[index]);
		if (condition.opcode == ConditionOpcode::UNSUPPORTED) valid = false;
		compiled.conditions.push_back(condition);
	}
	const Array actions = actions_value;
	for (int64_t index = 0; index < actions.size(); ++index) {
		const CompiledAction action = compile_action(actions[index]);
		if (!action.declaration_valid) valid = false;
		compiled.actions.push_back(action);
	}
	return compiled;
}

DuelNativeCompactKernel::CompiledActivation DuelNativeCompactKernel::compile_activation(
	const Variant &value
) {
	CompiledActivation compiled;
	if (value.get_type() != Variant::DICTIONARY) {
		compiled.declaration_valid = false;
		return compiled;
	}
	const Dictionary activation = value;
	if (activation.size() != 4) compiled.declaration_valid = false;
	const Array keys = activation.keys();
	for (int64_t index = 0; index < keys.size(); ++index) {
		const StringName key = keys[index];
		if (
			key != StringName("input")
			&& key != StringName("target_rule")
			&& key != StringName("costs")
			&& key != StringName("actions")
		) {
			compiled.declaration_valid = false;
		}
	}
	if (StringName(activation.get("input", StringName())) != StringName("drag_to_target")) {
		compiled.declaration_valid = false;
	}
	const StringName target_rule = activation.get("target_rule", StringName());
	if (target_rule == StringName("adjacent_empty_board")) {
		compiled.target_rule = TargetRuleOpcode::ADJACENT_EMPTY_BOARD;
	} else if (target_rule == StringName("adjacent_ally_board")) {
		compiled.target_rule = TargetRuleOpcode::ADJACENT_ALLY_BOARD;
	} else if (target_rule == StringName("adjacent_enemy_board")) {
		compiled.target_rule = TargetRuleOpcode::ADJACENT_ENEMY_BOARD;
	} else if (target_rule == StringName("other_ally_board")) {
		compiled.target_rule = TargetRuleOpcode::OTHER_ALLY_BOARD;
	} else if (target_rule == StringName("enemy_hand_card")) {
		compiled.target_rule = TargetRuleOpcode::ENEMY_HAND_CARD;
	} else if (target_rule == StringName("ally_hand_card")) {
		compiled.target_rule = TargetRuleOpcode::ALLY_HAND_CARD;
	} else if (target_rule == StringName("any_empty_board")) {
		compiled.target_rule = TargetRuleOpcode::ANY_EMPTY_BOARD;
	} else if (target_rule == StringName("any_enemy_board")) {
		compiled.target_rule = TargetRuleOpcode::ANY_ENEMY_BOARD;
	} else {
		compiled.declaration_valid = false;
	}

	const Variant costs_value = activation.get("costs", Variant());
	const Variant actions_value = activation.get("actions", Variant());
	if (costs_value.get_type() != Variant::ARRAY || actions_value.get_type() != Variant::ARRAY) {
		compiled.declaration_valid = false;
		return compiled;
	}
	const Array costs = costs_value;
	const Array actions = actions_value;
	if (costs.is_empty() || actions.is_empty()) compiled.declaration_valid = false;
	compiled.costs.reserve(static_cast<size_t>(costs.size()));
	for (int64_t index = 0; index < costs.size(); ++index) {
		const CompiledAction cost = compile_action(costs[index]);
		if (
			!cost.declaration_valid
			|| cost.opcode != ActionOpcode::SPEND_KI
			|| cost.amount <= 0
			|| cost.card_ref_explicit
		) {
			compiled.declaration_valid = false;
		} else {
			compiled.required_ki += cost.amount;
		}
		compiled.costs.push_back(cost);
	}
	compiled.actions.reserve(static_cast<size_t>(actions.size()));
	for (int64_t index = 0; index < actions.size(); ++index) {
		const CompiledAction action = compile_action(actions[index]);
		if (!action.declaration_valid) compiled.declaration_valid = false;
		compiled.actions.push_back(action);
	}
	return compiled;
}

DuelNativeCompactKernel::CompiledAbility DuelNativeCompactKernel::compile_ability(
	const Variant &value
) {
	CompiledAbility compiled;
	if (value.get_type() != Variant::DICTIONARY) {
		compiled.declaration_valid = false;
		return compiled;
	}
	const Dictionary ability = value;
	compiled.retained_on_flip = static_cast<bool>(ability.get("retained_on_flip", false));
	if (ability.has("activation")) {
		const Variant activation = ability["activation"];
		compiled.has_activation = (
			activation.get_type() == Variant::DICTIONARY
			&& !Dictionary(activation).is_empty()
		);
		compiled.activation = compile_activation(activation);
		if (!compiled.activation.declaration_valid) compiled.declaration_valid = false;
	}
	if (ability.has("modifiers")) {
		const Variant modifiers_value = ability["modifiers"];
		if (modifiers_value.get_type() != Variant::ARRAY) {
			compiled.declaration_valid = false;
		} else {
			const Array modifiers = modifiers_value;
			for (int64_t index = 0; index < modifiers.size(); ++index) {
				const CompiledModifier modifier = compile_modifier(modifiers[index]);
				if (modifier.opcode == ModifierOpcode::UNSUPPORTED) {
					compiled.declaration_valid = false;
				}
				compiled.modifiers.push_back(modifier);
			}
		}
	}
	const Variant triggers_value = ability.get("triggers", Array());
	if (triggers_value.get_type() != Variant::ARRAY) {
		compiled.declaration_valid = false;
		return compiled;
	}
	const Array triggers = triggers_value;
	for (int64_t index = 0; index < triggers.size(); ++index) {
		compiled.triggers.push_back(compile_trigger_rule(triggers[index], compiled.declaration_valid));
	}
	compiled.isolated_self_after_flip = (
		!compiled.has_activation
		&& compiled.modifiers.empty()
		&& compiled.triggers.size() == 1
		&& compiled.triggers[0].event_id == StringName("card_after_flipped")
	);
	if (compiled.isolated_self_after_flip) {
		bool has_self_condition = false;
		for (const CompiledCondition &condition : compiled.triggers[0].conditions) {
			has_self_condition = has_self_condition || condition.opcode == ConditionOpcode::TRIGGER_CARD_IS_SELF;
		}
		compiled.isolated_self_after_flip = has_self_condition;
	}
	return compiled;
}

int32_t DuelNativeCompactKernel::intern_compiled_ability(const Variant &value) {
	for (size_t index = 0; index < ability_declaration_pool.size(); ++index) {
		if (ability_declaration_pool[index] == value) return static_cast<int32_t>(index);
	}
	const int32_t index = static_cast<int32_t>(compiled_ability_pool.size());
	ability_declaration_pool.push_back(value);
	compiled_ability_pool.push_back(CompiledAbility());
	compiled_ability_pool[index] = compile_ability(value);
	return index;
}

void DuelNativeCompactKernel::compile_ability_sets() {
	compiled_ability_sets.clear();
	compiled_ability_pool.clear();
	ability_declaration_pool.clear();
	compiled_ability_sets.reserve(static_cast<size_t>(state.active_ability_set_pool.size()));
	for (int64_t set_index = 0; set_index < state.active_ability_set_pool.size(); ++set_index) {
		CompiledAbilitySet compiled;
		const Variant set_value = state.active_ability_set_pool[set_index];
		if (set_value.get_type() != Variant::ARRAY) {
			compiled.declaration_valid = false;
			compiled_ability_sets.push_back(compiled);
			continue;
		}
		const Array abilities = set_value;
		for (int64_t ability_index = 0; ability_index < abilities.size(); ++ability_index) {
			const int32_t pool_index = intern_compiled_ability(abilities[ability_index]);
			compiled.ability_pool_indices.push_back(pool_index);
			if (!compiled_ability_pool[pool_index].declaration_valid) compiled.declaration_valid = false;
		}
		compiled_ability_sets.push_back(compiled);
	}
}

bool DuelNativeCompactKernel::compile_runtime_suppression_batches() {
	state.card_runtime_suppression_batches.clear();
	state.card_runtime_suppression_batches.resize(state.card_instance_ids.size());
	for (size_t card_index = 0; card_index < state.card_instance_ids.size(); ++card_index) {
		if ((state.card_runtime_flags[card_index] & (1 << 6)) == 0) continue;
		const int32_t set_index = state.card_suppression_set_indices[card_index];
		if (
			set_index < 0
			|| set_index >= state.suppression_set_pool.size()
			|| Variant(state.suppression_set_pool[set_index]).get_type() != Variant::ARRAY
		) {
			last_error = "Temporary suppression set reference is invalid";
			return false;
		}
		const Array batches = state.suppression_set_pool[set_index];
		std::vector<RuntimeSuppressionBatch> compiled_batches;
		compiled_batches.reserve(static_cast<size_t>(batches.size()));
		for (int64_t batch_index = 0; batch_index < batches.size(); ++batch_index) {
			const Variant batch_value = batches[batch_index];
			if (batch_value.get_type() != Variant::DICTIONARY) {
				last_error = "Temporary suppression batch is not a Dictionary";
				return false;
			}
			const Dictionary batch = batch_value;
			const Variant expires_value = batch.get("expires_after_turn", Variant());
			const Variant entries_value = batch.get("entries", Variant());
			if (
				batch.size() != 2
				|| expires_value.get_type() != Variant::INT
				|| entries_value.get_type() != Variant::ARRAY
			) {
				last_error = "Temporary suppression batch has an invalid declaration shape";
				return false;
			}
			RuntimeSuppressionBatch compiled_batch;
			compiled_batch.expires_after_turn = static_cast<int32_t>(
				static_cast<int64_t>(expires_value)
			);
			const Array entries = entries_value;
			compiled_batch.entries.reserve(static_cast<size_t>(entries.size()));
			for (int64_t entry_index = 0; entry_index < entries.size(); ++entry_index) {
				const Variant entry_value = entries[entry_index];
				if (entry_value.get_type() != Variant::DICTIONARY) {
					last_error = "Temporary suppression entry is not a Dictionary";
					return false;
				}
				const Dictionary entry = entry_value;
				const Variant index_value = entry.get("index", Variant());
				const Variant ability_value = entry.get("ability", Variant());
				if (
					entry.size() != 2
					|| index_value.get_type() != Variant::INT
					|| static_cast<int64_t>(index_value) < 0
					|| ability_value.get_type() != Variant::DICTIONARY
				) {
					last_error = "Temporary suppression entry has an invalid declaration shape";
					return false;
				}
				RuntimeSuppressionEntry compiled_entry;
				compiled_entry.original_index = static_cast<int32_t>(
					static_cast<int64_t>(index_value)
				);
				compiled_entry.compiled_ability_index = intern_compiled_ability(ability_value);
				compiled_entry.handle = state.next_ability_handle++;
				compiled_batch.entries.push_back(compiled_entry);
			}
			compiled_batches.push_back(compiled_batch);
		}
		state.card_runtime_suppression_batches[card_index] = compiled_batches;
	}
	return true;
}

bool DuelNativeCompactKernel::validate_play_support(
	const NativeState &value,
	String &reason
) const {
	if (!value.has_rule_metadata) {
		reason = "Play transition requires immutable compact metadata pools";
		return false;
	}
	if (value.board_card_indices.size() != 9 || value.board_slot_extras.size() != 9) {
		reason = "Play transition requires the canonical nine-cell board";
		return false;
	}
	const Array state_abilities = value.side_payload.get("active_abilities", Array());
	const Array effect_queue = value.side_payload.get("effect_queue", Array());
	const Dictionary pending_choice = value.side_payload.get("pending_choice", Dictionary());
	if (!state_abilities.is_empty() || !effect_queue.is_empty() || !pending_choice.is_empty()) {
		reason = "Play transition requires no state abilities, queued effects, or pending choice";
		return false;
	}
	if (value.card_ids.size() != value.card_instance_ids.size()) {
		reason = "Play transition is missing card IDs";
		return false;
	}
	for (size_t card_index = 0; card_index < value.card_instance_ids.size(); ++card_index) {
		static constexpr uint8_t required_flags = (
			(1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5)
		);
		if ((value.card_runtime_flags[card_index] & required_flags) != required_flags) {
			reason = "Play transition requires normalized runtime cards";
			return false;
		}
		if (value.card_ids[card_index].is_empty()) {
			reason = "Play transition requires every card to have a card ID";
			return false;
		}
		if (!powers_supported(value, static_cast<int32_t>(card_index))) {
			reason = "Play transition does not cover mixed negative powers";
			return false;
		}
		const int32_t ability_set_index = value.card_active_ability_set_indices[card_index];
		if (
			ability_set_index < 0
			|| ability_set_index >= value.active_ability_set_pool.size()
			|| Variant(value.active_ability_set_pool[ability_set_index]).get_type() != Variant::ARRAY
			|| ability_set_index >= static_cast<int32_t>(compiled_ability_sets.size())
		) {
			reason = "Play transition has an invalid runtime ability-set reference";
			return false;
		}
	}
	return true;
}

bool DuelNativeCompactKernel::validate_action_rule_support(
	const NativeState &value,
	int32_t played_card_index,
	int32_t,
	String &reason
) const {
	const int32_t moving_owner = value.scalars[0];
	const bool source_enabled = card_effects_enabled(value, played_card_index, moving_owner);
	if (source_enabled && card_has_unsupported_enabled_modifier(value, played_card_index, moving_owner)) {
		reason = "Played card has an unsupported modifier";
		return false;
	}
	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		const int32_t card_index = value.board_card_indices[cell];
		if (card_index < 0) {
			continue;
		}
		const int32_t owner_id = value.board_owners[cell];
		if (card_has_unsupported_enabled_modifier(value, card_index, owner_id)) {
			reason = "Board contains an unsupported active modifier";
			return false;
		}
	}
	return true;
}

bool DuelNativeCompactKernel::card_effects_enabled(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id
) const {
	if (card_index < 0 || card_index >= static_cast<int32_t>(value.card_template_indices.size())) {
		return false;
	}
	const int32_t template_index = value.card_template_indices[card_index];
	if (template_index < 0 || template_index >= value.card_template_pool.size()) {
		return false;
	}
	const Dictionary card_template = value.card_template_pool[template_index];
	const StringName gate = card_template.get("effect_gate", StringName());
	if (gate.is_empty()) {
		return true;
	}
	const Dictionary gates_by_owner = value.side_payload.get(
		"enabled_effect_gates_by_owner",
		Dictionary()
	);
	const Variant gates_value = gates_by_owner.get(owner_id, Array());
	if (gates_value.get_type() != Variant::ARRAY) {
		return false;
	}
	const Array gates = gates_value;
	for (int64_t index = 0; index < gates.size(); ++index) {
		if (StringName(gates[index]) == gate) {
			return true;
		}
	}
	return false;
}

bool DuelNativeCompactKernel::card_has_abilities(
	const NativeState &value,
	int32_t card_index
) const {
	return (
		card_index >= 0
		&& card_index < static_cast<int32_t>(value.card_runtime_abilities.size())
		&& !value.card_runtime_abilities[card_index].empty()
	);
}

bool DuelNativeCompactKernel::ability_enabled(
	const NativeState &value,
	int32_t card_index,
	int32_t ability_index
) const {
	return runtime_ability(value, card_index, ability_index) != nullptr;
}

const DuelNativeCompactKernel::CompiledAbility *DuelNativeCompactKernel::runtime_ability(
	const NativeState &value,
	int32_t card_index,
	int32_t ability_index
) const {
	if (
		card_index < 0
		|| card_index >= static_cast<int32_t>(value.card_runtime_abilities.size())
		|| ability_index < 0
		|| ability_index >= static_cast<int32_t>(value.card_runtime_abilities[card_index].size())
	) {
		return nullptr;
	}
	const int32_t compiled_index = value.card_runtime_abilities[card_index][ability_index].compiled_ability_index;
	if (compiled_index < 0 || compiled_index >= static_cast<int32_t>(compiled_ability_pool.size())) {
		return nullptr;
	}
	return &compiled_ability_pool[compiled_index];
}


} // namespace godot
