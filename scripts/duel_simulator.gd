class_name DuelSimulator
extends RefCounted

const Rules = preload("res://scripts/duel_rules.gd")
const Effects = preload("res://scripts/duel_effects.gd")
const StateData = preload("res://scripts/duel_state.gd")
const MoveData = preload("res://scripts/duel_move.gd")


static func get_legal_moves(state: StateData) -> Array[MoveData]:
	if state == null:
		return []
	return get_legal_moves_for_owner(state, state.active_player)


static func get_legal_moves_for_owner(state: StateData, owner_id: int) -> Array[MoveData]:
	var moves: Array[MoveData] = []
	if state == null or state.board.size() != 9:
		return moves
	var hand: Array = state.get_hand(owner_id)
	for hand_index: int in range(hand.size()):
		for cell_index: int in range(9):
			if Rules.can_place(state.board, cell_index):
				moves.append(MoveData.new(hand_index, cell_index))
	return moves


static func is_move_legal(state: StateData, move: MoveData) -> bool:
	if state == null or move == null:
		return false
	var hand: Array = state.get_hand(state.active_player)
	return (
		move.hand_index >= 0
		and move.hand_index < hand.size()
		and Rules.can_place(state.board, move.cell_index)
	)


static func apply_move(state: StateData, move: MoveData) -> Dictionary:
	if not is_move_legal(state, move):
		return {
			"valid": false,
			"state": state,
			"captures": [],
			"exiles": [],
			"events": [],
		}

	var next_state: StateData = state.duplicate_state()
	var moving_owner: int = next_state.active_player
	var hand: Array = next_state.get_hand(moving_owner)
	var card: Dictionary = (hand[move.hand_index] as Dictionary).duplicate(true)
	hand.remove_at(move.hand_index)
	_normalize_runtime_card(card, moving_owner, next_state.turn_count, move.hand_index)
	next_state.board[move.cell_index] = {
		"card": card,
		"owner": moving_owner,
	}
	var events: Array[Dictionary] = [
		{
			"type": &"card_placed",
			"source_cell": move.cell_index,
			"target_cell": move.cell_index,
			"owner_id": moving_owner,
			"instance_id": StringName(card.get("instance_id", &"")),
		},
	]
	var captures: Array[int] = []
	var exiles: Array[int] = []
	var would_flip: Array[int] = Rules.get_would_flip_indices(next_state.board, move.cell_index)
	for target_cell: int in would_flip:
		var resolution_events: Array[Dictionary] = Effects.resolve_flip_attempt(
			next_state,
			move.cell_index,
			target_cell,
			moving_owner
		)
		for event: Dictionary in resolution_events:
			var event_type := StringName(event.get("type", &""))
			if event_type == &"card_flipped":
				captures.append(target_cell)
			elif event_type == &"card_exiled":
				exiles.append(target_cell)
		events.append_array(resolution_events)
	next_state.turn_count += 1
	next_state.state_version += 1
	next_state.active_player = _get_next_active_owner(next_state, moving_owner)
	return {
		"valid": true,
		"state": next_state,
		"captures": captures,
		"exiles": exiles,
		"events": events,
	}


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
	if not card.has("active_effects"):
		card["active_effects"] = []


static func choose_greedy_move(state: StateData) -> MoveData:
	if state == null:
		return MoveData.new()
	var legal_moves: Array[MoveData] = get_legal_moves(state)
	if legal_moves.is_empty():
		return MoveData.new()
	var moving_owner: int = state.active_player
	var hand: Array = state.get_hand(moving_owner)
	var best_move: MoveData = legal_moves[0]
	var best_score: int = -1_000_000_000
	var best_boundary_power: int = -1
	for move: MoveData in legal_moves:
		var transition: Dictionary = apply_move(state, move)
		var next_state: StateData = transition["state"] as StateData
		var move_score: int = score_difference(next_state, moving_owner)
		var card: Dictionary = hand[move.hand_index]
		var boundary_power: int = Rules.get_boundary_power(card, move.cell_index)
		var is_better: bool = move_score > best_score
		if move_score == best_score:
			is_better = boundary_power > best_boundary_power
		if move_score == best_score and boundary_power == best_boundary_power:
			is_better = move.hand_index < best_move.hand_index
		if (
			move_score == best_score
			and boundary_power == best_boundary_power
			and move.hand_index == best_move.hand_index
		):
			is_better = move.cell_index < best_move.cell_index
		if is_better:
			best_move = move
			best_score = move_score
			best_boundary_power = boundary_power
	return best_move.duplicate_move()


static func is_terminal(state: StateData) -> bool:
	if state == null:
		return true
	if state.turn_count >= state.max_turns:
		return true
	if not state.effect_queue.is_empty():
		return false
	return (
		get_legal_moves_for_owner(state, Rules.PLAYER_OWNER).is_empty()
		and get_legal_moves_for_owner(state, Rules.OPPONENT_OWNER).is_empty()
	)


static func score_difference(state: StateData, owner_id: int) -> int:
	var opponent_id: int = other_owner(owner_id)
	return Rules.count_owned(state.board, owner_id) - Rules.count_owned(state.board, opponent_id)


static func other_owner(owner_id: int) -> int:
	return Rules.OPPONENT_OWNER if owner_id == Rules.PLAYER_OWNER else Rules.PLAYER_OWNER


static func _get_next_active_owner(state: StateData, moving_owner: int) -> int:
	var preferred_owner: int = other_owner(moving_owner)
	if not get_legal_moves_for_owner(state, preferred_owner).is_empty():
		return preferred_owner
	if not get_legal_moves_for_owner(state, moving_owner).is_empty():
		return moving_owner
	return preferred_owner
