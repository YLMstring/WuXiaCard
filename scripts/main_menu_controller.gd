class_name MainMenuController
extends Control

signal journey_requested
signal run_reset_confirmed
signal progress_reset_confirmed

const RUN_RESET_PRESSES: int = 5
const PROGRESS_RESET_PRESSES: int = 10
const DEFAULT_CONFIRMATION_TIMEOUT: float = 3.0
const BackdropScript = preload("res://scripts/main_menu_backdrop.gd")

@onready var backdrop: Control = $Backdrop
@onready var artwork: TextureRect = $Artwork
@onready var title_label: Label = $MenuLayer/Title
@onready var journey_button: Button = $MenuLayer/Actions/JourneyButton
@onready var run_reset_button: Button = $MenuLayer/Actions/RunResetButton
@onready var progress_reset_button: Button = $MenuLayer/Actions/ProgressResetButton
@onready var notice_label: Label = $MenuLayer/Notice
@onready var run_reset_timer: Timer = $RunResetTimer
@onready var progress_reset_timer: Timer = $ProgressResetTimer

var _run_reset_count: int = 0
var _progress_reset_count: int = 0
var _artwork_rect: Rect2 = Rect2()


func _ready() -> void:
	resized.connect(_layout_menu)
	journey_button.pressed.connect(_on_journey_pressed)
	run_reset_button.pressed.connect(_on_run_reset_pressed)
	progress_reset_button.pressed.connect(_on_progress_reset_pressed)
	run_reset_timer.timeout.connect(_on_run_reset_timeout)
	progress_reset_timer.timeout.connect(_on_progress_reset_timeout)
	for button: Button in [journey_button, run_reset_button, progress_reset_button]:
		_style_action_button(button)
		button.button_down.connect(_on_action_button_down.bind(button))
		button.button_up.connect(_on_action_button_up.bind(button))
	_style_text()
	reset_confirmation_state()
	_layout_menu()


func show_notice(message: String) -> void:
	notice_label.text = message


func reset_confirmation_state() -> void:
	_run_reset_count = 0
	_progress_reset_count = 0
	run_reset_timer.stop()
	progress_reset_timer.stop()
	if is_node_ready():
		notice_label.text = ""


func debug_get_confirmation_counts() -> Vector2i:
	return Vector2i(_run_reset_count, _progress_reset_count)


func debug_set_confirmation_timeout(seconds: float) -> void:
	var safe_seconds: float = maxf(0.01, seconds)
	run_reset_timer.wait_time = safe_seconds
	progress_reset_timer.wait_time = safe_seconds


func debug_get_artwork_rect() -> Rect2:
	return _artwork_rect


func _on_journey_pressed() -> void:
	reset_confirmation_state()
	journey_requested.emit()


func _on_run_reset_pressed() -> void:
	_cancel_progress_reset()
	_run_reset_count += 1
	run_reset_timer.start()
	if _run_reset_count >= RUN_RESET_PRESSES:
		_run_reset_count = 0
		run_reset_timer.stop()
		notice_label.text = ""
		run_reset_confirmed.emit()
		return
	notice_label.text = "再按 %d 次闭关重修" % (RUN_RESET_PRESSES - _run_reset_count)


func _on_progress_reset_pressed() -> void:
	_cancel_run_reset()
	_progress_reset_count += 1
	progress_reset_timer.start()
	if _progress_reset_count >= PROGRESS_RESET_PRESSES:
		_progress_reset_count = 0
		progress_reset_timer.stop()
		notice_label.text = ""
		progress_reset_confirmed.emit()
		return
	notice_label.text = "再按 %d 次封剑归隐" % (
		PROGRESS_RESET_PRESSES - _progress_reset_count
	)


func _on_run_reset_timeout() -> void:
	_run_reset_count = 0
	if _progress_reset_count == 0:
		notice_label.text = ""


func _on_progress_reset_timeout() -> void:
	_progress_reset_count = 0
	if _run_reset_count == 0:
		notice_label.text = ""


func _cancel_run_reset() -> void:
	_run_reset_count = 0
	run_reset_timer.stop()


func _cancel_progress_reset() -> void:
	_progress_reset_count = 0
	progress_reset_timer.stop()


func _style_text() -> void:
	title_label.add_theme_color_override("font_color", Color("2b1c16"))
	title_label.add_theme_color_override("font_outline_color", Color(0.92, 0.84, 0.68, 0.68))
	title_label.add_theme_constant_override("outline_size", 2)
	notice_label.add_theme_color_override("font_color", Color("5c3c2c"))
	notice_label.add_theme_color_override("font_outline_color", Color(0.93, 0.88, 0.72, 0.64))
	notice_label.add_theme_constant_override("outline_size", 1)


func _style_action_button(button: Button) -> void:
	button.flat = true
	var empty_style := StyleBoxEmpty.new()
	for style_name: StringName in [
		&"normal",
		&"hover",
		&"pressed",
		&"hover_pressed",
		&"focus",
		&"disabled",
	]:
		button.add_theme_stylebox_override(style_name, empty_style)
	button.add_theme_color_override("font_color", Color("2d2019"))
	button.add_theme_color_override("font_hover_color", Color("56311f"))
	button.add_theme_color_override("font_pressed_color", Color("8a3f2d"))
	button.add_theme_color_override("font_outline_color", Color(0.94, 0.87, 0.70, 0.72))
	button.add_theme_constant_override("outline_size", 2)


func _on_action_button_down(button: Button) -> void:
	button.pivot_offset = button.size * 0.5
	var tween: Tween = button.create_tween()
	tween.tween_property(button, "scale", Vector2(0.96, 0.96), 0.06)


func _on_action_button_up(button: Button) -> void:
	var tween: Tween = button.create_tween()
	tween.tween_property(button, "scale", Vector2.ONE, 0.10)


func _layout_menu() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	_artwork_rect = BackdropScript.fit_square_rect(size)
	backdrop.call("configure", _artwork_rect)
	artwork.position = _artwork_rect.position
	artwork.size = _artwork_rect.size
	var square_side: float = _artwork_rect.size.x
	var content_width: float = clampf(square_side * 0.46, 210.0, 330.0)
	var title_height: float = clampf(square_side * 0.09, 44.0, 72.0)
	var title_y: float = _artwork_rect.position.y + square_side * 0.105
	title_label.position = Vector2(
		_artwork_rect.get_center().x - content_width * 0.5,
		title_y
	)
	title_label.size = Vector2(content_width, title_height)
	title_label.add_theme_font_size_override(
		"font_size",
		roundi(clampf(square_side * 0.068, 32.0, 52.0))
	)
	var button_height: float = clampf(square_side * 0.105, 54.0, 72.0)
	var button_gap: float = clampf(square_side * 0.018, 8.0, 14.0)
	var actions_height: float = button_height * 3.0 + button_gap * 2.0
	var actions_y: float = _artwork_rect.position.y + square_side * 0.255
	var actions: VBoxContainer = $MenuLayer/Actions
	actions.position = Vector2(
		_artwork_rect.get_center().x - content_width * 0.5,
		actions_y
	)
	actions.size = Vector2(content_width, actions_height)
	actions.add_theme_constant_override("separation", roundi(button_gap))
	for button: Button in [journey_button, run_reset_button, progress_reset_button]:
		button.custom_minimum_size = Vector2(content_width, button_height)
		button.add_theme_font_size_override(
			"font_size",
			roundi(clampf(square_side * 0.043, 23.0, 34.0))
		)
	var notice_height: float = clampf(square_side * 0.07, 34.0, 50.0)
	notice_label.position = Vector2(
		_artwork_rect.get_center().x - content_width * 0.62,
		actions_y + actions_height + button_gap
	)
	notice_label.size = Vector2(content_width * 1.24, notice_height)
	notice_label.add_theme_font_size_override(
		"font_size",
		roundi(clampf(square_side * 0.03, 16.0, 23.0))
	)
