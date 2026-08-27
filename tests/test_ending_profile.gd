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
	_check((profile["mastered_card_ids"] as Array).is_empty(), "New profiles begin with no card mastery")
	profile["max_unlocked_difficulty"] = 2
	profile["last_selected_difficulty"] = 2
	_check(store.is_profile_valid(profile), "Difficulty-two ending fixture is valid")

	var begin: Dictionary = store.begin_run_and_save(
		profile,
		&"HuaShanPai",
		[],
		&"qingfeng_xuedi",
		null,
		false,
		2
	)
	_check(bool(begin.get("ok", false)), "Ending fixture begins a run")
	var active: Dictionary = begin.get("profile", {})
	_check(store.get_run_difficulty(active) == 2, "Ending fixture begins at difficulty two")
	var active_deck_ids: Array[StringName] = store.get_main_deck_ids(active)
	active["mastered_card_ids"] = [String(active_deck_ids[0])]
	_check(store.is_profile_valid(active), "Mastery fixture remains a valid active profile")
	var defeat: Dictionary = store.record_completed_duel_and_save(
		active,
		Store.REWARD_DEFEAT,
		2,
		&"",
		[active_deck_ids[1]]
	)
	_check(bool(defeat.get("ok", false)), "A completed defeat saves")
	_check(not bool(defeat.get("completed", true)), "A defeat never completes the run")
	var after_defeat: Dictionary = defeat.get("profile", {})
	_check(int(after_defeat["effective_duel_count"]) == 1, "Defeat increments effective duels")
	_check((after_defeat["defeated_enemy_ids"] as Array).is_empty(), "Defeat records no defeated enemy")
	_check(int(after_defeat["level"]) == 1, "Defeat preserves the player level")
	_check(String(after_defeat["current_enemy_id"]) == "qingfeng_xuedi", "Defeat preserves the rematch enemy")
	_check(store.get_run_difficulty(after_defeat) == 2, "Defeat preserves the active run difficulty")
	_check(
		store.get_mastered_card_ids(after_defeat) == [active_deck_ids[0]],
		"Defeat ignores mastery candidates"
	)

	var ordinary_win: Dictionary = store.record_completed_duel_and_save(
		after_defeat,
		Store.REWARD_VICTORY,
		2,
		&"tieshan_menren",
		[active_deck_ids[1], &"missing_card", active_deck_ids[2], active_deck_ids[1]]
	)
	_check(bool(ordinary_win.get("ok", false)), "A non-final victory saves")
	_check(not bool(ordinary_win.get("completed", true)), "First of two victories does not finish")
	_check(bool(ordinary_win.get("advanced", false)), "A non-final victory advances progression")
	var advanced: Dictionary = ordinary_win.get("profile", {})
	_check(int(advanced["effective_duel_count"]) == 2, "Victory increments effective duels")
	_check((advanced["defeated_enemy_ids"] as Array) == ["qingfeng_xuedi"], "Victory appends the defeated enemy")
	_check(int(advanced["level"]) == 2, "Non-final victory advances one level")
	_check(String(advanced["current_enemy_id"]) == "tieshan_menren", "Non-final victory selects the requested next enemy")
	_check(store.get_run_difficulty(advanced) == 2, "A non-final victory preserves run difficulty")
	_check(
		store.get_mastered_card_ids(advanced)
		== [active_deck_ids[0], active_deck_ids[1], active_deck_ids[2]],
		"Victory appends valid main-deck mastery candidates in stable order"
	)

	advanced["level"] = 7
	advanced["current_enemy_id"] = "hanyue_nvxia"
	_check(store.is_profile_valid(advanced), "Final-win fixture can use an enemy that unlocks a sect")
	var final_win: Dictionary = store.record_completed_duel_and_save(
		advanced,
		Store.REWARD_VICTORY,
		2,
		&"",
		[active_deck_ids[3]]
	)
	_check(bool(final_win.get("ok", false)), "The final victory saves")
	_check(bool(final_win.get("completed", false)), "The configured victory target completes the run")
	_check(not bool(final_win.get("advanced", true)), "Final victory does not select another enemy")
	var summary: Dictionary = final_win.get("ending_summary", {})
	_check(String(summary.get("sect_id", "")) == "HuaShanPai", "Ending summary records the selected sect")
	_check(int(summary.get("effective_duel_count", 0)) == 3, "Ending summary records every effective duel")
	_check((summary.get("defeated_enemy_ids", []) as Array) == ["qingfeng_xuedi", "hanyue_nvxia"], "Ending summary preserves defeated enemies chronologically")
	_check(int(summary.get("score", -1)) == 5000, "Ending score floors 15000 divided by effective duels")
	_check(not bool(summary.get("flawless", true)), "A run containing a loss is not flawless")
	var completed_profile: Dictionary = final_win.get("profile", {})
	_check(not bool(completed_profile["run_active"]), "Completion closes the active run")
	_check((completed_profile["main_deck"] as Array) == _strings(Store.DEFAULT_MAIN_DECK_IDS), "Completion restores the default deck")
	_check(
		store.get_unlocked_ids(completed_profile) == Store.DEFAULT_MAIN_DECK_IDS,
		"Completion clears card unlocks except the two base cards"
	)
	_check(
		completed_profile["library_slots"] == store.create_default_profile()["library_slots"],
		"Completion clears the library"
	)
	_check(
		&"tingchao_gu" in store.get_unlocked_sect_ids(completed_profile),
		"Completion preserves the sect unlocked by the final enemy"
	)
	_check(
		store.get_mastered_card_ids(completed_profile)
		== [active_deck_ids[0], active_deck_ids[1], active_deck_ids[2], active_deck_ids[3]],
		"Final victory records mastery before closing the run"
	)
	_check(
		store.get_best_score(completed_profile, &"HuaShanPai", 0) == 500
		and store.get_best_score(completed_profile, &"HuaShanPai", 1) == 500
		and store.get_best_score(completed_profile, &"HuaShanPai", 2) == 5000
		and store.get_best_score(completed_profile, &"HuaShanPai", 3) == 0,
		"Difficulty-two completion records its score downward with low-difficulty caps"
	)
	_check(int(completed_profile["effective_duel_count"]) == 0, "Closed run clears its duel counter")
	_check((completed_profile["defeated_enemy_ids"] as Array).is_empty(), "Closed run clears its defeated-enemy history")
	_check(
		store.get_max_unlocked_difficulty(completed_profile) == 3,
		"Completing difficulty two unlocks difficulty three"
	)
	_check(
		store.get_last_selected_difficulty(completed_profile) == 2,
		"Completion preserves the last selected difficulty"
	)
	_check(store.get_run_difficulty(completed_profile) == 0, "Completion clears active run difficulty")

	var flawless_begin: Dictionary = store.begin_run_and_save(
		completed_profile,
		&"HuaShanPai",
		[],
		&"qingfeng_xuedi",
		null,
		false,
		2
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
	_check(
		store.get_best_score(best_profile, &"HuaShanPai", 0) == 500
		and store.get_best_score(best_profile, &"HuaShanPai", 1) == 500
		and store.get_best_score(best_profile, &"HuaShanPai", 2) == 15000,
		"A higher difficulty-two score replaces only its uncapped best and keeps low caps"
	)

	var lower_begin: Dictionary = store.begin_run_and_save(
		best_profile,
		&"HuaShanPai",
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
	_check(
		int((lower_finish.get("ending_summary", {}) as Dictionary).get("score", -1)) == 500
		and store.get_best_score(lower_finish.get("profile", {}), &"HuaShanPai", 0) == 500
		and store.get_best_score(lower_finish.get("profile", {}), &"HuaShanPai", 2) == 15000,
		"Difficulty-zero score caps at 500 and never replaces a higher difficulty best"
	)

	var difficulty_one_begin: Dictionary = store.begin_run_and_save(
		lower_finish.get("profile", {}),
		&"HuaShanPai",
		[],
		&"qingfeng_xuedi",
		null,
		false,
		1
	)
	var difficulty_one_finish: Dictionary = store.record_completed_duel_and_save(
		difficulty_one_begin.get("profile", {}),
		Store.REWARD_VICTORY,
		1
	)
	_check(
		int((difficulty_one_finish.get("ending_summary", {}) as Dictionary).get("score", -1))
		== 500
		and store.get_best_score(
			difficulty_one_finish.get("profile", {}),
			&"HuaShanPai",
			1
		) == 500
		and store.get_best_score(
			difficulty_one_finish.get("profile", {}),
			&"HuaShanPai",
			2
		) == 15000,
		"Difficulty-one final score caps at 500 without changing higher difficulty scores"
	)
	var isolation_source: Dictionary = (
		difficulty_one_finish.get("profile", {}) as Dictionary
	).duplicate(true)
	(isolation_source["unlocked_sect_ids"] as Array).append("TaiShanPai")
	var isolation_scores: Dictionary = isolation_source["best_scores_by_sect"] as Dictionary
	var isolation_huashan_scores: Dictionary = (
		isolation_scores["HuaShanPai"] as Dictionary
	).duplicate(true)
	isolation_huashan_scores["2"] = 12000
	isolation_scores["HuaShanPai"] = isolation_huashan_scores
	isolation_source["best_scores_by_sect"] = isolation_scores
	_check(store.is_profile_valid(isolation_source), "Per-sect score isolation fixture is valid")
	var isolation_begin: Dictionary = store.begin_run_and_save(
		isolation_source,
		&"TaiShanPai",
		[],
		&"qingfeng_xuedi",
		null,
		false,
		2
	)
	var isolation_finish: Dictionary = store.record_completed_duel_and_save(
		isolation_begin.get("profile", {}),
		Store.REWARD_VICTORY,
		1
	)
	_check(
		store.get_best_score(isolation_finish.get("profile", {}), &"TaiShanPai", 2)
		== 15000
		and store.get_best_score(
			isolation_finish.get("profile", {}),
			&"HuaShanPai",
			2
		) == 12000,
		"Completing one sect updates only that sect's per-difficulty scores"
	)

	var reset_begin: Dictionary = store.begin_run_and_save(
		difficulty_one_finish.get("profile", {}),
		&"HuaShanPai",
		[],
		&"qingfeng_xuedi"
	)
	var run_reset: Dictionary = store.reset_run_and_save(reset_begin.get("profile", {}))
	_check(
		store.get_best_score(run_reset.get("profile", {}), &"HuaShanPai", 0) == 500
		and store.get_best_score(run_reset.get("profile", {}), &"HuaShanPai", 2) == 15000,
		"Run reset preserves all per-difficulty ending achievements"
	)
	_check(
		store.get_mastered_card_ids(run_reset.get("profile", {}))
		== store.get_mastered_card_ids(reset_begin.get("profile", {})),
		"Run reset preserves card mastery"
	)
	_check(
		store.get_max_unlocked_difficulty(run_reset.get("profile", {})) == 3
		and store.get_last_selected_difficulty(run_reset.get("profile", {})) == 2
		and store.get_run_difficulty(run_reset.get("profile", {})) == 0,
		"Run reset preserves global difficulty progress and selection but clears run difficulty"
	)
	var full_reset: Dictionary = store.reset_all_progress_and_save(run_reset.get("profile", {}))
	_check((full_reset["profile"]["best_scores_by_sect"] as Dictionary).is_empty(), "Full reset clears ending achievements")
	_check(
		store.get_mastered_card_ids(full_reset.get("profile", {})).is_empty(),
		"Full reset clears card mastery"
	)
	_check(
		store.get_max_unlocked_difficulty(full_reset.get("profile", {})) == 0
		and store.get_last_selected_difficulty(full_reset.get("profile", {})) == 0
		and store.get_run_difficulty(full_reset.get("profile", {})) == 0,
		"Full reset clears every difficulty field"
	)

	var capped_profile: Dictionary = full_reset.get("profile", {}).duplicate(true)
	capped_profile["max_unlocked_difficulty"] = Store.MAX_DIFFICULTY
	capped_profile["last_selected_difficulty"] = Store.MAX_DIFFICULTY
	var capped_begin: Dictionary = store.begin_run_and_save(
		capped_profile,
		&"HuaShanPai",
		[],
		&"qingfeng_xuedi",
		null,
		false,
		Store.MAX_DIFFICULTY
	)
	var capped_finish: Dictionary = store.record_completed_duel_and_save(
		capped_begin.get("profile", {}),
		Store.REWARD_VICTORY,
		1
	)
	_check(
		bool(capped_finish.get("completed", false))
		and store.get_max_unlocked_difficulty(capped_finish.get("profile", {}))
		== Store.MAX_DIFFICULTY,
		"Completing difficulty nine remains capped at difficulty nine"
	)
	_check(
		int((capped_finish.get("ending_summary", {}) as Dictionary).get("score", -1)) == 15000
		and store.get_best_score(capped_finish.get("profile", {}), &"HuaShanPai", 0) == 500
		and store.get_best_score(capped_finish.get("profile", {}), &"HuaShanPai", 1) == 500
		and store.get_best_score(capped_finish.get("profile", {}), &"HuaShanPai", 2) == 15000
		and store.get_best_score(capped_finish.get("profile", {}), &"HuaShanPai", 9) == 15000,
		"Difficulty-nine completion keeps its full score and propagates through every lower difficulty"
	)

	var legacy_active: Dictionary = active.duplicate(true)
	legacy_active["schema_version"] = 6
	legacy_active.erase("effective_duel_count")
	legacy_active.erase("defeated_enemy_ids")
	legacy_active.erase("best_scores_by_sect")
	legacy_active["main_deck"] = ["LeiZHenJian1", "KuiHua1", "jiang_wei", "TuNaShu2", "TaiZuChangQuan"]
	var migrated: Dictionary = store.repair_profile(legacy_active)
	_check(store.is_profile_valid(migrated), "A legacy active profile migrates to the new schema")
	_check(not bool(migrated["run_active"]), "Legacy migration closes an unreconstructable active run")
	_check((migrated["main_deck"] as Array) == _strings(Store.DEFAULT_MAIN_DECK_IDS), "Legacy active-run migration restores the default deck")
	_check(migrated["unlocked_card_ids"] == legacy_active["unlocked_card_ids"], "Legacy migration preserves unlocks")
	_check((migrated["best_scores_by_sect"] as Dictionary).is_empty(), "Legacy migration starts with empty achievements")
	_check(
		store.get_max_unlocked_difficulty(migrated) == 2
		and store.get_last_selected_difficulty(migrated) == 2
		and store.get_run_difficulty(migrated) == 0,
		"An unreconstructable legacy run unlocks and selects two but remains inactive"
	)

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
