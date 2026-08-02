extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://main.tscn")
const Rules = preload("res://scripts/duel_rules.gd")
const Store = preload("res://scripts/deck_profile_store.gd")
const Enemies = preload("res://scripts/enemy_catalog.gd")
const Cards = preload("res://scripts/card_catalog.gd")
const MenuController = preload("res://scripts/main_menu_controller.gd")
const SelectorController = preload("res://scripts/sect_selection_controller.gd")
const RewardController = preload("res://scripts/reward_selection_controller.gd")

var _checks: int = 0
var _failures: int = 0
var _save_path: String = "user://main_flow_test.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var flow: Variant = MAIN_SCENE.instantiate()
	flow.deck_profile_path = _save_path
	flow.testing_mode = true
	flow.victories_required = 15
	root.add_child(flow)
	await process_frame
	await process_frame

	var menu := flow.debug_get_current_screen() as MenuController
	_check(menu != null, "Main scene starts at the main menu")
	(menu.get_node("MenuLayer/Actions/JourneyButton") as Button).pressed.emit()
	await process_frame
	var selector := flow.debug_get_current_screen() as SelectorController
	_check(selector != null, "An inactive run routes to sect selection")
	_check(selector.upcoming_enemy_name == "江湖门派", "Sect selection labels its friendly sect preview")
	(selector.get_node("DuelCanvas/TopBar/BackButton") as Button).pressed.emit()
	await process_frame
	menu = flow.debug_get_current_screen() as MenuController
	_check(menu != null, "Sect-selection back returns to the main menu")

	(menu.get_node("MenuLayer/Actions/JourneyButton") as Button).pressed.emit()
	await process_frame
	selector = flow.debug_get_current_screen() as SelectorController
	_check(selector.debug_select_sect(&"xuanyue_jianzong"), "Selector accepts the default sect")
	_check(selector.debug_confirm_selected_sect(), "Confirming a sect starts the run")
	await process_frame
	var builder := flow.debug_get_current_screen() as DeckBuilderController
	_check(builder != null, "Sect confirmation enters deck building")
	var active_profile: Dictionary = Store.new(_save_path).load_profile()
	_check(bool(active_profile["run_active"]), "Sect confirmation persists active-run state")
	_check(
		String(active_profile["selected_sect_id"]) == "xuanyue_jianzong",
		"Sect confirmation persists the chosen sect"
	)
	var store := Store.new(_save_path)
	_check(store.get_character_level(active_profile) == 1, "Sect confirmation starts level one")
	var level_one_enemy_id: StringName = store.get_current_enemy_id(active_profile)
	var level_one_enemy: Dictionary = Enemies.get_definition(level_one_enemy_id)
	_check(builder.upcoming_enemy_name == String(level_one_enemy["name"]), "Deck builder shows the saved level-one enemy")
	_check(
		builder.upcoming_enemy_card_ids == level_one_enemy["deck"],
		"Deck builder shows the saved enemy deck"
	)
	(builder.get_node("DuelCanvas/TopBar/BackButton") as Button).pressed.emit()
	await process_frame
	menu = flow.debug_get_current_screen() as MenuController
	_check(menu != null, "Deck-builder back returns to the main menu")

	(menu.get_node("MenuLayer/Actions/JourneyButton") as Button).pressed.emit()
	await process_frame
	builder = flow.debug_get_current_screen() as DeckBuilderController
	_check(builder != null, "An active run resumes directly in deck building")
	_check(builder.upcoming_enemy_name == String(level_one_enemy["name"]), "Resuming preserves the enemy")
	(builder.get_node("DuelCanvas/GoSecondButton") as Button).pressed.emit()
	await process_frame
	var duel := flow.debug_get_current_screen() as DuelController
	_check(duel != null, "Go-second choice enters the duel")
	_check(duel.debug_get_active_owner() == Rules.OPPONENT_OWNER, "Go-second gives the opponent opening turn")
	_check(
		duel.opponent_name_text == String(level_one_enemy["name"]),
		"Duel receives the same saved enemy"
	)
	var opponent_hand := duel.get_node("DuelCanvas/OpponentHand") as HBoxContainer
	var played_card := opponent_hand.get_child(0).get_child(0) as CardView
	var played_glyph: String = String(played_card.card_data.get("glyph", ""))
	_check(
		await duel.debug_commit_move(Rules.OPPONENT_OWNER, 0, 0, false),
		"Opponent hand play commits for memory tracking"
	)
	var memory_profile: Dictionary = store.load_profile()
	_check(
		played_glyph in store.get_remembered_enemy_glyphs(memory_profile),
		"Opponent hand play immediately persists its glyph"
	)
	var mastery_fixture_id: StringName = store.get_main_deck_ids(memory_profile)[0]
	duel.call("_record_mastery_candidate", mastery_fixture_id)
	(duel.get_node("DuelCanvas/TopBar/ExitButton") as Button).pressed.emit()
	await process_frame
	builder = flow.debug_get_current_screen() as DeckBuilderController
	_check(builder != null, "Duel return still goes back to deck building")
	var abandoned_profile: Dictionary = store.load_profile()
	_check(store.get_character_level(abandoned_profile) == 1, "Abandoning a duel does not level up")
	_check(
		store.get_current_enemy_id(abandoned_profile) == level_one_enemy_id,
		"Abandoning a duel preserves the rematch enemy"
	)
	_check(
		played_glyph in store.get_remembered_enemy_glyphs(abandoned_profile),
		"Abandoning preserves remembered enemy cards"
	)
	_check(
		played_glyph in builder.remembered_enemy_glyphs,
		"Returning deck builder receives remembered enemy cards"
	)
	_check(
		not store.is_card_mastered(abandoned_profile, mastery_fixture_id),
		"Abandoning discards mastery candidates"
	)

	(builder.get_node("DuelCanvas/GoSecondButton") as Button).pressed.emit()
	await process_frame
	duel = flow.debug_get_current_screen() as DuelController
	duel.call("_record_mastery_candidate", mastery_fixture_id)
	duel.return_requested.emit(&"victory")
	await process_frame
	var reward := flow.debug_get_current_screen() as RewardController
	_check(reward != null, "Victory opens reward selection")
	var victorious_profile: Dictionary = store.load_profile()
	_check(
		store.is_card_mastered(victorious_profile, mastery_fixture_id),
		"Winning persists the played main-deck card as globally mastered"
	)
	_check(store.get_character_level(victorious_profile) == 2, "Completed victory advances one level")
	_check(
		&"huixue_liuguang" in store.get_unlocked_ids(victorious_profile),
		"Crossing into tier two unlocks the selected sect's tier-two card"
	)
	_check(
		String(victorious_profile["library_slots"][0]) == "huixue_liuguang",
		"Automatic tier card reaches the library top before reward selection"
	)
	var level_two_enemy_id: StringName = store.get_current_enemy_id(victorious_profile)
	var level_two_enemy: Dictionary = Enemies.get_definition(level_two_enemy_id)
	_check(int(level_two_enemy["level"]) == 2, "Victory assigns a same-level enemy")
	_check(reward.upcoming_enemy_name == String(level_two_enemy["name"]), "Reward scene previews the new enemy")
	_check(
		store.get_remembered_enemy_glyphs(victorious_profile).is_empty(),
		"New enemy starts with no remembered cards"
	)
	var victory_reward_ids: Array[StringName] = store.get_pending_reward_ids(victorious_profile)
	_check(not victory_reward_ids.is_empty(), "Victory persists a reward offer")
	for reward_id: StringName in victory_reward_ids:
		_check(int(Cards.get_definition(reward_id)["tier"]) == 2, "Victory uses the new tier")
		_check(
			reward_id != &"huixue_liuguang",
			"Automatic tier unlock cannot reappear in the victory reward"
		)
	_check(reward.debug_claim_reward(0), "Victory reward can be claimed")
	await process_frame
	builder = flow.debug_get_current_screen() as DeckBuilderController
	_check(builder != null, "Claiming a victory reward enters deck building")
	_check(
		victory_reward_ids[0] in store.get_unlocked_ids(store.load_profile()),
		"Claimed victory reward is unlocked"
	)

	(builder.get_node("DuelCanvas/GoSecondButton") as Button).pressed.emit()
	await process_frame
	duel = flow.debug_get_current_screen() as DuelController
	duel.return_requested.emit(&"defeat")
	await process_frame
	reward = flow.debug_get_current_screen() as RewardController
	_check(reward != null, "Defeat opens reward selection")
	var defeated_profile: Dictionary = store.load_profile()
	_check(store.get_character_level(defeated_profile) == 2, "Defeat does not level up")
	_check(
		store.get_current_enemy_id(defeated_profile) == level_two_enemy_id,
		"Defeat preserves the rematch enemy"
	)
	var defeat_reward_ids: Array[StringName] = store.get_pending_reward_ids(defeated_profile)
	_check(not defeat_reward_ids.is_empty(), "Defeat persists a lower-tier offer")
	for reward_id: StringName in defeat_reward_ids:
		_check(int(Cards.get_definition(reward_id)["tier"]) < 2, "Defeat uses a lower tier")

	(reward.get_node("DuelCanvas/TopBar/BackButton") as Button).pressed.emit()
	await process_frame
	menu = flow.debug_get_current_screen() as MenuController
	_check(menu != null, "Reward return icon goes to the main menu")
	(menu.get_node("MenuLayer/Actions/JourneyButton") as Button).pressed.emit()
	await process_frame
	reward = flow.debug_get_current_screen() as RewardController
	_check(
		reward != null and reward.debug_get_reward_ids() == defeat_reward_ids,
		"Journey resumes the exact pending reward"
	)
	_check(reward.debug_claim_reward(0), "Resumed defeat reward can be claimed")
	await process_frame
	builder = flow.debug_get_current_screen() as DeckBuilderController
	(builder.get_node("DuelCanvas/TopBar/BackButton") as Button).pressed.emit()
	await process_frame
	menu = flow.debug_get_current_screen() as MenuController
	var run_reset_menu_id: int = menu.get_instance_id()
	var run_reset_button := menu.get_node("MenuLayer/Actions/RunResetButton") as Button
	for press_index: int in range(5):
		run_reset_button.pressed.emit()
	await process_frame
	menu = flow.debug_get_current_screen() as MenuController
	_check(menu != null, "Run reset stays on the main menu")
	_check(
		menu.get_instance_id() == run_reset_menu_id,
		"Run reset preserves the existing main-menu animation instance"
	)
	_check(
		(menu.get_node("MenuLayer/Notice") as Label).text.is_empty(),
		"Successful run reset clears the countdown notice"
	)
	var reset_profile: Dictionary = Store.new(_save_path).load_profile()
	_check(not bool(reset_profile["run_active"]), "Run reset clears active state")
	_check(
		Store.new(_save_path).get_main_deck_ids(reset_profile) == Store.DEFAULT_MAIN_DECK_IDS,
		"Run reset restores the default deck"
	)
	_check(
		&"hanfeng_liezhen" in Store.new(_save_path).get_unlocked_ids(reset_profile),
		"Run reset preserves unlocked cards"
	)
	_check(
		Store.new(_save_path).is_card_mastered(reset_profile, mastery_fixture_id),
		"Run reset preserves global card mastery"
	)

	var progress_reset_menu_id: int = menu.get_instance_id()
	var progress_reset_button := menu.get_node("MenuLayer/Actions/ProgressResetButton") as Button
	for press_index: int in range(10):
		progress_reset_button.pressed.emit()
	await process_frame
	menu = flow.debug_get_current_screen() as MenuController
	_check(
		menu.get_instance_id() == progress_reset_menu_id,
		"Full progress reset preserves the existing main-menu animation instance"
	)
	_check(
		(menu.get_node("MenuLayer/Notice") as Label).text.is_empty(),
		"Successful full reset clears the countdown notice"
	)
	var fully_reset_profile: Dictionary = Store.new(_save_path).load_profile()
	_check(
		fully_reset_profile == Store.new(_save_path).create_default_profile(),
		"Full progress reset restores the initial profile"
	)
	_check(
		not Store.new(_save_path).is_card_mastered(fully_reset_profile, mastery_fixture_id),
		"Full progress reset clears global card mastery"
	)

	flow.queue_free()
	await process_frame

	var failing_flow: Variant = MAIN_SCENE.instantiate()
	failing_flow.deck_profile_path = "user://missing_parent/main_flow_test.json"
	root.add_child(failing_flow)
	await process_frame
	var failing_menu := failing_flow.debug_get_current_screen() as MenuController
	var failing_reset_button := (
		failing_menu.get_node("MenuLayer/Actions/RunResetButton") as Button
	)
	for press_index: int in range(5):
		failing_reset_button.pressed.emit()
	await process_frame
	failing_menu = failing_flow.debug_get_current_screen() as MenuController
	_check(
		(failing_menu.get_node("MenuLayer/Notice") as Label).text == "保存失败，请重试",
		"A failed reset remains on the menu and reports the save failure"
	)
	failing_flow.queue_free()
	await process_frame

	_cleanup()
	_finish()


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = _save_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	if _failures == 0:
		print("MAIN_FLOW_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("MAIN_FLOW_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
