class_name ExtraTurnVfx
extends Control

var _board_rect: Rect2 = Rect2()
var _effect_color: Color = Color("e3b84f")
var _pulse_progress: float = 0.0
var _draw_board_pulse: bool = false
var _is_playing: bool = false
var _pulse_count: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func play_pulse(
	board_global_rect: Rect2,
	board_pulse_duration: float,
	effect_color: Color
) -> void:
	while _is_playing:
		await get_tree().process_frame
	_is_playing = true
	_effect_color = effect_color
	var board_top_left: Vector2 = _global_to_local(board_global_rect.position)
	var board_bottom_right: Vector2 = _global_to_local(board_global_rect.end)
	_board_rect = Rect2(board_top_left, board_bottom_right - board_top_left)
	visible = true
	_draw_board_pulse = true
	_pulse_progress = 0.0
	_pulse_count += 1
	queue_redraw()
	if board_pulse_duration > 0.0:
		var board_tween: Tween = create_tween()
		board_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		board_tween.tween_method(
			Callable(self, "_set_pulse_progress"),
			0.0,
			1.0,
			board_pulse_duration
		)
		await board_tween.finished
	else:
		_set_pulse_progress(1.0)
	_reset_visuals()
	_is_playing = false


func debug_get_pulse_count() -> int:
	return _pulse_count


func debug_is_clean() -> bool:
	return not _is_playing and not visible


func _global_to_local(global_point: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * global_point


func _set_pulse_progress(value: float) -> void:
	_pulse_progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func _reset_visuals() -> void:
	_board_rect = Rect2()
	_draw_board_pulse = false
	_pulse_progress = 0.0
	visible = false
	queue_redraw()


func _draw() -> void:
	if not _draw_board_pulse or _board_rect.size == Vector2.ZERO:
		return
	var pulse_alpha: float = sin(_pulse_progress * PI)
	var expansion: float = lerpf(2.0, 18.0, _pulse_progress)
	var pulse_rect: Rect2 = _board_rect.grow(expansion)
	var outline := StyleBoxFlat.new()
	outline.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	outline.border_color = Color(_effect_color, pulse_alpha * 0.92)
	outline.set_border_width_all(4)
	outline.set_corner_radius_all(12)
	draw_style_box(outline, pulse_rect)
