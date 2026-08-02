class_name DuelReplayRecord
extends RefCounted

const StateData = preload("res://scripts/duel_state.gd")
const ActionData = preload("res://scripts/duel_action.gd")

const VALID_OUTCOMES: Array[StringName] = [
	&"victory",
	&"defeat",
]

var _initial_state: StateData = null
var _actions: Array[ActionData] = []
var _final_state: StateData = null
var _outcome: StringName = &""
var _final_status: String = ""


func begin(state: StateData) -> void:
	_initial_state = state.duplicate_state() as StateData if state != null else null
	_actions.clear()
	_final_state = null
	_outcome = &""
	_final_status = ""


func record_action(action: ActionData) -> void:
	if _initial_state == null or action == null:
		return
	_actions.append(action.duplicate_action() as ActionData)


func complete(state: StateData, outcome: StringName, final_status: String) -> void:
	_final_state = state.duplicate_state() as StateData if state != null else null
	_outcome = outcome
	_final_status = final_status


func is_ready() -> bool:
	return (
		_initial_state != null
		and not _actions.is_empty()
		and _final_state != null
		and _outcome in VALID_OUTCOMES
	)


func get_initial_state() -> StateData:
	return _initial_state.duplicate_state() as StateData if _initial_state != null else null


func get_actions() -> Array[ActionData]:
	var result: Array[ActionData] = []
	for action: ActionData in _actions:
		result.append(action.duplicate_action() as ActionData)
	return result


func get_final_state() -> StateData:
	return _final_state.duplicate_state() as StateData if _final_state != null else null


func get_outcome() -> StringName:
	return _outcome


func get_final_status() -> String:
	return _final_status
