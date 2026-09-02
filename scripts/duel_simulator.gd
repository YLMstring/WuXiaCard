class_name DuelSimulator
extends RefCounted

const ActionData = preload("res://scripts/duel_action.gd")
const Abilities = preload("res://scripts/duel_abilities.gd")
const Executor = preload("res://scripts/duel_ability_executor.gd")
const NativeRules = preload("res://scripts/duel_native_rules.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const StateData = preload("res://scripts/duel_state.gd")
const Targeting = preload("res://scripts/duel_targeting.gd")

const BOARD_REPETITION_LIMIT: int = 5
const MAX_ATTACKS_PER_OWNER_TURN: int = 20


static func get_legal_actions(state: StateData) -> Array[ActionData]:
	return [] if state == null else get_legal_actions_for_owner(state, state.active_player)


static func get_legal_actions_for_owner(state: StateData, owner_id: int) -> Array[ActionData]:
	var actions: Array[ActionData] = []
	if state == null or state.board.size() != 9:
		return actions
	var hand: Array = state.get_hand(owner_id)
	for hand_index: int in range(hand.size()):
		var instance_id := StringName((hand[hand_index] as Dictionary).get("instance_id", &""))
		for cell_index: int in range(9):
			if Rules.can_place(state.board, cell_index):
				actions.append(ActionData.make_play(hand_index, cell_index, instance_id))
	if owner_id == state.active_player and state.extra_card_plays_remaining > 0:
		return actions
	for source_cell: int in range(state.board.size()):
		var slot_value: Variant = state.board[source_cell]
		if not slot_value is Dictionary or int((slot_value as Dictionary).get("owner", 0)) != owner_id:
			continue
		var card: Dictionary = (slot_value as Dictionary).get("card", {})
		var instance_id := StringName(card.get("instance_id", &""))
		var abilities: Array[Dictionary] = Abilities.get_activate_abilities(
			card, state.get_enabled_effect_gates(owner_id)
		)
		for activation_index: int in range(abilities.size()):
			var activation: Dictionary = abilities[activation_index].get("activation", {}) as Dictionary
			if not Executor.can_pay_costs(
				state, source_cell, instance_id, activation.get("costs", []) as Array
			):
				continue
			for target: Dictionary in Targeting.get_valid_targets(
				state, owner_id, source_cell, activation
			):
				actions.append(ActionData.make_activate(
					source_cell,
					instance_id,
					StringName(target.get("kind", &"")),
					int(target.get("index", -1)),
					activation_index
				))
	return actions


static func has_legal_action_for_owner(state: StateData, owner_id: int) -> bool:
	if state == null or state.board.size() != 9:
		return false
	if not state.get_hand(owner_id).is_empty():
		for cell_index: int in range(9):
			if Rules.can_place(state.board, cell_index):
				return true
	if owner_id == state.active_player and state.extra_card_plays_remaining > 0:
		return false
	for source_cell: int in range(state.board.size()):
		var slot_value: Variant = state.board[source_cell]
		if not slot_value is Dictionary or int((slot_value as Dictionary).get("owner", 0)) != owner_id:
			continue
		var card: Dictionary = (slot_value as Dictionary).get("card", {})
		var instance_id := StringName(card.get("instance_id", &""))
		for entry: Dictionary in Abilities.get_activate_abilities(
			card, state.get_enabled_effect_gates(owner_id)
		):
			var activation: Dictionary = entry.get("activation", {}) as Dictionary
			if Executor.can_pay_costs(
				state, source_cell, instance_id, activation.get("costs", []) as Array
			) and not Targeting.get_valid_targets(
				state, owner_id, source_cell, activation
			).is_empty():
				return true
	return false


static func is_action_legal(state: StateData, action: ActionData) -> bool:
	if state == null or action == null:
		return false
	if action.action_type == ActionData.TYPE_PLAY:
		return _is_play_action_legal(state, action)
	if action.action_type == ActionData.TYPE_ACTIVATE:
		return state.extra_card_plays_remaining <= 0 and _is_activate_action_legal(state, action)
	return false


static func apply_action(state: StateData, action: ActionData) -> Dictionary:
	return NativeRules.apply_action(state, action) if is_action_legal(state, action) else _invalid_transition(state)


static func choose_greedy_action(state: StateData) -> ActionData:
	if state == null:
		return ActionData.new()
	var actions: Array[ActionData] = get_legal_actions(state)
	if actions.is_empty():
		return ActionData.new()
	var owner_id: int = state.active_player
	var best: ActionData = actions[0]
	var best_score: int = -1_000_000_000
	for action: ActionData in actions:
		var next_state: StateData = apply_action(state, action).get("state") as StateData
		var value: int = score_difference(next_state, owner_id)
		if value > best_score or value == best_score and _is_preferred_tie(state, action, best):
			best = action
			best_score = value
	return best.duplicate_action()


static func is_terminal(state: StateData) -> bool:
	if state == null:
		return true
	if not state.effect_queue.is_empty():
		return false
	if state.extra_card_plays_remaining > 0 and _owner_has_legal_hand_play(state, state.active_player):
		return false
	return (
		state.turn_count >= state.max_turns
		or _has_fivefold_board_repetition(state)
		or _board_is_full(state.board)
		or (
			not has_legal_action_for_owner(state, Rules.PLAYER_OWNER)
			and not has_legal_action_for_owner(state, Rules.OPPONENT_OWNER)
		)
	)


static func get_board_repetition_signature(board: Array) -> String:
	var cells: Array[String] = []
	for cell_index: int in range(9):
		if cell_index >= board.size() or board[cell_index] == null:
			cells.append("empty")
			continue
		var slot: Dictionary = board[cell_index] as Dictionary
		var card_id_bytes: PackedByteArray = String(
			(slot.get("card", {}) as Dictionary).get("card_id", &"")
		).to_utf8_buffer()
		cells.append("card:%d:%s:owner:%d" % [
			card_id_bytes.size(), card_id_bytes.hex_encode(), int(slot.get("owner", 0))
		])
	return "|".join(cells)


static func score_difference(state: StateData, owner_id: int) -> int:
	if state == null:
		return 0
	return Rules.count_owned(state.board, owner_id) - Rules.count_owned(state.board, other_owner(owner_id))


static func other_owner(owner_id: int) -> int:
	return Rules.OPPONENT_OWNER if owner_id == Rules.PLAYER_OWNER else Rules.PLAYER_OWNER


# Focused fixtures use these adapters, but resolution remains in the production native kernel.
static func resolve_non_attack_flip(
	state: StateData,
	target_instance_id: StringName,
	new_owner: int,
	reason: StringName = &"non_attack_flip"
) -> Dictionary:
	return NativeRules.resolve_non_attack_flip(state, target_instance_id, new_owner, reason)


static func _resolve_trigger_event(state: StateData, event_id: StringName, context: Dictionary) -> Dictionary:
	return NativeRules.resolve_event(state, event_id, context)


static func _resolve_before_move_request(state: StateData, request: Dictionary) -> Dictionary:
	return NativeRules.resolve_event(
		state, StringName(request.get("movement_event", &"card_before_moved")), request
	)


static func _resolve_attack_request(state: StateData, request: Dictionary) -> Dictionary:
	return NativeRules.resolve_attack(state, request)


static func _resolve_standard_attacks(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	reason: StringName,
	repeat_attack: bool = false,
	requested_policy: Dictionary = {}
) -> Dictionary:
	return NativeRules.resolve_attack(state, {
		"mode": &"standard",
		"source_cell": source_cell,
		"source_instance_id": source_instance_id,
		"source_owner_id": _board_owner_at(state, source_cell),
		"reason": reason,
		"repeat_attack": repeat_attack,
		"attack_policy": requested_policy,
	})


static func _resolve_attack_target(
	state: StateData,
	attacker_cell: int,
	attacker_instance_id: StringName,
	attacked_cell: int,
	attacked_instance_id: StringName,
	reason: StringName,
	attack_policy: Dictionary = {}
) -> Dictionary:
	return NativeRules.resolve_attack(state, {
		"mode": &"targeted",
		"source_cell": attacker_cell,
		"source_instance_id": attacker_instance_id,
		"source_owner_id": _board_owner_at(state, attacker_cell),
		"target_cell": attacked_cell,
		"target_instance_id": attacked_instance_id,
		"target_owner_id": _board_owner_at(state, attacked_cell),
		"reason": reason,
		"attack_policy": attack_policy,
	})


static func _board_owner_at(state: StateData, cell: int) -> int:
	if state == null or cell < 0 or cell >= state.board.size() or not state.board[cell] is Dictionary:
		return 0
	return int((state.board[cell] as Dictionary).get("owner", 0))


static func _is_play_action_legal(state: StateData, action: ActionData) -> bool:
	if action.source_zone != ActionData.SOURCE_HAND or action.target_kind != ActionData.TARGET_BOARD_CELL:
		return false
	var hand: Array = state.get_hand(state.active_player)
	if action.source_index < 0 or action.source_index >= hand.size():
		return false
	return (
		_matches_instance(hand[action.source_index] as Dictionary, action.source_instance_id)
		and Rules.can_place(state.board, action.target_index)
	)


static func _is_activate_action_legal(state: StateData, action: ActionData) -> bool:
	if action.source_zone != ActionData.SOURCE_BOARD or action.source_index < 0 or action.source_index >= state.board.size():
		return false
	var slot_value: Variant = state.board[action.source_index]
	if not slot_value is Dictionary or int((slot_value as Dictionary).get("owner", 0)) != state.active_player:
		return false
	var card: Dictionary = (slot_value as Dictionary).get("card", {})
	if not _matches_instance(card, action.source_instance_id):
		return false
	var activation: Dictionary = Abilities.get_activation(
		card, action.activation_index, state.get_enabled_effect_gates(state.active_player)
	)
	return (
		not activation.is_empty()
		and Executor.can_pay_costs(
			state, action.source_index, action.source_instance_id, activation.get("costs", []) as Array
		)
		and Targeting.is_target_valid(
			state,
			state.active_player,
			action.source_index,
			activation,
			action.target_kind,
			action.target_index
		)
	)


static func _owner_has_legal_hand_play(state: StateData, owner_id: int) -> bool:
	if state.get_hand(owner_id).is_empty():
		return false
	for cell_index: int in range(state.board.size()):
		if Rules.can_place(state.board, cell_index):
			return true
	return false


static func _has_fivefold_board_repetition(state: StateData) -> bool:
	var counts: Dictionary = {}
	for value: Variant in state.repetition_hashes:
		var signature := String(value)
		var count: int = int(counts.get(signature, 0)) + 1
		if count >= BOARD_REPETITION_LIMIT:
			return true
		counts[signature] = count
	return false


static func _board_is_full(board: Array) -> bool:
	return board.size() == 9 and not board.has(null)


static func _matches_instance(card: Dictionary, expected_instance_id: StringName) -> bool:
	return expected_instance_id == &"" or StringName(card.get("instance_id", &"")) == expected_instance_id


static func _is_preferred_tie(state: StateData, candidate: ActionData, incumbent: ActionData) -> bool:
	if candidate.action_type != incumbent.action_type:
		return candidate.action_type == ActionData.TYPE_PLAY
	if candidate.action_type == ActionData.TYPE_PLAY:
		var hand: Array = state.get_hand(state.active_player)
		var candidate_power: int = Rules.get_boundary_power(hand[candidate.source_index], candidate.target_index)
		var incumbent_power: int = Rules.get_boundary_power(hand[incumbent.source_index], incumbent.target_index)
		if candidate_power != incumbent_power:
			return candidate_power > incumbent_power
	if candidate.source_index != incumbent.source_index:
		return candidate.source_index < incumbent.source_index
	return candidate.target_index < incumbent.target_index


static func _invalid_transition(state: StateData) -> Dictionary:
	return {"valid": false, "state": state, "captures": [], "exiles": [], "events": []}
