extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_consecutive_action_grants_are_capped()
	_test_action_grant_blocks_kuihua_end_turn_grant()
	_test_simultaneous_kuihua_requests_coalesce()
	if _failures == 0:
		print("EXTRA_PLAY_TURN_CAP_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"EXTRA_PLAY_TURN_CAP_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_consecutive_action_grants_are_capped() -> void:
	var state := State.new(
		Rules.empty_board(),
		[
			_card(&"DuGu9Jian3", Rules.PLAYER_OWNER, &"cap_break_first"),
			_card(&"DuGu9Jian3", Rules.PLAYER_OWNER, &"cap_break_second"),
			_card(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"cap_followup"),
		],
		[_card(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"cap_enemy_reply")],
		Rules.PLAYER_OWNER,
		0,
		[
			_card(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"cap_draw_first"),
			_card(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"cap_draw_second"),
		]
	)
	var first: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, 4, &"cap_break_first")
	)
	var after_first: State = first.get("state") as State
	_check(bool(first.get("valid", false)), "First extra-play source resolves")
	_check(
		_count_events(first.get("events", []), &"extra_card_play_granted") == 1
		and after_first.extra_card_plays_remaining == 1
		and after_first.extra_card_play_granted_this_turn,
		"First request grants and consumes the turn allowance"
	)

	var second_index: int = _hand_index(after_first, &"cap_break_second")
	var second: Dictionary = Simulator.apply_action(
		after_first,
		Action.make_play(second_index, 4, &"cap_break_second")
	)
	var after_second: State = second.get("state") as State
	_check(bool(second.get("valid", false)), "Granted hand play resolves")
	_check(
		_count_events(second.get("events", []), &"extra_card_play_granted") == 0
		and after_second.extra_card_plays_remaining == 0,
		"A consecutive request in the same turn has no effect"
	)
	_check(
		after_second.active_player == Rules.OPPONENT_OWNER
		and not after_second.extra_card_play_granted_this_turn,
		"Completing the actual owner turn resets the allowance"
	)


func _test_action_grant_blocks_kuihua_end_turn_grant() -> void:
	var board: Array = Rules.empty_board()
	board[0] = {
		"owner": Rules.PLAYER_OWNER,
		"card": _card(&"KuiHua1", Rules.PLAYER_OWNER, &"cap_kuihua"),
	}
	var state := State.new(
		board,
		[
			_card(&"DuGu9Jian3", Rules.PLAYER_OWNER, &"cap_kuihua_break"),
			_card(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"cap_kuihua_followup"),
		],
		[_card(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"cap_kuihua_enemy")],
		Rules.PLAYER_OWNER,
		0,
		[_card(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"cap_kuihua_draw")]
	)
	state.enabled_effect_gates_by_owner[Rules.PLAYER_OWNER] = [
		Catalog.EFFECT_GATE_SELF_CASTRATION,
	]
	var first: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, 4, &"cap_kuihua_break")
	)
	var after_first: State = first.get("state") as State
	_check(
		_count_events(first.get("events", []), &"extra_card_play_granted") == 1,
		"Action effect obtains the turn's single extra play"
	)
	var followup_index: int = _hand_index(after_first, &"cap_kuihua_followup")
	var second: Dictionary = Simulator.apply_action(
		after_first,
		Action.make_play(followup_index, 4, &"cap_kuihua_followup")
	)
	var after_second: State = second.get("state") as State
	_check(
		_count_events(second.get("events", []), &"extra_card_play_granted") == 0,
		"KuiHua1's later end-turn request cannot extend the same turn"
	)
	_check(
		after_second.active_player == Rules.OPPONENT_OWNER,
		"The owner turn closes after its one granted play"
	)


func _test_simultaneous_kuihua_requests_coalesce() -> void:
	var board: Array = Rules.empty_board()
	board[0] = {
		"owner": Rules.PLAYER_OWNER,
		"card": _card(&"KuiHua1", Rules.PLAYER_OWNER, &"cap_kuihua_left"),
	}
	board[8] = {
		"owner": Rules.PLAYER_OWNER,
		"card": _card(&"KuiHua1", Rules.PLAYER_OWNER, &"cap_kuihua_right"),
	}
	var state := State.new(
		board,
		[
			_card(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"cap_kuihua_play"),
			_card(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"cap_kuihua_extra"),
		],
		[_card(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"cap_kuihua_reply")],
		Rules.PLAYER_OWNER
	)
	state.enabled_effect_gates_by_owner[Rules.PLAYER_OWNER] = [
		Catalog.EFFECT_GATE_SELF_CASTRATION,
	]
	var transition: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, 4, &"cap_kuihua_play")
	)
	var next_state: State = transition.get("state") as State
	var grant_events: Array[Dictionary] = _events_of_type(
		transition.get("events", []),
		&"extra_card_play_granted"
	)
	_check(grant_events.size() == 1, "Simultaneous requests emit one grant event")
	if grant_events.size() == 1:
		_check(
			int(grant_events[0].get("amount", 0)) == 1
			and int(grant_events[0].get("request_count", 0)) == 2,
			"The single grant records both requesting sources"
		)
	_check(
		next_state.extra_card_plays_remaining == 1
		and next_state.extra_card_play_granted_this_turn,
		"Simultaneous requests still create only one pending play"
	)


func _card(card_id: StringName, owner_id: int, instance_id: StringName) -> Dictionary:
	return Catalog.create_instance(card_id, owner_id, instance_id)


func _hand_index(state: State, instance_id: StringName) -> int:
	var hand: Array = state.get_hand(Rules.PLAYER_OWNER)
	for index: int in range(hand.size()):
		if StringName((hand[index] as Dictionary).get("instance_id", &"")) == instance_id:
			return index
	return -1


func _count_events(events: Array, event_type: StringName) -> int:
	return _events_of_type(events, event_type).size()


func _events_of_type(events: Array, event_type: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event_value: Variant in events:
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
		):
			result.append(event_value as Dictionary)
	return result


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
