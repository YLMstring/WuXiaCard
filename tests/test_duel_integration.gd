extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const CARD_SCRIPT: Script = preload("res://scripts/card_view.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var duel: Node = DUEL_SCENE.instantiate()
	root.add_child(duel)
	await process_frame
	await process_frame
	duel.debug_set_fast_mode(true)

	_check_layout(duel)
	_check_card_edge_labels(duel)
	_check_hand_slots(duel.get_node("PlayerHand"))
	_check_hand_slots(duel.get_node("OpponentHand"))
	_check_catalog_hands(duel)
	_check_normal_opponent_concealment(duel)
	await _check_focus_loss_return()
	await _check_dragged_card_commits_through_simulator()
	await _check_testing_mode_manual_turns()
	await _check_player_gate_exile()
	await _check_opponent_tiger_exile()
	var initial_player_card_sizes: Dictionary = _card_sizes_by_slot(duel.get_node("PlayerHand"))

	var player_turns: int = 0
	while not duel.debug_is_complete() and player_turns < 5:
		var target_cell: int = duel.debug_first_empty_cell()
		var placed: bool = await duel.debug_place_player_card(0, target_cell)
		_check(placed, "Player turn %d commits through the production move path" % (player_turns + 1))
		player_turns += 1
		if player_turns == 1:
			await process_frame
			_check_hand_slots(duel.get_node("PlayerHand"))
			_check_remaining_card_sizes(duel.get_node("PlayerHand"), initial_player_card_sizes)

	var scores: Vector2i = duel.debug_get_scores()
	var occupancy: int = duel.debug_get_board_occupancy()
	var simulation_turns: int = duel.debug_get_simulation_turn_count()
	var remaining_cards: int = _count_cards(duel.get_node("PlayerHand")) + _count_cards(duel.get_node("OpponentHand"))
	_check(duel.debug_is_complete(), "Scripted match reaches the complete state")
	_check(scores.x + scores.y == occupancy, "Final scores count exactly the cards remaining on board")
	_check(player_turns == 5, "Player takes five turns when moving first")
	_check(duel.has_method("debug_get_simulation_turn_count"), "Production duel exposes simulator turn-count diagnostics")
	if duel.has_method("debug_get_simulation_turn_count"):
		_check(simulation_turns + remaining_cards == 10, "Every starting card is either placed or remains in hand")
	_check(_count_cards(duel.get_node("PlayerHand")) == 0, "Player hand is empty after five placements")
	_check(not duel.has_node("Arrow"), "Approved layout contains no right-side arrow")
	_check((duel.get_node("TopBar/OpponentName") as Label).text == "Shen Lian", "Opponent name appears in the upper-left top bar")
	_check((duel.get_node("TopBar/ExitButton") as Button).text == "Exit", "Exit button appears in the upper-right top bar")

	duel.queue_free()
	await process_frame
	if _failures == 0:
		print("DUEL_INTEGRATION_PASSED checks=%d player=%d opponent=%d" % [_checks, scores.x, scores.y])
	else:
		push_error("DUEL_INTEGRATION_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check_layout(duel: Node) -> void:
	var opponent_hand := duel.get_node("OpponentHand") as HBoxContainer
	var player_hand := duel.get_node("PlayerHand") as HBoxContainer
	var board_grid := duel.get_node("BoardCenter/BoardGrid") as GridContainer
	var turn_status := duel.get_node("TurnStatus") as Label
	var top_gap: float = board_grid.position.y - (opponent_hand.position.y + opponent_hand.size.y)
	var bottom_gap: float = player_hand.position.y - (board_grid.position.y + board_grid.size.y)
	var board_center_x: float = board_grid.position.x + board_grid.size.x * 0.5
	_check(absf(top_gap - bottom_gap) < 1.0, "Board has equal spacing to opponent and player hands")
	_check(absf(board_center_x - duel.size.x * 0.5) < 1.0, "Board remains horizontally centered")
	_check(absf(board_grid.size.x / board_grid.size.y - duel.board_aspect_ratio) < 0.01, "Board preserves the approved portrait-cell aspect ratio")
	_check(turn_status.position.y >= player_hand.position.y + player_hand.size.y, "Turn status appears below the player hand")
	_check(absf(turn_status.position.x - player_hand.position.x) < 1.0 and absf(turn_status.size.x - player_hand.size.x) < 1.0, "Turn status matches the player hand's horizontal bounds")
	_check(turn_status.position.y + turn_status.size.y <= duel.size.y - 8.0, "Turn status remains inside the bottom safe area")


func _check_card_edge_labels(duel: Node) -> void:
	var first_card := _first_card(duel.get_node("PlayerHand"))
	var top_label := first_card.find_child("TopPower", true, false) as Label
	var right_label := first_card.find_child("RightPower", true, false) as Label
	var bottom_label := first_card.find_child("BottomPower", true, false) as Label
	var left_label := first_card.find_child("LeftPower", true, false) as Label
	var card_rect: Rect2 = first_card.get_global_rect()
	var card_center: Vector2 = card_rect.get_center()
	_check(absf(top_label.get_global_rect().get_center().x - card_center.x) < 1.0 and top_label.get_global_rect().get_center().y < card_center.y, "Top power has its own rectangle centered on the top edge")
	_check(right_label.get_global_rect().get_center().x > card_center.x and absf(right_label.get_global_rect().get_center().y - card_center.y) < 1.0, "Right power has its own rectangle centered on the right edge")
	_check(absf(bottom_label.get_global_rect().get_center().x - card_center.x) < 1.0 and bottom_label.get_global_rect().get_center().y > card_center.y, "Bottom power has its own rectangle centered on the bottom edge")
	_check(left_label.get_global_rect().get_center().x < card_center.x and absf(left_label.get_global_rect().get_center().y - card_center.y) < 1.0, "Left power has its own rectangle centered on the left edge")
	_check(not top_label.text.is_empty() and not right_label.text.is_empty() and not bottom_label.text.is_empty() and not left_label.text.is_empty(), "All four edge powers contain display text")


func _check_hand_slots(container: Node) -> void:
	var has_five_slots: bool = container.get_child_count() == 5
	for child: Node in container.get_children():
		has_five_slots = has_five_slots and child.get_script() != CARD_SCRIPT and _count_cards(child) <= 1
	_check(has_five_slots, "%s keeps five persistent card slots" % container.name)


func _check_catalog_hands(duel: Node) -> void:
	var player_cards: Array[Control] = _cards_below(duel.get_node("PlayerHand"))
	var opponent_cards: Array[Control] = _cards_below(duel.get_node("OpponentHand"))
	var player_ids: Array[StringName] = []
	var opponent_ids: Array[StringName] = []
	for card: Control in player_cards:
		var player_card_data: Dictionary = card.get("card_data")
		player_ids.append(StringName(player_card_data.get("card_id", &"")))
	for card: Control in opponent_cards:
		var opponent_card_data: Dictionary = card.get("card_data")
		opponent_ids.append(StringName(opponent_card_data.get("card_id", &"")))
	_check(player_ids == [&"xu_shu", &"gate_general", &"meng_huo", &"jiang_wei", &"fa_zheng"], "Player hand resolves in catalog deck order")
	_check(opponent_ids == [&"zhang_ren", &"fire_envoy", &"tiger_general", &"strategist", &"sun_zan"], "Opponent hand resolves in catalog deck order")
	var gate_card_data: Dictionary = player_cards[1].get("card_data")
	var tiger_card_data: Dictionary = opponent_cards[2].get("card_data")
	var gate_effects: Array = gate_card_data.get("active_effects", [])
	var tiger_effects: Array = tiger_card_data.get("active_effects", [])
	_check(gate_effects.size() == 1 and bool((gate_effects[0] as Dictionary).get("retained_on_flip", false)), "Gate General view receives its retained catalog effect")
	_check(tiger_effects.size() == 1 and bool((tiger_effects[0] as Dictionary).get("retained_on_flip", false)), "Tiger General view receives its retained catalog effect")
	_check(not duel.has_method("_get_player_cards") and not duel.has_method("_get_opponent_cards"), "Controller no longer owns hard-coded card definitions")


func _check_normal_opponent_concealment(duel: Node) -> void:
	var opponent_cards: Array[Control] = _cards_below(duel.get_node("OpponentHand"))
	var all_concealed: bool = not opponent_cards.is_empty()
	var all_private_data_retained: bool = true
	for card: Control in opponent_cards:
		var card_data: Dictionary = card.get("card_data")
		all_private_data_retained = all_private_data_retained and not String(card_data.get("name", "")).is_empty() and (card_data.get("powers", []) as Array).size() == 4
		all_concealed = (
			all_concealed
			and card.has_method("is_face_down")
			and bool(card.call("is_face_down"))
			and not (card.get_node("Overlay/TopPower") as Label).visible
			and not (card.get_node("Overlay/RightPower") as Label).visible
			and not (card.get_node("Overlay/BottomPower") as Label).visible
			and not (card.get_node("Overlay/LeftPower") as Label).visible
			and card.tooltip_text.is_empty()
		)
	_check(all_concealed, "Normal mode presents every remaining opponent card face-down without power or tooltip leaks")
	_check(all_private_data_retained, "Face-down opponent views retain complete private card data")

	var first_card: Control = opponent_cards[0]
	var first_data: Dictionary = first_card.get("card_data")
	var supports_visibility: bool = first_card.has_method("set_face_down") and first_card.has_method("is_face_down")
	_check(supports_visibility, "Card view exposes reusable face-down presentation controls")
	if supports_visibility:
		first_card.call("set_face_down", false)
		first_card.call("set_face_down", false)
		var powers: Array = first_data.get("powers", [])
		_check(not bool(first_card.call("is_face_down")), "Repeated reveal calls leave the card face-up")
		_check((first_card.get_node("Overlay/ArtPlaceholder") as Label).text == str(first_data.get("glyph", "?")), "Revealing restores the opponent card glyph from retained data")
		_check((first_card.get_node("Overlay/TopPower") as Label).visible and (first_card.get_node("Overlay/TopPower") as Label).text == str(powers[0]), "Revealing restores visible power labels from retained data")
		_check(not first_card.tooltip_text.is_empty(), "Revealing restores the opponent card tooltip")
		first_card.call("set_face_down", true)
		first_card.call("set_face_down", true)
		_check(bool(first_card.call("is_face_down")) and first_card.tooltip_text.is_empty(), "Repeated conceal calls remain idempotent")


func _check_focus_loss_return() -> void:
	var focus_duel: Node = DUEL_SCENE.instantiate()
	root.add_child(focus_duel)
	await process_frame
	await process_frame
	focus_duel.debug_set_fast_mode(true)
	var card: Control = _first_card(focus_duel.get_node("PlayerHand"))
	var home_parent: Node = card.get_parent()
	card.call("_try_begin_drag", card.get_global_rect().get_center(), -1)
	_check(card.get_parent() == focus_duel.get_node("DragLayer"), "A playable card enters the drag layer when dragging starts")
	card.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(card.get_parent() == focus_duel.get_node("DragLayer"), "Focus-loss handling defers scene-tree mutation until notification processing ends")
	await process_frame
	await process_frame
	_check(card.get_parent() == home_parent, "A focus-loss drag cancellation safely returns the card to its slot")
	focus_duel.queue_free()
	await process_frame


func _check_dragged_card_commits_through_simulator() -> void:
	var drag_duel: Node = DUEL_SCENE.instantiate()
	root.add_child(drag_duel)
	await process_frame
	await process_frame
	drag_duel.debug_set_fast_mode(true)
	var card: Control = _first_card(drag_duel.get_node("PlayerHand"))
	drag_duel._on_card_drag_started(card, card.get_global_rect().get_center())
	_check(card.get_parent() == drag_duel.get_node("DragLayer"), "Real drag path reparents the card before commit")
	await drag_duel._commit_card(card, 0, 1)
	_check(drag_duel.debug_get_board_occupancy() == 2, "Dragged player card and opponent reply both commit through production")
	_check(drag_duel.debug_get_simulation_turn_count() == 2, "Real dragged placement advances simulator state for both turns")
	var opponent_board_card: Control = null
	for board_card_value: Variant in drag_duel.get("board_cards"):
		if board_card_value is Control and int((board_card_value as Control).get("owner_id")) == 2:
			opponent_board_card = board_card_value as Control
			break
	_check(opponent_board_card != null, "Normal AI places an opponent card view on the board")
	if opponent_board_card != null:
		_check(opponent_board_card.has_method("is_face_down") and not bool(opponent_board_card.call("is_face_down")), "An AI-played opponent card reveals when it reaches the board")
	drag_duel.queue_free()
	await process_frame


func _check_testing_mode_manual_turns() -> void:
	var test_duel: Node = DUEL_SCENE.instantiate()
	test_duel.set("testing_mode", true)
	root.add_child(test_duel)
	await process_frame
	await process_frame
	test_duel.debug_set_fast_mode(true)

	var player_cards: Array[Control] = _cards_below(test_duel.get_node("PlayerHand"))
	var opponent_cards: Array[Control] = _cards_below(test_duel.get_node("OpponentHand"))
	var all_face_up: bool = true
	for card: Control in player_cards + opponent_cards:
		all_face_up = all_face_up and card.has_method("is_face_down") and not bool(card.call("is_face_down"))
	_check(all_face_up, "Testing mode starts with both hands face-up")
	_check(_count_playable(player_cards) == player_cards.size() and _count_playable(opponent_cards) == 0, "Testing mode initially enables only the player hand")
	_check("Testing" in (test_duel.get_node("TurnStatus") as Label).text and "Player" in (test_duel.get_node("TurnStatus") as Label).text, "Testing status identifies the opening player side")

	var player_card: Control = player_cards[0]
	test_duel._on_card_drag_started(player_card, player_card.get_global_rect().get_center())
	_check(player_card.get_parent() == test_duel.get_node("DragLayer"), "Testing player drag uses the production drag layer")
	await test_duel._commit_card(player_card, 0, 1)
	_check(test_duel.debug_get_board_occupancy() == 1 and test_duel.debug_get_simulation_turn_count() == 1, "Testing mode suppresses the automatic AI reply")
	opponent_cards = _cards_below(test_duel.get_node("OpponentHand"))
	_check(_count_playable(_cards_below(test_duel.get_node("PlayerHand"))) == 0 and _count_playable(opponent_cards) == opponent_cards.size(), "Testing mode enables only the opponent hand on the opponent turn")
	_check("Testing" in (test_duel.get_node("TurnStatus") as Label).text and "Opponent" in (test_duel.get_node("TurnStatus") as Label).text, "Testing status identifies the opponent side")

	var opponent_card: Control = opponent_cards[0]
	var opponent_home: Node = opponent_card.get_parent()
	opponent_card.call("_try_begin_drag", opponent_card.get_global_rect().get_center(), -1)
	_check(opponent_card.get_parent() == test_duel.get_node("DragLayer"), "Testing opponent drag uses the production drag layer")
	opponent_card.call("_try_end_drag", Vector2(-100.0, -100.0), -1)
	await process_frame
	_check(opponent_card.get_parent() == opponent_home, "Invalid testing opponent drop returns to its original top-hand slot")

	opponent_card.call("_try_begin_drag", opponent_card.get_global_rect().get_center(), -1)
	opponent_card.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await process_frame
	await process_frame
	_check(opponent_card.get_parent() == opponent_home, "Focus loss returns a testing opponent card to its original top-hand slot")

	opponent_card.call("_try_begin_drag", opponent_card.get_global_rect().get_center(), -1)
	_check(opponent_card.get_parent() == test_duel.get_node("DragLayer"), "Testing opponent card can begin a second valid drag")
	await test_duel._commit_card(opponent_card, 1, 2)
	_check(test_duel.debug_get_board_occupancy() == 2 and test_duel.debug_get_simulation_turn_count() == 2, "Manual opponent placement advances the production simulator path exactly once")
	_check(_count_playable(_cards_below(test_duel.get_node("PlayerHand"))) == _count_cards(test_duel.get_node("PlayerHand")) and _count_playable(_cards_below(test_duel.get_node("OpponentHand"))) == 0, "Testing control returns to the player hand after the opponent move")
	test_duel.queue_free()
	await process_frame


func _check_player_gate_exile() -> void:
	var exile_duel: Node = DUEL_SCENE.instantiate()
	root.add_child(exile_duel)
	await process_frame
	await process_frame
	exile_duel.debug_set_fast_mode(true)
	_check(exile_duel.has_node("RemovalAudio"), "Duel scene contains dedicated removal audio")
	var gate_view: Control = _cards_below(exile_duel.get_node("PlayerHand"))[1]
	_check(gate_view.has_node("Overlay/InkSlash"), "Card view contains the exile ink overlay")
	_check(gate_view.has_method("play_effect_pulse") and gate_view.has_method("play_exile"), "Card view exposes exile presentation methods")

	var first_placed: bool = await exile_duel.debug_commit_move(1, 0, 0, false)
	var target_placed: bool = await exile_duel.debug_commit_move(2, 1, 5, false)
	var gate_placed: bool = await exile_duel.debug_commit_move(1, 0, 4, false)
	_check(first_placed and target_placed and gate_placed, "Scripted Gate General exile uses production move commits")
	await process_frame
	_check(exile_duel.debug_get_board_occupancy() == 2, "Gate General removes Fire Envoy instead of flipping it")
	_check(exile_duel.has_method("debug_has_board_card_view") and not bool(exile_duel.call("debug_has_board_card_view", 5)), "Gate General exile clears the target card view")
	_check(exile_duel.has_method("debug_get_removed_count") and int(exile_duel.call("debug_get_removed_count", 2)) == 1, "Fire Envoy enters the opponent's removed zone")
	_check(exile_duel.has_method("debug_can_place_at") and bool(exile_duel.call("debug_can_place_at", 5)), "Gate General's cleared cell is reusable")
	var gate_scores: Vector2i = exile_duel.debug_get_scores()
	_check(gate_scores == Vector2i(2, 0), "Gate General exile awards no point for the removed target")
	exile_duel.queue_free()
	await process_frame


func _check_opponent_tiger_exile() -> void:
	var exile_duel: Node = DUEL_SCENE.instantiate()
	root.add_child(exile_duel)
	await process_frame
	await process_frame
	exile_duel.debug_set_fast_mode(true)
	var target_placed: bool = await exile_duel.debug_commit_move(1, 0, 4, false)
	var tiger_placed: bool = await exile_duel.debug_commit_move(2, 2, 5, false)
	_check(target_placed and tiger_placed, "Scripted Tiger General exile uses production move commits")
	await process_frame
	_check(exile_duel.debug_get_board_occupancy() == 1, "Tiger General removes Xu Shu instead of flipping it")
	_check(exile_duel.has_method("debug_has_board_card_view") and not bool(exile_duel.call("debug_has_board_card_view", 4)), "Tiger General exile clears the target card view")
	_check(exile_duel.has_method("debug_get_removed_count") and int(exile_duel.call("debug_get_removed_count", 1)) == 1, "Xu Shu enters the player's removed zone")
	_check(exile_duel.has_method("debug_can_place_at") and bool(exile_duel.call("debug_can_place_at", 4)), "Tiger General's cleared cell is reusable")
	var tiger_scores: Vector2i = exile_duel.debug_get_scores()
	_check(tiger_scores == Vector2i(0, 1), "Tiger General exile awards no point for the removed target")
	exile_duel.queue_free()
	await process_frame


func _check_remaining_card_sizes(container: Node, expected_sizes: Dictionary) -> void:
	var sizes_are_stable: bool = true
	var observed_sizes: Array[String] = []
	for slot: Node in container.get_children():
		for card: Control in _cards_below(slot):
			var expected_size: Vector2 = expected_sizes.get(String(slot.name), Vector2.ZERO)
			sizes_are_stable = sizes_are_stable and card.size.is_equal_approx(expected_size)
			observed_sizes.append("%s=%s" % [slot.name, card.size])
	_check(sizes_are_stable, "%s cards keep their original per-slot size when a slot becomes empty (observed %s)" % [container.name, ", ".join(observed_sizes)])


func _card_sizes_by_slot(container: Node) -> Dictionary:
	var sizes: Dictionary = {}
	for slot: Node in container.get_children():
		for card: Control in _cards_below(slot):
			sizes[String(slot.name)] = card.size
	return sizes


func _first_card(container: Node) -> Control:
	var cards: Array[Control] = _cards_below(container)
	return cards[0] if not cards.is_empty() else null


func _cards_below(container: Node) -> Array[Control]:
	var cards: Array[Control] = []
	for child: Node in container.get_children():
		if child.get_script() == CARD_SCRIPT:
			cards.append(child as Control)
		else:
			cards.append_array(_cards_below(child))
	return cards


func _count_cards(container: Node) -> int:
	return _cards_below(container).size()


func _count_playable(cards: Array[Control]) -> int:
	var count: int = 0
	for card: Control in cards:
		if bool(card.get("playable")):
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
