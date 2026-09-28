extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Compact = preload("res://scripts/duel_compact_state.gd")
const Action = preload("res://scripts/duel_action.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_abilities()
	_test_next_hand_queue()
	_test_duplicate_queue_names_defer()
	_test_attack_modifiers_are_independent()
	_test_attack_attempt_presentation_events()
	_test_extra_play_attempt_draws_at_cap()
	_test_discard_source_extra_play_preserves_queue()
	_test_ally_attack_evasion()
	_test_tianluo_acquired_snapshot()
	_test_legacy_suppression_scalar_migrates()
	if _failures == 0:
		print("GUMU_ABILITY_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("GUMU_ABILITY_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _test_catalog_abilities() -> void:
	for card_id: StringName in [
		&"LangJiTianYa1", &"LangJiTianYa2", &"LangJiTianYa3",
		&"XiaoYuanYiJu1", &"XiaoYuanYiJu2", &"XiaoYuanYiJu3",
		&"LengYueKuiRen1", &"LengYueKuiRen2", &"LengYueKuiRen3",
		&"KongBi2", &"KongBi3", &"KongBi4",
		&"TianLuoDiWang2", &"TianLuoDiWang3", &"TianLuoDiWang4",
	]:
		_check(Catalog.has_card(card_id), "%s is registered" % card_id)
		_check(not (Catalog.get_definition(card_id).get("abilities", []) as Array).is_empty(),
			"%s has rule abilities" % card_id)


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
	board[4] = {"card": Catalog.create_instance(&"LangJiTianYa3", Rules.PLAYER_OWNER, &"extra_source"), "owner": Rules.PLAYER_OWNER}
	board[5] = {"card": Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"extra_target"), "owner": Rules.OPPONENT_OWNER}
	var state := State.new(board, [], [], Rules.PLAYER_OWNER, 1, [Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"draw_reward")])
	state.extra_card_play_granted_this_turn = true
	var result: Dictionary = Simulator.apply_action(state, Action.make_activate(4, &"extra_source", Action.TARGET_BOARD_CELL, 5))
	var next: State = result.get("state") as State
	_check(bool(result.get("valid", false)), "Tier-three activation resolves at an already-used extra-play cap")
	if next == null:
		return
	_check(_event_count(result.get("events", []), &"card_drawn") == 1, "KongBi draws before the capped extra-play attempt")
	_check(_event_count(result.get("events", []), &"extra_card_play_granted") == 0, "Capped attempt does not grant another play")


func _test_discard_source_extra_play_preserves_queue() -> void:
	var board: Array = Rules.empty_board()
	board[0] = {"card": Catalog.create_instance(&"LangJiTianYa3", Rules.PLAYER_OWNER, &"discard_source"), "owner": Rules.PLAYER_OWNER}
	board[8] = {"card": Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"discard_target"), "owner": Rules.OPPONENT_OWNER}
	var state := State.new(board, [
		Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"discard_play"),
		Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"normal_play"),
	], [], Rules.PLAYER_OWNER)
	state.effect_queue = [_queue_grant("冷月窥人", Catalog.GUMU_MINIMUM_DEFENSE_ON_ATTACK)]
	var activated: Dictionary = Simulator.apply_action(state, Action.make_activate(0, &"discard_source", Action.TARGET_BOARD_CELL, 8))
	var after_activation: State = activated.get("state") as State
	_check(bool(activated.get("valid", false)) and after_activation != null, "Tier-three activation grants a discard-source extra play")
	if after_activation == null:
		return
	_check(after_activation.next_hand_play_from_discard_owner == Rules.PLAYER_OWNER, "Extra opportunity carries discard-source marker")
	var played: Dictionary = Simulator.apply_action(after_activation, Action.make_play(0, 4, &"discard_play"))
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


func _test_legacy_suppression_scalar_migrates() -> void:
	var state := State.new(Rules.empty_board(), [Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"legacy_play")], [], Rules.PLAYER_OWNER)
	var compact := Compact.new()
	_check(compact.capture_state(state), "Legacy migration fixture captures")
	compact.scalars[Compact.SCALAR_PLAYER_PENDING_SUPPRESSION] = 2
	var restored: State = compact.restore()
	_check(restored != null and restored.effect_queue.size() == 2, "Old compact suppression scalar expands to queued records")
	var kernel: Object = ClassDB.instantiate(&"DuelNativeCompactKernel")
	_check(bool(kernel.call("load_compact_payload", compact.to_variant_payload())), "Native rules accept old compact suppression scalar")
	var transition: Dictionary = kernel.call("apply_play_transition", 0, 4, &"legacy_play") as Dictionary
	_check(bool(transition.get("valid", false)), "Legacy scalar layer is consumed on physical hand play")
	if bool(transition.get("valid", false)):
		var payload: Dictionary = transition.get("payload", {})
		var queue: Array = (payload.get("side_payload", {}) as Dictionary).get("effect_queue", [])
		var scalars: PackedInt32Array = payload.get("scalars", PackedInt32Array())
		_check(queue.size() == 1 and scalars[Compact.SCALAR_PLAYER_PENDING_SUPPRESSION] == 0, "Native transition retains only migrated queue state")


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
