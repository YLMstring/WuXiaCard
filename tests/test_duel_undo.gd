extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const ActionData = preload("res://scripts/duel_action.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const ProfileStore = preload("res://scripts/deck_profile_store.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")

const SAVE_PATH: String = "user://duel_undo_test.json"

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var store: RefCounted = ProfileStore.new(SAVE_PATH)
	var profile: Dictionary = store.create_testing_profile(store.create_default_profile())
	var laihe_library_index: int = (profile["library_slots"] as Array).find("LaiHeQinQuan1")
	_check(laihe_library_index >= 0, "Undo fixture finds LaiHe1 in the testing library")
	if laihe_library_index < 0:
		_finish()
		return
	var displaced_card: String = String((profile["main_deck"] as Array)[0])
	(profile["main_deck"] as Array)[0] = "LaiHeQinQuan1"
	(profile["library_slots"] as Array)[laihe_library_index] = displaced_card
	_check(store.save_profile(profile), "Undo fixture saves a valid LaiHe main deck")

	var duel: DuelController = DUEL_SCENE.instantiate() as DuelController
	duel.deck_profile_path = SAVE_PATH
	duel.testing_mode = true
	duel.starting_owner_id = Rules.PLAYER_OWNER
	duel.player_hand_shuffle_seed = 3109
	duel.opponent_hand_shuffle_seed = 3110
	duel.side_deck_shuffle_seed = 3111
	duel.opening_layout_seed = 3112
	root.add_child(duel)
	await process_frame
	duel.debug_set_fast_mode(true)

	var opening_key: String = StateKey.build(duel.duel_state)
	var opening_card_count: int = duel.debug_get_total_card_count()
	_check(not duel.debug_can_undo_last_player_decision(), "Undo is unavailable before the first player decision")

	var player_action: ActionData = _first_hand_play_excluding(
		duel.duel_state,
		Rules.PLAYER_OWNER,
		&"LaiHeQinQuan1"
	)
	_check(player_action != null, "Undo fixture finds a non-LaiHe player hand play")
	if player_action == null:
		duel.queue_free()
		await process_frame
		_finish()
		return
	_check(
		await duel.debug_commit_move(
			Rules.PLAYER_OWNER,
			player_action.source_index,
			player_action.target_index,
			false
		),
		"Player decision commits before the undo checkpoint"
	)
	_check(not duel.get_mastery_candidate_ids().is_empty(), "Player play records a mastery candidate")

	var opponent_action: ActionData = _first_hand_play(duel.duel_state, Rules.OPPONENT_OWNER)
	_check(opponent_action != null, "Undo fixture finds an opponent response")
	if opponent_action != null:
		_check(
			await duel.debug_commit_move(
				Rules.OPPONENT_OWNER,
				opponent_action.source_index,
				opponent_action.target_index,
				false
			),
			"Opponent response commits after the player decision"
		)
	_check(duel.debug_get_active_owner() == Rules.PLAYER_OWNER, "Opponent response returns control to the player")
	_check(duel.debug_can_undo_last_player_decision(), "LaiHe main-deck metadata enables undo on the next player decision")
	_check(duel.debug_get_replay_action_count() == 2, "Replay records both the player decision and opponent response")

	var replay_button := duel.get_node("DuelCanvas/ReplayButton") as Button
	replay_button.pressed.emit()
	await process_frame
	_check(StateKey.build(duel.duel_state) == opening_key, "Replay button restores the exact state before the player decision")
	_check(duel.debug_get_replay_action_count() == 0, "Undo removes the player decision and opponent response from replay")
	_check(duel.get_mastery_candidate_ids().is_empty(), "Undo restores the mastery candidate list")
	_check(duel.debug_get_total_card_count() == opening_card_count, "Undo rebuild preserves every logical and visual card")
	_check(not duel.debug_can_undo_last_player_decision(), "A successful undo consumes the current checkpoint")

	var restored_key: String = StateKey.build(duel.duel_state)
	replay_button.pressed.emit()
	await process_frame
	_check(StateKey.build(duel.duel_state) == restored_key, "A second press cannot walk farther back without a new player decision")

	duel.queue_free()
	await process_frame
	_cleanup()
	await _test_player_extra_play_keeps_first_checkpoint()
	await _test_opponent_turn_replay_keeps_first_checkpoint()
	_cleanup()
	_finish()


func _test_player_extra_play_keeps_first_checkpoint() -> void:
	_check(_save_testing_profile(true), "Extra-play undo fixture saves a LaiHe main deck")
	var duel: DuelController = await _create_duel()
	_replace_hand_card(duel, Rules.PLAYER_OWNER, 0, &"RanMuDaoFa2")
	_check(
		await duel.debug_commit_move(Rules.PLAYER_OWNER, 0, 4, false),
		"Player places RanMu before the extra-play undo turn"
	)
	var opponent_reply: ActionData = _first_hand_play(duel.duel_state, Rules.OPPONENT_OWNER)
	_check(
		opponent_reply != null
		and await duel.debug_commit_move(
			Rules.OPPONENT_OWNER,
			opponent_reply.source_index,
			opponent_reply.target_index,
			false
		),
		"Opponent returns control before the extra-play undo turn"
	)
	var before_first_decision_key: String = StateKey.build(duel.duel_state)
	_check(
		await duel.debug_commit_activate(
			Rules.PLAYER_OWNER,
			4,
			0,
			false,
			0,
			ActionData.TARGET_HAND_SLOT
		),
		"Player activation grants an extra hand play"
	)
	_check(
		duel.duel_state.active_player == Rules.PLAYER_OWNER
		and duel.duel_state.extra_card_plays_remaining == 1,
		"Granted extra play remains inside the same player turn"
	)
	var extra_play: ActionData = _first_hand_play(duel.duel_state, Rules.PLAYER_OWNER)
	_check(
		extra_play != null
		and await duel.debug_commit_move(
			Rules.PLAYER_OWNER,
			extra_play.source_index,
			extra_play.target_index,
			false
		),
		"Player commits the extra hand play"
	)
	var second_opponent_reply: ActionData = _first_hand_play(
		duel.duel_state,
		Rules.OPPONENT_OWNER
	)
	_check(
		second_opponent_reply != null
		and await duel.debug_commit_move(
			Rules.OPPONENT_OWNER,
			second_opponent_reply.source_index,
			second_opponent_reply.target_index,
			false
		),
		"Opponent responds after the player's extra play"
	)
	_check(
		duel.debug_undo_last_player_decision(),
		"Undo remains available after the complete extra-play turn"
	)
	_check(
		StateKey.build(duel.duel_state) == before_first_decision_key,
		"Undo returns before the player's first decision instead of the extra play"
	)
	duel.queue_free()
	await process_frame
	_cleanup()


func _test_opponent_turn_replay_keeps_first_checkpoint() -> void:
	_check(_save_testing_profile(false), "Opponent replay fixture saves a main deck without LaiHe")
	var duel: DuelController = await _create_duel()
	duel.replay_turn_delay = 0.25
	var memory_emissions: int = 0
	duel.opponent_card_played.connect(func(_glyph: String) -> void: memory_emissions += 1)
	var board: Array = Rules.empty_board()
	board[0] = {
		"owner": Rules.OPPONENT_OWNER,
		"card": Catalog.create_instance(
			&"RanMuDaoFa2",
			Rules.OPPONENT_OWNER,
			&"replay_ranmu"
		),
	}
	var replay_start := State.new(
		board,
		[
			Catalog.create_instance(&"TaiZuChangQuan", Rules.PLAYER_OWNER, &"replay_player_a"),
			Catalog.create_instance(&"TuNaShu1", Rules.PLAYER_OWNER, &"replay_player_b"),
		],
		[
			Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"replay_enemy_a"),
			Catalog.create_instance(&"TuNaShu1", Rules.OPPONENT_OWNER, &"replay_enemy_b"),
		],
		Rules.PLAYER_OWNER,
		1,
		[],
		[Catalog.create_instance(&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"replay_draw")]
	)
	duel.call("_rebuild_views_from_state", replay_start)
	var replay_record: RefCounted = duel.get("_replay_record")
	replay_record.call("begin", replay_start)
	_check(
		await duel.debug_commit_move(Rules.PLAYER_OWNER, 0, 8, false),
		"Player opens the opponent replay fixture"
	)
	var before_opponent_turn_key: String = StateKey.build(duel.duel_state)
	_check(
		await duel.debug_commit_activate(
			Rules.OPPONENT_OWNER,
			0,
			0,
			false,
			0,
			ActionData.TARGET_HAND_SLOT
		),
		"Opponent activation grants its extra hand play"
	)
	var opponent_extra_play: ActionData = _first_hand_play(
		duel.duel_state,
		Rules.OPPONENT_OWNER
	)
	_check(
		opponent_extra_play != null
		and await duel.debug_commit_move(
			Rules.OPPONENT_OWNER,
			opponent_extra_play.source_index,
			opponent_extra_play.target_index,
			false
		),
		"Opponent commits its recorded extra play"
	)
	var after_opponent_turn_key: String = StateKey.build(duel.duel_state)
	var replay_action_count: int = duel.debug_get_replay_action_count()
	var memory_emissions_before_replay: int = memory_emissions
	_check(
		duel.debug_can_replay_last_opponent_turn(),
		"The complete opponent turn is available for live replay"
	)
	duel.set("_undo_last_player_decision_enabled", true)
	duel.set("_undo_checkpoint_state", null)
	var replay_button := duel.get_node("DuelCanvas/ReplayButton") as Button
	replay_button.pressed.emit()
	await process_frame
	_check(duel.debug_is_replaying_opponent_turn(), "Unavailable undo falls back to opponent replay")
	_check(
		String(duel.get_node("DuelCanvas/TurnStatus").text) == "回放中...",
		"Opponent replay wait uses the dedicated status text"
	)
	_check(
		StateKey.build(duel.duel_state) == before_opponent_turn_key,
		"Opponent replay waits from the first decision checkpoint"
	)
	while duel.debug_is_replaying_opponent_turn():
		await process_frame
	_check(
		StateKey.build(duel.duel_state) == after_opponent_turn_key,
		"Opponent replay reproduces the exact final duel state"
	)
	_check(
		duel.debug_get_replay_action_count() == replay_action_count,
		"Opponent replay replaces rather than duplicates the recorded actions"
	)
	_check(
		memory_emissions == memory_emissions_before_replay,
		"Opponent replay does not repeat persistent enemy-memory side effects"
	)
	duel.queue_free()
	await process_frame
	_cleanup()


func _create_duel() -> DuelController:
	var duel: DuelController = DUEL_SCENE.instantiate() as DuelController
	duel.deck_profile_path = SAVE_PATH
	duel.testing_mode = true
	duel.starting_owner_id = Rules.PLAYER_OWNER
	duel.player_hand_shuffle_seed = 3109
	duel.opponent_hand_shuffle_seed = 3110
	duel.side_deck_shuffle_seed = 3111
	duel.opening_layout_seed = 3112
	root.add_child(duel)
	await process_frame
	duel.debug_set_fast_mode(true)
	return duel


func _save_testing_profile(with_laihe: bool) -> bool:
	var store: RefCounted = ProfileStore.new(SAVE_PATH)
	var profile: Dictionary = store.create_testing_profile(store.create_default_profile())
	if with_laihe:
		var laihe_library_index: int = (profile["library_slots"] as Array).find("LaiHeQinQuan1")
		if laihe_library_index < 0:
			return false
		var displaced_card: String = String((profile["main_deck"] as Array)[0])
		(profile["main_deck"] as Array)[0] = "LaiHeQinQuan1"
		(profile["library_slots"] as Array)[laihe_library_index] = displaced_card
	return store.save_profile(profile)


func _replace_hand_card(
	duel: DuelController,
	owner_id: int,
	hand_index: int,
	card_id: StringName
) -> void:
	var instance_id: StringName = duel.debug_get_hand_instance_ids(owner_id)[hand_index]
	var replacement: Dictionary = Catalog.create_instance(card_id, owner_id, instance_id)
	duel.duel_state.get_hand(owner_id)[hand_index] = replacement
	var card_view: Node = duel._get_card_view_for_logical_index(owner_id, hand_index)
	card_view.sync_runtime_data(replacement, owner_id)


func _first_hand_play_excluding(state, owner_id: int, excluded_card_id: StringName) -> ActionData:
	for action: ActionData in Simulator.get_legal_actions_for_owner(state, owner_id):
		if action.action_type != ActionData.TYPE_PLAY:
			continue
		var hand: Array = state.get_hand(owner_id)
		if action.source_index < 0 or action.source_index >= hand.size():
			continue
		if StringName((hand[action.source_index] as Dictionary).get("card_id", &"")) != excluded_card_id:
			return action
	return null


func _first_hand_play(state, owner_id: int) -> ActionData:
	for action: ActionData in Simulator.get_legal_actions_for_owner(state, owner_id):
		if action.action_type == ActionData.TYPE_PLAY:
			return action
	return null


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	if _failures == 0:
		print("DUEL_UNDO_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("DUEL_UNDO_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
