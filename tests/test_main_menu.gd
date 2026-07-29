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
	_check((menu.get_node("MenuLayer/Title") as Label).text.is_empty(), "Title text is replaced")
	_check(journey_button.text.is_empty(), "Journey text is replaced")
	_check(run_reset_button.text.is_empty(), "Run-reset text is replaced")
	_check(progress_reset_button.text.is_empty(), "Progress-reset text is replaced")
	_check(notice.text.is_empty(), "Notice starts empty")
	_check(artwork.texture != null, "Main-menu artwork texture is always assigned")
	_check(_has_glyph_texture(menu.get_node("MenuLayer/Title")), "Title uses its ink image")
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
	var tall_artwork: Rect2 = menu.debug_get_artwork_rect()
	_check(tall_artwork == Rect2(0.0, 210.0, 540.0, 540.0), "Tall layout centers the full square")
	_check(
		notice.position.y >= tall_artwork.position.y + tall_artwork.size.y * 0.8,
		"Tall layout places the notice below the illustrated grid"
	)
	menu.size = Vector2(1280.0, 720.0)
	await process_frame
	var wide_artwork: Rect2 = menu.debug_get_artwork_rect()
	_check(wide_artwork == Rect2(280.0, 0.0, 720.0, 720.0), "Wide layout centers the full square")
	_check(
		notice.position.y >= wide_artwork.position.y + wide_artwork.size.y * 0.8,
		"Wide layout keeps the notice below the illustrated grid"
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
