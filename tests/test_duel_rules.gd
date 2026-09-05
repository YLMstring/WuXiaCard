extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const BoardQueries = preload("res://tests/helpers/duel_native_board_queries.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_four_direction_attack_targets()
	_test_would_flip_query_is_pure()
	_test_contextual_attack_eligibility()
	_test_negative_powers_take_precedence_over_reversed_comparison()
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
	var attacker: Dictionary = _runtime_card(&"pure_attacker", [5, 5, 5, 5])
	board[4] = {"card": attacker, "owner": Rules.PLAYER_OWNER}
	board[1] = {"card": _runtime_card(&"pure_top", [4, 4, 4, 4]), "owner": Rules.OPPONENT_OWNER}
	board[5] = {"card": _runtime_card(&"pure_right", [4, 4, 4, 4]), "owner": Rules.OPPONENT_OWNER}
	board[7] = {"card": _runtime_card(&"pure_bottom", [5, 5, 5, 5]), "owner": Rules.OPPONENT_OWNER}
	board[3] = {"card": _runtime_card(&"pure_left", [4, 4, 4, 4]), "owner": Rules.PLAYER_OWNER}
	var before: Array = board.duplicate(true)

	var would_flip: Array[int] = BoardQueries.get_would_flip_indices(board, 4)
	_check(would_flip == [1, 5], "Would-flip query returns valid targets in top-right-bottom-left order")
	_check(board == before, "Would-flip query does not mutate board ownership")
	_check(BoardQueries.get_would_flip_indices(board, -1).is_empty(), "Would-flip query safely rejects an invalid source index")


func _test_four_direction_attack_targets() -> void:
	var board: Array = Rules.empty_board()
	board[4] = {"card": _runtime_card(&"four_attacker", [5, 5, 5, 5]), "owner": Rules.PLAYER_OWNER}
	for neighbor_index: int in [1, 5, 7, 3]:
		board[neighbor_index] = {
			"card": _runtime_card(StringName("four_target_%d" % neighbor_index), [4, 4, 4, 4]),
			"owner": Rules.OPPONENT_OWNER,
		}

	_check(
		BoardQueries.get_would_flip_indices(board, 4) == [1, 5, 7, 3],
		"Native center attack discovers all four weaker neighbors in direction order"
	)


func _test_contextual_attack_eligibility() -> void:
	var board: Array = Rules.empty_board()
	var attacker: Dictionary = _runtime_card(&"eligibility_attacker", [5, 5, 5, 5])
	board[4] = {"card": attacker, "owner": Rules.PLAYER_OWNER}
	board[1] = {"card": _runtime_card(&"eligibility_top", [4, 4, 4, 4]), "owner": Rules.OPPONENT_OWNER}
	board[5] = {"card": _runtime_card(&"eligibility_right", [5, 5, 5, 5]), "owner": Rules.OPPONENT_OWNER}
	board[3] = {"card": _runtime_card(&"eligibility_left", [4, 4, 4, 4]), "owner": Rules.PLAYER_OWNER}
	board[8] = {"card": _runtime_card(&"eligibility_diagonal", [4, 4, 4, 4]), "owner": Rules.OPPONENT_OWNER}
	_check(
		BoardQueries.can_attack_target(board, 4, 1),
		"Greater orthogonal enemy target is attackable with contextual reason"
	)
	_check(not BoardQueries.can_attack_target(board, 4, 5), "Equal orthogonal power is not attackable")
	_check(not BoardQueries.can_attack_target(board, 4, 3), "Friendly orthogonal card is not attackable")
	_check(not BoardQueries.can_attack_target(board, 4, 8), "Diagonal enemy is not attackable")
	_check(not BoardQueries.can_attack_target(board, -1, 1), "Invalid source cell is not attackable")
	_check(not BoardQueries.can_attack_target(board, 4, 9), "Invalid target cell is not attackable")
	var missing_board: Array = Rules.empty_board()
	missing_board[4] = {"card": attacker, "owner": Rules.PLAYER_OWNER}
	_check(not BoardQueries.can_attack_target(missing_board, 4, 1), "Missing target is not attackable")
	_check(not BoardQueries.can_attack_target(missing_board, 1, 4), "Missing source is not attackable")
	var wrap_board: Array = Rules.empty_board()
	wrap_board[2] = {"card": attacker, "owner": Rules.PLAYER_OWNER}
	wrap_board[3] = {"card": _runtime_card(&"wrap_target", [4, 4, 4, 4]), "owner": Rules.OPPONENT_OWNER}
	_check(not BoardQueries.can_attack_target(wrap_board, 2, 3), "Horizontal row wrapping is not adjacency")


func _test_negative_powers_take_precedence_over_reversed_comparison() -> void:
	var reversed_ability: Dictionary = {
		"modifiers": [{"type": Catalog.MODIFIER_POWER_COMPARISON_REVERSED}],
	}
	var numbered: Dictionary = _runtime_card(&"numbered", [5, 5, 5, 5])
	var reversed_numbered: Dictionary = _runtime_card(&"reversed_numbered", [5, 5, 5, 5], [reversed_ability])
	var negative: Dictionary = _runtime_card(&"negative", [-1, -1, -1, -1])
	var reversed_negative: Dictionary = _runtime_card(&"reversed_negative", [-1, -1, -1, -1], [reversed_ability])
	var board: Array = Rules.empty_board()
	board[4] = {"card": reversed_numbered, "owner": Rules.PLAYER_OWNER}
	board[5] = {"card": negative, "owner": Rules.OPPONENT_OWNER}
	_check(
		BoardQueries.can_attack_target(board, 4, 5),
		"Reversal does not stop an ordinary numbered card from attacking four-sided -1"
	)
	(board[5] as Dictionary)["card"] = reversed_negative
	_check(
		BoardQueries.can_attack_target(board, 4, 5),
		"Defender reversal does not protect a four-sided -1 card"
	)
	(board[4] as Dictionary)["card"] = reversed_negative
	(board[5] as Dictionary)["card"] = numbered
	_check(
		not BoardQueries.can_attack_target(board, 4, 5),
		"Reversal does not let a four-sided -1 card attack an ordinary numbered card"
	)
	var second_negative: Dictionary = reversed_negative.duplicate(true)
	second_negative["instance_id"] = &"second_reversed_negative"
	(board[5] as Dictionary)["card"] = second_negative
	_check(
		not BoardQueries.can_attack_target(board, 4, 5),
		"Reversal does not let one four-sided -1 card attack another"
	)


func _test_equal_power_does_not_capture() -> void:
	var board: Array = Rules.empty_board()
	var attacker: Dictionary = _runtime_card(&"equal_attacker", [1, 5, 1, 1])
	var defender: Dictionary = _runtime_card(&"equal_defender", [1, 1, 1, 5])
	board[4] = {"card": attacker, "owner": Rules.PLAYER_OWNER}
	board[5] = {"card": defender, "owner": Rules.OPPONENT_OWNER}
	_check(not BoardQueries.can_attack_target(board, 4, 5), "Equal touching powers do not produce a legal native attack")
	_check(int((board[5] as Dictionary)["owner"]) == Rules.OPPONENT_OWNER, "Pure native attack query leaves defender ownership unchanged")


func _test_illegal_placement_is_rejected() -> void:
	var board: Array = Rules.empty_board()
	_check(Rules.can_place(board, 0), "Empty cell is a legal placement location")
	board[0] = {"card": _runtime_card(&"occupied", [1, 2, 3, 4]), "owner": Rules.PLAYER_OWNER}
	_check(not Rules.can_place(board, 0), "Occupied cell is not a legal placement location")
	_check(not Rules.can_place(board, -1) and not Rules.can_place(board, 9), "Out-of-range cells are not legal placement locations")


func _test_score_and_full_board() -> void:
	var board: Array = Rules.empty_board()
	var card: Dictionary = Rules.make_card("Stone", "石", [1, 1, 1, 1])
	for cell_index: int in range(9):
		board[cell_index] = {
			"card": card.duplicate(true),
			"owner": Rules.PLAYER_OWNER if cell_index < 5 else Rules.OPPONENT_OWNER,
		}
	_check(Rules.count_owned(board, Rules.PLAYER_OWNER) == 5, "Player ownership score counts five")
	_check(Rules.count_owned(board, Rules.OPPONENT_OWNER) == 4, "Opponent ownership score counts four")
	_check(Rules.first_empty_cell(board) == -1, "A full board has no empty cell")


func _test_ai_is_deterministic_and_legal() -> void:
	var board: Array = Rules.empty_board()
	var hand: Array = [
		Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"greedy_enemy_a"),
		Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"greedy_enemy_b"),
	]
	var player_hand: Array = [
		Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"greedy_player_card"),
	]
	var state := State.new(board, player_hand, hand, Rules.OPPONENT_OWNER)
	var first_choice = Simulator.choose_greedy_action(state)
	var second_choice = Simulator.choose_greedy_action(state)
	_check(first_choice.is_same_as(second_choice), "Native greedy query returns the same move for the same state")
	_check(Simulator.is_action_legal(state, first_choice), "Native greedy query returns a legal production action")


func _runtime_card(
	instance_id: StringName,
	powers: Array[int],
	active_abilities: Array = [],
	original_owner: int = Rules.PLAYER_OWNER
) -> Dictionary:
	var card: Dictionary = Rules.make_card(
		String(instance_id),
		String(instance_id),
		powers,
		active_abilities,
		original_owner,
		instance_id
	)
	card["instance_id"] = instance_id
	return card


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
