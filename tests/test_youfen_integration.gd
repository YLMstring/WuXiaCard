extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Action = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")

const TEST_PROFILE_PATH: String = "user://youfen_integration_profile.json"

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
	var opponent_ids: Array[StringName] = [
		&"CangSongYingKe2",
		&"LeiZHenJian1",
		&"KuiHua1",
		&"YouFenLaiYi2",
		&"TuNaShu2",
	]
	duel.opponent_card_ids = opponent_ids
	root.add_child(duel)
	await process_frame
	await process_frame
	duel.debug_set_fast_mode(true)
	var source_instance_id: StringName = duel.debug_get_hand_instance_ids(
		Rules.PLAYER_OWNER
	)[3]
	var youfen: Dictionary = Catalog.create_instance(
		&"YouFenLaiYi4",
		Rules.PLAYER_OWNER,
		source_instance_id
	)
	duel.duel_state.get_hand(Rules.PLAYER_OWNER)[3] = youfen
	var source_hand_view: Node = duel._get_card_view_for_logical_index(
		Rules.PLAYER_OWNER,
		3
	)
	source_hand_view.sync_runtime_data(youfen, Rules.PLAYER_OWNER)

	var placed_source: bool = await duel.debug_commit_move(
		Rules.PLAYER_OWNER,
		3,
		4,
		false
	)
	_check(placed_source, "Tier-four 有凤来仪 enters through the production play path")
	var board_views: Array = duel.get("board_cards") as Array
	var source_view: Control = board_views[4] as Control
	source_instance_id = duel.debug_get_board_card_instance_id(4)

	var target_hand_instance_id: StringName = duel.debug_get_hand_instance_ids(
		Rules.OPPONENT_OWNER
	)[1]
	var weak_target: Dictionary = Catalog.create_instance(
		&"CangSongYingKe2",
		Rules.OPPONENT_OWNER,
		target_hand_instance_id
	)
	weak_target["powers"] = [0, 0, 0, 0]
	duel.duel_state.get_hand(Rules.OPPONENT_OWNER)[1] = weak_target
	var weak_target_view: Node = duel._get_card_view_for_logical_index(
		Rules.OPPONENT_OWNER,
		1
	)
	weak_target_view.sync_runtime_data(weak_target, Rules.OPPONENT_OWNER)
	var placed_target: bool = await duel.debug_commit_move(
		Rules.OPPONENT_OWNER,
		1,
		5,
		false
	)
	_check(placed_target, "Enemy target enters adjacent through the production play path")
	board_views = duel.get("board_cards") as Array
	var target_view: Control = board_views[5] as Control
	var target_instance_id: StringName = duel.debug_get_board_card_instance_id(5)
	source_view.call("_try_begin_drag", source_view.get_global_rect().get_center(), -1)
	var drag_action: Action = duel.call("_make_drag_action", source_view, 5) as Action
	_check(
		drag_action != null and drag_action.activation_index == 2,
		"Board drag selects the first catalog-ordered legal activation for its target"
	)
	duel.call("_return_card_home", source_view)
	duel.call("_clear_drag_context")
	var trace_start: int = duel.debug_get_presentation_trace().size()
	var attack_start: int = duel.debug_get_attack_vfx_trace().size()

	var activated: bool = await duel.debug_commit_activate(
		Rules.PLAYER_OWNER,
		4,
		5,
		false,
		2
	)
	_check(activated, "Controller executes the indexed enemy-swap activation")
	board_views = duel.get("board_cards") as Array
	_check(
		board_views[5] == source_view
		and duel.debug_get_board_card_instance_id(5) == source_instance_id,
		"Controller preserves A's view and places it in B's original square"
	)
	_check(
		board_views[4] == target_view
		and duel.debug_get_board_card_instance_id(4) == target_instance_id,
		"Controller preserves B's view and places it in A's original square"
	)
	_check(
		is_instance_valid(source_view) and is_instance_valid(target_view),
		"Swap creates no disappear or reconstruction presentation"
	)
	var source_ki: int = int((source_view.get("card_data") as Dictionary).get("ki", -1))
	_check(source_ki == 1, "Swapping spends one ki and synchronizes A's existing view")

	var trace: Array[StringName] = duel.debug_get_presentation_trace()
	var swap_trace: Array[StringName] = trace.slice(trace_start)
	_check(
		swap_trace == [
			&"ability_activated",
			&"ki_changed",
			&"card_moved",
			&"card_moved",
			&"attack_started",
			&"card_flipped",
		],
		"Presentation observes both ordered moves before the standard attack"
	)
	var attack_trace: Array[Dictionary] = duel.debug_get_attack_vfx_trace()
	_check(
		attack_trace.size() == attack_start + 1
		and StringName(attack_trace[-1].get("source_instance_id", &"")) == source_instance_id
		and StringName(attack_trace[-1].get("target_instance_id", &"")) == target_instance_id,
		"Attack VFX originates from A and targets the displaced enemy"
	)

	duel.queue_free()
	await process_frame
	_cleanup_profile()
	if _failures == 0:
		print("YOUFEN_INTEGRATION_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("YOUFEN_INTEGRATION_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


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
