class_name DuelOpeningSetup
extends RefCounted

const Catalog = preload("res://scripts/card_catalog.gd")
const Difficulty = preload("res://scripts/difficulty_rules.gd")
const Rules = preload("res://scripts/duel_rules.gd")

const BAGUA_CARD_ID: StringName = &"BaGuaFangWei"


static func get_adjacent_pairs() -> Array[Vector2i]:
	var pairs: Array[Vector2i] = []
	for row: int in range(3):
		for column: int in range(2):
			var cell: int = row * 3 + column
			pairs.append(Vector2i(cell, cell + 1))
	for row: int in range(2):
		for column: int in range(3):
			var cell: int = row * 3 + column
			pairs.append(Vector2i(cell, cell + 3))
	return pairs


static func build_opening_board(
	opening_owner: int,
	rng: RandomNumberGenerator,
	difficulty: int = 0
) -> Array:
	var board: Array = Rules.empty_board()
	if (
		opening_owner not in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]
		or rng == null
	):
		return board
	var later_owner: int = (
		Rules.OPPONENT_OWNER
		if opening_owner == Rules.PLAYER_OWNER
		else Rules.PLAYER_OWNER
	)
	var bagua_count: int = (
		Difficulty.get_later_player_bagua_count(difficulty)
		if later_owner == Rules.PLAYER_OWNER
		else 2
	)
	var selected_cells: Array[int] = []
	if bagua_count == 1:
		selected_cells.append(rng.randi_range(0, 8))
	elif bagua_count == 2:
		var pairs: Array[Vector2i] = get_adjacent_pairs()
		var selected_pair: Vector2i = pairs[rng.randi_range(0, pairs.size() - 1)]
		selected_cells.assign([selected_pair.x, selected_pair.y])
	for copy_index: int in range(selected_cells.size()):
		var instance_id := StringName(
			"opening_bagua_%d_%d" % [later_owner, copy_index]
		)
		var bagua: Dictionary = Catalog.create_instance(
			BAGUA_CARD_ID,
			later_owner,
			instance_id
		)
		if later_owner == Rules.OPPONENT_OWNER:
			var power: int = Difficulty.get_later_enemy_bagua_power(difficulty)
			if power >= 0:
				bagua["powers"] = [power, power, power, power]
		board[selected_cells[copy_index]] = {
			"owner": later_owner,
			"card": bagua,
		}
	return board
