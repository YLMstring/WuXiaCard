class_name DuelAbilities
extends RefCounted


static func is_activate_ability(ability: Dictionary) -> bool:
	var activation_value: Variant = ability.get("activation", null)
	return activation_value is Dictionary and not (activation_value as Dictionary).is_empty()


static func get_activate_ability(card: Dictionary) -> Dictionary:
	var active_abilities: Array = card.get("active_abilities", [])
	for ability_value: Variant in active_abilities:
		if not ability_value is Dictionary:
			continue
		var ability: Dictionary = ability_value
		if is_activate_ability(ability):
			return ability
	return {}


static func get_activation(card: Dictionary) -> Dictionary:
	var ability: Dictionary = get_activate_ability(card)
	if ability.is_empty():
		return {}
	return ability.get("activation", {}) as Dictionary


static func card_uses_ki(card: Dictionary) -> bool:
	return not get_activate_ability(card).is_empty()


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
