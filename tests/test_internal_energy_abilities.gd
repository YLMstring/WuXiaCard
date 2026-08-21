extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Abilities = preload("res://scripts/duel_abilities.gd")
const Action = preload("res://scripts/duel_action.gd")
const Executor = preload("res://scripts/duel_ability_executor.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const Triggers = preload("res://scripts/duel_triggers.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_vocabulary_and_declarations()
	_test_can_spend_ki_semantics()
	_test_transfer_ki_and_power_fallback()
	_test_failed_leftmost_hand_absorb_advances()
	_test_distribute_ki_cycles_board_then_hand()
	_test_initial_flip_grants_without_distribution()
	_test_second_flip_distributes_then_attacks()
	_test_entry_flip_cancels_standard_attack()
	_test_xixing_later_attack_targets_all_while_beiming_does_not()
	_test_standard_attack_stops_after_mid_chain_double_flip()
	_test_yijin_strengthens_then_draws_and_repeats_on_return()
	_finish()


func _test_catalog_vocabulary_and_declarations() -> void:
	_check(
		Catalog.ACTION_TRANSFER_CARD_RESOURCE in Catalog.KNOWN_ACTIONS
		and Catalog.ACTION_DISTRIBUTE_KI in Catalog.KNOWN_ACTIONS,
		"Generic resource-transfer actions are registered"
	)
	_check(
		Catalog.CONDITION_SELECTED_CARD_CAN_SPEND_KI in Catalog.KNOWN_SELECTOR_CONDITIONS
		and Catalog.CONDITION_SELECTED_CARD_CAN_TRANSFER_RESOURCE
		in Catalog.KNOWN_SELECTOR_CONDITIONS,
		"Ki-use and transferable-resource selector conditions are registered"
	)
	_check(
		Catalog.MODIFIER_SELF_ATTACKS_ALL in Catalog.KNOWN_MODIFIERS,
		"Self-indiscriminate attack modifier is registered"
	)
	for card_id: StringName in [&"XiXinDaFa4", &"XiXinDaFa5", &"YiJJ5"]:
		var abilities: Array = Catalog.get_definition(card_id).get("abilities", [])
		_check(not abilities.is_empty(), "%s declares complete abilities" % card_id)
		for ability_value: Variant in abilities:
			_check(
				ability_value is Dictionary
				and Catalog.validate_ability(ability_value as Dictionary, card_id).is_empty(),
				"%s ability passes catalog validation" % card_id
			)
	_check(
		(Catalog.get_definition(&"XiXinDaFa4").get("abilities", []) as Array).size() == 3,
		"XiXin declares locked attack, entry flip, and isolated first-flip grant"
	)
	_check(
		(Catalog.get_definition(&"XiXinDaFa5").get("abilities", []) as Array).size() == 2,
		"BeiMing omits only XiXin's locked self-attack modifier"
	)
	_check(
		(Catalog.get_definition(&"YiJJ5").get("abilities", []) as Array).size() == 2,
		"YiJin separates entry and retained self-after-flip rules"
	)


func _test_can_spend_ki_semantics() -> void:
	var activation_card: Dictionary = Catalog.create_instance(
		&"YouFenLaiYi2",
		Rules.PLAYER_OWNER,
		&"ki_activation"
	)
	var automatic_card: Dictionary = Catalog.create_instance(
		&"SanQinFeng1",
		Rules.PLAYER_OWNER,
		&"ki_automatic"
	)
	var nested_card: Dictionary = _plain(&"ki_nested", [1, 1, 1, 1], Rules.PLAYER_OWNER)
	nested_card["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_START_OWNER_TURN,
			"actions": [{
				"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {"zones": [Catalog.CARD_ZONE_BOARD]},
				"actions": [{"type": Catalog.ACTION_SPEND_KI, "amount": 1}],
			}],
		}],
	}]
	var spend_all_card: Dictionary = _plain(
		&"ki_spend_all",
		[1, 1, 1, 1],
		Rules.PLAYER_OWNER
	)
	spend_all_card["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_END_OWNER_TURN,
			"actions": [{"type": Catalog.ACTION_SPEND_ALL_KI}],
		}],
	}]
	var passive: Dictionary = _plain(&"ki_passive", [1, 1, 1, 1], Rules.PLAYER_OWNER)
	_check(
		Abilities.card_can_spend_ki(activation_card)
		and Abilities.card_can_spend_ki(automatic_card)
		and Abilities.card_can_spend_ki(nested_card)
		and Abilities.card_can_spend_ki(spend_all_card)
		and not Abilities.card_can_spend_ki(passive),
		"Ki eligibility includes active, automatic, nested, and spend-all abilities"
	)
	activation_card["effect_gate"] = Catalog.EFFECT_GATE_SELF_CASTRATION
	_check(
		not Abilities.card_can_spend_ki(activation_card, [])
		and Abilities.card_can_spend_ki(
			activation_card,
			[Catalog.EFFECT_GATE_SELF_CASTRATION]
		),
		"Disabled gated abilities do not provide ki-spend eligibility"
	)


func _test_transfer_ki_and_power_fallback() -> void:
	var source: Dictionary = _plain(&"transfer_source", [1, 1, 1, 1], Rules.PLAYER_OWNER)
	var ki_target: Dictionary = _plain(&"transfer_ki", [4, 4, 4, 4], Rules.PLAYER_OWNER)
	ki_target["ki"] = 2
	var board: Array = Rules.empty_board()
	board[4] = _slot(source, Rules.PLAYER_OWNER)
	var state := State.new(board, [ki_target])
	source = _runtime_card(state, &"transfer_source")
	ki_target = _runtime_card(state, &"transfer_ki")
	var ki_result: Dictionary = _execute_transfer(state, &"transfer_ki")
	_check(
		int(source.get("ki", -1)) == 1
		and int(ki_target.get("ki", -1)) == 1
		and _event_instance_ids(ki_result.get("events", []), &"ki_changed")
		== [&"transfer_ki", &"transfer_source"],
		"Resource transfer moves ki before considering powers"
	)

	var power_source: Dictionary = _plain(
		&"power_source",
		[1, 1, 1, 1],
		Rules.PLAYER_OWNER
	)
	var power_target: Dictionary = _plain(
		&"power_target",
		[0, 2, 0, 1],
		Rules.PLAYER_OWNER
	)
	var power_board: Array = Rules.empty_board()
	power_board[4] = _slot(power_source, Rules.PLAYER_OWNER)
	var power_state := State.new(power_board, [power_target])
	power_source = _runtime_card(power_state, &"power_source")
	power_target = _runtime_card(power_state, &"power_target")
	var power_result: Dictionary = _execute_transfer(power_state, &"power_target")
	var power_events: Array[Dictionary] = _events_of_type(
		power_result.get("events", []),
		&"powers_changed"
	)
	_check(
		power_target.get("powers", []) == [0, 1, 0, 0]
		and power_source.get("powers", []) == [2, 2, 2, 2],
		"Power fallback floors the donor and grants all four receiver sides"
	)
	_check(
		power_events.size() == 2
		and StringName(power_events[0].get("power_change_batch_id", &"")) != &""
		and power_events[0].get("power_change_batch_id")
		== power_events[1].get("power_change_batch_id"),
		"Both halves of one power transfer share a presentation batch"
	)

	var sentinel_source: Dictionary = _plain(
		&"sentinel_source",
		[1, 1, 1, 1],
		Rules.PLAYER_OWNER
	)
	var sentinel: Dictionary = _plain(
		&"sentinel_target",
		[-1, -1, -1, -1],
		Rules.PLAYER_OWNER
	)
	var sentinel_board: Array = Rules.empty_board()
	sentinel_board[4] = _slot(sentinel_source, Rules.PLAYER_OWNER)
	var sentinel_state := State.new(sentinel_board, [sentinel])
	sentinel_source = _runtime_card(sentinel_state, &"sentinel_source")
	sentinel = _runtime_card(sentinel_state, &"sentinel_target")
	var sentinel_result: Dictionary = _execute_transfer(sentinel_state, &"sentinel_target")
	_check(
		StringName(sentinel_result.get("result", &"")) == Catalog.ACTION_RESULT_NO_EFFECT
		and sentinel_source.get("powers", []) == [1, 1, 1, 1]
		and sentinel.get("powers", []) == [-1, -1, -1, -1],
		"Four-negative cards with no ki cannot donate powers"
	)

	var exile_source: Dictionary = _plain(&"exile_source", [1, 1, 1, 1], Rules.PLAYER_OWNER)
	var exile_target: Dictionary = _plain(&"exile_target", [0, 1, 0, 0], Rules.PLAYER_OWNER)
	var exile_survivor: Dictionary = _plain(&"exile_survivor", [5, 5, 5, 5], Rules.PLAYER_OWNER)
	exile_target["hand_slot_index"] = 1
	exile_survivor["hand_slot_index"] = 4
	var exile_board: Array = Rules.empty_board()
	exile_board[4] = _slot(exile_source, Rules.PLAYER_OWNER)
	var exile_state := State.new(exile_board, [exile_survivor, exile_target])
	exile_source = _runtime_card(exile_state, &"exile_source")
	var exile_result: Dictionary = _execute_transfer(exile_state, &"exile_target")
	var survivor_after: Dictionary = _runtime_card(exile_state, &"exile_survivor")
	_check(
		exile_state.get_hand(Rules.PLAYER_OWNER).size() == 1
		and _event_types(exile_result.get("events", [])).has(&"card_exiled")
		and not _event_types(exile_result.get("events", [])).has(&"hand_cards_shifted")
		and int(survivor_after.get("hand_slot_index", -1)) == 4
		and exile_source.get("powers", []) == [2, 2, 2, 2],
		"A hand donor reaching four zero is exiled without shifting other hand slots"
	)


func _test_failed_leftmost_hand_absorb_advances() -> void:
	var source: Dictionary = _plain(&"advance_source", [1, 1, 1, 1], Rules.PLAYER_OWNER)
	var sentinel: Dictionary = _plain(&"advance_sentinel", [-1, -1, -1, -1], Rules.PLAYER_OWNER)
	var valid: Dictionary = _plain(&"advance_valid", [3, 3, 3, 3], Rules.PLAYER_OWNER)
	var board: Array = Rules.empty_board()
	board[4] = _slot(source, Rules.PLAYER_OWNER)
	var state := State.new(board, [sentinel, valid])
	source = _runtime_card(state, &"advance_source")
	sentinel = _runtime_card(state, &"advance_sentinel")
	valid = _runtime_card(state, &"advance_valid")
	var result: Dictionary = Executor.execute_actions(
		state,
		4,
		&"advance_source",
		Rules.PLAYER_OWNER,
		[{
			"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
			"selector": {
				"zones": [Catalog.CARD_ZONE_HAND],
				"conditions": [
					{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY},
					_transferable_condition(),
				],
				"limit": 1,
			},
			"actions": [_transfer_action()],
		}],
		{}
	)
	_check(
		StringName(result.get("result", &"")) == Catalog.ACTION_RESULT_APPLIED
		and sentinel.get("powers", []) == [-1, -1, -1, -1]
		and valid.get("powers", []) == [2, 2, 2, 2]
		and source.get("powers", []) == [2, 2, 2, 2],
		"Failed leftmost hand absorption advances to the next transferable card"
	)


func _test_distribute_ki_cycles_board_then_hand() -> void:
	var source: Dictionary = _plain(&"distribution_source", [2, 2, 2, 2], Rules.PLAYER_OWNER)
	source["ki"] = 5
	var board_auto: Dictionary = Catalog.create_instance(
		&"SanQinFeng1",
		Rules.PLAYER_OWNER,
		&"distribution_board_auto"
	)
	var board_active: Dictionary = Catalog.create_instance(
		&"YouFenLaiYi2",
		Rules.PLAYER_OWNER,
		&"distribution_board_active"
	)
	board_active["ki"] = 0
	var board_passive: Dictionary = _plain(
		&"distribution_board_passive",
		[1, 1, 1, 1],
		Rules.PLAYER_OWNER
	)
	var hand_auto: Dictionary = Catalog.create_instance(
		&"SanQinFeng1",
		Rules.PLAYER_OWNER,
		&"distribution_hand_auto"
	)
	var board: Array = Rules.empty_board()
	board[0] = _slot(board_auto, Rules.PLAYER_OWNER)
	board[1] = _slot(board_passive, Rules.PLAYER_OWNER)
	board[2] = _slot(board_active, Rules.PLAYER_OWNER)
	board[4] = _slot(source, Rules.PLAYER_OWNER)
	var state := State.new(board, [hand_auto])
	source = _runtime_card(state, &"distribution_source")
	board_auto = _runtime_card(state, &"distribution_board_auto")
	board_active = _runtime_card(state, &"distribution_board_active")
	board_passive = _runtime_card(state, &"distribution_board_passive")
	hand_auto = _runtime_card(state, &"distribution_hand_auto")
	var result: Dictionary = Executor.execute_actions(
		state,
		4,
		&"distribution_source",
		Rules.PLAYER_OWNER,
		[_distribution_action()],
		{}
	)
	var recipients: Array[StringName] = []
	for instance_id: StringName in _event_instance_ids(result.get("events", []), &"ki_changed"):
		if instance_id != &"distribution_source":
			recipients.append(instance_id)
	_check(
		int(source.get("ki", -1)) == 0
		and int(board_auto.get("ki", -1)) == 2
		and int(board_active.get("ki", -1)) == 2
		and int(hand_auto.get("ki", -1)) == 1
		and int(board_passive.get("ki", -1)) == 0,
		"Distribution includes automatic and active ki spenders but skips passive cards"
	)
	_check(
		recipients == [
			&"distribution_board_auto",
			&"distribution_board_active",
			&"distribution_hand_auto",
			&"distribution_board_auto",
			&"distribution_board_active",
		],
		"Distribution cycles board row-major then hand left-to-right until empty"
	)

	var quiet_source: Dictionary = _plain(&"quiet_source", [1, 1, 1, 1], Rules.PLAYER_OWNER)
	quiet_source["ki"] = 3
	var quiet_board: Array = Rules.empty_board()
	quiet_board[4] = _slot(quiet_source, Rules.PLAYER_OWNER)
	var quiet_state := State.new(
		quiet_board,
		[_plain(&"quiet_passive", [1, 1, 1, 1], Rules.PLAYER_OWNER)]
	)
	quiet_source = _runtime_card(quiet_state, &"quiet_source")
	var quiet_result: Dictionary = Executor.execute_actions(
		quiet_state,
		4,
		&"quiet_source",
		Rules.PLAYER_OWNER,
		[_distribution_action()],
		{}
	)
	_check(
		int(quiet_source.get("ki", -1)) == 3
		and StringName(quiet_result.get("result", &"")) == Catalog.ACTION_RESULT_NO_EFFECT,
		"No eligible recipient leaves remaining source ki untouched"
	)


func _test_initial_flip_grants_without_distribution() -> void:
	for card_id: StringName in [&"XiXinDaFa4", &"XiXinDaFa5"]:
		var source: Dictionary = Catalog.create_instance(
			card_id,
			Rules.PLAYER_OWNER,
			StringName("initial_%s" % card_id)
		)
		source["ki"] = 3
		var board: Array = Rules.empty_board()
		board[4] = _slot(source, Rules.PLAYER_OWNER)
		var state := State.new(board)
		source = _runtime_card(state, StringName("initial_%s" % card_id))
		var result: Dictionary = Simulator.resolve_non_attack_flip(
			state,
			StringName(source.get("instance_id", &"")),
			Rules.OPPONENT_OWNER,
			&"initial_grant_fixture"
		)
		var expected_count: int = 4 if card_id == &"XiXinDaFa4" else 3
		_check(
			int((state.board[4] as Dictionary).get("owner", 0)) == Rules.OPPONENT_OWNER
			and int(source.get("ki", -1)) == 3
			and (source.get("active_abilities", []) as Array).size() == expected_count
			and _event_types(result.get("events", [])).count(&"attack_started") == 0,
			"%s initial flip only grants its later effects" % card_id
		)


func _test_second_flip_distributes_then_attacks() -> void:
	var source: Dictionary = Catalog.create_instance(
		&"XiXinDaFa5",
		Rules.PLAYER_OWNER,
		&"second_flip_source"
	)
	var board: Array = Rules.empty_board()
	board[4] = _slot(source, Rules.PLAYER_OWNER)
	var player_board_auto: Dictionary = Catalog.create_instance(
		&"SanQinFeng1",
		Rules.PLAYER_OWNER,
		&"second_board_auto"
	)
	var player_board_active: Dictionary = Catalog.create_instance(
		&"YouFenLaiYi2",
		Rules.PLAYER_OWNER,
		&"second_board_active"
	)
	player_board_active["ki"] = 0
	var player_hand_auto: Dictionary = Catalog.create_instance(
		&"SanQinFeng1",
		Rules.PLAYER_OWNER,
		&"second_hand_auto"
	)
	board[0] = _slot(player_board_auto, Rules.PLAYER_OWNER)
	board[2] = _slot(player_board_active, Rules.PLAYER_OWNER)
	board[5] = _slot(
		_plain(&"second_attack_target", [0, 0, 0, 0], Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	var state := State.new(board, [player_hand_auto])
	source = _runtime_card(state, &"second_flip_source")
	player_board_auto = _runtime_card(state, &"second_board_auto")
	player_board_active = _runtime_card(state, &"second_board_active")
	player_hand_auto = _runtime_card(state, &"second_hand_auto")
	Simulator.resolve_non_attack_flip(
		state,
		&"second_flip_source",
		Rules.OPPONENT_OWNER,
		&"initial_flip"
	)
	source["ki"] = 5
	var result: Dictionary = Simulator.resolve_non_attack_flip(
		state,
		&"second_flip_source",
		Rules.PLAYER_OWNER,
		&"second_flip"
	)
	var types: Array[StringName] = _event_types(result.get("events", []))
	_check(
		int(source.get("ki", -1)) == 0
		and int(player_board_auto.get("ki", -1)) == 2
		and int(player_board_active.get("ki", -1)) == 2
		and int(player_hand_auto.get("ki", -1)) == 1,
		"Second flip distributes every source ki using the approved cycle"
	)
	_check(
		types.has(&"attack_started")
		and types.rfind(&"ki_changed") < types.find(&"attack_started")
		and int((state.board[5] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER,
		"Second flip completes distribution before its normal attack"
	)


func _test_entry_flip_cancels_standard_attack() -> void:
	for card_id: StringName in [&"XiXinDaFa4", &"XiXinDaFa5"]:
		var source_id := StringName("entry_cancel_%s" % card_id)
		var source: Dictionary = Catalog.create_instance(
			card_id,
			Rules.PLAYER_OWNER,
			source_id
		)
		var future_enemy: Dictionary = _plain(
			StringName("entry_enemy_%s" % card_id),
			[0, 0, 0, 0],
			Rules.PLAYER_OWNER
		)
		var board: Array = Rules.empty_board()
		board[5] = _slot(future_enemy, Rules.PLAYER_OWNER)
		var transition: Dictionary = Simulator.apply_action(
			State.new(board, [source], [], Rules.PLAYER_OWNER),
			Action.make_play(0, 4, source_id)
		)
		_check(
			int(((transition.get("state") as State).board[5] as Dictionary).get("owner", 0))
			== Rules.PLAYER_OWNER
			and not _event_types(transition.get("events", [])).has(&"attack_started"),
			"%s changing owner on entry cancels its standard summon attack" % card_id
		)


func _test_xixing_later_attack_targets_all_while_beiming_does_not() -> void:
	for card_id: StringName in [&"XiXinDaFa4", &"XiXinDaFa5"]:
		var source_id := StringName("later_policy_%s" % card_id)
		var source: Dictionary = Catalog.create_instance(
			card_id,
			Rules.PLAYER_OWNER,
			source_id
		)
		var ally_id := StringName("later_ally_%s" % card_id)
		var board: Array = Rules.empty_board()
		board[4] = _slot(source, Rules.PLAYER_OWNER)
		board[5] = _slot(
			_plain(ally_id, [0, 0, 0, 0], Rules.PLAYER_OWNER),
			Rules.PLAYER_OWNER
		)
		var state := State.new(board)
		Simulator.resolve_non_attack_flip(
			state,
			source_id,
			Rules.OPPONENT_OWNER,
			&"initial_flip"
		)
		var result: Dictionary = Simulator.resolve_non_attack_flip(
			state,
			source_id,
			Rules.PLAYER_OWNER,
			&"later_flip"
		)
		var expected_owner: int = (
			Rules.OPPONENT_OWNER if card_id == &"XiXinDaFa4" else Rules.PLAYER_OWNER
		)
		_check(
			int((state.board[5] as Dictionary).get("owner", 0)) == expected_owner
			and (
				_event_types(result.get("events", [])).has(&"attack_started")
				== (card_id == &"XiXinDaFa4")
			),
			"%s applies its target policy only when a later attack is actually started"
			% card_id
		)

	var targeted_source: Dictionary = Catalog.create_instance(
		&"XiXinDaFa4",
		Rules.PLAYER_OWNER,
		&"targeted_xixing"
	)
	var targeted_board: Array = Rules.empty_board()
	targeted_board[4] = _slot(targeted_source, Rules.PLAYER_OWNER)
	targeted_board[5] = _slot(
		_plain(&"targeted_ally", [0, 0, 0, 0], Rules.PLAYER_OWNER),
		Rules.PLAYER_OWNER
	)
	var targeted_state := State.new(targeted_board)
	var request_result: Dictionary = Executor.execute_actions(
		targeted_state,
		4,
		&"targeted_xixing",
		Rules.PLAYER_OWNER,
		[{"type": Catalog.ACTION_ATTACK_TRIGGER_CARD}],
		{
			"trigger_cell": 5,
			"trigger_instance_id": &"targeted_ally",
			"trigger_owner_id": Rules.PLAYER_OWNER,
		}
	)
	var attack_requests: Array = request_result.get("attack_requests", []) as Array
	var targeted_result: Dictionary = Simulator._resolve_attack_request(
		targeted_state,
		attack_requests[0] as Dictionary if not attack_requests.is_empty() else {}
	)
	_check(
		attack_requests.size() == 1
		and (attack_requests[0] as Dictionary).get("attack_policy", {}).get(
			"attack_target_policy",
			&""
		) == Catalog.ATTACK_TARGET_ALL
		and _event_types(targeted_result.get("events", [])).has(&"attack_started")
		and int((targeted_state.board[5] as Dictionary).get("owner", 0))
		== Rules.OPPONENT_OWNER,
		"XiXin's locked target policy also permits a specified attack on an ally"
	)


func _test_standard_attack_stops_after_mid_chain_double_flip() -> void:
	var source: Dictionary = _plain(
		&"mid_flip_source",
		[5, 5, 5, 5],
		Rules.PLAYER_OWNER
	)
	var counter: Dictionary = _plain(
		&"mid_flip_counter",
		[1, 1, 1, 1],
		Rules.OPPONENT_OWNER
	)
	counter["active_abilities"] = [
		{
			"retained_on_flip": true,
			"modifiers": [{"type": Catalog.MODIFIER_SELF_ATTACKS_ALL}],
		},
		{
			"triggers": [{
				"event": Catalog.CARD_BE_ATTACKED,
				"conditions": [{"type": Catalog.CONDITION_ATTACKED_CARD_IS_SELF}],
				"actions": [
					{
						"type": Catalog.ACTION_CHANGE_POWERS,
						"amount": 10,
						"card": Catalog.CARD_REF_ABILITY_SOURCE,
					},
					{"type": Catalog.ACTION_STANDARD_ATTACK_WITH_SELF},
					{"type": Catalog.ACTION_STANDARD_ATTACK_WITH_SELF},
				],
			}],
		},
	]
	var second_target: Dictionary = _plain(
		&"mid_flip_second",
		[1, 1, 1, 1],
		Rules.OPPONENT_OWNER
	)
	var board: Array = Rules.empty_board()
	board[1] = _slot(counter, Rules.OPPONENT_OWNER)
	board[4] = _slot(source, Rules.PLAYER_OWNER)
	board[5] = _slot(second_target, Rules.OPPONENT_OWNER)
	var state := State.new(board)
	var result: Dictionary = Simulator._resolve_standard_attacks(
		state,
		4,
		&"mid_flip_source",
		&"mid_chain_double_flip_fixture",
		false,
		{"attack_target_policy": Catalog.ATTACK_TARGET_ALL}
	)
	var source_flip_count: int = 0
	var attacked_second: bool = false
	for event_value: Variant in result.get("events", []):
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value as Dictionary
		if (
			StringName(event.get("type", &"")) == &"card_flipped"
			and StringName(event.get("instance_id", &"")) == &"mid_flip_source"
		):
			source_flip_count += 1
		if (
			StringName(event.get("type", &"")) == &"attack_started"
			and StringName(event.get("source_instance_id", &"")) == &"mid_flip_source"
			and StringName(event.get("target_instance_id", &"")) == &"mid_flip_second"
		):
			attacked_second = true
	_check(
		source_flip_count == 2
		and int((state.board[4] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER
		and int((state.board[5] as Dictionary).get("owner", 0))
		== Rules.OPPONENT_OWNER
		and not attacked_second,
		(
			"Any mid-chain attacker flip stops later standard-attack targets even after flipping back; "
			+ "source_flips=%d source_owner=%d second_owner=%d attacked_second=%s events=%s"
			% [
				source_flip_count,
				int((state.board[4] as Dictionary).get("owner", 0)),
				int((state.board[5] as Dictionary).get("owner", 0)),
				attacked_second,
				_event_types(result.get("events", [])),
			]
		)
	)


func _test_yijin_strengthens_then_draws_and_repeats_on_return() -> void:
	var yijin: Dictionary = Catalog.create_instance(
		&"YiJJ5",
		Rules.PLAYER_OWNER,
		&"yijin_source"
	)
	var sentinel: Dictionary = _plain(&"yijin_sentinel", [-1, -1, -1, -1], Rules.PLAYER_OWNER)
	var ordinary: Dictionary = _plain(&"yijin_ordinary", [2, 2, 2, 2], Rules.PLAYER_OWNER)
	var first_draw: Dictionary = _plain(&"yijin_first_draw", [4, 4, 4, 4], Rules.PLAYER_OWNER)
	var second_draw: Dictionary = _plain(&"yijin_second_draw", [5, 5, 5, 5], Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			Rules.empty_board(),
			[yijin, sentinel, ordinary],
			[],
			Rules.PLAYER_OWNER,
			0,
			[first_draw, second_draw]
		),
		Action.make_play(0, 4, &"yijin_source")
	)
	var state: State = transition.get("state") as State
	sentinel = _runtime_card(state, &"yijin_sentinel")
	ordinary = _runtime_card(state, &"yijin_ordinary")
	first_draw = _runtime_card(state, &"yijin_first_draw")
	var hand: Array = state.get_hand(Rules.PLAYER_OWNER)
	_check(
		sentinel.get("powers", []) == [-1, -1, -1, -1]
		and int(sentinel.get("ki", -1)) == 1
		and ordinary.get("powers", []) == [3, 3, 3, 3]
		and int(ordinary.get("ki", -1)) == 1
		and hand.size() == 3
		and (hand[2] as Dictionary).get("powers", []) == [4, 4, 4, 4]
		and int((hand[2] as Dictionary).get("ki", -1)) == 0,
		"YiJin strengthens the old hand, preserves sentinel powers, then draws"
	)
	var power_events: Array[Dictionary] = _events_of_type(
		transition.get("events", []),
		&"powers_changed"
	)
	_check(
		power_events.size() == 1
		and StringName(power_events[0].get("power_change_batch_id", &"")) != &""
		and _event_types(transition.get("events", [])).find(&"powers_changed")
		< _event_types(transition.get("events", [])).find(&"card_drawn"),
		"YiJin batches legal old-hand powers before drawing"
	)
	Simulator.resolve_non_attack_flip(state, &"yijin_source", Rules.OPPONENT_OWNER, &"away")
	_check(
		ordinary.get("powers", []) == [3, 3, 3, 3]
		and state.get_hand(Rules.OPPONENT_OWNER).is_empty(),
		"YiJin does not trigger when flipping away from its original owner"
	)
	var return_result: Dictionary = Simulator.resolve_non_attack_flip(
		state,
		&"yijin_source",
		Rules.PLAYER_OWNER,
		&"return"
	)
	hand = state.get_hand(Rules.PLAYER_OWNER)
	_check(
		ordinary.get("powers", []) == [4, 4, 4, 4]
		and int(ordinary.get("ki", -1)) == 2
		and first_draw.get("powers", []) == [5, 5, 5, 5]
		and int(first_draw.get("ki", -1)) == 1
		and hand.size() == 4
		and (hand[3] as Dictionary).get("powers", []) == [5, 5, 5, 5]
		and int((hand[3] as Dictionary).get("ki", -1)) == 0
		and _event_types(return_result.get("events", [])).has(&"card_drawn"),
		"YiJin repeats only after returning and excludes its newly drawn card"
	)


func _execute_transfer(state: State, target_instance_id: StringName) -> Dictionary:
	return Executor.execute_actions(
		state,
		4,
		StringName((((state.board[4] as Dictionary).get("card", {}) as Dictionary).get(
			"instance_id",
			&""
		))),
		Rules.PLAYER_OWNER,
		[_transfer_action()],
		{"selected_card_instance_id": target_instance_id}
	)


func _transfer_action() -> Dictionary:
	return {
		"type": Catalog.ACTION_TRANSFER_CARD_RESOURCE,
		"from": Catalog.CARD_REF_SELECTED_CARD,
		"to": Catalog.CARD_REF_ABILITY_SOURCE,
		"amount": 1,
		"resource": Catalog.RESOURCE_KI,
		"fallback_resource": Catalog.RESOURCE_POWERS,
	}


func _transferable_condition() -> Dictionary:
	return {
		"type": Catalog.CONDITION_SELECTED_CARD_CAN_TRANSFER_RESOURCE,
		"amount": 1,
		"resource": Catalog.RESOURCE_KI,
		"fallback_resource": Catalog.RESOURCE_POWERS,
	}


func _distribution_action() -> Dictionary:
	return {
		"type": Catalog.ACTION_DISTRIBUTE_KI,
		"from": Catalog.CARD_REF_ABILITY_SOURCE,
		"amount": 1,
		"selector": {
			"zones": [Catalog.CARD_ZONE_BOARD, Catalog.CARD_ZONE_HAND],
			"conditions": [
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY},
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
				{"type": Catalog.CONDITION_SELECTED_CARD_CAN_SPEND_KI},
			],
		},
	}


func _plain(
	instance_id: StringName,
	powers: Array[int],
	original_owner: int
) -> Dictionary:
	var card: Dictionary = Rules.make_card(
		String(instance_id),
		"测",
		powers,
		[],
		original_owner
	)
	card["card_id"] = instance_id
	card["instance_id"] = instance_id
	card["original_owner"] = original_owner
	card["ki"] = 0
	return card


func _runtime_card(state: State, instance_id: StringName) -> Dictionary:
	for slot_value: Variant in state.board:
		if slot_value is Dictionary:
			var card: Dictionary = (slot_value as Dictionary).get("card", {}) as Dictionary
			if StringName(card.get("instance_id", &"")) == instance_id:
				return card
	for owner_id: int in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		for zone: Array in [
			state.get_hand(owner_id),
			state.decks.get(owner_id, []) as Array,
			state.removed_cards.get(owner_id, []) as Array,
		]:
			for card_value: Variant in zone:
				if card_value is Dictionary:
					var card: Dictionary = card_value as Dictionary
					if StringName(card.get("instance_id", &"")) == instance_id:
						return card
	return {}


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _events_of_type(events: Array, event_type: StringName) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for event_value: Variant in events:
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
		):
			matches.append(event_value as Dictionary)
	return matches


func _event_types(events: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for event_value: Variant in events:
		if event_value is Dictionary:
			result.append(StringName((event_value as Dictionary).get("type", &"")))
	return result


func _event_instance_ids(events: Array, event_type: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for event: Dictionary in _events_of_type(events, event_type):
		result.append(StringName(event.get("instance_id", &"")))
	return result


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)


func _finish() -> void:
	if _failures == 0:
		print("INTERNAL_ENERGY_ABILITY_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"INTERNAL_ENERGY_ABILITY_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)
