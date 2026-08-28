extends SceneTree

const FIXED_COMPLETE_ROUND_DEPTH: int = 1
const EXACT_ROOT_ACTION_GAME_IDS: Array[StringName] = [
	&"qingfeng_xuedi__dukou_xiaoke__g1",
	&"luoxia_jianji__heisha_xingzhe__g1",
]

const Action = preload("res://scripts/duel_action.gd")
const EnemyManifest = preload("res://tests/benchmarks/enemy_ai_benchmark_manifest.gd")
const EnemyStateFactory = preload("res://tests/benchmarks/enemy_ai_benchmark_state_factory.gd")
const Profile = preload("res://scripts/duel_search_profile.gd")
const Search = preload("res://scripts/duel_search.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if "--exact-root-actions" in OS.get_cmdline_user_args():
		_run_exact_root_actions()
		return
	var openings: Array[Dictionary] = _build_unique_openings()
	_check(openings.size() == 14, "Quick manifest produces exactly fourteen unique openings")
	for opening_index: int in range(openings.size()):
		var opening: Dictionary = openings[opening_index]
		var state: State = opening.get("state") as State
		if state == null:
			_check(false, "%s rebuilds a valid state" % opening.get("game_id", &"missing"))
			continue
		var baseline: Dictionary = _search(state, {
			"profile": &"baseline",
			"use_lazy_transitions": false,
			"use_pvs": false,
		})
		var lazy_only: Dictionary = _search(state, {
			"profile": &"enhanced",
			"use_lazy_transitions": true,
			"use_pvs": false,
		})
		var lazy_pvs: Dictionary = _search(state, {
			"profile": &"enhanced",
			"use_lazy_transitions": true,
			"use_pvs": true,
		})
		_check_result(opening, "Baseline", baseline)
		_check_result(opening, "Lazy-only", lazy_only)
		_check_result(opening, "Lazy+PVS", lazy_pvs)
		_check_equivalent(opening, "Lazy-only", baseline, lazy_only)
		_check_equivalent(opening, "Lazy+PVS", baseline, lazy_pvs)
		print(
			"REAL_QUICK_EQUIVALENCE_PROGRESS opening=%d/14 matchup=%s"
			% [opening_index + 1, String(opening.get("matchup_id", &"missing"))]
		)
	if _failures == 0:
		print(
			"REAL_QUICK_SEARCH_EQUIVALENCE_PASSED openings=%d comparisons=%d complete_round_depth=%d checks=%d"
			% [
				openings.size(),
				openings.size() * 2,
				FIXED_COMPLETE_ROUND_DEPTH,
				_checks,
			]
		)
	else:
		push_error(
			"REAL_QUICK_SEARCH_EQUIVALENCE_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _run_exact_root_actions() -> void:
	var openings: Array[Dictionary] = _build_unique_openings()
	var targets_found: int = 0
	for opening: Dictionary in openings:
		var game_id := StringName(opening.get("game_id", &"missing"))
		if game_id not in EXACT_ROOT_ACTION_GAME_IDS:
			continue
		targets_found += 1
		var state: State = opening.get("state") as State
		if state == null:
			_check(false, "%s rebuilds a valid state" % game_id)
			continue
		var baseline_overrides: Dictionary = {
			"profile": &"baseline",
			"use_lazy_transitions": false,
			"use_pvs": false,
		}
		var lazy_overrides: Dictionary = {
			"profile": &"enhanced",
			"use_lazy_transitions": true,
			"use_pvs": false,
		}
		var baseline: Dictionary = _search(state, baseline_overrides)
		var lazy_only: Dictionary = _search(state, lazy_overrides)
		var selected_actions: Array[Dictionary] = [
			{"label": "Baseline choice", "action": baseline.get("action")},
			{"label": "Lazy-only choice", "action": lazy_only.get("action")},
		]
		var observed_actions: Dictionary = {}
		for selection: Dictionary in selected_actions:
			var action: Action = selection.get("action") as Action
			if action == null:
				_check(false, "%s %s exists" % [game_id, selection.get("label", "missing")])
				continue
			var action_key: String = action.canonical_key()
			if observed_actions.has(action_key):
				continue
			var exact_baseline: Dictionary = _score_root_action_exact(
				state,
				action,
				baseline_overrides
			)
			var exact_lazy: Dictionary = _score_root_action_exact(
				state,
				action,
				lazy_overrides
			)
			observed_actions[action_key] = {
				"baseline": exact_baseline,
				"lazy": exact_lazy,
			}
			_check(
				bool(exact_baseline.get("valid", false))
				and bool(exact_lazy.get("valid", false)),
				"%s %s is legal for both exact scorers"
				% [game_id, selection.get("label", "missing")]
			)
			_check(
				int(exact_baseline.get("score", 0)) == int(exact_lazy.get("score", 1)),
				"%s %s exact score is traversal-independent baseline=%d lazy=%d"
				% [
					game_id,
					selection.get("label", "missing"),
					int(exact_baseline.get("score", 0)),
					int(exact_lazy.get("score", 1)),
				]
			)
			print(
				"REAL_QUICK_ROOT_ACTION_SCORE game=%s source=%s baseline=%d lazy=%d action=%s"
				% [
					game_id,
					selection.get("label", "missing"),
					int(exact_baseline.get("score", 0)),
					int(exact_lazy.get("score", 0)),
					action_key,
				]
			)
		var baseline_action: Action = baseline.get("action") as Action
		var lazy_action: Action = lazy_only.get("action") as Action
		var baseline_choice_scores: Dictionary = observed_actions.get(
			baseline_action.canonical_key(),
			{}
		) as Dictionary
		var lazy_choice_scores: Dictionary = observed_actions.get(
			lazy_action.canonical_key(),
			{}
		) as Dictionary
		var baseline_choice_score: Dictionary = baseline_choice_scores.get(
			"baseline",
			{}
		) as Dictionary
		var lazy_choice_score: Dictionary = lazy_choice_scores.get("lazy", {}) as Dictionary
		_check(
			int(baseline_choice_score.get("score", 0)) == int(baseline.get("score", 1)),
			"%s Baseline selected action achieves its reported root score exact=%d reported=%d"
			% [
				game_id,
				int(baseline_choice_score.get("score", 0)),
				int(baseline.get("score", 1)),
			]
		)
		_check(
			int(lazy_choice_score.get("score", 0)) == int(lazy_only.get("score", 1)),
			"%s Lazy-only selected action achieves its reported root score exact=%d reported=%d"
			% [
				game_id,
				int(lazy_choice_score.get("score", 0)),
				int(lazy_only.get("score", 1)),
			]
		)
	_check(targets_found == EXACT_ROOT_ACTION_GAME_IDS.size(), "Both mismatch openings are available")
	if _failures == 0:
		print(
			"REAL_QUICK_ROOT_ACTION_SCORES_PASSED openings=%d checks=%d"
			% [targets_found, _checks]
		)
	else:
		push_error(
			"REAL_QUICK_ROOT_ACTION_SCORES_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _build_unique_openings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var observed_state_keys: Dictionary = {}
	for matchup: Dictionary in EnemyManifest.get_matchups_for_mode(&"quick"):
		for game: Dictionary in EnemyManifest.expand_matchup(matchup):
			var built: Dictionary = EnemyStateFactory.build(game, matchup)
			var metadata: Dictionary = built.get("metadata", {}) as Dictionary
			var state_key: String = String(metadata.get("initial_state_key", ""))
			if observed_state_keys.has(state_key):
				continue
			observed_state_keys[state_key] = true
			result.append({
				"game_id": StringName(metadata.get("game_id", &"missing")),
				"matchup_id": StringName(metadata.get("matchup_id", &"missing")),
				"state_key": StateKey.build_compact(built.get("state") as State),
				"state": built.get("state"),
			})
	return result


func _search(state: State, overrides: Dictionary) -> Dictionary:
	return Search.find_best_action_iterative(
		state.duplicate_state(),
		state.active_player,
		_search_limits(overrides)
	)


func _search_limits(overrides: Dictionary) -> Dictionary:
	var limits: Dictionary = {
		"max_depth": FIXED_COMPLETE_ROUND_DEPTH,
		"use_tactical_extension": false,
		"use_evaluation_cache": false,
		"evaluator_profile": &"baseline",
	}
	limits.merge(overrides, true)
	return limits


func _score_root_action_exact(
	state: State,
	action: Action,
	overrides: Dictionary
) -> Dictionary:
	if action == null:
		return {"valid": false, "score": 0}
	var transition: Dictionary = Simulator.apply_action(state.duplicate_state(), action)
	if not bool(transition.get("valid", false)):
		return {"valid": false, "score": 0}
	var limits: Dictionary = _search_limits(overrides)
	var context: Dictionary = _make_search_context(Profile.normalize(limits))
	var next_state: State = transition.get("state") as State
	var remaining_owner_turn_boundaries: int = Search._remaining_after_transition(
		state,
		next_state,
		FIXED_COMPLETE_ROUND_DEPTH * 2
	)
	var score: int = Search._search(
		next_state,
		remaining_owner_turn_boundaries,
		-Search.INFINITY,
		Search.INFINITY,
		state.active_player,
		context,
		{}
	)
	return {
		"valid": not bool(context.get("aborted", false)),
		"score": score,
		"nodes": int(context.get("nodes", 0)),
	}


func _make_search_context(profile: Dictionary) -> Dictionary:
	return {
		"deadline_usec": 0,
		"max_nodes": 0,
		"nodes": 0,
		"cutoffs": 0,
		"transposition_hits": 0,
		"generated_actions": 0,
		"applied_transitions": 0,
		"pvs_probes": 0,
		"pvs_researches": 0,
		"evaluation_cache_hits": 0,
		"max_tactical_depth": 0,
		"tactical_candidates_scanned": 0,
		"tactical_actions_searched": 0,
		"max_tactical_candidates_per_node": 0,
		"max_tactical_actions_per_node": 0,
		"evaluation_cache": {},
		"history": {},
		"aborted": false,
		"stop_reason": &"",
		"horizon_reached": false,
		"should_cancel": Callable(),
		"profile": profile,
	}


func _check_result(opening: Dictionary, label: String, result: Dictionary) -> void:
	var action: Action = result.get("action") as Action
	_check(
		action != null,
		"%s %s returns an action" % [opening.get("game_id", &"missing"), label]
	)
	_check(
		int(result.get("completed_depth", 0)) == FIXED_COMPLETE_ROUND_DEPTH,
		"%s %s completes fixed complete-round depth %d"
		% [
			opening.get("game_id", &"missing"),
			label,
			FIXED_COMPLETE_ROUND_DEPTH,
		]
	)
	_check(
		bool(result.get("has_completed_depth", false)),
		"%s %s has a completed search depth"
		% [opening.get("game_id", &"missing"), label]
	)


func _check_equivalent(
	opening: Dictionary,
	label: String,
	baseline: Dictionary,
	candidate: Dictionary
) -> void:
	var baseline_action: Action = baseline.get("action") as Action
	var candidate_action: Action = candidate.get("action") as Action
	var baseline_action_key: String = (
		baseline_action.canonical_key() if baseline_action != null else "<missing>"
	)
	var candidate_action_key: String = (
		candidate_action.canonical_key() if candidate_action != null else "<missing>"
	)
	var context: String = (
		"game=%s matchup=%s state=%s candidate=%s"
		% [
			opening.get("game_id", &"missing"),
			opening.get("matchup_id", &"missing"),
			opening.get("state_key", ""),
			label,
		]
	)
	_check(
		int(candidate.get("completed_depth", 0))
		== int(baseline.get("completed_depth", -1)),
		"Completed depth matches: %s baseline=%d candidate=%d"
		% [
			context,
			int(baseline.get("completed_depth", -1)),
			int(candidate.get("completed_depth", -1)),
		]
	)
	_check(
		int(candidate.get("score", 0)) == int(baseline.get("score", 1)),
		"Score matches: %s baseline=%d candidate=%d"
		% [context, int(baseline.get("score", 1)), int(candidate.get("score", 0))]
	)
	_check(
		candidate_action_key == baseline_action_key,
		"Action matches: %s baseline=%s candidate=%s"
		% [context, baseline_action_key, candidate_action_key]
	)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("CHECK_FAILED: %s" % message)
