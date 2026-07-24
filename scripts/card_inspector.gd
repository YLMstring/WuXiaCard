class_name CardInspector
extends Control

signal inspection_closed

@export var close_drag_threshold: float = 12.0

const PLACEHOLDER: String = "—"

var _open: bool = false
var _pointer_active: bool = false
var _pointer_id: int = -2
var _press_position: Vector2 = Vector2.ZERO
var _gesture_moved: bool = false
var _card_snapshot: Dictionary = {}

@onready var parchment: Control = $Parchment
@onready var shadow: Panel = $Parchment/Shadow
@onready var body: PanelContainer = $Parchment/Body
@onready var top_rod: Panel = $Parchment/TopRod
@onready var bottom_rod: Panel = $Parchment/BottomRod
@onready var scroll: ScrollContainer = $Parchment/Body/Margin/Scroll
@onready var content: VBoxContainer = $Parchment/Body/Margin/Scroll/Content
@onready var title: Label = $Parchment/Body/Margin/Scroll/Content/Title
@onready var tags: HBoxContainer = $Parchment/Body/Margin/Scroll/Content/Tags
@onready var sect_tag: PanelContainer = $Parchment/Body/Margin/Scroll/Content/Tags/SectTag
@onready var sect_value: Label = $Parchment/Body/Margin/Scroll/Content/Tags/SectTag/Value
@onready var tier_tag: PanelContainer = $Parchment/Body/Margin/Scroll/Content/Tags/TierTag
@onready var tier_value: Label = $Parchment/Body/Margin/Scroll/Content/Tags/TierTag/Value
@onready var weapon_tag: PanelContainer = $Parchment/Body/Margin/Scroll/Content/Tags/WeaponTag
@onready var weapon_value: Label = $Parchment/Body/Margin/Scroll/Content/Tags/WeaponTag/Value
@onready var description: Label = $Parchment/Body/Margin/Scroll/Content/Description
@onready var flavor: Label = $Parchment/Body/Margin/Scroll/Content/Flavor


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_input(true)
	_style_inspector()
	visible = false


func present(card_data: Dictionary, board_rect: Rect2) -> void:
	_card_snapshot = card_data.duplicate(true)
	title.text = _display_string(_card_snapshot.get("glyph", ""))
	sect_value.text = _display_string(_card_snapshot.get("sect", ""))
	tier_value.text = _display_tier(_card_snapshot.get("tier", null))
	weapon_value.text = _display_string(_card_snapshot.get("weapon", ""))
	description.text = _display_string(_card_snapshot.get("description", ""))
	flavor.text = _display_string(_card_snapshot.get("flavor", ""))
	set_board_rect(board_rect)
	scroll.scroll_vertical = 0
	_reset_pointer()
	_open = true
	visible = true


func set_board_rect(board_rect: Rect2) -> void:
	parchment.position = board_rect.position
	parchment.size = board_rect.size
	var short_side: float = maxf(1.0, minf(board_rect.size.x, board_rect.size.y))
	title.add_theme_font_size_override("font_size", clampi(int(short_side * 0.085), 22, 32))
	description.add_theme_font_size_override("font_size", clampi(int(short_side * 0.046), 14, 18))
	flavor.add_theme_font_size_override("font_size", clampi(int(short_side * 0.040), 12, 16))


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_reset_pointer()
	inspection_closed.emit()


func is_open() -> bool:
	return _open


func get_card_snapshot() -> Dictionary:
	return _card_snapshot.duplicate(true)


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_event.pressed:
			_begin_pointer(mouse_event.position, -1)
		else:
			_end_pointer(mouse_event.position, -1)
	elif event is InputEventMouseMotion and _pointer_active and _pointer_id == -1:
		_update_pointer((event as InputEventMouseMotion).position)
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			_begin_pointer(touch_event.position, touch_event.index)
		else:
			_end_pointer(touch_event.position, touch_event.index)
	elif event is InputEventScreenDrag and _pointer_active:
		var drag_event := event as InputEventScreenDrag
		if drag_event.index == _pointer_id:
			_update_pointer(drag_event.position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_reset_pointer()


func _begin_pointer(pointer_position: Vector2, pointer_id: int) -> void:
	if _pointer_active:
		return
	_pointer_active = true
	_pointer_id = pointer_id
	_press_position = pointer_position
	_gesture_moved = false


func _update_pointer(pointer_position: Vector2) -> void:
	if not _pointer_active:
		return
	if pointer_position.distance_to(_press_position) > close_drag_threshold:
		_gesture_moved = true


func _end_pointer(pointer_position: Vector2, pointer_id: int) -> void:
	if not _pointer_active or pointer_id != _pointer_id:
		return
	_update_pointer(pointer_position)
	var should_close: bool = not _gesture_moved
	_reset_pointer()
	if should_close:
		close()


func _reset_pointer() -> void:
	_pointer_active = false
	_pointer_id = -2
	_press_position = Vector2.ZERO
	_gesture_moved = false


func _display_string(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return PLACEHOLDER
	var text_value: String = String(value).strip_edges()
	return text_value if not text_value.is_empty() else PLACEHOLDER


func _display_tier(value: Variant) -> String:
	if typeof(value) != TYPE_INT or int(value) < 1:
		return PLACEHOLDER
	if int(value) == 1:
		return "入门"
	if int(value) == 2:
		return "不凡"
	if int(value) == 3:
		return "上乘"
	if int(value) == 4:
		return "一流"
	if int(value) == 5:
		return "绝世"
	return "秘传"


func _style_inspector() -> void:
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = Color(0.12, 0.07, 0.04, 0.28)
	shadow_style.set_corner_radius_all(7)
	shadow.add_theme_stylebox_override("panel", shadow_style)

	var parchment_style := StyleBoxFlat.new()
	parchment_style.bg_color = Color("eddbb2")
	parchment_style.border_color = Color("946a3e")
	parchment_style.set_border_width_all(2)
	parchment_style.set_corner_radius_all(5)
	body.add_theme_stylebox_override("panel", parchment_style)

	var rod_style := StyleBoxFlat.new()
	rod_style.bg_color = Color("725033")
	rod_style.border_color = Color("3f2b20")
	rod_style.set_border_width_all(1)
	rod_style.set_corner_radius_all(5)
	top_rod.add_theme_stylebox_override("panel", rod_style)
	bottom_rod.add_theme_stylebox_override("panel", rod_style)

	for tag: PanelContainer in [sect_tag, tier_tag, weapon_tag]:
		var tag_style := StyleBoxFlat.new()
		tag_style.bg_color = Color("e1c99a")
		tag_style.border_color = Color("71583d")
		tag_style.set_border_width_all(1)
		tag_style.set_corner_radius_all(10)
		tag_style.content_margin_left = 8.0
		tag_style.content_margin_right = 8.0
		tag_style.content_margin_top = 3.0
		tag_style.content_margin_bottom = 3.0
		tag.add_theme_stylebox_override("panel", tag_style)
