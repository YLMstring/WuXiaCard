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
var max_turns: int = 200
var active_abilities: Array = []
var effect_queue: Array = []
var pending_choice: Dictionary = {}
var repetition_hashes: Array = []
var remembered_glyphs_by_owner: Dictionary = {}
var future_draw_reveal_audiences: Dictionary = {}
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
	copied.state_version = state_version
	return copied
