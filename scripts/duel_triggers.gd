class_name DuelTriggers
extends RefCounted

const Catalog = preload("res://scripts/card_catalog.gd")
const Executor = preload("res://scripts/duel_ability_executor.gd")
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
	if event_id == Catalog.TRIGGER_CARD_AFTER_SUMMONED:
		_discover_from_cell(
			state,
			event_id,
			int(context.get("trigger_cell", -1)),
			groups,
			context
		)
		return groups
	for source_cell: int in range(state.board.size()):
		_discover_from_cell(state, event_id, source_cell, groups, context)
	return groups


static func resolve_group(state: StateData, group: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"events": [],
		"extra_turn_requests": [],
		"attack_requests": [],
	}
	if state == null:
		return result
	var resolved: Dictionary = _get_current_rule(state, group)
	if resolved.is_empty():
		return result
	var card: Dictionary = resolved.get("card", {})
	var rule: Dictionary = resolved.get("rule", {})
	var source_cell: int = int(group.get("source_cell", -1))
	var context: Dictionary = group.get("context", {})
	if not _conditions_match(state, source_cell, card, rule.get("conditions", []), context):
		return result
	var action_result: Dictionary = Executor.execute_actions(
		state,
		source_cell,
		StringName(group.get("source_instance_id", &"")),
		int(group.get("source_owner_id", 0)),
		rule.get("actions", []) as Array,
		context
	)
	var events: Array = action_result.get("events", [])
	events.push_front({
		"type": &"ability_triggered",
		"source_cell": source_cell,
		"source_instance_id": StringName(group.get("source_instance_id", &"")),
		"source_owner_id": int(group.get("source_owner_id", 0)),
	})
	action_result["events"] = events
	return action_result


static func _discover_from_cell(
	state: StateData,
	event_id: StringName,
	source_cell: int,
	groups: Array[Dictionary],
	context: Dictionary
) -> void:
	if source_cell < 0 or source_cell >= state.board.size():
		return
	var slot_value: Variant = state.board[source_cell]
	if slot_value == null:
		return
	var slot: Dictionary = slot_value
	var card: Dictionary = slot.get("card", {})
	var instance_id := StringName(card.get("instance_id", &""))
	var active_abilities: Array = card.get("active_abilities", [])
	for ability_index: int in range(active_abilities.size()):
		var ability_value: Variant = active_abilities[ability_index]
		if not ability_value is Dictionary:
			continue
		var ability: Dictionary = ability_value
		var triggers: Array = ability.get("triggers", [])
		for trigger_index: int in range(triggers.size()):
			var rule_value: Variant = triggers[trigger_index]
			if not rule_value is Dictionary:
				continue
			var rule: Dictionary = rule_value
			if StringName(rule.get("event", &"")) != event_id:
				continue
			if not _conditions_match(
				state,
				source_cell,
				card,
				rule.get("conditions", []),
				context
			):
				continue
			groups.append({
				"event_id": event_id,
				"source_owner_id": int(slot.get("owner", 0)),
				"source_cell": source_cell,
				"source_instance_id": instance_id,
				"ability_index": ability_index,
				"ability_snapshot": ability.duplicate(true),
				"trigger_index": trigger_index,
				"context": context.duplicate(true),
			})


static func _get_current_rule(state: StateData, group: Dictionary) -> Dictionary:
	var source_cell: int = int(group.get("source_cell", -1))
	if source_cell < 0 or source_cell >= state.board.size():
		return {}
	var slot_value: Variant = state.board[source_cell]
	if slot_value == null:
		return {}
	var slot: Dictionary = slot_value
	if int(slot.get("owner", 0)) != int(group.get("source_owner_id", 0)):
		return {}
	var card: Dictionary = slot.get("card", {})
	if (
		StringName(card.get("instance_id", &""))
		!= StringName(group.get("source_instance_id", &""))
	):
		return {}
	var active_abilities: Array = card.get("active_abilities", [])
	var ability_index: int = int(group.get("ability_index", -1))
	if ability_index < 0 or ability_index >= active_abilities.size():
		return {}
	var ability_value: Variant = active_abilities[ability_index]
	if not ability_value is Dictionary:
		return {}
	var ability: Dictionary = ability_value
	if ability != group.get("ability_snapshot", {}):
		return {}
	var triggers: Array = ability.get("triggers", [])
	var trigger_index: int = int(group.get("trigger_index", -1))
	if trigger_index < 0 or trigger_index >= triggers.size():
		return {}
	var rule_value: Variant = triggers[trigger_index]
	if not rule_value is Dictionary:
		return {}
	var rule: Dictionary = rule_value
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
	for condition_value: Variant in conditions:
		if not condition_value is Dictionary:
			return false
		var condition: Dictionary = condition_value
		var condition_type := StringName(condition.get("type", &""))
		if condition_type == Catalog.CONDITION_KI_AT_LEAST:
			if int(card.get("ki", 0)) < int(condition.get("amount", 0)):
				return false
		elif condition_type == Catalog.CONDITION_TRIGGER_CARD_IS_ENEMY:
			var trigger_slot: Dictionary = _get_context_card_slot(
				state,
				context,
				"trigger_cell",
				"trigger_instance_id"
			)
			if trigger_slot.is_empty():
				return false
			var source_slot: Dictionary = state.board[source_cell]
			if int(source_slot.get("owner", 0)) == int(trigger_slot.get("owner", 0)):
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
		elif condition_type == Catalog.CONDITION_TRIGGER_CARD_IS_SELF:
			if (
				StringName(card.get("instance_id", &""))
				!= StringName(context.get("trigger_instance_id", &""))
				or source_cell != int(context.get("trigger_cell", -1))
			):
				return false
		elif condition_type == Catalog.CONDITION_ATTACKER_CARD_IS_SELF:
			if (
				StringName(card.get("instance_id", &""))
				!= StringName(context.get("attacker_instance_id", &""))
				or source_cell != int(context.get("attacker_cell", -1))
			):
				return false
		elif condition_type == Catalog.CONDITION_TURN_OWNER_IS_SELF:
			var source_slot: Dictionary = state.board[source_cell]
			if int(source_slot.get("owner", 0)) != int(context.get("turn_owner_id", 0)):
				return false
		else:
			return false
	return true


static func _get_context_card_slot(
	state: StateData,
	context: Dictionary,
	cell_key: String,
	instance_key: String
) -> Dictionary:
	var cell: int = int(context.get(cell_key, -1))
	if cell < 0 or cell >= state.board.size():
		return {}
	var slot_value: Variant = state.board[cell]
	if slot_value == null:
		return {}
	var slot: Dictionary = slot_value
	var card: Dictionary = slot.get("card", {})
	if StringName(card.get("instance_id", &"")) != StringName(context.get(instance_key, &"")):
		return {}
	return slot
