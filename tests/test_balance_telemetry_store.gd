extends SceneTree

const Store = preload("res://scripts/balance_telemetry_store.gd")

var _checks: int = 0
var _failures: int = 0
var _save_path: String = "user://balance_telemetry_store_test.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var store: RefCounted = Store.new(_save_path)
	var initial: Dictionary = store.load_state()
	var anonymous_id: String = store.get_anonymous_player_id()
	_check(store.is_state_valid(initial), "Default telemetry state is valid")
	_check(anonymous_id.begins_with("anon_"), "Default state creates an anonymous identifier")
	_check(
		Store.new(_save_path).get_anonymous_player_id() == anonymous_id,
		"Anonymous identifier survives reload"
	)

	var started: Dictionary = store.start_run(3, &"HuaShanPai", "1.0.1", "Android")
	_check(bool(started.get("ok", false)), "A telemetry run starts")
	_check(store.has_active_run(), "Started telemetry run is active")
	_check(
		not bool(store.begin_duel(&"enemy", 1, 1, [&"A"], _enemy_cards()).get("ok", false)),
		"A duel rejects a main deck that does not contain five cards"
	)

	var abandoned_begin: Dictionary = store.begin_duel(
		&"enemy_abandoned",
		1,
		1,
		_player_cards(),
		_enemy_cards()
	)
	_check(bool(abandoned_begin.get("ok", false)), "A pending duel is recorded")
	_check(
		store.abandon_pending_duel(String(abandoned_begin.get("duel_token", ""))),
		"A pending abandoned duel is cleared"
	)

	var first_begin: Dictionary = store.begin_duel(
		&"dukou_daoshi",
		1,
		2,
		_player_cards(),
		_enemy_cards(),
		false
	)
	var first_token: String = String(first_begin.get("duel_token", ""))
	var first_complete: Dictionary = store.complete_pending_duel(first_token, &"victory")
	_check(bool(first_complete.get("ok", false)), "A completed victory is appended")
	_check(
		not bool(store.complete_pending_duel(first_token, &"victory").get("ok", false)),
		"Completing the same pending duel twice cannot duplicate it"
	)

	var second_begin: Dictionary = store.begin_duel(
		&"qingfeng_xuedi",
		2,
		1,
		_player_cards(),
		_enemy_cards(),
		true
	)
	var second_complete: Dictionary = store.complete_pending_duel(
		String(second_begin.get("duel_token", "")),
		&"defeat"
	)
	_check(bool(second_complete.get("ok", false)), "A completed defeat is appended")

	var sealed: Dictionary = store.seal_completed_run(321)
	_check(bool(sealed.get("ok", false)), "A completed run seals into the upload queue")
	var report := sealed.get("report", {}) as Dictionary
	var duels := report.get("duels", []) as Array
	_check(not store.has_active_run(), "Sealing clears only the active run")
	_check(store.get_pending_reports().size() == 1, "Sealing queues one report")
	_check(
		String(report.get("anonymous_player_id", "")) == anonymous_id
		and int(report.get("difficulty", -1)) == 3
		and String(report.get("sect_id", "")) == "HuaShanPai"
		and int(report.get("final_score", -1)) == 321,
		"Run metadata is preserved"
	)
	_check(
		duels.size() == 2
		and String((duels[0] as Dictionary).get("enemy_id", "")) == "dukou_daoshi"
		and String((duels[0] as Dictionary).get("outcome", "")) == "victory"
		and not bool((duels[0] as Dictionary).get("counts_for_progress", true))
		and String((duels[1] as Dictionary).get("outcome", "")) == "defeat",
		"Completed duels retain order, outcome, and progression scope"
	)
	_check(
		(duels[0] as Dictionary).get("player_card_ids", []) == _strings(_player_cards())
		and (duels[0] as Dictionary).get("enemy_card_ids", []) == _strings(_enemy_cards()),
		"Both ordered five-card main decks are serialized"
	)
	_check(
		int(report.get("victory_count", -1)) == 1
		and int(report.get("defeat_count", -1)) == 1
		and int(report.get("formal_victory_count", -1)) == 0
		and int(report.get("formal_defeat_count", -1)) == 1,
		"Run totals distinguish formal and beginner duels"
	)

	var report_id: String = String(report.get("report_id", ""))
	_check(
		Store.new(_save_path).get_pending_reports().size() == 1,
		"Pending reports survive process-style reload"
	)
	_check(store.record_permanent_error(report_id, "invalid payload"), "Permanent errors are diagnosed")
	_check(store.get_pending_reports().size() == 1, "Permanent errors do not discard reports")
	_check(not store.confirm_report_uploaded("missing"), "Unknown upload acknowledgements change nothing")
	_check(store.confirm_report_uploaded(report_id), "A confirmed upload removes its report")
	_check(store.get_pending_reports().is_empty(), "Confirmed reports leave the queue")
	_check(store.get_anonymous_player_id() == anonymous_id, "Queue changes preserve anonymous identity")

	_check(store.start_run(0, &"HuaShanPai", "1.0.1", "Windows").get("ok", false), "Another run can start")
	_check(store.clear_active_run(), "Reset clears an unfinished run")
	_check(not store.has_active_run(), "Reset leaves no active telemetry run")
	_check(store.get_anonymous_player_id() == anonymous_id, "Reset does not rotate anonymous identity")

	var state_before_corruption: Dictionary = store.load_state()
	_check(store.save_state(state_before_corruption), "A second save creates a recoverable backup")
	var corrupt_file := FileAccess.open(_save_path, FileAccess.WRITE)
	corrupt_file.store_string("not json")
	corrupt_file.close()
	var recovered: Dictionary = Store.new(_save_path).load_state()
	_check(
		Store.new(_save_path).is_state_valid(recovered)
		and String(recovered.get("anonymous_player_id", "")) == anonymous_id,
		"A corrupt primary file recovers the previous valid backup"
	)

	_cleanup()
	_finish()


func _player_cards() -> Array[StringName]:
	return [&"TaiZuChangQuan", &"TuNaShu1", &"CangSongYingKe1", &"ZiXiaGong1", &"YouFenLaiYi1"]


func _enemy_cards() -> Array[StringName]:
	return [&"Enemy1", &"Enemy2", &"Enemy3", &"Enemy4", &"Enemy5"]


func _strings(values: Array) -> Array:
	var result: Array = []
	for value: Variant in values:
		result.append(String(value))
	return result


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = _save_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	if _failures == 0:
		print("BALANCE_TELEMETRY_STORE_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"BALANCE_TELEMETRY_STORE_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
