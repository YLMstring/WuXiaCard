extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Compact = preload("res://scripts/duel_compact_state.gd")
const Action = preload("res://scripts/duel_action.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const Abilities = preload("res://scripts/duel_abilities.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_abilities()
	_test_move_fallback_declarations()
	_test_conditional_generated_card()
	_test_locked_discard_source_hand_play()
	_test_tier_three_generation()
	_test_yunv_adjacent_entry()
	_test_next_hand_queue()
	_test_duplicate_queue_names_defer()
	_test_attack_modifiers_are_independent()
	_test_attack_attempt_presentation_events()
	_test_extra_play_attempt_draws_at_cap()
	_test_discard_source_extra_play_preserves_queue()
	_test_ally_attack_evasion()
	_test_evasion_failure()
	_test_suppression_duration()
	_test_tianluo_locked_move_penalty()
	_test_langji_tianluo_swap_penalty()
	_test_tianluo_acquired_snapshot()
	if _failures == 0:
		print("GUMU_ABILITY_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("GUMU_ABILITY_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _test_catalog_abilities() -> void:
	for card_id: StringName in [
		&"YuNvWuFeng",
		&"LangJiTianYa1", &"LangJiTianYa2", &"LangJiTianYa3",
		&"XiaoYuanYiJu1", &"XiaoYuanYiJu2", &"XiaoYuanYiJu3", &"XiaoYuanYiJu4",
		&"LengYueKuiRen1", &"LengYueKuiRen2", &"LengYueKuiRen3",
		&"KongBi1", &"KongBi2", &"KongBi3", &"KongBi4",
		&"TianLuoDiWang2", &"TianLuoDiWang3", &"TianLuoDiWang4",
	]:
		_check(Catalog.has_card(card_id), "%s is registered" % card_id)
		_check(not (Catalog.get_definition(card_id).get("abilities", []) as Array).is_empty(),
			"%s has rule abilities" % card_id)
	var expected_arrays: Dictionary = {
		&"YuNvWuFeng": [Catalog.GUMU_YUNV_DISCARD_SOURCE, Catalog.GUMU_YUNV_ENTER],
		&"LangJiTianYa3": [Catalog.GUMU_TIER_THREE_ADD_YUNV, Catalog.GUMU_ATTACK_EACH_TARGET_TWICE, Catalog.GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, Catalog.GUMU_QUEUE_NEXT_SWAP],
		&"LengYueKuiRen3": [Catalog.GUMU_TIER_THREE_ADD_YUNV, Catalog.GUMU_ATTACK_EACH_TARGET_TWICE, Catalog.GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, Catalog.GUMU_QUEUE_NEXT_MINIMUM_DEFENSE],
		&"XiaoYuanYiJu3": [Catalog.GUMU_ATTACK_EACH_TARGET_TWICE, Catalog.GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, Catalog.GUMU_QUEUE_NEXT_PERMANENT_SUPPRESSION],
		&"XiaoYuanYiJu4": [Catalog.GUMU_TIER_THREE_ADD_YUNV, Catalog.GUMU_ATTACK_EACH_TARGET_TWICE, Catalog.GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, Catalog.GUMU_QUEUE_NEXT_PERMANENT_SUPPRESSION],
		&"KongBi4": [Catalog.GUMU_DRAW_BEFORE_CONTINUOUS_ACTION_ATTEMPT, Catalog.GUMU_ALLY_ATTACK_EVASION_OR_EXILE],
	}
	for card_id: StringName in expected_arrays:
		var abilities: Array = Catalog.get_definition(card_id).get("abilities", [])
		_check(abilities == expected_arrays[card_id], "%s follows its complete designed ability array" % card_id)
		for ability_value: Variant in abilities:
			_check(not (ability_value as Dictionary).has("activation"), "%s has no retired tier-three activation" % card_id)
	for ability: Dictionary in Catalog.get_definition(&"YuNvWuFeng").get("abilities", []):
		_check(bool(ability.get("retained_on_flip", false)), "Both YuNv locked abilities retain on flip")


func _test_move_fallback_declarations() -> void:
	var ability: Dictionary = Catalog.GUMU_ALLY_ATTACK_EVASION_OR_EXILE.duplicate(true)
	_check(Catalog.validate_ability(ability).is_empty(), "Move fallback declaration is valid")
	_check(Abilities.has_other_card_exile(Catalog.create_instance(&"KongBi4", 1, &"bead_four")), "KongBi fourth-tier exile branch participates in generic bead recognition")
	_check(not Abilities.has_other_card_exile(Catalog.create_instance(&"KongBi3", 1, &"bead_three")), "Third-tier evasion has no exile marker")
	for invalid_value: Variant in [[], true, [42], [{"type": &"unknown_action"}], [{"type": Catalog.ACTION_EXILE_CARD, "card": Catalog.CARD_REF_TRIGGER_CARD, "unknown": true}]]:
		var invalid: Dictionary = ability.duplicate(true)
		invalid["triggers"][0]["actions"][0]["on_no_effect"] = invalid_value
		_check(not Catalog.validate_ability(invalid).is_empty(), "Catalog rejects malformed move fallback")
		var card: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", 1, &"invalid_fallback")
		card["active_abilities"] = [invalid]
		var compact := Compact.new()
		_check(compact.capture_state(State.new(Rules.empty_board(), [card])), "Invalid declaration fixture captures for independent native audit")
		var kernel: Object = ClassDB.instantiate(&"DuelNativeCompactKernel")
		_check(not bool(kernel.call("load_compact_payload", compact.to_variant_payload())), "Native compiler independently rejects malformed move fallback")
	var nested: Dictionary = ability.duplicate(true)
	nested["triggers"][0]["actions"][0]["on_no_effect"] = [{"type": Catalog.ACTION_GRANT_ABILITY_TO_SELF, "ability": {"modifiers": [{"type": Catalog.MODIFIER_CANNOT_ATTACK}]}}]
	var normalized: Dictionary = Catalog.normalize_ability(nested)
	_check(normalized["triggers"][0]["actions"][0]["on_no_effect"][0]["ability"].has("retained_on_flip"), "Nested fallback grants are normalized like ordinary action grants")


func _test_conditional_generated_card() -> void:
	var ability: Dictionary = {
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{
				"type": Catalog.ACTION_ADD_CARD_TO_HAND,
				"card_id": &"YuNvWuFeng",
				"recipient": Catalog.RECIPIENT_SELF,
				"only_if_absent": true,
			}],
		}],
	}
	_check(Catalog.validate_ability(ability).is_empty(), "Fixed-card add accepts an optional absence guard")
	for invalid_value: Variant in ["yes", 1]:
		var invalid: Dictionary = ability.duplicate(true)
		invalid["triggers"][0]["actions"][0]["only_if_absent"] = invalid_value
		_check(not Catalog.validate_ability(invalid).is_empty(), "Absence guard rejects a non-Boolean value")
	var dynamic: Dictionary = ability.duplicate(true)
	dynamic["triggers"][0]["actions"][0].erase("card_id")
	dynamic["triggers"][0]["actions"][0]["card"] = {
		"type": Catalog.CARD_SPEC_FRESH_COPY,
		"of": Catalog.CARD_REF_ABILITY_SOURCE,
	}
	_check(not Catalog.validate_ability(dynamic).is_empty(), "Absence guard requires a fixed card ID")
	for existing: bool in [false, true]:
		var source: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"generate_source")
		source["active_abilities"] = [ability]
		var board: Array = Rules.empty_board()
		board[4] = {"card": source, "owner": Rules.PLAYER_OWNER}
		var hand: Array = [Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"other_hand")]
		if existing:
			var already: Dictionary = Catalog.create_instance(&"YuNvWuFeng", Rules.PLAYER_OWNER, &"already_yunv")
			already["hand_slot_index"] = 4
			hand.append(already)
		var opponent_hand: Array = []
		if not existing:
			opponent_hand.append(Catalog.create_instance(&"YuNvWuFeng", Rules.OPPONENT_OWNER, &"opponent_prototype"))
		var state := State.new(board, hand, opponent_hand, Rules.PLAYER_OWNER)
		var result: Dictionary = Simulator._resolve_trigger_event(state, Catalog.TRIGGER_CARD_SUMMONED, {
			"trigger_instance_id": &"generate_source",
			"trigger_cell": 4,
			"trigger_owner_id": Rules.PLAYER_OWNER,
		})
		_check(bool(result.get("valid", false)), "Guarded generated-card trigger resolves with existing=%s" % str(existing))
		var found: int = 0
		for card_value: Variant in state.hands[Rules.PLAYER_OWNER]:
			if StringName((card_value as Dictionary).get("card_id", &"")) == &"YuNvWuFeng":
				found += 1
		_check(found == 1, "Guarded addition leaves exactly one YuNv with existing=%s" % str(existing))
		_check(_event_count(result.get("events", []), &"card_added_to_hand") == (0 if existing else 1), "Only a missing YuNv emits an add event")
	var full_source: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"full_source")
	full_source["active_abilities"] = [ability]
	var full_board: Array = Rules.empty_board()
	full_board[4] = {"card": full_source, "owner": Rules.PLAYER_OWNER}
	var full_hand: Array = []
	for index: int in range(5):
		full_hand.append(Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, StringName("full_%d" % index)))
	var full_state := State.new(full_board, full_hand, [], Rules.PLAYER_OWNER)
	var full_result: Dictionary = Simulator._resolve_trigger_event(full_state, Catalog.TRIGGER_CARD_SUMMONED, {
		"trigger_instance_id": &"full_source", "trigger_cell": 4,
		"trigger_owner_id": Rules.PLAYER_OWNER,
	})
	_check(bool(full_result.get("valid", false)), "Full hand does not invalidate guarded generation")
	_check((full_state.hands[Rules.PLAYER_OWNER] as Array).size() == 5, "Full hand remains unchanged")


func _test_locked_discard_source_hand_play() -> void:
	var source_ability: Dictionary = {
		"retained_on_flip": true,
		"modifiers": [{"type": &"hand_play_as_discard"}],
	}
	_check(Catalog.validate_ability(source_ability).is_empty(), "Locked discard-source hand modifier is a valid ability")
	for has_opportunity_marker: bool in [false, true]:
		var played: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"source_play")
		played["active_abilities"] = [source_ability]
		var state := State.new(Rules.empty_board(), [played], [], Rules.PLAYER_OWNER)
		state.effect_queue = [_queue_grant("冷月窥人", Catalog.GUMU_MINIMUM_DEFENSE_ON_ATTACK)]
		if has_opportunity_marker:
			state.next_hand_play_from_discard_owner = Rules.PLAYER_OWNER
		var result: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4, &"source_play"))
		var next: State = result.get("state") as State
		_check(bool(result.get("valid", false)) and next != null, "Locked source play resolves with marker=%s" % str(has_opportunity_marker))
		if next == null:
			continue
		_check(next.effect_queue.size() == 1, "Locked source play leaves next-hand queue intact")
		_check((next.last_hand_play_by_owner.get(Rules.PLAYER_OWNER, {}) as Dictionary).is_empty(), "Locked source play does not update hand-play history")
		_check(next.next_hand_play_from_discard_owner == 0, "Existing source marker clears after play")
	var flipped: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"locked_flip")
	flipped["active_abilities"] = [source_ability]
	var flip_board: Array = Rules.empty_board()
	flip_board[4] = {"card": flipped, "owner": Rules.PLAYER_OWNER}
	var flip_state := State.new(flip_board)
	Simulator.resolve_non_attack_flip(flip_state, &"locked_flip", Rules.OPPONENT_OWNER)
	var remaining: Array = ((flip_state.board[4] as Dictionary).get("card", {}) as Dictionary).get("active_abilities", [])
	_check(remaining.size() == 1, "Locked source modifier survives ownership flip")


func _test_next_hand_queue() -> void:
	var first := Catalog.create_instance(&"LangJiTianYa1", Rules.PLAYER_OWNER, &"grantor")
	var state := State.new(Rules.empty_board(), [first], [], Rules.PLAYER_OWNER)
	var result: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4, &"grantor"))
	_check(bool(result.get("valid", false)), "LangJi enters the board")
	var next: State = result.get("state") as State
	if next == null:
		return
	_check(next.effect_queue.size() == 1, "LangJi queues one next-hand grant")
	if next.effect_queue.size() == 1:
		var entry: Dictionary = next.effect_queue[0]
		_check(String(entry.get("grantor_name", "")) == "浪迹天涯",
			"Queue records the grantor's card name")


func _test_duplicate_queue_names_defer() -> void:
	var state := State.new(Rules.empty_board(), [
		Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"queue_first"),
		Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"queue_second"),
	], [Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"queue_enemy")], Rules.PLAYER_OWNER)
	state.effect_queue = [
		_queue_grant("浪迹天涯", Catalog.GUMU_MINIMUM_DEFENSE_ON_ATTACK),
		_queue_grant("浪迹天涯", Catalog.GUMU_WEAKEN_TARGET_ON_POWER_FAILURE),
		_queue_grant("冷月窥人", Catalog.GUMU_ATTACK_EACH_TARGET_TWICE),
	]
	var first: Dictionary = Simulator.apply_action(state, Action.make_play(0, 0, &"queue_first"))
	var after_first: State = first.get("state") as State
	_check(bool(first.get("valid", false)), "First queued hand play resolves")
	if after_first == null:
		return
	var first_abilities: Array = ((after_first.board[0] as Dictionary).get("card", {}) as Dictionary).get("active_abilities", [])
	_check(first_abilities.has(Catalog.GUMU_MINIMUM_DEFENSE_ON_ATTACK) and first_abilities.has(Catalog.GUMU_ATTACK_EACH_TARGET_TWICE), "Different grantor names stack in FIFO order")
	_check(after_first.effect_queue.size() == 1 and String((after_first.effect_queue[0] as Dictionary).get("grantor_name", "")) == "浪迹天涯", "Second same-name record remains queued")
	after_first.active_player = Rules.PLAYER_OWNER
	var second: Dictionary = Simulator.apply_action(after_first, Action.make_play(0, 8, &"queue_second"))
	var after_second: State = second.get("state") as State
	_check(bool(second.get("valid", false)) and after_second.effect_queue.is_empty(), "Deferred same-name grant is consumed by next hand play")
	var second_abilities: Array = ((after_second.board[8] as Dictionary).get("card", {}) as Dictionary).get("active_abilities", [])
	_check(second_abilities.has(Catalog.GUMU_WEAKEN_TARGET_ON_POWER_FAILURE), "Deferred ability reaches the second card")


func _test_attack_modifiers_are_independent() -> void:
	for mode: int in range(3):
		var attacker: Dictionary = Catalog.create_instance(&"LangJiTianYa2", Rules.PLAYER_OWNER, &"attack_%d" % mode)
		var abilities: Array = []
		if mode != 1:
			abilities.append(Catalog.GUMU_WEAKEN_TARGET_ON_POWER_FAILURE)
		if mode != 0:
			abilities.append(Catalog.GUMU_ATTACK_EACH_TARGET_TWICE)
		attacker["active_abilities"] = abilities
		var defender: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"defend_%d" % mode)
		defender["powers"] = [2, 2, 2, 6]
		var board: Array = Rules.empty_board()
		board[5] = {"card": defender, "owner": Rules.OPPONENT_OWNER}
		var result: Dictionary = Simulator.apply_action(State.new(board, [attacker], [], Rules.PLAYER_OWNER), Action.make_play(0, 4, StringName("attack_%d" % mode)))
		var next: State = result.get("state") as State
		_check(bool(result.get("valid", false)), "Attack modifier fixture resolves %d" % mode)
		if next == null or next.board[5] == null:
			continue
		var target: Dictionary = (next.board[5] as Dictionary).get("card", {})
		_check(int((next.board[5] as Dictionary).get("owner", 0)) == (Rules.PLAYER_OWNER if mode == 2 else Rules.OPPONENT_OWNER), "Double attempt and weakening are independent %d" % mode)
		_check(int((target.get("powers", []) as Array)[3]) == (5 if mode == 0 or mode == 2 else 6), "Only failed comparison with weakening changes power %d" % mode)


func _test_attack_attempt_presentation_events() -> void:
	for defense: int in [6, 7]:
		var attacker: Dictionary = Catalog.create_instance(&"LangJiTianYa2", Rules.PLAYER_OWNER, &"attempt_%d" % defense)
		attacker["active_abilities"] = [
			Catalog.GUMU_WEAKEN_TARGET_ON_POWER_FAILURE,
			Catalog.GUMU_ATTACK_EACH_TARGET_TWICE,
		]
		var defender: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"target_%d" % defense)
		defender["powers"] = [2, 2, 2, defense]
		var board: Array = Rules.empty_board()
		board[5] = {"card": defender, "owner": Rules.OPPONENT_OWNER}
		var result: Dictionary = Simulator.apply_action(
			State.new(board, [attacker], [], Rules.PLAYER_OWNER),
			Action.make_play(0, 4, StringName("attempt_%d" % defense))
		)
		_check(bool(result.get("valid", false)), "Two-attempt presentation fixture resolves %d" % defense)
		var relevant: Array[Dictionary] = []
		for item: Variant in result.get("events", []):
			if item is Dictionary and StringName(item.get("type", &"")) in [&"attack_attempted", &"attack_started", &"powers_changed"]:
				relevant.append(item)
		var expected: Array = (
			[&"attack_attempted", &"powers_changed", &"attack_started"]
			if defense == 6 else
			[&"attack_attempted", &"powers_changed", &"attack_attempted", &"powers_changed"]
		)
		var actual: Array[StringName] = []
		for event: Dictionary in relevant:
			actual.append(StringName(event.get("type", &"")))
		_check(actual == expected, "Every attempt has its own ordered attack and power events for defense %d: %s" % [defense, actual])
		for event: Dictionary in relevant:
			if StringName(event.get("type", &"")) == &"powers_changed":
				_check(bool(event.get("animate_separately", false)), "Failure power loss is marked for separate animation")
		if defense == 7 and relevant.size() == 4:
			_check((relevant[1].get("previous_powers", []) as Array)[3] == 7 and (relevant[1].get("powers", []) as Array)[3] == 6, "First failure animates seven to six")
			_check((relevant[3].get("previous_powers", []) as Array)[3] == 6 and (relevant[3].get("powers", []) as Array)[3] == 5, "Second failure animates six to five")


func _test_extra_play_attempt_draws_at_cap() -> void:
	var board: Array = Rules.empty_board()
	board[0] = {"card": Catalog.create_instance(&"KongBi4", Rules.PLAYER_OWNER, &"draw_guard"), "owner": Rules.PLAYER_OWNER}
	var state := State.new(board,
		[Catalog.create_instance(&"YuNvWuFeng", Rules.PLAYER_OWNER, &"extra_source")],
		[], Rules.PLAYER_OWNER, 1,
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"draw_reward")])
	state.extra_card_play_granted_this_turn = true
	var result: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4, &"extra_source"))
	var next: State = result.get("state") as State
	_check(bool(result.get("valid", false)), "YuNv entry resolves at an already-used extra-play cap")
	if next == null:
		return
	_check(_event_count(result.get("events", []), &"card_drawn") == 1, "KongBi draws before the capped extra-play attempt")
	_check(_event_count(result.get("events", []), &"extra_card_play_granted") == 0, "Capped attempt does not grant another play")


func _test_discard_source_extra_play_preserves_queue() -> void:
	var state := State.new(Rules.empty_board(), [
		Catalog.create_instance(&"YuNvWuFeng", Rules.PLAYER_OWNER, &"discard_source"),
		Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"discard_play"),
		Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"normal_play"),
	], [], Rules.PLAYER_OWNER)
	state.effect_queue = [_queue_grant("冷月窥人", Catalog.GUMU_MINIMUM_DEFENSE_ON_ATTACK)]
	var entered: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4, &"discard_source"))
	var after_entry: State = entered.get("state") as State
	_check(bool(entered.get("valid", false)) and after_entry != null, "YuNv entry grants a discard-source extra play")
	if after_entry == null:
		return
	_check(after_entry.effect_queue.size() == 1, "YuNv itself does not consume the hand-play queue")
	_check((after_entry.last_hand_play_by_owner.get(Rules.PLAYER_OWNER, {}) as Dictionary).is_empty(), "YuNv itself does not update hand-play history")
	_check(after_entry.next_hand_play_from_discard_owner == Rules.PLAYER_OWNER, "Extra opportunity carries discard-source marker")
	var played: Dictionary = Simulator.apply_action(after_entry, Action.make_play(0, 0, &"discard_play"))
	var after_play: State = played.get("state") as State
	_check(bool(played.get("valid", false)) and after_play != null, "Discard-source physical hand card is played")
	if after_play == null:
		return
	_check(after_play.effect_queue.size() == 1 and after_play.next_hand_play_from_discard_owner == 0, "Discard-source play leaves hand queue intact and clears its marker")
	_check((after_play.last_hand_play_by_owner.get(Rules.PLAYER_OWNER, {}) as Dictionary).is_empty(), "Discard-source play does not update hand-play history")
	after_play.active_player = Rules.PLAYER_OWNER
	var ordinary: Dictionary = Simulator.apply_action(after_play, Action.make_play(0, 5, &"normal_play"))
	var after_ordinary: State = ordinary.get("state") as State
	_check(bool(ordinary.get("valid", false)) and after_ordinary != null and after_ordinary.effect_queue.is_empty(), "Next normal hand play consumes waiting effect")


func _test_tier_three_generation() -> void:
	for card_id: StringName in [&"LangJiTianYa3", &"XiaoYuanYiJu4", &"LengYueKuiRen3"]:
		var entering: Dictionary = Catalog.create_instance(card_id, Rules.PLAYER_OWNER, &"tier_three")
		var result: Dictionary = Simulator.apply_action(
			State.new(Rules.empty_board(), [entering], [], Rules.PLAYER_OWNER),
			Action.make_play(0, 4, &"tier_three")
		)
		var next: State = result.get("state") as State
		_check(bool(result.get("valid", false)) and next != null, "%s enters without pre-existing YuNv" % card_id)
		if next == null:
			continue
		var count: int = 0
		for card_value: Variant in next.hands[Rules.PLAYER_OWNER]:
			if StringName((card_value as Dictionary).get("card_id", &"")) == &"YuNvWuFeng":
				count += 1
		_check(count == 1, "%s creates one YuNv from an otherwise absent catalog card" % card_id)
		_check(_event_count(result.get("events", []), &"card_added_to_hand") == 1, "%s emits the generated-card event" % card_id)
		_check((next.board[4] as Dictionary).get("card", {}).get("active_abilities", []).size() == 4, "%s keeps its four current rule abilities" % card_id)
		var existing: Dictionary = Catalog.create_instance(&"YuNvWuFeng", Rules.PLAYER_OWNER, &"existing_yunv")
		var duplicate: Dictionary = Simulator.apply_action(
			State.new(Rules.empty_board(), [entering, existing], [], Rules.PLAYER_OWNER),
			Action.make_play(0, 4, &"tier_three")
		)
		_check(bool(duplicate.get("valid", false)), "%s enters with YuNv already held" % card_id)
		_check(_event_count(duplicate.get("events", []), &"card_added_to_hand") == 0, "%s does not generate a duplicate YuNv" % card_id)
	var third: Dictionary = Simulator.apply_action(State.new(Rules.empty_board(), [
		Catalog.create_instance(&"XiaoYuanYiJu3", Rules.PLAYER_OWNER, &"xiao_three")
	], [], Rules.PLAYER_OWNER), Action.make_play(0, 4, &"xiao_three"))
	_check(bool(third.get("valid", false)) and _event_count(third.get("events", []), &"card_added_to_hand") == 0, "Xiao tier three no longer generates YuNv")


func _test_yunv_adjacent_entry() -> void:
	var board: Array = Rules.empty_board()
	var weakened: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"weak_neighbor")
	weakened["powers"] = [2, 2, 2, 2]
	var exiled: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"zero_neighbor")
	exiled["powers"] = [1, 1, 1, 1]
	board[1] = {"card": weakened, "owner": Rules.OPPONENT_OWNER}
	board[5] = {"card": exiled, "owner": Rules.OPPONENT_OWNER}
	var result: Dictionary = Simulator.apply_action(State.new(board, [
		Catalog.create_instance(&"YuNvWuFeng", Rules.PLAYER_OWNER, &"yunv_enter"),
		Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"followup"),
	], [], Rules.PLAYER_OWNER), Action.make_play(0, 4, &"yunv_enter"))
	var next: State = result.get("state") as State
	_check(bool(result.get("valid", false)) and next != null, "YuNv resolves entry beside two enemies")
	if next == null:
		return
	_check(((next.board[1] as Dictionary).get("card", {}) as Dictionary).get("powers", []) == [1, 1, 1, 1], "First adjacent enemy loses one on each side")
	_check(next.board[5] == null, "Second adjacent enemy is exiled when all powers reach zero")
	_check(_event_count(result.get("events", []), &"powers_changed") == 2, "Each adjacent enemy gets its own point-change event")
	_check(next.next_hand_play_from_discard_owner == Rules.PLAYER_OWNER, "YuNv still grants discard-source follow-up after weakening")


func _test_ally_attack_evasion() -> void:
	var board: Array = Rules.empty_board()
	board[0] = {"card": Catalog.create_instance(&"KongBi4", Rules.PLAYER_OWNER, &"evasion_guard"), "owner": Rules.PLAYER_OWNER}
	board[1] = {"card": Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"evasion_ally"), "owner": Rules.PLAYER_OWNER}
	var attacker: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"evasion_attacker")
	attacker["powers"] = [9, 9, 9, 9]
	var result: Dictionary = Simulator.apply_action(State.new(board, [], [attacker], Rules.OPPONENT_OWNER), Action.make_play(0, 4, &"evasion_attacker"))
	var next: State = result.get("state") as State
	_check(bool(result.get("valid", false)) and next != null, "Ally-evasion fixture resolves")
	if next == null:
		return
	_check(next.board[1] == null and next.board[2] != null and StringName(((next.board[2] as Dictionary).get("card", {}) as Dictionary).get("instance_id", &"")) == &"evasion_ally", "Attacked ally moves to first adjacent cell outside attack range")


func _test_evasion_failure() -> void:
	# A full set of neighbours: only tier four removes the attacked instance.
	for tier: int in range(1, 5):
		var board: Array = Rules.empty_board()
		board[0] = {"card": Catalog.create_instance(&"TaiZuChangQuan", 1, &"block_left"), "owner": 1}
		board[1] = {"card": Catalog.create_instance(StringName("KongBi%d" % tier), 1, &"blocked_self"), "owner": 1}
		board[2] = {"card": Catalog.create_instance(&"TaiZuChangQuan", 1, &"block_right"), "owner": 1}
		var attacker: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", 2, &"blocked_attacker")
		attacker["powers"] = [9, 9, 9, 9]
		board[4] = {"card": attacker, "owner": 2}
		var state := State.new(board)
		var result: Dictionary = Simulator._resolve_attack_target(state, 4, &"blocked_attacker", 1, &"blocked_self", &"test")
		_check(bool(result.get("valid", false)), "Blocked KongBi%d attack resolves" % tier)
		_check((state.board[1] == null) == (tier == 4), "Only tier four exiles itself on failed movement")
		_check(_event_count(result.get("events", []), &"card_exiled") == (1 if tier == 4 else 0), "Failed movement emits exactly the intended exile event")
	# The fourth tier protects another ally, including interruption after a cell was available.
	for mode: int in range(3):
		var board: Array = Rules.empty_board()
		board[0] = {"card": Catalog.create_instance(&"KongBi4", 1, &"failure_guard"), "owner": 1}
		var target: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", 1, &"failure_target")
		if mode == 1:
			target["active_abilities"] = [{"triggers": [{
				"event": Catalog.CARD_BEFORE_MOVED,
				"conditions": [{"type": Catalog.CONDITION_MOVING_CARD_IS_SELF}],
				"actions": [{"type": Catalog.ACTION_SUMMON_CARD,
					"card": {"type": Catalog.CARD_SPEC_FRESH_COPY, "of": Catalog.CARD_REF_ABILITY_SOURCE},
					"cell": {"type": Catalog.CELL_REF_FIRST_ADJACENT_EMPTY, "card": Catalog.CARD_REF_ABILITY_SOURCE}}],
			}]}]
		board[1] = {"card": target, "owner": 1}
		if mode == 0:
			board[2] = {"card": Catalog.create_instance(&"TaiZuChangQuan", 1, &"failure_blocker"), "owner": 1}
		var attacker: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", 2, &"failure_attacker")
		attacker["powers"] = [9, 9, 9, 9]
		if mode == 2:
			attacker["active_abilities"] = [{"modifiers": [{"type": Catalog.MODIFIER_UNLIMITED_ATTACK_RANGE}]}]
		board[4] = {"card": attacker, "owner": 2}
		var state := State.new(board)
		var result: Dictionary = Simulator._resolve_attack_target(state, 4, &"failure_attacker", 1, &"failure_target", &"test")
		_check(bool(result.get("valid", false)), "Fourth-tier ally movement mode %d resolves" % mode)
		_check(_event_count(result.get("events", []), &"card_moved") == (1 if mode == 2 else 0), "Only an actual movement emits card_moved")
		_check(_event_count(result.get("events", []), &"card_exiled") == (0 if mode == 2 else 1), "Only actual failure exiles the attacked ally")
		_check(state.board[0] != null, "Failure does not exile the protecting card")
		if mode == 1:
			_check(state.board[2] != null and StringName((state.board[2] as Dictionary)["card"]["instance_id"]) != &"failure_target", "Interrupted movement preserves the new blocker instance")
		if mode == 2:
			_check(state.board[2] != null and StringName((state.board[2] as Dictionary)["card"]["instance_id"]) == &"failure_target", "A successful move inside attack range does not trigger the failure branch")


func _test_suppression_duration() -> void:
	for tier: int in range(1, 5):
		var board: Array = Rules.empty_board()
		var enemy: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", 2, &"suppression_enemy")
		enemy["active_abilities"] = [Catalog.GUMU_ATTACK_EACH_TARGET_TWICE, Catalog.GUMU_YUNV_DISCARD_SOURCE]
		board[8] = {"card": enemy, "owner": 2}
		var ally: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", 1, &"suppression_ally")
		ally["active_abilities"] = [Catalog.GUMU_ATTACK_EACH_TARGET_TWICE]
		board[6] = {"card": ally, "owner": 1}
		var follow: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", 1, &"suppression_follow")
		follow["active_abilities"] = [{"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_GRANT_EXTRA_CARD_PLAY, "amount": 1}],
		}]}]
		var result: Dictionary = Simulator.apply_action(State.new(board, [
			Catalog.create_instance(StringName("XiaoYuanYiJu%d" % tier), 1, &"suppression_source"), follow,
			Catalog.create_instance(&"TaiZuChangQuan", 1, &"suppression_end")
		], [], 1), Action.make_play(0, 4, &"suppression_source"))
		var queued: State = result.get("state") as State
		_check(bool(result.get("valid", false)) and queued != null, "Xiao tier %d queues its effect" % tier)
		if queued == null:
			continue
		_check((queued.board[8] as Dictionary)["card"]["active_abilities"].size() == 2, "Queueing alone does not suppress enemies")
		queued.active_player = 1
		var played: Dictionary = Simulator.apply_action(queued, Action.make_play(0, 0, &"suppression_follow"))
		var suppressed: State = played.get("state") as State
		_check(bool(played.get("valid", false)) and suppressed != null, "Queued suppression resolves")
		if suppressed == null:
			continue
		_check(suppressed.active_player == 1, "Suppression is observed before owner-turn end")
		_check((suppressed.board[8] as Dictionary)["card"]["active_abilities"] == [Catalog.GUMU_YUNV_DISCARD_SOURCE], "Enemy loses non-locked abilities but retains locked abilities")
		_check((suppressed.board[6] as Dictionary)["card"]["active_abilities"].size() == 1, "Suppression leaves friendly abilities intact")
		var ended: Dictionary = Simulator.apply_action(suppressed, Action.make_play(0, 2, &"suppression_end"))
		var final_state: State = ended.get("state") as State
		_check(bool(ended.get("valid", false)) and final_state != null, "Suppression fixture closes the owner turn")
		if final_state != null:
			_check((final_state.board[8] as Dictionary)["card"]["active_abilities"].size() == (2 if tier <= 2 else 1), "Only tiers one and two restore suppressed effects at turn end")


func _test_tianluo_locked_move_penalty() -> void:
	for tier: int in range(2, 5):
		var entering: Dictionary = Catalog.create_instance(StringName("TianLuoDiWang%d" % tier), 1, &"net_source")
		var result: Dictionary = Simulator.apply_action(State.new(Rules.empty_board(), [entering,
			Catalog.create_instance(&"TaiZuChangQuan", 1, &"net_recipient")
		], [], 1), Action.make_play(0, 0, &"net_source"))
		var queued: State = result.get("state") as State
		_check(bool(result.get("valid", false)) and queued != null, "TianLuo%d grants itself and queues" % tier)
		if queued == null:
			continue
		queued.active_player = 1
		var follow: Dictionary = Simulator.apply_action(queued, Action.make_play(0, 2, &"net_recipient"))
		var state: State = follow.get("state") as State
		_check(bool(follow.get("valid", false)) and state != null, "TianLuo queued grant reaches the next hand card")
		if state == null:
			continue
		for flipped: bool in [false, true]:
			if flipped:
				Simulator.resolve_non_attack_flip(state, &"net_source", 2)
				Simulator.resolve_non_attack_flip(state, &"net_recipient", 2)
			var owner: int = 1 if flipped else 2
			var moving: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", owner, &"net_mover")
			moving["powers"] = [9, 9, 9, 9]
			moving["ki"] = 1
			moving["active_abilities"] = [{"activation": {
				"input": Catalog.ACTIVATION_DRAG_TO_TARGET,
				"target_rule": Catalog.TARGET_ADJACENT_EMPTY_BOARD,
				"costs": [{"type": Catalog.ACTION_SPEND_KI, "amount": 1}],
				"actions": [{"type": Catalog.ACTION_MOVE_SELF_TO_TARGET}],
			}}]
			state.board[4] = {"card": moving, "owner": owner}
			state.active_player = owner
			var moved: Dictionary = Simulator.apply_action(state, Action.make_activate(4, &"net_mover", Action.TARGET_BOARD_CELL, 7))
			var after: State = moved.get("state") as State
			_check(bool(moved.get("valid", false)) and after != null, "Enemy movement resolves before/after net ownership flip")
			if bool(moved.get("valid", false)) and after != null and after.board[7] != null:
				_check((after.board[7] as Dictionary)["card"]["powers"] == [5, 5, 5, 5], "Source and recipient each apply minus two, also after flipping")
				_check(_event_count(moved.get("events", []), &"powers_changed") == 2, "Fourth-tier snapshot does not duplicate its printed movement penalty")


func _test_langji_tianluo_swap_penalty() -> void:
	for lang_tier: int in range(1, 4):
		for net_tier: int in range(2, 5):
			var enemy: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", 2, &"swap_enemy")
			enemy["powers"] = [9, 9, 9, 9]
			var state := State.new(Rules.empty_board(), [
				Catalog.create_instance(StringName("LangJiTianYa%d" % lang_tier), 1, &"swap_lang"),
				Catalog.create_instance(StringName("TianLuoDiWang%d" % net_tier), 1, &"swap_net"),
				Catalog.create_instance(&"TaiZuChangQuan", 1, &"swap_spare"),
			], [enemy, Catalog.create_instance(&"TaiZuChangQuan", 2, &"swap_enemy_spare")], 1)
			var last: Dictionary = {}
			for step: Array in [[&"swap_lang", 0], [&"swap_enemy", 4], [&"swap_net", 5]]:
				var index: int = -1
				var hand: Array = state.get_hand(state.active_player)
				for i: int in range(hand.size()):
					if hand[i]["instance_id"] == step[0]:
						index = i
				last = Simulator.apply_action(state, Action.make_play(index, int(step[1]), step[0]))
				_check(bool(last.get("valid", false)), "LangJi%d/TianLuo%d actual alternating play is legal" % [lang_tier, net_tier])
				if not bool(last.get("valid", false)):
					break
				state = last["state"] as State
			if not bool(last.get("valid", false)):
				continue
			var penalties: int = 0
			var events: Array = last.get("events", [])
			for event: Dictionary in events:
				if event.get("type") == &"powers_changed" and event.get("amount") == -2:
					penalties += 1
					_check(event.get("ability_source_instance_id") == &"swap_net" and event.get("instance_id") == &"swap_enemy", "Swap penalty comes from the participating net and targets the displaced enemy")
			_check(penalties == 1, "LangJi%d/TianLuo%d swap applies exactly one enemy-move minus two" % [lang_tier, net_tier])
			_check(state.board[4]["card"]["instance_id"] == &"swap_net" and state.board[5]["card"]["instance_id"] == &"swap_enemy", "Both exact instances finish swapped")
			var expected: int = 7 if net_tier == 2 else 5
			_check(state.board[5]["card"]["powers"] == [expected, expected, expected, expected], "Swap penalty precedes the separate failed-attack penalties")


func _test_tianluo_acquired_snapshot() -> void:
	var source: Dictionary = Catalog.create_instance(&"TianLuoDiWang4", Rules.PLAYER_OWNER, &"tianluo_source")
	(source["active_abilities"] as Array).append(Catalog.GUMU_MINIMUM_DEFENSE_ON_ATTACK)
	var state := State.new(Rules.empty_board(), [source], [], Rules.PLAYER_OWNER)
	state.acquired_ability_indices_by_instance_id[&"tianluo_source"] = [(source["active_abilities"] as Array).size() - 1]
	var result: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4, &"tianluo_source"))
	var next: State = result.get("state") as State
	_check(bool(result.get("valid", false)) and next != null, "TianLuo acquired-ability fixture resolves")
	if next == null or next.effect_queue.is_empty():
		return
	var actions: Array = (next.effect_queue[0] as Dictionary).get("actions", [])
	_check(actions.size() == 2, "TianLuo queues one printed grant and one acquired-ability snapshot")
	if actions.size() == 2:
		_check((actions[1] as Dictionary).get("ability", {}) == Catalog.GUMU_MINIMUM_DEFENSE_ON_ATTACK, "Snapshot excludes printed abilities and the self-granted move penalty")


func _queue_grant(name: String, ability: Dictionary) -> Dictionary:
	return {"owner_id": Rules.PLAYER_OWNER, "grantor_name": name, "actions": [{"type": Catalog.ACTION_GRANT_TRIGGER_CARD_ABILITY, "ability": ability}]}


func _event_count(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for item: Variant in events:
		if item is Dictionary and StringName(item.get("type", &"")) == event_type:
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("CHECK_FAILED: %s" % message)
