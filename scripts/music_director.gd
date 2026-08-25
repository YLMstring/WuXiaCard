class_name MusicDirector
extends Node

signal track_started(path: String)

const CONTEXT_MENU: StringName = &"menu"
const CONTEXT_STORY: StringName = &"story"
const CONTEXT_BATTLE: StringName = &"battle"
const CONTEXT_TERROR: StringName = &"terror"
const CONTEXT_DECK_LOSE: StringName = &"deck_lose"
const CONTEXT_ENDING_LONELY: StringName = &"ending_lonely"
const CONTEXT_ENDING_BIXIE: StringName = &"ending_bixie"

const MUSIC_DIRECTORY: String = "res://music"
const AUDIO_EXTENSIONS: Array[String] = ["mp3", "ogg", "wav"]
const MENU_TRACK_PATHS: Array[String] = [
	"res://music/menu1.mp3",
	"res://music/menu2.mp3",
	"res://music/menu3.mp3",
]
const BATTLE_TRACK_PATHS: Array[String] = [
	"res://music/battle1.mp3",
	"res://music/battle2.mp3",
	"res://music/battle3.mp3",
	"res://music/battle4.mp3",
	"res://music/battle5.mp3",
	"res://music/battle6.mp3",
]
const TERROR_TRACK_PATH: String = "res://music/terror.mp3"
const LOSE_TRACK_PATH: String = "res://music/lose.mp3"
const LONELY_TRACK_PATH: String = "res://music/lonely.mp3"
const BIXIE_TRACK_PATH: String = "res://music/bixie.mp3"

@export_range(0.0, 5.0, 0.01) var fade_out_seconds: float = 0.6
@export_range(0.0, 5.0, 0.01) var fade_in_seconds: float = 0.08
@export_range(-80.0, 12.0, 0.1) var playback_volume_db: float = 0.0
@export_range(-80.0, 0.0, 0.1) var silent_volume_db: float = -60.0

var _player: AudioStreamPlayer = null
var _random := RandomNumberGenerator.new()
var _story_pool_entries: Array[String] = []
var _current_context: StringName = &""
var _current_track_path: String = ""
var _request_generation: int = 0
var _transition_tween: Tween = null
var _started_tracks: Array[String] = []
var _transition_trace: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_random.randomize()
	_story_pool_entries = _scan_story_pool()
	_ensure_player()


func _exit_tree() -> void:
	_request_generation += 1
	_cancel_transition()
	if _player == null or not is_instance_valid(_player):
		return
	_player.stop()
	_player.stream = null
	_current_track_path = ""


func request_context(context: StringName) -> void:
	_ensure_player()
	_request_generation += 1
	var generation: int = _request_generation
	_current_context = context
	_cancel_transition()
	var entries: Array[String] = _get_context_entries(context)
	if _player.playing and _current_track_path in entries:
		_restore_playback_volume()
		_transition_trace.append("continue:%s" % _current_track_path)
		return
	var target_path: String = _choose_loadable_path(entries)
	if target_path.is_empty():
		_stop_playback()
		return
	_switch_to_track(generation, target_path)


func debug_get_current_context() -> StringName:
	return _current_context


func debug_get_current_track_path() -> String:
	return _current_track_path


func debug_get_story_pool_entries() -> Array[String]:
	return _story_pool_entries.duplicate()


func debug_get_fixed_track_paths() -> Array[String]:
	var paths: Array[String] = []
	paths.append_array(MENU_TRACK_PATHS)
	paths.append_array(BATTLE_TRACK_PATHS)
	paths.append(TERROR_TRACK_PATH)
	paths.append(LOSE_TRACK_PATH)
	paths.append(LONELY_TRACK_PATH)
	paths.append(BIXIE_TRACK_PATH)
	return paths


func debug_get_started_tracks() -> Array[String]:
	return _started_tracks.duplicate()


func debug_get_transition_trace() -> Array[String]:
	return _transition_trace.duplicate()


func debug_clear_transition_trace() -> void:
	_transition_trace.clear()


func debug_set_random_seed(seed_value: int) -> void:
	_random.seed = seed_value


func debug_set_fade_durations(out_seconds: float, in_seconds: float) -> void:
	fade_out_seconds = maxf(out_seconds, 0.0)
	fade_in_seconds = maxf(in_seconds, 0.0)


func debug_simulate_track_finished() -> void:
	_ensure_player()
	_player.stop()
	_on_track_finished()


func debug_get_audio_player() -> AudioStreamPlayer:
	_ensure_player()
	return _player


func _ensure_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	_player = AudioStreamPlayer.new()
	_player.name = "BackgroundMusicPlayer"
	_player.volume_db = playback_volume_db
	add_child(_player)
	_player.finished.connect(_on_track_finished)


func _scan_story_pool() -> Array[String]:
	var weighted_entries: Array[String] = []
	var filenames: PackedStringArray = DirAccess.get_files_at(MUSIC_DIRECTORY)
	filenames.sort()
	for filename: String in filenames:
		var lowercase_name: String = filename.to_lower()
		if lowercase_name.get_extension() not in AUDIO_EXTENSIONS:
			continue
		var weight: int = 0
		if "village" in lowercase_name:
			weight = 2
		elif "story" in lowercase_name:
			weight = 1
		if weight == 0:
			continue
		var path: String = MUSIC_DIRECTORY.path_join(filename)
		if not ResourceLoader.exists(path):
			push_warning("Music track is unavailable: %s" % path)
			continue
		for copy_index: int in range(weight):
			weighted_entries.append(path)
	return weighted_entries


func _get_context_entries(context: StringName) -> Array[String]:
	var entries: Array[String] = []
	match context:
		CONTEXT_MENU:
			entries.append_array(MENU_TRACK_PATHS)
		CONTEXT_STORY:
			entries.append_array(_story_pool_entries)
		CONTEXT_BATTLE:
			entries.append_array(BATTLE_TRACK_PATHS)
		CONTEXT_TERROR:
			entries.append(TERROR_TRACK_PATH)
		CONTEXT_DECK_LOSE:
			entries.append(LOSE_TRACK_PATH)
		CONTEXT_ENDING_LONELY:
			entries.append(LONELY_TRACK_PATH)
		CONTEXT_ENDING_BIXIE:
			entries.append(BIXIE_TRACK_PATH)
		_:
			push_warning("Unknown music context: %s" % String(context))
	return entries


func _choose_loadable_path(weighted_entries: Array[String]) -> String:
	var candidates: Array[String] = weighted_entries.duplicate()
	while not candidates.is_empty():
		var index: int = _random.randi_range(0, candidates.size() - 1)
		var path: String = candidates[index]
		var stream: Resource = ResourceLoader.load(path)
		if stream is AudioStream:
			return path
		push_warning("Music track could not be loaded: %s" % path)
		candidates = candidates.filter(func(candidate: String) -> bool: return candidate != path)
	return ""


func _switch_to_track(generation: int, target_path: String) -> void:
	if _player.playing and not _current_track_path.is_empty():
		_transition_trace.append("fade_out:%s" % _current_track_path)
		if fade_out_seconds > 0.0:
			_transition_tween = create_tween()
			_transition_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			_transition_tween.tween_property(
				_player,
				"volume_db",
				silent_volume_db,
				fade_out_seconds
			)
			_transition_tween.tween_callback(
				_complete_switch.bind(generation, target_path)
			)
			return
		_player.volume_db = silent_volume_db
	_complete_switch(generation, target_path)


func _complete_switch(generation: int, target_path: String) -> void:
	if generation != _request_generation:
		return
	_transition_tween = null
	_player.stop()
	_current_track_path = ""
	var stream: Resource = ResourceLoader.load(target_path)
	if not stream is AudioStream:
		push_warning("Music track could not be loaded: %s" % target_path)
		_player.stream = null
		return
	_player.stream = stream as AudioStream
	_player.volume_db = silent_volume_db if fade_in_seconds > 0.0 else playback_volume_db
	_player.play()
	_current_track_path = target_path
	_started_tracks.append(target_path)
	_transition_trace.append("start:%s" % target_path)
	track_started.emit(target_path)
	if fade_in_seconds <= 0.0:
		return
	_transition_tween = create_tween()
	_transition_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_transition_tween.tween_property(
		_player,
		"volume_db",
		playback_volume_db,
		fade_in_seconds
	)


func _cancel_transition() -> void:
	if _transition_tween == null or not _transition_tween.is_valid():
		_transition_tween = null
		return
	_transition_tween.kill()
	_transition_tween = null


func _restore_playback_volume() -> void:
	if fade_in_seconds <= 0.0 or _player.volume_db >= playback_volume_db:
		_player.volume_db = playback_volume_db
		return
	_transition_tween = create_tween()
	_transition_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_transition_tween.tween_property(
		_player,
		"volume_db",
		playback_volume_db,
		fade_in_seconds
	)


func _stop_playback() -> void:
	_cancel_transition()
	_player.stop()
	_player.stream = null
	_current_track_path = ""


func _on_track_finished() -> void:
	if _current_context == CONTEXT_DECK_LOSE:
		request_context(CONTEXT_STORY)
		return
	request_context(_current_context)
