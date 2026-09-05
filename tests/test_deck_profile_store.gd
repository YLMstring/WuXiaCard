extends SceneTree

const Store = preload("res://scripts/deck_profile_store.gd")
const Enemies = preload("res://scripts/enemy_catalog.gd")
const Cards = preload("res://scripts/card_catalog.gd")
const Sects = preload("res://scripts/sect_catalog.gd")

const NEW_SECT_CARD_IDS: Array[StringName] = [
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
const LEGACY_MAIN_DECK_IDS: Array[StringName] = [
	&"CangSongYingKe2",
	&"LeiZHenJian1",
	&"KuiHua1",
	&"YouFenLaiYi2",
	&"TuNaShu2",
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
	_check(int(profile["schema_version"]) == 11, "Default profile uses schema version 11")
	_check(
		(profile["shown_guaranteed_reward_card_ids"] as Array).is_empty(),
		"Default profile has no shown guaranteed rewards"
	)
	_check(not bool(profile["run_active"]), "Default profile has no active run")
	_check(String(profile["selected_sect_id"]).is_empty(), "Default profile has no selected sect")
	_check(
		int(profile.get("max_unlocked_difficulty", -1)) == 0,
		"New profiles unlock only difficulty zero"
	)
	_check(
		int(profile.get("last_selected_difficulty", -1)) == 0,
		"New profiles select difficulty zero"
	)
	_check(
		int(profile.get("run_difficulty", -1)) == 0,
		"New profiles have no active run difficulty"
	)
	_check(
		store.get_best_score(profile, &"HuaShanPai", 0) == 0
		and store.get_best_score(profile, &"HuaShanPai", 9) == 0,
		"Missing per-difficulty best scores read as zero"
	)
	_check(store.get_character_level(profile) == 0, "New profiles begin at character level zero")
	_check(store.get_character_tier(profile) == 1, "Character tier begins at one")
	_check(store.get_current_enemy_id(profile) == &"", "Inactive profiles have no enemy")
	_check(store.get_remembered_enemy_glyphs(profile).is_empty(), "New profiles remember no enemy cards")
	_check(store.get_pending_reward_ids(profile).is_empty(), "New profiles have no pending reward")
	_check(
		store.get_mastered_card_ids(profile).is_empty(),
		"New profiles begin with no mastered cards"
	)
	_check(
		not store.is_card_mastered(profile, Store.DEFAULT_MAIN_DECK_IDS[0]),
		"Default main-deck cards do not begin mastered"
	)
	_check(
		store.get_unlocked_sect_ids(profile) == [&"HuaShanPai"],
		"Only Xuanyue Jianzong starts unlocked"
	)
	_check(
		store.get_unlocked_ids(profile) == Store.DEFAULT_MAIN_DECK_IDS,
		"Normal profiles initially unlock only Taizu Changquan and tier-one Tuna"
	)
	_check(
		store.get_main_deck_ids(profile) == Store.DEFAULT_MAIN_DECK_IDS,
		"The inactive initial deck contains the two base cards"
	)
	_check((profile["library_slots"] as Array).size() == 1000, "Default library has 1000 slots")
	var expected_library_count: int = 0
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
	var normal_profile: Dictionary = profile.duplicate(true)
	profile = store.create_testing_profile(profile)
	_check(store.is_profile_valid(profile), "Testing profile expansion is valid")
	_check(
		store.get_unlocked_ids(profile).size() == Cards.get_all_card_ids().size(),
		"Testing profile expansion unlocks every card"
	)
	_check(
		normal_profile == store.load_profile(),
		"Testing profile expansion does not mutate the persisted normal profile"
	)
	profile = _legacy_collection_profile(store)
	_check(store.save_profile(profile), "Legacy collection fixture saves")
	var malformed_mastery: Dictionary = profile.duplicate(true)
	malformed_mastery["mastered_card_ids"] = [
		String(Store.DEFAULT_MAIN_DECK_IDS[0]),
		"missing_card",
		String(Store.DEFAULT_MAIN_DECK_IDS[0]),
		String(Store.DEFAULT_MAIN_DECK_IDS[1]),
	]
	_check(
		not store.is_profile_valid(malformed_mastery),
		"Profiles reject unknown or duplicate mastery IDs"
	)
	var repaired_mastery: Dictionary = store.repair_profile(malformed_mastery)
	_check(
		store.get_mastered_card_ids(repaired_mastery) == [
			Store.DEFAULT_MAIN_DECK_IDS[0],
			Store.DEFAULT_MAIN_DECK_IDS[1],
		],
		"Mastery repair filters invalid entries in stable order"
	)
	var legacy_duplicate: Dictionary = profile.duplicate(true)
	var duplicate_source_index: int = (
		legacy_duplicate["library_slots"] as Array
	).find("CangSongYingKe3")
	_check(duplicate_source_index >= 0, "Legacy repair fixture finds a higher namesake")
	if duplicate_source_index >= 0:
		var displaced_for_fixture: String = String(legacy_duplicate["main_deck"][1])
		legacy_duplicate["main_deck"][1] = "CangSongYingKe3"
		legacy_duplicate["library_slots"][duplicate_source_index] = displaced_for_fixture
		_check(
			not store.is_profile_valid(legacy_duplicate),
			"Player profiles reject repeated glyphs"
		)
		var repaired_duplicate: Dictionary = store.repair_profile(legacy_duplicate)
		_check(
			store.is_profile_valid(repaired_duplicate),
			"Legacy repeated-glyph profile repairs to a valid deck"
		)
		_check(
			String(repaired_duplicate["main_deck"][1]) == "CangSongYingKe3",
			"Legacy repair keeps the highest-tier namesake in its original slot"
		)
		_check(
			String(repaired_duplicate["library_slots"][
				_occupied_count(repaired_duplicate["library_slots"]) - 1
			]) == "CangSongYingKe2",
			"Removed legacy namesake moves to the library bottom"
		)

	var original_deck: Array = (profile["main_deck"] as Array).duplicate()
	var original_library_card: String = String(profile["library_slots"][4])
	var exchange_result: Dictionary = store.exchange_and_save(profile, 4, 3)
	_check(bool(exchange_result.get("ok", false)), "A valid exchange saves")
	var exchanged: Dictionary = exchange_result.get("profile", {})
	_check(String(exchanged["main_deck"][3]) == original_library_card, "Library card enters target deck slot")
	_check(String(exchanged["library_slots"][4]) == String(original_deck[3]), "Displaced deck card takes exact source slot")
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
	var namesake_source_index: int = (
		unlocked["library_slots"] as Array
	).find("CangSongYingKe1")
	var rotated_result: Dictionary = store.exchange_and_save(
		unlocked,
		namesake_source_index,
		2
	)
	_check(bool(rotated_result.get("ok", false)), "Namesake exchange saves atomically")
	var rotated_profile: Dictionary = rotated_result.get("profile", {})
	_check(
		String(rotated_profile["main_deck"][2]) == "CangSongYingKe1",
		"Incoming namesake enters the selected main-deck slot"
	)
	_check(
		String(rotated_profile["main_deck"][0]) == String(unlocked["main_deck"][2]),
		"Selected-slot card rotates into the old namesake slot"
	)
	_check(
		String(rotated_profile["library_slots"][namesake_source_index])
		== "CangSongYingKe2",
		"Old namesake rotates into the original library source"
	)

	var duplicate_unlock: Dictionary = store.unlock_and_save(unlocked, &"CangSongYingKe1")
	_check(not bool(duplicate_unlock.get("ok", true)), "Duplicate unlock is rejected")
	_check(duplicate_unlock.get("profile", {}) == unlocked, "Duplicate unlock preserves profile")

	var batch_result: Dictionary = store.unlock_cards_and_save(
		unlocked,
		[&"MianLiCangZhen2", &"YunWu13Shi2"]
	)
	_check(bool(batch_result.get("ok", false)), "An ordered card batch saves")
	var batch_profile: Dictionary = batch_result.get("profile", {})
	_check(
		(batch_result.get("added_ids", []) as Array) == [&"MianLiCangZhen2", &"YunWu13Shi2"],
		"Batch result reports added IDs in input order"
	)
	_check(
		String(batch_profile["library_slots"][0]) == "MianLiCangZhen2"
		and String(batch_profile["library_slots"][1]) == "YunWu13Shi2",
		"Batch cards enter the library top without reversing"
	)
	_check(
		String(batch_profile["library_slots"][2]) == String(unlocked["library_slots"][0]),
		"Existing library order follows the complete new batch"
	)
	var partial_batch: Dictionary = store.unlock_cards_and_save(
		batch_profile,
		[&"MianLiCangZhen2", &"YiJianLuo9Yan1"]
	)
	_check(bool(partial_batch.get("ok", false)), "A partially owned batch succeeds")
	var partial_profile: Dictionary = partial_batch.get("profile", {})
	_check(
		(partial_batch.get("added_ids", []) as Array) == [&"YiJianLuo9Yan1"],
		"Only the missing card is reported from a partial batch"
	)
	_check(
		String(partial_profile["library_slots"][0]) == "YiJianLuo9Yan1"
		and String(partial_profile["library_slots"][1]) == "MianLiCangZhen2",
		"Only newly unlocked cards are inserted ahead of existing cards"
	)
	_check(
		partial_profile["unlocked_card_ids"].count("MianLiCangZhen2") == 1,
		"Batch unlock never duplicates ownership"
	)
	var no_op_batch: Dictionary = store.unlock_cards_and_save(
		partial_profile,
		[&"MianLiCangZhen2", &"missing_card"]
	)
	_check(bool(no_op_batch.get("ok", false)), "An empty filtered batch is a successful no-op")
	_check(no_op_batch.get("profile", {}) == partial_profile, "A no-op batch preserves the exact profile")
	_check((no_op_batch.get("added_ids", []) as Array).is_empty(), "A no-op batch reports no additions")

	var family_profile: Dictionary = _profile_with_locked_cards(
		store,
		[&"CangSongYingKe1", &"CangSongYingKe3", &"CangSongYingKe4"]
	)
	var family_library_before: Array = _occupied_values(family_profile["library_slots"])
	var family_unlock: Dictionary = store.unlock_and_save(
		family_profile,
		&"CangSongYingKe4"
	)
	_check(bool(family_unlock.get("ok", false)), "A high-tier family card unlock saves")
	var family_unlocked: Dictionary = family_unlock.get("profile", {})
	_check(
		(family_unlock.get("added_ids", []) as Array)
		== [&"CangSongYingKe4", &"CangSongYingKe1", &"CangSongYingKe3"],
		"Single unlock reports its primary before inherited lower-tier namesakes"
	)
	_check(
		String(family_unlocked["library_slots"][0]) == "CangSongYingKe4",
		"The directly unlocked family card enters the library top"
	)
	_check(
		_occupied_values(family_unlocked["library_slots"]).slice(
			1,
			1 + family_library_before.size()
		) == family_library_before,
		"Existing library order remains between primary and inherited cards"
	)
	_check(
		String(family_unlocked["library_slots"][1 + family_library_before.size()])
		== "CangSongYingKe1"
		and String(family_unlocked["library_slots"][2 + family_library_before.size()])
		== "CangSongYingKe3",
		"Inherited lower-tier namesakes append at the library bottom in catalog order"
	)
	_check(
		Store._is_lower_namesake(
			{"glyph": "同名", "sect": "甲门", "tier": 4},
			{"glyph": "同名", "sect": "乙门", "tier": 1}
		) == false,
		"Equal glyphs from different sects do not form an unlock family"
	)
	_check(
		Store._is_lower_namesake(
			{"glyph": "同名", "sect": "甲门", "tier": 4},
			{"glyph": "同名", "sect": "甲门", "tier": 2}
		),
		"Matching glyph and sect with a lower tier forms an unlock family"
	)
	_check(
		not Store._is_lower_namesake(
			{"glyph": "同名", "sect": "甲门", "tier": 4},
			{"glyph": "同名", "sect": "甲门", "tier": 4}
		),
		"Equal-tier namesakes are not inherited"
	)

	var overlapping_profile: Dictionary = _profile_with_locked_cards(
		store,
		[&"CangSongYingKe1", &"CangSongYingKe3", &"CangSongYingKe4"]
	)
	var overlapping_library_before: Array = _occupied_values(
		overlapping_profile["library_slots"]
	)
	var overlapping_unlock: Dictionary = store.unlock_cards_and_save(
		overlapping_profile,
		[&"CangSongYingKe4", &"CangSongYingKe3", &"CangSongYingKe4"]
	)
	_check(bool(overlapping_unlock.get("ok", false)), "Overlapping family batch saves")
	var overlapping_result: Dictionary = overlapping_unlock.get("profile", {})
	_check(
		(overlapping_unlock.get("added_ids", []) as Array)
		== [&"CangSongYingKe4", &"CangSongYingKe3", &"CangSongYingKe1"],
		"Explicit primaries remain at the front and overlapping inheritance is deduplicated"
	)
	_check(
		String(overlapping_result["library_slots"][0]) == "CangSongYingKe4"
		and String(overlapping_result["library_slots"][1]) == "CangSongYingKe3"
		and String(
			overlapping_result["library_slots"][2 + overlapping_library_before.size()]
		) == "CangSongYingKe1",
		"Batch primaries enter the top while only the inherited card enters the bottom"
	)

	var legacy_family_profile: Dictionary = family_profile.duplicate(true)
	var legacy_family_library: Array = _occupied_values(
		legacy_family_profile["library_slots"]
	)
	legacy_family_library.push_front("CangSongYingKe4")
	while legacy_family_library.size() < Store.LIBRARY_CAPACITY:
		legacy_family_library.append("")
	legacy_family_profile["library_slots"] = legacy_family_library
	(legacy_family_profile["unlocked_card_ids"] as Array).push_front(
		"CangSongYingKe4"
	)
	_check(
		store.is_profile_valid(legacy_family_profile),
		"Legacy family fixture with missing lower tiers is valid"
	)
	_check(
		store.repair_profile(legacy_family_profile) == legacy_family_profile,
		"Profile repair does not retroactively cascade a prior high-tier unlock"
	)

	var schema_one: Dictionary = profile.duplicate(true)
	schema_one["schema_version"] = 1
	schema_one.erase("unlocked_sect_ids")
	schema_one.erase("run_active")
	schema_one.erase("selected_sect_id")
	var migrated: Dictionary = store.repair_profile(schema_one)
	_check(store.is_profile_valid(migrated), "A schema-1 profile migrates to a valid current profile")
	_check(int(migrated["schema_version"]) == 11, "Migration advances the schema version")
	_check(
		store.get_unlocked_sect_ids(migrated) == [&"HuaShanPai"],
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
	_check(
		int(migrated.get("max_unlocked_difficulty", -1)) == 2
		and int(migrated.get("last_selected_difficulty", -1)) == 2
		and int(migrated.get("run_difficulty", -1)) == 0,
		"Legacy inactive profiles unlock and select difficulty two without an active difficulty"
	)

	var schema_eight: Dictionary = profile.duplicate(true)
	schema_eight["schema_version"] = 8
	schema_eight.erase("shown_guaranteed_reward_card_ids")
	schema_eight["mastered_card_ids"] = ["TaiZuChangQuan"]
	var migrated_schema_eight: Dictionary = store.repair_profile(schema_eight)
	_check(store.is_profile_valid(migrated_schema_eight), "A schema-eight profile migrates successfully")
	_check(
		migrated_schema_eight["mastered_card_ids"] == ["TaiZuChangQuan"],
		"Schema-eight migration preserves mastery"
	)
	_check(
		(migrated_schema_eight["shown_guaranteed_reward_card_ids"] as Array).is_empty(),
		"Schema-eight migration starts with no shown guaranteed rewards"
	)
	var schema_ten: Dictionary = profile.duplicate(true)
	schema_ten["schema_version"] = 10
	schema_ten["best_scores_by_sect"] = {
		"HuaShanPai": 4321,
		"TaiShanPai": 321,
	}
	var migrated_schema_ten: Dictionary = store.repair_profile(schema_ten)
	_check(store.is_profile_valid(migrated_schema_ten), "A schema-ten profile migrates successfully")
	_check(
		store.get_best_score(migrated_schema_ten, &"HuaShanPai", 0) == 500
		and store.get_best_score(migrated_schema_ten, &"HuaShanPai", 1) == 500
		and store.get_best_score(migrated_schema_ten, &"HuaShanPai", 2) == 4321
		and store.get_best_score(migrated_schema_ten, &"HuaShanPai", 3) == 0
		and store.get_best_score(migrated_schema_ten, &"TaiShanPai", 0) == 321
		and store.get_best_score(migrated_schema_ten, &"TaiShanPai", 1) == 321
		and store.get_best_score(migrated_schema_ten, &"TaiShanPai", 2) == 321,
		"Schema-ten scalar scores migrate to difficulties zero, one, and two with low caps"
	)

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
		"unlocked_card_ids": ["LeiZHenJian1", "KuiHua1", "jiang_wei", "TuNaShu2", "TaiZuChangQuan", "HuZhuaJueHuSHou2"],
		"unlocked_sect_ids": ["missing_sect", "TaiShanPai", "TaiShanPai"],
		"main_deck": ["LeiZHenJian1", "LeiZHenJian1", "missing", "jiang_wei"],
		"library_slots": ["", "KuiHua1", "", "TuNaShu2", "TaiZuChangQuan", "HuZhuaJueHuSHou2"],
	}
	var repaired: Dictionary = store.repair_profile(malformed)
	_check(store.is_profile_valid(repaired), "Malformed profile repairs to a valid profile")
	_check(
		store.get_unlocked_sect_ids(repaired) == [&"HuaShanPai", &"TaiShanPai"],
		"Repair removes unknown and duplicate sects while restoring the default"
	)
	_check(_library_has_no_gaps(repaired["library_slots"]), "Repair leaves no gaps in occupied prefix")
	var malformed_difficulty: Dictionary = repaired.duplicate(true)
	malformed_difficulty["max_unlocked_difficulty"] = 12.5
	malformed_difficulty["last_selected_difficulty"] = -3
	malformed_difficulty["run_difficulty"] = 7
	_check(
		not store.is_profile_valid(malformed_difficulty),
		"Difficulty fields reject fractional, negative, and inactive-run values"
	)
	var repaired_difficulty: Dictionary = store.repair_profile(malformed_difficulty)
	_check(
		store.is_profile_valid(repaired_difficulty)
		and int(repaired_difficulty.get("max_unlocked_difficulty", -1)) == 9
		and int(repaired_difficulty.get("last_selected_difficulty", -1)) == 0
		and int(repaired_difficulty.get("run_difficulty", -1)) == 0,
		"Difficulty repair clamps the global range and clears inactive run difficulty"
	)
	var malformed_scores: Dictionary = repaired_difficulty.duplicate(true)
	malformed_scores["best_scores_by_sect"] = {
		"HuaShanPai": {
			"0": 900,
			"1": 501,
			"2": 1200,
			"10": 50,
			"bad": 80,
		},
		"missing_sect": {"2": 700},
		"TaiShanPai": "invalid",
	}
	_check(
		not store.is_profile_valid(malformed_scores),
		"Per-difficulty score validation rejects low-cap overflow and malformed entries"
	)
	var repaired_scores: Dictionary = store.repair_profile(malformed_scores)
	_check(
		store.is_profile_valid(repaired_scores)
		and store.get_best_score(repaired_scores, &"HuaShanPai", 0) == 500
		and store.get_best_score(repaired_scores, &"HuaShanPai", 1) == 500
		and store.get_best_score(repaired_scores, &"HuaShanPai", 2) == 1200
		and store.get_best_score(repaired_scores, &"HuaShanPai", 9) == 0
		and store.get_best_score(repaired_scores, &"TaiShanPai", 2) == 0
		and store.get_best_score(repaired_scores, &"HuaShanPai", 10) == 0,
		"Score repair caps low difficulties and skips invalid sects, keys, and values"
	)

	var run_start_source: Dictionary = store.create_default_profile()
	_check(store.save_profile(run_start_source), "Run-state fixture saves")
	var selectable_difficulty_profile: Dictionary = run_start_source.duplicate(true)
	selectable_difficulty_profile["max_unlocked_difficulty"] = 2
	var select_difficulty: Dictionary = store.set_last_selected_difficulty_and_save(
		selectable_difficulty_profile,
		2
	)
	_check(bool(select_difficulty.get("ok", false)), "Selecting an unlocked difficulty saves")
	var selected_difficulty_profile: Dictionary = select_difficulty.get("profile", {})
	_check(
		store.get_max_unlocked_difficulty(selected_difficulty_profile) == 2
		and store.get_last_selected_difficulty(selected_difficulty_profile) == 2,
		"Difficulty accessors return the saved global and selected values"
	)
	var reject_difficulty: Dictionary = store.set_last_selected_difficulty_and_save(
		selected_difficulty_profile,
		3
	)
	_check(
		not bool(reject_difficulty.get("ok", true))
		and reject_difficulty.get("profile", {}) == selected_difficulty_profile,
		"Selecting a locked difficulty fails without changing the profile"
	)
	var difficulty_rng := RandomNumberGenerator.new()
	difficulty_rng.seed = 3107
	var difficulty_begin: Dictionary = store.begin_run_and_save(
		selected_difficulty_profile,
		&"HuaShanPai",
		[&"CangSongYingKe1"],
		&"qingfeng_xuedi",
		difficulty_rng,
		false,
		2
	)
	_check(
		bool(difficulty_begin.get("ok", false))
		and store.get_run_difficulty(difficulty_begin.get("profile", {})) == 2,
		"Beginning an unlocked difficulty records it on the active run"
	)
	var locked_difficulty_begin: Dictionary = store.begin_run_and_save(
		selected_difficulty_profile,
		&"HuaShanPai",
		[&"CangSongYingKe1"],
		&"qingfeng_xuedi",
		difficulty_rng,
		false,
		3
	)
	_check(
		not bool(locked_difficulty_begin.get("ok", true)),
		"Beginning a locked difficulty is rejected by the profile store"
	)
	_check(store.save_profile(run_start_source), "Run-state fixture resets after difficulty checks")
	var start_rng := RandomNumberGenerator.new()
	start_rng.seed = 3108
	var begin_result: Dictionary = store.begin_run_and_save(
		run_start_source,
		&"HuaShanPai",
		[&"CangSongYingKe1"],
		&"qingfeng_xuedi",
		start_rng
	)
	_check(bool(begin_result.get("ok", false)), "Beginning a valid run saves atomically")
	var active_profile: Dictionary = begin_result.get("profile", {})
	_check(store.is_run_active(active_profile), "Beginning a run marks it active")
	_check(store.get_character_level(active_profile) == 1, "Beginning a run advances to level one")
	_check(store.get_character_tier(active_profile) == 1, "Level one remains tier one")
	_check(store.get_run_difficulty(active_profile) == 0, "Existing run-start callers default to difficulty zero")
	var schema_nine_active: Dictionary = active_profile.duplicate(true)
	schema_nine_active["schema_version"] = 9
	schema_nine_active.erase("max_unlocked_difficulty")
	schema_nine_active.erase("last_selected_difficulty")
	schema_nine_active.erase("run_difficulty")
	var migrated_schema_nine_active: Dictionary = store.repair_profile(schema_nine_active)
	_check(
		store.is_profile_valid(migrated_schema_nine_active)
		and store.get_max_unlocked_difficulty(migrated_schema_nine_active) == 2
		and store.get_last_selected_difficulty(migrated_schema_nine_active) == 2
		and store.get_run_difficulty(migrated_schema_nine_active) == 2,
		"A schema-nine active run migrates as difficulty two"
	)
	var first_enemy_id: StringName = store.get_current_enemy_id(active_profile)
	_check(
		first_enemy_id in Enemies.get_enemy_ids_for_level(1),
		"Beginning a run assigns a level-one enemy"
	)
	var first_enemy_deck: Array = Enemies.get_definition(first_enemy_id)["deck"]
	var remembered_glyph: String = String(
		Cards.get_definition(StringName(String(first_enemy_deck[0])))["glyph"]
	)
	var remember_result: Dictionary = store.remember_enemy_glyph_and_save(
		active_profile,
		remembered_glyph
	)
	_check(bool(remember_result.get("ok", false)), "Seeing an enemy card saves its glyph")
	active_profile = remember_result.get("profile", active_profile)
	_check(
		store.get_remembered_enemy_glyphs(active_profile) == [remembered_glyph],
		"Remembered enemy glyph persists in the active run"
	)
	var duplicate_memory: Dictionary = store.remember_enemy_glyph_and_save(
		active_profile,
		remembered_glyph
	)
	_check(bool(duplicate_memory.get("ok", false)), "Remembering the same glyph is a successful no-op")
	_check(
		duplicate_memory.get("profile", {}) == active_profile,
		"Duplicate memory does not change the profile"
	)
	var invalid_memory: Dictionary = store.remember_enemy_glyph_and_save(
		active_profile,
		"不在敌方牌组"
	)
	_check(not bool(invalid_memory.get("ok", true)), "Unknown enemy glyphs cannot be remembered")
	_check(
		store.get_selected_sect_id(active_profile) == &"HuaShanPai",
		"Beginning a run records the selected sect"
	)
	var starting_deck: Array[StringName] = store.get_main_deck_ids(active_profile)
	_check(starting_deck.size() == 5, "Run start creates a complete five-card deck")
	_check(
		starting_deck.slice(0, 2) == Store.DEFAULT_MAIN_DECK_IDS,
		"Run start keeps the two base cards first"
	)
	var random_start_ids: Array[StringName] = starting_deck.slice(2)
	_check(random_start_ids.size() == 3, "Run start adds exactly three random cards")
	for random_id: StringName in random_start_ids:
		var definition: Dictionary = Cards.get_definition(random_id)
		_check(int(definition.get("tier", 0)) == 1, "%s is a tier-one random unlock" % random_id)
		_check(String(definition.get("sect", "")) != "华山", "%s is outside the selected sect" % random_id)
	var unlocked_after_start: Array[StringName] = store.get_unlocked_ids(active_profile)
	for card_id: StringName in Cards.get_all_card_ids():
		var definition: Dictionary = Cards.get_definition(card_id)
		if String(definition.get("sect", "")) == "华山" and int(definition.get("tier", 0)) == 1:
			_check(card_id in unlocked_after_start, "%s selected-sect tier one starts unlocked" % card_id)

	var reward_family_source: Dictionary = _profile_with_locked_cards(
		store,
		[&"CangSongYingKe1", &"CangSongYingKe3", &"CangSongYingKe4"]
	)
	var reward_family_begin: Dictionary = store.begin_run_and_save(
		reward_family_source,
		&"HuaShanPai",
		[&"CangSongYingKe1"],
		&"qingfeng_xuedi"
	)
	var reward_family_profile: Dictionary = reward_family_begin.get("profile", {})
	reward_family_profile["pending_reward_card_ids"] = ["CangSongYingKe4"]
	_check(
		store.is_profile_valid(reward_family_profile),
		"Reward family fixture remains a valid active profile"
	)
	var reward_family_before: Array = _occupied_values(
		reward_family_profile["library_slots"]
	)
	var reward_family_claim: Dictionary = store.claim_pending_reward_and_save(
		reward_family_profile,
		&"CangSongYingKe4"
	)
	_check(bool(reward_family_claim.get("ok", false)), "Claiming a family reward saves")
	var reward_family_result: Dictionary = reward_family_claim.get("profile", {})
	_check(
		String(reward_family_result["library_slots"][0]) == "CangSongYingKe4",
		"Claimed reward remains the primary top-of-library unlock"
	)
	_check(
		String(reward_family_result["library_slots"][1 + reward_family_before.size()])
		== "CangSongYingKe3",
		"Reward inheritance appends only the still-locked lower-tier namesake at the bottom"
	)
	_check(
		store.get_pending_reward_ids(reward_family_result).is_empty(),
		"Successful cascading reward claim clears the pending offer"
	)
	var schema_seven_active: Dictionary = active_profile.duplicate(true)
	schema_seven_active["schema_version"] = 7
	schema_seven_active.erase("mastered_card_ids")
	schema_seven_active["pending_reward_card_ids"] = ["MianLiCangZhen2"]
	schema_seven_active["effective_duel_count"] = 1
	schema_seven_active["best_scores_by_sect"] = {"HuaShanPai": 1234}
	var migrated_schema_seven: Dictionary = store.repair_profile(schema_seven_active)
	_check(
		store.is_profile_valid(migrated_schema_seven),
		"A schema-seven active profile migrates to schema eight"
	)
	_check(
		store.is_run_active(migrated_schema_seven),
		"Schema-seven migration preserves an active run"
	)
	_check(
		migrated_schema_seven["main_deck"] == schema_seven_active["main_deck"]
		and migrated_schema_seven["library_slots"] == schema_seven_active["library_slots"]
		and migrated_schema_seven["unlocked_card_ids"] == schema_seven_active["unlocked_card_ids"],
		"Schema-seven migration preserves deck placement and unlocks"
	)
	_check(
		migrated_schema_seven["remembered_enemy_glyphs"]
		== schema_seven_active["remembered_enemy_glyphs"]
		and store.get_pending_reward_ids(migrated_schema_seven) == [&"MianLiCangZhen2"]
		and int(migrated_schema_seven["effective_duel_count"]) == 1
		and store.get_best_score(migrated_schema_seven, &"HuaShanPai", 0) == 500
		and store.get_best_score(migrated_schema_seven, &"HuaShanPai", 1) == 500
		and store.get_best_score(migrated_schema_seven, &"HuaShanPai", 2) == 1234
		and store.get_best_score(migrated_schema_seven, &"HuaShanPai", 3) == 0,
		"Schema-seven migration preserves active-run history and pending reward"
	)
	_check(
		store.get_mastered_card_ids(migrated_schema_seven).is_empty(),
		"Schema-seven migration starts mastery empty"
	)
	var legacy_active: Dictionary = active_profile.duplicate(true)
	legacy_active["schema_version"] = 3
	legacy_active.erase("level")
	legacy_active.erase("current_enemy_id")
	var migrated_active: Dictionary = store.repair_profile(legacy_active)
	_check(not store.is_run_active(migrated_active), "A legacy active run closes when history cannot be reconstructed")
	_check(
		store.get_character_level(migrated_active) == 0,
		"Legacy active-run migration clears character progression"
	)
	_check(
		store.get_current_enemy_id(migrated_active) == &"",
		"Legacy active-run migration clears the unreconstructable enemy"
	)
	_check(
		store.get_remembered_enemy_glyphs(migrated_active).is_empty(),
		"Legacy active runs begin with no remembered cards"
	)
	var retained_sects: Array = (active_profile["unlocked_sect_ids"] as Array).duplicate()
	var retained_mastery: Array = (active_profile["mastered_card_ids"] as Array).duplicate()
	var exchange_for_reset: Dictionary = store.exchange_and_save(active_profile, 0, 0)
	_check(bool(exchange_for_reset.get("ok", false)), "Run fixture can change its main deck")
	var changed_profile: Dictionary = exchange_for_reset.get("profile", {})
	var progression_unlock_result: Dictionary = store.unlock_all_progression_and_save(
		changed_profile
	)
	_check(bool(progression_unlock_result.get("ok", false)), "Full progression unlock saves")
	var progression_unlock_profile: Dictionary = progression_unlock_result.get("profile", {})
	var expected_progression_profile: Dictionary = changed_profile.duplicate(true)
	expected_progression_profile["unlocked_sect_ids"] = []
	for sect_id: StringName in Sects.get_all_sect_ids():
		expected_progression_profile["unlocked_sect_ids"].append(String(sect_id))
	expected_progression_profile["max_unlocked_difficulty"] = Store.MAX_DIFFICULTY
	_check(
		store.get_unlocked_sect_ids(progression_unlock_profile) == Sects.get_all_sect_ids(),
		"Full progression unlock stores every sect in catalog order"
	)
	_check(
		store.get_max_unlocked_difficulty(progression_unlock_profile) == Store.MAX_DIFFICULTY,
		"Full progression unlock stores difficulty nine"
	)
	_check(
		progression_unlock_profile == expected_progression_profile,
		"Full progression unlock preserves every unrelated profile field"
	)
	_check(
		store.load_profile() == progression_unlock_profile,
		"Full progression unlock persists its exact candidate"
	)
	changed_profile = progression_unlock_profile
	retained_sects = (progression_unlock_profile["unlocked_sect_ids"] as Array).duplicate()
	var reset_result: Dictionary = store.reset_run_and_save(changed_profile)
	_check(bool(reset_result.get("ok", false)), "Resetting the current run saves")
	var reset_profile: Dictionary = reset_result.get("profile", {})
	_check(not store.is_run_active(reset_profile), "Run reset clears active state")
	_check(store.get_selected_sect_id(reset_profile) == &"", "Run reset clears the selected sect")
	_check(
		store.get_main_deck_ids(reset_profile) == Store.DEFAULT_MAIN_DECK_IDS,
		"Run reset restores the two-card inactive deck"
	)
	_check(
		store.get_unlocked_ids(reset_profile) == Store.DEFAULT_MAIN_DECK_IDS,
		"Run reset clears card unlocks except the two base cards"
	)
	_check(
		reset_profile["unlocked_sect_ids"] == retained_sects,
		"Run reset preserves sect unlocks"
	)
	_check(reset_profile["mastered_card_ids"] == retained_mastery, "Run reset preserves mastery")
	_check(store.get_character_level(reset_profile) == 0, "Run reset clears character level")
	_check(store.get_current_enemy_id(reset_profile) == &"", "Run reset clears the enemy")
	var declared_sect_profile: Dictionary = reset_profile.duplicate(true)
	Store._unlock_declared_sect(declared_sect_profile, {"sect_id": &"TaiShanPai"})
	_check(
		&"TaiShanPai" in store.get_unlocked_sect_ids(declared_sect_profile),
		"Defeating an enemy with a sect declaration unlocks that sect"
	)
	Store._unlock_declared_sect(declared_sect_profile, {"sect_id": &"TaiShanPai"})
	_check(
		(declared_sect_profile["unlocked_sect_ids"] as Array).count("TaiShanPai") == 1,
		"Repeated enemy sect unlocks are idempotent"
	)
	var no_sect_profile: Dictionary = reset_profile.duplicate(true)
	Store._unlock_declared_sect(no_sect_profile, {})
	_check(no_sect_profile == reset_profile, "Enemies without a sect declaration unlock nothing")

	var tier_reward_advance: Dictionary = store.advance_after_victory_and_save(
		active_profile,
		&"tieshan_menren"
	)
	var tier_reward_profile: Dictionary = tier_reward_advance.get(
		"profile",
		active_profile
	)
	var tier_reward_added: Array = tier_reward_advance.get("added_ids", []) as Array
	_check(
		&"CangSongYingKe2" in store.get_unlocked_ids(tier_reward_profile),
		"Level-two progression preserves an owned selected-sect tier-two card"
	)
	_check(
		not tier_reward_added.is_empty()
		and StringName(String(tier_reward_added[0])) == &"TuNaShu2"
		and String(tier_reward_profile["library_slots"][0]) == "TuNaShu2",
		"Level two unlocks tier-two Tuna before selected-sect cards"
	)
	var reward_rng := RandomNumberGenerator.new()
	reward_rng.seed = 2902
	var post_tier_reward: Dictionary = store.create_reward_offer_and_save(
		tier_reward_profile,
		Store.REWARD_VICTORY,
		reward_rng
	)
	_check(bool(post_tier_reward.get("ok", false)), "Post-tier reward offer saves")
	_check(
		&"CangSongYingKe2" not in (
			post_tier_reward.get("reward_ids", []) as Array
		)
		and &"TuNaShu2" not in (post_tier_reward.get("reward_ids", []) as Array),
		"Automatic Tuna and sect unlocks are excluded from the following reward offer"
	)

	var progression_profile: Dictionary = active_profile
	var previous_enemy_id: StringName = first_enemy_id
	for expected_level: int in range(2, 16):
		var expected_added_ids: Array = []
		if Store.tier_for_level(expected_level) > Store.tier_for_level(expected_level - 1):
			var before_ids: Array[StringName] = store.get_unlocked_ids(progression_profile)
			var entered_tier: int = Store.tier_for_level(expected_level)
			if entered_tier == 2 and &"TuNaShu2" not in before_ids:
				expected_added_ids.append(&"TuNaShu2")
			elif entered_tier == 3 and &"TuNaShu3" not in before_ids:
				expected_added_ids.append(&"TuNaShu3")
			for card_id: StringName in Cards.get_all_card_ids():
				var definition: Dictionary = Cards.get_definition(card_id)
				if (
					String(definition.get("sect", "")) == "华山派"
					and int(definition.get("tier", 0)) == entered_tier
					and card_id not in before_ids
				):
					expected_added_ids.append(card_id)
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
		_check(
			store.get_remembered_enemy_glyphs(progression_profile).is_empty(),
			"Changing to level %d clears remembered enemy cards" % expected_level
		)
		_check(
			(advance_result.get("added_ids", []) as Array) == expected_added_ids,
			"Level %d reports ordered Tuna and exact-tier sect unlocks: actual=%s expected=%s"
			% [expected_level, str(advance_result.get("added_ids", [])), str(expected_added_ids)]
		)
		for unlocked_id: StringName in expected_added_ids:
			_check(
				unlocked_id in store.get_unlocked_ids(progression_profile),
				"Level %d owns automatic sect card %s" % [expected_level, unlocked_id]
			)
		if not expected_added_ids.is_empty():
			_check(
				(progression_profile["library_slots"] as Array).slice(
					0, expected_added_ids.size()
				) == _strings(expected_added_ids),
				"Level %d inserts automatic unlocks at the library top in request order"
				% expected_level
			)
	var capped_result: Dictionary = store.advance_after_victory_and_save(progression_profile)
	_check(bool(capped_result.get("ok", false)), "A level-fifteen victory is a successful no-op")
	_check(not bool(capped_result.get("advanced", true)), "Level fifteen does not advance")
	var capped_profile: Dictionary = capped_result.get("profile", {})
	_check(
		store.get_character_level(capped_profile) == Store.MAX_CHARACTER_LEVEL,
		"Level-fifteen victory preserves the capped level"
	)
	_check(
		store.get_current_enemy_id(capped_profile)
		== store.get_current_enemy_id(progression_profile),
		"Level-fifteen victory preserves the current opponent"
	)
	var capped_enemy: Dictionary = Enemies.get_definition(
		store.get_current_enemy_id(progression_profile)
	)
	var capped_enemy_sect := StringName(String(capped_enemy.get("sect_id", "")))
	if capped_enemy_sect != &"":
		_check(
			capped_enemy_sect in store.get_unlocked_sect_ids(capped_profile),
			"Level-fifteen victory still unlocks the defeated enemy's declared sect"
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
		15: 5,
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
	var failed_difficulty_save: Dictionary = (
		failing_store.set_last_selected_difficulty_and_save(saved_before_failure, 0)
	)
	_check(
		not bool(failed_difficulty_save.get("ok", true))
		and failed_difficulty_save.get("profile", {}) == saved_before_failure,
		"Difficulty-selection save failure reports and rolls back"
	)
	var failed_batch: Dictionary = failing_store.unlock_cards_and_save(
		saved_before_failure,
		[&"CangSongYingKe1"]
	)
	_check(not bool(failed_batch.get("ok", true)), "Batch save failure is reported")
	_check(failed_batch.get("profile", {}) == saved_before_failure, "Batch save failure rolls back candidate data")
	var failed_begin: Dictionary = failing_store.begin_run_and_save(
		saved_before_failure,
		&"HuaShanPai",
		[]
	)
	_check(not bool(failed_begin.get("ok", true)), "Run-start save failure is reported")
	_check(failed_begin.get("profile", {}) == saved_before_failure, "Run-start save failure rolls back")
	var failed_advance: Dictionary = failing_store.advance_after_victory_and_save(
		active_profile,
		&"tieshan_menren"
	)
	_check(not bool(failed_advance.get("ok", true)), "Progression save failure is reported")
	_check(
		failed_advance.get("profile", {}) == active_profile,
		"Progression save failure rolls back level, enemy, and automatic unlocks"
	)
	var failed_completion: Dictionary = failing_store.record_completed_duel_and_save(
		active_profile,
		Store.REWARD_VICTORY,
		1
	)
	_check(not bool(failed_completion.get("ok", true)), "Completion save failure is reported")
	_check(
		failed_completion.get("profile", {}) == active_profile,
		"Completion save failure rolls back the run and retained progress"
	)
	var failed_reset: Dictionary = failing_store.reset_run_and_save(saved_before_failure)
	_check(not bool(failed_reset.get("ok", true)), "Run-reset save failure is reported")
	_check(failed_reset.get("profile", {}) == saved_before_failure, "Run-reset save failure rolls back")
	var failed_full_reset: Dictionary = failing_store.reset_all_progress_and_save(saved_before_failure)
	_check(not bool(failed_full_reset.get("ok", true)), "Full-reset save failure is reported")
	_check(failed_full_reset.get("profile", {}) == saved_before_failure, "Full-reset save failure rolls back")
	var failed_progression_unlock: Dictionary = failing_store.unlock_all_progression_and_save(
		saved_before_failure
	)
	_check(not bool(failed_progression_unlock.get("ok", true)), "Progression-unlock save failure is reported")
	_check(
		failed_progression_unlock.get("profile", {}) == saved_before_failure,
		"Progression-unlock save failure rolls back"
	)

	_cleanup()
	_finish()


func _occupied_count(slots: Array) -> int:
	var count: int = 0
	for value: Variant in slots:
		if not String(value).is_empty():
			count += 1
	return count


func _occupied_values(slots: Array) -> Array:
	var result: Array = []
	for value: Variant in slots:
		var card_id: String = String(value)
		if not card_id.is_empty():
			result.append(card_id)
	return result


func _profile_with_locked_cards(
	store: RefCounted,
	card_ids: Array[StringName]
) -> Dictionary:
	var profile: Dictionary = _legacy_collection_profile(store)
	var unlocked: Array = (profile["unlocked_card_ids"] as Array).duplicate()
	var occupied: Array = _occupied_values(profile["library_slots"])
	for card_id: StringName in card_ids:
		unlocked.erase(String(card_id))
		occupied.erase(String(card_id))
	profile["unlocked_card_ids"] = unlocked
	while occupied.size() < Store.LIBRARY_CAPACITY:
		occupied.append("")
	profile["library_slots"] = occupied
	_check(
		store.is_profile_valid(profile),
		"Locked-card fixture remains valid for %s" % str(card_ids)
	)
	return profile


func _legacy_collection_profile(store: RefCounted) -> Dictionary:
	var profile: Dictionary = store.create_default_profile()
	var unlocked: Array[StringName] = []
	for card_id: StringName in Cards.get_all_card_ids():
		if card_id not in Store.DEFAULT_LOCKED_IDS:
			unlocked.append(card_id)
	var library: Array = []
	for card_id: StringName in unlocked:
		if card_id not in LEGACY_MAIN_DECK_IDS:
			library.append(String(card_id))
	profile["unlocked_card_ids"] = _strings(unlocked)
	profile["main_deck"] = _strings(LEGACY_MAIN_DECK_IDS)
	while library.size() < Store.LIBRARY_CAPACITY:
		library.append("")
	profile["library_slots"] = library
	_check(store.is_profile_valid(profile), "Legacy collection fixture is valid")
	return profile


func _strings(values: Array) -> Array:
	var result: Array = []
	for value: Variant in values:
		result.append(String(value))
	return result


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
