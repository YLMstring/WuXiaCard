class_name SectCatalog
extends RefCounted

const ALL_SECT_IDS: Array[StringName] = [
	&"HuaShanPai",
	&"WuDangPai",
	&"TaiShanPai",
	&"HengShanPai",
	&"tingchao_gu",
	&"SongShanPai",
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
		"picture": "res://pics/LKT010_545.png",
		"sect": "华山",
		"tier": 4,
		"weapon": "剑法/心法",
		"description": "华山派擅长强化自身招式，并在场上发动多次攻击。",
		"flavor": "华山派正宗功夫以气功为根基，剑法变化繁复，轻灵机巧，恰如春日双燕飞舞柳间，高低左右，回转如意。",
	},
	&"WuDangPai": {
		"id": &"WuDangPai",
		"glyph": "武当派",
		"picture": "res://pics/LKT010_004.png",
		"sect": "武当山",
		"tier": 5,
		"weapon": "拳法/掌法/剑法/轻功",
		"description": "武当派的能力十分全面，无论是进攻，防守还是对策都游刃有余。",
		"flavor": "武当与少林并称武林中的泰山北斗，武功以绵密见长，讲究借力打力。",
	},
	&"TaiShanPai": {
		"id": &"TaiShanPai",
		"glyph": "泰山派",
		"picture": "res://pics/LKT010_553.png",
		"sect": "泰山",
		"tier": 5,
		"weapon": "重剑/术数",
		"description": "泰山派擅长根据对手情况做出应对，稳扎稳打。",
		"flavor": "泰山剑招以厚重沉稳见长，规矩谨严而又不失迅疾，犹似行云流水。",
	},
	&"HengShanPai": {
		"id": &"HengShanPai",
		"glyph": "恒山派",
		"picture": "res://pics/LKT010_491.png",
		"sect": "恒山",
		"tier": 4,
		"weapon": "轻剑/阵法",
		"description": "恒山派擅长保护友方，防守反击。",
		"flavor": "恒山剑法破绽极少，若言守御之严，仅逊于武当派的太极剑法，但偶尔忽出攻招，却又在太极剑法之上。",
	},
	&"tingchao_gu": {
		"id": &"tingchao_gu",
		"glyph": "衡山派",
		"picture": "res://pics/LKT010_556.png",
		"sect": "衡山",
		"tier": 4,
		"weapon": "轻剑",
		"description": "衡山派擅长解除对手的防御，用巧妙的移动和攻击来逆转局势。",
		"flavor": "衡山剑法灵动难测，变幻无方，一招既占先机，后招绵绵而至，再强的高手也难以抵御。",
	},
	&"SongShanPai": {
		"id": &"SongShanPai",
		"glyph": "嵩山派",
		"picture": "res://pics/LKT010_476.png",
		"sect": "嵩山",
		"tier": 4,
		"weapon": "剑法/掌法/心法",
		"description": "嵩山派擅长使用场上的卡牌配合形成点数差距，压制对手。",
		"flavor": "嵩山派武功乃堂堂之阵，正正之师，剑法气象森严，便似千军万马奔驰而来，长枪大戟，黄沙千里。",
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
