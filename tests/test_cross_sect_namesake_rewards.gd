extends SceneTree

const Store = preload("res://scripts/deck_profile_store.gd")
const Cards = preload("res://scripts/card_catalog.gd")
const Enemies = preload("res://scripts/enemy_catalog.gd")
const DeckRules = preload("res://scripts/deck_rules.gd")
const SAVE_PATH: String = "user://cross_sect_namesake_rewards_test.json"
const HENGSHAN: Array[StringName] = [
	&"JinZhenDuJie1", &"JinZhenDuJie2", &"JinZhenDuJie3", &"JinZhenDuJie4",
]
const KUNLUN: Array[StringName] = [
	&"JinZhenDuJie1a", &"JinZhenDuJie2a", &"JinZhenDuJie3a", &"JinZhenDuJie4a",
]

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var store := Store.new(SAVE_PATH)
	_test_rewards(store, KUNLUN, HENGSHAN)
	_test_rewards(store, HENGSHAN, KUNLUN)
	_test_both_owned_and_pending_offer(store)
	_test_claim_inheritance_and_reload(store)
	_test_fixed_tier_unlock(store)
	_test_opening_and_owned_fallback(store)
	_test_save_failure(store)
	_cleanup()
	if _failures == 0:
		print("CROSS_SECT_NAMESAKE_REWARDS_PASSED checks=%d" % _checks)
	else:
		push_error("CROSS_SECT_NAMESAKE_REWARDS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _test_rewards(store: RefCounted, own: Array[StringName], other: Array[StringName]) -> void:
	for level: int in [2, 5, 8]:
		var tier: int = Store.tier_for_level(level)
		var profile: Dictionary = _full_collection_profile(store, level)
		_lock_cards(profile, other)
		_lock_cards(profile, own.slice(1))
		_lock_cards(profile, [&"TuNaShu2"])
		_check(store.is_profile_valid(profile), "Cross-sect tier-%d fixture validates" % tier)
		for outcome: StringName in [Store.REWARD_VICTORY, Store.REWARD_DEFEAT]:
			var offer: Dictionary = store.create_reward_offer_and_save(profile, outcome, _rng(800 + level))
			var ids: Array[StringName] = store.get_pending_reward_ids(offer.get("profile", {}))
			_check(bool(offer.get("ok", false)) and not ids.is_empty(), "Namesake filtering retains eligible rewards")
			var found_other: bool = false
			for id: StringName in ids:
				found_other = found_other or id in other
			_check(not found_other, "Owned tier one excludes every other-sect tier from %s" % outcome)
			if outcome == Store.REWARD_VICTORY:
				_check(own[tier - 1] in ids, "Same-sect higher-tier reward remains eligible")
				if tier == 2:
					_check(&"TuNaShu2" in ids and ids.size() == 2, "Different glyph remains eligible after cross-sect filtering")


func _test_both_owned_and_pending_offer(store: RefCounted) -> void:
	var profile: Dictionary = _full_collection_profile(store, 2)
	_lock_cards(profile, HENGSHAN.slice(1))
	_lock_cards(profile, KUNLUN.slice(1))
	_lock_cards(profile, [&"TuNaShu2"])
	var before: Dictionary = profile.duplicate(true)
	var offer: Dictionary = store.create_reward_offer_and_save(profile, Store.REWARD_VICTORY, _rng(840))
	_check(store.get_pending_reward_ids(offer.get("profile", {})) == [&"TuNaShu2"], "Two owned sects exclude both future namesake families")
	_check(profile == before, "Reward creation preserves its input profile")
	_check(store.get_unlocked_ids(offer.get("profile", {})) == store.get_unlocked_ids(before), "Existing cross-sect unlocks are preserved")
	profile["pending_reward_card_ids"] = ["JinZhenDuJie2"]
	var resumed: Dictionary = store.create_reward_offer_and_save(profile, Store.REWARD_VICTORY, _rng(841))
	_check(store.get_pending_reward_ids(resumed.get("profile", {})) == [&"JinZhenDuJie2"], "Previously saved pending offer is preserved")


func _test_claim_inheritance_and_reload(store: RefCounted) -> void:
	var profile: Dictionary = _full_collection_profile(store, 2)
	_lock_cards(profile, HENGSHAN)
	_lock_cards(profile, KUNLUN)
	_lock_cards(profile, [&"TuNaShu2"])
	profile["pending_reward_card_ids"] = ["JinZhenDuJie3a"]
	var claim: Dictionary = store.claim_pending_reward_and_save(profile, &"JinZhenDuJie3a")
	_check(bool(claim.get("ok", false)), "A namesake reward can be claimed")
	var claimed: Dictionary = claim.get("profile", {})
	var unlocked: Array[StringName] = store.get_unlocked_ids(claimed)
	_check(&"JinZhenDuJie1a" in unlocked and &"JinZhenDuJie2a" in unlocked, "Claim inherits lower same-sect tiers")
	_check(&"JinZhenDuJie1" not in unlocked, "Claim does not inherit other-sect namesakes")
	var loaded: Dictionary = Store.new(SAVE_PATH).load_profile_read_only()
	_check(loaded == claimed, "Namesake unlock persists without extra state")
	var offer: Dictionary = store.create_reward_offer_and_save(loaded, Store.REWARD_VICTORY, _rng(850))
	_check(store.get_pending_reward_ids(offer.get("profile", {})) == [&"TuNaShu2"], "Reloaded inherited unlocks filter future random rewards")
	var reset: Dictionary = store.reset_run_and_save(claimed)
	_check(bool(reset.get("ok", false)) and &"JinZhenDuJie1a" not in store.get_unlocked_ids(reset.get("profile", {})), "Run reset clears its acquired namesake ownership")
	var restarted_source: Dictionary = reset.get("profile", {})
	var eligible_again: bool = false
	var no_pending_sect_ids: Array[StringName] = []
	for seed: int in range(24):
		var random_ids: Array[StringName] = store._pick_starting_tier_one_ids(restarted_source, no_pending_sect_ids, _rng(seed), false)
		eligible_again = eligible_again or &"JinZhenDuJie1" in random_ids
	_check(eligible_again, "Reset leaves no stale cross-sect exclusion")


func _test_fixed_tier_unlock(store: RefCounted) -> void:
	var profile: Dictionary = _full_collection_profile(store, 1)
	profile["selected_sect_id"] = "HengShanPai"
	profile["unlocked_sect_ids"].append("HengShanPai")
	profile["run_sect_pool_ids"] = ["HuaShanPai", "ShaoLinPai", "WuDangPai", "TaiShanPai", "SongShanPai"]
	_lock_cards(profile, HENGSHAN.slice(1))
	_lock_cards(profile, KUNLUN.slice(1))
	_lock_cards(profile, [&"TuNaShu2"])
	var advanced: Dictionary = store.advance_after_victory_and_save(profile, Enemies.get_enemy_ids_for_level(2)[0])
	_check(bool(advanced.get("ok", false)), "Fixed-tier advancement succeeds with an owned other-sect namesake")
	_check(&"JinZhenDuJie2" in store.get_unlocked_ids(advanced.get("profile", {})), "Fixed selected-sect tier unlock ignores random exclusion")
	var offer: Dictionary = store.create_reward_offer_and_save(advanced.get("profile", {}), Store.REWARD_VICTORY, _rng(860))
	_check(&"JinZhenDuJie2a" not in store.get_pending_reward_ids(offer.get("profile", {})), "Fixed unlock excludes other-sect random reward")


func _test_opening_and_owned_fallback(store: RefCounted) -> void:
	var source: Dictionary = store.create_default_profile()
	var all_owned: Dictionary = _full_collection_profile(store, 1)
	var correct_openings: bool = true
	var correct_fallbacks: bool = true
	var pending_kunlun_ids: Array[StringName] = [KUNLUN[0]]
	for seed: int in range(24):
		var ids: Array[StringName] = store._pick_starting_tier_one_ids(source, pending_kunlun_ids, _rng(seed), false)
		correct_openings = correct_openings and ids.size() == 3 and HENGSHAN[0] not in ids and DeckRules.has_unique_glyphs(ids)
		for allow_owned: bool in [false, true]:
			var fallback: Array[StringName] = store._pick_starting_tier_one_ids(all_owned, pending_kunlun_ids, _rng(seed), allow_owned)
			correct_fallbacks = correct_fallbacks and fallback.size() == 3 and HENGSHAN[0] not in fallback and DeckRules.has_unique_glyphs(fallback)
	_check(correct_openings, "Pending Kunlun tier-one unlock filters opening namesakes before save")
	_check(correct_fallbacks, "Owned opening fallback cannot reintroduce other-sect namesakes")
	var excluded_opening_ids: Array[StringName] = Cards.get_all_card_ids()
	var source_before_exhaustion: Dictionary = source.duplicate(true)
	_check(store._pick_starting_tier_one_ids(source, excluded_opening_ids, _rng(870), true).is_empty(), "An exhausted opening pool does not relax exclusions")
	_check(source == source_before_exhaustion, "An exhausted opening selection preserves input state")
	source["unlocked_sect_ids"].append("HengShanPai")
	var original: Dictionary = source.duplicate(true)
	var begun: Dictionary = store.begin_run_and_save(source, &"HengShanPai", [], &"qingfeng_xuedi", _rng(871))
	_check(bool(begun.get("ok", false)), "Hengshan production opening succeeds")
	var begun_profile: Dictionary = begun.get("profile", {})
	_check(HENGSHAN[0] in store.get_unlocked_ids(begun_profile), "Selected sect tier one unlocks at opening")
	_check(KUNLUN[0] not in store.get_main_deck_ids(begun_profile), "Selected-sect unlock excludes Kunlun from opening main deck")
	_check(DeckRules.has_unique_glyphs(store.get_main_deck_ids(begun_profile)), "All five opening main cards have distinct names")
	_check(source == original, "Opening selection preserves caller state until save")


func _test_save_failure(store: RefCounted) -> void:
	var profile: Dictionary = _full_collection_profile(store, 2)
	_lock_cards(profile, HENGSHAN)
	_lock_cards(profile, KUNLUN.slice(1))
	_lock_cards(profile, [&"TuNaShu2"])
	var before: Dictionary = profile.duplicate(true)
	var failing := Store.new(SAVE_PATH + "/cannot_save.json")
	var offer: Dictionary = failing.create_reward_offer_and_save(profile, Store.REWARD_VICTORY, _rng(880))
	_check(not bool(offer.get("ok", true)) and offer.get("profile", {}) == before and profile == before, "Failed filtered reward save rolls back")
	var source: Dictionary = store.create_default_profile()
	source["unlocked_sect_ids"].append("HengShanPai")
	var source_before: Dictionary = source.duplicate(true)
	var begun: Dictionary = failing.begin_run_and_save(source, &"HengShanPai", [], &"qingfeng_xuedi", _rng(881))
	_check(not bool(begun.get("ok", true)) and begun.get("profile", {}) == source_before and source == source_before, "Failed filtered opening save rolls back")


func _full_collection_profile(store: RefCounted, level: int) -> Dictionary:
	var profile: Dictionary = store.create_testing_profile(store.create_default_profile())
	profile["main_deck"] = ["TaiZuChangQuan", "TuNaShu1", "CangSongYingKe1", "TaiShan18Pan1", "WuDaFuJian1"]
	var library: Array = []
	for id: StringName in store.get_unlocked_ids(profile):
		if String(id) not in profile["main_deck"]:
			library.append(String(id))
	library.resize(Store.LIBRARY_CAPACITY)
	for i: int in range(library.size()):
		if library[i] == null:
			library[i] = ""
	profile["library_slots"] = library
	profile["run_active"] = true
	profile["selected_sect_id"] = "HuaShanPai"
	profile["run_sect_pool_ids"] = ["ShaoLinPai", "WuDangPai", "TaiShanPai", "HengShanPai", "SongShanPai"]
	profile["level"] = level
	profile["current_enemy_id"] = String(Enemies.get_enemy_ids_for_level(level)[0])
	return profile


func _lock_cards(profile: Dictionary, ids: Array) -> void:
	for id: Variant in ids:
		(profile["unlocked_card_ids"] as Array).erase(String(id))
		var library: Array = profile["library_slots"]
		library.erase(String(id))
		library.append("")


func _rng(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 1
	return rng


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("CHECK_FAILED: " + message)
