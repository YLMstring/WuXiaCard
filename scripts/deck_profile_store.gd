class_name DeckProfileStore
extends RefCounted

const Catalog = preload("res://scripts/card_catalog.gd")
const Sects = preload("res://scripts/sect_catalog.gd")
const Enemies = preload("res://scripts/enemy_catalog.gd")

const SCHEMA_VERSION: int = 6
const MAIN_DECK_CAPACITY: int = 5
const LIBRARY_CAPACITY: int = 1000
const MAX_CHARACTER_LEVEL: int = 15
const DEFAULT_SAVE_PATH: String = "user://wuxia_deck_profile.json"
const REWARD_VICTORY: StringName = &"victory"
const REWARD_DEFEAT: StringName = &"defeat"
const DEFAULT_UNLOCKED_SECT_IDS: Array[StringName] = [
	&"xuanyue_jianzong",
]
const DEFAULT_MAIN_DECK_IDS: Array[StringName] = [
	&"CangSongYingKe2",
	&"gate_general",
	&"meng_huo",
	&"YouFenLaiYi",
	&"fa_zheng",
]
const DEFAULT_LOCKED_IDS: Array[StringName] = [
	&"CangSongYingKe1",
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
		"run_active": false,
		"selected_sect_id": "",
		"level": 0,
		"current_enemy_id": "",
		"remembered_enemy_glyphs": [],
		"pending_reward_card_ids": [],
		"unlocked_sect_ids": _string_array(DEFAULT_UNLOCKED_SECT_IDS),
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
	var run_active_value: Variant = profile.get("run_active", null)
	var selected_sect_value: Variant = profile.get("selected_sect_id", null)
	var level_value: Variant = profile.get("level", null)
	var enemy_value: Variant = profile.get("current_enemy_id", null)
	var remembered_glyphs_value: Variant = profile.get("remembered_enemy_glyphs", null)
	var pending_rewards_value: Variant = profile.get("pending_reward_card_ids", null)
	if (
		typeof(run_active_value) != TYPE_BOOL
		or typeof(selected_sect_value) != TYPE_STRING
		or typeof(level_value) not in [TYPE_INT, TYPE_FLOAT]
		or typeof(enemy_value) != TYPE_STRING
		or typeof(remembered_glyphs_value) != TYPE_ARRAY
		or typeof(pending_rewards_value) != TYPE_ARRAY
	):
		return false
	var run_active: bool = bool(run_active_value)
	var selected_sect_id := StringName(String(selected_sect_value))
	var level: int = int(level_value)
	if float(level_value) != float(level):
		return false
	var current_enemy_id := StringName(String(enemy_value))
	var unlocked_sects_value: Variant = profile.get("unlocked_sect_ids", null)
	var unlocked_value: Variant = profile.get("unlocked_card_ids", null)
	var deck_value: Variant = profile.get("main_deck", null)
	var library_value: Variant = profile.get("library_slots", null)
	if (
		typeof(unlocked_sects_value) != TYPE_ARRAY
		or typeof(unlocked_value) != TYPE_ARRAY
		or typeof(deck_value) != TYPE_ARRAY
		or typeof(library_value) != TYPE_ARRAY
	):
		return false
	var sect_catalog_ids: Array[StringName] = Sects.get_all_sect_ids()
	var unlocked_sect_set: Dictionary = {}
	for value: Variant in unlocked_sects_value as Array:
		var sect_id := StringName(String(value))
		if sect_id == &"" or sect_id not in sect_catalog_ids or unlocked_sect_set.has(sect_id):
			return false
		unlocked_sect_set[sect_id] = true
	for default_sect_id: StringName in DEFAULT_UNLOCKED_SECT_IDS:
		if not unlocked_sect_set.has(default_sect_id):
			return false
	if run_active:
		if selected_sect_id == &"" or not unlocked_sect_set.has(selected_sect_id):
			return false
		if level < 1 or level > MAX_CHARACTER_LEVEL or not Enemies.has_enemy(current_enemy_id):
			return false
		if int(Enemies.get_definition(current_enemy_id).get("level", -1)) != level:
			return false
	elif (
		selected_sect_id != &""
		or level != 0
		or current_enemy_id != &""
		or not (remembered_glyphs_value as Array).is_empty()
		or not (pending_rewards_value as Array).is_empty()
	):
		return false
	var valid_enemy_glyphs: Dictionary = _enemy_glyph_set(current_enemy_id)
	var observed_glyphs: Dictionary = {}
	for value: Variant in remembered_glyphs_value as Array:
		if typeof(value) != TYPE_STRING:
			return false
		var glyph: String = String(value)
		if glyph.is_empty() or observed_glyphs.has(glyph) or not valid_enemy_glyphs.has(glyph):
			return false
		observed_glyphs[glyph] = true
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
	var observed_rewards: Dictionary = {}
	var pending_rewards: Array = pending_rewards_value as Array
	if pending_rewards.size() > 3:
		return false
	for value: Variant in pending_rewards:
		if typeof(value) != TYPE_STRING:
			return false
		var reward_id := StringName(String(value))
		if (
			not run_active
			or reward_id == &""
			or reward_id not in catalog_ids
			or unlocked_set.has(reward_id)
			or observed_rewards.has(reward_id)
		):
			return false
		observed_rewards[reward_id] = true
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
	var unlocked_sects: Array[StringName] = _repair_unlocked_sect_ids(
		profile.get("unlocked_sect_ids", [])
	)
	var run_active: bool = false
	var selected_sect_id: StringName = &""
	var level: int = 0
	var current_enemy_id: StringName = &""
	var remembered_enemy_glyphs: Array[String] = []
	var pending_reward_card_ids: Array[StringName] = []
	var schema_version: int = int(profile.get("schema_version", -1))
	if schema_version >= 4:
		var raw_run_active: Variant = profile.get("run_active", false)
		var raw_selected_sect: Variant = profile.get("selected_sect_id", "")
		if typeof(raw_run_active) == TYPE_BOOL and bool(raw_run_active):
			var candidate_sect := StringName(String(raw_selected_sect))
			if candidate_sect in unlocked_sects:
				run_active = true
				selected_sect_id = candidate_sect
				var candidate_level: int = clampi(
					int(profile.get("level", 1)),
					1,
					MAX_CHARACTER_LEVEL
				)
				var candidate_enemy := StringName(String(profile.get("current_enemy_id", "")))
				if (
					Enemies.has_enemy(candidate_enemy)
					and int(Enemies.get_definition(candidate_enemy).get("level", -1))
					== candidate_level
				):
					level = candidate_level
					current_enemy_id = candidate_enemy
				else:
					level = 1
					current_enemy_id = Enemies.get_enemy_ids_for_level(1)[0]
				if schema_version >= 5:
					var valid_glyphs: Dictionary = _enemy_glyph_set(current_enemy_id)
					var raw_memories: Variant = profile.get("remembered_enemy_glyphs", [])
					if typeof(raw_memories) == TYPE_ARRAY:
						for value: Variant in raw_memories as Array:
							if typeof(value) != TYPE_STRING:
								continue
							var glyph: String = String(value)
							if (
								not glyph.is_empty()
								and valid_glyphs.has(glyph)
								and glyph not in remembered_enemy_glyphs
							):
								remembered_enemy_glyphs.append(glyph)
	elif schema_version >= 3:
		var legacy_run_active: Variant = profile.get("run_active", false)
		var legacy_selected_sect: Variant = profile.get("selected_sect_id", "")
		if typeof(legacy_run_active) == TYPE_BOOL and bool(legacy_run_active):
			var legacy_sect := StringName(String(legacy_selected_sect))
			if legacy_sect in unlocked_sects:
				run_active = true
				selected_sect_id = legacy_sect
				level = 1
				current_enemy_id = Enemies.get_enemy_ids_for_level(1)[0]
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
	if run_active and schema_version >= SCHEMA_VERSION:
		var raw_pending_rewards: Variant = profile.get("pending_reward_card_ids", [])
		if typeof(raw_pending_rewards) == TYPE_ARRAY:
			for value: Variant in raw_pending_rewards as Array:
				var card_id := StringName(String(value))
				if (
					card_id != &""
					and card_id in catalog_ids
					and card_id not in unlocked
					and card_id not in pending_reward_card_ids
					and pending_reward_card_ids.size() < 3
				):
					pending_reward_card_ids.append(card_id)

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
		"run_active": run_active,
		"selected_sect_id": String(selected_sect_id),
		"level": level,
		"current_enemy_id": String(current_enemy_id),
		"remembered_enemy_glyphs": remembered_enemy_glyphs,
		"pending_reward_card_ids": _string_array(pending_reward_card_ids),
		"unlocked_sect_ids": _string_array(unlocked_sects),
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


func unlock_cards_and_save(profile: Dictionary, ordered_card_ids: Array) -> Dictionary:
	var unchanged: Dictionary = profile.duplicate(true)
	if not is_profile_valid(profile):
		return {"ok": false, "profile": unchanged, "added_ids": []}
	var catalog_ids: Array[StringName] = Catalog.get_all_card_ids()
	var already_unlocked: Array[StringName] = get_unlocked_ids(profile)
	var additions: Array[StringName] = []
	for value: Variant in ordered_card_ids:
		var card_id := StringName(String(value))
		if (
			card_id != &""
			and card_id in catalog_ids
			and card_id not in already_unlocked
			and card_id not in additions
		):
			additions.append(card_id)
	if additions.is_empty():
		return {"ok": true, "profile": unchanged, "added_ids": additions}
	var occupied: Array = _occupied_library(profile["library_slots"])
	if occupied.size() + additions.size() > LIBRARY_CAPACITY:
		return {"ok": false, "profile": unchanged, "added_ids": []}

	var candidate: Dictionary = profile.duplicate(true)
	var combined_library: Array = _string_array(additions)
	combined_library.append_array(occupied)
	candidate["library_slots"] = _padded_library(combined_library)
	var combined_unlocked: Array = _string_array(additions)
	combined_unlocked.append_array((profile["unlocked_card_ids"] as Array).duplicate())
	candidate["unlocked_card_ids"] = combined_unlocked
	if not is_profile_valid(candidate) or not save_profile(candidate):
		return {"ok": false, "profile": unchanged, "added_ids": []}
	return {"ok": true, "profile": candidate, "added_ids": additions}


func begin_run_and_save(
	profile: Dictionary,
	sect_id: StringName,
	ordered_card_ids: Array,
	enemy_id_override: StringName = &""
) -> Dictionary:
	var unchanged: Dictionary = profile.duplicate(true)
	if (
		not is_profile_valid(profile)
		or bool(profile["run_active"])
		or sect_id == &""
		or sect_id not in get_unlocked_sect_ids(profile)
	):
		return {"ok": false, "profile": unchanged, "added_ids": []}
	var additions: Array[StringName] = _collect_unlock_additions(profile, ordered_card_ids)
	var occupied: Array = _occupied_library(profile["library_slots"])
	if occupied.size() + additions.size() > LIBRARY_CAPACITY:
		return {"ok": false, "profile": unchanged, "added_ids": []}
	var candidate: Dictionary = profile.duplicate(true)
	var enemy_id: StringName = _choose_enemy_id(1, enemy_id_override)
	if enemy_id == &"":
		return {"ok": false, "profile": unchanged, "added_ids": []}
	if not additions.is_empty():
		var combined_library: Array = _string_array(additions)
		combined_library.append_array(occupied)
		candidate["library_slots"] = _padded_library(combined_library)
		var combined_unlocked: Array = _string_array(additions)
		combined_unlocked.append_array((profile["unlocked_card_ids"] as Array).duplicate())
		candidate["unlocked_card_ids"] = combined_unlocked
	candidate["run_active"] = true
	candidate["selected_sect_id"] = String(sect_id)
	candidate["level"] = 1
	candidate["current_enemy_id"] = String(enemy_id)
	candidate["remembered_enemy_glyphs"] = []
	candidate["pending_reward_card_ids"] = []
	if not is_profile_valid(candidate) or not save_profile(candidate):
		return {"ok": false, "profile": unchanged, "added_ids": []}
	return {"ok": true, "profile": candidate, "added_ids": additions}


func reset_run_and_save(profile: Dictionary) -> Dictionary:
	var unchanged: Dictionary = profile.duplicate(true)
	if not is_profile_valid(profile):
		return {"ok": false, "profile": unchanged}
	var unlocked_ids: Array[StringName] = get_unlocked_ids(profile)
	for card_id: StringName in DEFAULT_MAIN_DECK_IDS:
		if card_id not in unlocked_ids:
			return {"ok": false, "profile": unchanged}
	var library_order: Array[StringName] = []
	for value: Variant in profile["library_slots"]:
		var card_id := StringName(String(value))
		if card_id != &"" and card_id not in DEFAULT_MAIN_DECK_IDS and card_id not in library_order:
			library_order.append(card_id)
	for value: Variant in profile["main_deck"]:
		var card_id := StringName(String(value))
		if card_id not in DEFAULT_MAIN_DECK_IDS and card_id not in library_order:
			library_order.append(card_id)
	for card_id: StringName in unlocked_ids:
		if card_id not in DEFAULT_MAIN_DECK_IDS and card_id not in library_order:
			library_order.append(card_id)
	var candidate: Dictionary = profile.duplicate(true)
	candidate["run_active"] = false
	candidate["selected_sect_id"] = ""
	candidate["level"] = 0
	candidate["current_enemy_id"] = ""
	candidate["remembered_enemy_glyphs"] = []
	candidate["pending_reward_card_ids"] = []
	candidate["main_deck"] = _string_array(DEFAULT_MAIN_DECK_IDS)
	candidate["library_slots"] = _padded_library(_string_array(library_order))
	if not is_profile_valid(candidate) or not save_profile(candidate):
		return {"ok": false, "profile": unchanged}
	return {"ok": true, "profile": candidate}


func reset_all_progress_and_save(profile: Dictionary) -> Dictionary:
	var unchanged: Dictionary = profile.duplicate(true)
	if not is_profile_valid(profile):
		return {"ok": false, "profile": unchanged}
	var candidate: Dictionary = create_default_profile()
	if not save_profile(candidate):
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


func get_unlocked_sect_ids(profile: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	var raw: Variant = profile.get("unlocked_sect_ids", [])
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


func is_run_active(profile: Dictionary) -> bool:
	return is_profile_valid(profile) and bool(profile["run_active"])


func get_selected_sect_id(profile: Dictionary) -> StringName:
	if not is_profile_valid(profile):
		return &""
	return StringName(String(profile["selected_sect_id"]))


func get_character_level(profile: Dictionary) -> int:
	if not is_profile_valid(profile):
		return 0
	return int(profile["level"])


func get_character_tier(profile: Dictionary) -> int:
	return tier_for_level(get_character_level(profile))


func get_current_enemy_id(profile: Dictionary) -> StringName:
	if not is_profile_valid(profile):
		return &""
	return StringName(String(profile["current_enemy_id"]))


func get_remembered_enemy_glyphs(profile: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if not is_profile_valid(profile):
		return result
	for value: Variant in profile["remembered_enemy_glyphs"]:
		result.append(String(value))
	return result


func remember_enemy_glyph_and_save(profile: Dictionary, glyph: String) -> Dictionary:
	var unchanged: Dictionary = profile.duplicate(true)
	if not is_profile_valid(profile) or not is_run_active(profile) or glyph.is_empty():
		return {"ok": false, "profile": unchanged}
	if not _enemy_glyph_set(get_current_enemy_id(profile)).has(glyph):
		return {"ok": false, "profile": unchanged}
	if glyph in get_remembered_enemy_glyphs(profile):
		return {"ok": true, "profile": unchanged}
	var candidate: Dictionary = profile.duplicate(true)
	(candidate["remembered_enemy_glyphs"] as Array).append(glyph)
	if not is_profile_valid(candidate) or not save_profile(candidate):
		return {"ok": false, "profile": unchanged}
	return {"ok": true, "profile": candidate}


func get_pending_reward_ids(profile: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	if not is_profile_valid(profile):
		return result
	for value: Variant in profile["pending_reward_card_ids"]:
		result.append(StringName(String(value)))
	return result


func create_reward_offer_and_save(
	profile: Dictionary,
	outcome: StringName,
	rng: RandomNumberGenerator = null
) -> Dictionary:
	var unchanged: Dictionary = profile.duplicate(true)
	if (
		not is_profile_valid(profile)
		or not is_run_active(profile)
		or outcome not in [REWARD_VICTORY, REWARD_DEFEAT]
	):
		return {"ok": false, "offered": false, "profile": unchanged, "reward_ids": []}
	var existing: Array[StringName] = get_pending_reward_ids(profile)
	if not existing.is_empty():
		return {
			"ok": true,
			"offered": true,
			"profile": unchanged,
			"reward_ids": existing,
		}
	var player_tier: int = get_character_tier(profile)
	var unlocked: Array[StringName] = get_unlocked_ids(profile)
	var eligible: Array[StringName] = []
	for card_id: StringName in Catalog.get_all_card_ids():
		if card_id in unlocked:
			continue
		var card_tier: int = int(Catalog.get_definition(card_id).get("tier", 0))
		var qualifies: bool = card_tier == player_tier
		if outcome == REWARD_DEFEAT:
			qualifies = (
				card_tier == 1
				if player_tier <= 1
				else card_tier >= 1 and card_tier < player_tier
			)
		if qualifies:
			eligible.append(card_id)
	if eligible.is_empty():
		return {"ok": true, "offered": false, "profile": unchanged, "reward_ids": []}
	var picker: RandomNumberGenerator = rng
	if picker == null:
		picker = RandomNumberGenerator.new()
		picker.randomize()
	_shuffle_string_names(eligible, picker)
	var reward_ids: Array[StringName] = []
	for index: int in range(mini(3, eligible.size())):
		reward_ids.append(eligible[index])
	var candidate: Dictionary = profile.duplicate(true)
	candidate["pending_reward_card_ids"] = _string_array(reward_ids)
	if not is_profile_valid(candidate) or not save_profile(candidate):
		return {"ok": false, "offered": false, "profile": unchanged, "reward_ids": []}
	return {
		"ok": true,
		"offered": true,
		"profile": candidate,
		"reward_ids": reward_ids,
	}


func claim_pending_reward_and_save(profile: Dictionary, card_id: StringName) -> Dictionary:
	var unchanged: Dictionary = profile.duplicate(true)
	if (
		not is_profile_valid(profile)
		or not is_run_active(profile)
		or card_id not in get_pending_reward_ids(profile)
		or card_id in get_unlocked_ids(profile)
	):
		return {"ok": false, "profile": unchanged}
	var occupied: Array = _occupied_library(profile["library_slots"])
	if occupied.size() >= LIBRARY_CAPACITY:
		return {"ok": false, "profile": unchanged}
	var candidate: Dictionary = profile.duplicate(true)
	occupied.push_front(String(card_id))
	candidate["library_slots"] = _padded_library(occupied)
	(candidate["unlocked_card_ids"] as Array).push_front(String(card_id))
	candidate["pending_reward_card_ids"] = []
	if not is_profile_valid(candidate) or not save_profile(candidate):
		return {"ok": false, "profile": unchanged}
	return {"ok": true, "profile": candidate}


func advance_after_victory_and_save(
	profile: Dictionary,
	enemy_id_override: StringName = &""
) -> Dictionary:
	var unchanged: Dictionary = profile.duplicate(true)
	if (
		not is_profile_valid(profile)
		or not is_run_active(profile)
		or not get_pending_reward_ids(profile).is_empty()
	):
		return {"ok": false, "advanced": false, "profile": unchanged}
	var current_level: int = get_character_level(profile)
	if current_level >= MAX_CHARACTER_LEVEL:
		return {"ok": true, "advanced": false, "profile": unchanged}
	var next_level: int = current_level + 1
	var next_enemy_id: StringName = _choose_enemy_id(next_level, enemy_id_override)
	if next_enemy_id == &"":
		return {"ok": false, "advanced": false, "profile": unchanged}
	var candidate: Dictionary = profile.duplicate(true)
	candidate["level"] = next_level
	candidate["current_enemy_id"] = String(next_enemy_id)
	candidate["remembered_enemy_glyphs"] = []
	if not is_profile_valid(candidate) or not save_profile(candidate):
		return {"ok": false, "advanced": false, "profile": unchanged}
	return {"ok": true, "advanced": true, "profile": candidate}


static func tier_for_level(level: int) -> int:
	if level >= 15:
		return 6
	if level >= 11:
		return 5
	if level >= 8:
		return 4
	if level >= 5:
		return 3
	if level >= 2:
		return 2
	return 1


func _default_unlocked_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for card_id: StringName in Catalog.get_all_card_ids():
		if card_id not in DEFAULT_LOCKED_IDS:
			result.append(card_id)
	return result


func _collect_unlock_additions(profile: Dictionary, ordered_card_ids: Array) -> Array[StringName]:
	var catalog_ids: Array[StringName] = Catalog.get_all_card_ids()
	var already_unlocked: Array[StringName] = get_unlocked_ids(profile)
	var additions: Array[StringName] = []
	for value: Variant in ordered_card_ids:
		var card_id := StringName(String(value))
		if (
			card_id != &""
			and card_id in catalog_ids
			and card_id not in already_unlocked
			and card_id not in additions
		):
			additions.append(card_id)
	return additions


func _choose_enemy_id(level: int, enemy_id_override: StringName) -> StringName:
	if enemy_id_override != &"":
		if (
			Enemies.has_enemy(enemy_id_override)
			and int(Enemies.get_definition(enemy_id_override).get("level", -1)) == level
		):
			return enemy_id_override
		return &""
	return Enemies.pick_random_enemy_id(level)


static func _shuffle_string_names(
	values: Array[StringName],
	rng: RandomNumberGenerator
) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var temporary: StringName = values[index]
		values[index] = values[swap_index]
		values[swap_index] = temporary


static func _enemy_glyph_set(enemy_id: StringName) -> Dictionary:
	var result: Dictionary = {}
	if enemy_id == &"" or not Enemies.has_enemy(enemy_id):
		return result
	var enemy: Dictionary = Enemies.get_definition(enemy_id)
	for value: Variant in enemy.get("deck", []):
		var card_id := StringName(String(value))
		if not Catalog.has_card(card_id):
			continue
		var glyph: String = String(Catalog.get_definition(card_id).get("glyph", ""))
		if not glyph.is_empty():
			result[glyph] = true
	return result


func _repair_unlocked_sect_ids(raw_value: Variant) -> Array[StringName]:
	var result: Array[StringName] = DEFAULT_UNLOCKED_SECT_IDS.duplicate()
	if typeof(raw_value) != TYPE_ARRAY:
		return result
	var catalog_ids: Array[StringName] = Sects.get_all_sect_ids()
	for value: Variant in raw_value as Array:
		var sect_id := StringName(String(value))
		if sect_id != &"" and sect_id in catalog_ids and sect_id not in result:
			result.append(sect_id)
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
