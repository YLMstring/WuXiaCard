extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")

const TEST_PROFILE_PATH: String = "user://activation_targeting_presentation.json"

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

	await _check_hand_card_still_follows_pointer(duel)
	await _prepare_board_activation(duel)
	await _check_board_activation_stays_anchored(duel)
	await _check_committed_move_and_swap_presentation(duel)

	duel.queue_free()
	await process_frame
	_cleanup_test_profile()
	if _failures == 0:
		print("ACTIVATION_TARGETING_SWAP_PRESENTATION_PASSED checks=%d" % _checks)
	else:
		push_error(
			"ACTIVATION_TARGETING_SWAP_PRESENTATION_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _check_hand_card_still_follows_pointer(duel: Node) -> void:
	var card: Control = duel._get_card_view_for_logical_index(Rules.PLAYER_OWNER, 0)
	var start: Vector2 = card.global_position
	var pointer_start: Vector2 = card.get_global_rect().get_center()
	card._try_begin_drag(pointer_start, -1)
	card._move_drag(pointer_start + Vector2(40.0, 25.0))
	_check(
		card.global_position.distance_to(start) > 10.0,
		"A hand card still follows the pointer while dragged"
	)
	card._try_end_drag(Vector2(-100.0, -100.0), -1)
	await process_frame


func _prepare_board_activation(duel: Node) -> void:
	var player_instance_id: StringName = duel.debug_get_hand_instance_ids(
		Rules.PLAYER_OWNER
	)[0]
	var youfen: Dictionary = Catalog.create_instance(
		&"YouFenLaiYi4",
		Rules.PLAYER_OWNER,
		player_instance_id
	)
	duel.duel_state.get_hand(Rules.PLAYER_OWNER)[0] = youfen
	var youfen_view: Node = duel._get_card_view_for_logical_index(
		Rules.PLAYER_OWNER,
		0
	)
	youfen_view.sync_runtime_data(youfen, Rules.PLAYER_OWNER)
	var played: bool = await duel.debug_commit_move(
		Rules.PLAYER_OWNER,
		0,
		4,
		false
	)
	_check(played, "The activation test card enters the center cell")
	var replied: bool = await duel.debug_commit_move(
		Rules.OPPONENT_OWNER,
		0,
		0,
		false
	)
	_check(replied, "The opponent returns the turn without blocking adjacent cells")


func _check_board_activation_stays_anchored(duel: Node) -> void:
	var card: Control = duel.board_cards[4]
	var original_parent: Node = card.get_parent()
	var original_position: Vector2 = card.position
	var pointer_start: Vector2 = card.get_global_rect().get_center()
	var pointer_end: Vector2 = duel.board_cells[5].get_global_rect().get_center()
	card._try_begin_drag(pointer_start, -1)
	card._move_drag(pointer_end)
	_check(
		card.get_parent() == original_parent,
		"A board activation keeps its source card in the original cell"
	)
	_check(
		card.position.distance_to(original_position) < 0.5,
		"A board activation does not physically follow the pointer"
	)
	_check(
		duel.has_method("debug_has_targeting_trace")
		and duel.debug_has_targeting_trace(),
		"A live targeting trace is visible during a board activation drag"
	)
	if duel.has_method("debug_get_targeting_trace_end"):
		_check(
			duel.debug_get_targeting_trace_end().distance_to(pointer_end) < 1.0,
			"The targeting trace follows the pointer"
		)
	else:
		_check(false, "The targeting trace exposes its endpoint for verification")
	card._try_end_drag(Vector2(-100.0, -100.0), -1)
	await process_frame
	_check(
		duel.has_method("debug_has_targeting_trace")
		and not duel.debug_has_targeting_trace(),
		"An invalid release removes the targeting trace"
	)


func _check_committed_move_and_swap_presentation(duel: Node) -> void:
	duel.movement_duration = 0.01
	duel.swap_duration = 0.01
	var source_instance_id: StringName = duel.debug_get_board_card_instance_id(4)
	var source_view: Control = duel.board_cards[4]
	var sound_start: int = duel.debug_get_movement_sound_count()
	var moved: bool = await duel.debug_commit_activate(
		Rules.PLAYER_OWNER,
		4,
		5,
		false,
		0
	)
	_check(moved, "An empty-cell activation commits through the production controller")
	_check(
		duel.board_cards[5] == source_view
		and duel.debug_get_board_card_instance_id(5) == source_instance_id,
		"The real card view moves only after the target is committed"
	)

	var opponent_instance_id: StringName = duel.debug_get_hand_instance_ids(
		Rules.OPPONENT_OWNER
	)[0]
	var weak_target: Dictionary = Catalog.create_instance(
		&"CangSongYingKe2",
		Rules.OPPONENT_OWNER,
		opponent_instance_id
	)
	weak_target["powers"] = [0, 0, 0, 0]
	duel.duel_state.get_hand(Rules.OPPONENT_OWNER)[0] = weak_target
	var opponent_view: Node = duel._get_card_view_for_logical_index(
		Rules.OPPONENT_OWNER,
		0
	)
	opponent_view.sync_runtime_data(weak_target, Rules.OPPONENT_OWNER)
	var target_played: bool = await duel.debug_commit_move(
		Rules.OPPONENT_OWNER,
		0,
		2,
		false
	)
	_check(target_played, "A weak enemy target enters beside the activating card")
	var target_view: Control = duel.board_cards[2]
	var swapped: bool = await duel.debug_commit_activate(
		Rules.PLAYER_OWNER,
		5,
		2,
		false,
		2
	)
	_check(swapped, "An enemy-swap activation commits through the production controller")
	_check(
		duel.board_cards[2] == source_view and duel.board_cards[5] == target_view,
		"The reciprocal swap preserves both real card views"
	)
	_check(
		int((source_view.card_data as Dictionary).get("ki", -1)) == 0,
		"The moved source view retains its synchronized runtime ki"
	)
	var movement_trace: Array[Dictionary] = duel.debug_get_movement_presentation_trace()
	_check(
		movement_trace.size() == 2
		and StringName(movement_trace[0].get("kind", &"")) == &"move"
		and StringName(movement_trace[1].get("kind", &"")) == &"swap",
		"An ordinary move and a reciprocal swap use distinct presentation paths"
	)
	_check(
		float(movement_trace[1].get("arc_amount", 0.0)) > 0.0,
		"The reciprocal swap uses shallow opposing arcs"
	)
	_check(
		duel.debug_get_movement_sound_count() == sound_start + 2,
		"Each committed move or swap plays the movement sound exactly once"
	)
	_check(
		duel.drag_layer.get_node_or_null("MovementBrushTrail") == null,
		"Committed movement creates no brush trail"
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
