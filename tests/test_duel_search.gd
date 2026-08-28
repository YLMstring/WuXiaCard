extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Evaluator = preload("res://scripts/duel_evaluator.gd")
const EvaluationCache = preload("res://scripts/duel_evaluation_cache.gd")
const Profile = preload("res://scripts/duel_search_profile.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Search = preload("res://scripts/duel_search.gd")
const SearchOrdering = preload("res://scripts/duel_search_ordering.gd")
const SearchTactics = preload("res://scripts/duel_search_tactics.gd")
const Session = preload("res://scripts/duel_search_session.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")
const TurnPlan = preload("res://scripts/duel_turn_plan.gd")

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
	_test_search_profiles_and_stats()
	_test_action_ordering()
	_test_lazy_transition_equivalence()
	_test_pvs_equivalence()
	_test_tactical_transition_classification()
	_test_forced_loss_does_not_use_production_tactical_extension()
	_test_tactical_extension_bounds()
	_test_leaf_evaluation_cache()
	_test_evaluator_terminal_priority()
	_test_enhanced_evaluator_features()
	_test_complete_round_depth_semantics()
	_test_same_turn_continuation_plan()
	_test_turn_plan_validation()
	_test_iterative_depth_and_interruption()
	_test_minimum_completed_depth_guard()
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


func _test_search_profiles_and_stats() -> void:
	var baseline: Dictionary = Profile.normalize({"profile": &"baseline"})
	_check(StringName(baseline.get("name", &"")) == &"baseline", "Baseline search profile is selectable")
	_check(not bool(baseline.get("use_lazy_transitions", true)), "Baseline keeps eager transitions")
	_check(not bool(baseline.get("use_pvs", true)), "Baseline disables PVS")
	_check(not bool(baseline.get("use_tactical_extension", true)), "Baseline disables tactical extension")

	var enhanced: Dictionary = Profile.normalize({})
	_check(StringName(enhanced.get("name", &"")) == &"enhanced", "Enhanced is the deterministic default profile")
	_check(bool(enhanced.get("use_lazy_transitions", false)), "Enhanced enables lazy transitions")
	_check(not bool(enhanced.get("use_pvs", true)), "Production Enhanced defaults to LazyOnly without PVS")
	_check(not bool(enhanced.get("use_tactical_extension", true)), "Enhanced disables tactical extension by default")
	_check(int(enhanced.get("max_tactical_depth", -1)) == 2, "Enhanced tactical depth defaults to two")
	_check(int(enhanced.get("tactical_scan_limit", -1)) == 12, "Enhanced tactical scan defaults to twelve")
	_check(int(enhanced.get("tactical_action_limit", -1)) == 4, "Enhanced tactical action limit defaults to four")
	var pvs_opt_in: Dictionary = Profile.normalize({
		"profile": &"enhanced",
		"use_pvs": true,
	})
	_check(bool(pvs_opt_in.get("use_pvs", false)), "PVS remains available by explicit opt-in")
	var tactical_opt_in: Dictionary = Profile.normalize({
		"profile": &"enhanced",
		"use_tactical_extension": true,
	})
	_check(bool(tactical_opt_in.get("use_tactical_extension", false)), "Enhanced tactical extension remains available by explicit opt-in")

	var normalized: Dictionary = Profile.normalize({
		"profile": &"unknown",
		"evaluator_profile": &"unknown",
		"max_tactical_depth": -4,
		"tactical_scan_limit": -3,
		"tactical_action_limit": -2,
	})
	_check(StringName(normalized.get("name", &"")) == &"enhanced", "Unknown profiles fall back deterministically")
	_check(not bool(normalized.get("requested_profile_valid", true)), "Unknown profiles are reported as invalid")
	_check(
		StringName(normalized.get("evaluator_profile", &"")) == &"baseline",
		"Unknown evaluator profiles retain the production baseline evaluator"
	)
	_check(int(normalized.get("max_tactical_depth", -1)) == 0, "Negative tactical depth is clamped")
	_check(int(normalized.get("tactical_scan_limit", -1)) == 0, "Negative tactical scan limit is clamped")
	_check(int(normalized.get("tactical_action_limit", -1)) == 0, "Negative tactical action limit is clamped")

	var result: Dictionary = Search.find_best_action_iterative(
		_make_opening_state(),
		Rules.OPPONENT_OWNER,
		{"max_depth": 1, "profile": &"baseline"}
	)
	for field: String in [
		"max_tactical_depth",
		"generated_actions",
		"applied_transitions",
		"pvs_probes",
		"pvs_researches",
		"evaluation_cache_hits",
		"iteration_depth",
		"iteration_nodes",
		"root_actions_total",
		"root_actions_started",
		"root_actions_completed",
		"current_root_action_nodes",
		"time_order_usec",
		"time_apply_usec",
		"time_key_usec",
		"time_evaluate_usec",
	]:
		_check(result.has(field), "Search result includes %s" % field)
	_check(
		int(result.get("generated_actions", -1)) == int(result.get("applied_transitions", -2)),
		"Baseline eager search applies every generated action"
	)
	_check(int(result.get("pvs_probes", -1)) == 0, "Baseline reports zero PVS probes")
	_check(int(result.get("evaluation_cache_hits", -1)) == 0, "Baseline reports zero evaluation-cache hits")


func _test_action_ordering() -> void:
	var state: State = _make_opening_state()
	var actions: Array[Action] = Simulator.get_legal_actions(state)
	var pv_action: Action = actions[3]
	var tt_action: Action = actions[2]
	var history_action: Action = actions[1]
	var history: Dictionary = {SearchOrdering.history_key(history_action, state): 999_999}
	var ordered: Array[Action] = SearchOrdering.order_actions(
		state,
		actions,
		pv_action.canonical_key(),
		tt_action.canonical_key(),
		history
	)
	_check(ordered[0].is_same_as(pv_action), "Previous principal variation has first ordering priority")
	_check(ordered[1].is_same_as(tt_action), "Transposition-table best action has second ordering priority")
	_check(ordered[2].is_same_as(history_action), "History score follows PV and TT priorities")

	var structurally_same_a: Action = Action.make_play(0, 0, &"first_runtime_copy")
	var structurally_same_b: Action = Action.make_play(0, 0, &"second_runtime_copy")
	_check(
		SearchOrdering.history_key(structurally_same_a) == SearchOrdering.history_key(structurally_same_b),
		"History keys omit exact runtime identity"
	)
	var different_source_state: State = state.duplicate_state()
	different_source_state.get_hand(different_source_state.active_player)[0]["powers"] = [9, 9, 9, 9]
	_check(
		SearchOrdering.history_key(actions[0], state)
		!= SearchOrdering.history_key(actions[0], different_source_state),
		"History keys separate generic source-card shapes without using card identity"
	)
	var state_key_before: String = StateKey.build(state)
	SearchOrdering.structural_score(state, actions[0])
	_check(StateKey.build(state) == state_key_before, "Structural ordering never applies a transition")
	var tactical_board: Array = Rules.empty_board()
	var weak_enemy: Dictionary = Rules.make_card("Weak", "弱", [0, 0, 0, 0], [], Rules.PLAYER_OWNER)
	weak_enemy["instance_id"] = &"ordering_weak"
	tactical_board[4] = {"owner": Rules.PLAYER_OWNER, "card": weak_enemy}
	var strong_card: Dictionary = Rules.make_card("Strong", "强", [8, 8, 8, 8], [], Rules.OPPONENT_OWNER)
	strong_card["instance_id"] = &"ordering_strong"
	var tactical_state := State.new(tactical_board, [], [strong_card], Rules.OPPONENT_OWNER)
	_check(
		SearchOrdering.structural_score(
			tactical_state,
			Action.make_play(0, 1, &"ordering_strong")
		)
		> SearchOrdering.structural_score(
			tactical_state,
			Action.make_play(0, 8, &"ordering_strong")
		),
		"Generic structural ordering prioritizes a standard play with more legal flips"
	)
	var symmetric_actions: Array[Action] = [
		Action.make_play(0, 2, actions[0].source_instance_id),
		Action.make_play(0, 0, actions[0].source_instance_id),
	]
	var symmetric_order: Array[Action] = SearchOrdering.order_actions(
		state,
		symmetric_actions,
		"",
		"",
		{}
	)
	_check(
		symmetric_order[0].canonical_key() < symmetric_order[1].canonical_key(),
		"Equal structural priorities use canonical deterministic order"
	)


func _test_lazy_transition_equivalence() -> void:
	var state: State = _make_opening_state()
	var baseline: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{"max_depth": 3, "profile": &"baseline"}
	)
	var enhanced: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{
			"max_depth": 3,
			"profile": &"enhanced",
			"use_pvs": false,
			"use_tactical_extension": false,
			"use_evaluation_cache": false,
			"evaluator_profile": &"baseline",
		}
	)
	var baseline_action: Action = baseline.get("action") as Action
	var enhanced_action: Action = enhanced.get("action") as Action
	_check(int(baseline.get("score", 1)) == int(enhanced.get("score", 0)), "Lazy search preserves the fixed complete-round-depth minimax score")
	_check(baseline_action.is_same_as(enhanced_action), "Lazy search preserves the fixed complete-round-depth root action")
	_check(
		int(baseline.get("generated_actions", -1)) == int(baseline.get("applied_transitions", -2)),
		"Baseline remains an eager transition reference"
	)
	_check(
		int(enhanced.get("applied_transitions", 0)) < int(enhanced.get("generated_actions", 0)),
		"Lazy search skips transition work after cutoffs"
	)


func _test_pvs_equivalence() -> void:
	var state: State = _make_opening_state()
	var lazy_only: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{
			"max_depth": 3,
			"profile": &"enhanced",
			"use_pvs": false,
			"use_tactical_extension": false,
			"use_evaluation_cache": false,
		}
	)
	var with_pvs: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{
			"max_depth": 3,
			"profile": &"enhanced",
			"use_pvs": true,
			"use_tactical_extension": false,
			"use_evaluation_cache": false,
		}
	)
	var lazy_action: Action = lazy_only.get("action") as Action
	var pvs_action: Action = with_pvs.get("action") as Action
	_check(int(lazy_only.get("score", 1)) == int(with_pvs.get("score", 0)), "PVS preserves the fixed complete-round-depth minimax score")
	_check(lazy_action.is_same_as(pvs_action), "PVS preserves the fixed complete-round-depth root action")
	_check(int(with_pvs.get("pvs_probes", 0)) > 0, "PVS probes later ordered children with a narrow window")
	_check(int(with_pvs.get("pvs_researches", -1)) >= 0, "PVS reports full-window researches")
	_check(int(lazy_only.get("pvs_probes", -1)) == 0, "PVS-disabled search reports zero probes")


func _test_tactical_transition_classification() -> void:
	var before: State = _make_opening_state()
	var after: State = before.duplicate_state()
	var quiet: Dictionary = {
		"state": after,
		"captures": [],
		"exiles": [],
		"events": [{"type": &"card_drawn"}],
	}
	_check(not SearchTactics.is_volatile(before, quiet), "A pure draw is quiet")
	quiet["events"] = [{"type": &"card_moved"}]
	_check(not SearchTactics.is_volatile(before, quiet), "A pure movement is quiet")

	var capture: Dictionary = quiet.duplicate(true)
	capture["captures"] = [4]
	_check(SearchTactics.is_volatile(before, capture), "A real capture is volatile")
	var exile: Dictionary = quiet.duplicate(true)
	exile["exiles"] = [4]
	_check(SearchTactics.is_volatile(before, exile), "A real exile is volatile")
	var extra_play: Dictionary = quiet.duplicate(true)
	extra_play["events"] = [{"type": &"extra_card_play_granted"}]
	_check(SearchTactics.is_volatile(before, extra_play), "An extra card play is volatile")
	var resummon: Dictionary = quiet.duplicate(true)
	resummon["events"] = [{"type": &"card_summoned"}]
	_check(SearchTactics.is_volatile(before, resummon), "A generated summon is volatile")

	var ownership_after: State = before.duplicate_state()
	var ownership_card: Dictionary = Rules.make_card("Owner Shift", "转", [1, 1, 1, 1])
	ownership_card["instance_id"] = &"owner_shift"
	before.board[4] = {"owner": Rules.PLAYER_OWNER, "card": ownership_card}
	ownership_after = before.duplicate_state()
	(ownership_after.board[4] as Dictionary)["owner"] = Rules.OPPONENT_OWNER
	_check(
		SearchTactics.is_volatile(before, {
			"state": ownership_after,
			"captures": [],
			"exiles": [],
			"events": [],
		}),
		"A generic ownership change is volatile even without a presentation event"
	)


func _test_tactical_extension_bounds() -> void:
	var board: Array = Rules.empty_board()
	for cell_index: int in range(5):
		var owner_id: int = Rules.PLAYER_OWNER if cell_index % 2 == 0 else Rules.OPPONENT_OWNER
		var board_card: Dictionary = Rules.make_card("Board %d" % cell_index, "局", [1, 1, 1, 1], [], owner_id)
		board_card["instance_id"] = StringName("tactical_board_%d" % cell_index)
		board[cell_index] = {"owner": owner_id, "card": board_card}
	var player_card: Dictionary = Rules.make_card("Player Fill", "填", [2, 2, 2, 2], [], Rules.PLAYER_OWNER)
	player_card["instance_id"] = &"tactical_player"
	var opponent_card: Dictionary = Rules.make_card("Opponent Fill", "终", [9, 9, 9, 9], [], Rules.OPPONENT_OWNER)
	opponent_card["instance_id"] = &"tactical_opponent"
	var player_reserve: Dictionary = Rules.make_card("Player Reserve", "续", [2, 2, 2, 2], [], Rules.PLAYER_OWNER)
	player_reserve["instance_id"] = &"tactical_player_reserve"
	var opponent_reserve: Dictionary = Rules.make_card("Opponent Reserve", "续", [9, 9, 9, 9], [], Rules.OPPONENT_OWNER)
	opponent_reserve["instance_id"] = &"tactical_opponent_reserve"
	var state := State.new(
		board,
		[player_card, player_reserve],
		[opponent_card, opponent_reserve],
		Rules.PLAYER_OWNER
	)
	var result: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.PLAYER_OWNER,
		{
			"max_depth": 1,
			"profile": &"enhanced",
			"use_tactical_extension": true,
			"max_tactical_depth": 2,
			"tactical_scan_limit": 12,
			"tactical_action_limit": 4,
		}
	)
	_check(int(result.get("max_tactical_depth", 0)) > 0, "Volatile leaf actions extend beyond the ordinary horizon")
	_check(int(result.get("max_tactical_depth", 99)) <= 2, "Tactical extension never exceeds two plies")
	_check(int(result.get("tactical_candidates_scanned", 0)) > 0, "Tactical extension reports scanned candidates")
	_check(
		int(result.get("tactical_actions_searched", 0)) <= int(result.get("tactical_candidates_scanned", 0)),
		"Tactical search never exceeds its scanned candidates"
	)
	_check(int(result.get("max_tactical_candidates_per_node", 99)) <= 12, "Tactical candidate scan respects its per-node cap")
	_check(int(result.get("max_tactical_actions_per_node", 99)) <= 4, "Tactical volatile-action search respects its per-node cap")
	var disabled: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.PLAYER_OWNER,
		{
			"max_depth": 1,
			"profile": &"enhanced",
			"use_tactical_extension": false,
		}
	)
	_check(int(disabled.get("max_tactical_depth", -1)) == 0, "Disabled tactical search remains at the ordinary horizon")


func _test_forced_loss_does_not_use_production_tactical_extension() -> void:
	var board: Array = Rules.empty_board()
	for cell_index: int in range(8):
		var owner_id: int = Rules.PLAYER_OWNER if cell_index in [0, 2, 4] else Rules.OPPONENT_OWNER
		var board_card: Dictionary = Rules.make_card(
			"Forced Board %d" % cell_index,
			"迫",
			[1, 1, 1, 1],
			[],
			owner_id
		)
		board_card["instance_id"] = StringName("forced_board_%d" % cell_index)
		board[cell_index] = {"owner": owner_id, "card": board_card}
	var forced_card: Dictionary = Rules.make_card(
		"Forced Loss",
		"败",
		[0, 0, 0, 0],
		[],
		Rules.PLAYER_OWNER
	)
	forced_card["instance_id"] = &"forced_loss_card"
	var state := State.new(board, [forced_card], [], Rules.PLAYER_OWNER)
	var legal_actions: Array[Action] = Simulator.get_legal_actions(state)
	_check(legal_actions.size() == 1, "Forced-loss fixture has exactly one legal action")
	if legal_actions.size() != 1:
		return
	var stand_pat_score: int = Evaluator.evaluate(state, Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action(state, legal_actions[0])
	var forced_state: State = transition.get("state") as State
	_check(Simulator.is_terminal(forced_state), "The only legal action ends the duel")
	var forced_score: int = Evaluator.evaluate(forced_state, Rules.PLAYER_OWNER)
	_check(forced_score < stand_pat_score, "The mandatory action is a loss that stand-pat would conceal")
	var enhanced: Dictionary = Profile.normalize({"profile": &"enhanced"})
	_check(
		not bool(enhanced.get("use_tactical_extension", true)),
		"Production Enhanced cannot retain stand-pat instead of the mandatory loss"
	)


func _test_leaf_evaluation_cache() -> void:
	var state: State = _make_opening_state()
	var cache: Dictionary = {}
	var first: Dictionary = EvaluationCache.lookup_or_evaluate(
		cache,
		state,
		Rules.PLAYER_OWNER,
		&"baseline"
	)
	var repeated: Dictionary = EvaluationCache.lookup_or_evaluate(
		cache,
		state,
		Rules.PLAYER_OWNER,
		&"baseline"
	)
	_check(not bool(first.get("hit", true)), "First leaf evaluation populates the cache")
	_check(bool(repeated.get("hit", false)), "Repeated leaf evaluation hits the cache")
	_check(int(first.get("score", 1)) == int(repeated.get("score", 0)), "Cached evaluation preserves the exact score")
	var other_owner: Dictionary = EvaluationCache.lookup_or_evaluate(
		cache,
		state,
		Rules.OPPONENT_OWNER,
		&"baseline"
	)
	_check(not bool(other_owner.get("hit", true)), "Root owner participates in the evaluation cache key")
	var other_profile: Dictionary = EvaluationCache.lookup_or_evaluate(
		cache,
		state,
		Rules.PLAYER_OWNER,
		&"enhanced"
	)
	_check(not bool(other_profile.get("hit", true)), "Evaluator profile participates in the cache key")
	var fresh_cache: Dictionary = {}
	var next_search: Dictionary = EvaluationCache.lookup_or_evaluate(
		fresh_cache,
		state,
		Rules.PLAYER_OWNER,
		&"baseline"
	)
	_check(not bool(next_search.get("hit", true)), "A new top-level search starts with an empty evaluation cache")

	var disabled: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{
			"max_depth": 2,
			"profile": &"enhanced",
			"use_evaluation_cache": false,
			"use_tactical_extension": false,
		}
	)
	_check(int(disabled.get("evaluation_cache_hits", -1)) == 0, "Cache-disabled search reports zero evaluation hits")


func _test_evaluator_terminal_priority() -> void:
	var board: Array = Rules.empty_board()
	for index: int in range(9):
		var owner_id: int = Rules.PLAYER_OWNER if index < 5 else Rules.OPPONENT_OWNER
		board[index] = {"card": Rules.make_card("Card%d" % index, "牌", [1, 1, 1, 1]), "owner": owner_id}
	var state := State.new(board, [], [], Rules.PLAYER_OWNER)
	_check(Simulator.is_terminal(state), "Full evaluator fixture is terminal")
	_check(Evaluator.evaluate(state, Rules.PLAYER_OWNER) >= Evaluator.WIN_SCORE, "Terminal victory outranks heuristic scores")
	_check(Evaluator.evaluate(state, Rules.OPPONENT_OWNER) <= -Evaluator.WIN_SCORE, "Terminal loss outranks heuristic scores")


func _test_enhanced_evaluator_features() -> void:
	var no_use_card: Dictionary = Rules.make_card("Stored Ki", "气", [2, 2, 2, 2], [], Rules.PLAYER_OWNER)
	no_use_card["instance_id"] = &"eval_no_use"
	no_use_card["ki"] = 2
	var usable_card: Dictionary = no_use_card.duplicate(true)
	usable_card["instance_id"] = &"eval_usable"
	usable_card["active_abilities"] = [{
		"activation": {
			"target_rule": Catalog.TARGET_ADJACENT_EMPTY_BOARD,
			"costs": [{"type": Catalog.ACTION_SPEND_KI, "amount": 1}],
			"actions": [],
		},
	}]
	var opponent_card: Dictionary = Rules.make_card("Opponent", "敌", [2, 2, 2, 2], [], Rules.OPPONENT_OWNER)
	opponent_card["instance_id"] = &"eval_opponent"
	var no_use_board: Array = Rules.empty_board()
	no_use_board[4] = {"owner": Rules.PLAYER_OWNER, "card": no_use_card}
	no_use_board[0] = {"owner": Rules.OPPONENT_OWNER, "card": opponent_card}
	var usable_board: Array = no_use_board.duplicate(true)
	usable_board[4] = {"owner": Rules.PLAYER_OWNER, "card": usable_card}
	var reserve: Dictionary = Rules.make_card("Reserve", "续", [1, 1, 1, 1], [], Rules.PLAYER_OWNER)
	reserve["instance_id"] = &"eval_reserve"
	var no_use_state := State.new(no_use_board, [reserve], [], Rules.PLAYER_OWNER)
	var usable_state := State.new(usable_board, [reserve], [], Rules.PLAYER_OWNER)
	_check(
		Evaluator.evaluate(usable_state, Rules.PLAYER_OWNER, &"enhanced")
		> Evaluator.evaluate(no_use_state, Rules.PLAYER_OWNER, &"enhanced"),
		"Enhanced evaluation values ki that has a generic spending path"
	)

	var early_state: State = usable_state.duplicate_state()
	early_state.turn_count = 5
	var late_state: State = usable_state.duplicate_state()
	late_state.turn_count = 95
	_check(
		Evaluator.endgame_pressure(late_state) > Evaluator.endgame_pressure(early_state),
		"Endgame pressure rises near the action boundary"
	)
	_check(
		Evaluator.attack_potential(usable_state, Rules.PLAYER_OWNER) >= 0,
		"Attack structure is measured through generic rules"
	)
	var enhanced_score: int = Evaluator.evaluate(usable_state, Rules.PLAYER_OWNER, &"enhanced")
	_check(absi(enhanced_score) < Evaluator.WIN_SCORE, "Nonterminal enhanced evaluation remains below terminal scores")


func _test_complete_round_depth_semantics() -> void:
	var state: State = _make_opening_state()
	var expected: Dictionary = _bruteforce_complete_round_depth_one(
		state,
		Rules.OPPONENT_OWNER
	)
	var result: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{"max_depth": 1, "profile": &"enhanced"}
	)
	var expected_action: Action = expected.get("action") as Action
	var actual_action: Action = result.get("action") as Action
	_check(
		int(result.get("score", 0)) == int(expected.get("score", 1)),
		"Complete-round depth one matches an independent two-owner-turn minimax score"
	)
	_check(
		actual_action != null
		and expected_action != null
		and actual_action.is_same_as(expected_action),
		"Complete-round depth one matches the independent minimax action"
	)
	_check(
		int(result.get("completed_depth", 0)) == 1,
		"Completed depth is reported in complete-round units"
	)
	var legacy_action_depth_four: Dictionary = _bruteforce_fixed_action_depth(
		state,
		Rules.OPPONENT_OWNER,
		4
	)
	var complete_round_depth_two: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{"max_depth": 2, "profile": &"baseline"}
	)
	var legacy_action: Action = legacy_action_depth_four.get("action") as Action
	var round_two_action: Action = complete_round_depth_two.get("action") as Action
	_check(
		int(complete_round_depth_two.get("score", 0))
		== int(legacy_action_depth_four.get("score", 1)),
		"Quiet complete-round depth two matches the former action-depth-four score"
	)
	_check(
		round_two_action != null
		and legacy_action != null
		and round_two_action.is_same_as(legacy_action),
		"Quiet complete-round depth two matches the former action-depth-four action"
	)

	var empty_opponent_state: State = _make_empty_opponent_round_state()
	var first_action: Action = Simulator.get_legal_actions(empty_opponent_state)[0]
	var empty_transition: Dictionary = Simulator.apply_action(empty_opponent_state, first_action)
	var after_empty: State = empty_transition.get("state") as State
	_check(
		after_empty.owner_turn_serial - empty_opponent_state.owner_turn_serial >= 2,
		"One authoritative transition can complete the current turn and an empty opponent turn"
	)
	_check(
		after_empty.active_player == empty_opponent_state.active_player,
		"Automatic empty-turn advancement returns control without adding a search branch"
	)


func _test_same_turn_continuation_plan() -> void:
	var state: State = _make_extra_play_search_state()
	var result: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{"max_depth": 1, "profile": &"enhanced"}
	)
	var plan: Array = result.get("turn_plan", []) as Array
	_check(plan.size() == 2, "A completed round retains both same-turn opponent plays")
	if plan.size() != 2:
		return
	var current_state: State = state.duplicate_state()
	for plan_index: int in range(plan.size()):
		var entry: Dictionary = plan[plan_index] as Dictionary
		var action: Action = entry.get("action") as Action
		_check(
			String(entry.get("state_key", "")) == StateKey.build_compact(current_state),
			"Turn-plan entry %d is keyed to its exact pre-action state" % plan_index
		)
		_check(
			int(entry.get("owner_turn_serial", -1)) == state.owner_turn_serial,
			"Turn-plan entry %d remains inside the root owner turn" % plan_index
		)
		_check(
			action != null and Simulator.is_action_legal(current_state, action),
			"Turn-plan entry %d carries a legal pure-data action" % plan_index
		)
		if action == null or not Simulator.is_action_legal(current_state, action):
			return
		var transition: Dictionary = Simulator.apply_action(current_state, action)
		current_state = transition.get("state") as State
	_check(
		current_state.owner_turn_serial > state.owner_turn_serial,
		"The retained extra-play sequence stops after the owner turn closes"
	)


func _test_turn_plan_validation() -> void:
	var state: State = _make_extra_play_search_state()
	var result: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{"max_depth": 1, "profile": &"enhanced"}
	)
	var selected: Action = result.get("action") as Action
	var remaining: Array[Dictionary] = TurnPlan.remaining_after_selected_action(
		result.get("turn_plan", []) as Array,
		state,
		selected,
		false
	)
	_check(
		remaining.size() == 1,
		"Selecting the searched root action retains one extra-play continuation"
	)
	var transition: Dictionary = Simulator.apply_action(state, selected)
	var extra_state: State = transition.get("state") as State
	var taken: Dictionary = TurnPlan.take_next(
		remaining,
		extra_state,
		Rules.OPPONENT_OWNER
	)
	_check(
		bool(taken.get("matched", false)),
		"Exact same-turn state consumes the planned extra action"
	)
	_check(
		(taken.get("remaining_plan", []) as Array).is_empty(),
		"Consuming the last planned action exhausts the plan"
	)

	var mismatched_state: State = extra_state.duplicate_state()
	var changed_card: Dictionary = (
		mismatched_state.get_hand(Rules.OPPONENT_OWNER)[0] as Dictionary
	)
	changed_card["ki"] = int(changed_card.get("ki", 0)) + 1
	var rejected: Dictionary = TurnPlan.take_next(
		remaining,
		mismatched_state,
		Rules.OPPONENT_OWNER
	)
	_check(
		not bool(rejected.get("matched", true)),
		"A changed exact state invalidates the continuation"
	)
	_check(
		(rejected.get("remaining_plan", [1]) as Array).is_empty(),
		"Invalid continuation clears every remaining action"
	)
	_check(
		TurnPlan.remaining_after_selected_action(
			result.get("turn_plan", []) as Array,
			state,
			selected,
			true
		).is_empty(),
		"A greedy fallback never retains a searched continuation"
	)


func _test_iterative_depth_and_interruption() -> void:
	var state: State = _make_opening_state()
	var interrupted: Dictionary = Search.find_best_action_iterative(state, Rules.OPPONENT_OWNER, {"max_nodes": 1})
	_check(not bool(interrupted.get("has_completed_depth", true)), "Interrupted depth one publishes no partial result")
	_check(StringName(interrupted.get("completion_reason", &"")) == &"node_limit", "Node-limited interruption reports its completion reason")

	var completed: Dictionary = Search.find_best_action_iterative(state, Rules.OPPONENT_OWNER, {"max_depth": 2})
	_check(bool(completed.get("has_completed_depth", false)), "Iterative search publishes a completed depth")
	_check(int(completed.get("completed_depth", 0)) == 2, "Iterative search reaches its deterministic maximum depth")
	_check(int(completed.get("iteration_depth", 0)) == 2, "Search reports the last attempted iteration depth")
	_check(int(completed.get("iteration_nodes", 0)) > 0, "Search reports nodes spent in the last iteration")
	_check(
		int(completed.get("root_actions_completed", -1))
		== int(completed.get("root_actions_total", -2)),
		"A completed iteration reports every root action complete"
	)
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
	_check(int(partial.get("iteration_depth", 0)) == 2, "Cancelled search reports the interrupted iteration depth")
	_check(
		int(partial.get("root_actions_started", -1)) >= int(partial.get("root_actions_completed", -1)),
		"Interrupted root progress never completes more actions than it starts"
	)


func _test_minimum_completed_depth_guard() -> void:
	var state: State = _make_opening_state()
	var ordinary: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{"max_nodes": 1}
	)
	_check(
		not bool(ordinary.get("has_completed_depth", true)),
		"Default node limit still interrupts depth one"
	)
	_check(
		int(ordinary.get("min_completed_depth", -1)) == 0,
		"Missing minimum completed depth normalizes to zero"
	)
	_check(
		not bool(ordinary.get("minimum_depth_guard_used", true)),
		"Default node limit does not report minimum-depth guard use"
	)

	var protected: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{"max_nodes": 1, "min_completed_depth": 1}
	)
	_check(
		bool(protected.get("has_completed_depth", false))
		and int(protected.get("completed_depth", 0)) == 1,
		"Minimum-depth guard publishes a complete depth one"
	)
	_check(
		bool(protected.get("minimum_depth_guard_used", false)),
		"Crossing the nominal node limit during protected depth is reported"
	)
	_check(
		int(protected.get("nodes_over_limit", 0))
		== int(protected.get("nodes", 0)) - 1,
		"Protected search reports exact total node overrun"
	)
	_check(
		int(protected.get("iteration_depth", 0)) == 2
		and int(protected.get("iteration_nodes", -1)) == 0
		and int(protected.get("root_actions_started", -1)) == 0,
		"Search stops before exploring depth two when protected depth one exceeded the limit"
	)

	var depth_one: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{"max_depth": 1}
	)
	var depth_one_nodes: int = int(depth_one.get("nodes", 0))
	var shared_budget: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{
			"max_nodes": depth_one_nodes + 1,
			"min_completed_depth": 1,
		}
	)
	_check(
		int(shared_budget.get("completed_depth", 0)) == 1
		and int(shared_budget.get("nodes", 0)) >= depth_one_nodes + 1,
		"Depth two starts below the shared node limit without resetting depth-one nodes"
	)
	_check(
		not bool(shared_budget.get("minimum_depth_guard_used", true))
		and int(shared_budget.get("nodes_over_limit", -1)) == 0,
		"Reaching the limit after protected depth does not count as guard use or overrun"
	)

	var cancelled: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{"max_nodes": 1, "min_completed_depth": 1},
		Callable(self, "_always_cancel")
	)
	_check(
		not bool(cancelled.get("has_completed_depth", true))
		and StringName(cancelled.get("completion_reason", &"")) == &"cancelled",
		"Cancellation remains a hard stop during protected depth one"
	)
	var deadline: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{
			"max_nodes": 1,
			"min_completed_depth": 1,
			"deadline_usec": 1,
		}
	)
	_check(
		not bool(deadline.get("has_completed_depth", true))
		and StringName(deadline.get("completion_reason", &"")) == &"deadline",
		"Deadline remains a hard stop during protected depth one"
	)
	var normalized: Dictionary = Search.find_best_action_iterative(
		state,
		Rules.OPPONENT_OWNER,
		{"max_nodes": 1, "min_completed_depth": -5}
	)
	_check(
		int(normalized.get("min_completed_depth", -1)) == 0,
		"Negative minimum completed depth clamps to zero"
	)


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
	_check(not (completed_result.get("turn_plan", []) as Array).is_empty(), "Worker transports the completed turn plan")
	_check(not completed_session.is_running(), "Joined session leaves no worker running")

	var cancelled_session: Session = Session.new()
	_check(cancelled_session.start(state, Rules.OPPONENT_OWNER, 10.0, fallback), "Cancellation fixture starts its worker")
	cancelled_session.cancel()
	await _wait_for_session(cancelled_session)
	var cancelled_result: Dictionary = cancelled_session.finish_and_get_result()
	_check(bool(cancelled_result.get("used_fallback", false)), "Cancelled session falls back when no depth completes")
	_check((cancelled_result.get("turn_plan", []) as Array).is_empty(), "Fallback results never expose a partial turn plan")
	_check(not cancelled_session.is_running(), "Cancelled session joins without a live worker")


func _cancel_on_completed_depth(_progress: Dictionary) -> void:
	_cancel_after_completed_depth = true


func _should_cancel_after_depth() -> bool:
	return _cancel_after_completed_depth


func _always_cancel() -> bool:
	return true


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


func _make_extra_play_search_state() -> State:
	var board: Array = Rules.empty_board()
	board[4] = {
		"owner": Rules.OPPONENT_OWNER,
		"card": Catalog.create_instance(&"KuiHua1", Rules.OPPONENT_OWNER, &"search_kuihua"),
	}
	var player_reply: Dictionary = Rules.make_card(
		"Player Reply",
		"回",
		[0, 0, 0, 0],
		[],
		Rules.PLAYER_OWNER
	)
	player_reply["instance_id"] = &"search_player_reply"
	var first_extra: Dictionary = Rules.make_card(
		"Opponent First",
		"先",
		[0, 0, 0, 0],
		[],
		Rules.OPPONENT_OWNER
	)
	first_extra["instance_id"] = &"search_extra_first"
	var second_extra: Dictionary = Rules.make_card(
		"Opponent Second",
		"后",
		[0, 0, 0, 0],
		[],
		Rules.OPPONENT_OWNER
	)
	second_extra["instance_id"] = &"search_extra_second"
	return State.new(
		board,
		[player_reply],
		[first_extra, second_extra],
		Rules.OPPONENT_OWNER
	)


func _make_empty_opponent_round_state() -> State:
	var first: Dictionary = Rules.make_card(
		"First",
		"先",
		[0, 0, 0, 0],
		[],
		Rules.PLAYER_OWNER
	)
	first["instance_id"] = &"empty_round_first"
	var next: Dictionary = Rules.make_card(
		"Next",
		"继",
		[0, 0, 0, 0],
		[],
		Rules.PLAYER_OWNER
	)
	next["instance_id"] = &"empty_round_next"
	return State.new(Rules.empty_board(), [first, next], [], Rules.PLAYER_OWNER)


func _bruteforce_complete_round_depth_one(
	state: State,
	root_owner: int
) -> Dictionary:
	var root_serial: int = state.owner_turn_serial
	var best_action: Action = null
	var best_score: int = -Search.INFINITY
	for action: Action in Simulator.get_legal_actions(state):
		var transition: Dictionary = Simulator.apply_action(state, action)
		var next_state: State = transition.get("state") as State
		var score: int = _bruteforce_to_round_boundary(next_state, root_owner, root_serial)
		var better_tie: bool = (
			best_action != null
			and score == best_score
			and action.canonical_key() < best_action.canonical_key()
		)
		if best_action == null or score > best_score or better_tie:
			best_action = action
			best_score = score
	return {"action": best_action, "score": best_score}


func _bruteforce_fixed_action_depth(
	state: State,
	root_owner: int,
	remaining_actions: int
) -> Dictionary:
	var best_action: Action = null
	var maximizing: bool = state.active_player == root_owner
	var best_score: int = -Search.INFINITY if maximizing else Search.INFINITY
	for action: Action in Simulator.get_legal_actions(state):
		var transition: Dictionary = Simulator.apply_action(state, action)
		var score: int = _bruteforce_fixed_action_depth_score(
			transition.get("state") as State,
			root_owner,
			remaining_actions - 1
		)
		var better_tie: bool = (
			best_action != null
			and score == best_score
			and action.canonical_key() < best_action.canonical_key()
		)
		if (
			best_action == null
			or (maximizing and score > best_score)
			or (not maximizing and score < best_score)
			or better_tie
		):
			best_action = action
			best_score = score
	return {"action": best_action, "score": best_score}


func _bruteforce_fixed_action_depth_score(
	state: State,
	root_owner: int,
	remaining_actions: int
) -> int:
	if Simulator.is_terminal(state) or remaining_actions <= 0:
		return Evaluator.evaluate(state, root_owner, &"baseline")
	var legal_actions: Array[Action] = Simulator.get_legal_actions(state)
	if legal_actions.is_empty():
		return Evaluator.evaluate(state, root_owner, &"baseline")
	var maximizing: bool = state.active_player == root_owner
	var best_score: int = -Search.INFINITY if maximizing else Search.INFINITY
	for action: Action in legal_actions:
		var transition: Dictionary = Simulator.apply_action(state, action)
		var score: int = _bruteforce_fixed_action_depth_score(
			transition.get("state") as State,
			root_owner,
			remaining_actions - 1
		)
		best_score = maxi(best_score, score) if maximizing else mini(best_score, score)
	return best_score


func _bruteforce_to_round_boundary(
	state: State,
	root_owner: int,
	root_serial: int
) -> int:
	if Simulator.is_terminal(state) or state.owner_turn_serial - root_serial >= 2:
		return Evaluator.evaluate(state, root_owner, &"baseline")
	var legal_actions: Array[Action] = Simulator.get_legal_actions(state)
	if legal_actions.is_empty():
		return Evaluator.evaluate(state, root_owner, &"baseline")
	var maximizing: bool = state.active_player == root_owner
	var best_score: int = -Search.INFINITY if maximizing else Search.INFINITY
	for action: Action in legal_actions:
		var transition: Dictionary = Simulator.apply_action(state, action)
		var score: int = _bruteforce_to_round_boundary(
			transition.get("state") as State,
			root_owner,
			root_serial
		)
		best_score = maxi(best_score, score) if maximizing else mini(best_score, score)
	return best_score


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("CHECK_FAILED: %s" % message)
