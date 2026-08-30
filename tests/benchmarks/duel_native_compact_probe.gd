extends SceneTree

const CLONE_ITERATIONS: int = 100_000

const CompactState = preload("res://scripts/duel_compact_state.gd")
const EnemyManifest = preload("res://tests/benchmarks/enemy_ai_benchmark_manifest.gd")
const EnemyStateFactory = preload("res://tests/benchmarks/enemy_ai_benchmark_state_factory.gd")
const State = preload("res://scripts/duel_state.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ClassDB.class_exists(&"DuelNativeCompactKernel"):
		push_error("DUEL_NATIVE_COMPACT_PROBE_FAILED extension class is unavailable")
		quit(1)
		return
	var state: State = _first_opening()
	if state == null:
		push_error("DUEL_NATIVE_COMPACT_PROBE_FAILED no real opening")
		quit(1)
		return
	var compact: CompactState = CompactState.new()
	if not compact.capture_state(state):
		push_error("DUEL_NATIVE_COMPACT_PROBE_FAILED %s" % compact.capture_error)
		quit(1)
		return
	var kernel: Object = ClassDB.instantiate(&"DuelNativeCompactKernel")
	if kernel == null:
		push_error("DUEL_NATIVE_COMPACT_PROBE_FAILED class cannot be instantiated")
		quit(1)
		return
	if not bool(kernel.call("load_compact_payload", compact.to_mutable_variant_payload())):
		push_error(
			"DUEL_NATIVE_COMPACT_PROBE_FAILED load_error=%s"
			% kernel.call("get_last_error")
		)
		quit(1)
		return
	var layout: Dictionary = kernel.call("inspect_layout") as Dictionary
	var expected_card_count: int = compact.card_instance_ids.size()
	if (
		int(layout.get("scalar_count", 0)) != CompactState.SCALAR_COUNT
		or int(layout.get("board_cell_count", 0)) != state.board.size()
		or int(layout.get("zone_count", 0)) != CompactState.ZONE_COUNT
		or int(layout.get("card_count", 0)) != expected_card_count
		or int(layout.get("power_count", 0)) != expected_card_count * 4
	):
		push_error("DUEL_NATIVE_COMPACT_PROBE_FAILED layout=%s" % layout)
		quit(1)
		return
	var clone_result: Dictionary = kernel.call(
		"benchmark_core_clone",
		CLONE_ITERATIONS
	) as Dictionary
	if not bool(clone_result.get("valid", false)):
		push_error("DUEL_NATIVE_COMPACT_PROBE_FAILED clone_result=%s" % clone_result)
		quit(1)
		return
	var elapsed_usec: int = int(clone_result.get("elapsed_usec", 0))
	print(
		(
			"DUEL_NATIVE_COMPACT_PROBE_COMPLETE cards=%d powers=%d iterations=%d "
			+ "elapsed_usec=%d clones_per_second=%.1f checksum=%d sink=%d"
		)
		% [
			expected_card_count,
			expected_card_count * 4,
			CLONE_ITERATIONS,
			elapsed_usec,
			(
				float(CLONE_ITERATIONS) * 1_000_000.0 / float(elapsed_usec)
				if elapsed_usec > 0
				else 0.0
			),
			int(layout.get("checksum", 0)),
			int(clone_result.get("sink", 0)),
		]
	)
	quit(0)


func _first_opening() -> State:
	var matchups: Array[Dictionary] = EnemyManifest.get_matchups_for_mode(&"quick")
	if matchups.is_empty():
		return null
	var games: Array[Dictionary] = EnemyManifest.expand_matchup(matchups[0])
	if games.is_empty():
		return null
	var built: Dictionary = EnemyStateFactory.build(games[0], matchups[0])
	return built.get("state") as State
