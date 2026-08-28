class_name DuelTurnPlan
extends RefCounted

const ActionData = preload("res://scripts/duel_action.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const StateData = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")


static func remaining_after_selected_action(
	source_plan: Array,
	state: StateData,
	selected_action: ActionData,
	used_fallback: bool
) -> Array[Dictionary]:
	if used_fallback or state == null or selected_action == null or source_plan.is_empty():
		return []
	var first_entry: Dictionary = source_plan[0] as Dictionary
	if not _entry_matches_state(first_entry, state, state.active_player):
		return []
	var first_action: ActionData = first_entry.get("action", null) as ActionData
	if first_action == null or not first_action.is_same_as(selected_action):
		return []
	return copy_entries(source_plan.slice(1))


static func take_next(
	source_plan: Array,
	state: StateData,
	expected_owner: int
) -> Dictionary:
	if source_plan.is_empty() or state == null:
		return {"matched": false, "action": null, "remaining_plan": []}
	var first_entry: Dictionary = source_plan[0] as Dictionary
	if not _entry_matches_state(first_entry, state, expected_owner):
		return {"matched": false, "action": null, "remaining_plan": []}
	var action: ActionData = first_entry.get("action", null) as ActionData
	if action == null or not Simulator.is_action_legal(state, action):
		return {"matched": false, "action": null, "remaining_plan": []}
	return {
		"matched": true,
		"action": action.duplicate_action(),
		"remaining_plan": copy_entries(source_plan.slice(1)),
	}


static func copy_entries(source_plan: Array) -> Array[Dictionary]:
	var copied: Array[Dictionary] = []
	for entry_value: Variant in source_plan:
		if not entry_value is Dictionary:
			continue
		var source_entry: Dictionary = entry_value as Dictionary
		var entry: Dictionary = source_entry.duplicate(true)
		var action: ActionData = source_entry.get("action", null) as ActionData
		if action != null:
			entry["action"] = action.duplicate_action()
		copied.append(entry)
	return copied


static func _entry_matches_state(
	entry: Dictionary,
	state: StateData,
	expected_owner: int
) -> bool:
	if state.active_player != expected_owner:
		return false
	if int(entry.get("owner_id", 0)) != expected_owner:
		return false
	if int(entry.get("owner_turn_serial", -1)) != state.owner_turn_serial:
		return false
	return String(entry.get("state_key", "")) == StateKey.build_compact(state)
