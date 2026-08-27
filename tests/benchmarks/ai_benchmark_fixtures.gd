class_name DuelAIBenchmarkFixtures
extends RefCounted

const VERSION: int = 1

const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")
const StateData = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")


static func quick() -> Array[Dictionary]:
	return [
		_opening_fixture(),
		_mixed_midgame_fixture(),
		_activation_fixture(),
		_end_boundary_fixture(),
	]


static func extended() -> Array[Dictionary]:
	var fixtures: Array[Dictionary] = quick()
	fixtures.append_array([
		_sparse_reaction_fixture(),
		_ki_movement_fixture(),
		_crowded_fixture(),
		_empty_decks_fixture(),
		_zone_resources_fixture(),
		_repetition_pressure_fixture(),
		_difficulty_eight_fixture(),
		_flipped_ownership_fixture(),
		_multi_activation_fixture(),
		_one_empty_cell_fixture(),
		_no_hand_activation_fixture(),
		_late_turn_fixture(),
	])
	return fixtures


static func build_state(fixture: Dictionary) -> StateData:
	var board: Array = []
	board.resize(9)
	board.fill(null)
	var board_specs: Array = fixture.get("board", []) as Array
	for cell_index: int in range(mini(board_specs.size(), board.size())):
		var slot_value: Variant = board_specs[cell_index]
		if slot_value == null:
			continue
		var slot_spec: Dictionary = slot_value
		var current_owner: int = int(slot_spec.get("owner", Rules.PLAYER_OWNER))
		var card_spec: Dictionary = slot_spec.get("card", {}) as Dictionary
		board[cell_index] = {
			"owner": current_owner,
			"card": _build_card(card_spec, int(card_spec.get("original_owner", current_owner))),
		}
	var hands: Dictionary = fixture.get("hands", {}) as Dictionary
	var decks: Dictionary = fixture.get("decks", {}) as Dictionary
	var turn_data: Dictionary = fixture.get("turn_data", {}) as Dictionary
	var state := StateData.new(
		board,
		_build_zone(hands.get(Rules.PLAYER_OWNER, []) as Array, Rules.PLAYER_OWNER),
		_build_zone(hands.get(Rules.OPPONENT_OWNER, []) as Array, Rules.OPPONENT_OWNER),
		int(fixture.get("active_owner", Rules.PLAYER_OWNER)),
		int(turn_data.get("turn_count", 0)),
		_build_zone(decks.get(Rules.PLAYER_OWNER, []) as Array, Rules.PLAYER_OWNER),
		_build_zone(decks.get(Rules.OPPONENT_OWNER, []) as Array, Rules.OPPONENT_OWNER),
		int(fixture.get("difficulty", 0)),
		bool(turn_data.get("difficulty_eight_draw_consumed", false))
	)
	var discard: Dictionary = fixture.get("discard", {}) as Dictionary
	var removed: Dictionary = fixture.get("removed", {}) as Dictionary
	state.discard_piles = {
		Rules.PLAYER_OWNER: _build_zone(discard.get(Rules.PLAYER_OWNER, []) as Array, Rules.PLAYER_OWNER),
		Rules.OPPONENT_OWNER: _build_zone(discard.get(Rules.OPPONENT_OWNER, []) as Array, Rules.OPPONENT_OWNER),
	}
	state.removed_cards = {
		Rules.PLAYER_OWNER: _build_zone(removed.get(Rules.PLAYER_OWNER, []) as Array, Rules.PLAYER_OWNER),
		Rules.OPPONENT_OWNER: _build_zone(removed.get(Rules.OPPONENT_OWNER, []) as Array, Rules.OPPONENT_OWNER),
	}
	state.owner_turn_serial = int(turn_data.get("owner_turn_serial", 0))
	state.attacks_started_by_owner = (turn_data.get("attacks_started_by_owner", {
		Rules.PLAYER_OWNER: 0,
		Rules.OPPONENT_OWNER: 0,
	}) as Dictionary).duplicate(true)
	state.extra_card_plays_remaining = int(turn_data.get("extra_card_plays_remaining", 0))
	state.end_turn_triggers_resolved = bool(turn_data.get("end_turn_triggers_resolved", false))
	state.max_turns = int(turn_data.get("max_turns", 100))
	state.repetition_hashes = (fixture.get("repetition_history", []) as Array).duplicate(true)
	return state


static func validate_fixture(fixture: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for field: String in [
		"id",
		"difficulty",
		"active_owner",
		"board",
		"hands",
		"decks",
		"discard",
		"removed",
		"turn_data",
		"repetition_history",
	]:
		if not fixture.has(field):
			errors.append("missing %s" % field)
	var board_specs: Array = fixture.get("board", []) as Array
	if board_specs.size() != 9:
		errors.append("board must contain nine cells")
	var seen_instance_ids: Dictionary = {}
	for slot_value: Variant in board_specs:
		if slot_value == null:
			continue
		_validate_card_spec((slot_value as Dictionary).get("card", {}) as Dictionary, seen_instance_ids, errors)
	for zone_name: String in ["hands", "decks", "discard", "removed"]:
		var zones: Dictionary = fixture.get(zone_name, {}) as Dictionary
		for owner_id: int in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
			if not zones.has(owner_id):
				errors.append("%s missing owner %d" % [zone_name, owner_id])
				continue
			for card_spec_value: Variant in zones.get(owner_id, []):
				_validate_card_spec(card_spec_value as Dictionary, seen_instance_ids, errors)
	if errors.is_empty():
		var first_state: StateData = build_state(fixture)
		var second_state: StateData = build_state(fixture)
		if StateKey.build(first_state) != StateKey.build(second_state):
			errors.append("state key is nondeterministic")
	return errors


static func _build_zone(specs: Array, default_owner: int) -> Array:
	var cards: Array = []
	for spec_value: Variant in specs:
		var spec: Dictionary = spec_value
		cards.append(_build_card(spec, int(spec.get("original_owner", default_owner))))
	return cards


static func _build_card(spec: Dictionary, default_owner: int) -> Dictionary:
	var card := Catalog.create_instance(
		StringName(spec.get("card_id", &"TaiZuChangQuan")),
		int(spec.get("original_owner", default_owner)),
		StringName(spec.get("instance_id", &"benchmark_missing"))
	)
	if spec.has("powers"):
		card["powers"] = (spec["powers"] as Array).duplicate()
	if spec.has("ki"):
		card["ki"] = maxi(int(spec["ki"]), 0)
	return card


static func _validate_card_spec(
	spec: Dictionary,
	seen_instance_ids: Dictionary,
	errors: Array[String]
) -> void:
	var card_id := StringName(spec.get("card_id", &""))
	var instance_id := StringName(spec.get("instance_id", &""))
	if card_id == &"" or not Catalog.has_card(card_id):
		errors.append("unknown card id %s" % card_id)
	if instance_id == &"":
		errors.append("missing instance id")
	elif seen_instance_ids.has(instance_id):
		errors.append("duplicate instance id %s" % instance_id)
	else:
		seen_instance_ids[instance_id] = true


static func _empty_board_specs() -> Array:
	var board: Array = []
	board.resize(9)
	board.fill(null)
	return board


static func _card(card_id: StringName, instance_id: StringName, original_owner: int) -> Dictionary:
	return {
		"card_id": card_id,
		"instance_id": instance_id,
		"original_owner": original_owner,
	}


static func _base_fixture(
	fixture_id: StringName,
	active_owner: int,
	board: Array,
	player_hand: Array,
	opponent_hand: Array,
	player_deck: Array,
	opponent_deck: Array,
	turn_count: int = 0,
	max_turns: int = 100,
	repetition_history: Array = []
) -> Dictionary:
	return {
		"id": fixture_id,
		"version": VERSION,
		"difficulty": 0,
		"active_owner": active_owner,
		"board": board,
		"hands": {
			Rules.PLAYER_OWNER: player_hand,
			Rules.OPPONENT_OWNER: opponent_hand,
		},
		"decks": {
			Rules.PLAYER_OWNER: player_deck,
			Rules.OPPONENT_OWNER: opponent_deck,
		},
		"discard": {Rules.PLAYER_OWNER: [], Rules.OPPONENT_OWNER: []},
		"removed": {Rules.PLAYER_OWNER: [], Rules.OPPONENT_OWNER: []},
		"turn_data": {
			"turn_count": turn_count,
			"owner_turn_serial": turn_count,
			"attacks_started_by_owner": {Rules.PLAYER_OWNER: 0, Rules.OPPONENT_OWNER: 0},
			"extra_card_plays_remaining": 0,
			"end_turn_triggers_resolved": false,
			"max_turns": max_turns,
			"difficulty_eight_draw_consumed": false,
		},
		"repetition_history": repetition_history,
	}


static func _opening_fixture() -> Dictionary:
	return _base_fixture(
		&"v1_opening",
		Rules.PLAYER_OWNER,
		_empty_board_specs(),
		[
			_card(&"TaiZuChangQuan", &"v1_open_p_h0", Rules.PLAYER_OWNER),
			_card(&"TuNaShu1", &"v1_open_p_h1", Rules.PLAYER_OWNER),
			_card(&"CangSongYingKe1", &"v1_open_p_h2", Rules.PLAYER_OWNER),
		],
		[
			_card(&"TaiZuChangQuan", &"v1_open_o_h0", Rules.OPPONENT_OWNER),
			_card(&"TuNaShu1", &"v1_open_o_h1", Rules.OPPONENT_OWNER),
			_card(&"CangSongYingKe1", &"v1_open_o_h2", Rules.OPPONENT_OWNER),
		],
		[_card(&"WanYueChaoZong1", &"v1_open_p_d0", Rules.PLAYER_OWNER)],
		[_card(&"ZiXiaGong1", &"v1_open_o_d0", Rules.OPPONENT_OWNER)]
	)


static func _mixed_midgame_fixture() -> Dictionary:
	var board: Array = _empty_board_specs()
	board[0] = {"owner": Rules.PLAYER_OWNER, "card": _card(&"TaiZuChangQuan", &"v1_mid_p_b0", Rules.PLAYER_OWNER)}
	board[3] = {"owner": Rules.OPPONENT_OWNER, "card": _card(&"CangSongYingKe1", &"v1_mid_o_b3", Rules.OPPONENT_OWNER)}
	board[4] = {"owner": Rules.PLAYER_OWNER, "card": _card(&"TuNaShu1", &"v1_mid_o_b4", Rules.OPPONENT_OWNER)}
	board[8] = {"owner": Rules.OPPONENT_OWNER, "card": _card(&"WanYueChaoZong1", &"v1_mid_p_b8", Rules.PLAYER_OWNER)}
	return _base_fixture(
		&"v1_mixed_midgame",
		Rules.OPPONENT_OWNER,
		board,
		[
			_card(&"ZiXiaGong1", &"v1_mid_p_h0", Rules.PLAYER_OWNER),
			_card(&"CangSongYingKe2", &"v1_mid_p_h1", Rules.PLAYER_OWNER),
		],
		[
			_card(&"TuNaShu1", &"v1_mid_o_h0", Rules.OPPONENT_OWNER),
			_card(&"TaiZuChangQuan", &"v1_mid_o_h1", Rules.OPPONENT_OWNER),
		],
		[_card(&"CangSongYingKe1", &"v1_mid_p_d0", Rules.PLAYER_OWNER)],
		[_card(&"WanYueChaoZong1", &"v1_mid_o_d0", Rules.OPPONENT_OWNER)],
		17
	)


static func _activation_fixture() -> Dictionary:
	var board: Array = _empty_board_specs()
	board[1] = {"owner": Rules.PLAYER_OWNER, "card": _card(&"YouFenLaiYi2", &"v1_act_p_b1", Rules.PLAYER_OWNER)}
	board[4] = {"owner": Rules.OPPONENT_OWNER, "card": _card(&"YouFenLaiYi2", &"v1_act_o_b4", Rules.OPPONENT_OWNER)}
	board[7] = {"owner": Rules.PLAYER_OWNER, "card": _card(&"CangSongYingKe2", &"v1_act_p_b7", Rules.PLAYER_OWNER)}
	return _base_fixture(
		&"v1_activations",
		Rules.PLAYER_OWNER,
		board,
		[_card(&"ZiXiaGong1", &"v1_act_p_h0", Rules.PLAYER_OWNER)],
		[_card(&"TuNaShu1", &"v1_act_o_h0", Rules.OPPONENT_OWNER)],
		[_card(&"TaiZuChangQuan", &"v1_act_p_d0", Rules.PLAYER_OWNER)],
		[_card(&"TaiZuChangQuan", &"v1_act_o_d0", Rules.OPPONENT_OWNER)],
		31
	)


static func _end_boundary_fixture() -> Dictionary:
	var board: Array = _empty_board_specs()
	board[0] = {"owner": Rules.PLAYER_OWNER, "card": _card(&"TaiZuChangQuan", &"v1_end_p_b0", Rules.PLAYER_OWNER)}
	board[8] = {"owner": Rules.OPPONENT_OWNER, "card": _card(&"TaiZuChangQuan", &"v1_end_o_b8", Rules.OPPONENT_OWNER)}
	return _base_fixture(
		&"v1_end_boundary",
		Rules.PLAYER_OWNER,
		board,
		[_card(&"CangSongYingKe1", &"v1_end_p_h0", Rules.PLAYER_OWNER)],
		[_card(&"CangSongYingKe1", &"v1_end_o_h0", Rules.OPPONENT_OWNER)],
		[],
		[],
		99,
		100
	)


static func _sparse_reaction_fixture() -> Dictionary:
	var board: Array = _empty_board_specs()
	board[4] = {"owner": Rules.PLAYER_OWNER, "card": _card(&"CangSongYingKe2", &"v1_react_p_b4", Rules.PLAYER_OWNER)}
	return _base_fixture(
		&"v1_sparse_reaction",
		Rules.OPPONENT_OWNER,
		board,
		[
			_card(&"TaiZuChangQuan", &"v1_react_p_h0", Rules.PLAYER_OWNER),
			_card(&"TuNaShu1", &"v1_react_p_h1", Rules.PLAYER_OWNER),
		],
		[
			_card(&"WanYueChaoZong1", &"v1_react_o_h0", Rules.OPPONENT_OWNER),
			_card(&"CangSongYingKe1", &"v1_react_o_h1", Rules.OPPONENT_OWNER),
		],
		[_card(&"ZiXiaGong1", &"v1_react_p_d0", Rules.PLAYER_OWNER)],
		[_card(&"TuNaShu1", &"v1_react_o_d0", Rules.OPPONENT_OWNER)],
		8
	)


static func _ki_movement_fixture() -> Dictionary:
	var board: Array = _empty_board_specs()
	board[0] = {"owner": Rules.OPPONENT_OWNER, "card": _card(&"YouFenLaiYi2", &"v1_move_o_b0", Rules.OPPONENT_OWNER)}
	board[4] = {"owner": Rules.PLAYER_OWNER, "card": _card(&"YouFenLaiYi2", &"v1_move_p_b4", Rules.PLAYER_OWNER)}
	return _base_fixture(
		&"v1_ki_movement",
		Rules.PLAYER_OWNER,
		board,
		[_card(&"TaiZuChangQuan", &"v1_move_p_h0", Rules.PLAYER_OWNER)],
		[_card(&"CangSongYingKe1", &"v1_move_o_h0", Rules.OPPONENT_OWNER)],
		[_card(&"TuNaShu1", &"v1_move_p_d0", Rules.PLAYER_OWNER)],
		[_card(&"TuNaShu1", &"v1_move_o_d0", Rules.OPPONENT_OWNER)],
		12
	)


static func _crowded_fixture() -> Dictionary:
	var board: Array = _empty_board_specs()
	var ids: Array[StringName] = [
		&"TaiZuChangQuan", &"CangSongYingKe1", &"TuNaShu1",
		&"WanYueChaoZong1", &"ZiXiaGong1", &"CangSongYingKe2",
	]
	for cell_index: int in range(ids.size()):
		var owner_id: int = Rules.PLAYER_OWNER if cell_index in [0, 2, 4] else Rules.OPPONENT_OWNER
		board[cell_index] = {
			"owner": owner_id,
			"card": _card(ids[cell_index], StringName("v1_crowd_b%d" % cell_index), owner_id),
		}
	return _base_fixture(
		&"v1_crowded_six",
		Rules.OPPONENT_OWNER,
		board,
		[_card(&"YouFenLaiYi2", &"v1_crowd_p_h0", Rules.PLAYER_OWNER)],
		[_card(&"YouFenLaiYi2", &"v1_crowd_o_h0", Rules.OPPONENT_OWNER)],
		[],
		[],
		44
	)


static func _empty_decks_fixture() -> Dictionary:
	var board: Array = _empty_board_specs()
	board[2] = {"owner": Rules.PLAYER_OWNER, "card": _card(&"TaiZuChangQuan", &"v1_empty_p_b2", Rules.PLAYER_OWNER)}
	board[6] = {"owner": Rules.OPPONENT_OWNER, "card": _card(&"WanYueChaoZong1", &"v1_empty_o_b6", Rules.OPPONENT_OWNER)}
	return _base_fixture(
		&"v1_empty_decks",
		Rules.PLAYER_OWNER,
		board,
		[
			_card(&"TuNaShu1", &"v1_empty_p_h0", Rules.PLAYER_OWNER),
			_card(&"CangSongYingKe1", &"v1_empty_p_h1", Rules.PLAYER_OWNER),
		],
		[
			_card(&"TuNaShu1", &"v1_empty_o_h0", Rules.OPPONENT_OWNER),
			_card(&"CangSongYingKe1", &"v1_empty_o_h1", Rules.OPPONENT_OWNER),
		],
		[],
		[],
		40
	)


static func _zone_resources_fixture() -> Dictionary:
	var board: Array = _empty_board_specs()
	board[1] = {"owner": Rules.PLAYER_OWNER, "card": _card(&"ZiXiaGong1", &"v1_zone_p_b1", Rules.PLAYER_OWNER)}
	board[4] = {"owner": Rules.OPPONENT_OWNER, "card": _card(&"CangSongYingKe2", &"v1_zone_o_b4", Rules.OPPONENT_OWNER)}
	board[7] = {"owner": Rules.PLAYER_OWNER, "card": _card(&"TaiZuChangQuan", &"v1_zone_o_b7", Rules.OPPONENT_OWNER)}
	var fixture: Dictionary = _base_fixture(
		&"v1_zone_resources",
		Rules.OPPONENT_OWNER,
		board,
		[_card(&"WanYueChaoZong1", &"v1_zone_p_h0", Rules.PLAYER_OWNER)],
		[_card(&"TuNaShu1", &"v1_zone_o_h0", Rules.OPPONENT_OWNER)],
		[_card(&"CangSongYingKe1", &"v1_zone_p_d0", Rules.PLAYER_OWNER)],
		[_card(&"TaiZuChangQuan", &"v1_zone_o_d0", Rules.OPPONENT_OWNER)],
		53
	)
	fixture["discard"] = {
		Rules.PLAYER_OWNER: [_card(&"TuNaShu1", &"v1_zone_p_x0", Rules.PLAYER_OWNER)],
		Rules.OPPONENT_OWNER: [_card(&"ZiXiaGong1", &"v1_zone_o_x0", Rules.OPPONENT_OWNER)],
	}
	fixture["removed"] = {
		Rules.PLAYER_OWNER: [_card(&"TaiZuChangQuan", &"v1_zone_p_r0", Rules.PLAYER_OWNER)],
		Rules.OPPONENT_OWNER: [_card(&"CangSongYingKe1", &"v1_zone_o_r0", Rules.OPPONENT_OWNER)],
	}
	return fixture


static func _repetition_pressure_fixture() -> Dictionary:
	var board: Array = _empty_board_specs()
	board[0] = {"owner": Rules.PLAYER_OWNER, "card": _card(&"YouFenLaiYi2", &"v1_rep_p_b0", Rules.PLAYER_OWNER)}
	board[1] = {"owner": Rules.OPPONENT_OWNER, "card": _card(&"YouFenLaiYi2", &"v1_rep_o_b1", Rules.OPPONENT_OWNER)}
	board[4] = {"owner": Rules.PLAYER_OWNER, "card": _card(&"CangSongYingKe1", &"v1_rep_p_b4", Rules.PLAYER_OWNER)}
	board[8] = {"owner": Rules.OPPONENT_OWNER, "card": _card(&"TaiZuChangQuan", &"v1_rep_o_b8", Rules.OPPONENT_OWNER)}
	var fixture: Dictionary = _base_fixture(
		&"v1_repetition_pressure",
		Rules.PLAYER_OWNER,
		board,
		[_card(&"TuNaShu1", &"v1_rep_p_h0", Rules.PLAYER_OWNER)],
		[_card(&"TuNaShu1", &"v1_rep_o_h0", Rules.OPPONENT_OWNER)],
		[],
		[],
		61
	)
	var signature: String = Simulator.get_board_repetition_signature(build_state(fixture).board)
	fixture["repetition_history"] = [signature, signature, signature, signature]
	return fixture


static func _difficulty_eight_fixture() -> Dictionary:
	var board: Array = _empty_board_specs()
	board[3] = {"owner": Rules.PLAYER_OWNER, "card": _card(&"CangSongYingKe1", &"v1_d8_p_b3", Rules.PLAYER_OWNER)}
	board[5] = {"owner": Rules.OPPONENT_OWNER, "card": _card(&"WanYueChaoZong1", &"v1_d8_o_b5", Rules.OPPONENT_OWNER)}
	var fixture: Dictionary = _base_fixture(
		&"v1_difficulty_eight",
		Rules.OPPONENT_OWNER,
		board,
		[
			_card(&"TaiZuChangQuan", &"v1_d8_p_h0", Rules.PLAYER_OWNER),
			_card(&"TuNaShu1", &"v1_d8_p_h1", Rules.PLAYER_OWNER),
		],
		[
			_card(&"TaiZuChangQuan", &"v1_d8_o_h0", Rules.OPPONENT_OWNER),
			_card(&"TuNaShu1", &"v1_d8_o_h1", Rules.OPPONENT_OWNER),
		],
		[_card(&"ZiXiaGong1", &"v1_d8_p_d0", Rules.PLAYER_OWNER)],
		[_card(&"CangSongYingKe1", &"v1_d8_o_d0", Rules.OPPONENT_OWNER)],
		28
	)
	fixture["difficulty"] = 8
	return fixture


static func _flipped_ownership_fixture() -> Dictionary:
	var board: Array = _empty_board_specs()
	board[0] = {"owner": Rules.OPPONENT_OWNER, "card": _card(&"TaiZuChangQuan", &"v1_flip_p_b0", Rules.PLAYER_OWNER)}
	board[4] = {"owner": Rules.PLAYER_OWNER, "card": _card(&"CangSongYingKe1", &"v1_flip_o_b4", Rules.OPPONENT_OWNER)}
	board[8] = {"owner": Rules.OPPONENT_OWNER, "card": _card(&"WanYueChaoZong1", &"v1_flip_o_b8", Rules.OPPONENT_OWNER)}
	return _base_fixture(
		&"v1_flipped_ownership",
		Rules.PLAYER_OWNER,
		board,
		[_card(&"ZiXiaGong1", &"v1_flip_p_h0", Rules.PLAYER_OWNER)],
		[_card(&"TuNaShu1", &"v1_flip_o_h0", Rules.OPPONENT_OWNER)],
		[_card(&"TaiZuChangQuan", &"v1_flip_p_d0", Rules.PLAYER_OWNER)],
		[_card(&"CangSongYingKe2", &"v1_flip_o_d0", Rules.OPPONENT_OWNER)],
		35
	)


static func _multi_activation_fixture() -> Dictionary:
	var board: Array = _empty_board_specs()
	board[4] = {"owner": Rules.PLAYER_OWNER, "card": _card(&"YouFenLaiYi3", &"v1_multi_p_b4", Rules.PLAYER_OWNER)}
	board[1] = {"owner": Rules.PLAYER_OWNER, "card": _card(&"TaiZuChangQuan", &"v1_multi_p_b1", Rules.PLAYER_OWNER)}
	board[5] = {"owner": Rules.OPPONENT_OWNER, "card": _card(&"CangSongYingKe1", &"v1_multi_o_b5", Rules.OPPONENT_OWNER)}
	return _base_fixture(
		&"v1_multi_activation",
		Rules.PLAYER_OWNER,
		board,
		[_card(&"TuNaShu1", &"v1_multi_p_h0", Rules.PLAYER_OWNER)],
		[_card(&"WanYueChaoZong1", &"v1_multi_o_h0", Rules.OPPONENT_OWNER)],
		[],
		[],
		22
	)


static func _one_empty_cell_fixture() -> Dictionary:
	var board: Array = _empty_board_specs()
	for cell_index: int in range(8):
		var owner_id: int = Rules.PLAYER_OWNER if cell_index < 4 else Rules.OPPONENT_OWNER
		board[cell_index] = {
			"owner": owner_id,
			"card": _card(&"TaiZuChangQuan", StringName("v1_last_b%d" % cell_index), owner_id),
		}
	return _base_fixture(
		&"v1_one_empty_cell",
		Rules.OPPONENT_OWNER,
		board,
		[_card(&"CangSongYingKe1", &"v1_last_p_h0", Rules.PLAYER_OWNER)],
		[_card(&"CangSongYingKe1", &"v1_last_o_h0", Rules.OPPONENT_OWNER)],
		[],
		[],
		72
	)


static func _no_hand_activation_fixture() -> Dictionary:
	var board: Array = _empty_board_specs()
	board[1] = {"owner": Rules.PLAYER_OWNER, "card": _card(&"YouFenLaiYi2", &"v1_nohand_p_b1", Rules.PLAYER_OWNER)}
	board[7] = {"owner": Rules.OPPONENT_OWNER, "card": _card(&"YouFenLaiYi2", &"v1_nohand_o_b7", Rules.OPPONENT_OWNER)}
	return _base_fixture(
		&"v1_no_hand_activations",
		Rules.PLAYER_OWNER,
		board,
		[],
		[],
		[],
		[],
		47
	)


static func _late_turn_fixture() -> Dictionary:
	var board: Array = _empty_board_specs()
	for cell_index: int in [0, 2, 4, 6, 8]:
		var owner_id: int = Rules.PLAYER_OWNER if cell_index in [0, 4, 8] else Rules.OPPONENT_OWNER
		board[cell_index] = {
			"owner": owner_id,
			"card": _card(&"CangSongYingKe1", StringName("v1_late_b%d" % cell_index), owner_id),
		}
	return _base_fixture(
		&"v1_late_turn",
		Rules.OPPONENT_OWNER,
		board,
		[
			_card(&"TaiZuChangQuan", &"v1_late_p_h0", Rules.PLAYER_OWNER),
			_card(&"TuNaShu1", &"v1_late_p_h1", Rules.PLAYER_OWNER),
		],
		[
			_card(&"TaiZuChangQuan", &"v1_late_o_h0", Rules.OPPONENT_OWNER),
			_card(&"TuNaShu1", &"v1_late_o_h1", Rules.OPPONENT_OWNER),
		],
		[],
		[],
		95,
		100
	)
