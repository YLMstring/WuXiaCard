class_name DuelBackdrop
extends Control

const DUEL_ASPECT: float = 9.0 / 16.0
const ASPECT_EPSILON: float = 0.0001

const PARCHMENT_COLOR: Color = Color("d6d0b6")
const PARCHMENT_SAGE: Color = Color("9da596")
const LACQUER_COLOR: Color = Color("4a2d00")
const ANTIQUE_GOLD: Color = Color("bd9765")
const RIDGE_BACK_COLOR: Color = Color(0.325, 0.365, 0.341, 0.22)
const RIDGE_FRONT_COLOR: Color = Color(0.212, 0.278, 0.247, 0.15)
const INK_WASH_COLOR: Color = Color(0.18, 0.25, 0.22, 0.12)
const MIST_COLOR: Color = Color(0.96, 0.94, 0.85, 0.18)
const BOTTOM_STATUS_COLOR: Color = Color(0.42, 0.34, 0.27, 1.0)

enum LayoutMode {
	MODE_EXACT,
	MODE_TALL,
	MODE_WIDE,
}

var duel_rect: Rect2 = Rect2()
var presentation_mode: int = LayoutMode.MODE_EXACT
var _lacquer_tint_texture: GradientTexture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lacquer_tint_texture = create_lacquer_tint_texture(540)
	queue_redraw()


static func fit_duel_rect(viewport_size: Vector2) -> Rect2:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Rect2()
	var viewport_aspect: float = viewport_size.x / viewport_size.y
	var fitted_size: Vector2
	if viewport_aspect <= DUEL_ASPECT:
		fitted_size = Vector2(viewport_size.x, viewport_size.x / DUEL_ASPECT)
	else:
		fitted_size = Vector2(viewport_size.y * DUEL_ASPECT, viewport_size.y)
	return Rect2((viewport_size - fitted_size) * 0.5, fitted_size)


static func style_bottom_status(label: Label) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", BOTTOM_STATUS_COLOR)
	label.modulate = Color.WHITE
	label.self_modulate = Color.WHITE


static func classify_layout(viewport_size: Vector2) -> int:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return LayoutMode.MODE_EXACT
	var aspect_delta: float = viewport_size.x / viewport_size.y - DUEL_ASPECT
	if absf(aspect_delta) <= ASPECT_EPSILON:
		return LayoutMode.MODE_EXACT
	return LayoutMode.MODE_TALL if aspect_delta < 0.0 else LayoutMode.MODE_WIDE


static func describe_decoration(viewport_size: Vector2) -> Dictionary:
	var mode: int = classify_layout(viewport_size)
	return {
		"top_lacquer": mode == LayoutMode.MODE_TALL,
		"bottom_ridges": mode == LayoutMode.MODE_TALL,
		"side_wash": mode == LayoutMode.MODE_WIDE,
	}


static func calculate_lacquer_geometry(rect: Rect2) -> Dictionary:
	var inset: float = clampf(rect.size.y * 0.18, 3.0, 10.0)
	var first_y: float = rect.position.y + inset
	var second_y: float = rect.end.y - 0.5
	return {
		"first_y": first_y,
		"second_y": second_y,
		"ornament_y": (first_y + second_y) * 0.5,
	}


static func create_lacquer_tint_texture(width: int = 540) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.52, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.0),
		Color(0.42, 0.25, 0.22, 0.66),
		Color(0.0, 0.0, 0.0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = maxi(1, width)
	texture.height = 1
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


func configure(new_duel_rect: Rect2) -> void:
	duel_rect = new_duel_rect
	presentation_mode = classify_layout(size)
	queue_redraw()


func debug_get_layout_mode() -> int:
	return presentation_mode


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), PARCHMENT_COLOR)
	match presentation_mode:
		LayoutMode.MODE_TALL:
			_draw_tall_extensions()
		LayoutMode.MODE_WIDE:
			_draw_wide_extensions()


func _draw_tall_extensions() -> void:
	var top_height: float = maxf(0.0, duel_rect.position.y)
	var bottom_top: float = minf(size.y, duel_rect.end.y)
	var bottom_height: float = maxf(0.0, size.y - bottom_top)
	if top_height > 0.0:
		_draw_lacquer_extension(Rect2(0.0, 0.0, size.x, top_height))
	if bottom_height > 0.0:
		_draw_bottom_ink_extension(Rect2(0.0, bottom_top, size.x, bottom_height))


func _draw_lacquer_extension(rect: Rect2) -> void:
	draw_rect(rect, LACQUER_COLOR)
	draw_texture_rect(_lacquer_tint_texture, rect, false)
	if rect.size.y < 8.0:
		return
	var geometry: Dictionary = calculate_lacquer_geometry(rect)
	var first_y: float = float(geometry["first_y"])
	var second_y: float = float(geometry["second_y"])
	var ornament_y: float = float(geometry["ornament_y"])
	draw_line(
		Vector2(rect.position.x, first_y),
		Vector2(rect.end.x, first_y),
		ANTIQUE_GOLD,
		1.0
	)
	draw_line(
		Vector2(rect.position.x, second_y),
		Vector2(rect.end.x, second_y),
		ANTIQUE_GOLD,
		1.0
	)
	var center_x: float = rect.get_center().x
	var ornament_scale: float = clampf(rect.size.y * 0.075, 2.0, 5.0)
	for ornament_index: int in range(-2, 3):
		var ornament_x: float = center_x + float(ornament_index) * ornament_scale * 7.0
		if ornament_index % 2 == 0:
			_draw_diamond(Vector2(ornament_x, ornament_y), ornament_scale, ANTIQUE_GOLD)
		else:
			draw_circle(Vector2(ornament_x, ornament_y), ornament_scale * 0.42, ANTIQUE_GOLD)


func _draw_bottom_ink_extension(rect: Rect2) -> void:
	_draw_vertical_gradient(rect, PARCHMENT_COLOR, PARCHMENT_SAGE, 14)
	if rect.size.y < 4.0:
		return
	_draw_mist_cluster(rect, 0.52, 0.42, 0.68)
	_draw_rounded_ridge(rect, 0.56, 0.22, 0.0, RIDGE_BACK_COLOR)
	_draw_rounded_ridge(rect, 0.72, 0.13, 1.4, RIDGE_FRONT_COLOR)


func _draw_wide_extensions() -> void:
	var left_width: float = maxf(0.0, duel_rect.position.x)
	var right_left: float = minf(size.x, duel_rect.end.x)
	var right_width: float = maxf(0.0, size.x - right_left)
	if left_width > 0.0:
		_draw_side_wash(Rect2(0.0, 0.0, left_width, size.y), false)
	if right_width > 0.0:
		_draw_side_wash(Rect2(right_left, 0.0, right_width, size.y), true)


func _draw_side_wash(rect: Rect2, mirrored: bool) -> void:
	var steps: int = 18
	for step_index: int in range(steps):
		var progress: float = float(step_index) / float(steps - 1)
		var inward_progress: float = 1.0 - progress if mirrored else progress
		var color: Color = PARCHMENT_SAGE.lerp(PARCHMENT_COLOR, inward_progress)
		var step_width: float = rect.size.x / float(steps)
		draw_rect(
			Rect2(
				rect.position.x + step_width * float(step_index),
				rect.position.y,
				step_width + 1.0,
				rect.size.y
			),
			color
		)
	var ink_center_x: float = rect.position.x + rect.size.x * (0.70 if mirrored else 0.30)
	var mist_center_x: float = rect.position.x + rect.size.x * (0.42 if mirrored else 0.58)
	_draw_soft_cluster(
		Vector2(ink_center_x, rect.position.y + rect.size.y * 0.27),
		minf(rect.size.x, rect.size.y) * 0.42,
		INK_WASH_COLOR
	)
	_draw_soft_cluster(
		Vector2(mist_center_x, rect.position.y + rect.size.y * 0.74),
		minf(rect.size.x, rect.size.y) * 0.48,
		MIST_COLOR
	)


func _draw_vertical_gradient(rect: Rect2, from_color: Color, to_color: Color, steps: int) -> void:
	for step_index: int in range(steps):
		var progress: float = float(step_index) / float(steps - 1)
		var step_height: float = rect.size.y / float(steps)
		draw_rect(
			Rect2(
				rect.position.x,
				rect.position.y + step_height * float(step_index),
				rect.size.x,
				step_height + 1.0
			),
			from_color.lerp(to_color, progress)
		)


func _draw_rounded_ridge(
	rect: Rect2,
	baseline_ratio: float,
	amplitude_ratio: float,
	phase: float,
	color: Color
) -> void:
	var points := PackedVector2Array()
	points.append(Vector2(rect.position.x, rect.end.y))
	var sample_count: int = 32
	for sample_index: int in range(sample_count + 1):
		var progress: float = float(sample_index) / float(sample_count)
		var broad_wave: float = sin(progress * TAU * 1.18 + phase)
		var soft_wave: float = sin(progress * TAU * 2.05 + phase * 0.53) * 0.28
		var ridge_y: float = (
			rect.position.y
			+ rect.size.y * baseline_ratio
			- rect.size.y * amplitude_ratio * (broad_wave + soft_wave)
		)
		points.append(Vector2(rect.position.x + rect.size.x * progress, ridge_y))
	points.append(Vector2(rect.end.x, rect.end.y))
	draw_colored_polygon(points, color)


func _draw_mist_cluster(
	rect: Rect2,
	center_x_ratio: float,
	center_y_ratio: float,
	radius_ratio: float
) -> void:
	var center := Vector2(
		rect.position.x + rect.size.x * center_x_ratio,
		rect.position.y + rect.size.y * center_y_ratio
	)
	var radius: float = minf(rect.size.x, rect.size.y) * radius_ratio
	_draw_soft_cluster(center, radius, MIST_COLOR)


func _draw_soft_cluster(center: Vector2, radius: float, color: Color) -> void:
	if radius <= 0.0:
		return
	for layer_index: int in range(7, 0, -1):
		var progress: float = float(layer_index) / 7.0
		var layer_color: Color = color
		layer_color.a *= (1.0 - progress * 0.72) / 7.0
		draw_circle(center, radius * progress, layer_color)


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius, 0.0),
	])
	draw_colored_polygon(points, color)
