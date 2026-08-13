class_name DuelState
extends RefCounted

const Rules = preload("res://scripts/duel_rules.gd")

var board: Array = []
var hands: Dictionary = {}
var decks: Dictionary = {}
var discard_piles: Dictionary = {}
var removed_cards: Dictionary = {}
var active_player: int = Rules.PLAYER_OWNER
var turn_count: int = 0
var owner_turn_serial: int = 0
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
var state_version: int = 0


func _init(
	new_board: Array = [],
	player_hand: Array = [],
	opponent_hand: Array = [],
	new_active_player: int = Rules.PLAYER_OWNER,
	new_turn_count: int = 0,
	player_deck: Array = [],
	opponent_deck: Array = []
) -> void:
	board = new_board.duplicate(true)
	hands = {
		Rules.PLAYER_OWNER: player_hand.duplicate(true),
		Rules.OPPONENT_OWNER: opponent_hand.duplicate(true),
	}
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


func get_hand(owner_id: int) -> Array:
	return hands.get(owner_id, [])


func duplicate_state():
	var copied = get_script().new(
		board,
		get_hand(Rules.PLAYER_OWNER),
		get_hand(Rules.OPPONENT_OWNER),
		active_player,
		turn_count,
		decks.get(Rules.PLAYER_OWNER, []),
		decks.get(Rules.OPPONENT_OWNER, [])
	)
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
	copied.extra_card_plays_remaining = extra_card_plays_remaining
	copied.end_turn_triggers_resolved = end_turn_triggers_resolved
	copied.state_version = state_version
	return copied


func get_enabled_effect_gates(owner_id: int) -> Array:
	return enabled_effect_gates_by_owner.get(owner_id, []) as Array
