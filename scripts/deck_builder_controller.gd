class_name DeckBuilderController
extends Control

signal back_requested

const CARD_SCENE: PackedScene = preload("res://scenes/card_view.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const Decks = preload("res://scripts/duel_decks.gd")
const Settings = preload("res://scripts/game_settings.gd")
const Store = preload("res://scripts/deck_profile_store.gd")
const DuelBackdropData = preload("res://scripts/duel_backdrop.gd")
const CardInspectorData = preload("res://scripts/card_inspector.gd")

const DEFAULT_STATUS: String = "长按藏经阁卡牌，然后拖至主牌组"

@export var profile_path: String = Store.DEFAULT_SAVE_PATH
@export var upcoming_enemy_name: String = "对手名字"
@export var upcoming_enemy_card_ids: Array[StringName] = []
@export var hold_duration: float = 0.25
@export var library_aspect_ratio: float = 0.78

var testing_mode: bool = Settings.TESTING_MODE
var profile: Dictionary = {}
var _profile_store: RefCounted
var _inspection_open: bool = false
var _scroll_before_inspection: float = 0.0
var _drag_source_index: int = -1
var _drag_proxy: CardView = null
var _drag_proxy_offset: Vector2 = Vector2.ZERO

@onready var decor_backdrop: Control = $DecorBackdrop
@onready var duel_canvas: Control = $DuelCanvas
@onready var top_wash: ColorRect = $DuelCanvas/TopWash
@onready var top_wash_tint: TextureRect = $DuelCanvas/TopWash/CenterTint
@onready var top_wash_edge: ColorRect = $DuelCanvas/TopWash/BottomEdge
@onready var top_wash_shadow: ColorRect = $DuelCanvas/TopWash/Shadow
@onready var top_bar: HBoxContainer = $DuelCanvas/TopBar
@onready var enemy_seal: PanelContainer = $DuelCanvas/TopBar/EnemySeal
@onready var enemy_seal_label: Label = $DuelCanvas/TopBar/EnemySeal/Value
@onready var opponent_name: Label = $DuelCanvas/TopBar/OpponentName
@onready var back_button: Button = $DuelCanvas/TopBar/BackButton
@onready var opponent_hand: HBoxContainer = $DuelCanvas/OpponentHand
@onready var library_grid: Control = $DuelCanvas/DeckLibraryGrid
@onready var player_hand: HBoxContainer = $DuelCanvas/PlayerHand
@onready var status_label: Label = $DuelCanvas/Status
@onready var drag_layer: Control = $DuelCanvas/DragLayer
@onready var card_inspector: CardInspectorData = $DuelCanvas/CardInspector


func _ready() -> void:
	var catalog_errors: Array[String] = Catalog.validate_catalog()
	assert(catalog_errors.is_empty(), "Invalid card catalog: %s" % str(catalog_errors))
	_profile_store = Store.new(profile_path)
	profile = _profile_store.load_profile()
	_style_header()
	_create_hands()
	library_grid.set_hold_duration(hold_duration)
	library_grid.set_library_slots(profile["library_slots"])
	library_grid.inspection_requested.connect(_on_library_inspection_requested)
	library_grid.drag_started.connect(_on_library_drag_started)
	library_grid.drag_moved.connect(_on_library_drag_moved)
	library_grid.drag_ended.connect(_on_library_drag_ended)
	back_button.pressed.connect(_on_back_pressed)
	card_inspector.inspection_closed.connect(_on_inspection_closed)
	resized.connect(_layout_scene)
	get_viewport().size_changed.connect(_layout_scene)
	opponent_name.text = upcoming_enemy_name
	status_label.text = DEFAULT_STATUS
	_layout_scene.call_deferred()


func debug_exchange(library_index: int, deck_index: int) -> bool:
	var result: Dictionary = _profile_store.exchange_and_save(profile, library_index, deck_index)
	if not bool(result.get("ok", false)):
		return false
	profile = result["profile"]
	_refresh_player_slot(deck_index)
	library_grid.set_library_slots(profile["library_slots"])
	return true


func debug_get_profile() -> Dictionary:
	return profile.duplicate(true)


func debug_get_library_rect() -> Rect2:
	return _get_library_rect()


func debug_is_inspecting() -> bool:
	return _inspection_open


func _create_hands() -> void:
	_create_hand_slots(opponent_hand)
	_create_hand_slots(player_hand)
	var enemy_ids: Array[StringName] = upcoming_enemy_card_ids.duplicate()
	if enemy_ids.size() != 5:
		enemy_ids = Decks.get_opponent_card_ids()
	for card_index: int in range(5):
		var enemy_data: Dictionary = Catalog.create_instance(
			enemy_ids[card_index],
			DuelRules.OPPONENT_OWNER,
			StringName("deck_builder_enemy_%d" % card_index)
		)
		var enemy_card: CardView = _spawn_card_in_slot(
			opponent_hand.get_child(card_index) as PanelContainer,
			enemy_data,
			DuelRules.OPPONENT_OWNER
		)
		enemy_card.set_face_down(not testing_mode)
	for card_index: int in range(5):
		_refresh_player_slot(card_index)


func _create_hand_slots(container: HBoxContainer) -> void:
	for existing: Node in container.get_children():
		existing.queue_free()
	for slot_index: int in range(5):
		var slot := PanelContainer.new()
		slot.name = "Slot%d" % slot_index
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = Color(1.0, 1.0, 1.0, 0.06)
		slot_style.border_color = Color(1.0, 1.0, 1.0, 0.10)
		slot_style.set_border_width_all(1)
		slot_style.set_corner_radius_all(5)
		slot.add_theme_stylebox_override("panel", slot_style)
		container.add_child(slot)


func _refresh_player_slot(deck_index: int) -> void:
	if deck_index < 0 or deck_index >= player_hand.get_child_count():
		return
	var slot := player_hand.get_child(deck_index) as PanelContainer
	for child: Node in slot.get_children():
		slot.remove_child(child)
		child.queue_free()
	var card_id := StringName(String(profile["main_deck"][deck_index]))
	var card_data: Dictionary = Catalog.create_instance(
		card_id,
		DuelRules.PLAYER_OWNER,
		StringName("deck_builder_player_%d" % deck_index)
	)
	_spawn_card_in_slot(slot, card_data, DuelRules.PLAYER_OWNER)


func _spawn_card_in_slot(slot: PanelContainer, data: Dictionary, owner_id: int) -> CardView:
	var card := CARD_SCENE.instantiate() as CardView
	slot.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.configure(data, owner_id, false)
	card.inspection_requested.connect(_on_card_inspection_requested)
	return card


func _on_library_inspection_requested(_logical_index: int, data: Dictionary) -> void:
	_on_card_inspection_requested(data)


func _on_card_inspection_requested(data: Dictionary) -> void:
	if _inspection_open or data.is_empty():
		return
	_inspection_open = true
	_scroll_before_inspection = library_grid.get_scroll_offset()
	library_grid.set_interaction_enabled(false)
	library_grid.visible = false
	status_label.text = "查看卡牌详情 · 轻触返回"
	card_inspector.present(data, _get_library_rect())


func _on_inspection_closed() -> void:
	if not _inspection_open:
		return
	_inspection_open = false
	library_grid.visible = true
	library_grid.set_interaction_enabled(true)
	library_grid.set_scroll_offset(_scroll_before_inspection)
	status_label.text = DEFAULT_STATUS


func _on_library_drag_started(logical_index: int, data: Dictionary, pointer_position: Vector2) -> void:
	if _inspection_open or _drag_proxy != null:
		return
	_drag_source_index = logical_index
	_drag_proxy = CARD_SCENE.instantiate() as CardView
	drag_layer.add_child(_drag_proxy)
	_drag_proxy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_proxy.configure(data, DuelRules.PLAYER_OWNER, false)
	var source_slot: Variant = library_grid.debug_get_bound_slot(logical_index)
	var source_size: Vector2 = Vector2(64.0, 86.0)
	if source_slot != null:
		source_size = Vector2(source_slot.size.x, source_slot.size.y * 0.84)
	_drag_proxy.size = source_size
	_drag_proxy_offset = Vector2(-source_size.x * 0.5, -source_size.y * 0.72)
	_position_drag_proxy(pointer_position)


func _on_library_drag_moved(_logical_index: int, pointer_position: Vector2) -> void:
	_position_drag_proxy(pointer_position)


func _on_library_drag_ended(logical_index: int, pointer_position: Vector2) -> void:
	if _drag_proxy == null or logical_index != _drag_source_index:
		_clear_drag_proxy()
		return
	var deck_index: int = _get_player_slot_at(pointer_position)
	if deck_index >= 0:
		var result: Dictionary = _profile_store.exchange_and_save(profile, logical_index, deck_index)
		if bool(result.get("ok", false)):
			profile = result["profile"]
			_refresh_player_slot(deck_index)
			library_grid.set_library_slots(profile["library_slots"])
			status_label.text = DEFAULT_STATUS
		else:
			status_label.text = "保存失败"
	_clear_drag_proxy()


func _position_drag_proxy(pointer_position: Vector2) -> void:
	if _drag_proxy == null:
		return
	var local_pointer: Vector2 = drag_layer.get_global_transform_with_canvas().affine_inverse() * pointer_position
	_drag_proxy.position = local_pointer + _drag_proxy_offset


func _get_player_slot_at(pointer_position: Vector2) -> int:
	for slot_index: int in range(player_hand.get_child_count()):
		var slot := player_hand.get_child(slot_index) as Control
		if slot.get_global_rect().has_point(pointer_position):
			return slot_index
	return -1


func _clear_drag_proxy() -> void:
	if _drag_proxy != null:
		_drag_proxy.queue_free()
	_drag_proxy = null
	_drag_source_index = -1


func _on_back_pressed() -> void:
	back_requested.emit()


func _layout_scene() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	var fitted_rect: Rect2 = DuelBackdropData.fit_duel_rect(size)
	duel_canvas.position = fitted_rect.position
	duel_canvas.size = fitted_rect.size
	decor_backdrop.call("configure", fitted_rect)
	var canvas_size: Vector2 = duel_canvas.size
	var horizontal_margin: float = maxf(12.0, canvas_size.x * 0.03)
	var hand_width: float = canvas_size.x - horizontal_margin * 2.0
	var card_width: float = (hand_width - 16.0) / 5.0
	var hand_height: float = minf(canvas_size.y * 0.14, card_width / 0.75)
	var header_height: float = clampf(canvas_size.y * 0.0625, 56.0, 62.0)
	var header_gap: float = clampf(canvas_size.y * 0.0146, 12.0, 18.0)
	var top_bar_height: float = 44.0
	var opponent_top: float = header_height + header_gap
	var opponent_bottom: float = opponent_top + hand_height
	var status_gap: float = 8.0
	var status_height: float = 26.0
	var bottom_safe_margin: float = 8.0
	var player_bottom_margin: float = maxf(canvas_size.y * 0.05, status_gap + status_height + bottom_safe_margin)
	var player_top: float = canvas_size.y - player_bottom_margin - hand_height
	var interval_height: float = maxf(180.0, player_top - opponent_bottom)
	var minimum_gap: float = maxf(18.0, canvas_size.y * 0.032)
	var desired_width: float = canvas_size.x * 0.72
	var library_height: float = minf(desired_width / library_aspect_ratio, interval_height - minimum_gap * 2.0)
	var library_width: float = library_height * library_aspect_ratio
	var equal_gap: float = (interval_height - library_height) * 0.5
	var library_position := Vector2((canvas_size.x - library_width) * 0.5, opponent_bottom + equal_gap)

	top_wash.position = Vector2.ZERO
	top_wash.offset_bottom = header_height
	top_bar.position = Vector2(horizontal_margin, (header_height - top_bar_height) * 0.5)
	top_bar.size = Vector2(hand_width, top_bar_height)
	opponent_hand.position = Vector2(horizontal_margin, opponent_top)
	opponent_hand.size = Vector2(hand_width, hand_height)
	library_grid.position = library_position
	library_grid.size = Vector2(library_width, library_height)
	player_hand.position = Vector2(horizontal_margin, player_top)
	player_hand.size = Vector2(hand_width, hand_height)
	var desired_status_y: float = player_hand.position.y + player_hand.size.y + status_gap
	var maximum_status_y: float = canvas_size.y - bottom_safe_margin - status_height
	status_label.position = Vector2(player_hand.position.x, minf(desired_status_y, maximum_status_y))
	status_label.size = Vector2(player_hand.size.x, status_height)
	if _inspection_open:
		card_inspector.set_board_rect(_get_library_rect())


func _get_library_rect() -> Rect2:
	return Rect2(
		library_grid.global_position - duel_canvas.global_position,
		library_grid.size
	)


func _style_header() -> void:
	top_wash.color = DuelBackdropData.LACQUER_COLOR
	top_wash_edge.color = Color("c29969")
	top_wash_shadow.color = Color(0.08, 0.05, 0.04, 0.22)
	top_wash_shadow.offset_bottom = 3.0
	top_wash_tint.texture = DuelBackdropData.create_lacquer_tint_texture(540)
	var seal_style := StyleBoxFlat.new()
	seal_style.bg_color = Color("9e332f")
	seal_style.border_color = Color("c99261")
	seal_style.set_border_width_all(1)
	seal_style.set_corner_radius_all(2)
	seal_style.shadow_color = Color(0.08, 0.03, 0.02, 0.42)
	seal_style.shadow_size = 2
	seal_style.shadow_offset = Vector2(0.0, 1.0)
	enemy_seal.add_theme_stylebox_override("panel", seal_style)
	enemy_seal_label.add_theme_color_override("font_color", Color("f1d8b1"))
	enemy_seal_label.add_theme_font_size_override("font_size", 14)
	opponent_name.add_theme_color_override("font_color", Color("f2e4c7"))
	opponent_name.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.03, 0.55))
	opponent_name.add_theme_constant_override("outline_size", 1)
	opponent_name.add_theme_font_size_override("font_size", 22)
	opponent_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	opponent_name.clip_text = true
	var empty_style := StyleBoxEmpty.new()
	for style_name: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]:
		back_button.add_theme_stylebox_override(style_name, empty_style)
	back_button.add_theme_color_override("icon_normal_color", Color("e2c89c"))
	back_button.add_theme_color_override("icon_hover_color", Color("f4ddb2"))
	back_button.add_theme_color_override("icon_pressed_color", Color("cdb387"))
