class_name DuelAbilities
extends RefCounted

const Catalog = preload("res://scripts/card_catalog.gd")

const KI_BEAD_NONE: StringName = &"none"
const KI_BEAD_DARK: StringName = &"dark"
const KI_BEAD_LIGHT: StringName = &"light"
const KI_BEAD_GOLD: StringName = &"gold"


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


static func get_ki_bead_presentation(card: Dictionary) -> Dictionary:
	var ki: int = maxi(0, int(card.get("ki", 0)))
	var has_activation: bool = card_uses_ki(card)
	var has_ki_threshold: bool = has_ki_threshold_trigger(card)
	var kind: StringName = KI_BEAD_NONE
	if has_temporary_flip_protection(card):
		kind = KI_BEAD_GOLD
	elif has_activation or has_non_summon_trigger_ability(card):
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
	}


static func has_temporary_flip_protection(card: Dictionary) -> bool:
	for ability_value: Variant in card.get("active_abilities", []):
		if not ability_value is Dictionary:
			continue
		var ability: Dictionary = ability_value
		var triggers: Array = ability.get("triggers", [])
		if (
			_has_trigger_semantics(
				triggers,
				Catalog.CARD_BEFORE_FLIPPED,
				Catalog.CONDITION_TRIGGER_CARD_IS_SELF,
				Catalog.ACTION_PREVENT_TRIGGER_FLIP
			)
			and _has_trigger_semantics(
				triggers,
				Catalog.CARD_AFTER_FLIPPED,
				Catalog.CONDITION_TRIGGER_CARD_WAS_ENEMY,
				Catalog.ACTION_REMOVE_THIS_ABILITY
			)
			and _has_trigger_semantics(
				triggers,
				Catalog.TRIGGER_START_OWNER_TURN,
				Catalog.CONDITION_TURN_OWNER_IS_SELF,
				Catalog.ACTION_REMOVE_THIS_ABILITY
			)
		):
			return true
	return false


static func has_non_summon_trigger_ability(card: Dictionary) -> bool:
	for ability_value: Variant in card.get("active_abilities", []):
		if not ability_value is Dictionary:
			continue
		for trigger_value: Variant in (ability_value as Dictionary).get("triggers", []):
			if not trigger_value is Dictionary:
				continue
			var trigger: Dictionary = trigger_value
			if StringName(trigger.get("event", &"")) == &"":
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


static func _has_trigger_semantics(
	triggers: Array,
	event_type: StringName,
	condition_type: StringName,
	action_type: StringName
) -> bool:
	for trigger_value: Variant in triggers:
		if not trigger_value is Dictionary:
			continue
		var trigger: Dictionary = trigger_value
		if StringName(trigger.get("event", &"")) != event_type:
			continue
		if (
			_list_has_type(trigger.get("conditions", []), condition_type)
			and _list_has_type(trigger.get("actions", []), action_type)
		):
			return true
	return false


static func _list_has_type(values: Array, expected_type: StringName) -> bool:
	for value: Variant in values:
		if (
			value is Dictionary
			and StringName((value as Dictionary).get("type", &"")) == expected_type
		):
			return true
	return false


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
	card.erase("temporary_suppression_batches")
	return removed_count


static func temporarily_remove_non_retained_abilities(
	card: Dictionary,
	current_turn: int
) -> Array[Dictionary]:
	var retained_abilities: Array = []
	var removed_entries: Array[Dictionary] = []
	var active_abilities: Array = card.get("active_abilities", [])
	for ability_index: int in range(active_abilities.size()):
		var ability_value: Variant = active_abilities[ability_index]
		if not ability_value is Dictionary:
			continue
		var ability: Dictionary = ability_value
		if bool(ability.get("retained_on_flip", false)):
			retained_abilities.append(ability.duplicate(true))
		else:
			removed_entries.append({
				"index": ability_index,
				"ability": ability.duplicate(true),
			})
	if removed_entries.is_empty():
		return removed_entries
	card["active_abilities"] = retained_abilities
	var batches: Array = card.get("temporary_suppression_batches", [])
	batches.append({
		"expires_after_turn": current_turn,
		"entries": removed_entries.duplicate(true),
	})
	card["temporary_suppression_batches"] = batches
	return removed_entries


static func restore_temporarily_removed_abilities(
	card: Dictionary,
	completed_turn: int
) -> Array[Dictionary]:
	var batches: Array = card.get("temporary_suppression_batches", [])
	if batches.is_empty():
		return []
	var restored: Array[Dictionary] = []
	var remaining_batches: Array = []
	for batch_index: int in range(batches.size() - 1, -1, -1):
		var batch_value: Variant = batches[batch_index]
		if not batch_value is Dictionary:
			continue
		var batch: Dictionary = batch_value
		if int(batch.get("expires_after_turn", completed_turn)) > completed_turn:
			remaining_batches.push_front(batch.duplicate(true))
			continue
		var entries: Array = batch.get("entries", [])
		entries.sort_custom(func(first: Variant, second: Variant) -> bool:
			return int((first as Dictionary).get("index", 0)) < int((second as Dictionary).get("index", 0))
		)
		var active_abilities: Array = card.get("active_abilities", [])
		for entry_value: Variant in entries:
			if not entry_value is Dictionary:
				continue
			var entry: Dictionary = entry_value
			var ability_value: Variant = entry.get("ability", null)
			if not ability_value is Dictionary:
				continue
			var insert_index: int = clampi(int(entry.get("index", active_abilities.size())), 0, active_abilities.size())
			active_abilities.insert(insert_index, (ability_value as Dictionary).duplicate(true))
			restored.append((ability_value as Dictionary).duplicate(true))
		card["active_abilities"] = active_abilities
	if remaining_batches.is_empty():
		card.erase("temporary_suppression_batches")
	else:
		card["temporary_suppression_batches"] = remaining_batches
	return restored


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


static func can_attack_at_orthogonal_distance_two(card: Dictionary) -> bool:
	return has_modifier(card, Catalog.MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO)


static func allows_intervening_ally_at_orthogonal_distance_two(card: Dictionary) -> bool:
	for modifier: Dictionary in get_modifiers(card):
		if (
			StringName(modifier.get("type", &""))
			== Catalog.MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO
			and bool(modifier.get("allow_intervening_ally", false))
		):
			return true
	return false


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


static func get_minimum_effective_defending_power(
	card: Dictionary,
	fallback_direction: int,
	fallback_power: int
) -> int:
	var powers: Array = card.get("powers", [])
	if powers.size() != 4:
		return get_effective_defending_power(card, fallback_direction, fallback_power)
	var result: int = get_effective_defending_power(card, 0, int(powers[0]))
	for direction: int in range(1, 4):
		result = mini(
			result,
			get_effective_defending_power(card, direction, int(powers[direction]))
		)
	return result
