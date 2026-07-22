extends SceneTree

const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")
const Action = preload("res://scripts/duel_action.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const Search = preload("res://scripts/duel_search.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Effects = preload("res://scripts/duel_effects.gd")
const Triggers = preload("res://scripts/duel_triggers.gd")

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
	_test_draw_on_play_respects_hand_cap_and_event_order()
	_test_draw_on_play_uses_top_deck_order_and_available_cards()
	_test_draw_on_play_handles_empty_deck()
	_test_turn_passes_to_owner_with_a_legal_move()
	_test_reopened_cell_keeps_match_alive()
	_test_terminal_requires_both_players_to_be_stuck()
	_test_greedy_choice_matches_prototype()
	_test_greedy_ai_values_flip_over_equal_exile()
	_test_deeper_search_avoids_greedy_trap()
	_test_activate_action_generation_and_resolution()
	_test_activate_runs_standard_attack_without_on_play_effects()
	_test_flipped_activate_ability_is_lost_but_ki_remains()
	_test_greedy_tie_prefers_play_over_spending_ki()
	_test_search_can_choose_activate_action()
	_test_trigger_groups_resolve_atomically()
	_test_meng_huo_flip_gain_and_extra_turn()
	_test_meng_huo_multiple_flips_gain_in_order()
	_test_meng_huo_exile_grants_no_ki()
	_test_multiple_meng_huos_drain_for_one_extra_turn()
	_test_meng_huo_extra_turn_can_chain()
	_test_flipped_meng_huo_loses_ability_but_keeps_ki()
	_test_unusable_extra_turn_expires()

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

	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4))
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

	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4))
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

	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4))
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

	var first_transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4))
	var first_state: State = first_transition["state"] as State
	var first_events: Array = first_transition.get("events", [])
	_check(_count_events(first_events, &"ability_lost") == 1, "A non-retained effect emits one ability-lost event")
	_check((((first_state.board[5] as Dictionary)["card"] as Dictionary)["active_effects"] as Array).is_empty(), "Non-retained effect is removed after the first flip")

	var second_transition: Dictionary = Simulator.apply_action(first_state, Action.make_play(0, 2))
	var second_state: State = second_transition["state"] as State
	_check(int((second_state.board[5] as Dictionary)["owner"]) == Rules.OPPONENT_OWNER, "Target can flip back to its original owner")
	_check((((second_state.board[5] as Dictionary)["card"] as Dictionary)["active_effects"] as Array).is_empty(), "Lost effect does not return after flipping back")
	_check(_count_events(second_transition.get("events", []), &"ability_lost") == 0, "Already-lost effect does not emit another loss event")


func _test_draw_on_play_respects_hand_cap_and_event_order() -> void:
	var board: Array = Rules.empty_board()
	board[5] = {
		"card": Rules.make_card("Guard", "守", [1, 1, 1, 1], [], Rules.OPPONENT_OWNER),
		"owner": Rules.OPPONENT_OWNER,
	}
	var player_hand: Array = [Catalog.create_instance(&"fa_zheng", Rules.PLAYER_OWNER, &"main_1_fa")]
	for index: int in range(4):
		player_hand.append(Rules.make_card("Filler %d" % index, "填", [1, 1, 1, 1]))
	var player_deck: Array = [
		Catalog.create_instance(&"xu_shu", Rules.PLAYER_OWNER, &"side_1_top"),
		Catalog.create_instance(&"strategist", Rules.PLAYER_OWNER, &"side_1_next"),
	]
	var state := State.new(board, player_hand, [], Rules.PLAYER_OWNER, 0, player_deck, [])

	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4))
	var next_state: State = transition["state"] as State
	var event_types: Array[StringName] = []
	for event_value: Variant in transition.get("events", []):
		event_types.append(StringName((event_value as Dictionary).get("type", &"")))
	_check(event_types == [&"card_placed", &"card_drawn", &"card_flipped"], "Draw resolves after placement and before flip events")
	_check(next_state.get_hand(Rules.PLAYER_OWNER).size() == 5, "Playing from a full hand draws only enough to return to five")
	_check((next_state.decks[Rules.PLAYER_OWNER] as Array).size() == 1, "Hand cap leaves the second side-deck card undrawn")
	var draw_event: Dictionary = (transition.get("events", []) as Array)[1]
	_check(StringName(draw_event.get("card_id", &"")) == &"xu_shu", "Draw event identifies the top side-deck card")
	_check(StringName(draw_event.get("instance_id", &"")) == &"side_1_top", "Draw event carries stable instance identity")
	_check(int(draw_event.get("logical_hand_index", -1)) == 4, "Draw event reports its resulting logical hand index")
	_check((state.decks[Rules.PLAYER_OWNER] as Array).size() == 2, "Draw transition leaves its source deck untouched")


func _test_draw_on_play_uses_top_deck_order_and_available_cards() -> void:
	var player_hand: Array = [
		Catalog.create_instance(&"fa_zheng", Rules.PLAYER_OWNER, &"main_1_fa"),
		Rules.make_card("First", "一", [1, 1, 1, 1]),
		Rules.make_card("Second", "二", [1, 1, 1, 1]),
	]
	var first_draw: Dictionary = Catalog.create_instance(&"gate_general", Rules.PLAYER_OWNER, &"side_1_gate")
	var second_draw: Dictionary = Catalog.create_instance(&"strategist", Rules.PLAYER_OWNER, &"side_1_strategist")
	var state := State.new(Rules.empty_board(), player_hand, [], Rules.PLAYER_OWNER, 0, [first_draw, second_draw], [])

	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 0))
	var next_state: State = transition["state"] as State
	var next_hand: Array = next_state.get_hand(Rules.PLAYER_OWNER)
	_check(next_hand.size() == 4, "Playing from three cards can draw the full requested two")
	_check(StringName((next_hand[2] as Dictionary).get("instance_id", &"")) == &"side_1_gate", "First draw removes side-deck index zero first")
	_check(StringName((next_hand[3] as Dictionary).get("instance_id", &"")) == &"side_1_strategist", "Second draw preserves side-deck order")
	_check((next_state.decks[Rules.PLAYER_OWNER] as Array).is_empty(), "Drawing two removes both available side-deck cards")
	_check(_count_events(transition.get("events", []), &"card_drawn") == 2, "One event is emitted for each actual draw")

	var partial_state := State.new(
		Rules.empty_board(),
		[Catalog.create_instance(&"fa_zheng", Rules.PLAYER_OWNER, &"partial_fa")],
		[],
		Rules.PLAYER_OWNER,
		0,
		[Catalog.create_instance(&"tiger_general", Rules.PLAYER_OWNER, &"partial_tiger")],
		[]
	)
	var partial_transition: Dictionary = Simulator.apply_action(partial_state, Action.make_play(0, 0))
	_check(_count_events(partial_transition.get("events", []), &"card_drawn") == 1, "A depleted side deck draws only the one remaining card")


func _test_draw_on_play_handles_empty_deck() -> void:
	var state := State.new(
		Rules.empty_board(),
		[Catalog.create_instance(&"fa_zheng", Rules.PLAYER_OWNER, &"empty_fa")],
		[],
		Rules.PLAYER_OWNER
	)
	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 0))
	_check(_count_events(transition.get("events", []), &"card_drawn") == 0, "An empty side deck emits no draw event")
	_check((transition["state"] as State).get_hand(Rules.PLAYER_OWNER).is_empty(), "An empty side deck leaves the post-play hand empty")


func _test_turn_passes_to_owner_with_a_legal_move() -> void:
	var player_hand: Array = [
		Rules.make_card("First", "一", [1, 1, 1, 1]),
		Rules.make_card("Second", "二", [1, 1, 1, 1]),
	]
	var state := State.new(Rules.empty_board(), player_hand, [], Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 0))
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

	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4))
	var next_state = transition["state"]
	_check(next_state.board[5] == null, "Exile reopens a cell on an otherwise full board")
	_check(next_state.active_player == Rules.OPPONENT_OWNER, "Opponent receives the turn when it can use the reopened cell")
	_check(not Simulator.is_terminal(next_state), "Reopened cell prevents premature terminal state")
	var reply_moves: Array = Simulator.get_legal_actions(next_state)
	_check(reply_moves.size() == 1 and (reply_moves[0] as Object).target_index == 5, "Reopened cell is the opponent's legal reply")


func _test_terminal_requires_both_players_to_be_stuck() -> void:
	var opponent_only := State.new(
		Rules.empty_board(),
		[],
		[Rules.make_card("Opponent", "敌", [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check(not Simulator.is_terminal(opponent_only), "Empty active hand is not terminal while the opponent can move")
	_check(Simulator.get_legal_actions_for_owner(opponent_only, Rules.OPPONENT_OWNER).size() == 9, "Owner-specific action query finds the opponent's placements")

	var no_hands := State.new(
		Rules.empty_board(),
		[],
		[],
		Rules.PLAYER_OWNER,
		0,
		[Catalog.create_instance(&"fa_zheng", Rules.PLAYER_OWNER, &"unused_side_card")],
		[]
	)
	_check(Simulator.is_terminal(no_hands), "Match is terminal when neither player can move")
	_check((no_hands.decks[Rules.PLAYER_OWNER] as Array).size() == 1, "Unused side-deck cards do not prevent terminal state")
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

	var choice = Simulator.choose_greedy_action(state)
	_check(choice.as_vector2i() == Vector2i(1, 4), "Greedy AI values gaining a flipped card over an otherwise equal exile")


func _test_activate_action_generation_and_resolution() -> void:
	var board: Array = Rules.empty_board()
	var jiang_wei: Dictionary = Catalog.create_instance(&"jiang_wei", Rules.PLAYER_OWNER, &"board_jiang")
	board[4] = {"card": jiang_wei, "owner": Rules.PLAYER_OWNER}
	var state := State.new(board, [], [], Rules.PLAYER_OWNER)
	var actions: Array = Simulator.get_legal_actions(state)
	_check(actions.size() == 4, "Center move-and-attack card generates four orthogonal activate targets")
	var target_order: Array[int] = []
	for action: Action in actions:
		_check(action.action_type == Action.TYPE_ACTIVATE, "Board action is marked activate")
		target_order.append(action.target_index)
	_check(target_order == [1, 5, 7, 3], "Activate targets use deterministic top-right-bottom-left order")

	var transition: Dictionary = Simulator.apply_action(state, actions[1])
	var next_state: State = transition["state"] as State
	_check(bool(transition.get("valid", false)), "Legal activate action is accepted")
	_check(next_state.board[4] == null and next_state.board[5] != null, "Activate moves the existing card to its target")
	var moved_card: Dictionary = (next_state.board[5] as Dictionary)["card"]
	_check(StringName(moved_card.get("instance_id", &"")) == &"board_jiang", "Movement preserves stable card identity")
	_check(int(moved_card.get("ki", -1)) == 0, "Successful activation spends one ki")
	var event_types: Array[StringName] = []
	for event_value: Variant in transition.get("events", []):
		event_types.append(StringName((event_value as Dictionary).get("type", &"")))
	_check(event_types == [&"ability_activated", &"ki_changed", &"card_moved"], "Movement events use the canonical activation order")
	_check(int(((state.board[4] as Dictionary)["card"] as Dictionary).get("ki", -1)) == 1, "Activate transition leaves source-state ki untouched")


func _test_activate_runs_standard_attack_without_on_play_effects() -> void:
	var board: Array = Rules.empty_board()
	var effects: Array = [
		{
			"id": Catalog.EFFECT_MOVE_AND_ATTACK,
			"activation": Catalog.ACTIVATION_DRAG_TO_TARGET,
			"target_rule": Catalog.TARGET_ADJACENT_EMPTY_BOARD,
			"retained_on_flip": false,
		},
		{
			"id": Catalog.EFFECT_DRAW_CARDS_ON_PLAY,
			"draw_count": 2,
			"retained_on_flip": false,
		},
	]
	var mover: Dictionary = Rules.make_card("Mover", "移", [7, 7, 7, 7], effects, Rules.PLAYER_OWNER)
	mover["instance_id"] = &"mover"
	mover["ki"] = 1
	board[4] = {"card": mover, "owner": Rules.PLAYER_OWNER}
	board[2] = {
		"card": Rules.make_card("Guard", "守", [2, 2, 2, 2], [], Rules.OPPONENT_OWNER),
		"owner": Rules.OPPONENT_OWNER,
	}
	var deck: Array = [Catalog.create_instance(&"xu_shu", Rules.PLAYER_OWNER, &"would_draw")]
	var state := State.new(board, [], [], Rules.PLAYER_OWNER, 0, deck, [])
	var action: Action = Action.make_activate(4, &"mover", Catalog.EFFECT_MOVE_AND_ATTACK, Action.TARGET_BOARD_CELL, 5)
	var transition: Dictionary = Simulator.apply_action(state, action)
	var next_state: State = transition["state"] as State
	_check(int((next_state.board[2] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER, "Moved card performs its standard four-side attack")
	_check(_count_events(transition.get("events", []), &"card_flipped") == 1, "Activation emits the ordinary flip event")
	_check(_count_events(transition.get("events", []), &"card_drawn") == 0, "Movement does not retrigger on-play draw effects")
	_check((next_state.decks[Rules.PLAYER_OWNER] as Array).size() == 1, "Movement leaves the side deck untouched")


func _test_flipped_activate_ability_is_lost_but_ki_remains() -> void:
	var board: Array = Rules.empty_board()
	var jiang_wei: Dictionary = Catalog.create_instance(&"jiang_wei", Rules.OPPONENT_OWNER, &"flip_jiang")
	board[5] = {"card": jiang_wei, "owner": Rules.OPPONENT_OWNER}
	var attacker: Dictionary = Rules.make_card("Recruiter", "招", [1, 9, 1, 1], [], Rules.PLAYER_OWNER)
	var state := State.new(board, [attacker], [], Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4))
	var next_state: State = transition["state"] as State
	var flipped_card: Dictionary = (next_state.board[5] as Dictionary)["card"]
	_check(int(flipped_card.get("ki", -1)) == 1, "Ownership flip preserves ki")
	_check(Effects.get_activate_effect(flipped_card).is_empty(), "Ownership flip permanently removes non-retained activate ability")
	_check(_count_events(transition.get("events", []), &"ability_lost") == 1, "Lost activate ability emits the normal loss event")
	var player_actions: Array = Simulator.get_legal_actions_for_owner(next_state, Rules.PLAYER_OWNER)
	var can_activate_flipped_card: bool = false
	for action: Action in player_actions:
		can_activate_flipped_card = can_activate_flipped_card or (
			action.action_type == Action.TYPE_ACTIVATE and action.source_index == 5
		)
	_check(not can_activate_flipped_card, "Retained ki alone cannot activate a lost ability")


func _test_greedy_tie_prefers_play_over_spending_ki() -> void:
	var board: Array = Rules.empty_board()
	var effects: Array = [
		{
			"id": Catalog.EFFECT_MOVE_AND_ATTACK,
			"activation": Catalog.ACTIVATION_DRAG_TO_TARGET,
			"target_rule": Catalog.TARGET_ADJACENT_EMPTY_BOARD,
			"retained_on_flip": false,
		},
		{"id": Catalog.EFFECT_EXILE_INSTEAD_OF_FLIP, "retained_on_flip": true},
	]
	var mover: Dictionary = Rules.make_card("Mover", "移", [1, 9, 1, 1], effects, Rules.PLAYER_OWNER)
	mover["instance_id"] = &"tie_mover"
	mover["ki"] = 1
	board[0] = {"card": mover, "owner": Rules.PLAYER_OWNER}
	board[2] = {
		"card": Rules.make_card("Target", "标", [9, 9, 9, 1], [], Rules.OPPONENT_OWNER),
		"owner": Rules.OPPONENT_OWNER,
	}
	var weak_play: Dictionary = Rules.make_card("Weak", "弱", [1, 1, 1, 1], [], Rules.PLAYER_OWNER)
	var state := State.new(board, [weak_play], [], Rules.PLAYER_OWNER)
	var choice: Action = Simulator.choose_greedy_action(state)
	_check(choice.action_type == Action.TYPE_PLAY, "Greedy AI preserves ki when play and activate have equal immediate score")


func _test_search_can_choose_activate_action() -> void:
	var board: Array = Rules.empty_board()
	var sun_zan: Dictionary = Catalog.create_instance(&"sun_zan", Rules.OPPONENT_OWNER, &"search_sun")
	board[4] = {"card": sun_zan, "owner": Rules.OPPONENT_OWNER}
	var state := State.new(board, [], [], Rules.OPPONENT_OWNER)
	var choice: Action = Search.find_best_action(state, 2, Rules.OPPONENT_OWNER)
	_check(choice.action_type == Action.TYPE_ACTIVATE, "Deep search considers board activate actions")
	_check(choice.source_index == 4 and choice.target_index == 1, "Search action ordering is deterministic when activate outcomes tie")


func _test_trigger_groups_resolve_atomically() -> void:
	var board: Array = Rules.empty_board()
	var first: Dictionary = Catalog.create_instance(&"meng_huo", Rules.PLAYER_OWNER, &"trigger_first")
	var second: Dictionary = Catalog.create_instance(&"meng_huo", Rules.PLAYER_OWNER, &"trigger_second")
	first["ki"] = 2
	second["ki"] = 3
	board[0] = {"card": first, "owner": Rules.PLAYER_OWNER}
	board[8] = {"card": second, "owner": Rules.PLAYER_OWNER}
	var state := State.new(board, [], [], Rules.PLAYER_OWNER)
	var groups: Array[Dictionary] = Triggers.discover(
		state,
		Catalog.TRIGGER_END_OWNER_TURN,
		{"owner_id": Rules.PLAYER_OWNER}
	)
	_check(groups.size() == 2, "End-turn discovery finds both eligible Meng Huos")
	_check(int(groups[0].get("source_cell", -1)) == 0 and int(groups[1].get("source_cell", -1)) == 8, "End-turn discovery uses row-major board order")
	var copied: State = state.duplicate_state()
	var result: Dictionary = Triggers.resolve(copied, groups)
	var events: Array = result.get("events", [])
	var requests: Array = result.get("extra_turn_requests", [])
	_check(events.size() == 2 and requests.size() == 2, "Each valid rule drains ki and preserves its request after the spend")
	_check(int((events[0] as Dictionary).get("source_cell", -1)) == 0 and int((events[1] as Dictionary).get("source_cell", -1)) == 8, "Ki drains preserve row-major group order")
	_check(int((((copied.board[0] as Dictionary)["card"] as Dictionary).get("ki", -1))) == 0, "First matched rule spends all ki")
	_check(int((((copied.board[8] as Dictionary)["card"] as Dictionary).get("ki", -1))) == 0, "Second matched rule spends all ki")
	_check(int((((state.board[0] as Dictionary)["card"] as Dictionary).get("ki", -1))) == 2, "Trigger resolution leaves its source state untouched")

	var stale_state: State = state.duplicate_state()
	var replacement: Dictionary = Catalog.create_instance(&"meng_huo", Rules.PLAYER_OWNER, &"replacement")
	replacement["ki"] = 5
	stale_state.board[0] = {"card": replacement, "owner": Rules.PLAYER_OWNER}
	var stale_result: Dictionary = Triggers.resolve(stale_state, groups)
	_check((stale_result.get("events", []) as Array).size() == 1, "Stale instance group is ignored while other groups still resolve")
	_check(int(replacement.get("ki", -1)) == 5, "Stale source identity cannot spend replacement-card ki")


func _test_meng_huo_flip_gain_and_extra_turn() -> void:
	var board: Array = Rules.empty_board()
	board[5] = {
		"card": Rules.make_card("Guard", "守", [1, 1, 1, 1], [], Rules.OPPONENT_OWNER),
		"owner": Rules.OPPONENT_OWNER,
	}
	var hand: Array = [
		Catalog.create_instance(&"meng_huo", Rules.PLAYER_OWNER, &"momentum_meng"),
		Rules.make_card("Followup", "续", [1, 1, 1, 1], [], Rules.PLAYER_OWNER),
	]
	var state := State.new(board, hand, [], Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4))
	var next_state: State = transition["state"] as State
	var events: Array = transition.get("events", [])
	var event_types: Array[StringName] = _event_types(events)
	_check(event_types == [&"card_placed", &"card_flipped", &"ki_changed", &"ki_changed", &"extra_turn_granted"], "Single flip gains ki, drains it, then grants an extra turn")
	var gain_event: Dictionary = events[2]
	var spend_event: Dictionary = events[3]
	_check(int(gain_event.get("previous_ki", -1)) == 0 and int(gain_event.get("ki", -1)) == 1, "Successful flip gains exactly one ki")
	_check(int(spend_event.get("previous_ki", -1)) == 1 and int(spend_event.get("ki", -1)) == 0, "End turn spends all gained ki")
	_check(StringName(gain_event.get("change_reason", &"")) == Catalog.TRIGGER_ACTION_GAIN_KI, "Gain event identifies its generic trigger action")
	_check(StringName(spend_event.get("change_reason", &"")) == Catalog.TRIGGER_ACTION_SPEND_ALL_KI, "Spend event identifies its generic trigger action")
	_check(next_state.active_player == Rules.PLAYER_OWNER and next_state.turn_count == 1, "Extra turn retains the acting owner without adding a turn count")
	_check(int((((next_state.board[4] as Dictionary)["card"] as Dictionary).get("ki", -1))) == 0, "Final simulator state stores the drained ki")


func _test_meng_huo_multiple_flips_gain_in_order() -> void:
	var board: Array = Rules.empty_board()
	var weak: Dictionary = Rules.make_card("Weak", "弱", [1, 1, 1, 1], [], Rules.OPPONENT_OWNER)
	for target_cell: int in [1, 5, 7, 3]:
		board[target_cell] = {"card": weak.duplicate(true), "owner": Rules.OPPONENT_OWNER}
	var state := State.new(
		board,
		[
			Catalog.create_instance(&"meng_huo", Rules.PLAYER_OWNER, &"multi_meng"),
			Rules.make_card("Followup", "续", [1, 1, 1, 1], [], Rules.PLAYER_OWNER),
		],
		[],
		Rules.PLAYER_OWNER
	)
	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4))
	var events: Array = transition.get("events", [])
	var flip_targets: Array[int] = []
	var gained_values: Array[int] = []
	for event_value: Variant in events:
		var event: Dictionary = event_value
		if StringName(event.get("type", &"")) == &"card_flipped":
			flip_targets.append(int(event.get("target_cell", -1)))
		elif StringName(event.get("type", &"")) == &"ki_changed" and StringName(event.get("change_reason", &"")) == Catalog.TRIGGER_ACTION_GAIN_KI:
			gained_values.append(int(event.get("ki", -1)))
	_check(flip_targets == [1, 5, 7, 3], "Multi-flip attacks retain top-right-bottom-left order")
	_check(gained_values == [1, 2, 3, 4], "Meng Huo gains one ki immediately after each actual flip")
	_check(_count_events(events, &"extra_turn_granted") == 1, "Any amount of gained ki grants one extra turn")


func _test_meng_huo_exile_grants_no_ki() -> void:
	var board: Array = Rules.empty_board()
	board[5] = {
		"card": Rules.make_card("Target", "标", [1, 1, 1, 1], [], Rules.OPPONENT_OWNER),
		"owner": Rules.OPPONENT_OWNER,
	}
	var meng: Dictionary = Catalog.create_instance(&"meng_huo", Rules.PLAYER_OWNER, &"exile_meng")
	(meng.get("active_effects", []) as Array).append({
		"id": Catalog.EFFECT_EXILE_INSTEAD_OF_FLIP,
		"retained_on_flip": true,
	})
	var state := State.new(board, [meng], [], Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4))
	var events: Array = transition.get("events", [])
	_check(_count_events(events, &"card_exiled") == 1, "Fixture replaces Meng Huo's flip with exile")
	_check(_count_events(events, &"ki_changed") == 0 and _count_events(events, &"extra_turn_granted") == 0, "Exile grants no ki or extra turn")


func _test_multiple_meng_huos_drain_for_one_extra_turn() -> void:
	var board: Array = Rules.empty_board()
	var first: Dictionary = Catalog.create_instance(&"meng_huo", Rules.PLAYER_OWNER, &"row_first")
	var second: Dictionary = Catalog.create_instance(&"meng_huo", Rules.PLAYER_OWNER, &"row_second")
	first["ki"] = 2
	second["ki"] = 4
	board[0] = {"card": first, "owner": Rules.PLAYER_OWNER}
	board[8] = {"card": second, "owner": Rules.PLAYER_OWNER}
	var hand: Array = [
		Rules.make_card("Action", "行", [1, 1, 1, 1], [], Rules.PLAYER_OWNER),
		Rules.make_card("Followup", "续", [1, 1, 1, 1], [], Rules.PLAYER_OWNER),
	]
	var state := State.new(board, hand, [], Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4))
	var events: Array = transition.get("events", [])
	var drain_cells: Array[int] = []
	for event_value: Variant in events:
		var event: Dictionary = event_value
		if StringName(event.get("change_reason", &"")) == Catalog.TRIGGER_ACTION_SPEND_ALL_KI:
			drain_cells.append(int(event.get("source_cell", -1)))
	_check(drain_cells == [0, 8], "Multiple Meng Huos drain in row-major order")
	_check(_count_events(events, &"extra_turn_granted") == 1, "Multiple request tokens coalesce into one extra turn")
	var extra_event: Dictionary = _first_event(events, &"extra_turn_granted")
	_check(int(extra_event.get("request_count", 0)) == 2, "Coalesced event records both valid requests")
	_check((transition["state"] as State).active_player == Rules.PLAYER_OWNER, "Coalesced extra turn retains the acting owner once")


func _test_meng_huo_extra_turn_can_chain() -> void:
	var board: Array = Rules.empty_board()
	var weak: Dictionary = Rules.make_card("Weak", "弱", [1, 1, 1, 1], [], Rules.OPPONENT_OWNER)
	board[1] = {"card": weak.duplicate(true), "owner": Rules.OPPONENT_OWNER}
	board[4] = {"card": weak.duplicate(true), "owner": Rules.OPPONENT_OWNER}
	var hand: Array = [
		Catalog.create_instance(&"meng_huo", Rules.PLAYER_OWNER, &"chain_first"),
		Catalog.create_instance(&"meng_huo", Rules.PLAYER_OWNER, &"chain_second"),
		Rules.make_card("Followup", "续", [1, 1, 1, 1], [], Rules.PLAYER_OWNER),
	]
	var state := State.new(board, hand, [], Rules.PLAYER_OWNER)
	var first_transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 0))
	var first_state: State = first_transition["state"] as State
	_check(first_state.active_player == Rules.PLAYER_OWNER and _count_events(first_transition.get("events", []), &"extra_turn_granted") == 1, "First Meng Huo grants the first extra turn")
	var second_transition: Dictionary = Simulator.apply_action(first_state, Action.make_play(0, 3))
	var second_state: State = second_transition["state"] as State
	_check(second_state.active_player == Rules.PLAYER_OWNER and _count_events(second_transition.get("events", []), &"extra_turn_granted") == 1, "New ki gained during an extra turn grants another extra turn")
	_check(second_state.turn_count == 2, "Chained extra-turn actions each increment turn count once")


func _test_flipped_meng_huo_loses_ability_but_keeps_ki() -> void:
	var board: Array = Rules.empty_board()
	var meng: Dictionary = Catalog.create_instance(&"meng_huo", Rules.OPPONENT_OWNER, &"flipped_meng")
	meng["ki"] = 3
	board[5] = {"card": meng, "owner": Rules.OPPONENT_OWNER}
	var attacker: Dictionary = Rules.make_card("Recruiter", "招", [1, 9, 1, 1], [], Rules.PLAYER_OWNER)
	var state := State.new(board, [attacker], [], Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4))
	var next_state: State = transition["state"] as State
	var flipped: Dictionary = (next_state.board[5] as Dictionary)["card"]
	_check(int(flipped.get("ki", -1)) == 3, "Flipped Meng Huo keeps accumulated ki")
	_check(Effects.find_active_effect(flipped, Catalog.EFFECT_BATTLE_MOMENTUM).is_empty(), "Flipped Meng Huo loses battle momentum")
	_check(_count_events(transition.get("events", []), &"ability_lost") == 1, "Battle momentum loss emits the standard loss event")


func _test_unusable_extra_turn_expires() -> void:
	var board: Array = Rules.empty_board()
	board[1] = {
		"card": Rules.make_card("Target", "标", [1, 1, 1, 1], [], Rules.OPPONENT_OWNER),
		"owner": Rules.OPPONENT_OWNER,
	}
	var opponent_hand: Array = [Rules.make_card("Reply", "应", [1, 1, 1, 1], [], Rules.OPPONENT_OWNER)]
	var state := State.new(
		board,
		[Catalog.create_instance(&"meng_huo", Rules.PLAYER_OWNER, &"last_meng")],
		opponent_hand,
		Rules.PLAYER_OWNER
	)
	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 0))
	var next_state: State = transition["state"] as State
	_check(_count_events(transition.get("events", []), &"extra_turn_granted") == 1, "Successful flip still grants the extra-turn event")
	_check(next_state.active_player == Rules.OPPONENT_OWNER, "Extra turn expires when its owner has no legal action")


func _event_types(events: Array) -> Array[StringName]:
	var types: Array[StringName] = []
	for event_value: Variant in events:
		types.append(StringName((event_value as Dictionary).get("type", &"")))
	return types


func _first_event(events: Array, event_type: StringName) -> Dictionary:
	for event_value: Variant in events:
		var event: Dictionary = event_value
		if StringName(event.get("type", &"")) == event_type:
			return event
	return {}


func _count_events(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for event_value: Variant in events:
		if StringName((event_value as Dictionary).get("type", &"")) == event_type:
			count += 1
	return count


func _test_state_copy_is_isolated() -> void:
	var player_deck: Array = [Catalog.create_instance(&"fa_zheng", Rules.PLAYER_OWNER, &"side_1_0")]
	var opponent_deck: Array = [Catalog.create_instance(&"strategist", Rules.OPPONENT_OWNER, &"side_2_0")]
	var original := State.new(
		Rules.empty_board(),
		[Rules.make_card("Player", "我", [1, 2, 3, 4])],
		[Rules.make_card("Opponent", "敌", [4, 3, 2, 1])],
		Rules.PLAYER_OWNER,
		0,
		player_deck,
		opponent_deck
	)
	(player_deck[0] as Dictionary)["name"] = "Mutated source"
	(opponent_deck[0] as Dictionary)["name"] = "Mutated source"
	_check(String(((original.decks[Rules.PLAYER_OWNER] as Array)[0] as Dictionary)["name"]) == "Fa Zheng", "State constructor deep-copies the player side deck")
	_check(String(((original.decks[Rules.OPPONENT_OWNER] as Array)[0] as Dictionary)["name"]) == "Strategist", "State constructor deep-copies the opponent side deck")
	var copied = original.duplicate_state()
	copied.board[0] = {"card": Rules.make_card("Copy", "副", [5, 5, 5, 5]), "owner": Rules.PLAYER_OWNER}
	copied.get_hand(Rules.PLAYER_OWNER).clear()
	var copied_player_deck: Array = copied.decks[Rules.PLAYER_OWNER]
	((copied_player_deck[0] as Dictionary)["powers"] as Array)[0] = 99
	(((copied_player_deck[0] as Dictionary)["active_effects"] as Array)[0] as Dictionary)["draw_count"] = 9
	_check(original.board[0] == null, "Duplicating state isolates board mutation")
	_check(original.get_hand(Rules.PLAYER_OWNER).size() == 1, "Duplicating state isolates hand mutation")
	var original_top: Dictionary = (original.decks[Rules.PLAYER_OWNER] as Array)[0]
	_check(int((original_top["powers"] as Array)[0]) == 5, "Duplicating state isolates nested side-deck powers")
	_check(int((((original_top["active_effects"] as Array)[0] as Dictionary)["draw_count"])) == 2, "Duplicating state isolates nested side-deck effects")


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
	var moves: Array = Simulator.get_legal_actions(state)
	_check(moves.size() == 18, "Two cards on an empty board generate eighteen legal moves")
	_check((moves[0] as Object).source_index == 0 and (moves[0] as Object).target_index == 0, "Legal actions use deterministic card-then-cell ordering")
	_check((moves[17] as Object).source_index == 1 and (moves[17] as Object).target_index == 8, "Legal action ordering reaches the second card's final cell")


func _test_move_application_and_capture_parity() -> void:
	var board: Array = Rules.empty_board()
	var defender: Dictionary = Rules.make_card("Guard", "守", [1, 1, 1, 3])
	board[5] = {"card": defender, "owner": Rules.OPPONENT_OWNER}
	var attacker: Dictionary = Rules.make_card("Blade", "刀", [1, 5, 1, 1])
	var state := State.new(board, [attacker], [], Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4))
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
	var simulator_choice = Simulator.choose_greedy_action(state)
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
	var greedy_move = Simulator.choose_greedy_action(state)
	var searched_move = Search.find_best_action(state, 4, Rules.OPPONENT_OWNER)
	_check(greedy_move.as_vector2i() == Vector2i(1, 4), "Fixture preserves the tempting two-capture greedy move")
	_check(searched_move.as_vector2i() == Vector2i(0, 3), "Four-ply search chooses the stronger long-term move")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
