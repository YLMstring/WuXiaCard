extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Executor = preload("res://scripts/duel_ability_executor.gd")
const Revelation = preload("res://scripts/duel_revelation.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const TEST_PROFILE_PATH: String = "user://cangsong_sanqin_test_profile.json"

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_declarations()
	_test_generic_add_card_to_hand()
	_test_cangsong_copies_before_attack_flip()
	_test_cangsong_spends_with_full_hand()
	_test_exiled_attack_target_emits_no_flip_triggers()
	_test_non_attack_flip_uses_before_and_after_events()
	_test_sanqin_three_attacks_in_row_major_order()
	_test_sanqin_spends_without_attack_targets()
	await _test_opponent_hand_addition_is_revealed()

	if _failures == 0:
		print("CANGSONG_SANQIN_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"CANGSONG_SANQIN_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_catalog_declarations() -> void:
	for card_id: StringName in [
		&"CangSongYingKe3",
		&"CangSongYingKe4",
		&"SanQinFeng1",
		&"SanQinFeng2",
		&"SanQinFeng3",
	]:
		var abilities: Array = Catalog.get_definition(card_id).get("abilities", [])
		var expected_count: int = 2 if card_id in [
			&"CangSongYingKe3",
			&"CangSongYingKe4",
		] else 1
		_check(
			abilities.size() == expected_count,
			"%s keeps each distinct trigger in its own passive ability group" % card_id
		)
		for ability: Dictionary in abilities:
			_check(
				Catalog.validate_ability(ability, card_id).is_empty(),
				"%s declaration passes generic catalog validation" % card_id
			)
	for entry: Dictionary in [
		{
			"type": Catalog.ACTION_ADD_CARD_TO_HAND,
			"card_id": &"missing_card",
			"recipient": Catalog.RECIPIENT_SELF,
		},
		{
			"type": Catalog.ACTION_ADD_CARD_TO_HAND,
			"card_id": &"CangSongYingKe3",
			"recipient": &"third_owner",
		},
	]:
		var fixture: Dictionary = {
			"triggers": [{
				"event": Catalog.CARD_BEFORE_FLIPPED,
				"conditions": [],
				"actions": [entry],
			}],
		}
		_check(
			not Catalog.validate_ability(fixture).is_empty(),
			"Malformed add-card declaration is rejected"
		)


func _test_generic_add_card_to_hand() -> void:
	var source: Dictionary = Catalog.create_instance(
		&"ZiXiaGong1",
		Rules.PLAYER_OWNER,
		&"add_source"
	)
	var board: Array = Rules.empty_board()
	board[4] = {"card": source, "owner": Rules.PLAYER_OWNER}
	var state := State.new(board)
	var result: Dictionary = Executor.execute_actions(
		state,
		4,
		&"add_source",
		Rules.PLAYER_OWNER,
		[{
			"type": Catalog.ACTION_ADD_CARD_TO_HAND,
			"card_id": &"CangSongYingKe3",
			"recipient": Catalog.RECIPIENT_OPPONENT,
		}],
		{}
	)
	var opponent_hand: Array = state.get_hand(Rules.OPPONENT_OWNER)
	_check(
		StringName(result.get("result", &"")) == Catalog.ACTION_RESULT_APPLIED
		and opponent_hand.size() == 1,
		"Generic add-card action can add to the source owner's opponent"
	)
	var added: Dictionary = opponent_hand[0]
	var add_events: Array = result.get("events", [])
	_check(
		StringName(added.get("card_id", &"")) == &"CangSongYingKe3"
		and int(added.get("original_owner", 0)) == Rules.OPPONENT_OWNER
		and StringName(added.get("instance_id", &""))
		== &"generated_CangSongYingKe3_1",
		"Added card is a deterministic fresh catalog instance"
	)
	_check(
		Revelation.is_revealed_to(added, Rules.PLAYER_OWNER)
		and _event_types(add_events) == [&"card_added_to_hand", &"card_revealed"]
		and Revelation.is_revealed_to(
			(_first_event(add_events, &"card_added_to_hand").get("card", {}) as Dictionary),
			Rules.PLAYER_OWNER
		),
		"A non-draw hand addition is public to the recipient's opponent before its event snapshot"
	)
	var copied_state: State = state.duplicate_state()
	var second_result: Dictionary = Executor.execute_actions(
		copied_state,
		4,
		&"add_source",
		Rules.PLAYER_OWNER,
		[{
			"type": Catalog.ACTION_ADD_CARD_TO_HAND,
			"card_id": &"CangSongYingKe3",
			"recipient": Catalog.RECIPIENT_OPPONENT,
		}],
		{}
	)
	_check(
		StringName(
			(copied_state.get_hand(Rules.OPPONENT_OWNER)[1] as Dictionary).get(
				"instance_id",
				&""
			)
		) == &"generated_CangSongYingKe3_2"
		and StringName(second_result.get("result", &""))
		== Catalog.ACTION_RESULT_APPLIED,
		"Generated card IDs avoid collisions deterministically"
	)


func _test_cangsong_copies_before_attack_flip() -> void:
	var attacker: Dictionary = Catalog.create_instance(
		&"CangSongYingKe1",
		Rules.PLAYER_OWNER,
		&"copy_attacker"
	)
	var target: Dictionary = Catalog.create_instance(
		&"CangSongYingKe3",
		Rules.OPPONENT_OWNER,
		&"copy_target"
	)
	target["ki"] = 1
	target["powers"] = [9, 9, 9, 4]
	var board: Array = Rules.empty_board()
	board[4] = {"card": target, "owner": Rules.OPPONENT_OWNER}
	var state := State.new(board, [attacker])
	var transition: Dictionary = Simulator.apply_action_oracle(
		state,
		Action.make_play(0, 3, &"copy_attacker")
	)
	var next_state: State = transition.get("state") as State
	var copied_hand: Array = next_state.get_hand(Rules.OPPONENT_OWNER)
	_check(
		bool(transition.get("valid", false))
		and copied_hand.size() == 1
		and int((next_state.board[4] as Dictionary).get("owner", 0))
		== Rules.PLAYER_OWNER,
		"CangSong adds a copy for its pre-flip owner, then changes ownership"
	)
	var copied_card: Dictionary = copied_hand[0]
	var flipped_card: Dictionary = (next_state.board[4] as Dictionary).get("card", {})
	_check(
		copied_card.get("powers", []) == [3, 8, 8, 2]
		and int(copied_card.get("ki", -1)) == 0
		and (copied_card.get("active_abilities", []) as Array).size() == 2
		and int(flipped_card.get("ki", -1)) == 0
		and (flipped_card.get("active_abilities", []) as Array).is_empty(),
		"The gained card is fresh while the flipped source spends ki and loses ability"
	)
	_check(
		Revelation.is_revealed_to(copied_card, Rules.PLAYER_OWNER),
		"CangSong's enemy-hand copy is permanently visible to the player"
	)
	var event_types: Array[StringName] = _event_types(transition.get("events", []))
	_check(
		event_types.find(&"ki_changed")
		< event_types.find(&"card_added_to_hand")
		and event_types.find(&"card_added_to_hand")
		< event_types.find(&"card_flipped"),
		"CangSong spends, adds, and flips in order"
	)


func _test_cangsong_spends_with_full_hand() -> void:
	var attacker: Dictionary = Catalog.create_instance(
		&"CangSongYingKe1",
		Rules.PLAYER_OWNER,
		&"full_attacker"
	)
	var target: Dictionary = Catalog.create_instance(
		&"CangSongYingKe4",
		Rules.OPPONENT_OWNER,
		&"full_target"
	)
	target["ki"] = 1
	var full_hand: Array = []
	for index: int in range(5):
		full_hand.append(Catalog.create_instance(
			&"CangSongYingKe1",
			Rules.OPPONENT_OWNER,
			StringName("full_%d" % index)
		))
	var board: Array = Rules.empty_board()
	board[4] = {"card": target, "owner": Rules.OPPONENT_OWNER}
	var state := State.new(board, [attacker], full_hand)
	var transition: Dictionary = Simulator.apply_action_oracle(
		state,
		Action.make_play(0, 3, &"full_attacker")
	)
	var next_state: State = transition.get("state") as State
	var flipped: Dictionary = (next_state.board[4] as Dictionary).get("card", {})
	_check(
		next_state.get_hand(Rules.OPPONENT_OWNER).size() == 5
		and int(flipped.get("ki", -1)) == 0
		and &"card_added_to_hand" not in _event_types(transition.get("events", [])),
		"A full hand prevents the copy but does not refund CangSong's ki"
	)
	_check(
		&"card_revealed" not in _event_types(transition.get("events", [])),
		"A failed full-hand addition emits no reveal"
	)


func _test_exiled_attack_target_emits_no_flip_triggers() -> void:
	var attacker: Dictionary = Catalog.create_instance(
		&"LeiZHenJian1",
		Rules.PLAYER_OWNER,
		&"exile_attacker"
	)
	var target: Dictionary = Catalog.create_instance(
		&"CangSongYingKe3",
		Rules.OPPONENT_OWNER,
		&"exile_target"
	)
	target["ki"] = 1
	var board: Array = Rules.empty_board()
	board[4] = {"card": target, "owner": Rules.OPPONENT_OWNER}
	var state := State.new(board, [attacker])
	var transition: Dictionary = Simulator.apply_action_oracle(
		state,
		Action.make_play(0, 3, &"exile_attacker")
	)
	var types: Array[StringName] = _event_types(transition.get("events", []))
	_check(
		&"card_exiled" in types
		and &"card_added_to_hand" not in types
		and &"card_flipped" not in types,
		"Invalidation during CARD_BE_ATTACKED emits no before- or after-flip effects"
	)


func _test_non_attack_flip_uses_before_and_after_events() -> void:
	var target: Dictionary = Catalog.create_instance(
		&"CangSongYingKe3",
		Rules.OPPONENT_OWNER,
		&"effect_target"
	)
	target["ki"] = 1
	var board: Array = Rules.empty_board()
	board[8] = {"card": target, "owner": Rules.OPPONENT_OWNER}
	var state := State.new(board)
	var result: Dictionary = Simulator.resolve_non_attack_flip(
		state,
		&"effect_target",
		Rules.PLAYER_OWNER,
		&"fixture_effect"
	)
	var types: Array[StringName] = _event_types(result.get("events", []))
	_check(
		int((state.board[8] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER
		and state.get_hand(Rules.OPPONENT_OWNER).size() == 1
		and types.find(&"card_added_to_hand") < types.find(&"card_flipped"),
		"Non-attack flip resolves the reusable before-flip trigger"
	)


func _test_sanqin_three_attacks_in_row_major_order() -> void:
	var sanqin: Dictionary = Catalog.create_instance(
		&"SanQinFeng3",
		Rules.PLAYER_OWNER,
		&"sanqin_source"
	)
	sanqin["ki"] = 1
	var second: Dictionary = Catalog.create_instance(
		&"CangSongYingKe1",
		Rules.PLAYER_OWNER,
		&"sanqin_second"
	)
	var third: Dictionary = Catalog.create_instance(
		&"CangSongYingKe1",
		Rules.PLAYER_OWNER,
		&"sanqin_third"
	)
	var board: Array = Rules.empty_board()
	board[0] = {"card": sanqin, "owner": Rules.PLAYER_OWNER}
	board[2] = {"card": second, "owner": Rules.PLAYER_OWNER}
	board[6] = {"card": third, "owner": Rules.PLAYER_OWNER}
	for cell: int in [1, 3, 5, 7]:
		var enemy: Dictionary = Catalog.create_instance(
			&"CangSongYingKe1",
			Rules.OPPONENT_OWNER,
			StringName("sanqin_enemy_%d" % cell)
		)
		enemy["powers"] = [1, 1, 1, 1]
		board[cell] = {"card": enemy, "owner": Rules.OPPONENT_OWNER}
	var opponent_play: Dictionary = Catalog.create_instance(
		&"CangSongYingKe1",
		Rules.OPPONENT_OWNER,
		&"sanqin_opponent_play"
	)
	var state := State.new(
		board,
		[Catalog.create_instance(
			&"CangSongYingKe1",
			Rules.PLAYER_OWNER,
			&"sanqin_player_reply"
		)],
		[opponent_play],
		Rules.OPPONENT_OWNER
	)
	var transition: Dictionary = Simulator.apply_action_oracle(
		state,
		Action.make_play(0, 8, &"sanqin_opponent_play")
	)
	var next_state: State = transition.get("state") as State
	var attack_sources: Array[StringName] = []
	for event_value: Variant in transition.get("events", []):
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		if StringName(event.get("type", &"")) == &"attack_started":
			attack_sources.append(StringName(event.get("source_instance_id", &"")))
	_check(
		attack_sources == [
			&"sanqin_source",
			&"sanqin_source",
			&"sanqin_second",
			&"sanqin_third",
		],
		"SanQinFeng3 resolves selected standard attacks sequentially in row-major order"
	)
	_check(
		int(((next_state.board[0] as Dictionary).get("card", {}) as Dictionary).get("ki", -1))
		== 0
		and transition.get("captures", []) == [1, 3, 5, 7],
		"Start-turn ki spending and all attack captures propagate to the parent transition"
	)


func _test_sanqin_spends_without_attack_targets() -> void:
	var sanqin: Dictionary = Catalog.create_instance(
		&"SanQinFeng1",
		Rules.PLAYER_OWNER,
		&"quiet_sanqin"
	)
	sanqin["ki"] = 1
	var board: Array = Rules.empty_board()
	board[0] = {"card": sanqin, "owner": Rules.PLAYER_OWNER}
	var opponent_play: Dictionary = Catalog.create_instance(
		&"CangSongYingKe1",
		Rules.OPPONENT_OWNER,
		&"quiet_play"
	)
	var state := State.new(
		board,
		[Catalog.create_instance(
			&"CangSongYingKe1",
			Rules.PLAYER_OWNER,
			&"quiet_player_reply"
		)],
		[opponent_play],
		Rules.OPPONENT_OWNER
	)
	var transition: Dictionary = Simulator.apply_action_oracle(
		state,
		Action.make_play(0, 8, &"quiet_play")
	)
	var next_state: State = transition.get("state") as State
	_check(
		int(((next_state.board[0] as Dictionary).get("card", {}) as Dictionary).get("ki", -1))
		== 0
		and &"attack_started" not in _event_types(transition.get("events", [])),
		"SanQin spends one ki even when its selected sword has no attack target"
	)


func _test_opponent_hand_addition_is_revealed() -> void:
	_cleanup_test_profile()
	var duel: Node = DUEL_SCENE.instantiate()
	duel.set("deck_profile_path", TEST_PROFILE_PATH)
	duel.set("continue_automatically", false)
	duel.set("opponent_hand_shuffle_seed", -1)
	duel.set("opening_layout_seed", -1)
	duel.set("testing_mode", false)
	root.add_child(duel)
	await process_frame
	await process_frame
	duel.call("debug_set_fast_mode", true)
	var state: State = duel.get("duel_state") as State
	var opponent_hand: Array = state.get_hand(Rules.OPPONENT_OWNER)
	var removed: Dictionary = opponent_hand.pop_back()
	var removed_view: Node = duel.call(
		"_get_card_view_by_instance",
		StringName(removed.get("instance_id", &""))
	)
	if removed_view != null:
		removed_view.queue_free()
	await process_frame
	var added: Dictionary = Catalog.create_instance(
		&"CangSongYingKe3",
		Rules.OPPONENT_OWNER,
		&"present_added"
	)
	Revelation.reveal_to(added, Rules.PLAYER_OWNER)
	opponent_hand.append(added)
	await duel.call(
		"_present_transition_events",
		[{
			"type": &"card_added_to_hand",
			"source_instance_id": &"present_source",
			"owner_id": Rules.OPPONENT_OWNER,
			"card_id": &"CangSongYingKe3",
			"instance_id": &"present_added",
			"logical_hand_index": opponent_hand.size() - 1,
			"card": added.duplicate(true),
		}],
		Rules.OPPONENT_OWNER
	)
	var added_view: Node = duel.call("_get_card_view_by_instance", &"present_added")
	var trace: Array[StringName] = duel.call("debug_get_presentation_trace")
	_check(
		added_view != null
		and not bool(added_view.call("is_face_down"))
		and &"card_added_to_hand" in trace,
		"Production hand-addition presentation immediately shows a public opponent card"
	)
	duel.call("_rebuild_views_from_state", state.duplicate_state())
	await process_frame
	added_view = duel.call("_get_card_view_by_instance", &"present_added")
	_check(
		added_view != null and not bool(added_view.call("is_face_down")),
		"Rebuilding views preserves public non-draw opponent hand additions"
	)
	duel.queue_free()
	await process_frame
	_cleanup_test_profile()


func _cleanup_test_profile() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = TEST_PROFILE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _event_types(events: Array) -> Array[StringName]:
	var types: Array[StringName] = []
	for event_value: Variant in events:
		if event_value is Dictionary:
			types.append(StringName((event_value as Dictionary).get("type", &"")))
	return types


func _first_event(events: Array, event_type: StringName) -> Dictionary:
	for event_value: Variant in events:
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
		):
			return event_value as Dictionary
	return {}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
