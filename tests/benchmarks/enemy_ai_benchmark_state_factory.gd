class_name EnemyAIBenchmarkStateFactory
extends RefCounted

const VERSION: int = 2
const MASTER_SEED: int = 827_202_608

const InitialStateFactory = preload("res://scripts/duel_initial_state_factory.gd")
const Manifest = preload("res://tests/benchmarks/enemy_ai_benchmark_manifest.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const StateData = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")


static func build(game: Dictionary, matchup: Dictionary) -> Dictionary:
	var roster_by_id: Dictionary = _roster_by_id()
	var enemy_by_owner: Dictionary = game.get("enemy_by_owner", {}) as Dictionary
	var owner_one_id := StringName(enemy_by_owner.get(Rules.PLAYER_OWNER, &""))
	var owner_two_id := StringName(enemy_by_owner.get(Rules.OPPONENT_OWNER, &""))
	var owner_one: Dictionary = roster_by_id.get(owner_one_id, {})
	var owner_two: Dictionary = roster_by_id.get(owner_two_id, {})
	var matchup_id := StringName(matchup.get("id", &"missing"))
	var instance_namespace: String = "bench_v%d_%s_o1_%s_o2_%s" % [
		VERSION,
		matchup_id,
		owner_one_id,
		owner_two_id,
	]
	var seeds: Dictionary = {
		"owner_one_hand": stable_seed("hand|%s" % owner_one_id),
		"owner_two_hand": stable_seed("hand|%s" % owner_two_id),
		"owner_one_side": stable_seed("side|%s" % owner_one_id),
		"owner_two_side": stable_seed("side|%s" % owner_two_id),
		"opening": stable_seed("opening|%s" % matchup_id),
		"difficulty": stable_seed("difficulty|%s" % matchup_id),
	}
	var state: StateData = InitialStateFactory.build({
		"player_main_card_ids": owner_one.get("deck", []),
		"opponent_main_card_ids": owner_two.get("deck", []),
		"player_hand_shuffle_seed": seeds["owner_one_hand"],
		"opponent_hand_shuffle_seed": seeds["owner_two_hand"],
		"player_side_deck_shuffle_seed": seeds["owner_one_side"],
		"opponent_side_deck_shuffle_seed": seeds["owner_two_side"],
		"opening_layout_seed": seeds["opening"],
		"difficulty_effect_seed": seeds["difficulty"],
		"opening_owner": Rules.PLAYER_OWNER,
		"run_difficulty": 0,
		"player_enabled_effect_gates": _effect_gates(owner_one),
		"opponent_enabled_effect_gates": _effect_gates(owner_two),
		"remembered_glyphs_by_owner": {
			Rules.PLAYER_OWNER: [],
			Rules.OPPONENT_OWNER: [],
		},
		"instance_namespace": instance_namespace,
	})
	state.remembered_glyphs_by_owner = {
		Rules.PLAYER_OWNER: opening_glyphs(state, Rules.OPPONENT_OWNER),
		Rules.OPPONENT_OWNER: opening_glyphs(state, Rules.PLAYER_OWNER),
	}
	var metadata: Dictionary = {
		"fixture_version": VERSION,
		"master_seed": MASTER_SEED,
		"game_id": StringName(game.get("id", &"missing")),
		"matchup_id": matchup_id,
		"assignment": int(game.get("assignment", 0)),
		"enemy_by_owner": enemy_by_owner.duplicate(true),
		"profile_by_owner": (game.get("profile_by_owner", {}) as Dictionary).duplicate(true),
		"deck_by_owner": {
			Rules.PLAYER_OWNER: (owner_one.get("deck", []) as Array).duplicate(true),
			Rules.OPPONENT_OWNER: (owner_two.get("deck", []) as Array).duplicate(true),
		},
		"level_by_owner": {
			Rules.PLAYER_OWNER: int(owner_one.get("level", 0)),
			Rules.OPPONENT_OWNER: int(owner_two.get("level", 0)),
		},
		"seeds": seeds.duplicate(true),
		"initial_state_key": StateKey.build(state),
	}
	return {"state": state, "metadata": metadata}


static func opening_glyphs(state: StateData, owner_id: int) -> Array[String]:
	return InitialStateFactory.unique_card_glyphs(state.get_hand(owner_id))


static func stable_seed(label: String) -> int:
	var result: int = MASTER_SEED % 2_147_483_629
	for byte_value: int in label.to_utf8_buffer():
		result = (result * 131 + byte_value + 1) % 2_147_483_629
	return maxi(result, 1)


static func validate_built_game(built: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var state: StateData = built.get("state") as StateData
	var metadata: Dictionary = built.get("metadata", {}) as Dictionary
	if state == null:
		errors.append("missing state")
		return errors
	if String(metadata.get("initial_state_key", "")) != StateKey.build(state):
		errors.append("initial state key does not match metadata")
	var observed: Dictionary = {}
	for zone: Array in _all_card_zones(state):
		for card_value: Variant in zone:
			if not card_value is Dictionary:
				continue
			var instance_id := StringName((card_value as Dictionary).get("instance_id", &""))
			if instance_id == &"":
				errors.append("missing runtime instance ID")
			elif observed.has(instance_id):
				errors.append("duplicate runtime instance ID: %s" % instance_id)
			else:
				observed[instance_id] = true
	return errors


static func _all_card_zones(state: StateData) -> Array[Array]:
	var zones: Array[Array] = [
		state.get_hand(Rules.PLAYER_OWNER),
		state.get_hand(Rules.OPPONENT_OWNER),
		state.decks.get(Rules.PLAYER_OWNER, []) as Array,
		state.decks.get(Rules.OPPONENT_OWNER, []) as Array,
		state.discard_piles.get(Rules.PLAYER_OWNER, []) as Array,
		state.discard_piles.get(Rules.OPPONENT_OWNER, []) as Array,
		state.removed_cards.get(Rules.PLAYER_OWNER, []) as Array,
		state.removed_cards.get(Rules.OPPONENT_OWNER, []) as Array,
	]
	var board_cards: Array = []
	for slot_value: Variant in state.board:
		if slot_value != null:
			board_cards.append((slot_value as Dictionary).get("card", {}))
	zones.append(board_cards)
	return zones


static func _effect_gates(enemy: Dictionary) -> Array[StringName]:
	if bool(enemy.get("self_castration_enabled", true)):
		return [Rules.EFFECT_GATE_SELF_CASTRATION]
	return []


static func _roster_by_id() -> Dictionary:
	var result: Dictionary = {}
	for enemy: Dictionary in Manifest.get_roster():
		result[StringName(enemy.get("id", &""))] = enemy
	return result
