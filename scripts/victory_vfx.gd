class_name VictoryVfx
extends Control

signal finished

@export_range(0.0, 1.0, 0.01) var dimmer_alpha: float = 0.30
@export_range(0.0, 2.0, 0.01) var impact_duration: float = 0.22
@export_range(0.0, 2.0, 0.01) var settle_duration: float = 0.12
@export_range(0.0, 2.0, 0.01) var hold_duration: float = 0.56
@export_range(0.0, 2.0, 0.01) var fade_duration: float = 0.35
@export_range(-80.0, 6.0, 0.5) var gong_volume_db: float = -5.0

@onready var dimmer: ColorRect = $Dimmer
@onready var ink_burst: TextureRect = $InkBurst
@onready var victory_glyph: Label = $VictoryGlyph
@onready var gong_player: AudioStreamPlayer = $GongPlayer

var _animation: Tween = null
var _is_playing: bool = false
var _play_count: int = 0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_play_count += 1
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_strike_gong()

	_animation = create_tween()
	_animation.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_animation.tween_property(dimmer, "color:a", dimmer_alpha, impact_duration)
	_animation.parallel().tween_property(ink_burst, "modulate:a", 0.88, impact_duration)
	_animation.parallel().tween_property(ink_burst, "scale", Vector2(1.05, 1.05), impact_duration)
	_animation.parallel().tween_property(victory_glyph, "modulate:a", 1.0, impact_duration)
	_animation.parallel().tween_property(victory_glyph, "scale", Vector2(0.92, 0.92), impact_duration)
	_animation.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_animation.tween_property(ink_burst, "scale", Vector2.ONE, settle_duration)
	_animation.parallel().tween_property(victory_glyph, "scale", Vector2.ONE, settle_duration)
	_animation.tween_interval(hold_duration)
	_animation.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_animation.tween_property(self, "modulate:a", 0.0, fade_duration)
	_animation.tween_callback(_complete)


func complete_immediately() -> void:
	if not _is_playing:
		return
	_kill_animation()
	_complete()


func cancel() -> void:
	_kill_animation()
	if gong_player != null:
		gong_player.stop()
	_is_playing = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reset_visuals()


func is_playing() -> bool:
	return _is_playing


func debug_get_play_count() -> int:
	return _play_count


func _complete() -> void:
	if not _is_playing:
		return
	_is_playing = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reset_visuals()
	finished.emit()


func _kill_animation() -> void:
	if _animation != null and _animation.is_valid():
		_animation.kill()
	_animation = null


func _reset_visuals() -> void:
	modulate = Color.WHITE
	if dimmer != null:
		dimmer.color.a = 0.0
	if ink_burst != null:
		ink_burst.pivot_offset = ink_burst.size * 0.5
		ink_burst.scale = Vector2(0.25, 0.25)
		ink_burst.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if victory_glyph != null:
		victory_glyph.pivot_offset = victory_glyph.size * 0.5
		victory_glyph.scale = Vector2(1.8, 1.8)
		victory_glyph.modulate = Color(1.0, 1.0, 1.0, 0.0)


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
