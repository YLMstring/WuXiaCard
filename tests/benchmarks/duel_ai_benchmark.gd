class_name DuelAIBenchmark
extends SceneTree

const Fixtures = preload("res://tests/benchmarks/ai_benchmark_fixtures.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Search = preload("res://scripts/duel_search.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")


func _init() -> void:
	call_deferred("_run_command_line")


static func run_paired(
	fixtures: Array[Dictionary],
	first_profile: StringName,
	second_profile: StringName,
	limits: Dictionary,
	max_actions: int = 120,
	first_overrides: Dictionary = {},
	second_overrides: Dictionary = {},
	report_progress: bool = false
) -> Dictionary:
	var games: Array[Dictionary] = []
	var decision_samples: Array[Dictionary] = []
	var first_points: float = 0.0
	var incomplete_games: int = 0
	var first_decisions: int = 0
	var second_decisions: int = 0
	var first_fallbacks: int = 0
	var second_fallbacks: int = 0
	for fixture: Dictionary in fixtures:
		var paired_games: Array[Dictionary] = []
		for first_owner: int in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
			var profile_by_owner: Dictionary = {
				first_owner: first_profile,
				Simulator.other_owner(first_owner): second_profile,
			}
			var overrides_by_owner: Dictionary = {
				first_owner: first_overrides,
				Simulator.other_owner(first_owner): second_overrides,
			}
			var game: Dictionary = run_game(
				fixture,
				profile_by_owner,
				limits,
				max_actions,
				overrides_by_owner
			)
			game["first_profile_owner"] = first_owner
			games.append(game)
			paired_games.append(game)
			for decision_value: Variant in game.get("decisions", []):
				var decision: Dictionary = decision_value as Dictionary
				if StringName(decision.get("profile", &"")) == first_profile:
					first_decisions += 1
					if bool(decision.get("used_fallback", false)):
						first_fallbacks += 1
				else:
					second_decisions += 1
					if bool(decision.get("used_fallback", false)):
						second_fallbacks += 1
			if not bool(game.get("terminal", false)):
				incomplete_games += 1
				continue
			var winner_owner: int = int(game.get("winner_owner", 0))
			if winner_owner == 0:
				first_points += 0.5
			elif winner_owner == first_owner:
				first_points += 1.0
		if paired_games.size() == 2:
			var active_owner: int = int(fixture.get("active_owner", Rules.PLAYER_OWNER))
			var first_initial: Dictionary = _initial_decision_for_profile(
				paired_games,
				active_owner,
				first_profile
			)
			var second_initial: Dictionary = _initial_decision_for_profile(
				paired_games,
				active_owner,
				second_profile
			)
			decision_samples.append({
				"fixture_id": StringName(fixture.get("id", &"missing")),
				"first_depth": int(first_initial.get("completed_depth", 0)),
				"second_depth": int(second_initial.get("completed_depth", 0)),
				"first_fallback": bool(first_initial.get("used_fallback", true)),
				"second_fallback": bool(second_initial.get("used_fallback", true)),
			})
		if report_progress:
			print("AI_BENCHMARK_PROGRESS fixture=%s games=%d" % [fixture.get("id", "missing"), games.size()])
	var maximum_points: float = float(games.size())
	var non_regressing_samples: int = 0
	for sample: Dictionary in decision_samples:
		if int(sample.get("first_depth", 0)) >= int(sample.get("second_depth", 0)):
			non_regressing_samples += 1
	return {
		"fixture_version": Fixtures.VERSION,
		"fixture_count": fixtures.size(),
		"first_profile": first_profile,
		"second_profile": second_profile,
		"games": games,
		"decision_samples": decision_samples,
		"first_match_points": first_points,
		"maximum_match_points": maximum_points,
		"first_match_points_percent": (
			first_points * 100.0 / maximum_points
			if maximum_points > 0.0
			else 0.0
		),
		"incomplete_games": incomplete_games,
		"depth_non_regression_percent": (
			float(non_regressing_samples) * 100.0 / float(decision_samples.size())
			if not decision_samples.is_empty()
			else 0.0
		),
		"first_fallback_rate": (
			float(first_fallbacks) / float(first_decisions)
			if first_decisions > 0
			else 0.0
		),
		"second_fallback_rate": (
			float(second_fallbacks) / float(second_decisions)
			if second_decisions > 0
			else 0.0
		),
	}


static func _initial_decision_for_profile(
	paired_games: Array[Dictionary],
	active_owner: int,
	profile: StringName
) -> Dictionary:
	for game: Dictionary in paired_games:
		var decisions: Array = game.get("decisions", []) as Array
		if decisions.is_empty():
			continue
		var initial: Dictionary = decisions[0] as Dictionary
		if (
			int(initial.get("owner", 0)) == active_owner
			and StringName(initial.get("profile", &"")) == profile
		):
			return initial
	return {}


static func run_game(
	fixture: Dictionary,
	profile_by_owner: Dictionary,
	limits: Dictionary,
	max_actions: int = 120,
	overrides_by_owner: Dictionary = {}
) -> Dictionary:
	var state = Fixtures.build_state(fixture)
	var decisions: Array[Dictionary] = []
	var invalid_reason: StringName = &""
	while not Simulator.is_terminal(state) and decisions.size() < maxi(max_actions, 1):
		var moving_owner: int = state.active_player
		var legal_actions = Simulator.get_legal_actions(state)
		if legal_actions.is_empty():
			invalid_reason = &"missing_action"
			break
		var fallback = Simulator.choose_greedy_action(state)
		var search_limits: Dictionary = limits.duplicate(true)
		var owner_overrides: Dictionary = overrides_by_owner.get(moving_owner, {}) as Dictionary
		for override_key: Variant in owner_overrides:
			search_limits[override_key] = owner_overrides[override_key]
		search_limits["profile"] = StringName(profile_by_owner.get(moving_owner, &"baseline"))
		var result: Dictionary = Search.find_best_action_iterative(
			state,
			moving_owner,
			search_limits
		)
		var action = result.get("action", null)
		var used_fallback: bool = (
			not bool(result.get("has_completed_depth", false))
			or action == null
			or not Simulator.is_action_legal(state, action)
		)
		if used_fallback:
			action = fallback
		if action == null or not Simulator.is_action_legal(state, action):
			invalid_reason = &"illegal_action"
			break
		decisions.append({
			"owner": moving_owner,
			"profile": search_limits["profile"],
			"action_key": action.canonical_key(),
			"score": int(result.get("score", 0)),
			"completed_depth": int(result.get("completed_depth", 0)),
			"max_tactical_depth": int(result.get("max_tactical_depth", 0)),
			"tactical_candidates_scanned": int(result.get("tactical_candidates_scanned", 0)),
			"tactical_actions_searched": int(result.get("tactical_actions_searched", 0)),
			"max_tactical_candidates_per_node": int(result.get("max_tactical_candidates_per_node", 0)),
			"max_tactical_actions_per_node": int(result.get("max_tactical_actions_per_node", 0)),
			"nodes": int(result.get("nodes", 0)),
			"generated_actions": int(result.get("generated_actions", 0)),
			"applied_transitions": int(result.get("applied_transitions", 0)),
			"cutoffs": int(result.get("cutoffs", 0)),
			"transposition_hits": int(result.get("transposition_hits", 0)),
			"pvs_probes": int(result.get("pvs_probes", 0)),
			"pvs_researches": int(result.get("pvs_researches", 0)),
			"evaluation_cache_hits": int(result.get("evaluation_cache_hits", 0)),
			"elapsed_seconds": float(result.get("elapsed_seconds", 0.0)),
			"completion_reason": StringName(result.get("completion_reason", &"")),
			"used_fallback": used_fallback,
		})
		var transition: Dictionary = Simulator.apply_action(state, action)
		if not bool(transition.get("valid", false)):
			invalid_reason = &"invalid_transition"
			break
		state = transition.get("state")
	var terminal: bool = Simulator.is_terminal(state)
	if not terminal and invalid_reason == &"":
		invalid_reason = &"action_limit"
	var player_score: int = Simulator.score_difference(state, Rules.PLAYER_OWNER)
	return {
		"fixture_id": StringName(fixture.get("id", &"missing")),
		"terminal": terminal,
		"invalid_reason": invalid_reason,
		"actions": decisions.size(),
		"decisions": decisions,
		"player_score_difference": player_score,
		"winner_owner": (
			Rules.PLAYER_OWNER
			if player_score > 0
			else Rules.OPPONENT_OWNER if player_score < 0 else 0
		),
	}


func _run_command_line() -> void:
	var mode: String = "Quick"
	var variant: String = "Final"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--variant="):
			variant = argument.trim_prefix("--variant=")
	var fixtures: Array[Dictionary]
	var limits: Dictionary
	match mode.to_lower():
		"production":
			fixtures = Fixtures.quick().slice(0, 2)
			limits = {"budget_seconds": 10.0}
		"extended":
			fixtures = Fixtures.extended()
			limits = {"max_nodes": 10_000}
		_:
			mode = "Quick"
			fixtures = Fixtures.quick()
			limits = {"max_nodes": 1_500}
	var first_overrides: Dictionary = _variant_overrides(variant)
	var summary: Dictionary = run_paired(
		fixtures,
		&"enhanced",
		&"baseline",
		limits,
		120,
		first_overrides,
		{},
		true
	)
	summary["mode"] = mode
	summary["variant"] = variant
	var passed_gate: bool = (
		int(summary.get("incomplete_games", 0)) == 0
		and float(summary.get("first_match_points_percent", 0.0)) >= 55.0
		and float(summary.get("depth_non_regression_percent", 0.0)) >= 75.0
		and float(summary.get("first_fallback_rate", 1.0))
		<= float(summary.get("second_fallback_rate", 0.0))
	)
	summary["passed_gate"] = passed_gate
	var output_directory: String = ProjectSettings.globalize_path("res://.summer/local/ai-benchmarks")
	DirAccess.make_dir_recursive_absolute(output_directory)
	var timestamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var output_path: String = output_directory.path_join(
		"%s-%s-%s.json" % [mode.to_lower(), variant.to_lower(), timestamp]
	)
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("AI_BENCHMARK_FAILED unable_to_write=%s" % output_path)
		quit(1)
		return
	file.store_string(JSON.stringify(summary, "\t"))
	file.close()
	print(
		"AI_BENCHMARK_%s mode=%s variant=%s fixtures=%d games=%d points=%.1f%% depth_non_regression=%.1f%% first_fallback=%.3f second_fallback=%.3f incomplete=%d output=%s" % [
			"PASSED" if mode != "Extended" or variant != "Final" or passed_gate else "FAILED",
			mode,
			variant,
			fixtures.size(),
			(summary.get("games", []) as Array).size(),
			float(summary.get("first_match_points_percent", 0.0)),
			float(summary.get("depth_non_regression_percent", 0.0)),
			float(summary.get("first_fallback_rate", 0.0)),
			float(summary.get("second_fallback_rate", 0.0)),
			int(summary.get("incomplete_games", 0)),
			output_path,
		]
	)
	quit(0 if mode != "Extended" or variant != "Final" or passed_gate else 1)


func _variant_overrides(variant: String) -> Dictionary:
	match variant.to_lower():
		"baselineevaluator":
			return {"evaluator_profile": &"baseline"}
		"notactics":
			return {"use_tactical_extension": false}
		"searchonly":
			return {
				"use_tactical_extension": false,
				"evaluator_profile": &"baseline",
			}
		"lazyonly":
			return {
				"use_pvs": false,
				"use_tactical_extension": false,
				"evaluator_profile": &"baseline",
			}
		"evalonly":
			return {
				"use_lazy_transitions": false,
				"use_pvs": false,
				"use_tactical_extension": false,
				"evaluator_profile": &"enhanced",
			}
		_:
			return {}
