extends SceneTree

const Store = preload("res://scripts/deck_profile_store.gd")

var _checks: int = 0
var _failures: int = 0
var _save_path: String = "user://ending_profile_test.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var store: RefCounted = Store.new(_save_path)
	var profile: Dictionary = store.create_default_profile()
	_check(int(profile["effective_duel_count"]) == 0, "New profiles begin with zero effective duels")
	_check((profile["defeated_enemy_ids"] as Array).is_empty(), "New profiles begin with no defeated enemies")
	_check((profile["best_scores_by_sect"] as Dictionary).is_empty(), "New profiles begin with no ending achievements")

	var begin: Dictionary = store.begin_run_and_save(
		profile,
		&"xuanyue_jianzong",
		[],
		&"qingfeng_xuedi"
	)
	_check(bool(begin.get("ok", false)), "Ending fixture begins a run")
	var active: Dictionary = begin.get("profile", {})
	var defeat: Dictionary = store.record_completed_duel_and_save(
		active,
		Store.REWARD_DEFEAT,
		2
	)
	_check(bool(defeat.get("ok", false)), "A completed defeat saves")
	_check(not bool(defeat.get("completed", true)), "A defeat never completes the run")
	var after_defeat: Dictionary = defeat.get("profile", {})
	_check(int(after_defeat["effective_duel_count"]) == 1, "Defeat increments effective duels")
	_check((after_defeat["defeated_enemy_ids"] as Array).is_empty(), "Defeat records no defeated enemy")
	_check(int(after_defeat["level"]) == 1, "Defeat preserves the player level")
	_check(String(after_defeat["current_enemy_id"]) == "qingfeng_xuedi", "Defeat preserves the rematch enemy")

	var ordinary_win: Dictionary = store.record_completed_duel_and_save(
		after_defeat,
		Store.REWARD_VICTORY,
		2,
		&"tieshan_menren"
	)
	_check(bool(ordinary_win.get("ok", false)), "A non-final victory saves")
	_check(not bool(ordinary_win.get("completed", true)), "First of two victories does not finish")
	_check(bool(ordinary_win.get("advanced", false)), "A non-final victory advances progression")
	var advanced: Dictionary = ordinary_win.get("profile", {})
	_check(int(advanced["effective_duel_count"]) == 2, "Victory increments effective duels")
	_check((advanced["defeated_enemy_ids"] as Array) == ["qingfeng_xuedi"], "Victory appends the defeated enemy")
	_check(int(advanced["level"]) == 2, "Non-final victory advances one level")
	_check(String(advanced["current_enemy_id"]) == "tieshan_menren", "Non-final victory selects the requested next enemy")

	var unlocked_before: Array = (advanced["unlocked_card_ids"] as Array).duplicate()
	var final_win: Dictionary = store.record_completed_duel_and_save(
		advanced,
		Store.REWARD_VICTORY,
		2
	)
	_check(bool(final_win.get("ok", false)), "The final victory saves")
	_check(bool(final_win.get("completed", false)), "The configured victory target completes the run")
	_check(not bool(final_win.get("advanced", true)), "Final victory does not select another enemy")
	var summary: Dictionary = final_win.get("ending_summary", {})
	_check(String(summary.get("sect_id", "")) == "xuanyue_jianzong", "Ending summary records the selected sect")
	_check(int(summary.get("effective_duel_count", 0)) == 3, "Ending summary records every effective duel")
	_check((summary.get("defeated_enemy_ids", []) as Array) == ["qingfeng_xuedi", "tieshan_menren"], "Ending summary preserves defeated enemies chronologically")
	_check(int(summary.get("score", -1)) == 5000, "Ending score floors 15000 divided by effective duels")
	_check(not bool(summary.get("flawless", true)), "A run containing a loss is not flawless")
	var completed_profile: Dictionary = final_win.get("profile", {})
	_check(not bool(completed_profile["run_active"]), "Completion closes the active run")
	_check((completed_profile["main_deck"] as Array) == _strings(Store.DEFAULT_MAIN_DECK_IDS), "Completion restores the default deck")
	_check(completed_profile["unlocked_card_ids"] == unlocked_before, "Completion preserves card unlocks")
	_check(int((completed_profile["best_scores_by_sect"] as Dictionary)["xuanyue_jianzong"]) == 5000, "Completion stores the sect's first best score")
	_check(int(completed_profile["effective_duel_count"]) == 0, "Closed run clears its duel counter")
	_check((completed_profile["defeated_enemy_ids"] as Array).is_empty(), "Closed run clears its defeated-enemy history")

	var flawless_begin: Dictionary = store.begin_run_and_save(
		completed_profile,
		&"xuanyue_jianzong",
		[],
		&"qingfeng_xuedi"
	)
	var flawless_finish: Dictionary = store.record_completed_duel_and_save(
		flawless_begin.get("profile", {}),
		Store.REWARD_VICTORY,
		1
	)
	var flawless_summary: Dictionary = flawless_finish.get("ending_summary", {})
	_check(bool(flawless_summary.get("flawless", false)), "A victory-only run is flawless")
	_check(int(flawless_summary.get("score", -1)) == 15000, "One effective duel earns 15000 points")
	var best_profile: Dictionary = flawless_finish.get("profile", {})
	_check(int((best_profile["best_scores_by_sect"] as Dictionary)["xuanyue_jianzong"]) == 15000, "A higher score replaces the previous sect best")

	var lower_begin: Dictionary = store.begin_run_and_save(
		best_profile,
		&"xuanyue_jianzong",
		[],
		&"qingfeng_xuedi"
	)
	var lower_profile: Dictionary = lower_begin.get("profile", {})
	for ignored: int in range(2):
		lower_profile = store.record_completed_duel_and_save(
			lower_profile,
			Store.REWARD_DEFEAT,
			1
		).get("profile", lower_profile)
	var lower_finish: Dictionary = store.record_completed_duel_and_save(
		lower_profile,
		Store.REWARD_VICTORY,
		1
	)
	_check(int((lower_finish["profile"]["best_scores_by_sect"] as Dictionary)["xuanyue_jianzong"]) == 15000, "A lower result never replaces the sect best")

	var reset_begin: Dictionary = store.begin_run_and_save(
		lower_finish.get("profile", {}),
		&"xuanyue_jianzong",
		[],
		&"qingfeng_xuedi"
	)
	var run_reset: Dictionary = store.reset_run_and_save(reset_begin.get("profile", {}))
	_check(int((run_reset["profile"]["best_scores_by_sect"] as Dictionary)["xuanyue_jianzong"]) == 15000, "Run reset preserves ending achievements")
	var full_reset: Dictionary = store.reset_all_progress_and_save(run_reset.get("profile", {}))
	_check((full_reset["profile"]["best_scores_by_sect"] as Dictionary).is_empty(), "Full reset clears ending achievements")

	var legacy_active: Dictionary = active.duplicate(true)
	legacy_active["schema_version"] = 6
	legacy_active.erase("effective_duel_count")
	legacy_active.erase("defeated_enemy_ids")
	legacy_active.erase("best_scores_by_sect")
	legacy_active["main_deck"] = ["gate_general", "meng_huo", "jiang_wei", "fa_zheng", "fire_envoy"]
	var migrated: Dictionary = store.repair_profile(legacy_active)
	_check(store.is_profile_valid(migrated), "A legacy active profile migrates to the new schema")
	_check(not bool(migrated["run_active"]), "Legacy migration closes an unreconstructable active run")
	_check((migrated["main_deck"] as Array) == _strings(Store.DEFAULT_MAIN_DECK_IDS), "Legacy active-run migration restores the default deck")
	_check(migrated["unlocked_card_ids"] == legacy_active["unlocked_card_ids"], "Legacy migration preserves unlocks")
	_check((migrated["best_scores_by_sect"] as Dictionary).is_empty(), "Legacy migration starts with empty achievements")

	var invalid_outcome: Dictionary = store.record_completed_duel_and_save(active, &"abandoned", 2)
	_check(not bool(invalid_outcome.get("ok", true)), "The completed-duel transaction rejects abandon")
	var invalid_target: Dictionary = store.record_completed_duel_and_save(active, Store.REWARD_VICTORY, 0)
	_check(not bool(invalid_target.get("ok", true)), "The completed-duel transaction rejects an invalid victory target")

	_cleanup()
	_finish()


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = _save_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _strings(values: Array) -> Array:
	var result: Array = []
	for value: Variant in values:
		result.append(String(value))
	return result


func _finish() -> void:
	if _failures == 0:
		print("ENDING_PROFILE_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("ENDING_PROFILE_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
