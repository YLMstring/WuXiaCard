extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Executor = preload("res://scripts/duel_ability_executor.gd")
const Revelation = preload("res://scripts/duel_revelation.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const Triggers = preload("res://scripts/duel_triggers.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_vocabulary_and_declarations()
	_test_jinzhen_returns_first_matching_card_as_fresh_copy()
	_test_jinzhen_follows_board_movement_and_revalidates_conditions()
	_test_jinzhen_exiles_when_hand_is_full()
	_test_wanhua_copy_uses_lowest_adjacent_cell_and_full_summon()
	_test_wanhua_copy_retention_differs_by_tier()
	_test_wanhua_loser_reopens_full_board_before_terminal_state()
	_test_wanhua_winner_stays_for_stable_terminal_state()
	_test_wanhua_tie_snapshot_removes_both_sides()
	if _failures == 0:
		print("JINZHEN_WANHUA_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"JINZHEN_WANHUA_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_vocabulary_and_declarations() -> void:
	_check(Catalog.TRIGGER_BEFORE_DUEL_END in Catalog.KNOWN_TRIGGER_EVENTS, "Before-duel-end event is registered")
	_check(Catalog.CONDITION_OWNER_DID_NOT_WIN in Catalog.KNOWN_TRIGGER_CONDITIONS, "Nonwinner condition is registered")
	_check(Catalog.CONDITION_ATTACKED_CARD_IS_SELF in Catalog.KNOWN_TRIGGER_CONDITIONS, "Attacked-self condition is registered")
	_check(Catalog.CONDITION_SELECTED_CARD_ORIGINAL_OWNER_IS_SELF in Catalog.KNOWN_SELECTOR_CONDITIONS, "Original-owner selector condition is registered")
	for action_type: StringName in [
		Catalog.ACTION_RETURN_CARD_TO_HAND,
		Catalog.ACTION_SUMMON_CARD,
		Catalog.ACTION_EXILE_SELF,
	]:
		_check(action_type in Catalog.KNOWN_ACTIONS, "%s action is registered" % action_type)
	_check(Catalog.validate_catalog().is_empty(), "Complete catalog validates")
	var expected_counts: Dictionary = {
		&"JinZhenDuJie1": 0,
		&"JinZhenDuJie2": 1,
		&"JinZhenDuJie3": 2,
		&"JinZhenDuJie4": 2,
		&"WanHuaJian1": 1,
		&"WanHuaJian2": 2,
		&"WanHuaJian3": 2,
	}
	for card_id: StringName in expected_counts:
		_check(card_id in Catalog.get_all_card_ids(), "%s is registered" % card_id)
		var abilities: Array = Catalog.get_definition(card_id).get("abilities", [])
		_check(abilities.size() == int(expected_counts[card_id]), "%s has its approved ability count" % card_id)
	var jin_two: Array = Catalog.get_definition(&"JinZhenDuJie2").get("abilities", [])
	if not jin_two.is_empty():
		var trigger: Dictionary = ((jin_two[0] as Dictionary).get("triggers", []) as Array)[0]
		_check(StringName(trigger.get("event", &"")) == Catalog.TRIGGER_CARD_AFTER_SUMMONED, "JinZhen returns after its summon")
	var wan_two: Array = Catalog.get_definition(&"WanHuaJian2").get("abilities", [])
	var wan_three: Array = Catalog.get_definition(&"WanHuaJian3").get("abilities", [])
	if wan_two.size() == 2 and wan_three.size() == 2:
		_check(bool((wan_two[0] as Dictionary).get("retained_on_flip", false)), "WanHua tier two retains copy")
		_check(not bool((wan_three[0] as Dictionary).get("retained_on_flip", false)), "WanHua tier three loses copy")
		_check(bool((wan_two[1] as Dictionary).get("retained_on_flip", false)) and bool((wan_three[1] as Dictionary).get("retained_on_flip", false)), "WanHua ending remains locked")


func _test_jinzhen_returns_first_matching_card_as_fresh_copy() -> void:
	var first: Dictionary = Catalog.create_instance(&"TianChangZhang3", Rules.PLAYER_OWNER, &"generated_TianChangZhang3_1")
	first["ki"] = 9
	first["powers"] = [99, 99, 99, 99]
	first["active_abilities"] = []
	var second: Dictionary = Catalog.create_instance(&"HenShanJianZhen2", Rules.PLAYER_OWNER, &"jin_second")
	var board: Array = Rules.empty_board()
	board[0] = _slot(first, Rules.OPPONENT_OWNER, Rules.PLAYER_OWNER)
	board[2] = _slot(second, Rules.OPPONENT_OWNER, Rules.PLAYER_OWNER)
	var source: Dictionary = Catalog.create_instance(&"JinZhenDuJie2", Rules.PLAYER_OWNER, &"jin_source")
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [source], [_plain(&"jin_reply")], Rules.PLAYER_OWNER),
		Action.make_play(0, 8, &"jin_source")
	)
	var next_state: State = transition.get("state") as State
	_check(next_state.board[0] == null and next_state.board[2] != null, "JinZhen selects the lowest matching board index")
	var hand: Array = next_state.get_hand(Rules.PLAYER_OWNER)
	_check(hand.size() == 1, "Returned card enters the ability source owner's hand")
	if hand.size() == 1:
		var returned: Dictionary = hand[0]
		var definition: Dictionary = Catalog.get_definition(&"TianChangZhang3")
		_check(StringName(returned.get("instance_id", &"")) != &"generated_TianChangZhang3_1", "Returned card receives a fresh instance ID")
		_check(returned.get("powers", []) == definition.get("powers", []) and int(returned.get("ki", -1)) == 0, "Returned card resets to catalog powers and ki")
		_check(int(returned.get("original_owner", 0)) == Rules.PLAYER_OWNER, "Returned fresh copy belongs originally to the source owner")
		_check(
			Revelation.is_revealed_to(returned, Rules.OPPONENT_OWNER),
			"A fresh board return is permanently visible to the recipient's opponent"
		)
	_check(_event_count(transition.get("events", []), &"card_returned_to_hand") == 1, "Return emits one ordered presentation event")
	_check(
		_event_types(transition.get("events", [])).find(&"card_revealed")
		== _event_types(transition.get("events", [])).find(&"card_returned_to_hand") + 1,
		"A fresh return emits its reveal immediately after entering the hand"
	)
	_check((next_state.removed_cards[Rules.PLAYER_OWNER] as Array).is_empty(), "Successful return does not exile the old instance")


func _test_jinzhen_follows_board_movement_and_revalidates_conditions() -> void:
	var source: Dictionary = Catalog.create_instance(&"JinZhenDuJie2", Rules.PLAYER_OWNER, &"moving_source")
	var target: Dictionary = Catalog.create_instance(&"TianChangZhang3", Rules.PLAYER_OWNER, &"moving_target")
	var board: Array = Rules.empty_board()
	board[4] = _slot(source, Rules.PLAYER_OWNER)
	board[0] = _slot(target, Rules.OPPONENT_OWNER, Rules.PLAYER_OWNER)
	board[2] = board[0]
	board[0] = null
	var state := State.new(board)
	var result: Dictionary = Executor.execute_actions(
		state,
		0,
		&"moving_target",
		Rules.OPPONENT_OWNER,
		[{
			"type": Catalog.ACTION_RETURN_CARD_TO_HAND,
			"card": Catalog.CARD_REF_SELECTED_CARD,
			"recipient": Catalog.OWNER_ABILITY_SOURCE,
		}],
		{
			"ability_source_instance_id": &"moving_source",
			"ability_source_owner_id": Rules.PLAYER_OWNER,
			"selected_card_instance_id": &"moving_target",
			"selected_card_conditions": [
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_ENEMY},
				{"type": Catalog.CONDITION_SELECTED_CARD_ORIGINAL_OWNER_IS_SELF},
			],
		}
	)
	_check(StringName(result.get("result", &"")) == Catalog.ACTION_RESULT_APPLIED and state.board[2] == null, "Return follows the exact instance after board movement")

	var changed_source: Dictionary = Catalog.create_instance(&"JinZhenDuJie2", Rules.PLAYER_OWNER, &"changed_source")
	var changed_target: Dictionary = Catalog.create_instance(&"TianChangZhang3", Rules.PLAYER_OWNER, &"changed_target")
	var changed_board: Array = Rules.empty_board()
	changed_board[4] = _slot(changed_source, Rules.PLAYER_OWNER)
	changed_board[2] = _slot(changed_target, Rules.PLAYER_OWNER, Rules.PLAYER_OWNER)
	var changed_state := State.new(changed_board)
	var skipped: Dictionary = Executor.execute_actions(
		changed_state,
		2,
		&"changed_target",
		Rules.PLAYER_OWNER,
		[{
			"type": Catalog.ACTION_RETURN_CARD_TO_HAND,
			"card": Catalog.CARD_REF_SELECTED_CARD,
			"recipient": Catalog.OWNER_ABILITY_SOURCE,
		}],
		{
			"ability_source_instance_id": &"changed_source",
			"ability_source_owner_id": Rules.PLAYER_OWNER,
			"selected_card_instance_id": &"changed_target",
			"selected_card_conditions": [
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_ENEMY},
				{"type": Catalog.CONDITION_SELECTED_CARD_ORIGINAL_OWNER_IS_SELF},
			],
		}
	)
	_check(StringName(skipped.get("result", &"")) == Catalog.ACTION_RESULT_NO_EFFECT and changed_state.board[2] != null, "Return skips when a declared condition stopped matching")


func _test_jinzhen_exiles_when_hand_is_full() -> void:
	var source: Dictionary = Catalog.create_instance(&"JinZhenDuJie2", Rules.PLAYER_OWNER, &"full_source")
	var target: Dictionary = Catalog.create_instance(&"TianChangZhang3", Rules.PLAYER_OWNER, &"full_target")
	var board: Array = Rules.empty_board()
	board[4] = _slot(source, Rules.PLAYER_OWNER)
	board[0] = _slot(target, Rules.OPPONENT_OWNER, Rules.PLAYER_OWNER)
	var full_hand: Array = []
	for index: int in range(5):
		full_hand.append(_plain(StringName("full_hand_%d" % index)))
	var state := State.new(board, full_hand)
	var groups: Array[Dictionary] = Triggers.discover(
		state,
		Catalog.TRIGGER_CARD_AFTER_SUMMONED,
		{"trigger_cell": 4, "trigger_instance_id": &"full_source", "trigger_owner_id": Rules.PLAYER_OWNER}
	)
	var result: Dictionary = Triggers.resolve_group(state, groups[0]) if not groups.is_empty() else {}
	_check(state.board[0] == null and state.get_hand(Rules.PLAYER_OWNER).size() == 5, "A full hand exiles instead of returning")
	_check((state.removed_cards[Rules.PLAYER_OWNER] as Array).size() == 1, "Full-hand fallback records the old instance in removed cards")
	var exile: Dictionary = _first_event(result.get("events", []), &"card_exiled")
	_check(not exile.is_empty() and not bool(exile.get("self_removal", true)), "Full-hand fallback keeps the external exile presentation")


func _test_wanhua_copy_uses_lowest_adjacent_cell_and_full_summon() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(&"WanHuaJian2", Rules.PLAYER_OWNER, &"wan_source"), Rules.PLAYER_OWNER)
	board[0] = _slot(_plain(&"wan_copy_target", [1, 1, 1, 1]), Rules.OPPONENT_OWNER)
	var attacker: Dictionary = _plain(&"wan_attacker", [1, 1, 9, 1])
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [], [attacker], Rules.OPPONENT_OWNER),
		Action.make_play(0, 1, &"wan_attacker")
	)
	var next_state: State = transition.get("state") as State
	_check(next_state.board[3] != null, "WanHua creates its copy in the lowest-index adjacent empty cell")
	if next_state.board[3] != null:
		var copy_slot: Dictionary = next_state.board[3]
		var copy: Dictionary = copy_slot.get("card", {})
		_check(StringName(copy.get("card_id", &"")) == &"WanHuaJian2" and StringName(copy.get("instance_id", &"")) != &"wan_source", "WanHua creates a fresh exact-ID copy")
		_check(int(copy_slot.get("owner", 0)) == Rules.PLAYER_OWNER and int(copy.get("original_owner", 0)) == Rules.PLAYER_OWNER, "Generated copy uses the generator's current owner")
	_check(int((next_state.board[0] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER, "Generated copy performs its standard attack")
	var types: Array[StringName] = _event_types(transition.get("events", []))
	_check(types.find(&"card_summoned") >= 0 and types.find(&"card_summoned") < types.rfind(&"card_flipped"), "Generated copy resolves summon presentation before the original attack completes")


func _test_wanhua_copy_retention_differs_by_tier() -> void:
	for card_id: StringName in [&"WanHuaJian2", &"WanHuaJian3"]:
		var board: Array = Rules.empty_board()
		board[4] = _slot(Catalog.create_instance(card_id, Rules.PLAYER_OWNER, StringName("flip_%s" % card_id)), Rules.PLAYER_OWNER)
		var state := State.new(board)
		Executor.resolve_normal_flip(state, -1, &"", 4, StringName("flip_%s" % card_id), Rules.OPPONENT_OWNER)
		var active: Array = (((state.board[4] as Dictionary).get("card", {}) as Dictionary).get("active_abilities", []) as Array)
		_check(active.size() == (2 if card_id == &"WanHuaJian2" else 1), "%s keeps only its approved retained abilities" % card_id)


func _test_wanhua_loser_reopens_full_board_before_terminal_state() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(Catalog.create_instance(&"WanHuaJian1", Rules.OPPONENT_OWNER, &"losing_wan"), Rules.OPPONENT_OWNER)
	for cell: int in [1, 2, 3]:
		board[cell] = _slot(_plain(StringName("losing_enemy_%d" % cell), [9, 9, 9, 9]), Rules.OPPONENT_OWNER)
	for cell: int in [4, 5, 6, 7]:
		board[cell] = _slot(_plain(StringName("losing_ally_%d" % cell), [9, 9, 9, 9]), Rules.PLAYER_OWNER)
	var ninth: Dictionary = _plain(&"losing_ninth", [1, 1, 1, 1])
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [ninth], [_plain(&"losing_reply")], Rules.PLAYER_OWNER),
		Action.make_play(0, 8, &"losing_ninth")
	)
	var next_state: State = transition.get("state") as State
	_check(next_state.board[0] == null and not Simulator.is_terminal(next_state), "Losing WanHua reopens the full board before terminal state")
	_check(next_state.active_player == Rules.OPPONENT_OWNER, "Normal next owner receives the reopened turn")
	var exile: Dictionary = _first_event(transition.get("events", []), &"card_exiled")
	_check(bool(exile.get("self_removal", false)), "WanHua self-removal requests fade presentation")


func _test_wanhua_winner_stays_for_stable_terminal_state() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(Catalog.create_instance(&"WanHuaJian1", Rules.PLAYER_OWNER, &"winning_wan"), Rules.PLAYER_OWNER)
	for cell: int in [1, 2, 3]:
		board[cell] = _slot(_plain(StringName("winning_ally_%d" % cell), [9, 9, 9, 9]), Rules.PLAYER_OWNER)
	for cell: int in [4, 5, 6, 7]:
		board[cell] = _slot(_plain(StringName("winning_enemy_%d" % cell), [9, 9, 9, 9]), Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [_plain(&"winning_ninth")], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 8, &"winning_ninth")
	)
	var next_state: State = transition.get("state") as State
	_check(next_state.board[0] != null and Simulator.is_terminal(next_state), "Winning WanHua remains on a stable full terminal board")
	_check(_event_count(transition.get("events", []), &"card_exiled") == 0, "Winner's ending ability has no effect")


func _test_wanhua_tie_snapshot_removes_both_sides() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(Catalog.create_instance(&"WanHuaJian1", Rules.PLAYER_OWNER, &"tie_player"), Rules.PLAYER_OWNER)
	board[8] = _slot(Catalog.create_instance(&"WanHuaJian1", Rules.OPPONENT_OWNER, &"tie_opponent"), Rules.OPPONENT_OWNER)
	var state := State.new(board)
	var groups: Array[Dictionary] = Triggers.discover(state, Catalog.TRIGGER_BEFORE_DUEL_END, {"winning_owner_ids": []})
	_check(groups.size() == 2, "Tie snapshot discovers both sides before either self-removal")
	for group: Dictionary in groups:
		Triggers.resolve_group(state, group)
	_check(state.board[0] == null and state.board[8] == null, "Both pre-discovered tie abilities resolve")


func _plain(instance_id: StringName, powers: Array[int] = [1, 1, 1, 1]) -> Dictionary:
	var card: Dictionary = Rules.make_card(String(instance_id), "测", powers, [], Rules.PLAYER_OWNER)
	card["instance_id"] = instance_id
	return card


func _slot(card: Dictionary, owner_id: int, original_owner: int = 0) -> Dictionary:
	card["original_owner"] = owner_id if original_owner == 0 else original_owner
	return {"card": card, "owner": owner_id}


func _event_types(events: Array) -> Array[StringName]:
	var types: Array[StringName] = []
	for value: Variant in events:
		if value is Dictionary:
			types.append(StringName((value as Dictionary).get("type", &"")))
	return types


func _event_count(events: Array, event_type: StringName) -> int:
	return _event_types(events).count(event_type)


func _first_event(events: Array, event_type: StringName) -> Dictionary:
	for value: Variant in events:
		if value is Dictionary and StringName((value as Dictionary).get("type", &"")) == event_type:
			return value as Dictionary
	return {}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
