class_name DuelAbilityExecutor
extends RefCounted

const MAX_HAND_SIZE: int = 5

const Abilities = preload("res://scripts/duel_abilities.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Selector = preload("res://scripts/duel_card_selector.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const StateData = preload("res://scripts/duel_state.gd")


static func can_pay_costs(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	costs: Array
) -> bool:
	if state == null:
		return false
	var source_slot: Dictionary = _get_card_slot(state, source_cell, source_instance_id)
	if source_slot.is_empty():
		return false
	var source_card: Dictionary = source_slot.get("card", {})
	var required_ki: int = 0
	for cost_value: Variant in costs:
		if not cost_value is Dictionary:
			return false
		var cost: Dictionary = cost_value
		var cost_type := StringName(cost.get("type", &""))
		if cost_type != Catalog.ACTION_SPEND_KI:
			return false
		var amount: int = int(cost.get("amount", 0))
		if amount <= 0:
			return false
		required_ki += amount
	return int(source_card.get("ki", 0)) >= required_ki


static func execute_activation(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	activation: Dictionary,
	target_kind: StringName,
	target_index: int
) -> Dictionary:
	var empty_result: Dictionary = _empty_result()
	empty_result["valid"] = false
	if state == null:
		return empty_result
	var source_slot: Dictionary = _get_card_slot(state, source_cell, source_instance_id)
	if source_slot.is_empty():
		return empty_result
	var costs: Array = activation.get("costs", [])
	if not can_pay_costs(state, source_cell, source_instance_id, costs):
		return empty_result
	var owner_id: int = int(source_slot.get("owner", 0))
	var context: Dictionary = {
		"target_kind": target_kind,
		"target_index": target_index,
	}
	var events: Array[Dictionary] = [{
		"type": &"ability_activated",
		"source_cell": source_cell,
		"target_cell": target_index,
		"owner_id": owner_id,
		"instance_id": source_instance_id,
	}]
	var cost_result: Dictionary = execute_actions(
		state,
		source_cell,
		source_instance_id,
		owner_id,
		costs,
		context
	)
	events.append_array(cost_result.get("events", []) as Array)
	var action_result: Dictionary = execute_actions(
		state,
		int(cost_result.get("source_cell", source_cell)),
		source_instance_id,
		owner_id,
		activation.get("actions", []) as Array,
		context
	)
	events.append_array(action_result.get("events", []) as Array)
	return {
		"valid": true,
		"events": events,
		"attack_requests": action_result.get("attack_requests", []),
		"extra_turn_requests": action_result.get("extra_turn_requests", []),
		"source_cell": int(action_result.get("source_cell", source_cell)),
		"result": action_result.get("result", Catalog.ACTION_RESULT_APPLIED),
	}


static func execute_actions(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	actions: Array,
	context: Dictionary
) -> Dictionary:
	var result: Dictionary = _empty_result()
	result["source_cell"] = source_cell
	if state == null:
		return result
	var action_context: Dictionary = context.duplicate(true)
	if not action_context.has("ability_source_instance_id"):
		action_context["ability_source_instance_id"] = source_instance_id
		action_context["ability_source_owner_id"] = expected_owner
	var current_source_cell: int = source_cell
	for action_value: Variant in actions:
		if not action_value is Dictionary:
			continue
		var declaration: Dictionary = action_value
		var action_result: Dictionary = _execute_action(
			state,
			current_source_cell,
			source_instance_id,
			expected_owner,
			declaration,
			action_context
		)
		result["events"].append_array(action_result.get("events", []) as Array)
		result["attack_requests"].append_array(action_result.get("attack_requests", []) as Array)
		result["extra_turn_requests"].append_array(action_result.get("extra_turn_requests", []) as Array)
		current_source_cell = int(action_result.get("source_cell", current_source_cell))
		var action_status := StringName(action_result.get("result", Catalog.ACTION_RESULT_NO_EFFECT))
		if action_status == Catalog.ACTION_RESULT_INVALID_CONTEXT:
			result["result"] = Catalog.ACTION_RESULT_INVALID_CONTEXT
			break
		if (
			action_status == Catalog.ACTION_RESULT_NO_EFFECT
			and StringName(declaration.get("on_invalid_context", &"")) == Catalog.STOP_RULE
		):
			result["result"] = Catalog.ACTION_RESULT_INVALID_CONTEXT
			break
		if action_status == Catalog.ACTION_RESULT_APPLIED:
			result["result"] = Catalog.ACTION_RESULT_APPLIED
	result["source_cell"] = current_source_cell
	return result


static func resolve_normal_flip(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	target_cell: int,
	target_instance_id: StringName,
	new_owner: int
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var source_slot: Dictionary = _get_card_slot(state, source_cell, source_instance_id, new_owner)
	var target_slot: Dictionary = _get_card_slot(state, target_cell, target_instance_id)
	if source_slot.is_empty() or target_slot.is_empty():
		return events
	if int(target_slot.get("owner", 0)) == new_owner:
		return events
	var target_card: Dictionary = target_slot.get("card", {})
	target_slot["owner"] = new_owner
	events.append({
		"type": &"card_flipped",
		"source_cell": source_cell,
		"target_cell": target_cell,
		"owner_id": new_owner,
		"instance_id": target_instance_id,
	})
	var removed_count: int = Abilities.remove_non_retained_abilities(target_card)
	for _removed_index: int in range(removed_count):
		events.append({
			"type": &"ability_lost",
			"source_cell": source_cell,
			"target_cell": target_cell,
			"owner_id": new_owner,
			"instance_id": target_instance_id,
		})
	return events


static func _execute_action(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	declaration: Dictionary,
	context: Dictionary
) -> Dictionary:
	var action_type := StringName(declaration.get("type", &""))
	if action_type == Catalog.ACTION_FOR_EACH_SELECTED_CARD:
		return _for_each_selected_card(
			state,
			source_cell,
			declaration,
			context
		)
	if action_type == Catalog.ACTION_DRAW_CARDS:
		return _draw_cards(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			int(declaration.get("amount", 0))
		)
	if action_type == Catalog.ACTION_EXILE_ATTACKED_CARD:
		return _exile_attacked_card(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			context
		)
	if action_type == Catalog.ACTION_ATTACK_TRIGGER_CARD:
		return _request_trigger_attack(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			context
		)
	if action_type == Catalog.ACTION_GAIN_KI:
		return _change_ki(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			int(declaration.get("amount", 0)),
			action_type
		)
	if action_type == Catalog.ACTION_ADD_POWERS:
		return _add_powers(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			int(declaration.get("amount", 0))
		)
	if action_type == Catalog.ACTION_SPEND_KI:
		return _change_ki(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			-int(declaration.get("amount", 0)),
			action_type
		)
	if action_type == Catalog.ACTION_SPEND_ALL_KI:
		return _spend_all_ki(
			state,
			source_cell,
			source_instance_id,
			expected_owner
		)
	if action_type == Catalog.ACTION_REQUEST_EXTRA_TURN:
		return _request_extra_turn(
			state,
			source_cell,
			source_instance_id,
			expected_owner
		)
	if action_type == Catalog.ACTION_MOVE_SELF_TO_TARGET:
		return _move_self(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			context
		)
	if action_type == Catalog.ACTION_SWAP_SELF_WITH_TARGET:
		return _swap_self_with_target(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			context
		)
	if action_type == Catalog.ACTION_STANDARD_ATTACK_WITH_SELF:
		return _request_standard_attack(
			state,
			source_cell,
			source_instance_id,
			expected_owner
		)
	return _no_effect(source_cell)


static func _for_each_selected_card(
	state: StateData,
	source_cell: int,
	declaration: Dictionary,
	context: Dictionary
) -> Dictionary:
	var result: Dictionary = _empty_result()
	result["source_cell"] = source_cell
	var source_instance_id := StringName(context.get("ability_source_instance_id", &""))
	var selector: Dictionary = declaration.get("selector", {})
	var conditions: Array = selector.get("conditions", [])
	var selected_ids: Array[StringName] = Selector.snapshot(
		state,
		selector,
		source_instance_id
	)
	for selected_instance_id: StringName in selected_ids:
		var selected: Dictionary = Selector.revalidate(
			state,
			selected_instance_id,
			source_instance_id,
			conditions
		)
		if selected.is_empty():
			continue
		var selected_cell: int = (
			int(selected.get("index", -1))
			if StringName(selected.get("zone", &"")) == Catalog.CARD_ZONE_BOARD
			else -1
		)
		var nested_result: Dictionary = execute_actions(
			state,
			selected_cell,
			selected_instance_id,
			int(selected.get("owner_id", 0)),
			declaration.get("actions", []) as Array,
			context
		)
		result["events"].append_array(nested_result.get("events", []) as Array)
		result["attack_requests"].append_array(
			nested_result.get("attack_requests", []) as Array
		)
		result["extra_turn_requests"].append_array(
			nested_result.get("extra_turn_requests", []) as Array
		)
		var nested_status := StringName(
			nested_result.get("result", Catalog.ACTION_RESULT_NO_EFFECT)
		)
		if nested_status == Catalog.ACTION_RESULT_INVALID_CONTEXT:
			result["result"] = Catalog.ACTION_RESULT_INVALID_CONTEXT
			return result
		if nested_status == Catalog.ACTION_RESULT_APPLIED:
			result["result"] = Catalog.ACTION_RESULT_APPLIED
	return result


static func _draw_cards(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	requested_count: int
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if source.is_empty() or requested_count <= 0:
		return _no_effect(source_cell)
	var owner_id: int = int(source.get("owner_id", 0))
	var hand: Array = state.get_hand(owner_id)
	var deck: Array = state.decks.get(owner_id, [])
	var actual_count: int = mini(requested_count, mini(MAX_HAND_SIZE - hand.size(), deck.size()))
	var events: Array[Dictionary] = []
	for _draw_index: int in range(maxi(actual_count, 0)):
		var drawn_card: Dictionary = deck.pop_front()
		hand.append(drawn_card)
		events.append({
			"type": &"card_drawn",
			"source_cell": source_cell,
			"owner_id": owner_id,
			"card_id": StringName(drawn_card.get("card_id", &"")),
			"instance_id": StringName(drawn_card.get("instance_id", &"")),
			"logical_hand_index": hand.size() - 1,
		})
	return _applied(source_cell, events) if actual_count > 0 else _no_effect(source_cell)


static func _exile_attacked_card(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	context: Dictionary
) -> Dictionary:
	var source_slot: Dictionary = _get_card_slot(
		state,
		source_cell,
		source_instance_id,
		expected_owner
	)
	var target_cell: int = int(context.get("attacked_cell", -1))
	var target_instance_id := StringName(context.get("attacked_instance_id", &""))
	var target_slot: Dictionary = _get_card_slot(state, target_cell, target_instance_id)
	if source_slot.is_empty() or target_slot.is_empty():
		return _no_effect(source_cell)
	var target_card: Dictionary = target_slot.get("card", {})
	var original_owner: int = int(target_card.get("original_owner", 0))
	if original_owner not in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		original_owner = int(target_slot.get("owner", 0))
	if not state.removed_cards.has(original_owner):
		state.removed_cards[original_owner] = []
	(state.removed_cards[original_owner] as Array).append(target_card)
	state.board[target_cell] = null
	return _applied(source_cell, [{
		"type": &"card_exiled",
		"source_cell": source_cell,
		"target_cell": target_cell,
		"owner_id": int(source_slot.get("owner", 0)),
		"original_owner": original_owner,
		"instance_id": target_instance_id,
	}])


static func _request_trigger_attack(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	context: Dictionary
) -> Dictionary:
	var source_slot: Dictionary = _get_card_slot(
		state,
		source_cell,
		source_instance_id,
		expected_owner
	)
	var target_cell: int = int(context.get("trigger_cell", -1))
	var target_instance_id := StringName(context.get("trigger_instance_id", &""))
	var target_slot: Dictionary = _get_card_slot(state, target_cell, target_instance_id)
	if source_slot.is_empty() or target_slot.is_empty():
		return _no_effect(source_cell)
	if not Rules.can_attack_target(
		state.board,
		source_cell,
		target_cell,
		{"reason": &"card_summoned_reaction", "trigger_context": context}
	):
		return _no_effect(source_cell)
	var result: Dictionary = _applied(source_cell)
	result["attack_requests"].append({
		"mode": &"targeted",
		"source_cell": source_cell,
		"source_instance_id": source_instance_id,
		"source_owner_id": int(source_slot.get("owner", 0)),
		"target_cell": target_cell,
		"target_instance_id": target_instance_id,
		"target_owner_id": int(target_slot.get("owner", 0)),
		"reason": &"card_summoned_reaction",
	})
	return result


static func _change_ki(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	delta: int,
	reason: StringName
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if source.is_empty() or delta == 0:
		return _no_effect(source_cell)
	var card: Dictionary = source.get("card", {})
	var previous_ki: int = int(card.get("ki", 0))
	var resulting_ki: int = previous_ki + delta
	if resulting_ki < 0:
		return _no_effect(source_cell)
	card["ki"] = resulting_ki
	var current_cell: int = _get_location_cell(source)
	return _applied(source_cell, [_make_ki_event(
		current_cell,
		int(source.get("owner_id", 0)),
		source_instance_id,
		previous_ki,
		resulting_ki,
		reason,
		StringName(source.get("zone", &"")),
		int(source.get("index", -1))
	)])


static func _add_powers(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	amount: int
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if source.is_empty() or amount <= 0:
		return _no_effect(source_cell)
	var card: Dictionary = source.get("card", {})
	var previous_powers: Array = (card.get("powers", []) as Array).duplicate()
	if previous_powers.size() != 4:
		return _no_effect(source_cell)
	var resulting_powers: Array = previous_powers.duplicate()
	for power_index: int in range(resulting_powers.size()):
		resulting_powers[power_index] = int(resulting_powers[power_index]) + amount
	card["powers"] = resulting_powers
	var current_cell: int = _get_location_cell(source)
	return _applied(source_cell, [{
		"type": &"powers_changed",
		"source_cell": current_cell,
		"target_cell": current_cell,
		"owner_id": int(source.get("owner_id", 0)),
		"instance_id": source_instance_id,
		"previous_powers": previous_powers,
		"powers": resulting_powers.duplicate(),
		"change_reason": Catalog.ACTION_ADD_POWERS,
		"zone": StringName(source.get("zone", &"")),
		"logical_index": int(source.get("index", -1)),
	}])


static func _spend_all_ki(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if source.is_empty():
		return _no_effect(source_cell)
	var card: Dictionary = source.get("card", {})
	var previous_ki: int = int(card.get("ki", 0))
	if previous_ki <= 0:
		return _no_effect(source_cell)
	card["ki"] = 0
	var current_cell: int = _get_location_cell(source)
	return _applied(source_cell, [_make_ki_event(
		current_cell,
		int(source.get("owner_id", 0)),
		source_instance_id,
		previous_ki,
		0,
		Catalog.ACTION_SPEND_ALL_KI,
		StringName(source.get("zone", &"")),
		int(source.get("index", -1))
	)])


static func _request_extra_turn(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if source.is_empty():
		return _no_effect(source_cell)
	var result: Dictionary = _applied(source_cell)
	result["extra_turn_requests"].append({
		"owner_id": int(source.get("owner_id", 0)),
		"source_cell": _get_location_cell(source),
		"source_instance_id": source_instance_id,
	})
	return result


static func _move_self(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	context: Dictionary
) -> Dictionary:
	var source_slot: Dictionary = _get_card_slot(
		state,
		source_cell,
		source_instance_id,
		expected_owner
	)
	var target_kind := StringName(context.get("target_kind", &""))
	var target_cell: int = int(context.get("target_index", -1))
	if (
		source_slot.is_empty()
		or target_kind != &"board_cell"
		or target_cell < 0
		or target_cell >= state.board.size()
		or state.board[target_cell] != null
		or not _are_adjacent(source_cell, target_cell)
	):
		return _no_effect(source_cell)
	return _move_card_between_cells(
		state,
		source_cell,
		target_cell,
		source_instance_id,
		expected_owner
	)


static func _swap_self_with_target(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	context: Dictionary
) -> Dictionary:
	var source_slot: Dictionary = _get_card_slot(
		state,
		source_cell,
		source_instance_id,
		expected_owner
	)
	var target_kind := StringName(context.get("target_kind", &""))
	var target_cell: int = int(context.get("target_index", -1))
	if (
		source_slot.is_empty()
		or target_kind != &"board_cell"
		or target_cell < 0
		or target_cell >= state.board.size()
		or state.board[target_cell] == null
		or not _are_adjacent(source_cell, target_cell)
	):
		return _no_effect(source_cell)
	var target_slot: Dictionary = state.board[target_cell] as Dictionary
	var target_card: Dictionary = target_slot.get("card", {})
	var target_instance_id := StringName(target_card.get("instance_id", &""))
	var target_owner: int = int(target_slot.get("owner", 0))
	if target_instance_id == &"":
		return _no_effect(source_cell)

	var reserved_target: Dictionary = target_slot
	state.board[target_cell] = null
	var source_move: Dictionary = _move_card_between_cells(
		state,
		source_cell,
		target_cell,
		source_instance_id,
		expected_owner
	)
	if StringName(source_move.get("result", &"")) != Catalog.ACTION_RESULT_APPLIED:
		state.board[target_cell] = reserved_target
		return _no_effect(source_cell)

	var reserved_source: Dictionary = state.board[target_cell] as Dictionary
	state.board[target_cell] = reserved_target
	var target_move: Dictionary = _move_card_between_cells(
		state,
		target_cell,
		source_cell,
		target_instance_id,
		target_owner
	)
	if StringName(target_move.get("result", &"")) != Catalog.ACTION_RESULT_APPLIED:
		state.board[source_cell] = reserved_source
		state.board[target_cell] = reserved_target
		return _no_effect(source_cell)
	state.board[target_cell] = reserved_source

	var events: Array = source_move.get("events", []) as Array
	events.append_array(target_move.get("events", []) as Array)
	return _applied(target_cell, events)


static func _move_card_between_cells(
	state: StateData,
	source_cell: int,
	target_cell: int,
	instance_id: StringName,
	expected_owner: int
) -> Dictionary:
	var source_slot: Dictionary = _get_card_slot(
		state,
		source_cell,
		instance_id,
		expected_owner
	)
	if (
		source_slot.is_empty()
		or target_cell < 0
		or target_cell >= state.board.size()
		or state.board[target_cell] != null
	):
		return _no_effect(source_cell)
	state.board[source_cell] = null
	state.board[target_cell] = source_slot
	return _applied(target_cell, [{
		"type": &"card_moved",
		"source_cell": source_cell,
		"target_cell": target_cell,
		"owner_id": int(source_slot.get("owner", 0)),
		"instance_id": instance_id,
	}])


static func _request_standard_attack(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int
) -> Dictionary:
	var source_slot: Dictionary = _get_card_slot(
		state,
		source_cell,
		source_instance_id,
		expected_owner
	)
	if source_slot.is_empty():
		return _no_effect(source_cell)
	var result: Dictionary = _applied(source_cell)
	result["attack_requests"].append({
		"mode": &"standard",
		"source_cell": source_cell,
		"source_instance_id": source_instance_id,
		"source_owner_id": int(source_slot.get("owner", 0)),
		"reason": &"activated_ability",
	})
	return result


static func _get_card_slot(
	state: StateData,
	cell: int,
	instance_id: StringName,
	expected_owner: int = 0
) -> Dictionary:
	if state == null or cell < 0 or cell >= state.board.size():
		return {}
	var slot_value: Variant = state.board[cell]
	if slot_value == null:
		return {}
	var slot: Dictionary = slot_value
	var card: Dictionary = slot.get("card", {})
	if StringName(card.get("instance_id", &"")) != instance_id:
		return {}
	if expected_owner != 0 and int(slot.get("owner", 0)) != expected_owner:
		return {}
	return slot


static func _get_subject(
	state: StateData,
	instance_id: StringName,
	expected_owner: int
) -> Dictionary:
	var subject: Dictionary = Selector.locate_card(state, instance_id)
	if (
		subject.is_empty()
		or expected_owner != 0
		and int(subject.get("owner_id", 0)) != expected_owner
	):
		return {}
	return subject


static func _get_location_cell(location: Dictionary) -> int:
	if StringName(location.get("zone", &"")) != Catalog.CARD_ZONE_BOARD:
		return -1
	return int(location.get("index", -1))


static func _are_adjacent(first_cell: int, second_cell: int) -> bool:
	for direction: int in range(4):
		if Rules.get_neighbor_index(first_cell, direction) == second_cell:
			return true
	return false


static func _make_ki_event(
	source_cell: int,
	owner_id: int,
	instance_id: StringName,
	previous_ki: int,
	resulting_ki: int,
	action_type: StringName,
	zone: StringName,
	logical_index: int
) -> Dictionary:
	return {
		"type": &"ki_changed",
		"source_cell": source_cell,
		"target_cell": source_cell,
		"owner_id": owner_id,
		"instance_id": instance_id,
		"previous_ki": previous_ki,
		"ki": resulting_ki,
		"change_reason": action_type,
		"zone": zone,
		"logical_index": logical_index,
	}


static func _empty_result() -> Dictionary:
	return {
		"result": Catalog.ACTION_RESULT_NO_EFFECT,
		"events": [],
		"attack_requests": [],
		"extra_turn_requests": [],
		"source_cell": -1,
	}


static func _no_effect(source_cell: int) -> Dictionary:
	var result: Dictionary = _empty_result()
	result["source_cell"] = source_cell
	return result


static func _applied(source_cell: int, events: Array = []) -> Dictionary:
	var result: Dictionary = _empty_result()
	result["result"] = Catalog.ACTION_RESULT_APPLIED
	result["source_cell"] = source_cell
	result["events"] = events
	return result
