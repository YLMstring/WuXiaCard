class_name DuelAbilities
extends RefCounted

const Catalog = preload("res://scripts/card_catalog.gd")

const KI_BEAD_NONE: StringName = &"none"
const KI_BEAD_DARK: StringName = &"dark"
const KI_BEAD_LIGHT: StringName = &"light"
const KI_BEAD_GRAY: StringName = &"gray"
const KI_BEAD_GOLD: StringName = &"gold"
const KI_BEAD_MARKER_GUARD: String = "护"
const KI_BEAD_MARKER_CIRCLE: String = "圈"
const KI_BEAD_MARKER_CHAIN: String = "连"
const KI_BEAD_MARKER_ATTACK: String = "攻"
const KI_BEAD_MARKER_RETURN: String = "回"
const KI_BEAD_MARKER_BREAK: String = "破"
const KI_BEAD_MARKER_YANG: String = "阳"
const KI_BEAD_MARKER_YIN: String = "阴"
const KI_BEAD_MARKER_SPECIAL: String = "奇"
const KI_BEAD_MARKER_DEFEND: String = "守"
const KI_BEAD_MARKER_VOID: String = "虚"
const KI_BEAD_MARKER_DEFAULT: String = "化"

const ATTACK_ACTION_TYPES: Array[StringName] = [
	Catalog.ACTION_ATTACK_TRIGGER_CARD,
	Catalog.ACTION_STANDARD_ATTACK_WITH_SELF,
]
const SPECIAL_ATTACK_RANGE_MODIFIERS: Array[StringName] = [
	Catalog.MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO,
	Catalog.MODIFIER_UNLIMITED_ATTACK_RANGE,
	Catalog.MODIFIER_NON_ORTHOGONAL_ATTACK_ANY_AXIS,
]


static func is_activate_ability(ability: Dictionary) -> bool:
	var activation_value: Variant = ability.get("activation", null)
	return activation_value is Dictionary and not (activation_value as Dictionary).is_empty()


static func card_effects_enabled(
	card: Dictionary,
	enabled_effect_gates: Variant = null
) -> bool:
	var gate := StringName(card.get("effect_gate", &""))
	if gate == &"" or enabled_effect_gates == null:
		return true
	return enabled_effect_gates is Array and gate in (enabled_effect_gates as Array)


static func get_activate_abilities(
	card: Dictionary,
	enabled_effect_gates: Variant = null
) -> Array[Dictionary]:
	var activate_abilities: Array[Dictionary] = []
	if not card_effects_enabled(card, enabled_effect_gates):
		return activate_abilities
	var active_abilities: Array = card.get("active_abilities", [])
	for ability_value: Variant in active_abilities:
		if not ability_value is Dictionary:
			continue
		var ability: Dictionary = ability_value
		if is_activate_ability(ability):
			activate_abilities.append(ability)
	return activate_abilities


static func get_activate_ability_at(
	card: Dictionary,
	activation_index: int,
	enabled_effect_gates: Variant = null
) -> Dictionary:
	var activate_abilities: Array[Dictionary] = get_activate_abilities(card, enabled_effect_gates)
	if activation_index < 0 or activation_index >= activate_abilities.size():
		return {}
	return activate_abilities[activation_index]


static func get_activation(
	card: Dictionary,
	activation_index: int = 0,
	enabled_effect_gates: Variant = null
) -> Dictionary:
	var ability: Dictionary = get_activate_ability_at(card, activation_index, enabled_effect_gates)
	if ability.is_empty():
		return {}
	return ability.get("activation", {}) as Dictionary


static func card_uses_ki(card: Dictionary) -> bool:
	return not get_activate_abilities(card).is_empty()


static func card_can_spend_ki(
	card: Dictionary,
	enabled_effect_gates: Variant = null
) -> bool:
	if not card_effects_enabled(card, enabled_effect_gates):
		return false
	for ability_value: Variant in card.get("active_abilities", []):
		if not ability_value is Dictionary:
			continue
		var ability: Dictionary = ability_value
		var activation_value: Variant = ability.get("activation", null)
		if activation_value is Dictionary:
			var activation: Dictionary = activation_value
			if (
				_actions_can_spend_ki(activation.get("costs", []))
				or _actions_can_spend_ki(activation.get("actions", []))
			):
				return true
		for trigger_value: Variant in ability.get("triggers", []):
			if (
				trigger_value is Dictionary
				and _actions_can_spend_ki(
					(trigger_value as Dictionary).get("actions", [])
				)
			):
				return true
	return false


static func _actions_can_spend_ki(actions_value: Variant) -> bool:
	if not actions_value is Array:
		return false
	for action_value: Variant in actions_value as Array:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		var action_type := StringName(action.get("type", &""))
		if action_type == Catalog.ACTION_SPEND_KI:
			return true
		if _actions_can_spend_ki(action.get("actions", null)):
			return true
	return false


static func get_ki_bead_presentation(card: Dictionary) -> Dictionary:
	var ki: int = maxi(0, int(card.get("ki", 0)))
	var marker: String = get_ki_bead_passive_marker(card)
	if bool(card.get("suppress_ki_bead", false)):
		return {
			"kind": KI_BEAD_NONE,
			"show_number": false,
			"value": ki,
			"marker": marker,
		}
	var has_activation: bool = card_uses_ki(card)
	var has_ki_threshold: bool = has_ki_threshold_trigger(card)
	var has_taiji_common: bool = has_taiji_common_modifier(card)
	var has_special_range: bool = has_special_attack_range(card)
	var kind: StringName = KI_BEAD_NONE
	if has_flip_prevention(card):
		kind = KI_BEAD_GOLD
	elif has_source_exile(card):
		kind = KI_BEAD_GRAY
	elif (
		has_activation
		or has_bead_trigger_ability(card)
		or has_taiji_common
		or has_special_range
	):
		kind = KI_BEAD_LIGHT
	elif ki > 0:
		kind = KI_BEAD_DARK
	return {
		"kind": kind,
		"show_number": (
			kind != KI_BEAD_NONE
			and (ki > 0 or has_activation or has_ki_threshold)
		),
		"value": ki,
		"marker": marker,
	}


static func get_ki_bead_passive_marker(card: Dictionary) -> String:
	# 文字优先级独立于珠子颜色：例如反击兼防翻面的牌仍显示金珠“护”。
	if has_hengshan_counterattack(card):
		return KI_BEAD_MARKER_GUARD
	if has_taiji_common_modifier(card):
		return KI_BEAD_MARKER_CIRCLE
	if has_chain_attack(card):
		return KI_BEAD_MARKER_CHAIN
	if _card_actions_have_any_type(card, ATTACK_ACTION_TYPES):
		return KI_BEAD_MARKER_ATTACK
	if _card_actions_have_type(card, Catalog.ACTION_RETURN_CARD_TO_HAND):
		return KI_BEAD_MARKER_RETURN
	if has_other_card_exile(card):
		return KI_BEAD_MARKER_BREAK
	if _card_has_power_change_direction(card, 1):
		return KI_BEAD_MARKER_YANG
	if _card_has_power_change_direction(card, -1):
		return KI_BEAD_MARKER_YIN
	if has_special_attack_range(card):
		return KI_BEAD_MARKER_SPECIAL
	if has_flip_prevention(card):
		return KI_BEAD_MARKER_DEFEND
	if has_source_exile(card):
		return KI_BEAD_MARKER_VOID
	return KI_BEAD_MARKER_DEFAULT


static func has_hengshan_counterattack(card: Dictionary) -> bool:
	for ability_value: Variant in card.get("active_abilities", []):
		if not ability_value is Dictionary:
			continue
		for trigger_value: Variant in (ability_value as Dictionary).get("triggers", []):
			if (
				trigger_value is Dictionary
				and _list_has_type(
					(trigger_value as Dictionary).get("conditions", []),
					Catalog.CONDITION_ATTACK_FLIPPED_ALLY_IN_RANGE
				)
				and _actions_have_type(
					(trigger_value as Dictionary).get("actions", []),
					Catalog.ACTION_STANDARD_ATTACK_WITH_SELF
				)
			):
				return true
	return false


static func has_taiji_common_modifier(card: Dictionary) -> bool:
	return (
		has_modifier(card, Catalog.MODIFIER_POWER_COMPARISON_REVERSED)
		or has_modifier(card, Catalog.MODIFIER_ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES)
	)


static func has_chain_attack(card: Dictionary) -> bool:
	if _card_actions_have_type(card, Catalog.ACTION_STANDARD_ATTACK_WITH_CARD):
		return true
	for ability_value: Variant in card.get("active_abilities", []):
		if not ability_value is Dictionary:
			continue
		var ability: Dictionary = ability_value
		var activation_value: Variant = ability.get("activation", null)
		if activation_value is Dictionary:
			var activation: Dictionary = activation_value
			if (
				_actions_have_selected_card_self_attack(activation.get("costs", []), false)
				or _actions_have_selected_card_self_attack(
					activation.get("actions", []),
					false
				)
			):
				return true
		for trigger_value: Variant in ability.get("triggers", []):
			if (
				trigger_value is Dictionary
				and _actions_have_selected_card_self_attack(
					(trigger_value as Dictionary).get("actions", []),
					false
				)
			):
				return true
	return false


static func has_special_attack_range(card: Dictionary) -> bool:
	for modifier_type: StringName in SPECIAL_ATTACK_RANGE_MODIFIERS:
		if has_modifier(card, modifier_type):
			return true
	return false


static func has_flip_prevention(card: Dictionary) -> bool:
	for ability_value: Variant in card.get("active_abilities", []):
		if not ability_value is Dictionary:
			continue
		var ability: Dictionary = ability_value
		var activation_value: Variant = ability.get("activation", null)
		if activation_value is Dictionary:
			var activation: Dictionary = activation_value
			if (
				_actions_have_type(activation.get("costs", []), Catalog.ACTION_PREVENT_TRIGGER_FLIP)
				or _actions_have_type(activation.get("actions", []), Catalog.ACTION_PREVENT_TRIGGER_FLIP)
			):
				return true
		for trigger_value: Variant in ability.get("triggers", []):
			if (
				trigger_value is Dictionary
				and _actions_have_type(
					(trigger_value as Dictionary).get("actions", []),
					Catalog.ACTION_PREVENT_TRIGGER_FLIP
				)
			):
				return true
	return false


static func has_source_exile(card: Dictionary) -> bool:
	for ability_value: Variant in card.get("active_abilities", []):
		if not ability_value is Dictionary:
			continue
		var ability: Dictionary = ability_value
		var activation_value: Variant = ability.get("activation", null)
		if activation_value is Dictionary:
			var activation: Dictionary = activation_value
			if (
				_actions_exile_source(activation.get("costs", []), true, false)
				or _actions_exile_source(activation.get("actions", []), true, false)
			):
				return true
		for trigger_value: Variant in ability.get("triggers", []):
			if not trigger_value is Dictionary:
				continue
			var trigger: Dictionary = trigger_value
			var trigger_is_source: bool = _list_has_type(
				trigger.get("conditions", []),
				Catalog.CONDITION_TRIGGER_CARD_IS_SELF
			)
			if _actions_exile_source(
				trigger.get("actions", []),
				true,
				trigger_is_source
			):
				return true
	return false


static func has_other_card_exile(card: Dictionary) -> bool:
	for ability_value: Variant in card.get("active_abilities", []):
		if not ability_value is Dictionary:
			continue
		var ability: Dictionary = ability_value
		var activation_value: Variant = ability.get("activation", null)
		if activation_value is Dictionary:
			var activation: Dictionary = activation_value
			if (
				_actions_exile_other_card(activation.get("costs", []), true, false)
				or _actions_exile_other_card(activation.get("actions", []), true, false)
			):
				return true
		for trigger_value: Variant in ability.get("triggers", []):
			if not trigger_value is Dictionary:
				continue
			var trigger: Dictionary = trigger_value
			var trigger_is_source: bool = _list_has_type(
				trigger.get("conditions", []),
				Catalog.CONDITION_TRIGGER_CARD_IS_SELF
			)
			if _actions_exile_other_card(
				trigger.get("actions", []),
				true,
				trigger_is_source
			):
				return true
	return false


static func _actions_have_type(actions_value: Variant, expected_type: StringName) -> bool:
	if not actions_value is Array:
		return false
	for action_value: Variant in actions_value as Array:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		if StringName(action.get("type", &"")) == expected_type:
			return true
		if _actions_have_type(action.get("actions", null), expected_type):
			return true
	return false


static func _card_actions_have_type(card: Dictionary, expected_type: StringName) -> bool:
	return _card_actions_have_any_type(card, [expected_type])


static func _card_actions_have_any_type(card: Dictionary, expected_types: Array) -> bool:
	for ability_value: Variant in card.get("active_abilities", []):
		if not ability_value is Dictionary:
			continue
		var ability: Dictionary = ability_value
		var activation_value: Variant = ability.get("activation", null)
		if activation_value is Dictionary:
			var activation: Dictionary = activation_value
			if (
				_actions_have_any_type(activation.get("costs", []), expected_types)
				or _actions_have_any_type(activation.get("actions", []), expected_types)
			):
				return true
		for trigger_value: Variant in ability.get("triggers", []):
			if (
				trigger_value is Dictionary
				and _actions_have_any_type(
					(trigger_value as Dictionary).get("actions", []),
					expected_types
				)
			):
				return true
	return false


static func _actions_have_any_type(actions_value: Variant, expected_types: Array) -> bool:
	if not actions_value is Array:
		return false
	for action_value: Variant in actions_value as Array:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		if StringName(action.get("type", &"")) in expected_types:
			return true
		if _actions_have_any_type(action.get("actions", null), expected_types):
			return true
	return false


static func _actions_have_selected_card_self_attack(
	actions_value: Variant,
	inside_selected_card_iteration: bool
) -> bool:
	if not actions_value is Array:
		return false
	for action_value: Variant in actions_value as Array:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		var action_type := StringName(action.get("type", &""))
		if (
			inside_selected_card_iteration
			and action_type == Catalog.ACTION_STANDARD_ATTACK_WITH_SELF
		):
			return true
		var nested_inside_iteration: bool = (
			inside_selected_card_iteration
			or action_type == Catalog.ACTION_FOR_EACH_SELECTED_CARD
		)
		if _actions_have_selected_card_self_attack(
			action.get("actions", null),
			nested_inside_iteration
		):
			return true
	return false


static func _card_has_power_change_direction(card: Dictionary, direction: int) -> bool:
	for ability_value: Variant in card.get("active_abilities", []):
		if not ability_value is Dictionary:
			continue
		var ability: Dictionary = ability_value
		var activation_value: Variant = ability.get("activation", null)
		if activation_value is Dictionary:
			var activation: Dictionary = activation_value
			if (
				_actions_have_power_change_direction(activation.get("costs", []), direction)
				or _actions_have_power_change_direction(
					activation.get("actions", []),
					direction
				)
			):
				return true
		for trigger_value: Variant in ability.get("triggers", []):
			if (
				trigger_value is Dictionary
				and _actions_have_power_change_direction(
					(trigger_value as Dictionary).get("actions", []),
					direction
				)
			):
				return true
	return false


static func _actions_have_power_change_direction(
	actions_value: Variant,
	direction: int
) -> bool:
	if not actions_value is Array:
		return false
	for action_value: Variant in actions_value as Array:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		if StringName(action.get("type", &"")) == Catalog.ACTION_CHANGE_POWERS:
			var amount: Variant = action.get("amount", 0)
			if typeof(amount) == TYPE_INT and signi(int(amount)) == direction:
				return true
			# 目录目前唯一的动态点数值是牌数；它不会为负，语义上属于增加。
			if amount is Dictionary and direction > 0:
				return true
		if _actions_have_power_change_direction(action.get("actions", null), direction):
			return true
	return false


static func _actions_exile_source(
	actions_value: Variant,
	action_subject_is_source: bool,
	trigger_card_is_source: bool
) -> bool:
	if not actions_value is Array:
		return false
	for action_value: Variant in actions_value as Array:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		var action_type := StringName(action.get("type", &""))
		if action_type == Catalog.ACTION_EXILE_SELF and action_subject_is_source:
			return true
		if action_type == Catalog.ACTION_EXILE_CARD:
			var card_reference := StringName(action.get("card", &""))
			if (
				card_reference == Catalog.CARD_REF_ABILITY_SOURCE
				or trigger_card_is_source
				and card_reference == Catalog.CARD_REF_TRIGGER_CARD
			):
				return true
		var nested_subject_is_source: bool = action_subject_is_source
		if action_type == Catalog.ACTION_FOR_EACH_SELECTED_CARD:
			nested_subject_is_source = false
		if _actions_exile_source(
			action.get("actions", null),
			nested_subject_is_source,
			trigger_card_is_source
		):
			return true
	return false


static func _actions_exile_other_card(
	actions_value: Variant,
	action_subject_is_source: bool,
	trigger_card_is_source: bool
) -> bool:
	if not actions_value is Array:
		return false
	for action_value: Variant in actions_value as Array:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		var action_type := StringName(action.get("type", &""))
		if action_type == Catalog.ACTION_EXILE_SELF and not action_subject_is_source:
			return true
		if action_type == Catalog.ACTION_EXILE_CARD:
			var card_reference := StringName(action.get("card", &""))
			if (
				card_reference != Catalog.CARD_REF_ABILITY_SOURCE
				and not (
					trigger_card_is_source
					and card_reference == Catalog.CARD_REF_TRIGGER_CARD
				)
			):
				return true
		var nested_subject_is_source: bool = action_subject_is_source
		if action_type == Catalog.ACTION_FOR_EACH_SELECTED_CARD:
			nested_subject_is_source = false
		if _actions_exile_other_card(
			action.get("actions", null),
			nested_subject_is_source,
			trigger_card_is_source
		):
			return true
	return false


static func has_bead_trigger_ability(card: Dictionary) -> bool:
	for ability_value: Variant in card.get("active_abilities", []):
		if not ability_value is Dictionary:
			continue
		for trigger_value: Variant in (ability_value as Dictionary).get("triggers", []):
			if not trigger_value is Dictionary:
				continue
			var trigger: Dictionary = trigger_value
			var event_type := StringName(trigger.get("event", &""))
			if event_type == &"":
				continue
			# 开局与弃牌后能力通常只承担一次性规则，不单独制造常驻珠子。
			if event_type in [Catalog.TRIGGER_DUEL_STARTED, Catalog.CARD_AFTER_DISCARDED]:
				continue
			if not _is_own_summon_only_trigger(trigger):
				return true
	return false


static func has_ki_threshold_trigger(card: Dictionary) -> bool:
	for ability_value: Variant in card.get("active_abilities", []):
		if not ability_value is Dictionary:
			continue
		for trigger_value: Variant in (ability_value as Dictionary).get("triggers", []):
			if not trigger_value is Dictionary:
				continue
			if _list_has_type(
				(trigger_value as Dictionary).get("conditions", []),
				Catalog.CONDITION_KI_AT_LEAST
			):
				return true
	return false


static func _is_own_summon_only_trigger(trigger: Dictionary) -> bool:
	var event_type: StringName = StringName(trigger.get("event", &""))
	if event_type not in [
		Catalog.TRIGGER_CARD_BEFORE_SUMMONED,
		Catalog.TRIGGER_CARD_SUMMONED,
		Catalog.TRIGGER_CARD_AFTER_SUMMONED,
	]:
		return false
	return _list_has_type(
		trigger.get("conditions", []),
		Catalog.CONDITION_TRIGGER_CARD_IS_SELF
	)


static func _list_has_type(values: Array, expected_type: StringName) -> bool:
	for value: Variant in values:
		if (
			value is Dictionary
			and StringName((value as Dictionary).get("type", &"")) == expected_type
		):
			return true
	return false


static func has_modifier(
	card: Dictionary,
	modifier_type: StringName,
	enabled_effect_gates: Variant = null
) -> bool:
	for modifier: Dictionary in _get_modifier_views(card, enabled_effect_gates):
		if StringName(modifier.get("type", &"")) == modifier_type:
			return true
	return false


static func _get_modifier_views(
	card: Dictionary,
	enabled_effect_gates: Variant = null
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not card_effects_enabled(card, enabled_effect_gates):
		return result
	for ability_value: Variant in card.get("active_abilities", []):
		if not ability_value is Dictionary:
			continue
		for modifier_value: Variant in (ability_value as Dictionary).get("modifiers", []):
			if modifier_value is Dictionary:
				result.append(modifier_value as Dictionary)
	return result
