extends SceneTree

const Store = preload("res://scripts/deck_profile_store.gd")
const Enemies = preload("res://scripts/enemy_catalog.gd")

const NEW_SECT_CARD_IDS: Array[StringName] = [
	&"hanfeng_liezhen",
	&"huixue_liuguang",
	&"qiyao_lianfeng",
	&"wanyue_guizong",
	&"yuyan_tousuo",
	&"wusuo_changqiao",
	&"feixing_ruye",
	&"qianji_tingyu",
	&"hengsha_duanlu",
	&"chilian_huifeng",
	&"shahai_zhuri",
	&"damo_guzhan",
	&"dielang_tuizhou",
	&"huichao_tingjin",
	&"canghai_sandie",
	&"haitian_yizhang",
	&"zhujian_cangfeng",
	&"luming_wenlu",
	&"jingwei_dingju",
	&"zhishang_shanhe",
]

var _checks: int = 0
var _failures: int = 0
var _save_path: String = "user://deck_profile_store_test.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var store: RefCounted = Store.new(_save_path)
	var profile: Dictionary = store.load_profile()
	_check(store.is_profile_valid(profile), "Default profile is valid")
	_check(int(profile["schema_version"]) == 4, "Default profile uses schema version 4")
	_check(not bool(profile["run_active"]), "Default profile has no active run")
	_check(String(profile["selected_sect_id"]).is_empty(), "Default profile has no selected sect")
	_check(store.get_character_level(profile) == 0, "New profiles begin at character level zero")
	_check(store.get_character_tier(profile) == 1, "Character tier begins at one")
	_check(store.get_current_enemy_id(profile) == &"", "Inactive profiles have no enemy")
	_check(
		store.get_unlocked_sect_ids(profile) == [&"xuanyue_jianzong"],
		"Only Xuanyue Jianzong starts unlocked"
	)
	_check((profile["main_deck"] as Array).size() == 5, "Default main deck has five cards")
	_check((profile["library_slots"] as Array).size() == 1000, "Default library has 1000 slots")
	var expected_library_count: int = (profile["unlocked_card_ids"] as Array).size() - 5
	_check(
		_occupied_count(profile["library_slots"]) == expected_library_count,
		"Default library contains every unlocked card outside the main deck"
	)
	_check(
		String(profile["library_slots"][expected_library_count]).is_empty(),
		"The first unused default library slot is empty"
	)
	_check(not (&"CangSongYingKe1" in store.get_unlocked_ids(profile)), "CangSongYingKe1 starts locked")
	for card_id: StringName in NEW_SECT_CARD_IDS:
		_check(card_id not in store.get_unlocked_ids(profile), "%s starts locked" % card_id)
	_check(
		store.repair_profile(profile) == profile,
		"Repairing an existing valid profile does not auto-unlock new sect cards"
	)

	var original_deck: Array = (profile["main_deck"] as Array).duplicate()
	var original_library_card: String = String(profile["library_slots"][1])
	var exchange_result: Dictionary = store.exchange_and_save(profile, 1, 3)
	_check(bool(exchange_result.get("ok", false)), "A valid exchange saves")
	var exchanged: Dictionary = exchange_result.get("profile", {})
	_check(String(exchanged["main_deck"][3]) == original_library_card, "Library card enters target deck slot")
	_check(String(exchanged["library_slots"][1]) == String(original_deck[3]), "Displaced deck card takes exact source slot")
	_check(store.is_profile_valid(exchanged), "Exchanged profile remains valid")

	var reloaded: Dictionary = store.load_profile()
	_check(reloaded == exchanged, "Save/load preserves exact deck and library order")

	var invalid_result: Dictionary = store.exchange_and_save(reloaded, 999, 0)
	_check(not bool(invalid_result.get("ok", true)), "An empty source cannot exchange")
	_check(invalid_result.get("profile", {}) == reloaded, "Invalid exchange preserves the profile")

	var unlock_result: Dictionary = store.unlock_and_save(reloaded, &"CangSongYingKe1")
	_check(bool(unlock_result.get("ok", false)), "A valid unlock saves")
	var unlocked: Dictionary = unlock_result.get("profile", {})
	_check(String(unlocked["library_slots"][0]) == "CangSongYingKe1", "New unlock enters the first library slot")
	_check(String(unlocked["library_slots"][1]) == String(reloaded["library_slots"][0]), "Existing library order shifts forward")
	_check((unlocked["main_deck"] as Array) == (reloaded["main_deck"] as Array), "Unlock does not change main deck")

	var duplicate_unlock: Dictionary = store.unlock_and_save(unlocked, &"CangSongYingKe1")
	_check(not bool(duplicate_unlock.get("ok", true)), "Duplicate unlock is rejected")
	_check(duplicate_unlock.get("profile", {}) == unlocked, "Duplicate unlock preserves profile")

	var batch_result: Dictionary = store.unlock_cards_and_save(
		unlocked,
		[&"hengsha_duanlu", &"chilian_huifeng"]
	)
	_check(bool(batch_result.get("ok", false)), "An ordered card batch saves")
	var batch_profile: Dictionary = batch_result.get("profile", {})
	_check(
		(batch_result.get("added_ids", []) as Array) == [&"hengsha_duanlu", &"chilian_huifeng"],
		"Batch result reports added IDs in input order"
	)
	_check(
		String(batch_profile["library_slots"][0]) == "hengsha_duanlu"
		and String(batch_profile["library_slots"][1]) == "chilian_huifeng",
		"Batch cards enter the library top without reversing"
	)
	_check(
		String(batch_profile["library_slots"][2]) == String(unlocked["library_slots"][0]),
		"Existing library order follows the complete new batch"
	)
	var partial_batch: Dictionary = store.unlock_cards_and_save(
		batch_profile,
		[&"hengsha_duanlu", &"shahai_zhuri"]
	)
	_check(bool(partial_batch.get("ok", false)), "A partially owned batch succeeds")
	var partial_profile: Dictionary = partial_batch.get("profile", {})
	_check(
		(partial_batch.get("added_ids", []) as Array) == [&"shahai_zhuri"],
		"Only the missing card is reported from a partial batch"
	)
	_check(
		String(partial_profile["library_slots"][0]) == "shahai_zhuri"
		and String(partial_profile["library_slots"][1]) == "hengsha_duanlu",
		"Only newly unlocked cards are inserted ahead of existing cards"
	)
	_check(
		partial_profile["unlocked_card_ids"].count("hengsha_duanlu") == 1,
		"Batch unlock never duplicates ownership"
	)
	var no_op_batch: Dictionary = store.unlock_cards_and_save(
		partial_profile,
		[&"hengsha_duanlu", &"missing_card"]
	)
	_check(bool(no_op_batch.get("ok", false)), "An empty filtered batch is a successful no-op")
	_check(no_op_batch.get("profile", {}) == partial_profile, "A no-op batch preserves the exact profile")
	_check((no_op_batch.get("added_ids", []) as Array).is_empty(), "A no-op batch reports no additions")

	var schema_one: Dictionary = profile.duplicate(true)
	schema_one["schema_version"] = 1
	schema_one.erase("unlocked_sect_ids")
	schema_one.erase("run_active")
	schema_one.erase("selected_sect_id")
	var migrated: Dictionary = store.repair_profile(schema_one)
	_check(store.is_profile_valid(migrated), "A schema-1 profile migrates to a valid current profile")
	_check(int(migrated["schema_version"]) == 4, "Migration advances the schema version")
	_check(
		store.get_unlocked_sect_ids(migrated) == [&"xuanyue_jianzong"],
		"Migration adds only the default sect"
	)
	_check(migrated["main_deck"] == profile["main_deck"], "Migration preserves main-deck order")
	_check(migrated["library_slots"] == profile["library_slots"], "Migration preserves library order")
	_check(
		migrated["unlocked_card_ids"] == profile["unlocked_card_ids"],
		"Migration does not unlock cards"
	)
	_check(not bool(migrated["run_active"]), "Legacy migration starts with no active run")
	_check(String(migrated["selected_sect_id"]).is_empty(), "Legacy migration clears the selected sect")

	var schema_two: Dictionary = profile.duplicate(true)
	schema_two["schema_version"] = 2
	schema_two.erase("run_active")
	schema_two.erase("selected_sect_id")
	var migrated_schema_two: Dictionary = store.repair_profile(schema_two)
	_check(store.is_profile_valid(migrated_schema_two), "A schema-2 profile migrates successfully")
	_check(migrated_schema_two["main_deck"] == profile["main_deck"], "Schema-2 migration preserves deck order")
	_check(
		migrated_schema_two["library_slots"] == profile["library_slots"],
		"Schema-2 migration preserves library order"
	)
	_check(
		migrated_schema_two["unlocked_card_ids"] == profile["unlocked_card_ids"],
		"Schema-2 migration preserves unlocked cards"
	)

	var malformed := {
		"schema_version": 1,
		"unlocked_card_ids": ["gate_general", "meng_huo", "jiang_wei", "fa_zheng", "fire_envoy", "tiger_general"],
		"unlocked_sect_ids": ["missing_sect", "yanyu_lou", "yanyu_lou"],
		"main_deck": ["gate_general", "gate_general", "missing", "jiang_wei"],
		"library_slots": ["", "meng_huo", "", "fa_zheng", "fire_envoy", "tiger_general"],
	}
	var repaired: Dictionary = store.repair_profile(malformed)
	_check(store.is_profile_valid(repaired), "Malformed profile repairs to a valid profile")
	_check(
		store.get_unlocked_sect_ids(repaired) == [&"xuanyue_jianzong", &"yanyu_lou"],
		"Repair removes unknown and duplicate sects while restoring the default"
	)
	_check(_library_has_no_gaps(repaired["library_slots"]), "Repair leaves no gaps in occupied prefix")

	var run_start_source: Dictionary = store.create_default_profile()
	_check(store.save_profile(run_start_source), "Run-state fixture saves")
	var begin_result: Dictionary = store.begin_run_and_save(
		run_start_source,
		&"xuanyue_jianzong",
		[&"hanfeng_liezhen"]
	)
	_check(bool(begin_result.get("ok", false)), "Beginning a valid run saves atomically")
	var active_profile: Dictionary = begin_result.get("profile", {})
	_check(store.is_run_active(active_profile), "Beginning a run marks it active")
	_check(store.get_character_level(active_profile) == 1, "Beginning a run advances to level one")
	_check(store.get_character_tier(active_profile) == 1, "Level one remains tier one")
	var first_enemy_id: StringName = store.get_current_enemy_id(active_profile)
	_check(
		first_enemy_id in Enemies.get_enemy_ids_for_level(1),
		"Beginning a run assigns a level-one enemy"
	)
	_check(
		store.get_selected_sect_id(active_profile) == &"xuanyue_jianzong",
		"Beginning a run records the selected sect"
	)
	_check(
		String(active_profile["library_slots"][0]) == "hanfeng_liezhen",
		"Newly unlocked run cards appear at the top of the library"
	)
	var legacy_active: Dictionary = active_profile.duplicate(true)
	legacy_active["schema_version"] = 3
	legacy_active.erase("level")
	legacy_active.erase("current_enemy_id")
	var migrated_active: Dictionary = store.repair_profile(legacy_active)
	_check(store.is_run_active(migrated_active), "A schema-three active run remains active")
	_check(
		store.get_character_level(migrated_active) == 1,
		"Legacy active runs enter progression at level one"
	)
	_check(
		store.get_current_enemy_id(migrated_active) in Enemies.get_enemy_ids_for_level(1),
		"Legacy active runs receive a level-one enemy"
	)
	var active_unlocked: Array = (active_profile["unlocked_card_ids"] as Array).duplicate()
	var exchange_for_reset: Dictionary = store.exchange_and_save(active_profile, 0, 0)
	_check(bool(exchange_for_reset.get("ok", false)), "Run fixture can change its main deck")
	var changed_profile: Dictionary = exchange_for_reset.get("profile", {})
	var reset_result: Dictionary = store.reset_run_and_save(changed_profile)
	_check(bool(reset_result.get("ok", false)), "Resetting the current run saves")
	var reset_profile: Dictionary = reset_result.get("profile", {})
	_check(not store.is_run_active(reset_profile), "Run reset clears active state")
	_check(store.get_selected_sect_id(reset_profile) == &"", "Run reset clears the selected sect")
	_check(
		store.get_main_deck_ids(reset_profile) == Store.DEFAULT_MAIN_DECK_IDS,
		"Run reset restores the default main deck"
	)
	_check(
		reset_profile["unlocked_card_ids"] == active_unlocked,
		"Run reset preserves card unlocks"
	)
	_check(
		reset_profile["unlocked_sect_ids"] == active_profile["unlocked_sect_ids"],
		"Run reset preserves sect unlocks"
	)
	_check(store.get_character_level(reset_profile) == 0, "Run reset clears character level")
	_check(store.get_current_enemy_id(reset_profile) == &"", "Run reset clears the enemy")

	var progression_profile: Dictionary = active_profile
	var previous_enemy_id: StringName = first_enemy_id
	for expected_level: int in range(2, 16):
		var candidate_ids: Array[StringName] = Enemies.get_enemy_ids_for_level(expected_level)
		var advance_result: Dictionary = store.advance_after_victory_and_save(
			progression_profile,
			candidate_ids[expected_level % candidate_ids.size()]
		)
		_check(bool(advance_result.get("ok", false)), "Victory advances to level %d" % expected_level)
		_check(bool(advance_result.get("advanced", false)), "Level %d reports advancement" % expected_level)
		progression_profile = advance_result.get("profile", progression_profile)
		_check(
			store.get_character_level(progression_profile) == expected_level,
			"Victory persists level %d" % expected_level
		)
		var enemy_id: StringName = store.get_current_enemy_id(progression_profile)
		_check(
			enemy_id in candidate_ids and enemy_id != previous_enemy_id,
			"Level %d receives a same-level new enemy" % expected_level
		)
		previous_enemy_id = enemy_id
	var capped_result: Dictionary = store.advance_after_victory_and_save(progression_profile)
	_check(bool(capped_result.get("ok", false)), "A level-fifteen victory is a successful no-op")
	_check(not bool(capped_result.get("advanced", true)), "Level fifteen does not advance")
	_check(
		capped_result.get("profile", {}) == progression_profile,
		"Level-fifteen victory preserves the opponent"
	)

	var expected_tiers: Dictionary = {
		0: 1,
		1: 1,
		2: 2,
		4: 2,
		5: 3,
		7: 3,
		8: 4,
		10: 4,
		11: 5,
		14: 5,
		15: 6,
	}
	for level_value: Variant in expected_tiers:
		_check(
			Store.tier_for_level(int(level_value)) == int(expected_tiers[level_value]),
			"Level %d maps to tier %d" % [level_value, expected_tiers[level_value]]
		)
	var full_reset_result: Dictionary = store.reset_all_progress_and_save(reset_profile)
	_check(bool(full_reset_result.get("ok", false)), "Full progress reset saves")
	_check(
		full_reset_result.get("profile", {}) == store.create_default_profile(),
		"Full progress reset restores the complete default profile"
	)

	var saved_before_failure: Dictionary = store.load_profile()
	var failing_store: RefCounted = Store.new("user://missing_parent/deck_profile.json")
	var failed_save: Dictionary = failing_store.exchange_and_save(saved_before_failure, 0, 0)
	_check(not bool(failed_save.get("ok", true)), "Save failure is reported")
	_check(failed_save.get("profile", {}) == saved_before_failure, "Save failure rolls back candidate data")
	var failed_batch: Dictionary = failing_store.unlock_cards_and_save(
		saved_before_failure,
		[&"hanfeng_liezhen"]
	)
	_check(not bool(failed_batch.get("ok", true)), "Batch save failure is reported")
	_check(failed_batch.get("profile", {}) == saved_before_failure, "Batch save failure rolls back candidate data")
	var failed_begin: Dictionary = failing_store.begin_run_and_save(
		saved_before_failure,
		&"xuanyue_jianzong",
		[]
	)
	_check(not bool(failed_begin.get("ok", true)), "Run-start save failure is reported")
	_check(failed_begin.get("profile", {}) == saved_before_failure, "Run-start save failure rolls back")
	var failed_reset: Dictionary = failing_store.reset_run_and_save(saved_before_failure)
	_check(not bool(failed_reset.get("ok", true)), "Run-reset save failure is reported")
	_check(failed_reset.get("profile", {}) == saved_before_failure, "Run-reset save failure rolls back")
	var failed_full_reset: Dictionary = failing_store.reset_all_progress_and_save(saved_before_failure)
	_check(not bool(failed_full_reset.get("ok", true)), "Full-reset save failure is reported")
	_check(failed_full_reset.get("profile", {}) == saved_before_failure, "Full-reset save failure rolls back")

	_cleanup()
	_finish()


func _occupied_count(slots: Array) -> int:
	var count: int = 0
	for value: Variant in slots:
		if not String(value).is_empty():
			count += 1
	return count


func _library_has_no_gaps(slots: Array) -> bool:
	var found_empty: bool = false
	for value: Variant in slots:
		if String(value).is_empty():
			found_empty = true
		elif found_empty:
			return false
	return true


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = _save_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	if _failures == 0:
		print("DECK_PROFILE_STORE_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("DECK_PROFILE_STORE_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
