extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")

const TEST_PROFILE_PATH: String = "user://mianli_cangzhen3_integration.json"

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_profile()
	var duel: Node = DUEL_SCENE.instantiate()
	duel.set("deck_profile_path", TEST_PROFILE_PATH)
	duel.set("testing_mode", true)
	duel.set("opponent_hand_shuffle_seed", -1)
	root.add_child(duel)
	await process_frame
	await process_frame
	duel.set("snap_duration", 0.0)
	duel.set("capture_flip_duration", 0.0)
	duel.set("attack_vfx_duration", 0.0)
	duel.set("ability_trigger_pulse_duration", 0.0)
	duel.set("draw_bloom_duration", 0.0)
	duel.set("draw_rise_duration", 0.0)
	duel.set("draw_post_effect_gap", 0.0)
	duel.set("card_fade_duration", 0.04)
	await _test_old_view_fades_before_fresh_summon(duel)
	duel.queue_free()
	await process_frame
	_cleanup_profile()
	if _failures == 0:
		print("MIANLI_CANGZHEN3_INTEGRATION_PASSED checks=%d" % _checks)
	else:
		push_error(
			"MIANLI_CANGZHEN3_INTEGRATION_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_old_view_fades_before_fresh_summon(duel: Node) -> void:
	var target: Dictionary = Catalog.create_instance(
		&"TuNaShu1",
		Rules.PLAYER_OWNER,
		&"integration_old_target"
	)
	var board: Array = Rules.empty_board()
	board[1] = _slot(target, Rules.OPPONENT_OWNER, Rules.PLAYER_OWNER)
	var source: Dictionary = Catalog.create_instance(
		&"MianLiCangZhen3",
		Rules.PLAYER_OWNER,
		&"integration_mianli"
	)
	var state := State.new(board, [source], [], Rules.PLAYER_OWNER)
	duel.call("_rebuild_views_from_state", state)
	var committed: bool = await duel.debug_commit_move(Rules.PLAYER_OWNER, 0, 4, false)
	var trace: Array[StringName] = duel.debug_get_presentation_trace()
	var faded_index: int = trace.rfind(&"card_resummon_faded")
	var summon_index: int = trace.rfind(&"card_summoned")
	_check(committed, "MianLi resummon commits through the production controller")
	_check(faded_index >= 0 and faded_index < summon_index, "Old view fades before the fresh ink summon")
	_check(duel.debug_has_board_card_view(1), "Fresh resummoned card receives a live board view")
	_check(duel.debug_get_board_card_instance_id(1) == _instance_at(duel, 1), "Fresh board view matches simulator identity")
	_check(duel.debug_get_board_card_instance_id(1) != &"integration_old_target", "Production view no longer uses the old identity")


func _instance_at(duel: Node, cell: int) -> StringName:
	var value: Variant = duel.duel_state.board[cell]
	if value == null:
		return &""
	return StringName(((value as Dictionary).get("card", {}) as Dictionary).get("instance_id", &""))


func _slot(card: Dictionary, owner_id: int, original_owner: int = 0) -> Dictionary:
	card["original_owner"] = owner_id if original_owner == 0 else original_owner
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
