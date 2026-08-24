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
	_test_declarations()
	_test_empty_hand_does_not_prevent_flip()
	_test_tier_one_discards_leftmost_and_never_recalls()
	_test_discard_shifts_only_cards_to_its_right()
	_test_tier_two_without_ki_leaves_discarded_card()
	_test_tier_three_spends_ki_and_gains_fresh_copy()
	_test_full_hand_after_discard_trigger_still_spends_ki()
	_test_normal_play_preserves_remaining_physical_slots()
	_test_attack_flip_uses_the_same_discard_prevention()
	_test_tier_four_reacts_to_its_own_prevention()
	_test_tier_four_reacts_to_other_friendly_prevention()
	_test_multiple_tier_four_sources_all_react()
	_test_removal_does_not_emit_flip_prevented_trigger()
	if _failures == 0:
		print("JINGANG_BUHUAI_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"JINGANG_BUHUAI_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_declarations() -> void:
	for card_id: StringName in [
		&"JinGangBuHuai1",
		&"JinGangBuHuai2",
		&"JinGangBuHuai3",
		&"JinGangBuHuai4",
	]:
		var abilities: Array = Catalog.get_definition(card_id).get("abilities", [])
		_check(not abilities.is_empty(), "%s declares its complete abilities" % card_id)
	var tier_one: Array = Catalog.get_definition(&"JinGangBuHuai1").get("abilities", [])
	var tier_two: Array = Catalog.get_definition(&"JinGangBuHuai2").get("abilities", [])
	var tier_four: Array = Catalog.get_definition(&"JinGangBuHuai4").get("abilities", [])
	if not tier_one.is_empty():
		_check(
			_contains_all(_action_types(tier_one[0] as Dictionary), [
				&"discard_card", Catalog.ACTION_PREVENT_TRIGGER_FLIP,
			]),
			"Tier one declares discard followed by flip prevention"
		)
	if not tier_two.is_empty():
		_check(
			_contains_all(_action_types(tier_two[0] as Dictionary), [
				&"discard_card",
				Catalog.ACTION_PREVENT_TRIGGER_FLIP,
				Catalog.ACTION_SPEND_KI,
				Catalog.ACTION_ADD_CARD_TO_HAND,
			]),
			"Tier two through four declare discard, prevention, ki spend, and a fresh copy"
		)
		var copy_action: Dictionary = _first_action_of_type(
			tier_two[0] as Dictionary,
			Catalog.ACTION_ADD_CARD_TO_HAND
		)
		_check(
			copy_action.get("card", {}) == {
				"type": Catalog.CARD_SPEC_FRESH_COPY,
				"of": Catalog.CARD_REF_SELECTED_CARD,
			}
			and StringName(copy_action.get("recipient", &"")) == Catalog.RECIPIENT_SELF,
			"Jingang's generic add-to-hand action copies the discarded selection"
		)
	_check(tier_four.size() == 2, "Tier four keeps protection and rally as separate abilities")
	if tier_four.size() == 2:
		var rally_trigger: Dictionary = ((tier_four[1] as Dictionary).get("triggers", []) as Array)[0]
		_check(
			StringName(rally_trigger.get("event", &"")) == &"card_flip_prevented"
			and rally_trigger.get("conditions", [])
			== [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_ALLY}]
			and _contains_all(_action_types(tier_four[1] as Dictionary), [
				Catalog.ACTION_CHANGE_POWERS,
				Catalog.ACTION_STANDARD_ATTACK_WITH_CARD,
			]),
			"Tier four rallies every friendly card whose flip was prevented"
		)


func _test_empty_hand_does_not_prevent_flip() -> void:
	var state: State = _state_with_source(&"JinGangBuHuai1", &"empty_guard", [], 4)
	var result: Dictionary = Simulator.resolve_non_attack_flip(
		state, &"empty_guard", Rules.OPPONENT_OWNER
	)
	_check(
		_board_owner(state, &"empty_guard") == Rules.OPPONENT_OWNER,
		"Jingang flips normally when its current owner has no hand card to discard"
	)
	_check(
		_event_count(result.get("events", []), &"card_flip_prevented") == 0,
		"A failed discard emits no flip-prevented event"
	)


func _test_tier_one_discards_leftmost_and_never_recalls() -> void:
	var left: Dictionary = _plain(&"tier_one_left", Rules.PLAYER_OWNER)
	var right: Dictionary = _plain(&"tier_one_right", Rules.PLAYER_OWNER)
	var state: State = _state_with_source(
		&"JinGangBuHuai1", &"tier_one_guard", [left, right], 4
	)
	var source: Dictionary = _board_card(state, &"tier_one_guard")
	source["ki"] = 2
	var result: Dictionary = Simulator.resolve_non_attack_flip(
		state, &"tier_one_guard", Rules.OPPONENT_OWNER
	)
	_check(
		_board_owner(state, &"tier_one_guard") == Rules.PLAYER_OWNER,
		"Tier one prevents its flip after discarding"
	)
	_check(
		state.get_hand(Rules.PLAYER_OWNER).size() == 1
		and _instance_at(state.get_hand(Rules.PLAYER_OWNER), 0) == &"tier_one_right"
		and _instance_at(state.discard_piles[Rules.PLAYER_OWNER] as Array, 0)
		== &"tier_one_left",
		"Tier one discards the exact leftmost hand instance"
	)
	_check(
		int(_board_card(state, &"tier_one_guard").get("ki", 0)) == 2,
		"Tier one never spends ki or recalls its discard"
	)
	_check(
		_event_count(result.get("events", []), &"card_discarded") == 1
		and _event_count(result.get("events", []), &"card_returned_to_hand") == 0,
		"Tier one emits discard without a return event"
	)


func _test_discard_shifts_only_cards_to_its_right() -> void:
	var discarded: Dictionary = _plain(&"shift_discarded", Rules.PLAYER_OWNER)
	var right_near: Dictionary = _plain(&"shift_right_near", Rules.PLAYER_OWNER)
	var right_far: Dictionary = _plain(&"shift_right_far", Rules.PLAYER_OWNER)
	discarded["hand_slot_index"] = 2
	right_near["hand_slot_index"] = 3
	right_far["hand_slot_index"] = 4
	var state: State = _state_with_source(
		&"JinGangBuHuai1",
		&"shift_guard",
		[discarded, right_near, right_far],
		4
	)
	var result: Dictionary = Simulator.resolve_non_attack_flip(
		state, &"shift_guard", Rules.OPPONENT_OWNER
	)
	var hand: Array = state.get_hand(Rules.PLAYER_OWNER)
	_check(
		_hand_slot_of(hand, &"shift_right_near") == 2
		and _hand_slot_of(hand, &"shift_right_far") == 3,
		"Discard shifts every card to its right left by exactly one slot"
	)
	var shift_event: Dictionary = _first_event(result.get("events", []), &"hand_cards_shifted")
	_check(
		shift_event.get("moves", []) == [
			{"instance_id": &"shift_right_near", "from_slot": 3, "to_slot": 2},
			{"instance_id": &"shift_right_far", "from_slot": 4, "to_slot": 3},
		],
		"Discard emits one ordered pure-data batch for simultaneous presentation"
	)


func _test_tier_two_without_ki_leaves_discarded_card() -> void:
	var discarded: Dictionary = _plain(&"tier_two_discard", Rules.PLAYER_OWNER)
	var state: State = _state_with_source(
		&"JinGangBuHuai2", &"tier_two_guard", [discarded], 4
	)
	Simulator.resolve_non_attack_flip(state, &"tier_two_guard", Rules.OPPONENT_OWNER)
	_check(
		_board_owner(state, &"tier_two_guard") == Rules.PLAYER_OWNER
		and state.get_hand(Rules.PLAYER_OWNER).is_empty()
		and _instance_at(state.discard_piles[Rules.PLAYER_OWNER] as Array, 0)
		== &"tier_two_discard",
		"Tier two prevents but leaves its discard when it has no ki"
	)


func _test_tier_three_spends_ki_and_gains_fresh_copy() -> void:
	var discarded: Dictionary = Catalog.create_instance(
		&"TuNaShu1",
		Rules.PLAYER_OWNER,
		&"tier_three_discard"
	)
	var retained_right: Dictionary = _plain(&"tier_three_right", Rules.PLAYER_OWNER)
	var retained_far: Dictionary = _plain(&"tier_three_far", Rules.PLAYER_OWNER)
	discarded["hand_slot_index"] = 0
	retained_right["hand_slot_index"] = 1
	retained_far["hand_slot_index"] = 2
	discarded["powers"] = [2, 3, 4, 5]
	discarded["ki"] = 3
	discarded["active_abilities"] = []
	var state: State = _state_with_source(
		&"JinGangBuHuai3",
		&"tier_three_guard",
		[retained_right, discarded, retained_far],
		4
	)
	var result: Dictionary = Simulator.resolve_non_attack_flip(
		state, &"tier_three_guard", Rules.OPPONENT_OWNER
	)
	var added_event: Dictionary = _first_event(result.get("events", []), &"card_added_to_hand")
	var copied_instance_id := StringName(added_event.get("instance_id", &""))
	var copied: Dictionary = _card_in_hand(
		state.get_hand(Rules.PLAYER_OWNER), copied_instance_id
	)
	var fresh_baseline: Dictionary = Catalog.create_instance(
		&"TuNaShu1",
		Rules.PLAYER_OWNER,
		&"fresh_baseline"
	)
	_check(
		_board_owner(state, &"tier_three_guard") == Rules.PLAYER_OWNER
		and int(_board_card(state, &"tier_three_guard").get("ki", -1)) == 0,
		"Tier three prevents its flip and spends exactly one ki"
	)
	_check(
		copied_instance_id != &""
		and copied_instance_id != &"tier_three_discard"
		and StringName(copied.get("card_id", &"")) == &"TuNaShu1"
		and copied.get("powers", []) == fresh_baseline.get("powers", [])
		and int(copied.get("ki", -1)) == int(fresh_baseline.get("ki", -2))
		and copied.get("active_abilities", []) == fresh_baseline.get("active_abilities", [])
		and int(copied.get("hand_slot_index", -1)) == 2
		and _hand_slot_of(state.get_hand(Rules.PLAYER_OWNER), &"tier_three_right") == 0
		and _hand_slot_of(state.get_hand(Rules.PLAYER_OWNER), &"tier_three_far") == 1
		and _instance_at(state.discard_piles[Rules.PLAYER_OWNER] as Array, 0)
		== &"tier_three_discard",
		"Tier three leaves the discarded instance behind and gains a catalog-fresh copy"
	)
	_check(
		_event_types_between(
			result.get("events", []),
			[&"card_discarded", &"hand_cards_shifted", &"card_added_to_hand"]
		),
		"Discard fade, batch shift, and copy addition remain explicitly ordered"
	)
	_check(
		_event_count(result.get("events", []), &"card_discarded") == 1
		and _event_count(result.get("events", []), &"card_added_to_hand") == 1
		and _event_count(result.get("events", []), &"card_returned_to_hand") == 0,
		"Successful copy emits discard then add without returning the original"
	)


func _test_full_hand_after_discard_trigger_still_spends_ki() -> void:
	var nianhua: Dictionary = Catalog.create_instance(
		&"NianhuaWeiXiao4",
		Rules.PLAYER_OWNER,
		&"full_hand_discard"
	)
	nianhua["hand_slot_index"] = 0
	var owner_hand: Array = [nianhua]
	for index: int in range(4):
		var filler: Dictionary = _plain(
			StringName("full_hand_filler_%d" % index),
			Rules.PLAYER_OWNER
		)
		filler["hand_slot_index"] = index + 1
		owner_hand.append(filler)
	var state: State = _state_with_source(
		&"JinGangBuHuai3",
		&"full_hand_guard",
		owner_hand,
		8
	)
	state.board[0] = _slot(
		_plain(&"full_hand_enemy", Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	state.board[2] = _slot(
		Catalog.create_instance(
			&"TaiZuChangQuan",
			Rules.PLAYER_OWNER,
			&"full_hand_returned"
		),
		Rules.PLAYER_OWNER
	)
	var result: Dictionary = Simulator.resolve_non_attack_flip(
		state,
		&"full_hand_guard",
		Rules.OPPONENT_OWNER
	)
	_check(
		int(_board_card(state, &"full_hand_guard").get("ki", -1)) == 0
		and state.get_hand(Rules.PLAYER_OWNER).size() == 5
		and _board_cell(state, &"full_hand_discard") == 1
		and _event_count(result.get("events", []), &"card_added_to_hand") == 0,
		"Jingang spends ki without refund when a discard trigger refills the hand first"
	)


func _test_normal_play_preserves_remaining_physical_slots() -> void:
	var played: Dictionary = _plain(&"normal_played", Rules.PLAYER_OWNER)
	var remaining: Dictionary = _plain(&"normal_remaining", Rules.PLAYER_OWNER)
	played["hand_slot_index"] = 1
	remaining["hand_slot_index"] = 4
	var transition: Dictionary = Simulator.apply_action(
		State.new(Rules.empty_board(), [played, remaining], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"normal_played")
	)
	var next_state: State = transition.get("state") as State
	_check(
		_hand_slot_of(next_state.get_hand(Rules.PLAYER_OWNER), &"normal_remaining") == 4
		and _event_count(transition.get("events", []), &"hand_cards_shifted") == 0,
		"Normal play leaves every other physical hand slot unchanged"
	)


func _test_attack_flip_uses_the_same_discard_prevention() -> void:
	var board: Array = Rules.empty_board()
	board[1] = _slot(
		Catalog.create_instance(&"JinGangBuHuai1", Rules.OPPONENT_OWNER, &"attack_guard"),
		Rules.OPPONENT_OWNER
	)
	var attacker: Dictionary = _plain(&"jingang_attacker", Rules.PLAYER_OWNER, [9, 9, 9, 9])
	var enemy_left: Dictionary = _plain(&"enemy_left", Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [attacker], [enemy_left], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"jingang_attacker")
	)
	var next_state: State = transition.get("state") as State
	_check(
		_board_owner(next_state, &"attack_guard") == Rules.OPPONENT_OWNER
		and _instance_at(next_state.discard_piles[Rules.OPPONENT_OWNER] as Array, 0)
		== &"enemy_left",
		"Attack flips use the same current-owner discard prevention"
	)


func _test_tier_four_reacts_to_its_own_prevention() -> void:
	var state: State = _state_with_source(
		&"JinGangBuHuai4",
		&"self_rally_guard",
		[_plain(&"self_rally_discard", Rules.PLAYER_OWNER)],
		4
	)
	state.board[1] = _slot(
		_plain(&"self_rally_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1]),
		Rules.OPPONENT_OWNER
	)
	var before_powers: Array = _board_card(state, &"self_rally_guard").get("powers", []).duplicate()
	var result: Dictionary = Simulator.resolve_non_attack_flip(
		state, &"self_rally_guard", Rules.OPPONENT_OWNER
	)
	_check(
		_board_card(state, &"self_rally_guard").get("powers", [])
		== _plus_one(before_powers),
		"Tier four treats its own prevented flip as a friendly rally"
	)
	_check(
		_event_count(result.get("events", []), &"attack_started") >= 1,
		"Tier four makes itself attack after its prevention"
	)


func _test_tier_four_reacts_to_other_friendly_prevention() -> void:
	var protected: Dictionary = _plain(&"other_protected", Rules.PLAYER_OWNER, [9, 9, 9, 9])
	protected["active_abilities"] = [Catalog.normalize_ability(Catalog.TEMPORARY_FLIP_PROTECTION)]
	var board: Array = Rules.empty_board()
	board[4] = _slot(protected, Rules.PLAYER_OWNER)
	board[8] = _slot(
		Catalog.create_instance(&"JinGangBuHuai4", Rules.PLAYER_OWNER, &"other_rally_source"),
		Rules.PLAYER_OWNER
	)
	board[1] = _slot(_plain(&"other_rally_enemy", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var state := State.new(board)
	var result: Dictionary = Simulator.resolve_non_attack_flip(
		state, &"other_protected", Rules.OPPONENT_OWNER
	)
	_check(
		_board_card(state, &"other_protected").get("powers", []) == [10, 10, 10, 10],
		"Tier four adds one to another friendly card whose flip was prevented"
	)
	_check(
		_event_count(result.get("events", []), &"attack_started") >= 1,
		"The other protected friendly card attacks"
	)


func _test_multiple_tier_four_sources_all_react() -> void:
	var protected: Dictionary = _plain(&"multi_protected", Rules.PLAYER_OWNER, [1, 1, 1, 1])
	protected["active_abilities"] = [Catalog.normalize_ability(Catalog.TEMPORARY_FLIP_PROTECTION)]
	var board: Array = Rules.empty_board()
	board[4] = _slot(protected, Rules.PLAYER_OWNER)
	board[6] = _slot(
		Catalog.create_instance(&"JinGangBuHuai4", Rules.PLAYER_OWNER, &"multi_source_one"),
		Rules.PLAYER_OWNER
	)
	board[8] = _slot(
		Catalog.create_instance(&"JinGangBuHuai4", Rules.PLAYER_OWNER, &"multi_source_two"),
		Rules.PLAYER_OWNER
	)
	var state := State.new(board)
	var result: Dictionary = Simulator.resolve_non_attack_flip(
		state, &"multi_protected", Rules.OPPONENT_OWNER
	)
	_check(
		_board_card(state, &"multi_protected").get("powers", []) == [3, 3, 3, 3],
		"Every tier-four source independently strengthens the protected friendly"
	)
	_check(
		_ability_sources(result.get("events", []), &"card_flip_prevented")
		== [&"multi_source_one", &"multi_source_two"],
		"Multiple tier-four rallies resolve in row-major source order"
	)


func _test_removal_does_not_emit_flip_prevented_trigger() -> void:
	var board: Array = Rules.empty_board()
	board[1] = _slot(
		Catalog.create_instance(&"BaGuaFangWei", Rules.OPPONENT_OWNER, &"removed_bagua"),
		Rules.OPPONENT_OWNER
	)
	board[8] = _slot(
		Catalog.create_instance(&"JinGangBuHuai4", Rules.OPPONENT_OWNER, &"removal_watcher"),
		Rules.OPPONENT_OWNER
	)
	var attacker: Dictionary = _plain(&"removal_attacker", Rules.PLAYER_OWNER, [9, 9, 9, 9])
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [attacker], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"removal_attacker")
	)
	var next_state: State = transition.get("state") as State
	_check(
		_event_count(transition.get("events", []), &"card_flip_prevented") == 0
		and _board_card(next_state, &"removal_watcher").get("powers", []) == [6, 3, 6, 3],
		"Removing a pending target is not a flip-prevented trigger"
	)


func _state_with_source(
	card_id: StringName,
	instance_id: StringName,
	owner_hand: Array,
	cell: int
) -> State:
	var board: Array = Rules.empty_board()
	board[cell] = _slot(
		Catalog.create_instance(card_id, Rules.PLAYER_OWNER, instance_id),
		Rules.PLAYER_OWNER
	)
	return State.new(board, owner_hand, [], Rules.PLAYER_OWNER)


func _plain(
	instance_id: StringName,
	owner_id: int,
	powers: Array = [1, 1, 1, 1]
) -> Dictionary:
	var typed_powers: Array[int] = []
	for power: Variant in powers:
		typed_powers.append(int(power))
	var card: Dictionary = Rules.make_card("Fixture", "测", typed_powers, [], owner_id)
	card["instance_id"] = instance_id
	return card


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _board_card(state: State, instance_id: StringName) -> Dictionary:
	for slot_value: Variant in state.board:
		if slot_value is Dictionary:
			var card: Dictionary = (slot_value as Dictionary).get("card", {})
			if StringName(card.get("instance_id", &"")) == instance_id:
				return card
	return {}


func _board_owner(state: State, instance_id: StringName) -> int:
	for slot_value: Variant in state.board:
		if slot_value is Dictionary:
			var slot: Dictionary = slot_value
			if StringName((slot.get("card", {}) as Dictionary).get("instance_id", &"")) == instance_id:
				return int(slot.get("owner", 0))
	return 0


func _board_cell(state: State, instance_id: StringName) -> int:
	for cell: int in range(state.board.size()):
		var slot_value: Variant = state.board[cell]
		if (
			slot_value is Dictionary
			and StringName(((slot_value as Dictionary).get("card", {}) as Dictionary).get(
				"instance_id", &""
			)) == instance_id
		):
			return cell
	return -1


func _instance_at(cards: Array, index: int) -> StringName:
	if index < 0 or index >= cards.size() or not cards[index] is Dictionary:
		return &""
	return StringName((cards[index] as Dictionary).get("instance_id", &""))


func _card_in_hand(hand: Array, instance_id: StringName) -> Dictionary:
	for card_value: Variant in hand:
		if (
			card_value is Dictionary
			and StringName((card_value as Dictionary).get("instance_id", &"")) == instance_id
		):
			return card_value as Dictionary
	return {}


func _hand_slot_of(hand: Array, instance_id: StringName) -> int:
	return int(_card_in_hand(hand, instance_id).get("hand_slot_index", -1))


func _first_event(events: Array, event_type: StringName) -> Dictionary:
	for event_value: Variant in events:
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
		):
			return event_value as Dictionary
	return {}


func _event_types_between(events: Array, expected: Array[StringName]) -> bool:
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


func _ability_sources(events: Array, after_event: StringName) -> Array[StringName]:
	var sources: Array[StringName] = []
	var after_seen: bool = false
	for event_value: Variant in events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		var event_type := StringName(event.get("type", &""))
		if event_type == after_event:
			after_seen = true
		elif after_seen and event_type == &"ability_triggered":
			sources.append(StringName(event.get("source_instance_id", &"")))
	return sources


func _action_types(ability: Dictionary) -> Array[StringName]:
	var types: Array[StringName] = []
	for trigger_value: Variant in ability.get("triggers", []):
		if trigger_value is Dictionary:
			_collect_action_types((trigger_value as Dictionary).get("actions", []), types)
	return types


func _first_action_of_type(ability: Dictionary, expected_type: StringName) -> Dictionary:
	for trigger_value: Variant in ability.get("triggers", []):
		if not trigger_value is Dictionary:
			continue
		var found: Dictionary = _find_action_of_type(
			(trigger_value as Dictionary).get("actions", []),
			expected_type
		)
		if not found.is_empty():
			return found
	return {}


func _find_action_of_type(actions: Array, expected_type: StringName) -> Dictionary:
	for action_value: Variant in actions:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		if StringName(action.get("type", &"")) == expected_type:
			return action
		var nested: Dictionary = _find_action_of_type(action.get("actions", []), expected_type)
		if not nested.is_empty():
			return nested
	return {}


func _collect_action_types(actions: Array, types: Array[StringName]) -> void:
	for action_value: Variant in actions:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		types.append(StringName(action.get("type", &"")))
		_collect_action_types(action.get("actions", []) as Array, types)


func _contains_all(actual: Array[StringName], required: Array) -> bool:
	for value: Variant in required:
		if StringName(value) not in actual:
			return false
	return true


func _plus_one(powers: Array) -> Array:
	var result: Array = []
	for value: Variant in powers:
		result.append(int(value) + 1)
	return result


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
