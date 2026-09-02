extends RefCounted

const ProductionSimulator = preload("res://scripts/duel_simulator.gd")
const NativeRules = preload("res://scripts/duel_native_rules.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const StateData = preload("res://scripts/duel_state.gd")
const ActionData = preload("res://scripts/duel_action.gd")

const MAX_ATTACKS_PER_OWNER_TURN: int = ProductionSimulator.MAX_ATTACKS_PER_OWNER_TURN


static func get_legal_actions(state: StateData) -> Array[ActionData]:
	return ProductionSimulator.get_legal_actions(state)


static func get_legal_actions_for_owner(state: StateData, owner_id: int) -> Array[ActionData]:
	return ProductionSimulator.get_legal_actions_for_owner(state, owner_id)


static func has_legal_action_for_owner(state: StateData, owner_id: int) -> bool:
	return ProductionSimulator.has_legal_action_for_owner(state, owner_id)


static func is_action_legal(state: StateData, action: ActionData) -> bool:
	return ProductionSimulator.is_action_legal(state, action)


static func is_terminal(state: StateData) -> bool:
	return ProductionSimulator.is_terminal(state)


static func get_board_repetition_signature(board: Array) -> String:
	return ProductionSimulator.get_board_repetition_signature(board)


static func apply_action(state: StateData, action: ActionData) -> Dictionary:
	_ensure_runtime_instance_ids(state)
	return ProductionSimulator.apply_action(state, action)


static func choose_greedy_action(state: StateData) -> ActionData:
	_ensure_runtime_instance_ids(state)
	return ProductionSimulator.choose_greedy_action(state)


static func resolve_non_attack_flip(
	state: StateData,
	target_instance_id: StringName,
	new_owner: int,
	reason: StringName = &"non_attack_flip"
) -> Dictionary:
	_ensure_runtime_instance_ids(state)
	return NativeRules.resolve_non_attack_flip(
		state,
		target_instance_id,
		new_owner,
		reason
	)


static func _resolve_attack_request(
	state: StateData,
	request: Dictionary
) -> Dictionary:
	_ensure_runtime_instance_ids(state)
	return NativeRules.resolve_attack(state, request)


static func _resolve_attack_target(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	target_cell: int,
	target_instance_id: StringName,
	reason: StringName,
	attack_policy: Dictionary = {}
) -> Dictionary:
	_ensure_runtime_instance_ids(state)
	var source_owner: int = int((state.board[source_cell] as Dictionary).get("owner", 0)) \
		if source_cell >= 0 and source_cell < state.board.size() and state.board[source_cell] is Dictionary \
		else 0
	var target_owner: int = int((state.board[target_cell] as Dictionary).get("owner", 0)) \
		if target_cell >= 0 and target_cell < state.board.size() and state.board[target_cell] is Dictionary \
		else 0
	return NativeRules.resolve_attack(state, {
		"mode": &"targeted",
		"source_cell": source_cell,
		"source_instance_id": source_instance_id,
		"source_owner_id": source_owner,
		"target_cell": target_cell,
		"target_instance_id": target_instance_id,
		"target_owner_id": target_owner,
		"reason": reason,
		"attack_policy": attack_policy,
	})


static func _resolve_before_move_request(
	state: StateData,
	request: Dictionary
) -> Dictionary:
	_ensure_runtime_instance_ids(state)
	return NativeRules.resolve_event(
		state,
		StringName(request.get("movement_event", &"card_before_moved")),
		request
	)


static func _resolve_standard_attacks(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	reason: StringName,
	repeat_attack: bool = false,
	requested_policy: Dictionary = {}
) -> Dictionary:
	_ensure_runtime_instance_ids(state)
	var source_owner: int = int((state.board[source_cell] as Dictionary).get("owner", 0)) \
		if source_cell >= 0 and source_cell < state.board.size() and state.board[source_cell] is Dictionary \
		else 0
	return NativeRules.resolve_attack(state, {
		"mode": &"standard",
		"source_cell": source_cell,
		"source_instance_id": source_instance_id,
		"source_owner_id": source_owner,
		"reason": reason,
		"repeat_attack": repeat_attack,
		"attack_policy": requested_policy,
	})


static func _resolve_trigger_event(
	state: StateData,
	event_id: StringName,
	context: Dictionary
) -> Dictionary:
	_ensure_runtime_instance_ids(state)
	return NativeRules.resolve_event(state, event_id, context)


static func _ensure_runtime_instance_ids(state: StateData) -> void:
	if state == null:
		return
	var used: Dictionary = {}
	_collect_existing_ids(state, used)
	for cell_index: int in range(state.board.size()):
		var slot_value: Variant = state.board[cell_index]
		if slot_value is Dictionary:
			var slot: Dictionary = slot_value as Dictionary
			_assign_if_missing(
				slot.get("card", {}) as Dictionary,
				"board_%d" % cell_index,
				int(slot.get("owner", 0)),
				used
			)
	for owner_id: int in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		_assign_zone(state.get_hand(owner_id), "hand_%d" % owner_id, owner_id, used)
		_assign_zone(
			state.decks.get(owner_id, []) as Array,
			"deck_%d" % owner_id,
			owner_id,
			used
		)
		_assign_zone(
			state.discard_piles.get(owner_id, []) as Array,
			"discard_%d" % owner_id,
			owner_id,
			used
		)
		_assign_zone(
			state.removed_cards.get(owner_id, []) as Array,
			"removed_%d" % owner_id,
			owner_id,
			used
		)


static func _collect_existing_ids(state: StateData, used: Dictionary) -> void:
	for slot_value: Variant in state.board:
		if slot_value is Dictionary:
			_collect_card_id((slot_value as Dictionary).get("card", {}) as Dictionary, used)
	for owner_id: int in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		for zone: Array in [
			state.get_hand(owner_id),
			state.decks.get(owner_id, []) as Array,
			state.discard_piles.get(owner_id, []) as Array,
			state.removed_cards.get(owner_id, []) as Array,
		]:
			for card_value: Variant in zone:
				if card_value is Dictionary:
					_collect_card_id(card_value as Dictionary, used)


static func _collect_card_id(card: Dictionary, used: Dictionary) -> void:
	var instance_id := StringName(card.get("instance_id", &""))
	if instance_id != &"":
		used[instance_id] = true


static func _assign_zone(
	zone: Array,
	prefix: String,
	owner_id: int,
	used: Dictionary
) -> void:
	for index: int in range(zone.size()):
		var card_value: Variant = zone[index]
		if card_value is Dictionary:
			_assign_if_missing(
				card_value as Dictionary,
				"%s_%d" % [prefix, index],
				owner_id,
				used
			)


static func _assign_if_missing(
	card: Dictionary,
	prefix: String,
	owner_id: int,
	used: Dictionary
) -> void:
	if card.is_empty():
		return
	var resolved_owner: int = int(card.get("original_owner", 0))
	if resolved_owner not in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		resolved_owner = owner_id
		card["original_owner"] = resolved_owner
	if not card.has("ki"):
		card["ki"] = 0
	var normalized_abilities: Array = []
	for ability_value: Variant in card.get("active_abilities", []):
		if ability_value is Dictionary:
			normalized_abilities.append(Catalog.normalize_ability(ability_value as Dictionary))
	card["active_abilities"] = normalized_abilities
	if not card.has("revealed_to_owner_ids") or (
		(card.get("revealed_to_owner_ids", []) as Array).is_empty()
		and resolved_owner in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]
	):
		card["revealed_to_owner_ids"] = [resolved_owner]
	if StringName(card.get("instance_id", &"")) == &"":
		var suffix: String = String(card.get("card_id", &"card"))
		var candidate := StringName("test_%s_%s" % [prefix, suffix])
		var collision_index: int = 2
		while used.has(candidate):
			candidate = StringName("test_%s_%s_%d" % [prefix, suffix, collision_index])
			collision_index += 1
		card["instance_id"] = candidate
		used[candidate] = true
