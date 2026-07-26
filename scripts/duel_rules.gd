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


static func make_card(
	card_name: String,
	glyph: String,
	powers: Array[int],
	active_effects: Array = [],
	original_owner: int = 0,
	card_id: StringName = &""
) -> Dictionary:
	assert(powers.size() == 4, "Cards require top, right, bottom, and left powers.")
	var resolved_card_id: StringName = card_id
	if resolved_card_id == &"":
		resolved_card_id = StringName(card_name.to_snake_case())
	return {
		"instance_id": &"",
		"card_id": resolved_card_id,
		"name": card_name,
		"glyph": glyph,
		"powers": powers.duplicate(),
		"original_owner": original_owner,
		"active_effects": active_effects.duplicate(true),
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
	var captured: Array[int] = get_would_flip_indices(board, placed_index)
	if captured.is_empty():
		return captured
	var placed_owner: int = int((board[placed_index] as Dictionary)["owner"])
	for captured_index: int in captured:
		(board[captured_index] as Dictionary)["owner"] = placed_owner
	return captured


static func get_would_flip_indices(board: Array, source_index: int) -> Array[int]:
	var targets: Array[int] = []
	if source_index < 0 or source_index >= board.size() or board[source_index] == null:
		return targets

	for direction: int in range(4):
		var neighbor_index: int = get_neighbor_index(source_index, direction)
		if can_attack_target(board, source_index, neighbor_index):
			targets.append(neighbor_index)
	return targets


static func can_attack_target(
	board: Array,
	source_index: int,
	target_index: int,
	_context: Dictionary = {}
) -> bool:
	if (
		board.size() != 9
		or source_index < 0
		or source_index >= board.size()
		or target_index < 0
		or target_index >= board.size()
		or board[source_index] == null
		or board[target_index] == null
	):
		return false
	var direction: int = -1
	for candidate_direction: int in range(DIRECTIONS.size()):
		if get_neighbor_index(source_index, candidate_direction) == target_index:
			direction = candidate_direction
			break
	if direction < 0:
		return false
	var source_slot: Dictionary = board[source_index]
	var target_slot: Dictionary = board[target_index]
	if int(source_slot.get("owner", 0)) == int(target_slot.get("owner", 0)):
		return false
	var source_card: Dictionary = source_slot.get("card", {})
	var target_card: Dictionary = target_slot.get("card", {})
	var source_powers: Array = source_card.get("powers", [])
	var target_powers: Array = target_card.get("powers", [])
	if source_powers.size() != 4 or target_powers.size() != 4:
		return false
	return int(source_powers[direction]) > int(target_powers[OPPOSITE[direction]])


static func get_neighbor_index(cell_index: int, direction: int) -> int:
	if cell_index < 0 or cell_index >= 9 or direction < 0 or direction >= DIRECTIONS.size():
		return -1
	var row: int = floori(float(cell_index) / 3.0)
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
			var boundary_power: int = get_boundary_power(card, cell_index)

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


static func get_boundary_power(card: Dictionary, cell_index: int) -> int:
	var powers: Array = card["powers"]
	var total: int = 0
	for direction: int in range(4):
		if get_neighbor_index(cell_index, direction) < 0:
			total += int(powers[direction])
	return total
