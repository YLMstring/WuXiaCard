class_name DeckLibraryGrid
extends Control

signal inspection_requested(logical_index: int, card_data: Dictionary)
signal drag_armed(logical_index: int, card_data: Dictionary)
signal drag_started(logical_index: int, card_data: Dictionary, pointer_position: Vector2)
signal drag_moved(logical_index: int, pointer_position: Vector2)
signal drag_ended(logical_index: int, pointer_position: Vector2)

const SLOT_SCENE: PackedScene = preload("res://scenes/deck_library_slot.tscn")
const SlotLayoutData = preload("res://scripts/deck_library_slot.gd")
const ParchmentChromeData = preload("res://scripts/parchment_chrome.gd")
const COLUMN_COUNT: int = 4
const TOTAL_SLOTS: int = 1000
const TOTAL_ROWS: int = 250
const VISIBLE_ROWS: int = 3
const BUFFER_ROWS: int = 1
const POOLED_ROWS: int = VISIBLE_ROWS + BUFFER_ROWS * 2
const CONTENT_TOP_PADDING: float = 8.0
const CONTENT_SIDE_PADDING: float = 7.0

@export var hold_duration: float = 0.25

var library_slots: Array = []
var library_display_owner_ids: Array[int] = []
var interaction_enabled: bool = true
var _slot_pool: Array = []
var _row_height: float = 1.0
var _column_width: float = 1.0
var _pool_start_row: int = -1
var _recycling_frozen: bool = false
var _pending_refresh: bool = false
var _manual_mouse_scroll_active: bool = false
var _manual_mouse_scroll_last: Vector2 = Vector2.ZERO

@onready var shadow: Panel = $Shadow
@onready var body: PanelContainer = $Body
@onready var top_rod: Panel = $TopRod
@onready var bottom_rod: Panel = $BottomRod
@onready var title: Label = $Body/Margin/Layout/Title
@onready var scroll: ScrollContainer = $Body/Margin/Layout/Scroll
@onready var content: Control = $Body/Margin/Layout/Scroll/Content


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.get_v_scroll_bar().value_changed.connect(_on_scroll_changed)
	resized.connect(_queue_layout_grid)
	_style_parchment()
	_create_pool()
	set_library_slots([])
	_queue_layout_grid()


func set_library_slots(values: Array, display_owner_ids: Array[int] = []) -> void:
	library_slots = values.duplicate()
	library_slots.resize(TOTAL_SLOTS)
	library_display_owner_ids.resize(TOTAL_SLOTS)
	for index: int in range(TOTAL_SLOTS):
		if library_slots[index] == null:
			library_slots[index] = ""
		library_display_owner_ids[index] = _normalized_display_owner(
			display_owner_ids[index] if index < display_owner_ids.size() else DuelRules.PLAYER_OWNER
		)
	_pending_refresh = true
	_refresh_pool(true)


func set_scroll_offset(value: float) -> void:
	scroll.scroll_vertical = maxi(0, int(value))
	_refresh_pool()


func get_scroll_offset() -> float:
	return float(scroll.scroll_vertical)


func refresh_logical_index(logical_index: int, value: Variant) -> void:
	if logical_index < 0 or logical_index >= TOTAL_SLOTS:
		return
	library_slots[logical_index] = value
	var visible_slot: Variant = debug_get_bound_slot(logical_index)
	if visible_slot != null:
		_bind_slot(visible_slot, logical_index)


func set_interaction_enabled(value: bool) -> void:
	interaction_enabled = value
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	for slot: Variant in _slot_pool:
		slot.set_interaction_enabled(value)
	if not value:
		cancel_active_gesture()


func cancel_active_gesture() -> void:
	for slot: Variant in _slot_pool:
		slot.cancel_gesture()
	_manual_mouse_scroll_active = false
	_recycling_frozen = false
	if _pending_refresh:
		_refresh_pool(true)


func set_hold_duration(value: float) -> void:
	hold_duration = maxf(0.0, value)
	for slot: Variant in _slot_pool:
		slot.set_hold_duration(hold_duration)


func debug_get_pool_size() -> int:
	return _slot_pool.size()


func debug_get_bound_indices() -> Array[int]:
	var result: Array[int] = []
	for slot: Variant in _slot_pool:
		result.append(slot.logical_index)
	return result


func debug_get_bound_slot(logical_index: int) -> Variant:
	for slot: Variant in _slot_pool:
		if slot.logical_index == logical_index:
			return slot
	return null


func debug_get_row_height() -> float:
	return _row_height


func get_display_owner_id(logical_index: int) -> int:
	if logical_index < 0 or logical_index >= library_display_owner_ids.size():
		return DuelRules.PLAYER_OWNER
	return _normalized_display_owner(library_display_owner_ids[logical_index])


func _create_pool() -> void:
	for pool_index: int in range(POOLED_ROWS * COLUMN_COUNT):
		var slot: Variant = SLOT_SCENE.instantiate()
		slot.name = "PooledSlot%d" % pool_index
		content.add_child(slot)
		slot.set_hold_duration(hold_duration)
		slot.inspection_requested.connect(_on_slot_inspection_requested)
		slot.drag_armed.connect(_on_slot_drag_armed)
		slot.drag_started.connect(_on_slot_drag_started)
		slot.drag_moved.connect(_on_slot_drag_moved)
		slot.drag_ended.connect(_on_slot_drag_ended)
		slot.mouse_scroll_started.connect(_on_slot_mouse_scroll_started)
		_slot_pool.append(slot)


func _queue_layout_grid() -> void:
	_layout_grid.call_deferred()


func _layout_grid() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	title.add_theme_font_size_override("font_size", clampi(int(size.x * 0.07), 22, 30))
	if scroll.size.x <= 0.0 or scroll.size.y <= 0.0:
		return
	var horizontal_gap: float = 6.0
	var usable_width: float = scroll.size.x - CONTENT_SIDE_PADDING * 2.0
	_column_width = maxf(1.0, (usable_width - horizontal_gap * float(COLUMN_COUNT - 1)) / float(COLUMN_COUNT))
	var fitted_row_height: float = (
		(scroll.size.y - CONTENT_TOP_PADDING) / float(VISIBLE_ROWS)
	)
	_row_height = maxf(1.0, fitted_row_height + SlotLayoutData.ROW_HEIGHT_INCREMENT)
	content.custom_minimum_size = Vector2(
		scroll.size.x,
		CONTENT_TOP_PADDING + _row_height * float(TOTAL_ROWS)
	)
	for slot: Variant in _slot_pool:
		slot.size = Vector2(_column_width, _row_height)
	_pending_refresh = true
	_refresh_pool(true)


func _refresh_pool(force: bool = false) -> void:
	if not is_node_ready() or _slot_pool.is_empty():
		return
	if _recycling_frozen:
		_pending_refresh = true
		return
	var effective_scroll: float = maxf(0.0, float(scroll.scroll_vertical) - CONTENT_TOP_PADDING)
	var first_visible_row: int = clampi(int(floor(effective_scroll / _row_height)), 0, TOTAL_ROWS - VISIBLE_ROWS)
	var start_row: int = clampi(first_visible_row - BUFFER_ROWS, 0, TOTAL_ROWS - POOLED_ROWS)
	if not force and not _pending_refresh and start_row == _pool_start_row:
		return
	_pool_start_row = start_row
	_pending_refresh = false
	var horizontal_gap: float = 6.0
	for pool_index: int in range(_slot_pool.size()):
		var pool_row: int = floori(float(pool_index) / float(COLUMN_COUNT))
		var column: int = pool_index % COLUMN_COUNT
		var logical_row: int = start_row + pool_row
		var logical_index: int = logical_row * COLUMN_COUNT + column
		var slot: Variant = _slot_pool[pool_index]
		slot.position = Vector2(
			CONTENT_SIDE_PADDING + float(column) * (_column_width + horizontal_gap),
			CONTENT_TOP_PADDING + float(logical_row) * _row_height
		)
		_bind_slot(slot, logical_index)


func _bind_slot(slot: Variant, logical_index: int) -> void:
	var value: Variant = library_slots[logical_index] if logical_index >= 0 and logical_index < library_slots.size() else ""
	if String(value).is_empty():
		slot.bind(logical_index, {})
		return
	var card_id := StringName(String(value))
	if card_id not in CardCatalog.get_all_card_ids():
		slot.bind(logical_index, {})
		return
	slot.bind(
		logical_index,
		CardCatalog.create_instance(
			card_id,
			DuelRules.PLAYER_OWNER,
			StringName("library_%d" % logical_index)
		),
		get_display_owner_id(logical_index)
	)
	slot.set_interaction_enabled(interaction_enabled)


func _normalized_display_owner(owner_id: int) -> int:
	if owner_id == DuelRules.OPPONENT_OWNER:
		return DuelRules.OPPONENT_OWNER
	return DuelRules.PLAYER_OWNER


func _on_scroll_changed(_value: float) -> void:
	_refresh_pool()


func _input(event: InputEvent) -> void:
	if not _manual_mouse_scroll_active:
		return
	if event is InputEventMouseMotion:
		var mouse_event := event as InputEventMouseMotion
		var delta_y: float = mouse_event.position.y - _manual_mouse_scroll_last.y
		_manual_mouse_scroll_last = mouse_event.position
		_apply_manual_mouse_scroll(delta_y)
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			_manual_mouse_scroll_active = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		_manual_mouse_scroll_active = false


func _on_slot_mouse_scroll_started(
	_logical_index: int,
	pointer_position: Vector2,
	initial_delta_y: float
) -> void:
	if not interaction_enabled:
		return
	_manual_mouse_scroll_active = true
	_manual_mouse_scroll_last = pointer_position
	_apply_manual_mouse_scroll(initial_delta_y)


func _apply_manual_mouse_scroll(delta_y: float) -> void:
	if is_zero_approx(delta_y):
		return
	scroll.scroll_vertical = maxi(0, scroll.scroll_vertical - roundi(delta_y))


func _on_slot_inspection_requested(logical_index: int, data: Dictionary) -> void:
	if interaction_enabled:
		inspection_requested.emit(logical_index, data)


func _on_slot_drag_armed(logical_index: int, data: Dictionary) -> void:
	if not interaction_enabled:
		return
	_recycling_frozen = true
	drag_armed.emit(logical_index, data)


func _on_slot_drag_started(logical_index: int, data: Dictionary, pointer_position: Vector2) -> void:
	if interaction_enabled:
		drag_started.emit(logical_index, data, pointer_position)


func _on_slot_drag_moved(logical_index: int, pointer_position: Vector2) -> void:
	if interaction_enabled:
		drag_moved.emit(logical_index, pointer_position)


func _on_slot_drag_ended(logical_index: int, pointer_position: Vector2) -> void:
	if interaction_enabled:
		drag_ended.emit(logical_index, pointer_position)
	_recycling_frozen = false
	if _pending_refresh:
		_refresh_pool(true)


func _style_parchment() -> void:
	ParchmentChromeData.apply(shadow, body, top_rod, bottom_rod)
