extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://main.tscn")
const Rules = preload("res://scripts/duel_rules.gd")
const Store = preload("res://scripts/deck_profile_store.gd")
const MenuController = preload("res://scripts/main_menu_controller.gd")
const SelectorController = preload("res://scripts/sect_selection_controller.gd")

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

	var menu := flow.debug_get_current_screen() as MenuController
	_check(menu != null, "Main scene starts at the main menu")
	(menu.get_node("MenuLayer/Actions/JourneyButton") as Button).pressed.emit()
	await process_frame
	var selector := flow.debug_get_current_screen() as SelectorController
	_check(selector != null, "An inactive run routes to sect selection")
	_check(selector.upcoming_enemy_name == "测试对手", "Main flow passes enemy details to sect selection")
	(selector.get_node("DuelCanvas/TopBar/BackButton") as Button).pressed.emit()
	await process_frame
	menu = flow.debug_get_current_screen() as MenuController
	_check(menu != null, "Sect-selection back returns to the main menu")

	(menu.get_node("MenuLayer/Actions/JourneyButton") as Button).pressed.emit()
	await process_frame
	selector = flow.debug_get_current_screen() as SelectorController
	_check(selector.debug_select_sect(&"xuanyue_jianzong"), "Selector accepts the default sect")
	_check(selector.debug_confirm_selected_sect(), "Confirming a sect starts the run")
	await process_frame
	var builder := flow.debug_get_current_screen() as DeckBuilderController
	_check(builder != null, "Sect confirmation enters deck building")
	var active_profile: Dictionary = Store.new(_save_path).load_profile()
	_check(bool(active_profile["run_active"]), "Sect confirmation persists active-run state")
	_check(
		String(active_profile["selected_sect_id"]) == "xuanyue_jianzong",
		"Sect confirmation persists the chosen sect"
	)
	(builder.get_node("DuelCanvas/TopBar/BackButton") as Button).pressed.emit()
	await process_frame
	menu = flow.debug_get_current_screen() as MenuController
	_check(menu != null, "Deck-builder back returns to the main menu")

	(menu.get_node("MenuLayer/Actions/JourneyButton") as Button).pressed.emit()
	await process_frame
	builder = flow.debug_get_current_screen() as DeckBuilderController
	_check(builder != null, "An active run resumes directly in deck building")
	_check(builder.upcoming_enemy_name == "测试对手", "Deck builder receives enemy details")
	(builder.get_node("DuelCanvas/GoSecondButton") as Button).pressed.emit()
	await process_frame
	var duel := flow.debug_get_current_screen() as DuelController
	_check(duel != null, "Go-second choice enters the duel")
	_check(duel.debug_get_active_owner() == Rules.OPPONENT_OWNER, "Go-second gives the opponent opening turn")
	_check(duel.opponent_name_text == "测试对手", "Duel receives the same enemy")
	(duel.get_node("DuelCanvas/TopBar/ExitButton") as Button).pressed.emit()
	await process_frame
	builder = flow.debug_get_current_screen() as DeckBuilderController
	_check(builder != null, "Duel return still goes back to deck building")

	(builder.get_node("DuelCanvas/TopBar/BackButton") as Button).pressed.emit()
	await process_frame
	menu = flow.debug_get_current_screen() as MenuController
	var run_reset_button := menu.get_node("MenuLayer/Actions/RunResetButton") as Button
	for press_index: int in range(5):
		run_reset_button.pressed.emit()
	await process_frame
	menu = flow.debug_get_current_screen() as MenuController
	_check(menu != null, "Run reset stays on the main menu")
	_check(
		(menu.get_node("MenuLayer/Notice") as Label).text == "本次江湖历程已重置",
		"Run reset reports completion"
	)
	var reset_profile: Dictionary = Store.new(_save_path).load_profile()
	_check(not bool(reset_profile["run_active"]), "Run reset clears active state")
	_check(
		Store.new(_save_path).get_main_deck_ids(reset_profile) == Store.DEFAULT_MAIN_DECK_IDS,
		"Run reset restores the default deck"
	)
	_check(
		&"hanfeng_liezhen" in Store.new(_save_path).get_unlocked_ids(reset_profile),
		"Run reset preserves unlocked cards"
	)

	var progress_reset_button := menu.get_node("MenuLayer/Actions/ProgressResetButton") as Button
	for press_index: int in range(10):
		progress_reset_button.pressed.emit()
	await process_frame
	menu = flow.debug_get_current_screen() as MenuController
	_check(
		(menu.get_node("MenuLayer/Notice") as Label).text == "所有进度已清除",
		"Full progress reset reports completion"
	)
	var fully_reset_profile: Dictionary = Store.new(_save_path).load_profile()
	_check(
		fully_reset_profile == Store.new(_save_path).create_default_profile(),
		"Full progress reset restores the initial profile"
	)

	flow.queue_free()
	await process_frame

	var failing_flow: Variant = MAIN_SCENE.instantiate()
	failing_flow.deck_profile_path = "user://missing_parent/main_flow_test.json"
	root.add_child(failing_flow)
	await process_frame
	var failing_menu := failing_flow.debug_get_current_screen() as MenuController
	var failing_reset_button := (
		failing_menu.get_node("MenuLayer/Actions/RunResetButton") as Button
	)
	for press_index: int in range(5):
		failing_reset_button.pressed.emit()
	await process_frame
	failing_menu = failing_flow.debug_get_current_screen() as MenuController
	_check(
		(failing_menu.get_node("MenuLayer/Notice") as Label).text == "保存失败，请重试",
		"A failed reset remains on the menu and reports the save failure"
	)
	failing_flow.queue_free()
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
