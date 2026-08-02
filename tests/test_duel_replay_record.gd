extends SceneTree

const ReplayRecord = preload("res://scripts/duel_replay_record.gd")
const StateData = preload("res://scripts/duel_state.gd")
const ActionData = preload("res://scripts/duel_action.gd")
const Rules = preload("res://scripts/duel_rules.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var opening: StateData = _make_state(0)
	var record: RefCounted = ReplayRecord.new()
	_check(not record.is_ready(), "Fresh replay record is not ready")
	_check(record.get_actions().is_empty(), "Fresh replay record has no actions")

	record.begin(opening)
	opening.turn_count = 99
	opening.get_hand(Rules.PLAYER_OWNER)[0]["ki"] = 7
	var stored_opening: StateData = record.get_initial_state()
	_check(stored_opening != null, "Replay begin stores an initial state")
	_check(stored_opening.turn_count == 0, "Initial state is independent from its source")
	_check(
		int((stored_opening.get_hand(Rules.PLAYER_OWNER)[0] as Dictionary)["ki"]) == 0,
		"Nested opening card data is duplicated"
	)
	stored_opening.turn_count = 42
	_check(record.get_initial_state().turn_count == 0, "Initial-state accessor returns a fresh duplicate")

	var action: ActionData = ActionData.make_play(0, 4, &"player_card")
	record.record_action(action)
	action.target_index = 8
	var stored_actions: Array[ActionData] = record.get_actions()
	_check(stored_actions.size() == 1, "Replay record stores one action")
	_check(stored_actions[0].target_index == 4, "Recorded action is independent from its source")
	stored_actions[0].target_index = 2
	_check(record.get_actions()[0].target_index == 4, "Action accessor returns fresh duplicates")
	_check(not record.is_ready(), "Initial state and actions alone are not ready")

	var final_state: StateData = _make_state(1)
	record.complete(final_state, &"victory", "获胜 · 1–0")
	final_state.turn_count = 77
	_check(record.is_ready(), "Completed victory record is ready")
	_check(record.get_outcome() == &"victory", "Replay record preserves outcome")
	_check(record.get_final_status() == "获胜 · 1–0", "Replay record preserves final status")
	_check(record.get_final_state().turn_count == 1, "Final state is independent from its source")
	var returned_final: StateData = record.get_final_state()
	returned_final.turn_count = 55
	_check(record.get_final_state().turn_count == 1, "Final-state accessor returns a fresh duplicate")

	var reset_opening: StateData = _make_state(3)
	record.begin(reset_opening)
	_check(not record.is_ready(), "Beginning a new record clears completion")
	_check(record.get_actions().is_empty(), "Beginning a new record clears old actions")
	_check(record.get_outcome() == &"", "Beginning a new record clears old outcome")

	var empty_record: RefCounted = ReplayRecord.new()
	empty_record.begin(_make_state(0))
	empty_record.complete(_make_state(0), &"defeat", "失败 · 0–0")
	_check(not empty_record.is_ready(), "A completed record without actions is not replayable")

	_finish()


func _make_state(turn_count: int) -> StateData:
	var player_card: Dictionary = {
		"card_id": &"fixture",
		"instance_id": &"player_card",
		"owner": Rules.PLAYER_OWNER,
		"ki": 0,
		"powers": [1, 2, 3, 4],
		"active_abilities": [],
	}
	return StateData.new(
		Rules.empty_board(),
		[player_card],
		[],
		Rules.PLAYER_OWNER,
		turn_count,
		[],
		[]
	)


func _finish() -> void:
	if _failures == 0:
		print("DUEL_REPLAY_RECORD_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("DUEL_REPLAY_RECORD_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
