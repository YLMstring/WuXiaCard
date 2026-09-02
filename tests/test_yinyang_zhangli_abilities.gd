extends SceneTree

const CARD_SCENE: PackedScene = preload("res://scenes/card_view.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const Action = preload("res://scripts/duel_action.gd")
const Abilities = preload("res://scripts/duel_abilities.gd")
const Executor = preload("res://scripts/duel_ability_executor.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_and_special_power_vocabulary()
	await _test_special_power_presentation()
	_test_power_change_immunity_and_selector_skip()
	_test_distance_two_attack_rules()
	_test_entry_draw_and_grant_order()
	_test_empty_draw_and_no_palm_edges()
	_test_filtered_draw_respects_hand_capacity()
	_test_repeat_attack_is_nonrecursive()
	_test_grant_deduplication_and_flip_loss()
	_finish()


func _test_catalog_and_special_power_vocabulary() -> void:
	_check(
		Catalog.CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE
		in Catalog.KNOWN_SELECTOR_CONDITIONS,
		"Mutable-power selector conditions are registered"
	)
	_check(
		Catalog.MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO in Catalog.KNOWN_MODIFIERS,
		"Distance-two attack modifiers are registered"
	)
	_check(
		Catalog.CONDITION_ATTACK_IS_NOT_REPEAT in Catalog.KNOWN_TRIGGER_CONDITIONS,
		"Non-repeat attack conditions are registered"
	)
	_check(
		Rules.has_special_negative_powers({"powers": [-1, -1, -1, -1]}),
		"Four negative-one sides use special power rules"
	)
	_check(
		not Rules.has_special_negative_powers({"powers": [-1, 2, 3, 4]})
		and not Rules.has_special_negative_powers({"powers": [0, 0, 0, 0]}),
		"Partial negative-one and ordinary zero powers do not use the sentinel rule"
	)
	for card_id: StringName in [&"YinYangZhang3", &"YinYangZhang4"]:
		var abilities: Array = Catalog.get_definition(card_id).get("abilities", [])
		var actions: Array = (((abilities[0] as Dictionary).get("triggers", []) as Array)[0] as Dictionary).get("actions", [])
		_check(not abilities.is_empty(), "%s declares its complete ability" % card_id)
		_check(
			actions[1] == {
				"type": Catalog.ACTION_DRAW_CARDS,
				"amount": 2,
				"weapon": "掌法",
			},
			"%s draws two palm cards with the generic filtered draw action" % card_id
		)


func _test_special_power_presentation() -> void:
	var sentinel: Control = CARD_SCENE.instantiate() as Control
	root.add_child(sentinel)
	await process_frame
	sentinel.call(
		"configure",
		Catalog.create_instance(&"YinYangZhang3", Rules.PLAYER_OWNER, &"sentinel_view"),
		Rules.PLAYER_OWNER,
		true
	)
	_check(
		_power_labels(sentinel).all(func(label: Label) -> bool: return not label.visible),
		"A revealed four-negative-one card hides all power labels"
	)
	var partial: Control = CARD_SCENE.instantiate() as Control
	root.add_child(partial)
	await process_frame
	partial.call(
		"configure",
		_plain(&"partial_view", [-1, 2, 3, 4], Rules.PLAYER_OWNER),
		Rules.PLAYER_OWNER,
		true
	)
	_check(
		_power_labels(partial).all(func(label: Label) -> bool: return label.visible),
		"A partial negative-one card still displays all four values"
	)
	sentinel.queue_free()
	partial.queue_free()
	await process_frame


func _test_power_change_immunity_and_selector_skip() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(_plain(&"sentinel", [-1, -1, -1, -1], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[1] = _slot(_plain(&"first_legal", [1, 1, 1, 1], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[2] = _slot(_plain(&"second_legal", [2, 2, 2, 2], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[3] = _slot(_plain(&"third_legal", [3, 3, 3, 3], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	board[8] = _slot(_plain(&"power_source", [4, 4, 4, 4], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var state := State.new(board)
	for amount: int in [2, -2]:
		var direct: Dictionary = Executor.execute_actions(
			state,
			8,
			&"power_source",
			Rules.PLAYER_OWNER,
			[{
				"type": Catalog.ACTION_CHANGE_POWERS,
				"amount": amount,
				"card": Catalog.CARD_REF_TRIGGER_CARD,
			}],
			{"trigger_instance_id": &"sentinel"}
		)
		_check(
			((state.board[0] as Dictionary).get("card", {}) as Dictionary).get("powers", [])
			== [-1, -1, -1, -1]
			and (direct.get("events", []) as Array).is_empty(),
			"Signed power change %d cannot target the special sentinel" % amount
		)
	var wrapper: Dictionary = {
		"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
		"selector": {
			"zones": [Catalog.CARD_ZONE_BOARD],
			"conditions": [
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY},
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
				{"type": Catalog.CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE},
			],
			"limit": 2,
		},
		"actions": [{
			"type": Catalog.ACTION_CHANGE_POWERS,
			"amount": 1,
			"card": Catalog.CARD_REF_SELECTED_CARD,
		}],
	}
	var batch: Dictionary = Executor.execute_actions(
		state,
		8,
		&"power_source",
		Rules.PLAYER_OWNER,
		[wrapper],
		{}
	)
	_check(
		((state.board[1] as Dictionary).get("card", {}) as Dictionary).get("powers", [])
		== [2, 2, 2, 2]
		and ((state.board[2] as Dictionary).get("card", {}) as Dictionary).get("powers", [])
		== [3, 3, 3, 3]
		and ((state.board[3] as Dictionary).get("card", {}) as Dictionary).get("powers", [])
		== [3, 3, 3, 3],
		"A limited power selector skips the sentinel and changes the next two legal cards"
	)
	_check(
		_count_events(batch.get("events", []), &"powers_changed") == 2,
		"Skipped sentinels consume no visual or logical power event"
	)


func _test_distance_two_attack_rules() -> void:
	var sentinel_board: Array = Rules.empty_board()
	sentinel_board[4] = _slot(_plain(&"ordinary_attacker", [1, 1, 1, 1], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	sentinel_board[1] = _slot(_plain(&"negative_defender", [-1, -1, -1, -1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	_check(
		Rules.can_attack_target(sentinel_board, 4, 1),
		"Any nonnegative ordinary edge can attack a negative-one defender"
	)

	var tier_three: Dictionary = _plain(&"tier_three_palm", [5, 5, 5, 5], Rules.PLAYER_OWNER)
	tier_three["active_abilities"] = [_range_ability(false)]
	var board: Array = Rules.empty_board()
	board[6] = _slot(tier_three, Rules.PLAYER_OWNER)
	board[0] = _slot(_plain(&"far_enemy", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	_check(Rules.can_attack_target(board, 6, 0), "Tier-three range attacks through one empty cell")
	board[3] = _slot(_plain(&"middle_ally", [1, 1, 1, 1], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	_check(not Rules.can_attack_target(board, 6, 0), "Tier-three range cannot attack through an ally")
	var tier_four: Dictionary = (board[6] as Dictionary).get("card", {})
	tier_four["active_abilities"] = [_range_ability(true)]
	_check(Rules.can_attack_target(board, 6, 0), "Tier-four range attacks through one ally")
	(board[3] as Dictionary)["owner"] = Rules.OPPONENT_OWNER
	_check(not Rules.can_attack_target(board, 6, 0), "Distance-two attacks never pass through an enemy")
	_check(not Rules.can_attack_target(board, 6, 2), "Distance-two attacks remain orthogonal and do not wrap")


func _test_entry_draw_and_grant_order() -> void:
	var yinyang: Dictionary = Catalog.create_instance(
		&"YinYangZhang3",
		Rules.PLAYER_OWNER,
		&"entry_yinyang"
	)
	var existing_palm: Dictionary = _plain(
		&"existing_palm",
		[3, 3, 3, 3],
		Rules.PLAYER_OWNER
	)
	var non_palm: Dictionary = _plain(
		&"existing_sword",
		[3, 3, 3, 3],
		Rules.PLAYER_OWNER,
		"剑法"
	)
	var drawn_palm: Dictionary = _plain(
		&"drawn_palm_one",
		[4, 4, 4, 4],
		Rules.PLAYER_OWNER
	)
	var drawn_palm_two: Dictionary = _plain(
		&"drawn_palm_two",
		[5, 5, 5, 5],
		Rules.PLAYER_OWNER
	)
	var skipped_sword_one: Dictionary = _plain(
		&"skipped_sword_one", [1, 1, 1, 1], Rules.PLAYER_OWNER, "剑法"
	)
	var skipped_sword_two: Dictionary = _plain(
		&"skipped_sword_two", [2, 2, 2, 2], Rules.PLAYER_OWNER, "剑法"
	)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			Rules.empty_board(),
			[yinyang, existing_palm, non_palm],
			[_plain(&"opponent_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
			Rules.PLAYER_OWNER,
			0,
			[skipped_sword_one, drawn_palm, skipped_sword_two, drawn_palm_two],
			[]
		),
		Action.make_play(0, 4, &"entry_yinyang")
	)
	var next_state: State = transition.get("state") as State
	var runtime_existing: Dictionary = _find_hand_card(next_state, &"existing_palm")
	var runtime_drawn: Dictionary = _find_hand_card(next_state, &"drawn_palm_one")
	var runtime_drawn_two: Dictionary = _find_hand_card(next_state, &"drawn_palm_two")
	var runtime_non_palm: Dictionary = _find_hand_card(next_state, &"existing_sword")
	_check(
		bool(transition.get("valid", false))
		and next_state.board[4] == null
		and _removed_has(next_state, Rules.PLAYER_OWNER, &"entry_yinyang"),
		"YinYang exiles itself instead of remaining on the board"
	)
	_check(
		(runtime_existing.get("active_abilities", []) as Array).size() == 2
		and (runtime_drawn.get("active_abilities", []) as Array).size() == 2
		and (runtime_drawn_two.get("active_abilities", []) as Array).size() == 2
		and (runtime_non_palm.get("active_abilities", []) as Array).is_empty(),
		"Existing and both newly drawn palm cards receive both effects, while non-palm cards do not"
	)
	_check(
		Abilities.can_attack_at_orthogonal_distance_two(runtime_drawn)
		and not Abilities.allows_intervening_ally_at_orthogonal_distance_two(runtime_drawn),
		"Tier-three grants the empty-cell distance-two modifier"
	)
	var events: Array = transition.get("events", [])
	var exile_index: int = _event_index(events, &"card_exiled", &"entry_yinyang")
	var draw_index: int = _event_index(events, &"card_drawn", &"drawn_palm_one")
	var second_draw_index: int = _event_index(events, &"card_drawn", &"drawn_palm_two")
	var grant_index: int = _event_index(events, &"ability_gained", &"drawn_palm_one")
	_check(
		exile_index >= 0
		and exile_index < draw_index
		and draw_index < second_draw_index
		and second_draw_index < grant_index,
		"Entry events present exile, two filtered draws, then grants in order"
	)
	var remaining_deck: Array = next_state.decks.get(Rules.PLAYER_OWNER, [])
	_check(
		remaining_deck.size() == 2
		and StringName((remaining_deck[0] as Dictionary).get("instance_id", &"")) == &"skipped_sword_one"
		and StringName((remaining_deck[1] as Dictionary).get("instance_id", &"")) == &"skipped_sword_two",
		"Filtered draws leave skipped non-palms in their original order"
	)
	_check(
		_count_events(events, &"attack_started") == 0,
		"The exiled YinYang card performs no summon standard attack"
	)


func _test_empty_draw_and_no_palm_edges() -> void:
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			Rules.empty_board(),
			[
				Catalog.create_instance(
					&"YinYangZhang4",
					Rules.PLAYER_OWNER,
					&"edge_yinyang"
				),
				_plain(&"edge_sword", [2, 2, 2, 2], Rules.PLAYER_OWNER, "剑法"),
			],
			[_plain(&"edge_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
			Rules.PLAYER_OWNER
		),
		Action.make_play(0, 4, &"edge_yinyang")
	)
	var next_state: State = transition.get("state") as State
	_check(
		_find_hand_card(next_state, &"edge_sword").get("active_abilities", []) == []
		and _count_events(transition.get("events", []), &"card_drawn") == 0
		and next_state.get_hand(Rules.PLAYER_OWNER).size() == 1
		and _count_events(transition.get("events", []), &"ability_gained") == 0,
		"An empty deck draws no filtered fallback card and grants no palm abilities"
	)


func _test_filtered_draw_respects_hand_capacity() -> void:
	var player_hand: Array = [
		Catalog.create_instance(&"YinYangZhang4", Rules.PLAYER_OWNER, &"capacity_yinyang"),
		_plain(&"capacity_one", [1, 1, 1, 1], Rules.PLAYER_OWNER, "剑法"),
		_plain(&"capacity_two", [1, 1, 1, 1], Rules.PLAYER_OWNER, "剑法"),
		_plain(&"capacity_three", [1, 1, 1, 1], Rules.PLAYER_OWNER, "剑法"),
		_plain(&"capacity_four", [1, 1, 1, 1], Rules.PLAYER_OWNER, "剑法"),
	]
	var deck: Array = [
		_plain(&"capacity_palm_one", [2, 2, 2, 2], Rules.PLAYER_OWNER),
		_plain(&"capacity_palm_two", [3, 3, 3, 3], Rules.PLAYER_OWNER),
	]
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			Rules.empty_board(),
			player_hand,
			[_plain(&"capacity_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
			Rules.PLAYER_OWNER,
			0,
			deck,
			[]
		),
		Action.make_play(0, 4, &"capacity_yinyang")
	)
	var next_state: State = transition.get("state") as State
	_check(
		_count_events(transition.get("events", []), &"card_drawn") == 1
		and next_state.get_hand(Rules.PLAYER_OWNER).size() == 5
		and StringName(((next_state.decks[Rules.PLAYER_OWNER] as Array)[0] as Dictionary).get("instance_id", &"")) == &"capacity_palm_two",
		"Filtered draw stops at hand capacity and leaves the second matching card in the deck"
	)


func _test_repeat_attack_is_nonrecursive() -> void:
	var repeat_observer: Dictionary = {
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_ATTACK,
			"conditions": [{"type": Catalog.CONDITION_ATTACKER_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_GAIN_KI, "amount": 1}],
		}],
	}
	var attacker: Dictionary = _plain(
		&"repeat_palm",
		[5, 5, 5, 5],
		Rules.PLAYER_OWNER
	)
	attacker["active_abilities"] = [
		Catalog.YINYANG_REPEAT_ATTACK.duplicate(true),
		repeat_observer,
	]
	var board: Array = Rules.empty_board()
	board[1] = _slot(
		_plain(&"repeat_defender", [1, 1, 1, 1], Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[attacker],
			[_plain(&"repeat_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
			Rules.PLAYER_OWNER
		),
		Action.make_play(0, 4, &"repeat_palm")
	)
	var next_state: State = transition.get("state") as State
	var runtime: Dictionary = (next_state.board[4] as Dictionary).get("card", {})
	_check(
		int(runtime.get("ki", 0)) == 1,
		"After-attack abilities resolve only for the original attack that had a valid target"
	)
	_check(
		_count_events(transition.get("events", []), &"card_flipped") == 1
		and _count_events(transition.get("events", []), &"ki_changed") == 1,
		"A repeat with no remaining legal target has no attack-after effects"
	)


func _test_grant_deduplication_and_flip_loss() -> void:
	var palm: Dictionary = _plain(&"stacked_palm", [5, 5, 5, 5], Rules.PLAYER_OWNER)
	var board: Array = Rules.empty_board()
	board[4] = _slot(palm, Rules.PLAYER_OWNER)
	var state := State.new(board)
	var actions: Array = [
		{"type": Catalog.ACTION_GRANT_ABILITY_TO_SELF, "ability": Catalog.YINYANG_REPEAT_ATTACK},
		{"type": Catalog.ACTION_GRANT_ABILITY_TO_SELF, "ability": Catalog.YINYANG_REPEAT_ATTACK},
		{"type": Catalog.ACTION_GRANT_ABILITY_TO_SELF, "ability": Catalog.YINYANG_RANGE_THREE},
		{"type": Catalog.ACTION_GRANT_ABILITY_TO_SELF, "ability": Catalog.YINYANG_RANGE_FOUR},
	]
	var grant_result: Dictionary = Executor.execute_actions(
		state,
		4,
		&"stacked_palm",
		Rules.PLAYER_OWNER,
		actions,
		{}
	)
	var runtime: Dictionary = (state.board[4] as Dictionary).get("card", {})
	_check(
		(runtime.get("active_abilities", []) as Array).size() == 3
		and _count_events(grant_result.get("events", []), &"ability_gained") == 3,
		"Repeated grants deduplicate the shared repeat ability"
	)
	_check(
		Abilities.can_attack_at_orthogonal_distance_two(runtime)
		and Abilities.allows_intervening_ally_at_orthogonal_distance_two(runtime),
		"Tier-four range remains the effective superset after tier-three and tier-four grants"
	)
	state.board[0] = _slot(
		_plain(&"flip_source", [9, 9, 9, 9], Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	var flip_events: Array[Dictionary] = Executor.resolve_normal_flip(
		state,
		0,
		&"flip_source",
		4,
		&"stacked_palm",
		Rules.OPPONENT_OWNER
	)
	_check(
		(runtime.get("active_abilities", []) as Array).is_empty()
		and _count_events(flip_events, &"ability_lost") == 3,
		"All granted YinYang effects are non-retained and are lost on flip"
	)


func _range_ability(allow_intervening_ally: bool) -> Dictionary:
	return {
		"modifiers": [{
			"type": Catalog.MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO,
			"allow_intervening_ally": allow_intervening_ally,
		}],
	}


func _power_labels(card: Control) -> Array[Label]:
	return [
		card.get_node("Overlay/TopPower") as Label,
		card.get_node("Overlay/RightPower") as Label,
		card.get_node("Overlay/BottomPower") as Label,
		card.get_node("Overlay/LeftPower") as Label,
	]


func _plain(
	instance_id: StringName,
	powers: Array,
	owner_id: int,
	weapon: String = "掌法"
) -> Dictionary:
	return {
		"instance_id": instance_id,
		"card_id": instance_id,
		"glyph": String(instance_id),
		"picture": "",
		"sect": "嵩山派",
		"tier": 1,
		"weapon": weapon,
		"description": "",
		"flavor": "",
		"powers": powers.duplicate(),
		"ki": 0,
		"original_owner": owner_id,
		"active_abilities": [],
		"revealed_to_owner_ids": [owner_id],
	}


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _find_hand_card(state: State, instance_id: StringName) -> Dictionary:
	for owner_id: int in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		for card_value: Variant in state.get_hand(owner_id):
			if (
				card_value is Dictionary
				and StringName((card_value as Dictionary).get("instance_id", &""))
				== instance_id
			):
				return card_value as Dictionary
	return {}


func _removed_has(state: State, owner_id: int, instance_id: StringName) -> bool:
	for card_value: Variant in state.removed_cards.get(owner_id, []):
		if (
			card_value is Dictionary
			and StringName((card_value as Dictionary).get("instance_id", &""))
			== instance_id
		):
			return true
	return false


func _event_index(
	events: Array,
	event_type: StringName,
	instance_id: StringName
) -> int:
	for event_index: int in range(events.size()):
		var event_value: Variant = events[event_index]
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
			and StringName((event_value as Dictionary).get("instance_id", &""))
			== instance_id
		):
			return event_index
	return -1


func _count_events(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for event_value: Variant in events:
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
		):
			count += 1
	return count


func _finish() -> void:
	if _failures == 0:
		print("YINYANG_ZHANGLI_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"YINYANG_ZHANGLI_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
