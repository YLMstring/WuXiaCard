extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Decks = preload("res://scripts/duel_decks.gd")
const ProfileStore = preload("res://scripts/deck_profile_store.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_gate_vocabulary_and_state_copy()
	await _test_duel_enemy_gate_configuration()
	_test_profile_initializes_player_gate()
	_test_player_gate_controls_kuihua_one()
	_test_zero_target_attack_has_no_after_attack_trigger()
	_test_kuihua_two_minimum_defense_and_after_attack_gain()
	_test_kuihua_two_returns_only_from_a_successful_attack()
	_test_kuihua_two_indiscriminate_attack_changes_owners()
	_test_kuihua_three_swaps_only_one_adjacent_enemy()
	_test_kuihua_three_resummons_only_after_flipping_enemy()
	_test_kuihua_four_exiles_targets_and_recursively_enters_copies()
	_test_kuihua_four_is_inert_without_player_gate()
	_finish()


func _test_gate_vocabulary_and_state_copy() -> void:
	_check(
		Catalog.EFFECT_GATE_SELF_CASTRATION in Catalog.KNOWN_EFFECT_GATES,
		"Self-castration is a registered effect gate"
	)


func _test_profile_initializes_player_gate() -> void:
	var profile_path: String = "user://kuihua_gate_profile_test.json"
	_cleanup_profile(profile_path)
	_check(
		Catalog.EFFECT_GATE_SELF_CASTRATION
		not in Decks.get_player_enabled_effect_gates(profile_path),
		"A new normal profile disables player self-castration effects without KuiHua0"
	)
	var store: RefCounted = ProfileStore.new(profile_path)
	var profile: Dictionary = store.create_testing_profile(store.create_default_profile())
	_check(store.save_profile(profile), "A fully unlocked profile saves for gate testing")
	_check(
		Catalog.EFFECT_GATE_SELF_CASTRATION
		in Decks.get_player_enabled_effect_gates(profile_path),
		"An unlocked KuiHua0 enables player self-castration effects"
	)
	(profile["unlocked_card_ids"] as Array).erase("KuiHua0")
	(profile["library_slots"] as Array).erase("KuiHua0")
	(profile["library_slots"] as Array).append("")
	_check(store.save_profile(profile), "A profile without KuiHua0 saves for gate testing")
	_check(
		Catalog.EFFECT_GATE_SELF_CASTRATION
		not in Decks.get_player_enabled_effect_gates(profile_path),
		"A valid profile without KuiHua0 disables player self-castration effects"
	)
	_cleanup_profile(profile_path)
	var state := State.new()
	_check(
		Catalog.EFFECT_GATE_SELF_CASTRATION
		in (state.enabled_effect_gates_by_owner[Rules.OPPONENT_OWNER] as Array),
		"Enemy self-castration effects default to enabled"
	)
	_check(
		Catalog.EFFECT_GATE_SELF_CASTRATION
		not in (state.enabled_effect_gates_by_owner[Rules.PLAYER_OWNER] as Array),
		"Player self-castration effects default to disabled"
	)
	var disabled_key: String = StateKey.build(state)
	state.enabled_effect_gates_by_owner[Rules.PLAYER_OWNER] = [
		Catalog.EFFECT_GATE_SELF_CASTRATION,
	]
	var copied: State = state.duplicate_state() as State
	_check(
		Catalog.EFFECT_GATE_SELF_CASTRATION
		in (copied.enabled_effect_gates_by_owner[Rules.PLAYER_OWNER] as Array),
		"State duplication preserves player effect gates"
	)
	_check(
		disabled_key != StateKey.build(state),
		"State keys distinguish different effect gates"
	)


func _test_duel_enemy_gate_configuration() -> void:
	var enabled_duel: Node = load("res://scenes/duel.tscn").instantiate()
	enabled_duel.set("continue_automatically", false)
	root.add_child(enabled_duel)
	await process_frame
	_check(
		Catalog.EFFECT_GATE_SELF_CASTRATION
		in enabled_duel.duel_state.get_enabled_effect_gates(Rules.OPPONENT_OWNER),
		"A duel enables enemy self-castration effects by default"
	)
	enabled_duel.queue_free()
	await process_frame

	var disabled_duel: Node = load("res://scenes/duel.tscn").instantiate()
	disabled_duel.set("continue_automatically", false)
	disabled_duel.set("opponent_self_castration_enabled", false)
	root.add_child(disabled_duel)
	await process_frame
	_check(
		Catalog.EFFECT_GATE_SELF_CASTRATION
		not in disabled_duel.duel_state.get_enabled_effect_gates(Rules.OPPONENT_OWNER),
		"An explicit duel enemy declaration disables self-castration effects"
	)
	disabled_duel.queue_free()
	await process_frame


func _test_player_gate_controls_kuihua_one() -> void:
	var disabled := State.new(
		Rules.empty_board(),
		[
			Catalog.create_instance(&"KuiHua1", Rules.PLAYER_OWNER, &"disabled_kuihua"),
			_plain(&"disabled_followup", [1, 1, 1, 1], Rules.PLAYER_OWNER),
		],
		[_plain(&"disabled_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER
	)
	var disabled_transition: Dictionary = Simulator.apply_action(
		disabled,
		Action.make_play(0, 4, &"disabled_kuihua")
	)
	_check(
		_count_events(disabled_transition.get("events", []), &"extra_card_play_granted") == 0
		and (disabled_transition.get("state") as State).active_player == Rules.OPPONENT_OWNER,
		"A player without the gate gets no KuiHua1 extra play"
	)

	var enabled := State.new(
		Rules.empty_board(),
		[
			Catalog.create_instance(&"KuiHua1", Rules.PLAYER_OWNER, &"enabled_kuihua"),
			_plain(&"enabled_followup", [1, 1, 1, 1], Rules.PLAYER_OWNER),
		],
		[_plain(&"enabled_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER
	)
	enabled.enabled_effect_gates_by_owner[Rules.PLAYER_OWNER] = [
		Catalog.EFFECT_GATE_SELF_CASTRATION,
	]
	var enabled_transition: Dictionary = Simulator.apply_action(
		enabled,
		Action.make_play(0, 4, &"enabled_kuihua")
	)
	_check(
		_count_events(enabled_transition.get("events", []), &"extra_card_play_granted") == 1
		and (enabled_transition.get("state") as State).active_player == Rules.PLAYER_OWNER,
		"An enabled player receives the KuiHua1 extra play"
	)


func _test_zero_target_attack_has_no_after_attack_trigger() -> void:
	var observer: Dictionary = _plain(
		&"zero_attack_observer",
		[1, 1, 1, 1],
		Rules.PLAYER_OWNER
	)
	observer["active_abilities"] = [{
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_ATTACK,
			"conditions": [{"type": Catalog.CONDITION_ATTACKER_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_GAIN_KI, "amount": 1}],
		}],
	}]
	var board: Array = Rules.empty_board()
	board[1] = _slot(
		_plain(&"too_strong", [9, 9, 9, 9], Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[observer],
			[_plain(&"zero_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
			Rules.PLAYER_OWNER
		),
		Action.make_play(0, 4, &"zero_attack_observer")
	)
	var runtime: Dictionary = (((transition.get("state") as State).board[4] as Dictionary).get(
		"card",
		{}
	))
	_check(
		_count_events(transition.get("events", []), &"attack_started") == 0
		and int(runtime.get("ki", 0)) == 0,
		"An attack with no successful initial target has no after-attack trigger"
	)


func _test_kuihua_two_minimum_defense_and_after_attack_gain() -> void:
	var board: Array = Rules.empty_board()
	board[1] = _slot(
		_plain(&"minimum_defender", [9, 9, 9, 1], Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	var state := State.new(
		board,
		[Catalog.create_instance(&"KuiHua2", Rules.PLAYER_OWNER, &"kuihua_two_attack")],
		[_plain(&"minimum_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER
	)
	_enable_player_kuihua(state)
	var transition: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, 4, &"kuihua_two_attack")
	)
	var next_state: State = transition.get("state") as State
	var runtime: Dictionary = (next_state.board[4] as Dictionary).get("card", {})
	_check(
		int((next_state.board[1] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER,
		"KuiHua2 attacks against the defender's minimum side"
	)
	_check(
		_count_events(transition.get("events", []), &"ability_gained") == 1
		and _card_has_modifier(runtime, Catalog.MODIFIER_ENEMY_ATTACKS_ALL),
		"KuiHua2 gains indiscriminate enemy attacks after a real attack"
	)

	var empty_state := State.new(
		Rules.empty_board(),
		[Catalog.create_instance(&"KuiHua2", Rules.PLAYER_OWNER, &"kuihua_two_no_attack")],
		[_plain(&"no_attack_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER
	)
	_enable_player_kuihua(empty_state)
	var no_attack_transition: Dictionary = Simulator.apply_action(
		empty_state,
		Action.make_play(0, 4, &"kuihua_two_no_attack")
	)
	var no_attack_card: Dictionary = (
		((no_attack_transition.get("state") as State).board[4] as Dictionary).get("card", {})
	)
	_check(
		not _card_has_modifier(no_attack_card, Catalog.MODIFIER_ENEMY_ATTACKS_ALL),
		"KuiHua2 gains nothing when no attack starts"
	)


func _test_kuihua_two_returns_only_from_a_successful_attack() -> void:
	var weak_attack_state: State = _kuihua_two_defense_state([1, 1, 1, 1], &"weak_attacker")
	var weak_transition: Dictionary = Simulator.apply_action(
		weak_attack_state,
		Action.make_play(0, 4, &"weak_attacker")
	)
	var weak_next: State = weak_transition.get("state") as State
	_check(
		_find_hand_card(weak_next.hands[Rules.OPPONENT_OWNER], &"kuihua_two_defender") < 0
		and weak_next.board[1] != null,
		"KuiHua2 does not return when attack power is insufficient"
	)

	var strong_attack_state: State = _kuihua_two_defense_state([9, 9, 9, 9], &"strong_attacker")
	var strong_transition: Dictionary = Simulator.apply_action(
		strong_attack_state,
		Action.make_play(0, 4, &"strong_attacker")
	)
	var strong_next: State = strong_transition.get("state") as State
	_check(
		_find_hand_card_by_card_id(strong_next.hands[Rules.OPPONENT_OWNER], &"KuiHua2") >= 0
		and strong_next.board[1] == null,
		"KuiHua2 returns to its current owner's hand after a successful attack begins"
	)


func _test_kuihua_two_indiscriminate_attack_changes_owners() -> void:
	var board: Array = Rules.empty_board()
	var policy_source: Dictionary = Catalog.create_instance(
		&"KuiHua2",
		Rules.PLAYER_OWNER,
		&"kuihua_two_policy"
	)
	(policy_source["active_abilities"] as Array).append(
		Catalog.KUIHUA_INDISCRIMINATE_ATTACK.duplicate(true)
	)
	board[8] = _slot(policy_source, Rules.PLAYER_OWNER)
	board[1] = _slot(
		_plain(&"attacker_old_ally", [1, 1, 1, 1], Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	board[3] = _slot(
		_plain(&"attacker_enemy", [1, 1, 1, 1], Rules.PLAYER_OWNER),
		Rules.PLAYER_OWNER
	)
	var state := State.new(
		board,
		[_plain(&"policy_reply", [1, 1, 1, 1], Rules.PLAYER_OWNER)],
		[_plain(&"policy_attacker", [9, 9, 9, 9], Rules.OPPONENT_OWNER)],
		Rules.OPPONENT_OWNER
	)
	_enable_player_kuihua(state)
	var transition: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, 4, &"policy_attacker")
	)
	var next_state: State = transition.get("state") as State
	_check(
		int((next_state.board[1] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER,
		"An indiscriminate attack flips the attacker's old ally to KuiHua2's owner"
	)
	_check(
		int((next_state.board[3] as Dictionary).get("owner", 0)) == Rules.OPPONENT_OWNER,
		"An indiscriminate attack still flips a normal enemy to the attacker"
	)
	_check(
		_count_events(transition.get("events", []), &"attack_started") == 2,
		"An indiscriminate attack resolves allied and enemy targets in one attack"
	)


func _test_kuihua_three_swaps_only_one_adjacent_enemy() -> void:
	var single_board: Array = Rules.empty_board()
	single_board[1] = _slot(
		_plain(&"single_adjacent_enemy", [9, 9, 9, 9], Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	var single_state := State.new(
		single_board,
		[Catalog.create_instance(&"KuiHua3", Rules.PLAYER_OWNER, &"kuihua_three_swap")],
		[_plain(&"single_swap_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER
	)
	_enable_player_kuihua(single_state)
	var single_transition: Dictionary = Simulator.apply_action(
		single_state,
		Action.make_play(0, 4, &"kuihua_three_swap")
	)
	var single_next: State = single_transition.get("state") as State
	_check(
		_board_instance_id(single_next, 1) == &"kuihua_three_swap"
		and _board_instance_id(single_next, 4) == &"single_adjacent_enemy",
		"KuiHua3 swaps with its only adjacent enemy after entering"
	)

	var double_board: Array = Rules.empty_board()
	double_board[1] = _slot(
		_plain(&"first_adjacent_enemy", [9, 9, 9, 9], Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	double_board[3] = _slot(
		_plain(&"second_adjacent_enemy", [9, 9, 9, 9], Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	var double_state := State.new(
		double_board,
		[Catalog.create_instance(&"KuiHua3", Rules.PLAYER_OWNER, &"kuihua_three_stay")],
		[_plain(&"double_swap_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER
	)
	_enable_player_kuihua(double_state)
	var double_transition: Dictionary = Simulator.apply_action(
		double_state,
		Action.make_play(0, 4, &"kuihua_three_stay")
	)
	_check(
		_board_instance_id(double_transition.get("state") as State, 4) == &"kuihua_three_stay",
		"KuiHua3 does not swap when two adjacent enemies exist"
	)


func _test_kuihua_three_resummons_only_after_flipping_enemy() -> void:
	var flip_board: Array = Rules.empty_board()
	flip_board[1] = _slot(
		_plain(&"resummon_strong_enemy", [9, 9, 9, 9], Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	flip_board[3] = _slot(
		_plain(&"resummon_weak_enemy", [1, 1, 1, 1], Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	var flip_state := State.new(
		flip_board,
		[Catalog.create_instance(&"KuiHua3", Rules.PLAYER_OWNER, &"kuihua_three_old")],
		[_plain(&"resummon_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER
	)
	_enable_player_kuihua(flip_state)
	var flip_transition: Dictionary = Simulator.apply_action(
		flip_state,
		Action.make_play(0, 4, &"kuihua_three_old")
	)
	var flip_next: State = flip_transition.get("state") as State
	var fresh_cell: int = _find_board_card_id(flip_next, &"KuiHua3")
	_check(
		_count_events(flip_transition.get("events", []), &"card_departed_for_resummon") == 1
		and _count_events(flip_transition.get("events", []), &"card_summoned") == 1
		and fresh_cell == 1
		and _board_instance_id(flip_next, fresh_cell) != &"kuihua_three_old",
		"KuiHua3 re-enters as a fresh instance and resolves its entry ability"
	)
	_check(
		_find_instance_anywhere(flip_next, &"kuihua_three_old") == &""
		and (flip_next.removed_cards[Rules.PLAYER_OWNER] as Array).is_empty(),
		"KuiHua3's old instance disappears without being exiled"
	)

	var return_board: Array = Rules.empty_board()
	return_board[1] = _slot(
		_plain(&"return_strong_enemy", [9, 9, 9, 9], Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	return_board[3] = _slot(
		Catalog.create_instance(&"KuiHua2", Rules.OPPONENT_OWNER, &"returning_kuihua_two"),
		Rules.OPPONENT_OWNER
	)
	var return_state := State.new(
		return_board,
		[Catalog.create_instance(&"KuiHua3", Rules.PLAYER_OWNER, &"kuihua_three_no_flip")],
		[_plain(&"no_flip_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER
	)
	_enable_player_kuihua(return_state)
	var return_transition: Dictionary = Simulator.apply_action(
		return_state,
		Action.make_play(0, 4, &"kuihua_three_no_flip")
	)
	_check(
		_count_events(return_transition.get("events", []), &"attack_started") == 1
		and _count_events(return_transition.get("events", []), &"card_departed_for_resummon") == 0
		and _board_instance_id(return_transition.get("state") as State, 4) == &"kuihua_three_no_flip",
		"KuiHua3 does not re-enter when an attack starts but flips no enemy"
	)


func _test_kuihua_four_exiles_targets_and_recursively_enters_copies() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(
		_plain(&"captured_enemy_zero", [1, 1, 1, 1], Rules.OPPONENT_OWNER),
		Rules.PLAYER_OWNER
	)
	board[8] = _slot(
		_plain(&"captured_enemy_eight", [1, 1, 1, 1], Rules.OPPONENT_OWNER),
		Rules.PLAYER_OWNER
	)
	var state := State.new(
		board,
		[Catalog.create_instance(&"KuiHua4", Rules.PLAYER_OWNER, &"kuihua_four_source")],
		[_plain(&"kuihua_four_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER,
		0,
		[
			_plain(&"kuihua_four_draw_one", [1, 1, 1, 1], Rules.PLAYER_OWNER),
			_plain(&"kuihua_four_draw_two", [1, 1, 1, 1], Rules.PLAYER_OWNER),
			_plain(&"kuihua_four_draw_three", [1, 1, 1, 1], Rules.PLAYER_OWNER),
		]
	)
	_enable_player_kuihua(state)
	var transition: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, 4, &"kuihua_four_source")
	)
	var next_state: State = transition.get("state") as State
	_check(
		_count_events(transition.get("events", []), &"card_exiled") == 2
		and _find_hand_card(
			next_state.removed_cards[Rules.OPPONENT_OWNER],
			&"captured_enemy_zero"
		) >= 0
		and _find_hand_card(
			next_state.removed_cards[Rules.OPPONENT_OWNER],
			&"captured_enemy_eight"
		) >= 0,
		"KuiHua4 truly exiles each target to its original owner's removed zone"
	)
	_check(
		_find_board_card_id_count(next_state, &"KuiHua4") == 3
		and _board_card_id(next_state, 0) == &"KuiHua4"
		and _board_card_id(next_state, 8) == &"KuiHua4",
		"KuiHua4 creates fresh copies in every exiled target's cell"
	)
	_check(
		_count_events(transition.get("events", []), &"card_summoned") == 2
		and _count_events(transition.get("events", []), &"card_drawn") == 3,
		"Each KuiHua4 copy fully enters and triggers its own draw ability"
	)


func _test_kuihua_four_is_inert_without_player_gate() -> void:
	var board: Array = Rules.empty_board()
	board[0] = _slot(
		_plain(&"disabled_captured_enemy", [1, 1, 1, 1], Rules.OPPONENT_OWNER),
		Rules.PLAYER_OWNER
	)
	var state := State.new(
		board,
		[Catalog.create_instance(&"KuiHua4", Rules.PLAYER_OWNER, &"disabled_kuihua_four")],
		[_plain(&"disabled_four_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER,
		0,
		[_plain(&"disabled_four_draw", [1, 1, 1, 1], Rules.PLAYER_OWNER)]
	)
	var transition: Dictionary = Simulator.apply_action(
		state,
		Action.make_play(0, 4, &"disabled_kuihua_four")
	)
	var next_state: State = transition.get("state") as State
	_check(
		_count_events(transition.get("events", []), &"card_drawn") == 0
		and _count_events(transition.get("events", []), &"card_exiled") == 0
		and _board_instance_id(next_state, 0) == &"disabled_captured_enemy",
		"A player without KuiHua0 gets no KuiHua4 effects"
	)
func _plain(instance_id: StringName, powers: Array[int], owner_id: int) -> Dictionary:
	var card: Dictionary = Rules.make_card(
		String(instance_id),
		String(instance_id),
		powers,
		[],
		owner_id,
		instance_id
	)
	card["instance_id"] = instance_id
	return card


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _enable_player_kuihua(state: State) -> void:
	state.enabled_effect_gates_by_owner[Rules.PLAYER_OWNER] = [
		Catalog.EFFECT_GATE_SELF_CASTRATION,
	]


func _kuihua_two_defense_state(attacker_powers: Array[int], attacker_id: StringName) -> State:
	var board: Array = Rules.empty_board()
	board[1] = _slot(
		Catalog.create_instance(
			&"KuiHua2",
			Rules.OPPONENT_OWNER,
			&"kuihua_two_defender"
		),
		Rules.OPPONENT_OWNER
	)
	return State.new(
		board,
		[_plain(attacker_id, attacker_powers, Rules.PLAYER_OWNER)],
		[_plain(&"defense_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
		Rules.PLAYER_OWNER
	)


func _find_hand_card(hand: Array, instance_id: StringName) -> int:
	for index: int in range(hand.size()):
		var card_value: Variant = hand[index]
		if (
			card_value is Dictionary
			and StringName((card_value as Dictionary).get("instance_id", &"")) == instance_id
		):
			return index
	return -1


func _find_hand_card_by_card_id(hand: Array, card_id: StringName) -> int:
	for index: int in range(hand.size()):
		var card_value: Variant = hand[index]
		if (
			card_value is Dictionary
			and StringName((card_value as Dictionary).get("card_id", &"")) == card_id
		):
			return index
	return -1


func _card_has_modifier(card: Dictionary, modifier_type: StringName) -> bool:
	for ability_value: Variant in card.get("active_abilities", []):
		if not ability_value is Dictionary:
			continue
		for modifier_value: Variant in (ability_value as Dictionary).get("modifiers", []):
			if (
				modifier_value is Dictionary
				and StringName((modifier_value as Dictionary).get("type", &"")) == modifier_type
			):
				return true
	return false


func _board_instance_id(state: State, cell: int) -> StringName:
	if cell < 0 or cell >= state.board.size() or state.board[cell] == null:
		return &""
	return StringName(
		((state.board[cell] as Dictionary).get("card", {}) as Dictionary).get("instance_id", &"")
	)


func _find_board_card_id(state: State, card_id: StringName) -> int:
	for cell: int in range(state.board.size()):
		if state.board[cell] == null:
			continue
		var card: Dictionary = (state.board[cell] as Dictionary).get("card", {})
		if StringName(card.get("card_id", &"")) == card_id:
			return cell
	return -1


func _find_board_card_id_count(state: State, card_id: StringName) -> int:
	var count: int = 0
	for cell: int in range(state.board.size()):
		if _board_card_id(state, cell) == card_id:
			count += 1
	return count


func _board_card_id(state: State, cell: int) -> StringName:
	if cell < 0 or cell >= state.board.size() or state.board[cell] == null:
		return &""
	return StringName(
		((state.board[cell] as Dictionary).get("card", {}) as Dictionary).get("card_id", &"")
	)


func _find_instance_anywhere(state: State, instance_id: StringName) -> StringName:
	for cell: int in range(state.board.size()):
		if _board_instance_id(state, cell) == instance_id:
			return &"board"
	for owner_id: int in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		for zone: Dictionary in [state.hands, state.decks, state.discard_piles, state.removed_cards]:
			if _find_hand_card(zone.get(owner_id, []), instance_id) >= 0:
				return &"zone"
	return &""


func _count_events(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for event_value: Variant in events:
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
		):
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)


func _finish() -> void:
	if _failures == 0:
		print("KUIHUA_ABILITY_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"KUIHUA_ABILITY_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _cleanup_profile(profile_path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = profile_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
