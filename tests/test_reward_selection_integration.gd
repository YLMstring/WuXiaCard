extends SceneTree

const REWARD_SCENE: PackedScene = preload("res://scenes/reward_selection.tscn")
const Store = preload("res://scripts/deck_profile_store.gd")
const Enemies = preload("res://scripts/enemy_catalog.gd")

const SAVE_PATH: String = "user://reward_selection_test.json"

var _checks: int = 0
var _failures: int = 0
var _claim_count: int = 0
var _back_count: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var store := Store.new(SAVE_PATH)
	var profile: Dictionary = store.create_default_profile()
	_check(store.save_profile(profile), "Reward-scene fixture saves")
	var begin_result: Dictionary = store.begin_run_and_save(
		profile,
		&"xuanyue_jianzong",
		[],
		&"qingfeng_xuedi"
	)
	profile = begin_result.get("profile", profile)
	for next_level: int in range(2, 12):
		var advance_result: Dictionary = store.advance_after_victory_and_save(
			profile,
			Enemies.get_enemy_ids_for_level(next_level)[0]
		)
		profile = advance_result.get("profile", profile)
	_check(store.get_character_tier(profile) == 5, "Reward-scene fixture reaches tier five")
	var rng := RandomNumberGenerator.new()
	rng.seed = 411
	var offer_result: Dictionary = store.create_reward_offer_and_save(
		profile,
		Store.REWARD_VICTORY,
		rng
	)
	_check(bool(offer_result.get("ok", false)), "Tier-five reward offer saves")
	profile = offer_result.get("profile", profile)
	var reward_ids: Array[StringName] = store.get_pending_reward_ids(profile)
	_check(reward_ids.size() == 1, "Current catalog provides one locked tier-five reward")

	var enemy: Dictionary = Enemies.get_definition(store.get_current_enemy_id(profile))
	var reward: Variant = REWARD_SCENE.instantiate()
	reward.profile_path = SAVE_PATH
	reward.upcoming_enemy_name = String(enemy["name"])
	reward.upcoming_enemy_card_ids = _string_names(enemy["deck"])
	reward.testing_mode = false
	reward.reward_claimed.connect(_on_reward_claimed)
	reward.back_requested.connect(_on_back_requested)
	root.add_child(reward)
	await process_frame
	await process_frame

	var grid := reward.get_node("DuelCanvas/DeckLibraryGrid") as DeckLibraryGrid
	_check(grid.column_count == 3 and grid.total_slots == 3, "Reward scroll uses three positions")
	_check(reward.debug_get_reward_ids() == reward_ids, "Reward scene renders the saved offer")
	var first_slot: Variant = grid.debug_get_bound_slot(0)
	var second_slot: Variant = grid.debug_get_bound_slot(1)
	var third_slot: Variant = grid.debug_get_bound_slot(2)
	_check(first_slot != null and not first_slot.is_placeholder(), "First reward is revealed")
	_check(second_slot != null and second_slot.is_placeholder(), "Second position is a card back")
	_check(third_slot != null and third_slot.is_placeholder(), "Third position is a card back")
	_check(
		second_slot.get_node("CardHost/CardView").is_face_down()
		and third_slot.get_node("CardHost/CardView").is_face_down(),
		"Unused reward positions display face-down cards"
	)

	reward.call("_on_library_inspection_requested", 0, first_slot.card_data)
	_check(reward.debug_is_inspecting(), "Revealed reward opens normal inspection")
	(reward.get_node("DuelCanvas/CardInspector") as Control).call("close")
	_check(not reward.debug_is_inspecting(), "Closing inspection restores reward choices")

	var deck_before: Array[StringName] = store.get_main_deck_ids(profile)
	var source_point: Vector2 = first_slot.get_global_rect().get_center()
	reward.call("_on_library_drag_started", 0, first_slot.card_data, source_point)
	reward.call("_on_library_drag_ended", 0, Vector2(-100.0, -100.0))
	_check(
		store.get_pending_reward_ids(store.load_profile()) == reward_ids,
		"Dropping outside the hand preserves the offer"
	)
	reward.call("_on_library_drag_started", 0, first_slot.card_data, source_point)
	var hand := reward.get_node("DuelCanvas/PlayerHand") as HBoxContainer
	reward.call("_on_library_drag_ended", 0, hand.get_global_rect().get_center())
	await process_frame
	_check(_claim_count == 1, "A successful claim emits completion once")
	var claimed_profile: Dictionary = store.load_profile()
	_check(reward_ids[0] in store.get_unlocked_ids(claimed_profile), "Scene claim unlocks reward")
	_check(store.get_main_deck_ids(claimed_profile) == deck_before, "Scene claim preserves main deck")
	_check(String(claimed_profile["library_slots"][0]) == String(reward_ids[0]), "Scene claim enters library top")
	_check(store.get_pending_reward_ids(claimed_profile).is_empty(), "Scene claim clears pending offer")

	(reward.get_node("DuelCanvas/TopBar/BackButton") as Button).pressed.emit()
	_check(_back_count == 1, "Reward return icon emits a back request")
	reward.queue_free()
	await process_frame
	_cleanup()
	_finish()


func _string_names(values: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Variant in values:
		result.append(StringName(String(value)))
	return result


func _on_reward_claimed() -> void:
	_claim_count += 1


func _on_back_requested() -> void:
	_back_count += 1


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	if _failures == 0:
		print("REWARD_SELECTION_INTEGRATION_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"REWARD_SELECTION_INTEGRATION_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
