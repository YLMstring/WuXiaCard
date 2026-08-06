extends SceneTree

const Catalog = preload("res://scripts/card_catalog.gd")
const Abilities = preload("res://scripts/duel_abilities.gd")
const CardScene: PackedScene = preload("res://scenes/card_view.tscn")

const BEAD_NONE: StringName = &"none"
const BEAD_DARK: StringName = &"dark"
const BEAD_LIGHT: StringName = &"light"
const BEAD_GOLD: StringName = &"gold"
const LIGHT_BEAD_BACKGROUND: Color = Color("2f7664")
const GOLD_BEAD_BACKGROUND: Color = Color("9a6a20")
const DARK_BEAD_MODULATE: Color = Color(0.55, 0.62, 0.59, 0.72)
const PASSIVE_MARKER_FONT_SCALE: float = 0.8

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_presentation_priority_table()
	_test_own_summon_trigger_classification()
	_test_mixed_runtime_abilities()
	await _test_card_view_rendering()
	await _test_card_view_sizing()
	await _test_exact_value_centering()
	if _failures == 0:
		print("KI_BEAD_PRESENTATION_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"KI_BEAD_PRESENTATION_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _test_presentation_priority_table() -> void:
	var ki_threshold: Array = [
		{"type": Catalog.CONDITION_KI_AT_LEAST, "amount": 1},
	]
	_expect(_card(0), BEAD_NONE, false, 0, "Zero ki and no ability has no bead")
	_expect(_card(3), BEAD_DARK, true, 3, "Unrepresented positive ki uses dark bead")
	_expect(
		_card(0, [_activate_ability()]),
		BEAD_LIGHT,
		true,
		0,
		"Activate ability uses light bead and displays zero"
	)
	_expect(
		_card(0, [_trigger_ability(Catalog.TRIGGER_START_OWNER_TURN)]),
		BEAD_LIGHT,
		false,
		0,
		"Passive qualifying trigger uses unnumbered light bead at zero ki"
	)
	_expect(
		_card(2, [_trigger_ability(Catalog.TRIGGER_START_OWNER_TURN)]),
		BEAD_LIGHT,
		true,
		2,
		"Passive qualifying trigger displays positive ki"
	)
	var threshold_card: Dictionary = _card(
		0,
		[_trigger_ability(Catalog.TRIGGER_START_OWNER_TURN, ki_threshold)]
	)
	_expect(
		threshold_card,
		BEAD_LIGHT,
		true,
		0,
		"Ki-threshold trigger displays numeric zero"
	)
	_check(
		not Abilities.card_uses_ki(threshold_card),
		"Ki-threshold trigger does not broaden activate-only card_uses_ki"
	)
	_expect(
		_card(0, [Catalog.TEMPORARY_FLIP_PROTECTION]),
		BEAD_GOLD,
		false,
		0,
		"Temporary protection uses an unnumbered gold bead at zero ki"
	)
	_expect(
		_card(0, [Catalog.TEMPORARY_FLIP_PROTECTION, _activate_ability()]),
		BEAD_GOLD,
		true,
		0,
		"Gold takes priority while activation still makes zero visible"
	)
	_expect(
		_card(4, [Catalog.TEMPORARY_FLIP_PROTECTION]),
		BEAD_GOLD,
		true,
		4,
		"Protected card displays positive ki on its gold bead"
	)
	_expect(
		_card(0, [
			Catalog.TEMPORARY_FLIP_PROTECTION,
			_trigger_ability(Catalog.TRIGGER_START_OWNER_TURN, ki_threshold),
		]),
		BEAD_GOLD,
		true,
		0,
		"Ki-threshold trigger displays zero on a gold bead"
	)
	_expect(
		_card(0, [{"modifiers": [{"type": Catalog.MODIFIER_ATTACK_REQUIRES_OTHER_ALLY}]}]),
		BEAD_NONE,
		false,
		0,
		"Static modifier alone earns no bead"
	)


func _test_own_summon_trigger_classification() -> void:
	var self_condition: Array = [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}]
	var self_and_ki_conditions: Array = [
		{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF},
		{"type": Catalog.CONDITION_KI_AT_LEAST, "amount": 1},
	]
	_expect(
		_card(0, [_trigger_ability(Catalog.TRIGGER_CARD_SUMMONED, self_condition)]),
		BEAD_NONE,
		false,
		0,
		"Self card-summoned trigger is excluded"
	)
	_expect(
		_card(0, [_trigger_ability(Catalog.TRIGGER_CARD_AFTER_SUMMONED, self_condition)]),
		BEAD_NONE,
		false,
		0,
		"Self card-after-summoned trigger is excluded"
	)
	_expect(
		_card(0, [
			_trigger_ability(Catalog.TRIGGER_CARD_SUMMONED, self_and_ki_conditions),
		]),
		BEAD_NONE,
		false,
		0,
		"Ki threshold does not make an own-summon-only trigger show a bead"
	)
	_expect(
		_card(0, [_trigger_ability(Catalog.TRIGGER_CARD_SUMMONED)]),
		BEAD_LIGHT,
		false,
		0,
		"Summon trigger without self condition qualifies"
	)
	_expect(
		_card(0, [_trigger_ability(Catalog.TRIGGER_CARD_AFTER_SUMMONED)]),
		BEAD_LIGHT,
		false,
		0,
		"After-summon trigger without self condition qualifies"
	)
	_expect(
		_card(0, [_trigger_ability(Catalog.CARD_BEFORE_FLIPPED, self_condition)]),
		BEAD_LIGHT,
		false,
		0,
		"A non-summon self trigger still qualifies"
	)


func _test_mixed_runtime_abilities() -> void:
	var self_condition: Array = [{"type": Catalog.CONDITION_TRIGGER_CARD_IS_SELF}]
	var mixed_trigger_ability: Dictionary = {
		"triggers": [
			_trigger(Catalog.TRIGGER_CARD_SUMMONED, self_condition),
			_trigger(Catalog.TRIGGER_END_OWNER_TURN),
		],
	}
	_expect(
		_card(0, [mixed_trigger_ability]),
		BEAD_LIGHT,
		false,
		0,
		"One qualifying trigger among summon-only triggers earns light bead"
	)
	var card: Dictionary = _card(0, [Catalog.TEMPORARY_FLIP_PROTECTION])
	_expect(card, BEAD_GOLD, false, 0, "Runtime protection starts gold")
	card["active_abilities"] = []
	_expect(card, BEAD_NONE, false, 0, "Removing runtime protection removes gold bead")


func _test_card_view_rendering() -> void:
	var card_view: Control = CardScene.instantiate()
	root.add_child(card_view)
	card_view.size = Vector2(96.0, 128.0)
	card_view.call("configure", _card(0), 1, false)
	await process_frame
	var badge := card_view.get_node("Overlay/KiBadge") as PanelContainer
	var value := card_view.get_node("Overlay/KiBadge/Value") as Control
	_check(not badge.visible, "CardView hides bead for zero ki without a qualifying ability")

	card_view.call("sync_runtime_data", _card(3), 1)
	_check(
		badge.visible and value.visible and str(value.get("text")) == "3",
		"CardView shows positive otherwise-unrepresented ki"
	)
	_check(
		badge.modulate.is_equal_approx(DARK_BEAD_MODULATE),
		"Positive otherwise-unrepresented ki uses the current dark treatment"
	)

	card_view.call("sync_runtime_data", _card(0, [_activate_ability()]), 1)
	_check(
		badge.visible and value.visible and str(value.get("text")) == "0",
		"Activate ability keeps a visible zero"
	)
	_check(
		_style_background(badge).is_equal_approx(LIGHT_BEAD_BACKGROUND)
		and badge.modulate.is_equal_approx(Color.WHITE),
		"Activate ability uses the current full-light bead"
	)

	card_view.call(
		"sync_runtime_data",
		_card(0, [_trigger_ability(Catalog.TRIGGER_END_OWNER_TURN)]),
		1
	)
	_check(
		badge.visible and value.visible and str(value.get("text")) == "化",
		"Zero-ki passive trigger shows the current passive marker on its bead"
	)

	card_view.call(
		"sync_runtime_data",
		_card(0, [_trigger_ability(
			Catalog.TRIGGER_END_OWNER_TURN,
			[{"type": Catalog.CONDITION_KI_AT_LEAST, "amount": 1}]
		)]),
		1
	)
	_check(
		badge.visible and value.visible and str(value.get("text")) == "0",
		"Zero-ki threshold trigger renders numeric zero instead of the passive marker"
	)

	card_view.call(
		"sync_runtime_data",
		_card(0, [Catalog.TEMPORARY_FLIP_PROTECTION, _activate_ability()]),
		1
	)
	_check(
		badge.visible and value.visible and str(value.get("text")) == "0",
		"Protected activate card shows zero on its bead"
	)
	_check(
		_style_background(badge).is_equal_approx(GOLD_BEAD_BACKGROUND),
		"Temporary protection renders the gold bead"
	)

	card_view.call("sync_runtime_data", _card(0, [_activate_ability()]), 1)
	_check(
		_style_background(badge).is_equal_approx(LIGHT_BEAD_BACKGROUND),
		"Losing protection immediately restores the remaining light bead"
	)
	await card_view.call("play_ability_lost", 0.0)
	_check(
		(card_view.get("card_data").get("active_abilities", []) as Array).size() == 1
		and badge.visible,
		"Ability-loss presentation does not mutate already-synchronized card data"
	)

	card_view.call(
		"sync_runtime_data",
		_card(0, [Catalog.TEMPORARY_FLIP_PROTECTION]),
		1
	)
	_check(
		badge.visible and value.visible and str(value.get("text")) == "化",
		"Protected passive card shows the current passive marker on its gold bead"
	)
	await card_view.call("play_ki_gain_pulse", 0.01)
	_check(
		_style_background(badge).is_equal_approx(GOLD_BEAD_BACKGROUND)
		and badge.modulate.is_equal_approx(Color.WHITE),
		"Ki pulse returns a gold bead to its gold resting presentation"
	)

	card_view.call("set_face_down", true)
	_check(
		not badge.visible and not value.visible,
		"Face-down cards conceal the ability bead and its label"
	)
	card_view.call("set_face_down", false)
	card_view.call("set_ki_badge_enabled", false)
	_check(
		not badge.visible and not value.visible,
		"Explicit bead disabling remains authoritative"
	)
	card_view.queue_free()
	await process_frame


func _test_card_view_sizing() -> void:
	var card_view: Control = CardScene.instantiate()
	root.add_child(card_view)
	card_view.call("configure", _card(0, [_activate_ability()]), 1, false)
	var badge := card_view.get_node("Overlay/KiBadge") as PanelContainer
	var value := card_view.get_node("Overlay/KiBadge/Value") as Control
	var cases: Array[Dictionary] = [
		{"size": Vector2(54.0, 72.0), "diameter": 14.0, "margin": 2.0},
		{"size": Vector2(96.0, 128.0), "diameter": 19.2, "margin": 2.4},
		{"size": Vector2(130.0, 173.0), "diameter": 26.0, "margin": 3.25},
	]
	for test_case: Dictionary in cases:
		card_view.call("sync_runtime_data", _card(0, [_activate_ability()]), 1)
		card_view.size = test_case["size"] as Vector2
		await process_frame
		var expected_diameter: float = float(test_case["diameter"])
		var expected_margin: float = float(test_case["margin"])
		var expected_font_size: int = maxi(8, roundi(expected_diameter * 0.54))
		var expected_rim: int = maxi(1, roundi(expected_diameter * 0.077))
		var style := badge.get_theme_stylebox("panel") as StyleBoxFlat
		_check(
			is_equal_approx(badge.size.x, expected_diameter)
			and is_equal_approx(badge.size.y, expected_diameter),
			"Ki bead diameter follows the card's shorter side at %s"
			% [test_case["size"]]
		)
		_check(
			is_equal_approx(-badge.offset_right, expected_margin)
			and is_equal_approx(-badge.offset_bottom, expected_margin),
			"Ki bead keeps its responsive bottom-right margin at %s"
			% [test_case["size"]]
		)
		_check(
			int(value.get("font_size")) == expected_font_size
			and int(value.get("outline_size")) == expected_rim,
			"Ki bead text scales with its diameter at %s" % [test_case["size"]]
		)
		_check(
			style != null
			and style.get_border_width(SIDE_LEFT) == expected_rim
			and style.get_corner_radius(CORNER_TOP_LEFT) == roundi(expected_diameter * 0.5)
			and style.shadow_size == expected_rim,
			"Ki bead rim, radius, and shadow scale at %s" % [test_case["size"]]
		)
		_check(
			style != null
			and is_equal_approx(style.get_content_margin(SIDE_LEFT), float(expected_rim))
			and is_equal_approx(style.get_content_margin(SIDE_RIGHT), float(expected_rim))
			and is_equal_approx(
				style.get_content_margin(SIDE_TOP),
				style.get_content_margin(SIDE_BOTTOM)
			),
			"Ki bead keeps equal content margins with no manual text offset at %s"
			% [test_case["size"]]
		)
		_check(
			badge.pivot_offset.is_equal_approx(badge.size * 0.5),
			"Ki bead pivot follows its resized geometry at %s" % [test_case["size"]]
		)
		card_view.call(
			"sync_runtime_data",
			_card(0, [_trigger_ability(Catalog.TRIGGER_END_OWNER_TURN)]),
			1
		)
		await process_frame
		_check(
			str(value.get("text")) == "化"
			and int(value.get("font_size")) == roundi(
				float(expected_font_size) * PASSIVE_MARKER_FONT_SCALE
			),
			"Passive marker uses 80 percent of numeric font size at %s"
			% [test_case["size"]]
		)
	card_view.call("sync_runtime_data", _card(0, [_activate_ability()]), 1)
	await process_frame
	_check(
		value.visible
		and str(value.get("text")) == "0"
		and int(value.get("font_size")) == maxi(
			8,
			roundi(float(cases[-1]["diameter"]) * 0.54)
		),
		"Responsive layout does not alter numeric ki presentation"
	)
	card_view.queue_free()
	await process_frame


func _test_exact_value_centering() -> void:
	var card_view: Control = CardScene.instantiate()
	root.add_child(card_view)
	card_view.call("configure", _card(0, [_activate_ability()]), 1, false)
	var value := card_view.get_node("Overlay/KiBadge/Value") as Control
	var supports_exact_centering: bool = (
		value.has_method("set_value_text")
		and value.has_method("debug_get_centered_ink_bounds")
		and value.has_method("debug_get_centered_ink_centroid")
		and value.has_method("debug_get_glyph_count")
	)
	_check(
		supports_exact_centering,
		"Ki bead value uses the reusable exact visible-glyph renderer"
	)
	if supports_exact_centering:
		var sizes: Array[Vector2] = [
			Vector2(54.0, 72.0),
			Vector2(96.0, 128.0),
			Vector2(130.0, 173.0),
		]
		var values: Array[String] = ["0", "1", "10", "99", "化"]
		for card_size: Vector2 in sizes:
			card_view.size = card_size
			await process_frame
			for text_value: String in values:
				value.call("set_value_text", text_value)
				await process_frame
				var centered_bounds: Rect2 = value.call("debug_get_centered_ink_bounds") as Rect2
				var centered_centroid: Vector2 = value.call(
					"debug_get_centered_ink_centroid"
				) as Vector2
				_check(
					centered_bounds.has_area(),
					"Value %s has visible outline-inclusive glyph bounds at %s"
					% [text_value, card_size]
				)
				_check(
					centered_centroid.is_equal_approx(value.size * 0.5),
					"Value %s visible ink centroid is exactly centered at %s"
					% [text_value, card_size]
				)
				_check(
					int(value.call("debug_get_glyph_count")) > 0,
					"Value %s shapes to valid theme or fallback glyphs" % text_value
				)
		value.call("set_value_text", "")
		await process_frame
		var empty_bounds: Rect2 = value.call("debug_get_centered_ink_bounds") as Rect2
		_check(
			not empty_bounds.has_area()
			and int(value.call("debug_get_glyph_count")) == 0,
			"Empty bead text produces no glyph geometry"
		)
	card_view.queue_free()
	await process_frame


func _card(ki: int, abilities: Array = []) -> Dictionary:
	return {
		"ki": ki,
		"powers": [1, 1, 1, 1],
		"active_abilities": abilities.duplicate(true),
	}


func _style_background(badge: PanelContainer) -> Color:
	var style := badge.get_theme_stylebox("panel") as StyleBoxFlat
	return style.bg_color if style != null else Color.TRANSPARENT


func _activate_ability() -> Dictionary:
	return {
		"activation": {
			"input": Catalog.ACTIVATION_DRAG_TO_TARGET,
			"target": Catalog.TARGET_ADJACENT_EMPTY_BOARD,
			"actions": [{"type": Catalog.ACTION_MOVE_SELF_TO_TARGET}],
		},
	}


func _trigger_ability(event_type: StringName, conditions: Array = []) -> Dictionary:
	return {"triggers": [_trigger(event_type, conditions)]}


func _trigger(event_type: StringName, conditions: Array = []) -> Dictionary:
	return {
		"event": event_type,
		"conditions": conditions.duplicate(true),
		"actions": [],
	}


func _expect(
	card: Dictionary,
	expected_kind: StringName,
	expected_show_number: bool,
	expected_value: int,
	message: String
) -> void:
	var presentation: Dictionary = Abilities.get_ki_bead_presentation(card)
	_check(
		StringName(presentation.get("kind", &"")) == expected_kind
		and bool(presentation.get("show_number", false)) == expected_show_number
		and int(presentation.get("value", -1)) == expected_value,
		message
	)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
