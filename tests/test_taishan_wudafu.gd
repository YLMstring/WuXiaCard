extends SceneTree

const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")
const Action = preload("res://scripts/duel_action.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Selector = preload("res://scripts/duel_card_selector.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_declarations_validate()
	_test_exactly_one_adjacent_enemy_selection()
	_test_taishan_swaps_in_every_direction()
	_test_taishan_swaps_then_attacks_from_its_new_cell()
	_test_taishan_does_not_swap_with_zero_or_two_adjacent_enemies()
	_test_taishan_three_temporary_protection()
	_test_wudafu_one_protects_itself()
	_test_wudafu_two_grants_only_allied_heavy_swords()
	_test_wudafu_three_draws_before_granting()
	_test_wudafu_three_hand_cap_does_not_stop_grants()
	_test_wudafu_three_empty_deck_does_not_stop_grants()

	if _failures == 0:
		print("TAISHAN_WUDAFU_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"TAISHAN_WUDAFU_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_catalog_declarations_validate() -> void:
	_check(
		Catalog.validate_catalog().is_empty(),
		"The complete card catalog passes validation"
	)
	var expected_ability_counts: Dictionary = {
		&"TaiShan18Pan2": 1,
		&"TaiShan18Pan3": 2,
		&"WuDaFuJian1": 1,
		&"WuDaFuJian2": 1,
		&"WuDaFuJian3": 1,
	}
	for card_id: StringName in expected_ability_counts:
		var abilities: Array = Catalog.get_definition(card_id).get("abilities", [])
		_check(
			abilities.size() == int(expected_ability_counts[card_id]),
			"%s declares its approved ability count" % card_id
		)
		for ability_value: Variant in abilities:
			_check(
				Catalog.validate_ability(ability_value as Dictionary, card_id).is_empty(),
				"%s ability declaration passes catalog validation" % card_id
			)


func _test_exactly_one_adjacent_enemy_selection() -> void:
	var board: Array = Rules.empty_board()
	var source: Dictionary = _make_card(
		&"selector_source",
		Rules.PLAYER_OWNER,
		"重剑"
	)
	var first_enemy: Dictionary = _make_card(
		&"selector_enemy_one",
		Rules.OPPONENT_OWNER,
		"重剑"
	)
	board[4] = {"card": source, "owner": Rules.PLAYER_OWNER}
	board[5] = {"card": first_enemy, "owner": Rules.OPPONENT_OWNER}
	var state := State.new(board)
	var selector: Dictionary = {
		"zones": [Catalog.CARD_ZONE_BOARD],
		"conditions": [
			{"type": Catalog.CONDITION_SELECTED_CARD_IS_ENEMY},
			{"type": Catalog.CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
		],
		"required_count": 1,
	}
	_check(
		Selector.snapshot(state, selector, &"selector_source") == [&"selector_enemy_one"],
		"Exact-count selector returns one orthogonally adjacent enemy"
	)
	state.board[3] = {
		"card": _make_card(
			&"selector_enemy_two",
			Rules.OPPONENT_OWNER,
			"重剑"
		),
		"owner": Rules.OPPONENT_OWNER,
	}
	_check(
		Selector.snapshot(state, selector, &"selector_source").is_empty(),
		"Exact-count selector returns no cards when two enemies match"
	)
	state.board[3] = null
	state.board[5] = null
	state.board[0] = {
		"card": _make_card(
			&"selector_diagonal_enemy",
			Rules.OPPONENT_OWNER,
			"重剑"
		),
		"owner": Rules.OPPONENT_OWNER,
	}
	_check(
		Selector.snapshot(state, selector, &"selector_source").is_empty(),
		"Diagonal enemies are not adjacent"
	)


func _test_taishan_swaps_in_every_direction() -> void:
	for target_cell: int in [1, 3, 5, 7]:
		var instance_suffix: String = str(target_cell)
		var taishan_instance := StringName("taishan_direction_%s" % instance_suffix)
		var enemy_instance := StringName("taishan_enemy_%s" % instance_suffix)
		var board: Array = Rules.empty_board()
		board[target_cell] = {
			"card": _make_card(enemy_instance, Rules.OPPONENT_OWNER, "重剑"),
			"owner": Rules.OPPONENT_OWNER,
		}
		var state := State.new(
			board,
			[Catalog.create_instance(
				&"TaiShan18Pan2",
				Rules.PLAYER_OWNER,
				taishan_instance
			)],
			[],
			Rules.PLAYER_OWNER
		)
		var transition: Dictionary = Simulator.apply_action(
			state,
			Action.make_play(0, 4)
		)
		var next_state: State = transition.get("state") as State
		_check(
			_instance_at(next_state, target_cell) == taishan_instance
			and _instance_at(next_state, 4) == enemy_instance,
			"TaiShan18Pan2 swaps through neighbor cell %d" % target_cell
		)


func _test_taishan_swaps_then_attacks_from_its_new_cell() -> void:
	var taishan: Dictionary = Catalog.create_instance(
		&"TaiShan18Pan2",
		Rules.PLAYER_OWNER,
		&"taishan_swap"
	)
	var enemy: Dictionary = _make_card(
		&"taishan_swap_enemy",
		Rules.OPPONENT_OWNER,
		"重剑",
		[1, 1, 1, 1]
	)
	var board: Array = Rules.empty_board()
	board[5] = {"card": enemy, "owner": Rules.OPPONENT_OWNER}
	var state := State.new(board, [taishan], [], Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4))
	var next_state: State = transition.get("state") as State
	_check(bool(transition.get("valid", false)), "TaiShan18Pan2 play is valid")
	_check(
		_instance_at(next_state, 5) == &"taishan_swap"
		and _instance_at(next_state, 4) == &"taishan_swap_enemy",
		"TaiShan18Pan2 moves first and the sole enemy reappears in its old cell"
	)
	var move_events: Array[Dictionary] = _events_of_type(
		transition.get("events", []),
		&"card_moved"
	)
	_check(
		move_events.size() == 2
		and StringName(move_events[0].get("instance_id", &"")) == &"taishan_swap"
		and StringName(move_events[1].get("instance_id", &"")) == &"taishan_swap_enemy",
		"Source-initiated swap emits source movement before selected-card movement"
	)
	var attack_events: Array[Dictionary] = _events_of_type(
		transition.get("events", []),
		&"attack_started"
	)
	_check(
		attack_events.size() == 1
		and int(attack_events[0].get("source_cell", -1)) == 5
		and int(attack_events[0].get("target_cell", -1)) == 4,
		"The summoned card performs its standard attack from its post-swap cell"
	)


func _test_taishan_does_not_swap_with_zero_or_two_adjacent_enemies() -> void:
	var no_enemy := State.new(
		Rules.empty_board(),
		[Catalog.create_instance(
			&"TaiShan18Pan2",
			Rules.PLAYER_OWNER,
			&"taishan_zero"
		)],
		[],
		Rules.PLAYER_OWNER
	)
	var zero_result: Dictionary = Simulator.apply_action(no_enemy, Action.make_play(0, 4))
	var zero_state: State = zero_result.get("state") as State
	_check(
		_instance_at(zero_state, 4) == &"taishan_zero"
		and _events_of_type(zero_result.get("events", []), &"card_moved").is_empty(),
		"TaiShan18Pan2 remains in place with no adjacent enemy"
	)

	var board: Array = Rules.empty_board()
	board[3] = {
		"card": _make_card(&"taishan_two_left", Rules.OPPONENT_OWNER, "重剑"),
		"owner": Rules.OPPONENT_OWNER,
	}
	board[5] = {
		"card": _make_card(&"taishan_two_right", Rules.OPPONENT_OWNER, "重剑"),
		"owner": Rules.OPPONENT_OWNER,
	}
	var two_enemy := State.new(
		board,
		[Catalog.create_instance(
			&"TaiShan18Pan2",
			Rules.PLAYER_OWNER,
			&"taishan_two"
		)],
		[],
		Rules.PLAYER_OWNER
	)
	var two_result: Dictionary = Simulator.apply_action(two_enemy, Action.make_play(0, 4))
	var two_state: State = two_result.get("state") as State
	_check(
		_instance_at(two_state, 4) == &"taishan_two"
		and _events_of_type(two_result.get("events", []), &"card_moved").is_empty(),
		"TaiShan18Pan2 remains in place when two adjacent enemies match"
	)


func _test_taishan_three_temporary_protection() -> void:
	var board: Array = Rules.empty_board()
	board[4] = {
		"card": Catalog.create_instance(
			&"TaiShan18Pan3",
			Rules.PLAYER_OWNER,
			&"taishan_guard"
		),
		"owner": Rules.PLAYER_OWNER,
	}
	board[0] = {
		"card": _make_card(&"guard_enemy", Rules.OPPONENT_OWNER, "重剑"),
		"owner": Rules.OPPONENT_OWNER,
	}
	var state := State.new(board)
	var prevented: Dictionary = Simulator.resolve_non_attack_flip(
		state,
		&"taishan_guard",
		Rules.OPPONENT_OWNER
	)
	_check(
		int((state.board[4] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER
		and _events_of_type(prevented.get("events", []), &"card_flip_prevented").size() == 1,
		"TaiShan18Pan3 prevents its first flip attempt"
	)
	Simulator.resolve_non_attack_flip(state, &"guard_enemy", Rules.PLAYER_OWNER)
	var guarded_card: Dictionary = (state.board[4] as Dictionary).get("card", {})
	_check(
		(guarded_card.get("active_abilities", []) as Array).size() == 1,
		"An enemy ownership flip removes only TaiShan18Pan3's temporary protection"
	)
	var successful: Dictionary = Simulator.resolve_non_attack_flip(
		state,
		&"taishan_guard",
		Rules.OPPONENT_OWNER
	)
	_check(
		int((state.board[4] as Dictionary).get("owner", 0)) == Rules.OPPONENT_OWNER
		and _events_of_type(successful.get("events", []), &"card_flipped").size() == 1,
		"TaiShan18Pan3 can flip after its protection expires"
	)


func _test_wudafu_one_protects_itself() -> void:
	var state := State.new(
		Rules.empty_board(),
		[Catalog.create_instance(
			&"WuDaFuJian1",
			Rules.PLAYER_OWNER,
			&"wudafu_one"
		)],
		[],
		Rules.PLAYER_OWNER
	)
	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4))
	var next_state: State = transition.get("state") as State
	var card: Dictionary = (next_state.board[4] as Dictionary).get("card", {})
	_check(
		(card.get("active_abilities", []) as Array).size() == 2,
		"WuDaFuJian1 grants temporary protection to itself after summon"
	)
	var flip_result: Dictionary = Simulator.resolve_non_attack_flip(
		next_state,
		&"wudafu_one",
		Rules.OPPONENT_OWNER
	)
	_check(
		int((next_state.board[4] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER
		and _events_of_type(flip_result.get("events", []), &"card_flip_prevented").size() == 1,
		"WuDaFuJian1's granted protection prevents a flip"
	)


func _test_wudafu_two_grants_only_allied_heavy_swords() -> void:
	var board: Array = Rules.empty_board()
	board[0] = {
		"card": _make_card(&"allied_heavy", Rules.PLAYER_OWNER, "重剑"),
		"owner": Rules.PLAYER_OWNER,
	}
	board[1] = {
		"card": _make_card(&"allied_sword", Rules.PLAYER_OWNER, "剑法"),
		"owner": Rules.PLAYER_OWNER,
	}
	board[2] = {
		"card": _make_card(&"enemy_heavy", Rules.OPPONENT_OWNER, "重剑"),
		"owner": Rules.OPPONENT_OWNER,
	}
	var state := State.new(
		board,
		[Catalog.create_instance(
			&"WuDaFuJian2",
			Rules.PLAYER_OWNER,
			&"wudafu_two"
		)],
		[],
		Rules.PLAYER_OWNER
	)
	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4))
	var next_state: State = transition.get("state") as State
	_check(
		_ability_count(next_state, 0) == 1
		and _ability_count(next_state, 4) == 2,
		"WuDaFuJian2 protects allied heavy swords and includes itself"
	)
	_check(
		_ability_count(next_state, 1) == 0
		and _ability_count(next_state, 2) == 0,
		"WuDaFuJian2 excludes non-heavy allies and enemy heavy swords"
	)


func _test_wudafu_three_draws_before_granting() -> void:
	var board: Array = Rules.empty_board()
	board[0] = {
		"card": _make_card(&"draw_heavy", Rules.PLAYER_OWNER, "重剑"),
		"owner": Rules.PLAYER_OWNER,
	}
	var state := State.new(
		board,
		[Catalog.create_instance(
			&"WuDaFuJian3",
			Rules.PLAYER_OWNER,
			&"wudafu_three"
		)],
		[_make_card(&"wudafu_reply", Rules.OPPONENT_OWNER, "剑法")],
		Rules.PLAYER_OWNER,
		0,
		[
			_make_card(&"wudafu_draw_one", Rules.PLAYER_OWNER, "剑法"),
			_make_card(&"wudafu_draw_two", Rules.PLAYER_OWNER, "剑法"),
			_make_card(&"wudafu_draw_three", Rules.PLAYER_OWNER, "剑法"),
		],
		[]
	)
	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4))
	var next_state: State = transition.get("state") as State
	var event_types: Array[StringName] = _event_types(transition.get("events", []))
	_check(
		next_state.get_hand(Rules.PLAYER_OWNER).size() == 2
		and (next_state.decks.get(Rules.PLAYER_OWNER, []) as Array).size() == 1,
		"WuDaFuJian3 draws once for itself and once for another allied heavy sword"
	)
	_check(
		_count_before(event_types, &"card_drawn", &"ability_gained") == 2
		and _events_of_type(transition.get("events", []), &"ability_gained").size() == 2,
		"WuDaFuJian3 completes both draws before granting both protections"
	)


func _test_wudafu_three_hand_cap_does_not_stop_grants() -> void:
	var board: Array = Rules.empty_board()
	board[0] = {
		"card": _make_card(&"cap_heavy", Rules.PLAYER_OWNER, "重剑"),
		"owner": Rules.PLAYER_OWNER,
	}
	var player_hand: Array = [
		Catalog.create_instance(
			&"WuDaFuJian3",
			Rules.PLAYER_OWNER,
			&"wudafu_cap"
		),
		_make_card(&"cap_hand_one", Rules.PLAYER_OWNER, "剑法"),
		_make_card(&"cap_hand_two", Rules.PLAYER_OWNER, "剑法"),
		_make_card(&"cap_hand_three", Rules.PLAYER_OWNER, "剑法"),
		_make_card(&"cap_hand_four", Rules.PLAYER_OWNER, "剑法"),
	]
	var state := State.new(
		board,
		player_hand,
		[_make_card(&"cap_reply", Rules.OPPONENT_OWNER, "剑法")],
		Rules.PLAYER_OWNER,
		0,
		[
			_make_card(&"cap_draw_one", Rules.PLAYER_OWNER, "剑法"),
			_make_card(&"cap_draw_two", Rules.PLAYER_OWNER, "剑法"),
		],
		[]
	)
	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4))
	var next_state: State = transition.get("state") as State
	_check(
		next_state.get_hand(Rules.PLAYER_OWNER).size() == 5
		and _events_of_type(transition.get("events", []), &"card_drawn").size() == 1,
		"WuDaFuJian3 obeys the five-card hand cap"
	)
	_check(
		_ability_count(next_state, 0) == 1
		and _ability_count(next_state, 4) == 2,
		"A capped draw does not stop WuDaFuJian3 from granting protections"
	)


func _test_wudafu_three_empty_deck_does_not_stop_grants() -> void:
	var board: Array = Rules.empty_board()
	board[0] = {
		"card": _make_card(&"empty_heavy", Rules.PLAYER_OWNER, "重剑"),
		"owner": Rules.PLAYER_OWNER,
	}
	var state := State.new(
		board,
		[Catalog.create_instance(
			&"WuDaFuJian3",
			Rules.PLAYER_OWNER,
			&"wudafu_empty"
		)],
		[_make_card(&"empty_reply", Rules.OPPONENT_OWNER, "剑法")],
		Rules.PLAYER_OWNER,
		0,
		[],
		[]
	)
	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4))
	var next_state: State = transition.get("state") as State
	_check(
		_events_of_type(transition.get("events", []), &"card_drawn").is_empty(),
		"WuDaFuJian3 draws nothing from an empty side deck"
	)
	_check(
		_ability_count(next_state, 0) == 1
		and _ability_count(next_state, 4) == 2,
		"An empty side deck does not stop WuDaFuJian3 from granting protections"
	)


func _make_card(
	instance_id: StringName,
	owner_id: int,
	weapon: String,
	powers: Array = [1, 1, 1, 1]
) -> Dictionary:
	return {
		"card_id": instance_id,
		"instance_id": instance_id,
		"glyph": String(instance_id),
		"sect": "测试",
		"tier": 1,
		"weapon": weapon,
		"powers": powers.duplicate(),
		"ki": 0,
		"active_abilities": [],
		"owner": owner_id,
	}


func _instance_at(state: State, cell: int) -> StringName:
	if state == null or cell < 0 or cell >= state.board.size() or state.board[cell] == null:
		return &""
	return StringName(
		((state.board[cell] as Dictionary).get("card", {}) as Dictionary).get(
			"instance_id",
			&""
		)
	)


func _ability_count(state: State, cell: int) -> int:
	if state == null or cell < 0 or cell >= state.board.size() or state.board[cell] == null:
		return -1
	var card: Dictionary = (state.board[cell] as Dictionary).get("card", {})
	return (card.get("active_abilities", []) as Array).size()


func _events_of_type(events_value: Variant, event_type: StringName) -> Array[Dictionary]:
	var matching: Array[Dictionary] = []
	if not events_value is Array:
		return matching
	for event_value: Variant in events_value as Array:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		if StringName(event.get("type", &"")) == event_type:
			matching.append(event)
	return matching


func _event_types(events_value: Variant) -> Array[StringName]:
	var types: Array[StringName] = []
	if not events_value is Array:
		return types
	for event_value: Variant in events_value as Array:
		if event_value is Dictionary:
			types.append(StringName((event_value as Dictionary).get("type", &"")))
	return types


func _count_before(
	event_types: Array[StringName],
	counted_type: StringName,
	stop_type: StringName
) -> int:
	var count: int = 0
	for event_type: StringName in event_types:
		if event_type == stop_type:
			break
		if event_type == counted_type:
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
