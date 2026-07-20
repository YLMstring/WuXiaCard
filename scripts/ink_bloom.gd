class_name InkBloom
extends Control

const POOLS: Array[Dictionary] = [
	{"center": Vector2(0.50, 0.53), "radius": Vector2(0.34, 0.25), "alpha": 0.92},
	{"center": Vector2(0.28, 0.58), "radius": Vector2(0.24, 0.17), "alpha": 0.82},
	{"center": Vector2(0.69, 0.40), "radius": Vector2(0.23, 0.20), "alpha": 0.86},
	{"center": Vector2(0.57, 0.70), "radius": Vector2(0.27, 0.13), "alpha": 0.74},
]

const DROPLETS: Array[Dictionary] = [
	{"center": Vector2(0.12, 0.29), "radius": 0.050, "alpha": 0.82},
	{"center": Vector2(0.86, 0.68), "radius": 0.035, "alpha": 0.76},
	{"center": Vector2(0.78, 0.17), "radius": 0.025, "alpha": 0.68},
	{"center": Vector2(0.20, 0.82), "radius": 0.020, "alpha": 0.62},
]

@export var ink_color: Color = Color("211824"):
	set(value):
		ink_color = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	queue_redraw()


func set_ink_color(value: Color) -> void:
	ink_color = value


func get_pool_count() -> int:
	return POOLS.size()


func get_droplet_count() -> int:
	return DROPLETS.size()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	for pool: Dictionary in POOLS:
		var center: Vector2 = (pool["center"] as Vector2) * size
		var radius: Vector2 = (pool["radius"] as Vector2) * size
		var tint: Color = ink_color
		tint.a *= float(pool["alpha"])
		draw_set_transform(center, 0.0, Vector2(1.0, radius.y / radius.x))
		draw_circle(Vector2.ZERO, radius.x, tint, true, -1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var short_side: float = minf(size.x, size.y)
	for droplet: Dictionary in DROPLETS:
		var center: Vector2 = (droplet["center"] as Vector2) * size
		var tint: Color = ink_color
		tint.a *= float(droplet["alpha"])
		draw_circle(center, float(droplet["radius"]) * short_side, tint, true, -1.0, true)
