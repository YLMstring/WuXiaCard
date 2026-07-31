extends SceneTree

const Store = preload("res://scripts/deck_profile_store.gd")
const Enemies = preload("res://scripts/enemy_catalog.gd")
const Cards = preload("res://scripts/card_catalog.gd")

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
	_check(int(profile["schema_version"]) == 6, "Default profile uses schema version 6")
	_check(not bool(profile["run_active"]), "Default profile has no active run")
	_check(String(profile["selected_sect_id"]).is_empty(), "Default profile has no selected sect")
	_check(store.get_character_level(profile) == 0, "New profiles begin at character level zero")
	_check(store.get_character_tier(profile) == 1, "Character tier begins at one")
	_check(store.get_current_enemy_id(profile) == &"", "Inactive profiles have no enemy")
	_check(store.get_remembered_enemy_glyphs(profile).is_empty(), "New profiles remember no enemy cards")
	_check(store.get_pending_reward_ids(profile).is_empty(), "New profiles have no pending reward")
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
	_check(int(migrated["schema_version"]) == 6, "Migration advances the schema version")
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
		[&"hanfeng_liezhen"],
		&"qingfeng_xuedi"
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
		store.get_selected_sect_id(active_profile) == &"xuanyue_jianzong",
		"Beginning a run records the selected sect"
	)
	_check(
		String(active_profile["library_slots"][0]) == "hanfeng_liezhen",
		"Newly unlocked run cards appear at the top of the library"
	)
	_check(
		(begin_result.get("added_ids", []) as Array) == [&"hanfeng_liezhen"],
		"Run start reports every newly owned sect card"
	)

	var reward_family_source: Dictionary = _profile_with_locked_cards(
		store,
		[&"CangSongYingKe1", &"CangSongYingKe3", &"CangSongYingKe4"]
	)
	var reward_family_begin: Dictionary = store.begin_run_and_save(
		reward_family_source,
		&"xuanyue_jianzong",
		[&"hanfeng_liezhen"],
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
		== "CangSongYingKe1"
		and String(reward_family_result["library_slots"][2 + reward_family_before.size()])
		== "CangSongYingKe3",
		"Reward inheritance appends lower-tier namesakes at the bottom"
	)
	_check(
		store.get_pending_reward_ids(reward_family_result).is_empty(),
		"Successful cascading reward claim clears the pending offer"
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
	_check(
		store.get_remembered_enemy_glyphs(migrated_active).is_empty(),
		"Legacy active runs begin with no remembered cards"
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

	var tier_reward_advance: Dictionary = store.advance_after_victory_and_save(
		active_profile,
		&"tieshan_menren"
	)
	var tier_reward_profile: Dictionary = tier_reward_advance.get(
		"profile",
		active_profile
	)
	_check(
		&"huixue_liuguang" in store.get_unlocked_ids(tier_reward_profile),
		"Level-two progression owns the selected sect's tier-two card"
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
		&"huixue_liuguang" not in (
			post_tier_reward.get("reward_ids", []) as Array
		),
		"Automatic tier unlock is excluded from the following reward offer"
	)

	var progression_profile: Dictionary = active_profile
	var previous_enemy_id: StringName = first_enemy_id
	var expected_tier_unlocks: Dictionary = {
		2: [&"huixue_liuguang"],
		5: [&"qiyao_lianfeng"],
		8: [],
		11: [&"wanyue_guizong"],
	}
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
		_check(
			store.get_remembered_enemy_glyphs(progression_profile).is_empty(),
			"Changing to level %d clears remembered enemy cards" % expected_level
		)
		var expected_added_ids: Array = expected_tier_unlocks.get(expected_level, [])
		_check(
			(advance_result.get("added_ids", []) as Array) == expected_added_ids,
			"Level %d reports only its exact-tier sect unlocks" % expected_level
		)
		for unlocked_id: StringName in expected_added_ids:
			_check(
				unlocked_id in store.get_unlocked_ids(progression_profile),
				"Level %d owns automatic sect card %s" % [expected_level, unlocked_id]
			)
		if not expected_added_ids.is_empty():
			_check(
				String(progression_profile["library_slots"][0])
				== String(expected_added_ids[0]),
				"Level %d inserts automatic sect cards at the library top"
				% expected_level
			)
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
	var failed_advance: Dictionary = failing_store.advance_after_victory_and_save(
		active_profile,
		&"tieshan_menren"
	)
	_check(not bool(failed_advance.get("ok", true)), "Progression save failure is reported")
	_check(
		failed_advance.get("profile", {}) == active_profile,
		"Progression save failure rolls back level, enemy, and automatic unlocks"
	)
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
	var profile: Dictionary = store.create_default_profile()
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
