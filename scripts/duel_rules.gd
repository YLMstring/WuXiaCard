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
const EFFECT_GATE_SELF_CASTRATION: StringName = &"self_castration"

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


static func get_would_flip_indices(
	board: Array,
	source_index: int,
	context: Dictionary = {}
) -> Array[int]:
	var targets: Array[int] = []
	if source_index < 0 or source_index >= board.size() or board[source_index] == null:
		return targets

	var source_slot: Dictionary = board[source_index]
	var source_card: Dictionary = source_slot.get("card", {})
	var source_gates: Array = _get_effect_gates(context, int(source_slot.get("owner", 0)))
	var unlimited_range: bool = Abilities.has_modifier(
		source_card,
		Catalog.MODIFIER_UNLIMITED_ATTACK_RANGE,
		source_gates
	)
	var candidate_indices: Array[int] = []
	if unlimited_range:
		for cell_index: int in range(board.size()):
			if cell_index != source_index:
				candidate_indices.append(cell_index)
	else:
		for direction: int in range(4):
			var neighbor_index: int = get_neighbor_index(source_index, direction)
			if neighbor_index >= 0:
				candidate_indices.append(neighbor_index)
				var distance_two_index: int = get_neighbor_index(neighbor_index, direction)
				if distance_two_index >= 0:
					candidate_indices.append(distance_two_index)
	var first_legal_only: bool = Abilities.has_modifier(
		source_card,
		Catalog.MODIFIER_STANDARD_ATTACK_FIRST_LEGAL_TARGET,
		source_gates
	)
	for target_index: int in candidate_indices:
		if can_attack_target(board, source_index, target_index, context):
			targets.append(target_index)
			if first_legal_only:
				break
	return targets


static func can_attack_target(
	board: Array,
	source_index: int,
	target_index: int,
	context: Dictionary = {}
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
	var source_gates: Array = _get_effect_gates(
		context,
		int(source_slot.get("owner", 0))
	)
	if (
		Abilities.has_modifier(
			source_card,
			Catalog.MODIFIER_ATTACK_REQUIRES_OTHER_ALLY,
			source_gates
		)
		and count_owned(board, int(source_slot.get("owner", 0))) < 2
	):
		return false
	return is_target_in_attack_range(board, source_index, target_index, context)


static func is_target_in_attack_range(
	board: Array,
	source_index: int,
	target_index: int,
	context: Dictionary = {}
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
	if source_index == target_index:
		return false
	var source_slot: Dictionary = board[source_index]
	var target_slot: Dictionary = board[target_index]
	var source_owner: int = int(source_slot.get("owner", 0))
	var target_owner: int = int(target_slot.get("owner", 0))
	var target_policy := StringName(
		context.get("attack_target_policy", Catalog.ATTACK_TARGET_ENEMIES_ONLY)
	)
	if bool(context.get("allow_allied_targets", false)):
		target_policy = Catalog.ATTACK_TARGET_ALL
	if (
		target_policy == Catalog.ATTACK_TARGET_ENEMIES_ONLY and source_owner == target_owner
		or target_policy == Catalog.ATTACK_TARGET_ALLIES_ONLY and source_owner != target_owner
		or target_policy not in [
			Catalog.ATTACK_TARGET_ENEMIES_ONLY,
			Catalog.ATTACK_TARGET_ALLIES_ONLY,
			Catalog.ATTACK_TARGET_ALL,
		]
	):
		return false
	var source_card: Dictionary = source_slot.get("card", {})
	var source_gates: Array = _get_effect_gates(
		context,
		int(source_slot.get("owner", 0))
	)
	var source_row: int = floori(float(source_index) / 3.0)
	var source_column: int = source_index % 3
	var target_row: int = floori(float(target_index) / 3.0)
	var target_column: int = target_index % 3
	var row_delta: int = target_row - source_row
	var column_delta: int = target_column - source_column
	var same_axis: bool = row_delta == 0 or column_delta == 0
	var unlimited_range: bool = Abilities.has_modifier(
		source_card,
		Catalog.MODIFIER_UNLIMITED_ATTACK_RANGE,
		source_gates
	)
	if not same_axis and not unlimited_range:
		return false
	if (
		not same_axis
		and not Abilities.has_modifier(
			source_card,
			Catalog.MODIFIER_NON_ORTHOGONAL_ATTACK_ANY_AXIS,
			source_gates
		)
	):
		return false
	var direction: int = -1
	var distance: int = 0
	if same_axis:
		if row_delta < 0:
			direction = TOP
		elif column_delta > 0:
			direction = RIGHT
		elif row_delta > 0:
			direction = BOTTOM
		elif column_delta < 0:
			direction = LEFT
		distance = maxi(absi(row_delta), absi(column_delta))
	if not unlimited_range and distance > 2:
		return false
	if not unlimited_range and distance == 2:
		if not Abilities.can_attack_at_orthogonal_distance_two_with_gates(
			source_card,
			source_gates
		):
			return false
		var intervening_index: int = get_neighbor_index(source_index, direction)
		var intervening_value: Variant = board[intervening_index]
		if intervening_value != null:
			var intervening_slot: Dictionary = intervening_value
			var intervening_is_ally: bool = (
				int(intervening_slot.get("owner", 0)) == int(source_slot.get("owner", 0))
			)
			if intervening_is_ally:
				if not Abilities.allows_intervening_ally_at_orthogonal_distance_two_with_gates(
					source_card,
					source_gates
				):
					return false
			elif not Abilities.allows_intervening_enemy_at_orthogonal_distance_two_with_gates(
				source_card,
				source_gates
			):
				return false
	if bool(context.get("skip_power_comparison", false)):
		return true
	var target_card: Dictionary = target_slot.get("card", {})
	var target_gates: Array = _get_effect_gates(
		context,
		int(target_slot.get("owner", 0))
	)
	var source_powers: Array = source_card.get("powers", [])
	var target_powers: Array = target_card.get("powers", [])
	if source_powers.size() != 4 or target_powers.size() != 4:
		return false
	var comparison_reversed: bool = (
		Abilities.has_modifier(
			source_card,
			Catalog.MODIFIER_POWER_COMPARISON_REVERSED,
			source_gates
		)
		or Abilities.has_modifier(
			target_card,
			Catalog.MODIFIER_POWER_COMPARISON_REVERSED,
			target_gates
		)
	)
	if same_axis:
		return _power_pair_wins(
			source_card,
			target_card,
			direction,
			OPPOSITE[direction],
			source_powers,
			target_powers,
			source_gates,
			target_gates,
			comparison_reversed
		)
	var vertical_direction: int = TOP if row_delta < 0 else BOTTOM
	var horizontal_direction: int = LEFT if column_delta < 0 else RIGHT
	return (
		_power_pair_wins(
			source_card,
			target_card,
			vertical_direction,
			OPPOSITE[vertical_direction],
			source_powers,
			target_powers,
			source_gates,
			target_gates,
			comparison_reversed
		)
		or _power_pair_wins(
			source_card,
			target_card,
			horizontal_direction,
			OPPOSITE[horizontal_direction],
			source_powers,
			target_powers,
			source_gates,
			target_gates,
			comparison_reversed
		)
	)


static func _power_pair_wins(
	source_card: Dictionary,
	target_card: Dictionary,
	attacking_direction: int,
	defending_direction: int,
	source_powers: Array,
	target_powers: Array,
	source_gates: Array,
	target_gates: Array,
	comparison_reversed: bool
) -> bool:
	var source_is_special_negative: bool = _has_four_negative_one_powers(source_powers)
	if source_is_special_negative:
		return false
	if _has_four_negative_one_powers(target_powers):
		return int(source_powers[attacking_direction]) >= 0
	var defending_power: int
	if Abilities.has_modifier(
		source_card,
		Catalog.MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE,
		source_gates
	):
		defending_power = Abilities.get_minimum_effective_defending_power(
			target_card,
			defending_direction,
			int(target_powers[defending_direction]),
			target_gates
		)
	else:
		defending_power = Abilities.get_effective_defending_power(
			target_card,
			defending_direction,
			int(target_powers[defending_direction]),
			target_gates
		)
	var attacking_power: int = int(source_powers[attacking_direction])
	return attacking_power < defending_power if comparison_reversed else attacking_power > defending_power


static func _has_four_negative_one_powers(powers: Array) -> bool:
	return powers.size() == 4 and powers.all(func(value: Variant) -> bool: return int(value) == -1)


static func _get_effect_gates(context: Dictionary, owner_id: int) -> Array:
	var by_owner_value: Variant = context.get("enabled_effect_gates_by_owner", null)
	if not by_owner_value is Dictionary:
		return []
	return (by_owner_value as Dictionary).get(owner_id, []) as Array


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
