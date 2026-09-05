class_name DuelRules
extends RefCounted

const TOP: int = 0
const RIGHT: int = 1
const BOTTOM: int = 2
const LEFT: int = 3

const PLAYER_OWNER: int = 1
const OPPONENT_OWNER: int = 2
const EFFECT_GATE_SELF_CASTRATION: StringName = &"self_castration"

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]


static func make_card(
	card_name: String,
	glyph: String,
	powers: Array[int],
	active_abilities: Array = [],
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
		"active_abilities": active_abilities.duplicate(true),
		"revealed_to_owner_ids": [original_owner] if original_owner in [PLAYER_OWNER, OPPONENT_OWNER] else [],
	}


static func empty_board() -> Array:
	var board: Array = []
	board.resize(9)
	board.fill(null)
	return board


static func can_place(board: Array, cell_index: int) -> bool:
	return cell_index >= 0 and cell_index < 9 and board.size() == 9 and board[cell_index] == null


static func has_special_negative_powers(card: Dictionary) -> bool:
	var powers: Array = card.get("powers", [])
	return powers.size() == 4 and powers == [-1, -1, -1, -1]


static func can_change_powers(card: Dictionary) -> bool:
	return not has_special_negative_powers(card)


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


static func first_empty_cell(board: Array) -> int:
	for cell_index: int in range(board.size()):
		if board[cell_index] == null:
			return cell_index
	return -1
