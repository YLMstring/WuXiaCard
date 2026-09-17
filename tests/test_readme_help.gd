extends SceneTree

const HELP_SCENE: PackedScene = preload("res://scenes/readme_help.tscn")
const Markdown = preload("res://scripts/readme_markdown.gd")
const HelpController = preload("res://scripts/readme_help_controller.gd")
const Backdrop = preload("res://scripts/main_menu_backdrop.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var sample: String = """<a id="toc"></a>
# 标题

- **重点**与`代码`
- [章节](#chapter)
- [外部](https://example.com)

<a id="chapter"></a>
## 章节

```text
[示例]
```
"""
	var converted: Dictionary = Markdown.convert(sample)
	var bbcode: String = String(converted.get("bbcode", ""))
	var anchors: Dictionary = converted.get("anchors", {}) as Dictionary
	_check(bbcode.contains("[b]重点[/b]"), "Markdown converter preserves bold emphasis")
	_check(bbcode.contains("section:chapter"), "Markdown converter emits an internal section link")
	_check(not bbcode.contains("https://example.com"), "External targets are not made actionable")
	_check(bbcode.contains("[lb]示例[rb]"), "Code blocks escape BBCode delimiters")
	_check(anchors.has("toc") and anchors.has("chapter"), "HTML anchors become local scroll targets")

	var help := HELP_SCENE.instantiate() as HelpController
	help.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	help.size = Vector2(540.0, 960.0)
	root.add_child(help)
	await process_frame
	await process_frame
	var document := help.get_node("Parchment/Body/Margin/Layout/Document") as RichTextLabel
	var background_artwork := help.get_node("Artwork") as TextureRect
	var parchment := help.get_node("Parchment") as Control
	var body := help.get_node("Parchment/Body") as Control
	var parchment_art := help.get_node("Parchment/Artwork") as TextureRect
	var back_button := help.get_node("BackButton") as Button
	var reference_safe_rect: Rect2 = Backdrop.fit_safe_rect(help.size)
	_check(
		reference_safe_rect.encloses(Rect2(parchment.position, parchment.size)),
		"Reference short screen keeps the complete scroll inside the safe area"
	)
	_check(
		body.get_global_rect().encloses(back_button.get_global_rect()),
		"Back button sits inside the scroll cloth"
	)
	_check(
		help.get_node_or_null("Parchment/Body/Margin/Layout/PageTitle") == null
		and help.get_node_or_null("Parchment/Body/Margin/Layout/Divider") == null,
		"Help page does not repeat a title or divider above the README"
	)
	_check(document != null and document.bbcode_enabled, "Help page uses a BBCode-enabled rich document")
	_check(
		document.get_v_scroll_bar().modulate.a == 0.0,
		"Help page keeps scrolling available without displaying its scrollbar"
	)
	_check(
		help.debug_get_document_text().contains("三分钟看懂怎么玩")
		and help.debug_get_document_text().contains("技术细节"),
		"Help page loads the bundled README from beginning through technical details"
	)
	_check(help.debug_get_anchor_line("toc") >= 0, "README table-of-contents anchor is available")
	_check(help.debug_get_anchor_line("technical-details") > 0, "Late README anchors are available")
	document.meta_clicked.emit("section:technical-details")
	await process_frame
	await process_frame
	var scroll_bar := document.get_v_scroll_bar()
	var technical_paragraph: int = help.debug_get_anchor_line("technical-details")
	var expected_scroll: float = minf(
		document.get_paragraph_offset(technical_paragraph),
		scroll_bar.max_value - scroll_bar.page
	)
	_check(
		absf(scroll_bar.value - expected_scroll) <= 2.0,
		"A table-of-contents link scrolls down to the requested late README section"
	)
	_check(
		parchment_art.texture != null
		and parchment_art.texture.resource_path == "res://art/ui/card_inspector_scroll.png",
		"Help page uses the shared generated scroll artwork"
	)
	_check(back_button.size.x >= 42.0 and back_button.size.y >= 42.0, "Back control remains touch-sized")
	var reference_parchment_size: Vector2 = parchment.size
	help.size = Vector2(540.0, 800.0)
	await process_frame
	await process_frame
	var compact_viewport_rect := Rect2(Vector2.ZERO, help.size)
	_check(
		compact_viewport_rect.encloses(Rect2(parchment.position, parchment.size)),
		"Extra-short screen keeps both scroll rollers fully visible"
	)
	_check(
		is_equal_approx(parchment.size.x, reference_parchment_size.x),
		"Extra-short screen preserves the scroll width instead of faking height with side pillars"
	)
	_check(
		parchment.size.y < reference_parchment_size.y - 80.0,
		"Extra-short screen genuinely reduces the scroll height"
	)
	_check(
		background_artwork.position.is_equal_approx(Vector2.ZERO)
		and background_artwork.size.is_equal_approx(help.size),
		"Extra-short screen covers the full viewport and crops the background vertically"
	)
	_check(
		body.get_global_rect().encloses(back_button.get_global_rect()),
		"Extra-short screen keeps the back button inside the scroll cloth"
	)
	var back_count := {"value": 0}
	help.back_requested.connect(
		func() -> void: back_count["value"] = int(back_count["value"]) + 1
	)
	back_button.pressed.emit()
	_check(int(back_count["value"]) == 1, "Back control requests a return exactly once")

	var export_text: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	_check(
		export_text.count("include_filter=\"README.md\"") == 2,
		"Both Android and Windows exports explicitly include README.md"
	)

	help.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if _failures == 0:
		print("README_HELP_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("README_HELP_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
