extends SceneTree

const Difficulty = preload("res://scripts/difficulty_rules.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_normalization_and_text()
	_test_progression_thresholds()
	_test_cumulative_bagua_rules()
	_test_remaining_thresholds()
	_test_enemy_search_depth_limits()
	_finish()


func _test_normalization_and_text() -> void:
	_check(Difficulty.normalize(-1) == 0, "Difficulty clamps below zero")
	_check(Difficulty.normalize(11) == 10, "Difficulty clamps above ten")
	var expected_texts: Array[String] = [
		"",
		"可挑战前辈名宿，敌方思考加深",
		"可挑战一派宗师，敌方思考加深",
		"可挑战武林神话，敌方思考加深",
		"后行动时，友方只占据一个八卦方位",
		"先行动时，敌方占据的八卦方位点数变为二",
		"战败后获得的卡牌品阶降低",
		"后行动时，友方不占据八卦方位",
		"先行动时，敌方占据的八卦方位点数变为四",
		"无法看到未揭示的卡牌的点数",
		"敌方思考时间加倍",
	]
	for difficulty: int in range(expected_texts.size()):
		_check(
			Difficulty.get_effect_text(difficulty) == expected_texts[difficulty],
			"Difficulty %d exposes the exact player-facing effect text" % difficulty
		)


func _test_progression_thresholds() -> void:
	_check(Difficulty.get_victories_required(0) == 12, "Difficulty zero ends after twelve enemies")
	_check(Difficulty.get_victories_required(1) == 13, "Difficulty one ends after thirteen enemies")
	_check(Difficulty.get_victories_required(2) == 14, "Difficulty two ends after fourteen enemies")
	for difficulty: int in range(3, 11):
		_check(
			Difficulty.get_victories_required(difficulty) == 15,
			"Difficulty %d ends after fifteen enemies" % difficulty
		)


func _test_cumulative_bagua_rules() -> void:
	for difficulty: int in range(0, 4):
		_check(
			Difficulty.get_later_player_bagua_count(difficulty) == 2,
			"Difficulty %d gives a later player two Bagua" % difficulty
		)
	for difficulty: int in range(4, 7):
		_check(
			Difficulty.get_later_player_bagua_count(difficulty) == 1,
			"Difficulty %d gives a later player one Bagua" % difficulty
		)
	for difficulty: int in range(7, 11):
		_check(
			Difficulty.get_later_player_bagua_count(difficulty) == 0,
			"Difficulty %d gives a later player no Bagua" % difficulty
		)
	_check(Difficulty.get_later_enemy_bagua_power(4) == -1, "Difficulty four keeps default Bagua powers")
	_check(Difficulty.get_later_enemy_bagua_power(5) == 2, "Difficulty five sets enemy Bagua powers to two")
	_check(Difficulty.get_later_enemy_bagua_power(7) == 2, "Difficulty seven retains the first enemy Bagua override")
	_check(Difficulty.get_later_enemy_bagua_power(8) == 4, "Difficulty eight sets enemy Bagua powers to four")
	_check(Difficulty.get_later_enemy_bagua_power(10) == 4, "Difficulty ten retains the strongest Bagua override")


func _test_remaining_thresholds() -> void:
	_check(Difficulty.get_max_defeat_reward_tier(5, 3) == 3, "Difficulty five keeps current-tier defeat rewards")
	_check(Difficulty.get_max_defeat_reward_tier(6, 3) == 2, "Difficulty six lowers the defeat reward ceiling")
	_check(Difficulty.get_max_defeat_reward_tier(10, 1) == 1, "Tier one remains the defeat reward floor")
	_check(not Difficulty.hides_unrevealed_card_powers(8), "Difficulty eight shows unrevealed powers")
	_check(Difficulty.hides_unrevealed_card_powers(9), "Difficulty nine hides unrevealed powers")
	_check(is_equal_approx(Difficulty.enemy_search_time_multiplier(9), 1.0), "Difficulty nine keeps normal search time")
	_check(is_equal_approx(Difficulty.enemy_search_time_multiplier(10), 2.0), "Difficulty ten doubles search time")


func _test_enemy_search_depth_limits() -> void:
	_check(Difficulty.get_enemy_search_max_depth(0) == 1, "Difficulty zero caps enemy search at depth one")
	_check(Difficulty.get_enemy_search_max_depth(1) == 2, "Difficulty one caps enemy search at depth two")
	_check(Difficulty.get_enemy_search_max_depth(2) == 3, "Difficulty two caps enemy search at depth three")
	for difficulty: int in range(3, 11):
		_check(
			Difficulty.get_enemy_search_max_depth(difficulty) == 0,
			"Difficulty %d leaves enemy search depth unlimited" % difficulty
		)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)


func _finish() -> void:
	if _failures == 0:
		print("DIFFICULTY_RULES_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"DIFFICULTY_RULES_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)
