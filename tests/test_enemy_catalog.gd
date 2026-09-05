extends SceneTree

const Catalog = preload("res://scripts/enemy_catalog.gd")
const Cards = preload("res://scripts/card_catalog.gd")
const Sects = preload("res://scripts/sect_catalog.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(Catalog.validate_catalog().is_empty(), "Enemy catalog validates")
	_check(Catalog.get_all_enemy_ids().size() == 34, "Normal enemy roster contains 34 enemies")
	_check(
		Catalog.has_enemy(&"wulin_sanren")
		and Catalog.has_enemy(&"wulin_sanren2"),
		"Dongfang Bubai and Zhang Sanfeng are normal enemies"
	)
	_check_benchmark_roster()
	var card_ids: Array[StringName] = Cards.get_all_card_ids()
	var observed_decks: Dictionary = {}
	var observed_enemy_ids: Dictionary = {}
	for level: int in range(1, 16):
		var enemy_ids: Array[StringName] = Catalog.get_enemy_ids_for_level(level)
		_check(
			not enemy_ids.is_empty(),
			"Level %d has at least one configured enemy candidate" % level
		)
		for enemy_id: StringName in enemy_ids:
			_check(not observed_enemy_ids.has(enemy_id), "%s appears at exactly one level" % enemy_id)
			observed_enemy_ids[enemy_id] = true
			var definition: Dictionary = Catalog.get_definition(enemy_id)
			_check(StringName(definition["id"]) == enemy_id, "%s preserves its ID" % enemy_id)
			_check(int(definition["level"]) == level, "%s preserves its level" % enemy_id)
			_check(not String(definition["name"]).is_empty(), "%s has a name" % enemy_id)
			var deck: Array = definition["deck"]
			_check(deck.size() == 5, "%s has a five-card deck" % enemy_id)
			var deck_signature: String = "|".join(
				deck.map(func(value: Variant) -> String: return String(value))
			)
			_check(not observed_decks.has(deck_signature), "%s has a unique deck" % enemy_id)
			observed_decks[deck_signature] = enemy_id
			for value: Variant in deck:
				_check(StringName(String(value)) in card_ids, "%s uses a known card" % enemy_id)
	_check(
		observed_enemy_ids.size() == Catalog.get_all_enemy_ids().size(),
		"Level candidate lookup covers every configured enemy"
	)

	var seeded_a := RandomNumberGenerator.new()
	var seeded_b := RandomNumberGenerator.new()
	seeded_a.seed = 917
	seeded_b.seed = 917
	_check(
		Catalog.pick_random_enemy_id(8, seeded_a)
		== Catalog.pick_random_enemy_id(8, seeded_b),
		"Seeded enemy selection is deterministic"
	)
	_check(Catalog.pick_random_enemy_id(0) == &"", "Invalid levels have no enemy")
	_check(
		not Catalog.is_self_castration_enabled(&"qingfeng_xuedi"),
		"Young Escort Lin Pingzhi explicitly disables self-castration"
	)
	_check(
		Catalog.is_self_castration_enabled(&"dukou_xiaoke"),
		"Shi Biaotou keeps the default self-castration behavior"
	)
	_check(
		Catalog.is_self_castration_enabled(&"tieshan_menren"),
		"Enemies without a declaration enable self-castration by default"
	)
	var duplicate_fixture: Dictionary = Catalog.get_definition(&"qingfeng_xuedi")
	duplicate_fixture["id"] = &"duplicate_fixture"
	duplicate_fixture["deck"] = [
		&"TaiZuChangQuan",
		&"TaiZuChangQuan",
		&"CangSongYingKe1",
		&"CangSongYingKe2",
		&"CangSongYingKe3",
	]
	_check(
		Catalog.validate_definition(duplicate_fixture).is_empty(),
		"Enemy definitions may contain exact duplicates and repeated glyphs"
	)
	var short_fixture: Dictionary = duplicate_fixture.duplicate(true)
	short_fixture["deck"] = [&"TaiZuChangQuan"]
	_check(
		not Catalog.validate_definition(short_fixture).is_empty(),
		"Enemy definitions still require exactly five cards"
	)
	var unknown_fixture: Dictionary = duplicate_fixture.duplicate(true)
	unknown_fixture["deck"] = [
		&"TaiZuChangQuan",
		&"TaiZuChangQuan",
		&"TaiZuChangQuan",
		&"TaiZuChangQuan",
		&"missing_card",
	]
	_check(
		not Catalog.validate_definition(unknown_fixture).is_empty(),
		"Enemy definitions still reject unknown cards"
	)
	var invalid_switch: Dictionary = duplicate_fixture.duplicate(true)
	invalid_switch["self_castration_enabled"] = 0
	_check(
		not Catalog.validate_definition(invalid_switch).is_empty(),
		"Enemy self-castration declarations must be Boolean"
	)
	var valid_sect: Dictionary = duplicate_fixture.duplicate(true)
	valid_sect["sect_id"] = &"TaiShanPai"
	_check(
		Catalog.validate_definition(valid_sect).is_empty(),
		"Enemy definitions accept a known StringName sect declaration"
	)
	var invalid_sect: Dictionary = duplicate_fixture.duplicate(true)
	invalid_sect["sect_id"] = &"missing_sect"
	_check(
		not Catalog.validate_definition(invalid_sect).is_empty(),
		"Enemy definitions reject unknown sect declarations"
	)
	var wrong_sect_type: Dictionary = duplicate_fixture.duplicate(true)
	wrong_sect_type["sect_id"] = String(Sects.get_all_sect_ids()[0])
	_check(
		not Catalog.validate_definition(wrong_sect_type).is_empty(),
		"Enemy sect declarations must be StringName values"
	)
	_finish()


func _check_benchmark_roster() -> void:
	var roster: Array[Dictionary] = Catalog.get_ai_benchmark_definitions()
	_check(roster.size() == 34, "AI benchmark roster contains 34 enemy definitions")
	_check(
		StringName(roster[32].get("id", &"")) == &"wulin_sanren"
		and StringName(roster[33].get("id", &"")) == &"wulin_sanren2",
		"Dongfang Bubai and Zhang Sanfeng finish the normal catalog order"
	)
	var dongfang: Dictionary = roster[32]
	var zhang: Dictionary = roster[33]
	_check(
		dongfang.get("deck", []) == [
			&"KuiHua1", &"KuiHua4", &"KuiHua3", &"KuiHua2", &"KuiHua2"
		],
		"Dongfang Bubai preserves the approved benchmark deck"
	)
	_check(
		zhang.get("deck", []) == [
			&"TaiJiLuanHuan5",
			&"TaiJiYinYang5",
			&"TaiJiSanHuan5",
			&"TaiJiDaKui5",
			&"DuGu9Jian1",
		],
		"Zhang Sanfeng preserves the approved benchmark deck"
	)
	_check(
		typeof(dongfang.get("self_castration_enabled")) == TYPE_BOOL
		and bool(dongfang.get("self_castration_enabled")),
		"Dongfang Bubai normalizes self-castration to an explicit Boolean"
	)
	_check(
		Catalog.get_enemy_ids_for_level(15) == [
			&"wulin_sanren3", &"wulin_sanren", &"wulin_sanren2",
		],
		"Level fifteen includes all three normal final enemies"
	)
	var observed_ids: Dictionary = {}
	for definition: Dictionary in roster:
		var enemy_id := StringName(definition.get("id", &""))
		_check(not observed_ids.has(enemy_id), "%s appears once in benchmark roster" % enemy_id)
		observed_ids[enemy_id] = true
		_check(
			Catalog.validate_definition(definition).is_empty(),
			"%s is a valid benchmark enemy definition" % enemy_id
		)
	var original_name: String = String(roster[0].get("name", ""))
	roster[0]["name"] = "mutated"
	var fresh: Array[Dictionary] = Catalog.get_ai_benchmark_definitions()
	_check(
		String(fresh[0].get("name", "")) == original_name,
		"Benchmark roster returns deep-copied definitions"
	)


func _finish() -> void:
	if _failures == 0:
		print("ENEMY_CATALOG_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("ENEMY_CATALOG_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
