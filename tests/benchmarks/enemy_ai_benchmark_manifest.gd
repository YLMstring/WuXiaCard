class_name EnemyAIBenchmarkManifest
extends RefCounted

const VERSION: int = 2

const Enemies = preload("res://scripts/enemy_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")

const QUICK_PAIRS: Array[Array] = [
	[&"qingfeng_xuedi", &"dukou_xiaoke"],
	[&"luoxia_jianji", &"heisha_xingzhe"],
	[&"cangyan_hufa3", &"cangyan_hufa2"],
	[&"canghai_haoke", &"qianji_xiansheng"],
	[&"zhenyue_shi", &"wuying_ke2"],
	[&"chisha_menzhu2", &"chisha_menzhu3"],
	[&"wulin_sanren", &"wulin_sanren2"],
]

const PILOT_PAIRS: Array[Array] = [
	[&"tieshan_menren", &"qingzhu_daoke"],
	[&"cangyan_hufa3", &"cangyan_hufa2"],
	[&"wulin_sanren", &"wulin_sanren2"],
]

const PRODUCTION_PAIRS: Array[Array] = [
	[&"tieshan_menren", &"qingzhu_daoke"],
	[&"cangyan_hufa3", &"cangyan_hufa2"],
	[&"zhenyue_shi", &"wuying_ke2"],
	[&"wulin_sanren", &"wulin_sanren2"],
]

const EXTRA_PLAY_CAP_PAIRS: Array[Array] = [
	[&"wulin_sanren", &"wulin_sanren"],
	[&"wulin_sanren", &"tianmen_yishi"],
	[&"tianmen_yishi", &"tianmen_yishi"],
]


static func get_roster() -> Array[Dictionary]:
	return Enemies.get_ai_benchmark_definitions()


static func get_all_matchups() -> Array[Dictionary]:
	var roster: Array[Dictionary] = get_roster()
	var result: Array[Dictionary] = []
	for first_index: int in range(roster.size()):
		var first: Dictionary = roster[first_index]
		for second_index: int in range(first_index + 1, roster.size()):
			var second: Dictionary = roster[second_index]
			if int(first.get("level", 0)) == int(second.get("level", -1)):
				result.append(_make_matchup(first, second, &"same_level"))
	var feng := _definition_by_id(roster, &"tianmen_yishi")
	for enemy: Dictionary in roster:
		if int(enemy.get("level", 0)) == 15:
			result.append(_make_matchup(feng, enemy, &"cross_level"))
	return result


static func get_matchups_for_mode(mode: StringName) -> Array[Dictionary]:
	if mode == &"extended":
		return get_all_matchups()
	var pairs: Array[Array] = []
	match mode:
		&"quick":
			pairs = QUICK_PAIRS
		&"pilot":
			pairs = PILOT_PAIRS
		&"production":
			pairs = PRODUCTION_PAIRS
		_:
			return []
	var all_matchups: Array[Dictionary] = get_all_matchups()
	var result: Array[Dictionary] = []
	for pair: Array in pairs:
		var found: Dictionary = _find_matchup(
			all_matchups,
			StringName(pair[0]),
			StringName(pair[1])
		)
		if not found.is_empty():
			result.append(found)
	return result


static func get_extra_play_cap_matchups() -> Array[Dictionary]:
	var roster: Array[Dictionary] = get_roster()
	var result: Array[Dictionary] = []
	for pair: Array in EXTRA_PLAY_CAP_PAIRS:
		var first: Dictionary = _definition_by_id(roster, StringName(pair[0]))
		var second: Dictionary = _definition_by_id(roster, StringName(pair[1]))
		if not first.is_empty() and not second.is_empty():
			result.append(_make_matchup(first, second, &"extra_play_cap"))
	return result


static func expand_matchups(matchups: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for matchup: Dictionary in matchups:
		result.append_array(expand_matchup(matchup))
	return result


static func expand_matchup(matchup: Dictionary) -> Array[Dictionary]:
	var matchup_id := StringName(matchup.get("id", &"missing"))
	var enemy_a := StringName(matchup.get("enemy_a_id", &""))
	var enemy_b := StringName(matchup.get("enemy_b_id", &""))
	return [
		_make_game(matchup_id, 1, enemy_a, enemy_b, &"enhanced", &"baseline"),
		_make_game(matchup_id, 2, enemy_a, enemy_b, &"baseline", &"enhanced"),
		_make_game(matchup_id, 3, enemy_b, enemy_a, &"enhanced", &"baseline"),
		_make_game(matchup_id, 4, enemy_b, enemy_a, &"baseline", &"enhanced"),
	]


static func get_card_id_coverage(matchups: Array[Dictionary]) -> Array[StringName]:
	var roster: Array[Dictionary] = get_roster()
	var roster_by_id: Dictionary = {}
	for enemy: Dictionary in roster:
		roster_by_id[StringName(enemy.get("id", &""))] = enemy
	var result: Array[StringName] = []
	for matchup: Dictionary in matchups:
		for field: String in ["enemy_a_id", "enemy_b_id"]:
			var enemy_id := StringName(matchup.get(field, &""))
			var definition: Dictionary = roster_by_id.get(enemy_id, {})
			for card_value: Variant in definition.get("deck", []):
				var card_id := StringName(String(card_value))
				if card_id not in result:
					result.append(card_id)
	return result


static func _make_matchup(
	first: Dictionary,
	second: Dictionary,
	kind: StringName
) -> Dictionary:
	var first_id := StringName(first.get("id", &""))
	var second_id := StringName(second.get("id", &""))
	return {
		"id": StringName("%s__%s" % [first_id, second_id]),
		"kind": kind,
		"enemy_a_id": first_id,
		"enemy_a_name": String(first.get("name", "")),
		"enemy_a_level": int(first.get("level", 0)),
		"enemy_b_id": second_id,
		"enemy_b_name": String(second.get("name", "")),
		"enemy_b_level": int(second.get("level", 0)),
	}


static func _make_game(
	matchup_id: StringName,
	assignment: int,
	owner_one_enemy: StringName,
	owner_two_enemy: StringName,
	owner_one_profile: StringName,
	owner_two_profile: StringName
) -> Dictionary:
	return {
		"id": StringName("%s__g%d" % [matchup_id, assignment]),
		"matchup_id": matchup_id,
		"assignment": assignment,
		"enemy_by_owner": {
			Rules.PLAYER_OWNER: owner_one_enemy,
			Rules.OPPONENT_OWNER: owner_two_enemy,
		},
		"profile_by_owner": {
			Rules.PLAYER_OWNER: owner_one_profile,
			Rules.OPPONENT_OWNER: owner_two_profile,
		},
	}


static func _definition_by_id(
	roster: Array[Dictionary],
	enemy_id: StringName
) -> Dictionary:
	for enemy: Dictionary in roster:
		if StringName(enemy.get("id", &"")) == enemy_id:
			return enemy
	return {}


static func _find_matchup(
	matchups: Array[Dictionary],
	first_id: StringName,
	second_id: StringName
) -> Dictionary:
	for matchup: Dictionary in matchups:
		var enemy_a := StringName(matchup.get("enemy_a_id", &""))
		var enemy_b := StringName(matchup.get("enemy_b_id", &""))
		if (
			(enemy_a == first_id and enemy_b == second_id)
			or (enemy_a == second_id and enemy_b == first_id)
		):
			return matchup
	return {}
