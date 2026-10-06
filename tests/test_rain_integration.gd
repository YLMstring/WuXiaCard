extends SceneTree

const DuelScene = preload("res://scenes/duel.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const State = preload("res://scripts/duel_state.gd")
const Rules = preload("res://scripts/duel_rules.gd")
var checks := 0
var failures := 0
var duel: Node
var visible_walk := false

func _init() -> void:
	call_deferred("_run")

func _card(id: StringName, owner: int, instance: StringName, powers: Array = []) -> Dictionary:
	var card: Dictionary = Catalog.create_instance(id,owner,instance)
	if not powers.is_empty(): card.powers = powers.duplicate()
	return card

func _put(board: Array, cell: int, card: Dictionary, owner: int) -> void:
	board[cell] = {"card":card,"owner":owner}

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _load(state: State) -> void:
	duel._rebuild_views_from_state(state)
	await process_frame

func _run() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"),true)
	visible_walk = "--rain-visible" in OS.get_cmdline_user_args()
	duel = DuelScene.instantiate()
	duel.deck_profile_path = "user://rain_integration_isolated.json"
	duel.testing_mode = true
	duel.opponent_hand_shuffle_seed = -1
	duel.opening_layout_seed = -1
	root.add_child(duel)
	await process_frame
	await process_frame
	if not visible_walk: duel.debug_set_fast_mode(true)
	for owner: int in [1,2]:
		for tier: int in [1,2,3,4]: await _range_and_activation(owner,tier)
		await _source_flip(owner)
	duel.queue_free()
	await process_frame
	await process_frame
	print("RAIN_INTEGRATION_%s checks=%d visible=%s" % ["PASSED" if failures == 0 else "FAILED",checks,visible_walk])
	quit(failures)

func _range_and_activation(owner: int, tier: int) -> void:
	var enemy := 3-owner
	var board: Array = Rules.empty_board()
	_put(board,4,_card(&"TaiZuChangQuan",owner,&"middle",[9,9,9,9]),owner)
	for cell: int in [1,8]:
		_put(board,cell,_card(&"TaiZuChangQuan",enemy,StringName("target_%d" % cell),[1,1,1,1]),enemy)
	var own_hand := [_card(StringName("YuDaFeiHua%d" % tier),owner,&"rain"),_card(&"TaiZuChangQuan",owner,&"own_spare")]
	var other_hand := [_card(&"TaiZuChangQuan",enemy,&"reply",[0,0,0,0]),_card(&"TaiZuChangQuan",enemy,&"enemy_spare")]
	await _load(State.new(board,own_hand if owner == 1 else other_hand,own_hand if owner == 2 else other_hand,owner))
	_check(await duel.debug_commit_move(owner,0,0,false), "Rain entry commits owner=%d tier=%d" % [owner,tier])
	_check(duel.board_cards[8].owner_id == owner and duel.board_cards[1].owner_id == enemy, "Rendered distant diagonal capture leaves adjacent orthogonal enemy")
	_check(duel.duel_state.owner_auras_by_owner[owner].size() == 1, "All tiers visibly apply player aura")
	if tier == 1: return
	_check(await duel.debug_commit_move(enemy,0,7,false), "Intervening enemy turn commits")
	var trace_start: int = duel.debug_get_attack_vfx_trace().size()
	_check(await duel.debug_commit_activate(owner,0,4,false), "Rain restores range and attacks through production activation")
	_check(duel.duel_state.owner_auras_by_owner[owner].is_empty(), "Restoration clears aura")
	_check(duel.board_cards[1].owner_id == owner and duel.board_cards[0].card_data.ki == 0, "Rendered ordinary attack and spent ki match simulator")
	var trace: Array = duel.debug_get_attack_vfx_trace().slice(trace_start)
	_check(not trace.is_empty() and trace[0].source_instance_id == &"middle", "Attack animation comes from chosen ally")
	var hand: Array = duel.duel_state.get_hand(owner)
	_check(hand.size() == (1 if tier == 2 else 2), "Only tiers three and four add a copy")
	if tier >= 3 and hand.size() == 2:
		var copy: Dictionary = hand[1]
		var view: Node = duel._get_card_view_by_instance(copy.instance_id)
		_check(view != null and view.card_data.card_id == copy.card_id and view.card_data.ki == 1 and view.card_data.powers == [4,7,8,3], "Generated copy renders in hand at original powers and ki")
		if visible_walk and owner == 1 and tier == 3:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.summer/local/rain-update-20261006/rain-copy.png")
	_check(not await duel.debug_commit_activate(owner,0,4,false), "Repeated activation cannot bypass exhausted ki")

func _source_flip(owner: int) -> void:
	var enemy := 3-owner
	var board: Array = Rules.empty_board()
	_put(board,4,_card(&"TaiZuChangQuan",owner,&"ally",[9,9,9,9]),owner)
	for cell: int in [1,2]:
		_put(board,cell,_card(&"TaiZuChangQuan",enemy,StringName("target_%d" % cell),[1,1,1,1]),enemy)
	var own_hand := [_card(&"YuDaFeiHua2",owner,&"rain"),_card(&"WuShengWuSe2",owner,&"silent")]
	var other_hand := [_card(&"TaiZuChangQuan",enemy,&"capturer",[9,9,9,9]),_card(&"TaiZuChangQuan",enemy,&"spare")]
	await _load(State.new(board,own_hand if owner == 1 else other_hand,own_hand if owner == 2 else other_hand,owner))
	_check(await duel.debug_commit_move(owner,0,8,false), "Aura source entry commits")
	_check(await duel.debug_commit_move(enemy,0,5,false), "Enemy visibly flips Rain source")
	_check(duel.board_cards[8].owner_id == enemy and duel.board_cards[8].card_data.active_abilities.is_empty(), "Source view is flipped and loses abilities")
	_check(await duel.debug_commit_move(owner,0,7,false), "Later ally enters after source flipped")
	_check(duel.board_cards[1].owner_id == enemy and duel.board_cards[2].owner_id == enemy, "Later ally entry still skips orthogonal attacks under original aura")
	_check(await duel.debug_commit_activate(owner,7,4,false), "Silent's extra activation triggers ally attacks after source flipped")
	_check(duel.board_cards[2].owner_id == owner and duel.board_cards[1].owner_id == enemy, "Existing ally visibly retains diagonal capture after source flips")
	_check(duel.duel_state.owner_auras_by_owner[owner].size() == 1 and (duel.duel_state.owner_auras_by_owner.get(enemy,[]) as Array).is_empty(), "Rendered flow leaves aura with original holder")
