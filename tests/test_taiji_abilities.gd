extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Abilities = preload("res://scripts/duel_abilities.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_and_vocabulary()
	_test_reversed_comparison_once()
	_test_attack_target_policies()
	_test_attack_counter_state()
	_test_sanhuan_redirects_summon_attack()
	_test_other_friendly_fire_consumes_all_taiji_redirects()
	_test_enemy_attack_against_taiji_ally_does_not_consume_redirect()
	_test_sanhuan_resurrects_same_instance()
	_test_dakui_strengthens_then_attacks_allies()
	_test_luanhuan_starts_adjacent_attacks()
	_test_attack_cap_stops_later_attackers()
	_test_yinyang_grants_two_separate_abilities()
	_finish()


func _test_catalog_and_vocabulary() -> void:
	_check(Catalog.validate_catalog().is_empty(), "The catalog accepts all six Taiji declarations")
	_check(
		Catalog.CONDITION_ATTACK_TARGETED_ATTACKER_ALLY
		in Catalog.KNOWN_TRIGGER_CONDITIONS,
		"Attacks against attacker allies use a registered trigger condition"
	)
	for card_id: StringName in [
		&"TaiJiSanHuan4", &"TaiJiSanHuan5", &"TaiJiDaKui5",
		&"TaiJiLuanHuan4", &"TaiJiLuanHuan5", &"TaiJiYinYang5",
	]:
		_check(
			not (Catalog.get_definition(card_id).get("abilities", []) as Array).is_empty(),
			"%s declares its complete ability" % card_id
		)
	for card_id: StringName in [&"TaiJiSanHuan4", &"TaiJiSanHuan5", &"TaiJiDaKui5"]:
		var common_ability: Dictionary = (
			Catalog.get_definition(card_id).get("abilities", []) as Array
		)[0]
		var common_trigger: Dictionary = (
			common_ability.get("triggers", []) as Array
		)[0]
		_check(
			common_ability.get("modifiers", []) == [{
				"type": Catalog.MODIFIER_ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES,
			}]
			and common_trigger.get("event", &"") == Catalog.TRIGGER_CARD_AFTER_ATTACK
			and common_trigger.get("conditions", []) == [
				{"type": Catalog.CONDITION_ATTACKER_CARD_IS_ENEMY},
				{"type": Catalog.CONDITION_ATTACK_TARGETED_ATTACKER_ALLY},
			]
			and common_trigger.get("actions", []) == [{
				"type": Catalog.ACTION_REMOVE_THIS_ABILITY,
			}],
			"%s declares the shared one-use friendly-fire redirect" % card_id
		)


func _test_reversed_comparison_once() -> void:
	var ordinary: Dictionary = _plain(&"ordinary", [4, 4, 4, 4], Rules.PLAYER_OWNER)
	var reversed: Dictionary = Catalog.create_instance(
		&"TaiJiLuanHuan4", Rules.OPPONENT_OWNER, &"reversed"
	)
	var board: Array = Rules.empty_board()
	board[4] = _slot(ordinary, Rules.PLAYER_OWNER)
	board[1] = _slot(reversed, Rules.OPPONENT_OWNER)
	_check(Rules.can_attack_target(board, 4, 1), "A lower edge wins against a reversed defender")
	_check(not Rules.can_attack_target(board, 1, 4), "A higher reversed attacker loses to a lower edge")
	(board[4] as Dictionary)["card"] = Catalog.create_instance(
		&"TaiJiLuanHuan4", Rules.PLAYER_OWNER, &"second_reversed"
	)
	_check(
		not Rules.can_attack_target(board, 4, 1),
		"Two reversed participants still reverse once and ties fail"
	)


func _test_attack_target_policies() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(_plain(&"policy_source", [9, 9, 9, 9], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[1] = _slot(_plain(&"policy_ally", [1, 1, 1, 1], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[3] = _slot(_plain(&"policy_enemy", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	_check(
		Rules.can_attack_target(board, 4, 1, {"attack_target_policy": Catalog.ATTACK_TARGET_ALLIES_ONLY})
		and not Rules.can_attack_target(board, 4, 3, {"attack_target_policy": Catalog.ATTACK_TARGET_ALLIES_ONLY}),
		"Allies-only attacks exclude enemies"
	)
	_check(
		Rules.can_attack_target(board, 4, 1, {"attack_target_policy": Catalog.ATTACK_TARGET_ALL})
		and Rules.can_attack_target(board, 4, 3, {"attack_target_policy": Catalog.ATTACK_TARGET_ALL}),
		"All-target attacks include both owners"
	)


func _test_attack_counter_state() -> void:
	var state := State.new()
	var initial_key: String = StateKey.build(state)
	state.attacks_started_by_owner[Rules.PLAYER_OWNER] = 7
	var copied: State = state.duplicate_state() as State
	_check(
		int(copied.attacks_started_by_owner.get(Rules.PLAYER_OWNER, 0)) == 7,
		"State duplication preserves attack counts"
	)
	_check(initial_key != StateKey.build(state), "State keys distinguish attack counts")


func _test_sanhuan_redirects_summon_attack() -> void:
	var board: Array = Rules.empty_board()
	board[1] = _slot(
		Catalog.create_instance(&"TaiJiSanHuan4", Rules.PLAYER_OWNER, &"sanhuan_guard"),
		Rules.PLAYER_OWNER
	)
	board[7] = _slot(
		Catalog.create_instance(&"TaiJiSanHuan5", Rules.PLAYER_OWNER, &"second_guard"),
		Rules.PLAYER_OWNER
	)
	board[3] = _slot(_plain(&"summoner_ally", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[5] = _slot(_plain(&"summoner_enemy", [1, 1, 1, 1], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[_plain(&"sanhuan_reply", [1, 1, 1, 1], Rules.PLAYER_OWNER)],
			[_plain(&"redirected_summon", [9, 9, 9, 9], Rules.OPPONENT_OWNER)],
			Rules.OPPONENT_OWNER
		),
		Action.make_play(0, 4, &"redirected_summon")
	)
	var next_state: State = transition.get("state") as State
	_check(
		int((next_state.board[3] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER
		and int((next_state.board[5] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER,
		"An adjacent SanHuan redirects only the summoner's ally and flips it to the enemy"
	)
	_check(
		not Abilities.has_modifier(
			(next_state.board[1] as Dictionary).get("card", {}),
			Catalog.MODIFIER_ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES
		)
		and not Abilities.has_modifier(
			(next_state.board[7] as Dictionary).get("card", {}),
			Catalog.MODIFIER_ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES
		),
		"Every adjacent Taiji source loses the redirect after the summoned enemy attacks its ally"
	)


func _test_other_friendly_fire_consumes_all_taiji_redirects() -> void:
	var board: Array = Rules.empty_board()
	board[1] = _slot(_plain(&"friendly_fire_ally", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[3] = _slot(_plain(&"friendly_fire_enemy", [1, 1, 1, 1], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[4] = _slot(_plain(&"friendly_fire_attacker", [9, 9, 9, 9], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[6] = _slot(Catalog.create_instance(&"TaiJiSanHuan4", Rules.PLAYER_OWNER, &"watcher_one"), Rules.PLAYER_OWNER)
	board[0] = _slot(Catalog.create_instance(&"LeiZHenJian3", Rules.PLAYER_OWNER, &"yizi_modifier"), Rules.PLAYER_OWNER)
	board[8] = _slot(Catalog.create_instance(&"TaiJiDaKui5", Rules.PLAYER_OWNER, &"watcher_two"), Rules.PLAYER_OWNER)
	var state := State.new(board, [], [], Rules.OPPONENT_OWNER)
	var result: Dictionary = Simulator._resolve_standard_attacks(
		state,
		4,
		&"friendly_fire_attacker",
		&"test_yizi_friendly_fire"
	)
	_check(
		_count_events(result.get("events", []), &"attack_started") == 2,
		"YiZi causes the enemy to attack both owners"
	)
	_check(
		not Abilities.has_modifier(
			(state.board[6] as Dictionary).get("card", {}),
			Catalog.MODIFIER_ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES
		)
		and not Abilities.has_modifier(
			(state.board[8] as Dictionary).get("card", {}),
			Catalog.MODIFIER_ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES
		),
		"Friendly fire caused by another card consumes every enemy Taiji redirect"
	)


func _test_enemy_attack_against_taiji_ally_does_not_consume_redirect() -> void:
	var board: Array = Rules.empty_board()
	board[1] = _slot(_plain(&"ordinary_target", [1, 1, 1, 1], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[4] = _slot(_plain(&"ordinary_enemy", [9, 9, 9, 9], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[8] = _slot(Catalog.create_instance(&"TaiJiSanHuan4", Rules.PLAYER_OWNER, &"ordinary_watcher"), Rules.PLAYER_OWNER)
	var state := State.new(board, [], [], Rules.OPPONENT_OWNER)
	var result: Dictionary = Simulator._resolve_standard_attacks(
		state,
		4,
		&"ordinary_enemy",
		&"test_enemy_attack"
	)
	_check(
		_count_events(result.get("events", []), &"attack_started") == 1
		and Abilities.has_modifier(
			(state.board[8] as Dictionary).get("card", {}),
			Catalog.MODIFIER_ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES
		),
		"An enemy attacking the Taiji owner's ally does not consume the redirect"
	)


func _test_sanhuan_resurrects_same_instance() -> void:
	var source: Dictionary = Catalog.create_instance(&"TaiJiSanHuan5", Rules.PLAYER_OWNER, &"sanhuan_five")
	var skipped: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"zero_removed")
	skipped["powers"] = [0, 0, 0, 0]
	var negative_skipped: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan",
		Rules.PLAYER_OWNER,
		&"negative_removed"
	)
	negative_skipped["powers"] = [-1, -1, -1, -1]
	var revived: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"revived_exact")
	revived["powers"] = [2, 3, 4, 5]
	revived["ki"] = 2
	var board: Array = Rules.empty_board()
	board[4] = _slot(source, Rules.PLAYER_OWNER)
	var state := State.new(board, [], [], Rules.PLAYER_OWNER, 0, [_plain(&"drawn", [1, 1, 1, 1], Rules.PLAYER_OWNER)], [])
	state.removed_cards[Rules.PLAYER_OWNER] = [skipped, negative_skipped, revived]
	var transition: Dictionary = Simulator.apply_action(
		state,
		Action.make_activate(4, &"sanhuan_five", Action.TARGET_BOARD_CELL, 8, 0)
	)
	var next_state: State = transition.get("state") as State
	var runtime: Dictionary = (next_state.board[8] as Dictionary).get("card", {})
	_check(
		StringName(runtime.get("instance_id", &"")) == &"revived_exact"
		and runtime.get("powers", []) == [2, 3, 4, 5]
		and int(runtime.get("ki", 0)) == 2,
		"SanHuan skips cards without ordinary powers and summons the same preserved instance"
	)
	var remaining_removed: Array = next_state.removed_cards.get(
		Rules.PLAYER_OWNER,
		[]
	) as Array
	_check(
		(state.removed_cards.get(Rules.PLAYER_OWNER, []) as Array).size() == 3
		and remaining_removed.size() == 2
		and StringName((remaining_removed[0] as Dictionary).get("instance_id", &""))
		== &"zero_removed"
		and StringName((remaining_removed[1] as Dictionary).get("instance_id", &""))
		== &"negative_removed"
		and next_state.get_hand(Rules.PLAYER_OWNER).size() == 1,
		"Only the powered instance leaves removal and the activation draws one"
	)


func _test_dakui_strengthens_then_attacks_allies() -> void:
	var board: Array = Rules.empty_board()
	board[8] = _slot(Catalog.create_instance(&"TaiJiDaKui5", Rules.PLAYER_OWNER, &"dakui"), Rules.PLAYER_OWNER)
	board[4] = _slot(_plain(&"dakui_enemy", [9, 9, 9, 9], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[1] = _slot(_plain(&"dakui_enemy_ally", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[3] = _slot(_plain(&"dakui_player_card", [1, 1, 1, 1], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [], [], Rules.PLAYER_OWNER),
		Action.make_activate(8, &"dakui", Action.TARGET_BOARD_CELL, 4, 0)
	)
	var next_state: State = transition.get("state") as State
	_check(
		((next_state.board[4] as Dictionary).get("card", {}) as Dictionary).get("powers", []) == [10, 10, 10, 10]
		and int((next_state.board[1] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER
		and int((next_state.board[3] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER,
		"DaKui adds one then enemy attacks flip only their own allies"
	)


func _test_luanhuan_starts_adjacent_attacks() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(_plain(&"luan_enemy_for_ally", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[3] = _slot(_plain(&"luan_adjacent_ally", [9, 9, 9, 9], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[5] = _slot(_plain(&"luan_entry_enemy", [9, 9, 9, 9], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[Catalog.create_instance(&"TaiJiLuanHuan5", Rules.PLAYER_OWNER, &"luan_source")],
			[],
			Rules.PLAYER_OWNER
		),
		Action.make_play(0, 4, &"luan_source")
	)
	var next_state: State = transition.get("state") as State
	_check(
		int((next_state.board[0] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER,
		"LuanHuan makes an adjacent ally attack after its real reversed attack"
	)


func _test_attack_cap_stops_later_attackers() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(&"TaiJiDaKui5", Rules.PLAYER_OWNER, &"cap_dakui"), Rules.PLAYER_OWNER)
	board[0] = _slot(_plain(&"first_capped_attacker", [9, 9, 9, 9], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[6] = _slot(_plain(&"second_capped_attacker", [9, 9, 9, 9], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[1] = _slot(_plain(&"first_capped_ally", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[7] = _slot(_plain(&"second_capped_ally", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var state := State.new(board, [], [], Rules.PLAYER_OWNER)
	state.attacks_started_by_owner[Rules.OPPONENT_OWNER] = Simulator.MAX_ATTACKS_PER_OWNER_TURN - 1
	var transition: Dictionary = Simulator.apply_action(
		state,
		Action.make_activate(4, &"cap_dakui", Action.TARGET_BOARD_CELL, 0, 0)
	)
	_check(
		_count_events(transition.get("events", []), &"attack_started") == 1,
		"The twentieth attack starts and later attacks by that owner are suppressed"
	)
func _test_yinyang_grants_two_separate_abilities() -> void:
	var board: Array = Rules.empty_board()
	board[1] = _slot(_plain(&"yinyang_enemy", [9, 9, 9, 9], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[8] = _slot(_plain(&"yinyang_survivor", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[Catalog.create_instance(&"TaiJiYinYang5", Rules.PLAYER_OWNER, &"taiji_yinyang")],
			[],
			Rules.PLAYER_OWNER
		),
		Action.make_play(0, 4, &"taiji_yinyang")
	)
	var next_state: State = transition.get("state") as State
	var enemy: Dictionary = (next_state.board[8] as Dictionary).get("card", {})
	_check(
		Abilities.has_modifier(enemy, Catalog.MODIFIER_DEFENDING_POWER_OVERRIDE)
		and _has_retained_ability(enemy),
		"YinYang grants separate zero-defense and retained exile abilities"
	)


func _plain(instance_id: StringName, powers: Array[int], owner_id: int) -> Dictionary:
	var card: Dictionary = Rules.make_card(
		String(instance_id), String(instance_id), powers, [], owner_id, instance_id
	)
	card["instance_id"] = instance_id
	return card


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _has_retained_ability(card: Dictionary) -> bool:
	for ability_value: Variant in card.get("active_abilities", []):
		if ability_value is Dictionary and bool((ability_value as Dictionary).get("retained_on_flip", false)):
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


func _finish() -> void:
	if _failures == 0:
		print("TAIJI_ABILITY_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("TAIJI_ABILITY_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)
