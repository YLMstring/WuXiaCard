extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")
const Triggers = preload("res://scripts/duel_triggers.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_removing_an_earlier_ability_does_not_stale_a_later_trigger()
	_test_replacing_the_ability_does_not_inherit_an_old_trigger()
	_test_moved_trigger_card_preserves_own_discovered_trigger()
	if _failures == 0:
		print("DUEL_TRIGGER_REVALIDATION_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"DUEL_TRIGGER_REVALIDATION_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_removing_an_earlier_ability_does_not_stale_a_later_trigger() -> void:
	var state: State = _make_state()
	var groups: Array[Dictionary] = Triggers.discover(
		state,
		Catalog.TRIGGER_CARD_AFTER_SUMMONED,
		_context()
	)
	_check(groups.size() == 2, "Both same-card abilities are snapshotted before resolution")
	var events: Array = []
	events.append_array((Triggers.resolve_group(state, groups[0]).get("events", []) as Array))
	events.append_array((Triggers.resolve_group(state, groups[1]).get("events", []) as Array))
	_check(
		_event_types(events)
		== [&"ability_triggered", &"ability_lost", &"ability_triggered", &"card_drawn"],
		"Removing an earlier ability does not cancel a later snapshotted trigger after it shifts"
	)
	_check(
		state.get_hand(Rules.PLAYER_OWNER).size() == 1,
		"The shifted later ability still applies its action"
	)


func _test_replacing_the_ability_does_not_inherit_an_old_trigger() -> void:
	var state: State = _make_state()
	var groups: Array[Dictionary] = Triggers.discover(
		state,
		Catalog.TRIGGER_CARD_AFTER_SUMMONED,
		_context()
	)
	var card: Dictionary = (state.board[4] as Dictionary).get("card", {})
	var abilities: Array = card.get("active_abilities", [])
	abilities = abilities.duplicate(false)
	abilities.remove_at(1)
	abilities.append(_draw_ability())
	card["active_abilities"] = abilities
	var result: Dictionary = Triggers.resolve_group(state, groups[1])
	_check(
		(result.get("events", []) as Array).is_empty(),
		"A newly inserted equal declaration does not inherit the removed entry's old trigger"
	)
	_check(
		state.get_hand(Rules.PLAYER_OWNER).is_empty(),
		"A stale trigger cannot apply the replacement ability's action"
	)


func _test_moved_trigger_card_preserves_own_discovered_trigger() -> void:
	var state: State = _make_state()
	var groups: Array[Dictionary] = Triggers.discover(
		state,
		Catalog.TRIGGER_CARD_AFTER_SUMMONED,
		_context()
	)
	state.board[5] = state.board[4]
	state.board[4] = null
	var result: Dictionary = Triggers.resolve_group(state, groups[1])
	_check(
		_event_types(result.get("events", [])) == [&"ability_triggered", &"card_drawn"],
		"An already-discovered self trigger follows its exact card instance after board movement"
	)
	_check(
		state.get_hand(Rules.PLAYER_OWNER).size() == 1,
		"The moved card resolves its self-trigger actions from the new cell"
	)


func _make_state() -> State:
	var source: Dictionary = Rules.make_card(
		"Trigger Source",
		"触",
		[1, 1, 1, 1],
		[_remove_self_ability(), _draw_ability()],
		Rules.PLAYER_OWNER
	)
	source["instance_id"] = &"trigger_source"
	source["ki"] = 0
	var drawn: Dictionary = Rules.make_card(
		"Drawn",
		"抽",
		[1, 1, 1, 1],
		[],
		Rules.PLAYER_OWNER
	)
	drawn["instance_id"] = &"trigger_drawn"
	drawn["ki"] = 0
	var board: Array = Rules.empty_board()
	board[4] = {"owner": Rules.PLAYER_OWNER, "card": source}
	return State.new(board, [], [], Rules.PLAYER_OWNER, 0, [drawn], [])


func _context() -> Dictionary:
	return {
		"trigger_cell": 4,
		"trigger_instance_id": &"trigger_source",
		"trigger_owner_id": Rules.PLAYER_OWNER,
		"summon_reason": &"hand_play",
	}


func _remove_self_ability() -> Dictionary:
	return {
		"retained_on_flip": false,
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_REMOVE_THIS_ABILITY}],
		}],
	}


func _draw_ability() -> Dictionary:
	return {
		"retained_on_flip": false,
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1}],
		}],
	}


func _event_types(events: Array) -> Array[StringName]:
	var types: Array[StringName] = []
	for event_value: Variant in events:
		types.append(StringName((event_value as Dictionary).get("type", &"")))
	return types


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
