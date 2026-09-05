class_name DeckProfileStore
extends RefCounted

const Catalog = preload("res://scripts/card_catalog.gd")
const Sects = preload("res://scripts/sect_catalog.gd")
const Enemies = preload("res://scripts/enemy_catalog.gd")
const DeckRules = preload("res://scripts/deck_rules.gd")
const Difficulty = preload("res://scripts/difficulty_rules.gd")

const SCHEMA_VERSION: int = 11
const COMPLETED_RUN_HISTORY_SCHEMA_VERSION: int = 7
const MASTERY_SCHEMA_VERSION: int = 8
const GUARANTEED_REWARD_HISTORY_SCHEMA_VERSION: int = 9
const DIFFICULTY_SCHEMA_VERSION: int = 10
const DIFFICULTY_BEST_SCORE_SCHEMA_VERSION: int = 11
const MAIN_DECK_CAPACITY: int = 5
const LIBRARY_CAPACITY: int = 1000
const MAX_CHARACTER_LEVEL: int = 15
const MAX_DIFFICULTY: int = 9
const LEGACY_UNLOCKED_DIFFICULTY: int = 2
const DEFAULT_VICTORIES_REQUIRED: int = 15
const ENDING_SCORE_POOL: int = 15000
const LOW_DIFFICULTY_SCORE_CAP: int = 500
const DEFAULT_SAVE_PATH: String = "user://wuxia_deck_profile.json"
const REWARD_VICTORY: StringName = &"victory"
const REWARD_DEFEAT: StringName = &"defeat"
const DEFAULT_UNLOCKED_SECT_IDS: Array[StringName] = [
	&"HuaShanPai",
]
const DEFAULT_MAIN_DECK_IDS: Array[StringName] = [
	&"TaiZuChangQuan",
	&"TuNaShu1",
]
const TESTING_MAIN_DECK_IDS: Array[StringName] = [
	&"CangSongYingKe2",
	&"LeiZHenJian1",
	&"KuiHua1",
	&"YouFenLaiYi2",
	&"TuNaShu2",
]
const DEFAULT_LOCKED_IDS: Array[StringName] = [
	&"CangSongYingKe1",
	&"TaiShan18Pan1",
	&"WuDaFuJian1",
	&"QiXinLuoChangKong2",
	&"TianChangZhang3",
	&"HenShanJianZhen2",
	&"MianLiCangZhen2",
	&"YunWu13Shi2",
	&"YiJianLuo9Yan1",
	&"TianZhuYunQi2",
	&"JianFaQinYin1",
	&"YanHuiZhuRong3",
	&"WanYueChaoZong1",
	&"DaSongYangZhang1",
	&"YinYangZhang3",
	&"HanBinZhenQi3",
	&"TianWaiYuLong2",
]
const TIER_LEAD_UNLOCK_IDS: Dictionary = {
	2: [&"TuNaShu2"],
	3: [&"TuNaShu3"],
}

var save_path: String


func _init(new_save_path: String = DEFAULT_SAVE_PATH) -> void:
	save_path = new_save_path


func create_default_profile() -> Dictionary:
	var unlocked_ids: Array[StringName] = DEFAULT_MAIN_DECK_IDS.duplicate()
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
		"max_unlocked_difficulty": 0,
		"last_selected_difficulty": 0,
		"run_difficulty": 0,
		"level": 0,
		"current_enemy_id": "",
		"remembered_enemy_glyphs": [],
		"pending_reward_card_ids": [],
		"shown_guaranteed_reward_card_ids": [],
		"effective_duel_count": 0,
		"defeated_enemy_ids": [],
		"best_scores_by_sect": {},
		"mastered_card_ids": [],
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


func load_profile_read_only() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return create_default_profile()
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return create_default_profile()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return create_default_profile()
	var repaired: Dictionary = repair_profile(parsed as Dictionary)
	return repaired if is_profile_valid(repaired) else create_default_profile()


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
	var max_difficulty_value: Variant = profile.get("max_unlocked_difficulty", null)
	var last_difficulty_value: Variant = profile.get("last_selected_difficulty", null)
	var run_difficulty_value: Variant = profile.get("run_difficulty", null)
	var level_value: Variant = profile.get("level", null)
	var enemy_value: Variant = profile.get("current_enemy_id", null)
	var remembered_glyphs_value: Variant = profile.get("remembered_enemy_glyphs", null)
	var pending_rewards_value: Variant = profile.get("pending_reward_card_ids", null)
	var shown_guaranteed_rewards_value: Variant = profile.get(
		"shown_guaranteed_reward_card_ids",
		null
	)
	var effective_duels_value: Variant = profile.get("effective_duel_count", null)
	var defeated_enemies_value: Variant = profile.get("defeated_enemy_ids", null)
	var best_scores_value: Variant = profile.get("best_scores_by_sect", null)
	var mastered_cards_value: Variant = profile.get("mastered_card_ids", null)
	if (
		typeof(run_active_value) != TYPE_BOOL
		or typeof(selected_sect_value) != TYPE_STRING
		or typeof(max_difficulty_value) != TYPE_INT
		or typeof(last_difficulty_value) != TYPE_INT
		or typeof(run_difficulty_value) != TYPE_INT
		or typeof(level_value) not in [TYPE_INT, TYPE_FLOAT]
		or typeof(enemy_value) != TYPE_STRING
		or typeof(remembered_glyphs_value) != TYPE_ARRAY
		or typeof(pending_rewards_value) != TYPE_ARRAY
		or typeof(shown_guaranteed_rewards_value) != TYPE_ARRAY
		or typeof(effective_duels_value) not in [TYPE_INT, TYPE_FLOAT]
		or typeof(defeated_enemies_value) != TYPE_ARRAY
		or typeof(best_scores_value) != TYPE_DICTIONARY
		or typeof(mastered_cards_value) != TYPE_ARRAY
	):
		return false
	var run_active: bool = bool(run_active_value)
	var selected_sect_id := StringName(String(selected_sect_value))
	var max_unlocked_difficulty: int = int(max_difficulty_value)
	var last_selected_difficulty: int = int(last_difficulty_value)
	var run_difficulty: int = int(run_difficulty_value)
	if (
		max_unlocked_difficulty < 0
		or max_unlocked_difficulty > MAX_DIFFICULTY
		or last_selected_difficulty < 0
		or last_selected_difficulty > max_unlocked_difficulty
		or run_difficulty < 0
		or run_difficulty > max_unlocked_difficulty
		or (not run_active and run_difficulty != 0)
	):
		return false
	var level: int = int(level_value)
	if float(level_value) != float(level):
		return false
	var current_enemy_id := StringName(String(enemy_value))
	var effective_duel_count: int = int(effective_duels_value)
	if (
		float(effective_duels_value) != float(effective_duel_count)
		or effective_duel_count < 0
	):
		return false
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
		or not (shown_guaranteed_rewards_value as Array).is_empty()
		or effective_duel_count != 0
		or not (defeated_enemies_value as Array).is_empty()
	):
		return false
	var defeated_enemy_count: int = 0
	for value: Variant in defeated_enemies_value as Array:
		if typeof(value) != TYPE_STRING:
			return false
		var defeated_enemy_id := StringName(String(value))
		if not Enemies.has_enemy(defeated_enemy_id):
			return false
		defeated_enemy_count += 1
	if defeated_enemy_count > effective_duel_count:
		return false
	for raw_sect_id: Variant in (best_scores_value as Dictionary).keys():
		var sect_id := StringName(String(raw_sect_id))
		var difficulty_scores_value: Variant = (
			(best_scores_value as Dictionary)[raw_sect_id]
		)
		if (
			typeof(raw_sect_id) != TYPE_STRING
			or not Sects.has_sect(sect_id)
			or typeof(difficulty_scores_value) != TYPE_DICTIONARY
		):
			return false
		for raw_difficulty: Variant in (difficulty_scores_value as Dictionary).keys():
			if typeof(raw_difficulty) != TYPE_STRING:
				return false
			var difficulty_text: String = String(raw_difficulty)
			if not _is_valid_difficulty_score_key(difficulty_text):
				return false
			var difficulty: int = int(difficulty_text)
			var score_value: Variant = (
				(difficulty_scores_value as Dictionary)[raw_difficulty]
			)
			if (
				typeof(score_value) not in [TYPE_INT, TYPE_FLOAT]
				or float(score_value) != float(int(score_value))
				or int(score_value) < 0
				or (
					difficulty <= 1
					and int(score_value) > LOW_DIFFICULTY_SCORE_CAP
				)
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
	if library.size() != LIBRARY_CAPACITY:
		return false
	var catalog_ids: Array[StringName] = Catalog.get_all_card_ids()
	var shown_guaranteed_set: Dictionary = {}
	for value: Variant in shown_guaranteed_rewards_value as Array:
		if typeof(value) != TYPE_STRING:
			return false
		var shown_card_id := StringName(String(value))
		if (
			not run_active
			or shown_card_id == &""
			or shown_card_id not in catalog_ids
			or shown_guaranteed_set.has(shown_card_id)
			or not Catalog.get_definition(shown_card_id).has("guaranteed_defeat_reward")
		):
			return false
		shown_guaranteed_set[shown_card_id] = true
	var mastered_set: Dictionary = {}
	for value: Variant in mastered_cards_value as Array:
		if typeof(value) != TYPE_STRING:
			return false
		var mastered_id := StringName(String(value))
		if mastered_id == &"" or mastered_id not in catalog_ids or mastered_set.has(mastered_id):
			return false
		mastered_set[mastered_id] = true
	var unlocked_set: Dictionary = {}
	for value: Variant in unlocked:
		var card_id := StringName(String(value))
		if card_id == &"" or card_id not in catalog_ids or unlocked_set.has(card_id):
			return false
		unlocked_set[card_id] = true
	var deck_size_valid: bool = (
		deck.size() == MAIN_DECK_CAPACITY
		if run_active
		else deck.size() >= mini(DEFAULT_MAIN_DECK_IDS.size(), unlocked_set.size())
		and deck.size() <= mini(MAIN_DECK_CAPACITY, unlocked_set.size())
	)
	if not deck_size_valid or not DeckRules.has_unique_glyphs(deck):
		return false
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
	var max_unlocked_difficulty: int = 0
	var last_selected_difficulty: int = 0
	var run_difficulty: int = 0
	var level: int = 0
	var current_enemy_id: StringName = &""
	var remembered_enemy_glyphs: Array[String] = []
	var pending_reward_card_ids: Array[StringName] = []
	var shown_guaranteed_reward_card_ids: Array[StringName] = []
	var effective_duel_count: int = 0
	var defeated_enemy_ids: Array[StringName] = []
	var best_scores_by_sect: Dictionary = {}
	var mastered_card_ids: Array[StringName] = []
	var schema_version: int = int(profile.get("schema_version", -1))
	var legacy_active_run: bool = (
		schema_version < COMPLETED_RUN_HISTORY_SCHEMA_VERSION
		and typeof(profile.get("run_active", false)) == TYPE_BOOL
		and bool(profile.get("run_active", false))
	)
	if schema_version >= COMPLETED_RUN_HISTORY_SCHEMA_VERSION:
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
				var raw_effective_duels: Variant = profile.get("effective_duel_count", 0)
				if typeof(raw_effective_duels) in [TYPE_INT, TYPE_FLOAT]:
					var repaired_count: int = maxi(0, int(raw_effective_duels))
					if float(raw_effective_duels) == float(int(raw_effective_duels)):
						effective_duel_count = repaired_count
				var raw_defeated: Variant = profile.get("defeated_enemy_ids", [])
				if typeof(raw_defeated) == TYPE_ARRAY:
					for value: Variant in raw_defeated as Array:
						var defeated_id := StringName(String(value))
						if Enemies.has_enemy(defeated_id):
							defeated_enemy_ids.append(defeated_id)
				if defeated_enemy_ids.size() > effective_duel_count:
					effective_duel_count = defeated_enemy_ids.size()
		best_scores_by_sect = _repair_best_scores_by_sect(
			profile.get("best_scores_by_sect", {}),
			schema_version
		)
	if schema_version < DIFFICULTY_SCHEMA_VERSION:
		max_unlocked_difficulty = LEGACY_UNLOCKED_DIFFICULTY
		last_selected_difficulty = LEGACY_UNLOCKED_DIFFICULTY
		run_difficulty = LEGACY_UNLOCKED_DIFFICULTY if run_active else 0
	else:
		max_unlocked_difficulty = clampi(
			int(profile.get("max_unlocked_difficulty", 0)),
			0,
			MAX_DIFFICULTY
		)
		last_selected_difficulty = clampi(
			int(profile.get("last_selected_difficulty", 0)),
			0,
			max_unlocked_difficulty
		)
		run_difficulty = (
			clampi(
				int(profile.get("run_difficulty", 0)),
				0,
				max_unlocked_difficulty
			)
			if run_active
			else 0
		)
	var catalog_ids: Array[StringName] = Catalog.get_all_card_ids()
	if schema_version >= MASTERY_SCHEMA_VERSION:
		var raw_mastery: Variant = profile.get("mastered_card_ids", [])
		if typeof(raw_mastery) == TYPE_ARRAY:
			for value: Variant in raw_mastery as Array:
				var mastered_id := StringName(String(value))
				if (
					mastered_id != &""
					and mastered_id in catalog_ids
					and mastered_id not in mastered_card_ids
				):
					mastered_card_ids.append(mastered_id)
	var unlocked: Array[StringName] = []
	var raw_unlocked: Variant = profile.get("unlocked_card_ids", null)
	if typeof(raw_unlocked) == TYPE_ARRAY:
		for value: Variant in raw_unlocked:
			var card_id := StringName(String(value))
			if card_id != &"" and card_id in catalog_ids and card_id not in unlocked:
				unlocked.append(card_id)
	else:
		unlocked = _default_unlocked_ids()
	if run_active and schema_version >= COMPLETED_RUN_HISTORY_SCHEMA_VERSION:
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
	if run_active and schema_version >= GUARANTEED_REWARD_HISTORY_SCHEMA_VERSION:
		var raw_shown_guaranteed: Variant = profile.get(
			"shown_guaranteed_reward_card_ids",
			[]
		)
		if typeof(raw_shown_guaranteed) == TYPE_ARRAY:
			for value: Variant in raw_shown_guaranteed as Array:
				var card_id := StringName(String(value))
				if (
					typeof(value) == TYPE_STRING
					and card_id in catalog_ids
					and card_id not in shown_guaranteed_reward_card_ids
					and Catalog.get_definition(card_id).has("guaranteed_defeat_reward")
				):
					shown_guaranteed_reward_card_ids.append(card_id)

	var raw_deck: Variant = profile.get("main_deck", [])
	var raw_library: Variant = profile.get("library_slots", [])
	var repaired_deck_capacity: int = MAIN_DECK_CAPACITY
	if not run_active and typeof(raw_deck) == TYPE_ARRAY:
		repaired_deck_capacity = clampi(
			(raw_deck as Array).size(),
			mini(DEFAULT_MAIN_DECK_IDS.size(), unlocked.size()),
			mini(MAIN_DECK_CAPACITY, unlocked.size())
		)
	var placement: Dictionary = DeckRules.repair_player_placement(
		unlocked,
		raw_deck as Array if typeof(raw_deck) == TYPE_ARRAY else [],
		raw_library as Array if typeof(raw_library) == TYPE_ARRAY else [],
		repaired_deck_capacity,
		LIBRARY_CAPACITY
	)
	if not bool(placement.get("ok", false)):
		return create_default_profile()
	var deck: Array = placement.get("main_deck", [])
	var repaired_library: Array = placement.get("library_cards", [])
	if legacy_active_run:
		var default_placement: Dictionary = _build_default_deck_placement(
			unlocked,
			deck,
			repaired_library
		)
		if bool(default_placement.get("ok", false)):
			deck = default_placement.get("main_deck", deck)
			repaired_library = default_placement.get("library_cards", repaired_library)
	return {
		"schema_version": SCHEMA_VERSION,
		"run_active": run_active,
		"selected_sect_id": String(selected_sect_id),
		"max_unlocked_difficulty": max_unlocked_difficulty,
		"last_selected_difficulty": last_selected_difficulty,
		"run_difficulty": run_difficulty,
		"level": level,
		"current_enemy_id": String(current_enemy_id),
		"remembered_enemy_glyphs": remembered_enemy_glyphs,
		"pending_reward_card_ids": _string_array(pending_reward_card_ids),
		"shown_guaranteed_reward_card_ids": _string_array(
			shown_guaranteed_reward_card_ids
		),
		"effective_duel_count": effective_duel_count,
		"defeated_enemy_ids": _string_array(defeated_enemy_ids),
		"best_scores_by_sect": best_scores_by_sect,
		"mastered_card_ids": _string_array(mastered_card_ids),
		"unlocked_sect_ids": _string_array(unlocked_sects),
		"unlocked_card_ids": _string_array(unlocked),
		"main_deck": _string_array(deck),
		"library_slots": _padded_library(_string_array(repaired_library)),
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
	var exchange: Dictionary = DeckRules.build_player_exchange(
		profile["main_deck"],
		profile["library_slots"],
		library_index,
		deck_index
	)
	if not bool(exchange.get("ok", false)):
		return {"ok": false, "profile": unchanged}
	var candidate: Dictionary = profile.duplicate(true)
	candidate["main_deck"] = (exchange["main_deck"] as Array).duplicate()
	candidate["library_slots"] = (exchange["library_slots"] as Array).duplicate()
	if not is_profile_valid(candidate) or not save_profile(candidate):
		return {"ok": false, "profile": unchanged}
	return {"ok": true, "profile": candidate}


func unlock_and_save(profile: Dictionary, card_id: StringName) -> Dictionary:
	var unchanged: Dictionary = profile.duplicate(true)
	if not is_profile_valid(profile):
		return {"ok": false, "profile": unchanged, "added_ids": []}
	if card_id not in Catalog.get_all_card_ids() or card_id in get_unlocked_ids(profile):
		return {"ok": false, "profile": unchanged, "added_ids": []}
	var expansion: Dictionary = _build_unlock_expansion(profile, [card_id])
	if not bool(expansion.get("ok", false)):
		return {"ok": false, "profile": unchanged, "added_ids": []}
	var candidate: Dictionary = profile.duplicate(true)
	_apply_unlock_expansion(candidate, expansion)
	if not is_profile_valid(candidate) or not save_profile(candidate):
		return {"ok": false, "profile": unchanged, "added_ids": []}
	return {
		"ok": true,
		"profile": candidate,
		"added_ids": expansion.get("added_ids", []),
	}


func unlock_cards_and_save(profile: Dictionary, ordered_card_ids: Array) -> Dictionary:
	var unchanged: Dictionary = profile.duplicate(true)
	if not is_profile_valid(profile):
		return {"ok": false, "profile": unchanged, "added_ids": []}
	var expansion: Dictionary = _build_unlock_expansion(profile, ordered_card_ids)
	if not bool(expansion.get("ok", false)):
		return {"ok": false, "profile": unchanged, "added_ids": []}
	var added_ids: Array = expansion.get("added_ids", []) as Array
	if added_ids.is_empty():
		return {"ok": true, "profile": unchanged, "added_ids": added_ids}
	var candidate: Dictionary = profile.duplicate(true)
	_apply_unlock_expansion(candidate, expansion)
	if not is_profile_valid(candidate) or not save_profile(candidate):
		return {"ok": false, "profile": unchanged, "added_ids": []}
	return {"ok": true, "profile": candidate, "added_ids": added_ids}


func begin_run_and_save(
	profile: Dictionary,
	sect_id: StringName,
	_ordered_card_ids: Array,
	enemy_id_override: StringName = &"",
	rng: RandomNumberGenerator = null,
	allow_owned_starting_cards: bool = false,
	difficulty: int = 0
) -> Dictionary:
	var unchanged: Dictionary = profile.duplicate(true)
	if (
		not is_profile_valid(profile)
		or bool(profile["run_active"])
		or sect_id == &""
		or sect_id not in get_unlocked_sect_ids(profile)
		or difficulty < 0
		or difficulty > get_max_unlocked_difficulty(profile)
	):
		return {"ok": false, "profile": unchanged, "added_ids": []}
	var sect_tier_one_ids: Array[StringName] = _get_card_ids_for_sect_tier(sect_id, 1)
	var random_tier_one_ids: Array[StringName] = _pick_starting_tier_one_ids(
		profile,
		sect_tier_one_ids,
		rng,
		allow_owned_starting_cards
	)
	if random_tier_one_ids.size() != MAIN_DECK_CAPACITY - DEFAULT_MAIN_DECK_IDS.size():
		return {"ok": false, "profile": unchanged, "added_ids": []}
	var requested_unlocks: Array[StringName] = sect_tier_one_ids.duplicate()
	requested_unlocks.append_array(random_tier_one_ids)
	var expansion: Dictionary = _build_unlock_expansion(profile, requested_unlocks)
	if not bool(expansion.get("ok", false)):
		return {"ok": false, "profile": unchanged, "added_ids": []}
	var candidate: Dictionary = profile.duplicate(true)
	var enemy_id: StringName = _choose_enemy_id(1, enemy_id_override)
	if enemy_id == &"":
		return {"ok": false, "profile": unchanged, "added_ids": []}
	_apply_unlock_expansion(candidate, expansion)
	var starting_deck: Array[StringName] = DEFAULT_MAIN_DECK_IDS.duplicate()
	starting_deck.append_array(random_tier_one_ids)
	var starting_placement: Dictionary = _build_exact_deck_placement(
		get_unlocked_ids(candidate),
		starting_deck,
		candidate.get("library_slots", []) as Array
	)
	if not bool(starting_placement.get("ok", false)):
		return {"ok": false, "profile": unchanged, "added_ids": []}
	candidate["main_deck"] = starting_placement.get("main_deck", [])
	candidate["library_slots"] = _padded_library(
		starting_placement.get("library_cards", []) as Array
	)
	candidate["run_active"] = true
	candidate["selected_sect_id"] = String(sect_id)
	candidate["run_difficulty"] = difficulty
	candidate["level"] = 1
	candidate["current_enemy_id"] = String(enemy_id)
	candidate["remembered_enemy_glyphs"] = []
	candidate["pending_reward_card_ids"] = []
	candidate["shown_guaranteed_reward_card_ids"] = []
	candidate["effective_duel_count"] = 0
	candidate["defeated_enemy_ids"] = []
	if not is_profile_valid(candidate) or not save_profile(candidate):
		return {"ok": false, "profile": unchanged, "added_ids": []}
	return {
		"ok": true,
		"profile": candidate,
		"added_ids": expansion.get("added_ids", []),
	}


func reset_run_and_save(profile: Dictionary) -> Dictionary:
	var unchanged: Dictionary = profile.duplicate(true)
	var candidate: Dictionary = _build_run_reset_profile(profile)
	if candidate.is_empty():
		return {"ok": false, "profile": unchanged}
	if not save_profile(candidate):
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


func unlock_all_progression_and_save(profile: Dictionary) -> Dictionary:
	var unchanged: Dictionary = profile.duplicate(true)
	if not is_profile_valid(profile):
		return {"ok": false, "profile": unchanged}
	var candidate: Dictionary = profile.duplicate(true)
	candidate["unlocked_sect_ids"] = _string_array(Sects.get_all_sect_ids())
	candidate["max_unlocked_difficulty"] = MAX_DIFFICULTY
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


func create_testing_profile(profile: Dictionary) -> Dictionary:
	var source: Dictionary = repair_profile(profile)
	var all_ids: Array[StringName] = Catalog.get_all_card_ids()
	var requested_deck: Array[StringName] = get_main_deck_ids(source)
	if requested_deck.size() < MAIN_DECK_CAPACITY:
		requested_deck = TESTING_MAIN_DECK_IDS.duplicate()
	var used_glyphs: Dictionary = {}
	for value: Variant in requested_deck:
		used_glyphs[DeckRules.get_glyph(StringName(String(value)))] = true
	for card_id: StringName in all_ids:
		if requested_deck.size() >= MAIN_DECK_CAPACITY:
			break
		var glyph: String = DeckRules.get_glyph(card_id)
		if glyph.is_empty() or used_glyphs.has(glyph):
			continue
		requested_deck.append(card_id)
		used_glyphs[glyph] = true
	var placement: Dictionary = _build_exact_deck_placement(
		all_ids,
		requested_deck,
		source.get("library_slots", []) as Array
	)
	if not bool(placement.get("ok", false)):
		return {}
	var result: Dictionary = source.duplicate(true)
	result["pending_reward_card_ids"] = []
	result["unlocked_card_ids"] = _string_array(all_ids)
	result["main_deck"] = placement.get("main_deck", [])
	result["library_slots"] = _padded_library(
		placement.get("library_cards", []) as Array
	)
	return result if is_profile_valid(result) else {}


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


func get_max_unlocked_difficulty(profile: Dictionary) -> int:
	if not is_profile_valid(profile):
		return 0
	return int(profile["max_unlocked_difficulty"])


func get_last_selected_difficulty(profile: Dictionary) -> int:
	if not is_profile_valid(profile):
		return 0
	return int(profile["last_selected_difficulty"])


func get_run_difficulty(profile: Dictionary) -> int:
	if not is_profile_valid(profile):
		return 0
	return int(profile["run_difficulty"])


func set_last_selected_difficulty_and_save(
	profile: Dictionary,
	difficulty: int
) -> Dictionary:
	var unchanged: Dictionary = profile.duplicate(true)
	if (
		not is_profile_valid(profile)
		or difficulty < 0
		or difficulty > get_max_unlocked_difficulty(profile)
	):
		return {"ok": false, "profile": unchanged}
	var candidate: Dictionary = profile.duplicate(true)
	candidate["last_selected_difficulty"] = difficulty
	if not is_profile_valid(candidate) or not save_profile(candidate):
		return {"ok": false, "profile": unchanged}
	return {"ok": true, "profile": candidate}


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


func get_effective_duel_count(profile: Dictionary) -> int:
	if not is_profile_valid(profile):
		return 0
	return int(profile["effective_duel_count"])


func get_defeated_enemy_ids(profile: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	if not is_profile_valid(profile):
		return result
	for value: Variant in profile["defeated_enemy_ids"]:
		result.append(StringName(String(value)))
	return result


func get_best_scores_by_sect(profile: Dictionary) -> Dictionary:
	if not is_profile_valid(profile):
		return {}
	return (profile["best_scores_by_sect"] as Dictionary).duplicate(true)


func get_best_score(
	profile: Dictionary,
	sect_id: StringName,
	difficulty: int
) -> int:
	if (
		not is_profile_valid(profile)
		or not Sects.has_sect(sect_id)
		or difficulty < 0
		or difficulty > MAX_DIFFICULTY
	):
		return 0
	var best_scores: Dictionary = profile["best_scores_by_sect"] as Dictionary
	var difficulty_scores_value: Variant = best_scores.get(String(sect_id), {})
	if typeof(difficulty_scores_value) != TYPE_DICTIONARY:
		return 0
	return int((difficulty_scores_value as Dictionary).get(str(difficulty), 0))


func get_mastered_card_ids(profile: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	if not is_profile_valid(profile):
		return result
	for value: Variant in profile["mastered_card_ids"]:
		result.append(StringName(String(value)))
	return result


func is_card_mastered(profile: Dictionary, card_id: StringName) -> bool:
	return card_id in get_mastered_card_ids(profile)


func record_completed_duel_and_save(
	profile: Dictionary,
	outcome: StringName,
	victories_required: int = DEFAULT_VICTORIES_REQUIRED,
	enemy_id_override: StringName = &"",
	mastery_candidate_ids: Array = []
) -> Dictionary:
	var unchanged: Dictionary = profile.duplicate(true)
	var failed: Dictionary = {
		"ok": false,
		"completed": false,
		"advanced": false,
		"profile": unchanged,
		"ending_summary": {},
		"added_ids": [],
	}
	if (
		not is_profile_valid(profile)
		or not is_run_active(profile)
		or not get_pending_reward_ids(profile).is_empty()
		or outcome not in [REWARD_VICTORY, REWARD_DEFEAT]
		or victories_required < 1
		or victories_required > MAX_CHARACTER_LEVEL
	):
		return failed

	var candidate: Dictionary = profile.duplicate(true)
	candidate["effective_duel_count"] = int(candidate["effective_duel_count"]) + 1
	if outcome == REWARD_DEFEAT:
		if not is_profile_valid(candidate) or not save_profile(candidate):
			return failed
		return {
			"ok": true,
			"completed": false,
			"advanced": false,
			"profile": candidate,
			"ending_summary": {},
			"added_ids": [],
		}

	_apply_mastery_candidates(candidate, mastery_candidate_ids)
	var defeated_enemy_id: StringName = get_current_enemy_id(candidate)
	(candidate["defeated_enemy_ids"] as Array).append(String(defeated_enemy_id))
	_unlock_enemy_sect(candidate, defeated_enemy_id)
	var effective_victories_required: int = mini(
		victories_required,
		Difficulty.get_victories_required(get_run_difficulty(candidate))
	)
	if (
		(candidate["defeated_enemy_ids"] as Array).size()
		>= effective_victories_required
	):
		_unlock_next_difficulty(candidate)
		var summary: Dictionary = _build_ending_summary(candidate)
		_record_best_score(candidate, summary)
		var completed_candidate: Dictionary = _build_run_reset_profile(candidate)
		if completed_candidate.is_empty():
			return failed
		if not is_profile_valid(completed_candidate) or not save_profile(completed_candidate):
			return failed
		return {
			"ok": true,
			"completed": true,
			"advanced": false,
			"profile": completed_candidate,
			"ending_summary": summary.duplicate(true),
			"added_ids": [],
		}

	var advancement: Dictionary = _build_victory_advancement(
		candidate,
		enemy_id_override
	)
	if not bool(advancement.get("ok", false)):
		return failed
	candidate = advancement.get("profile", candidate)
	if not is_profile_valid(candidate) or not save_profile(candidate):
		return failed
	return {
		"ok": true,
		"completed": false,
		"advanced": bool(advancement.get("advanced", false)),
		"profile": candidate,
		"ending_summary": {},
		"added_ids": advancement.get("added_ids", []),
	}


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
		var definition: Dictionary = Catalog.get_definition(card_id)
		var card_tier: int = int(definition.get("tier", 0))
		var qualifies: bool = card_tier == player_tier
		if outcome == REWARD_VICTORY:
			var extra_victory_tiers: Array = definition.get(
				"extra_victory_reward_tiers",
				[]
			) as Array
			qualifies = qualifies or player_tier in extra_victory_tiers
		if outcome == REWARD_DEFEAT:
			qualifies = (
				card_tier == 1
				if player_tier <= 1
				else card_tier >= 1 and card_tier < player_tier
			)
		if qualifies:
			eligible.append(card_id)
	var guaranteed_ids: Array[StringName] = []
	if outcome == REWARD_DEFEAT:
		guaranteed_ids = _get_eligible_guaranteed_defeat_reward_ids(
			profile,
			player_tier,
			unlocked
		)
	if eligible.is_empty() and guaranteed_ids.is_empty():
		return {"ok": true, "offered": false, "profile": unchanged, "reward_ids": []}
	var picker: RandomNumberGenerator = rng
	if picker == null:
		picker = RandomNumberGenerator.new()
		picker.randomize()
	_shuffle_string_names(eligible, picker)
	var reward_ids: Array[StringName] = []
	var included_guaranteed_ids: Array[StringName] = []
	for guaranteed_id: StringName in guaranteed_ids:
		if reward_ids.size() >= 3:
			break
		reward_ids.append(guaranteed_id)
		included_guaranteed_ids.append(guaranteed_id)
	for eligible_id: StringName in eligible:
		if reward_ids.size() >= 3:
			break
		if eligible_id not in reward_ids:
			reward_ids.append(eligible_id)
	if not included_guaranteed_ids.is_empty():
		_shuffle_string_names(reward_ids, picker)
	var candidate: Dictionary = profile.duplicate(true)
	candidate["pending_reward_card_ids"] = _string_array(reward_ids)
	var shown_guaranteed: Array = candidate["shown_guaranteed_reward_card_ids"] as Array
	for guaranteed_id: StringName in included_guaranteed_ids:
		if String(guaranteed_id) not in shown_guaranteed:
			shown_guaranteed.append(String(guaranteed_id))
	if not is_profile_valid(candidate) or not save_profile(candidate):
		return {"ok": false, "offered": false, "profile": unchanged, "reward_ids": []}
	return {
		"ok": true,
		"offered": true,
		"profile": candidate,
		"reward_ids": reward_ids,
	}


func _get_eligible_guaranteed_defeat_reward_ids(
	profile: Dictionary,
	player_tier: int,
	unlocked: Array[StringName]
) -> Array[StringName]:
	var unlocked_effect_gates: Dictionary = {}
	for unlocked_id: StringName in unlocked:
		var unlocked_definition: Dictionary = Catalog.get_definition(unlocked_id)
		var effect_gate := StringName(unlocked_definition.get("effect_gate", &""))
		if effect_gate != &"":
			unlocked_effect_gates[effect_gate] = true
	var shown_ids: Array[StringName] = []
	for value: Variant in profile.get("shown_guaranteed_reward_card_ids", []):
		shown_ids.append(StringName(String(value)))
	var result: Array[StringName] = []
	for card_id: StringName in Catalog.get_all_card_ids():
		if card_id in unlocked or card_id in shown_ids:
			continue
		var definition: Dictionary = Catalog.get_definition(card_id)
		var declaration_value: Variant = definition.get(
			"guaranteed_defeat_reward",
			null
		)
		if typeof(declaration_value) != TYPE_DICTIONARY:
			continue
		var declaration: Dictionary = declaration_value as Dictionary
		var minimum_tier: int = int(declaration.get("min_character_tier", 0))
		var required_gate := StringName(
			declaration.get("requires_unlocked_effect_gate", &"")
		)
		if player_tier >= minimum_tier and unlocked_effect_gates.has(required_gate):
			result.append(card_id)
	return result


func claim_pending_reward_and_save(profile: Dictionary, card_id: StringName) -> Dictionary:
	var unchanged: Dictionary = profile.duplicate(true)
	if (
		not is_profile_valid(profile)
		or not is_run_active(profile)
		or card_id not in get_pending_reward_ids(profile)
		or card_id in get_unlocked_ids(profile)
	):
		return {"ok": false, "profile": unchanged, "added_ids": []}
	var expansion: Dictionary = _build_unlock_expansion(profile, [card_id])
	if not bool(expansion.get("ok", false)):
		return {"ok": false, "profile": unchanged, "added_ids": []}
	var candidate: Dictionary = profile.duplicate(true)
	_apply_unlock_expansion(candidate, expansion)
	candidate["pending_reward_card_ids"] = []
	if not is_profile_valid(candidate) or not save_profile(candidate):
		return {"ok": false, "profile": unchanged, "added_ids": []}
	return {
		"ok": true,
		"profile": candidate,
		"added_ids": expansion.get("added_ids", []),
	}


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
		return {
			"ok": false,
			"advanced": false,
			"profile": unchanged,
			"added_ids": [],
		}
	var advancement: Dictionary = _build_victory_advancement(profile, enemy_id_override)
	if not bool(advancement.get("ok", false)):
		return advancement
	var candidate: Dictionary = advancement.get("profile", unchanged)
	if not is_profile_valid(candidate) or not save_profile(candidate):
		return {
			"ok": false,
			"advanced": false,
			"profile": unchanged,
			"added_ids": [],
		}
	return {
		"ok": true,
		"advanced": bool(advancement.get("advanced", false)),
		"profile": candidate,
		"added_ids": advancement.get("added_ids", []),
	}


static func tier_for_level(level: int) -> int:
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
	return DEFAULT_MAIN_DECK_IDS.duplicate()


func _pick_starting_tier_one_ids(
	profile: Dictionary,
	sect_tier_one_ids: Array[StringName],
	rng: RandomNumberGenerator,
	allow_owned: bool
) -> Array[StringName]:
	var already_unlocked: Array[StringName] = get_unlocked_ids(profile)
	var candidates: Array[StringName] = []
	var owned_fallbacks: Array[StringName] = []
	for card_id: StringName in Catalog.get_all_card_ids():
		var definition: Dictionary = Catalog.get_definition(card_id)
		if (
			int(definition.get("tier", 0)) == 1
			and card_id not in DEFAULT_MAIN_DECK_IDS
			and card_id not in sect_tier_one_ids
		):
			if card_id in already_unlocked:
				owned_fallbacks.append(card_id)
			else:
				candidates.append(card_id)
	var picker: RandomNumberGenerator = rng
	if picker == null:
		picker = RandomNumberGenerator.new()
		picker.randomize()
	_shuffle_string_names(candidates, picker)
	_shuffle_string_names(owned_fallbacks, picker)
	if allow_owned:
		candidates.append_array(owned_fallbacks)
	var result: Array[StringName] = []
	var used_glyphs: Dictionary = {}
	for card_id: StringName in DEFAULT_MAIN_DECK_IDS:
		used_glyphs[DeckRules.get_glyph(card_id)] = true
	for candidate_id: StringName in candidates:
		var glyph: String = DeckRules.get_glyph(candidate_id)
		if glyph.is_empty() or used_glyphs.has(glyph):
			continue
		result.append(candidate_id)
		used_glyphs[glyph] = true
		if result.size() >= MAIN_DECK_CAPACITY - DEFAULT_MAIN_DECK_IDS.size():
			break
	if not allow_owned and result.size() < MAIN_DECK_CAPACITY - DEFAULT_MAIN_DECK_IDS.size():
		for candidate_id: StringName in owned_fallbacks:
			var glyph: String = DeckRules.get_glyph(candidate_id)
			if glyph.is_empty() or used_glyphs.has(glyph):
				continue
			result.append(candidate_id)
			used_glyphs[glyph] = true
			if result.size() >= MAIN_DECK_CAPACITY - DEFAULT_MAIN_DECK_IDS.size():
				break
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


func _build_unlock_expansion(
	profile: Dictionary,
	ordered_card_ids: Array
) -> Dictionary:
	var primary_additions: Array[StringName] = _collect_unlock_additions(
		profile,
		ordered_card_ids
	)
	var already_unlocked: Array[StringName] = get_unlocked_ids(profile)
	var inherited_additions: Array[StringName] = []
	for candidate_id: StringName in Catalog.get_all_card_ids():
		if (
			candidate_id in already_unlocked
			or candidate_id in primary_additions
			or candidate_id in inherited_additions
		):
			continue
		var candidate_definition: Dictionary = Catalog.get_definition(candidate_id)
		for primary_id: StringName in primary_additions:
			var primary_definition: Dictionary = Catalog.get_definition(primary_id)
			if _is_lower_namesake(primary_definition, candidate_definition):
				inherited_additions.append(candidate_id)
				break

	var occupied: Array = _occupied_library(profile["library_slots"])
	var resulting_size: int = (
		primary_additions.size()
		+ occupied.size()
		+ inherited_additions.size()
	)
	if resulting_size > LIBRARY_CAPACITY:
		return {
			"ok": false,
			"primary_ids": [],
			"inherited_ids": [],
			"added_ids": [],
		}

	var library_values: Array = _string_array(primary_additions)
	library_values.append_array(occupied)
	library_values.append_array(_string_array(inherited_additions))
	var unlocked_values: Array = _string_array(primary_additions)
	unlocked_values.append_array((profile["unlocked_card_ids"] as Array).duplicate())
	unlocked_values.append_array(_string_array(inherited_additions))
	var added_ids: Array[StringName] = primary_additions.duplicate()
	added_ids.append_array(inherited_additions)
	return {
		"ok": true,
		"primary_ids": primary_additions,
		"inherited_ids": inherited_additions,
		"added_ids": added_ids,
		"library_slots": _padded_library(library_values),
		"unlocked_card_ids": unlocked_values,
	}


func _apply_unlock_expansion(
	candidate: Dictionary,
	expansion: Dictionary
) -> void:
	candidate["library_slots"] = (
		expansion.get("library_slots", candidate.get("library_slots", [])) as Array
	).duplicate()
	candidate["unlocked_card_ids"] = (
		expansion.get(
			"unlocked_card_ids",
			candidate.get("unlocked_card_ids", [])
		) as Array
	).duplicate()


static func _is_lower_namesake(
	primary_definition: Dictionary,
	candidate_definition: Dictionary
) -> bool:
	var primary_glyph: String = String(primary_definition.get("glyph", ""))
	var primary_sect: String = String(primary_definition.get("sect", ""))
	return (
		not primary_glyph.is_empty()
		and not primary_sect.is_empty()
		and String(candidate_definition.get("glyph", "")) == primary_glyph
		and String(candidate_definition.get("sect", "")) == primary_sect
		and int(candidate_definition.get("tier", 0))
		< int(primary_definition.get("tier", 0))
	)


func _get_selected_sect_card_ids_for_tier(
	profile: Dictionary,
	tier: int
) -> Array[StringName]:
	var sect_id: StringName = get_selected_sect_id(profile)
	return _get_card_ids_for_sect_tier(sect_id, tier)


func _get_card_ids_for_sect_tier(
	sect_id: StringName,
	tier: int
) -> Array[StringName]:
	var result: Array[StringName] = []
	if sect_id == &"" or not Sects.has_sect(sect_id):
		return result
	var sect_glyph: String = String(Sects.get_definition(sect_id).get("glyph", ""))
	for card_id: StringName in Catalog.get_all_card_ids():
		var definition: Dictionary = Catalog.get_definition(card_id)
		if (
			String(definition.get("sect", "")) == sect_glyph
			and int(definition.get("tier", 0)) == tier
		):
			result.append(card_id)
	return result


func _build_exact_deck_placement(
	unlocked_ids: Array[StringName],
	requested_deck: Array[StringName],
	current_library: Array
) -> Dictionary:
	if (
		requested_deck.size() != MAIN_DECK_CAPACITY
		or not DeckRules.has_unique_glyphs(requested_deck)
	):
		return {"ok": false}
	var deck_set: Dictionary = {}
	for card_id: StringName in requested_deck:
		if card_id not in unlocked_ids or deck_set.has(card_id):
			return {"ok": false}
		deck_set[card_id] = true
	var library_cards: Array[StringName] = []
	for value: Variant in current_library:
		var card_id := StringName(String(value))
		if (
			card_id != &""
			and card_id in unlocked_ids
			and not deck_set.has(card_id)
			and card_id not in library_cards
		):
			library_cards.append(card_id)
	for card_id: StringName in unlocked_ids:
		if not deck_set.has(card_id) and card_id not in library_cards:
			library_cards.append(card_id)
	return {
		"ok": true,
		"main_deck": _string_array(requested_deck),
		"library_cards": _string_array(library_cards),
	}


func _build_victory_advancement(
	profile: Dictionary,
	enemy_id_override: StringName
) -> Dictionary:
	var unchanged: Dictionary = profile.duplicate(true)
	_unlock_enemy_sect(unchanged, get_current_enemy_id(unchanged))
	var current_level: int = get_character_level(profile)
	if current_level >= MAX_CHARACTER_LEVEL:
		return {
			"ok": true,
			"advanced": false,
			"profile": unchanged,
			"added_ids": [],
		}
	var next_level: int = current_level + 1
	var next_enemy_id: StringName = _choose_enemy_id(next_level, enemy_id_override)
	if next_enemy_id == &"":
		return {
			"ok": false,
			"advanced": false,
			"profile": unchanged,
			"added_ids": [],
		}
	var requested_unlocks: Array[StringName] = []
	var current_tier: int = tier_for_level(current_level)
	var next_tier: int = tier_for_level(next_level)
	if next_tier > current_tier:
		for card_id: StringName in TIER_LEAD_UNLOCK_IDS.get(next_tier, []):
			requested_unlocks.append(card_id)
		requested_unlocks.append_array(
			_get_selected_sect_card_ids_for_tier(profile, next_tier)
		)
	var expansion: Dictionary = _build_unlock_expansion(profile, requested_unlocks)
	if not bool(expansion.get("ok", false)):
		return {
			"ok": false,
			"advanced": false,
			"profile": unchanged,
			"added_ids": [],
		}
	var candidate: Dictionary = unchanged.duplicate(true)
	_apply_unlock_expansion(candidate, expansion)
	candidate["level"] = next_level
	candidate["current_enemy_id"] = String(next_enemy_id)
	candidate["remembered_enemy_glyphs"] = []
	return {
		"ok": true,
		"advanced": true,
		"profile": candidate,
		"added_ids": expansion.get("added_ids", []),
	}


func _unlock_enemy_sect(profile: Dictionary, enemy_id: StringName) -> void:
	if enemy_id == &"" or not Enemies.has_enemy(enemy_id):
		return
	_unlock_declared_sect(profile, Enemies.get_definition(enemy_id))


static func _unlock_next_difficulty(profile: Dictionary) -> void:
	var completed_difficulty: int = clampi(
		int(profile.get("run_difficulty", 0)),
		0,
		MAX_DIFFICULTY
	)
	profile["max_unlocked_difficulty"] = maxi(
		int(profile.get("max_unlocked_difficulty", 0)),
		mini(completed_difficulty + 1, MAX_DIFFICULTY)
	)


static func _unlock_declared_sect(profile: Dictionary, enemy: Dictionary) -> void:
	var sect_id := StringName(String(enemy.get("sect_id", "")))
	if sect_id == &"" or not Sects.has_sect(sect_id):
		return
	var unlocked_sects: Array = profile.get("unlocked_sect_ids", []) as Array
	if String(sect_id) not in unlocked_sects:
		unlocked_sects.append(String(sect_id))
	profile["unlocked_sect_ids"] = unlocked_sects


func _build_ending_summary(profile: Dictionary) -> Dictionary:
	var effective_duels: int = maxi(1, int(profile.get("effective_duel_count", 0)))
	var defeated_ids: Array = (profile.get("defeated_enemy_ids", []) as Array).duplicate()
	var difficulty: int = clampi(
		int(profile.get("run_difficulty", 0)),
		0,
		MAX_DIFFICULTY
	)
	var raw_score: int = floori(float(ENDING_SCORE_POOL) / float(effective_duels))
	return {
		"sect_id": String(profile.get("selected_sect_id", "")),
		"score": _score_for_difficulty(raw_score, difficulty),
		"effective_duel_count": effective_duels,
		"defeated_enemy_ids": defeated_ids,
		"flawless": effective_duels == defeated_ids.size(),
	}


func _record_best_score(profile: Dictionary, summary: Dictionary) -> void:
	var sect_id: String = String(summary.get("sect_id", ""))
	var score: int = int(summary.get("score", 0))
	var best_scores: Dictionary = profile.get("best_scores_by_sect", {}) as Dictionary
	var difficulty_scores: Dictionary = (
		(best_scores.get(sect_id, {}) as Dictionary).duplicate(true)
	)
	var completed_difficulty: int = clampi(
		int(profile.get("run_difficulty", 0)),
		0,
		MAX_DIFFICULTY
	)
	for difficulty: int in range(completed_difficulty + 1):
		var difficulty_key: String = str(difficulty)
		var candidate_score: int = _score_for_difficulty(score, difficulty)
		if (
			not difficulty_scores.has(difficulty_key)
			or candidate_score > int(difficulty_scores[difficulty_key])
		):
			difficulty_scores[difficulty_key] = candidate_score
	best_scores[sect_id] = difficulty_scores
	profile["best_scores_by_sect"] = best_scores


static func _score_for_difficulty(score: int, difficulty: int) -> int:
	var nonnegative_score: int = maxi(0, score)
	if difficulty <= 1:
		return mini(nonnegative_score, LOW_DIFFICULTY_SCORE_CAP)
	return nonnegative_score


static func _is_valid_difficulty_score_key(value: String) -> bool:
	if not value.is_valid_int():
		return false
	var difficulty: int = int(value)
	return (
		difficulty >= 0
		and difficulty <= MAX_DIFFICULTY
		and value == str(difficulty)
	)


func _repair_best_scores_by_sect(
	raw_best_scores_value: Variant,
	schema_version: int
) -> Dictionary:
	var repaired: Dictionary = {}
	if typeof(raw_best_scores_value) != TYPE_DICTIONARY:
		return repaired
	var raw_best_scores: Dictionary = raw_best_scores_value as Dictionary
	for raw_sect_id: Variant in raw_best_scores.keys():
		var sect_id := StringName(String(raw_sect_id))
		if typeof(raw_sect_id) != TYPE_STRING or not Sects.has_sect(sect_id):
			continue
		if schema_version < DIFFICULTY_BEST_SCORE_SCHEMA_VERSION:
			var legacy_score_value: Variant = raw_best_scores[raw_sect_id]
			if (
				typeof(legacy_score_value) not in [TYPE_INT, TYPE_FLOAT]
				or float(legacy_score_value) != float(int(legacy_score_value))
				or int(legacy_score_value) < 0
			):
				continue
			var legacy_score: int = int(legacy_score_value)
			repaired[String(sect_id)] = {
				"0": _score_for_difficulty(legacy_score, 0),
				"1": _score_for_difficulty(legacy_score, 1),
				"2": legacy_score,
			}
			continue
		var raw_difficulty_scores_value: Variant = raw_best_scores[raw_sect_id]
		if typeof(raw_difficulty_scores_value) != TYPE_DICTIONARY:
			continue
		var repaired_difficulty_scores: Dictionary = {}
		var raw_difficulty_scores: Dictionary = raw_difficulty_scores_value as Dictionary
		for raw_difficulty: Variant in raw_difficulty_scores.keys():
			if typeof(raw_difficulty) != TYPE_STRING:
				continue
			var difficulty_text: String = String(raw_difficulty)
			if not _is_valid_difficulty_score_key(difficulty_text):
				continue
			var raw_score_value: Variant = raw_difficulty_scores[raw_difficulty]
			if (
				typeof(raw_score_value) not in [TYPE_INT, TYPE_FLOAT]
				or float(raw_score_value) != float(int(raw_score_value))
				or int(raw_score_value) < 0
			):
				continue
			var difficulty: int = int(difficulty_text)
			repaired_difficulty_scores[difficulty_text] = _score_for_difficulty(
				int(raw_score_value),
				difficulty
			)
		if not repaired_difficulty_scores.is_empty():
			repaired[String(sect_id)] = repaired_difficulty_scores
	return repaired


func _apply_mastery_candidates(profile: Dictionary, candidate_ids: Array) -> void:
	var main_deck_set: Dictionary = {}
	for value: Variant in profile.get("main_deck", []):
		main_deck_set[StringName(String(value))] = true
	var mastered_ids: Array[StringName] = []
	var mastered_set: Dictionary = {}
	for value: Variant in profile.get("mastered_card_ids", []):
		var mastered_id := StringName(String(value))
		if mastered_id == &"" or mastered_set.has(mastered_id):
			continue
		mastered_ids.append(mastered_id)
		mastered_set[mastered_id] = true
	for value: Variant in candidate_ids:
		var card_id := StringName(String(value))
		if (
			card_id == &""
			or not Catalog.has_card(card_id)
			or not main_deck_set.has(card_id)
			or mastered_set.has(card_id)
		):
			continue
		mastered_ids.append(card_id)
		mastered_set[card_id] = true
	profile["mastered_card_ids"] = _string_array(mastered_ids)


func _build_run_reset_profile(profile: Dictionary) -> Dictionary:
	if not is_profile_valid(profile):
		return {}
	var reset_profile: Dictionary = create_default_profile()
	reset_profile["unlocked_sect_ids"] = (
		profile["unlocked_sect_ids"] as Array
	).duplicate()
	reset_profile["best_scores_by_sect"] = (
		profile["best_scores_by_sect"] as Dictionary
	).duplicate(true)
	reset_profile["mastered_card_ids"] = (
		profile["mastered_card_ids"] as Array
	).duplicate()
	reset_profile["max_unlocked_difficulty"] = int(
		profile["max_unlocked_difficulty"]
	)
	reset_profile["last_selected_difficulty"] = int(
		profile["last_selected_difficulty"]
	)
	if not is_profile_valid(reset_profile):
		return {}
	return reset_profile


func _build_default_deck_placement(
	unlocked_ids: Array[StringName],
	current_deck: Array,
	current_library: Array
) -> Dictionary:
	for default_card_id: StringName in DEFAULT_MAIN_DECK_IDS:
		if default_card_id not in unlocked_ids:
			return {"ok": false}
	var library_order: Array[StringName] = []
	for collection: Array in [current_library, current_deck, unlocked_ids]:
		for value: Variant in collection:
			var card_id := StringName(String(value))
			if (
				card_id != &""
				and card_id not in DEFAULT_MAIN_DECK_IDS
				and card_id in unlocked_ids
				and card_id not in library_order
			):
				library_order.append(card_id)
	return {
		"ok": true,
		"main_deck": _string_array(DEFAULT_MAIN_DECK_IDS),
		"library_cards": _string_array(library_order),
	}


func _build_inactive_deck_placement(
	unlocked_ids: Array[StringName],
	current_library: Array
) -> Dictionary:
	for base_id: StringName in DEFAULT_MAIN_DECK_IDS:
		if base_id not in unlocked_ids:
			return {"ok": false}
	var library_cards: Array[StringName] = []
	for collection: Array in [current_library, unlocked_ids]:
		for value: Variant in collection:
			var card_id := StringName(String(value))
			if (
				card_id != &""
				and card_id in unlocked_ids
				and card_id not in DEFAULT_MAIN_DECK_IDS
				and card_id not in library_cards
			):
				library_cards.append(card_id)
	return {
		"ok": true,
		"main_deck": _string_array(DEFAULT_MAIN_DECK_IDS),
		"library_cards": _string_array(library_cards),
	}


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
