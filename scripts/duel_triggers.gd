class_name DuelTriggers
extends RefCounted

const Catalog = preload("res://scripts/card_catalog.gd")
const Abilities = preload("res://scripts/duel_abilities.gd")
const Executor = preload("res://scripts/duel_ability_executor.gd")
const Selector = preload("res://scripts/duel_card_selector.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Revelation = preload("res://scripts/duel_revelation.gd")
const StateData = preload("res://scripts/duel_state.gd")


static func discover(
	state: StateData,
	event_id: StringName,
	context: Dictionary
) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	if state == null or event_id not in Catalog.KNOWN_TRIGGER_EVENTS:
		return groups
	if event_id == Catalog.TRIGGER_CARD_BEFORE_SUMMONED:
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


static func resolve_group(
	state: StateData,
	group: Dictionary,
	attack_resolver: Callable = Callable(),
	flip_resolver: Callable = Callable(),
	summon_resolver: Callable = Callable(),
	before_move_resolver: Callable = Callable(),
	event_resolver: Callable = Callable()
) -> Dictionary:
	var result: Dictionary = {
		"events": [],
		"extra_turn_requests": [],
		"attack_requests": [],
		"flip_requests": [],
		"summon_requests": [],
		"flip_prevention_requests": [],
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
	context = context.duplicate(true)
	context["resolving_ability_index"] = int(group.get("ability_index", -1))
	context["resolving_trigger_index"] = int(group.get("trigger_index", -1))
	context["resolving_event_id"] = StringName(group.get("event_id", &""))
	context["resolving_ability_snapshot"] = group.get("ability_snapshot", {}).duplicate(true)
	if not _conditions_match(state, source_cell, card, rule.get("conditions", []), context):
		return result
	var action_result: Dictionary = Executor.execute_actions(
		state,
		source_cell,
		StringName(group.get("source_instance_id", &"")),
		int(group.get("source_owner_id", 0)),
		rule.get("actions", []) as Array,
		context,
		attack_resolver,
		flip_resolver,
		summon_resolver,
		before_move_resolver,
		event_resolver
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
	if not Abilities.card_effects_enabled(
		card,
		state.get_enabled_effect_gates(int(slot.get("owner", 0)))
	):
		return
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
	if not Abilities.card_effects_enabled(
		card,
		state.get_enabled_effect_gates(int(slot.get("owner", 0)))
	):
		return {}
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
		elif condition_type in [
			Catalog.CONDITION_TRIGGER_CARD_IS_ALLY,
			Catalog.CONDITION_TRIGGER_CARD_IS_ENEMY,
		]:
			var trigger_slot: Dictionary = _get_context_card_slot(
				state,
				context,
				"trigger_cell",
				"trigger_instance_id"
			)
			if trigger_slot.is_empty():
				return false
			var source_slot: Dictionary = state.board[source_cell]
			var owners_match: bool = (
				int(source_slot.get("owner", 0)) == int(trigger_slot.get("owner", 0))
			)
			if (
				condition_type == Catalog.CONDITION_TRIGGER_CARD_IS_ALLY
				and not owners_match
				or condition_type == Catalog.CONDITION_TRIGGER_CARD_IS_ENEMY
				and owners_match
			):
				return false
		elif condition_type == Catalog.CONDITION_TRIGGER_CARD_IN_RANGE:
			if not Rules.is_target_in_attack_range(
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
		elif condition_type == Catalog.CONDITION_KI_CHANGED_CARD_IS_SELF:
			if (
				StringName(card.get("instance_id", &""))
				!= StringName(context.get("trigger_instance_id", &""))
				or source_cell != int(context.get("trigger_cell", -1))
			):
				return false
		elif condition_type == Catalog.CONDITION_KI_REACHED_ZERO:
			if (
				int(context.get("previous_ki", 0)) <= 0
				or int(context.get("ki", -1)) != 0
			):
				return false
		elif condition_type == Catalog.CONDITION_ATTACKER_CARD_IS_SELF:
			if (
				StringName(card.get("instance_id", &""))
				!= StringName(context.get("attacker_instance_id", &""))
				or source_cell != int(context.get("attacker_cell", -1))
			):
				return false
		elif condition_type == Catalog.CONDITION_ATTACK_IS_NOT_REPEAT:
			if bool(context.get("repeat_attack", false)):
				return false
		elif condition_type == Catalog.CONDITION_ACTIVATION_OWNER_IS_ALLY:
			var source_slot: Dictionary = state.board[source_cell]
			var activation_owner: int = int(context.get("activation_owner_id", 0))
			if (
				activation_owner not in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]
				or activation_owner != int(source_slot.get("owner", 0))
			):
				return false
		elif condition_type == Catalog.CONDITION_TRIGGER_CARD_OUTSIDE_SOURCE_OWNER_HAND:
			var source_slot: Dictionary = state.board[source_cell]
			var source_owner: int = int(source_slot.get("owner", 0))
			if (
				StringName(context.get("trigger_zone", &"")) == Catalog.CARD_ZONE_HAND
				and int(context.get("trigger_owner_id", 0)) == source_owner
			):
				return false
		elif condition_type == Catalog.CONDITION_TURN_OWNER_IS_SELF:
			var source_slot: Dictionary = state.board[source_cell]
			if int(source_slot.get("owner", 0)) != int(context.get("turn_owner_id", 0)):
				return false
		elif condition_type == Catalog.CONDITION_TRIGGER_CARD_REVEALED_TO_SELF:
			var revealed_slot: Dictionary = _get_context_card_slot(
				state,
				context,
				"trigger_cell",
				"trigger_instance_id"
			)
			if revealed_slot.is_empty():
				return false
			var source_slot: Dictionary = state.board[source_cell]
			if not Revelation.is_revealed_to(
				revealed_slot.get("card", {}),
				int(source_slot.get("owner", 0))
			):
				return false
		elif condition_type == Catalog.CONDITION_TRIGGER_CARD_WAS_ENEMY:
			var source_slot: Dictionary = state.board[source_cell]
			var previous_owner: int = int(context.get("trigger_owner_id", 0))
			if (
				previous_owner not in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]
				or previous_owner == int(source_slot.get("owner", 0))
			):
				return false
		elif condition_type == Catalog.CONDITION_ATTACKER_CARD_IS_ENEMY:
			var source_slot: Dictionary = state.board[source_cell]
			var attacker_owner: int = int(context.get("attacker_owner_id", 0))
			if (
				attacker_owner not in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]
				or attacker_owner == int(source_slot.get("owner", 0))
			):
				return false
		elif condition_type == Catalog.CONDITION_ATTACKER_CARD_IS_OTHER_ALLY:
			var source_slot: Dictionary = state.board[source_cell]
			var attacker_owner: int = int(context.get("attacker_owner_id", 0))
			if (
				attacker_owner not in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]
				or attacker_owner != int(source_slot.get("owner", 0))
				or StringName(context.get("attacker_instance_id", &""))
				== StringName(card.get("instance_id", &""))
			):
				return false
		elif condition_type == Catalog.CONDITION_DRAWN_CARD_IS_ENEMY:
			var source_slot: Dictionary = state.board[source_cell]
			var drawn_owner: int = int(context.get("trigger_owner_id", 0))
			if (
				drawn_owner not in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]
				or drawn_owner == int(source_slot.get("owner", 0))
			):
				return false
		elif condition_type == Catalog.CONDITION_ATTACK_FLIPPED_ALLY_IN_RANGE:
			if not _attack_flipped_ally_in_range(
				state,
				source_cell,
				context.get("attack_flips", []) as Array
			):
				return false
		elif condition_type == Catalog.CONDITION_ATTACK_FLIPPED_ENEMY:
			var attacker_owner: int = int(context.get("attacker_owner_id", 0))
			var flipped_enemy: bool = false
			for record_value: Variant in context.get("attack_flips", []):
				if (
					record_value is Dictionary
					and int((record_value as Dictionary).get("previous_owner_id", 0))
					!= attacker_owner
				):
					flipped_enemy = true
					break
			if not flipped_enemy:
				return false
		elif condition_type == Catalog.CONDITION_ATTACKED_CARD_IS_SELF:
			if (
				StringName(card.get("instance_id", &""))
				!= StringName(context.get("attacked_instance_id", &""))
				or source_cell != int(context.get("attacked_cell", -1))
			):
				return false
		elif condition_type == Catalog.CONDITION_OWNER_DID_NOT_WIN:
			var source_slot: Dictionary = state.board[source_cell]
			var winning_owner_ids: Array = context.get("winning_owner_ids", [])
			if int(source_slot.get("owner", 0)) in winning_owner_ids:
				return false
		elif condition_type == Catalog.CONDITION_TRIGGER_CARD_ORIGINAL_OWNER_IS_SELF:
			var trigger_instance_id := StringName(context.get("trigger_instance_id", &""))
			var trigger_location: Dictionary = Selector.locate_card(state, trigger_instance_id)
			if (
				trigger_location.is_empty()
				or StringName(trigger_location.get("zone", &"")) != Catalog.CARD_ZONE_BOARD
			):
				return false
			var trigger_card: Dictionary = trigger_location.get("card", {})
			var original_owner_source_slot: Dictionary = state.board[source_cell]
			if (
				int(trigger_card.get("original_owner", 0))
				!= int(original_owner_source_slot.get("owner", 0))
			):
				return false
		elif condition_type == Catalog.CONDITION_MOVING_CARD_IS_SELF:
			if (
				StringName(card.get("instance_id", &""))
				!= StringName(context.get("moving_instance_id", &""))
				or source_cell != int(context.get("moving_source_cell", -1))
			):
				return false
		elif condition_type == Catalog.CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE:
			if not _are_adjacent(source_cell, int(context.get("trigger_cell", -1))):
				return false
		elif condition_type == Catalog.CONDITION_SOURCE_HAS_ADJACENT_EMPTY_CELL:
			if not _has_adjacent_empty_cell(state, source_cell):
				return false
		elif condition_type == Catalog.CONDITION_SOURCE_HAS_EMPTY_BETWEEN_ENEMY:
			if not _has_empty_between_enemy(state, source_cell):
				return false
		else:
			return false
	return true


static func _are_adjacent(first_cell: int, second_cell: int) -> bool:
	for direction: int in range(4):
		if Rules.get_neighbor_index(first_cell, direction) == second_cell:
			return true
	return false


static func _has_adjacent_empty_cell(state: StateData, source_cell: int) -> bool:
	for cell: int in range(state.board.size()):
		if state.board[cell] == null and _are_adjacent(source_cell, cell):
			return true
	return false


static func _has_empty_between_enemy(state: StateData, source_cell: int) -> bool:
	if source_cell < 0 or source_cell >= state.board.size():
		return false
	var source_value: Variant = state.board[source_cell]
	if source_value == null:
		return false
	var source_owner: int = int((source_value as Dictionary).get("owner", 0))
	for direction: int in range(4):
		var middle_cell: int = Rules.get_neighbor_index(source_cell, direction)
		if middle_cell < 0 or state.board[middle_cell] != null:
			continue
		var far_cell: int = Rules.get_neighbor_index(middle_cell, direction)
		if far_cell < 0 or state.board[far_cell] == null:
			continue
		if int((state.board[far_cell] as Dictionary).get("owner", 0)) != source_owner:
			return true
	return false


static func _attack_flipped_ally_in_range(
	state: StateData,
	source_cell: int,
	attack_flips: Array
) -> bool:
	if source_cell < 0 or source_cell >= state.board.size():
		return false
	var source_value: Variant = state.board[source_cell]
	if source_value == null:
		return false
	var source_owner: int = int((source_value as Dictionary).get("owner", 0))
	for record_value: Variant in attack_flips:
		if not record_value is Dictionary:
			continue
		var record: Dictionary = record_value
		if int(record.get("previous_owner_id", 0)) != source_owner:
			continue
		var target_cell: int = _find_board_cell(
			state,
			StringName(record.get("instance_id", &""))
		)
		if (
			target_cell >= 0
			and Rules.is_target_in_attack_range(
				state.board,
				source_cell,
				target_cell,
				{"reason": &"after_attack_reaction"}
			)
		):
			return true
	return false


static func _find_board_cell(state: StateData, instance_id: StringName) -> int:
	if instance_id == &"":
		return -1
	for cell: int in range(state.board.size()):
		var slot_value: Variant = state.board[cell]
		if slot_value == null:
			continue
		var card: Dictionary = (slot_value as Dictionary).get("card", {})
		if StringName(card.get("instance_id", &"")) == instance_id:
			return cell
	return -1


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
