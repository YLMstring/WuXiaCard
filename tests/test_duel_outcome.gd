extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")

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
	victory_duel.duel_state.terminal_reason = State.TERMINAL_REASON_ACTION_LIMIT
	victory_duel.call("_finish_match")
	_check(victory_duel.debug_get_match_outcome() == &"victory", "Higher player score records victory")
	_check(
		(victory_duel.get_node("DuelCanvas/TurnStatus") as Label).text
		== "行动上限 获胜 · 1–0",
		"Action-limit victory keeps the result and score in the approved text"
	)
	victory_duel.return_requested.connect(
		func(outcome: StringName) -> void:
			victory_outcome["value"] = outcome
			victory_outcome["count"] = int(victory_outcome["count"]) + 1
	)
	(victory_duel.get_node("DuelCanvas/TopBar/ExitButton") as Button).pressed.emit()
	(victory_duel.get_node("DuelCanvas/TopBar/ExitButton") as Button).pressed.emit()
	_check(victory_outcome["value"] == &"victory", "Returning after a win reports victory")
	_check(int(victory_outcome["count"]) == 1, "Repeated return presses emit one result")
	victory_duel.queue_free()
	await process_frame

	var defeat_outcome: Dictionary = {"value": &""}
	var defeat_duel: Node = DUEL_SCENE.instantiate()
	defeat_duel.set("testing_mode", true)
	defeat_duel.set("opening_layout_seed", -1)
	root.add_child(defeat_duel)
	await process_frame
	defeat_duel.set("board", Rules.empty_board())
	defeat_duel.duel_state.terminal_reason = State.TERMINAL_REASON_FIVEFOLD_REPETITION
	defeat_duel.call("_finish_match")
	_check(defeat_duel.debug_get_match_outcome() == &"defeat", "A tie records defeat")
	_check(
		(defeat_duel.get_node("DuelCanvas/TurnStatus") as Label).text
		== "五次重复 失败 · 0–0",
		"Fivefold tie preserves the existing defeat outcome in the approved text"
	)
	defeat_duel.return_requested.connect(
		func(outcome: StringName) -> void: defeat_outcome["value"] = outcome
	)
	(defeat_duel.get_node("DuelCanvas/TopBar/ExitButton") as Button).pressed.emit()
	_check(defeat_outcome["value"] == &"defeat", "Returning after a loss reports defeat")
	defeat_duel.queue_free()
	await process_frame

	var loop_duel: Node = DUEL_SCENE.instantiate()
	loop_duel.set("testing_mode", true)
	loop_duel.set("opening_layout_seed", -1)
	root.add_child(loop_duel)
	await process_frame
	var loop_board: Array = Rules.empty_board()
	loop_board[0] = {"owner": Rules.PLAYER_OWNER, "card": {}}
	loop_board[1] = {"owner": Rules.OPPONENT_OWNER, "card": {}}
	loop_board[2] = {"owner": Rules.OPPONENT_OWNER, "card": {}}
	loop_duel.set("board", loop_board)
	loop_duel.duel_state.terminal_reason = State.TERMINAL_REASON_RESOLUTION_LOOP
	loop_duel.call("_finish_match")
	_check(
		(loop_duel.get_node("DuelCanvas/TurnStatus") as Label).text
		== "结算循环 失败 · 1–2",
		"Resolution-loop loss keeps the result and score in the approved text"
	)
	loop_duel.queue_free()
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
