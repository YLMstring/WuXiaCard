class_name DuelController
extends Control

signal return_requested(outcome: StringName)
signal opponent_card_played(glyph: String)

const OUTCOME_VICTORY: StringName = &"victory"
const OUTCOME_DEFEAT: StringName = &"defeat"
const OUTCOME_ABANDONED: StringName = &"abandoned"

enum TurnState {
	PLAYER,
	RESOLVING,
	OPPONENT,
	COMPLETE,
}

const CARD_SCENE: PackedScene = preload("res://scenes/card_view.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const Abilities = preload("res://scripts/duel_abilities.gd")
const Decks = preload("res://scripts/duel_decks.gd")
const Settings = preload("res://scripts/game_settings.gd")
const StateData = preload("res://scripts/duel_state.gd")
const ActionData = preload("res://scripts/duel_action.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const SearchSession = preload("res://scripts/duel_search_session.gd")
const CardInspectorData = preload("res://scripts/card_inspector.gd")
const ExtraTurnVfxData = preload("res://scripts/extra_turn_vfx.gd")
const AttackVfxData = preload("res://scripts/attack_vfx.gd")
const DuelBackdropData = preload("res://scripts/duel_backdrop.gd")
const ReplayRecordData = preload("res://scripts/duel_replay_record.gd")
const Revelation = preload("res://scripts/duel_revelation.gd")

@export var board_aspect_ratio: float = 0.78
@export var drag_touch_offset: float = 48.0
@export var snap_duration: float = 0.12
@export var capture_flip_duration: float = 0.18
@export var attack_vfx_duration: float = 0.15
@export var ability_trigger_pulse_duration: float = 0.14
@export var exile_duration: float = 0.22
@export var exile_step_delay: float = 0.10
@export var exile_ink_color: Color = Color("6f1118")
@export var card_fade_duration: float = 0.18
@export var removal_audio_volume_db: float = -4.0
@export var movement_audio_volume_db: float = -9.0
@export var movement_duration: float = 0.20
@export var swap_duration: float = 0.28
@export var swap_arc_ratio: float = 0.12
@export var summon_swap_readable_duration: float = 0.30
@export var targeting_trace_width: float = 6.0
@export var targeting_trace_color: Color = Color(0.12, 0.42, 0.38, 0.72)
@export var ki_gain_pulse_duration: float = 0.18
@export var extra_card_play_status_duration: float = 0.35
@export var extra_card_play_effect_color: Color = Color("e3b84f")
@export var draw_bloom_duration: float = 0.12
@export var draw_rise_duration: float = 0.28
@export var draw_post_effect_gap: float = 0.20
@export var draw_ink_color: Color = Color("211824")
@export var side_deck_shuffle_seed: int = 0
@export var player_hand_shuffle_seed: int = 0
@export var opponent_hand_shuffle_seed: int = 0
@export var opponent_think_delay: float = 0.55
@export var opponent_search_budget_seconds: float = 10.0
@export_range(0.0, 10.0, 0.05) var replay_turn_delay: float = 2.0
@export var invalid_shake_duration: float = 0.18
@export var placement_haptic_ms: int = 20
@export var multi_capture_haptic_ms: int = 45
@export var deck_profile_path: String = "user://wuxia_deck_profile.json"
@export var starting_owner_id: int = DuelRules.PLAYER_OWNER
@export var opponent_name_text: String = "对手名字"
@export var opponent_card_ids: Array[StringName] = []
@export var remembered_enemy_glyphs: Array[String] = []

var turn_state: TurnState = TurnState.PLAYER
var testing_mode: bool = Settings.TESTING_MODE
var board: Array = DuelRules.empty_board()
var duel_state: StateData = null
var board_cells: Array[PanelContainer] = []
var board_cards: Array = []
var _hovered_cell: int = -1
var _drag_source_zone: StringName = &""
var _drag_source_index: int = -1
var _drag_valid_targets: Array[int] = []
var _drag_action_candidates: Array[ActionData] = []
var _targeting_trace: Line2D = null
var _targeting_trace_end_global: Vector2 = Vector2.ZERO
var _fast_mode: bool = false
var _presentation_trace: Array[StringName] = []
var _attack_vfx_trace: Array[Dictionary] = []
var _ability_pulse_trace: Array[StringName] = []
var _ki_presentation_trace: Array[int] = []
var _movement_presentation_trace: Array[Dictionary] = []
var _movement_sound_count: int = 0
var _opponent_search_session: SearchSession = null
var _opponent_search_started_usec: int = 0
var _opponent_search_test_limits: Dictionary = {}
var _last_search_report: Dictionary = {}
var _inspection_open: bool = false
var _board_visible_before_inspection: bool = true
var _scores_visible_before_inspection: bool = true
var _match_outcome: StringName = &""
var _return_emitted: bool = false
var _status_before_inspection: String = ""
var _mastery_eligible_card_ids: Dictionary = {}
var _mastery_candidate_ids: Array[StringName] = []
var _mastery_candidate_set: Dictionary = {}
var _replay_record: ReplayRecordData = ReplayRecordData.new()
var _is_replaying: bool = false
var _is_replay_presenting_action: bool = false
var _replay_generation: int = 0
var _replay_feedback_tween: Tween = null
var _replay_delay_remaining: float = 0.0

@onready var decor_backdrop: DuelBackdropData = $DecorBackdrop
@onready var duel_canvas: Control = $DuelCanvas
@onready var board_grid: GridContainer = $DuelCanvas/BoardCenter/BoardGrid
@onready var top_wash: ColorRect = $DuelCanvas/TopWash
@onready var top_wash_tint: TextureRect = $DuelCanvas/TopWash/CenterTint
@onready var top_wash_edge: ColorRect = $DuelCanvas/TopWash/BottomEdge
@onready var top_wash_shadow: ColorRect = $DuelCanvas/TopWash/Shadow
@onready var top_bar: HBoxContainer = $DuelCanvas/TopBar
@onready var enemy_seal: PanelContainer = $DuelCanvas/TopBar/EnemySeal
@onready var enemy_seal_label: Label = $DuelCanvas/TopBar/EnemySeal/Value
@onready var opponent_name: Label = $DuelCanvas/TopBar/OpponentName
@onready var exit_button: Button = $DuelCanvas/TopBar/ExitButton
@onready var opponent_hand: HBoxContainer = $DuelCanvas/OpponentHand
@onready var player_hand: HBoxContainer = $DuelCanvas/PlayerHand
@onready var replay_button: Button = $DuelCanvas/ReplayButton
@onready var score_overlay: VBoxContainer = $DuelCanvas/ScoreOverlay
@onready var opponent_score_panel: PanelContainer = $DuelCanvas/ScoreOverlay/OpponentScorePanel
@onready var player_score_panel: PanelContainer = $DuelCanvas/ScoreOverlay/PlayerScorePanel
@onready var opponent_score: Label = $DuelCanvas/ScoreOverlay/OpponentScorePanel/OpponentScore
@onready var player_score: Label = $DuelCanvas/ScoreOverlay/PlayerScorePanel/PlayerScore
@onready var turn_status: Label = $DuelCanvas/TurnStatus
@onready var card_inspector: CardInspectorData = $DuelCanvas/CardInspector
@onready var extra_turn_vfx: ExtraTurnVfxData = $DuelCanvas/ExtraTurnVfx
@onready var attack_vfx: AttackVfxData = $DuelCanvas/AttackVfx
@onready var drag_layer: Control = $DuelCanvas/DragLayer
@onready var placement_audio: AudioStreamPlayer = $PlacementAudio
@onready var capture_audio: AudioStreamPlayer = $CaptureAudio
@onready var removal_audio: AudioStreamPlayer = $RemovalAudio
@onready var movement_audio: AudioStreamPlayer = $MovementAudio


func _ready() -> void:
	board_cards.resize(9)
	board_cards.fill(null)
	_create_board_cells()
	var catalog_errors: Array[String] = Catalog.validate_catalog()
	assert(catalog_errors.is_empty(), "Invalid card catalog: %s" % str(catalog_errors))
	var player_card_ids: Array[StringName] = Decks.get_player_card_ids(deck_profile_path)
	_set_mastery_eligible_card_ids(player_card_ids)
	_shuffle_hand_ids(player_card_ids, player_hand_shuffle_seed)
	var player_cards: Array = _create_card_instances(player_card_ids, DuelRules.PLAYER_OWNER, "main")
	var effective_opponent_ids: Array[StringName] = opponent_card_ids.duplicate()
	if effective_opponent_ids.size() != 5:
		effective_opponent_ids = Decks.get_opponent_card_ids()
	_shuffle_hand_ids(effective_opponent_ids, opponent_hand_shuffle_seed)
	var opponent_cards: Array = _create_card_instances(effective_opponent_ids, DuelRules.OPPONENT_OWNER, "main")
	var player_side_deck: Array = _create_card_instances(
		Decks.get_side_deck_card_ids(player_card_ids),
		DuelRules.PLAYER_OWNER,
		"side"
	)
	var opponent_side_deck: Array = _create_card_instances(
		Decks.get_side_deck_card_ids(effective_opponent_ids),
		DuelRules.OPPONENT_OWNER,
		"side"
	)
	_shuffle_side_decks(player_side_deck, opponent_side_deck)
	var opening_owner: int = _get_valid_starting_owner()
	duel_state = StateData.new(
		board,
		player_cards,
		opponent_cards,
		opening_owner,
		0,
		player_side_deck,
		opponent_side_deck
	)
	duel_state.remembered_glyphs_by_owner = {
		DuelRules.PLAYER_OWNER: remembered_enemy_glyphs.duplicate(),
	}
	_replay_record.begin(duel_state)
	board = duel_state.board
	_create_hands()
	_create_placeholder_audio()
	top_bar.move_child(enemy_seal, 0)
	_style_static_ui()
	exit_button.pressed.connect(_on_exit_pressed)
	replay_button.pressed.connect(_on_replay_pressed)
	replay_button.button_down.connect(_on_replay_button_down)
	replay_button.button_up.connect(_on_replay_button_up)
	card_inspector.inspection_closed.connect(_on_card_inspection_closed)
	resized.connect(_layout_duel)
	get_viewport().size_changed.connect(_layout_duel)
	opponent_name.text = opponent_name_text
	turn_state = TurnState.PLAYER if opening_owner == DuelRules.PLAYER_OWNER else TurnState.OPPONENT
	_sync_hand_playability()
	_update_score()
	_update_turn_status()
	_layout_duel.call_deferred()
	if opening_owner == DuelRules.OPPONENT_OWNER and not testing_mode:
		_begin_opening_opponent_turn.call_deferred()


func _exit_tree() -> void:
	_replay_generation += 1
	_cancel_opponent_search()


func _get_valid_starting_owner() -> int:
	if starting_owner_id == DuelRules.OPPONENT_OWNER:
		return DuelRules.OPPONENT_OWNER
	return DuelRules.PLAYER_OWNER


func _begin_opening_opponent_turn() -> void:
	if opponent_think_delay > 0.0:
		await get_tree().create_timer(opponent_think_delay).timeout
	if (
		is_inside_tree()
		and not testing_mode
		and duel_state != null
		and duel_state.active_player == DuelRules.OPPONENT_OWNER
		and turn_state == TurnState.OPPONENT
	):
		await _perform_opponent_turn()


func debug_set_fast_mode(enabled: bool) -> void:
	_fast_mode = enabled
	if enabled:
		snap_duration = 0.0
		capture_flip_duration = 0.0
		attack_vfx_duration = 0.0
		ability_trigger_pulse_duration = 0.0
		exile_duration = 0.0
		exile_step_delay = 0.0
		card_fade_duration = 0.0
		draw_bloom_duration = 0.0
		draw_rise_duration = 0.0
		draw_post_effect_gap = 0.0
		movement_duration = 0.0
		swap_duration = 0.0
		summon_swap_readable_duration = 0.0
		ki_gain_pulse_duration = 0.0
		extra_card_play_status_duration = 0.0
		opponent_think_delay = 0.0
		opponent_search_budget_seconds = 0.0
		_opponent_search_test_limits = {"max_depth": 1}
		invalid_shake_duration = 0.0


func debug_place_player_card(hand_index: int, cell_index: int) -> bool:
	var action: ActionData = ActionData.make_play(hand_index, cell_index)
	if (
		_inspection_open
		or
		turn_state != TurnState.PLAYER
		or duel_state == null
		or duel_state.active_player != DuelRules.PLAYER_OWNER
		or not Simulator.is_action_legal(duel_state, action)
	):
		return false
	var card: CardView = _get_card_view_for_logical_index(DuelRules.PLAYER_OWNER, hand_index)
	if card == null:
		return false
	await _commit_card(card, cell_index, DuelRules.PLAYER_OWNER)
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


func debug_get_match_outcome() -> StringName:
	return _match_outcome


func debug_is_replay_ready() -> bool:
	return _replay_record.is_ready()


func debug_is_replaying() -> bool:
	return _is_replaying


func debug_get_replay_action_count() -> int:
	return _replay_record.get_actions().size()


func debug_get_replay_initial_decks() -> Dictionary:
	var initial_state: StateData = _replay_record.get_initial_state()
	return initial_state.decks.duplicate(true) if initial_state != null else {}


func debug_is_replay_waiting() -> bool:
	return _is_replaying and not _is_replay_presenting_action and _replay_delay_remaining > 0.0


func debug_get_replay_delay_remaining() -> float:
	return _replay_delay_remaining


func debug_start_replay() -> bool:
	return await _start_replay()


func get_mastery_candidate_ids() -> Array[StringName]:
	return _mastery_candidate_ids.duplicate()


func debug_get_simulation_turn_count() -> int:
	return duel_state.turn_count if duel_state != null else 0


func debug_get_side_deck_card_ids(owner_id: int) -> Array[StringName]:
	var card_ids: Array[StringName] = []
	if duel_state == null:
		return card_ids
	for card_value: Variant in duel_state.decks.get(owner_id, []):
		card_ids.append(StringName((card_value as Dictionary).get("card_id", &"")))
	return card_ids


func debug_get_all_instance_ids() -> Array[StringName]:
	var instance_ids: Array[StringName] = []
	if duel_state == null:
		return instance_ids
	for owner_id: int in [DuelRules.PLAYER_OWNER, DuelRules.OPPONENT_OWNER]:
		for card_value: Variant in duel_state.get_hand(owner_id):
			instance_ids.append(StringName((card_value as Dictionary).get("instance_id", &"")))
		for card_value: Variant in duel_state.decks.get(owner_id, []):
			instance_ids.append(StringName((card_value as Dictionary).get("instance_id", &"")))
	return instance_ids


func debug_get_presentation_trace() -> Array[StringName]:
	return _presentation_trace.duplicate()


func debug_get_attack_vfx_trace() -> Array[Dictionary]:
	return _attack_vfx_trace.duplicate(true)


func debug_get_attack_vfx_placement(
	source_cell: int,
	target_cell: int
) -> Dictionary:
	return _get_attack_vfx_placement(source_cell, target_cell)


func debug_get_ability_pulse_trace() -> Array[StringName]:
	return _ability_pulse_trace.duplicate()


func debug_get_ki_presentation_trace() -> Array[int]:
	return _ki_presentation_trace.duplicate()


func debug_has_targeting_trace() -> bool:
	return _targeting_trace != null and is_instance_valid(_targeting_trace)


func debug_get_targeting_trace_end() -> Vector2:
	return _targeting_trace_end_global


func debug_get_movement_presentation_trace() -> Array[Dictionary]:
	return _movement_presentation_trace.duplicate(true)


func debug_get_movement_sound_count() -> int:
	return _movement_sound_count


func debug_get_active_owner() -> int:
	return duel_state.active_player if duel_state != null else 0


func debug_get_search_budget_seconds() -> float:
	return opponent_search_budget_seconds


func debug_get_last_search_report() -> Dictionary:
	return _last_search_report.duplicate(true)


func debug_is_search_running() -> bool:
	return _opponent_search_session != null and _opponent_search_session.is_running()


func debug_is_inspection_open() -> bool:
	return _inspection_open and card_inspector.is_open()


func debug_open_inspection(card_data: Dictionary) -> bool:
	_on_card_inspection_requested(card_data)
	return debug_is_inspection_open()


func debug_close_inspection() -> void:
	card_inspector.close()


func debug_set_search_limits(budget_seconds: float, test_limits: Dictionary = {}) -> void:
	opponent_search_budget_seconds = maxf(budget_seconds, 0.0)
	_opponent_search_test_limits = test_limits.duplicate(true)


func debug_get_hand_instance_ids(owner_id: int) -> Array[StringName]:
	var instance_ids: Array[StringName] = []
	if duel_state == null:
		return instance_ids
	for card_value: Variant in duel_state.get_hand(owner_id):
		instance_ids.append(StringName((card_value as Dictionary).get("instance_id", &"")))
	return instance_ids


func debug_get_hand_view_instance_ids(owner_id: int) -> Array[StringName]:
	var instance_ids: Array[StringName] = []
	for card: CardView in _get_cards_in_hand(_get_hand_for_owner(owner_id)):
		instance_ids.append(_get_card_instance_id(card))
	return instance_ids


func debug_get_board_card_instance_id(cell_index: int) -> StringName:
	if not debug_has_board_card_view(cell_index):
		return &""
	return _get_card_instance_id(board_cards[cell_index] as CardView)


func debug_get_total_card_count() -> int:
	if duel_state == null:
		return 0
	var total: int = debug_get_board_occupancy()
	for owner_id: int in [DuelRules.PLAYER_OWNER, DuelRules.OPPONENT_OWNER]:
		total += duel_state.get_hand(owner_id).size()
		total += (duel_state.decks.get(owner_id, []) as Array).size()
		total += (duel_state.discard_piles.get(owner_id, []) as Array).size()
		total += (duel_state.removed_cards.get(owner_id, []) as Array).size()
	return total


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
	if _inspection_open or duel_state == null or duel_state.active_player != owner_id:
		return false
	var card: CardView = _get_card_view_for_logical_index(owner_id, hand_index)
	if card == null:
		return false
	var action: ActionData = ActionData.make_play(hand_index, cell_index, _get_card_instance_id(card))
	if not Simulator.is_action_legal(duel_state, action):
		return false
	await _commit_action(card, action, owner_id, continue_automatically)
	return true


func debug_commit_activate(
	owner_id: int,
	source_cell: int,
	target_cell: int,
	continue_automatically: bool = false,
	activation_index: int = 0
) -> bool:
	if _inspection_open or duel_state == null or duel_state.active_player != owner_id or not debug_has_board_card_view(source_cell):
		return false
	var card := board_cards[source_cell] as CardView
	var activation: Dictionary = Abilities.get_activation(card.card_data, activation_index)
	if activation.is_empty():
		return false
	var action: ActionData = ActionData.make_activate(
		source_cell,
		_get_card_instance_id(card),
		ActionData.TARGET_BOARD_CELL,
		target_cell,
		activation_index
	)
	if not Simulator.is_action_legal(duel_state, action):
		return false
	await _commit_action(card, action, owner_id, continue_automatically)
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
	_create_hand_slots(opponent_hand)
	_create_hand_slots(player_hand)
	for card_index: int in range(duel_state.get_hand(DuelRules.OPPONENT_OWNER).size()):
		var card_data: Dictionary = duel_state.get_hand(DuelRules.OPPONENT_OWNER)[card_index]
		var opponent_card: CardView = _spawn_card_in_slot(opponent_hand.get_child(card_index) as PanelContainer, card_data, DuelRules.OPPONENT_OWNER, false)
		opponent_card.set_face_down(_should_conceal_hand_card(card_data, DuelRules.OPPONENT_OWNER))
	for card_index: int in range(duel_state.get_hand(DuelRules.PLAYER_OWNER).size()):
		var card_data: Dictionary = duel_state.get_hand(DuelRules.PLAYER_OWNER)[card_index]
		_spawn_card_in_slot(player_hand.get_child(card_index) as PanelContainer, card_data, DuelRules.PLAYER_OWNER, false)


func _create_card_instances(card_ids: Array[StringName], owner_id: int, zone: String) -> Array:
	var instances: Array = []
	for card_index: int in range(card_ids.size()):
		var instance_id := StringName("%s_%d_%d" % [zone, owner_id, card_index])
		instances.append(Catalog.create_instance(card_ids[card_index], owner_id, instance_id))
	return instances


func _shuffle_side_decks(player_deck: Array, opponent_deck: Array) -> void:
	var random := RandomNumberGenerator.new()
	if side_deck_shuffle_seed == 0:
		random.randomize()
	else:
		random.seed = side_deck_shuffle_seed
	_shuffle_with_rng(player_deck, random)
	_shuffle_with_rng(opponent_deck, random)


func _shuffle_hand_ids(card_ids: Array[StringName], shuffle_seed: int) -> void:
	if shuffle_seed < 0:
		return
	var random := RandomNumberGenerator.new()
	if shuffle_seed == 0:
		random.randomize()
	else:
		random.seed = shuffle_seed
	_shuffle_with_rng(card_ids, random)


func _shuffle_with_rng(cards: Array, random: RandomNumberGenerator) -> void:
	for card_index: int in range(cards.size() - 1, 0, -1):
		var swap_index: int = random.randi_range(0, card_index)
		var temporary: Variant = cards[card_index]
		cards[card_index] = cards[swap_index]
		cards[swap_index] = temporary


func _create_hand_slots(container: HBoxContainer) -> void:
	for slot_index: int in range(5):
		container.add_child(_create_hand_slot(slot_index))


func _create_hand_slot(slot_index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = "Slot%d" % slot_index
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slot_style := StyleBoxFlat.new()
	slot_style.bg_color = Color(1.0, 1.0, 1.0, 0.06)
	slot_style.border_color = Color(1.0, 1.0, 1.0, 0.10)
	slot_style.set_border_width_all(1)
	slot_style.set_corner_radius_all(5)
	slot.add_theme_stylebox_override("panel", slot_style)
	return slot


func _spawn_card_in_slot(slot: PanelContainer, card_data: Dictionary, owner_id: int, is_playable: bool) -> CardView:
	var card := CARD_SCENE.instantiate() as CardView
	slot.custom_minimum_size = card.custom_minimum_size
	slot.add_child(card)
	card.touch_drag_offset = drag_touch_offset
	card.configure(card_data, owner_id, is_playable)
	card.drag_started.connect(_on_card_drag_started)
	card.drag_moved.connect(_on_card_drag_moved)
	card.drag_ended.connect(_on_card_drag_ended)
	card.inspection_requested.connect(_on_card_inspection_requested)
	return card


func _on_card_drag_started(card: CardView, pointer_position: Vector2) -> void:
	if not _can_manually_drag(card):
		card.finish_drag_state()
		return
	_drag_source_index = _get_board_cell_for_card(card)
	_drag_source_zone = ActionData.SOURCE_BOARD if _drag_source_index >= 0 else ActionData.SOURCE_HAND
	_drag_valid_targets = _get_drag_targets(card)
	if _drag_source_zone == ActionData.SOURCE_BOARD:
		card.set_drag_follows_pointer(false)
		_begin_targeting_trace(card, pointer_position)
	else:
		card.set_drag_follows_pointer(true)
		card.reparent(drag_layer, true)
	_highlight_legal_cells()


func _on_card_drag_moved(_card: CardView, pointer_position: Vector2) -> void:
	_update_targeting_trace(pointer_position)
	var target_cell: int = _get_cell_at_position(pointer_position)
	if target_cell == _hovered_cell:
		return
	_hovered_cell = target_cell
	_highlight_legal_cells()
	if target_cell in _drag_valid_targets:
		_set_cell_style(target_cell, "hover")


func _on_card_drag_ended(card: CardView, pointer_position: Vector2) -> void:
	var target_cell: int = _get_cell_at_position(pointer_position)
	_clear_cell_highlights()
	var action: ActionData = _make_drag_action(card, target_cell)
	if _can_manually_drag(card) and action != null and Simulator.is_action_legal(duel_state, action):
		card.finish_drag_state()
		_remove_targeting_trace()
		await _commit_action(card, action, card.owner_id)
		_clear_drag_context()
		return
	_return_card_home(card)
	card.play_invalid_shake(invalid_shake_duration)
	_clear_drag_context()


func _on_card_inspection_requested(card_data: Dictionary) -> void:
	if (
		_inspection_open
		or turn_state == TurnState.RESOLVING
		or (_is_replaying and _is_replay_presenting_action)
	):
		return
	_inspection_open = true
	_board_visible_before_inspection = board_grid.visible
	_scores_visible_before_inspection = score_overlay.visible
	_status_before_inspection = turn_status.text
	board_grid.visible = false
	score_overlay.visible = false
	_sync_hand_playability()
	turn_status.text = "查看卡牌详情 · 轻触返回"
	card_inspector.present(card_data, _get_board_rect())


func _on_card_inspection_closed() -> void:
	if not _inspection_open:
		return
	_inspection_open = false
	board_grid.visible = _board_visible_before_inspection
	score_overlay.visible = _scores_visible_before_inspection
	turn_status.text = _status_before_inspection
	_sync_hand_playability()
	_update_turn_status()


func _return_card_home(card: CardView) -> void:
	var home_parent: Node = card.get_home_parent()
	if home_parent == null or not is_instance_valid(home_parent):
		if _drag_source_zone == ActionData.SOURCE_BOARD and _drag_source_index >= 0:
			home_parent = board_cells[_drag_source_index]
		else:
			home_parent = _get_hand_for_owner(card.owner_id)
	card.reparent(home_parent, false)
	var target_index: int = clampi(card.get_home_index(), 0, home_parent.get_child_count() - 1)
	home_parent.move_child(card, target_index)
	card.finish_drag_state()
	if _drag_source_zone == ActionData.SOURCE_BOARD:
		card.z_index = 1


func _commit_card(
	card: CardView,
	cell_index: int,
	owner_id: int,
	continue_automatically: bool = true
) -> void:
	if _inspection_open or duel_state == null or duel_state.active_player != owner_id:
		return
	var instance_id: StringName = _get_card_instance_id(card)
	var hand_index: int = _get_logical_hand_index(owner_id, instance_id)
	var action: ActionData = ActionData.make_play(hand_index, cell_index, instance_id)
	await _commit_action(card, action, owner_id, continue_automatically)


func _commit_action(
	card: CardView,
	action: ActionData,
	owner_id: int,
	continue_automatically: bool = true
) -> void:
	if duel_state == null or duel_state.active_player != owner_id:
		return
	if not Simulator.is_action_legal(duel_state, action):
		return
	var presentation_started_msec: int = Time.get_ticks_msec()
	var transition: Dictionary = Simulator.apply_action(duel_state, action)
	if not bool(transition.get("valid", false)):
		return
	if not _is_replaying:
		_replay_record.record_action(action)
	if not _is_replaying and owner_id == DuelRules.PLAYER_OWNER and action.action_type == ActionData.TYPE_PLAY:
		_record_mastery_candidate(StringName(card.card_data.get("card_id", &"")))
	if not _is_replaying and owner_id == DuelRules.OPPONENT_OWNER and action.action_type == ActionData.TYPE_PLAY:
		opponent_card_played.emit(String(card.card_data.get("glyph", "")))
	duel_state = transition["state"] as StateData
	board = duel_state.board
	var events: Array = transition.get("events", [])
	turn_state = TurnState.RESOLVING
	_sync_hand_playability()
	_update_turn_status()

	card.set_face_down(false)
	card.set_playable(false)
	card.z_index = 1
	card.scale = Vector2(0.9, 0.9) if action.action_type == ActionData.TYPE_PLAY else Vector2.ONE
	card.rotation = 0.0
	if action.action_type == ActionData.TYPE_PLAY:
		card.reparent(board_cells[action.target_index], false)
		board_cards[action.target_index] = card

	if action.action_type == ActionData.TYPE_PLAY:
		_play_placement_feedback()
	if action.action_type == ActionData.TYPE_PLAY and snap_duration > 0.0:
		var snap_tween: Tween = create_tween()
		snap_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		snap_tween.tween_property(card, "scale", Vector2.ONE, snap_duration)
		await snap_tween.finished
	else:
		card.scale = Vector2.ONE

	var resolved_targets: int = await _present_transition_events(
		events,
		owner_id,
		action.action_type == ActionData.TYPE_PLAY,
		_get_card_instance_id(card),
		presentation_started_msec
	)
	_reconcile_board_card_views()
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


func _movement_group_contains_instance(
	events: Array,
	event_index: int,
	instance_id: StringName
) -> bool:
	if instance_id == &"" or event_index < 0 or event_index >= events.size():
		return false
	var first: Dictionary = events[event_index] as Dictionary
	if StringName(first.get("instance_id", &"")) == instance_id:
		return true
	if event_index + 1 >= events.size():
		return false
	var second: Dictionary = events[event_index + 1] as Dictionary
	return (
		StringName(second.get("type", &"")) == &"card_moved"
		and StringName(second.get("instance_id", &"")) == instance_id
		and _movement_events_are_reciprocal(first, second)
	)


func _wait_for_summon_swap_readability(started_msec: int) -> void:
	if summon_swap_readable_duration <= 0.0 or started_msec <= 0:
		return
	var elapsed: float = float(Time.get_ticks_msec() - started_msec) / 1000.0
	var remaining: float = summon_swap_readable_duration - elapsed
	if remaining > 0.0:
		await get_tree().create_timer(remaining).timeout


func _present_movement_event_group(
	events: Array,
	event_index: int
) -> int:
	var first: Dictionary = events[event_index] as Dictionary
	_presentation_trace.append(&"card_moved")
	if event_index + 1 < events.size():
		var second: Dictionary = events[event_index + 1] as Dictionary
		if _movement_events_are_reciprocal(first, second):
			_presentation_trace.append(&"card_moved")
			await _animate_reciprocal_swap(first, second)
			return 2
	await _animate_single_movement(first)
	return 1


func _movement_events_are_reciprocal(first: Dictionary, second: Dictionary) -> bool:
	return (
		StringName(first.get("type", &"")) == &"card_moved"
		and StringName(second.get("type", &"")) == &"card_moved"
		and int(first.get("source_cell", -1)) == int(second.get("target_cell", -2))
		and int(first.get("target_cell", -1)) == int(second.get("source_cell", -2))
		and StringName(first.get("instance_id", &"")) != &""
		and StringName(second.get("instance_id", &"")) != &""
	)


func _animate_single_movement(event: Dictionary) -> void:
	var instance_id := StringName(event.get("instance_id", &""))
	var source_cell: int = int(event.get("source_cell", -1))
	var target_cell: int = int(event.get("target_cell", -1))
	var card: CardView = _get_board_card_view_by_instance(instance_id)
	if not _valid_movement_cells(source_cell, target_cell) or card == null:
		_apply_movement_mapping_immediate(event)
		return
	var start_global: Vector2 = card.global_position
	var end_global: Vector2 = board_cells[target_cell].get_global_rect().position
	card.reparent(drag_layer, true)
	card.z_index = 90
	_play_movement_feedback()
	_movement_presentation_trace.append({
		"kind": &"move",
		"instance_id": instance_id,
		"source_cell": source_cell,
		"target_cell": target_cell,
		"duration": movement_duration,
	})
	if movement_duration > 0.0:
		var tween: Tween = create_tween()
		tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(card, "global_position", end_global, movement_duration)
		await tween.finished
	else:
		card.global_position = end_global
	_finalize_presented_card_move(card, source_cell, target_cell)


func _animate_reciprocal_swap(
	first: Dictionary,
	second: Dictionary
) -> void:
	var first_id := StringName(first.get("instance_id", &""))
	var second_id := StringName(second.get("instance_id", &""))
	var first_source: int = int(first.get("source_cell", -1))
	var first_target: int = int(first.get("target_cell", -1))
	var second_source: int = int(second.get("source_cell", -1))
	var second_target: int = int(second.get("target_cell", -1))
	var first_card: CardView = _get_board_card_view_by_instance(first_id)
	var second_card: CardView = _get_board_card_view_by_instance(second_id)
	if (
		not _valid_movement_cells(first_source, first_target)
		or not _valid_movement_cells(second_source, second_target)
		or first_card == null
		or second_card == null
	):
		_apply_movement_mapping_immediate(first)
		_apply_movement_mapping_immediate(second)
		return

	var first_start: Vector2 = first_card.global_position
	var second_start: Vector2 = second_card.global_position
	var first_end: Vector2 = board_cells[first_target].get_global_rect().position
	var second_end: Vector2 = board_cells[second_target].get_global_rect().position
	var direction: Vector2 = first_end - first_start
	var perpendicular: Vector2 = Vector2(-direction.y, direction.x).normalized()
	var cell_size: Vector2 = board_cells[first_source].get_global_rect().size
	var arc_amount: float = minf(cell_size.x, cell_size.y) * swap_arc_ratio
	var first_control: Vector2 = (first_start + first_end) * 0.5 + perpendicular * arc_amount
	var second_control: Vector2 = (second_start + second_end) * 0.5 - perpendicular * arc_amount

	first_card.reparent(drag_layer, true)
	second_card.reparent(drag_layer, true)
	first_card.z_index = 91
	second_card.z_index = 90
	_play_movement_feedback()
	_movement_presentation_trace.append({
		"kind": &"swap",
		"first_instance_id": first_id,
		"second_instance_id": second_id,
		"first_source_cell": first_source,
		"first_target_cell": first_target,
		"duration": swap_duration,
		"arc_amount": arc_amount,
	})
	if swap_duration > 0.0:
		var tween: Tween = create_tween()
		tween.set_parallel(true)
		tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_method(
			_set_card_bezier_position.bind(
				first_card,
				first_start,
				first_control,
				first_end
			),
			0.0,
			1.0,
			swap_duration
		)
		tween.tween_method(
			_set_card_bezier_position.bind(
				second_card,
				second_start,
				second_control,
				second_end
			),
			0.0,
			1.0,
			swap_duration
		)
		await tween.finished
	else:
		first_card.global_position = first_end
		second_card.global_position = second_end

	board_cards[first_source] = null
	board_cards[second_source] = null
	_finalize_presented_card_move(
		first_card,
		first_source,
		first_target
	)
	_finalize_presented_card_move(
		second_card,
		second_source,
		second_target
	)


func _set_card_bezier_position(
	progress: float,
	card: CardView,
	start: Vector2,
	control: Vector2,
	end: Vector2
) -> void:
	if card == null or not is_instance_valid(card):
		return
	var inverse: float = 1.0 - progress
	card.global_position = (
		inverse * inverse * start
		+ 2.0 * inverse * progress * control
		+ progress * progress * end
	)


func _valid_movement_cells(source_cell: int, target_cell: int) -> bool:
	return (
		source_cell >= 0
		and source_cell < board_cells.size()
		and target_cell >= 0
		and target_cell < board_cells.size()
	)


func _apply_movement_mapping_immediate(event: Dictionary) -> void:
	var instance_id := StringName(event.get("instance_id", &""))
	var source_cell: int = int(event.get("source_cell", -1))
	var target_cell: int = int(event.get("target_cell", -1))
	var card: CardView = _get_board_card_view_by_instance(instance_id)
	if card == null or not _valid_movement_cells(source_cell, target_cell):
		return
	_finalize_presented_card_move(card, source_cell, target_cell)


func _finalize_presented_card_move(
	card: CardView,
	source_cell: int,
	target_cell: int
) -> void:
	if card == null or not is_instance_valid(card) or not _valid_movement_cells(source_cell, target_cell):
		return
	if board_cards[source_cell] == card:
		board_cards[source_cell] = null
	card.reparent(board_cells[target_cell], false)
	card.scale = Vector2.ONE
	card.rotation = 0.0
	card.z_index = 1
	board_cards[target_cell] = card


func _reconcile_board_card_views() -> void:
	if duel_state == null:
		return
	var views_by_instance: Dictionary = {}
	for card_value: Variant in board_cards:
		var mapped_card := card_value as CardView
		if mapped_card != null and is_instance_valid(mapped_card):
			views_by_instance[_get_card_instance_id(mapped_card)] = mapped_card
	for cell: PanelContainer in board_cells:
		for child: Node in cell.get_children():
			var cell_card := child as CardView
			if cell_card != null and is_instance_valid(cell_card):
				views_by_instance[_get_card_instance_id(cell_card)] = cell_card
	for child: Node in drag_layer.get_children():
		var floating_card := child as CardView
		if floating_card != null and is_instance_valid(floating_card):
			views_by_instance[_get_card_instance_id(floating_card)] = floating_card
	board_cards.fill(null)
	for cell_index: int in range(mini(board_cards.size(), duel_state.board.size())):
		var logical_slot_value: Variant = duel_state.board[cell_index]
		if logical_slot_value == null:
			continue
		var logical_slot: Dictionary = logical_slot_value
		var logical_card: Dictionary = logical_slot.get("card", {})
		var instance_id := StringName(logical_card.get("instance_id", &""))
		var card_view := views_by_instance.get(instance_id, null) as CardView
		if card_view == null or not is_instance_valid(card_view):
			card_view = _spawn_card_in_slot(
				board_cells[cell_index],
				logical_card,
				int(logical_slot.get("owner", DuelRules.PLAYER_OWNER)),
				false
			)
		else:
			card_view.reparent(board_cells[cell_index], false)
		card_view.set_face_down(false)
		card_view.set_playable(false)
		card_view.scale = Vector2.ONE
		card_view.rotation = 0.0
		card_view.z_index = 1
		card_view.sync_runtime_data(
			logical_card,
			int(logical_slot.get("owner", card_view.owner_id))
		)
		board_cards[cell_index] = card_view


func _present_transition_events(
	events: Array,
	fallback_owner: int,
	is_play_action: bool = false,
	played_instance_id: StringName = &"",
	presentation_started_msec: int = 0
) -> int:
	var resolved_targets: int = 0
	var last_pulsed_instance_id: StringName = &""
	var drew_card: bool = false
	var waited_after_draw: bool = false
	var event_index: int = 0
	while event_index < events.size():
		var event: Dictionary = events[event_index] as Dictionary
		var event_type := StringName(event.get("type", &""))
		var target_cell: int = int(event.get("target_cell", -1))
		var consumed_events: int = 1
		if event_type == &"ability_activated":
			_presentation_trace.append(event_type)
		elif event_type == &"card_moved":
			if (
				is_play_action
				and _movement_group_contains_instance(
					events,
					event_index,
					played_instance_id
				)
			):
				await _wait_for_summon_swap_readability(presentation_started_msec)
			consumed_events = await _present_movement_event_group(
				events,
				event_index
			)
		elif event_type == &"attack_started":
			if drew_card and not waited_after_draw:
				await _wait_after_draw_before_board_effect()
				waited_after_draw = true
			_presentation_trace.append(event_type)
			var source_cell: int = int(event.get("source_cell", -1))
			var source_instance_id := StringName(event.get("source_instance_id", &""))
			var target_instance_id := StringName(event.get("target_instance_id", &""))
			var source_card: CardView = null
			if (
				source_cell >= 0
				and source_cell < board_cards.size()
				and board_cards[source_cell] != null
				and is_instance_valid(board_cards[source_cell])
			):
				source_card = board_cards[source_cell] as CardView
			var placement: Dictionary = _get_attack_vfx_placement(
				source_cell,
				target_cell
			)
			if (
				source_card != null
				and _get_card_instance_id(source_card) == source_instance_id
				and not placement.is_empty()
			):
				_attack_vfx_trace.append({
					"source_instance_id": source_instance_id,
					"target_instance_id": target_instance_id,
					"neighbor_cell": int(placement["neighbor_cell"]),
					"center": placement["center"],
					"rotation": float(placement["rotation"]),
				})
				await attack_vfx.play_attack(
					placement["center"],
					float(placement["rotation"]),
					attack_vfx_duration
				)
		elif event_type == &"ability_triggered":
			_presentation_trace.append(event_type)
			var source_instance_id := StringName(event.get("source_instance_id", &""))
			var source_card: CardView = _get_board_card_view_by_instance(source_instance_id)
			if source_card != null and source_instance_id != last_pulsed_instance_id:
				_ability_pulse_trace.append(source_instance_id)
				await source_card.play_effect_pulse(ability_trigger_pulse_duration)
				last_pulsed_instance_id = source_instance_id
		elif event_type == &"ki_changed":
			await _present_ki_changed_event(event)
		elif event_type == &"powers_changed":
			_present_powers_changed_event(event)
		elif event_type == &"extra_card_play_granted":
			await _present_extra_card_play_event(event)
		elif event_type in [&"card_drawn", &"card_added_to_hand"]:
			await _present_hand_addition_event(event, event_type)
			drew_card = true
		elif event_type == &"card_summoned":
			await _present_generated_summon_event(event)
		elif event_type == &"card_departed_for_resummon":
			await _present_card_departed_for_resummon_event(event)
		elif event_type == &"card_returned_to_hand":
			await _present_card_returned_to_hand_event(event)
		elif event_type == &"card_revealed":
			_present_card_revealed_event(event)
		elif event_type in [&"ability_gained", &"ability_lost"]:
			var changed_instance_id := StringName(event.get("instance_id", &""))
			var changed_view: CardView = _get_card_view_by_instance(changed_instance_id)
			var changed_data: Dictionary = _get_logical_card_by_instance(changed_instance_id)
			if changed_view != null and not changed_data.is_empty():
				changed_view.sync_runtime_data(changed_data, changed_view.owner_id)
				if event_type == &"ability_lost":
					await changed_view.play_ability_lost(capture_flip_duration * 0.5)
		elif event_type == &"card_flipped":
			if drew_card and not waited_after_draw:
				await _wait_after_draw_before_board_effect()
				waited_after_draw = true
			_presentation_trace.append(&"card_flipped")
			var flipped_card := board_cards[target_cell] as CardView
			if flipped_card != null:
				_play_capture_feedback()
				var new_owner: int = int(event.get("owner_id", fallback_owner))
				await flipped_card.play_capture_flip(
					new_owner,
					maxf(capture_flip_duration, 0.02)
				)
			resolved_targets += 1
		elif event_type == &"card_exiled":
			if drew_card and not waited_after_draw:
				await _wait_after_draw_before_board_effect()
				waited_after_draw = true
			_presentation_trace.append(&"card_exiled")
			var self_removal: bool = bool(event.get("self_removal", false))
			if not self_removal and exile_step_delay > 0.0:
				await get_tree().create_timer(exile_step_delay).timeout
			var exiled_card := board_cards[target_cell] as CardView
			board_cards[target_cell] = null
			if exiled_card != null:
				if self_removal:
					_presentation_trace.append(&"card_self_faded")
					await exiled_card.play_fade_out(card_fade_duration)
				else:
					_play_removal_feedback()
					await exiled_card.play_exile(exile_duration, exile_ink_color)
				exiled_card.queue_free()
			resolved_targets += 1
		event_index += consumed_events
	return resolved_targets


func _set_mastery_eligible_card_ids(card_ids: Array[StringName]) -> void:
	_mastery_eligible_card_ids.clear()
	_mastery_candidate_ids.clear()
	_mastery_candidate_set.clear()
	for card_id: StringName in card_ids:
		_mastery_eligible_card_ids[card_id] = true


func _record_mastery_candidate(card_id: StringName) -> void:
	if (
		card_id == &""
		or not _mastery_eligible_card_ids.has(card_id)
		or _mastery_candidate_set.has(card_id)
	):
		return
	_mastery_candidate_ids.append(card_id)
	_mastery_candidate_set[card_id] = true


func _present_ki_changed_event(event: Dictionary) -> void:
	_presentation_trace.append(&"ki_changed")
	var instance_id := StringName(event.get("instance_id", &""))
	var card: CardView = _get_card_view_by_instance(instance_id)
	if card == null:
		return
	var previous_ki: int = int(event.get("previous_ki", card.card_data.get("ki", 0)))
	var resulting_ki: int = int(event.get("ki", previous_ki))
	_ki_presentation_trace.append(resulting_ki)
	card.set_runtime_ki(resulting_ki)
	if resulting_ki > previous_ki:
		await card.play_ki_gain_pulse(ki_gain_pulse_duration)


func _present_powers_changed_event(event: Dictionary) -> void:
	_presentation_trace.append(&"powers_changed")
	var instance_id := StringName(event.get("instance_id", &""))
	var card: CardView = _get_card_view_by_instance(instance_id)
	if card == null:
		return
	var powers_value: Variant = event.get("powers", [])
	if powers_value is Array:
		card.set_runtime_powers(powers_value as Array)


func _present_extra_card_play_event(_event: Dictionary) -> void:
	_presentation_trace.append(&"extra_card_play_granted")
	turn_status.text = "额外出牌"
	turn_status.modulate = extra_card_play_effect_color
	await extra_turn_vfx.play_pulse(
		board_grid.get_global_rect(),
		extra_card_play_status_duration,
		extra_card_play_effect_color
	)
	turn_status.modulate = Color.WHITE


func _present_hand_addition_event(
	event: Dictionary,
	event_type: StringName
) -> void:
	var owner_id: int = int(event.get("owner_id", 0))
	var instance_id := StringName(event.get("instance_id", &""))
	var card_data: Dictionary = _get_logical_hand_card_by_instance(owner_id, instance_id)
	var target_slot: PanelContainer = _get_first_empty_hand_slot(_get_hand_for_owner(owner_id))
	if card_data.is_empty() or target_slot == null:
		return
	var card: CardView = _spawn_card_in_slot(target_slot, card_data, owner_id, false)
	card.set_face_down(_should_conceal_hand_card(card_data, owner_id))
	_presentation_trace.append(event_type)
	await card.play_draw_summon(draw_bloom_duration, draw_rise_duration, draw_ink_color)


func _present_generated_summon_event(event: Dictionary) -> void:
	var target_cell: int = int(event.get("target_cell", -1))
	if target_cell < 0 or target_cell >= board_cells.size():
		return
	var card_data: Dictionary = event.get("card", {})
	var owner_id: int = int(event.get("owner_id", 0))
	if card_data.is_empty() or board_cards[target_cell] != null:
		return
	var from_hand_instance_id := StringName(event.get("from_hand_instance_id", &""))
	var card: CardView = null
	if from_hand_instance_id != &"":
		card = _get_card_view_by_instance(from_hand_instance_id)
	if card != null:
		card.reparent(board_cells[target_cell], false)
		card.sync_runtime_data(card_data, owner_id)
	else:
		card = _spawn_card_in_slot(
			board_cells[target_cell],
			card_data,
			owner_id,
			false
		)
	card.set_face_down(false)
	card.z_index = 1
	board_cards[target_cell] = card
	_presentation_trace.append(&"card_summoned")
	await card.play_draw_summon(draw_bloom_duration, draw_rise_duration, draw_ink_color)


func _present_card_departed_for_resummon_event(event: Dictionary) -> void:
	var target_cell: int = int(event.get("target_cell", -1))
	var old_instance_id := StringName(event.get("old_instance_id", &""))
	if target_cell < 0 or target_cell >= board_cards.size():
		return
	var old_view := board_cards[target_cell] as CardView
	if old_view == null or _get_card_instance_id(old_view) != old_instance_id:
		return
	board_cards[target_cell] = null
	_presentation_trace.append(&"card_resummon_faded")
	await old_view.play_fade_out(card_fade_duration)
	old_view.queue_free()


func _present_card_returned_to_hand_event(event: Dictionary) -> void:
	var target_cell: int = int(event.get("target_cell", -1))
	var old_instance_id := StringName(event.get("old_instance_id", &""))
	var returning_view: CardView = null
	if (
		target_cell >= 0
		and target_cell < board_cards.size()
		and board_cards[target_cell] != null
		and _get_card_instance_id(board_cards[target_cell] as CardView) == old_instance_id
	):
		returning_view = board_cards[target_cell] as CardView
		board_cards[target_cell] = null
	if returning_view != null:
		_presentation_trace.append(&"card_return_faded")
		await returning_view.play_fade_out(card_fade_duration)
		returning_view.queue_free()
	_presentation_trace.append(&"card_returned_to_hand")
	await _present_hand_addition_event(event, &"card_added_to_hand")


func _present_card_revealed_event(event: Dictionary) -> void:
	var instance_id := StringName(event.get("instance_id", &""))
	var card: CardView = _get_card_view_by_instance(instance_id)
	var card_data: Dictionary = _get_logical_card_by_instance(instance_id)
	if card == null or card_data.is_empty():
		return
	card.sync_runtime_data(card_data, int(event.get("owner_id", card.owner_id)))
	card.set_face_down(false)
	_presentation_trace.append(&"card_revealed")


func _should_conceal_hand_card(card_data: Dictionary, owner_id: int) -> bool:
	return (
		owner_id == DuelRules.OPPONENT_OWNER
		and not testing_mode
		and not Revelation.is_revealed_to(card_data, DuelRules.PLAYER_OWNER)
	)


func _get_logical_card_by_instance(instance_id: StringName) -> Dictionary:
	if duel_state == null:
		return {}
	for owner_id: int in [DuelRules.PLAYER_OWNER, DuelRules.OPPONENT_OWNER]:
		for card_value: Variant in duel_state.get_hand(owner_id):
			var card: Dictionary = card_value
			if StringName(card.get("instance_id", &"")) == instance_id:
				return card
	for slot_value: Variant in duel_state.board:
		if slot_value == null:
			continue
		var card: Dictionary = (slot_value as Dictionary).get("card", {})
		if StringName(card.get("instance_id", &"")) == instance_id:
			return card
	return {}


func _wait_after_draw_before_board_effect() -> void:
	_presentation_trace.append(&"post_draw_gap")
	if draw_post_effect_gap > 0.0:
		await get_tree().create_timer(draw_post_effect_gap).timeout


func _perform_opponent_turn() -> void:
	if duel_state == null or testing_mode or turn_state != TurnState.OPPONENT:
		return
	var starting_version: int = duel_state.state_version
	var greedy_fallback: ActionData = Simulator.choose_greedy_action(duel_state)
	if greedy_fallback.action_type == &"":
		_finish_match()
		return
	var session: SearchSession = SearchSession.new()
	_opponent_search_session = session
	_opponent_search_started_usec = Time.get_ticks_usec()
	var started: bool = session.start(
		duel_state,
		DuelRules.OPPONENT_OWNER,
		opponent_search_budget_seconds,
		greedy_fallback,
		_opponent_search_test_limits
	)
	if started:
		while is_inside_tree() and not session.is_complete():
			var progress: Dictionary = session.get_progress()
			var elapsed: float = float(Time.get_ticks_usec() - _opponent_search_started_usec) / 1_000_000.0
			if not _inspection_open:
				turn_status.text = "对手正在思考… %.1fs · 深度 %d" % [
					elapsed,
					int(progress.get("completed_depth", 0)),
				]
			await get_tree().process_frame
	while is_inside_tree() and _inspection_open:
		await get_tree().process_frame
	if not is_inside_tree():
		return
	var search_result: Dictionary = session.finish_and_get_result()
	if _opponent_search_session == session:
		_opponent_search_session = null
	if (
		duel_state == null
		or turn_state != TurnState.OPPONENT
		or duel_state.state_version != starting_version
		or Simulator.is_terminal(duel_state)
	):
		search_result["completion_reason"] = &"stale_result"
		_last_search_report = search_result.duplicate(true)
		_print_search_report(search_result)
		return
	var choice: ActionData = search_result.get("action", null) as ActionData
	if choice == null or not Simulator.is_action_legal(duel_state, choice):
		choice = greedy_fallback.duplicate_action()
		search_result["used_fallback"] = true
	if not Simulator.is_action_legal(duel_state, choice):
		search_result["completion_reason"] = &"no_legal_action"
		search_result["action"] = choice.duplicate_action()
		_last_search_report = search_result.duplicate(true)
		_print_search_report(search_result)
		_finish_match()
		return
	search_result["action"] = choice.duplicate_action()
	_last_search_report = search_result.duplicate(true)
	_print_search_report(search_result)
	var opponent_card: CardView = null
	if choice.action_type == ActionData.TYPE_PLAY:
		opponent_card = _get_card_view_for_logical_index(DuelRules.OPPONENT_OWNER, choice.source_index)
	elif choice.action_type == ActionData.TYPE_ACTIVATE and debug_has_board_card_view(choice.source_index):
		opponent_card = board_cards[choice.source_index] as CardView
	if opponent_card == null or choice.target_index < 0:
		_finish_match()
		return
	await _commit_action(opponent_card, choice, DuelRules.OPPONENT_OWNER)


func _print_search_report(result: Dictionary) -> void:
	var action: ActionData = result.get("action", null) as ActionData
	var action_key: String = action.canonical_key() if action != null else "none"
	print(
		"AI_SEARCH elapsed=%.3f depth=%d nodes=%d cutoffs=%d cache_hits=%d reason=%s fallback=%s action=%s" % [
			float(result.get("elapsed_seconds", 0.0)),
			int(result.get("completed_depth", 0)),
			int(result.get("nodes", 0)),
			int(result.get("cutoffs", 0)),
			int(result.get("transposition_hits", 0)),
			String(result.get("completion_reason", &"unknown")),
			str(bool(result.get("used_fallback", false))),
			action_key,
		]
	)


func _cancel_opponent_search() -> void:
	if _opponent_search_session == null:
		return
	_opponent_search_session.cancel_and_join()
	_opponent_search_session = null


func _finish_match() -> void:
	_cancel_opponent_search()
	turn_state = TurnState.COMPLETE
	_sync_hand_playability()
	var player_total: int = DuelRules.count_owned(board, DuelRules.PLAYER_OWNER)
	var opponent_total: int = DuelRules.count_owned(board, DuelRules.OPPONENT_OWNER)
	if player_total > opponent_total:
		_match_outcome = OUTCOME_VICTORY
		turn_status.text = "获胜 · %d–%d" % [player_total, opponent_total]
	else:
		_match_outcome = OUTCOME_DEFEAT
		turn_status.text = "失败 · %d–%d" % [player_total, opponent_total]
	if not _is_replaying:
		_replay_record.complete(duel_state, _match_outcome, turn_status.text)
	print("DUEL_COMPLETE player=%d opponent=%d" % [player_total, opponent_total])


func _sync_hand_playability() -> void:
	for card: CardView in _get_cards_in_hand(player_hand):
		card.set_playable(
			not _inspection_open
			and not _is_replaying
			and turn_state == TurnState.PLAYER
			and duel_state != null
			and duel_state.active_player == DuelRules.PLAYER_OWNER
		)
	for card: CardView in _get_cards_in_hand(opponent_hand):
		card.set_playable(
			not _inspection_open
			and not _is_replaying
			and testing_mode
			and turn_state == TurnState.OPPONENT
			and duel_state != null
			and duel_state.active_player == DuelRules.OPPONENT_OWNER
		)
	for cell_index: int in range(board_cards.size()):
		var board_card := board_cards[cell_index] as CardView
		if board_card == null:
			continue
		var can_control_owner: bool = (
			not _is_replaying
			and (
			(board_card.owner_id == DuelRules.PLAYER_OWNER and turn_state == TurnState.PLAYER)
			or (board_card.owner_id == DuelRules.OPPONENT_OWNER and testing_mode and turn_state == TurnState.OPPONENT)
			)
		)
		board_card.set_playable(
			not _inspection_open
			and can_control_owner
			and _has_legal_activate_from(cell_index)
		)


func _can_manually_drag(card: CardView) -> bool:
	if _inspection_open or _is_replaying or duel_state == null or duel_state.active_player != card.owner_id:
		return false
	if card.owner_id == DuelRules.PLAYER_OWNER:
		return turn_state == TurnState.PLAYER
	if card.owner_id == DuelRules.OPPONENT_OWNER:
		return testing_mode and turn_state == TurnState.OPPONENT
	return false


func _get_hand_for_owner(owner_id: int) -> HBoxContainer:
	return player_hand if owner_id == DuelRules.PLAYER_OWNER else opponent_hand


func _get_card_instance_id(card: CardView) -> StringName:
	if card == null:
		return &""
	return StringName(card.card_data.get("instance_id", &""))


func _get_logical_hand_index(owner_id: int, instance_id: StringName) -> int:
	if duel_state == null or instance_id == &"":
		return -1
	var hand: Array = duel_state.get_hand(owner_id)
	for hand_index: int in range(hand.size()):
		var card_data: Dictionary = hand[hand_index]
		if StringName(card_data.get("instance_id", &"")) == instance_id:
			return hand_index
	return -1


func _get_card_view_for_logical_index(owner_id: int, hand_index: int) -> CardView:
	if duel_state == null:
		return null
	var hand: Array = duel_state.get_hand(owner_id)
	if hand_index < 0 or hand_index >= hand.size():
		return null
	var card_data: Dictionary = hand[hand_index]
	return _get_hand_card_view_by_instance(
		_get_hand_for_owner(owner_id),
		StringName(card_data.get("instance_id", &""))
	)


func _get_logical_hand_card_by_instance(owner_id: int, instance_id: StringName) -> Dictionary:
	var hand_index: int = _get_logical_hand_index(owner_id, instance_id)
	if hand_index < 0:
		return {}
	return duel_state.get_hand(owner_id)[hand_index]


func _get_hand_card_view_by_instance(container: HBoxContainer, instance_id: StringName) -> CardView:
	for card: CardView in _get_cards_in_hand(container):
		if _get_card_instance_id(card) == instance_id:
			return card
	return null


func _get_board_card_view_by_instance(instance_id: StringName) -> CardView:
	if instance_id == &"":
		return null
	for card_value: Variant in board_cards:
		var card := card_value as CardView
		if card != null and is_instance_valid(card) and _get_card_instance_id(card) == instance_id:
			return card
	return null


func _get_card_view_by_instance(instance_id: StringName) -> CardView:
	var board_card: CardView = _get_board_card_view_by_instance(instance_id)
	if board_card != null:
		return board_card
	var player_card: CardView = _get_hand_card_view_by_instance(player_hand, instance_id)
	if player_card != null:
		return player_card
	return _get_hand_card_view_by_instance(opponent_hand, instance_id)


func _get_first_empty_hand_slot(container: HBoxContainer) -> PanelContainer:
	for child: Node in container.get_children():
		var slot := child as PanelContainer
		if slot != null and _get_cards_in_slot(slot).is_empty():
			return slot
	return null


func _get_cards_in_slot(slot: Node) -> Array[CardView]:
	var cards: Array[CardView] = []
	for child: Node in slot.get_children():
		if child is CardView:
			cards.append(child as CardView)
	return cards


func _get_cards_in_hand(container: HBoxContainer) -> Array[CardView]:
	var result: Array[CardView] = []
	for slot: Node in container.get_children():
		for child: Node in slot.get_children():
			if child is CardView:
				result.append(child as CardView)
	return result


func _get_attack_vfx_placement(
	source_cell: int,
	target_cell: int
) -> Dictionary:
	if (
		source_cell < 0
		or source_cell >= 9
		or target_cell < 0
		or target_cell >= 9
		or source_cell == target_cell
		or board_cells.size() != 9
	):
		return {}

	var source_row: int = floori(float(source_cell) / 3.0)
	var source_column: int = source_cell % 3
	var target_row: int = floori(float(target_cell) / 3.0)
	var target_column: int = target_cell % 3
	var neighbor_cell: int = -1
	var rotation_radians: float = 0.0
	var horizontal_step: int = 0
	var vertical_step: int = 0
	if source_row == target_row:
		horizontal_step = 1 if target_column > source_column else -1
		neighbor_cell = source_cell + horizontal_step
		rotation_radians = 0.0 if horizontal_step > 0 else PI
	elif source_column == target_column:
		vertical_step = 1 if target_row > source_row else -1
		neighbor_cell = source_cell + vertical_step * 3
		rotation_radians = PI / 2.0 if vertical_step > 0 else -PI / 2.0
	else:
		return {}

	if (
		neighbor_cell < 0
		or neighbor_cell >= board_cells.size()
		or board_cells[source_cell] == null
		or board_cells[neighbor_cell] == null
		or not is_instance_valid(board_cells[source_cell])
		or not is_instance_valid(board_cells[neighbor_cell])
	):
		return {}

	var source_rect: Rect2 = board_cells[source_cell].get_global_rect()
	var neighbor_rect: Rect2 = board_cells[neighbor_cell].get_global_rect()
	var seam_center: Vector2
	if horizontal_step > 0:
		seam_center = Vector2(
			(source_rect.end.x + neighbor_rect.position.x) * 0.5,
			(source_rect.get_center().y + neighbor_rect.get_center().y) * 0.5
		)
	elif horizontal_step < 0:
		seam_center = Vector2(
			(source_rect.position.x + neighbor_rect.end.x) * 0.5,
			(source_rect.get_center().y + neighbor_rect.get_center().y) * 0.5
		)
	elif vertical_step > 0:
		seam_center = Vector2(
			(source_rect.get_center().x + neighbor_rect.get_center().x) * 0.5,
			(source_rect.end.y + neighbor_rect.position.y) * 0.5
		)
	else:
		seam_center = Vector2(
			(source_rect.get_center().x + neighbor_rect.get_center().x) * 0.5,
			(source_rect.position.y + neighbor_rect.end.y) * 0.5
		)

	return {
		"center": seam_center,
		"rotation": rotation_radians,
		"neighbor_cell": neighbor_cell,
	}


func _get_cell_at_position(pointer_position: Vector2) -> int:
	for cell_index: int in range(board_cells.size()):
		if board_cells[cell_index].get_global_rect().has_point(pointer_position):
			return cell_index
	return -1


func _get_board_cell_for_card(card: CardView) -> int:
	for cell_index: int in range(board_cards.size()):
		if board_cards[cell_index] == card:
			return cell_index
	return -1


func _get_drag_targets(card: CardView) -> Array[int]:
	var targets: Array[int] = []
	_drag_action_candidates.clear()
	if duel_state == null:
		return targets
	var source_cell: int = _get_board_cell_for_card(card)
	if source_cell < 0:
		for cell_index: int in range(board.size()):
			if DuelRules.can_place(board, cell_index):
				targets.append(cell_index)
		return targets
	for action: ActionData in Simulator.get_legal_actions(duel_state):
		if (
			action.action_type == ActionData.TYPE_ACTIVATE
			and action.source_index == source_cell
			and action.source_instance_id == _get_card_instance_id(card)
			and action.target_kind == ActionData.TARGET_BOARD_CELL
		):
			_drag_action_candidates.append(action)
			if action.target_index not in targets:
				targets.append(action.target_index)
	return targets


func _make_drag_action(card: CardView, target_cell: int) -> ActionData:
	if target_cell not in _drag_valid_targets:
		return null
	var instance_id: StringName = _get_card_instance_id(card)
	if _drag_source_zone == ActionData.SOURCE_HAND:
		return ActionData.make_play(
			_get_logical_hand_index(card.owner_id, instance_id),
			target_cell,
			instance_id
		)
	if _drag_source_zone == ActionData.SOURCE_BOARD:
		for action: ActionData in _drag_action_candidates:
			if (
				action.target_kind == ActionData.TARGET_BOARD_CELL
				and action.target_index == target_cell
			):
				return action.duplicate_action()
	return null


func _clear_drag_context() -> void:
	_remove_targeting_trace()
	_drag_source_zone = &""
	_drag_source_index = -1
	_drag_valid_targets.clear()
	_drag_action_candidates.clear()


func _begin_targeting_trace(card: CardView, pointer_position: Vector2) -> void:
	_remove_targeting_trace()
	_targeting_trace = Line2D.new()
	_targeting_trace.name = "ActivationTargetingTrace"
	_targeting_trace.width = targeting_trace_width
	_targeting_trace.default_color = targeting_trace_color
	_targeting_trace.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_targeting_trace.end_cap_mode = Line2D.LINE_CAP_ROUND
	_targeting_trace.antialiased = true
	_targeting_trace.z_index = 95
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 0.55))
	taper.add_point(Vector2(0.22, 1.0))
	taper.add_point(Vector2(1.0, 0.12))
	_targeting_trace.width_curve = taper
	var fade := Gradient.new()
	fade.set_color(0, targeting_trace_color)
	fade.set_color(1, Color(
		targeting_trace_color.r,
		targeting_trace_color.g,
		targeting_trace_color.b,
		targeting_trace_color.a * 0.32
	))
	_targeting_trace.gradient = fade
	drag_layer.add_child(_targeting_trace)
	var source_center: Vector2 = card.get_global_rect().get_center()
	var inverse_canvas: Transform2D = drag_layer.get_global_transform_with_canvas().affine_inverse()
	var source_local: Vector2 = inverse_canvas * source_center
	var pointer_local: Vector2 = inverse_canvas * pointer_position
	_targeting_trace.points = PackedVector2Array([
		source_local,
		(source_local + pointer_local) * 0.5,
		pointer_local,
	])
	_targeting_trace_end_global = pointer_position


func _update_targeting_trace(pointer_position: Vector2) -> void:
	if _targeting_trace == null or not is_instance_valid(_targeting_trace):
		return
	var inverse_canvas: Transform2D = drag_layer.get_global_transform_with_canvas().affine_inverse()
	var points: PackedVector2Array = _targeting_trace.points
	if points.size() < 3:
		return
	var pointer_local: Vector2 = inverse_canvas * pointer_position
	var direction: Vector2 = pointer_local - points[0]
	var perpendicular: Vector2 = Vector2(-direction.y, direction.x).normalized()
	points[1] = (points[0] + pointer_local) * 0.5 + perpendicular * 2.0
	points[2] = pointer_local
	_targeting_trace.points = points
	_targeting_trace_end_global = pointer_position


func _remove_targeting_trace() -> void:
	if _targeting_trace != null and is_instance_valid(_targeting_trace):
		_targeting_trace.queue_free()
	_targeting_trace = null


func _has_legal_activate_from(source_cell: int) -> bool:
	if duel_state == null:
		return false
	for action: ActionData in Simulator.get_legal_actions(duel_state):
		if action.action_type == ActionData.TYPE_ACTIVATE and action.source_index == source_cell:
			return true
	return false


func _highlight_legal_cells() -> void:
	for cell_index: int in range(board_cells.size()):
		if cell_index in _drag_valid_targets:
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
		style.bg_color = Color(0.18, 0.72, 0.68, 0.28)
		style.border_color = Color("45b9ad")
		style.set_border_width_all(3)
	elif mode == "hover":
		style.bg_color = Color(0.25, 0.86, 0.78, 0.52)
		style.border_color = Color("75e0d2")
		style.set_border_width_all(4)
	board_cells[cell_index].add_theme_stylebox_override("panel", style)


func _update_score() -> void:
	opponent_score.text = str(DuelRules.count_owned(board, DuelRules.OPPONENT_OWNER))
	player_score.text = str(DuelRules.count_owned(board, DuelRules.PLAYER_OWNER))


func _update_turn_status() -> void:
	if _inspection_open:
		turn_status.text = "查看卡牌详情 · 轻触返回"
		return
	match turn_state:
		TurnState.PLAYER:
			turn_status.text = "Testing · Player side · play or activate" if testing_mode else "你的回合 · 拖动卡牌"
		TurnState.RESOLVING:
			turn_status.text = "结算中…"
		TurnState.OPPONENT:
			turn_status.text = "Testing · Opponent side · play or activate" if testing_mode else "对手正在思考…"
		TurnState.COMPLETE:
			pass


func _layout_duel() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	var fitted_duel_rect: Rect2 = DuelBackdropData.fit_duel_rect(size)
	duel_canvas.position = fitted_duel_rect.position
	duel_canvas.size = fitted_duel_rect.size
	decor_backdrop.configure(fitted_duel_rect)
	var canvas_size: Vector2 = duel_canvas.size
	var horizontal_margin: float = maxf(12.0, canvas_size.x * 0.03)
	var available_hand_width: float = canvas_size.x - horizontal_margin * 2.0
	var card_width: float = (available_hand_width - 16.0) / 5.0
	var hand_height: float = minf(canvas_size.y * 0.14, card_width / 0.75)
	var header_height: float = clampf(canvas_size.y * 0.0625, 56.0, 62.0)
	var header_gap: float = clampf(canvas_size.y * 0.0146, 12.0, 18.0)
	var top_bar_height: float = 44.0
	var opponent_top: float = header_height + header_gap
	var opponent_bottom: float = opponent_top + hand_height
	var status_gap: float = 8.0
	var status_height: float = 26.0
	var bottom_safe_margin: float = 8.0
	var player_bottom_margin: float = maxf(canvas_size.y * 0.05, status_gap + status_height + bottom_safe_margin)
	var player_top: float = canvas_size.y - player_bottom_margin - hand_height
	var interval_height: float = maxf(180.0, player_top - opponent_bottom)
	var minimum_gap: float = maxf(18.0, canvas_size.y * 0.032)
	var desired_board_width: float = canvas_size.x * 0.72
	var board_height: float = minf(desired_board_width / board_aspect_ratio, interval_height - minimum_gap * 2.0)
	var board_width: float = board_height * board_aspect_ratio
	var equal_gap: float = (interval_height - board_height) * 0.5
	var board_position := Vector2((canvas_size.x - board_width) * 0.5, opponent_bottom + equal_gap)

	top_wash.position = Vector2.ZERO
	top_wash.offset_bottom = header_height
	top_bar.position = Vector2(horizontal_margin, (header_height - top_bar_height) * 0.5)
	top_bar.size = Vector2(available_hand_width, top_bar_height)
	opponent_hand.position = Vector2(horizontal_margin, opponent_top)
	opponent_hand.size = Vector2(available_hand_width, hand_height)
	player_hand.position = Vector2(horizontal_margin, player_top)
	player_hand.size = Vector2(available_hand_width, hand_height)
	board_grid.position = board_position
	board_grid.size = Vector2(board_width, board_height)
	replay_button.size = Vector2(44.0, 44.0)
	replay_button.position = Vector2(
		maxf(0.0, board_position.x - replay_button.size.x - 8.0),
		board_position.y + board_height * 0.5 - replay_button.size.y * 0.5
	)
	replay_button.pivot_offset = replay_button.size * 0.5
	if _inspection_open:
		card_inspector.set_board_rect(_get_board_rect())

	var score_width: float = minf(46.0, canvas_size.x * 0.085)
	var score_x: float = minf(canvas_size.x - horizontal_margin - score_width, board_position.x + board_width + 8.0)
	score_overlay.position = Vector2(score_x, board_position.y + board_height * 0.5 - 51.5)
	score_overlay.size = Vector2(score_width, 120.0)
	var desired_status_y: float = player_hand.position.y + player_hand.size.y + status_gap
	var maximum_status_y: float = canvas_size.y - bottom_safe_margin - status_height
	turn_status.position = Vector2(player_hand.position.x, minf(desired_status_y, maximum_status_y))
	turn_status.size = Vector2(player_hand.size.x, status_height)


func _get_board_rect() -> Rect2:
	return Rect2(
		board_grid.global_position - duel_canvas.global_position,
		board_grid.size
	)


func _style_static_ui() -> void:
	_style_duel_header()
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


func _style_duel_header() -> void:
	top_wash.color = DuelBackdropData.LACQUER_COLOR
	top_wash_edge.color = Color("c29969")
	top_wash_shadow.color = Color(0.08, 0.05, 0.04, 0.22)
	top_wash_shadow.offset_bottom = 3.0

	var header_texture: GradientTexture2D = DuelBackdropData.create_lacquer_tint_texture(540)
	top_wash_tint.texture = header_texture

	var seal_style := StyleBoxFlat.new()
	seal_style.bg_color = Color("9e332f")
	seal_style.border_color = Color("c99261")
	seal_style.set_border_width_all(1)
	seal_style.set_corner_radius_all(2)
	seal_style.shadow_color = Color(0.08, 0.03, 0.02, 0.42)
	seal_style.shadow_size = 2
	seal_style.shadow_offset = Vector2(0.0, 1.0)
	enemy_seal.add_theme_stylebox_override("panel", seal_style)
	enemy_seal_label.add_theme_color_override("font_color", Color("f1d8b1"))
	enemy_seal_label.add_theme_font_size_override("font_size", 14)

	opponent_name.add_theme_color_override("font_color", Color("f2e4c7"))
	opponent_name.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.03, 0.55))
	opponent_name.add_theme_constant_override("outline_size", 1)
	opponent_name.add_theme_font_size_override("font_size", 22)
	opponent_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	opponent_name.clip_text = true

	var exit_empty := StyleBoxEmpty.new()
	for style_name: StringName in [
		&"normal",
		&"hover",
		&"pressed",
		&"hover_pressed",
		&"disabled",
		&"focus",
	]:
		exit_button.add_theme_stylebox_override(style_name, exit_empty)
	exit_button.add_theme_color_override("icon_normal_color", Color("e2c89c"))
	exit_button.add_theme_color_override("icon_hover_color", Color("f4ddb2"))
	exit_button.add_theme_color_override("icon_pressed_color", Color("cdb387"))
	exit_button.add_theme_color_override("icon_hover_pressed_color", Color("d8bd91"))
	exit_button.add_theme_color_override("icon_focus_color", Color("f4ddb2"))
	exit_button.add_theme_color_override("icon_disabled_color", Color(0.62, 0.52, 0.4, 0.55))


func _create_placeholder_audio() -> void:
	placement_audio.stream = _make_tone(190.0, 0.07)
	capture_audio.stream = _make_tone(470.0, 0.09)
	removal_audio.stream = _make_removal_tone(0.14)
	removal_audio.volume_db = removal_audio_volume_db
	movement_audio.stream = _make_movement_whoosh(0.16)
	movement_audio.volume_db = movement_audio_volume_db


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


func _make_movement_whoosh(duration: float) -> AudioStreamWAV:
	var sample_rate: int = 22050
	var sample_count: int = int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for sample_index: int in range(sample_count):
		var time: float = float(sample_index) / float(sample_rate)
		var progress: float = float(sample_index) / float(sample_count)
		var envelope: float = sin(PI * progress) * 0.10
		var brush_noise: float = sin(TAU * 941.0 * time) * sin(TAU * 377.0 * time)
		var low_air: float = sin(TAU * (150.0 + progress * 90.0) * time) * 0.35
		var wave: float = (brush_noise * 0.65 + low_air) * envelope
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


func _play_movement_feedback() -> void:
	_movement_sound_count += 1
	if not OS.has_feature("headless"):
		movement_audio.play()


func _vibrate(duration_ms: int) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms)


func _on_replay_pressed() -> void:
	if turn_state != TurnState.COMPLETE or _is_replaying or not _replay_record.is_ready():
		return
	_start_replay()


func _on_replay_button_down() -> void:
	if _replay_feedback_tween != null and _replay_feedback_tween.is_valid():
		_replay_feedback_tween.kill()
	replay_button.scale = Vector2(0.92, 0.92)
	replay_button.modulate.a = 0.62


func _on_replay_button_up() -> void:
	_play_replay_button_feedback(Vector2.ONE, 1.0, 0.14, Tween.TRANS_BACK)


func _play_replay_button_feedback(
	target_scale: Vector2,
	target_alpha: float,
	duration: float,
	transition: Tween.TransitionType
) -> void:
	if _replay_feedback_tween != null and _replay_feedback_tween.is_valid():
		_replay_feedback_tween.kill()
	_replay_feedback_tween = create_tween()
	_replay_feedback_tween.set_parallel(true)
	_replay_feedback_tween.set_trans(transition).set_ease(Tween.EASE_OUT)
	_replay_feedback_tween.tween_property(replay_button, "scale", target_scale, duration)
	_replay_feedback_tween.tween_property(replay_button, "modulate:a", target_alpha, duration)


func _start_replay() -> bool:
	if (
		turn_state != TurnState.COMPLETE
		or _is_replaying
		or not _replay_record.is_ready()
	):
		return false
	_cancel_opponent_search()
	_replay_generation += 1
	var generation: int = _replay_generation
	_is_replaying = true
	_is_replay_presenting_action = false
	var initial_state: StateData = _replay_record.get_initial_state()
	if initial_state == null:
		_restore_completed_replay_state("Replay initial state is unavailable")
		return false
	_rebuild_views_from_state(initial_state)
	var actions: Array[ActionData] = _replay_record.get_actions()
	for action_index: int in range(actions.size()):
		if generation != _replay_generation or not is_inside_tree():
			return false
		var action: ActionData = actions[action_index]
		if not Simulator.is_action_legal(duel_state, action):
			_restore_completed_replay_state(
				"Replay action %d is no longer legal" % action_index
			)
			return false
		var source_card: CardView = _get_card_view_by_instance(action.source_instance_id)
		if source_card == null:
			_restore_completed_replay_state(
				"Replay action %d has no source view" % action_index
			)
			return false
		var owner_id: int = duel_state.active_player
		_is_replay_presenting_action = true
		await _commit_action(source_card, action, owner_id, false)
		_is_replay_presenting_action = false
		if generation != _replay_generation or not is_inside_tree():
			return false
		if action_index < actions.size() - 1:
			if not await _wait_replay_delay(generation):
				return false
	if not Simulator.is_terminal(duel_state):
		_restore_completed_replay_state("Replay ended before reaching a terminal state")
		return false
	_is_replaying = false
	_is_replay_presenting_action = false
	turn_state = TurnState.COMPLETE
	_match_outcome = _replay_record.get_outcome()
	turn_status.text = _replay_record.get_final_status()
	turn_status.modulate = Color("3b211d")
	_sync_hand_playability()
	_update_score()
	return true


func _wait_replay_delay(generation: int) -> bool:
	_replay_delay_remaining = replay_turn_delay
	var previous_ticks: int = Time.get_ticks_usec()
	while _replay_delay_remaining > 0.0:
		await get_tree().process_frame
		if generation != _replay_generation or not is_inside_tree():
			_replay_delay_remaining = 0.0
			return false
		var current_ticks: int = Time.get_ticks_usec()
		if not _inspection_open:
			_replay_delay_remaining -= float(current_ticks - previous_ticks) / 1000000.0
		previous_ticks = current_ticks
	_replay_delay_remaining = 0.0
	return true


func _restore_completed_replay_state(reason: String) -> void:
	push_warning(reason)
	var final_state: StateData = _replay_record.get_final_state()
	if final_state != null:
		_rebuild_views_from_state(final_state)
	_is_replaying = false
	_is_replay_presenting_action = false
	_replay_delay_remaining = 0.0
	turn_state = TurnState.COMPLETE
	_match_outcome = _replay_record.get_outcome()
	turn_status.text = _replay_record.get_final_status()
	turn_status.modulate = Color("3b211d")
	_sync_hand_playability()
	_update_score()


func _rebuild_views_from_state(source_state: StateData) -> void:
	duel_state = source_state.duplicate_state() as StateData
	board = duel_state.board
	_clear_all_card_views()
	for owner_id: int in [DuelRules.OPPONENT_OWNER, DuelRules.PLAYER_OWNER]:
		var hand_container: HBoxContainer = _get_hand_for_owner(owner_id)
		var hand: Array = duel_state.get_hand(owner_id)
		for card_index: int in range(mini(hand.size(), hand_container.get_child_count())):
			var card_data: Dictionary = hand[card_index]
			var card: CardView = _spawn_card_in_slot(
				hand_container.get_child(card_index) as PanelContainer,
				card_data,
				owner_id,
				false
			)
			card.set_face_down(_should_conceal_hand_card(card_data, owner_id))
	for cell_index: int in range(mini(board.size(), board_cells.size())):
		var slot_value: Variant = board[cell_index]
		if slot_value == null:
			continue
		var logical_slot: Dictionary = slot_value
		var owner_id: int = int(logical_slot.get("owner", 0))
		var card_data: Dictionary = logical_slot.get("card", {})
		var card: CardView = _spawn_card_in_slot(
			board_cells[cell_index],
			card_data,
			owner_id,
			false
		)
		card.set_face_down(false)
		card.z_index = 1
		board_cards[cell_index] = card
	_clear_drag_context()
	_clear_cell_highlights()
	turn_state = (
		TurnState.PLAYER
		if duel_state.active_player == DuelRules.PLAYER_OWNER
		else TurnState.OPPONENT
	)
	_sync_hand_playability()
	_update_score()
	_update_turn_status()


func _clear_all_card_views() -> void:
	var observed: Dictionary = {}
	for hand_container: HBoxContainer in [opponent_hand, player_hand]:
		for slot: Node in hand_container.get_children():
			for child: Node in slot.get_children():
				if child is CardView:
					observed[child.get_instance_id()] = child
	for card_value: Variant in board_cards:
		var card := card_value as CardView
		if card != null and is_instance_valid(card):
			observed[card.get_instance_id()] = card
	for child: Node in drag_layer.get_children():
		if child is CardView:
			observed[child.get_instance_id()] = child
	for card_value: Variant in observed.values():
		var card := card_value as CardView
		if card != null and is_instance_valid(card):
			card.free()
	board_cards.fill(null)


func _on_exit_pressed() -> void:
	if _return_emitted:
		return
	var was_replaying: bool = _is_replaying
	_return_emitted = true
	_replay_generation += 1
	_is_replaying = false
	_is_replay_presenting_action = false
	_replay_delay_remaining = 0.0
	_cancel_opponent_search()
	var outcome: StringName = (
		_replay_record.get_outcome()
		if was_replaying and _replay_record.is_ready()
		else _match_outcome
		if turn_state == TurnState.COMPLETE and _match_outcome != &""
		else OUTCOME_ABANDONED
	)
	return_requested.emit(outcome)
