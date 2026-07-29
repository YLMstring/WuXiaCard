class_name MainMenuBackdrop
extends Control

const PAPER_COLOR: Color = Color("d6d0b6")
const SAGE_COLOR: Color = Color("929b8b")
const INK_COLOR: Color = Color(0.12, 0.17, 0.15, 0.15)
const MIST_COLOR: Color = Color(0.96, 0.94, 0.85, 0.16)
const GOLD_COLOR: Color = Color("b88d58")

var artwork_rect: Rect2 = Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


static func fit_square_rect(viewport_size: Vector2) -> Rect2:
	var side: float = minf(viewport_size.x, viewport_size.y)
	if side <= 0.0:
		return Rect2()
	return Rect2((viewport_size - Vector2(side, side)) * 0.5, Vector2(side, side))


func configure(new_artwork_rect: Rect2) -> void:
	artwork_rect = new_artwork_rect
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), PAPER_COLOR)
	if artwork_rect.position.y > 0.0:
		_draw_tall_extensions()
	elif artwork_rect.position.x > 0.0:
		_draw_wide_extensions()


func _draw_tall_extensions() -> void:
	var top_rect := Rect2(0.0, 0.0, size.x, artwork_rect.position.y)
	var bottom_rect := Rect2(
		0.0,
		artwork_rect.end.y,
		size.x,
		maxf(0.0, size.y - artwork_rect.end.y)
	)
	_draw_vertical_wash(top_rect, SAGE_COLOR, PAPER_COLOR)
	_draw_vertical_wash(bottom_rect, PAPER_COLOR, SAGE_COLOR)
	if top_rect.size.y > 4.0:
		draw_line(
			Vector2(0.0, top_rect.end.y - 0.5),
			Vector2(size.x, top_rect.end.y - 0.5),
			GOLD_COLOR,
			1.0
		)
		_draw_soft_cluster(
			Vector2(size.x * 0.52, top_rect.size.y * 0.48),
			minf(size.x, top_rect.size.y) * 0.62,
			MIST_COLOR
		)
	if bottom_rect.size.y > 4.0:
		draw_line(
			Vector2(0.0, bottom_rect.position.y + 0.5),
			Vector2(size.x, bottom_rect.position.y + 0.5),
			GOLD_COLOR,
			1.0
		)
		_draw_ridge(bottom_rect, 0.62, 0.18, INK_COLOR)
		_draw_ridge(bottom_rect, 0.78, 0.11, Color(0.09, 0.14, 0.12, 0.10))


func _draw_wide_extensions() -> void:
	var left_rect := Rect2(0.0, 0.0, artwork_rect.position.x, size.y)
	var right_rect := Rect2(
		artwork_rect.end.x,
		0.0,
		maxf(0.0, size.x - artwork_rect.end.x),
		size.y
	)
	_draw_horizontal_wash(left_rect, SAGE_COLOR, PAPER_COLOR)
	_draw_horizontal_wash(right_rect, PAPER_COLOR, SAGE_COLOR)
	_draw_soft_cluster(
		Vector2(left_rect.size.x * 0.42, size.y * 0.32),
		minf(left_rect.size.x, size.y) * 0.58,
		INK_COLOR
	)
	_draw_soft_cluster(
		Vector2(right_rect.position.x + right_rect.size.x * 0.58, size.y * 0.68),
		minf(right_rect.size.x, size.y) * 0.58,
		INK_COLOR
	)


func _draw_vertical_wash(rect: Rect2, from_color: Color, to_color: Color) -> void:
	var steps: int = 18
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


func _draw_horizontal_wash(rect: Rect2, from_color: Color, to_color: Color) -> void:
	var steps: int = 18
	for step_index: int in range(steps):
		var progress: float = float(step_index) / float(steps - 1)
		var step_width: float = rect.size.x / float(steps)
		draw_rect(
			Rect2(
				rect.position.x + step_width * float(step_index),
				rect.position.y,
				step_width + 1.0,
				rect.size.y
			),
			from_color.lerp(to_color, progress)
		)


func _draw_ridge(rect: Rect2, baseline_ratio: float, amplitude_ratio: float, color: Color) -> void:
	var points := PackedVector2Array([Vector2(rect.position.x, rect.end.y)])
	for sample_index: int in range(33):
		var progress: float = float(sample_index) / 32.0
		var wave: float = sin(progress * TAU * 1.15) + sin(progress * TAU * 2.1) * 0.22
		points.append(Vector2(
			rect.position.x + rect.size.x * progress,
			rect.position.y + rect.size.y * baseline_ratio - rect.size.y * amplitude_ratio * wave
		))
	points.append(Vector2(rect.end.x, rect.end.y))
	draw_colored_polygon(points, color)


func _draw_soft_cluster(center: Vector2, radius: float, color: Color) -> void:
	if radius <= 0.0:
		return
	for layer_index: int in range(7, 0, -1):
		var progress: float = float(layer_index) / 7.0
		var layer_color: Color = color
		layer_color.a *= (1.0 - progress * 0.72) / 7.0
		draw_circle(center, radius * progress, layer_color)
