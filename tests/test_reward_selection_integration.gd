extends SceneTree

const REWARD_SCENE: PackedScene = preload("res://scenes/reward_selection.tscn")
const Store = preload("res://scripts/deck_profile_store.gd")
const Enemies = preload("res://scripts/enemy_catalog.gd")

const SAVE_PATH: String = "user://reward_selection_test.json"

var _checks: int = 0
var _failures: int = 0
var _claim_count: int = 0
var _claimed_card_id: StringName = &""
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
		&"HuaShanPai",
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
	var available_locked_ids: Array[StringName] = []
	for card_id: StringName in [&"KuiHua2", &"KuiHua3", &"KuiHua4"]:
		if card_id not in store.get_unlocked_ids(profile):
			available_locked_ids.append(card_id)
	if available_locked_ids.size() < 2:
		for card_id: StringName in Store.DEFAULT_LOCKED_IDS:
			if card_id not in store.get_unlocked_ids(profile) and card_id not in available_locked_ids:
				available_locked_ids.append(card_id)
				if available_locked_ids.size() >= 2:
					break
	profile["mastered_card_ids"] = [String(available_locked_ids[0])]
	profile["pending_reward_card_ids"] = [
		String(available_locked_ids[0]),
		String(available_locked_ids[1]),
	]
	_check(
		store.save_profile(profile),
		"Single-card reward-scene fixture saves after tier progression"
	)
	var reward_ids: Array[StringName] = store.get_pending_reward_ids(profile)
	_check(reward_ids.size() == 2, "Reward-scene fixture provides two visible choices")

	var enemy: Dictionary = Enemies.get_definition(store.get_current_enemy_id(profile))
	var reward: Variant = REWARD_SCENE.instantiate()
	reward.profile_path = SAVE_PATH
	reward.upcoming_enemy_name = String(enemy["name"])
	reward.upcoming_enemy_card_ids = _string_names(enemy["deck"])
	reward.testing_mode = true
	reward.set("reward_color_seed", 411)
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
	_check(
		grid.get_display_owner_id(0) == DuelRules.PLAYER_OWNER
		and grid.get_display_owner_id(1) == DuelRules.OPPONENT_OWNER
		and grid.get_display_owner_id(2) in [
			DuelRules.PLAYER_OWNER,
			DuelRules.OPPONENT_OWNER,
		],
		"Revealed rewards use mastery colors while the card back keeps a valid random color"
	)
	_check(first_slot != null and not first_slot.is_placeholder(), "First reward is revealed")
	_check(second_slot != null and not second_slot.is_placeholder(), "Second reward is revealed")
	_check(third_slot != null and third_slot.is_placeholder(), "Third position is a card back")
	var reward_scroll := grid.find_child("Scroll", true, false) as ScrollContainer
	var scroll_center_x: float = reward_scroll.size.x * 0.5
	var first_center_x: float = first_slot.position.x + first_slot.size.x * 0.5
	var second_center_x: float = second_slot.position.x + second_slot.size.x * 0.5
	var third_center_x: float = third_slot.position.x + third_slot.size.x * 0.5
	var old_three_column_width: float = (reward_scroll.size.x - 14.0 - 12.0) / 3.0
	_check(
		is_equal_approx(first_center_x, scroll_center_x),
		"First reward forms the centered upper point"
	)
	_check(
		second_slot.position.y > first_slot.position.y
		and is_equal_approx(second_slot.position.y, third_slot.position.y),
		"Second and third rewards form one lower row"
	)
	_check(
		is_equal_approx(second_center_x + third_center_x, reward_scroll.size.x),
		"Lower reward cards are symmetric around the scroll center"
	)
	_check(
		first_slot.size.x >= old_three_column_width * 1.35,
		"Reward triangle uses visibly larger card slots"
	)
	_check(
		third_slot.get_node("CardHost/CardView").is_face_down(),
		"Unused reward position displays a face-down card"
	)
	var enemy_hand := reward.get_node("DuelCanvas/OpponentHand") as HBoxContainer
	var enemy_cards_stay_red: bool = true
	for enemy_slot: Node in enemy_hand.get_children():
		var enemy_card := enemy_slot.get_child(0) as CardView
		enemy_cards_stay_red = (
			enemy_cards_stay_red
			and not enemy_card.is_face_down()
			and enemy_card.owner_id == DuelRules.OPPONENT_OWNER
		)
	_check(enemy_cards_stay_red, "Testing-mode revealed enemy hand stays red")

	reward.call("_on_library_inspection_requested", 0, first_slot.card_data)
	_check(reward.debug_is_inspecting(), "Revealed reward opens normal inspection")
	(reward.get_node("DuelCanvas/CardInspector") as Control).call("close")
	_check(not reward.debug_is_inspecting(), "Closing inspection restores reward choices")

	var deck_before: Array[StringName] = store.get_main_deck_ids(profile)
	var source_point: Vector2 = first_slot.get_global_rect().get_center()
	reward.call("_on_library_drag_started", 0, first_slot.card_data, source_point)
	var drag_proxy := reward.get_node("DuelCanvas/DragLayer").get_child(-1) as CardView
	_check(
		drag_proxy.owner_id == grid.get_display_owner_id(0),
		"Reward drag preview preserves the source card's mastery color"
	)
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
	_check(_claimed_card_id == reward_ids[0], "A successful claim emits the exact card ID")
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


func _on_reward_claimed(card_id: StringName) -> void:
	_claim_count += 1
	_claimed_card_id = card_id


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
