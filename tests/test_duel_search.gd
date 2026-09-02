extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Search = preload("res://scripts/duel_search.gd")
const Session = preload("res://scripts/duel_search_session.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")
const TurnPlan = preload("res://scripts/duel_turn_plan.gd")

var _checks: int = 0
var _failures: int = 0
var _cancel_checks: int = 0
var _cancel_after_progress: bool = false
var _progress_snapshots: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_production_facade_uses_native_search()
	_test_forced_terminal_score_and_canonical_tie()
	_test_complete_round_result_schema()
	_test_native_progress_is_published_during_search()
	_test_selectable_depth_modes()
	_test_node_limit_and_minimum_depth_guard()
	_test_cancellation_and_deadline_are_hard_stops()
	_test_same_turn_continuation_plan()
	_test_turn_plan_validation()
	_test_search_inherits_summon_reactions()
	await _test_search_session()
	if _failures == 0:
		print("DUEL_SEARCH_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("DUEL_SEARCH_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _test_production_facade_uses_native_search() -> void:
	var state: State = _make_opening_state()
	var production: Dictionary = Search.find_best_action_iterative(state, Rules.OPPONENT_OWNER, {"max_depth": 1})
	var explicit_native: Dictionary = Search.find_best_action_iterative_native(state, Rules.OPPONENT_OWNER, {"max_depth": 1})
	var production_action: Action = production.get("action") as Action
	var native_action: Action = explicit_native.get("action") as Action
	_check(production_action != null and native_action != null, "Both native search entries return an action")
	if production_action == null or native_action == null:
		return
	_check(production_action.is_same_as(native_action), "Production facade selects the explicit native action")
	_check(int(production.get("score", 0)) == int(explicit_native.get("score", 1)), "Production facade returns the native score")
	_check(Simulator.is_action_legal(state, production_action), "Production search returns a legal action")
	var simple: Action = Search.find_best_action(state, 1, Rules.OPPONENT_OWNER)
	_check(simple.is_same_as(production_action), "Simple search facade preserves canonical native identity")


func _test_forced_terminal_score_and_canonical_tie() -> void:
	var forced_board: Array = Rules.empty_board()
	for cell_index: int in range(8):
		var owner_id: int = Rules.PLAYER_OWNER if cell_index < 4 else Rules.OPPONENT_OWNER
		forced_board[cell_index] = _slot(
			Catalog.create_instance(&"TaiZuChangQuan", owner_id, StringName("search_forced_board_%d" % cell_index)),
			owner_id
		)
	var forced := State.new(
		forced_board,
		[],
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"search_forced_winner")],
		Rules.OPPONENT_OWNER
	)
	var forced_result: Dictionary = Search.find_best_action_iterative(forced, Rules.OPPONENT_OWNER, {"max_depth": 1})
	var forced_action: Action = forced_result.get("action") as Action
	_check(forced_action != null, "Forced terminal search returns its only action")
	if forced_action != null:
		_check(forced_action.source_index == 0 and forced_action.target_index == 8, "Forced search fills the only empty cell")
		_check(forced_action.source_instance_id == &"search_forced_winner", "Forced search preserves exact source identity")
	_check(int(forced_result.get("score", 0)) == 1_000_099, "Terminal win score includes ownership margin and action count")

	var tied := State.new(
		Rules.empty_board(),
		[],
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"search_tie_card")],
		Rules.OPPONENT_OWNER
	)
	var first: Dictionary = Search.find_best_action_iterative(tied, Rules.OPPONENT_OWNER, {"max_depth": 1})
	var repeated: Dictionary = Search.find_best_action_iterative(tied, Rules.OPPONENT_OWNER, {"max_depth": 1})
	var first_action: Action = first.get("action") as Action
	var repeated_action: Action = repeated.get("action") as Action
	_check(first_action != null and repeated_action != null, "Canonical tie fixture returns actions")
	if first_action == null or repeated_action == null:
		return
	_check(first_action.target_index == 0, "Equal terminal choices use the lowest canonical action key")
	_check(first_action.is_same_as(repeated_action), "Repeated native tie searches are deterministic")
	_check(int(first.get("score", 0)) == int(repeated.get("score", 1)), "Repeated native tie searches preserve score")


func _test_complete_round_result_schema() -> void:
	_progress_snapshots.clear()
	var result: Dictionary = Search.find_best_action_iterative(
		_make_opening_state(),
		Rules.OPPONENT_OWNER,
		{"max_depth": 1},
		Callable(),
		Callable(self, "_record_progress")
	)
	_check(bool(result.get("has_completed_depth", false)), "Native search publishes a completed round")
	_check(int(result.get("completed_depth", 0)) == 1, "Completed depth uses complete-round units")
	_check(int(result.get("iteration_depth", 0)) == 1, "Result reports the attempted complete-round depth")
	_check(int(result.get("nodes", 0)) > 0, "Result reports visited native nodes")
	_check(int(result.get("generated_actions", 0)) > 0, "Result reports native action generation")
	_check(int(result.get("applied_transitions", 0)) > 0, "Result reports native transitions")
	_check((result.get("depth_snapshots", []) as Array).size() == 1, "Depth-one search retains one completed snapshot")
	_check(_progress_snapshots.size() == 1, "Progress callback receives the completed depth snapshot")
	_check(StringName(result.get("completion_reason", &"")) == &"max_depth", "Maximum depth is reported explicitly")


func _test_native_progress_is_published_during_search() -> void:
	_cancel_after_progress = false
	_progress_snapshots.clear()
	var result: Dictionary = Search.find_best_action_iterative(
		_make_opening_state(),
		Rules.OPPONENT_OWNER,
		{"max_depth": 2},
		Callable(self, "_cancel_after_completed_progress"),
		Callable(self, "_record_progress_and_request_cancel")
	)
	_check(_progress_snapshots.size() == 1, "Native search publishes exactly one live snapshot before cancellation")
	_check(int(result.get("completed_depth", 0)) == 1, "Live depth-one progress can cancel before depth two begins")
	_check(StringName(result.get("completion_reason", &"")) == &"cancelled", "Progress-requested cancellation is reported explicitly")


func _test_selectable_depth_modes() -> void:
	var state: State = _make_opening_state()
	var default_result: Dictionary = Search.find_best_action_iterative(
		state, Rules.OPPONENT_OWNER, {"max_depth": 1}
	)
	var complete_round: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{"max_depth": 1, "depth_mode": &"complete_round"}
	)
	var self_turn_one: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{"max_depth": 1, "depth_mode": &"self_turn"}
	)
	var self_turn_two: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{"max_depth": 2, "depth_mode": &"self_turn"}
	)
	_check(StringName(default_result.get("depth_mode", &"")) == &"complete_round", "Unspecified search depth keeps complete-round semantics")
	_check(StringName(complete_round.get("depth_mode", &"")) == &"complete_round", "Complete-round mode is reported explicitly")
	_check(StringName(self_turn_one.get("depth_mode", &"")) == &"self_turn", "Self-turn mode is reported explicitly")
	_check(int(complete_round.get("owner_turn_boundaries", 0)) == 2, "Complete-round depth one spans two owner-turn boundaries")
	_check(int(self_turn_one.get("owner_turn_boundaries", 0)) == 1, "Self-turn depth one stops after the current owner turn")
	_check(int(self_turn_two.get("owner_turn_boundaries", 0)) == 3, "Self-turn depth two spans current, enemy, and next owner turns")
	var self_turn_snapshots: Array = self_turn_two.get("depth_snapshots", []) as Array
	_check(self_turn_snapshots.size() == 2, "Self-turn depth two retains both completed iterations")
	if self_turn_snapshots.size() == 2:
		_check(int((self_turn_snapshots[0] as Dictionary).get("owner_turn_boundaries", 0)) == 1, "Self-turn depth-one snapshot records one boundary")
		_check(int((self_turn_snapshots[1] as Dictionary).get("owner_turn_boundaries", 0)) == 3, "Self-turn depth-two snapshot records three boundaries")
	var default_action: Action = default_result.get("action") as Action
	var explicit_action: Action = complete_round.get("action") as Action
	_check(default_action != null and explicit_action != null and default_action.is_same_as(explicit_action), "Explicit complete-round mode preserves the default action")
	_check(int(default_result.get("score", 0)) == int(complete_round.get("score", 1)), "Explicit complete-round mode preserves the default score")

	var extra_play_state: State = _make_extra_play_search_state()
	extra_play_state.extra_card_plays_remaining = 2
	var extra_play_result: Dictionary = Search.find_best_action_iterative(
		extra_play_state,
		Rules.OPPONENT_OWNER,
		{"max_depth": 1, "depth_mode": &"self_turn"}
	)
	_check((extra_play_result.get("turn_plan", []) as Array).size() == 2, "Self-turn depth one includes every granted play before the owner turn ends")


func _test_node_limit_and_minimum_depth_guard() -> void:
	var state: State = _make_opening_state()
	var interrupted: Dictionary = Search.find_best_action_iterative(state, Rules.OPPONENT_OWNER, {"max_nodes": 1})
	_check(not bool(interrupted.get("has_completed_depth", true)), "Node interruption publishes no partial round")
	_check(StringName(interrupted.get("completion_reason", &"")) == &"node_limit", "Node interruption reports its reason")
	var protected: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{"max_nodes": 1, "min_completed_depth": 1}
	)
	_check(bool(protected.get("has_completed_depth", false)), "Minimum-depth guard completes round one")
	_check(int(protected.get("completed_depth", 0)) == 1, "Minimum-depth guard stops with a complete round")
	_check(bool(protected.get("minimum_depth_guard_used", false)), "Minimum-depth node overrun is disclosed")
	_check(int(protected.get("nodes", 0)) > 1, "Minimum-depth guard overruns the nominal node budget")


func _test_cancellation_and_deadline_are_hard_stops() -> void:
	_cancel_checks = 0
	var cancelled: Dictionary = Search.find_best_action_iterative(
		_make_opening_state(),
		Rules.OPPONENT_OWNER,
		{"max_depth": 3},
		Callable(self, "_cancel_after_native_entry")
	)
	_check(_cancel_checks >= 2, "Native search polls cancellation inside C++")
	_check(not bool(cancelled.get("has_completed_depth", true)), "Cancellation publishes no partial round")
	_check(StringName(cancelled.get("completion_reason", &"")) == &"cancelled", "Cancellation reports its reason")
	var deadline: Dictionary = Search.find_best_action_iterative(
		_make_opening_state(),
		Rules.OPPONENT_OWNER,
		{"deadline_usec": Time.get_ticks_usec() - 1, "min_completed_depth": 1}
	)
	_check(not bool(deadline.get("has_completed_depth", true)), "Expired deadline overrides the minimum-depth guard")
	_check(StringName(deadline.get("completion_reason", &"")) == &"deadline", "Expired deadline reports its hard stop")


func _test_same_turn_continuation_plan() -> void:
	var state: State = _make_extra_play_search_state()
	state.extra_card_plays_remaining = 2
	var result: Dictionary = Search.find_best_action_iterative(state, Rules.OPPONENT_OWNER, {"max_depth": 1})
	var plan: Array = result.get("turn_plan", []) as Array
	_check(plan.size() == 2, "A completed round retains both same-turn opponent plays")
	if plan.size() != 2:
		return
	var current_state: State = state.duplicate_state()
	for plan_index: int in range(plan.size()):
		var entry: Dictionary = plan[plan_index] as Dictionary
		var action: Action = entry.get("action") as Action
		_check(String(entry.get("state_key", "")) == StateKey.build_compact(current_state), "Plan entry is keyed to its exact pre-action state")
		_check(int(entry.get("owner_turn_serial", -1)) == state.owner_turn_serial, "Plan entry remains in the root owner turn")
		_check(action != null and Simulator.is_action_legal(current_state, action), "Plan entry carries a legal pure-data action")
		if action == null or not Simulator.is_action_legal(current_state, action):
			return
		current_state = Simulator.apply_action(current_state, action).get("state") as State
	_check(current_state.owner_turn_serial > state.owner_turn_serial, "Extra-play plan stops after the owner turn closes")


func _test_turn_plan_validation() -> void:
	var state: State = _make_extra_play_search_state()
	state.extra_card_plays_remaining = 2
	var result: Dictionary = Search.find_best_action_iterative(state, Rules.OPPONENT_OWNER, {"max_depth": 1})
	var selected: Action = result.get("action") as Action
	var remaining: Array[Dictionary] = TurnPlan.remaining_after_selected_action(
		result.get("turn_plan", []) as Array,
		state,
		selected,
		false
	)
	_check(remaining.size() == 1, "Selected root action retains one same-turn continuation")
	if selected == null:
		return
	var shallow_result: Dictionary = result.duplicate(true)
	shallow_result["has_completed_depth"] = true
	shallow_result["completed_depth"] = 1
	shallow_result["used_fallback"] = false
	_check(
		TurnPlan.remaining_after_search_result(
			shallow_result, state, selected, 2
		).is_empty(),
		"Depth-one search result does not retain a same-turn continuation"
	)
	var deep_result: Dictionary = result.duplicate(true)
	deep_result["has_completed_depth"] = true
	deep_result["completed_depth"] = 2
	deep_result["used_fallback"] = false
	_check(
		TurnPlan.remaining_after_search_result(
			deep_result, state, selected, 2
		).size() == 1,
		"Depth-two search result retains its valid same-turn continuation"
	)
	deep_result["used_fallback"] = true
	_check(
		TurnPlan.remaining_after_search_result(
			deep_result, state, selected, 2
		).is_empty(),
		"Fallback result never retains a same-turn continuation at depth two"
	)
	var extra_state: State = Simulator.apply_action(state, selected).get("state") as State
	var taken: Dictionary = TurnPlan.take_next(remaining, extra_state, Rules.OPPONENT_OWNER)
	_check(bool(taken.get("matched", false)), "Exact same-turn state consumes the planned action")
	_check((taken.get("remaining_plan", []) as Array).is_empty(), "Last planned action exhausts the plan")
	var mismatched: State = extra_state.duplicate_state()
	var changed: Dictionary = mismatched.get_hand(Rules.OPPONENT_OWNER)[0] as Dictionary
	changed["ki"] = int(changed.get("ki", 0)) + 1
	var rejected: Dictionary = TurnPlan.take_next(remaining, mismatched, Rules.OPPONENT_OWNER)
	_check(not bool(rejected.get("matched", true)), "Changed state invalidates the continuation")
	_check((rejected.get("remaining_plan", [1]) as Array).is_empty(), "Invalid continuation clears the plan")
	_check(TurnPlan.remaining_after_selected_action(result.get("turn_plan", []) as Array, state, selected, true).is_empty(), "Fallback never retains a searched continuation")


func _test_search_inherits_summon_reactions() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(
		Catalog.create_instance(&"CangSongYingKe2", Rules.PLAYER_OWNER, &"search_cangsong"),
		Rules.PLAYER_OWNER
	)
	var state := State.new(
		board,
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"search_reply")],
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"search_target")],
		Rules.OPPONENT_OWNER
	)
	var punished: State = Simulator.apply_action(state, Action.make_play(0, 5, &"search_target")).get("state") as State
	_check(int((punished.board[5] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER, "Summon reaction flips an adjacent entering enemy")
	var first: Action = Search.find_best_action(state, 1, Rules.OPPONENT_OWNER)
	var repeated: Action = Search.find_best_action(state, 1, Rules.OPPONENT_OWNER)
	_check(first.is_same_as(repeated), "Reaction-aware native search remains deterministic")
	_check(first.target_index not in [1, 3, 5, 7], "Native search avoids a square immediately punished by CangSong")


func _test_search_session() -> void:
	var state: State = _make_opening_state()
	var fallback: Action = Simulator.choose_greedy_action(state)
	var fallback_session: Session = Session.new()
	_check(fallback_session.start(state, Rules.OPPONENT_OWNER, 0.0, fallback, {"max_nodes": 1}), "Native session starts one worker")
	await _wait_for_session(fallback_session)
	var fallback_result: Dictionary = fallback_session.finish_and_get_result()
	_check(bool(fallback_result.get("used_fallback", false)), "Interrupted native session uses its greedy fallback")
	var fallback_action: Action = fallback_result.get("action") as Action
	_check(fallback_action != null and fallback_action.is_same_as(fallback), "Fallback preserves canonical identity")

	var failure_session: Session = Session.new()
	_check(failure_session.start(state, Rules.OPPONENT_OWNER, 1.0, fallback, {"force_failure": true}), "Failure fixture starts its worker")
	await _wait_for_session(failure_session)
	var failure_result: Dictionary = failure_session.finish_and_get_result()
	_check(StringName(failure_result.get("completion_reason", &"")) == &"worker_failed", "Worker failure is explicit")
	_check(bool(failure_result.get("used_fallback", false)), "Worker failure uses the fallback")

	var completed_session: Session = Session.new()
	_check(completed_session.start(state, Rules.OPPONENT_OWNER, 2.0, fallback, {"max_depth": 1}), "Completed native fixture starts its worker")
	await _wait_for_session(completed_session)
	var completed_result: Dictionary = completed_session.finish_and_get_result()
	_check(bool(completed_result.get("has_completed_depth", false)), "Worker publishes a completed native round")
	_check(not bool(completed_result.get("used_fallback", true)), "Completed native result replaces the fallback")
	_check(not completed_session.is_running(), "Joined session leaves no worker running")

	var live_progress_session: Session = Session.new()
	_check(live_progress_session.start(state, Rules.OPPONENT_OWNER, 5.0, fallback, {"max_depth": 99}), "Live-progress fixture starts its worker")
	var observed_live_depth: int = 0
	var live_progress_frames: int = 0
	while not live_progress_session.is_complete() and live_progress_frames < 600:
		observed_live_depth = int(live_progress_session.get_progress().get("completed_depth", 0))
		if observed_live_depth > 0:
			break
		await process_frame
		live_progress_frames += 1
	_check(observed_live_depth > 0, "Worker publishes a completed depth while the search is still running")
	_check(live_progress_session.is_running(), "Live completed-depth progress precedes the final worker result")
	live_progress_session.cancel_and_join()

	var cancelled_session: Session = Session.new()
	_check(cancelled_session.start(state, Rules.OPPONENT_OWNER, 10.0, fallback, {"max_depth": 5}), "Cancellation fixture starts its worker")
	cancelled_session.cancel()
	await _wait_for_session(cancelled_session)
	var cancelled_result: Dictionary = cancelled_session.finish_and_get_result()
	_check(bool(cancelled_result.get("used_fallback", false)), "Cancelled session falls back before a depth completes")
	_check((cancelled_result.get("turn_plan", []) as Array).is_empty(), "Cancelled fallback has no partial plan")
	_check(not cancelled_session.is_running(), "Cancelled session joins without a live worker")


func _record_progress(progress: Dictionary) -> void:
	_progress_snapshots.append(progress.duplicate(true))


func _record_progress_and_request_cancel(progress: Dictionary) -> void:
	_progress_snapshots.append(progress.duplicate(true))
	_cancel_after_progress = true


func _cancel_after_completed_progress() -> bool:
	return _cancel_after_progress


func _cancel_after_native_entry() -> bool:
	_cancel_checks += 1
	return _cancel_checks >= 2


func _wait_for_session(session: Session) -> void:
	var frames: int = 0
	while not session.is_complete() and frames < 600:
		await process_frame
		frames += 1
	_check(session.is_complete(), "Worker session completes within the frame bound")


func _make_opening_state() -> State:
	return State.new(
		Rules.empty_board(),
		[
			Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"search_player_a"),
			Catalog.create_instance(&"TuNaShu1", Rules.PLAYER_OWNER, &"search_player_b"),
		],
		[
			Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"search_opponent_a"),
			Catalog.create_instance(&"TuNaShu1", Rules.OPPONENT_OWNER, &"search_opponent_b"),
		],
		Rules.OPPONENT_OWNER
	)


func _make_extra_play_search_state() -> State:
	return State.new(
		Rules.empty_board(),
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"search_player_reply")],
		[
			Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"search_extra_first"),
			Catalog.create_instance(&"TuNaShu1", Rules.OPPONENT_OWNER, &"search_extra_second"),
		],
		Rules.OPPONENT_OWNER
	)


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
