class_name BalanceTelemetryStore
extends RefCounted

const SCHEMA_VERSION: int = 1
const REPORT_SCHEMA_VERSION: int = 1
const DEFAULT_SAVE_PATH: String = "user://wuxia_balance_telemetry.json"
const OUTCOME_VICTORY: String = "victory"
const OUTCOME_DEFEAT: String = "defeat"
const VALID_OUTCOMES: Array[String] = [OUTCOME_VICTORY, OUTCOME_DEFEAT]
const VALID_STARTING_OWNERS: Array[int] = [1, 2]
const MAIN_DECK_SIZE: int = 5

var save_path: String


func _init(new_save_path: String = DEFAULT_SAVE_PATH) -> void:
	save_path = new_save_path


func create_default_state() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"anonymous_player_id": _new_identifier("anon"),
		"active_run": {},
		"pending_reports": [],
		"diagnostics": [],
	}


func load_state() -> Dictionary:
	var primary: Dictionary = _read_valid_state(save_path)
	if not primary.is_empty():
		return primary
	var backup_path: String = save_path + ".bak"
	var backup: Dictionary = _read_valid_state(backup_path)
	if not backup.is_empty():
		_remove_if_present(save_path)
		_write_primary_without_rotation(backup)
		return backup
	var replacement: Dictionary = create_default_state()
	if FileAccess.file_exists(save_path) or FileAccess.file_exists(backup_path):
		(replacement["diagnostics"] as Array).append({
			"kind": "local_state_unrecoverable",
			"recorded_at": _now_unix(),
		})
	_remove_if_present(save_path)
	_remove_if_present(backup_path)
	save_state(replacement)
	return replacement


func save_state(state: Dictionary) -> bool:
	if not is_state_valid(state):
		return false
	var temporary_path: String = save_path + ".tmp"
	var backup_path: String = save_path + ".bak"
	var temporary_file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if temporary_file == null:
		return false
	temporary_file.store_string(JSON.stringify(state))
	temporary_file.flush()
	temporary_file.close()
	var temporary_global: String = ProjectSettings.globalize_path(temporary_path)
	var save_global: String = ProjectSettings.globalize_path(save_path)
	var backup_global: String = ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_global)
	var had_existing: bool = FileAccess.file_exists(save_path)
	if had_existing and DirAccess.rename_absolute(save_global, backup_global) != OK:
		DirAccess.remove_absolute(temporary_global)
		return false
	if DirAccess.rename_absolute(temporary_global, save_global) != OK:
		if had_existing:
			DirAccess.rename_absolute(backup_global, save_global)
		return false
	return true


func is_state_valid(state: Dictionary) -> bool:
	if int(state.get("schema_version", -1)) != SCHEMA_VERSION:
		return false
	var anonymous_id: Variant = state.get("anonymous_player_id", null)
	if typeof(anonymous_id) != TYPE_STRING or not String(anonymous_id).begins_with("anon_"):
		return false
	if typeof(state.get("active_run", null)) != TYPE_DICTIONARY:
		return false
	if typeof(state.get("pending_reports", null)) != TYPE_ARRAY:
		return false
	if typeof(state.get("diagnostics", null)) != TYPE_ARRAY:
		return false
	for report_value: Variant in state.get("pending_reports", []):
		if typeof(report_value) != TYPE_DICTIONARY:
			return false
		var report := report_value as Dictionary
		if String(report.get("report_id", "")).is_empty():
			return false
	return true


func get_anonymous_player_id() -> String:
	return String(load_state().get("anonymous_player_id", ""))


func has_active_run() -> bool:
	return not (load_state().get("active_run", {}) as Dictionary).is_empty()


func start_run(
	difficulty: int,
	sect_id: StringName,
	game_version: String,
	platform: String
) -> Dictionary:
	if difficulty < 0 or String(sect_id).is_empty():
		return {"ok": false}
	var state: Dictionary = load_state()
	var run_id: String = _new_identifier("run")
	state["active_run"] = {
		"run_id": run_id,
		"game_version": game_version,
		"platform": platform,
		"difficulty": difficulty,
		"sect_id": String(sect_id),
		"started_at": _now_unix(),
		"duels": [],
		"pending_duel": {},
	}
	return {"ok": save_state(state), "run_id": run_id}


func clear_active_run() -> bool:
	var state: Dictionary = load_state()
	state["active_run"] = {}
	return save_state(state)


func begin_duel(
	enemy_id: StringName,
	player_level: int,
	starting_owner: int,
	player_card_ids: Array,
	enemy_card_ids: Array,
	counts_for_progress: bool = true
) -> Dictionary:
	if (
		String(enemy_id).is_empty()
		or player_level < 0
		or starting_owner not in VALID_STARTING_OWNERS
		or not _is_valid_main_deck(player_card_ids)
		or not _is_valid_main_deck(enemy_card_ids)
	):
		return {"ok": false}
	var state: Dictionary = load_state()
	var active_run := state.get("active_run", {}) as Dictionary
	if active_run.is_empty():
		return {"ok": false}
	var duel_token: String = _new_identifier("duel")
	active_run["pending_duel"] = {
		"duel_token": duel_token,
		"enemy_id": String(enemy_id),
		"player_level": player_level,
		"starting_owner": starting_owner,
		"player_card_ids": _string_array(player_card_ids),
		"enemy_card_ids": _string_array(enemy_card_ids),
		"counts_for_progress": counts_for_progress,
		"started_at": _now_unix(),
	}
	state["active_run"] = active_run
	return {"ok": save_state(state), "duel_token": duel_token}


func abandon_pending_duel(duel_token: String = "") -> bool:
	var state: Dictionary = load_state()
	var active_run := state.get("active_run", {}) as Dictionary
	if active_run.is_empty():
		return true
	var pending := active_run.get("pending_duel", {}) as Dictionary
	if (
		not duel_token.is_empty()
		and not pending.is_empty()
		and String(pending.get("duel_token", "")) != duel_token
	):
		return false
	active_run["pending_duel"] = {}
	state["active_run"] = active_run
	return save_state(state)


func complete_pending_duel(duel_token: String, outcome: StringName) -> Dictionary:
	var outcome_text: String = String(outcome)
	if outcome_text not in VALID_OUTCOMES:
		return {"ok": false}
	var state: Dictionary = load_state()
	var active_run := state.get("active_run", {}) as Dictionary
	if active_run.is_empty():
		return {"ok": false}
	var pending := active_run.get("pending_duel", {}) as Dictionary
	if pending.is_empty() or String(pending.get("duel_token", "")) != duel_token:
		return {"ok": false}
	var duels := active_run.get("duels", []) as Array
	var completed: Dictionary = pending.duplicate(true)
	completed.erase("duel_token")
	completed["duel_index"] = duels.size() + 1
	completed["outcome"] = outcome_text
	completed["completed_at"] = _now_unix()
	duels.append(completed)
	active_run["duels"] = duels
	active_run["pending_duel"] = {}
	state["active_run"] = active_run
	return {"ok": save_state(state), "duel": completed.duplicate(true)}


func seal_completed_run(final_score: int) -> Dictionary:
	var state: Dictionary = load_state()
	var active_run := state.get("active_run", {}) as Dictionary
	var duels := active_run.get("duels", []) as Array
	if active_run.is_empty() or duels.is_empty():
		return {"ok": false}
	var victory_count: int = 0
	var defeat_count: int = 0
	var formal_victory_count: int = 0
	var formal_defeat_count: int = 0
	for duel_value: Variant in duels:
		var duel := duel_value as Dictionary
		var is_victory: bool = String(duel.get("outcome", "")) == OUTCOME_VICTORY
		if is_victory:
			victory_count += 1
		else:
			defeat_count += 1
		if bool(duel.get("counts_for_progress", true)):
			if is_victory:
				formal_victory_count += 1
			else:
				formal_defeat_count += 1
	var report: Dictionary = {
		"schema_version": REPORT_SCHEMA_VERSION,
		"report_id": _new_identifier("report"),
		"anonymous_player_id": String(state.get("anonymous_player_id", "")),
		"run_id": String(active_run.get("run_id", "")),
		"game_version": String(active_run.get("game_version", "")),
		"platform": String(active_run.get("platform", "")),
		"difficulty": int(active_run.get("difficulty", 0)),
		"sect_id": String(active_run.get("sect_id", "")),
		"final_score": final_score,
		"victory_count": victory_count,
		"defeat_count": defeat_count,
		"formal_victory_count": formal_victory_count,
		"formal_defeat_count": formal_defeat_count,
		"started_at": int(active_run.get("started_at", 0)),
		"completed_at": _now_unix(),
		"duels": duels.duplicate(true),
	}
	var pending_reports := state.get("pending_reports", []) as Array
	pending_reports.append(report)
	state["pending_reports"] = pending_reports
	state["active_run"] = {}
	return {"ok": save_state(state), "report": report.duplicate(true)}


func get_pending_reports() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for report_value: Variant in load_state().get("pending_reports", []):
		result.append((report_value as Dictionary).duplicate(true))
	return result


func confirm_report_uploaded(report_id: String) -> bool:
	if report_id.is_empty():
		return false
	var state: Dictionary = load_state()
	var retained: Array = []
	var found: bool = false
	for report_value: Variant in state.get("pending_reports", []):
		var report := report_value as Dictionary
		if String(report.get("report_id", "")) == report_id:
			found = true
			continue
		retained.append(report)
	if not found:
		return false
	state["pending_reports"] = retained
	return save_state(state)


func record_permanent_error(report_id: String, message: String) -> bool:
	if report_id.is_empty():
		return false
	var state: Dictionary = load_state()
	var found: bool = false
	var pending_reports := state.get("pending_reports", []) as Array
	for index: int in range(pending_reports.size()):
		var report := pending_reports[index] as Dictionary
		if String(report.get("report_id", "")) != report_id:
			continue
		report["permanent_error"] = message.left(500)
		report["permanent_error_at"] = _now_unix()
		pending_reports[index] = report
		found = true
		break
	if not found:
		return false
	state["pending_reports"] = pending_reports
	(state["diagnostics"] as Array).append({
		"kind": "report_rejected",
		"report_id": report_id,
		"message": message.left(500),
		"recorded_at": _now_unix(),
	})
	return save_state(state)


func _read_valid_state(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {}
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var state := parsed as Dictionary
	return state if is_state_valid(state) else {}


func _write_primary_without_rotation(state: Dictionary) -> bool:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(state))
	file.flush()
	file.close()
	return true


func _remove_if_present(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _is_valid_main_deck(card_ids: Array) -> bool:
	if card_ids.size() != MAIN_DECK_SIZE:
		return false
	for value: Variant in card_ids:
		if String(value).is_empty():
			return false
	return true


func _string_array(values: Array) -> Array:
	var result: Array = []
	for value: Variant in values:
		result.append(String(value))
	return result


func _new_identifier(prefix: String) -> String:
	var random_bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	return "%s_%s" % [prefix, random_bytes.hex_encode()]


func _now_unix() -> int:
	return int(Time.get_unix_time_from_system())
