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
	var title_glow := title.get_node("TitleGlow") as TextureRect
	var title_glow_material := title_glow.material as ShaderMaterial
	var initial_title_scale: float = title.scale.x
	var initial_title_color: Color = title.self_modulate
	var initial_glow_parameter: Variant = title_glow_material.get_shader_parameter(&"glow_color")
	var initial_glow_color: Color = (
		initial_glow_parameter if initial_glow_parameter is Color else Color.TRANSPARENT
	)
	var initial_glow_strength: float = float(
		title_glow_material.get_shader_parameter(&"pulse_strength")
	)
	await create_timer(0.65).timeout
	var animated_glow_parameter: Variant = title_glow_material.get_shader_parameter(&"glow_color")
	var animated_glow_color: Color = (
		animated_glow_parameter if animated_glow_parameter is Color else Color.TRANSPARENT
	)
	var animated_glow_strength: float = float(
		title_glow_material.get_shader_parameter(&"pulse_strength")
	)
	_check(
		absf(title.scale.x - initial_title_scale) < 0.001,
		"Title glow breathing keeps the title scale stable"
	)
	_check(
		animated_glow_strength > initial_glow_strength + 0.04,
		"Title breathing visibly changes the halo strength"
	)
	_check(
		_color_difference(initial_title_color, title.self_modulate) < 0.01,
		"Title breathing keeps the ink color stable"
	)
	_check(
		_color_difference(initial_glow_color, animated_glow_color) < 0.01,
		"Title breathing keeps one stable halo color"
	)
	_check(_has_glyph_texture(journey_button), "Journey action uses its ink image")
	_check(_has_glyph_texture(run_reset_button), "Run reset uses its ink image")
	_check(_has_glyph_texture(progress_reset_button), "Progress reset uses its ink image")

	var signal_counts := {
		"journey": 0,
		"run_reset": 0,
		"progress_reset": 0,
		"progression_unlock": 0,
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
	menu.progression_unlock_requested.connect(
		func() -> void:
			signal_counts["progression_unlock"] = int(signal_counts["progression_unlock"]) + 1
	)

	progress_reset_button.pressed.emit()
	_check(menu.debug_get_progression_unlock_step() == 0, "Unlock gesture cannot start from full reset")
	journey_button.pressed.emit()
	run_reset_button.pressed.emit()
	progress_reset_button.pressed.emit()
	progress_reset_button.pressed.emit()
	_check(menu.debug_get_progression_unlock_step() == 0, "Wrong alternation clears the unlock gesture")
	journey_button.pressed.emit()
	run_reset_button.pressed.emit()
	progress_reset_button.pressed.emit()
	journey_button.pressed.emit()
	_check(menu.debug_get_progression_unlock_step() == 0, "Journey clears the unlock gesture")
	var journey_count_before_unlock: int = int(signal_counts["journey"])
	for pair_index: int in range(5):
		run_reset_button.pressed.emit()
		progress_reset_button.pressed.emit()
	_check(int(signal_counts["progression_unlock"]) == 1, "Five alternating pairs request full progression unlock")
	_check(int(signal_counts["run_reset"]) == 0, "Unlock gesture does not confirm run reset")
	_check(int(signal_counts["progress_reset"]) == 0, "Unlock gesture does not confirm full reset")
	_check(menu.debug_get_progression_unlock_step() == 0, "Completed unlock gesture clears its step")
	_check(menu.debug_get_confirmation_counts() == Vector2i.ZERO, "Completed unlock gesture clears destructive countdowns")
	_check(int(signal_counts["journey"]) == journey_count_before_unlock, "Unlock gesture does not request navigation")

	run_reset_button.pressed.emit()
	_check(notice.text == "再按四次\n放弃本局", "Run-reset countdown starts at four in two lines")
	for press_index: int in range(3):
		run_reset_button.pressed.emit()
	_check(int(signal_counts["run_reset"]) == 0, "Four run-reset presses do not confirm")
	_check(notice.text == "再按一次\n放弃本局", "Run-reset countdown reaches one")
	run_reset_button.pressed.emit()
	_check(int(signal_counts["run_reset"]) == 1, "The fifth run-reset press confirms")
	_check(menu.debug_get_confirmation_counts() == Vector2i.ZERO, "Confirmation clears run counter")

	progress_reset_button.pressed.emit()
	_check(notice.text == "再按九次\n删档重来", "Progress-reset countdown starts at nine in two lines")
	for press_index: int in range(8):
		progress_reset_button.pressed.emit()
	_check(int(signal_counts["progress_reset"]) == 0, "Nine progress-reset presses do not confirm")
	_check(notice.text == "再按一次\n删档重来", "Progress-reset countdown reaches one")
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
	_check(int(signal_counts["journey"]) == journey_count_before_unlock + 1, "Journey action emits once")
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
			clampf(normal_safe.size.x * 0.46, 210.0, 330.0) * 1.50
		),
		"Title image uses the 150 percent responsive width"
	)
	_check(
		notice.get_rect().end.y < normal_safe.position.y + normal_safe.size.y * 0.6,
		"Normal-phone layout places the notice directly above the illustrated grid"
	)
	_check(notice.size.y >= 52.0, "Notice has enough height for two text lines")
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


func _color_difference(a: Color, b: Color) -> float:
	return (
		absf(a.r - b.r)
		+ absf(a.g - b.g)
		+ absf(a.b - b.b)
		+ absf(a.a - b.a)
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
