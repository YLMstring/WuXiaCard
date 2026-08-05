class_name EnemyCatalog
extends RefCounted

const Cards = preload("res://scripts/card_catalog.gd")

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
	&"jiange_suzhu",
	&"tingchao_zhuren",
	&"chisha_menzhu",
	&"yanyu_louzhu",
	&"bailu_shanzhang",
	&"xuanyue_jianshou",
	&"tianmen_yishi",
	&"guhai_kuangdao",
	&"wulin_sanren",
	&"jiugong_lunjianzhe",
]

const _ENEMY_ROWS: Array[Dictionary] = [
	{"id": &"qingfeng_xuedi", "name": "清风学弟", "level": 1, "deck": [&"CangSongYingKe1", &"CangSongYingKe2", &"fire_envoy", &"tiger_general", &"TuNaShu1"]},
	{"id": &"dukou_xiaoke", "name": "渡口侠客", "level": 1, "deck": [&"CangSongYingKe2", &"CangSongYingKe3", &"CangSongYingKe4", &"YouFenLaiYi2", &"TuNaShu2"]},
	{"id": &"tieshan_menren", "name": "铁山门人", "level": 2, "deck": [&"CangSongYingKe3", &"CangSongYingKe4", &"YouFenLaiYi2", &"TuNaShu2", &"fire_envoy"]},
	{"id": &"qingzhu_daoke", "name": "青竹刀客", "level": 2, "deck": [&"CangSongYingKe4", &"YouFenLaiYi2", &"TuNaShu2", &"fire_envoy", &"tiger_general"]},
	{"id": &"luoxia_jianji", "name": "落霞剑姬", "level": 3, "deck": [&"YouFenLaiYi2", &"TuNaShu2", &"fire_envoy", &"tiger_general", &"TuNaShu1"]},
	{"id": &"heisha_xingzhe", "name": "黑砂行者", "level": 3, "deck": [&"TuNaShu2", &"fire_envoy", &"tiger_general", &"TuNaShu1", &"TuNaShu1"]},
	{"id": &"beiling_shuangying", "name": "北岭双影", "level": 4, "deck": [&"fire_envoy", &"tiger_general", &"TuNaShu1", &"TuNaShu1", &"LaiHeQinQuan1"]},
	{"id": &"yanbo_yuke", "name": "烟波渔客", "level": 4, "deck": [&"tiger_general", &"TuNaShu1", &"TuNaShu1", &"LaiHeQinQuan1", &"TaiShan18Pan1"]},
	{"id": &"cangyan_hufa", "name": "苍岩护法", "level": 5, "deck": [&"TuNaShu1", &"TuNaShu1", &"LaiHeQinQuan1", &"TaiShan18Pan1", &"WuDaFuJian1"]},
	{"id": &"tingyu_zhangshi", "name": "听雨掌事", "level": 5, "deck": [&"TuNaShu1", &"LaiHeQinQuan1", &"TaiShan18Pan1", &"WuDaFuJian1", &"QiXinLuoChangKong2"]},
	{"id": &"jinling_kuaijian", "name": "金陵快剑", "level": 6, "deck": [&"LaiHeQinQuan1", &"TaiShan18Pan1", &"WuDaFuJian1", &"QiXinLuoChangKong2", &"yuyan_tousuo"]},
	{"id": &"chilian_sanke", "name": "赤练散客", "level": 6, "deck": [&"TaiShan18Pan1", &"WuDaFuJian1", &"QiXinLuoChangKong2", &"yuyan_tousuo", &"wusuo_changqiao"]},
	{"id": &"xuanhuo_qishi", "name": "玄火骑士", "level": 7, "deck": [&"WuDaFuJian1", &"QiXinLuoChangKong2", &"yuyan_tousuo", &"wusuo_changqiao", &"feixing_ruye"]},
	{"id": &"baishi_daoren", "name": "白石道人", "level": 7, "deck": [&"QiXinLuoChangKong2", &"yuyan_tousuo", &"wusuo_changqiao", &"feixing_ruye", &"qianji_tingyu"]},
	{"id": &"fengsha_lingzhu", "name": "风沙令主", "level": 8, "deck": [&"yuyan_tousuo", &"wusuo_changqiao", &"feixing_ruye", &"qianji_tingyu", &"hengsha_duanlu"]},
	{"id": &"canghai_haoke", "name": "沧海豪客", "level": 8, "deck": [&"wusuo_changqiao", &"feixing_ruye", &"qianji_tingyu", &"hengsha_duanlu", &"chilian_huifeng"]},
	{"id": &"qianji_xiansheng", "name": "千机先生", "level": 9, "deck": [&"feixing_ruye", &"qianji_tingyu", &"hengsha_duanlu", &"chilian_huifeng", &"shahai_zhuri"]},
	{"id": &"hanyue_nvxia", "name": "寒月女侠", "level": 9, "deck": [&"qianji_tingyu", &"hengsha_duanlu", &"chilian_huifeng", &"shahai_zhuri", &"damo_guzhan"]},
	{"id": &"zhenyue_shi", "name": "镇岳使", "level": 10, "deck": [&"hengsha_duanlu", &"chilian_huifeng", &"shahai_zhuri", &"damo_guzhan", &"dielang_tuizhou"]},
	{"id": &"wuying_ke", "name": "无影客", "level": 10, "deck": [&"chilian_huifeng", &"shahai_zhuri", &"damo_guzhan", &"dielang_tuizhou", &"huichao_tingjin"]},
	{"id": &"jiange_suzhu", "name": "剑阁宿主", "level": 11, "deck": [&"shahai_zhuri", &"damo_guzhan", &"dielang_tuizhou", &"huichao_tingjin", &"canghai_sandie"]},
	{"id": &"tingchao_zhuren", "name": "听潮主人", "level": 11, "deck": [&"damo_guzhan", &"dielang_tuizhou", &"huichao_tingjin", &"canghai_sandie", &"haitian_yizhang"]},
	{"id": &"chisha_menzhu", "name": "赤砂门主", "level": 12, "deck": [&"dielang_tuizhou", &"huichao_tingjin", &"canghai_sandie", &"haitian_yizhang", &"zhujian_cangfeng"]},
	{"id": &"yanyu_louzhu", "name": "烟雨楼主", "level": 12, "deck": [&"huichao_tingjin", &"canghai_sandie", &"haitian_yizhang", &"zhujian_cangfeng", &"luming_wenlu"]},
	{"id": &"bailu_shanzhang", "name": "白鹿山长", "level": 13, "deck": [&"canghai_sandie", &"haitian_yizhang", &"zhujian_cangfeng", &"luming_wenlu", &"jingwei_dingju"]},
	{"id": &"xuanyue_jianshou", "name": "玄岳剑首", "level": 13, "deck": [&"haitian_yizhang", &"zhujian_cangfeng", &"luming_wenlu", &"jingwei_dingju", &"zhishang_shanhe"]},
	{"id": &"tianmen_yishi", "name": "天门遗世", "level": 14, "deck": [&"zhujian_cangfeng", &"luming_wenlu", &"jingwei_dingju", &"zhishang_shanhe", &"gate_general"]},
	{"id": &"guhai_kuangdao", "name": "孤海狂刀", "level": 14, "deck": [&"luming_wenlu", &"jingwei_dingju", &"zhishang_shanhe", &"gate_general", &"meng_huo"]},
	{"id": &"wulin_sanren", "name": "武林散人", "level": 15, "deck": [&"jingwei_dingju", &"zhishang_shanhe", &"gate_general", &"meng_huo", &"CangSongYingKe1"]},
	{"id": &"jiugong_lunjianzhe", "name": "九宫论剑者", "level": 15, "deck": [&"zhishang_shanhe", &"gate_general", &"meng_huo", &"CangSongYingKe1", &"CangSongYingKe2"]},
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
