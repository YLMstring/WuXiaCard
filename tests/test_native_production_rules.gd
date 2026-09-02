extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
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
	_test_every_catalog_card_hand_play_matches_oracle()
	_test_every_catalog_activation_matches_oracle()
	_test_native_whole_tree_search_matches_oracle()
	_test_native_search_node_budget_keeps_only_complete_depths()
	_test_production_search_routes_to_native_whole_tree()
	_test_native_search_honors_cancellation()
	_test_native_search_keeps_same_turn_principal_actions()
	if _failures == 0:
		print("NATIVE_PRODUCTION_RULES_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("NATIVE_PRODUCTION_RULES_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _test_every_catalog_card_hand_play_matches_oracle() -> void:
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
		_compare_transition(
			state,
			Action.make_play(0, 4, StringName("native_play_%s" % prefix)),
			"catalog play %s" % card_id
		)


func _test_every_catalog_activation_matches_oracle() -> void:
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
		for action: Action in Simulator.get_legal_actions(state):
			if action.action_type != Action.TYPE_ACTIVATE or action.source_index != 4:
				continue
			_compare_transition(state, action, "catalog activation %s %s" % [card_id, action.canonical_key()])


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


func _test_native_whole_tree_search_matches_oracle() -> void:
	var state: State = _make_search_state()
	var native: Dictionary = Search.find_best_action_iterative_native(
		state,
		Rules.OPPONENT_OWNER,
		{"max_depth": 1}
	)
	var oracle: Dictionary = Search.find_best_action_iterative_oracle(
		state,
		Rules.OPPONENT_OWNER,
		{"max_depth": 1}
	)
	var native_action: Action = native.get("action") as Action
	var oracle_action: Action = oracle.get("action") as Action
	_check(native_action != null and native_action.action_type != &"", "Native whole-tree search returns an action")
	_check(
		native_action.canonical_key() == oracle_action.canonical_key(),
		"Depth-one native whole-tree search chooses the same action as Oracle"
	)
	_check(int(native.get("score", 0)) == int(oracle.get("score", 1)), "Depth-one native whole-tree score matches Oracle")
	_check(int(native.get("completed_depth", 0)) == 1, "Native whole-tree search reports complete-round depth one")


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


func _compare_transition(state: State, action: Action, label: String) -> void:
	var oracle: Dictionary = Simulator.apply_action_oracle(state, action)
	var native: Dictionary = Simulator.apply_action(state, action)
	_check(bool(oracle.get("valid", false)), "%s oracle accepts the action" % label)
	_check(bool(native.get("valid", false)), "%s production native accepts the action" % label)
	if not bool(oracle.get("valid", false)) or not bool(native.get("valid", false)):
		return
	var oracle_state: State = oracle.get("state") as State
	var native_state: State = native.get("state") as State
	_check(
		CompactState.exact_state_payload(native_state) == CompactState.exact_state_payload(oracle_state),
		"%s native state exactly matches Oracle" % label
	)
	_check(native.get("captures", []) == oracle.get("captures", []), "%s capture order matches Oracle" % label)
	_check(native.get("exiles", []) == oracle.get("exiles", []), "%s exile order matches Oracle" % label)
	_check(native.get("events", []) == oracle.get("events", []), "%s event order matches Oracle" % label)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
