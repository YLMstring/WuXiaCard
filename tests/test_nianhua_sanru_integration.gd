extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Catalog = preload("res://scripts/card_catalog.gd")
const CardView = preload("res://scripts/card_view.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")

const TEST_PROFILE_PATH: String = "user://nianhua_sanru_integration.json"

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
	await _test_generated_before_summon_self_exile_clears_view(duel)
	duel.queue_free()
	await process_frame
	_cleanup_profile()
	if _failures == 0:
		print("NIANHUA_SANRU_INTEGRATION_PASSED checks=%d" % _checks)
	else:
		push_error(
			"NIANHUA_SANRU_INTEGRATION_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_generated_before_summon_self_exile_clears_view(duel: Node) -> void:
	var sanru: Dictionary = Catalog.create_instance(
		&"SanRuDiYu3", Rules.PLAYER_OWNER, &"integration_sanru"
	)
	var anticipate: Dictionary = Catalog.create_instance(
		&"DuGu9Jian2", Rules.PLAYER_OWNER, &"integration_anticipate"
	)
	var state := State.new(
		Rules.empty_board(),
		[sanru],
		[Catalog.create_instance(
			&"TaiZuChangQuan", Rules.OPPONENT_OWNER, &"integration_reply"
		)],
		Rules.PLAYER_OWNER,
		0,
		[Catalog.create_instance(
			&"TuNaShu1", Rules.PLAYER_OWNER, &"integration_anticipate_draw"
		)]
	)
	state.discard_piles[Rules.PLAYER_OWNER] = [anticipate]
	duel.call("_rebuild_views_from_state", state)
	var trace_start: int = (duel.debug_get_presentation_trace() as Array).size()
	var committed: bool = await duel.debug_commit_move(
		Rules.PLAYER_OWNER,
		0,
		4,
		false
	)
	await process_frame
	var trace: Array = (duel.debug_get_presentation_trace() as Array).slice(trace_start)
	_check(committed, "Sanru commits through the production controller")
	_check(
		duel.duel_state.board[1] == null
		and _removed_has_instance(
			duel.duel_state.removed_cards.get(Rules.PLAYER_OWNER, []) as Array,
			&"integration_anticipate"
		),
		"Anticipate summoned from discard resolves its before-summon self-exile"
	)
	_check(
		not _cell_has_card_instance(duel, 1, &"integration_anticipate"),
		"A generated card exiled before its summon presentation leaves no board view (views=%s)"
		% [_board_view_ids(duel)]
	)
	_check(
		trace.find(&"card_exiled") >= 0
		and trace.find(&"card_summoned") > trace.find(&"card_exiled")
		and trace.find(&"card_self_faded") > trace.find(&"card_summoned"),
		"The deferred self-exile fades the generated view after it appears (trace=%s)"
		% [trace]
	)


func _board_view_ids(duel: Node) -> Array[StringName]:
	var result: Array[StringName] = []
	for cell: int in range(duel.board_cells.size()):
		for child: Node in (duel.board_cells[cell] as Node).get_children():
			if child is CardView:
				result.append(StringName((child.card_data as Dictionary).get("instance_id", &"")))
	return result


func _cell_has_card_instance(duel: Node, cell: int, instance_id: StringName) -> bool:
	for child: Node in (duel.board_cells[cell] as Node).get_children():
		if (
			child is CardView
			and StringName((child.card_data as Dictionary).get("instance_id", &""))
			== instance_id
		):
			return true
	return false


func _removed_has_instance(cards: Array, instance_id: StringName) -> bool:
	for card_value: Variant in cards:
		if (
			card_value is Dictionary
			and StringName((card_value as Dictionary).get("instance_id", &""))
			== instance_id
		):
			return true
	return false


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
