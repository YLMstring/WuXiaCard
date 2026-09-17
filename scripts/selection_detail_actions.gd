class_name SelectionDetailActions
extends Control

signal top_action_pressed(action_index: int)
signal bottom_action_pressed
signal bottom_action_rejected

const ACTIVE_TEXT_COLOR: Color = Color("3a2a1c")
const SELECTED_TEXT_COLOR: Color = Color("f4e2bd")
const DISABLED_TEXT_COLOR: Color = Color(0.45, 0.43, 0.40, 0.82)
const PRESSED_SCALE: Vector2 = Vector2(0.96, 0.96)
const FILTER_BACKGROUND: Color = Color("f1dfb8")
const FILTER_HOVER_BACKGROUND: Color = Color("f6e8ca")
const FILTER_PRESSED_BACKGROUND: Color = Color("ddc392")
const FILTER_BORDER: Color = Color("8b673d")
const PRIMARY_BACKGROUND: Color = Color("654127")
const PRIMARY_HOVER_BACKGROUND: Color = Color("765033")
const PRIMARY_PRESSED_BACKGROUND: Color = Color("51321f")
const PRIMARY_BORDER: Color = Color("c69a54")

var _bottom_enabled: bool = true
var _button_tweens: Dictionary = {}

@onready var top_actions: HBoxContainer = $TopActions
@onready var bottom_action: Button = $BottomAction


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index: int in range(top_actions.get_child_count()):
		var button := top_actions.get_child(index) as Button
		_style_filter_button(button)
		button.pressed.connect(_on_top_pressed.bind(index))
	bottom_action.pressed.connect(_on_bottom_pressed)
	_style_primary_button(bottom_action)
	hide_all()


func apply_layout(top_rect: Rect2, bottom_rect: Rect2) -> void:
	var top_size := Vector2(
		top_rect.size.x * 0.84,
		clampf(top_rect.size.y * 0.48, 50.0, 64.0)
	)
	top_actions.position = top_rect.position + (top_rect.size - top_size) * 0.5
	top_actions.size = top_size
	top_actions.add_theme_constant_override("separation", 18)

	var bottom_size := Vector2(
		bottom_rect.size.x * 0.60,
		clampf(bottom_rect.size.y * 0.50, 54.0, 68.0)
	)
	bottom_action.position = bottom_rect.position + (bottom_rect.size - bottom_size) * 0.5
	bottom_action.size = bottom_size


func configure_top_actions(labels: Array, selected_index: int = -1) -> void:
	for index: int in range(top_actions.get_child_count()):
		var button := top_actions.get_child(index) as Button
		button.visible = index < labels.size()
		if not button.visible:
			continue
		button.text = String(labels[index])
		_apply_selected_style(button, index == selected_index)
	top_actions.visible = not labels.is_empty()


func configure_bottom_action(label: String, enabled: bool = true) -> void:
	_bottom_enabled = enabled
	bottom_action.text = label
	bottom_action.visible = not label.is_empty()
	bottom_action.modulate = Color.WHITE if enabled else Color(0.72, 0.72, 0.72, 0.92)
	bottom_action.add_theme_color_override(
		"font_color",
		SELECTED_TEXT_COLOR if enabled else DISABLED_TEXT_COLOR
	)


func hide_top_actions() -> void:
	top_actions.visible = false


func hide_bottom_action() -> void:
	bottom_action.visible = false


func hide_all() -> void:
	hide_top_actions()
	hide_bottom_action()


func get_exclusion_controls() -> Array[Control]:
	var controls: Array[Control] = [top_actions, bottom_action]
	return controls


func _on_top_pressed(action_index: int) -> void:
	_vibrate(12)
	top_action_pressed.emit(action_index)


func _on_bottom_pressed() -> void:
	if not _bottom_enabled:
		_vibrate(30)
		bottom_action_rejected.emit()
		return
	_vibrate(12)
	bottom_action_pressed.emit()


func _style_filter_button(button: Button) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", ACTIVE_TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", ACTIVE_TEXT_COLOR)
	button.add_theme_color_override("font_pressed_color", ACTIVE_TEXT_COLOR)
	button.add_theme_color_override("font_focus_color", ACTIVE_TEXT_COLOR)
	button.add_theme_stylebox_override("normal", _make_style(FILTER_BACKGROUND, FILTER_BORDER, 1, false))
	button.add_theme_stylebox_override("hover", _make_style(FILTER_HOVER_BACKGROUND, FILTER_BORDER, 2, false))
	button.add_theme_stylebox_override("pressed", _make_style(FILTER_PRESSED_BACKGROUND, FILTER_BORDER, 2, false))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.button_down.connect(_on_button_down.bind(button))
	button.button_up.connect(_on_button_up.bind(button))


func _style_primary_button(button: Button) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 17)
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color_name, SELECTED_TEXT_COLOR)
	button.add_theme_stylebox_override(
		"normal",
		_make_style(PRIMARY_BACKGROUND, PRIMARY_BORDER, 2, true)
	)
	button.add_theme_stylebox_override(
		"hover",
		_make_style(PRIMARY_HOVER_BACKGROUND, PRIMARY_BORDER, 2, true)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_make_style(PRIMARY_PRESSED_BACKGROUND, PRIMARY_BORDER, 2, false)
	)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.button_down.connect(_on_button_down.bind(button))
	button.button_up.connect(_on_button_up.bind(button))


func _apply_selected_style(button: Button, selected: bool) -> void:
	button.add_theme_color_override(
		"font_color",
		SELECTED_TEXT_COLOR if selected else ACTIVE_TEXT_COLOR
	)
	button.add_theme_color_override(
		"font_hover_color",
		SELECTED_TEXT_COLOR if selected else ACTIVE_TEXT_COLOR
	)
	button.add_theme_color_override(
		"font_pressed_color",
		SELECTED_TEXT_COLOR if selected else ACTIVE_TEXT_COLOR
	)
	button.add_theme_stylebox_override(
		"normal",
		_make_style(
			Color("765438") if selected else FILTER_BACKGROUND,
			Color("c89554") if selected else FILTER_BORDER,
			2 if selected else 1,
			false
		)
	)
	button.add_theme_stylebox_override(
		"hover",
		_make_style(
			Color("846041") if selected else FILTER_HOVER_BACKGROUND,
			Color("d5aa68") if selected else FILTER_BORDER,
			2,
			false
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_make_style(
			Color("65452f") if selected else FILTER_PRESSED_BACKGROUND,
			Color("c89554") if selected else FILTER_BORDER,
			2,
			false
		)
	)


func _make_style(
	background: Color,
	border: Color,
	border_width: int,
	with_shadow: bool
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	if with_shadow:
		style.shadow_color = Color(0.20, 0.12, 0.06, 0.24)
		style.shadow_size = 2
		style.shadow_offset = Vector2(0.0, 2.0)
	return style


func _on_button_down(button: Button) -> void:
	_kill_button_tween(button)
	button.pivot_offset = button.size * 0.5
	button.scale = PRESSED_SCALE


func _on_button_up(button: Button) -> void:
	_kill_button_tween(button)
	var tween: Tween = button.create_tween()
	_button_tweens[button.get_instance_id()] = tween
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE, 0.10)


func _kill_button_tween(button: Button) -> void:
	var instance_id: int = button.get_instance_id()
	var existing: Variant = _button_tweens.get(instance_id, null)
	if existing is Tween and (existing as Tween).is_valid():
		(existing as Tween).kill()
	_button_tweens.erase(instance_id)


func _vibrate(duration_ms: int) -> void:
	if duration_ms > 0 and OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms)
