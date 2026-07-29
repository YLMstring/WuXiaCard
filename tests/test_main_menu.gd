extends SceneTree

const MENU_SCENE: PackedScene = preload("res://scenes/main_menu.tscn")
const MenuController = preload("res://scripts/main_menu_controller.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu := MENU_SCENE.instantiate() as MenuController
	root.add_child(menu)
	await process_frame
	_check(menu != null, "Main menu scene instantiates")
	var journey_button := menu.get_node("MenuLayer/Actions/JourneyButton") as Button
	var run_reset_button := menu.get_node("MenuLayer/Actions/RunResetButton") as Button
	var progress_reset_button := menu.get_node("MenuLayer/Actions/ProgressResetButton") as Button
	var notice := menu.get_node("MenuLayer/Notice") as Label
	var artwork := menu.get_node("Artwork") as TextureRect
	var title := menu.get_node("MenuLayer/Title") as Label
	_check(title.text.is_empty(), "Title text is replaced")
	_check(journey_button.text.is_empty(), "Journey text is replaced")
	_check(run_reset_button.text.is_empty(), "Run-reset text is replaced")
	_check(progress_reset_button.text.is_empty(), "Progress-reset text is replaced")
	_check(notice.text.is_empty(), "Notice starts empty")
	_check(artwork.texture != null, "Main-menu artwork texture is always assigned")
	_check(
		artwork.texture.get_width() == 1080 and artwork.texture.get_height() == 2400,
		"Main-menu artwork uses the exact 1080 by 2400 phone master"
	)
	_check(
		artwork.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED,
		"Phone artwork center-crops without distortion"
	)
	_check(_has_glyph_texture(title), "Title uses its ink image")
	_check(_has_title_glow(title), "Title has a non-interactive shader glow behind its ink")
	_check(_has_glyph_texture(journey_button), "Journey action uses its ink image")
	_check(_has_glyph_texture(run_reset_button), "Run reset uses its ink image")
	_check(_has_glyph_texture(progress_reset_button), "Progress reset uses its ink image")

	var signal_counts := {
		"journey": 0,
		"run_reset": 0,
		"progress_reset": 0,
	}
	menu.journey_requested.connect(
		func() -> void: signal_counts["journey"] = int(signal_counts["journey"]) + 1
	)
	menu.run_reset_confirmed.connect(
		func() -> void: signal_counts["run_reset"] = int(signal_counts["run_reset"]) + 1
	)
	menu.progress_reset_confirmed.connect(
		func() -> void:
			signal_counts["progress_reset"] = int(signal_counts["progress_reset"]) + 1
	)

	for press_index: int in range(4):
		run_reset_button.pressed.emit()
	_check(int(signal_counts["run_reset"]) == 0, "Four run-reset presses do not confirm")
	_check(notice.text == "再按 1 次重置本局进度", "Run-reset countdown reaches one")
	run_reset_button.pressed.emit()
	_check(int(signal_counts["run_reset"]) == 1, "The fifth run-reset press confirms")
	_check(menu.debug_get_confirmation_counts() == Vector2i.ZERO, "Confirmation clears run counter")

	for press_index: int in range(9):
		progress_reset_button.pressed.emit()
	_check(int(signal_counts["progress_reset"]) == 0, "Nine progress-reset presses do not confirm")
	_check(notice.text == "再按 1 次重置所有进度", "Progress-reset countdown reaches one")
	progress_reset_button.pressed.emit()
	_check(int(signal_counts["progress_reset"]) == 1, "The tenth progress-reset press confirms")

	run_reset_button.pressed.emit()
	_check(menu.debug_get_confirmation_counts() == Vector2i(1, 0), "Run countdown starts")
	progress_reset_button.pressed.emit()
	_check(
		menu.debug_get_confirmation_counts() == Vector2i(0, 1),
		"A different destructive action cancels the first countdown"
	)
	journey_button.pressed.emit()
	_check(int(signal_counts["journey"]) == 1, "Journey action emits once")
	_check(menu.debug_get_confirmation_counts() == Vector2i.ZERO, "Journey cancels both countdowns")
	_check(notice.text.is_empty(), "Journey clears countdown notice")

	menu.debug_set_confirmation_timeout(0.03)
	run_reset_button.pressed.emit()
	await create_timer(0.06).timeout
	_check(menu.debug_get_confirmation_counts() == Vector2i.ZERO, "Run countdown expires")
	_check(notice.text.is_empty(), "Expired countdown clears its notice")
	progress_reset_button.pressed.emit()
	await create_timer(0.06).timeout
	_check(menu.debug_get_confirmation_counts() == Vector2i.ZERO, "Progress countdown expires")

	menu.size = Vector2(540.0, 960.0)
	await process_frame
	var normal_artwork: Rect2 = menu.debug_get_artwork_rect()
	var normal_safe := Rect2(0.0, 0.0, 540.0, 960.0)
	_check(normal_artwork == Rect2(0.0, 0.0, 540.0, 960.0), "Normal phone fills the screen")
	_check(normal_artwork == normal_safe, "Normal phone uses the full 9:16 UI-safe region")
	_check(
		is_equal_approx(
			title.size.x,
			clampf(normal_safe.size.x * 0.46, 210.0, 330.0) * 1.35
		),
		"Title image uses the 135 percent responsive width"
	)
	_check(
		notice.get_rect().end.y < normal_safe.position.y + normal_safe.size.y * 0.6,
		"Normal-phone layout places the notice directly above the illustrated grid"
	)
	menu.size = Vector2(540.0, 1200.0)
	await process_frame
	var long_artwork: Rect2 = menu.debug_get_artwork_rect()
	var long_safe := Rect2(0.0, 120.0, 540.0, 960.0)
	_check(long_artwork == Rect2(0.0, 0.0, 540.0, 1200.0), "Long phone reveals the complete 9:20 artwork")
	_check(
		is_equal_approx(title.get_global_rect().get_center().x, long_safe.get_center().x),
		"Long-phone title remains centered in the safe region"
	)
	menu.size = Vector2(1280.0, 720.0)
	await process_frame
	var wide_artwork: Rect2 = menu.debug_get_artwork_rect()
	var wide_safe := Rect2(437.5, 0.0, 405.0, 720.0)
	_check(wide_artwork == Rect2(437.5, 0.0, 405.0, 720.0), "Wide layout centers a 9:16 artwork crop")
	_check(wide_artwork == wide_safe, "Wide layout anchors UI to the centered portrait canvas")
	_check(
		notice.get_rect().end.y < wide_safe.position.y + wide_safe.size.y * 0.6,
		"Wide layout keeps the notice directly above the illustrated grid"
	)
	var buttons: Array[Button] = [journey_button, run_reset_button, progress_reset_button]
	for button: Button in buttons:
		_check(button.size.y >= 54.0, "%s remains touch-sized" % button.name)
	_check(
		not journey_button.get_global_rect().intersects(run_reset_button.get_global_rect())
		and not run_reset_button.get_global_rect().intersects(progress_reset_button.get_global_rect()),
		"Action hit areas do not overlap"
	)

	menu.queue_free()
	await process_frame
	_finish()


func _has_glyph_texture(parent: Node) -> bool:
	var glyph := parent.get_node_or_null("InkGlyph") as TextureRect
	return glyph != null and glyph.texture != null and glyph.mouse_filter == Control.MOUSE_FILTER_IGNORE


func _has_title_glow(parent: Node) -> bool:
	var glow := parent.get_node_or_null("TitleGlow") as TextureRect
	var glyph := parent.get_node_or_null("InkGlyph") as TextureRect
	return (
		glow != null
		and glyph != null
		and glow.texture != null
		and glow.material is ShaderMaterial
		and glow.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and glow.get_index() < glyph.get_index()
	)


func _finish() -> void:
	if _failures == 0:
		print("MAIN_MENU_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("MAIN_MENU_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
