class_name AttackVfx
extends Control

const EDGE_INSET: float = 8.0
const DIRECTION_EPSILON: float = 0.0001
const FLECK_COUNT: int = 3
const WRITE_PHASE_RATIO: float = 0.40
const HOLD_PHASE_RATIO: float = 0.233333
const FADE_PHASE_RATIO: float = 0.366667

var _fragments: Array[Dictionary] = []
var _flecks: Array[Dictionary] = []
var _ink_color: Color = Color("211824")
var _stroke_start: Vector2 = Vector2.ZERO
var _stroke_end: Vector2 = Vector2.ZERO
var _reveal_progress: float = 0.0
var _opacity: float = 0.0
var _is_playing: bool = false
var _playback_count: int = 0
var _last_start: Vector2 = Vector2.ZERO
var _last_end: Vector2 = Vector2.ZERO
var _last_fleck_count: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func play_attack(
	source_global_rect: Rect2,
	target_global_rect: Rect2,
	duration: float,
	ink_color: Color
) -> void:
	while _is_playing:
		await get_tree().process_frame
	_is_playing = true
	_playback_count += 1
	_ink_color = ink_color
	_prepare_geometry(source_global_rect, target_global_rect)
	if _fragments.is_empty():
		_reset_visuals()
		_is_playing = false
		return

	visible = true
	_set_reveal_progress(0.0)
	_set_opacity(1.0)
	if duration > 0.0:
		var write_duration: float = duration * WRITE_PHASE_RATIO
		var hold_duration: float = duration * HOLD_PHASE_RATIO
		var fade_duration: float = duration * FADE_PHASE_RATIO
		var playback_tween: Tween = create_tween()
		playback_tween.tween_method(
			Callable(self, "_set_reveal_progress"),
			0.0,
			1.0,
			write_duration
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		playback_tween.tween_interval(hold_duration)
		playback_tween.tween_method(
			Callable(self, "_set_opacity"),
			1.0,
			0.0,
			fade_duration
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await playback_tween.finished
	else:
		_set_reveal_progress(1.0)
		_set_opacity(0.0)

	_reset_visuals()
	_is_playing = false


func debug_get_playback_count() -> int:
	return _playback_count


func debug_get_last_start() -> Vector2:
	return _last_start


func debug_get_last_end() -> Vector2:
	return _last_end


func debug_get_last_fleck_count() -> int:
	return _last_fleck_count


func debug_is_clean() -> bool:
	return (
		not _is_playing
		and not visible
		and _fragments.is_empty()
		and _flecks.is_empty()
	)


func _prepare_geometry(source_global_rect: Rect2, target_global_rect: Rect2) -> void:
	_fragments.clear()
	_flecks.clear()
	var source_rect: Rect2 = _global_rect_to_local(source_global_rect)
	var target_rect: Rect2 = _global_rect_to_local(target_global_rect)
	var center_delta: Vector2 = target_rect.get_center() - source_rect.get_center()
	if center_delta.length_squared() <= DIRECTION_EPSILON:
		_last_start = Vector2.ZERO
		_last_end = Vector2.ZERO
		_last_fleck_count = 0
		return

	var direction: Vector2 = center_delta.normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	var source_edge: Vector2 = _ray_rect_edge(
		source_rect,
		source_rect.get_center(),
		direction
	)
	var target_edge: Vector2 = _ray_rect_edge(
		target_rect,
		target_rect.get_center(),
		-direction
	)
	_stroke_start = source_edge - direction * EDGE_INSET
	_stroke_end = target_edge + direction * EDGE_INSET
	_last_start = _stroke_start
	_last_end = _stroke_end

	var stroke_length: float = _stroke_start.distance_to(_stroke_end)
	var body_width: float = clampf(stroke_length * 0.075, 4.5, 9.0)
	var fragment_specs: Array[Dictionary] = [
		{"from": 0.00, "to": 0.22, "offset": 0.0, "width": 1.00, "tone": 0.00},
		{"from": 0.245, "to": 0.47, "offset": -0.8, "width": 0.88, "tone": 0.04},
		{"from": 0.495, "to": 0.71, "offset": 0.9, "width": 0.72, "tone": 0.08},
		{"from": 0.735, "to": 1.00, "offset": -0.35, "width": 0.48, "tone": 0.02},
		{"from": 0.055, "to": 0.31, "offset": 4.1, "width": 0.18, "tone": 0.38},
		{"from": 0.365, "to": 0.63, "offset": -3.6, "width": 0.15, "tone": 0.44},
		{"from": 0.675, "to": 0.925, "offset": 2.8, "width": 0.12, "tone": 0.48},
	]
	for spec: Dictionary in fragment_specs:
		var start_t: float = float(spec["from"])
		var end_t: float = float(spec["to"])
		var midpoint: float = (start_t + end_t) * 0.5
		var taper: float = lerpf(1.0, 0.42, midpoint)
		_fragments.append({
			"from": start_t,
			"to": end_t,
			"offset": perpendicular * float(spec["offset"]),
			"width": maxf(0.75, body_width * float(spec["width"]) * taper),
			"tone": float(spec["tone"]),
		})

	var fleck_specs: Array[Vector3] = [
		Vector3(0.78, -6.7, 1.8),
		Vector3(0.87, 5.3, 1.35),
		Vector3(0.94, -3.1, 1.0),
	]
	for fleck_spec: Vector3 in fleck_specs:
		_flecks.append({
			"progress": fleck_spec.x,
			"position": _stroke_start.lerp(_stroke_end, fleck_spec.x)
				+ perpendicular * fleck_spec.y,
			"radius": fleck_spec.z,
		})
	_last_fleck_count = _flecks.size()
	assert(_last_fleck_count == FLECK_COUNT)


func _global_rect_to_local(global_rect: Rect2) -> Rect2:
	var inverse: Transform2D = get_global_transform_with_canvas().affine_inverse()
	var local_start: Vector2 = inverse * global_rect.position
	var local_end: Vector2 = inverse * global_rect.end
	return Rect2(local_start, local_end - local_start).abs()


func _ray_rect_edge(rect: Rect2, origin: Vector2, direction: Vector2) -> Vector2:
	var half_size: Vector2 = rect.size * 0.5
	var x_distance: float = INF
	var y_distance: float = INF
	if absf(direction.x) > DIRECTION_EPSILON:
		x_distance = half_size.x / absf(direction.x)
	if absf(direction.y) > DIRECTION_EPSILON:
		y_distance = half_size.y / absf(direction.y)
	return origin + direction * minf(x_distance, y_distance)


func _set_reveal_progress(value: float) -> void:
	_reveal_progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func _set_opacity(value: float) -> void:
	_opacity = clampf(value, 0.0, 1.0)
	queue_redraw()


func _reset_visuals() -> void:
	_fragments.clear()
	_flecks.clear()
	_reveal_progress = 0.0
	_opacity = 0.0
	visible = false
	queue_redraw()


func _draw() -> void:
	if _opacity <= 0.0:
		return
	var gray_brown: Color = _ink_color.lerp(Color("75685c"), 0.48)
	for fragment: Dictionary in _fragments:
		var start_t: float = float(fragment["from"])
		if _reveal_progress <= start_t:
			continue
		var end_t: float = minf(float(fragment["to"]), _reveal_progress)
		var offset: Vector2 = fragment["offset"]
		var fragment_color: Color = _ink_color.lerp(
			gray_brown,
			float(fragment["tone"])
		)
		fragment_color.a *= _opacity
		draw_line(
			_stroke_start.lerp(_stroke_end, start_t) + offset,
			_stroke_start.lerp(_stroke_end, end_t) + offset,
			fragment_color,
			float(fragment["width"]),
			true
		)
	for fleck: Dictionary in _flecks:
		if _reveal_progress < float(fleck["progress"]):
			continue
		var fleck_color := Color(_ink_color, _opacity * 0.82)
		draw_circle(
			fleck["position"],
			float(fleck["radius"]),
			fleck_color
		)
