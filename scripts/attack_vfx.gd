class_name AttackVfx
extends Control

const ATTACK_TEXTURE: Texture2D = preload("res://inkpics/attack.png")
const DISPLAY_SIZE: Vector2 = Vector2(64.0, 22.0)
const WRITE_PHASE_RATIO: float = 0.40
const HOLD_PHASE_RATIO: float = 0.233333
const FADE_PHASE_RATIO: float = 0.366667

var _effect_root: Control = null
var _clip: Control = null
var _texture_rect: TextureRect = null
var _is_playing: bool = false
var _playback_count: int = 0
var _last_center: Vector2 = Vector2.ZERO
var _last_rotation: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_visual_hierarchy()
	_reset_visuals()


func play_attack(
	seam_global_center: Vector2,
	rotation_radians: float,
	duration: float
) -> void:
	while _is_playing:
		await get_tree().process_frame
	_is_playing = true
	_playback_count += 1
	_ensure_visual_hierarchy()

	var inverse: Transform2D = get_global_transform_with_canvas().affine_inverse()
	_last_center = inverse * seam_global_center
	_last_rotation = rotation_radians
	_effect_root.position = _last_center - DISPLAY_SIZE * 0.5
	_effect_root.rotation = rotation_radians

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


func debug_get_last_center() -> Vector2:
	return _last_center


func debug_get_last_rotation() -> float:
	return _last_rotation


func debug_get_display_size() -> Vector2:
	return DISPLAY_SIZE


func debug_get_texture_path() -> String:
	return ATTACK_TEXTURE.resource_path


func debug_get_clip_size() -> Vector2:
	if _clip == null:
		return Vector2.ZERO
	return _clip.size


func debug_is_clean() -> bool:
	return (
		not _is_playing
		and not visible
		and _clip != null
		and is_zero_approx(_clip.size.x)
		and _effect_root != null
		and is_zero_approx(_effect_root.modulate.a)
	)


func _ensure_visual_hierarchy() -> void:
	if _effect_root != null:
		return

	_effect_root = Control.new()
	_effect_root.name = "EffectRoot"
	_effect_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effect_root.size = DISPLAY_SIZE
	_effect_root.pivot_offset = DISPLAY_SIZE * 0.5
	add_child(_effect_root)

	_clip = Control.new()
	_clip.name = "Clip"
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.clip_contents = true
	_clip.position = Vector2.ZERO
	_clip.size = Vector2(0.0, DISPLAY_SIZE.y)
	_effect_root.add_child(_clip)

	_texture_rect = TextureRect.new()
	_texture_rect.name = "Texture"
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.texture = ATTACK_TEXTURE
	_texture_rect.position = Vector2.ZERO
	_texture_rect.size = DISPLAY_SIZE
	_clip.add_child(_texture_rect)


func _set_reveal_progress(value: float) -> void:
	_ensure_visual_hierarchy()
	var progress: float = clampf(value, 0.0, 1.0)
	_clip.size = Vector2(DISPLAY_SIZE.x * progress, DISPLAY_SIZE.y)


func _set_opacity(value: float) -> void:
	_ensure_visual_hierarchy()
	var effect_color := Color.WHITE
	effect_color.a = clampf(value, 0.0, 1.0)
	_effect_root.modulate = effect_color


func _reset_visuals() -> void:
	_ensure_visual_hierarchy()
	_set_reveal_progress(0.0)
	_set_opacity(0.0)
	_effect_root.position = Vector2.ZERO
	_effect_root.rotation = 0.0
	visible = false
