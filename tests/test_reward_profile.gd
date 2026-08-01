extends SceneTree

const Store = preload("res://scripts/deck_profile_store.gd")
const Cards = preload("res://scripts/card_catalog.gd")
const Enemies = preload("res://scripts/enemy_catalog.gd")

const SAVE_PATH: String = "user://reward_profile_test.json"

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var store := Store.new(SAVE_PATH)
	var profile: Dictionary = store.create_default_profile()
	_check(int(profile["schema_version"]) == 7, "Reward state advances the profile schema")
	_check(store.get_pending_reward_ids(profile).is_empty(), "Default profile has no pending reward")
	_check(store.save_profile(profile), "Reward fixture saves")
	var begin_result: Dictionary = store.begin_run_and_save(
		profile,
		&"xuanyue_jianzong",
		[],
		&"qingfeng_xuedi"
	)
	_check(bool(begin_result.get("ok", false)), "Reward fixture starts a run")
	profile = begin_result.get("profile", profile)

	var seeded_rng := RandomNumberGenerator.new()
	seeded_rng.seed = 771
	var victory_offer: Dictionary = store.create_reward_offer_and_save(
		profile,
		Store.REWARD_VICTORY,
		seeded_rng
	)
	_check(bool(victory_offer.get("ok", false)), "Victory offer saves")
	_check(bool(victory_offer.get("offered", false)), "Tier-one victory has eligible rewards")
	profile = victory_offer.get("profile", profile)
	var victory_ids: Array[StringName] = store.get_pending_reward_ids(profile)
	_check(victory_ids.size() == 3, "Victory offer selects three cards when available")
	_check(_all_unique(victory_ids), "Reward offer never repeats a card")
	for card_id: StringName in victory_ids:
		_check(
			int(Cards.get_definition(card_id)["tier"]) == 1,
			"Victory reward matches the player's tier"
		)
		_check(card_id not in store.get_unlocked_ids(begin_result["profile"]), "Victory reward was locked")

	var reroll_rng := RandomNumberGenerator.new()
	reroll_rng.seed = 999
	var repeated_offer: Dictionary = store.create_reward_offer_and_save(
		profile,
		Store.REWARD_VICTORY,
		reroll_rng
	)
	_check(bool(repeated_offer.get("ok", false)), "Existing offer resumes successfully")
	_check(
		store.get_pending_reward_ids(repeated_offer["profile"]) == victory_ids,
		"Existing pending offer cannot be rerolled"
	)

	var deck_before: Array[StringName] = store.get_main_deck_ids(profile)
	var library_before: Array = (profile["library_slots"] as Array).duplicate()
	var claimed_id: StringName = victory_ids[1]
	var claim_result: Dictionary = store.claim_pending_reward_and_save(profile, claimed_id)
	_check(bool(claim_result.get("ok", false)), "Pending reward can be claimed")
	profile = claim_result.get("profile", profile)
	_check(claimed_id in store.get_unlocked_ids(profile), "Claim unlocks the selected card")
	_check(store.get_pending_reward_ids(profile).is_empty(), "Claim clears the entire offer")
	_check(store.get_main_deck_ids(profile) == deck_before, "Claim leaves the main deck unchanged")
	_check(String(profile["library_slots"][0]) == String(claimed_id), "Claim inserts at library top")
	_check(
		String(profile["library_slots"][1]) == String(library_before[0]),
		"Existing library order follows the claimed card"
	)
	var invalid_claim: Dictionary = store.claim_pending_reward_and_save(profile, victory_ids[0])
	_check(not bool(invalid_claim.get("ok", true)), "A cleared offer cannot grant another card")

	var tier_one_loss_rng := RandomNumberGenerator.new()
	tier_one_loss_rng.seed = 212
	var tier_one_loss: Dictionary = store.create_reward_offer_and_save(
		profile,
		Store.REWARD_DEFEAT,
		tier_one_loss_rng
	)
	_check(bool(tier_one_loss.get("offered", false)), "Tier-one defeat still offers rewards")
	profile = tier_one_loss.get("profile", profile)
	var tier_one_loss_ids: Array[StringName] = store.get_pending_reward_ids(profile)
	for card_id: StringName in tier_one_loss_ids:
		_check(int(Cards.get_definition(card_id)["tier"]) == 1, "Tier-one defeat falls back to tier one")
	var tier_one_claim: Dictionary = store.claim_pending_reward_and_save(
		profile,
		tier_one_loss_ids[0]
	)
	profile = tier_one_claim.get("profile", profile)

	var remaining_tier_one: Array[StringName] = []
	for card_id: StringName in Cards.get_all_card_ids():
		if (
			int(Cards.get_definition(card_id)["tier"]) == 1
			and card_id not in store.get_unlocked_ids(profile)
		):
			remaining_tier_one.append(card_id)
	var unlock_tier_one: Dictionary = store.unlock_cards_and_save(profile, remaining_tier_one)
	_check(bool(unlock_tier_one.get("ok", false)), "Fixture unlocks remaining tier-one cards")
	profile = unlock_tier_one.get("profile", profile)
	var empty_offer: Dictionary = store.create_reward_offer_and_save(
		profile,
		Store.REWARD_VICTORY,
		tier_one_loss_rng
	)
	_check(bool(empty_offer.get("ok", false)), "Empty eligible pool is a successful no-op")
	_check(not bool(empty_offer.get("offered", true)), "Empty eligible pool skips reward selection")
	_check(store.get_pending_reward_ids(empty_offer["profile"]).is_empty(), "Empty pool saves no offer")

	for next_level: int in range(2, 6):
		var enemy_id: StringName = Enemies.get_enemy_ids_for_level(next_level)[0]
		var advance_result: Dictionary = store.advance_after_victory_and_save(profile, enemy_id)
		_check(bool(advance_result.get("ok", false)), "Fixture advances to level %d" % next_level)
		profile = advance_result.get("profile", profile)
	_check(store.get_character_tier(profile) == 3, "Level five fixture is tier three")

	var loss_rng := RandomNumberGenerator.new()
	loss_rng.seed = 314
	var loss_offer: Dictionary = store.create_reward_offer_and_save(
		profile,
		Store.REWARD_DEFEAT,
		loss_rng
	)
	_check(bool(loss_offer.get("ok", false)), "Defeat offer saves")
	profile = loss_offer.get("profile", profile)
	var loss_ids: Array[StringName] = store.get_pending_reward_ids(profile)
	_check(not loss_ids.is_empty(), "Tier-three defeat has lower-tier rewards")
	for card_id: StringName in loss_ids:
		var tier: int = int(Cards.get_definition(card_id)["tier"])
		_check(tier >= 1 and tier < 3, "Defeat reward comes from any lower tier")

	var schema_five: Dictionary = profile.duplicate(true)
	schema_five["schema_version"] = 5
	schema_five.erase("pending_reward_card_ids")
	var migrated: Dictionary = store.repair_profile(schema_five)
	_check(store.is_profile_valid(migrated), "Schema-five profile migrates")
	_check(store.get_pending_reward_ids(migrated).is_empty(), "Legacy profile gains no pending reward")

	var reset_result: Dictionary = store.reset_run_and_save(profile)
	_check(bool(reset_result.get("ok", false)), "Run reset succeeds with pending rewards")
	_check(
		store.get_pending_reward_ids(reset_result["profile"]).is_empty(),
		"Run reset clears pending rewards"
	)

	_cleanup()
	_finish()


func _all_unique(values: Array[StringName]) -> bool:
	var observed: Dictionary = {}
	for value: StringName in values:
		if observed.has(value):
			return false
		observed[value] = true
	return true


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	if _failures == 0:
		print("REWARD_PROFILE_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("REWARD_PROFILE_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
