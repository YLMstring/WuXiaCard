extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const Executor = preload("res://tests/helpers/duel_native_action_test_harness.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

const TEST_PROFILE_PATH: String = "user://jingang_buhuai_integration.json"

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_profile()
	var duel: Node = DUEL_SCENE.instantiate()
	duel.set("deck_profile_path", TEST_PROFILE_PATH)
	duel.set("testing_mode", true)
	duel.set("player_hand_shuffle_seed", -1)
	duel.set("opponent_hand_shuffle_seed", -1)
	duel.set("opening_layout_seed", -1)
	root.add_child(duel)
	await process_frame
	await process_frame
	duel.debug_set_fast_mode(true)
	await _test_discard_fades_before_fresh_copy_appears(duel)
	await _test_batch_discards_fade_together_before_one_shift(duel)
	duel.queue_free()
	await process_frame
	_cleanup_profile()
	if _failures == 0:
		print("JINGANG_BUHUAI_INTEGRATION_PASSED checks=%d" % _checks)
	else:
		push_error(
			"JINGANG_BUHUAI_INTEGRATION_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_discard_fades_before_fresh_copy_appears(duel: Node) -> void:
	var board: Array = Rules.empty_board()
	board[4] = {
		"card": Catalog.create_instance(
			&"JinGangBuHuai3",
			Rules.PLAYER_OWNER,
			&"integration_jingang"
		),
		"owner": Rules.PLAYER_OWNER,
	}
	var right_near: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan",
		Rules.PLAYER_OWNER,
		&"integration_jingang_right_near"
	)
	var discarded_card: Dictionary = Catalog.create_instance(
		&"TuNaShu1",
		Rules.PLAYER_OWNER,
		&"integration_jingang_discard"
	)
	var right_far: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan",
		Rules.PLAYER_OWNER,
		&"integration_jingang_right_far"
	)
	discarded_card["hand_slot_index"] = 0
	right_near["hand_slot_index"] = 1
	right_far["hand_slot_index"] = 2
	duel.call(
		"_rebuild_views_from_state",
		State.new(board, [right_near, discarded_card, right_far], [], Rules.PLAYER_OWNER)
	)
	var result: Dictionary = Simulator.resolve_non_attack_flip(
		duel.duel_state,
		&"integration_jingang",
		Rules.OPPONENT_OWNER
	)
	await duel.call(
		"_present_transition_events",
		result.get("events", []),
		Rules.PLAYER_OWNER
	)
	var trace: Array[StringName] = duel.debug_get_presentation_trace()
	var added_event: Dictionary = _first_event(result.get("events", []), &"card_added_to_hand")
	var copied_instance_id := StringName(added_event.get("instance_id", &""))
	var hand_view_ids: Array[StringName] = duel.debug_get_hand_view_instance_ids(
		Rules.PLAYER_OWNER
	)
	var slot_view_ids: Array = duel.call(
		"debug_get_hand_view_slot_instance_ids", Rules.PLAYER_OWNER
	)
	var movement_trace: Array[Dictionary] = duel.debug_get_movement_presentation_trace()
	_check(
		trace.rfind(&"card_discarded") < trace.rfind(&"card_added_to_hand")
		and &"card_discard_faded" in trace,
		"Discard reuses the fade-out presentation before the fresh copy appears"
	)
	_check(
		hand_view_ids == [
			&"integration_jingang_right_near",
			&"integration_jingang_right_far",
			copied_instance_id,
		],
		"The discarded view stays gone while one fresh-copy view appears"
	)
	_check(
		trace.rfind(&"card_discarded") < trace.rfind(&"hand_cards_shifted")
		and trace.rfind(&"hand_cards_shifted") < trace.rfind(&"card_added_to_hand")
		and slot_view_ids == [
			&"integration_jingang_right_near",
			&"integration_jingang_right_far",
			copied_instance_id,
			&"",
			&"",
		]
		and not movement_trace.is_empty()
		and StringName(movement_trace[-1].get("kind", &"")) == &"hand_shift"
		and (movement_trace[-1].get("moves", []) as Array).size() == 2,
		"Discard shifts right-side views left together before the copy fills the next slot"
	)
	_check(
		_instance_at(duel.duel_state.discard_piles[Rules.PLAYER_OWNER] as Array, 0)
		== &"integration_jingang_discard"
		and copied_instance_id != &"integration_jingang_discard",
		"Presentation keeps the original discard and the fresh copy as distinct instances"
	)


func _test_batch_discards_fade_together_before_one_shift(duel: Node) -> void:
	var board: Array = Rules.empty_board()
	board[4] = {
		"card": Catalog.create_instance(
			&"TaiZuChangQuan",
			Rules.PLAYER_OWNER,
			&"integration_batch_source"
		),
		"owner": Rules.PLAYER_OWNER,
	}
	var first: Dictionary = Catalog.create_instance(
		&"TuNaShu1", Rules.PLAYER_OWNER, &"integration_batch_first"
	)
	var second: Dictionary = Catalog.create_instance(
		&"TuNaShu1", Rules.PLAYER_OWNER, &"integration_batch_second"
	)
	var survivor: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"integration_batch_survivor"
	)
	first["hand_slot_index"] = 0
	second["hand_slot_index"] = 2
	survivor["hand_slot_index"] = 4
	duel.call(
		"_rebuild_views_from_state",
		State.new(board, [survivor, second, first], [], Rules.PLAYER_OWNER)
	)
	var trace_start: int = (duel.debug_get_presentation_trace() as Array).size()
	var result: Dictionary = Executor.execute_actions(
		duel.duel_state,
		4,
		&"integration_batch_source",
		Rules.PLAYER_OWNER,
		[{
			"type": Catalog.ACTION_DISCARD_CARDS,
			"selector": {
				"zones": [Catalog.CARD_ZONE_HAND],
				"conditions": [{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY}],
				"limit": 2,
			},
		}],
		{
			"ability_source_instance_id": &"integration_batch_source",
			"ability_source_owner_id": Rules.PLAYER_OWNER,
		},
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		func(event_id: StringName, event_context: Dictionary) -> Dictionary:
			return Simulator._resolve_trigger_event(duel.duel_state, event_id, event_context)
	)
	await duel.call(
		"_present_transition_events",
		result.get("events", []),
		Rules.PLAYER_OWNER
	)
	var trace: Array = duel.debug_get_presentation_trace()
	var batch_trace: Array = trace.slice(trace_start)
	var slot_view_ids: Array = duel.call(
		"debug_get_hand_view_slot_instance_ids", Rules.PLAYER_OWNER
	)
	_check(
		_count_trace(batch_trace, &"card_discard_batch") == 1
		and _count_trace(batch_trace, &"card_discarded") == 2
		and _count_trace(batch_trace, &"card_discard_faded") == 2,
		"One discard batch starts both existing fade-outs together"
	)
	_check(
		_count_trace(batch_trace, &"hand_cards_shifted") == 1
		and batch_trace.rfind(&"card_discard_faded") < batch_trace.rfind(&"hand_cards_shifted")
		and slot_view_ids == [
			&"", &"", &"integration_batch_survivor", &"", &""
		],
		"The survivors perform one final collective hand shift after both fades"
	)


func _first_event(events: Array, event_type: StringName) -> Dictionary:
	for event_value: Variant in events:
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
		):
			return event_value as Dictionary
	return {}


func _instance_at(cards: Array, index: int) -> StringName:
	if index < 0 or index >= cards.size() or not cards[index] is Dictionary:
		return &""
	return StringName((cards[index] as Dictionary).get("instance_id", &""))


func _count_trace(trace: Array, event_type: StringName) -> int:
	var count: int = 0
	for value: Variant in trace:
		if StringName(value) == event_type:
			count += 1
	return count


func _cleanup_profile() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = TEST_PROFILE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
