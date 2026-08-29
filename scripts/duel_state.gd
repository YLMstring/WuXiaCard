class_name DuelState
extends RefCounted

const Rules = preload("res://scripts/duel_rules.gd")

const HAND_SLOT_COUNT: int = 5
const HAND_SLOT_INDEX_KEY: StringName = &"hand_slot_index"

var board: Array = []
var hands: Dictionary = {}
var decks: Dictionary = {}
var discard_piles: Dictionary = {}
var removed_cards: Dictionary = {}
var active_player: int = Rules.PLAYER_OWNER
var turn_count: int = 0
var owner_turn_serial: int = 0
var attacks_started_by_owner: Dictionary = {}
var extra_card_plays_remaining: int = 0
var end_turn_triggers_resolved: bool = false
var max_turns: int = 100
var active_abilities: Array = []
var effect_queue: Array = []
var pending_choice: Dictionary = {}
var repetition_hashes: Array = []
var remembered_glyphs_by_owner: Dictionary = {}
var future_draw_reveal_audiences: Dictionary = {}
var last_hand_play_by_owner: Dictionary = {}
var pending_non_retained_suppression_by_owner: Dictionary = {}
var enabled_effect_gates_by_owner: Dictionary = {}
var run_difficulty: int = 0
var difficulty_eight_draw_consumed: bool = false
var state_version: int = 0


func _init(
	new_board: Array = [],
	player_hand: Array = [],
	opponent_hand: Array = [],
	new_active_player: int = Rules.PLAYER_OWNER,
	new_turn_count: int = 0,
	player_deck: Array = [],
	opponent_deck: Array = [],
	new_run_difficulty: int = 0,
	new_difficulty_eight_draw_consumed: bool = false
) -> void:
	board = new_board.duplicate(true)
	hands = {
		Rules.PLAYER_OWNER: player_hand.duplicate(true),
		Rules.OPPONENT_OWNER: opponent_hand.duplicate(true),
	}
	_normalize_hand_slots(hands[Rules.PLAYER_OWNER] as Array)
	_normalize_hand_slots(hands[Rules.OPPONENT_OWNER] as Array)
	decks = {
		Rules.PLAYER_OWNER: player_deck.duplicate(true),
		Rules.OPPONENT_OWNER: opponent_deck.duplicate(true),
	}
	discard_piles = {
		Rules.PLAYER_OWNER: [],
		Rules.OPPONENT_OWNER: [],
	}
	removed_cards = {
		Rules.PLAYER_OWNER: [],
		Rules.OPPONENT_OWNER: [],
	}
	attacks_started_by_owner = {
		Rules.PLAYER_OWNER: 0,
		Rules.OPPONENT_OWNER: 0,
	}
	last_hand_play_by_owner = {
		Rules.PLAYER_OWNER: {},
		Rules.OPPONENT_OWNER: {},
	}
	pending_non_retained_suppression_by_owner = {
		Rules.PLAYER_OWNER: 0,
		Rules.OPPONENT_OWNER: 0,
	}
	enabled_effect_gates_by_owner = {
		Rules.PLAYER_OWNER: [],
		Rules.OPPONENT_OWNER: [Rules.EFFECT_GATE_SELF_CASTRATION],
	}
	active_player = new_active_player
	turn_count = new_turn_count
	run_difficulty = clampi(new_run_difficulty, 0, 9)
	difficulty_eight_draw_consumed = new_difficulty_eight_draw_consumed


func get_hand(owner_id: int) -> Array:
	return hands.get(owner_id, [])


func get_leftmost_empty_hand_slot(owner_id: int) -> int:
	var occupied: Dictionary = {}
	for card_value: Variant in get_hand(owner_id):
		if not card_value is Dictionary:
			continue
		var slot_index: int = int((card_value as Dictionary).get(HAND_SLOT_INDEX_KEY, -1))
		if slot_index >= 0 and slot_index < HAND_SLOT_COUNT:
			occupied[slot_index] = true
	for slot_index: int in range(HAND_SLOT_COUNT):
		if not occupied.has(slot_index):
			return slot_index
	return -1


func assign_card_to_leftmost_empty_hand_slot(owner_id: int, card: Dictionary) -> int:
	var slot_index: int = get_leftmost_empty_hand_slot(owner_id)
	if slot_index >= 0:
		card[HAND_SLOT_INDEX_KEY] = slot_index
	return slot_index


func shift_hand_slots_after_discard(owner_id: int, discarded_slot: int) -> Array[Dictionary]:
	return shift_hand_slots_after_batch_discard(owner_id, [discarded_slot])


func shift_hand_slots_after_batch_discard(
	owner_id: int,
	discarded_slots: Array[int]
) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	var valid_slots: Array[int] = []
	for discarded_slot: int in discarded_slots:
		if (
			discarded_slot >= 0
			and discarded_slot < HAND_SLOT_COUNT
			and discarded_slot not in valid_slots
		):
			valid_slots.append(discarded_slot)
	valid_slots.sort()
	if valid_slots.is_empty():
		return moves
	for card_value: Variant in get_hand(owner_id):
		if not card_value is Dictionary:
			continue
		var card: Dictionary = card_value
		var from_slot: int = int(card.get(HAND_SLOT_INDEX_KEY, -1))
		if from_slot < 0 or from_slot >= HAND_SLOT_COUNT:
			continue
		var removed_before: int = 0
		for discarded_slot: int in valid_slots:
			if discarded_slot < from_slot:
				removed_before += 1
		var to_slot: int = from_slot - removed_before
		if to_slot == from_slot:
			continue
		card[HAND_SLOT_INDEX_KEY] = to_slot
		moves.append({
			"instance_id": StringName(card.get("instance_id", &"")),
			"from_slot": from_slot,
			"to_slot": to_slot,
		})
	moves.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return int(first.get("from_slot", -1)) < int(second.get("from_slot", -1))
	)
	return moves


func _normalize_hand_slots(hand: Array) -> void:
	var occupied: Dictionary = {}
	var unassigned: Array[Dictionary] = []
	for card_value: Variant in hand:
		if not card_value is Dictionary:
			continue
		var card: Dictionary = card_value
		var slot_index: int = int(card.get(HAND_SLOT_INDEX_KEY, -1))
		if (
			slot_index >= 0
			and slot_index < HAND_SLOT_COUNT
			and not occupied.has(slot_index)
		):
			occupied[slot_index] = true
		else:
			card.erase(HAND_SLOT_INDEX_KEY)
			unassigned.append(card)
	for card: Dictionary in unassigned:
		for slot_index: int in range(HAND_SLOT_COUNT):
			if occupied.has(slot_index):
				continue
			card[HAND_SLOT_INDEX_KEY] = slot_index
			occupied[slot_index] = true
			break


func duplicate_state() -> DuelState:
	var copied: DuelState = get_script().new() as DuelState
	copied.board = _duplicate_board(board)
	copied.hands = _duplicate_card_zones(hands)
	copied.decks = _duplicate_card_zones(decks)
	copied.discard_piles = _duplicate_card_zones(discard_piles)
	copied.removed_cards = _duplicate_card_zones(removed_cards)
	copied.active_player = active_player
	copied.turn_count = turn_count
	copied.run_difficulty = run_difficulty
	copied.difficulty_eight_draw_consumed = difficulty_eight_draw_consumed
	copied.max_turns = max_turns
	copied.active_abilities = active_abilities.duplicate()
	copied.effect_queue = effect_queue.duplicate(true)
	copied.pending_choice = pending_choice.duplicate(true)
	copied.repetition_hashes = repetition_hashes.duplicate(true)
	copied.remembered_glyphs_by_owner = remembered_glyphs_by_owner.duplicate(true)
	copied.future_draw_reveal_audiences = future_draw_reveal_audiences.duplicate(true)
	copied.last_hand_play_by_owner = last_hand_play_by_owner.duplicate(true)
	copied.pending_non_retained_suppression_by_owner = pending_non_retained_suppression_by_owner.duplicate(true)
	copied.enabled_effect_gates_by_owner = enabled_effect_gates_by_owner.duplicate(true)
	copied.owner_turn_serial = owner_turn_serial
	copied.attacks_started_by_owner = attacks_started_by_owner.duplicate(true)
	copied.extra_card_plays_remaining = extra_card_plays_remaining
	copied.end_turn_triggers_resolved = end_turn_triggers_resolved
	copied.state_version = state_version
	return copied


func duplicate_state_deep_reference() -> DuelState:
	var copied: DuelState = get_script().new(
		board,
		get_hand(Rules.PLAYER_OWNER),
		get_hand(Rules.OPPONENT_OWNER),
		active_player,
		turn_count,
		decks.get(Rules.PLAYER_OWNER, []),
		decks.get(Rules.OPPONENT_OWNER, []),
		run_difficulty,
		difficulty_eight_draw_consumed
	) as DuelState
	copied.discard_piles = discard_piles.duplicate(true)
	copied.removed_cards = removed_cards.duplicate(true)
	copied.max_turns = max_turns
	copied.active_abilities = active_abilities.duplicate(true)
	copied.effect_queue = effect_queue.duplicate(true)
	copied.pending_choice = pending_choice.duplicate(true)
	copied.repetition_hashes = repetition_hashes.duplicate(true)
	copied.remembered_glyphs_by_owner = remembered_glyphs_by_owner.duplicate(true)
	copied.future_draw_reveal_audiences = future_draw_reveal_audiences.duplicate(true)
	copied.last_hand_play_by_owner = last_hand_play_by_owner.duplicate(true)
	copied.pending_non_retained_suppression_by_owner = pending_non_retained_suppression_by_owner.duplicate(true)
	copied.enabled_effect_gates_by_owner = enabled_effect_gates_by_owner.duplicate(true)
	copied.owner_turn_serial = owner_turn_serial
	copied.attacks_started_by_owner = attacks_started_by_owner.duplicate(true)
	copied.extra_card_plays_remaining = extra_card_plays_remaining
	copied.end_turn_triggers_resolved = end_turn_triggers_resolved
	copied.state_version = state_version
	return copied


func _duplicate_board(source: Array) -> Array:
	var copied: Array = []
	copied.resize(source.size())
	for cell: int in range(source.size()):
		var slot_value: Variant = source[cell]
		if slot_value == null:
			continue
		var source_slot: Dictionary = slot_value as Dictionary
		var copied_slot: Dictionary = source_slot.duplicate()
		copied_slot["card"] = _duplicate_runtime_card(
			source_slot.get("card", {}) as Dictionary
		)
		copied[cell] = copied_slot
	return copied


func _duplicate_card_zones(source: Dictionary) -> Dictionary:
	return {
		Rules.PLAYER_OWNER: _duplicate_card_array(
			source.get(Rules.PLAYER_OWNER, []) as Array
		),
		Rules.OPPONENT_OWNER: _duplicate_card_array(
			source.get(Rules.OPPONENT_OWNER, []) as Array
		),
	}


func _duplicate_card_array(source: Array) -> Array:
	var copied: Array = []
	copied.resize(source.size())
	for index: int in range(source.size()):
		copied[index] = _duplicate_runtime_card(source[index] as Dictionary)
	return copied


func _duplicate_runtime_card(source: Dictionary) -> Dictionary:
	var copied: Dictionary = source.duplicate()
	if source.has("powers"):
		copied["powers"] = (source.get("powers", []) as Array).duplicate()
	if source.has("active_abilities"):
		copied["active_abilities"] = (
			source.get("active_abilities", []) as Array
		).duplicate()
	if source.has("revealed_to_owner_ids"):
		copied["revealed_to_owner_ids"] = (
			source.get("revealed_to_owner_ids", []) as Array
		).duplicate()
	if source.has("temporary_suppression_batches"):
		copied["temporary_suppression_batches"] = (
			source.get("temporary_suppression_batches", []) as Array
		).duplicate(true)
	return copied


func get_enabled_effect_gates(owner_id: int) -> Array:
	return enabled_effect_gates_by_owner.get(owner_id, []) as Array
