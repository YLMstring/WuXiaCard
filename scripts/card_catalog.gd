class_name CardCatalog
extends RefCounted

const EFFECT_EXILE_INSTEAD_OF_FLIP: StringName = &"exile_instead_of_flip"
const EFFECT_DRAW_CARDS_ON_PLAY: StringName = &"draw_cards_on_play"
const EFFECT_MOVE_AND_ATTACK: StringName = &"move_and_attack"
const EFFECT_BATTLE_MOMENTUM: StringName = &"battle_momentum"
const EFFECT_WELCOMING_PINE: StringName = &"welcoming_pine"
const ACTIVATION_DRAG_TO_TARGET: StringName = &"drag_to_target"
const TARGET_ADJACENT_EMPTY_BOARD: StringName = &"adjacent_empty_board"
const TRIGGER_AFTER_SUCCESSFUL_FLIP_BY_SELF: StringName = &"after_successful_flip_by_self"
const TRIGGER_END_OWNER_TURN: StringName = &"end_owner_turn"
const TRIGGER_CARD_SUMMONED: StringName = &"card_summoned"
const CONDITION_KI_AT_LEAST: StringName = &"ki_at_least"
const CONDITION_TRIGGER_CARD_IS_ENEMY: StringName = &"trigger_card_is_enemy"
const CONDITION_TRIGGER_CARD_IN_RANGE: StringName = &"trigger_card_in_range"
const TRIGGER_ACTION_GAIN_KI: StringName = &"gain_ki"
const TRIGGER_ACTION_SPEND_ALL_KI: StringName = &"spend_all_ki"
const TRIGGER_ACTION_REQUEST_EXTRA_TURN: StringName = &"request_extra_turn"
const TRIGGER_ACTION_ATTACK_TRIGGER_CARD: StringName = &"attack_trigger_card"
const KNOWN_EFFECT_IDS: Array[StringName] = [
	EFFECT_EXILE_INSTEAD_OF_FLIP,
	EFFECT_DRAW_CARDS_ON_PLAY,
	EFFECT_MOVE_AND_ATTACK,
	EFFECT_BATTLE_MOMENTUM,
	EFFECT_WELCOMING_PINE,
]
const KNOWN_TRIGGER_EVENTS: Array[StringName] = [
	TRIGGER_AFTER_SUCCESSFUL_FLIP_BY_SELF,
	TRIGGER_END_OWNER_TURN,
	TRIGGER_CARD_SUMMONED,
]
const KNOWN_TRIGGER_CONDITIONS: Array[StringName] = [
	CONDITION_KI_AT_LEAST,
	CONDITION_TRIGGER_CARD_IS_ENEMY,
	CONDITION_TRIGGER_CARD_IN_RANGE,
]
const KNOWN_TRIGGER_ACTIONS: Array[StringName] = [
	TRIGGER_ACTION_GAIN_KI,
	TRIGGER_ACTION_SPEND_ALL_KI,
	TRIGGER_ACTION_REQUEST_EXTRA_TURN,
	TRIGGER_ACTION_ATTACK_TRIGGER_CARD,
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
		"effects": [],
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
		"effects": [
			{
				"id": EFFECT_WELCOMING_PINE,
				"triggers": [
					{
						"event": TRIGGER_CARD_SUMMONED,
						"conditions": [
							{"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
							{"type": CONDITION_TRIGGER_CARD_IN_RANGE},
						],
						"actions": [
							{"type": TRIGGER_ACTION_ATTACK_TRIGGER_CARD},
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
		"effects": [
			{
				"id": EFFECT_EXILE_INSTEAD_OF_FLIP,
				"retained_on_flip": true,
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
		"effects": [
			{
				"id": EFFECT_BATTLE_MOMENTUM,
				"triggers": [
					{
						"event": TRIGGER_AFTER_SUCCESSFUL_FLIP_BY_SELF,
						"actions": [
							{"type": TRIGGER_ACTION_GAIN_KI, "amount": 1},
						],
					},
					{
						"event": TRIGGER_END_OWNER_TURN,
						"conditions": [
							{"type": CONDITION_KI_AT_LEAST, "amount": 1},
						],
						"actions": [
							{"type": TRIGGER_ACTION_SPEND_ALL_KI},
							{"type": TRIGGER_ACTION_REQUEST_EXTRA_TURN},
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
		"effects": [
			{
				"id": EFFECT_MOVE_AND_ATTACK,
				"activation": ACTIVATION_DRAG_TO_TARGET,
				"target_rule": TARGET_ADJACENT_EMPTY_BOARD,
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
		"effects": [
			{
				"id": EFFECT_DRAW_CARDS_ON_PLAY,
				"draw_count": 2,
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
		"effects": [],
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
		"effects": [
			{
				"id": EFFECT_EXILE_INSTEAD_OF_FLIP,
				"retained_on_flip": true,
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
		"effects": [
			{
				"id": EFFECT_DRAW_CARDS_ON_PLAY,
				"draw_count": 2,
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
		"effects": [
			{
				"id": EFFECT_MOVE_AND_ATTACK,
				"activation": ACTIVATION_DRAG_TO_TARGET,
				"target_rule": TARGET_ADJACENT_EMPTY_BOARD,
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
		"active_effects": _normalize_effects(definition["effects"] as Array),
	}


static func validate_effect(effect: Dictionary, card_id: StringName = &"fixture") -> Array[String]:
	var errors: Array[String] = []
	_validate_effect(card_id, effect, errors)
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
	var effects: Array = definition.get("effects", [])
	var starting_ki: Variant = definition.get("starting_ki", 0)
	if typeof(starting_ki) != TYPE_INT or int(starting_ki) < 0:
		errors.append("Card %s requires a non-negative integer starting_ki" % card_id)
	var activate_effect_count: int = 0
	for effect_value: Variant in effects:
		if not effect_value is Dictionary:
			errors.append("Card %s has a non-dictionary effect" % card_id)
			continue
		var effect: Dictionary = effect_value
		if effect.has("activation"):
			activate_effect_count += 1
		_validate_effect(card_id, effect, errors)
	if activate_effect_count > 1:
		errors.append("Card %s declares more than one activate effect" % card_id)


static func _normalize_effects(raw_effects: Array) -> Array:
	var normalized_effects: Array = []
	for effect_value: Variant in raw_effects:
		var effect: Dictionary = (effect_value as Dictionary).duplicate(true)
		if not effect.has("retained_on_flip"):
			effect["retained_on_flip"] = false
		normalized_effects.append(effect)
	return normalized_effects


static func _validate_effect(
	card_id: StringName,
	effect: Dictionary,
	errors: Array[String]
) -> void:
	var effect_id := StringName(effect.get("id", &""))
	if effect_id not in KNOWN_EFFECT_IDS:
		errors.append("Card %s uses unknown effect %s" % [card_id, effect_id])
	if effect.has("retained_on_flip") and typeof(effect["retained_on_flip"]) != TYPE_BOOL:
		errors.append("Card %s effect %s has non-Boolean retained_on_flip" % [card_id, effect_id])
	if effect_id == EFFECT_DRAW_CARDS_ON_PLAY:
		if not effect.has("draw_count") or typeof(effect["draw_count"]) != TYPE_INT:
			errors.append("Card %s draw effect requires an integer draw_count" % card_id)
		elif int(effect["draw_count"]) <= 0:
			errors.append("Card %s draw effect requires a positive draw_count" % card_id)
	if effect_id == EFFECT_MOVE_AND_ATTACK:
		if StringName(effect.get("activation", &"")) != ACTIVATION_DRAG_TO_TARGET:
			errors.append("Card %s move effect requires drag_to_target activation" % card_id)
		if StringName(effect.get("target_rule", &"")) != TARGET_ADJACENT_EMPTY_BOARD:
			errors.append("Card %s move effect requires adjacent_empty_board targeting" % card_id)
	if effect_id in [EFFECT_BATTLE_MOMENTUM, EFFECT_WELCOMING_PINE]:
		_validate_triggers(card_id, effect.get("triggers", null), errors)


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
			_validate_trigger_condition(card_id, event_id, condition_value as Dictionary, errors)
	var actions_value: Variant = trigger.get("actions", null)
	if not actions_value is Array or (actions_value as Array).is_empty():
		errors.append("Card %s trigger %s requires a non-empty action array" % [card_id, event_id])
		return
	for action_value: Variant in actions_value as Array:
		if not action_value is Dictionary:
			errors.append("Card %s trigger %s has a non-dictionary action" % [card_id, event_id])
			continue
		_validate_trigger_action(card_id, event_id, action_value as Dictionary, errors)


static func _validate_trigger_condition(
	card_id: StringName,
	event_id: StringName,
	condition: Dictionary,
	errors: Array[String]
) -> void:
	var condition_type := StringName(condition.get("type", &""))
	if condition_type not in KNOWN_TRIGGER_CONDITIONS:
		errors.append("Card %s trigger %s uses unknown condition %s" % [card_id, event_id, condition_type])
		return
	var allowed_keys: Array[StringName] = [&"type"]
	if condition_type == CONDITION_KI_AT_LEAST:
		allowed_keys.append(&"amount")
		var threshold: Variant = condition.get("amount", null)
		if typeof(threshold) != TYPE_INT or int(threshold) < 0:
			errors.append("Card %s trigger %s requires a non-negative integer ki_at_least amount" % [card_id, event_id])
	for key: Variant in condition.keys():
		if StringName(key) not in allowed_keys:
			errors.append("Card %s trigger %s condition %s has unsupported field %s" % [card_id, event_id, condition_type, key])


static func _validate_trigger_action(
	card_id: StringName,
	event_id: StringName,
	action: Dictionary,
	errors: Array[String]
) -> void:
	var action_type := StringName(action.get("type", &""))
	if action_type not in KNOWN_TRIGGER_ACTIONS:
		errors.append("Card %s trigger %s uses unknown action %s" % [card_id, event_id, action_type])
		return
	var allowed_keys: Array[StringName] = [&"type"]
	if action_type == TRIGGER_ACTION_GAIN_KI:
		allowed_keys.append(&"amount")
		var amount: Variant = action.get("amount", null)
		if typeof(amount) != TYPE_INT or int(amount) <= 0:
			errors.append("Card %s trigger %s gain_ki requires a positive integer amount" % [card_id, event_id])
	for key: Variant in action.keys():
		if StringName(key) not in allowed_keys:
			errors.append("Card %s trigger %s action %s has unsupported field %s" % [card_id, event_id, action_type, key])
