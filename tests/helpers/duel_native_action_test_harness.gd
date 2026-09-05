extends RefCounted

const NativeRules = preload("res://scripts/duel_native_rules.gd")


static func execute_actions(
	state,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	actions: Array,
	context: Dictionary,
	_attack_resolver: Callable = Callable(),
	_flip_resolver: Callable = Callable(),
	_summon_resolver: Callable = Callable(),
	_before_move_resolver: Callable = Callable(),
	_event_resolver: Callable = Callable()
) -> Dictionary:
	return NativeRules.execute_actions(
		state,
		source_cell,
		source_instance_id,
		expected_owner,
		actions,
		context
	)


static func resolve_normal_flip(
	state,
	_attacker_cell: int,
	_attacker_instance_id: StringName,
	target_cell: int,
	reason: StringName,
	new_owner: int,
	_event_resolver: Callable = Callable()
) -> Array[Dictionary]:
	if state == null or target_cell < 0 or target_cell >= state.board.size():
		return []
	var slot_value: Variant = state.board[target_cell]
	if not slot_value is Dictionary:
		return []
	var card: Dictionary = (slot_value as Dictionary).get("card", {})
	var result: Dictionary = NativeRules.resolve_non_attack_flip(
		state,
		StringName(card.get("instance_id", &"")),
		new_owner,
		reason
	)
	var events: Array[Dictionary] = []
	for event_value: Variant in result.get("events", []):
		if event_value is Dictionary:
			events.append(event_value as Dictionary)
	return events
