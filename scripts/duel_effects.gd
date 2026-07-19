class_name DuelEffects
extends RefCounted

const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const StateData = preload("res://scripts/duel_state.gd")


static func resolve_flip_attempt(
	state: StateData,
	source_cell: int,
	target_cell: int,
	new_owner: int
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state == null or not _is_occupied_cell(state.board, source_cell) or not _is_occupied_cell(state.board, target_cell):
		return events
	var source_slot: Dictionary = state.board[source_cell]
	var target_slot: Dictionary = state.board[target_cell]
	if int(source_slot.get("owner", 0)) != new_owner or int(target_slot.get("owner", 0)) == new_owner:
		return events

	var source_card: Dictionary = source_slot["card"]
	if _has_active_effect(source_card, Catalog.EFFECT_EXILE_INSTEAD_OF_FLIP):
		return _resolve_exile(state, source_cell, target_cell, new_owner)
	return _resolve_normal_flip(state, source_cell, target_cell, new_owner)


static func _resolve_exile(
	state: StateData,
	source_cell: int,
	target_cell: int,
	new_owner: int
) -> Array[Dictionary]:
	var target_slot: Dictionary = state.board[target_cell]
	var target_card: Dictionary = target_slot["card"]
	var original_owner: int = int(target_card.get("original_owner", 0))
	if original_owner != Rules.PLAYER_OWNER and original_owner != Rules.OPPONENT_OWNER:
		original_owner = int(target_slot["owner"])
	if not state.removed_cards.has(original_owner):
		state.removed_cards[original_owner] = []
	var removed_zone: Array = state.removed_cards[original_owner]
	removed_zone.append(target_card)
	state.board[target_cell] = null
	return [
		{
			"type": &"card_exiled",
			"source_cell": source_cell,
			"target_cell": target_cell,
			"owner_id": new_owner,
			"original_owner": original_owner,
			"instance_id": StringName(target_card.get("instance_id", &"")),
		},
	]


static func _resolve_normal_flip(
	state: StateData,
	source_cell: int,
	target_cell: int,
	new_owner: int
) -> Array[Dictionary]:
	var target_slot: Dictionary = state.board[target_cell]
	var target_card: Dictionary = target_slot["card"]
	target_slot["owner"] = new_owner
	var events: Array[Dictionary] = [
		{
			"type": &"card_flipped",
			"source_cell": source_cell,
			"target_cell": target_cell,
			"owner_id": new_owner,
			"instance_id": StringName(target_card.get("instance_id", &"")),
		},
	]

	var retained_effects: Array = []
	var active_effects: Array = target_card.get("active_effects", [])
	for effect_value: Variant in active_effects:
		var effect: Dictionary = (effect_value as Dictionary).duplicate(true)
		if bool(effect.get("retained_on_flip", false)):
			retained_effects.append(effect)
			continue
		events.append(
			{
				"type": &"ability_lost",
				"source_cell": source_cell,
				"target_cell": target_cell,
				"owner_id": new_owner,
				"instance_id": StringName(target_card.get("instance_id", &"")),
				"effect_id": StringName(effect.get("id", &"")),
			}
		)
	target_card["active_effects"] = retained_effects
	return events


static func _has_active_effect(card: Dictionary, effect_id: StringName) -> bool:
	var active_effects: Array = card.get("active_effects", [])
	for effect_value: Variant in active_effects:
		var effect: Dictionary = effect_value
		if StringName(effect.get("id", &"")) == effect_id:
			return true
	return false


static func _is_occupied_cell(board: Array, cell_index: int) -> bool:
	return cell_index >= 0 and cell_index < board.size() and board[cell_index] != null
