extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Executor = preload("res://scripts/duel_ability_executor.gd")
const Revelation = preload("res://scripts/duel_revelation.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_vocabulary_and_declarations()
	_test_nianhua_four_discard_summons_same_instance()
	_test_nianhua_four_without_legal_cell_stays_discarded()
	_test_nianhua_returns_snapshot_to_original_owners()
	_test_sanru_discard_transforms_and_returns_same_instance()
	_test_transform_full_hand_exiles_same_instance()
	_test_sanru_two_reloads_current_discard_top_after_first_chain()
	_test_sanru_three_uses_adjacent_then_row_major_fallback()
	_test_sanru_end_turn_exile_is_not_retained()
	_test_all_range_modifiers_are_retained()
	if _failures == 0:
		print("NIANHUA_SANRU_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"NIANHUA_SANRU_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_vocabulary_and_declarations() -> void:
	_check(
		Catalog.CARD_AFTER_DISCARDED in Catalog.KNOWN_TRIGGER_EVENTS,
		"After-discard event is registered"
	)
	_check(
		Catalog.ACTION_TRANSFORM_CARD in Catalog.KNOWN_ACTIONS,
		"Transform action is registered"
	)
	_check(
		Catalog.OWNER_CARD_ORIGINAL in Catalog.KNOWN_OWNER_REFERENCES,
		"Original-owner reference is registered"
	)
	_check(Catalog.validate_catalog().is_empty(), "Complete catalog validates")
	for card_id: StringName in [
		&"NianhuaWeiXiao3",
		&"NianhuaWeiXiao4",
		&"SanRuDiYu1",
		&"SanRuDiYu2",
		&"SanRuDiYu3",
	]:
		var abilities: Array = Catalog.get_definition(card_id).get("abilities", [])
		_check(not abilities.is_empty(), "%s declares its complete abilities" % card_id)


func _test_nianhua_four_discard_summons_same_instance() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(
		Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"nian_enemy"),
		Rules.OPPONENT_OWNER
	)
	board[8] = _slot(_plain(&"nian_discard_source", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var nianhua: Dictionary = Catalog.create_instance(
		&"NianhuaWeiXiao4", Rules.PLAYER_OWNER, &"nian_discarded"
	)
	nianhua["powers"] = [8, 7, 6, 5]
	var state := State.new(board, [nianhua], [], Rules.PLAYER_OWNER)
	var result: Dictionary = _discard_selected_hand_card(
		state, 8, &"nian_discard_source", &"nian_discarded"
	)
	var summoned: Dictionary = _board_card(state, &"nian_discarded")
	_check(
		not summoned.is_empty()
		and _board_cell(state, &"nian_discarded") == 1
		and summoned.get("powers", []) == [8, 7, 6, 5],
		"Nianhua four reuses the exact discard instance in the first enemy-adjacent empty cell"
	)
	_check(
		(state.discard_piles[Rules.PLAYER_OWNER] as Array).is_empty(),
		"Successful discard summon removes Nianhua from the discard pile"
	)
	_check(
		_event_types_in_order(
			result.get("events", []),
			[&"card_discarded", &"card_summoned", &"card_returned_to_hand"]
		),
		"Discard fade precedes summon and Nianhua's adjacent return"
	)


func _test_nianhua_four_without_legal_cell_stays_discarded() -> void:
	var board: Array = Rules.empty_board()
	board[8] = _slot(_plain(&"nian_no_cell_source", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var nianhua: Dictionary = Catalog.create_instance(
		&"NianhuaWeiXiao4", Rules.PLAYER_OWNER, &"nian_no_cell"
	)
	var state := State.new(board, [nianhua], [], Rules.PLAYER_OWNER)
	var result: Dictionary = _discard_selected_hand_card(
		state, 8, &"nian_no_cell_source", &"nian_no_cell"
	)
	_check(
		_board_cell(state, &"nian_no_cell") < 0
		and _instance_at(state.discard_piles[Rules.PLAYER_OWNER] as Array, 0)
		== &"nian_no_cell",
		"Nianhua remains discarded when no empty cell is adjacent to an enemy"
	)
	_check(
		_event_count(result.get("events", []), &"card_summoned") == 0,
		"Failed discard summon emits no summon event"
	)


func _test_nianhua_returns_snapshot_to_original_owners() -> void:
	var board: Array = Rules.empty_board()
	var first: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"nian_return_first"
	)
	var second: Dictionary = Catalog.create_instance(
		&"TuNaShu1", Rules.PLAYER_OWNER, &"nian_return_second"
	)
	board[1] = _slot(first, Rules.PLAYER_OWNER)
	board[3] = _slot(second, Rules.OPPONENT_OWNER)
	var source: Dictionary = Catalog.create_instance(
		&"NianhuaWeiXiao3", Rules.PLAYER_OWNER, &"nian_return_source"
	)
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [source], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"nian_return_source")
	)
	var next_state: State = transition.get("state") as State
	_check(
		next_state.board[1] == null and next_state.board[3] == null,
		"Nianhua removes every adjacent target selected at trigger start"
	)
	_check(
		_hand_has_card_id(next_state, Rules.OPPONENT_OWNER, &"TaiZuChangQuan")
		and _hand_has_card_id(next_state, Rules.PLAYER_OWNER, &"TuNaShu1"),
		"Each adjacent card returns to its original owner rather than its current owner"
	)
	var return_cells: Array[int] = []
	for event_value: Variant in transition.get("events", []):
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &""))
			== &"card_returned_to_hand"
		):
			return_cells.append(int((event_value as Dictionary).get("target_cell", -1)))
	_check(return_cells == [1, 3], "Nianhua returns its target snapshot in row-major order")


func _test_sanru_discard_transforms_and_returns_same_instance() -> void:
	var board: Array = Rules.empty_board()
	board[8] = _slot(_plain(&"san_transform_source", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var sanru: Dictionary = Catalog.create_instance(
		&"SanRuDiYu1", Rules.PLAYER_OWNER, &"san_transform"
	)
	sanru["powers"] = [9, 9, 9, 9]
	sanru["ki"] = 7
	(sanru["active_abilities"] as Array).append({"modifiers": []})
	var state := State.new(board, [sanru], [], Rules.PLAYER_OWNER)
	var result: Dictionary = _discard_selected_hand_card(
		state, 8, &"san_transform_source", &"san_transform"
	)
	var transformed: Dictionary = _card_in_hand(state, Rules.PLAYER_OWNER, &"san_transform")
	var definition: Dictionary = Catalog.get_definition(&"SanRuDiYu2")
	_check(
		StringName(transformed.get("card_id", &"")) == &"SanRuDiYu2"
		and transformed.get("powers", []) == definition.get("powers", [])
		and int(transformed.get("ki", -1)) == int(definition.get("starting_ki", 0))
		and not (transformed.get("active_abilities", []) as Array).is_empty(),
		"Discard transformation completely replaces runtime card data with tier two"
	)
	_check(
		int(transformed.get("original_owner", 0)) == Rules.PLAYER_OWNER,
		"Transformation preserves original owner and exact instance identity"
	)
	_check(
		Revelation.is_revealed_to(transformed, Rules.OPPONENT_OWNER),
		"The same instance returned from discard becomes permanently visible to the opponent"
	)
	_check(
		_event_types_in_order(
			result.get("events", []),
			[&"card_discarded", &"card_transformed", &"card_returned_to_hand", &"card_revealed"]
		),
		"Discard, transform, exact-instance return, and public reveal emit ordered pure-data events"
	)
	var second_result: Dictionary = _discard_selected_hand_card(
		state, 8, &"san_transform_source", &"san_transform"
	)
	_check(
		StringName(_card_in_hand(state, Rules.PLAYER_OWNER, &"san_transform").get("card_id", &""))
		== &"SanRuDiYu3"
		and _event_count(second_result.get("events", []), &"card_revealed") == 0,
		"Returning an already-public exact instance does not emit a duplicate reveal"
	)


func _test_transform_full_hand_exiles_same_instance() -> void:
	var board: Array = Rules.empty_board()
	board[8] = _slot(_plain(&"san_full_source", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var full_hand: Array = []
	for index: int in range(5):
		full_hand.append(_plain(StringName("san_full_hand_%d" % index), Rules.PLAYER_OWNER))
	var state := State.new(board, full_hand, [], Rules.PLAYER_OWNER)
	state.discard_piles[Rules.PLAYER_OWNER] = [Catalog.create_instance(
		&"SanRuDiYu1", Rules.PLAYER_OWNER, &"san_full_transform"
	)]
	var result: Dictionary = Executor.execute_actions(
		state,
		8,
		&"san_full_transform",
		Rules.PLAYER_OWNER,
		[
			{
				"type": Catalog.ACTION_TRANSFORM_CARD,
				"card": Catalog.CARD_REF_TRIGGER_CARD,
				"card_id": &"SanRuDiYu2",
			},
			{
				"type": Catalog.ACTION_RETURN_CARD_TO_HAND,
				"card": Catalog.CARD_REF_TRIGGER_CARD,
				"recipient": Catalog.OWNER_CARD_CURRENT,
				"preserve_instance": true,
			},
		],
		{
			"ability_source_instance_id": &"san_full_transform",
			"ability_source_owner_id": Rules.PLAYER_OWNER,
			"trigger_instance_id": &"san_full_transform",
			"trigger_owner_id": Rules.PLAYER_OWNER,
			"trigger_zone": Catalog.CARD_ZONE_DISCARD,
		},
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		func(event_id: StringName, event_context: Dictionary) -> Dictionary:
			return Simulator._resolve_trigger_event(state, event_id, event_context)
	)
	_check(
		(state.discard_piles[Rules.PLAYER_OWNER] as Array).is_empty()
		and _instance_at(state.removed_cards[Rules.PLAYER_OWNER] as Array, 0)
		== &"san_full_transform",
		"A transformed exact instance is exiled when its destination hand is full"
	)
	_check(
		StringName(((state.removed_cards[Rules.PLAYER_OWNER] as Array)[0] as Dictionary).get("card_id", &""))
		== &"SanRuDiYu2"
		and _event_count(result.get("events", []), &"card_exiled") == 1,
		"Full-hand fallback removes the transformed tier and emits exile presentation"
	)


func _test_sanru_two_reloads_current_discard_top_after_first_chain() -> void:
	var sanru: Dictionary = Catalog.create_instance(
		&"SanRuDiYu2", Rules.PLAYER_OWNER, &"san_dynamic_source"
	)
	var newly_discarded: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"san_dynamic_new_top"
	)
	newly_discarded["powers"] = [8, 7, 6, 5]
	var state := State.new(
		Rules.empty_board(),
		[sanru, newly_discarded],
		[_plain(&"san_dynamic_reply", Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER
	)
	state.discard_piles[Rules.PLAYER_OWNER] = [
		Catalog.create_instance(&"TuNaShu1", Rules.PLAYER_OWNER, &"san_dynamic_bottom"),
		Catalog.create_instance(&"BaoCanShouQue2", Rules.PLAYER_OWNER, &"san_dynamic_first"),
	]
	var transition: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, 4, &"san_dynamic_source")
	)
	var next_state: State = transition.get("state") as State
	_check(
		_board_cell(next_state, &"san_dynamic_first") == 1
		and _board_cell(next_state, &"san_dynamic_new_top") == 3,
		"Sanru two fully resolves the first summon before selecting its second discard top"
	)
	_check(
		_instance_at(next_state.discard_piles[Rules.PLAYER_OWNER] as Array, 0)
		== &"san_dynamic_bottom"
		and (next_state.discard_piles[Rules.PLAYER_OWNER] as Array).size() == 1,
		"The old lower discard remains when a newly discarded card becomes the next top"
	)
	var resummoned: Dictionary = _board_card(next_state, &"san_dynamic_new_top")
	_check(
		int((_board_slot(next_state, &"san_dynamic_new_top")).get("owner", 0))
		== Rules.PLAYER_OWNER
		and int(resummoned.get("original_owner", 0)) == Rules.OPPONENT_OWNER
		and resummoned.get("powers", []) == [8, 7, 6, 5],
		"Discard summon preserves the instance state and original owner but uses Sanru's owner"
	)


func _test_sanru_three_uses_adjacent_then_row_major_fallback() -> void:
	var board: Array = Rules.empty_board()
	for cell: int in [1, 3, 5, 7]:
		board[cell] = _slot(
			_plain(StringName("san_block_%d" % cell), Rules.PLAYER_OWNER),
			Rules.PLAYER_OWNER
		)
	var sanru: Dictionary = Catalog.create_instance(
		&"SanRuDiYu3", Rules.PLAYER_OWNER, &"san_fallback_source"
	)
	var state := State.new(
		board,
		[sanru],
		[_plain(&"san_fallback_reply", Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER
	)
	state.discard_piles[Rules.PLAYER_OWNER] = [
		Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"san_fallback_third"),
		Catalog.create_instance(&"TuNaShu1", Rules.PLAYER_OWNER, &"san_fallback_second"),
		Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"san_fallback_first"),
	]
	var transition: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, 4, &"san_fallback_source")
	)
	var next_state: State = transition.get("state") as State
	_check(
		_board_cell(next_state, &"san_fallback_first") == 0
		and _board_cell(next_state, &"san_fallback_second") == 2
		and _board_cell(next_state, &"san_fallback_third") == 6,
		"Sanru three falls back to current nonadjacent empty cells in row-major order"
	)


func _test_sanru_end_turn_exile_is_not_retained() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(
		Catalog.create_instance(&"SanRuDiYu3", Rules.PLAYER_OWNER, &"san_end_normal"),
		Rules.PLAYER_OWNER
	)
	var state := State.new(board)
	Simulator._resolve_trigger_event(
		state,
		Catalog.TRIGGER_END_OWNER_TURN,
		{"turn_owner_id": Rules.PLAYER_OWNER}
	)
	_check(
		_board_cell(state, &"san_end_normal") < 0
		and _instance_at(state.removed_cards[Rules.PLAYER_OWNER] as Array, 0)
		== &"san_end_normal",
		"Unflipped Sanru exiles itself at its current owner's turn end"
	)

	var flipped_board: Array = Rules.empty_board()
	flipped_board[4] = _slot(
		Catalog.create_instance(&"SanRuDiYu3", Rules.PLAYER_OWNER, &"san_end_flipped"),
		Rules.PLAYER_OWNER
	)
	var flipped_state := State.new(flipped_board)
	Executor.resolve_normal_flip(
		flipped_state,
		-1,
		&"",
		4,
		&"san_end_flipped",
		Rules.OPPONENT_OWNER
	)
	Simulator._resolve_trigger_event(
		flipped_state,
		Catalog.TRIGGER_END_OWNER_TURN,
		{"turn_owner_id": Rules.OPPONENT_OWNER}
	)
	_check(
		_board_cell(flipped_state, &"san_end_flipped") == 4,
		"Flipped Sanru loses its non-retained end-turn exile"
	)


func _test_all_range_modifiers_are_retained() -> void:
	var expectations: Dictionary = {
		&"NianhuaWeiXiao3": false,
		&"NianhuaWeiXiao4": true,
		&"SanRuDiYu1": false,
		&"SanRuDiYu2": true,
		&"SanRuDiYu3": true,
	}
	for card_id: StringName in expectations:
		var instance_id := StringName("range_%s" % card_id)
		var board: Array = Rules.empty_board()
		board[4] = _slot(
			Catalog.create_instance(card_id, Rules.PLAYER_OWNER, instance_id),
			Rules.PLAYER_OWNER
		)
		var state := State.new(board)
		Executor.resolve_normal_flip(
			state, -1, &"", 4, instance_id, Rules.OPPONENT_OWNER
		)
		var active: Array = _board_card(state, instance_id).get("active_abilities", [])
		var range_modifier: Dictionary = _find_range_modifier(active)
		_check(
			not range_modifier.is_empty()
			and bool(range_modifier.get("allow_intervening_ally", false))
			== bool(expectations[card_id]),
			"%s retains its approved locked range after flipping" % card_id
		)


func _discard_selected_hand_card(
	state: State,
	source_cell: int,
	source_instance_id: StringName,
	target_instance_id: StringName
) -> Dictionary:
	return Executor.execute_actions(
		state,
		source_cell,
		source_instance_id,
		Rules.PLAYER_OWNER,
		[{
			"type": Catalog.ACTION_DISCARD_CARD,
			"card": Catalog.CARD_REF_SELECTED_CARD,
		}],
		{
			"ability_source_instance_id": source_instance_id,
			"ability_source_owner_id": Rules.PLAYER_OWNER,
			"selected_card_instance_id": target_instance_id,
			"selected_card_conditions": [],
		},
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		func(event_id: StringName, event_context: Dictionary) -> Dictionary:
			return Simulator._resolve_trigger_event(state, event_id, event_context)
	)


func _plain(instance_id: StringName, owner_id: int) -> Dictionary:
	var card: Dictionary = Rules.make_card(
		String(instance_id), "测", [1, 1, 1, 1], [], owner_id
	)
	card["instance_id"] = instance_id
	return card


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _board_cell(state: State, instance_id: StringName) -> int:
	for cell: int in range(state.board.size()):
		var slot_value: Variant = state.board[cell]
		if (
			slot_value is Dictionary
			and StringName(((slot_value as Dictionary).get("card", {}) as Dictionary).get("instance_id", &""))
			== instance_id
		):
			return cell
	return -1


func _board_slot(state: State, instance_id: StringName) -> Dictionary:
	var cell: int = _board_cell(state, instance_id)
	return state.board[cell] as Dictionary if cell >= 0 else {}


func _board_card(state: State, instance_id: StringName) -> Dictionary:
	return _board_slot(state, instance_id).get("card", {}) as Dictionary


func _card_in_hand(state: State, owner_id: int, instance_id: StringName) -> Dictionary:
	for value: Variant in state.get_hand(owner_id):
		if (
			value is Dictionary
			and StringName((value as Dictionary).get("instance_id", &"")) == instance_id
		):
			return value as Dictionary
	return {}


func _hand_has_card_id(state: State, owner_id: int, card_id: StringName) -> bool:
	for value: Variant in state.get_hand(owner_id):
		if value is Dictionary and StringName((value as Dictionary).get("card_id", &"")) == card_id:
			return true
	return false


func _instance_at(cards: Array, index: int) -> StringName:
	if index < 0 or index >= cards.size() or not cards[index] is Dictionary:
		return &""
	return StringName((cards[index] as Dictionary).get("instance_id", &""))


func _find_range_modifier(abilities: Array) -> Dictionary:
	for ability_value: Variant in abilities:
		if not ability_value is Dictionary:
			continue
		for modifier_value: Variant in (ability_value as Dictionary).get("modifiers", []):
			if (
				modifier_value is Dictionary
				and StringName((modifier_value as Dictionary).get("type", &""))
				== Catalog.MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO
			):
				return modifier_value as Dictionary
	return {}


func _event_count(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for value: Variant in events:
		if value is Dictionary and StringName((value as Dictionary).get("type", &"")) == event_type:
			count += 1
	return count


func _event_types_in_order(events: Array, expected: Array[StringName]) -> bool:
	var expected_index: int = 0
	for value: Variant in events:
		if not value is Dictionary or expected_index >= expected.size():
			continue
		if StringName((value as Dictionary).get("type", &"")) == expected[expected_index]:
			expected_index += 1
	return expected_index == expected.size()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
