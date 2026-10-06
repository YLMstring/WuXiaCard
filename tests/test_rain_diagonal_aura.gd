extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")
const Action = preload("res://scripts/duel_action.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const Native = preload("res://scripts/duel_native_rules.gd")
const Compact = preload("res://scripts/duel_compact_state.gd")
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for owner: int in [1, 2]:
		for tier: int in [1, 2, 3, 4]:
			_test_range(owner, tier)
		_test_source_lifecycle(owner)
		_test_nested_aura(owner)
		_test_evasion(owner)
		for tier: int in [2, 3, 4]:
			_test_activation(owner, tier, false)
			_test_activation(owner, tier, true)
	_test_validation_and_legacy_range()
	print("RAIN_DIAGONAL_AURA_%s checks=%d failures=%d" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(failures)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _card(id: StringName, owner: int, instance: StringName, powers: Array = []) -> Dictionary:
	var card: Dictionary = Catalog.create_instance(id, owner, instance)
	if not powers.is_empty(): card.powers = powers.duplicate()
	return card

func _put(board: Array, cell: int, card: Dictionary, owner: int) -> void:
	board[cell] = {"card": card, "owner": owner}

func _count(events: Array, type: StringName) -> int:
	var count := 0
	for event: Dictionary in events:
		if event.type == type: count += 1
	return count

func _test_range(owner: int, tier: int) -> void:
	var enemy := 3 - owner
	var board: Array = Rules.empty_board()
	_put(board, 4, _card(&"TaiZuChangQuan", owner, &"middle", [9,9,9,9]), owner)
	_put(board, 6, _card(&"TaiZuChangQuan", owner, &"ally", [9,9,9,9]), owner)
	for cell: int in [1,2,5,8]:
		_put(board, cell, _card(&"TaiZuChangQuan", enemy, StringName("enemy_%d" % cell), [9,9,1,1] if cell == 8 else [1,1,1,1]), enemy)
	var rain: Dictionary = _card(StringName("YuDaFeiHua%d" % tier), owner, &"rain")
	var state = State.new(board, [rain] if owner == 1 else [], [rain] if owner == 2 else [], owner)
	var result: Dictionary = Simulator.apply_action(state, Action.make_play(0, 0, &"rain"))
	_check(result.get("valid", false), "Rain entry resolves owner=%d tier=%d" % [owner,tier])
	if not result.get("valid", false): return
	state = result.state
	_check(state.board[8].owner == owner, "Distant diagonal wins one opposed pair through occupied middle")
	_check(state.board[1].owner == enemy and state.board[2].owner == enemy and state.board[5].owner == enemy, "No adjacent/long orthogonal or skew captures")
	_check((state.owner_auras_by_owner.get(owner, []) as Array).size() == 1, "Every tier grants player aura")
	_check(Native.can_attack_target(state,6,2) and Native.is_target_in_attack_range(state,6,2), "Other ally receives distant diagonal; hint matches attack")
	_check(not Native.can_attack_target(state,6,5,{},true), "Skew (one by two) is outside diagonal range")
	result = Simulator._resolve_standard_attacks(state,6,&"ally",&"rain_ally_probe")
	_check(result.get("valid",false) and result.state.board[2].owner == owner, "Other ally really attacks distant diagonal")
	var has_activation := Native.count_legal_actions_for_owner(state,owner) > 0
	_check(has_activation if tier >= 2 else not has_activation, "Tier one has no activation; higher tiers do")

func _test_source_lifecycle(owner: int) -> void:
	var enemy := 3-owner
	var board: Array = Rules.empty_board()
	for cell: int in [0,3,4]:
		_put(board,cell,_card(&"TaiZuChangQuan",owner,StringName("ally_%d" % cell),[9,9,9,9]),owner)
	for cell: int in [1,2]:
		_put(board,cell,_card(&"TaiZuChangQuan",enemy,StringName("enemy_%d" % cell),[1,1,1,1]),enemy)
	var rain: Dictionary = _card(&"YuDaFeiHua2",owner,&"rain")
	var capturer: Dictionary = _card(&"TaiZuChangQuan",enemy,&"capturer",[9,9,9,9])
	var entry: Dictionary = Simulator.apply_action(State.new(board,[rain] if owner == 1 else [capturer],[rain] if owner == 2 else [capturer],owner),Action.make_play(0,8,&"rain"))
	_check(entry.get("valid",false), "Source lifecycle entry")
	if not entry.get("valid",false): return
	var state = entry.state
	var saved: Dictionary = state.owner_auras_by_owner.duplicate(true)
	for action: Dictionary in [
		{"type":Catalog.ACTION_PERMANENTLY_REMOVE_NON_RETAINED_ABILITIES,"card":Catalog.CARD_REF_ABILITY_SOURCE},
		{"type":Catalog.ACTION_EXILE_CARD,"card":Catalog.CARD_REF_ABILITY_SOURCE},
	]:
		var isolated = state.duplicate_state()
		var result: Dictionary = Native.execute_actions(isolated,8,&"rain",owner,[action],{})
		_check(result.get("valid",false), "Source removal/ability loss resolves")
		_check(isolated.owner_auras_by_owner == saved and Native.can_attack_target(isolated,4,2) and not Native.can_attack_target(isolated,4,1,{},true), "Source removal/ability loss preserves player aura")
	var recipient: Dictionary = Simulator.resolve_non_attack_flip(state.duplicate_state(),&"ally_4",enemy)
	_check(recipient.get("valid",false) and Native.can_attack_target(recipient.state,4,3,{},true) and not Native.can_attack_target(recipient.state,4,0,{},true), "Recipient-only flip loses aura without altering holder")
	var non_attack: Dictionary = Simulator.resolve_non_attack_flip(state.duplicate_state(),&"rain",enemy)
	_check(non_attack.get("valid",false) and Native.can_attack_target(non_attack.state,4,2) and not Native.can_attack_target(non_attack.state,8,4,{},true), "Non-attack source flip preserves original holder")
	state.active_player = enemy
	var capture: Dictionary = Simulator.apply_action(state,Action.make_play(0,5,&"capturer"))
	_check(capture.get("valid",false), "Real opponent attack resolves")
	if not capture.get("valid",false): return
	state = capture.state
	_check(state.board[8].owner == enemy and state.board[8].card.active_abilities.is_empty(), "Source actually flips and loses its card abilities")
	_check(state.owner_auras_by_owner == saved, "Stored aura unchanged after source flip")
	_check(Native.can_attack_target(state,4,2) and not Native.can_attack_target(state,4,1,{},true), "Original ally keeps diagonal rule after source flip")
	_check(not Native.can_attack_target(state,8,4,{},true), "Source flip never grants aura to opponent")
	Simulator.resolve_non_attack_flip(state,&"ally_4",enemy)
	_check(Native.can_attack_target(state,4,3,{},true) and not Native.can_attack_target(state,4,0,{},true), "Recipient flipped after source still uses ordinary enemy range")
	Simulator.resolve_non_attack_flip(state,&"ally_4",owner)
	_check(Native.can_attack_target(state,4,2) and not Native.can_attack_target(state,4,1,{},true), "Returned ally regains original player's aura")
	var attack: Dictionary = Simulator._resolve_standard_attacks(state,4,&"ally_4",&"post_flip")
	_check(attack.get("valid",false) and attack.state.board[2].owner == owner and attack.state.board[1].owner == enemy, "Post-flip real attack captures diagonal and skips orthogonal")

func _test_nested_aura(owner: int) -> void:
	var board: Array = Rules.empty_board()
	_put(board,4,_card(&"TaiZuChangQuan",3-owner,&"provider"),3-owner)
	_put(board,3,_card(&"TaiZuChangQuan",owner,&"recipient"),owner)
	_put(board,0,_card(&"TaiZuChangQuan",owner,&"distant"),owner)
	var state = State.new(board,[],[],owner)
	state.owner_auras_by_owner = {owner:[{"handle":1,"source_instance_id":&"provider","aura":{
		"auras":[{"selector":{"zones":[&"board"],"conditions":[{"type":&"selected_card_is_ally"},{"type":&"selected_card_adjacent_to_source"}]},
		"ability":{"triggers":[{"event":&"end_owner_turn","actions":[{"type":&"gain_ki","amount":1}]}]}}]}}]}
	state.next_owner_aura_handle = 2
	var result: Dictionary = Native.resolve_event(state,&"end_owner_turn",{"turn_owner_id":owner})
	_check(result.get("valid",false), "Nested aura discovers/revalidates after provider owner changes")
	_check(state.board[3].card.ki == 1 and state.board[0].card.ki == 0 and state.board[4].card.ki == 0, "Nested aura uses holder allegiance but live provider adjacency")
	# Discover while provider is still friendly, then flip it before the queued
	# aura recipient resolves. Discovery and revalidation must agree on holder.
	state.board[3].card.ki = 0
	state.board[4].owner = owner
	state.board[4].card.active_abilities = [{"retained_on_flip":true,"triggers":[{"event":&"end_owner_turn","actions":[{"type":&"flip_self","new_owner":&"opponent_of_card_current_owner"}]}]}]
	result = Native.resolve_event(state,&"end_owner_turn",{"turn_owner_id":owner})
	_check(result.get("valid",false) and state.board[4].owner == 3-owner, "Provider flips between nested aura discovery and execution")
	_check(state.board[3].card.ki == 1, "Queued aura recipient revalidates against fixed holder")

func _test_evasion(owner: int) -> void:
	var board: Array = Rules.empty_board()
	var attacker: Dictionary = _card(&"TaiZuChangQuan",owner,&"diagonal_attacker",[9,9,9,9])
	attacker.active_abilities = [{"modifiers":[{"type":&"non_orthogonal_attack_any_axis","allow_diagonal_all":true}]}]
	_put(board,2,attacker,owner)
	_put(board,5,_card(&"KongBi2",3-owner,&"evading_target",[1,1,1,1]),3-owner)
	var state = State.new(board,[],[],owner)
	var result: Dictionary = Simulator._resolve_standard_attacks(state,2,&"diagonal_attacker",&"evasion_probe")
	_check(result.get("valid",false), "Evasion under all-diagonal range resolves")
	_check(state.board[5] == null and state.board[8] != null and state.board[8].card.instance_id == &"evading_target" and state.board[8].owner == 3-owner, "Evasion skips diagonal empty cell four and escapes to eight")

func _test_activation(owner: int, tier: int, full_hand: bool) -> void:
	var board: Array = Rules.empty_board()
	var rain: Dictionary = _card(StringName("YuDaFeiHua%d" % tier),owner,&"rain",[1,1,1,1])
	rain.active_abilities.append({"modifiers":[{"type":&"unlimited_attack_range"}]})
	_put(board,0,rain,owner)
	_put(board,4,_card(&"TaiZuChangQuan",owner,&"ally",[9,9,9,9]),owner)
	for cell: int in [1,8]: _put(board,cell,_card(&"TaiZuChangQuan",3-owner,StringName("enemy_%d" % cell),[1,1,1,1]),3-owner)
	var hand: Array = []
	if full_hand:
		for index: int in range(5): hand.append(_card(&"TaiZuChangQuan",owner,StringName("hand_%d" % index)))
	var state = State.new(board,hand if owner == 1 else [],hand if owner == 2 else [],owner)
	var aura: Dictionary = Catalog.KUNLUN_DIAGONAL_OWNER_AURA.duplicate(true)
	aura.tag = &"diagonal_adjacent_attack"
	var unrelated := {"tag":&"other","modifiers":[{"type":&"enemy_cannot_attack_during_owner_turn"}]}
	state.owner_auras_by_owner = {owner:[{"handle":1,"source_instance_id":&"rain","aura":aura},{"handle":2,"source_instance_id":&"rain","aura":aura},{"handle":3,"source_instance_id":&"rain","aura":unrelated}],3-owner:[{"handle":4,"source_instance_id":&"rain","aura":unrelated}]}
	state.next_owner_aura_handle = 5
	var result: Dictionary = Simulator.apply_action(state,Action.make_activate(0,&"rain",&"board_cell",4))
	_check(result.get("valid",false), "Rain activation resolves tier=%d full=%s owner=%d" % [tier,full_hand,owner])
	if not result.get("valid",false): return
	state = result.state
	_check(state.board[0].card.ki == 0, "Activation costs one ki")
	_check(state.owner_auras_by_owner[owner].size() == 1 and state.owner_auras_by_owner[3-owner].size() == 1, "All own Rain auras cleared; other tags and opponent preserved")
	_check(state.board[1].owner == owner and state.board[8].owner == 3-owner, "Chosen ally attacks after restoration using ordinary range")
	var last_remove := -1
	var first_attack := -1
	var added := -1
	for index: int in range(result.events.size()):
		var event: Dictionary = result.events[index]
		if event.type == &"owner_aura_removed": last_remove = index
		if event.type == &"attack_started" and first_attack < 0: first_attack = index
		if event.type == &"card_added_to_hand": added = index
	_check(last_remove >= 0 and first_attack > last_remove, "Aura removal precedes attack")
	if tier == 2 or full_hand:
		_check(state.hands[owner].size() == (5 if full_hand else 0), "Tier two no copy; full hand remains fixed at five")
	else:
		_check(state.hands[owner].size() == 1 and added > first_attack, "Copy arrives after attack")
		if state.hands[owner].is_empty(): return
		var copy: Dictionary = state.hands[owner][0]
		_check(copy.card_id == rain.card_id and copy.instance_id != &"rain", "Copy has matching card ID and new instance")
		_check(copy.powers == Catalog.get_definition(rain.card_id).powers and copy.ki == 1 and copy.active_abilities == Catalog.create_instance(rain.card_id,owner,&"expected").active_abilities, "Fresh copy restores catalog powers, ki and abilities")
	state.active_player = owner
	_check(not Simulator.is_action_legal(state,Action.make_activate(0,&"rain",&"board_cell",4)), "No second activation without ki even on own turn")

func _test_validation_and_legacy_range() -> void:
	for flag: Variant in [true,false,1,"true"]:
		var ability := {"modifiers":[{"type":&"non_orthogonal_attack_any_axis","allow_diagonal_all":flag}]}
		var valid := typeof(flag) == TYPE_BOOL
		_check(Catalog.validate_ability(ability).is_empty() == valid, "Catalog validates Boolean all-diagonal field")
		var card: Dictionary = _card(&"TaiZuChangQuan",1,&"flag")
		card.active_abilities = [ability]
		var compact = Compact.new()
		compact.capture_state(State.new(Rules.empty_board(),[card]))
		var kernel: Object = ClassDB.instantiate(&"DuelNativeCompactKernel")
		_check(bool(kernel.call("load_compact_payload",compact.to_variant_payload())) == valid, "Native independently validates Boolean all-diagonal field")
		kernel = null
	var board: Array = Rules.empty_board()
	var old: Dictionary = _card(&"TaiZuChangQuan",1,&"legacy",[9,9,9,9])
	old.active_abilities = [{"modifiers":[{"type":&"non_orthogonal_attack_any_axis","allow_diagonal_adjacent":true,"forbid_orthogonal_adjacent":true}]}]
	_put(board,0,old,1)
	for cell: int in [1,4,8]: _put(board,cell,_card(&"TaiZuChangQuan",2,StringName("old_%d" % cell),[1,1,1,1]),2)
	var state = State.new(board)
	_check(Native.can_attack_target(state,0,4) and not Native.can_attack_target(state,0,8) and not Native.can_attack_target(state,0,1), "Legacy adjacent-only flag keeps old semantics")
