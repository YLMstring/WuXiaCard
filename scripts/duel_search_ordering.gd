class_name DuelSearchOrdering
extends RefCounted

const ActionData = preload("res://scripts/duel_action.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const StateData = preload("res://scripts/duel_state.gd")


static func order_actions(
	state: StateData,
	actions: Array[ActionData],
	principal_variation_key: String = "",
	transposition_key: String = "",
	history: Dictionary = {}
) -> Array[ActionData]:
	var records: Array[Dictionary] = []
	for action: ActionData in actions:
		var canonical_key: String = action.canonical_key()
		records.append({
			"action": action,
			"is_principal_variation": canonical_key == principal_variation_key,
			"is_transposition_best": canonical_key == transposition_key,
			"history": int(history.get(history_key(action, state), 0)),
			"structural": structural_score(state, action),
			"canonical_key": canonical_key,
		})
	records.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_pv: bool = bool(left["is_principal_variation"])
		var right_pv: bool = bool(right["is_principal_variation"])
		if left_pv != right_pv:
			return left_pv
		var left_tt: bool = bool(left["is_transposition_best"])
		var right_tt: bool = bool(right["is_transposition_best"])
		if left_tt != right_tt:
			return left_tt
		var left_history: int = int(left["history"])
		var right_history: int = int(right["history"])
		if left_history != right_history:
			return left_history > right_history
		var left_structural: int = int(left["structural"])
		var right_structural: int = int(right["structural"])
		if left_structural != right_structural:
			return left_structural > right_structural
		return String(left["canonical_key"]) < String(right["canonical_key"])
	)
	var ordered: Array[ActionData] = []
	for record: Dictionary in records:
		ordered.append(record["action"] as ActionData)
	return ordered


static func history_key(action: ActionData, state: StateData = null) -> String:
	if action == null:
		return "none"
	return "%s|%s|%d|%s|%d|%d|%s" % [
		String(action.action_type),
		String(action.source_zone),
		action.source_index,
		String(action.target_kind),
		action.target_index,
		action.activation_index,
		_source_fingerprint(state, action),
	]


static func _source_fingerprint(state: StateData, action: ActionData) -> String:
	if state == null or action == null:
		return "generic"
	var card: Dictionary = {}
	if action.source_zone == ActionData.SOURCE_HAND:
		var hand: Array = state.get_hand(state.active_player)
		if action.source_index >= 0 and action.source_index < hand.size():
			card = hand[action.source_index] as Dictionary
	elif action.source_zone == ActionData.SOURCE_BOARD:
		if action.source_index >= 0 and action.source_index < state.board.size():
			var slot_value: Variant = state.board[action.source_index]
			if slot_value != null:
				card = (slot_value as Dictionary).get("card", {}) as Dictionary
	if card.is_empty():
		return "missing"
	var power_parts: Array[String] = []
	for power_value: Variant in card.get("powers", []):
		power_parts.append(str(int(power_value)))
	return "p:%s|k:%d|a:%d" % [
		",".join(power_parts),
		int(card.get("ki", 0)),
		(card.get("active_abilities", []) as Array).size(),
	]


static func structural_score(state: StateData, action: ActionData) -> int:
	if state == null or action == null:
		return 0
	if action.action_type == ActionData.TYPE_ACTIVATE:
		return 500
	if action.action_type != ActionData.TYPE_PLAY:
		return 0
	var hand: Array = state.get_hand(state.active_player)
	if action.source_index < 0 or action.source_index >= hand.size():
		return 0
	var card: Dictionary = hand[action.source_index] as Dictionary
	var powers: Array = card.get("powers", [0, 0, 0, 0]) as Array
	var score: int = 20 if action.target_index == 4 else 10 if action.target_index in [0, 2, 6, 8] else 0
	for direction: int in range(4):
		var neighbor_index: int = Rules.get_neighbor_index(action.target_index, direction)
		if neighbor_index < 0 or neighbor_index >= state.board.size():
			continue
		var neighbor_value: Variant = state.board[neighbor_index]
		if neighbor_value == null:
			continue
		var neighbor: Dictionary = neighbor_value as Dictionary
		if int(neighbor.get("owner", 0)) == state.active_player:
			score += 5
			continue
		score += 25
		var enemy_card: Dictionary = neighbor.get("card", {}) as Dictionary
		var enemy_powers: Array = enemy_card.get("powers", [0, 0, 0, 0]) as Array
		if (
			direction < powers.size()
			and Rules.OPPOSITE[direction] < enemy_powers.size()
			and int(powers[direction]) > int(enemy_powers[Rules.OPPOSITE[direction]])
		):
			score += 100
	return score
