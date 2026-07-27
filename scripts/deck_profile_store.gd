class_name DeckProfileStore
extends RefCounted

const Catalog = preload("res://scripts/card_catalog.gd")

const SCHEMA_VERSION: int = 1
const MAIN_DECK_CAPACITY: int = 5
const LIBRARY_CAPACITY: int = 1000
const DEFAULT_SAVE_PATH: String = "user://wuxia_deck_profile.json"
const DEFAULT_MAIN_DECK_IDS: Array[StringName] = [
	&"CangSongYingKe2",
	&"gate_general",
	&"meng_huo",
	&"jiang_wei",
	&"fa_zheng",
]
const DEFAULT_LOCKED_IDS: Array[StringName] = [
	&"CangSongYingKe1",
]

var save_path: String


func _init(new_save_path: String = DEFAULT_SAVE_PATH) -> void:
	save_path = new_save_path


func create_default_profile() -> Dictionary:
	var unlocked_ids: Array[StringName] = _default_unlocked_ids()
	var main_deck: Array = []
	for card_id: StringName in DEFAULT_MAIN_DECK_IDS:
		if card_id in unlocked_ids:
			main_deck.append(String(card_id))
	var library_cards: Array = []
	for card_id: StringName in unlocked_ids:
		if card_id not in DEFAULT_MAIN_DECK_IDS:
			library_cards.append(String(card_id))
	return {
		"schema_version": SCHEMA_VERSION,
		"unlocked_card_ids": _string_array(unlocked_ids),
		"main_deck": main_deck,
		"library_slots": _padded_library(library_cards),
	}


func load_profile() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		var default_profile: Dictionary = create_default_profile()
		save_profile(default_profile)
		return default_profile
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return create_default_profile()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Deck profile JSON is invalid; using defaults")
		return create_default_profile()
	var repaired: Dictionary = repair_profile(parsed as Dictionary)
	if not is_profile_valid(repaired):
		push_warning("Deck profile could not be repaired; using defaults")
		return create_default_profile()
	if repaired != parsed:
		save_profile(repaired)
	return repaired


func save_profile(profile: Dictionary) -> bool:
	if not is_profile_valid(profile):
		return false
	var temporary_path: String = save_path + ".tmp"
	var backup_path: String = save_path + ".bak"
	var temporary_file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if temporary_file == null:
		return false
	temporary_file.store_string(JSON.stringify(profile))
	temporary_file.flush()
	temporary_file.close()
	var temporary_global: String = ProjectSettings.globalize_path(temporary_path)
	var save_global: String = ProjectSettings.globalize_path(save_path)
	var backup_global: String = ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_global)
	var had_existing: bool = FileAccess.file_exists(save_path)
	if had_existing and DirAccess.rename_absolute(save_global, backup_global) != OK:
		DirAccess.remove_absolute(temporary_global)
		return false
	if DirAccess.rename_absolute(temporary_global, save_global) != OK:
		if had_existing:
			DirAccess.rename_absolute(backup_global, save_global)
		return false
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_global)
	return true


func is_profile_valid(profile: Dictionary) -> bool:
	if int(profile.get("schema_version", -1)) != SCHEMA_VERSION:
		return false
	var unlocked_value: Variant = profile.get("unlocked_card_ids", null)
	var deck_value: Variant = profile.get("main_deck", null)
	var library_value: Variant = profile.get("library_slots", null)
	if typeof(unlocked_value) != TYPE_ARRAY or typeof(deck_value) != TYPE_ARRAY or typeof(library_value) != TYPE_ARRAY:
		return false
	var unlocked: Array = unlocked_value
	var deck: Array = deck_value
	var library: Array = library_value
	if deck.size() != MAIN_DECK_CAPACITY or library.size() != LIBRARY_CAPACITY:
		return false
	var catalog_ids: Array[StringName] = Catalog.get_all_card_ids()
	var unlocked_set: Dictionary = {}
	for value: Variant in unlocked:
		var card_id := StringName(String(value))
		if card_id == &"" or card_id not in catalog_ids or unlocked_set.has(card_id):
			return false
		unlocked_set[card_id] = true
	if unlocked_set.size() < MAIN_DECK_CAPACITY:
		return false
	var placed_set: Dictionary = {}
	for value: Variant in deck:
		var card_id := StringName(String(value))
		if not unlocked_set.has(card_id) or placed_set.has(card_id):
			return false
		placed_set[card_id] = true
	var found_empty: bool = false
	for value: Variant in library:
		var text_value: String = String(value)
		if text_value.is_empty():
			found_empty = true
			continue
		if found_empty:
			return false
		var card_id := StringName(text_value)
		if not unlocked_set.has(card_id) or placed_set.has(card_id):
			return false
		placed_set[card_id] = true
	return placed_set.size() == unlocked_set.size()


func repair_profile(profile: Dictionary) -> Dictionary:
	var catalog_ids: Array[StringName] = Catalog.get_all_card_ids()
	var unlocked: Array[StringName] = []
	var raw_unlocked: Variant = profile.get("unlocked_card_ids", null)
	if typeof(raw_unlocked) == TYPE_ARRAY:
		for value: Variant in raw_unlocked:
			var card_id := StringName(String(value))
			if card_id != &"" and card_id in catalog_ids and card_id not in unlocked:
				unlocked.append(card_id)
	else:
		unlocked = _default_unlocked_ids()
	if unlocked.size() < MAIN_DECK_CAPACITY:
		return create_default_profile()

	var deck: Array[StringName] = []
	var raw_deck: Variant = profile.get("main_deck", [])
	if typeof(raw_deck) == TYPE_ARRAY:
		for value: Variant in raw_deck:
			var card_id := StringName(String(value))
			if card_id in unlocked and card_id not in deck and deck.size() < MAIN_DECK_CAPACITY:
				deck.append(card_id)

	var library_order: Array[StringName] = []
	var raw_library: Variant = profile.get("library_slots", [])
	if typeof(raw_library) == TYPE_ARRAY:
		for value: Variant in raw_library:
			var card_id := StringName(String(value))
			if card_id != &"" and card_id in unlocked and card_id not in deck and card_id not in library_order:
				library_order.append(card_id)

	for card_id: StringName in library_order.duplicate():
		if deck.size() >= MAIN_DECK_CAPACITY:
			break
		deck.append(card_id)
		library_order.erase(card_id)
	for card_id: StringName in unlocked:
		if deck.size() >= MAIN_DECK_CAPACITY:
			break
		if card_id not in deck and card_id not in library_order:
			deck.append(card_id)
	if deck.size() != MAIN_DECK_CAPACITY:
		return create_default_profile()

	var missing_library: Array[StringName] = []
	for card_id: StringName in unlocked:
		if card_id not in deck and card_id not in library_order:
			missing_library.append(card_id)
	var repaired_library: Array = _string_array(missing_library)
	repaired_library.append_array(_string_array(library_order))
	if repaired_library.size() > LIBRARY_CAPACITY:
		return create_default_profile()
	return {
		"schema_version": SCHEMA_VERSION,
		"unlocked_card_ids": _string_array(unlocked),
		"main_deck": _string_array(deck),
		"library_slots": _padded_library(repaired_library),
	}


func exchange_and_save(profile: Dictionary, library_index: int, deck_index: int) -> Dictionary:
	var unchanged: Dictionary = profile.duplicate(true)
	if not is_profile_valid(profile):
		return {"ok": false, "profile": unchanged}
	if library_index < 0 or library_index >= LIBRARY_CAPACITY:
		return {"ok": false, "profile": unchanged}
	if deck_index < 0 or deck_index >= MAIN_DECK_CAPACITY:
		return {"ok": false, "profile": unchanged}
	if String(profile["library_slots"][library_index]).is_empty():
		return {"ok": false, "profile": unchanged}
	var candidate: Dictionary = profile.duplicate(true)
	var displaced: Variant = candidate["main_deck"][deck_index]
	candidate["main_deck"][deck_index] = candidate["library_slots"][library_index]
	candidate["library_slots"][library_index] = displaced
	if not is_profile_valid(candidate) or not save_profile(candidate):
		return {"ok": false, "profile": unchanged}
	return {"ok": true, "profile": candidate}


func unlock_and_save(profile: Dictionary, card_id: StringName) -> Dictionary:
	var unchanged: Dictionary = profile.duplicate(true)
	if not is_profile_valid(profile):
		return {"ok": false, "profile": unchanged}
	if card_id not in Catalog.get_all_card_ids() or card_id in get_unlocked_ids(profile):
		return {"ok": false, "profile": unchanged}
	var occupied: Array = _occupied_library(profile["library_slots"])
	if occupied.size() >= LIBRARY_CAPACITY:
		return {"ok": false, "profile": unchanged}
	var candidate: Dictionary = profile.duplicate(true)
	occupied.push_front(String(card_id))
	candidate["library_slots"] = _padded_library(occupied)
	(candidate["unlocked_card_ids"] as Array).push_front(String(card_id))
	if not is_profile_valid(candidate) or not save_profile(candidate):
		return {"ok": false, "profile": unchanged}
	return {"ok": true, "profile": candidate}


func get_unlocked_ids(profile: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	var raw: Variant = profile.get("unlocked_card_ids", [])
	if typeof(raw) != TYPE_ARRAY:
		return result
	for value: Variant in raw:
		result.append(StringName(String(value)))
	return result


func get_main_deck_ids(profile: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	if not is_profile_valid(profile):
		return DEFAULT_MAIN_DECK_IDS.duplicate()
	for value: Variant in profile["main_deck"]:
		result.append(StringName(String(value)))
	return result


func _default_unlocked_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for card_id: StringName in Catalog.get_all_card_ids():
		if card_id not in DEFAULT_LOCKED_IDS:
			result.append(card_id)
	return result


func _string_array(values: Array) -> Array:
	var result: Array = []
	for value: Variant in values:
		result.append(String(value))
	return result


func _occupied_library(values: Array) -> Array:
	var result: Array = []
	for value: Variant in values:
		var text_value: String = String(value)
		if not text_value.is_empty():
			result.append(text_value)
	return result


func _padded_library(occupied_values: Array) -> Array:
	var result: Array = occupied_values.duplicate()
	if result.size() > LIBRARY_CAPACITY:
		result.resize(LIBRARY_CAPACITY)
	while result.size() < LIBRARY_CAPACITY:
		result.append("")
	return result
