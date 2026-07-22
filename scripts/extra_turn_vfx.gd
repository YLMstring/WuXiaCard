class_name ExtraTurnVfx
extends Control

const BEAD_RADIUS: float = 7.0
const SOURCE_PULSE_SCALE: float = 1.07

var _beads: Array[Dictionary] = []
var _board_rect: Rect2 = Rect2()
var _effect_color: Color = Color("e3b84f")
var _bead_progress: float = 0.0
var _pulse_progress: float = 0.0
var _draw_beads: bool = false
var _draw_board_pulse: bool = false
var _is_playing: bool = false
var _last_bead_count: int = 0
var _pulse_count: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func play_convergence(
	source_controls: Array,
	board_global_rect: Rect2,
	convergence_duration: float,
	pulse_duration: float,
	effect_color: Color
) -> void:
	while _is_playing:
		await get_tree().process_frame
	_is_playing = true
	_effect_color = effect_color
	_prepare_geometry(source_controls, board_global_rect)
	visible = true
	_draw_beads = not _beads.is_empty()
	_draw_board_pulse = false
	_set_bead_progress(0.0)
	_set_pulse_progress(0.0)

	if _draw_beads and convergence_duration > 0.0:
		var convergence_tween: Tween = create_tween()
		convergence_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		convergence_tween.tween_method(
			Callable(self, "_set_bead_progress"),
			0.0,
			1.0,
			convergence_duration
		)
		await convergence_tween.finished
	else:
		_set_bead_progress(1.0)
	_draw_beads = false
	_draw_board_pulse = true
	_pulse_count += 1
	queue_redraw()

	var source_records: Array[Dictionary] = _get_source_records(source_controls)
	var source_tweens: Array[Tween] = []
	if pulse_duration > 0.0:
		for record: Dictionary in source_records:
			var source: Control = record["control"] as Control
			if not is_instance_valid(source):
				continue
			var resting_scale: Vector2 = record["scale"] as Vector2
			source.pivot_offset = source.size * 0.5
			var source_tween: Tween = source.create_tween()
			source_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			source_tween.tween_property(
				source,
				"scale",
				resting_scale * SOURCE_PULSE_SCALE,
				pulse_duration * 0.35
			)
			source_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
			source_tween.tween_property(
				source,
				"scale",
				resting_scale,
				pulse_duration * 0.65
			)
			source_tweens.append(source_tween)
		var board_tween: Tween = create_tween()
		board_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		board_tween.tween_method(
			Callable(self, "_set_pulse_progress"),
			0.0,
			1.0,
			pulse_duration
		)
		await board_tween.finished
	else:
		_set_pulse_progress(1.0)

	for record: Dictionary in source_records:
		var source: Control = record["control"] as Control
		if is_instance_valid(source):
			source.scale = record["scale"] as Vector2
	_reset_visuals()
	_is_playing = false


func debug_get_last_bead_count() -> int:
	return _last_bead_count


func debug_get_pulse_count() -> int:
	return _pulse_count


func debug_is_clean() -> bool:
	return not _is_playing and not visible and _beads.is_empty()


func _prepare_geometry(source_controls: Array, board_global_rect: Rect2) -> void:
	_beads.clear()
	var seen_sources: Dictionary = {}
	for source_value: Variant in source_controls:
		var source: Control = source_value as Control
		if source == null or not is_instance_valid(source):
			continue
		var source_id: int = source.get_instance_id()
		if seen_sources.has(source_id):
			continue
		seen_sources[source_id] = true
		var source_rect: Rect2 = source.get_global_rect()
		_beads.append({
			"start": _global_to_local(source_rect.position + source_rect.size * Vector2(0.82, 0.18)),
			"end": _global_to_local(source_rect.get_center()),
		})
	_last_bead_count = _beads.size()
	var board_top_left: Vector2 = _global_to_local(board_global_rect.position)
	var board_bottom_right: Vector2 = _global_to_local(board_global_rect.end)
	_board_rect = Rect2(board_top_left, board_bottom_right - board_top_left)


func _global_to_local(global_point: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * global_point


func _get_source_records(source_controls: Array) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var seen_sources: Dictionary = {}
	for source_value: Variant in source_controls:
		var source: Control = source_value as Control
		if source == null or not is_instance_valid(source):
			continue
		var source_id: int = source.get_instance_id()
		if seen_sources.has(source_id):
			continue
		seen_sources[source_id] = true
		records.append({"control": source, "scale": source.scale})
	return records


func _set_bead_progress(value: float) -> void:
	_bead_progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func _set_pulse_progress(value: float) -> void:
	_pulse_progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func _reset_visuals() -> void:
	_beads.clear()
	_board_rect = Rect2()
	_draw_beads = false
	_draw_board_pulse = false
	_bead_progress = 0.0
	_pulse_progress = 0.0
	visible = false
	queue_redraw()


func _draw() -> void:
	if _draw_beads:
		var eased_progress: float = ease(_bead_progress, 2.0)
		var bead_alpha: float = 1.0 - eased_progress * 0.45
		var bead_radius: float = lerpf(BEAD_RADIUS, BEAD_RADIUS * 0.28, eased_progress)
		for bead: Dictionary in _beads:
			var bead_position: Vector2 = (bead["start"] as Vector2).lerp(
				bead["end"] as Vector2,
				eased_progress
			)
			draw_circle(bead_position, bead_radius + 5.0, Color(_effect_color, 0.18 * bead_alpha))
			draw_circle(bead_position, bead_radius, Color(_effect_color, bead_alpha))
			draw_arc(bead_position, bead_radius + 1.5, 0.0, TAU, 24, Color(0.42, 0.18, 0.05, bead_alpha), 1.5)
	if _draw_board_pulse and _board_rect.size != Vector2.ZERO:
		var pulse_alpha: float = sin(_pulse_progress * PI)
		var expansion: float = lerpf(2.0, 18.0, _pulse_progress)
		var pulse_rect: Rect2 = _board_rect.grow(expansion)
		var outline := StyleBoxFlat.new()
		outline.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		outline.border_color = Color(_effect_color, pulse_alpha * 0.92)
		outline.set_border_width_all(4)
		outline.set_corner_radius_all(12)
		draw_style_box(outline, pulse_rect)
