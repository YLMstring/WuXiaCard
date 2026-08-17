extends SceneTree

const Catalog = preload("res://scripts/sect_catalog.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_validation()
	_test_definition_contents()
	_test_schema_validation()
	_test_copy_isolation()

	if _failures == 0:
		print("SECT_CATALOG_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("SECT_CATALOG_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _test_catalog_validation() -> void:
	var validation_errors: Array[String] = Catalog.validate_catalog()
	_check(validation_errors.is_empty(), "All sect definitions pass validation: %s" % str(validation_errors))
	_check(
		not Catalog.get_all_sect_ids().is_empty(),
		"Sect catalog exposes at least one playable sect"
	)


func _test_definition_contents() -> void:
	var observed_ids: Dictionary = {}
	for sect_id: StringName in Catalog.get_all_sect_ids():
		var definition: Dictionary = Catalog.get_definition(sect_id)
		_check(Catalog.has_sect(sect_id), "Sect %s is discoverable" % sect_id)
		_check(StringName(definition.get("id", &"")) == sect_id, "Sect %s stores its stable ID" % sect_id)
		_check(not String(definition.get("glyph", "")).is_empty(), "Sect %s stores a display name" % sect_id)
		_check(not String(definition.get("picture", "")).is_empty(), "Sect %s stores a picture path" % sect_id)
		_check(ResourceLoader.exists(String(definition.get("picture", ""))), "Sect %s picture exists" % sect_id)
		_check(not String(definition.get("sect", "")).is_empty(), "Sect %s stores its region" % sect_id)
		_check(int(definition.get("tier", 0)) > 0, "Sect %s stores positive prestige" % sect_id)
		_check(not String(definition.get("weapon", "")).is_empty(), "Sect %s stores its specialty" % sect_id)
		_check(not String(definition.get("description", "")).is_empty(), "Sect %s has a description" % sect_id)
		_check(not String(definition.get("flavor", "")).is_empty(), "Sect %s has flavor text" % sect_id)
		_check(not definition.has("powers"), "Sect %s omits powers" % sect_id)
		_check(not definition.has("abilities"), "Sect %s omits abilities" % sect_id)
		observed_ids[sect_id] = true
	_check(
		observed_ids.size() == Catalog.get_all_sect_ids().size(),
		"Sect catalog IDs are unique"
	)


func _test_schema_validation() -> void:
	var valid_fixture: Dictionary = Catalog.get_definition(&"HuaShanPai")
	valid_fixture["id"] = &"fixture"
	_check(Catalog.validate_definition(valid_fixture).is_empty(), "Complete fixture passes validation")

	for field: StringName in [&"glyph", &"picture", &"sect", &"weapon", &"description", &"flavor"]:
		var empty_metadata: Dictionary = valid_fixture.duplicate(true)
		empty_metadata[field] = ""
		_check(
			not Catalog.validate_definition(empty_metadata).is_empty(),
			"Empty %s metadata fails validation" % field
		)
		var wrong_type: Dictionary = valid_fixture.duplicate(true)
		wrong_type[field] = 1
		_check(
			not Catalog.validate_definition(wrong_type).is_empty(),
			"Non-String %s metadata fails validation" % field
		)

	for invalid_glyph: String in ["甲乙丙丁戊己庚辛"]:
		var invalid_title: Dictionary = valid_fixture.duplicate(true)
		invalid_title["glyph"] = invalid_glyph
		_check(not Catalog.validate_definition(invalid_title).is_empty(), "Overlong glyph fails validation")
	for invalid_tier: Variant in [0, -1, 1.5, "1"]:
		var invalid_prestige: Dictionary = valid_fixture.duplicate(true)
		invalid_prestige["tier"] = invalid_tier
		_check(
			not Catalog.validate_definition(invalid_prestige).is_empty(),
			"Invalid prestige %s fails validation" % str(invalid_tier)
		)
	for unsupported_field: StringName in [&"powers", &"abilities"]:
		var playable_metadata: Dictionary = valid_fixture.duplicate(true)
		playable_metadata[unsupported_field] = []
		_check(
			not Catalog.validate_definition(playable_metadata).is_empty(),
			"Playable-card field %s fails sect validation" % unsupported_field
		)
	var missing_picture: Dictionary = valid_fixture.duplicate(true)
	missing_picture["picture"] = "res://pics/does_not_exist.png"
	_check(not Catalog.validate_definition(missing_picture).is_empty(), "Missing picture resource fails validation")
	var mismatched_id: Dictionary = valid_fixture.duplicate(true)
	mismatched_id["id"] = &"another_sect"
	_check(not Catalog.validate_definition(mismatched_id).is_empty(), "Mismatched definition ID fails validation")


func _test_copy_isolation() -> void:
	var expected_ids: Array[StringName] = Catalog.get_all_sect_ids()
	var ids: Array[StringName] = Catalog.get_all_sect_ids()
	ids.clear()
	_check(Catalog.get_all_sect_ids() == expected_ids, "ID getter returns a defensive copy")
	var first: Dictionary = Catalog.get_definition(&"HuaShanPai")
	var original_glyph: String = String(first.get("glyph", ""))
	first["glyph"] = "已修改"
	var second: Dictionary = Catalog.get_definition(&"HuaShanPai")
	_check(second.get("glyph", "") == original_glyph, "Definition getter returns a deep defensive copy")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
