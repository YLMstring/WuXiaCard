extends SceneTree

const BUILDER_SCENE: PackedScene = preload("res://scenes/deck_builder.tscn")
const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Store = preload("res://scripts/deck_profile_store.gd")
const Enemies = preload("res://scripts/enemy_catalog.gd")
const Cards = preload("res://scripts/card_catalog.gd")

const SAVE_PATH: String = "user://enemy_memory_test.json"
const ENEMY_ID: StringName = &"qingfeng_xuedi"

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var store := Store.new(SAVE_PATH)
	var base_profile: Dictionary = store.create_default_profile()
	_check(store.save_profile(base_profile), "Enemy-memory fixture saves")
	var begin_result: Dictionary = store.begin_run_and_save(
		base_profile,
		&"HuaShanPai",
		[],
		ENEMY_ID
	)
	_check(bool(begin_result.get("ok", false)), "Enemy-memory run starts")
	var profile: Dictionary = begin_result.get("profile", {})
	var enemy: Dictionary = Enemies.get_definition(ENEMY_ID)
	var first_card_id := StringName(String((enemy["deck"] as Array)[0]))
	var shared_glyph: String = String(Cards.get_definition(first_card_id)["glyph"])
	var remember_result: Dictionary = store.remember_enemy_glyph_and_save(profile, shared_glyph)
	_check(bool(remember_result.get("ok", false)), "Shared glyph is remembered")
	profile = remember_result.get("profile", profile)

	var builder: Variant = BUILDER_SCENE.instantiate()
	builder.profile_path = SAVE_PATH
	builder.upcoming_enemy_name = String(enemy["name"])
	builder.upcoming_enemy_card_ids = _string_names(enemy["deck"])
	builder.remembered_enemy_glyphs = store.get_remembered_enemy_glyphs(profile)
	builder.testing_mode = false
	root.add_child(builder)
	await process_frame
	var builder_cards: Array[CardView] = _hand_cards(
		builder.get_node("DuelCanvas/OpponentHand") as HBoxContainer
	)
	var matching_count: int = 0
	for card: CardView in builder_cards:
		var matches: bool = String(card.card_data.get("glyph", "")) == shared_glyph
		if matches:
			matching_count += 1
		_check(
			card.is_face_down() != matches,
			"Only remembered same-glyph cards reveal in deck-building"
		)
	_check(matching_count >= 2, "Fixture contains multiple IDs sharing the remembered glyph")
	builder.queue_free()
	await process_frame

	var duel_orders: Array[Array] = []
	for seed: int in [731, 731, 947]:
		var duel: Variant = DUEL_SCENE.instantiate()
		duel.deck_profile_path = SAVE_PATH
		duel.opponent_card_ids = _string_names(enemy["deck"])
		duel.opponent_hand_shuffle_seed = seed
		duel.opening_layout_seed = -1
		duel.remembered_enemy_glyphs = store.get_remembered_enemy_glyphs(profile)
		duel.testing_mode = false
		root.add_child(duel)
		await process_frame
		var duel_cards: Array[CardView] = _hand_cards(
			duel.get_node("DuelCanvas/OpponentHand") as HBoxContainer
		)
		var player_opening_glyphs: Array[String] = _hand_glyphs(
			duel.duel_state.get_hand(DuelRules.PLAYER_OWNER)
		)
		var enemy_remembered_glyphs: Array[String] = []
		for value: Variant in duel.duel_state.remembered_glyphs_by_owner.get(
			DuelRules.OPPONENT_OWNER,
			[]
		):
			enemy_remembered_glyphs.append(String(value))
		player_opening_glyphs.sort()
		enemy_remembered_glyphs.sort()
		_check(
			enemy_remembered_glyphs == player_opening_glyphs,
			"Enemy remembers every player opening main-deck glyph"
		)
		_check(
			duel.duel_state.remembered_glyphs_by_owner.get(
				DuelRules.PLAYER_OWNER,
				[]
			) == [shared_glyph],
			"Player keeps the persisted enemy-glyph memory"
		)
		var order: Array = []
		var all_concealed: bool = true
		for card: CardView in duel_cards:
			order.append(StringName(card.card_data.get("card_id", &"")))
			all_concealed = all_concealed and card.is_face_down()
		duel_orders.append(order)
		_check(all_concealed, "Remembered cards remain concealed inside the duel")
		duel.queue_free()
		await process_frame
	_check(duel_orders[0] == duel_orders[1], "Equal hand-shuffle seeds reproduce the same order")
	_check(duel_orders[0] != duel_orders[2], "Different hand-shuffle seeds change the order")
	_check(duel_orders[0] != enemy["deck"], "Opponent duel hand is shuffled from catalog order")

	_cleanup()
	_finish()


func _hand_cards(hand: HBoxContainer) -> Array[CardView]:
	var result: Array[CardView] = []
	for slot: Node in hand.get_children():
		if slot.get_child_count() > 0:
			result.append(slot.get_child(0) as CardView)
	return result


func _string_names(values: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Variant in values:
		result.append(StringName(String(value)))
	return result


func _hand_glyphs(hand: Array) -> Array[String]:
	var result: Array[String] = []
	for card_value: Variant in hand:
		var glyph: String = String((card_value as Dictionary).get("glyph", ""))
		if not glyph.is_empty() and glyph not in result:
			result.append(glyph)
	return result


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	if _failures == 0:
		print("ENEMY_MEMORY_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("ENEMY_MEMORY_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
