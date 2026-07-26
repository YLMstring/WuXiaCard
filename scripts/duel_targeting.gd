class_name DuelTargeting
extends RefCounted

const ActionData = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const StateData = preload("res://scripts/duel_state.gd")


static func get_valid_targets(
	state: StateData,
	owner_id: int,
	source_cell: int,
	activation: Dictionary
) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	if not _has_owned_source(state, owner_id, source_cell):
		return targets
	var target_rule := StringName(activation.get("target_rule", &""))
	if target_rule != Catalog.TARGET_ADJACENT_EMPTY_BOARD:
		return targets
	for direction: int in range(4):
		var target_cell: int = Rules.get_neighbor_index(source_cell, direction)
		if Rules.can_place(state.board, target_cell):
			targets.append({
				"kind": ActionData.TARGET_BOARD_CELL,
				"index": target_cell,
			})
	return targets


static func is_target_valid(
	state: StateData,
	owner_id: int,
	source_cell: int,
	activation: Dictionary,
	target_kind: StringName,
	target_index: int
) -> bool:
	for target: Dictionary in get_valid_targets(state, owner_id, source_cell, activation):
		if StringName(target.get("kind", &"")) == target_kind and int(target.get("index", -1)) == target_index:
			return true
	return false


static func _has_owned_source(state: StateData, owner_id: int, source_cell: int) -> bool:
	if state == null or source_cell < 0 or source_cell >= state.board.size():
		return false
	var source_slot: Variant = state.board[source_cell]
	return source_slot != null and int((source_slot as Dictionary).get("owner", 0)) == owner_id
