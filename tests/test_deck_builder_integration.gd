extends SceneTree

const BUILDER_SCENE: PackedScene = preload("res://scenes/deck_builder.tscn")
const Store = preload("res://scripts/deck_profile_store.gd")
const Catalog = preload("res://scripts/card_catalog.gd")

var _checks: int = 0
var _failures: int = 0
var _back_count: int = 0
var _duel_requests: Array[int] = []
var _save_path: String = "user://deck_builder_integration_test.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var builder: Variant = BUILDER_SCENE.instantiate()
	builder.profile_path = _save_path
	builder.testing_mode = false
	builder.library_color_seed = 12345
	root.add_child(builder)
	builder.size = Vector2(540.0, 960.0)
	await process_frame
	builder.call("_layout_scene")
	await process_frame

	var canvas: Control = builder.get_node("DuelCanvas") as Control
	var opponent_hand: HBoxContainer = canvas.get_node("OpponentHand") as HBoxContainer
	var player_hand: HBoxContainer = canvas.get_node("PlayerHand") as HBoxContainer
	var grid: Variant = canvas.get_node("DeckLibraryGrid")
	var go_first := canvas.get_node("GoFirstButton") as Button
	var go_second := canvas.get_node("GoSecondButton") as Button
	_check(canvas.find_child("ScoreOverlay", true, false) == null, "Deck builder has no score panels")
	_check(opponent_hand.get_child_count() == 5, "Opponent hand keeps five slots")
	_check(player_hand.get_child_count() == 5, "Player main deck keeps five slots")
	_check(grid.debug_get_pool_size() == 20, "Production scene uses four-column virtualized library pool")
	_check(go_first.flat and go_second.flat and go_first.text.is_empty() and go_second.text.is_empty(), "Opening choices show only supplied ink pictures")
	_check(go_first.position.x < grid.position.x and go_second.position.x > grid.position.x + grid.size.x, "Opening choices flank the library scroll")
	_check(go_first.get_node("Characters").get_child_count() == 4, "Go-first control stacks four character pictures")
	_check(go_second.get_node("Characters").get_child_count() == 4, "Go-second control stacks four character pictures")
	for control_path: String in [
		"GoFirstButton/Characters/Qiang",
		"GoFirstButton/Characters/Zhan",
		"GoFirstButton/Characters/Xian",
		"GoFirstButton/Characters/Ji",
		"GoSecondButton/Characters/Hou",
		"GoSecondButton/Characters/Fa",
		"GoSecondButton/Characters/Zhi",
		"GoSecondButton/Characters/Ren",
	]:
		_check((canvas.get_node(control_path) as TextureRect).texture != null, "%s uses a supplied character picture" % control_path)
	var ki_library_slot: Variant = grid.debug_get_bound_slot(3)
	var library_ki_badge := ki_library_slot.get_node("CardHost/CardView/Overlay/KiBadge") as Control
	_check(int(ki_library_slot.card_data.get("ki", 0)) > 0, "Library bead fixture uses a card with ki")
	_check(not library_ki_badge.visible, "Library cards hide ki beads")
	go_second.button_down.emit()
	_check(go_second.scale.x < 1.0 and go_second.modulate.a < 1.0, "Opening choice visibly responds while held")
	go_second.button_up.emit()
	var profile: Dictionary = builder.debug_get_profile()
	_check(_occupied_count(profile["library_slots"]) == 4, "Production scene starts with four library cards")
	_check(grid.debug_get_bound_slot(4).is_empty(), "First slot after the full four-card row is empty")
	var display_owner_ids: Array[int] = builder.debug_get_library_display_owner_ids()
	_check(display_owner_ids.size() == 1000, "Deck-builder entry rolls one stable display color per library slot")
	for logical_index: int in range(4):
		var expected_owner: int = display_owner_ids[logical_index]
		var library_card := grid.debug_get_bound_slot(logical_index).get_node("CardHost/CardView") as CardView
		_check(
			expected_owner in [DuelRules.PLAYER_OWNER, DuelRules.OPPONENT_OWNER]
			and library_card.owner_id == expected_owner,
			"Occupied library card %d uses its rolled blue-or-red appearance" % logical_index
		)

	for slot: Node in opponent_hand.get_children():
		var card: CardView = slot.get_child(0) as CardView
		_check(card.is_face_down(), "Normal mode keeps opponent card face-down")

	builder.duel_requested.connect(func(owner_id: int) -> void: _duel_requests.append(owner_id))
	var tier_totals: Vector2i = builder.debug_get_tier_totals()
	_check(tier_totals == Vector2i(6, 5), "Default player and enemy tier totals are calculated from catalog data")
	_check(not builder.debug_can_go_first(), "Higher-tier player deck blocks the go-first choice")
	var blocked_character := go_first.get_node("Characters/Qiang") as TextureRect
	var blocked_material := blocked_character.material as ShaderMaterial
	_check(blocked_material != null, "Blocked go-first ink uses a recoloring material")
	if blocked_material != null:
		var blocked_ink: Color = blocked_material.get_shader_parameter("ink_color")
		_check(blocked_ink.r >= 0.45 and blocked_ink.g >= 0.45 and blocked_ink.b >= 0.45, "Blocked go-first strokes become clearly grey")
	go_first.pressed.emit()
	_check(_duel_requests.is_empty(), "Blocked go-first press does not request a duel")
	_check(builder.debug_get_status() == "主卡组总品阶不高于对手时方可选择先攻", "Blocked go-first press shows the exact rule notice")
	go_second.pressed.emit()
	_check(_duel_requests == [DuelRules.OPPONENT_OWNER], "Go-second choice requests an opponent opening turn")

	builder.back_requested.connect(func() -> void: _back_count += 1)
	(builder.get_node("DuelCanvas/TopBar/BackButton") as Button).pressed.emit()
	_check(_back_count == 1 and builder.get_parent() == root, "Back button emits without navigating")

	var old_deck_card: String = String(profile["main_deck"][0])
	var old_library_card: String = String(profile["library_slots"][0])
	_check(builder.debug_exchange(0, 0), "Valid library-to-deck exchange succeeds")
	var exchanged: Dictionary = builder.debug_get_profile()
	_check(String(exchanged["main_deck"][0]) == old_library_card, "Library card enters selected main-deck slot")
	_check(String(exchanged["library_slots"][0]) == old_deck_card, "Displaced card occupies exact library source")
	_check(builder.debug_can_go_first(), "Deck exchange immediately refreshes go-first eligibility")
	go_first.pressed.emit()
	_check(_duel_requests.back() == DuelRules.PLAYER_OWNER, "Eligible go-first choice requests a player opening turn")
	var reload_store: Variant = Store.new(_save_path)
	var reloaded: Dictionary = reload_store.load_profile()
	_check(reloaded == exchanged, "Production exchange persists immediately")

	var drag_source_id := StringName(String(exchanged["library_slots"][1]))
	var drag_data: Dictionary = Catalog.create_instance(drag_source_id, DuelRules.PLAYER_OWNER, &"drag_source")
	var target_slot := player_hand.get_child(1) as Control
	var target_point: Vector2 = target_slot.get_global_rect().get_center()
	builder.call("_on_library_drag_started", 1, drag_data, target_point)
	var drag_proxy := canvas.get_node("DragLayer").get_child(-1) as CardView
	_check(
		drag_proxy.owner_id == grid.get_display_owner_id(1),
		"Library drag preview preserves the source card's rolled color"
	)
	builder.call("_on_library_drag_ended", 1, target_point)
	var dragged_profile: Dictionary = builder.debug_get_profile()
	_check(String(dragged_profile["main_deck"][1]) == String(drag_source_id), "Production drag hit-test exchanges into target hand slot")
	var before_invalid: Dictionary = dragged_profile.duplicate(true)
	var invalid_source_id := StringName(String(dragged_profile["library_slots"][2]))
	var invalid_data: Dictionary = Catalog.create_instance(invalid_source_id, DuelRules.PLAYER_OWNER, &"invalid_drag")
	builder.call("_on_library_drag_started", 2, invalid_data, Vector2.ZERO)
	builder.call("_on_library_drag_ended", 2, Vector2(-100.0, -100.0))
	_check(builder.debug_get_profile() == before_invalid, "Invalid production drop leaves profile unchanged")

	grid.set_scroll_offset(grid.debug_get_row_height() * 10.0)
	var saved_offset: float = grid.get_scroll_offset()
	var inspect_data: Dictionary = Catalog.create_instance(StringName(exchanged["main_deck"][0]), DuelRules.PLAYER_OWNER, &"inspect")
	builder.call("_on_card_inspection_requested", inspect_data)
	_check(builder.debug_is_inspecting() and not grid.visible, "Inspection replaces the library")
	(builder.get_node("DuelCanvas/CardInspector") as Control).call("close")
	_check(not builder.debug_is_inspecting() and grid.visible, "Closing inspection restores the library")
	_check(is_equal_approx(grid.get_scroll_offset(), saved_offset), "Inspection restores library scroll offset")

	builder.size = Vector2(540.0, 1080.0)
	builder.call("_layout_scene")
	var fitted: Rect2 = DuelBackdrop.fit_duel_rect(builder.size)
	_check(canvas.position.is_equal_approx(fitted.position) and canvas.size.is_equal_approx(fitted.size), "Tall layout keeps centered 9:16 canvas")
	builder.size = Vector2(1200.0, 960.0)
	builder.call("_layout_scene")
	fitted = DuelBackdrop.fit_duel_rect(builder.size)
	_check(canvas.position.is_equal_approx(fitted.position) and canvas.size.is_equal_approx(fitted.size), "Wide layout keeps centered 9:16 canvas")

	builder.queue_free()
	await process_frame
	var testing_builder: Variant = BUILDER_SCENE.instantiate()
	testing_builder.profile_path = _save_path
	testing_builder.testing_mode = true
	testing_builder.library_color_seed = 67890
	root.add_child(testing_builder)
	await process_frame
	var testing_hand: HBoxContainer = testing_builder.get_node("DuelCanvas/OpponentHand") as HBoxContainer
	var all_revealed: bool = true
	for slot: Node in testing_hand.get_children():
		all_revealed = all_revealed and not (slot.get_child(0) as CardView).is_face_down()
	_check(all_revealed, "Testing mode reveals all opponent cards")

	testing_builder.queue_free()
	await process_frame
	_cleanup()
	_finish()


func _occupied_count(slots: Array) -> int:
	var result: int = 0
	for value: Variant in slots:
		if not String(value).is_empty():
			result += 1
	return result


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = _save_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	if _failures == 0:
		print("DECK_BUILDER_INTEGRATION_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("DECK_BUILDER_INTEGRATION_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
