class_name DuelAIBenchmark
extends SceneTree

const Fixtures = preload("res://tests/benchmarks/ai_benchmark_fixtures.gd")
const EnemyManifest = preload("res://tests/benchmarks/enemy_ai_benchmark_manifest.gd")
const EnemyStateFactory = preload("res://tests/benchmarks/enemy_ai_benchmark_state_factory.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Search = preload("res://scripts/duel_search.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")

const EXTENDED_NODE_LIMIT: int = 1_500
const SUCCESSFUL_ACTION_WATCHDOG: int = 256


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


static func run_enemy_matchups(
	matchups: Array[Dictionary],
	limits: Dictionary,
	max_actions: int = SUCCESSFUL_ACTION_WATCHDOG,
	enhanced_overrides: Dictionary = {},
	baseline_overrides: Dictionary = {},
	report_progress: bool = false
) -> Dictionary:
	var games: Array[Dictionary] = []
	for matchup: Dictionary in matchups:
		var matchup_games: Array[Dictionary] = []
		for game_spec: Dictionary in EnemyManifest.expand_matchup(matchup):
			var game: Dictionary = run_enemy_game(
				game_spec,
				matchup,
				limits,
				max_actions,
				enhanced_overrides,
				baseline_overrides
			)
			games.append(game)
			matchup_games.append(game)
		if report_progress:
			var matchup_points: float = 0.0
			var matchup_incomplete: int = 0
			for game: Dictionary in matchup_games:
				matchup_points += float(game.get("enhanced_match_points", 0.0))
				if not bool(game.get("terminal", false)):
					matchup_incomplete += 1
			print(
				"AI_BENCHMARK_MATCHUP id=%s games=4 enhanced=%.1f/4 incomplete=%d"
				% [matchup.get("id", "missing"), matchup_points, matchup_incomplete]
			)
	return aggregate_enemy_games(games, matchups)


static func run_enemy_game(
	game_spec: Dictionary,
	matchup: Dictionary,
	limits: Dictionary,
	max_actions: int = SUCCESSFUL_ACTION_WATCHDOG,
	enhanced_overrides: Dictionary = {},
	baseline_overrides: Dictionary = {}
) -> Dictionary:
	var built: Dictionary = EnemyStateFactory.build(game_spec, matchup)
	var build_errors: Array[String] = EnemyStateFactory.validate_built_game(built)
	var metadata: Dictionary = built.get("metadata", {}) as Dictionary
	if not build_errors.is_empty():
		return _failed_enemy_game(metadata, &"invalid_initial_state", build_errors)
	var state = built.get("state")
	var decisions: Array[Dictionary] = []
	var invalid_reason: StringName = &""
	var profile_by_owner: Dictionary = game_spec.get("profile_by_owner", {}) as Dictionary
	while not Simulator.is_terminal(state) and decisions.size() < maxi(max_actions, 1):
		var moving_owner: int = state.active_player
		var legal_actions: Array = Simulator.get_legal_actions(state)
		if legal_actions.is_empty():
			invalid_reason = &"missing_action"
			break
		var profile := StringName(profile_by_owner.get(moving_owner, &"baseline"))
		var search_limits: Dictionary = limits.duplicate(true)
		var overrides: Dictionary = (
			enhanced_overrides if profile == &"enhanced" else baseline_overrides
		)
		for override_key: Variant in overrides:
			search_limits[override_key] = overrides[override_key]
		search_limits["profile"] = profile
		var fallback = Simulator.choose_greedy_action(state)
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
		decisions.append(_decision_record(moving_owner, profile, action, result, used_fallback))
		var transition: Dictionary = Simulator.apply_action(state, action)
		if not bool(transition.get("valid", false)):
			invalid_reason = &"invalid_transition"
			break
		var next_state: Variant = transition.get("state", null)
		if next_state == null:
			invalid_reason = &"missing_transition_state"
			break
		state = next_state
	var terminal: bool = Simulator.is_terminal(state)
	if not terminal and invalid_reason == &"":
		invalid_reason = &"action_limit"
	var player_score: int = Simulator.score_difference(state, Rules.PLAYER_OWNER)
	var winner_owner: int = (
		Rules.PLAYER_OWNER
		if player_score > 0
		else Rules.OPPONENT_OWNER if player_score < 0 else 0
	)
	var enhanced_owner: int = _owner_for_profile(profile_by_owner, &"enhanced")
	var enhanced_points: float = 0.0
	if terminal:
		if winner_owner == 0:
			enhanced_points = 0.5
		elif winner_owner == enhanced_owner:
			enhanced_points = 1.0
	var result_game: Dictionary = metadata.duplicate(true)
	result_game.merge({
		"terminal": terminal,
		"invalid_reason": invalid_reason,
		"actions": decisions.size(),
		"decisions": decisions,
		"player_score_difference": player_score,
		"winner_owner": winner_owner,
		"winner_profile": (
			StringName(profile_by_owner.get(winner_owner, &"")) if winner_owner != 0 else &""
		),
		"enhanced_owner": enhanced_owner,
		"enhanced_match_points": enhanced_points,
	}, true)
	return result_game


static func aggregate_enemy_games(
	games: Array[Dictionary],
	matchups: Array[Dictionary]
) -> Dictionary:
	var enhanced_points: float = 0.0
	var incomplete_games: int = 0
	var invalid_games: int = 0
	var enhanced_decisions: int = 0
	var baseline_decisions: int = 0
	var enhanced_fallbacks: int = 0
	var baseline_fallbacks: int = 0
	var by_level: Dictionary = {}
	var by_matchup: Dictionary = {}
	var by_enemy_deck: Dictionary = {}
	var by_first_second: Dictionary = {}
	var observed_game_ids: Dictionary = {}
	var duplicate_game_ids: Array[StringName] = []
	for game: Dictionary in games:
		var game_id := StringName(game.get("game_id", &"missing"))
		if observed_game_ids.has(game_id):
			duplicate_game_ids.append(game_id)
		else:
			observed_game_ids[game_id] = true
		var points: float = float(game.get("enhanced_match_points", 0.0))
		enhanced_points += points
		if not bool(game.get("terminal", false)):
			incomplete_games += 1
		if StringName(game.get("invalid_reason", &"")) != &"":
			invalid_games += 1
		var matchup_id: String = String(game.get("matchup_id", "missing"))
		_add_breakdown(by_matchup, matchup_id, points)
		var level_by_owner: Dictionary = game.get("level_by_owner", {}) as Dictionary
		var level_one: int = int(level_by_owner.get(Rules.PLAYER_OWNER, 0))
		var level_two: int = int(level_by_owner.get(Rules.OPPONENT_OWNER, 0))
		var level_key: String = str(level_one) if level_one == level_two else "%d-%d" % [level_one, level_two]
		_add_breakdown(by_level, level_key, points)
		var enhanced_owner: int = int(game.get("enhanced_owner", 0))
		var enemy_by_owner: Dictionary = game.get("enemy_by_owner", {}) as Dictionary
		_add_breakdown(by_enemy_deck, String(enemy_by_owner.get(enhanced_owner, &"missing")), points)
		_add_breakdown(
			by_first_second,
			"first" if enhanced_owner == Rules.PLAYER_OWNER else "second",
			points
		)
		for decision: Dictionary in game.get("decisions", []):
			if StringName(decision.get("profile", &"")) == &"enhanced":
				enhanced_decisions += 1
				if bool(decision.get("used_fallback", false)):
					enhanced_fallbacks += 1
			else:
				baseline_decisions += 1
				if bool(decision.get("used_fallback", false)):
					baseline_fallbacks += 1
	var expected_game_ids: Dictionary = {}
	for expected: Dictionary in EnemyManifest.expand_matchups(matchups):
		expected_game_ids[StringName(expected.get("id", &""))] = true
	var missing_game_ids: Array[StringName] = []
	for expected_id: Variant in expected_game_ids:
		if not observed_game_ids.has(expected_id):
			missing_game_ids.append(StringName(expected_id))
	var depth_samples: Array[Dictionary] = _build_enemy_depth_samples(games)
	var non_regressing: int = 0
	for sample: Dictionary in depth_samples:
		if int(sample.get("enhanced_depth", 0)) >= int(sample.get("baseline_depth", 0)):
			non_regressing += 1
	var maximum_points: float = float(games.size())
	var enhanced_percent: float = (
		enhanced_points * 100.0 / maximum_points if maximum_points > 0.0 else 0.0
	)
	var depth_percent: float = (
		float(non_regressing) * 100.0 / float(depth_samples.size())
		if not depth_samples.is_empty()
		else 0.0
	)
	var enhanced_fallback_rate: float = (
		float(enhanced_fallbacks) / float(enhanced_decisions)
		if enhanced_decisions > 0
		else 0.0
	)
	var baseline_fallback_rate: float = (
		float(baseline_fallbacks) / float(baseline_decisions)
		if baseline_decisions > 0
		else 0.0
	)
	var passed_gate: bool = (
		incomplete_games == 0
		and invalid_games == 0
		and missing_game_ids.is_empty()
		and duplicate_game_ids.is_empty()
		and enhanced_percent >= 55.0
		and depth_percent >= 75.0
		and enhanced_fallback_rate <= baseline_fallback_rate
	)
	return {
		"fixture_version": EnemyStateFactory.VERSION,
		"roster_count": EnemyManifest.get_roster().size(),
		"matchup_count": matchups.size(),
		"game_count": games.size(),
		"games": games,
		"enhanced_match_points": enhanced_points,
		"maximum_match_points": maximum_points,
		"enhanced_match_points_percent": enhanced_percent,
		"depth_samples": depth_samples,
		"depth_non_regression_percent": depth_percent,
		"enhanced_fallback_rate": enhanced_fallback_rate,
		"baseline_fallback_rate": baseline_fallback_rate,
		"incomplete_games": incomplete_games,
		"invalid_games": invalid_games,
		"missing_game_ids": missing_game_ids,
		"duplicate_game_ids": duplicate_game_ids,
		"breakdown": {
			"level": by_level,
			"matchup": by_matchup,
			"enemy_deck": by_enemy_deck,
			"first_second": by_first_second,
		},
		"card_id_coverage": EnemyManifest.get_card_id_coverage(matchups),
		"passed_gate": passed_gate,
	}


static func _decision_record(
	owner_id: int,
	profile: StringName,
	action: Variant,
	search_result: Dictionary,
	used_fallback: bool
) -> Dictionary:
	return {
		"owner": owner_id,
		"profile": profile,
		"action_key": action.canonical_key(),
		"score": int(search_result.get("score", 0)),
		"completed_depth": int(search_result.get("completed_depth", 0)),
		"max_tactical_depth": int(search_result.get("max_tactical_depth", 0)),
		"tactical_candidates_scanned": int(search_result.get("tactical_candidates_scanned", 0)),
		"tactical_actions_searched": int(search_result.get("tactical_actions_searched", 0)),
		"nodes": int(search_result.get("nodes", 0)),
		"generated_actions": int(search_result.get("generated_actions", 0)),
		"applied_transitions": int(search_result.get("applied_transitions", 0)),
		"cutoffs": int(search_result.get("cutoffs", 0)),
		"transposition_hits": int(search_result.get("transposition_hits", 0)),
		"pvs_probes": int(search_result.get("pvs_probes", 0)),
		"pvs_researches": int(search_result.get("pvs_researches", 0)),
		"evaluation_cache_hits": int(search_result.get("evaluation_cache_hits", 0)),
		"elapsed_seconds": float(search_result.get("elapsed_seconds", 0.0)),
		"completion_reason": StringName(search_result.get("completion_reason", &"")),
		"used_fallback": used_fallback,
	}


static func _build_enemy_depth_samples(games: Array[Dictionary]) -> Array[Dictionary]:
	var by_state: Dictionary = {}
	for game: Dictionary in games:
		var decisions: Array = game.get("decisions", []) as Array
		if decisions.is_empty():
			continue
		var initial: Dictionary = decisions[0] as Dictionary
		var state_key: String = String(game.get("initial_state_key", ""))
		var sample: Dictionary = by_state.get(state_key, {
			"initial_state_key": state_key,
			"matchup_id": game.get("matchup_id", &""),
		})
		var profile := StringName(initial.get("profile", &""))
		sample["%s_depth" % profile] = int(initial.get("completed_depth", 0))
		sample["%s_fallback" % profile] = bool(initial.get("used_fallback", true))
		by_state[state_key] = sample
	var result: Array[Dictionary] = []
	for state_key: Variant in by_state:
		var sample: Dictionary = by_state[state_key]
		if sample.has("enhanced_depth") and sample.has("baseline_depth"):
			result.append(sample)
	result.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return String(first.get("initial_state_key", "")) < String(second.get("initial_state_key", ""))
	)
	return result


static func _add_breakdown(target: Dictionary, key: String, points: float) -> void:
	var entry: Dictionary = target.get(key, {"games": 0, "enhanced_points": 0.0})
	entry["games"] = int(entry.get("games", 0)) + 1
	entry["enhanced_points"] = float(entry.get("enhanced_points", 0.0)) + points
	entry["enhanced_percent"] = float(entry["enhanced_points"]) * 100.0 / float(entry["games"])
	target[key] = entry


static func _owner_for_profile(profile_by_owner: Dictionary, profile: StringName) -> int:
	for owner_id: int in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		if StringName(profile_by_owner.get(owner_id, &"")) == profile:
			return owner_id
	return 0


static func _failed_enemy_game(
	metadata: Dictionary,
	reason: StringName,
	errors: Array[String]
) -> Dictionary:
	var result: Dictionary = metadata.duplicate(true)
	result.merge({
		"terminal": false,
		"invalid_reason": reason,
		"errors": errors,
		"actions": 0,
		"decisions": [],
		"winner_owner": 0,
		"enhanced_owner": _owner_for_profile(
			metadata.get("profile_by_owner", {}) as Dictionary,
			&"enhanced"
		),
		"enhanced_match_points": 0.0,
	}, true)
	return result


func _run_command_line() -> void:
	var mode: String = "Quick"
	var variant: String = "Final"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--variant="):
			variant = argument.trim_prefix("--variant=")
	var mode_key := StringName(mode.to_lower())
	if mode_key not in [&"quick", &"pilot", &"extended", &"production"]:
		push_error("AI_BENCHMARK_FAILED unknown_mode=%s" % mode)
		quit(1)
		return
	var enhanced_overrides: Dictionary = _variant_overrides(variant)
	var summary: Dictionary
	if mode_key == &"pilot":
		summary = _run_pilot(enhanced_overrides)
	else:
		var config: Dictionary = _mode_config(mode_key)
		var matchups: Array[Dictionary] = EnemyManifest.get_matchups_for_mode(mode_key)
		var started_usec: int = Time.get_ticks_usec()
		summary = run_enemy_matchups(
			matchups,
			config.get("limits", {}) as Dictionary,
			SUCCESSFUL_ACTION_WATCHDOG,
			enhanced_overrides,
			{},
			true
		)
		summary["elapsed_seconds"] = float(Time.get_ticks_usec() - started_usec) / 1_000_000.0
		summary["limits"] = (config.get("limits", {}) as Dictionary).duplicate(true)
		summary["roster"] = EnemyManifest.get_roster()
		summary["matchups"] = matchups
	summary["mode"] = mode
	summary["variant"] = variant
	var output_path: String = _write_report(summary, mode, variant)
	if output_path.is_empty():
		quit(1)
		return
	var enforce_gate: bool = mode_key == &"extended" and variant.to_lower() == "final"
	var passed: bool = bool(summary.get("passed_gate", false))
	var status: String = "FAILED" if enforce_gate and not passed else "PASSED"
	print(
		"AI_BENCHMARK_%s mode=%s variant=%s matchups=%d games=%d points=%.1f%% depth=%.1f%% enhanced_fallback=%.3f baseline_fallback=%.3f incomplete=%d invalid=%d elapsed=%.1fs output=%s"
		% [
			status,
			mode,
			variant,
			int(summary.get("matchup_count", 0)),
			int(summary.get("game_count", 0)),
			float(summary.get("enhanced_match_points_percent", 0.0)),
			float(summary.get("depth_non_regression_percent", 0.0)),
			float(summary.get("enhanced_fallback_rate", 0.0)),
			float(summary.get("baseline_fallback_rate", 0.0)),
			int(summary.get("incomplete_games", 0)),
			int(summary.get("invalid_games", 0)),
			float(summary.get("elapsed_seconds", 0.0)),
			output_path,
		]
	)
	quit(1 if enforce_gate and not passed else 0)


func _run_pilot(enhanced_overrides: Dictionary) -> Dictionary:
	var matchups: Array[Dictionary] = EnemyManifest.get_matchups_for_mode(&"pilot")
	var attempts: Array[Dictionary] = []
	var chosen_node_limit: int = 0
	var chosen_summary: Dictionary = {}
	for node_limit: int in [10_000, 5_000, 3_000, 1_500]:
		var started_usec: int = Time.get_ticks_usec()
		var attempt: Dictionary = run_enemy_matchups(
			matchups,
			{"max_nodes": node_limit},
			SUCCESSFUL_ACTION_WATCHDOG,
			enhanced_overrides,
			{},
			true
		)
		var elapsed_seconds: float = float(Time.get_ticks_usec() - started_usec) / 1_000_000.0
		var projected_seconds: float = (
			elapsed_seconds * 112.0 / float(maxi(int(attempt.get("game_count", 0)), 1))
		)
		attempt["node_limit"] = node_limit
		attempt["elapsed_seconds"] = elapsed_seconds
		attempt["projected_extended_seconds"] = projected_seconds
		attempts.append(attempt)
		print(
			"AI_BENCHMARK_PILOT nodes=%d games=%d elapsed=%.1fs projected=%.1fs"
			% [node_limit, int(attempt.get("game_count", 0)), elapsed_seconds, projected_seconds]
		)
		if projected_seconds <= 1_800.0:
			chosen_node_limit = node_limit
			chosen_summary = attempt
			break
	var result: Dictionary = chosen_summary.duplicate(true)
	result["attempts"] = attempts
	result["chosen_node_limit"] = chosen_node_limit
	result["calibration_passed"] = chosen_node_limit > 0
	result["passed_gate"] = chosen_node_limit > 0
	result["roster"] = EnemyManifest.get_roster()
	result["matchups"] = matchups
	return result


func _mode_config(mode: StringName) -> Dictionary:
	match mode:
		&"quick":
			return {"limits": {"max_nodes": 1_500}}
		&"extended":
			return {"limits": {"max_nodes": EXTENDED_NODE_LIMIT}}
		&"production":
			return {"limits": {"budget_seconds": 10.0}}
	return {}


func _write_report(summary: Dictionary, mode: String, variant: String) -> String:
	var output_directory: String = ProjectSettings.globalize_path(
		"res://.summer/local/ai-benchmarks"
	)
	DirAccess.make_dir_recursive_absolute(output_directory)
	var timestamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var output_path: String = output_directory.path_join(
		"%s-%s-v%d-%s.json"
		% [mode.to_lower(), variant.to_lower(), EnemyStateFactory.VERSION, timestamp]
	)
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("AI_BENCHMARK_FAILED unable_to_write=%s" % output_path)
		return ""
	file.store_string(JSON.stringify(summary))
	file.close()
	return output_path


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
