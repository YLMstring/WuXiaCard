extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://main.tscn")
const Rules = preload("res://scripts/duel_rules.gd")

var _checks: int = 0
var _failures: int = 0
var _save_path: String = "user://main_flow_test.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var flow: Variant = MAIN_SCENE.instantiate()
	flow.deck_profile_path = _save_path
	flow.testing_mode = true
	flow.upcoming_enemy_name = "测试对手"
	var enemy_ids: Array[StringName] = [
		&"CangSongYingKe2",
		&"fire_envoy",
		&"tiger_general",
		&"strategist",
		&"sun_zan",
	]
	flow.upcoming_enemy_card_ids = enemy_ids
	root.add_child(flow)
	await process_frame
	await process_frame

	var builder := flow.debug_get_current_screen() as DeckBuilderController
	_check(builder != null, "Main scene starts in deck building")
	_check(builder.upcoming_enemy_name == "测试对手", "Main flow passes upcoming enemy details to deck building")
	(builder.get_node("DuelCanvas/GoFirstButton") as Button).pressed.emit()
	await process_frame
	var duel := flow.debug_get_current_screen() as DuelController
	_check(duel != null, "Eligible go-first choice enters the duel")
	_check(duel.debug_get_active_owner() == Rules.PLAYER_OWNER, "Go-first choice gives the player the opening turn")
	_check(duel.opponent_name_text == "测试对手", "Duel receives the same upcoming enemy")

	(duel.get_node("DuelCanvas/TopBar/ExitButton") as Button).pressed.emit()
	await process_frame
	builder = flow.debug_get_current_screen() as DeckBuilderController
	_check(builder != null, "Duel return icon goes back to deck building")

	(builder.get_node("DuelCanvas/GoSecondButton") as Button).pressed.emit()
	await process_frame
	duel = flow.debug_get_current_screen() as DuelController
	_check(duel != null, "Go-second choice enters the duel")
	_check(duel.debug_get_active_owner() == Rules.OPPONENT_OWNER, "Go-second choice gives the opponent the opening turn")
	_check(duel.turn_state == DuelController.TurnState.OPPONENT, "Testing mode exposes the opening opponent turn for manual control")
	await process_frame
	_check(duel.debug_get_simulation_turn_count() == 0, "Testing mode does not run opening AI automatically")

	flow.queue_free()
	await process_frame
	_cleanup()
	_finish()


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = _save_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	if _failures == 0:
		print("MAIN_FLOW_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("MAIN_FLOW_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
