class_name DuelAbilityExecutor
extends RefCounted

const MAX_HAND_SIZE: int = 5

const Abilities = preload("res://scripts/duel_abilities.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Selector = preload("res://scripts/duel_card_selector.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Revelation = preload("res://scripts/duel_revelation.gd")
const StateData = preload("res://scripts/duel_state.gd")


static func can_pay_costs(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	costs: Array
) -> bool:
	if state == null:
		return false
	var source_slot: Dictionary = _get_card_slot(state, source_cell, source_instance_id)
	if source_slot.is_empty():
		return false
	var source_card: Dictionary = source_slot.get("card", {})
	var required_ki: int = 0
	for cost_value: Variant in costs:
		if not cost_value is Dictionary:
			return false
		var cost: Dictionary = cost_value
		var cost_type := StringName(cost.get("type", &""))
		if cost_type != Catalog.ACTION_SPEND_KI:
			return false
		var amount: int = int(cost.get("amount", 0))
		if amount <= 0:
			return false
		required_ki += amount
	return int(source_card.get("ki", 0)) >= required_ki


static func execute_activation(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	activation: Dictionary,
	target_kind: StringName,
	target_index: int,
	attack_resolver: Callable = Callable(),
	flip_resolver: Callable = Callable(),
	summon_resolver: Callable = Callable(),
	before_move_resolver: Callable = Callable()
) -> Dictionary:
	var empty_result: Dictionary = _empty_result()
	empty_result["valid"] = false
	if state == null:
		return empty_result
	var source_slot: Dictionary = _get_card_slot(state, source_cell, source_instance_id)
	if source_slot.is_empty():
		return empty_result
	var costs: Array = activation.get("costs", [])
	if not can_pay_costs(state, source_cell, source_instance_id, costs):
		return empty_result
	var owner_id: int = int(source_slot.get("owner", 0))
	var context: Dictionary = {
		"target_kind": target_kind,
		"target_index": target_index,
	}
	if target_kind == &"board_cell" and target_index >= 0 and target_index < state.board.size():
		var target_value: Variant = state.board[target_index]
		if target_value is Dictionary:
			context["selected_card_instance_id"] = StringName(
				((target_value as Dictionary).get("card", {}) as Dictionary).get("instance_id", &"")
			)
	var events: Array[Dictionary] = [{
		"type": &"ability_activated",
		"source_cell": source_cell,
		"target_cell": target_index,
		"owner_id": owner_id,
		"instance_id": source_instance_id,
	}]
	var cost_result: Dictionary = execute_actions(
		state,
		source_cell,
		source_instance_id,
		owner_id,
		costs,
		context,
		attack_resolver,
		flip_resolver,
		summon_resolver,
		before_move_resolver
	)
	events.append_array(cost_result.get("events", []) as Array)
	var action_result: Dictionary = execute_actions(
		state,
		int(cost_result.get("source_cell", source_cell)),
		source_instance_id,
		owner_id,
		activation.get("actions", []) as Array,
		context,
		attack_resolver,
		flip_resolver,
		summon_resolver,
		before_move_resolver
	)
	events.append_array(action_result.get("events", []) as Array)
	return {
		"valid": true,
		"events": events,
		"attack_requests": action_result.get("attack_requests", []),
		"flip_requests": action_result.get("flip_requests", []),
		"summon_requests": action_result.get("summon_requests", []),
		"extra_turn_requests": action_result.get("extra_turn_requests", []),
		"flip_prevention_requests": action_result.get("flip_prevention_requests", []),
		"captures": (
			(cost_result.get("captures", []) as Array)
			+ (action_result.get("captures", []) as Array)
		),
		"exiles": (
			(cost_result.get("exiles", []) as Array)
			+ (action_result.get("exiles", []) as Array)
		),
		"source_cell": int(action_result.get("source_cell", source_cell)),
		"result": action_result.get("result", Catalog.ACTION_RESULT_APPLIED),
	}


static func execute_actions(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	actions: Array,
	context: Dictionary,
	attack_resolver: Callable = Callable(),
	flip_resolver: Callable = Callable(),
	summon_resolver: Callable = Callable(),
	before_move_resolver: Callable = Callable()
) -> Dictionary:
	var result: Dictionary = _empty_result()
	result["source_cell"] = source_cell
	if state == null:
		return result
	var action_context: Dictionary = context.duplicate(true)
	if not action_context.has("ability_source_instance_id"):
		action_context["ability_source_instance_id"] = source_instance_id
		action_context["ability_source_owner_id"] = expected_owner
	if not action_context.has("card_reference_snapshots"):
		action_context["card_reference_snapshots"] = {}
	var reference_snapshots: Dictionary = action_context["card_reference_snapshots"] as Dictionary
	if not reference_snapshots.has(Catalog.CARD_REF_ABILITY_SOURCE):
		reference_snapshots[Catalog.CARD_REF_ABILITY_SOURCE] = _snapshot_card_reference(
			state,
			StringName(action_context.get("ability_source_instance_id", source_instance_id))
		)
	if not reference_snapshots.has(Catalog.CARD_REF_SELECTED_CARD):
		var selected_instance_id := StringName(action_context.get("selected_card_instance_id", &""))
		if selected_instance_id != &"":
			reference_snapshots[Catalog.CARD_REF_SELECTED_CARD] = _snapshot_card_reference(
				state,
				selected_instance_id
			)
	var current_source_cell: int = source_cell
	for action_value: Variant in actions:
		if not action_value is Dictionary:
			continue
		var declaration: Dictionary = action_value
		var action_result: Dictionary = _execute_action(
			state,
			current_source_cell,
			source_instance_id,
			expected_owner,
			declaration,
			action_context,
			attack_resolver,
			flip_resolver,
			summon_resolver,
			before_move_resolver
		)
		result["events"].append_array(action_result.get("events", []) as Array)
		result["captures"].append_array(action_result.get("captures", []) as Array)
		result["exiles"].append_array(action_result.get("exiles", []) as Array)
		result["extra_turn_requests"].append_array(action_result.get("extra_turn_requests", []) as Array)
		result["flip_prevention_requests"].append_array(action_result.get("flip_prevention_requests", []) as Array)
		for request_value: Variant in action_result.get("attack_requests", []):
			if not request_value is Dictionary:
				continue
			if not attack_resolver.is_valid():
				result["attack_requests"].append(request_value)
				continue
			var resolution_value: Variant = attack_resolver.call(request_value as Dictionary)
			if not resolution_value is Dictionary:
				continue
			var resolution: Dictionary = resolution_value
			result["events"].append_array(resolution.get("events", []) as Array)
			result["captures"].append_array(resolution.get("captures", []) as Array)
			result["exiles"].append_array(resolution.get("exiles", []) as Array)
			result["extra_turn_requests"].append_array(
				resolution.get("extra_turn_requests", []) as Array
			)
			result["flip_prevention_requests"].append_array(
				resolution.get("flip_prevention_requests", []) as Array
			)
		for request_value: Variant in action_result.get("flip_requests", []):
			if not request_value is Dictionary:
				continue
			if not flip_resolver.is_valid():
				result["flip_requests"].append(request_value)
				continue
			var flip_resolution_value: Variant = flip_resolver.call(request_value as Dictionary)
			if not flip_resolution_value is Dictionary:
				continue
			var flip_resolution: Dictionary = flip_resolution_value
			result["events"].append_array(flip_resolution.get("events", []) as Array)
			result["captures"].append_array(flip_resolution.get("captures", []) as Array)
			result["exiles"].append_array(flip_resolution.get("exiles", []) as Array)
			result["extra_turn_requests"].append_array(
				flip_resolution.get("extra_turn_requests", []) as Array
			)
			result["flip_prevention_requests"].append_array(
				flip_resolution.get("flip_prevention_requests", []) as Array
			)
		for request_value: Variant in action_result.get("summon_requests", []):
			if not request_value is Dictionary:
				continue
			if not summon_resolver.is_valid():
				result["summon_requests"].append(request_value)
				continue
			var summon_resolution_value: Variant = summon_resolver.call(
				request_value as Dictionary
			)
			if not summon_resolution_value is Dictionary:
				continue
			var summon_resolution: Dictionary = summon_resolution_value
			result["events"].append_array(summon_resolution.get("events", []) as Array)
			result["captures"].append_array(summon_resolution.get("captures", []) as Array)
			result["exiles"].append_array(summon_resolution.get("exiles", []) as Array)
			result["extra_turn_requests"].append_array(
				summon_resolution.get("extra_turn_requests", []) as Array
			)
			result["flip_prevention_requests"].append_array(
				summon_resolution.get("flip_prevention_requests", []) as Array
			)
		current_source_cell = int(action_result.get("source_cell", current_source_cell))
		var action_status := StringName(action_result.get("result", Catalog.ACTION_RESULT_NO_EFFECT))
		if action_status == Catalog.ACTION_RESULT_INVALID_CONTEXT:
			result["result"] = Catalog.ACTION_RESULT_INVALID_CONTEXT
			break
		if (
			action_status == Catalog.ACTION_RESULT_NO_EFFECT
			and StringName(declaration.get("on_invalid_context", &"")) == Catalog.STOP_RULE
		):
			result["result"] = Catalog.ACTION_RESULT_INVALID_CONTEXT
			break
		if action_status == Catalog.ACTION_RESULT_APPLIED:
			result["result"] = Catalog.ACTION_RESULT_APPLIED
	result["source_cell"] = current_source_cell
	return result


static func resolve_normal_flip(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	target_cell: int,
	target_instance_id: StringName,
	new_owner: int
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var target_slot: Dictionary = _get_card_slot(state, target_cell, target_instance_id)
	if target_slot.is_empty():
		return events
	if (
		source_instance_id != &""
		and _get_card_slot(
			state,
			source_cell,
			source_instance_id,
			new_owner
		).is_empty()
	):
		return events
	if int(target_slot.get("owner", 0)) == new_owner:
		return events
	var target_card: Dictionary = target_slot.get("card", {})
	target_slot["owner"] = new_owner
	events.append({
		"type": &"card_flipped",
		"source_cell": source_cell,
		"target_cell": target_cell,
		"owner_id": new_owner,
		"instance_id": target_instance_id,
	})
	var removed_count: int = Abilities.remove_non_retained_abilities(target_card)
	for _removed_index: int in range(removed_count):
		events.append({
			"type": &"ability_lost",
			"source_cell": source_cell,
			"target_cell": target_cell,
			"owner_id": new_owner,
			"instance_id": target_instance_id,
		})
	return events


static func _execute_action(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	declaration: Dictionary,
	context: Dictionary,
	attack_resolver: Callable,
	flip_resolver: Callable,
	summon_resolver: Callable,
	before_move_resolver: Callable
) -> Dictionary:
	var action_type := StringName(declaration.get("type", &""))
	if action_type == Catalog.ACTION_FOR_EACH_SELECTED_CARD:
		return _for_each_selected_card(
			state,
			source_cell,
			declaration,
			context,
			attack_resolver,
			flip_resolver,
			summon_resolver,
			before_move_resolver
		)
	if action_type == Catalog.ACTION_DRAW_CARDS:
		return _draw_cards(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			int(declaration.get("amount", 0))
		)
	if action_type == Catalog.ACTION_EXILE_ATTACKED_CARD:
		return _exile_attacked_card(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			context
		)
	if action_type == Catalog.ACTION_TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES:
		return _temporarily_remove_non_retained_abilities(
			state,
			source_cell,
			source_instance_id,
			expected_owner
		)
	if action_type == Catalog.ACTION_ATTACK_TRIGGER_CARD:
		return _request_trigger_attack(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			context
		)
	if action_type == Catalog.ACTION_GAIN_KI:
		return _change_ki(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			int(declaration.get("amount", 0)),
			action_type
		)
	if action_type == Catalog.ACTION_ADD_POWERS:
		var power_instance_id: StringName = source_instance_id
		var power_owner: int = expected_owner
		if StringName(declaration.get("target", &"")) == Catalog.ACTION_TARGET_ABILITY_SOURCE:
			power_instance_id = StringName(context.get("ability_source_instance_id", &""))
			power_owner = int(context.get("ability_source_owner_id", 0))
		return _add_powers(
			state,
			source_cell,
			power_instance_id,
			power_owner,
			int(declaration.get("amount", 0))
		)
	if action_type == Catalog.ACTION_ADD_CARD_TO_HAND:
		return _add_card_to_hand(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			StringName(declaration.get("card_id", &"")),
			StringName(declaration.get("recipient", &""))
		)
	if action_type == Catalog.ACTION_REVEAL_HAND_CARDS:
		return _reveal_hand_cards(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			StringName(declaration.get("recipient", &"")),
			StringName(declaration.get("filter", &""))
		)
	if action_type == Catalog.ACTION_ENABLE_FUTURE_DRAW_REVEAL:
		return _enable_future_draw_reveal(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			StringName(declaration.get("recipient", &""))
		)
	if action_type == Catalog.ACTION_GRANT_TRIGGER_CARD_ABILITY:
		return _grant_trigger_card_ability(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			declaration.get("ability", {}) as Dictionary,
			context
		)
	if action_type == Catalog.ACTION_GRANT_ABILITY_TO_SELF:
		return _grant_ability_to_self(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			declaration.get("ability", {}) as Dictionary
		)
	if action_type == Catalog.ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE:
		return _self_swapped_with_ability_source(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			context,
			before_move_resolver
		)
	if action_type == Catalog.ACTION_PREVENT_TRIGGER_FLIP:
		return _prevent_trigger_flip(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			context
		)
	if action_type == Catalog.ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY:
		return _move_self_to_first_adjacent_empty(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			before_move_resolver
		)
	if action_type == Catalog.ACTION_REMOVE_THIS_ABILITY:
		return _remove_this_ability(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			context
		)
	if action_type == Catalog.ACTION_FLIP_SELF:
		return _request_flip_self(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			StringName(declaration.get("new_owner", &"")),
			context
		)
	if action_type == Catalog.ACTION_RETURN_CARD_TO_HAND:
		return _return_card_to_hand(
			state,
			source_cell,
			StringName(declaration.get("card", &"")),
			StringName(declaration.get("recipient", &"")),
			context
		)
	if action_type == Catalog.ACTION_SUMMON_CARD:
		return _request_summon_card(
			state,
			source_cell,
			declaration,
			context
		)
	if action_type == Catalog.ACTION_EXILE_SELF:
		return _exile_self(
			state,
			source_cell,
			source_instance_id,
			expected_owner
		)
	if action_type == Catalog.ACTION_RESUMMON_TRIGGER_CARD_IN_PLACE:
		return _request_trigger_card_resummon(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			context
		)
	if action_type == Catalog.ACTION_SPEND_KI:
		return _change_ki(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			-int(declaration.get("amount", 0)),
			action_type
		)
	if action_type == Catalog.ACTION_SPEND_ALL_KI:
		return _spend_all_ki(
			state,
			source_cell,
			source_instance_id,
			expected_owner
		)
	if action_type == Catalog.ACTION_GRANT_EXTRA_CARD_PLAY:
		return _grant_extra_card_play(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			int(declaration.get("amount", 0))
		)
	if action_type == Catalog.ACTION_MOVE_SELF_TO_TARGET:
		return _move_self(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			context,
			before_move_resolver
		)
	if action_type == Catalog.ACTION_MOVE_SELF_TO_FIRST_EMPTY_BETWEEN_ENEMY:
		return _move_self_to_first_empty_between_enemy(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			before_move_resolver
		)
	if action_type == Catalog.ACTION_SWAP_SELF_WITH_TARGET:
		return _swap_self_with_target(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			context,
			before_move_resolver
		)
	if action_type == Catalog.ACTION_STANDARD_ATTACK_WITH_SELF:
		return _request_standard_attack(
			state,
			source_cell,
			source_instance_id,
			expected_owner
		)
	return _no_effect(source_cell)


static func _for_each_selected_card(
	state: StateData,
	source_cell: int,
	declaration: Dictionary,
	context: Dictionary,
	attack_resolver: Callable,
	flip_resolver: Callable,
	summon_resolver: Callable,
	before_move_resolver: Callable
) -> Dictionary:
	var result: Dictionary = _empty_result()
	result["source_cell"] = source_cell
	var source_instance_id := StringName(context.get("ability_source_instance_id", &""))
	var selector: Dictionary = declaration.get("selector", {})
	var conditions: Array = selector.get("conditions", [])
	var selected_ids: Array[StringName] = Selector.snapshot(
		state,
		selector,
		source_instance_id,
		context
	)
	for selected_instance_id: StringName in selected_ids:
		var selected: Dictionary = Selector.revalidate(
			state,
			selected_instance_id,
			source_instance_id,
			conditions,
			context
		)
		if selected.is_empty():
			continue
		var selected_cell: int = (
			int(selected.get("index", -1))
			if StringName(selected.get("zone", &"")) == Catalog.CARD_ZONE_BOARD
			else -1
		)
		var nested_context: Dictionary = context.duplicate(true)
		nested_context["selected_card_conditions"] = conditions.duplicate(true)
		nested_context["selected_card_instance_id"] = selected_instance_id
		var nested_snapshots: Dictionary = nested_context.get(
			"card_reference_snapshots",
			{}
		) as Dictionary
		nested_snapshots[Catalog.CARD_REF_SELECTED_CARD] = _snapshot_card_reference(
			state,
			selected_instance_id
		)
		nested_context["card_reference_snapshots"] = nested_snapshots
		var nested_result: Dictionary = execute_actions(
			state,
			selected_cell,
			selected_instance_id,
			int(selected.get("owner_id", 0)),
			declaration.get("actions", []) as Array,
			nested_context,
			attack_resolver,
			flip_resolver,
			summon_resolver,
			before_move_resolver
		)
		result["events"].append_array(nested_result.get("events", []) as Array)
		result["captures"].append_array(nested_result.get("captures", []) as Array)
		result["exiles"].append_array(nested_result.get("exiles", []) as Array)
		result["attack_requests"].append_array(
			nested_result.get("attack_requests", []) as Array
		)
		result["flip_requests"].append_array(
			nested_result.get("flip_requests", []) as Array
		)
		result["summon_requests"].append_array(
			nested_result.get("summon_requests", []) as Array
		)
		result["extra_turn_requests"].append_array(
			nested_result.get("extra_turn_requests", []) as Array
		)
		result["flip_prevention_requests"].append_array(
			nested_result.get("flip_prevention_requests", []) as Array
		)
		var nested_status := StringName(
			nested_result.get("result", Catalog.ACTION_RESULT_NO_EFFECT)
		)
		if nested_status == Catalog.ACTION_RESULT_INVALID_CONTEXT:
			result["result"] = Catalog.ACTION_RESULT_INVALID_CONTEXT
			return result
		if nested_status == Catalog.ACTION_RESULT_APPLIED:
			result["result"] = Catalog.ACTION_RESULT_APPLIED
		var current_ability_source: Dictionary = Selector.locate_card(
			state,
			source_instance_id
		)
		if StringName(current_ability_source.get("zone", &"")) == Catalog.CARD_ZONE_BOARD:
			result["source_cell"] = int(current_ability_source.get("index", result["source_cell"]))
	return result


static func _temporarily_remove_non_retained_abilities(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int
) -> Dictionary:
	var subject: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if subject.is_empty():
		return _no_effect(source_cell)
	var card: Dictionary = subject.get("card", {})
	var removed_entries: Array[Dictionary] = (
		Abilities.temporarily_remove_non_retained_abilities(card, state.owner_turn_serial)
	)
	if removed_entries.is_empty():
		return _no_effect(source_cell)
	var location_cell: int = _get_location_cell(subject)
	var events: Array[Dictionary] = []
	for _entry: Dictionary in removed_entries:
		events.append({
			"type": &"ability_lost",
			"source_cell": source_cell,
			"target_cell": location_cell,
			"owner_id": int(subject.get("owner_id", 0)),
			"instance_id": source_instance_id,
			"zone": StringName(subject.get("zone", &"")),
			"logical_index": int(subject.get("index", -1)),
			"temporary": true,
		})
	return _applied(source_cell, events)


static func _draw_cards(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	requested_count: int
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if source.is_empty() or requested_count <= 0:
		return _no_effect(source_cell)
	var owner_id: int = int(source.get("owner_id", 0))
	var hand: Array = state.get_hand(owner_id)
	var deck: Array = state.decks.get(owner_id, [])
	var actual_count: int = mini(requested_count, mini(MAX_HAND_SIZE - hand.size(), deck.size()))
	var events: Array[Dictionary] = []
	for _draw_index: int in range(maxi(actual_count, 0)):
		var drawn_card: Dictionary = deck.pop_front()
		hand.append(drawn_card)
		events.append({
			"type": &"card_drawn",
			"source_cell": source_cell,
			"owner_id": owner_id,
			"card_id": StringName(drawn_card.get("card_id", &"")),
			"instance_id": StringName(drawn_card.get("instance_id", &"")),
			"logical_hand_index": hand.size() - 1,
		})
		for observer_value: Variant in Revelation.get_future_draw_audiences(state, owner_id):
			var observer_owner_id: int = int(observer_value)
			if Revelation.reveal_to(drawn_card, observer_owner_id):
				events.append({
					"type": &"card_revealed",
					"source_cell": source_cell,
					"owner_id": owner_id,
					"observer_owner_id": observer_owner_id,
					"card_id": StringName(drawn_card.get("card_id", &"")),
					"instance_id": StringName(drawn_card.get("instance_id", &"")),
					"logical_hand_index": hand.size() - 1,
				})
	return _applied(source_cell, events) if actual_count > 0 else _no_effect(source_cell)


static func _reveal_hand_cards(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	recipient: StringName,
	reveal_filter: StringName
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if source.is_empty() or recipient not in Catalog.KNOWN_RECIPIENTS or reveal_filter not in Catalog.KNOWN_REVEAL_FILTERS:
		return _no_effect(source_cell)
	var observer_owner_id: int = int(source.get("owner_id", 0))
	var hand_owner_id: int = _resolve_recipient_owner(observer_owner_id, recipient)
	var remembered: Array = Revelation.get_remembered_glyphs(state, observer_owner_id)
	var events: Array[Dictionary] = []
	var hand: Array = state.get_hand(hand_owner_id)
	for hand_index: int in range(hand.size()):
		var card: Dictionary = hand[hand_index]
		if reveal_filter == Catalog.REVEAL_FILTER_REMEMBERED and String(card.get("glyph", "")) not in remembered:
			continue
		if not Revelation.reveal_to(card, observer_owner_id):
			continue
		events.append({
			"type": &"card_revealed",
			"source_cell": source_cell,
			"owner_id": hand_owner_id,
			"observer_owner_id": observer_owner_id,
			"card_id": StringName(card.get("card_id", &"")),
			"instance_id": StringName(card.get("instance_id", &"")),
			"logical_hand_index": hand_index,
		})
	return _applied(source_cell, events) if not events.is_empty() else _no_effect(source_cell)


static func _enable_future_draw_reveal(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	recipient: StringName
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if source.is_empty() or recipient not in Catalog.KNOWN_RECIPIENTS:
		return _no_effect(source_cell)
	var observer_owner_id: int = int(source.get("owner_id", 0))
	var hand_owner_id: int = _resolve_recipient_owner(observer_owner_id, recipient)
	if not Revelation.enable_future_draw_reveal(state, hand_owner_id, observer_owner_id):
		return _no_effect(source_cell)
	return _applied(source_cell)


static func _grant_trigger_card_ability(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	ability: Dictionary,
	context: Dictionary
) -> Dictionary:
	if _get_subject(state, source_instance_id, expected_owner).is_empty() or ability.is_empty():
		return _no_effect(source_cell)
	var target_cell: int = int(context.get("trigger_cell", -1))
	var target_instance_id := StringName(context.get("trigger_instance_id", &""))
	var target_slot: Dictionary = _get_card_slot(state, target_cell, target_instance_id)
	if target_slot.is_empty():
		return _no_effect(source_cell)
	return _grant_ability_to_location(
		source_cell,
		source_instance_id,
		{
			"zone": Catalog.CARD_ZONE_BOARD,
			"owner_id": int(target_slot.get("owner", 0)),
			"index": target_cell,
			"card": target_slot.get("card", {}),
		},
		ability
	)


static func _grant_ability_to_self(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	ability: Dictionary
) -> Dictionary:
	var subject: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if subject.is_empty() or ability.is_empty():
		return _no_effect(source_cell)
	return _grant_ability_to_location(
		source_cell,
		source_instance_id,
		subject,
		ability
	)


static func _grant_ability_to_location(
	source_cell: int,
	source_instance_id: StringName,
	target: Dictionary,
	ability: Dictionary
) -> Dictionary:
	var target_card: Dictionary = target.get("card", {})
	var target_instance_id := StringName(target_card.get("instance_id", &""))
	if target_instance_id == &"":
		return _no_effect(source_cell)
	var normalized: Dictionary = Catalog.normalize_ability(ability)
	var active: Array = target_card.get("active_abilities", [])
	if normalized in active:
		return _no_effect(source_cell)
	if Abilities.is_activate_ability(normalized):
		Abilities.replace_activate_ability(target_card, normalized)
	else:
		active = active.duplicate(true)
		active.append(normalized)
		target_card["active_abilities"] = active
	return _applied(source_cell, [{
		"type": &"ability_gained",
		"source_cell": source_cell,
		"source_instance_id": source_instance_id,
		"target_cell": _get_location_cell(target),
		"owner_id": int(target.get("owner_id", 0)),
		"instance_id": target_instance_id,
		"zone": StringName(target.get("zone", &"")),
		"logical_index": int(target.get("index", -1)),
	}])


static func _prevent_trigger_flip(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	context: Dictionary
) -> Dictionary:
	if _get_subject(state, source_instance_id, expected_owner).is_empty():
		return _no_effect(source_cell)
	var target_instance_id := StringName(context.get("trigger_instance_id", &""))
	var new_owner_id: int = int(context.get("new_owner_id", 0))
	if target_instance_id == &"" or new_owner_id not in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		return _no_effect(source_cell)
	var result: Dictionary = _applied(source_cell)
	result["flip_prevention_requests"].append({
		"target_instance_id": target_instance_id,
		"new_owner_id": new_owner_id,
		"source_instance_id": source_instance_id,
		"source_cell": source_cell,
	})
	return result


static func _remove_this_ability(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	context: Dictionary
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if source.is_empty():
		return _no_effect(source_cell)
	var card: Dictionary = source.get("card", {})
	var abilities: Array = card.get("active_abilities", [])
	var ability_index: int = int(context.get("resolving_ability_index", -1))
	var snapshot: Dictionary = context.get("resolving_ability_snapshot", {})
	if ability_index < 0 or ability_index >= abilities.size() or abilities[ability_index] != snapshot:
		return _no_effect(source_cell)
	abilities = abilities.duplicate(true)
	abilities.remove_at(ability_index)
	card["active_abilities"] = abilities
	var current_cell: int = _get_location_cell(source)
	return _applied(current_cell, [{
		"type": &"ability_lost",
		"source_cell": current_cell,
		"target_cell": current_cell,
		"owner_id": int(source.get("owner_id", 0)),
		"instance_id": source_instance_id,
	}])


static func _resolve_recipient_owner(source_owner_id: int, recipient: StringName) -> int:
	if recipient == Catalog.RECIPIENT_OPPONENT:
		return Rules.OPPONENT_OWNER if source_owner_id == Rules.PLAYER_OWNER else Rules.PLAYER_OWNER
	return source_owner_id


static func _exile_attacked_card(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	context: Dictionary
) -> Dictionary:
	var source_slot: Dictionary = _get_card_slot(
		state,
		source_cell,
		source_instance_id,
		expected_owner
	)
	var target_cell: int = int(context.get("attacked_cell", -1))
	var target_instance_id := StringName(context.get("attacked_instance_id", &""))
	var target_slot: Dictionary = _get_card_slot(state, target_cell, target_instance_id)
	if source_slot.is_empty() or target_slot.is_empty():
		return _no_effect(source_cell)
	var target_card: Dictionary = target_slot.get("card", {})
	var original_owner: int = int(target_card.get("original_owner", 0))
	if original_owner not in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		original_owner = int(target_slot.get("owner", 0))
	if not state.removed_cards.has(original_owner):
		state.removed_cards[original_owner] = []
	(state.removed_cards[original_owner] as Array).append(target_card)
	state.board[target_cell] = null
	return _applied(source_cell, [{
		"type": &"card_exiled",
		"source_cell": source_cell,
		"target_cell": target_cell,
		"owner_id": int(source_slot.get("owner", 0)),
		"original_owner": original_owner,
		"instance_id": target_instance_id,
	}])


static func _request_trigger_attack(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	context: Dictionary
) -> Dictionary:
	var source_slot: Dictionary = _get_card_slot(
		state,
		source_cell,
		source_instance_id,
		expected_owner
	)
	var target_cell: int = int(context.get("trigger_cell", -1))
	var target_instance_id := StringName(context.get("trigger_instance_id", &""))
	var target_slot: Dictionary = _get_card_slot(state, target_cell, target_instance_id)
	if source_slot.is_empty() or target_slot.is_empty():
		return _no_effect(source_cell)
	if not Rules.can_attack_target(
		state.board,
		source_cell,
		target_cell,
		{"reason": &"card_summoned_reaction", "trigger_context": context}
	):
		return _no_effect(source_cell)
	var result: Dictionary = _applied(source_cell)
	result["attack_requests"].append({
		"mode": &"targeted",
		"source_cell": source_cell,
		"source_instance_id": source_instance_id,
		"source_owner_id": int(source_slot.get("owner", 0)),
		"target_cell": target_cell,
		"target_instance_id": target_instance_id,
		"target_owner_id": int(target_slot.get("owner", 0)),
		"reason": &"card_summoned_reaction",
	})
	return result


static func _change_ki(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	delta: int,
	reason: StringName
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if source.is_empty() or delta == 0:
		return _no_effect(source_cell)
	var card: Dictionary = source.get("card", {})
	var previous_ki: int = int(card.get("ki", 0))
	var resulting_ki: int = previous_ki + delta
	if resulting_ki < 0:
		return _no_effect(source_cell)
	card["ki"] = resulting_ki
	var current_cell: int = _get_location_cell(source)
	return _applied(source_cell, [_make_ki_event(
		current_cell,
		int(source.get("owner_id", 0)),
		source_instance_id,
		previous_ki,
		resulting_ki,
		reason,
		StringName(source.get("zone", &"")),
		int(source.get("index", -1))
	)])


static func _add_powers(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	amount: int
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if source.is_empty() or amount <= 0:
		return _no_effect(source_cell)
	var card: Dictionary = source.get("card", {})
	var previous_powers: Array = (card.get("powers", []) as Array).duplicate()
	if previous_powers.size() != 4:
		return _no_effect(source_cell)
	var resulting_powers: Array = previous_powers.duplicate()
	for power_index: int in range(resulting_powers.size()):
		resulting_powers[power_index] = int(resulting_powers[power_index]) + amount
	card["powers"] = resulting_powers
	var current_cell: int = _get_location_cell(source)
	return _applied(source_cell, [{
		"type": &"powers_changed",
		"source_cell": current_cell,
		"target_cell": current_cell,
		"owner_id": int(source.get("owner_id", 0)),
		"instance_id": source_instance_id,
		"previous_powers": previous_powers,
		"powers": resulting_powers.duplicate(),
		"change_reason": Catalog.ACTION_ADD_POWERS,
		"zone": StringName(source.get("zone", &"")),
		"logical_index": int(source.get("index", -1)),
	}])


static func _add_card_to_hand(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	card_id: StringName,
	recipient: StringName
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if (
		source.is_empty()
		or not Catalog.has_card(card_id)
		or recipient not in Catalog.KNOWN_RECIPIENTS
	):
		return _no_effect(source_cell)
	var source_owner: int = int(source.get("owner_id", 0))
	var recipient_owner: int = source_owner
	if recipient == Catalog.RECIPIENT_OPPONENT:
		recipient_owner = (
			Rules.OPPONENT_OWNER
			if source_owner == Rules.PLAYER_OWNER
			else Rules.PLAYER_OWNER
		)
	var hand: Array = state.get_hand(recipient_owner)
	if hand.size() >= MAX_HAND_SIZE:
		return _no_effect(source_cell)
	var instance_id: StringName = _make_generated_instance_id(state, card_id)
	var added_card: Dictionary = Catalog.create_instance(
		card_id,
		recipient_owner,
		instance_id
	)
	hand.append(added_card)
	return _applied(source_cell, [{
		"type": &"card_added_to_hand",
		"source_cell": _get_location_cell(source),
		"source_instance_id": source_instance_id,
		"owner_id": recipient_owner,
		"card_id": card_id,
		"instance_id": instance_id,
		"logical_hand_index": hand.size() - 1,
		"card": added_card.duplicate(true),
	}])


static func _make_generated_instance_id(
	state: StateData,
	card_id: StringName
) -> StringName:
	var observed: Dictionary = {}
	for instance_id: StringName in _get_all_instance_ids(state):
		observed[instance_id] = true
	var serial: int = 1
	while true:
		var candidate := StringName("generated_%s_%d" % [card_id, serial])
		if not observed.has(candidate):
			return candidate
		serial += 1
	return &""


static func _get_all_instance_ids(state: StateData) -> Array[StringName]:
	var instance_ids: Array[StringName] = []
	for slot_value: Variant in state.board:
		if slot_value is Dictionary:
			_append_card_instance_id(
				instance_ids,
				(slot_value as Dictionary).get("card", {})
			)
	for owner_id: int in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		for zone: Dictionary in [
			state.hands,
			state.decks,
			state.discard_piles,
			state.removed_cards,
		]:
			for card_value: Variant in zone.get(owner_id, []):
				_append_card_instance_id(instance_ids, card_value)
	return instance_ids


static func _append_card_instance_id(
	instance_ids: Array[StringName],
	card_value: Variant
) -> void:
	if not card_value is Dictionary:
		return
	var instance_id := StringName((card_value as Dictionary).get("instance_id", &""))
	if instance_id != &"":
		instance_ids.append(instance_id)


static func _return_card_to_hand(
	state: StateData,
	source_cell: int,
	card_reference: StringName,
	recipient_reference: StringName,
	context: Dictionary
) -> Dictionary:
	var snapshot: Dictionary = _get_reference_snapshot(context, card_reference)
	var instance_id := StringName(snapshot.get("instance_id", &""))
	var subject: Dictionary = Selector.locate_card(state, instance_id)
	if subject.is_empty() or StringName(subject.get("zone", &"")) != Catalog.CARD_ZONE_BOARD:
		return _no_effect(source_cell)
	if card_reference == Catalog.CARD_REF_SELECTED_CARD:
		var selected_conditions: Array = context.get("selected_card_conditions", [])
		var ability_source_instance_id := StringName(context.get("ability_source_instance_id", &""))
		subject = Selector.revalidate(
			state,
			instance_id,
			ability_source_instance_id,
			selected_conditions,
			context
		)
		if subject.is_empty():
			return _no_effect(source_cell)
	var target_cell: int = int(subject.get("index", -1))
	var ability_source: Dictionary = Selector.locate_card(
		state,
		StringName(context.get("ability_source_instance_id", &""))
	)
	var source_current_cell: int = _get_location_cell(ability_source)
	if source_current_cell < 0:
		source_current_cell = int(
			(_get_reference_snapshot(context, Catalog.CARD_REF_ABILITY_SOURCE)).get("index", source_cell)
		)
	var recipient_owner: int = int(subject.get("owner_id", 0))
	if recipient_reference == Catalog.OWNER_ABILITY_SOURCE:
		recipient_owner = int(context.get("ability_source_owner_id", 0))
	elif recipient_reference != Catalog.OWNER_CARD_CURRENT:
		return _no_effect(source_cell)
	var hand: Array = state.get_hand(recipient_owner)
	if hand.size() >= MAX_HAND_SIZE:
		return _exile_board_subject(
			state,
			subject,
			source_current_cell,
			StringName(context.get("ability_source_instance_id", &"")),
			card_reference == Catalog.CARD_REF_ABILITY_SOURCE
		)
	var old_card: Dictionary = subject.get("card", {})
	var card_id := StringName(old_card.get("card_id", &""))
	if not Catalog.has_card(card_id):
		return _no_effect(source_cell)
	var new_instance_id: StringName = _make_generated_instance_id(state, card_id)
	state.board[target_cell] = null
	var returned_card: Dictionary = Catalog.create_instance(
		card_id,
		recipient_owner,
		new_instance_id
	)
	hand.append(returned_card)
	return _applied(source_current_cell, [{
		"type": &"card_returned_to_hand",
		"source_cell": source_current_cell,
		"source_instance_id": StringName(context.get("ability_source_instance_id", &"")),
		"target_cell": target_cell,
		"old_instance_id": instance_id,
		"owner_id": recipient_owner,
		"card_id": card_id,
		"instance_id": new_instance_id,
		"logical_hand_index": hand.size() - 1,
		"card": returned_card.duplicate(true),
	}])


static func _request_summon_card(
	state: StateData,
	source_cell: int,
	declaration: Dictionary,
	context: Dictionary
) -> Dictionary:
	var source_snapshot: Dictionary = _get_reference_snapshot(
		context,
		Catalog.CARD_REF_ABILITY_SOURCE
	)
	var source_instance_id := StringName(source_snapshot.get("instance_id", &""))
	var source_owner: int = int(context.get("ability_source_owner_id", 0))
	var source_location: Dictionary = Selector.locate_card(state, source_instance_id)
	var current_source_cell: int = _get_location_cell(source_location)
	var card_spec: Variant = declaration.get("card", null)
	var card_id: StringName = &""
	var existing_instance_id: StringName = &""
	if typeof(card_spec) in [TYPE_STRING, TYPE_STRING_NAME]:
		var card_reference := StringName(card_spec)
		var card_snapshot: Dictionary = _get_reference_snapshot(context, card_reference)
		existing_instance_id = StringName(card_snapshot.get("instance_id", &""))
		var existing_location: Dictionary = Selector.locate_card(state, existing_instance_id)
		if (
			existing_location.is_empty()
			or StringName(existing_location.get("zone", &"")) != Catalog.CARD_ZONE_HAND
		):
			return _no_effect(source_cell)
		card_id = StringName((existing_location.get("card", {}) as Dictionary).get("card_id", &""))
		source_owner = int(existing_location.get("owner_id", source_owner))
	elif card_spec is Dictionary:
		var fresh_spec: Dictionary = card_spec
		if StringName(fresh_spec.get("type", &"")) != Catalog.CARD_SPEC_FRESH_COPY:
			return _no_effect(source_cell)
		var copied_snapshot: Dictionary = _get_reference_snapshot(
			context,
			StringName(fresh_spec.get("of", &""))
		)
		card_id = StringName(copied_snapshot.get("card_id", &""))
	else:
		return _no_effect(source_cell)
	if not Catalog.has_card(card_id):
		return _no_effect(source_cell)
	var cell_spec_value: Variant = declaration.get("cell", null)
	if not cell_spec_value is Dictionary:
		return _no_effect(source_cell)
	var cell_spec: Dictionary = cell_spec_value
	var anchor_reference := StringName(cell_spec.get("card", &""))
	var anchor_snapshot: Dictionary = _get_reference_snapshot(context, anchor_reference)
	var target_cell: int = -1
	var requires_adjacent_source: bool = false
	if StringName(cell_spec.get("type", &"")) == Catalog.CELL_REF_INITIAL_CARD_CELL:
		target_cell = int(anchor_snapshot.get("index", -1))
	elif StringName(cell_spec.get("type", &"")) == Catalog.CELL_REF_FIRST_ADJACENT_EMPTY:
		var anchor_location: Dictionary = Selector.locate_card(
			state,
			StringName(anchor_snapshot.get("instance_id", &""))
		)
		var anchor_cell: int = _get_location_cell(anchor_location)
		var empty_neighbors: Array[int] = []
		for direction: int in range(4):
			var neighbor_cell: int = Rules.get_neighbor_index(anchor_cell, direction)
			if neighbor_cell >= 0 and state.board[neighbor_cell] == null:
				empty_neighbors.append(neighbor_cell)
		if empty_neighbors.is_empty():
			return _no_effect(source_cell)
		empty_neighbors.sort()
		target_cell = empty_neighbors[0]
		requires_adjacent_source = anchor_reference == Catalog.CARD_REF_ABILITY_SOURCE
	if target_cell < 0 or target_cell >= state.board.size() or state.board[target_cell] != null:
		return _no_effect(source_cell)
	var result: Dictionary = _applied(current_source_cell if current_source_cell >= 0 else source_cell)
	result["summon_requests"].append({
		"source_cell": current_source_cell if current_source_cell >= 0 else int(source_snapshot.get("index", source_cell)),
		"source_instance_id": source_instance_id,
		"source_owner_id": source_owner,
		"target_cell": target_cell,
		"card_id": card_id,
		"instance_id": existing_instance_id if existing_instance_id != &"" else _make_generated_instance_id(state, card_id),
		"existing_hand_instance_id": existing_instance_id,
		"requires_source": requires_adjacent_source,
		"requires_adjacent_source": requires_adjacent_source,
		"reason": &"ability_fresh_copy",
	})
	return result


static func _request_trigger_card_resummon(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	context: Dictionary
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if source.is_empty() or StringName(source.get("zone", &"")) != Catalog.CARD_ZONE_BOARD:
		return _no_effect(source_cell)
	var trigger_instance_id := StringName(context.get("trigger_instance_id", &""))
	var trigger: Dictionary = Selector.locate_card(state, trigger_instance_id)
	if (
		trigger.is_empty()
		or StringName(trigger.get("zone", &"")) != Catalog.CARD_ZONE_BOARD
	):
		return _no_effect(int(source.get("index", source_cell)))
	var trigger_card: Dictionary = trigger.get("card", {})
	var card_id := StringName(trigger_card.get("card_id", &""))
	if not Catalog.has_card(card_id):
		return _no_effect(int(source.get("index", source_cell)))
	var target_cell: int = int(trigger.get("index", -1))
	if target_cell < 0 or target_cell >= state.board.size():
		return _no_effect(int(source.get("index", source_cell)))
	var new_instance_id: StringName = _make_generated_instance_id(state, card_id)
	if new_instance_id == &"":
		return _no_effect(int(source.get("index", source_cell)))
	var source_current_cell: int = int(source.get("index", source_cell))
	var source_owner: int = int(source.get("owner_id", expected_owner))
	state.board[target_cell] = null
	var result: Dictionary = _applied(source_current_cell, [{
		"type": &"card_departed_for_resummon",
		"source_cell": source_current_cell,
		"source_instance_id": source_instance_id,
		"target_cell": target_cell,
		"owner_id": source_owner,
		"old_instance_id": trigger_instance_id,
		"card_id": card_id,
	}])
	result["summon_requests"].append({
		"source_cell": source_current_cell,
		"source_instance_id": source_instance_id,
		"source_owner_id": source_owner,
		"target_cell": target_cell,
		"card_id": card_id,
		"instance_id": new_instance_id,
		"old_instance_id": trigger_instance_id,
		"requires_adjacent_source": false,
		"reason": &"ability_resummon_in_place",
	})
	return result


static func _exile_self(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int
) -> Dictionary:
	var subject: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if subject.is_empty() or StringName(subject.get("zone", &"")) != Catalog.CARD_ZONE_BOARD:
		return _no_effect(source_cell)
	return _exile_board_subject(
		state,
		subject,
		int(subject.get("index", source_cell)),
		source_instance_id,
		true
	)


static func _exile_board_subject(
	state: StateData,
	subject: Dictionary,
	source_cell: int,
	source_instance_id: StringName,
	self_removal: bool
) -> Dictionary:
	var target_cell: int = int(subject.get("index", -1))
	if target_cell < 0 or target_cell >= state.board.size():
		return _no_effect(source_cell)
	var target_card: Dictionary = subject.get("card", {})
	var target_instance_id := StringName(target_card.get("instance_id", &""))
	if target_instance_id == &"" or state.board[target_cell] == null:
		return _no_effect(source_cell)
	var original_owner: int = int(target_card.get("original_owner", 0))
	if original_owner not in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		original_owner = int(subject.get("owner_id", 0))
	if not state.removed_cards.has(original_owner):
		state.removed_cards[original_owner] = []
	(state.removed_cards[original_owner] as Array).append(target_card)
	state.board[target_cell] = null
	return _applied(source_cell, [{
		"type": &"card_exiled",
		"source_cell": source_cell,
		"source_instance_id": source_instance_id,
		"target_cell": target_cell,
		"owner_id": int(subject.get("owner_id", 0)),
		"original_owner": original_owner,
		"instance_id": target_instance_id,
		"self_removal": self_removal,
	}])


static func _spend_all_ki(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if source.is_empty():
		return _no_effect(source_cell)
	var card: Dictionary = source.get("card", {})
	var previous_ki: int = int(card.get("ki", 0))
	if previous_ki <= 0:
		return _no_effect(source_cell)
	card["ki"] = 0
	var current_cell: int = _get_location_cell(source)
	return _applied(source_cell, [_make_ki_event(
		current_cell,
		int(source.get("owner_id", 0)),
		source_instance_id,
		previous_ki,
		0,
		Catalog.ACTION_SPEND_ALL_KI,
		StringName(source.get("zone", &"")),
		int(source.get("index", -1))
	)])


static func _grant_extra_card_play(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	amount: int
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if source.is_empty() or amount <= 0:
		return _no_effect(source_cell)
	var result: Dictionary = _applied(source_cell)
	result["extra_turn_requests"].append({
		"owner_id": int(source.get("owner_id", 0)),
		"source_cell": _get_location_cell(source),
		"source_instance_id": source_instance_id,
		"amount": amount,
	})
	return result


static func _move_self(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	context: Dictionary,
	before_move_resolver: Callable = Callable()
) -> Dictionary:
	var source_slot: Dictionary = _get_card_slot(
		state,
		source_cell,
		source_instance_id,
		expected_owner
	)
	var target_kind := StringName(context.get("target_kind", &""))
	var target_cell: int = int(context.get("target_index", -1))
	if (
		source_slot.is_empty()
		or target_kind != &"board_cell"
		or target_cell < 0
		or target_cell >= state.board.size()
		or state.board[target_cell] != null
		or not _are_adjacent(source_cell, target_cell)
	):
		return _no_effect(source_cell)
	return _move_card_between_cells(
		state,
		source_cell,
		target_cell,
		source_instance_id,
		expected_owner,
		before_move_resolver
	)


static func _move_self_to_first_adjacent_empty(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	before_move_resolver: Callable = Callable()
) -> Dictionary:
	var subject: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if StringName(subject.get("zone", &"")) != Catalog.CARD_ZONE_BOARD:
		return _no_effect(source_cell)
	var current_cell: int = int(subject.get("index", -1))
	for target_cell: int in range(state.board.size()):
		if state.board[target_cell] == null and _are_adjacent(current_cell, target_cell):
			return _move_card_between_cells(
				state,
				current_cell,
				target_cell,
				source_instance_id,
				expected_owner,
				before_move_resolver
			)
	return _no_effect(source_cell)


static func _move_self_to_first_empty_between_enemy(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	before_move_resolver: Callable = Callable()
) -> Dictionary:
	var subject: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if StringName(subject.get("zone", &"")) != Catalog.CARD_ZONE_BOARD:
		return _no_effect(source_cell)
	var current_cell: int = int(subject.get("index", -1))
	for middle_cell: int in range(state.board.size()):
		if state.board[middle_cell] != null:
			continue
		for direction: int in range(4):
			if Rules.get_neighbor_index(current_cell, direction) != middle_cell:
				continue
			var far_cell: int = Rules.get_neighbor_index(middle_cell, direction)
			if far_cell < 0 or state.board[far_cell] == null:
				continue
			if int((state.board[far_cell] as Dictionary).get("owner", 0)) == expected_owner:
				continue
			return _move_card_between_cells(
				state,
				current_cell,
				middle_cell,
				source_instance_id,
				expected_owner,
				before_move_resolver
			)
	return _no_effect(source_cell)


static func _swap_self_with_target(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	context: Dictionary,
	before_move_resolver: Callable = Callable()
) -> Dictionary:
	var source_slot: Dictionary = _get_card_slot(
		state,
		source_cell,
		source_instance_id,
		expected_owner
	)
	var target_kind := StringName(context.get("target_kind", &""))
	var target_cell: int = int(context.get("target_index", -1))
	if (
		source_slot.is_empty()
		or target_kind != &"board_cell"
		or target_cell < 0
		or target_cell >= state.board.size()
		or state.board[target_cell] == null
		or not _are_adjacent(source_cell, target_cell)
	):
		return _no_effect(source_cell)
	var target_slot: Dictionary = state.board[target_cell] as Dictionary
	var target_card: Dictionary = target_slot.get("card", {})
	var target_instance_id := StringName(target_card.get("instance_id", &""))
	var target_owner: int = int(target_slot.get("owner", 0))
	if target_instance_id == &"":
		return _no_effect(source_cell)
	return _swap_board_cards(
		state,
		source_cell,
		source_instance_id,
		expected_owner,
		target_cell,
		target_instance_id,
		target_owner,
		before_move_resolver
	)


static func _self_swapped_with_ability_source(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	context: Dictionary,
	before_move_resolver: Callable = Callable()
) -> Dictionary:
	var subject: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	var ability_source_instance_id := StringName(
		context.get("ability_source_instance_id", &"")
	)
	var ability_source_owner: int = int(context.get("ability_source_owner_id", 0))
	var ability_source: Dictionary = _get_subject(
		state,
		ability_source_instance_id,
		ability_source_owner
	)
	if (
		subject.is_empty()
		or ability_source.is_empty()
		or source_instance_id == ability_source_instance_id
		or StringName(subject.get("zone", &"")) != Catalog.CARD_ZONE_BOARD
		or StringName(ability_source.get("zone", &"")) != Catalog.CARD_ZONE_BOARD
	):
		return _no_effect(source_cell)
	var subject_cell: int = int(subject.get("index", -1))
	var ability_source_cell: int = int(ability_source.get("index", -1))
	if not _are_adjacent(ability_source_cell, subject_cell):
		return _no_effect(source_cell)
	var result: Dictionary = _swap_board_cards(
		state,
		ability_source_cell,
		ability_source_instance_id,
		ability_source_owner,
		subject_cell,
		source_instance_id,
		expected_owner,
		before_move_resolver
	)
	if StringName(result.get("result", &"")) == Catalog.ACTION_RESULT_APPLIED:
		result["source_cell"] = ability_source_cell
	return result


static func _swap_board_cards(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	target_cell: int,
	target_instance_id: StringName,
	target_owner: int,
	before_move_resolver: Callable = Callable()
) -> Dictionary:
	if (
		_get_card_slot(
			state,
			source_cell,
			source_instance_id,
			expected_owner
		).is_empty()
		or _get_card_slot(
			state,
			target_cell,
			target_instance_id,
			target_owner
		).is_empty()
		or not _are_adjacent(source_cell, target_cell)
	):
		return _no_effect(source_cell)

	var source_before: Dictionary = _resolve_before_move(
		state,
		source_cell,
		target_cell,
		source_instance_id,
		expected_owner,
		before_move_resolver
	)
	if not _movement_is_valid(
		state,
		source_cell,
		target_cell,
		source_instance_id,
		expected_owner,
		true
	) or _get_card_slot(
		state,
		target_cell,
		target_instance_id,
		target_owner
	).is_empty():
		return source_before
	var reserved_target: Dictionary = state.board[target_cell] as Dictionary
	state.board[target_cell] = null
	var source_move: Dictionary = _move_card_between_cells(
		state,
		source_cell,
		target_cell,
		source_instance_id,
		expected_owner,
		before_move_resolver,
		false
	)
	var source_events: Array = (source_before.get("events", []) as Array).duplicate()
	source_events.append_array(source_move.get("events", []) as Array)
	source_move["events"] = source_events
	source_move["captures"].append_array(source_before.get("captures", []) as Array)
	source_move["exiles"].append_array(source_before.get("exiles", []) as Array)
	if StringName(source_move.get("result", &"")) != Catalog.ACTION_RESULT_APPLIED:
		state.board[target_cell] = reserved_target
		return source_before

	var reserved_source: Dictionary = state.board[target_cell] as Dictionary
	state.board[target_cell] = reserved_target
	var target_move: Dictionary = _move_card_between_cells(
		state,
		target_cell,
		source_cell,
		target_instance_id,
		target_owner,
		before_move_resolver
	)
	if StringName(target_move.get("result", &"")) != Catalog.ACTION_RESULT_APPLIED:
		state.board[source_cell] = reserved_source
		state.board[target_cell] = reserved_target
		return _no_effect(source_cell)
	state.board[target_cell] = reserved_source

	var events: Array = source_move.get("events", []) as Array
	events.append_array(target_move.get("events", []) as Array)
	var result: Dictionary = _applied(target_cell, events)
	result["captures"].append_array(source_move.get("captures", []) as Array)
	result["captures"].append_array(target_move.get("captures", []) as Array)
	result["exiles"].append_array(source_move.get("exiles", []) as Array)
	result["exiles"].append_array(target_move.get("exiles", []) as Array)
	return result


static func _move_card_between_cells(
	state: StateData,
	source_cell: int,
	target_cell: int,
	instance_id: StringName,
	expected_owner: int,
	before_move_resolver: Callable = Callable(),
	resolve_before: bool = true
) -> Dictionary:
	var before_result: Dictionary = _no_effect(source_cell)
	if resolve_before:
		before_result = _resolve_movement_event(
			state,
			Catalog.CARD_BEFORE_MOVED,
			source_cell,
			target_cell,
			instance_id,
			expected_owner,
			before_move_resolver
		)
	var source_slot: Dictionary = _get_card_slot(
		state,
		source_cell,
		instance_id,
		expected_owner
	)
	if not _movement_is_valid(
		state,
		source_cell,
		target_cell,
		instance_id,
		expected_owner
	):
		return before_result
	state.board[source_cell] = null
	state.board[target_cell] = source_slot
	var result: Dictionary = _applied(target_cell, before_result.get("events", []) as Array)
	result["captures"].append_array(before_result.get("captures", []) as Array)
	result["exiles"].append_array(before_result.get("exiles", []) as Array)
	result["events"].append({
		"type": &"card_moved",
		"source_cell": source_cell,
		"target_cell": target_cell,
		"owner_id": int(source_slot.get("owner", 0)),
		"instance_id": instance_id,
	})
	var after_result: Dictionary = _resolve_movement_event(
		state,
		Catalog.CARD_AFTER_MOVED,
		target_cell,
		target_cell,
		instance_id,
		expected_owner,
		before_move_resolver,
		source_cell
	)
	result["events"].append_array(after_result.get("events", []) as Array)
	result["captures"].append_array(after_result.get("captures", []) as Array)
	result["exiles"].append_array(after_result.get("exiles", []) as Array)
	result["extra_turn_requests"].append_array(
		after_result.get("extra_turn_requests", []) as Array
	)
	return result


static func _resolve_before_move(
	state: StateData,
	source_cell: int,
	target_cell: int,
	instance_id: StringName,
	expected_owner: int,
	before_move_resolver: Callable
) -> Dictionary:
	return _resolve_movement_event(
		state,
		Catalog.CARD_BEFORE_MOVED,
		source_cell,
		target_cell,
		instance_id,
		expected_owner,
		before_move_resolver
	)


static func _resolve_movement_event(
	_state: StateData,
	event_id: StringName,
	source_cell: int,
	target_cell: int,
	instance_id: StringName,
	expected_owner: int,
	movement_resolver: Callable,
	origin_cell: int = -1
) -> Dictionary:
	var result: Dictionary = _no_effect(source_cell)
	if not movement_resolver.is_valid():
		return result
	var resolution_value: Variant = movement_resolver.call({
		"movement_event": event_id,
		"moving_source_cell": source_cell,
		"moving_origin_cell": origin_cell if origin_cell >= 0 else source_cell,
		"moving_target_cell": target_cell,
		"moving_instance_id": instance_id,
		"moving_owner_id": expected_owner,
	})
	if resolution_value is Dictionary:
		result = resolution_value as Dictionary
		result["source_cell"] = source_cell
	return result


static func _movement_is_valid(
	state: StateData,
	source_cell: int,
	target_cell: int,
	instance_id: StringName,
	expected_owner: int,
	allow_occupied_target: bool = false
) -> bool:
	return (
		not _get_card_slot(
			state,
			source_cell,
			instance_id,
			expected_owner
		).is_empty()
		and target_cell >= 0
		and target_cell < state.board.size()
		and (allow_occupied_target or state.board[target_cell] == null)
	)


static func _request_standard_attack(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int
) -> Dictionary:
	var source_slot: Dictionary = _get_card_slot(
		state,
		source_cell,
		source_instance_id,
		expected_owner
	)
	if source_slot.is_empty():
		return _no_effect(source_cell)
	var result: Dictionary = _applied(source_cell)
	result["attack_requests"].append({
		"mode": &"standard",
		"source_cell": source_cell,
		"source_instance_id": source_instance_id,
		"source_owner_id": int(source_slot.get("owner", 0)),
		"reason": &"activated_ability",
	})
	return result


static func _request_flip_self(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	new_owner_reference: StringName,
	context: Dictionary
) -> Dictionary:
	var subject: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	var ability_source_instance_id := StringName(
		context.get("ability_source_instance_id", &"")
	)
	var ability_source_owner: int = int(context.get("ability_source_owner_id", 0))
	var ability_source: Dictionary = _get_subject(
		state,
		ability_source_instance_id,
		ability_source_owner
	)
	if (
		subject.is_empty()
		or ability_source.is_empty()
		or StringName(subject.get("zone", &"")) != Catalog.CARD_ZONE_BOARD
		or new_owner_reference != Catalog.OWNER_ABILITY_SOURCE
		or int(subject.get("owner_id", 0)) == ability_source_owner
	):
		return _no_effect(source_cell)
	var result: Dictionary = _applied(source_cell)
	result["flip_requests"].append({
		"target_instance_id": source_instance_id,
		"new_owner_id": ability_source_owner,
		"reason": &"ability_non_attack_flip",
	})
	return result


static func _get_card_slot(
	state: StateData,
	cell: int,
	instance_id: StringName,
	expected_owner: int = 0
) -> Dictionary:
	if state == null or cell < 0 or cell >= state.board.size():
		return {}
	var slot_value: Variant = state.board[cell]
	if slot_value == null:
		return {}
	var slot: Dictionary = slot_value
	var card: Dictionary = slot.get("card", {})
	if StringName(card.get("instance_id", &"")) != instance_id:
		return {}
	if expected_owner != 0 and int(slot.get("owner", 0)) != expected_owner:
		return {}
	return slot


static func _get_subject(
	state: StateData,
	instance_id: StringName,
	expected_owner: int
) -> Dictionary:
	var subject: Dictionary = Selector.locate_card(state, instance_id)
	if (
		subject.is_empty()
		or expected_owner != 0
		and int(subject.get("owner_id", 0)) != expected_owner
	):
		return {}
	return subject


static func _snapshot_card_reference(
	state: StateData,
	instance_id: StringName
) -> Dictionary:
	var location: Dictionary = Selector.locate_card(state, instance_id)
	if location.is_empty():
		return {}
	var card: Dictionary = location.get("card", {})
	return {
		"instance_id": instance_id,
		"card_id": StringName(card.get("card_id", &"")),
		"owner_id": int(location.get("owner_id", 0)),
		"zone": StringName(location.get("zone", &"")),
		"index": int(location.get("index", -1)),
	}


static func _get_reference_snapshot(
	context: Dictionary,
	card_reference: StringName
) -> Dictionary:
	var snapshots: Dictionary = context.get("card_reference_snapshots", {})
	var snapshot_value: Variant = snapshots.get(card_reference, {})
	return snapshot_value as Dictionary if snapshot_value is Dictionary else {}


static func _get_location_cell(location: Dictionary) -> int:
	if StringName(location.get("zone", &"")) != Catalog.CARD_ZONE_BOARD:
		return -1
	return int(location.get("index", -1))


static func _are_adjacent(first_cell: int, second_cell: int) -> bool:
	for direction: int in range(4):
		if Rules.get_neighbor_index(first_cell, direction) == second_cell:
			return true
	return false


static func _make_ki_event(
	source_cell: int,
	owner_id: int,
	instance_id: StringName,
	previous_ki: int,
	resulting_ki: int,
	action_type: StringName,
	zone: StringName,
	logical_index: int
) -> Dictionary:
	return {
		"type": &"ki_changed",
		"source_cell": source_cell,
		"target_cell": source_cell,
		"owner_id": owner_id,
		"instance_id": instance_id,
		"previous_ki": previous_ki,
		"ki": resulting_ki,
		"change_reason": action_type,
		"zone": zone,
		"logical_index": logical_index,
	}


static func _empty_result() -> Dictionary:
	return {
		"result": Catalog.ACTION_RESULT_NO_EFFECT,
		"events": [],
		"attack_requests": [],
		"flip_requests": [],
		"summon_requests": [],
		"extra_turn_requests": [],
		"flip_prevention_requests": [],
		"captures": [],
		"exiles": [],
		"source_cell": -1,
	}


static func _no_effect(source_cell: int) -> Dictionary:
	var result: Dictionary = _empty_result()
	result["source_cell"] = source_cell
	return result


static func _applied(source_cell: int, events: Array = []) -> Dictionary:
	var result: Dictionary = _empty_result()
	result["result"] = Catalog.ACTION_RESULT_APPLIED
	result["source_cell"] = source_cell
	result["events"] = events
	return result
