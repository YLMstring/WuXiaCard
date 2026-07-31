extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Selector = preload("res://scripts/duel_card_selector.gd")
const StateData = preload("res://scripts/duel_state.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_order_and_filters()
	_test_declared_zone_order_and_limit()
	_test_revalidation_ignores_movement()
	_test_revalidation_skips_failed_conditions()
	if _failures == 0:
		print("DUEL_CARD_SELECTOR_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"DUEL_CARD_SELECTOR_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_order_and_filters() -> void:
	var source: Dictionary = _card(&"source", "心法")
	var hand_sword: Dictionary = _card(&"hand_sword", "剑法")
	var hand_method: Dictionary = _card(&"hand_method", "心法")
	var enemy_sword: Dictionary = _card(&"enemy_sword", "剑法")
	var board_sword: Dictionary = _card(&"board_sword", "剑法")
	var enemy_board_sword: Dictionary = _card(&"enemy_board_sword", "剑法")
	var board: Array = Rules.empty_board()
	board[0] = {"owner": Rules.PLAYER_OWNER, "card": board_sword}
	board[4] = {"owner": Rules.PLAYER_OWNER, "card": source}
	board[8] = {"owner": Rules.OPPONENT_OWNER, "card": enemy_board_sword}
	var state := StateData.new(
		board,
		[hand_sword, hand_method],
		[enemy_sword]
	)
	var selected: Array[StringName] = Selector.snapshot(
		state,
		{
			"zones": [Catalog.CARD_ZONE_HAND, Catalog.CARD_ZONE_BOARD],
			"conditions": [
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY},
				{
					"type": Catalog.CONDITION_SELECTED_CARD_WEAPON_IS,
					"weapon": "剑法",
				},
			],
		},
		&"source"
	)
	_check(
		selected == [&"hand_sword", &"board_sword"],
		"Selector visits allied hand before row-major board and filters enemy/non-weapon cards"
	)


func _test_declared_zone_order_and_limit() -> void:
	var source: Dictionary = _card(&"source", "心法")
	var hand_one: Dictionary = _card(&"hand_one", "剑法")
	var board_one: Dictionary = _card(&"board_one", "剑法")
	var board_two: Dictionary = _card(&"board_two", "剑法")
	var board: Array = Rules.empty_board()
	board[0] = {"owner": Rules.PLAYER_OWNER, "card": board_one}
	board[4] = {"owner": Rules.PLAYER_OWNER, "card": source}
	board[8] = {"owner": Rules.PLAYER_OWNER, "card": board_two}
	var state := StateData.new(board, [hand_one], [])
	var selected: Array[StringName] = Selector.snapshot(
		state,
		{
			"zones": [Catalog.CARD_ZONE_BOARD, Catalog.CARD_ZONE_HAND],
			"conditions": [
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY},
				{"type": Catalog.CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
			],
			"limit": 2,
		},
		&"source"
	)
	_check(
		selected == [&"board_one", &"board_two"],
		"Selector honors declared zone order, board order, self exclusion, and initial limit"
	)


func _test_revalidation_ignores_movement() -> void:
	var source: Dictionary = _card(&"source", "心法")
	var target: Dictionary = _card(&"target", "剑法")
	var board: Array = Rules.empty_board()
	board[0] = {"owner": Rules.PLAYER_OWNER, "card": target}
	board[4] = {"owner": Rules.PLAYER_OWNER, "card": source}
	var state := StateData.new(board)
	var conditions: Array = [
		{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY},
		{"type": Catalog.CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
	]
	var selected: Array[StringName] = Selector.snapshot(
		state,
		{"zones": [Catalog.CARD_ZONE_BOARD], "conditions": conditions},
		&"source"
	)
	state.board[0] = null
	state.get_hand(Rules.PLAYER_OWNER).append(target)
	var revalidated: Dictionary = Selector.revalidate(
		state,
		selected[0],
		&"source",
		conditions
	)
	_check(
		StringName(revalidated.get("zone", &"")) == Catalog.CARD_ZONE_HAND,
		"Selected card remains valid after moving to another zone when conditions still match"
	)


func _test_revalidation_skips_failed_conditions() -> void:
	var source: Dictionary = _card(&"source", "心法")
	var target: Dictionary = _card(&"target", "剑法")
	var board: Array = Rules.empty_board()
	board[0] = {"owner": Rules.PLAYER_OWNER, "card": target}
	board[4] = {"owner": Rules.PLAYER_OWNER, "card": source}
	var state := StateData.new(board)
	var conditions: Array = [
		{"type": Catalog.CONDITION_SELECTED_CARD_IS_ALLY},
		{
			"type": Catalog.CONDITION_SELECTED_CARD_WEAPON_IS,
			"weapon": "剑法",
		},
	]
	state.board[0]["owner"] = Rules.OPPONENT_OWNER
	_check(
		Selector.revalidate(state, &"target", &"source", conditions).is_empty(),
		"Ownership change skips a selected card whose ally condition no longer matches"
	)
	state.board[0]["owner"] = Rules.PLAYER_OWNER
	((state.board[0] as Dictionary).get("card", {}) as Dictionary)["weapon"] = "心法"
	_check(
		Selector.revalidate(state, &"target", &"source", conditions).is_empty(),
		"Weapon change skips a selected card whose weapon condition no longer matches"
	)
	state.board[0] = null
	_check(
		Selector.revalidate(state, &"target", &"source", conditions).is_empty(),
		"Missing selected instance is skipped as no effect"
	)


func _card(instance_id: StringName, weapon: String) -> Dictionary:
	var card: Dictionary = Rules.make_card(
		String(instance_id),
		"测",
		[1, 1, 1, 1],
		[],
		Rules.PLAYER_OWNER
	)
	card["instance_id"] = instance_id
	card["weapon"] = weapon
	card["ki"] = 0
	return card


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
