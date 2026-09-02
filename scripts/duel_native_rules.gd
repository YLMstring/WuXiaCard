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
		return _integration_failure(state, "Native rules rejected a GDScript-legal action: %s" % reason)
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


static func search_iterative(
	state: StateData,
	root_owner: int,
	limits: Dictionary,
	should_cancel: Callable = Callable()
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
	var native_result: Dictionary = kernel.call(
		"search_iterative_round_depth",
		root_owner,
		maxi(int(limits.get("max_depth", 0)), 0),
		budget_usec,
		maxi(int(limits.get("max_nodes", 0)), 0),
		maxi(int(limits.get("min_completed_depth", 0)), 0),
		should_cancel
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
