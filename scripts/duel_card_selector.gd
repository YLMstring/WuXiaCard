class_name DuelCardSelector
extends RefCounted

const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const StateData = preload("res://scripts/duel_state.gd")


static func snapshot(
	state: StateData,
	selector: Dictionary,
	source_instance_id: StringName,
	context: Dictionary = {}
) -> Array[StringName]:
	var selected: Array[StringName] = []
	if state == null or source_instance_id == &"":
		return selected
	var source: Dictionary = _resolve_source(state, source_instance_id, context)
	if source.is_empty():
		return selected
	var limit: int = int(selector.get("limit", 0))
	var required_count: int = int(selector.get("required_count", 0))
	var observed: Dictionary = {}
	for zone_value: Variant in selector.get("zones", []):
		var zone := StringName(zone_value)
		for candidate: Dictionary in _get_zone_candidates(
			state,
			zone,
			int(source.get("owner_id", 0))
		):
			var instance_id := StringName(
				(candidate.get("card", {}) as Dictionary).get("instance_id", &"")
			)
			if instance_id == &"" or observed.has(instance_id):
				continue
			observed[instance_id] = true
			if not conditions_match(
				state,
				candidate,
				source_instance_id,
				selector.get("conditions", []),
				context
			):
				continue
			selected.append(instance_id)
			if limit > 0 and selected.size() >= limit:
				if required_count > 0 and selected.size() != required_count:
					selected.clear()
				return selected
	if required_count > 0 and selected.size() != required_count:
		selected.clear()
	return selected


static func revalidate(
	state: StateData,
	instance_id: StringName,
	source_instance_id: StringName,
	conditions: Array,
	context: Dictionary = {}
) -> Dictionary:
	var candidate: Dictionary = locate_card(state, instance_id)
	if candidate.is_empty():
		return {}
	if not conditions_match(state, candidate, source_instance_id, conditions, context):
		return {}
	return candidate


static func conditions_match(
	state: StateData,
	candidate: Dictionary,
	source_instance_id: StringName,
	conditions: Array,
	context: Dictionary = {}
) -> bool:
	if state == null or candidate.is_empty():
		return false
	var selected_card: Dictionary = candidate.get("card", {})
	var selected_instance_id := StringName(selected_card.get("instance_id", &""))
	if selected_instance_id == &"":
		return false
	var source: Dictionary = _resolve_source(state, source_instance_id, context)
	if source.is_empty():
		return false
	for condition_value: Variant in conditions:
		if not condition_value is Dictionary:
			return false
		var condition: Dictionary = condition_value
		var condition_type := StringName(condition.get("type", &""))
		if condition_type == Catalog.CONDITION_SELECTED_CARD_IS_ALLY:
			if int(candidate.get("owner_id", 0)) != int(source.get("owner_id", 0)):
				return false
		elif condition_type == Catalog.CONDITION_SELECTED_CARD_IS_ENEMY:
			if int(candidate.get("owner_id", 0)) == int(source.get("owner_id", 0)):
				return false
		elif condition_type == Catalog.CONDITION_SELECTED_CARD_WEAPON_IS:
			if String(selected_card.get("weapon", "")) != String(condition.get("weapon", "")):
				return false
		elif condition_type == Catalog.CONDITION_SELECTED_CARD_IS_NOT_SOURCE:
			if selected_instance_id == source_instance_id:
				return false
		elif condition_type == Catalog.CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE:
			if (
				StringName(candidate.get("zone", &"")) != Catalog.CARD_ZONE_BOARD
				or StringName(source.get("zone", &"")) != Catalog.CARD_ZONE_BOARD
				or not _are_adjacent(
					int(candidate.get("index", -1)),
					int(source.get("index", -1))
				)
			):
				return false
		elif condition_type == Catalog.CONDITION_SELECTED_CARD_SURROUNDED_BY_ALLIES:
			if not _is_surrounded_by_source_allies(state, candidate, source):
				return false
		elif condition_type == Catalog.CONDITION_SELECTED_CARD_ORIGINAL_OWNER_IS_SELF:
			if int(selected_card.get("original_owner", 0)) != int(source.get("owner_id", 0)):
				return false
		elif condition_type == Catalog.CONDITION_SELECTED_CARD_FLIPPED_BY_CURRENT_ATTACK:
			if not _attack_flip_contains(
				context.get("attack_flips", []) as Array,
				selected_instance_id,
				int(source.get("owner_id", 0))
			):
				return false
		elif condition_type == Catalog.CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE:
			if not Rules.can_change_powers(selected_card):
				return false
		else:
			return false
	return true


static func _resolve_source(
	state: StateData,
	source_instance_id: StringName,
	context: Dictionary
) -> Dictionary:
	var live_source: Dictionary = locate_card(state, source_instance_id)
	if not live_source.is_empty():
		return live_source
	var snapshots_value: Variant = context.get("card_reference_snapshots", {})
	if not snapshots_value is Dictionary:
		return {}
	var snapshot_value: Variant = (snapshots_value as Dictionary).get(
		Catalog.CARD_REF_ABILITY_SOURCE,
		{}
	)
	if not snapshot_value is Dictionary:
		return {}
	var source_snapshot: Dictionary = snapshot_value
	if StringName(source_snapshot.get("instance_id", &"")) != source_instance_id:
		return {}
	var owner_id: int = int(source_snapshot.get("owner_id", 0))
	if owner_id not in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		return {}
	return {
		"zone": &"",
		"owner_id": owner_id,
		"index": -1,
		"card": {
			"instance_id": source_instance_id,
			"card_id": StringName(source_snapshot.get("card_id", &"")),
		},
	}


static func _attack_flip_contains(
	attack_flips: Array,
	instance_id: StringName,
	source_owner: int
) -> bool:
	for record_value: Variant in attack_flips:
		if (
			record_value is Dictionary
			and StringName((record_value as Dictionary).get("instance_id", &"")) == instance_id
			and int((record_value as Dictionary).get("previous_owner_id", 0)) != source_owner
		):
			return true
	return false


static func locate_card(state: StateData, instance_id: StringName) -> Dictionary:
	if state == null or instance_id == &"":
		return {}
	for cell: int in range(state.board.size()):
		var slot_value: Variant = state.board[cell]
		if slot_value == null:
			continue
		var slot: Dictionary = slot_value
		var card: Dictionary = slot.get("card", {})
		if StringName(card.get("instance_id", &"")) == instance_id:
			return {
				"zone": Catalog.CARD_ZONE_BOARD,
				"owner_id": int(slot.get("owner", 0)),
				"index": cell,
				"card": card,
			}
	for owner_id: int in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		var hand: Array = state.get_hand(owner_id)
		for hand_index: int in range(hand.size()):
			var card_value: Variant = hand[hand_index]
			if not card_value is Dictionary:
				continue
			var card: Dictionary = card_value
			if StringName(card.get("instance_id", &"")) == instance_id:
				return {
					"zone": Catalog.CARD_ZONE_HAND,
					"owner_id": owner_id,
					"index": hand_index,
					"card": card,
				}
	return {}


static func _get_zone_candidates(
	state: StateData,
	zone: StringName,
	source_owner: int
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if zone == Catalog.CARD_ZONE_HAND:
		var owner_order: Array[int] = [source_owner]
		var other_owner: int = (
			Rules.OPPONENT_OWNER
			if source_owner == Rules.PLAYER_OWNER
			else Rules.PLAYER_OWNER
		)
		if other_owner != source_owner:
			owner_order.append(other_owner)
		for owner_id: int in owner_order:
			var hand: Array = state.get_hand(owner_id)
			for hand_index: int in range(hand.size()):
				var card_value: Variant = hand[hand_index]
				if not card_value is Dictionary:
					continue
				candidates.append({
					"zone": Catalog.CARD_ZONE_HAND,
					"owner_id": owner_id,
					"index": hand_index,
					"card": card_value,
				})
	elif zone == Catalog.CARD_ZONE_BOARD:
		for cell: int in range(state.board.size()):
			var slot_value: Variant = state.board[cell]
			if slot_value == null:
				continue
			var slot: Dictionary = slot_value
			candidates.append({
				"zone": Catalog.CARD_ZONE_BOARD,
				"owner_id": int(slot.get("owner", 0)),
				"index": cell,
				"card": slot.get("card", {}),
			})
	return candidates


static func _are_adjacent(first_cell: int, second_cell: int) -> bool:
	for direction: int in range(4):
		if Rules.get_neighbor_index(first_cell, direction) == second_cell:
			return true
	return false


static func _is_surrounded_by_source_allies(
	state: StateData,
	candidate: Dictionary,
	source: Dictionary
) -> bool:
	if (
		StringName(candidate.get("zone", &"")) != Catalog.CARD_ZONE_BOARD
		or StringName(source.get("zone", &"")) != Catalog.CARD_ZONE_BOARD
	):
		return false
	var candidate_cell: int = int(candidate.get("index", -1))
	var source_owner: int = int(source.get("owner_id", 0))
	var neighbor_count: int = 0
	for direction: int in range(4):
		var neighbor_cell: int = Rules.get_neighbor_index(candidate_cell, direction)
		if neighbor_cell < 0:
			continue
		neighbor_count += 1
		var neighbor_value: Variant = state.board[neighbor_cell]
		if (
			neighbor_value == null
			or int((neighbor_value as Dictionary).get("owner", 0)) != source_owner
		):
			return false
	return neighbor_count > 0
