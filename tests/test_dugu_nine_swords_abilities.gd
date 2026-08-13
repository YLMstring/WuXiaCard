extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Action = preload("res://scripts/duel_action.gd")
const Revelation = preload("res://scripts/duel_revelation.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_declarations()
	_test_state_copy_and_key()
	_test_no_form_exiles_and_draws_in_order()
	_test_no_form_uses_current_owner_and_snapshot_targets()
	_test_anticipate_returns_previous_plays()
	_test_anticipate_full_hand_and_missing_target_continue()
	_test_break_all_suppresses_next_non_heart()
	_test_break_all_skips_heart_methods()
	_test_break_all_stacks_one_layer_per_card()
	_test_break_all_consumes_for_abilityless_card()
	_finish()


func _test_catalog_declarations() -> void:
	_check(
		Catalog.CONDITION_SELECTED_CARD_IS_PREVIOUS_HAND_PLAY
		in Catalog.KNOWN_SELECTOR_CONDITIONS,
		"Previous-hand-play selection is registered"
	)
	_check(
		Catalog.ACTION_ADD_PENDING_NON_RETAINED_SUPPRESSION in Catalog.KNOWN_ACTIONS,
		"Pending permanent suppression is registered"
	)
	var expected_by_card: Dictionary = {
		&"DuGu9Jian1": [Catalog.DUGU_NO_FORM],
		&"DuGu9Jian2": [Catalog.DUGU_ANTICIPATE],
		&"DuGu9Jian3": [Catalog.DUGU_BREAK_ALL],
	}
	for card_id: StringName in [&"DuGu9Jian1", &"DuGu9Jian2", &"DuGu9Jian3"]:
		var abilities: Array = Catalog.get_definition(card_id).get("abilities", [])
		_check(
			abilities == (expected_by_card[card_id] as Array),
			"%s declaration exactly matches the approved design" % card_id
		)
		if abilities.size() != 1:
			continue
		var ability: Dictionary = abilities[0]
		_check(
			not ability.has("retained_on_flip"),
			"%s relies on default non-retention" % card_id
		)
		var triggers: Array = ability.get("triggers", [])
		_check(
			triggers.size() == 1
			and StringName((triggers[0] as Dictionary).get("event", &""))
			== Catalog.TRIGGER_CARD_BEFORE_SUMMONED,
			"%s triggers before its own summon" % card_id
		)
	var invalid_condition: Dictionary = Catalog.DUGU_ANTICIPATE.duplicate(true)
	invalid_condition["triggers"][0]["actions"][2]["selector"]["conditions"][0]["played_by"] = &"unknown"
	_check(
		not Catalog.validate_ability(invalid_condition).is_empty(),
		"Previous-play conditions reject unknown owner references"
	)
	var invalid_action: Dictionary = Catalog.DUGU_BREAK_ALL.duplicate(true)
	invalid_action["triggers"][0]["actions"][3]["amount"] = 0
	_check(
		not Catalog.validate_ability(invalid_action).is_empty(),
		"Pending suppression rejects non-positive amounts"
	)


func _test_state_copy_and_key() -> void:
	var state := State.new(Rules.empty_board())
	state.last_hand_play_by_owner[Rules.PLAYER_OWNER] = {
		"played_by_owner_id": Rules.PLAYER_OWNER,
		"card_id": &"CangSongYingKe1",
		"instance_id": &"history_one",
	}
	state.pending_non_retained_suppression_by_owner[Rules.OPPONENT_OWNER] = 2
	var copied: State = state.duplicate_state() as State
	copied.last_hand_play_by_owner[Rules.PLAYER_OWNER]["instance_id"] = &"history_two"
	copied.pending_non_retained_suppression_by_owner[Rules.OPPONENT_OWNER] = 1
	_check(
		StringName(state.last_hand_play_by_owner[Rules.PLAYER_OWNER]["instance_id"])
		== &"history_one",
		"Hand-play history is deeply copied"
	)
	_check(
		int(state.pending_non_retained_suppression_by_owner[Rules.OPPONENT_OWNER]) == 2,
		"Pending suppression counts are deeply copied"
	)
	_check(StateKey.build(state) != StateKey.build(copied), "State keys encode Dugu state")


func _test_no_form_exiles_and_draws_in_order() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(_catalog_card(&"CangSongYingKe1", Rules.PLAYER_OWNER, &"untouched"), Rules.PLAYER_OWNER)
	board[1] = _slot(_catalog_card(&"CangSongYingKe2", Rules.PLAYER_OWNER, &"north"), Rules.PLAYER_OWNER)
	board[3] = _slot(_catalog_card(&"TuNaShu1", Rules.OPPONENT_OWNER, &"west"), Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[_catalog_card(&"DuGu9Jian1", Rules.PLAYER_OWNER, &"no_form")],
			[],
			Rules.PLAYER_OWNER,
			0,
			[
				_catalog_card(&"CangSongYingKe3", Rules.PLAYER_OWNER, &"draw_self"),
				_catalog_card(&"CangSongYingKe4", Rules.PLAYER_OWNER, &"draw_north"),
			],
			[_catalog_card(&"TuNaShu2", Rules.OPPONENT_OWNER, &"draw_west")]
		),
		Action.make_play(0, 4, &"no_form")
	)
	var next_state: State = transition.get("state") as State
	_check(bool(transition.get("valid", false)), "No Form is a legal hand play")
	_check(
		_instance_at(next_state, 0) == &"untouched"
		and next_state.board[1] == null
		and next_state.board[3] == null
		and next_state.board[4] == null,
		"No Form removes itself and only its orthogonal neighbors"
	)
	_check(
		_relevant_event_types(transition.get("events", []), [&"card_exiled", &"card_drawn"])
		== [
			&"card_exiled", &"card_drawn",
			&"card_exiled", &"card_drawn",
			&"card_exiled", &"card_drawn",
		],
		"Each removal is immediately followed by its owner's draw"
	)
	_check(
		next_state.get_hand(Rules.PLAYER_OWNER).size() == 2
		and next_state.get_hand(Rules.OPPONENT_OWNER).size() == 1,
		"No Form draws for each removed card's current owner"
	)


func _test_no_form_uses_current_owner_and_snapshot_targets() -> void:
	var board: Array = Rules.empty_board()
	board[1] = _slot(
		_catalog_card(&"CangSongYingKe1", Rules.OPPONENT_OWNER, &"flipped_neighbor"),
		Rules.PLAYER_OWNER
	)
	var state := State.new(
		board,
		[_catalog_card(&"DuGu9Jian1", Rules.PLAYER_OWNER, &"no_form_owner")],
		[],
		Rules.PLAYER_OWNER,
		0,
		[
			_catalog_card(&"CangSongYingKe2", Rules.PLAYER_OWNER, &"owner_draw_one"),
			_catalog_card(&"CangSongYingKe3", Rules.PLAYER_OWNER, &"owner_draw_two"),
		]
	)
	var transition: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, 4, &"no_form_owner")
	)
	var next_state: State = transition.get("state") as State
	_check(
		next_state.get_hand(Rules.PLAYER_OWNER).size() == 2
		and next_state.get_hand(Rules.OPPONENT_OWNER).is_empty(),
		"A flipped neighbor draws for its current owner"
	)
	_check(
		(state.removed_cards[Rules.OPPONENT_OWNER] as Array).is_empty()
		and (next_state.removed_cards[Rules.OPPONENT_OWNER] as Array).size() == 1,
		"The flipped neighbor enters its original owner's removed zone"
	)


func _test_anticipate_returns_previous_plays() -> void:
	var board: Array = Rules.empty_board()
	board[1] = _slot(
		_catalog_card(&"CangSongYingKe1", Rules.OPPONENT_OWNER, &"enemy_previous"),
		Rules.PLAYER_OWNER
	)
	board[3] = _slot(
		_catalog_card(&"CangSongYingKe2", Rules.PLAYER_OWNER, &"own_previous"),
		Rules.PLAYER_OWNER
	)
	var state := State.new(
		board,
		[_catalog_card(&"DuGu9Jian2", Rules.PLAYER_OWNER, &"anticipate")],
		[],
		Rules.PLAYER_OWNER,
		0,
		[_catalog_card(&"TuNaShu1", Rules.PLAYER_OWNER, &"anticipate_draw")]
	)
	state.last_hand_play_by_owner = {
		Rules.PLAYER_OWNER: {
			"played_by_owner_id": Rules.PLAYER_OWNER,
			"card_id": &"CangSongYingKe2",
			"instance_id": &"own_previous",
		},
		Rules.OPPONENT_OWNER: {
			"played_by_owner_id": Rules.OPPONENT_OWNER,
			"card_id": &"CangSongYingKe1",
			"instance_id": &"enemy_previous",
		},
	}
	var transition: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, 4, &"anticipate")
	)
	var next_state: State = transition.get("state") as State
	_check(
		next_state.board[1] == null and next_state.board[3] == null and next_state.board[4] == null,
		"Anticipate removes itself and returns both previous hand plays"
	)
	_check(
		next_state.get_hand(Rules.OPPONENT_OWNER).size() == 1
		and StringName((next_state.get_hand(Rules.OPPONENT_OWNER)[0] as Dictionary).get("card_id", &""))
		== &"CangSongYingKe1",
		"A flipped previous play returns to the player who played it"
	)
	_check(
		_relevant_event_types(
			transition.get("events", []),
			[&"card_exiled", &"card_drawn", &"card_returned_to_hand", &"extra_card_play_granted"]
		) == [
			&"card_exiled",
			&"card_drawn",
			&"card_returned_to_hand",
			&"card_returned_to_hand",
			&"extra_card_play_granted",
		],
		"Anticipate resolves opponent return, own return, then extra play"
	)
	_check(
		next_state.extra_card_plays_remaining == 1
		and next_state.active_player == Rules.PLAYER_OWNER,
		"Anticipate grants a usable extra hand play"
	)
	_check(
		StringName(next_state.last_hand_play_by_owner[Rules.PLAYER_OWNER].get("instance_id", &""))
		== &"anticipate",
		"The successful Anticipate play becomes the new history only after resolution"
	)


func _test_anticipate_full_hand_and_missing_target_continue() -> void:
	var previous_enemy: Dictionary = _catalog_card(
		&"CangSongYingKe1",
		Rules.OPPONENT_OWNER,
		&"full_hand_target"
	)
	var board: Array = Rules.empty_board()
	board[1] = _slot(previous_enemy, Rules.OPPONENT_OWNER)
	var opponent_hand: Array = []
	for index: int in range(5):
		opponent_hand.append(_catalog_card(
			&"TuNaShu1",
			Rules.OPPONENT_OWNER,
			StringName("full_hand_%d" % index)
		))
	var state := State.new(
		board,
		[_catalog_card(&"DuGu9Jian2", Rules.PLAYER_OWNER, &"anticipate_full")],
		opponent_hand,
		Rules.PLAYER_OWNER,
		0,
		[_catalog_card(&"TuNaShu2", Rules.PLAYER_OWNER, &"full_draw")]
	)
	state.last_hand_play_by_owner = {
		Rules.PLAYER_OWNER: {
			"played_by_owner_id": Rules.PLAYER_OWNER,
			"card_id": &"CangSongYingKe2",
			"instance_id": &"missing_own_target",
		},
		Rules.OPPONENT_OWNER: {
			"played_by_owner_id": Rules.OPPONENT_OWNER,
			"card_id": &"CangSongYingKe1",
			"instance_id": &"full_hand_target",
		},
	}
	var transition: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, 4, &"anticipate_full")
	)
	var next_state: State = transition.get("state") as State
	_check(
		next_state.board[1] == null
		and next_state.get_hand(Rules.OPPONENT_OWNER).size() == 5
		and (next_state.removed_cards[Rules.OPPONENT_OWNER] as Array).size() == 1,
		"A full recipient hand exiles the previous play"
	)
	_check(
		next_state.extra_card_plays_remaining == 1,
		"Missing return targets do not prevent the later extra play"
	)


func _test_break_all_suppresses_next_non_heart() -> void:
	var non_retained: Dictionary = _before_summon_ability(
		[{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1}],
		false
	)
	var retained: Dictionary = _before_summon_ability(
		[{"type": Catalog.ACTION_GAIN_KI, "amount": 1}],
		true
	)
	var target: Dictionary = _catalog_card(&"CangSongYingKe1", Rules.OPPONENT_OWNER, &"suppressed")
	target["active_abilities"] = [non_retained, retained]
	var first: Dictionary = Simulator.apply_action(
		State.new(
			Rules.empty_board(),
			[_catalog_card(&"DuGu9Jian3", Rules.PLAYER_OWNER, &"break_all")],
			[target],
			Rules.PLAYER_OWNER,
			0,
			[_catalog_card(&"TuNaShu1", Rules.PLAYER_OWNER, &"break_draw")],
			[_catalog_card(&"TuNaShu2", Rules.OPPONENT_OWNER, &"blocked_draw")]
		),
		Action.make_play(0, 4, &"break_all")
	)
	var prepared: State = first.get("state") as State
	_check(
		int(prepared.pending_non_retained_suppression_by_owner[Rules.OPPONENT_OWNER]) == 1,
		"Break All adds one persistent suppression layer"
	)
	_check(
		not Revelation.is_revealed_to(
			prepared.get_hand(Rules.OPPONENT_OWNER)[0],
			Rules.PLAYER_OWNER
		),
		"Break All does not reveal the opponent hand"
	)
	var extra_play: Dictionary = Simulator.apply_action(
		prepared,
		Action.make_play(0, 8, &"break_draw")
	)
	prepared = extra_play.get("state") as State
	var second: Dictionary = Simulator.apply_action(
		prepared,
		Action.make_play(0, 0, &"suppressed")
	)
	var resolved: State = second.get("state") as State
	var runtime: Dictionary = (resolved.board[0] as Dictionary).get("card", {})
	_check(
		int(resolved.pending_non_retained_suppression_by_owner[Rules.OPPONENT_OWNER]) == 0
		and (runtime.get("active_abilities", []) as Array).size() == 1
		and bool(((runtime.get("active_abilities", []) as Array)[0] as Dictionary).get("retained_on_flip", false)),
		"The next non-heart play permanently loses only non-retained abilities"
	)
	_check(int(runtime.get("ki", 0)) == 1, "A retained before-summon ability still resolves")
	var relevant: Array[StringName] = _relevant_event_types(
		second.get("events", []),
		[&"non_retained_suppression_consumed", &"ability_lost", &"ability_triggered"]
	)
	_check(
		relevant.slice(0, 3) == [
			&"non_retained_suppression_consumed",
			&"ability_lost",
			&"ability_triggered",
		],
		"Suppression is consumed and abilities are lost before trigger discovery"
	)


func _test_break_all_skips_heart_methods() -> void:
	var heart: Dictionary = _catalog_card(&"TuNaShu1", Rules.OPPONENT_OWNER, &"heart")
	heart["active_abilities"] = [_before_summon_ability(
		[{"type": Catalog.ACTION_GAIN_KI, "amount": 1}],
		false
	)]
	var state := State.new(Rules.empty_board(), [], [heart], Rules.OPPONENT_OWNER)
	state.pending_non_retained_suppression_by_owner[Rules.OPPONENT_OWNER] = 1
	var transition: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, 4, &"heart")
	)
	var next_state: State = transition.get("state") as State
	var runtime: Dictionary = (next_state.board[4] as Dictionary).get("card", {})
	_check(
		int(next_state.pending_non_retained_suppression_by_owner[Rules.OPPONENT_OWNER]) == 1
		and int(runtime.get("ki", 0)) == 1,
		"Heart methods neither consume nor receive pending suppression"
	)


func _test_break_all_stacks_one_layer_per_card() -> void:
	var first_card: Dictionary = _catalog_card(
		&"CangSongYingKe1",
		Rules.PLAYER_OWNER,
		&"stack_first"
	)
	var second_card: Dictionary = _catalog_card(
		&"CangSongYingKe2",
		Rules.PLAYER_OWNER,
		&"stack_second"
	)
	first_card["active_abilities"] = [_before_summon_ability(
		[{"type": Catalog.ACTION_GAIN_KI, "amount": 1}],
		false
	)]
	second_card["active_abilities"] = [_before_summon_ability(
		[{"type": Catalog.ACTION_GAIN_KI, "amount": 1}],
		false
	)]
	var state := State.new(
		Rules.empty_board(),
		[first_card, second_card],
		[],
		Rules.PLAYER_OWNER
	)
	state.pending_non_retained_suppression_by_owner[Rules.PLAYER_OWNER] = 2
	state.extra_card_plays_remaining = 1
	var first_transition: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, 0, &"stack_first")
	)
	var after_first: State = first_transition.get("state") as State
	_check(
		int(after_first.pending_non_retained_suppression_by_owner[Rules.PLAYER_OWNER]) == 1
		and int(((after_first.board[0] as Dictionary).get("card", {}) as Dictionary).get("ki", 0)) == 0,
		"One non-heart play consumes exactly one suppression layer"
	)
	var second_transition: Dictionary = Simulator.apply_action(
		after_first,
		Action.make_play(0, 8, &"stack_second")
	)
	var after_second: State = second_transition.get("state") as State
	_check(
		int(after_second.pending_non_retained_suppression_by_owner[Rules.PLAYER_OWNER]) == 0
		and int(((after_second.board[8] as Dictionary).get("card", {}) as Dictionary).get("ki", 0)) == 0,
		"The next non-heart play consumes the next queued layer"
	)


func _test_break_all_consumes_for_abilityless_card() -> void:
	var card: Dictionary = _catalog_card(
		&"CangSongYingKe1",
		Rules.PLAYER_OWNER,
		&"abilityless_target"
	)
	card["active_abilities"] = []
	var state := State.new(Rules.empty_board(), [card], [], Rules.PLAYER_OWNER)
	state.pending_non_retained_suppression_by_owner[Rules.PLAYER_OWNER] = 1
	var transition: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, 4, &"abilityless_target")
	)
	var next_state: State = transition.get("state") as State
	_check(
		int(next_state.pending_non_retained_suppression_by_owner[Rules.PLAYER_OWNER]) == 0
		and _relevant_event_types(
			transition.get("events", []),
			[&"non_retained_suppression_consumed", &"ability_lost"]
		) == [&"non_retained_suppression_consumed"],
		"An abilityless non-heart card still consumes one layer without fake loss events"
	)
func _before_summon_ability(actions: Array, retained: bool) -> Dictionary:
	return {
		"retained_on_flip": retained,
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_BEFORE_SUMMONED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": actions.duplicate(true),
		}],
	}


func _catalog_card(card_id: StringName, owner_id: int, instance_id: StringName) -> Dictionary:
	return Catalog.create_instance(card_id, owner_id, instance_id)


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _instance_at(state: State, cell: int) -> StringName:
	if state == null or cell < 0 or cell >= state.board.size() or state.board[cell] == null:
		return &""
	return StringName(
		(((state.board[cell] as Dictionary).get("card", {}) as Dictionary).get(
			"instance_id",
			&""
		))
	)


func _relevant_event_types(events: Array, allowed: Array[StringName]) -> Array[StringName]:
	var types: Array[StringName] = []
	for event_value: Variant in events:
		if not event_value is Dictionary:
			continue
		var event_type := StringName((event_value as Dictionary).get("type", &""))
		if event_type in allowed:
			types.append(event_type)
	return types


func _finish() -> void:
	if _failures == 0:
		print("DUGU_NINE_SWORDS_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"DUGU_NINE_SWORDS_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
