class_name SectSelectionController
extends Control

signal back_requested
signal deck_builder_requested

const CARD_SCENE: PackedScene = preload("res://scenes/card_view.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const Sects = preload("res://scripts/sect_catalog.gd")
const Store = preload("res://scripts/deck_profile_store.gd")
const SelectionShell = preload("res://scripts/deck_selection_shell.gd")
const CardInspectorData = preload("res://scripts/card_inspector.gd")

const DEFAULT_STATUS: String = "轻触门派查看详情，长按门派并拖至下方"
const LOCKED_STATUS: String = "该门派尚未解锁"
const DIFFICULTY_ENEMY_PREFIX: String = "江湖门派·进阶"
const DIFFICULTY_STATUS_SUFFIX: String = "：进阶特效文本占位"
const DIFFICULTY_NUMERALS: Array[String] = [
	"零",
	"一",
	"二",
	"三",
	"四",
	"五",
	"六",
	"七",
	"八",
	"九",
]
const DIFFICULTY_BUTTON_SIZE: Vector2 = Vector2(21.0, 34.0)
const DIFFICULTY_BUTTON_CENTER_GAP: float = 21.0
const DIFFICULTY_BUTTON_PRESSED_SCALE: Vector2 = Vector2(0.92, 0.92)
const DIFFICULTY_BUTTON_PRESSED_ALPHA: float = 0.62
const DIFFICULTY_BUTTON_RELEASE_DURATION: float = 0.14

@export var profile_path: String = Store.DEFAULT_SAVE_PATH
@export var upcoming_enemy_name: String = "江湖门派"
@export var testing_mode: bool = false
@export var hold_duration: float = 0.25
@export var library_aspect_ratio: float = 0.78

var profile: Dictionary = {}
var _profile_store: RefCounted
var _selected_sect_id: StringName = &""
var _max_unlocked_difficulty: int = 0
var _selected_difficulty: int = 0
var _upper_preview_ids: Array[StringName] = []
var _lower_preview_ids: Array[StringName] = []
var _inspection_open: bool = false
var _scroll_before_inspection: float = 0.0
var _drag_source_index: int = -1
var _drag_proxy: CardView = null
var _drag_proxy_offset: Vector2 = Vector2.ZERO
var _difficulty_feedback_tweens: Dictionary = {}

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
@onready var difficulty_left_button: TextureButton = $DuelCanvas/DifficultyLeftButton
@onready var difficulty_right_button: TextureButton = $DuelCanvas/DifficultyRightButton
@onready var go_first_button: Button = $DuelCanvas/GoFirstButton
@onready var go_second_button: Button = $DuelCanvas/GoSecondButton
@onready var player_hand: HBoxContainer = $DuelCanvas/PlayerHand
@onready var status_label: Label = $DuelCanvas/Status
@onready var drag_layer: Control = $DuelCanvas/DragLayer
@onready var card_inspector: CardInspectorData = $DuelCanvas/CardInspector


func _ready() -> void:
	var card_errors: Array[String] = Catalog.validate_catalog()
	assert(card_errors.is_empty(), "Invalid card catalog: %s" % str(card_errors))
	var sect_errors: Array[String] = Sects.validate_catalog()
	assert(sect_errors.is_empty(), "Invalid sect catalog: %s" % str(sect_errors))
	_profile_store = Store.new(profile_path)
	profile = _profile_store.load_profile()
	_max_unlocked_difficulty = _profile_store.get_max_unlocked_difficulty(profile)
	_selected_difficulty = _profile_store.get_last_selected_difficulty(profile)
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
	SelectionShell.create_hand_slots(opponent_hand)
	SelectionShell.create_hand_slots(player_hand)
	_refresh_preview_hand(
		opponent_hand,
		_upper_preview_ids,
		DuelRules.OPPONENT_OWNER,
		"sect_preview_upper"
	)
	_refresh_preview_hand(
		player_hand,
		_lower_preview_ids,
		DuelRules.PLAYER_OWNER,
		"sect_preview_lower"
	)
	go_first_button.visible = false
	go_first_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	go_second_button.visible = false
	go_second_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	library_grid.set_hold_duration(hold_duration)
	_refresh_sect_grid()
	library_grid.inspection_requested.connect(_on_library_inspection_requested)
	library_grid.hold_recognized.connect(_on_library_hold_recognized)
	library_grid.drag_started.connect(_on_library_drag_started)
	library_grid.drag_moved.connect(_on_library_drag_moved)
	library_grid.drag_ended.connect(_on_library_drag_ended)
	back_button.pressed.connect(_on_back_pressed)
	difficulty_left_button.pressed.connect(_on_difficulty_left_pressed)
	difficulty_right_button.pressed.connect(_on_difficulty_right_pressed)
	for button: TextureButton in [difficulty_left_button, difficulty_right_button]:
		button.button_down.connect(_on_difficulty_button_down.bind(button))
		button.button_up.connect(_on_difficulty_button_up.bind(button))
	card_inspector.inspection_closed.connect(_on_inspection_closed)
	resized.connect(_layout_scene)
	get_viewport().size_changed.connect(_layout_scene)
	enemy_seal_label.text = "友"
	_refresh_difficulty_ui()
	_layout_scene.call_deferred()


func debug_select_sect(sect_id: StringName, inspect: bool = false) -> bool:
	if not Sects.has_sect(sect_id):
		return false
	var data: Dictionary = Sects.get_definition(sect_id)
	_select_sect(data)
	if inspect:
		_open_inspector(_build_sect_inspector_data(data))
	return true


func debug_confirm_selected_sect() -> bool:
	return _complete_selected_sect()


func debug_get_selected_sect_id() -> StringName:
	return _selected_sect_id


func debug_get_selected_difficulty() -> int:
	return _selected_difficulty


func debug_get_max_unlocked_difficulty() -> int:
	return _max_unlocked_difficulty


func debug_get_upper_preview_ids() -> Array[StringName]:
	return _upper_preview_ids.duplicate()


func debug_get_lower_preview_ids() -> Array[StringName]:
	return _lower_preview_ids.duplicate()


func debug_is_inspecting() -> bool:
	return _inspection_open


func debug_get_status() -> String:
	return status_label.text


func _difficulty_default_status() -> String:
	if _selected_difficulty <= 0:
		return DEFAULT_STATUS
	return "进阶%s%s" % [
		DIFFICULTY_NUMERALS[_selected_difficulty],
		DIFFICULTY_STATUS_SUFFIX,
	]


func _refresh_difficulty_ui() -> void:
	_selected_difficulty = clampi(
		_selected_difficulty,
		0,
		_max_unlocked_difficulty
	)
	if _selected_difficulty == 0:
		opponent_name.text = upcoming_enemy_name
	else:
		opponent_name.text = "%s%s" % [
			DIFFICULTY_ENEMY_PREFIX,
			DIFFICULTY_NUMERALS[_selected_difficulty],
		]
	status_label.text = _difficulty_default_status()
	_update_difficulty_button_interaction()


func _update_difficulty_button_interaction() -> void:
	var has_multiple_difficulties: bool = _max_unlocked_difficulty > 0
	difficulty_left_button.visible = has_multiple_difficulties
	difficulty_right_button.visible = has_multiple_difficulties
	var disabled: bool = (
		not has_multiple_difficulties
		or _inspection_open
		or _drag_proxy != null
	)
	difficulty_left_button.disabled = disabled
	difficulty_right_button.disabled = disabled
	if disabled:
		_reset_difficulty_button_feedback(difficulty_left_button)
		_reset_difficulty_button_feedback(difficulty_right_button)


func _on_difficulty_left_pressed() -> void:
	_cycle_difficulty(-1)


func _on_difficulty_right_pressed() -> void:
	_cycle_difficulty(1)


func _on_difficulty_button_down(button: TextureButton) -> void:
	if button.disabled:
		return
	_kill_difficulty_feedback_tween(button)
	button.pivot_offset = button.size * 0.5
	button.scale = DIFFICULTY_BUTTON_PRESSED_SCALE
	button.modulate.a = DIFFICULTY_BUTTON_PRESSED_ALPHA


func _on_difficulty_button_up(button: TextureButton) -> void:
	_kill_difficulty_feedback_tween(button)
	var tween: Tween = button.create_tween()
	_difficulty_feedback_tweens[button.get_instance_id()] = tween
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		button,
		"scale",
		Vector2.ONE,
		DIFFICULTY_BUTTON_RELEASE_DURATION
	)
	tween.parallel().tween_property(
		button,
		"modulate:a",
		1.0,
		DIFFICULTY_BUTTON_RELEASE_DURATION
	)


func _reset_difficulty_button_feedback(button: TextureButton) -> void:
	_kill_difficulty_feedback_tween(button)
	button.scale = Vector2.ONE
	button.modulate.a = 1.0


func _kill_difficulty_feedback_tween(button: TextureButton) -> void:
	var tween_id: int = button.get_instance_id()
	var tween: Tween = _difficulty_feedback_tweens.get(tween_id) as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	_difficulty_feedback_tweens.erase(tween_id)


func _cycle_difficulty(delta: int) -> void:
	if (
		_max_unlocked_difficulty <= 0
		or _inspection_open
		or _drag_proxy != null
	):
		return
	var difficulty_count: int = _max_unlocked_difficulty + 1
	var next_difficulty: int = posmod(
		_selected_difficulty + delta,
		difficulty_count
	)
	var result: Dictionary = _profile_store.set_last_selected_difficulty_and_save(
		profile,
		next_difficulty
	)
	if not bool(result.get("ok", false)):
		status_label.text = "保存失败"
		return
	profile = result.get("profile", profile)
	_selected_difficulty = next_difficulty
	_refresh_difficulty_ui()


func _refresh_sect_grid() -> void:
	var entries: Array = []
	var display_owner_ids: Array = []
	var drag_enabled_values: Array = []
	var unlocked_sect_ids: Array[StringName] = _profile_store.get_unlocked_sect_ids(profile)
	for sect_id: StringName in Sects.get_all_sect_ids():
		var unlocked: bool = sect_id in unlocked_sect_ids
		entries.append(Sects.get_definition(sect_id))
		display_owner_ids.append(
			DuelRules.PLAYER_OWNER if unlocked else DuelRules.OPPONENT_OWNER
		)
		drag_enabled_values.append(unlocked)
	library_grid.set_display_entries(
		entries,
		display_owner_ids,
		drag_enabled_values,
		false
	)


func _select_sect(data: Dictionary) -> void:
	var sect_id := StringName(String(data.get("id", "")))
	if not Sects.has_sect(sect_id):
		return
	_selected_sect_id = sect_id
	_upper_preview_ids = _get_preview_ids(sect_id, false)
	_lower_preview_ids = _get_preview_ids(sect_id, true)
	_refresh_preview_hand(
		opponent_hand,
		_upper_preview_ids,
		DuelRules.OPPONENT_OWNER,
		"sect_preview_upper"
	)
	_refresh_preview_hand(
		player_hand,
		_lower_preview_ids,
		DuelRules.PLAYER_OWNER,
		"sect_preview_lower"
	)


func _get_preview_ids(sect_id: StringName, ascending: bool) -> Array[StringName]:
	var result: Array[StringName] = []
	if not Sects.has_sect(sect_id):
		return result
	var sect_glyph: String = String(Sects.get_definition(sect_id).get("glyph", ""))
	var ranked: Array[Dictionary] = []
	var catalog_ids: Array[StringName] = Catalog.get_all_card_ids()
	for catalog_index: int in range(catalog_ids.size()):
		var card_id: StringName = catalog_ids[catalog_index]
		var definition: Dictionary = Catalog.get_definition(card_id)
		if String(definition.get("sect", "")) != sect_glyph:
			continue
		ranked.append({
			"id": card_id,
			"tier": int(definition.get("tier", 0)),
			"catalog_index": catalog_index,
		})
	ranked.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_tier: int = int(left["tier"])
		var right_tier: int = int(right["tier"])
		if left_tier == right_tier:
			return int(left["catalog_index"]) < int(right["catalog_index"])
		return left_tier < right_tier if ascending else left_tier > right_tier
	)
	for index: int in range(mini(5, ranked.size())):
		result.append(StringName(String(ranked[index]["id"])))
	return result


func _get_tier_one_ids(sect_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	if not Sects.has_sect(sect_id):
		return result
	var sect_glyph: String = String(Sects.get_definition(sect_id).get("glyph", ""))
	for card_id: StringName in Catalog.get_all_card_ids():
		var definition: Dictionary = Catalog.get_definition(card_id)
		if (
			String(definition.get("sect", "")) == sect_glyph
			and int(definition.get("tier", 0)) == 1
		):
			result.append(card_id)
	return result


func _refresh_preview_hand(
	container: HBoxContainer,
	card_ids: Array[StringName],
	owner_id: int,
	instance_prefix: String
) -> void:
	for slot_index: int in range(container.get_child_count()):
		var slot := container.get_child(slot_index) as PanelContainer
		for child: Node in slot.get_children():
			slot.remove_child(child)
			child.queue_free()
		if slot_index >= card_ids.size():
			_spawn_preview_card_back(slot, owner_id)
			continue
		var card_data: Dictionary = Catalog.create_instance(
			card_ids[slot_index],
			owner_id,
			StringName("%s_%d" % [instance_prefix, slot_index])
		)
		var card: CardView = _spawn_preview_card(slot, card_data, owner_id)
		card.set_face_down(false)


func _spawn_preview_card(
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


func _spawn_preview_card_back(
	slot: PanelContainer,
	owner_id: int
) -> CardView:
	var card := CARD_SCENE.instantiate() as CardView
	slot.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.configure({}, owner_id, false)
	card.set_face_down(true)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card


func _on_library_inspection_requested(_logical_index: int, data: Dictionary) -> void:
	_select_sect(data)
	_open_inspector(_build_sect_inspector_data(data))


func _on_library_hold_recognized(logical_index: int, data: Dictionary) -> void:
	_select_sect(data)
	var sect_id := StringName(String(data.get("id", "")))
	if sect_id not in _profile_store.get_unlocked_sect_ids(profile):
		status_label.text = LOCKED_STATUS
		library_grid.play_rejected_drag_pulse(logical_index)
	else:
		status_label.text = _difficulty_default_status()


func _on_card_inspection_requested(data: Dictionary) -> void:
	_open_inspector(data)


func _build_sect_inspector_data(data: Dictionary) -> Dictionary:
	var result: Dictionary = data.duplicate(true)
	var sect_id := StringName(String(result.get("id", "")))
	var best_score: int = _profile_store.get_best_score(
		profile,
		sect_id,
		_selected_difficulty
	)
	if _selected_difficulty <= 0:
		result["sect"] = "最高分：%d" % best_score
	else:
		result["sect"] = "进阶%s：%d" % [
			DIFFICULTY_NUMERALS[_selected_difficulty],
			best_score,
		]
	return result


func _open_inspector(data: Dictionary) -> void:
	if _inspection_open or data.is_empty():
		return
	_inspection_open = true
	_update_difficulty_button_interaction()
	_scroll_before_inspection = library_grid.get_scroll_offset()
	library_grid.set_interaction_enabled(false)
	library_grid.visible = false
	status_label.text = "查看详情 · 轻触返回"
	card_inspector.present(data, _get_library_rect())


func _on_inspection_closed() -> void:
	if not _inspection_open:
		return
	_inspection_open = false
	library_grid.visible = true
	library_grid.set_interaction_enabled(true)
	library_grid.set_scroll_offset(_scroll_before_inspection)
	status_label.text = _difficulty_default_status()
	_update_difficulty_button_interaction()


func _on_library_drag_started(
	logical_index: int,
	data: Dictionary,
	pointer_position: Vector2
) -> void:
	if _inspection_open or _drag_proxy != null:
		return
	var sect_id := StringName(String(data.get("id", "")))
	if sect_id not in _profile_store.get_unlocked_sect_ids(profile):
		status_label.text = LOCKED_STATUS
		return
	_drag_source_index = logical_index
	_drag_proxy = CARD_SCENE.instantiate() as CardView
	drag_layer.add_child(_drag_proxy)
	_drag_proxy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_proxy.set_ki_badge_enabled(false)
	_drag_proxy.set_power_numbers_enabled(false)
	_drag_proxy.configure(data, DuelRules.PLAYER_OWNER, false)
	_update_difficulty_button_interaction()
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
		_complete_selected_sect()
	_clear_drag_proxy()


func _complete_selected_sect() -> bool:
	if (
		not Sects.has_sect(_selected_sect_id)
		or _selected_sect_id not in _profile_store.get_unlocked_sect_ids(profile)
	):
		status_label.text = LOCKED_STATUS
		return false
	var result: Dictionary = _profile_store.begin_run_and_save(
		profile,
		_selected_sect_id,
		_get_tier_one_ids(_selected_sect_id),
		&"",
		null,
		testing_mode,
		_selected_difficulty
	)
	if not bool(result.get("ok", false)):
		status_label.text = "保存失败"
		return false
	profile = result.get("profile", profile)
	status_label.text = _difficulty_default_status()
	deck_builder_requested.emit()
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
	_update_difficulty_button_interaction()


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
	_layout_difficulty_buttons()
	if _inspection_open:
		card_inspector.set_board_rect(_get_library_rect())


func _layout_difficulty_buttons() -> void:
	var library_rect := Rect2(library_grid.position, library_grid.size)
	var left_center := Vector2(
		library_rect.position.x - DIFFICULTY_BUTTON_CENTER_GAP,
		library_rect.get_center().y
	)
	var right_center := Vector2(
		library_rect.end.x + DIFFICULTY_BUTTON_CENTER_GAP,
		library_rect.get_center().y
	)
	difficulty_left_button.size = DIFFICULTY_BUTTON_SIZE
	difficulty_right_button.size = DIFFICULTY_BUTTON_SIZE
	difficulty_left_button.position = left_center - DIFFICULTY_BUTTON_SIZE * 0.5
	difficulty_right_button.position = right_center - DIFFICULTY_BUTTON_SIZE * 0.5
	difficulty_left_button.pivot_offset = DIFFICULTY_BUTTON_SIZE * 0.5
	difficulty_right_button.pivot_offset = DIFFICULTY_BUTTON_SIZE * 0.5


func _get_library_rect() -> Rect2:
	return Rect2(
		library_grid.global_position - duel_canvas.global_position,
		library_grid.size
	)
