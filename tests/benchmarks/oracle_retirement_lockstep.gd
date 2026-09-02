extends SceneTree

const Action = preload("res://scripts/duel_action.gd")
const CompactState = preload("res://scripts/duel_compact_state.gd")
const Manifest = preload("res://tests/benchmarks/enemy_ai_benchmark_manifest.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const StateFactory = preload("res://tests/benchmarks/enemy_ai_benchmark_state_factory.gd")

const MAX_ACTIONS_PER_WALK: int = 140

var _checks: int = 0
var _failures: int = 0
var _walks: int = 0
var _actions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var matchups: Array[Dictionary] = Manifest.get_matchups_for_mode(&"quick")
	for game: Dictionary in Manifest.expand_matchups(matchups):
		var matchup: Dictionary = _matchup_for_game(matchups, game)
		var built: Dictionary = StateFactory.build(game, matchup)
		_check(
			StateFactory.validate_built_game(built).is_empty(),
			"%s builds a valid real-deck opening" % game.get("id", &"missing")
		)
		var opening: State = built.get("state") as State
		if opening == null:
			continue
		_run_walk(opening, StringName(game.get("id", &"missing")), 0)
		var reversed: State = opening.duplicate_state()
		reversed.active_player = Simulator.other_owner(reversed.active_player)
		_run_walk(reversed, StringName(game.get("id", &"missing")), 1)
	if _failures == 0:
		print(
			"ORACLE_RETIREMENT_LOCKSTEP_PASSED checks=%d walks=%d actions=%d"
			% [_checks, _walks, _actions]
		)
	else:
		push_error(
			"ORACLE_RETIREMENT_LOCKSTEP_FAILED failures=%d checks=%d walks=%d actions=%d"
			% [_failures, _checks, _walks, _actions]
		)
	quit(_failures)


func _run_walk(opening: State, game_id: StringName, initiative_variant: int) -> void:
	_walks += 1
	var native_state: State = opening.duplicate_state()
	var oracle_state: State = opening.duplicate_state()
	var label: String = "%s initiative=%d" % [game_id, initiative_variant]
	for step: int in range(MAX_ACTIONS_PER_WALK):
		if not _compare_states(native_state, oracle_state, "%s step=%d pre" % [label, step]):
			return
		var native_terminal: bool = Simulator.is_terminal(native_state)
		var oracle_terminal: bool = Simulator.is_terminal(oracle_state)
		_check(native_terminal == oracle_terminal, "%s terminal status matches at step %d" % [label, step])
		if native_terminal or oracle_terminal:
			return
		var native_actions: Array[Action] = Simulator.get_legal_actions(native_state)
		var oracle_actions: Array[Action] = Simulator.get_legal_actions(oracle_state)
		var native_keys: Array[String] = _action_keys(native_actions)
		var oracle_keys: Array[String] = _action_keys(oracle_actions)
		_check(native_keys == oracle_keys, "%s legal actions match at step %d" % [label, step])
		if native_keys != oracle_keys or native_actions.is_empty():
			return
		var action_index: int = posmod(
			StateFactory.stable_seed("%s|%d|%d" % [game_id, initiative_variant, step]),
			native_actions.size()
		)
		var action: Action = _action_by_key(native_actions, native_keys[action_index])
		var native_transition: Dictionary = Simulator.apply_action(native_state, action)
		var oracle_transition: Dictionary = Simulator.apply_action_oracle(
			oracle_state,
			action.duplicate_action()
		)
		_actions += 1
		_check(bool(native_transition.get("valid", false)), "%s native accepts step %d" % [label, step])
		_check(bool(oracle_transition.get("valid", false)), "%s Oracle accepts step %d" % [label, step])
		if (
			not bool(native_transition.get("valid", false))
			or not bool(oracle_transition.get("valid", false))
		):
			return
		_check(
			native_transition.get("captures", []) == oracle_transition.get("captures", []),
			"%s captures match at step %d action=%s" % [label, step, action.canonical_key()]
		)
		_check(
			native_transition.get("exiles", []) == oracle_transition.get("exiles", []),
			"%s exiles match at step %d action=%s" % [label, step, action.canonical_key()]
		)
		_check(
			native_transition.get("events", []) == oracle_transition.get("events", []),
			"%s events match at step %d action=%s" % [label, step, action.canonical_key()]
		)
		native_state = native_transition.get("state") as State
		oracle_state = oracle_transition.get("state") as State
	_check(false, "%s exceeded the %d-action lockstep watchdog" % [label, MAX_ACTIONS_PER_WALK])


func _compare_states(native_state: State, oracle_state: State, label: String) -> bool:
	var equal: bool = (
		native_state != null
		and oracle_state != null
		and CompactState.exact_state_payload(native_state)
		== CompactState.exact_state_payload(oracle_state)
	)
	_check(equal, "%s exact state matches" % label)
	return equal


func _action_keys(actions: Array[Action]) -> Array[String]:
	var result: Array[String] = []
	for action: Action in actions:
		result.append(action.canonical_key())
	result.sort()
	return result


func _action_by_key(actions: Array[Action], key: String) -> Action:
	for action: Action in actions:
		if action.canonical_key() == key:
			return action
	return null


func _matchup_for_game(matchups: Array[Dictionary], game: Dictionary) -> Dictionary:
	var matchup_id := StringName(game.get("matchup_id", &""))
	for matchup: Dictionary in matchups:
		if StringName(matchup.get("id", &"")) == matchup_id:
			return matchup
	return {}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
