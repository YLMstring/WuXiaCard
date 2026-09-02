extends SceneTree

const OpeningSetup = preload("res://scripts/duel_opening_setup.gd")
const InitialStateFactory = preload("res://scripts/duel_initial_state_factory.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const DeckRules = preload("res://scripts/deck_rules.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")
const Action = preload("res://scripts/duel_action.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_exact_adjacent_pair_space()
	_test_seeded_layout_and_ownership()
	_test_difficulty_bagua_layouts()
	_test_enemy_opening_hand_buff()
	_test_initial_state_factory_determinism_and_isolation()
	_test_initial_state_factory_complete_opening()
	_test_bagua_exiles_before_flip()
	_finish()


func _test_exact_adjacent_pair_space() -> void:
	var expected: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(1, 2),
		Vector2i(3, 4), Vector2i(4, 5),
		Vector2i(6, 7), Vector2i(7, 8),
		Vector2i(0, 3), Vector2i(1, 4), Vector2i(2, 5),
		Vector2i(3, 6), Vector2i(4, 7), Vector2i(5, 8),
	]
	var pairs: Array[Vector2i] = OpeningSetup.get_adjacent_pairs()
	_check(pairs == expected, "Opening setup exposes each orthogonal adjacent pair exactly once")
	var observed: Dictionary = {}
	for pair: Vector2i in pairs:
		_check(pair.x < pair.y, "Opening pairs keep stable lower-cell-first order")
		_check(not observed.has(pair), "Opening pairs contain no duplicates")
		observed[pair] = true
		var row_distance: int = absi(floori(float(pair.x) / 3.0) - floori(float(pair.y) / 3.0))
		var column_distance: int = absi(pair.x % 3 - pair.y % 3)
		_check(row_distance + column_distance == 1, "Every opening pair is orthogonally adjacent")


func _test_seeded_layout_and_ownership() -> void:
	var player_first_a: Array = OpeningSetup.build_opening_board(
		Rules.PLAYER_OWNER,
		_seeded_rng(8192)
	)
	var player_first_b: Array = OpeningSetup.build_opening_board(
		Rules.PLAYER_OWNER,
		_seeded_rng(8192)
	)
	_check(player_first_a == player_first_b, "Equal opening seeds reproduce the exact layout")
	_check(_occupied_cells(player_first_a).size() == 2, "Opening setup occupies exactly two cells")
	_check(_cells_are_adjacent(_occupied_cells(player_first_a)), "Opening Bagua cells are adjacent")
	_check(
		_bagua_cards_are_owned_by(player_first_a, Rules.OPPONENT_OWNER),
		"Player-first setup gives both Bagua cards to the opponent"
	)

	var opponent_first: Array = OpeningSetup.build_opening_board(
		Rules.OPPONENT_OWNER,
		_seeded_rng(8192)
	)
	_check(
		_bagua_cards_are_owned_by(opponent_first, Rules.PLAYER_OWNER),
		"Opponent-first setup gives both Bagua cards to the player"
	)
	var occupied: Array[int] = _occupied_cells(opponent_first)
	var first_card: Dictionary = (opponent_first[occupied[0]] as Dictionary).get("card", {})
	var second_card: Dictionary = (opponent_first[occupied[1]] as Dictionary).get("card", {})
	_check(
		StringName(first_card.get("instance_id", &""))
		!= StringName(second_card.get("instance_id", &"")),
		"Opening Bagua copies receive unique runtime identities"
	)

	var player_hand: Array = [Catalog.create_instance(
		&"TaiZuChangQuan",
		Rules.PLAYER_OWNER,
		&"opening_player_hand"
	)]
	var opponent_hand: Array = [Catalog.create_instance(
		&"TuNaShu1",
		Rules.OPPONENT_OWNER,
		&"opening_opponent_hand"
	)]
	var player_deck: Array = [Catalog.create_instance(
		&"TuNaShu2",
		Rules.PLAYER_OWNER,
		&"opening_player_deck"
	)]
	var state: State = State.new(
		player_first_a,
		player_hand,
		opponent_hand,
		Rules.PLAYER_OWNER,
		0,
		player_deck,
		[]
	)
	_check(state.active_player == Rules.PLAYER_OWNER, "Opening layout does not change the first actor")
	_check(state.turn_count == 0, "Opening layout does not consume an action")
	var runtime_player_hand: Array = state.get_hand(Rules.PLAYER_OWNER)
	var runtime_opponent_hand: Array = state.get_hand(Rules.OPPONENT_OWNER)
	_check(
		runtime_player_hand.size() == 1
		and StringName((runtime_player_hand[0] as Dictionary).get("instance_id", &""))
		== &"opening_player_hand"
		and int((runtime_player_hand[0] as Dictionary).get("hand_slot_index", -1)) == 0,
		"Opening layout preserves the player hand and assigns its physical slot"
	)
	_check(
		runtime_opponent_hand.size() == 1
		and StringName((runtime_opponent_hand[0] as Dictionary).get("instance_id", &""))
		== &"opening_opponent_hand"
		and int((runtime_opponent_hand[0] as Dictionary).get("hand_slot_index", -1)) == 0,
		"Opening layout preserves the opponent hand and assigns its physical slot"
	)
	_check(state.decks[Rules.PLAYER_OWNER] == player_deck, "Opening layout preserves the side deck")


func _test_bagua_exiles_before_flip() -> void:
	var board: Array = Rules.empty_board()
	board[1] = {
		"owner": Rules.OPPONENT_OWNER,
		"card": Catalog.create_instance(
			&"BaGuaFangWei",
			Rules.OPPONENT_OWNER,
			&"bagua_target"
		),
	}
	var attacker: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan",
		Rules.PLAYER_OWNER,
		&"bagua_attacker"
	)
	var state: State = State.new(board, [attacker], [], Rules.PLAYER_OWNER)
	var transition: Dictionary = Simulator.apply_action_oracle(state, Action.make_play(0, 0))
	_check(bool(transition.get("valid", false)), "A normal card can attack special-negative Bagua")
	var next_state: State = transition.get("state", state)
	_check(next_state.board[1] == null, "Bagua leaves the board before its pending flip")
	var removed: Array = next_state.removed_cards[Rules.OPPONENT_OWNER]
	_check(
		removed.size() == 1
		and StringName((removed[0] as Dictionary).get("instance_id", &"")) == &"bagua_target",
		"Bagua is truly exiled to its original owner's removed zone"
	)
	var event_types: Array[StringName] = _event_types(transition.get("events", []))
	_check(&"attack_started" in event_types, "Bagua attack begins normally")
	_check(&"card_exiled" in event_types, "Bagua emits the normal exile event")
	_check(&"card_flipped" not in event_types, "Bagua exile prevents the pending flip")


func _test_difficulty_bagua_layouts() -> void:
	var observed_single_cells: Dictionary = {}
	for seed_value: int in range(1, 500):
		var single_board: Array = OpeningSetup.build_opening_board(
			Rules.OPPONENT_OWNER,
			_seeded_rng(seed_value),
			3
		)
		var occupied: Array[int] = _occupied_cells(single_board)
		_check(occupied.size() == 1, "Difficulty three gives a later player one Bagua")
		if occupied.size() == 1:
			observed_single_cells[occupied[0]] = true
		if observed_single_cells.size() == 9:
			break
	_check(observed_single_cells.size() == 9, "Single-Bagua setup can select every board cell")
	var no_bagua_board: Array = OpeningSetup.build_opening_board(
		Rules.OPPONENT_OWNER,
		_seeded_rng(8192),
		6
	)
	_check(_occupied_cells(no_bagua_board).is_empty(), "Difficulty six gives a later player no Bagua")

	for fixture: Dictionary in [
		{"difficulty": 3, "power": -1},
		{"difficulty": 4, "power": 2},
		{"difficulty": 6, "power": 2},
		{"difficulty": 7, "power": 4},
	]:
		var enemy_bagua_board: Array = OpeningSetup.build_opening_board(
			Rules.PLAYER_OWNER,
			_seeded_rng(8192),
			int(fixture["difficulty"])
		)
		_check(
			_occupied_cells(enemy_bagua_board).size() == 2
			and _cells_are_adjacent(_occupied_cells(enemy_bagua_board)),
			"Player-first difficulty %d keeps two adjacent enemy Bagua"
			% int(fixture["difficulty"])
		)
		for cell: int in _occupied_cells(enemy_bagua_board):
			var card: Dictionary = (enemy_bagua_board[cell] as Dictionary).get("card", {})
			var expected_power: int = int(fixture["power"])
			_check(
				card.get("powers", []) == [
					expected_power,
					expected_power,
					expected_power,
					expected_power,
				],
				"Difficulty %d statically sets enemy Bagua powers to %d"
				% [int(fixture["difficulty"]), expected_power]
			)


func _test_enemy_opening_hand_buff() -> void:
	var special_negative: Dictionary = Catalog.create_instance(
		&"BaGuaFangWei",
		Rules.OPPONENT_OWNER,
		&"opening_buff_negative"
	)
	var legal_first: Dictionary = Catalog.create_instance(
		&"TaiZuChangQuan",
		Rules.OPPONENT_OWNER,
		&"opening_buff_first"
	)
	var legal_second: Dictionary = Catalog.create_instance(
		&"TuNaShu1",
		Rules.OPPONENT_OWNER,
		&"opening_buff_second"
	)
	var difficulty_eight_hand: Array = [
		special_negative.duplicate(true),
		legal_first.duplicate(true),
		legal_second.duplicate(true),
	]
	_check(
		OpeningSetup.apply_enemy_opening_hand_buff(
			difficulty_eight_hand,
			8,
			_seeded_rng(7)
		) == &"",
		"Difficulty eight does not buff an opening hand card"
	)
	var difficulty_nine_hand: Array = [special_negative, legal_first, legal_second]
	var selected_id: StringName = OpeningSetup.apply_enemy_opening_hand_buff(
		difficulty_nine_hand,
		9,
		_seeded_rng(7)
	)
	_check(selected_id in [&"opening_buff_first", &"opening_buff_second"], "Difficulty nine skips special-negative cards")
	_check(special_negative.get("powers", []) == [-1, -1, -1, -1], "Special-negative opening card remains unchanged")
	var changed_count: int = 0
	for card: Dictionary in [legal_first, legal_second]:
		var original: Array = (
			Catalog.get_definition(StringName(card.get("card_id", &""))).get("powers", [])
			as Array
		)
		var expected: Array = []
		for power_value: Variant in original:
			expected.append(int(power_value) + 1)
		if card.get("powers", []) == expected:
			changed_count += 1
	_check(changed_count == 1, "Difficulty nine buffs exactly one legal opening hand card on all sides")
	var all_negative_hand: Array = [special_negative.duplicate(true)]
	_check(
		OpeningSetup.apply_enemy_opening_hand_buff(
			all_negative_hand,
			9,
			_seeded_rng(7)
		) == &"",
		"Difficulty nine is inert when every opening hand card is special-negative"
	)


func _test_initial_state_factory_determinism_and_isolation() -> void:
	var config: Dictionary = {
		"player_main_card_ids": [
			&"CangSongYingKe1", &"SanQinFeng1", &"ZiXiaGong1", &"TuNaShu1", &"YouFenLaiYi2",
		],
		"opponent_main_card_ids": [
			&"JinZhenDuJie1", &"WanHuaJian1", &"TuNaShu1", &"MianLiCangZhen2", &"HenShanJianZhen2",
		],
		"player_hand_shuffle_seed": 201,
		"opponent_hand_shuffle_seed": 202,
		"side_deck_shuffle_seed": 203,
		"opening_layout_seed": 204,
		"difficulty_effect_seed": 205,
		"opening_owner": Rules.PLAYER_OWNER,
		"run_difficulty": 0,
		"player_enabled_effect_gates": [&"player_gate"],
		"opponent_enabled_effect_gates": [&"opponent_gate"],
		"remembered_glyphs_by_owner": {
			Rules.PLAYER_OWNER: ["enemy-memory"],
			Rules.OPPONENT_OWNER: ["player-memory"],
		},
	}
	var first: State = InitialStateFactory.build(config)
	var second: State = InitialStateFactory.build(config)
	_check(StateKey.build(first) == StateKey.build(second), "Initial-state factory is deterministic for fixed seeds")
	(first.get_hand(Rules.PLAYER_OWNER)[0] as Dictionary)["powers"][0] = 999
	(first.enabled_effect_gates_by_owner[Rules.PLAYER_OWNER] as Array).append(&"mutated")
	_check(
		int((second.get_hand(Rules.PLAYER_OWNER)[0] as Dictionary).get("powers", [])[0]) != 999,
		"Repeated factory states do not share card data"
	)
	_check(
		&"mutated" not in second.get_enabled_effect_gates(Rules.PLAYER_OWNER),
		"Repeated factory states do not share effect-gate arrays"
	)


func _test_initial_state_factory_complete_opening() -> void:
	var player_ids: Array[StringName] = [
		&"CangSongYingKe1", &"SanQinFeng1", &"ZiXiaGong1", &"TuNaShu1", &"YouFenLaiYi2",
	]
	var opponent_ids: Array[StringName] = [
		&"JinZhenDuJie1", &"WanHuaJian1", &"TuNaShu1", &"MianLiCangZhen2", &"HenShanJianZhen2",
	]
	var state: State = InitialStateFactory.build({
		"player_main_card_ids": player_ids,
		"opponent_main_card_ids": opponent_ids,
		"player_hand_shuffle_seed": -1,
		"opponent_hand_shuffle_seed": -1,
		"side_deck_shuffle_seed": 501,
		"opening_layout_seed": 502,
		"difficulty_effect_seed": 503,
		"opening_owner": Rules.PLAYER_OWNER,
		"run_difficulty": 0,
		"player_enabled_effect_gates": [&"player_gate"],
		"opponent_enabled_effect_gates": [],
		"player_remembered_enemy_glyphs": ["known-enemy"],
	})
	_check(_occupied_cells(state.board).size() == 2, "Factory creates two static difficulty-zero Bagua for the later owner")
	_check(state.turn_count == 0 and state.effect_queue.is_empty(), "Factory opening consumes no actions or presentation events")
	_check(
		_card_id_set(state.decks[Rules.PLAYER_OWNER] as Array)
		== _string_name_set(DeckRules.build_side_deck_card_ids(player_ids)),
		"Factory derives the player side deck through DeckRules"
	)
	_check(
		_card_id_set(state.decks[Rules.OPPONENT_OWNER] as Array)
		== _string_name_set(DeckRules.build_side_deck_card_ids(opponent_ids)),
		"Factory derives the opponent side deck through DeckRules"
	)
	_check(
		state.get_enabled_effect_gates(Rules.PLAYER_OWNER) == [&"player_gate"]
		and state.get_enabled_effect_gates(Rules.OPPONENT_OWNER).is_empty(),
		"Factory preserves explicit effect gates for both owners"
	)
	_check(
		state.remembered_glyphs_by_owner[Rules.PLAYER_OWNER] == ["known-enemy"],
		"Factory preserves player enemy memory"
	)
	_check(
		state.remembered_glyphs_by_owner[Rules.OPPONENT_OWNER]
		== InitialStateFactory.unique_card_glyphs(state.get_hand(Rules.PLAYER_OWNER)),
		"Factory remembers the player's opening main-deck glyphs for the opponent"
	)
	_check(_all_runtime_instance_ids_are_unique(state), "Factory assigns unique runtime IDs across opening zones")


func _card_id_set(cards: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for card_value: Variant in cards:
		if card_value is Dictionary:
			result.append(StringName((card_value as Dictionary).get("card_id", &"")))
	result.sort()
	return result


func _string_name_set(values: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = values.duplicate()
	result.sort()
	return result


func _all_runtime_instance_ids_are_unique(state: State) -> bool:
	var observed: Dictionary = {}
	for zone: Array in [
		state.get_hand(Rules.PLAYER_OWNER),
		state.get_hand(Rules.OPPONENT_OWNER),
		state.decks[Rules.PLAYER_OWNER] as Array,
		state.decks[Rules.OPPONENT_OWNER] as Array,
	]:
		for card_value: Variant in zone:
			if not card_value is Dictionary:
				continue
			var instance_id := StringName((card_value as Dictionary).get("instance_id", &""))
			if instance_id == &"" or observed.has(instance_id):
				return false
			observed[instance_id] = true
	for slot_value: Variant in state.board:
		if slot_value == null:
			continue
		var card: Dictionary = (slot_value as Dictionary).get("card", {})
		var instance_id := StringName(card.get("instance_id", &""))
		if instance_id == &"" or observed.has(instance_id):
			return false
		observed[instance_id] = true
	return true


func _bagua_cards_are_owned_by(board: Array, expected_owner: int) -> bool:
	var occupied: Array[int] = _occupied_cells(board)
	if occupied.size() != 2:
		return false
	for cell: int in occupied:
		var slot: Dictionary = board[cell]
		var card: Dictionary = slot.get("card", {})
		if (
			int(slot.get("owner", 0)) != expected_owner
			or StringName(card.get("card_id", &"")) != &"BaGuaFangWei"
			or int(card.get("original_owner", 0)) != expected_owner
		):
			return false
	return true


func _occupied_cells(board: Array) -> Array[int]:
	var result: Array[int] = []
	for cell: int in range(board.size()):
		if board[cell] != null:
			result.append(cell)
	return result


func _cells_are_adjacent(cells: Array[int]) -> bool:
	if cells.size() != 2:
		return false
	var first: int = cells[0]
	var second: int = cells[1]
	return (
		absi(floori(float(first) / 3.0) - floori(float(second) / 3.0))
		+ absi(first % 3 - second % 3)
		== 1
	)


func _event_types(events: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for event_value: Variant in events:
		if event_value is Dictionary:
			result.append(StringName((event_value as Dictionary).get("type", &"")))
	return result


func _seeded_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)


func _finish() -> void:
	if _failures == 0:
		print("DUEL_OPENING_SETUP_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"DUEL_OPENING_SETUP_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)
