extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Action = preload("res://scripts/duel_action.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_vocabulary_and_declarations()
	_test_single_discard_entry_buff()
	_test_lijing_four_partial_payment()
	_test_prevented_self_attack_exiles_target()
	_test_other_attack_prevention_does_not_trigger()
	_test_baocan_attack_gate_and_mutual_exile()
	_test_baocan_four_resummons_two_fresh_copies()
	_test_baocan_four_checks_hand_after_exile_chain()
	_test_baocan_four_checks_empty_hand_once()
	_test_baocan_four_second_copy_respects_occupied_cell()
	if _failures == 0:
		print("BAOCAN_LIJING_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"BAOCAN_LIJING_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_vocabulary_and_declarations() -> void:
	_check(Catalog.ACTION_IF in Catalog.KNOWN_ACTIONS, "Conditional action is registered")
	_check(
		Catalog.CONDITION_SOURCE_OWNER_HAND_EMPTY in Catalog.KNOWN_ACTION_CONDITIONS,
		"Post-action empty-hand condition is registered"
	)
	_check(
		Catalog.CARD_REF_ATTACKER_CARD in Catalog.KNOWN_CARD_REFERENCES,
		"Attacker-card reference is registered"
	)
	var conditional_fixture: Dictionary = Catalog.get_definition(&"TaiZuChangQuan")
	conditional_fixture["id"] = &"fixture"
	conditional_fixture["glyph"] = "条件"
	conditional_fixture["abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{
				"type": Catalog.ACTION_IF,
				"conditions": [{
					"type": Catalog.CONDITION_SOURCE_OWNER_HAND_EMPTY,
				}],
				"actions": [{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1}],
			}],
		}],
	}]
	var conditional_errors: Array[String] = Catalog.validate_definition(conditional_fixture)
	_check(
		conditional_errors.is_empty(),
		"A complete conditional action declaration validates: %s" % str(conditional_errors)
	)
	var unknown_condition_fixture: Dictionary = conditional_fixture.duplicate(true)
	var unknown_ability: Dictionary = (
		unknown_condition_fixture.get("abilities", []) as Array
	)[0]
	var unknown_trigger: Dictionary = (unknown_ability.get("triggers", []) as Array)[0]
	var unknown_action: Dictionary = (unknown_trigger.get("actions", []) as Array)[0]
	unknown_action["conditions"] = [{"type": &"unknown_action_condition"}]
	_check(
		not Catalog.validate_definition(unknown_condition_fixture).is_empty(),
		"Unknown conditional-action conditions are rejected"
	)
	var empty_nested_fixture: Dictionary = conditional_fixture.duplicate(true)
	var empty_ability: Dictionary = (empty_nested_fixture.get("abilities", []) as Array)[0]
	var empty_trigger: Dictionary = (empty_ability.get("triggers", []) as Array)[0]
	var empty_action: Dictionary = (empty_trigger.get("actions", []) as Array)[0]
	empty_action["actions"] = []
	_check(
		not Catalog.validate_definition(empty_nested_fixture).is_empty(),
		"Conditional actions reject an empty nested action list"
	)
	_check(Catalog.validate_catalog().is_empty(), "The complete catalog validates")
	var expected_counts: Dictionary = {
		&"BaoCanShouQue2": 2,
		&"BaoCanShouQue3": 3,
		&"BaoCanShouQue4": 3,
		&"LiJingRuLai3": 1,
		&"LiJingRuLai4": 2,
	}
	for card_id: StringName in expected_counts:
		var abilities: Array = Catalog.get_definition(card_id).get("abilities", [])
		_check(
			abilities.size() == int(expected_counts[card_id]),
			"%s declares each approved ability separately" % card_id
		)
	var bao_four: Array = Catalog.get_definition(&"BaoCanShouQue4").get("abilities", [])
	var li_four: Array = Catalog.get_definition(&"LiJingRuLai4").get("abilities", [])
	if bao_four.size() == 3:
		_check(not bool((bao_four[0] as Dictionary).get("retained_on_flip", false)), "BaoCan entry payment is not locked")
		_check(bool((bao_four[1] as Dictionary).get("retained_on_flip", false)), "BaoCan prevented-flip exile is locked")
		_check(bool((bao_four[2] as Dictionary).get("retained_on_flip", false)), "BaoCan attacked replacement is locked")
		_check(Catalog.ACTION_IF in _action_types(bao_four[2] as Dictionary), "BaoCan tier four gates both copies with one conditional action")
	if li_four.size() == 2:
		_check(not bool((li_four[0] as Dictionary).get("retained_on_flip", false)), "LiJing payment is not locked")
		_check(bool((li_four[1] as Dictionary).get("retained_on_flip", false)), "LiJing prevented-flip exile is locked")


func _test_single_discard_entry_buff() -> void:
	for card_id: StringName in [
		&"BaoCanShouQue2",
		&"BaoCanShouQue3",
		&"BaoCanShouQue4",
		&"LiJingRuLai3",
	]:
		var source_id := StringName("%s_entry" % card_id)
		var left_id := StringName("%s_left" % card_id)
		var right_id := StringName("%s_right" % card_id)
		var source: Dictionary = Catalog.create_instance(card_id, Rules.PLAYER_OWNER, source_id)
		var left: Dictionary = _plain(left_id, Rules.PLAYER_OWNER)
		var right: Dictionary = _plain(right_id, Rules.PLAYER_OWNER)
		source["hand_slot_index"] = 0
		left["hand_slot_index"] = 1
		right["hand_slot_index"] = 4
		var initial_powers: Array = source.get("powers", []).duplicate()
		var transition: Dictionary = Simulator.apply_action(
			State.new(
				Rules.empty_board(),
				[source, right, left],
				[_plain(&"entry_enemy_hand", Rules.OPPONENT_OWNER)],
				Rules.PLAYER_OWNER
			),
			Action.make_play(0, 4, source_id)
		)
		var next_state: State = transition.get("state") as State
		_check(
			_instance_at(next_state.discard_piles[Rules.PLAYER_OWNER] as Array, 0) == left_id
			and _hand_slot_of(next_state.get_hand(Rules.PLAYER_OWNER), right_id) == 3,
			"%s discards the physical leftmost card and shifts only its right side" % card_id
		)
		_check(
			_board_card(next_state, source_id).get("powers", []) == _add_to_powers(initial_powers, 2),
			"%s gains two on every side only after its discard" % card_id
		)
		_check(
			_events_follow(
				transition.get("events", []),
				[&"card_discarded", &"hand_cards_shifted", &"powers_changed"]
			),
			"%s presents discard, hand shift, then power gain" % card_id
		)


func _test_lijing_four_partial_payment() -> void:
	for remaining_count: int in range(4):
		var source_id := StringName("lijing_four_%d" % remaining_count)
		var source: Dictionary = Catalog.create_instance(
			&"LiJingRuLai4",
			Rules.PLAYER_OWNER,
			source_id
		)
		source["hand_slot_index"] = 0
		var player_hand: Array = [source]
		for index: int in range(remaining_count):
			var filler: Dictionary = _plain(
				StringName("lijing_filler_%d_%d" % [remaining_count, index]),
				Rules.PLAYER_OWNER
			)
			filler["hand_slot_index"] = index + 1
			player_hand.append(filler)
		var transition: Dictionary = Simulator.apply_action(
			State.new(
				Rules.empty_board(),
				player_hand,
				[_plain(&"lijing_enemy_hand", Rules.OPPONENT_OWNER)],
				Rules.PLAYER_OWNER
			),
			Action.make_play(0, 4, source_id)
		)
		var next_state: State = transition.get("state") as State
		var discarded_count: int = (next_state.discard_piles[Rules.PLAYER_OWNER] as Array).size()
		var expected_discards: int = mini(remaining_count, 2)
		var expected_powers: Array = [9, 9, 9, 9] if remaining_count >= 2 else [6, 6, 6, 6]
		_check(discarded_count == expected_discards, "LiJing4 discards up to two cards with %d available" % remaining_count)
		_check(_board_card(next_state, source_id).get("powers", []) == expected_powers, "LiJing4 gains three only after the second discard with %d available" % remaining_count)
		_check(_event_count(transition.get("events", []), &"card_discarded") == expected_discards, "LiJing4 emits one discard event per paid card with %d available" % remaining_count)


func _test_prevented_self_attack_exiles_target() -> void:
	var protected: Dictionary = _plain(&"bao_protected", Rules.OPPONENT_OWNER)
	protected["active_abilities"] = [Catalog.normalize_ability(Catalog.TEMPORARY_FLIP_PROTECTION)]
	var board: Array = Rules.empty_board()
	board[5] = _slot(protected, Rules.OPPONENT_OWNER)
	var source: Dictionary = Catalog.create_instance(&"BaoCanShouQue3", Rules.PLAYER_OWNER, &"bao_three_attacker")
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [source], [_plain(&"bao_enemy_hand", Rules.OPPONENT_OWNER)], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"bao_three_attacker")
	)
	var next_state: State = transition.get("state") as State
	_check(next_state.board[5] == null, "BaoCan3 exiles the exact target whose flip it failed to complete")
	_check(_instance_at(next_state.removed_cards[Rules.OPPONENT_OWNER] as Array, 0) == &"bao_protected", "Prevented target enters its original owner's removed zone")
	_check(_events_follow(transition.get("events", []), [&"card_flip_prevented", &"card_exiled"]), "Explicit prevention precedes BaoCan target exile")


func _test_other_attack_prevention_does_not_trigger() -> void:
	var protected: Dictionary = _plain(&"other_protected", Rules.OPPONENT_OWNER)
	protected["active_abilities"] = [Catalog.normalize_ability(Catalog.TEMPORARY_FLIP_PROTECTION)]
	var board: Array = Rules.empty_board()
	board[5] = _slot(protected, Rules.OPPONENT_OWNER)
	board[8] = _slot(
		Catalog.create_instance(&"BaoCanShouQue3", Rules.PLAYER_OWNER, &"bao_watcher"),
		Rules.PLAYER_OWNER
	)
	var attacker: Dictionary = _plain(&"other_attacker", Rules.PLAYER_OWNER, [1, 9, 1, 1])
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [attacker], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"other_attacker")
	)
	var next_state: State = transition.get("state") as State
	_check(next_state.board[5] != null, "BaoCan does not exile a target protected from another attacker's flip")
	_check(_event_count(transition.get("events", []), &"card_flip_prevented") == 1, "The unrelated attack is still explicitly prevented")


func _test_baocan_attack_gate_and_mutual_exile() -> void:
	var weak_result: Dictionary = _attack_baocan_two([1, 0, 1, 1], &"weak")
	var weak_state: State = weak_result.get("state") as State
	_check(_event_count(weak_result.get("events", []), &"attack_started") == 0, "Insufficient power never reaches BaoCan's attacked timing")
	_check(weak_state.board[4] != null and weak_state.board[5] != null, "Weak attack leaves both cards on board")

	var strong_result: Dictionary = _attack_baocan_two([1, 9, 1, 1], &"strong")
	var strong_state: State = strong_result.get("state") as State
	_check(_event_count(strong_result.get("events", []), &"attack_started") == 1, "Successful attack reaches BaoCan's attacked timing once")
	_check(strong_state.board[4] == null and strong_state.board[5] == null, "BaoCan removes itself and the exact attacker before flipping")
	_check(_instance_at(strong_state.removed_cards[Rules.OPPONENT_OWNER] as Array, 0) == &"strong_bao", "BaoCan enters its original owner's removed zone")
	_check(_instance_at(strong_state.removed_cards[Rules.PLAYER_OWNER] as Array, 0) == &"strong_attacker", "Attacker enters its original owner's removed zone")
	_check(_event_count(strong_result.get("events", []), &"card_flipped") == 0, "Mutual exile ends the pending attack without a flip")


func _test_baocan_four_resummons_two_fresh_copies() -> void:
	var transition: Dictionary = _attack_baocan_four(false)
	var next_state: State = transition.get("state") as State
	var first_copy: Dictionary = _card_at(next_state, 5)
	var second_copy: Dictionary = _card_at(next_state, 4)
	_check(StringName(first_copy.get("card_id", &"")) == &"BaoCanShouQue4", "First fresh copy fully enters BaoCan's former cell")
	_check(StringName(second_copy.get("card_id", &"")) == &"BaoCanShouQue4", "Second fresh copy fully enters the attacker's former cell")
	_check(StringName(first_copy.get("instance_id", &"")) not in [&"copy_bao", &"copy_attacker"], "First replacement has a fresh instance ID")
	_check(StringName(second_copy.get("instance_id", &"")) not in [&"copy_bao", &"copy_attacker", StringName(first_copy.get("instance_id", &""))], "Second replacement is a distinct fresh instance")
	_check(_owner_at(next_state, 5) == Rules.OPPONENT_OWNER and _owner_at(next_state, 4) == Rules.OPPONENT_OWNER, "Both copies belong to the removed BaoCan's current side")
	_check(_event_count(transition.get("events", []), &"card_summoned") == 2, "Both replacements use the complete summon path")


func _test_baocan_four_checks_hand_after_exile_chain() -> void:
	var transition: Dictionary = _attack_baocan_four(true)
	var next_state: State = transition.get("state") as State
	_check(next_state.board[4] == null and next_state.board[5] == null, "Exile-triggered draw suppresses both replacement summons")
	_check(next_state.get_hand(Rules.OPPONENT_OWNER).size() == 1, "BaoCan checks its owner's hand after the exile draw finishes")
	_check(_event_count(transition.get("events", []), &"card_summoned") == 0, "Failed empty-hand condition executes neither nested summon")


func _test_baocan_four_checks_empty_hand_once() -> void:
	var board: Array = Rules.empty_board()
	board[5] = _slot(
		Catalog.create_instance(
			&"BaoCanShouQue4",
			Rules.OPPONENT_OWNER,
			&"single_check_bao"
		),
		Rules.OPPONENT_OWNER
	)
	var watcher: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan",
		Rules.OPPONENT_OWNER,
		&"draw_watcher"
	)
	watcher["active_abilities"] = [Catalog.normalize_ability({
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_ALLY}],
			"actions": [
				{"type": Catalog.ACTION_REMOVE_THIS_ABILITY},
				{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1},
			],
		}],
	})]
	board[8] = _slot(watcher, Rules.OPPONENT_OWNER)
	var attacker: Dictionary = _plain(
		&"single_check_attacker",
		Rules.PLAYER_OWNER,
		[1, 9, 1, 1]
	)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[attacker],
			[],
			Rules.PLAYER_OWNER,
			0,
			[],
			[_plain(&"draw_between_copies", Rules.OPPONENT_OWNER)]
		),
		Action.make_play(0, 4, &"single_check_attacker")
	)
	var next_state: State = transition.get("state") as State
	_check(
		StringName(_card_at(next_state, 5).get("card_id", &"")) == &"BaoCanShouQue4"
		and StringName(_card_at(next_state, 4).get("card_id", &"")) == &"BaoCanShouQue4",
		"A draw during the first copy's complete summon does not recheck the accepted condition"
	)
	_check(
		_events_follow(
			transition.get("events", []),
			[&"card_summoned", &"card_drawn", &"card_summoned"]
		),
		"Both copy actions continue in order after the one-time empty-hand check"
	)


func _test_baocan_four_second_copy_respects_occupied_cell() -> void:
	var board: Array = Rules.empty_board()
	board[5] = _slot(
		Catalog.create_instance(
			&"BaoCanShouQue4",
			Rules.OPPONENT_OWNER,
			&"occupied_cell_bao"
		),
		Rules.OPPONENT_OWNER
	)
	var watcher: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan",
		Rules.OPPONENT_OWNER,
		&"summon_watcher"
	)
	watcher["active_abilities"] = [Catalog.normalize_ability({
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_ALLY}],
			"actions": [
				{"type": Catalog.ACTION_REMOVE_THIS_ABILITY},
				{
					"type": Catalog.ACTION_SUMMON_CARD,
					"card": {
						"type": Catalog.CARD_SPEC_FRESH_COPY,
						"of": Catalog.CARD_REF_ABILITY_SOURCE,
					},
					"cell": {
						"type": Catalog.CELL_REF_FIRST_ADJACENT_EMPTY,
						"card": Catalog.CARD_REF_ABILITY_SOURCE,
					},
				},
			],
		}],
	})]
	board[7] = _slot(watcher, Rules.OPPONENT_OWNER)
	var attacker: Dictionary = _plain(
		&"occupied_cell_attacker",
		Rules.PLAYER_OWNER,
		[1, 9, 1, 1]
	)
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [attacker], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"occupied_cell_attacker")
	)
	var next_state: State = transition.get("state") as State
	_check(
		StringName(_card_at(next_state, 5).get("card_id", &"")) == &"BaoCanShouQue4",
		"The first copy completes in BaoCan's former cell"
	)
	_check(
		StringName(_card_at(next_state, 4).get("card_id", &"")) == &"TaiZuChangQuan",
		"A complete first summon chain may occupy the attacker's former cell"
	)
	_check(
		_board_card_id_count(next_state, &"BaoCanShouQue4") == 1,
		"The second copy fails instead of replacing a card that occupied its destination"
	)


func _attack_baocan_two(attacker_powers: Array, prefix: StringName) -> Dictionary:
	var board: Array = Rules.empty_board()
	board[5] = _slot(
		Catalog.create_instance(
			&"BaoCanShouQue2",
			Rules.OPPONENT_OWNER,
			StringName("%s_bao" % prefix)
		),
		Rules.OPPONENT_OWNER
	)
	var attacker: Dictionary = _plain(
		StringName("%s_attacker" % prefix),
		Rules.PLAYER_OWNER,
		attacker_powers
	)
	return Simulator.apply_action(
		State.new(board, [attacker], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, StringName("%s_attacker" % prefix))
	)


func _attack_baocan_four(draw_during_exile: bool) -> Dictionary:
	var source: Dictionary = Catalog.create_instance(
		&"BaoCanShouQue4",
		Rules.OPPONENT_OWNER,
		&"draw_bao" if draw_during_exile else &"copy_bao"
	)
	if draw_during_exile:
		source["active_abilities"].append(Catalog.normalize_ability({
			"triggers": [{
				"event": Catalog.CARD_BEFORE_EXILED,
				"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
				"actions": [{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1}],
			}],
		}))
	var board: Array = Rules.empty_board()
	board[5] = _slot(source, Rules.OPPONENT_OWNER)
	var attacker_id: StringName = &"draw_attacker" if draw_during_exile else &"copy_attacker"
	var attacker: Dictionary = _plain(attacker_id, Rules.PLAYER_OWNER, [1, 9, 1, 1])
	var opponent_deck: Array = (
		[_plain(&"exile_drawn", Rules.OPPONENT_OWNER)]
		if draw_during_exile
		else []
	)
	return Simulator.apply_action(
		State.new(board, [attacker], [], Rules.PLAYER_OWNER, 0, [], opponent_deck),
		Action.make_play(0, 4, attacker_id)
	)


func _plain(
	instance_id: StringName,
	original_owner: int,
	powers: Array = [1, 1, 1, 1]
) -> Dictionary:
	var typed_powers: Array[int] = []
	for power: Variant in powers:
		typed_powers.append(int(power))
	var card: Dictionary = Rules.make_card("Fixture", "测", typed_powers, [], original_owner)
	card["instance_id"] = instance_id
	card["original_owner"] = original_owner
	return card


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _card_at(state: State, cell: int) -> Dictionary:
	if cell < 0 or cell >= state.board.size() or state.board[cell] == null:
		return {}
	return ((state.board[cell] as Dictionary).get("card", {}) as Dictionary)


func _owner_at(state: State, cell: int) -> int:
	if cell < 0 or cell >= state.board.size() or state.board[cell] == null:
		return 0
	return int((state.board[cell] as Dictionary).get("owner", 0))


func _board_card(state: State, instance_id: StringName) -> Dictionary:
	for slot_value: Variant in state.board:
		if slot_value is Dictionary:
			var card: Dictionary = (slot_value as Dictionary).get("card", {})
			if StringName(card.get("instance_id", &"")) == instance_id:
				return card
	return {}


func _board_card_id_count(state: State, card_id: StringName) -> int:
	var count: int = 0
	for slot_value: Variant in state.board:
		if not slot_value is Dictionary:
			continue
		var card: Dictionary = (slot_value as Dictionary).get("card", {})
		if StringName(card.get("card_id", &"")) == card_id:
			count += 1
	return count


func _instance_at(cards: Array, index: int) -> StringName:
	if index < 0 or index >= cards.size() or not cards[index] is Dictionary:
		return &""
	return StringName((cards[index] as Dictionary).get("instance_id", &""))


func _hand_slot_of(hand: Array, instance_id: StringName) -> int:
	for card_value: Variant in hand:
		if (
			card_value is Dictionary
			and StringName((card_value as Dictionary).get("instance_id", &"")) == instance_id
		):
			return int((card_value as Dictionary).get("hand_slot_index", -1))
	return -1


func _add_to_powers(powers: Array, amount: int) -> Array:
	var changed: Array = []
	for value: Variant in powers:
		changed.append(int(value) + amount)
	return changed


func _events_follow(events: Array, expected: Array[StringName]) -> bool:
	var next_expected: int = 0
	for event_value: Variant in events:
		if not event_value is Dictionary or next_expected >= expected.size():
			continue
		if StringName((event_value as Dictionary).get("type", &"")) == expected[next_expected]:
			next_expected += 1
	return next_expected == expected.size()


func _event_count(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for event_value: Variant in events:
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
		):
			count += 1
	return count


func _action_types(ability: Dictionary) -> Array[StringName]:
	var types: Array[StringName] = []
	for trigger_value: Variant in ability.get("triggers", []):
		if trigger_value is Dictionary:
			_collect_action_types((trigger_value as Dictionary).get("actions", []), types)
	return types


func _collect_action_types(actions: Array, types: Array[StringName]) -> void:
	for action_value: Variant in actions:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		types.append(StringName(action.get("type", &"")))
		_collect_action_types(action.get("actions", []) as Array, types)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
