extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const NativeRules = preload("res://scripts/duel_native_rules.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_removing_an_earlier_ability_does_not_stale_a_later_trigger()
	_test_source_move_within_board_tracks_new_cell()
	_test_source_owner_change_uses_current_owner()
	_test_source_zone_change_cancels_later_trigger()
	_test_ordinary_events_do_not_scan_hands()
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
	var result: Dictionary = NativeRules.resolve_event(
		state,
		Catalog.TRIGGER_CARD_AFTER_SUMMONED,
		_context()
	)
	var events: Array = result.get("events", [])
	_check(
		_event_types(events)
		== [&"ability_triggered", &"ability_lost", &"ability_triggered", &"card_drawn"],
		"Removing an earlier ability does not cancel a later snapshotted trigger after it shifts"
	)
	_check(
		state.get_hand(Rules.PLAYER_OWNER).size() == 1,
		"The shifted later ability still applies its action"
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


func _test_source_move_within_board_tracks_new_cell() -> void:
	var move_ability: Dictionary = {
		"retained_on_flip": false,
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"actions": [{"type": Catalog.ACTION_SWAP_SELF_WITH_TRIGGER_CARD}],
		}],
	}
	var source: Dictionary = _card(&"moving_source", [
		move_ability,
		_draw_without_condition(false, Catalog.TRIGGER_CARD_AFTER_SUMMONED),
	], Rules.PLAYER_OWNER)
	var trigger: Dictionary = _card(&"moving_trigger", [], Rules.OPPONENT_OWNER)
	var drawn: Dictionary = _card(&"moving_drawn", [], Rules.PLAYER_OWNER)
	var board: Array = Rules.empty_board()
	board[1] = {"owner": Rules.OPPONENT_OWNER, "card": trigger}
	board[4] = {"owner": Rules.PLAYER_OWNER, "card": source}
	var state := State.new(board, [], [], Rules.PLAYER_OWNER, 0, [drawn], [])
	var result: Dictionary = NativeRules.resolve_event(state, Catalog.TRIGGER_CARD_AFTER_SUMMONED, {
		"trigger_cell": 1,
		"trigger_instance_id": &"moving_trigger",
		"trigger_owner_id": Rules.OPPONENT_OWNER,
	})
	_check(bool(result.get("valid", false)), "Moved-source trigger chain resolves")
	_check(
		StringName(((state.board[1] as Dictionary).get("card", {}) as Dictionary).get("instance_id", &"")) == &"moving_source",
		"Source moves to the trigger's former cell"
	)
	_check(state.get_hand(Rules.PLAYER_OWNER).size() == 1, "Later trigger follows its source within the board and draws")


func _test_source_owner_change_uses_current_owner() -> void:
	var flip_ability: Dictionary = {
		"retained_on_flip": true,
		"triggers": [{
			"event": Catalog.TRIGGER_END_OWNER_TURN,
			"actions": [{
				"type": Catalog.ACTION_FLIP_SELF,
				"new_owner": Catalog.OWNER_OPPONENT_OF_CARD_CURRENT,
			}],
		}],
	}
	var source: Dictionary = _card(&"owner_change_source", [flip_ability, _draw_without_condition(true)], Rules.PLAYER_OWNER)
	var player_draw: Dictionary = _card(&"player_draw", [], Rules.PLAYER_OWNER)
	var opponent_draw: Dictionary = _card(&"opponent_draw", [], Rules.OPPONENT_OWNER)
	var board: Array = Rules.empty_board()
	board[4] = {"owner": Rules.PLAYER_OWNER, "card": source}
	var state := State.new(board, [], [], Rules.PLAYER_OWNER, 0, [player_draw], [opponent_draw])
	var result: Dictionary = NativeRules.resolve_event(state, Catalog.TRIGGER_END_OWNER_TURN, {
		"turn_owner_id": Rules.PLAYER_OWNER,
	})
	_check(bool(result.get("valid", false)), "Owner-changing trigger chain resolves")
	_check(int((state.board[4] as Dictionary).get("owner", 0)) == Rules.OPPONENT_OWNER, "First trigger changes the source owner")
	_check(state.get_hand(Rules.OPPONENT_OWNER).size() == 1, "Later trigger draws for the source's current owner")
	_check(state.get_hand(Rules.PLAYER_OWNER).is_empty(), "Later trigger no longer uses the discovery-time owner")


func _test_source_zone_change_cancels_later_trigger() -> void:
	var exile_ability: Dictionary = {
		"retained_on_flip": false,
		"triggers": [{
			"event": Catalog.TRIGGER_END_OWNER_TURN,
			"actions": [{"type": Catalog.ACTION_EXILE_SELF}],
		}],
	}
	var source: Dictionary = _card(&"zone_change_source", [exile_ability, _draw_without_condition(false)], Rules.PLAYER_OWNER)
	var drawn: Dictionary = _card(&"zone_change_drawn", [], Rules.PLAYER_OWNER)
	var board: Array = Rules.empty_board()
	board[4] = {"owner": Rules.PLAYER_OWNER, "card": source}
	var state := State.new(board, [], [], Rules.PLAYER_OWNER, 0, [drawn], [])
	NativeRules.resolve_event(state, Catalog.TRIGGER_END_OWNER_TURN, {"turn_owner_id": Rules.PLAYER_OWNER})
	_check(state.get_hand(Rules.PLAYER_OWNER).is_empty(), "Cross-zone source movement cancels its later trigger")


func _test_ordinary_events_do_not_scan_hands() -> void:
	var hand_ability: Dictionary = {
		"retained_on_flip": false,
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_ATTACK,
			"actions": [{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1}],
		}],
	}
	var source: Dictionary = _card(&"ignored_hand_source", [hand_ability], Rules.PLAYER_OWNER)
	var drawn: Dictionary = _card(&"ignored_hand_drawn", [], Rules.PLAYER_OWNER)
	var state := State.new(Rules.empty_board(), [source], [], Rules.PLAYER_OWNER, 0, [drawn], [])
	NativeRules.resolve_event(state, Catalog.TRIGGER_CARD_AFTER_ATTACK, {})
	_check(state.get_hand(Rules.PLAYER_OWNER).size() == 1, "Ordinary events do not discover abilities in hand")


func _draw_without_condition(
	retained: bool,
	event_id: StringName = Catalog.TRIGGER_END_OWNER_TURN
) -> Dictionary:
	return {
		"retained_on_flip": retained,
		"triggers": [{
			"event": event_id,
			"actions": [{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1}],
		}],
	}


func _card(instance_id: StringName, abilities: Array, owner_id: int) -> Dictionary:
	var card: Dictionary = Rules.make_card(
		String(instance_id),
		String(instance_id),
		[1, 1, 1, 1],
		abilities,
		owner_id,
		instance_id
	)
	card["instance_id"] = instance_id
	card["ki"] = 0
	return card


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
