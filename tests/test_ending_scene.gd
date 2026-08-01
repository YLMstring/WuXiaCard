extends SceneTree

const ENDING_SCENE: PackedScene = preload("res://scenes/ending.tscn")
const EndingController = preload("res://scripts/ending_controller.gd")

var _checks: int = 0
var _failures: int = 0
var _returned: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ending := ENDING_SCENE.instantiate() as EndingController
	ending.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ending.size = Vector2(540.0, 960.0)
	ending.present({
		"sect_id": "xuanyue_jianzong",
		"score": 5000,
		"effective_duel_count": 3,
		"defeated_enemy_ids": ["qingfeng_xuedi", "tieshan_menren"],
		"flawless": false,
	})
	root.add_child(ending)
	await process_frame
	await process_frame

	var menu := ending.get_node("MainMenu") as MainMenuController
	var actions := menu.get_node("MenuLayer/Actions") as VBoxContainer
	var notice := menu.get_node("MenuLayer/Notice") as Label
	var score := ending.get_node("EndingLayer/Score") as Label
	var story := ending.get_node("EndingLayer/Story") as Label
	_check(menu != null, "Ending scene instances the production main menu")
	_check(not actions.visible, "Ending scene hides all three menu actions")
	_check(not notice.visible, "Ending scene hides the ordinary menu notice")
	_check(score.text == "得分 5000", "Ending scene displays the final score")
	_check(story.text.contains("玄岳剑宗"), "Ending prose names the selected sect")
	_check(story.text.contains("清风学弟") and story.text.contains("铁山门人"), "Ending prose names every defeated enemy")
	_check(story.text.find("清风学弟") < story.text.find("铁山门人"), "Defeated enemies remain chronological")
	_check(story.text.contains("也曾折剑再战"), "A run with losses uses the comeback prose")
	_check(story.language == "zh", "Ending prose opts into Chinese line breaking")
	_check(story.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "Ending prose uses smart wrapping")
	var safe_rect: Rect2 = menu.debug_get_safe_rect()
	_check(safe_rect.encloses(Rect2(score.position, score.size)), "Score remains inside the menu safe area")
	_check(safe_rect.encloses(Rect2(story.position, story.size)), "Story remains inside the menu safe area")

	ending.present({
		"sect_id": "xuanyue_jianzong",
		"score": 1000,
		"effective_duel_count": 15,
		"defeated_enemy_ids": ["qingfeng_xuedi"],
		"flawless": true,
	})
	_check(story.text.contains("未尝一败"), "A flawless run uses the undefeated prose")
	_check(not story.text.contains("折剑再战"), "Flawless prose never mentions a comeback")

	_returned = false
	ending.return_requested.connect(_on_return_requested)
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = false
	ending._input(tap)
	_check(_returned, "Releasing a tap anywhere requests the main menu")

	ending.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if _failures == 0:
		print("ENDING_SCENE_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("ENDING_SCENE_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _on_return_requested() -> void:
	_returned = true


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
