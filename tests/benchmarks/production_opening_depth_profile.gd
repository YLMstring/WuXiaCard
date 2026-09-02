extends SceneTree

const DEFAULT_BUDGET_SECONDS: float = 10.0
const DEFAULT_MAX_OPENINGS: int = 14
const TIMING_NODE_LIMIT: int = 5_000
const TARGET_COMPLETE_ROUND_DEPTH: int = 2
const BASELINE_COMPLETE_ROUND_DEPTH: int = 1
const OUTPUT_DIRECTORY: String = "res://.summer/local/ai-benchmarks"

const Action = preload("res://scripts/duel_action.gd")
const EnemyManifest = preload("res://tests/benchmarks/enemy_ai_benchmark_manifest.gd")
const EnemyStateFactory = preload("res://tests/benchmarks/enemy_ai_benchmark_state_factory.gd")
const Search = preload("res://scripts/duel_search.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")

var _depth_snapshots: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var options: Dictionary = _parse_options()
	var budget_seconds: float = float(options.get("budget_seconds", DEFAULT_BUDGET_SECONDS))
	var max_openings: int = int(options.get("max_openings", DEFAULT_MAX_OPENINGS))
	var openings: Array[Dictionary] = _build_unique_openings()
	if max_openings > 0 and openings.size() > max_openings:
		openings.resize(max_openings)
	var samples: Array[Dictionary] = []
	for opening_index: int in range(openings.size()):
		var sample: Dictionary = _profile_opening(openings[opening_index], budget_seconds)
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
	var timing_samples: Array[Dictionary] = _run_timing_probes(openings)
	var report: Dictionary = {
		"schema_version": 2,
		"created_unix_time": int(Time.get_unix_time_from_system()),
		"fixture_version": EnemyManifest.VERSION,
		"configuration": {
			"backend": "native",
			"budget_seconds": budget_seconds,
			"depth_unit": "complete_round",
			"target_depth": TARGET_COMPLETE_ROUND_DEPTH,
			"profile": "enhanced",
			"use_lazy_transitions": true,
			"use_pvs": false,
			"use_tactical_extension": false,
			"use_evaluation_cache": false,
			"evaluator_profile": "baseline",
			"opening_count": openings.size(),
		},
		"summary": _summarize(samples, timing_samples, budget_seconds),
		"openings": samples,
		"timing_probes": timing_samples,
	}
	var output_path: String = _write_report(report)
	if output_path.is_empty():
		push_error("OPENING_DEPTH_PROFILE_FAILED could not write JSON report")
		quit(1)
		return
	var summary: Dictionary = report.get("summary", {}) as Dictionary
	print(
		(
			"OPENING_DEPTH_PROFILE_COMPLETE openings=%d target_depth=%d completed=%d "
			+ "avg_depth=%.3f avg_depth1_seconds=%.3f report=%s"
		)
		% [
			openings.size(),
			TARGET_COMPLETE_ROUND_DEPTH,
			int(summary.get("target_depth_completed", 0)),
			float(summary.get("average_completed_depth", 0.0)),
			float(summary.get("average_baseline_depth_seconds", 0.0)),
			output_path,
		]
	)
	quit(0)


func _profile_opening(
	opening: Dictionary,
	budget_seconds: float
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
		TARGET_COMPLETE_ROUND_DEPTH
	)
	var estimated_required_seconds: Variant = null
	if not target_depth_snapshot.is_empty():
		estimated_required_seconds = float(
			target_depth_snapshot.get("elapsed_seconds", 0.0)
		)
	elif (
		int(result.get("iteration_depth", 0)) == TARGET_COMPLETE_ROUND_DEPTH
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
	return {
		"game_id": String(opening.get("game_id", &"missing")),
		"matchup_id": String(opening.get("matchup_id", &"missing")),
		"state_key": String(opening.get("state_key", "")),
		"state_key_length": String(opening.get("state_key", "")).length(),
		"exact_state_key_digest": StateKey.build(state).sha256_text(),
		"root_legal_actions": int(opening.get("root_legal_actions", 0)),
		"completed_depth": int(result.get("completed_depth", 0)),
		"attempted_depth": int(result.get("iteration_depth", 0)),
		"elapsed_seconds": float(result.get("elapsed_seconds", 0.0)),
		"nodes": int(result.get("nodes", 0)),
		"generated_actions": int(result.get("generated_actions", 0)),
		"applied_transitions": int(result.get("applied_transitions", 0)),
		"cutoffs": int(result.get("cutoffs", 0)),
		"transposition_hits": int(result.get("transposition_hits", 0)),
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


func _record_depth_progress(progress: Dictionary) -> void:
	var action: Action = progress.get("action") as Action
	_depth_snapshots.append({
		"depth": int(progress.get("completed_depth", 0)),
		"score": int(progress.get("score", 0)),
		"action_key": action.canonical_key() if action != null else "",
		"elapsed_seconds": float(progress.get("elapsed_seconds", 0.0)),
		"nodes": int(progress.get("nodes", 0)),
		"generated_actions": int(progress.get("generated_actions", 0)),
		"applied_transitions": int(progress.get("applied_transitions", 0)),
		"cutoffs": int(progress.get("cutoffs", 0)),
		"transposition_hits": int(progress.get("transposition_hits", 0)),
	})


func _snapshot_for_depth(depth: int) -> Dictionary:
	for snapshot: Dictionary in _depth_snapshots:
		if int(snapshot.get("depth", 0)) == depth:
			return snapshot
	return {}


func _run_timing_probes(
	openings: Array[Dictionary]
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
				"collect_timings": true,
			}
		var profile_result: Dictionary = Search.find_best_action_iterative(
			state.duplicate_state(), state.active_player, timing_limits
		)
		var elapsed_usec: float = float(profile_result.get("elapsed_seconds", 0.0)) * 1_000_000.0
		var measured_usec: int = (
			int(profile_result.get("time_order_usec", 0))
			+ int(profile_result.get("time_apply_usec", 0))
			+ int(profile_result.get("time_key_usec", 0))
			+ int(profile_result.get("time_evaluate_usec", 0))
		)
		result.append({
			"game_id": String(opening.get("game_id", &"missing")),
			"node_limit": TIMING_NODE_LIMIT,
			"nodes": int(profile_result.get("nodes", 0)),
			"elapsed_seconds": float(profile_result.get("elapsed_seconds", 0.0)),
			"time_order_usec": int(profile_result.get("time_order_usec", 0)),
			"time_apply_usec": int(profile_result.get("time_apply_usec", 0)),
			"time_key_usec": int(profile_result.get("time_key_usec", 0)),
			"time_evaluate_usec": int(profile_result.get("time_evaluate_usec", 0)),
			"time_other_usec": maxi(int(elapsed_usec) - measured_usec, 0),
		})
	return result


func _summarize(
	samples: Array[Dictionary],
	timing_samples: Array[Dictionary],
	budget_seconds: float
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
	var compact_key_length_total: int = 0
	var fallback_count: int = 0
	for sample: Dictionary in samples:
		var completed_depth: int = int(sample.get("completed_depth", 0))
		var depth_key: String = str(completed_depth)
		depth_histogram[depth_key] = int(depth_histogram.get(depth_key, 0)) + 1
		depth_total += completed_depth
		total_nodes += int(sample.get("nodes", 0))
		total_search_seconds += float(sample.get("elapsed_seconds", 0.0))
		compact_key_length_total += int(sample.get("state_key_length", 0))
		if bool(sample.get("used_fallback", false)):
			fallback_count += 1
		if completed_depth >= TARGET_COMPLETE_ROUND_DEPTH:
			target_depth_completed += 1
		for snapshot_value: Variant in sample.get("depth_snapshots", []):
			var snapshot: Dictionary = snapshot_value as Dictionary
			if int(snapshot.get("depth", 0)) == BASELINE_COMPLETE_ROUND_DEPTH:
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
		"depth_unit": "complete_round",
		"target_depth": TARGET_COMPLETE_ROUND_DEPTH,
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
		"baseline_snapshot_count": baseline_snapshot_count,
		"fallback_count": fallback_count,
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


func _build_unique_openings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var observed_state_keys: Dictionary = {}
	for matchup: Dictionary in EnemyManifest.get_matchups_for_mode(&"quick"):
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


func _write_report(report: Dictionary) -> String:
	var absolute_directory: String = ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return ""
	var filename: String = "production-opening-depth-%d.json" % int(Time.get_unix_time_from_system())
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
	return result
