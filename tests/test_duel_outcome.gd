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
		var gong_stream: AudioStreamWAV = victory_vfx.call("_create_gong_stream") as AudioStreamWAV
		_check(
			gong_stream != null and gong_stream.data.size() == 88200,
			"Victory presentation owns a deterministic one-second gong waveform"
		)
		var settle_time: float = (
			float(victory_vfx.get("entry_duration"))
			+ float(victory_vfx.get("impact_duration"))
			+ float(victory_vfx.get("settle_duration"))
		)
		var fade_time: float = settle_time + float(victory_vfx.get("hold_duration"))
		var finish_time: float = fade_time + float(victory_vfx.get("fade_duration"))
		_check(is_equal_approx(settle_time, 1.10), "Victory presentation settles at 1.10 seconds")
		_check(is_equal_approx(fade_time, 3.00), "Victory presentation starts fading at 3.00 seconds")
		_check(is_equal_approx(finish_time, 4.00), "Victory presentation finishes at 4.00 seconds")
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
	completed_victory.call("debug_complete_victory_vfx")
	await process_frame
	_check(
		not bool(completed_victory.call("debug_is_victory_vfx_playing")),
		"Natural completion path releases the victory input gate"
	)
	_check(
		(completed_victory.get_node("DuelCanvas/TurnStatus") as Label).visible,
		"Natural completion path keeps the final score visible"
	)
	_check(
		(completed_victory.get_node("DuelCanvas/PostMatchReturnButton") as Button).visible,
		"Natural completion path keeps the return action visible"
	)
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
