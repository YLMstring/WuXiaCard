extends SceneTree

const ENDING_SCENE: PackedScene = preload("res://scenes/ending.tscn")
const EndingController = preload("res://scripts/ending_controller.gd")
const LONG_ENEMY_IDS: Array[String] = [
	"qingfeng_xuedi",
	"tieshan_menren",
	"luoxia_jianji",
	"beiling_shuangying",
	"cangyan_hufa",
	"jinling_kuaijian",
	"xuanhuo_qishi",
	"fengsha_lingzhu",
	"qianji_xiansheng",
	"zhenyue_shi",
	"jiange_suzhu",
	"chisha_menzhu",
	"bailu_shanzhang",
	"tianmen_yishi",
	"wulin_sanren",
]

var _checks: int = 0
var _failures: int = 0
var _return_count: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ending := ENDING_SCENE.instantiate() as EndingController
	ending.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ending.size = Vector2(540.0, 960.0)
	ending.present({
		"sect_id": "xuanyue_jianzong",
		"score": 5000,
		"effective_duel_count": 3,
		"defeated_enemy_ids": LONG_ENEMY_IDS,
		"flawless": false,
	})
	root.add_child(ending)
	await process_frame
	await process_frame

	var menu := ending.get_node("MainMenu") as MainMenuController
	var actions := menu.get_node("MenuLayer/Actions") as VBoxContainer
	var notice := menu.get_node("MenuLayer/Notice") as Label
	var score := ending.get_node("EndingLayer/Score") as Label
	var story_clip := ending.get_node_or_null("EndingLayer/StoryClip") as Control
	var story := ending.get_node_or_null("EndingLayer/StoryClip/Story") as Label
	_check(menu != null, "Ending scene instances the production main menu")
	_check(not actions.visible, "Ending scene hides all three menu actions")
	_check(not notice.visible, "Ending scene hides the ordinary menu notice")
	_check(story_clip != null, "Ending scene owns a dedicated story clipping viewport")
	_check(story != null, "Story is a child of the clipping viewport")
	if story_clip == null or story == null:
		ending.queue_free()
		await process_frame
		_finish()
		return
	_check(story_clip.clip_contents, "Story viewport clips every overflowing line")
	_check(score.text == "得分 5000", "Ending scene displays the final score")
	_check(story.text.contains("玄岳剑宗"), "Ending prose names the selected sect")
	_check(story.text.contains("清风学弟") and story.text.contains("铁山门人"), "Ending prose names every defeated enemy")
	_check(story.text.find("清风学弟") < story.text.find("铁山门人"), "Defeated enemies remain chronological")
	_check(story.text.contains("也曾折剑再战"), "A run with losses uses the comeback prose")
	_check(story.language == "zh", "Ending prose opts into Chinese line breaking")
	_check(story.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "Ending prose uses smart wrapping")
	_check(ending.debug_get_story_max_offset() > 0.0, "Long ending prose produces measured overflow")
	var safe_rect: Rect2 = menu.debug_get_safe_rect()
	_check(safe_rect.encloses(Rect2(score.position, score.size)), "Score remains inside the menu safe area")
	_check(safe_rect.encloses(Rect2(story_clip.position, story_clip.size)), "Story viewport remains inside the menu safe area")
	_check(score.get_theme_font_size("font_size") < 28, "Compact ending uses a smaller score font")
	_check(story.get_theme_font_size("font_size") < 17, "Compact ending uses a smaller story font")
	var title := menu.get_node("MenuLayer/Title") as Label
	var title_bottom: float = title.position.y + title.size.y
	_check(
		score.position.y - title_bottom >= safe_rect.size.y * 0.02,
		"A visible breathing gap separates title and score"
	)
	_check(
		story_clip.position.y + story_clip.size.y
		< safe_rect.position.y + safe_rect.size.y * 0.50,
		"Compact story viewport ends above the painted arena"
	)

	ending.present({
		"sect_id": "xuanyue_jianzong",
		"score": 1000,
		"effective_duel_count": 15,
		"defeated_enemy_ids": ["qingfeng_xuedi"],
		"flawless": true,
	})
	_check(story.text.contains("未尝一败"), "A flawless run uses the undefeated prose")
	_check(not story.text.contains("折剑再战"), "Flawless prose never mentions a comeback")

	ending.debug_set_story_text("短章已尽。")
	_check(ending.debug_get_story_max_offset() == 0.0, "Short prose needs no roll")
	_check(ending.debug_is_story_roll_complete(), "Short prose completes immediately")

	ending.present({
		"sect_id": "xuanyue_jianzong",
		"score": 5000,
		"effective_duel_count": 16,
		"defeated_enemy_ids": LONG_ENEMY_IDS,
		"flawless": false,
	})
	_check(not ending.debug_is_story_roll_complete(), "Long prose locks navigation while hidden text remains")
	ending.size = Vector2(1280.0, 820.0)
	await process_frame
	await process_frame
	var wide_safe_rect: Rect2 = menu.debug_get_safe_rect()
	_check(
		wide_safe_rect.encloses(Rect2(score.position, score.size)),
		"Wide hosts keep the fixed score inside the 9:16 safe area"
	)
	_check(
		wide_safe_rect.encloses(Rect2(story_clip.position, story_clip.size)),
		"Wide hosts keep the clipped story inside the 9:16 safe area"
	)
	_check(
		ending.debug_get_story_scroll_offset() <= ending.debug_get_story_max_offset(),
		"Responsive relayout clamps story progress to the recomputed overflow"
	)
	ending.size = Vector2(540.0, 960.0)
	await process_frame
	await process_frame
	var fixed_score_position: Vector2 = score.position
	_return_count = 0
	ending.return_requested.connect(_on_return_requested)
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = false
	ending._input(tap)
	_check(_return_count == 0, "An early tap is consumed without returning")
	var touch := InputEventScreenTouch.new()
	touch.pressed = false
	ending._input(touch)
	_check(_return_count == 0, "An early touch release is consumed without returning")
	var offset_before: float = ending.debug_get_story_scroll_offset()
	ending.debug_advance_story_roll(1.0)
	_check(
		ending.debug_get_story_scroll_offset() > offset_before,
		"Story advances upward at its configured speed"
	)
	_check(score.position == fixed_score_position, "Score remains fixed while story rolls")
	_check(
		is_equal_approx(story.position.y, -ending.debug_get_story_scroll_offset()),
		"Story position follows the measured negative offset"
	)
	ending.debug_advance_story_roll(10000.0)
	_check(ending.debug_is_story_roll_complete(), "Roll completes at the measured maximum")
	_check(
		is_equal_approx(
			ending.debug_get_story_scroll_offset(),
			ending.debug_get_story_max_offset()
		),
		"Story roll never exceeds its exact overflow"
	)
	_check(
		is_equal_approx(story.position.y + story.size.y, story_clip.size.y),
		"Final story line stops fully visible at the viewport bottom"
	)
	var completed_offset: float = ending.debug_get_story_scroll_offset()
	ending.debug_advance_story_roll(1.0)
	_check(
		is_equal_approx(ending.debug_get_story_scroll_offset(), completed_offset),
		"Completed prose remains stationary while it waits for the player"
	)
	ending._input(tap)
	ending._input(tap)
	_check(_return_count == 1, "Only the first post-roll tap requests the main menu")

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
	_return_count += 1


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
