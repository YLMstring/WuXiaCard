extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Executor = preload("res://tests/helpers/duel_native_action_test_harness.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_twentieth_special_summon_succeeds()
	_test_twenty_first_special_summon_is_skipped_only()
	_test_owner_counters_are_independent()
	_test_blocked_resummon_preserves_original_instance()
	_test_normal_hand_play_is_exempt_and_turn_boundary_resets_both()
	if _failures == 0:
		print("SPECIAL_SUMMON_TURN_CAP_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"SPECIAL_SUMMON_TURN_CAP_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_twentieth_special_summon_succeeds() -> void:
	var state: State = _selected_hand_summon_state(
		Rules.PLAYER_OWNER,
		&"twentieth_source",
		&"twentieth_target"
	)
	state.special_summons_by_owner[Rules.PLAYER_OWNER] = Simulator.MAX_SPECIAL_SUMMONS_PER_OWNER_TURN - 1
	var result: Dictionary = _summon_selected_hand_card(
		state,
		Rules.PLAYER_OWNER,
		&"twentieth_source",
		&"twentieth_target"
	)
	_check(
		StringName(result.get("result", &"")) == Catalog.ACTION_RESULT_APPLIED,
		"The twentieth special summon is applied"
	)
	_check(_instance_at(state, 1) == &"twentieth_target", "The twentieth card enters the board")
	_check(
		int(state.special_summons_by_owner.get(Rules.PLAYER_OWNER, -1)) == Simulator.MAX_SPECIAL_SUMMONS_PER_OWNER_TURN,
		"A successful special summon increments its resulting owner's counter"
	)


func _test_twenty_first_special_summon_is_skipped_only() -> void:
	var state: State = _selected_hand_summon_state(
		Rules.PLAYER_OWNER,
		&"blocked_source",
		&"blocked_target"
	)
	state.special_summons_by_owner[Rules.PLAYER_OWNER] = Simulator.MAX_SPECIAL_SUMMONS_PER_OWNER_TURN
	var result: Dictionary = Executor.execute_actions(
		state,
		4,
		&"blocked_source",
		Rules.PLAYER_OWNER,
		[
			_summon_selected_action(),
			{
				"type": Catalog.ACTION_CHANGE_POWERS,
				"amount": 1,
				"card": Catalog.CARD_REF_ABILITY_SOURCE,
			},
		],
		{"selected_card_instance_id": &"blocked_target"}
	)
	_check(
		StringName(result.get("result", &"")) == Catalog.ACTION_RESULT_APPLIED,
		"A later action still applies after a capped summon is skipped"
	)
	_check(_instance_at(state, 1) == &"", "The capped summon does not occupy its destination")
	_check(_hand_has(state, Rules.PLAYER_OWNER, &"blocked_target"), "The capped card remains in its source zone")
	_check(
		_card_at(state, 4).get("powers", []) == [3, 3, 3, 3],
		"The action batch continues after the capped summon"
	)
	_check(
		_count_events(result.get("events", []), &"card_summoned") == 0,
		"The capped summon emits no summon event"
	)
	_check(
		int(state.special_summons_by_owner.get(Rules.PLAYER_OWNER, -1)) == Simulator.MAX_SPECIAL_SUMMONS_PER_OWNER_TURN,
		"A capped summon does not increment the counter"
	)


func _test_owner_counters_are_independent() -> void:
	var state: State = _selected_hand_summon_state(
		Rules.OPPONENT_OWNER,
		&"opponent_source",
		&"opponent_target"
	)
	state.special_summons_by_owner = {
		Rules.PLAYER_OWNER: Simulator.MAX_SPECIAL_SUMMONS_PER_OWNER_TURN,
		Rules.OPPONENT_OWNER: Simulator.MAX_SPECIAL_SUMMONS_PER_OWNER_TURN - 1,
	}
	_summon_selected_hand_card(
		state,
		Rules.OPPONENT_OWNER,
		&"opponent_source",
		&"opponent_target"
	)
	_check(_instance_at(state, 1) == &"opponent_target", "One owner's cap does not block the other owner")
	_check(
		state.special_summons_by_owner == {
			Rules.PLAYER_OWNER: Simulator.MAX_SPECIAL_SUMMONS_PER_OWNER_TURN,
			Rules.OPPONENT_OWNER: Simulator.MAX_SPECIAL_SUMMONS_PER_OWNER_TURN,
		},
		"Special summon counters advance independently"
	)


func _test_blocked_resummon_preserves_original_instance() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(_plain(&"resummon_source", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[0] = _slot(_plain(&"resummon_target", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var state := State.new(board)
	state.special_summons_by_owner[Rules.PLAYER_OWNER] = Simulator.MAX_SPECIAL_SUMMONS_PER_OWNER_TURN
	var result: Dictionary = Executor.execute_actions(
		state,
		4,
		&"resummon_source",
		Rules.PLAYER_OWNER,
		[{
			"type": Catalog.ACTION_RESUMMON_CARD_IN_PLACE,
			"card": Catalog.CARD_REF_TRIGGER_CARD,
		}],
		{"trigger_instance_id": &"resummon_target"}
	)
	_check(
		StringName(result.get("result", &"")) == Catalog.ACTION_RESULT_NO_EFFECT,
		"A capped in-place resummon has no effect"
	)
	_check(_instance_at(state, 0) == &"resummon_target", "A capped resummon leaves the same instance on board")
	_check(
		_count_events(result.get("events", []), &"card_departed_for_resummon") == 0
		and _count_events(result.get("events", []), &"card_summoned") == 0,
		"A capped resummon emits neither departure nor summon events"
	)


func _test_normal_hand_play_is_exempt_and_turn_boundary_resets_both() -> void:
	var hand_card: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan",
		Rules.PLAYER_OWNER,
		&"ordinary_hand_play"
	)
	var opponent_card: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan",
		Rules.OPPONENT_OWNER,
		&"ordinary_reply"
	)
	var state := State.new(
		Rules.empty_board(),
		[hand_card],
		[opponent_card],
		Rules.PLAYER_OWNER
	)
	state.special_summons_by_owner = {
		Rules.PLAYER_OWNER: Simulator.MAX_SPECIAL_SUMMONS_PER_OWNER_TURN,
		Rules.OPPONENT_OWNER: 7,
	}
	var transition: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, 4, &"ordinary_hand_play")
	)
	var next_state: State = transition.get("state") as State
	_check(bool(transition.get("valid", false)), "An ordinary hand play remains legal at the special summon cap")
	_check(_instance_at(next_state, 4) == &"ordinary_hand_play", "The exempt hand card enters normally")
	_check(
		next_state.special_summons_by_owner == {
			Rules.PLAYER_OWNER: 0,
			Rules.OPPONENT_OWNER: 0,
		},
		"The real turn boundary resets both owners' special summon counters"
	)


func _selected_hand_summon_state(
	owner_id: int,
	source_instance_id: StringName,
	target_instance_id: StringName
) -> State:
	var board: Array = Rules.empty_board()
	board[4] = _slot(_plain(source_instance_id, owner_id, [2, 2, 2, 2]), owner_id)
	var target: Dictionary = _plain(target_instance_id, owner_id)
	return State.new(
		board,
		[target] if owner_id == Rules.PLAYER_OWNER else [],
		[target] if owner_id == Rules.OPPONENT_OWNER else [],
		owner_id
	)


func _summon_selected_hand_card(
	state: State,
	owner_id: int,
	source_instance_id: StringName,
	target_instance_id: StringName
) -> Dictionary:
	return Executor.execute_actions(
		state,
		4,
		source_instance_id,
		owner_id,
		[_summon_selected_action()],
		{"selected_card_instance_id": target_instance_id}
	)


func _summon_selected_action() -> Dictionary:
	return {
		"type": Catalog.ACTION_SUMMON_CARD,
		"card": Catalog.CARD_REF_SELECTED_CARD,
		"cell": {
			"type": Catalog.CELL_REF_FIRST_ADJACENT_EMPTY,
			"card": Catalog.CARD_REF_ABILITY_SOURCE,
		},
	}


func _plain(
	instance_id: StringName,
	owner_id: int,
	powers: Array[int] = [1, 1, 1, 1]
) -> Dictionary:
	var card: Dictionary = Rules.make_card(String(instance_id), "测", powers, [], owner_id)
	card["instance_id"] = instance_id
	return card


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"owner": owner_id, "card": card}


func _card_at(state: State, cell: int) -> Dictionary:
	if state == null or cell < 0 or cell >= state.board.size():
		return {}
	var slot_value: Variant = state.board[cell]
	if not slot_value is Dictionary:
		return {}
	return (slot_value as Dictionary).get("card", {}) as Dictionary


func _instance_at(state: State, cell: int) -> StringName:
	return StringName(_card_at(state, cell).get("instance_id", &""))


func _hand_has(state: State, owner_id: int, instance_id: StringName) -> bool:
	for card_value: Variant in state.get_hand(owner_id):
		if (
			card_value is Dictionary
			and StringName((card_value as Dictionary).get("instance_id", &"")) == instance_id
		):
			return true
	return false


func _count_events(events: Array, event_type: StringName) -> int:
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
