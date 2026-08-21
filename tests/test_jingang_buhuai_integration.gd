extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
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
	await _test_discard_fades_before_same_instance_return(duel)
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


func _test_discard_fades_before_same_instance_return(duel: Node) -> void:
	var board: Array = Rules.empty_board()
	board[4] = {
		"card": Catalog.create_instance(
			&"JinGangBuHuai3",
			Rules.PLAYER_OWNER,
			&"integration_jingang"
		),
		"owner": Rules.PLAYER_OWNER,
	}
	var hand_card: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan",
		Rules.PLAYER_OWNER,
		&"integration_jingang_discard"
	)
	duel.call(
		"_rebuild_views_from_state",
		State.new(board, [hand_card], [], Rules.PLAYER_OWNER)
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
	var hand_view_ids: Array[StringName] = duel.debug_get_hand_view_instance_ids(
		Rules.PLAYER_OWNER
	)
	_check(
		trace.rfind(&"card_discarded") < trace.rfind(&"card_returned_to_hand")
		and &"card_discard_faded" in trace,
		"Discard reuses the fade-out presentation before the recalled card appears"
	)
	_check(
		hand_view_ids == [&"integration_jingang_discard"],
		"Same-instance recall leaves exactly one synchronized hand view"
	)


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
