extends SceneTree

const Rules = preload("res://scripts/deck_rules.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_unique_glyphs()
	_test_exchanges()
	_test_repair()
	_test_side_deck_derivation()
	if _failures == 0:
		print("DECK_RULES_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("DECK_RULES_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _test_unique_glyphs() -> void:
	_check(
		Rules.has_unique_glyphs([
			&"CangSongYingKe2",
			&"LeiZHenJian1",
			&"KuiHua1",
			&"YouFenLaiYi2",
			&"TuNaShu2",
		]),
		"Distinct glyphs are accepted"
	)
	_check(
		not Rules.has_unique_glyphs([
			&"CangSongYingKe2",
			&"CangSongYingKe1",
		]),
		"Different IDs with the same glyph are rejected"
	)


func _test_exchanges() -> void:
	var main: Array = [
		"CangSongYingKe2",
		"LeiZHenJian1",
		"KuiHua1",
		"YouFenLaiYi2",
		"TuNaShu2",
	]
	var library: Array = ["TaiZuChangQuan", "CangSongYingKe1", "YouFenLaiYi3"]
	var normal: Dictionary = Rules.build_player_exchange(main, library, 0, 1)
	_check(bool(normal.get("ok", false)), "Ordinary exchange succeeds")
	_check(normal["main_deck"][1] == "TaiZuChangQuan", "Incoming ordinary card enters target")
	_check(normal["library_slots"][0] == "LeiZHenJian1", "Displaced ordinary card enters source")

	var direct: Dictionary = Rules.build_player_exchange(main, library, 1, 0)
	_check(direct["main_deck"][0] == "CangSongYingKe1", "Namesake can replace its own slot")
	_check(direct["library_slots"][1] == "CangSongYingKe2", "Old version returns to source")

	var rotated: Dictionary = Rules.build_player_exchange(main, library, 1, 2)
	_check(rotated["main_deck"][2] == "CangSongYingKe1", "Incoming namesake enters chosen slot")
	_check(rotated["main_deck"][0] == "KuiHua1", "Chosen-slot card rotates into old namesake slot")
	_check(rotated["library_slots"][1] == "CangSongYingKe2", "Old namesake rotates into library source")
	_check(
		(rotated["changed_deck_indices"] as Array).size() == 2,
		"Three-way rotation reports both changed deck slots"
	)


func _test_repair() -> void:
	var unlocked: Array = [
		"CangSongYingKe1",
		"CangSongYingKe2",
		"LeiZHenJian1",
		"KuiHua1",
		"YouFenLaiYi2",
		"TuNaShu2",
		"TaiZuChangQuan",
	]
	var repaired: Dictionary = Rules.repair_player_placement(
		unlocked,
		[
			"CangSongYingKe1",
			"LeiZHenJian1",
			"CangSongYingKe2",
			"KuiHua1",
			"YouFenLaiYi2",
		],
		["TuNaShu2", "TaiZuChangQuan"],
		5,
		1000
	)
	_check(bool(repaired.get("ok", false)), "Legacy duplicate-glyph deck is repairable")
	var deck: Array = repaired["main_deck"]
	_check(deck[2] == &"CangSongYingKe2", "Highest-tier namesake stays in its original slot")
	_check(deck[0] == &"TuNaShu2", "First stable library filler occupies the vacancy")
	_check(Rules.has_unique_glyphs(deck), "Repaired deck has unique glyphs")
	var library: Array = repaired["library_cards"]
	_check(library.back() == &"CangSongYingKe1", "Removed lower namesake moves to library bottom")


func _test_side_deck_derivation() -> void:
	var main_entries: Array = [
		{"id": &"main_a", "glyph": "甲", "sect": "玄门", "tier": 3},
		{"id": &"main_a_low", "glyph": "甲", "sect": "玄门", "tier": 1},
		{"id": &"wanderer", "glyph": "游", "sect": "江湖", "tier": 5},
	]
	var catalog_entries: Array = [
		{"id": &"a_low", "glyph": "同名", "sect": "玄门", "tier": 1},
		{"id": &"other", "glyph": "乙", "sect": "玄门", "tier": 2},
		{"id": &"a_high", "glyph": "同名", "sect": "玄门", "tier": 3},
		{"id": &"a_tie", "glyph": "同名", "sect": "玄门", "tier": 3},
		{"id": &"too_high", "glyph": "丙", "sect": "玄门", "tier": 4},
		{"id": &"wanderer_copy", "glyph": "游", "sect": "江湖", "tier": 1},
		{"id": &"other_sect", "glyph": "丁", "sect": "别派", "tier": 1},
	]
	var result: Array[StringName] = Rules.build_side_deck_from_entries(
		main_entries,
		catalog_entries
	)
	_check(result == [&"other", &"a_high"], "Side deck keeps eligible catalog order and best glyph version")
	_check(&"a_tie" not in result, "Equal-tier tie keeps the earlier catalog card")
	_check(&"wanderer_copy" not in result, "江湖 main cards contribute no side cards")
	_check(&"too_high" not in result, "Cards above the sect threshold are excluded")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
