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

	var malformed := {
		"schema_version": 1,
		"unlocked_card_ids": ["gate_general", "meng_huo", "jiang_wei", "fa_zheng", "fire_envoy", "tiger_general"],
		"main_deck": ["gate_general", "gate_general", "missing", "jiang_wei"],
		"library_slots": ["", "meng_huo", "", "fa_zheng", "fire_envoy", "tiger_general"],
	}
	var repaired: Dictionary = store.repair_profile(malformed)
	_check(store.is_profile_valid(repaired), "Malformed profile repairs to a valid profile")
	_check(String(repaired["library_slots"][0]) != "", "Repair compacts occupied slots to the top")
	_check(_library_has_no_gaps(repaired["library_slots"]), "Repair leaves no gaps in occupied prefix")

	var saved_before_failure: Dictionary = store.load_profile()
	var failing_store: RefCounted = Store.new("user://missing_parent/deck_profile.json")
	var failed_save: Dictionary = failing_store.exchange_and_save(saved_before_failure, 0, 0)
	_check(not bool(failed_save.get("ok", true)), "Save failure is reported")
	_check(failed_save.get("profile", {}) == saved_before_failure, "Save failure rolls back candidate data")

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
