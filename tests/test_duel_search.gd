extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Evaluator = preload("res://scripts/duel_evaluator.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Search = preload("res://scripts/duel_search.gd")
const Session = preload("res://scripts/duel_search_session.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")

var _failures: int = 0
var _checks: int = 0
var _cancel_after_completed_depth: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if "runtime-benchmark" in OS.get_cmdline_user_args():
		await _run_runtime_benchmark()
		quit(_failures)
		return
	_test_action_and_state_keys()
	_test_evaluator_terminal_priority()
	_test_iterative_depth_and_interruption()
	_test_search_inherits_summon_reactions()
	await _test_search_session()
	if _failures == 0:
		print("DUEL_SEARCH_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("DUEL_SEARCH_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _run_runtime_benchmark() -> void:
	var duel: Node = DUEL_SCENE.instantiate()
	duel.set("opening_layout_seed", 8192)
	root.add_child(duel)
	await process_frame
	await process_frame
	_check(is_equal_approx(float(duel.debug_get_search_budget_seconds()), 10.0), "Shen Lian uses a 10-second search budget")
	var frames_before: int = Engine.get_process_frames()
	var committed: bool = await duel.debug_place_player_card(0, 0)
	var frames_after: int = Engine.get_process_frames()
	var report: Dictionary = duel.debug_get_last_search_report()
	var elapsed: float = float(report.get("elapsed_seconds", -1.0))
	_check(committed, "Player move and automatic smart opponent turn complete")
	_check(frames_after > frames_before + 30, "Main scene continues processing frames during search")
	_check(int(report.get("completed_depth", 0)) >= 1, "Search completes at least one full depth")
	_check(not bool(report.get("used_fallback", true)), "Completed search does not use the greedy fallback")
	_check(elapsed >= 1.0 and elapsed <= 10.25, "Search respects the 10-second maximum with polling tolerance")
	_check(duel.debug_get_board_occupancy() >= 2, "Opponent result commits through the production board path")
	if _failures == 0:
		print(
			"DUEL_SEARCH_BENCHMARK_PASSED elapsed=%.3f depth=%d nodes=%d cutoffs=%d cache_hits=%d reason=%s frames=%d" % [
				elapsed,
				int(report.get("completed_depth", 0)),
				int(report.get("nodes", 0)),
				int(report.get("cutoffs", 0)),
				int(report.get("transposition_hits", 0)),
				String(report.get("completion_reason", &"missing")),
				frames_after - frames_before,
			]
		)
	else:
		push_error("DUEL_SEARCH_BENCHMARK_FAILED failures=%d" % _failures)
	duel.queue_free()
	await process_frame


func _test_action_and_state_keys() -> void:
	var action: Action = Action.make_activate(4, &"unit_1", Action.TARGET_BOARD_CELL, 5)
	_check(action.canonical_key() == action.duplicate_action().canonical_key(), "Duplicated actions retain a stable canonical key")
	var changed_action: Action = action.duplicate_action()
	changed_action.target_index = 3
	_check(action.canonical_key() != changed_action.canonical_key(), "Every target participates in the canonical action key")
	var changed_activation: Action = action.duplicate_action()
	changed_activation.activation_index = 1
	_check(
		action.canonical_key() != changed_activation.canonical_key()
		and not action.is_same_as(changed_activation),
		"Activate ability index participates in canonical action identity"
	)

	var state: State = _make_opening_state()
	var copied: State = state.duplicate_state()
	_check(StateKey.build(state) == StateKey.build(copied), "Deep-copied states retain the same canonical key")
	copied.state_version += 1
	_check(StateKey.build(state) == StateKey.build(copied), "Live state version is excluded from the transposition key")
	(copied.get_hand(Rules.PLAYER_OWNER)[0] as Dictionary)["ki"] = 2
	_check(StateKey.build(state) != StateKey.build(copied), "Card ki changes the canonical state key")
	copied = state.duplicate_state()
	var copied_powers: Array = (
		(copied.get_hand(Rules.PLAYER_OWNER)[0] as Dictionary).get("powers", [])
	)
	copied_powers[0] = int(copied_powers[0]) + 1
	_check(
		StateKey.build(state) != StateKey.build(copied),
		"Permanent runtime power changes participate in the canonical state key"
	)
	_check(
		(state.get_hand(Rules.PLAYER_OWNER)[0] as Dictionary).get("powers", [])
		!= copied_powers,
		"Search-state copies do not alias mutable runtime power arrays"
	)
	copied = state.duplicate_state()
	var removed_card: Dictionary = (copied.get_hand(Rules.PLAYER_OWNER)[0] as Dictionary).duplicate(true)
	copied.get_hand(Rules.PLAYER_OWNER).remove_at(0)
	(copied.removed_cards[Rules.PLAYER_OWNER] as Array).append(removed_card)
	_check(
		StateKey.build(state) != StateKey.build(copied),
		"Exact-card power death and original-owner removal participate in the state key"
	)
	_check(
		(state.removed_cards[Rules.PLAYER_OWNER] as Array).is_empty(),
		"Search-state copies do not alias removed zones"
	)
	var first_order: Dictionary = {"alpha": 1, "beta": 2}
	var second_order: Dictionary = {}
	second_order["beta"] = 2
	second_order["alpha"] = 1
	state.pending_choice = first_order
	copied = state.duplicate_state()
	copied.pending_choice = second_order
	_check(StateKey.build(state) == StateKey.build(copied), "Dictionary insertion order does not affect the state key")
	copied = state.duplicate_state()
	copied.repetition_hashes.append("board-signature")
	_check(
		StateKey.build(state) != StateKey.build(copied),
		"Completed-boundary repetition history participates in the state key"
	)
	_check(
		state.repetition_hashes.is_empty(),
		"Search-state copies do not alias repetition history"
	)
	copied = state.duplicate_state()
	copied.run_difficulty = 8
	_check(
		StateKey.build(state) != StateKey.build(copied),
		"Active run difficulty participates in the canonical state key"
	)
	copied = state.duplicate_state()
	copied.difficulty_eight_draw_consumed = true
	_check(
		StateKey.build(state) != StateKey.build(copied),
		"Difficulty-eight one-card draw usage participates in the state key"
	)
	_check(
		not state.difficulty_eight_draw_consumed,
		"Search-state copies do not alias difficulty runtime flags"
	)


func _test_evaluator_terminal_priority() -> void:
	var board: Array = Rules.empty_board()
	for index: int in range(9):
		var owner_id: int = Rules.PLAYER_OWNER if index < 5 else Rules.OPPONENT_OWNER
		board[index] = {"card": Rules.make_card("Card%d" % index, "牌", [1, 1, 1, 1]), "owner": owner_id}
	var state := State.new(board, [], [], Rules.PLAYER_OWNER)
	_check(Simulator.is_terminal(state), "Full evaluator fixture is terminal")
	_check(Evaluator.evaluate(state, Rules.PLAYER_OWNER) >= Evaluator.WIN_SCORE, "Terminal victory outranks heuristic scores")
	_check(Evaluator.evaluate(state, Rules.OPPONENT_OWNER) <= -Evaluator.WIN_SCORE, "Terminal loss outranks heuristic scores")


func _test_iterative_depth_and_interruption() -> void:
	var state: State = _make_opening_state()
	var interrupted: Dictionary = Search.find_best_action_iterative(state, Rules.OPPONENT_OWNER, {"max_nodes": 1})
	_check(not bool(interrupted.get("has_completed_depth", true)), "Interrupted depth one publishes no partial result")
	_check(StringName(interrupted.get("completion_reason", &"")) == &"node_limit", "Node-limited interruption reports its completion reason")

	var completed: Dictionary = Search.find_best_action_iterative(state, Rules.OPPONENT_OWNER, {"max_depth": 2})
	_check(bool(completed.get("has_completed_depth", false)), "Iterative search publishes a completed depth")
	_check(int(completed.get("completed_depth", 0)) == 2, "Iterative search reaches its deterministic maximum depth")
	var first_action: Action = completed.get("action") as Action
	var repeated: Dictionary = Search.find_best_action_iterative(state, Rules.OPPONENT_OWNER, {"max_depth": 2})
	var repeated_action: Action = repeated.get("action") as Action
	_check(first_action.is_same_as(repeated_action), "Identical completed searches choose the same action")
	_check(int(completed.get("score", 0)) == int(repeated.get("score", 1)), "Identical completed searches return the same score")

	_cancel_after_completed_depth = false
	var partial: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{},
		Callable(self, "_should_cancel_after_depth"),
		Callable(self, "_cancel_on_completed_depth")
	)
	_check(int(partial.get("completed_depth", 0)) == 1, "Cancelled deeper iteration retains the last fully completed depth")
	_check(StringName(partial.get("completion_reason", &"")) == &"cancelled", "Mid-search cancellation reports cancellation")


func _test_search_inherits_summon_reactions() -> void:
	var board: Array = Rules.empty_board()
	board[4] = {
		"card": Catalog.create_instance(&"CangSongYingKe2", Rules.PLAYER_OWNER, &"search_cang"),
		"owner": Rules.PLAYER_OWNER,
	}
	var opponent_card: Dictionary = Rules.make_card("Search Target", "标", [1, 1, 1, 1], [], Rules.OPPONENT_OWNER)
	opponent_card["instance_id"] = &"search_target"
	var player_reply: Dictionary = Rules.make_card("Reply", "续", [1, 1, 1, 1], [], Rules.PLAYER_OWNER)
	player_reply["instance_id"] = &"search_reply"
	var state := State.new(board, [player_reply], [opponent_card], Rules.OPPONENT_OWNER)
	var punished: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, 5, &"search_target")
	)
	var punished_state: State = punished["state"] as State
	_check(
		int((punished_state.board[5] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER,
		"Search fixture resolves the summon reaction through the simulator"
	)
	var first: Action = Search.find_best_action(state, 1, Rules.OPPONENT_OWNER)
	var repeated: Action = Search.find_best_action(state, 1, Rules.OPPONENT_OWNER)
	_check(first.is_same_as(repeated), "Reaction-aware search remains deterministic")
	_check(first.target_index not in [1, 3, 5, 7], "Search avoids a summon square immediately punished by CangSong")


func _test_search_session() -> void:
	var state: State = _make_opening_state()
	var fallback: Action = Simulator.choose_greedy_action(state)
	var fallback_session: Session = Session.new()
	_check(fallback_session.start(state, Rules.OPPONENT_OWNER, 0.0, fallback, {"max_nodes": 1}), "Search session starts one worker")
	await _wait_for_session(fallback_session)
	var fallback_result: Dictionary = fallback_session.finish_and_get_result()
	var fallback_action: Action = fallback_result.get("action") as Action
	_check(bool(fallback_result.get("used_fallback", false)), "Interrupted session selects the retained greedy fallback")
	_check(fallback_action.is_same_as(fallback), "Fallback action preserves full canonical identity")

	var failure_session: Session = Session.new()
	_check(failure_session.start(state, Rules.OPPONENT_OWNER, 1.0, fallback, {"force_failure": true}), "Failure fixture starts its worker")
	await _wait_for_session(failure_session)
	var failure_result: Dictionary = failure_session.finish_and_get_result()
	_check(StringName(failure_result.get("completion_reason", &"")) == &"worker_failed", "Worker failure is reported explicitly")
	_check(bool(failure_result.get("used_fallback", false)), "Worker failure uses the greedy fallback")

	var completed_session: Session = Session.new()
	_check(completed_session.start(state, Rules.OPPONENT_OWNER, 1.0, fallback, {"max_depth": 2}), "Completed fixture starts its worker")
	await _wait_for_session(completed_session)
	var completed_result: Dictionary = completed_session.finish_and_get_result()
	_check(bool(completed_result.get("has_completed_depth", false)), "Worker publishes a completed search depth")
	_check(not bool(completed_result.get("used_fallback", true)), "Completed worker result replaces the fallback")
	_check(not completed_session.is_running(), "Joined session leaves no worker running")

	var cancelled_session: Session = Session.new()
	_check(cancelled_session.start(state, Rules.OPPONENT_OWNER, 10.0, fallback), "Cancellation fixture starts its worker")
	cancelled_session.cancel()
	await _wait_for_session(cancelled_session)
	var cancelled_result: Dictionary = cancelled_session.finish_and_get_result()
	_check(bool(cancelled_result.get("used_fallback", false)), "Cancelled session falls back when no depth completes")
	_check(not cancelled_session.is_running(), "Cancelled session joins without a live worker")


func _cancel_on_completed_depth(_progress: Dictionary) -> void:
	_cancel_after_completed_depth = true


func _should_cancel_after_depth() -> bool:
	return _cancel_after_completed_depth


func _wait_for_session(session: Session) -> void:
	var frames: int = 0
	while not session.is_complete() and frames < 600:
		await process_frame
		frames += 1
	_check(session.is_complete(), "Worker session completes within the test frame bound")


func _make_opening_state() -> State:
	var player_hand: Array = [
		Rules.make_card("Player A", "甲", [3, 6, 2, 5]),
		Rules.make_card("Player B", "乙", [7, 2, 4, 3]),
	]
	var opponent_hand: Array = [
		Rules.make_card("Opponent A", "丙", [4, 4, 5, 2]),
		Rules.make_card("Opponent B", "丁", [6, 3, 3, 6]),
	]
	return State.new(Rules.empty_board(), player_hand, opponent_hand, Rules.OPPONENT_OWNER)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("CHECK_FAILED: %s" % message)
