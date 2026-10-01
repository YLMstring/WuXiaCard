extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Enemies = preload("res://scripts/enemy_catalog.gd")
const Factory = preload("res://scripts/duel_initial_state_factory.gd")
const State = preload("res://scripts/duel_state.gd")
const Compact = preload("res://scripts/duel_compact_state.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Action = preload("res://scripts/duel_action.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const Native = preload("res://scripts/duel_native_rules.gd")
const Search = preload("res://scripts/duel_search.gd")
const Keys = preload("res://scripts/duel_state_key.gd")
const Plans = preload("res://scripts/duel_turn_plan.gd")
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_opening_and_directory()
	var state := _fixture()
	var available := false
	for property: Dictionary in state.get_property_list():
		if property.name == "opponent_favorite_instance_id":
			available = true
	_check(available, "Favorite uses an exact instance in authoritative state")
	if available:
		_test_compact_and_identity()
		_test_decisions_and_consumption()
		_test_loss_and_anticipation()
		_test_partial_loss_restore_and_self_exile()
	if failures == 0:
		print("ENEMY_FAVORITE_TESTS_PASSED checks=%d" % checks)
	else:
		push_error("ENEMY_FAVORITE_TESTS_FAILED failures=%d checks=%d" % [failures, checks])
	quit(failures)

func _test_opening_and_directory() -> void:
	var ids: Array[StringName] = [&"TuNaShu3", &"TaiZuChangQuan", &"TaiZuChangQuan", &"TaiZuChangQuan", &"TaiZuChangQuan"]
	for seed_value: int in [1, 29, 812]:
		var config := {"player_main_card_ids": ids, "opponent_main_card_ids": ids,
			"opponent_favorite_card_id": &"TuNaShu3", "opponent_hand_shuffle_seed": seed_value,
			"player_hand_shuffle_seed": 11, "side_deck_shuffle_seed": 17,
			"opening_layout_seed": 19, "difficulty_effect_seed": 23}
		var state := Factory.build(config)
		var central: Dictionary = state.get_hand(2)[2]
		_check(central.get("card_id") == &"TuNaShu3" and central.hand_slot_index == 2, "Configured card occupies fixed central opening slot")
		_check(state.get("opponent_favorite_instance_id") == central.instance_id, "Opening records central identity")
		_check(Keys.build(state) == Keys.build(Factory.build(config)), "Opening seed and favorite are reproducible")
	for definition: Dictionary in Enemies.get_ai_benchmark_definitions():
		var favorite: StringName = definition.get("favorite_card", &"")
		if favorite != &"":
			_check(Catalog.has_card(favorite) and favorite in definition.deck, "Current declared favorites exist in their decks")
	var invalid := {"id": &"fixture", "name": "fixture", "level": 1, "deck": ids, "favorite_card": &"unknown"}
	_check(not Enemies.validate_definition(invalid).is_empty(), "Unknown favorite is rejected")
	invalid.favorite_card = &"YiKongDaoDi4"
	_check(not Enemies.validate_definition(invalid).is_empty(), "Favorite absent from opening deck is rejected")
	invalid.favorite_card = 42
	_check(not Enemies.validate_definition(invalid).is_empty(), "Favorite type is validated")

func _fixture() -> State:
	return State.new(Rules.empty_board(), [Catalog.create_instance(&"TaiZuChangQuan", 1, &"player")], [
		Catalog.create_instance(&"TuNaShu3", 2, &"copy"),
		Catalog.create_instance(&"TaiZuChangQuan", 2, &"other"),
		Catalog.create_instance(&"TuNaShu3", 2, &"favorite")], 2)

func _tracked() -> State:
	var state := _fixture()
	state.set("opponent_favorite_instance_id", &"favorite")
	return state

func _test_compact_and_identity() -> void:
	var state := _tracked()
	state.next_hand_play_from_discard_owner = 2
	var compact := Compact.new()
	_check(compact.capture_state(state), "Tracked state captures")
	_check(compact.scalars.size() == 16 and compact.scalars[8] == 2, "Discard-source marker reuses slot eight")
	_check(compact.scalars[9] >= 0 and compact.card_instance_ids[compact.scalars[9]] == &"favorite", "Slot nine names the exact instance")
	_check(not compact.side_payload.has("next_hand_play_from_discard_owner"), "No duplicate discard-source storage")
	_check(compact.to_variant_payload().format_version == 2, "New ABI is explicitly versioned")
	_check(Keys.build(compact.restore()) == Keys.build(state), "Both reused slots round-trip losslessly")
	var plain := state.duplicate_state() as State
	plain.set("opponent_favorite_instance_id", &"")
	_check(Keys.build_compact(plain) != Keys.build_compact(state), "Restriction participates in exact plan identity")
	var payload := compact.to_variant_payload()
	payload.format_version = 1
	var kernel: Object = ClassDB.instantiate(&"DuelNativeCompactKernel")
	_check(not kernel.call("load_compact_payload", payload), "Old incompatible native ABI is rejected")

func _test_decisions_and_consumption() -> void:
	var state := _tracked()
	var greedy := Simulator.choose_greedy_action(state)
	_check(greedy.source_instance_id == &"favorite", "Greedy chooses exact central instance, not same-ID copy")
	var result := Search.find_best_action_iterative(state, 2, {"max_depth": 1, "max_nodes": 500})
	var chosen: Action = result.get("action")
	_check(chosen != null and chosen.source_instance_id == &"favorite", "Deep search chooses same constrained instance")
	var copy_play := Action.make_play(0, 0, &"copy") as Action
	_check(Simulator.is_action_legal(state, copy_play), "Manual play still permits a same-ID copy")
	var copied := Simulator.apply_action(state, copy_play)
	_check(copied.valid and copied.state.get("opponent_favorite_instance_id") == &"favorite", "Playing another copy does not consume restriction")
	var played := Simulator.apply_action(state, Action.make_play(2, 0, &"favorite"))
	_check(played.valid and played.state.get("opponent_favorite_instance_id") == &"", "Playing designated instance consumes restriction")
	_check(state.get("opponent_favorite_instance_id") == &"favorite", "Search and transitions leave parent untouched")
	var invalid := Simulator.apply_action(state, Action.make_play(2, 99, &"favorite"))
	_check(not invalid.valid and state.get("opponent_favorite_instance_id") == &"favorite", "Invalid play does not consume restriction")
	var entry := {"state_key": Keys.build_compact(state), "owner_id": 2, "turn_count": state.turn_count, "action": copy_play}
	_check(not Plans.take_next([entry], state, 2).matched, "A merely legal cached action cannot bypass AI preference")
	# Removed without a play/loss: no legal preferred action, no retargeting.
	var unavailable := _tracked()
	var exact: Dictionary = unavailable.get_hand(2).pop_back()
	unavailable.removed_cards[2].append(exact)
	_check(Simulator.choose_greedy_action(unavailable).source_instance_id != &"favorite", "No preferred legal action falls back to full actions")
	_check(unavailable.get("opponent_favorite_instance_id") == &"favorite", "Departure alone preserves identity")
	unavailable.active_player = 1
	_check(Simulator.choose_greedy_action(unavailable).source_instance_id == &"player", "Player decision is unrestricted")

func _test_loss_and_anticipation() -> void:
	for kind: StringName in [Catalog.ACTION_TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES, Catalog.ACTION_PERMANENTLY_REMOVE_NON_RETAINED_ABILITIES]:
		var state := _tracked()
		var declaration := {"type": kind}
		if kind == Catalog.ACTION_PERMANENTLY_REMOVE_NON_RETAINED_ABILITIES:
			declaration.card = Catalog.CARD_REF_ABILITY_SOURCE
		var lost := Native.execute_actions(state.duplicate_state(), -1, &"favorite", 2, [declaration], {})
		_check(lost.valid and lost.state.get("opponent_favorite_instance_id") == &"", "Actual temporary/permanent loss cancels preference")
		_check(state.get("opponent_favorite_instance_id") == &"favorite", "Direct loss preserves input state")
		var other := Native.execute_actions(state.duplicate_state(), -1, &"copy", 2, [declaration], {})
		_check(other.valid and other.state.get("opponent_favorite_instance_id") == &"favorite", "Other copy losing effects does not cancel")
	var locked := _tracked()
	locked.get_hand(2)[2].active_abilities = [Catalog.GUMU_YUNV_DISCARD_SOURCE]
	var no_loss := Native.execute_actions(locked, -1, &"favorite", 2,
		[{"type": Catalog.ACTION_PERMANENTLY_REMOVE_NON_RETAINED_ABILITIES, "card": Catalog.CARD_REF_ABILITY_SOURCE}], {})
	_check(no_loss.valid and no_loss.state.get("opponent_favorite_instance_id") == &"favorite", "Protected effects without actual loss retain preference")
	for owner: int in [1, 2]:
		var state := _tracked()
		var source: StringName = &"player" if owner == 1 else &"copy"
		var added := Native.execute_actions(state, -1, source, owner,
			[{"type": Catalog.ACTION_ADD_PENDING_NON_RETAINED_SUPPRESSION, "recipient": Catalog.RECIPIENT_OPPONENT, "amount": 2}], {})
		_check(added.valid and added.state.effect_queue.size() == 2, "Anticipation still queues repeated ordinary effects")
		_check(added.state.get("opponent_favorite_instance_id") == (&"" if owner == 1 else &"favorite"), "Anticipation cancels immediately for its recipient only")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _test_partial_loss_restore_and_self_exile() -> void:
	var state := _tracked()
	state.get_hand(2)[2].active_abilities = [Catalog.GUMU_YUNV_DISCARD_SOURCE,
		{"modifiers": [{"type": Catalog.MODIFIER_CANNOT_ATTACK}]}]
	state.acquired_ability_indices_by_instance_id = {&"favorite": [1]}
	var lost := Native.execute_actions(state, -1, &"favorite", 2,
		[{"type": Catalog.ACTION_TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES}], {})
	_check(lost.valid and state.get_hand(2)[2].active_abilities.size() == 1
		and state.opponent_favorite_instance_id == &"", "Losing one acquired effect cancels while locked effect remains")
	var ended := Simulator.apply_action(state, Action.make_play(0, 0, &"copy"))
	_check(ended.valid and ended.state.get_hand(2)[1].active_abilities.size() == 2
		and ended.state.opponent_favorite_instance_id == &"", "Restoration does not restart preference")
	for card_id: StringName in [&"ZuoYouHuBo5", &"YiKongDaoDi4"]:
		state = _tracked()
		state.hands[2][2] = Catalog.create_instance(card_id, 2, &"favorite")
		state.hands[2][2].hand_slot_index = 2
		var played := Simulator.apply_action(state, Action.make_play(2, 4, &"favorite"))
		_check(played.valid and played.state.opponent_favorite_instance_id == &"", "Self-exiling configured card releases on physical play")
		_check(state.opponent_favorite_instance_id == &"favorite", "Self-exile transition isolates parent")
	state = _tracked()
	state.get_hand(2)[2].active_abilities = [{"triggers": [{
		"event": Catalog.TRIGGER_CARD_BEFORE_SUMMONED,
		"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [{"type": Catalog.ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY, "on_invalid_context": Catalog.STOP_RULE},
			{"type": Catalog.ACTION_DRAW_CARDS, "amount": 1}]
	}]}]
	for cell: int in range(9):
		if cell != 4:
			state.board[cell] = {"card": Catalog.create_instance(&"TaiZuChangQuan", 1, StringName("block_%d" % cell)), "owner": 1}
	_check(Simulator.choose_greedy_action(state).source_instance_id == &"favorite", "Entry STOP_RULE does not require qualification preview")
