extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_vocabulary_and_declarations()
	_test_yikong_exiles_at_summoned_timing_and_refills_hand()
	_test_yikong_five_discards_physical_rightmost_enemy_card()
	_test_ranmu_activation_targets_own_hand()
	_test_ranmu_three_buffs_only_after_a_real_attack()
	_test_wuxiang_activation_attacks_after_discard_before_draw()
	_test_wuxiang_four_attacks_once_after_a_batch()
	_test_multiple_wuxiang_sources_resolve_row_major()
	_test_lijing_four_locks_and_discards_two_as_one_batch()
	if _failures == 0:
		print("SHAOLIN_DISCARD_ABILITIES_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"SHAOLIN_DISCARD_ABILITIES_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_vocabulary_and_declarations() -> void:
	_check(Catalog.TARGET_ALLY_HAND_CARD in Catalog.KNOWN_TARGET_RULES, "Ally hand target is registered")
	_check(Catalog.ACTION_DISCARD_CARDS in Catalog.KNOWN_ACTIONS, "Batch discard action is registered")
	_check(Catalog.TRIGGER_DISCARD_BATCH_FINISHED in Catalog.KNOWN_TRIGGER_EVENTS, "Discard batch event is registered")
	_check(Catalog.CONDITION_DISCARD_OWNER_IS_SELF in Catalog.KNOWN_TRIGGER_CONDITIONS, "Discard owner condition is registered")
	_check(Catalog.CONDITION_LAST_DISCARD_BATCH_SIZE_AT_LEAST in Catalog.KNOWN_ACTION_CONDITIONS, "Discard batch size condition is registered")
	_check(Catalog.SELECT_ORDER_HAND_RIGHT_TO_LEFT in Catalog.KNOWN_SELECTOR_ORDERS, "Right-to-left hand order is registered")
	_check(Catalog.validate_catalog().is_empty(), "Complete catalog validates")
	for card_id: StringName in [
		&"YiKongDaoDi4",
		&"YiKongDaoDi5",
		&"RanMuDaoFa2",
		&"RanMuDaoFa3",
		&"WuXiangJieZhi3",
		&"WuXiangJieZhi4",
	]:
		_check(
			not (Catalog.get_definition(card_id).get("abilities", []) as Array).is_empty(),
			"%s declares its complete abilities" % card_id
		)


func _test_yikong_exiles_at_summoned_timing_and_refills_hand() -> void:
	var yikong: Dictionary = Catalog.create_instance(&"YiKongDaoDi4", Rules.PLAYER_OWNER, &"yikong_four")
	var first: Dictionary = _plain(&"yikong_first", Rules.PLAYER_OWNER)
	var second: Dictionary = _plain(&"yikong_second", Rules.PLAYER_OWNER)
	yikong[State.HAND_SLOT_INDEX_KEY] = 0
	first[State.HAND_SLOT_INDEX_KEY] = 1
	second[State.HAND_SLOT_INDEX_KEY] = 4
	var deck: Array = []
	for index: int in range(5):
		deck.append(Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, StringName("yikong_draw_%d" % index)))
	var transition: Dictionary = Simulator.apply_action_oracle(
		State.new(
			Rules.empty_board(),
			[yikong, second, first],
			[_plain(&"yikong_enemy_hand", Rules.OPPONENT_OWNER)],
			Rules.PLAYER_OWNER,
			0,
			deck,
			[]
		),
		Action.make_play(0, 4, &"yikong_four")
	)
	var next_state: State = transition.get("state") as State
	var events: Array = transition.get("events", [])
	_check(next_state.board[4] == null, "YiKong leaves the board during summoned timing")
	_check(_pile_has(next_state.removed_cards[Rules.PLAYER_OWNER] as Array, &"yikong_four"), "YiKong is really exiled")
	_check((next_state.discard_piles[Rules.PLAYER_OWNER] as Array).size() == 2, "YiKong batch-discards every remaining allied hand card")
	_check(next_state.get_hand(Rules.PLAYER_OWNER).size() == 5, "YiKong draws five cards after the discard batch")
	_check(
		_event_index(events, &"card_placed") < _event_index(events, &"card_exiled")
		and _event_index(events, &"card_exiled") < _event_index(events, &"card_discarded")
		and _last_event_index(events, &"card_discarded") < _event_index(events, &"card_drawn"),
		"YiKong presents placement, exile, the complete discard batch, then draws"
	)
	_check(_event_count(events, &"attack_started") == 0, "Exiled YiKong never reaches its standard attack")


func _test_yikong_five_discards_physical_rightmost_enemy_card() -> void:
	var yikong: Dictionary = Catalog.create_instance(&"YiKongDaoDi5", Rules.PLAYER_OWNER, &"yikong_five")
	var logical_first: Dictionary = _plain(&"enemy_rightmost", Rules.OPPONENT_OWNER)
	var logical_second: Dictionary = _plain(&"enemy_leftmost", Rules.OPPONENT_OWNER)
	logical_first[State.HAND_SLOT_INDEX_KEY] = 4
	logical_second[State.HAND_SLOT_INDEX_KEY] = 0
	var transition: Dictionary = Simulator.apply_action_oracle(
		State.new(
			Rules.empty_board(),
			[yikong],
			[logical_first, logical_second],
			Rules.PLAYER_OWNER
		),
		Action.make_play(0, 4, &"yikong_five")
	)
	var next_state: State = transition.get("state") as State
	_check(
		_pile_has(next_state.discard_piles[Rules.OPPONENT_OWNER] as Array, &"enemy_rightmost")
		and _hand_has(next_state.get_hand(Rules.OPPONENT_OWNER), &"enemy_leftmost"),
		"YiKong five discards the opponent's physical rightmost occupied slot"
	)


func _test_ranmu_activation_targets_own_hand() -> void:
	var source: Dictionary = Catalog.create_instance(&"RanMuDaoFa2", Rules.PLAYER_OWNER, &"ranmu_source")
	var ally: Dictionary = _plain(&"ranmu_ally", Rules.PLAYER_OWNER)
	var own_target: Dictionary = _plain(&"ranmu_own_target", Rules.PLAYER_OWNER)
	var remaining_hand: Dictionary = _plain(&"ranmu_remaining", Rules.PLAYER_OWNER)
	var enemy_hand: Dictionary = _plain(&"ranmu_enemy_hand", Rules.OPPONENT_OWNER)
	var board: Array = Rules.empty_board()
	board[0] = _slot(ally, Rules.PLAYER_OWNER)
	board[4] = _slot(source, Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action_oracle(
		State.new(board, [own_target, remaining_hand], [enemy_hand], Rules.PLAYER_OWNER),
		Action.make_activate(4, &"ranmu_source", Action.TARGET_HAND_SLOT, 0)
	)
	var next_state: State = transition.get("state") as State
	_check(bool(transition.get("valid", false)), "RanMu activation accepts an allied hand target")
	_check(
		_pile_has(next_state.discard_piles[Rules.PLAYER_OWNER] as Array, &"ranmu_own_target")
		and _hand_has(next_state.get_hand(Rules.OPPONENT_OWNER), &"ranmu_enemy_hand"),
		"RanMu discards the selected allied hand instance, not the opponent's matching index"
	)
	_check(_board_card(next_state, &"ranmu_source").get("powers", []) == [6, 8, 8, 6], "RanMu buffs itself")
	_check(_board_card(next_state, &"ranmu_ally").get("powers", []) == [2, 2, 2, 2], "RanMu buffs every allied board card")
	_check(next_state.extra_card_plays_remaining == 1, "RanMu grants exactly one extra card play")


func _test_ranmu_three_buffs_only_after_a_real_attack() -> void:
	var source: Dictionary = Catalog.create_instance(&"RanMuDaoFa3", Rules.PLAYER_OWNER, &"ranmu_attack")
	var defender: Dictionary = _plain(&"ranmu_defender", Rules.OPPONENT_OWNER)
	var board: Array = Rules.empty_board()
	board[5] = _slot(defender, Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action_oracle(
		State.new(board, [source], [_plain(&"ranmu_reply", Rules.OPPONENT_OWNER)], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"ranmu_attack")
	)
	var next_state: State = transition.get("state") as State
	_check(_event_count(transition.get("events", []), &"attack_started") == 1, "RanMu fixture completes a real attack")
	_check(_board_card(next_state, &"ranmu_attack").get("powers", []) == [6, 8, 8, 6], "RanMu buffs after its real attack")
	_check(_board_card(next_state, &"ranmu_defender").get("powers", []) == [2, 2, 2, 2], "The newly flipped ally joins RanMu's post-attack buff")

	var idle_source: Dictionary = Catalog.create_instance(&"RanMuDaoFa3", Rules.PLAYER_OWNER, &"ranmu_idle")
	var idle_board: Array = Rules.empty_board()
	idle_board[8] = _slot(_plain(&"ranmu_far_enemy", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var idle_transition: Dictionary = Simulator.apply_action_oracle(
		State.new(idle_board, [idle_source], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"ranmu_idle")
	)
	_check(_event_count(idle_transition.get("events", []), &"attack_started") == 0, "RanMu fixture without a legal target starts no attack")
	_check(_board_card(idle_transition.get("state") as State, &"ranmu_idle").get("powers", []) == [5, 7, 7, 5], "RanMu receives no post-attack buff when no attack occurred")


func _test_wuxiang_activation_attacks_after_discard_before_draw() -> void:
	var source: Dictionary = Catalog.create_instance(&"WuXiangJieZhi4", Rules.PLAYER_OWNER, &"wuxiang_activate")
	var target: Dictionary = _plain(&"wuxiang_activation_target", Rules.PLAYER_OWNER)
	var enemy: Dictionary = _plain(&"wuxiang_activation_enemy", Rules.OPPONENT_OWNER)
	var drawn: Dictionary = Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"wuxiang_drawn")
	var board: Array = Rules.empty_board()
	board[0] = _slot(source, Rules.PLAYER_OWNER)
	board[8] = _slot(enemy, Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action_oracle(
		State.new(board, [target], [], Rules.PLAYER_OWNER, 0, [drawn], []),
		Action.make_activate(0, &"wuxiang_activate", Action.TARGET_HAND_SLOT, 0)
	)
	var events: Array = transition.get("events", [])
	_check(bool(transition.get("valid", false)), "WuXiang activation accepts an allied hand target")
	_check(
		_event_index(events, &"card_discarded") < _event_index(events, &"attack_started")
		and _event_index(events, &"attack_started") < _event_index(events, &"card_drawn"),
		"WuXiang completes discard-batch reactions before its activation draw"
	)


func _test_wuxiang_four_attacks_once_after_a_batch() -> void:
	var wuxiang: Dictionary = Catalog.create_instance(&"WuXiangJieZhi4", Rules.PLAYER_OWNER, &"wuxiang_watcher")
	var yikong: Dictionary = Catalog.create_instance(&"YiKongDaoDi4", Rules.PLAYER_OWNER, &"wuxiang_yikong")
	var first: Dictionary = _plain(&"wuxiang_discard_one", Rules.PLAYER_OWNER)
	var second: Dictionary = _plain(&"wuxiang_discard_two", Rules.PLAYER_OWNER)
	var enemy: Dictionary = _plain(&"wuxiang_enemy", Rules.OPPONENT_OWNER)
	var board: Array = Rules.empty_board()
	board[0] = _slot(wuxiang, Rules.PLAYER_OWNER)
	board[8] = _slot(enemy, Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action_oracle(
		State.new(board, [yikong, first, second], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"wuxiang_yikong")
	)
	var events: Array = transition.get("events", [])
	_check(_event_count(events, &"card_discarded") == 2, "Fixture produces a two-card discard batch")
	_check(_event_count(events, &"attack_started") == 1, "WuXiang four attacks once for the whole discard batch")
	_check(
		_last_event_index(events, &"card_discarded") < _event_index(events, &"attack_started"),
		"WuXiang waits until every locked discard has completed"
	)


func _test_multiple_wuxiang_sources_resolve_row_major() -> void:
	var first: Dictionary = Catalog.create_instance(&"WuXiangJieZhi4", Rules.PLAYER_OWNER, &"wuxiang_first")
	var second: Dictionary = Catalog.create_instance(&"WuXiangJieZhi4", Rules.PLAYER_OWNER, &"wuxiang_second")
	var yikong: Dictionary = Catalog.create_instance(&"YiKongDaoDi4", Rules.PLAYER_OWNER, &"wuxiang_multi_yikong")
	var board: Array = Rules.empty_board()
	board[0] = _slot(first, Rules.PLAYER_OWNER)
	board[2] = _slot(second, Rules.PLAYER_OWNER)
	board[6] = _slot(_plain(&"wuxiang_enemy_first", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[8] = _slot(_plain(&"wuxiang_enemy_second", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action_oracle(
		State.new(board, [yikong, _plain(&"wuxiang_multi_discard", Rules.PLAYER_OWNER)], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"wuxiang_multi_yikong")
	)
	var attacking_sources: Array[StringName] = []
	for event: Dictionary in _events_of_type(transition.get("events", []), &"attack_started"):
		attacking_sources.append(StringName(event.get("source_instance_id", &"")))
	_check(attacking_sources == [&"wuxiang_first", &"wuxiang_second"], "Multiple WuXiang discard reactions resolve in board row-major order")


func _test_lijing_four_locks_and_discards_two_as_one_batch() -> void:
	var source: Dictionary = Catalog.create_instance(&"LiJingRuLai4", Rules.PLAYER_OWNER, &"lijing_batch")
	var first: Dictionary = _plain(&"lijing_first", Rules.PLAYER_OWNER)
	var second: Dictionary = _plain(&"lijing_second", Rules.PLAYER_OWNER)
	var third: Dictionary = _plain(&"lijing_third", Rules.PLAYER_OWNER)
	first[State.HAND_SLOT_INDEX_KEY] = 0
	second[State.HAND_SLOT_INDEX_KEY] = 2
	third[State.HAND_SLOT_INDEX_KEY] = 4
	source[State.HAND_SLOT_INDEX_KEY] = 1
	var transition: Dictionary = Simulator.apply_action_oracle(
		State.new(
			Rules.empty_board(),
			[third, source, second, first],
			[_plain(&"lijing_enemy", Rules.OPPONENT_OWNER)],
			Rules.PLAYER_OWNER
		),
		Action.make_play(1, 4, &"lijing_batch")
	)
	var next_state: State = transition.get("state") as State
	var discarded_events: Array[Dictionary] = _events_of_type(transition.get("events", []), &"card_discarded")
	_check(
		_pile_has(next_state.discard_piles[Rules.PLAYER_OWNER] as Array, &"lijing_first")
		and _pile_has(next_state.discard_piles[Rules.PLAYER_OWNER] as Array, &"lijing_second")
		and _hand_has(next_state.get_hand(Rules.PLAYER_OWNER), &"lijing_third"),
		"LiJing locks the physical leftmost two cards at trigger start"
	)
	_check(discarded_events.size() == 2, "LiJing emits one discard event per card")
	_check(
		discarded_events.size() == 2
		and StringName(discarded_events[0].get("discard_batch_id", &"")) != &""
		and discarded_events[0].get("discard_batch_id") == discarded_events[1].get("discard_batch_id"),
		"LiJing's two discard events share one batch identity"
	)
	_check(_board_card(next_state, &"lijing_batch").get("powers", []) == [9, 9, 9, 9], "LiJing gains three after paying both locked cards")
	_check(_event_count(transition.get("events", []), &"hand_cards_shifted") == 1, "A batch computes one final hand shift")


func _plain(instance_id: StringName, owner_id: int) -> Dictionary:
	var card: Dictionary = Rules.make_card(String(instance_id), "测", [1, 1, 1, 1], [], owner_id)
	card["instance_id"] = instance_id
	return card


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _board_card(state: State, instance_id: StringName) -> Dictionary:
	for slot_value: Variant in state.board:
		if not slot_value is Dictionary:
			continue
		var card: Dictionary = (slot_value as Dictionary).get("card", {})
		if StringName(card.get("instance_id", &"")) == instance_id:
			return card
	return {}


func _pile_has(cards: Array, instance_id: StringName) -> bool:
	return _hand_has(cards, instance_id)


func _hand_has(cards: Array, instance_id: StringName) -> bool:
	for value: Variant in cards:
		if value is Dictionary and StringName((value as Dictionary).get("instance_id", &"")) == instance_id:
			return true
	return false


func _events_of_type(events: Array, event_type: StringName) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for value: Variant in events:
		if value is Dictionary and StringName((value as Dictionary).get("type", &"")) == event_type:
			matches.append(value as Dictionary)
	return matches


func _event_count(events: Array, event_type: StringName) -> int:
	return _events_of_type(events, event_type).size()


func _event_index(events: Array, event_type: StringName) -> int:
	for index: int in range(events.size()):
		if events[index] is Dictionary and StringName((events[index] as Dictionary).get("type", &"")) == event_type:
			return index
	return -1


func _last_event_index(events: Array, event_type: StringName) -> int:
	for index: int in range(events.size() - 1, -1, -1):
		if events[index] is Dictionary and StringName((events[index] as Dictionary).get("type", &"")) == event_type:
			return index
	return -1


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
