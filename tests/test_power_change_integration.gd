extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Rules = preload("res://scripts/duel_rules.gd")
const TEST_PROFILE_PATH: String = "user://power_change_integration_test.json"

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
	duel.set("testing_mode", false)
	root.add_child(duel)
	await process_frame
	await process_frame
	duel.call("debug_set_fast_mode", true)
	duel.set("power_change_duration", 0.04)

	var player_ids: Array[StringName] = duel.call("debug_get_hand_instance_ids", Rules.PLAYER_OWNER)
	var first_id: StringName = player_ids[0]
	var second_id: StringName = player_ids[1]
	var first_card: Node = duel.call("_get_card_view_by_instance", first_id)
	var second_card: Node = duel.call("_get_card_view_by_instance", second_id)
	var first_previous: Array = (first_card.get("card_data") as Dictionary).get("powers", []).duplicate()
	var second_previous: Array = (second_card.get("card_data") as Dictionary).get("powers", []).duplicate()
	var first_final: Array = _offset(first_previous, 1)
	var second_final: Array = _offset(second_previous, 1)
	var started_msec: int = Time.get_ticks_msec()
	await duel.call(
		"_present_transition_events",
		[
			_power_event(first_id, first_previous, first_final, 1, &"parallel_batch"),
			_power_event(second_id, second_previous, second_final, 1, &"parallel_batch"),
		],
		Rules.PLAYER_OWNER
	)
	var elapsed_msec: int = Time.get_ticks_msec() - started_msec
	_check(elapsed_msec < 100, "Two visible cards share one animation barrier")
	_check(
		(first_card.get("card_data") as Dictionary).get("powers", []) == first_final
		and (second_card.get("card_data") as Dictionary).get("powers", []) == second_final,
		"One batch synchronizes all four final values on both cards; got %s / %s"
		% [
			(first_card.get("card_data") as Dictionary).get("powers", []),
			(second_card.get("card_data") as Dictionary).get("powers", []),
		]
	)
	var trace: Array[Dictionary] = duel.call("debug_get_power_change_presentation_trace")
	_check(trace.size() == 2, "A two-card batch starts two visible animations")
	_check(
		int(trace[0].get("started_msec", -1)) == int(trace[1].get("started_msec", -2)),
		"All visible animations in one batch receive the same start timestamp"
	)
	_check(
		(trace[0].get("glow_color") as Color).is_equal_approx(duel.get("power_gain_glow_color") as Color),
		"Positive batches use the restrained warm gain glow"
	)

	var repeated_previous: Array = first_final.duplicate()
	var repeated_middle: Array = _offset(repeated_previous, 2)
	var repeated_final: Array = _offset(repeated_middle, -1)
	await duel.call(
		"_present_transition_events",
		[
			_power_event(first_id, repeated_previous, repeated_middle, 2, &"repeat_batch"),
			_power_event(first_id, repeated_middle, repeated_final, -1, &"repeat_batch"),
		],
		Rules.PLAYER_OWNER
	)
	trace = duel.call("debug_get_power_change_presentation_trace")
	_check(trace.size() == 3, "Repeated logical changes on one card coalesce to one visual animation")
	var repeated_trace: Dictionary = trace[-1]
	_check(
		repeated_trace.get("previous_powers", []) == repeated_previous
		and repeated_trace.get("powers", []) == repeated_final,
		"Coalescing uses earliest previous and latest final powers"
	)

	var opponent_ids: Array[StringName] = duel.call("debug_get_hand_instance_ids", Rules.OPPONENT_OWNER)
	var hidden_id: StringName = opponent_ids[0]
	var hidden_card: Node = duel.call("_get_card_view_by_instance", hidden_id)
	var hidden_previous: Array = (hidden_card.get("card_data") as Dictionary).get("powers", []).duplicate()
	var hidden_final: Array = _offset(hidden_previous, -1)
	duel.set("power_change_duration", 0.20)
	started_msec = Time.get_ticks_msec()
	await duel.call(
		"_present_transition_events",
		[_power_event(hidden_id, hidden_previous, hidden_final, -1, &"hidden_batch")],
		Rules.OPPONENT_OWNER
	)
	elapsed_msec = Time.get_ticks_msec() - started_msec
	trace = duel.call("debug_get_power_change_presentation_trace")
	_check(elapsed_msec < 80, "A fully hidden batch adds no empty animation wait")
	_check(trace.size() == 3, "A face-down opponent card emits no visible animation trace")
	_check(
		bool(hidden_card.call("is_face_down"))
		and (hidden_card.get("card_data") as Dictionary).get("powers", []) == hidden_final,
		"Hidden power changes synchronize data without revealing metadata"
	)

	duel.set("power_change_duration", 0.04)
	var zero_powers: Array = [0, 0, 0, 0]
	started_msec = Time.get_ticks_msec()
	await duel.call(
		"_present_transition_events",
		[
			_power_event(first_id, repeated_final, zero_powers, -9, &"lethal_batch"),
			{
				"type": &"card_exiled",
				"instance_id": first_id,
				"target_cell": -1,
				"zone": &"hand",
				"logical_index": 0,
				"self_removal": false,
				"power_change_batch_id": &"lethal_batch",
			},
		],
		Rules.PLAYER_OWNER
	)
	elapsed_msec = Time.get_ticks_msec() - started_msec
	await process_frame
	var presentation_trace: Array[StringName] = duel.call("debug_get_presentation_trace")
	trace = duel.call("debug_get_power_change_presentation_trace")
	_check(elapsed_msec >= 30, "A lethal card waits for the shared power animation barrier")
	_check(not is_instance_valid(first_card), "A hand card is removed only after its lethal power animation")
	_check(
		presentation_trace.size() >= 2
		and presentation_trace[presentation_trace.size() - 2] == &"powers_changed"
		and presentation_trace[presentation_trace.size() - 1] == &"card_exiled",
		"Lethal presentation preserves power-before-exile ordering"
	)
	_check(
		(trace[-1].get("glow_color") as Color).is_equal_approx(duel.get("power_loss_glow_color") as Color),
		"Negative batches use the dark red loss glow"
	)

	duel.queue_free()
	await process_frame
	_cleanup_test_profile()
	if _failures == 0:
		print("POWER_CHANGE_INTEGRATION_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"POWER_CHANGE_INTEGRATION_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _power_event(
	instance_id: StringName,
	previous_powers: Array,
	resulting_powers: Array,
	amount: int,
	batch_id: StringName
) -> Dictionary:
	return {
		"type": &"powers_changed",
		"instance_id": instance_id,
		"previous_powers": previous_powers.duplicate(),
		"powers": resulting_powers.duplicate(),
		"amount": amount,
		"power_change_batch_id": batch_id,
	}


func _offset(powers: Array, amount: int) -> Array:
	var result: Array = []
	for value: Variant in powers:
		result.append(maxi(0, int(value) + amount))
	return result


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
