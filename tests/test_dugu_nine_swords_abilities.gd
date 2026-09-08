extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Action = preload("res://scripts/duel_action.gd")
const Revelation = preload("res://scripts/duel_revelation.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_declarations()
	_test_state_copy_and_key()
	_test_no_form_reveals_and_exiles_in_order()
	_test_anticipate_suppresses_next_card()
	_test_anticipate_includes_heart_methods()
	_test_pending_suppression_stacks_and_consumes_for_abilityless_cards()
	_test_break_all_transforms_enemies_and_preserves_runtime_identity()
	_finish()


func _test_catalog_declarations() -> void:
	_check(
		Catalog.ACTION_ADD_PENDING_NON_RETAINED_SUPPRESSION in Catalog.KNOWN_ACTIONS
		and Catalog.ACTION_PERMANENTLY_REMOVE_NON_RETAINED_ABILITIES in Catalog.KNOWN_ACTIONS,
		"Both permanent-suppression actions are registered"
	)
	var expected_by_card: Dictionary = {
		&"DuGu9Jian1": [Catalog.DUGU_NO_FORM],
		&"DuGu9Jian2": [Catalog.DUGU_ANTICIPATE],
		&"DuGu9Jian3": [Catalog.DUGU_BREAK_ALL],
	}
	for card_id: StringName in expected_by_card:
		var abilities: Array = Catalog.get_definition(card_id).get("abilities", [])
		_check(abilities == (expected_by_card[card_id] as Array), "%s uses its approved declaration" % card_id)
		_check(
			abilities.size() == 1
			and StringName((((abilities[0] as Dictionary).get("triggers", []) as Array)[0] as Dictionary).get("event", &""))
			== Catalog.TRIGGER_CARD_BEFORE_SUMMONED,
			"%s triggers before its own summon" % card_id
		)
	_check(Catalog.validate_catalog().is_empty(), "Dugu declarations pass catalog validation")


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
		StringName(state.last_hand_play_by_owner[Rules.PLAYER_OWNER]["instance_id"]) == &"history_one",
		"Hand-play history is deeply copied"
	)
	_check(int(state.pending_non_retained_suppression_by_owner[Rules.OPPONENT_OWNER]) == 2, "Pending suppression counts are deeply copied")
	_check(StateKey.build(state) != StateKey.build(copied), "State keys encode Dugu state")


func _test_no_form_reveals_and_exiles_in_order() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(_catalog_card(&"CangSongYingKe1", Rules.PLAYER_OWNER, &"untouched"), Rules.PLAYER_OWNER)
	board[1] = _slot(_catalog_card(&"CangSongYingKe2", Rules.PLAYER_OWNER, &"north"), Rules.PLAYER_OWNER)
	board[3] = _slot(_catalog_card(&"TuNaShu1", Rules.OPPONENT_OWNER, &"west"), Rules.OPPONENT_OWNER)
	var hidden_enemy: Dictionary = _catalog_card(&"TuNaShu2", Rules.OPPONENT_OWNER, &"hidden_enemy")
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[_catalog_card(&"DuGu9Jian1", Rules.PLAYER_OWNER, &"no_form")],
			[hidden_enemy],
			Rules.PLAYER_OWNER,
			0,
			[
				_catalog_card(&"CangSongYingKe3", Rules.PLAYER_OWNER, &"draw_self"),
				_catalog_card(&"CangSongYingKe4", Rules.PLAYER_OWNER, &"draw_north"),
			],
			[_catalog_card(&"TuNaShu3", Rules.OPPONENT_OWNER, &"draw_west")]
		),
		Action.make_play(0, 4, &"no_form")
	)
	var next_state: State = transition.get("state") as State
	_check(bool(transition.get("valid", false)), "No Form is a legal hand play")
	_check(
		Revelation.is_revealed_to(next_state.get_hand(Rules.OPPONENT_OWNER)[0], Rules.PLAYER_OWNER)
		and (next_state.future_draw_reveal_audiences.get(Rules.OPPONENT_OWNER, []) as Array).has(Rules.PLAYER_OWNER),
		"No Form reveals the current opponent hand and all future draws"
	)
	_check(
		_instance_at(next_state, 0) == &"untouched" and next_state.board[1] == null
		and next_state.board[3] == null and next_state.board[4] == null,
		"No Form removes itself and only its orthogonal neighbors"
	)
	_check(
		_relevant_event_types(transition.get("events", []), [&"card_exiled", &"card_drawn"])
		== [&"card_exiled", &"card_drawn", &"card_exiled", &"card_drawn", &"card_exiled", &"card_drawn"],
		"Each removal is immediately followed by its current owner's draw"
	)


func _test_anticipate_suppresses_next_card() -> void:
	var non_retained: Dictionary = _before_summon_ability([{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1}], false)
	var retained: Dictionary = _before_summon_ability([{"type": Catalog.ACTION_GAIN_KI, "amount": 1}], true)
	var target: Dictionary = _catalog_card(&"CangSongYingKe1", Rules.OPPONENT_OWNER, &"suppressed")
	target["active_abilities"] = [non_retained, retained]
	var first: Dictionary = Simulator.apply_action(
		State.new(
			Rules.empty_board(),
			[_catalog_card(&"DuGu9Jian2", Rules.PLAYER_OWNER, &"anticipate"), _catalog_card(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"followup")],
			[target], Rules.PLAYER_OWNER, 0,
			[_catalog_card(&"TuNaShu1", Rules.PLAYER_OWNER, &"anticipate_draw")],
			[_catalog_card(&"TuNaShu2", Rules.OPPONENT_OWNER, &"blocked_draw")]
		),
		Action.make_play(0, 4, &"anticipate")
	)
	var prepared: State = first.get("state") as State
	_check(
		prepared.board[4] == null and prepared.extra_card_plays_remaining == 1
		and int(prepared.pending_non_retained_suppression_by_owner[Rules.OPPONENT_OWNER]) == 1,
		"Anticipate exiles itself, draws, grants an extra play, and queues suppression"
	)
	prepared = (Simulator.apply_action(prepared, Action.make_play(0, 8, &"followup")).get("state") as State)
	var second: Dictionary = Simulator.apply_action(prepared, Action.make_play(0, 0, &"suppressed"))
	var resolved: State = second.get("state") as State
	var runtime: Dictionary = (resolved.board[0] as Dictionary).get("card", {})
	_check(
		int(resolved.pending_non_retained_suppression_by_owner[Rules.OPPONENT_OWNER]) == 0
		and (runtime.get("active_abilities", []) as Array).size() == 1
		and bool(((runtime.get("active_abilities", []) as Array)[0] as Dictionary).get("retained_on_flip", false)),
		"The next hand-played card permanently loses only non-retained abilities"
	)
	_check(int(runtime.get("ki", 0)) == 1, "The retained before-summon ability still resolves")
	_check(
		_relevant_event_types(second.get("events", []), [&"non_retained_suppression_consumed", &"ability_lost", &"ability_triggered"]).slice(0, 3)
		== [&"non_retained_suppression_consumed", &"ability_lost", &"ability_triggered"],
		"Suppression is consumed before trigger discovery"
	)


func _test_anticipate_includes_heart_methods() -> void:
	var heart: Dictionary = _catalog_card(&"TuNaShu1", Rules.OPPONENT_OWNER, &"heart")
	heart["active_abilities"] = [_before_summon_ability([{"type": Catalog.ACTION_GAIN_KI, "amount": 1}], false)]
	var state := State.new(Rules.empty_board(), [], [heart], Rules.OPPONENT_OWNER)
	state.pending_non_retained_suppression_by_owner[Rules.OPPONENT_OWNER] = 1
	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4, &"heart"))
	var next_state: State = transition.get("state") as State
	var runtime: Dictionary = (next_state.board[4] as Dictionary).get("card", {})
	_check(
		int(next_state.pending_non_retained_suppression_by_owner[Rules.OPPONENT_OWNER]) == 0
		and (runtime.get("active_abilities", []) as Array).is_empty() and int(runtime.get("ki", 0)) == 0,
		"Heart methods consume suppression and lose non-retained abilities too"
	)


func _test_pending_suppression_stacks_and_consumes_for_abilityless_cards() -> void:
	var first_card: Dictionary = _catalog_card(&"CangSongYingKe1", Rules.PLAYER_OWNER, &"stack_first")
	first_card["active_abilities"] = []
	var second_card: Dictionary = _catalog_card(&"CangSongYingKe2", Rules.PLAYER_OWNER, &"stack_second")
	second_card["active_abilities"] = []
	var state := State.new(Rules.empty_board(), [first_card, second_card], [], Rules.PLAYER_OWNER)
	state.pending_non_retained_suppression_by_owner[Rules.PLAYER_OWNER] = 2
	state.extra_card_plays_remaining = 1
	var first_transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 0, &"stack_first"))
	var after_first: State = first_transition.get("state") as State
	var second_transition: Dictionary = Simulator.apply_action(after_first, Action.make_play(0, 8, &"stack_second"))
	var after_second: State = second_transition.get("state") as State
	_check(
		int(after_first.pending_non_retained_suppression_by_owner[Rules.PLAYER_OWNER]) == 1
		and int(after_second.pending_non_retained_suppression_by_owner[Rules.PLAYER_OWNER]) == 0,
		"Each hand play consumes exactly one stacked layer, even without abilities"
	)
	_check(
		_relevant_event_types(first_transition.get("events", []), [&"non_retained_suppression_consumed", &"ability_lost"])
		== [&"non_retained_suppression_consumed"],
		"An abilityless card consumes a layer without fake loss events"
	)


func _test_break_all_transforms_enemies_and_preserves_runtime_identity() -> void:
	var enemy: Dictionary = _catalog_card(&"CangSongYingKe4", Rules.OPPONENT_OWNER, &"enemy_transform")
	enemy["powers"] = [9, 2, 7, 4]
	enemy["ki"] = 5
	enemy["revealed_to_owner_ids"] = [Rules.OPPONENT_OWNER, Rules.PLAYER_OWNER]
	var ally: Dictionary = _catalog_card(&"CangSongYingKe1", Rules.PLAYER_OWNER, &"ally_untouched")
	var board: Array = Rules.empty_board()
	board[1] = _slot(enemy, Rules.OPPONENT_OWNER)
	board[3] = _slot(ally, Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [_catalog_card(&"DuGu9Jian3", Rules.PLAYER_OWNER, &"break_all")], [], Rules.PLAYER_OWNER, 0, [_catalog_card(&"TuNaShu1", Rules.PLAYER_OWNER, &"break_draw")]),
		Action.make_play(0, 4, &"break_all")
	)
	var next_state: State = transition.get("state") as State
	var transformed: Dictionary = (next_state.board[1] as Dictionary).get("card", {})
	_check(
		StringName(transformed.get("card_id", &"")) == &"TaiZuChangQuan"
		and StringName(transformed.get("instance_id", &"")) == &"enemy_transform"
		and transformed.get("powers", []) == [9, 2, 7, 4] and int(transformed.get("ki", -1)) == 0,
		"Break All creates a same-instance TaiZu card with preserved powers and reset ki"
	)
	_check(
		int((next_state.board[1] as Dictionary).get("owner", 0)) == Rules.OPPONENT_OWNER
		and int(transformed.get("original_owner", 0)) == Rules.OPPONENT_OWNER
		and transformed.get("revealed_to_owner_ids", []) == [Rules.OPPONENT_OWNER, Rules.PLAYER_OWNER]
		and StringName((((next_state.board[3] as Dictionary).get("card", {}) as Dictionary).get("card_id", &""))) == &"CangSongYingKe1",
		"Break All preserves owner, original owner, reveal state, and allied cards"
	)
	_check(
		next_state.extra_card_plays_remaining == 1
		and _relevant_event_types(transition.get("events", []), [&"card_exiled", &"card_drawn", &"card_transformed", &"extra_card_play_granted"])
		== [&"card_exiled", &"card_drawn", &"card_transformed", &"extra_card_play_granted"],
		"Break All resolves exile, draw, transform, then extra play"
	)


func _before_summon_ability(actions: Array, retained: bool) -> Dictionary:
	return {"retained_on_flip": retained, "triggers": [{"event": Catalog.TRIGGER_CARD_BEFORE_SUMMONED, "conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}], "actions": actions.duplicate(true)}]}


func _catalog_card(card_id: StringName, owner_id: int, instance_id: StringName) -> Dictionary:
	return Catalog.create_instance(card_id, owner_id, instance_id)


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _instance_at(state: State, cell: int) -> StringName:
	if state == null or cell < 0 or cell >= state.board.size() or state.board[cell] == null:
		return &""
	return StringName((((state.board[cell] as Dictionary).get("card", {}) as Dictionary).get("instance_id", &"")))


func _relevant_event_types(events: Array, allowed: Array[StringName]) -> Array[StringName]:
	var types: Array[StringName] = []
	for event_value: Variant in events:
		if event_value is Dictionary:
			var event_type := StringName((event_value as Dictionary).get("type", &""))
			if event_type in allowed:
				types.append(event_type)
	return types


func _finish() -> void:
	if _failures == 0:
		print("DUGU_NINE_SWORDS_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("DUGU_NINE_SWORDS_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
