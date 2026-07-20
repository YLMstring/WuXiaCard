class_name CardCatalog
extends RefCounted

const EFFECT_EXILE_INSTEAD_OF_FLIP: StringName = &"exile_instead_of_flip"
const EFFECT_DRAW_CARDS_ON_PLAY: StringName = &"draw_cards_on_play"
const KNOWN_EFFECT_IDS: Array[StringName] = [
	EFFECT_EXILE_INSTEAD_OF_FLIP,
	EFFECT_DRAW_CARDS_ON_PLAY,
]

const ALL_CARD_IDS: Array[StringName] = [
	&"xu_shu",
	&"gate_general",
	&"meng_huo",
	&"jiang_wei",
	&"fa_zheng",
	&"zhang_ren",
	&"fire_envoy",
	&"tiger_general",
	&"strategist",
	&"sun_zan",
]

const _CARD_DEFINITIONS: Dictionary = {
	&"xu_shu": {
		"id": &"xu_shu",
		"name": "Xu Shu",
		"glyph": "徐",
		"powers": [3, 2, 3, 2],
		"effects": [],
	},
	&"gate_general": {
		"id": &"gate_general",
		"name": "Gate General",
		"glyph": "关",
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
		"name": "Meng Huo",
		"glyph": "孟",
		"powers": [8, 7, 2, 3],
		"effects": [],
	},
	&"jiang_wei": {
		"id": &"jiang_wei",
		"name": "Jiang Wei",
		"glyph": "姜",
		"powers": [6, 6, 6, 6],
		"effects": [],
	},
	&"fa_zheng": {
		"id": &"fa_zheng",
		"name": "Fa Zheng",
		"glyph": "法",
		"powers": [5, 4, 4, 3],
		"effects": [
			{
				"id": EFFECT_DRAW_CARDS_ON_PLAY,
				"draw_count": 2,
			},
		],
	},
	&"zhang_ren": {
		"id": &"zhang_ren",
		"name": "Zhang Ren",
		"glyph": "张",
		"powers": [4, 7, 7, 4],
		"effects": [],
	},
	&"fire_envoy": {
		"id": &"fire_envoy",
		"name": "Fire Envoy",
		"glyph": "火",
		"powers": [5, 5, 4, 4],
		"effects": [],
	},
	&"tiger_general": {
		"id": &"tiger_general",
		"name": "Tiger General",
		"glyph": "虎",
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
		"name": "Strategist",
		"glyph": "策",
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
		"name": "Sun Zan",
		"glyph": "孙",
		"powers": [3, 5, 8, 8],
		"effects": [],
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
		"name": String(definition["name"]),
		"glyph": String(definition["glyph"]),
		"powers": (definition["powers"] as Array).duplicate(),
		"original_owner": original_owner,
		"active_effects": _normalize_effects(definition["effects"] as Array),
	}


static func validate_effect(effect: Dictionary, card_id: StringName = &"fixture") -> Array[String]:
	var errors: Array[String] = []
	_validate_effect(card_id, effect, errors)
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
	if String(definition.get("name", "")).is_empty():
		errors.append("Card %s has no name" % card_id)
	if String(definition.get("glyph", "")).is_empty():
		errors.append("Card %s has no glyph" % card_id)
	var powers: Array = definition.get("powers", [])
	if powers.size() != 4:
		errors.append("Card %s requires four powers" % card_id)
	for power: Variant in powers:
		if typeof(power) != TYPE_INT:
			errors.append("Card %s has a non-integer power" % card_id)
	var effects: Array = definition.get("effects", [])
	for effect_value: Variant in effects:
		if not effect_value is Dictionary:
			errors.append("Card %s has a non-dictionary effect" % card_id)
			continue
		var effect: Dictionary = effect_value
		_validate_effect(card_id, effect, errors)


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
