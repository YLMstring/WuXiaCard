class_name DuelSearchSession
extends RefCounted

const ActionData = preload("res://scripts/duel_action.gd")
const Search = preload("res://scripts/duel_search.gd")
const StateData = preload("res://scripts/duel_state.gd")

var _thread: Thread = null
var _mutex: Mutex = Mutex.new()
var _cancel_requested: bool = false
var _complete: bool = false
var _joined: bool = false
var _progress: Dictionary = {}
var _result: Dictionary = {}


func start(
	state: StateData,
	root_owner: int,
	budget_seconds: float,
	greedy_fallback: ActionData,
	test_limits: Dictionary = {}
) -> bool:
	if state == null or greedy_fallback == null or _thread != null:
		return false
	var isolated_state: StateData = state.duplicate_state()
	var isolated_fallback: ActionData = greedy_fallback.duplicate_action()
	_mutex.lock()
	_cancel_requested = false
	_complete = false
	_joined = false
	_progress = {
		"elapsed_seconds": 0.0,
		"completed_depth": 0,
		"nodes": 0,
		"cutoffs": 0,
		"transposition_hits": 0,
		"generated_actions": 0,
		"applied_transitions": 0,
		"pvs_probes": 0,
		"pvs_researches": 0,
		"evaluation_cache_hits": 0,
		"max_tactical_depth": 0,
		"tactical_candidates_scanned": 0,
		"tactical_actions_searched": 0,
		"max_tactical_candidates_per_node": 0,
		"max_tactical_actions_per_node": 0,
		"turn_plan": [],
		"completion_reason": &"searching",
	}
	_result = {}
	_mutex.unlock()
	_thread = Thread.new()
	var error: Error = _thread.start(_run_worker.bind(
		isolated_state,
		root_owner,
		maxf(budget_seconds, 0.0),
		isolated_fallback,
		test_limits.duplicate(true)
	))
	if error != OK:
		_thread = null
		_publish_failure(isolated_fallback, &"thread_start_failed")
		return false
	return true


func get_progress() -> Dictionary:
	_mutex.lock()
	var copied: Dictionary = _progress.duplicate(true)
	_mutex.unlock()
	return copied


func is_complete() -> bool:
	_mutex.lock()
	var value: bool = _complete
	_mutex.unlock()
	return value


func is_running() -> bool:
	return _thread != null and not is_complete()


func cancel() -> void:
	_mutex.lock()
	_cancel_requested = true
	_mutex.unlock()


func finish_and_get_result() -> Dictionary:
	if _thread != null and not _joined:
		_thread.wait_to_finish()
		_joined = true
	_mutex.lock()
	var copied: Dictionary = _copy_result(_result)
	_mutex.unlock()
	return copied


func cancel_and_join() -> Dictionary:
	cancel()
	return finish_and_get_result()


func _run_worker(
	state: StateData,
	root_owner: int,
	budget_seconds: float,
	greedy_fallback: ActionData,
	test_limits: Dictionary
) -> void:
	if bool(test_limits.get("force_failure", false)):
		_publish_failure(greedy_fallback, &"worker_failed")
		return
	var limits: Dictionary = test_limits.duplicate(true)
	if budget_seconds > 0.0:
		limits["deadline_usec"] = Time.get_ticks_usec() + int(budget_seconds * 1_000_000.0)
	elif not limits.has("max_depth") and not limits.has("max_nodes"):
		limits["max_nodes"] = 1
	var search_result: Dictionary = Search.find_best_action_iterative(
		state,
		root_owner,
		limits,
		Callable(self, "_is_cancel_requested"),
		Callable(self, "_publish_progress")
	)
	var has_completed_depth: bool = bool(search_result.get("has_completed_depth", false))
	var selected_action: ActionData = search_result.get("action", null) as ActionData
	var use_fallback: bool = not has_completed_depth or selected_action == null or selected_action.action_type == &""
	if use_fallback:
		selected_action = greedy_fallback.duplicate_action()
		search_result["turn_plan"] = []
	search_result["action"] = selected_action.duplicate_action()
	search_result["used_fallback"] = use_fallback
	_publish_final(search_result)


func _is_cancel_requested() -> bool:
	_mutex.lock()
	var value: bool = _cancel_requested
	_mutex.unlock()
	return value


func _publish_progress(progress: Dictionary) -> void:
	_mutex.lock()
	_progress = _copy_result(progress)
	_mutex.unlock()


func _publish_final(result: Dictionary) -> void:
	_mutex.lock()
	_result = _copy_result(result)
	_progress = _copy_result(result)
	_complete = true
	_mutex.unlock()


func _publish_failure(fallback: ActionData, reason: StringName) -> void:
	_publish_final({
		"action": fallback.duplicate_action(),
		"score": 0,
		"completed_depth": 0,
		"nodes": 0,
		"cutoffs": 0,
		"transposition_hits": 0,
		"generated_actions": 0,
		"applied_transitions": 0,
		"pvs_probes": 0,
		"pvs_researches": 0,
		"evaluation_cache_hits": 0,
		"max_tactical_depth": 0,
		"tactical_candidates_scanned": 0,
		"tactical_actions_searched": 0,
		"max_tactical_candidates_per_node": 0,
		"max_tactical_actions_per_node": 0,
		"elapsed_seconds": 0.0,
		"solved": false,
		"completion_reason": reason,
		"has_completed_depth": false,
		"used_fallback": true,
		"turn_plan": [],
	})


func _copy_result(source: Dictionary) -> Dictionary:
	var copied: Dictionary = source.duplicate(true)
	var action: ActionData = source.get("action", null) as ActionData
	if action != null:
		copied["action"] = action.duplicate_action()
	var copied_plan: Array[Dictionary] = []
	for entry_value: Variant in source.get("turn_plan", []):
		if not entry_value is Dictionary:
			continue
		var source_entry: Dictionary = entry_value as Dictionary
		var copied_entry: Dictionary = source_entry.duplicate(true)
		var planned_action: ActionData = source_entry.get("action", null) as ActionData
		if planned_action != null:
			copied_entry["action"] = planned_action.duplicate_action()
		copied_plan.append(copied_entry)
	copied["turn_plan"] = copied_plan
	return copied
