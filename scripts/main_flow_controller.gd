class_name MainFlowController
extends Control

const DECK_BUILDER_SCENE: PackedScene = preload("res://scenes/deck_builder.tscn")
const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Settings = preload("res://scripts/game_settings.gd")
const Store = preload("res://scripts/deck_profile_store.gd")

@export var deck_profile_path: String = Store.DEFAULT_SAVE_PATH
@export var upcoming_enemy_name: String = "对手名字"
@export var upcoming_enemy_card_ids: Array[StringName] = []

var testing_mode: bool = Settings.TESTING_MODE
var _current_screen: Control = null


func _ready() -> void:
	_show_deck_builder()


func debug_get_current_screen() -> Control:
	return _current_screen


func _show_deck_builder() -> void:
	var builder := DECK_BUILDER_SCENE.instantiate() as DeckBuilderController
	builder.profile_path = deck_profile_path
	builder.upcoming_enemy_name = upcoming_enemy_name
	builder.upcoming_enemy_card_ids = upcoming_enemy_card_ids.duplicate()
	builder.testing_mode = testing_mode
	builder.duel_requested.connect(_on_duel_requested)
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


func _on_duel_return_requested() -> void:
	_show_deck_builder()
