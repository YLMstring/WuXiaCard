extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Decks = preload("res://scripts/duel_decks.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_validation()
	_test_catalog_definitions()
	_test_definition_copy_isolation()
	_test_effect_declarations()
	_test_encounter_decks()
	_test_side_deck_pool()
	_test_draw_effect_validation()

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
	for card_id: StringName in Catalog.get_all_card_ids():
		var definition: Dictionary = Catalog.get_definition(card_id)
		_check(not definition.is_empty(), "Card %s resolves to a definition" % card_id)
		_check(StringName(definition.get("id", &"")) == card_id, "Card %s stores its stable ID" % card_id)
		_check(not String(definition.get("name", "")).is_empty(), "Card %s has a display name" % card_id)
		_check(not String(definition.get("glyph", "")).is_empty(), "Card %s has a glyph" % card_id)
		var powers: Array = definition.get("powers", [])
		_check(powers.size() == 4, "Card %s has four edge powers" % card_id)
		var powers_are_integers: bool = true
		for power: Variant in powers:
			powers_are_integers = powers_are_integers and typeof(power) == TYPE_INT
		_check(powers_are_integers, "Card %s powers are integers" % card_id)
		observed_ids[card_id] = true
	_check(observed_ids.size() == 10, "Catalog IDs are unique")


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
	_check(player_ids == [&"xu_shu", &"gate_general", &"meng_huo", &"jiang_wei", &"fa_zheng"], "Player deck preserves current hand order")
	_check(opponent_ids == [&"zhang_ren", &"fire_envoy", &"tiger_general", &"strategist", &"sun_zan"], "Opponent deck preserves current hand order")
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


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
