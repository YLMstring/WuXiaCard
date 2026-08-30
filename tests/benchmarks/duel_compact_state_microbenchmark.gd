extends SceneTree

const STATE_TARGET: int = 512
const CHILDREN_PER_STATE: int = 2
const COPY_PASSES: int = 5

const CompactState = preload("res://scripts/duel_compact_state.gd")
const EnemyManifest = preload("res://tests/benchmarks/enemy_ai_benchmark_manifest.gd")
const EnemyStateFactory = preload("res://tests/benchmarks/enemy_ai_benchmark_state_factory.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var states: Array[State] = _build_corpus()
	if states.size() != STATE_TARGET:
		push_error(
			"COMPACT_STATE_MICROBENCHMARK_FAILED states=%d target=%d"
			% [states.size(), STATE_TARGET]
		)
		quit(1)
		return

	var capture_started_usec: int = Time.get_ticks_usec()
	var snapshots: Array[CompactState] = []
	for state: State in states:
		var compact: CompactState = CompactState.new()
		if not compact.capture_state(state):
			push_error("COMPACT_STATE_MICROBENCHMARK_FAILED %s" % compact.capture_error)
			quit(1)
			return
		snapshots.append(compact)
	var capture_seconds: float = (
		float(Time.get_ticks_usec() - capture_started_usec) / 1_000_000.0
	)

	var restore_started_usec: int = Time.get_ticks_usec()
	var exact_mismatches: int = 0
	for state_index: int in range(states.size()):
		var state: State = states[state_index]
		var compact: CompactState = snapshots[state_index]
		var restored: State = compact.restore()
		if (
			restored == null
			or StateKey.build(state) != StateKey.build(restored)
			or state.state_version != restored.state_version
		):
			exact_mismatches += 1
	var restore_seconds: float = (
		float(Time.get_ticks_usec() - restore_started_usec) / 1_000_000.0
	)
	if exact_mismatches > 0:
		push_error(
			"COMPACT_STATE_MICROBENCHMARK_FAILED exact_mismatches=%d"
			% exact_mismatches
		)
		quit(1)
		return

	var source_bytes: int = 0
	var compact_standalone_bytes: int = 0
	var compact_branch_bytes: int = 0
	for state_index: int in range(states.size()):
		source_bytes += var_to_bytes(
			CompactState.exact_state_payload(states[state_index])
		).size()
		compact_standalone_bytes += var_to_bytes(
			snapshots[state_index].to_variant_payload()
		).size()
		compact_branch_bytes += var_to_bytes(
			snapshots[state_index].to_mutable_variant_payload()
		).size()

	_warm_up_copies(states, snapshots)
	var state_copy: Dictionary = _measure_state_copy(states)
	var compact_copy: Dictionary = _measure_compact_copy(snapshots)
	var source_average: float = float(source_bytes) / float(states.size())
	var standalone_average: float = float(compact_standalone_bytes) / float(states.size())
	var branch_average: float = float(compact_branch_bytes) / float(states.size())
	print(
		(
			"COMPACT_STATE_MICROBENCHMARK_COMPLETE states=%d exact_mismatches=%d "
			+ "capture_seconds=%.6f restore_seconds=%.6f source_avg_bytes=%.1f "
			+ "compact_standalone_avg_bytes=%.1f compact_branch_avg_bytes=%.1f "
			+ "standalone_size_ratio=%.3f branch_size_ratio=%.3f "
			+ "copy_passes=%d copy_calls=%d state_copy_seconds=%.6f "
			+ "compact_copy_seconds=%.6f copy_speedup=%.3f sink=%d"
		)
		% [
			states.size(),
			exact_mismatches,
			capture_seconds,
			restore_seconds,
			source_average,
			standalone_average,
			branch_average,
			standalone_average / source_average if source_average > 0.0 else 0.0,
			branch_average / source_average if source_average > 0.0 else 0.0,
			COPY_PASSES,
			int(state_copy.get("calls", 0)),
			float(state_copy.get("seconds", 0.0)),
			float(compact_copy.get("seconds", 0.0)),
			(
				float(state_copy.get("seconds", 0.0))
				/ float(compact_copy.get("seconds", 1.0))
				if float(compact_copy.get("seconds", 0.0)) > 0.0
				else 0.0
			),
			int(state_copy.get("sink", 0)) ^ int(compact_copy.get("sink", 0)),
		]
	)
	quit(0)


func _warm_up_copies(states: Array[State], snapshots: Array[CompactState]) -> void:
	for index: int in range(mini(states.size(), 16)):
		states[index].duplicate_state()
		snapshots[index].duplicate_compact()


func _measure_state_copy(states: Array[State]) -> Dictionary:
	var sink: int = 0
	var started_usec: int = Time.get_ticks_usec()
	for pass_index: int in range(COPY_PASSES):
		for state: State in states:
			var copied: State = state.duplicate_state()
			sink = sink ^ copied.owner_turn_serial ^ copied.board.size() ^ pass_index
	return {
		"calls": states.size() * COPY_PASSES,
		"seconds": float(Time.get_ticks_usec() - started_usec) / 1_000_000.0,
		"sink": sink,
	}


func _measure_compact_copy(snapshots: Array[CompactState]) -> Dictionary:
	var sink: int = 0
	var started_usec: int = Time.get_ticks_usec()
	for pass_index: int in range(COPY_PASSES):
		for snapshot: CompactState in snapshots:
			var copied: CompactState = snapshot.duplicate_compact() as CompactState
			sink = (
				sink
				^ copied.scalars[CompactState.SCALAR_OWNER_TURN_SERIAL]
				^ copied.board_card_indices.size()
				^ pass_index
			)
	return {
		"calls": snapshots.size() * COPY_PASSES,
		"seconds": float(Time.get_ticks_usec() - started_usec) / 1_000_000.0,
		"sink": sink,
	}


func _build_corpus() -> Array[State]:
	var queue: Array[State] = []
	var opening_keys: Dictionary = {}
	for matchup: Dictionary in EnemyManifest.get_matchups_for_mode(&"quick"):
		for game: Dictionary in EnemyManifest.expand_matchup(matchup):
			var built: Dictionary = EnemyStateFactory.build(game, matchup)
			var state: State = built.get("state") as State
			if state == null:
				continue
			var exact_key: String = StateKey.build(state)
			if opening_keys.has(exact_key):
				continue
			opening_keys[exact_key] = true
			queue.append(state)

	var states: Array[State] = []
	var exact_keys: Dictionary = {}
	var queue_index: int = 0
	while queue_index < queue.size() and states.size() < STATE_TARGET:
		var state: State = queue[queue_index]
		queue_index += 1
		var exact_key: String = StateKey.build(state)
		if exact_keys.has(exact_key):
			continue
		exact_keys[exact_key] = true
		states.append(state)
		var actions: Array = Simulator.get_legal_actions(state)
		actions.sort_custom(func(first: Variant, second: Variant) -> bool:
			return first.canonical_key() < second.canonical_key()
		)
		for action_index: int in range(mini(actions.size(), CHILDREN_PER_STATE)):
			var transition: Dictionary = Simulator.apply_action(state, actions[action_index])
			if not bool(transition.get("valid", false)):
				continue
			var child: State = transition.get("state") as State
			if child != null:
				queue.append(child)
	return states
