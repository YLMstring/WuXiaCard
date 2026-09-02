extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Action = preload("res://scripts/duel_action.gd")
const Executor = preload("res://scripts/duel_ability_executor.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const Triggers = preload("res://scripts/duel_triggers.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_vocabulary_and_declarations()
	_test_power_change_validation()
	_test_signed_change_and_dynamic_count()
	_test_zero_power_removes_board_and_hand_cards()
	_test_power_change_batches()
	_test_wanyue_entry_decay_and_adjacent_growth()
	_test_dasongyang_ally_and_enemy_reactions()
	_test_summoned_card_removed_before_attack()
	if _failures == 0:
		print("WANYUE_DASONGYANG_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"WANYUE_DASONGYANG_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_catalog_vocabulary_and_declarations() -> void:
	_check(Catalog.ACTION_CHANGE_POWERS in Catalog.KNOWN_ACTIONS, "Signed power changes are registered")
	_check(Catalog.VALUE_CARD_COUNT in Catalog.KNOWN_VALUE_TYPES, "Card-count values are registered")
	_check(Catalog.CARD_REF_TRIGGER_CARD in Catalog.KNOWN_CARD_REFERENCES, "Trigger-card references are registered")
	_check(
		Catalog.CONDITION_TRIGGER_CARD_IS_ALLY in Catalog.KNOWN_TRIGGER_CONDITIONS,
		"Ally summon conditions are registered"
	)
	_check(Catalog.validate_catalog().is_empty(), "The complete catalog validates")
	for tier: int in range(1, 5):
		var wanyue_id := StringName("WanYueChaoZong%d" % tier)
		var dasong_id := StringName("DaSongYangZhang%d" % tier)
		var wanyue_abilities: Array = Catalog.get_definition(wanyue_id).get("abilities", [])
		var dasong_abilities: Array = Catalog.get_definition(dasong_id).get("abilities", [])
		_check(wanyue_abilities.size() == (1 if tier == 1 else 2), "%s has approved abilities" % wanyue_id)
		_check(dasong_abilities.size() == (1 if tier == 1 else 2), "%s has approved abilities" % dasong_id)


func _test_power_change_validation() -> void:
	var valid: Dictionary = _trigger_ability([{
		"type": Catalog.ACTION_CHANGE_POWERS,
		"amount": -2,
		"card": Catalog.CARD_REF_TRIGGER_CARD,
	}])
	_check(Catalog.validate_ability(valid).is_empty(), "Negative literal power changes validate")
	var dynamic: Dictionary = _trigger_ability([{
		"type": Catalog.ACTION_CHANGE_POWERS,
		"amount": {
			"type": Catalog.VALUE_CARD_COUNT,
			"zone": Catalog.CARD_ZONE_HAND,
			"owner": Catalog.OWNER_ABILITY_SOURCE,
		},
		"card": Catalog.CARD_REF_ABILITY_SOURCE,
	}])
	_check(Catalog.validate_ability(dynamic).is_empty(), "Dynamic hand-count changes validate")
	for invalid_action: Dictionary in [
		{"type": Catalog.ACTION_CHANGE_POWERS, "amount": 0, "card": Catalog.CARD_REF_ABILITY_SOURCE},
		{"type": Catalog.ACTION_CHANGE_POWERS, "amount": 1, "card": &"unknown"},
		{
			"type": Catalog.ACTION_CHANGE_POWERS,
			"amount": {"type": Catalog.VALUE_CARD_COUNT, "zone": Catalog.CARD_ZONE_BOARD, "owner": Catalog.OWNER_ABILITY_SOURCE},
			"card": Catalog.CARD_REF_ABILITY_SOURCE,
		},
		{
			"type": Catalog.ACTION_CHANGE_POWERS,
			"amount": {"type": &"unknown", "zone": Catalog.CARD_ZONE_HAND, "owner": Catalog.OWNER_ABILITY_SOURCE},
			"card": Catalog.CARD_REF_ABILITY_SOURCE,
		},
	]:
		_check(not Catalog.validate_ability(_trigger_ability([invalid_action])).is_empty(), "Malformed power changes fail validation")


func _test_signed_change_and_dynamic_count() -> void:
	var source: Dictionary = _plain(&"signed_source", [1, 2, 3, 4], Rules.PLAYER_OWNER)
	var board: Array = Rules.empty_board()
	board[4] = _slot(source, Rules.PLAYER_OWNER)
	var hand: Array = [
		_plain(&"count_one", [1, 1, 1, 1], Rules.PLAYER_OWNER),
		_plain(&"count_two", [1, 1, 1, 1], Rules.PLAYER_OWNER),
	]
	var state := State.new(board, hand, [])
	var result: Dictionary = Executor.execute_actions(
		state,
		4,
		&"signed_source",
		Rules.PLAYER_OWNER,
		[
			{"type": Catalog.ACTION_CHANGE_POWERS, "amount": -2, "card": Catalog.CARD_REF_ABILITY_SOURCE},
			{
				"type": Catalog.ACTION_CHANGE_POWERS,
				"amount": {"type": Catalog.VALUE_CARD_COUNT, "zone": Catalog.CARD_ZONE_HAND, "owner": Catalog.OWNER_ABILITY_SOURCE},
				"card": Catalog.CARD_REF_ABILITY_SOURCE,
			},
		],
		{}
	)
	_check(source.get("powers", []) == [1, 2, 3, 4], "State construction isolates fixture data")
	var changed: Dictionary = (state.board[4] as Dictionary).get("card", {})
	_check(changed.get("powers", []) == [2, 2, 3, 4], "Negative changes clamp each side and dynamic count uses current hand")
	var events: Array = result.get("events", [])
	_check(_event_types(events) == [&"powers_changed", &"powers_changed"], "Each logical change emits one event")
	_check(int((events[0] as Dictionary).get("amount", 0)) == -2, "Power event records resolved signed amount")


func _test_zero_power_removes_board_and_hand_cards() -> void:
	var source: Dictionary = _plain(&"external_source", [5, 5, 5, 5], Rules.PLAYER_OWNER)
	var target: Dictionary = _plain(&"board_target", [1, 2, 0, 2], Rules.OPPONENT_OWNER)
	var board: Array = Rules.empty_board()
	board[0] = _slot(source, Rules.PLAYER_OWNER)
	board[1] = _slot(target, Rules.PLAYER_OWNER)
	var state := State.new(board)
	var result: Dictionary = Executor.execute_actions(
		state,
		0,
		&"external_source",
		Rules.PLAYER_OWNER,
		[{"type": Catalog.ACTION_CHANGE_POWERS, "amount": -2, "card": Catalog.CARD_REF_TRIGGER_CARD}],
		{"trigger_instance_id": &"board_target"}
	)
	_check(state.board[1] == null, "A board card reaching four zeros leaves the board")
	_check((state.removed_cards[Rules.OPPONENT_OWNER] as Array).size() == 1, "Removal uses the original owner's zone")
	var events: Array = result.get("events", [])
	_check(_event_types(events) == [&"powers_changed", &"card_exiled"], "Power change precedes removal")
	_check(not bool((events[1] as Dictionary).get("self_removal", true)), "External power death uses external exile presentation")

	var hand_target: Dictionary = _plain(&"hand_target", [1, 1, 1, 1], Rules.PLAYER_OWNER)
	var hand_state := State.new(board, [hand_target], [])
	hand_state.board[1] = null
	var hand_result: Dictionary = Executor.execute_actions(
		hand_state,
		0,
		&"external_source",
		Rules.PLAYER_OWNER,
		[{
			"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
			"selector": {"zones": [Catalog.CARD_ZONE_HAND], "conditions": [{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY}]},
			"actions": [{"type": Catalog.ACTION_CHANGE_POWERS, "amount": -1, "card": Catalog.CARD_REF_SELECTED_CARD}],
		}],
		{}
	)
	_check(hand_state.get_hand(Rules.PLAYER_OWNER).is_empty(), "A zero-power hand card leaves its exact hand slot")
	_check(_event_types(hand_result.get("events", [])) == [&"powers_changed", &"card_exiled"], "Hand death keeps logical event order")


func _test_power_change_batches() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(_plain(&"batch_source", [3, 3, 3, 3], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[0] = _slot(_plain(&"batch_one", [1, 1, 1, 1], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[1] = _slot(_plain(&"batch_two", [2, 2, 2, 2], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var state := State.new(board)
	var wrapper: Dictionary = {
		"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
		"selector": {
			"zones": [Catalog.CARD_ZONE_BOARD],
			"conditions": [
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY},
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
			],
		},
		"actions": [{"type": Catalog.ACTION_CHANGE_POWERS, "amount": 1, "card": Catalog.CARD_REF_SELECTED_CARD}],
	}
	var result: Dictionary = Executor.execute_actions(
		state,
		4,
		&"batch_source",
		Rules.PLAYER_OWNER,
		[wrapper, wrapper],
		{}
	)
	var power_events: Array[Dictionary] = []
	for event_value: Variant in result.get("events", []):
		if event_value is Dictionary and StringName((event_value as Dictionary).get("type", &"")) == &"powers_changed":
			power_events.append(event_value as Dictionary)
	_check(power_events.size() == 4, "Two top-level actions preserve four logical changes")
	_check(power_events[0].get("power_change_batch_id") == power_events[1].get("power_change_batch_id"), "One selector action shares one batch")
	_check(power_events[1].get("power_change_batch_id") != power_events[2].get("power_change_batch_id"), "Different top-level actions use separate batches")


func _test_wanyue_entry_decay_and_adjacent_growth() -> void:
	var wanyue: Dictionary = Catalog.create_instance(&"WanYueChaoZong1", Rules.PLAYER_OWNER, &"wanyue_entry")
	var hand: Array = [wanyue]
	for index: int in range(4):
		hand.append(_plain(StringName("entry_hand_%d" % index), [1, 1, 1, 1], Rules.PLAYER_OWNER))
	var transition: Dictionary = Simulator.apply_action_oracle(
		State.new(
			Rules.empty_board(),
			hand,
			[_plain(&"entry_enemy_hand", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
			Rules.PLAYER_OWNER
		),
		Action.make_play(0, 4, &"wanyue_entry")
	)
	var next_state: State = transition.get("state") as State
	var runtime: Dictionary = (next_state.board[4] as Dictionary).get("card", {})
	_check(
		runtime.get("powers", []) == [8, 7, 7, 8],
		"WanYue counts the four cards remaining after it leaves hand; got %s, hand=%d, amounts=%s"
		% [
			runtime.get("powers", []),
			next_state.get_hand(Rules.PLAYER_OWNER).size(),
			_power_amounts(transition.get("events", [])),
		]
	)
	var groups: Array[Dictionary] = Triggers.discover(
		next_state,
		Catalog.TRIGGER_START_OWNER_TURN,
		{"turn_owner_id": Rules.PLAYER_OWNER}
	)
	for group: Dictionary in groups:
		Triggers.resolve_group(next_state, group)
	_check(
		runtime.get("powers", []) == [7, 6, 6, 7],
		"WanYue loses one on its owner's turn start; got %s" % [runtime.get("powers", [])]
	)

	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(&"WanYueChaoZong4", Rules.PLAYER_OWNER, &"wanyue_four"), Rules.PLAYER_OWNER)
	var ally: Dictionary = _plain(&"wanyue_ally", [1, 1, 1, 1], Rules.PLAYER_OWNER)
	var ally_transition: Dictionary = Simulator.apply_action_oracle(
		State.new(board, [ally], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 5, &"wanyue_ally")
	)
	var ally_state: State = ally_transition.get("state") as State
	_check(((ally_state.board[5] as Dictionary).get("card", {}) as Dictionary).get("powers", []) == [3, 3, 3, 3], "WanYue tier four grants an adjacent ally two")


func _test_dasongyang_ally_and_enemy_reactions() -> void:
	var ally_expected: Dictionary = {1: 1, 2: 1, 3: 1, 4: 2}
	var enemy_expected: Dictionary = {1: 0, 2: -1, 3: -2, 4: -2}
	for tier: int in range(1, 5):
		var card_id := StringName("DaSongYangZhang%d" % tier)
		var ally_board: Array = Rules.empty_board()
		ally_board[4] = _slot(Catalog.create_instance(card_id, Rules.PLAYER_OWNER, StringName("dasong_ally_%d" % tier)), Rules.PLAYER_OWNER)
		var ally_id := StringName("ally_%d" % tier)
		var ally_transition: Dictionary = Simulator.apply_action_oracle(
			State.new(ally_board, [_plain(ally_id, [5, 5, 5, 5], Rules.PLAYER_OWNER)], [], Rules.PLAYER_OWNER),
			Action.make_play(0, 5, ally_id)
		)
		var ally_state: State = ally_transition.get("state") as State
		var ally_powers: Array = ((ally_state.board[5] as Dictionary).get("card", {}) as Dictionary).get("powers", [])
		_check(ally_powers == [5 + int(ally_expected[tier]), 5 + int(ally_expected[tier]), 5 + int(ally_expected[tier]), 5 + int(ally_expected[tier])], "DaSongYang tier %d applies its ally amount" % tier)

		var enemy_board: Array = Rules.empty_board()
		enemy_board[4] = _slot(Catalog.create_instance(card_id, Rules.PLAYER_OWNER, StringName("dasong_enemy_%d" % tier)), Rules.PLAYER_OWNER)
		var enemy_id := StringName("enemy_%d" % tier)
		var enemy_transition: Dictionary = Simulator.apply_action_oracle(
			State.new(enemy_board, [], [_plain(enemy_id, [5, 5, 5, 5], Rules.OPPONENT_OWNER)], Rules.OPPONENT_OWNER),
			Action.make_play(0, 5, enemy_id)
		)
		var enemy_state: State = enemy_transition.get("state") as State
		var enemy_powers: Array = ((enemy_state.board[5] as Dictionary).get("card", {}) as Dictionary).get("powers", [])
		_check(enemy_powers == [5 + int(enemy_expected[tier]), 5 + int(enemy_expected[tier]), 5 + int(enemy_expected[tier]), 5 + int(enemy_expected[tier])], "DaSongYang tier %d applies its enemy amount" % tier)


func _test_summoned_card_removed_before_attack() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(&"DaSongYangZhang3", Rules.PLAYER_OWNER, &"lethal_dasong"), Rules.PLAYER_OWNER)
	var victim: Dictionary = _plain(&"lethal_victim", [1, 1, 1, 1], Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action_oracle(
		State.new(board, [], [victim], Rules.OPPONENT_OWNER),
		Action.make_play(0, 5, &"lethal_victim")
	)
	var next_state: State = transition.get("state") as State
	_check(next_state.board[5] == null, "A summoned card killed by global reactions is removed")
	_check(_event_count(transition.get("events", []), &"attack_started") == 0, "A killed summon performs no standard attack")


func _trigger_ability(actions: Array) -> Dictionary:
	return {
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_SUMMONED,
			"conditions": [],
			"actions": actions,
		}],
	}


func _plain(instance_id: StringName, powers: Array[int], original_owner: int) -> Dictionary:
	var card: Dictionary = Rules.make_card(String(instance_id), "测", powers, [], original_owner)
	card["instance_id"] = instance_id
	card["original_owner"] = original_owner
	return card


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _event_types(events: Array) -> Array[StringName]:
	var types: Array[StringName] = []
	for event_value: Variant in events:
		if event_value is Dictionary:
			types.append(StringName((event_value as Dictionary).get("type", &"")))
	return types


func _event_count(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for observed: StringName in _event_types(events):
		if observed == event_type:
			count += 1
	return count


func _power_amounts(events: Array) -> Array[int]:
	var amounts: Array[int] = []
	for event_value: Variant in events:
		if event_value is Dictionary and StringName((event_value as Dictionary).get("type", &"")) == &"powers_changed":
			amounts.append(int((event_value as Dictionary).get("amount", 0)))
	return amounts


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
