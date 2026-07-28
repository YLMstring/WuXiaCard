class_name DeckLibrarySlot
extends Control

signal inspection_requested(logical_index: int, card_data: Dictionary)
signal drag_armed(logical_index: int, card_data: Dictionary)
signal drag_started(logical_index: int, card_data: Dictionary, pointer_position: Vector2)
signal drag_moved(logical_index: int, pointer_position: Vector2)
signal drag_ended(logical_index: int, pointer_position: Vector2)
signal mouse_scroll_started(logical_index: int, pointer_position: Vector2, initial_delta_y: float)

@export var hold_duration: float = 0.25
@export var movement_threshold: float = 12.0

const CARD_ASPECT_RATIO: float = 0.75
const HOLD_SCALE: float = 1.035
const BASE_CARD_NAME_GAP: float = 4.0
const CARD_NAME_GAP: float = 6.0
const ROW_HEIGHT_INCREMENT: float = CARD_NAME_GAP - BASE_CARD_NAME_GAP
const TIER_NAME_COLORS: Dictionary = {
	1: Color("66717a"),
	2: Color("3e7659"),
	3: Color("3f6f9c"),
	4: Color("715a96"),
	5: Color("9a612d"),
}
const OTHER_TIER_NAME_COLOR: Color = Color("963f4a")

var logical_index: int = -1
var card_data: Dictionary = {}
var display_owner_id: int = DuelRules.PLAYER_OWNER
var interaction_enabled: bool = true

var _pointer_active: bool = false
var _pointer_id: int = -2
var _pointer_start: Vector2 = Vector2.ZERO
var _scrolling: bool = false
var _drag_is_armed: bool = false
var _dragging: bool = false
var _drag_vacancy_visible: bool = false

@onready var empty_frame: PanelContainer = $CardHost/EmptyFrame
@onready var card_view: CardView = $CardHost/CardView
@onready var name_label: Label = $Name
@onready var hold_timer: Timer = $HoldTimer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	hold_timer.one_shot = true
	hold_timer.timeout.connect(_on_hold_timeout)
	card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_view.set_ki_badge_enabled(false)
	resized.connect(_layout_content)
	_style_empty_frame()
	_layout_content()
	bind(-1, {})


func bind(
	new_logical_index: int,
	new_card_data: Dictionary,
	new_display_owner_id: int = DuelRules.PLAYER_OWNER
) -> void:
	cancel_gesture()
	logical_index = new_logical_index
	card_data = new_card_data.duplicate(true)
	display_owner_id = (
		DuelRules.OPPONENT_OWNER
		if new_display_owner_id == DuelRules.OPPONENT_OWNER
		else DuelRules.PLAYER_OWNER
	)
	var occupied: bool = not card_data.is_empty()
	empty_frame.visible = not occupied
	card_view.visible = occupied
	name_label.text = String(card_data.get("glyph", "")) if occupied else ""
	name_label.remove_theme_color_override("font_color")
	if occupied:
		name_label.add_theme_color_override("font_color", _tier_name_color(card_data.get("tier", null)))
		card_view.configure(card_data, display_owner_id, false)
		card_view.set_face_down(false)
	_set_drag_vacancy_visible(false)
	modulate = Color.WHITE
	scale = Vector2.ONE


func set_interaction_enabled(value: bool) -> void:
	interaction_enabled = value
	if not interaction_enabled:
		cancel_gesture()


func set_hold_duration(value: float) -> void:
	hold_duration = maxf(0.0, value)


func cancel_gesture() -> void:
	hold_timer.stop()
	_pointer_active = false
	_pointer_id = -2
	_pointer_start = Vector2.ZERO
	_scrolling = false
	_drag_is_armed = false
	_dragging = false
	_set_drag_vacancy_visible(false)
	scale = Vector2.ONE
	z_index = 0


func is_empty() -> bool:
	return card_data.is_empty()


func is_drag_armed() -> bool:
	return _drag_is_armed


func is_dragging() -> bool:
	return _dragging


func get_drag_preview_size() -> Vector2:
	return $CardHost.size * HOLD_SCALE


func debug_begin_pointer(pointer_position: Vector2, pointer_id: int = -1) -> void:
	_begin_pointer(pointer_position, pointer_id)


func debug_move_pointer(pointer_position: Vector2) -> void:
	_update_pointer(pointer_position)


func debug_end_pointer(pointer_position: Vector2, pointer_id: int = -1) -> void:
	_end_pointer(pointer_position, pointer_id)


func debug_force_hold_timeout() -> void:
	_on_hold_timeout()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_event.pressed:
			_begin_pointer(mouse_event.global_position, -1)
		else:
			_end_pointer(mouse_event.global_position, -1)
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			_begin_pointer(touch_event.position, touch_event.index)
		else:
			_end_pointer(touch_event.position, touch_event.index)


func _input(event: InputEvent) -> void:
	if not _pointer_active:
		return
	if event is InputEventMouseMotion and _pointer_id == -1:
		_update_pointer((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton and _pointer_id == -1:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			_end_pointer(mouse_event.position, -1)
	elif event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if drag_event.index == _pointer_id:
			_update_pointer(drag_event.position)
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.index == _pointer_id and not touch_event.pressed:
			_end_pointer(touch_event.position, touch_event.index)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		cancel_gesture()


func _begin_pointer(pointer_position: Vector2, pointer_id: int) -> void:
	if not interaction_enabled or _pointer_active:
		return
	_pointer_active = true
	_pointer_id = pointer_id
	_pointer_start = pointer_position
	_scrolling = false
	_drag_is_armed = false
	_dragging = false
	if not card_data.is_empty():
		hold_timer.start(hold_duration)


func _update_pointer(pointer_position: Vector2) -> void:
	if not _pointer_active:
		return
	if _drag_is_armed:
		if not _dragging:
			_dragging = true
			_set_drag_vacancy_visible(true)
			drag_started.emit(logical_index, card_data.duplicate(true), pointer_position)
		drag_moved.emit(logical_index, pointer_position)
		return
	if pointer_position.distance_to(_pointer_start) > movement_threshold:
		_scrolling = true
		hold_timer.stop()
		if _pointer_id == -1:
			mouse_scroll_started.emit(
				logical_index,
				pointer_position,
				pointer_position.y - _pointer_start.y
			)


func _end_pointer(pointer_position: Vector2, pointer_id: int) -> void:
	if not _pointer_active or pointer_id != _pointer_id:
		return
	if _dragging or _drag_is_armed:
		drag_ended.emit(logical_index, pointer_position)
	elif not _scrolling and not _drag_is_armed and not card_data.is_empty():
		if pointer_position.distance_to(_pointer_start) <= movement_threshold:
			inspection_requested.emit(logical_index, card_data.duplicate(true))
	cancel_gesture()


func _on_hold_timeout() -> void:
	if not _pointer_active or _scrolling or card_data.is_empty() or not interaction_enabled:
		return
	_drag_is_armed = true
	pivot_offset = size * 0.5
	scale = Vector2.ONE * HOLD_SCALE
	z_index = 2
	drag_armed.emit(logical_index, card_data.duplicate(true))


func _layout_content() -> void:
	if not is_node_ready():
		return
	var label_height: float = clampf(size.x * 0.18, 14.0, 18.0)
	var desired_card_size := Vector2(size.x, size.x / CARD_ASPECT_RATIO)
	var available_card_height: float = maxf(1.0, size.y - label_height - CARD_NAME_GAP)
	var card_height: float = minf(desired_card_size.y, available_card_height)
	var card_width: float = card_height * CARD_ASPECT_RATIO
	var group_height: float = card_height + CARD_NAME_GAP + label_height
	var group_top: float = maxf(0.0, (size.y - group_height) * 0.5)
	$CardHost.position = Vector2((size.x - card_width) * 0.5, group_top)
	$CardHost.size = Vector2(card_width, card_height)
	name_label.position = Vector2(0.0, group_top + card_height + CARD_NAME_GAP)
	name_label.size = Vector2(size.x, label_height)
	var short_side: float = maxf(1.0, minf($CardHost.size.x, $CardHost.size.y))
	name_label.add_theme_font_size_override("font_size", clampi(int(short_side * 0.17), 9, 14))


func _set_drag_vacancy_visible(value: bool) -> void:
	_drag_vacancy_visible = value and not card_data.is_empty()
	var occupied: bool = not card_data.is_empty()
	card_view.visible = occupied and not _drag_vacancy_visible
	empty_frame.visible = not occupied or _drag_vacancy_visible
	name_label.visible = not _drag_vacancy_visible
	if _drag_vacancy_visible:
		scale = Vector2.ONE
		z_index = 0


func _tier_name_color(tier_value: Variant) -> Color:
	if typeof(tier_value) == TYPE_INT and TIER_NAME_COLORS.has(int(tier_value)):
		return TIER_NAME_COLORS[int(tier_value)] as Color
	return OTHER_TIER_NAME_COLOR


func _style_empty_frame() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.06)
	style.border_color = Color(0.35, 0.31, 0.24, 0.17)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	empty_frame.add_theme_stylebox_override("panel", style)
