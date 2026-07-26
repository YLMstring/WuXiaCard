class_name DuelTriggers
extends RefCounted

const Catalog = preload("res://scripts/card_catalog.gd")
const Effects = preload("res://scripts/duel_effects.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const StateData = preload("res://scripts/duel_state.gd")


static func discover(
	state: StateData,
	event_id: StringName,
	context: Dictionary
) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	if state == null or event_id not in Catalog.KNOWN_TRIGGER_EVENTS:
		return groups
	var owner_id: int = int(context.get("owner_id", 0))
	if event_id == Catalog.TRIGGER_AFTER_SUCCESSFUL_FLIP_BY_SELF:
		_discover_from_cell(
			state,
			event_id,
			owner_id,
			int(context.get("source_cell", -1)),
			StringName(context.get("source_instance_id", &"")),
			groups
		)
	elif event_id == Catalog.TRIGGER_END_OWNER_TURN:
		for source_cell: int in range(state.board.size()):
			_discover_from_cell(state, event_id, owner_id, source_cell, &"", groups)
	elif event_id == Catalog.TRIGGER_CARD_SUMMONED:
		for source_cell: int in range(state.board.size()):
			_discover_from_cell(state, event_id, 0, source_cell, &"", groups, context)
	return groups


static func resolve(state: StateData, groups: Array[Dictionary]) -> Dictionary:
	var events: Array[Dictionary] = []
	var extra_turn_requests: Array[Dictionary] = []
	var attack_requests: Array[Dictionary] = []
	if state == null:
		return {
			"events": events,
			"extra_turn_requests": extra_turn_requests,
			"attack_requests": attack_requests,
		}
	for group: Dictionary in groups:
		var resolved: Dictionary = _get_current_rule(state, group)
		if resolved.is_empty():
			continue
		var card: Dictionary = resolved["card"]
		var rule: Dictionary = resolved["rule"]
		var context: Dictionary = group.get("context", {})
		var source_cell: int = int(group.get("source_cell", -1))
		if not _conditions_match(state, source_cell, card, rule.get("conditions", []), context):
			continue
		var owner_id: int = int(group.get("owner_id", 0))
		var instance_id := StringName(group.get("source_instance_id", &""))
		var ability_id := StringName(group.get("ability_id", &""))
		var actions: Array = rule.get("actions", [])
		for action_value: Variant in actions:
			var action: Dictionary = action_value
			var action_type := StringName(action.get("type", &""))
			if action_type == Catalog.TRIGGER_ACTION_GAIN_KI:
				var previous_ki: int = int(card.get("ki", 0))
				var resulting_ki: int = previous_ki + int(action.get("amount", 0))
				card["ki"] = resulting_ki
				events.append(_make_ki_event(
					source_cell,
					owner_id,
					instance_id,
					ability_id,
					previous_ki,
					resulting_ki,
					action_type
				))
			elif action_type == Catalog.TRIGGER_ACTION_SPEND_ALL_KI:
				var previous_ki: int = int(card.get("ki", 0))
				card["ki"] = 0
				if previous_ki != 0:
					events.append(_make_ki_event(
						source_cell,
						owner_id,
						instance_id,
						ability_id,
						previous_ki,
						0,
						action_type
					))
			elif action_type == Catalog.TRIGGER_ACTION_REQUEST_EXTRA_TURN:
				extra_turn_requests.append({
					"owner_id": owner_id,
					"source_cell": source_cell,
					"source_instance_id": instance_id,
					"ability_id": ability_id,
				})
			elif action_type == Catalog.TRIGGER_ACTION_ATTACK_TRIGGER_CARD:
				var target_slot: Dictionary = _get_trigger_card_slot(state, context)
				if target_slot.is_empty():
					continue
				var target_card: Dictionary = target_slot.get("card", {})
				attack_requests.append({
					"source_cell": source_cell,
					"source_instance_id": instance_id,
					"source_owner_id": owner_id,
					"target_cell": int(context.get("trigger_cell", -1)),
					"target_instance_id": StringName(target_card.get("instance_id", &"")),
					"target_owner_id": int(target_slot.get("owner", 0)),
					"ability_id": ability_id,
					"reason": &"card_summoned_reaction",
				})
	return {
		"events": events,
		"extra_turn_requests": extra_turn_requests,
		"attack_requests": attack_requests,
	}


static func _discover_from_cell(
	state: StateData,
	event_id: StringName,
	owner_id: int,
	source_cell: int,
	expected_instance_id: StringName,
	groups: Array[Dictionary],
	context: Dictionary = {}
) -> void:
	if source_cell < 0 or source_cell >= state.board.size():
		return
	var slot_value: Variant = state.board[source_cell]
	if slot_value == null:
		return
	var slot: Dictionary = slot_value
	var current_owner_id: int = int(slot.get("owner", 0))
	if owner_id != 0 and current_owner_id != owner_id:
		return
	var card: Dictionary = slot.get("card", {})
	var instance_id := StringName(card.get("instance_id", &""))
	if expected_instance_id != &"" and instance_id != expected_instance_id:
		return
	var active_effects: Array = card.get("active_effects", [])
	for effect_value: Variant in active_effects:
		var effect: Dictionary = effect_value
		var triggers: Array = effect.get("triggers", [])
		for trigger_index: int in range(triggers.size()):
			var rule: Dictionary = triggers[trigger_index]
			if StringName(rule.get("event", &"")) != event_id:
				continue
			if not _conditions_match(state, source_cell, card, rule.get("conditions", []), context):
				continue
			groups.append({
				"event_id": event_id,
				"owner_id": current_owner_id,
				"source_cell": source_cell,
				"source_instance_id": instance_id,
				"ability_id": StringName(effect.get("id", &"")),
				"trigger_index": trigger_index,
				"context": context.duplicate(true),
				"actions": (rule.get("actions", []) as Array).duplicate(true),
			})


static func _get_current_rule(state: StateData, group: Dictionary) -> Dictionary:
	var source_cell: int = int(group.get("source_cell", -1))
	if source_cell < 0 or source_cell >= state.board.size():
		return {}
	var slot_value: Variant = state.board[source_cell]
	if slot_value == null or int((slot_value as Dictionary).get("owner", 0)) != int(group.get("owner_id", 0)):
		return {}
	var card: Dictionary = (slot_value as Dictionary).get("card", {})
	if StringName(card.get("instance_id", &"")) != StringName(group.get("source_instance_id", &"")):
		return {}
	var effect: Dictionary = Effects.find_active_effect(card, StringName(group.get("ability_id", &"")))
	if effect.is_empty():
		return {}
	var triggers: Array = effect.get("triggers", [])
	var trigger_index: int = int(group.get("trigger_index", -1))
	if trigger_index < 0 or trigger_index >= triggers.size():
		return {}
	var rule: Dictionary = triggers[trigger_index]
	if StringName(rule.get("event", &"")) != StringName(group.get("event_id", &"")):
		return {}
	return {"card": card, "rule": rule}


static func _conditions_match(
	state: StateData,
	source_cell: int,
	card: Dictionary,
	conditions_value: Variant,
	context: Dictionary
) -> bool:
	if not conditions_value is Array:
		return false
	var conditions: Array = conditions_value
	if conditions.is_empty():
		return true
	for condition_value: Variant in conditions:
		if not condition_value is Dictionary:
			return false
		var condition: Dictionary = condition_value
		var condition_type := StringName(condition.get("type", &""))
		if condition_type == Catalog.CONDITION_KI_AT_LEAST:
			if int(card.get("ki", 0)) < int(condition.get("amount", 0)):
				return false
		elif condition_type == Catalog.CONDITION_TRIGGER_CARD_IS_ENEMY:
			var target_slot: Dictionary = _get_trigger_card_slot(state, context)
			if target_slot.is_empty():
				return false
			var source_slot: Dictionary = state.board[source_cell]
			if int(source_slot.get("owner", 0)) == int(target_slot.get("owner", 0)):
				return false
		elif condition_type == Catalog.CONDITION_TRIGGER_CARD_IN_RANGE:
			if not Rules.can_attack_target(
				state.board,
				source_cell,
				int(context.get("trigger_cell", -1)),
				{
					"reason": &"card_summoned_reaction",
					"trigger_context": context,
				}
			):
				return false
		else:
			return false
	return true


static func _get_trigger_card_slot(state: StateData, context: Dictionary) -> Dictionary:
	var target_cell: int = int(context.get("trigger_cell", -1))
	if target_cell < 0 or target_cell >= state.board.size():
		return {}
	var target_value: Variant = state.board[target_cell]
	if target_value == null:
		return {}
	var target_slot: Dictionary = target_value
	var target_card: Dictionary = target_slot.get("card", {})
	if StringName(target_card.get("instance_id", &"")) != StringName(context.get("trigger_instance_id", &"")):
		return {}
	return target_slot


static func _make_ki_event(
	source_cell: int,
	owner_id: int,
	instance_id: StringName,
	ability_id: StringName,
	previous_ki: int,
	resulting_ki: int,
	action_type: StringName
) -> Dictionary:
	return {
		"type": &"ki_changed",
		"source_cell": source_cell,
		"target_cell": source_cell,
		"owner_id": owner_id,
		"instance_id": instance_id,
		"effect_id": ability_id,
		"previous_ki": previous_ki,
		"ki": resulting_ki,
		"change_reason": action_type,
	}
