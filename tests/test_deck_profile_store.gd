extends SceneTree

const Store = preload("res://scripts/deck_profile_store.gd")

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
	_check(int(profile["schema_version"]) == 2, "Default profile uses schema version 2")
	_check(
		store.get_unlocked_sect_ids(profile) == [&"xuanyue_jianzong"],
		"Only Xuanyue Jianzong starts unlocked"
	)
	_check((profile["main_deck"] as Array).size() == 5, "Default main deck has five cards")
	_check((profile["library_slots"] as Array).size() == 1000, "Default library has 1000 slots")
	_check(_occupied_count(profile["library_slots"]) == 4, "Default library has four occupied slots")
	_check(String(profile["library_slots"][4]).is_empty(), "The fifth library slot is empty")
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
	var migrated: Dictionary = store.repair_profile(schema_one)
	_check(store.is_profile_valid(migrated), "A schema-1 profile migrates to a valid current profile")
	_check(int(migrated["schema_version"]) == 2, "Migration advances the schema version")
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
	_check(String(repaired["library_slots"][0]) != "", "Repair compacts occupied slots to the top")
	_check(_library_has_no_gaps(repaired["library_slots"]), "Repair leaves no gaps in occupied prefix")

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
