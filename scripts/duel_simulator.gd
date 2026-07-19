class_name DuelSimulator
extends RefCounted

const Rules = preload("res://scripts/duel_rules.gd")
const StateData = preload("res://scripts/duel_state.gd")
const MoveData = preload("res://scripts/duel_move.gd")


static func get_legal_moves(state: StateData) -> Array[MoveData]:
	var moves: Array[MoveData] = []
	if state == null or state.board.size() != 9:
		return moves
	var hand: Array = state.get_hand(state.active_player)
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
		}

	var next_state: StateData = state.duplicate_state()
	var moving_owner: int = next_state.active_player
	var hand: Array = next_state.get_hand(moving_owner)
	var card: Dictionary = (hand[move.hand_index] as Dictionary).duplicate(true)
	hand.remove_at(move.hand_index)
	var captures: Array[int] = Rules.place_card(next_state.board, move.cell_index, card, moving_owner)
	next_state.active_player = other_owner(moving_owner)
	next_state.turn_count += 1
	next_state.state_version += 1
	return {
		"valid": true,
		"state": next_state,
		"captures": captures,
	}


static func choose_greedy_move(state: StateData) -> MoveData:
	if state == null:
		return MoveData.new()
	var choice: Vector2i = Rules.choose_ai_move(
		state.board,
		state.get_hand(state.active_player),
		state.active_player
	)
	return MoveData.new(choice.x, choice.y)


static func is_terminal(state: StateData) -> bool:
	if state == null:
		return true
	return (
		Rules.is_board_full(state.board)
		or state.turn_count >= state.max_turns
		or get_legal_moves(state).is_empty()
	)


static func score_difference(state: StateData, owner_id: int) -> int:
	var opponent_id: int = other_owner(owner_id)
	return Rules.count_owned(state.board, owner_id) - Rules.count_owned(state.board, opponent_id)


static func other_owner(owner_id: int) -> int:
	return Rules.OPPONENT_OWNER if owner_id == Rules.PLAYER_OWNER else Rules.PLAYER_OWNER
