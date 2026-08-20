extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

const TEST_PROFILE_PATH: String = "user://jinzhen_wanhua_integration.json"

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
	duel.set("opening_layout_seed", -1)
	root.add_child(duel)
	await process_frame
	await process_frame
	_configure_short_presentations(duel)
	await _test_return_fades_before_hand_appearance(duel)
	await _test_generated_copy_gets_a_board_view(duel)
	await _test_self_exile_fades_without_external_exile_animation(duel)
	duel.queue_free()
	await process_frame
	_cleanup_profile()
	if _failures == 0:
		print("JINZHEN_WANHUA_INTEGRATION_PASSED checks=%d" % _checks)
	else:
		push_error(
			"JINZHEN_WANHUA_INTEGRATION_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _configure_short_presentations(duel: Node) -> void:
	duel.set("snap_duration", 0.0)
	duel.set("capture_flip_duration", 0.0)
	duel.set("attack_vfx_duration", 0.0)
	duel.set("ability_trigger_pulse_duration", 0.0)
	duel.set("draw_bloom_duration", 0.0)
	duel.set("draw_rise_duration", 0.0)
	duel.set("draw_post_effect_gap", 0.0)
	duel.set("exile_step_delay", 0.0)
	duel.set("card_fade_duration", 0.06)


func _test_return_fades_before_hand_appearance(duel: Node) -> void:
	var target: Dictionary = Catalog.create_instance(
		&"TianChangZhang3", Rules.PLAYER_OWNER, &"integration_return_target"
	)
	var board: Array = Rules.empty_board()
	board[0] = _slot(target, Rules.OPPONENT_OWNER, Rules.PLAYER_OWNER)
	var state := State.new(
		board,
		[Catalog.create_instance(&"JinZhenDuJie2", Rules.PLAYER_OWNER, &"integration_jin")],
		[_plain(&"integration_reply")],
		Rules.PLAYER_OWNER
	)
	duel.call("_rebuild_views_from_state", state)
	var committed: bool = await duel.debug_commit_move(Rules.PLAYER_OWNER, 0, 8, false)
	var trace: Array[StringName] = duel.debug_get_presentation_trace()
	_check(committed, "JinZhen return commits through the production controller")
	_check(trace.rfind(&"card_return_faded") < trace.rfind(&"card_added_to_hand"), "Returned card fades before its fresh hand view appears")
	_check(not duel.debug_has_board_card_view(0), "Returned board view is removed")
	_check(duel.debug_get_hand_view_instance_ids(Rules.PLAYER_OWNER).size() == 1, "Fresh returned hand view is created")


func _test_generated_copy_gets_a_board_view(duel: Node) -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(&"WanHuaJian2", Rules.PLAYER_OWNER, &"integration_wan"), Rules.PLAYER_OWNER)
	board[0] = _slot(_plain(&"integration_copy_target"), Rules.OPPONENT_OWNER)
	var state := State.new(
		board,
		[],
		[_plain(&"integration_attacker", [1, 1, 9, 1])],
		Rules.OPPONENT_OWNER
	)
	duel.call("_rebuild_views_from_state", state)
	var committed: bool = await duel.debug_commit_move(Rules.OPPONENT_OWNER, 0, 1, false)
	_check(committed and duel.debug_has_board_card_view(3), "Generated WanHua copy receives a live board view")
	_check(duel.debug_get_board_card_instance_id(3) == _instance_at(duel, 3), "Generated view stays synchronized with simulator identity")
	_check(&"card_summoned" in duel.debug_get_presentation_trace(), "Generated summon uses its dedicated presentation event")


func _test_self_exile_fades_without_external_exile_animation(duel: Node) -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(Catalog.create_instance(&"WanHuaJian1", Rules.OPPONENT_OWNER, &"integration_loser"), Rules.OPPONENT_OWNER)
	for cell: int in [1, 2, 3]:
		board[cell] = _slot(_plain(StringName("integration_enemy_%d" % cell), [9, 9, 9, 9]), Rules.OPPONENT_OWNER)
	for cell: int in [4, 5, 6, 7]:
		board[cell] = _slot(_plain(StringName("integration_ally_%d" % cell), [9, 9, 9, 9]), Rules.PLAYER_OWNER)
	var state := State.new(
		board,
		[_plain(&"integration_ninth")],
		[_plain(&"integration_next")],
		Rules.PLAYER_OWNER
	)
	duel.call("_rebuild_views_from_state", state)
	var committed: bool = await duel.debug_commit_move(Rules.PLAYER_OWNER, 0, 8, false)
	var trace: Array[StringName] = duel.debug_get_presentation_trace()
	_check(committed and not duel.debug_has_board_card_view(0), "WanHua self-removal clears its board view")
	_check(&"card_self_faded" in trace, "WanHua self-removal uses the fade path")
	_check(not Simulator.is_terminal(duel.duel_state), "Fade-backed self-removal reopens the duel")


func _instance_at(duel: Node, cell: int) -> StringName:
	var value: Variant = duel.duel_state.board[cell]
	if value == null:
		return &""
	return StringName(((value as Dictionary).get("card", {}) as Dictionary).get("instance_id", &""))


func _plain(instance_id: StringName, powers: Array[int] = [1, 1, 1, 1]) -> Dictionary:
	var card: Dictionary = Rules.make_card(String(instance_id), "测", powers, [], Rules.PLAYER_OWNER)
	card["instance_id"] = instance_id
	return card


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
