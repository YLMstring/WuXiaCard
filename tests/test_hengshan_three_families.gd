extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Abilities = preload("res://scripts/duel_abilities.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Executor = preload("res://scripts/duel_ability_executor.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_vocabulary()
	_test_card_declarations()
	_test_yunwu_suppresses_summon_reactions_then_restores()
	_test_yijian_two_swaps_with_its_only_direct_flip()
	_test_yijian_three_attacks_after_the_swap()
	_test_yijian_three_stops_when_the_flip_is_no_longer_adjacent()
	_test_tianzhu_three_moves_then_draws()
	_test_tianzhu_four_suppresses_before_external_movement()
	_test_temporary_suppression_retains_permanent_abilities_and_new_grants()
	_test_flipping_while_suppressed_permanently_erases_the_stored_ability()
	if _failures == 0:
		print("HENGSHAN_THREE_FAMILIES_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"HENGSHAN_THREE_FAMILIES_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_catalog_vocabulary() -> void:
	for event_id: StringName in [
		Catalog.TRIGGER_CARD_BEFORE_SUMMONED,
		Catalog.CARD_BEFORE_MOVED,
	]:
		_check(event_id in Catalog.KNOWN_TRIGGER_EVENTS, "%s is a known trigger event" % event_id)
	for condition_id: StringName in [
		Catalog.CONDITION_MOVING_CARD_IS_SELF,
		Catalog.CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE,
		Catalog.CONDITION_SOURCE_HAS_ADJACENT_EMPTY_CELL,
	]:
		_check(
			condition_id in Catalog.KNOWN_TRIGGER_CONDITIONS,
			"%s is a known trigger condition" % condition_id
		)
	_check(
		Catalog.CONDITION_SELECTED_CARD_FLIPPED_BY_CURRENT_ATTACK
		in Catalog.KNOWN_SELECTOR_CONDITIONS,
		"The direct-attack-flip selector condition is registered"
	)
	for action_id: StringName in [
		Catalog.ACTION_TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES,
		Catalog.ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY,
	]:
		_check(action_id in Catalog.KNOWN_ACTIONS, "%s is a known action" % action_id)


func _test_card_declarations() -> void:
	_check(Catalog.validate_catalog().is_empty(), "The complete card catalog validates")
	var expected_counts: Dictionary = {
		&"YunWu13Shi2": 1,
		&"YunWu13Shi3": 2,
		&"YiJianLuo9Yan1": 0,
		&"YiJianLuo9Yan2": 1,
		&"YiJianLuo9Yan3": 1,
		&"TianZhuYunQi2": 1,
		&"TianZhuYunQi3": 1,
		&"TianZhuYunQi4": 2,
	}
	for card_id: StringName in expected_counts:
		var abilities: Array = Catalog.get_definition(card_id).get("abilities", [])
		_check(
			abilities.size() == int(expected_counts[card_id]),
			"%s declares the approved ability count" % card_id
		)


func _test_yunwu_suppresses_summon_reactions_then_restores() -> void:
	var reacting_enemy: Dictionary = Catalog.create_instance(
		&"CangSongYingKe2", Rules.OPPONENT_OWNER, &"yunwu_reactor"
	)
	reacting_enemy["powers"] = [9, 9, 9, 9]
	var board: Array = Rules.empty_board()
	board[1] = _slot(reacting_enemy, Rules.OPPONENT_OWNER)
	var yunwu: Dictionary = Catalog.create_instance(
		&"YunWu13Shi2", Rules.PLAYER_OWNER, &"yunwu_two"
	)
	var transition: Dictionary = Simulator.apply_action_oracle(
		State.new(board, [yunwu], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"yunwu_two")
	)
	var next_state: State = transition.get("state") as State
	_check(
		int((next_state.board[4] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER,
		"The suppressed enemy cannot react to YunWu entering"
	)
	_check(
		_ability_count(next_state, &"yunwu_reactor") == 1,
		"The enemy ability returns after the current turn ends"
	)
	_check(
		_event_index(transition.get("events", []), &"ability_lost")
		< _event_index(transition.get("events", []), &"card_placed")
		and _event_index(transition.get("events", []), &"ability_gained")
		> _event_index(transition.get("events", []), &"card_placed"),
		"Suppression happens before summon reactions and restoration happens at turn end"
	)
	var loss_event: Dictionary = _first_event(transition.get("events", []), &"ability_lost")
	_check(
		StringName(loss_event.get("source_instance_id", &"")) == &"yunwu_two"
		and StringName(loss_event.get("instance_id", &"")) == &"yunwu_reactor",
		"Temporary suppression records YunWu as the external source of the ability loss"
	)


func _test_yijian_two_swaps_with_its_only_direct_flip() -> void:
	var enemy: Dictionary = _plain(&"yijian_two_enemy", [1, 1, 1, 1])
	var board: Array = Rules.empty_board()
	board[5] = _slot(enemy, Rules.OPPONENT_OWNER)
	var card: Dictionary = Catalog.create_instance(
		&"YiJianLuo9Yan2", Rules.PLAYER_OWNER, &"yijian_two"
	)
	var transition: Dictionary = Simulator.apply_action_oracle(
		State.new(board, [card], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"yijian_two")
	)
	var next_state: State = transition.get("state") as State
	_check(_instance_at(next_state, 5) == &"yijian_two", "YiJian moves into the flipped card's slot")
	_check(_instance_at(next_state, 4) == &"yijian_two_enemy", "The flipped card returns to YiJian's old slot")


func _test_yijian_three_attacks_after_the_swap() -> void:
	var board: Array = Rules.empty_board()
	board[5] = _slot(_plain(&"first_flip", [1, 1, 1, 1]), Rules.OPPONENT_OWNER)
	board[2] = _slot(_plain(&"followup_flip", [1, 1, 1, 1]), Rules.OPPONENT_OWNER)
	var card: Dictionary = Catalog.create_instance(
		&"YiJianLuo9Yan3", Rules.PLAYER_OWNER, &"yijian_three"
	)
	var transition: Dictionary = Simulator.apply_action_oracle(
		State.new(board, [card], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"yijian_three")
	)
	var next_state: State = transition.get("state") as State
	_check(
		_has_attack_event(transition.get("events", []), 5, 2, &"yijian_three"),
		"Tier three attacks from the square reached by its first swap"
	)
	_check(
		int((next_state.board[2] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER,
		"Tier three attacks from its new square"
	)


func _test_yijian_three_stops_when_the_flip_is_no_longer_adjacent() -> void:
	var source: Dictionary = Catalog.create_instance(
		&"YiJianLuo9Yan3", Rules.PLAYER_OWNER, &"distant_yijian"
	)
	var target: Dictionary = _plain(&"distant_flip")
	var board: Array = Rules.empty_board()
	board[0] = _slot(source, Rules.PLAYER_OWNER)
	board[8] = _slot(target, Rules.PLAYER_OWNER)
	var trigger: Dictionary = (
		((source.get("active_abilities", [])[0] as Dictionary).get("triggers", [])[0])
		as Dictionary
	)
	var result: Dictionary = Executor.execute_actions(
		State.new(board),
		0,
		&"distant_yijian",
		Rules.PLAYER_OWNER,
		trigger.get("actions", []) as Array,
		{
			"attacker_cell": 0,
			"attacker_instance_id": &"distant_yijian",
			"attacker_owner_id": Rules.PLAYER_OWNER,
			"attack_flips": [{
				"instance_id": &"distant_flip",
				"previous_owner_id": Rules.OPPONENT_OWNER,
			}],
		}
	)
	_check(
		StringName(result.get("result", &"")) == Catalog.ACTION_RESULT_INVALID_CONTEXT
		and (result.get("attack_requests", []) as Array).is_empty(),
		"A non-adjacent exact flip makes the swap fail and stops the follow-up attack"
	)


func _test_tianzhu_three_moves_then_draws() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(
		&"TianZhuYunQi3", Rules.PLAYER_OWNER, &"tianzhu_three"
	), Rules.PLAYER_OWNER)
	var enemy_play: Dictionary = _plain(&"enemy_play", [1, 1, 1, 1])
	var drawn: Dictionary = _plain(&"drawn_card")
	var state := State.new(board, [], [enemy_play], Rules.OPPONENT_OWNER)
	state.decks[Rules.PLAYER_OWNER] = [drawn]
	var transition: Dictionary = Simulator.apply_action_oracle(
		state,
		Action.make_play(0, 1, &"enemy_play")
	)
	var next_state: State = transition.get("state") as State
	_check(_instance_at(next_state, 3) == &"tianzhu_three", "TianZhu uses the lowest row-major adjacent empty cell")
	_check(next_state.get_hand(Rules.PLAYER_OWNER).size() == 1, "Tier three draws only after moving")


func _test_tianzhu_four_suppresses_before_external_movement() -> void:
	var tianzhu: Dictionary = Catalog.create_instance(
		&"TianZhuYunQi4", Rules.PLAYER_OWNER, &"tianzhu_four"
	)
	tianzhu["ki"] = 1
	(tianzhu["active_abilities"] as Array).append({
		"retained_on_flip": false,
		"activation": {
			"input": Catalog.ACTIVATION_DRAG_TO_TARGET,
			"target_rule": Catalog.TARGET_ADJACENT_EMPTY_BOARD,
			"costs": [{"type": Catalog.ACTION_SPEND_KI, "amount": 1}],
			"actions": [{"type": Catalog.ACTION_MOVE_SELF_TO_TARGET}],
		},
	})
	var board: Array = Rules.empty_board()
	board[4] = _slot(tianzhu, Rules.PLAYER_OWNER)
	board[1] = _slot(Catalog.create_instance(
		&"CangSongYingKe2", Rules.OPPONENT_OWNER, &"movement_neighbor"
	), Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action_oracle(
		State.new(board, [], [], Rules.PLAYER_OWNER),
		Action.make_activate(4, &"tianzhu_four", Action.TARGET_BOARD_CELL, 3)
	)
	var events: Array = transition.get("events", [])
	_check(
		_event_index(events, &"ability_lost") < _event_index(events, &"card_moved"),
		"TianZhu suppresses adjacent enemies before movement caused by another ability"
	)
	_check(
		_ability_count(transition.get("state") as State, &"movement_neighbor") == 1,
		"Movement suppression restores at the end of the turn"
	)


func _test_temporary_suppression_retains_permanent_abilities_and_new_grants() -> void:
	var old_ability: Dictionary = {"triggers": [{
		"event": Catalog.TRIGGER_END_OWNER_TURN,
		"conditions": [],
		"actions": [{"type": Catalog.ACTION_GAIN_KI, "amount": 1}],
	}], "retained_on_flip": false}
	var retained_ability: Dictionary = {"modifiers": [{
		"type": Catalog.MODIFIER_DEFENDING_POWER_OVERRIDE,
		"value": 3,
	}], "retained_on_flip": true}
	var new_ability: Dictionary = {"modifiers": [{
		"type": Catalog.MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE,
	}], "retained_on_flip": false}
	var card: Dictionary = _plain(&"suppression_fixture")
	card["active_abilities"] = [old_ability, retained_ability]
	var removed: Array[Dictionary] = Abilities.temporarily_remove_non_retained_abilities(card, 7)
	(card["active_abilities"] as Array).append(new_ability.duplicate(true))
	var restored: Array[Dictionary] = Abilities.restore_temporarily_removed_abilities(card, 7)
	var active: Array = card.get("active_abilities", [])
	_check(removed.size() == 1 and restored.size() == 1, "One temporary batch removes and restores one ability")
	_check(
		active.size() == 3
		and active[0] == old_ability
		and active[1] == retained_ability
		and active[2] == new_ability,
		"Retained abilities and abilities granted later remain active in their stable order"
	)


func _test_flipping_while_suppressed_permanently_erases_the_stored_ability() -> void:
	var old_ability: Dictionary = {"triggers": [{
		"event": Catalog.TRIGGER_END_OWNER_TURN,
		"conditions": [],
		"actions": [{"type": Catalog.ACTION_GAIN_KI, "amount": 1}],
	}], "retained_on_flip": false}
	var retained_ability: Dictionary = {"modifiers": [{
		"type": Catalog.MODIFIER_DEFENDING_POWER_OVERRIDE,
		"value": 3,
	}], "retained_on_flip": true}
	var card: Dictionary = _plain(&"flip_suppression_fixture")
	card["active_abilities"] = [old_ability, retained_ability]
	Abilities.temporarily_remove_non_retained_abilities(card, 4)
	var board: Array = Rules.empty_board()
	board[4] = _slot(card, Rules.OPPONENT_OWNER)
	var state := State.new(board)
	Executor.resolve_normal_flip(
		state,
		-1,
		&"",
		4,
		&"flip_suppression_fixture",
		Rules.PLAYER_OWNER
	)
	var flipped_card: Dictionary = (state.board[4] as Dictionary).get("card", {})
	_check(
		(flipped_card.get("active_abilities", []) as Array).size() == 1
		and (flipped_card.get("active_abilities", []) as Array)[0] == retained_ability
		and not flipped_card.has("temporary_suppression_batches"),
		"Flipping clears stored non-retained abilities permanently but keeps retained abilities"
	)


func _plain(instance_id: StringName, powers: Array[int] = [1, 1, 1, 1]) -> Dictionary:
	var card: Dictionary = Rules.make_card(String(instance_id), "测", powers, [], Rules.PLAYER_OWNER)
	card["instance_id"] = instance_id
	return card


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	card["original_owner"] = owner_id
	return {"card": card, "owner": owner_id}


func _instance_at(state: State, cell: int) -> StringName:
	if state == null or state.board[cell] == null:
		return &""
	return StringName(((state.board[cell] as Dictionary).get("card", {}) as Dictionary).get("instance_id", &""))


func _ability_count(state: State, instance_id: StringName) -> int:
	if state == null:
		return -1
	for slot_value: Variant in state.board:
		if slot_value == null:
			continue
		var card: Dictionary = (slot_value as Dictionary).get("card", {})
		if StringName(card.get("instance_id", &"")) == instance_id:
			return (card.get("active_abilities", []) as Array).size()
	return -1


func _event_index(events: Array, event_type: StringName) -> int:
	for index: int in range(events.size()):
		var event_value: Variant = events[index]
		if event_value is Dictionary and StringName((event_value as Dictionary).get("type", &"")) == event_type:
			return index
	return 1_000_000


func _first_event(events: Array, event_type: StringName) -> Dictionary:
	for event_value: Variant in events:
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
		):
			return event_value as Dictionary
	return {}


func _has_attack_event(
	events: Array,
	source_cell: int,
	target_cell: int,
	instance_id: StringName
) -> bool:
	for event_value: Variant in events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		if (
			StringName(event.get("type", &"")) == &"attack_started"
			and int(event.get("source_cell", -1)) == source_cell
			and int(event.get("target_cell", -1)) == target_cell
			and StringName(event.get("source_instance_id", &"")) == instance_id
		):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
