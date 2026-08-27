extends SceneTree

const Fixtures = preload("res://tests/benchmarks/ai_benchmark_fixtures.gd")
const EnemyManifest = preload("res://tests/benchmarks/enemy_ai_benchmark_manifest.gd")
const EnemyStateFactory = preload("res://tests/benchmarks/enemy_ai_benchmark_state_factory.gd")
const Runner = preload("res://tests/benchmarks/duel_ai_benchmark.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_enemy_manifest()
	_check_enemy_state_factory()
	var fixtures: Array[Dictionary] = Fixtures.quick()
	_check(fixtures.size() == 4, "Quick benchmark exposes four versioned fixtures")
	_check(Fixtures.VERSION == 1, "Benchmark fixture schema is versioned")
	for fixture: Dictionary in fixtures:
		var errors: Array[String] = Fixtures.validate_fixture(fixture)
		_check(errors.is_empty(), "Fixture %s validates: %s" % [fixture.get("id", "missing"), errors])
		var first_state = Fixtures.build_state(fixture)
		var second_state = Fixtures.build_state(fixture)
		_check(
			StateKey.build(first_state) == StateKey.build(second_state),
			"Fixture %s rebuilds deterministically" % fixture.get("id", "missing")
		)
		if not first_state.get_hand(1).is_empty():
			(first_state.get_hand(1)[0] as Dictionary)["ki"] = 99
			_check(
				int((second_state.get_hand(1)[0] as Dictionary).get("ki", 0)) != 99,
				"Fixture %s rebuilds without mutable aliases" % fixture.get("id", "missing")
			)
	var extended: Array[Dictionary] = Fixtures.extended()
	_check(extended.size() == 16, "Extended benchmark exposes sixteen versioned fixtures")
	var fixture_ids: Dictionary = {}
	for fixture: Dictionary in extended:
		var fixture_id := StringName(fixture.get("id", &""))
		_check(not fixture_ids.has(fixture_id), "Extended fixture IDs are unique: %s" % fixture_id)
		fixture_ids[fixture_id] = true
		_check(
			Fixtures.validate_fixture(fixture).is_empty(),
			"Extended fixture validates: %s" % fixture_id
		)

	var smoke: Dictionary = Runner.run_paired(
		[fixtures[3]],
		&"baseline",
		&"baseline",
		{"max_depth": 1},
		4
	)
	_check((smoke.get("games", []) as Array).size() == 2, "Paired runner swaps algorithms across two games")
	_check(is_equal_approx(float(smoke.get("first_match_points_percent", -1.0)), 50.0), "Identical profiles produce symmetric 50 percent match points")
	_check(int(smoke.get("incomplete_games", -1)) == 0, "Smoke pair reaches terminal states")
	_check(is_equal_approx(float(smoke.get("depth_non_regression_percent", -1.0)), 100.0), "Identical profiles have no initial-depth regressions")
	_check(
		is_equal_approx(
			float(smoke.get("first_fallback_rate", -1.0)),
			float(smoke.get("second_fallback_rate", -2.0))
		),
		"Identical profiles have matching fallback rates"
	)
	var enemy_smoke_matchups: Array[Dictionary] = [
		EnemyManifest.get_matchups_for_mode(&"quick")[0]
	]
	var enemy_smoke: Dictionary = Runner.run_enemy_matchups(
		enemy_smoke_matchups,
		{"max_depth": 1},
		1
	)
	_check(int(enemy_smoke.get("game_count", 0)) == 4, "Enemy smoke executes one four-game crossover")
	_check(int(enemy_smoke.get("incomplete_games", 0)) == 4, "One-action smoke reports every watchdog stop as incomplete")
	_check(int(enemy_smoke.get("invalid_games", 0)) == 4, "One-action smoke records explicit action-limit reasons")
	_check((enemy_smoke.get("missing_game_ids", []) as Array).is_empty(), "Enemy smoke schedules every required assignment")
	_check((enemy_smoke.get("duplicate_game_ids", []) as Array).is_empty(), "Enemy smoke schedules no duplicate game IDs")
	_check((enemy_smoke.get("depth_samples", []) as Array).size() == 2, "Four-game crossover creates two paired initial-depth samples")

	if _failures == 0:
		print("DUEL_AI_BENCHMARK_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("DUEL_AI_BENCHMARK_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check_enemy_manifest() -> void:
	var roster: Array[Dictionary] = EnemyManifest.get_roster()
	_check(roster.size() == 34, "Enemy benchmark manifest exposes 34 decks")
	var roster_ids: Dictionary = {}
	for enemy: Dictionary in roster:
		var enemy_id := StringName(enemy.get("id", &""))
		_check(not roster_ids.has(enemy_id), "Enemy benchmark roster IDs are unique: %s" % enemy_id)
		roster_ids[enemy_id] = true
		_check((enemy.get("deck", []) as Array).size() == 5, "%s contributes five main cards" % enemy_id)
	var matchups: Array[Dictionary] = EnemyManifest.get_all_matchups()
	_check(matchups.size() == 28, "Enemy benchmark manifest contains 28 matchups")
	var same_level_count: int = 0
	var matchup_ids: Dictionary = {}
	var pair_keys: Dictionary = {}
	for matchup: Dictionary in matchups:
		var matchup_id := StringName(matchup.get("id", &""))
		var first_id := StringName(matchup.get("enemy_a_id", &""))
		var second_id := StringName(matchup.get("enemy_b_id", &""))
		_check(not matchup_ids.has(matchup_id), "Matchup IDs are unique: %s" % matchup_id)
		matchup_ids[matchup_id] = true
		_check(first_id != second_id, "%s is not a self-match" % matchup_id)
		var ordered: Array[String] = [String(first_id), String(second_id)]
		ordered.sort()
		var pair_key: String = "|".join(ordered)
		_check(not pair_keys.has(pair_key), "%s is an unrepeated unordered pair" % matchup_id)
		pair_keys[pair_key] = true
		if int(matchup.get("enemy_a_level", 0)) == int(matchup.get("enemy_b_level", -1)):
			same_level_count += 1
		var games: Array[Dictionary] = EnemyManifest.expand_matchup(matchup)
		_check(games.size() == 4, "%s expands to four balanced games" % matchup_id)
		_check(_assignment_is_balanced(games, first_id), "%s balances enemy A across profile and owner" % matchup_id)
		_check(_assignment_is_balanced(games, second_id), "%s balances enemy B across profile and owner" % matchup_id)
	_check(same_level_count == 25, "Manifest includes all 25 same-level unordered pairs")
	_check(
		EnemyManifest.expand_matchups(matchups).size() == 112,
		"Full enemy benchmark expands to 112 games"
	)
	_check(
		EnemyManifest.get_all_matchups() == matchups,
		"Manifest rebuild is deterministic"
	)
	for mode_fixture: Dictionary in [
		{"mode": &"quick", "matchups": 7, "games": 28},
		{"mode": &"pilot", "matchups": 3, "games": 12},
		{"mode": &"production", "matchups": 4, "games": 16},
	]:
		var selected: Array[Dictionary] = EnemyManifest.get_matchups_for_mode(
			StringName(mode_fixture["mode"])
		)
		_check(selected.size() == int(mode_fixture["matchups"]), "%s selects the approved matchup count" % mode_fixture["mode"])
		_check(EnemyManifest.expand_matchups(selected).size() == int(mode_fixture["games"]), "%s selects the approved game count" % mode_fixture["mode"])


func _assignment_is_balanced(games: Array[Dictionary], enemy_id: StringName) -> bool:
	var observed: Dictionary = {}
	for game: Dictionary in games:
		for owner_id: int in [1, 2]:
			if StringName(game.get("enemy_by_owner", {}).get(owner_id, &"")) != enemy_id:
				continue
			var profile := StringName(game.get("profile_by_owner", {}).get(owner_id, &""))
			observed["%s|%d" % [profile, owner_id]] = true
	return observed.size() == 4


func _check_enemy_state_factory() -> void:
	var matchup: Dictionary = EnemyManifest.get_matchups_for_mode(&"quick")[0]
	var games: Array[Dictionary] = EnemyManifest.expand_matchup(matchup)
	var first_build: Dictionary = EnemyStateFactory.build(games[0], matchup)
	var repeated_build: Dictionary = EnemyStateFactory.build(games[0], matchup)
	var first_state: Variant = first_build.get("state")
	var repeated_state: Variant = repeated_build.get("state")
	_check(
		StateKey.build(first_state) == StateKey.build(repeated_state),
		"Enemy benchmark state rebuilds deterministically"
	)
	(first_state.get_hand(Rules.PLAYER_OWNER)[0] as Dictionary)["ki"] = 99
	_check(
		int((repeated_state.get_hand(Rules.PLAYER_OWNER)[0] as Dictionary).get("ki", 0)) != 99,
		"Enemy benchmark state rebuilds without mutable aliases"
	)
	var profile_swap: Dictionary = EnemyStateFactory.build(games[1], matchup)
	_check(
		StateKey.build(repeated_state) == StateKey.build(profile_swap.get("state")),
		"Swapping AI profiles does not change the opening state"
	)
	var deck_swap: Dictionary = EnemyStateFactory.build(games[2], matchup)
	var deck_swap_state: Variant = deck_swap.get("state")
	var enemy_a := StringName(matchup.get("enemy_a_id", &""))
	var enemy_b := StringName(matchup.get("enemy_b_id", &""))
	_check(
		_card_ids_for_enemy(repeated_state, games[0], enemy_a, true)
		== _card_ids_for_enemy(deck_swap_state, games[2], enemy_a, true),
		"Enemy A keeps its deterministic hand order when owners swap"
	)
	_check(
		_card_ids_for_enemy(repeated_state, games[0], enemy_b, false)
		== _card_ids_for_enemy(deck_swap_state, games[2], enemy_b, false),
		"Enemy B keeps its deterministic side-deck order when owners swap"
	)
	_check(
		Rules.EFFECT_GATE_SELF_CASTRATION
		not in repeated_state.get_enabled_effect_gates(Rules.PLAYER_OWNER),
		"Young Escort Lin Pingzhi disables self-castration in benchmark states"
	)
	_check(
		Rules.EFFECT_GATE_SELF_CASTRATION
		in repeated_state.get_enabled_effect_gates(Rules.OPPONENT_OWNER),
		"Ordinary enemy benchmark decks enable self-castration"
	)
	_check(
		repeated_state.remembered_glyphs_by_owner[Rules.PLAYER_OWNER]
		== EnemyStateFactory.opening_glyphs(repeated_state, Rules.OPPONENT_OWNER)
		and repeated_state.remembered_glyphs_by_owner[Rules.OPPONENT_OWNER]
		== EnemyStateFactory.opening_glyphs(repeated_state, Rules.PLAYER_OWNER),
		"Both benchmark owners remember the opposing five-card opening deck"
	)
	_check(
		EnemyStateFactory.validate_built_game(repeated_build).is_empty(),
		"Enemy benchmark state metadata and runtime IDs validate"
	)


func _card_ids_for_enemy(
	state: Variant,
	game: Dictionary,
	enemy_id: StringName,
	hand: bool
) -> Array[StringName]:
	var owner_id: int = 0
	for candidate_owner: int in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		if StringName(game.get("enemy_by_owner", {}).get(candidate_owner, &"")) == enemy_id:
			owner_id = candidate_owner
			break
	var zone: Array = (
		state.get_hand(owner_id)
		if hand
		else state.decks.get(owner_id, []) as Array
	)
	var result: Array[StringName] = []
	for card_value: Variant in zone:
		result.append(StringName((card_value as Dictionary).get("card_id", &"")))
	return result


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("CHECK_FAILED: %s" % message)
