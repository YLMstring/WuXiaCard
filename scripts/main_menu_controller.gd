class_name MainMenuController
extends Control

signal journey_requested
signal run_reset_confirmed
signal progress_reset_confirmed

const RUN_RESET_PRESSES: int = 5
const PROGRESS_RESET_PRESSES: int = 10
const DEFAULT_CONFIRMATION_TIMEOUT: float = 3.0
const COUNTDOWN_NUMERALS: Dictionary = {
	1: "一",
	2: "二",
	3: "三",
	4: "四",
	5: "五",
	6: "六",
	7: "七",
	8: "八",
	9: "九",
}
const BackdropScript = preload("res://scripts/main_menu_backdrop.gd")
const MENU_ARTWORK: Texture2D = preload("res://pics/main_menu_background_phone.png")
const TITLE_INK: Texture2D = preload("res://inkpics/九宫论剑.png")
const TITLE_GLOW_SHADER: Shader = preload("res://scripts/main_menu_title_glow.gdshader")
const TITLE_BREATH_MIN_SCALE: Vector2 = Vector2(0.99, 0.99)
const TITLE_BREATH_MAX_SCALE: Vector2 = Vector2(1.01, 1.01)
const TITLE_BREATH_DURATION: float = 1.1
const TITLE_GLOW_MIN_STRENGTH: float = 0.3
const TITLE_GLOW_MAX_STRENGTH: float = 0.7
const TITLE_GLOW_COLOR: Color = Color(1.0, 0.78, 0.28, 0.82)
const JOURNEY_INK: Texture2D = preload("res://inkpics/踏入江湖.png")
const RUN_RESET_INK: Texture2D = preload("res://inkpics/闭关重修.png")
const PROGRESS_RESET_INK: Texture2D = preload("res://inkpics/封剑归隐.png")

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
var _safe_rect: Rect2 = Rect2()


func _ready() -> void:
	artwork.texture = MENU_ARTWORK
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_install_ink_glyphs()
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


func _install_ink_glyphs() -> void:
	title_label.text = ""
	_add_title_glow(title_label, TITLE_INK)
	_add_ink_glyph(title_label, TITLE_INK, false)
	var button_textures: Dictionary = {
		journey_button: JOURNEY_INK,
		run_reset_button: RUN_RESET_INK,
		progress_reset_button: PROGRESS_RESET_INK,
	}
	for button: Button in button_textures:
		button.text = ""
		_add_ink_glyph(button, button_textures[button] as Texture2D, true)
		button.mouse_entered.connect(_on_action_hover_changed.bind(button, true))
		button.mouse_exited.connect(_on_action_hover_changed.bind(button, false))


func _add_title_glow(parent: Control, texture: Texture2D) -> void:
	var glow := TextureRect.new()
	glow.name = "TitleGlow"
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.texture = texture
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var glow_material := ShaderMaterial.new()
	glow_material.shader = TITLE_GLOW_SHADER
	glow_material.set_shader_parameter(&"radius", 11.5)
	glow_material.set_shader_parameter(&"pulse_strength", TITLE_GLOW_MIN_STRENGTH)
	glow_material.set_shader_parameter(&"glow_color", TITLE_GLOW_COLOR)
	glow.material = glow_material
	parent.add_child(glow)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.scale = TITLE_BREATH_MIN_SCALE
	parent.self_modulate = Color.WHITE
	var pulse: Tween = parent.create_tween().set_loops()
	pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(parent, "scale", TITLE_BREATH_MAX_SCALE, TITLE_BREATH_DURATION)
	pulse.parallel().tween_method(
		_set_title_glow_strength.bind(glow_material),
		TITLE_GLOW_MIN_STRENGTH,
		TITLE_GLOW_MAX_STRENGTH,
		TITLE_BREATH_DURATION
	)
	pulse.tween_property(parent, "scale", TITLE_BREATH_MIN_SCALE, TITLE_BREATH_DURATION)
	pulse.parallel().tween_method(
		_set_title_glow_strength.bind(glow_material),
		TITLE_GLOW_MAX_STRENGTH,
		TITLE_GLOW_MIN_STRENGTH,
		TITLE_BREATH_DURATION
	)


func _set_title_glow_strength(strength: float, glow_material: ShaderMaterial) -> void:
	glow_material.set_shader_parameter(&"pulse_strength", strength)


func _add_ink_glyph(parent: Control, texture: Texture2D, subdued: bool) -> void:
	var glyph := TextureRect.new()
	glyph.name = "InkGlyph"
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.texture = texture
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.self_modulate.a = 0.88 if subdued else 1.0
	parent.add_child(glyph)
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _on_action_hover_changed(button: Button, hovered: bool) -> void:
	var glyph := button.get_node_or_null("InkGlyph") as TextureRect
	if glyph == null:
		return
	var tween: Tween = glyph.create_tween()
	tween.tween_property(glyph, "self_modulate:a", 1.0 if hovered else 0.88, 0.08)


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


func debug_get_safe_rect() -> Rect2:
	return _safe_rect


func _countdown_notice(remaining: int, action_text: String) -> String:
	var numeral: String = str(COUNTDOWN_NUMERALS.get(remaining, str(remaining)))
	return "再按%s次\n%s" % [numeral, action_text]


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
	notice_label.text = _countdown_notice(
		RUN_RESET_PRESSES - _run_reset_count,
		"放弃本局"
	)


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
	notice_label.text = _countdown_notice(
		PROGRESS_RESET_PRESSES - _progress_reset_count,
		"删档重来"
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
	_artwork_rect = BackdropScript.fit_phone_artwork_rect(size)
	_safe_rect = BackdropScript.fit_safe_rect(size)
	backdrop.call("configure", _artwork_rect)
	artwork.position = _artwork_rect.position
	artwork.size = _artwork_rect.size
	var safe_width: float = _safe_rect.size.x
	var safe_height: float = _safe_rect.size.y
	var content_width: float = clampf(safe_width * 0.46, 210.0, 330.0)
	var base_title_height: float = clampf(safe_width * 0.09, 44.0, 72.0)
	var title_width: float = content_width * 1.50
	var title_height: float = base_title_height * 1.50
	var title_center_y: float = (
		_safe_rect.position.y + safe_height * 0.105 + base_title_height * 0.5
	)
	title_label.position = Vector2(
		_safe_rect.get_center().x - title_width * 0.5,
		title_center_y - title_height * 0.5
	)
	title_label.size = Vector2(title_width, title_height)
	title_label.pivot_offset = title_label.size * 0.5
	title_label.add_theme_font_size_override(
		"font_size",
		roundi(clampf(safe_width * 0.068, 32.0, 52.0))
	)
	var button_height: float = clampf(safe_width * 0.105, 54.0, 72.0)
	var button_gap: float = clampf(safe_width * 0.018, 8.0, 14.0)
	var actions_height: float = button_height * 3.0 + button_gap * 2.0
	var actions_y: float = _safe_rect.position.y + safe_height * 0.255
	var actions: VBoxContainer = $MenuLayer/Actions
	actions.position = Vector2(
		_safe_rect.get_center().x - content_width * 0.5,
		actions_y
	)
	actions.size = Vector2(content_width, actions_height)
	actions.add_theme_constant_override("separation", roundi(button_gap))
	for button: Button in [journey_button, run_reset_button, progress_reset_button]:
		button.custom_minimum_size = Vector2(content_width, button_height)
		button.add_theme_font_size_override(
			"font_size",
			roundi(clampf(safe_width * 0.043, 23.0, 34.0))
		)
	var notice_height: float = clampf(safe_width * 0.11, 52.0, 72.0)
	var notice_width: float = content_width * 1.4
	notice_label.position = Vector2(
		_safe_rect.get_center().x - notice_width * 0.5,
		actions_y + actions_height + button_gap - 275
	)
	notice_label.size = Vector2(notice_width, notice_height)
	notice_label.add_theme_font_size_override(
		"font_size",
		roundi(clampf(safe_width * 0.03, 16.0, 23.0))
	)
