extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Action = preload("res://scripts/duel_action.gd")
const ProfileStore = preload("res://scripts/deck_profile_store.gd")
const Rules = preload("res://scripts/duel_rules.gd")

const TEST_PROFILE_PATH: String = "user://youfen_integration_profile.json"

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_profile()
	var store: RefCounted = ProfileStore.new(TEST_PROFILE_PATH)
	var profile: Dictionary = store.create_default_profile()
	var library_index: int = (profile.get("library_slots", []) as Array).find("YouFenLaiYi4")
	_check(library_index >= 0, "Default test profile exposes tier-four 有凤来仪 in its library")
	var exchange_result: Dictionary = store.exchange_and_save(profile, library_index, 3)
	_check(bool(exchange_result.get("ok", false)), "Test profile places tier-four 有凤来仪 in the main deck")

	var duel: Node = DUEL_SCENE.instantiate()
	duel.set("deck_profile_path", TEST_PROFILE_PATH)
	duel.set("opponent_hand_shuffle_seed", -1)
	root.add_child(duel)
	await process_frame
	await process_frame
	duel.debug_set_fast_mode(true)

	var placed_source: bool = await duel.debug_commit_move(
		Rules.PLAYER_OWNER,
		3,
		4,
		false
	)
	_check(placed_source, "Tier-four 有凤来仪 enters through the production play path")
	var board_views: Array = duel.get("board_cards") as Array
	var source_view: Control = board_views[4] as Control
	var source_instance_id: StringName = duel.debug_get_board_card_instance_id(4)

	var placed_target: bool = await duel.debug_commit_move(
		Rules.OPPONENT_OWNER,
		1,
		5,
		false
	)
	_check(placed_target, "Enemy target enters adjacent through the production play path")
	board_views = duel.get("board_cards") as Array
	var target_view: Control = board_views[5] as Control
	var target_instance_id: StringName = duel.debug_get_board_card_instance_id(5)
	source_view.call("_try_begin_drag", source_view.get_global_rect().get_center(), -1)
	var drag_action: Action = duel.call("_make_drag_action", source_view, 5) as Action
	_check(
		drag_action != null and drag_action.activation_index == 2,
		"Board drag selects the first catalog-ordered legal activation for its target"
	)
	duel.call("_return_card_home", source_view)
	duel.call("_clear_drag_context")
	var trace_start: int = duel.debug_get_presentation_trace().size()
	var attack_start: int = duel.debug_get_attack_vfx_trace().size()

	var activated: bool = await duel.debug_commit_activate(
		Rules.PLAYER_OWNER,
		4,
		5,
		false,
		2
	)
	_check(activated, "Controller executes the indexed enemy-swap activation")
	board_views = duel.get("board_cards") as Array
	_check(
		board_views[5] == source_view
		and duel.debug_get_board_card_instance_id(5) == source_instance_id,
		"Controller preserves A's view and places it in B's original square"
	)
	_check(
		board_views[4] == target_view
		and duel.debug_get_board_card_instance_id(4) == target_instance_id,
		"Controller preserves B's view and places it in A's original square"
	)
	_check(
		is_instance_valid(source_view) and is_instance_valid(target_view),
		"Swap creates no disappear or reconstruction presentation"
	)
	var source_ki: int = int((source_view.get("card_data") as Dictionary).get("ki", -1))
	_check(source_ki == 2, "Swapping spends one ki and synchronizes A's existing view")

	var trace: Array[StringName] = duel.debug_get_presentation_trace()
	var swap_trace: Array[StringName] = trace.slice(trace_start)
	_check(
		swap_trace == [
			&"ability_activated",
			&"ki_changed",
			&"card_moved",
			&"card_moved",
			&"attack_started",
			&"card_flipped",
		],
		"Presentation observes both ordered moves before the standard attack"
	)
	var attack_trace: Array[Dictionary] = duel.debug_get_attack_vfx_trace()
	_check(
		attack_trace.size() == attack_start + 1
		and StringName(attack_trace[-1].get("source_instance_id", &"")) == source_instance_id
		and StringName(attack_trace[-1].get("target_instance_id", &"")) == target_instance_id,
		"Attack VFX originates from A and targets the displaced enemy"
	)

	duel.queue_free()
	await process_frame
	_cleanup_profile()
	if _failures == 0:
		print("YOUFEN_INTEGRATION_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("YOUFEN_INTEGRATION_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _cleanup_profile() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = TEST_PROFILE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
