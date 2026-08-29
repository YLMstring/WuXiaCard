extends SceneTree

const STATE_TARGET: int = 512
const CHILDREN_PER_STATE: int = 2
const ACTIONS_PER_STATE: int = 2
const MEASURED_PASSES: int = 3

const Action = preload("res://scripts/duel_action.gd")
const EnemyManifest = preload("res://tests/benchmarks/enemy_ai_benchmark_manifest.gd")
const EnemyStateFactory = preload("res://tests/benchmarks/enemy_ai_benchmark_state_factory.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var corpus: Dictionary = _build_corpus()
	var states: Array[State] = corpus.get("states", []) as Array[State]
	var pairs: Array[Dictionary] = corpus.get("pairs", []) as Array[Dictionary]
	if states.size() < STATE_TARGET or pairs.is_empty():
		push_error(
			"TRANSITION_MICROBENCHMARK_FAILED states=%d pairs=%d target=%d"
			% [states.size(), pairs.size(), STATE_TARGET]
		)
		quit(1)
		return
	var parity: Dictionary = _verify_legal_action_query(states)
	if int(parity.get("mismatches", 0)) > 0:
		push_error(
			"TRANSITION_MICROBENCHMARK_FAILED legal_query_checks=%d mismatches=%d"
			% [int(parity.get("checks", 0)), int(parity.get("mismatches", 0))]
		)
		quit(1)
		return
	_warm_up(pairs)
	var duplicate_result: Dictionary = _measure_duplicates(pairs)
	var apply_result: Dictionary = _measure_apply(pairs)
	var duplicate_seconds: float = float(duplicate_result.get("seconds", 0.0))
	var apply_seconds: float = float(apply_result.get("seconds", 0.0))
	var duplicate_share: float = (
		duplicate_seconds / apply_seconds
		if apply_seconds > 0.0
		else 0.0
	)
	var estimated_resolution_seconds: float = maxf(
		apply_seconds - duplicate_seconds,
		0.0
	)
	print(
		(
			"TRANSITION_MICROBENCHMARK_COMPLETE states=%d pairs=%d passes=%d calls=%d "
			+ "play_pairs=%d activate_pairs=%d duplicate_seconds=%.6f "
			+ "apply_seconds=%.6f duplicate_share=%.3f "
			+ "estimated_resolution_seconds=%.6f duplicate_calls_per_second=%.1f "
			+ "apply_calls_per_second=%.1f legal_query_checks=%d "
			+ "legal_query_mismatches=%d sink=%d"
		)
		% [
			states.size(),
			pairs.size(),
			MEASURED_PASSES,
			int(apply_result.get("calls", 0)),
			int(corpus.get("play_pairs", 0)),
			int(corpus.get("activate_pairs", 0)),
			duplicate_seconds,
			apply_seconds,
			duplicate_share,
			estimated_resolution_seconds,
			float(duplicate_result.get("calls_per_second", 0.0)),
			float(apply_result.get("calls_per_second", 0.0)),
			int(parity.get("checks", 0)),
			int(parity.get("mismatches", 0)),
			int(duplicate_result.get("sink", 0)) ^ int(apply_result.get("sink", 0)),
		]
	)
	quit(0)


func _warm_up(pairs: Array[Dictionary]) -> void:
	for pair_index: int in range(mini(pairs.size(), 8)):
		var pair: Dictionary = pairs[pair_index]
		var state: State = pair.get("state") as State
		var action: Action = pair.get("action") as Action
		state.duplicate_state()
		Simulator.apply_action(state, action)


func _verify_legal_action_query(states: Array[State]) -> Dictionary:
	var checks: int = 0
	var mismatches: int = 0
	for state: State in states:
		for owner_id: int in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
			checks += 1
			var expected: bool = not Simulator.get_legal_actions_for_owner(
				state,
				owner_id
			).is_empty()
			var actual: bool = Simulator.has_legal_action_for_owner(state, owner_id)
			if actual != expected:
				mismatches += 1
				print(
					"LEGAL_QUERY_MISMATCH owner=%d state=%s expected=%s actual=%s"
					% [owner_id, StateKey.build_compact(state), expected, actual]
				)
	return {"checks": checks, "mismatches": mismatches}


func _measure_duplicates(pairs: Array[Dictionary]) -> Dictionary:
	var sink: int = 0
	var calls: int = pairs.size() * MEASURED_PASSES
	var started_usec: int = Time.get_ticks_usec()
	for pass_index: int in range(MEASURED_PASSES):
		for pair: Dictionary in pairs:
			var state: State = pair.get("state") as State
			var copied: State = state.duplicate_state() as State
			sink = sink ^ copied.board.size() ^ copied.owner_turn_serial ^ pass_index
	var seconds: float = float(Time.get_ticks_usec() - started_usec) / 1_000_000.0
	return {
		"seconds": seconds,
		"calls": calls,
		"calls_per_second": float(calls) / seconds if seconds > 0.0 else 0.0,
		"sink": sink,
	}


func _measure_apply(pairs: Array[Dictionary]) -> Dictionary:
	var sink: int = 0
	var calls: int = pairs.size() * MEASURED_PASSES
	var started_usec: int = Time.get_ticks_usec()
	for pass_index: int in range(MEASURED_PASSES):
		for pair: Dictionary in pairs:
			var state: State = pair.get("state") as State
			var action: Action = pair.get("action") as Action
			var transition: Dictionary = Simulator.apply_action(state, action)
			if not bool(transition.get("valid", false)):
				push_error("Measured transition became invalid: %s" % action.canonical_key())
				continue
			var next_state: State = transition.get("state") as State
			sink = sink ^ next_state.board.size() ^ next_state.owner_turn_serial ^ pass_index
	var seconds: float = float(Time.get_ticks_usec() - started_usec) / 1_000_000.0
	return {
		"seconds": seconds,
		"calls": calls,
		"calls_per_second": float(calls) / seconds if seconds > 0.0 else 0.0,
		"sink": sink,
	}


func _build_corpus() -> Dictionary:
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
	var states: Array[State] = []
	var pairs: Array[Dictionary] = []
	var exact_digests: Dictionary = {}
	var play_pairs: int = 0
	var activate_pairs: int = 0
	var queue_index: int = 0
	while queue_index < queue.size() and states.size() < STATE_TARGET:
		var state: State = queue[queue_index]
		queue_index += 1
		var exact_digest: String = StateKey.build(state).sha256_text()
		if exact_digests.has(exact_digest):
			continue
		exact_digests[exact_digest] = true
		states.append(state)
		var actions: Array[Action] = Simulator.get_legal_actions(state)
		actions.sort_custom(func(first: Action, second: Action) -> bool:
			return first.canonical_key() < second.canonical_key()
		)
		var measured_indices: Array[int] = _measured_action_indices(actions.size())
		for action_index: int in measured_indices:
			var measured_action: Action = actions[action_index]
			pairs.append({"state": state, "action": measured_action})
			if measured_action.action_type == Action.TYPE_PLAY:
				play_pairs += 1
			elif measured_action.action_type == Action.TYPE_ACTIVATE:
				activate_pairs += 1
		for action_index: int in range(mini(actions.size(), CHILDREN_PER_STATE)):
			var transition: Dictionary = Simulator.apply_action(state, actions[action_index])
			if not bool(transition.get("valid", false)):
				continue
			var next_state: State = transition.get("state") as State
			if next_state != null:
				queue.append(next_state)
	return {
		"states": states,
		"pairs": pairs,
		"play_pairs": play_pairs,
		"activate_pairs": activate_pairs,
	}


func _measured_action_indices(action_count: int) -> Array[int]:
	var result: Array[int] = []
	if action_count <= 0:
		return result
	result.append(0)
	if ACTIONS_PER_STATE > 1 and action_count > 1:
		result.append(action_count - 1)
	return result
