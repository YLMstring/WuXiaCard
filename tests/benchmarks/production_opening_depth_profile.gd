extends SceneTree

const DEFAULT_BUDGET_SECONDS: float = 10.0
const DEFAULT_MAX_OPENINGS: int = 14
const TIMING_NODE_LIMIT: int = 5_000
const TARGET_DEPTH: int = 2
const BASELINE_DEPTH: int = 1
const OUTPUT_DIRECTORY: String = "res://.summer/local/ai-benchmarks"

const Action = preload("res://scripts/duel_action.gd")
const EnemyManifest = preload("res://tests/benchmarks/enemy_ai_benchmark_manifest.gd")
const EnemyStateFactory = preload("res://tests/benchmarks/enemy_ai_benchmark_state_factory.gd")
const Search = preload("res://scripts/duel_search.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")
const TurnPlan = preload("res://scripts/duel_turn_plan.gd")

var _depth_snapshots: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var options: Dictionary = _parse_options()
	var budget_seconds: float = float(options.get("budget_seconds", DEFAULT_BUDGET_SECONDS))
	var max_openings: int = int(options.get("max_openings", DEFAULT_MAX_OPENINGS))
	var depth_mode: StringName = StringName(options.get("depth_mode", &"self_turn"))
	var opening_set: StringName = StringName(options.get("opening_set", &"quick_unique"))
	var use_internal_pv_ordering: bool = bool(options.get("use_internal_pv_ordering", false))
	var use_history_ordering: bool = bool(options.get("use_history_ordering", false))
	var use_transposition_table: bool = bool(options.get("use_transposition_table", false))
	var transposition_table_mib: int = maxi(
		int(options.get("transposition_table_mib", 8)), 0
	)
	var collect_transposition_diagnostics: bool = bool(
		options.get("collect_transposition_diagnostics", false)
	)
	var openings: Array[Dictionary] = _build_unique_openings(opening_set)
	if max_openings > 0 and openings.size() > max_openings:
		openings.resize(max_openings)
	var samples: Array[Dictionary] = []
	for opening_index: int in range(openings.size()):
		var sample: Dictionary = _profile_opening(
			openings[opening_index],
			budget_seconds,
			depth_mode,
			opening_set == &"extra_play_cap",
			use_internal_pv_ordering,
			use_history_ordering,
			use_transposition_table,
			transposition_table_mib,
			collect_transposition_diagnostics
		)
		samples.append(sample)
		print(
			(
				"OPENING_DEPTH_PROFILE_PROGRESS opening=%d/%d game=%s depth=%d "
				+ "attempted=%d roots=%d/%d elapsed=%.3f nodes=%d"
			)
			% [
				opening_index + 1,
				openings.size(),
				String(sample.get("game_id", "missing")),
				int(sample.get("completed_depth", 0)),
				int(sample.get("attempted_depth", 0)),
				int(sample.get("root_actions_completed", 0)),
				int(sample.get("root_actions_total", 0)),
				float(sample.get("elapsed_seconds", 0.0)),
				int(sample.get("nodes", 0)),
			]
		)
		var extra_play: Dictionary = sample.get("extra_play", {}) as Dictionary
		if bool(extra_play.get("entered_extra_play", false)):
			print(
				(
					"OPENING_DEPTH_PROFILE_EXTRA game=%s reused=%s searched=%s "
					+ "depth=%d attempted=%d roots=%d/%d elapsed=%.3f nodes=%d"
				)
				% [
					String(sample.get("game_id", "missing")),
					str(bool(extra_play.get("plan_reused", false))),
					str(bool(extra_play.get("fresh_search", false))),
					int(extra_play.get("completed_depth", 0)),
					int(extra_play.get("attempted_depth", 0)),
					int(extra_play.get("root_actions_completed", 0)),
					int(extra_play.get("root_actions_total", 0)),
					float(extra_play.get("elapsed_seconds", 0.0)),
					int(extra_play.get("nodes", 0)),
				]
			)
	var timing_samples: Array[Dictionary] = _run_timing_probes(
		openings,
		depth_mode,
		use_internal_pv_ordering,
		use_history_ordering,
		use_transposition_table,
		transposition_table_mib
	)
	var report: Dictionary = {
		"schema_version": 4,
		"created_unix_time": int(Time.get_unix_time_from_system()),
		"fixture_version": EnemyManifest.VERSION,
		"configuration": {
			"backend": "native",
			"budget_seconds": budget_seconds,
			"depth_unit": String(depth_mode),
			"depth_mode": String(depth_mode),
			"target_depth": TARGET_DEPTH,
			"profile": "enhanced",
			"use_lazy_transitions": true,
			"use_pvs": false,
			"use_tactical_extension": false,
			"use_evaluation_cache": false,
			"evaluator_profile": "baseline",
			"opening_count": openings.size(),
			"opening_set": String(opening_set),
			"use_internal_pv_ordering": use_internal_pv_ordering,
			"use_history_ordering": use_history_ordering,
			"use_transposition_table": use_transposition_table,
			"transposition_table_mib": transposition_table_mib,
			"collect_transposition_diagnostics": collect_transposition_diagnostics,
		},
		"summary": _summarize(samples, timing_samples, budget_seconds, depth_mode),
		"openings": samples,
		"timing_probes": timing_samples,
	}
	var output_path: String = _write_report(report, opening_set)
	if output_path.is_empty():
		push_error("OPENING_DEPTH_PROFILE_FAILED could not write JSON report")
		quit(1)
		return
	var summary: Dictionary = report.get("summary", {}) as Dictionary
	print(
		(
			"OPENING_DEPTH_PROFILE_COMPLETE openings=%d target_depth=%d completed=%d "
			+ "avg_depth=%.3f avg_depth1_seconds=%.3f tt_hit_rate=%.4f "
			+ "tt_completed_hit_rate=%.4f tt_leaf_hit_rate=%.4f "
			+ "tt_internal_hit_rate=%.4f tt_state_hit_rate=%.4f "
			+ "table_hit_rate=%.4f report=%s"
		)
		% [
			openings.size(),
			TARGET_DEPTH,
			int(summary.get("target_depth_completed", 0)),
			float(summary.get("average_completed_depth", 0.0)),
			float(summary.get("average_baseline_depth_seconds", 0.0)),
			float(summary.get("transposition_hit_rate", 0.0)),
			float(summary.get("transposition_completed_hit_rate", 0.0)),
			float(summary.get("transposition_leaf_completed_hit_rate", 0.0)),
			float(summary.get("transposition_internal_completed_hit_rate", 0.0)),
			float(summary.get("transposition_state_hit_rate", 0.0)),
			float(summary.get("transposition_table_hit_rate", 0.0)),
			output_path,
		]
	)
	quit(0)


func _profile_opening(
	opening: Dictionary,
	budget_seconds: float,
	depth_mode: StringName,
	profile_extra_play: bool = false,
	use_internal_pv_ordering: bool = false,
	use_history_ordering: bool = false,
	use_transposition_table: bool = false,
	transposition_table_mib: int = 8,
	collect_transposition_diagnostics: bool = false
) -> Dictionary:
	_depth_snapshots.clear()
	var state: State = opening.get("state") as State
	var limits: Dictionary = {
		"budget_seconds": budget_seconds,
		"profile": &"enhanced",
		"use_lazy_transitions": true,
		"use_pvs": false,
		"use_tactical_extension": false,
		"use_evaluation_cache": false,
		"evaluator_profile": &"baseline",
		"depth_mode": depth_mode,
		"use_internal_pv_ordering": use_internal_pv_ordering,
		"use_history_ordering": use_history_ordering,
		"use_transposition_table": use_transposition_table,
		"transposition_table_mib": transposition_table_mib,
		"collect_search_diagnostics": collect_transposition_diagnostics,
	}
	var result: Dictionary = Search.find_best_action_iterative(
		state.duplicate_state(),
		state.active_player,
		limits,
		Callable(),
		Callable(self, "_record_depth_progress")
	)
	var last_completed: Dictionary = (
		_depth_snapshots.back()
		if not _depth_snapshots.is_empty()
		else {}
	)
	var target_depth_snapshot: Dictionary = _snapshot_for_depth(
		TARGET_DEPTH
	)
	var selected_action: Action = result.get("action") as Action
	var estimated_required_seconds: Variant = null
	if not target_depth_snapshot.is_empty():
		estimated_required_seconds = float(
			target_depth_snapshot.get("elapsed_seconds", 0.0)
		)
	elif (
		int(result.get("iteration_depth", 0)) == TARGET_DEPTH
		and int(result.get("root_actions_completed", 0)) > 0
	):
		var partial_seconds: float = maxf(
			float(result.get("elapsed_seconds", 0.0))
			- float(last_completed.get("elapsed_seconds", 0.0)),
			0.000_001
		)
		estimated_required_seconds = (
			float(last_completed.get("elapsed_seconds", 0.0))
			+ partial_seconds
			* float(result.get("root_actions_total", 0))
			/ float(result.get("root_actions_completed", 1))
		)
	var estimated_speedup: Variant = null
	if estimated_required_seconds != null:
		estimated_speedup = float(estimated_required_seconds) / budget_seconds
	var sample: Dictionary = {
		"game_id": String(opening.get("game_id", &"missing")),
		"matchup_id": String(opening.get("matchup_id", &"missing")),
		"depth_mode": String(result.get("depth_mode", depth_mode)),
		"state_key": String(opening.get("state_key", "")),
		"state_key_length": String(opening.get("state_key", "")).length(),
		"exact_state_key_digest": StateKey.build(state).sha256_text(),
		"action_key": selected_action.canonical_key() if selected_action != null else "",
		"root_legal_actions": int(opening.get("root_legal_actions", 0)),
		"completed_depth": int(result.get("completed_depth", 0)),
		"attempted_depth": int(result.get("iteration_depth", 0)),
		"elapsed_seconds": float(result.get("elapsed_seconds", 0.0)),
		"nodes": int(result.get("nodes", 0)),
		"generated_actions": int(result.get("generated_actions", 0)),
		"applied_transitions": int(result.get("applied_transitions", 0)),
		"cutoffs": int(result.get("cutoffs", 0)),
		"pv_queries": int(result.get("pv_queries", 0)),
		"pv_hits": int(result.get("pv_hits", 0)),
		"pv_legal_hits": int(result.get("pv_legal_hits", 0)),
		"pv_illegal_hits": int(result.get("pv_illegal_hits", 0)),
		"history_queries": int(result.get("history_queries", 0)),
		"history_hits": int(result.get("history_hits", 0)),
		"history_cutoffs": int(result.get("history_cutoffs", 0)),
		"transposition_probes": int(result.get("transposition_probes", 0)),
		"transposition_hits": int(result.get("transposition_hits", 0)),
		"transposition_completed_hits": int(result.get("transposition_completed_hits", 0)),
		"transposition_leaf_probes": int(result.get("transposition_leaf_probes", 0)),
		"transposition_leaf_completed_hits": int(result.get("transposition_leaf_completed_hits", 0)),
		"transposition_internal_probes": int(result.get("transposition_internal_probes", 0)),
		"transposition_internal_completed_hits": int(result.get("transposition_internal_completed_hits", 0)),
		"transposition_state_hits": int(result.get("transposition_state_hits", 0)),
		"transposition_unique_keys": int(result.get("transposition_unique_keys", 0)),
		"transposition_completed_keys": int(result.get("transposition_completed_keys", 0)),
		"transposition_unique_states": int(result.get("transposition_unique_states", 0)),
		"transposition_table_probes": int(result.get("transposition_table_probes", 0)),
		"transposition_table_hits": int(result.get("transposition_table_hits", 0)),
		"transposition_exact_hits": int(result.get("transposition_exact_hits", 0)),
		"transposition_bound_hits": int(result.get("transposition_bound_hits", 0)),
		"transposition_exact_returns": int(result.get("transposition_exact_returns", 0)),
		"transposition_bound_cutoffs": int(result.get("transposition_bound_cutoffs", 0)),
		"transposition_stores": int(result.get("transposition_stores", 0)),
		"transposition_updates": int(result.get("transposition_updates", 0)),
		"transposition_replacements": int(result.get("transposition_replacements", 0)),
		"transposition_collisions": int(result.get("transposition_collisions", 0)),
		"transposition_move_queries": int(result.get("transposition_move_queries", 0)),
		"transposition_move_legal_hits": int(result.get("transposition_move_legal_hits", 0)),
		"transposition_move_illegal_hits": int(result.get("transposition_move_illegal_hits", 0)),
		"transposition_table_enabled": bool(result.get("transposition_table_enabled", false)),
		"transposition_table_requested_mib": int(result.get("transposition_table_requested_mib", 0)),
		"transposition_table_capacity_bytes": int(result.get("transposition_table_capacity_bytes", 0)),
		"transposition_table_allocation_fallback": bool(result.get("transposition_table_allocation_fallback", false)),
		"iteration_nodes": int(result.get("iteration_nodes", 0)),
		"root_actions_total": int(result.get("root_actions_total", 0)),
		"root_actions_started": int(result.get("root_actions_started", 0)),
		"root_actions_completed": int(result.get("root_actions_completed", 0)),
		"current_root_action_nodes": int(result.get("current_root_action_nodes", 0)),
		"completion_reason": String(result.get("completion_reason", &"")),
		"used_fallback": not bool(result.get("has_completed_depth", false)),
		"depth_snapshots": _depth_snapshots.duplicate(true),
		"estimated_target_depth_seconds": estimated_required_seconds,
		"estimated_speedup_for_target_depth": estimated_speedup,
	}
	if profile_extra_play:
		sample["extra_play"] = _profile_extra_play_decision(
			state,
			result,
			budget_seconds,
			depth_mode,
			use_internal_pv_ordering,
			use_history_ordering,
			use_transposition_table,
			transposition_table_mib,
			collect_transposition_diagnostics
		)
	return sample


func _profile_extra_play_decision(
	state: State,
	first_result: Dictionary,
	budget_seconds: float,
	depth_mode: StringName,
	use_internal_pv_ordering: bool,
	use_history_ordering: bool,
	use_transposition_table: bool,
	transposition_table_mib: int,
	collect_transposition_diagnostics: bool
) -> Dictionary:
	var first_action: Action = first_result.get("action") as Action
	var sample: Dictionary = {
		"entered_extra_play": false,
		"plan_reused": false,
		"fresh_search": false,
		"completed_depth": 0,
		"attempted_depth": 0,
		"elapsed_seconds": 0.0,
		"nodes": 0,
		"root_actions_total": 0,
		"root_actions_completed": 0,
		"depth_snapshots": [],
	}
	if first_action == null:
		sample["reason"] = "no_first_action"
		return sample
	var transition: Dictionary = Simulator.apply_action(
		state.duplicate_state(), first_action
	)
	if not bool(transition.get("valid", false)):
		sample["reason"] = "invalid_first_action"
		return sample
	sample["first_action_key"] = first_action.canonical_key()
	var extra_state: State = transition.get("state") as State
	if (
		extra_state == null
		or extra_state.active_player != state.active_player
		or extra_state.owner_turn_serial != state.owner_turn_serial
	):
		sample["reason"] = "first_action_did_not_grant_extra_play"
		return sample
	sample["entered_extra_play"] = true
	sample["state_key"] = StateKey.build_compact(extra_state)
	var reusable_plan: Array[Dictionary] = TurnPlan.remaining_after_search_result(
		first_result,
		state,
		first_action,
		TARGET_DEPTH
	)
	if not reusable_plan.is_empty():
		sample["plan_reused"] = true
		sample["reason"] = "completed_depth_two_plan"
		sample["completed_depth"] = int(first_result.get("completed_depth", 0))
		return sample

	_depth_snapshots.clear()
	var second_result: Dictionary = Search.find_best_action_iterative(
		extra_state.duplicate_state(),
		extra_state.active_player,
		{
			"budget_seconds": budget_seconds,
			"profile": &"enhanced",
			"use_lazy_transitions": true,
			"use_pvs": false,
			"use_tactical_extension": false,
			"use_evaluation_cache": false,
			"evaluator_profile": &"baseline",
			"depth_mode": depth_mode,
			"use_internal_pv_ordering": use_internal_pv_ordering,
			"use_history_ordering": use_history_ordering,
			"use_transposition_table": use_transposition_table,
			"transposition_table_mib": transposition_table_mib,
			"collect_search_diagnostics": collect_transposition_diagnostics,
		},
		Callable(),
		Callable(self, "_record_depth_progress")
	)
	sample["fresh_search"] = true
	sample["reason"] = "shallow_first_search_rethought"
	sample["completed_depth"] = int(second_result.get("completed_depth", 0))
	sample["attempted_depth"] = int(second_result.get("iteration_depth", 0))
	sample["elapsed_seconds"] = float(second_result.get("elapsed_seconds", 0.0))
	sample["nodes"] = int(second_result.get("nodes", 0))
	sample["generated_actions"] = int(second_result.get("generated_actions", 0))
	sample["applied_transitions"] = int(second_result.get("applied_transitions", 0))
	sample["cutoffs"] = int(second_result.get("cutoffs", 0))
	sample["pv_queries"] = int(second_result.get("pv_queries", 0))
	sample["pv_hits"] = int(second_result.get("pv_hits", 0))
	sample["pv_legal_hits"] = int(second_result.get("pv_legal_hits", 0))
	sample["pv_illegal_hits"] = int(second_result.get("pv_illegal_hits", 0))
	sample["history_queries"] = int(second_result.get("history_queries", 0))
	sample["history_hits"] = int(second_result.get("history_hits", 0))
	sample["history_cutoffs"] = int(second_result.get("history_cutoffs", 0))
	sample["transposition_probes"] = int(second_result.get("transposition_probes", 0))
	sample["transposition_hits"] = int(second_result.get("transposition_hits", 0))
	sample["transposition_completed_hits"] = int(second_result.get("transposition_completed_hits", 0))
	sample["transposition_leaf_probes"] = int(second_result.get("transposition_leaf_probes", 0))
	sample["transposition_leaf_completed_hits"] = int(second_result.get("transposition_leaf_completed_hits", 0))
	sample["transposition_internal_probes"] = int(second_result.get("transposition_internal_probes", 0))
	sample["transposition_internal_completed_hits"] = int(second_result.get("transposition_internal_completed_hits", 0))
	sample["transposition_state_hits"] = int(second_result.get("transposition_state_hits", 0))
	sample["transposition_unique_keys"] = int(second_result.get("transposition_unique_keys", 0))
	sample["transposition_completed_keys"] = int(second_result.get("transposition_completed_keys", 0))
	sample["transposition_unique_states"] = int(second_result.get("transposition_unique_states", 0))
	sample["transposition_table_probes"] = int(second_result.get("transposition_table_probes", 0))
	sample["transposition_table_hits"] = int(second_result.get("transposition_table_hits", 0))
	sample["transposition_exact_returns"] = int(second_result.get("transposition_exact_returns", 0))
	sample["transposition_bound_cutoffs"] = int(second_result.get("transposition_bound_cutoffs", 0))
	sample["transposition_stores"] = int(second_result.get("transposition_stores", 0))
	sample["transposition_replacements"] = int(second_result.get("transposition_replacements", 0))
	sample["transposition_collisions"] = int(second_result.get("transposition_collisions", 0))
	sample["root_actions_total"] = int(second_result.get("root_actions_total", 0))
	sample["root_actions_started"] = int(second_result.get("root_actions_started", 0))
	sample["root_actions_completed"] = int(second_result.get("root_actions_completed", 0))
	sample["completion_reason"] = String(
		second_result.get("completion_reason", &"")
	)
	var second_action: Action = second_result.get("action") as Action
	sample["action_key"] = (
		second_action.canonical_key() if second_action != null else ""
	)
	sample["depth_snapshots"] = _depth_snapshots.duplicate(true)
	return sample


func _record_depth_progress(progress: Dictionary) -> void:
	var action: Action = progress.get("action") as Action
	_depth_snapshots.append({
		"depth": int(progress.get("completed_depth", 0)),
		"owner_turn_boundaries": int(progress.get("owner_turn_boundaries", 0)),
		"score": int(progress.get("score", 0)),
		"action_key": action.canonical_key() if action != null else "",
		"elapsed_seconds": float(progress.get("elapsed_seconds", 0.0)),
		"nodes": int(progress.get("nodes", 0)),
		"generated_actions": int(progress.get("generated_actions", 0)),
		"applied_transitions": int(progress.get("applied_transitions", 0)),
		"cutoffs": int(progress.get("cutoffs", 0)),
		"pv_queries": int(progress.get("pv_queries", 0)),
		"pv_hits": int(progress.get("pv_hits", 0)),
		"pv_legal_hits": int(progress.get("pv_legal_hits", 0)),
		"pv_illegal_hits": int(progress.get("pv_illegal_hits", 0)),
		"history_queries": int(progress.get("history_queries", 0)),
		"history_hits": int(progress.get("history_hits", 0)),
		"history_cutoffs": int(progress.get("history_cutoffs", 0)),
		"transposition_probes": int(progress.get("transposition_probes", 0)),
		"transposition_hits": int(progress.get("transposition_hits", 0)),
		"transposition_completed_hits": int(progress.get("transposition_completed_hits", 0)),
		"transposition_leaf_probes": int(progress.get("transposition_leaf_probes", 0)),
		"transposition_leaf_completed_hits": int(progress.get("transposition_leaf_completed_hits", 0)),
		"transposition_internal_probes": int(progress.get("transposition_internal_probes", 0)),
		"transposition_internal_completed_hits": int(progress.get("transposition_internal_completed_hits", 0)),
		"transposition_state_hits": int(progress.get("transposition_state_hits", 0)),
		"transposition_unique_keys": int(progress.get("transposition_unique_keys", 0)),
		"transposition_completed_keys": int(progress.get("transposition_completed_keys", 0)),
		"transposition_unique_states": int(progress.get("transposition_unique_states", 0)),
		"transposition_table_probes": int(progress.get("transposition_table_probes", 0)),
		"transposition_table_hits": int(progress.get("transposition_table_hits", 0)),
		"transposition_exact_returns": int(progress.get("transposition_exact_returns", 0)),
		"transposition_bound_cutoffs": int(progress.get("transposition_bound_cutoffs", 0)),
		"transposition_stores": int(progress.get("transposition_stores", 0)),
		"transposition_replacements": int(progress.get("transposition_replacements", 0)),
		"transposition_collisions": int(progress.get("transposition_collisions", 0)),
	})


func _snapshot_for_depth(depth: int) -> Dictionary:
	for snapshot: Dictionary in _depth_snapshots:
		if int(snapshot.get("depth", 0)) == depth:
			return snapshot
	return {}


func _run_timing_probes(
	openings: Array[Dictionary],
	depth_mode: StringName,
	use_internal_pv_ordering: bool,
	use_history_ordering: bool,
	use_transposition_table: bool,
	transposition_table_mib: int
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if openings.is_empty():
		return result
	var indices: Array[int] = [0, floori(float(openings.size()) / 2.0), openings.size() - 1]
	var observed: Dictionary = {}
	for opening_index: int in indices:
		if observed.has(opening_index):
			continue
		observed[opening_index] = true
		var opening: Dictionary = openings[opening_index]
		var state: State = opening.get("state") as State
		var timing_limits: Dictionary = {
			"max_nodes": TIMING_NODE_LIMIT,
			"profile": &"enhanced",
			"use_lazy_transitions": true,
			"use_pvs": false,
			"use_tactical_extension": false,
			"use_evaluation_cache": false,
			"evaluator_profile": &"baseline",
			"collect_search_diagnostics": true,
			"depth_mode": depth_mode,
			"use_internal_pv_ordering": use_internal_pv_ordering,
			"use_history_ordering": use_history_ordering,
			"use_transposition_table": use_transposition_table,
			"transposition_table_mib": transposition_table_mib,
		}
		var profile_result: Dictionary = Search.find_best_action_iterative(
			state.duplicate_state(), state.active_player, timing_limits
		)
		var elapsed_usec: float = float(profile_result.get("elapsed_seconds", 0.0)) * 1_000_000.0
		var measured_usec: int = (
			int(profile_result.get("time_legal_actions_usec", 0))
			+ int(profile_result.get("time_order_usec", 0))
			+ int(profile_result.get("time_apply_usec", 0))
			+ int(profile_result.get("time_key_usec", 0))
			+ int(profile_result.get("time_evaluate_usec", 0))
		)
		result.append({
			"game_id": String(opening.get("game_id", &"missing")),
			"node_limit": TIMING_NODE_LIMIT,
			"nodes": int(profile_result.get("nodes", 0)),
			"elapsed_seconds": float(profile_result.get("elapsed_seconds", 0.0)),
			"time_legal_actions_usec": int(profile_result.get("time_legal_actions_usec", 0)),
			"time_order_usec": int(profile_result.get("time_order_usec", 0)),
			"time_apply_usec": int(profile_result.get("time_apply_usec", 0)),
			"time_key_usec": int(profile_result.get("time_key_usec", 0)),
			"time_evaluate_usec": int(profile_result.get("time_evaluate_usec", 0)),
			"ordered_nodes": int(profile_result.get("ordered_nodes", 0)),
			"visited_children": int(profile_result.get("visited_children", 0)),
			"cutoff_first_child": int(profile_result.get("cutoff_first_child", 0)),
			"cutoff_second_child": int(profile_result.get("cutoff_second_child", 0)),
			"cutoff_third_fourth_child": int(profile_result.get("cutoff_third_fourth_child", 0)),
			"cutoff_fifth_eighth_child": int(profile_result.get("cutoff_fifth_eighth_child", 0)),
			"cutoff_ninth_or_later_child": int(profile_result.get("cutoff_ninth_or_later_child", 0)),
			"pv_queries": int(profile_result.get("pv_queries", 0)),
			"pv_hits": int(profile_result.get("pv_hits", 0)),
			"pv_legal_hits": int(profile_result.get("pv_legal_hits", 0)),
			"pv_illegal_hits": int(profile_result.get("pv_illegal_hits", 0)),
			"history_queries": int(profile_result.get("history_queries", 0)),
			"history_hits": int(profile_result.get("history_hits", 0)),
			"history_cutoffs": int(profile_result.get("history_cutoffs", 0)),
			"transposition_table_probes": int(profile_result.get("transposition_table_probes", 0)),
			"transposition_table_hits": int(profile_result.get("transposition_table_hits", 0)),
			"transposition_exact_returns": int(profile_result.get("transposition_exact_returns", 0)),
			"transposition_bound_cutoffs": int(profile_result.get("transposition_bound_cutoffs", 0)),
			"time_other_usec": maxi(int(elapsed_usec) - measured_usec, 0),
		})
	return result


func _summarize(
	samples: Array[Dictionary],
	timing_samples: Array[Dictionary],
	budget_seconds: float,
	depth_mode: StringName
) -> Dictionary:
	var depth_histogram: Dictionary = {}
	var depth_total: int = 0
	var target_depth_completed: int = 0
	var baseline_depth_seconds_total: float = 0.0
	var baseline_depth_count: int = 0
	var baseline_snapshot_count: int = 0
	var estimated_speedup_total: float = 0.0
	var estimated_speedup_count: int = 0
	var total_nodes: int = 0
	var total_search_seconds: float = 0.0
	var transposition_probes: int = 0
	var transposition_hits: int = 0
	var transposition_completed_hits: int = 0
	var transposition_leaf_probes: int = 0
	var transposition_leaf_completed_hits: int = 0
	var transposition_internal_probes: int = 0
	var transposition_internal_completed_hits: int = 0
	var transposition_state_hits: int = 0
	var transposition_unique_keys: int = 0
	var transposition_completed_keys: int = 0
	var transposition_unique_states: int = 0
	var transposition_table_probes: int = 0
	var transposition_table_hits: int = 0
	var transposition_exact_returns: int = 0
	var transposition_bound_cutoffs: int = 0
	var transposition_stores: int = 0
	var transposition_updates: int = 0
	var transposition_replacements: int = 0
	var transposition_collisions: int = 0
	var transposition_move_queries: int = 0
	var transposition_move_legal_hits: int = 0
	var transposition_move_illegal_hits: int = 0
	var transposition_allocation_fallbacks: int = 0
	var compact_key_length_total: int = 0
	var fallback_count: int = 0
	var extra_play_states: int = 0
	var extra_play_plans_reused: int = 0
	var extra_play_fresh_searches: int = 0
	var extra_play_fresh_target_depth_completed: int = 0
	for sample: Dictionary in samples:
		var completed_depth: int = int(sample.get("completed_depth", 0))
		var depth_key: String = str(completed_depth)
		depth_histogram[depth_key] = int(depth_histogram.get(depth_key, 0)) + 1
		depth_total += completed_depth
		total_nodes += int(sample.get("nodes", 0))
		total_search_seconds += float(sample.get("elapsed_seconds", 0.0))
		transposition_probes += int(sample.get("transposition_probes", 0))
		transposition_hits += int(sample.get("transposition_hits", 0))
		transposition_completed_hits += int(sample.get("transposition_completed_hits", 0))
		transposition_leaf_probes += int(sample.get("transposition_leaf_probes", 0))
		transposition_leaf_completed_hits += int(sample.get("transposition_leaf_completed_hits", 0))
		transposition_internal_probes += int(sample.get("transposition_internal_probes", 0))
		transposition_internal_completed_hits += int(sample.get("transposition_internal_completed_hits", 0))
		transposition_state_hits += int(sample.get("transposition_state_hits", 0))
		transposition_unique_keys += int(sample.get("transposition_unique_keys", 0))
		transposition_completed_keys += int(sample.get("transposition_completed_keys", 0))
		transposition_unique_states += int(sample.get("transposition_unique_states", 0))
		transposition_table_probes += int(sample.get("transposition_table_probes", 0))
		transposition_table_hits += int(sample.get("transposition_table_hits", 0))
		transposition_exact_returns += int(sample.get("transposition_exact_returns", 0))
		transposition_bound_cutoffs += int(sample.get("transposition_bound_cutoffs", 0))
		transposition_stores += int(sample.get("transposition_stores", 0))
		transposition_updates += int(sample.get("transposition_updates", 0))
		transposition_replacements += int(sample.get("transposition_replacements", 0))
		transposition_collisions += int(sample.get("transposition_collisions", 0))
		transposition_move_queries += int(sample.get("transposition_move_queries", 0))
		transposition_move_legal_hits += int(sample.get("transposition_move_legal_hits", 0))
		transposition_move_illegal_hits += int(sample.get("transposition_move_illegal_hits", 0))
		if bool(sample.get("transposition_table_allocation_fallback", false)):
			transposition_allocation_fallbacks += 1
		compact_key_length_total += int(sample.get("state_key_length", 0))
		if bool(sample.get("used_fallback", false)):
			fallback_count += 1
		var extra_play: Dictionary = sample.get("extra_play", {}) as Dictionary
		if bool(extra_play.get("entered_extra_play", false)):
			extra_play_states += 1
		if bool(extra_play.get("plan_reused", false)):
			extra_play_plans_reused += 1
		if bool(extra_play.get("fresh_search", false)):
			extra_play_fresh_searches += 1
			if int(extra_play.get("completed_depth", 0)) >= TARGET_DEPTH:
				extra_play_fresh_target_depth_completed += 1
		if completed_depth >= TARGET_DEPTH:
			target_depth_completed += 1
		for snapshot_value: Variant in sample.get("depth_snapshots", []):
			var snapshot: Dictionary = snapshot_value as Dictionary
			if int(snapshot.get("depth", 0)) == BASELINE_DEPTH:
				baseline_depth_seconds_total += float(
					snapshot.get("elapsed_seconds", 0.0)
				)
				baseline_depth_count += 1
				if not String(snapshot.get("action_key", "")).is_empty():
					baseline_snapshot_count += 1
				break
		var speedup_value: Variant = sample.get("estimated_speedup_for_target_depth")
		if speedup_value != null:
			estimated_speedup_total += float(speedup_value)
			estimated_speedup_count += 1
	var timing_probe_nodes: int = 0
	var timing_probe_elapsed_seconds: float = 0.0
	var timing_probe_key_usec: int = 0
	for timing_sample: Dictionary in timing_samples:
		timing_probe_nodes += int(timing_sample.get("nodes", 0))
		timing_probe_elapsed_seconds += float(
			timing_sample.get("elapsed_seconds", 0.0)
		)
		timing_probe_key_usec += int(timing_sample.get("time_key_usec", 0))
	return {
		"depth_unit": String(depth_mode),
		"depth_mode": String(depth_mode),
		"target_depth": TARGET_DEPTH,
		"depth_histogram": depth_histogram,
		"target_depth_completed": target_depth_completed,
		"average_completed_depth": (
			float(depth_total) / float(samples.size())
			if not samples.is_empty()
			else 0.0
		),
		"average_baseline_depth_seconds": (
			baseline_depth_seconds_total / float(baseline_depth_count)
			if baseline_depth_count > 0
			else 0.0
		),
		"average_estimated_speedup_for_target_depth": (
			estimated_speedup_total / float(estimated_speedup_count)
			if estimated_speedup_count > 0
			else null
		),
		"total_nodes": total_nodes,
		"total_search_seconds": total_search_seconds,
		"nodes_per_second": (
			float(total_nodes) / total_search_seconds
			if total_search_seconds > 0.0
			else 0.0
		),
		"transposition_probes": transposition_probes,
		"transposition_hits": transposition_hits,
		"transposition_hit_rate": (
			float(transposition_hits) / float(transposition_probes)
			if transposition_probes > 0
			else 0.0
		),
		"transposition_completed_hits": transposition_completed_hits,
		"transposition_completed_hit_rate": (
			float(transposition_completed_hits) / float(transposition_probes)
			if transposition_probes > 0
			else 0.0
		),
		"transposition_leaf_probes": transposition_leaf_probes,
		"transposition_leaf_completed_hits": transposition_leaf_completed_hits,
		"transposition_leaf_completed_hit_rate": (
			float(transposition_leaf_completed_hits) / float(transposition_leaf_probes)
			if transposition_leaf_probes > 0
			else 0.0
		),
		"transposition_internal_probes": transposition_internal_probes,
		"transposition_internal_completed_hits": transposition_internal_completed_hits,
		"transposition_internal_completed_hit_rate": (
			float(transposition_internal_completed_hits) / float(transposition_internal_probes)
			if transposition_internal_probes > 0
			else 0.0
		),
		"transposition_state_hits": transposition_state_hits,
		"transposition_state_hit_rate": (
			float(transposition_state_hits) / float(transposition_probes)
			if transposition_probes > 0
			else 0.0
		),
		"transposition_unique_keys": transposition_unique_keys,
		"transposition_completed_keys": transposition_completed_keys,
		"transposition_unique_states": transposition_unique_states,
		"transposition_table_probes": transposition_table_probes,
		"transposition_table_hits": transposition_table_hits,
		"transposition_table_hit_rate": (
			float(transposition_table_hits) / float(transposition_table_probes)
			if transposition_table_probes > 0
			else 0.0
		),
		"transposition_exact_returns": transposition_exact_returns,
		"transposition_bound_cutoffs": transposition_bound_cutoffs,
		"transposition_stores": transposition_stores,
		"transposition_updates": transposition_updates,
		"transposition_replacements": transposition_replacements,
		"transposition_collisions": transposition_collisions,
		"transposition_move_queries": transposition_move_queries,
		"transposition_move_legal_hits": transposition_move_legal_hits,
		"transposition_move_illegal_hits": transposition_move_illegal_hits,
		"transposition_allocation_fallbacks": transposition_allocation_fallbacks,
		"baseline_snapshot_count": baseline_snapshot_count,
		"fallback_count": fallback_count,
		"extra_play_states": extra_play_states,
		"extra_play_plans_reused": extra_play_plans_reused,
		"extra_play_fresh_searches": extra_play_fresh_searches,
		"extra_play_fresh_target_depth_completed": (
			extra_play_fresh_target_depth_completed
		),
		"average_initial_compact_key_length": (
			float(compact_key_length_total) / float(samples.size())
			if not samples.is_empty()
			else 0.0
		),
		"timing_probe_nodes": timing_probe_nodes,
		"timing_probe_elapsed_seconds": timing_probe_elapsed_seconds,
		"timing_probe_key_usec": timing_probe_key_usec,
		"timing_probe_key_usec_per_node": (
			float(timing_probe_key_usec) / float(timing_probe_nodes)
			if timing_probe_nodes > 0
			else 0.0
		),
		"budget_seconds": budget_seconds,
	}


func _build_unique_openings(opening_set: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var observed_state_keys: Dictionary = {}
	var matchups: Array[Dictionary] = (
		EnemyManifest.get_extra_play_cap_matchups()
		if opening_set == &"extra_play_cap"
		else EnemyManifest.get_matchups_for_mode(&"quick")
	)
	for matchup: Dictionary in matchups:
		for game: Dictionary in EnemyManifest.expand_matchup(matchup):
			var built: Dictionary = EnemyStateFactory.build(game, matchup)
			var metadata: Dictionary = built.get("metadata", {}) as Dictionary
			var state: State = built.get("state") as State
			var exact_state_key: String = String(metadata.get("initial_state_key", ""))
			if observed_state_keys.has(exact_state_key):
				continue
			observed_state_keys[exact_state_key] = true
			result.append({
				"game_id": StringName(metadata.get("game_id", &"missing")),
				"matchup_id": StringName(metadata.get("matchup_id", &"missing")),
				"state_key": StateKey.build_compact(state),
				"root_legal_actions": Simulator.get_legal_actions(state).size(),
				"state": state,
			})
	return result


func _write_report(report: Dictionary, opening_set: StringName) -> String:
	var absolute_directory: String = ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return ""
	var filename: String = (
		"production-opening-depth-extra-play-cap-%d.json"
		if opening_set == &"extra_play_cap"
		else "production-opening-depth-%d.json"
	) % int(Time.get_unix_time_from_system())
	var absolute_path: String = absolute_directory.path_join(filename)
	var file: FileAccess = FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	return absolute_path


func _parse_options() -> Dictionary:
	var result: Dictionary = {
		"budget_seconds": DEFAULT_BUDGET_SECONDS,
		"max_openings": DEFAULT_MAX_OPENINGS,
		"depth_mode": &"self_turn",
		"opening_set": &"quick_unique",
		"use_internal_pv_ordering": false,
		"use_history_ordering": false,
		"use_transposition_table": false,
		"transposition_table_mib": 8,
		"collect_transposition_diagnostics": false,
	}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--budget-seconds="):
			result["budget_seconds"] = maxf(
				float(argument.trim_prefix("--budget-seconds=")),
				0.001
			)
		elif argument.begins_with("--max-openings="):
			result["max_openings"] = maxi(
				int(argument.trim_prefix("--max-openings=")),
				1
			)
		elif argument.begins_with("--depth-mode="):
			var requested_mode := StringName(argument.trim_prefix("--depth-mode="))
			if requested_mode not in [&"complete_round", &"self_turn"]:
				push_error("Unsupported depth mode: %s" % requested_mode)
				continue
			result["depth_mode"] = requested_mode
		elif argument.begins_with("--opening-set="):
			var requested_set := StringName(argument.trim_prefix("--opening-set="))
			if requested_set not in [&"quick_unique", &"extra_play_cap"]:
				push_error("Unsupported opening set: %s" % requested_set)
				continue
			result["opening_set"] = requested_set
		elif argument == "--use-internal-pv-ordering":
			result["use_internal_pv_ordering"] = true
		elif argument == "--use-history-ordering":
			result["use_history_ordering"] = true
		elif argument == "--use-transposition-table":
			result["use_transposition_table"] = true
		elif argument.begins_with("--transposition-table-mib="):
			result["transposition_table_mib"] = maxi(
				int(argument.trim_prefix("--transposition-table-mib=")),
				0
			)
		elif argument == "--collect-transposition-diagnostics":
			result["collect_transposition_diagnostics"] = true
	return result
