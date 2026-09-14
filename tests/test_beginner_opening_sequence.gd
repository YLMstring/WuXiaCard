extends SceneTree

const Store = preload("res://scripts/deck_profile_store.gd")
const Enemies = preload("res://scripts/enemy_catalog.gd")
const Cards = preload("res://scripts/card_catalog.gd")

const SAVE_PATH: String = "user://beginner_opening_sequence_test.json"

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var store := Store.new(SAVE_PATH)
	var start_rng := RandomNumberGenerator.new()
	start_rng.seed = 9401
	var begin: Dictionary = store.begin_run_and_save(
		store.create_default_profile(),
		&"HuaShanPai",
		[],
		&"",
		start_rng
	)
	_check(bool(begin.get("ok", false)), "Huashan difficulty-zero run begins")
	var profile: Dictionary = begin.get("profile", {})
	_check(
		store.get_beginner_opening_stage(profile) == Store.BEGINNER_OPENING_LINGHU
		and store.get_current_enemy_id(profile) == Store.BEGINNER_LINGHU_ENEMY_ID
		and store.get_character_level(profile) == 1,
		"Huashan difficulty zero starts at the Linghu beginner duel"
	)
	_check(
		store.get_effective_duel_count(profile) == 0
		and store.get_defeated_enemy_ids(profile).is_empty(),
		"Beginner opening starts outside formal score history"
	)
	profile = store.load_profile()
	_check(
		store.get_beginner_opening_stage(profile) == Store.BEGINNER_OPENING_LINGHU
		and store.get_current_enemy_id(profile) == Store.BEGINNER_LINGHU_ENEMY_ID,
		"Saved beginner opening stage survives a real JSON reload"
	)

	var defeat: Dictionary = store.record_completed_duel_and_save(
		profile,
		Store.REWARD_DEFEAT
	)
	_check(bool(defeat.get("ok", false)), "Linghu defeat saves")
	profile = defeat.get("profile", profile)
	_check(
		store.get_beginner_opening_stage(profile) == Store.BEGINNER_OPENING_LINGHU
		and store.get_current_enemy_id(profile) == Store.BEGINNER_LINGHU_ENEMY_ID,
		"Linghu defeat keeps the same beginner duel"
	)
	_check(_has_no_formal_history(store, profile), "Linghu defeat does not affect score history")
	profile = _offer_and_claim_tier_one(store, profile, Store.REWARD_DEFEAT, 9402)

	var mastery_id: StringName = store.get_main_deck_ids(profile)[0]
	var linghu_win: Dictionary = store.record_completed_duel_and_save(
		profile,
		Store.REWARD_VICTORY,
		Store.DEFAULT_VICTORIES_REQUIRED,
		&"",
		[mastery_id]
	)
	_check(bool(linghu_win.get("ok", false)), "Linghu victory saves")
	profile = linghu_win.get("profile", profile)
	_check(
		bool(linghu_win.get("advanced", false))
		and store.get_beginner_opening_stage(profile) == Store.BEGINNER_OPENING_WUSHI
		and store.get_current_enemy_id(profile) == Store.BEGINNER_WUSHI_ENEMY_ID
		and store.get_character_level(profile) == 1,
		"Linghu victory advances to Jianghu Wushi without leveling"
	)
	_check(store.is_card_mastered(profile, mastery_id), "Beginner victory records card mastery")
	_check(_has_no_formal_history(store, profile), "Linghu victory does not affect score history")
	profile = _offer_and_claim_tier_one(store, profile, Store.REWARD_VICTORY, 9403)

	var wushi_defeat: Dictionary = store.record_completed_duel_and_save(
		profile,
		Store.REWARD_DEFEAT
	)
	profile = wushi_defeat.get("profile", profile)
	_check(
		bool(wushi_defeat.get("ok", false))
		and store.get_beginner_opening_stage(profile) == Store.BEGINNER_OPENING_WUSHI
		and store.get_current_enemy_id(profile) == Store.BEGINNER_WUSHI_ENEMY_ID,
		"Jianghu Wushi defeat keeps the same beginner duel"
	)
	_check(_has_no_formal_history(store, profile), "Wushi defeat does not affect score history")
	profile = _offer_and_claim_tier_one(store, profile, Store.REWARD_DEFEAT, 9404)

	var wushi_win: Dictionary = store.record_completed_duel_and_save(
		profile,
		Store.REWARD_VICTORY
	)
	profile = wushi_win.get("profile", profile)
	_check(
		bool(wushi_win.get("ok", false))
		and store.get_beginner_opening_stage(profile) == Store.BEGINNER_OPENING_NONE
		and store.get_current_enemy_id(profile) == Store.BEGINNER_FORMAL_ENEMY_ID
		and store.get_character_level(profile) == 1,
		"Wushi victory enters the formal Lin Pingzhi duel without leveling"
	)
	_check(_has_no_formal_history(store, profile), "Wushi victory does not affect formal history")
	profile = _offer_and_claim_tier_one(store, profile, Store.REWARD_VICTORY, 9405)

	var formal_win: Dictionary = store.record_completed_duel_and_save(
		profile,
		Store.REWARD_VICTORY,
		Store.DEFAULT_VICTORIES_REQUIRED,
		&"tieshan_menren"
	)
	profile = formal_win.get("profile", profile)
	_check(
		bool(formal_win.get("ok", false))
		and store.get_character_level(profile) == 2
		and store.get_current_enemy_id(profile) == &"tieshan_menren",
		"Defeating Lin Pingzhi resumes normal level-two progression"
	)
	_check(
		store.get_effective_duel_count(profile) == 1
		and store.get_defeated_enemy_ids(profile) == [&"qingfeng_xuedi"],
		"Lin Pingzhi is the first scored duel and first ending-history enemy"
	)

	var migrated_source: Dictionary = begin.get("profile", {}).duplicate(true)
	migrated_source["schema_version"] = 14
	migrated_source.erase("beginner_opening_stage")
	var migrated: Dictionary = store.repair_profile(migrated_source)
	_check(
		store.is_profile_valid(migrated)
		and store.get_beginner_opening_stage(migrated) == Store.BEGINNER_OPENING_NONE
		and store.get_current_enemy_id(migrated) != Store.BEGINNER_LINGHU_ENEMY_ID,
		"Old active saves migrate without being inserted into the beginner opening"
	)

	var invalid_stage: Dictionary = begin.get("profile", {}).duplicate(true)
	invalid_stage["beginner_opening_stage"] = Store.BEGINNER_OPENING_WUSHI
	_check(not store.is_profile_valid(invalid_stage), "Stage and fixed enemy must match")
	var invalid_history: Dictionary = begin.get("profile", {}).duplicate(true)
	invalid_history["effective_duel_count"] = 1
	_check(not store.is_profile_valid(invalid_history), "Beginner stages reject formal duel history")

	var reset: Dictionary = store.reset_run_and_save(begin.get("profile", {}))
	_check(
		bool(reset.get("ok", false))
		and store.get_beginner_opening_stage(reset.get("profile", {}))
		== Store.BEGINNER_OPENING_NONE,
		"Run reset clears the beginner opening"
	)

	_check_non_beginner_starts()
	_finish()


func _offer_and_claim_tier_one(
	store: RefCounted,
	profile: Dictionary,
	outcome: StringName,
	seed_value: int
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var offer: Dictionary = store.create_reward_offer_and_save(profile, outcome, rng)
	_check(bool(offer.get("ok", false)), "Beginner reward offer saves")
	var offered_profile: Dictionary = offer.get("profile", profile)
	var reward_ids: Array[StringName] = store.get_pending_reward_ids(offered_profile)
	_check(not reward_ids.is_empty(), "Beginner duel offers at least one reward")
	for card_id: StringName in reward_ids:
		_check(int(Cards.get_definition(card_id).get("tier", 0)) == 1, "%s is tier one" % card_id)
	if reward_ids.is_empty():
		return offered_profile
	var claim: Dictionary = store.claim_pending_reward_and_save(offered_profile, reward_ids[0])
	_check(bool(claim.get("ok", false)), "Beginner tier-one reward can be claimed")
	return claim.get("profile", offered_profile)


func _has_no_formal_history(store: RefCounted, profile: Dictionary) -> bool:
	return (
		store.get_effective_duel_count(profile) == 0
		and store.get_defeated_enemy_ids(profile).is_empty()
	)


func _check_non_beginner_starts() -> void:
	var other_store := Store.new("user://beginner_opening_other_sect_test.json")
	var other_profile: Dictionary = other_store.create_default_profile()
	(other_profile["unlocked_sect_ids"] as Array).append("TaiShanPai")
	var other_begin: Dictionary = other_store.begin_run_and_save(
		other_profile,
		&"TaiShanPai",
		[]
	)
	_check(
		bool(other_begin.get("ok", false))
		and other_store.get_beginner_opening_stage(other_begin.get("profile", {}))
		== Store.BEGINNER_OPENING_NONE,
		"Other sects at difficulty zero use the ordinary opening"
	)
	_check(
		other_store.get_current_enemy_id(other_begin.get("profile", {}))
		in Enemies.get_enemy_ids_for_level(1),
		"Other sects begin against an ordinary level-one enemy"
	)

	var higher_store := Store.new("user://beginner_opening_higher_difficulty_test.json")
	var higher_profile: Dictionary = higher_store.create_default_profile()
	higher_profile["max_unlocked_difficulty"] = 1
	var higher_begin: Dictionary = higher_store.begin_run_and_save(
		higher_profile,
		&"HuaShanPai",
		[],
		&"",
		null,
		false,
		1
	)
	_check(
		bool(higher_begin.get("ok", false))
		and higher_store.get_beginner_opening_stage(higher_begin.get("profile", {}))
		== Store.BEGINNER_OPENING_NONE,
		"Huashan above difficulty zero uses the ordinary opening"
	)
	_check(
		higher_store.get_current_enemy_id(higher_begin.get("profile", {}))
		in Enemies.get_enemy_ids_for_level(1),
		"Higher-difficulty Huashan begins against an ordinary level-one enemy"
	)
	_cleanup_path("user://beginner_opening_other_sect_test.json")
	_cleanup_path("user://beginner_opening_higher_difficulty_test.json")


func _cleanup() -> void:
	_cleanup_path(SAVE_PATH)
	_cleanup_path("user://beginner_opening_other_sect_test.json")
	_cleanup_path("user://beginner_opening_higher_difficulty_test.json")


func _cleanup_path(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var candidate: String = path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func _finish() -> void:
	_cleanup()
	if _failures == 0:
		print("BEGINNER_OPENING_SEQUENCE_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"BEGINNER_OPENING_SEQUENCE_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
