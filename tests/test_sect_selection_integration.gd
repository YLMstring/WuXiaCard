extends SceneTree

const SECT_SCENE: PackedScene = preload("res://scenes/sect_selection.tscn")
const Store = preload("res://scripts/deck_profile_store.gd")
const SelectorController = preload("res://scripts/sect_selection_controller.gd")

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
	_check(selector.upcoming_enemy_name == "测试对手", "Selector accepts the upcoming enemy name")
	_check((canvas.get_node("TopBar/OpponentName") as Label).text == "测试对手", "Header shows the upcoming enemy name")
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

	var expected_sect_ids: Array[StringName] = [
		&"HuaShanPai",
		&"TaiShanPai",
		&"chisha_men",
		&"tingchao_gu",
		&"bailu_shuyuan",
	]
	for index: int in range(expected_sect_ids.size()):
		var entry: Dictionary = grid.library_slots[index]
		_check(
			StringName(String(entry.get("id", ""))) == expected_sect_ids[index],
			"Sect grid preserves catalog order at slot %d" % index
		)
	_check(String(grid.library_slots[5]).is_empty(), "The first unused sect position is empty")
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
	var locked_center: Vector2 = locked_slot.get_global_rect().get_center()
	locked_slot.debug_begin_pointer(locked_center)
	locked_slot.debug_end_pointer(locked_center)
	_check(locked_slot.debug_get_rejected_drag_pulse_count() == 0, "Tapping a locked sect does not pulse")
	selector.card_inspector.close()
	await process_frame
	locked_slot.debug_begin_pointer(locked_center)
	locked_slot.debug_force_hold_timeout()
	locked_slot.debug_end_pointer(locked_center)
	_check(selector.debug_get_selected_sect_id() == &"TaiShanPai", "Holding a locked sect updates selection")
	_check(
		selector.debug_get_upper_preview_ids().is_empty(),
		"A locked sect without cards leaves the preview empty"
	)
	_check(not selector.debug_is_inspecting(), "A hold does not open the inspector")
	_check(not locked_slot.is_drag_armed(), "A locked hold never arms drag")
	_check(selector.debug_get_status() == SelectorController.LOCKED_STATUS, "Locked hold reports its status")
	_check(locked_slot.debug_get_rejected_drag_pulse_count() == 1, "A locked hold pulses exactly once")
	locked_slot.debug_begin_pointer(locked_center)
	locked_slot.debug_force_hold_timeout()
	locked_slot.debug_end_pointer(locked_center)
	_check(locked_slot.debug_get_rejected_drag_pulse_count() == 2, "A repeated locked hold restarts one pulse")

	_check(selector.debug_select_sect(&"chisha_men"), "Debug selection accepts a known sect")
	_check(
		selector.debug_get_lower_preview_ids().slice(0, 2)
		== [&"hengsha_duanlu", &"chilian_huifeng"],
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
	scores["HuaShanPai"] = 4321
	saved_profile["best_scores_by_sect"] = scores
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
	first_slot = grid.debug_get_bound_slot(0)
	first_slot.debug_begin_pointer(first_slot.get_global_rect().get_center())
	first_slot.debug_end_pointer(first_slot.get_global_rect().get_center())
	_check(
		String(selector.card_inspector.get_card_snapshot().get("sect", ""))
		== "最高分：4321",
		"Sect inspection displays the saved per-sect best score"
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
