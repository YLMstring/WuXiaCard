extends SceneTree

const OpeningSetup = preload("res://scripts/duel_opening_setup.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const State = preload("res://scripts/duel_state.gd")
const Action = preload("res://scripts/duel_action.gd")
const Simulator = preload("res://scripts/duel_simulator.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_exact_adjacent_pair_space()
	_test_seeded_layout_and_ownership()
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
	_check(state.get_hand(Rules.PLAYER_OWNER) == player_hand, "Opening layout preserves the player hand")
	_check(state.get_hand(Rules.OPPONENT_OWNER) == opponent_hand, "Opening layout preserves the opponent hand")
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
	var transition: Dictionary = Simulator.apply_action(state, Action.make_play(0, 0))
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
