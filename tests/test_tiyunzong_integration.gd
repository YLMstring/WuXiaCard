extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")

const TEST_PROFILE_PATH: String = "user://tiyunzong_integration.json"

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
	await _walk_activation_through_controller(duel)
	duel.queue_free()
	await process_frame
	_cleanup_profile()
	if _failures == 0:
		print("TIYUNZONG_INTEGRATION_PASSED checks=%d" % _checks)
	else:
		push_error(
			"TIYUNZONG_INTEGRATION_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _walk_activation_through_controller(duel: Node) -> void:
	var board: Array = Rules.empty_board()
	board[4] = {
		"card": Catalog.create_instance(
			&"TiYunZong2", Rules.PLAYER_OWNER, &"integration_old_tiyun"
		),
		"owner": Rules.PLAYER_OWNER,
	}
	board[0] = {
		"card": Catalog.create_instance(
			&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"integration_old_ally"
		),
		"owner": Rules.PLAYER_OWNER,
	}
	var attack_target: Dictionary = Rules.make_card(
		"梯云纵攻击目标",
		"integration_attack_target",
		[1, 1, 6, 1],
		[],
		Rules.OPPONENT_OWNER,
		&"integration_attack_target"
	)
	attack_target["instance_id"] = &"integration_attack_target"
	attack_target["ki"] = 0
	attack_target["ki"] = 0
	board[1] = {"card": attack_target, "owner": Rules.OPPONENT_OWNER}
	var state := State.new(
		board,
		[Catalog.create_instance(
			&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"integration_extra_play"
		)],
		[],
		Rules.PLAYER_OWNER
	)
	duel.call("_rebuild_views_from_state", state)
	var old_tiyun_view: Node = duel.board_cards[4]
	var old_ally_view: Node = duel.board_cards[0]
	var committed: bool = await duel.debug_commit_activate(
		Rules.PLAYER_OWNER,
		4,
		0,
		false
	)
	await process_frame
	var new_tiyun_view: Node = duel.board_cards[0]
	var new_ally_view: Node = duel.board_cards[4]
	var new_tiyun_id: StringName = duel.debug_get_board_card_instance_id(0)
	var new_ally_id: StringName = duel.debug_get_board_card_instance_id(4)
	_check(committed, "TiYun activation commits through the production controller")
	_check(
		new_tiyun_view != null
		and StringName((new_tiyun_view.card_data as Dictionary).get("card_id", &""))
		== &"TiYunZong2"
		and new_ally_view != null
		and StringName((new_ally_view.card_data as Dictionary).get("card_id", &""))
		== &"TaiZuChangQuan",
		"Both fresh card views appear in each other's original cell"
	)
	_check(
		new_tiyun_id not in [&"", &"integration_old_tiyun"]
		and new_ally_id not in [&"", &"integration_old_ally"],
		"Production presentation uses both fresh runtime instances"
	)
	_check(
		int((new_tiyun_view.card_data as Dictionary).get("ki", -1)) == 0
		and duel.duel_state.extra_card_plays_remaining == 1,
		"Fresh TiYun view spends ki before the extra play remains available"
	)
	var trace: Array[StringName] = duel.debug_get_presentation_trace()
	_check(
		trace.count(&"card_resummon_faded") == 2
		and trace.count(&"card_summoned") == 2
		and trace.count(&"extra_card_play_granted") == 1
		and trace.rfind(&"card_summoned") < trace.rfind(&"extra_card_play_granted"),
		"Controller presents both departures and summons before the extra-play effect"
	)
	var attack_trace: Array[Dictionary] = duel.debug_get_attack_vfx_trace()
	_check(
		attack_trace.size() == 1
		and StringName(attack_trace[0].get("source_instance_id", &"")) == new_tiyun_id
		and StringName(attack_trace[0].get("target_instance_id", &""))
		== &"integration_attack_target",
		"Fresh TiYun completes its entry attack through production presentation"
	)
	_check(
		not is_instance_valid(old_tiyun_view) and not is_instance_valid(old_ally_view),
		"Both departed CardViews are freed after their fade presentation"
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
