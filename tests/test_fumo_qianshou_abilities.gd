extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Executor = preload("res://scripts/duel_ability_executor.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_vocabulary_and_declarations()
	_test_fumo_reduces_moving_allies_and_can_cancel_move()
	_test_fumo_ignores_numberless_moving_card()
	_test_fumo_grants_reaction_once_and_reacts_in_range()
	_test_fumo_four_attacks_across_enemy_only()
	_test_qianshou_copies_complete_runtime_state_after_board_exile()
	_test_qianshou_responds_to_zero_power_exile()
	_test_qianshou_skips_numberless_and_off_board_exiles()
	_test_qianshou_sources_compete_for_original_cell()
	_test_qianshou_does_not_copy_itself_after_its_own_exile()
	_test_qianshou_flip_protection_gains_perfect_copy()
	_test_qianshou_flip_protection_edge_cases()
	if _failures == 0:
		print("FUMO_QIANSHOU_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"FUMO_QIANSHOU_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_vocabulary_and_declarations() -> void:
	_check(Catalog.CARD_AFTER_EXILED in Catalog.KNOWN_TRIGGER_EVENTS, "After-exile event is registered")
	_check(
		Catalog.CONDITION_MOVING_CARD_IS_ALLY in Catalog.KNOWN_TRIGGER_CONDITIONS,
		"Moving-card ally condition is registered"
	)
	_check(
		Catalog.CONDITION_TRIGGER_CARD_WAS_ON_BOARD in Catalog.KNOWN_TRIGGER_CONDITIONS,
		"Trigger-card former-board condition is registered"
	)
	_check(
		Catalog.CONDITION_TRIGGER_CARD_POWERS_COULD_CHANGE in Catalog.KNOWN_TRIGGER_CONDITIONS,
		"Power-change snapshot condition is registered"
	)
	_check(Catalog.validate_catalog().is_empty(), "Complete catalog validates")
	for card_id: StringName in [&"FuMoQuan3", &"FuMoQuan4", &"QianShouRuLai5"]:
		_check(
			not (Catalog.get_definition(card_id).get("abilities", []) as Array).is_empty(),
			"%s declares complete abilities" % card_id
		)
	var fumo_four: Dictionary = Catalog.create_instance(
		&"FuMoQuan4", Rules.PLAYER_OWNER, &"fumo_four_declaration"
	)
	var modifier: Dictionary = _find_range_modifier(fumo_four.get("active_abilities", []))
	_check(
		not modifier.is_empty()
		and bool(modifier.get("allow_intervening_enemy", false))
		and not bool(modifier.get("allow_intervening_ally", false)),
		"Fumo four declares its locked enemy-intervening range"
	)


func _test_fumo_reduces_moving_allies_and_can_cancel_move() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(Catalog.create_instance(&"FuMoQuan3", Rules.PLAYER_OWNER, &"fumo_move"), Rules.PLAYER_OWNER)
	board[4] = _slot(_plain(&"moving_ally", Rules.PLAYER_OWNER, [2, 2, 2, 2]), Rules.PLAYER_OWNER)
	var state := State.new(board)
	var moved: Dictionary = _move_first_adjacent(state, 4, &"moving_ally")
	_check(_board_cell(state, &"moving_ally") == 1, "A surviving ally completes its move")
	_check(
		_board_card(state, &"moving_ally").get("powers", []) == [1, 1, 1, 1],
		"Fumo reduces an allied moving card before movement"
	)
	_check(_event_types_in_order(moved.get("events", []), [&"powers_changed", &"card_moved"]), "Power loss precedes movement presentation")

	var zero_board: Array = Rules.empty_board()
	zero_board[0] = _slot(Catalog.create_instance(&"FuMoQuan3", Rules.PLAYER_OWNER, &"fumo_zero"), Rules.PLAYER_OWNER)
	zero_board[2] = _slot(Catalog.create_instance(&"FuMoQuan3", Rules.PLAYER_OWNER, &"fumo_zero_second"), Rules.PLAYER_OWNER)
	zero_board[4] = _slot(_plain(&"zero_mover", Rules.PLAYER_OWNER, [2, 2, 2, 2]), Rules.PLAYER_OWNER)
	var zero_state := State.new(zero_board)
	var canceled: Dictionary = _move_first_adjacent(zero_state, 4, &"zero_mover")
	_check(_board_cell(zero_state, &"zero_mover") < 0, "A mover reduced to zero is removed")
	_check(_removed_has(zero_state, Rules.PLAYER_OWNER, &"zero_mover"), "Zero mover enters its original owner's removed zone")
	_check(_event_count(canceled.get("events", []), &"card_moved") == 0, "Removal cancels the pending move")
	_check(_event_count(canceled.get("events", []), &"powers_changed") == 2, "Multiple Fumo sources reduce a mover in row-major order")


func _test_fumo_ignores_numberless_moving_card() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(Catalog.create_instance(&"FuMoQuan3", Rules.PLAYER_OWNER, &"fumo_numberless"), Rules.PLAYER_OWNER)
	board[4] = _slot(_plain(&"numberless_mover", Rules.PLAYER_OWNER, [-1, -1, -1, -1]), Rules.PLAYER_OWNER)
	var state := State.new(board)
	var result: Dictionary = _move_first_adjacent(state, 4, &"numberless_mover")
	_check(_board_cell(state, &"numberless_mover") == 1, "Numberless ally still moves")
	_check(_board_card(state, &"numberless_mover").get("powers", []) == [-1, -1, -1, -1], "Numberless powers stay unchanged")
	_check(_event_count(result.get("events", []), &"powers_changed") == 0, "Ignored power loss emits no power event")
	var enemy_board: Array = Rules.empty_board()
	enemy_board[0] = _slot(Catalog.create_instance(&"FuMoQuan3", Rules.PLAYER_OWNER, &"fumo_enemy_move"), Rules.PLAYER_OWNER)
	enemy_board[4] = _slot(_plain(&"moving_enemy", Rules.OPPONENT_OWNER, [3, 3, 3, 3]), Rules.OPPONENT_OWNER)
	var enemy_state := State.new(enemy_board)
	_move_first_adjacent(enemy_state, 4, &"moving_enemy")
	_check(_board_card(enemy_state, &"moving_enemy").get("powers", []) == [3, 3, 3, 3], "Enemy movement does not trigger Fumo's allied reduction")


func _test_fumo_grants_reaction_once_and_reacts_in_range() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(Catalog.create_instance(&"FuMoQuan3", Rules.PLAYER_OWNER, &"fumo_grant"), Rules.PLAYER_OWNER)
	board[4] = _slot(_plain(&"fumo_friend", Rules.PLAYER_OWNER, [9, 9, 9, 9]), Rules.PLAYER_OWNER)
	var state := State.new(board, [_plain(&"fumo_nonempty", Rules.PLAYER_OWNER)], [], Rules.PLAYER_OWNER)
	Simulator._resolve_trigger_event(state, Catalog.TRIGGER_END_OWNER_TURN, {"turn_owner_id": Rules.PLAYER_OWNER})
	_check(_count_summon_reactions(_board_card(state, &"fumo_friend")) == 0, "A nonempty hand grants no reaction")
	state.get_hand(Rules.PLAYER_OWNER).clear()
	Simulator._resolve_trigger_event(state, Catalog.TRIGGER_END_OWNER_TURN, {"turn_owner_id": Rules.PLAYER_OWNER})
	Simulator._resolve_trigger_event(state, Catalog.TRIGGER_END_OWNER_TURN, {"turn_owner_id": Rules.PLAYER_OWNER})
	_check(_count_summon_reactions(_board_card(state, &"fumo_friend")) == 1, "Repeated empty-hand grants are idempotent")
	board = state.board
	board[5] = _slot(_plain(&"fumo_enemy", Rules.OPPONENT_OWNER, [1, 1, 1, 1]), Rules.OPPONENT_OWNER)
	var reaction: Dictionary = Simulator._resolve_trigger_event(
		state,
		Catalog.TRIGGER_CARD_AFTER_SUMMONED,
		{"trigger_cell": 5, "trigger_instance_id": &"fumo_enemy", "trigger_owner_id": Rules.OPPONENT_OWNER}
	)
	_check(int((state.board[5] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER, "Granted ability attacks an enemy summoned in range")
	_check(_event_count(reaction.get("events", []), &"attack_started") == 1, "Granted reaction starts one real attack")


func _test_fumo_four_attacks_across_enemy_only() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(Catalog.create_instance(&"FuMoQuan4", Rules.PLAYER_OWNER, &"fumo_range"), Rules.PLAYER_OWNER)
	board[1] = _slot(_plain(&"range_middle_enemy", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[2] = _slot(_plain(&"range_far_enemy", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var state := State.new(board)
	_check(Rules.is_target_in_attack_range(state.board, 0, 2, {"skip_power_comparison": true}), "Fumo four can attack across one enemy")
	(state.board[1] as Dictionary)["owner"] = Rules.PLAYER_OWNER
	_check(not Rules.is_target_in_attack_range(state.board, 0, 2, {"skip_power_comparison": true}), "Fumo four cannot attack across one ally")


func _test_qianshou_copies_complete_runtime_state_after_board_exile() -> void:
	var board: Array = Rules.empty_board()
	var qianshou: Dictionary = Catalog.create_instance(&"QianShouRuLai5", Rules.PLAYER_OWNER, &"qian_runtime")
	qianshou["powers"] = [9, 8, 7, 6]
	qianshou["ki"] = 3
	(qianshou["active_abilities"] as Array).append({
		"retained_on_flip": false,
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_GAIN_KI, "amount": 1}],
		}],
	})
	board[0] = _slot(qianshou, Rules.PLAYER_OWNER)
	board[4] = _slot(_plain(&"qian_exile_target", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[5] = _slot(_plain(&"qian_standard_target", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[8] = _slot(_plain(&"qian_exiler", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var state := State.new(board)
	var result: Dictionary = _exile_board_card(state, 8, &"qian_exiler", &"qian_exile_target")
	var copy: Dictionary = _card_at_cell(state, 4)
	_check(StringName(copy.get("card_id", &"")) == &"QianShouRuLai5", "Qianshou creates itself in the removed card's former cell")
	_check(StringName(copy.get("instance_id", &"")) != &"qian_runtime", "Perfect board copy gets a fresh instance ID")
	_check(copy.get("powers", []) == [9, 8, 7, 6] and int(copy.get("ki", -1)) == 4, "Perfect board copy retains powers and ki before resolving its own summon trigger")
	_check(copy.get("active_abilities", []) == qianshou.get("active_abilities", []), "Perfect board copy retains the complete active ability state")
	_check(_event_types_in_order(result.get("events", []), [&"card_exiled", &"card_summoned", &"ki_changed", &"attack_started"]), "Perfect copy resolves normal summon triggers and standard attack after exile")
	_check(int((state.board[5] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER, "Perfect board copy performs its normal standard attack")


func _test_qianshou_responds_to_zero_power_exile() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(Catalog.create_instance(&"QianShouRuLai5", Rules.PLAYER_OWNER, &"qian_zero_source"), Rules.PLAYER_OWNER)
	board[4] = _slot(_plain(&"qian_zero_target", Rules.OPPONENT_OWNER, [1, 1, 1, 1]), Rules.OPPONENT_OWNER)
	board[8] = _slot(_plain(&"qian_zero_changer", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var state := State.new(board)
	_change_trigger_powers(state, 8, &"qian_zero_changer", &"qian_zero_target", -1)
	_check(StringName(_card_at_cell(state, 4).get("card_id", &"")) == &"QianShouRuLai5", "Four-zero power exile triggers Qianshou")


func _test_qianshou_skips_numberless_and_off_board_exiles() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(Catalog.create_instance(&"QianShouRuLai5", Rules.PLAYER_OWNER, &"qian_skip_source"), Rules.PLAYER_OWNER)
	board[4] = _slot(_plain(&"qian_numberless", Rules.OPPONENT_OWNER, [-1, -1, -1, -1]), Rules.OPPONENT_OWNER)
	board[8] = _slot(_plain(&"qian_skip_exiler", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var state := State.new(board)
	_exile_board_card(state, 8, &"qian_skip_exiler", &"qian_numberless")
	_check(state.board[4] == null, "Numberless board exile does not trigger Qianshou")

	var hand_target: Dictionary = _plain(&"qian_hand_target", Rules.OPPONENT_OWNER)
	state.get_hand(Rules.OPPONENT_OWNER).append(hand_target)
	_exile_referenced(state, 8, &"qian_skip_exiler", &"qian_hand_target")
	_check(_count_card_id_on_board(state, &"QianShouRuLai5") == 1, "Hand exile does not trigger the board-only Qianshou rule")


func _test_qianshou_sources_compete_for_original_cell() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(Catalog.create_instance(&"QianShouRuLai5", Rules.PLAYER_OWNER, &"qian_first"), Rules.PLAYER_OWNER)
	board[2] = _slot(Catalog.create_instance(&"QianShouRuLai5", Rules.PLAYER_OWNER, &"qian_second"), Rules.PLAYER_OWNER)
	board[4] = _slot(_plain(&"qian_compete_target", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[8] = _slot(_plain(&"qian_compete_exiler", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var state := State.new(board)
	var result: Dictionary = _exile_board_card(state, 8, &"qian_compete_exiler", &"qian_compete_target")
	_check(_count_card_id_on_board(state, &"QianShouRuLai5") == 3, "Only one source wins the former cell")
	_check(_event_count(result.get("events", []), &"card_summoned") == 1, "Competing sources emit only one successful summon")


func _test_qianshou_does_not_copy_itself_after_its_own_exile() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(&"QianShouRuLai5", Rules.PLAYER_OWNER, &"qian_self_exiled"), Rules.PLAYER_OWNER)
	board[8] = _slot(_plain(&"qian_self_exiler", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var state := State.new(board)
	_exile_board_card(state, 8, &"qian_self_exiler", &"qian_self_exiled")
	_check(state.board[4] == null and _count_card_id_on_board(state, &"QianShouRuLai5") == 0, "An exiled Qianshou is no longer a reaction source")


func _test_qianshou_flip_protection_gains_perfect_copy() -> void:
	var board: Array = Rules.empty_board()
	var qianshou: Dictionary = Catalog.create_instance(&"QianShouRuLai5", Rules.PLAYER_OWNER, &"qian_protect")
	qianshou["ki"] = 1
	board[4] = _slot(qianshou, Rules.PLAYER_OWNER)
	var right_card: Dictionary = _plain(&"qian_right_hand", Rules.PLAYER_OWNER)
	right_card[State.HAND_SLOT_INDEX_KEY] = 3
	var left_card: Dictionary = Catalog.create_instance(&"TuNaShu1", Rules.PLAYER_OWNER, &"qian_left_hand")
	left_card["powers"] = [7, 6, 5, 4]
	left_card["ki"] = 2
	(left_card["active_abilities"] as Array).append({"retained_on_flip": false, "modifiers": [{"type": Catalog.MODIFIER_DEFENDING_POWER_OVERRIDE, "value": 1}]})
	left_card[State.HAND_SLOT_INDEX_KEY] = 0
	var state := State.new(board, [right_card, left_card], [], Rules.PLAYER_OWNER)
	var result: Dictionary = Simulator.resolve_non_attack_flip(state, &"qian_protect", Rules.OPPONENT_OWNER)
	_check(int((state.board[4] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER, "Discard successfully prevents Qianshou's flip")
	_check(_discard_has(state, Rules.PLAYER_OWNER, &"qian_left_hand"), "Physical-leftmost card is discarded")
	var copy: Dictionary = _first_hand_card_id_except(state, Rules.PLAYER_OWNER, &"TuNaShu1", &"qian_left_hand")
	_check(not copy.is_empty() and copy.get("powers", []) == [7, 6, 5, 4] and int(copy.get("ki", -1)) == 2, "Hand perfect copy retains runtime powers and ki")
	_check(copy.get("active_abilities", []) == left_card.get("active_abilities", []) and StringName(copy.get("instance_id", &"")) != &"qian_left_hand", "Hand perfect copy retains abilities with a fresh identity")
	_check(int(_board_card(state, &"qian_protect").get("ki", -1)) == 0, "Qianshou spends one ki after prevention")
	_check(_event_types_in_order(result.get("events", []), [&"card_discarded", &"card_added_to_hand", &"card_flip_prevented"]), "Discard and copy finish before prevented-flip event")


func _test_qianshou_flip_protection_edge_cases() -> void:
	var no_hand_board: Array = Rules.empty_board()
	no_hand_board[4] = _slot(Catalog.create_instance(&"QianShouRuLai5", Rules.PLAYER_OWNER, &"qian_no_hand"), Rules.PLAYER_OWNER)
	var no_hand_state := State.new(no_hand_board)
	Simulator.resolve_non_attack_flip(no_hand_state, &"qian_no_hand", Rules.OPPONENT_OWNER)
	_check(int((no_hand_state.board[4] as Dictionary).get("owner", 0)) == Rules.OPPONENT_OWNER, "No hand means Qianshou cannot prevent flipping")

	var no_ki_board: Array = Rules.empty_board()
	no_ki_board[4] = _slot(Catalog.create_instance(&"QianShouRuLai5", Rules.PLAYER_OWNER, &"qian_no_ki"), Rules.PLAYER_OWNER)
	var no_ki_card: Dictionary = Catalog.create_instance(&"TuNaShu1", Rules.PLAYER_OWNER, &"qian_no_ki_discard")
	var no_ki_state := State.new(no_ki_board, [no_ki_card], [], Rules.PLAYER_OWNER)
	Simulator.resolve_non_attack_flip(no_ki_state, &"qian_no_ki", Rules.OPPONENT_OWNER)
	_check(int((no_ki_state.board[4] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER, "Successful discard prevents flip even without ki")
	_check(_discard_has(no_ki_state, Rules.PLAYER_OWNER, &"qian_no_ki_discard") and no_ki_state.get_hand(Rules.PLAYER_OWNER).is_empty(), "No-ki protection discards but gains no copy")


func _move_first_adjacent(state: State, source_cell: int, instance_id: StringName) -> Dictionary:
	var owner_id: int = int((state.board[source_cell] as Dictionary).get("owner", 0))
	return Executor.execute_actions(
		state, source_cell, instance_id, owner_id,
		[{"type": Catalog.ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY}],
		{"ability_source_instance_id": instance_id, "ability_source_owner_id": owner_id},
		Callable(), Callable(), Callable(),
		func(request: Dictionary) -> Dictionary: return Simulator._resolve_before_move_request(state, request),
		func(event_id: StringName, event_context: Dictionary) -> Dictionary: return Simulator._resolve_trigger_event(state, event_id, event_context)
	)


func _exile_board_card(state: State, source_cell: int, source_id: StringName, target_id: StringName) -> Dictionary:
	return _exile_referenced(state, source_cell, source_id, target_id)


func _exile_referenced(state: State, source_cell: int, source_id: StringName, target_id: StringName) -> Dictionary:
	return Executor.execute_actions(
		state, source_cell, source_id, int((state.board[source_cell] as Dictionary).get("owner", 0)),
		[{"type": Catalog.ACTION_EXILE_CARD, "card": Catalog.CARD_REF_TRIGGER_CARD}],
		{"ability_source_instance_id": source_id, "ability_source_owner_id": int((state.board[source_cell] as Dictionary).get("owner", 0)), "trigger_instance_id": target_id},
		Callable(), Callable(), Callable(), Callable(),
		func(event_id: StringName, event_context: Dictionary) -> Dictionary: return Simulator._resolve_trigger_event(state, event_id, event_context)
	)


func _change_trigger_powers(state: State, source_cell: int, source_id: StringName, target_id: StringName, amount: int) -> Dictionary:
	return Executor.execute_actions(
		state, source_cell, source_id, int((state.board[source_cell] as Dictionary).get("owner", 0)),
		[{"type": Catalog.ACTION_CHANGE_POWERS, "amount": amount, "card": Catalog.CARD_REF_TRIGGER_CARD}],
		{"ability_source_instance_id": source_id, "ability_source_owner_id": int((state.board[source_cell] as Dictionary).get("owner", 0)), "trigger_instance_id": target_id},
		Callable(), Callable(), Callable(), Callable(),
		func(event_id: StringName, event_context: Dictionary) -> Dictionary: return Simulator._resolve_trigger_event(state, event_id, event_context)
	)


func _plain(
	instance_id: StringName,
	owner_id: int,
	powers: Array[int] = [1, 1, 1, 1]
) -> Dictionary:
	var card: Dictionary = Rules.make_card(String(instance_id), "测", powers, [], owner_id)
	card["instance_id"] = instance_id
	return card


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _board_cell(state: State, instance_id: StringName) -> int:
	for cell: int in range(state.board.size()):
		if state.board[cell] is Dictionary and StringName((((state.board[cell] as Dictionary).get("card", {})) as Dictionary).get("instance_id", &"")) == instance_id:
			return cell
	return -1


func _board_card(state: State, instance_id: StringName) -> Dictionary:
	var cell: int = _board_cell(state, instance_id)
	return (state.board[cell] as Dictionary).get("card", {}) as Dictionary if cell >= 0 else {}


func _card_at_cell(state: State, cell: int) -> Dictionary:
	return (state.board[cell] as Dictionary).get("card", {}) as Dictionary if state.board[cell] is Dictionary else {}


func _removed_has(state: State, owner_id: int, instance_id: StringName) -> bool:
	return _zone_has(state.removed_cards.get(owner_id, []) as Array, instance_id)


func _discard_has(state: State, owner_id: int, instance_id: StringName) -> bool:
	return _zone_has(state.discard_piles.get(owner_id, []) as Array, instance_id)


func _zone_has(cards: Array, instance_id: StringName) -> bool:
	for value: Variant in cards:
		if value is Dictionary and StringName((value as Dictionary).get("instance_id", &"")) == instance_id:
			return true
	return false


func _count_card_id_on_board(state: State, card_id: StringName) -> int:
	var count: int = 0
	for value: Variant in state.board:
		if value is Dictionary and StringName((((value as Dictionary).get("card", {})) as Dictionary).get("card_id", &"")) == card_id:
			count += 1
	return count


func _first_hand_card_id_except(state: State, owner_id: int, card_id: StringName, excluded_id: StringName) -> Dictionary:
	for value: Variant in state.get_hand(owner_id):
		if value is Dictionary and StringName((value as Dictionary).get("card_id", &"")) == card_id and StringName((value as Dictionary).get("instance_id", &"")) != excluded_id:
			return value as Dictionary
	return {}


func _find_range_modifier(abilities: Array) -> Dictionary:
	for ability_value: Variant in abilities:
		if not ability_value is Dictionary:
			continue
		for modifier_value: Variant in (ability_value as Dictionary).get("modifiers", []):
			if modifier_value is Dictionary and StringName((modifier_value as Dictionary).get("type", &"")) == Catalog.MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO:
				return modifier_value as Dictionary
	return {}


func _count_summon_reactions(card: Dictionary) -> int:
	var count: int = 0
	for ability_value: Variant in card.get("active_abilities", []):
		if not ability_value is Dictionary:
			continue
		for trigger_value: Variant in (ability_value as Dictionary).get("triggers", []):
			if trigger_value is Dictionary and StringName((trigger_value as Dictionary).get("event", &"")) == Catalog.TRIGGER_CARD_AFTER_SUMMONED:
				count += 1
	return count


func _event_count(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for value: Variant in events:
		if value is Dictionary and StringName((value as Dictionary).get("type", &"")) == event_type:
			count += 1
	return count


func _event_types_in_order(events: Array, expected: Array[StringName]) -> bool:
	var expected_index: int = 0
	for value: Variant in events:
		if value is Dictionary and expected_index < expected.size() and StringName((value as Dictionary).get("type", &"")) == expected[expected_index]:
			expected_index += 1
	return expected_index == expected.size()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
