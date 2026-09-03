extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Action = preload("res://scripts/duel_action.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Selector = preload("res://scripts/duel_card_selector.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const Triggers = preload("res://scripts/duel_triggers.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_vocabulary()
	_test_card_declarations()
	_test_tianchang_power_from_adjacent_enemies()
	_test_enclosure_selector_uses_existing_neighbors()
	_test_hengshan_two_grants_self_and_adjacent_allies()
	_test_hengshan_three_grants_all_allies()
	_test_hengshan_four_flips_surrounded_enemy()
	_test_hengshan_four_respects_flip_prevention()
	_test_repeated_hengshan_grants_do_not_stack()
	_test_after_attack_uses_final_board_positions()
	_test_counterattacks_once_after_all_directions()
	_test_nested_counterattacks_consume_before_attacking()
	if _failures == 0:
		print("TIANCHANG_HENGSHAN_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"TIANCHANG_HENGSHAN_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_catalog_vocabulary() -> void:
	_check(
		Catalog.TRIGGER_CARD_AFTER_ATTACK in Catalog.KNOWN_TRIGGER_EVENTS,
		"The complete-attack event is registered"
	)
	_check(
		Catalog.CONDITION_ATTACKER_CARD_IS_ENEMY in Catalog.KNOWN_TRIGGER_CONDITIONS,
		"The enemy-attacker condition is registered"
	)
	_check(
		Catalog.CONDITION_ATTACK_FLIPPED_ALLY_IN_RANGE
		in Catalog.KNOWN_TRIGGER_CONDITIONS,
		"The attack-summary ally condition is registered"
	)
	_check(
		Catalog.CONDITION_SELECTED_CARD_SURROUNDED_BY_ALLIES
		in Catalog.KNOWN_SELECTOR_CONDITIONS,
		"The enclosure selector condition is registered"
	)
	_check(
		Catalog.ACTION_FLIP_SELF in Catalog.KNOWN_ACTIONS,
		"The generic selected-card flip action is registered"
	)


func _test_card_declarations() -> void:
	_check(Catalog.validate_catalog().is_empty(), "The complete catalog validates")
	var expected_ability_counts: Dictionary = {
		&"TianChangZhang3": 1,
		&"TianChangZhang4": 2,
		&"HenShanJianZhen2": 1,
		&"HenShanJianZhen3": 1,
		&"HenShanJianZhen4": 2,
	}
	for card_id: StringName in expected_ability_counts:
		_check(Catalog.has_card(card_id), "%s has a definition" % card_id)
		_check(card_id in Catalog.get_all_card_ids(), "%s is registered" % card_id)
		if not Catalog.has_card(card_id):
			continue
		var abilities: Array = Catalog.get_definition(card_id).get("abilities", [])
		_check(
			abilities.size() == int(expected_ability_counts[card_id]),
			"%s declares the approved ability count" % card_id
		)


func _test_tianchang_power_from_adjacent_enemies() -> void:
	var board: Array = Rules.empty_board()
	board[1] = _slot(_plain(&"north_enemy", [9, 9, 9, 9]), Rules.OPPONENT_OWNER)
	board[5] = _slot(_plain(&"east_enemy", [9, 9, 9, 9]), Rules.OPPONENT_OWNER)
	board[7] = _slot(_plain(&"south_ally", [1, 1, 1, 1]), Rules.PLAYER_OWNER)
	var tianchang: Dictionary = Catalog.create_instance(
		&"TianChangZhang3",
		Rules.PLAYER_OWNER,
		&"tianchang_power"
	)
	var initial_powers: Array = (tianchang.get("powers", []) as Array).duplicate()
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [tianchang], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"tianchang_power")
	)
	var next_state: State = transition.get("state") as State
	var runtime: Dictionary = (next_state.board[4] as Dictionary).get("card", {})
	var expected_powers: Array = []
	for power: Variant in initial_powers:
		expected_powers.append(int(power) + 2)
	_check(
		runtime.get("powers", []) == expected_powers,
		"Two adjacent enemies add two to every side"
	)
	_check(
		_event_count(transition.get("events", []), &"powers_changed") == 2,
		"The selector applies one power increase per adjacent enemy"
	)


func _test_enclosure_selector_uses_existing_neighbors() -> void:
	var corner_board: Array = Rules.empty_board()
	corner_board[8] = _slot(_plain(&"selector_source"), Rules.PLAYER_OWNER)
	corner_board[0] = _slot(_plain(&"corner_enemy"), Rules.OPPONENT_OWNER)
	corner_board[1] = _slot(_plain(&"corner_right"), Rules.PLAYER_OWNER)
	corner_board[3] = _slot(_plain(&"corner_down"), Rules.PLAYER_OWNER)
	var selector: Dictionary = {
		"zones": [Catalog.CARD_ZONE_BOARD],
		"conditions": [
			{"type": Catalog.CONDITION_SELECTED_CARD_IS_ENEMY},
			{"type": Catalog.CONDITION_SELECTED_CARD_SURROUNDED_BY_ALLIES},
		],
	}
	var corner_state := State.new(corner_board)
	_check(
		Selector.snapshot(corner_state, selector, &"selector_source") == [&"corner_enemy"],
		"A corner enemy is surrounded by its two existing allied neighbors"
	)
	corner_state.board[3] = null
	_check(
		Selector.snapshot(corner_state, selector, &"selector_source").is_empty(),
		"An empty existing neighbor breaks corner enclosure"
	)
	var edge_board: Array = Rules.empty_board()
	edge_board[8] = _slot(_plain(&"edge_source"), Rules.PLAYER_OWNER)
	edge_board[1] = _slot(_plain(&"edge_enemy"), Rules.OPPONENT_OWNER)
	for cell: int in [0, 2, 4]:
		edge_board[cell] = _slot(_plain(StringName("edge_ally_%d" % cell)), Rules.PLAYER_OWNER)
	_check(
		Selector.snapshot(State.new(edge_board), selector, &"edge_source") == [&"edge_enemy"],
		"A non-corner edge enemy requires all three existing allied neighbors"
	)
	var center_board: Array = Rules.empty_board()
	center_board[0] = _slot(_plain(&"center_source"), Rules.PLAYER_OWNER)
	center_board[4] = _slot(_plain(&"center_enemy"), Rules.OPPONENT_OWNER)
	for cell: int in [1, 3, 5, 7]:
		center_board[cell] = _slot(_plain(StringName("center_ally_%d" % cell)), Rules.PLAYER_OWNER)
	_check(
		Selector.snapshot(State.new(center_board), selector, &"center_source") == [&"center_enemy"],
		"A center enemy requires all four allied neighbors"
	)


func _test_hengshan_two_grants_self_and_adjacent_allies() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(
		&"HenShanJianZhen2", Rules.PLAYER_OWNER, &"hengshan_two"
	), Rules.PLAYER_OWNER)
	board[1] = _slot(_plain(&"adjacent_ally"), Rules.PLAYER_OWNER)
	board[0] = _slot(_plain(&"distant_ally"), Rules.PLAYER_OWNER)
	board[5] = _slot(_plain(&"adjacent_enemy"), Rules.OPPONENT_OWNER)
	var quiet: Dictionary = _plain(&"quiet_two")
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [quiet], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 8, &"quiet_two")
	)
	var next_state: State = transition.get("state") as State
	_check(_ability_count(next_state, 4) == 2, "Tier two grants its counter to itself")
	_check(_ability_count(next_state, 1) == 1, "Tier two grants an adjacent ally")
	_check(_ability_count(next_state, 0) == 0, "Tier two excludes a distant ally")
	_check(_ability_count(next_state, 5) == 0, "Tier two excludes an adjacent enemy")


func _test_hengshan_three_grants_all_allies() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(
		&"HenShanJianZhen3", Rules.PLAYER_OWNER, &"hengshan_three"
	), Rules.PLAYER_OWNER)
	board[0] = _slot(_plain(&"far_ally"), Rules.PLAYER_OWNER)
	board[5] = _slot(_plain(&"far_enemy"), Rules.OPPONENT_OWNER)
	var quiet: Dictionary = _plain(&"quiet_three")
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [quiet], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 8, &"quiet_three")
	)
	var next_state: State = transition.get("state") as State
	_check(_ability_count(next_state, 4) == 2, "Tier three grants itself")
	_check(_ability_count(next_state, 0) == 1, "Tier three grants a distant ally")
	_check(_ability_count(next_state, 8) == 1, "Tier three includes the newly played ally")
	_check(_ability_count(next_state, 5) == 0, "Tier three excludes enemies")


func _test_hengshan_four_flips_surrounded_enemy() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(_plain(&"surrounded_enemy"), Rules.OPPONENT_OWNER)
	board[1] = _slot(_plain(&"surround_right"), Rules.PLAYER_OWNER)
	board[3] = _slot(_plain(&"surround_down"), Rules.PLAYER_OWNER)
	var hengshan: Dictionary = Catalog.create_instance(
		&"HenShanJianZhen4",
		Rules.PLAYER_OWNER,
		&"hengshan_four"
	)
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [hengshan], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 8, &"hengshan_four")
	)
	var next_state: State = transition.get("state") as State
	_check(
		int((next_state.board[0] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER,
		"Tier four flips a corner enemy enclosed by both existing neighbors"
	)
	_check(
		_event_count(transition.get("events", []), &"card_flipped") == 1,
		"The enclosure action uses the normal non-attack flip pipeline"
	)


func _test_hengshan_four_respects_flip_prevention() -> void:
	var protected: Dictionary = _plain(&"protected_enemy")
	protected["active_abilities"] = [Catalog.normalize_ability(
		Catalog.TEMPORARY_FLIP_PROTECTION
	)]
	var board: Array = Rules.empty_board()
	board[0] = _slot(protected, Rules.OPPONENT_OWNER)
	board[1] = _slot(_plain(&"protect_right"), Rules.PLAYER_OWNER)
	board[3] = _slot(_plain(&"protect_down"), Rules.PLAYER_OWNER)
	var hengshan: Dictionary = Catalog.create_instance(
		&"HenShanJianZhen4",
		Rules.PLAYER_OWNER,
		&"protect_hengshan"
	)
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [hengshan], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 8, &"protect_hengshan")
	)
	var next_state: State = transition.get("state") as State
	_check(
		int((next_state.board[0] as Dictionary).get("owner", 0)) == Rules.OPPONENT_OWNER,
		"Enclosure flipping respects normal flip prevention"
	)
	_check(
		_event_count(transition.get("events", []), &"card_flip_prevented") == 1,
		"The generic flip request emits the established prevention event"
	)


func _test_repeated_hengshan_grants_do_not_stack() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(
		&"HenShanJianZhen2", Rules.PLAYER_OWNER, &"repeat_hengshan"
	), Rules.PLAYER_OWNER)
	board[1] = _slot(_plain(&"repeat_ally"), Rules.PLAYER_OWNER)
	var state := State.new(board)
	for _repeat: int in range(2):
		var groups: Array[Dictionary] = Triggers.discover(
			state,
			Catalog.TRIGGER_END_OWNER_TURN,
			{"turn_owner_id": Rules.PLAYER_OWNER}
		)
		for group: Dictionary in groups:
			Triggers.resolve_group(state, group)
	_check(_ability_count(state, 4) == 2, "Repeated turn ends do not stack the same self counter")
	_check(_ability_count(state, 1) == 1, "Repeated turn ends do not stack the same allied counter")


func _test_after_attack_uses_final_board_positions() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(
		&"TianChangZhang4", Rules.PLAYER_OWNER, &"range_counter"
	), Rules.PLAYER_OWNER)
	board[8] = _slot(_plain(&"moved_flip"), Rules.OPPONENT_OWNER)
	var state := State.new(board)
	var context: Dictionary = {
		"attacker_instance_id": &"enemy_attacker",
		"attacker_owner_id": Rules.OPPONENT_OWNER,
		"attack_flips": [{
			"instance_id": &"moved_flip",
			"previous_owner_id": Rules.PLAYER_OWNER,
		}],
	}
	_check(
		Triggers.discover(state, Catalog.TRIGGER_CARD_AFTER_ATTACK, context).is_empty(),
		"A flipped ally outside final attack range does not trigger the counter"
	)
	state.board[5] = state.board[8]
	state.board[8] = null
	_check(
		Triggers.discover(state, Catalog.TRIGGER_CARD_AFTER_ATTACK, context).size() == 1,
		"The exact flipped ally triggers after moving into final attack range"
	)


func _test_counterattacks_once_after_all_directions() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(
		&"TianChangZhang4", Rules.PLAYER_OWNER, &"multi_counter"
	), Rules.PLAYER_OWNER)
	board[1] = _slot(_plain(&"north_ally", [1, 1, 1, 1]), Rules.PLAYER_OWNER)
	board[3] = _slot(_plain(&"west_ally", [1, 1, 1, 1]), Rules.PLAYER_OWNER)
	var attacker: Dictionary = _plain(&"multi_attacker", [9, 9, 9, 9])
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [], [attacker], Rules.OPPONENT_OWNER),
		Action.make_play(0, 0, &"multi_attacker")
	)
	var next_state: State = transition.get("state") as State
	_check(
		int((next_state.board[1] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER
		and int((next_state.board[3] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER,
		"One counterattack reclaims both allies after the enemy finishes both directions"
	)
	_check(
		_ability_count(next_state, 4) == 1,
		"The one-use counter is consumed before its standard attack"
	)
	_check(
		_event_count(transition.get("events", []), &"ability_triggered") == 1,
		"Multiple qualifying flips trigger the counter ability only once"
	)


func _test_nested_counterattacks_consume_before_attacking() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(
		&"TianChangZhang4", Rules.PLAYER_OWNER, &"nested_player_counter"
	), Rules.PLAYER_OWNER)
	board[2] = _slot(Catalog.create_instance(
		&"TianChangZhang4", Rules.OPPONENT_OWNER, &"nested_enemy_counter"
	), Rules.OPPONENT_OWNER)
	board[5] = _slot(_plain(&"nested_ally", [1, 1, 1, 1]), Rules.PLAYER_OWNER)
	var attacker: Dictionary = _plain(&"nested_attacker", [9, 9, 9, 9])
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [], [attacker], Rules.OPPONENT_OWNER),
		Action.make_play(0, 8, &"nested_attacker")
	)
	var next_state: State = transition.get("state") as State
	_check(
		_event_count(transition.get("events", []), &"ability_triggered") == 2,
		"Two opposing counters each trigger once without recursive reuse"
	)
	_check(
		_ability_count(next_state, 4) == 1 and _ability_count(next_state, 2) == 1,
		"Both nested one-use counter abilities are consumed before their attacks"
	)
	_check(
		int((next_state.board[5] as Dictionary).get("owner", 0)) == Rules.OPPONENT_OWNER,
		"The second counterattack resolves after the first counter finishes"
	)
func _plain(instance_id: StringName, powers: Array[int] = [1, 1, 1, 1]) -> Dictionary:
	var card: Dictionary = Rules.make_card(
		String(instance_id),
		"测",
		powers,
		[],
		Rules.PLAYER_OWNER
	)
	card["instance_id"] = instance_id
	return card


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	card["original_owner"] = owner_id
	return {"card": card, "owner": owner_id}


func _ability_count(state: State, cell: int) -> int:
	if state == null or state.board[cell] == null:
		return -1
	var card: Dictionary = (state.board[cell] as Dictionary).get("card", {})
	return (card.get("active_abilities", []) as Array).size()


func _event_count(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for event_value: Variant in events:
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
		):
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
