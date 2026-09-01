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
	_report_catalog_trigger_inventory()
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
	_test_fresh_prototype_metadata(kernel)
	_test_activation_legal_action_parity(kernel)
	_test_basic_transition_parity(kernel)
	_test_draw_trigger_transition_parity(kernel)
	_test_draw_reveal_and_difficulty_parity(kernel)
	_test_draw_trigger_rejections(kernel)
	_test_if_transition_parity(kernel)
	_test_discard_transition_parity(kernel)
	_test_transform_transition_parity(kernel)
	_test_preserved_return_transition_parity(kernel)
	_test_selector_transition_parity(kernel)
	_test_power_change_transition_parity(kernel)
	_test_ki_flip_and_grant_transition_parity(kernel)
	_test_return_to_hand_transition_parity(kernel)
	_test_swap_transition_parity(kernel)
	_test_attack_lifecycle_transition_parity(kernel)
	_test_attack_modifier_transition_parity(kernel)
	_test_event_reaction_primitive_parity(kernel)
	_test_summon_before_lifecycle_parity(kernel)
	_test_generated_summon_and_turn_boundary_transition_parity(kernel)
	_test_suppression_transition_parity(kernel)
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


func _test_fresh_prototype_metadata(kernel: Object) -> void:
	var catalog_card: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan",
		Rules.PLAYER_OWNER,
		&"native_prototype_card"
	)
	var prototype_state := State.new(
		Rules.empty_board(),
		[catalog_card],
		[],
		Rules.PLAYER_OWNER
	)
	var compact := CompactState.new()
	_check(compact.capture_state(prototype_state), "Fresh-prototype fixture captures")
	_check(
		bool(kernel.call("load_compact_payload", compact.to_variant_payload())),
		"Native kernel loads fresh-card prototype metadata"
	)
	var layout: Dictionary = kernel.call("inspect_layout") as Dictionary
	_check(
		int(layout.get("fresh_card_prototype_count", -1)) == 1,
		"Native kernel compiles one fresh-card prototype"
	)
	var actual: Dictionary = kernel.call(
		"apply_play_transition",
		0,
		4,
		&"native_prototype_card"
	) as Dictionary
	_check(bool(actual.get("supported", false)), "Prototype metadata preserves a supported transition")
	var result_payload: Dictionary = actual.get("payload", {}) as Dictionary
	_check(
		(result_payload.get("fresh_card_prototypes", []) as Array).size() == 1,
		"Native transition payload preserves immutable fresh-card prototypes"
	)
	_check(
		int(result_payload.get("empty_deck_draw_prototype_index", -1)) == 0,
		"Native transition payload preserves the dedicated empty-deck fallback reference"
	)
	_check(
		CompactState.from_variant_payload(result_payload) != null,
		"Native payload with fresh-card prototypes remains loadable"
	)
	var legacy_payload: Dictionary = compact.to_variant_payload().duplicate(true)
	legacy_payload.erase("fresh_card_prototypes")
	legacy_payload.erase("empty_deck_draw_prototype_index")
	_check(
		bool(kernel.call("load_compact_payload", legacy_payload)),
		"Native kernel accepts legacy payload without fresh-card prototypes"
	)
	layout = kernel.call("inspect_layout") as Dictionary
	_check(
		int(layout.get("fresh_card_prototype_count", -1)) == 0,
		"Legacy native payload has no inferred prototype metadata"
	)
	var invalid_fallback_payload: Dictionary = compact.to_variant_payload().duplicate(true)
	invalid_fallback_payload["empty_deck_draw_prototype_index"] = 3
	_check(
		not bool(kernel.call("load_compact_payload", invalid_fallback_payload)),
		"Native kernel rejects an out-of-range empty-deck fallback reference"
	)


func _test_activation_legal_action_parity(kernel: Object) -> void:
	var source: Dictionary = _make_plain_card(
		&"原生主动能力源",
		&"native_activation_source",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	source["ki"] = 1
	source["effect_gate"] = &"native_activation_gate"
	var target_rules: Array[StringName] = [
		Catalog.TARGET_ADJACENT_EMPTY_BOARD,
		Catalog.TARGET_ADJACENT_ALLY_BOARD,
		Catalog.TARGET_ADJACENT_ENEMY_BOARD,
		Catalog.TARGET_OTHER_ALLY_BOARD,
		Catalog.TARGET_ENEMY_HAND_CARD,
		Catalog.TARGET_ALLY_HAND_CARD,
		Catalog.TARGET_ANY_EMPTY_BOARD,
		Catalog.TARGET_ANY_ENEMY_BOARD,
	]
	var abilities: Array = []
	for target_rule: StringName in target_rules:
		abilities.append({
			"retained_on_flip": false,
			"activation": {
				"input": Catalog.ACTIVATION_DRAG_TO_TARGET,
				"target_rule": target_rule,
				"costs": [{"type": Catalog.ACTION_SPEND_KI, "amount": 1}],
				"actions": [{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1}],
			},
		})
	source["active_abilities"] = abilities
	var board: Array = Rules.empty_board()
	board[4] = _slot(source, Rules.PLAYER_OWNER)
	board[1] = _slot(
		_make_plain_card(&"原生相邻友方", &"native_activation_ally_a", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
		Rules.PLAYER_OWNER
	)
	board[8] = _slot(
		_make_plain_card(&"原生其它友方", &"native_activation_ally_b", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
		Rules.PLAYER_OWNER
	)
	board[5] = _slot(
		_make_plain_card(&"原生相邻敌方", &"native_activation_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		Rules.OPPONENT_OWNER
	)
	var state := State.new(
		board,
		[
			_make_plain_card(&"原生友方手牌甲", &"native_activation_hand_a", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
			_make_plain_card(&"原生友方手牌乙", &"native_activation_hand_b", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
		],
		[
			_make_plain_card(&"原生敌方手牌甲", &"native_activation_enemy_hand_a", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
			_make_plain_card(&"原生敌方手牌乙", &"native_activation_enemy_hand_b", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		],
		Rules.PLAYER_OWNER
	)
	(state.enabled_effect_gates_by_owner[Rules.PLAYER_OWNER] as Array).append(
		&"native_activation_gate"
	)
	_check_legal_action_parity(kernel, state, Rules.PLAYER_OWNER, "Eight activation target rules")
	var activation_count: int = 0
	for action: Action in Simulator.get_legal_actions_for_owner(state, Rules.PLAYER_OWNER):
		if action.action_type == Action.TYPE_ACTIVATE:
			activation_count += 1
	_check(activation_count == 16, "Eight activation target rules enumerate every ordered target")

	var no_ki_state: State = state.duplicate_state()
	((no_ki_state.board[4] as Dictionary).get("card", {}) as Dictionary)["ki"] = 0
	_check_legal_action_parity(kernel, no_ki_state, Rules.PLAYER_OWNER, "Activation ki cost")
	_check(
		_count_activate_actions(Simulator.get_legal_actions_for_owner(no_ki_state, Rules.PLAYER_OWNER)) == 0,
		"Insufficient ki removes every activation action"
	)

	var gated_state: State = state.duplicate_state()
	gated_state.enabled_effect_gates_by_owner[Rules.PLAYER_OWNER] = []
	_check_legal_action_parity(kernel, gated_state, Rules.PLAYER_OWNER, "Activation effect gate")
	_check(
		_count_activate_actions(Simulator.get_legal_actions_for_owner(gated_state, Rules.PLAYER_OWNER)) == 0,
		"Disabled effect gate removes every activation action"
	)

	var extra_play_state: State = state.duplicate_state()
	extra_play_state.extra_card_plays_remaining = 1
	_check_legal_action_parity(kernel, extra_play_state, Rules.PLAYER_OWNER, "Extra-play activation exclusion")
	_check(
		_count_activate_actions(Simulator.get_legal_actions_for_owner(extra_play_state, Rules.PLAYER_OWNER)) == 0,
		"Extra play exposes only hand-play actions"
	)


func _check_legal_action_parity(
	kernel: Object,
	state: State,
	owner_id: int,
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
	var expected_keys: Array[String] = []
	for action: Action in Simulator.get_legal_actions_for_owner(state, owner_id):
		expected_keys.append(action.canonical_key())
	var actual_keys: Array[String] = []
	for action_value: Variant in kernel.call("get_legal_actions_for_owner", owner_id) as Array:
		actual_keys.append(_native_action_canonical_key(action_value as Dictionary))
	_check(actual_keys == expected_keys, "%s legal actions preserve exact order and identity" % label)


func _native_action_canonical_key(action: Dictionary) -> String:
	return "%s|%s|%010d|%s|%s|%010d|%010d" % [
		StringName(action.get("action_type", &"")),
		StringName(action.get("source_zone", &"")),
		int(action.get("source_index", -1)),
		StringName(action.get("source_instance_id", &"")),
		StringName(action.get("target_kind", &"")),
		int(action.get("target_index", -1)),
		int(action.get("activation_index", 0)),
	]


func _count_activate_actions(actions: Array) -> int:
	var count: int = 0
	for action_value: Variant in actions:
		var action: Action = action_value as Action
		if action != null and action.action_type == Action.TYPE_ACTIVATE:
			count += 1
	return count


func _report_catalog_trigger_inventory() -> void:
	var event_counts: Dictionary = {}
	var condition_counts: Dictionary = {}
	var action_counts: Dictionary = {}
	for card_id: StringName in Catalog.get_all_card_ids():
		var definition: Dictionary = Catalog.get_definition(card_id)
		for ability_value: Variant in definition.get("abilities", []) as Array:
			if ability_value is Dictionary:
				_collect_ability_trigger_inventory(
					ability_value as Dictionary,
					event_counts,
					condition_counts,
					action_counts
				)
	print(
		"DUEL_NATIVE_TRIGGER_INVENTORY events=%s conditions=%s actions=%s"
		% [
			JSON.stringify(_sorted_inventory(event_counts)),
			JSON.stringify(_sorted_inventory(condition_counts)),
			JSON.stringify(_sorted_inventory(action_counts)),
		]
	)


func _collect_ability_trigger_inventory(
	ability: Dictionary,
	event_counts: Dictionary,
	condition_counts: Dictionary,
	action_counts: Dictionary
) -> void:
	for trigger_value: Variant in ability.get("triggers", []) as Array:
		if not trigger_value is Dictionary:
			continue
		var trigger: Dictionary = trigger_value
		_increment_inventory(event_counts, StringName(trigger.get("event", &"")))
		_collect_condition_inventory(
			trigger.get("conditions", []) as Array,
			condition_counts
		)
		_collect_action_inventory(
			trigger.get("actions", []) as Array,
			event_counts,
			condition_counts,
			action_counts
		)


func _collect_action_inventory(
	actions: Array,
	event_counts: Dictionary,
	condition_counts: Dictionary,
	action_counts: Dictionary
) -> void:
	for action_value: Variant in actions:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		_increment_inventory(action_counts, StringName(action.get("type", &"")))
		_collect_condition_inventory(
			action.get("conditions", []) as Array,
			condition_counts
		)
		var selector_value: Variant = action.get("selector", null)
		if selector_value is Dictionary:
			_collect_condition_inventory(
				(selector_value as Dictionary).get("conditions", []) as Array,
				condition_counts
			)
		_collect_action_inventory(
			action.get("actions", []) as Array,
			event_counts,
			condition_counts,
			action_counts
		)
		var granted_ability_value: Variant = action.get("ability", null)
		if granted_ability_value is Dictionary:
			_collect_ability_trigger_inventory(
				granted_ability_value as Dictionary,
				event_counts,
				condition_counts,
				action_counts
			)


func _collect_condition_inventory(conditions: Array, condition_counts: Dictionary) -> void:
	for condition_value: Variant in conditions:
		if condition_value is Dictionary:
			_increment_inventory(
				condition_counts,
				StringName((condition_value as Dictionary).get("type", &""))
			)


func _increment_inventory(counts: Dictionary, key: StringName) -> void:
	if key == &"":
		return
	counts[key] = int(counts.get(key, 0)) + 1


func _sorted_inventory(counts: Dictionary) -> Array[Dictionary]:
	var keys: Array[StringName] = []
	for key_value: Variant in counts:
		keys.append(StringName(key_value))
	keys.sort_custom(func(first: StringName, second: StringName) -> bool:
		return String(first) < String(second)
	)
	var entries: Array[Dictionary] = []
	for key: StringName in keys:
		entries.append({"type": key, "count": int(counts.get(key, 0))})
	return entries


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
	var rejection_reasons_by_card: Dictionary = {}
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
					var source_card_id: String = "unknown"
					var active_hand: Array = opening.get_hand(opening.active_player)
					if action.source_index >= 0 and action.source_index < active_hand.size():
						var source_value: Variant = active_hand[action.source_index]
						if source_value is Dictionary:
							source_card_id = String((source_value as Dictionary).get("card_id", &"unknown"))
					var card_rejections: Dictionary = rejection_reasons_by_card.get(source_card_id, {})
					card_rejections[reason] = int(card_rejections.get(reason, 0)) + 1
					rejection_reasons_by_card[source_card_id] = card_rejections
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
					var mismatch_card_id: String = "unknown"
					var mismatch_hand: Array = opening.get_hand(opening.active_player)
					if action.source_index >= 0 and action.source_index < mismatch_hand.size():
						var mismatch_source: Variant = mismatch_hand[action.source_index]
						if mismatch_source is Dictionary:
							mismatch_card_id = String((mismatch_source as Dictionary).get("card_id", &"unknown"))
					var mismatch_actual_compact: CompactState = CompactState.from_variant_payload(
						actual.get("payload", {}) as Dictionary
					)
					var mismatch_actual_state: State = (
						mismatch_actual_compact.restore() if mismatch_actual_compact != null else null
					)
					var mismatch_expected_state: State = expected.get("state") as State
					print(
						"DUEL_NATIVE_QUICK_MISMATCH card=%s source=%d target=%d state_equal=%s version=%d/%d captures=%s/%s exiles=%s/%s events=%s/%s"
						% [
							mismatch_card_id,
							action.source_index,
							action.target_index,
							str(
								mismatch_actual_state != null
								and mismatch_expected_state != null
								and StateKey.build(mismatch_actual_state) == StateKey.build(mismatch_expected_state)
							),
							mismatch_actual_state.state_version if mismatch_actual_state != null else -1,
							mismatch_expected_state.state_version if mismatch_expected_state != null else -1,
							JSON.stringify(actual.get("captures", [])),
							JSON.stringify(expected.get("captures", [])),
							JSON.stringify(actual.get("exiles", [])),
							JSON.stringify(expected.get("exiles", [])),
							JSON.stringify(_summarize_events(actual.get("events", []) as Array)),
							JSON.stringify(_summarize_events(expected.get("events", []) as Array)),
						]
					)
	_check(unique_openings.size() == 14, "Quick coverage uses 14 unique real openings")
	_check(mismatches == 0, "Every supported Quick root action has exact oracle parity")
	print(
		"DUEL_NATIVE_QUICK_COVERAGE openings=%d total_legal=%d supported=%d exact_parity=%d mismatches=%d rejection_reasons=%s rejection_reasons_by_card=%s"
		% [
			unique_openings.size(),
			total_legal,
			supported,
			exact_parity,
			mismatches,
			JSON.stringify(rejection_reasons),
			JSON.stringify(rejection_reasons_by_card),
		]
	)


func _summarize_events(events: Array) -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for event_value: Variant in events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		var summary: Dictionary = {"type": event.get("type", &"")}
		for key: StringName in [
			&"source_cell",
			&"target_cell",
			&"source_owner_id",
			&"owner_id",
			&"observer_owner_id",
			&"logical_hand_index",
			&"logical_index",
		]:
			if event.has(key):
				summary[key] = event[key]
		summaries.append(summary)
	return summaries


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

	var global_board: Array = Rules.empty_board()
	var global_listener: Dictionary = _make_plain_card(
		&"全场进场监听",
		&"native_global_after_summoned_listener",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	global_listener["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [],
			"actions": [{"type": Catalog.ACTION_GAIN_KI, "amount": 1}],
		}],
	}]
	global_board[0] = _slot(global_listener, Rules.PLAYER_OWNER)
	var global_state := State.new(
		global_board,
		[_make_plain_card(
			&"全场监听进场牌",
			&"native_global_after_summoned_trigger",
			Rules.PLAYER_OWNER,
			[1, 1, 1, 1]
		)],
		[_make_plain_card(
			&"全场监听敌手",
			&"native_global_after_summoned_enemy",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		)],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		global_state,
		0,
		4,
		&"native_global_after_summoned_trigger",
		"After-summoned discovery scans the full board in row-major order"
	)


func _test_draw_reveal_and_difficulty_parity(kernel: Object) -> void:
	var reveal_source: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_enable_draw_reveal_source"
	)
	reveal_source["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{
				"type": Catalog.ACTION_ENABLE_FUTURE_DRAW_REVEAL,
				"recipient": Catalog.RECIPIENT_OPPONENT,
			}],
		}],
	}]
	var enable_state := State.new(
		Rules.empty_board(),
		[
			reveal_source,
			Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_enable_draw_reveal_filler"),
		],
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_enable_draw_reveal_enemy")],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel, enable_state, 0, 4, &"native_enable_draw_reveal_source",
		"Future-draw reveal audience is persisted in compact state"
	)

	var future_draw_state := State.new(
		Rules.empty_board(),
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_future_draw_observer")],
		[
			Catalog.create_instance(&"TuNaShu1", Rules.OPPONENT_OWNER, &"native_future_draw_source"),
			Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_future_draw_filler"),
		],
		Rules.OPPONENT_OWNER,
		0,
		[],
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_future_draw_card")]
	)
	future_draw_state.future_draw_reveal_audiences[Rules.OPPONENT_OWNER] = [
		Rules.PLAYER_OWNER,
	]
	_check_transition_parity(
		kernel, future_draw_state, 0, 4, &"native_future_draw_source",
		"Future-draw audience sees each newly drawn card"
	)

	var enemy_draw_board: Array = Rules.empty_board()
	var enemy_draw_listener: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_enemy_draw_listener"
	)
	enemy_draw_listener["active_abilities"] = [{
		"retained_on_flip": true,
		"triggers": [{
			"event": Catalog.CARD_AFTER_DRAWN,
			"conditions": [{"type": Catalog.CONDITION_DRAWN_CARD_IS_ENEMY}],
			"actions": [{
				"type": Catalog.ACTION_EXILE_CARD,
				"card": Catalog.CARD_REF_TRIGGER_CARD,
			}],
		}],
	}]
	enemy_draw_board[0] = _slot(enemy_draw_listener, Rules.PLAYER_OWNER)
	var enemy_draw_state := State.new(
		enemy_draw_board,
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_enemy_draw_player_hand")],
		[
			Catalog.create_instance(&"TuNaShu1", Rules.OPPONENT_OWNER, &"native_enemy_draw_source"),
			Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_enemy_draw_filler"),
		],
		Rules.OPPONENT_OWNER,
		0,
		[],
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_enemy_draw_card")]
	)
	_check_transition_parity(
		kernel, enemy_draw_state, 0, 4, &"native_enemy_draw_source",
		"Enemy after-drawn reaction can exile the exact drawn hand instance"
	)

	var difficulty_play_state := State.new(
		Rules.empty_board(),
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_difficulty_player_hand")],
		[
			Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_difficulty_play_source"),
			Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_difficulty_play_filler"),
		],
		Rules.OPPONENT_OWNER,
		0,
		[],
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_difficulty_play_draw")]
	)
	difficulty_play_state.run_difficulty = 8
	_check_transition_parity(
		kernel, difficulty_play_state, 0, 4, &"native_difficulty_play_source",
		"Difficulty eight draws when opponent hand first becomes one after play"
	)

	var difficulty_discard_source: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_difficulty_discard_source"
	)
	difficulty_discard_source["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{
				"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [Catalog.CARD_ZONE_HAND],
					"conditions": [{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY}],
					"limit": 1,
					"required_count": 1,
				},
				"actions": [{
					"type": Catalog.ACTION_DISCARD_CARD,
					"card": Catalog.CARD_REF_SELECTED_CARD,
				}],
			}],
		}],
	}]
	var difficulty_discard_state := State.new(
		Rules.empty_board(),
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_difficulty_discard_player")],
		[
			difficulty_discard_source,
			Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_difficulty_discard_target"),
			Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_difficulty_discard_filler"),
		],
		Rules.OPPONENT_OWNER,
		0,
		[],
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_difficulty_discard_draw")]
	)
	difficulty_discard_state.run_difficulty = 8
	_check_transition_parity(
		kernel, difficulty_discard_state, 0, 4, &"native_difficulty_discard_source",
		"Difficulty eight also observes nested discard hand changes"
	)


func _test_draw_trigger_rejections(kernel: Object) -> void:
	var empty_deck_state := State.new(
		Rules.empty_board(),
		[Catalog.create_instance(&"TuNaShu1", Rules.PLAYER_OWNER, &"native_empty_draw")],
		[_make_plain_card(&"敌手", &"native_empty_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel, empty_deck_state, 0, 4, &"native_empty_draw",
		"Empty-deck fallback generates TaiZuChangQuan"
	)

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
	_check_transition_parity(
		kernel, listener_state, 0, 4, &"native_listener_source",
		"After-drawn listener resolves after the card enters hand"
	)

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
	_check_transition_parity(
		kernel,
		unsupported_state,
		0,
		4,
		&"native_unsupported_source",
		"After-summoned ki gain"
	)

	var nested_unknown_source: Dictionary = _make_after_summoned_card(
		&"native_nested_unknown_source",
		{
			"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
			"selector": {
				"zones": [Catalog.CARD_ZONE_BOARD],
				"conditions": [{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY}],
				"limit": 1,
			},
			"actions": [
				{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1},
				{"type": &"native_unknown_nested_action"},
			],
		}
	)
	var nested_unknown_state := State.new(
		Rules.empty_board(),
		[nested_unknown_source],
		[_make_plain_card(&"敌手", &"native_nested_unknown_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER,
		0,
		[_make_plain_card(&"不可泄漏抽牌", &"native_nested_unknown_draw", Rules.PLAYER_OWNER, [1, 1, 1, 1])]
	)
	_check_transition_rejected(
		kernel,
		nested_unknown_state,
		&"native_nested_unknown_source",
		"Unsupported nested action is rejected atomically"
	)


func _test_summon_before_lifecycle_parity(kernel: Object) -> void:
	var swap_listener: Dictionary = _make_plain_card(
		&"进场换位监听者",
		&"native_summoned_swap_listener",
		Rules.OPPONENT_OWNER,
		[0, 0, 0, 0]
	)
	swap_listener["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_SUMMONED,
			"conditions": [
				{"type": Catalog.CONDITION_TRIGGER_CARD_IS_ENEMY},
				{"type": Catalog.CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE},
			],
			"actions": [{"type": Catalog.ACTION_SWAP_SELF_WITH_TRIGGER_CARD}],
		}],
	}]
	var swapped_summon: Dictionary = _make_plain_card(
		&"换位后进场牌",
		&"native_summoned_swapped_card",
		Rules.PLAYER_OWNER,
		[0, 0, 0, 0]
	)
	swapped_summon["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_GAIN_KI, "amount": 1}],
		}],
	}]
	var swapped_board: Array = Rules.empty_board()
	swapped_board[0] = _slot(swap_listener, Rules.OPPONENT_OWNER)
	var swapped_state := State.new(
		swapped_board,
		[
			swapped_summon,
			_make_plain_card(&"换位后续手牌", &"native_summoned_swap_filler", Rules.PLAYER_OWNER, [0, 0, 0, 0]),
		],
		[_make_plain_card(&"换位敌方手牌", &"native_summoned_swap_enemy", Rules.OPPONENT_OWNER, [0, 0, 0, 0])],
		Rules.PLAYER_OWNER
	)
	var swapped_expected: Dictionary = Simulator.apply_action(
		swapped_state,
		Action.make_play(0, 1, &"native_summoned_swapped_card")
	)
	var swapped_result: State = swapped_expected.get("state") as State
	_check(
		swapped_result != null
		and StringName(((swapped_result.board[0] as Dictionary).get("card", {}) as Dictionary).get("instance_id", &""))
		== &"native_summoned_swapped_card"
		and int(((swapped_result.board[0] as Dictionary).get("card", {}) as Dictionary).get("ki", 0)) == 1,
		"A summoned hand instance moved during CARD_SUMMONED resolves CARD_AFTER_SUMMONED from its current cell"
	)
	_check_transition_parity(
		kernel,
		swapped_state,
		0,
		1,
		&"native_summoned_swapped_card",
		"CARD_SUMMONED relocation preserves full-board CARD_AFTER_SUMMONED discovery"
	)

	var no_form_board: Array = Rules.empty_board()
	no_form_board[3] = _slot(
		_make_plain_card(&"无招相邻友方", &"native_no_form_ally", Rules.PLAYER_OWNER, [9, 9, 9, 9]),
		Rules.PLAYER_OWNER
	)
	no_form_board[5] = _slot(
		_make_plain_card(&"无招相邻敌方", &"native_no_form_enemy", Rules.OPPONENT_OWNER, [9, 9, 9, 9]),
		Rules.OPPONENT_OWNER
	)
	var no_form_state := State.new(
		no_form_board,
		[Catalog.create_instance(&"DuGu9Jian1", Rules.PLAYER_OWNER, &"native_no_form")],
		[
			_make_plain_card(&"待揭示甲", &"native_no_form_reveal_a", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
			_make_plain_card(&"待揭示乙", &"native_no_form_reveal_b", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		],
		Rules.PLAYER_OWNER,
		0,
		[
			_make_plain_card(&"无招本方抽一", &"native_no_form_draw_ally", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
			_make_plain_card(&"无招本方抽二", &"native_no_form_draw_self", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
		],
		[_make_plain_card(&"无招敌方抽牌", &"native_no_form_draw_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])]
	)
	var no_form_expected: Dictionary = Simulator.apply_action(
		no_form_state,
		Action.make_play(0, 4, &"native_no_form")
	)
	var no_form_events: Array = no_form_expected.get("events", []) as Array
	_check(
		_first_event_index(no_form_events, &"card_revealed")
		< _first_event_index(no_form_events, &"card_exiled"),
		"No-form reveals the enemy hand before exiling cards"
	)
	_check(
		_count_event_type(no_form_events, &"card_exiled") == 3
		and _count_event_type(no_form_events, &"card_drawn") == 3,
		"No-form exiles self and both adjacent cards and draws for each owner"
	)
	_check(
		_count_event_type(no_form_events, &"attack_started") == 0,
		"A card that leaves during before-summoned skips its standard attack"
	)
	_check_transition_parity(
		kernel,
		no_form_state,
		0,
		4,
		&"native_no_form",
		"Before-summoned reveal, self-exile, owner draws, and adjacent snapshot"
	)

	var anticipate_board: Array = Rules.empty_board()
	anticipate_board[0] = _slot(
		Catalog.create_instance(
			&"TaiZuChangQuan",
			Rules.OPPONENT_OWNER,
			&"native_anticipate_enemy_previous"
		),
		Rules.OPPONENT_OWNER
	)
	anticipate_board[8] = _slot(
		Catalog.create_instance(
			&"TaiZuChangQuan",
			Rules.PLAYER_OWNER,
			&"native_anticipate_ally_previous"
		),
		Rules.PLAYER_OWNER
	)
	var anticipate_state := State.new(
		anticipate_board,
		[Catalog.create_instance(&"DuGu9Jian2", Rules.PLAYER_OWNER, &"native_anticipate")],
		[_make_plain_card(&"料敌敌手", &"native_anticipate_enemy_hand", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER,
		0,
		[_make_plain_card(&"料敌抽牌", &"native_anticipate_draw", Rules.PLAYER_OWNER, [1, 1, 1, 1])]
	)
	anticipate_state.last_hand_play_by_owner = {
		Rules.PLAYER_OWNER: {
			"card_id": &"TaiZuChangQuan",
			"instance_id": &"native_anticipate_ally_previous",
			"played_by_owner_id": Rules.PLAYER_OWNER,
		},
		Rules.OPPONENT_OWNER: {
			"card_id": &"TaiZuChangQuan",
			"instance_id": &"native_anticipate_enemy_previous",
			"played_by_owner_id": Rules.OPPONENT_OWNER,
		},
	}
	var anticipate_expected: Dictionary = Simulator.apply_action(
		anticipate_state,
		Action.make_play(0, 4, &"native_anticipate")
	)
	var anticipate_result: State = anticipate_expected.get("state") as State
	_check(
		anticipate_result != null
		and anticipate_result.active_player == Rules.PLAYER_OWNER
		and anticipate_result.extra_card_plays_remaining == 1,
		"Anticipate retains the acting owner for its granted extra play"
	)
	_check(
		StringName(
			(anticipate_result.last_hand_play_by_owner.get(Rules.PLAYER_OWNER, {}) as Dictionary).get(
				"instance_id",
				&""
			)
		) == &"native_anticipate",
		"A self-exiled hand play is still recorded as the owner's last hand play"
	)
	_check_transition_parity(
		kernel,
		anticipate_state,
		0,
		4,
		&"native_anticipate",
		"Before-summoned source snapshot survives self-exile and grants an extra play"
	)

	var break_all_state := State.new(
		Rules.empty_board(),
		[Catalog.create_instance(&"DuGu9Jian3", Rules.PLAYER_OWNER, &"native_break_all")],
		[_make_plain_card(&"破尽敌手", &"native_break_all_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER,
		0,
		[_make_plain_card(&"破尽抽牌", &"native_break_all_draw", Rules.PLAYER_OWNER, [1, 1, 1, 1])]
	)
	var break_all_expected: Dictionary = Simulator.apply_action(
		break_all_state,
		Action.make_play(0, 4, &"native_break_all")
	)
	var break_all_result: State = break_all_expected.get("state") as State
	_check(
		break_all_result != null
		and break_all_result.active_player == Rules.PLAYER_OWNER
		and break_all_result.extra_card_plays_remaining == 1
		and int(
			break_all_result.pending_non_retained_suppression_by_owner.get(
				Rules.OPPONENT_OWNER,
				0
			)
		) == 1,
		"Break-all aggregates its extra play and pending enemy suppression"
	)
	_check_transition_parity(
		kernel,
		break_all_state,
		0,
		4,
		&"native_break_all",
		"Before-summoned extra play and pending suppression requests"
	)

	var consumed_extra_state := State.new(
		Rules.empty_board(),
		[
			_make_plain_card(&"消费额外出牌", &"native_consume_extra", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
			_make_plain_card(&"消费后留手", &"native_consume_extra_remain", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
		],
		[_make_plain_card(&"消费额外敌手", &"native_consume_extra_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	consumed_extra_state.extra_card_plays_remaining = 1
	var consumed_extra_expected: Dictionary = Simulator.apply_action(
		consumed_extra_state,
		Action.make_play(0, 4, &"native_consume_extra")
	)
	var consumed_extra_result: State = consumed_extra_expected.get("state") as State
	_check(
		consumed_extra_result != null
		and consumed_extra_result.extra_card_plays_remaining == 0
		and consumed_extra_result.active_player == Rules.OPPONENT_OWNER,
		"An existing extra play is consumed before the played card can grant another"
	)
	_check_transition_parity(
		kernel,
		consumed_extra_state,
		0,
		4,
		&"native_consume_extra",
		"Existing extra-play consumption"
	)

	var pending_before_card: Dictionary = _make_plain_card(
		&"待压制进场前",
		&"native_pending_before_order",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	pending_before_card["weapon"] = "剑法"
	pending_before_card["active_abilities"] = [{
		"retained_on_flip": false,
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_BEFORE_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1}],
		}],
	}]
	var pending_before_state := State.new(
		Rules.empty_board(),
		[pending_before_card],
		[_make_plain_card(&"待压制敌手", &"native_pending_before_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER,
		0,
		[_make_plain_card(&"不应抽到", &"native_pending_before_draw", Rules.PLAYER_OWNER, [1, 1, 1, 1])]
	)
	pending_before_state.pending_non_retained_suppression_by_owner[Rules.PLAYER_OWNER] = 1
	var pending_before_expected: Dictionary = Simulator.apply_action(
		pending_before_state,
		Action.make_play(0, 4, &"native_pending_before_order")
	)
	_check(
		_count_event_type(pending_before_expected.get("events", []) as Array, &"card_drawn") == 0,
		"Pending suppression is consumed before before-summoned discovery"
	)
	_check_transition_parity(
		kernel,
		pending_before_state,
		0,
		4,
		&"native_pending_before_order",
		"Pending suppression precedes the next non-heart before-summoned trigger"
	)

	var summoned_listener_ability: Dictionary = {
		"retained_on_flip": false,
		"triggers": [
			{
				"event": Catalog.TRIGGER_CARD_SUMMONED,
				"conditions": [],
				"actions": [{"type": Catalog.ACTION_GAIN_KI, "amount": 1}],
			},
			{
				"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
				"conditions": [],
				"actions": [{"type": Catalog.ACTION_GAIN_KI, "amount": 1}],
			},
		],
	}
	var global_board: Array = Rules.empty_board()
	var first_listener: Dictionary = _make_plain_card(
		&"首格进场监听",
		&"native_global_summon_first",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	first_listener["active_abilities"] = [summoned_listener_ability.duplicate(true)]
	global_board[0] = _slot(first_listener, Rules.PLAYER_OWNER)
	var last_listener: Dictionary = _make_plain_card(
		&"末格进场监听",
		&"native_global_summon_last",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	last_listener["active_abilities"] = [summoned_listener_ability.duplicate(true)]
	global_board[8] = _slot(last_listener, Rules.PLAYER_OWNER)
	var global_state := State.new(
		global_board,
		[_make_plain_card(&"全场进场源", &"native_global_summon_source", Rules.PLAYER_OWNER, [1, 1, 1, 1])],
		[_make_plain_card(&"全场敌手", &"native_global_summon_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	var global_expected: Dictionary = Simulator.apply_action(
		global_state,
		Action.make_play(0, 4, &"native_global_summon_source")
	)
	var global_trigger_cells: Array[int] = []
	for event_value: Variant in global_expected.get("events", []) as Array:
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == &"ability_triggered"
		):
			global_trigger_cells.append(int((event_value as Dictionary).get("source_cell", -1)))
	_check(
		global_trigger_cells == [0, 8, 0, 8],
		"CARD_SUMMONED and CARD_AFTER_SUMMONED each scan the full board row-major"
	)
	_check_transition_parity(
		kernel,
		global_state,
		0,
		4,
		&"native_global_summon_source",
		"Full-board summoned and after-summoned discovery order"
	)

	var moved_during_summoned_board: Array = Rules.empty_board()
	moved_during_summoned_board[5] = _slot(
		Catalog.create_instance(
			&"TianWaiYuLong2",
			Rules.PLAYER_OWNER,
			&"native_summoned_swap_listener"
		),
		Rules.PLAYER_OWNER
	)
	var moved_during_summoned_source: Dictionary = _make_after_summoned_card(
		&"native_summoned_moved_source",
		{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1}
	)
	var moved_during_summoned_state := State.new(
		moved_during_summoned_board,
		[moved_during_summoned_source],
		[_make_plain_card(&"换位敌手", &"native_summoned_swap_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER,
		0,
		[_make_plain_card(&"不应在换位后抽到", &"native_summoned_swap_draw", Rules.PLAYER_OWNER, [1, 1, 1, 1])]
	)
	var moved_during_summoned_expected: Dictionary = Simulator.apply_action(
		moved_during_summoned_state,
		Action.make_play(0, 4, &"native_summoned_moved_source")
	)
	_check(
		_count_event_type(
			moved_during_summoned_expected.get("events", []) as Array,
			&"card_drawn"
		) == 1,
		"A hand play moved during CARD_SUMMONED still receives CARD_AFTER_SUMMONED"
	)
	_check_transition_parity(
		kernel,
		moved_during_summoned_state,
		0,
		4,
		&"native_summoned_moved_source",
		"Hand-play after-summoned follows the surviving instance's current cell"
	)

	for yunwu_id: StringName in [&"YunWu13Shi2", &"YunWu13Shi3"]:
		var yunwu_board: Array = Rules.empty_board()
		var suppressed_enemy: Dictionary = _make_plain_card(
			yunwu_id,
			StringName("native_%s_enemy" % String(yunwu_id)),
			Rules.OPPONENT_OWNER,
			[9, 9, 9, 9]
		)
		suppressed_enemy["active_abilities"] = [{
			"retained_on_flip": false,
			"triggers": [{
				"event": Catalog.TRIGGER_CARD_SUMMONED,
				"conditions": [],
				"actions": [{"type": Catalog.ACTION_GAIN_KI, "amount": 1}],
			}],
		}]
		var enemy_cell: int = 5 if yunwu_id == &"YunWu13Shi3" else 0
		yunwu_board[enemy_cell] = _slot(suppressed_enemy, Rules.OPPONENT_OWNER)
		var yunwu_instance_id := StringName("native_%s_source" % String(yunwu_id))
		var yunwu_state := State.new(
			yunwu_board,
			[Catalog.create_instance(yunwu_id, Rules.PLAYER_OWNER, yunwu_instance_id)],
			[_make_plain_card(&"云雾敌手", StringName("native_%s_hand" % String(yunwu_id)), Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
			Rules.PLAYER_OWNER
		)
		var yunwu_expected: Dictionary = Simulator.apply_action(
			yunwu_state,
			Action.make_play(0, 4, yunwu_instance_id)
		)
		_check(
			_count_event_type(yunwu_expected.get("events", []) as Array, &"ki_changed") == 0,
			"%s suppresses full-board summoned reactions before discovery" % String(yunwu_id)
		)
		_check_transition_parity(
			kernel,
			yunwu_state,
			0,
			4,
			yunwu_instance_id,
			"%s temporary suppression restores at the owner-turn boundary" % String(yunwu_id)
		)


func _test_generated_summon_and_turn_boundary_transition_parity(kernel: Object) -> void:
	var depart_source: Dictionary = Catalog.create_instance(
		&"TiYunZong2", Rules.PLAYER_OWNER, &"native_generated_depart_source"
	)
	depart_source["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [
				{
					"type": Catalog.ACTION_DEPART_CARD_FOR_RESUMMON,
					"card": Catalog.CARD_REF_ABILITY_SOURCE,
				},
				{
					"type": Catalog.ACTION_SUMMON_CARD,
					"card": {
						"type": Catalog.CARD_SPEC_FRESH_COPY,
						"of": Catalog.CARD_REF_ABILITY_SOURCE,
					},
					"cell": {
						"type": Catalog.CELL_REF_INITIAL_CARD_CELL,
						"card": Catalog.CARD_REF_ABILITY_SOURCE,
					},
				},
				{
					"type": Catalog.ACTION_GAIN_KI,
					"amount": 1,
					"card": Catalog.CARD_REF_LAST_SUMMONED_CARD,
				},
			],
		}],
	}]
	var depart_state := State.new(
		Rules.empty_board(),
		[
			depart_source,
			Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_generated_depart_filler"),
		],
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_generated_depart_enemy")],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel, depart_state, 0, 4, &"native_generated_depart_source",
		"Depart, fresh-copy summon, and last-summoned reference"
	)
	var end_source: Dictionary = _make_plain_card(
		&"回合结束额外出牌",
		&"native_boundary_end_source",
		Rules.PLAYER_OWNER,
		[0, 0, 0, 0]
	)
	end_source["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_END_OWNER_TURN,
			"conditions": [{"type": Catalog.CONDITION_TURN_OWNER_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_GRANT_EXTRA_CARD_PLAY, "amount": 1}],
		}],
	}]
	var end_board: Array = Rules.empty_board()
	end_board[0] = _slot(end_source, Rules.PLAYER_OWNER)
	var end_state := State.new(
		end_board,
		[
			_make_plain_card(&"结束节点出牌", &"native_boundary_end_play", Rules.PLAYER_OWNER, [0, 0, 0, 0]),
			_make_plain_card(&"结束节点后续", &"native_boundary_end_filler", Rules.PLAYER_OWNER, [0, 0, 0, 0]),
		],
		[_make_plain_card(&"结束节点敌手", &"native_boundary_end_enemy", Rules.OPPONENT_OWNER, [0, 0, 0, 0])],
		Rules.PLAYER_OWNER
	)
	end_state.max_turns = 1
	var end_expected: Dictionary = Simulator.apply_action(
		end_state,
		Action.make_play(0, 4, &"native_boundary_end_play")
	)
	var end_result: State = end_expected.get("state") as State
	_check(
		end_result != null
		and end_result.turn_count == 1
		and end_result.active_player == Rules.PLAYER_OWNER
		and end_result.extra_card_plays_remaining == 1
		and end_result.end_turn_triggers_resolved,
		"End-turn granted extra play survives the action cap and keeps the same owner"
	)
	_check_transition_parity(
		kernel, end_state, 0, 4, &"native_boundary_end_play",
		"End-turn extra play precedes action-cap terminal detection"
	)

	var empty_owner_source: Dictionary = _make_plain_card(
		&"空回合节点",
		&"native_boundary_empty_source",
		Rules.OPPONENT_OWNER,
		[1, 1, 1, 1]
	)
	empty_owner_source["active_abilities"] = [
		{
			"triggers": [{
				"event": Catalog.TRIGGER_START_OWNER_TURN,
				"conditions": [{"type": Catalog.CONDITION_TURN_OWNER_IS_SELF}],
				"actions": [{"type": Catalog.ACTION_GAIN_KI, "amount": 1}],
			}],
		},
		{
			"triggers": [{
				"event": Catalog.TRIGGER_END_OWNER_TURN,
				"conditions": [{"type": Catalog.CONDITION_TURN_OWNER_IS_SELF}],
				"actions": [{
					"type": Catalog.ACTION_CHANGE_POWERS,
					"amount": 1,
					"card": Catalog.CARD_REF_ABILITY_SOURCE,
				}],
			}],
		},
	]
	var empty_owner_board: Array = Rules.empty_board()
	empty_owner_board[0] = _slot(empty_owner_source, Rules.OPPONENT_OWNER)
	var empty_owner_state := State.new(
		empty_owner_board,
		[
			_make_plain_card(&"空回合前出牌", &"native_boundary_empty_play", Rules.PLAYER_OWNER, [0, 0, 0, 0]),
			_make_plain_card(&"空回合后续", &"native_boundary_empty_filler", Rules.PLAYER_OWNER, [0, 0, 0, 0]),
		],
		[],
		Rules.PLAYER_OWNER
	)
	var empty_owner_expected: Dictionary = Simulator.apply_action(
		empty_owner_state,
		Action.make_play(0, 4, &"native_boundary_empty_play")
	)
	var empty_owner_result: State = empty_owner_expected.get("state") as State
	var empty_owner_card: Dictionary = (
		(empty_owner_result.board[0] as Dictionary).get("card", {}) as Dictionary
		if empty_owner_result != null
		else {}
	)
	_check(
		empty_owner_result != null
		and empty_owner_result.active_player == Rules.PLAYER_OWNER
		and int(empty_owner_card.get("ki", 0)) == 1
		and empty_owner_card.get("powers", []) == [2, 2, 2, 2],
		"An owner with no legal action still resolves start and end turn nodes"
	)
	_check_transition_parity(
		kernel, empty_owner_state, 0, 4, &"native_boundary_empty_play",
		"Empty owner turns emit both boundary trigger events"
	)

	var terminal_start_source: Dictionary = _make_plain_card(
		&"终局后不可开始",
		&"native_boundary_terminal_start",
		Rules.OPPONENT_OWNER,
		[1, 1, 1, 1]
	)
	terminal_start_source["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_START_OWNER_TURN,
			"conditions": [{"type": Catalog.CONDITION_TURN_OWNER_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_GAIN_KI, "amount": 1}],
		}],
	}]
	var terminal_board: Array = Rules.empty_board()
	terminal_board[0] = _slot(terminal_start_source, Rules.OPPONENT_OWNER)
	var terminal_state := State.new(
		terminal_board,
		[_make_plain_card(&"终局行动", &"native_boundary_terminal_play", Rules.PLAYER_OWNER, [0, 0, 0, 0])],
		[_make_plain_card(&"终局敌手", &"native_boundary_terminal_enemy", Rules.OPPONENT_OWNER, [0, 0, 0, 0])],
		Rules.PLAYER_OWNER
	)
	terminal_state.max_turns = 1
	var terminal_expected: Dictionary = Simulator.apply_action(
		terminal_state,
		Action.make_play(0, 4, &"native_boundary_terminal_play")
	)
	var terminal_result: State = terminal_expected.get("state") as State
	_check(
		terminal_result != null
		and int((((terminal_result.board[0] as Dictionary).get("card", {}) as Dictionary).get("ki", 0))) == 0,
		"Terminal detection occurs before the next owner's start-turn trigger"
	)
	_check_transition_parity(
		kernel, terminal_state, 0, 4, &"native_boundary_terminal_play",
		"Action-cap terminal detection precedes next-owner start"
	)

	var ending_source: Dictionary = _make_plain_card(
		&"满场前终局",
		&"native_boundary_before_end",
		Rules.OPPONENT_OWNER,
		[0, 0, 0, 0]
	)
	ending_source["active_abilities"] = [{
		"retained_on_flip": true,
		"triggers": [{
			"event": Catalog.TRIGGER_BEFORE_DUEL_END,
			"conditions": [{"type": Catalog.CONDITION_OWNER_DID_NOT_WIN}],
			"actions": [{"type": Catalog.ACTION_EXILE_SELF}],
		}],
	}]
	var ending_board: Array = Rules.empty_board()
	ending_board[0] = _slot(ending_source, Rules.OPPONENT_OWNER)
	for cell_index: int in range(1, 8):
		var owner_id: int = Rules.PLAYER_OWNER if cell_index % 2 == 1 else Rules.OPPONENT_OWNER
		ending_board[cell_index] = _slot(
			_make_plain_card(
				&"满场占位%d" % cell_index,
				&"native_boundary_full_%d" % cell_index,
				owner_id,
				[0, 0, 0, 0]
			),
			owner_id
		)
	var ending_state := State.new(
		ending_board,
		[
			_make_plain_card(&"满场行动", &"native_boundary_full_play", Rules.PLAYER_OWNER, [0, 0, 0, 0]),
			_make_plain_card(&"满场后续", &"native_boundary_full_filler", Rules.PLAYER_OWNER, [0, 0, 0, 0]),
		],
		[_make_plain_card(&"满场敌手", &"native_boundary_full_enemy", Rules.OPPONENT_OWNER, [0, 0, 0, 0])],
		Rules.PLAYER_OWNER
	)
	var ending_expected: Dictionary = Simulator.apply_action(
		ending_state,
		Action.make_play(0, 8, &"native_boundary_full_play")
	)
	var ending_result: State = ending_expected.get("state") as State
	_check(
		ending_result != null and ending_result.board[0] == null,
		"Before-duel-end resolves on the full board before terminal detection"
	)
	_check_transition_parity(
		kernel, ending_state, 0, 8, &"native_boundary_full_play",
		"Full-board before-duel-end reactions precede terminal detection"
	)

	var perfect_board: Array = Rules.empty_board()
	perfect_board[0] = _slot(
		Catalog.create_instance(&"QianShouRuLai5", Rules.PLAYER_OWNER, &"native_perfect_listener"),
		Rules.PLAYER_OWNER
	)
	var perfect_trigger: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_perfect_exile_trigger"
	)
	perfect_trigger["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_EXILE_SELF}],
		}],
	}]
	var perfect_state := State.new(
		perfect_board,
		[
			perfect_trigger,
			Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_perfect_filler"),
		],
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_perfect_enemy")],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel, perfect_state, 0, 4, &"native_perfect_exile_trigger",
		"Perfect runtime copy summons into an exiled card's initial cell"
	)

	var hand_source: Dictionary = Catalog.create_instance(
		&"TuNaShu1", Rules.PLAYER_OWNER, &"native_existing_hand_source"
	)
	hand_source["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [
				{"type": Catalog.ACTION_EXILE_SELF},
				{
					"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
					"selector": {
						"zones": [Catalog.CARD_ZONE_HAND],
						"conditions": [{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY}],
						"limit": 1,
						"required_count": 1,
					},
					"actions": [{
						"type": Catalog.ACTION_SUMMON_CARD,
						"card": Catalog.CARD_REF_SELECTED_CARD,
						"cell": {
							"type": Catalog.CELL_REF_INITIAL_CARD_CELL,
							"card": Catalog.CARD_REF_ABILITY_SOURCE,
						},
					}],
				},
			],
		}],
	}]
	var hand_state := State.new(
		Rules.empty_board(),
		[
			hand_source,
			Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_existing_hand_replacement"),
		],
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_existing_hand_enemy")],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel, hand_state, 0, 4, &"native_existing_hand_source",
		"Existing hand instance summons after its source leaves"
	)

	var removed_source: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_removed_summon_source"
	)
	removed_source["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{
				"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [Catalog.CARD_ZONE_REMOVED],
					"conditions": [{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY}],
					"limit": 1,
					"required_count": 1,
				},
				"actions": [{
					"type": Catalog.ACTION_SUMMON_CARD,
					"card": Catalog.CARD_REF_SELECTED_CARD,
					"cell": {
						"type": Catalog.CELL_REF_FIRST_ADJACENT_EMPTY,
						"card": Catalog.CARD_REF_ABILITY_SOURCE,
					},
				}],
			}],
		}],
	}]
	var removed_state := State.new(
		Rules.empty_board(),
		[
			removed_source,
			Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_removed_summon_filler"),
		],
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_removed_summon_enemy")],
		Rules.PLAYER_OWNER
	)
	var removed_card: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_removed_summon_card"
	)
	removed_card["powers"] = [8, 7, 6, 5]
	removed_state.removed_cards[Rules.PLAYER_OWNER] = [removed_card]
	_check_transition_parity(
		kernel, removed_state, 0, 4, &"native_removed_summon_source",
		"Removed-zone exact instance summons without resetting runtime state"
	)

	var resummon_board: Array = Rules.empty_board()
	resummon_board[0] = _slot(
		Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_resummon_target"),
		Rules.PLAYER_OWNER
	)
	var resummon_source: Dictionary = Catalog.create_instance(
		&"TuNaShu1", Rules.PLAYER_OWNER, &"native_resummon_source"
	)
	resummon_source["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{
				"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [Catalog.CARD_ZONE_BOARD],
					"conditions": [
						{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY},
						{"type": Catalog.CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
					],
					"limit": 1,
					"required_count": 1,
				},
				"actions": [{
					"type": Catalog.ACTION_RESUMMON_CARD_IN_PLACE,
					"card": Catalog.CARD_REF_SELECTED_CARD,
				}],
			}],
		}],
	}]
	var resummon_state := State.new(
		resummon_board,
		[
			resummon_source,
			Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_resummon_filler"),
		],
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_resummon_enemy")],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel, resummon_state, 0, 4, &"native_resummon_source",
		"In-place resummon replaces the old runtime identity with a fresh instance"
	)

	var top_source: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_top_discard_source"
	)
	top_source["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{
				"type": Catalog.ACTION_SUMMON_CARD,
				"card": {
					"type": Catalog.CARD_SPEC_TOP_DISCARD,
					"owner": Catalog.OWNER_ABILITY_SOURCE,
				},
				"cell": {
					"type": Catalog.CELL_REF_FIRST_ADJACENT_OR_ANY_EMPTY,
					"card": Catalog.CARD_REF_ABILITY_SOURCE,
				},
			}],
		}],
	}]
	var top_state := State.new(
		Rules.empty_board(),
		[
			top_source,
			Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_top_discard_filler"),
		],
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_top_discard_enemy")],
		Rules.PLAYER_OWNER
	)
	top_state.discard_piles[Rules.PLAYER_OWNER] = [
		Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_top_discard_card"),
	]
	_check_transition_parity(
		kernel, top_state, 0, 4, &"native_top_discard_source",
		"Top discard instance summons into the first adjacent empty cell"
	)

	var discarded_board: Array = Rules.empty_board()
	discarded_board[0] = _slot(
		Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_discard_anchor"),
		Rules.OPPONENT_OWNER
	)
	var discarded_source: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_direct_discard_source"
	)
	discarded_source["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{
				"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [Catalog.CARD_ZONE_HAND],
					"conditions": [{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY}],
					"limit": 1,
					"required_count": 1,
				},
				"actions": [{
					"type": Catalog.ACTION_DISCARD_CARD,
					"card": Catalog.CARD_REF_SELECTED_CARD,
				}],
			}],
		}],
	}]
	var discarded_state := State.new(
		discarded_board,
		[
			discarded_source,
			Catalog.create_instance(&"NianhuaWeiXiao4", Rules.PLAYER_OWNER, &"native_direct_discard_card"),
		],
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_direct_discard_enemy")],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel, discarded_state, 0, 8, &"native_direct_discard_source",
		"Discarded exact instance summons into the first owner-adjacent empty cell"
	)


func _test_suppression_transition_parity(kernel: Object) -> void:
	var first_ability: Dictionary = {
		"retained_on_flip": false,
		"triggers": [],
	}
	var second_ability: Dictionary = {
		"retained_on_flip": false,
		"triggers": [],
		"modifiers": [],
	}
	var retained_ability: Dictionary = {
		"retained_on_flip": true,
		"triggers": [],
	}
	var expiring_batches: Array = [
		{
			"expires_after_turn": 0,
			"entries": [{"index": 0, "ability": first_ability.duplicate(true)}],
		},
		{
			"expires_after_turn": 0,
			"entries": [{"index": 0, "ability": second_ability.duplicate(true)}],
		},
	]
	var future_batch: Array = [{
		"expires_after_turn": 1,
		"entries": [{"index": 0, "ability": first_ability.duplicate(true)}],
	}]
	var restoration_board: Array = Rules.empty_board()
	restoration_board[0] = _slot(
		_make_suppressed_card(
			&"native_suppression_board",
			Rules.PLAYER_OWNER,
			[retained_ability.duplicate(true)],
			expiring_batches
		),
		Rules.PLAYER_OWNER
	)
	var restoration_state := State.new(
		restoration_board,
		[
			_make_plain_card(
				&"压制恢复出牌",
				&"native_suppression_play",
				Rules.PLAYER_OWNER,
				[1, 1, 1, 1]
			),
			_make_suppressed_card(
				&"native_suppression_hand",
				Rules.PLAYER_OWNER,
				[],
				expiring_batches
			),
		],
		[_make_plain_card(
			&"压制恢复敌手",
			&"native_suppression_enemy",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		)],
		Rules.PLAYER_OWNER,
		0,
		[_make_suppressed_card(
			&"native_suppression_deck",
			Rules.PLAYER_OWNER,
			[],
			future_batch
		)]
	)
	restoration_state.discard_piles[Rules.PLAYER_OWNER] = [
		_make_suppressed_card(
			&"native_suppression_discard",
			Rules.PLAYER_OWNER,
			[],
			expiring_batches
		),
	]
	restoration_state.removed_cards[Rules.OPPONENT_OWNER] = [
		_make_suppressed_card(
			&"native_suppression_removed",
			Rules.OPPONENT_OWNER,
			[],
			expiring_batches
		),
	]
	_check_transition_parity(
		kernel,
		restoration_state,
		0,
		4,
		&"native_suppression_play",
		"Temporary suppression restores across live zones in oracle order"
	)

	var flipped_board: Array = Rules.empty_board()
	flipped_board[1] = _slot(
		_make_suppressed_card(
			&"native_suppression_flipped",
			Rules.OPPONENT_OWNER,
			[],
			expiring_batches
		),
		Rules.OPPONENT_OWNER
	)
	var flipped_state := State.new(
		flipped_board,
		[_make_plain_card(
			&"压制翻面攻击者",
			&"native_suppression_flip_attacker",
			Rules.PLAYER_OWNER,
			[2, 2, 2, 2]
		)],
		[_make_plain_card(
			&"压制翻面敌手",
			&"native_suppression_flip_enemy",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		)],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		flipped_state,
		0,
		4,
		&"native_suppression_flip_attacker",
		"Ownership flips permanently clear temporary suppression batches"
	)

	var moved_source: Dictionary = _make_selector_source(
		&"native_suppression_move_source",
		{
			"zones": [Catalog.CARD_ZONE_DISCARD],
			"conditions": [{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY}],
			"limit": 1,
		},
		[{
			"type": Catalog.ACTION_RETURN_CARD_TO_HAND,
			"card": Catalog.CARD_REF_SELECTED_CARD,
			"recipient": Catalog.OWNER_CARD_CURRENT,
			"preserve_instance": true,
		}]
	)
	var moved_state := State.new(
		Rules.empty_board(),
		[moved_source],
		[_make_plain_card(
			&"压制移动敌手",
			&"native_suppression_move_enemy",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		)],
		Rules.PLAYER_OWNER
	)
	moved_state.discard_piles[Rules.PLAYER_OWNER] = [
		_make_suppressed_card(
			&"native_suppression_moved",
			Rules.PLAYER_OWNER,
			[],
			expiring_batches
		),
	]
	_check_transition_parity(
		kernel,
		moved_state,
		0,
		4,
		&"native_suppression_move_source",
		"Suppression follows an exact instance from discard into hand before restoration"
	)

	var pending_card: Dictionary = _make_plain_card(
		&"待消费压制牌",
		&"native_pending_suppression_play",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	var pending_removed_ability: Dictionary = {
		"retained_on_flip": false,
		"triggers": [],
		"modifiers": [{"type": &"native_unsupported_modifier"}],
	}
	pending_card["active_abilities"] = [
		pending_removed_ability,
		retained_ability.duplicate(true),
	]
	var pending_state := State.new(
		Rules.empty_board(),
		[pending_card],
		[_make_plain_card(
			&"待消费压制敌手",
			&"native_pending_suppression_enemy",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		)],
		Rules.PLAYER_OWNER
	)
	pending_state.pending_non_retained_suppression_by_owner[Rules.PLAYER_OWNER] = 1
	_check_transition_parity(
		kernel,
		pending_state,
		0,
		4,
		&"native_pending_suppression_play",
		"Pending suppression consumes one layer before a non-heart summon"
	)

	var heart_card: Dictionary = pending_card.duplicate(true)
	heart_card["instance_id"] = &"native_pending_suppression_heart"
	heart_card["weapon"] = "心法"
	heart_card["active_abilities"] = [
		first_ability.duplicate(true),
		retained_ability.duplicate(true),
	]
	var heart_state := State.new(
		Rules.empty_board(),
		[heart_card],
		[_make_plain_card(
			&"心法压制敌手",
			&"native_pending_suppression_heart_enemy",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		)],
		Rules.PLAYER_OWNER
	)
	heart_state.pending_non_retained_suppression_by_owner[Rules.PLAYER_OWNER] = 1
	_check_transition_parity(
		kernel,
		heart_state,
		0,
		4,
		&"native_pending_suppression_heart",
		"Heart methods preserve pending suppression"
	)

	var invalid_compact := CompactState.new()
	_check(
		invalid_compact.capture_state(restoration_state),
		"Malformed suppression fixture can be compacted"
	)
	var invalid_payload: Dictionary = invalid_compact.to_variant_payload().duplicate(true)
	var invalid_pool: Array = invalid_payload.get("suppression_set_pool", []) as Array
	var invalid_batches: Array = invalid_pool[0] as Array
	var invalid_batch: Dictionary = (invalid_batches[0] as Dictionary).duplicate(true)
	invalid_batch["unknown_field"] = true
	invalid_batches[0] = invalid_batch
	invalid_pool[0] = invalid_batches
	invalid_payload["suppression_set_pool"] = invalid_pool
	_check(
		not bool(kernel.call("load_compact_payload", invalid_payload)),
		"Native load atomically rejects an unknown suppression batch field"
	)


func _test_if_transition_parity(kernel: Object) -> void:
	var conditional_action: Dictionary = {
		"type": Catalog.ACTION_IF,
		"conditions": [{"type": Catalog.CONDITION_SOURCE_OWNER_HAND_EMPTY}],
		"actions": [{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1}],
	}
	var true_source: Dictionary = _make_after_summoned_card(
		&"native_if_true_source",
		conditional_action
	)
	var true_state := State.new(
		Rules.empty_board(),
		[true_source],
		[_make_plain_card(
			&"条件敌手",
			&"native_if_true_enemy",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		)],
		Rules.PLAYER_OWNER,
		0,
		[_make_plain_card(
			&"条件抽牌",
			&"native_if_true_draw",
			Rules.PLAYER_OWNER,
			[1, 1, 1, 1]
		)]
	)
	_check_transition_parity(
		kernel,
		true_state,
		0,
		4,
		&"native_if_true_source",
		"IF executes children when the source owner's hand is empty"
	)

	var false_source: Dictionary = _make_after_summoned_card(
		&"native_if_false_source",
		conditional_action
	)
	var false_state := State.new(
		Rules.empty_board(),
		[
			false_source,
			_make_plain_card(
				&"条件留手",
				&"native_if_false_remain",
				Rules.PLAYER_OWNER,
				[1, 1, 1, 1]
			),
		],
		[_make_plain_card(
			&"条件敌手",
			&"native_if_false_enemy",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		)],
		Rules.PLAYER_OWNER,
		0,
		[_make_plain_card(
			&"不应抽到",
			&"native_if_false_draw",
			Rules.PLAYER_OWNER,
			[1, 1, 1, 1]
		)]
	)
	_check_transition_parity(
		kernel,
		false_state,
		0,
		4,
		&"native_if_false_source",
		"IF no-effect does not stop later transition phases"
	)


func _test_discard_transition_parity(kernel: Object) -> void:
	var single_source: Dictionary = Catalog.create_instance(
		&"LiJingRuLai3",
		Rules.PLAYER_OWNER,
		&"native_discard_single_source"
	)
	var single_state := State.new(
		Rules.empty_board(),
		[
			single_source,
			_make_plain_card(
				&"单弃目标",
				&"native_discard_single_target",
				Rules.PLAYER_OWNER,
				[1, 1, 1, 1]
			),
		],
		[_make_plain_card(
			&"单弃敌手",
			&"native_discard_single_enemy",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		)],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		single_state,
		0,
		4,
		&"native_discard_single_source",
		"Single discard transaction"
	)

	var first: Dictionary = _make_plain_card(
		&"批弃一",
		&"native_discard_batch_first",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	var source: Dictionary = Catalog.create_instance(
		&"LiJingRuLai4",
		Rules.PLAYER_OWNER,
		&"native_discard_batch_source"
	)
	var second: Dictionary = _make_plain_card(
		&"批弃二",
		&"native_discard_batch_second",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	var remaining: Dictionary = _make_plain_card(
		&"批弃留手",
		&"native_discard_batch_remaining",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	first[State.HAND_SLOT_INDEX_KEY] = 0
	source[State.HAND_SLOT_INDEX_KEY] = 1
	second[State.HAND_SLOT_INDEX_KEY] = 3
	remaining[State.HAND_SLOT_INDEX_KEY] = 4
	var batch_state := State.new(
		Rules.empty_board(),
		[remaining, source, second, first],
		[_make_plain_card(
			&"批弃敌手",
			&"native_discard_batch_enemy",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		)],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		batch_state,
		1,
		4,
		&"native_discard_batch_source",
		"Batch discard, one-time hand shift, and batch-size IF"
	)


func _test_transform_transition_parity(kernel: Object) -> void:
	var transform_target: Dictionary = Catalog.create_instance(
		&"SanRuDiYu1",
		Rules.PLAYER_OWNER,
		&"native_transform_target"
	)
	transform_target["powers"] = [9, 8, 7, 6]
	transform_target["ki"] = 5
	transform_target["active_abilities"] = [{
		"retained_on_flip": false,
		"triggers": [{
			"event": Catalog.CARD_AFTER_DISCARDED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{
				"type": Catalog.ACTION_TRANSFORM_CARD,
				"card": Catalog.CARD_REF_TRIGGER_CARD,
				"card_id": &"SanRuDiYu2",
			}],
		}],
	}]
	var discard_source: Dictionary = _make_selector_source(
		&"native_transform_discard_source",
		{
			"zones": [Catalog.CARD_ZONE_HAND],
			"conditions": [{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY}],
			"limit": 1,
		},
		[{"type": Catalog.ACTION_DISCARD_CARD, "card": Catalog.CARD_REF_SELECTED_CARD}]
	)
	var transform_state := State.new(
		Rules.empty_board(),
		[discard_source, transform_target],
		[_make_plain_card(
			&"变形敌手",
			&"native_transform_enemy",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		)],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		transform_state,
		0,
		4,
		&"native_transform_discard_source",
		"Discarded card transforms in place from a reachable fresh prototype"
	)


func _test_preserved_return_transition_parity(kernel: Object) -> void:
	var discard_source: Dictionary = _make_selector_source(
		&"native_preserved_return_source",
		{
			"zones": [Catalog.CARD_ZONE_HAND],
			"conditions": [{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY}],
			"limit": 1,
		},
		[{"type": Catalog.ACTION_DISCARD_CARD, "card": Catalog.CARD_REF_SELECTED_CARD}]
	)
	var returned_target: Dictionary = Catalog.create_instance(
		&"SanRuDiYu1",
		Rules.PLAYER_OWNER,
		&"native_preserved_return_target"
	)
	var return_state := State.new(
		Rules.empty_board(),
		[discard_source, returned_target],
		[_make_plain_card(
			&"回手敌手",
			&"native_preserved_return_enemy",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		)],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		return_state,
		0,
		4,
		&"native_preserved_return_source",
		"Transformed discard card returns as the same publicly revealed instance"
	)

	var public_source: Dictionary = _make_selector_source(
		&"native_public_return_source",
		{
			"zones": [Catalog.CARD_ZONE_HAND],
			"conditions": [{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY}],
			"limit": 1,
		},
		[{"type": Catalog.ACTION_DISCARD_CARD, "card": Catalog.CARD_REF_SELECTED_CARD}]
	)
	var public_target: Dictionary = Catalog.create_instance(
		&"SanRuDiYu1",
		Rules.PLAYER_OWNER,
		&"native_public_return_target"
	)
	public_target["revealed_to_owner_ids"] = [
		Rules.PLAYER_OWNER,
		Rules.OPPONENT_OWNER,
	]
	_check_transition_parity(
		kernel,
		State.new(
			Rules.empty_board(),
			[public_source, public_target],
			[_make_plain_card(
				&"公开回手敌手",
				&"native_public_return_enemy",
				Rules.OPPONENT_OWNER,
				[1, 1, 1, 1]
			)],
			Rules.PLAYER_OWNER
		),
		0,
		4,
		&"native_public_return_source",
		"Already-public preserved return emits no duplicate reveal"
	)

	var full_source: Dictionary = _make_selector_source(
		&"native_full_return_source",
		{
			"zones": [Catalog.CARD_ZONE_HAND],
			"conditions": [{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY}],
			"limit": 1,
		},
		[{"type": Catalog.ACTION_DISCARD_CARD, "card": Catalog.CARD_REF_SELECTED_CARD}]
	)
	var full_target: Dictionary = Catalog.create_instance(
		&"SanRuDiYu1",
		Rules.PLAYER_OWNER,
		&"native_full_return_target"
	)
	full_target["active_abilities"] = [{
		"retained_on_flip": false,
		"triggers": [{
			"event": Catalog.CARD_AFTER_DISCARDED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [
				{
					"type": Catalog.ACTION_TRANSFORM_CARD,
					"card": Catalog.CARD_REF_TRIGGER_CARD,
					"card_id": &"SanRuDiYu2",
				},
				{"type": Catalog.ACTION_DRAW_CARDS, "amount": 2},
				{
					"type": Catalog.ACTION_RETURN_CARD_TO_HAND,
					"card": Catalog.CARD_REF_TRIGGER_CARD,
					"recipient": Catalog.OWNER_CARD_CURRENT,
					"preserve_instance": true,
				},
			],
		}],
	}]
	var full_state := State.new(
		Rules.empty_board(),
		[
			full_source,
			full_target,
			_make_plain_card(&"满手一", &"native_full_return_one", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
			_make_plain_card(&"满手二", &"native_full_return_two", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
			_make_plain_card(&"满手三", &"native_full_return_three", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
		],
		[_make_plain_card(
			&"满手回手敌手",
			&"native_full_return_enemy",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		)],
		Rules.PLAYER_OWNER,
		0,
		[
			_make_plain_card(&"补满一", &"native_full_return_draw_one", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
			_make_plain_card(&"补满二", &"native_full_return_draw_two", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
		]
	)
	_check_transition_parity(
		kernel,
		full_state,
		0,
		4,
		&"native_full_return_source",
		"Full-hand preserved return exiles the same transformed instance"
	)


func _test_selector_transition_parity(kernel: Object) -> void:
	var zone_source: Dictionary = _make_selector_source(
		&"native_selector_zone_source",
		{
			"zones": [
				Catalog.CARD_ZONE_HAND,
				Catalog.CARD_ZONE_BOARD,
				Catalog.CARD_ZONE_DISCARD,
				Catalog.CARD_ZONE_REMOVED,
				Catalog.CARD_ZONE_HAND,
			],
			"conditions": [],
		},
		[{"type": Catalog.ACTION_EXILE_CARD, "card": Catalog.CARD_REF_SELECTED_CARD}]
	)
	var zone_player_hand: Dictionary = _make_plain_card(
		&"区域玩家手牌",
		&"native_selector_zone_player_hand",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	zone_player_hand[State.HAND_SLOT_INDEX_KEY] = 4
	var zone_enemy_hand: Dictionary = _make_plain_card(
		&"区域敌方手牌",
		&"native_selector_zone_enemy_hand",
		Rules.OPPONENT_OWNER,
		[1, 1, 1, 1]
	)
	zone_enemy_hand[State.HAND_SLOT_INDEX_KEY] = 3
	var zone_board: Array = Rules.empty_board()
	zone_board[8] = _slot(
		_make_plain_card(&"区域场上牌", &"native_selector_zone_board", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		Rules.OPPONENT_OWNER
	)
	var zone_state := State.new(
		zone_board,
		[zone_source, zone_player_hand],
		[zone_enemy_hand],
		Rules.PLAYER_OWNER
	)
	zone_state.discard_piles[Rules.PLAYER_OWNER] = [
		_make_plain_card(&"区域弃牌", &"native_selector_zone_discard", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
	]
	zone_state.removed_cards[Rules.OPPONENT_OWNER] = [
		_make_plain_card(&"区域移除牌", &"native_selector_zone_removed", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
	]
	_check_transition_parity(
		kernel,
		zone_state,
		0,
		4,
		&"native_selector_zone_source",
		"Selector scans four zones once and survives source exile"
	)

	var left: Dictionary = _make_plain_card(&"左侧", &"native_selector_left", Rules.PLAYER_OWNER, [1, 1, 1, 1])
	left[State.HAND_SLOT_INDEX_KEY] = 0
	var middle: Dictionary = _make_plain_card(&"中间", &"native_selector_middle", Rules.PLAYER_OWNER, [1, 1, 1, 1])
	middle[State.HAND_SLOT_INDEX_KEY] = 2
	var right: Dictionary = _make_plain_card(&"右侧", &"native_selector_right", Rules.PLAYER_OWNER, [1, 1, 1, 1])
	right[State.HAND_SLOT_INDEX_KEY] = 4
	var reverse_source: Dictionary = _make_selector_source(
		&"native_selector_reverse_source",
		{
			"zones": [Catalog.CARD_ZONE_HAND],
			"conditions": [{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY}],
			"order": Catalog.SELECT_ORDER_HAND_RIGHT_TO_LEFT,
			"limit": 2,
			"required_count": 2,
		},
		[{"type": Catalog.ACTION_EXILE_CARD, "card": Catalog.CARD_REF_SELECTED_CARD}]
	)
	reverse_source[State.HAND_SLOT_INDEX_KEY] = 1
	var reverse_state := State.new(
		Rules.empty_board(),
		[left, reverse_source, right, middle],
		[_make_plain_card(&"敌手", &"native_selector_reverse_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_selector_exile_order(
		kernel,
		reverse_state,
		1,
		&"native_selector_reverse_source",
		[&"native_selector_right", &"native_selector_middle"],
		"Selector uses physical hand slots right-to-left"
	)

	var required_source: Dictionary = _make_selector_source(
		&"native_selector_required_source",
		{
			"zones": [Catalog.CARD_ZONE_HAND],
			"conditions": [{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY}],
			"limit": 2,
			"required_count": 3,
		},
		[{"type": Catalog.ACTION_EXILE_CARD, "card": Catalog.CARD_REF_SELECTED_CARD}]
	)
	var required_state := State.new(
		Rules.empty_board(),
		[
			required_source,
			_make_plain_card(&"不足一", &"native_selector_required_one", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
			_make_plain_card(&"不足二", &"native_selector_required_two", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
		],
		[_make_plain_card(&"敌手", &"native_selector_required_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_selector_exile_order(
		kernel,
		required_state,
		0,
		&"native_selector_required_source",
		[],
		"Selector clears a limit snapshot that misses required_count"
	)

	var flip_target: Dictionary = _make_plain_card(
		&"攻击翻面目标",
		&"native_selector_flip_target",
		Rules.OPPONENT_OWNER,
		[0, 0, 0, 0]
	)
	var flip_board: Array = Rules.empty_board()
	flip_board[1] = _slot(flip_target, Rules.OPPONENT_OWNER)
	var flip_source: Dictionary = _make_plain_card(
		&"攻击翻面选择器",
		&"native_selector_flip_source",
		Rules.PLAYER_OWNER,
		[2, 2, 2, 2]
	)
	flip_source["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_ATTACK,
			"conditions": [{"type": Catalog.CONDITION_ATTACKER_CARD_IS_SELF}],
			"actions": [{
				"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [Catalog.CARD_ZONE_BOARD],
					"conditions": [{"type": Catalog.CONDITION_SELECTED_CARD_FLIPPED_BY_CURRENT_ATTACK}],
				},
				"actions": [{"type": Catalog.ACTION_EXILE_CARD, "card": Catalog.CARD_REF_SELECTED_CARD}],
			}],
		}],
	}]
	var flip_state := State.new(
		flip_board,
		[flip_source],
		[_make_plain_card(&"敌手", &"native_selector_flip_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		flip_state,
		0,
		4,
		&"native_selector_flip_source",
		"Selector identifies the exact card flipped by the current attack"
	)

	var compound_board: Array = Rules.empty_board()
	var compound_target: Dictionary = _make_plain_card(
		&"复合条件目标",
		&"native_selector_compound_target",
		Rules.OPPONENT_OWNER,
		[2, 1, 2, 1]
	)
	compound_target["weapon"] = "验证剑法"
	compound_board[4] = _slot(compound_target, Rules.OPPONENT_OWNER)
	for cell: int in [3, 5, 7]:
		compound_board[cell] = _slot(
			_make_plain_card(
				StringName("包围友方%d" % cell),
				StringName("native_selector_surround_%d" % cell),
				Rules.PLAYER_OWNER,
				[1, 1, 1, 1]
			),
			Rules.PLAYER_OWNER
		)
	var compound_source: Dictionary = _make_selector_source(
		&"native_selector_compound_source",
		{
			"zones": [Catalog.CARD_ZONE_BOARD],
			"conditions": [
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_ENEMY},
				{"type": Catalog.CONDITION_SELECTED_CARD_WEAPON_IS, "weapon": "验证剑法"},
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
				{"type": Catalog.CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
				{"type": Catalog.CONDITION_SELECTED_CARD_SURROUNDED_BY_ALLIES},
				{"type": Catalog.CONDITION_SELECTED_CARD_ORIGINAL_OWNER_IS_ENEMY},
				{"type": Catalog.CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE},
				{"type": Catalog.CONDITION_SELECTED_CARD_HAS_NONZERO_POWER},
			],
		},
		[{"type": Catalog.ACTION_EXILE_CARD, "card": Catalog.CARD_REF_SELECTED_CARD}]
	)
	var compound_state := State.new(
		compound_board,
		[compound_source],
		[_make_plain_card(&"敌手", &"native_selector_compound_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_selector_exile_order(
		kernel,
		compound_state,
		0,
		&"native_selector_compound_source",
		[&"native_selector_compound_target"],
		"Selector composes board relationship and card-state conditions",
		1
	)

	var previous_board: Array = Rules.empty_board()
	previous_board[8] = _slot(
		_make_plain_card(&"上一张牌", &"native_selector_previous_target", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		Rules.OPPONENT_OWNER
	)
	var previous_source: Dictionary = _make_selector_source(
		&"native_selector_previous_source",
		{
			"zones": [Catalog.CARD_ZONE_BOARD],
			"conditions": [{
				"type": Catalog.CONDITION_SELECTED_CARD_IS_PREVIOUS_HAND_PLAY,
				"played_by": Catalog.OWNER_OPPONENT_OF_ABILITY_SOURCE,
			}],
		},
		[{"type": Catalog.ACTION_EXILE_CARD, "card": Catalog.CARD_REF_SELECTED_CARD}]
	)
	var previous_state := State.new(
		previous_board,
		[previous_source],
		[_make_plain_card(&"敌手", &"native_selector_previous_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	previous_state.last_hand_play_by_owner[Rules.OPPONENT_OWNER] = {
		"played_by_owner_id": Rules.OPPONENT_OWNER,
		"card_id": &"上一张牌",
		"instance_id": &"native_selector_previous_target",
	}
	_check_selector_exile_order(
		kernel,
		previous_state,
		0,
		&"native_selector_previous_source",
		[&"native_selector_previous_target"],
		"Selector resolves previous hand play by relative owner"
	)

	var spend_candidate: Dictionary = _make_plain_card(
		&"可耗内力",
		&"native_selector_spend_candidate",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	spend_candidate["ki"] = 2
	spend_candidate["active_abilities"] = [{
		"activation": {
			"actions": [{"type": Catalog.ACTION_SPEND_KI, "amount": 1}],
		},
	}]
	var spend_source: Dictionary = _make_selector_source(
		&"native_selector_spend_source",
		{
			"zones": [Catalog.CARD_ZONE_HAND],
			"conditions": [
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY},
				{"type": Catalog.CONDITION_SELECTED_CARD_CAN_SPEND_KI},
				{
					"type": Catalog.CONDITION_SELECTED_CARD_CAN_TRANSFER_RESOURCE,
					"resource": Catalog.RESOURCE_KI,
					"fallback_resource": Catalog.RESOURCE_POWERS,
					"amount": 2,
				},
			],
		},
		[{"type": Catalog.ACTION_EXILE_CARD, "card": Catalog.CARD_REF_SELECTED_CARD}]
	)
	var spend_state := State.new(
		Rules.empty_board(),
		[spend_source, spend_candidate],
		[_make_plain_card(&"敌手", &"native_selector_spend_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_selector_exile_order(
		kernel,
		spend_state,
		0,
		&"native_selector_spend_source",
		[&"native_selector_spend_candidate"],
		"Selector detects automatic or active ki spending and transferable resources"
	)

	var negative_candidate: Dictionary = _make_plain_card(
		&"不可改点资源",
		&"native_selector_negative_candidate",
		Rules.PLAYER_OWNER,
		[-1, -1, -1, -1]
	)
	var power_candidate: Dictionary = _make_plain_card(
		&"点数后备资源",
		&"native_selector_power_candidate",
		Rules.PLAYER_OWNER,
		[0, 2, 0, 0]
	)
	var resource_source: Dictionary = _make_selector_source(
		&"native_selector_resource_source",
		{
			"zones": [Catalog.CARD_ZONE_HAND],
			"conditions": [
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY},
				{"type": Catalog.CONDITION_SELECTED_CARD_ORIGINAL_OWNER_IS_SELF},
				{"type": Catalog.CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE},
				{
					"type": Catalog.CONDITION_SELECTED_CARD_CAN_TRANSFER_RESOURCE,
					"resource": Catalog.RESOURCE_KI,
					"fallback_resource": Catalog.RESOURCE_POWERS,
					"amount": 3,
				},
			],
			"limit": 1,
		},
		[{"type": Catalog.ACTION_EXILE_CARD, "card": Catalog.CARD_REF_SELECTED_CARD}]
	)
	var resource_state := State.new(
		Rules.empty_board(),
		[resource_source, negative_candidate, power_candidate],
		[_make_plain_card(&"敌手", &"native_selector_resource_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_selector_exile_order(
		kernel,
		resource_state,
		0,
		&"native_selector_resource_source",
		[&"native_selector_power_candidate"],
		"Selector skips four-sided negative powers and accepts fallback power resources"
	)

	var revalidate_board: Array = Rules.empty_board()
	for cell: int in [1, 2, 3, 4, 5, 7, 8]:
		var support_card: Dictionary = _make_plain_card(
			StringName("重验牌%d" % cell),
			StringName("native_selector_revalidate_%d" % cell),
			Rules.PLAYER_OWNER,
			[1, 1, 1, 1]
		)
		if cell in [4, 5, 8]:
			support_card["weapon"] = "重验目标"
		revalidate_board[cell] = _slot(support_card, Rules.PLAYER_OWNER)
	var revalidate_source: Dictionary = _make_selector_source(
		&"native_selector_revalidate_source",
		{
			"zones": [Catalog.CARD_ZONE_BOARD],
			"conditions": [
				{"type": Catalog.CONDITION_SELECTED_CARD_WEAPON_IS, "weapon": "重验目标"},
				{"type": Catalog.CONDITION_SELECTED_CARD_SURROUNDED_BY_ALLIES},
			],
			"limit": 2,
		},
		[
			{"type": Catalog.ACTION_EXILE_CARD, "card": Catalog.CARD_REF_SELECTED_CARD},
			{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1},
		]
	)
	var revalidate_state := State.new(
		revalidate_board,
		[revalidate_source],
		[_make_plain_card(&"敌手", &"native_selector_revalidate_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER,
		0,
		[_make_plain_card(&"重验抽牌", &"native_selector_revalidate_draw", Rules.PLAYER_OWNER, [1, 1, 1, 1])]
	)
	_check_selector_exile_order(
		kernel,
		revalidate_state,
		0,
		&"native_selector_revalidate_source",
		[&"native_selector_revalidate_4"],
		"Selector skips a stale second target without refilling from a third",
		0
	)


func _test_power_change_transition_parity(kernel: Object) -> void:
	var dynamic_source: Dictionary = _make_plain_card(
		&"动态改点来源",
		&"native_power_dynamic_source",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	dynamic_source["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [
				{
					"type": Catalog.ACTION_CHANGE_POWERS,
					"card": Catalog.CARD_REF_ABILITY_SOURCE,
					"amount": {
						"type": Catalog.VALUE_CARD_COUNT,
						"zone": Catalog.CARD_ZONE_HAND,
						"owner": Catalog.OWNER_ABILITY_SOURCE,
					},
					"power_change_batch_group": &"native_dynamic_source",
				},
				{
					"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
					"selector": {
						"zones": [Catalog.CARD_ZONE_HAND],
						"conditions": [
							{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY},
							{"type": Catalog.CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE},
						],
					},
					"actions": [{
						"type": Catalog.ACTION_CHANGE_POWERS,
						"card": Catalog.CARD_REF_SELECTED_CARD,
						"amount": {
							"type": Catalog.VALUE_CARD_COUNT,
							"zone": Catalog.CARD_ZONE_HAND,
							"owner": Catalog.OWNER_CARD_CURRENT,
						},
					}],
				},
			],
		}],
	}]
	var dynamic_state := State.new(
		Rules.empty_board(),
		[
			dynamic_source,
			_make_plain_card(&"动态手牌一", &"native_power_dynamic_one", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
			_make_plain_card(&"动态手牌二", &"native_power_dynamic_two", Rules.PLAYER_OWNER, [2, 2, 2, 2]),
		],
		[_make_plain_card(&"敌手", &"native_power_dynamic_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_power_change_fixture(
		kernel,
		dynamic_state,
		&"native_power_dynamic_source",
		3,
		0,
		2,
		"Dynamic hand counts and selector batch sharing"
	)

	var zero_board: Array = Rules.empty_board()
	zero_board[0] = _slot(
		_make_plain_card(&"负点跳过", &"native_power_negative", Rules.OPPONENT_OWNER, [-1, -1, -1, -1]),
		Rules.OPPONENT_OWNER
	)
	zero_board[1] = _slot(
		_make_plain_card(&"归零目标", &"native_power_zero_target", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		Rules.OPPONENT_OWNER
	)
	var zero_source: Dictionary = _make_selector_source(
		&"native_power_zero_source",
		{
			"zones": [Catalog.CARD_ZONE_BOARD],
			"conditions": [
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_ENEMY},
				{"type": Catalog.CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE},
			],
		},
		[{
			"type": Catalog.ACTION_CHANGE_POWERS,
			"card": Catalog.CARD_REF_SELECTED_CARD,
			"amount": -1,
		}]
	)
	var zero_state := State.new(
		zero_board,
		[zero_source],
		[_make_plain_card(&"敌手", &"native_power_zero_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_power_change_fixture(
		kernel,
		zero_state,
		&"native_power_zero_source",
		1,
		1,
		1,
		"Power reduction emits before zero-power exile with one shared batch",
		4
	)


func _test_ki_flip_and_grant_transition_parity(kernel: Object) -> void:
	var ki_source: Dictionary = _make_plain_card(
		&"内力翻面链",
		&"native_ki_flip_source",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	ki_source["active_abilities"] = [
		{
			"retained_on_flip": false,
			"triggers": [{
				"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
				"conditions": [
					{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF},
					{"type": Catalog.CONDITION_KI_AT_LEAST, "amount": 0},
				],
				"actions": [
					{"type": Catalog.ACTION_GAIN_KI, "amount": 2},
					{"type": Catalog.ACTION_SPEND_KI, "amount": 2},
				],
			}],
		},
		{
			"retained_on_flip": false,
			"triggers": [{
				"event": Catalog.CARD_KI_CHANGED,
				"conditions": [
					{"type": Catalog.CONDITION_KI_CHANGED_CARD_IS_SELF},
					{"type": Catalog.CONDITION_KI_REACHED_ZERO},
				],
				"actions": [{
					"type": Catalog.ACTION_FLIP_SELF,
					"new_owner": Catalog.OWNER_OPPONENT_OF_ABILITY_SOURCE,
				}],
			}],
		},
	]
	var ki_state := State.new(
		Rules.empty_board(),
		[ki_source],
		[_make_plain_card(&"敌手", &"native_ki_flip_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		ki_state,
		0,
		4,
		&"native_ki_flip_source",
		"Ki changes resolve zero trigger and non-attack flip before the next action"
	)

	var future_passive: Dictionary = {
		"retained_on_flip": true,
		"triggers": [{
			"event": &"native_future_event",
			"conditions": [],
			"actions": [{"type": &"native_future_action"}],
		}],
	}
	var replacement_activation: Dictionary = {
		"retained_on_flip": false,
		"activation": {
			"actions": [{"type": Catalog.ACTION_SPEND_KI, "amount": 1}],
		},
	}
	var grant_source: Dictionary = _make_plain_card(
		&"动态授予链",
		&"native_grant_source",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	grant_source["active_abilities"] = [
		{
			"retained_on_flip": false,
			"triggers": [{
				"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
				"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
				"actions": [
					{"type": Catalog.ACTION_GRANT_ABILITY_TO_SELF, "ability": future_passive},
					{"type": Catalog.ACTION_GRANT_ABILITY_TO_SELF, "ability": future_passive},
					{"type": Catalog.ACTION_GRANT_ABILITY_TO_SELF, "ability": replacement_activation},
				],
			}],
		},
		{
			"retained_on_flip": false,
			"activation": {"actions": [{"type": Catalog.ACTION_GAIN_KI, "amount": 1}]},
		},
		{
			"retained_on_flip": true,
			"activation": {"actions": [{"type": Catalog.ACTION_GAIN_KI, "amount": 2}]},
		},
	]
	var grant_state := State.new(
		Rules.empty_board(),
		[grant_source],
		[_make_plain_card(&"敌手", &"native_grant_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		grant_state,
		0,
		4,
		&"native_grant_source",
		"Passive grant deduplicates and dynamic activation replaces all innate activations"
	)


func _test_return_to_hand_transition_parity(kernel: Object) -> void:
	var returned_target: Dictionary = Catalog.create_instance(
		&"TuNaShu3",
		Rules.OPPONENT_OWNER,
		&"generated_TuNaShu3_1"
	)
	returned_target["powers"] = [9, 8, 7, 6]
	returned_target["ki"] = 4
	returned_target["active_abilities"] = []
	var board: Array = Rules.empty_board()
	board[1] = _slot(returned_target, Rules.OPPONENT_OWNER)
	var occupied_id: Dictionary = Catalog.create_instance(
		&"TuNaShu3",
		Rules.OPPONENT_OWNER,
		&"generated_TuNaShu3_2"
	)
	occupied_id[State.HAND_SLOT_INDEX_KEY] = 3
	var return_state := State.new(
		board,
		[Catalog.create_instance(&"NianhuaWeiXiao4", Rules.PLAYER_OWNER, &"native_return_source")],
		[occupied_id],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		return_state,
		0,
		4,
		&"native_return_source",
		"Board return creates a public catalog-fresh instance in the leftmost slot"
	)

	var full_board: Array = Rules.empty_board()
	full_board[1] = _slot(
		Catalog.create_instance(&"TuNaShu1", Rules.OPPONENT_OWNER, &"native_full_return_target"),
		Rules.OPPONENT_OWNER
	)
	var full_hand: Array = []
	for hand_index: int in range(5):
		var hand_card: Dictionary = Catalog.create_instance(
			&"TaiZuChangQuan",
			Rules.OPPONENT_OWNER,
			StringName("native_full_return_hand_%d" % hand_index)
		)
		hand_card[State.HAND_SLOT_INDEX_KEY] = hand_index
		full_hand.append(hand_card)
	var full_state := State.new(
		full_board,
		[Catalog.create_instance(&"NianhuaWeiXiao3", Rules.PLAYER_OWNER, &"native_full_return_source")],
		full_hand,
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		full_state,
		0,
		4,
		&"native_full_return_source",
		"Board return to a full hand uses the ordinary external exile lifecycle"
	)

	var compact := CompactState.new()
	_check(compact.capture_state(return_state), "Missing-prototype return fixture captures")
	var missing_payload: Dictionary = compact.to_variant_payload()
	var retained_prototypes: Array = []
	for prototype_value: Variant in missing_payload.get("fresh_card_prototypes", []) as Array:
		var prototype: Dictionary = prototype_value as Dictionary
		if StringName(prototype.get("card_id", &"")) != &"TuNaShu3":
			retained_prototypes.append(prototype)
	missing_payload["fresh_card_prototypes"] = retained_prototypes
	missing_payload["empty_deck_draw_prototype_index"] = _prototype_index_by_card_id(
		retained_prototypes,
		&"TaiZuChangQuan"
	)
	_check(
		bool(kernel.call("load_compact_payload", missing_payload)),
		"Native kernel loads a root missing an optional target prototype"
	)
	var rejected: Dictionary = kernel.call(
		"apply_play_transition",
		0,
		4,
		&"native_return_source"
	) as Dictionary
	_check(
		not bool(rejected.get("supported", false))
		and not bool(rejected.get("valid", false))
		and (rejected.get("events", []) as Array).is_empty()
		and (rejected.get("captures", []) as Array).is_empty()
		and (rejected.get("exiles", []) as Array).is_empty(),
		"A reached return without a fresh prototype rejects atomically"
	)


func _prototype_index_by_card_id(prototypes: Array, card_id: StringName) -> int:
	for index: int in range(prototypes.size()):
		var prototype_value: Variant = prototypes[index]
		if (
			prototype_value is Dictionary
			and StringName((prototype_value as Dictionary).get("card_id", &"")) == card_id
		):
			return index
	return -1


func _test_swap_transition_parity(kernel: Object) -> void:
	var taishan_board: Array = Rules.empty_board()
	taishan_board[5] = _slot(
		_make_plain_card(
			&"原生交换敌方",
			&"native_taishan_swap_target",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		),
		Rules.OPPONENT_OWNER
	)
	var taishan_state := State.new(
		taishan_board,
		[Catalog.create_instance(
			&"TaiShan18Pan2",
			Rules.PLAYER_OWNER,
			&"native_taishan_swap_source"
		)],
		[_make_plain_card(
			&"原生交换敌手",
			&"native_taishan_swap_hand",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		)],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		taishan_state,
		0,
		4,
		&"native_taishan_swap_source",
		"TaiShan performs an ordered adjacent swap before its standard attack"
	)

	var kuihua_board: Array = Rules.empty_board()
	kuihua_board[1] = _slot(
		_make_plain_card(
			&"原生葵花敌方",
			&"native_kuihua_swap_target",
			Rules.OPPONENT_OWNER,
			[9, 9, 9, 9]
		),
		Rules.OPPONENT_OWNER
	)
	var kuihua_state := State.new(
		kuihua_board,
		[Catalog.create_instance(
			&"KuiHua3",
			Rules.PLAYER_OWNER,
			&"native_kuihua_swap_source"
		)],
		[_make_plain_card(
			&"原生葵花敌手",
			&"native_kuihua_swap_hand",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		)],
		Rules.PLAYER_OWNER
	)
	kuihua_state.enabled_effect_gates_by_owner[Rules.PLAYER_OWNER] = [
		Rules.EFFECT_GATE_SELF_CASTRATION,
	]
	_check_transition_parity(
		kernel,
		kuihua_state,
		0,
		4,
		&"native_kuihua_swap_source",
		"KuiHua performs the same selected-card swap under its enabled effect gate"
	)

	var listener: Dictionary = _make_plain_card(
		&"原生移动监听",
		&"native_swap_listener",
		Rules.PLAYER_OWNER,
		[2, 2, 2, 2]
	)
	listener["active_abilities"] = [{
		"retained_on_flip": false,
		"triggers": [{
			"event": Catalog.CARD_BEFORE_MOVED,
			"conditions": [{"type": Catalog.CONDITION_MOVING_CARD_IS_ALLY}],
			"actions": [{
				"type": Catalog.ACTION_CHANGE_POWERS,
				"amount": -1,
				"card": Catalog.CARD_REF_TRIGGER_CARD,
			}],
		}],
	}]
	var listened_board: Array = Rules.empty_board()
	listened_board[0] = _slot(listener, Rules.PLAYER_OWNER)
	listened_board[5] = _slot(
		_make_plain_card(
			&"原生受监听敌方",
			&"native_listened_swap_target",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		),
		Rules.OPPONENT_OWNER
	)
	var listened_state := State.new(
		listened_board,
		[Catalog.create_instance(
			&"TaiShan18Pan2",
			Rules.PLAYER_OWNER,
			&"native_listened_swap_source"
		)],
		[_make_plain_card(
			&"原生受监听敌手",
			&"native_listened_swap_hand",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		)],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		listened_state,
		0,
		4,
		&"native_listened_swap_source",
		"A global before-moved ally listener resolves during the first swap leg"
	)

	var after_move_source: Dictionary = Catalog.create_instance(
		&"TaiShan18Pan2",
		Rules.PLAYER_OWNER,
		&"native_after_move_swap_source"
	)
	var after_move_abilities: Array = (
		after_move_source.get("active_abilities", []) as Array
	).duplicate(true)
	after_move_abilities.append({
		"retained_on_flip": false,
		"triggers": [{
			"event": Catalog.CARD_AFTER_MOVED,
			"conditions": [{"type": Catalog.CONDITION_MOVING_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_GAIN_KI, "amount": 1}],
		}],
	})
	after_move_source["active_abilities"] = after_move_abilities
	var after_move_board: Array = Rules.empty_board()
	after_move_board[5] = _slot(
		_make_plain_card(
			&"原生移动后敌方",
			&"native_after_move_swap_target",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		),
		Rules.OPPONENT_OWNER
	)
	var after_move_state := State.new(
		after_move_board,
		[after_move_source],
		[_make_plain_card(
			&"原生移动后敌手",
			&"native_after_move_swap_hand",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		)],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		after_move_state,
		0,
		4,
		&"native_after_move_swap_source",
		"A self after-moved listener observes the source at its new cell"
	)

	var fragile_source: Dictionary = Catalog.create_instance(
		&"TaiShan18Pan2",
		Rules.PLAYER_OWNER,
		&"native_fragile_swap_source"
	)
	fragile_source["powers"] = [1, 1, 1, 1]
	var cancel_board: Array = Rules.empty_board()
	cancel_board[0] = _slot(listener.duplicate(true), Rules.PLAYER_OWNER)
	cancel_board[5] = _slot(
		_make_plain_card(
			&"原生取消交换敌方",
			&"native_cancel_swap_target",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		),
		Rules.OPPONENT_OWNER
	)
	var cancel_state := State.new(
		cancel_board,
		[fragile_source],
		[_make_plain_card(
			&"原生取消交换敌手",
			&"native_cancel_swap_hand",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		)],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		cancel_state,
		0,
		4,
		&"native_fragile_swap_source",
		"A before-moved listener can exile the moving source and cancel the swap"
	)

	var unsupported_listener: Dictionary = _make_plain_card(
		&"原生未知移动监听",
		&"native_unsupported_swap_listener",
		Rules.PLAYER_OWNER,
		[2, 2, 2, 2]
	)
	unsupported_listener["active_abilities"] = [{
		"retained_on_flip": false,
		"triggers": [{
			"event": Catalog.CARD_BEFORE_MOVED,
			"conditions": [{"type": Catalog.CONDITION_MOVING_CARD_IS_ALLY}],
			"actions": [{
				"type": Catalog.ACTION_REVEAL_CARD,
				"card": Catalog.CARD_REF_TRIGGER_CARD,
				"observer": Catalog.OWNER_ABILITY_SOURCE,
			}],
		}],
	}]
	var unsupported_board: Array = Rules.empty_board()
	unsupported_board[0] = _slot(unsupported_listener, Rules.PLAYER_OWNER)
	unsupported_board[5] = _slot(
		_make_plain_card(
			&"原生未知交换敌方",
			&"native_unsupported_swap_target",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		),
		Rules.OPPONENT_OWNER
	)
	var unsupported_state := State.new(
		unsupported_board,
		[Catalog.create_instance(
			&"TaiShan18Pan2",
			Rules.PLAYER_OWNER,
			&"native_unsupported_swap_source"
		)],
		[_make_plain_card(
			&"原生未知交换敌手",
			&"native_unsupported_swap_hand",
			Rules.OPPONENT_OWNER,
			[1, 1, 1, 1]
		)],
		Rules.PLAYER_OWNER
	)
	var unsupported_compact := CompactState.new()
	_check(
		unsupported_compact.capture_state(unsupported_state),
		"Unsupported movement-listener fixture captures"
	)
	_check(
		bool(kernel.call(
			"load_compact_payload",
			unsupported_compact.to_variant_payload()
		)),
		"Unsupported movement-listener fixture loads natively"
	)
	var unsupported_result: Dictionary = kernel.call(
		"apply_play_transition",
		0,
		4,
		&"native_unsupported_swap_source"
	) as Dictionary
	_check(
		not bool(unsupported_result.get("supported", false))
		and not bool(unsupported_result.get("valid", false))
		and (unsupported_result.get("events", []) as Array).is_empty()
		and (unsupported_result.get("captures", []) as Array).is_empty()
		and (unsupported_result.get("exiles", []) as Array).is_empty(),
		"A reached unsupported movement listener rejects atomically"
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

	var shifted_board: Array = Rules.empty_board()
	var shifted_listener: Dictionary = _make_plain_card(
		&"能力换位监听",
		&"native_shifted_listener",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	shifted_listener["active_abilities"] = [
		{
			"triggers": [{
				"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
				"conditions": [],
				"actions": [{"type": Catalog.ACTION_REMOVE_THIS_ABILITY}],
			}],
		},
		{
			"triggers": [{
				"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
				"conditions": [],
				"actions": [{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1}],
			}],
		},
	]
	shifted_board[0] = _slot(shifted_listener, Rules.PLAYER_OWNER)
	var shifted_state := State.new(
		shifted_board,
		[_make_plain_card(&"换位进场牌", &"native_shifted_source", Rules.PLAYER_OWNER, [1, 1, 1, 1])],
		[_make_plain_card(&"敌手", &"native_shifted_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER,
		0,
		[_make_plain_card(&"换位后抽牌", &"native_shifted_draw", Rules.PLAYER_OWNER, [1, 1, 1, 1])]
	)
	_check_transition_parity(
		kernel,
		shifted_state,
		0,
		4,
		&"native_shifted_source",
		"Removing an earlier ability preserves a discovered later ability"
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
	_check_transition_parity(
		kernel,
		nested_state,
		0,
		4,
		&"native_nested_attacker",
		"Relevant nested attack reaction resolves through the shared attack path"
	)


func _test_event_reaction_primitive_parity(kernel: Object) -> void:
	var reaction_board: Array = Rules.empty_board()
	var reaction_source: Dictionary = _make_plain_card(
		&"全场进场反应",
		&"native_reaction_source",
		Rules.PLAYER_OWNER,
		[3, 3, 3, 3]
	)
	reaction_source["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [
				{"type": Catalog.CONDITION_TRIGGER_CARD_IS_ENEMY},
				{"type": Catalog.CONDITION_TRIGGER_CARD_IN_RANGE},
			],
			"actions": [{"type": Catalog.ACTION_ATTACK_TRIGGER_CARD}],
		}],
	}]
	reaction_board[0] = _slot(reaction_source, Rules.PLAYER_OWNER)
	var reaction_state := State.new(
		reaction_board,
		[_make_plain_card(&"玩家占位手牌", &"native_reaction_player_hand", Rules.PLAYER_OWNER, [1, 1, 1, 1])],
		[_make_plain_card(&"反应目标", &"native_reaction_target", Rules.OPPONENT_OWNER, [0, 0, 0, 0])],
		Rules.OPPONENT_OWNER
	)
	_check_transition_parity(
		kernel,
		reaction_state,
		0,
		1,
		&"native_reaction_target",
		"Full-board after-summoned listener makes an exact targeted reaction"
	)
	var out_of_range_board: Array = Rules.empty_board()
	out_of_range_board[0] = _slot(reaction_source.duplicate(true), Rules.PLAYER_OWNER)
	var out_of_range_state := State.new(
		out_of_range_board,
		[_make_plain_card(&"玩家占位手牌", &"native_reaction_player_hand_far", Rules.PLAYER_OWNER, [1, 1, 1, 1])],
		[_make_plain_card(&"范围外目标", &"native_reaction_far_target", Rules.OPPONENT_OWNER, [0, 0, 0, 0])],
		Rules.OPPONENT_OWNER
	)
	var out_of_range_expected: Dictionary = Simulator.apply_action(
		out_of_range_state,
		Action.make_play(0, 8, &"native_reaction_far_target")
	)
	_check(
		_first_event_index(out_of_range_expected.get("events", []) as Array, &"attack_started") < 0,
		"Out-of-range after-summoned target does not create a reaction attack"
	)
	_check_transition_parity(
		kernel,
		out_of_range_state,
		0,
		8,
		&"native_reaction_far_target",
		"Full-board reaction range condition rejects an out-of-range target"
	)

	var disappearing_board: Array = Rules.empty_board()
	disappearing_board[0] = _slot(reaction_source.duplicate(true), Rules.PLAYER_OWNER)
	disappearing_board[3] = _slot(
		_make_plain_card(&"不可顺延目标", &"native_reaction_second_target", Rules.OPPONENT_OWNER, [0, 0, 0, 0]),
		Rules.OPPONENT_OWNER
	)
	var disappearing_target: Dictionary = _make_plain_card(
		&"受击离场目标",
		&"native_reaction_disappearing_target",
		Rules.OPPONENT_OWNER,
		[0, 0, 0, 0]
	)
	disappearing_target["active_abilities"] = [{
		"retained_on_flip": true,
		"triggers": [{
			"event": Catalog.CARD_BE_ATTACKED,
			"conditions": [{"type": Catalog.CONDITION_ATTACKED_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_EXILE_SELF}],
		}],
	}]
	var disappearing_state := State.new(
		disappearing_board,
		[_make_plain_card(&"玩家占位手牌", &"native_reaction_player_hand_2", Rules.PLAYER_OWNER, [1, 1, 1, 1])],
		[disappearing_target],
		Rules.OPPONENT_OWNER
	)
	_check_transition_parity(
		kernel,
		disappearing_state,
		0,
		1,
		&"native_reaction_disappearing_target",
		"Targeted reaction does not retarget when the exact target leaves during CARD_BE_ATTACKED"
	)

	var flipped_source_board: Array = Rules.empty_board()
	var directional_reaction_source: Dictionary = reaction_source.duplicate(true)
	directional_reaction_source["instance_id"] = &"native_reaction_flipped_source"
	directional_reaction_source["powers"] = [0, 3, 0, 0]
	flipped_source_board[0] = _slot(directional_reaction_source, Rules.PLAYER_OWNER)
	var source_flipper: Dictionary = _make_plain_card(
		&"反应中翻转攻方",
		&"native_reaction_source_flipper",
		Rules.OPPONENT_OWNER,
		[2, 1, 1, 1]
	)
	source_flipper["active_abilities"] = [{
		"retained_on_flip": true,
		"triggers": [{
			"event": Catalog.CARD_BE_ATTACKED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_ALLY}],
			"actions": [{"type": Catalog.ACTION_STANDARD_ATTACK_WITH_SELF}],
		}],
	}]
	flipped_source_board[3] = _slot(source_flipper, Rules.OPPONENT_OWNER)
	var flipped_source_state := State.new(
		flipped_source_board,
		[_make_plain_card(&"玩家占位手牌", &"native_reaction_player_hand_3", Rules.PLAYER_OWNER, [1, 1, 1, 1])],
		[_make_plain_card(&"反应目标", &"native_reaction_flip_target", Rules.OPPONENT_OWNER, [0, 0, 0, 0])],
		Rules.OPPONENT_OWNER
	)
	_check_transition_parity(
		kernel,
		flipped_source_state,
		0,
		1,
		&"native_reaction_flip_target",
		"Targeted reaction stops when its exact attacker changes owner during CARD_BE_ATTACKED"
	)

	var movement_board: Array = Rules.empty_board()
	movement_board[2] = _slot(
		_make_plain_card(&"隔空敌方", &"native_between_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		Rules.OPPONENT_OWNER
	)
	var movement_listener: Dictionary = _make_plain_card(
		&"移动监听",
		&"native_between_listener",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	movement_listener["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.CARD_AFTER_MOVED,
			"conditions": [{"type": Catalog.CONDITION_MOVING_CARD_IS_ALLY}],
			"actions": [{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1}],
		}],
	}]
	movement_board[8] = _slot(movement_listener, Rules.PLAYER_OWNER)
	var moving_source: Dictionary = _make_plain_card(
		&"首个中间空位移动",
		&"native_between_source",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	moving_source["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [
				{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF},
				{"type": Catalog.CONDITION_SOURCE_HAS_EMPTY_BETWEEN_ENEMY},
			],
			"actions": [{"type": Catalog.ACTION_MOVE_SELF_TO_FIRST_EMPTY_BETWEEN_ENEMY}],
		}],
	}]
	var movement_state := State.new(
		movement_board,
		[moving_source],
		[_make_plain_card(&"敌方占位手牌", &"native_between_enemy_hand", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER,
		0,
		[_make_plain_card(&"移动后抽牌", &"native_between_draw", Rules.PLAYER_OWNER, [1, 1, 1, 1])]
	)
	_check_transition_parity(
		kernel,
		movement_state,
		0,
		0,
		&"native_between_source",
		"First empty cell between source and enemy uses the shared movement transaction"
	)

	_check_transfer_fixture(kernel, true)
	_check_transfer_fixture(kernel, false)
	_check_transfer_skips_special_negative_fixture(kernel)
	_check_outside_hand_exile_fixture(kernel, false)
	_check_outside_hand_exile_fixture(kernel, true)

	var counter_board: Array = Rules.empty_board()
	var counter: Dictionary = _make_plain_card(
		&"范围内友方翻面反击",
		&"native_counter_source",
		Rules.PLAYER_OWNER,
		[1, 4, 1, 1]
	)
	counter["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_ATTACK,
			"conditions": [
				{"type": Catalog.CONDITION_ATTACKER_CARD_IS_ENEMY},
				{"type": Catalog.CONDITION_ATTACK_FLIPPED_ALLY_IN_RANGE},
			],
			"actions": [{"type": Catalog.ACTION_STANDARD_ATTACK_WITH_SELF}],
		}],
	}]
	counter_board[0] = _slot(counter, Rules.PLAYER_OWNER)
	counter_board[1] = _slot(
		_make_plain_card(&"被翻友方", &"native_counter_ally", Rules.PLAYER_OWNER, [0, 0, 0, 0]),
		Rules.PLAYER_OWNER
	)
	var counter_state := State.new(
		counter_board,
		[_make_plain_card(&"玩家占位手牌", &"native_counter_player_hand", Rules.PLAYER_OWNER, [1, 1, 1, 1])],
		[_make_plain_card(&"敌方攻方", &"native_counter_attacker", Rules.OPPONENT_OWNER, [2, 2, 2, 2])],
		Rules.OPPONENT_OWNER
	)
	_check_transition_parity(
		kernel,
		counter_state,
		0,
		4,
		&"native_counter_attacker",
		"After-attack reaction recognizes this attack's still-in-range flipped ally"
	)


func _check_transfer_fixture(kernel: Object, use_ki: bool) -> void:
	var donor: Dictionary = _make_plain_card(
		&"资源供体",
		StringName("native_transfer_donor_%s" % ("ki" if use_ki else "powers")),
		Rules.OPPONENT_OWNER,
		[1, 1, 1, 1]
	)
	donor["ki"] = 1 if use_ki else 0
	var board: Array = Rules.empty_board()
	board[0] = _slot(donor, Rules.OPPONENT_OWNER)
	var source: Dictionary = _make_plain_card(
		&"资源接收者",
		StringName("native_transfer_source_%s" % ("ki" if use_ki else "powers")),
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	source["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{
				"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [Catalog.CARD_ZONE_BOARD],
					"conditions": [
						{"type": Catalog.CONDITION_SELECTED_CARD_IS_ENEMY},
						{
							"type": Catalog.CONDITION_SELECTED_CARD_CAN_TRANSFER_RESOURCE,
							"amount": 1,
							"resource": Catalog.RESOURCE_KI,
							"fallback_resource": Catalog.RESOURCE_POWERS,
						},
					],
					"limit": 1,
				},
				"actions": [{
					"type": Catalog.ACTION_TRANSFER_CARD_RESOURCE,
					"from": Catalog.CARD_REF_SELECTED_CARD,
					"to": Catalog.CARD_REF_ABILITY_SOURCE,
					"amount": 1,
					"resource": Catalog.RESOURCE_KI,
					"fallback_resource": Catalog.RESOURCE_POWERS,
				}],
			}],
		}],
	}]
	var instance_id := StringName(source.get("instance_id", &""))
	var state := State.new(
		board,
		[source],
		[_make_plain_card(&"敌方占位手牌", StringName("native_transfer_hand_%s" % ("ki" if use_ki else "powers")), Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		state,
		0,
		4,
		instance_id,
		"Resource transfer prefers ki" if use_ki else "Resource transfer falls back to powers and preserves zero-exile ordering"
	)


func _check_transfer_skips_special_negative_fixture(kernel: Object) -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(
		_make_plain_card(&"不可吸取供体", &"native_transfer_negative", Rules.OPPONENT_OWNER, [-1, -1, -1, -1]),
		Rules.OPPONENT_OWNER
	)
	var valid_donor: Dictionary = _make_plain_card(
		&"顺延供体",
		&"native_transfer_next_donor",
		Rules.OPPONENT_OWNER,
		[1, 1, 1, 1]
	)
	valid_donor["ki"] = 1
	board[1] = _slot(valid_donor, Rules.OPPONENT_OWNER)
	var source: Dictionary = _make_plain_card(
		&"跳过不可吸取牌",
		&"native_transfer_skip_source",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	source["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{
				"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [Catalog.CARD_ZONE_BOARD],
					"conditions": [
						{"type": Catalog.CONDITION_SELECTED_CARD_IS_ENEMY},
						{
							"type": Catalog.CONDITION_SELECTED_CARD_CAN_TRANSFER_RESOURCE,
							"amount": 1,
							"resource": Catalog.RESOURCE_KI,
							"fallback_resource": Catalog.RESOURCE_POWERS,
						},
					],
					"limit": 1,
				},
				"actions": [{
					"type": Catalog.ACTION_TRANSFER_CARD_RESOURCE,
					"from": Catalog.CARD_REF_SELECTED_CARD,
					"to": Catalog.CARD_REF_ABILITY_SOURCE,
					"amount": 1,
					"resource": Catalog.RESOURCE_KI,
					"fallback_resource": Catalog.RESOURCE_POWERS,
				}],
			}],
		}],
	}]
	var state := State.new(
		board,
		[source],
		[_make_plain_card(&"敌方占位手牌", &"native_transfer_skip_hand", Rules.OPPONENT_OWNER, [1, 1, 1, 1])],
		Rules.PLAYER_OWNER
	)
	_check_transition_parity(
		kernel,
		state,
		0,
		4,
		&"native_transfer_skip_source",
		"Resource selector skips a four-sided -1 card and locks the next legal donor"
	)


func _check_outside_hand_exile_fixture(kernel: Object, exile_enemy_hand: bool) -> void:
	var board: Array = Rules.empty_board()
	var listener: Dictionary = _make_plain_card(
		&"手牌外移除监听",
		StringName("native_outside_listener_%s" % ("enemy" if exile_enemy_hand else "ally")),
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	listener["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.CARD_BEFORE_EXILED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_OUTSIDE_SOURCE_OWNER_HAND}],
			"actions": [{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1}],
		}],
	}]
	board[8] = _slot(listener, Rules.PLAYER_OWNER)
	var source: Dictionary = _make_plain_card(
		&"移除手牌来源",
		StringName("native_outside_source_%s" % ("enemy" if exile_enemy_hand else "ally")),
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	source["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{
				"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [Catalog.CARD_ZONE_HAND],
					"conditions": [{
						"type": (
							Catalog.CONDITION_SELECTED_CARD_IS_ENEMY
							if exile_enemy_hand
							else Catalog.CONDITION_SELECTED_CARD_IS_ALLY
						),
					}],
					"limit": 1,
				},
				"actions": [{"type": Catalog.ACTION_EXILE_CARD, "card": Catalog.CARD_REF_SELECTED_CARD}],
			}],
		}],
	}]
	var source_id := StringName(source.get("instance_id", &""))
	var ally_hand_card := _make_plain_card(
		&"己方手牌移除目标",
		StringName("native_outside_ally_target_%s" % ("enemy" if exile_enemy_hand else "ally")),
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	var enemy_hand_card := _make_plain_card(
		&"敌方手牌移除目标",
		StringName("native_outside_enemy_target_%s" % ("enemy" if exile_enemy_hand else "ally")),
		Rules.OPPONENT_OWNER,
		[1, 1, 1, 1]
	)
	var state := State.new(
		board,
		[source, ally_hand_card],
		[enemy_hand_card],
		Rules.PLAYER_OWNER,
		0,
		[_make_plain_card(&"手牌外移除后抽牌", StringName("native_outside_draw_%s" % ("enemy" if exile_enemy_hand else "ally")), Rules.PLAYER_OWNER, [1, 1, 1, 1])]
	)
	_check_transition_parity(
		kernel,
		state,
		0,
		4,
		source_id,
		"Enemy hand exile counts as outside the listener owner's hand" if exile_enemy_hand else "Own hand exile does not count as outside the listener owner's hand"
	)


func _test_attack_modifier_transition_parity(kernel: Object) -> void:
	var enemy_hand: Array = [
		_make_plain_card(&"修正器敌手", &"native_modifier_enemy_hand", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
	]

	var requires_board: Array = Rules.empty_board()
	requires_board[1] = _slot(
		_make_plain_card(&"孤立目标", &"native_requires_target", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		Rules.OPPONENT_OWNER
	)
	var requires_source: Dictionary = _make_modifier_card(
		&"需要友方攻方",
		&"native_requires_source",
		Rules.PLAYER_OWNER,
		[5, 5, 5, 5],
		[{"type": Catalog.MODIFIER_ATTACK_REQUIRES_OTHER_ALLY}]
	)
	_check_modifier_transition(
		kernel,
		State.new(requires_board, [requires_source], enemy_hand.duplicate(true), Rules.PLAYER_OWNER),
		4,
		&"native_requires_source",
		[],
		"Other-ally requirement blocks an isolated attacker"
	)

	var minimum_board: Array = Rules.empty_board()
	minimum_board[8] = _slot(
		_make_plain_card(&"所需友方", &"native_minimum_ally", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
		Rules.PLAYER_OWNER
	)
	minimum_board[5] = _slot(
		_make_plain_card(&"最小防守目标", &"native_minimum_target", Rules.OPPONENT_OWNER, [1, 1, 1, 9]),
		Rules.OPPONENT_OWNER
	)
	var minimum_source: Dictionary = _make_modifier_card(
		&"取最小防守攻方",
		&"native_minimum_source",
		Rules.PLAYER_OWNER,
		[2, 2, 2, 2],
		[
			{"type": Catalog.MODIFIER_ATTACK_REQUIRES_OTHER_ALLY},
			{"type": Catalog.MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE},
		]
	)
	_check_modifier_transition(
		kernel,
		State.new(minimum_board, [minimum_source], enemy_hand.duplicate(true), Rules.PLAYER_OWNER),
		4,
		&"native_minimum_source",
		[5],
		"Other-ally and minimum-defense modifiers combine"
	)

	var lost_ally_board: Array = Rules.empty_board()
	lost_ally_board[1] = _slot(
		_make_plain_card(&"失友目标", &"native_lost_ally_target", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		Rules.OPPONENT_OWNER
	)
	var departing_ally: Dictionary = _make_plain_card(
		&"受击时离场友方",
		&"native_departing_ally",
		Rules.PLAYER_OWNER,
		[1, 1, 1, 1]
	)
	departing_ally["active_abilities"] = [{
		"retained_on_flip": true,
		"triggers": [{
			"event": Catalog.CARD_BE_ATTACKED,
			"conditions": [],
			"actions": [{"type": Catalog.ACTION_EXILE_SELF}],
		}],
	}]
	lost_ally_board[8] = _slot(departing_ally, Rules.PLAYER_OWNER)
	var lost_ally_source: Dictionary = _make_modifier_card(
		&"失友攻方",
		&"native_lost_ally_source",
		Rules.PLAYER_OWNER,
		[5, 5, 5, 5],
		[{"type": Catalog.MODIFIER_ATTACK_REQUIRES_OTHER_ALLY}]
	)
	_check_modifier_transition(
		kernel,
		State.new(lost_ally_board, [lost_ally_source], enemy_hand.duplicate(true), Rules.PLAYER_OWNER),
		4,
		&"native_lost_ally_source",
		[],
		"Other-ally requirement is revalidated after CARD_BE_ATTACKED"
	)

	var override_board: Array = Rules.empty_board()
	var override_target: Dictionary = _make_modifier_card(
		&"覆写防守目标",
		&"native_override_target",
		Rules.OPPONENT_OWNER,
		[1, 1, 1, 1],
		[{"type": Catalog.MODIFIER_DEFENDING_POWER_OVERRIDE, "value": 7}]
	)
	override_board[5] = _slot(override_target, Rules.OPPONENT_OWNER)
	_check_modifier_transition(
		kernel,
		State.new(
			override_board,
			[_make_plain_card(&"覆写攻方", &"native_override_source", Rules.PLAYER_OWNER, [5, 5, 5, 5])],
			enemy_hand.duplicate(true),
			Rules.PLAYER_OWNER
		),
		4,
		&"native_override_source",
		[],
		"Defending-power override uses the generic comparison path"
	)

	var ally_range_board: Array = Rules.empty_board()
	ally_range_board[4] = _slot(
		_make_plain_card(&"隔位友方", &"native_range_ally", Rules.PLAYER_OWNER, [9, 9, 9, 9]),
		Rules.PLAYER_OWNER
	)
	ally_range_board[1] = _slot(
		_make_plain_card(&"隔友方目标", &"native_range_ally_target", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		Rules.OPPONENT_OWNER
	)
	var ally_range_source: Dictionary = _make_modifier_card(
		&"隔友方攻方",
		&"native_range_ally_source",
		Rules.PLAYER_OWNER,
		[5, 1, 1, 1],
		[{
			"type": Catalog.MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO,
			"allow_intervening_ally": true,
		}]
	)
	_check_modifier_transition(
		kernel,
		State.new(ally_range_board, [ally_range_source], enemy_hand.duplicate(true), Rules.PLAYER_OWNER),
		7,
		&"native_range_ally_source",
		[1],
		"Range-two modifier permits an intervening ally"
	)

	var enemy_range_board: Array = Rules.empty_board()
	enemy_range_board[4] = _slot(
		_make_plain_card(&"隔位敌方", &"native_range_enemy", Rules.OPPONENT_OWNER, [9, 9, 9, 9]),
		Rules.OPPONENT_OWNER
	)
	enemy_range_board[1] = _slot(
		_make_plain_card(&"隔敌方目标", &"native_range_enemy_target", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		Rules.OPPONENT_OWNER
	)
	var enemy_range_source: Dictionary = _make_modifier_card(
		&"隔敌方攻方",
		&"native_range_enemy_source",
		Rules.PLAYER_OWNER,
		[5, 1, 1, 1],
		[{
			"type": Catalog.MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO,
			"allow_intervening_ally": false,
			"allow_intervening_enemy": true,
		}]
	)
	_check_modifier_transition(
		kernel,
		State.new(enemy_range_board, [enemy_range_source], enemy_hand.duplicate(true), Rules.PLAYER_OWNER),
		7,
		&"native_range_enemy_source",
		[1],
		"Range-two modifier permits an intervening enemy"
	)

	var reversed_board: Array = Rules.empty_board()
	reversed_board[1] = _slot(
		_make_plain_card(&"反转高点目标", &"native_reversed_target", Rules.OPPONENT_OWNER, [9, 9, 9, 9]),
		Rules.OPPONENT_OWNER
	)
	var reversed_source: Dictionary = _make_modifier_card(
		&"反转攻方",
		&"native_reversed_source",
		Rules.PLAYER_OWNER,
		[5, 5, 5, 5],
		[{"type": Catalog.MODIFIER_POWER_COMPARISON_REVERSED}]
	)
	_check_modifier_transition(
		kernel,
		State.new(reversed_board, [reversed_source], enemy_hand.duplicate(true), Rules.PLAYER_OWNER),
		4,
		&"native_reversed_source",
		[1],
		"Reversed comparison attacks a larger ordinary power"
	)

	var negative_defender_board: Array = Rules.empty_board()
	negative_defender_board[1] = _slot(
		_make_plain_card(&"负点目标", &"native_negative_defender", Rules.OPPONENT_OWNER, [-1, -1, -1, -1]),
		Rules.OPPONENT_OWNER
	)
	_check_modifier_transition(
		kernel,
		State.new(negative_defender_board, [reversed_source.duplicate(true)], enemy_hand.duplicate(true), Rules.PLAYER_OWNER),
		4,
		&"native_reversed_source",
		[1],
		"Reversal cannot protect a four-sided negative defender"
	)

	var negative_attacker_board: Array = Rules.empty_board()
	negative_attacker_board[1] = _slot(
		_make_plain_card(&"普通目标", &"native_negative_target", Rules.OPPONENT_OWNER, [9, 9, 9, 9]),
		Rules.OPPONENT_OWNER
	)
	var negative_attacker: Dictionary = _make_modifier_card(
		&"负点攻方",
		&"native_negative_source",
		Rules.PLAYER_OWNER,
		[-1, -1, -1, -1],
		[{"type": Catalog.MODIFIER_POWER_COMPARISON_REVERSED}]
	)
	_check_modifier_transition(
		kernel,
		State.new(negative_attacker_board, [negative_attacker], enemy_hand.duplicate(true), Rules.PLAYER_OWNER),
		4,
		&"native_negative_source",
		[],
		"Reversal cannot make a four-sided negative attacker win"
	)

	var redirect_board: Array = Rules.empty_board()
	var redirect_source: Dictionary = _make_modifier_card(
		&"相邻改向来源",
		&"native_redirect_source",
		Rules.OPPONENT_OWNER,
		[9, 9, 9, 9],
		[{"type": Catalog.MODIFIER_ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES}]
	)
	redirect_source["active_abilities"][0]["triggers"] = [{
		"event": Catalog.TRIGGER_CARD_AFTER_ATTACK,
		"conditions": [{"type": Catalog.CONDITION_ATTACKER_CARD_IS_ENEMY}],
		"actions": [{"type": Catalog.ACTION_REMOVE_THIS_ABILITY}],
	}]
	redirect_board[1] = _slot(redirect_source, Rules.OPPONENT_OWNER)
	redirect_board[3] = _slot(
		_make_plain_card(&"改向友方目标", &"native_redirect_ally", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
		Rules.PLAYER_OWNER
	)
	_check_modifier_transition(
		kernel,
		State.new(
			redirect_board,
			[_make_plain_card(&"改向攻方", &"native_redirect_attacker", Rules.PLAYER_OWNER, [1, 1, 1, 5])],
			enemy_hand.duplicate(true),
			Rules.PLAYER_OWNER
		),
		4,
		&"native_redirect_attacker",
		[3],
		"Adjacent summon redirect attacks an ally and removes its source ability"
	)

	var invalidated_redirect_board: Array = Rules.empty_board()
	var invalidated_source: Dictionary = _make_modifier_card(
		&"失效改向来源",
		&"native_invalidated_redirect_source",
		Rules.OPPONENT_OWNER,
		[1, 1, 1, 1],
		[{"type": Catalog.MODIFIER_ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES}]
	)
	invalidated_source["active_abilities"][0]["triggers"] = [{
		"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
		"conditions": [],
		"actions": [{"type": Catalog.ACTION_REMOVE_THIS_ABILITY}],
	}]
	invalidated_redirect_board[1] = _slot(invalidated_source, Rules.OPPONENT_OWNER)
	invalidated_redirect_board[3] = _slot(
		_make_plain_card(&"不再改向的友方", &"native_invalidated_redirect_ally", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
		Rules.PLAYER_OWNER
	)
	_check_modifier_transition(
		kernel,
		State.new(
			invalidated_redirect_board,
			[_make_plain_card(&"失效改向攻方", &"native_invalidated_redirect_attacker", Rules.PLAYER_OWNER, [5, 1, 1, 1])],
			enemy_hand.duplicate(true),
			Rules.PLAYER_OWNER
		),
		4,
		&"native_invalidated_redirect_attacker",
		[1],
		"Summon redirect revalidates that the original source ability remains enabled"
	)

	var first_legal_board: Array = Rules.empty_board()
	first_legal_board[0] = _slot(
		_make_plain_card(&"首个斜向目标", &"native_first_diagonal", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		Rules.OPPONENT_OWNER
	)
	first_legal_board[1] = _slot(
		_make_plain_card(&"后续目标", &"native_first_later", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		Rules.OPPONENT_OWNER
	)
	var first_legal_source: Dictionary = _make_modifier_card(
		&"首个合法攻方",
		&"native_first_source",
		Rules.PLAYER_OWNER,
		[5, 5, 5, 5],
		[
			{"type": Catalog.MODIFIER_UNLIMITED_ATTACK_RANGE},
			{"type": Catalog.MODIFIER_NON_ORTHOGONAL_ATTACK_ANY_AXIS},
			{"type": Catalog.MODIFIER_STANDARD_ATTACK_FIRST_LEGAL_TARGET},
		]
	)
	_check_modifier_transition(
		kernel,
		State.new(first_legal_board, [first_legal_source], enemy_hand.duplicate(true), Rules.PLAYER_OWNER),
		4,
		&"native_first_source",
		[0],
		"Unlimited non-orthogonal attack locks the first row-major legal target"
	)

	var removed_first_board: Array = Rules.empty_board()
	var removed_first_target: Dictionary = _make_plain_card(
		&"移除首目标",
		&"native_removed_first_target",
		Rules.OPPONENT_OWNER,
		[1, 1, 1, 1]
	)
	removed_first_target["active_abilities"] = [{
		"retained_on_flip": true,
		"triggers": [{
			"event": Catalog.CARD_BE_ATTACKED,
			"conditions": [{"type": Catalog.CONDITION_ATTACKED_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_EXILE_SELF}],
		}],
	}]
	removed_first_board[0] = _slot(removed_first_target, Rules.OPPONENT_OWNER)
	removed_first_board[1] = _slot(
		_make_plain_card(&"不顺延目标", &"native_no_fallback_target", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		Rules.OPPONENT_OWNER
	)
	_check_modifier_transition(
		kernel,
		State.new(removed_first_board, [first_legal_source.duplicate(true)], enemy_hand.duplicate(true), Rules.PLAYER_OWNER),
		4,
		&"native_first_source",
		[],
		"First-legal attack does not fall through after its locked target is exiled"
	)

	var orthogonal_only_source: Dictionary = _make_modifier_card(
		&"仅无限距离攻方",
		&"native_orthogonal_only_source",
		Rules.PLAYER_OWNER,
		[5, 5, 5, 5],
		[{"type": Catalog.MODIFIER_UNLIMITED_ATTACK_RANGE}]
	)
	var diagonal_only_board: Array = Rules.empty_board()
	diagonal_only_board[0] = _slot(
		_make_plain_card(&"不可斜攻目标", &"native_diagonal_only_target", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		Rules.OPPONENT_OWNER
	)
	_check_modifier_transition(
		kernel,
		State.new(diagonal_only_board, [orthogonal_only_source], enemy_hand.duplicate(true), Rules.PLAYER_OWNER),
		4,
		&"native_orthogonal_only_source",
		[],
		"Unlimited range alone does not permit a non-orthogonal attack"
	)

	var self_all_board: Array = Rules.empty_board()
	self_all_board[1] = _slot(
		_make_plain_card(&"不分敌我敌方", &"native_self_all_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		Rules.OPPONENT_OWNER
	)
	self_all_board[3] = _slot(
		_make_plain_card(&"不分敌我友方", &"native_self_all_ally", Rules.PLAYER_OWNER, [1, 1, 1, 1]),
		Rules.PLAYER_OWNER
	)
	var self_all_source: Dictionary = _make_modifier_card(
		&"自身不分敌我攻方",
		&"native_self_all_source",
		Rules.PLAYER_OWNER,
		[5, 5, 5, 5],
		[{"type": Catalog.MODIFIER_SELF_ATTACKS_ALL}]
	)
	_check_modifier_transition(
		kernel,
		State.new(self_all_board, [self_all_source], enemy_hand.duplicate(true), Rules.PLAYER_OWNER),
		4,
		&"native_self_all_source",
		[1, 3],
		"Self-attacks-all flips both enemy and allied targets"
	)

	var lock_board: Array = Rules.empty_board()
	lock_board[0] = _slot(
		_make_modifier_card(
			&"回合攻击锁",
			&"native_turn_lock_source",
			Rules.PLAYER_OWNER,
			[1, 1, 1, 1],
			[{"type": Catalog.MODIFIER_ENEMY_CANNOT_ATTACK_DURING_OWNER_TURN}]
		),
		Rules.PLAYER_OWNER
	)
	lock_board[1] = _slot(
		_make_plain_card(&"锁定规则敌方", &"native_turn_lock_target", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		Rules.OPPONENT_OWNER
	)
	_check_modifier_transition(
		kernel,
		State.new(
			lock_board,
			[_make_plain_card(&"本方正常攻方", &"native_turn_lock_attacker", Rules.PLAYER_OWNER, [5, 5, 5, 5])],
			enemy_hand.duplicate(true),
			Rules.PLAYER_OWNER
		),
		4,
		&"native_turn_lock_attacker",
		[1],
		"Owner-turn attack lock does not prohibit the active owner's own attack"
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
	if actual.get("exiles", []) != expected.get("exiles", []):
		print("NATIVE_EXILE_DIFFERENCE label=%s expected=%s actual=%s" % [
			label,
			expected.get("exiles", []),
			actual.get("exiles", []),
		])
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


func _check_modifier_transition(
	kernel: Object,
	state: State,
	target_cell: int,
	instance_id: StringName,
	expected_captures: Array,
	label: String
) -> void:
	var expected: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, target_cell, instance_id)
	)
	_check(bool(expected.get("valid", false)), "%s oracle transition is valid before parity" % label)
	_check(
		expected.get("captures", []) == expected_captures,
		"%s exercises the intended captures" % label
	)
	_check_transition_parity(kernel, state, 0, target_cell, instance_id, label)


func _check_selector_exile_order(
	kernel: Object,
	state: State,
	hand_index: int,
	instance_id: StringName,
	expected_instance_ids: Array,
	label: String,
	target_cell: int = 4
) -> void:
	var expected: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(hand_index, target_cell, instance_id)
	)
	var actual_ids: Array[StringName] = []
	for event_value: Variant in expected.get("events", []):
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == &"card_exiled"
		):
			actual_ids.append(StringName((event_value as Dictionary).get("instance_id", &"")))
	_check(actual_ids == expected_instance_ids, "%s exercises the intended selected order" % label)
	_check_transition_parity(kernel, state, hand_index, target_cell, instance_id, label)


func _check_power_change_fixture(
	kernel: Object,
	state: State,
	instance_id: StringName,
	expected_power_changes: int,
	expected_zero_exiles: int,
	expected_batch_count: int,
	label: String,
	target_cell: int = 4
) -> void:
	var expected: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, target_cell, instance_id)
	)
	var power_count: int = 0
	var zero_exile_count: int = 0
	var batch_ids: Dictionary = {}
	var first_power_index: int = -1
	var first_zero_exile_index: int = -1
	var events: Array = expected.get("events", []) as Array
	for event_index: int in range(events.size()):
		var event: Dictionary = events[event_index] as Dictionary
		var event_type := StringName(event.get("type", &""))
		if event_type == &"powers_changed":
			power_count += 1
			if first_power_index < 0:
				first_power_index = event_index
			batch_ids[StringName(event.get("power_change_batch_id", &""))] = true
		elif (
			event_type == &"card_exiled"
			and StringName(event.get("exile_reason", &"")) == &"power_reached_zero"
		):
			zero_exile_count += 1
			if first_zero_exile_index < 0:
				first_zero_exile_index = event_index
			batch_ids[StringName(event.get("power_change_batch_id", &""))] = true
	_check(power_count == expected_power_changes, "%s exercises the intended power changes" % label)
	_check(zero_exile_count == expected_zero_exiles, "%s exercises the intended zero-power exiles" % label)
	_check(batch_ids.size() == expected_batch_count and not batch_ids.has(&""), "%s assigns the intended power batches" % label)
	if expected_zero_exiles > 0:
		_check(first_power_index >= 0 and first_power_index < first_zero_exile_index, "%s changes powers before exile" % label)
	_check_transition_parity(kernel, state, 0, target_cell, instance_id, label)


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
	_check(
		not result.has("payload")
		and (result.get("events", []) as Array).is_empty()
		and (result.get("captures", []) as Array).is_empty()
		and (result.get("exiles", []) as Array).is_empty(),
		"%s rejection exposes no partial native branch" % label
	)


func _first_event_index(events: Array, event_type: StringName) -> int:
	for event_index: int in range(events.size()):
		var event_value: Variant = events[event_index]
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
		):
			return event_index
	return -1


func _count_event_type(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for event_value: Variant in events:
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
		):
			count += 1
	return count


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


func _make_selector_source(
	instance_id: StringName,
	selector: Dictionary,
	actions: Array
) -> Dictionary:
	return _make_after_summoned_card(
		instance_id,
		{
			"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
			"selector": selector,
			"actions": actions,
		}
	)


func _make_modifier_card(
	card_id: StringName,
	instance_id: StringName,
	owner_id: int,
	powers: Array[int],
	modifiers: Array
) -> Dictionary:
	var card: Dictionary = _make_plain_card(card_id, instance_id, owner_id, powers)
	card["active_abilities"] = [{
		"retained_on_flip": false,
		"modifiers": modifiers.duplicate(true),
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


func _make_suppressed_card(
	instance_id: StringName,
	owner_id: int,
	active_abilities: Array,
	batches: Array
) -> Dictionary:
	var card: Dictionary = _make_plain_card(
		&"原生压制夹具",
		instance_id,
		owner_id,
		[1, 1, 1, 1]
	)
	card["active_abilities"] = active_abilities.duplicate(true)
	card["temporary_suppression_batches"] = batches.duplicate(true)
	return card


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	print("CHECK_FAILED: %s" % message)
