class_name DifficultyRules
extends RefCounted

const MIN_DIFFICULTY: int = 0
const MAX_DIFFICULTY: int = 9

const EFFECT_TEXTS: Array[String] = [
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


static func normalize(difficulty: int) -> int:
	return clampi(difficulty, MIN_DIFFICULTY, MAX_DIFFICULTY)


static func get_effect_text(difficulty: int) -> String:
	return EFFECT_TEXTS[normalize(difficulty)]


static func get_victories_required(difficulty: int) -> int:
	var normalized: int = normalize(difficulty)
	if normalized <= 0:
		return 13
	if normalized == 1:
		return 14
	return 15


static func get_later_player_bagua_count(difficulty: int) -> int:
	var normalized: int = normalize(difficulty)
	if normalized >= 6:
		return 0
	if normalized >= 3:
		return 1
	return 2


static func get_later_enemy_bagua_power(difficulty: int) -> int:
	var normalized: int = normalize(difficulty)
	if normalized >= 7:
		return 4
	if normalized >= 4:
		return 2
	return -1


static func player_must_be_strictly_lower_to_go_first(difficulty: int) -> bool:
	return normalize(difficulty) >= 5


static func enemy_draws_on_first_one_card_hand(difficulty: int) -> bool:
	return normalize(difficulty) >= 8


static func buffs_random_enemy_opening_hand_card(difficulty: int) -> bool:
	return normalize(difficulty) >= 9
