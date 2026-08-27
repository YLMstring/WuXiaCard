extends SceneTree

const SECT_SCENE: PackedScene = preload("res://scenes/sect_selection.tscn")
const Store = preload("res://scripts/deck_profile_store.gd")
const SelectorController = preload("res://scripts/sect_selection_controller.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Sects = preload("res://scripts/sect_catalog.gd")

var _checks: int = 0
var _failures: int = 0
var _back_count: int = 0
var _builder_requests: int = 0
var _save_path: String = "user://sect_selection_integration_test.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var selector := SECT_SCENE.instantiate() as SelectorController
	selector.profile_path = _save_path
	selector.upcoming_enemy_name = "测试对手"
	root.add_child(selector)
	selector.size = Vector2(540.0, 960.0)
	selector.back_requested.connect(func() -> void: _back_count += 1)
	selector.deck_builder_requested.connect(func() -> void: _builder_requests += 1)
	await process_frame
	await process_frame

	var canvas := selector.get_node("DuelCanvas") as Control
	var grid := canvas.get_node("DeckLibraryGrid") as DeckLibraryGrid
	var opponent_hand := canvas.get_node("OpponentHand") as HBoxContainer
	var player_hand := canvas.get_node("PlayerHand") as HBoxContainer
	var title_image := grid.get_node("Body/Margin/Layout/Title/Image") as TextureRect
	var left_difficulty_button := canvas.get_node_or_null("DifficultyLeftButton") as TextureButton
	var right_difficulty_button := canvas.get_node_or_null("DifficultyRightButton") as TextureButton
	_check(selector.upcoming_enemy_name == "测试对手", "Selector accepts the upcoming enemy name")
	_check((canvas.get_node("TopBar/OpponentName") as Label).text == "测试对手", "Header shows the upcoming enemy name")
	_check(
		left_difficulty_button != null and right_difficulty_button != null,
		"Sect selection declares both difficulty arrow buttons"
	)
	if left_difficulty_button != null and right_difficulty_button != null:
		_check(
			not left_difficulty_button.visible and not right_difficulty_button.visible,
			"Difficulty arrows stay hidden while only difficulty zero is unlocked"
		)
		_check(
			left_difficulty_button.texture_normal != null
			and left_difficulty_button.texture_normal.resource_path == "res://inkpics/arrow.png"
			and right_difficulty_button.texture_normal == left_difficulty_button.texture_normal,
			"Both difficulty buttons reuse the supplied arrow texture"
		)
		_check(
			left_difficulty_button.flip_h and not right_difficulty_button.flip_h,
			"Only the left difficulty arrow is horizontally flipped"
		)
	_check(
		selector.has_method("debug_get_selected_difficulty")
		and _selected_difficulty(selector) == 0,
		"A new selector begins on difficulty zero"
	)
	_check(
		(canvas.get_node("TopBar/EnemySeal/Value") as Label).text == "友",
		"Sect selection uses the friend seal"
	)
	_check(title_image.texture != null, "Selector keeps the inherited Cangjingge title image")
	_check(not (canvas.get_node("GoFirstButton") as Button).visible, "Go-first control is hidden")
	_check(not (canvas.get_node("GoSecondButton") as Button).visible, "Go-second control is hidden")
	_check(opponent_hand.get_child_count() == 5, "Upper preview hand keeps five fixed slots")
	_check(player_hand.get_child_count() == 5, "Lower preview hand keeps five fixed slots")
	_check(_occupied_hand_slots(opponent_hand) == 5, "Upper preview hand starts visually filled")
	_check(_occupied_hand_slots(player_hand) == 5, "Lower preview hand starts visually filled")
	_check(_face_down_hand_slots(opponent_hand) == 5, "Upper preview hand starts with five card backs")
	_check(_face_down_hand_slots(player_hand) == 5, "Lower preview hand starts with five card backs")
	_check(_data_free_hand_slots(opponent_hand) == 5, "Upper initial card backs contain no card data")
	_check(_data_free_hand_slots(player_hand) == 5, "Lower initial card backs contain no card data")
	_check(_inspectable_hand_slots(opponent_hand) == 0, "Upper initial card backs are not inspectable")
	_check(_inspectable_hand_slots(player_hand) == 0, "Lower initial card backs are not inspectable")

	var expected_sect_ids: Array[StringName] = Sects.get_all_sect_ids()
	for index: int in range(expected_sect_ids.size()):
		var entry: Dictionary = grid.library_slots[index]
		_check(
			StringName(String(entry.get("id", ""))) == expected_sect_ids[index],
			"Sect grid preserves catalog order at slot %d" % index
		)
	var first_unused_entry: Variant = grid.library_slots[expected_sect_ids.size()]
	_check(
		not first_unused_entry is Dictionary
		or (first_unused_entry as Dictionary).is_empty(),
		"The first position after the current sect catalog is empty"
	)
	_check(
		grid.get_display_owner_id(0) == DuelRules.PLAYER_OWNER,
		"Default unlocked sect is blue"
	)
	for index: int in range(1, expected_sect_ids.size()):
		_check(
			grid.get_display_owner_id(index) == DuelRules.OPPONENT_OWNER,
			"Locked sect %d is red" % index
		)
	var first_slot: Variant = grid.debug_get_bound_slot(0)
	var first_card := first_slot.get_node("CardHost/CardView") as CardView
	_check(first_slot.drag_enabled, "Default unlocked sect may drag")
	_check(not grid.debug_get_bound_slot(1).drag_enabled, "Locked sect may not drag")
	_check(not first_card.ki_badge_enabled, "Sect entries hide ki badges")
	_check(not first_card.power_numbers_enabled, "Sect entries hide power numbers")

	first_slot.debug_begin_pointer(first_slot.get_global_rect().get_center())
	first_slot.debug_end_pointer(first_slot.get_global_rect().get_center())
	_check(selector.debug_get_selected_sect_id() == &"HuaShanPai", "Tapping selects the sect")
	_check(selector.debug_is_inspecting(), "Tapping also opens sect inspection")
	_check(
		StringName(String(selector.card_inspector.get_card_snapshot().get("id", "")))
		== &"HuaShanPai",
		"Sect inspector receives the sect definition"
	)
	_check(
		String(selector.card_inspector.get_card_snapshot().get("sect", ""))
		== "最高分：0",
		"A sect with no completed-run score displays zero as its best score"
	)
	_check(
		selector.debug_get_upper_preview_ids()
		== [&"CangSongYingKe4", &"YouFenLaiYi4", &"ZiXiaGong4", &"CangSongYingKe3", &"YouFenLaiYi3"],
		"Upper hand orders Huashan cards from highest tier"
	)
	_check(
		selector.debug_get_lower_preview_ids()
		== [&"CangSongYingKe1", &"SanQinFeng1", &"ZiXiaGong1", &"CangSongYingKe2", &"YouFenLaiYi2"],
		"Lower hand orders Huashan cards from lowest tier"
	)
	_check(_occupied_hand_slots(opponent_hand) == 5, "Upper preview hand remains visually filled")
	_check(_occupied_hand_slots(player_hand) == 5, "Lower preview hand remains visually filled")
	_check(_face_down_hand_slots(opponent_hand) == 0, "Upper preview fills all five slots with cards")
	_check(_face_down_hand_slots(player_hand) == 0, "Lower preview fills all five slots with cards")
	_check(_data_free_hand_slots(opponent_hand) == 0, "Every upper preview slot contains card data")
	_check(_data_free_hand_slots(player_hand) == 0, "Every lower preview slot contains card data")
	_check(_inspectable_hand_slots(opponent_hand) == 5, "Every upper preview card is inspectable")
	_check(_inspectable_hand_slots(player_hand) == 5, "Every lower preview card is inspectable")
	selector.card_inspector.close()
	await process_frame
	_check(not selector.debug_is_inspecting() and grid.visible, "Closing inspection restores the sect grid")
	_check(_occupied_hand_slots(player_hand) == 5, "Closing inspection preserves previews and card backs")

	var preview_card := player_hand.get_child(0).get_child(0) as CardView
	preview_card.inspection_requested.emit(preview_card.card_data)
	_check(selector.debug_is_inspecting(), "A preview card opens normal card inspection")
	_check(
		StringName(String(selector.card_inspector.get_card_snapshot().get("card_id", "")))
		== &"CangSongYingKe1",
		"Preview inspection receives card data rather than sect data"
	)
	_check(
		String(selector.card_inspector.get_card_snapshot().get("sect", "")) == "华山派",
		"Ordinary preview-card inspection keeps the card's actual sect"
	)
	selector.card_inspector.close()
	await process_frame

	var locked_slot: Variant = grid.debug_get_bound_slot(1)
	var locked_sect_id: StringName = expected_sect_ids[1]
	var locked_center: Vector2 = locked_slot.get_global_rect().get_center()
	locked_slot.debug_begin_pointer(locked_center)
	locked_slot.debug_end_pointer(locked_center)
	_check(locked_slot.debug_get_rejected_drag_pulse_count() == 0, "Tapping a locked sect does not pulse")
	selector.card_inspector.close()
	await process_frame
	locked_slot.debug_begin_pointer(locked_center)
	locked_slot.debug_force_hold_timeout()
	locked_slot.debug_end_pointer(locked_center)
	_check(selector.debug_get_selected_sect_id() == locked_sect_id, "Holding a locked sect updates selection")
	_check(
		selector.debug_get_upper_preview_ids()
		== _expected_preview_ids(locked_sect_id, false),
		"A locked sect previews its five highest-tier cards"
	)
	_check(not selector.debug_is_inspecting(), "A hold does not open the inspector")
	_check(not locked_slot.is_drag_armed(), "A locked hold never arms drag")
	_check(selector.debug_get_status() == SelectorController.LOCKED_STATUS, "Locked hold reports its status")
	_check(locked_slot.debug_get_rejected_drag_pulse_count() == 1, "A locked hold pulses exactly once")
	locked_slot.debug_begin_pointer(locked_center)
	locked_slot.debug_force_hold_timeout()
	locked_slot.debug_end_pointer(locked_center)
	_check(locked_slot.debug_get_rejected_drag_pulse_count() == 2, "A repeated locked hold restarts one pulse")

	_check(selector.debug_select_sect(&"HengShanPai"), "Debug selection accepts a known sect")
	_check(
		selector.debug_get_lower_preview_ids().slice(0, 2)
		== _expected_preview_ids(&"HengShanPai", true).slice(0, 2),
		"Equal-tier preview ties retain CardCatalog order"
	)

	(canvas.get_node("TopBar/BackButton") as Button).pressed.emit()
	_check(_back_count == 1, "Back icon emits one navigation-neutral request")

	_check(selector.debug_select_sect(&"HuaShanPai"), "Default unlocked sect can be reselected")
	var cancel_center: Vector2 = first_slot.get_global_rect().get_center()
	first_slot.debug_begin_pointer(cancel_center)
	first_slot.debug_force_hold_timeout()
	first_slot.debug_move_pointer(cancel_center + Vector2(0.0, 20.0))
	first_slot.debug_end_pointer(Vector2(4.0, 4.0))
	_check(first_slot.debug_get_rejected_drag_pulse_count() == 0, "An unlocked hold never uses rejected-drag feedback")
	_check(_builder_requests == 0, "Dropping outside the lower hand cancels selection")
	_check(
		&"CangSongYingKe1" not in Store.new(_save_path).get_unlocked_ids(
			Store.new(_save_path).load_profile()
		),
		"Cancelled selection does not unlock cards"
	)

	first_slot = grid.debug_get_bound_slot(0)
	var drag_start: Vector2 = first_slot.get_global_rect().get_center()
	var valid_drop: Vector2 = player_hand.get_global_rect().get_center()
	first_slot.debug_begin_pointer(drag_start)
	first_slot.debug_force_hold_timeout()
	first_slot.debug_move_pointer(valid_drop)
	first_slot.debug_end_pointer(valid_drop)
	await process_frame
	_check(_builder_requests == 1, "Dropping anywhere over the lower hand confirms selection")
	var saved_profile: Dictionary = Store.new(_save_path).load_profile()
	_check(
		String(saved_profile["library_slots"][0]) == "CangSongYingKe1",
		"Successful selection inserts its tier-1 card at the library top"
	)
	_check(
		saved_profile["unlocked_card_ids"].count("CangSongYingKe1") == 1,
		"Successful selection unlocks its tier-1 card exactly once"
	)
	_check(bool(saved_profile["run_active"]), "Successful selection starts the run")
	_check(
		StringName(String(saved_profile["selected_sect_id"])) == &"HuaShanPai",
		"Successful selection records the chosen sect"
	)

	var scores: Dictionary = saved_profile["best_scores_by_sect"] as Dictionary
	scores["HuaShanPai"] = {
		"0": 500,
		"1": 111,
		"2": 4321,
	}
	saved_profile["best_scores_by_sect"] = scores
	saved_profile["max_unlocked_difficulty"] = 2
	saved_profile["last_selected_difficulty"] = 1
	_check(Store.new(_save_path).save_profile(saved_profile), "Best-score fixture saves")
	selector.queue_free()
	await process_frame

	selector = SECT_SCENE.instantiate() as SelectorController
	selector.profile_path = _save_path
	root.add_child(selector)
	selector.size = Vector2(540.0, 960.0)
	await process_frame
	await process_frame
	grid = selector.get_node("DuelCanvas/DeckLibraryGrid") as DeckLibraryGrid
	canvas = selector.get_node("DuelCanvas") as Control
	left_difficulty_button = canvas.get_node_or_null("DifficultyLeftButton") as TextureButton
	right_difficulty_button = canvas.get_node_or_null("DifficultyRightButton") as TextureButton
	_check(
		left_difficulty_button != null
		and right_difficulty_button != null
		and left_difficulty_button.visible
		and right_difficulty_button.visible,
		"Unlocking more difficulties reveals both arrows"
	)
	if left_difficulty_button != null and right_difficulty_button != null:
		var grid_rect: Rect2 = grid.get_global_rect()
		_check(
			left_difficulty_button.size.is_equal_approx(Vector2(21.0, 34.0))
			and right_difficulty_button.size.is_equal_approx(Vector2(21.0, 34.0)),
			"Difficulty arrow buttons use half-size geometry"
		)
		_check(
			is_equal_approx(
				left_difficulty_button.get_global_rect().get_center().y,
				grid_rect.get_center().y
			)
			and is_equal_approx(
				right_difficulty_button.get_global_rect().get_center().y,
				grid_rect.get_center().y
			),
			"Difficulty arrows remain vertically centered beside the scroll"
		)
		_check(
			is_equal_approx(
				left_difficulty_button.get_global_rect().get_center().x,
				grid_rect.position.x - 21.0
			)
			and is_equal_approx(
				right_difficulty_button.get_global_rect().get_center().x,
				grid_rect.end.x + 21.0
			),
			"Difficulty arrows keep their original horizontal centers"
		)
		left_difficulty_button.button_down.emit()
		_check(
			left_difficulty_button.pivot_offset.is_equal_approx(
				left_difficulty_button.size * 0.5
			)
			and left_difficulty_button.scale.is_equal_approx(Vector2(0.92, 0.92))
			and is_equal_approx(left_difficulty_button.modulate.a, 0.62),
			"Difficulty arrow touch-down provides centered scale and opacity feedback"
		)
		left_difficulty_button.button_up.emit()
		await create_timer(0.18).timeout
		_check(
			left_difficulty_button.scale.is_equal_approx(Vector2.ONE)
			and is_equal_approx(left_difficulty_button.modulate.a, 1.0),
			"Difficulty arrow touch feedback restores cleanly on release"
		)
	_check(
		_selected_difficulty(selector) == 1
		and (canvas.get_node("TopBar/OpponentName") as Label).text == "江湖门派·进阶一"
		and selector.debug_get_status() == "进阶一：进阶特效文本占位",
		"Reopening the selector restores difficulty one and its Chinese text"
	)
	_check(
		selector.debug_select_sect(&"HuaShanPai", true),
		"Difficulty-one score fixture opens sect inspection"
	)
	_check(
		String(selector.card_inspector.get_card_snapshot().get("sect", ""))
		== "进阶一：111",
		"Difficulty-one sect inspection displays only its own best score"
	)
	selector.card_inspector.close()
	await process_frame
	if right_difficulty_button != null:
		right_difficulty_button.pressed.emit()
	_check(
		_selected_difficulty(selector) == 2
		and Store.new(_save_path).get_last_selected_difficulty(
			Store.new(_save_path).load_profile()
		) == 2,
		"The right arrow advances and immediately saves difficulty two"
	)
	if right_difficulty_button != null:
		right_difficulty_button.pressed.emit()
	_check(
		_selected_difficulty(selector) == 0
		and (canvas.get_node("TopBar/OpponentName") as Label).text
		== selector.upcoming_enemy_name
		and selector.debug_get_status() == SelectorController.DEFAULT_STATUS,
		"The right arrow wraps to difficulty zero and restores existing text"
	)
	if left_difficulty_button != null:
		left_difficulty_button.pressed.emit()
	_check(
		_selected_difficulty(selector) == 2
		and (canvas.get_node("TopBar/OpponentName") as Label).text == "江湖门派·进阶二"
		and selector.debug_get_status() == "进阶二：进阶特效文本占位",
		"The left arrow wraps from zero to the highest unlocked difficulty"
	)
	if left_difficulty_button != null:
		left_difficulty_button.button_down.emit()
	first_slot = grid.debug_get_bound_slot(0)
	first_slot.debug_begin_pointer(first_slot.get_global_rect().get_center())
	first_slot.debug_end_pointer(first_slot.get_global_rect().get_center())
	_check(
		String(selector.card_inspector.get_card_snapshot().get("sect", ""))
		== "进阶二：4321",
		"Sect inspection displays the selected difficulty's per-sect best score"
	)
	_check(
		left_difficulty_button == null or left_difficulty_button.disabled,
		"Difficulty arrows are disabled while inspecting"
	)
	_check(
		left_difficulty_button == null
		or (
			left_difficulty_button.scale.is_equal_approx(Vector2.ONE)
			and is_equal_approx(left_difficulty_button.modulate.a, 1.0)
		),
		"Disabling a held difficulty arrow restores its resting visual state"
	)
	selector.card_inspector.close()
	await process_frame
	_check(
		selector.debug_get_status() == "进阶二：进阶特效文本占位",
		"Closing inspection restores the selected difficulty status"
	)

	selector.queue_free()
	await process_frame
	var store := Store.new(_save_path)
	var reset_result: Dictionary = store.reset_run_and_save(store.load_profile())
	_check(bool(reset_result.get("ok", false)), "Difficulty persistence fixture closes the active run")
	selector = SECT_SCENE.instantiate() as SelectorController
	selector.profile_path = _save_path
	root.add_child(selector)
	selector.size = Vector2(540.0, 960.0)
	await process_frame
	await process_frame
	_check(
		_selected_difficulty(selector) == 2,
		"A fresh selector instance restores the last saved difficulty"
	)
	_check(selector.debug_select_sect(&"HuaShanPai"), "Persisted difficulty fixture selects an unlocked sect")
	_check(selector.debug_confirm_selected_sect(), "Persisted difficulty fixture starts a run")
	var difficulty_run: Dictionary = store.load_profile()
	_check(
		store.get_run_difficulty(difficulty_run) == 2,
		"Confirming a sect records the selected difficulty on the active run"
	)
	selector.queue_free()
	await process_frame
	_cleanup()
	_finish()


func _occupied_hand_slots(hand: HBoxContainer) -> int:
	var result: int = 0
	for slot: Node in hand.get_children():
		if slot.get_child_count() > 0:
			result += 1
	return result


func _selected_difficulty(selector: Node) -> int:
	if not selector.has_method("debug_get_selected_difficulty"):
		return -1
	return int(selector.call("debug_get_selected_difficulty"))


func _expected_preview_ids(sect_id: StringName, ascending: bool) -> Array[StringName]:
	var result: Array[StringName] = []
	var sect_glyph: String = String(Sects.get_definition(sect_id).get("glyph", ""))
	var ranked: Array[Dictionary] = []
	var catalog_ids: Array[StringName] = Catalog.get_all_card_ids()
	for catalog_index: int in range(catalog_ids.size()):
		var card_id: StringName = catalog_ids[catalog_index]
		var definition: Dictionary = Catalog.get_definition(card_id)
		if String(definition.get("sect", "")) != sect_glyph:
			continue
		ranked.append({
			"id": card_id,
			"tier": int(definition.get("tier", 0)),
			"catalog_index": catalog_index,
		})
	ranked.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_tier: int = int(left["tier"])
		var right_tier: int = int(right["tier"])
		if left_tier == right_tier:
			return int(left["catalog_index"]) < int(right["catalog_index"])
		return left_tier < right_tier if ascending else left_tier > right_tier
	)
	for index: int in range(mini(5, ranked.size())):
		result.append(StringName(String(ranked[index]["id"])))
	return result


func _face_down_hand_slots(hand: HBoxContainer) -> int:
	var result: int = 0
	for slot: Node in hand.get_children():
		if slot.get_child_count() == 0:
			continue
		var card := slot.get_child(0) as CardView
		if card.is_face_down():
			result += 1
	return result


func _data_free_hand_slots(hand: HBoxContainer) -> int:
	var result: int = 0
	for slot: Node in hand.get_children():
		if slot.get_child_count() == 0:
			continue
		var card := slot.get_child(0) as CardView
		if card.card_data.is_empty():
			result += 1
	return result


func _inspectable_hand_slots(hand: HBoxContainer) -> int:
	var result: int = 0
	for slot: Node in hand.get_children():
		if slot.get_child_count() == 0:
			continue
		var card := slot.get_child(0) as CardView
		if not card.inspection_requested.get_connections().is_empty():
			result += 1
	return result


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = _save_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	if _failures == 0:
		print("SECT_SELECTION_INTEGRATION_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"SECT_SELECTION_INTEGRATION_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
