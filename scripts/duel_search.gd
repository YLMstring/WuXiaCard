class_name DuelSearch
extends RefCounted

const WIN_SCORE: int = 1_000_000
const INFINITY: int = 1_000_000_000
const StateData = preload("res://scripts/duel_state.gd")
const MoveData = preload("res://scripts/duel_move.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")


static func find_best_move(
	state: StateData,
	max_depth: int,
	root_owner: int = -1
) -> MoveData:
	var legal_moves: Array[MoveData] = Simulator.get_legal_moves(state)
	if legal_moves.is_empty():
		return MoveData.new()
	if root_owner < 0:
		root_owner = state.active_player

	var maximizing: bool = state.active_player == root_owner
	var best_score: int = -INFINITY if maximizing else INFINITY
	var best_move: MoveData = legal_moves[0]
	var alpha: int = -INFINITY
	var beta: int = INFINITY
	for move: MoveData in legal_moves:
		var transition: Dictionary = Simulator.apply_move(state, move)
		var next_state: StateData = transition["state"] as StateData
		var score: int = _search(next_state, maxi(max_depth - 1, 0), alpha, beta, root_owner)
		if maximizing:
			if score > best_score:
				best_score = score
				best_move = move
			alpha = maxi(alpha, best_score)
		else:
			if score < best_score:
				best_score = score
				best_move = move
			beta = mini(beta, best_score)
	return best_move.duplicate_move()


static func _search(
	state: StateData,
	depth_remaining: int,
	alpha_value: int,
	beta_value: int,
	root_owner: int
) -> int:
	if depth_remaining <= 0 or Simulator.is_terminal(state):
		return _evaluate(state, root_owner)

	var legal_moves: Array[MoveData] = Simulator.get_legal_moves(state)
	if legal_moves.is_empty():
		return _evaluate(state, root_owner)

	var alpha: int = alpha_value
	var beta: int = beta_value
	if state.active_player == root_owner:
		var maximum: int = -INFINITY
		for move: MoveData in legal_moves:
			var transition: Dictionary = Simulator.apply_move(state, move)
			var next_state: StateData = transition["state"] as StateData
			maximum = maxi(maximum, _search(next_state, depth_remaining - 1, alpha, beta, root_owner))
			alpha = maxi(alpha, maximum)
			if alpha >= beta:
				break
		return maximum

	var minimum: int = INFINITY
	for move: MoveData in legal_moves:
		var transition: Dictionary = Simulator.apply_move(state, move)
		var next_state: StateData = transition["state"] as StateData
		minimum = mini(minimum, _search(next_state, depth_remaining - 1, alpha, beta, root_owner))
		beta = mini(beta, minimum)
		if alpha >= beta:
			break
	return minimum


static func _evaluate(state: StateData, root_owner: int) -> int:
	var score_difference: int = Simulator.score_difference(state, root_owner)
	if Simulator.is_terminal(state):
		if score_difference > 0:
			return WIN_SCORE + score_difference * 100 - state.turn_count
		if score_difference < 0:
			return -WIN_SCORE + score_difference * 100 + state.turn_count
		return 0

	var opponent_owner: int = Simulator.other_owner(root_owner)
	var hand_difference: int = (
		state.get_hand(root_owner).size()
		- state.get_hand(opponent_owner).size()
	)
	return score_difference * 100 + hand_difference * 5
