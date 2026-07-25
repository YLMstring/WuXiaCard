extends SceneTree

const Backdrop = preload("res://scripts/duel_backdrop.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_fitted_duel_rect()
	_test_layout_classification()
	_test_decoration_description()
	_test_lacquer_geometry()
	_test_lacquer_tint_texture()

	if _failures == 0:
		print("DUEL_BACKDROP_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("DUEL_BACKDROP_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _test_fitted_duel_rect() -> void:
	var exact: Rect2 = Backdrop.fit_duel_rect(Vector2(540.0, 960.0))
	_check(
		exact.is_equal_approx(Rect2(0.0, 0.0, 540.0, 960.0)),
		"Exact 9:16 viewport is fully occupied"
	)

	var tall: Rect2 = Backdrop.fit_duel_rect(Vector2(405.0, 900.0))
	_check(
		tall.is_equal_approx(Rect2(0.0, 90.0, 405.0, 720.0)),
		"Tall phone fits a centered 9:16 duel by width"
	)

	var wide: Rect2 = Backdrop.fit_duel_rect(Vector2(1280.0, 839.0))
	_check(is_equal_approx(wide.size.y, 839.0), "Wide PC fits the duel by height")
	_check(
		is_equal_approx(wide.size.x / wide.size.y, 9.0 / 16.0),
		"Wide PC duel preserves the 9:16 aspect ratio"
	)
	_check(
		wide.get_center().is_equal_approx(Vector2(640.0, 419.5)),
		"Wide PC duel remains centered"
	)

	_check(
		Backdrop.fit_duel_rect(Vector2.ZERO) == Rect2(),
		"Non-positive viewport dimensions return an empty rectangle"
	)


func _test_layout_classification() -> void:
	_check(
		Backdrop.classify_layout(Vector2(540.0, 960.0)) == Backdrop.LayoutMode.MODE_EXACT,
		"9:16 viewport selects exact mode"
	)
	_check(
		Backdrop.classify_layout(Vector2(405.0, 900.0)) == Backdrop.LayoutMode.MODE_TALL,
		"Tall phone selects tall mode"
	)
	_check(
		Backdrop.classify_layout(Vector2(1280.0, 839.0)) == Backdrop.LayoutMode.MODE_WIDE,
		"Wide PC selects wide mode"
	)


func _test_decoration_description() -> void:
	var exact: Dictionary = Backdrop.describe_decoration(Vector2(540.0, 960.0))
	_check(
		not exact["top_lacquer"]
		and not exact["bottom_ridges"]
		and not exact["side_wash"],
		"Exact mode exposes no decorative extension"
	)

	var tall: Dictionary = Backdrop.describe_decoration(Vector2(405.0, 900.0))
	_check(
		tall["top_lacquer"]
		and tall["bottom_ridges"]
		and not tall["side_wash"],
		"Tall mode uses lacquer above and rounded ridges below"
	)

	var wide: Dictionary = Backdrop.describe_decoration(Vector2(1280.0, 839.0))
	_check(
		not wide["top_lacquer"]
		and not wide["bottom_ridges"]
		and wide["side_wash"],
		"Wide mode uses mountain-free mirrored side wash"
	)


func _test_lacquer_geometry() -> void:
	var extension_rect := Rect2(0.0, 0.0, 405.0, 90.0)
	var geometry: Dictionary = Backdrop.calculate_lacquer_geometry(extension_rect)
	_check(
		is_equal_approx(float(geometry["first_y"]), 10.0),
		"Upper lacquer line retains its responsive inset"
	)
	_check(
		is_equal_approx(float(geometry["second_y"]), 89.5),
		"Lower lacquer line sits half a pixel inside the duel seam"
	)
	_check(
		is_equal_approx(
			float(geometry["ornament_y"]),
			(float(geometry["first_y"]) + float(geometry["second_y"])) * 0.5
		),
		"Lacquer ornaments remain exactly centered between both gold lines"
	)


func _test_lacquer_tint_texture() -> void:
	var texture: GradientTexture2D = Backdrop.create_lacquer_tint_texture(405)
	var gradient: Gradient = texture.gradient
	_check(texture.width == 405, "Shared lacquer tint preserves the requested texture width")
	_check(
		gradient.offsets == PackedFloat32Array([0.0, 0.52, 1.0]),
		"Shared lacquer tint keeps the approved horizontal offsets"
	)
	_check(
		gradient.colors[0].is_equal_approx(Color(0.0, 0.0, 0.0, 0.0))
		and gradient.colors[1].is_equal_approx(Color(0.42, 0.25, 0.22, 0.66))
		and gradient.colors[2].is_equal_approx(Color(0.0, 0.0, 0.0, 0.0)),
		"Shared lacquer tint keeps transparent edges and the approved warm center"
	)
	_check(
		texture.fill_from.is_equal_approx(Vector2(0.0, 0.5))
		and texture.fill_to.is_equal_approx(Vector2(1.0, 0.5)),
		"Shared lacquer tint runs horizontally across the full width"
	)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
