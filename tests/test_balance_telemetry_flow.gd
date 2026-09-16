extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://main.tscn")
const ProfileStore = preload("res://scripts/deck_profile_store.gd")
const MenuController = preload("res://scripts/main_menu_controller.gd")
const SelectorController = preload("res://scripts/sect_selection_controller.gd")

var _checks: int = 0
var _failures: int = 0
var _profile_path: String = "user://balance_telemetry_flow_profile_test.json"
var _telemetry_path: String = "user://balance_telemetry_flow_test.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var profile_store := ProfileStore.new(_profile_path)
	var profile: Dictionary = profile_store.create_default_profile()
	(profile["unlocked_sect_ids"] as Array).append("TaiShanPai")
	_check(profile_store.save_profile(profile), "Normal-mode telemetry fixture saves")

	var flow: Variant = MAIN_SCENE.instantiate()
	flow.deck_profile_path = _profile_path
	flow.balance_telemetry_path = _telemetry_path
	flow.telemetry_force_local_capture_for_tests = true
	flow.testing_mode = false
	flow.victories_required = 1
	root.add_child(flow)
	await process_frame
	var menu := flow.debug_get_current_screen() as MenuController
	(menu.get_node("MenuLayer/Actions/JourneyButton") as Button).pressed.emit()
	await process_frame
	var selector := flow.debug_get_current_screen() as SelectorController
	_check(selector != null, "Fixture reaches sect selection")
	_check(selector.debug_select_sect(&"TaiShanPai"), "Fixture selects Taishan")
	_check(selector.debug_confirm_selected_sect(), "Sect confirmation starts a new run")
	await process_frame
	var telemetry_state: Dictionary = flow.debug_get_balance_telemetry_state()
	_check(
		not (telemetry_state.get("active_run", {}) as Dictionary).is_empty(),
		"A newly selected run starts telemetry"
	)

	flow.call("_show_duel", 1)
	await process_frame
	telemetry_state = flow.debug_get_balance_telemetry_state()
	var active_run := telemetry_state.get("active_run", {}) as Dictionary
	var pending_duel := active_run.get("pending_duel", {}) as Dictionary
	_check(String(pending_duel.get("enemy_id", "")) != "", "Duel capture records the stable enemy ID")
	_check(
		(pending_duel.get("player_card_ids", []) as Array).size() == 5
		and (pending_duel.get("enemy_card_ids", []) as Array).size() == 5,
		"Duel capture records both five-card opening main decks"
	)
	flow.call("_on_duel_return_requested", &"abandoned")
	await process_frame
	telemetry_state = flow.debug_get_balance_telemetry_state()
	active_run = telemetry_state.get("active_run", {}) as Dictionary
	_check(
		(active_run.get("duels", []) as Array).is_empty()
		and (active_run.get("pending_duel", {}) as Dictionary).is_empty(),
		"Abandoning a duel records no result"
	)

	flow.call("_show_duel", 2)
	await process_frame
	flow.call("_on_duel_return_requested", &"victory")
	await process_frame
	telemetry_state = flow.debug_get_balance_telemetry_state()
	var reports := telemetry_state.get("pending_reports", []) as Array
	_check(reports.size() == 1, "Completing the run queues one report")
	if reports.size() == 1:
		var report := reports[0] as Dictionary
		var duels := report.get("duels", []) as Array
		_check(
			String(report.get("sect_id", "")) == "TaiShanPai"
			and int(report.get("difficulty", -1)) == 0
			and int(report.get("final_score", -1)) == 500,
			"Queued report preserves run metadata and final score"
		)
		_check(
			duels.size() == 1
			and int((duels[0] as Dictionary).get("starting_owner", 0)) == 2
			and String((duels[0] as Dictionary).get("outcome", "")) == "victory",
			"Queued report preserves starting side and result"
		)

	flow.call(
		"_queue_beginner_flow_completed_event_if_needed",
		ProfileStore.BEGINNER_OPENING_LINGHU,
		profile_store.load_profile(),
		&"victory"
	)
	_check(
		(flow.debug_get_balance_telemetry_state().get("pending_events", []) as Array).is_empty(),
		"The first tutorial victory does not record completion"
	)
	flow.call(
		"_queue_beginner_flow_completed_event_if_needed",
		ProfileStore.BEGINNER_OPENING_WUSHI,
		profile_store.load_profile(),
		&"victory"
	)
	var events := flow.debug_get_balance_telemetry_state().get("pending_events", []) as Array
	_check(
		events.size() == 1
		and String((events[0] as Dictionary).get("event_type", ""))
			== "beginner_flow_completed",
		"The Wushi victory queues the installation-level completion event"
	)
	flow.call(
		"_queue_beginner_flow_completed_event_if_needed",
		ProfileStore.BEGINNER_OPENING_WUSHI,
		profile_store.load_profile(),
		&"victory"
	)
	_check(
		(flow.debug_get_balance_telemetry_state().get("pending_events", []) as Array).size() == 1,
		"Repeating the completion transition cannot duplicate the event"
	)
	flow.queue_free()
	await process_frame
	await process_frame
	await process_frame

	_cleanup()
	_finish()


func _cleanup() -> void:
	for base_path: String in [_profile_path, _telemetry_path]:
		for suffix: String in ["", ".tmp", ".bak"]:
			var path: String = base_path + suffix
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	if _failures == 0:
		print("BALANCE_TELEMETRY_FLOW_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"BALANCE_TELEMETRY_FLOW_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
