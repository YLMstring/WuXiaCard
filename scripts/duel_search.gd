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
	var native_progress_callback: Callable = Callable()
	if on_progress.is_valid():
		native_progress_callback = func(snapshot: Dictionary) -> void:
			var progress: Dictionary = {
				"action": snapshot.get("action", ActionData.new()),
				"score": int(snapshot.get("score", 0)),
				"completed_depth": int(snapshot.get("depth", 0)),
				"owner_turn_boundaries": int(snapshot.get("owner_turn_boundaries", 0)),
				"nodes": int(snapshot.get("nodes", 0)),
				"generated_actions": int(snapshot.get("generated_actions", 0)),
				"applied_transitions": int(snapshot.get("applied_transitions", 0)),
				"cutoffs": int(snapshot.get("cutoffs", 0)),
				"time_legal_actions_usec": int(snapshot.get("time_legal_actions_usec", 0)),
				"time_order_usec": int(snapshot.get("time_order_usec", 0)),
				"time_apply_usec": int(snapshot.get("time_apply_usec", 0)),
				"time_evaluate_usec": int(snapshot.get("time_evaluate_usec", 0)),
				"time_key_usec": int(snapshot.get("time_key_usec", 0)),
				"ordered_nodes": int(snapshot.get("ordered_nodes", 0)),
				"visited_children": int(snapshot.get("visited_children", 0)),
				"cutoff_first_child": int(snapshot.get("cutoff_first_child", 0)),
				"cutoff_second_child": int(snapshot.get("cutoff_second_child", 0)),
				"cutoff_third_fourth_child": int(snapshot.get("cutoff_third_fourth_child", 0)),
				"cutoff_fifth_eighth_child": int(snapshot.get("cutoff_fifth_eighth_child", 0)),
				"cutoff_ninth_or_later_child": int(snapshot.get("cutoff_ninth_or_later_child", 0)),
				"pv_queries": int(snapshot.get("pv_queries", 0)),
				"pv_hits": int(snapshot.get("pv_hits", 0)),
				"pv_legal_hits": int(snapshot.get("pv_legal_hits", 0)),
				"pv_illegal_hits": int(snapshot.get("pv_illegal_hits", 0)),
				"history_queries": int(snapshot.get("history_queries", 0)),
				"history_hits": int(snapshot.get("history_hits", 0)),
				"history_cutoffs": int(snapshot.get("history_cutoffs", 0)),
				"transposition_probes": int(snapshot.get("transposition_probes", 0)),
				"transposition_hits": int(snapshot.get("transposition_hits", 0)),
				"transposition_completed_hits": int(snapshot.get("transposition_completed_hits", 0)),
				"transposition_leaf_probes": int(snapshot.get("transposition_leaf_probes", 0)),
				"transposition_leaf_completed_hits": int(snapshot.get("transposition_leaf_completed_hits", 0)),
				"transposition_internal_probes": int(snapshot.get("transposition_internal_probes", 0)),
				"transposition_internal_completed_hits": int(snapshot.get("transposition_internal_completed_hits", 0)),
				"transposition_state_hits": int(snapshot.get("transposition_state_hits", 0)),
				"transposition_unique_keys": int(snapshot.get("transposition_unique_keys", 0)),
				"transposition_completed_keys": int(snapshot.get("transposition_completed_keys", 0)),
				"transposition_unique_states": int(snapshot.get("transposition_unique_states", 0)),
				"transposition_table_probes": int(snapshot.get("transposition_table_probes", 0)),
				"transposition_table_hits": int(snapshot.get("transposition_table_hits", 0)),
				"transposition_exact_hits": int(snapshot.get("transposition_exact_hits", 0)),
				"transposition_bound_hits": int(snapshot.get("transposition_bound_hits", 0)),
				"transposition_exact_returns": int(snapshot.get("transposition_exact_returns", 0)),
				"transposition_bound_cutoffs": int(snapshot.get("transposition_bound_cutoffs", 0)),
				"transposition_stores": int(snapshot.get("transposition_stores", 0)),
				"transposition_updates": int(snapshot.get("transposition_updates", 0)),
				"transposition_replacements": int(snapshot.get("transposition_replacements", 0)),
				"transposition_collisions": int(snapshot.get("transposition_collisions", 0)),
				"transposition_move_queries": int(snapshot.get("transposition_move_queries", 0)),
				"transposition_move_legal_hits": int(snapshot.get("transposition_move_legal_hits", 0)),
				"transposition_move_illegal_hits": int(snapshot.get("transposition_move_illegal_hits", 0)),
				"transposition_table_enabled": bool(snapshot.get("transposition_table_enabled", false)),
				"transposition_table_requested_mib": int(snapshot.get("transposition_table_requested_mib", 0)),
				"transposition_table_entry_size_bytes": int(snapshot.get("transposition_table_entry_size_bytes", 0)),
				"transposition_table_set_count": int(snapshot.get("transposition_table_set_count", 0)),
				"transposition_table_slot_count": int(snapshot.get("transposition_table_slot_count", 0)),
				"transposition_table_capacity_bytes": int(snapshot.get("transposition_table_capacity_bytes", 0)),
				"transposition_table_allocation_fallback": bool(snapshot.get("transposition_table_allocation_fallback", false)),
				"elapsed_seconds": float(snapshot.get("elapsed_usec", 0)) / 1_000_000.0,
				"completion_reason": &"searching",
			}
			on_progress.call(progress)
	var result: Dictionary = NativeRules.search_iterative(
		state,
		root_owner,
		native_limits,
		should_cancel,
		native_progress_callback
	)
	result = _native_result_schema(result, native_limits, profile, started_usec)
	var action: ActionData = result.get("action", null) as ActionData
	if bool(result.get("has_completed_depth", false)) and action != null:
		result["turn_plan"] = _build_native_turn_plan(
			state, result.get("principal_actions", []) as Array
		)
	return result


static func find_best_action_iterative(
	state: StateData,
	root_owner: int = -1,
	limits: Dictionary = {},
	should_cancel: Callable = Callable(),
	on_progress: Callable = Callable()
) -> Dictionary:
	var production_limits: Dictionary = limits.duplicate(true)
	if not production_limits.has("use_internal_pv_ordering"):
		production_limits["use_internal_pv_ordering"] = true
	if not production_limits.has("use_history_ordering"):
		production_limits["use_history_ordering"] = true
	if not production_limits.has("use_transposition_table"):
		production_limits["use_transposition_table"] = true
	if not production_limits.has("transposition_table_mib"):
		production_limits["transposition_table_mib"] = 8
	return find_best_action_iterative_native(
		state, root_owner, production_limits, should_cancel, on_progress
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
	result["depth_mode"] = StringName(source.get(
		"depth_mode",
		limits.get("depth_mode", &"complete_round")
	))
	result["owner_turn_boundaries"] = int(source.get("owner_turn_boundaries", 0))
	result["nodes"] = int(source.get("nodes", 0))
	result["min_completed_depth"] = maxi(int(limits.get("min_completed_depth", 0)), 0)
	result["minimum_depth_guard_used"] = bool(source.get("minimum_depth_guard_used", false))
	var max_nodes: int = maxi(int(limits.get("max_nodes", 0)), 0)
	result["nodes_over_limit"] = maxi(int(result["nodes"]) - max_nodes, 0) if max_nodes > 0 else 0
	for field: String in [
		"cutoffs", "generated_actions", "applied_transitions",
		"root_actions_total", "root_actions_started", "root_actions_completed",
		"time_legal_actions_usec", "time_order_usec", "time_apply_usec",
		"time_key_usec", "time_evaluate_usec", "ordered_nodes", "visited_children",
		"cutoff_first_child", "cutoff_second_child", "cutoff_third_fourth_child",
		"cutoff_fifth_eighth_child", "cutoff_ninth_or_later_child",
		"pv_queries", "pv_hits", "pv_legal_hits", "pv_illegal_hits",
		"history_queries", "history_hits", "history_cutoffs",
		"transposition_probes", "transposition_hits", "transposition_completed_hits",
		"transposition_leaf_probes", "transposition_leaf_completed_hits",
		"transposition_internal_probes", "transposition_internal_completed_hits",
		"transposition_state_hits", "transposition_unique_keys",
		"transposition_completed_keys", "transposition_unique_states",
		"transposition_table_probes", "transposition_table_hits",
		"transposition_exact_hits", "transposition_bound_hits",
		"transposition_exact_returns", "transposition_bound_cutoffs",
		"transposition_stores", "transposition_updates",
		"transposition_replacements", "transposition_collisions",
		"transposition_move_queries", "transposition_move_legal_hits",
		"transposition_move_illegal_hits",
	]:
		result[field] = int(source.get(field, 0))
	for field: String in [
		"pvs_probes", "pvs_researches", "evaluation_cache_hits",
		"iteration_nodes", "current_root_action_nodes", "max_tactical_depth",
		"tactical_candidates_scanned", "tactical_actions_searched",
		"max_tactical_candidates_per_node", "max_tactical_actions_per_node",
	]:
		result[field] = 0
	result["internal_pv_ordering_enabled"] = bool(source.get(
		"internal_pv_ordering_enabled",
		limits.get("use_internal_pv_ordering", false)
	))
	result["history_ordering_enabled"] = bool(source.get(
		"history_ordering_enabled",
		limits.get("use_history_ordering", false)
	))
	result["transposition_table_enabled"] = bool(source.get(
		"transposition_table_enabled",
		false
	))
	result["transposition_table_requested_mib"] = int(source.get(
		"transposition_table_requested_mib",
		limits.get("transposition_table_mib", 0)
	))
	result["transposition_table_entry_size_bytes"] = int(source.get(
		"transposition_table_entry_size_bytes", 0
	))
	result["transposition_table_set_count"] = int(source.get(
		"transposition_table_set_count", 0
	))
	result["transposition_table_slot_count"] = int(source.get(
		"transposition_table_slot_count", 0
	))
	result["transposition_table_capacity_bytes"] = int(source.get(
		"transposition_table_capacity_bytes", 0
	))
	result["transposition_table_allocation_fallback"] = bool(source.get(
		"transposition_table_allocation_fallback", false
	))
	result["search_diagnostics_enabled"] = bool(source.get(
		"search_diagnostics_enabled",
		limits.get("collect_search_diagnostics", limits.get("collect_timings", false))
	))
	result["iteration_depth"] = int(source.get("iteration_depth", source.get("completed_depth", 0)))
	result["turn_plan"] = []
	result["search_profile"] = StringName(profile.get("name", Profile.ENHANCED))
	result["elapsed_seconds"] = float(Time.get_ticks_usec() - started_usec) / 1_000_000.0
	result["solved"] = bool(source.get("solved", false))
	result["completion_reason"] = StringName(source.get("completion_reason", &"max_depth"))
	result["has_completed_depth"] = bool(source.get("has_completed_depth", false))
	return result
