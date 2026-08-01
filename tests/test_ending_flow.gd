extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://main.tscn")
const Store = preload("res://scripts/deck_profile_store.gd")
const EndingController = preload("res://scripts/ending_controller.gd")
const MenuController = preload("res://scripts/main_menu_controller.gd")
const SelectorController = preload("res://scripts/sect_selection_controller.gd")

var _checks: int = 0
var _failures: int = 0
var _save_path: String = "user://ending_flow_test.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var store: RefCounted = Store.new(_save_path)
	var default_profile: Dictionary = store.create_default_profile()
	var begin: Dictionary = store.begin_run_and_save(
		default_profile,
		&"xuanyue_jianzong",
		[],
		&"qingfeng_xuedi"
	)
	_check(bool(begin.get("ok", false)), "Final-flow fixture begins an active run")

	var flow: Variant = MAIN_SCENE.instantiate()
	flow.deck_profile_path = _save_path
	flow.testing_mode = true
	flow.victories_required = 1
	root.add_child(flow)
	await process_frame
	await process_frame

	var menu := flow.debug_get_current_screen() as MenuController
	(menu.get_node("MenuLayer/Actions/JourneyButton") as Button).pressed.emit()
	await process_frame
	var builder := flow.debug_get_current_screen() as DeckBuilderController
	_check(builder != null, "An active final-flow fixture resumes deck building")
	(builder.get_node("DuelCanvas/GoSecondButton") as Button).pressed.emit()
	await process_frame
	var duel := flow.debug_get_current_screen() as DuelController
	_check(duel != null, "Final-flow fixture enters the duel")
	duel.return_requested.emit(DuelController.OUTCOME_VICTORY)
	await process_frame

	var ending := flow.debug_get_current_screen() as EndingController
	_check(ending != null, "Final victory routes directly to the ending scene")
	var summary: Dictionary = ending.get_summary()
	_check(int(summary.get("score", -1)) == 15000, "Threshold-one final victory displays the formula score")
	_check((summary.get("defeated_enemy_ids", []) as Array) == ["qingfeng_xuedi"], "Ending receives the defeated enemy history")
	var completed_profile: Dictionary = store.load_profile()
	_check(not bool(completed_profile["run_active"]), "Final-victory routing persists a closed run")
	_check((completed_profile["pending_reward_card_ids"] as Array).is_empty(), "Final victory bypasses reward creation")
	_check((completed_profile["main_deck"] as Array) == _strings(Store.DEFAULT_MAIN_DECK_IDS), "Final-victory routing restores the default deck")
	_check(int((completed_profile["best_scores_by_sect"] as Dictionary)["xuanyue_jianzong"]) == 15000, "Final-victory routing persists the achievement")

	var overflow_fixture: String = ""
	for index: int in range(20):
		overflow_fixture += "第%d段江湖往事仍在缓缓展开。\n" % (index + 1)
	ending.debug_set_story_text(overflow_fixture)
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = false
	ending._input(tap)
	await process_frame
	_check(flow.debug_get_current_screen() == ending, "Early ending tap cannot skip hidden story text")
	ending.debug_finish_story_roll()
	ending._input(tap)
	await process_frame
	menu = flow.debug_get_current_screen() as MenuController
	_check(menu != null, "Ending tap request returns to the normal main menu")
	(menu.get_node("MenuLayer/Actions/JourneyButton") as Button).pressed.emit()
	await process_frame
	var selector := flow.debug_get_current_screen() as SelectorController
	_check(selector != null, "Journey starts fresh sect selection after an ending")

	flow.queue_free()
	await process_frame
	_cleanup()
	_finish()


func _strings(values: Array) -> Array:
	var result: Array = []
	for value: Variant in values:
		result.append(String(value))
	return result


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = _save_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	if _failures == 0:
		print("ENDING_FLOW_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("ENDING_FLOW_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
