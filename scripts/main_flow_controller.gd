class_name MainFlowController
extends Control

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/main_menu.tscn")
const SECT_SELECTION_SCENE: PackedScene = preload("res://scenes/sect_selection.tscn")
const DECK_BUILDER_SCENE: PackedScene = preload("res://scenes/deck_builder.tscn")
const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const MenuController = preload("res://scripts/main_menu_controller.gd")
const SelectorController = preload("res://scripts/sect_selection_controller.gd")
const Settings = preload("res://scripts/game_settings.gd")
const Store = preload("res://scripts/deck_profile_store.gd")

@export var deck_profile_path: String = Store.DEFAULT_SAVE_PATH
@export var upcoming_enemy_name: String = "对手名字"
@export var upcoming_enemy_card_ids: Array[StringName] = []

var testing_mode: bool = Settings.TESTING_MODE
var _current_screen: Control = null


func _ready() -> void:
	_show_main_menu()


func debug_get_current_screen() -> Control:
	return _current_screen


func _show_main_menu(notice: String = "") -> void:
	var menu := MAIN_MENU_SCENE.instantiate() as MenuController
	menu.journey_requested.connect(_on_journey_requested)
	menu.run_reset_confirmed.connect(_on_run_reset_confirmed)
	menu.progress_reset_confirmed.connect(_on_progress_reset_confirmed)
	_replace_screen(menu)
	if not notice.is_empty():
		menu.show_notice(notice)


func _show_sect_selection() -> void:
	var selector := SECT_SELECTION_SCENE.instantiate() as SelectorController
	selector.profile_path = deck_profile_path
	selector.upcoming_enemy_name = upcoming_enemy_name
	selector.deck_builder_requested.connect(_on_deck_builder_requested)
	selector.back_requested.connect(_on_return_to_menu_requested)
	_replace_screen(selector)


func _show_deck_builder() -> void:
	var builder := DECK_BUILDER_SCENE.instantiate() as DeckBuilderController
	builder.profile_path = deck_profile_path
	builder.upcoming_enemy_name = upcoming_enemy_name
	builder.upcoming_enemy_card_ids = upcoming_enemy_card_ids.duplicate()
	builder.testing_mode = testing_mode
	builder.duel_requested.connect(_on_duel_requested)
	builder.back_requested.connect(_on_return_to_menu_requested)
	_replace_screen(builder)


func _show_duel(starting_owner_id: int) -> void:
	var duel := DUEL_SCENE.instantiate() as DuelController
	duel.deck_profile_path = deck_profile_path
	duel.starting_owner_id = starting_owner_id
	duel.opponent_name_text = upcoming_enemy_name
	duel.opponent_card_ids = upcoming_enemy_card_ids.duplicate()
	duel.testing_mode = testing_mode
	duel.return_requested.connect(_on_duel_return_requested)
	_replace_screen(duel)


func _replace_screen(next_screen: Control) -> void:
	if _current_screen != null and is_instance_valid(_current_screen):
		remove_child(_current_screen)
		_current_screen.queue_free()
	_current_screen = next_screen
	add_child(_current_screen)
	_current_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _on_duel_requested(starting_owner_id: int) -> void:
	_show_duel(starting_owner_id)


func _on_journey_requested() -> void:
	var store := Store.new(deck_profile_path)
	var profile: Dictionary = store.load_profile()
	if store.is_run_active(profile):
		_show_deck_builder()
	else:
		_show_sect_selection()


func _on_run_reset_confirmed() -> void:
	var store := Store.new(deck_profile_path)
	var profile: Dictionary = store.load_profile()
	var result: Dictionary = store.reset_run_and_save(profile)
	_show_main_menu(
		"本次江湖历程已重置"
		if bool(result.get("ok", false))
		else "保存失败，请重试"
	)


func _on_progress_reset_confirmed() -> void:
	var store := Store.new(deck_profile_path)
	var profile: Dictionary = store.load_profile()
	var result: Dictionary = store.reset_all_progress_and_save(profile)
	_show_main_menu(
		"所有进度已清除"
		if bool(result.get("ok", false))
		else "保存失败，请重试"
	)


func _on_deck_builder_requested() -> void:
	_show_deck_builder()


func _on_duel_return_requested() -> void:
	_show_deck_builder()


func _on_return_to_menu_requested() -> void:
	_show_main_menu()
