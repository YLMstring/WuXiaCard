extends SceneTree

const Rules = preload("res://scripts/duel_rules.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_four_direction_capture()
	_test_would_flip_query_is_pure()
	_test_contextual_attack_eligibility()
	_test_equal_power_does_not_capture()
	_test_illegal_placement_is_rejected()
	_test_score_and_full_board()
	_test_ai_is_deterministic_and_legal()

	if _failures == 0:
		print("DUEL_RULE_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("DUEL_RULE_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _test_would_flip_query_is_pure() -> void:
	var board: Array = Rules.empty_board()
	var attacker: Dictionary = Rules.make_card("Center", "中", [5, 5, 5, 5])
	var weak_defender: Dictionary = Rules.make_card("Weak", "弱", [4, 4, 4, 4])
	var equal_defender: Dictionary = Rules.make_card("Equal", "平", [5, 5, 5, 5])
	board[4] = {"card": attacker, "owner": Rules.PLAYER_OWNER}
	board[1] = {"card": weak_defender.duplicate(true), "owner": Rules.OPPONENT_OWNER}
	board[5] = {"card": weak_defender.duplicate(true), "owner": Rules.OPPONENT_OWNER}
	board[7] = {"card": equal_defender, "owner": Rules.OPPONENT_OWNER}
	board[3] = {"card": weak_defender.duplicate(true), "owner": Rules.PLAYER_OWNER}
	var before: Array = board.duplicate(true)

	var would_flip: Array[int] = Rules.get_would_flip_indices(board, 4)
	_check(would_flip == [1, 5], "Would-flip query returns valid targets in top-right-bottom-left order")
	_check(board == before, "Would-flip query does not mutate board ownership")
	_check(Rules.get_would_flip_indices(board, -1).is_empty(), "Would-flip query safely rejects an invalid source index")


func _test_four_direction_capture() -> void:
	var board: Array = Rules.empty_board()
	var attacker: Dictionary = Rules.make_card("Center", "中", [5, 5, 5, 5])
	var defender: Dictionary = Rules.make_card("Guard", "守", [4, 4, 4, 4])
	for neighbor_index: int in [1, 5, 7, 3]:
		board[neighbor_index] = {"card": defender.duplicate(true), "owner": Rules.OPPONENT_OWNER}

	var captured: Array[int] = Rules.place_card(board, 4, attacker, Rules.PLAYER_OWNER)
	_check(captured.size() == 4, "Center placement captures all four weaker neighbors")
	for neighbor_index: int in [1, 5, 7, 3]:
		_check(int((board[neighbor_index] as Dictionary)["owner"]) == Rules.PLAYER_OWNER, "Captured owner updates at cell %d" % neighbor_index)


func _test_contextual_attack_eligibility() -> void:
	var board: Array = Rules.empty_board()
	var attacker: Dictionary = Rules.make_card("Attacker", "攻", [5, 5, 5, 5])
	var weak_enemy: Dictionary = Rules.make_card("Weak", "弱", [4, 4, 4, 4])
	var equal_enemy: Dictionary = Rules.make_card("Equal", "平", [5, 5, 5, 5])
	board[4] = {"card": attacker, "owner": Rules.PLAYER_OWNER}
	board[1] = {"card": weak_enemy.duplicate(true), "owner": Rules.OPPONENT_OWNER}
	board[5] = {"card": equal_enemy, "owner": Rules.OPPONENT_OWNER}
	board[3] = {"card": weak_enemy.duplicate(true), "owner": Rules.PLAYER_OWNER}
	board[8] = {"card": weak_enemy.duplicate(true), "owner": Rules.OPPONENT_OWNER}
	_check(
		Rules.can_attack_target(board, 4, 1, {"reason": &"card_summoned_reaction"}),
		"Greater orthogonal enemy target is attackable with contextual reason"
	)
	_check(not Rules.can_attack_target(board, 4, 5), "Equal orthogonal power is not attackable")
	_check(not Rules.can_attack_target(board, 4, 3), "Friendly orthogonal card is not attackable")
	_check(not Rules.can_attack_target(board, 4, 8), "Diagonal enemy is not attackable")
	_check(not Rules.can_attack_target(board, -1, 1), "Invalid source cell is not attackable")
	_check(not Rules.can_attack_target(board, 4, 9), "Invalid target cell is not attackable")
	var missing_board: Array = Rules.empty_board()
	missing_board[4] = {"card": attacker, "owner": Rules.PLAYER_OWNER}
	_check(not Rules.can_attack_target(missing_board, 4, 1), "Missing target is not attackable")
	_check(not Rules.can_attack_target(missing_board, 1, 4), "Missing source is not attackable")
	var wrap_board: Array = Rules.empty_board()
	wrap_board[2] = {"card": attacker, "owner": Rules.PLAYER_OWNER}
	wrap_board[3] = {"card": weak_enemy, "owner": Rules.OPPONENT_OWNER}
	_check(not Rules.can_attack_target(wrap_board, 2, 3), "Horizontal row wrapping is not adjacency")


func _test_equal_power_does_not_capture() -> void:
	var board: Array = Rules.empty_board()
	var attacker: Dictionary = Rules.make_card("Equal", "平", [1, 5, 1, 1])
	var defender: Dictionary = Rules.make_card("Equal Guard", "衡", [1, 1, 1, 5])
	board[5] = {"card": defender, "owner": Rules.OPPONENT_OWNER}
	var captured: Array[int] = Rules.place_card(board, 4, attacker, Rules.PLAYER_OWNER)
	_check(captured.is_empty(), "Equal touching powers do not capture")
	_check(int((board[5] as Dictionary)["owner"]) == Rules.OPPONENT_OWNER, "Equal-power defender keeps ownership")


func _test_illegal_placement_is_rejected() -> void:
	var board: Array = Rules.empty_board()
	var card: Dictionary = Rules.make_card("First", "一", [1, 2, 3, 4])
	Rules.place_card(board, 0, card, Rules.PLAYER_OWNER)
	var before: Array = board.duplicate(true)
	var captured: Array[int] = Rules.place_card(board, 0, card, Rules.OPPONENT_OWNER)
	_check(captured.is_empty(), "Occupied-cell placement reports no captures")
	_check(board == before, "Occupied-cell placement leaves board unchanged")


func _test_score_and_full_board() -> void:
	var board: Array = Rules.empty_board()
	var card: Dictionary = Rules.make_card("Stone", "石", [1, 1, 1, 1])
	for cell_index: int in range(9):
		board[cell_index] = {
			"card": card.duplicate(true),
			"owner": Rules.PLAYER_OWNER if cell_index < 5 else Rules.OPPONENT_OWNER,
		}
	_check(Rules.is_board_full(board), "Nine occupied cells make a full board")
	_check(Rules.count_owned(board, Rules.PLAYER_OWNER) == 5, "Player ownership score counts five")
	_check(Rules.count_owned(board, Rules.OPPONENT_OWNER) == 4, "Opponent ownership score counts four")


func _test_ai_is_deterministic_and_legal() -> void:
	var board: Array = Rules.empty_board()
	var hand: Array = [
		Rules.make_card("Crane", "鹤", [6, 2, 5, 7]),
		Rules.make_card("Tiger", "虎", [4, 8, 3, 5]),
	]
	var first_choice: Vector2i = Rules.choose_ai_move(board, hand)
	var second_choice: Vector2i = Rules.choose_ai_move(board, hand)
	_check(first_choice == second_choice, "AI returns the same move for the same state")
	_check(first_choice.x >= 0 and first_choice.x < hand.size(), "AI chooses a card in hand")
	_check(Rules.can_place(board, first_choice.y), "AI chooses an empty board cell")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
