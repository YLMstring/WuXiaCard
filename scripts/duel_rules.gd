class_name DuelRules
extends RefCounted

const TOP: int = 0
const RIGHT: int = 1
const BOTTOM: int = 2
const LEFT: int = 3

const PLAYER_OWNER: int = 1
const OPPONENT_OWNER: int = 2

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]
const OPPOSITE: Array[int] = [BOTTOM, LEFT, TOP, RIGHT]


static func make_card(card_name: String, glyph: String, powers: Array[int]) -> Dictionary:
	assert(powers.size() == 4, "Cards require top, right, bottom, and left powers.")
	return {
		"name": card_name,
		"glyph": glyph,
		"powers": powers.duplicate(),
	}


static func empty_board() -> Array:
	var board: Array = []
	board.resize(9)
	board.fill(null)
	return board


static func can_place(board: Array, cell_index: int) -> bool:
	return cell_index >= 0 and cell_index < 9 and board.size() == 9 and board[cell_index] == null


static func place_card(board: Array, cell_index: int, card: Dictionary, owner_id: int) -> Array[int]:
	if not can_place(board, cell_index):
		return []
	board[cell_index] = {
		"card": card.duplicate(true),
		"owner": owner_id,
	}
	return resolve_captures(board, cell_index)


static func resolve_captures(board: Array, placed_index: int) -> Array[int]:
	var captured: Array[int] = []
	if placed_index < 0 or placed_index >= board.size() or board[placed_index] == null:
		return captured

	var placed_slot: Dictionary = board[placed_index]
	var placed_card: Dictionary = placed_slot["card"]
	var placed_powers: Array = placed_card["powers"]
	var placed_owner: int = int(placed_slot["owner"])

	for direction: int in range(4):
		var neighbor_index: int = get_neighbor_index(placed_index, direction)
		if neighbor_index < 0 or board[neighbor_index] == null:
			continue

		var neighbor_slot: Dictionary = board[neighbor_index]
		if int(neighbor_slot["owner"]) == placed_owner:
			continue

		var neighbor_card: Dictionary = neighbor_slot["card"]
		var neighbor_powers: Array = neighbor_card["powers"]
		var attack_power: int = int(placed_powers[direction])
		var defense_power: int = int(neighbor_powers[OPPOSITE[direction]])
		if attack_power > defense_power:
			neighbor_slot["owner"] = placed_owner
			captured.append(neighbor_index)

	return captured


static func get_neighbor_index(cell_index: int, direction: int) -> int:
	if cell_index < 0 or cell_index >= 9 or direction < 0 or direction >= DIRECTIONS.size():
		return -1
	var row: int = cell_index / 3
	var column: int = cell_index % 3
	var target: Vector2i = Vector2i(column, row) + DIRECTIONS[direction]
	if target.x < 0 or target.x >= 3 or target.y < 0 or target.y >= 3:
		return -1
	return target.y * 3 + target.x


static func count_owned(board: Array, owner_id: int) -> int:
	var total: int = 0
	for slot: Variant in board:
		if slot != null and int((slot as Dictionary)["owner"]) == owner_id:
			total += 1
	return total


static func is_board_full(board: Array) -> bool:
	if board.size() != 9:
		return false
	for slot: Variant in board:
		if slot == null:
			return false
	return true


static func first_empty_cell(board: Array) -> int:
	for cell_index: int in range(board.size()):
		if board[cell_index] == null:
			return cell_index
	return -1


static func choose_ai_move(board: Array, hand: Array, owner_id: int = OPPONENT_OWNER) -> Vector2i:
	var best_card_index: int = -1
	var best_cell_index: int = -1
	var best_capture_count: int = -1
	var best_boundary_power: int = -1

	for card_index: int in range(hand.size()):
		var card: Dictionary = hand[card_index]
		for cell_index: int in range(9):
			if not can_place(board, cell_index):
				continue
			var simulated_board: Array = board.duplicate(true)
			var captures: Array[int] = place_card(simulated_board, cell_index, card, owner_id)
			var capture_count: int = captures.size()
			var boundary_power: int = _get_boundary_power(card, cell_index)

			var is_better: bool = capture_count > best_capture_count
			if capture_count == best_capture_count:
				is_better = boundary_power > best_boundary_power
			if capture_count == best_capture_count and boundary_power == best_boundary_power:
				is_better = best_card_index < 0 or card_index < best_card_index
			if (
				capture_count == best_capture_count
				and boundary_power == best_boundary_power
				and card_index == best_card_index
			):
				is_better = best_cell_index < 0 or cell_index < best_cell_index

			if is_better:
				best_capture_count = capture_count
				best_boundary_power = boundary_power
				best_card_index = card_index
				best_cell_index = cell_index

	return Vector2i(best_card_index, best_cell_index)


static func _get_boundary_power(card: Dictionary, cell_index: int) -> int:
	var powers: Array = card["powers"]
	var total: int = 0
	for direction: int in range(4):
		if get_neighbor_index(cell_index, direction) < 0:
			total += int(powers[direction])
	return total
