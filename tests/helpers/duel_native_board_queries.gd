extends RefCounted

const NativeRules = preload("res://scripts/duel_native_rules.gd")
const State = preload("res://scripts/duel_state.gd")


static func get_would_flip_indices(
	board: Array,
	source_cell: int,
	context: Dictionary = {}
) -> Array[int]:
	return NativeRules.get_attack_targets(
		State.new(board), source_cell, _attack_policy(context)
	)


static func can_attack_target(
	board: Array,
	source_cell: int,
	target_cell: int,
	context: Dictionary = {}
) -> bool:
	return NativeRules.can_attack_target(
		State.new(board),
		source_cell,
		target_cell,
		_attack_policy(context),
		bool(context.get("skip_power_comparison", false))
	)


static func is_target_in_attack_range(
	board: Array,
	source_cell: int,
	target_cell: int,
	context: Dictionary = {}
) -> bool:
	return NativeRules.is_target_in_attack_range(
		State.new(board),
		source_cell,
		target_cell,
		_attack_policy(context),
		bool(context.get("skip_power_comparison", false))
	)


static func _attack_policy(context: Dictionary) -> Dictionary:
	var policy: Dictionary = {}
	for key: String in ["attack_target_policy", "capture_owner_id"]:
		if context.has(key):
			policy[key] = context[key]
	return policy
