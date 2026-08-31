extends SceneTree

const CORPUS_STATE_TARGET: int = 512
const CHILDREN_PER_STATE: int = 2

const Catalog = preload("res://scripts/card_catalog.gd")
const CompactState = preload("res://scripts/duel_compact_state.gd")
const EnemyManifest = preload("res://tests/benchmarks/enemy_ai_benchmark_manifest.gd")
const EnemyStateFactory = preload("res://tests/benchmarks/enemy_ai_benchmark_state_factory.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const State = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")

var _checks: int = 0
var _failures: int = 0
var _states_checked: int = 0
var _difference_reported: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_nonempty_runtime_payload_round_trip()
	_test_fresh_card_prototype_metadata()
	_test_transform_reachable_fresh_prototypes()
	_test_variant_payload_load_round_trip()
	_test_compact_copy_isolation()
	_test_real_quick_state_corpus()
	if _failures == 0:
		print(
			"DUEL_COMPACT_STATE_TESTS_PASSED checks=%d states=%d"
			% [_checks, _states_checked]
		)
	else:
		push_error(
			"DUEL_COMPACT_STATE_TESTS_FAILED failures=%d checks=%d states=%d"
			% [_failures, _checks, _states_checked]
		)
	quit(_failures)


func _test_nonempty_runtime_payload_round_trip() -> void:
	var hand_card: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan",
		Rules.PLAYER_OWNER,
		&"compact_hand"
	)
	hand_card[State.HAND_SLOT_INDEX_KEY] = 3
	hand_card["revealed_to_owner_ids"] = [
		Rules.PLAYER_OWNER,
		Rules.OPPONENT_OWNER,
	]
	var board_card: Dictionary = Catalog.create_instance(
		&"TuNaShu1",
		Rules.OPPONENT_OWNER,
		&"compact_board"
	)
	board_card["temporary_suppression_batches"] = [{
		"expires_after_owner_turn_serial": 7,
		"abilities": [{
			"index": 0,
			"ability": (board_card.get("active_abilities", []) as Array)[0],
		}],
	}]
	var state := State.new(
		[
			{"owner": Rules.OPPONENT_OWNER, "card": board_card, "fixture_extra": 9},
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
		],
		[hand_card],
		[],
		Rules.OPPONENT_OWNER
	)
	state.active_abilities = [{"fixture": &"state_ability"}]
	state.effect_queue = [{"event": &"queued", "amount": 2}]
	state.pending_choice = {"owner": Rules.PLAYER_OWNER, "cells": [1, 2]}
	state.repetition_hashes = [&"repeat_a", &"repeat_b"]
	state.remembered_glyphs_by_owner = {
		Rules.PLAYER_OWNER: ["拳"],
		Rules.OPPONENT_OWNER: ["心"],
	}
	state.future_draw_reveal_audiences = {
		Rules.PLAYER_OWNER: [Rules.OPPONENT_OWNER],
	}
	state.last_hand_play_by_owner = {
		Rules.PLAYER_OWNER: {"card_id": &"TaiZuChangQuan1", "instance_id": &"old"},
		Rules.OPPONENT_OWNER: {},
	}
	state.pending_non_retained_suppression_by_owner = {
		Rules.PLAYER_OWNER: 2,
		Rules.OPPONENT_OWNER: 1,
	}
	state.enabled_effect_gates_by_owner = {
		Rules.PLAYER_OWNER: [&"fixture_gate"],
		Rules.OPPONENT_OWNER: [],
	}
	state.owner_turn_serial = 12
	state.attacks_started_by_owner = {
		Rules.PLAYER_OWNER: 4,
		Rules.OPPONENT_OWNER: 5,
	}
	state.extra_card_plays_remaining = 2
	state.end_turn_triggers_resolved = true
	state.max_turns = 77
	state.run_difficulty = 9
	state.difficulty_eight_draw_consumed = true
	state.state_version = 42

	var compact: CompactState = _capture(state)
	_check(compact != null, "Nonempty runtime state can be captured")
	if compact == null:
		return
	_check(compact.is_structurally_valid(), "Captured compact state is structurally valid")
	var restored: State = compact.restore()
	_check(restored != null, "Nonempty compact state can be restored")
	if restored == null:
		return
	_check_exact_state(state, restored, "Nonempty runtime state round-trips exactly")


func _test_fresh_card_prototype_metadata() -> void:
	var mutated: Dictionary = Catalog.create_instance(
		&"TuNaShu3",
		Rules.PLAYER_OWNER,
		&"compact_mutated_prototype_source"
	)
	mutated["powers"] = [9, 8, 7, 6]
	mutated["ki"] = 4
	mutated["active_abilities"] = []
	mutated["temporary_suppression_batches"] = [{"fixture": true}]
	var state := State.new(Rules.empty_board(), [mutated], [], Rules.PLAYER_OWNER)
	var compact: CompactState = _capture(state)
	_check(compact != null, "Mutated runtime card can be captured for fresh prototype metadata")
	if compact == null:
		return
	var has_prototype_property: bool = false
	for property: Dictionary in compact.get_property_list():
		if StringName(property.get("name", &"")) == &"fresh_card_prototypes":
			has_prototype_property = true
			break
	_check(has_prototype_property, "Compact state exposes immutable fresh-card prototypes")
	if not has_prototype_property:
		return
	var prototypes: Array = compact.get("fresh_card_prototypes") as Array
	_check(prototypes.size() == 1, "Fresh prototype table deduplicates the captured card ID")
	if prototypes.size() != 1:
		return
	var prototype: Dictionary = prototypes[0] as Dictionary
	var expected_fresh: Dictionary = Catalog.create_instance(
		&"TuNaShu3",
		Rules.PLAYER_OWNER,
		&"expected"
	)
	_check(StringName(prototype.get("card_id", &"")) == &"TuNaShu3", "Fresh prototype keeps card ID")
	_check(
		prototype.get("powers", []) == expected_fresh.get("powers", []),
		"Fresh prototype keeps catalog powers"
	)
	_check(
		int(prototype.get("ki", -1)) == int(expected_fresh.get("ki", -2)),
		"Fresh prototype keeps catalog starting ki"
	)
	var template_index: int = int(prototype.get("template_index", -1))
	_check(
		template_index >= 0
		and template_index < compact.card_template_pool.size()
		and StringName((compact.card_template_pool[template_index] as Dictionary).get("card_id", &""))
		== &"TuNaShu3",
		"Fresh prototype references immutable catalog card metadata"
	)
	var ability_set_index: int = int(prototype.get("active_ability_set_index", -1))
	var expected_abilities: Array = expected_fresh.get("active_abilities", []) as Array
	_check(
		ability_set_index >= 0
		and ability_set_index < compact.active_ability_set_pool.size()
		and compact.active_ability_set_pool[ability_set_index] == expected_abilities,
		"Fresh prototype keeps normalized innate abilities instead of runtime losses"
	)
	var full_payload: Dictionary = compact.to_variant_payload()
	_check(full_payload.has("fresh_card_prototypes"), "Full payload carries fresh-card prototypes")
	var legacy_payload: Dictionary = full_payload.duplicate(true)
	legacy_payload.erase("fresh_card_prototypes")
	var legacy_loaded: CompactState = CompactState.from_variant_payload(legacy_payload)
	_check(legacy_loaded != null, "Legacy format-1 payload without prototypes remains loadable")
	if legacy_loaded != null:
		var restored: State = legacy_loaded.restore()
		_check(restored != null, "Legacy payload without prototypes remains restorable")
		if restored != null:
			_check_exact_state(state, restored, "Prototype metadata does not alter restored duel state")


func _test_transform_reachable_fresh_prototypes() -> void:
	var state := State.new(
		Rules.empty_board(),
		[Catalog.create_instance(
			&"SanRuDiYu1",
			Rules.PLAYER_OWNER,
			&"compact_transform_prototype_source"
		)],
		[],
		Rules.PLAYER_OWNER
	)
	var compact: CompactState = _capture(state)
	_check(compact != null, "Transform-prototype root can be captured")
	if compact == null:
		return
	var prototype_ids: Array[StringName] = []
	for prototype_value: Variant in compact.fresh_card_prototypes:
		prototype_ids.append(StringName((prototype_value as Dictionary).get("card_id", &"")))
	_check(
		prototype_ids == [&"SanRuDiYu1", &"SanRuDiYu2", &"SanRuDiYu3"],
		"Fresh prototypes include the deterministic transitive transform closure only"
	)


func _test_variant_payload_load_round_trip() -> void:
	var built: Dictionary = _first_real_opening()
	var state: State = built.get("state") as State
	_check(state != null, "A real opening exists for variant-payload loading")
	if state == null:
		return
	var captured: CompactState = _capture(state)
	_check(captured != null, "Real opening can be captured before variant-payload loading")
	if captured == null:
		return
	var loaded: CompactState = CompactState.from_variant_payload(
		captured.to_variant_payload()
	)
	_check(loaded != null, "Full compact variant payload can be loaded")
	if loaded == null:
		return
	var restored: State = loaded.restore()
	_check(restored != null, "Loaded compact variant payload can be restored")
	if restored != null:
		_check_exact_state(state, restored, "Loaded compact variant payload stays lossless")


func _test_compact_copy_isolation() -> void:
	var built: Dictionary = _first_real_opening()
	var state: State = built.get("state") as State
	_check(state != null, "A real opening exists for compact-copy isolation")
	if state == null:
		return
	var compact: CompactState = _capture(state)
	_check(compact != null, "Real opening can be captured for compact-copy isolation")
	if compact == null:
		return
	var copied: CompactState = compact.duplicate_compact() as CompactState
	var original_active_player: int = compact.scalars[CompactState.SCALAR_ACTIVE_PLAYER]
	copied.scalars[CompactState.SCALAR_ACTIVE_PLAYER] = Rules.OPPONENT_OWNER
	_check(
		compact.scalars[CompactState.SCALAR_ACTIVE_PLAYER] == original_active_player,
		"Compact scalar arrays are isolated between branches"
	)
	if not copied.card_powers.is_empty():
		var original_power: int = compact.card_powers[0]
		copied.card_powers[0] = original_power + 3
		_check(
			compact.card_powers[0] == original_power,
			"Compact card-power arrays are isolated between branches"
		)
	var copied_remembered: Dictionary = copied.side_payload.get(
		&"remembered_glyphs_by_owner",
		{}
	) as Dictionary
	var copied_player_glyphs: Array = copied_remembered.get(
		Rules.PLAYER_OWNER,
		[]
	) as Array
	copied_player_glyphs.append("隔离")
	var original_remembered: Dictionary = compact.side_payload.get(
		&"remembered_glyphs_by_owner",
		{}
	) as Dictionary
	_check(
		"隔离" not in (original_remembered.get(Rules.PLAYER_OWNER, []) as Array),
		"Compact mutable side payload is isolated between branches"
	)
	_check(
		copied.card_template_pool == compact.card_template_pool,
		"Compact copies retain the same immutable template contents"
	)


func _test_real_quick_state_corpus() -> void:
	var queue: Array[State] = []
	var opening_keys: Dictionary = {}
	for matchup: Dictionary in EnemyManifest.get_matchups_for_mode(&"quick"):
		for game: Dictionary in EnemyManifest.expand_matchup(matchup):
			var built: Dictionary = EnemyStateFactory.build(game, matchup)
			var state: State = built.get("state") as State
			if state == null:
				continue
			var exact_key: String = StateKey.build(state)
			if opening_keys.has(exact_key):
				continue
			opening_keys[exact_key] = true
			queue.append(state)
	_check(opening_keys.size() == 14, "Compact corpus starts from fourteen real Quick openings")

	var seen: Dictionary = {}
	var queue_index: int = 0
	while queue_index < queue.size() and seen.size() < CORPUS_STATE_TARGET:
		var state: State = queue[queue_index]
		queue_index += 1
		var exact_key: String = StateKey.build(state)
		if seen.has(exact_key):
			continue
		seen[exact_key] = true
		var compact: CompactState = _capture(state)
		_check(compact != null, "Real Quick state %d can be captured" % seen.size())
		if compact == null:
			continue
		var restored: State = compact.restore()
		_check(restored != null, "Real Quick state %d can be restored" % seen.size())
		if restored != null:
			_check_exact_state(
				state,
				restored,
				"Real Quick state %d round-trips exactly" % seen.size()
			)

		var actions: Array = Simulator.get_legal_actions(state)
		actions.sort_custom(func(first: Variant, second: Variant) -> bool:
			return first.canonical_key() < second.canonical_key()
		)
		for action_index: int in range(mini(actions.size(), CHILDREN_PER_STATE)):
			var transition: Dictionary = Simulator.apply_action(state, actions[action_index])
			if not bool(transition.get("valid", false)):
				continue
			var child: State = transition.get("state") as State
			if child != null:
				queue.append(child)
	_states_checked = seen.size()
	_check(
		_states_checked == CORPUS_STATE_TARGET,
		"Compact corpus reaches %d distinct real states" % CORPUS_STATE_TARGET
	)


func _first_real_opening() -> Dictionary:
	var matchups: Array[Dictionary] = EnemyManifest.get_matchups_for_mode(&"quick")
	if matchups.is_empty():
		return {}
	var games: Array[Dictionary] = EnemyManifest.expand_matchup(matchups[0])
	if games.is_empty():
		return {}
	return EnemyStateFactory.build(games[0], matchups[0])


func _capture(state: State) -> CompactState:
	var compact: CompactState = CompactState.new()
	if not compact.capture_state(state):
		return null
	return compact


func _check_exact_state(expected: State, actual: State, message: String) -> void:
	var matches: bool = (
		StateKey.build(expected) == StateKey.build(actual)
		and expected.state_version == actual.state_version
	)
	if not matches and not _difference_reported:
		_difference_reported = true
		print(
			"COMPACT_FIRST_DIFFERENCE %s"
			% _first_difference(
				CompactState.exact_state_payload(expected),
				CompactState.exact_state_payload(actual),
				"state"
			)
		)
	_check(matches, message)


func _first_difference(expected: Variant, actual: Variant, path: String) -> String:
	if typeof(expected) != typeof(actual):
		return "%s type expected=%d actual=%d" % [path, typeof(expected), typeof(actual)]
	if expected is Dictionary:
		var expected_dictionary: Dictionary = expected
		var actual_dictionary: Dictionary = actual
		for key: Variant in expected_dictionary:
			if not actual_dictionary.has(key):
				return "%s missing_key=%s" % [path, str(key)]
			var child_path: String = "%s.%s" % [path, str(key)]
			var child_difference: String = _first_difference(
				expected_dictionary[key],
				actual_dictionary[key],
				child_path
			)
			if not child_difference.is_empty():
				return child_difference
		for key: Variant in actual_dictionary:
			if not expected_dictionary.has(key):
				return "%s unexpected_key=%s" % [path, str(key)]
		return ""
	if expected is Array:
		var expected_array: Array = expected
		var actual_array: Array = actual
		if expected_array.size() != actual_array.size():
			return "%s size expected=%d actual=%d" % [
				path,
				expected_array.size(),
				actual_array.size(),
			]
		for index: int in range(expected_array.size()):
			var child_difference: String = _first_difference(
				expected_array[index],
				actual_array[index],
				"%s[%d]" % [path, index]
			)
			if not child_difference.is_empty():
				return child_difference
		return ""
	if expected != actual:
		return "%s expected=%s actual=%s" % [path, str(expected), str(actual)]
	return ""


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	print("CHECK_FAILED: %s" % message)
