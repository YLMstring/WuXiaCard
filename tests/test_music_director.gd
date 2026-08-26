extends SceneTree

const Music = preload("res://scripts/music_director.gd")
const EXPECTED_STORY_TRACK_PATHS: Array[String] = [
	"res://music/funny-village.mp3",
	"res://music/funny-village.mp3",
	"res://music/happy-village.mp3",
	"res://music/happy-village.mp3",
	"res://music/lively-village.mp3",
	"res://music/lively-village.mp3",
	"res://music/monk-village.mp3",
	"res://music/monk-village.mp3",
	"res://music/monk2-village.mp3",
	"res://music/monk2-village.mp3",
	"res://music/peace-village.mp3",
	"res://music/peace-village.mp3",
	"res://music/virtue-village.mp3",
	"res://music/virtue-village.mp3",
	"res://music/exciting-story.mp3",
	"res://music/happy-story.mp3",
	"res://music/sad-story.mp3",
	"res://music/sadder-story.mp3",
]

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var director: Variant = Music.new()
	root.add_child(director)
	await process_frame
	director.debug_set_random_seed(8252026)
	director.debug_set_fade_durations(0.0, 0.0)

	for path: String in director.debug_get_fixed_track_paths():
		_check(ResourceLoader.exists(path), "Fixed music exists: %s" % path)
		_check(ResourceLoader.load(path) is AudioStream, "Fixed music loads: %s" % path)

	var weighted_story_pool: Array[String] = director.debug_get_story_pool_entries()
	_check(
		weighted_story_pool == EXPECTED_STORY_TRACK_PATHS,
		"Story pool uses the exact fixed weighted track list"
	)
	var unique_story_paths: Dictionary = {}
	for path: String in weighted_story_pool:
		unique_story_paths[path] = true
	_check(weighted_story_pool.size() == 18, "Story pool has 18 fixed weighted entries")
	_check(unique_story_paths.size() == 11, "Story pool contains the 11 fixed tracks")
	for path_value: Variant in unique_story_paths.keys():
		var path: String = String(path_value)
		_check(ResourceLoader.exists(path), "Fixed story music exists: %s" % path)
		_check(ResourceLoader.load(path) is AudioStream, "Fixed story music loads: %s" % path)
		var expected_count: int = 2 if "village" in path.get_file().to_lower() else 1
		_check(
			weighted_story_pool.count(path) == expected_count,
			"Story pool applies per-track weight: %s" % path
		)

	director.request_context(Music.CONTEXT_MENU)
	var menu_path: String = director.debug_get_current_track_path()
	var menu_start_count: int = director.debug_get_started_tracks().size()
	_check(menu_path.get_file().begins_with("menu"), "Menu selects a menu track")
	director.request_context(Music.CONTEXT_MENU)
	_check(director.debug_get_current_track_path() == menu_path, "Menu/sect pool continues")
	_check(
		director.debug_get_started_tracks().size() == menu_start_count,
		"Continuing the menu pool does not restart playback"
	)

	director.request_context(Music.CONTEXT_STORY)
	var story_path: String = director.debug_get_current_track_path()
	var story_start_count: int = director.debug_get_started_tracks().size()
	_check(
		"village" in story_path.get_file() or "story" in story_path.get_file(),
		"Deck/reward pool selects a village/story track"
	)
	director.request_context(Music.CONTEXT_STORY)
	_check(director.debug_get_current_track_path() == story_path, "Deck/reward pool continues")
	_check(
		director.debug_get_started_tracks().size() == story_start_count,
		"Continuing the story pool does not restart playback"
	)

	director.request_context(Music.CONTEXT_TERROR)
	_check(
		director.debug_get_current_track_path() == "res://music/terror.mp3",
		"Special reward uses terror"
	)
	director.request_context(Music.CONTEXT_DECK_LOSE)
	_check(
		director.debug_get_current_track_path() == "res://music/lose.mp3",
		"Castration selection uses lose on the next deck entry"
	)
	director.debug_simulate_track_finished()
	_check(director.debug_get_current_context() == Music.CONTEXT_STORY, "Lose expires into story")
	_check(
		"village" in director.debug_get_current_track_path().get_file()
		or "story" in director.debug_get_current_track_path().get_file(),
		"Lose completion starts the normal deck pool"
	)

	director.request_context(Music.CONTEXT_ENDING_LONELY)
	_check(
		director.debug_get_current_track_path() == "res://music/lonely.mp3",
		"Normal ending uses lonely"
	)
	director.request_context(Music.CONTEXT_ENDING_BIXIE)
	_check(
		director.debug_get_current_track_path() == "res://music/bixie.mp3",
		"Castration ending uses bixie"
	)

	director.request_context(Music.CONTEXT_MENU)
	director.debug_clear_transition_trace()
	director.request_context(Music.CONTEXT_BATTLE)
	var transition_trace: Array[String] = director.debug_get_transition_trace()
	_check(transition_trace.size() >= 2, "A music switch records fade and start")
	_check(transition_trace[0].begins_with("fade_out:"), "Old music fades first")
	_check(transition_trace[1].begins_with("start:"), "New music starts after fade")

	director.debug_set_fade_durations(0.02, 0.0)
	director.request_context(Music.CONTEXT_MENU)
	director.request_context(Music.CONTEXT_BATTLE)
	director.request_context(Music.CONTEXT_ENDING_LONELY)
	await create_timer(0.1).timeout
	await process_frame
	_check(
		director.debug_get_current_track_path() == "res://music/lonely.mp3",
		"Rapid requests leave the latest context playing (path=%s trace=%s)"
		% [
			director.debug_get_current_track_path(),
			str(director.debug_get_transition_trace()),
		]
	)

	director.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	await process_frame
	_finish()


func _finish() -> void:
	if _failures == 0:
		print("MUSIC_DIRECTOR_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("MUSIC_DIRECTOR_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
