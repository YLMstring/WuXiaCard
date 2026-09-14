extends SceneTree

const INSPECTOR_SCENE_PATH: String = "res://scenes/card_inspector.tscn"
const CARD_SCENE: PackedScene = preload("res://scenes/card_view.tscn")
const EffectFormatter = preload("res://scripts/card_effect_text_formatter.gd")

var _checks: int = 0
var _failures: int = 0
var _close_count: int = 0
var _inspection_requests: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_effect_formatter()
	if not ResourceLoader.exists(INSPECTOR_SCENE_PATH):
		_check(false, "Reusable card inspector scene exists")
		_finish()
		return

	var packed_scene: PackedScene = load(INSPECTOR_SCENE_PATH) as PackedScene
	var inspector: Control = packed_scene.instantiate() as Control
	root.add_child(inspector)
	await process_frame
	inspector.connect("inspection_closed", _on_inspection_closed)

	var board_rect := Rect2(60.0, 220.0, 300.0, 390.0)
	inspector.call("present", {
		"glyph": "苍松迎客",
		"sect": "华山派",
		"tier": 2,
		"weapon": "剑法",
		"description": "对手招式进场时，若我可以，对其发起攻击。",
		"flavor": "华山剑法的绝招。",
	}, board_rect)
	await process_frame

	var parchment: Control = inspector.get_node("Parchment") as Control
	var parchment_shadow: Control = inspector.get_node("Parchment/Shadow") as Control
	var parchment_body: Control = inspector.get_node("Parchment/Body") as Control
	var content: VBoxContainer = inspector.get_node("Parchment/Body/Margin/Scroll/Content") as VBoxContainer
	var title: Label = content.get_node("Title") as Label
	var tags: HBoxContainer = content.get_node("Tags") as HBoxContainer
	var sect_value: Label = tags.get_node("SectTag/Value") as Label
	var tier_value: Label = tags.get_node("TierTag/Value") as Label
	var weapon_value: Label = tags.get_node("WeaponTag/Value") as Label
	var description: RichTextLabel = content.get_node("Description") as RichTextLabel
	var flavor: Label = content.get_node("Flavor") as Label
	var scroll: ScrollContainer = inspector.get_node("Parchment/Body/Margin/Scroll") as ScrollContainer

	_check(
		bool(ProjectSettings.get_setting("internationalization/locale/include_text_server_data", false)),
		"Exports include ICU text-server data for proper Chinese line breaking"
	)
	_check(bool(inspector.call("is_open")), "Present opens the inspector")
	_check(parchment.position.is_equal_approx(board_rect.position) and parchment.size.is_equal_approx(board_rect.size), "Parchment exactly occupies the supplied board rectangle")
	_check(not parchment_shadow.visible and parchment_body.visible, "Inspector parchment hides its shadow without hiding the scroll body")
	_check(title.text == "苍松迎客", "Glyph is displayed as the card name")
	_check(sect_value.text == "华山派" and tier_value.text == "不凡" and weapon_value.text == "剑法", "Sect, tier, and weapon values are populated")
	_check(
		tags.get_node("SectTag").get_index()
		< tags.get_node("TierTag").get_index()
		and tags.get_node("TierTag").get_index() < tags.get_node("WeaponTag").get_index(),
		"Metadata tags remain ordered sect, tier, weapon"
	)
	_check(_parsed_effect_text(description.text) == "对手招式进场时，若我可以，对其发起攻击。", "Description is displayed as complete rules text")
	_check(
		description.bbcode_enabled
		and description.fit_content
		and not description.scroll_active,
		"Description uses auto-height rich text without a nested scrollbar"
	)
	_check(
		String(inspector.call("get_card_snapshot").get("description", ""))
		== "对手招式进场时，若我可以，对其发起攻击。",
		"Inspector snapshots retain the unformatted catalog description"
	)
	_check(flavor.text == "华山剑法的绝招。", "Flavor text is displayed separately")
	_check(description.language == "zh" and flavor.language == "zh", "Wrapped inspector text explicitly uses Chinese line-breaking rules")
	_check(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Inspector never scrolls horizontally")
	_check(scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER, "Inspector scrollbar stays hidden while long text remains scrollable")

	inspector.call("present", {
		"glyph": "",
		"sect": "",
		"tier": null,
		"weapon": "",
		"description": "",
		"flavor": "",
	}, board_rect)
	await process_frame
	_check(
		title.text == "—"
		and sect_value.text == "—"
		and tier_value.text == "—"
		and weapon_value.text == "—"
		and description.get_parsed_text() == "—"
		and flavor.text == "—",
		"Every missing displayed value uses the placeholder"
	)

	_submit_mouse_gesture(inspector, Vector2(8.0, 8.0), Vector2(8.0, 8.0))
	_check(_close_count == 1 and not bool(inspector.call("is_open")), "A stationary tap closes inspection exactly once")
	inspector.call("present", {"glyph": "苍松迎客", "tier": 1}, board_rect)
	_submit_mouse_gesture(inspector, Vector2(8.0, 8.0), Vector2(40.0, 8.0))
	_check(_close_count == 1 and bool(inspector.call("is_open")), "A scroll-sized gesture does not close inspection")
	inspector.call("close")
	inspector.call("close")
	_check(_close_count == 2 and not bool(inspector.call("is_open")), "Repeated close requests are idempotent")

	inspector.queue_free()
	await process_frame
	await _check_card_view_gestures()
	_finish()


func _check_effect_formatter() -> void:
	var single: String = "进场后，抽一张牌。"
	var single_bbcode: String = EffectFormatter.format_bbcode(single)
	_check(_parsed_effect_text(single_bbcode) == single, "Single effect preserves every visible character")
	_check(single_bbcode.count("[p]") == 1, "Single effect produces one outer paragraph")

	var multiple: String = "进场后，抽一张牌。锁定：回合结束时，将我移除。"
	var multiple_bbcode: String = EffectFormatter.format_bbcode(multiple)
	_check(_parsed_effect_text(multiple_bbcode) == multiple, "Multiple effects preserve their original text")
	_check(multiple_bbcode.count("[p]") == 2, "Top-level full stops split independent effect paragraphs")
	_check(multiple_bbcode.contains("[b]锁定：[/b]"), "A locked prefix receives emphasis")

	var combined_prefix: String = "锁定，指定：移动至一个相邻空格，然后发起攻击。"
	var combined_bbcode: String = EffectFormatter.format_bbcode(combined_prefix)
	_check(_parsed_effect_text(combined_bbcode) == combined_prefix, "Combined-prefix formatting preserves its source text")
	_check(combined_bbcode.contains("[b]锁定，指定：[/b]"), "The complete locked-targeted prefix is emphasized together")

	var nested: String = "进场后，获得以下效果：【回合开始时，抽一张牌。翻面前，将我移除。】然后发起攻击。"
	var nested_bbcode: String = EffectFormatter.format_bbcode(nested)
	_check(_parsed_effect_text(nested_bbcode) == nested, "Nested granted effects preserve their original text")
	_check(nested_bbcode.count("[p]") == 1, "Nested full stops do not split the containing outer effect")
	_check(nested_bbcode.contains("[indent]"), "Granted-effect brackets receive one visual indentation level")
	_check(nested_bbcode.contains("[b]回合开始时，[/b]"), "Nested effect timing receives the same prefix emphasis")

	var parenthetical: String = "回合开始时，失去此效果。（无论我在哪里）攻击后，抽一张牌。"
	var parenthetical_bbcode: String = EffectFormatter.format_bbcode(parenthetical)
	_check(_parsed_effect_text(parenthetical_bbcode) == parenthetical, "Trailing parenthetical notes preserve their original text")
	_check(parenthetical_bbcode.count("[p]") == 2, "A trailing parenthetical note stays attached to its preceding paragraph")

	var quoted: String = "进场后，获得“抽一张牌。然后攻击。”。回合结束时，将我移除。"
	var quoted_bbcode: String = EffectFormatter.format_bbcode(quoted)
	_check(_parsed_effect_text(quoted_bbcode) == quoted, "Quoted effects preserve every original character")
	_check(quoted_bbcode.count("[p]") == 2, "Full stops inside quotes do not create outer paragraphs")

	var manual_break: String = "进场后，抽一张牌。\n回合结束时，将我移除。"
	var manual_bbcode: String = EffectFormatter.format_bbcode(manual_break)
	_check(_parsed_effect_text(manual_bbcode) == manual_break, "Manual line breaks remain visible and unchanged")
	_check(manual_bbcode.count("[p]") == 2, "Manual line breaks define explicit effect paragraphs")

	var literal_brackets: String = "进场后，[测试]抽一张牌。"
	var bracket_bbcode: String = EffectFormatter.format_bbcode(literal_brackets)
	_check(_parsed_effect_text(bracket_bbcode) == literal_brackets, "Literal square brackets cannot inject rich-text markup")

	for malformed: String in [
		"进场后，获得以下效果：【抽一张牌。",
		"进场后，获得以下效果：】抽一张牌。",
		"进场后，获得“抽一张牌。",
	]:
		var malformed_bbcode: String = EffectFormatter.format_bbcode(malformed)
		_check(_parsed_effect_text(malformed_bbcode) == malformed, "Malformed nesting falls back without losing text")
		_check(not malformed_bbcode.contains("[indent]"), "Malformed nesting does not receive partial structural formatting")


func _parsed_effect_text(bbcode: String) -> String:
	var rich_text := RichTextLabel.new()
	rich_text.bbcode_enabled = true
	rich_text.text = bbcode
	var parsed: String = rich_text.get_parsed_text().replace("\r", "").replace("\t", "")
	rich_text.free()
	return parsed


func _submit_mouse_gesture(inspector: Control, start: Vector2, finish: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	inspector.call("_input", press)
	if not start.is_equal_approx(finish):
		var motion := InputEventMouseMotion.new()
		motion.position = finish
		inspector.call("_input", motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = finish
	inspector.call("_input", release)


func _on_inspection_closed() -> void:
	_close_count += 1


func _check_card_view_gestures() -> void:
	var card: Control = CARD_SCENE.instantiate() as Control
	root.add_child(card)
	card.size = Vector2(96.0, 128.0)
	card.call("configure", {
		"glyph": "苍松迎客",
		"sect": "华山派",
		"tier": 2,
		"weapon": "剑法",
		"description": "规则",
		"flavor": "风味",
		"powers": [4, 7, 7, 4],
		"ki": 0,
		"active_abilities": [],
	}, 1, true)
	await process_frame
	var supports_inspection: bool = card.has_signal("inspection_requested")
	_check(supports_inspection, "CardView exposes a dedicated inspection request signal")
	if not supports_inspection:
		card.queue_free()
		await process_frame
		return
	card.connect("inspection_requested", _on_card_inspection_requested)

	_submit_card_mouse_gesture(card, Vector2(48.0, 64.0), Vector2(48.0, 64.0))
	_check(_inspection_requests == 1 and not bool(card.call("is_being_dragged")), "A stationary revealed-card tap requests inspection without dragging")
	card.call("set_playable", false)
	_submit_card_mouse_gesture(card, Vector2(48.0, 64.0), Vector2(48.0, 64.0))
	_check(_inspection_requests == 2, "A revealed non-playable card can still be inspected")
	card.call("set_face_down", true)
	_check(
		(card.get_node("Overlay/TopPower") as Label).visible
		and (card.get_node("Overlay/RightPower") as Label).visible
		and (card.get_node("Overlay/BottomPower") as Label).visible
		and (card.get_node("Overlay/LeftPower") as Label).visible,
		"A face-down card shows its numbered powers by default"
	)
	_submit_card_mouse_gesture(card, Vector2(48.0, 64.0), Vector2(48.0, 64.0))
	_check(_inspection_requests == 2, "A face-down card never requests inspection")
	card.call("set_concealed_power_numbers_enabled", false)
	_check(
		not (card.get_node("Overlay/TopPower") as Label).visible
		and not (card.get_node("Overlay/RightPower") as Label).visible
		and not (card.get_node("Overlay/BottomPower") as Label).visible
		and not (card.get_node("Overlay/LeftPower") as Label).visible,
		"Concealed-power suppression hides every face-down power label"
	)

	card.call("set_face_down", false)
	card.call("set_playable", true)
	_submit_card_mouse_press(card, Vector2(48.0, 64.0))
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(76.0, 64.0)
	motion.global_position = motion.position
	card.call("_input", motion)
	_check(bool(card.call("is_being_dragged")) and _inspection_requests == 2, "Movement beyond the threshold begins drag instead of inspection")
	card.call("finish_drag_state")
	card.queue_free()
	await process_frame


func _submit_card_mouse_gesture(card: Control, start: Vector2, finish: Vector2) -> void:
	_submit_card_mouse_press(card, start)
	if not start.is_equal_approx(finish):
		var motion := InputEventMouseMotion.new()
		motion.position = finish
		motion.global_position = finish
		card.call("_input", motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = finish
	release.global_position = finish
	card.call("_gui_input", release)


func _submit_card_mouse_press(card: Control, position: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = position
	press.global_position = position
	card.call("_gui_input", press)


func _on_card_inspection_requested(_card_data: Dictionary) -> void:
	_inspection_requests += 1


func _finish() -> void:
	if _failures == 0:
		print("CARD_INSPECTOR_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("CARD_INSPECTOR_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
