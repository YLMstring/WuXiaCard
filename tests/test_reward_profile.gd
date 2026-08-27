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
	_check(int(profile["schema_version"]) == 11, "Reward state advances the profile schema")
	_check(store.get_pending_reward_ids(profile).is_empty(), "Default profile has no pending reward")
	_check(store.save_profile(profile), "Reward fixture saves")
	var begin_result: Dictionary = store.begin_run_and_save(
		profile,
		&"HuaShanPai",
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

	var tier_five_profile: Dictionary = store.create_testing_profile(
		store.create_default_profile()
	)
	tier_five_profile["run_active"] = true
	tier_five_profile["selected_sect_id"] = "HuaShanPai"
	tier_five_profile["level"] = 11
	tier_five_profile["current_enemy_id"] = String(
		Enemies.get_enemy_ids_for_level(11)[0]
	)
	for special_id: StringName in [&"KuiHua2", &"KuiHua3", &"KuiHua4"]:
		(tier_five_profile["unlocked_card_ids"] as Array).erase(String(special_id))
		(tier_five_profile["library_slots"] as Array).erase(String(special_id))
		(tier_five_profile["library_slots"] as Array).append("")
	for card_id: StringName in Cards.get_all_card_ids():
		if (
			int(Cards.get_definition(card_id).get("tier", 0)) == 5
			and card_id not in tier_five_profile["unlocked_card_ids"]
		):
			(tier_five_profile["unlocked_card_ids"] as Array).append(String(card_id))
			(tier_five_profile["library_slots"] as Array).push_front(String(card_id))
			(tier_five_profile["library_slots"] as Array).pop_back()
	_check(store.is_profile_valid(tier_five_profile), "Tier-five special reward fixture is valid")
	_check(store.save_profile(tier_five_profile), "Tier-five special reward fixture saves")
	var tier_five_rng := RandomNumberGenerator.new()
	tier_five_rng.seed = 515
	var tier_five_offer: Dictionary = store.create_reward_offer_and_save(
		tier_five_profile,
		Store.REWARD_VICTORY,
		tier_five_rng
	)
	var tier_five_reward_ids: Array[StringName] = store.get_pending_reward_ids(
		tier_five_offer.get("profile", {})
	)
	tier_five_reward_ids.sort()
	var expected_special_ids: Array[StringName] = [&"KuiHua2", &"KuiHua3", &"KuiHua4"]
	expected_special_ids.sort()
	_check(
		bool(tier_five_offer.get("offered", false))
		and tier_five_reward_ids == expected_special_ids,
		"KuiHua2-4 can fill a tier-five victory reward offer while remaining tier one"
	)
	for special_id: StringName in expected_special_ids:
		_check(
			int(Cards.get_definition(special_id).get("tier", 0)) == 1,
			"%s keeps its real tier-one identity" % special_id
		)

	_test_kuihua_zero_defeat_guarantee(store)

	_cleanup()
	_finish()


func _test_kuihua_zero_defeat_guarantee(store: RefCounted) -> void:
	var qualifying: Dictionary = store.create_testing_profile(store.create_default_profile())
	qualifying["run_active"] = true
	qualifying["selected_sect_id"] = "HuaShanPai"
	qualifying["level"] = 11
	qualifying["current_enemy_id"] = String(Enemies.get_enemy_ids_for_level(11)[0])
	qualifying["pending_reward_card_ids"] = []
	qualifying["shown_guaranteed_reward_card_ids"] = []
	for locked_id: StringName in [
		&"KuiHua0",
		&"CangSongYingKe4",
		&"WanYueChaoZong4",
	]:
		_lock_library_card(qualifying, locked_id)
	_check(store.is_profile_valid(qualifying), "KuiHua0 guarantee fixture is valid")

	var tier_four: Dictionary = qualifying.duplicate(true)
	tier_four["level"] = 8
	tier_four["current_enemy_id"] = String(Enemies.get_enemy_ids_for_level(8)[0])
	var tier_four_offer: Dictionary = store.create_reward_offer_and_save(
		tier_four,
		Store.REWARD_DEFEAT,
		_seeded_rng(800)
	)
	_check(
		&"KuiHua0" not in store.get_pending_reward_ids(tier_four_offer.get("profile", {})),
		"KuiHua0 cannot appear before character tier five"
	)

	var no_gate: Dictionary = qualifying.duplicate(true)
	_replace_main_deck_card(no_gate, &"KuiHua1", &"TaiZuChangQuan")
	for gated_id: StringName in [&"KuiHua1", &"KuiHua2", &"KuiHua3", &"KuiHua4"]:
		_lock_library_card(no_gate, gated_id)
	_check(store.is_profile_valid(no_gate), "No-self-castration guarantee fixture is valid")
	var no_gate_offer: Dictionary = store.create_reward_offer_and_save(
		no_gate,
		Store.REWARD_DEFEAT,
		_seeded_rng(801)
	)
	_check(
		&"KuiHua0" not in store.get_pending_reward_ids(no_gate_offer.get("profile", {})),
		"KuiHua0 requires at least one unlocked self-castration card"
	)

	var first_offer: Dictionary = store.create_reward_offer_and_save(
		qualifying,
		Store.REWARD_DEFEAT,
		_seeded_rng(802)
	)
	var first_profile: Dictionary = first_offer.get("profile", {})
	var first_ids: Array[StringName] = store.get_pending_reward_ids(first_profile)
	_check(
		bool(first_offer.get("offered", false))
		and first_ids.size() == 3
		and &"KuiHua0" in first_ids,
		"The first qualifying tier-five defeat guarantees KuiHua0 among three choices"
	)
	_check(
		first_profile["shown_guaranteed_reward_card_ids"] == ["KuiHua0"],
		"Creating the guarantee records KuiHua0 as shown for this run"
	)
	var resumed_offer: Dictionary = store.create_reward_offer_and_save(
		first_profile,
		Store.REWARD_DEFEAT,
		_seeded_rng(999)
	)
	_check(
		store.get_pending_reward_ids(resumed_offer.get("profile", {})) == first_ids
		and resumed_offer["profile"]["shown_guaranteed_reward_card_ids"] == ["KuiHua0"],
		"Reopening a pending guarantee preserves its choices and single shown record"
	)
	var observed_positions: Dictionary = {}
	for seed: int in range(810, 820):
		var positioned_offer: Dictionary = store.create_reward_offer_and_save(
			qualifying,
			Store.REWARD_DEFEAT,
			_seeded_rng(seed)
		)
		var positioned_ids: Array[StringName] = store.get_pending_reward_ids(
			positioned_offer.get("profile", {})
		)
		observed_positions[positioned_ids.find(&"KuiHua0")] = true
	_check(observed_positions.size() > 1, "KuiHua0 has no fixed position in the reward choices")
	var claim_kuihua_zero: Dictionary = store.claim_pending_reward_and_save(
		first_profile,
		&"KuiHua0"
	)
	var after_kuihua_zero: Dictionary = claim_kuihua_zero.get("profile", {})
	var unlocked_repeat: Dictionary = store.create_reward_offer_and_save(
		after_kuihua_zero,
		Store.REWARD_DEFEAT,
		_seeded_rng(804)
	)
	_check(
		bool(claim_kuihua_zero.get("ok", false))
		and &"KuiHua0" in store.get_unlocked_ids(after_kuihua_zero)
		and &"KuiHua0" not in store.get_pending_reward_ids(unlocked_repeat.get("profile", {})),
		"An unlocked KuiHua0 is never guaranteed again"
	)
	var other_reward_id: StringName = &""
	for reward_id: StringName in first_ids:
		if reward_id != &"KuiHua0":
			other_reward_id = reward_id
			break
	var claim_other: Dictionary = store.claim_pending_reward_and_save(
		first_profile,
		other_reward_id
	)
	var after_other: Dictionary = claim_other.get("profile", {})
	_check(bool(claim_other.get("ok", false)), "A non-KuiHua0 guaranteed offer choice can be claimed")
	_check(&"KuiHua0" not in store.get_unlocked_ids(after_other), "Skipping KuiHua0 leaves it locked")
	var repeated_offer: Dictionary = store.create_reward_offer_and_save(
		after_other,
		Store.REWARD_DEFEAT,
		_seeded_rng(803)
	)
	_check(
		&"KuiHua0" not in store.get_pending_reward_ids(repeated_offer.get("profile", {})),
		"A skipped KuiHua0 does not reappear later in the same run"
	)
	var reset_result: Dictionary = store.reset_run_and_save(after_other)
	_check(
		bool(reset_result.get("ok", false))
		and (reset_result["profile"]["shown_guaranteed_reward_card_ids"] as Array).is_empty(),
		"Closing the run clears shown guaranteed rewards for a future run"
	)
	var restarted_qualifying: Dictionary = qualifying.duplicate(true)
	restarted_qualifying["shown_guaranteed_reward_card_ids"] = (
		reset_result["profile"]["shown_guaranteed_reward_card_ids"] as Array
	).duplicate()
	var restarted_offer: Dictionary = store.create_reward_offer_and_save(
		restarted_qualifying,
		Store.REWARD_DEFEAT,
		_seeded_rng(805)
	)
	_check(
		&"KuiHua0" in store.get_pending_reward_ids(restarted_offer.get("profile", {})),
		"A later run can guarantee KuiHua0 again after the reset"
	)


func _lock_library_card(profile: Dictionary, card_id: StringName) -> void:
	(profile["unlocked_card_ids"] as Array).erase(String(card_id))
	var library: Array = profile["library_slots"] as Array
	var library_index: int = library.find(String(card_id))
	if library_index >= 0:
		library.remove_at(library_index)
		library.append("")


func _replace_main_deck_card(
	profile: Dictionary,
	removed_id: StringName,
	replacement_id: StringName
) -> void:
	var deck: Array = profile["main_deck"] as Array
	var removed_index: int = deck.find(String(removed_id))
	deck[removed_index] = String(replacement_id)
	(profile["library_slots"] as Array).erase(String(replacement_id))
	(profile["library_slots"] as Array).append("")


func _seeded_rng(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng


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
