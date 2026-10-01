extends SceneTree

const Store = preload("res://scripts/deck_profile_store.gd")
const Enemies = preload("res://scripts/enemy_catalog.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const MAIN_SCENE = preload("res://main.tscn")
const SAVE_PATH := "user://hidden_enemy_reroll_test.json"
const SEQUENCE := [0, 1, 2, 3, 4, 3, 2, 1, 0]
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	root.size = Vector2i(540, 960)
	_cleanup()
	var store := Store.new(SAVE_PATH)
	_check(store.has_method("reroll_enemy_and_save"), "Store exposes atomic enemy reroll")
	if store.has_method("reroll_enemy_and_save"):
		_test_store(store)
	await _test_input_and_flow(store)
	_cleanup()
	if failures == 0:
		print("ENEMY_REROLL_TESTS_PASSED checks=%d" % checks)
	else:
		push_error("ENEMY_REROLL_TESTS_FAILED failures=%d checks=%d" % [failures, checks])
	quit(failures)

func _pool(difficulty: int) -> Array[StringName]:
	for level: int in range(1, Store.MAX_CHARACTER_LEVEL + 1):
		var ids := Enemies.get_random_enemy_ids_for_level(level, difficulty)
		if ids.size() > 1:
			return ids
	return []

func _profile(store: RefCounted, difficulty: int = 0) -> Dictionary:
	var initial: Dictionary = store.create_default_profile()
	initial.max_unlocked_difficulty = difficulty
	var first := Enemies.get_random_enemy_ids_for_level(1, difficulty)
	var started: Dictionary = store.begin_run_and_save(initial, &"HuaShanPai", [], first[0], null, false, difficulty)
	_check(started.ok, "Explicit ordinary run fixture starts")
	var profile: Dictionary = started.profile
	var pool := _pool(difficulty)
	_check(pool.size() > 1, "Current roster supplies multiple ordinary candidates")
	profile.level = int(Enemies.get_definition(pool[0]).level)
	profile.current_enemy_id = String(pool[0])
	profile.tutorial_pending = false
	profile.remembered_enemy_glyphs = []
	_check(store.save_profile(profile), "Ordinary reroll fixture saves")
	return profile

func _test_store(store: RefCounted) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 173
	for difficulty: int in [0, 4]:
		var profile := _profile(store, difficulty)
		var original: Dictionary = profile.duplicate(true)
		var definition := Enemies.get_definition(StringName(profile.current_enemy_id))
		profile.remembered_enemy_glyphs = [String(Catalog.get_definition(definition.deck[0]).glyph)]
		original = profile.duplicate(true)
		var result: Dictionary = store.call("reroll_enemy_and_save", profile, rng)
		_check(result.ok and result.profile.current_enemy_id != profile.current_enemy_id, "Reroll excludes current enemy")
		_check(StringName(result.profile.current_enemy_id) in Enemies.get_random_enemy_ids_for_level(profile.level, difficulty), "Reroll follows level and difficulty gates")
		_check(result.profile.remembered_enemy_glyphs.is_empty(), "Old enemy memories clear")
		var expected := original.duplicate(true)
		expected.current_enemy_id = result.profile.current_enemy_id
		expected.remembered_enemy_glyphs = []
		_check(result.profile == expected and profile == original, "Only opponent and memories change; input is isolated")
		_check(store.load_profile() == result.profile, "New opponent persists across reload")
		var failing := Store.new("user://hidden_reroll_missing_parent/profile.json")
		var failed: Dictionary = failing.call("reroll_enemy_and_save", profile, rng)
		_check(not failed.ok and failed.profile == original, "Save failure returns original profile")
		# Temporarily narrow the current catalog pool, without a fixed roster count.
		var definitions: Dictionary = Enemies._enemy_definitions.duplicate(true)
		for id: StringName in Enemies.get_random_enemy_ids_for_level(profile.level, difficulty):
			if id != StringName(profile.current_enemy_id):
				Enemies._enemy_definitions[id].special_only = true
		var none: Dictionary = store.call("reroll_enemy_and_save", profile, rng)
		Enemies._enemy_definitions = definitions
		_check(not none.ok and none.profile == original, "No alternative preserves opponent")
		_check(store.load_profile() == result.profile, "No alternative does not write a save")
	var inactive: Dictionary = store.create_default_profile()
	var rejected: Dictionary = store.call("reroll_enemy_and_save", inactive)
	_check(not rejected.ok and rejected.profile == inactive, "Inactive journey cannot reroll")
	var beginner: Dictionary = store.begin_run_and_save(inactive, &"HuaShanPai", []).profile
	rejected = store.call("reroll_enemy_and_save", beginner)
	_check(not rejected.ok and rejected.profile == beginner, "Fixed beginner enemies cannot reroll")

func _test_input_and_flow(store: RefCounted) -> void:
	var profile := _profile(store)
	var flow: Variant = MAIN_SCENE.instantiate()
	flow.testing_mode = false
	flow.deck_profile_path = SAVE_PATH
	for id: Variant in profile.library_slots:
		if not String(id).is_empty():
			flow._active_new_card_highlight_ids.assign([StringName(id)])
			break
	root.add_child(flow)
	flow.call("_show_deck_builder")
	await process_frame
	await process_frame
	var builder: Variant = flow.debug_get_current_screen()
	_check(builder.has_signal("enemy_reroll_requested"), "Deck builder exposes scoped reroll request")
	if not builder.has_signal("enemy_reroll_requested"):
		flow.queue_free()
		await process_frame
		return
	var requests := [0]
	builder.enemy_reroll_requested.connect(func() -> void: requests[0] += 1)
	var hand: Control = builder.opponent_hand
	var grid: Variant = builder.library_grid
	grid.set_scroll_offset(35.0)
	var before_scroll: float = grid.get_scroll_offset()
	var before_audio: int = builder._rank_up_sound_play_count
	var before_highlights: Array = builder.new_card_highlight_ids.duplicate()
	for index: int in range(8):
		await _tap(hand, SEQUENCE[index])
	_check(requests[0] == 0 and store.load_profile().current_enemy_id == profile.current_enemy_id, "First eight taps do not reroll")
	await _tap(hand, 0)
	var changed: Dictionary = store.load_profile()
	_check(requests[0] == 1 and changed.current_enemy_id != profile.current_enemy_id, "Ninth tap rerolls exactly once")
	_check(flow.debug_get_current_screen() == builder and grid.get_scroll_offset() == before_scroll, "Refresh retains screen and library scroll")
	_check(builder.new_card_highlight_ids == before_highlights and builder._rank_up_sound_play_count == before_audio, "Refresh retains highlights and does not replay rank audio")
	_check(not before_highlights.is_empty(), "Highlight retention covers an actual rewarded card")
	var enemy := Enemies.get_definition(StringName(changed.current_enemy_id))
	_check(builder.opponent_name.text == enemy.name and builder._effective_enemy_card_ids == enemy.deck, "Displayed enemy matches saved directory")
	var total := 0
	for card_id: StringName in enemy.deck:
		total += int(Catalog.get_definition(card_id).tier)
	_check(builder.debug_get_tier_totals().y == total, "Enemy tier and first-player conditions refresh")
	# Wrong-slot 0 restarts the prefix; the subsequent eight taps complete it.
	await _tap(hand, 0)
	await _tap(hand, 2)
	await _tap(hand, 0)
	for index: int in range(1, 9):
		await _tap(hand, SEQUENCE[index], true)
	_check(requests[0] == 2, "Wrong-slot restart and touch sequence work")
	# A matching mouse event synthesized from touch must not count twice.
	for slot: int in SEQUENCE:
		await _tap(hand, slot, true, true)
	_check(requests[0] == 3, "Emulated mouse input is not counted twice")
	await _tap(hand, 0)
	await _drag(hand, 1, 2)
	for index: int in range(2, 9):
		await _tap(hand, SEQUENCE[index])
	_check(requests[0] == 3, "Cross-card release cancels sequence")
	await _tap(hand, 0)
	await _tap_at(Vector2(5, 5))
	for index: int in range(1, 9):
		await _tap(hand, SEQUENCE[index])
	_check(requests[0] == 3, "Click outside opponent row breaks prefix")
	await _tap(hand, 0)
	for index: int in [0, 1]:
		_touch(_center(hand, 1), index, true)
	for index: int in [1, 0]:
		_touch(_center(hand, 1), index, false)
	for index: int in range(2, 9):
		await _tap(hand, SEQUENCE[index])
	_check(requests[0] == 3, "Multi-touch cancels prefix until all fingers release")
	await _tap(hand, 0)
	_touch(_center(hand, 1), 0, true)
	_touch(_center(hand, 1), 0, false, true)
	for index: int in range(2, 9):
		await _tap(hand, SEQUENCE[index])
	_check(requests[0] == 3, "Canceled touch cannot finish a tap")
	await _tap(hand, 0)
	_touch(_center(hand, 1), 0, true)
	await create_timer(builder.hold_duration + 0.05).timeout
	_touch(_center(hand, 1), 0, false)
	for index: int in range(2, 9):
		await _tap(hand, SEQUENCE[index])
	_check(requests[0] == 3, "Long press does not count as tap")
	for index: int in range(8):
		await _tap(hand, SEQUENCE[index])
	builder.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _tap(hand, 0)
	_check(requests[0] == 3, "Focus loss clears incomplete sequence")
	var card: CardView = hand.get_child(2).get_child(0)
	card.set_face_down(false)
	for slot: int in SEQUENCE:
		await _tap(hand, slot)
	_check(requests[0] == 3, "Any revealed opponent card disables gesture")
	builder.card_inspector.close()
	await process_frame
	# Refresh restores all backs and forgets an incomplete prefix.
	builder.call("refresh_upcoming_enemy", store.load_profile(), enemy)
	await process_frame
	for index: int in range(8):
		await _tap(hand, SEQUENCE[index])
	builder.call("_open_card_inspector", builder.player_hand.get_child(0).get_child(0).card_data, -1, 0)
	builder.card_inspector.close()
	await process_frame
	await _tap(hand, 0)
	_check(requests[0] == 3, "Opening inspector clears unfinished prefix")
	# Explicit directory overrides must stay immutable even with valid gestures.
	flow.upcoming_enemy_name = "Override"
	flow.upcoming_enemy_card_ids.assign(enemy.deck)
	var before_override: Dictionary = store.load_profile()
	for index: int in range(1, 9):
		await _tap(hand, SEQUENCE[index])
	_check(store.load_profile() == before_override, "Explicit enemy override refuses reroll")
	flow.upcoming_enemy_name = ""
	flow.upcoming_enemy_card_ids.clear()
	flow.call("_show_duel", 1)
	await process_frame
	var duel: Variant = flow.debug_get_current_screen()
	var final_enemy := Enemies.get_definition(StringName(store.load_profile().current_enemy_id))
	_check(duel.opponent_name_text == final_enemy.name and duel.opponent_card_ids == final_enemy.deck
		and duel.opponent_favorite_card_id == final_enemy.get("favorite_card", &""), "Actual duel loads rerolled complete directory definition")
	flow.queue_free()
	await process_frame
	_check(not is_instance_valid(flow), "Reroll fixture frees its main scene before exit")
	# Match the telemetry-flow fixture: MP3 playback releases on the audio thread.
	await create_timer(0.2).timeout

func _center(hand: Control, slot: int) -> Vector2:
	var card: Control = hand.get_child(slot).get_child(0)
	return card.get_global_transform_with_canvas() * (card.size * 0.5)

func _tap(hand: Control, slot: int, touch: bool = false, emulated: bool = false) -> void:
	await _tap_at(_center(hand, slot), touch, emulated)

func _tap_at(position: Vector2, touch: bool = false, emulated: bool = false) -> void:
	for pressed: bool in [true, false]:
		if touch:
			var event := InputEventScreenTouch.new()
			event.index = 0
			event.position = position
			event.pressed = pressed
			root.push_input(event)
		if not touch or emulated:
			var event := InputEventMouseButton.new()
			event.device = InputEvent.DEVICE_ID_EMULATION if emulated else 0
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = position
			event.global_position = position
			event.pressed = pressed
			root.push_input(event)
		await process_frame

func _drag(hand: Control, from_slot: int, to_slot: int) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = _center(hand, from_slot)
	root.push_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = _center(hand, to_slot)
	root.push_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = motion.position
	root.push_input(release)
	await process_frame

func _touch(position: Vector2, index: int, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = position
	event.index = index
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path := SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
