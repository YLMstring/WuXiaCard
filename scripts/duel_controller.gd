class_name DuelController
extends Control

enum TurnState {
	PLAYER,
	RESOLVING,
	OPPONENT,
	COMPLETE,
}

const CARD_SCENE: PackedScene = preload("res://scenes/card_view.tscn")

@export var board_aspect_ratio: float = 0.78
@export var drag_touch_offset: float = 48.0
@export var snap_duration: float = 0.12
@export var capture_step_delay: float = 0.18
@export var opponent_think_delay: float = 0.55
@export var invalid_shake_duration: float = 0.18
@export var placement_haptic_ms: int = 20
@export var multi_capture_haptic_ms: int = 45

var turn_state: TurnState = TurnState.PLAYER
var board: Array = DuelRules.empty_board()
var board_cells: Array[PanelContainer] = []
var board_cards: Array = []
var _hovered_cell: int = -1

@onready var board_grid: GridContainer = $BoardCenter/BoardGrid
@onready var top_bar: HBoxContainer = $TopBar
@onready var opponent_name: Label = $TopBar/OpponentName
@onready var exit_button: Button = $TopBar/ExitButton
@onready var opponent_hand: HBoxContainer = $OpponentHand
@onready var player_hand: HBoxContainer = $PlayerHand
@onready var score_overlay: VBoxContainer = $ScoreOverlay
@onready var opponent_score_panel: PanelContainer = $ScoreOverlay/OpponentScorePanel
@onready var player_score_panel: PanelContainer = $ScoreOverlay/PlayerScorePanel
@onready var opponent_score: Label = $ScoreOverlay/OpponentScorePanel/OpponentScore
@onready var player_score: Label = $ScoreOverlay/PlayerScorePanel/PlayerScore
@onready var turn_status: Label = $TurnStatus
@onready var drag_layer: Control = $DragLayer
@onready var placement_audio: AudioStreamPlayer = $PlacementAudio
@onready var capture_audio: AudioStreamPlayer = $CaptureAudio


func _ready() -> void:
	board_cards.resize(9)
	board_cards.fill(null)
	_create_board_cells()
	_create_hands()
	_create_placeholder_audio()
	_style_static_ui()
	exit_button.pressed.connect(_on_exit_pressed)
	resized.connect(_layout_duel)
	get_viewport().size_changed.connect(_layout_duel)
	opponent_name.text = "Shen Lian"
	turn_state = TurnState.PLAYER
	_set_hand_playable(true)
	_update_score()
	_update_turn_status()
	_layout_duel.call_deferred()


func debug_set_fast_mode(enabled: bool) -> void:
	if enabled:
		snap_duration = 0.0
		capture_step_delay = 0.0
		opponent_think_delay = 0.0
		invalid_shake_duration = 0.0


func debug_place_player_card(hand_index: int, cell_index: int) -> bool:
	if turn_state != TurnState.PLAYER or not DuelRules.can_place(board, cell_index):
		return false
	var cards: Array[CardView] = _get_cards_in_hand(player_hand)
	if hand_index < 0 or hand_index >= cards.size():
		return false
	await _commit_card(cards[hand_index], cell_index, DuelRules.PLAYER_OWNER)
	return true


func debug_first_empty_cell() -> int:
	return DuelRules.first_empty_cell(board)


func debug_get_board_occupancy() -> int:
	var count: int = 0
	for slot: Variant in board:
		if slot != null:
			count += 1
	return count


func debug_get_scores() -> Vector2i:
	return Vector2i(
		DuelRules.count_owned(board, DuelRules.PLAYER_OWNER),
		DuelRules.count_owned(board, DuelRules.OPPONENT_OWNER)
	)


func debug_is_complete() -> bool:
	return turn_state == TurnState.COMPLETE


func _create_board_cells() -> void:
	for cell_index: int in range(9):
		var cell := PanelContainer.new()
		cell.name = "Cell%d" % cell_index
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board_grid.add_child(cell)
		board_cells.append(cell)
		_set_cell_style(cell_index, "normal")


func _create_hands() -> void:
	for card_data: Dictionary in _get_opponent_cards():
		_spawn_card(opponent_hand, card_data, DuelRules.OPPONENT_OWNER, false)
	for card_data: Dictionary in _get_player_cards():
		_spawn_card(player_hand, card_data, DuelRules.PLAYER_OWNER, true)


func _spawn_card(container: HBoxContainer, card_data: Dictionary, owner_id: int, is_playable: bool) -> CardView:
	var slot := PanelContainer.new()
	slot.name = "Slot%d" % container.get_child_count()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slot_style := StyleBoxFlat.new()
	slot_style.bg_color = Color(1.0, 1.0, 1.0, 0.06)
	slot_style.border_color = Color(1.0, 1.0, 1.0, 0.10)
	slot_style.set_border_width_all(1)
	slot_style.set_corner_radius_all(5)
	slot.add_theme_stylebox_override("panel", slot_style)
	container.add_child(slot)
	var card := CARD_SCENE.instantiate() as CardView
	slot.custom_minimum_size = card.custom_minimum_size
	slot.add_child(card)
	card.touch_drag_offset = drag_touch_offset
	card.configure(card_data, owner_id, is_playable)
	if owner_id == DuelRules.PLAYER_OWNER:
		card.drag_started.connect(_on_card_drag_started)
		card.drag_moved.connect(_on_card_drag_moved)
		card.drag_ended.connect(_on_card_drag_ended)
	return card


func _on_card_drag_started(card: CardView, _pointer_position: Vector2) -> void:
	if turn_state != TurnState.PLAYER:
		card.finish_drag_state()
		return
	card.reparent(drag_layer, true)
	_highlight_legal_cells()


func _on_card_drag_moved(_card: CardView, pointer_position: Vector2) -> void:
	var target_cell: int = _get_cell_at_position(pointer_position)
	if target_cell == _hovered_cell:
		return
	_hovered_cell = target_cell
	_highlight_legal_cells()
	if target_cell >= 0 and DuelRules.can_place(board, target_cell):
		_set_cell_style(target_cell, "hover")


func _on_card_drag_ended(card: CardView, pointer_position: Vector2) -> void:
	var target_cell: int = _get_cell_at_position(pointer_position)
	_clear_cell_highlights()
	if turn_state == TurnState.PLAYER and DuelRules.can_place(board, target_cell):
		card.finish_drag_state()
		await _commit_card(card, target_cell, DuelRules.PLAYER_OWNER)
		return
	_return_card_to_hand(card)
	card.play_invalid_shake(invalid_shake_duration)


func _return_card_to_hand(card: CardView) -> void:
	var home_parent: Node = card.get_home_parent()
	if home_parent == null or not is_instance_valid(home_parent):
		home_parent = player_hand
	card.reparent(home_parent, false)
	var target_index: int = clampi(card.get_home_index(), 0, home_parent.get_child_count() - 1)
	home_parent.move_child(card, target_index)
	card.finish_drag_state()


func _commit_card(card: CardView, cell_index: int, owner_id: int) -> void:
	if not DuelRules.can_place(board, cell_index):
		return
	turn_state = TurnState.RESOLVING
	_set_hand_playable(false)
	_update_turn_status()

	var target_cell: PanelContainer = board_cells[cell_index]
	card.reparent(target_cell, false)
	card.set_playable(false)
	card.scale = Vector2(0.9, 0.9)
	card.rotation = 0.0
	board_cards[cell_index] = card
	var captured: Array[int] = DuelRules.place_card(board, cell_index, card.card_data, owner_id)

	_play_placement_feedback()
	if snap_duration > 0.0:
		var snap_tween: Tween = create_tween()
		snap_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		snap_tween.tween_property(card, "scale", Vector2.ONE, snap_duration)
		await snap_tween.finished
	else:
		card.scale = Vector2.ONE

	for captured_index: int in captured:
		if capture_step_delay > 0.0:
			await get_tree().create_timer(capture_step_delay).timeout
		var captured_card := board_cards[captured_index] as CardView
		if captured_card != null:
			_play_capture_feedback()
			await captured_card.play_capture_flip(owner_id, maxf(capture_step_delay, 0.02))

	if captured.size() > 1:
		_vibrate(multi_capture_haptic_ms)
	_update_score()

	if DuelRules.is_board_full(board):
		_finish_match()
		return

	if owner_id == DuelRules.PLAYER_OWNER:
		turn_state = TurnState.OPPONENT
		_update_turn_status()
		if opponent_think_delay > 0.0:
			await get_tree().create_timer(opponent_think_delay).timeout
		await _perform_opponent_turn()
	else:
		turn_state = TurnState.PLAYER
		_set_hand_playable(true)
		_update_turn_status()


func _perform_opponent_turn() -> void:
	var opponent_cards: Array[CardView] = _get_cards_in_hand(opponent_hand)
	var card_data: Array = []
	for card: CardView in opponent_cards:
		card_data.append(card.card_data)
	var choice: Vector2i = DuelRules.choose_ai_move(board, card_data, DuelRules.OPPONENT_OWNER)
	if choice.x < 0 or choice.y < 0:
		_finish_match()
		return
	await _commit_card(opponent_cards[choice.x], choice.y, DuelRules.OPPONENT_OWNER)


func _finish_match() -> void:
	turn_state = TurnState.COMPLETE
	_set_hand_playable(false)
	var player_total: int = DuelRules.count_owned(board, DuelRules.PLAYER_OWNER)
	var opponent_total: int = DuelRules.count_owned(board, DuelRules.OPPONENT_OWNER)
	if player_total > opponent_total:
		turn_status.text = "Victory · %d–%d" % [player_total, opponent_total]
	else:
		turn_status.text = "Defeat · %d–%d" % [player_total, opponent_total]
	turn_status.modulate = Color("3b211d")
	print("DUEL_COMPLETE player=%d opponent=%d" % [player_total, opponent_total])


func _set_hand_playable(value: bool) -> void:
	for card: CardView in _get_cards_in_hand(player_hand):
		card.set_playable(value and turn_state == TurnState.PLAYER)


func _get_cards_in_hand(container: HBoxContainer) -> Array[CardView]:
	var result: Array[CardView] = []
	for slot: Node in container.get_children():
		for child: Node in slot.get_children():
			if child is CardView:
				result.append(child as CardView)
	return result


func _get_cell_at_position(pointer_position: Vector2) -> int:
	for cell_index: int in range(board_cells.size()):
		if board_cells[cell_index].get_global_rect().has_point(pointer_position):
			return cell_index
	return -1


func _highlight_legal_cells() -> void:
	for cell_index: int in range(board_cells.size()):
		if DuelRules.can_place(board, cell_index):
			_set_cell_style(cell_index, "legal")
		else:
			_set_cell_style(cell_index, "normal")


func _clear_cell_highlights() -> void:
	_hovered_cell = -1
	for cell_index: int in range(board_cells.size()):
		_set_cell_style(cell_index, "normal")


func _set_cell_style(cell_index: int, mode: String) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.56, 0.53, 0.46, 0.42)
	style.border_color = Color("c7bda8")
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	if mode == "legal":
		style.bg_color = Color(0.93, 0.84, 0.55, 0.34)
		style.border_color = Color("d2a63f")
		style.set_border_width_all(3)
	elif mode == "hover":
		style.bg_color = Color(1.0, 0.89, 0.45, 0.62)
		style.border_color = Color("f0c95b")
		style.set_border_width_all(4)
	board_cells[cell_index].add_theme_stylebox_override("panel", style)


func _update_score() -> void:
	opponent_score.text = str(DuelRules.count_owned(board, DuelRules.OPPONENT_OWNER))
	player_score.text = str(DuelRules.count_owned(board, DuelRules.PLAYER_OWNER))


func _update_turn_status() -> void:
	match turn_state:
		TurnState.PLAYER:
			turn_status.text = "Your turn · drag a card"
		TurnState.RESOLVING:
			turn_status.text = "Resolving…"
		TurnState.OPPONENT:
			turn_status.text = "Shen Lian considers…"
		TurnState.COMPLETE:
			pass


func _layout_duel() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	var horizontal_margin: float = maxf(12.0, size.x * 0.03)
	var available_hand_width: float = size.x - horizontal_margin * 2.0
	var card_width: float = (available_hand_width - 16.0) / 5.0
	var hand_height: float = minf(size.y * 0.14, card_width / 0.75)
	var opponent_top: float = maxf(size.y * 0.085, 72.0)
	var opponent_bottom: float = opponent_top + hand_height
	var status_gap: float = 8.0
	var status_height: float = 26.0
	var bottom_safe_margin: float = 8.0
	var player_bottom_margin: float = maxf(size.y * 0.05, status_gap + status_height + bottom_safe_margin)
	var player_top: float = size.y - player_bottom_margin - hand_height
	var interval_height: float = maxf(180.0, player_top - opponent_bottom)
	var minimum_gap: float = maxf(18.0, size.y * 0.032)
	var desired_board_width: float = size.x * 0.72
	var board_height: float = minf(desired_board_width / board_aspect_ratio, interval_height - minimum_gap * 2.0)
	var board_width: float = board_height * board_aspect_ratio
	var equal_gap: float = (interval_height - board_height) * 0.5
	var board_position := Vector2((size.x - board_width) * 0.5, opponent_bottom + equal_gap)

	top_bar.position = Vector2(horizontal_margin, maxf(12.0, size.y * 0.016))
	top_bar.size = Vector2(available_hand_width, maxf(44.0, size.y * 0.05))
	opponent_hand.position = Vector2(horizontal_margin, opponent_top)
	opponent_hand.size = Vector2(available_hand_width, hand_height)
	player_hand.position = Vector2(horizontal_margin, player_top)
	player_hand.size = Vector2(available_hand_width, hand_height)
	board_grid.position = board_position
	board_grid.size = Vector2(board_width, board_height)

	var score_width: float = minf(46.0, size.x * 0.085)
	var score_x: float = minf(size.x - horizontal_margin - score_width, board_position.x + board_width + 8.0)
	score_overlay.position = Vector2(score_x, board_position.y + board_height * 0.5 - 60.0)
	score_overlay.size = Vector2(score_width, 120.0)
	var desired_status_y: float = player_hand.position.y + player_hand.size.y + status_gap
	var maximum_status_y: float = size.y - bottom_safe_margin - status_height
	turn_status.position = Vector2(player_hand.position.x, minf(desired_status_y, maximum_status_y))
	turn_status.size = Vector2(player_hand.size.x, status_height)


func _style_static_ui() -> void:
	var opponent_style := StyleBoxFlat.new()
	opponent_style.bg_color = Color("d9695f")
	opponent_style.border_color = Color("8c403a")
	opponent_style.set_border_width_all(2)
	opponent_style.set_corner_radius_all(5)
	opponent_score_panel.add_theme_stylebox_override("panel", opponent_style)
	var player_style := StyleBoxFlat.new()
	player_style.bg_color = Color("85bad1")
	player_style.border_color = Color("416e82")
	player_style.set_border_width_all(2)
	player_style.set_corner_radius_all(5)
	player_score_panel.add_theme_stylebox_override("panel", player_style)


func _create_placeholder_audio() -> void:
	placement_audio.stream = _make_tone(190.0, 0.07)
	capture_audio.stream = _make_tone(470.0, 0.09)


func _make_tone(frequency: float, duration: float) -> AudioStreamWAV:
	var sample_rate: int = 22050
	var sample_count: int = int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for sample_index: int in range(sample_count):
		var time: float = float(sample_index) / float(sample_rate)
		var envelope: float = 1.0 - float(sample_index) / float(sample_count)
		var wave: float = sin(TAU * frequency * time) * envelope * 0.18
		bytes.encode_s16(sample_index * 2, int(wave * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = bytes
	return stream


func _play_placement_feedback() -> void:
	if not OS.has_feature("headless"):
		placement_audio.play()
	_vibrate(placement_haptic_ms)


func _play_capture_feedback() -> void:
	if not OS.has_feature("headless"):
		capture_audio.play()


func _vibrate(duration_ms: int) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms)


func _on_exit_pressed() -> void:
	get_tree().quit()


func _get_player_cards() -> Array[Dictionary]:
	return [
		DuelRules.make_card("Xu Shu", "徐", [3, 2, 3, 2]),
		DuelRules.make_card("Gate General", "关", [7, 7, 7, 7]),
		DuelRules.make_card("Meng Huo", "孟", [8, 7, 2, 3]),
		DuelRules.make_card("Jiang Wei", "姜", [6, 6, 6, 6]),
		DuelRules.make_card("Fa Zheng", "法", [5, 4, 4, 3]),
	]


func _get_opponent_cards() -> Array[Dictionary]:
	return [
		DuelRules.make_card("Zhang Ren", "张", [4, 7, 7, 4]),
		DuelRules.make_card("Fire Envoy", "火", [5, 5, 4, 4]),
		DuelRules.make_card("Tiger General", "虎", [3, 4, 8, 8]),
		DuelRules.make_card("Strategist", "策", [4, 4, 4, 4]),
		DuelRules.make_card("Sun Zan", "孙", [3, 5, 8, 8]),
	]
