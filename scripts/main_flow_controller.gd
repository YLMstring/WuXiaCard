class_name MainFlowController
extends Control

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/main_menu.tscn")
const SECT_SELECTION_SCENE: PackedScene = preload("res://scenes/sect_selection.tscn")
const DECK_BUILDER_SCENE: PackedScene = preload("res://scenes/deck_builder.tscn")
const REWARD_SELECTION_SCENE: PackedScene = preload("res://scenes/reward_selection.tscn")
const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const ENDING_SCENE: PackedScene = preload("res://scenes/ending.tscn")
const TUTORIAL_SCENE_PATH: String = "res://scenes/tutorial.tscn"
const Music = preload("res://scripts/music_director.gd")
const MenuController = preload("res://scripts/main_menu_controller.gd")
const SelectorController = preload("res://scripts/sect_selection_controller.gd")
const RewardController = preload("res://scripts/reward_selection_controller.gd")
const DuelRules = preload("res://scripts/duel_rules.gd")
const Settings = preload("res://scripts/game_settings.gd")
const Store = preload("res://scripts/deck_profile_store.gd")
const Enemies = preload("res://scripts/enemy_catalog.gd")
const BalanceStore = preload("res://scripts/balance_telemetry_store.gd")
const BalanceUploader = preload("res://scripts/balance_telemetry_uploader.gd")

@export var deck_profile_path: String = Store.DEFAULT_SAVE_PATH
@export var balance_telemetry_path: String = BalanceStore.DEFAULT_SAVE_PATH
@export var telemetry_enabled: bool = true
@export var balance_telemetry_endpoint: String = ""
@export var telemetry_force_local_capture_for_tests: bool = false
@export var upcoming_enemy_name: String = ""
@export var upcoming_enemy_card_ids: Array[StringName] = []
@export_range(1, Store.MAX_CHARACTER_LEVEL) var victories_required: int = (
	Store.DEFAULT_VICTORIES_REQUIRED
)

var testing_mode: bool = Settings.default_testing_mode()
var _current_screen: Control = null
var _normal_deck_profile_path: String = ""
var _music_director: Node = null
var _play_lose_on_next_deck_builder: bool = false
var _balance_telemetry_store: RefCounted = null
var _balance_telemetry_uploader: Node = null
var _pending_telemetry_duel_token: String = ""


func _ready() -> void:
	_music_director = Music.new() as Node
	add_child(_music_director)
	if testing_mode:
		_prepare_testing_profile()
	_prepare_balance_telemetry()
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
	_try_upload_pending_balance_telemetry()
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


func _show_tutorial() -> void:
	var tutorial_scene := ResourceLoader.load(TUTORIAL_SCENE_PATH) as PackedScene
	if tutorial_scene == null:
		push_error("Tutorial scene could not be loaded")
		_show_main_menu("教程资源加载失败，请重试")
		return
	var tutorial := tutorial_scene.instantiate() as Control
	tutorial.connect(&"completion_requested", _on_tutorial_completion_requested)
	_replace_screen(tutorial)
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
	_begin_balance_telemetry_duel(store, profile, duel)
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
		_continue_active_run()
	elif _should_auto_start_default_run(store, profile):
		var result: Dictionary = store.begin_run_and_save(
			profile,
			&"HuaShanPai",
			[],
			&"",
			null,
			false,
			0
		)
		if bool(result.get("ok", false)):
			_begin_balance_telemetry_run(result.get("profile", {}) as Dictionary)
			_continue_active_run()
		else:
			_finish_reset_on_current_menu("保存失败，请重试")
	else:
		_show_sect_selection()


func _should_auto_start_default_run(store: RefCounted, profile: Dictionary) -> bool:
	if testing_mode or store.get_max_unlocked_difficulty(profile) != 0:
		return false
	var unlocked_sect_ids: Array[StringName] = store.get_unlocked_sect_ids(profile)
	return unlocked_sect_ids.size() == 1 and unlocked_sect_ids[0] == &"HuaShanPai"


func _on_run_reset_confirmed() -> void:
	var store := Store.new(deck_profile_path)
	var profile: Dictionary = store.load_profile()
	var result: Dictionary = store.reset_run_and_save(profile)
	if bool(result.get("ok", false)):
		_clear_active_balance_telemetry_run()
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
	if bool(result.get("ok", false)):
		_clear_active_balance_telemetry_run()
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
	var store := Store.new(deck_profile_path)
	_begin_balance_telemetry_run(store.load_profile())
	_continue_active_run()


func _continue_active_run() -> void:
	var store := Store.new(deck_profile_path)
	var profile: Dictionary = store.load_profile()
	if store.is_tutorial_pending(profile):
		_show_tutorial()
	else:
		_show_deck_builder()


func _on_tutorial_completion_requested() -> void:
	var tutorial: Control = _current_screen
	if tutorial == null or not tutorial.has_method("show_save_error"):
		return
	var store := Store.new(deck_profile_path)
	var profile: Dictionary = store.load_profile()
	var result: Dictionary = store.complete_tutorial_and_save(profile)
	if not bool(result.get("ok", false)):
		tutorial.call("show_save_error")
		return
	_show_deck_builder()


func _on_duel_return_requested(outcome: StringName) -> void:
	if outcome == DuelController.OUTCOME_ABANDONED:
		_abandon_pending_balance_telemetry_duel()
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
	var telemetry_duel_saved: bool = _complete_pending_balance_telemetry_duel(
		reward_outcome
	)
	if bool(duel_result.get("completed", false)):
		var ending_summary: Dictionary = (
			duel_result.get("ending_summary", {}) as Dictionary
		).duplicate(true)
		ending_summary["kuihua0_unlocked_this_run"] = kuihua0_unlocked_this_run
		if telemetry_duel_saved:
			_seal_completed_balance_telemetry_run(
				int(ending_summary.get("score", 0))
			)
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


func _prepare_balance_telemetry() -> void:
	var capture_enabled: bool = Settings.should_capture_balance_telemetry(
		testing_mode,
		OS.has_feature("editor"),
		OS.has_feature("headless"),
		telemetry_force_local_capture_for_tests
	)
	if not telemetry_enabled or not capture_enabled:
		return
	_balance_telemetry_store = BalanceStore.new(balance_telemetry_path)
	_balance_telemetry_store.load_state()
	var endpoint: String = balance_telemetry_endpoint.strip_edges()
	if endpoint.is_empty():
		endpoint = String(ProjectSettings.get_setting(
			"balance_telemetry/endpoint",
			""
		)).strip_edges()
	_balance_telemetry_uploader = BalanceUploader.new()
	add_child(_balance_telemetry_uploader)
	_balance_telemetry_uploader.configure(
		_balance_telemetry_store,
		endpoint,
		Settings.should_upload_balance_telemetry(
			capture_enabled,
			telemetry_enabled,
			endpoint,
			OS.get_name()
		)
	)


func _begin_balance_telemetry_run(profile: Dictionary) -> void:
	if _balance_telemetry_store == null:
		return
	var store := Store.new(deck_profile_path)
	if not store.is_run_active(profile):
		return
	var result: Dictionary = _balance_telemetry_store.start_run(
		store.get_run_difficulty(profile),
		store.get_selected_sect_id(profile),
		String(ProjectSettings.get_setting("application/config/version", "")),
		OS.get_name()
	)
	if not bool(result.get("ok", false)):
		push_warning("Balance telemetry run could not be started")


func _begin_balance_telemetry_duel(
	store: RefCounted,
	profile: Dictionary,
	duel: DuelController
) -> void:
	_pending_telemetry_duel_token = ""
	if _balance_telemetry_store == null or not _balance_telemetry_store.has_active_run():
		return
	var enemy_id: StringName = store.get_current_enemy_id(profile)
	if enemy_id == &"":
		return
	var opening_cards: Dictionary = duel.get_opening_main_deck_card_ids()
	var result: Dictionary = _balance_telemetry_store.begin_duel(
		enemy_id,
		store.get_character_level(profile),
		duel.get_opening_owner_id(),
		opening_cards.get(DuelRules.PLAYER_OWNER, []),
		opening_cards.get(DuelRules.OPPONENT_OWNER, []),
		store.get_beginner_opening_stage(profile) == Store.BEGINNER_OPENING_NONE
	)
	if not bool(result.get("ok", false)):
		push_warning("Balance telemetry duel could not be started")
		return
	_pending_telemetry_duel_token = String(result.get("duel_token", ""))


func _abandon_pending_balance_telemetry_duel() -> void:
	if _balance_telemetry_store == null or _pending_telemetry_duel_token.is_empty():
		return
	if not _balance_telemetry_store.abandon_pending_duel(
		_pending_telemetry_duel_token
	):
		push_warning("Abandoned balance telemetry duel could not be cleared")
	_pending_telemetry_duel_token = ""


func _complete_pending_balance_telemetry_duel(outcome: StringName) -> bool:
	if _balance_telemetry_store == null or _pending_telemetry_duel_token.is_empty():
		return false
	var result: Dictionary = _balance_telemetry_store.complete_pending_duel(
		_pending_telemetry_duel_token,
		outcome
	)
	_pending_telemetry_duel_token = ""
	if bool(result.get("ok", false)):
		return true
	push_warning("Completed balance telemetry duel could not be saved")
	return false


func _seal_completed_balance_telemetry_run(final_score: int) -> void:
	if _balance_telemetry_store == null:
		return
	var result: Dictionary = _balance_telemetry_store.seal_completed_run(final_score)
	if not bool(result.get("ok", false)):
		push_warning("Completed balance telemetry run could not be queued")
		return
	_try_upload_pending_balance_telemetry()


func _try_upload_pending_balance_telemetry() -> void:
	if _balance_telemetry_uploader != null:
		_balance_telemetry_uploader.try_upload_pending.call_deferred()


func _clear_active_balance_telemetry_run() -> void:
	_pending_telemetry_duel_token = ""
	if _balance_telemetry_store == null:
		return
	if not _balance_telemetry_store.clear_active_run():
		push_warning("Active balance telemetry run could not be cleared")


func debug_get_balance_telemetry_state() -> Dictionary:
	if _balance_telemetry_store == null:
		return {}
	return _balance_telemetry_store.load_state().duplicate(true)
