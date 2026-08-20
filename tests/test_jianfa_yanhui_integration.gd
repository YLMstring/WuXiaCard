extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")

const TEST_PROFILE_PATH: String = "user://jianfa_yanhui_integration.json"

var _failures: int = 0
var _checks: int = 0


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
	await _test_exact_hand_card_moves_to_board(duel)
	duel.queue_free()
	await process_frame
	_cleanup_profile()
	if _failures == 0:
		print("JIANFA_YANHUI_INTEGRATION_PASSED checks=%d" % _checks)
	else:
		push_error(
			"JIANFA_YANHUI_INTEGRATION_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_exact_hand_card_moves_to_board(duel: Node) -> void:
	var board: Array = Rules.empty_board()
	var yanhui: Dictionary = Catalog.create_instance(
		&"YanHuiZhuRong3", Rules.OPPONENT_OWNER, &"integration_yanhui"
	)
	board[5] = {"card": yanhui, "owner": Rules.OPPONENT_OWNER}
	var attacker: Dictionary = Catalog.create_instance(
		&"CangSongYingKe1", Rules.PLAYER_OWNER, &"integration_attacker"
	)
	attacker["powers"] = [1, 9, 1, 1]
	var light_sword: Dictionary = Catalog.create_instance(
		&"JianFaQinYin1", Rules.OPPONENT_OWNER, &"integration_light"
	)
	var state := State.new(board, [attacker], [light_sword], Rules.PLAYER_OWNER)
	duel.call("_rebuild_views_from_state", state)
	var committed: bool = await duel.debug_commit_move(
		Rules.PLAYER_OWNER,
		0,
		4,
		false
	)
	var hand_view_ids: Array[StringName] = duel.debug_get_hand_view_instance_ids(
		Rules.OPPONENT_OWNER
	)
	_check(committed, "YanHui replacement commits through the production controller")
	_check(
		duel.debug_get_board_card_instance_id(5) == &"integration_light",
		"The exact selected hand view becomes the board view"
	)
	_check(
		&"integration_light" not in hand_view_ids and hand_view_ids.size() == 1,
		"The moved hand view leaves no stale duplicate behind"
	)
	_check(
		StringName((duel.duel_state.get_hand(Rules.OPPONENT_OWNER)[0] as Dictionary).get("card_id", &""))
		== &"YanHuiZhuRong3",
		"The returned YanHui fresh copy has a synchronized hand view"
	)
	var trace: Array[StringName] = duel.debug_get_presentation_trace()
	_check(
		trace.rfind(&"card_returned_to_hand") < trace.rfind(&"card_summoned"),
		"YanHui return presentation precedes the replacement summon"
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
