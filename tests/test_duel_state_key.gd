extends SceneTree

const State = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")
const Action = preload("res://scripts/duel_action.gd")
const EnemyManifest = preload("res://tests/benchmarks/enemy_ai_benchmark_manifest.gd")
const EnemyStateFactory = preload("res://tests/benchmarks/enemy_ai_benchmark_state_factory.gd")
const Simulator = preload("res://tests/helpers/duel_native_test_simulator.gd")

const COLLISION_STATE_TARGET: int = 512
const CHILDREN_PER_STATE: int = 2
const NULL_VECTOR: String = "v2:1:715d4659040c5b8c:ba2e4204b39b76cd"
const NESTED_VECTOR: String = "v2:8:dabb0ecb86a90c42:4c840896b3761535"

var _failures: int = 0
var _checks: int = 0
var _collision_states_checked: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_streaming_format()
	_test_variant_structure()
	_test_state_semantics()
	_test_real_state_collision_corpus()
	if _failures == 0:
		print(
			"DUEL_STATE_KEY_TESTS_PASSED checks=%d states=%d collisions=0"
			% [_checks, _collision_states_checked]
		)
	else:
		push_error(
			"DUEL_STATE_KEY_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_streaming_format() -> void:
	var state: State = State.new()
	_check(
		StateKey.build_compact(state).begins_with("v2:"),
		"Compact state keys use the streaming v2 format"
	)
	_check(
		StateKey.build_compact(null).begins_with("v2:"),
		"Null compact keys use the streaming v2 format"
	)


func _test_variant_structure() -> void:
	_check(
		StateKey.build_variant_compact(null) == NULL_VECTOR,
		"Null fingerprint matches its fixed vector"
	)
	_check(
		StateKey.build_variant_compact({"a": [1, true, &"江湖"], "b": null})
		== NESTED_VECTOR,
		"Nested fingerprint matches its fixed vector"
	)
	var first_dictionary: Dictionary = {"b": 2, "a": 1}
	var reordered_dictionary: Dictionary = {}
	reordered_dictionary["a"] = 1
	reordered_dictionary["b"] = 2
	_check(
		StateKey.build_variant_compact(first_dictionary)
		== StateKey.build_variant_compact(reordered_dictionary),
		"Dictionary insertion order does not affect the streaming fingerprint"
	)
	_check(
		StateKey.build_variant_compact([1, 2])
		!= StateKey.build_variant_compact([2, 1]),
		"Array order affects the streaming fingerprint"
	)
	_check(
		StateKey.build_variant_compact("same")
		!= StateKey.build_variant_compact(&"same"),
		"String and StringName retain distinct type identity"
	)
	_check(
		StateKey.build_variant_compact(1) != StateKey.build_variant_compact(true),
		"Integer and boolean values retain distinct type identity"
	)
	_check(
		StateKey.build_variant_compact(1) != StateKey.build_variant_compact(1.0),
		"Integer and float values retain distinct type identity"
	)
	_check(
		StateKey.build_variant_compact("")
		!= StateKey.build_variant_compact("江湖"),
		"UTF-8 text content affects the streaming fingerprint"
	)
	var nested: Dictionary = {
		"array": [null, true, {&"name": "江湖"}],
		"empty": {},
	}
	var changed_nested: Dictionary = nested.duplicate(true)
	(changed_nested["array"] as Array).append(3)
	_check(
		StateKey.build_variant_compact(nested)
		!= StateKey.build_variant_compact(changed_nested),
		"Nested container changes affect the streaming fingerprint"
	)


func _test_state_semantics() -> void:
	var state: State = State.new()
	var copied: State = state.duplicate_state() as State
	_check(
		StateKey.build_compact(state) == StateKey.build_compact(copied),
		"Deep-copied states retain the same streaming fingerprint"
	)
	copied.state_version += 1
	_check(
		StateKey.build_compact(state) == StateKey.build_compact(copied),
		"Live-only state version remains excluded from compact identity"
	)
	copied.active_player = 2
	_check(
		StateKey.build_compact(state) != StateKey.build_compact(copied),
		"Active player affects compact identity"
	)
	copied = state.duplicate_state() as State
	copied.effect_queue.append({"event": &"test", "amount": 1})
	_check(
		StateKey.build_compact(state) != StateKey.build_compact(copied),
		"Effect queue affects compact identity"
	)
	copied = state.duplicate_state() as State
	copied.removed_cards[1] = [{"card_id": &"Test", "powers": [1, 2, 3, 4]}]
	_check(
		StateKey.build_compact(state) != StateKey.build_compact(copied),
		"Removed cards affect compact identity"
	)
	copied = state.duplicate_state() as State
	copied.run_difficulty = 9
	_check(
		StateKey.build_compact(state) != StateKey.build_compact(copied),
		"Run difficulty affects compact identity"
	)
	copied = state.duplicate_state() as State
	copied.extra_card_play_granted_this_turn = true
	_check(
		StateKey.build_compact(state) != StateKey.build_compact(copied),
		"Per-turn extra-play grant usage affects compact identity"
	)


func _test_real_state_collision_corpus() -> void:
	var queue: Array[Dictionary] = []
	var opening_exact_keys: Dictionary = {}
	for matchup: Dictionary in EnemyManifest.get_matchups_for_mode(&"quick"):
		for game: Dictionary in EnemyManifest.expand_matchup(matchup):
			var built: Dictionary = EnemyStateFactory.build(game, matchup)
			var metadata: Dictionary = built.get("metadata", {}) as Dictionary
			var state: State = built.get("state") as State
			if state == null:
				continue
			var exact_key: String = String(metadata.get("initial_state_key", ""))
			if opening_exact_keys.has(exact_key):
				continue
			opening_exact_keys[exact_key] = true
			queue.append({
				"state": state,
				"source": String(metadata.get("game_id", "missing")),
			})
	_check(opening_exact_keys.size() == 14, "Collision corpus starts from fourteen real openings")
	var exact_seen: Dictionary = {}
	var compact_to_exact: Dictionary = {}
	var queue_index: int = 0
	while queue_index < queue.size() and exact_seen.size() < COLLISION_STATE_TARGET:
		var entry: Dictionary = queue[queue_index]
		queue_index += 1
		var state: State = entry.get("state") as State
		if state == null:
			continue
		var exact_key: String = StateKey.build(state)
		if exact_seen.has(exact_key):
			continue
		exact_seen[exact_key] = true
		var compact_key: String = StateKey.build_compact(state)
		if compact_to_exact.has(compact_key):
			_check(
				String(compact_to_exact[compact_key]) == exact_key,
				"Streaming fingerprint collision at %s" % entry.get("source", "missing")
			)
		else:
			compact_to_exact[compact_key] = exact_key
		var actions: Array[Action] = Simulator.get_legal_actions(state)
		actions.sort_custom(func(first: Action, second: Action) -> bool:
			return first.canonical_key() < second.canonical_key()
		)
		for action_index: int in range(mini(actions.size(), CHILDREN_PER_STATE)):
			var action: Action = actions[action_index]
			var transition: Dictionary = Simulator.apply_action(state, action)
			if not bool(transition.get("valid", false)):
				continue
			var next_state: State = transition.get("state") as State
			if next_state == null:
				continue
			queue.append({
				"state": next_state,
				"source": "%s/%s"
				% [entry.get("source", "missing"), action.canonical_key()],
			})
	_collision_states_checked = exact_seen.size()
	_check(
		_collision_states_checked >= COLLISION_STATE_TARGET,
		"Collision corpus reaches at least %d distinct exact states"
		% COLLISION_STATE_TARGET
	)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	print("CHECK_FAILED: %s" % message)
