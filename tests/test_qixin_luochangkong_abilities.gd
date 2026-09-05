extends SceneTree

const BoardQueries = preload("res://tests/helpers/duel_native_board_queries.gd")

const Catalog = preload("res://scripts/card_catalog.gd")
const Abilities = preload("res://scripts/duel_abilities.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")
const Action = preload("res://scripts/duel_action.gd")

const MODIFIER_ATTACK_REQUIRES_OTHER_ALLY: StringName = &"attack_requires_other_ally"
const MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE: StringName = &"defending_power_uses_minimum_side"

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_declarations()
	_test_modifier_validation()
	_test_attack_permission_and_minimum_defense()
	_test_summon_attack_gate()
	_test_reaction_respects_declaration_gate()
	_test_retained_modifiers_follow_owner()
	_test_temporary_flip_protection()
	_test_state_copy_isolated()
	if _failures == 0:
		print("QIXIN_LUOCHANGKONG_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"QIXIN_LUOCHANGKONG_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_catalog_declarations() -> void:
	_check(Catalog.validate_catalog().is_empty(), "The complete catalog validates")
	var expected_ability_counts: Dictionary = {
		&"QiXinLuoChangKong2": 1,
		&"QiXinLuoChangKong3": 2,
		&"QiXinLuoChangKong4": 3,
	}
	for card_id: StringName in expected_ability_counts:
		_check(Catalog.has_card(card_id), "%s has a catalog definition" % card_id)
		_check(
			card_id in Catalog.get_all_card_ids(),
			"%s is registered in ALL_CARD_IDS" % card_id
		)
		if not Catalog.has_card(card_id):
			continue
		var abilities: Array = Catalog.get_definition(card_id).get("abilities", [])
		_check(
			abilities.size() == int(expected_ability_counts[card_id]),
			"%s declares its approved ability count" % card_id
		)
		if abilities.is_empty():
			continue
		var modifier_ability: Dictionary = abilities[0] as Dictionary
		_check(
			bool(modifier_ability.get("retained_on_flip", false)),
			"%s retains its modifier ability on flip" % card_id
		)
		var modifier_types: Array[StringName] = []
		for modifier_value: Variant in modifier_ability.get("modifiers", []):
			if modifier_value is Dictionary:
				modifier_types.append(StringName((modifier_value as Dictionary).get("type", &"")))
		_check(
			modifier_types == [
				MODIFIER_ATTACK_REQUIRES_OTHER_ALLY,
				MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE,
			],
			"%s declares both retained attack modifiers in order" % card_id
		)


func _test_modifier_validation() -> void:
	var valid: Dictionary = {
		"retained_on_flip": true,
		"modifiers": [
			{"type": MODIFIER_ATTACK_REQUIRES_OTHER_ALLY},
			{"type": MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE},
		],
	}
	_check(
		Catalog.validate_ability(valid).is_empty(),
		"Parameterless Boolean modifiers pass validation"
	)
	var illegal_value: Dictionary = {
		"modifiers": [{
			"type": MODIFIER_ATTACK_REQUIRES_OTHER_ALLY,
			"value": 1,
		}],
	}
	_check(
		not Catalog.validate_ability(illegal_value).is_empty(),
		"A Boolean modifier rejects a value field"
	)
	var missing_override_value: Dictionary = {
		"modifiers": [{"type": Catalog.MODIFIER_DEFENDING_POWER_OVERRIDE}],
	}
	_check(
		not Catalog.validate_ability(missing_override_value).is_empty(),
		"The numeric defending-power override still requires a value"
	)


func _test_attack_permission_and_minimum_defense() -> void:
	var attacker: Dictionary = Catalog.create_instance(
		&"QiXinLuoChangKong2",
		Rules.PLAYER_OWNER,
		&"qixin_rule"
	)
	var defender: Dictionary = Rules.make_card(
		"Guard",
		"守",
		[1, 9, 9, 9],
		[],
		Rules.OPPONENT_OWNER
	)
	defender["instance_id"] = &"qixin_guard"
	var board: Array = Rules.empty_board()
	board[4] = {"card": attacker, "owner": Rules.PLAYER_OWNER}
	board[5] = {"card": defender, "owner": Rules.OPPONENT_OWNER}
	var original_powers: Array = (defender["powers"] as Array).duplicate()
	_check(
		BoardQueries.is_target_in_attack_range(board, 4, 5),
		"QiXin compares against the defender's minimum effective side"
	)
	_check(
		not BoardQueries.can_attack_target(board, 4, 5),
		"QiXin cannot declare an attack while it has no other ally"
	)
	var ally: Dictionary = Rules.make_card(
		"Ally",
		"友",
		[1, 1, 1, 1],
		[],
		Rules.PLAYER_OWNER
	)
	ally["instance_id"] = &"qixin_ally"
	board[0] = {"card": ally, "owner": Rules.PLAYER_OWNER}
	_check(
		BoardQueries.can_attack_target(board, 4, 5),
		"One other allied board card permits QiXin to declare the attack"
	)
	board[0] = null
	_check(
		BoardQueries.is_target_in_attack_range(board, 4, 5)
		and not BoardQueries.can_attack_target(board, 4, 5),
		"Post-declaration range remains valid even if the other ally disappears"
	)
	_check(
		defender["powers"] == original_powers,
		"Minimum-side attack comparison leaves the defender's stored powers intact"
	)


func _test_summon_attack_gate() -> void:
	var alone_result: Dictionary = Simulator.apply_action(
		_make_qixin_summon_state(false),
		Action.make_play(0, 4, &"qixin_summon")
	)
	var alone_state: State = alone_result.get("state") as State
	_check(
		int((alone_state.board[5] as Dictionary).get("owner", 0))
		== Rules.OPPONENT_OWNER,
		"A summoned QiXin does not flip while it is the owner's only board card"
	)
	_check(
		_event_count(alone_result.get("events", []), &"attack_started") == 0,
		"A denied summon attack emits no attack-started event"
	)

	var allied_result: Dictionary = Simulator.apply_action(
		_make_qixin_summon_state(true),
		Action.make_play(0, 4, &"qixin_summon")
	)
	var allied_state: State = allied_result.get("state") as State
	_check(
		int((allied_state.board[5] as Dictionary).get("owner", 0))
		== Rules.PLAYER_OWNER,
		"A summoned QiXin flips with another ally present"
	)
	_check(
		_event_count(allied_result.get("events", []), &"attack_started") == 1,
		"A permitted summon attack emits one attack-started event"
	)


func _test_reaction_respects_declaration_gate() -> void:
	var alone_result: Dictionary = Simulator.apply_action(
		_make_qixin_reaction_state(false),
		Action.make_play(0, 5, &"reaction_target")
	)
	var alone_state: State = alone_result.get("state") as State
	_check(
		_event_count(alone_result.get("events", []), &"ability_triggered") == 1,
		"QiXin's summon reaction still triggers when the target is in range"
	)
	_check(
		_event_count(alone_result.get("events", []), &"attack_started") == 0
		and int((alone_state.board[5] as Dictionary).get("owner", 0))
		== Rules.OPPONENT_OWNER,
		"A triggered reaction cannot declare its attack without another ally"
	)

	var allied_result: Dictionary = Simulator.apply_action(
		_make_qixin_reaction_state(true),
		Action.make_play(0, 5, &"reaction_target")
	)
	var allied_state: State = allied_result.get("state") as State
	_check(
		_event_count(allied_result.get("events", []), &"ability_triggered") == 1
		and _event_count(allied_result.get("events", []), &"attack_started") == 1,
		"QiXin's reaction declares one attack when another ally is present"
	)
	_check(
		int((allied_state.board[5] as Dictionary).get("owner", 0))
		== Rules.PLAYER_OWNER,
		"The permitted reaction flips the summoned enemy"
	)


func _test_retained_modifiers_follow_owner() -> void:
	var qixin: Dictionary = Catalog.create_instance(
		&"QiXinLuoChangKong3",
		Rules.PLAYER_OWNER,
		&"retained_qixin"
	)
	var target: Dictionary = Rules.make_card(
		"Target",
		"靶",
		[1, 9, 9, 9],
		[],
		Rules.PLAYER_OWNER
	)
	target["instance_id"] = &"retained_target"
	var board: Array = Rules.empty_board()
	board[4] = {"card": qixin, "owner": Rules.PLAYER_OWNER}
	board[5] = {"card": target, "owner": Rules.PLAYER_OWNER}
	var state := State.new(board)
	Simulator.resolve_non_attack_flip(
		state,
		&"retained_qixin",
		Rules.OPPONENT_OWNER,
		&"fixture_flip"
	)
	var runtime: Dictionary = (state.board[4] as Dictionary).get("card", {})
	_check(
		(runtime.get("active_abilities", []) as Array).size() == 1,
		"Flipping QiXin permanently removes its non-retained reaction ability"
	)
	_check(
		Abilities.has_modifier(runtime, MODIFIER_ATTACK_REQUIRES_OTHER_ALLY)
		and Abilities.has_modifier(runtime, MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE),
		"Both attack modifiers remain after QiXin changes owner"
	)
	_check(
		not BoardQueries.can_attack_target(state.board, 4, 5),
		"Retained ally requirement evaluates from QiXin's new owner"
	)
	var new_ally: Dictionary = Rules.make_card(
		"New Ally",
		"新",
		[1, 1, 1, 1],
		[],
		Rules.OPPONENT_OWNER
	)
	new_ally["instance_id"] = &"retained_ally"
	state.board[0] = {"card": new_ally, "owner": Rules.OPPONENT_OWNER}
	_check(
		BoardQueries.can_attack_target(state.board, 4, 5),
		"A new-owner ally permits the retained minimum-side attack"
	)


func _test_temporary_flip_protection() -> void:
	var protected: Dictionary = Catalog.create_instance(
		&"QiXinLuoChangKong4",
		Rules.OPPONENT_OWNER,
		&"protected_qixin"
	)
	var board: Array = Rules.empty_board()
	board[4] = {"card": protected, "owner": Rules.OPPONENT_OWNER}
	var state := State.new(board, [], [], Rules.PLAYER_OWNER)
	var prevented: Dictionary = Simulator.resolve_non_attack_flip(
		state,
		&"protected_qixin",
		Rules.PLAYER_OWNER,
		&"fixture_flip"
	)
	_check(
		int((state.board[4] as Dictionary).get("owner", 0))
		== Rules.OPPONENT_OWNER
		and _event_count(prevented.get("events", []), &"card_flip_prevented") == 1,
		"QiXin4 prevents its first attempted flip"
	)

	var enemy: Dictionary = Rules.make_card(
		"Enemy",
		"敌",
		[1, 1, 1, 1],
		[],
		Rules.PLAYER_OWNER
	)
	enemy["instance_id"] = &"protection_enemy"
	state.board[0] = {"card": enemy, "owner": Rules.PLAYER_OWNER}
	Simulator.resolve_non_attack_flip(
		state,
		&"protection_enemy",
		Rules.OPPONENT_OWNER,
		&"fixture_enemy_flip"
	)
	var runtime: Dictionary = (state.board[4] as Dictionary).get("card", {})
	_check(
		(runtime.get("active_abilities", []) as Array).size() == 2,
		"An actual enemy flip permanently removes only QiXin4's protection"
	)
	var later: Dictionary = Simulator.resolve_non_attack_flip(
		state,
		&"protected_qixin",
		Rules.PLAYER_OWNER,
		&"fixture_later_flip"
	)
	_check(
		int((state.board[4] as Dictionary).get("owner", 0))
		== Rules.PLAYER_OWNER
		and _event_count(later.get("events", []), &"card_flipped") == 1,
		"QiXin4 can flip after its protection has expired"
	)
	_check(
		((state.board[4] as Dictionary).get("card", {}) as Dictionary)
		.get("active_abilities", []).size() == 1,
		"Only QiXin4's retained modifier ability survives that later flip"
	)

	var turn_protected: Dictionary = Catalog.create_instance(
		&"QiXinLuoChangKong4",
		Rules.PLAYER_OWNER,
		&"turn_qixin"
	)
	var turn_board: Array = Rules.empty_board()
	turn_board[4] = {"card": turn_protected, "owner": Rules.PLAYER_OWNER}
	var quiet: Dictionary = Rules.make_card(
		"Quiet",
		"静",
		[1, 1, 1, 1],
		[],
		Rules.OPPONENT_OWNER
	)
	quiet["instance_id"] = &"quiet_turn_card"
	var turn_state := State.new(
		turn_board,
		[Rules.make_card("Player Reply", "应", [1, 1, 1, 1], [], Rules.PLAYER_OWNER)],
		[quiet],
		Rules.OPPONENT_OWNER
	)
	var turn_result: Dictionary = Simulator.apply_action(
		turn_state,
		Action.make_play(0, 0, &"quiet_turn_card")
	)
	var after_turn: State = turn_result.get("state") as State
	var turn_runtime: Dictionary = (after_turn.board[4] as Dictionary).get("card", {})
	_check(
		(turn_runtime.get("active_abilities", []) as Array).size() == 2,
		"QiXin4's protection expires at the start of its current owner's turn"
	)


func _test_state_copy_isolated() -> void:
	var qixin: Dictionary = Catalog.create_instance(
		&"QiXinLuoChangKong4",
		Rules.PLAYER_OWNER,
		&"copy_qixin"
	)
	var board: Array = Rules.empty_board()
	board[4] = {"card": qixin, "owner": Rules.PLAYER_OWNER}
	var state := State.new(board)
	var copied: State = state.duplicate_state()
	var copied_card: Dictionary = (copied.board[4] as Dictionary).get("card", {})
	(copied_card.get("active_abilities", []) as Array).clear()
	var original_card: Dictionary = (state.board[4] as Dictionary).get("card", {})
	_check(
		(original_card.get("active_abilities", []) as Array).size() == 3,
		"QiXin runtime abilities remain isolated across simulated state copies"
	)


func _make_qixin_summon_state(has_ally: bool) -> State:
	var qixin: Dictionary = Catalog.create_instance(
		&"QiXinLuoChangKong2",
		Rules.PLAYER_OWNER,
		&"qixin_summon"
	)
	var defender: Dictionary = Rules.make_card(
		"Summon Guard",
		"守",
		[1, 9, 9, 9],
		[],
		Rules.OPPONENT_OWNER
	)
	defender["instance_id"] = &"summon_guard"
	var board: Array = Rules.empty_board()
	board[5] = {"card": defender, "owner": Rules.OPPONENT_OWNER}
	if has_ally:
		var ally: Dictionary = Rules.make_card(
			"Summon Ally",
			"友",
			[1, 1, 1, 1],
			[],
			Rules.PLAYER_OWNER
		)
		ally["instance_id"] = &"summon_ally"
		board[0] = {"card": ally, "owner": Rules.PLAYER_OWNER}
	return State.new(board, [qixin], [], Rules.PLAYER_OWNER)


func _make_qixin_reaction_state(has_ally: bool) -> State:
	var qixin: Dictionary = Catalog.create_instance(
		&"QiXinLuoChangKong3",
		Rules.PLAYER_OWNER,
		&"reaction_qixin"
	)
	var target: Dictionary = Rules.make_card(
		"Reaction Target",
		"靶",
		[1, 1, 1, 1],
		[],
		Rules.OPPONENT_OWNER
	)
	target["instance_id"] = &"reaction_target"
	var board: Array = Rules.empty_board()
	board[4] = {"card": qixin, "owner": Rules.PLAYER_OWNER}
	if has_ally:
		var ally: Dictionary = Rules.make_card(
			"Reaction Ally",
			"友",
			[1, 1, 1, 1],
			[],
			Rules.PLAYER_OWNER
		)
		ally["instance_id"] = &"reaction_ally"
		board[0] = {"card": ally, "owner": Rules.PLAYER_OWNER}
	return State.new(board, [], [target], Rules.OPPONENT_OWNER)


func _event_count(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for event_value: Variant in events:
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &""))
			== event_type
		):
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
