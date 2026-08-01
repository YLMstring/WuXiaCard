class_name EndingController
extends Control

signal return_requested

const Sects = preload("res://scripts/sect_catalog.gd")
const Enemies = preload("res://scripts/enemy_catalog.gd")
const SCORE_TOP_RATIO: float = 0.21
const SCORE_HEIGHT_RATIO: float = 0.045
const SCORE_WIDTH_RATIO: float = 0.62
const STORY_TOP_RATIO: float = 0.285
const STORY_BOTTOM_RATIO: float = 0.455
const STORY_WIDTH_RATIO: float = 0.68
const MIN_TITLE_SCORE_GAP_RATIO: float = 0.02

@onready var main_menu: MainMenuController = $MainMenu
@onready var score_label: Label = $EndingLayer/Score
@onready var story_clip: Control = $EndingLayer/StoryClip
@onready var story_label: Label = $EndingLayer/StoryClip/Story

@export_range(1.0, 120.0, 1.0) var story_scroll_speed: float = 18.0

var _summary: Dictionary = {}
var _return_emitted: bool = false
var _story_scroll_offset: float = 0.0
var _story_max_offset: float = 0.0
var _story_roll_complete: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	set_process(false)
	var actions := main_menu.get_node("MenuLayer/Actions") as VBoxContainer
	for child: Node in actions.get_children():
		if child is Button:
			(child as Button).focus_mode = Control.FOCUS_NONE
	actions.visible = false
	main_menu.get_node("MenuLayer/Notice").visible = false
	_style_text()
	resized.connect(_layout_ending)
	_apply_summary()
	_story_scroll_offset = 0.0
	_layout_ending()


func present(summary: Dictionary) -> void:
	_summary = summary.duplicate(true)
	_return_emitted = false
	_story_scroll_offset = 0.0
	if is_node_ready():
		_apply_summary()
		_layout_ending()


func get_summary() -> Dictionary:
	return _summary.duplicate(true)


func debug_get_story_scroll_offset() -> float:
	return _story_scroll_offset


func debug_get_story_max_offset() -> float:
	return _story_max_offset


func debug_is_story_roll_complete() -> bool:
	return _story_roll_complete


func debug_advance_story_roll(delta: float) -> void:
	_advance_story_roll(maxf(0.0, delta))


func debug_finish_story_roll() -> void:
	_story_scroll_offset = _story_max_offset
	_story_roll_complete = true
	_apply_story_scroll_position()
	set_process(false)


func debug_set_story_text(text: String) -> void:
	story_label.text = text
	_story_scroll_offset = 0.0
	_recalculate_story_roll()


func _process(delta: float) -> void:
	_advance_story_roll(delta)


func _input(event: InputEvent) -> void:
	if _return_emitted:
		return
	var released: bool = false
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		released = mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed
	elif event is InputEventScreenTouch:
		released = not (event as InputEventScreenTouch).pressed
	if not released:
		return
	if not _story_roll_complete:
		get_viewport().set_input_as_handled()
		return
	_return_emitted = true
	get_viewport().set_input_as_handled()
	return_requested.emit()


static func build_story(summary: Dictionary) -> String:
	var sect_id := StringName(String(summary.get("sect_id", "")))
	var sect_name: String = "无名门派"
	if Sects.has_sect(sect_id):
		sect_name = String(Sects.get_definition(sect_id).get("glyph", sect_name))
	if sect_name == "无门无派":
		sect_name = "江湖散人"
	else:
		sect_name = sect_name + "弟子"
	var enemy_names: Array[String] = []
	var defeated_value: Variant = summary.get("defeated_enemy_ids", [])
	if typeof(defeated_value) == TYPE_ARRAY:
		for value: Variant in defeated_value as Array:
			var enemy_id := StringName(String(value))
			if Enemies.has_enemy(enemy_id):
				enemy_names.append(String(Enemies.get_definition(enemy_id).get("name", "")))
	var defeated_text: String = "诸路豪杰"
	if not enemy_names.is_empty():
		defeated_text = "、".join(enemy_names)
	var journey_text: String = (
		"一路走来，你连战连捷，剑锋所向，未尝一败；"
		if bool(summary.get("flawless", false))
		else "一路走来，你有过锋芒毕露，也曾折剑再战；"
	)
	return (
		"你立于华山之巅，长风掠过衣袂，回首踏入江湖以来的诸般往事。"
		+ "本是%s，却另有奇遇，以九宫论剑图谱所载的诸般功夫，先后战胜%s。" % [sect_name, defeated_text]
		+ journey_text
		+ "而今群雄皆已成为身后旧影，九宫论剑之名亦随你的剑锋传遍四海。"
		+ "自此江湖再论高下，无人能够绕过你的名字。"
	)


func _apply_summary() -> void:
	score_label.text = "得分 %d" % int(_summary.get("score", 0))
	story_label.text = build_story(_summary)


func _style_text() -> void:
	score_label.add_theme_color_override("font_color", Color("6f3a22"))
	score_label.add_theme_color_override(
		"font_outline_color",
		Color(0.95, 0.84, 0.56, 0.72)
	)
	score_label.add_theme_constant_override("outline_size", 2)
	story_label.add_theme_color_override("font_color", Color("33231b"))
	story_label.add_theme_color_override(
		"font_outline_color",
		Color(0.94, 0.88, 0.72, 0.42)
	)
	story_label.add_theme_constant_override("outline_size", 1)
	story_label.add_theme_constant_override("line_spacing", 3)


func _layout_ending() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	var safe_rect: Rect2 = main_menu.debug_get_safe_rect()
	if safe_rect.size.x <= 0.0 or safe_rect.size.y <= 0.0:
		return
	var safe_width: float = safe_rect.size.x
	var safe_height: float = safe_rect.size.y
	var score_width: float = safe_width * SCORE_WIDTH_RATIO
	var score_height: float = clampf(safe_height * SCORE_HEIGHT_RATIO, 30.0, 46.0)
	score_label.position = Vector2(
		safe_rect.get_center().x - score_width * 0.5,
		safe_rect.position.y + safe_height * SCORE_TOP_RATIO
	)
	score_label.size = Vector2(score_width, score_height)
	score_label.add_theme_font_size_override(
		"font_size",
		roundi(clampf(safe_width * 0.034, 18.0, 27.0))
	)
	var title := main_menu.get_node("MenuLayer/Title") as Label
	var title_bottom: float = title.position.y + title.size.y
	var minimum_score_y: float = title_bottom + safe_height * MIN_TITLE_SCORE_GAP_RATIO
	if score_label.position.y < minimum_score_y:
		score_label.position.y = minimum_score_y
	var story_width: float = safe_width * STORY_WIDTH_RATIO
	var story_y: float = safe_rect.position.y + safe_height * STORY_TOP_RATIO
	var story_bottom: float = safe_rect.position.y + safe_height * STORY_BOTTOM_RATIO
	story_clip.position = Vector2(
		safe_rect.get_center().x - story_width * 0.5,
		story_y
	)
	story_clip.size = Vector2(story_width, story_bottom - story_y)
	story_label.add_theme_font_size_override(
		"font_size",
		roundi(clampf(safe_width * 0.026, 13.0, 19.0))
	)
	_recalculate_story_roll()


func _recalculate_story_roll() -> void:
	if story_clip.size.x <= 0.0 or story_clip.size.y <= 0.0:
		_story_max_offset = 0.0
		_story_roll_complete = true
		set_process(false)
		return
	story_label.position = Vector2.ZERO
	story_label.size = story_clip.size
	var rendered_height: float = maxf(
		story_clip.size.y,
		story_label.get_minimum_size().y
	)
	story_label.size = Vector2(story_clip.size.x, rendered_height)
	_story_max_offset = maxf(rendered_height - story_clip.size.y, 0.0)
	_story_scroll_offset = clampf(
		_story_scroll_offset,
		0.0,
		_story_max_offset
	)
	_story_roll_complete = is_zero_approx(
		_story_max_offset - _story_scroll_offset
	)
	_apply_story_scroll_position()
	set_process(not _story_roll_complete)


func _advance_story_roll(delta: float) -> void:
	if _story_roll_complete or delta <= 0.0:
		return
	_story_scroll_offset = minf(
		_story_max_offset,
		_story_scroll_offset + story_scroll_speed * delta
	)
	_story_roll_complete = is_zero_approx(
		_story_max_offset - _story_scroll_offset
	)
	_apply_story_scroll_position()
	if _story_roll_complete:
		set_process(false)


func _apply_story_scroll_position() -> void:
	story_label.position = Vector2(0.0, -_story_scroll_offset)
