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
	await _check_focus_loss_return()
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
	_check(duel.debug_is_complete(), "Nine-card scripted match reaches the complete state")
	_check(duel.debug_get_board_occupancy() == 9, "Completed match occupies all nine board cells")
	_check(scores.x + scores.y == 9, "Final ownership scores total nine board cards")
	_check(player_turns == 5, "Player takes five turns when moving first")
	_check(_count_cards(duel.get_node("PlayerHand")) == 0, "Player hand is empty after five placements")
	_check(_count_cards(duel.get_node("OpponentHand")) == 1, "Opponent retains one card after four placements")
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


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
