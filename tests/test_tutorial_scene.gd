extends SceneTree

const TUTORIAL_SCENE: PackedScene = preload("res://scenes/tutorial.tscn")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var tutorial: Variant = TUTORIAL_SCENE.instantiate()
	root.add_child(tutorial)
	await process_frame
	var page_texture := tutorial.get_node("PageTexture") as TextureRect
	var advance_button := tutorial.get_node("AdvanceButton") as Button
	var notice_label := tutorial.get_node("Notice") as Label
	_check(tutorial.debug_get_page_count() == 10, "Tutorial contains ten ordered pages")
	_check(tutorial.debug_get_current_page_index() == 0, "Tutorial opens on its first page")
	_check(
		tutorial.debug_get_current_texture().resource_path.ends_with("tutorial_01.png"),
		"Tutorial displays page one immediately"
	)
	_check(
		tutorial.debug_get_current_texture().get_size() == Vector2(1080, 2400),
		"Page one keeps the authored 20:9 dimensions"
	)
	_check(
		page_texture.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED,
		"Tutorial artwork uses centered aspect-cover scaling"
	)
	_check(
		page_texture.anchor_right == 1.0
		and page_texture.anchor_bottom == 1.0
		and advance_button.anchor_right == 1.0
		and advance_button.anchor_bottom == 1.0,
		"Tutorial artwork and input surface fill the viewport"
	)

	var completion_count: Array[int] = [0]
	tutorial.completion_requested.connect(func() -> void: completion_count[0] += 1)
	for expected_page: int in range(1, 10):
		advance_button.pressed.emit()
		_check(
			tutorial.debug_get_current_page_index() == expected_page,
			"One press advances exactly to page %d" % (expected_page + 1)
		)
		_check(
			tutorial.debug_get_current_texture().resource_path.ends_with(
				"tutorial_%02d.png" % (expected_page + 1)
			),
			"Page %d uses its matching texture" % (expected_page + 1)
		)
		_check(
			tutorial.debug_get_current_texture().get_size() == Vector2(1080, 2400),
			"Page %d keeps the authored 20:9 dimensions" % (expected_page + 1)
		)
	_check(completion_count[0] == 0, "Reaching page ten does not finish it automatically")
	advance_button.pressed.emit()
	_check(
		completion_count[0] == 1
		and tutorial.debug_is_completion_request_pending()
		and advance_button.disabled,
		"Pressing page ten emits one locked completion request"
	)
	advance_button.pressed.emit()
	_check(completion_count[0] == 1, "Repeated input cannot duplicate a pending completion request")
	tutorial.show_save_error()
	_check(
		not tutorial.debug_is_completion_request_pending()
		and not advance_button.disabled
		and notice_label.visible
		and notice_label.text == "保存失败，请重试",
		"A save failure reports the error and allows a retry"
	)
	advance_button.pressed.emit()
	_check(completion_count[0] == 2, "Retry input emits one new completion request")
	tutorial.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if _failures == 0:
		print("TUTORIAL_SCENE_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("TUTORIAL_SCENE_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
