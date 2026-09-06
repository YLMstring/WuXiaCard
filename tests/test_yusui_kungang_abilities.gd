extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_vocabulary_and_declarations()
	_test_entry_swaps_only_with_exactly_one_adjacent_enemy()
	_test_locked_decay_runs_only_at_current_owners_turn_boundaries_after_flip()
	_test_tier_four_exile_flips_every_adjacent_card()
	_test_tier_three_reenters_as_enemy_bagua_with_same_instance()
	_test_captured_tier_three_uses_pre_exile_owner_for_enemy_relation()
	_test_summon_owner_does_not_change_exact_card_source_owner()
	if _failures == 0:
		print("YUSUI_KUNGANG_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"YUSUI_KUNGANG_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_vocabulary_and_declarations() -> void:
	_check(
		Catalog.OWNER_OPPONENT_OF_CARD_CURRENT in Catalog.KNOWN_OWNER_REFERENCES,
		"Opposite-current-card owner reference is registered"
	)
	_check(Catalog.validate_catalog().is_empty(), "Complete catalog validates")
	for card_id: StringName in [&"YuSuiKunGang3", &"YuSuiKunGang4"]:
		var abilities: Array = Catalog.get_definition(card_id).get("abilities", [])
		_check(abilities.size() == 3, "%s declares entry, decay, and exile abilities" % card_id)
		if abilities.size() != 3:
			continue
		_check(
			not bool((abilities[0] as Dictionary).get("retained_on_flip", false)),
			"%s entry swap is not locked" % card_id
		)
		_check(
			bool((abilities[1] as Dictionary).get("retained_on_flip", false)),
			"%s turn-boundary decay is locked" % card_id
		)
		_check(
			bool((abilities[2] as Dictionary).get("retained_on_flip", false)),
			"%s exile reaction is locked" % card_id
		)


func _test_entry_swaps_only_with_exactly_one_adjacent_enemy() -> void:
	var single_board: Array = Rules.empty_board()
	single_board[1] = _slot(_plain(&"single_enemy", Rules.OPPONENT_OWNER, [9, 9, 9, 9]), Rules.OPPONENT_OWNER)
	single_board[3] = _slot(_plain(&"single_ally", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var single_card: Dictionary = Catalog.create_instance(
		&"YuSuiKunGang3", Rules.PLAYER_OWNER, &"single_yusui"
	)
	var single_result: Dictionary = Simulator.apply_action(
		State.new(single_board, [single_card], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"single_yusui")
	)
	var single_state: State = single_result.get("state") as State
	_check(_instance_at(single_state, 1) == &"single_yusui", "One adjacent enemy receives YuSui's old cell")
	_check(_instance_at(single_state, 4) == &"single_enemy", "YuSui swaps the sole adjacent enemy into its entry cell")
	_check(_event_count(single_result.get("events", []), &"card_moved") == 2, "Exactly one adjacent enemy emits both swap legs")

	var double_board: Array = Rules.empty_board()
	double_board[1] = _slot(_plain(&"double_enemy_a", Rules.OPPONENT_OWNER, [9, 9, 9, 9]), Rules.OPPONENT_OWNER)
	double_board[3] = _slot(_plain(&"double_enemy_b", Rules.OPPONENT_OWNER, [9, 9, 9, 9]), Rules.OPPONENT_OWNER)
	var double_card: Dictionary = Catalog.create_instance(
		&"YuSuiKunGang4", Rules.PLAYER_OWNER, &"double_yusui"
	)
	var double_result: Dictionary = Simulator.apply_action(
		State.new(double_board, [double_card], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"double_yusui")
	)
	var double_state: State = double_result.get("state") as State
	_check(_instance_at(double_state, 4) == &"double_yusui", "Two adjacent enemies prevent the entry swap")
	_check(_event_count(double_result.get("events", []), &"card_moved") == 0, "Invalid enemy count emits no swap")


func _test_locked_decay_runs_only_at_current_owners_turn_boundaries_after_flip() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(
		Catalog.create_instance(&"YuSuiKunGang4", Rules.PLAYER_OWNER, &"decay_yusui"),
		Rules.PLAYER_OWNER
	)
	var state := State.new(board)
	Simulator._resolve_trigger_event(
		state,
		Catalog.TRIGGER_START_OWNER_TURN,
		{"turn_owner_id": Rules.OPPONENT_OWNER}
	)
	_check(
		_board_card(state, &"decay_yusui").get("powers", []) == [3, 5, 5, 3],
		"Opponent turn start does not reduce player-owned YuSui"
	)
	Simulator._resolve_trigger_event(
		state,
		Catalog.TRIGGER_START_OWNER_TURN,
		{"turn_owner_id": Rules.PLAYER_OWNER}
	)
	_check(
		_board_card(state, &"decay_yusui").get("powers", []) == [2, 4, 4, 2],
		"Player turn start reduces player-owned YuSui once"
	)
	Simulator.resolve_non_attack_flip(state, &"decay_yusui", Rules.OPPONENT_OWNER)
	var flipped: Dictionary = _board_card(state, &"decay_yusui")
	_check((flipped.get("active_abilities", []) as Array).size() == 2, "Flip removes entry swap but retains both locked abilities")
	Simulator._resolve_trigger_event(
		state,
		Catalog.TRIGGER_END_OWNER_TURN,
		{"turn_owner_id": Rules.PLAYER_OWNER}
	)
	_check(
		_board_card(state, &"decay_yusui").get("powers", []) == [2, 4, 4, 2],
		"Player turn end does not reduce opponent-owned YuSui"
	)
	Simulator._resolve_trigger_event(
		state,
		Catalog.TRIGGER_END_OWNER_TURN,
		{"turn_owner_id": Rules.OPPONENT_OWNER}
	)
	_check(
		_board_card(state, &"decay_yusui").get("powers", []) == [1, 3, 3, 1],
		"Opponent turn end reduces opponent-owned YuSui once"
	)


func _test_tier_four_exile_flips_every_adjacent_card() -> void:
	var board: Array = Rules.empty_board()
	var yusui: Dictionary = Catalog.create_instance(
		&"YuSuiKunGang4", Rules.PLAYER_OWNER, &"exile_yusui_four"
	)
	yusui["powers"] = [1, 1, 1, 1]
	board[4] = _slot(yusui, Rules.PLAYER_OWNER)
	board[1] = _slot(_plain(&"north_enemy", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[3] = _slot(_plain(&"west_ally", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[5] = _slot(_plain(&"east_enemy", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[7] = _slot(_plain(&"south_ally", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[0] = _slot(_plain(&"corner_enemy", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var state := State.new(board)
	var result: Dictionary = Simulator._resolve_trigger_event(
		state,
		Catalog.TRIGGER_START_OWNER_TURN,
		{"turn_owner_id": Rules.PLAYER_OWNER}
	)
	_check(state.board[4] == null, "Tier four remains removed after reaching zero")
	_check(_removed_has(state, Rules.PLAYER_OWNER, &"exile_yusui_four"), "Tier four enters its original owner's removed zone")
	_check(_owner_at(state, 1) == Rules.PLAYER_OWNER, "North enemy flips")
	_check(_owner_at(state, 3) == Rules.OPPONENT_OWNER, "West ally flips")
	_check(_owner_at(state, 5) == Rules.PLAYER_OWNER, "East enemy flips")
	_check(_owner_at(state, 7) == Rules.OPPONENT_OWNER, "South ally flips")
	_check(_owner_at(state, 0) == Rules.OPPONENT_OWNER, "Nonadjacent card does not flip")
	_check(
		_event_types_in_order(result.get("events", []), [&"powers_changed", &"card_flipped", &"card_exiled"]),
		"Adjacent flips finish before YuSui enters the removed zone"
	)
	_check(_event_count(result.get("events", []), &"card_flipped") == 4, "Every adjacent card is flipped exactly once")


func _test_tier_three_reenters_as_enemy_bagua_with_same_instance() -> void:
	var board: Array = Rules.empty_board()
	var yusui: Dictionary = Catalog.create_instance(
		&"YuSuiKunGang3", Rules.PLAYER_OWNER, &"rebirth_yusui"
	)
	yusui["powers"] = [1, 1, 1, 1]
	board[4] = _slot(yusui, Rules.PLAYER_OWNER)
	board[1] = _slot(_plain(&"rebirth_neighbor", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var state := State.new(board)
	var result: Dictionary = Simulator._resolve_trigger_event(
		state,
		Catalog.TRIGGER_END_OWNER_TURN,
		{"turn_owner_id": Rules.PLAYER_OWNER}
	)
	var reborn: Dictionary = _card_at(state, 4)
	_check(StringName(reborn.get("instance_id", &"")) == &"rebirth_yusui", "Rebirth preserves the exact runtime instance")
	_check(StringName(reborn.get("card_id", &"")) == &"BaGuaFangWei", "Tier three transforms into Bagua Fangwei")
	_check(_owner_at(state, 4) == Rules.OPPONENT_OWNER, "Reborn Bagua belongs to the former owner's enemy")
	_check(reborn.get("powers", []) == [-1, -1, -1, -1], "Reborn Bagua uses fresh catalog powers")
	_check(not _removed_has(state, Rules.PLAYER_OWNER, &"rebirth_yusui"), "Reborn instance leaves the removed zone")
	_check(_owner_at(state, 1) == Rules.PLAYER_OWNER, "Adjacent flips finish before rebirth")
	_check(
		_event_types_in_order(
			result.get("events", []),
			[
				&"card_flipped",
				&"card_transformed",
				&"card_departed_for_resummon",
				&"card_summoned",
			]
		),
		"Tier-three adjacent flip, transform, departure, and summon stay ordered"
	)
	_check(_event_count(result.get("events", []), &"card_exiled") == 0, "Successful tier-three rebirth cancels the pending exile")


func _test_captured_tier_three_uses_pre_exile_owner_for_enemy_relation() -> void:
	var board: Array = Rules.empty_board()
	var yusui: Dictionary = Catalog.create_instance(
		&"YuSuiKunGang3", Rules.PLAYER_OWNER, &"captured_yusui"
	)
	yusui["powers"] = [1, 1, 1, 1]
	board[4] = _slot(yusui, Rules.OPPONENT_OWNER)
	var state := State.new(board)
	Simulator._resolve_trigger_event(
		state,
		Catalog.TRIGGER_START_OWNER_TURN,
		{"turn_owner_id": Rules.OPPONENT_OWNER}
	)
	_check(_owner_at(state, 4) == Rules.PLAYER_OWNER, "Captured YuSui reenters for the enemy of its pre-exile owner")
	_check(StringName(_card_at(state, 4).get("card_id", &"")) == &"BaGuaFangWei", "Captured YuSui still transforms")
	_check(not _removed_has(state, Rules.PLAYER_OWNER, &"captured_yusui"), "Captured original-owner storage does not block reentry")


func _test_summon_owner_does_not_change_exact_card_source_owner() -> void:
	var board: Array = Rules.empty_board()
	var source: Dictionary = _plain(
		&"summon_owner_source",
		Rules.PLAYER_OWNER,
		[9, 9, 9, 9]
	)
	source["active_abilities"] = [Catalog.normalize_ability({
		"triggers": [{
			"event": Catalog.TRIGGER_START_OWNER_TURN,
			"actions": [{
				"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [Catalog.CARD_ZONE_HAND],
					"conditions": [{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY}],
					"limit": 1,
				},
				"actions": [{
					"type": Catalog.ACTION_SUMMON_CARD,
					"card": Catalog.CARD_REF_SELECTED_CARD,
					"cell": {
						"type": Catalog.CELL_REF_FIRST_ADJACENT_EMPTY,
						"card": Catalog.CARD_REF_ABILITY_SOURCE,
					},
					"owner": Catalog.OWNER_OPPONENT_OF_ABILITY_SOURCE,
				}],
			}],
		}],
	})]
	board[4] = _slot(source, Rules.PLAYER_OWNER)
	var hand_card: Dictionary = _plain(
		&"summon_owner_hand_card",
		Rules.PLAYER_OWNER
	)
	var state := State.new(board, [hand_card])
	Simulator._resolve_trigger_event(
		state,
		Catalog.TRIGGER_START_OWNER_TURN,
		{"turn_owner_id": Rules.PLAYER_OWNER}
	)
	_check(state.get_hand(Rules.PLAYER_OWNER).is_empty(), "Summon owner override still takes the exact card from the ability owner's hand")
	_check(_instance_at(state, 1) == &"summon_owner_hand_card", "Exact hand instance enters the selected board cell")
	_check(_owner_at(state, 1) == Rules.OPPONENT_OWNER, "Summon owner override affects only the resulting board owner")


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


func _instance_at(state: State, cell: int) -> StringName:
	return StringName(_card_at(state, cell).get("instance_id", &""))


func _owner_at(state: State, cell: int) -> int:
	return int((state.board[cell] as Dictionary).get("owner", 0)) if state.board[cell] is Dictionary else 0


func _card_at(state: State, cell: int) -> Dictionary:
	return (state.board[cell] as Dictionary).get("card", {}) as Dictionary if state.board[cell] is Dictionary else {}


func _board_card(state: State, instance_id: StringName) -> Dictionary:
	for cell: int in range(state.board.size()):
		if _instance_at(state, cell) == instance_id:
			return _card_at(state, cell)
	return {}


func _removed_has(state: State, owner_id: int, instance_id: StringName) -> bool:
	for value: Variant in state.removed_cards.get(owner_id, []) as Array:
		if value is Dictionary and StringName((value as Dictionary).get("instance_id", &"")) == instance_id:
			return true
	return false


func _event_count(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for value: Variant in events:
		if value is Dictionary and StringName((value as Dictionary).get("type", &"")) == event_type:
			count += 1
	return count


func _event_types_in_order(events: Array, expected: Array[StringName]) -> bool:
	var next_index: int = 0
	for value: Variant in events:
		if not value is Dictionary:
			continue
		if next_index < expected.size() and StringName((value as Dictionary).get("type", &"")) == expected[next_index]:
			next_index += 1
	return next_index == expected.size()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
