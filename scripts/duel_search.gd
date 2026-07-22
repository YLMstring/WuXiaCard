class_name DuelSearch
extends RefCounted

const WIN_SCORE: int = 1_000_000
const INFINITY: int = 1_000_000_000
const MAX_TRANSPOSITION_ENTRIES: int = 50_000

const ActionData = preload("res://scripts/duel_action.gd")
const Evaluator = preload("res://scripts/duel_evaluator.gd")
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
		{"max_depth": maxi(max_depth, 1)},
		Callable(),
		Callable()
	)
	var action: ActionData = result.get("action", null) as ActionData
	return action.duplicate_action() if action != null else ActionData.new()


static func find_best_action_iterative(
	state: StateData,
	root_owner: int = -1,
	limits: Dictionary = {},
	should_cancel: Callable = Callable(),
	on_progress: Callable = Callable()
) -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	var legal_actions: Array[ActionData] = Simulator.get_legal_actions(state)
	if state == null or legal_actions.is_empty():
		return _make_result(null, 0, 0, {}, started_usec, true, &"no_legal_action", false)
	if root_owner < 0:
		root_owner = state.active_player

	var context: Dictionary = {
		"deadline_usec": int(limits.get("deadline_usec", 0)),
		"max_nodes": int(limits.get("max_nodes", 0)),
		"nodes": 0,
		"cutoffs": 0,
		"transposition_hits": 0,
		"aborted": false,
		"stop_reason": &"",
		"horizon_reached": false,
		"should_cancel": should_cancel,
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
		var iteration: Dictionary = _search_root(
			state,
			depth,
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
		previous_best_key = best_action.canonical_key()
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
	depth: int,
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
	var records: Array[Dictionary] = _ordered_transitions(state, previous_best_key, context)
	for record: Dictionary in records:
		if _should_stop(context):
			return {}
		var action: ActionData = record["action"] as ActionData
		var next_state: StateData = (record["transition"] as Dictionary)["state"] as StateData
		var score: int = _search(next_state, depth - 1, alpha, beta, root_owner, context, table)
		if bool(context["aborted"]):
			return {}
		var is_better_tie: bool = (
			best_action != null
			and score == best_score
			and action.canonical_key() < best_action.canonical_key()
		)
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
		return Evaluator.evaluate(state, root_owner)
	if depth_remaining <= 0:
		context["horizon_reached"] = true
		return Evaluator.evaluate(state, root_owner)

	var key: String = StateKey.build_compact(state)
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
	var records: Array[Dictionary] = _ordered_transitions(state, best_key, context)
	if records.is_empty():
		return Evaluator.evaluate(state, root_owner)
	var horizon_before: bool = bool(context["horizon_reached"])
	var chosen_key: String = ""
	for record: Dictionary in records:
		if _should_stop(context):
			return 0
		var action: ActionData = record["action"] as ActionData
		var next_state: StateData = (record["transition"] as Dictionary)["state"] as StateData
		var child_score: int = _search(
			next_state,
			depth_remaining - 1,
			alpha,
			beta,
			root_owner,
			context,
			table
		)
		if bool(context["aborted"]):
			return 0
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


static func _ordered_transitions(
	state: StateData,
	preferred_key: String,
	_context: Dictionary
) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for action: ActionData in Simulator.get_legal_actions(state):
		var transition: Dictionary = Simulator.apply_action(state, action)
		var next_state: StateData = transition["state"] as StateData
		var priority: int = 0
		if action.canonical_key() == preferred_key:
			priority += 1_000_000
		if Simulator.is_terminal(next_state):
			priority += 100_000
		priority += (transition.get("captures", []) as Array).size() * 10_000
		priority += (transition.get("exiles", []) as Array).size() * 8_000
		for event_value: Variant in transition.get("events", []):
			if StringName((event_value as Dictionary).get("type", &"")) == &"extra_turn_granted":
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
		context["aborted"] = true
		context["stop_reason"] = &"node_limit"
		return true
	var deadline_usec: int = int(context.get("deadline_usec", 0))
	if deadline_usec > 0 and Time.get_ticks_usec() >= deadline_usec:
		context["aborted"] = true
		context["stop_reason"] = &"deadline"
		return true
	return false


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
	return {
		"action": action.duplicate_action() if action != null else ActionData.new(),
		"score": score,
		"completed_depth": completed_depth,
		"nodes": int(context.get("nodes", 0)),
		"cutoffs": int(context.get("cutoffs", 0)),
		"transposition_hits": int(context.get("transposition_hits", 0)),
		"elapsed_seconds": float(Time.get_ticks_usec() - started_usec) / 1_000_000.0,
		"solved": solved,
		"completion_reason": completion_reason,
		"has_completed_depth": has_completed_depth,
	}
