extends SceneTree

const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")
const Move = preload("res://scripts/duel_move.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const Search = preload("res://scripts/duel_search.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_state_copy_is_isolated()
	_test_legal_move_generation()
	_test_move_application_and_capture_parity()
	_test_greedy_choice_matches_prototype()
	_test_deeper_search_avoids_greedy_trap()

	if _failures == 0:
		print("DUEL_SIMULATOR_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("DUEL_SIMULATOR_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _test_state_copy_is_isolated() -> void:
	var original := State.new(
		Rules.empty_board(),
		[Rules.make_card("Player", "我", [1, 2, 3, 4])],
		[Rules.make_card("Opponent", "敌", [4, 3, 2, 1])],
		Rules.PLAYER_OWNER
	)
	var copied = original.duplicate_state()
	copied.board[0] = {"card": Rules.make_card("Copy", "副", [5, 5, 5, 5]), "owner": Rules.PLAYER_OWNER}
	copied.get_hand(Rules.PLAYER_OWNER).clear()
	_check(original.board[0] == null, "Duplicating state isolates board mutation")
	_check(original.get_hand(Rules.PLAYER_OWNER).size() == 1, "Duplicating state isolates hand mutation")


func _test_legal_move_generation() -> void:
	var state := State.new(
		Rules.empty_board(),
		[
			Rules.make_card("One", "一", [1, 1, 1, 1]),
			Rules.make_card("Two", "二", [2, 2, 2, 2]),
		],
		[],
		Rules.PLAYER_OWNER
	)
	var moves: Array = Simulator.get_legal_moves(state)
	_check(moves.size() == 18, "Two cards on an empty board generate eighteen legal moves")
	_check((moves[0] as Object).hand_index == 0 and (moves[0] as Object).cell_index == 0, "Legal moves use deterministic card-then-cell ordering")
	_check((moves[17] as Object).hand_index == 1 and (moves[17] as Object).cell_index == 8, "Legal move ordering reaches the second card's final cell")


func _test_move_application_and_capture_parity() -> void:
	var board: Array = Rules.empty_board()
	var defender: Dictionary = Rules.make_card("Guard", "守", [1, 1, 1, 3])
	board[5] = {"card": defender, "owner": Rules.OPPONENT_OWNER}
	var attacker: Dictionary = Rules.make_card("Blade", "刀", [1, 5, 1, 1])
	var state := State.new(board, [attacker], [], Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_move(state, Move.new(0, 4))
	var next_state = transition.get("state")
	_check(bool(transition.get("valid", false)), "A legal simulator move is accepted")
	_check((transition.get("captures", []) as Array) == [5], "Simulator reports the same direct capture as DuelRules")
	_check(state.board[4] == null and int((state.board[5] as Dictionary)["owner"]) == Rules.OPPONENT_OWNER, "Simulation never mutates the source state")
	_check(next_state.get_hand(Rules.PLAYER_OWNER).is_empty(), "Placed card leaves the simulated hand")
	_check(int((next_state.board[5] as Dictionary)["owner"]) == Rules.PLAYER_OWNER, "Captured ownership updates in the simulated board")
	_check(next_state.active_player == Rules.OPPONENT_OWNER and next_state.turn_count == 1, "Simulation advances player and turn count")


func _test_greedy_choice_matches_prototype() -> void:
	var board: Array = Rules.empty_board()
	var opponent_hand: Array = [
		Rules.make_card("Crane", "鹤", [6, 2, 5, 7]),
		Rules.make_card("Tiger", "虎", [4, 8, 3, 5]),
	]
	var state := State.new(board, [], opponent_hand, Rules.OPPONENT_OWNER)
	var prototype_choice: Vector2i = Rules.choose_ai_move(board, opponent_hand, Rules.OPPONENT_OWNER)
	var simulator_choice = Simulator.choose_greedy_move(state)
	_check(simulator_choice.as_vector2i() == prototype_choice, "Simulator greedy adapter preserves the prototype AI choice")


func _test_deeper_search_avoids_greedy_trap() -> void:
	var board: Array = Rules.empty_board()
	board[0] = {"card": Rules.make_card("B3", "三", [6, 5, 5, 9]), "owner": Rules.PLAYER_OWNER}
	board[1] = {"card": Rules.make_card("B2", "二", [9, 3, 1, 3]), "owner": Rules.PLAYER_OWNER}
	board[5] = {"card": Rules.make_card("B4", "四", [9, 1, 7, 7]), "owner": Rules.PLAYER_OWNER}
	board[6] = {"card": Rules.make_card("B1", "一", [4, 6, 7, 4]), "owner": Rules.PLAYER_OWNER}
	board[7] = {"card": Rules.make_card("B0", "零", [9, 5, 8, 5]), "owner": Rules.OPPONENT_OWNER}
	var player_hand: Array = [
		Rules.make_card("P0", "甲", [5, 9, 1, 3]),
		Rules.make_card("P1", "乙", [8, 3, 7, 7]),
	]
	var opponent_hand: Array = [
		Rules.make_card("O0", "丙", [4, 4, 6, 2]),
		Rules.make_card("O1", "丁", [4, 9, 6, 6]),
	]
	var state := State.new(board, player_hand, opponent_hand, Rules.OPPONENT_OWNER)
	var greedy_move = Simulator.choose_greedy_move(state)
	var searched_move = Search.find_best_move(state, 4, Rules.OPPONENT_OWNER)
	_check(greedy_move.as_vector2i() == Vector2i(1, 4), "Fixture preserves the tempting two-capture greedy move")
	_check(searched_move.as_vector2i() == Vector2i(0, 3), "Four-ply search chooses the stronger long-term move")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
