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
	var description: VBoxContainer = content.get_node("Description") as VBoxContainer
	var flavor: Label = content.get_node("Flavor") as Label
	var scroll: ScrollContainer = inspector.get_node("Parchment/Body/Margin/Scroll") as ScrollContainer
	var description_labels: Array[Label] = _description_labels(description)

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
	_check(
		description_labels.size() == 1
		and description_labels[0].text == "对手招式进场时，若我可以，对其发起攻击。",
		"Description is displayed as complete plain-label rules text"
	)
	_check(
		description.get_theme_constant("separation") == 7,
		"Description paragraphs retain the approved half-line spacing"
	)
	_check(
		description_labels[0].get_theme_color("font_color").is_equal_approx(
			Color(0.2, 0.15, 0.1, 1)
		)
		and description_labels[0].get_theme_font_size("font_size") == 14,
		"Description paragraphs restore the original Label color and responsive size"
	)
	_check(
		String(inspector.call("get_card_snapshot").get("description", ""))
		== "对手招式进场时，若我可以，对其发起攻击。",
		"Inspector snapshots retain the unformatted catalog description"
	)
	_check(flavor.text == "华山剑法的绝招。", "Flavor text is displayed separately")
	_check(description_labels[0].language == "zh" and flavor.language == "zh", "Wrapped inspector text explicitly uses Chinese line-breaking rules")
	_check(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Inspector never scrolls horizontally")
	_check(scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER, "Inspector scrollbar stays hidden while long text remains scrollable")

	inspector.call("present", {
		"description": "进场后，抽一张牌。锁定：回合结束时，将我移除。",
	}, board_rect)
	await process_frame
	description_labels = _description_labels(description)
	_check(
		description_labels.size() == 2
		and description_labels[0].text == "进场后，抽一张牌。"
		and description_labels[1].text == "锁定：回合结束时，将我移除。",
		"Inspector renders top-level sentences as separate ordinary labels"
	)
	var nested_description: String = "进场后，获得以下效果：【回合开始时，抽一张牌。翻面前，将我移除。】然后发起攻击。"
	inspector.call("present", {"description": nested_description}, board_rect)
	await process_frame
	description_labels = _description_labels(description)
	_check(
		description_labels.size() == 1
		and description_labels[0].text == nested_description,
		"Repeated inspection removes stale paragraphs and keeps bracket contents unbroken"
	)

	inspector.call("present", {
		"glyph": "",
		"sect": "",
		"tier": null,
		"weapon": "",
		"description": "",
		"flavor": "",
	}, board_rect)
	await process_frame
	description_labels = _description_labels(description)
	_check(
		title.text == "—"
		and sect_value.text == "—"
		and tier_value.text == "—"
		and weapon_value.text == "—"
		and description_labels.size() == 1
		and description_labels[0].text == "—"
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
	var single_paragraphs: Array[String] = EffectFormatter.split_paragraphs(single)
	_check(single_paragraphs == [single], "Single effect produces one complete paragraph")

	var multiple: String = "进场后，抽一张牌。锁定：回合结束时，将我移除。"
	var multiple_paragraphs: Array[String] = EffectFormatter.split_paragraphs(multiple)
	_check(
		multiple_paragraphs == ["进场后，抽一张牌。", "锁定：回合结束时，将我移除。"],
		"Top-level full stops split independent plain-text paragraphs"
	)

	var combined_prefix: String = "锁定，指定：移动至一个相邻空格，然后发起攻击。"
	_check(
		EffectFormatter.split_paragraphs(combined_prefix) == [combined_prefix],
		"Rule prefixes remain ordinary unmodified text"
	)

	var nested: String = "进场后，获得以下效果：【回合开始时，抽一张牌。翻面前，将我移除。】然后发起攻击。"
	_check(
		EffectFormatter.split_paragraphs(nested) == [nested],
		"Granted-effect brackets remain one unindented paragraph"
	)

	var parenthetical: String = "回合开始时，失去此效果。（无论我在哪里）攻击后，抽一张牌。"
	_check(
		EffectFormatter.split_paragraphs(parenthetical)
		== ["回合开始时，失去此效果。", "（无论我在哪里）攻击后，抽一张牌。"],
		"A top-level full stop before a parenthetical starts the next paragraph"
	)

	var quoted: String = "进场后，获得“抽一张牌。然后攻击。”。回合结束时，将我移除。"
	_check(
		EffectFormatter.split_paragraphs(quoted)
		== ["进场后，获得“抽一张牌。然后攻击。”。", "回合结束时，将我移除。"],
		"Full stops inside quotes do not create paragraphs"
	)

	var manual_break: String = "进场后，抽一张牌。\n回合结束时，将我移除。"
	_check(
		EffectFormatter.split_paragraphs(manual_break)
		== ["进场后，抽一张牌。", "回合结束时，将我移除。"],
		"Manual line breaks define paragraphs without empty duplicates"
	)

	var literal_brackets: String = "进场后，[测试]抽一张牌。"
	_check(
		EffectFormatter.split_paragraphs(literal_brackets) == [literal_brackets],
		"Literal square brackets remain unchanged plain text"
	)

	for malformed: String in [
		"进场后，获得以下效果：【抽一张牌。",
		"进场后，获得以下效果：】抽一张牌。",
		"进场后，获得“抽一张牌。",
	]:
		_check(
			EffectFormatter.split_paragraphs(malformed) == [malformed],
			"Malformed nesting falls back to one complete original paragraph"
		)


func _description_labels(container: VBoxContainer) -> Array[Label]:
	var labels: Array[Label] = []
	for child: Node in container.get_children():
		if child is Label:
			labels.append(child as Label)
	return labels


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
