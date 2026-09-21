class_name RewardSelectionController
extends Control

signal back_requested
signal reward_claimed(card_id: StringName)

const CARD_SCENE: PackedScene = preload("res://scenes/card_view.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const Difficulty = preload("res://scripts/difficulty_rules.gd")
const Settings = preload("res://scripts/game_settings.gd")
const Store = preload("res://scripts/deck_profile_store.gd")
const Sects = preload("res://scripts/sect_catalog.gd")
const SelectionShell = preload("res://scripts/deck_selection_shell.gd")
const CardInspectorData = preload("res://scripts/card_inspector.gd")

const DEFAULT_STATUS: String = "选择一张奖励牌，长按可直接领取"
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
	"十",
]

@export var profile_path: String = Store.DEFAULT_SAVE_PATH
@export var upcoming_enemy_name: String = "对手名字"
@export var upcoming_enemy_card_ids: Array[StringName] = []
@export var remembered_enemy_glyphs: Array[String] = []
@export var hold_duration: float = 0.25
@export var library_aspect_ratio: float = 0.78
@export var reward_color_seed: int = 0

var testing_mode: bool = Settings.default_testing_mode()
var profile: Dictionary = {}
var _profile_store: RefCounted
var _reward_ids: Array[StringName] = []
var _reward_display_owner_ids: Array[int] = []
var _inspection_open: bool = false
var _inspected_reward_index: int = -1

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
@onready var card_inspector: CardInspectorData = $DuelCanvas/CardInspector
@onready var detail_actions = $DuelCanvas/SelectionDetailActions


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
	library_grid.set_ki_badges_enabled(true)
	_roll_reward_display_owners()
	_refresh_reward_grid()
	library_grid.inspection_requested.connect(_on_library_inspection_requested)
	library_grid.hold_recognized.connect(_on_library_hold_recognized)
	back_button.pressed.connect(_on_back_pressed)
	card_inspector.inspection_closed.connect(_on_inspection_closed)
	detail_actions.bottom_action_pressed.connect(_on_detail_action_pressed)
	resized.connect(_layout_scene)
	get_viewport().size_changed.connect(_layout_scene)
	enemy_seal_label.text = "友"
	opponent_name.text = "随机门派池"
	status_label.text = _get_default_status()
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
	var sect_pool_ids: Array[StringName] = _profile_store.get_run_sect_pool_ids(profile)
	for card_index: int in range(5):
		var sect_slot := opponent_hand.get_child(card_index) as PanelContainer
		if card_index >= sect_pool_ids.size() or not Sects.has_sect(sect_pool_ids[card_index]):
			_spawn_card_back_in_slot(sect_slot, DuelRules.OPPONENT_OWNER)
			continue
		var sect_data: Dictionary = Sects.get_definition(sect_pool_ids[card_index])
		var sect_card: CardView = _spawn_card_in_slot(
			sect_slot,
			sect_data,
			DuelRules.OPPONENT_OWNER
		)
		sect_card.set_face_down(false)
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
	card.set_concealed_power_numbers_enabled(
		not Difficulty.hides_unrevealed_card_powers(
			_profile_store.get_run_difficulty(profile)
		)
	)
	card.inspection_requested.connect(_on_card_inspection_requested)
	return card


func _spawn_card_back_in_slot(slot: PanelContainer, owner_id: int) -> void:
	var card := CARD_SCENE.instantiate() as CardView
	slot.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.configure({}, owner_id, false)
	card.set_face_down(true)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _refresh_reward_grid() -> void:
	var entries: Array = []
	var drag_enabled: Array = []
	for reward_index: int in range(3):
		if reward_index < _reward_ids.size():
			entries.append(String(_reward_ids[reward_index]))
			drag_enabled.append(false)
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
	var mastered_set: Dictionary = {}
	for card_id: StringName in _profile_store.get_mastered_card_ids(profile):
		mastered_set[card_id] = true
	_reward_display_owner_ids.clear()
	for reward_index: int in range(3):
		if reward_index < _reward_ids.size():
			_reward_display_owner_ids.append(
				DuelRules.PLAYER_OWNER
				if mastered_set.has(_reward_ids[reward_index])
				else DuelRules.OPPONENT_OWNER
			)
			continue
		_reward_display_owner_ids.append(
			DuelRules.PLAYER_OWNER
			if random.randi_range(0, 1) == 0
			else DuelRules.OPPONENT_OWNER
		)


func _on_library_inspection_requested(
	logical_index: int,
	data: Dictionary
) -> void:
	if logical_index < 0 or logical_index >= _reward_ids.size():
		return
	_open_card_inspector(data, logical_index)


func _on_card_inspection_requested(data: Dictionary) -> void:
	_open_card_inspector(data, -1)


func _open_card_inspector(data: Dictionary, reward_index: int) -> void:
	if _inspection_open or data.is_empty() or bool(data.get("_display_placeholder", false)):
		return
	var inspected_data: Dictionary = data
	var inspected_id := StringName(String(data.get("id", "")))
	if Sects.has_sect(inspected_id):
		inspected_data = _build_sect_inspector_data(data)
	_inspection_open = true
	_inspected_reward_index = reward_index
	library_grid.set_interaction_enabled(false)
	library_grid.visible = false
	if reward_index >= 0:
		player_hand.visible = false
		detail_actions.configure_bottom_action("领取奖励")
		status_label.text = "查看详情 · 轻触返回"
	else:
		player_hand.visible = true
		detail_actions.hide_bottom_action()
		status_label.text = "查看详情 · 轻触返回"
	card_inspector.set_close_exclusion_controls(detail_actions.get_exclusion_controls())
	card_inspector.present(inspected_data, _get_library_rect())


func _build_sect_inspector_data(data: Dictionary) -> Dictionary:
	var result: Dictionary = data.duplicate(true)
	var sect_id := StringName(String(result.get("id", "")))
	var difficulty: int = _profile_store.get_run_difficulty(profile)
	var best_score: int = _profile_store.get_best_score(profile, sect_id, difficulty)
	if difficulty <= 0:
		result["sect"] = "最高分：%d" % best_score
	else:
		result["sect"] = "进阶%s：%d" % [
			DIFFICULTY_NUMERALS[difficulty],
			best_score,
		]
	return result


func _on_inspection_closed() -> void:
	if not _inspection_open:
		return
	_inspection_open = false
	_inspected_reward_index = -1
	card_inspector.set_close_exclusion_controls([])
	detail_actions.hide_all()
	player_hand.visible = true
	library_grid.visible = true
	library_grid.set_interaction_enabled(true)
	status_label.text = _get_default_status()


func _get_default_status() -> String:
	return DEFAULT_STATUS


func _on_library_hold_recognized(logical_index: int, _data: Dictionary) -> void:
	if _inspection_open or logical_index < 0 or logical_index >= _reward_ids.size():
		return
	_claim_reward(logical_index)


func _on_detail_action_pressed() -> void:
	if _inspected_reward_index >= 0:
		_claim_reward(_inspected_reward_index)


func _claim_reward(reward_index: int) -> bool:
	if reward_index < 0 or reward_index >= _reward_ids.size():
		return false
	var claimed_card_id: StringName = _reward_ids[reward_index]
	var result: Dictionary = _profile_store.claim_pending_reward_and_save(
		profile,
		claimed_card_id
	)
	if not bool(result.get("ok", false)):
		status_label.text = "保存失败，请重试"
		return false
	profile = result.get("profile", profile)
	_reward_ids.clear()
	reward_claimed.emit(claimed_card_id)
	return true


func _on_back_pressed() -> void:
	back_requested.emit()


func _layout_scene() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	var layout: Dictionary = SelectionShell.apply_core_layout(
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
	detail_actions.apply_layout(
		layout["opponent_hand_rect"],
		layout["player_hand_rect"]
	)
	if _inspection_open:
		card_inspector.set_board_rect(_get_library_rect())


func _get_library_rect() -> Rect2:
	return Rect2(
		library_grid.global_position - duel_canvas.global_position,
		library_grid.size
	)
