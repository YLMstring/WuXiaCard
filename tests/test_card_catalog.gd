extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Decks = preload("res://scripts/duel_decks.gd")
const Abilities = preload("res://scripts/duel_abilities.gd")

const NEW_SECT_CARD_IDS: Array[StringName] = [
	&"TaiShan18Pan1",
	&"WuDaFuJian1",
	&"QiXinLuoChangKong2",
	&"TianChangZhang3",
	&"HenShanJianZhen2",
	&"JinZhenDuJie1",
	&"WanHuaJian1",
	&"MianLiCangZhen2",
	&"chilian_huifeng",
	&"shahai_zhuri",
	&"damo_guzhan",
	&"dielang_tuizhou",
	&"huichao_tingjin",
	&"canghai_sandie",
	&"haitian_yizhang",
	&"zhujian_cangfeng",
	&"luming_wenlu",
	&"jingwei_dingju",
	&"zhishang_shanhe",
]

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_validation()
	_test_catalog_definitions()
	_test_definition_schema_validation()
	_test_definition_copy_isolation()
	_test_new_sect_card_definitions()
	_test_ability_declarations()
	_test_encounter_decks()
	_test_side_deck_pool()
	_test_draw_action_validation()
	_test_activate_ability_declarations()
	_test_activate_ability_replacement()
	_test_trigger_ability_schema()
	_test_welcoming_pine_schema()

	if _failures == 0:
		print("CARD_CATALOG_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("CARD_CATALOG_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _test_catalog_validation() -> void:
	var validation_errors: Array[String] = Catalog.validate_catalog()
	_check(validation_errors.is_empty(), "All catalog definitions pass validation: %s" % str(validation_errors))
	_check(Catalog.get_all_card_ids().size() == 58, "Catalog contains all fifty-eight current cards")


func _test_catalog_definitions() -> void:
	var observed_ids: Dictionary = {}
	for card_id: StringName in Catalog.get_all_card_ids():
		var definition: Dictionary = Catalog.get_definition(card_id)
		_check(not definition.is_empty(), "Card %s resolves to a definition" % card_id)
		_check(StringName(definition.get("id", &"")) == card_id, "Card %s stores its stable ID" % card_id)
		_check(not definition.has("name"), "Card %s omits the retired name field" % card_id)
		var glyph: Variant = definition.get("glyph", null)
		_check(typeof(glyph) == TYPE_STRING and (glyph as String).length() >= 1 and (glyph as String).length() <= 7, "Card %s has a 1-7 character glyph title" % card_id)
		var picture: Variant = definition.get("picture", null)
		_check(typeof(picture) == TYPE_STRING and not String(picture).is_empty(), "Card %s declares a picture" % card_id)
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
	_check(observed_ids.size() == 58, "Catalog IDs are unique")


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
	(first["abilities"] as Array).clear()
	_check(int((second["powers"] as Array)[0]) == 7, "Power mutation does not alter another catalog copy")
	_check((second["abilities"] as Array).size() == 1, "Ability mutation does not alter another catalog copy")


func _test_new_sect_card_definitions() -> void:
	var observed_new_sect_ids: Array[StringName] = []
	for card_id: StringName in Catalog.get_all_card_ids():
		if card_id in NEW_SECT_CARD_IDS:
			observed_new_sect_ids.append(card_id)
	_check(
		observed_new_sect_ids == NEW_SECT_CARD_IDS,
		"The original nineteen sect-card families preserve catalog order"
	)
	for card_id: StringName in NEW_SECT_CARD_IDS:
		var definition: Dictionary = Catalog.get_definition(card_id)
		for field: StringName in [&"glyph", &"picture", &"sect", &"weapon", &"flavor"]:
			_check(
				typeof(definition.get(field, null)) == TYPE_STRING
				and not String(definition[field]).strip_edges().is_empty(),
				"%s has nonempty %s metadata" % [card_id, field]
			)
		_check(typeof(definition.get("description", null)) == TYPE_STRING, "%s has String description metadata" % card_id)


func _test_ability_declarations() -> void:
	for card_id: StringName in [&"gate_general", &"tiger_general"]:
		var definition: Dictionary = Catalog.get_definition(card_id)
		var abilities: Array = definition.get("abilities", [])
		_check(abilities.size() == 1, "%s declares one ability" % card_id)
		if abilities.is_empty():
			continue
		var ability: Dictionary = abilities[0]
		_check(not ability.has("id"), "%s ability is identity-free" % card_id)
		_check(ability.has("retained_on_flip") and bool(ability["retained_on_flip"]), "%s retains its exile ability after ownership flips" % card_id)
		var trigger: Dictionary = (ability.get("triggers", []) as Array)[0]
		_check(StringName(trigger.get("event", &"")) == Catalog.CARD_BE_ATTACKED, "%s reacts before an attack resolves" % card_id)
		_check(trigger.get("conditions", []) == [{"type": Catalog.CONDITION_ATTACKER_CARD_IS_SELF}], "%s only replaces its own attacks" % card_id)
		_check(trigger.get("actions", []) == [{"type": Catalog.ACTION_EXILE_ATTACKED_CARD}], "%s exiles the attacked card" % card_id)
	for card_id: StringName in [&"TuNaShu2", &"TuNaShu1"]:
		var definition: Dictionary = Catalog.get_definition(card_id)
		var abilities: Array = definition.get("abilities", [])
		_check(abilities.size() == 1, "%s declares one ability" % card_id)
		if abilities.is_empty():
			continue
		var ability: Dictionary = abilities[0]
		_check(not ability.has("id"), "%s draw ability is identity-free" % card_id)
		_check(not ability.has("retained_on_flip"), "%s relies on default non-retention" % card_id)
		var trigger: Dictionary = (ability.get("triggers", []) as Array)[0]
		_check(StringName(trigger.get("event", &"")) == Catalog.TRIGGER_CARD_AFTER_SUMMONED, "%s draws after summon reactions" % card_id)
		_check(trigger.get("conditions", []) == [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}], "%s only draws for its own summon" % card_id)
		var expected_amount: int = 2 if card_id == &"TuNaShu2" else 1
		_check(trigger.get("actions", []) == [{"type": Catalog.ACTION_DRAW_CARDS, "amount": expected_amount}], "%s declares its catalog draw amount" % card_id)
		var instance: Dictionary = Catalog.create_instance(card_id, 1, StringName("test_%s" % card_id))
		var active_ability: Dictionary = (instance.get("active_abilities", []) as Array)[0]
		_check(active_ability.has("retained_on_flip") and not bool(active_ability["retained_on_flip"]), "%s runtime ability normalizes missing retention to false" % card_id)


func _test_encounter_decks() -> void:
	var test_profile_path: String = "user://card_catalog_deck_test.json"
	for suffix: String in ["", ".tmp", ".bak"]:
		var cleanup_path: String = test_profile_path + suffix
		if FileAccess.file_exists(cleanup_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(cleanup_path))
	var player_ids: Array[StringName] = Decks.get_player_card_ids(test_profile_path)
	var opponent_ids: Array[StringName] = Decks.get_opponent_card_ids()
	_check(player_ids == [&"CangSongYingKe2", &"gate_general", &"meng_huo", &"YouFenLaiYi2", &"TuNaShu2"], "Player deck preserves current hand order")
	_check(opponent_ids == [&"CangSongYingKe1", &"fire_envoy", &"tiger_general", &"TuNaShu1", &"TuNaShu1"], "Opponent deck preserves current hand order")
	for card_id: StringName in player_ids + opponent_ids:
		_check(Catalog.has_card(card_id), "Deck card %s exists in the catalog" % card_id)
	for suffix: String in ["", ".tmp", ".bak"]:
		var cleanup_path: String = test_profile_path + suffix
		if FileAccess.file_exists(cleanup_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(cleanup_path))


func _test_side_deck_pool() -> void:
	var main_ids: Array[StringName] = Decks.get_player_card_ids()
	var side_ids: Array[StringName] = Decks.get_side_deck_card_ids(main_ids)
	_check(not side_ids.is_empty(), "A catalog-backed main deck derives side cards")
	var observed_glyphs: Dictionary = {}
	for card_id: StringName in side_ids:
		var glyph: String = String(Catalog.get_definition(card_id).get("glyph", ""))
		_check(not observed_glyphs.has(glyph), "Side deck keeps at most one card per glyph")
		observed_glyphs[glyph] = true
	side_ids.clear()
	_check(
		not Decks.get_side_deck_card_ids(main_ids).is_empty(),
		"Side deck getter returns a defensive result"
	)


func _test_draw_action_validation() -> void:
	var valid_errors: Array[String] = Catalog.validate_ability({
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"actions": [{"type": Catalog.ACTION_DRAW_CARDS, "amount": 2}],
		}],
	})
	_check(valid_errors.is_empty(), "Positive integer draw actions pass validation")
	for invalid_count: Variant in [null, 1.5, 0, -2]:
		var action: Dictionary = {"type": Catalog.ACTION_DRAW_CARDS}
		if invalid_count != null:
			action["amount"] = invalid_count
		var ability: Dictionary = {
			"triggers": [{
				"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
				"actions": [action],
			}],
		}
		_check(not Catalog.validate_ability(ability).is_empty(), "Invalid draw amount %s fails validation" % str(invalid_count))
	_check(not Catalog.validate_ability({
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"actions": [{"type": Catalog.ACTION_DRAW_CARDS, "amount": 2}],
		}],
		"retained_on_flip": "no",
	}).is_empty(), "Non-Boolean optional retention fails validation")
	_check(not Catalog.validate_ability({
		"id": &"legacy",
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"actions": [{"type": Catalog.ACTION_DRAW_CARDS, "amount": 2}],
		}],
	}).is_empty(), "Legacy ability IDs fail validation")
	_check(not Catalog.validate_ability({
		"draw_count": 2,
		"triggers": [{
			"event": Catalog.TRIGGER_CARD_AFTER_SUMMONED,
			"actions": [{"type": Catalog.ACTION_DRAW_CARDS, "amount": 2}],
		}],
	}).is_empty(), "Legacy draw_count fails validation")


func _test_activate_ability_declarations() -> void:
	var expected_rules: Dictionary = {
		&"YouFenLaiYi2": [Catalog.TARGET_ADJACENT_EMPTY_BOARD],
		&"YouFenLaiYi3": [
			Catalog.TARGET_ADJACENT_EMPTY_BOARD,
			Catalog.TARGET_ADJACENT_ALLY_BOARD,
		],
		&"YouFenLaiYi4": [
			Catalog.TARGET_ADJACENT_EMPTY_BOARD,
			Catalog.TARGET_ADJACENT_ALLY_BOARD,
			Catalog.TARGET_ADJACENT_ENEMY_BOARD,
		],
	}
	for card_id: StringName in expected_rules:
		var definition: Dictionary = Catalog.get_definition(card_id)
		var abilities: Array = definition.get("abilities", [])
		var rules: Array = expected_rules[card_id]
		_check(abilities.size() == rules.size(), "%s declares every cataloged activation" % card_id)
		for ability_index: int in range(abilities.size()):
			var ability: Dictionary = abilities[ability_index]
			_check(not ability.has("id"), "%s activation %d is identity-free" % [card_id, ability_index])
			_check(bool(ability.get("retained_on_flip", false)), "%s activation %d is retained on flip" % [card_id, ability_index])
			var activation: Dictionary = ability.get("activation", {})
			_check(StringName(activation.get("input", &"")) == Catalog.ACTIVATION_DRAG_TO_TARGET, "%s activation %d uses dragging" % [card_id, ability_index])
			_check(StringName(activation.get("target_rule", &"")) == rules[ability_index], "%s activation %d preserves target priority" % [card_id, ability_index])
			_check(activation.get("costs", []) == [{"type": Catalog.ACTION_SPEND_KI, "amount": 1}], "%s activation %d spends one ki" % [card_id, ability_index])
			var expected_first_action: StringName = (
				Catalog.ACTION_MOVE_SELF_TO_TARGET
				if ability_index == 0
				else Catalog.ACTION_SWAP_SELF_WITH_TARGET
			)
			_check(
				activation.get("actions", []) == [
					{"type": expected_first_action},
					{"type": Catalog.ACTION_STANDARD_ATTACK_WITH_SELF},
				],
				"%s activation %d performs its board operation then attacks" % [card_id, ability_index]
			)
		var instance: Dictionary = Catalog.create_instance(card_id, 1, StringName("test_%s" % card_id))
		_check((Abilities.get_activate_abilities(instance) as Array).size() == rules.size(), "%s instances preserve every activation" % card_id)
		_check(Abilities.card_uses_ki(instance), "%s uses ki when any activation exists" % card_id)
	var invalid_activation: Dictionary = {
		"activation": {
			"input": &"click",
			"target_rule": Catalog.TARGET_ADJACENT_EMPTY_BOARD,
			"costs": [{"type": Catalog.ACTION_SPEND_KI, "amount": 1}],
			"actions": [{"type": Catalog.ACTION_MOVE_SELF_TO_TARGET}],
		},
	}
	_check(not Catalog.validate_ability(invalid_activation).is_empty(), "Unsupported activation input fails validation")
	var duplicate_activation_definition: Dictionary = Catalog.get_definition(&"CangSongYingKe1")
	var activate_ability: Dictionary = Catalog.get_definition(&"YouFenLaiYi2")["abilities"][0]
	duplicate_activation_definition["id"] = &"fixture"
	duplicate_activation_definition["abilities"] = [
		activate_ability.duplicate(true),
		activate_ability.duplicate(true),
	]
	_check(
		Catalog.validate_definition(duplicate_activation_definition).is_empty(),
		"More than one valid activation in a definition passes validation"
	)


func _test_activate_ability_replacement() -> void:
	var card: Dictionary = Catalog.create_instance(&"TuNaShu2", 1, &"replacement_fixture")
	var first_activate: Dictionary = Catalog.get_definition(&"YouFenLaiYi2")["abilities"][0]
	Abilities.replace_activate_ability(card, first_activate)
	_check((card.get("active_abilities", []) as Array).size() == 2, "Adding activation preserves unrelated passive ability")
	var second_activate: Dictionary = Catalog.get_definition(&"YouFenLaiYi3")["abilities"][1]
	(card.get("active_abilities", []) as Array).append(second_activate.duplicate(true))
	var replacement: Dictionary = first_activate.duplicate(true)
	(replacement["activation"] as Dictionary)["target_rule"] = Catalog.TARGET_ADJACENT_EMPTY_BOARD
	Abilities.replace_activate_ability(card, replacement)
	var active_abilities: Array = card.get("active_abilities", [])
	var activate_count: int = 0
	for ability_value: Variant in active_abilities:
		if Abilities.is_activate_ability(ability_value as Dictionary):
			activate_count += 1
	_check(active_abilities.size() == 2 and activate_count == 1, "New activation replaces all old activation slots")
	_check(not Abilities.get_activation(card).is_empty(), "Replacement activation becomes active")


func _test_trigger_ability_schema() -> void:
	var definition: Dictionary = Catalog.get_definition(&"meng_huo")
	var abilities: Array = definition.get("abilities", [])
	_check(abilities.size() == 1, "Meng Huo declares one ability")
	var ability: Dictionary = abilities[0]
	_check(not ability.has("id"), "Meng Huo ability is identity-free")
	_check(not ability.has("retained_on_flip"), "Battle momentum uses default non-retention")
	var triggers: Array = ability.get("triggers", [])
	_check(triggers.size() == 2, "Battle momentum declares two trigger rules")
	_check(StringName((triggers[0] as Dictionary).get("event", &"")) == Catalog.CARD_AFTER_FLIPPED, "First rule reacts after flips")
	_check((triggers[0] as Dictionary).get("conditions", []) == [{"type": Catalog.CONDITION_ATTACKER_CARD_IS_SELF}], "First rule requires Meng Huo as attacker")
	_check(StringName((triggers[1] as Dictionary).get("event", &"")) == Catalog.TRIGGER_END_OWNER_TURN, "Second rule reacts at end of turn")
	_check(
		(triggers[1] as Dictionary).get("conditions", []) == [
			{"type": Catalog.CONDITION_TURN_OWNER_IS_SELF},
			{"type": Catalog.CONDITION_KI_AT_LEAST, "amount": 1},
		],
		"Meng Huo uses the shared typed conditions array"
	)
	var instance: Dictionary = Catalog.create_instance(&"meng_huo", 1, &"trigger_meng")
	_check(int(instance.get("ki", -1)) == 0, "Meng Huo starts with zero ki")
	var runtime_ability: Dictionary = (instance.get("active_abilities", []) as Array)[0]
	_check(runtime_ability.has("retained_on_flip") and not bool(runtime_ability["retained_on_flip"]), "Battle momentum normalizes to non-retained")
	_check(Catalog.validate_ability(ability, &"meng_huo_fixture").is_empty(), "Approved trigger schema passes validation")

	var invalid_abilities: Array[Dictionary] = [
		{},
		{"triggers": []},
		{"triggers": [{"event": &"unknown", "actions": [{"type": Catalog.ACTION_SPEND_ALL_KI}]}]},
		{"triggers": [{"event": Catalog.TRIGGER_END_OWNER_TURN, "actions": []}]},
		{"triggers": [{"event": Catalog.TRIGGER_END_OWNER_TURN, "conditions": {}, "actions": [{"type": Catalog.ACTION_SPEND_ALL_KI}]}]},
		{"triggers": [{"event": Catalog.TRIGGER_END_OWNER_TURN, "conditions": [1], "actions": [{"type": Catalog.ACTION_SPEND_ALL_KI}]}]},
		{"triggers": [{"event": Catalog.TRIGGER_END_OWNER_TURN, "conditions": [{"type": &"unknown"}], "actions": [{"type": Catalog.ACTION_SPEND_ALL_KI}]}]},
		{"triggers": [{"event": Catalog.TRIGGER_END_OWNER_TURN, "conditions": [{"type": Catalog.CONDITION_KI_AT_LEAST}], "actions": [{"type": Catalog.ACTION_SPEND_ALL_KI}]}]},
		{"triggers": [{"event": Catalog.TRIGGER_END_OWNER_TURN, "conditions": [{"type": Catalog.CONDITION_KI_AT_LEAST, "amount": 1.5}], "actions": [{"type": Catalog.ACTION_SPEND_ALL_KI}]}]},
		{"triggers": [{"event": Catalog.TRIGGER_END_OWNER_TURN, "conditions": [{"type": Catalog.CONDITION_KI_AT_LEAST, "amount": -1}], "actions": [{"type": Catalog.ACTION_SPEND_ALL_KI}]}]},
		{"triggers": [{"event": Catalog.TRIGGER_END_OWNER_TURN, "conditions": [{"type": Catalog.CONDITION_KI_AT_LEAST, "amount": 1, "extra": true}], "actions": [{"type": Catalog.ACTION_SPEND_ALL_KI}]}]},
		{"triggers": [{"event": Catalog.CARD_AFTER_FLIPPED, "actions": [{"type": Catalog.ACTION_GAIN_KI, "amount": 0}]}]},
		{"triggers": [{"event": Catalog.CARD_AFTER_FLIPPED, "actions": [{"type": &"unknown"}]}]},
		{"triggers": [{"event": Catalog.CARD_AFTER_FLIPPED, "actions": [{"type": Catalog.ACTION_SPEND_ALL_KI, "extra": true}]}]},
		{"triggers": [{"event": Catalog.CARD_AFTER_FLIPPED, "actions": [{"type": Catalog.ACTION_GAIN_KI, "amount": 1, "on_invalid_context": &"unknown"}]}]},
	]
	for invalid_ability: Dictionary in invalid_abilities:
		_check(not Catalog.validate_ability(invalid_ability).is_empty(), "Malformed trigger ability fails validation: %s" % str(invalid_ability))
	var stop_rule_ability: Dictionary = {
		"triggers": [{
			"event": Catalog.CARD_AFTER_FLIPPED,
			"actions": [{
				"type": Catalog.ACTION_GAIN_KI,
				"amount": 1,
				"on_invalid_context": Catalog.STOP_RULE,
			}],
		}],
	}
	_check(Catalog.validate_ability(stop_rule_ability).is_empty(), "Explicit STOP_RULE policy passes validation")


func _test_welcoming_pine_schema() -> void:
	var definition: Dictionary = Catalog.get_definition(&"CangSongYingKe2")
	var abilities: Array = definition.get("abilities", [])
	_check(abilities.size() == 1, "Tier-two CangSong declares one ability")
	if abilities.is_empty():
		return
	var ability: Dictionary = abilities[0]
	_check(not ability.has("id"), "Welcoming Pine is identity-free")
	_check(not ability.has("retained_on_flip"), "Welcoming Pine relies on default non-retention")
	var triggers: Array = ability.get("triggers", [])
	_check(triggers.size() == 1, "Welcoming Pine declares one summon trigger")
	if triggers.is_empty():
		return
	var trigger: Dictionary = triggers[0]
	_check(StringName(trigger.get("event", &"")) == Catalog.TRIGGER_CARD_SUMMONED, "Welcoming Pine reacts to summoned cards")
	_check(
		trigger.get("conditions", []) == [
			{"type": Catalog.CONDITION_TRIGGER_CARD_IS_ENEMY},
			{"type": Catalog.CONDITION_TRIGGER_CARD_IN_RANGE},
		],
		"Welcoming Pine ANDs enemy and in-range conditions in order"
	)
	_check(
		trigger.get("actions", []) == [
			{"type": Catalog.ACTION_ATTACK_TRIGGER_CARD},
		],
		"Welcoming Pine attacks the triggering card"
	)
	_check(Catalog.validate_ability(ability, &"welcoming_pine_fixture").is_empty(), "Welcoming Pine schema passes validation")
	var instance: Dictionary = Catalog.create_instance(&"CangSongYingKe2", 1, &"welcoming_pine")
	var runtime_ability: Dictionary = (instance.get("active_abilities", []) as Array)[0]
	_check(runtime_ability.has("retained_on_flip") and not bool(runtime_ability["retained_on_flip"]), "Welcoming Pine normalizes to non-retained")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
