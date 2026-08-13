extends SceneTree

const Catalog = preload("res://scripts/enemy_catalog.gd")
const Cards = preload("res://scripts/card_catalog.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(Catalog.validate_catalog().is_empty(), "Enemy catalog validates")
	_check(Catalog.get_all_enemy_ids().size() == 30, "Catalog contains two enemies per level")
	var card_ids: Array[StringName] = Cards.get_all_card_ids()
	var observed_decks: Dictionary = {}
	for level: int in range(1, 16):
		var enemy_ids: Array[StringName] = Catalog.get_enemy_ids_for_level(level)
		_check(enemy_ids.size() == 2, "Level %d has two random candidates" % level)
		for enemy_id: StringName in enemy_ids:
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
		not Catalog.is_self_castration_enabled(&"qingfeng_xuedi")
		and not Catalog.is_self_castration_enabled(&"dukou_xiaoke"),
		"Both Young Escort Lin Pingzhi encounters explicitly disable self-castration"
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
	_finish()


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
