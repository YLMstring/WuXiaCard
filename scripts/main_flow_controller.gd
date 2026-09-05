class_name MainFlowController
extends Control

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/main_menu.tscn")
const SECT_SELECTION_SCENE: PackedScene = preload("res://scenes/sect_selection.tscn")
const DECK_BUILDER_SCENE: PackedScene = preload("res://scenes/deck_builder.tscn")
const REWARD_SELECTION_SCENE: PackedScene = preload("res://scenes/reward_selection.tscn")
const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const ENDING_SCENE: PackedScene = preload("res://scenes/ending.tscn")
const Music = preload("res://scripts/music_director.gd")
const MenuController = preload("res://scripts/main_menu_controller.gd")
const SelectorController = preload("res://scripts/sect_selection_controller.gd")
const RewardController = preload("res://scripts/reward_selection_controller.gd")
const Settings = preload("res://scripts/game_settings.gd")
const Store = preload("res://scripts/deck_profile_store.gd")
const Enemies = preload("res://scripts/enemy_catalog.gd")

@export var deck_profile_path: String = Store.DEFAULT_SAVE_PATH
@export var upcoming_enemy_name: String = ""
@export var upcoming_enemy_card_ids: Array[StringName] = []
@export_range(1, Store.MAX_CHARACTER_LEVEL) var victories_required: int = (
	Store.DEFAULT_VICTORIES_REQUIRED
)

var testing_mode: bool = Settings.TESTING_MODE
var _current_screen: Control = null
var _normal_deck_profile_path: String = ""
var _music_director: Node = null
var _play_lose_on_next_deck_builder: bool = false


func _ready() -> void:
	_music_director = Music.new() as Node
	add_child(_music_director)
	if testing_mode:
		_prepare_testing_profile()
	_show_main_menu()


func _exit_tree() -> void:
	if not testing_mode or _normal_deck_profile_path.is_empty():
		return
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = deck_profile_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func debug_get_current_screen() -> Control:
	return _current_screen


func debug_get_music_director() -> Node:
	return _music_director


func _show_main_menu(notice: String = "") -> void:
	var menu := MAIN_MENU_SCENE.instantiate() as MenuController
	menu.journey_requested.connect(_on_journey_requested)
	menu.run_reset_confirmed.connect(_on_run_reset_confirmed)
	menu.progress_reset_confirmed.connect(_on_progress_reset_confirmed)
	menu.progression_unlock_requested.connect(_on_progression_unlock_requested)
	_replace_screen(menu)
	_music_director.request_context(Music.CONTEXT_MENU)
	if not notice.is_empty():
		menu.show_notice(notice)


func _show_sect_selection() -> void:
	var selector := SECT_SELECTION_SCENE.instantiate() as SelectorController
	var enemy: Dictionary = _get_upcoming_enemy()
	selector.profile_path = deck_profile_path
	selector.testing_mode = testing_mode
	selector.upcoming_enemy_name = String(enemy["name"])
	selector.deck_builder_requested.connect(_on_deck_builder_requested)
	selector.back_requested.connect(_on_return_to_menu_requested)
	_replace_screen(selector)
	_music_director.request_context(Music.CONTEXT_MENU)


func _show_deck_builder() -> void:
	var builder := DECK_BUILDER_SCENE.instantiate() as DeckBuilderController
	var enemy: Dictionary = _get_upcoming_enemy()
	var store := Store.new(deck_profile_path)
	var profile: Dictionary = store.load_profile()
	builder.profile_path = deck_profile_path
	builder.upcoming_enemy_name = String(enemy["name"])
	builder.upcoming_enemy_card_ids = _enemy_deck_from_details(enemy)
	builder.remembered_enemy_glyphs = store.get_remembered_enemy_glyphs(profile)
	builder.testing_mode = testing_mode
	builder.duel_requested.connect(_on_duel_requested)
	builder.back_requested.connect(_on_return_to_menu_requested)
	_replace_screen(builder)
	if _play_lose_on_next_deck_builder:
		_play_lose_on_next_deck_builder = false
		_music_director.request_context(Music.CONTEXT_DECK_LOSE)
	else:
		_music_director.request_context(Music.CONTEXT_STORY)


func _show_reward_selection() -> void:
	var reward := REWARD_SELECTION_SCENE.instantiate() as RewardController
	var enemy: Dictionary = _get_upcoming_enemy()
	var store := Store.new(deck_profile_path)
	var profile: Dictionary = store.load_profile()
	reward.profile_path = deck_profile_path
	reward.upcoming_enemy_name = String(enemy["name"])
	reward.upcoming_enemy_card_ids = _enemy_deck_from_details(enemy)
	reward.remembered_enemy_glyphs = store.get_remembered_enemy_glyphs(profile)
	reward.testing_mode = testing_mode
	reward.reward_claimed.connect(_on_reward_claimed)
	reward.back_requested.connect(_on_return_to_menu_requested)
	_replace_screen(reward)
	var reward_ids: Array[StringName] = store.get_pending_reward_ids(profile)
	_music_director.request_context(
		Music.CONTEXT_TERROR
		if &"KuiHua0" in reward_ids
		else Music.CONTEXT_STORY
	)


func _show_duel(starting_owner_id: int) -> void:
	var duel := DUEL_SCENE.instantiate() as DuelController
	var enemy: Dictionary = _get_upcoming_enemy()
	var store := Store.new(deck_profile_path)
	var profile: Dictionary = store.load_profile()
	duel.deck_profile_path = deck_profile_path
	duel.starting_owner_id = starting_owner_id
	duel.opponent_name_text = String(enemy["name"])
	duel.opponent_card_ids = _enemy_deck_from_details(enemy)
	duel.opponent_self_castration_enabled = bool(enemy.get(
		"self_castration_enabled",
		true
	))
	duel.remembered_enemy_glyphs = store.get_remembered_enemy_glyphs(profile)
	duel.run_difficulty = store.get_run_difficulty(profile)
	duel.testing_mode = testing_mode
	duel.opponent_card_played.connect(_on_opponent_card_played)
	duel.return_requested.connect(_on_duel_return_requested)
	_replace_screen(duel)
	_music_director.request_context(Music.CONTEXT_BATTLE)


func _show_ending(summary: Dictionary) -> void:
	var ending := ENDING_SCENE.instantiate() as Control
	ending.call("present", summary)
	ending.connect(&"return_requested", _on_ending_return_requested)
	_replace_screen(ending)
	_music_director.request_context(
		Music.CONTEXT_ENDING_BIXIE
		if bool(summary.get("kuihua0_unlocked_this_run", false))
		else Music.CONTEXT_ENDING_LONELY
	)


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
	if not store.get_pending_reward_ids(profile).is_empty():
		_show_reward_selection()
	elif store.is_run_active(profile):
		_show_deck_builder()
	else:
		_show_sect_selection()


func _on_run_reset_confirmed() -> void:
	var store := Store.new(deck_profile_path)
	var profile: Dictionary = store.load_profile()
	var result: Dictionary = store.reset_run_and_save(profile)
	result = _restore_testing_unlocks(store, result)
	_finish_reset_on_current_menu(
		""
		if bool(result.get("ok", false))
		else "保存失败，请重试"
	)


func _on_progress_reset_confirmed() -> void:
	var store := Store.new(deck_profile_path)
	var profile: Dictionary = store.load_profile()
	var result: Dictionary = store.reset_all_progress_and_save(profile)
	result = _restore_testing_unlocks(store, result)
	_finish_reset_on_current_menu(
		""
		if bool(result.get("ok", false))
		else "保存失败，请重试"
	)


func _on_progression_unlock_requested() -> void:
	var store := Store.new(deck_profile_path)
	var profile: Dictionary = store.load_profile()
	var result: Dictionary = store.unlock_all_progression_and_save(profile)
	_finish_reset_on_current_menu(
		"已解锁全部门派与进阶"
		if bool(result.get("ok", false))
		else "保存失败，请重试"
	)


func _finish_reset_on_current_menu(notice: String) -> void:
	var menu := _current_screen as MenuController
	if menu != null:
		menu.show_notice(notice)
		return
	_show_main_menu(notice)


func _restore_testing_unlocks(store: RefCounted, result: Dictionary) -> Dictionary:
	if not testing_mode or not bool(result.get("ok", false)):
		return result
	var expanded: Dictionary = store.create_testing_profile(
		result.get("profile", {}) as Dictionary
	)
	if expanded.is_empty() or not store.save_profile(expanded):
		return {"ok": false, "profile": result.get("profile", {})}
	return {"ok": true, "profile": expanded}


func _on_deck_builder_requested() -> void:
	_show_deck_builder()


func _on_duel_return_requested(outcome: StringName) -> void:
	if outcome == DuelController.OUTCOME_ABANDONED:
		_show_deck_builder()
		return
	var mastery_candidate_ids: Array[StringName] = []
	if outcome == DuelController.OUTCOME_VICTORY:
		var completed_duel := _current_screen as DuelController
		if completed_duel != null:
			mastery_candidate_ids = completed_duel.get_mastery_candidate_ids()
	var store := Store.new(deck_profile_path)
	var profile: Dictionary = store.load_profile()
	var kuihua0_unlocked_this_run: bool = (
		not testing_mode
		and &"KuiHua0" in store.get_unlocked_ids(profile)
	)
	var reward_outcome: StringName = (
		Store.REWARD_VICTORY
		if outcome == DuelController.OUTCOME_VICTORY
		else Store.REWARD_DEFEAT
	)
	var duel_result: Dictionary = store.record_completed_duel_and_save(
		profile,
		reward_outcome,
		victories_required,
		&"",
		mastery_candidate_ids
	)
	if not bool(duel_result.get("ok", false)):
		push_warning("Completed duel could not be saved")
		_show_deck_builder()
		return
	if bool(duel_result.get("completed", false)):
		var ending_summary: Dictionary = (
			duel_result.get("ending_summary", {}) as Dictionary
		).duplicate(true)
		ending_summary["kuihua0_unlocked_this_run"] = kuihua0_unlocked_this_run
		_show_ending(ending_summary)
		return
	profile = duel_result.get("profile", profile)
	var offer_result: Dictionary = store.create_reward_offer_and_save(
		profile,
		reward_outcome
	)
	if not bool(offer_result.get("ok", false)):
		push_warning("Reward offer could not be saved")
		_show_deck_builder()
		return
	if bool(offer_result.get("offered", false)):
		_show_reward_selection()
	else:
		_show_deck_builder()


func _on_reward_claimed(card_id: StringName) -> void:
	if card_id == &"KuiHua0":
		_play_lose_on_next_deck_builder = true
	_show_deck_builder()


func _on_ending_return_requested() -> void:
	_show_main_menu()


func _on_opponent_card_played(glyph: String) -> void:
	var store := Store.new(deck_profile_path)
	var profile: Dictionary = store.load_profile()
	var result: Dictionary = store.remember_enemy_glyph_and_save(profile, glyph)
	if not bool(result.get("ok", false)):
		push_warning("Enemy card memory could not be saved")


func _on_return_to_menu_requested() -> void:
	_show_main_menu()


func _get_upcoming_enemy() -> Dictionary:
	if not upcoming_enemy_name.is_empty() or not upcoming_enemy_card_ids.is_empty():
		return {
			"name": (
				upcoming_enemy_name
				if not upcoming_enemy_name.is_empty()
				else "对手名字"
			),
			"deck": upcoming_enemy_card_ids.duplicate(),
		}
	var store := Store.new(deck_profile_path)
	var profile: Dictionary = store.load_profile()
	var enemy_id: StringName = store.get_current_enemy_id(profile)
	if enemy_id != &"" and Enemies.has_enemy(enemy_id):
		return Enemies.get_definition(enemy_id)
	return {
		"name": "江湖门派",
		"deck": [],
	}


func _enemy_deck_from_details(enemy: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Variant in enemy.get("deck", []):
		result.append(StringName(String(value)))
	return result


func _prepare_testing_profile() -> void:
	_normal_deck_profile_path = deck_profile_path
	var normal_store := Store.new(_normal_deck_profile_path)
	var source: Dictionary = normal_store.load_profile_read_only()
	deck_profile_path = _normal_deck_profile_path + ".testing"
	var testing_store := Store.new(deck_profile_path)
	var testing_profile: Dictionary = testing_store.create_testing_profile(source)
	if testing_profile.is_empty() or not testing_store.save_profile(testing_profile):
		push_warning("Testing profile could not be prepared")
