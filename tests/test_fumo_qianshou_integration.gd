extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const Executor = preload("res://scripts/duel_ability_executor.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

const TEST_PROFILE_PATH: String = "user://fumo_qianshou_integration.json"

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
	await _test_after_exile_perfect_copy_view(duel)
	await _test_flip_protection_discard_then_copy_view(duel)
	duel.queue_free()
	await process_frame
	_cleanup_profile()
	if _failures == 0:
		print("FUMO_QIANSHOU_INTEGRATION_PASSED checks=%d" % _checks)
	else:
		push_error(
			"FUMO_QIANSHOU_INTEGRATION_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_after_exile_perfect_copy_view(duel: Node) -> void:
	var board: Array = Rules.empty_board()
	var qianshou: Dictionary = Catalog.create_instance(
		&"QianShouRuLai5", Rules.PLAYER_OWNER, &"integration_qian_source"
	)
	qianshou["powers"] = [9, 8, 7, 6]
	qianshou["ki"] = 2
	board[0] = _slot(qianshou, Rules.PLAYER_OWNER)
	board[4] = _slot(
		Catalog.create_instance(
			&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"integration_qian_target"
		),
		Rules.OPPONENT_OWNER
	)
	board[8] = _slot(
		Catalog.create_instance(
			&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"integration_qian_exiler"
		),
		Rules.PLAYER_OWNER
	)
	duel.call("_rebuild_views_from_state", State.new(board, [], [], Rules.PLAYER_OWNER))
	var trace_start: int = (duel.debug_get_presentation_trace() as Array).size()
	var result: Dictionary = Executor.execute_actions(
		duel.duel_state,
		8,
		&"integration_qian_exiler",
		Rules.PLAYER_OWNER,
		[{"type": Catalog.ACTION_EXILE_CARD, "card": Catalog.CARD_REF_TRIGGER_CARD}],
		{
			"ability_source_instance_id": &"integration_qian_exiler",
			"ability_source_owner_id": Rules.PLAYER_OWNER,
			"trigger_instance_id": &"integration_qian_target",
		},
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		func(event_id: StringName, event_context: Dictionary) -> Dictionary:
			return Simulator._resolve_trigger_event(
				duel.duel_state,
				event_id,
				event_context
			)
	)
	await duel.call(
		"_present_transition_events",
		result.get("events", []),
		Rules.PLAYER_OWNER
	)
	var trace: Array = (duel.debug_get_presentation_trace() as Array).slice(trace_start)
	var copy_slot: Dictionary = duel.duel_state.board[4] as Dictionary
	var copy: Dictionary = copy_slot.get("card", {})
	var copy_id := StringName(copy.get("instance_id", &""))
	_check(
		StringName(copy.get("card_id", &"")) == &"QianShouRuLai5"
		and copy_id != &"integration_qian_source"
		and copy.get("powers", []) == [9, 8, 7, 6]
		and int(copy.get("ki", -1)) == 2,
		"Production duel keeps the perfect runtime state under a new identity"
	)
	_check(
		duel.debug_has_board_card_view(4)
		and duel.debug_get_board_card_instance_id(4) == copy_id,
		"Perfect-copy summon creates a synchronized live board view"
	)
	_check(
		trace.find(&"card_exiled") >= 0
		and trace.find(&"card_summoned") > trace.find(&"card_exiled"),
		"External exile presentation finishes before the perfect-copy summon"
	)


func _test_flip_protection_discard_then_copy_view(duel: Node) -> void:
	var board: Array = Rules.empty_board()
	var qianshou: Dictionary = Catalog.create_instance(
		&"QianShouRuLai5", Rules.PLAYER_OWNER, &"integration_qian_flip"
	)
	qianshou["ki"] = 1
	board[4] = _slot(qianshou, Rules.PLAYER_OWNER)
	var discarded: Dictionary = Catalog.create_instance(
		&"TuNaShu1", Rules.PLAYER_OWNER, &"integration_qian_discard"
	)
	discarded["powers"] = [7, 6, 5, 4]
	discarded["ki"] = 3
	discarded[State.HAND_SLOT_INDEX_KEY] = 0
	duel.call(
		"_rebuild_views_from_state",
		State.new(board, [discarded], [], Rules.PLAYER_OWNER)
	)
	var trace_start: int = (duel.debug_get_presentation_trace() as Array).size()
	var result: Dictionary = Simulator.resolve_non_attack_flip(
		duel.duel_state,
		&"integration_qian_flip",
		Rules.OPPONENT_OWNER
	)
	await duel.call(
		"_present_transition_events",
		result.get("events", []),
		Rules.PLAYER_OWNER
	)
	var trace: Array = (duel.debug_get_presentation_trace() as Array).slice(trace_start)
	var hand_ids: Array[StringName] = duel.debug_get_hand_view_instance_ids(
		Rules.PLAYER_OWNER
	)
	var copied: Dictionary = duel.duel_state.get_hand(Rules.PLAYER_OWNER)[0]
	var copied_id := StringName(copied.get("instance_id", &""))
	_check(
		int((duel.duel_state.board[4] as Dictionary).get("owner", 0))
		== Rules.PLAYER_OWNER
		and copied_id != &"integration_qian_discard"
		and copied.get("powers", []) == [7, 6, 5, 4]
		and int(copied.get("ki", -1)) == 3,
		"Production duel prevents the flip and retains discarded runtime values"
	)
	_check(
		hand_ids == [copied_id]
		and trace.find(&"card_discard_faded") >= 0
		and trace.find(&"card_added_to_hand") > trace.find(&"card_discard_faded"),
		"Discard fades before one synchronized perfect-copy hand view appears"
	)
	_check(
		trace.find(&"card_flipped") < 0,
		"The production trace never presents a flip after successful prevention"
	)


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


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
