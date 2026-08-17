extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Abilities = preload("res://scripts/duel_abilities.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_vocabulary_and_catalog_declarations()
	_test_leizhen_draws_before_board_exile()
	_test_flipped_leizhen_loses_exile_draw()
	_test_huzhua_three_reacts_only_to_other_real_ally_attack()
	_test_huzhua_four_intercepts_each_drawn_card()
	_test_hand_leizhen_does_not_trigger_when_intercepted()
	_test_yizidianjian_uses_all_target_policy_until_flipped()
	_finish()


func _test_vocabulary_and_catalog_declarations() -> void:
	_check(Catalog.CARD_BEFORE_EXILED in Catalog.KNOWN_TRIGGER_EVENTS, "Before-exile events are registered")
	_check(Catalog.CARD_AFTER_DRAWN in Catalog.KNOWN_TRIGGER_EVENTS, "After-draw events are registered")
	_check(Catalog.ACTION_EXILE_CARD in Catalog.KNOWN_ACTIONS, "Generic explicit exile actions are registered")
	_check(
		Catalog.CONDITION_ATTACKER_CARD_IS_OTHER_ALLY in Catalog.KNOWN_TRIGGER_CONDITIONS,
		"Other-allied-attacker conditions are registered"
	)
	_check(
		Catalog.CONDITION_DRAWN_CARD_IS_ENEMY in Catalog.KNOWN_TRIGGER_CONDITIONS,
		"Enemy-drawn-card conditions are registered"
	)
	_check(Catalog.validate_catalog().is_empty(), "The completed family declarations pass catalog validation")
	_check(
		(Catalog.get_definition(&"LeiZHenJian2").get("abilities", []) as Array).size() == 3,
		"LeiZhen tier two declares defense, retained self-exile, and exile draw"
	)
	_check(
		(Catalog.get_definition(&"LeiZHenJian3").get("abilities", []) as Array).size() == 4,
		"YiZiDianJian also declares the enemy all-target modifier"
	)
	_check(
		(Catalog.get_definition(&"HuZhuaJueHuSHou3").get("abilities", []) as Array).size() == 2,
		"HuZhua tier three separates retained target exile from its attack reaction"
	)
	_check(
		(Catalog.get_definition(&"HuZhuaJueHuSHou4").get("abilities", []) as Array).size() == 3,
		"HuZhua tier four adds a retained draw interception"
	)


func _test_leizhen_draws_before_board_exile() -> void:
	var board: Array = Rules.empty_board()
	board[1] = _slot(
		Catalog.create_instance(&"LeiZHenJian2", Rules.PLAYER_OWNER, &"leizhen_draw"),
		Rules.PLAYER_OWNER
	)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[_plain(&"leizhen_draw_card", [1, 1, 1, 1], Rules.PLAYER_OWNER)],
			[_plain(&"leizhen_attacker", [9, 9, 9, 9], Rules.OPPONENT_OWNER)],
			Rules.OPPONENT_OWNER,
			0,
			[_plain(&"leizhen_replacement", [2, 2, 2, 2], Rules.PLAYER_OWNER)],
			[]
		),
		Action.make_play(0, 4, &"leizhen_attacker")
	)
	var next_state: State = transition.get("state") as State
	var events: Array = transition.get("events", [])
	_check(next_state.board[1] == null, "Attacked LeiZhen removes itself")
	_check(
		_find_hand_instance(next_state.get_hand(Rules.PLAYER_OWNER), &"leizhen_replacement") >= 0,
		"Board LeiZhen draws for its current owner before exile"
	)
	_check(
		_event_index(events, &"card_drawn", &"leizhen_replacement")
		< _event_index(events, &"card_exiled", &"leizhen_draw"),
		"LeiZhen draw presentation precedes its exile event"
	)


func _test_flipped_leizhen_loses_exile_draw() -> void:
	var board: Array = Rules.empty_board()
	board[1] = _slot(
		Catalog.create_instance(&"LeiZHenJian2", Rules.PLAYER_OWNER, &"flipped_leizhen"),
		Rules.PLAYER_OWNER
	)
	var state := State.new(
		board,
		[_plain(&"flip_attacker", [9, 9, 9, 9], Rules.PLAYER_OWNER)],
		[],
		Rules.PLAYER_OWNER,
		0,
		[],
		[_plain(&"forbidden_draw", [1, 1, 1, 1], Rules.OPPONENT_OWNER)]
	)
	Simulator.resolve_non_attack_flip(state, &"flipped_leizhen", Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, 4, &"flip_attacker")
	)
	var next_state: State = transition.get("state") as State
	_check(next_state.board[1] == null, "Retained LeiZhen self-exile survives its ownership flip")
	_check(
		_count_events(transition.get("events", []), &"card_drawn") == 0,
		"Flipped LeiZhen has lost its non-retained exile draw"
	)


func _test_huzhua_three_reacts_only_to_other_real_ally_attack() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(_plain(&"huzhua_reaction_target", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[1] = _slot(_plain(&"ally_attack_target", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[3] = _slot(
		Catalog.create_instance(&"HuZhuaJueHuSHou3", Rules.PLAYER_OWNER, &"huzhua_three"),
		Rules.PLAYER_OWNER
	)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[_plain(&"real_ally_attacker", [9, 9, 9, 9], Rules.PLAYER_OWNER)],
			[],
			Rules.PLAYER_OWNER
		),
		Action.make_play(0, 4, &"real_ally_attacker")
	)
	var next_state: State = transition.get("state") as State
	_check(
		next_state.board[0] == null
		and int((next_state.board[1] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER,
		"Another ally's real attack makes HuZhua attack and exile its own target"
	)
	_check(
		_count_events(transition.get("events", []), &"attack_started") == 2,
		"The allied attack and HuZhua reaction each start exactly once"
	)

	var weak_board: Array = Rules.empty_board()
	weak_board[0] = _slot(_plain(&"untouched_huzhua_target", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	weak_board[1] = _slot(_plain(&"too_strong_for_ally", [9, 9, 9, 9], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	weak_board[3] = _slot(
		Catalog.create_instance(&"HuZhuaJueHuSHou3", Rules.PLAYER_OWNER, &"idle_huzhua"),
		Rules.PLAYER_OWNER
	)
	var weak_transition: Dictionary = Simulator.apply_action(
		State.new(
			weak_board,
			[_plain(&"weak_ally_attacker", [1, 1, 1, 1], Rules.PLAYER_OWNER)],
			[],
			Rules.PLAYER_OWNER
		),
		Action.make_play(0, 4, &"weak_ally_attacker")
	)
	_check(
		_count_events(weak_transition.get("events", []), &"attack_started") == 0
		and (weak_transition.get("state") as State).board[0] != null,
		"A failed ally attack produces no HuZhua reaction"
	)


func _test_huzhua_four_intercepts_each_drawn_card() -> void:
	var board: Array = Rules.empty_board()
	board[8] = _slot(
		Catalog.create_instance(&"HuZhuaJueHuSHou4", Rules.PLAYER_OWNER, &"draw_hunter"),
		Rules.PLAYER_OWNER
	)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[],
			[Catalog.create_instance(&"TuNaShu2", Rules.OPPONENT_OWNER, &"double_draw")],
			Rules.OPPONENT_OWNER,
			0,
			[],
			[
				_plain(&"intercept_one", [1, 1, 1, 1], Rules.OPPONENT_OWNER),
				_plain(&"intercept_two", [2, 2, 2, 2], Rules.OPPONENT_OWNER),
			]
		),
		Action.make_play(0, 4, &"double_draw")
	)
	var next_state: State = transition.get("state") as State
	_check(next_state.get_hand(Rules.OPPONENT_OWNER).is_empty(), "HuZhua removes each drawn enemy card")
	_check(
		(next_state.removed_cards[Rules.OPPONENT_OWNER] as Array).size() == 2,
		"Each intercepted exact instance enters its original owner's removed zone"
	)
	_check(
		_relevant_event_types_after_first_draw(transition.get("events", [])) == [
			&"card_drawn", &"ability_triggered", &"card_exiled",
			&"card_drawn", &"ability_triggered", &"card_exiled",
		],
		"Multi-draw resolves draw, HuZhua, exile before the next draw"
	)
	for draw_event: Dictionary in _events_of_type(transition.get("events", []), &"card_drawn"):
		_check(not (draw_event.get("card", {}) as Dictionary).is_empty(), "Draw events preserve card data for transient presentation")


func _test_hand_leizhen_does_not_trigger_when_intercepted() -> void:
	var board: Array = Rules.empty_board()
	board[8] = _slot(
		Catalog.create_instance(&"HuZhuaJueHuSHou4", Rules.PLAYER_OWNER, &"hand_rule_hunter"),
		Rules.PLAYER_OWNER
	)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[],
			[Catalog.create_instance(&"TuNaShu1", Rules.OPPONENT_OWNER, &"single_draw")],
			Rules.OPPONENT_OWNER,
			0,
			[],
			[Catalog.create_instance(&"LeiZHenJian2", Rules.OPPONENT_OWNER, &"hand_leizhen")]
		),
		Action.make_play(0, 4, &"single_draw")
	)
	_check(
		_count_events(transition.get("events", []), &"card_drawn") == 1,
		"An intercepted hand LeiZhen does not trigger its own replacement draw"
	)


func _test_yizidianjian_uses_all_target_policy_until_flipped() -> void:
	var board: Array = Rules.empty_board()
	board[8] = _slot(
		Catalog.create_instance(&"LeiZHenJian3", Rules.PLAYER_OWNER, &"yizi_policy"),
		Rules.PLAYER_OWNER
	)
	board[1] = _slot(_plain(&"enemy_old_ally", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[3] = _slot(_plain(&"enemy_normal_target", [1, 1, 1, 1], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[],
			[_plain(&"yizi_enemy_attacker", [9, 9, 9, 9], Rules.OPPONENT_OWNER)],
			Rules.OPPONENT_OWNER
		),
		Action.make_play(0, 4, &"yizi_enemy_attacker")
	)
	var next_state: State = transition.get("state") as State
	_check(
		int((next_state.board[1] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER
		and int((next_state.board[3] as Dictionary).get("owner", 0)) == Rules.OPPONENT_OWNER,
		"YiZi makes an enemy attack both owners with the generic capture policy"
	)

	var flipped_board: Array = Rules.empty_board()
	flipped_board[8] = _slot(
		Catalog.create_instance(&"LeiZHenJian3", Rules.OPPONENT_OWNER, &"flipped_yizi"),
		Rules.PLAYER_OWNER
	)
	var flipped_state := State.new(flipped_board)
	Simulator.resolve_non_attack_flip(flipped_state, &"flipped_yizi", Rules.OPPONENT_OWNER)
	var flipped_card: Dictionary = (flipped_state.board[8] as Dictionary).get("card", {})
	_check(
		not Abilities.has_modifier(flipped_card, Catalog.MODIFIER_ENEMY_ATTACKS_ALL),
		"YiZi loses its non-retained all-target policy after flipping"
	)


func _plain(instance_id: StringName, powers: Array[int], owner_id: int) -> Dictionary:
	var card: Dictionary = Rules.make_card(
		String(instance_id), String(instance_id), powers, [], owner_id, instance_id
	)
	card["instance_id"] = instance_id
	return card


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _find_hand_instance(hand: Array, instance_id: StringName) -> int:
	for index: int in range(hand.size()):
		var card_value: Variant = hand[index]
		if card_value is Dictionary and StringName((card_value as Dictionary).get("instance_id", &"")) == instance_id:
			return index
	return -1


func _event_index(events: Array, event_type: StringName, instance_id: StringName) -> int:
	for index: int in range(events.size()):
		var event_value: Variant = events[index]
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
			and StringName((event_value as Dictionary).get("instance_id", &"")) == instance_id
		):
			return index
	return 9999


func _count_events(events: Array, event_type: StringName) -> int:
	return _events_of_type(events, event_type).size()


func _events_of_type(events: Array, event_type: StringName) -> Array[Dictionary]:
	var matching: Array[Dictionary] = []
	for event_value: Variant in events:
		if event_value is Dictionary and StringName((event_value as Dictionary).get("type", &"")) == event_type:
			matching.append(event_value as Dictionary)
	return matching


func _relevant_event_types_after_first_draw(events: Array) -> Array[StringName]:
	var relevant: Array[StringName] = []
	var found_first_draw: bool = false
	for event_value: Variant in events:
		if not event_value is Dictionary:
			continue
		var event_type := StringName((event_value as Dictionary).get("type", &""))
		if event_type == &"card_drawn":
			found_first_draw = true
		if not found_first_draw:
			continue
		if event_type in [&"card_drawn", &"ability_triggered", &"card_exiled"]:
			relevant.append(event_type)
	return relevant


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)


func _finish() -> void:
	if _failures == 0:
		print("LEIZHEN_HUZHUA_ABILITY_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"LEIZHEN_HUZHUA_ABILITY_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)
