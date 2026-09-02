extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Abilities = preload("res://scripts/duel_abilities.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const CompactState = preload("res://scripts/duel_compact_state.gd")
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
