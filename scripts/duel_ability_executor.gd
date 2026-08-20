class_name DuelAbilityExecutor
extends RefCounted

const MAX_HAND_SIZE: int = 5
const EMPTY_DECK_DRAW_CARD_ID: StringName = &"TaiZuChangQuan"

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
	before_move_resolver: Callable = Callable(),
	event_resolver: Callable = Callable()
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
		"ability_source_instance_id": source_instance_id,
		"ability_source_owner_id": owner_id,
		"card_reference_snapshots": {},
	}
	var snapshots: Dictionary = context["card_reference_snapshots"] as Dictionary
	snapshots[Catalog.CARD_REF_ABILITY_SOURCE] = _snapshot_card_reference(
		state,
		source_instance_id
	)
	if target_kind == &"board_cell" and target_index >= 0 and target_index < state.board.size():
		var target_value: Variant = state.board[target_index]
		if target_value is Dictionary:
			context["selected_card_instance_id"] = StringName(
				((target_value as Dictionary).get("card", {}) as Dictionary).get("instance_id", &"")
			)
	elif target_kind == &"hand_slot":
		var opponent_owner: int = (
			Rules.OPPONENT_OWNER
			if owner_id == Rules.PLAYER_OWNER
			else Rules.PLAYER_OWNER
		)
		var opponent_hand: Array = state.get_hand(opponent_owner)
		if target_index >= 0 and target_index < opponent_hand.size():
			var target_card: Dictionary = opponent_hand[target_index]
			context["selected_card_instance_id"] = StringName(
				target_card.get("instance_id", &"")
			)
	var selected_instance_id := StringName(context.get("selected_card_instance_id", &""))
	if selected_instance_id != &"":
		snapshots[Catalog.CARD_REF_SELECTED_CARD] = _snapshot_card_reference(
			state,
			selected_instance_id
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
		before_move_resolver,
		event_resolver
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
		before_move_resolver,
		event_resolver
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
	before_move_resolver: Callable = Callable(),
	event_resolver: Callable = Callable()
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
	var action_subject_snapshot: Dictionary = _snapshot_card_reference(
		state,
		source_instance_id
	)
	if not action_subject_snapshot.is_empty():
		action_context["action_subject_snapshot"] = action_subject_snapshot
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
	if not reference_snapshots.has(Catalog.CARD_REF_TRIGGER_CARD):
		var trigger_instance_id := StringName(action_context.get("trigger_instance_id", &""))
		if trigger_instance_id != &"":
			reference_snapshots[Catalog.CARD_REF_TRIGGER_CARD] = _snapshot_card_reference(
				state,
				trigger_instance_id
			)
	var current_source_cell: int = source_cell
	for action_index: int in range(actions.size()):
		var action_value: Variant = actions[action_index]
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
			before_move_resolver,
			event_resolver
		)
		if not bool(action_context.get("defer_power_change_batch", false)):
			_assign_power_change_batch(
				action_result.get("events", []) as Array,
				_make_power_change_batch_id(
					source_instance_id,
					action_context,
					action_index,
					StringName(declaration.get("power_change_batch_group", &""))
				)
			)
		result["events"].append_array(action_result.get("events", []) as Array)
		result["captures"].append_array(action_result.get("captures", []) as Array)
		result["exiles"].append_array(action_result.get("exiles", []) as Array)
		result["extra_turn_requests"].append_array(action_result.get("extra_turn_requests", []) as Array)
		result["flip_prevention_requests"].append_array(action_result.get("flip_prevention_requests", []) as Array)
		if event_resolver.is_valid():
			for event_value: Variant in action_result.get("events", []):
				if (
					not event_value is Dictionary
					or StringName((event_value as Dictionary).get("type", &""))
					!= &"ki_changed"
					or bool((event_value as Dictionary).get("ki_trigger_resolved", false))
				):
					continue
				var ki_event: Dictionary = event_value
				var resolution_value: Variant = event_resolver.call(
					Catalog.CARD_KI_CHANGED,
					{
						"trigger_cell": int(ki_event.get("target_cell", -1)),
						"trigger_instance_id": StringName(ki_event.get("instance_id", &"")),
						"trigger_owner_id": int(ki_event.get("owner_id", 0)),
						"previous_ki": int(ki_event.get("previous_ki", 0)),
						"ki": int(ki_event.get("ki", 0)),
						"change_reason": StringName(ki_event.get("change_reason", &"")),
					}
				)
				if not resolution_value is Dictionary:
					continue
				var event_resolution: Dictionary = resolution_value
				result["events"].append_array(event_resolution.get("events", []) as Array)
				result["captures"].append_array(event_resolution.get("captures", []) as Array)
				result["exiles"].append_array(event_resolution.get("exiles", []) as Array)
				result["extra_turn_requests"].append_array(
					event_resolution.get("extra_turn_requests", []) as Array
				)
				result["flip_prevention_requests"].append_array(
					event_resolution.get("flip_prevention_requests", []) as Array
				)
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
	new_owner: int,
	expected_source_owner: int = 0
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if expected_source_owner not in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		expected_source_owner = new_owner
	var target_slot: Dictionary = _get_card_slot(state, target_cell, target_instance_id)
	if target_slot.is_empty():
		return events
	if (
		source_instance_id != &""
		and _get_card_slot(
			state,
			source_cell,
			source_instance_id,
			expected_source_owner
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
	var removed_count: int = Abilities.remove_non_retained_abilities_before_after_flip(
		target_card
	)
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
	before_move_resolver: Callable,
	event_resolver: Callable
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
			before_move_resolver,
			event_resolver
		)
	if action_type == Catalog.ACTION_DRAW_CARDS:
		return _draw_cards(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			int(declaration.get("amount", 0)),
			String(declaration.get("weapon", "")),
			context,
			event_resolver
		)
	if action_type == Catalog.ACTION_EXILE_CARD:
		return _exile_referenced_card(
			state,
			source_cell,
			StringName(declaration.get("card", &"")),
			context,
			event_resolver
		)
	if action_type == Catalog.ACTION_DEPART_CARD_FOR_RESUMMON:
		return _depart_referenced_card_for_resummon(
			state,
			source_cell,
			StringName(declaration.get("card", &"")),
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
		var gain_instance_id: StringName = source_instance_id
		var gain_owner: int = expected_owner
		if declaration.has("card"):
			var gain_snapshot: Dictionary = _get_reference_snapshot(
				context,
				StringName(declaration.get("card", &""))
			)
			var gain_subject: Dictionary = _locate_snapshot_subject(state, gain_snapshot)
			if gain_subject.is_empty():
				return _no_effect(source_cell)
			gain_instance_id = StringName(
				(gain_subject.get("card", {}) as Dictionary).get("instance_id", &"")
			)
			gain_owner = int(gain_subject.get("owner_id", 0))
		return _change_ki(
			state,
			source_cell,
			gain_instance_id,
			gain_owner,
			int(declaration.get("amount", 0)),
			action_type
		)
	if action_type == Catalog.ACTION_TRANSFER_CARD_RESOURCE:
		return _transfer_card_resource(
			state,
			source_cell,
			declaration,
			context,
			event_resolver
		)
	if action_type == Catalog.ACTION_DISTRIBUTE_KI:
		return _distribute_ki(
			state,
			source_cell,
			declaration,
			context,
			event_resolver
		)
	if action_type == Catalog.ACTION_CHANGE_POWERS:
		var power_reference := StringName(declaration.get("card", &""))
		var power_snapshot: Dictionary = _get_reference_snapshot(context, power_reference)
		return _change_powers(
			state,
			source_cell,
			StringName(power_snapshot.get("instance_id", &"")),
			int(power_snapshot.get("owner_id", 0)),
			declaration.get("amount", null),
			context,
			event_resolver
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
			StringName(declaration.get("filter", &"")),
			context
		)
	if action_type == Catalog.ACTION_REVEAL_CARD:
		return _reveal_card(
			state,
			source_cell,
			StringName(declaration.get("card", &"")),
			StringName(declaration.get("observer", &"")),
			context
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
	if action_type == Catalog.ACTION_SWAP_SELF_WITH_TRIGGER_CARD:
		return _swap_self_with_trigger_card(
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
			context,
			event_resolver
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
			expected_owner,
			context,
			event_resolver
		)
	if action_type == Catalog.ACTION_RESUMMON_CARD_IN_PLACE:
		return _request_card_resummon(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			StringName(declaration.get("card", &"")),
			context
		)
	if action_type == Catalog.ACTION_SPEND_KI:
		var spend_instance_id: StringName = source_instance_id
		var spend_owner: int = expected_owner
		if declaration.has("card"):
			var spend_snapshot: Dictionary = _get_reference_snapshot(
				context,
				StringName(declaration.get("card", &""))
			)
			var spend_subject: Dictionary = _locate_snapshot_subject(state, spend_snapshot)
			if spend_subject.is_empty():
				return _no_effect(source_cell)
			spend_instance_id = StringName(
				(spend_subject.get("card", {}) as Dictionary).get("instance_id", &"")
			)
			spend_owner = int(spend_subject.get("owner_id", 0))
		return _change_ki(
			state,
			source_cell,
			spend_instance_id,
			spend_owner,
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
		var grant_instance_id: StringName = source_instance_id
		var grant_owner: int = expected_owner
		if declaration.has("card"):
			var grant_snapshot: Dictionary = _get_reference_snapshot(
				context,
				StringName(declaration.get("card", &""))
			)
			var grant_subject: Dictionary = _locate_snapshot_subject(state, grant_snapshot)
			if grant_subject.is_empty():
				return _no_effect(source_cell)
			grant_instance_id = StringName(
				(grant_subject.get("card", {}) as Dictionary).get("instance_id", &"")
			)
			grant_owner = int(grant_subject.get("owner_id", 0))
		return _grant_extra_card_play(
			state,
			source_cell,
			grant_instance_id,
			grant_owner,
			int(declaration.get("amount", 0)),
			context
		)
	if action_type == Catalog.ACTION_ADD_PENDING_NON_RETAINED_SUPPRESSION:
		return _add_pending_non_retained_suppression(
			state,
			source_cell,
			source_instance_id,
			expected_owner,
			StringName(declaration.get("recipient", &"")),
			int(declaration.get("amount", 0)),
			context
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
			expected_owner,
			bool(declaration.get("repeat_attack", false)),
			StringName(declaration.get("target_policy", &""))
		)
	if action_type == Catalog.ACTION_STANDARD_ATTACK_WITH_CARD:
		return _request_standard_attack_with_card(
			state,
			source_cell,
			StringName(declaration.get("card", &"")),
			context
		)
	return _no_effect(source_cell)


static func _transfer_card_resource(
	state: StateData,
	source_cell: int,
	declaration: Dictionary,
	context: Dictionary,
	event_resolver: Callable
) -> Dictionary:
	var donor: Dictionary = _locate_snapshot_subject(
		state,
		_get_reference_snapshot(
			context,
			StringName(declaration.get("from", &""))
		)
	)
	var receiver: Dictionary = _locate_snapshot_subject(
		state,
		_get_reference_snapshot(
			context,
			StringName(declaration.get("to", &""))
		)
	)
	if donor.is_empty() or receiver.is_empty():
		return _no_effect(source_cell)
	var donor_id := StringName((donor.get("card", {}) as Dictionary).get("instance_id", &""))
	var receiver_id := StringName(
		(receiver.get("card", {}) as Dictionary).get("instance_id", &"")
	)
	if donor_id == &"" or receiver_id == &"" or donor_id == receiver_id:
		return _no_effect(source_cell)
	var amount: int = int(declaration.get("amount", 0))
	for resource_key: StringName in [
		StringName(declaration.get("resource", &"")),
		StringName(declaration.get("fallback_resource", &"")),
	]:
		if not _subject_can_donate_resource(donor, resource_key, amount):
			continue
		if not _subject_can_receive_resource(receiver, resource_key):
			return _no_effect(source_cell)
		if resource_key == Catalog.RESOURCE_KI:
			return _transfer_ki_between_subjects(
				state,
				source_cell,
				donor,
				receiver,
				amount,
				false,
				event_resolver
			)
		if resource_key == Catalog.RESOURCE_POWERS:
			return _transfer_powers_between_subjects(
				state,
				source_cell,
				donor,
				receiver,
				amount,
				context,
				event_resolver
			)
	return _no_effect(source_cell)


static func _distribute_ki(
	state: StateData,
	source_cell: int,
	declaration: Dictionary,
	context: Dictionary,
	event_resolver: Callable
) -> Dictionary:
	var distributor: Dictionary = _locate_snapshot_subject(
		state,
		_get_reference_snapshot(
			context,
			StringName(declaration.get("from", &""))
		)
	)
	if distributor.is_empty():
		return _no_effect(source_cell)
	var distributor_id := StringName(
		(distributor.get("card", {}) as Dictionary).get("instance_id", &"")
	)
	var amount: int = int(declaration.get("amount", 0))
	if distributor_id == &"" or amount <= 0:
		return _no_effect(source_cell)
	var selector: Dictionary = declaration.get("selector", {})
	var conditions: Array = selector.get("conditions", [])
	var selected_ids: Array[StringName] = Selector.snapshot(
		state,
		selector,
		distributor_id,
		context
	)
	var result: Dictionary = _no_effect(source_cell)
	while true:
		distributor = Selector.locate_card(state, distributor_id)
		if (
			distributor.is_empty()
			or not _subject_can_donate_resource(distributor, Catalog.RESOURCE_KI, amount)
		):
			break
		var transferred_in_round: bool = false
		for selected_id: StringName in selected_ids:
			distributor = Selector.locate_card(state, distributor_id)
			if (
				distributor.is_empty()
				or not _subject_can_donate_resource(
					distributor,
					Catalog.RESOURCE_KI,
					amount
				)
			):
				break
			var recipient: Dictionary = Selector.revalidate(
				state,
				selected_id,
				distributor_id,
				conditions,
				context
			)
			if recipient.is_empty():
				continue
			var transfer_result: Dictionary = _transfer_ki_between_subjects(
				state,
				source_cell,
				distributor,
				recipient,
				amount,
				true,
				event_resolver
			)
			if StringName(transfer_result.get("result", &"")) != Catalog.ACTION_RESULT_APPLIED:
				continue
			transferred_in_round = true
			_merge_action_resolution(result, transfer_result)
		if not transferred_in_round:
			break
	result["source_cell"] = source_cell
	return result


static func _transfer_ki_between_subjects(
	state: StateData,
	source_cell: int,
	donor: Dictionary,
	receiver: Dictionary,
	amount: int,
	resolve_triggers_now: bool,
	event_resolver: Callable
) -> Dictionary:
	if (
		not _subject_can_donate_resource(donor, Catalog.RESOURCE_KI, amount)
		or not _subject_can_receive_resource(receiver, Catalog.RESOURCE_KI)
	):
		return _no_effect(source_cell)
	var donor_card: Dictionary = donor.get("card", {})
	var receiver_card: Dictionary = receiver.get("card", {})
	var donor_id := StringName(donor_card.get("instance_id", &""))
	var receiver_id := StringName(receiver_card.get("instance_id", &""))
	if donor_id == &"" or receiver_id == &"" or donor_id == receiver_id:
		return _no_effect(source_cell)
	var result: Dictionary = _no_effect(source_cell)
	_merge_action_resolution(
		result,
		_change_ki(
			state,
			source_cell,
			donor_id,
			int(donor.get("owner_id", 0)),
			-amount,
			Catalog.ACTION_TRANSFER_CARD_RESOURCE
		)
	)
	_merge_action_resolution(
		result,
		_change_ki(
			state,
			source_cell,
			receiver_id,
			int(receiver.get("owner_id", 0)),
			amount,
			Catalog.ACTION_TRANSFER_CARD_RESOURCE
		)
	)
	if resolve_triggers_now:
		_resolve_ki_events_now(result, event_resolver)
	return result


static func _transfer_powers_between_subjects(
	state: StateData,
	source_cell: int,
	donor: Dictionary,
	receiver: Dictionary,
	amount: int,
	context: Dictionary,
	event_resolver: Callable
) -> Dictionary:
	if (
		not _subject_can_donate_resource(donor, Catalog.RESOURCE_POWERS, amount)
		or not _subject_can_receive_resource(receiver, Catalog.RESOURCE_POWERS)
	):
		return _no_effect(source_cell)
	var donor_id := StringName((donor.get("card", {}) as Dictionary).get("instance_id", &""))
	var receiver_id := StringName(
		(receiver.get("card", {}) as Dictionary).get("instance_id", &"")
	)
	if donor_id == &"" or receiver_id == &"" or donor_id == receiver_id:
		return _no_effect(source_cell)
	var result: Dictionary = _no_effect(source_cell)
	_merge_action_resolution(
		result,
		_change_powers(
			state,
			source_cell,
			donor_id,
			int(donor.get("owner_id", 0)),
			-amount,
			context,
			event_resolver
		)
	)
	_merge_action_resolution(
		result,
		_change_powers(
			state,
			source_cell,
			receiver_id,
			int(receiver.get("owner_id", 0)),
			amount,
			context,
			event_resolver
		)
	)
	return result


static func _subject_can_donate_resource(
	subject: Dictionary,
	resource: StringName,
	amount: int
) -> bool:
	if subject.is_empty() or amount <= 0:
		return false
	var card: Dictionary = subject.get("card", {})
	if resource == Catalog.RESOURCE_KI:
		return int(card.get("ki", 0)) >= amount
	if resource == Catalog.RESOURCE_POWERS:
		if not Rules.can_change_powers(card):
			return false
		var powers: Array = card.get("powers", [])
		return (
			powers.size() == 4
			and powers.any(func(value: Variant) -> bool: return int(value) > 0)
		)
	return false


static func _subject_can_receive_resource(
	subject: Dictionary,
	resource: StringName
) -> bool:
	if subject.is_empty():
		return false
	if resource == Catalog.RESOURCE_KI:
		return true
	if resource == Catalog.RESOURCE_POWERS:
		var card: Dictionary = subject.get("card", {})
		return Rules.can_change_powers(card) and (card.get("powers", []) as Array).size() == 4
	return false


static func _resolve_ki_events_now(
	result: Dictionary,
	event_resolver: Callable
) -> void:
	if not event_resolver.is_valid():
		return
	var initial_events: Array = (result.get("events", []) as Array).duplicate()
	for event_value: Variant in initial_events:
		if (
			not event_value is Dictionary
			or StringName((event_value as Dictionary).get("type", &"")) != &"ki_changed"
		):
			continue
		var ki_event: Dictionary = event_value
		ki_event["ki_trigger_resolved"] = true
		var resolution_value: Variant = event_resolver.call(
			Catalog.CARD_KI_CHANGED,
			{
				"trigger_cell": int(ki_event.get("target_cell", -1)),
				"trigger_instance_id": StringName(ki_event.get("instance_id", &"")),
				"trigger_owner_id": int(ki_event.get("owner_id", 0)),
				"previous_ki": int(ki_event.get("previous_ki", 0)),
				"ki": int(ki_event.get("ki", 0)),
				"change_reason": StringName(ki_event.get("change_reason", &"")),
			}
		)
		if resolution_value is Dictionary:
			_merge_action_resolution(result, resolution_value as Dictionary)


static func _for_each_selected_card(
	state: StateData,
	source_cell: int,
	declaration: Dictionary,
	context: Dictionary,
	attack_resolver: Callable,
	flip_resolver: Callable,
	summon_resolver: Callable,
	before_move_resolver: Callable,
	event_resolver: Callable
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
		nested_context["defer_power_change_batch"] = true
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
			before_move_resolver,
			event_resolver
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
	requested_count: int,
	weapon_filter: String,
	context: Dictionary,
	event_resolver: Callable
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	var owner_id: int = int(source.get("owner_id", 0))
	if source.is_empty():
		var snapshot: Dictionary = _get_action_subject_snapshot(context)
		if (
			StringName(snapshot.get("instance_id", &"")) != source_instance_id
			or int(snapshot.get("owner_id", 0)) != expected_owner
		):
			return _no_effect(source_cell)
		owner_id = expected_owner
	if requested_count <= 0:
		return _no_effect(source_cell)
	var hand: Array = state.get_hand(owner_id)
	var deck: Array = state.decks.get(owner_id, [])
	var result: Dictionary = _no_effect(source_cell)
	for _draw_index: int in range(requested_count):
		if hand.size() >= MAX_HAND_SIZE:
			break
		var drawn_card: Dictionary
		var deck_index: int = 0
		if not weapon_filter.is_empty():
			deck_index = -1
			for candidate_index: int in range(deck.size()):
				var candidate_value: Variant = deck[candidate_index]
				if (
					candidate_value is Dictionary
					and String((candidate_value as Dictionary).get("weapon", ""))
					== weapon_filter
				):
					deck_index = candidate_index
					break
			if deck_index < 0:
				break
		elif deck.is_empty():
			var instance_id: StringName = _make_generated_instance_id(
				state,
				EMPTY_DECK_DRAW_CARD_ID
			)
			drawn_card = Catalog.create_instance(
				EMPTY_DECK_DRAW_CARD_ID,
				owner_id,
				instance_id
			)
		else:
			deck_index = 0
		if deck_index >= 0 and not deck.is_empty():
			drawn_card = deck.pop_at(deck_index)
		hand.append(drawn_card)
		var logical_hand_index: int = hand.size() - 1
		var drawn_instance_id := StringName(drawn_card.get("instance_id", &""))
		result["result"] = Catalog.ACTION_RESULT_APPLIED
		result["events"].append({
			"type": &"card_drawn",
			"source_cell": source_cell,
			"owner_id": owner_id,
			"card_id": StringName(drawn_card.get("card_id", &"")),
			"instance_id": drawn_instance_id,
			"logical_hand_index": logical_hand_index,
			"card": drawn_card.duplicate(true),
		})
		for observer_value: Variant in Revelation.get_future_draw_audiences(state, owner_id):
			var observer_owner_id: int = int(observer_value)
			if Revelation.reveal_to(drawn_card, observer_owner_id):
				result["events"].append({
					"type": &"card_revealed",
					"source_cell": source_cell,
					"owner_id": owner_id,
					"observer_owner_id": observer_owner_id,
					"card_id": StringName(drawn_card.get("card_id", &"")),
					"instance_id": drawn_instance_id,
					"logical_hand_index": logical_hand_index,
				})
		if event_resolver.is_valid():
			var drawn_context: Dictionary = context.duplicate(true)
			drawn_context["trigger_cell"] = -1
			drawn_context["trigger_instance_id"] = drawn_instance_id
			drawn_context["trigger_owner_id"] = owner_id
			drawn_context["trigger_zone"] = Catalog.CARD_ZONE_HAND
			drawn_context["trigger_logical_index"] = logical_hand_index
			var snapshots: Dictionary = drawn_context.get("card_reference_snapshots", {}).duplicate(true)
			snapshots[Catalog.CARD_REF_TRIGGER_CARD] = _snapshot_card_reference(
				state,
				drawn_instance_id
			)
			drawn_context["card_reference_snapshots"] = snapshots
			var resolution_value: Variant = event_resolver.call(
				Catalog.CARD_AFTER_DRAWN,
				drawn_context
			)
			if resolution_value is Dictionary:
				_merge_action_resolution(result, resolution_value as Dictionary)
	return result


static func _reveal_hand_cards(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	recipient: StringName,
	reveal_filter: StringName,
	context: Dictionary
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	var observer_owner_id: int = int(source.get("owner_id", 0))
	if source.is_empty():
		var snapshot: Dictionary = _get_action_subject_snapshot(context)
		if (
			StringName(snapshot.get("instance_id", &"")) != source_instance_id
			or int(snapshot.get("owner_id", 0)) != expected_owner
		):
			return _no_effect(source_cell)
		observer_owner_id = expected_owner
	if recipient not in Catalog.KNOWN_RECIPIENTS or reveal_filter not in Catalog.KNOWN_REVEAL_FILTERS:
		return _no_effect(source_cell)
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


static func _reveal_card(
	state: StateData,
	source_cell: int,
	card_reference: StringName,
	observer_reference: StringName,
	context: Dictionary
) -> Dictionary:
	var snapshot: Dictionary = _get_reference_snapshot(context, card_reference)
	var instance_id := StringName(snapshot.get("instance_id", &""))
	var expected_owner: int = int(snapshot.get("owner_id", 0))
	var target: Dictionary = _get_subject(state, instance_id, expected_owner)
	if target.is_empty():
		return _no_effect(source_cell)
	var observer_owner_id: int = _resolve_owner_reference(
		observer_reference,
		context,
		target
	)
	var card: Dictionary = target.get("card", {})
	if not Revelation.reveal_to(card, observer_owner_id):
		return _no_effect(source_cell)
	var logical_index: int = int(target.get("index", -1))
	return _applied(source_cell, [{
		"type": &"card_revealed",
		"source_cell": source_cell,
		"owner_id": int(target.get("owner_id", 0)),
		"observer_owner_id": observer_owner_id,
		"card_id": StringName(card.get("card_id", &"")),
		"instance_id": instance_id,
		"zone": StringName(target.get("zone", &"")),
		"logical_hand_index": (
			logical_index
			if StringName(target.get("zone", &"")) == Catalog.CARD_ZONE_HAND
			else -1
		),
		"target_cell": _get_location_cell(target),
	}])


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


static func _resolve_owner_reference(
	reference: StringName,
	context: Dictionary,
	card_location: Dictionary = {}
) -> int:
	var source_owner: int = int(context.get("ability_source_owner_id", 0))
	if reference == Catalog.OWNER_ABILITY_SOURCE:
		return source_owner
	if reference == Catalog.OWNER_OPPONENT_OF_ABILITY_SOURCE:
		return (
			Rules.OPPONENT_OWNER
			if source_owner == Rules.PLAYER_OWNER
			else Rules.PLAYER_OWNER
		)
	if reference == Catalog.OWNER_CARD_CURRENT:
		return int(card_location.get("owner_id", 0))
	return 0


static func _exile_referenced_card(
	state: StateData,
	source_cell: int,
	card_reference: StringName,
	context: Dictionary,
	event_resolver: Callable
) -> Dictionary:
	var snapshot: Dictionary = _get_reference_snapshot(context, card_reference)
	if snapshot.is_empty() and card_reference == Catalog.CARD_REF_TRIGGER_CARD:
		snapshot = _snapshot_context_trigger_card(state, context)
	var target_instance_id := StringName(snapshot.get("instance_id", &""))
	var subject: Dictionary = _locate_snapshot_subject(state, snapshot)
	if subject.is_empty():
		return _no_effect(source_cell)
	if card_reference == Catalog.CARD_REF_SELECTED_CARD:
		subject = Selector.revalidate(
			state,
			target_instance_id,
			StringName(context.get("ability_source_instance_id", &"")),
			context.get("selected_card_conditions", []) as Array,
			context
		)
		if subject.is_empty():
			return _no_effect(source_cell)
	var ability_source_instance_id := StringName(
		context.get("ability_source_instance_id", &"")
	)
	return _exile_subject(
		state,
		subject,
		source_cell,
		ability_source_instance_id,
		ability_source_instance_id == target_instance_id,
		&"ability_exile_card",
		context,
		event_resolver
	)


static func _depart_referenced_card_for_resummon(
	state: StateData,
	source_cell: int,
	card_reference: StringName,
	context: Dictionary
) -> Dictionary:
	var snapshot: Dictionary = _get_reference_snapshot(context, card_reference)
	var subject: Dictionary = _locate_snapshot_subject(state, snapshot)
	if subject.is_empty() or StringName(subject.get("zone", &"")) != Catalog.CARD_ZONE_BOARD:
		return _no_effect(source_cell)
	var target_cell: int = int(subject.get("index", -1))
	if target_cell < 0 or target_cell >= state.board.size():
		return _no_effect(source_cell)
	var target_card: Dictionary = subject.get("card", {})
	var target_instance_id := StringName(target_card.get("instance_id", &""))
	var card_id := StringName(target_card.get("card_id", &""))
	if target_instance_id == &"" or not Catalog.has_card(card_id):
		return _no_effect(source_cell)
	var ability_source_snapshot: Dictionary = _get_reference_snapshot(
		context,
		Catalog.CARD_REF_ABILITY_SOURCE
	)
	var ability_source_cell: int = int(ability_source_snapshot.get("index", source_cell))
	state.board[target_cell] = null
	return _applied(ability_source_cell, [{
		"type": &"card_departed_for_resummon",
		"source_cell": ability_source_cell,
		"source_instance_id": StringName(context.get("ability_source_instance_id", &"")),
		"target_cell": target_cell,
		"owner_id": int(subject.get("owner_id", 0)),
		"old_instance_id": target_instance_id,
		"card_id": card_id,
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
	var attack_policy: Dictionary = {}
	var source_owner: int = int(source_slot.get("owner", 0))
	if Abilities.has_modifier(
		source_slot.get("card", {}),
		Catalog.MODIFIER_SELF_ATTACKS_ALL,
		state.get_enabled_effect_gates(source_owner)
	):
		attack_policy["attack_target_policy"] = Catalog.ATTACK_TARGET_ALL
	var rules_context: Dictionary = {
		"reason": &"card_summoned_reaction",
		"trigger_context": context,
	}
	rules_context.merge(attack_policy, true)
	if not Rules.can_attack_target(
		state.board,
		source_cell,
		target_cell,
		rules_context
	):
		return _no_effect(source_cell)
	var result: Dictionary = _applied(source_cell)
	var request: Dictionary = {
		"mode": &"targeted",
		"source_cell": source_cell,
		"source_instance_id": source_instance_id,
		"source_owner_id": source_owner,
		"target_cell": target_cell,
		"target_instance_id": target_instance_id,
		"target_owner_id": int(target_slot.get("owner", 0)),
		"reason": &"card_summoned_reaction",
	}
	if not attack_policy.is_empty():
		request["attack_policy"] = attack_policy
	result["attack_requests"].append(request)
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


static func _change_powers(
	state: StateData,
	source_cell: int,
	target_instance_id: StringName,
	expected_owner: int,
	amount_value: Variant,
	context: Dictionary,
	event_resolver: Callable
) -> Dictionary:
	var target: Dictionary = _get_subject(state, target_instance_id, expected_owner)
	if target.is_empty():
		return _no_effect(source_cell)
	var card: Dictionary = target.get("card", {})
	if not Rules.can_change_powers(card):
		return _no_effect(source_cell)
	var amount: int = _resolve_power_change_amount(state, target, amount_value, context)
	if amount == 0:
		return _no_effect(source_cell)
	var previous_powers: Array = (card.get("powers", []) as Array).duplicate()
	if previous_powers.size() != 4:
		return _no_effect(source_cell)
	var resulting_powers: Array = previous_powers.duplicate()
	for power_index: int in range(resulting_powers.size()):
		resulting_powers[power_index] = maxi(
			0,
			int(resulting_powers[power_index]) + amount
		)
	card["powers"] = resulting_powers
	var current_cell: int = _get_location_cell(target)
	var events: Array = [{
		"type": &"powers_changed",
		"source_cell": source_cell,
		"target_cell": current_cell,
		"owner_id": int(target.get("owner_id", 0)),
		"instance_id": target_instance_id,
		"ability_source_instance_id": StringName(
			context.get("ability_source_instance_id", &"")
		),
		"previous_powers": previous_powers,
		"powers": resulting_powers.duplicate(),
		"amount": amount,
		"change_reason": Catalog.ACTION_CHANGE_POWERS,
		"zone": StringName(target.get("zone", &"")),
		"logical_index": int(target.get("index", -1)),
	}]
	var result: Dictionary = _applied(source_cell, events)
	if amount < 0 and resulting_powers == [0, 0, 0, 0]:
		var exile_result: Dictionary = _exile_subject(
			state,
			target,
			source_cell,
			StringName(context.get("ability_source_instance_id", &"")),
			StringName(context.get("ability_source_instance_id", &"")) == target_instance_id,
			&"power_reached_zero",
			context,
			event_resolver
		)
		_merge_action_resolution(result, exile_result)
	return result


static func _resolve_power_change_amount(
	state: StateData,
	target: Dictionary,
	value: Variant,
	context: Dictionary
) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if not value is Dictionary:
		return 0
	var spec: Dictionary = value
	if (
		StringName(spec.get("type", &"")) != Catalog.VALUE_CARD_COUNT
		or StringName(spec.get("zone", &"")) != Catalog.CARD_ZONE_HAND
	):
		return 0
	var owner_id: int = 0
	var owner_reference := StringName(spec.get("owner", &""))
	if owner_reference == Catalog.OWNER_ABILITY_SOURCE:
		var ability_source: Dictionary = Selector.locate_card(
			state,
			StringName(context.get("ability_source_instance_id", &""))
		)
		owner_id = int(ability_source.get("owner_id", 0))
	elif owner_reference == Catalog.OWNER_CARD_CURRENT:
		owner_id = int(target.get("owner_id", 0))
	if owner_id not in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		return 0
	var count: int = 0
	for card_value: Variant in state.get_hand(owner_id):
		if card_value is Dictionary:
			count += 1
	return count


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
	context: Dictionary,
	event_resolver: Callable
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
	if recipient_reference != Catalog.OWNER_CARD_CURRENT:
		recipient_owner = _resolve_owner_reference(recipient_reference, context, subject)
		if recipient_owner not in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
			return _no_effect(source_cell)
	var hand: Array = state.get_hand(recipient_owner)
	if hand.size() >= MAX_HAND_SIZE:
		return _exile_subject(
			state,
			subject,
			source_current_cell,
			StringName(context.get("ability_source_instance_id", &"")),
			card_reference == Catalog.CARD_REF_ABILITY_SOURCE,
			&"return_to_full_hand",
			context,
			event_resolver
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
	var existing_removed_instance_id: StringName = &""
	if typeof(card_spec) in [TYPE_STRING, TYPE_STRING_NAME]:
		var card_reference := StringName(card_spec)
		var card_snapshot: Dictionary = _get_reference_snapshot(context, card_reference)
		existing_instance_id = StringName(card_snapshot.get("instance_id", &""))
		var existing_location: Dictionary = Selector.locate_card(state, existing_instance_id)
		var existing_zone := StringName(existing_location.get("zone", &""))
		if existing_location.is_empty() or existing_zone not in [
			Catalog.CARD_ZONE_HAND,
			Catalog.CARD_ZONE_REMOVED,
		]:
			return _no_effect(source_cell)
		card_id = StringName((existing_location.get("card", {}) as Dictionary).get("card_id", &""))
		if existing_zone == Catalog.CARD_ZONE_REMOVED:
			existing_removed_instance_id = existing_instance_id
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
	elif StringName(cell_spec.get("type", &"")) == Catalog.CELL_REF_ACTIVATION_TARGET:
		target_cell = int(context.get("target_index", -1))
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
	var summoned_instance_id: StringName = (
		existing_instance_id
		if existing_instance_id != &""
		else _make_generated_instance_id(state, card_id)
	)
	if summoned_instance_id == &"":
		return _no_effect(source_cell)
	var result: Dictionary = _applied(current_source_cell if current_source_cell >= 0 else source_cell)
	result["summon_requests"].append({
		"source_cell": current_source_cell if current_source_cell >= 0 else int(source_snapshot.get("index", source_cell)),
		"source_instance_id": source_instance_id,
		"source_owner_id": source_owner,
		"target_cell": target_cell,
		"card_id": card_id,
		"instance_id": summoned_instance_id,
		"existing_hand_instance_id": (
			existing_instance_id if existing_removed_instance_id == &"" else &""
		),
		"existing_removed_instance_id": existing_removed_instance_id,
		"requires_source": requires_adjacent_source,
		"requires_adjacent_source": requires_adjacent_source,
		"reason": &"ability_fresh_copy",
	})
	var reference_snapshots: Dictionary = context.get("card_reference_snapshots", {})
	reference_snapshots[Catalog.CARD_REF_LAST_SUMMONED_CARD] = {
		"instance_id": summoned_instance_id,
		"card_id": card_id,
		"owner_id": source_owner,
		"zone": Catalog.CARD_ZONE_BOARD,
		"index": target_cell,
	}
	context["card_reference_snapshots"] = reference_snapshots
	return result


static func _request_card_resummon(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	card_reference: StringName,
	context: Dictionary
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if source.is_empty() or StringName(source.get("zone", &"")) != Catalog.CARD_ZONE_BOARD:
		return _no_effect(source_cell)
	var target_snapshot: Dictionary = _get_reference_snapshot(context, card_reference)
	var target_instance_id := StringName(target_snapshot.get("instance_id", &""))
	var target: Dictionary = Selector.locate_card(state, target_instance_id)
	if (
		target.is_empty()
		or StringName(target.get("zone", &"")) != Catalog.CARD_ZONE_BOARD
	):
		return _no_effect(int(source.get("index", source_cell)))
	var target_card: Dictionary = target.get("card", {})
	var card_id := StringName(target_card.get("card_id", &""))
	if not Catalog.has_card(card_id):
		return _no_effect(int(source.get("index", source_cell)))
	var target_cell: int = int(target.get("index", -1))
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
		"old_instance_id": target_instance_id,
		"card_id": card_id,
	}])
	result["summon_requests"].append({
		"source_cell": source_current_cell,
		"source_instance_id": source_instance_id,
		"source_owner_id": source_owner,
		"target_cell": target_cell,
		"card_id": card_id,
		"instance_id": new_instance_id,
		"old_instance_id": target_instance_id,
		"requires_source": false,
		"requires_adjacent_source": false,
		"reason": &"ability_resummon_in_place",
	})
	return result


static func _exile_self(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	context: Dictionary,
	event_resolver: Callable
) -> Dictionary:
	var subject: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	if subject.is_empty() or StringName(subject.get("zone", &"")) != Catalog.CARD_ZONE_BOARD:
		return _no_effect(source_cell)
	return _exile_subject(
		state,
		subject,
		int(subject.get("index", source_cell)),
		source_instance_id,
		true,
		&"ability_exile_self",
		context,
		event_resolver
	)


static func _exile_subject(
	state: StateData,
	subject: Dictionary,
	source_cell: int,
	ability_source_instance_id: StringName,
	self_removal: bool,
	exile_reason: StringName,
	context: Dictionary,
	event_resolver: Callable
) -> Dictionary:
	var target_card: Dictionary = subject.get("card", {})
	var target_instance_id := StringName(target_card.get("instance_id", &""))
	var initial_zone := StringName(subject.get("zone", &""))
	var initial_index: int = int(subject.get("index", -1))
	var initial_owner: int = int(subject.get("owner_id", 0))
	var exile_identity := target_instance_id
	if exile_identity == &"":
		exile_identity = StringName(
			"legacy:%s:%d:%d" % [String(initial_zone), initial_owner, initial_index]
		)
	var exile_stack: Array = context.get("exile_in_progress_instance_ids", [])
	if exile_identity in exile_stack:
		return _no_effect(source_cell)
	var current_subject: Dictionary = _locate_exact_subject(
		state,
		target_instance_id,
		initial_zone,
		initial_index,
		initial_owner
	)
	if current_subject.is_empty() or initial_zone not in [
		Catalog.CARD_ZONE_BOARD,
		Catalog.CARD_ZONE_HAND,
	]:
		return _no_effect(source_cell)
	var result: Dictionary = _no_effect(source_cell)
	if initial_zone in [Catalog.CARD_ZONE_BOARD, Catalog.CARD_ZONE_HAND] and event_resolver.is_valid():
		var before_context: Dictionary = context.duplicate(true)
		var target_cell: int = (
			int(current_subject.get("index", -1))
			if initial_zone == Catalog.CARD_ZONE_BOARD
			else -1
		)
		var trigger_logical_index: int = int(current_subject.get("index", -1))
		var target_owner: int = int(current_subject.get("owner_id", 0))
		before_context["trigger_cell"] = target_cell
		before_context["trigger_instance_id"] = target_instance_id
		before_context["trigger_owner_id"] = target_owner
		before_context["trigger_zone"] = initial_zone
		before_context["trigger_logical_index"] = trigger_logical_index
		before_context["exile_reason"] = exile_reason
		var nested_stack: Array = exile_stack.duplicate()
		nested_stack.append(exile_identity)
		before_context["exile_in_progress_instance_ids"] = nested_stack
		var snapshots: Dictionary = before_context.get("card_reference_snapshots", {}).duplicate(true)
		snapshots[Catalog.CARD_REF_TRIGGER_CARD] = _snapshot_location(current_subject)
		before_context["card_reference_snapshots"] = snapshots
		var before_value: Variant = event_resolver.call(
			Catalog.CARD_BEFORE_EXILED,
			before_context
		)
		if before_value is Dictionary:
			_merge_action_resolution(result, before_value as Dictionary)
	current_subject = _locate_exact_subject(
		state,
		target_instance_id,
		initial_zone,
		initial_index,
		initial_owner
	)
	if current_subject.is_empty():
		return result
	var zone := StringName(current_subject.get("zone", &""))
	var logical_index: int = int(current_subject.get("index", -1))
	var current_owner: int = int(current_subject.get("owner_id", 0))
	target_card = current_subject.get("card", {})
	if zone == Catalog.CARD_ZONE_BOARD:
		if (
			logical_index < 0
			or logical_index >= state.board.size()
			or state.board[logical_index] == null
		):
			return result
		state.board[logical_index] = null
	elif zone == Catalog.CARD_ZONE_HAND:
		var hand: Array = state.get_hand(current_owner)
		if (
			logical_index < 0
			or logical_index >= hand.size()
			or not hand[logical_index] is Dictionary
			or StringName((hand[logical_index] as Dictionary).get("instance_id", &""))
			!= target_instance_id
		):
			return result
		hand.remove_at(logical_index)
	else:
		return result
	var original_owner: int = int(target_card.get("original_owner", 0))
	if original_owner not in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		original_owner = current_owner
	if not state.removed_cards.has(original_owner):
		state.removed_cards[original_owner] = []
	(state.removed_cards[original_owner] as Array).append(target_card)
	var exile_result: Dictionary = _applied(source_cell, [{
		"type": &"card_exiled",
		"source_cell": source_cell,
		"source_instance_id": ability_source_instance_id,
		"target_cell": logical_index if zone == Catalog.CARD_ZONE_BOARD else -1,
		"owner_id": current_owner,
		"original_owner": original_owner,
		"instance_id": target_instance_id,
		"self_removal": self_removal,
		"zone": zone,
		"logical_index": logical_index,
		"exile_reason": exile_reason,
	}])
	_merge_action_resolution(result, exile_result)
	return result


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
	amount: int,
	context: Dictionary
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	var owner_id: int = int(source.get("owner_id", 0))
	var current_cell: int = _get_location_cell(source)
	if source.is_empty():
		var snapshot: Dictionary = _get_action_subject_snapshot(context)
		if (
			StringName(snapshot.get("instance_id", &"")) != source_instance_id
			or int(snapshot.get("owner_id", 0)) != expected_owner
		):
			return _no_effect(source_cell)
		owner_id = expected_owner
		current_cell = int(snapshot.get("index", source_cell))
	if amount <= 0:
		return _no_effect(source_cell)
	var result: Dictionary = _applied(source_cell)
	result["extra_turn_requests"].append({
		"owner_id": owner_id,
		"source_cell": current_cell,
		"source_instance_id": source_instance_id,
		"amount": amount,
	})
	return result


static func _add_pending_non_retained_suppression(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	recipient: StringName,
	amount: int,
	context: Dictionary
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	var source_owner: int = int(source.get("owner_id", 0))
	if source.is_empty():
		var snapshot: Dictionary = _get_action_subject_snapshot(context)
		if (
			StringName(snapshot.get("instance_id", &"")) != source_instance_id
			or int(snapshot.get("owner_id", 0)) != expected_owner
		):
			return _no_effect(source_cell)
		source_owner = expected_owner
	if recipient not in Catalog.KNOWN_RECIPIENTS or amount <= 0:
		return _no_effect(source_cell)
	var recipient_owner: int = _resolve_recipient_owner(source_owner, recipient)
	var previous_count: int = int(
		state.pending_non_retained_suppression_by_owner.get(recipient_owner, 0)
	)
	var pending_count: int = previous_count + amount
	state.pending_non_retained_suppression_by_owner[recipient_owner] = pending_count
	return _applied(source_cell, [{
		"type": &"non_retained_suppression_added",
		"source_cell": source_cell,
		"source_instance_id": source_instance_id,
		"owner_id": recipient_owner,
		"amount": amount,
		"pending_count": pending_count,
	}])


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


static func _swap_self_with_trigger_card(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	context: Dictionary,
	before_move_resolver: Callable = Callable()
) -> Dictionary:
	var source: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	var trigger_instance_id := StringName(context.get("trigger_instance_id", &""))
	var trigger_owner: int = int(context.get("trigger_owner_id", 0))
	var trigger: Dictionary = _get_subject(state, trigger_instance_id, trigger_owner)
	if (
		source.is_empty()
		or trigger.is_empty()
		or source_instance_id == trigger_instance_id
		or StringName(source.get("zone", &"")) != Catalog.CARD_ZONE_BOARD
		or StringName(trigger.get("zone", &"")) != Catalog.CARD_ZONE_BOARD
	):
		return _no_effect(source_cell)
	var current_source_cell: int = int(source.get("index", -1))
	var trigger_cell: int = int(trigger.get("index", -1))
	if not _are_adjacent(current_source_cell, trigger_cell):
		return _no_effect(source_cell)
	return _swap_board_cards(
		state,
		current_source_cell,
		source_instance_id,
		expected_owner,
		trigger_cell,
		trigger_instance_id,
		trigger_owner,
		before_move_resolver
	)


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
	expected_owner: int,
	repeat_attack: bool = false,
	target_policy: StringName = &""
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
	var request: Dictionary = {
		"mode": &"standard",
		"source_cell": source_cell,
		"source_instance_id": source_instance_id,
		"source_owner_id": int(source_slot.get("owner", 0)),
		"reason": &"activated_ability",
		"repeat_attack": repeat_attack,
	}
	if target_policy != &"":
		request["attack_policy"] = {"attack_target_policy": target_policy}
	result["attack_requests"].append(request)
	return result


static func _request_standard_attack_with_card(
	state: StateData,
	source_cell: int,
	card_reference: StringName,
	context: Dictionary
) -> Dictionary:
	var snapshot: Dictionary = _get_reference_snapshot(context, card_reference)
	var subject: Dictionary = _locate_snapshot_subject(state, snapshot)
	if (
		subject.is_empty()
		or StringName(subject.get("zone", &"")) != Catalog.CARD_ZONE_BOARD
	):
		return _no_effect(source_cell)
	var current_cell: int = int(subject.get("index", -1))
	var current_owner: int = int(subject.get("owner_id", 0))
	var card: Dictionary = subject.get("card", {})
	return _request_standard_attack(
		state,
		current_cell,
		StringName(card.get("instance_id", &"")),
		current_owner
	)


static func _request_flip_self(
	state: StateData,
	source_cell: int,
	source_instance_id: StringName,
	expected_owner: int,
	new_owner_reference: StringName,
	context: Dictionary
) -> Dictionary:
	var subject: Dictionary = _get_subject(state, source_instance_id, expected_owner)
	var ability_source_owner: int = int(context.get("ability_source_owner_id", 0))
	var new_owner: int = _resolve_owner_reference(new_owner_reference, context)
	if (
		subject.is_empty()
		or StringName(subject.get("zone", &"")) != Catalog.CARD_ZONE_BOARD
		or ability_source_owner not in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]
		or new_owner not in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]
		or int(subject.get("owner_id", 0)) == new_owner
	):
		return _no_effect(source_cell)
	var result: Dictionary = _applied(source_cell)
	result["flip_requests"].append({
		"target_instance_id": source_instance_id,
		"new_owner_id": new_owner,
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
	return _snapshot_location(location)


static func _snapshot_location(location: Dictionary) -> Dictionary:
	var card: Dictionary = location.get("card", {})
	return {
		"instance_id": StringName(card.get("instance_id", &"")),
		"card_id": StringName(card.get("card_id", &"")),
		"owner_id": int(location.get("owner_id", 0)),
		"zone": StringName(location.get("zone", &"")),
		"index": int(location.get("index", -1)),
	}


static func _snapshot_context_trigger_card(
	state: StateData,
	context: Dictionary
) -> Dictionary:
	var trigger_cell: int = int(context.get("trigger_cell", -1))
	if trigger_cell < 0:
		trigger_cell = int(context.get("attacked_cell", -1))
	var trigger_instance_id := StringName(context.get("trigger_instance_id", &""))
	if trigger_instance_id == &"":
		trigger_instance_id = StringName(context.get("attacked_instance_id", &""))
	var trigger_owner: int = int(context.get("trigger_owner_id", 0))
	if trigger_owner == 0:
		trigger_owner = int(context.get("attacked_owner_id", 0))
	var subject: Dictionary = _locate_exact_subject(
		state,
		trigger_instance_id,
		Catalog.CARD_ZONE_BOARD,
		trigger_cell,
		trigger_owner
	)
	return _snapshot_location(subject) if not subject.is_empty() else {}


static func _locate_snapshot_subject(state: StateData, snapshot: Dictionary) -> Dictionary:
	return _locate_exact_subject(
		state,
		StringName(snapshot.get("instance_id", &"")),
		StringName(snapshot.get("zone", &"")),
		int(snapshot.get("index", -1)),
		int(snapshot.get("owner_id", 0))
	)


static func _locate_exact_subject(
	state: StateData,
	instance_id: StringName,
	zone: StringName,
	index: int,
	owner_id: int
) -> Dictionary:
	if instance_id != &"":
		return Selector.locate_card(state, instance_id)
	if zone == Catalog.CARD_ZONE_BOARD:
		if index < 0 or index >= state.board.size() or state.board[index] == null:
			return {}
		var slot: Dictionary = state.board[index]
		var card: Dictionary = slot.get("card", {})
		if StringName(card.get("instance_id", &"")) != &"":
			return {}
		return {
			"zone": zone,
			"owner_id": int(slot.get("owner", 0)),
			"index": index,
			"card": card,
		}
	if zone == Catalog.CARD_ZONE_HAND and owner_id in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		var hand: Array = state.get_hand(owner_id)
		if index < 0 or index >= hand.size() or not hand[index] is Dictionary:
			return {}
		var card: Dictionary = hand[index]
		if StringName(card.get("instance_id", &"")) != &"":
			return {}
		return {
			"zone": zone,
			"owner_id": owner_id,
			"index": index,
			"card": card,
		}
	return {}


static func _get_reference_snapshot(
	context: Dictionary,
	card_reference: StringName
) -> Dictionary:
	var snapshots: Dictionary = context.get("card_reference_snapshots", {})
	var snapshot_value: Variant = snapshots.get(card_reference, {})
	return snapshot_value as Dictionary if snapshot_value is Dictionary else {}


static func _get_action_subject_snapshot(context: Dictionary) -> Dictionary:
	var snapshot_value: Variant = context.get("action_subject_snapshot", {})
	return snapshot_value as Dictionary if snapshot_value is Dictionary else {}


static func _get_location_cell(location: Dictionary) -> int:
	if StringName(location.get("zone", &"")) != Catalog.CARD_ZONE_BOARD:
		return -1
	return int(location.get("index", -1))


static func _make_power_change_batch_id(
	source_instance_id: StringName,
	context: Dictionary,
	action_index: int,
	batch_group: StringName = &""
) -> StringName:
	return StringName(
		"%s|%s|%d|%d|%s"
		% [
			String(source_instance_id),
			String(context.get("resolving_event_id", &"direct")),
			int(context.get("resolving_ability_index", -1)),
			int(context.get("resolving_trigger_index", -1)),
			String(batch_group) if batch_group != &"" else str(action_index),
		]
	)


static func _assign_power_change_batch(events: Array, batch_id: StringName) -> void:
	var has_power_change: bool = false
	for event_value: Variant in events:
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &""))
			== &"powers_changed"
		):
			has_power_change = true
			break
	if not has_power_change:
		return
	for event_value: Variant in events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		if StringName(event.get("type", &"")) in [&"powers_changed", &"card_exiled"]:
			event["power_change_batch_id"] = batch_id


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


static func _merge_action_resolution(target: Dictionary, source: Dictionary) -> void:
	for key: StringName in [
		&"events",
		&"attack_requests",
		&"flip_requests",
		&"summon_requests",
		&"extra_turn_requests",
		&"flip_prevention_requests",
		&"captures",
		&"exiles",
	]:
		if not target.has(key):
			target[key] = []
		var source_values: Variant = source.get(key, [])
		if source_values is Array:
			(target[key] as Array).append_array(source_values as Array)
	if StringName(source.get("result", &"")) == Catalog.ACTION_RESULT_APPLIED:
		target["result"] = Catalog.ACTION_RESULT_APPLIED


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
