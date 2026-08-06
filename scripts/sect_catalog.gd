class_name SectCatalog
extends RefCounted

const ALL_SECT_IDS: Array[StringName] = [
	&"HuaShanPai",
	&"TaiShanPai",
	&"HengShanPai",
	&"tingchao_gu",
	&"bailu_shuyuan",
]

const _DEFINITION_FIELDS: Array[StringName] = [
	&"id",
	&"glyph",
	&"picture",
	&"sect",
	&"tier",
	&"weapon",
	&"description",
	&"flavor",
]

const _SECT_DEFINITIONS: Dictionary = {
	&"HuaShanPai": {
		"id": &"HuaShanPai",
		"glyph": "华山派",
		"picture": "res://pics/LKT010_568.png",
		"sect": "华山",
		"tier": 4,
		"weapon": "剑法/心法",
		"description": "华山派擅长强化自身招式，并在场上发动多次攻击。",
		"flavor": "华山派正宗功夫以气功为根基，剑法变化繁复，轻灵机巧，恰如春日双燕飞舞柳间，高低左右，回转如意。",
	},
	&"TaiShanPai": {
		"id": &"TaiShanPai",
		"glyph": "泰山派",
		"picture": "res://pics/LKT010_002.png",
		"sect": "泰山",
		"tier": 5,
		"weapon": "重剑/术数",
		"description": "泰山派擅长根据对手情况做出应对，稳扎稳打。",
		"flavor": "泰山剑招以厚重沉稳见长，规矩谨严而又不失迅疾，犹似行云流水。",
	},
	&"HengShanPai": {
		"id": &"HengShanPai",
		"glyph": "赤砂门",
		"picture": "res://pics/LKT010_003.png",
		"sect": "西域赤沙",
		"tier": 4,
		"weapon": "轻剑/剑阵",
		"description": "恒山派擅长保护友方，防守反击。",
		"flavor": "恒山剑法破绽极少，若言守御之严，仅逊于武当派的太极剑法，但偶尔忽出攻招，却又在太极剑法之上。",
	},
	&"tingchao_gu": {
		"id": &"tingchao_gu",
		"glyph": "听潮谷",
		"picture": "res://pics/LKT010_004.png",
		"sect": "东海群岛",
		"tier": 4,
		"weapon": "掌法",
		"description": "听潮谷以潮汐悟劲，掌法时缓时急，善于卸去正面冲击，再以层叠内劲反攻。门人也精通舟行与水上身法。",
		"flavor": "谷中石壁布满天然孔洞，涨潮时会奏出低沉长音。掌门择徒不问出身，只问来者能否听出潮声中的第七次回响。",
	},
	&"bailu_shuyuan": {
		"id": &"bailu_shuyuan",
		"glyph": "白鹿书院",
		"picture": "res://pics/LKT010_005.png",
		"sect": "中州鹿鸣山",
		"tier": 2,
		"weapon": "奇门",
		"description": "白鹿书院主张先明理而后用武，将机关、阵图与经义融为奇门之术。门人正面武力不盛，却擅长准备、推演和改变战场条件。",
		"flavor": "书院藏书楼前常有白鹿出没，从不畏人。院中旧规写道：“能胜一局者可学术，能止一战者方可传道。”",
	},
}


static func has_sect(sect_id: StringName) -> bool:
	return _SECT_DEFINITIONS.has(sect_id)


static func get_all_sect_ids() -> Array[StringName]:
	return ALL_SECT_IDS.duplicate()


static func get_definition(sect_id: StringName) -> Dictionary:
	assert(has_sect(sect_id), "Unknown sect ID: %s" % sect_id)
	var definition: Dictionary = _SECT_DEFINITIONS.get(sect_id, {})
	return definition.duplicate(true)


static func validate_definition(
	definition: Dictionary,
	sect_id: StringName = &"fixture"
) -> Array[String]:
	var errors: Array[String] = []
	_validate_definition(sect_id, definition, errors)
	return errors


static func validate_catalog() -> Array[String]:
	var errors: Array[String] = []
	var observed_ids: Dictionary = {}
	for sect_id: StringName in ALL_SECT_IDS:
		if observed_ids.has(sect_id):
			errors.append("Duplicate sect catalog ID: %s" % sect_id)
			continue
		observed_ids[sect_id] = true
		if not _SECT_DEFINITIONS.has(sect_id):
			errors.append("Missing sect definition for ID: %s" % sect_id)
			continue
		_validate_definition(sect_id, _SECT_DEFINITIONS[sect_id] as Dictionary, errors)
	for raw_key: Variant in _SECT_DEFINITIONS.keys():
		var definition_id := StringName(raw_key)
		if not observed_ids.has(definition_id):
			errors.append("Sect definition is absent from ALL_SECT_IDS: %s" % definition_id)
	return errors


static func _validate_definition(
	sect_id: StringName,
	definition: Dictionary,
	errors: Array[String]
) -> void:
	if sect_id == &"":
		errors.append("Sect ID cannot be empty")
	var id_value: Variant = definition.get("id", null)
	if typeof(id_value) != TYPE_STRING_NAME:
		errors.append("Sect %s requires a StringName id" % sect_id)
	elif id_value != sect_id:
		errors.append("Sect definition ID does not match key: %s" % sect_id)
	for raw_key: Variant in definition.keys():
		if StringName(raw_key) not in _DEFINITION_FIELDS:
			errors.append("Sect %s has unsupported field %s" % [sect_id, raw_key])

	var glyph_value: Variant = definition.get("glyph", null)
	if typeof(glyph_value) != TYPE_STRING:
		errors.append("Sect %s requires a String glyph" % sect_id)
	else:
		var glyph_length: int = (glyph_value as String).length()
		if glyph_length < 1 or glyph_length > 7:
			errors.append("Sect %s glyph must contain 1 to 7 characters" % sect_id)

	for field: StringName in [&"picture", &"sect", &"weapon", &"description", &"flavor"]:
		var value: Variant = definition.get(field, null)
		if typeof(value) != TYPE_STRING or String(value).strip_edges().is_empty():
			errors.append("Sect %s requires non-empty String metadata %s" % [sect_id, field])
	var picture_value: Variant = definition.get("picture", null)
	if (
		typeof(picture_value) == TYPE_STRING
		and not String(picture_value).is_empty()
		and not ResourceLoader.exists(String(picture_value))
	):
		errors.append("Sect %s picture resource does not exist: %s" % [sect_id, picture_value])

	var tier_value: Variant = definition.get("tier", null)
	if typeof(tier_value) != TYPE_INT or int(tier_value) <= 0:
		errors.append("Sect %s requires a positive integer prestige tier" % sect_id)
