extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const InitialStateFactory = preload("res://scripts/duel_initial_state_factory.gd")
const NativeRules = preload("res://scripts/duel_native_rules.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_declarations()
	_test_duel_start_reveal()
	_test_hidden_blade_center_restriction()
	_test_embrace_moon_aura_and_snapshot()
	_test_embrace_moon_tracks_attacked_ally_after_self_exile()
	_test_closed_door_attack_context()
	_test_owner_aura_expires_at_any_turn_end()
	_test_chuncan_cannot_attack_until_flipped()
	_finish()


func _test_catalog_declarations() -> void:
	_check(Catalog.validate_catalog().is_empty(), "The complete catalog validates")
	_check(Catalog.TRIGGER_DUEL_STARTED in Catalog.KNOWN_TRIGGER_EVENTS, "Duel-start event is registered")
	_check(Catalog.CONDITION_ATTACK_FLIPPED_ANY_CARD in Catalog.KNOWN_ACTION_CONDITIONS, "Attack-flip action condition is registered")
	_check(Catalog.ACTION_SET_ATTACK_USED_POWERS in Catalog.KNOWN_ACTIONS, "Directional power-set action is registered")
	_check(Catalog.ACTION_GRANT_OWNER_AURA in Catalog.KNOWN_ACTIONS, "Owner-aura grant action is registered")
	_check(Catalog.CONDITION_ABILITY_SOURCE_IN_ZONE in Catalog.KNOWN_TRIGGER_CONDITIONS, "Ability-source zone condition is registered")
	_check(Catalog.MODIFIER_CANNOT_ATTACK in Catalog.KNOWN_MODIFIERS, "Cannot-attack modifier is registered")
	_check(
		Catalog.MODIFIER_OPPONENT_PLAY_CELL_ONLY_IF_NO_OTHER_ACTION in Catalog.KNOWN_MODIFIERS,
		"Conditional cell restriction is registered"
	)
	_check(
		Catalog.get_definition(&"HuJiaDao1").get("abilities", []) == [Catalog.HUJIA_HIDDEN_BLADE],
		"HuJiaDao1 uses the approved full declaration"
	)
	_check(
		Catalog.get_definition(&"HuJiaDao2").get("abilities", []) == [Catalog.HUJIA_EMBRACE_MOON],
		"HuJiaDao2 uses the approved full declaration"
	)
	_check(
		Catalog.get_definition(&"HuJiaDao3").get("abilities", []) == [Catalog.HUJIA_CLOSED_DOOR],
		"HuJiaDao3 uses the approved full declaration"
	)
	for card_id: StringName in [&"ChunCanZhang2", &"ChunCanZhang3"]:
		_check(
			Catalog.get_definition(card_id).get("abilities", []) == [Catalog.CHUNCAN_CANNOT_ATTACK],
			"%s uses the shared non-retained cannot-attack declaration" % card_id
		)


func _test_duel_start_reveal() -> void:
	var state: State = InitialStateFactory.build({
		"player_main_card_ids": [&"HuJiaDao1", &"TuNaShu1", &"SanQinFeng1", &"ZiXiaGong1", &"CangSongYingKe1"],
		"opponent_main_card_ids": [&"ChunCanZhang2", &"HuJiaDao2", &"HuJiaDao3", &"TaiZuChangQuan", &"TuNaShu1"],
		"player_hand_shuffle_seed": -1,
		"opponent_hand_shuffle_seed": -1,
		"opening_layout_seed": -1,
		"side_deck_shuffle_seed": 901,
		"opening_owner": Rules.PLAYER_OWNER,
	})
	var hidden_blade: Dictionary = _find_hand_card(state, &"main_1_0")
	_check(_revealed_to(hidden_blade, Rules.OPPONENT_OWNER), "Duel start reveals HuJiaDao1 to its opponent")
	var all_enemy_revealed: bool = true
	for card_value: Variant in state.get_hand(Rules.OPPONENT_OWNER):
		all_enemy_revealed = all_enemy_revealed and _revealed_to(card_value as Dictionary, Rules.PLAYER_OWNER)
	_check(all_enemy_revealed, "Duel start reveals the current enemy hand to HuJiaDao1's owner")
	_check(
		(state.owner_auras_by_owner.get(Rules.PLAYER_OWNER, []) as Array).size() == 1,
		"Duel start grants HuJiaDao1's owner aura"
	)


func _test_hidden_blade_center_restriction() -> void:
	var restricted := State.new(
		Rules.empty_board(),
		[_plain(&"player_play", [1, 1, 1, 1], Rules.PLAYER_OWNER)],
		[Catalog.create_instance(&"HuJiaDao1", Rules.OPPONENT_OWNER, &"enemy_hidden_blade")],
		Rules.PLAYER_OWNER
	)
	restricted = _resolve_duel_started(restricted)
	var actions: Array = Simulator.get_legal_actions_for_owner(restricted, Rules.PLAYER_OWNER)
	_check(not _has_play_to(actions, 4), "Center play is removed while another cell is legal")
	_check(_has_play_to(actions, 0), "Non-center plays remain legal")

	var center_only_board: Array = Rules.empty_board()
	for cell: int in range(9):
		if cell == 4:
			continue
		center_only_board[cell] = _slot(
			_plain(StringName("filler_%d" % cell), [1, 1, 1, 1], Rules.OPPONENT_OWNER),
			Rules.OPPONENT_OWNER
		)
	var center_only := State.new(
		center_only_board,
		[_plain(&"only_play", [1, 1, 1, 1], Rules.PLAYER_OWNER)],
		[Catalog.create_instance(&"HuJiaDao1", Rules.OPPONENT_OWNER, &"only_hidden_blade")],
		Rules.PLAYER_OWNER
	)
	center_only = _resolve_duel_started(center_only)
	_check(_has_play_to(Simulator.get_legal_actions(center_only), 4), "Center remains legal when it is the only action")


func _test_embrace_moon_aura_and_snapshot() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(_plain(&"aura_attacker", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var aura_defender: Dictionary = _plain(&"aura_defender", [9, 9, 9, 9], Rules.PLAYER_OWNER)
	aura_defender["effect_gate"] = Catalog.EFFECT_GATE_SELF_CASTRATION
	board[1] = _slot(aura_defender, Rules.PLAYER_OWNER)
	var first_embrace: Dictionary = Catalog.create_instance(
		&"HuJiaDao2",
		Rules.PLAYER_OWNER,
		&"embrace_last"
	)
	first_embrace["powers"] = [1, 1, 1, 1]
	var second_embrace: Dictionary = Catalog.create_instance(
		&"HuJiaDao2",
		Rules.PLAYER_OWNER,
		&"embrace_second"
	)
	var state := State.new(
		board,
		[first_embrace, second_embrace],
		[],
		Rules.OPPONENT_OWNER,
		0,
		[
			_plain(&"aura_draw_first", [2, 2, 2, 2], Rules.PLAYER_OWNER),
			_plain(&"aura_draw_second", [2, 2, 2, 2], Rules.PLAYER_OWNER),
		],
		[]
	)
	state = _resolve_duel_started(state)
	var result: Dictionary = Simulator._resolve_standard_attacks(state, 4, &"aura_attacker", &"aura_test")
	_check(_count_events(result.get("events", []), &"attack_started") == 1, "Aura defense zero applies even when the recipient's own effects are gated")
	_check(_removed_has(state, Rules.PLAYER_OWNER, &"embrace_last"), "The final HuJiaDao2 loses one on all sides and is exiled")
	_check(_removed_has(state, Rules.PLAYER_OWNER, &"aura_defender"), "The already-discovered virtual reaction still exiles the defender")
	_check(
		not _find_hand_card(state, &"aura_draw_first").is_empty()
		and not _find_hand_card(state, &"aura_draw_second").is_empty(),
		"Each owner aura draws once before a virtual reaction exiles the recipient"
	)
	_check(
		_find_hand_card(state, &"embrace_second").get("powers", []) == [3, 3, 3, 3],
		"Every HuJiaDao2 aura independently reduces its exact source"
	)
	_check(
		_event_index(result.get("events", []), &"powers_changed", &"embrace_last")
		< _event_index(result.get("events", []), &"card_drawn", &"aura_draw_first"),
		"Source point loss resolves before its owner-aura draw"
	)


func _test_embrace_moon_tracks_attacked_ally_after_self_exile() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(
		_plain(&"self_exile_attacker", [9, 9, 9, 9], Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	board[1] = _slot(
		Catalog.create_instance(&"LeiZHenJian2", Rules.PLAYER_OWNER, &"self_exile_defender"),
		Rules.PLAYER_OWNER
	)
	var state := State.new(
		board,
		[Catalog.create_instance(&"HuJiaDao2", Rules.PLAYER_OWNER, &"self_exile_embrace")],
		[],
		Rules.OPPONENT_OWNER,
		1,
		[
			_plain(&"self_exile_draw_one", [2, 2, 2, 2], Rules.PLAYER_OWNER),
			_plain(&"self_exile_draw_two", [2, 2, 2, 2], Rules.PLAYER_OWNER),
		],
		[]
	)
	state = _resolve_duel_started(state)
	var result: Dictionary = Simulator._resolve_standard_attacks(
		state,
		4,
		&"self_exile_attacker",
		&"self_exile_aura_test"
	)
	_check(
		_removed_has(state, Rules.PLAYER_OWNER, &"self_exile_defender"),
		"LeiZhenJian2 exiles itself before the later owner-aura reaction"
	)
	_check(
		state.get_hand(Rules.PLAYER_OWNER).size() == 3,
		"Embrace Moon still draws after the attacked ally has left the board"
	)
	_check(
		_count_events(result.get("events", []), &"card_drawn") == 2,
		"LeiZhenJian2 and Embrace Moon each draw once"
	)


func _test_closed_door_attack_context() -> void:
	var self_flip: Dictionary = {
		"triggers": [{
			"event": Catalog.CARD_BE_ATTACKED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{
				"type": Catalog.ACTION_FLIP_SELF,
				"new_owner": Catalog.OWNER_OPPONENT_OF_CARD_CURRENT,
			}],
		}],
	}
	var board: Array = Rules.empty_board()
	board[4] = _slot(_plain(&"closed_attacker", [5, 5, 5, 5], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[1] = _slot(_plain(&"trigger_flip_target", [1, 1, 1, 1], Rules.PLAYER_OWNER, [self_flip]), Rules.PLAYER_OWNER)
	var state := State.new(
		board,
		[Catalog.create_instance(&"HuJiaDao3", Rules.PLAYER_OWNER, &"closed_door")],
		[],
		Rules.OPPONENT_OWNER
	)
	state = _resolve_duel_started(state)
	var result: Dictionary = Simulator._resolve_standard_attacks(state, 4, &"closed_attacker", &"closed_test")
	_check(_board_powers(state, &"closed_attacker") == [0, 5, 5, 5], "Trigger-chain flips do not count and only the used top side becomes zero")
	_check(_find_hand_card(state, &"closed_door").get("powers", []) == [5, 5, 5, 5], "HuJiaDao3 reveals and gains one after an enemy attack")
	_check(_count_events(result.get("events", []), &"powers_changed") == 2, "HuJiaDao3 gain and directional reset use normal power events")

	var direct_board: Array = Rules.empty_board()
	direct_board[4] = _slot(_plain(&"direct_attacker", [5, 5, 5, 5], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	direct_board[1] = _slot(_plain(&"direct_target", [1, 1, 1, 1], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var direct_state := State.new(
		direct_board,
		[Catalog.create_instance(&"HuJiaDao3", Rules.PLAYER_OWNER, &"direct_closed")],
		[],
		Rules.OPPONENT_OWNER
	)
	direct_state = _resolve_duel_started(direct_state)
	Simulator._resolve_standard_attacks(direct_state, 4, &"direct_attacker", &"direct_test")
	_check(_board_powers(direct_state, &"direct_attacker") == [5, 5, 5, 5], "An attack-caused flip prevents directional reset")


func _test_chuncan_cannot_attack_until_flipped() -> void:
	var board: Array = Rules.empty_board()
	board[1] = _slot(_plain(&"chuncan_target", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[Catalog.create_instance(&"ChunCanZhang2", Rules.PLAYER_OWNER, &"chuncan")],
			[],
			Rules.PLAYER_OWNER
		),
		Action.make_play(0, 4, &"chuncan")
	)
	var state: State = transition.get("state") as State
	_check(_count_events(transition.get("events", []), &"attack_started") == 0, "ChunCan blocks its summon attack")
	_check(int((state.board[1] as Dictionary).get("owner", 0)) == Rules.OPPONENT_OWNER, "Blocked summon attack does not flip its target")
	Simulator.resolve_non_attack_flip(state, &"chuncan", Rules.OPPONENT_OWNER)
	_check(((state.board[4] as Dictionary).get("card", {}) as Dictionary).get("active_abilities", []).is_empty(), "ChunCan loses the non-retained restriction when flipped")


func _test_owner_aura_expires_at_any_turn_end() -> void:
	var source: Dictionary = Catalog.create_instance(
		&"HuJiaDao1",
		Rules.PLAYER_OWNER,
		&"expiring_hidden_blade"
	)
	var state := _resolve_duel_started(State.new(
		Rules.empty_board(),
		[source],
		[],
		Rules.PLAYER_OWNER
	))
	var current_source: Dictionary = _find_hand_card(state, &"expiring_hidden_blade")
	state.get_hand(Rules.PLAYER_OWNER).erase(current_source)
	(state.discard_piles[Rules.PLAYER_OWNER] as Array).append(current_source)
	_check(
		(state.owner_auras_by_owner[Rules.PLAYER_OWNER] as Array).size() == 1,
		"Leaving hand does not remove an owner aura immediately"
	)
	var ended: Dictionary = NativeRules.resolve_event(
		state,
		Catalog.TRIGGER_END_OWNER_TURN,
		{"turn_owner_id": Rules.OPPONENT_OWNER}
	)
	_check(bool(ended.get("valid", false)), "Either side's turn end can resolve aura expiry")
	_check(
		(state.owner_auras_by_owner[Rules.PLAYER_OWNER] as Array).is_empty(),
		"Owner aura expires when its exact source is no longer in hand"
	)


func _plain(instance_id: StringName, raw_powers: Array, owner_id: int, abilities: Array = []) -> Dictionary:
	var powers: Array[int] = []
	for power_value: Variant in raw_powers:
		powers.append(int(power_value))
	var card: Dictionary = Rules.make_card(String(instance_id), String(instance_id), powers, abilities, owner_id, instance_id)
	card["instance_id"] = instance_id
	return card


func _resolve_duel_started(state: State) -> State:
	var transition: Dictionary = NativeRules.resolve_event(state, Catalog.TRIGGER_DUEL_STARTED, {})
	_check(
		bool(transition.get("valid", false)),
		"Duel-start owner-aura setup is supported: %s" % transition.get("reason", "")
	)
	return transition.get("state") as State


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _has_play_to(actions: Array, cell: int) -> bool:
	for action_value: Variant in actions:
		if action_value is Action and action_value.action_type == Action.TYPE_PLAY and action_value.target_index == cell:
			return true
	return false


func _revealed_to(card: Dictionary, owner_id: int) -> bool:
	return owner_id in (card.get("revealed_to_owner_ids", []) as Array)


func _find_hand_card(state: State, instance_id: StringName) -> Dictionary:
	for owner_id: int in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		for card_value: Variant in state.get_hand(owner_id):
			if StringName((card_value as Dictionary).get("instance_id", &"")) == instance_id:
				return card_value as Dictionary
	return {}


func _board_powers(state: State, instance_id: StringName) -> Array:
	for slot_value: Variant in state.board:
		if not slot_value is Dictionary:
			continue
		var card: Dictionary = (slot_value as Dictionary).get("card", {})
		if StringName(card.get("instance_id", &"")) == instance_id:
			return (card.get("powers", []) as Array).duplicate()
	return []


func _removed_has(state: State, owner_id: int, instance_id: StringName) -> bool:
	for card_value: Variant in state.removed_cards.get(owner_id, []):
		if StringName((card_value as Dictionary).get("instance_id", &"")) == instance_id:
			return true
	return false


func _count_events(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for event_value: Variant in events:
		if event_value is Dictionary and StringName((event_value as Dictionary).get("type", &"")) == event_type:
			count += 1
	return count


func _event_index(events: Array, event_type: StringName, instance_id: StringName) -> int:
	for index: int in range(events.size()):
		var event_value: Variant = events[index]
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
			and StringName((event_value as Dictionary).get("instance_id", &"")) == instance_id
		):
			return index
	return -1


func _finish() -> void:
	if _failures == 0:
		print("HUJIA_CHUNCAN_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("HUJIA_CHUNCAN_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
