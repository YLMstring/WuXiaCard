extends SceneTree

const CLONE_ITERATIONS: int = 100_000
const TRANSITION_ITERATIONS: int = 5_000

const CompactState = preload("res://scripts/duel_compact_state.gd")
const Action = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
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
	_test_draw_trigger_transition_parity(kernel)
	_test_draw_trigger_rejections(kernel)
	_test_attack_lifecycle_transition_parity(kernel)
	_report_real_quick_native_coverage(kernel)
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


func _report_real_quick_native_coverage(kernel: Object) -> void:
	var unique_openings: Dictionary = {}
	var total_legal: int = 0
	var supported: int = 0
	var exact_parity: int = 0
	var mismatches: int = 0
	var rejection_reasons: Dictionary = {}
	var matchups: Array[Dictionary] = EnemyManifest.get_matchups_for_mode(&"quick")
	for matchup: Dictionary in matchups:
		for game: Dictionary in EnemyManifest.expand_matchup(matchup):
			var built: Dictionary = EnemyStateFactory.build(game, matchup)
			var opening: State = built.get("state") as State
			if opening == null:
				continue
			var opening_key: String = StateKey.build(opening)
			if unique_openings.has(opening_key):
				continue
			unique_openings[opening_key] = true
			var compact := CompactState.new()
			if not compact.capture_state(opening):
				mismatches += 1
				continue
			if not bool(kernel.call("load_compact_payload", compact.to_variant_payload())):
				mismatches += 1
				continue
			for action: Action in Simulator.get_legal_actions(opening):
				if action.action_type != Action.TYPE_PLAY:
					continue
				total_legal += 1
				var actual: Dictionary = kernel.call(
					"apply_play_transition",
					action.source_index,
					action.target_index,
					action.source_instance_id
				) as Dictionary
				if not bool(actual.get("supported", false)):
					var reason: String = String(actual.get("reason", "unspecified"))
					rejection_reasons[reason] = int(rejection_reasons.get(reason, 0)) + 1
					_check(
						not bool(actual.get("valid", false))
						and (actual.get("events", []) as Array).is_empty()
						and (actual.get("captures", []) as Array).is_empty()
						and (actual.get("exiles", []) as Array).is_empty(),
						"Unsupported Quick branch leaves no partial transition"
					)
					continue
				supported += 1
				var expected: Dictionary = Simulator.apply_action(opening, action)
				var matches: bool = bool(actual.get("valid", false)) == bool(expected.get("valid", false))
				if matches and bool(actual.get("valid", false)):
					var result_compact: CompactState = CompactState.from_variant_payload(
						actual.get("payload", {}) as Dictionary
					)
					var actual_state: State = result_compact.restore() if result_compact != null else null
					var expected_state: State = expected.get("state") as State
					matches = (
						actual_state != null
						and expected_state != null
						and StateKey.build(actual_state) == StateKey.build(expected_state)
						and actual_state.state_version == expected_state.state_version
						and actual.get("captures", []) == expected.get("captures", [])
						and actual.get("exiles", []) == expected.get("exiles", [])
						and actual.get("events", []) == expected.get("events", [])
					)
				if matches:
					exact_parity += 1
				else:
					mismatches += 1
	_check(unique_openings.size() == 14, "Quick coverage uses 14 unique real openings")
	_check(mismatches == 0, "Every supported Quick root action has exact oracle parity")
	print(
		"DUEL_NATIVE_QUICK_COVERAGE openings=%d total_legal=%d supported=%d exact_parity=%d mismatches=%d rejection_reasons=%s"
		% [
			unique_openings.size(),
			total_legal,
			supported,
			exact_parity,
			mismatches,
			JSON.stringify(rejection_reasons),
		]
	)


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


func _test_draw_trigger_transition_parity(kernel: Object) -> void:
	for owner_id: int in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		for tier: int in range(1, 4):
			var prefix: String = "native_tuna_%d_%d" % [owner_id, tier]
			var source_id := StringName("TuNaShu%d" % tier)
			var source: Dictionary = Catalog.create_instance(
				source_id,
				owner_id,
				StringName("%s_source" % prefix)
			)
			var remaining: Dictionary = _make_plain_card(
				&"吐纳余牌",
				StringName("%s_remaining" % prefix),
				owner_id,
				[1, 1, 1, 1]
			)
			var active_hand: Array = [remaining, source]
			if tier == 2:
				remaining[State.HAND_SLOT_INDEX_KEY] = 2
				source[State.HAND_SLOT_INDEX_KEY] = 4
			var active_deck: Array = []
			for draw_index: int in range(3):
				active_deck.append(_make_plain_card(
					StringName("吐纳抽牌%d" % draw_index),
					StringName("%s_draw_%d" % [prefix, draw_index]),
					owner_id,
					[1, 1, 1, 1]
				))
			if owner_id == Rules.PLAYER_OWNER and tier == 1:
				var dormant_drawn_card: Dictionary = _make_after_summoned_card(
					StringName("%s_draw_0" % prefix),
					{"type": Catalog.ACTION_GAIN_KI, "amount": 1}
				)
				dormant_drawn_card["card_id"] = &"吐纳抽牌0"
				active_deck[0] = dormant_drawn_card
			var other_owner: int = (
				Rules.OPPONENT_OWNER if owner_id == Rules.PLAYER_OWNER else Rules.PLAYER_OWNER
			)
			var other_hand: Array = [_make_plain_card(
				&"吐纳敌手",
				StringName("%s_other" % prefix),
				other_owner,
				[1, 1, 1, 1]
			)]
			var state := State.new(
				Rules.empty_board(),
				active_hand if owner_id == Rules.PLAYER_OWNER else other_hand,
				active_hand if owner_id == Rules.OPPONENT_OWNER else other_hand,
				owner_id,
				0,
				active_deck if owner_id == Rules.PLAYER_OWNER else [],
				active_deck if owner_id == Rules.OPPONENT_OWNER else []
			)
			if tier == 2:
				remaining[State.HAND_SLOT_INDEX_KEY] = 2
				source[State.HAND_SLOT_INDEX_KEY] = 4
				var stored_hand: Array = state.get_hand(owner_id)
				(stored_hand[0] as Dictionary)[State.HAND_SLOT_INDEX_KEY] = 2
				(stored_hand[1] as Dictionary)[State.HAND_SLOT_INDEX_KEY] = 4
			_check_transition_parity(
				kernel,
				state,
				1,
				4,
				StringName("%s_source" % prefix),
				"TuNaShu%d owner %d draw parity" % [tier, owner_id]
			)

	var cap_hand: Array = []
	for hand_index: int in range(4):
		cap_hand.append(_make_plain_card(
			StringName("上限余牌%d" % hand_index),
			StringName("native_tuna_cap_%d" % hand_index),
			Rules.PLAYER_OWNER,
			[1, 1, 1, 1]
		))
	cap_hand.append(Catalog.create_instance(
		&"TuNaShu3",
		Rules.PLAYER_OWNER,
		&"native_tuna_cap_source"
	))
	var cap_state := State.new(
		Rules.empty_board(),
		cap_hand,
		[_make_plain_card(&"上限敌手", &"native_tuna_cap_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER,
		0,
		[
			_make_plain_card(&"上限抽一", &"native_tuna_cap_draw_1", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
			_make_plain_card(&"上限抽二", &"native_tuna_cap_draw_2", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
		]
	)
	_check_transition_parity(
		kernel,
		cap_state,
		4,
		4,
		&"native_tuna_cap_source",
		"TuNaShu3 hand-cap truncation"
	)

	var attack_board: Array = Rules.empty_board()
	attack_board[1] = _slot(
		_make_plain_card(&"吐纳受击", &"native_tuna_attack_target", Rules.OPPONENT_OWNER, [0, 0, 0, 0]),
		Rules.OPPONENT_OWNER
	)
	var attack_state := State.new(
		attack_board,
		[Catalog.create_instance(&"TuNaShu1", Rules.PLAYER_OWNER, &"native_tuna_attack_source")],
		[_make_plain_card(&"吐纳敌手", &"native_tuna_attack_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER,
		0,
		[_make_plain_card(&"吐纳先抽", &"native_tuna_attack_draw", Rules.PLAYER_OWNER, [1, 1, 1, 1])]
	)
	_check_transition_parity(
		kernel,
		attack_state,
		0,
		4,
		&"native_tuna_attack_source",
		"Draw events precede standard attack"
	)


func _test_draw_trigger_rejections(kernel: Object) -> void:
	var empty_deck_state := State.new(
		Rules.empty_board(),
		[Catalog.create_instance(&"TuNaShu1", Rules.PLAYER_OWNER, &"native_empty_draw")],
		[_make_plain_card(&"敌手", &"native_empty_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_transition_rejected(kernel, empty_deck_state, &"native_empty_draw", "Empty-deck fallback")

	var listener_board: Array = Rules.empty_board()
	var draw_listener: Dictionary = _make_plain_card(
		&"抽牌监听",
		&"native_draw_listener",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	draw_listener["active_abilities"] = [{
		"retained_on_flip": false,
		"triggers": [{
			"event": Catalog.CARD_AFTER_DRAWN,
			"conditions": [],
			"actions": [{"type": Catalog.ACTION_GAIN_KI, "amount": 1}],
		}],
	}]
	listener_board[0] = _slot(draw_listener, Rules.PLAYER_OWNER)
	var listener_state := State.new(
		listener_board,
		[Catalog.create_instance(&"TuNaShu1", Rules.PLAYER_OWNER, &"native_listener_source")],
		[_make_plain_card(&"敌手", &"native_listener_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER,
		0,
		[_make_plain_card(&"待抽", &"native_listener_draw", Rules.PLAYER_OWNER, [1, 1, 1, 1])]
	)
	_check_transition_rejected(kernel, listener_state, &"native_listener_source", "After-drawn listener")

	var filtered_source: Dictionary = _make_after_summoned_card(
		&"native_filtered_source",
		{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1, "weapon": "剑法"}
	)
	var filtered_state := State.new(
		Rules.empty_board(),
		[filtered_source],
		[_make_plain_card(&"敌手", &"native_filtered_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER,
		0,
		[_make_plain_card(&"待抽", &"native_filtered_draw", Rules.PLAYER_OWNER, [1, 1, 1, 1])]
	)
	_check_transition_rejected(kernel, filtered_state, &"native_filtered_source", "Filtered draw")

	var unsupported_source: Dictionary = _make_after_summoned_card(
		&"native_unsupported_source",
		{"type": Catalog.ACTION_GAIN_KI, "amount": 1}
	)
	var unsupported_state := State.new(
		Rules.empty_board(),
		[unsupported_source],
		[_make_plain_card(&"敌手", &"native_unsupported_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_transition_rejected(
		kernel,
		unsupported_state,
		&"native_unsupported_source",
		"Unsupported after-summoned action"
	)


func _test_attack_lifecycle_transition_parity(kernel: Object) -> void:
	for owner_id: int in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		var other_owner: int = (
			Rules.OPPONENT_OWNER if owner_id == Rules.PLAYER_OWNER else Rules.PLAYER_OWNER
		)
		var bagua_board: Array = Rules.empty_board()
		bagua_board[1] = _slot(
			Catalog.create_instance(&"BaGuaFangWei", other_owner, StringName("native_bagua_%d" % owner_id)),
			other_owner
		)
		var bagua_state := State.new(
			bagua_board,
			[_make_plain_card(&"八卦攻方", StringName("native_bagua_attacker_%d" % owner_id), owner_id, [1, 1, 1, 1])] if owner_id == Rules.PLAYER_OWNER else [_make_plain_card(&"八卦守方手牌", &"native_bagua_player_hand", Rules.PLAYER_OWNER, [1, 1, 1, 1])],
			[_make_plain_card(&"八卦攻方", StringName("native_bagua_attacker_%d" % owner_id), owner_id, [1, 1, 1, 1])] if owner_id == Rules.OPPONENT_OWNER else [_make_plain_card(&"八卦守方手牌", &"native_bagua_enemy_hand", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
			owner_id
		)
		_check_transition_parity(
			kernel,
			bagua_state,
			0,
			4,
			StringName("native_bagua_attacker_%d" % owner_id),
			"BaGua pre-flip exile owner %d" % owner_id
		)

	for tier: int in range(1, 4):
		var lei_board: Array = Rules.empty_board()
		lei_board[1] = _slot(
			Catalog.create_instance(
				StringName("LeiZHenJian%d" % tier),
				Rules.OPPONENT_OWNER,
				StringName("native_lei_target_%d" % tier)
			),
			Rules.OPPONENT_OWNER
		)
		var lei_state := State.new(
			lei_board,
			[_make_plain_card(&"雷震攻方", StringName("native_lei_attacker_%d" % tier), Rules.PLAYER_OWNER, [1, 1, 1, 1])],
			[_make_plain_card(&"雷震敌手", StringName("native_lei_enemy_hand_%d" % tier), Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
			Rules.PLAYER_OWNER,
			0,
			[],
			[_make_plain_card(&"雷震抽牌", StringName("native_lei_draw_%d" % tier), Rules.OPPONENT_OWNER, [1, 1, 1, 1])]
		)
		_check_transition_parity(
			kernel,
			lei_state,
			0,
			4,
			StringName("native_lei_attacker_%d" % tier),
			"LeiZhen tier %d defense and exile" % tier
		)

	var all_board: Array = Rules.empty_board()
	all_board[3] = _slot(
		_make_plain_card(&"友方目标", &"native_lei_all_ally", Rules.PLAYER_OWNER, [0, 0, 0, 0]),
		Rules.PLAYER_OWNER
	)
	all_board[1] = _slot(
		_make_plain_card(&"敌方目标", &"native_lei_all_enemy", Rules.OPPONENT_OWNER, [0, 0, 0, 0]),
		Rules.OPPONENT_OWNER
	)
	all_board[8] = _slot(
		Catalog.create_instance(&"LeiZHenJian3", Rules.OPPONENT_OWNER, &"native_lei_all_source"),
		Rules.OPPONENT_OWNER
	)
	var all_state := State.new(
		all_board,
		[_make_plain_card(&"不分敌我攻方", &"native_lei_all_attacker", Rules.PLAYER_OWNER, [2, 2, 2, 2])],
		[_make_plain_card(&"敌手", &"native_lei_all_hand", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		all_state,
		0,
		4,
		&"native_lei_all_attacker",
		"LeiZhen enemy-attacks-all policy"
	)

	var remove_attacker_board: Array = Rules.empty_board()
	var remove_attacker_target: Dictionary = _make_plain_card(
		&"移除攻击者",
		&"native_remove_attacker_target",
		Rules.OPPONENT_OWNER,
		[0, 0, 0, 0]
	)
	remove_attacker_target["active_abilities"] = [{
		"retained_on_flip": true,
		"triggers": [{
			"event": Catalog.CARD_BE_ATTACKED,
			"conditions": [{"type": Catalog.CONDITION_ATTACKED_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_EXILE_CARD, "card": Catalog.CARD_REF_ATTACKER_CARD}],
		}],
	}]
	remove_attacker_board[1] = _slot(remove_attacker_target, Rules.OPPONENT_OWNER)
	var remove_attacker_state := State.new(
		remove_attacker_board,
		[_make_plain_card(&"被移除攻方", &"native_removed_attacker", Rules.PLAYER_OWNER, [2, 2, 2, 2])],
		[_make_plain_card(&"敌手", &"native_remove_attacker_hand", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		remove_attacker_state,
		0,
		4,
		&"native_removed_attacker",
		"Attacker exile stops locked-target loop"
	)

	var cleanup_board: Array = Rules.empty_board()
	var cleanup_target: Dictionary = _make_plain_card(
		&"翻面能力清理",
		&"native_flip_cleanup_target",
		Rules.OPPONENT_OWNER,
		[0, 0, 0, 0]
	)
	cleanup_target["active_abilities"] = [
		{"retained_on_flip": true, "triggers": [{"event": Catalog.CARD_BEFORE_EXILED, "conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}], "actions": [{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1}]}]},
		{"triggers": [{"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED, "conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}], "actions": [{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1}]}]},
		{"triggers": [{"event": Catalog.CARD_AFTER_FLIPPED, "conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}], "actions": [{"type": Catalog.ACTION_PREVENT_TRIGGER_FLIP}]}]},
	]
	cleanup_board[1] = _slot(cleanup_target, Rules.OPPONENT_OWNER)
	var cleanup_state := State.new(
		cleanup_board,
		[_make_plain_card(&"翻面攻方", &"native_flip_cleanup_attacker", Rules.PLAYER_OWNER, [2, 2, 2, 2])],
		[_make_plain_card(&"敌手", &"native_flip_cleanup_hand", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		cleanup_state,
		0,
		4,
		&"native_flip_cleanup_attacker",
		"Retained ordinary and deferred flip cleanup"
	)

	var prevent_board: Array = Rules.empty_board()
	var prevent_target: Dictionary = _make_plain_card(
		&"阻止翻面",
		&"native_prevent_target",
		Rules.OPPONENT_OWNER,
		[0, 0, 0, 0]
	)
	prevent_target["active_abilities"] = [{
		"retained_on_flip": true,
		"triggers": [{
			"event": Catalog.CARD_BEFORE_FLIPPED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_PREVENT_TRIGGER_FLIP}],
		}],
	}]
	prevent_board[1] = _slot(prevent_target, Rules.OPPONENT_OWNER)
	var prevent_state := State.new(
		prevent_board,
		[_make_plain_card(&"阻止攻方", &"native_prevent_attacker", Rules.PLAYER_OWNER, [2, 2, 2, 2])],
		[_make_plain_card(&"敌手", &"native_prevent_hand", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		prevent_state,
		0,
		4,
		&"native_prevent_attacker",
		"Before-flip prevention and prevented event"
	)

	var after_attack_board: Array = Rules.empty_board()
	after_attack_board[1] = _slot(
		_make_plain_card(&"攻击目标", &"native_after_attack_target", Rules.OPPONENT_OWNER, [0, 0, 0, 0]),
		Rules.OPPONENT_OWNER
	)
	var after_attack_source: Dictionary = _make_plain_card(
		&"攻击后失去能力",
		&"native_after_attack_source",
		Rules.PLAYER_OWNER,
		[2, 2, 2, 2]
	)
	after_attack_source["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_ATTACK,
			"conditions": [{"type": Catalog.CONDITION_ATTACKER_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_REMOVE_THIS_ABILITY}],
		}],
	}]
	var after_attack_state := State.new(
		after_attack_board,
		[after_attack_source],
		[_make_plain_card(&"敌手", &"native_after_attack_hand", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		after_attack_state,
		0,
		4,
		&"native_after_attack_source",
		"After-attack self condition removes current ability"
	)

	var after_exile_board: Array = Rules.empty_board()
	var exiled_target: Dictionary = _make_plain_card(
		&"受击移除目标",
		&"native_after_exile_target",
		Rules.OPPONENT_OWNER,
		[0, 0, 0, 0]
	)
	exiled_target["active_abilities"] = [{
		"retained_on_flip": true,
		"triggers": [{
			"event": Catalog.CARD_BE_ATTACKED,
			"conditions": [{"type": Catalog.CONDITION_ATTACKED_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_EXILE_SELF}],
		}],
	}]
	after_exile_board[1] = _slot(exiled_target, Rules.OPPONENT_OWNER)
	var exile_watcher: Dictionary = _make_plain_card(
		&"移除后监听",
		&"native_after_exile_watcher",
		Rules.OPPONENT_OWNER,
		[1, 1, 1, 1]
	)
	exile_watcher["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.CARD_AFTER_EXILED,
			"conditions": [
				{"type": Catalog.CONDITION_TRIGGER_CARD_WAS_ON_BOARD},
				{"type": Catalog.CONDITION_TRIGGER_CARD_POWERS_COULD_CHANGE},
			],
			"actions": [{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1}],
		}],
	}]
	after_exile_board[8] = _slot(exile_watcher, Rules.OPPONENT_OWNER)
	var after_exile_state := State.new(
		after_exile_board,
		[_make_plain_card(&"移除攻方", &"native_after_exile_attacker", Rules.PLAYER_OWNER, [2, 2, 2, 2])],
		[_make_plain_card(&"敌手", &"native_after_exile_hand", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER,
		0,
		[],
		[_make_plain_card(&"移除后抽牌", &"native_after_exile_draw", Rules.OPPONENT_OWNER, [1, 1, 1, 1])]
	)
	_check_transition_parity(
		kernel,
		after_exile_state,
		0,
		4,
		&"native_after_exile_attacker",
		"After-exile snapshot conditions and draw"
	)

	var nested_board: Array = Rules.empty_board()
	var nested_target: Dictionary = _make_plain_card(
		&"嵌套攻击拒绝",
		&"native_nested_target",
		Rules.OPPONENT_OWNER,
		[0, 0, 0, 0]
	)
	nested_target["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.CARD_BE_ATTACKED,
			"conditions": [{"type": Catalog.CONDITION_ATTACKED_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_ATTACK_TRIGGER_CARD}],
		}],
	}]
	nested_board[1] = _slot(nested_target, Rules.OPPONENT_OWNER)
	var nested_state := State.new(
		nested_board,
		[_make_plain_card(&"嵌套攻方", &"native_nested_attacker", Rules.PLAYER_OWNER, [2, 2, 2, 2])],
		[_make_plain_card(&"敌手", &"native_nested_hand", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_transition_rejected(
		kernel,
		nested_state,
		&"native_nested_attacker",
		"Relevant nested attack reaction"
	)


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
			"apply_play_transition",
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
	var compiled_layout: Dictionary = kernel.call("inspect_layout") as Dictionary
	_check(
		int(compiled_layout.get("compiled_ability_set_count", -1))
		== compact.active_ability_set_pool.size(),
		"%s immutable ability sets compile once at root load" % label
	)
	var actual: Dictionary = kernel.call(
		"apply_play_transition",
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
	var draw_event_index: int = _first_event_index(actual.get("events", []) as Array, &"card_drawn")
	var attack_event_index: int = _first_event_index(actual.get("events", []) as Array, &"attack_started")
	var draw_event: Dictionary = (
		(actual.get("events", []) as Array)[draw_event_index] as Dictionary
		if draw_event_index >= 0
		else {}
	)
	if (
		draw_event_index >= 0
		and attack_event_index >= 0
		and int(draw_event.get("source_cell", -1)) == target_cell
	):
		_check(
			draw_event_index < attack_event_index,
			"%s draw events precede the standard attack" % label
		)


func _check_transition_rejected(
	kernel: Object,
	state: State,
	instance_id: StringName,
	label: String
) -> void:
	var compact := CompactState.new()
	_check(compact.capture_state(state), "%s fixture can be compacted" % label)
	if not compact.is_structurally_valid():
		return
	_check(
		bool(kernel.call("load_compact_payload", compact.to_variant_payload())),
		"%s compact source loads natively" % label
	)
	var result: Dictionary = kernel.call(
		"apply_play_transition",
		0,
		4,
		instance_id
	) as Dictionary
	_check(not bool(result.get("supported", true)), "%s is explicitly unsupported" % label)
	_check(not bool(result.get("valid", true)), "%s does not produce a transition" % label)


func _first_event_index(events: Array, event_type: StringName) -> int:
	for event_index: int in range(events.size()):
		var event_value: Variant = events[event_index]
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
		):
			return event_index
	return -1


func _make_after_summoned_card(instance_id: StringName, action: Dictionary) -> Dictionary:
	var card: Dictionary = _make_plain_card(
		&"原生能力夹具",
		instance_id,
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	card["active_abilities"] = [{
		"retained_on_flip": false,
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [action],
		}],
	}]
	return card


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
