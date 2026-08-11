extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const Store = preload("res://scripts/deck_profile_store.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Rules = preload("res://scripts/duel_rules.gd")

const SAVE_PATH: String = "user://card_mastery_test.json"

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var store: RefCounted = Store.new(SAVE_PATH)
	var profile: Dictionary = store.create_default_profile()
	_check(store.save_profile(profile), "Mastery duel fixture saves")

	var duel: DuelController = DUEL_SCENE.instantiate() as DuelController
	duel.deck_profile_path = SAVE_PATH
	duel.testing_mode = true
	duel.player_hand_shuffle_seed = -1
	duel.opponent_hand_shuffle_seed = -1
	root.add_child(duel)
	await process_frame
	await process_frame
	duel.debug_set_fast_mode(true)

	var first_player_card := (
		duel.get_node("DuelCanvas/PlayerHand/Slot0").get_child(0) as CardView
	)
	var first_card_id := StringName(first_player_card.card_data.get("card_id", &""))
	_check(duel.get_mastery_candidate_ids().is_empty(), "Duel begins with no mastery candidates")
	_check(
		not await duel.debug_commit_move(Rules.PLAYER_OWNER, 0, -1, false),
		"Illegal player play is rejected"
	)
	_check(
		duel.get_mastery_candidate_ids().is_empty(),
		"Illegal player play creates no mastery candidate"
	)
	_check(
		await duel.debug_commit_move(Rules.PLAYER_OWNER, 0, 0, false),
		"Legal player hand play commits"
	)
	_check(
		duel.get_mastery_candidate_ids() == [first_card_id],
		"Legal play records the exact main-deck card ID"
	)

	var candidates_before_opponent: Array[StringName] = duel.get_mastery_candidate_ids()
	_check(
		await duel.debug_commit_move(Rules.OPPONENT_OWNER, 0, 8, false),
		"Opponent hand play commits in testing mode"
	)
	_check(
		duel.get_mastery_candidate_ids() == candidates_before_opponent,
		"Opponent hand play creates no player mastery candidate"
	)

	duel.call("_record_mastery_candidate", first_card_id)
	_check(
		duel.get_mastery_candidate_ids() == [first_card_id],
		"Repeated qualifying copies deduplicate by exact ID"
	)
	var second_main_id := StringName(String(profile["main_deck"][1]))
	duel.call("_record_mastery_candidate", second_main_id)
	_check(
		duel.get_mastery_candidate_ids() == [first_card_id, second_main_id],
		"A different eligible main-deck ID qualifies independently of runtime instance"
	)

	var same_glyph_other_id: StringName = _find_same_glyph_other_id(first_card_id)
	_check(same_glyph_other_id != &"", "Mastery fixture finds a same-glyph alternate ID")
	duel.call("_record_mastery_candidate", same_glyph_other_id)
	_check(
		duel.get_mastery_candidate_ids() == [first_card_id, second_main_id],
		"A same-glyph different-ID card does not qualify"
	)

	duel.queue_free()
	await process_frame
	_cleanup()
	_finish()


func _find_same_glyph_other_id(card_id: StringName) -> StringName:
	var glyph: String = String(Catalog.get_definition(card_id).get("glyph", ""))
	for candidate_id: StringName in Catalog.get_all_card_ids():
		if (
			candidate_id != card_id
			and String(Catalog.get_definition(candidate_id).get("glyph", "")) == glyph
		):
			return candidate_id
	return &""


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	if _failures == 0:
		print("CARD_MASTERY_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("CARD_MASTERY_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
