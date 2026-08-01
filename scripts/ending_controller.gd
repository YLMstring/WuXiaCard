class_name EndingController
extends Control

signal return_requested

const Sects = preload("res://scripts/sect_catalog.gd")
const Enemies = preload("res://scripts/enemy_catalog.gd")

@onready var main_menu: MainMenuController = $MainMenu
@onready var score_label: Label = $EndingLayer/Score
@onready var story_label: Label = $EndingLayer/Story

var _summary: Dictionary = {}
var _return_emitted: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	var actions := main_menu.get_node("MenuLayer/Actions") as VBoxContainer
	for child: Node in actions.get_children():
		if child is Button:
			(child as Button).focus_mode = Control.FOCUS_NONE
	actions.visible = false
	main_menu.get_node("MenuLayer/Notice").visible = false
	_style_text()
	resized.connect(_layout_ending)
	_apply_summary()
	_layout_ending()


func present(summary: Dictionary) -> void:
	_summary = summary.duplicate(true)
	_return_emitted = false
	if is_node_ready():
		_apply_summary()
		_layout_ending()


func get_summary() -> Dictionary:
	return _summary.duplicate(true)


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
	_return_emitted = true
	get_viewport().set_input_as_handled()
	return_requested.emit()


static func build_story(summary: Dictionary) -> String:
	var sect_id := StringName(String(summary.get("sect_id", "")))
	var sect_name: String = "无名门派"
	if Sects.has_sect(sect_id):
		sect_name = String(Sects.get_definition(sect_id).get("glyph", sect_name))
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
		+ "你以%s门人的身份仗剑而行，先后战胜%s。" % [sect_name, defeated_text]
		+ journey_text
		+ "如今群雄皆知你的名号，九宫论剑的余音仍在峰峦间回荡。"
		+ "此后江湖每逢谈及此战，必会记得你曾以一剑定高下，"
		+ "于华山绝顶写下属于%s的传奇。" % sect_name
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


func _layout_ending() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	var safe_rect: Rect2 = main_menu.debug_get_safe_rect()
	if safe_rect.size.x <= 0.0 or safe_rect.size.y <= 0.0:
		return
	var safe_width: float = safe_rect.size.x
	var safe_height: float = safe_rect.size.y
	var score_width: float = safe_width * 0.72
	var score_height: float = clampf(safe_height * 0.07, 44.0, 70.0)
	score_label.position = Vector2(
		safe_rect.get_center().x - score_width * 0.5,
		safe_rect.position.y + safe_height * 0.205
	)
	score_label.size = Vector2(score_width, score_height)
	score_label.add_theme_font_size_override(
		"font_size",
		roundi(clampf(safe_width * 0.058, 28.0, 44.0))
	)
	var story_width: float = safe_width * 0.78
	var story_y: float = safe_rect.position.y + safe_height * 0.30
	var story_bottom: float = safe_rect.position.y + safe_height * 0.94
	story_label.position = Vector2(
		safe_rect.get_center().x - story_width * 0.5,
		story_y
	)
	story_label.size = Vector2(story_width, story_bottom - story_y)
	story_label.add_theme_font_size_override(
		"font_size",
		roundi(clampf(safe_width * 0.034, 17.0, 25.0))
	)
