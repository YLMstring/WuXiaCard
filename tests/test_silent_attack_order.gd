extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")
const Action = preload("res://scripts/duel_action.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")

var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for owner: int in [1,2]:
		for tier: int in [1,2,3,4]:
			_test_attack_order(owner,tier)
		for tier: int in [2,3,4]:
			_test_counterattack_interleaves(owner,tier)
		_test_adjacent_snapshot(owner)
	print("SILENT_ATTACK_ORDER_%s checks=%d failures=%d" % ["PASSED" if failures == 0 else "FAILED",checks,failures])
	quit(failures)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _card(id: StringName, owner: int, instance: StringName, powers: Array = []) -> Dictionary:
	var card: Dictionary = Catalog.create_instance(id,owner,instance)
	if not powers.is_empty(): card.powers = powers.duplicate()
	return card

func _attack_sources(events: Array) -> Array:
	var sources: Array = []
	for event: Dictionary in events:
		if event.type == &"attack_started": sources.append(event.source_instance_id)
	return sources

func _test_attack_order(owner: int, tier: int) -> void:
	var board: Array = Rules.empty_board()
	board[4] = {"card":_card(StringName("WuShengWuSe%d" % tier),owner,&"silent"),"owner":owner}
	board[3] = {"card":_card(&"TaiZuChangQuan",owner,&"left_ally",[9,9,9,9]),"owner":owner}
	board[5] = {"card":_card(&"TaiZuChangQuan",owner,&"chosen_ally",[7,8,9,6]),"owner":owner}
	for cell: int in [0,1,2]:
		board[cell] = {"card":_card(&"TaiZuChangQuan",3-owner,StringName("target_%d" % cell),[1,1,1,1]),"owner":3-owner}
	var state = State.new(board,[],[],owner)
	var result: Dictionary = Simulator.apply_action(state,Action.make_activate(4,&"silent",&"board_cell",5))
	_check(result.get("valid",false), "Silent activation resolves owner=%d tier=%d" % [owner,tier])
	if not result.get("valid",false): return
	var expected: Array = [&"silent"] if tier == 1 else ([&"left_ally",&"chosen_ally",&"silent"] if tier == 4 else [&"chosen_ally",&"silent"])
	_check(_attack_sources(result.events) == expected, "Allied attacks finish before Silent; tier=%d got=%s" % [tier,str(_attack_sources(result.events))])
	var copy_index: int = -1
	var first_attack: int = -1
	for index: int in range(result.events.size()):
		var event: Dictionary = result.events[index]
		if event.type == &"powers_changed" and event.instance_id == &"silent": copy_index = index
		if event.type == &"attack_started" and first_attack < 0: first_attack = index
	_check(copy_index >= 0 and copy_index < first_attack, "Copy completes before every attack")
	_check(result.state.board[4].card.powers == [7,8,9,6] and result.state.board[4].card.ki == 0, "Copy and normal ki cost remain intact")
	_check(result.state.board[1].owner == owner, "Silent's final attack still executes")

func _test_counterattack_interleaves(owner: int, tier: int) -> void:
	var board: Array = Rules.empty_board()
	board[4] = {"card":_card(StringName("WuShengWuSe%d" % tier),owner,&"silent"),"owner":owner}
	board[3] = {"card":_card(&"TaiZuChangQuan",owner,&"chosen_ally",[9,9,9,9]),"owner":owner}
	board[0] = {"card":_card(&"TaiZuChangQuan",3-owner,&"first_capture",[1,1,1,1]),"owner":3-owner}
	var counter: Dictionary = _card(&"TaiZuChangQuan",3-owner,&"counter",[1,1,1,8])
	counter.active_abilities = [Catalog.HENGSHAN_COUNTERATTACK]
	board[1] = {"card":counter,"owner":3-owner}
	var state = State.new(board,[],[],owner)
	var result: Dictionary = Simulator.apply_action(state,Action.make_activate(4,&"silent",&"board_cell",3))
	_check(result.get("valid",false), "Counterattack fixture resolves")
	if not result.get("valid",false): return
	_check(_attack_sources(result.events) == [&"chosen_ally",&"counter",&"silent"], "Counterattack completes between ally and Silent")
	_check(result.state.board[0].owner == 3-owner and result.state.board[1].owner == owner, "Attack ordering changes actual capture outcome as described")

func _test_adjacent_snapshot(owner: int) -> void:
	var board: Array = Rules.empty_board()
	board[4] = {"card":_card(&"WuShengWuSe4",owner,&"silent"),"owner":owner}
	var left: Dictionary = _card(&"TaiZuChangQuan",owner,&"left_ally",[9,9,9,9])
	left.active_abilities = [Catalog.KUNLUN_DIAGONAL_ATTACK]
	board[3] = {"card":left,"owner":owner}
	board[5] = {"card":_card(&"TaiZuChangQuan",owner,&"chosen_ally",[10,10,10,10]),"owner":owner}
	for cell: int in [0,1,2,7]:
		var powers: Array = [9,9,9,9] if cell == 7 else ([0,0,0,0] if cell == 0 else [1,1,1,1])
		board[cell] = {"card":_card(&"TaiZuChangQuan",3-owner,StringName("snapshot_target_%d" % cell),powers),"owner":3-owner}
	var result: Dictionary = Simulator.apply_action(State.new(board,[],[],owner),Action.make_activate(4,&"silent",&"board_cell",5))
	_check(result.get("valid",false), "Four-tier snapshot fixture resolves")
	if not result.get("valid",false): return
	_check(_attack_sources(result.events) == [&"left_ally",&"chosen_ally",&"silent"], "Newly captured adjacent ally is not appended to attack snapshot")
	_check(result.state.board[1].owner == owner and result.state.board[0].owner == 3-owner, "New ally does not attack its zero-point neighbor")
