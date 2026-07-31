class_name RewardSelectionController
extends Control

signal back_requested
signal reward_claimed

const CARD_SCENE: PackedScene = preload("res://scenes/card_view.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const Decks = preload("res://scripts/duel_decks.gd")
const Settings = preload("res://scripts/game_settings.gd")
const Store = preload("res://scripts/deck_profile_store.gd")
const SelectionShell = preload("res://scripts/deck_selection_shell.gd")
const CardInspectorData = preload("res://scripts/card_inspector.gd")

const DEFAULT_STATUS: String = "长按奖励卡牌，然后拖至主牌组"

@export var profile_path: String = Store.DEFAULT_SAVE_PATH
@export var upcoming_enemy_name: String = "对手名字"
@export var upcoming_enemy_card_ids: Array[StringName] = []
@export var remembered_enemy_glyphs: Array[String] = []
@export var hold_duration: float = 0.25
@export var library_aspect_ratio: float = 0.78
@export var reward_color_seed: int = 0

var testing_mode: bool = Settings.TESTING_MODE
var profile: Dictionary = {}
var _profile_store: RefCounted
var _reward_ids: Array[StringName] = []
var _reward_display_owner_ids: Array[int] = []
var _inspection_open: bool = false
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
@onready var library_grid: DeckLibraryGrid = $DuelCanvas/DeckLibraryGrid
@onready var go_first_button: Button = $DuelCanvas/GoFirstButton
@onready var go_second_button: Button = $DuelCanvas/GoSecondButton
@onready var player_hand: HBoxContainer = $DuelCanvas/PlayerHand
@onready var status_label: Label = $DuelCanvas/Status
@onready var drag_layer: Control = $DuelCanvas/DragLayer
@onready var card_inspector: CardInspectorData = $DuelCanvas/CardInspector


func _ready() -> void:
	var catalog_errors: Array[String] = Catalog.validate_catalog()
	assert(catalog_errors.is_empty(), "Invalid card catalog: %s" % str(catalog_errors))
	_profile_store = Store.new(profile_path)
	profile = _profile_store.load_profile()
	_reward_ids = _profile_store.get_pending_reward_ids(profile)
	SelectionShell.style_header(
		top_wash,
		top_wash_tint,
		top_wash_edge,
		top_wash_shadow,
		enemy_seal,
		enemy_seal_label,
		opponent_name,
		back_button
	)
	_create_hands()
	go_first_button.visible = false
	go_first_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	go_second_button.visible = false
	go_second_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	library_grid.set_hold_duration(hold_duration)
	_roll_reward_display_owners()
	_refresh_reward_grid()
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


func debug_get_reward_ids() -> Array[StringName]:
	return _reward_ids.duplicate()


func debug_get_reward_display_owner_ids() -> Array[int]:
	return _reward_display_owner_ids.duplicate()


func debug_is_inspecting() -> bool:
	return _inspection_open


func debug_claim_reward(reward_index: int) -> bool:
	return _claim_reward(reward_index)


func _create_hands() -> void:
	SelectionShell.create_hand_slots(opponent_hand)
	SelectionShell.create_hand_slots(player_hand)
	var enemy_ids: Array[StringName] = upcoming_enemy_card_ids.duplicate()
	if enemy_ids.size() != 5:
		enemy_ids = Decks.get_opponent_card_ids()
	for card_index: int in range(5):
		var enemy_data: Dictionary = Catalog.create_instance(
			enemy_ids[card_index],
			DuelRules.OPPONENT_OWNER,
			StringName("reward_enemy_%d" % card_index)
		)
		var enemy_card: CardView = _spawn_card_in_slot(
			opponent_hand.get_child(card_index) as PanelContainer,
			enemy_data,
			DuelRules.OPPONENT_OWNER
		)
		var glyph: String = String(enemy_data.get("glyph", ""))
		enemy_card.set_face_down(
			not testing_mode and glyph not in remembered_enemy_glyphs
		)
	var main_deck: Array[StringName] = _profile_store.get_main_deck_ids(profile)
	for card_index: int in range(5):
		var player_data: Dictionary = Catalog.create_instance(
			main_deck[card_index],
			DuelRules.PLAYER_OWNER,
			StringName("reward_player_%d" % card_index)
		)
		_spawn_card_in_slot(
			player_hand.get_child(card_index) as PanelContainer,
			player_data,
			DuelRules.PLAYER_OWNER
		)


func _spawn_card_in_slot(
	slot: PanelContainer,
	data: Dictionary,
	owner_id: int
) -> CardView:
	var card := CARD_SCENE.instantiate() as CardView
	slot.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.configure(data, owner_id, false)
	card.inspection_requested.connect(_on_card_inspection_requested)
	return card


func _refresh_reward_grid() -> void:
	var entries: Array = []
	var drag_enabled: Array = []
	for reward_index: int in range(3):
		if reward_index < _reward_ids.size():
			entries.append(String(_reward_ids[reward_index]))
			drag_enabled.append(true)
		else:
			entries.append({"_display_placeholder": true})
			drag_enabled.append(false)
	library_grid.set_display_entries(
		entries,
		_reward_display_owner_ids,
		drag_enabled,
		true
	)


func _roll_reward_display_owners() -> void:
	var random := RandomNumberGenerator.new()
	if reward_color_seed == 0:
		random.randomize()
	else:
		random.seed = reward_color_seed
	_reward_display_owner_ids.clear()
	for reward_index: int in range(3):
		_reward_display_owner_ids.append(
			DuelRules.PLAYER_OWNER
			if random.randi_range(0, 1) == 0
			else DuelRules.OPPONENT_OWNER
		)


func _on_library_inspection_requested(
	_logical_index: int,
	data: Dictionary
) -> void:
	_on_card_inspection_requested(data)


func _on_card_inspection_requested(data: Dictionary) -> void:
	if _inspection_open or data.is_empty() or bool(data.get("_display_placeholder", false)):
		return
	_inspection_open = true
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
	status_label.text = DEFAULT_STATUS


func _on_library_drag_started(
	logical_index: int,
	data: Dictionary,
	pointer_position: Vector2
) -> void:
	if _inspection_open or _drag_proxy != null or logical_index >= _reward_ids.size():
		return
	_drag_source_index = logical_index
	_drag_proxy = CARD_SCENE.instantiate() as CardView
	drag_layer.add_child(_drag_proxy)
	_drag_proxy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_proxy.set_ki_badge_enabled(false)
	_drag_proxy.configure(data, library_grid.get_display_owner_id(logical_index), false)
	var source_slot: Variant = library_grid.debug_get_bound_slot(logical_index)
	var source_size: Vector2 = _drag_proxy.size
	if source_slot != null:
		source_size = source_slot.get_drag_preview_size()
	_drag_proxy.size = source_size
	_drag_proxy_offset = Vector2(-source_size.x * 0.5, -source_size.y * 0.72)
	_position_drag_proxy(pointer_position)


func _on_library_drag_moved(
	_logical_index: int,
	pointer_position: Vector2
) -> void:
	_position_drag_proxy(pointer_position)


func _on_library_drag_ended(
	logical_index: int,
	pointer_position: Vector2
) -> void:
	if _drag_proxy == null or logical_index != _drag_source_index:
		_clear_drag_proxy()
		return
	if player_hand.get_global_rect().has_point(pointer_position):
		_claim_reward(logical_index)
	_clear_drag_proxy()


func _claim_reward(reward_index: int) -> bool:
	if reward_index < 0 or reward_index >= _reward_ids.size():
		return false
	var result: Dictionary = _profile_store.claim_pending_reward_and_save(
		profile,
		_reward_ids[reward_index]
	)
	if not bool(result.get("ok", false)):
		status_label.text = "保存失败，请重试"
		return false
	profile = result.get("profile", profile)
	_reward_ids.clear()
	reward_claimed.emit()
	return true


func _position_drag_proxy(pointer_position: Vector2) -> void:
	if _drag_proxy == null:
		return
	var local_pointer: Vector2 = (
		drag_layer.get_global_transform_with_canvas().affine_inverse()
		* pointer_position
	)
	_drag_proxy.position = local_pointer + _drag_proxy_offset


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
	SelectionShell.apply_core_layout(
		size,
		library_aspect_ratio,
		decor_backdrop,
		duel_canvas,
		top_wash,
		top_bar,
		opponent_hand,
		library_grid,
		player_hand,
		status_label
	)
	if _inspection_open:
		card_inspector.set_board_rect(_get_library_rect())


func _get_library_rect() -> Rect2:
	return Rect2(
		library_grid.global_position - duel_canvas.global_position,
		library_grid.size
	)
