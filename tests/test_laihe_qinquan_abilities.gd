extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const Action = preload("res://scripts/duel_action.gd")
const Abilities = preload("res://scripts/duel_abilities.gd")
const CardScene = preload("res://scenes/card_view.tscn")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_declarations()
	_test_revelation_state_is_clone_safe()
	_test_reveal_all_and_future_draws()
	_test_remembered_reveal_and_weakness()
	_test_enemy_remembered_reveal_and_weakness()
	_test_flip_protection()
	await _test_picture_fade()
	if _failures == 0:
		print("LAIHE_QINQUAN_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("LAIHE_QINQUAN_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _test_catalog_declarations() -> void:
	var expected_counts: Dictionary = {
		&"LaiHeQinQuan1": 1,
		&"LaiHeQinQuan2": 2,
		&"LaiHeQinQuan3": 3,
		&"LaiHeQinQuan4": 2,
		&"LaiHeQinQuan5": 3,
	}
	for card_id: StringName in expected_counts:
		var abilities: Array = Catalog.get_definition(card_id).get("abilities", [])
		_check(abilities.size() == int(expected_counts[card_id]), "%s declares its approved abilities" % card_id)
	_check(Catalog.validate_catalog().is_empty(), "LaiHe declarations pass catalog validation")


func _test_revelation_state_is_clone_safe() -> void:
	var card: Dictionary = Catalog.create_instance(&"TuNaShu1", Rules.OPPONENT_OWNER, &"known_card")
	_check(card.get("revealed_to_owner_ids", []) == [Rules.OPPONENT_OWNER], "A card starts revealed to its original owner")
	var state := State.new(Rules.empty_board(), [], [card], Rules.PLAYER_OWNER)
	state.remembered_glyphs_by_owner = {Rules.PLAYER_OWNER: ["吐纳术"]}
	state.future_draw_reveal_audiences = {Rules.OPPONENT_OWNER: [Rules.PLAYER_OWNER]}
	var copied = state.duplicate_state()
	(copied.remembered_glyphs_by_owner[Rules.PLAYER_OWNER] as Array).append("异")
	(copied.future_draw_reveal_audiences[Rules.OPPONENT_OWNER] as Array).clear()
	_check((state.remembered_glyphs_by_owner[Rules.PLAYER_OWNER] as Array) == ["吐纳术"], "Remembered glyphs deep-copy")
	_check((state.future_draw_reveal_audiences[Rules.OPPONENT_OWNER] as Array) == [Rules.PLAYER_OWNER], "Future reveal audiences deep-copy")
	_check(StateKey.build(state) != StateKey.build(copied), "Knowledge state changes the search key")


func _test_reveal_all_and_future_draws() -> void:
	var enemy_hand: Array = [
		Catalog.create_instance(&"TuNaShu1", Rules.OPPONENT_OWNER, &"enemy_a"),
		Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"enemy_b"),
	]
	var reveal_one: Dictionary = Catalog.create_instance(&"LaiHeQinQuan1", Rules.PLAYER_OWNER, &"laihe_1")
	var state := State.new(Rules.empty_board(), [reveal_one], enemy_hand, Rules.PLAYER_OWNER)
	var result: Dictionary = Simulator.apply_action_oracle(state, Action.make_play(0, 4))
	var next: State = result["state"] as State
	_check(_all_revealed(next.get_hand(Rules.OPPONENT_OWNER), Rules.PLAYER_OWNER), "LaiHe1 reveals every current enemy hand card")
	_check(_event_count(result.get("events", []), &"card_revealed") == 2, "LaiHe1 emits one event per newly revealed card")

	var reveal_three: Dictionary = Catalog.create_instance(&"LaiHeQinQuan3", Rules.PLAYER_OWNER, &"laihe_3")
	var drawer: Dictionary = Catalog.create_instance(&"TuNaShu1", Rules.OPPONENT_OWNER, &"enemy_drawer")
	var drawn: Dictionary = Catalog.create_instance(&"TuNaShu1", Rules.OPPONENT_OWNER, &"future_enemy")
	var state_three := State.new(Rules.empty_board(), [reveal_three], [drawer], Rules.PLAYER_OWNER, 0, [], [drawn])
	var result_three: Dictionary = Simulator.apply_action_oracle(state_three, Action.make_play(0, 4))
	var next_three: State = result_three["state"] as State
	_check((next_three.future_draw_reveal_audiences.get(Rules.OPPONENT_OWNER, []) as Array).has(Rules.PLAYER_OWNER), "LaiHe3 permanently enables future enemy-draw reveal")
	var draw_result: Dictionary = Simulator.apply_action_oracle(next_three, Action.make_play(0, 0))
	var after_draw: State = draw_result["state"] as State
	_check(_is_revealed(after_draw.get_hand(Rules.OPPONENT_OWNER)[0], Rules.PLAYER_OWNER), "LaiHe3 reveals a later enemy draw")
	var draw_event_index: int = _event_index(draw_result.get("events", []), &"card_drawn")
	var reveal_event_index: int = _event_index(draw_result.get("events", []), &"card_revealed")
	_check(draw_event_index >= 0 and reveal_event_index == draw_event_index + 1, "A draw event precedes its reveal event")


func _test_remembered_reveal_and_weakness() -> void:
	var remembered: Dictionary = Catalog.create_instance(&"TuNaShu1", Rules.OPPONENT_OWNER, &"remembered_enemy")
	var unknown: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"unknown_enemy")
	var source: Dictionary = Catalog.create_instance(&"LaiHeQinQuan4", Rules.PLAYER_OWNER, &"laihe_4")
	var state := State.new(Rules.empty_board(), [source], [remembered, unknown], Rules.PLAYER_OWNER)
	state.remembered_glyphs_by_owner = {Rules.PLAYER_OWNER: ["吐纳术"]}
	var reveal_result: Dictionary = Simulator.apply_action_oracle(state, Action.make_play(0, 4))
	var revealed_state: State = reveal_result["state"] as State
	_check(_is_revealed(revealed_state.get_hand(Rules.OPPONENT_OWNER)[0], Rules.PLAYER_OWNER), "LaiHe4 reveals a remembered glyph")
	_check(not _is_revealed(revealed_state.get_hand(Rules.OPPONENT_OWNER)[1], Rules.PLAYER_OWNER), "LaiHe4 leaves an unknown glyph concealed")
	var summon_result: Dictionary = Simulator.apply_action_oracle(revealed_state, Action.make_play(0, 0))
	var summoned_state: State = summon_result["state"] as State
	var summoned_card: Dictionary = (summoned_state.board[0] as Dictionary).get("card", {})
	_check(Abilities.has_modifier(summoned_card, Catalog.MODIFIER_DEFENDING_POWER_OVERRIDE), "LaiHe4 grants weakness to a revealed enemy summon")
	_check(_event_count(summon_result.get("events", []), &"ability_gained") == 1, "A successful weakness grant emits one event")
	Simulator.resolve_non_attack_flip(summoned_state, &"remembered_enemy", Rules.PLAYER_OWNER)
	_check(not Abilities.has_modifier(summoned_card, Catalog.MODIFIER_DEFENDING_POWER_OVERRIDE), "Granted weakness is lost when its card flips")

	var first_source: Dictionary = Catalog.create_instance(&"LaiHeQinQuan4", Rules.PLAYER_OWNER, &"grant_one")
	var second_source: Dictionary = Catalog.create_instance(&"LaiHeQinQuan4", Rules.PLAYER_OWNER, &"grant_two")
	var duplicate_target: Dictionary = Catalog.create_instance(&"TuNaShu1", Rules.OPPONENT_OWNER, &"duplicate_target")
	duplicate_target["revealed_to_owner_ids"].append(Rules.PLAYER_OWNER)
	var duplicate_board: Array = Rules.empty_board()
	duplicate_board[3] = {"card": first_source, "owner": Rules.PLAYER_OWNER}
	duplicate_board[6] = {"card": second_source, "owner": Rules.PLAYER_OWNER}
	var duplicate_state := State.new(duplicate_board, [], [duplicate_target], Rules.OPPONENT_OWNER)
	var duplicate_result: Dictionary = Simulator.apply_action_oracle(duplicate_state, Action.make_play(0, 0))
	_check(_event_count(duplicate_result.get("events", []), &"ability_gained") == 1, "Structurally identical weakness grants are idempotent")

	var weakness: Dictionary = {
		"retained_on_flip": false,
		"modifiers": [{"type": Catalog.MODIFIER_DEFENDING_POWER_OVERRIDE, "value": 1}],
	}
	var target: Dictionary = Rules.make_card("Target", "靶", [9, 9, 9, 9], [weakness], Rules.OPPONENT_OWNER)
	var attacker: Dictionary = Rules.make_card("Attacker", "攻", [2, 2, 2, 2], [], Rules.PLAYER_OWNER)
	var board: Array = Rules.empty_board()
	board[4] = {"card": attacker, "owner": Rules.PLAYER_OWNER}
	board[5] = {"card": target, "owner": Rules.OPPONENT_OWNER}
	_check(Rules.can_attack_target(board, 4, 5), "Weakness makes every defending edge count as one")
	_check(int((target["powers"] as Array)[3]) == 9, "Weakness does not alter stored powers")
	_check(Abilities.has_modifier(target, Catalog.MODIFIER_DEFENDING_POWER_OVERRIDE), "Weakness remains queryable for presentation")


func _test_enemy_remembered_reveal_and_weakness() -> void:
	var opening_tuna: Dictionary = Catalog.create_instance(
		&"TuNaShu1",
		Rules.PLAYER_OWNER,
		&"player_opening_tuna"
	)
	var later_same_glyph: Dictionary = Catalog.create_instance(
		&"TuNaShu2",
		Rules.PLAYER_OWNER,
		&"player_later_tuna"
	)
	var later_other_glyph: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan",
		Rules.PLAYER_OWNER,
		&"player_later_taizu"
	)
	var enemy_source: Dictionary = Catalog.create_instance(
		&"LaiHeQinQuan4",
		Rules.OPPONENT_OWNER,
		&"enemy_laihe_4"
	)
	var state := State.new(
		Rules.empty_board(),
		[opening_tuna, later_same_glyph, later_other_glyph],
		[enemy_source],
		Rules.OPPONENT_OWNER
	)
	state.remembered_glyphs_by_owner = {
		Rules.OPPONENT_OWNER: ["吐纳术"],
	}
	var reveal_result: Dictionary = Simulator.apply_action_oracle(
		state,
		Action.make_play(0, 4)
	)
	var revealed_state: State = reveal_result["state"] as State
	var player_hand: Array = revealed_state.get_hand(Rules.PLAYER_OWNER)
	_check(
		_is_revealed(player_hand[0], Rules.OPPONENT_OWNER),
		"Enemy LaiHe4 reveals a remembered player opening card"
	)
	_check(
		_is_revealed(player_hand[1], Rules.OPPONENT_OWNER),
		"Enemy LaiHe4 reveals a later card sharing an opening glyph"
	)
	_check(
		not _is_revealed(player_hand[2], Rules.OPPONENT_OWNER),
		"Enemy LaiHe4 leaves a later unrelated glyph concealed"
	)
	var summon_result: Dictionary = Simulator.apply_action_oracle(
		revealed_state,
		Action.make_play(0, 0)
	)
	var summoned_state: State = summon_result["state"] as State
	var summoned_card: Dictionary = (summoned_state.board[0] as Dictionary).get(
		"card",
		{}
	)
	_check(
		Abilities.has_modifier(
			summoned_card,
			Catalog.MODIFIER_DEFENDING_POWER_OVERRIDE
		),
		"Enemy LaiHe4 grants its weakness to a revealed player summon"
	)


func _test_flip_protection() -> void:
	var protected: Dictionary = Catalog.create_instance(&"LaiHeQinQuan2", Rules.OPPONENT_OWNER, &"protected")
	var board: Array = Rules.empty_board()
	board[4] = {"card": protected, "owner": Rules.OPPONENT_OWNER}
	var state := State.new(board, [], [], Rules.PLAYER_OWNER)
	var result: Dictionary = Simulator.resolve_non_attack_flip(state, &"protected", Rules.PLAYER_OWNER)
	_check(int((state.board[4] as Dictionary).get("owner", 0)) == Rules.OPPONENT_OWNER, "LaiHe protection prevents the first flip")
	_check(_event_count(result.get("events", []), &"card_flip_prevented") == 1, "Prevented flip emits one event")
	_check(_event_count(result.get("events", []), &"card_flipped") == 0, "Prevented flip emits no flipped event")
	var enemy: Dictionary = Rules.make_card("Enemy", "敌", [1, 1, 1, 1], [], Rules.PLAYER_OWNER)
	enemy["instance_id"] = &"enemy_flip"
	state.board[0] = {"card": enemy, "owner": Rules.PLAYER_OWNER}
	Simulator.resolve_non_attack_flip(state, &"enemy_flip", Rules.OPPONENT_OWNER)
	var protected_runtime: Dictionary = (state.board[4] as Dictionary).get("card", {})
	_check((protected_runtime.get("active_abilities", []) as Array).size() == 1, "An actual enemy flip removes only LaiHe2's protection ability")
	var later_result: Dictionary = Simulator.resolve_non_attack_flip(state, &"protected", Rules.PLAYER_OWNER)
	_check(int((state.board[4] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER, "LaiHe2 can flip after its protection expires")
	_check(_event_count(later_result.get("events", []), &"card_flipped") == 1, "Expired protection no longer prevents the flip")

	var attack_target: Dictionary = Catalog.create_instance(&"LaiHeQinQuan2", Rules.OPPONENT_OWNER, &"attack_protected")
	var attack_board: Array = Rules.empty_board()
	attack_board[5] = {"card": attack_target, "owner": Rules.OPPONENT_OWNER}
	var attacker: Dictionary = Rules.make_card("Attacker", "攻", [1, 9, 1, 1], [], Rules.PLAYER_OWNER)
	var attack_state := State.new(attack_board, [attacker], [], Rules.PLAYER_OWNER)
	var attack_result: Dictionary = Simulator.apply_action_oracle(attack_state, Action.make_play(0, 4))
	var after_attack: State = attack_result["state"] as State
	_check(int((after_attack.board[5] as Dictionary).get("owner", 0)) == Rules.OPPONENT_OWNER, "LaiHe protection also prevents an attack flip")
	_check(_event_count(attack_result.get("events", []), &"card_flip_prevented") == 1, "Attack prevention emits the same generic event")

	var turn_protected: Dictionary = Catalog.create_instance(&"LaiHeQinQuan2", Rules.PLAYER_OWNER, &"turn_protected")
	var turn_board: Array = Rules.empty_board()
	turn_board[4] = {"card": turn_protected, "owner": Rules.PLAYER_OWNER}
	var opponent_play: Dictionary = Rules.make_card("Quiet", "静", [1, 1, 1, 1], [], Rules.OPPONENT_OWNER)
	var player_reply: Dictionary = Rules.make_card(
		"Player Reply",
		"应",
		[1, 1, 1, 1],
		[],
		Rules.PLAYER_OWNER
	)
	var turn_state := State.new(
		turn_board,
		[player_reply],
		[opponent_play],
		Rules.OPPONENT_OWNER
	)
	var turn_result: Dictionary = Simulator.apply_action_oracle(turn_state, Action.make_play(0, 0))
	var after_turn: State = turn_result["state"] as State
	var turn_runtime: Dictionary = (after_turn.board[4] as Dictionary).get("card", {})
	_check((turn_runtime.get("active_abilities", []) as Array).size() == 1, "Protection expires at the start of its owner's turn")


func _test_picture_fade() -> void:
	var card_data: Dictionary = Catalog.create_instance(&"TuNaShu1", Rules.OPPONENT_OWNER, &"fade_card")
	card_data["active_abilities"].append({
		"retained_on_flip": false,
		"modifiers": [{"type": Catalog.MODIFIER_DEFENDING_POWER_OVERRIDE, "value": 1}],
	})
	var card: Control = CardScene.instantiate()
	root.add_child(card)
	card.call("configure", card_data, Rules.OPPONENT_OWNER, false)
	await process_frame
	var picture := card.get_node("Overlay/CardPicture") as TextureRect
	_check(is_equal_approx(picture.self_modulate.a, 0.30), "Weakness fades only the central card picture to 30 percent")
	card_data["active_abilities"].clear()
	card.call("sync_runtime_data", card_data, Rules.OPPONENT_OWNER)
	_check(is_equal_approx(picture.self_modulate.a, 1.0), "Removing weakness restores full picture opacity")
	card.queue_free()
	await process_frame


func _all_revealed(cards: Array, observer: int) -> bool:
	for card_value: Variant in cards:
		if not _is_revealed(card_value as Dictionary, observer):
			return false
	return true


func _is_revealed(card: Dictionary, observer: int) -> bool:
	return observer in (card.get("revealed_to_owner_ids", []) as Array)


func _event_count(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for event_value: Variant in events:
		if event_value is Dictionary and StringName((event_value as Dictionary).get("type", &"")) == event_type:
			count += 1
	return count


func _event_index(events: Array, event_type: StringName) -> int:
	for index: int in range(events.size()):
		var event_value: Variant = events[index]
		if event_value is Dictionary and StringName((event_value as Dictionary).get("type", &"")) == event_type:
			return index
	return -1


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
