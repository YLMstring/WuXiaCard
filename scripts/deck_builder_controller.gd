class_name DeckBuilderController
extends Control

signal back_requested
signal duel_requested(starting_owner_id: int)

const CARD_SCENE: PackedScene = preload("res://scenes/card_view.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const Decks = preload("res://scripts/duel_decks.gd")
const Settings = preload("res://scripts/game_settings.gd")
const Store = preload("res://scripts/deck_profile_store.gd")
const DuelBackdropData = preload("res://scripts/duel_backdrop.gd")
const CardInspectorData = preload("res://scripts/card_inspector.gd")

const DEFAULT_STATUS: String = "长按藏经阁卡牌，然后拖至主牌组"
const GO_FIRST_BLOCKED_NOTICE: String = "主卡组总品阶不高于对手时方可选择先攻"
const ACTIVE_INK_COLOR: Color = Color("1a1513")
const BLOCKED_INK_COLOR: Color = Color(0.52, 0.52, 0.52, 0.92)
const PRESSED_INK_COLOR: Color = Color(0.44, 0.44, 0.44, 0.82)
const CHOICE_SIZE_SCALE: float = 0.72
const PRESSED_CHOICE_SCALE: Vector2 = Vector2(0.94, 0.94)

@export var profile_path: String = Store.DEFAULT_SAVE_PATH
@export var upcoming_enemy_name: String = "对手名字"
@export var upcoming_enemy_card_ids: Array[StringName] = []
@export var hold_duration: float = 0.25
@export var library_aspect_ratio: float = 0.78
@export var library_color_seed: int = 0

var testing_mode: bool = Settings.TESTING_MODE
var profile: Dictionary = {}
var _profile_store: RefCounted
var _inspection_open: bool = false
var _scroll_before_inspection: float = 0.0
var _drag_source_index: int = -1
var _drag_proxy: CardView = null
var _drag_proxy_offset: Vector2 = Vector2.ZERO
var _effective_enemy_card_ids: Array[StringName] = []
var _go_first_allowed: bool = true
var _go_first_ink_material: ShaderMaterial = null
var _go_second_ink_material: ShaderMaterial = null
var _choice_feedback_tweens: Dictionary = {}
var _blocked_feedback_tween: Tween = null
var _library_display_owner_ids: Array[int] = []

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
	_roll_library_display_owners()
	_style_header()
	_create_hands()
	library_grid.set_hold_duration(hold_duration)
	_refresh_library_grid()
	library_grid.inspection_requested.connect(_on_library_inspection_requested)
	library_grid.drag_started.connect(_on_library_drag_started)
	library_grid.drag_moved.connect(_on_library_drag_moved)
	library_grid.drag_ended.connect(_on_library_drag_ended)
	back_button.pressed.connect(_on_back_pressed)
	go_first_button.pressed.connect(_on_go_first_pressed)
	go_second_button.pressed.connect(_on_go_second_pressed)
	card_inspector.inspection_closed.connect(_on_inspection_closed)
	resized.connect(_layout_scene)
	get_viewport().size_changed.connect(_layout_scene)
	opponent_name.text = upcoming_enemy_name
	status_label.text = DEFAULT_STATUS
	_style_start_controls()
	_refresh_start_controls()
	_layout_scene.call_deferred()


func debug_exchange(library_index: int, deck_index: int) -> bool:
	var result: Dictionary = _profile_store.exchange_and_save(profile, library_index, deck_index)
	if not bool(result.get("ok", false)):
		return false
	profile = result["profile"]
	_refresh_player_slot(deck_index)
	_refresh_library_grid()
	_refresh_start_controls()
	return true


func debug_get_profile() -> Dictionary:
	return profile.duplicate(true)


func debug_get_library_rect() -> Rect2:
	return _get_library_rect()


func debug_is_inspecting() -> bool:
	return _inspection_open


func debug_get_tier_totals() -> Vector2i:
	return Vector2i(
		_get_tier_total(_get_player_main_deck_ids()),
		_get_tier_total(_effective_enemy_card_ids)
	)


func debug_can_go_first() -> bool:
	return _go_first_allowed


func debug_get_status() -> String:
	return status_label.text


func debug_get_library_display_owner_ids() -> Array[int]:
	return _library_display_owner_ids.duplicate()


func _roll_library_display_owners() -> void:
	var random := RandomNumberGenerator.new()
	if library_color_seed == 0:
		random.randomize()
	else:
		random.seed = library_color_seed
	_library_display_owner_ids.resize(DeckLibraryGrid.TOTAL_SLOTS)
	_library_display_owner_ids.fill(DuelRules.PLAYER_OWNER)
	var library_values: Array = profile.get("library_slots", [])
	for logical_index: int in range(mini(library_values.size(), DeckLibraryGrid.TOTAL_SLOTS)):
		if String(library_values[logical_index]).is_empty():
			continue
		_library_display_owner_ids[logical_index] = (
			DuelRules.PLAYER_OWNER
			if random.randi_range(0, 1) == 0
			else DuelRules.OPPONENT_OWNER
		)


func _refresh_library_grid() -> void:
	library_grid.set_library_slots(profile["library_slots"], _library_display_owner_ids)


func _create_hands() -> void:
	_create_hand_slots(opponent_hand)
	_create_hand_slots(player_hand)
	var enemy_ids: Array[StringName] = upcoming_enemy_card_ids.duplicate()
	if enemy_ids.size() != 5:
		enemy_ids = Decks.get_opponent_card_ids()
	_effective_enemy_card_ids = enemy_ids.duplicate()
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
	_set_start_controls_visible(false)
	status_label.text = "查看卡牌详情 · 轻触返回"
	card_inspector.present(data, _get_library_rect())


func _on_inspection_closed() -> void:
	if not _inspection_open:
		return
	_inspection_open = false
	library_grid.visible = true
	library_grid.set_interaction_enabled(true)
	library_grid.set_scroll_offset(_scroll_before_inspection)
	_set_start_controls_visible(true)
	_refresh_start_controls()
	status_label.text = DEFAULT_STATUS


func _on_library_drag_started(logical_index: int, data: Dictionary, pointer_position: Vector2) -> void:
	if _inspection_open or _drag_proxy != null:
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
			_refresh_library_grid()
			_refresh_start_controls()
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


func _on_go_first_pressed() -> void:
	if not _go_first_allowed:
		status_label.text = GO_FIRST_BLOCKED_NOTICE
		_play_blocked_choice_feedback()
		return
	duel_requested.emit(DuelRules.PLAYER_OWNER)


func _on_go_second_pressed() -> void:
	duel_requested.emit(DuelRules.OPPONENT_OWNER)


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
	var choice_slot_width: float = clampf((canvas_size.x - library_width) * 0.32, 44.0, 54.0)
	var choice_slot_height: float = minf(220.0, library_height * 0.48)
	var choice_width: float = choice_slot_width * CHOICE_SIZE_SCALE
	var choice_height: float = choice_slot_height * CHOICE_SIZE_SCALE
	var choice_gap: float = maxf(6.0, canvas_size.x * 0.014)
	var choice_y: float = library_position.y + (library_height - choice_height) * 0.5
	var go_first_slot_x: float = maxf(
		horizontal_margin,
		library_position.x - choice_gap - choice_slot_width
	)
	go_first_button.position = Vector2(
		go_first_slot_x + (choice_slot_width - choice_width) * 0.5,
		choice_y
	)
	go_first_button.size = Vector2(choice_width, choice_height)
	var go_second_slot_x: float = minf(
		canvas_size.x - horizontal_margin - choice_slot_width,
		library_position.x + library_width + choice_gap
	)
	go_second_button.position = Vector2(
		go_second_slot_x + (choice_slot_width - choice_width) * 0.5,
		choice_y
	)
	go_second_button.size = Vector2(choice_width, choice_height)
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


func _get_player_main_deck_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Variant in profile.get("main_deck", []):
		result.append(StringName(String(value)))
	return result


func _get_tier_total(card_ids: Array[StringName]) -> int:
	var total: int = 0
	for card_id: StringName in card_ids:
		if Catalog.has_card(card_id):
			total += int(Catalog.get_definition(card_id).get("tier", 0))
	return total


func _refresh_start_controls() -> void:
	if not is_node_ready():
		return
	var player_total: int = _get_tier_total(_get_player_main_deck_ids())
	var enemy_total: int = _get_tier_total(_effective_enemy_card_ids)
	_go_first_allowed = player_total <= enemy_total
	if _go_first_ink_material != null:
		_go_first_ink_material.set_shader_parameter(
			"ink_color",
			ACTIVE_INK_COLOR if _go_first_allowed else BLOCKED_INK_COLOR
		)
	if _go_second_ink_material != null:
		_go_second_ink_material.set_shader_parameter("ink_color", ACTIVE_INK_COLOR)
	go_first_button.modulate = Color.WHITE
	go_second_button.modulate = Color.WHITE
	go_first_button.tooltip_text = ""


func _set_start_controls_visible(controls_visible: bool) -> void:
	go_first_button.visible = controls_visible
	go_second_button.visible = controls_visible


func _style_start_controls() -> void:
	var empty_style := StyleBoxEmpty.new()
	for button: Button in [go_first_button, go_second_button]:
		button.focus_mode = Control.FOCUS_NONE
		button.button_down.connect(_on_start_button_down.bind(button))
		button.button_up.connect(_on_start_button_up.bind(button))
		for style_name: StringName in [
			&"normal",
			&"hover",
			&"pressed",
			&"hover_pressed",
			&"disabled",
			&"focus",
		]:
			button.add_theme_stylebox_override(style_name, empty_style)
	var ink_shader := Shader.new()
	ink_shader.code = """
shader_type canvas_item;

uniform vec4 ink_color : source_color = vec4(0.10, 0.08, 0.07, 1.0);

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	COLOR = vec4(ink_color.rgb, source.a * ink_color.a);
}
"""
	_go_first_ink_material = _create_choice_ink_material(ink_shader)
	for child: Node in go_first_button.get_node("Characters").get_children():
		if child is TextureRect:
			(child as TextureRect).material = _go_first_ink_material
	_go_second_ink_material = _create_choice_ink_material(ink_shader)
	for child: Node in go_second_button.get_node("Characters").get_children():
		if child is TextureRect:
			(child as TextureRect).material = _go_second_ink_material


func _create_choice_ink_material(shader: Shader) -> ShaderMaterial:
	var ink_material := ShaderMaterial.new()
	ink_material.shader = shader
	ink_material.set_shader_parameter("ink_color", ACTIVE_INK_COLOR)
	return ink_material


func _on_start_button_down(button: Button) -> void:
	_kill_choice_feedback_tween(button)
	button.pivot_offset = button.size * 0.5
	button.scale = PRESSED_CHOICE_SCALE
	_set_choice_pressed_ink(button, true)


func _on_start_button_up(button: Button) -> void:
	_kill_choice_feedback_tween(button)
	_set_choice_pressed_ink(button, false)
	var tween: Tween = button.create_tween()
	_choice_feedback_tweens[button.get_instance_id()] = tween
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE, 0.10)


func _set_choice_pressed_ink(button: Button, pressed: bool) -> void:
	var ink_material: ShaderMaterial = (
		_go_first_ink_material
		if button == go_first_button
		else _go_second_ink_material
	)
	if ink_material == null:
		return
	var resting_color: Color = ACTIVE_INK_COLOR
	if button == go_first_button and not _go_first_allowed:
		resting_color = BLOCKED_INK_COLOR
	ink_material.set_shader_parameter(
		"ink_color",
		PRESSED_INK_COLOR if pressed else resting_color
	)


func _kill_choice_feedback_tween(button: Button) -> void:
	var instance_id: int = button.get_instance_id()
	var existing: Variant = _choice_feedback_tweens.get(instance_id, null)
	if existing is Tween and (existing as Tween).is_valid():
		(existing as Tween).kill()
	_choice_feedback_tweens.erase(instance_id)


func _play_blocked_choice_feedback() -> void:
	if _blocked_feedback_tween != null and _blocked_feedback_tween.is_valid():
		_blocked_feedback_tween.kill()
	var resting_position: Vector2 = go_first_button.position
	_blocked_feedback_tween = go_first_button.create_tween()
	_blocked_feedback_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_blocked_feedback_tween.tween_property(go_first_button, "position:x", resting_position.x - 4.0, 0.035)
	_blocked_feedback_tween.tween_property(go_first_button, "position:x", resting_position.x + 4.0, 0.055)
	_blocked_feedback_tween.tween_property(go_first_button, "position:x", resting_position.x, 0.035)


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
