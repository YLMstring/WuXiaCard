class_name DuelController
extends Control

enum TurnState {
	PLAYER,
	RESOLVING,
	OPPONENT,
	COMPLETE,
}

const CARD_SCENE: PackedScene = preload("res://scenes/card_view.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const Decks = preload("res://scripts/duel_decks.gd")
const Settings = preload("res://scripts/game_settings.gd")
const StateData = preload("res://scripts/duel_state.gd")
const MoveData = preload("res://scripts/duel_move.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const SIMULATOR_HAND_INDEX_META: StringName = &"simulator_hand_index"

@export var board_aspect_ratio: float = 0.78
@export var drag_touch_offset: float = 48.0
@export var snap_duration: float = 0.12
@export var capture_step_delay: float = 0.18
@export var exile_pulse_duration: float = 0.14
@export var exile_duration: float = 0.22
@export var exile_step_delay: float = 0.10
@export var exile_ink_color: Color = Color("6f1118")
@export var removal_audio_volume_db: float = -4.0
@export var opponent_think_delay: float = 0.55
@export var invalid_shake_duration: float = 0.18
@export var placement_haptic_ms: int = 20
@export var multi_capture_haptic_ms: int = 45

var turn_state: TurnState = TurnState.PLAYER
var testing_mode: bool = Settings.TESTING_MODE
var board: Array = DuelRules.empty_board()
var duel_state: StateData = null
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
@onready var removal_audio: AudioStreamPlayer = $RemovalAudio


func _ready() -> void:
	board_cards.resize(9)
	board_cards.fill(null)
	_create_board_cells()
	var catalog_errors: Array[String] = Catalog.validate_catalog()
	assert(catalog_errors.is_empty(), "Invalid card catalog: %s" % str(catalog_errors))
	var player_cards: Array = _create_card_instances(Decks.get_player_card_ids(), DuelRules.PLAYER_OWNER)
	var opponent_cards: Array = _create_card_instances(Decks.get_opponent_card_ids(), DuelRules.OPPONENT_OWNER)
	duel_state = StateData.new(
		board,
		player_cards,
		opponent_cards,
		DuelRules.PLAYER_OWNER
	)
	board = duel_state.board
	_create_hands()
	_create_placeholder_audio()
	_style_static_ui()
	exit_button.pressed.connect(_on_exit_pressed)
	resized.connect(_layout_duel)
	get_viewport().size_changed.connect(_layout_duel)
	opponent_name.text = "Shen Lian"
	turn_state = TurnState.PLAYER
	_sync_hand_playability()
	_update_score()
	_update_turn_status()
	_layout_duel.call_deferred()


func debug_set_fast_mode(enabled: bool) -> void:
	if enabled:
		snap_duration = 0.0
		capture_step_delay = 0.0
		exile_pulse_duration = 0.0
		exile_duration = 0.0
		exile_step_delay = 0.0
		opponent_think_delay = 0.0
		invalid_shake_duration = 0.0


func debug_place_player_card(hand_index: int, cell_index: int) -> bool:
	var move := MoveData.new(hand_index, cell_index)
	if (
		turn_state != TurnState.PLAYER
		or duel_state == null
		or duel_state.active_player != DuelRules.PLAYER_OWNER
		or not Simulator.is_move_legal(duel_state, move)
	):
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


func debug_get_simulation_turn_count() -> int:
	return duel_state.turn_count if duel_state != null else 0


func debug_has_board_card_view(cell_index: int) -> bool:
	return (
		cell_index >= 0
		and cell_index < board_cards.size()
		and board_cards[cell_index] != null
		and is_instance_valid(board_cards[cell_index])
	)


func debug_get_removed_count(owner_id: int) -> int:
	if duel_state == null:
		return 0
	return (duel_state.removed_cards.get(owner_id, []) as Array).size()


func debug_can_place_at(cell_index: int) -> bool:
	return DuelRules.can_place(board, cell_index)


func debug_commit_move(
	owner_id: int,
	hand_index: int,
	cell_index: int,
	continue_automatically: bool = false
) -> bool:
	if duel_state == null or duel_state.active_player != owner_id:
		return false
	var source_hand: HBoxContainer = player_hand if owner_id == DuelRules.PLAYER_OWNER else opponent_hand
	var cards: Array[CardView] = _get_cards_in_hand(source_hand)
	if hand_index < 0 or hand_index >= cards.size():
		return false
	var move := MoveData.new(hand_index, cell_index)
	if not Simulator.is_move_legal(duel_state, move):
		return false
	await _commit_card(cards[hand_index], cell_index, owner_id, continue_automatically)
	return true


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
	for card_data: Dictionary in duel_state.get_hand(DuelRules.OPPONENT_OWNER):
		var opponent_card: CardView = _spawn_card(opponent_hand, card_data, DuelRules.OPPONENT_OWNER, false)
		opponent_card.set_face_down(not testing_mode)
	for card_data: Dictionary in duel_state.get_hand(DuelRules.PLAYER_OWNER):
		_spawn_card(player_hand, card_data, DuelRules.PLAYER_OWNER, false)


func _create_card_instances(card_ids: Array[StringName], owner_id: int) -> Array:
	var instances: Array = []
	for card_index: int in range(card_ids.size()):
		var instance_id := StringName("card_%d_%d" % [owner_id, card_index])
		instances.append(Catalog.create_instance(card_ids[card_index], owner_id, instance_id))
	return instances


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
	card.drag_started.connect(_on_card_drag_started)
	card.drag_moved.connect(_on_card_drag_moved)
	card.drag_ended.connect(_on_card_drag_ended)
	return card


func _on_card_drag_started(card: CardView, _pointer_position: Vector2) -> void:
	if not _can_manually_drag(card):
		card.finish_drag_state()
		return
	var source_hand: HBoxContainer = _get_hand_for_owner(card.owner_id)
	card.set_meta(SIMULATOR_HAND_INDEX_META, _get_cards_in_hand(source_hand).find(card))
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
	if _can_manually_drag(card) and DuelRules.can_place(board, target_cell):
		card.finish_drag_state()
		await _commit_card(card, target_cell, card.owner_id)
		return
	_return_card_to_hand(card)
	card.play_invalid_shake(invalid_shake_duration)


func _return_card_to_hand(card: CardView) -> void:
	var home_parent: Node = card.get_home_parent()
	if home_parent == null or not is_instance_valid(home_parent):
		home_parent = _get_hand_for_owner(card.owner_id)
	card.reparent(home_parent, false)
	var target_index: int = clampi(card.get_home_index(), 0, home_parent.get_child_count() - 1)
	home_parent.move_child(card, target_index)
	card.remove_meta(SIMULATOR_HAND_INDEX_META)
	card.finish_drag_state()


func _commit_card(
	card: CardView,
	cell_index: int,
	owner_id: int,
	continue_automatically: bool = true
) -> void:
	if duel_state == null or duel_state.active_player != owner_id:
		return
	var source_hand: HBoxContainer = player_hand if owner_id == DuelRules.PLAYER_OWNER else opponent_hand
	var source_cards: Array[CardView] = _get_cards_in_hand(source_hand)
	var hand_index: int = source_cards.find(card)
	if hand_index < 0 and card.has_meta(SIMULATOR_HAND_INDEX_META):
		hand_index = int(card.get_meta(SIMULATOR_HAND_INDEX_META))
	var move := MoveData.new(hand_index, cell_index)
	if not Simulator.is_move_legal(duel_state, move):
		return
	var transition: Dictionary = Simulator.apply_move(duel_state, move)
	if not bool(transition.get("valid", false)):
		return
	duel_state = transition["state"] as StateData
	board = duel_state.board
	var events: Array = transition.get("events", [])
	card.remove_meta(SIMULATOR_HAND_INDEX_META)

	turn_state = TurnState.RESOLVING
	_sync_hand_playability()
	_update_turn_status()

	var target_cell: PanelContainer = board_cells[cell_index]
	card.set_face_down(false)
	card.reparent(target_cell, false)
	card.set_playable(false)
	card.scale = Vector2(0.9, 0.9)
	card.rotation = 0.0
	board_cards[cell_index] = card

	_play_placement_feedback()
	if snap_duration > 0.0:
		var snap_tween: Tween = create_tween()
		snap_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		snap_tween.tween_property(card, "scale", Vector2.ONE, snap_duration)
		await snap_tween.finished
	else:
		card.scale = Vector2.ONE

	var resolved_targets: int = await _present_transition_events(events, owner_id)
	if resolved_targets > 1:
		_vibrate(multi_capture_haptic_ms)
	_update_score()

	if Simulator.is_terminal(duel_state):
		_finish_match()
		return

	if duel_state.active_player == DuelRules.PLAYER_OWNER:
		turn_state = TurnState.PLAYER
		_sync_hand_playability()
		_update_turn_status()
		return

	turn_state = TurnState.OPPONENT
	_sync_hand_playability()
	_update_turn_status()
	if testing_mode or not continue_automatically:
		return
	if opponent_think_delay > 0.0:
		await get_tree().create_timer(opponent_think_delay).timeout
	await _perform_opponent_turn()


func _present_transition_events(events: Array, fallback_owner: int) -> int:
	var resolved_targets: int = 0
	var source_pulsed: bool = false
	for event_value: Variant in events:
		var event: Dictionary = event_value
		var event_type := StringName(event.get("type", &""))
		var target_cell: int = int(event.get("target_cell", -1))
		if event_type == &"card_flipped":
			if capture_step_delay > 0.0:
				await get_tree().create_timer(capture_step_delay).timeout
			var flipped_card := board_cards[target_cell] as CardView
			if flipped_card != null:
				_play_capture_feedback()
				var new_owner: int = int(event.get("owner_id", fallback_owner))
				await flipped_card.play_capture_flip(new_owner, maxf(capture_step_delay, 0.02))
			resolved_targets += 1
		elif event_type == &"ability_lost":
			var changed_card := board_cards[target_cell] as CardView
			if changed_card != null:
				await changed_card.play_ability_lost(
					StringName(event.get("effect_id", &"")),
					capture_step_delay * 0.5
				)
		elif event_type == &"card_exiled":
			if not source_pulsed:
				var source_cell: int = int(event.get("source_cell", -1))
				var source_card := board_cards[source_cell] as CardView if source_cell >= 0 and source_cell < board_cards.size() else null
				if source_card != null:
					_play_removal_feedback()
					await source_card.play_effect_pulse(exile_pulse_duration)
				source_pulsed = true
			if exile_step_delay > 0.0:
				await get_tree().create_timer(exile_step_delay).timeout
			var exiled_card := board_cards[target_cell] as CardView
			board_cards[target_cell] = null
			if exiled_card != null:
				_play_removal_feedback()
				await exiled_card.play_exile(exile_duration, exile_ink_color)
				exiled_card.queue_free()
			resolved_targets += 1
	return resolved_targets


func _perform_opponent_turn() -> void:
	var opponent_cards: Array[CardView] = _get_cards_in_hand(opponent_hand)
	var choice: MoveData = Simulator.choose_greedy_move(duel_state)
	if (
		choice.hand_index < 0
		or choice.hand_index >= opponent_cards.size()
		or choice.cell_index < 0
	):
		_finish_match()
		return
	await _commit_card(
		opponent_cards[choice.hand_index],
		choice.cell_index,
		DuelRules.OPPONENT_OWNER
	)


func _finish_match() -> void:
	turn_state = TurnState.COMPLETE
	_sync_hand_playability()
	var player_total: int = DuelRules.count_owned(board, DuelRules.PLAYER_OWNER)
	var opponent_total: int = DuelRules.count_owned(board, DuelRules.OPPONENT_OWNER)
	if player_total > opponent_total:
		turn_status.text = "Victory · %d–%d" % [player_total, opponent_total]
	else:
		turn_status.text = "Defeat · %d–%d" % [player_total, opponent_total]
	turn_status.modulate = Color("3b211d")
	print("DUEL_COMPLETE player=%d opponent=%d" % [player_total, opponent_total])


func _sync_hand_playability() -> void:
	for card: CardView in _get_cards_in_hand(player_hand):
		card.set_playable(
			turn_state == TurnState.PLAYER
			and duel_state != null
			and duel_state.active_player == DuelRules.PLAYER_OWNER
		)
	for card: CardView in _get_cards_in_hand(opponent_hand):
		card.set_playable(
			testing_mode
			and turn_state == TurnState.OPPONENT
			and duel_state != null
			and duel_state.active_player == DuelRules.OPPONENT_OWNER
		)


func _can_manually_drag(card: CardView) -> bool:
	if duel_state == null or duel_state.active_player != card.owner_id:
		return false
	if card.owner_id == DuelRules.PLAYER_OWNER:
		return turn_state == TurnState.PLAYER
	if card.owner_id == DuelRules.OPPONENT_OWNER:
		return testing_mode and turn_state == TurnState.OPPONENT
	return false


func _get_hand_for_owner(owner_id: int) -> HBoxContainer:
	return player_hand if owner_id == DuelRules.PLAYER_OWNER else opponent_hand


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
			turn_status.text = "Testing · Player side · drag a card" if testing_mode else "Your turn · drag a card"
		TurnState.RESOLVING:
			turn_status.text = "Resolving…"
		TurnState.OPPONENT:
			turn_status.text = "Testing · Opponent side · drag a card" if testing_mode else "Shen Lian considers…"
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
	removal_audio.stream = _make_removal_tone(0.14)
	removal_audio.volume_db = removal_audio_volume_db


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


func _make_removal_tone(duration: float) -> AudioStreamWAV:
	var sample_rate: int = 22050
	var sample_count: int = int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for sample_index: int in range(sample_count):
		var time: float = float(sample_index) / float(sample_rate)
		var progress: float = float(sample_index) / float(sample_count)
		var envelope: float = (1.0 - progress) * (1.0 - progress)
		var low_brush: float = sin(TAU * (118.0 - progress * 42.0) * time) * 0.13
		var paper_texture: float = sin(TAU * 1511.0 * time) * sin(TAU * 887.0 * time) * 0.055
		var wave: float = (low_brush + paper_texture) * envelope
		bytes.encode_s16(sample_index * 2, int(clampf(wave, -1.0, 1.0) * 32767.0))
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


func _play_removal_feedback() -> void:
	if not OS.has_feature("headless"):
		removal_audio.play()


func _vibrate(duration_ms: int) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms)


func _on_exit_pressed() -> void:
	get_tree().quit()
