class_name DuelRules
extends RefCounted

const Abilities = preload("res://scripts/duel_abilities.gd")
const Catalog = preload("res://scripts/card_catalog.gd")

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
		if neighbor_index >= 0:
			var distance_two_index: int = get_neighbor_index(neighbor_index, direction)
			if can_attack_target(board, source_index, distance_two_index):
				targets.append(distance_two_index)
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
		or board[source_index] == null
	):
		return false
	var source_slot: Dictionary = board[source_index]
	var source_card: Dictionary = source_slot.get("card", {})
	if (
		Abilities.has_modifier(source_card, Catalog.MODIFIER_ATTACK_REQUIRES_OTHER_ALLY)
		and count_owned(board, int(source_slot.get("owner", 0))) < 2
	):
		return false
	return is_target_in_attack_range(board, source_index, target_index)


static func is_target_in_attack_range(
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
	var distance: int = 0
	for candidate_direction: int in range(DIRECTIONS.size()):
		var neighbor_index: int = get_neighbor_index(source_index, candidate_direction)
		if neighbor_index == target_index:
			direction = candidate_direction
			distance = 1
			break
		if (
			neighbor_index >= 0
			and get_neighbor_index(neighbor_index, candidate_direction) == target_index
		):
			direction = candidate_direction
			distance = 2
			break
	if direction < 0:
		return false
	var source_slot: Dictionary = board[source_index]
	var target_slot: Dictionary = board[target_index]
	if int(source_slot.get("owner", 0)) == int(target_slot.get("owner", 0)):
		return false
	var source_card: Dictionary = source_slot.get("card", {})
	if distance == 2:
		if not Abilities.can_attack_at_orthogonal_distance_two(source_card):
			return false
		var intervening_index: int = get_neighbor_index(source_index, direction)
		var intervening_value: Variant = board[intervening_index]
		if intervening_value != null:
			var intervening_slot: Dictionary = intervening_value
			if (
				int(intervening_slot.get("owner", 0)) != int(source_slot.get("owner", 0))
				or not Abilities.allows_intervening_ally_at_orthogonal_distance_two(source_card)
			):
				return false
	var target_card: Dictionary = target_slot.get("card", {})
	var source_powers: Array = source_card.get("powers", [])
	var target_powers: Array = target_card.get("powers", [])
	if source_powers.size() != 4 or target_powers.size() != 4:
		return false
	var defending_direction: int = OPPOSITE[direction]
	var defending_power: int
	if Abilities.has_modifier(
		source_card,
		Catalog.MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE
	):
		defending_power = Abilities.get_minimum_effective_defending_power(
			target_card,
			defending_direction,
			int(target_powers[defending_direction])
		)
	else:
		defending_power = Abilities.get_effective_defending_power(
			target_card,
			defending_direction,
			int(target_powers[defending_direction])
		)
	return int(source_powers[direction]) > defending_power


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
