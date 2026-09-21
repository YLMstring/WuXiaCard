extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Rules = preload("res://scripts/duel_rules.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var abandoned_outcome: Dictionary = {"value": &""}
	var active_duel: Node = DUEL_SCENE.instantiate()
	active_duel.set("testing_mode", true)
	active_duel.set("opening_layout_seed", -1)
	root.add_child(active_duel)
	await process_frame
	active_duel.return_requested.connect(
		func(outcome: StringName) -> void: abandoned_outcome["value"] = outcome
	)
	(active_duel.get_node("DuelCanvas/TopBar/ExitButton") as Button).pressed.emit()
	_check(abandoned_outcome["value"] == &"abandoned", "Leaving an active duel reports abandonment")
	active_duel.queue_free()
	await process_frame

	var victory_outcome: Dictionary = {"value": &"", "count": 0}
	var victory_duel: Node = DUEL_SCENE.instantiate()
	victory_duel.set("testing_mode", true)
	victory_duel.set("opening_layout_seed", -1)
	root.add_child(victory_duel)
	await process_frame
	var victory_board: Array = Rules.empty_board()
	victory_board[0] = {"owner": Rules.PLAYER_OWNER, "card": {}}
	victory_duel.set("board", victory_board)
	victory_duel.call("_finish_match")
	_check(victory_duel.debug_get_match_outcome() == &"victory", "Higher player score records victory")
	var victory_vfx := victory_duel.get_node_or_null("VictoryVfx") as Control
	_check(victory_vfx != null, "Duel scene owns the victory presentation overlay")
	if victory_vfx != null:
		var victory_emblem := victory_vfx.get_node_or_null("VictoryEmblem") as TextureRect
		_check(
			victory_emblem != null and victory_emblem.texture != null,
			"Victory presentation owns the approved red-gold emblem texture"
		)
		var gong_player := victory_vfx.get_node("GongPlayer") as AudioStreamPlayer
		_check(
			gong_player.stream is AudioStreamMP3
			and gong_player.stream.resource_path == "res://music/luo.mp3",
			"Victory presentation uses the approved gong recording"
		)
		var settle_time: float = (
			float(victory_vfx.get("entry_duration"))
			+ float(victory_vfx.get("impact_duration"))
			+ float(victory_vfx.get("settle_duration"))
		)
		var fade_time: float = settle_time + float(victory_vfx.get("hold_duration"))
		var finish_time: float = fade_time + float(victory_vfx.get("fade_duration"))
		var impact_time: float = (
			float(victory_vfx.get("entry_duration"))
			+ float(victory_vfx.get("impact_duration"))
		)
		_check(is_equal_approx(impact_time, 0.70), "Victory emblem impacts at 0.70 seconds")
		var has_gong_timing_api: bool = victory_vfx.has_method("debug_get_gong_start_time")
		_check(has_gong_timing_api, "Victory presentation exposes deterministic gong timing")
		if has_gong_timing_api:
			var gong_start_time: float = float(victory_vfx.call("debug_get_gong_start_time"))
			_check(
				is_equal_approx(gong_start_time, 0.60)
				and is_equal_approx(gong_start_time + 0.10, impact_time),
				"Gong starts early enough for its measured 0.10-second strike peak to meet impact"
			)
		_check(is_equal_approx(settle_time, 1.10), "Victory presentation settles at 1.10 seconds")
		_check(is_equal_approx(fade_time, 3.00), "Victory presentation starts fading at 3.00 seconds")
		_check(is_equal_approx(finish_time, 4.00), "Victory presentation finishes at 4.00 seconds")
		var has_smash_curve_api: bool = victory_vfx.has_method("debug_get_smash_scale")
		_check(has_smash_curve_api, "Victory presentation exposes its deterministic smash curve")
		if has_smash_curve_api:
			var smash_duration: float = (
				float(victory_vfx.get("entry_duration"))
				+ float(victory_vfx.get("impact_duration"))
			)
			var boundary_time: float = float(victory_vfx.get("entry_duration"))
			var boundary_progress: float = boundary_time / smash_duration
			var curved_boundary_progress: float = (
				0.22 * boundary_progress
				+ 0.78 * boundary_progress * boundary_progress * boundary_progress
			)
			_check(
				is_equal_approx(float(victory_vfx.call("debug_get_smash_scale", 0.0)), 2.0)
				and is_equal_approx(
					float(victory_vfx.call("debug_get_smash_scale", boundary_time)),
					lerpf(2.0, 0.90, curved_boundary_progress)
				)
				and is_equal_approx(
					float(victory_vfx.call("debug_get_smash_scale", smash_duration)),
					0.90
				),
				"Victory emblem keeps one continuous accelerating depth-smash trajectory"
			)
		var rebound_duration_value: Variant = victory_vfx.get("rebound_duration")
		var recovery_duration_value: Variant = victory_vfx.get("recovery_duration")
		_check(
			rebound_duration_value != null
			and recovery_duration_value != null
			and is_equal_approx(float(rebound_duration_value), 0.12)
			and is_equal_approx(float(recovery_duration_value), 0.14),
			"Victory impact uses a short explicit rebound instead of a soft back ease"
		)
		_check(
			victory_emblem != null
			and victory_emblem.scale.is_equal_approx(Vector2(2.0, 2.0)),
			"Victory emblem begins at the enlarged 2.0 scale"
		)
		var fallback_glyph := victory_vfx.get_node("FallbackGlyph") as Label
		var impact_flash := victory_vfx.get_node_or_null("ImpactFlash") as ColorRect
		var impact_ring := victory_vfx.get_node_or_null("ImpactRing") as ColorRect
		var impact_flash_material := impact_flash.material as ShaderMaterial if impact_flash != null else null
		var impact_flash_shader := impact_flash_material.shader if impact_flash_material != null else null
		_check(
			impact_flash != null
			and impact_ring != null
			and impact_flash_material != null
			and impact_ring.material is ShaderMaterial
			and impact_flash.z_index < victory_emblem.z_index
			and impact_ring.z_index < victory_emblem.z_index,
			"Victory impact keeps every animated light layer behind the emblem"
		)
		_check(
			impact_flash_shader != null
			and impact_flash_shader.code.contains("center_cutout"),
			"Victory impact burst explicitly masks the emblem center"
		)
		_check(
			victory_emblem != null
			and victory_emblem.position.is_equal_approx(
				victory_vfx.get("_emblem_rest_position") as Vector2
			)
			and fallback_glyph.position.is_equal_approx(
				victory_vfx.get("_fallback_rest_position") as Vector2
			),
			"Victory emblem and fallback remain centered without screen-space descent"
		)
	_check(
		bool(victory_duel.call("debug_is_victory_vfx_playing")),
		"Victory starts the presentation before terminal controls appear"
	)
	_check(
		not (victory_duel.get_node("DuelCanvas/TurnStatus") as Label).visible,
		"Victory presentation hides the final score text"
	)
	_check(
		not (victory_duel.get_node("DuelCanvas/PostMatchReturnButton") as Button).visible,
		"Victory presentation hides the return action"
	)
	victory_duel.return_requested.connect(
		func(outcome: StringName) -> void:
			victory_outcome["value"] = outcome
			victory_outcome["count"] = int(victory_outcome["count"]) + 1
	)
	(victory_duel.get_node("DuelCanvas/TopBar/ExitButton") as Button).pressed.emit()
	_check(victory_outcome["value"] == &"", "Victory presentation blocks leaving the duel")
	(victory_duel.get_node("DuelCanvas/PostMatchReturnButton") as Button).pressed.emit()
	_check(victory_outcome["value"] == &"", "Victory presentation blocks early return before settling")
	var first_play_count: int = int(victory_vfx.call("debug_get_play_count"))
	victory_duel.call("_finish_match")
	_check(
		int(victory_vfx.call("debug_get_play_count")) == first_play_count,
		"Repeated terminal checks do not stack victory presentations"
	)
	victory_duel.call("debug_settle_victory_vfx")
	await process_frame
	var settled_emblem := victory_vfx.get_node("VictoryEmblem") as TextureRect
	var settled_emblem_position: Vector2 = settled_emblem.position
	for frame_index: int in range(3):
		await process_frame
	_check(
		settled_emblem.position.is_equal_approx(settled_emblem_position)
		and settled_emblem.scale.is_equal_approx(Vector2.ONE),
		"Forced settle prevents the smash tween from restoring an in-flight visual"
	)
	_check(
		bool(victory_duel.call("debug_is_victory_vfx_playing")),
		"Settling the victory presentation keeps the remaining effect active"
	)
	_check(
		(victory_duel.get_node("DuelCanvas/TurnStatus") as Label).visible,
		"Settling the victory presentation reveals the final score text"
	)
	_check(
		(victory_duel.get_node("DuelCanvas/PostMatchReturnButton") as Button).visible,
		"Settling the victory presentation reveals the return action"
	)
	_check(
		(victory_duel.get_node("DuelCanvas/PostMatchReturnButton") as Button).z_index > victory_vfx.z_index,
		"Settled return action stays above the victory input blocker"
	)
	(victory_duel.get_node("DuelCanvas/TopBar/ExitButton") as Button).pressed.emit()
	_check(victory_outcome["value"] == &"", "Top exit remains blocked while the settled effect is playing")
	(victory_duel.get_node("DuelCanvas/PostMatchReturnButton") as Button).pressed.emit()
	_check(
		not bool(victory_duel.call("debug_is_victory_vfx_playing")),
		"Settled return action cancels the remaining victory effect"
	)
	(victory_duel.get_node("DuelCanvas/PostMatchReturnButton") as Button).pressed.emit()
	(victory_duel.get_node("DuelCanvas/TopBar/ExitButton") as Button).pressed.emit()
	_check(victory_outcome["value"] == &"victory", "Early return after settling reports victory")
	_check(int(victory_outcome["count"]) == 1, "Repeated return presses emit one result")
	victory_duel.queue_free()
	await process_frame

	var completed_victory: Node = DUEL_SCENE.instantiate()
	completed_victory.set("testing_mode", true)
	completed_victory.set("opening_layout_seed", -1)
	root.add_child(completed_victory)
	await process_frame
	var completed_board: Array = Rules.empty_board()
	completed_board[0] = {"owner": Rules.PLAYER_OWNER, "card": {}}
	completed_victory.set("board", completed_board)
	completed_victory.call("_finish_match")
	var completed_vfx := completed_victory.get_node("VictoryVfx") as Control
	var detached_gong := completed_vfx.call("_spawn_gong_one_shot") as AudioStreamPlayer
	_check(
		detached_gong != null
		and detached_gong.get_parent() == root
		and detached_gong.playing,
		"Victory impact starts a detached gong one-shot"
	)
	completed_victory.call("debug_complete_victory_vfx")
	await process_frame
	_check(
		not bool(completed_victory.call("debug_is_victory_vfx_playing")),
		"Natural completion path releases the victory input gate"
	)
	_check(
		is_instance_valid(detached_gong) and detached_gong.playing,
		"Victory completion leaves the detached gong playing to its end"
	)
	_check(
		(completed_victory.get_node("DuelCanvas/TurnStatus") as Label).visible,
		"Natural completion path keeps the final score visible"
	)
	_check(
		(completed_victory.get_node("DuelCanvas/PostMatchReturnButton") as Button).visible,
		"Natural completion path keeps the return action visible"
	)
	if is_instance_valid(detached_gong):
		detached_gong.stop()
		detached_gong.queue_free()
	completed_victory.queue_free()
	await process_frame

	var replay_victory: Node = DUEL_SCENE.instantiate()
	replay_victory.set("testing_mode", true)
	replay_victory.set("opening_layout_seed", -1)
	root.add_child(replay_victory)
	await process_frame
	var replay_board: Array = Rules.empty_board()
	replay_board[0] = {"owner": Rules.PLAYER_OWNER, "card": {}}
	replay_victory.set("board", replay_board)
	replay_victory.set("_is_replaying", true)
	replay_victory.call("_finish_match")
	var replay_vfx := replay_victory.get_node("VictoryVfx") as Control
	_check(
		int(replay_vfx.call("debug_get_play_count")) == 0,
		"Reaching victory during replay skips the victory presentation"
	)
	_check(
		not bool(replay_victory.call("debug_is_victory_vfx_playing")),
		"Replay victory terminal has no active victory input gate"
	)
	_check(
		(replay_victory.get_node("DuelCanvas/TurnStatus") as Label).visible,
		"Replay victory terminal shows the final score immediately"
	)
	replay_victory.set("_is_replaying", false)
	replay_victory.call("_sync_terminal_hand_action")
	_check(
		(replay_victory.get_node("DuelCanvas/PostMatchReturnButton") as Button).visible,
		"Leaving replay mode exposes the final return action"
	)
	replay_victory.queue_free()
	await process_frame

	var defeat_outcome: Dictionary = {"value": &""}
	var defeat_duel: Node = DUEL_SCENE.instantiate()
	defeat_duel.set("testing_mode", true)
	defeat_duel.set("opening_layout_seed", -1)
	root.add_child(defeat_duel)
	await process_frame
	defeat_duel.set("board", Rules.empty_board())
	defeat_duel.call("_finish_match")
	_check(defeat_duel.debug_get_match_outcome() == &"defeat", "A tie records defeat")
	_check(
		not bool(defeat_duel.call("debug_is_victory_vfx_playing")),
		"Defeat does not start the victory presentation"
	)
	_check(
		(defeat_duel.get_node("DuelCanvas/TurnStatus") as Label).visible,
		"Defeat keeps the final score text visible"
	)
	_check(
		(defeat_duel.get_node("DuelCanvas/PostMatchReturnButton") as Button).visible,
		"Defeat keeps the return action visible"
	)
	defeat_duel.return_requested.connect(
		func(outcome: StringName) -> void: defeat_outcome["value"] = outcome
	)
	(defeat_duel.get_node("DuelCanvas/TopBar/ExitButton") as Button).pressed.emit()
	_check(defeat_outcome["value"] == &"defeat", "Returning after a loss reports defeat")
	defeat_duel.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if _failures == 0:
		print("DUEL_OUTCOME_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("DUEL_OUTCOME_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
