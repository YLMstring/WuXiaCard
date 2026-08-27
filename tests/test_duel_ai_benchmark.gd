extends SceneTree

const Fixtures = preload("res://tests/benchmarks/ai_benchmark_fixtures.gd")
const Runner = preload("res://tests/benchmarks/duel_ai_benchmark.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
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

	if _failures == 0:
		print("DUEL_AI_BENCHMARK_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("DUEL_AI_BENCHMARK_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("CHECK_FAILED: %s" % message)
