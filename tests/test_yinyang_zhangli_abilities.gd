extends SceneTree

const BoardQueries = preload("res://tests/helpers/duel_native_board_queries.gd")

const CARD_SCENE: PackedScene = preload("res://scenes/card_view.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const Action = preload("res://scripts/duel_action.gd")
const Abilities = preload("res://scripts/duel_abilities.gd")
const Executor = preload("res://tests/helpers/duel_native_action_test_harness.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_and_special_power_vocabulary()
	await _test_special_power_presentation()
	_test_power_change_immunity_and_selector_skip()
	_test_distance_two_attack_rules()
	_test_entry_draw_grant_and_attack_order()
	_test_empty_draw_and_no_palm_edges()
	_test_filtered_draw_respects_hand_capacity()
	_test_range_grant_deduplication_and_flip_loss()
	_test_power_increase_batch_reactions()
	_finish()


func _test_catalog_and_special_power_vocabulary() -> void:
	_check(
		Catalog.CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE
		in Catalog.KNOWN_SELECTOR_CONDITIONS,
		"Mutable-power selector conditions are registered"
	)
	_check(
		Catalog.MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO in Catalog.KNOWN_MODIFIERS,
		"Distance-two attack modifiers are registered"
	)
	_check(
		Catalog.TRIGGER_POWER_INCREASE_BATCH_FINISHED in Catalog.KNOWN_TRIGGER_EVENTS
		and Catalog.CONDITION_POWER_INCREASE_BATCH_INCLUDES_ALLY
		in Catalog.KNOWN_TRIGGER_CONDITIONS,
		"Power-increase batch reactions use registered generic vocabulary"
	)
	var missing_batch_zone: Dictionary = Catalog.YINYANG_RANGE_FOUR.duplicate(true)
	var missing_zone_condition: Dictionary = (
		(((missing_batch_zone.get("triggers", []) as Array)[0] as Dictionary)
		.get("conditions", []) as Array)[0] as Dictionary
	)
	missing_zone_condition.erase("zone")
	_check(
		not Catalog.validate_ability(missing_batch_zone).is_empty(),
		"Power-increase batch ally conditions require an explicit zone"
	)
	var unknown_batch_zone: Dictionary = Catalog.YINYANG_RANGE_FOUR.duplicate(true)
	var unknown_zone_condition: Dictionary = (
		(((unknown_batch_zone.get("triggers", []) as Array)[0] as Dictionary)
		.get("conditions", []) as Array)[0] as Dictionary
	)
	unknown_zone_condition["zone"] = &"deck"
	_check(
		not Catalog.validate_ability(unknown_batch_zone).is_empty(),
		"Power-increase batch ally conditions reject unknown zones"
	)
	_check(
		Rules.has_special_negative_powers({"powers": [-1, -1, -1, -1]}),
		"Four negative-one sides use special power rules"
	)
	_check(
		not Rules.has_special_negative_powers({"powers": [-1, 2, 3, 4]})
		and not Rules.has_special_negative_powers({"powers": [0, 0, 0, 0]}),
		"Partial negative-one and ordinary zero powers do not use the sentinel rule"
	)
	var expected_declarations: Dictionary = {
		&"YinYangZhang2": [1, Catalog.YINYANG_RANGE_TWO],
		&"YinYangZhang3": [2, Catalog.YINYANG_RANGE_THREE],
		&"YinYangZhang4": [2, Catalog.YINYANG_RANGE_FOUR],
	}
	for card_id: StringName in expected_declarations:
		var abilities: Array = Catalog.get_definition(card_id).get("abilities", [])
		var actions: Array = (((abilities[0] as Dictionary).get("triggers", []) as Array)[0] as Dictionary).get("actions", [])
		var expected: Array = expected_declarations[card_id]
		var expected_range: Dictionary = expected[1]
		_check(not abilities.is_empty(), "%s declares its complete ability" % card_id)
		_check(
			actions[1] == {
				"type": Catalog.ACTION_DRAW_CARDS,
				"amount": expected[0],
				"weapon": "掌法",
			},
			"%s uses the generic filtered draw action with its tier amount" % card_id
		)
		_check(
			actions.size() == 4
			and actions[2].get("selector", {}).get("zones", []) == [Catalog.CARD_ZONE_BOARD]
			and actions[2].get("actions", []) == [{
				"type": Catalog.ACTION_GRANT_ABILITY_TO_SELF,
				"ability": expected_range,
			}]
			and actions[3].get("selector", {}).get("zones", []) == [Catalog.CARD_ZONE_BOARD]
			and actions[3].get("actions", []) == [{
				"type": Catalog.ACTION_STANDARD_ATTACK_WITH_SELF,
			}],
			"%s grants board palms their range before a separate board-palm attack pass"
			% card_id
		)
		if card_id == &"YinYangZhang4":
			var granted_triggers: Array = expected_range.get("triggers", [])
			var batch_conditions: Array = (
				(granted_triggers[0] as Dictionary).get("conditions", [])
			)
			_check(
				batch_conditions == [{
					"type": Catalog.CONDITION_POWER_INCREASE_BATCH_INCLUDES_ALLY,
					"zone": Catalog.CARD_ZONE_BOARD,
				}],
				"YinYangZhang4 reacts only to allied board-card power increases"
			)


func _test_special_power_presentation() -> void:
	var sentinel: Control = CARD_SCENE.instantiate() as Control
	root.add_child(sentinel)
	await process_frame
	sentinel.call(
		"configure",
		Catalog.create_instance(&"YinYangZhang3", Rules.PLAYER_OWNER, &"sentinel_view"),
		Rules.PLAYER_OWNER,
		true
	)
	_check(
		_power_labels(sentinel).all(func(label: Label) -> bool: return not label.visible),
		"A revealed four-negative-one card hides all power labels"
	)
	var partial: Control = CARD_SCENE.instantiate() as Control
	root.add_child(partial)
	await process_frame
	partial.call(
		"configure",
		_plain(&"partial_view", [-1, 2, 3, 4], Rules.PLAYER_OWNER),
		Rules.PLAYER_OWNER,
		true
	)
	_check(
		_power_labels(partial).all(func(label: Label) -> bool: return label.visible),
		"A partial negative-one card still displays all four values"
	)
	sentinel.queue_free()
	partial.queue_free()
	await process_frame


func _test_power_change_immunity_and_selector_skip() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(_plain(&"sentinel", [-1, -1, -1, -1], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[1] = _slot(_plain(&"first_legal", [1, 1, 1, 1], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[2] = _slot(_plain(&"second_legal", [2, 2, 2, 2], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[3] = _slot(_plain(&"third_legal", [3, 3, 3, 3], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[8] = _slot(_plain(&"power_source", [4, 4, 4, 4], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var state := State.new(board)
	for amount: int in [2, -2]:
		var direct: Dictionary = Executor.execute_actions(
			state,
			8,
			&"power_source",
			Rules.PLAYER_OWNER,
			[{
				"type": Catalog.ACTION_CHANGE_POWERS,
				"amount": amount,
				"card": Catalog.CARD_REF_TRIGGER_CARD,
			}],
			{"trigger_instance_id": &"sentinel"}
		)
		_check(
			((state.board[0] as Dictionary).get("card", {}) as Dictionary).get("powers", [])
			== [-1, -1, -1, -1]
			and (direct.get("events", []) as Array).is_empty(),
			"Signed power change %d cannot target the special sentinel" % amount
		)
	var wrapper: Dictionary = {
		"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
		"selector": {
			"zones": [Catalog.CARD_ZONE_BOARD],
			"conditions": [
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY},
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
				{"type": Catalog.CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE},
			],
			"limit": 2,
		},
		"actions": [{
			"type": Catalog.ACTION_CHANGE_POWERS,
			"amount": 1,
			"card": Catalog.CARD_REF_SELECTED_CARD,
		}],
	}
	var batch: Dictionary = Executor.execute_actions(
		state,
		8,
		&"power_source",
		Rules.PLAYER_OWNER,
		[wrapper],
		{}
	)
	_check(
		((state.board[1] as Dictionary).get("card", {}) as Dictionary).get("powers", [])
		== [2, 2, 2, 2]
		and ((state.board[2] as Dictionary).get("card", {}) as Dictionary).get("powers", [])
		== [3, 3, 3, 3]
		and ((state.board[3] as Dictionary).get("card", {}) as Dictionary).get("powers", [])
		== [3, 3, 3, 3],
		"A limited power selector skips the sentinel and changes the next two legal cards"
	)
	_check(
		_count_events(batch.get("events", []), &"powers_changed") == 2,
		"Skipped sentinels consume no visual or logical power event"
	)


func _test_distance_two_attack_rules() -> void:
	var sentinel_board: Array = Rules.empty_board()
	sentinel_board[4] = _slot(_plain(&"ordinary_attacker", [1, 1, 1, 1], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	sentinel_board[1] = _slot(_plain(&"negative_defender", [-1, -1, -1, -1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	_check(
		BoardQueries.can_attack_target(sentinel_board, 4, 1),
		"Any nonnegative ordinary edge can attack a negative-one defender"
	)

	var tier_two: Dictionary = _plain(&"tier_two_palm", [5, 5, 5, 5], Rules.PLAYER_OWNER)
	tier_two["active_abilities"] = [_range_ability(false)]
	var board: Array = Rules.empty_board()
	board[6] = _slot(tier_two, Rules.PLAYER_OWNER)
	board[0] = _slot(_plain(&"far_enemy", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	_check(BoardQueries.can_attack_target(board, 6, 0), "Tier-two range attacks through one empty cell")
	board[3] = _slot(_plain(&"middle_ally", [1, 1, 1, 1], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	_check(not BoardQueries.can_attack_target(board, 6, 0), "Tier-two range cannot attack through an ally")
	var tier_three: Dictionary = (board[6] as Dictionary).get("card", {})
	tier_three["active_abilities"] = [_range_ability(true)]
	_check(BoardQueries.can_attack_target(board, 6, 0), "Tier-three and tier-four range attacks through one ally")
	(board[3] as Dictionary)["owner"] = Rules.OPPONENT_OWNER
	_check(not BoardQueries.can_attack_target(board, 6, 0), "Distance-two attacks never pass through an enemy")
	_check(not BoardQueries.can_attack_target(board, 6, 2), "Distance-two attacks remain orthogonal and do not wrap")


func _test_entry_draw_grant_and_attack_order() -> void:
	var yinyang: Dictionary = Catalog.create_instance(
		&"YinYangZhang3",
		Rules.PLAYER_OWNER,
		&"entry_yinyang"
	)
	var board_palm_first: Dictionary = _plain(
		&"board_palm_first",
		[5, 5, 5, 5],
		Rules.PLAYER_OWNER
	)
	var board_palm_second: Dictionary = _plain(
		&"board_palm_second",
		[5, 5, 5, 5],
		Rules.PLAYER_OWNER
	)
	var board_sword: Dictionary = _plain(
		&"board_sword",
		[5, 5, 5, 5],
		Rules.PLAYER_OWNER,
		"剑法"
	)
	var hand_palm: Dictionary = _plain(
		&"hand_palm",
		[3, 3, 3, 3],
		Rules.PLAYER_OWNER
	)
	var hand_sword: Dictionary = _plain(
		&"hand_sword",
		[3, 3, 3, 3],
		Rules.PLAYER_OWNER,
		"剑法"
	)
	var drawn_palm: Dictionary = _plain(
		&"drawn_palm",
		[4, 4, 4, 4],
		Rules.PLAYER_OWNER
	)
	var skipped_sword: Dictionary = _plain(
		&"skipped_sword", [1, 1, 1, 1], Rules.PLAYER_OWNER, "剑法"
	)
	var remaining_palm: Dictionary = _plain(
		&"remaining_palm", [6, 6, 6, 6], Rules.PLAYER_OWNER
	)
	var board: Array = Rules.empty_board()
	board[0] = _slot(board_palm_first, Rules.PLAYER_OWNER)
	board[2] = _slot(board_palm_second, Rules.PLAYER_OWNER)
	board[4] = _slot(board_sword, Rules.PLAYER_OWNER)
	board[6] = _slot(
		_plain(&"first_victim", [1, 1, 1, 1], Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	board[8] = _slot(
		_plain(&"second_victim", [1, 1, 1, 1], Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[yinyang, hand_palm, hand_sword],
			[_plain(&"opponent_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
			Rules.PLAYER_OWNER,
			0,
			[skipped_sword, drawn_palm, remaining_palm],
			[]
		),
		Action.make_play(0, 1, &"entry_yinyang")
	)
	var next_state: State = transition.get("state") as State
	var runtime_first: Dictionary = _board_card(next_state, &"board_palm_first")
	var runtime_second: Dictionary = _board_card(next_state, &"board_palm_second")
	var runtime_sword: Dictionary = _board_card(next_state, &"board_sword")
	var runtime_hand_palm: Dictionary = _find_hand_card(next_state, &"hand_palm")
	var runtime_drawn: Dictionary = _find_hand_card(next_state, &"drawn_palm")
	var runtime_remaining: Dictionary = _find_hand_card(next_state, &"remaining_palm")
	_check(
		bool(transition.get("valid", false))
		and next_state.board[1] == null
		and _removed_has(next_state, Rules.PLAYER_OWNER, &"entry_yinyang"),
		"YinYang exiles itself instead of remaining on the board"
	)
	_check(
		(runtime_first.get("active_abilities", []) as Array).size() == 1
		and (runtime_second.get("active_abilities", []) as Array).size() == 1
		and (runtime_sword.get("active_abilities", []) as Array).is_empty()
		and (runtime_hand_palm.get("active_abilities", []) as Array).is_empty()
		and (runtime_drawn.get("active_abilities", []) as Array).is_empty()
		and (runtime_remaining.get("active_abilities", []) as Array).is_empty(),
		"Only allied board palms receive the range ability"
	)
	var events: Array = transition.get("events", [])
	var exile_index: int = _event_index(events, &"card_exiled", &"entry_yinyang")
	var draw_index: int = _event_index(events, &"card_drawn", &"drawn_palm")
	var first_grant_index: int = _event_index(events, &"ability_gained", &"board_palm_first")
	var second_grant_index: int = _event_index(events, &"ability_gained", &"board_palm_second")
	var first_attack_index: int = _event_index(events, &"attack_started", &"", &"board_palm_first")
	var second_attack_index: int = _event_index(events, &"attack_started", &"", &"board_palm_second")
	_check(
		exile_index >= 0
		and exile_index < draw_index
		and draw_index < first_grant_index
		and first_grant_index < second_grant_index
		and second_grant_index < first_attack_index
		and first_attack_index < second_attack_index,
		"Entry events present exile, filtered draws, every grant, then row-major attacks"
	)
	var remaining_deck: Array = next_state.decks.get(Rules.PLAYER_OWNER, [])
	_check(
		remaining_deck.size() == 1
		and StringName((remaining_deck[0] as Dictionary).get("instance_id", &"")) == &"skipped_sword"
		and not runtime_drawn.is_empty()
		and not runtime_remaining.is_empty(),
		"Tier three draws two matching palms while leaving the skipped sword in place"
	)
	_check(
		_count_events(events, &"attack_started") == 2
		and int((next_state.board[6] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER
		and int((next_state.board[8] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER,
		"Both allied board palms attack once while the exiled YinYang never attacks"
	)


func _test_empty_draw_and_no_palm_edges() -> void:
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			Rules.empty_board(),
			[
				Catalog.create_instance(
					&"YinYangZhang4",
					Rules.PLAYER_OWNER,
					&"edge_yinyang"
				),
				_plain(&"edge_sword", [2, 2, 2, 2], Rules.PLAYER_OWNER, "剑法"),
			],
			[_plain(&"edge_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
			Rules.PLAYER_OWNER
		),
		Action.make_play(0, 4, &"edge_yinyang")
	)
	var next_state: State = transition.get("state") as State
	_check(
		_find_hand_card(next_state, &"edge_sword").get("active_abilities", []) == []
		and _count_events(transition.get("events", []), &"card_drawn") == 0
		and next_state.get_hand(Rules.PLAYER_OWNER).size() == 1
		and _count_events(transition.get("events", []), &"ability_gained") == 0,
		"An empty deck draws no filtered fallback card and grants no palm abilities"
	)


func _test_filtered_draw_respects_hand_capacity() -> void:
	var player_hand: Array = [
		Catalog.create_instance(&"YinYangZhang4", Rules.PLAYER_OWNER, &"capacity_yinyang"),
		_plain(&"capacity_one", [1, 1, 1, 1], Rules.PLAYER_OWNER, "剑法"),
		_plain(&"capacity_two", [1, 1, 1, 1], Rules.PLAYER_OWNER, "剑法"),
		_plain(&"capacity_three", [1, 1, 1, 1], Rules.PLAYER_OWNER, "剑法"),
		_plain(&"capacity_four", [1, 1, 1, 1], Rules.PLAYER_OWNER, "剑法"),
	]
	var deck: Array = [
		_plain(&"capacity_palm_one", [2, 2, 2, 2], Rules.PLAYER_OWNER),
		_plain(&"capacity_palm_two", [3, 3, 3, 3], Rules.PLAYER_OWNER),
	]
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			Rules.empty_board(),
			player_hand,
			[_plain(&"capacity_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
			Rules.PLAYER_OWNER,
			0,
			deck,
			[]
		),
		Action.make_play(0, 4, &"capacity_yinyang")
	)
	var next_state: State = transition.get("state") as State
	_check(
		_count_events(transition.get("events", []), &"card_drawn") == 1
		and next_state.get_hand(Rules.PLAYER_OWNER).size() == 5
		and StringName(((next_state.decks[Rules.PLAYER_OWNER] as Array)[0] as Dictionary).get("instance_id", &"")) == &"capacity_palm_two",
		"Filtered draw stops at hand capacity and leaves the second matching card in the deck"
	)


func _test_range_grant_deduplication_and_flip_loss() -> void:
	var palm: Dictionary = _plain(&"stacked_palm", [5, 5, 5, 5], Rules.PLAYER_OWNER)
	var board: Array = Rules.empty_board()
	board[4] = _slot(palm, Rules.PLAYER_OWNER)
	var state := State.new(board)
	var actions: Array = [
		{"type": Catalog.ACTION_GRANT_ABILITY_TO_SELF, "ability": Catalog.YINYANG_RANGE_THREE},
		{"type": Catalog.ACTION_GRANT_ABILITY_TO_SELF, "ability": Catalog.YINYANG_RANGE_THREE},
		{"type": Catalog.ACTION_GRANT_ABILITY_TO_SELF, "ability": Catalog.YINYANG_RANGE_FOUR},
	]
	var grant_result: Dictionary = Executor.execute_actions(
		state,
		4,
		&"stacked_palm",
		Rules.PLAYER_OWNER,
		actions,
		{}
	)
	var runtime: Dictionary = (state.board[4] as Dictionary).get("card", {})
	_check(
		(runtime.get("active_abilities", []) as Array).size() == 2
		and _count_events(grant_result.get("events", []), &"ability_gained") == 2,
		"Repeated range grants deduplicate structurally identical abilities"
	)
	state.board[0] = _slot(
		_plain(&"flip_source", [9, 9, 9, 9], Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	var flip_events: Array[Dictionary] = Executor.resolve_normal_flip(
		state,
		0,
		&"flip_source",
		4,
		&"stacked_palm",
		Rules.OPPONENT_OWNER
	)
	_check(
		(runtime.get("active_abilities", []) as Array).is_empty()
		and _count_events(flip_events, &"ability_lost") == 2,
		"All granted YinYang range effects are non-retained and are lost on flip"
	)


func _test_power_increase_batch_reactions() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(_plain(&"batch_ally_a", [2, 2, 2, 2], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[1] = _slot(_plain(&"batch_enemy", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[2] = _slot(_plain(&"batch_ally_b", [2, 2, 2, 2], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var listener: Dictionary = _plain(&"batch_listener", [9, 9, 9, 9], Rules.PLAYER_OWNER)
	listener["active_abilities"] = [Catalog.YINYANG_RANGE_FOUR]
	board[4] = _slot(listener, Rules.PLAYER_OWNER)
	board[8] = _slot(_plain(&"batch_source", [2, 2, 2, 2], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var state := State.new(board)
	var batch_action: Dictionary = {
		"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
		"selector": {
			"zones": [Catalog.CARD_ZONE_BOARD],
			"conditions": [
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY},
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
			],
			"limit": 2,
		},
		"actions": [{
			"type": Catalog.ACTION_CHANGE_POWERS,
			"amount": 1,
			"card": Catalog.CARD_REF_SELECTED_CARD,
		}],
	}
	var result: Dictionary = Executor.execute_actions(
		state,
		8,
		&"batch_source",
		Rules.PLAYER_OWNER,
		[batch_action],
		{}
	)
	var events: Array = result.get("events", [])
	_check(
		_count_events(events, &"powers_changed") == 2
		and _count_source_events(events, &"ability_triggered", &"batch_listener") == 1
		and _count_source_events(events, &"attack_started", &"batch_listener") == 1,
		"One multi-card power increase batch makes each tier-four listener attack only once"
	)
	_check(
		_last_event_index(events, &"powers_changed")
		< _event_index(events, &"ability_triggered", &"", &"batch_listener"),
		"The batch reaction begins only after every power-change event"
	)

	var hand_only_board: Array = Rules.empty_board()
	var hand_only_listener: Dictionary = _plain(
		&"hand_only_listener", [5, 5, 5, 5], Rules.PLAYER_OWNER
	)
	hand_only_listener["active_abilities"] = [Catalog.YINYANG_RANGE_FOUR]
	hand_only_board[0] = _slot(hand_only_listener, Rules.PLAYER_OWNER)
	hand_only_board[8] = _slot(
		_plain(&"hand_only_source", [2, 2, 2, 2], Rules.PLAYER_OWNER),
		Rules.PLAYER_OWNER
	)
	var hand_only_state := State.new(
		hand_only_board,
		[_plain(&"hand_only_target", [2, 2, 2, 2], Rules.PLAYER_OWNER)]
	)
	var hand_only_result: Dictionary = Executor.execute_actions(
		hand_only_state,
		8,
		&"hand_only_source",
		Rules.PLAYER_OWNER,
		[_power_change_trigger_action(&"hand_only")],
		{"trigger_instance_id": &"hand_only_target"}
	)
	_check(
		_count_events(hand_only_result.get("events", []), &"powers_changed") == 1
		and _count_source_events(
			hand_only_result.get("events", []), &"ability_triggered", &"hand_only_listener"
		) == 0,
		"An allied hand-card increase does not trigger YinYangZhang4"
	)

	var mixed_board: Array = Rules.empty_board()
	var mixed_listener: Dictionary = _plain(
		&"mixed_listener", [5, 5, 5, 5], Rules.PLAYER_OWNER, "剑法"
	)
	mixed_listener["active_abilities"] = [Catalog.YINYANG_RANGE_FOUR]
	mixed_board[0] = _slot(mixed_listener, Rules.PLAYER_OWNER)
	mixed_board[6] = _slot(
		_plain(&"mixed_board_target", [2, 2, 2, 2], Rules.PLAYER_OWNER),
		Rules.PLAYER_OWNER
	)
	mixed_board[8] = _slot(
		_plain(&"mixed_source", [2, 2, 2, 2], Rules.PLAYER_OWNER, "剑法"),
		Rules.PLAYER_OWNER
	)
	var mixed_state := State.new(
		mixed_board,
		[_plain(&"mixed_hand_target", [2, 2, 2, 2], Rules.PLAYER_OWNER)]
	)
	var mixed_result: Dictionary = Executor.execute_actions(
		mixed_state,
		8,
		&"mixed_source",
		Rules.PLAYER_OWNER,
		[{
			"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
			"selector": {
				"zones": [Catalog.CARD_ZONE_HAND, Catalog.CARD_ZONE_BOARD],
				"conditions": [
					{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY},
					{
						"type": Catalog.CONDITION_SELECTED_CARD_WEAPON_IS,
						"weapon": "掌法",
					},
				],
			},
			"actions": [{
				"type": Catalog.ACTION_CHANGE_POWERS,
				"amount": 1,
				"card": Catalog.CARD_REF_SELECTED_CARD,
			}],
		}],
		{}
	)
	_check(
		_count_events(mixed_result.get("events", []), &"powers_changed") == 2
		and _count_source_events(
			mixed_result.get("events", []), &"ability_triggered", &"mixed_listener"
		) == 1,
		"A mixed hand-and-board increase batch triggers once because it includes a board ally"
	)

	var grouped_state := _make_batch_group_state()
	var grouped: Dictionary = Executor.execute_actions(
		grouped_state,
		8,
		&"group_source",
		Rules.PLAYER_OWNER,
		[
			_power_change_trigger_action(&"shared"),
			_power_change_trigger_action(&"shared"),
		],
		{"trigger_instance_id": &"group_target"}
	)
	_check(
		_count_source_events(grouped.get("events", []), &"ability_triggered", &"group_listener") == 1,
		"Contiguous sibling changes with one batch group dispatch one reaction event"
	)
	var separate_state := _make_batch_group_state()
	var separate: Dictionary = Executor.execute_actions(
		separate_state,
		8,
		&"group_source",
		Rules.PLAYER_OWNER,
		[
			_power_change_trigger_action(&"first"),
			_power_change_trigger_action(&"second"),
		],
		{"trigger_instance_id": &"group_target"}
	)
	_check(
		_count_source_events(separate.get("events", []), &"ability_triggered", &"group_listener") == 2,
		"Two distinct power-increase batches dispatch two reactions"
	)
	var multi_board: Array = Rules.empty_board()
	for cell_and_id: Array in [[0, &"multi_listener_a"], [2, &"multi_listener_b"]]:
		var multi_listener: Dictionary = _plain(
			cell_and_id[1], [5, 5, 5, 5], Rules.PLAYER_OWNER
		)
		multi_listener["active_abilities"] = [Catalog.YINYANG_RANGE_FOUR]
		multi_board[cell_and_id[0]] = _slot(multi_listener, Rules.PLAYER_OWNER)
	multi_board[6] = _slot(
		_plain(&"multi_target", [2, 2, 2, 2], Rules.PLAYER_OWNER),
		Rules.PLAYER_OWNER
	)
	multi_board[8] = _slot(
		_plain(&"multi_source", [2, 2, 2, 2], Rules.PLAYER_OWNER),
		Rules.PLAYER_OWNER
	)
	var multi_result: Dictionary = Executor.execute_actions(
		State.new(multi_board),
		8,
		&"multi_source",
		Rules.PLAYER_OWNER,
		[_power_change_trigger_action(&"multi")],
		{"trigger_instance_id": &"multi_target"}
	)
	_check(
		_count_source_events(multi_result.get("events", []), &"ability_triggered", &"multi_listener_a") == 1
		and _count_source_events(multi_result.get("events", []), &"ability_triggered", &"multi_listener_b") == 1,
		"Every allied tier-four listener reacts once to the same batch"
	)

	var enemy_board: Array = Rules.empty_board()
	var enemy_listener: Dictionary = _plain(
		&"enemy_batch_listener", [5, 5, 5, 5], Rules.PLAYER_OWNER
	)
	enemy_listener["active_abilities"] = [Catalog.YINYANG_RANGE_FOUR]
	enemy_board[0] = _slot(enemy_listener, Rules.PLAYER_OWNER)
	enemy_board[6] = _slot(
		_plain(&"enemy_batch_target", [2, 2, 2, 2], Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	enemy_board[8] = _slot(
		_plain(&"enemy_batch_source", [2, 2, 2, 2], Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	var enemy_result: Dictionary = Executor.execute_actions(
		State.new(enemy_board),
		8,
		&"enemy_batch_source",
		Rules.OPPONENT_OWNER,
		[_power_change_trigger_action(&"enemy")],
		{"trigger_instance_id": &"enemy_batch_target"}
	)
	_check(
		_count_source_events(enemy_result.get("events", []), &"ability_triggered", &"enemy_batch_listener") == 0,
		"A batch that increases only enemy cards does not trigger the listener"
	)

	var ignored_state := _make_batch_group_state()
	var decreased: Dictionary = Executor.execute_actions(
		ignored_state,
		8,
		&"group_source",
		Rules.PLAYER_OWNER,
		[{
			"type": Catalog.ACTION_CHANGE_POWERS,
			"amount": -1,
			"card": Catalog.CARD_REF_TRIGGER_CARD,
		}],
		{"trigger_instance_id": &"group_target"}
	)
	_check(
		_count_source_events(decreased.get("events", []), &"ability_triggered", &"group_listener") == 0,
		"Power decreases do not dispatch the increase-batch reaction"
	)
	var sentinel: Dictionary = _board_card(ignored_state, &"group_target")
	sentinel["powers"] = [-1, -1, -1, -1]
	var no_effect: Dictionary = Executor.execute_actions(
		ignored_state,
		8,
		&"group_source",
		Rules.PLAYER_OWNER,
		[{
			"type": Catalog.ACTION_CHANGE_POWERS,
			"amount": 1,
			"card": Catalog.CARD_REF_TRIGGER_CARD,
		}],
		{"trigger_instance_id": &"group_target"}
	)
	_check(
		_count_events(no_effect.get("events", []), &"powers_changed") == 0
		and _count_source_events(no_effect.get("events", []), &"ability_triggered", &"group_listener") == 0,
		"A failed positive change dispatches no batch reaction"
	)


func _make_batch_group_state() -> State:
	var board: Array = Rules.empty_board()
	var listener: Dictionary = _plain(&"group_listener", [5, 5, 5, 5], Rules.PLAYER_OWNER)
	listener["active_abilities"] = [Catalog.YINYANG_RANGE_FOUR]
	board[4] = _slot(listener, Rules.PLAYER_OWNER)
	board[6] = _slot(_plain(&"group_target", [2, 2, 2, 2], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[8] = _slot(_plain(&"group_source", [2, 2, 2, 2], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	return State.new(board)


func _power_change_trigger_action(group_name: StringName) -> Dictionary:
	return {
		"type": Catalog.ACTION_CHANGE_POWERS,
		"amount": 1,
		"card": Catalog.CARD_REF_TRIGGER_CARD,
		"power_change_batch_group": group_name,
	}


func _range_ability(allow_intervening_ally: bool) -> Dictionary:
	return {
		"modifiers": [{
			"type": Catalog.MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO,
			"allow_intervening_ally": allow_intervening_ally,
		}],
	}


func _power_labels(card: Control) -> Array[Label]:
	return [
		card.get_node("Overlay/TopPower") as Label,
		card.get_node("Overlay/RightPower") as Label,
		card.get_node("Overlay/BottomPower") as Label,
		card.get_node("Overlay/LeftPower") as Label,
	]


func _plain(
	instance_id: StringName,
	powers: Array,
	owner_id: int,
	weapon: String = "掌法"
) -> Dictionary:
	return {
		"instance_id": instance_id,
		"card_id": instance_id,
		"glyph": String(instance_id),
		"picture": "",
		"sect": "嵩山派",
		"tier": 1,
		"weapon": weapon,
		"description": "",
		"flavor": "",
		"powers": powers.duplicate(),
		"ki": 0,
		"original_owner": owner_id,
		"active_abilities": [],
		"revealed_to_owner_ids": [owner_id],
	}


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _find_hand_card(state: State, instance_id: StringName) -> Dictionary:
	for owner_id: int in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		for card_value: Variant in state.get_hand(owner_id):
			if (
				card_value is Dictionary
				and StringName((card_value as Dictionary).get("instance_id", &""))
				== instance_id
			):
				return card_value as Dictionary
	return {}


func _board_card(state: State, instance_id: StringName) -> Dictionary:
	for slot_value: Variant in state.board:
		if not slot_value is Dictionary:
			continue
		var card: Dictionary = (slot_value as Dictionary).get("card", {})
		if StringName(card.get("instance_id", &"")) == instance_id:
			return card
	return {}


func _removed_has(state: State, owner_id: int, instance_id: StringName) -> bool:
	for card_value: Variant in state.removed_cards.get(owner_id, []):
		if (
			card_value is Dictionary
			and StringName((card_value as Dictionary).get("instance_id", &""))
			== instance_id
		):
			return true
	return false


func _event_index(
	events: Array,
	event_type: StringName,
	instance_id: StringName,
	source_instance_id: StringName = &""
) -> int:
	for event_index: int in range(events.size()):
		var event_value: Variant = events[event_index]
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
			and (
				instance_id == &""
				or StringName((event_value as Dictionary).get("instance_id", &""))
				== instance_id
			)
			and (
				source_instance_id == &""
				or StringName((event_value as Dictionary).get("source_instance_id", &""))
				== source_instance_id
			)
		):
			return event_index
	return -1


func _count_events(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for event_value: Variant in events:
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
		):
			count += 1
	return count


func _count_source_events(
	events: Array,
	event_type: StringName,
	source_instance_id: StringName
) -> int:
	var count: int = 0
	for event_value: Variant in events:
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
			and StringName((event_value as Dictionary).get("source_instance_id", &""))
			== source_instance_id
		):
			count += 1
	return count


func _last_event_index(events: Array, event_type: StringName) -> int:
	for event_index: int in range(events.size() - 1, -1, -1):
		var event_value: Variant = events[event_index]
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
		):
			return event_index
	return -1


func _finish() -> void:
	if _failures == 0:
		print("YINYANG_ZHANGLI_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"YINYANG_ZHANGLI_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
