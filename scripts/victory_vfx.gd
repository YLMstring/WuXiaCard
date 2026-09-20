class_name VictoryVfx
extends Control

signal settled
signal finished

const DROP_START_OFFSET_Y: float = -153.0
const DROP_INITIAL_SCALE: float = 2.0

@export_range(0.0, 1.0, 0.01) var dimmer_alpha: float = 0.42
@export_range(0.0, 2.0, 0.01) var entry_duration: float = 0.25
@export_range(0.0, 2.0, 0.01) var impact_duration: float = 0.45
@export_range(0.0, 2.0, 0.01) var settle_duration: float = 0.40
@export_range(0.0, 4.0, 0.01) var hold_duration: float = 1.90
@export_range(0.0, 2.0, 0.01) var fade_duration: float = 1.00
@export_range(-80.0, 6.0, 0.5) var gong_volume_db: float = -5.0

@onready var dimmer: ColorRect = $Dimmer
@onready var vignette: ColorRect = $Vignette
@onready var radial_glow: ColorRect = $RadialGlow
@onready var light_rays: ColorRect = $LightRays
@onready var gold_particles: ColorRect = $GoldParticles
@onready var victory_emblem: TextureRect = $VictoryEmblem
@onready var fallback_glyph: Label = $FallbackGlyph
@onready var impact_flash: ColorRect = $ImpactFlash
@onready var gong_player: AudioStreamPlayer = $GongPlayer

var _animation: Tween = null
var _drop_animation: Tween = null
var _is_playing: bool = false
var _is_settled: bool = false
var _play_count: int = 0
var _emblem_rest_position: Vector2 = Vector2.ZERO
var _fallback_rest_position: Vector2 = Vector2.ZERO
var _particles_rest_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emblem_rest_position = victory_emblem.position
	_fallback_rest_position = fallback_glyph.position
	_particles_rest_position = gold_particles.position
	_reset_visuals()
	if not OS.has_feature("headless"):
		gong_player.stream = _create_gong_stream()
		gong_player.volume_db = gong_volume_db


func play() -> void:
	if _is_playing:
		return
	_kill_animation()
	_reset_visuals()
	_is_playing = true
	_is_settled = false
	_play_count += 1
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_start_drop_motion()

	_animation = create_tween()
	_animation.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_animation.tween_property(dimmer, "color:a", dimmer_alpha, entry_duration)
	_animation.parallel().tween_property(vignette, "modulate:a", 1.0, entry_duration)
	_animation.parallel().tween_property(victory_emblem, "modulate:a", 0.32, entry_duration)
	_animation.parallel().tween_property(fallback_glyph, "modulate:a", 0.32, entry_duration)
	_animation.parallel().tween_property(radial_glow, "modulate:a", 0.20, entry_duration)

	_animation.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_animation.tween_property(victory_emblem, "scale", Vector2(0.92, 0.92), impact_duration)
	_animation.parallel().tween_property(fallback_glyph, "scale", Vector2(0.92, 0.92), impact_duration)
	_animation.parallel().tween_property(victory_emblem, "modulate:a", 1.0, impact_duration)
	_animation.parallel().tween_property(fallback_glyph, "modulate:a", 1.0, impact_duration)
	_animation.parallel().tween_property(radial_glow, "modulate:a", 0.92, impact_duration)
	_animation.parallel().tween_property(radial_glow, "scale", Vector2(1.12, 1.12), impact_duration)
	_animation.parallel().tween_property(light_rays, "modulate:a", 0.78, impact_duration)
	_animation.parallel().tween_property(light_rays, "scale", Vector2.ONE, impact_duration)
	_animation.parallel().tween_property(impact_flash, "modulate:a", 0.68, impact_duration)
	_animation.parallel().tween_property(impact_flash, "scale", Vector2.ONE, impact_duration)
	_animation.parallel().tween_property(gold_particles, "modulate:a", 0.78, impact_duration)
	_animation.tween_callback(_strike_gong)

	_animation.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_animation.tween_property(victory_emblem, "scale", Vector2.ONE, settle_duration)
	_animation.parallel().tween_property(fallback_glyph, "scale", Vector2.ONE, settle_duration)
	_animation.parallel().tween_property(impact_flash, "modulate:a", 0.0, settle_duration)
	_animation.parallel().tween_property(radial_glow, "modulate:a", 0.58, settle_duration)
	_animation.parallel().tween_property(light_rays, "modulate:a", 0.46, settle_duration)
	_animation.tween_callback(_mark_settled)

	_animation.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_animation.tween_property(light_rays, "rotation", 0.16, hold_duration)
	_animation.parallel().tween_property(gold_particles, "position", _particles_rest_position + Vector2(0.0, -18.0), hold_duration)
	_animation.parallel().tween_property(radial_glow, "scale", Vector2(1.04, 1.04), hold_duration)

	_animation.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_animation.tween_property(dimmer, "color:a", 0.0, fade_duration)
	_animation.parallel().tween_property(vignette, "modulate:a", 0.0, fade_duration)
	_animation.parallel().tween_property(radial_glow, "modulate:a", 0.0, fade_duration)
	_animation.parallel().tween_property(light_rays, "modulate:a", 0.0, fade_duration)
	_animation.parallel().tween_property(gold_particles, "modulate:a", 0.0, fade_duration)
	_animation.parallel().tween_property(victory_emblem, "modulate:a", 0.0, fade_duration)
	_animation.parallel().tween_property(fallback_glyph, "modulate:a", 0.0, fade_duration)
	_animation.parallel().tween_property(impact_flash, "modulate:a", 0.0, fade_duration)
	_animation.tween_callback(_complete)


func complete_settle_immediately() -> void:
	if not _is_playing or _is_settled:
		return
	_kill_animation()
	_apply_settled_visuals()
	_mark_settled()


func complete_immediately() -> void:
	if not _is_playing:
		return
	_kill_animation()
	if not _is_settled:
		_apply_settled_visuals()
		_mark_settled()
	_complete()


func cancel() -> void:
	_kill_animation()
	if gong_player != null:
		gong_player.stop()
	_is_playing = false
	_is_settled = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reset_visuals()


func is_playing() -> bool:
	return _is_playing


func debug_get_play_count() -> int:
	return _play_count


func debug_get_drop_offset_y(elapsed_seconds: float) -> float:
	return lerpf(
		DROP_START_OFFSET_Y,
		0.0,
		_drop_curve_progress(elapsed_seconds / _drop_duration())
	)


func debug_get_drop_speed_y(_elapsed_seconds: float) -> float:
	return -DROP_START_OFFSET_Y / _drop_duration()


func _mark_settled() -> void:
	if not _is_playing or _is_settled:
		return
	_is_settled = true
	settled.emit()


func _complete() -> void:
	if not _is_playing:
		return
	if not _is_settled:
		_mark_settled()
	_is_playing = false
	_is_settled = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reset_visuals()
	finished.emit()


func _kill_animation() -> void:
	if _animation != null and _animation.is_valid():
		_animation.kill()
	_animation = null
	if _drop_animation != null and _drop_animation.is_valid():
		_drop_animation.kill()
	_drop_animation = null


func _drop_duration() -> float:
	return maxf(entry_duration + impact_duration, 0.001)


func _drop_curve_progress(normalized_time: float) -> float:
	return clampf(normalized_time, 0.0, 1.0)


func _set_drop_progress(progress: float) -> void:
	var offset := Vector2(
		0.0,
		lerpf(DROP_START_OFFSET_Y, 0.0, _drop_curve_progress(progress))
	)
	if victory_emblem != null:
		victory_emblem.position = _emblem_rest_position + offset
	if fallback_glyph != null:
		fallback_glyph.position = _fallback_rest_position + offset


func _start_drop_motion() -> void:
	_set_drop_progress(0.0)
	_drop_animation = create_tween()
	_drop_animation.set_trans(Tween.TRANS_LINEAR)
	_drop_animation.tween_method(_set_drop_progress, 0.0, 1.0, _drop_duration())


func _reset_visuals() -> void:
	modulate = Color.WHITE
	if dimmer != null:
		dimmer.color.a = 0.0
	if vignette != null:
		vignette.modulate.a = 0.0
	if radial_glow != null:
		radial_glow.pivot_offset = radial_glow.size * 0.5
		radial_glow.scale = Vector2(0.62, 0.62)
		radial_glow.modulate.a = 0.0
	if light_rays != null:
		light_rays.pivot_offset = light_rays.size * 0.5
		light_rays.scale = Vector2(0.34, 0.34)
		light_rays.rotation = -0.10
		light_rays.modulate.a = 0.0
	if gold_particles != null:
		gold_particles.position = _particles_rest_position
		gold_particles.modulate.a = 0.0
	if victory_emblem != null:
		victory_emblem.pivot_offset = victory_emblem.size * 0.5
		victory_emblem.position = _emblem_rest_position + Vector2(0.0, DROP_START_OFFSET_Y)
		victory_emblem.scale = Vector2.ONE * DROP_INITIAL_SCALE
		victory_emblem.modulate = Color(1.0, 1.0, 1.0, 0.0)
		victory_emblem.visible = victory_emblem.texture != null
	if fallback_glyph != null:
		fallback_glyph.pivot_offset = fallback_glyph.size * 0.5
		fallback_glyph.position = _fallback_rest_position + Vector2(0.0, DROP_START_OFFSET_Y)
		fallback_glyph.scale = Vector2.ONE * DROP_INITIAL_SCALE
		fallback_glyph.modulate = Color(1.0, 1.0, 1.0, 0.0)
		fallback_glyph.visible = victory_emblem == null or victory_emblem.texture == null
	if impact_flash != null:
		impact_flash.pivot_offset = impact_flash.size * 0.5
		impact_flash.scale = Vector2(0.48, 0.48)
		impact_flash.modulate.a = 0.0


func _apply_settled_visuals() -> void:
	dimmer.color.a = dimmer_alpha
	vignette.modulate.a = 1.0
	radial_glow.scale = Vector2(1.12, 1.12)
	radial_glow.modulate.a = 0.58
	light_rays.scale = Vector2.ONE
	light_rays.modulate.a = 0.46
	gold_particles.modulate.a = 0.78
	victory_emblem.position = _emblem_rest_position
	victory_emblem.scale = Vector2.ONE
	victory_emblem.modulate.a = 1.0
	fallback_glyph.position = _fallback_rest_position
	fallback_glyph.scale = Vector2.ONE
	fallback_glyph.modulate.a = 1.0
	impact_flash.modulate.a = 0.0


func _strike_gong() -> void:
	if OS.has_feature("headless") or gong_player == null or gong_player.stream == null:
		return
	gong_player.play()


func _create_gong_stream() -> AudioStreamWAV:
	# 固定的加法合成避免依赖外部音频服务，也绝不触碰对局随机数。
	const SAMPLE_RATE: int = 44100
	const DURATION_SECONDS: float = 1.0
	var sample_count: int = int(SAMPLE_RATE * DURATION_SECONDS)
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	for sample_index: int in range(sample_count):
		var time: float = float(sample_index) / float(SAMPLE_RATE)
		var attack: float = 1.0 - exp(-95.0 * time)
		var body: float = exp(-3.25 * time)
		var low_ring: float = (
			0.55 * sin(TAU * 91.0 * time)
			+ 0.28 * sin(TAU * 146.5 * time + 0.35)
			+ 0.17 * sin(TAU * 232.0 * time + 0.9)
			+ 0.09 * sin(TAU * 317.0 * time + 1.4)
		)
		var mallet: float = exp(-48.0 * time) * (
			0.10 * sin(TAU * 731.0 * time)
			+ 0.07 * sin(TAU * 1187.0 * time + 0.4)
		)
		var tail_fade: float = clampf((DURATION_SECONDS - time) / 0.12, 0.0, 1.0)
		var value: float = clampf((attack * body * low_ring + mallet) * tail_fade, -1.0, 1.0)
		pcm.encode_s16(sample_index * 2, int(value * 24500.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = pcm
	return stream
