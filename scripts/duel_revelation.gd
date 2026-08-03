class_name DuelRevelation
extends RefCounted

const Rules = preload("res://scripts/duel_rules.gd")
const StateData = preload("res://scripts/duel_state.gd")


static func is_revealed_to(card: Dictionary, observer_owner_id: int) -> bool:
	return observer_owner_id in (card.get("revealed_to_owner_ids", []) as Array)


static func reveal_to(card: Dictionary, observer_owner_id: int) -> bool:
	if observer_owner_id not in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		return false
	var audiences: Array = card.get("revealed_to_owner_ids", [])
	if observer_owner_id in audiences:
		return false
	audiences = audiences.duplicate()
	audiences.append(observer_owner_id)
	card["revealed_to_owner_ids"] = audiences
	return true


static func get_remembered_glyphs(state: StateData, observer_owner_id: int) -> Array:
	if state == null:
		return []
	return (state.remembered_glyphs_by_owner.get(observer_owner_id, []) as Array).duplicate()


static func enable_future_draw_reveal(
	state: StateData,
	hand_owner_id: int,
	observer_owner_id: int
) -> bool:
	if state == null:
		return false
	var audiences: Array = state.future_draw_reveal_audiences.get(hand_owner_id, [])
	if observer_owner_id in audiences:
		return false
	audiences = audiences.duplicate()
	audiences.append(observer_owner_id)
	state.future_draw_reveal_audiences[hand_owner_id] = audiences
	return true


static func get_future_draw_audiences(state: StateData, hand_owner_id: int) -> Array:
	if state == null:
		return []
	return (state.future_draw_reveal_audiences.get(hand_owner_id, []) as Array).duplicate()
