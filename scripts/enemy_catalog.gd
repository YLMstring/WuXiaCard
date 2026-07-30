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

const DECK_A: Array[StringName] = [
	&"CangSongYingKe1",
	&"fire_envoy",
	&"tiger_general",
	&"strategist",
	&"sun_zan",
]
const DECK_B: Array[StringName] = [
	&"CangSongYingKe2",
	&"YouFenLaiYi",
	&"fa_zheng",
	&"gate_general",
	&"meng_huo",
]
const DECK_C: Array[StringName] = [
	&"hanfeng_liezhen",
	&"huixue_liuguang",
	&"qiyao_lianfeng",
	&"wanyue_guizong",
	&"yuyan_tousuo",
]
const DECK_D: Array[StringName] = [
	&"wusuo_changqiao",
	&"feixing_ruye",
	&"qianji_tingyu",
	&"hengsha_duanlu",
	&"chilian_huifeng",
]
const DECK_E: Array[StringName] = [
	&"shahai_zhuri",
	&"damo_guzhan",
	&"dielang_tuizhou",
	&"huichao_tingjin",
	&"canghai_sandie",
]
const DECK_F: Array[StringName] = [
	&"haitian_yizhang",
	&"zhujian_cangfeng",
	&"luming_wenlu",
	&"jingwei_dingju",
	&"zhishang_shanhe",
]

const _ENEMY_ROWS: Array[Dictionary] = [
	{"id": &"qingfeng_xuedi", "name": "清风学弟", "level": 1, "deck": DECK_A},
	{"id": &"dukou_xiaoke", "name": "渡口侠客", "level": 1, "deck": DECK_B},
	{"id": &"tieshan_menren", "name": "铁山门人", "level": 2, "deck": DECK_B},
	{"id": &"qingzhu_daoke", "name": "青竹刀客", "level": 2, "deck": DECK_C},
	{"id": &"luoxia_jianji", "name": "落霞剑姬", "level": 3, "deck": DECK_C},
	{"id": &"heisha_xingzhe", "name": "黑砂行者", "level": 3, "deck": DECK_D},
	{"id": &"beiling_shuangying", "name": "北岭双影", "level": 4, "deck": DECK_D},
	{"id": &"yanbo_yuke", "name": "烟波渔客", "level": 4, "deck": DECK_E},
	{"id": &"cangyan_hufa", "name": "苍岩护法", "level": 5, "deck": DECK_E},
	{"id": &"tingyu_zhangshi", "name": "听雨掌事", "level": 5, "deck": DECK_F},
	{"id": &"jinling_kuaijian", "name": "金陵快剑", "level": 6, "deck": DECK_F},
	{"id": &"chilian_sanke", "name": "赤练散客", "level": 6, "deck": DECK_A},
	{"id": &"xuanhuo_qishi", "name": "玄火骑士", "level": 7, "deck": DECK_A},
	{"id": &"baishi_daoren", "name": "白石道人", "level": 7, "deck": DECK_C},
	{"id": &"fengsha_lingzhu", "name": "风沙令主", "level": 8, "deck": DECK_D},
	{"id": &"canghai_haoke", "name": "沧海豪客", "level": 8, "deck": DECK_E},
	{"id": &"qianji_xiansheng", "name": "千机先生", "level": 9, "deck": DECK_F},
	{"id": &"hanyue_nvxia", "name": "寒月女侠", "level": 9, "deck": DECK_B},
	{"id": &"zhenyue_shi", "name": "镇岳使", "level": 10, "deck": DECK_C},
	{"id": &"wuying_ke", "name": "无影客", "level": 10, "deck": DECK_D},
	{"id": &"jiange_suzhu", "name": "剑阁宿主", "level": 11, "deck": DECK_E},
	{"id": &"tingchao_zhuren", "name": "听潮主人", "level": 11, "deck": DECK_F},
	{"id": &"chisha_menzhu", "name": "赤砂门主", "level": 12, "deck": DECK_A},
	{"id": &"yanyu_louzhu", "name": "烟雨楼主", "level": 12, "deck": DECK_B},
	{"id": &"bailu_shanzhang", "name": "白鹿山长", "level": 13, "deck": DECK_C},
	{"id": &"xuanyue_jianshou", "name": "玄岳剑首", "level": 13, "deck": DECK_D},
	{"id": &"tianmen_yishi", "name": "天门遗世", "level": 14, "deck": DECK_E},
	{"id": &"guhai_kuangdao", "name": "孤海狂刀", "level": 14, "deck": DECK_F},
	{"id": &"wulin_sanren", "name": "武林散人", "level": 15, "deck": DECK_A},
	{"id": &"jiugong_lunjianzhe", "name": "九宫论剑者", "level": 15, "deck": DECK_F},
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
	for enemy_id: StringName in ALL_ENEMY_IDS:
		if observed.has(enemy_id):
			errors.append("Duplicate enemy catalog ID: %s" % enemy_id)
			continue
		observed[enemy_id] = true
		if not _enemy_definitions.has(enemy_id):
			errors.append("Missing enemy definition: %s" % enemy_id)
			continue
		_validate_definition(enemy_id, _enemy_definitions[enemy_id] as Dictionary, errors)
	for raw_key: Variant in _enemy_definitions:
		var enemy_id := StringName(raw_key)
		if not observed.has(enemy_id):
			errors.append("Enemy definition is absent from ALL_ENEMY_IDS: %s" % enemy_id)
	return errors


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
	var observed_cards: Dictionary = {}
	for value: Variant in deck:
		var card_id := StringName(String(value))
		if card_id not in known_card_ids:
			errors.append("Enemy %s uses unknown card %s" % [enemy_id, card_id])
		elif observed_cards.has(card_id):
			errors.append("Enemy %s repeats card %s" % [enemy_id, card_id])
		observed_cards[card_id] = true


static func _build_definition_map() -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in _ENEMY_ROWS:
		var enemy_id := StringName(row.get("id", &""))
		result[enemy_id] = row.duplicate(true)
	return result
