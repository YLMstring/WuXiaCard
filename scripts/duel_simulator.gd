class_name DuelSimulator
extends RefCounted

const ACTIVATE_KI_COST: int = 1

const ActionData = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Effects = preload("res://scripts/duel_effects.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const StateData = preload("res://scripts/duel_state.gd")
const Targeting = preload("res://scripts/duel_targeting.gd")


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
		var source_slot: Variant = state.board[source_cell]
		if source_slot == null or int((source_slot as Dictionary).get("owner", 0)) != owner_id:
			continue
		var source_card: Dictionary = (source_slot as Dictionary).get("card", {})
		if int(source_card.get("ki", 0)) < ACTIVATE_KI_COST:
			continue
		var effect: Dictionary = Effects.get_activate_effect(source_card)
		if effect.is_empty():
			continue
		var ability_id := StringName(effect.get("id", &""))
		for target: Dictionary in Targeting.get_valid_targets(state, owner_id, source_cell, effect):
			actions.append(ActionData.make_activate(
				source_cell,
				StringName(source_card.get("instance_id", &"")),
				ability_id,
				StringName(target.get("kind", &"")),
				int(target.get("index", -1))
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
		if action_score > best_score or (
			action_score == best_score and _is_preferred_tie(state, action, best_action)
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
	if action.source_zone != ActionData.SOURCE_HAND or action.target_kind != ActionData.TARGET_BOARD_CELL:
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
	var source_slot: Variant = state.board[action.source_index]
	if source_slot == null or int((source_slot as Dictionary).get("owner", 0)) != state.active_player:
		return false
	var card: Dictionary = (source_slot as Dictionary).get("card", {})
	if not _matches_instance(card, action.source_instance_id) or int(card.get("ki", 0)) < ACTIVATE_KI_COST:
		return false
	var effect: Dictionary = Effects.get_activate_effect(card)
	if effect.is_empty() or StringName(effect.get("id", &"")) != action.ability_id:
		return false
	return Targeting.is_target_valid(
		state,
		state.active_player,
		action.source_index,
		effect,
		action.target_kind,
		action.target_index
	)


static func _apply_play_action(state: StateData, action: ActionData) -> Dictionary:
	var next_state: StateData = state.duplicate_state()
	var moving_owner: int = next_state.active_player
	var hand: Array = next_state.get_hand(moving_owner)
	var card: Dictionary = (hand[action.source_index] as Dictionary).duplicate(true)
	hand.remove_at(action.source_index)
	_normalize_runtime_card(card, moving_owner, next_state.turn_count, action.source_index)
	next_state.board[action.target_index] = {
		"card": card,
		"owner": moving_owner,
	}
	var events: Array[Dictionary] = [{
		"type": &"card_placed",
		"source_cell": action.target_index,
		"target_cell": action.target_index,
		"owner_id": moving_owner,
		"instance_id": StringName(card.get("instance_id", &"")),
	}]
	events.append_array(Effects.resolve_on_play_effects(next_state, action.target_index, moving_owner))
	var attack_result: Dictionary = _resolve_attacks(next_state, action.target_index, moving_owner)
	events.append_array(attack_result["events"] as Array)
	_finish_turn(next_state, moving_owner)
	return {
		"valid": true,
		"state": next_state,
		"captures": attack_result["captures"],
		"exiles": attack_result["exiles"],
		"events": events,
	}


static func _apply_activate_action(state: StateData, action: ActionData) -> Dictionary:
	var next_state: StateData = state.duplicate_state()
	var moving_owner: int = next_state.active_player
	var source_slot: Dictionary = next_state.board[action.source_index]
	var card: Dictionary = source_slot.get("card", {})
	var previous_ki: int = int(card.get("ki", 0))
	card["ki"] = previous_ki - ACTIVATE_KI_COST
	next_state.board[action.source_index] = null
	next_state.board[action.target_index] = source_slot
	var instance_id := StringName(card.get("instance_id", &""))
	var events: Array[Dictionary] = [
		{
			"type": &"ability_activated",
			"source_cell": action.source_index,
			"target_cell": action.target_index,
			"owner_id": moving_owner,
			"instance_id": instance_id,
			"effect_id": action.ability_id,
		},
		{
			"type": &"ki_changed",
			"source_cell": action.source_index,
			"target_cell": action.target_index,
			"owner_id": moving_owner,
			"instance_id": instance_id,
			"previous_ki": previous_ki,
			"ki": int(card["ki"]),
		},
		{
			"type": &"card_moved",
			"source_cell": action.source_index,
			"target_cell": action.target_index,
			"owner_id": moving_owner,
			"instance_id": instance_id,
		},
	]
	var attack_result: Dictionary = _resolve_attacks(next_state, action.target_index, moving_owner)
	events.append_array(attack_result["events"] as Array)
	_finish_turn(next_state, moving_owner)
	return {
		"valid": true,
		"state": next_state,
		"captures": attack_result["captures"],
		"exiles": attack_result["exiles"],
		"events": events,
	}


static func _resolve_attacks(state: StateData, source_cell: int, owner_id: int) -> Dictionary:
	var captures: Array[int] = []
	var exiles: Array[int] = []
	var events: Array[Dictionary] = []
	var would_flip: Array[int] = Rules.get_would_flip_indices(state.board, source_cell)
	for target_cell: int in would_flip:
		var resolution_events: Array[Dictionary] = Effects.resolve_flip_attempt(
			state,
			source_cell,
			target_cell,
			owner_id
		)
		for event: Dictionary in resolution_events:
			var event_type := StringName(event.get("type", &""))
			if event_type == &"card_flipped":
				captures.append(target_cell)
			elif event_type == &"card_exiled":
				exiles.append(target_cell)
		events.append_array(resolution_events)
	return {"captures": captures, "exiles": exiles, "events": events}


static func _finish_turn(state: StateData, moving_owner: int) -> void:
	state.turn_count += 1
	state.state_version += 1
	state.active_player = _get_next_active_owner(state, moving_owner)


static func _normalize_runtime_card(
	card: Dictionary,
	owner_id: int,
	turn_count: int,
	hand_index: int
) -> void:
	if not card.has("card_id"):
		card["card_id"] = StringName(String(card.get("name", "card")).to_snake_case())
	if not card.has("instance_id") or StringName(card.get("instance_id", &"")) == &"":
		card["instance_id"] = StringName("fixture_%d_%d_%d" % [owner_id, turn_count, hand_index])
	if int(card.get("original_owner", 0)) == 0:
		card["original_owner"] = owner_id
	if not card.has("ki"):
		card["ki"] = 0
	if not card.has("active_effects"):
		card["active_effects"] = []


static func _matches_instance(card: Dictionary, expected_instance_id: StringName) -> bool:
	return expected_instance_id == &"" or StringName(card.get("instance_id", &"")) == expected_instance_id


static func _is_preferred_tie(state: StateData, candidate: ActionData, incumbent: ActionData) -> bool:
	if candidate.action_type != incumbent.action_type:
		return candidate.action_type == ActionData.TYPE_PLAY
	if candidate.action_type == ActionData.TYPE_PLAY:
		var hand: Array = state.get_hand(state.active_player)
		var candidate_boundary: int = Rules.get_boundary_power(hand[candidate.source_index], candidate.target_index)
		var incumbent_boundary: int = Rules.get_boundary_power(hand[incumbent.source_index], incumbent.target_index)
		if candidate_boundary != incumbent_boundary:
			return candidate_boundary > incumbent_boundary
	if candidate.source_index != incumbent.source_index:
		return candidate.source_index < incumbent.source_index
	return candidate.target_index < incumbent.target_index


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
