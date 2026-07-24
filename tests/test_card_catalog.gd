extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Decks = preload("res://scripts/duel_decks.gd")
const DuelEffects = preload("res://scripts/duel_effects.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_validation()
	_test_catalog_definitions()
	_test_definition_schema_validation()
	_test_definition_copy_isolation()
	_test_effect_declarations()
	_test_encounter_decks()
	_test_side_deck_pool()
	_test_draw_effect_validation()
	_test_activate_effect_declarations()
	_test_activate_effect_replacement()
	_test_trigger_ability_schema()

	if _failures == 0:
		print("CARD_CATALOG_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("CARD_CATALOG_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _test_catalog_validation() -> void:
	var validation_errors: Array[String] = Catalog.validate_catalog()
	_check(validation_errors.is_empty(), "All catalog definitions pass validation: %s" % str(validation_errors))
	_check(Catalog.get_all_card_ids().size() == 10, "Catalog contains the ten current cards")


func _test_catalog_definitions() -> void:
	var observed_ids: Dictionary = {}
	var expected_pictures: Dictionary = {
		&"CangSongYingKe1": "res://pics/LKT010_568.png",
		&"CangSongYingKe2": "res://pics/LKT010_568.png",
		&"gate_general": "res://pics/LKT010_002.png",
		&"meng_huo": "res://pics/LKT010_003.png",
		&"jiang_wei": "res://pics/LKT010_004.png",
		&"fa_zheng": "res://pics/LKT010_005.png",
		&"fire_envoy": "res://pics/LKT010_007.png",
		&"tiger_general": "res://pics/LKT010_008.png",
		&"strategist": "res://pics/LKT010_009.png",
		&"sun_zan": "res://pics/LKT010_010.png",
	}
	for card_id: StringName in Catalog.get_all_card_ids():
		var definition: Dictionary = Catalog.get_definition(card_id)
		_check(not definition.is_empty(), "Card %s resolves to a definition" % card_id)
		_check(StringName(definition.get("id", &"")) == card_id, "Card %s stores its stable ID" % card_id)
		_check(not definition.has("name"), "Card %s omits the retired name field" % card_id)
		var glyph: Variant = definition.get("glyph", null)
		_check(typeof(glyph) == TYPE_STRING and (glyph as String).length() >= 1 and (glyph as String).length() <= 7, "Card %s has a 1-7 character glyph title" % card_id)
		var picture: Variant = definition.get("picture", null)
		_check(typeof(picture) == TYPE_STRING and picture == expected_pictures[card_id], "Card %s maps to its approved picture" % card_id)
		_check(typeof(picture) == TYPE_STRING and ResourceLoader.exists(String(picture)), "Card %s picture resource exists" % card_id)
		for metadata_key: StringName in [&"sect", &"weapon", &"description", &"flavor"]:
			_check(definition.has(metadata_key) and typeof(definition[metadata_key]) == TYPE_STRING, "Card %s has String metadata %s" % [card_id, metadata_key])
		_check(typeof(definition.get("tier", null)) == TYPE_INT and int(definition["tier"]) >= 1, "Card %s has a positive integer tier" % card_id)
		var powers: Array = definition.get("powers", [])
		_check(powers.size() == 4, "Card %s has four edge powers" % card_id)
		var powers_are_integers: bool = true
		for power: Variant in powers:
			powers_are_integers = powers_are_integers and typeof(power) == TYPE_INT
		_check(powers_are_integers, "Card %s powers are integers" % card_id)
		observed_ids[card_id] = true
	_check(observed_ids.size() == 10, "Catalog IDs are unique")


func _test_definition_schema_validation() -> void:
	var valid_fixture: Dictionary = Catalog.get_definition(&"CangSongYingKe1")
	valid_fixture["id"] = &"fixture"
	for glyph: String in ["甲", "甲乙丙丁戊己庚"]:
		valid_fixture["glyph"] = glyph
		_check(Catalog.validate_definition(valid_fixture).is_empty(), "Glyph length %d passes definition validation" % glyph.length())
	for invalid_glyph: Variant in ["", "甲乙丙丁戊己庚辛", &"甲"]:
		valid_fixture["glyph"] = invalid_glyph
		_check(not Catalog.validate_definition(valid_fixture).is_empty(), "Invalid glyph %s fails definition validation" % str(invalid_glyph))
	valid_fixture["glyph"] = "甲"
	for invalid_picture: Variant in ["", 1, "res://pics/does_not_exist.png"]:
		var invalid_picture_definition: Dictionary = valid_fixture.duplicate(true)
		invalid_picture_definition["picture"] = invalid_picture
		_check(not Catalog.validate_definition(invalid_picture_definition).is_empty(), "Invalid picture %s fails validation" % str(invalid_picture))
	for metadata_key: StringName in [&"sect", &"weapon", &"description", &"flavor"]:
		var invalid_metadata: Dictionary = valid_fixture.duplicate(true)
		invalid_metadata[metadata_key] = 1
		_check(not Catalog.validate_definition(invalid_metadata).is_empty(), "Non-String %s metadata fails validation" % metadata_key)
	var missing_metadata: Dictionary = valid_fixture.duplicate(true)
	missing_metadata.erase("sect")
	_check(not Catalog.validate_definition(missing_metadata).is_empty(), "Missing required metadata fails validation")
	for invalid_tier: Variant in [0, -1, 1.5, "1"]:
		var invalid_tier_definition: Dictionary = valid_fixture.duplicate(true)
		invalid_tier_definition["tier"] = invalid_tier
		_check(not Catalog.validate_definition(invalid_tier_definition).is_empty(), "Invalid tier %s fails validation" % str(invalid_tier))
	var retired_name: Dictionary = valid_fixture.duplicate(true)
	retired_name["name"] = "Legacy"
	_check(not Catalog.validate_definition(retired_name).is_empty(), "Retired name metadata fails validation")

	var instance: Dictionary = Catalog.create_instance(&"CangSongYingKe1", 1, &"metadata_fixture")
	_check(not instance.has("name"), "Production runtime instances omit retired name metadata")
	for metadata_key: StringName in [&"glyph", &"picture", &"sect", &"weapon", &"description", &"flavor"]:
		_check(instance.has(metadata_key) and typeof(instance[metadata_key]) == TYPE_STRING, "Runtime instance copies String metadata %s" % metadata_key)
	_check(int(instance.get("tier", 0)) == 1, "Runtime instance copies tier metadata")


func _test_definition_copy_isolation() -> void:
	var first: Dictionary = Catalog.get_definition(&"gate_general")
	var second: Dictionary = Catalog.get_definition(&"gate_general")
	(first["powers"] as Array)[0] = 99
	(first["effects"] as Array).clear()
	_check(int((second["powers"] as Array)[0]) == 7, "Power mutation does not alter another catalog copy")
	_check((second["effects"] as Array).size() == 1, "Effect mutation does not alter another catalog copy")


func _test_effect_declarations() -> void:
	for card_id: StringName in [&"gate_general", &"tiger_general"]:
		var definition: Dictionary = Catalog.get_definition(card_id)
		var effects: Array = definition.get("effects", [])
		_check(effects.size() == 1, "%s declares one effect" % card_id)
		if effects.is_empty():
			continue
		var effect: Dictionary = effects[0]
		_check(StringName(effect.get("id", &"")) == Catalog.EFFECT_EXILE_INSTEAD_OF_FLIP, "%s declares exile instead of flip" % card_id)
		_check(effect.has("retained_on_flip") and bool(effect["retained_on_flip"]), "%s retains its exile ability after ownership flips" % card_id)
	for card_id: StringName in [&"fa_zheng", &"strategist"]:
		var definition: Dictionary = Catalog.get_definition(card_id)
		var effects: Array = definition.get("effects", [])
		_check(effects.size() == 1, "%s declares one effect" % card_id)
		if effects.is_empty():
			continue
		var effect: Dictionary = effects[0]
		_check(StringName(effect.get("id", &"")) == Catalog.EFFECT_DRAW_CARDS_ON_PLAY, "%s declares draw cards on play" % card_id)
		_check(int(effect.get("draw_count", 0)) == 2, "%s declares a draw count of two" % card_id)
		_check(not effect.has("retained_on_flip"), "%s relies on the default non-retained effect behavior" % card_id)
		var instance: Dictionary = Catalog.create_instance(card_id, 1, StringName("test_%s" % card_id))
		var active_effect: Dictionary = (instance.get("active_effects", []) as Array)[0]
		_check(active_effect.has("retained_on_flip") and not bool(active_effect["retained_on_flip"]), "%s runtime effect normalizes missing retention to false" % card_id)


func _test_encounter_decks() -> void:
	var player_ids: Array[StringName] = Decks.get_player_card_ids()
	var opponent_ids: Array[StringName] = Decks.get_opponent_card_ids()
	_check(player_ids == [&"CangSongYingKe2", &"gate_general", &"meng_huo", &"jiang_wei", &"fa_zheng"], "Player deck preserves current hand order")
	_check(opponent_ids == [&"CangSongYingKe1", &"fire_envoy", &"tiger_general", &"strategist", &"sun_zan"], "Opponent deck preserves current hand order")
	for card_id: StringName in player_ids + opponent_ids:
		_check(Catalog.has_card(card_id), "Deck card %s exists in the catalog" % card_id)


func _test_side_deck_pool() -> void:
	var side_ids: Array[StringName] = Decks.get_side_deck_card_ids()
	_check(side_ids == Catalog.get_all_card_ids(), "Side deck contains every catalog card exactly once")
	side_ids.clear()
	_check(Decks.get_side_deck_card_ids().size() == 10, "Side deck getter returns a defensive copy")


func _test_draw_effect_validation() -> void:
	var valid_errors: Array[String] = Catalog.validate_effect({
		"id": Catalog.EFFECT_DRAW_CARDS_ON_PLAY,
		"draw_count": 2,
	})
	_check(valid_errors.is_empty(), "Positive integer draw effects pass validation")
	for invalid_count: Variant in [null, 1.5, 0, -2]:
		var effect: Dictionary = {"id": Catalog.EFFECT_DRAW_CARDS_ON_PLAY}
		if invalid_count != null:
			effect["draw_count"] = invalid_count
		_check(not Catalog.validate_effect(effect).is_empty(), "Invalid draw count %s fails validation" % str(invalid_count))
	_check(not Catalog.validate_effect({
		"id": Catalog.EFFECT_DRAW_CARDS_ON_PLAY,
		"draw_count": 2,
		"retained_on_flip": "no",
	}).is_empty(), "Non-Boolean optional retention fails validation")


func _test_activate_effect_declarations() -> void:
	for card_id: StringName in [&"jiang_wei", &"sun_zan"]:
		var definition: Dictionary = Catalog.get_definition(card_id)
		_check(int(definition.get("starting_ki", 0)) == 1, "%s starts with one ki" % card_id)
		var effects: Array = definition.get("effects", [])
		_check(effects.size() == 1, "%s declares one effect" % card_id)
		if effects.is_empty():
			continue
		var effect: Dictionary = effects[0]
		_check(StringName(effect.get("id", &"")) == Catalog.EFFECT_MOVE_AND_ATTACK, "%s declares move and attack" % card_id)
		_check(StringName(effect.get("activation", &"")) == Catalog.ACTIVATION_DRAG_TO_TARGET, "%s activates by dragging" % card_id)
		_check(StringName(effect.get("target_rule", &"")) == Catalog.TARGET_ADJACENT_EMPTY_BOARD, "%s targets an adjacent empty board cell" % card_id)
		_check(not effect.has("retained_on_flip"), "%s relies on default non-retention" % card_id)
		var instance: Dictionary = Catalog.create_instance(card_id, 1, StringName("test_%s" % card_id))
		_check(int(instance.get("ki", 0)) == 1, "%s instances receive one ki" % card_id)
		var active_effect: Dictionary = (instance.get("active_effects", []) as Array)[0]
		_check(active_effect.has("retained_on_flip") and not bool(active_effect["retained_on_flip"]), "%s activate effect is lost on flip" % card_id)
	var invalid_activation: Dictionary = {
		"id": Catalog.EFFECT_MOVE_AND_ATTACK,
		"activation": &"click",
		"target_rule": Catalog.TARGET_ADJACENT_EMPTY_BOARD,
	}
	_check(not Catalog.validate_effect(invalid_activation).is_empty(), "Unsupported activation input fails validation")


func _test_activate_effect_replacement() -> void:
	var card: Dictionary = Catalog.create_instance(&"fa_zheng", 1, &"replacement_fixture")
	var first_activate: Dictionary = Catalog.get_definition(&"jiang_wei")["effects"][0]
	DuelEffects.replace_activate_effect(card, first_activate)
	_check((card.get("active_effects", []) as Array).size() == 2, "Adding activate effect preserves unrelated on-play effect")
	var replacement: Dictionary = first_activate.duplicate(true)
	replacement["id"] = &"replacement_activate_fixture"
	DuelEffects.replace_activate_effect(card, replacement)
	var active_effects: Array = card.get("active_effects", [])
	var activate_count: int = 0
	for effect_value: Variant in active_effects:
		if DuelEffects.is_activate_effect(effect_value as Dictionary):
			activate_count += 1
	_check(active_effects.size() == 2 and activate_count == 1, "New activate effect replaces the old activate slot")
	_check(StringName(DuelEffects.get_activate_effect(card).get("id", &"")) == &"replacement_activate_fixture", "Replacement activate effect becomes active")


func _test_trigger_ability_schema() -> void:
	var definition: Dictionary = Catalog.get_definition(&"meng_huo")
	var effects: Array = definition.get("effects", [])
	_check(effects.size() == 1, "Meng Huo declares one ability")
	var effect: Dictionary = effects[0]
	_check(StringName(effect.get("id", &"")) == Catalog.EFFECT_BATTLE_MOMENTUM, "Meng Huo declares battle momentum")
	_check(not effect.has("retained_on_flip"), "Battle momentum uses default non-retention")
	var triggers: Array = effect.get("triggers", [])
	_check(triggers.size() == 2, "Battle momentum declares two trigger rules")
	_check(StringName((triggers[0] as Dictionary).get("event", &"")) == Catalog.TRIGGER_AFTER_SUCCESSFUL_FLIP_BY_SELF, "First rule reacts to successful flips")
	_check(StringName((triggers[1] as Dictionary).get("event", &"")) == Catalog.TRIGGER_END_OWNER_TURN, "Second rule reacts at end of turn")
	var instance: Dictionary = Catalog.create_instance(&"meng_huo", 1, &"trigger_meng")
	_check(int(instance.get("ki", -1)) == 0, "Meng Huo starts with zero ki")
	var runtime_effect: Dictionary = (instance.get("active_effects", []) as Array)[0]
	_check(runtime_effect.has("retained_on_flip") and not bool(runtime_effect["retained_on_flip"]), "Battle momentum normalizes to non-retained")
	_check(Catalog.validate_effect(effect, &"meng_huo_fixture").is_empty(), "Approved trigger schema passes validation")

	var invalid_effects: Array[Dictionary] = [
		{"id": Catalog.EFFECT_BATTLE_MOMENTUM},
		{"id": Catalog.EFFECT_BATTLE_MOMENTUM, "triggers": []},
		{"id": Catalog.EFFECT_BATTLE_MOMENTUM, "triggers": [{"event": &"unknown", "actions": [{"type": Catalog.TRIGGER_ACTION_SPEND_ALL_KI}]}]},
		{"id": Catalog.EFFECT_BATTLE_MOMENTUM, "triggers": [{"event": Catalog.TRIGGER_END_OWNER_TURN, "actions": []}]},
		{"id": Catalog.EFFECT_BATTLE_MOMENTUM, "triggers": [{"event": Catalog.TRIGGER_END_OWNER_TURN, "condition": {"unknown": 1}, "actions": [{"type": Catalog.TRIGGER_ACTION_SPEND_ALL_KI}]}]},
		{"id": Catalog.EFFECT_BATTLE_MOMENTUM, "triggers": [{"event": Catalog.TRIGGER_END_OWNER_TURN, "condition": {Catalog.CONDITION_KI_AT_LEAST: -1}, "actions": [{"type": Catalog.TRIGGER_ACTION_SPEND_ALL_KI}]}]},
		{"id": Catalog.EFFECT_BATTLE_MOMENTUM, "triggers": [{"event": Catalog.TRIGGER_AFTER_SUCCESSFUL_FLIP_BY_SELF, "actions": [{"type": Catalog.TRIGGER_ACTION_GAIN_KI, "amount": 0}]}]},
		{"id": Catalog.EFFECT_BATTLE_MOMENTUM, "triggers": [{"event": Catalog.TRIGGER_AFTER_SUCCESSFUL_FLIP_BY_SELF, "actions": [{"type": &"unknown"}]}]},
	]
	for invalid_effect: Dictionary in invalid_effects:
		_check(not Catalog.validate_effect(invalid_effect).is_empty(), "Malformed trigger effect fails validation: %s" % str(invalid_effect))


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
