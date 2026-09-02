class_name DuelSearch
extends RefCounted

const ActionData = preload("res://scripts/duel_action.gd")
const NativeRules = preload("res://scripts/duel_native_rules.gd")
const Profile = preload("res://scripts/duel_search_profile.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const StateData = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")


static func find_best_action(
	state: StateData,
	max_depth: int,
	root_owner: int = -1
) -> ActionData:
	var result: Dictionary = find_best_action_iterative(
		state,
		root_owner,
		{"max_depth": maxi(max_depth, 1)}
	)
	var action: ActionData = result.get("action", null) as ActionData
	return action.duplicate_action() if action != null else ActionData.new()


static func find_best_action_iterative_native(
	state: StateData,
	root_owner: int = -1,
	limits: Dictionary = {},
	should_cancel: Callable = Callable(),
	on_progress: Callable = Callable()
) -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	var profile: Dictionary = Profile.normalize(limits)
	if state == null:
		return _native_result_schema({
			"action": ActionData.new(),
			"completion_reason": &"no_legal_action",
			"has_completed_depth": false,
		}, limits, profile, started_usec)
	if root_owner < 0:
		root_owner = state.active_player
	if should_cancel.is_valid() and bool(should_cancel.call()):
		return _native_result_schema({
			"action": ActionData.new(),
			"completion_reason": &"cancelled",
			"has_completed_depth": false,
		}, limits, profile, started_usec)
	var native_limits: Dictionary = limits.duplicate(true)
	if int(native_limits.get("deadline_usec", 0)) <= 0 and float(native_limits.get("budget_seconds", 0.0)) > 0.0:
		native_limits["deadline_usec"] = started_usec + int(
			float(native_limits["budget_seconds"]) * 1_000_000.0
		)
	var result: Dictionary = NativeRules.search_iterative(
		state, root_owner, native_limits, should_cancel
	)
	result = _native_result_schema(result, native_limits, profile, started_usec)
	var action: ActionData = result.get("action", null) as ActionData
	if bool(result.get("has_completed_depth", false)) and action != null:
		result["turn_plan"] = _build_native_turn_plan(
			state, result.get("principal_actions", []) as Array
		)
	if on_progress.is_valid():
		for snapshot_value: Variant in result.get("depth_snapshots", []):
			if not snapshot_value is Dictionary:
				continue
			var snapshot: Dictionary = snapshot_value as Dictionary
			var progress: Dictionary = result.duplicate(true)
			var snapshot_action: ActionData = snapshot.get("action", null) as ActionData
			progress["action"] = snapshot_action.duplicate_action() if snapshot_action != null else ActionData.new()
			progress["score"] = int(snapshot.get("score", 0))
			progress["completed_depth"] = int(snapshot.get("depth", 0))
			progress["nodes"] = int(snapshot.get("nodes", 0))
			progress["generated_actions"] = int(snapshot.get("generated_actions", 0))
			progress["applied_transitions"] = int(snapshot.get("applied_transitions", 0))
			progress["cutoffs"] = int(snapshot.get("cutoffs", 0))
			progress["elapsed_seconds"] = float(snapshot.get("elapsed_usec", 0)) / 1_000_000.0
			progress["completion_reason"] = &"searching"
			on_progress.call(progress)
	return result


static func find_best_action_iterative(
	state: StateData,
	root_owner: int = -1,
	limits: Dictionary = {},
	should_cancel: Callable = Callable(),
	on_progress: Callable = Callable()
) -> Dictionary:
	return find_best_action_iterative_native(
		state, root_owner, limits, should_cancel, on_progress
	)


static func _build_native_turn_plan(state: StateData, planned_actions: Array) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	if state == null or planned_actions.is_empty():
		return plan
	var current_state: StateData = state.duplicate_state()
	var root_owner: int = current_state.active_player
	var root_serial: int = current_state.owner_turn_serial
	for value: Variant in planned_actions:
		var action: ActionData = value as ActionData
		if (
			action == null
			or current_state.active_player != root_owner
			or current_state.owner_turn_serial != root_serial
			or not Simulator.is_action_legal(current_state, action)
		):
			break
		plan.append({
			"state_key": StateKey.build_compact(current_state),
			"owner_turn_serial": root_serial,
			"owner_id": root_owner,
			"action": action.duplicate_action(),
		})
		var transition: Dictionary = Simulator.apply_action(current_state, action)
		if not bool(transition.get("valid", false)):
			break
		current_state = transition.get("state") as StateData
		if current_state == null or Simulator.is_terminal(current_state):
			break
	return plan


static func _native_result_schema(
	source: Dictionary,
	limits: Dictionary,
	profile: Dictionary,
	started_usec: int
) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	var action: ActionData = source.get("action", null) as ActionData
	result["action"] = action.duplicate_action() if action != null else ActionData.new()
	result["completed_depth"] = int(source.get("completed_depth", 0))
	result["nodes"] = int(source.get("nodes", 0))
	result["min_completed_depth"] = maxi(int(limits.get("min_completed_depth", 0)), 0)
	result["minimum_depth_guard_used"] = bool(source.get("minimum_depth_guard_used", false))
	var max_nodes: int = maxi(int(limits.get("max_nodes", 0)), 0)
	result["nodes_over_limit"] = maxi(int(result["nodes"]) - max_nodes, 0) if max_nodes > 0 else 0
	for field: String in [
		"cutoffs", "generated_actions", "applied_transitions",
		"root_actions_total", "root_actions_started", "root_actions_completed",
	]:
		result[field] = int(source.get(field, 0))
	for field: String in [
		"transposition_hits", "pvs_probes", "pvs_researches", "evaluation_cache_hits",
		"iteration_nodes", "current_root_action_nodes", "time_order_usec", "time_apply_usec",
		"time_key_usec", "time_evaluate_usec", "max_tactical_depth",
		"tactical_candidates_scanned", "tactical_actions_searched",
		"max_tactical_candidates_per_node", "max_tactical_actions_per_node",
	]:
		result[field] = 0
	result["iteration_depth"] = int(source.get("iteration_depth", source.get("completed_depth", 0)))
	result["turn_plan"] = []
	result["search_profile"] = StringName(profile.get("name", Profile.ENHANCED))
	result["elapsed_seconds"] = float(Time.get_ticks_usec() - started_usec) / 1_000_000.0
	result["solved"] = bool(source.get("solved", false))
	result["completion_reason"] = StringName(source.get("completion_reason", &"max_depth"))
	result["has_completed_depth"] = bool(source.get("has_completed_depth", false))
	return result
