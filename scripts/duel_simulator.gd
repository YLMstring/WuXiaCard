class_name DuelSimulator
extends RefCounted

const ActionData = preload("res://scripts/duel_action.gd")
const NativeRules = preload("res://scripts/duel_native_rules.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const StateData = preload("res://scripts/duel_state.gd")

const MAX_ATTACKS_PER_OWNER_TURN: int = 20


static func get_legal_actions(state: StateData) -> Array[ActionData]:
	return [] if state == null else get_legal_actions_for_owner(state, state.active_player)


static func get_legal_actions_for_owner(state: StateData, owner_id: int) -> Array[ActionData]:
	return NativeRules.get_legal_actions_for_owner(state, owner_id)


static func has_legal_action_for_owner(state: StateData, owner_id: int) -> bool:
	return NativeRules.count_legal_actions_for_owner(state, owner_id) > 0


static func is_action_legal(state: StateData, action: ActionData) -> bool:
	return (
		state != null
		and NativeRules.is_action_legal_for_owner(state, action, state.active_player)
	)


static func apply_action(state: StateData, action: ActionData) -> Dictionary:
	return NativeRules.apply_action(state, action)


static func choose_greedy_action(state: StateData) -> ActionData:
	return ActionData.new() if state == null else NativeRules.choose_greedy_action(
		state,
		state.active_player
	)


static func is_terminal(state: StateData) -> bool:
	return NativeRules.is_terminal(state)


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
	return NativeRules.score_difference(state, owner_id)


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
