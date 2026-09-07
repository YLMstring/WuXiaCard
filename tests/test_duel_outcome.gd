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
	defeat_duel.call("_finish_match")
	_check(defeat_duel.debug_get_match_outcome() == &"defeat", "A tie records defeat")
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
