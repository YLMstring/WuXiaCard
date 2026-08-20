extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Rules = preload("res://scripts/duel_rules.gd")
const TEST_PROFILE_PATH: String = "user://zixia_integration_deck_test.json"

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_test_profile()
	var duel: Node = DUEL_SCENE.instantiate()
	duel.set("deck_profile_path", TEST_PROFILE_PATH)
	duel.set("continue_automatically", false)
	duel.set("opponent_hand_shuffle_seed", -1)
	duel.set("opening_layout_seed", -1)
	duel.set("testing_mode", false)
	root.add_child(duel)
	await process_frame
	await process_frame
	duel.call("debug_set_fast_mode", true)

	var player_ids: Array[StringName] = duel.call(
		"debug_get_hand_instance_ids",
		Rules.PLAYER_OWNER
	)
	var player_id: StringName = player_ids[0]
	var player_card: Node = duel.call("_get_card_view_by_instance", player_id)
	await duel.call(
		"_present_transition_events",
		[
			{
				"type": &"powers_changed",
				"instance_id": player_id,
				"owner_id": Rules.PLAYER_OWNER,
				"powers": [9, 8, 7, 6],
			},
			{
				"type": &"ki_changed",
				"instance_id": player_id,
				"owner_id": Rules.PLAYER_OWNER,
				"previous_ki": 0,
				"ki": 2,
			},
		],
		Rules.PLAYER_OWNER
	)
	_check(
		player_card.get("card_data").get("powers", []) == [9, 8, 7, 6],
		"Controller synchronizes selected hand-card runtime powers"
	)
	_check(
		(player_card.get_node("Overlay/TopPower") as Label).text == "9"
		and (player_card.get_node("Overlay/RightPower") as Label).text == "8"
		and (player_card.get_node("Overlay/BottomPower") as Label).text == "7"
		and (player_card.get_node("Overlay/LeftPower") as Label).text == "6",
		"CardView refreshes all four visible power labels"
	)
	_check(
		int(player_card.get("card_data").get("ki", 0)) == 2,
		"Controller synchronizes selected hand-card runtime ki"
	)

	var opponent_ids: Array[StringName] = duel.call(
		"debug_get_hand_instance_ids",
		Rules.OPPONENT_OWNER
	)
	var opponent_id: StringName = opponent_ids[0]
	var opponent_card: Node = duel.call("_get_card_view_by_instance", opponent_id)
	_check(bool(opponent_card.call("is_face_down")), "Normal opponent hand begins concealed")
	await duel.call(
		"_present_transition_events",
		[{
			"type": &"powers_changed",
			"instance_id": opponent_id,
			"owner_id": Rules.OPPONENT_OWNER,
			"powers": [8, 8, 8, 8],
		}],
		Rules.OPPONENT_OWNER
	)
	_check(
		bool(opponent_card.call("is_face_down"))
		and not (opponent_card.get_node("Overlay/TopPower") as Label).visible,
		"Runtime synchronization does not reveal a face-down opponent card"
	)
	var trace: Array[StringName] = duel.call("debug_get_presentation_trace")
	_check(
		&"powers_changed" in trace and &"ki_changed" in trace,
		"Controller records generic power and ki presentation events"
	)

	duel.queue_free()
	await process_frame
	_cleanup_test_profile()
	if _failures == 0:
		print("ZIXIA_INTEGRATION_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"ZIXIA_INTEGRATION_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _cleanup_test_profile() -> void:
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
