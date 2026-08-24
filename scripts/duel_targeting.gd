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
	if target_rule not in Catalog.KNOWN_TARGET_RULES:
		return targets
	if target_rule in [Catalog.TARGET_ENEMY_HAND_CARD, Catalog.TARGET_ALLY_HAND_CARD]:
		var target_owner: int = owner_id
		if target_rule == Catalog.TARGET_ENEMY_HAND_CARD:
			target_owner = (
			Rules.OPPONENT_OWNER
			if owner_id == Rules.PLAYER_OWNER
			else Rules.PLAYER_OWNER
		)
		var target_hand: Array = state.get_hand(target_owner)
		for hand_index: int in range(target_hand.size()):
			if target_hand[hand_index] is Dictionary:
				targets.append({
					"kind": ActionData.TARGET_HAND_SLOT,
					"index": hand_index,
				})
		return targets
	if target_rule == Catalog.TARGET_OTHER_ALLY_BOARD:
		for target_cell: int in range(state.board.size()):
			if target_cell == source_cell:
				continue
			if _matches_target_rule(state, owner_id, target_cell, target_rule):
				targets.append({
					"kind": ActionData.TARGET_BOARD_CELL,
					"index": target_cell,
				})
		return targets
	if target_rule in [Catalog.TARGET_ANY_EMPTY_BOARD, Catalog.TARGET_ANY_ENEMY_BOARD]:
		for target_cell: int in range(state.board.size()):
			if _matches_target_rule(state, owner_id, target_cell, target_rule):
				targets.append({
					"kind": ActionData.TARGET_BOARD_CELL,
					"index": target_cell,
				})
		return targets
	for direction: int in range(4):
		var target_cell: int = Rules.get_neighbor_index(source_cell, direction)
		if _matches_target_rule(state, owner_id, target_cell, target_rule):
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


static func _matches_target_rule(
	state: StateData,
	owner_id: int,
	target_cell: int,
	target_rule: StringName
) -> bool:
	if target_cell < 0 or target_cell >= state.board.size():
		return false
	if target_rule in [Catalog.TARGET_ADJACENT_EMPTY_BOARD, Catalog.TARGET_ANY_EMPTY_BOARD]:
		return Rules.can_place(state.board, target_cell)
	var target_slot_value: Variant = state.board[target_cell]
	if target_slot_value == null:
		return false
	var target_owner: int = int((target_slot_value as Dictionary).get("owner", 0))
	if target_rule == Catalog.TARGET_ADJACENT_ALLY_BOARD:
		return target_owner == owner_id
	if target_rule == Catalog.TARGET_OTHER_ALLY_BOARD:
		return target_owner == owner_id
	if target_rule == Catalog.TARGET_ADJACENT_ENEMY_BOARD:
		return target_owner != owner_id
	if target_rule == Catalog.TARGET_ANY_ENEMY_BOARD:
		return target_owner != owner_id
	return false
