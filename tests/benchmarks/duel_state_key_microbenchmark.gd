extends SceneTree

const STATE_TARGET: int = 512
const CHILDREN_PER_STATE: int = 2
const MEASURED_PASSES: int = 3

const Action = preload("res://scripts/duel_action.gd")
const EnemyManifest = preload("res://tests/benchmarks/enemy_ai_benchmark_manifest.gd")
const EnemyStateFactory = preload("res://tests/benchmarks/enemy_ai_benchmark_state_factory.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var states: Array[State] = _build_state_corpus()
	if states.size() < STATE_TARGET:
		push_error(
			"STATE_KEY_MICROBENCHMARK_FAILED states=%d target=%d"
			% [states.size(), STATE_TARGET]
		)
		quit(1)
		return
	_warm_up(states)
	var legacy: Dictionary = _measure(states, true)
	var streaming: Dictionary = _measure(states, false)
	var legacy_seconds: float = float(legacy.get("seconds", 0.0))
	var streaming_seconds: float = float(streaming.get("seconds", 0.0))
	var speedup: float = (
		legacy_seconds / streaming_seconds
		if streaming_seconds > 0.0
		else 0.0
	)
	print(
		(
			"STATE_KEY_MICROBENCHMARK_COMPLETE states=%d passes=%d calls=%d "
			+ "legacy_seconds=%.6f streaming_seconds=%.6f speedup=%.3fx "
			+ "legacy_keys_per_second=%.1f streaming_keys_per_second=%.1f "
			+ "legacy_average_length=%.2f streaming_average_length=%.2f sink=%d"
		)
		% [
			states.size(),
			MEASURED_PASSES,
			int(streaming.get("calls", 0)),
			legacy_seconds,
			streaming_seconds,
			speedup,
			float(legacy.get("keys_per_second", 0.0)),
			float(streaming.get("keys_per_second", 0.0)),
			float(legacy.get("average_length", 0.0)),
			float(streaming.get("average_length", 0.0)),
			int(legacy.get("sink", 0)) ^ int(streaming.get("sink", 0)),
		]
	)
	quit(0)


func _warm_up(states: Array[State]) -> void:
	for state_index: int in range(mini(states.size(), 8)):
		StateKey.build_compact_legacy_for_benchmark(states[state_index])
		StateKey.build_compact(states[state_index])


func _measure(states: Array[State], use_legacy: bool) -> Dictionary:
	var sink: int = 0
	var key_length_total: int = 0
	var calls: int = states.size() * MEASURED_PASSES
	var started_usec: int = Time.get_ticks_usec()
	for pass_index: int in range(MEASURED_PASSES):
		for state: State in states:
			var key: String = (
				StateKey.build_compact_legacy_for_benchmark(state)
				if use_legacy
				else StateKey.build_compact(state)
			)
			sink = sink ^ key.hash() ^ pass_index
			key_length_total += key.length()
	var seconds: float = float(Time.get_ticks_usec() - started_usec) / 1_000_000.0
	return {
		"seconds": seconds,
		"calls": calls,
		"keys_per_second": float(calls) / seconds if seconds > 0.0 else 0.0,
		"average_length": float(key_length_total) / float(calls) if calls > 0 else 0.0,
		"sink": sink,
	}


func _build_state_corpus() -> Array[State]:
	var queue: Array[State] = []
	var opening_exact_keys: Dictionary = {}
	for matchup: Dictionary in EnemyManifest.get_matchups_for_mode(&"quick"):
		for game: Dictionary in EnemyManifest.expand_matchup(matchup):
			var built: Dictionary = EnemyStateFactory.build(game, matchup)
			var metadata: Dictionary = built.get("metadata", {}) as Dictionary
			var state: State = built.get("state") as State
			if state == null:
				continue
			var exact_key: String = String(metadata.get("initial_state_key", ""))
			if opening_exact_keys.has(exact_key):
				continue
			opening_exact_keys[exact_key] = true
			queue.append(state)
	var result: Array[State] = []
	var exact_digests: Dictionary = {}
	var queue_index: int = 0
	while queue_index < queue.size() and result.size() < STATE_TARGET:
		var state: State = queue[queue_index]
		queue_index += 1
		var exact_digest: String = StateKey.build(state).sha256_text()
		if exact_digests.has(exact_digest):
			continue
		exact_digests[exact_digest] = true
		result.append(state)
		var actions: Array[Action] = Simulator.get_legal_actions(state)
		actions.sort_custom(func(first: Action, second: Action) -> bool:
			return first.canonical_key() < second.canonical_key()
		)
		for action_index: int in range(mini(actions.size(), CHILDREN_PER_STATE)):
			var transition: Dictionary = Simulator.apply_action(state, actions[action_index])
			if not bool(transition.get("valid", false)):
				continue
			var next_state: State = transition.get("state") as State
			if next_state != null:
				queue.append(next_state)
	return result
