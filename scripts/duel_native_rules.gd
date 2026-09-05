class_name DuelNativeRules
extends RefCounted

const ActionData = preload("res://scripts/duel_action.gd")
const CompactState = preload("res://scripts/duel_compact_state.gd")
const StateData = preload("res://scripts/duel_state.gd")

const KERNEL_CLASS: StringName = &"DuelNativeCompactKernel"


static func apply_action(state: StateData, action: ActionData) -> Dictionary:
	if state == null or action == null:
		return _integration_failure(state, "Native transition received a null state or action")
	if not ClassDB.class_exists(KERNEL_CLASS):
		return _integration_failure(state, "DuelNativeCompactKernel is unavailable")

	var compact := CompactState.new()
	if not compact.capture_state(state) or not compact.is_structurally_valid():
		return _integration_failure(state, "Duel state could not cross the compact native boundary")

	var kernel: Object = ClassDB.instantiate(KERNEL_CLASS)
	if kernel == null:
		return _integration_failure(state, "DuelNativeCompactKernel could not be instantiated")
	if not bool(kernel.call("load_compact_payload", compact.to_variant_payload())):
		return _integration_failure(
			state,
			"Native compact payload load failed: %s" % String(kernel.call("get_last_error"))
		)

	var native_result: Dictionary
	if action.action_type == ActionData.TYPE_PLAY:
		native_result = kernel.call(
			"apply_play_transition",
			action.source_index,
			action.target_index,
			action.source_instance_id
		) as Dictionary
	elif action.action_type == ActionData.TYPE_ACTIVATE:
		native_result = kernel.call(
			"apply_activate_transition",
			action.source_index,
			action.target_kind,
			action.target_index,
			action.activation_index,
			action.source_instance_id
		) as Dictionary
	else:
		return _integration_failure(state, "Native transition received an unknown action type")

	var reason := String(native_result.get("reason", ""))
	if not bool(native_result.get("supported", false)):
		return _integration_failure(state, "Native rules do not support this legal action: %s" % reason)
	if not bool(native_result.get("valid", false)):
		return {
			"valid": false,
			"state": state,
			"captures": [],
			"exiles": [],
			"events": [],
			"reason": reason,
		}
	var payload_value: Variant = native_result.get("payload", null)
	if not payload_value is Dictionary:
		return _integration_failure(state, "Native transition returned no compact payload")
	var restored_compact: CompactState = CompactState.from_variant_payload(payload_value as Dictionary)
	if restored_compact == null or not restored_compact.is_structurally_valid():
		return _integration_failure(state, "Native transition returned a malformed compact payload")
	var next_state: StateData = restored_compact.restore()
	if next_state == null:
		return _integration_failure(state, "Native compact payload could not restore a duel state")
	for field: String in ["captures", "exiles", "events"]:
		if not native_result.get(field, null) is Array:
			return _integration_failure(state, "Native transition field '%s' is not an Array" % field)
	return {
		"valid": true,
		"state": next_state,
		"captures": native_result.get("captures", []),
		"exiles": native_result.get("exiles", []),
		"events": native_result.get("events", []),
	}


static func get_legal_actions_for_owner(
	state: StateData,
	owner_id: int
) -> Array[ActionData]:
	var actions: Array[ActionData] = []
	var kernel: Object = _load_query_kernel(state, "legal-action query")
	if kernel == null:
		return actions
	for value: Variant in kernel.call("get_legal_actions_for_owner", owner_id):
		if value is Dictionary:
			actions.append(_action_from_native(value as Dictionary))
	return actions


static func count_legal_actions_for_owner(state: StateData, owner_id: int) -> int:
	var kernel: Object = _load_query_kernel(state, "legal-action count")
	return 0 if kernel == null else int(kernel.call("count_legal_actions_for_owner", owner_id))


static func is_action_legal_for_owner(
	state: StateData,
	action: ActionData,
	owner_id: int
) -> bool:
	if action == null:
		return false
	var kernel: Object = _load_query_kernel(state, "action-legality query")
	return false if kernel == null else bool(kernel.call(
		"is_action_legal_for_owner",
		_action_to_native(action),
		owner_id
	))


static func is_terminal(state: StateData) -> bool:
	if state == null:
		return true
	var kernel: Object = _load_query_kernel(state, "terminal-state query")
	return true if kernel == null else bool(kernel.call("is_terminal_state"))


static func score_difference(state: StateData, owner_id: int) -> int:
	var kernel: Object = _load_query_kernel(state, "score query")
	return 0 if kernel == null else int(kernel.call("score_difference_for_owner", owner_id))


static func choose_greedy_action(state: StateData, owner_id: int) -> ActionData:
	var kernel: Object = _load_query_kernel(state, "greedy-action query")
	if kernel == null:
		return ActionData.new()
	var value: Variant = kernel.call("choose_greedy_action_for_owner", owner_id)
	return _action_from_native(value as Dictionary) if value is Dictionary else ActionData.new()


static func get_attack_targets(
	state: StateData,
	source_cell: int,
	attack_policy: Dictionary = {}
) -> Array[int]:
	var kernel: Object = _load_query_kernel(state, "get attack targets")
	var result: Array[int] = []
	if kernel == null:
		return result
	for value: Variant in kernel.call(
		"get_attack_targets_for_source", source_cell, attack_policy
	) as Array:
		result.append(int(value))
	return result


static func can_attack_target(
	state: StateData,
	source_cell: int,
	target_cell: int,
	attack_policy: Dictionary = {},
	skip_power_comparison: bool = false
) -> bool:
	var kernel: Object = _load_query_kernel(state, "check attack target")
	return kernel != null and bool(kernel.call(
		"can_attack_target_cells",
		source_cell,
		target_cell,
		attack_policy,
		skip_power_comparison
	))


static func is_target_in_attack_range(
	state: StateData,
	source_cell: int,
	target_cell: int,
	attack_policy: Dictionary = {},
	skip_power_comparison: bool = false
) -> bool:
	var kernel: Object = _load_query_kernel(state, "check attack range")
	return kernel != null and bool(kernel.call(
		"is_target_in_attack_range_cells",
		source_cell,
		target_cell,
		attack_policy,
		skip_power_comparison
	))


static func resolve_event(
	state: StateData,
	event_id: StringName,
	context: Dictionary
) -> Dictionary:
	return _resolve_direct_transition(
		state,
		&"resolve_event_transition",
		[event_id, context]
	)


static func execute_actions(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	actions: Array,
	context: Dictionary
) -> Dictionary:
	var action_context: Dictionary = context.duplicate(true)
	# The explicit source arguments define this direct action batch. They must not
	# leak through nested events and replace the source of a newly triggered ability.
	for key: String in [
		"ability_source_cell",
		"ability_source_instance_id",
		"ability_source_owner_id",
		"ability_source_zone",
		"ability_source_logical_index",
	]:
		action_context.erase(key)
	return _resolve_direct_transition(
		state,
		&"resolve_actions_transition",
		[source_cell, source_instance_id, expected_owner, actions, action_context]
	)


static func resolve_attack(state: StateData, request: Dictionary) -> Dictionary:
	return _resolve_direct_transition(
		state,
		&"resolve_attack_transition",
		[request]
	)


static func resolve_non_attack_flip(
	state: StateData,
	target_instance_id: StringName,
	new_owner: int,
	reason: StringName = &"non_attack_flip"
) -> Dictionary:
	return _resolve_direct_transition(
		state,
		&"resolve_non_attack_flip_transition",
		[target_instance_id, new_owner, reason]
	)


static func _resolve_direct_transition(
	state: StateData,
	method: StringName,
	arguments: Array
) -> Dictionary:
	if state == null:
		return _integration_failure(state, "Native direct transition received a null state")
	if not ClassDB.class_exists(KERNEL_CLASS):
		return _integration_failure(state, "DuelNativeCompactKernel is unavailable")
	var compact := CompactState.new()
	if not compact.capture_state(state) or not compact.is_structurally_valid():
		return _integration_failure(state, "Duel state could not cross the compact native boundary")
	var kernel: Object = ClassDB.instantiate(KERNEL_CLASS)
	if kernel == null:
		return _integration_failure(state, "DuelNativeCompactKernel could not be instantiated")
	if not bool(kernel.call("load_compact_payload", compact.to_variant_payload())):
		return _integration_failure(
			state,
			"Native compact payload load failed: %s" % String(kernel.call("get_last_error"))
		)
	var native_result: Dictionary = kernel.callv(method, arguments) as Dictionary
	var reason := String(native_result.get("reason", ""))
	if not bool(native_result.get("supported", false)):
		return _integration_failure(state, "Native direct transition is unsupported: %s" % reason)
	if not bool(native_result.get("valid", false)):
		return _integration_failure(state, "Native direct transition is invalid: %s" % reason)
	var payload_value: Variant = native_result.get("payload", null)
	if not payload_value is Dictionary:
		return _integration_failure(state, "Native direct transition returned no compact payload")
	var restored_compact: CompactState = CompactState.from_variant_payload(payload_value as Dictionary)
	if restored_compact == null or not restored_compact.is_structurally_valid():
		return _integration_failure(state, "Native direct transition returned a malformed compact payload")
	var next_state: StateData = restored_compact.restore()
	if next_state == null:
		return _integration_failure(state, "Native direct transition payload could not restore a duel state")
	for field: String in ["captures", "exiles", "events"]:
		if not native_result.get(field, null) is Array:
			return _integration_failure(state, "Native direct transition field '%s' is not an Array" % field)
	_overwrite_state(state, next_state)
	var result: Dictionary = {
		"valid": true,
		"state": state,
		"captures": native_result.get("captures", []),
		"exiles": native_result.get("exiles", []),
		"events": native_result.get("events", []),
	}
	for field: String in ["source_cell", "result"]:
		if native_result.has(field):
			result[field] = native_result[field]
	return result


static func _overwrite_state(target: StateData, source: StateData) -> void:
	var existing_cards: Dictionary = {}
	_collect_runtime_cards(target, existing_cards)
	target.board.resize(source.board.size())
	for cell_index: int in range(source.board.size()):
		var source_slot_value: Variant = source.board[cell_index]
		if not source_slot_value is Dictionary:
			target.board[cell_index] = null
			continue
		var source_slot: Dictionary = source_slot_value as Dictionary
		var target_slot: Dictionary = (
			target.board[cell_index] as Dictionary
			if target.board[cell_index] is Dictionary
			else {}
		)
		target_slot.clear()
		target_slot.merge(source_slot, true)
		target_slot["card"] = _reuse_runtime_card(
			source_slot.get("card", {}) as Dictionary,
			existing_cards
		)
		target.board[cell_index] = target_slot
	_sync_card_zone_dictionary(target.hands, source.hands, existing_cards)
	_sync_card_zone_dictionary(target.decks, source.decks, existing_cards)
	_sync_card_zone_dictionary(target.discard_piles, source.discard_piles, existing_cards)
	_sync_card_zone_dictionary(target.removed_cards, source.removed_cards, existing_cards)
	for property_name: StringName in [
		&"active_player",
		&"turn_count",
		&"owner_turn_serial",
		&"attacks_started_by_owner",
		&"extra_card_plays_remaining",
		&"extra_card_play_granted_this_turn",
		&"end_turn_triggers_resolved",
		&"max_turns",
		&"active_abilities",
		&"effect_queue",
		&"pending_choice",
		&"repetition_hashes",
		&"remembered_glyphs_by_owner",
		&"future_draw_reveal_audiences",
		&"last_hand_play_by_owner",
		&"pending_non_retained_suppression_by_owner",
		&"enabled_effect_gates_by_owner",
		&"run_difficulty",
		&"difficulty_eight_draw_consumed",
		&"state_version",
	]:
		target.set(property_name, source.get(property_name))


static func _collect_runtime_cards(state: StateData, result: Dictionary) -> void:
	for slot_value: Variant in state.board:
		if slot_value is Dictionary:
			_collect_runtime_card((slot_value as Dictionary).get("card", {}) as Dictionary, result)
	for zone_dictionary: Dictionary in [
		state.hands,
		state.decks,
		state.discard_piles,
		state.removed_cards,
	]:
		for owner_id: int in [1, 2]:
			for card_value: Variant in zone_dictionary.get(owner_id, []):
				if card_value is Dictionary:
					_collect_runtime_card(card_value as Dictionary, result)


static func _collect_runtime_card(card: Dictionary, result: Dictionary) -> void:
	var instance_id := StringName(card.get("instance_id", &""))
	if instance_id != &"":
		result[instance_id] = card


static func _reuse_runtime_card(source_card: Dictionary, existing_cards: Dictionary) -> Dictionary:
	var instance_id := StringName(source_card.get("instance_id", &""))
	var target_card: Dictionary = existing_cards.get(instance_id, {}) as Dictionary
	if target_card.is_empty():
		return source_card
	target_card.clear()
	target_card.merge(source_card, true)
	return target_card


static func _sync_card_zone_dictionary(
	target_zones: Dictionary,
	source_zones: Dictionary,
	existing_cards: Dictionary
) -> void:
	for owner_id: int in [1, 2]:
		var target_zone: Array = target_zones.get(owner_id, []) as Array
		target_zone.clear()
		for card_value: Variant in source_zones.get(owner_id, []):
			if card_value is Dictionary:
				target_zone.append(_reuse_runtime_card(card_value as Dictionary, existing_cards))
		target_zones[owner_id] = target_zone


static func search_iterative(
	state: StateData,
	root_owner: int,
	limits: Dictionary,
	should_cancel: Callable = Callable(),
	on_progress: Callable = Callable()
) -> Dictionary:
	if state == null:
		return _search_integration_failure("Native search received a null state")
	if not ClassDB.class_exists(KERNEL_CLASS):
		return _search_integration_failure("DuelNativeCompactKernel is unavailable")

	var compact := CompactState.new()
	if not compact.capture_state(state) or not compact.is_structurally_valid():
		return _search_integration_failure("Duel state could not cross the compact native boundary")
	var kernel: Object = ClassDB.instantiate(KERNEL_CLASS)
	if kernel == null:
		return _search_integration_failure("DuelNativeCompactKernel could not be instantiated")
	if not bool(kernel.call("load_compact_payload", compact.to_variant_payload())):
		return _search_integration_failure(
			"Native compact payload load failed: %s" % String(kernel.call("get_last_error"))
		)

	var budget_usec: int = 0
	var deadline_usec: int = int(limits.get("deadline_usec", 0))
	if deadline_usec > 0:
		budget_usec = maxi(deadline_usec - Time.get_ticks_usec(), 1)
	elif float(limits.get("budget_seconds", 0.0)) > 0.0:
		budget_usec = maxi(int(float(limits["budget_seconds"]) * 1_000_000.0), 1)
	var native_progress_callback: Callable = Callable()
	if on_progress.is_valid():
		native_progress_callback = func(snapshot: Dictionary) -> void:
			var converted: Dictionary = snapshot.duplicate(true)
			converted["action"] = _action_from_native(
				snapshot.get("action", {}) as Dictionary
			)
			on_progress.call(converted)
	var native_result: Dictionary = kernel.call(
		"search_iterative_depth",
		root_owner,
		maxi(int(limits.get("max_depth", 0)), 0),
		budget_usec,
		maxi(int(limits.get("max_nodes", 0)), 0),
		maxi(int(limits.get("min_completed_depth", 0)), 0),
		StringName(limits.get("depth_mode", &"complete_round")),
		should_cancel,
		native_progress_callback,
		bool(limits.get("use_internal_pv_ordering", false)),
		bool(limits.get("use_history_ordering", false)),
		bool(limits.get(
			"collect_search_diagnostics",
			limits.get("collect_timings", false)
		)),
		bool(limits.get("use_transposition_table", false)),
		maxi(int(limits.get("transposition_table_mib", 0)), 0),
		bool(limits.get("include_deck_evaluation", false)),
		bool(limits.get("include_danger_evaluation", false)),
		bool(limits.get("include_tempo_evaluation", false))
	) as Dictionary
	if not bool(native_result.get("supported", false)):
		return _search_integration_failure(
			"Native search does not support the reachable tree: %s"
			% String(native_result.get("reason", ""))
		)
	var action: ActionData = _action_from_native(native_result.get("action", {}) as Dictionary)
	native_result["action"] = action
	var converted_snapshots: Array[Dictionary] = []
	for snapshot_value: Variant in native_result.get("depth_snapshots", []):
		if not snapshot_value is Dictionary:
			continue
		var snapshot: Dictionary = (snapshot_value as Dictionary).duplicate(true)
		snapshot["action"] = _action_from_native(snapshot.get("action", {}) as Dictionary)
		converted_snapshots.append(snapshot)
	native_result["depth_snapshots"] = converted_snapshots
	var converted_principal_actions: Array[ActionData] = []
	for action_value: Variant in native_result.get("principal_actions", []):
		if action_value is Dictionary:
			converted_principal_actions.append(_action_from_native(action_value as Dictionary))
	native_result["principal_actions"] = converted_principal_actions
	native_result["elapsed_seconds"] = float(native_result.get("elapsed_usec", 0)) / 1_000_000.0
	native_result["has_completed_depth"] = (
		bool(native_result.get("valid", false))
		and int(native_result.get("completed_depth", 0)) > 0
		and action.action_type != &""
	)
	return native_result


static func _action_from_native(value: Dictionary) -> ActionData:
	if value.is_empty():
		return ActionData.new()
	return ActionData.new(
		StringName(value.get("action_type", &"")),
		StringName(value.get("source_zone", &"")),
		int(value.get("source_index", -1)),
		StringName(value.get("source_instance_id", &"")),
		StringName(value.get("target_kind", &"")),
		int(value.get("target_index", -1)),
		int(value.get("activation_index", 0))
	)


static func _action_to_native(action: ActionData) -> Dictionary:
	return {
		"action_type": action.action_type,
		"source_zone": action.source_zone,
		"source_index": action.source_index,
		"source_instance_id": action.source_instance_id,
		"target_kind": action.target_kind,
		"target_index": action.target_index,
		"activation_index": action.activation_index,
	}


static func _load_query_kernel(state: StateData, operation_name: String) -> Object:
	if state == null:
		push_error("NATIVE_DUEL_QUERY_INTEGRATION_ERROR: %s received a null state" % operation_name)
		return null
	if not ClassDB.class_exists(KERNEL_CLASS):
		push_error("NATIVE_DUEL_QUERY_INTEGRATION_ERROR: DuelNativeCompactKernel is unavailable")
		return null
	var compact := CompactState.new()
	if not compact.capture_state(state) or not compact.is_structurally_valid():
		push_error("NATIVE_DUEL_QUERY_INTEGRATION_ERROR: Duel state could not cross the compact native boundary")
		return null
	var kernel: Object = ClassDB.instantiate(KERNEL_CLASS)
	if kernel == null:
		push_error("NATIVE_DUEL_QUERY_INTEGRATION_ERROR: DuelNativeCompactKernel could not be instantiated")
		return null
	if not bool(kernel.call("load_compact_payload", compact.to_variant_payload())):
		push_error(
			"NATIVE_DUEL_QUERY_INTEGRATION_ERROR: Native compact payload load failed: %s"
			% String(kernel.call("get_last_error"))
		)
		return null
	return kernel


static func _search_integration_failure(reason: String) -> Dictionary:
	push_error("NATIVE_DUEL_SEARCH_INTEGRATION_ERROR: %s" % reason)
	return {
		"supported": false,
		"valid": false,
		"action": ActionData.new(),
		"score": 0,
		"completed_depth": 0,
		"nodes": 0,
		"elapsed_seconds": 0.0,
		"completion_reason": &"native_integration_error",
		"has_completed_depth": false,
		"integration_error": true,
		"reason": reason,
	}


static func _integration_failure(state: StateData, reason: String) -> Dictionary:
	push_error("NATIVE_DUEL_RULES_INTEGRATION_ERROR: %s" % reason)
	return {
		"valid": false,
		"state": state,
		"captures": [],
		"exiles": [],
		"events": [],
		"integration_error": true,
		"reason": reason,
	}
