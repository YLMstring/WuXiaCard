extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Action = preload("res://scripts/duel_action.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")
const Executor = preload("res://tests/helpers/duel_native_action_test_harness.gd")
const State = preload("res://scripts/duel_state.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_declarations()
	_test_occupied_ally_play()
	_test_neighbor_flip_protection_and_swaps()
	_test_array_attacks()
	_test_draw_and_opening_hand_effects()
	_test_remote_entry_and_flip_rewards()
	_test_double_hand_aura()
	_test_double_hand_previous_turn_target()
	_test_exile_card_requires_actual_removal()
	_test_double_hand_prevented_exile()
	if _failures == 0:
		print("QUANZHEN_DOUBLE_HAND_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("QUANZHEN_DOUBLE_HAND_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _test_catalog_declarations() -> void:
	_check(Catalog.validate_catalog().is_empty(), "Catalog validates")
	for card_id: StringName in [
		&"TianGangBeiDou2", &"TianGangBeiDou3", &"TianGangBeiDou4",
		&"TianGangBeiDou5", &"JinYanGong2", &"JinYanGong3", &"JinYanGong4",
		&"XianTianGong5", &"QiXinJuHui1", &"QiXinJuHui2",
		&"QiXinJuHui3", &"QiXinJuHui4", &"DingYangZhen1",
		&"DingYangZhen2", &"DingYangZhen3", &"DingYangZhen4",
		&"KongWanChengFan4", &"ZuoYouHuBo5",
	]:
		_check(Catalog.has_card(card_id), "%s exists" % card_id)
		if Catalog.has_card(card_id):
			_check(
				not (Catalog.get_definition(card_id).get("abilities", []) as Array).is_empty(),
				"%s has rule declarations" % card_id
			)
	_check(not Catalog.has_card(&"JinYanGong5"), "Retired JinYanGong5 ID is absent")
	_check(not Catalog.has_card(&"WuDangMianZhang4"), "Retired WuDangMianZhang4 ID is absent")
	for card_id: StringName in [&"TaiZuChangQuan", &"CangSongYingKe1", &"HuZhuaJueHuSHou1"]:
		_check(
			(Catalog.get_definition(card_id).get("abilities", []) as Array).is_empty(),
			"Unrelated %s remains without abilities" % card_id
		)
	var expected_abilities: Dictionary = {
		&"JinYanGong3": [Catalog.TIYUNZONG_LOCKED_FLIP_MOVE,
			Catalog.QZ_JINYAN_ENTRY_DRAW, Catalog.QZ_JINYAN_ALLY_DRAW_GAIN_KI],
		&"JinYanGong4": [Catalog.TIYUNZONG_LOCKED_FLIP_MOVE,
			Catalog.QZ_JINYAN_ENTRY_DRAW, Catalog.QZ_JINYAN_ALLY_DRAW_GAIN_KI_AND_PROTECT],
		&"XianTianGong5": [Catalog.QZ_XIANTIAN_OPENING_HAND_KI],
		&"DingYangZhen3": [Catalog.QZ_SPEND_KI_TO_PREVENT_FLIP,
			Catalog.QZ_DING_FLIP_PROTECT_AND_ALLY_KI],
		&"ZuoYouHuBo5": [Catalog.QZ_HUBO_BEFORE_SUMMON],
	}
	for card_id: StringName in expected_abilities.keys():
		_check(
			Catalog.get_definition(card_id).get("abilities", []) == expected_abilities[card_id],
			"%s has the exact approved ability sequence" % card_id
		)


func _test_occupied_ally_play() -> void:
	var board: Array = Rules.empty_board()
	board[4] = {"card": Catalog.create_instance(&"QiXinJuHui1", Rules.PLAYER_OWNER, &"old_ally"), "owner": Rules.PLAYER_OWNER}
	board[3] = {"card": Catalog.create_instance(&"QiXinJuHui1", Rules.OPPONENT_OWNER, &"enemy"), "owner": Rules.OPPONENT_OWNER}
	var card: Dictionary = Catalog.create_instance(&"KongWanChengFan4", Rules.PLAYER_OWNER, &"new_card")
	var state := State.new(board, [card], [], Rules.PLAYER_OWNER)
	var occupied_action: Action = Action.make_play(0, 4, &"new_card")
	_check(Simulator.is_action_legal(state, occupied_action), "KongWan may play over ally")
	_check(
		not Simulator.is_action_legal(state, Action.make_play(0, 3, &"new_card")),
		"KongWan may not play over enemy"
	)
	var result: Dictionary = Simulator.apply_action(state, occupied_action)
	_check(bool(result.get("valid", false)), "KongWan occupied ally play resolves")
	var next: State = result.get("state") as State
	if next != null:
		_check(_instance_at(next, 4) == &"new_card", "KongWan occupies the old ally cell")
		_check(_removed_has(next, Rules.PLAYER_OWNER, &"old_ally"), "Previous ally enters removed zone")
	_check(
		_events_in_order(result.get("events", []), [&"card_exiled", &"card_placed"]),
		"Occupied play exiles before placing"
	)
	board = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(&"YuSuiKunGang3", Rules.PLAYER_OWNER, &"reborn_ally"), Rules.PLAYER_OWNER)
	state = State.new(
		board,
		[Catalog.create_instance(&"KongWanChengFan4", Rules.PLAYER_OWNER, &"blocked_play")],
		[_plain(&"opponent_hand", Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER
	)
	var before_state: State = state.duplicate_state() as State
	result = Simulator.apply_action(state, Action.make_play(0, 4, &"blocked_play"))
	_check(not bool(result.get("valid", false)), "Reborn ally blocks occupied replacement")
	_check(
		_instance_at(state, 4) == _instance_at(before_state, 4)
		and state.get_hand(Rules.PLAYER_OWNER).size() == before_state.get_hand(Rules.PLAYER_OWNER).size()
		and (state.removed_cards.get(Rules.PLAYER_OWNER, []) as Array).is_empty(),
		"Invalid occupied replacement leaves source state unchanged"
	)


func _test_neighbor_flip_protection_and_swaps() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(&"QiXinJuHui1", Rules.PLAYER_OWNER, &"protected"), Rules.PLAYER_OWNER)
	board[1] = _slot(_plain(&"friend", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var state := State.new(board)
	Simulator.resolve_non_attack_flip(state, &"protected", Rules.OPPONENT_OWNER)
	_check(_owner_at(state, 4) == Rules.PLAYER_OWNER, "Adjacent friend prevents flip")
	_check(int(_card_at(state, 4).get("ki", -1)) == 0, "Protection spends one ki")

	board = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(&"TianGangBeiDou4", Rules.PLAYER_OWNER, &"tier_four"), Rules.PLAYER_OWNER)
	board[1] = _slot(_plain(&"swap_friend", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	state = State.new(board)
	Simulator.resolve_non_attack_flip(state, &"tier_four", Rules.OPPONENT_OWNER)
	_check(_instance_at(state, 4) == &"swap_friend", "Tier four swaps with first adjacent friend")
	_check(StringName(_card_at(state, 1).get("card_id", &"")) == &"TianGangBeiDou4", "Tier four re-enters at friend cell")

	board = Rules.empty_board()
	board[0] = _slot(Catalog.create_instance(&"TianGangBeiDou5", Rules.PLAYER_OWNER, &"remote_array"), Rules.PLAYER_OWNER)
	board[7] = _slot(Catalog.create_instance(&"QiXinJuHui1", Rules.PLAYER_OWNER, &"remote_target"), Rules.PLAYER_OWNER)
	board[4] = _slot(_plain(&"first_friend", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[6] = _slot(_plain(&"second_friend", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	state = State.new(board)
	Simulator.resolve_non_attack_flip(state, &"remote_target", Rules.OPPONENT_OWNER)
	_check(_instance_at(state, 7) == &"first_friend", "Tier five uses protected card's row-first neighbor")
	_check(StringName(_card_at(state, 4).get("card_id", &"")) == &"QiXinJuHui1", "Remote protected card re-enters")
	_check(_instance_at(state, 0) == &"remote_array", "Remote array does not join the swap")


func _test_array_attacks() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(&"TianGangBeiDou2", Rules.PLAYER_OWNER, &"adjacent_array"), Rules.PLAYER_OWNER)
	board[1] = _slot(_plain(&"adjacent_attacker", Rules.PLAYER_OWNER, [1, 9, 1, 1]), Rules.PLAYER_OWNER)
	board[2] = _slot(_plain(&"adjacent_target", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var state := State.new(board)
	Simulator._resolve_trigger_event(
		state, Catalog.TRIGGER_CARD_AFTER_SUMMONED,
		{"trigger_instance_id": &"adjacent_array", "trigger_cell": 4, "trigger_owner_id": Rules.PLAYER_OWNER}
	)
	_check(_owner_at(state, 2) == Rules.PLAYER_OWNER, "Tier two orders adjacent ally to attack")
	board = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(&"TianGangBeiDou5", Rules.PLAYER_OWNER, &"all_array"), Rules.PLAYER_OWNER)
	board[0] = _slot(_plain(&"remote_attacker", Rules.PLAYER_OWNER, [1, 9, 1, 1]), Rules.PLAYER_OWNER)
	board[1] = _slot(_plain(&"remote_target", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	state = State.new(board)
	Simulator._resolve_trigger_event(
		state, Catalog.TRIGGER_CARD_AFTER_SUMMONED,
		{"trigger_instance_id": &"all_array", "trigger_cell": 4, "trigger_owner_id": Rules.PLAYER_OWNER}
	)
	_check(_owner_at(state, 1) == Rules.PLAYER_OWNER, "Tier five orders nonadjacent ally to attack")


func _test_draw_and_opening_hand_effects() -> void:
	var jinyan: Dictionary = Catalog.create_instance(&"JinYanGong2", Rules.PLAYER_OWNER, &"jinyan")
	var state := State.new(
		Rules.empty_board(), [jinyan], [_plain(&"opponent", Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER, 1, [_plain(&"drawn", Rules.PLAYER_OWNER)]
	)
	var result: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4, &"jinyan"))
	_check(bool(result.get("valid", false)), "JinYan hand play resolves")
	var next: State = result.get("state") as State
	if next != null:
		_check(next.get_hand(Rules.PLAYER_OWNER).size() == 1, "JinYan draws one card")
		if not next.get_hand(Rules.PLAYER_OWNER).is_empty():
			_check(int((next.get_hand(Rules.PLAYER_OWNER)[0] as Dictionary).get("ki", 0)) == 1, "JinYan gives the drawn card one ki")
	jinyan = Catalog.create_instance(&"JinYanGong4", Rules.PLAYER_OWNER, &"jinyan_four")
	state = State.new(
		Rules.empty_board(), [jinyan], [_plain(&"opponent_four", Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER, 1, [_plain(&"drawn_four", Rules.PLAYER_OWNER)]
	)
	result = Simulator.apply_action(state, Action.make_play(0, 4, &"jinyan_four"))
	next = result.get("state") as State
	if next != null and not next.get_hand(Rules.PLAYER_OWNER).is_empty():
		var drawn_four: Dictionary = next.get_hand(Rules.PLAYER_OWNER)[0] as Dictionary
		_check(int(drawn_four.get("ki", 0)) == 1, "JinYan four gives drawn card ki")
		_check((drawn_four.get("active_abilities", []) as Array).size() == 1, "JinYan four grants drawn card protection")

	state = State.new(Rules.empty_board(), [
		Catalog.create_instance(&"XianTianGong5", Rules.PLAYER_OWNER, &"xiantian"),
		_plain(&"opening_friend", Rules.PLAYER_OWNER),
	])
	Simulator._resolve_trigger_event(state, Catalog.TRIGGER_DUEL_STARTED, {})
	_check(int((state.get_hand(Rules.PLAYER_OWNER)[0] as Dictionary).get("ki", 0)) == 1, "XianTian buffs itself at opening")
	_check(int((state.get_hand(Rules.PLAYER_OWNER)[1] as Dictionary).get("ki", 0)) == 1, "XianTian buffs other opening cards")


func _test_remote_entry_and_flip_rewards() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(Catalog.create_instance(&"QiXinJuHui2", Rules.PLAYER_OWNER, &"local_qixin"), Rules.PLAYER_OWNER)
	var state := State.new(board, [_plain(&"remote_entry", Rules.PLAYER_OWNER)], [_plain(&"opponent_local", Rules.OPPONENT_OWNER)])
	var result: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4, &"remote_entry"))
	var next: State = result.get("state") as State
	if next != null:
		_check(int(_card_at(next, 4).get("ki", 0)) == 0, "QiXin two ignores nonadjacent entry")
	board = Rules.empty_board()
	board[0] = _slot(Catalog.create_instance(&"QiXinJuHui2", Rules.PLAYER_OWNER, &"adjacent_qixin"), Rules.PLAYER_OWNER)
	state = State.new(board, [_plain(&"local_entry", Rules.PLAYER_OWNER)], [_plain(&"opponent_adjacent", Rules.OPPONENT_OWNER)])
	result = Simulator.apply_action(state, Action.make_play(0, 1, &"local_entry"))
	next = result.get("state") as State
	if next != null:
		_check(int(_card_at(next, 1).get("ki", 0)) == 1, "QiXin two buffs adjacent entry")
		_check((_card_at(next, 1).get("active_abilities", []) as Array).size() == 1, "QiXin two grants adjacent entry protection")
	board = Rules.empty_board()
	board[0] = _slot(Catalog.create_instance(&"QiXinJuHui3", Rules.PLAYER_OWNER, &"remote_qixin"), Rules.PLAYER_OWNER)
	board[4] = _slot(_plain(&"entry_neighbor", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	state = State.new(board, [_plain(&"entered", Rules.PLAYER_OWNER)], [_plain(&"opponent", Rules.OPPONENT_OWNER)])
	result = Simulator.apply_action(state, Action.make_play(0, 7, &"entered"))
	next = result.get("state") as State
	_check(bool(result.get("valid", false)), "Remote QiXin entry resolves")
	if next != null:
		_check(int(_card_at(next, 7).get("ki", 0)) == 1, "Remote QiXin grants ki near any ally")
		_check((_card_at(next, 7).get("active_abilities", []) as Array).size() == 1, "Remote QiXin grants protection")
	board = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(&"DingYangZhen2", Rules.PLAYER_OWNER, &"ding_two"), Rules.PLAYER_OWNER)
	board[3] = _slot(_plain(&"ding_two_target", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	state = State.new(board)
	Simulator._resolve_standard_attacks(state, 4, &"ding_two", &"ding_two_test")
	_check(int(_card_at(state, 3).get("ki", 0)) == 1, "DingYang two gives flipped target ki")
	_check((_card_at(state, 3).get("active_abilities", []) as Array).size() == 1, "DingYang two grants protection")

	board = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(&"DingYangZhen4", Rules.PLAYER_OWNER, &"ding"), Rules.PLAYER_OWNER)
	board[3] = _slot(_plain(&"flip_target", Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[0] = _slot(_plain(&"other_friend", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	state = State.new(board)
	Simulator._resolve_standard_attacks(state, 4, &"ding", &"ding_test")
	_check(_owner_at(state, 3) == Rules.PLAYER_OWNER, "DingYang flips its enemy")
	_check(int(_card_at(state, 3).get("ki", 0)) == 1, "DingYang includes flipped target in ally ki gain")
	_check((_card_at(state, 3).get("powers", []) as Array) == [2, 2, 2, 2], "DingYang includes flipped target in power gain")
	_check(int(_card_at(state, 0).get("ki", 0)) == 1, "DingYang grants other ally ki")
	_check((_card_at(state, 0).get("powers", []) as Array) == [2, 2, 2, 2], "DingYang grants other ally powers")


func _test_double_hand_aura() -> void:
	var hand: Array = [
		Catalog.create_instance(&"ZuoYouHuBo5", Rules.PLAYER_OWNER, &"hubo"),
		_plain(&"next_play", Rules.PLAYER_OWNER, [3, 3, 3, 3]),
	]
	(hand[1] as Dictionary)["ki"] = 1
	var state := State.new(
		Rules.empty_board(), hand, [_plain(&"opponent", Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER, 1, [_plain(&"reward_draw", Rules.PLAYER_OWNER)]
	)
	var result: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4, &"hubo"))
	_check(bool(result.get("valid", false)), "Double Hand enters and self-exiles")
	var next: State = result.get("state") as State
	if next == null:
		return
	_check(_removed_has(next, Rules.PLAYER_OWNER, &"hubo"), "Double Hand removes itself")
	_check((next.owner_auras_by_owner.get(Rules.PLAYER_OWNER, []) as Array).size() == 1, "Double Hand grants owner aura")
	_check(_event_count(result.get("events", []), &"card_drawn") == 0, "Self-exiled Double Hand does not reward its own removal")
	next.active_player = Rules.PLAYER_OWNER
	result = Simulator.apply_action(next, Action.make_play(0, 4, &"next_play"))
	_check(bool(result.get("valid", false)), "Next hand card resolves under aura")
	next = result.get("state") as State
	if next == null:
		return
	_check(_removed_has(next, Rules.PLAYER_OWNER, &"next_play"), "Aura removes latest hand play at turn end")
	_check(_event_count(result.get("events", []), &"card_drawn") == 1, "Successful removal draws once")
	_check(next.extra_card_plays_remaining == 1, "Successful removal grants extra play")
	_check(next.get_hand(Rules.PLAYER_OWNER).size() == 1, "Reward draw enters hand")


func _test_double_hand_previous_turn_target() -> void:
	var state := State.new(
		Rules.empty_board(),
		[Catalog.create_instance(&"ZuoYouHuBo5", Rules.PLAYER_OWNER, &"older_hubo")],
		[_plain(&"older_opponent", Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER, 1, [_plain(&"older_reward", Rules.PLAYER_OWNER)]
	)
	var result: Dictionary = Simulator.apply_action(state, Action.make_play(0, 0, &"older_hubo"))
	var next: State = result.get("state") as State
	if next == null:
		_check(false, "Double Hand prior-turn fixture starts")
		return
	var historical_card: Dictionary = _plain(&"historical_play", Rules.PLAYER_OWNER)
	var same_id_clone: Dictionary = _plain(&"other_instance", Rules.OPPONENT_OWNER)
	same_id_clone["card_id"] = historical_card.get("card_id", &"")
	next.board[4] = _slot(historical_card, Rules.OPPONENT_OWNER)
	next.board[5] = _slot(same_id_clone, Rules.OPPONENT_OWNER)
	next.last_hand_play_by_owner[Rules.PLAYER_OWNER] = {
		"played_by_owner_id": Rules.PLAYER_OWNER,
		"card_id": historical_card.get("card_id", &""),
		"instance_id": &"historical_play",
	}
	next.turn_count = 4
	result = Simulator._resolve_trigger_event(
		next, Catalog.TRIGGER_END_OWNER_TURN,
		{"turn_owner_id": Rules.PLAYER_OWNER}
	)
	_check(_removed_has(next, Rules.PLAYER_OWNER, &"historical_play"), "Aura reaches exact earlier-turn hand play after ownership flip")
	_check(_instance_at(next, 5) == &"other_instance", "Aura ignores another instance with the same card ID")
	_check(_event_count(result.get("events", []), &"card_drawn") == 1, "Earlier-turn successful exile draws once")
	result = Simulator._resolve_trigger_event(
		next, Catalog.TRIGGER_END_OWNER_TURN,
		{"turn_owner_id": Rules.PLAYER_OWNER}
	)
	_check(_event_count(result.get("events", []), &"card_exiled") == 0, "Absent exact prior play does not exile same-ID clone")
	_check(_event_count(result.get("events", []), &"extra_card_play_granted") == 0, "Absent exact prior play grants no extra play")


func _test_exile_card_requires_actual_removal() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(_plain(&"exile_source", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[4] = _slot(Catalog.create_instance(&"YuSuiKunGang3", Rules.PLAYER_OWNER, &"rescued_target"), Rules.PLAYER_OWNER)
	var state := State.new(board)
	var result: Dictionary = Executor.execute_actions(
		state, 0, &"exile_source", Rules.PLAYER_OWNER,
		[{"type": Catalog.ACTION_EXILE_CARD, "card": Catalog.CARD_REF_TRIGGER_CARD}],
		{"trigger_cell": 4, "trigger_instance_id": &"rescued_target", "trigger_owner_id": Rules.PLAYER_OWNER}
	)
	_check(_event_count(result.get("events", []), &"card_exiled") == 0, "YuSui's before-exile reaction prevents actual removal")
	_check(_instance_at(state, 4) == &"rescued_target", "Prevented exile preserves the target instance")
	_check(StringName(_card_at(state, 4).get("card_id", &"")) == &"BaGuaFangWei", "Before-exile transformation still takes effect")
	_check(StringName(result.get("result", &"")) == Catalog.ACTION_RESULT_NO_EFFECT, "Explicit exile reports NO_EFFECT when its target was rescued")
	board[4] = _slot(_plain(&"plain_target", Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	state = State.new(board)
	result = Executor.execute_actions(
		state, 0, &"exile_source", Rules.PLAYER_OWNER,
		[{"type": Catalog.ACTION_EXILE_CARD, "card": Catalog.CARD_REF_TRIGGER_CARD}],
		{"trigger_cell": 4, "trigger_instance_id": &"plain_target", "trigger_owner_id": Rules.PLAYER_OWNER}
	)
	_check(_removed_has(state, Rules.PLAYER_OWNER, &"plain_target"), "Plain target is actually removed")
	_check(StringName(result.get("result", &"")) == Catalog.ACTION_RESULT_APPLIED, "Explicit exile reports APPLIED after actual removal")


func _test_double_hand_prevented_exile() -> void:
	var state := State.new(
		Rules.empty_board(),
		[Catalog.create_instance(&"ZuoYouHuBo5", Rules.PLAYER_OWNER, &"rescue_hubo")],
		[_plain(&"rescue_opponent", Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER, 1, [_plain(&"rescue_reward", Rules.PLAYER_OWNER)]
	)
	var result: Dictionary = Simulator.apply_action(state, Action.make_play(0, 0, &"rescue_hubo"))
	var next: State = result.get("state") as State
	if next == null:
		_check(false, "Double Hand prevented-exile fixture starts")
		return
	next.board[4] = _slot(Catalog.create_instance(&"YuSuiKunGang3", Rules.PLAYER_OWNER, &"last_play_rescued"), Rules.PLAYER_OWNER)
	next.last_hand_play_by_owner[Rules.PLAYER_OWNER] = {
		"played_by_owner_id": Rules.PLAYER_OWNER,
		"card_id": &"YuSuiKunGang3",
		"instance_id": &"last_play_rescued",
	}
	result = Simulator._resolve_trigger_event(
		next, Catalog.TRIGGER_END_OWNER_TURN,
		{"turn_owner_id": Rules.PLAYER_OWNER}
	)
	_check(_instance_at(next, 4) == &"last_play_rescued", "Double Hand target survives through its exile reaction")
	_check(StringName(_card_at(next, 4).get("card_id", &"")) == &"BaGuaFangWei", "Double Hand attempted the target's exile")
	_check(_event_count(result.get("events", []), &"card_exiled") == 0, "Rescued prior play emits no exile event")
	_check(_event_count(result.get("events", []), &"card_drawn") == 0, "Prevented removal does not draw")
	_check(_event_count(result.get("events", []), &"extra_card_play_granted") == 0, "Prevented removal grants no extra play")


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


func _card_at(state: State, cell: int) -> Dictionary:
	return (state.board[cell] as Dictionary).get("card", {}) as Dictionary if state.board[cell] is Dictionary else {}


func _instance_at(state: State, cell: int) -> StringName:
	return StringName(_card_at(state, cell).get("instance_id", &""))


func _owner_at(state: State, cell: int) -> int:
	return int((state.board[cell] as Dictionary).get("owner", 0)) if state.board[cell] is Dictionary else 0


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


func _events_in_order(events: Array, expected: Array[StringName]) -> bool:
	var next_index: int = 0
	for value: Variant in events:
		if value is Dictionary and next_index < expected.size() and StringName((value as Dictionary).get("type", &"")) == expected[next_index]:
			next_index += 1
	return next_index == expected.size()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("FAIL: %s" % message)
