class_name VictoryVfx
extends Control

signal settled
signal finished

const SMASH_INITIAL_SCALE: float = 2.0
const SMASH_IMPACT_SCALE: float = 0.90
const SMASH_LINEAR_WEIGHT: float = 0.22
const SMASH_CUBIC_WEIGHT: float = 0.78
const EARLY_REVEAL_DURATION: float = 0.12
const IMPACT_HOLD_DURATION: float = 0.03
const REBOUND_SCALE: float = 1.04
const IMPACT_FLASH_ALPHA: float = 0.78

@export_range(0.0, 1.0, 0.01) var dimmer_alpha: float = 0.42
@export_range(0.0, 2.0, 0.01) var entry_duration: float = 0.25
@export_range(0.0, 2.0, 0.01) var impact_duration: float = 0.45
@export_range(0.0, 2.0, 0.01) var settle_duration: float = 0.40
@export_range(0.0, 0.5, 0.01) var rebound_duration: float = 0.12
@export_range(0.0, 0.5, 0.01) var recovery_duration: float = 0.14
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
var _smash_animation: Tween = null
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
	if gong_player != null:
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
	_start_smash_motion()

	var early_reveal_duration: float = minf(entry_duration, EARLY_REVEAL_DURATION)
	var reveal_finish_duration: float = maxf(entry_duration - early_reveal_duration, 0.0)
	_animation = create_tween()
	_animation.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_animation.tween_property(dimmer, "color:a", dimmer_alpha * 0.72, early_reveal_duration)
	_animation.parallel().tween_property(vignette, "modulate:a", 0.65, early_reveal_duration)
	_animation.parallel().tween_property(victory_emblem, "modulate:a", 0.70, early_reveal_duration)
	_animation.parallel().tween_property(fallback_glyph, "modulate:a", 0.70, early_reveal_duration)
	_animation.parallel().tween_property(radial_glow, "modulate:a", 0.10, early_reveal_duration)

	_animation.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_animation.tween_property(dimmer, "color:a", dimmer_alpha, reveal_finish_duration)
	_animation.parallel().tween_property(vignette, "modulate:a", 1.0, reveal_finish_duration)
	_animation.parallel().tween_property(victory_emblem, "modulate:a", 1.0, reveal_finish_duration)
	_animation.parallel().tween_property(fallback_glyph, "modulate:a", 1.0, reveal_finish_duration)
	_animation.parallel().tween_property(radial_glow, "modulate:a", 0.20, reveal_finish_duration)

	_animation.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_animation.tween_property(radial_glow, "modulate:a", 0.55, impact_duration)
	_animation.parallel().tween_property(radial_glow, "scale", Vector2(1.05, 1.05), impact_duration)
	_animation.parallel().tween_property(light_rays, "modulate:a", 0.50, impact_duration)
	_animation.parallel().tween_property(light_rays, "scale", Vector2(0.92, 0.92), impact_duration)
	_animation.parallel().tween_property(gold_particles, "modulate:a", 0.35, impact_duration)
	_animation.tween_callback(_trigger_impact)
	_animation.tween_interval(IMPACT_HOLD_DURATION)

	_animation.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_animation.tween_property(victory_emblem, "scale", Vector2.ONE * REBOUND_SCALE, rebound_duration)
	_animation.parallel().tween_property(fallback_glyph, "scale", Vector2.ONE * REBOUND_SCALE, rebound_duration)
	_animation.parallel().tween_property(impact_flash, "modulate:a", 0.0, minf(rebound_duration, 0.10))
	_animation.parallel().tween_property(radial_glow, "modulate:a", 0.65, rebound_duration)
	_animation.parallel().tween_property(light_rays, "modulate:a", 0.50, rebound_duration)

	_animation.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_animation.tween_property(victory_emblem, "scale", Vector2.ONE, recovery_duration)
	_animation.parallel().tween_property(fallback_glyph, "scale", Vector2.ONE, recovery_duration)
	_animation.parallel().tween_property(radial_glow, "modulate:a", 0.58, recovery_duration)
	_animation.parallel().tween_property(light_rays, "modulate:a", 0.46, recovery_duration)
	_animation.tween_interval(_settle_hold_duration())
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
	_is_playing = false
	_is_settled = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reset_visuals()


func is_playing() -> bool:
	return _is_playing


func debug_get_play_count() -> int:
	return _play_count


func debug_get_smash_scale(elapsed_seconds: float) -> float:
	return lerpf(
		SMASH_INITIAL_SCALE,
		SMASH_IMPACT_SCALE,
		_smash_curve_progress(elapsed_seconds / _smash_duration())
	)


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
	if _smash_animation != null and _smash_animation.is_valid():
		_smash_animation.kill()
	_smash_animation = null


func _smash_duration() -> float:
	return maxf(entry_duration + impact_duration, 0.001)


func _smash_curve_progress(normalized_time: float) -> float:
	var time: float = clampf(normalized_time, 0.0, 1.0)
	return SMASH_LINEAR_WEIGHT * time + SMASH_CUBIC_WEIGHT * time * time * time


func _settle_hold_duration() -> float:
	return maxf(
		settle_duration - IMPACT_HOLD_DURATION - rebound_duration - recovery_duration,
		0.0
	)


func _set_smash_progress(progress: float) -> void:
	var smash_scale: float = lerpf(
		SMASH_INITIAL_SCALE,
		SMASH_IMPACT_SCALE,
		_smash_curve_progress(progress)
	)
	if victory_emblem != null:
		victory_emblem.scale = Vector2.ONE * smash_scale
	if fallback_glyph != null:
		fallback_glyph.scale = Vector2.ONE * smash_scale


func _start_smash_motion() -> void:
	_set_smash_progress(0.0)
	_smash_animation = create_tween()
	_smash_animation.set_trans(Tween.TRANS_LINEAR)
	_smash_animation.tween_method(_set_smash_progress, 0.0, 1.0, _smash_duration())


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
		victory_emblem.position = _emblem_rest_position
		victory_emblem.scale = Vector2.ONE * SMASH_INITIAL_SCALE
		victory_emblem.modulate = Color(1.0, 1.0, 1.0, 0.0)
		victory_emblem.visible = victory_emblem.texture != null
	if fallback_glyph != null:
		fallback_glyph.pivot_offset = fallback_glyph.size * 0.5
		fallback_glyph.position = _fallback_rest_position
		fallback_glyph.scale = Vector2.ONE * SMASH_INITIAL_SCALE
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


func _trigger_impact() -> void:
	impact_flash.modulate.a = IMPACT_FLASH_ALPHA
	impact_flash.scale = Vector2.ONE
	radial_glow.modulate.a = 0.92
	radial_glow.scale = Vector2(1.12, 1.12)
	light_rays.modulate.a = 0.78
	light_rays.scale = Vector2.ONE
	gold_particles.modulate.a = 0.78
	_strike_gong()


func _strike_gong() -> void:
	if OS.has_feature("headless") or gong_player == null or gong_player.stream == null:
		return
	_spawn_gong_one_shot()


func _spawn_gong_one_shot() -> AudioStreamPlayer:
	if gong_player == null or gong_player.stream == null or get_tree() == null:
		return null
	var one_shot := AudioStreamPlayer.new()
	one_shot.name = "VictoryGongOneShot"
	one_shot.stream = gong_player.stream
	one_shot.volume_db = gong_player.volume_db
	one_shot.bus = gong_player.bus
	one_shot.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(one_shot, true)
	one_shot.finished.connect(one_shot.queue_free, CONNECT_ONE_SHOT)
	one_shot.play()
	return one_shot
