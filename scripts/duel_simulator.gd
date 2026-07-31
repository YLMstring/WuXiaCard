class_name DuelSimulator
extends RefCounted

const ActionData = preload("res://scripts/duel_action.gd")
const Abilities = preload("res://scripts/duel_abilities.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Executor = preload("res://scripts/duel_ability_executor.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const StateData = preload("res://scripts/duel_state.gd")
const Targeting = preload("res://scripts/duel_targeting.gd")
const Triggers = preload("res://scripts/duel_triggers.gd")


static func get_legal_actions(state: StateData) -> Array[ActionData]:
	if state == null:
		return []
	return get_legal_actions_for_owner(state, state.active_player)


static func get_legal_actions_for_owner(state: StateData, owner_id: int) -> Array[ActionData]:
	var actions: Array[ActionData] = []
	if state == null or state.board.size() != 9:
		return actions
	var hand: Array = state.get_hand(owner_id)
	for hand_index: int in range(hand.size()):
		var card: Dictionary = hand[hand_index]
		var instance_id := StringName(card.get("instance_id", &""))
		for cell_index: int in range(9):
			if Rules.can_place(state.board, cell_index):
				actions.append(ActionData.make_play(hand_index, cell_index, instance_id))
	for source_cell: int in range(state.board.size()):
		var source_slot_value: Variant = state.board[source_cell]
		if (
			source_slot_value == null
			or int((source_slot_value as Dictionary).get("owner", 0)) != owner_id
		):
			continue
		var source_card: Dictionary = (source_slot_value as Dictionary).get("card", {})
		var source_instance_id := StringName(source_card.get("instance_id", &""))
		var activate_abilities: Array[Dictionary] = Abilities.get_activate_abilities(source_card)
		for activation_index: int in range(activate_abilities.size()):
			var activation: Dictionary = activate_abilities[activation_index].get(
				"activation",
				{}
			) as Dictionary
			if not Executor.can_pay_costs(
				state,
				source_cell,
				source_instance_id,
				activation.get("costs", []) as Array
			):
				continue
			for target: Dictionary in Targeting.get_valid_targets(
				state,
				owner_id,
				source_cell,
				activation
			):
				actions.append(ActionData.make_activate(
					source_cell,
					source_instance_id,
					StringName(target.get("kind", &"")),
					int(target.get("index", -1)),
					activation_index
				))
	return actions


static func is_action_legal(state: StateData, action: ActionData) -> bool:
	if state == null or action == null:
		return false
	if action.action_type == ActionData.TYPE_PLAY:
		return _is_play_action_legal(state, action)
	if action.action_type == ActionData.TYPE_ACTIVATE:
		return _is_activate_action_legal(state, action)
	return false


static func apply_action(state: StateData, action: ActionData) -> Dictionary:
	if not is_action_legal(state, action):
		return _invalid_transition(state)
	if action.action_type == ActionData.TYPE_PLAY:
		return _apply_play_action(state, action)
	return _apply_activate_action(state, action)


static func choose_greedy_action(state: StateData) -> ActionData:
	if state == null:
		return ActionData.new()
	var legal_actions: Array[ActionData] = get_legal_actions(state)
	if legal_actions.is_empty():
		return ActionData.new()
	var moving_owner: int = state.active_player
	var best_action: ActionData = legal_actions[0]
	var best_score: int = -1_000_000_000
	for action: ActionData in legal_actions:
		var transition: Dictionary = apply_action(state, action)
		var next_state: StateData = transition["state"] as StateData
		var action_score: int = score_difference(next_state, moving_owner)
		if (
			action_score > best_score
			or action_score == best_score and _is_preferred_tie(state, action, best_action)
		):
			best_action = action
			best_score = action_score
	return best_action.duplicate_action()


static func is_terminal(state: StateData) -> bool:
	if state == null:
		return true
	if state.turn_count >= state.max_turns:
		return true
	if not state.effect_queue.is_empty():
		return false
	return (
		get_legal_actions_for_owner(state, Rules.PLAYER_OWNER).is_empty()
		and get_legal_actions_for_owner(state, Rules.OPPONENT_OWNER).is_empty()
	)


static func score_difference(state: StateData, owner_id: int) -> int:
	var opponent_id: int = other_owner(owner_id)
	return Rules.count_owned(state.board, owner_id) - Rules.count_owned(state.board, opponent_id)


static func other_owner(owner_id: int) -> int:
	return Rules.OPPONENT_OWNER if owner_id == Rules.PLAYER_OWNER else Rules.PLAYER_OWNER


static func _is_play_action_legal(state: StateData, action: ActionData) -> bool:
	if (
		action.source_zone != ActionData.SOURCE_HAND
		or action.target_kind != ActionData.TARGET_BOARD_CELL
	):
		return false
	var hand: Array = state.get_hand(state.active_player)
	if action.source_index < 0 or action.source_index >= hand.size():
		return false
	var card: Dictionary = hand[action.source_index]
	return (
		_matches_instance(card, action.source_instance_id)
		and Rules.can_place(state.board, action.target_index)
	)


static func _is_activate_action_legal(state: StateData, action: ActionData) -> bool:
	if action.source_zone != ActionData.SOURCE_BOARD:
		return false
	if action.source_index < 0 or action.source_index >= state.board.size():
		return false
	var source_slot_value: Variant = state.board[action.source_index]
	if (
		source_slot_value == null
		or int((source_slot_value as Dictionary).get("owner", 0)) != state.active_player
	):
		return false
	var card: Dictionary = (source_slot_value as Dictionary).get("card", {})
	if not _matches_instance(card, action.source_instance_id):
		return false
	var activation: Dictionary = Abilities.get_activation(card, action.activation_index)
	if activation.is_empty():
		return false
	if not Executor.can_pay_costs(
		state,
		action.source_index,
		action.source_instance_id,
		activation.get("costs", []) as Array
	):
		return false
	return Targeting.is_target_valid(
		state,
		state.active_player,
		action.source_index,
		activation,
		action.target_kind,
		action.target_index
	)


static func _apply_play_action(state: StateData, action: ActionData) -> Dictionary:
	var next_state: StateData = state.duplicate_state()
	var summoning_owner: int = next_state.active_player
	var hand: Array = next_state.get_hand(summoning_owner)
	var card: Dictionary = (hand[action.source_index] as Dictionary).duplicate(true)
	hand.remove_at(action.source_index)
	_normalize_runtime_card(card, summoning_owner, next_state.turn_count, action.source_index)
	var instance_id := StringName(card.get("instance_id", &""))
	next_state.board[action.target_index] = {
		"card": card,
		"owner": summoning_owner,
	}
	var events: Array[Dictionary] = [{
		"type": &"card_placed",
		"source_cell": action.target_index,
		"target_cell": action.target_index,
		"owner_id": summoning_owner,
		"instance_id": instance_id,
	}]
	var captures: Array[int] = []
	var exiles: Array[int] = []
	var summon_context: Dictionary = {
		"trigger_cell": action.target_index,
		"trigger_instance_id": instance_id,
		"trigger_owner_id": summoning_owner,
		"summon_reason": &"hand_play",
	}
	var summon_result: Dictionary = _resolve_trigger_event(
		next_state,
		Catalog.TRIGGER_CARD_SUMMONED,
		summon_context
	)
	_merge_resolution(captures, exiles, events, summon_result)

	if _card_instance_at(next_state, action.target_index, instance_id):
		var current_slot: Dictionary = next_state.board[action.target_index]
		var after_context: Dictionary = summon_context.duplicate(true)
		after_context["trigger_owner_id"] = int(current_slot.get("owner", 0))
		var after_result: Dictionary = _resolve_trigger_event(
			next_state,
			Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			after_context
		)
		_merge_resolution(captures, exiles, events, after_result)

	if _owned_card_instance_at(
		next_state,
		action.target_index,
		instance_id,
		summoning_owner
	):
		var attack_result: Dictionary = _resolve_standard_attacks(
			next_state,
			action.target_index,
			instance_id,
			&"summon_standard_attack"
		)
		_merge_resolution(captures, exiles, events, attack_result)
	events.append_array(_finish_turn(next_state, summoning_owner))
	return {
		"valid": true,
		"state": next_state,
		"captures": captures,
		"exiles": exiles,
		"events": events,
	}


static func _apply_activate_action(state: StateData, action: ActionData) -> Dictionary:
	var next_state: StateData = state.duplicate_state()
	var moving_owner: int = next_state.active_player
	var source_slot: Dictionary = next_state.board[action.source_index]
	var card: Dictionary = source_slot.get("card", {})
	var activation: Dictionary = Abilities.get_activation(card, action.activation_index)
	var activation_result: Dictionary = Executor.execute_activation(
		next_state,
		action.source_index,
		action.source_instance_id,
		activation,
		action.target_kind,
		action.target_index
	)
	if not bool(activation_result.get("valid", false)):
		return _invalid_transition(state)
	var captures: Array[int] = []
	var exiles: Array[int] = []
	var events: Array[Dictionary] = activation_result.get("events", [])
	for request_value: Variant in activation_result.get("attack_requests", []):
		if not request_value is Dictionary:
			continue
		var request_result: Dictionary = _resolve_attack_request(next_state, request_value)
		_merge_resolution(captures, exiles, events, request_result)
	events.append_array(_finish_turn(next_state, moving_owner))
	return {
		"valid": true,
		"state": next_state,
		"captures": captures,
		"exiles": exiles,
		"events": events,
	}


static func _resolve_standard_attacks(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	reason: StringName
) -> Dictionary:
	var result: Dictionary = _empty_resolution()
	if not _card_instance_at(state, source_cell, source_instance_id):
		return result
	var target_cells: Array[int] = Rules.get_would_flip_indices(state.board, source_cell)
	for target_cell: int in target_cells:
		if not _card_instance_at(state, source_cell, source_instance_id):
			break
		var target_slot_value: Variant = state.board[target_cell]
		if target_slot_value == null:
			continue
		var target_card: Dictionary = (target_slot_value as Dictionary).get("card", {})
		var target_result: Dictionary = _resolve_attack_target(
			state,
			source_cell,
			source_instance_id,
			target_cell,
			StringName(target_card.get("instance_id", &"")),
			reason
		)
		_merge_resolution(
			result["captures"],
			result["exiles"],
			result["events"],
			target_result
		)
	return result


static func _resolve_attack_target(
	state: StateData,
	attacker_cell: int,
	attacker_instance_id: StringName,
	attacked_cell: int,
	attacked_instance_id: StringName,
	reason: StringName
) -> Dictionary:
	var result: Dictionary = _empty_resolution()
	if not _attack_is_valid(
		state,
		attacker_cell,
		attacker_instance_id,
		attacked_cell,
		attacked_instance_id
	):
		return result
	var attacker_slot: Dictionary = state.board[attacker_cell]
	var attacked_slot: Dictionary = state.board[attacked_cell]
	var attack_context: Dictionary = {
		"attacker_cell": attacker_cell,
		"attacker_instance_id": attacker_instance_id,
		"attacker_owner_id": int(attacker_slot.get("owner", 0)),
		"attacked_cell": attacked_cell,
		"attacked_instance_id": attacked_instance_id,
		"attacked_owner_id": int(attacked_slot.get("owner", 0)),
		"attack_reason": reason,
	}
	result["events"].append({
		"type": &"attack_started",
		"source_cell": attacker_cell,
		"source_instance_id": attacker_instance_id,
		"source_owner_id": int(attacker_slot.get("owner", 0)),
		"target_cell": attacked_cell,
		"target_instance_id": attacked_instance_id,
		"target_owner_id": int(attacked_slot.get("owner", 0)),
		"attack_reason": reason,
	})
	var before_result: Dictionary = _resolve_trigger_event(
		state,
		Catalog.CARD_BE_ATTACKED,
		attack_context
	)
	_merge_resolution(
		result["captures"],
		result["exiles"],
		result["events"],
		before_result
	)
	if not _attack_is_valid(
		state,
		attacker_cell,
		attacker_instance_id,
		attacked_cell,
		attacked_instance_id
	):
		return result
	attacker_slot = state.board[attacker_cell]
	var attacker_owner: int = int(attacker_slot.get("owner", 0))
	var flip_events: Array[Dictionary] = Executor.resolve_normal_flip(
		state,
		attacker_cell,
		attacker_instance_id,
		attacked_cell,
		attacked_instance_id,
		attacker_owner
	)
	if flip_events.is_empty():
		return result
	result["captures"].append(attacked_cell)
	result["events"].append_array(flip_events)
	var after_result: Dictionary = _resolve_trigger_event(
		state,
		Catalog.CARD_AFTER_FLIPPED,
		attack_context
	)
	_merge_resolution(
		result["captures"],
		result["exiles"],
		result["events"],
		after_result
	)
	return result


static func _resolve_trigger_event(
	state: StateData,
	event_id: StringName,
	context: Dictionary
) -> Dictionary:
	var result: Dictionary = _empty_resolution()
	result["extra_turn_requests"] = []
	var groups: Array[Dictionary] = Triggers.discover(state, event_id, context)
	for group: Dictionary in groups:
		var group_result: Dictionary = Triggers.resolve_group(state, group)
		var group_events: Array = group_result.get("events", [])
		_record_direct_resolution_events(result, group_events)
		result["events"].append_array(group_events)
		result["extra_turn_requests"].append_array(
			group_result.get("extra_turn_requests", []) as Array
		)
		for request_value: Variant in group_result.get("attack_requests", []):
			if not request_value is Dictionary:
				continue
			var request_result: Dictionary = _resolve_attack_request(state, request_value)
			_merge_resolution(
				result["captures"],
				result["exiles"],
				result["events"],
				request_result
			)
	return result


static func _record_direct_resolution_events(result: Dictionary, events: Array) -> void:
	for event_value: Variant in events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		var event_type := StringName(event.get("type", &""))
		var target_cell: int = int(event.get("target_cell", -1))
		if event_type == &"card_exiled" and target_cell not in result["exiles"]:
			result["exiles"].append(target_cell)
		elif event_type == &"card_flipped" and target_cell not in result["captures"]:
			result["captures"].append(target_cell)


static func _resolve_attack_request(state: StateData, request: Dictionary) -> Dictionary:
	var source_cell: int = int(request.get("source_cell", -1))
	var source_instance_id := StringName(request.get("source_instance_id", &""))
	if not _owned_card_instance_at(
		state,
		source_cell,
		source_instance_id,
		int(request.get("source_owner_id", 0))
	):
		return _empty_resolution()
	var mode := StringName(request.get("mode", &""))
	if mode == &"standard":
		return _resolve_standard_attacks(
			state,
			source_cell,
			source_instance_id,
			StringName(request.get("reason", &"ability_standard_attack"))
		)
	if mode != &"targeted":
		return _empty_resolution()
	var target_cell: int = int(request.get("target_cell", -1))
	var target_instance_id := StringName(request.get("target_instance_id", &""))
	if not _owned_card_instance_at(
		state,
		target_cell,
		target_instance_id,
		int(request.get("target_owner_id", 0))
	):
		return _empty_resolution()
	return _resolve_attack_target(
		state,
		source_cell,
		source_instance_id,
		target_cell,
		target_instance_id,
		StringName(request.get("reason", &"ability_targeted_attack"))
	)


static func _attack_is_valid(
	state: StateData,
	attacker_cell: int,
	attacker_instance_id: StringName,
	attacked_cell: int,
	attacked_instance_id: StringName
) -> bool:
	if (
		not _card_instance_at(state, attacker_cell, attacker_instance_id)
		or not _card_instance_at(state, attacked_cell, attacked_instance_id)
	):
		return false
	return Rules.can_attack_target(
		state.board,
		attacker_cell,
		attacked_cell,
		{"reason": &"attack_resolution"}
	)


static func _finish_turn(state: StateData, moving_owner: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var end_result: Dictionary = _resolve_trigger_event(
		state,
		Catalog.TRIGGER_END_OWNER_TURN,
		{"turn_owner_id": moving_owner}
	)
	events.append_array(end_result.get("events", []) as Array)
	var extra_turn_requests: Array = end_result.get("extra_turn_requests", [])
	var extra_turn_granted: bool = not extra_turn_requests.is_empty()
	if extra_turn_granted:
		var source_instance_ids: Array[StringName] = []
		for request_value: Variant in extra_turn_requests:
			if not request_value is Dictionary:
				continue
			var request: Dictionary = request_value
			if int(request.get("owner_id", 0)) == moving_owner:
				source_instance_ids.append(
					StringName(request.get("source_instance_id", &""))
				)
		extra_turn_granted = not source_instance_ids.is_empty()
		if extra_turn_granted:
			events.append({
				"type": &"extra_turn_granted",
				"owner_id": moving_owner,
				"request_count": source_instance_ids.size(),
				"source_instance_ids": source_instance_ids,
			})
	state.turn_count += 1
	state.state_version += 1
	if extra_turn_granted and not get_legal_actions_for_owner(state, moving_owner).is_empty():
		state.active_player = moving_owner
	else:
		state.active_player = _get_next_active_owner(state, moving_owner)
	var start_result: Dictionary = _resolve_trigger_event(
		state,
		Catalog.TRIGGER_START_OWNER_TURN,
		{"turn_owner_id": state.active_player}
	)
	events.append_array(start_result.get("events", []) as Array)
	return events


static func _normalize_runtime_card(
	card: Dictionary,
	owner_id: int,
	turn_count: int,
	hand_index: int
) -> void:
	if not card.has("card_id"):
		card["card_id"] = StringName(String(card.get("glyph", "card")).to_snake_case())
	if not card.has("instance_id") or StringName(card.get("instance_id", &"")) == &"":
		card["instance_id"] = StringName(
			"fixture_%d_%d_%d" % [owner_id, turn_count, hand_index]
		)
	if int(card.get("original_owner", 0)) == 0:
		card["original_owner"] = owner_id
	if not card.has("ki"):
		card["ki"] = 0
	if not card.has("active_abilities"):
		card["active_abilities"] = []


static func _card_instance_at(
	state: StateData,
	cell: int,
	instance_id: StringName
) -> bool:
	if state == null or cell < 0 or cell >= state.board.size():
		return false
	var slot_value: Variant = state.board[cell]
	if slot_value == null:
		return false
	var card: Dictionary = (slot_value as Dictionary).get("card", {})
	return StringName(card.get("instance_id", &"")) == instance_id


static func _owned_card_instance_at(
	state: StateData,
	cell: int,
	instance_id: StringName,
	owner_id: int
) -> bool:
	if not _card_instance_at(state, cell, instance_id):
		return false
	return int((state.board[cell] as Dictionary).get("owner", 0)) == owner_id


static func _matches_instance(card: Dictionary, expected_instance_id: StringName) -> bool:
	return (
		expected_instance_id == &""
		or StringName(card.get("instance_id", &"")) == expected_instance_id
	)


static func _is_preferred_tie(
	state: StateData,
	candidate: ActionData,
	incumbent: ActionData
) -> bool:
	if candidate.action_type != incumbent.action_type:
		return candidate.action_type == ActionData.TYPE_PLAY
	if candidate.action_type == ActionData.TYPE_PLAY:
		var hand: Array = state.get_hand(state.active_player)
		var candidate_boundary: int = Rules.get_boundary_power(
			hand[candidate.source_index],
			candidate.target_index
		)
		var incumbent_boundary: int = Rules.get_boundary_power(
			hand[incumbent.source_index],
			incumbent.target_index
		)
		if candidate_boundary != incumbent_boundary:
			return candidate_boundary > incumbent_boundary
	if candidate.source_index != incumbent.source_index:
		return candidate.source_index < incumbent.source_index
	return candidate.target_index < incumbent.target_index


static func _merge_resolution(
	captures: Array,
	exiles: Array,
	events: Array,
	addition: Dictionary
) -> void:
	captures.append_array(addition.get("captures", []) as Array)
	exiles.append_array(addition.get("exiles", []) as Array)
	events.append_array(addition.get("events", []) as Array)


static func _empty_resolution() -> Dictionary:
	return {
		"captures": [],
		"exiles": [],
		"events": [],
	}


static func _invalid_transition(state: StateData) -> Dictionary:
	return {
		"valid": false,
		"state": state,
		"captures": [],
		"exiles": [],
		"events": [],
	}


static func _get_next_active_owner(state: StateData, moving_owner: int) -> int:
	var preferred_owner: int = other_owner(moving_owner)
	if not get_legal_actions_for_owner(state, preferred_owner).is_empty():
		return preferred_owner
	if not get_legal_actions_for_owner(state, moving_owner).is_empty():
		return moving_owner
	return preferred_owner
