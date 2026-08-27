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
	_finish()


func _test_normalization_and_text() -> void:
	_check(Difficulty.normalize(-1) == 0, "Difficulty clamps below zero")
	_check(Difficulty.normalize(10) == 9, "Difficulty clamps above nine")
	var expected_texts: Array[String] = [
		"",
		"可挑战一派宗师",
		"可挑战武林神话",
		"后行动时，友方只占据一个八卦方位",
		"先行动时，敌方占据的八卦方位点数变为二",
		"卡组总品阶低于对手时方可选择先攻",
		"后行动时，友方不占据八卦方位",
		"先行动时，敌方占据的八卦方位点数变为四",
		"敌方手牌数首次变为一时，其抽一张牌",
		"对局开始时，随机一张敌方手牌点数加一",
	]
	for difficulty: int in range(expected_texts.size()):
		_check(
			Difficulty.get_effect_text(difficulty) == expected_texts[difficulty],
			"Difficulty %d exposes the exact player-facing effect text" % difficulty
		)


func _test_progression_thresholds() -> void:
	_check(Difficulty.get_victories_required(0) == 13, "Difficulty zero ends after thirteen enemies")
	_check(Difficulty.get_victories_required(1) == 14, "Difficulty one ends after fourteen enemies")
	for difficulty: int in range(2, 10):
		_check(
			Difficulty.get_victories_required(difficulty) == 15,
			"Difficulty %d ends after fifteen enemies" % difficulty
		)


func _test_cumulative_bagua_rules() -> void:
	for difficulty: int in range(0, 3):
		_check(
			Difficulty.get_later_player_bagua_count(difficulty) == 2,
			"Difficulty %d gives a later player two Bagua" % difficulty
		)
	for difficulty: int in range(3, 6):
		_check(
			Difficulty.get_later_player_bagua_count(difficulty) == 1,
			"Difficulty %d gives a later player one Bagua" % difficulty
		)
	for difficulty: int in range(6, 10):
		_check(
			Difficulty.get_later_player_bagua_count(difficulty) == 0,
			"Difficulty %d gives a later player no Bagua" % difficulty
		)
	_check(Difficulty.get_later_enemy_bagua_power(3) == -1, "Difficulty three keeps default Bagua powers")
	_check(Difficulty.get_later_enemy_bagua_power(4) == 2, "Difficulty four sets enemy Bagua powers to two")
	_check(Difficulty.get_later_enemy_bagua_power(6) == 2, "Difficulty six retains the first enemy Bagua override")
	_check(Difficulty.get_later_enemy_bagua_power(7) == 4, "Difficulty seven sets enemy Bagua powers to four")
	_check(Difficulty.get_later_enemy_bagua_power(9) == 4, "Difficulty nine retains the strongest Bagua override")


func _test_remaining_thresholds() -> void:
	_check(not Difficulty.player_must_be_strictly_lower_to_go_first(4), "Difficulty four permits equal tiers")
	_check(Difficulty.player_must_be_strictly_lower_to_go_first(5), "Difficulty five requires lower tiers")
	_check(not Difficulty.enemy_draws_on_first_one_card_hand(7), "Difficulty seven has no one-card draw")
	_check(Difficulty.enemy_draws_on_first_one_card_hand(8), "Difficulty eight enables the one-card draw")
	_check(not Difficulty.buffs_random_enemy_opening_hand_card(8), "Difficulty eight has no opening hand buff")
	_check(Difficulty.buffs_random_enemy_opening_hand_card(9), "Difficulty nine enables the opening hand buff")


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
