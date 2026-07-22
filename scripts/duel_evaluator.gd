class_name DuelEvaluator
extends RefCounted

const WIN_SCORE: int = 1_000_000
const DECK_CARD_WEIGHT: int = 25
const POWER_WEIGHT: int = 1
const MOBILITY_WEIGHT: int = 1
const KI_WEIGHT: int = 4
const ACTIVE_EFFECT_WEIGHT: int = 4
const DANGER_WEIGHT: int = 2
const TEMPO_WEIGHT: int = 2
const POSITIONAL_LIMIT: int = 499
const STRATEGIC_SCALE: int = 1_000

const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const StateData = preload("res://scripts/duel_state.gd")


static func evaluate(state: StateData, root_owner: int) -> int:
	if state == null:
		return -WIN_SCORE
	var score_difference: int = Simulator.score_difference(state, root_owner)
	if Simulator.is_terminal(state):
		if score_difference > 0:
			return WIN_SCORE + score_difference * 100 - state.turn_count
		if score_difference < 0:
			return -WIN_SCORE + score_difference * 100 + state.turn_count
		return 0

	var opponent_owner: int = Simulator.other_owner(root_owner)
	var strategic_score: int = score_difference * 100
	strategic_score += (
		state.get_hand(root_owner).size()
		- state.get_hand(opponent_owner).size()
	) * 5
	var positional_score: int = (
		_zone_value(state.get_hand(root_owner), 0)
		- _zone_value(state.get_hand(opponent_owner), 0)
	)
	positional_score += (
		_zone_value(state.decks.get(root_owner, []), DECK_CARD_WEIGHT)
		- _zone_value(state.decks.get(opponent_owner, []), DECK_CARD_WEIGHT)
	)
	positional_score += (
		Simulator.get_legal_actions_for_owner(state, root_owner).size()
		- Simulator.get_legal_actions_for_owner(state, opponent_owner).size()
	) * MOBILITY_WEIGHT
	positional_score += _board_resource_value(state, root_owner) - _board_resource_value(state, opponent_owner)
	positional_score += _danger_value(state, opponent_owner) - _danger_value(state, root_owner)
	positional_score += TEMPO_WEIGHT if state.active_player == root_owner else -TEMPO_WEIGHT
	positional_score = clampi(positional_score, -POSITIONAL_LIMIT, POSITIONAL_LIMIT)
	return strategic_score * STRATEGIC_SCALE + positional_score


static func _zone_value(cards: Array, card_weight: int) -> int:
	var value: int = cards.size() * card_weight
	for card_value: Variant in cards:
		var card: Dictionary = card_value
		value += _power_sum(card) * POWER_WEIGHT
		value += int(card.get("ki", 0)) * KI_WEIGHT
		value += (card.get("active_effects", []) as Array).size() * ACTIVE_EFFECT_WEIGHT
	return value


static func _board_resource_value(state: StateData, owner_id: int) -> int:
	var value: int = 0
	for slot_value: Variant in state.board:
		if slot_value == null:
			continue
		var slot: Dictionary = slot_value
		if int(slot.get("owner", 0)) != owner_id:
			continue
		var card: Dictionary = slot.get("card", {})
		value += _power_sum(card) * POWER_WEIGHT
		value += int(card.get("ki", 0)) * KI_WEIGHT
		value += (card.get("active_effects", []) as Array).size() * ACTIVE_EFFECT_WEIGHT
	return value


static func _danger_value(state: StateData, owner_id: int) -> int:
	var danger: int = 0
	for cell_index: int in range(state.board.size()):
		var slot_value: Variant = state.board[cell_index]
		if slot_value == null or int((slot_value as Dictionary).get("owner", 0)) != owner_id:
			continue
		var card: Dictionary = (slot_value as Dictionary).get("card", {})
		var powers: Array = card.get("powers", [0, 0, 0, 0])
		for direction: int in range(4):
			var neighbor_index: int = Rules.get_neighbor_index(cell_index, direction)
			if neighbor_index < 0:
				continue
			var neighbor_value: Variant = state.board[neighbor_index]
			if neighbor_value == null or int((neighbor_value as Dictionary).get("owner", 0)) == owner_id:
				continue
			var enemy_card: Dictionary = (neighbor_value as Dictionary).get("card", {})
			var enemy_powers: Array = enemy_card.get("powers", [0, 0, 0, 0])
			if int(enemy_powers[Rules.OPPOSITE[direction]]) > int(powers[direction]):
				danger += DANGER_WEIGHT
	return danger


static func _power_sum(card: Dictionary) -> int:
	var total: int = 0
	for power: Variant in card.get("powers", []):
		total += int(power)
	return total
