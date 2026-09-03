extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Abilities = preload("res://scripts/duel_abilities.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const CompactState = preload("res://scripts/duel_compact_state.gd")
const EnemyManifest = preload("res://tests/benchmarks/enemy_ai_benchmark_manifest.gd")
const EnemyStateFactory = preload("res://tests/benchmarks/enemy_ai_benchmark_state_factory.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Search = preload("res://scripts/duel_search.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

var _checks: int = 0
var _failures: int = 0
var _native_cancel_checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_live_catalog_compiles_natively()
	_test_every_catalog_card_hand_play_runs_in_production()
	_test_every_catalog_activation_runs_in_production()
	_test_native_whole_tree_search_is_deterministic()
	_test_native_depth_modes_match_fixed_and_iterative_search()
	_test_native_search_solves_forced_terminal_choice()
	_test_native_search_node_budget_keeps_only_complete_depths()
	_test_production_search_routes_to_native_whole_tree()
	_test_native_search_honors_cancellation()
	_test_native_search_keeps_same_turn_principal_actions()
	_test_native_search_action_order_is_stable()
	_test_native_fast_legal_action_count_matches_generated_actions()
	_test_native_search_diagnostics_contract()
	_test_native_search_releases_temporary_dictionaries()
	if _failures == 0:
		print("NATIVE_PRODUCTION_RULES_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("NATIVE_PRODUCTION_RULES_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _test_live_catalog_compiles_natively() -> void:
	var catalog_cards: Array = []
	for card_index: int in range(Catalog.ALL_CARD_IDS.size()):
		catalog_cards.append(Catalog.create_instance(
			Catalog.ALL_CARD_IDS[card_index],
			Rules.PLAYER_OWNER,
			StringName("production_catalog_audit_%d" % card_index)
		))
	var state := State.new(Rules.empty_board(), [], [], Rules.PLAYER_OWNER)
	state.removed_cards[Rules.PLAYER_OWNER] = catalog_cards
	var compact := CompactState.new()
	_check(compact.capture_state(state), "Complete live catalog crosses the compact boundary")
	if not compact.is_structurally_valid():
		return
	var kernel: Object = ClassDB.instantiate(&"DuelNativeCompactKernel")
	_check(kernel != null, "Native production kernel is registered")
	if kernel == null:
		return
	_check(
		bool(kernel.call("load_compact_payload", compact.to_variant_payload())),
		"Complete live catalog loads into the native kernel"
	)
	var layout: Dictionary = kernel.call("inspect_layout") as Dictionary
	_check(
		int(layout.get("invalid_compiled_ability_count", -1)) == 0,
		"Every live catalog ability uses supported native declarations"
	)
	_check(
		int(layout.get("invalid_compiled_ability_set_count", -1)) == 0,
		"Every live catalog ability set compiles natively"
	)


func _test_native_depth_modes_match_fixed_and_iterative_search() -> void:
	var state: State = _make_search_state()
	var compact := CompactState.new()
	_check(compact.capture_state(state), "Search depth fixture crosses the compact boundary")
	if not compact.is_structurally_valid():
		return
	var kernel: Object = ClassDB.instantiate(&"DuelNativeCompactKernel")
	_check(kernel != null, "Search depth fixture creates the native kernel")
	if kernel == null:
		return
	_check(bool(kernel.call("load_compact_payload", compact.to_variant_payload())), "Search depth fixture loads into the native kernel")
	var fixed: Dictionary = kernel.call(
		"search_fixed_depth", Rules.OPPONENT_OWNER, 1, &"self_turn"
	) as Dictionary
	var iterative: Dictionary = kernel.call(
		"search_iterative_depth",
		Rules.OPPONENT_OWNER,
		1,
		0,
		0,
		0,
		&"self_turn",
		Callable()
	) as Dictionary
	_check(bool(fixed.get("valid", false)) and bool(iterative.get("valid", false)), "Fixed and iterative self-turn searches both complete")
	_check(int(fixed.get("owner_turn_boundaries", 0)) == 1, "Fixed self-turn depth one uses one owner-turn boundary")
	_check(int(iterative.get("owner_turn_boundaries", 0)) == 1, "Iterative self-turn depth one uses one owner-turn boundary")
	_check(int(fixed.get("score", 0)) == int(iterative.get("score", 1)), "Fixed and iterative self-turn searches agree on score")
	_check((fixed.get("action", {}) as Dictionary) == (iterative.get("action", {}) as Dictionary), "Fixed and iterative self-turn searches agree on action")


func _test_every_catalog_card_hand_play_runs_in_production() -> void:
	for card_id: StringName in Catalog.ALL_CARD_IDS:
		var prefix := String(card_id).to_snake_case()
		var state := State.new(
			Rules.empty_board(),
			[Catalog.create_instance(card_id, Rules.PLAYER_OWNER, StringName("native_play_%s" % prefix))],
			[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, StringName("native_enemy_hand_%s" % prefix))],
			Rules.PLAYER_OWNER,
			0,
			[
				Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, StringName("native_deck_a_%s" % prefix)),
				Catalog.create_instance(&"TuNaShu1", Rules.PLAYER_OWNER, StringName("native_deck_b_%s" % prefix)),
			],
			[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, StringName("native_enemy_deck_%s" % prefix))]
		)
		var transition: Dictionary = _assert_production_transition(
			state,
			Action.make_play(0, 4, StringName("native_play_%s" % prefix)),
			"catalog play %s" % card_id
		)
		if not bool(transition.get("valid", false)):
			continue
		var next_state: State = transition.get("state") as State
		_check(
			not _zone_has_instance(
				next_state.get_hand(Rules.PLAYER_OWNER),
				StringName("native_play_%s" % prefix)
			),
			"catalog play %s consumes its exact hand instance" % card_id
		)


func _test_every_catalog_activation_runs_in_production() -> void:
	var activation_declarations: int = 0
	var covered_declarations: Dictionary = {}
	for card_id: StringName in Catalog.ALL_CARD_IDS:
		var prefix := String(card_id).to_snake_case()
		var board: Array = Rules.empty_board()
		var source: Dictionary = Catalog.create_instance(
			card_id,
			Rules.PLAYER_OWNER,
			StringName("native_activation_%s" % prefix)
		)
		source["ki"] = maxi(int(source.get("ki", 0)), 3)
		board[4] = {"owner": Rules.PLAYER_OWNER, "card": source}
		board[1] = {
			"owner": Rules.PLAYER_OWNER,
			"card": Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, StringName("native_ally_%s" % prefix)),
		}
		board[3] = {
			"owner": Rules.OPPONENT_OWNER,
			"card": Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, StringName("native_enemy_%s" % prefix)),
		}
		var state := State.new(
			board,
			[Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, StringName("native_player_hand_%s" % prefix))],
			[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, StringName("native_opponent_hand_%s" % prefix))],
			Rules.PLAYER_OWNER,
			0,
			[Catalog.create_instance(&"TuNaShu1", Rules.PLAYER_OWNER, StringName("native_player_deck_%s" % prefix))],
			[Catalog.create_instance(&"TuNaShu1", Rules.OPPONENT_OWNER, StringName("native_opponent_deck_%s" % prefix))]
		)
		state.enabled_effect_gates_by_owner[Rules.PLAYER_OWNER] = [
			Rules.EFFECT_GATE_SELF_CASTRATION,
		]
		var declared: Array[Dictionary] = Abilities.get_activate_abilities(
			source,
			state.get_enabled_effect_gates(Rules.PLAYER_OWNER)
		)
		activation_declarations += declared.size()
		for action: Action in Simulator.get_legal_actions(state):
			if action.action_type != Action.TYPE_ACTIVATE or action.source_index != 4:
				continue
			covered_declarations["%s|%d" % [card_id, action.activation_index]] = true
			_assert_production_transition(
				state,
				action,
				"catalog activation %s %s" % [card_id, action.canonical_key()]
			)
	_check(activation_declarations > 0, "The live catalog exposes activation declarations")
	_check(
		covered_declarations.size() == activation_declarations,
		"The complete fixture reaches every live activation declaration"
	)


func _make_search_state() -> State:
	return State.new(
		Rules.empty_board(),
		[
			Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"native_search_player_a"),
			Catalog.create_instance(&"TuNaShu1", Rules.PLAYER_OWNER, &"native_search_player_b"),
		],
		[
			Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"native_search_enemy_a"),
			Catalog.create_instance(&"TuNaShu1", Rules.OPPONENT_OWNER, &"native_search_enemy_b"),
		],
		Rules.OPPONENT_OWNER
	)


func _test_native_whole_tree_search_is_deterministic() -> void:
	var state: State = _make_search_state()
	var first: Dictionary = Search.find_best_action_iterative_native(
		state,
		Rules.OPPONENT_OWNER,
		{"max_depth": 1}
	)
	var repeated: Dictionary = Search.find_best_action_iterative_native(
		state,
		Rules.OPPONENT_OWNER,
		{"max_depth": 1}
	)
	var first_action: Action = first.get("action") as Action
	var repeated_action: Action = repeated.get("action") as Action
	_check(first_action != null and first_action.action_type != &"", "Native whole-tree search returns an action")
	_check(
		first_action.canonical_key() == repeated_action.canonical_key(),
		"Repeated native searches choose the same canonical action"
	)
	_check(int(first.get("score", 0)) == int(repeated.get("score", 1)), "Repeated native searches return the same score")
	_check(int(first.get("completed_depth", 0)) == 1, "Native whole-tree search reports complete-round depth one")
	_check(Simulator.is_action_legal(state, first_action), "Native whole-tree search returns a legal action")


func _test_native_search_solves_forced_terminal_choice() -> void:
	var board: Array = Rules.empty_board()
	for cell_index: int in range(8):
		var owner_id: int = Rules.PLAYER_OWNER if cell_index < 4 else Rules.OPPONENT_OWNER
		board[cell_index] = {
			"owner": owner_id,
			"card": Catalog.create_instance(
				&"TaiZuChangQuan",
				owner_id,
				StringName("forced_board_%d" % cell_index)
			),
		}
	var state := State.new(
		board,
		[],
		[Catalog.create_instance(
			&"TaiZuChangQuan",
			Rules.OPPONENT_OWNER,
			&"forced_winner"
		)],
		Rules.OPPONENT_OWNER
	)
	var result: Dictionary = Search.find_best_action_iterative_native(
		state,
		Rules.OPPONENT_OWNER,
		{"max_depth": 1}
	)
	var action: Action = result.get("action") as Action
	_check(action != null, "Forced terminal search returns its only action")
	if action == null:
		return
	_check(action.source_index == 0 and action.target_index == 8, "Forced terminal search fills the only empty cell")
	_check(action.source_instance_id == &"forced_winner", "Forced terminal search preserves exact source identity")
	_check(int(result.get("score", 0)) == 1_000_099, "Forced terminal win has the documented terminal score")


func _test_native_search_node_budget_keeps_only_complete_depths() -> void:
	var ordinary: Dictionary = Search.find_best_action_iterative_native(
		_make_search_state(),
		Rules.OPPONENT_OWNER,
		{"max_nodes": 1}
	)
	_check(not bool(ordinary.get("has_completed_depth", true)), "Native node interruption publishes no partial depth")
	var protected: Dictionary = Search.find_best_action_iterative_native(
		_make_search_state(),
		Rules.OPPONENT_OWNER,
		{"max_nodes": 1, "min_completed_depth": 1}
	)
	_check(bool(protected.get("has_completed_depth", false)), "Native minimum-depth guard completes depth one")
	_check(int(protected.get("completed_depth", 0)) == 1, "Native minimum-depth guard stops after complete depth one")
	_check(bool(protected.get("minimum_depth_guard_used", false)), "Native minimum-depth overrun is reported")


func _test_production_search_routes_to_native_whole_tree() -> void:
	var production: Dictionary = Search.find_best_action_iterative(
		_make_search_state(),
		Rules.OPPONENT_OWNER,
		{"max_depth": 1}
	)
	var explicit_native: Dictionary = Search.find_best_action_iterative_native(
		_make_search_state(),
		Rules.OPPONENT_OWNER,
		{"max_depth": 1}
	)
	var production_action: Action = production.get("action") as Action
	var native_action: Action = explicit_native.get("action") as Action
	_check(bool(production.get("has_completed_depth", false)), "Production search completes a native whole-tree depth")
	_check(production.has("depth_snapshots"), "Production search exposes native depth snapshots")
	_check(
		production_action.canonical_key() == native_action.canonical_key(),
		"Production search chooses the explicit native whole-tree action"
	)
	_check(int(production.get("score", 0)) == int(explicit_native.get("score", 1)), "Production search uses the native whole-tree score")


func _test_native_search_honors_cancellation() -> void:
	_native_cancel_checks = 0
	var cancelled: Dictionary = Search.find_best_action_iterative_native(
		_make_search_state(),
		Rules.OPPONENT_OWNER,
		{"max_depth": 3},
		Callable(self, "_cancel_native_search_after_entry")
	)
	_check(_native_cancel_checks >= 2, "Native whole-tree search polls cancellation inside C++")
	_check(not bool(cancelled.get("has_completed_depth", true)), "Cancelled native search publishes no partial depth")
	_check(StringName(cancelled.get("completion_reason", &"")) == &"cancelled", "Native search reports cancellation")


func _cancel_native_search_after_entry() -> bool:
	_native_cancel_checks += 1
	return _native_cancel_checks >= 2


func _test_native_search_keeps_same_turn_principal_actions() -> void:
	var state: State = _make_search_state()
	# The counter includes the action currently being consumed; two means this
	# action plus one searched continuation in the same owner turn.
	state.extra_card_plays_remaining = 2
	var result: Dictionary = Search.find_best_action_iterative_native(
		state,
		Rules.OPPONENT_OWNER,
		{"max_depth": 1}
	)
	var plan: Array = result.get("turn_plan", []) as Array
	_check(
		plan.size() == 2,
		"Native search preserves both actions from an extra-play owner turn (plan=%d principal=%d)"
		% [plan.size(), (result.get("principal_actions", []) as Array).size()]
	)
	if plan.size() != 2:
		return
	_check(
		int((plan[0] as Dictionary).get("owner_turn_serial", -1))
		== int((plan[1] as Dictionary).get("owner_turn_serial", -2)),
		"Native continuation actions share the searched owner-turn serial"
	)


func _test_native_search_action_order_is_stable() -> void:
	var board: Array = Rules.empty_board()
	var source: Dictionary = Catalog.create_instance(
		&"YouFenLaiYi4", Rules.OPPONENT_OWNER, &"ordering_active"
	)
	source["ki"] = 2
	board[4] = {"owner": Rules.OPPONENT_OWNER, "card": source}
	board[1] = {
		"owner": Rules.OPPONENT_OWNER,
		"card": Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"ordering_ally"),
	}
	board[3] = {
		"owner": Rules.PLAYER_OWNER,
		"card": Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"ordering_enemy"),
	}
	var state := State.new(
		board,
		[],
		[
			Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"ordering_hand_a"),
			Catalog.create_instance(&"TuNaShu1", Rules.OPPONENT_OWNER, &"ordering_hand_b"),
		],
		Rules.OPPONENT_OWNER
	)
	var compact := CompactState.new()
	_check(compact.capture_state(state), "Native action-order fixture crosses the compact boundary")
	if not compact.is_structurally_valid():
		return
	var kernel: Object = ClassDB.instantiate(&"DuelNativeCompactKernel")
	_check(kernel != null, "Native action-order fixture creates the kernel")
	if kernel == null:
		return
	_check(bool(kernel.call("load_compact_payload", compact.to_variant_payload())), "Native action-order fixture loads")
	var ordered: Array = kernel.call(
		"inspect_ordered_search_actions_for_owner", Rules.OPPONENT_OWNER
	) as Array
	var repeated: Array = kernel.call(
		"inspect_ordered_search_actions_for_owner", Rules.OPPONENT_OWNER
	) as Array
	var ordered_keys: Array[String] = []
	var repeated_keys: Array[String] = []
	for action_value: Variant in ordered:
		ordered_keys.append(_native_action_key(action_value as Dictionary))
	for action_value: Variant in repeated:
		repeated_keys.append(_native_action_key(action_value as Dictionary))
	var expected: Array[String] = [
		"activate|4|ordering_active|board_cell|1|1",
		"activate|4|ordering_active|board_cell|3|2",
		"activate|4|ordering_active|board_cell|5|0",
		"activate|4|ordering_active|board_cell|7|0",
		"play|0|ordering_hand_a|board_cell|0|0",
		"play|1|ordering_hand_b|board_cell|0|0",
		"play|0|ordering_hand_a|board_cell|6|0",
		"play|1|ordering_hand_b|board_cell|6|0",
		"play|0|ordering_hand_a|board_cell|2|0",
		"play|1|ordering_hand_b|board_cell|2|0",
		"play|0|ordering_hand_a|board_cell|8|0",
		"play|1|ordering_hand_b|board_cell|8|0",
		"play|0|ordering_hand_a|board_cell|5|0",
		"play|0|ordering_hand_a|board_cell|7|0",
		"play|1|ordering_hand_b|board_cell|5|0",
		"play|1|ordering_hand_b|board_cell|7|0",
	]
	_check(ordered_keys == expected, "Native structural action order stays frozen (actual=%s)" % [ordered_keys])
	_check(repeated_keys == expected, "Repeated native action ordering is deterministic")
	if ordered.size() > 8:
		var preferred: Dictionary = ordered[8] as Dictionary
		var preferred_order: Array = kernel.call(
			"inspect_ordered_search_actions_for_owner",
			Rules.OPPONENT_OWNER,
			preferred
		) as Array
		_check(
			not preferred_order.is_empty()
			and _native_action_key(preferred_order[0] as Dictionary) == _native_action_key(preferred),
			"Exact preferred-action matching outranks structural order"
		)


func _native_action_key(action: Dictionary) -> String:
	return "%s|%d|%s|%s|%d|%d" % [
		StringName(action.get("action_type", &"")),
		int(action.get("source_index", -1)),
		StringName(action.get("source_instance_id", &"")),
		StringName(action.get("target_kind", &"")),
		int(action.get("target_index", -1)),
		int(action.get("activation_index", 0)),
	]


func _test_native_fast_legal_action_count_matches_generated_actions() -> void:
	var matchups: Array[Dictionary] = EnemyManifest.get_matchups_for_mode(&"quick")
	for matchup_index: int in range(mini(matchups.size(), 3)):
		var matchup: Dictionary = matchups[matchup_index]
		var games: Array[Dictionary] = EnemyManifest.expand_matchup(matchup)
		if games.is_empty():
			continue
		var built: Dictionary = EnemyStateFactory.build(games[0], matchup)
		var opening: State = built.get("state") as State
		_assert_native_legal_count_equivalence(opening, "Quick opening %d" % matchup_index)
		var opening_actions: Array[Action] = Simulator.get_legal_actions(opening)
		if not opening_actions.is_empty():
			var transition: Dictionary = Simulator.apply_action(opening, opening_actions[0])
			if bool(transition.get("valid", false)):
				_assert_native_legal_count_equivalence(
					transition.get("state") as State,
					"Quick derived state %d" % matchup_index
				)
		var extra_play: State = opening.duplicate_state()
		extra_play.extra_card_plays_remaining = 1
		_assert_native_legal_count_equivalence(
			extra_play,
			"Quick extra-play state %d" % matchup_index
		)

	var activation_board: Array = Rules.empty_board()
	var multi_activation: Dictionary = Catalog.create_instance(
		&"YouFenLaiYi4", Rules.OPPONENT_OWNER, &"count_multi_activation"
	)
	multi_activation["ki"] = 2
	activation_board[4] = {"owner": Rules.OPPONENT_OWNER, "card": multi_activation}
	activation_board[1] = {
		"owner": Rules.OPPONENT_OWNER,
		"card": Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"count_ally"),
	}
	activation_board[3] = {
		"owner": Rules.PLAYER_OWNER,
		"card": Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"count_enemy"),
	}
	var hand_target: Dictionary = Catalog.create_instance(
		&"HanBinZhenQi3", Rules.OPPONENT_OWNER, &"count_hand_activation"
	)
	hand_target["ki"] = 1
	activation_board[0] = {"owner": Rules.OPPONENT_OWNER, "card": hand_target}
	var activation_state := State.new(
		activation_board,
		[
			Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"count_player_hand_a"),
			Catalog.create_instance(&"TuNaShu1", Rules.PLAYER_OWNER, &"count_player_hand_b"),
		],
		[
			Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"count_opponent_hand_a"),
			Catalog.create_instance(&"TuNaShu1", Rules.OPPONENT_OWNER, &"count_opponent_hand_b"),
		],
		Rules.OPPONENT_OWNER
	)
	_assert_native_legal_count_equivalence(activation_state, "Multiple board and hand activations")

	var no_ki_state: State = activation_state.duplicate_state()
	var no_ki_hand_source: Dictionary = (no_ki_state.board[0] as Dictionary).get("card", {}) as Dictionary
	var no_ki_multi_source: Dictionary = (no_ki_state.board[4] as Dictionary).get("card", {}) as Dictionary
	no_ki_hand_source["ki"] = 0
	no_ki_multi_source["ki"] = 0
	_assert_native_legal_count_equivalence(no_ki_state, "Unaffordable activations")

	var full_board: Array = Rules.empty_board()
	for cell: int in range(full_board.size()):
		var owner_id: int = Rules.PLAYER_OWNER if cell % 2 == 0 else Rules.OPPONENT_OWNER
		full_board[cell] = {
			"owner": owner_id,
			"card": Catalog.create_instance(
				&"TaiZuChangQuan", owner_id, StringName("count_full_%d" % cell)
			),
		}
	var full_state := State.new(
		full_board,
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"count_full_player_hand")],
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"count_full_opponent_hand")],
		Rules.OPPONENT_OWNER
	)
	_assert_native_legal_count_equivalence(full_state, "Full board with no play cells")


func _assert_native_legal_count_equivalence(state: State, label: String) -> void:
	var compact := CompactState.new()
	_check(compact.capture_state(state), "%s crosses the compact boundary" % label)
	if not compact.is_structurally_valid():
		return
	var kernel: Object = ClassDB.instantiate(&"DuelNativeCompactKernel")
	_check(kernel != null, "%s creates the count kernel" % label)
	if kernel == null:
		return
	_check(bool(kernel.call("load_compact_payload", compact.to_variant_payload())), "%s loads natively" % label)
	for owner_id: int in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		var generated: Array = kernel.call("get_legal_actions_for_owner", owner_id) as Array
		var counted: int = int(kernel.call("count_legal_actions_for_owner", owner_id))
		_check(
			counted == generated.size(),
			"%s owner %d fast count matches %d generated actions (counted=%d)"
			% [label, owner_id, generated.size(), counted]
		)


func _test_native_search_diagnostics_contract() -> void:
	var state: State = _make_search_state()
	var reference: Dictionary = Search.find_best_action_iterative_native(
		state,
		Rules.OPPONENT_OWNER,
		{
			"max_depth": 1,
			"depth_mode": &"complete_round",
			"use_internal_pv_ordering": false,
			"use_history_ordering": false,
			"collect_search_diagnostics": false,
		}
	)
	var diagnostic: Dictionary = Search.find_best_action_iterative_native(
		state,
		Rules.OPPONENT_OWNER,
		{
			"max_depth": 1,
			"depth_mode": &"complete_round",
			"use_internal_pv_ordering": true,
			"use_history_ordering": true,
			"collect_search_diagnostics": true,
		}
	)
	_check(
		not bool(reference.get("search_diagnostics_enabled", true)),
		"Native search diagnostics default to disabled"
	)
	_check(
		bool(diagnostic.get("search_diagnostics_enabled", false)),
		"Native search accepts the benchmark-only diagnostics switch"
	)
	_check(
		bool(diagnostic.get("internal_pv_ordering_enabled", false)),
		"Native search receives the internal PV ordering switch"
	)
	_check(
		bool(diagnostic.get("history_ordering_enabled", false)),
		"Native search receives the history ordering switch"
	)
	for field: String in [
		"time_legal_actions_usec",
		"time_order_usec",
		"time_apply_usec",
		"time_evaluate_usec",
		"time_key_usec",
		"ordered_nodes",
		"visited_children",
		"cutoff_first_child",
		"cutoff_second_child",
		"cutoff_third_fourth_child",
		"cutoff_fifth_eighth_child",
		"cutoff_ninth_or_later_child",
		"pv_queries",
		"pv_hits",
		"pv_legal_hits",
		"pv_illegal_hits",
		"history_queries",
		"history_hits",
		"history_cutoffs",
	]:
		_check(int(reference.get(field, -1)) == 0, "Disabled diagnostics keep %s at zero" % field)
		_check(int(diagnostic.get(field, -1)) >= 0, "Enabled diagnostics expose nonnegative %s" % field)
	_check(int(diagnostic.get("ordered_nodes", 0)) > 0, "Enabled diagnostics count ordered nodes")
	_check(int(diagnostic.get("visited_children", 0)) > 0, "Enabled diagnostics count visited children")
	var cutoff_bucket_total: int = 0
	for field: String in [
		"cutoff_first_child",
		"cutoff_second_child",
		"cutoff_third_fourth_child",
		"cutoff_fifth_eighth_child",
		"cutoff_ninth_or_later_child",
	]:
		cutoff_bucket_total += int(diagnostic.get(field, 0))
	_check(
		cutoff_bucket_total == int(diagnostic.get("cutoffs", -1)),
		"Cutoff position buckets account for every native cutoff"
	)
	var reference_action: Action = reference.get("action") as Action
	var diagnostic_action: Action = diagnostic.get("action") as Action
	_check(
		reference_action != null
		and diagnostic_action != null
		and reference_action.is_same_as(diagnostic_action),
		"Diagnostic and dormant ordering switches preserve the root action"
	)
	_check(
		int(reference.get("score", 0)) == int(diagnostic.get("score", 1)),
		"Diagnostic and dormant ordering switches preserve the score"
	)


func _test_native_search_releases_temporary_dictionaries() -> void:
	var compact := CompactState.new()
	_check(compact.capture_state(_make_search_state()), "Native memory fixture crosses the compact boundary")
	if not compact.is_structurally_valid():
		return
	var kernel: Object = ClassDB.instantiate(&"DuelNativeCompactKernel")
	_check(kernel != null, "Native memory fixture creates the native kernel")
	if kernel == null:
		return
	_check(
		bool(kernel.call("load_compact_payload", compact.to_variant_payload())),
		"Native memory fixture loads into the native kernel"
	)
	var warmup: Dictionary = kernel.call(
		"search_iterative_depth",
		Rules.OPPONENT_OWNER,
		0,
		0,
		2_000,
		0,
		&"complete_round",
		Callable()
	) as Dictionary
	warmup.clear()
	var minimum_usage: float = float(Performance.get_monitor(Performance.MEMORY_STATIC))
	var maximum_usage: float = minimum_usage
	for _repeat_index: int in range(3):
		var result: Dictionary = kernel.call(
			"search_iterative_depth",
			Rules.OPPONENT_OWNER,
			0,
			0,
			2_000,
			0,
			&"complete_round",
			Callable()
		) as Dictionary
		_check(int(result.get("nodes", 0)) >= 2_000, "Native memory fixture reaches its node budget")
		result.clear()
		var usage: float = float(Performance.get_monitor(Performance.MEMORY_STATIC))
		minimum_usage = minf(minimum_usage, usage)
		maximum_usage = maxf(maximum_usage, usage)
	_check(
		maximum_usage - minimum_usage < 1_048_576.0,
		"Repeated native searches release temporary Dictionary references (growth=%.2f MiB)"
		% ((maximum_usage - minimum_usage) / 1_048_576.0)
	)


func _assert_production_transition(state: State, action: Action, label: String) -> Dictionary:
	var before: Dictionary = CompactState.exact_state_payload(state)
	var transition: Dictionary = Simulator.apply_action(state, action)
	_check(bool(transition.get("valid", false)), "%s production native accepts the action" % label)
	_check(CompactState.exact_state_payload(state) == before, "%s does not mutate its input state" % label)
	_check(transition.get("captures", null) is Array, "%s returns an ordered capture array" % label)
	_check(transition.get("exiles", null) is Array, "%s returns an ordered exile array" % label)
	_check(transition.get("events", null) is Array, "%s returns an ordered event array" % label)
	if not bool(transition.get("valid", false)):
		return transition
	var next_state: State = transition.get("state") as State
	_check(next_state != null, "%s returns a DuelState" % label)
	if next_state == null:
		return transition
	var compact := CompactState.new()
	_check(
		compact.capture_state(next_state) and compact.is_structurally_valid(),
		"%s returns a structurally valid production state" % label
	)
	_check(next_state.turn_count == state.turn_count + 1, "%s consumes exactly one action" % label)
	return transition


func _zone_has_instance(zone: Array, instance_id: StringName) -> bool:
	for card_value: Variant in zone:
		if (
			card_value is Dictionary
			and StringName((card_value as Dictionary).get("instance_id", &"")) == instance_id
		):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
