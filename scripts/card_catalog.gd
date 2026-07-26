class_name CardCatalog
extends RefCounted

const ACTIVATION_DRAG_TO_TARGET: StringName = &"drag_to_target"
const TARGET_ADJACENT_EMPTY_BOARD: StringName = &"adjacent_empty_board"
const TRIGGER_CARD_SUMMONED: StringName = &"card_summoned"
const TRIGGER_CARD_AFTER_SUMMONED: StringName = &"card_after_summoned"
const CARD_BE_ATTACKED: StringName = &"card_be_attacked"
const CARD_AFTER_FLIPPED: StringName = &"card_after_flipped"
const TRIGGER_END_OWNER_TURN: StringName = &"end_owner_turn"
const CONDITION_KI_AT_LEAST: StringName = &"ki_at_least"
const CONDITION_TRIGGER_CARD_IS_ENEMY: StringName = &"trigger_card_is_enemy"
const CONDITION_TRIGGER_CARD_IN_RANGE: StringName = &"trigger_card_in_range"
const CONDITION_TRIGGER_CARD_IS_SELF: StringName = &"trigger_card_is_self"
const CONDITION_ATTACKER_CARD_IS_SELF: StringName = &"attacker_card_is_self"
const CONDITION_TURN_OWNER_IS_SELF: StringName = &"turn_owner_is_self"
const ACTION_DRAW_CARDS: StringName = &"draw_cards"
const ACTION_EXILE_ATTACKED_CARD: StringName = &"exile_attacked_card"
const ACTION_ATTACK_TRIGGER_CARD: StringName = &"attack_trigger_card"
const ACTION_GAIN_KI: StringName = &"gain_ki"
const ACTION_SPEND_KI: StringName = &"spend_ki"
const ACTION_SPEND_ALL_KI: StringName = &"spend_all_ki"
const ACTION_REQUEST_EXTRA_TURN: StringName = &"request_extra_turn"
const ACTION_MOVE_SELF_TO_TARGET: StringName = &"move_self_to_target"
const ACTION_STANDARD_ATTACK_WITH_SELF: StringName = &"standard_attack_with_self"
const ACTION_RESULT_APPLIED: StringName = &"applied"
const ACTION_RESULT_NO_EFFECT: StringName = &"no_effect"
const ACTION_RESULT_INVALID_CONTEXT: StringName = &"invalid_context"
const STOP_RULE: StringName = &"stop_rule"
const KNOWN_ACTIVATION_INPUTS: Array[StringName] = [ACTIVATION_DRAG_TO_TARGET]
const KNOWN_TARGET_RULES: Array[StringName] = [TARGET_ADJACENT_EMPTY_BOARD]
const KNOWN_TRIGGER_EVENTS: Array[StringName] = [
	TRIGGER_CARD_SUMMONED,
	TRIGGER_CARD_AFTER_SUMMONED,
	CARD_BE_ATTACKED,
	CARD_AFTER_FLIPPED,
	TRIGGER_END_OWNER_TURN,
]
const KNOWN_TRIGGER_CONDITIONS: Array[StringName] = [
	CONDITION_KI_AT_LEAST,
	CONDITION_TRIGGER_CARD_IS_ENEMY,
	CONDITION_TRIGGER_CARD_IN_RANGE,
	CONDITION_TRIGGER_CARD_IS_SELF,
	CONDITION_ATTACKER_CARD_IS_SELF,
	CONDITION_TURN_OWNER_IS_SELF,
]
const KNOWN_ACTIONS: Array[StringName] = [
	ACTION_DRAW_CARDS,
	ACTION_EXILE_ATTACKED_CARD,
	ACTION_ATTACK_TRIGGER_CARD,
	ACTION_GAIN_KI,
	ACTION_SPEND_KI,
	ACTION_SPEND_ALL_KI,
	ACTION_REQUEST_EXTRA_TURN,
	ACTION_MOVE_SELF_TO_TARGET,
	ACTION_STANDARD_ATTACK_WITH_SELF,
]

const ALL_CARD_IDS: Array[StringName] = [
	&"CangSongYingKe1",
	&"CangSongYingKe2",
	&"gate_general",
	&"meng_huo",
	&"jiang_wei",
	&"fa_zheng",
	&"fire_envoy",
	&"tiger_general",
	&"strategist",
	&"sun_zan",
]

const _CARD_DEFINITIONS: Dictionary = {
	&"CangSongYingKe1": {
		"id": &"CangSongYingKe1",
		"glyph": "苍松迎客",
		"picture": "res://pics/LKT010_568.png",
		"sect": "华山派",
		"tier": 1,
		"weapon": "剑法",
		"description": "",
		"flavor": "华山剑法的绝招。华山上有数株古松，枝叶向下伸展，有如张臂欢迎上山的游客一般，称为“迎客松”。这招“苍松迎客”，便是从这几株古松的形状上变化而出。",
		"powers": [4, 7, 7, 4],
		"abilities": [],
	},
	&"CangSongYingKe2": {
		"id": &"CangSongYingKe2",
		"glyph": "苍松迎客",
		"picture": "res://pics/LKT010_568.png",
		"sect": "华山派",
		"tier": 2,
		"weapon": "剑法",
		"description": "对手招式进场时，若我可以，对其发起攻击。",
		"flavor": "华山剑法的绝招。华山上有数株古松，枝叶向下伸展，有如张臂欢迎上山的游客一般，称为“迎客松”。这招“苍松迎客”，便是从这几株古松的形状上变化而出。",
		"powers": [4, 7, 7, 4],
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_CARD_SUMMONED,
						"conditions": [
							{"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
							{"type": CONDITION_TRIGGER_CARD_IN_RANGE},
						],
						"actions": [
							{"type": ACTION_ATTACK_TRIGGER_CARD},
						],
					},
				],
			},
		],
	},
	&"gate_general": {
		"id": &"gate_general",
		"glyph": "关",
		"picture": "res://pics/LKT010_002.png",
		"sect": "",
		"tier": 1,
		"weapon": "",
		"description": "",
		"flavor": "",
		"powers": [7, 7, 7, 7],
		"abilities": [
			{
				"retained_on_flip": true,
				"triggers": [
					{
						"event": CARD_BE_ATTACKED,
						"conditions": [
							{"type": CONDITION_ATTACKER_CARD_IS_SELF},
						],
						"actions": [
							{"type": ACTION_EXILE_ATTACKED_CARD},
						],
					},
				],
			},
		],
	},
	&"meng_huo": {
		"id": &"meng_huo",
		"glyph": "孟",
		"picture": "res://pics/LKT010_003.png",
		"sect": "",
		"tier": 1,
		"weapon": "",
		"description": "",
		"flavor": "",
		"powers": [8, 7, 2, 3],
		"abilities": [
			{
				"triggers": [
					{
						"event": CARD_AFTER_FLIPPED,
						"conditions": [
							{"type": CONDITION_ATTACKER_CARD_IS_SELF},
						],
						"actions": [
							{"type": ACTION_GAIN_KI, "amount": 1},
						],
					},
					{
						"event": TRIGGER_END_OWNER_TURN,
						"conditions": [
							{"type": CONDITION_TURN_OWNER_IS_SELF},
							{"type": CONDITION_KI_AT_LEAST, "amount": 1},
						],
						"actions": [
							{"type": ACTION_SPEND_ALL_KI},
							{"type": ACTION_REQUEST_EXTRA_TURN},
						],
					},
				],
			},
		],
	},
	&"jiang_wei": {
		"id": &"jiang_wei",
		"glyph": "姜",
		"picture": "res://pics/LKT010_004.png",
		"sect": "",
		"tier": 1,
		"weapon": "",
		"description": "",
		"flavor": "",
		"powers": [6, 6, 6, 6],
		"starting_ki": 1,
		"abilities": [
			{
				"activation": {
					"input": ACTIVATION_DRAG_TO_TARGET,
					"target_rule": TARGET_ADJACENT_EMPTY_BOARD,
					"costs": [
						{"type": ACTION_SPEND_KI, "amount": 1},
					],
					"actions": [
						{"type": ACTION_MOVE_SELF_TO_TARGET},
						{"type": ACTION_STANDARD_ATTACK_WITH_SELF},
					],
				},
			},
		],
	},
	&"fa_zheng": {
		"id": &"fa_zheng",
		"glyph": "法",
		"picture": "res://pics/LKT010_005.png",
		"sect": "",
		"tier": 1,
		"weapon": "",
		"description": "",
		"flavor": "",
		"powers": [5, 4, 4, 3],
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_CARD_AFTER_SUMMONED,
						"conditions": [
							{"type": CONDITION_TRIGGER_CARD_IS_SELF},
						],
						"actions": [
							{"type": ACTION_DRAW_CARDS, "amount": 2},
						],
					},
				],
			},
		],
	},
	&"fire_envoy": {
		"id": &"fire_envoy",
		"glyph": "火",
		"picture": "res://pics/LKT010_007.png",
		"sect": "",
		"tier": 1,
		"weapon": "",
		"description": "",
		"flavor": "",
		"powers": [5, 5, 4, 4],
		"abilities": [],
	},
	&"tiger_general": {
		"id": &"tiger_general",
		"glyph": "虎",
		"picture": "res://pics/LKT010_008.png",
		"sect": "",
		"tier": 1,
		"weapon": "",
		"description": "",
		"flavor": "",
		"powers": [3, 4, 8, 8],
		"abilities": [
			{
				"retained_on_flip": true,
				"triggers": [
					{
						"event": CARD_BE_ATTACKED,
						"conditions": [
							{"type": CONDITION_ATTACKER_CARD_IS_SELF},
						],
						"actions": [
							{"type": ACTION_EXILE_ATTACKED_CARD},
						],
					},
				],
			},
		],
	},
	&"strategist": {
		"id": &"strategist",
		"glyph": "策",
		"picture": "res://pics/LKT010_009.png",
		"sect": "",
		"tier": 1,
		"weapon": "",
		"description": "",
		"flavor": "",
		"powers": [4, 4, 4, 4],
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_CARD_AFTER_SUMMONED,
						"conditions": [
							{"type": CONDITION_TRIGGER_CARD_IS_SELF},
						],
						"actions": [
							{"type": ACTION_DRAW_CARDS, "amount": 2},
						],
					},
				],
			},
		],
	},
	&"sun_zan": {
		"id": &"sun_zan",
		"glyph": "孙",
		"picture": "res://pics/LKT010_010.png",
		"sect": "",
		"tier": 1,
		"weapon": "",
		"description": "",
		"flavor": "",
		"powers": [3, 5, 8, 8],
		"starting_ki": 1,
		"abilities": [
			{
				"activation": {
					"input": ACTIVATION_DRAG_TO_TARGET,
					"target_rule": TARGET_ADJACENT_EMPTY_BOARD,
					"costs": [
						{"type": ACTION_SPEND_KI, "amount": 1},
					],
					"actions": [
						{"type": ACTION_MOVE_SELF_TO_TARGET},
						{"type": ACTION_STANDARD_ATTACK_WITH_SELF},
					],
				},
			},
		],
	},
}


static func has_card(card_id: StringName) -> bool:
	return _CARD_DEFINITIONS.has(card_id)


static func get_all_card_ids() -> Array[StringName]:
	return ALL_CARD_IDS.duplicate()


static func get_definition(card_id: StringName) -> Dictionary:
	assert(has_card(card_id), "Unknown card ID: %s" % card_id)
	var definition: Dictionary = _CARD_DEFINITIONS.get(card_id, {})
	return definition.duplicate(true)


static func create_instance(
	card_id: StringName,
	original_owner: int,
	instance_id: StringName
) -> Dictionary:
	var definition: Dictionary = get_definition(card_id)
	return {
		"instance_id": instance_id,
		"card_id": card_id,
		"glyph": String(definition["glyph"]),
		"picture": String(definition["picture"]),
		"sect": String(definition["sect"]),
		"tier": int(definition["tier"]),
		"weapon": String(definition["weapon"]),
		"description": String(definition["description"]),
		"flavor": String(definition["flavor"]),
		"powers": (definition["powers"] as Array).duplicate(),
		"original_owner": original_owner,
		"ki": int(definition.get("starting_ki", 0)),
		"active_abilities": _normalize_abilities(definition["abilities"] as Array),
	}


static func validate_ability(ability: Dictionary, card_id: StringName = &"fixture") -> Array[String]:
	var errors: Array[String] = []
	_validate_ability(card_id, ability, errors)
	return errors


static func validate_definition(
	definition: Dictionary,
	card_id: StringName = &"fixture"
) -> Array[String]:
	var errors: Array[String] = []
	_validate_definition(card_id, definition, errors)
	return errors


static func validate_catalog() -> Array[String]:
	var errors: Array[String] = []
	var observed_ids: Dictionary = {}
	for card_id: StringName in ALL_CARD_IDS:
		if observed_ids.has(card_id):
			errors.append("Duplicate catalog ID: %s" % card_id)
			continue
		observed_ids[card_id] = true
		if not _CARD_DEFINITIONS.has(card_id):
			errors.append("Missing definition for ID: %s" % card_id)
			continue
		_validate_definition(card_id, _CARD_DEFINITIONS[card_id] as Dictionary, errors)
	for raw_key: Variant in _CARD_DEFINITIONS.keys():
		var definition_id := StringName(raw_key)
		if not observed_ids.has(definition_id):
			errors.append("Definition is absent from ALL_CARD_IDS: %s" % definition_id)
	return errors


static func _validate_definition(
	card_id: StringName,
	definition: Dictionary,
	errors: Array[String]
) -> void:
	if card_id == &"":
		errors.append("Card ID cannot be empty")
	if StringName(definition.get("id", &"")) != card_id:
		errors.append("Definition ID does not match key: %s" % card_id)
	if definition.has("name"):
		errors.append("Card %s still declares retired name metadata" % card_id)
	var glyph_value: Variant = definition.get("glyph", null)
	if typeof(glyph_value) != TYPE_STRING:
		errors.append("Card %s requires a String glyph" % card_id)
	else:
		var glyph_length: int = (glyph_value as String).length()
		if glyph_length < 1 or glyph_length > 7:
			errors.append("Card %s glyph must contain 1 to 7 characters" % card_id)
	var picture_value: Variant = definition.get("picture", null)
	if typeof(picture_value) != TYPE_STRING or String(picture_value).is_empty():
		errors.append("Card %s requires a non-empty String picture" % card_id)
	elif not ResourceLoader.exists(String(picture_value)):
		errors.append("Card %s picture resource does not exist: %s" % [card_id, picture_value])
	for metadata_key: StringName in [&"sect", &"weapon", &"description", &"flavor"]:
		if not definition.has(metadata_key) or typeof(definition[metadata_key]) != TYPE_STRING:
			errors.append("Card %s requires String metadata %s" % [card_id, metadata_key])
	var tier_value: Variant = definition.get("tier", null)
	if typeof(tier_value) != TYPE_INT or int(tier_value) < 1:
		errors.append("Card %s requires an integer tier of at least 1" % card_id)
	var powers: Array = definition.get("powers", [])
	if powers.size() != 4:
		errors.append("Card %s requires four powers" % card_id)
	for power: Variant in powers:
		if typeof(power) != TYPE_INT:
			errors.append("Card %s has a non-integer power" % card_id)
	if definition.has("effects"):
		errors.append("Card %s still declares retired effects data" % card_id)
	var abilities_value: Variant = definition.get("abilities", null)
	var starting_ki: Variant = definition.get("starting_ki", 0)
	if typeof(starting_ki) != TYPE_INT or int(starting_ki) < 0:
		errors.append("Card %s requires a non-negative integer starting_ki" % card_id)
	if not abilities_value is Array:
		errors.append("Card %s requires an abilities array" % card_id)
		return
	var activation_count: int = 0
	for ability_value: Variant in abilities_value as Array:
		if not ability_value is Dictionary:
			errors.append("Card %s has a non-dictionary ability" % card_id)
			continue
		var ability: Dictionary = ability_value
		if ability.has("activation"):
			activation_count += 1
		_validate_ability(card_id, ability, errors)
	if activation_count > 1:
		errors.append("Card %s declares more than one activation" % card_id)


static func _normalize_abilities(raw_abilities: Array) -> Array:
	var normalized_abilities: Array = []
	for ability_value: Variant in raw_abilities:
		var ability: Dictionary = (ability_value as Dictionary).duplicate(true)
		if not ability.has("retained_on_flip"):
			ability["retained_on_flip"] = false
		normalized_abilities.append(ability)
	return normalized_abilities


static func _validate_ability(
	card_id: StringName,
	ability: Dictionary,
	errors: Array[String]
) -> void:
	if ability.has("id"):
		errors.append("Card %s ability must not declare an id" % card_id)
	for key: Variant in ability.keys():
		if StringName(key) not in [&"retained_on_flip", &"triggers", &"activation"]:
			errors.append("Card %s ability has unsupported field %s" % [card_id, key])
	if ability.has("retained_on_flip") and typeof(ability["retained_on_flip"]) != TYPE_BOOL:
		errors.append("Card %s ability has non-Boolean retained_on_flip" % card_id)
	if not ability.has("triggers") and not ability.has("activation"):
		errors.append("Card %s ability requires triggers or activation" % card_id)
	if ability.has("triggers"):
		_validate_triggers(card_id, ability["triggers"], errors)
	if ability.has("activation"):
		_validate_activation(card_id, ability["activation"], errors)


static func _validate_triggers(card_id: StringName, trigger_value: Variant, errors: Array[String]) -> void:
	if not trigger_value is Array:
		errors.append("Card %s trigger ability requires a trigger array" % card_id)
		return
	var triggers: Array = trigger_value
	if triggers.is_empty():
		errors.append("Card %s trigger ability requires at least one trigger" % card_id)
		return
	for trigger_value_item: Variant in triggers:
		if not trigger_value_item is Dictionary:
			errors.append("Card %s has a non-dictionary trigger" % card_id)
			continue
		_validate_trigger(card_id, trigger_value_item as Dictionary, errors)


static func _validate_trigger(card_id: StringName, trigger: Dictionary, errors: Array[String]) -> void:
	var event_id := StringName(trigger.get("event", &""))
	if event_id not in KNOWN_TRIGGER_EVENTS:
		errors.append("Card %s uses unknown trigger event %s" % [card_id, event_id])
	for key: Variant in trigger.keys():
		if StringName(key) not in [&"event", &"conditions", &"actions"]:
			errors.append("Card %s trigger %s has unsupported field %s" % [card_id, event_id, key])
	var conditions_value: Variant = trigger.get("conditions", [])
	if not conditions_value is Array:
		errors.append("Card %s trigger %s requires a conditions array" % [card_id, event_id])
	else:
		for condition_value: Variant in conditions_value as Array:
			if not condition_value is Dictionary:
				errors.append("Card %s trigger %s has a non-dictionary condition" % [card_id, event_id])
				continue
			_validate_condition(card_id, "trigger %s" % event_id, condition_value as Dictionary, errors)
	var actions_value: Variant = trigger.get("actions", null)
	if not actions_value is Array or (actions_value as Array).is_empty():
		errors.append("Card %s trigger %s requires a non-empty action array" % [card_id, event_id])
		return
	for action_value: Variant in actions_value as Array:
		if not action_value is Dictionary:
			errors.append("Card %s trigger %s has a non-dictionary action" % [card_id, event_id])
			continue
		_validate_action(card_id, "trigger %s" % event_id, action_value as Dictionary, false, errors)


static func _validate_condition(
	card_id: StringName,
	context_name: String,
	condition: Dictionary,
	errors: Array[String]
) -> void:
	var condition_type := StringName(condition.get("type", &""))
	if condition_type not in KNOWN_TRIGGER_CONDITIONS:
		errors.append("Card %s %s uses unknown condition %s" % [card_id, context_name, condition_type])
		return
	var allowed_keys: Array[StringName] = [&"type"]
	if condition_type == CONDITION_KI_AT_LEAST:
		allowed_keys.append(&"amount")
		var threshold: Variant = condition.get("amount", null)
		if typeof(threshold) != TYPE_INT or int(threshold) < 0:
			errors.append("Card %s %s requires a non-negative integer ki_at_least amount" % [card_id, context_name])
	for key: Variant in condition.keys():
		if StringName(key) not in allowed_keys:
			errors.append("Card %s %s condition %s has unsupported field %s" % [card_id, context_name, condition_type, key])


static func _validate_activation(
	card_id: StringName,
	activation_value: Variant,
	errors: Array[String]
) -> void:
	if not activation_value is Dictionary:
		errors.append("Card %s activation must be a Dictionary" % card_id)
		return
	var activation: Dictionary = activation_value
	for key: Variant in activation.keys():
		if StringName(key) not in [&"input", &"target_rule", &"costs", &"actions"]:
			errors.append("Card %s activation has unsupported field %s" % [card_id, key])
	var input_id := StringName(activation.get("input", &""))
	if input_id not in KNOWN_ACTIVATION_INPUTS:
		errors.append("Card %s uses unknown activation input %s" % [card_id, input_id])
	var target_rule := StringName(activation.get("target_rule", &""))
	if target_rule not in KNOWN_TARGET_RULES:
		errors.append("Card %s uses unknown target rule %s" % [card_id, target_rule])
	var costs_value: Variant = activation.get("costs", null)
	if not costs_value is Array or (costs_value as Array).is_empty():
		errors.append("Card %s activation requires a non-empty costs array" % card_id)
	else:
		for cost_value: Variant in costs_value as Array:
			if not cost_value is Dictionary:
				errors.append("Card %s activation has a non-dictionary cost" % card_id)
				continue
			_validate_action(card_id, "activation cost", cost_value as Dictionary, true, errors)
	var actions_value: Variant = activation.get("actions", null)
	if not actions_value is Array or (actions_value as Array).is_empty():
		errors.append("Card %s activation requires a non-empty actions array" % card_id)
	else:
		for action_value: Variant in actions_value as Array:
			if not action_value is Dictionary:
				errors.append("Card %s activation has a non-dictionary action" % card_id)
				continue
			_validate_action(card_id, "activation", action_value as Dictionary, false, errors)


static func _validate_action(
	card_id: StringName,
	context_name: String,
	action: Dictionary,
	is_cost: bool,
	errors: Array[String]
) -> void:
	var action_type := StringName(action.get("type", &""))
	if action_type not in KNOWN_ACTIONS:
		errors.append("Card %s %s uses unknown action %s" % [card_id, context_name, action_type])
		return
	if is_cost and action_type != ACTION_SPEND_KI:
		errors.append("Card %s activation uses unsupported cost action %s" % [card_id, action_type])
	var allowed_keys: Array[StringName] = [&"type", &"on_invalid_context"]
	if action_type in [ACTION_DRAW_CARDS, ACTION_GAIN_KI, ACTION_SPEND_KI]:
		allowed_keys.append(&"amount")
		var amount: Variant = action.get("amount", null)
		if typeof(amount) != TYPE_INT or int(amount) <= 0:
			errors.append("Card %s %s action %s requires a positive integer amount" % [card_id, context_name, action_type])
	if action.has("on_invalid_context"):
		if StringName(action.get("on_invalid_context", &"")) != STOP_RULE:
			errors.append("Card %s %s action %s has invalid on_invalid_context policy" % [card_id, context_name, action_type])
	for key: Variant in action.keys():
		if StringName(key) not in allowed_keys:
			errors.append("Card %s %s action %s has unsupported field %s" % [card_id, context_name, action_type, key])
