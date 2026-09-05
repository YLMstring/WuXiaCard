extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Action = preload("res://scripts/duel_action.gd")
const Revelation = preload("res://scripts/duel_revelation.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const Targeting = preload("res://scripts/duel_targeting.gd")
const Triggers = preload("res://scripts/duel_triggers.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_vocabulary_and_declarations()
	_test_enemy_hand_targeting()
	_test_staged_self_after_flip_cleanup()
	_test_hanbin_target_activation()
	_test_hanbin_last_ki_flip_and_frozen_turn()
	_test_tianwai_swap_and_attack()
	_test_tianwai_tier_three_and_multiple_sources()
	_test_tianwai_preserves_moved_summons_self_trigger()
	_finish()


func _test_catalog_vocabulary_and_declarations() -> void:
	_check(
		Catalog.TARGET_ENEMY_HAND_CARD in Catalog.KNOWN_TARGET_RULES,
		"Enemy-hand activation targets are registered"
	)
	_check(
		Catalog.CARD_KI_CHANGED in Catalog.KNOWN_TRIGGER_EVENTS,
		"Ki-change trigger events are registered"
	)
	_check(
		Catalog.CONDITION_KI_CHANGED_CARD_IS_SELF in Catalog.KNOWN_TRIGGER_CONDITIONS
		and Catalog.CONDITION_KI_REACHED_ZERO in Catalog.KNOWN_TRIGGER_CONDITIONS,
		"Ki-change trigger conditions are registered"
	)
	_check(
		Catalog.ACTION_REVEAL_CARD in Catalog.KNOWN_ACTIONS
		and Catalog.ACTION_SWAP_SELF_WITH_TRIGGER_CARD in Catalog.KNOWN_ACTIONS,
		"HanBin and TianWai generic actions are registered"
	)
	_check(
		Catalog.OWNER_OPPONENT_OF_ABILITY_SOURCE in Catalog.KNOWN_OWNER_REFERENCES,
		"Opponent-relative owner references are registered"
	)
	for card_id: StringName in [
		&"HanBinZhenQi3",
		&"HanBinZhenQi4",
		&"TianWaiYuLong2",
		&"TianWaiYuLong3",
	]:
		_check(
			not (Catalog.get_definition(card_id).get("abilities", []) as Array).is_empty(),
			"%s declares its complete ability" % card_id
		)


func _test_enemy_hand_targeting() -> void:
	var source: Dictionary = _plain(&"hand_target_source", [2, 2, 2, 2], Rules.PLAYER_OWNER)
	var board: Array = Rules.empty_board()
	board[4] = _slot(source, Rules.PLAYER_OWNER)
	var state := State.new(
		board,
		[_plain(&"player_hand", [1, 1, 1, 1], Rules.PLAYER_OWNER)],
		[
			_plain(&"enemy_left", [1, 1, 1, 1], Rules.OPPONENT_OWNER),
			_plain(&"enemy_right", [-1, -1, -1, -1], Rules.OPPONENT_OWNER),
		]
	)
	var activation: Dictionary = {
		"target_rule": Catalog.TARGET_ENEMY_HAND_CARD,
	}
	var targets: Array[Dictionary] = Targeting.get_valid_targets(
		state,
		Rules.PLAYER_OWNER,
		4,
		activation
	)
	_check(
		targets == [
			{"kind": Action.TARGET_HAND_SLOT, "index": 0},
			{"kind": Action.TARGET_HAND_SLOT, "index": 1},
		],
		"Enemy-hand targeting enumerates every logical opponent card, including YinYang"
	)
	_check(
		not Targeting.is_target_valid(
			state,
			Rules.PLAYER_OWNER,
			4,
			activation,
			Action.TARGET_BOARD_CELL,
			0
		)
		and not Targeting.is_target_valid(
			state,
			Rules.PLAYER_OWNER,
			4,
			activation,
			Action.TARGET_HAND_SLOT,
			2
		),
		"Enemy-hand targeting rejects board cells and empty logical slots"
	)


func _test_staged_self_after_flip_cleanup() -> void:
	var granted_ability: Dictionary = {
		"modifiers": [{
			"type": Catalog.MODIFIER_DEFENDING_POWER_OVERRIDE,
			"value": 5,
		}],
	}
	var ordinary_ability: Dictionary = {
		"triggers": [{
			"event": Catalog.TRIGGER_END_OWNER_TURN,
			"conditions": [{"type": Catalog.CONDITION_TURN_OWNER_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_GAIN_KI, "amount": 1}],
		}],
	}
	var self_after_flip: Dictionary = {
		"triggers": [{
			"event": Catalog.CARD_AFTER_FLIPPED,
			"conditions": [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{
				"type": Catalog.ACTION_GRANT_ABILITY_TO_SELF,
				"ability": granted_ability,
			}],
		}],
	}
	var target: Dictionary = _plain(&"staged_flip_target", [1, 1, 1, 1], Rules.OPPONENT_OWNER)
	target["active_abilities"] = [ordinary_ability, self_after_flip]
	var attacker: Dictionary = _plain(&"staged_flip_attacker", [1, 9, 1, 1], Rules.PLAYER_OWNER)
	var board: Array = Rules.empty_board()
	board[4] = _slot(target, Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[attacker],
			[_plain(&"staged_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
			Rules.PLAYER_OWNER
		),
		Action.make_play(0, 3, &"staged_flip_attacker")
	)
	var next_state: State = transition.get("state") as State
	var runtime: Dictionary = (next_state.board[4] as Dictionary).get("card", {})
	_check(
		(runtime.get("active_abilities", []) as Array).size() == 1
		and (runtime.get("active_abilities", []) as Array)[0]
		== Catalog.normalize_ability(granted_ability),
		"A self-after-flip rule resolves once, loses itself, and preserves its new grant"
	)
	var relevant: Array[StringName] = []
	for event_type: StringName in _event_types(transition.get("events", [])):
		if event_type in [
			&"card_flipped",
			&"ability_lost",
			&"ability_triggered",
			&"ability_gained",
		]:
			relevant.append(event_type)
	_check(
		relevant.slice(0, 5) == [
			&"card_flipped",
			&"ability_lost",
			&"ability_triggered",
			&"ability_gained",
			&"ability_lost",
		],
		"Flip cleanup loses ordinary abilities before self-after-flip and its old rule after"
	)


func _test_hanbin_target_activation() -> void:
	var source: Dictionary = Catalog.create_instance(
		&"HanBinZhenQi3",
		Rules.PLAYER_OWNER,
		&"hanbin_three"
	)
	var target: Dictionary = _plain(&"hanbin_target", [3, 3, 3, 3], Rules.OPPONENT_OWNER)
	var board: Array = Rules.empty_board()
	board[4] = _slot(source, Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [], [target], Rules.PLAYER_OWNER),
		Action.make_activate(4, &"hanbin_three", Action.TARGET_HAND_SLOT, 0)
	)
	var next_state: State = transition.get("state") as State
	var runtime_target: Dictionary = next_state.get_hand(Rules.OPPONENT_OWNER)[0]
	_check(
		bool(transition.get("valid", false))
		and runtime_target.get("powers", []) == [2, 2, 2, 2]
		and Revelation.is_revealed_to(runtime_target, Rules.PLAYER_OWNER),
		"HanBin spends ki to weaken and reveal the exact enemy hand target"
	)

	var sentinel_source: Dictionary = Catalog.create_instance(
		&"HanBinZhenQi3",
		Rules.PLAYER_OWNER,
		&"hanbin_sentinel_source"
	)
	var sentinel: Dictionary = _plain(
		&"hanbin_sentinel",
		[-1, -1, -1, -1],
		Rules.OPPONENT_OWNER
	)
	var sentinel_board: Array = Rules.empty_board()
	sentinel_board[4] = _slot(sentinel_source, Rules.PLAYER_OWNER)
	var sentinel_transition: Dictionary = Simulator.apply_action(
		State.new(sentinel_board, [], [sentinel], Rules.PLAYER_OWNER),
		Action.make_activate(4, &"hanbin_sentinel_source", Action.TARGET_HAND_SLOT, 0)
	)
	var sentinel_state: State = sentinel_transition.get("state") as State
	var runtime_sentinel: Dictionary = sentinel_state.get_hand(Rules.OPPONENT_OWNER)[0]
	_check(
		bool(sentinel_transition.get("valid", false))
		and runtime_sentinel.get("powers", []) == [-1, -1, -1, -1]
		and Revelation.is_revealed_to(runtime_sentinel, Rules.PLAYER_OWNER)
		and _count_events(sentinel_transition.get("events", []), &"powers_changed") == 0,
		"Actively selected YinYang is revealed while its power change has no effect"
	)


func _test_tianwai_swap_and_attack() -> void:
	var source: Dictionary = Catalog.create_instance(
		&"TianWaiYuLong2",
		Rules.PLAYER_OWNER,
		&"tianwai_two"
	)
	var ally: Dictionary = _plain(&"tianwai_ally", [2, 2, 2, 2], Rules.PLAYER_OWNER)
	var enemy: Dictionary = _plain(&"tianwai_enemy", [1, 1, 1, 1], Rules.OPPONENT_OWNER)
	var board: Array = Rules.empty_board()
	board[4] = _slot(source, Rules.PLAYER_OWNER)
	board[2] = _slot(enemy, Rules.OPPONENT_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[ally],
			[_plain(&"tianwai_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
			Rules.PLAYER_OWNER
		),
		Action.make_play(0, 5, &"tianwai_ally")
	)
	var next_state: State = transition.get("state") as State
	_check(
		_instance_at(next_state, 4) == &"tianwai_ally"
		and _instance_at(next_state, 5) == &"tianwai_two"
		and int((next_state.board[2] as Dictionary).get("owner", 0)) == Rules.PLAYER_OWNER,
		"TianWai swaps with the adjacent allied summon and attacks from its new cell"
	)
	var attack_event: Dictionary = _first_event(transition.get("events", []), &"attack_started")
	_check(
		StringName(attack_event.get("source_instance_id", &"")) == &"tianwai_two"
		and int(attack_event.get("source_cell", -1)) == 5,
		"TianWai is the follow-up attacker after the swap"
	)


func _test_hanbin_last_ki_flip_and_frozen_turn() -> void:
	var source: Dictionary = Catalog.create_instance(
		&"HanBinZhenQi4",
		Rules.PLAYER_OWNER,
		&"hanbin_four"
	)
	var target: Dictionary = _plain(&"hanbin_four_target", [3, 3, 3, 3], Rules.OPPONENT_OWNER)
	var board: Array = Rules.empty_board()
	board[4] = _slot(source, Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(board, [], [target], Rules.PLAYER_OWNER),
		Action.make_activate(4, &"hanbin_four", Action.TARGET_HAND_SLOT, 0)
	)
	var next_state: State = transition.get("state") as State
	var runtime_source: Dictionary = (next_state.board[4] as Dictionary).get("card", {})
	var runtime_target: Dictionary = next_state.get_hand(Rules.OPPONENT_OWNER)[0]
	var types: Array[StringName] = _event_types(transition.get("events", []))
	var first_power_event: Dictionary = _first_event(
		transition.get("events", []),
		&"powers_changed"
	)
	_check(
		int((next_state.board[4] as Dictionary).get("owner", 0)) == Rules.OPPONENT_OWNER
		and runtime_target.get("powers", []) == [1, 1, 1, 1]
		and StringName(first_power_event.get("instance_id", &"")) == &"hanbin_four_target"
		and first_power_event.get("powers", []) == [2, 2, 2, 2]
		and Revelation.is_revealed_to(runtime_target, Rules.PLAYER_OWNER)
		and types.find(&"card_flipped") >= 0
		and types.find(&"card_flipped") < types.find(&"powers_changed")
		and types.find(&"card_flipped") < types.find(&"card_revealed"),
		"HanBin4 flips immediately on its last ki, then resolves its locked hand target: owner=%d target=%s revealed=%s events=%s"
		% [
			int((next_state.board[4] as Dictionary).get("owner", 0)),
			str(runtime_target.get("powers", [])),
			str(Revelation.is_revealed_to(runtime_target, Rules.PLAYER_OWNER)),
			str(types),
		]
	)
	_check(
		(runtime_source.get("active_abilities", []) as Array).size() == 1
		and (runtime_source.get("active_abilities", []) as Array)[0]
		== Catalog.normalize_ability(Catalog.HANBIN_FROZEN_TURN),
		"HanBin4 keeps only the newly granted frozen-turn ability after that flip"
	)

	var frozen: Dictionary = Catalog.create_instance(
		&"HanBinZhenQi3",
		Rules.PLAYER_OWNER,
		&"frozen_source"
	)
	frozen["active_abilities"] = [Catalog.normalize_ability(Catalog.HANBIN_FROZEN_TURN)]
	var frozen_board: Array = Rules.empty_board()
	frozen_board[4] = _slot(frozen, Rules.PLAYER_OWNER)
	var sentinel: Dictionary = _plain(&"frozen_sentinel", [-1, -1, -1, -1], Rules.PLAYER_OWNER)
	var left: Dictionary = _plain(&"frozen_left", [3, 3, 3, 3], Rules.PLAYER_OWNER)
	var middle: Dictionary = _plain(&"frozen_middle", [4, 4, 4, 4], Rules.PLAYER_OWNER)
	var right: Dictionary = _plain(&"frozen_right", [5, 5, 5, 5], Rules.PLAYER_OWNER)
	var frozen_state := State.new(
		frozen_board,
		[sentinel, left, middle, right],
		[],
		Rules.PLAYER_OWNER
	)
	var groups: Array[Dictionary] = Triggers.discover(
		frozen_state,
		Catalog.TRIGGER_START_OWNER_TURN,
		{"turn_owner_id": Rules.PLAYER_OWNER}
	)
	var frozen_result: Dictionary = Triggers.resolve_group(frozen_state, groups[0])
	var runtime_frozen: Dictionary = (frozen_state.board[4] as Dictionary).get("card", {})
	var runtime_hand: Array = frozen_state.get_hand(Rules.PLAYER_OWNER)
	var power_events: Array[Dictionary] = []
	for event_value: Variant in frozen_result.get("events", []):
		if event_value is Dictionary and StringName((event_value as Dictionary).get("type", &"")) == &"powers_changed":
			power_events.append(event_value)
	_check(
		runtime_frozen.get("powers", []) == [1, 0, 0, 1]
		and (runtime_hand[0] as Dictionary).get("powers", []) == [-1, -1, -1, -1]
		and (runtime_hand[1] as Dictionary).get("powers", []) == [2, 2, 2, 2]
		and (runtime_hand[2] as Dictionary).get("powers", []) == [3, 3, 3, 3]
		and (runtime_hand[3] as Dictionary).get("powers", []) == [5, 5, 5, 5],
		"Frozen turn skips YinYang and weakens the next two legal leftmost hand cards: self=%s hand=%s"
		% [str(runtime_frozen.get("powers", [])), str([
			(runtime_hand[0] as Dictionary).get("powers", []),
			(runtime_hand[1] as Dictionary).get("powers", []),
			(runtime_hand[2] as Dictionary).get("powers", []),
			(runtime_hand[3] as Dictionary).get("powers", []),
		])]
	)
	var shared_batch: bool = power_events.size() == 3
	var batch_id := StringName(power_events[0].get("power_change_batch_id", &"")) if not power_events.is_empty() else &""
	for power_event: Dictionary in power_events:
		shared_batch = shared_batch and StringName(
			power_event.get("power_change_batch_id", &"")
		) == batch_id
	_check(
		shared_batch and batch_id != &"",
		"Frozen turn emits self and both hand changes in one simultaneous presentation batch"
	)
	Simulator.resolve_non_attack_flip(
		frozen_state,
		&"frozen_source",
		Rules.OPPONENT_OWNER,
		&"test_flip"
	)
	Simulator.resolve_non_attack_flip(
		frozen_state,
		&"frozen_source",
		Rules.PLAYER_OWNER,
		&"test_flip_back"
	)
	_check(
		(runtime_frozen.get("active_abilities", []) as Array).is_empty(),
		"The frozen-turn ability is permanently lost on a later flip and is not regained: %s"
		% str(runtime_frozen.get("active_abilities", []))
	)


func _test_tianwai_tier_three_and_multiple_sources() -> void:
	var source: Dictionary = Catalog.create_instance(
		&"TianWaiYuLong3",
		Rules.PLAYER_OWNER,
		&"tianwai_three"
	)
	var ally: Dictionary = _plain(&"tianwai_three_ally", [2, 2, 2, 2], Rules.PLAYER_OWNER)
	var board: Array = Rules.empty_board()
	board[4] = _slot(source, Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[ally],
			[_plain(&"tianwai_three_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
			Rules.PLAYER_OWNER
		),
		Action.make_play(0, 5, &"tianwai_three_ally")
	)
	var next_state: State = transition.get("state") as State
	var moved_ally: Dictionary = (next_state.board[4] as Dictionary).get("card", {})
	_check(
		_instance_at(next_state, 5) == &"tianwai_three"
		and moved_ally.get("powers", []) == [3, 3, 3, 3],
		"TianWai3 strengthens the exact summoned ally before swapping and attacking"
	)

	var sentinel_source: Dictionary = Catalog.create_instance(
		&"TianWaiYuLong3",
		Rules.PLAYER_OWNER,
		&"tianwai_three_sentinel_source"
	)
	var sentinel: Dictionary = _plain(
		&"tianwai_three_sentinel",
		[-1, -1, -1, -1],
		Rules.PLAYER_OWNER
	)
	var sentinel_board: Array = Rules.empty_board()
	sentinel_board[4] = _slot(sentinel_source, Rules.PLAYER_OWNER)
	var sentinel_transition: Dictionary = Simulator.apply_action(
		State.new(
			sentinel_board,
			[sentinel],
			[_plain(&"tianwai_sentinel_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
			Rules.PLAYER_OWNER
		),
		Action.make_play(0, 5, &"tianwai_three_sentinel")
	)
	var sentinel_state: State = sentinel_transition.get("state") as State
	_check(
		_instance_at(sentinel_state, 4) == &"tianwai_three_sentinel"
		and _instance_at(sentinel_state, 5) == &"tianwai_three_sentinel_source"
		and ((sentinel_state.board[4] as Dictionary).get("card", {}) as Dictionary).get("powers", []) == [-1, -1, -1, -1],
		"TianWai3 still swaps and attacks when YinYang makes its optional +1 ineffective"
	)

	var first: Dictionary = Catalog.create_instance(&"TianWaiYuLong2", Rules.PLAYER_OWNER, &"tianwai_first")
	var second: Dictionary = Catalog.create_instance(&"TianWaiYuLong2", Rules.PLAYER_OWNER, &"tianwai_second")
	var shared_ally: Dictionary = _plain(&"tianwai_shared_ally", [2, 2, 2, 2], Rules.PLAYER_OWNER)
	var multiple_board: Array = Rules.empty_board()
	multiple_board[2] = _slot(first, Rules.PLAYER_OWNER)
	multiple_board[4] = _slot(second, Rules.PLAYER_OWNER)
	var multiple_transition: Dictionary = Simulator.apply_action(
		State.new(
			multiple_board,
			[shared_ally],
			[_plain(&"tianwai_multiple_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
			Rules.PLAYER_OWNER
		),
		Action.make_play(0, 1, &"tianwai_shared_ally")
	)
	_check(
		_instance_at(multiple_transition.get("state") as State, 1) == &"tianwai_first"
		and _count_source_events(
			multiple_transition.get("events", []),
			&"attack_started",
			&"tianwai_second"
		) == 0,
		"Multiple TianWai sources resolve row-major and later sources revalidate after swaps"
	)


func _test_tianwai_preserves_moved_summons_self_trigger() -> void:
	var tianwai: Dictionary = Catalog.create_instance(
		&"TianWaiYuLong2",
		Rules.PLAYER_OWNER,
		&"tianwai_before_yinyang"
	)
	var yinyang: Dictionary = Catalog.create_instance(
		&"YinYangZhang3",
		Rules.PLAYER_OWNER,
		&"moved_yinyang"
	)
	var board: Array = Rules.empty_board()
	board[4] = _slot(tianwai, Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action(
		State.new(
			board,
			[yinyang],
			[_plain(&"moved_yinyang_reply", [1, 1, 1, 1], Rules.OPPONENT_OWNER)],
			Rules.PLAYER_OWNER,
			0,
			[
				_plain(&"moved_yinyang_draw_one", [2, 2, 2, 2], Rules.PLAYER_OWNER, "掌法"),
				_plain(&"moved_yinyang_draw_two", [3, 3, 3, 3], Rules.PLAYER_OWNER, "掌法"),
			],
			[]
		),
		Action.make_play(0, 5, &"moved_yinyang")
	)
	var next_state: State = transition.get("state") as State
	_check(
		bool(transition.get("valid", false))
		and _instance_at(next_state, 5) == &"tianwai_before_yinyang"
		and next_state.board[4] == null
		and _removed_has(next_state, Rules.PLAYER_OWNER, &"moved_yinyang"),
		"A summoned card's discovered self trigger follows the same instance after TianWai swaps it"
	)
	_check(
		next_state.get_hand(Rules.PLAYER_OWNER).size() == 2
		and _count_source_events(
			transition.get("events", []),
			&"ability_triggered",
			&"moved_yinyang"
		) == 1,
		"Moved YinYang still resolves its draw-and-grant summon ability"
	)


func _plain(
	instance_id: StringName,
	powers: Array,
	owner_id: int,
	weapon: String = "剑法"
) -> Dictionary:
	return {
		"card_id": instance_id,
		"instance_id": instance_id,
		"glyph": String(instance_id),
		"weapon": weapon,
		"powers": powers.duplicate(),
		"ki": 0,
		"original_owner": owner_id,
		"active_abilities": [],
	}


func _slot(card: Dictionary, owner_id: int) -> Dictionary:
	return {"card": card, "owner": owner_id}


func _event_types(events: Array) -> Array[StringName]:
	var types: Array[StringName] = []
	for event_value: Variant in events:
		if event_value is Dictionary:
			types.append(StringName((event_value as Dictionary).get("type", &"")))
	return types


func _count_events(events: Array, event_type: StringName) -> int:
	var count: int = 0
	for actual_type: StringName in _event_types(events):
		if actual_type == event_type:
			count += 1
	return count


func _count_source_events(
	events: Array,
	event_type: StringName,
	source_instance_id: StringName
) -> int:
	var count: int = 0
	for event_value: Variant in events:
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
			and StringName((event_value as Dictionary).get("source_instance_id", &""))
			== source_instance_id
		):
			count += 1
	return count


func _instance_at(state: State, cell: int) -> StringName:
	if state == null or cell < 0 or cell >= state.board.size() or state.board[cell] == null:
		return &""
	return StringName(
		(((state.board[cell] as Dictionary).get("card", {}) as Dictionary).get(
			"instance_id",
			&""
		))
	)


func _removed_has(state: State, owner_id: int, instance_id: StringName) -> bool:
	for card_value: Variant in state.removed_cards.get(owner_id, []):
		if (
			card_value is Dictionary
			and StringName((card_value as Dictionary).get("instance_id", &"")) == instance_id
		):
			return true
	return false


func _first_event(events: Array, event_type: StringName) -> Dictionary:
	for event_value: Variant in events:
		if (
			event_value is Dictionary
			and StringName((event_value as Dictionary).get("type", &"")) == event_type
		):
			return event_value as Dictionary
	return {}


func _finish() -> void:
	if _failures == 0:
		print("HANBIN_TIANWAI_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"HANBIN_TIANWAI_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
