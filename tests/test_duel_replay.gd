extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Simulator = preload("res://scripts/duel_simulator.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")
const ActionData = preload("res://scripts/duel_action.gd")
const Rules = preload("res://scripts/duel_rules.gd")

var _checks: int = 0
var _failures: int = 0
var _memory_emissions: int = 0
var _save_path: String = "user://duel_replay_test.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var duel: DuelController = DUEL_SCENE.instantiate() as DuelController
	duel.deck_profile_path = _save_path
	duel.testing_mode = false
	duel.side_deck_shuffle_seed = 8841
	duel.opponent_hand_shuffle_seed = -1
	duel.replay_turn_delay = 0.01
	duel.opponent_card_played.connect(func(_glyph: String) -> void: _memory_emissions += 1)
	root.add_child(duel)
	await process_frame
	await process_frame
	duel.debug_set_fast_mode(true)
	duel.call("_layout_duel")

	var replay_button := duel.get_node_or_null("DuelCanvas/ReplayButton") as Button
	var replay_icon := duel.get_node_or_null("DuelCanvas/ReplayButton/ReplayIcon") as TextureRect
	_check(replay_button != null, "Duel scene contains a replay button")
	if replay_button != null:
		_check(replay_button.flat and replay_button.text.is_empty(), "Replay control is icon-only and frame-free")
		_check(replay_button.icon == null, "Replay button leaves built-in icon rendering unused")
		_check(replay_button.size.is_equal_approx(Vector2(44.0, 44.0)), "Replay touch target is 44 by 44")
		_check(replay_icon != null, "Replay button owns a separate visual child")
		if replay_icon != null:
			_check(replay_icon.texture != null and replay_icon.texture.resource_path == "res://inkpics/replay.png", "Replay visual uses the supplied image")
			_check(replay_icon.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Replay visual cannot intercept button input")
			_check(replay_icon.size.is_equal_approx(Vector2(55.0, 55.0)), "Replay visual is larger than its touch target")
			_check(replay_icon.get_rect().get_center().is_equal_approx(replay_button.get_rect().size * 0.5), "Replay visual remains centered on the button")
		var board := duel.get_node("DuelCanvas/BoardCenter/BoardGrid") as Control
		_check(replay_button.position.x + replay_button.size.x <= board.position.x, "Replay control stays left of the board")
		_check(absf(replay_button.get_rect().get_center().y - board.get_rect().get_center().y) < 1.0, "Replay control is vertically centered on the board")
		replay_button.button_down.emit()
		await create_timer(0.08).timeout
		_check(replay_button.scale.x < 1.0 and replay_button.modulate.a < 1.0, "Replay touch-down provides scale and opacity feedback")
		replay_button.button_up.emit()
		await create_timer(0.18).timeout
		_check(replay_button.scale.is_equal_approx(Vector2.ONE) and is_equal_approx(replay_button.modulate.a, 1.0), "Replay touch feedback restores cleanly on release")

	var opening_key: String = StateKey.build(duel.duel_state)
	var opening_side_decks: Dictionary = duel.duel_state.decks.duplicate(true)
	_check(not duel.debug_is_replay_ready(), "Active duel replay is not ready")
	_check(not await duel.debug_start_replay(), "Replay request during active duel is a no-op")
	_check(StateKey.build(duel.duel_state) == opening_key, "Unavailable replay preserves active duel state")

	var action_count: int = 0
	while not duel.debug_is_complete() and action_count < 100:
		var actions: Array[ActionData] = Simulator.get_legal_actions(duel.duel_state)
		_check(not actions.is_empty(), "Non-terminal replay fixture has a legal action")
		if actions.is_empty():
			break
		var action: ActionData = actions[0]
		var owner_id: int = duel.debug_get_active_owner()
		var committed: bool = false
		if action.action_type == ActionData.TYPE_PLAY:
			committed = await duel.debug_commit_move(
				owner_id,
				action.source_index,
				action.target_index,
				false
			)
		else:
			committed = await duel.debug_commit_activate(
				owner_id,
				action.source_index,
				action.target_index,
				false,
				action.activation_index
			)
		_check(committed, "Replay fixture commits legal action %d" % (action_count + 1))
		action_count += 1

	_check(duel.debug_is_complete(), "Replay fixture reaches a completed duel")
	_check(duel.debug_is_replay_ready(), "Completed duel produces a ready replay")
	_check(duel.debug_get_replay_action_count() == action_count, "Every successful real action is recorded exactly once")
	_check(duel.debug_get_replay_initial_decks() == opening_side_decks, "Replay preserves exact shuffled opening side decks")
	var final_key: String = StateKey.build(duel.duel_state)
	var final_outcome: StringName = duel.debug_get_match_outcome()
	var final_status: String = (duel.get_node("DuelCanvas/TurnStatus") as Label).text
	var mastery_before: Array[StringName] = duel.get_mastery_candidate_ids()
	var memory_before: int = _memory_emissions
	var trace_size_before: int = duel.debug_get_presentation_trace().size()

	duel.debug_start_replay()
	await process_frame
	_check(duel.debug_is_replaying(), "Completed replay request starts playback")
	_check(not await duel.debug_start_replay(), "Replay request during playback is a no-op")
	var replay_frames: int = 0
	while duel.debug_is_replaying() and replay_frames < 1000:
		await process_frame
		replay_frames += 1
	_check(not duel.debug_is_replaying(), "Replay finishes within the safety frame bound")
	_check(StateKey.build(duel.duel_state) == final_key, "Replay reconstructs the exact final logical state")
	_check(duel.debug_get_match_outcome() == final_outcome, "Replay preserves the original outcome")
	_check((duel.get_node("DuelCanvas/TurnStatus") as Label).text == final_status, "Replay restores the original final status")
	_check(duel.get_mastery_candidate_ids() == mastery_before, "Replay creates no mastery candidates")
	_check(_memory_emissions == memory_before, "Replay emits no opponent-memory signals")
	_check(duel.debug_get_replay_action_count() == action_count, "Replay does not record itself")
	_check(duel.debug_get_presentation_trace().size() > trace_size_before, "Replay reuses normal transition presentation")

	_check(await duel.debug_start_replay(), "Completed replay can be started repeatedly")
	_check(StateKey.build(duel.duel_state) == final_key, "Repeated replay returns to the same final state")

	duel.replay_turn_delay = 0.15
	duel.debug_start_replay()
	var wait_frames: int = 0
	while not duel.debug_is_replay_waiting() and duel.debug_is_replaying() and wait_frames < 300:
		await process_frame
		wait_frames += 1
	_check(duel.debug_is_replay_waiting(), "Replay reaches a settled inter-turn delay")
	_check(_opponent_hand_is_concealed(duel), "Normal-mode opponent hand remains concealed during replay")
	var inspect_card: CardView = _first_card(duel.get_node("DuelCanvas/PlayerHand"))
	_check(inspect_card != null and duel.debug_open_inspection(inspect_card.card_data), "A revealed card can be inspected during replay delay")
	var paused_remaining: float = duel.debug_get_replay_delay_remaining()
	await create_timer(0.08).timeout
	_check(
		absf(duel.debug_get_replay_delay_remaining() - paused_remaining) < 0.01,
		"Open inspection pauses the remaining replay delay"
	)
	duel.debug_close_inspection()
	var resumed_frames: int = 0
	while duel.debug_is_replaying() and resumed_frames < 1500:
		await process_frame
		resumed_frames += 1
	_check(not duel.debug_is_replaying(), "Replay resumes and finishes after inspection closes")

	var replay_record = duel.get("_replay_record")
	var preserved_actions: Array[ActionData] = replay_record.get_actions()
	var invalid_action: ActionData = preserved_actions[0].duplicate_action() as ActionData
	invalid_action.source_instance_id = &"missing_replay_source"
	var invalid_actions: Array[ActionData] = [invalid_action]
	replay_record.set("_actions", invalid_actions)
	_check(not await duel.debug_start_replay(), "An invalid recorded action aborts replay safely")
	_check(StateKey.build(duel.duel_state) == final_key, "Invalid replay recovery restores the immutable final state")
	_check(duel.debug_get_match_outcome() == final_outcome, "Invalid replay recovery preserves the original outcome")
	_check((duel.get_node("DuelCanvas/TurnStatus") as Label).text == final_status, "Invalid replay recovery preserves the final status")
	_check(_memory_emissions == memory_before, "Invalid replay recovery emits no opponent-memory signal")
	replay_record.set("_actions", preserved_actions)
	_check(duel.debug_is_replay_ready(), "The preserved valid replay remains available after recovery testing")

	var returned_outcomes: Array[StringName] = []
	duel.return_requested.connect(func(outcome: StringName) -> void: returned_outcomes.append(outcome))
	duel.replay_turn_delay = 0.2
	duel.debug_start_replay()
	wait_frames = 0
	while not duel.debug_is_replay_waiting() and duel.debug_is_replaying() and wait_frames < 300:
		await process_frame
		wait_frames += 1
	(duel.get_node("DuelCanvas/TopBar/ExitButton") as Button).pressed.emit()
	await process_frame
	_check(not duel.debug_is_replaying(), "Return during replay cancels delayed playback")
	_check(returned_outcomes == [final_outcome], "Return during replay emits the original completed outcome")

	duel.queue_free()
	await process_frame
	_cleanup()
	_finish()


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = _save_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _first_card(container: Node) -> CardView:
	for slot: Node in container.get_children():
		for child: Node in slot.get_children():
			if child is CardView:
				return child as CardView
	return null


func _opponent_hand_is_concealed(duel: DuelController) -> bool:
	var observed: int = 0
	for slot: Node in duel.get_node("DuelCanvas/OpponentHand").get_children():
		for child: Node in slot.get_children():
			if child is CardView:
				observed += 1
				if not (child as CardView).is_face_down():
					return false
	return observed > 0


func _finish() -> void:
	if _failures == 0:
		print("DUEL_REPLAY_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("DUEL_REPLAY_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
