extends SceneTree

const DuelScene = preload("res://scenes/duel.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const State = preload("res://scripts/duel_state.gd")
const Rules = preload("res://scripts/duel_rules.gd")

var checks := 0
var failures := 0
var duel: Node
var saw_extra_activation := false
var visible_walk := false
var saved_screenshot := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	visible_walk = "--kunlun-visible" in OS.get_cmdline_user_args()
	duel = DuelScene.instantiate()
	duel.deck_profile_path = "user://kunlun_integration_isolated.json"
	duel.testing_mode = true
	duel.opponent_hand_shuffle_seed = -1
	duel.opening_layout_seed = -1
	root.add_child(duel)
	await process_frame
	await process_frame
	if not visible_walk: duel.debug_set_fast_mode(true)
	process_frame.connect(_watch_status)
	for cycle: int in range(5 if visible_walk else 1):
		await _silent_flow(cycle)
		await _formation_flow()
		await _rain_flow()
		await _jade_flow()
	await _ai_flow()
	duel.queue_free()
	await process_frame
	await process_frame
	print("KUNLUN_INTEGRATION_%s checks=%d visible=%s" % ["PASSED" if failures == 0 else "FAILED", checks, visible_walk])
	quit(failures)

func _watch_status() -> void:
	if not is_instance_valid(duel): return
	if duel.turn_status.text == "额外指定":
		saw_extra_activation = true
		if visible_walk and not saved_screenshot:
			saved_screenshot = true
			_capture.call_deferred()

func _capture() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.summer/local/kunlun-20261005/extra-activation.png")

func _card(id: StringName, owner: int, instance: StringName, powers: Array = []) -> Dictionary:
	var card: Dictionary = Catalog.create_instance(id, owner, instance)
	if not powers.is_empty(): card.powers = powers.duplicate()
	return card

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("KUNLUN_INTEGRATION: " + message)

func _load(state: State) -> void:
	duel.testing_mode = true
	duel._rebuild_views_from_state(state)
	await process_frame

func _silent_flow(cycle: int) -> void:
	var board: Array = Rules.empty_board()
	board[0] = {"card":_card(&"KongBi3",1,&"draw_source"),"owner":1}
	board[3] = {"card":_card(&"TaiZuChangQuan",1,&"donor",[7,8,9,6]),"owner":1}
	board[1] = {"card":_card(&"TaiZuChangQuan",2,&"weak_enemy",[1,1,1,1]),"owner":2}
	var state = State.new(board,[_card(&"WuShengWuSe1",1,&"silent"),_card(&"TaiZuChangQuan",1,&"spare")],[_card(&"TaiZuChangQuan",2,&"reply")])
	state.decks[1] = [_card(&"TaiZuChangQuan",1,&"attempt_draw")]
	await _load(state)
	saw_extra_activation = false
	# Headless fast mode has no frame barrier: verify the actual presentation
	# method's label too, while the visible walkthrough observes the real flow.
	if not visible_walk:
		await duel._present_extra_card_play_event({"activation_only":true})
		_check(duel.turn_status.text == "额外指定", "Activation-only presentation uses its own label")
	_check(await duel.debug_commit_move(1,0,4,false), "Silent entry commits through production controller")
	_check(duel.duel_state.active_player == 1 and duel.duel_state.extra_activation_only, "Controller retains activation-only decision")
	_check(duel.duel_state.get_hand(1).size() == 2, "KongBi draws before activation grant")
	if visible_walk: _check(saw_extra_activation, "Normal-duration entry displays extra-activation label")
	for repeat: int in range(10):
		_check(not await duel.debug_commit_move(1,0,8,false), "Repeated hand input cannot spend activation-only credit")
	_check(not await duel.debug_commit_activate(1,4,8,false), "Out-of-range activation is rejected")
	_check(await duel.debug_commit_activate(1,4,3,false), "Granted activation commits")
	_check(duel.board_cards[4].card_data.powers == [7,8,9,6] and duel.duel_state.board[4].card.powers == [7,8,9,6], "Rendered and authoritative copy values match")
	_check(duel.duel_state.board[1].owner == 1 and duel.board_cards[1].owner_id == 1, "Copied attack visibly flips target")
	_check(duel.duel_state.active_player == 2 and not duel.duel_state.extra_activation_only, "Continuation ends after one activation")
	if cycle == 0:
		_check(duel.debug_open_inspection(duel.board_cards[4].card_data), "New card remains inspectable after activation")
		_check(not await duel.debug_commit_activate(2,4,3,false), "Inspection blocks new action")
		duel.debug_close_inspection()

func _formation_flow() -> void:
	var board: Array = Rules.empty_board()
	board[4] = {"card":_card(&"WuShengWuSe1",1,&"formation_anchor"),"owner":1}
	var state = State.new(board,[_card(&"YinYangLiangYi3",1,&"formation_entry")],[_card(&"TaiZuChangQuan",2,&"reply")])
	state.decks[1] = [_card(&"TianGangBeiDou2",1,&"formation_draw")]
	await _load(state)
	_check(await duel.debug_commit_move(1,0,8,false), "Formation entry runs animated draw/exile/summon")
	_check(duel.board_cards[8] == null and duel.board_cards[1] != null and duel.board_cards[1].card_data.card_id == &"BaGuaFangWei", "Generated Bagua and removed source reconcile")
	var view: Node = duel._get_card_view_by_instance(&"formation_draw")
	_check(view != null and view.card_data.powers == [5,4,5,4], "Drawn formation receives buff before source exile")

func _rain_flow() -> void:
	var board: Array = Rules.empty_board()
	board[0] = {"card":_card(&"TaiZuChangQuan",2,&"rain_diagonal",[1,1,1,1]),"owner":2}
	board[1] = {"card":_card(&"TaiZuChangQuan",2,&"rain_straight",[1,1,1,1]),"owner":2}
	board[3] = {"card":_card(&"TaiZuChangQuan",1,&"rain_ally",[9,9,9,9]),"owner":1}
	await _load(State.new(board,[_card(&"YuDaFeiHua3",1,&"rain")],[_card(&"TaiZuChangQuan",2,&"reply",[0,0,0,0])]))
	_check(await duel.debug_commit_move(1,0,4,false), "Rain entry presents diagonal attack")
	_check(duel.board_cards[0].owner_id == 1 and duel.board_cards[1].owner_id == 2, "Diagonal capture leaves straight target untouched")
	_check(await duel.debug_commit_move(2,0,8,false), "Opponent completes intervening turn")
	_check(await duel.debug_commit_activate(1,4,3,false), "Rain restoration activates through normal target path")
	_check((duel.duel_state.owner_auras_by_owner.get(1,[]) as Array).is_empty(), "Restoration removes rain owner aura")

func _jade_flow() -> void:
	var board: Array = Rules.empty_board()
	board[2] = {"card":_card(&"TaiZuChangQuan",1,&"jade_enemy",[9,9,9,9]),"owner":1}
	await _load(State.new(board,[_card(&"TaiZuChangQuan",1,&"reply")],[_card(&"YuSuiKunGang3a",2,&"jade"),_card(&"TaiZuChangQuan",2,&"jade_spare")],2))
	_check(await duel.debug_commit_move(2,0,0,false), "Opponent Jade animates entry movement")
	_check(duel.board_cards[0] == null and duel.board_cards[1] == null and duel.board_cards[2].owner_id == 2, "Movement flips adjacent enemy then removes Jade")

func _ai_flow() -> void:
	var board: Array = Rules.empty_board()
	board[4] = {"card":_card(&"WuShengWuSe1",2,&"ai_silent"),"owner":2}
	board[3] = {"card":_card(&"TaiZuChangQuan",2,&"ai_donor",[7,8,9,6]),"owner":2}
	board[1] = {"card":_card(&"TaiZuChangQuan",1,&"ai_target",[1,1,1,1]),"owner":1}
	var state = State.new(board,[_card(&"TaiZuChangQuan",1,&"player_reply")],[_card(&"TaiZuChangQuan",2,&"ai_spare")],2)
	state.extra_card_plays_remaining = 1
	state.extra_activation_only = true
	state.extra_card_play_granted_this_turn = true
	await _load(state)
	duel.testing_mode = false
	duel.debug_set_search_limits(0.5,{"max_depth":1,"max_nodes":100})
	await duel._perform_opponent_turn()
	var report: Dictionary = duel.debug_get_last_search_report()
	var action = report.get("action")
	_check(action != null and action.action_type == &"activate" and not report.get("used_fallback",false), "Actual opponent worker chooses constrained activation")
	_check(duel.duel_state.active_player == 1 and duel.board_cards[4].card_data.powers == [7,8,9,6], "Actual AI activation finishes and renders copied powers")
