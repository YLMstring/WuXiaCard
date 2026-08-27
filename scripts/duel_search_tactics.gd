class_name DuelSearchTactics
extends RefCounted

const Simulator = preload("res://scripts/duel_simulator.gd")
const StateData = preload("res://scripts/duel_state.gd")

const VOLATILE_EVENT_TYPES: Array[StringName] = [
	&"card_flipped",
	&"card_exiled",
	&"card_summoned",
	&"card_departed_for_resummon",
	&"card_returned_to_hand",
	&"extra_card_play_granted",
]


static func is_volatile(before_state: StateData, transition: Dictionary) -> bool:
	if before_state == null:
		return false
	var after_state: StateData = transition.get("state", null) as StateData
	if after_state == null:
		return false
	if not (transition.get("captures", []) as Array).is_empty():
		return true
	if not (transition.get("exiles", []) as Array).is_empty():
		return true
	if Simulator.is_terminal(after_state):
		return true
	for event_value: Variant in transition.get("events", []):
		var event: Dictionary = event_value as Dictionary
		if StringName(event.get("type", &"")) in VOLATILE_EVENT_TYPES:
			return true
	var owner_before: Dictionary = _board_owner_by_instance(before_state)
	var owner_after: Dictionary = _board_owner_by_instance(after_state)
	for instance_id: Variant in owner_before:
		if owner_after.has(instance_id) and int(owner_after[instance_id]) != int(owner_before[instance_id]):
			return true
	return false


static func _board_owner_by_instance(state: StateData) -> Dictionary:
	var owners: Dictionary = {}
	for slot_value: Variant in state.board:
		if slot_value == null:
			continue
		var slot: Dictionary = slot_value as Dictionary
		var card: Dictionary = slot.get("card", {}) as Dictionary
		var instance_id := StringName(card.get("instance_id", &""))
		if instance_id != &"":
			owners[instance_id] = int(slot.get("owner", 0))
	return owners
