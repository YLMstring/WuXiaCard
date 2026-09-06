extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const CardView = preload("res://scripts/card_view.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")

const TEST_PROFILE_PATH: String = "user://yusui_kungang_integration.json"

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_profile()
	var duel: Node = DUEL_SCENE.instantiate()
	duel.set("deck_profile_path", TEST_PROFILE_PATH)
	duel.set("testing_mode", true)
	duel.set("player_hand_shuffle_seed", -1)
	duel.set("opponent_hand_shuffle_seed", -1)
	duel.set("opening_layout_seed", -1)
	root.add_child(duel)
	await process_frame
	await process_frame
	duel.debug_set_fast_mode(true)
	await _test_same_view_identity_survives_rebirth(duel)
	duel.queue_free()
	await process_frame
	_cleanup_profile()
	if _failures == 0:
		print("YUSUI_KUNGANG_INTEGRATION_PASSED checks=%d" % _checks)
	else:
		push_error(
			"YUSUI_KUNGANG_INTEGRATION_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_same_view_identity_survives_rebirth(duel: Node) -> void:
	var yusui: Dictionary = Catalog.create_instance(
		&"YuSuiKunGang3", Rules.PLAYER_OWNER, &"integration_yusui"
	)
	yusui["powers"] = [1, 1, 1, 1]
	var reply: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"integration_reply"
	)
	var state := State.new(Rules.empty_board(), [yusui], [reply], Rules.PLAYER_OWNER)
	duel.call("_rebuild_views_from_state", state)
	var trace_start: int = (duel.debug_get_presentation_trace() as Array).size()
	var committed: bool = await duel.debug_commit_move(Rules.PLAYER_OWNER, 0, 4, false)
	await process_frame
	var trace: Array = (duel.debug_get_presentation_trace() as Array).slice(trace_start)
	var card: Dictionary = _card_at(duel, 4)
	var view: CardView = _card_view_at(duel, 4)
	_check(committed, "YuSui commits through the production controller")
	_check(StringName(card.get("card_id", &"")) == &"BaGuaFangWei", "Production state contains the transformed Bagua")
	_check(StringName(card.get("instance_id", &"")) == &"integration_yusui", "Production state preserves the exact instance")
	_check(int((duel.duel_state.board[4] as Dictionary).get("owner", 0)) == Rules.OPPONENT_OWNER, "Production state applies enemy ownership")
	_check(view != null, "Reborn Bagua has a live board view")
	_check(view != null and StringName(view.card_data.get("instance_id", &"")) == &"integration_yusui", "Reborn board view matches the preserved identity")
	_check(view != null and StringName(view.card_data.get("card_id", &"")) == &"BaGuaFangWei", "Reborn board view displays Bagua data")
	_check(
		trace.find(&"card_resummon_faded") >= 0
		and trace.find(&"card_summoned") > trace.find(&"card_resummon_faded"),
		"Old YuSui view fades before the transformed Bagua summon"
	)


func _card_at(duel: Node, cell: int) -> Dictionary:
	var value: Variant = duel.duel_state.board[cell]
	return (value as Dictionary).get("card", {}) as Dictionary if value is Dictionary else {}


func _card_view_at(duel: Node, cell: int) -> CardView:
	for child: Node in (duel.board_cells[cell] as Node).get_children():
		if child is CardView:
			return child as CardView
	return null


func _cleanup_profile() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = TEST_PROFILE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
