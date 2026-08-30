extends SceneTree

const CLONE_ITERATIONS: int = 100_000
const TRANSITION_ITERATIONS: int = 5_000

const CompactState = preload("res://scripts/duel_compact_state.gd")
const Action = preload("res://scripts/duel_action.gd")
const EnemyManifest = preload("res://tests/benchmarks/enemy_ai_benchmark_manifest.gd")
const EnemyStateFactory = preload("res://tests/benchmarks/enemy_ai_benchmark_state_factory.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")

var _checks: int = 0
var _failures: int = 0


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
	_test_basic_transition_parity(kernel)
	_test_basic_transition_rejects_abilities(kernel)
	if _failures > 0:
		push_error(
			"DUEL_NATIVE_COMPACT_PROBE_FAILED parity_failures=%d checks=%d"
			% [_failures, _checks]
		)
		quit(1)
		return
	var transition_benchmark: Dictionary = _benchmark_basic_transition(kernel)
	if not bool(transition_benchmark.get("valid", false)):
		push_error("DUEL_NATIVE_COMPACT_PROBE_FAILED transition benchmark")
		quit(1)
		return
	print(
		(
			"DUEL_NATIVE_BASIC_TRANSITION_BENCHMARK iterations=%d native_usec=%d "
			+ "oracle_usec=%d speedup=%.3f"
		)
		% [
			TRANSITION_ITERATIONS,
			int(transition_benchmark.get("native_usec", 0)),
			int(transition_benchmark.get("oracle_usec", 0)),
			float(transition_benchmark.get("speedup", 0.0)),
		]
	)
	var elapsed_usec: int = int(clone_result.get("elapsed_usec", 0))
	print(
		(
			"DUEL_NATIVE_COMPACT_PROBE_COMPLETE cards=%d powers=%d iterations=%d "
			+ "elapsed_usec=%d clones_per_second=%.1f checksum=%d sink=%d "
			+ "parity_checks=%d"
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
			_checks,
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


func _test_basic_transition_parity(kernel: Object) -> void:
	var capture_board: Array = Rules.empty_board()
	capture_board[1] = _slot(
		_make_plain_card(&"测试上", &"native_top", Rules.OPPONENT_OWNER, [1, 1, 1, 2]),
		Rules.OPPONENT_OWNER
	)
	capture_board[5] = _slot(
		_make_plain_card(&"测试右", &"native_right", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		Rules.OPPONENT_OWNER
	)
	capture_board[7] = _slot(
		_make_plain_card(&"测试下", &"native_bottom", Rules.OPPONENT_OWNER, [6, 1, 1, 1]),
		Rules.OPPONENT_OWNER
	)
	capture_board[3] = _slot(
		_make_plain_card(&"测试友", &"native_ally", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
		Rules.PLAYER_OWNER
	)
	var capture_state := State.new(
		capture_board,
		[
			_make_plain_card(&"留手", &"native_remain", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
			_make_plain_card(&"进场拳", &"native_play", Rules.PLAYER_OWNER, [5, 5, 5, 5]),
		],
		[_make_plain_card(&"敌手", &"native_enemy_hand", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		capture_state,
		1,
		4,
		&"native_play",
		"Multiple adjacent captures"
	)

	var empty_turn_board: Array = Rules.empty_board()
	empty_turn_board[0] = _slot(
		_make_plain_card(&"角落", &"native_corner", Rules.OPPONENT_OWNER, [2, 2, 2, 2]),
		Rules.OPPONENT_OWNER
	)
	var empty_turn_state := State.new(
		empty_turn_board,
		[
			_make_plain_card(&"跨空回合", &"native_skip_play", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
			_make_plain_card(&"后续行动", &"native_followup", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
		],
		[],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		empty_turn_state,
		0,
		8,
		&"native_skip_play",
		"Empty opponent turn advancement"
	)

	var capped_state := State.new(
		Rules.empty_board(),
		[_make_plain_card(&"末次行动", &"native_cap_play", Rules.PLAYER_OWNER, [1, 1, 1, 1])],
		[_make_plain_card(&"未轮到", &"native_cap_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	capped_state.max_turns = 1
	_check_transition_parity(
		kernel,
		capped_state,
		0,
		4,
		&"native_cap_play",
		"Action-limit terminal boundary"
	)

	var full_board: Array = Rules.empty_board()
	for cell: int in range(9):
		if cell == 4:
			continue
		var owner_id: int = Rules.PLAYER_OWNER if cell % 2 == 0 else Rules.OPPONENT_OWNER
		full_board[cell] = _slot(
			_make_plain_card(
				StringName("满场%d" % cell),
				StringName("native_full_%d" % cell),
				owner_id,
				[1, 1, 1, 1]
			),
			owner_id
		)
	var full_state := State.new(
		full_board,
		[_make_plain_card(&"满场落子", &"native_full_play", Rules.PLAYER_OWNER, [0, 0, 0, 0])],
		[_make_plain_card(&"满场敌手", &"native_full_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		full_state,
		0,
		4,
		&"native_full_play",
		"Full-board terminal boundary"
	)

	var repetition_state := State.new(
		Rules.empty_board(),
		[_make_plain_card(&"五次重复", &"native_repeat_play", Rules.PLAYER_OWNER, [1, 1, 1, 1])],
		[_make_plain_card(&"重复敌手", &"native_repeat_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	var repeated_board: Array = repetition_state.board.duplicate(true)
	repeated_board[4] = _slot(
		(repetition_state.get_hand(Rules.PLAYER_OWNER)[0] as Dictionary).duplicate(true),
		Rules.PLAYER_OWNER
	)
	var repeated_signature: String = Simulator.get_board_repetition_signature(repeated_board)
	repetition_state.repetition_hashes = [
		repeated_signature,
		repeated_signature,
		repeated_signature,
		repeated_signature,
	]
	_check_transition_parity(
		kernel,
		repetition_state,
		0,
		4,
		&"native_repeat_play",
		"Fivefold-repetition terminal boundary"
	)


func _test_basic_transition_rejects_abilities(kernel: Object) -> void:
	var ability_card: Dictionary = _make_plain_card(
		&"带能力",
		&"native_ability",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	ability_card["active_abilities"] = [{"trigger": &"fixture"}]
	var state := State.new(
		Rules.empty_board(),
		[ability_card],
		[_make_plain_card(&"敌手", &"native_reject_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	var compact := CompactState.new()
	_check(compact.capture_state(state), "Ability rejection fixture can be captured")
	if not compact.is_structurally_valid():
		return
	_check(
		bool(kernel.call("load_compact_payload", compact.to_variant_payload())),
		"Ability rejection fixture loads into native state"
	)
	var result: Dictionary = kernel.call(
		"apply_basic_play_transition",
		0,
		4,
		&"native_ability"
	) as Dictionary
	_check(not bool(result.get("supported", true)), "Ability-bearing state is explicitly unsupported")
	_check(not bool(result.get("valid", true)), "Unsupported state does not produce a transition")


func _benchmark_basic_transition(kernel: Object) -> Dictionary:
	var board: Array = Rules.empty_board()
	board[1] = _slot(
		_make_plain_card(&"计时上", &"native_bench_top", Rules.OPPONENT_OWNER, [1, 1, 1, 2]),
		Rules.OPPONENT_OWNER
	)
	board[5] = _slot(
		_make_plain_card(&"计时右", &"native_bench_right", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		Rules.OPPONENT_OWNER
	)
	var state := State.new(
		board,
		[_make_plain_card(&"计时出牌", &"native_bench_play", Rules.PLAYER_OWNER, [5, 5, 5, 5])],
		[_make_plain_card(&"计时敌手", &"native_bench_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	var compact := CompactState.new()
	if not compact.capture_state(state):
		return {"valid": false}
	if not bool(kernel.call("load_compact_payload", compact.to_variant_payload())):
		return {"valid": false}

	var native_sink: int = 0
	var native_started_usec: int = Time.get_ticks_usec()
	for _iteration: int in range(TRANSITION_ITERATIONS):
		var transition: Dictionary = kernel.call(
			"apply_basic_play_transition",
			0,
			4,
			&"native_bench_play"
		) as Dictionary
		if not bool(transition.get("valid", false)):
			return {"valid": false}
		native_sink += (transition.get("events", []) as Array).size()
	var native_usec: int = Time.get_ticks_usec() - native_started_usec

	var oracle_sink: int = 0
	var action: Action = Action.make_play(0, 4, &"native_bench_play")
	var oracle_started_usec: int = Time.get_ticks_usec()
	for _iteration: int in range(TRANSITION_ITERATIONS):
		var transition: Dictionary = Simulator.apply_action(state, action)
		if not bool(transition.get("valid", false)):
			return {"valid": false}
		oracle_sink += (transition.get("events", []) as Array).size()
	var oracle_usec: int = Time.get_ticks_usec() - oracle_started_usec
	return {
		"valid": native_sink == oracle_sink and native_sink > 0,
		"native_usec": native_usec,
		"oracle_usec": oracle_usec,
		"speedup": float(oracle_usec) / float(native_usec) if native_usec > 0 else 0.0,
	}


func _check_transition_parity(
	kernel: Object,
	state: State,
	hand_index: int,
	target_cell: int,
	instance_id: StringName,
	label: String
) -> void:
	var action: Action = Action.make_play(hand_index, target_cell, instance_id)
	var expected: Dictionary = Simulator.apply_action(state, action)
	_check(bool(expected.get("valid", false)), "%s oracle transition is valid" % label)
	if not bool(expected.get("valid", false)):
		return
	var compact := CompactState.new()
	_check(compact.capture_state(state), "%s source can be compacted" % label)
	if not compact.is_structurally_valid():
		return
	_check(
		bool(kernel.call("load_compact_payload", compact.to_variant_payload())),
		"%s compact source loads natively" % label
	)
	var actual: Dictionary = kernel.call(
		"apply_basic_play_transition",
		hand_index,
		target_cell,
		instance_id
	) as Dictionary
	_check(bool(actual.get("supported", false)), "%s is covered by the native slice" % label)
	_check(bool(actual.get("valid", false)), "%s native transition is valid" % label)
	if not bool(actual.get("valid", false)):
		print("NATIVE_BASIC_TRANSITION_REASON label=%s reason=%s" % [label, actual.get("reason", "")])
		return
	var result_compact: CompactState = CompactState.from_variant_payload(
		actual.get("payload", {}) as Dictionary
	)
	_check(result_compact != null, "%s native result payload can be loaded" % label)
	if result_compact == null:
		return
	var actual_state: State = result_compact.restore()
	_check(actual_state != null, "%s native result payload can be restored" % label)
	if actual_state == null:
		return
	var expected_state: State = expected.get("state") as State
	_check(
		StateKey.build(actual_state) == StateKey.build(expected_state)
		and actual_state.state_version == expected_state.state_version,
		"%s native state exactly matches DuelSimulator" % label
	)
	_check(
		actual.get("captures", []) == expected.get("captures", []),
		"%s captures exactly match DuelSimulator" % label
	)
	_check(
		actual.get("exiles", []) == expected.get("exiles", []),
		"%s exiles exactly match DuelSimulator" % label
	)
	_check(
		actual.get("events", []) == expected.get("events", []),
		"%s events exactly match DuelSimulator" % label
	)
	if actual.get("events", []) != expected.get("events", []):
		print("NATIVE_EVENT_DIFFERENCE label=%s expected=%s actual=%s" % [
			label,
			expected.get("events", []),
			actual.get("events", []),
		])


func _make_plain_card(
	card_id: StringName,
	instance_id: StringName,
	owner_id: int,
	powers: Array[int]
) -> Dictionary:
	return {
		"instance_id": instance_id,
		"card_id": card_id,
		"name": String(card_id),
		"glyph": String(card_id),
		"powers": powers.duplicate(),
		"original_owner": owner_id,
		"ki": 0,
		"active_abilities": [],
		"revealed_to_owner_ids": [owner_id],
	}


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	print("CHECK_FAILED: %s" % message)
