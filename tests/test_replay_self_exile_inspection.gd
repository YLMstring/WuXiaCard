extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")
const Action = preload("res://scripts/duel_action.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const ReplayRecord = preload("res://scripts/duel_replay_record.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_live_play_and_trigger_filter()
	await _check_manual_inspection_during_live_resolution()
	await _check_full_replay()
	await _check_opponent_turn_replay()
	await _check_manual_preempts_automatic_replay(false)
	await _check_manual_preempts_automatic_replay(true)
	await _check_cancelled_replay_closes_inspection()
	if _failures == 0:
		print("REPLAY_SELF_EXILE_INSPECTION_PASSED checks=%d" % _checks)
	else:
		push_error("REPLAY_SELF_EXILE_INSPECTION_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _new_duel() -> DuelController:
	var duel: DuelController = DUEL_SCENE.instantiate() as DuelController
	duel.testing_mode = false
	duel.replay_turn_delay = 0.0
	root.add_child(duel)
	await process_frame
	await process_frame
	duel.debug_set_fast_mode(true)
	duel.debug_set_fast_mode(false)
	return duel


func _make_state(with_player_card: bool) -> State:
	var player_hand: Array = []
	if with_player_card:
		player_hand.append(Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"player_followup"))
	var state := State.new(
		Rules.empty_board(),
		player_hand,
		[Catalog.create_instance(&"YuNvWuFeng", Rules.OPPONENT_OWNER, &"opponent_yunv")],
		Rules.OPPONENT_OWNER
	)
	if not with_player_card:
		state.max_turns = 1
	return state


func _check_live_play_and_trigger_filter() -> void:
	var duel: DuelController = await _new_duel()
	duel.call("_rebuild_views_from_state", _make_state(true))
	_check(await duel.debug_commit_move(Rules.OPPONENT_OWNER, 0, 4, false), "Live enemy self-exile play commits")
	_check(not duel.debug_is_inspection_open(), "Live enemy self-exile does not interrupt the duel")
	_check(&"card_exiled" in duel.debug_get_presentation_trace(), "Live enemy self-exile still presents normally")
	duel.set("_is_replaying", true)
	var played: Action = Action.make_play(0, 4, &"opponent_yunv")
	var exact_exile: Array = [{"type": &"card_exiled", "self_removal": true, "instance_id": &"opponent_yunv"}]
	_check(bool(duel.call("_should_inspect_replayed_self_exile", played, Rules.OPPONENT_OWNER, exact_exile)), "Matching enemy replay self-exile qualifies")
	_check(not bool(duel.call("_should_inspect_replayed_self_exile", played, Rules.OPPONENT_OWNER, [{"type": &"card_exiled", "self_removal": true, "instance_id": &"other_card"}])), "Exiling another card does not qualify")
	_check(not bool(duel.call("_should_inspect_replayed_self_exile", played, Rules.OPPONENT_OWNER, [{"type": &"card_exiled", "self_removal": false, "instance_id": &"opponent_yunv"}])), "Ordinary exile does not qualify")
	_check(not bool(duel.call("_should_inspect_replayed_self_exile", played, Rules.PLAYER_OWNER, exact_exile)), "Player self-exile does not qualify")
	var activation: Action = played.duplicate_action() as Action
	activation.action_type = Action.TYPE_ACTIVATE
	_check(not bool(duel.call("_should_inspect_replayed_self_exile", activation, Rules.OPPONENT_OWNER, exact_exile)), "Enemy activation self-exile does not qualify")
	var same_name_new_instance: Action = Action.make_play(0, 4, &"second_yunv")
	_check(not bool(duel.call("_should_inspect_replayed_self_exile", same_name_new_instance, Rules.OPPONENT_OWNER, exact_exile)), "Same-name instance does not reuse another action's exile")
	_check(bool(duel.call("_should_inspect_replayed_self_exile", same_name_new_instance, Rules.OPPONENT_OWNER, [{"type": &"card_exiled", "self_removal": true, "instance_id": &"second_yunv"}])), "Later same-name instance qualifies independently")
	duel.debug_set_fast_mode(true)
	_check(not bool(duel.call("_should_inspect_replayed_self_exile", played, Rules.OPPONENT_OWNER, exact_exile)), "Fast presentation skips automatic modal")
	duel.queue_free()
	await process_frame


func _check_manual_inspection_during_live_resolution() -> void:
	var duel: DuelController = await _new_duel()
	duel.snap_duration = 0.30
	duel.card_fade_duration = 0.30
	duel.call("_rebuild_views_from_state", _make_state(true))
	duel.debug_commit_move(Rules.OPPONENT_OWNER, 0, 4, false)
	var played_card: CardView = _board_card(duel, 4)
	_check(played_card != null, "Live resolution exposes the just-revealed played card")
	if played_card != null:
		_submit_card_tap(played_card)
	_check(duel.debug_is_inspection_open(), "A tap opens inspection immediately during live resolution")
	await create_timer(0.36).timeout
	_check(
		not (&"board_entry_pause" in duel.debug_get_presentation_trace()),
		"The running snap finishes behind inspection without starting the next presentation step"
	)
	duel.debug_close_inspection()
	for _frame: int in range(120):
		if &"card_exiled" in duel.debug_get_presentation_trace():
			break
		await process_frame
	_check(&"card_exiled" in duel.debug_get_presentation_trace(), "Live resolution resumes the exile after close")
	var fading_card: CardView = _board_card(duel, 4)
	_check(fading_card != null, "The self-exiling card remains tappable during its fade")
	if fading_card != null:
		_submit_card_tap(fading_card)
	_check(duel.debug_is_inspection_open(), "Exile fade accepts immediate inspection")
	await create_timer(0.36).timeout
	var inspector: CardInspector = duel.get_node("DuelCanvas/CardInspector") as CardInspector
	var snapshot: Dictionary = inspector.get("_card_snapshot")
	_check(
		StringName(snapshot.get("instance_id", &"")) == &"opponent_yunv"
		and not is_instance_valid(fading_card),
		"The inspector retains its tapped snapshot after the fading card is freed"
	)
	_check(
		duel.turn_state == DuelController.TurnState.RESOLVING,
		"Resolution does not advance after the exile fade while inspection remains open"
	)
	duel.debug_close_inspection()
	for _frame: int in range(120):
		if duel.turn_state != DuelController.TurnState.RESOLVING:
			break
		await process_frame
	_check(duel.turn_state != DuelController.TurnState.RESOLVING, "Closing fade inspection resumes resolution")
	duel.queue_free()
	await process_frame


func _check_manual_preempts_automatic_replay(opponent_turn: bool) -> void:
	var duel: DuelController = await _new_duel()
	duel.snap_duration = 0.30
	var initial: State = _make_state(opponent_turn)
	var action: Action = Action.make_play(0, 4, &"opponent_yunv")
	var finished: State = Simulator.apply_action(initial, action).get("state") as State
	var record := ReplayRecord.new()
	record.begin(initial)
	record.record_action(action)
	if opponent_turn:
		duel.set("_opponent_replay_checkpoint_state", initial.duplicate_state())
		duel.set("_opponent_replay_checkpoint_action_count", 0)
		var recorded_actions: Array[Action] = [action]
		duel.set("_opponent_replay_actions", recorded_actions)
	else:
		record.complete(finished, &"defeat", "回放结束")
	duel.set("_replay_record", record)
	duel.call("_rebuild_views_from_state", finished)
	if opponent_turn:
		duel.debug_replay_last_opponent_turn()
	else:
		duel.set("turn_state", DuelController.TurnState.COMPLETE)
		duel.debug_start_replay()
	var inspected_card: CardView = (
		_first_hand_card(duel, Rules.PLAYER_OWNER)
		if opponent_turn else _board_card(duel, 4)
	)
	_check(inspected_card != null, "Replay exposes a public card during its snap")
	if inspected_card != null:
		_submit_card_tap(inspected_card)
	var label: String = "opponent-turn" if opponent_turn else "full"
	_check(duel.debug_is_inspection_open(), "%s replay accepts immediate manual inspection" % label)
	await create_timer(0.36).timeout
	_check(
		not (&"board_entry_pause" in duel.debug_get_presentation_trace()),
		"%s replay holds the next step while manual inspection stays open" % label
	)
	duel.debug_close_inspection()
	await _wait_for_replay_end(duel, opponent_turn)
	_check(
		not (duel.debug_is_replaying_opponent_turn() if opponent_turn else duel.debug_is_replaying()),
		"%s replay skips the conflicting automatic inspection" % label
	)
	_check(not duel.debug_is_inspection_open(), "%s replay ends with inspection closed" % label)
	_check(&"card_exiled" in duel.debug_get_presentation_trace(), "%s replay still presents exile" % label)
	duel.queue_free()
	await process_frame


func _check_full_replay() -> void:
	var duel: DuelController = await _new_duel()
	var initial: State = _make_state(false)
	var action: Action = Action.make_play(0, 4, &"opponent_yunv")
	var transition: Dictionary = Simulator.apply_action(initial, action)
	_check(bool(transition.get("valid", false)), "Full-replay fixture action is valid")
	var finished: State = transition.get("state") as State
	_check(Simulator.is_terminal(finished), "Full-replay fixture finishes the duel")
	var record := ReplayRecord.new()
	record.begin(initial)
	record.record_action(action)
	record.complete(finished, &"defeat", "回放结束")
	duel.set("_replay_record", record)
	duel.call("_rebuild_views_from_state", finished)
	duel.set("turn_state", DuelController.TurnState.COMPLETE)
	duel.debug_start_replay()
	await _wait_for_inspection(duel)
	_check(duel.debug_is_inspection_open(), "Full replay pauses for enemy self-exile inspection")
	_check(duel.debug_is_replaying(), "Full replay remains active while inspecting")
	_check(not (&"card_exiled" in duel.debug_get_presentation_trace()), "Exile presentation waits for inspector close")
	_check(_inspected_card_is_yunv(duel), "Inspector shows the revealed played YuNv card")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		var image: Image = duel.get_viewport().get_texture().get_image()
		_check(image.save_png("res://.summer/local/replay_self_exile_inspection.png") == OK, "Portrait inspector screenshot saves")
	duel.debug_close_inspection()
	await _wait_for_replay_end(duel, false)
	_check(not duel.debug_is_replaying(), "Full replay continues after closing inspector")
	_check(&"card_exiled" in duel.debug_get_presentation_trace(), "Full replay presents exile after close")
	_check(StateKey.build(duel.duel_state) == StateKey.build(finished), "Full replay preserves final state")
	duel.queue_free()
	await process_frame


func _check_opponent_turn_replay() -> void:
	var duel: DuelController = await _new_duel()
	var initial: State = _make_state(true)
	var action: Action = Action.make_play(0, 4, &"opponent_yunv")
	var transition: Dictionary = Simulator.apply_action(initial, action)
	_check(bool(transition.get("valid", false)), "Opponent-turn fixture action is valid")
	var live_state: State = transition.get("state") as State
	_check(live_state.active_player == Rules.PLAYER_OWNER and not Simulator.is_terminal(live_state), "Opponent-turn fixture reaches a live player decision")
	var record := ReplayRecord.new()
	record.begin(initial)
	record.record_action(action)
	duel.set("_replay_record", record)
	duel.set("_opponent_replay_checkpoint_state", initial.duplicate_state())
	duel.set("_opponent_replay_checkpoint_action_count", 0)
	var recorded_actions: Array[Action] = [action]
	duel.set("_opponent_replay_actions", recorded_actions)
	duel.call("_rebuild_views_from_state", live_state)
	_check(duel.debug_can_replay_last_opponent_turn(), "Opponent-turn replay fixture is available")
	duel.debug_replay_last_opponent_turn()
	await _wait_for_inspection(duel)
	_check(duel.debug_is_inspection_open(), "Opponent-turn replay pauses for enemy self-exile inspection")
	_check(duel.debug_is_replaying_opponent_turn(), "Opponent-turn replay remains active while inspecting")
	_check(not (&"card_exiled" in duel.debug_get_presentation_trace()), "Opponent-turn exile waits for inspector close")
	_check(_inspected_card_is_yunv(duel), "Opponent-turn inspector shows the played YuNv card")
	duel.debug_close_inspection()
	await _wait_for_replay_end(duel, true)
	_check(not duel.debug_is_replaying_opponent_turn(), "Opponent-turn replay continues after inspector close")
	_check(&"card_exiled" in duel.debug_get_presentation_trace(), "Opponent-turn replay presents exile after close")
	_check(StateKey.build(duel.duel_state) == StateKey.build(live_state), "Opponent-turn replay restores the live decision")
	duel.queue_free()
	await process_frame


func _check_cancelled_replay_closes_inspection() -> void:
	var duel: DuelController = await _new_duel()
	var initial: State = _make_state(false)
	var action: Action = Action.make_play(0, 4, &"opponent_yunv")
	var finished: State = Simulator.apply_action(initial, action).get("state") as State
	var record := ReplayRecord.new()
	record.begin(initial)
	record.record_action(action)
	record.complete(finished, &"defeat", "回放结束")
	duel.set("_replay_record", record)
	duel.call("_rebuild_views_from_state", finished)
	duel.set("turn_state", DuelController.TurnState.COMPLETE)
	duel.debug_start_replay()
	await _wait_for_inspection(duel)
	_check(duel.debug_is_inspection_open(), "Cancellation fixture reaches the replay inspector")
	duel.call("_leave_duel", true)
	await process_frame
	_check(not duel.debug_is_inspection_open(), "Cancelling replay closes its inspector")
	_check(not duel.debug_is_replaying(), "Cancelling replay stops playback")
	_check(not (&"card_exiled" in duel.debug_get_presentation_trace()), "Cancelled replay does not resume the abandoned event timeline")
	duel.queue_free()
	await process_frame


func _inspected_card_is_yunv(duel: DuelController) -> bool:
	var inspector := duel.get_node("DuelCanvas/CardInspector") as CardInspector
	var snapshot: Dictionary = inspector.get("_card_snapshot")
	return (
		StringName(snapshot.get("instance_id", &"")) == &"opponent_yunv"
		and String(snapshot.get("glyph", "")) == "玉女无锋"
		and not String(snapshot.get("description", "")).is_empty()
	)


func _board_card(duel: DuelController, cell_index: int) -> CardView:
	var board: GridContainer = duel.get_node("DuelCanvas/BoardCenter/BoardGrid") as GridContainer
	for child: Node in board.get_child(cell_index).get_children():
		if child is CardView:
			return child as CardView
	return null


func _first_hand_card(duel: DuelController, owner_id: int) -> CardView:
	var hand_path: String = (
		"DuelCanvas/PlayerHand" if owner_id == Rules.PLAYER_OWNER else "DuelCanvas/OpponentHand"
	)
	for slot: Node in duel.get_node(hand_path).get_children():
		for child: Node in slot.get_children():
			if child is CardView:
				return child as CardView
	return null


func _submit_card_tap(card: CardView) -> void:
	var center: Vector2 = card.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = center
		event.global_position = center
		card._gui_input(event)


func _wait_for_inspection(duel: DuelController) -> void:
	for _frame: int in range(120):
		if duel.debug_is_inspection_open():
			return
		await process_frame


func _wait_for_replay_end(duel: DuelController, opponent_turn: bool) -> void:
	for _frame: int in range(240):
		if not (duel.debug_is_replaying_opponent_turn() if opponent_turn else duel.debug_is_replaying()):
			return
		await process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("CHECK_FAILED: %s" % message)
