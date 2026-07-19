extends SceneTree

const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")
const Move = preload("res://scripts/duel_move.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const Search = preload("res://scripts/duel_search.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Effects = preload("res://scripts/duel_effects.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_state_copy_is_isolated()
	_test_legal_move_generation()
	_test_move_application_and_capture_parity()
	_test_exile_effect_removes_every_target()
	_test_exile_uses_original_owner_and_is_copy_isolated()
	_test_retained_effect_survives_flip_and_future_attempt()
	_test_nonretained_effect_is_permanently_lost()
	_test_turn_passes_to_owner_with_a_legal_move()
	_test_reopened_cell_keeps_match_alive()
	_test_terminal_requires_both_players_to_be_stuck()
	_test_greedy_choice_matches_prototype()
	_test_greedy_ai_values_flip_over_equal_exile()
	_test_deeper_search_avoids_greedy_trap()

	if _failures == 0:
		print("DUEL_SIMULATOR_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("DUEL_SIMULATOR_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _test_exile_effect_removes_every_target() -> void:
	var board: Array = Rules.empty_board()
	var defender: Dictionary = Rules.make_card("Guard", "守", [4, 4, 4, 4], [], Rules.OPPONENT_OWNER)
	for neighbor_index: int in [1, 5, 7, 3]:
		board[neighbor_index] = {"card": defender.duplicate(true), "owner": Rules.OPPONENT_OWNER}
	var exile_effect: Array = [{"id": Catalog.EFFECT_EXILE_INSTEAD_OF_FLIP, "retained_on_flip": true}]
	var attacker: Dictionary = Rules.make_card("Exiler", "逐", [5, 5, 5, 5], exile_effect, Rules.PLAYER_OWNER)
	var state := State.new(board, [attacker], [], Rules.PLAYER_OWNER)

	var transition: Dictionary = Simulator.apply_move(state, Move.new(0, 4))
	var next_state: State = transition["state"] as State
	var events: Array = transition.get("events", [])
	var exile_targets: Array[int] = []
	for event_value: Variant in events:
		var event: Dictionary = event_value
		if StringName(event.get("type", &"")) == &"card_exiled":
			exile_targets.append(int(event["target_cell"]))
	_check(exile_targets == [1, 5, 7, 3], "Exile events follow top-right-bottom-left order")
	_check((transition.get("exiles", []) as Array) == [1, 5, 7, 3], "Simulator reports all exiled cells")
	_check((transition.get("captures", []) as Array).is_empty(), "Exiled cards are not also reported as flips")
	for neighbor_index: int in [1, 5, 7, 3]:
		_check(next_state.board[neighbor_index] == null, "Exiled target clears cell %d" % neighbor_index)
	_check((next_state.removed_cards[Rules.OPPONENT_OWNER] as Array).size() == 4, "Every target enters the opponent's removed zone")
	_check(Rules.count_owned(next_state.board, Rules.PLAYER_OWNER) == 1, "Only the placed source scores for the player")
	_check(Rules.count_owned(next_state.board, Rules.OPPONENT_OWNER) == 0, "Exiled targets score for neither player")
	_check(state.board[1] != null and state.board[4] == null, "Exile transition leaves its source state untouched")


func _test_exile_uses_original_owner_and_is_copy_isolated() -> void:
	var board: Array = Rules.empty_board()
	var target_effects: Array = [{"id": Catalog.EFFECT_EXILE_INSTEAD_OF_FLIP, "retained_on_flip": true}]
	var target: Dictionary = Rules.make_card("Turncoat", "反", [1, 1, 1, 1], target_effects, Rules.PLAYER_OWNER)
	board[5] = {"card": target, "owner": Rules.OPPONENT_OWNER}
	var source_effects: Array = [{"id": Catalog.EFFECT_EXILE_INSTEAD_OF_FLIP, "retained_on_flip": true}]
	var source: Dictionary = Rules.make_card("Exiler", "逐", [1, 5, 1, 1], source_effects, Rules.PLAYER_OWNER)
	var state := State.new(board, [source], [], Rules.PLAYER_OWNER)

	var transition: Dictionary = Simulator.apply_move(state, Move.new(0, 4))
	var next_state: State = transition["state"] as State
	var player_removed: Array = next_state.removed_cards[Rules.PLAYER_OWNER]
	_check(player_removed.size() == 1, "Exile records a previously flipped target under its original owner")
	_check((next_state.removed_cards[Rules.OPPONENT_OWNER] as Array).is_empty(), "Current owner does not receive the previously flipped target")
	((player_removed[0] as Dictionary)["active_effects"] as Array).clear()
	_check(((state.board[5] as Dictionary)["card"] as Dictionary)["active_effects"].size() == 1, "Removed-zone mutation is isolated from the source state")
	_check(Rules.can_place(next_state.board, 5), "An exiled cell is immediately reusable")


func _test_retained_effect_survives_flip_and_future_attempt() -> void:
	var board: Array = Rules.empty_board()
	var retained_effect: Array = [{"id": Catalog.EFFECT_EXILE_INSTEAD_OF_FLIP, "retained_on_flip": true}]
	var tiger: Dictionary = Rules.make_card("Tiger General", "虎", [1, 1, 8, 1], retained_effect, Rules.OPPONENT_OWNER)
	var future_target: Dictionary = Rules.make_card("Future Target", "标", [1, 1, 1, 1], [], Rules.OPPONENT_OWNER)
	board[5] = {"card": tiger, "owner": Rules.OPPONENT_OWNER}
	board[8] = {"card": future_target, "owner": Rules.OPPONENT_OWNER}
	var attacker: Dictionary = Rules.make_card("Recruiter", "招", [1, 5, 1, 1], [], Rules.PLAYER_OWNER)
	var state := State.new(board, [attacker], [], Rules.PLAYER_OWNER)

	var transition: Dictionary = Simulator.apply_move(state, Move.new(0, 4))
	var next_state: State = transition["state"] as State
	var flipped_tiger: Dictionary = (next_state.board[5] as Dictionary)["card"]
	_check(int((next_state.board[5] as Dictionary)["owner"]) == Rules.PLAYER_OWNER, "Tiger General changes ownership through a normal flip")
	_check((flipped_tiger["active_effects"] as Array).size() == 1, "Retained effect survives the ownership flip")

	var combo_state: State = next_state.duplicate_state()
	var combo_events: Array[Dictionary] = Effects.resolve_flip_attempt(combo_state, 5, 8, Rules.PLAYER_OWNER)
	_check(combo_events.size() == 1 and StringName(combo_events[0].get("type", &"")) == &"card_exiled", "A future attempt by the flipped Tiger General still exiles")
	_check(combo_state.board[8] == null, "Future retained-effect attempt clears its target")


func _test_nonretained_effect_is_permanently_lost() -> void:
	var board: Array = Rules.empty_board()
	var nonretained_effect: Array = [{"id": Catalog.EFFECT_EXILE_INSTEAD_OF_FLIP, "retained_on_flip": false}]
	var target: Dictionary = Rules.make_card("Fragile Adept", "失", [1, 1, 1, 1], nonretained_effect, Rules.OPPONENT_OWNER)
	board[5] = {"card": target, "owner": Rules.OPPONENT_OWNER}
	var first_attacker: Dictionary = Rules.make_card("First", "一", [1, 5, 1, 1], [], Rules.PLAYER_OWNER)
	var second_attacker: Dictionary = Rules.make_card("Second", "二", [1, 1, 5, 1], [], Rules.OPPONENT_OWNER)
	var state := State.new(board, [first_attacker], [second_attacker], Rules.PLAYER_OWNER)

	var first_transition: Dictionary = Simulator.apply_move(state, Move.new(0, 4))
	var first_state: State = first_transition["state"] as State
	var first_events: Array = first_transition.get("events", [])
	_check(_count_events(first_events, &"ability_lost") == 1, "A non-retained effect emits one ability-lost event")
	_check((((first_state.board[5] as Dictionary)["card"] as Dictionary)["active_effects"] as Array).is_empty(), "Non-retained effect is removed after the first flip")

	var second_transition: Dictionary = Simulator.apply_move(first_state, Move.new(0, 2))
	var second_state: State = second_transition["state"] as State
	_check(int((second_state.board[5] as Dictionary)["owner"]) == Rules.OPPONENT_OWNER, "Target can flip back to its original owner")
	_check((((second_state.board[5] as Dictionary)["card"] as Dictionary)["active_effects"] as Array).is_empty(), "Lost effect does not return after flipping back")
	_check(_count_events(second_transition.get("events", []), &"ability_lost") == 0, "Already-lost effect does not emit another loss event")


func _test_turn_passes_to_owner_with_a_legal_move() -> void:
	var player_hand: Array = [
		Rules.make_card("First", "一", [1, 1, 1, 1]),
		Rules.make_card("Second", "二", [1, 1, 1, 1]),
	]
	var state := State.new(Rules.empty_board(), player_hand, [], Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_move(state, Move.new(0, 0))
	var next_state = transition["state"]
	_check(next_state.active_player == Rules.PLAYER_OWNER, "Opponent with no move passes back to the player")
	_check(not Simulator.is_terminal(next_state), "Match continues when the player can still place a card")


func _test_reopened_cell_keeps_match_alive() -> void:
	var board: Array = Rules.empty_board()
	var sturdy: Dictionary = Rules.make_card("Sturdy", "固", [9, 9, 9, 9], [], Rules.OPPONENT_OWNER)
	for cell_index: int in range(9):
		if cell_index != 4:
			board[cell_index] = {"card": sturdy.duplicate(true), "owner": Rules.OPPONENT_OWNER}
	var weak_target: Dictionary = Rules.make_card("Weak", "弱", [9, 9, 9, 1], [], Rules.OPPONENT_OWNER)
	board[5] = {"card": weak_target, "owner": Rules.OPPONENT_OWNER}
	var exile_effect: Array = [{"id": Catalog.EFFECT_EXILE_INSTEAD_OF_FLIP, "retained_on_flip": true}]
	var exiler: Dictionary = Rules.make_card("Exiler", "逐", [1, 5, 1, 1], exile_effect, Rules.PLAYER_OWNER)
	var opponent_reply: Dictionary = Rules.make_card("Reply", "应", [1, 1, 1, 1], [], Rules.OPPONENT_OWNER)
	var state := State.new(board, [exiler], [opponent_reply], Rules.PLAYER_OWNER)

	var transition: Dictionary = Simulator.apply_move(state, Move.new(0, 4))
	var next_state = transition["state"]
	_check(next_state.board[5] == null, "Exile reopens a cell on an otherwise full board")
	_check(next_state.active_player == Rules.OPPONENT_OWNER, "Opponent receives the turn when it can use the reopened cell")
	_check(not Simulator.is_terminal(next_state), "Reopened cell prevents premature terminal state")
	var reply_moves: Array = Simulator.get_legal_moves(next_state)
	_check(reply_moves.size() == 1 and (reply_moves[0] as Object).cell_index == 5, "Reopened cell is the opponent's legal reply")


func _test_terminal_requires_both_players_to_be_stuck() -> void:
	var opponent_only := State.new(
		Rules.empty_board(),
		[],
		[Rules.make_card("Opponent", "敌", [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check(not Simulator.is_terminal(opponent_only), "Empty active hand is not terminal while the opponent can move")
	_check(Simulator.get_legal_moves_for_owner(opponent_only, Rules.OPPONENT_OWNER).size() == 9, "Owner-specific move query finds the opponent's placements")

	var no_hands := State.new(Rules.empty_board(), [], [], Rules.PLAYER_OWNER)
	_check(Simulator.is_terminal(no_hands), "Match is terminal when neither player can move")
	no_hands.effect_queue.append({"type": &"pending_test"})
	_check(not Simulator.is_terminal(no_hands), "Pending effect queue delays terminal state")
	no_hands.turn_count = no_hands.max_turns
	_check(Simulator.is_terminal(no_hands), "Turn cap ends the match even with pending effects")


func _test_greedy_ai_values_flip_over_equal_exile() -> void:
	var board: Array = Rules.empty_board()
	var allied_guard: Dictionary = Rules.make_card("Ally", "友", [9, 9, 9, 9], [], Rules.OPPONENT_OWNER)
	for cell_index: int in range(9):
		if cell_index != 4:
			board[cell_index] = {"card": allied_guard.duplicate(true), "owner": Rules.OPPONENT_OWNER}
	var target: Dictionary = Rules.make_card("Target", "标", [9, 9, 9, 1], [], Rules.PLAYER_OWNER)
	board[5] = {"card": target, "owner": Rules.PLAYER_OWNER}
	var exile_effect: Array = [{"id": Catalog.EFFECT_EXILE_INSTEAD_OF_FLIP, "retained_on_flip": true}]
	var exile_card: Dictionary = Rules.make_card("Exiler", "逐", [1, 5, 1, 1], exile_effect, Rules.OPPONENT_OWNER)
	var flip_card: Dictionary = Rules.make_card("Flipper", "翻", [1, 5, 1, 1], [], Rules.OPPONENT_OWNER)
	var state := State.new(board, [], [exile_card, flip_card], Rules.OPPONENT_OWNER)

	var choice = Simulator.choose_greedy_move(state)
	_check(choice.as_vector2i() == Vector2i(1, 4), "Greedy AI values gaining a flipped card over an otherwise equal exile")


func _count_events(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for event_value: Variant in events:
		if StringName((event_value as Dictionary).get("type", &"")) == event_type:
			count += 1
	return count


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
