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
	_check_benchmark_roster()
	var card_ids: Array[StringName] = Cards.get_all_card_ids()
	var expected_by_level: Dictionary = {}
	var ordinary_enemy_count: int = 0
	for enemy_id: StringName in Catalog.get_all_enemy_ids():
		var definition: Dictionary = Catalog.get_definition(enemy_id)
		var level: int = int(definition["level"])
		if not expected_by_level.has(level):
			expected_by_level[level] = []
		if not bool(definition.get("special_only", false)):
			(expected_by_level[level] as Array).append(enemy_id)
			ordinary_enemy_count += 1
		_check(
			Catalog.is_self_castration_enabled(enemy_id)
			== bool(definition.get("self_castration_enabled", true)),
			"%s respects its configured self-castration switch" % enemy_id
		)
	var observed_enemy_ids: Dictionary = {}
	# Cover the supported campaign levels, including configured gaps and specials.
	for level: int in range(0, 16):
		var enemy_ids: Array[StringName] = Catalog.get_enemy_ids_for_level(level)
		_check(
			enemy_ids == expected_by_level.get(level, []),
			"Level %d contains exactly its configured ordinary candidates" % level
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
			for value: Variant in deck:
				_check(StringName(String(value)) in card_ids, "%s uses a known card" % enemy_id)
	_check(
		observed_enemy_ids.size() == ordinary_enemy_count,
		"Level candidate lookup covers every ordinary configured enemy"
	)
	var beginner_enemy: Dictionary = Catalog.get_definition(&"dukou_daoshi")
	_check(
		int(beginner_enemy.get("level", -1)) == 0
		and bool(beginner_enemy.get("special_only", false)),
		"Beginner Linghu Chong is an explicit level-zero special enemy"
	)
	_check(
		&"dukou_daoshi" not in observed_enemy_ids
		and Catalog.get_enemy_ids_for_level(0).is_empty(),
		"Special enemies never enter ordinary level candidate lookup"
	)

	_check_random_selection(expected_by_level)
	_check(Catalog.pick_random_enemy_id(0) == &"", "Invalid levels have no enemy")
	_check(Catalog.is_self_castration_enabled(&"missing_enemy"), "Unknown enemies keep the default effect gate")
	var duplicate_fixture: Dictionary = {
		"id": &"duplicate_fixture", "name": "规则测试", "level": 1,
		"deck": [
			&"TaiZuChangQuan",
			&"TaiZuChangQuan",
			&"CangSongYingKe1",
			&"CangSongYingKe2",
			&"CangSongYingKe3",
		],
	}
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
	var invalid_special: Dictionary = duplicate_fixture.duplicate(true)
	invalid_special["special_only"] = 1
	_check(
		not Catalog.validate_definition(invalid_special).is_empty(),
		"Enemy special-only declarations must be Boolean"
	)
	var valid_level_zero_special: Dictionary = duplicate_fixture.duplicate(true)
	valid_level_zero_special["level"] = 0
	valid_level_zero_special["special_only"] = true
	_check(
		Catalog.validate_definition(valid_level_zero_special).is_empty(),
		"Explicit special enemies may use level zero"
	)
	var invalid_level_zero_ordinary: Dictionary = valid_level_zero_special.duplicate(true)
	invalid_level_zero_ordinary["special_only"] = false
	_check(
		not Catalog.validate_definition(invalid_level_zero_ordinary).is_empty(),
		"Ordinary enemies may not use level zero"
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
	var catalog_ids: Array[StringName] = Catalog.get_all_enemy_ids()
	_check(roster.size() == catalog_ids.size(), "Benchmark roster covers the current catalog")
	var observed_ids: Dictionary = {}
	for definition: Dictionary in roster:
		var enemy_id := StringName(definition.get("id", &""))
		_check(not observed_ids.has(enemy_id), "%s appears once in benchmark roster" % enemy_id)
		observed_ids[enemy_id] = true
		_check(enemy_id in catalog_ids, "%s is a registered benchmark enemy" % enemy_id)
		if Catalog.has_enemy(enemy_id):
			var expected: Dictionary = Catalog.get_definition(enemy_id)
			expected["self_castration_enabled"] = bool(expected.get("self_castration_enabled", true))
			_check(definition == expected, "%s uses current catalog metadata and deck with the normalized switch" % enemy_id)
		_check(typeof(definition.get("self_castration_enabled")) == TYPE_BOOL, "%s has a normalized effect-gate switch" % enemy_id)
		_check(
			Catalog.validate_definition(definition).is_empty(),
			"%s is a valid benchmark enemy definition" % enemy_id
		)
	if roster.is_empty():
		_check(false, "Benchmark roster provides a real enemy fixture")
		return
	var original: Dictionary = roster[0].duplicate(true)
	var original_catalog: Dictionary = Catalog.get_definition(StringName(original["id"]))
	roster[0]["name"] = "mutated"
	(roster[0]["deck"] as Array)[0] = &"mutated_card"
	var fresh: Array[Dictionary] = Catalog.get_ai_benchmark_definitions()
	_check(
		fresh[0] == original
		and Catalog.get_definition(StringName(original["id"])) == original_catalog,
		"Benchmark roster returns deep-copied definitions"
	)


func _check_random_selection(expected_by_level: Dictionary) -> void:
	var difficulty_by_glyph: Dictionary = {}
	var difficulties: Array[int] = [0]
	for sect_id: StringName in Sects.get_all_sect_ids():
		var sect: Dictionary = Sects.get_definition(sect_id)
		var threshold: int = int(sect["min_random_difficulty"])
		difficulty_by_glyph[String(sect["glyph"])] = threshold
		for boundary: int in [maxi(0, threshold - 1), threshold]:
			if boundary not in difficulties:
				difficulties.append(boundary)
	var required_by_enemy: Dictionary = {}
	for enemy_id: StringName in Catalog.get_all_enemy_ids():
		var definition: Dictionary = Catalog.get_definition(enemy_id)
		var required: int = 0
		for card_id: StringName in definition["deck"]:
			var glyph: String = String(Cards.get_definition(card_id).get("sect", ""))
			required = maxi(required, int(difficulty_by_glyph.get(glyph, 0)))
		required_by_enemy[enemy_id] = required
		for difficulty: int in difficulties:
			_check(
				Catalog.is_enemy_randomly_available(definition, difficulty) == (difficulty >= required),
				"%s follows all deck sect gates at difficulty %d" % [enemy_id, difficulty]
			)
	for level: int in range(0, 16):
		for difficulty: int in difficulties:
			var expected: Array[StringName] = []
			for enemy_id: StringName in expected_by_level.get(level, []):
				if difficulty >= int(required_by_enemy[enemy_id]):
					expected.append(enemy_id)
			_check(
				Catalog.get_random_enemy_ids_for_level(level, difficulty) == expected,
				"Level %d difficulty %d contains exactly the eligible enemies" % [level, difficulty]
			)
			var seeded_a := RandomNumberGenerator.new()
			var seeded_b := RandomNumberGenerator.new()
			seeded_a.seed = 917
			seeded_b.seed = 917
			for draw_index: int in range(3):
				var selected: StringName = Catalog.pick_random_enemy_id(level, seeded_a, difficulty)
				_check(
					selected == Catalog.pick_random_enemy_id(level, seeded_b, difficulty),
					"Seeded selection repeats level %d difficulty %d draw %d" % [level, difficulty, draw_index]
				)
				_check(
					(selected == &"" and expected.is_empty()) or selected in expected,
					"Random selection stays in the eligible pool"
				)
	# A single gated card must control a mixed deck, even without an enemy sect tag.
	for glyph: String in difficulty_by_glyph:
		var threshold: int = int(difficulty_by_glyph[glyph])
		if threshold <= 0:
			continue
		for card_id: StringName in Cards.get_all_card_ids():
			if String(Cards.get_definition(card_id).get("sect", "")) != glyph:
				continue
			var mixed: Dictionary = {
				"deck": [&"TaiZuChangQuan", card_id, &"TaiZuChangQuan", &"TaiZuChangQuan", &"TaiZuChangQuan"],
			}
			_check(
				not Catalog.is_enemy_randomly_available(mixed, threshold - 1)
				and Catalog.is_enemy_randomly_available(mixed, threshold),
				"%s's single gated card controls a mixed deck" % glyph
			)
			break
	_check(not Catalog.is_enemy_randomly_available({"deck": [&"missing_card"]}, 10), "Unknown cards cannot enter random enemy pools")


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
