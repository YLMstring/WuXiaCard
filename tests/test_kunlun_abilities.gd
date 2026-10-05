extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")
const Action = preload("res://scripts/duel_action.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")
const Compact = preload("res://scripts/duel_compact_state.gd")
const Search = preload("res://scripts/duel_search.gd")

var checks: int = 0
var failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_formations()
	_test_diagonal()
	_test_copy_attacks()
	_test_movement()
	_test_action_types()
	_test_draw_attempts()
	_test_aura_removal()
	_test_copy_special_powers()
	_test_copy_last_summoned()
	_test_native_declaration_validation()
	if failures == 0:
		print("KUNLUN_ABILITY_TESTS_PASSED checks=%d" % checks)
	else:
		push_error("KUNLUN_ABILITY_TESTS_FAILED failures=%d checks=%d" % [failures, checks])
	quit(failures)

func _card(id: StringName, owner: int, instance: StringName) -> Dictionary:
	return Catalog.create_instance(id, owner, instance)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _count(events: Array, type: StringName) -> int:
	var result: int = 0
	for event: Dictionary in events:
		if StringName(event.get("type", &"")) == type:
			result += 1
	return result

func _test_formations() -> void:
	for owner: int in [1, 2]:
		for tier: int in [2, 3, 4]:
			var board: Array = Rules.empty_board()
			board[4] = {"card": _card(&"WuShengWuSe1", owner, &"formation_ally"), "owner": owner}
			var played: Dictionary = _card(StringName("YinYangLiangYi%d" % tier), owner, &"yin_entry")
			var drawn: Dictionary = _card(&"TianGangBeiDou2", owner, &"draw_formation")
			var state = State.new(board, [played] if owner == 1 else [], [played] if owner == 2 else [], owner)
			state.decks[owner] = [_card(&"TaiZuChangQuan", owner, &"skip_draw"), drawn]
			for index: int in range(5):
				state.decks[owner].append(_card(&"TianGangBeiDou2",owner,StringName("additional_formation_%d" % index)))
			var result: Dictionary = Simulator.apply_action(state, Action.make_play(0, 8, &"yin_entry"))
			_check(bool(result.get("valid", false)), "Formation entry resolves owner=%d tier=%d" % [owner, tier])
			if not result.get("valid", false): continue
			var next: State = result.state
			_check(next.board[8] == null, "Yin removes itself before generation")
			var amount: int = 4 if tier == 4 else 2
			_check(_count(result.events, &"card_drawn") == amount, "Filtered draw skips non-formations and uses the exact tier count")
			_check(next.board[1] != null and next.board[1].card.card_id == &"BaGuaFangWei", "Ally generates at first adjacent empty cell")
			var hand: Array = next.hands[owner]
			var expected: Array = [5, 4, 5, 4] if tier >= 3 else [4, 3, 4, 3]
			_check(hand.size() == amount and hand[0].powers == expected, "In-play draw buff applies before source departs")
			var later: Dictionary = _card(&"TaiZuChangQuan",owner,&"later_draw_source")
			later.active_abilities = [{"triggers":[{"event":&"card_summoned","conditions":[{"type":&"trigger_card_is_self"}],"actions":[{"type":&"draw_cards","amount":1,"weapon":"阵法"}]}]}]
			next.hands[owner].append(later)
			next.active_player = owner
			var later_result: Dictionary = Simulator.apply_action(next,Action.make_play(amount,8,&"later_draw_source"))
			_check(later_result.get("valid",false), "Later draw resolves after Yin leaves the board")
			if later_result.get("valid",false):
				_check(later_result.state.hands[owner][-1].powers == [4,3,4,3], "Departed Yin does not buff later draws")

func _test_diagonal() -> void:
	for owner: int in [1, 2]:
		var enemy: int = 3 - owner
		for tier: int in [1, 2, 3, 4]:
			var board: Array = Rules.empty_board()
			var diagonal: Dictionary = _card(&"TaiZuChangQuan", enemy, &"diagonal_target")
			diagonal.powers = [9, 9, 1, 9]
			board[0] = {"card": diagonal, "owner": enemy}
			var straight: Dictionary = _card(&"TaiZuChangQuan", enemy, &"straight_target")
			straight.powers = [1, 1, 1, 1]
			board[1] = {"card": straight, "owner": enemy}
			var played: Dictionary = _card(StringName("YuDaFeiHua%d" % tier), owner, &"rain_entry")
			var state = State.new(board, [played] if owner == 1 else [], [played] if owner == 2 else [], owner)
			var result: Dictionary = Simulator.apply_action(state, Action.make_play(0, 4, &"rain_entry"))
			_check(bool(result.get("valid", false)), "Rain entry resolves")
			if not result.get("valid", false): continue
			_check(result.state.board[0].owner == owner, "Diagonal wins with one stronger opposed pair")
			_check(result.state.board[1].owner == enemy, "Rain forbids orthogonally adjacent attack")

func _test_copy_attacks() -> void:
	for tier: int in [1, 2, 3, 4]:
		var board: Array = Rules.empty_board()
		board[4] = {"card": _card(StringName("WuShengWuSe%d" % tier), 1, &"silent"), "owner": 1}
		var ally: Dictionary = _card(&"TaiZuChangQuan", 1, &"power_donor")
		ally.powers = [7, 8, 9, 6]
		board[3] = {"card": ally, "owner": 1}
		var enemy: Dictionary = _card(&"TaiZuChangQuan", 2, &"silent_enemy")
		enemy.powers = [1, 1, 1, 1]
		board[1] = {"card": enemy, "owner": 2}
		var second_enemy: Dictionary = _card(&"TaiZuChangQuan", 2, &"donor_enemy")
		second_enemy.powers = [1, 1, 1, 1]
		board[0] = {"card": second_enemy, "owner": 2}
		var state = State.new(board, [], [_card(&"TaiZuChangQuan", 2, &"future_enemy")], 1)
		var result: Dictionary = Simulator.apply_action(state, Action.make_activate(4, &"silent", &"board_cell", 3))
		_check(bool(result.get("valid", false)), "Silent activation resolves tier %d" % tier)
		if not result.get("valid", false): continue
		_check(result.state.board[4].card.powers == [7, 8, 9, 6], "Copy replaces -1 powers in direction order")
		_check(result.state.board[3].card.powers == [7, 8, 9, 6], "Copy leaves donor unchanged")
		_check(result.state.board[4].card.ki == 0, "Copy activation spends exactly one ki")
		_check(result.state.board[1].owner == 1, "Copied card attacks after copying")
		_check(_count(result.events, &"attack_started") == (1 if tier == 1 else 2), "Separate attacks resolve in order")

func _test_movement() -> void:
	for owner: int in [1, 2]:
		for tier: int in [2, 3]:
			var board: Array = Rules.empty_board()
			board[2] = {"card": _card(&"TaiZuChangQuan", 3 - owner, &"move_enemy"), "owner": 3 - owner}
			var played: Dictionary = _card(StringName("YuSuiKunGang%da" % tier), owner, &"jade")
			var state = State.new(board, [played] if owner == 1 else [], [played] if owner == 2 else [], owner)
			var result: Dictionary = Simulator.apply_action(state, Action.make_play(0, 0, &"jade"))
			_check(bool(result.get("valid", false)), "Jade entry resolves")
			if not result.get("valid", false): continue
			_check(result.state.board[0] == null, "Jade moves into intervening gap")
			_check(result.state.board[2].owner == owner, "Moving Jade flips adjacent enemy without power comparison")
			_check(result.state.board[1] == null if tier == 3 else (result.state.board[1] != null and result.state.board[1].owner == 3 - owner),
				"Jade exiles or flips itself after enemies")

func _requests(order: Array) -> Dictionary:
	var actions: Array = []
	for only_activation: bool in order:
		var request: Dictionary = {"type": &"grant_extra_card_play", "amount": 1}
		if only_activation: request["activation_only"] = true
		actions.append(request)
	return {"triggers": [{"event": &"card_after_summoned", "conditions": [{"type": &"trigger_card_is_self"}], "actions": actions}]}

func _test_action_types() -> void:
	for order: Array in [[false, true], [true, false]]:
		for hand_available: bool in [false, true]:
			for activate_available: bool in [false, true]:
				var board: Array = Rules.empty_board()
				if activate_available:
					board[4] = {"card": _card(&"WuShengWuSe1", 1, &"usable_activation"), "owner": 1}
					board[3] = {"card": _card(&"TaiZuChangQuan", 1, &"activation_target"), "owner": 1}
				var played: Dictionary = _card(&"TaiZuChangQuan", 1, &"request_source")
				played.active_abilities = [_requests(order)]
				var hand: Array = [played]
				if hand_available: hand.append(_card(&"TaiZuChangQuan", 1, &"extra_hand"))
				var state = State.new(board, hand, [_card(&"TaiZuChangQuan", 2, &"opponent_hand")], 1)
				var result: Dictionary = Simulator.apply_action(state, Action.make_play(0, 8, &"request_source"))
				_check(bool(result.get("valid", false)), "Mixed extra requests compile and resolve")
				if not result.get("valid", false): continue
				var expected: StringName = &""
				for only_activation: bool in order:
					if activate_available if only_activation else hand_available:
						expected = &"activate" if only_activation else &"play"
						break
				_check(result.state.active_player == (2 if expected == &"" else 1), "First usable extra type controls continuation")
				if expected == &"": continue
				var legal: Array = Simulator.get_legal_actions(result.state)
				_check(not legal.is_empty(), "Chosen extra type has actions")
				for action: Action in legal:
					_check(action.action_type == expected, "Chosen extra type excludes other action kind")
				var compact = Compact.new()
				_check(compact.capture_state(result.state) and compact.scalars.size() == 16,
					"Continuation keeps 16 compact slots")
				_check(compact.scalars[11] == int(expected == &"activate"), "Slot 11 stores activation-only restriction")
				var continued: Dictionary = Simulator.apply_action(result.state, legal[0])
				_check(continued.get("valid", false) and continued.state.active_player == 2,
					"Only one granted continuation is consumed")
				if expected == &"activate":
					var search: Dictionary = Search.find_best_action_iterative_native(result.state, 1, {"max_depth": 1, "max_nodes": 100, "depth_mode": &"self_turn"})
					_check(search.get("has_completed_depth", false) and search.action.action_type == &"activate", "Deep AI obeys activation-only legality")

func _test_draw_attempts() -> void:
	for owner: int in [1, 2]:
		for capped: bool in [false, true]:
			var board: Array = Rules.empty_board()
			board[0] = {"card": _card(&"KongBi3", owner, &"continuous_draw"), "owner": owner}
			var played: Dictionary = _card(&"TaiZuChangQuan", owner, &"two_requests")
			played.active_abilities = [_requests([true, false])]
			var state = State.new(board, [played] if owner == 1 else [], [played] if owner == 2 else [], owner)
			state.extra_card_play_granted_this_turn = capped
			var result: Dictionary = Simulator.apply_action(state, Action.make_play(0, 8, &"two_requests"))
			_check(result.get("valid", false), "Both continuous-action attempts resolve for either owner")
			if not result.get("valid", false): continue
			_check(_count(result.events, &"card_drawn") == 2, "Activation and play attempt each draw, including capped attempts")
			_check(_count(result.events, &"extra_card_play_granted") == (0 if capped else 1), "Successful grants use shared cap")
			if not capped:
				_check(result.state.active_player == owner and not result.state.extra_activation_only,
					"After draws unusable activation falls back to now-usable hand play")
			var types: Array = []
			for event: Dictionary in result.events:
				if event.type in [&"card_drawn", &"extra_card_play_granted"]: types.append(event.type)
			_check(types == ([&"card_drawn", &"card_drawn"] if capped else [&"card_drawn", &"card_drawn", &"extra_card_play_granted"]), "Draw reactions finish before chosen grant event")

func _test_aura_removal() -> void:
	for owner: int in [1, 2]:
		var source: Dictionary = _card(&"YuDaFeiHua3", owner, &"rain_activation")
		var board: Array = Rules.empty_board()
		board[4] = {"card": source, "owner": owner}
		board[3] = {"card": _card(&"TaiZuChangQuan", owner, &"restore_attacker"), "owner": owner}
		var enemy: Dictionary = _card(&"TaiZuChangQuan", 3-owner, &"restored_target")
		enemy.powers = [1,1,1,1]
		board[0] = {"card": enemy, "owner": 3-owner}
		var state = State.new(board, [], [], owner)
		var tagged: Dictionary = Catalog.KUNLUN_DIAGONAL_OWNER_AURA.duplicate(true)
		tagged.tag = &"diagonal_adjacent_attack"
		var unrelated: Dictionary = tagged.duplicate(true)
		unrelated.tag = &"unrelated_effect"
		unrelated.auras[0].ability = {"modifiers": [{"type": &"defending_power_override", "value": 0}]}
		state.owner_auras_by_owner = {
			owner: [{"handle":1,"source_instance_id":&"rain_activation","aura":tagged},
				{"handle":2,"source_instance_id":&"rain_activation","aura":tagged},
				{"handle":3,"source_instance_id":&"rain_activation","aura":unrelated}],
			3-owner: [{"handle":4,"source_instance_id":&"restored_target","aura":tagged}],
		}
		state.next_owner_aura_handle = 5
		var result: Dictionary = Simulator.apply_action(state, Action.make_activate(4, &"rain_activation", &"board_cell", 3))
		_check(result.get("valid", false), "Tagged aura removal compiles after state roundtrip")
		if not result.get("valid", false): continue
		_check((result.state.owner_auras_by_owner.get(owner,[]) as Array).size() == 1, "All own matching auras removed; unrelated remains")
		_check((result.state.owner_auras_by_owner.get(3-owner,[]) as Array).size() == 1, "Opponent aura unaffected")
		_check(result.state.board[0].owner == owner, "Chosen ally attacks with orthogonal rules after aura removal")
		_check(_count(result.events,&"owner_aura_removed") == 2, "Each removed aura reports its exact handle")

func _test_copy_special_powers() -> void:
	for powers: Array in [[-1,-1,-1,-1],[0,0,0,0],[7,8,9,6]]:
		var board: Array = Rules.empty_board()
		var source: Dictionary = _card(&"WuShengWuSe1", 1, &"copy_edge")
		if powers == [7,8,9,6]: source.powers = powers.duplicate()
		board[4] = {"card":source,"owner":1}
		var donor: Dictionary = _card(&"TaiZuChangQuan",1,&"edge_donor")
		donor.powers = powers.duplicate()
		board[3] = {"card":donor,"owner":1}
		var state = State.new(board, [], [_card(&"TaiZuChangQuan",2,&"edge_opponent")],1)
		var result: Dictionary = Simulator.apply_action(state,Action.make_activate(4,&"copy_edge",&"board_cell",3))
		_check(result.get("valid",false), "Special point-copy activation resolves")
		if not result.get("valid",false): continue
		_check(result.state.board[4] == null if powers == [0,0,0,0] else result.state.board[4].card.powers == powers, "Copies sentinel or removes four-zero result")
		_check(_count(result.events,&"powers_changed") == (1 if powers == [0,0,0,0] else 0), "Identical copy is a no-op")

func _test_copy_last_summoned() -> void:
	var source: Dictionary = _card(&"TaiZuChangQuan", 1, &"copy_last")
	source.active_abilities = [{"triggers":[{"event":&"card_after_summoned","conditions":[{"type":&"trigger_card_is_self"}],"actions":[
		{"type":&"summon_card","card_id":&"BaGuaFangWei","cell":{"type":&"first_adjacent_empty","card":&"ability_source"}},
		{"type":&"change_powers","card":&"ability_source","copy_from":&"last_summoned_card"},
	]}]}]
	# Include the generated prototype in this synthetic root; catalog closure alone
	# cannot infer custom test abilities attached to an unrelated TaiZu card.
	var state = State.new(Rules.empty_board(),[source],[_card(&"BaGuaFangWei",2,&"copy_prototype")])
	var result: Dictionary = Simulator.apply_action(state,Action.make_play(0,0,&"copy_last"))
	_check(result.get("valid",false), "Copy supports the validated last-summoned reference")
	if result.get("valid",false):
		_check(result.state.board[0].card.powers == [-1,-1,-1,-1], "Copy reads the current action execution's last summoned card; events=%s" % str(result.events))

func _test_native_declaration_validation() -> void:
	for action: Dictionary in [
		{"type":&"grant_extra_card_play","amount":1,"activation_only":1},
		{"type":&"grant_extra_card_play","amount":1,"activation_only":true,"next_hand_play_source":&"discard"},
		{"type":&"change_powers","card":&"ability_source","copy_from":&"selected_card","amount":1},
		{"type":&"summon_card","card_id":&"BaGuaFangWei","card":&"selected_card","cell":{"type":&"first_adjacent_empty","card":&"ability_source"}},
		{"type":&"remove_owner_auras","tag":""},
		{"type":&"grant_owner_aura","tag":true,"aura":{"modifiers":[{"type":&"cannot_attack"}]}},
		{"type":&"grant_owner_aura","aura":{"tag":true,"modifiers":[{"type":&"cannot_attack"}]}},
	]:
		var ability: Dictionary = {"triggers":[{"event":&"card_summoned","conditions":[{"type":&"trigger_card_is_self"}],"actions":[action]}]}
		_check(not Catalog.validate_ability(ability).is_empty(), "Catalog rejects malformed extension")
		var source: Dictionary = _card(&"TaiZuChangQuan",1,&"bad_extension")
		source.active_abilities = [ability]
		var compact = Compact.new()
		_check(compact.capture_state(State.new(Rules.empty_board(),[source])), "Malformed fixture captures independently of declaration validator")
		var kernel: Object = ClassDB.instantiate(&"DuelNativeCompactKernel")
		_check(not kernel.call("load_compact_payload",compact.to_variant_payload()), "Native independently rejects malformed extension")

