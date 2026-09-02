extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const Abilities = preload("res://scripts/duel_abilities.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")
const State = preload("res://scripts/duel_state.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_vocabulary_and_catalog_declarations()
	_test_raozhi_range_comparison_and_first_target()
	_test_raozhi_commits_without_fallback_and_targeted_attacks_stay_explicit()
	_test_attack_recheck_uses_range_but_not_powers()
	_test_committed_attack_does_not_compare_powers_twice()
	_test_flip_guard_exiles_then_is_lost_after_own_flip()
	_test_flipped_card_attacks_as_the_same_instance()
	_test_shenmen_blocks_enemy_attacks_on_owner_turn()
	_test_raozhi_reacts_after_friendly_targeted_activation()
	_finish()


func _test_vocabulary_and_catalog_declarations() -> void:
	_check(Catalog.CARD_AFTER_TARGETED_ACTIVATION in Catalog.KNOWN_TRIGGER_EVENTS, "Targeted activation completion is a trigger event")
	_check(Catalog.CONDITION_ACTIVATION_OWNER_IS_ALLY in Catalog.KNOWN_TRIGGER_CONDITIONS, "Friendly activation owner is a trigger condition")
	_check(Catalog.ACTION_STANDARD_ATTACK_WITH_CARD in Catalog.KNOWN_ACTIONS, "Referenced-card standard attack is an action")
	for modifier_id: StringName in [
		Catalog.MODIFIER_UNLIMITED_ATTACK_RANGE,
		Catalog.MODIFIER_NON_ORTHOGONAL_ATTACK_ANY_AXIS,
		Catalog.MODIFIER_STANDARD_ATTACK_FIRST_LEGAL_TARGET,
		Catalog.MODIFIER_ENEMY_CANNOT_ATTACK_DURING_OWNER_TURN,
	]:
		_check(modifier_id in Catalog.KNOWN_MODIFIERS, "%s is a known modifier" % modifier_id)
	_check(Catalog.validate_catalog().is_empty(), "All nine Wudang declarations validate")
	var expected_ability_counts: Dictionary = {
		&"RaoZhiRouJian2": 1,
		&"RaoZhiRouJian3": 2,
		&"RaoZhiRouJian4": 3,
		&"ShenMen13Jian1": 0,
		&"ShenMen13Jian2": 1,
		&"ShenMen13Jian3": 2,
		&"WuDangMianZhang1": 0,
		&"WuDangMianZhang2": 1,
		&"WuDangMianZhang3": 2,
	}
	for card_id: StringName in expected_ability_counts:
		_check(
			(Catalog.get_definition(card_id).get("abilities", []) as Array).size()
			== int(expected_ability_counts[card_id]),
			"%s declares every ability as a separate entry" % card_id
		)


func _test_raozhi_range_comparison_and_first_target() -> void:
	var board: Array = Rules.empty_board()
	board[4] = _slot(Catalog.create_instance(&"RaoZhiRouJian2", Rules.PLAYER_OWNER, &"raozhi_rules"), Rules.PLAYER_OWNER)
	board[0] = _slot(_plain(&"first_enemy", [9, 1, 9, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[1] = _slot(_plain(&"second_enemy", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	_check(Rules.can_attack_target(board, 4, 0), "RaoZhi attacks a non-collinear card when either facing axis wins")
	_check(Rules.can_attack_target(board, 4, 1), "RaoZhi attacks an ordinary distant card through intervening cards")
	_check(Rules.get_would_flip_indices(board, 4) == [0], "RaoZhi commits to the first legal enemy in board order")
	(board[0] as Dictionary)["card"] = _plain(&"too_strong", [9, 9, 9, 9], Rules.OPPONENT_OWNER)
	_check(not Rules.can_attack_target(board, 4, 0), "A non-collinear target resists when both facing axes fail")
	_check(Rules.get_would_flip_indices(board, 4) == [1], "RaoZhi skips initially illegal targets")
	(board[0] as Dictionary)["card"] = _plain(&"first_ally", [1, 1, 1, 1], Rules.PLAYER_OWNER)
	(board[0] as Dictionary)["owner"] = Rules.PLAYER_OWNER
	_check(
		Rules.get_would_flip_indices(board, 4, {"attack_target_policy": Catalog.ATTACK_TARGET_ALL}) == [0],
		"All-target policy changes first target to the first other card"
	)
	_check(
		Rules.get_would_flip_indices(board, 4, {"attack_target_policy": Catalog.ATTACK_TARGET_ALLIES_ONLY}) == [0],
		"Allies-only policy changes first target to the first ally"
	)
	_check(Rules.can_attack_target(board, 4, 1), "An explicitly chosen later target remains legal")


func _test_committed_attack_does_not_compare_powers_twice() -> void:
	var defender_ability: Dictionary = {
		"triggers": [{
			"event": Catalog.CARD_BE_ATTACKED,
			"conditions": [{"type": Catalog.CONDITION_ATTACKED_CARD_IS_SELF}],
			"actions": [{
				"type": Catalog.ACTION_CHANGE_POWERS,
				"amount": 9,
				"card": Catalog.CARD_REF_TRIGGER_CARD,
			}],
		}],
	}
	var board: Array = Rules.empty_board()
	board[1] = _slot(_plain(&"growing_defender", [1, 1, 1, 1], Rules.OPPONENT_OWNER, [defender_ability]), Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [_plain(&"committed_attacker", [5, 5, 5, 5], Rules.PLAYER_OWNER)], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"committed_attacker")
	)
	_check(
		int(((transition.get("state") as State).board[1] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER,
		"A target that raises defense during CARD_BE_ATTACKED is still flipped by the committed attack"
	)

	var first_target_ability: Dictionary = {
		"triggers": [{
			"event": Catalog.CARD_AFTER_FLIPPED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{
				"type": Catalog.ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [Catalog.CARD_ZONE_BOARD],
					"conditions": [{"type": Catalog.CONDITION_SELECTED_CARD_IS_ENEMY}],
					"limit": 1,
					"required_count": 1,
				},
				"actions": [{
					"type": Catalog.ACTION_CHANGE_POWERS,
					"amount": 9,
					"card": Catalog.CARD_REF_SELECTED_CARD,
				}],
			}],
		}],
	}
	var multi_board: Array = Rules.empty_board()
	multi_board[1] = _slot(
		_plain(&"first_committed_target", [1, 1, 1, 1], Rules.OPPONENT_OWNER, [first_target_ability]),
		Rules.OPPONENT_OWNER
	)
	multi_board[5] = _slot(
		_plain(&"later_strengthened_target", [1, 1, 1, 1], Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER
	)
	var multi_transition: Dictionary = Simulator.apply_action(
		State.new(
			multi_board,
			[_plain(&"multi_committed_attacker", [5, 5, 5, 5], Rules.PLAYER_OWNER)],
			[],
			Rules.PLAYER_OWNER
		),
		Action.make_play(0, 4, &"multi_committed_attacker")
	)
	var multi_state: State = multi_transition.get("state") as State
	_check(
		int((multi_state.board[5] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER,
		"A later locked target remains committed after an earlier target raises its powers"
	)


func _test_raozhi_commits_without_fallback_and_targeted_attacks_stay_explicit() -> void:
	var exile_on_attack: Dictionary = {
		"triggers": [{
			"event": Catalog.CARD_BE_ATTACKED,
			"conditions": [{"type": Catalog.CONDITION_ATTACKED_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_EXILE_CARD, "card": Catalog.CARD_REF_TRIGGER_CARD}],
		}],
	}
	var board: Array = Rules.empty_board()
	board[0] = _slot(_plain(&"committed_exile", [1, 1, 1, 1], Rules.OPPONENT_OWNER, [exile_on_attack]), Rules.OPPONENT_OWNER)
	board[1] = _slot(_plain(&"no_fallback_target", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [Catalog.create_instance(&"RaoZhiRouJian2", Rules.PLAYER_OWNER, &"committed_raozhi")], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"committed_raozhi")
	)
	var next_state: State = transition.get("state") as State
	_check(next_state.board[0] == null, "The committed first target may remove itself in CARD_BE_ATTACKED")
	_check(int((next_state.board[1] as Dictionary).get("owner", 0)) == Rules.OPPONENT_OWNER, "RaoZhi does not fall through to a second target")

	var targeted_board: Array = Rules.empty_board()
	targeted_board[4] = _slot(Catalog.create_instance(&"RaoZhiRouJian2", Rules.PLAYER_OWNER, &"targeted_raozhi"), Rules.PLAYER_OWNER)
	targeted_board[0] = _slot(_plain(&"earlier_target", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	targeted_board[1] = _slot(_plain(&"explicit_target", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var targeted_state := State.new(targeted_board, [], [], Rules.PLAYER_OWNER)
	Simulator._resolve_attack_request(targeted_state, {
		"mode": &"targeted",
		"source_cell": 4,
		"source_instance_id": &"targeted_raozhi",
		"source_owner_id": Rules.PLAYER_OWNER,
		"target_cell": 1,
		"target_instance_id": &"explicit_target",
		"target_owner_id": Rules.OPPONENT_OWNER,
	})
	_check(int((targeted_state.board[0] as Dictionary).get("owner", 0)) == Rules.OPPONENT_OWNER, "Targeted attacks do not redirect to RaoZhi's first target")
	_check(int((targeted_state.board[1] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER, "Targeted attacks keep their explicit legal target")


func _test_attack_recheck_uses_range_but_not_powers() -> void:
	var move_on_attack: Dictionary = {
		"triggers": [{
			"event": Catalog.CARD_BE_ATTACKED,
			"conditions": [{"type": Catalog.CONDITION_ATTACKED_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY}],
		}],
	}
	var ordinary_board: Array = Rules.empty_board()
	ordinary_board[1] = _slot(_plain(&"ordinary_mover", [1, 1, 1, 1], Rules.OPPONENT_OWNER, [move_on_attack]), Rules.OPPONENT_OWNER)
	var ordinary_transition: Dictionary = Simulator.apply_action(
		State.new(ordinary_board, [_plain(&"ordinary_source", [9, 9, 9, 9], Rules.PLAYER_OWNER)], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"ordinary_source")
	)
	var ordinary_state: State = ordinary_transition.get("state") as State
	var ordinary_mover_cell: int = _find_board_instance(ordinary_state.board, &"ordinary_mover")
	_check(
		ordinary_mover_cell >= 0
		and int((ordinary_state.board[ordinary_mover_cell] as Dictionary).get("owner", 0)) == Rules.OPPONENT_OWNER,
		"An ordinary target moving out of range cancels the committed flip"
	)

	var unlimited_board: Array = Rules.empty_board()
	unlimited_board[0] = _slot(_plain(&"unlimited_mover", [1, 1, 1, 1], Rules.OPPONENT_OWNER, [move_on_attack]), Rules.OPPONENT_OWNER)
	var unlimited_transition: Dictionary = Simulator.apply_action(
		State.new(unlimited_board, [Catalog.create_instance(&"RaoZhiRouJian2", Rules.PLAYER_OWNER, &"moving_raozhi")], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 8, &"moving_raozhi")
	)
	var unlimited_state: State = unlimited_transition.get("state") as State
	var unlimited_mover_cell: int = _find_board_instance(unlimited_state.board, &"unlimited_mover")
	_check(
		unlimited_mover_cell >= 0
		and int((unlimited_state.board[unlimited_mover_cell] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER,
		"Movement alone does not cancel RaoZhi's unlimited committed attack"
	)


func _test_flip_guard_exiles_then_is_lost_after_own_flip() -> void:
	var guarded_board: Array = Rules.empty_board()
	guarded_board[1] = _slot(Catalog.create_instance(&"WuDangMianZhang2", Rules.OPPONENT_OWNER, &"guarded_mianzhang"), Rules.OPPONENT_OWNER)
	var guarded_transition: Dictionary = Simulator.apply_action(
		State.new(guarded_board, [_plain(&"guard_attacker", [9, 9, 9, 9], Rules.PLAYER_OWNER)], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"guard_attacker")
	)
	var guarded_state: State = guarded_transition.get("state") as State
	_check(guarded_state.board[1] == null, "MianZhang exiles itself before it would flip")
	_check((guarded_state.removed_cards[Rules.OPPONENT_OWNER] as Array).size() == 1, "Flip guard performs a real exile")

	var attacking_board: Array = Rules.empty_board()
	attacking_board[1] = _slot(_plain(&"guard_loss_target", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var attacking_transition: Dictionary = Simulator.apply_action(
		State.new(attacking_board, [Catalog.create_instance(&"WuDangMianZhang3", Rules.PLAYER_OWNER, &"mianzhang_guard_loss")], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"mianzhang_guard_loss")
	)
	var attacking_state: State = attacking_transition.get("state") as State
	var mianzhang_card: Dictionary = (attacking_state.board[4] as Dictionary).get("card", {})
	_check((mianzhang_card.get("active_abilities", []) as Array).size() == 1, "MianZhang permanently loses only its guard after flipping another card")
	Simulator.resolve_non_attack_flip(attacking_state, &"mianzhang_guard_loss", Rules.OPPONENT_OWNER)
	_check(int((attacking_state.board[4] as Dictionary).get("owner", 0)) == Rules.OPPONENT_OWNER, "A spent guard no longer prevents later flips")


func _test_flipped_card_attacks_as_the_same_instance() -> void:
	var board: Array = Rules.empty_board()
	board[1] = _slot(_plain(&"forced_attacker", [1, 9, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[2] = _slot(_plain(&"forced_target", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [Catalog.create_instance(&"ShenMen13Jian2", Rules.PLAYER_OWNER, &"shenmen_force")], [], Rules.PLAYER_OWNER),
		Action.make_play(0, 4, &"shenmen_force")
	)
	var next_state: State = transition.get("state") as State
	_check(int((next_state.board[1] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER, "ShenMen flips the first exact card")
	_check(int((next_state.board[2] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER, "That same flipped instance immediately attacks for its new owner")
	_check(_count_events(transition.get("events", []), &"attack_started") == 2, "The original and forced attacks each start once")


func _test_shenmen_blocks_enemy_attacks_on_owner_turn() -> void:
	var board: Array = Rules.empty_board()
	board[8] = _slot(Catalog.create_instance(&"ShenMen13Jian3", Rules.PLAYER_OWNER, &"shenmen_lock"), Rules.PLAYER_OWNER)
	board[4] = _slot(_plain(&"blocked_enemy", [9, 9, 9, 9], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	board[1] = _slot(_plain(&"blocked_target", [1, 1, 1, 1], Rules.PLAYER_OWNER), Rules.PLAYER_OWNER)
	var state := State.new(board, [], [], Rules.PLAYER_OWNER)
	var standard_result: Dictionary = Simulator._resolve_standard_attacks(state, 4, &"blocked_enemy", &"test_block")
	_check(_count_events(standard_result.get("events", []), &"attack_started") == 0, "ShenMen blocks enemy standard attacks during its owner's turn")
	var targeted_result: Dictionary = Simulator._resolve_attack_request(state, {
		"mode": &"targeted",
		"source_cell": 4,
		"source_instance_id": &"blocked_enemy",
		"source_owner_id": Rules.OPPONENT_OWNER,
		"target_cell": 1,
		"target_instance_id": &"blocked_target",
		"target_owner_id": Rules.PLAYER_OWNER,
	})
	_check(_count_events(targeted_result.get("events", []), &"attack_started") == 0, "ShenMen also blocks targeted enemy attacks")
	Simulator.resolve_non_attack_flip(state, &"shenmen_lock", Rules.OPPONENT_OWNER)
	_check(not Abilities.has_modifier((state.board[8] as Dictionary).get("card", {}), Catalog.MODIFIER_ENEMY_CANNOT_ATTACK_DURING_OWNER_TURN), "ShenMen loses the non-retained lock when flipped")
	var locked_raozhi: Dictionary = Catalog.create_instance(&"RaoZhiRouJian2", Rules.PLAYER_OWNER, &"locked_raozhi")
	state.board[7] = _slot(locked_raozhi, Rules.PLAYER_OWNER)
	Simulator.resolve_non_attack_flip(state, &"locked_raozhi", Rules.OPPONENT_OWNER)
	_check(Abilities.has_modifier((state.board[7] as Dictionary).get("card", {}), Catalog.MODIFIER_UNLIMITED_ATTACK_RANGE), "RaoZhi's locked attack modifiers survive ownership flips")


func _test_raozhi_reacts_after_friendly_targeted_activation() -> void:
	var board: Array = Rules.empty_board()
	board[8] = _slot(Catalog.create_instance(&"RaoZhiRouJian4", Rules.PLAYER_OWNER, &"raozhi_reaction"), Rules.PLAYER_OWNER)
	var hanbin: Dictionary = Catalog.create_instance(&"HanBinZhenQi3", Rules.PLAYER_OWNER, &"friendly_activation")
	hanbin["ki"] = 1
	board[4] = _slot(hanbin, Rules.PLAYER_OWNER)
	board[0] = _slot(_plain(&"reaction_target", [1, 1, 1, 1], Rules.OPPONENT_OWNER), Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [], [_plain(&"selected_hand_card", [5, 5, 5, 5], Rules.OPPONENT_OWNER)], Rules.PLAYER_OWNER),
		Action.make_activate(4, &"friendly_activation", Action.TARGET_HAND_SLOT, 0)
	)
	var next_state: State = transition.get("state") as State
	_check(int((next_state.board[0] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER, "RaoZhi attacks after the friendly targeted activation fully resolves")
	_check(_count_events(transition.get("events", []), &"attack_started") == 1, "One targeted activation produces one RaoZhi reaction attack")
	_check(_event_index(transition.get("events", []), &"powers_changed") < _event_index(transition.get("events", []), &"attack_started"), "The complete targeted ability resolves before RaoZhi attacks")


func _plain(instance_id: StringName, powers: Array[int], owner_id: int, abilities: Array = []) -> Dictionary:
	var card: Dictionary = Rules.make_card(String(instance_id), String(instance_id), powers, abilities, owner_id, instance_id)
	card["instance_id"] = instance_id
	return card


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _count_events(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for event_value: Variant in events:
		if event_value is Dictionary and StringName((event_value as Dictionary).get("type", &"")) == event_type:
			count += 1
	return count


func _find_board_instance(board: Array, instance_id: StringName) -> int:
	for cell_index: int in range(board.size()):
		var slot_value: Variant = board[cell_index]
		if slot_value is Dictionary:
			var card: Dictionary = (slot_value as Dictionary).get("card", {})
			if StringName(card.get("instance_id", &"")) == instance_id:
				return cell_index
	return -1


func _event_index(events: Array, event_type: StringName) -> int:
	for index: int in range(events.size()):
		var event_value: Variant = events[index]
		if event_value is Dictionary and StringName((event_value as Dictionary).get("type", &"")) == event_type:
			return index
	return 9999


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)


func _finish() -> void:
	if _failures == 0:
		print("WUDANG_NINE_CARDS_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("WUDANG_NINE_CARDS_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)
