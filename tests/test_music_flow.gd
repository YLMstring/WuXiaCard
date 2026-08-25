extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://main.tscn")
const Music = preload("res://scripts/music_director.gd")
const Store = preload("res://scripts/deck_profile_store.gd")
const Catalog = preload("res://scripts/card_catalog.gd")

const NORMAL_SAVE_PATH: String = "user://music_flow_test.json"
const TESTING_SAVE_PATH: String = "user://music_flow_testing_test.json"

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_path(NORMAL_SAVE_PATH)
	_cleanup_path(TESTING_SAVE_PATH)
	await _test_normal_music_flow()
	await _test_testing_unlock_does_not_trigger_bixie()
	_cleanup_path(NORMAL_SAVE_PATH)
	_cleanup_path(TESTING_SAVE_PATH)
	_finish()


func _test_normal_music_flow() -> void:
	var store := Store.new(NORMAL_SAVE_PATH)
	var profile: Dictionary = store.create_default_profile()
	var begin: Dictionary = store.begin_run_and_save(
		profile,
		&"HuaShanPai",
		[],
		&"qingfeng_xuedi"
	)
	profile = begin.get("profile", profile)
	profile["pending_reward_card_ids"] = ["KuiHua0"]
	_check(store.save_profile(profile), "Special-reward music fixture saves")

	var flow: Variant = MAIN_SCENE.instantiate()
	flow.deck_profile_path = NORMAL_SAVE_PATH
	flow.testing_mode = false
	flow.victories_required = 1
	root.add_child(flow)
	await process_frame
	await process_frame
	var director: Variant = flow.debug_get_music_director()
	director.debug_set_fade_durations(0.0, 0.0)
	_check(director.debug_get_current_context() == Music.CONTEXT_MENU, "Main menu requests menu music")

	flow.call("_on_journey_requested")
	await process_frame
	var reward := flow.debug_get_current_screen() as RewardSelectionController
	_check(reward != null, "Pending special reward opens reward selection")
	_check(director.debug_get_current_context() == Music.CONTEXT_TERROR, "KuiHua0 reward uses terror")
	_check(
		director.debug_get_current_track_path() == "res://music/terror.mp3",
		"KuiHua0 reward starts the terror track"
	)
	_check(reward.debug_claim_reward(0), "KuiHua0 reward can be claimed")
	await process_frame
	_check(flow.debug_get_current_screen() is DeckBuilderController, "Claim returns to deck building")
	_check(director.debug_get_current_context() == Music.CONTEXT_DECK_LOSE, "Claim consumes lose entry")
	_check(
		director.debug_get_current_track_path() == "res://music/lose.mp3",
		"First deck entry after KuiHua0 plays lose"
	)
	director.debug_simulate_track_finished()
	_check(director.debug_get_current_context() == Music.CONTEXT_STORY, "Lose naturally restores story pool")

	profile = store.load_profile()
	var ordinary_reward_id: StringName = _first_locked_card_except(
		store.get_unlocked_ids(profile),
		&"KuiHua0"
	)
	_check(ordinary_reward_id != &"", "Normal-reward fixture finds a locked card")
	profile["pending_reward_card_ids"] = [String(ordinary_reward_id)]
	_check(store.save_profile(profile), "Normal-reward music fixture saves")
	var story_path: String = director.debug_get_current_track_path()
	var story_start_count: int = director.debug_get_started_tracks().size()
	flow.call("_show_reward_selection")
	await process_frame
	reward = flow.debug_get_current_screen() as RewardSelectionController
	_check(director.debug_get_current_context() == Music.CONTEXT_STORY, "Normal reward uses story pool")
	_check(director.debug_get_current_track_path() == story_path, "Deck to normal reward continues music")
	_check(
		director.debug_get_started_tracks().size() == story_start_count,
		"Deck to normal reward does not restart the current track"
	)
	_check(reward.debug_claim_reward(0), "Ordinary reward can be claimed")
	await process_frame
	_check(director.debug_get_current_context() == Music.CONTEXT_STORY, "Ordinary claim returns to story")
	_check(director.debug_get_current_track_path() == story_path, "Normal reward to deck continues music")

	flow.call("_show_main_menu")
	var menu_path: String = director.debug_get_current_track_path()
	var menu_start_count: int = director.debug_get_started_tracks().size()
	flow.call("_show_sect_selection")
	_check(director.debug_get_current_context() == Music.CONTEXT_MENU, "Sect selection uses menu pool")
	_check(director.debug_get_current_track_path() == menu_path, "Menu to sect continues music")
	_check(
		director.debug_get_started_tracks().size() == menu_start_count,
		"Menu to sect does not restart the current track"
	)
	flow.call("_show_main_menu")
	_check(director.debug_get_current_track_path() == menu_path, "Sect to menu continues music")

	flow.call("_show_duel", DuelRules.PLAYER_OWNER)
	await process_frame
	var duel := flow.debug_get_current_screen() as DuelController
	_check(duel != null, "Music flow reaches the duel")
	_check(director.debug_get_current_context() == Music.CONTEXT_BATTLE, "Duel uses battle music")
	_check(director.debug_get_current_track_path().get_file().begins_with("battle"), "Duel starts battle track")
	duel.return_requested.emit(DuelController.OUTCOME_VICTORY)
	await process_frame
	_check(director.debug_get_current_context() == Music.CONTEXT_ENDING_BIXIE, "Unlocked KuiHua0 uses bixie ending")
	_check(
		director.debug_get_current_track_path() == "res://music/bixie.mp3",
		"Bixie ending starts the bixie track"
	)
	flow.queue_free()
	await process_frame


func _test_testing_unlock_does_not_trigger_bixie() -> void:
	var flow: Variant = MAIN_SCENE.instantiate()
	flow.deck_profile_path = TESTING_SAVE_PATH
	flow.testing_mode = true
	flow.victories_required = 1
	root.add_child(flow)
	await process_frame
	await process_frame
	var runtime_path: String = String(flow.deck_profile_path)
	var store := Store.new(runtime_path)
	var profile: Dictionary = store.create_default_profile()
	var begin: Dictionary = store.begin_run_and_save(
		profile,
		&"HuaShanPai",
		[],
		&"qingfeng_xuedi"
	)
	profile = store.create_testing_profile(begin.get("profile", profile) as Dictionary)
	_check(store.save_profile(profile), "Testing-mode ending fixture saves")
	var director: Variant = flow.debug_get_music_director()
	director.debug_set_fade_durations(0.0, 0.0)
	flow.call("_show_duel", DuelRules.PLAYER_OWNER)
	await process_frame
	var duel := flow.debug_get_current_screen() as DuelController
	duel.return_requested.emit(DuelController.OUTCOME_VICTORY)
	await process_frame
	_check(
		director.debug_get_current_context() == Music.CONTEXT_ENDING_LONELY,
		"Testing-mode temporary KuiHua0 unlock uses the normal ending"
	)
	_check(
		director.debug_get_current_track_path() == "res://music/lonely.mp3",
		"Testing-mode ending starts lonely"
	)
	flow.queue_free()
	await process_frame


func _first_locked_card_except(
	unlocked_ids: Array[StringName],
	excluded_id: StringName
) -> StringName:
	for card_id: StringName in Catalog.get_all_card_ids():
		if card_id != excluded_id and card_id not in unlocked_ids:
			return card_id
	return &""


func _cleanup_path(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".testing", ".testing.tmp", ".testing.bak"]:
		var candidate: String = path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func _finish() -> void:
	if _failures == 0:
		print("MUSIC_FLOW_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("MUSIC_FLOW_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
