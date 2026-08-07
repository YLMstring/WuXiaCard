extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Executor = preload("res://scripts/duel_ability_executor.gd")
const ProfileStore = preload("res://scripts/deck_profile_store.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_vocabulary_and_declaration()
	_test_resummon_is_fresh_and_resolves_full_summon()
	_test_resummon_requires_self_attack_and_original_ally()
	_test_resummon_request_follows_exact_instance()
	_test_resummon_skips_a_missing_instance()
	_test_abilities_are_lost_on_flip()
	if _failures == 0:
		print("MIANLI_CANGZHEN3_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"MIANLI_CANGZHEN3_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_vocabulary_and_declaration() -> void:
	_check(
		Catalog.CONDITION_TRIGGER_CARD_ORIGINAL_OWNER_IS_SELF
		in Catalog.KNOWN_TRIGGER_CONDITIONS,
		"Trigger-card original-owner condition is registered"
	)
	_check(
		Catalog.ACTION_RESUMMON_TRIGGER_CARD_IN_PLACE in Catalog.KNOWN_ACTIONS,
		"In-place resummon action is registered"
	)
	_check(&"MianLiCangZhen3" in Catalog.get_all_card_ids(), "MianLi tier three is registered")
	_check(
		&"MianLiCangZhen3" not in ProfileStore.DEFAULT_LOCKED_IDS,
		"MianLi tier three is not default-locked"
	)
	var abilities: Array = Catalog.get_definition(&"MianLiCangZhen3").get("abilities", [])
	_check(abilities.size() == 2, "MianLi tier three declares resummon and counterattack")
	if abilities.size() == 2:
		var trigger: Dictionary = ((abilities[0] as Dictionary).get("triggers", []) as Array)[0]
		_check(StringName(trigger.get("event", &"")) == Catalog.CARD_AFTER_FLIPPED, "Resummon listens after a completed flip")
		_check(
			trigger.get("conditions", [])
			== [
				{"type": Catalog.CONDITION_ATTACKER_CARD_IS_SELF},
				{"type": Catalog.CONDITION_TRIGGER_CARD_ORIGINAL_OWNER_IS_SELF},
			],
			"Resummon uses the approved two trigger conditions"
		)
		_check(
			trigger.get("actions", [])
			== [{"type": Catalog.ACTION_RESUMMON_TRIGGER_CARD_IN_PLACE}],
			"Resummon uses the generic in-place action"
		)
	_check(Catalog.validate_catalog().is_empty(), "Complete catalog validates")


func _test_resummon_is_fresh_and_resolves_full_summon() -> void:
	var old_target: Dictionary = Catalog.create_instance(
		&"TuNaShu1",
		Rules.PLAYER_OWNER,
		&"generated_TuNaShu1_1"
	)
	old_target["ki"] = 9
	old_target["powers"] = [0, 0, 0, 0]
	old_target["active_abilities"] = []
	var board: Array = Rules.empty_board()
	board[0] = _slot(_plain(&"fresh_attack_target", [1, 0, 1, 1]), Rules.OPPONENT_OWNER)
	board[1] = _slot(old_target, Rules.OPPONENT_OWNER, Rules.PLAYER_OWNER)
	var source: Dictionary = Catalog.create_instance(
		&"MianLiCangZhen3",
		Rules.PLAYER_OWNER,
		&"mianli_source"
	)
	var draw_card: Dictionary = _plain(&"resummon_draw")
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[source],
			[],
			Rules.PLAYER_OWNER,
			0,
			[draw_card],
			[]
		),
		Action.make_play(0, 4, &"mianli_source")
	)
	var next_state: State = transition.get("state") as State
	var new_slot: Dictionary = next_state.board[1]
	var new_target: Dictionary = new_slot.get("card", {})
	var definition: Dictionary = Catalog.get_definition(&"TuNaShu1")
	_check(StringName(new_target.get("instance_id", &"")) != &"generated_TuNaShu1_1", "Resummon replaces the old runtime identity")
	_check(StringName(new_target.get("card_id", &"")) == &"TuNaShu1", "Resummon keeps the exact catalog card ID")
	_check(int(new_slot.get("owner", 0)) == Rules.PLAYER_OWNER and int(new_target.get("original_owner", 0)) == Rules.PLAYER_OWNER, "Fresh instance belongs currently and originally to the source owner")
	_check(new_target.get("powers", []) == definition.get("powers", []), "Fresh instance restores catalog powers")
	_check(int(new_target.get("ki", -1)) == int(definition.get("starting_ki", 0)), "Fresh instance restores catalog ki")
	_check((new_target.get("active_abilities", []) as Array).size() == 1, "Fresh instance restores catalog abilities")
	_check(next_state.get_hand(Rules.PLAYER_OWNER).size() == 1, "Fresh instance resolves its after-summon draw")
	_check(int(((next_state.board[0] as Dictionary).get("owner", 0))) == Rules.PLAYER_OWNER, "Fresh instance performs its standard attack")
	var types: Array[StringName] = _event_types(transition.get("events", []))
	var flipped_index: int = types.find(&"card_flipped")
	var departed_index: int = types.find(&"card_departed_for_resummon")
	var summoned_index: int = types.find(&"card_summoned", departed_index + 1)
	var drawn_index: int = types.find(&"card_drawn", summoned_index + 1)
	_check(flipped_index >= 0 and flipped_index < departed_index and departed_index < summoned_index, "Old flip, departure, and fresh summon events stay ordered")
	_check(summoned_index < drawn_index, "After-summon effects resolve after the fresh summon event")
	_check((next_state.removed_cards[Rules.PLAYER_OWNER] as Array).is_empty(), "Resummon does not exile the old instance")


func _test_resummon_requires_self_attack_and_original_ally() -> void:
	var nonally_target: Dictionary = Catalog.create_instance(
		&"TuNaShu1",
		Rules.OPPONENT_OWNER,
		&"nonally_target"
	)
	var nonally_board: Array = Rules.empty_board()
	nonally_board[1] = _slot(nonally_target, Rules.OPPONENT_OWNER)
	var source: Dictionary = Catalog.create_instance(&"MianLiCangZhen3", Rules.PLAYER_OWNER, &"nonally_source")
	var nonally_transition: Dictionary = Simulator.apply_action(
		State.new(nonally_board, [source], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"nonally_source")
	)
	var nonally_state: State = nonally_transition.get("state") as State
	_check(_instance_at(nonally_state, 1) == &"nonally_target", "A card originally owned by the enemy is not resummoned")
	_check(_event_types(nonally_transition.get("events", [])).count(&"card_departed_for_resummon") == 0, "Nonmatching original owner emits no departure")

	var allied_target: Dictionary = Catalog.create_instance(&"TuNaShu1", Rules.PLAYER_OWNER, &"other_attacker_target")
	var other_board: Array = Rules.empty_board()
	other_board[1] = _slot(allied_target, Rules.OPPONENT_OWNER, Rules.PLAYER_OWNER)
	other_board[8] = _slot(
		Catalog.create_instance(&"MianLiCangZhen3", Rules.PLAYER_OWNER, &"watching_mianli"),
		Rules.PLAYER_OWNER
	)
	var other_attacker: Dictionary = _plain(&"other_attacker", [9, 1, 1, 1])
	var other_transition: Dictionary = Simulator.apply_action(
		State.new(other_board, [other_attacker], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"other_attacker")
	)
	var other_state: State = other_transition.get("state") as State
	_check(_instance_at(other_state, 1) == &"other_attacker_target", "MianLi does not react when another allied card made the flip")
	_check(_event_types(other_transition.get("events", [])).count(&"card_departed_for_resummon") == 0, "Another attacker's flip emits no resummon departure")


func _test_resummon_request_follows_exact_instance() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(&"MianLiCangZhen3", Rules.PLAYER_OWNER, &"moving_source"), Rules.PLAYER_OWNER)
	board[0] = _slot(Catalog.create_instance(&"TuNaShu1", Rules.PLAYER_OWNER, &"moving_target"), Rules.PLAYER_OWNER)
	var state := State.new(board)
	var observed: Dictionary = {"request": {}}
	var summon_resolver: Callable = func(request: Dictionary) -> Dictionary:
		observed["request"] = request.duplicate(true)
		return _empty_resolution()
	var result: Dictionary = Executor.execute_actions(
		state,
		4,
		&"moving_source",
		Rules.PLAYER_OWNER,
		[{"type": Catalog.ACTION_RESUMMON_TRIGGER_CARD_IN_PLACE}],
		{"trigger_cell": 1, "trigger_instance_id": &"moving_target"},
		Callable(),
		Callable(),
		summon_resolver
	)
	_check(StringName(result.get("result", &"")) == Catalog.ACTION_RESULT_APPLIED, "Moved exact instance still produces a resummon")
	_check(state.board[0] == null, "Moved old instance leaves its current cell")
	var observed_request: Dictionary = observed.get("request", {})
	_check(int(observed_request.get("target_cell", -1)) == 0, "Resummon request targets the exact instance's current cell")
	_check(StringName(observed_request.get("old_instance_id", &"")) == &"moving_target", "Resummon request preserves old identity for presentation")


func _test_resummon_skips_a_missing_instance() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(&"MianLiCangZhen3", Rules.PLAYER_OWNER, &"missing_source"), Rules.PLAYER_OWNER)
	var state := State.new(board)
	var result: Dictionary = Executor.execute_actions(
		state,
		4,
		&"missing_source",
		Rules.PLAYER_OWNER,
		[{"type": Catalog.ACTION_RESUMMON_TRIGGER_CARD_IN_PLACE}],
		{"trigger_cell": 1, "trigger_instance_id": &"missing_target"}
	)
	_check(StringName(result.get("result", &"")) == Catalog.ACTION_RESULT_NO_EFFECT, "Missing trigger instance returns no effect")
	_check((result.get("summon_requests", []) as Array).is_empty(), "Missing trigger instance creates no summon request")


func _test_abilities_are_lost_on_flip() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(&"MianLiCangZhen3", Rules.PLAYER_OWNER, &"flip_mianli"), Rules.PLAYER_OWNER)
	var state := State.new(board)
	Executor.resolve_normal_flip(state, -1, &"", 4, &"flip_mianli", Rules.OPPONENT_OWNER)
	var flipped: Dictionary = (state.board[4] as Dictionary).get("card", {})
	_check((flipped.get("active_abilities", []) as Array).is_empty(), "Both MianLi abilities are lost on flip")


func _plain(instance_id: StringName, powers: Array[int] = [1, 1, 1, 1]) -> Dictionary:
	var card: Dictionary = Rules.make_card(String(instance_id), "测", powers, [], Rules.PLAYER_OWNER)
	card["instance_id"] = instance_id
	return card


func _slot(card: Dictionary, owner_id: int, original_owner: int = 0) -> Dictionary:
	card["original_owner"] = owner_id if original_owner == 0 else original_owner
	return {"card": card, "owner": owner_id}


func _instance_at(state: State, cell: int) -> StringName:
	if state.board[cell] == null:
		return &""
	return StringName((((state.board[cell] as Dictionary).get("card", {})) as Dictionary).get("instance_id", &""))


func _event_types(events: Array) -> Array[StringName]:
	var types: Array[StringName] = []
	for value: Variant in events:
		if value is Dictionary:
			types.append(StringName((value as Dictionary).get("type", &"")))
	return types


func _empty_resolution() -> Dictionary:
	return {
		"events": [],
		"captures": [],
		"exiles": [],
		"extra_turn_requests": [],
		"flip_prevention_requests": [],
	}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
