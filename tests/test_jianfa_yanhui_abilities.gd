extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_jianfa_entry_uses_lowest_qualifying_cell()
	_test_jianfa_activation_grants_only_an_extra_play()
	_test_yanhui_replaces_itself_with_exact_leftmost_light_sword()
	_test_yanhui_four_returns_other_ally_and_summons_copy()
	if _failures == 0:
		print("JIANFA_YANHUI_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"JIANFA_YANHUI_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_jianfa_entry_uses_lowest_qualifying_cell() -> void:
	var board: Array = Rules.empty_board()
	board[2] = _slot(_plain(&"right_enemy", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[6] = _slot(_plain(&"lower_enemy", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var source: Dictionary = Catalog.create_instance(
		&"JianFaQinYin1", Rules.PLAYER_OWNER, &"jianfa_entry"
	)
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [source], [_plain(&"reply", Rules.OPPONENT_OWNER)], Rules.PLAYER_OWNER),
		Action.make_play(0, 0, &"jianfa_entry")
	)
	var next_state: State = transition.get("state") as State
	_check(_instance_at(next_state, 1) == &"jianfa_entry", "Entry movement chooses cell 1 before cell 3")
	_check(_count_events(transition.get("events", []), &"card_moved") == 1, "Entry movement emits one movement event")


func _test_jianfa_activation_grants_only_an_extra_play() -> void:
	var board: Array = Rules.empty_board()
	var source: Dictionary = Catalog.create_instance(
		&"JianFaQinYin3", Rules.PLAYER_OWNER, &"jianfa_activate"
	)
	var enemy: Dictionary = Catalog.create_instance(
		&"CangSongYingKe2", Rules.OPPONENT_OWNER, &"suppressed_enemy"
	)
	board[0] = _slot(source, Rules.PLAYER_OWNER)
	board[2] = _slot(enemy, Rules.OPPONENT_OWNER)
	var state := State.new(
		board,
		[_plain(&"extra_play", Rules.PLAYER_OWNER)],
		[_plain(&"reply", Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER
	)
	var transition: Dictionary = Simulator.apply_action(
		state,
		Action.make_activate(0, &"jianfa_activate", Action.TARGET_BOARD_CELL, 1)
	)
	var next_state: State = transition.get("state") as State
	_check(_instance_at(next_state, 1) == &"jianfa_activate", "Activation moves JianFa before granting a play")
	_check(next_state.active_player == Rules.PLAYER_OWNER and next_state.extra_card_plays_remaining == 1, "Activation grants one pending card play")
	_check(((_card_at(next_state, 2).get("active_abilities", [])) as Array).is_empty(), "Enemy beside JianFa's new cell stays suppressed during the extra play")
	var legal_actions: Array = Simulator.get_legal_actions(next_state)
	_check(not legal_actions.is_empty(), "The pending extra play has legal actions")
	for legal_action: Action in legal_actions:
		_check(legal_action.action_type == Action.TYPE_PLAY, "Only hand plays are legal during the extra-play window")
	var finish_transition: Dictionary = Simulator.apply_action(
		next_state,
		Action.make_play(0, 3, &"extra_play")
	)
	var finished: State = finish_transition.get("state") as State
	_check(finished.extra_card_plays_remaining == 0, "The extra-play allowance is consumed")
	_check(not ((_card_at(finished, 2).get("active_abilities", [])) as Array).is_empty(), "Suppressed abilities restore only after the owner turn closes")


func _test_yanhui_replaces_itself_with_exact_leftmost_light_sword() -> void:
	var board: Array = Rules.empty_board()
	var yanhui: Dictionary = Catalog.create_instance(
		&"YanHuiZhuRong3", Rules.OPPONENT_OWNER, &"yanhui_target"
	)
	board[5] = _slot(yanhui, Rules.OPPONENT_OWNER)
	var attacker: Dictionary = _plain(&"attacker", Rules.PLAYER_OWNER)
	attacker["powers"] = [1, 9, 1, 1]
	var left_light: Dictionary = Catalog.create_instance(
		&"JianFaQinYin1", Rules.OPPONENT_OWNER, &"left_light"
	)
	var right_light: Dictionary = Catalog.create_instance(
		&"TianZhuYunQi2", Rules.OPPONENT_OWNER, &"right_light"
	)
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [attacker], [left_light, right_light], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"attacker")
	)
	var next_state: State = transition.get("state") as State
	_check(_instance_at(next_state, 5) == &"left_light", "YanHui plays the exact leftmost light-sword instance")
	_check(_hand_contains_card(next_state, Rules.OPPONENT_OWNER, &"YanHuiZhuRong3"), "YanHui returns to its owner's hand as a fresh copy")
	_check(_hand_contains_instance(next_state, Rules.OPPONENT_OWNER, &"right_light"), "Later light-sword cards remain in hand")
	_check(_count_events(transition.get("events", []), &"card_flipped") == 0, "Replacing the attacked target prevents that attack flip")


func _test_yanhui_four_returns_other_ally_and_summons_copy() -> void:
	var board: Array = Rules.empty_board()
	var source: Dictionary = Catalog.create_instance(
		&"YanHuiZhuRong4", Rules.PLAYER_OWNER, &"yanhui_source"
	)
	var ally: Dictionary = Catalog.create_instance(
		&"JianFaQinYin1", Rules.PLAYER_OWNER, &"returned_ally"
	)
	board[4] = _slot(source, Rules.PLAYER_OWNER)
	board[5] = _slot(ally, Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [], [_plain(&"reply", Rules.OPPONENT_OWNER)], Rules.PLAYER_OWNER),
		Action.make_activate(4, &"yanhui_source", Action.TARGET_BOARD_CELL, 5)
	)
	var next_state: State = transition.get("state") as State
	_check(_instance_at(next_state, 4) == &"yanhui_source", "YanHui remains in its own cell")
	_check(StringName(_card_at(next_state, 5).get("card_id", &"")) == &"YanHuiZhuRong4", "A fresh YanHui copy is summoned in the ally's initial cell")
	_check(_hand_contains_card(next_state, Rules.PLAYER_OWNER, &"JianFaQinYin1"), "The selected ally returns to the ability source owner's hand")


func _plain(instance_id: StringName, owner_id: int) -> Dictionary:
	var card: Dictionary = Catalog.create_instance(&"CangSongYingKe1", owner_id, instance_id)
	card["powers"] = [1, 1, 1, 1]
	return card


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _card_at(state: State, cell: int) -> Dictionary:
	if state.board[cell] == null:
		return {}
	return (state.board[cell] as Dictionary).get("card", {}) as Dictionary


func _instance_at(state: State, cell: int) -> StringName:
	return StringName(_card_at(state, cell).get("instance_id", &""))


func _hand_contains_instance(state: State, owner_id: int, instance_id: StringName) -> bool:
	for card_value: Variant in state.get_hand(owner_id):
		if StringName((card_value as Dictionary).get("instance_id", &"")) == instance_id:
			return true
	return false


func _hand_contains_card(state: State, owner_id: int, card_id: StringName) -> bool:
	for card_value: Variant in state.get_hand(owner_id):
		if StringName((card_value as Dictionary).get("card_id", &"")) == card_id:
			return true
	return false


func _count_events(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for event_value: Variant in events:
		if StringName((event_value as Dictionary).get("type", &"")) == event_type:
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
