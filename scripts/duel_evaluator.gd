class_name DuelEvaluator
extends RefCounted

const WIN_SCORE: int = 1_000_000
const DECK_CARD_WEIGHT: int = 25
const POWER_WEIGHT: int = 1
const MOBILITY_WEIGHT: int = 1
const KI_WEIGHT: int = 4
const ACTIVE_ABILITY_WEIGHT: int = 4
const DANGER_WEIGHT: int = 2
const TEMPO_WEIGHT: int = 2
const POSITIONAL_LIMIT: int = 499
const STRATEGIC_SCALE: int = 1_000
const ENHANCED_PROFILE: StringName = &"enhanced"
const USABLE_KI_BONUS: int = 2
const ATTACK_POTENTIAL_WEIGHT: int = 3
const EXTRA_PLAY_TEMPO_WEIGHT: int = 4

const Abilities = preload("res://scripts/duel_abilities.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const StateData = preload("res://scripts/duel_state.gd")


static func evaluate(
	state: StateData,
	root_owner: int,
	evaluator_profile: StringName = &"baseline"
) -> int:
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
	if evaluator_profile == ENHANCED_PROFILE:
		positional_score += _ki_usability_adjustment(state, root_owner)
		positional_score -= _ki_usability_adjustment(state, opponent_owner)
		positional_score += (
			attack_potential(state, root_owner)
			- attack_potential(state, opponent_owner)
		) * ATTACK_POTENTIAL_WEIGHT
		positional_score += score_difference * endgame_pressure(state)
		var extra_play_tempo: int = state.extra_card_plays_remaining * EXTRA_PLAY_TEMPO_WEIGHT
		positional_score += extra_play_tempo if state.active_player == root_owner else -extra_play_tempo
	positional_score = clampi(positional_score, -POSITIONAL_LIMIT, POSITIONAL_LIMIT)
	return clampi(
		strategic_score * STRATEGIC_SCALE + positional_score,
		-WIN_SCORE + 1,
		WIN_SCORE - 1
	)


static func endgame_pressure(state: StateData) -> int:
	if state == null:
		return 0
	var occupied_cells: int = 0
	for slot_value: Variant in state.board:
		if slot_value != null:
			occupied_cells += 1
	var pressure: int = occupied_cells * 2
	var remaining_turns: int = maxi(state.max_turns - state.turn_count, 0)
	if remaining_turns <= 20:
		pressure += 20 - remaining_turns
	var repetition_counts: Dictionary = {}
	var maximum_repetitions: int = 0
	for signature_value: Variant in state.repetition_hashes:
		var signature: String = String(signature_value)
		repetition_counts[signature] = int(repetition_counts.get(signature, 0)) + 1
		maximum_repetitions = maxi(maximum_repetitions, int(repetition_counts[signature]))
	pressure += maximum_repetitions * 3
	return pressure


static func attack_potential(state: StateData, owner_id: int) -> int:
	if state == null:
		return 0
	var context: Dictionary = {
		"enabled_effect_gates_by_owner": state.enabled_effect_gates_by_owner,
	}
	var potential: int = 0
	for cell_index: int in range(state.board.size()):
		var slot_value: Variant = state.board[cell_index]
		if slot_value == null or int((slot_value as Dictionary).get("owner", 0)) != owner_id:
			continue
		potential += mini(Rules.get_would_flip_indices(state.board, cell_index, context).size(), 2)
	return potential


static func _zone_value(cards: Array, card_weight: int) -> int:
	var value: int = cards.size() * card_weight
	for card_value: Variant in cards:
		var card: Dictionary = card_value
		value += _power_sum(card) * POWER_WEIGHT
		value += int(card.get("ki", 0)) * KI_WEIGHT
		value += (card.get("active_abilities", []) as Array).size() * ACTIVE_ABILITY_WEIGHT
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
		value += (card.get("active_abilities", []) as Array).size() * ACTIVE_ABILITY_WEIGHT
	return value


static func _ki_usability_adjustment(state: StateData, owner_id: int) -> int:
	var adjustment: int = 0
	var gates: Array = state.get_enabled_effect_gates(owner_id)
	for card_value: Variant in state.get_hand(owner_id):
		adjustment += _card_ki_usability_adjustment(card_value as Dictionary, gates)
	for slot_value: Variant in state.board:
		if slot_value == null or int((slot_value as Dictionary).get("owner", 0)) != owner_id:
			continue
		adjustment += _card_ki_usability_adjustment(
			(slot_value as Dictionary).get("card", {}) as Dictionary,
			gates
		)
	return adjustment


static func _card_ki_usability_adjustment(card: Dictionary, gates: Array) -> int:
	var ki: int = maxi(int(card.get("ki", 0)), 0)
	if ki == 0:
		return 0
	if Abilities.card_can_spend_ki(card, gates):
		return ki * USABLE_KI_BONUS
	return -ki * KI_WEIGHT


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
