class_name DuelInitialStateFactory
extends RefCounted

const Catalog = preload("res://scripts/card_catalog.gd")
const DeckRules = preload("res://scripts/deck_rules.gd")
const OpeningSetup = preload("res://scripts/duel_opening_setup.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const StateData = preload("res://scripts/duel_state.gd")


static func build(config: Dictionary) -> StateData:
	var player_ids: Array[StringName] = _to_string_name_array(
		config.get("player_main_card_ids", [])
	)
	var opponent_ids: Array[StringName] = _to_string_name_array(
		config.get("opponent_main_card_ids", [])
	)
	shuffle_with_seed(player_ids, int(config.get("player_hand_shuffle_seed", 0)), true)
	shuffle_with_seed(opponent_ids, int(config.get("opponent_hand_shuffle_seed", 0)), true)

	var instance_namespace: String = String(config.get("instance_namespace", ""))
	var player_cards: Array = create_card_instances(
		player_ids,
		Rules.PLAYER_OWNER,
		"main",
		instance_namespace
	)
	var opponent_cards: Array = create_card_instances(
		opponent_ids,
		Rules.OPPONENT_OWNER,
		"main",
		instance_namespace
	)
	var run_difficulty: int = clampi(int(config.get("run_difficulty", 0)), 0, 9)
	OpeningSetup.apply_enemy_opening_hand_buff(
		opponent_cards,
		run_difficulty,
		make_seeded_rng(int(config.get("difficulty_effect_seed", 0)))
	)

	var player_side_deck: Array = create_card_instances(
		DeckRules.build_side_deck_card_ids(player_ids),
		Rules.PLAYER_OWNER,
		"side",
		instance_namespace
	)
	var opponent_side_deck: Array = create_card_instances(
		DeckRules.build_side_deck_card_ids(opponent_ids),
		Rules.OPPONENT_OWNER,
		"side",
		instance_namespace
	)
	_shuffle_side_decks(player_side_deck, opponent_side_deck, config)

	var opening_owner: int = int(config.get("opening_owner", Rules.PLAYER_OWNER))
	if opening_owner != Rules.OPPONENT_OWNER:
		opening_owner = Rules.PLAYER_OWNER
	var board: Array = _build_opening_board(
		opening_owner,
		run_difficulty,
		int(config.get("opening_layout_seed", 0)),
		instance_namespace
	)
	var state: StateData = StateData.new(
		board,
		player_cards,
		opponent_cards,
		opening_owner,
		0,
		player_side_deck,
		opponent_side_deck,
		run_difficulty
	)
	state.enabled_effect_gates_by_owner = {
		Rules.PLAYER_OWNER: _duplicate_array(
			config.get("player_enabled_effect_gates", [])
		),
		Rules.OPPONENT_OWNER: _duplicate_array(
			config.get("opponent_enabled_effect_gates", [Rules.EFFECT_GATE_SELF_CASTRATION])
		),
	}
	state.remembered_glyphs_by_owner = _build_remembered_glyphs(
		config,
		player_cards,
		opponent_cards
	)
	state.max_turns = int(config.get("max_turns", state.max_turns))
	return state


static func create_card_instances(
	card_ids: Array[StringName],
	owner_id: int,
	zone: String,
	instance_namespace: String = ""
) -> Array:
	var instances: Array = []
	for card_index: int in range(card_ids.size()):
		var base_id: String = "%s_%d_%d" % [zone, owner_id, card_index]
		var instance_id := StringName(
			base_id if instance_namespace.is_empty() else "%s_%s" % [instance_namespace, base_id]
		)
		instances.append(Catalog.create_instance(card_ids[card_index], owner_id, instance_id))
	return instances


static func unique_card_glyphs(cards: Array) -> Array[String]:
	var glyphs: Array[String] = []
	for card_value: Variant in cards:
		if not card_value is Dictionary:
			continue
		var glyph := String((card_value as Dictionary).get("glyph", ""))
		if not glyph.is_empty() and glyph not in glyphs:
			glyphs.append(glyph)
	return glyphs


static func shuffle_with_seed(values: Array, seed_value: int, negative_disables: bool) -> void:
	if negative_disables and seed_value < 0:
		return
	shuffle_with_rng(values, make_seeded_rng(seed_value))


static func shuffle_with_rng(values: Array, rng: RandomNumberGenerator) -> void:
	for value_index: int in range(values.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, value_index)
		var temporary: Variant = values[value_index]
		values[value_index] = values[swap_index]
		values[swap_index] = temporary


static func make_seeded_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	return rng


static func _shuffle_side_decks(
	player_deck: Array,
	opponent_deck: Array,
	config: Dictionary
) -> void:
	if (
		config.has("player_side_deck_shuffle_seed")
		or config.has("opponent_side_deck_shuffle_seed")
	):
		shuffle_with_seed(
			player_deck,
			int(config.get("player_side_deck_shuffle_seed", 0)),
			false
		)
		shuffle_with_seed(
			opponent_deck,
			int(config.get("opponent_side_deck_shuffle_seed", 0)),
			false
		)
		return
	var rng: RandomNumberGenerator = make_seeded_rng(
		int(config.get("side_deck_shuffle_seed", 0))
	)
	shuffle_with_rng(player_deck, rng)
	shuffle_with_rng(opponent_deck, rng)


static func _build_opening_board(
	opening_owner: int,
	run_difficulty: int,
	seed_value: int,
	instance_namespace: String
) -> Array:
	if seed_value < 0:
		return Rules.empty_board()
	var board: Array = OpeningSetup.build_opening_board(
		opening_owner,
		make_seeded_rng(seed_value),
		run_difficulty
	)
	if instance_namespace.is_empty():
		return board
	for slot_value: Variant in board:
		if slot_value == null:
			continue
		var card: Dictionary = (slot_value as Dictionary).get("card", {})
		card["instance_id"] = StringName(
			"%s_%s" % [instance_namespace, String(card.get("instance_id", ""))]
		)
	return board


static func _build_remembered_glyphs(
	config: Dictionary,
	player_cards: Array,
	opponent_cards: Array
) -> Dictionary:
	if config.has("remembered_glyphs_by_owner"):
		var provided: Variant = config.get("remembered_glyphs_by_owner")
		if provided is Dictionary:
			return (provided as Dictionary).duplicate(true)
	return {
		Rules.PLAYER_OWNER: _duplicate_array(
			config.get("player_remembered_enemy_glyphs", [])
		),
		Rules.OPPONENT_OWNER: unique_card_glyphs(player_cards),
	}


static func _duplicate_array(value: Variant) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []


static func _to_string_name_array(value: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if not value is Array:
		return result
	for item: Variant in value as Array:
		result.append(StringName(String(item)))
	return result
