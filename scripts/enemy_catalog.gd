class_name EnemyCatalog
extends RefCounted

const Cards = preload("res://scripts/card_catalog.gd")
const Sects = preload("res://scripts/sect_catalog.gd")

const ALL_ENEMY_IDS: Array[StringName] = [
	&"qingfeng_xuedi",
	&"dukou_xiaoke",
	&"tieshan_menren",
	&"qingzhu_daoke",
	&"luoxia_jianji",
	&"heisha_xingzhe",
	&"beiling_shuangying",
	&"yanbo_yuke",
	&"cangyan_hufa",
	&"tingyu_zhangshi",
	&"jinling_kuaijian",
	&"chilian_sanke",
	&"xuanhuo_qishi",
	&"baishi_daoren",
	&"fengsha_lingzhu",
	&"canghai_haoke",
	&"qianji_xiansheng",
	&"hanyue_nvxia",
	&"zhenyue_shi",
	&"wuying_ke",
	&"tingchao_zhuren",
	&"chisha_menzhu",
	&"bailu_shanzhang",
	&"tianmen_yishi",
	&"wulin_sanren",
]

const _ENEMY_ROWS: Array[Dictionary] = [
	{"id": &"qingfeng_xuedi", "name": "少镖头·林平之", "level": 1, "self_castration_enabled": false, "deck": [&"KuiHua4", &"KuiHua4", &"KuiHua3", &"KuiHua3", &"KuiHua2"]},
	{"id": &"dukou_xiaoke", "name": "史镖头", "level": 1, "deck": [&"TaiZuChangQuan", &"TaiZuChangQuan", &"TaiZuChangQuan", &"TaiZuChangQuan", &"TaiZuChangQuan"]},
	{"id": &"tieshan_menren", "name": "小师妹·岳灵珊", "level": 2, "deck": [&"CangSongYingKe1", &"SanQinFeng1", &"ZiXiaGong1", &"TuNaShu1", &"YouFenLaiYi2"]},
	{"id": &"qingzhu_daoke", "name": "仪琳", "level": 2, "deck": [&"JinZhenDuJie1", &"WanHuaJian1", &"TuNaShu1", &"MianLiCangZhen2", &"HenShanJianZhen2"]},
	{"id": &"luoxia_jianji", "name": "泰山弟子", "level": 3, "deck": [&"YouFenLaiYi2", &"TuNaShu2", &"TaiZuChangQuan", &"tiger_general", &"TuNaShu1"]},
	{"id": &"heisha_xingzhe", "name": "衡山弟子", "level": 3, "deck": [&"TuNaShu2", &"TaiZuChangQuan", &"tiger_general", &"TuNaShu1", &"TuNaShu1"]},
	{"id": &"beiling_shuangying", "name": "恒山弟子", "level": 4, "deck": [&"TaiZuChangQuan", &"tiger_general", &"TuNaShu1", &"TuNaShu1", &"LaiHeQinQuan1"]},
	{"id": &"yanbo_yuke", "name": "嵩山弟子", "level": 4, "deck": [&"tiger_general", &"TuNaShu1", &"TuNaShu1", &"LaiHeQinQuan1", &"TaiShan18Pan1"]},
	{"id": &"cangyan_hufa", "name": "玉玑子", "level": 5, "deck": [&"TuNaShu1", &"TuNaShu1", &"LaiHeQinQuan1", &"TaiShan18Pan1", &"WuDaFuJian1"]},
	{"id": &"tingyu_zhangshi", "name": "费斌", "level": 5, "deck": [&"TuNaShu1", &"LaiHeQinQuan1", &"TaiShan18Pan1", &"WuDaFuJian1", &"QiXinLuoChangKong2"]},
	{"id": &"jinling_kuaijian", "name": "刘正风", "level": 6, "deck": [&"LaiHeQinQuan1", &"TaiShan18Pan1", &"WuDaFuJian1", &"QiXinLuoChangKong2", &"TianChangZhang3"]},
	{"id": &"chilian_sanke", "name": "定静", "level": 6, "deck": [&"TaiShan18Pan1", &"WuDaFuJian1", &"QiXinLuoChangKong2", &"TianChangZhang3", &"HenShanJianZhen2"]},
	{"id": &"xuanhuo_qishi", "name": "宁中则", "level": 7, "deck": [&"WuDaFuJian1", &"QiXinLuoChangKong2", &"TianChangZhang3", &"HenShanJianZhen2", &"JinZhenDuJie1"]},
	{"id": &"baishi_daoren", "name": "五岳秘剑·岳灵珊", "level": 7, "deck": [&"YanHuiZhuRong4", &"TianZhuYunQi4", &"JinZhenDuJie4", &"WuDaFuJian3", &"WanYueChaoZong4"]},
	{"id": &"fengsha_lingzhu", "name": "乐厚", "level": 8, "deck": [&"YinYangZhang4", &"DaSongYangZhang4", &"DaSongYangZhang4", &"DaSongYangZhang4", &"TuNaShu3"]},
	{"id": &"canghai_haoke", "name": "定闲", "level": 8, "sect_id": &"HengShanPai", "deck": [&"HenShanJianZhen4", &"JinZhenDuJie4", &"WanHuaJian3", &"MianLiCangZhen3", &"TuNaShu3"]},
	{"id": &"qianji_xiansheng", "name": "天门道人", "level": 9, "deck": [&"LaiHeQinQuan3", &"WuDaFuJian3", &"QiXinLuoChangKong4", &"TaiShan18Pan3", &"WuDaFuJian3"]},
	{"id": &"hanyue_nvxia", "name": "莫大", "level": 9, "sect_id": &"tingchao_gu", "deck": [&"YunWu13Shi3", &"YunWu13Shi3", &"YiJianLuo9Yan3", &"JianFaQinYin3", &"TuNaShu3"]},
	{"id": &"zhenyue_shi", "name": "君子剑·岳不群", "level": 10, "deck": [&"SanQinFeng3", &"CangSongYingKe4", &"YouFenLaiYi4", &"ZiXiaGong2", &"ZiXiaGong4"]},
	{"id": &"wuying_ke", "name": "左冷禅", "level": 10, "sect_id": &"SongShanPai", "deck": [&"WanYueChaoZong4", &"DaSongYangZhang4", &"HanBinZhenQi4", &"TianWaiYuLong3", &"TuNaShu3"]},
	{"id": &"tingchao_zhuren", "name": "杜甫", "level": 11, "deck": [&"LaiHeQinQuan5", &"WuDaFuJian3", &"QiXinLuoChangKong4", &"TaiShan18Pan3", &"QiXinLuoChangKong4"]},
	{"id": &"chisha_menzhu", "name": "复仇者·林平之", "level": 12, "deck": [&"YouFenLaiYi3", &"KuiHua4", &"KuiHua3", &"CangSongYingKe3", &"ZiXiaGong2"]},
	{"id": &"bailu_shanzhang", "name": "五岳掌门·岳不群", "level": 13, "deck": [&"SanQinFeng3", &"KuiHua4", &"KuiHua3", &"KuiHua2", &"ZiXiaGong4"]},
	{"id": &"tianmen_yishi", "name": "风清扬", "level": 14, "deck": [&"DuGu9Jian1", &"DuGu9Jian2", &"DuGu9Jian3", &"DuGu9Jian3", &"CangSongYingKe4"]},
	{"id": &"wulin_sanren", "name": "东方不败", "level": 15, "deck": [&"KuiHua1", &"KuiHua4", &"KuiHua3", &"KuiHua2", &"KuiHua2"]},
]

static var _enemy_definitions: Dictionary = _build_definition_map()


static func has_enemy(enemy_id: StringName) -> bool:
	return _enemy_definitions.has(enemy_id)


static func get_all_enemy_ids() -> Array[StringName]:
	return ALL_ENEMY_IDS.duplicate()


static func get_definition(enemy_id: StringName) -> Dictionary:
	assert(has_enemy(enemy_id), "Unknown enemy ID: %s" % enemy_id)
	return (_enemy_definitions[enemy_id] as Dictionary).duplicate(true)


static func get_enemy_ids_for_level(level: int) -> Array[StringName]:
	var result: Array[StringName] = []
	for enemy_id: StringName in ALL_ENEMY_IDS:
		var definition: Dictionary = _enemy_definitions.get(enemy_id, {})
		if int(definition.get("level", -1)) == level:
			result.append(enemy_id)
	return result


static func is_self_castration_enabled(enemy_id: StringName) -> bool:
	if not has_enemy(enemy_id):
		return true
	return bool((_enemy_definitions[enemy_id] as Dictionary).get(
		"self_castration_enabled",
		true
	))


static func pick_random_enemy_id(
	level: int,
	rng: RandomNumberGenerator = null
) -> StringName:
	var candidates: Array[StringName] = get_enemy_ids_for_level(level)
	if candidates.is_empty():
		return &""
	var picker: RandomNumberGenerator = rng
	if picker == null:
		picker = RandomNumberGenerator.new()
		picker.randomize()
	return candidates[picker.randi_range(0, candidates.size() - 1)]


static func validate_catalog() -> Array[String]:
	var errors: Array[String] = []
	var observed: Dictionary = {}
	var observed_decks: Dictionary = {}
	for enemy_id: StringName in ALL_ENEMY_IDS:
		if observed.has(enemy_id):
			errors.append("Duplicate enemy catalog ID: %s" % enemy_id)
			continue
		observed[enemy_id] = true
		if not _enemy_definitions.has(enemy_id):
			errors.append("Missing enemy definition: %s" % enemy_id)
			continue
		var definition: Dictionary = _enemy_definitions[enemy_id] as Dictionary
		_validate_definition(enemy_id, definition, errors)
		var signature: String = _deck_signature(definition.get("deck", []))
		if not signature.is_empty():
			if observed_decks.has(signature):
				errors.append(
					"Enemy %s shares a deck with %s"
					% [enemy_id, StringName(observed_decks[signature])]
				)
			else:
				observed_decks[signature] = enemy_id
	for raw_key: Variant in _enemy_definitions:
		var enemy_id := StringName(raw_key)
		if not observed.has(enemy_id):
			errors.append("Enemy definition is absent from ALL_ENEMY_IDS: %s" % enemy_id)
	return errors


static func validate_definition(definition: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var enemy_id := StringName(String(definition.get("id", "")))
	_validate_definition(enemy_id, definition, errors)
	return errors


static func _deck_signature(deck_value: Variant) -> String:
	if typeof(deck_value) != TYPE_ARRAY:
		return ""
	var normalized: Array[String] = []
	for value: Variant in deck_value as Array:
		normalized.append(String(value))
	normalized.sort()
	return "|".join(normalized)


static func _validate_definition(
	enemy_id: StringName,
	definition: Dictionary,
	errors: Array[String]
) -> void:
	if StringName(definition.get("id", &"")) != enemy_id:
		errors.append("Enemy definition ID does not match key: %s" % enemy_id)
	if String(definition.get("name", "")).strip_edges().is_empty():
		errors.append("Enemy %s requires a non-empty name" % enemy_id)
	var level: int = int(definition.get("level", 0))
	if level < 1 or level > 15:
		errors.append("Enemy %s requires a level from 1 to 15" % enemy_id)
	if (
		definition.has("self_castration_enabled")
		and typeof(definition.get("self_castration_enabled")) != TYPE_BOOL
	):
		errors.append("Enemy %s requires a Boolean self_castration_enabled" % enemy_id)
	if definition.has("sect_id"):
		var sect_id_value: Variant = definition.get("sect_id")
		if (
			typeof(sect_id_value) != TYPE_STRING_NAME
			or not Sects.has_sect(sect_id_value as StringName)
		):
			errors.append("Enemy %s requires a known StringName sect_id" % enemy_id)
	var deck_value: Variant = definition.get("deck", null)
	if typeof(deck_value) != TYPE_ARRAY:
		errors.append("Enemy %s requires an Array deck" % enemy_id)
		return
	var deck: Array = deck_value
	if deck.size() != 5:
		errors.append("Enemy %s requires exactly five cards" % enemy_id)
	var known_card_ids: Array[StringName] = Cards.get_all_card_ids()
	for value: Variant in deck:
		var card_id := StringName(String(value))
		if card_id not in known_card_ids:
			errors.append("Enemy %s uses unknown card %s" % [enemy_id, card_id])


static func _build_definition_map() -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in _ENEMY_ROWS:
		var enemy_id := StringName(row.get("id", &""))
		result[enemy_id] = row.duplicate(true)
	return result
