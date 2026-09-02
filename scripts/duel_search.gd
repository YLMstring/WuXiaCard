class_name DuelSearch
extends RefCounted

const WIN_SCORE: int = 1_000_000
const INFINITY: int = 1_000_000_000
const MAX_TRANSPOSITION_ENTRIES: int = 50_000

const ActionData = preload("res://scripts/duel_action.gd")
const EvaluationCache = preload("res://scripts/duel_evaluation_cache.gd")
const Evaluator = preload("res://scripts/duel_evaluator.gd")
const NativeRules = preload("res://scripts/duel_native_rules.gd")
const Profile = preload("res://scripts/duel_search_profile.gd")
const Ordering = preload("res://scripts/duel_search_ordering.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const Tactics = preload("res://scripts/duel_search_tactics.gd")
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
		{"max_depth": maxi(max_depth, 1)},
		Callable(),
		Callable()
	)
	var action: ActionData = result.get("action", null) as ActionData
	return action.duplicate_action() if action != null else ActionData.new()


static func find_best_action_oracle(
	state: StateData,
	max_depth: int,
	root_owner: int = -1
) -> ActionData:
	var result: Dictionary = find_best_action_iterative_oracle(
		state,
		root_owner,
		{"max_depth": maxi(max_depth, 1)}
	)
	var action: ActionData = result.get("action", null) as ActionData
	return action.duplicate_action() if action != null else ActionData.new()


static func find_best_action_iterative_oracle(
	state: StateData,
	root_owner: int = -1,
	limits: Dictionary = {},
	should_cancel: Callable = Callable(),
	on_progress: Callable = Callable()
) -> Dictionary:
	var oracle_limits: Dictionary = limits.duplicate(true)
	oracle_limits["_oracle_test_backend"] = true
	return find_best_action_iterative(
		state,
		root_owner,
		oracle_limits,
		should_cancel,
		on_progress
	)


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
	if (
		int(native_limits.get("deadline_usec", 0)) <= 0
		and float(native_limits.get("budget_seconds", 0.0)) > 0.0
	):
		native_limits["deadline_usec"] = (
			started_usec + int(float(native_limits["budget_seconds"]) * 1_000_000.0)
		)
	var result: Dictionary = NativeRules.search_iterative(
		state,
		root_owner,
		native_limits,
		should_cancel
	)
	result = _native_result_schema(result, native_limits, profile, started_usec)
	var action: ActionData = result.get("action", null) as ActionData
	if bool(result.get("has_completed_depth", false)) and action != null:
		result["turn_plan"] = _build_native_turn_plan(
			state,
			result.get("principal_actions", []) as Array
		)
	if on_progress.is_valid():
		for snapshot_value: Variant in result.get("depth_snapshots", []):
			if not snapshot_value is Dictionary:
				continue
			var snapshot: Dictionary = snapshot_value as Dictionary
			var progress: Dictionary = result.duplicate(true)
			progress["action"] = (snapshot.get("action") as ActionData).duplicate_action()
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
	if not bool(limits.get("_oracle_test_backend", false)):
		return find_best_action_iterative_native(
			state,
			root_owner,
			limits,
			should_cancel,
			on_progress
		)
	var started_usec: int = Time.get_ticks_usec()
	var profile: Dictionary = Profile.normalize(limits)
	var max_nodes: int = int(limits.get("max_nodes", 0))
	var min_completed_depth: int = maxi(int(limits.get("min_completed_depth", 0)), 0)
	var initial_context: Dictionary = {
		"profile": profile,
		"max_nodes": max_nodes,
		"min_completed_depth": min_completed_depth,
		"completed_depth": 0,
		"minimum_depth_guard_used": false,
	}
	if state == null:
		return _make_result(null, 0, 0, initial_context, started_usec, true, &"no_legal_action", false)
	var legal_actions: Array[ActionData] = Simulator.get_legal_actions(state)
	if legal_actions.is_empty():
		return _make_result(null, 0, 0, initial_context, started_usec, true, &"no_legal_action", false)
	if root_owner < 0:
		root_owner = state.active_player

	var context: Dictionary = {
		"oracle_backend": bool(limits.get("_oracle_test_backend", false)),
		"deadline_usec": int(limits.get("deadline_usec", 0)),
		"max_nodes": max_nodes,
		"min_completed_depth": min_completed_depth,
		"completed_depth": 0,
		"minimum_depth_guard_used": false,
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
		"evaluation_cache": {},
		"history": {},
		"aborted": false,
		"stop_reason": &"",
		"horizon_reached": false,
		"iteration_depth": 0,
		"iteration_started_nodes": 0,
		"root_actions_total": 0,
		"root_actions_started": 0,
		"root_actions_completed": 0,
		"root_current_action_started_nodes": 0,
		"collect_timings": bool(limits.get("collect_timings", false)),
		"time_order_usec": 0,
		"time_apply_usec": 0,
		"time_key_usec": 0,
		"time_evaluate_usec": 0,
		"turn_plan": [],
		"should_cancel": should_cancel,
		"profile": profile,
	}
	if context["deadline_usec"] <= 0 and float(limits.get("budget_seconds", 0.0)) > 0.0:
		context["deadline_usec"] = started_usec + int(float(limits["budget_seconds"]) * 1_000_000.0)
	var max_depth: int = int(limits.get("max_depth", 0))
	var table: Dictionary = {}
	var best_action: ActionData = null
	var best_score: int = 0
	var completed_depth: int = 0
	var solved: bool = false
	var previous_best_key: String = ""
	var depth: int = 1
	while max_depth <= 0 or depth <= max_depth:
		context["aborted"] = false
		context["stop_reason"] = &""
		context["horizon_reached"] = false
		context["iteration_depth"] = depth
		context["iteration_started_nodes"] = int(context["nodes"])
		context["root_actions_total"] = 0
		context["root_actions_started"] = 0
		context["root_actions_completed"] = 0
		context["root_current_action_started_nodes"] = int(context["nodes"])
		var iteration: Dictionary = _search_root(
			state,
			depth * 2,
			root_owner,
			context,
			table,
			previous_best_key
		)
		if bool(context["aborted"]):
			break
		best_action = (iteration.get("action") as ActionData).duplicate_action()
		best_score = int(iteration.get("score", 0))
		completed_depth = depth
		if (
			max_nodes > 0
			and int(context.get("nodes", 0)) >= max_nodes
			and depth <= min_completed_depth
		):
			context["minimum_depth_guard_used"] = true
		context["completed_depth"] = completed_depth
		previous_best_key = best_action.canonical_key()
		context["turn_plan"] = _build_same_turn_plan(
			state,
			best_action,
			table,
			bool(context.get("oracle_backend", false))
		)
		solved = not bool(context["horizon_reached"])
		if on_progress.is_valid():
			on_progress.call(_make_result(
				best_action,
				best_score,
				completed_depth,
				context,
				started_usec,
				solved,
				&"solved" if solved else &"searching",
				true
			))
		if solved:
			break
		depth += 1

	var reason: StringName = &"solved" if solved else StringName(context.get("stop_reason", &""))
	if reason == &"":
		reason = &"max_depth"
	return _make_result(
		best_action,
		best_score,
		completed_depth,
		context,
		started_usec,
		solved,
		reason,
		completed_depth > 0
	)


static func _search_root(
	state: StateData,
	remaining_owner_turn_boundaries: int,
	root_owner: int,
	context: Dictionary,
	table: Dictionary,
	previous_best_key: String
) -> Dictionary:
	var maximizing: bool = state.active_player == root_owner
	var best_score: int = -INFINITY if maximizing else INFINITY
	var best_action: ActionData = null
	var alpha: int = -INFINITY
	var beta: int = INFINITY
	var first_child: bool = true
	var records: Array[Dictionary] = _ordered_records(
		state,
		previous_best_key,
		"",
		context
	)
	context["root_actions_total"] = records.size()
	for record: Dictionary in records:
		if _should_stop(context):
			return {}
		context["root_actions_started"] = int(context["root_actions_started"]) + 1
		context["root_current_action_started_nodes"] = int(context["nodes"])
		var action: ActionData = record["action"] as ActionData
		var next_state: StateData = _next_state_for_record(state, record, context)
		var child_remaining: int = _remaining_after_transition(
			state,
			next_state,
			remaining_owner_turn_boundaries
		)
		var score: int = _search_child(
			next_state,
			child_remaining,
			alpha,
			beta,
			root_owner,
			maximizing,
			first_child,
			context,
			table
		)
		if bool(context["aborted"]):
			return {}
		first_child = false
		var action_key: String = action.canonical_key()
		var is_better_tie: bool = (
			best_action != null
			and score == best_score
			and action_key < best_action.canonical_key()
		)
		if is_better_tie:
			# A later alpha-beta child may return the current root score as a
			# fail-low/fail-high bound. Verify the narrow equality interval before
			# allowing canonical tie-breaking to replace the proven best action.
			score = _search(
				next_state,
				child_remaining,
				best_score - 1,
				best_score + 1,
				root_owner,
				context,
				table
			)
			if bool(context["aborted"]):
				return {}
			is_better_tie = score == best_score
		context["root_actions_completed"] = int(context["root_actions_completed"]) + 1
		if best_action == null or (maximizing and score > best_score) or (not maximizing and score < best_score) or is_better_tie:
			best_score = score
			best_action = action
		if maximizing:
			alpha = maxi(alpha, best_score)
		else:
			beta = mini(beta, best_score)
	return {"action": best_action, "score": best_score}


static func _search(
	state: StateData,
	depth_remaining: int,
	alpha_value: int,
	beta_value: int,
	root_owner: int,
	context: Dictionary,
	table: Dictionary
) -> int:
	if _should_stop(context):
		return 0
	context["nodes"] = int(context["nodes"]) + 1
	if Simulator.is_terminal(state):
		return _evaluate_state(state, root_owner, context)
	if depth_remaining <= 0:
		context["horizon_reached"] = true
		var profile: Dictionary = context.get("profile", {}) as Dictionary
		if bool(profile.get("use_tactical_extension", false)):
			return _search_tactical(
				state,
				alpha_value,
				beta_value,
				root_owner,
				int(profile.get("max_tactical_depth", 0)),
				0,
				false,
				context,
				table
			)
		return _evaluate_state(state, root_owner, context)

	var key_started_usec: int = (
		Time.get_ticks_usec()
		if bool(context.get("collect_timings", false))
		else 0
	)
	var key: String = StateKey.build_compact(state)
	if key_started_usec > 0:
		context["time_key_usec"] = (
			int(context.get("time_key_usec", 0))
			+ Time.get_ticks_usec()
			- key_started_usec
		)
	var original_alpha: int = alpha_value
	var original_beta: int = beta_value
	var alpha: int = alpha_value
	var beta: int = beta_value
	var cached: Dictionary = table.get(key, {})
	if not cached.is_empty() and int(cached.get("depth", -1)) >= depth_remaining:
		context["transposition_hits"] = int(context["transposition_hits"]) + 1
		if bool(cached.get("horizon", false)):
			context["horizon_reached"] = true
		var cached_score: int = int(cached.get("score", 0))
		var cached_bound := StringName(cached.get("bound", &""))
		if cached_bound == &"exact":
			return cached_score
		if cached_bound == &"lower":
			alpha = maxi(alpha, cached_score)
		elif cached_bound == &"upper":
			beta = mini(beta, cached_score)
		if alpha >= beta:
			return cached_score

	var maximizing: bool = state.active_player == root_owner
	var best_score: int = -INFINITY if maximizing else INFINITY
	var best_key: String = String(cached.get("best_action_key", ""))
	var records: Array[Dictionary] = _ordered_records(state, "", best_key, context)
	if records.is_empty():
		return _evaluate_state(state, root_owner, context)
	var horizon_before: bool = bool(context["horizon_reached"])
	var chosen_key: String = ""
	var first_child: bool = true
	for record: Dictionary in records:
		if _should_stop(context):
			return 0
		var action: ActionData = record["action"] as ActionData
		var next_state: StateData = _next_state_for_record(state, record, context)
		var child_remaining: int = _remaining_after_transition(
			state,
			next_state,
			depth_remaining
		)
		var child_score: int = _search_child(
			next_state,
			child_remaining,
			alpha,
			beta,
			root_owner,
			maximizing,
			first_child,
			context,
			table
		)
		if bool(context["aborted"]):
			return 0
		first_child = false
		var action_key: String = action.canonical_key()
		var is_better_tie: bool = not chosen_key.is_empty() and child_score == best_score and action_key < chosen_key
		if chosen_key.is_empty() or (maximizing and child_score > best_score) or (not maximizing and child_score < best_score) or is_better_tie:
			best_score = child_score
			chosen_key = action_key
		if maximizing:
			alpha = maxi(alpha, best_score)
		else:
			beta = mini(beta, best_score)
		if alpha >= beta:
			context["cutoffs"] = int(context["cutoffs"]) + 1
			_record_history_cutoff(context, state, action, depth_remaining)
			break

	var stored_bound: StringName = &"exact"
	if best_score <= original_alpha:
		stored_bound = &"upper"
	elif best_score >= original_beta:
		stored_bound = &"lower"
	if table.has(key) or table.size() < MAX_TRANSPOSITION_ENTRIES:
		table[key] = {
			"depth": depth_remaining,
			"score": best_score,
			"bound": stored_bound,
			"best_action_key": chosen_key,
			"horizon": bool(context["horizon_reached"]) and not horizon_before,
		}
	return best_score


static func _remaining_after_transition(
	state: StateData,
	next_state: StateData,
	remaining_owner_turn_boundaries: int
) -> int:
	if state == null or next_state == null:
		return remaining_owner_turn_boundaries
	var completed_owner_turns: int = maxi(
		next_state.owner_turn_serial - state.owner_turn_serial,
		0
	)
	return remaining_owner_turn_boundaries - completed_owner_turns


static func _search_child(
	state: StateData,
	depth_remaining: int,
	alpha: int,
	beta: int,
	root_owner: int,
	maximizing: bool,
	first_child: bool,
	context: Dictionary,
	table: Dictionary
) -> int:
	var profile: Dictionary = context.get("profile", {}) as Dictionary
	if first_child or not bool(profile.get("use_pvs", false)):
		return _search(state, depth_remaining, alpha, beta, root_owner, context, table)
	context["pvs_probes"] = int(context.get("pvs_probes", 0)) + 1
	var score: int
	if maximizing:
		score = _search(
			state,
			depth_remaining,
			alpha,
			mini(alpha + 1, beta),
			root_owner,
			context,
			table
		)
		if bool(context.get("aborted", false)):
			return 0
		if score > alpha and score < beta:
			context["pvs_researches"] = int(context.get("pvs_researches", 0)) + 1
			score = _search(state, depth_remaining, alpha, beta, root_owner, context, table)
	else:
		score = _search(
			state,
			depth_remaining,
			maxi(beta - 1, alpha),
			beta,
			root_owner,
			context,
			table
		)
		if bool(context.get("aborted", false)):
			return 0
		if score < beta and score > alpha:
			context["pvs_researches"] = int(context.get("pvs_researches", 0)) + 1
			score = _search(state, depth_remaining, alpha, beta, root_owner, context, table)
	return score


static func _search_tactical(
	state: StateData,
	alpha_value: int,
	beta_value: int,
	root_owner: int,
	remaining_depth: int,
	current_depth: int,
	count_node: bool,
	context: Dictionary,
	table: Dictionary
) -> int:
	if count_node:
		if _should_stop(context):
			return 0
		context["nodes"] = int(context.get("nodes", 0)) + 1
	if Simulator.is_terminal(state):
		return _evaluate_state(state, root_owner, context)
	var stand_pat: int = _evaluate_state(state, root_owner, context)
	if remaining_depth <= 0:
		return stand_pat
	var maximizing: bool = state.active_player == root_owner
	var best_score: int = stand_pat
	var alpha: int = alpha_value
	var beta: int = beta_value
	if maximizing:
		alpha = maxi(alpha, stand_pat)
	else:
		beta = mini(beta, stand_pat)
	if alpha >= beta:
		context["cutoffs"] = int(context.get("cutoffs", 0)) + 1
		return stand_pat

	var profile: Dictionary = context.get("profile", {}) as Dictionary
	var scan_limit: int = int(profile.get("tactical_scan_limit", 0))
	var action_limit: int = int(profile.get("tactical_action_limit", 0))
	if scan_limit <= 0 or action_limit <= 0:
		return stand_pat
	var legal_actions: Array[ActionData] = Simulator.get_legal_actions(state)
	context["generated_actions"] = int(context.get("generated_actions", 0)) + legal_actions.size()
	var ordered_actions: Array[ActionData] = Ordering.order_actions(
		state,
		legal_actions,
		"",
		"",
		context.get("history", {}) as Dictionary
	)
	var scanned_at_node: int = 0
	var searched_at_node: int = 0
	var first_child: bool = true
	for action: ActionData in ordered_actions:
		if scanned_at_node >= scan_limit or searched_at_node >= action_limit:
			break
		if _should_stop(context):
			return 0
		var transition: Dictionary = _apply_transition(state, action, context)
		context["applied_transitions"] = int(context.get("applied_transitions", 0)) + 1
		scanned_at_node += 1
		context["tactical_candidates_scanned"] = int(context.get("tactical_candidates_scanned", 0)) + 1
		if not Tactics.is_volatile(state, transition):
			continue
		searched_at_node += 1
		context["tactical_actions_searched"] = int(context.get("tactical_actions_searched", 0)) + 1
		context["max_tactical_depth"] = maxi(
			int(context.get("max_tactical_depth", 0)),
			current_depth + 1
		)
		var next_state: StateData = transition["state"] as StateData
		var child_score: int = _search_tactical_child(
			next_state,
			alpha,
			beta,
			root_owner,
			remaining_depth - 1,
			current_depth + 1,
			maximizing,
			first_child,
			context,
			table
		)
		if bool(context.get("aborted", false)):
			return 0
		first_child = false
		if maximizing:
			best_score = maxi(best_score, child_score)
			alpha = maxi(alpha, best_score)
		else:
			best_score = mini(best_score, child_score)
			beta = mini(beta, best_score)
		if alpha >= beta:
			context["cutoffs"] = int(context.get("cutoffs", 0)) + 1
			_record_history_cutoff(context, state, action, remaining_depth)
			break
	context["max_tactical_candidates_per_node"] = maxi(
		int(context.get("max_tactical_candidates_per_node", 0)),
		scanned_at_node
	)
	context["max_tactical_actions_per_node"] = maxi(
		int(context.get("max_tactical_actions_per_node", 0)),
		searched_at_node
	)
	return best_score


static func _search_tactical_child(
	state: StateData,
	alpha: int,
	beta: int,
	root_owner: int,
	remaining_depth: int,
	current_depth: int,
	maximizing: bool,
	first_child: bool,
	context: Dictionary,
	table: Dictionary
) -> int:
	var profile: Dictionary = context.get("profile", {}) as Dictionary
	if first_child or not bool(profile.get("use_pvs", false)):
		return _search_tactical(
			state, alpha, beta, root_owner, remaining_depth, current_depth, true, context, table
		)
	context["pvs_probes"] = int(context.get("pvs_probes", 0)) + 1
	var score: int
	if maximizing:
		score = _search_tactical(
			state,
			alpha,
			mini(alpha + 1, beta),
			root_owner,
			remaining_depth,
			current_depth,
			true,
			context,
			table
		)
		if not bool(context.get("aborted", false)) and score > alpha and score < beta:
			context["pvs_researches"] = int(context.get("pvs_researches", 0)) + 1
			score = _search_tactical(
				state, alpha, beta, root_owner, remaining_depth, current_depth, true, context, table
			)
	else:
		score = _search_tactical(
			state,
			maxi(beta - 1, alpha),
			beta,
			root_owner,
			remaining_depth,
			current_depth,
			true,
			context,
			table
		)
		if not bool(context.get("aborted", false)) and score < beta and score > alpha:
			context["pvs_researches"] = int(context.get("pvs_researches", 0)) + 1
			score = _search_tactical(
				state, alpha, beta, root_owner, remaining_depth, current_depth, true, context, table
			)
	return score


static func _ordered_records(
	state: StateData,
	principal_variation_key: String,
	transposition_key: String,
	context: Dictionary
) -> Array[Dictionary]:
	var timing_started_usec: int = (
		Time.get_ticks_usec()
		if bool(context.get("collect_timings", false))
		else 0
	)
	var profile: Dictionary = context.get("profile", {}) as Dictionary
	if not bool(profile.get("use_lazy_transitions", false)):
		var preferred_key: String = (
			principal_variation_key
			if not principal_variation_key.is_empty()
			else transposition_key
		)
		var eager_records: Array[Dictionary] = _ordered_transitions(state, preferred_key, context)
		_record_elapsed_timing(context, "time_order_usec", timing_started_usec)
		return eager_records
	var legal_actions: Array[ActionData] = Simulator.get_legal_actions(state)
	context["generated_actions"] = int(context.get("generated_actions", 0)) + legal_actions.size()
	var ordered_actions: Array[ActionData] = Ordering.order_actions(
		state,
		legal_actions,
		principal_variation_key,
		transposition_key,
		context.get("history", {}) as Dictionary
	)
	var records: Array[Dictionary] = []
	for action: ActionData in ordered_actions:
		records.append({"action": action})
	_record_elapsed_timing(context, "time_order_usec", timing_started_usec)
	return records


static func _next_state_for_record(
	state: StateData,
	record: Dictionary,
	context: Dictionary
) -> StateData:
	if record.has("transition"):
		return (record["transition"] as Dictionary)["state"] as StateData
	var timing_started_usec: int = (
		Time.get_ticks_usec()
		if bool(context.get("collect_timings", false))
		else 0
	)
	var transition: Dictionary = _apply_transition(state, record["action"] as ActionData, context)
	_record_elapsed_timing(context, "time_apply_usec", timing_started_usec)
	context["applied_transitions"] = int(context.get("applied_transitions", 0)) + 1
	return transition["state"] as StateData


static func _record_history_cutoff(
	context: Dictionary,
	state: StateData,
	action: ActionData,
	depth_remaining: int
) -> void:
	var history: Dictionary = context.get("history", {}) as Dictionary
	var key: String = Ordering.history_key(action, state)
	history[key] = int(history.get(key, 0)) + depth_remaining * depth_remaining


static func _evaluate_state(
	state: StateData,
	root_owner: int,
	context: Dictionary
) -> int:
	var timing_started_usec: int = (
		Time.get_ticks_usec()
		if bool(context.get("collect_timings", false))
		else 0
	)
	var profile: Dictionary = context.get("profile", {}) as Dictionary
	if not bool(profile.get("use_evaluation_cache", false)):
		var score: int = Evaluator.evaluate(
			state,
			root_owner,
			StringName(profile.get("evaluator_profile", Profile.ENHANCED))
		)
		_record_elapsed_timing(context, "time_evaluate_usec", timing_started_usec)
		return score
	var lookup: Dictionary = EvaluationCache.lookup_or_evaluate(
		context.get("evaluation_cache", {}) as Dictionary,
		state,
		root_owner,
		StringName(profile.get("evaluator_profile", Profile.ENHANCED))
	)
	if bool(lookup.get("hit", false)):
		context["evaluation_cache_hits"] = int(context.get("evaluation_cache_hits", 0)) + 1
	_record_elapsed_timing(context, "time_evaluate_usec", timing_started_usec)
	return int(lookup.get("score", 0))


static func _record_elapsed_timing(
	context: Dictionary,
	field: String,
	started_usec: int
) -> void:
	if started_usec <= 0:
		return
	context[field] = int(context.get(field, 0)) + Time.get_ticks_usec() - started_usec


static func _apply_transition(
	state: StateData,
	action: ActionData,
	context: Dictionary
) -> Dictionary:
	if bool(context.get("oracle_backend", false)):
		return Simulator.apply_action_oracle(state, action)
	return Simulator.apply_action(state, action)


static func _ordered_transitions(
	state: StateData,
	preferred_key: String,
	context: Dictionary
) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var legal_actions: Array[ActionData] = Simulator.get_legal_actions(state)
	context["generated_actions"] = int(context.get("generated_actions", 0)) + legal_actions.size()
	for action: ActionData in legal_actions:
		var transition: Dictionary = _apply_transition(state, action, context)
		context["applied_transitions"] = int(context.get("applied_transitions", 0)) + 1
		var next_state: StateData = transition["state"] as StateData
		var priority: int = 0
		if action.canonical_key() == preferred_key:
			priority += 1_000_000
		if Simulator.is_terminal(next_state):
			priority += 100_000
		priority += (transition.get("captures", []) as Array).size() * 10_000
		priority += (transition.get("exiles", []) as Array).size() * 8_000
		for event_value: Variant in transition.get("events", []):
			if StringName((event_value as Dictionary).get("type", &"")) == &"extra_card_play_granted":
				priority += 5_000
		if action.action_type == ActionData.TYPE_ACTIVATE:
			priority += 500
		priority += Simulator.score_difference(next_state, state.active_player) * 10
		records.append({
			"action": action,
			"transition": transition,
			"priority": priority,
			"key": action.canonical_key(),
		})
	records.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_priority: int = int(left["priority"])
		var right_priority: int = int(right["priority"])
		if left_priority != right_priority:
			return left_priority > right_priority
		return String(left["key"]) < String(right["key"])
	)
	return records


static func _should_stop(context: Dictionary) -> bool:
	if bool(context.get("aborted", false)):
		return true
	var cancel_check: Callable = context.get("should_cancel", Callable())
	if cancel_check.is_valid() and bool(cancel_check.call()):
		context["aborted"] = true
		context["stop_reason"] = &"cancelled"
		return true
	var max_nodes: int = int(context.get("max_nodes", 0))
	if max_nodes > 0 and int(context.get("nodes", 0)) >= max_nodes:
		var completed_depth: int = int(context.get("completed_depth", 0))
		var min_completed_depth: int = int(context.get("min_completed_depth", 0))
		if completed_depth < min_completed_depth:
			context["minimum_depth_guard_used"] = true
		else:
			context["aborted"] = true
			context["stop_reason"] = &"node_limit"
			return true
	var deadline_usec: int = int(context.get("deadline_usec", 0))
	if deadline_usec > 0 and Time.get_ticks_usec() >= deadline_usec:
		context["aborted"] = true
		context["stop_reason"] = &"deadline"
		return true
	return false


static func _build_same_turn_plan(
	state: StateData,
	first_action: ActionData,
	table: Dictionary,
	oracle_backend: bool = false
) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	if state == null or first_action == null or first_action.action_type == &"":
		return plan
	var root_owner: int = state.active_player
	var root_owner_turn_serial: int = state.owner_turn_serial
	var current_state: StateData = state
	var current_action: ActionData = first_action
	var observed_state_keys: Dictionary = {}
	while (
		current_state != null
		and current_state.active_player == root_owner
		and current_state.owner_turn_serial == root_owner_turn_serial
	):
		var current_key: String = StateKey.build_compact(current_state)
		if observed_state_keys.has(current_key):
			break
		observed_state_keys[current_key] = true
		if not Simulator.is_action_legal(current_state, current_action):
			break
		plan.append({
			"state_key": current_key,
			"owner_turn_serial": root_owner_turn_serial,
			"owner_id": root_owner,
			"action": current_action.duplicate_action(),
		})
		var transition: Dictionary = (
			Simulator.apply_action_oracle(current_state, current_action)
			if oracle_backend
			else Simulator.apply_action(current_state, current_action)
		)
		if not bool(transition.get("valid", false)):
			break
		current_state = transition.get("state") as StateData
		if (
			current_state == null
			or Simulator.is_terminal(current_state)
			or current_state.active_player != root_owner
			or current_state.owner_turn_serial != root_owner_turn_serial
		):
			break
		var next_key: String = StateKey.build_compact(current_state)
		var cached: Dictionary = table.get(next_key, {}) as Dictionary
		var next_action_key: String = String(cached.get("best_action_key", ""))
		if next_action_key.is_empty():
			break
		current_action = _find_legal_action_by_key(current_state, next_action_key)
		if current_action == null:
			break
	return plan


static func _build_native_turn_plan(
	state: StateData,
	planned_actions: Array
) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	if state == null or planned_actions.is_empty():
		return plan
	var current_state: StateData = state.duplicate_state()
	var root_owner: int = current_state.active_player
	var root_owner_turn_serial: int = current_state.owner_turn_serial
	for action_value: Variant in planned_actions:
		var action: ActionData = action_value as ActionData
		if (
			action == null
			or current_state.active_player != root_owner
			or current_state.owner_turn_serial != root_owner_turn_serial
			or not Simulator.is_action_legal(current_state, action)
		):
			break
		plan.append({
			"state_key": StateKey.build_compact(current_state),
			"owner_turn_serial": root_owner_turn_serial,
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


static func _find_legal_action_by_key(
	state: StateData,
	action_key: String
) -> ActionData:
	for action: ActionData in Simulator.get_legal_actions(state):
		if action.canonical_key() == action_key:
			return action
	return null


static func _duplicate_turn_plan(source: Array) -> Array[Dictionary]:
	var copied_plan: Array[Dictionary] = []
	for entry_value: Variant in source:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = (entry_value as Dictionary).duplicate(true)
		var action: ActionData = (entry_value as Dictionary).get("action", null) as ActionData
		if action != null:
			entry["action"] = action.duplicate_action()
		copied_plan.append(entry)
	return copied_plan


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
	result["nodes_over_limit"] = (
		maxi(int(result["nodes"]) - max_nodes, 0) if max_nodes > 0 else 0
	)
	for field: String in [
		"cutoffs",
		"generated_actions",
		"applied_transitions",
		"root_actions_total",
		"root_actions_started",
		"root_actions_completed",
	]:
		result[field] = int(source.get(field, 0))
	result["transposition_hits"] = 0
	result["pvs_probes"] = 0
	result["pvs_researches"] = 0
	result["evaluation_cache_hits"] = 0
	result["iteration_depth"] = int(source.get("iteration_depth", source.get("completed_depth", 0)))
	result["iteration_nodes"] = 0
	result["current_root_action_nodes"] = 0
	result["time_order_usec"] = 0
	result["time_apply_usec"] = 0
	result["time_key_usec"] = 0
	result["time_evaluate_usec"] = 0
	result["turn_plan"] = []
	result["max_tactical_depth"] = 0
	result["tactical_candidates_scanned"] = 0
	result["tactical_actions_searched"] = 0
	result["max_tactical_candidates_per_node"] = 0
	result["max_tactical_actions_per_node"] = 0
	result["search_profile"] = StringName(profile.get("name", Profile.ENHANCED))
	result["elapsed_seconds"] = float(Time.get_ticks_usec() - started_usec) / 1_000_000.0
	result["solved"] = bool(source.get("solved", false))
	result["completion_reason"] = StringName(source.get("completion_reason", &"max_depth"))
	result["has_completed_depth"] = bool(source.get("has_completed_depth", false))
	return result


static func _make_result(
	action: ActionData,
	score: int,
	completed_depth: int,
	context: Dictionary,
	started_usec: int,
	solved: bool,
	completion_reason: StringName,
	has_completed_depth: bool
) -> Dictionary:
	var nodes: int = int(context.get("nodes", 0))
	var max_nodes: int = int(context.get("max_nodes", 0))
	return {
		"action": action.duplicate_action() if action != null else ActionData.new(),
		"score": score,
		"completed_depth": completed_depth,
		"nodes": nodes,
		"min_completed_depth": maxi(int(context.get("min_completed_depth", 0)), 0),
		"minimum_depth_guard_used": bool(context.get("minimum_depth_guard_used", false)),
		"nodes_over_limit": maxi(nodes - max_nodes, 0) if max_nodes > 0 else 0,
		"cutoffs": int(context.get("cutoffs", 0)),
		"transposition_hits": int(context.get("transposition_hits", 0)),
		"generated_actions": int(context.get("generated_actions", 0)),
		"applied_transitions": int(context.get("applied_transitions", 0)),
		"pvs_probes": int(context.get("pvs_probes", 0)),
		"pvs_researches": int(context.get("pvs_researches", 0)),
		"evaluation_cache_hits": int(context.get("evaluation_cache_hits", 0)),
		"iteration_depth": int(context.get("iteration_depth", 0)),
		"iteration_nodes": maxi(
			int(context.get("nodes", 0)) - int(context.get("iteration_started_nodes", 0)),
			0
		),
		"root_actions_total": int(context.get("root_actions_total", 0)),
		"root_actions_started": int(context.get("root_actions_started", 0)),
		"root_actions_completed": int(context.get("root_actions_completed", 0)),
		"current_root_action_nodes": (
			maxi(
				int(context.get("nodes", 0))
				- int(context.get("root_current_action_started_nodes", 0)),
				0
			)
			if int(context.get("root_actions_started", 0))
			> int(context.get("root_actions_completed", 0))
			else 0
		),
		"time_order_usec": int(context.get("time_order_usec", 0)),
		"time_apply_usec": int(context.get("time_apply_usec", 0)),
		"time_key_usec": int(context.get("time_key_usec", 0)),
		"time_evaluate_usec": int(context.get("time_evaluate_usec", 0)),
		"turn_plan": _duplicate_turn_plan(context.get("turn_plan", []) as Array),
		"max_tactical_depth": int(context.get("max_tactical_depth", 0)),
		"tactical_candidates_scanned": int(context.get("tactical_candidates_scanned", 0)),
		"tactical_actions_searched": int(context.get("tactical_actions_searched", 0)),
		"max_tactical_candidates_per_node": int(context.get("max_tactical_candidates_per_node", 0)),
		"max_tactical_actions_per_node": int(context.get("max_tactical_actions_per_node", 0)),
		"search_profile": StringName((context.get("profile", {}) as Dictionary).get("name", Profile.ENHANCED)),
		"elapsed_seconds": float(Time.get_ticks_usec() - started_usec) / 1_000_000.0,
		"solved": solved,
		"completion_reason": completion_reason,
		"has_completed_depth": has_completed_depth,
	}
