extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Executor = preload("res://scripts/duel_ability_executor.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_vocabulary_and_catalog_declarations()
	_test_activation_resummons_fresh_instances_in_order()
	_test_flip_move_replaces_only_when_move_succeeds()
	_test_tier_four_draws_only_outside_current_owner_hand()
	_finish()


func _test_vocabulary_and_catalog_declarations() -> void:
	_check(Catalog.ACTION_DEPART_CARD_FOR_RESUMMON in Catalog.KNOWN_ACTIONS, "Generic resummon departure is registered")
	_check(Catalog.CARD_REF_LAST_SUMMONED_CARD in Catalog.KNOWN_CARD_REFERENCES, "Last summoned card is a known reference")
	_check(
		Catalog.CONDITION_TRIGGER_CARD_OUTSIDE_SOURCE_OWNER_HAND in Catalog.KNOWN_TRIGGER_CONDITIONS,
		"Outside-current-owner-hand exile condition is registered"
	)
	_check(Catalog.validate_catalog().is_empty(), "All TiYunZong declarations validate")
	for card_id: StringName in [&"TiYunZong2", &"TiYunZong3", &"TiYunZong4"]:
		_check(card_id in Catalog.get_all_card_ids(), "%s is in catalog order" % card_id)
	var expected_counts: Dictionary = {
		&"TiYunZong2": 1,
		&"TiYunZong3": 2,
		&"TiYunZong4": 3,
	}
	for card_id: StringName in expected_counts:
		_check(
			(Catalog.get_definition(card_id).get("abilities", []) as Array).size()
			== int(expected_counts[card_id]),
			"%s declares each ability separately" % card_id
		)


func _test_activation_resummons_fresh_instances_in_order() -> void:
	var board: Array = Rules.empty_board()
	var source: Dictionary = Catalog.create_instance(&"TiYunZong2", Rules.PLAYER_OWNER, &"old_tiyun")
	board[4] = _slot(source, Rules.PLAYER_OWNER)
	board[0] = _slot(Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"old_ally"), Rules.PLAYER_OWNER)
	board[1] = _slot(_plain(&"tiyun_attack_target", [1, 1, 6, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var state := State.new(
		board,
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"extra_play_card")],
		[],
		Rules.PLAYER_OWNER
	)
	var transition: Dictionary = Simulator.apply_action(
		state,
		Action.make_activate(4, &"old_tiyun", Action.TARGET_BOARD_CELL, 0)
	)
	var next_state: State = transition.get("state") as State
	var new_ally: Dictionary = (next_state.board[4] as Dictionary).get("card", {})
	var new_tiyun: Dictionary = (next_state.board[0] as Dictionary).get("card", {})
	_check(StringName(new_ally.get("card_id", &"")) == &"TaiZuChangQuan", "Selected ally reenters in old TiYun cell")
	_check(StringName(new_tiyun.get("card_id", &"")) == &"TiYunZong2", "TiYun reenters in selected ally cell")
	_check(StringName(new_ally.get("instance_id", &"")) not in [&"", &"old_ally"], "Selected ally receives a fresh instance ID")
	_check(StringName(new_tiyun.get("instance_id", &"")) not in [&"", &"old_tiyun"], "TiYun receives a fresh instance ID")
	_check(int(new_tiyun.get("ki", -1)) == 0, "Fresh TiYun immediately spends its starting ki after attacking")
	_check(next_state.extra_card_plays_remaining == 1, "Fresh TiYun grants one extra card play")
	_check(_find_any_zone_instance(next_state, &"old_ally") == &"", "Old ally instance disappears without entering another zone")
	_check(_find_any_zone_instance(next_state, &"old_tiyun") == &"", "Old TiYun instance disappears without entering another zone")
	_check(
		_count_events(transition.get("events", []), &"card_departed_for_resummon") == 2,
		"Both old instances depart without exile"
	)
	_check(_count_events(transition.get("events", []), &"card_exiled") == 0, "Resummon departure is not exile")
	var events: Array = transition.get("events", [])
	var ally_summon_index: int = _event_index_for_card_id(events, &"card_summoned", &"TaiZuChangQuan")
	var tiyun_summon_index: int = _event_index_for_card_id(events, &"card_summoned", &"TiYunZong2")
	var last_attack_index: int = _last_event_index(events, &"attack_started")
	var fresh_ki_index: int = _event_index_for_instance(events, &"ki_changed", StringName(new_tiyun.get("instance_id", &"")))
	var extra_index: int = _event_index(events, &"extra_card_play_granted")
	_check(ally_summon_index >= 0 and ally_summon_index < tiyun_summon_index, "Selected ally fully enters before fresh TiYun")
	_check(tiyun_summon_index < last_attack_index and last_attack_index < fresh_ki_index, "Fresh TiYun attacks before spending ki")
	_check(fresh_ki_index < extra_index, "Fresh TiYun spends ki before granting the extra play")


func _test_flip_move_replaces_only_when_move_succeeds() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(&"TiYunZong3", Rules.OPPONENT_OWNER, &"moving_tiyun"), Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [_plain(&"move_attacker", [9, 9, 9, 9], Rules.PLAYER_OWNER)], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 1, &"move_attacker")
	)
	var next_state: State = transition.get("state") as State
	_check(next_state.board[4] == null, "TiYun leaves its attacked cell before flip")
	_check(
		_find_board_instance(next_state.board, &"moving_tiyun") == 3
		and int((next_state.board[3] as Dictionary).get("owner", 0)) == Rules.OPPONENT_OWNER,
		"TiYun moves to the lowest-index adjacent empty cell and prevents flip"
	)
	_check(_count_events(transition.get("events", []), &"card_flip_prevented") == 1, "Successful move explicitly prevents the flip")

	var full_board: Array = Rules.empty_board()
	full_board[4] = _slot(Catalog.create_instance(&"TiYunZong3", Rules.OPPONENT_OWNER, &"trapped_tiyun"), Rules.OPPONENT_OWNER)
	for cell_index: int in [3, 5, 7]:
		full_board[cell_index] = _slot(_plain(StringName("block_%d" % cell_index), [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var trapped_transition: Dictionary = Simulator.apply_action(
		State.new(full_board, [_plain(&"trap_attacker", [9, 9, 9, 9], Rules.PLAYER_OWNER)], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 1, &"trap_attacker")
	)
	var trapped_state: State = trapped_transition.get("state") as State
	_check(int((trapped_state.board[4] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER, "TiYun flips normally when no adjacent empty cell exists")
	_check(
		_card_has_trigger((trapped_state.board[4] as Dictionary).get("card", {}), Catalog.CARD_BEFORE_FLIPPED),
		"Locked flip-move ability survives the ownership flip"
	)


func _test_tier_four_draws_only_outside_current_owner_hand() -> void:
	var own_hand_board: Array = Rules.empty_board()
	own_hand_board[8] = _slot(Catalog.create_instance(&"TiYunZong4", Rules.PLAYER_OWNER, &"own_hand_tiyun"), Rules.PLAYER_OWNER)
	own_hand_board[7] = _slot(Catalog.create_instance(&"HuZhuaJueHuSHou4", Rules.OPPONENT_OWNER, &"enemy_huzhua"), Rules.OPPONENT_OWNER)
	var own_hand_transition: Dictionary = Simulator.apply_action(
		State.new(
			own_hand_board,
			[Catalog.create_instance(&"TuNaShu1", Rules.PLAYER_OWNER, &"own_draw_source")],
			[],
			Rules.PLAYER_OWNER,
			0,
			[_plain(&"own_intercepted_draw", [1, 1, 1, 1], Rules.PLAYER_OWNER)],
			[]
		),
		Action.make_play(0, 4, &"own_draw_source")
	)
	_check(_count_events(own_hand_transition.get("events", []), &"card_drawn") == 1, "Removing a card from TiYun owner's hand does not trigger another draw")

	var enemy_hand_board: Array = Rules.empty_board()
	enemy_hand_board[8] = _slot(Catalog.create_instance(&"TiYunZong4", Rules.PLAYER_OWNER, &"enemy_hand_tiyun"), Rules.PLAYER_OWNER)
	enemy_hand_board[7] = _slot(Catalog.create_instance(&"HuZhuaJueHuSHou4", Rules.PLAYER_OWNER, &"ally_huzhua"), Rules.PLAYER_OWNER)
	var enemy_hand_transition: Dictionary = Simulator.apply_action(
		State.new(
			enemy_hand_board,
			[],
			[Catalog.create_instance(&"TuNaShu1", Rules.OPPONENT_OWNER, &"enemy_draw_source")],
			Rules.OPPONENT_OWNER,
			0,
			[_plain(&"tiyun_reward_draw", [2, 2, 2, 2], Rules.PLAYER_OWNER)],
			[_plain(&"enemy_intercepted_draw", [1, 1, 1, 1], Rules.OPPONENT_OWNER)]
		),
		Action.make_play(0, 4, &"enemy_draw_source")
	)
	_check(_count_events(enemy_hand_transition.get("events", []), &"card_drawn") == 2, "Removing an enemy hand card triggers TiYun's draw")
	_check(
		_find_hand_instance((enemy_hand_transition.get("state") as State).get_hand(Rules.PLAYER_OWNER), &"tiyun_reward_draw") >= 0,
		"Outside-hand removal draws for TiYun's current owner"
	)


func _plain(instance_id: StringName, powers: Array[int], owner_id: int, abilities: Array = []) -> Dictionary:
	var card: Dictionary = Rules.make_card(String(instance_id), String(instance_id), powers, abilities, owner_id, instance_id)
	card["instance_id"] = instance_id
	return card


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _find_board_instance(board: Array, instance_id: StringName) -> int:
	for cell_index: int in range(board.size()):
		var slot_value: Variant = board[cell_index]
		if slot_value is Dictionary and StringName((((slot_value as Dictionary).get("card", {})) as Dictionary).get("instance_id", &"")) == instance_id:
			return cell_index
	return -1


func _find_hand_instance(hand: Array, instance_id: StringName) -> int:
	for index: int in range(hand.size()):
		if hand[index] is Dictionary and StringName((hand[index] as Dictionary).get("instance_id", &"")) == instance_id:
			return index
	return -1


func _find_any_zone_instance(state: State, instance_id: StringName) -> StringName:
	if _find_board_instance(state.board, instance_id) >= 0:
		return Catalog.CARD_ZONE_BOARD
	for owner_id: int in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		if _find_hand_instance(state.get_hand(owner_id), instance_id) >= 0:
			return Catalog.CARD_ZONE_HAND
		if _find_hand_instance(state.removed_cards.get(owner_id, []) as Array, instance_id) >= 0:
			return Catalog.CARD_ZONE_REMOVED
	return &""


func _count_events(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for event_value: Variant in events:
		if event_value is Dictionary and StringName((event_value as Dictionary).get("type", &"")) == event_type:
			count += 1
	return count


func _card_has_trigger(card: Dictionary, event_type: StringName) -> bool:
	for ability_value: Variant in card.get("active_abilities", card.get("abilities", [])):
		if not ability_value is Dictionary:
			continue
		for trigger_value: Variant in (ability_value as Dictionary).get("triggers", []):
			if (
				trigger_value is Dictionary
				and StringName((trigger_value as Dictionary).get("event", &"")) == event_type
			):
				return true
	return false


func _event_index(events: Array, event_type: StringName) -> int:
	for index: int in range(events.size()):
		if events[index] is Dictionary and StringName((events[index] as Dictionary).get("type", &"")) == event_type:
			return index
	return 9999


func _last_event_index(events: Array, event_type: StringName) -> int:
	for index: int in range(events.size() - 1, -1, -1):
		if events[index] is Dictionary and StringName((events[index] as Dictionary).get("type", &"")) == event_type:
			return index
	return -1


func _event_index_for_card_id(events: Array, event_type: StringName, card_id: StringName) -> int:
	for index: int in range(events.size()):
		var event_value: Variant = events[index]
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
			and StringName((event_value as Dictionary).get("card_id", &"")) == card_id
		):
			return index
	return 9999


func _event_index_for_instance(events: Array, event_type: StringName, instance_id: StringName) -> int:
	for index: int in range(events.size()):
		var event_value: Variant = events[index]
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
			and StringName((event_value as Dictionary).get("instance_id", &"")) == instance_id
		):
			return index
	return 9999


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)


func _finish() -> void:
	if _failures == 0:
		print("TIYUNZONG_ABILITY_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("TIYUNZONG_ABILITY_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)
