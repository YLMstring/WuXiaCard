extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")

const TEST_PROFILE_PATH: String = "user://taishan_wudafu_integration.json"

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_test_profile()
	var duel: Node = DUEL_SCENE.instantiate()
	duel.set("deck_profile_path", TEST_PROFILE_PATH)
	duel.set("testing_mode", true)
	duel.set("opponent_hand_shuffle_seed", -1)
	var opponent_ids: Array[StringName] = [
		&"CangSongYingKe2",
		&"gate_general",
		&"meng_huo",
		&"YouFenLaiYi2",
		&"TuNaShu2",
	]
	duel.opponent_card_ids = opponent_ids
	root.add_child(duel)
	await process_frame
	await process_frame
	duel.debug_set_fast_mode(true)
	duel.snap_duration = 0.02
	duel.ability_trigger_pulse_duration = 0.02
	duel.swap_duration = 0.02
	duel.summon_swap_readable_duration = 0.10

	duel.duel_state.active_player = Rules.OPPONENT_OWNER
	var opponent_instance_id: StringName = duel.debug_get_hand_instance_ids(
		Rules.OPPONENT_OWNER
	)[0]
	var opponent_played: bool = await duel.debug_commit_move(
		Rules.OPPONENT_OWNER,
		0,
		5,
		false
	)
	_check(opponent_played, "Opponent card enters the sole adjacent square")

	var player_instance_id: StringName = duel.debug_get_hand_instance_ids(
		Rules.PLAYER_OWNER
	)[0]
	var taishan: Dictionary = Catalog.create_instance(
		&"TaiShan18Pan2",
		Rules.PLAYER_OWNER,
		player_instance_id
	)
	duel.duel_state.get_hand(Rules.PLAYER_OWNER)[0] = taishan
	var taishan_view: Node = duel._get_card_view_for_logical_index(
		Rules.PLAYER_OWNER,
		0
	)
	taishan_view.sync_runtime_data(taishan, Rules.PLAYER_OWNER)

	var presentation_started_msec: int = Time.get_ticks_msec()
	var taishan_played: bool = await duel.debug_commit_move(
		Rules.PLAYER_OWNER,
		0,
		4,
		false
	)
	var presentation_elapsed: float = (
		float(Time.get_ticks_msec() - presentation_started_msec) / 1000.0
	)
	_check(taishan_played, "TaiShan18Pan2 enters through the production controller")
	_check(
		presentation_elapsed >= 0.10,
		"TaiShan remains readable in its original slot before its swap begins"
	)
	_check(
		duel.debug_get_ability_pulse_trace().has(player_instance_id),
		"TaiShan pulses in its original slot before the movement event"
	)
	_check(
		_instance_at(duel, 5) == player_instance_id
		and _instance_at(duel, 4) == opponent_instance_id,
		"Production simulator swaps the two logical cards"
	)
	_check(
		duel.debug_get_board_card_instance_id(5) == player_instance_id
		and duel.debug_get_board_card_instance_id(4) == opponent_instance_id,
		"Production controller remaps both card views after a summon-triggered swap"
	)

	duel.queue_free()
	await process_frame
	_cleanup_test_profile()
	if _failures == 0:
		print("TAISHAN_WUDAFU_INTEGRATION_PASSED checks=%d" % _checks)
	else:
		push_error(
			"TAISHAN_WUDAFU_INTEGRATION_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _instance_at(duel: Node, cell_index: int) -> StringName:
	var slot_value: Variant = duel.duel_state.board[cell_index]
	if slot_value == null:
		return &""
	return StringName(
		((slot_value as Dictionary).get("card", {}) as Dictionary).get(
			"instance_id",
			&""
		)
	)


func _cleanup_test_profile() -> void:
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
