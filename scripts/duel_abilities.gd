class_name DuelAbilities
extends RefCounted

const Catalog = preload("res://scripts/card_catalog.gd")


static func is_activate_ability(ability: Dictionary) -> bool:
	var activation_value: Variant = ability.get("activation", null)
	return activation_value is Dictionary and not (activation_value as Dictionary).is_empty()


static func get_activate_ability(card: Dictionary) -> Dictionary:
	return get_activate_ability_at(card, 0)


static func get_activate_abilities(card: Dictionary) -> Array[Dictionary]:
	var activate_abilities: Array[Dictionary] = []
	var active_abilities: Array = card.get("active_abilities", [])
	for ability_value: Variant in active_abilities:
		if not ability_value is Dictionary:
			continue
		var ability: Dictionary = ability_value
		if is_activate_ability(ability):
			activate_abilities.append(ability)
	return activate_abilities


static func get_activate_ability_at(card: Dictionary, activation_index: int) -> Dictionary:
	var activate_abilities: Array[Dictionary] = get_activate_abilities(card)
	if activation_index < 0 or activation_index >= activate_abilities.size():
		return {}
	return activate_abilities[activation_index]


static func get_activation(card: Dictionary, activation_index: int = 0) -> Dictionary:
	var ability: Dictionary = get_activate_ability_at(card, activation_index)
	if ability.is_empty():
		return {}
	return ability.get("activation", {}) as Dictionary


static func card_uses_ki(card: Dictionary) -> bool:
	return not get_activate_abilities(card).is_empty()


static func replace_activate_ability(card: Dictionary, new_ability: Dictionary) -> void:
	var retained_abilities: Array = []
	var active_abilities: Array = card.get("active_abilities", [])
	for ability_value: Variant in active_abilities:
		if not ability_value is Dictionary:
			continue
		var ability: Dictionary = ability_value
		if not is_activate_ability(ability):
			retained_abilities.append(ability.duplicate(true))
	if not new_ability.is_empty():
		retained_abilities.append(new_ability.duplicate(true))
	card["active_abilities"] = retained_abilities


static func remove_non_retained_abilities(card: Dictionary) -> int:
	var retained_abilities: Array = []
	var removed_count: int = 0
	for ability_value: Variant in card.get("active_abilities", []):
		if not ability_value is Dictionary:
			continue
		var ability: Dictionary = ability_value
		if bool(ability.get("retained_on_flip", false)):
			retained_abilities.append(ability.duplicate(true))
		else:
			removed_count += 1
	card["active_abilities"] = retained_abilities
	return removed_count


static func has_modifier(card: Dictionary, modifier_type: StringName) -> bool:
	for modifier: Dictionary in get_modifiers(card):
		if StringName(modifier.get("type", &"")) == modifier_type:
			return true
	return false


static func get_modifiers(card: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for ability_value: Variant in card.get("active_abilities", []):
		if not ability_value is Dictionary:
			continue
		for modifier_value: Variant in (ability_value as Dictionary).get("modifiers", []):
			if modifier_value is Dictionary:
				result.append((modifier_value as Dictionary).duplicate(true))
	return result


static func get_effective_defending_power(
	card: Dictionary,
	_direction: int,
	base_power: int
) -> int:
	var result: int = base_power
	for modifier: Dictionary in get_modifiers(card):
		if StringName(modifier.get("type", &"")) == Catalog.MODIFIER_DEFENDING_POWER_OVERRIDE:
			result = int(modifier.get("value", result))
	return result
