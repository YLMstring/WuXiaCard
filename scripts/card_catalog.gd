class_name CardCatalog
extends RefCounted

const ACTIVATION_DRAG_TO_TARGET: StringName = &"drag_to_target"
const TARGET_ADJACENT_EMPTY_BOARD: StringName = &"adjacent_empty_board"
const TARGET_ADJACENT_ALLY_BOARD: StringName = &"adjacent_ally_board"
const TARGET_ADJACENT_ENEMY_BOARD: StringName = &"adjacent_enemy_board"
const TRIGGER_CARD_SUMMONED: StringName = &"card_summoned"
const TRIGGER_CARD_BEFORE_SUMMONED: StringName = &"card_before_summoned"
const TRIGGER_CARD_AFTER_SUMMONED: StringName = &"card_after_summoned"
const TRIGGER_CARD_AFTER_ATTACK: StringName = &"card_after_attack"
const CARD_BE_ATTACKED: StringName = &"card_be_attacked"
const CARD_BEFORE_MOVED: StringName = &"card_before_moved"
const CARD_BEFORE_FLIPPED: StringName = &"card_before_flipped"
const CARD_AFTER_FLIPPED: StringName = &"card_after_flipped"
const TRIGGER_START_OWNER_TURN: StringName = &"start_owner_turn"
const TRIGGER_END_OWNER_TURN: StringName = &"end_owner_turn"
const TRIGGER_BEFORE_DUEL_END: StringName = &"before_duel_end"
const CONDITION_KI_AT_LEAST: StringName = &"ki_at_least"
const CONDITION_TRIGGER_CARD_IS_ENEMY: StringName = &"trigger_card_is_enemy"
const CONDITION_TRIGGER_CARD_IN_RANGE: StringName = &"trigger_card_in_range"
const CONDITION_TRIGGER_CARD_IS_SELF: StringName = &"trigger_card_is_self"
const CONDITION_ATTACKER_CARD_IS_SELF: StringName = &"attacker_card_is_self"
const CONDITION_TURN_OWNER_IS_SELF: StringName = &"turn_owner_is_self"
const CONDITION_TRIGGER_CARD_REVEALED_TO_SELF: StringName = &"trigger_card_revealed_to_self"
const CONDITION_TRIGGER_CARD_WAS_ENEMY: StringName = &"trigger_card_was_enemy"
const CONDITION_ATTACKER_CARD_IS_ENEMY: StringName = &"attacker_card_is_enemy"
const CONDITION_ATTACK_FLIPPED_ALLY_IN_RANGE: StringName = &"attack_flipped_ally_in_range"
const CONDITION_ATTACKED_CARD_IS_SELF: StringName = &"attacked_card_is_self"
const CONDITION_OWNER_DID_NOT_WIN: StringName = &"owner_did_not_win"
const CONDITION_TRIGGER_CARD_ORIGINAL_OWNER_IS_SELF: StringName = &"trigger_card_original_owner_is_self"
const CONDITION_MOVING_CARD_IS_SELF: StringName = &"moving_card_is_self"
const CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE: StringName = &"trigger_card_adjacent_to_source"
const CONDITION_SOURCE_HAS_ADJACENT_EMPTY_CELL: StringName = &"source_has_adjacent_empty_cell"
const CONDITION_SELECTED_CARD_IS_ALLY: StringName = &"selected_card_is_ally"
const CONDITION_SELECTED_CARD_IS_ENEMY: StringName = &"selected_card_is_enemy"
const CONDITION_SELECTED_CARD_WEAPON_IS: StringName = &"selected_card_weapon_is"
const CONDITION_SELECTED_CARD_IS_NOT_SOURCE: StringName = &"selected_card_is_not_source"
const CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE: StringName = &"selected_card_adjacent_to_source"
const CONDITION_SELECTED_CARD_SURROUNDED_BY_ALLIES: StringName = &"selected_card_surrounded_by_allies"
const CONDITION_SELECTED_CARD_ORIGINAL_OWNER_IS_SELF: StringName = &"selected_card_original_owner_is_self"
const CONDITION_SELECTED_CARD_FLIPPED_BY_CURRENT_ATTACK: StringName = &"selected_card_flipped_by_current_attack"
const ACTION_DRAW_CARDS: StringName = &"draw_cards"
const ACTION_EXILE_ATTACKED_CARD: StringName = &"exile_attacked_card"
const ACTION_ATTACK_TRIGGER_CARD: StringName = &"attack_trigger_card"
const ACTION_GAIN_KI: StringName = &"gain_ki"
const ACTION_SPEND_KI: StringName = &"spend_ki"
const ACTION_SPEND_ALL_KI: StringName = &"spend_all_ki"
const ACTION_REQUEST_EXTRA_TURN: StringName = &"request_extra_turn"
const ACTION_MOVE_SELF_TO_TARGET: StringName = &"move_self_to_target"
const ACTION_SWAP_SELF_WITH_TARGET: StringName = &"swap_self_with_target"
const ACTION_STANDARD_ATTACK_WITH_SELF: StringName = &"standard_attack_with_self"
const ACTION_FOR_EACH_SELECTED_CARD: StringName = &"for_each_selected_card"
const ACTION_ADD_POWERS: StringName = &"add_powers"
const ACTION_ADD_CARD_TO_HAND: StringName = &"add_card_to_hand"
const ACTION_REVEAL_HAND_CARDS: StringName = &"reveal_hand_cards"
const ACTION_ENABLE_FUTURE_DRAW_REVEAL: StringName = &"enable_future_draw_reveal"
const ACTION_GRANT_TRIGGER_CARD_ABILITY: StringName = &"grant_trigger_card_ability"
const ACTION_GRANT_ABILITY_TO_SELF: StringName = &"grant_ability_to_self"
const ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE: StringName = &"self_swapped_with_ability_source"
const ACTION_PREVENT_TRIGGER_FLIP: StringName = &"prevent_trigger_flip"
const ACTION_REMOVE_THIS_ABILITY: StringName = &"remove_this_ability"
const ACTION_FLIP_SELF: StringName = &"flip_self"
const ACTION_RETURN_SELF_TO_ABILITY_SOURCE_HAND: StringName = &"return_self_to_ability_source_hand"
const ACTION_SUMMON_FRESH_COPY_IN_FIRST_ADJACENT_EMPTY: StringName = &"summon_fresh_copy_in_first_adjacent_empty"
const ACTION_EXILE_SELF: StringName = &"exile_self"
const ACTION_RESUMMON_TRIGGER_CARD_IN_PLACE: StringName = &"resummon_trigger_card_in_place"
const ACTION_TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES: StringName = &"temporarily_remove_non_retained_abilities"
const ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY: StringName = &"move_self_to_first_adjacent_empty"
const ACTION_TARGET_ABILITY_SOURCE: StringName = &"ability_source"
const OWNER_ABILITY_SOURCE: StringName = &"ability_source"
const REVEAL_FILTER_ALL: StringName = &"all"
const REVEAL_FILTER_REMEMBERED: StringName = &"remembered"
const MODIFIER_DEFENDING_POWER_OVERRIDE: StringName = &"defending_power_override"
const MODIFIER_ATTACK_REQUIRES_OTHER_ALLY: StringName = &"attack_requires_other_ally"
const MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE: StringName = &"defending_power_uses_minimum_side"
const CARD_ZONE_HAND: StringName = &"hand"
const CARD_ZONE_BOARD: StringName = &"board"
const RECIPIENT_SELF: StringName = &"self"
const RECIPIENT_OPPONENT: StringName = &"opponent"
const ACTION_RESULT_APPLIED: StringName = &"applied"
const ACTION_RESULT_NO_EFFECT: StringName = &"no_effect"
const ACTION_RESULT_INVALID_CONTEXT: StringName = &"invalid_context"
const STOP_RULE: StringName = &"stop_rule"
const KNOWN_ACTIVATION_INPUTS: Array[StringName] = [ACTIVATION_DRAG_TO_TARGET]
const KNOWN_TARGET_RULES: Array[StringName] = [
	TARGET_ADJACENT_EMPTY_BOARD,
	TARGET_ADJACENT_ALLY_BOARD,
	TARGET_ADJACENT_ENEMY_BOARD,
]
const KNOWN_TRIGGER_EVENTS: Array[StringName] = [
	TRIGGER_CARD_SUMMONED,
	TRIGGER_CARD_BEFORE_SUMMONED,
	TRIGGER_CARD_AFTER_SUMMONED,
	TRIGGER_CARD_AFTER_ATTACK,
	CARD_BE_ATTACKED,
	CARD_BEFORE_MOVED,
	CARD_BEFORE_FLIPPED,
	CARD_AFTER_FLIPPED,
	TRIGGER_START_OWNER_TURN,
	TRIGGER_END_OWNER_TURN,
	TRIGGER_BEFORE_DUEL_END,
]
const KNOWN_TRIGGER_CONDITIONS: Array[StringName] = [
	CONDITION_KI_AT_LEAST,
	CONDITION_TRIGGER_CARD_IS_ENEMY,
	CONDITION_TRIGGER_CARD_IN_RANGE,
	CONDITION_TRIGGER_CARD_IS_SELF,
	CONDITION_ATTACKER_CARD_IS_SELF,
	CONDITION_TURN_OWNER_IS_SELF,
	CONDITION_TRIGGER_CARD_REVEALED_TO_SELF,
	CONDITION_TRIGGER_CARD_WAS_ENEMY,
	CONDITION_ATTACKER_CARD_IS_ENEMY,
	CONDITION_ATTACK_FLIPPED_ALLY_IN_RANGE,
	CONDITION_ATTACKED_CARD_IS_SELF,
	CONDITION_OWNER_DID_NOT_WIN,
	CONDITION_TRIGGER_CARD_ORIGINAL_OWNER_IS_SELF,
	CONDITION_MOVING_CARD_IS_SELF,
	CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE,
	CONDITION_SOURCE_HAS_ADJACENT_EMPTY_CELL,
]
const KNOWN_SELECTOR_CONDITIONS: Array[StringName] = [
	CONDITION_SELECTED_CARD_IS_ALLY,
	CONDITION_SELECTED_CARD_IS_ENEMY,
	CONDITION_SELECTED_CARD_WEAPON_IS,
	CONDITION_SELECTED_CARD_IS_NOT_SOURCE,
	CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE,
	CONDITION_SELECTED_CARD_SURROUNDED_BY_ALLIES,
	CONDITION_SELECTED_CARD_ORIGINAL_OWNER_IS_SELF,
	CONDITION_SELECTED_CARD_FLIPPED_BY_CURRENT_ATTACK,
]
const KNOWN_CARD_ZONES: Array[StringName] = [CARD_ZONE_HAND, CARD_ZONE_BOARD]
const KNOWN_ACTIONS: Array[StringName] = [
	ACTION_DRAW_CARDS,
	ACTION_EXILE_ATTACKED_CARD,
	ACTION_ATTACK_TRIGGER_CARD,
	ACTION_GAIN_KI,
	ACTION_SPEND_KI,
	ACTION_SPEND_ALL_KI,
	ACTION_REQUEST_EXTRA_TURN,
	ACTION_MOVE_SELF_TO_TARGET,
	ACTION_SWAP_SELF_WITH_TARGET,
	ACTION_STANDARD_ATTACK_WITH_SELF,
	ACTION_FOR_EACH_SELECTED_CARD,
	ACTION_ADD_POWERS,
	ACTION_ADD_CARD_TO_HAND,
	ACTION_REVEAL_HAND_CARDS,
	ACTION_ENABLE_FUTURE_DRAW_REVEAL,
	ACTION_GRANT_TRIGGER_CARD_ABILITY,
	ACTION_GRANT_ABILITY_TO_SELF,
	ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE,
	ACTION_PREVENT_TRIGGER_FLIP,
	ACTION_REMOVE_THIS_ABILITY,
	ACTION_FLIP_SELF,
	ACTION_RETURN_SELF_TO_ABILITY_SOURCE_HAND,
	ACTION_SUMMON_FRESH_COPY_IN_FIRST_ADJACENT_EMPTY,
	ACTION_EXILE_SELF,
	ACTION_RESUMMON_TRIGGER_CARD_IN_PLACE,
	ACTION_TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES,
	ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY,
]
const KNOWN_RECIPIENTS: Array[StringName] = [RECIPIENT_SELF, RECIPIENT_OPPONENT]
const KNOWN_REVEAL_FILTERS: Array[StringName] = [REVEAL_FILTER_ALL, REVEAL_FILTER_REMEMBERED]
const KNOWN_MODIFIERS: Array[StringName] = [
	MODIFIER_DEFENDING_POWER_OVERRIDE,
	MODIFIER_ATTACK_REQUIRES_OTHER_ALLY,
	MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE,
]

const ALL_CARD_IDS: Array[StringName] = [
	&"CangSongYingKe1",
	&"CangSongYingKe2",
	&"CangSongYingKe3",
	&"CangSongYingKe4",
	&"YouFenLaiYi2",
	&"YouFenLaiYi3",
	&"YouFenLaiYi4",
	&"SanQinFeng1",
	&"SanQinFeng2",
	&"SanQinFeng3",
	&"ZiXiaGong1",
	&"ZiXiaGong2",
	&"ZiXiaGong3",
	&"ZiXiaGong4",
	&"fire_envoy",
	&"tiger_general",
	&"TuNaShu1",
	&"TuNaShu2",
	&"LaiHeQinQuan1",
	&"LaiHeQinQuan2",
	&"LaiHeQinQuan3",
	&"LaiHeQinQuan4",
	&"LaiHeQinQuan5",
	&"TaiShan18Pan1",
	&"TaiShan18Pan2",
	&"TaiShan18Pan3",
	&"WuDaFuJian1",
	&"WuDaFuJian2",
	&"WuDaFuJian3",
	&"QiXinLuoChangKong2",
	&"QiXinLuoChangKong3",
	&"QiXinLuoChangKong4",
	&"TianChangZhang3",
	&"TianChangZhang4",
	&"HenShanJianZhen2",
	&"HenShanJianZhen3",
	&"HenShanJianZhen4",
	&"JinZhenDuJie1",
	&"JinZhenDuJie2",
	&"JinZhenDuJie3",
	&"JinZhenDuJie4",
	&"WanHuaJian1",
	&"WanHuaJian2",
	&"WanHuaJian3",
	&"MianLiCangZhen2",
	&"MianLiCangZhen3",
	&"YunWu13Shi2",
	&"YunWu13Shi3",
	&"YiJianLuo9Yan1",
	&"YiJianLuo9Yan2",
	&"YiJianLuo9Yan3",
	&"TianZhuYunQi2",
	&"TianZhuYunQi3",
	&"TianZhuYunQi4",
	&"JianFaQinYin1",
	&"YanHuiZhuRong3",
	&"canghai_sandie",
	&"haitian_yizhang",
	&"zhujian_cangfeng",
	&"luming_wenlu",
	&"jingwei_dingju",
	&"zhishang_shanhe",
	&"gate_general",
	&"meng_huo",
]

const TEMPORARY_FLIP_PROTECTION: Dictionary = {
	"triggers": [
		{
			"event": CARD_BEFORE_FLIPPED,
			"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{"type": ACTION_PREVENT_TRIGGER_FLIP}],
		},
		{
			"event": CARD_AFTER_FLIPPED,
			"conditions": [{"type": CONDITION_TRIGGER_CARD_WAS_ENEMY}],
			"actions": [{"type": ACTION_REMOVE_THIS_ABILITY}],
		},
		{
			"event": TRIGGER_START_OWNER_TURN,
			"conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
			"actions": [{"type": ACTION_REMOVE_THIS_ABILITY}],
		},
	],
}

const QIXIN_RETAINED_ATTACK_MODIFIERS: Dictionary = {
	"retained_on_flip": true,
	"modifiers": [
		{"type": MODIFIER_ATTACK_REQUIRES_OTHER_ALLY},
		{"type": MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE},
	],
}

const QIXIN_SUMMON_REACTION: Dictionary = {
	"triggers": [
		{
			"event": TRIGGER_CARD_SUMMONED,
			"conditions": [
				{"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
				{"type": CONDITION_TRIGGER_CARD_IN_RANGE},
			],
			"actions": [{"type": ACTION_ATTACK_TRIGGER_CARD}],
		},
	],
}

const HENGSHAN_COUNTERATTACK: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_ATTACK,
		"conditions": [
			{"type": CONDITION_ATTACKER_CARD_IS_ENEMY},
			{"type": CONDITION_ATTACK_FLIPPED_ALLY_IN_RANGE},
		],
		"actions": [
			{"type": ACTION_REMOVE_THIS_ABILITY},
			{"type": ACTION_STANDARD_ATTACK_WITH_SELF},
		],
	}],
}

const MIANLI_RESUMMON: Dictionary = {
	"triggers": [{
		"event": CARD_AFTER_FLIPPED,
		"conditions": [
			{"type": CONDITION_ATTACKER_CARD_IS_SELF},
			{"type": CONDITION_TRIGGER_CARD_ORIGINAL_OWNER_IS_SELF},
		],
		"actions": [{"type": ACTION_RESUMMON_TRIGGER_CARD_IN_PLACE}],
	}],
}

const JINZHEN_RETURN: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_FOR_EACH_SELECTED_CARD,
			"selector": {
				"zones": [CARD_ZONE_BOARD],
				"conditions": [
					{"type": CONDITION_SELECTED_CARD_IS_ENEMY},
					{"type": CONDITION_SELECTED_CARD_ORIGINAL_OWNER_IS_SELF},
				],
				"limit": 1,
			},
			"actions": [{"type": ACTION_RETURN_SELF_TO_ABILITY_SOURCE_HAND}],
		}],
	}],
}

const WANHUA_COPY_TRIGGER: Dictionary = {
	"event": CARD_BE_ATTACKED,
	"conditions": [{"type": CONDITION_ATTACKED_CARD_IS_SELF}],
	"actions": [{"type": ACTION_SUMMON_FRESH_COPY_IN_FIRST_ADJACENT_EMPTY}],
}

const WANHUA_COPY_RETAINED: Dictionary = {
	"retained_on_flip": true,
	"triggers": [WANHUA_COPY_TRIGGER],
}

const WANHUA_COPY: Dictionary = {
	"triggers": [WANHUA_COPY_TRIGGER],
}

const WANHUA_ENDING: Dictionary = {
	"retained_on_flip": true,
	"triggers": [{
		"event": TRIGGER_BEFORE_DUEL_END,
		"conditions": [{"type": CONDITION_OWNER_DID_NOT_WIN}],
		"actions": [{"type": ACTION_EXILE_SELF}],
	}],
}

const TIANCHANG_SUMMON_POWER: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_FOR_EACH_SELECTED_CARD,
			"selector": {
				"zones": [CARD_ZONE_BOARD],
				"conditions": [
					{"type": CONDITION_SELECTED_CARD_IS_ENEMY},
					{"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
				],
			},
			"actions": [{
				"type": ACTION_ADD_POWERS,
				"amount": 1,
				"target": ACTION_TARGET_ABILITY_SOURCE,
			}],
		}],
	}],
}

const _CARD_DEFINITIONS: Dictionary = {
	&"CangSongYingKe1": {
		"id": &"CangSongYingKe1",
		"glyph": "苍松迎客",
		"picture": "res://pics/LKT010_568.png",
		"sect": "华山派",
		"tier": 1,
		"weapon": "剑法",
		"description": "",
		"flavor": "华山剑法的绝招。华山上有数株古松，枝叶向下伸展，有如张臂欢迎上山的游客一般，称为“迎客松”。这招“苍松迎客”，便是从这几株古松的形状上变化而出。",
		"powers": [3, 8, 8, 4],
		"abilities": [],
	},
	&"CangSongYingKe2": {
		"id": &"CangSongYingKe2",
		"glyph": "苍松迎客",
		"picture": "res://pics/LKT010_568.png",
		"sect": "华山派",
		"tier": 2,
		"weapon": "剑法",
		"description": "对手招式进场时，若在我的攻击范围内，我对其发起攻击。",
		"flavor": "华山剑法的绝招。华山上有数株古松，枝叶向下伸展，有如张臂欢迎上山的游客一般，称为“迎客松”。这招“苍松迎客”，便是从这几株古松的形状上变化而出。",
		"powers": [3, 8, 8, 4],
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_CARD_SUMMONED,
						"conditions": [
							{"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
							{"type": CONDITION_TRIGGER_CARD_IN_RANGE},
						],
						"actions": [
							{"type": ACTION_ATTACK_TRIGGER_CARD},
						],
					},
				],
			},
		],
	},
	&"CangSongYingKe3": {
		"id": &"CangSongYingKe3",
		"glyph": "苍松迎客",
		"picture": "res://pics/LKT010_568.png",
		"sect": "华山派",
		"tier": 3,
		"weapon": "剑法",
		"description": "对手招式进场时，若在我的攻击范围内，我对其发起攻击。我翻面前，耗内力以获取一张我的复制。",
		"flavor": "华山剑法的绝招。华山上有数株古松，枝叶向下伸展，有如张臂欢迎上山的游客一般，称为“迎客松”。这招“苍松迎客”，便是从这几株古松的形状上变化而出。",
		"powers": [3, 8, 8, 4],
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_CARD_SUMMONED,
						"conditions": [
							{"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
							{"type": CONDITION_TRIGGER_CARD_IN_RANGE},
						],
						"actions": [
							{"type": ACTION_ATTACK_TRIGGER_CARD},
						],
					},
					{
						"event": CARD_BEFORE_FLIPPED,
						"conditions": [
							{"type": CONDITION_TRIGGER_CARD_IS_SELF},
							{"type": CONDITION_KI_AT_LEAST, "amount": 1},
						],
						"actions": [
							{"type": ACTION_SPEND_KI, "amount": 1},
							{
								"type": ACTION_ADD_CARD_TO_HAND,
								"card_id": &"CangSongYingKe3",
								"recipient": RECIPIENT_SELF,
							},
						],
					},
				],
			},
		],
	},
	&"CangSongYingKe4": {
		"id": &"CangSongYingKe4",
		"glyph": "苍松迎客",
		"picture": "res://pics/LKT010_568.png",
		"sect": "华山派",
		"tier": 4,
		"weapon": "剑法",
		"description": "对手招式进场时，若在我的攻击范围内，我对其发起攻击。我翻面前，耗内力以获取一张我的复制。",
		"flavor": "华山剑法的绝招。华山上有数株古松，枝叶向下伸展，有如张臂欢迎上山的游客一般，称为“迎客松”。这招“苍松迎客”，便是从这几株古松的形状上变化而出。",
		"powers": [4, 9, 8, 5],
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_CARD_SUMMONED,
						"conditions": [
							{"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
							{"type": CONDITION_TRIGGER_CARD_IN_RANGE},
						],
						"actions": [
							{"type": ACTION_ATTACK_TRIGGER_CARD},
						],
					},
					{
						"event": CARD_BEFORE_FLIPPED,
						"conditions": [
							{"type": CONDITION_TRIGGER_CARD_IS_SELF},
							{"type": CONDITION_KI_AT_LEAST, "amount": 1},
						],
						"actions": [
							{"type": ACTION_SPEND_KI, "amount": 1},
							{
								"type": ACTION_ADD_CARD_TO_HAND,
								"card_id": &"CangSongYingKe4",
								"recipient": RECIPIENT_SELF,
							},
						],
					},
				],
			},
		],
	},
	&"YouFenLaiYi2": {
		"id": &"YouFenLaiYi2",
		"glyph": "有凤来仪",
		"picture": "res://pics/LKT010_558.png",
		"sect": "华山派",
		"tier": 2,
		"weapon": "剑法",
		"description": "锁定，指定：移动至一个相邻空格，然后发起攻击。",
		"flavor": "华山剑法的杀招，剑势飞舞而出，轻盈灵动。招数本极寻常，但五个后着变化繁复，威力极大。",
		"powers": [7, 5, 7, 7],
		"starting_ki": 1,
		"abilities": [
			{
				"retained_on_flip": true,
				"activation": {
					"input": ACTIVATION_DRAG_TO_TARGET,
					"target_rule": TARGET_ADJACENT_EMPTY_BOARD,
					"costs": [
						{"type": ACTION_SPEND_KI, "amount": 1},
					],
					"actions": [
						{"type": ACTION_MOVE_SELF_TO_TARGET},
						{"type": ACTION_STANDARD_ATTACK_WITH_SELF},
					],
				},
			},
		],
	},
	&"YouFenLaiYi3": {
		"id": &"YouFenLaiYi3",
		"glyph": "有凤来仪",
		"picture": "res://pics/LKT010_558.png",
		"sect": "华山派",
		"tier": 3,
		"weapon": "剑法",
		"description": "锁定，指定：移动至一个相邻空格，然后发起攻击。锁定，指定：与一个相邻友方交换位置，然后发起攻击。",
		"flavor": "华山剑法的杀招，剑势飞舞而出，轻盈灵动。招数本极寻常，但五个后着变化繁复，威力极大。",
		"powers": [7, 5, 7, 7],
		"starting_ki": 2,
		"abilities": [
			{
				"retained_on_flip": true,
				"activation": {
					"input": ACTIVATION_DRAG_TO_TARGET,
					"target_rule": TARGET_ADJACENT_EMPTY_BOARD,
					"costs": [
						{"type": ACTION_SPEND_KI, "amount": 1},
					],
					"actions": [
						{"type": ACTION_MOVE_SELF_TO_TARGET},
						{"type": ACTION_STANDARD_ATTACK_WITH_SELF},
					],
				},
			},
			{
				"retained_on_flip": true,
				"activation": {
					"input": ACTIVATION_DRAG_TO_TARGET,
					"target_rule": TARGET_ADJACENT_ALLY_BOARD,
					"costs": [
						{"type": ACTION_SPEND_KI, "amount": 1},
					],
					"actions": [
						{"type": ACTION_SWAP_SELF_WITH_TARGET},
						{"type": ACTION_STANDARD_ATTACK_WITH_SELF},
					],
				},
			},
		],
	},
	&"YouFenLaiYi4": {
		"id": &"YouFenLaiYi4",
		"glyph": "有凤来仪",
		"picture": "res://pics/LKT010_558.png",
		"sect": "华山派",
		"tier": 4,
		"weapon": "剑法",
		"description": "锁定，指定：移动至一个相邻空格，然后发起攻击。锁定，指定：与一个相邻友方交换位置，然后发起攻击。锁定，指定：与一个相邻敌方交换位置，然后发起攻击。",
		"flavor": "华山剑法的杀招，剑势飞舞而出，轻盈灵动。招数本极寻常，但五个后着变化繁复，威力极大。",
		"powers": [7, 6, 7, 7],
		"starting_ki": 2,
		"abilities": [
			{
				"retained_on_flip": true,
				"activation": {
					"input": ACTIVATION_DRAG_TO_TARGET,
					"target_rule": TARGET_ADJACENT_EMPTY_BOARD,
					"costs": [
						{"type": ACTION_SPEND_KI, "amount": 1},
					],
					"actions": [
						{"type": ACTION_MOVE_SELF_TO_TARGET},
						{"type": ACTION_STANDARD_ATTACK_WITH_SELF},
					],
				},
			},
			{
				"retained_on_flip": true,
				"activation": {
					"input": ACTIVATION_DRAG_TO_TARGET,
					"target_rule": TARGET_ADJACENT_ALLY_BOARD,
					"costs": [
						{"type": ACTION_SPEND_KI, "amount": 1},
					],
					"actions": [
						{"type": ACTION_SWAP_SELF_WITH_TARGET},
						{"type": ACTION_STANDARD_ATTACK_WITH_SELF},
					],
				},
			},
			{
				"retained_on_flip": true,
				"activation": {
					"input": ACTIVATION_DRAG_TO_TARGET,
					"target_rule": TARGET_ADJACENT_ENEMY_BOARD,
					"costs": [
						{"type": ACTION_SPEND_KI, "amount": 1},
					],
					"actions": [
						{"type": ACTION_SWAP_SELF_WITH_TARGET},
						{"type": ACTION_STANDARD_ATTACK_WITH_SELF},
					],
				},
			},
		],
	},
	&"SanQinFeng1": {
		"id": &"SanQinFeng1",
		"glyph": "太岳三青峰",
		"picture": "res://pics/LKT010_559.png",
		"sect": "华山派",
		"tier": 1,
		"weapon": "剑法",
		"description": "回合开始时，耗内力以令场上首一个友方剑法发起攻击。",
		"flavor": "岳不群的得意之作，据说第二剑比第一剑的劲道狠，第三剑又胜过了第二剑。",
		"powers": [8, 2, 4, 8],
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_START_OWNER_TURN,
						"conditions": [
							{"type": CONDITION_TURN_OWNER_IS_SELF},
							{"type": CONDITION_KI_AT_LEAST, "amount": 1},
						],
						"actions": [
							{"type": ACTION_SPEND_KI, "amount": 1},
							{
								"type": ACTION_FOR_EACH_SELECTED_CARD,
								"selector": {
									"zones": [CARD_ZONE_BOARD],
									"conditions": [
										{"type": CONDITION_SELECTED_CARD_IS_ALLY},
										{
											"type": CONDITION_SELECTED_CARD_WEAPON_IS,
											"weapon": "剑法",
										},
									],
									"limit": 1,
								},
								"actions": [
									{"type": ACTION_STANDARD_ATTACK_WITH_SELF},
								],
							},
						],
					},
				],
			},
		],
	},
	&"SanQinFeng2": {
		"id": &"SanQinFeng2",
		"glyph": "太岳三青峰",
		"picture": "res://pics/LKT010_559.png",
		"sect": "华山派",
		"tier": 2,
		"weapon": "剑法",
		"description": "回合开始时，耗内力以令场上首两个友方剑法发起攻击。",
		"flavor": "岳不群的得意之作，据说第二剑比第一剑的劲道狠，第三剑又胜过了第二剑。",
		"powers": [8, 2, 4, 8],
		"starting_ki": 1,
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_START_OWNER_TURN,
						"conditions": [
							{"type": CONDITION_TURN_OWNER_IS_SELF},
							{"type": CONDITION_KI_AT_LEAST, "amount": 1},
						],
						"actions": [
							{"type": ACTION_SPEND_KI, "amount": 1},
							{
								"type": ACTION_FOR_EACH_SELECTED_CARD,
								"selector": {
									"zones": [CARD_ZONE_BOARD],
									"conditions": [
										{"type": CONDITION_SELECTED_CARD_IS_ALLY},
										{
											"type": CONDITION_SELECTED_CARD_WEAPON_IS,
											"weapon": "剑法",
										},
									],
									"limit": 2,
								},
								"actions": [
									{"type": ACTION_STANDARD_ATTACK_WITH_SELF},
								],
							},
						],
					},
				],
			},
		],
	},
	&"SanQinFeng3": {
		"id": &"SanQinFeng3",
		"glyph": "太岳三青峰",
		"picture": "res://pics/LKT010_559.png",
		"sect": "华山派",
		"tier": 3,
		"weapon": "剑法",
		"description": "回合开始时，耗内力以令场上首三个友方剑法发起攻击。",
		"flavor": "岳不群的得意之作，据说第二剑比第一剑的劲道狠，第三剑又胜过了第二剑。",
		"powers": [8, 3, 4, 8],
		"starting_ki": 1,
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_START_OWNER_TURN,
						"conditions": [
							{"type": CONDITION_TURN_OWNER_IS_SELF},
							{"type": CONDITION_KI_AT_LEAST, "amount": 1},
						],
						"actions": [
							{"type": ACTION_SPEND_KI, "amount": 1},
							{
								"type": ACTION_FOR_EACH_SELECTED_CARD,
								"selector": {
									"zones": [CARD_ZONE_BOARD],
									"conditions": [
										{"type": CONDITION_SELECTED_CARD_IS_ALLY},
										{
											"type": CONDITION_SELECTED_CARD_WEAPON_IS,
											"weapon": "剑法",
										},
									],
									"limit": 3,
								},
								"actions": [
									{"type": ACTION_STANDARD_ATTACK_WITH_SELF},
								],
							},
						],
					},
				],
			},
		],
	},
	&"ZiXiaGong1": {
		"id": &"ZiXiaGong1",
		"glyph": "以气御剑",
		"picture": "res://pics/LKT010_495.png",
		"sect": "华山派",
		"tier": 1,
		"weapon": "心法",
		"description": "进场后，手牌和场上的友方剑法内力加一。",
		"flavor": "华山气宗正统的运气口诀，气功一成，无往不利。",
		"powers": [2, 1, 1, 2],
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_CARD_AFTER_SUMMONED,
						"conditions": [
							{"type": CONDITION_TRIGGER_CARD_IS_SELF},
						],
						"actions": [
							{
								"type": ACTION_FOR_EACH_SELECTED_CARD,
								"selector": {
									"zones": [CARD_ZONE_HAND, CARD_ZONE_BOARD],
									"conditions": [
										{"type": CONDITION_SELECTED_CARD_IS_ALLY},
										{
											"type": CONDITION_SELECTED_CARD_WEAPON_IS,
											"weapon": "剑法",
										},
									],
								},
								"actions": [
									{"type": ACTION_GAIN_KI, "amount": 1},
								],
							},
						],
					},
				],
			},
		],
	},
	&"ZiXiaGong2": {
		"id": &"ZiXiaGong2",
		"glyph": "以气御剑",
		"picture": "res://pics/LKT010_495.png",
		"sect": "华山派",
		"tier": 2,
		"weapon": "心法",
		"description": "进场后，手牌和场上的友方剑法内力加一，抽一张牌。",
		"flavor": "华山气宗正统的运气口诀，气功一成，无往不利。",
		"powers": [2, 1, 1, 2],
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_CARD_AFTER_SUMMONED,
						"conditions": [
							{"type": CONDITION_TRIGGER_CARD_IS_SELF},
						],
						"actions": [
							{
								"type": ACTION_FOR_EACH_SELECTED_CARD,
								"selector": {
									"zones": [CARD_ZONE_HAND, CARD_ZONE_BOARD],
									"conditions": [
										{"type": CONDITION_SELECTED_CARD_IS_ALLY},
										{
											"type": CONDITION_SELECTED_CARD_WEAPON_IS,
											"weapon": "剑法",
										},
									],
								},
								"actions": [
									{"type": ACTION_GAIN_KI, "amount": 1},
								],
							},
							{"type": ACTION_DRAW_CARDS, "amount": 1},
						],
					},
				],
			},
		],
	},
	&"ZiXiaGong3": {
		"id": &"ZiXiaGong3",
		"glyph": "紫霞功",
		"picture": "res://pics/LKT010_496.png",
		"sect": "华山派",
		"tier": 3,
		"weapon": "心法",
		"description": "锁定：回合开始时，所有手牌点数加一。",
		"flavor": "紫霞功威力极大，自来有“华山九功，第一紫霞”的说法。这门内功初发时若有若无，绵如云霞，然而蓄劲极韧，到后来更铺天盖地，势不可当，“紫霞”二字由此而来。",
		"powers": [3, 2, 2, 2],
		"abilities": [
			{
				"retained_on_flip": true,
				"triggers": [
					{
						"event": TRIGGER_START_OWNER_TURN,
						"conditions": [
							{"type": CONDITION_TURN_OWNER_IS_SELF},
						],
						"actions": [
							{
								"type": ACTION_FOR_EACH_SELECTED_CARD,
								"selector": {
									"zones": [CARD_ZONE_HAND],
									"conditions": [
										{"type": CONDITION_SELECTED_CARD_IS_ALLY},
									],
								},
								"actions": [
									{"type": ACTION_ADD_POWERS, "amount": 1},
								],
							},
						],
					},
				],
			},
		],
	},
	&"ZiXiaGong4": {
		"id": &"ZiXiaGong4",
		"glyph": "紫霞功",
		"picture": "res://pics/LKT010_496.png",
		"sect": "华山派",
		"tier": 4,
		"weapon": "心法",
		"description": "锁定：回合开始时，所有手牌点数加一。锁定：回合结束时，场上首两个其它友方点数加一。",
		"flavor": "紫霞功威力极大，自来有“华山九功，第一紫霞”的说法。这门内功初发时若有若无，绵如云霞，然而蓄劲极韧，到后来更铺天盖地，势不可当，“紫霞”二字由此而来。",
		"powers": [3, 2, 2, 2],
		"abilities": [
			{
				"retained_on_flip": true,
				"triggers": [
					{
						"event": TRIGGER_START_OWNER_TURN,
						"conditions": [
							{"type": CONDITION_TURN_OWNER_IS_SELF},
						],
						"actions": [
							{
								"type": ACTION_FOR_EACH_SELECTED_CARD,
								"selector": {
									"zones": [CARD_ZONE_HAND],
									"conditions": [
										{"type": CONDITION_SELECTED_CARD_IS_ALLY},
									],
								},
								"actions": [
									{"type": ACTION_ADD_POWERS, "amount": 1},
								],
							},
						],
					},
					{
						"event": TRIGGER_END_OWNER_TURN,
						"conditions": [
							{"type": CONDITION_TURN_OWNER_IS_SELF},
						],
						"actions": [
							{
								"type": ACTION_FOR_EACH_SELECTED_CARD,
								"selector": {
									"zones": [CARD_ZONE_BOARD],
									"conditions": [
										{"type": CONDITION_SELECTED_CARD_IS_ALLY},
										{"type": CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
									],
									"limit": 2,
								},
								"actions": [
									{"type": ACTION_ADD_POWERS, "amount": 1},
								],
							},
						],
					},
				],
			},
		],
	},
	&"fire_envoy": {
		"id": &"fire_envoy",
		"glyph": "火",
		"picture": "res://pics/LKT010_007.png",
		"sect": "",
		"tier": 1,
		"weapon": "",
		"description": "",
		"flavor": "",
		"powers": [5, 5, 4, 4],
		"abilities": [],
	},
	&"tiger_general": {
		"id": &"tiger_general",
		"glyph": "虎",
		"picture": "res://pics/LKT010_008.png",
		"sect": "",
		"tier": 1,
		"weapon": "",
		"description": "",
		"flavor": "",
		"powers": [3, 4, 8, 8],
		"abilities": [
			{
				"retained_on_flip": true,
				"triggers": [
					{
						"event": CARD_BE_ATTACKED,
						"conditions": [
							{"type": CONDITION_ATTACKER_CARD_IS_SELF},
						],
						"actions": [
							{"type": ACTION_EXILE_ATTACKED_CARD},
						],
					},
				],
			},
		],
	},
	&"TuNaShu1": {
		"id": &"TuNaShu1",
		"glyph": "吐纳术",
		"picture": "res://pics/LKT010_002.png",
		"sect": "江湖",
		"tier": 1,
		"weapon": "心法",
		"description": "进场后，抽一张牌。",
		"flavor": "江湖上常见的呼吸吐纳功夫，简单易学。",
		"powers": [1, 1, 1, 1],
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_CARD_AFTER_SUMMONED,
						"conditions": [
							{"type": CONDITION_TRIGGER_CARD_IS_SELF},
						],
						"actions": [
							{"type": ACTION_DRAW_CARDS, "amount": 1},
						],
					},
				],
			},
		],
	},
	&"TuNaShu2": {
		"id": &"TuNaShu2",
		"glyph": "吐纳术",
		"picture": "res://pics/LKT010_002.png",
		"sect": "江湖",
		"tier": 2,
		"weapon": "心法",
		"description": "进场后，抽两张牌。",
		"flavor": "江湖上常见的呼吸吐纳功夫，简单易学。",
		"powers": [1, 2, 2, 2],
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_CARD_AFTER_SUMMONED,
						"conditions": [
							{"type": CONDITION_TRIGGER_CARD_IS_SELF},
						],
						"actions": [
							{"type": ACTION_DRAW_CARDS, "amount": 2},
						],
					},
				],
			},
		],
	},
	&"LaiHeQinQuan1": {
		"id": &"LaiHeQinQuan1",
		"glyph": "来鹤清泉",
		"picture": "res://pics/LKT010_001.png",
		"sect": "泰山派",
		"tier": 1,
		"weapon": "重剑",
		"description": "进场后，揭示所有敌方手牌。",
		"flavor": "泰山派剑法，弯腰出剑，形如仙鹤饮水。",
		"powers": [2, 2, 4, 4],
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_CARD_AFTER_SUMMONED,
						"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
						"actions": [{
							"type": ACTION_REVEAL_HAND_CARDS,
							"recipient": RECIPIENT_OPPONENT,
							"filter": REVEAL_FILTER_ALL,
						}],
					},
				],
			},
		],
	},
	&"LaiHeQinQuan2": {
		"id": &"LaiHeQinQuan2",
		"glyph": "来鹤清泉",
		"picture": "res://pics/LKT010_001.png",
		"sect": "泰山派",
		"tier": 2,
		"weapon": "重剑",
		"description": "进场后，揭示所有敌方手牌。我翻面前，阻止翻面，敌方翻面后或回合开始时，失去此效果。",
		"flavor": "泰山派剑法，弯腰出剑，形如仙鹤饮水。",
		"powers": [2, 2, 4, 4],
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_CARD_AFTER_SUMMONED,
						"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
						"actions": [{
							"type": ACTION_REVEAL_HAND_CARDS,
							"recipient": RECIPIENT_OPPONENT,
							"filter": REVEAL_FILTER_ALL,
						}],
					},
				],
			},
			{
				"triggers": [
					{
						"event": CARD_BEFORE_FLIPPED,
						"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
						"actions": [{"type": ACTION_PREVENT_TRIGGER_FLIP}],
					},
					{
						"event": CARD_AFTER_FLIPPED,
						"conditions": [{"type": CONDITION_TRIGGER_CARD_WAS_ENEMY}],
						"actions": [{"type": ACTION_REMOVE_THIS_ABILITY}],
					},
					{
						"event": TRIGGER_START_OWNER_TURN,
						"conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
						"actions": [{"type": ACTION_REMOVE_THIS_ABILITY}],
					},
				],
			},
		],
	},
	&"LaiHeQinQuan3": {
		"id": &"LaiHeQinQuan3",
		"glyph": "来鹤清泉",
		"picture": "res://pics/LKT010_001.png",
		"sect": "泰山派",
		"tier": 3,
		"weapon": "重剑",
		"description": "进场后，揭示所有敌方手牌以及后续抽到的牌。我翻面前，阻止翻面，敌方翻面后或回合开始时，失去此效果。",
		"flavor": "泰山派剑法，弯腰出剑，形如仙鹤饮水。",
		"powers": [2, 2, 5, 5],
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_CARD_AFTER_SUMMONED,
						"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
						"actions": [{
							"type": ACTION_REVEAL_HAND_CARDS,
							"recipient": RECIPIENT_OPPONENT,
							"filter": REVEAL_FILTER_ALL,
						}],
					},
				],
			},
			{
				"triggers": [
					{
						"event": TRIGGER_CARD_AFTER_SUMMONED,
						"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
						"actions": [{
							"type": ACTION_ENABLE_FUTURE_DRAW_REVEAL,
							"recipient": RECIPIENT_OPPONENT,
						}],
					},
				],
			},
			{
				"triggers": [
					{
						"event": CARD_BEFORE_FLIPPED,
						"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
						"actions": [{"type": ACTION_PREVENT_TRIGGER_FLIP}],
					},
					{
						"event": CARD_AFTER_FLIPPED,
						"conditions": [{"type": CONDITION_TRIGGER_CARD_WAS_ENEMY}],
						"actions": [{"type": ACTION_REMOVE_THIS_ABILITY}],
					},
					{
						"event": TRIGGER_START_OWNER_TURN,
						"conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
						"actions": [{"type": ACTION_REMOVE_THIS_ABILITY}],
					},
				],
			},
		],
	},
	&"LaiHeQinQuan4": {
		"id": &"LaiHeQinQuan4",
		"glyph": "岱宗如何",
		"picture": "res://pics/LKT010_004.png",
		"sect": "泰山派",
		"tier": 4,
		"weapon": "术数",
		"description": "进场后，揭示敌方手牌中曾经出过的牌。敌方手牌中已揭示的牌进场时，使其获得以下效果：判断是否能被攻击时，所有点数视为零。",
		"flavor": "泰山派剑法中最高深的绝艺，要旨不在右手剑招，而在左手的算数。左手不住屈指计算，算的是敌人所处方位、武功门派、身形长短、兵刃大小，以及日光所照高低等等，计算极为繁复，一经算准，挺剑击出，无不中的。",
		"powers": [1, 4, 3, 2],
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_CARD_AFTER_SUMMONED,
						"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
						"actions": [{
							"type": ACTION_REVEAL_HAND_CARDS,
							"recipient": RECIPIENT_OPPONENT,
							"filter": REVEAL_FILTER_REMEMBERED,
						}],
					},
				],
			},
			{
				"triggers": [
					{
						"event": TRIGGER_CARD_SUMMONED,
						"conditions": [
							{"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
							{"type": CONDITION_TRIGGER_CARD_REVEALED_TO_SELF},
						],
						"actions": [{
							"type": ACTION_GRANT_TRIGGER_CARD_ABILITY,
							"ability": {
								"modifiers": [{
									"type": MODIFIER_DEFENDING_POWER_OVERRIDE,
									"value": 0,
								}],
							},
						}],
					},
				],
			},
		],
	},
	&"LaiHeQinQuan5": {
		"id": &"LaiHeQinQuan5",
		"glyph": "岱宗如何",
		"picture": "res://pics/LKT010_004.png",
		"sect": "泰山派",
		"tier": 5,
		"weapon": "术数",
		"description": "进场后，揭示敌方手牌中曾经出过的牌。敌方手牌中已揭示的牌进场时，使其获得以下效果：判断是否能被攻击时，所有点数视为零。我翻面前，阻止翻面，敌方翻面后或回合开始时，失去此效果。",
		"flavor": "泰山派剑法中最高深的绝艺，要旨不在右手剑招，而在左手的算数。左手不住屈指计算，算的是敌人所处方位、武功门派、身形长短、兵刃大小，以及日光所照高低等等，计算极为繁复，一经算准，挺剑击出，无不中的。",
		"powers": [2, 5, 4, 3],
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_CARD_AFTER_SUMMONED,
						"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
						"actions": [{
							"type": ACTION_REVEAL_HAND_CARDS,
							"recipient": RECIPIENT_OPPONENT,
							"filter": REVEAL_FILTER_REMEMBERED,
						}],
					},
				],
			},
			{
				"triggers": [
					{
						"event": TRIGGER_CARD_SUMMONED,
						"conditions": [
							{"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
							{"type": CONDITION_TRIGGER_CARD_REVEALED_TO_SELF},
						],
						"actions": [{
							"type": ACTION_GRANT_TRIGGER_CARD_ABILITY,
							"ability": {
								"modifiers": [{
									"type": MODIFIER_DEFENDING_POWER_OVERRIDE,
									"value": 0,
								}],
							},
						}],
					},
				],
			},
			{
				"triggers": [
					{
						"event": CARD_BEFORE_FLIPPED,
						"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
						"actions": [{"type": ACTION_PREVENT_TRIGGER_FLIP}],
					},
					{
						"event": CARD_AFTER_FLIPPED,
						"conditions": [{"type": CONDITION_TRIGGER_CARD_WAS_ENEMY}],
						"actions": [{"type": ACTION_REMOVE_THIS_ABILITY}],
					},
					{
						"event": TRIGGER_START_OWNER_TURN,
						"conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
						"actions": [{"type": ACTION_REMOVE_THIS_ABILITY}],
					},
				],
			},
		],
	},
	&"TaiShan18Pan1": {
		"id": &"TaiShan18Pan1",
		"glyph": "泰山十八盘",
		"picture": "res://pics/LKT010_502.png",
		"sect": "泰山派",
		"tier": 1,
		"weapon": "重剑",
		"description": "",
		"flavor": "泰山派昔年一位名宿所创剑法，他见泰山山门下十八盘处羊肠曲折，五步一转，十步一回，势甚险峻，因而将地势融入剑法之中，与八卦门的八卦游身掌有异曲同工之妙。泰山十八盘越盘越高，越行越险，这路剑招也是越转越狠辣。",
		"powers": [7, 4, 7, 4],
		"abilities": [],
	},
	&"TaiShan18Pan2": {
		"id": &"TaiShan18Pan2",
		"glyph": "泰山十八盘",
		"picture": "res://pics/LKT010_502.png",
		"sect": "泰山派",
		"tier": 2,
		"weapon": "重剑",
		"description": "进场后，若只有一个相邻敌方，与其交换位置。",
		"flavor": "泰山派昔年一位名宿所创剑法，他见泰山山门下十八盘处羊肠曲折，五步一转，十步一回，势甚险峻，因而将地势融入剑法之中，与八卦门的八卦游身掌有异曲同工之妙。泰山十八盘越盘越高，越行越险，这路剑招也是越转越狠辣。",
		"powers": [7, 4, 7, 4],
		"abilities": [{
			"triggers": [{
				"event": TRIGGER_CARD_AFTER_SUMMONED,
				"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
				"actions": [{
					"type": ACTION_FOR_EACH_SELECTED_CARD,
					"selector": {
						"zones": [CARD_ZONE_BOARD],
						"conditions": [
							{"type": CONDITION_SELECTED_CARD_IS_ENEMY},
							{"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
						],
						"required_count": 1,
					},
					"actions": [{"type": ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE}],
				}],
			}],
		}],
	},
	&"TaiShan18Pan3": {
		"id": &"TaiShan18Pan3",
		"glyph": "泰山十八盘",
		"picture": "res://pics/LKT010_502.png",
		"sect": "泰山派",
		"tier": 3,
		"weapon": "重剑",
		"description": "进场后，若只有一个相邻敌方，与其交换位置。我翻面前，阻止翻面，敌方翻面后或回合开始时，失去此效果。",
		"flavor": "泰山派昔年一位名宿所创剑法，他见泰山山门下十八盘处羊肠曲折，五步一转，十步一回，势甚险峻，因而将地势融入剑法之中，与八卦门的八卦游身掌有异曲同工之妙。泰山十八盘越盘越高，越行越险，这路剑招也是越转越狠辣。",
		"powers": [7, 4, 7, 4],
		"abilities": [
			{
				"triggers": [{
					"event": TRIGGER_CARD_AFTER_SUMMONED,
					"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
					"actions": [{
						"type": ACTION_FOR_EACH_SELECTED_CARD,
						"selector": {
							"zones": [CARD_ZONE_BOARD],
							"conditions": [
								{"type": CONDITION_SELECTED_CARD_IS_ENEMY},
								{"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
							],
							"required_count": 1,
						},
						"actions": [{"type": ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE}],
					}],
				}],
			},
			TEMPORARY_FLIP_PROTECTION,
		],
	},
	&"WuDaFuJian1": {
		"id": &"WuDaFuJian1",
		"glyph": "五大夫剑",
		"picture": "res://pics/LKT010_553.png",
		"sect": "泰山派",
		"tier": 1,
		"weapon": "重剑",
		"description": "进场后，使我获得以下效果：我翻面前，阻止翻面，敌方翻面后或回合开始时，失去此效果。",
		"flavor": "泰山有松树极古，相传为秦时所封之“五大夫松”，虬枝斜出，苍翠相掩。泰山派师祖曾由此而悟出一套招数古朴，内藏奇变的剑法。",
		"powers": [3, 5, 3, 3],
		"abilities": [{
			"triggers": [{
				"event": TRIGGER_CARD_AFTER_SUMMONED,
				"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
				"actions": [{
					"type": ACTION_GRANT_ABILITY_TO_SELF,
					"ability": TEMPORARY_FLIP_PROTECTION,
				}],
			}],
		}],
	},
	&"WuDaFuJian2": {
		"id": &"WuDaFuJian2",
		"glyph": "五大夫剑",
		"picture": "res://pics/LKT010_553.png",
		"sect": "泰山派",
		"tier": 2,
		"weapon": "重剑",
		"description": "进场后，使所有友方重剑获得以下效果：我翻面前，阻止翻面，敌方翻面后或回合开始时，失去此效果。",
		"flavor": "泰山有松树极古，相传为秦时所封之“五大夫松”，虬枝斜出，苍翠相掩。泰山派师祖曾由此而悟出一套招数古朴，内藏奇变的剑法。",
		"powers": [3, 5, 3, 3],
		"abilities": [{
			"triggers": [{
				"event": TRIGGER_CARD_AFTER_SUMMONED,
				"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
				"actions": [{
					"type": ACTION_FOR_EACH_SELECTED_CARD,
					"selector": {
						"zones": [CARD_ZONE_BOARD],
						"conditions": [
							{"type": CONDITION_SELECTED_CARD_IS_ALLY},
							{
								"type": CONDITION_SELECTED_CARD_WEAPON_IS,
								"weapon": "重剑",
							},
						],
					},
					"actions": [{
						"type": ACTION_GRANT_ABILITY_TO_SELF,
						"ability": TEMPORARY_FLIP_PROTECTION,
					}],
				}],
			}],
		}],
	},
	&"WuDaFuJian3": {
		"id": &"WuDaFuJian3",
		"glyph": "五大夫剑",
		"picture": "res://pics/LKT010_553.png",
		"sect": "泰山派",
		"tier": 3,
		"weapon": "重剑",
		"description": "进场后，每有一个友方重剑，抽一张牌，并使所有友方重剑获得以下效果：我翻面前，阻止翻面，敌方翻面后或回合开始时，失去此效果。",
		"flavor": "泰山有松树极古，相传为秦时所封之“五大夫松”，虬枝斜出，苍翠相掩。泰山派师祖曾由此而悟出一套招数古朴，内藏奇变的剑法。",
		"powers": [3, 5, 3, 3],
		"abilities": [{
			"triggers": [{
				"event": TRIGGER_CARD_AFTER_SUMMONED,
				"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
				"actions": [
					{
						"type": ACTION_FOR_EACH_SELECTED_CARD,
						"selector": {
							"zones": [CARD_ZONE_BOARD],
							"conditions": [
								{"type": CONDITION_SELECTED_CARD_IS_ALLY},
								{
									"type": CONDITION_SELECTED_CARD_WEAPON_IS,
									"weapon": "重剑",
								},
							],
						},
						"actions": [{"type": ACTION_DRAW_CARDS, "amount": 1}],
					},
					{
						"type": ACTION_FOR_EACH_SELECTED_CARD,
						"selector": {
							"zones": [CARD_ZONE_BOARD],
							"conditions": [
								{"type": CONDITION_SELECTED_CARD_IS_ALLY},
								{
									"type": CONDITION_SELECTED_CARD_WEAPON_IS,
									"weapon": "重剑",
								},
							],
						},
						"actions": [{
							"type": ACTION_GRANT_ABILITY_TO_SELF,
							"ability": TEMPORARY_FLIP_PROTECTION,
						}],
					},
				],
			}],
		}],
	},
	&"QiXinLuoChangKong2": {
		"id": &"QiXinLuoChangKong2",
		"glyph": "七星落长空",
		"picture": "res://pics/LKT010_546.png",
		"sect": "泰山派",
		"tier": 2,
		"weapon": "重剑",
		"description": "锁定：场上没有其它友方时无法攻击。锁定：攻击时，防御者的点数视为其最小一侧的点数。",
		"flavor": "泰山派剑法的精要所在。单只这一剑，便罩住对方胸口的膻中、神藏、灵墟、神封、步廊、幽门、通谷七处大穴，不论闪向何处，总有一穴会让剑尖刺中。须得轻功高强，立即倒纵出丈许之外，方可避过。",
		"powers": [6, 6, 5, 6],
		"abilities": [QIXIN_RETAINED_ATTACK_MODIFIERS],
	},
	&"QiXinLuoChangKong3": {
		"id": &"QiXinLuoChangKong3",
		"glyph": "七星落长空",
		"picture": "res://pics/LKT010_546.png",
		"sect": "泰山派",
		"tier": 3,
		"weapon": "重剑",
		"description": "锁定：场上没有其它友方时无法攻击。锁定：防御者的点数视为其最小一侧的点数。对手招式进场时，若在我的攻击范围内，我对其发起攻击。",
		"flavor": "泰山派剑法的精要所在。单只这一剑，便罩住对方胸口的膻中、神藏、灵墟、神封、步廊、幽门、通谷七处大穴，不论闪向何处，总有一穴会让剑尖刺中。须得轻功高强，立即倒纵出丈许之外，方可避过。",
		"powers": [6, 6, 6, 6],
		"abilities": [
			QIXIN_RETAINED_ATTACK_MODIFIERS,
			QIXIN_SUMMON_REACTION,
		],
	},
	&"QiXinLuoChangKong4": {
		"id": &"QiXinLuoChangKong4",
		"glyph": "七星落长空",
		"picture": "res://pics/LKT010_546.png",
		"sect": "泰山派",
		"tier": 4,
		"weapon": "重剑",
		"description": "锁定：场上没有其它友方时无法攻击。锁定：防御者的点数视为其最小一侧的点数。对手招式进场时，若在我的攻击范围内，我对其发起攻击。我翻面前，阻止翻面，敌方翻面后或回合开始时，失去此效果。",
		"flavor": "泰山派剑法的精要所在。单只这一剑，便罩住对方胸口的膻中、神藏、灵墟、神封、步廊、幽门、通谷七处大穴，不论闪向何处，总有一穴会让剑尖刺中。须得轻功高强，立即倒纵出丈许之外，方可避过。",
		"powers": [7, 5, 5, 5],
		"abilities": [
			QIXIN_RETAINED_ATTACK_MODIFIERS,
			QIXIN_SUMMON_REACTION,
			TEMPORARY_FLIP_PROTECTION,
		],
	},
	&"TianChangZhang3": {
		"id": &"TianChangZhang3",
		"glyph": "天长掌法",
		"picture": "res://pics/LKT010_023.png",
		"sect": "恒山派",
		"tier": 3,
		"weapon": "掌法",
		"description": "进场后，每有一个相邻敌方，我的点数加一。",
		"flavor": "恒山派掌法，练成之后可单凭一双肉掌，在合力围攻的兵刃间翻滚来去。",
		"powers": [7, 6, 7, 6],
		"abilities": [TIANCHANG_SUMMON_POWER],
	},
	&"TianChangZhang4": {
		"id": &"TianChangZhang4",
		"glyph": "天长掌法",
		"picture": "res://pics/LKT010_023.png",
		"sect": "恒山派",
		"tier": 4,
		"weapon": "掌法",
		"description": "进场后，每有一个相邻敌方，我的点数加一。敌方攻击后，若本次攻击中有在我攻击范围内的友方被翻面，我发起攻击，然后失去此效果。",
		"flavor": "恒山派掌法，练成之后可单凭一双肉掌，在合力围攻的兵刃间翻滚来去。",
		"powers": [7, 6, 7, 6],
		"abilities": [
			TIANCHANG_SUMMON_POWER,
			HENGSHAN_COUNTERATTACK,
		],
	},
	&"HenShanJianZhen2": {
		"id": &"HenShanJianZhen2",
		"glyph": "恒山剑阵",
		"picture": "res://pics/LKT010_350.png",
		"sect": "恒山派",
		"tier": 2,
		"weapon": "剑阵",
		"description": "回合结束时，使我和所有相邻友方获得以下效果：敌方攻击后，若本次攻击中有在我攻击范围内的友方被翻面，我发起攻击，然后失去此效果。",
		"flavor": "恒山派的奇妙剑阵，七柄剑既攻敌，复自守，七剑连环，绝无破绽可寻，在纹丝不动之中蕴含无限杀机。",
		"powers": [6, 7, 6, 7],
		"abilities": [{
			"triggers": [{
				"event": TRIGGER_END_OWNER_TURN,
				"conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
				"actions": [
					{
						"type": ACTION_GRANT_ABILITY_TO_SELF,
						"ability": HENGSHAN_COUNTERATTACK,
					},
					{
						"type": ACTION_FOR_EACH_SELECTED_CARD,
						"selector": {
							"zones": [CARD_ZONE_BOARD],
							"conditions": [
								{"type": CONDITION_SELECTED_CARD_IS_ALLY},
								{"type": CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
								{"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
							],
						},
						"actions": [{
							"type": ACTION_GRANT_ABILITY_TO_SELF,
							"ability": HENGSHAN_COUNTERATTACK,
						}],
					},
				],
			}],
		}],
	},
	&"HenShanJianZhen3": {
		"id": &"HenShanJianZhen3",
		"glyph": "恒山剑阵",
		"picture": "res://pics/LKT010_350.png",
		"sect": "恒山派",
		"tier": 3,
		"weapon": "剑阵",
		"description": "回合结束时，使我和所有友方获得以下效果：敌方攻击后，若本次攻击中有在我攻击范围内的友方被翻面，我发起攻击，然后失去此效果。",
		"flavor": "恒山派的奇妙剑阵，七柄剑既攻敌，复自守，七剑连环，绝无破绽可寻，在纹丝不动之中蕴含无限杀机。",
		"powers": [6, 7, 6, 7],
		"abilities": [{
			"triggers": [{
				"event": TRIGGER_END_OWNER_TURN,
				"conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
				"actions": [{
					"type": ACTION_FOR_EACH_SELECTED_CARD,
					"selector": {
						"zones": [CARD_ZONE_BOARD],
						"conditions": [{"type": CONDITION_SELECTED_CARD_IS_ALLY}],
					},
					"actions": [{
						"type": ACTION_GRANT_ABILITY_TO_SELF,
						"ability": HENGSHAN_COUNTERATTACK,
					}],
				}],
			}],
		}],
	},
	&"HenShanJianZhen4": {
		"id": &"HenShanJianZhen4",
		"glyph": "恒山剑阵",
		"picture": "res://pics/LKT010_350.png",
		"sect": "恒山派",
		"tier": 4,
		"weapon": "剑阵",
		"description": "进场后，使所有被友方包围的敌方翻面。回合结束时，使我和所有友方获得以下效果：敌方攻击后，若本次攻击中有在我攻击范围内的友方被翻面，我发起攻击，然后失去此效果。",
		"flavor": "恒山派的奇妙剑阵，七柄剑既攻敌，复自守，七剑连环，绝无破绽可寻，在纹丝不动之中蕴含无限杀机。",
		"powers": [6, 7, 6, 7],
		"abilities": [
			{
				"triggers": [{
					"event": TRIGGER_CARD_AFTER_SUMMONED,
					"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
					"actions": [{
						"type": ACTION_FOR_EACH_SELECTED_CARD,
						"selector": {
							"zones": [CARD_ZONE_BOARD],
							"conditions": [
								{"type": CONDITION_SELECTED_CARD_IS_ENEMY},
								{"type": CONDITION_SELECTED_CARD_SURROUNDED_BY_ALLIES},
							],
						},
						"actions": [{
							"type": ACTION_FLIP_SELF,
							"new_owner": OWNER_ABILITY_SOURCE,
						}],
					}],
				}],
			},
			{
				"triggers": [{
					"event": TRIGGER_END_OWNER_TURN,
					"conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
					"actions": [{
						"type": ACTION_FOR_EACH_SELECTED_CARD,
						"selector": {
							"zones": [CARD_ZONE_BOARD],
							"conditions": [{"type": CONDITION_SELECTED_CARD_IS_ALLY}],
						},
						"actions": [{
							"type": ACTION_GRANT_ABILITY_TO_SELF,
							"ability": HENGSHAN_COUNTERATTACK,
						}],
					}],
				}],
			},
		],
	},
	&"JinZhenDuJie1": {
		"id": &"JinZhenDuJie1",
		"glyph": "金针渡劫",
		"picture": "res://pics/LKT010_567.png",
		"sect": "恒山派",
		"tier": 1,
		"weapon": "轻剑",
		"description": "",
		"flavor": "中规中矩的恒山派武学，剑法中隐含阴柔之力，圆转绵密，余意不尽。",
		"powers": [7, 7, 3, 3],
		"abilities": [],
	},
	&"JinZhenDuJie2": {
		"id": &"JinZhenDuJie2",
		"glyph": "金针渡劫",
		"picture": "res://pics/LKT010_567.png",
		"sect": "恒山派",
		"tier": 2,
		"weapon": "轻剑",
		"description": "进场后，将首个最初是友方的敌方移回你的手牌。",
		"flavor": "中规中矩的恒山派武学，剑法中隐含阴柔之力，圆转绵密，余意不尽。",
		"powers": [7, 7, 3, 3],
		"abilities": [JINZHEN_RETURN],
	},
	&"JinZhenDuJie3": {
		"id": &"JinZhenDuJie3",
		"glyph": "金针渡劫",
		"picture": "res://pics/LKT010_567.png",
		"sect": "恒山派",
		"tier": 3,
		"weapon": "轻剑",
		"description": "进场后，将首个最初是友方的敌方移回你的手牌。敌方攻击后，若本次攻击中有在我攻击范围内的友方被翻面，我发起攻击，然后失去此效果。",
		"flavor": "中规中矩的恒山派武学，剑法中隐含阴柔之力，圆转绵密，余意不尽。",
		"powers": [7, 7, 3, 3],
		"abilities": [JINZHEN_RETURN, HENGSHAN_COUNTERATTACK],
	},
	&"JinZhenDuJie4": {
		"id": &"JinZhenDuJie4",
		"glyph": "金针渡劫",
		"picture": "res://pics/LKT010_567.png",
		"sect": "恒山派",
		"tier": 4,
		"weapon": "轻剑",
		"description": "进场后，将首个最初是友方的敌方移回你的手牌。敌方攻击后，若本次攻击中有在我攻击范围内的友方被翻面，我发起攻击，然后失去此效果。",
		"flavor": "中规中矩的恒山派武学，剑法中隐含阴柔之力，圆转绵密，余意不尽。",
		"powers": [8, 8, 4, 4],
		"abilities": [JINZHEN_RETURN, HENGSHAN_COUNTERATTACK],
	},
	&"WanHuaJian1": {
		"id": &"WanHuaJian1",
		"glyph": "万花剑法",
		"picture": "res://pics/LKT010_491.png",
		"sect": "恒山派",
		"tier": 1,
		"weapon": "轻剑",
		"description": "锁定：对局结束前，若你没赢，将我移除。",
		"flavor": "恒山派的精妙剑法，黑夜之中，唯有星月微光，长剑飞舞。",
		"powers": [4, 4, 4, 4],
		"abilities": [WANHUA_ENDING],
	},
	&"WanHuaJian2": {
		"id": &"WanHuaJian2",
		"glyph": "万花剑法",
		"picture": "res://pics/LKT010_491.png",
		"sect": "恒山派",
		"tier": 2,
		"weapon": "轻剑",
		"description": "锁定：被攻击时，在首个相邻空格生成我的复制。锁定：对局结束前，若你没赢，将我移除。",
		"flavor": "恒山派的精妙剑法，黑夜之中，唯有星月微光，长剑飞舞。",
		"powers": [4, 4, 4, 4],
		"abilities": [WANHUA_COPY_RETAINED, WANHUA_ENDING],
	},
	&"WanHuaJian3": {
		"id": &"WanHuaJian3",
		"glyph": "万花剑法",
		"picture": "res://pics/LKT010_491.png",
		"sect": "恒山派",
		"tier": 3,
		"weapon": "轻剑",
		"description": "被攻击时，在首个相邻空格生成我的复制。锁定：对局结束前，若你没赢，将我移除。",
		"flavor": "恒山派的精妙剑法，黑夜之中，唯有星月微光，长剑飞舞。",
		"powers": [4, 4, 4, 4],
		"abilities": [WANHUA_COPY, WANHUA_ENDING],
	},
	&"MianLiCangZhen2": {
		"id": &"MianLiCangZhen2",
		"glyph": "绵里藏针",
		"picture": "res://pics/LKT010_510.png",
		"sect": "恒山派",
		"tier": 2,
		"weapon": "轻剑",
		"description": "敌方攻击后，若本次攻击中有在我攻击范围内的友方被翻面，我发起攻击，然后失去此效果。",
		"flavor": "恒山派武功的根本要诀，于极平凡的招式之中暗蓄锋芒，便如是暗藏钢针的一团棉絮。旁人倘若不加触犯，棉絮轻柔温软，于人无忤，但若猛力紧捏，棉絮中所藏钢针便刺入手掌。",
		"powers": [4, 2, 8, 8],
		"abilities": [HENGSHAN_COUNTERATTACK],
	},
	&"MianLiCangZhen3": {
		"id": &"MianLiCangZhen3",
		"glyph": "绵里藏针",
		"picture": "res://pics/LKT010_510.png",
		"sect": "恒山派",
		"tier": 3,
		"weapon": "轻剑",
		"description": "我将敌方翻面后，若其最初是友方，使其重新进场。敌方攻击后，若本次攻击中有在我攻击范围内的友方被翻面，我发起攻击，然后失去此效果。",
		"flavor": "恒山派武功的根本要诀，于极平凡的招式之中暗蓄锋芒，便如是暗藏钢针的一团棉絮。旁人倘若不加触犯，棉絮轻柔温软，于人无忤，但若猛力紧捏，棉絮中所藏钢针便刺入手掌。",
		"powers": [4, 2, 8, 8],
		"abilities": [MIANLI_RESUMMON, HENGSHAN_COUNTERATTACK],
	},
	&"YunWu13Shi2": {
		"id": &"YunWu13Shi2",
		"glyph": "云雾十三式",
		"picture": "res://pics/LKT010_437.png",
		"sect": "衡山派",
		"tier": 2,
		"weapon": "轻剑",
		"description": "进场前，使所有敌方失去效果，直到当前回合结束。",
		"flavor": "这一套“百变千幻衡山云雾十三式”乃衡山派上代一位走江湖变戏法卖艺为生的高手所创。那走江湖变戏法，仗的是声东击西，虚虚实实，幻人耳目。到得晚年，他武功愈高，变戏法的技能也是日增，竟然将内家功夫使用到戏法之中，街头观众一见，无不称赏，后来更是一变，反将变戏法的本领渗入了武功，五花八门，层出不穷。",
		"powers": [7, 6, 5, 4],
		"abilities": [{
			"triggers": [{
				"event": TRIGGER_CARD_BEFORE_SUMMONED,
				"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
				"actions": [{
					"type": ACTION_FOR_EACH_SELECTED_CARD,
					"selector": {
						"zones": [CARD_ZONE_BOARD],
						"conditions": [{"type": CONDITION_SELECTED_CARD_IS_ENEMY}],
					},
					"actions": [{"type": ACTION_TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES}],
				}],
			}],
		}],
	},
	&"YunWu13Shi3": {
		"id": &"YunWu13Shi3",
		"glyph": "云雾十三式",
		"picture": "res://pics/LKT010_437.png",
		"sect": "衡山派",
		"tier": 3,
		"weapon": "轻剑",
		"description": "进场前，使所有敌方失去效果，直到当前回合结束。进场后，若只有一个相邻敌方，与其交换位置。",
		"flavor": "这一套“百变千幻衡山云雾十三式”乃衡山派上代一位走江湖变戏法卖艺为生的高手所创。那走江湖变戏法，仗的是声东击西，虚虚实实，幻人耳目。到得晚年，他武功愈高，变戏法的技能也是日增，竟然将内家功夫使用到戏法之中，街头观众一见，无不称赏，后来更是一变，反将变戏法的本领渗入了武功，五花八门，层出不穷。",
		"powers": [7, 6, 5, 4],
		"abilities": [
			{
				"triggers": [{
					"event": TRIGGER_CARD_BEFORE_SUMMONED,
					"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
					"actions": [{
						"type": ACTION_FOR_EACH_SELECTED_CARD,
						"selector": {
							"zones": [CARD_ZONE_BOARD],
							"conditions": [{"type": CONDITION_SELECTED_CARD_IS_ENEMY}],
						},
						"actions": [{"type": ACTION_TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES}],
					}],
				}],
			},
			{
				"triggers": [{
					"event": TRIGGER_CARD_AFTER_SUMMONED,
					"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
					"actions": [{
						"type": ACTION_FOR_EACH_SELECTED_CARD,
						"selector": {
							"zones": [CARD_ZONE_BOARD],
							"conditions": [
								{"type": CONDITION_SELECTED_CARD_IS_ENEMY},
								{"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
							],
							"required_count": 1,
						},
						"actions": [{"type": ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE}],
					}],
				}],
			},
		],
	},
	&"YiJianLuo9Yan1": {
		"id": &"YiJianLuo9Yan1",
		"glyph": "一剑落九雁",
		"picture": "res://pics/LKT010_494.png",
		"sect": "衡山派",
		"tier": 1,
		"weapon": "轻剑",
		"description": "",
		"flavor": "衡山派三十六路回风落雁剑中的第十七招，莫大先生曾用此式一剑削断七只茶杯，而茶杯一只不倒。",
		"powers": [6, 8, 6, 2],
		"abilities": [],
	},
	&"YiJianLuo9Yan2": {
		"id": &"YiJianLuo9Yan2",
		"glyph": "一剑落九雁",
		"picture": "res://pics/LKT010_494.png",
		"sect": "衡山派",
		"tier": 2,
		"weapon": "轻剑",
		"description": "攻击后，若本次攻击中有且只有一名敌方被翻面，我与其交换位置。",
		"flavor": "衡山派三十六路回风落雁剑中的第十七招，莫大先生曾用此式一剑削断七只茶杯，而茶杯一只不倒。",
		"powers": [6, 8, 6, 2],
		"abilities": [{
			"triggers": [{
				"event": TRIGGER_CARD_AFTER_ATTACK,
				"conditions": [{"type": CONDITION_ATTACKER_CARD_IS_SELF}],
				"actions": [{
					"type": ACTION_FOR_EACH_SELECTED_CARD,
					"selector": {
						"zones": [CARD_ZONE_BOARD],
						"conditions": [
							{"type": CONDITION_SELECTED_CARD_FLIPPED_BY_CURRENT_ATTACK},
							{"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
						],
						"required_count": 1,
					},
					"actions": [{"type": ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE}],
				}],
			}],
		}],
	},
	&"YiJianLuo9Yan3": {
		"id": &"YiJianLuo9Yan3",
		"glyph": "一剑落九雁",
		"picture": "res://pics/LKT010_494.png",
		"sect": "衡山派",
		"tier": 3,
		"weapon": "轻剑",
		"description": "攻击后，若本次攻击中有且只有一名敌方被翻面，我与其交换位置，然后发起攻击。",
		"flavor": "衡山派三十六路回风落雁剑中的第十七招，莫大先生曾用此式一剑削断七只茶杯，而茶杯一只不倒。",
		"powers": [6, 8, 6, 2],
		"abilities": [{
			"triggers": [{
				"event": TRIGGER_CARD_AFTER_ATTACK,
				"conditions": [{"type": CONDITION_ATTACKER_CARD_IS_SELF}],
				"actions": [
					{
						"type": ACTION_FOR_EACH_SELECTED_CARD,
						"selector": {
							"zones": [CARD_ZONE_BOARD],
							"conditions": [
								{"type": CONDITION_SELECTED_CARD_FLIPPED_BY_CURRENT_ATTACK},
								{"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
							],
							"required_count": 1,
						},
						"actions": [{"type": ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE}],
						"on_invalid_context": STOP_RULE,
					},
					{"type": ACTION_STANDARD_ATTACK_WITH_SELF},
				],
			}],
		}],
	},
	&"TianZhuYunQi2": {
		"id": &"TianZhuYunQi2",
		"glyph": "天柱云气",
		"picture": "res://pics/LKT010_561.png",
		"sect": "衡山派",
		"tier": 2,
		"weapon": "轻剑",
		"description": "敌方在相邻进场时，我向首个相邻空格移动。",
		"flavor": "天柱剑法的精要所在，主要是从云雾中变化出来，极尽诡奇之能事，动向无定，不可捉摸。",
		"powers": [1, 1, 6, 1],
		"abilities": [{
			"triggers": [{
				"event": TRIGGER_CARD_SUMMONED,
				"conditions": [
					{"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
					{"type": CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE},
					{"type": CONDITION_SOURCE_HAS_ADJACENT_EMPTY_CELL},
				],
				"actions": [{"type": ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY}],
			}],
		}],
	},
	&"TianZhuYunQi3": {
		"id": &"TianZhuYunQi3",
		"glyph": "天柱云气",
		"picture": "res://pics/LKT010_561.png",
		"sect": "衡山派",
		"tier": 3,
		"weapon": "轻剑",
		"description": "敌方在相邻进场时，我向首个相邻空格移动，抽一张牌。",
		"flavor": "天柱剑法的精要所在，主要是从云雾中变化出来，极尽诡奇之能事，动向无定，不可捉摸。",
		"powers": [1, 1, 6, 1],
		"abilities": [{
			"triggers": [{
				"event": TRIGGER_CARD_SUMMONED,
				"conditions": [
					{"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
					{"type": CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE},
					{"type": CONDITION_SOURCE_HAS_ADJACENT_EMPTY_CELL},
				],
				"actions": [
					{"type": ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY, "on_invalid_context": STOP_RULE},
					{"type": ACTION_DRAW_CARDS, "amount": 1},
				],
			}],
		}],
	},
	&"TianZhuYunQi4": {
		"id": &"TianZhuYunQi4",
		"glyph": "天柱云气",
		"picture": "res://pics/LKT010_561.png",
		"sect": "衡山派",
		"tier": 4,
		"weapon": "轻剑",
		"description": "敌方在相邻进场时，我向首个相邻空格移动，抽一张牌。我移动前，所有相邻敌方失去效果，直到当前回合结束。",
		"flavor": "天柱剑法的精要所在，主要是从云雾中变化出来，极尽诡奇之能事，动向无定，不可捉摸。",
		"powers": [1, 1, 6, 1],
		"abilities": [
			{
				"triggers": [{
					"event": TRIGGER_CARD_SUMMONED,
					"conditions": [
						{"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
						{"type": CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE},
						{"type": CONDITION_SOURCE_HAS_ADJACENT_EMPTY_CELL},
					],
					"actions": [
						{"type": ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY, "on_invalid_context": STOP_RULE},
						{"type": ACTION_DRAW_CARDS, "amount": 1},
					],
				}],
			},
			{
				"triggers": [{
					"event": CARD_BEFORE_MOVED,
					"conditions": [{"type": CONDITION_MOVING_CARD_IS_SELF}],
					"actions": [{
						"type": ACTION_FOR_EACH_SELECTED_CARD,
						"selector": {
							"zones": [CARD_ZONE_BOARD],
							"conditions": [
								{"type": CONDITION_SELECTED_CARD_IS_ENEMY},
								{"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
							],
						},
						"actions": [{"type": ACTION_TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES}],
					}],
				}],
			},
		],
	},
	&"JianFaQinYin1": {
		"id": &"JianFaQinYin1",
		"glyph": "剑发琴音",
		"picture": "res://pics/LKT010_556.png",
		"sect": "衡山派",
		"tier": 1,
		"weapon": "轻剑",
		"description": "进场后，若与直线上的敌方相距一个空位，移动至该空位。",
		"flavor": "莫大先生的绝技，所谓“琴中藏剑，剑发琴音”，手中短剑嗡嗡作响，犹如灵蛇颤动不绝，将对手裹在剑光之中。",
		"powers": [4, 5, 6, 7],
		"abilities": [],
	},
	&"JianFaQinYin2": {
		"id": &"JianFaQinYin2",
		"glyph": "剑发琴音",
		"picture": "res://pics/LKT010_556.png",
		"sect": "衡山派",
		"tier": 2,
		"weapon": "轻剑",
		"description": "进场后，若与直线上的敌方相距一个空位，移动至该空位。指定：移动至一个相邻空格，然后进行一个额外回合。",
		"flavor": "莫大先生的绝技，所谓“琴中藏剑，剑发琴音”，手中短剑嗡嗡作响，犹如灵蛇颤动不绝，将对手裹在剑光之中。",
		"powers": [4, 5, 6, 7],
		"starting_ki": 1,
		"abilities": [],
	},
	&"JianFaQinYin3": {
		"id": &"JianFaQinYin3",
		"glyph": "剑发琴音",
		"picture": "res://pics/LKT010_556.png",
		"sect": "衡山派",
		"tier": 3,
		"weapon": "轻剑",
		"description": "进场后，若与直线上的敌方相距一个空位，移动至该空位。我移动后，所有相邻敌方失去效果，直到当前回合结束。指定：移动至一个相邻空格，然后进行一个额外回合。",
		"flavor": "莫大先生的绝技，所谓“琴中藏剑，剑发琴音”，手中短剑嗡嗡作响，犹如灵蛇颤动不绝，将对手裹在剑光之中。",
		"powers": [4, 5, 6, 7],
		"starting_ki": 1,
		"abilities": [],
	},
	&"YanHuiZhuRong3": {
		"id": &"YanHuiZhuRong3",
		"glyph": "雁回祝融",
		"picture": "res://pics/LKT010_474.png",
		"sect": "衡山派",
		"tier": 3,
		"weapon": "轻剑",
		"description": "我翻面前，若手牌中有轻剑牌，我移回手牌，然后在相同位置打出最左侧的轻剑牌。",
		"flavor": "衡山五神剑中最为精深的招式，将祝融剑法数十招中的精奥之处融会简化而入一招，一招之中有攻有守，威力之强，为衡山剑法之冠。",
		"powers": [4, 3, 3, 3],
		"abilities": [],
	},
	&"YanHuiZhuRong4": {
		"id": &"YanHuiZhuRong4",
		"glyph": "雁回祝融",
		"picture": "res://pics/LKT010_474.png",
		"sect": "衡山派",
		"tier": 4,
		"weapon": "轻剑",
		"description": "我翻面前，若手牌中有轻剑牌，我移回手牌，然后在相同位置打出最左侧的轻剑牌。指定：选择一个友方，将其移回手牌，然后在相同位置生成我的复制。",
		"flavor": "衡山五神剑中最为精深的招式，将祝融剑法数十招中的精奥之处融会简化而入一招，一招之中有攻有守，威力之强，为衡山剑法之冠。",
		"powers": [4, 3, 3, 3],
		"starting_ki": 1,
		"abilities": [],
	},
	&"canghai_sandie": {
		"id": &"canghai_sandie",
		"glyph": "沧海三叠",
		"picture": "res://pics/LKT010_025.png",
		"sect": "听潮谷",
		"tier": 3,
		"weapon": "掌法",
		"description": "三重掌劲间隔而至，第一重开势，第二重乱息，第三重方显真正威力。",
		"flavor": "海上老船工最怕无风时忽然出现三道浪，因为那往往意味着听潮谷有人在远处试掌。",
		"powers": [7, 6, 5, 4],
		"abilities": [],
	},
	&"haitian_yizhang": {
		"id": &"haitian_yizhang",
		"glyph": "海天一掌",
		"picture": "res://pics/LKT010_026.png",
		"sect": "听潮谷",
		"tier": 4,
		"weapon": "掌法",
		"description": "心息与潮声合一，将繁复变化归于平直一掌，势如海天相接而无处可避。",
		"flavor": "谷主闭关之处面朝东海，门前没有守卫，只有一道永远不会越过门槛的潮线。",
		"powers": [8, 5, 7, 6],
		"abilities": [],
	},
	&"zhujian_cangfeng": {
		"id": &"zhujian_cangfeng",
		"glyph": "竹简藏锋",
		"picture": "res://pics/LKT010_027.png",
		"sect": "白鹿书院",
		"tier": 1,
		"weapon": "奇门",
		"description": "将细小机关藏入成束竹简，展开阵图时也能出其不意地牵制近身之敌。",
		"flavor": "书院借出的竹简总会如数归还，只是偶尔会多出一片无人认得字迹的新简。",
		"powers": [3, 5, 4, 6],
		"abilities": [],
	},
	&"luming_wenlu": {
		"id": &"luming_wenlu",
		"glyph": "鹿鸣问路",
		"picture": "res://pics/LKT010_028.png",
		"sect": "白鹿书院",
		"tier": 1,
		"weapon": "奇门",
		"description": "以声响和标记试探周围变化，逐步排除虚路，找到阵势中唯一的生门。",
		"flavor": "山中白鹿从不踏进死路。书院弟子跟随它们多年，却仍不明白究竟是谁在为谁引路。",
		"powers": [5, 4, 6, 3],
		"abilities": [],
	},
	&"jingwei_dingju": {
		"id": &"jingwei_dingju",
		"glyph": "经纬定局",
		"picture": "res://pics/LKT010_029.png",
		"sect": "白鹿书院",
		"tier": 2,
		"weapon": "奇门",
		"description": "以纵横线位划分战场，预先安排机关与退路，使对手的每一步都落入推演。",
		"flavor": "院中棋盘没有黑白子，只有长短不同的木筹，因为胜负从来不只分成两边。",
		"powers": [6, 7, 4, 5],
		"abilities": [],
	},
	&"zhishang_shanhe": {
		"id": &"zhishang_shanhe",
		"glyph": "纸上山河",
		"picture": "res://pics/LKT010_030.png",
		"sect": "白鹿书院",
		"tier": 2,
		"weapon": "奇门",
		"description": "将地形、敌我与时机绘入一卷阵图，以周密布置弥补正面力量的不足。",
		"flavor": "书院地窖藏着一幅从未完成的天下图，据说每当江湖格局改变，纸上便会自行多出一道墨痕。",
		"powers": [7, 5, 6, 4],
		"abilities": [],
	},
	&"gate_general": {
		"id": &"gate_general",
		"glyph": "关",
		"picture": "res://pics/LKT010_002.png",
		"sect": "",
		"tier": 1,
		"weapon": "",
		"description": "",
		"flavor": "",
		"powers": [7, 7, 7, 7],
		"abilities": [
			{
				"retained_on_flip": true,
				"triggers": [
					{
						"event": CARD_BE_ATTACKED,
						"conditions": [
							{"type": CONDITION_ATTACKER_CARD_IS_SELF},
						],
						"actions": [
							{"type": ACTION_EXILE_ATTACKED_CARD},
						],
					},
				],
			},
		],
	},
	&"meng_huo": {
		"id": &"meng_huo",
		"glyph": "孟",
		"picture": "res://pics/LKT010_003.png",
		"sect": "",
		"tier": 1,
		"weapon": "",
		"description": "",
		"flavor": "",
		"powers": [8, 7, 2, 3],
		"abilities": [
			{
				"triggers": [
					{
						"event": CARD_AFTER_FLIPPED,
						"conditions": [
							{"type": CONDITION_ATTACKER_CARD_IS_SELF},
						],
						"actions": [
							{"type": ACTION_GAIN_KI, "amount": 1},
						],
					},
					{
						"event": TRIGGER_END_OWNER_TURN,
						"conditions": [
							{"type": CONDITION_TURN_OWNER_IS_SELF},
							{"type": CONDITION_KI_AT_LEAST, "amount": 1},
						],
						"actions": [
							{"type": ACTION_SPEND_ALL_KI},
							{"type": ACTION_REQUEST_EXTRA_TURN},
						],
					},
				],
			},
		],
	},
}


static func has_card(card_id: StringName) -> bool:
	return _CARD_DEFINITIONS.has(card_id)


static func get_all_card_ids() -> Array[StringName]:
	return ALL_CARD_IDS.duplicate()


static func get_definition(card_id: StringName) -> Dictionary:
	assert(has_card(card_id), "Unknown card ID: %s" % card_id)
	var definition: Dictionary = _CARD_DEFINITIONS.get(card_id, {})
	return definition.duplicate(true)


static func create_instance(
	card_id: StringName,
	original_owner: int,
	instance_id: StringName
) -> Dictionary:
	var definition: Dictionary = get_definition(card_id)
	return {
		"instance_id": instance_id,
		"card_id": card_id,
		"glyph": String(definition["glyph"]),
		"picture": String(definition["picture"]),
		"sect": String(definition["sect"]),
		"tier": int(definition["tier"]),
		"weapon": String(definition["weapon"]),
		"description": String(definition["description"]),
		"flavor": String(definition["flavor"]),
		"powers": (definition["powers"] as Array).duplicate(),
		"original_owner": original_owner,
		"ki": int(definition.get("starting_ki", 0)),
		"active_abilities": _normalize_abilities(definition["abilities"] as Array),
		"revealed_to_owner_ids": [original_owner],
	}


static func validate_ability(ability: Dictionary, card_id: StringName = &"fixture") -> Array[String]:
	var errors: Array[String] = []
	_validate_ability(card_id, ability, errors)
	return errors


static func validate_definition(
	definition: Dictionary,
	card_id: StringName = &"fixture"
) -> Array[String]:
	var errors: Array[String] = []
	_validate_definition(card_id, definition, errors)
	return errors


static func validate_catalog() -> Array[String]:
	var errors: Array[String] = []
	var observed_ids: Dictionary = {}
	for card_id: StringName in ALL_CARD_IDS:
		if observed_ids.has(card_id):
			errors.append("Duplicate catalog ID: %s" % card_id)
			continue
		observed_ids[card_id] = true
		if not _CARD_DEFINITIONS.has(card_id):
			errors.append("Missing definition for ID: %s" % card_id)
			continue
		_validate_definition(card_id, _CARD_DEFINITIONS[card_id] as Dictionary, errors)
	for raw_key: Variant in _CARD_DEFINITIONS.keys():
		var definition_id := StringName(raw_key)
		if not observed_ids.has(definition_id):
			errors.append("Definition is absent from ALL_CARD_IDS: %s" % definition_id)
	return errors


static func _validate_definition(
	card_id: StringName,
	definition: Dictionary,
	errors: Array[String]
) -> void:
	if card_id == &"":
		errors.append("Card ID cannot be empty")
	if StringName(definition.get("id", &"")) != card_id:
		errors.append("Definition ID does not match key: %s" % card_id)
	if definition.has("name"):
		errors.append("Card %s still declares retired name metadata" % card_id)
	var glyph_value: Variant = definition.get("glyph", null)
	if typeof(glyph_value) != TYPE_STRING:
		errors.append("Card %s requires a String glyph" % card_id)
	else:
		var glyph_length: int = (glyph_value as String).length()
		if glyph_length < 1 or glyph_length > 7:
			errors.append("Card %s glyph must contain 1 to 7 characters" % card_id)
	var picture_value: Variant = definition.get("picture", null)
	if typeof(picture_value) != TYPE_STRING or String(picture_value).is_empty():
		errors.append("Card %s requires a non-empty String picture" % card_id)
	elif not ResourceLoader.exists(String(picture_value)):
		errors.append("Card %s picture resource does not exist: %s" % [card_id, picture_value])
	for metadata_key: StringName in [&"sect", &"weapon", &"description", &"flavor"]:
		if not definition.has(metadata_key) or typeof(definition[metadata_key]) != TYPE_STRING:
			errors.append("Card %s requires String metadata %s" % [card_id, metadata_key])
	var tier_value: Variant = definition.get("tier", null)
	if typeof(tier_value) != TYPE_INT or int(tier_value) < 1:
		errors.append("Card %s requires an integer tier of at least 1" % card_id)
	var powers: Array = definition.get("powers", [])
	if powers.size() != 4:
		errors.append("Card %s requires four powers" % card_id)
	for power: Variant in powers:
		if typeof(power) != TYPE_INT:
			errors.append("Card %s has a non-integer power" % card_id)
	if definition.has("effects"):
		errors.append("Card %s still declares retired effects data" % card_id)
	var abilities_value: Variant = definition.get("abilities", null)
	var starting_ki: Variant = definition.get("starting_ki", 0)
	if typeof(starting_ki) != TYPE_INT or int(starting_ki) < 0:
		errors.append("Card %s requires a non-negative integer starting_ki" % card_id)
	if not abilities_value is Array:
		errors.append("Card %s requires an abilities array" % card_id)
		return
	for ability_value: Variant in abilities_value as Array:
		if not ability_value is Dictionary:
			errors.append("Card %s has a non-dictionary ability" % card_id)
			continue
		var ability: Dictionary = ability_value
		_validate_ability(card_id, ability, errors)


static func _normalize_abilities(raw_abilities: Array) -> Array:
	var normalized_abilities: Array = []
	for ability_value: Variant in raw_abilities:
		normalized_abilities.append(normalize_ability(ability_value as Dictionary))
	return normalized_abilities


static func normalize_ability(raw_ability: Dictionary) -> Dictionary:
	var ability: Dictionary = raw_ability.duplicate(true)
	if not ability.has("retained_on_flip"):
		ability["retained_on_flip"] = false
	for trigger_value: Variant in ability.get("triggers", []):
		if not trigger_value is Dictionary:
			continue
		_normalize_nested_grants((trigger_value as Dictionary).get("actions", []))
	if ability.has("activation") and ability["activation"] is Dictionary:
		_normalize_nested_grants((ability["activation"] as Dictionary).get("actions", []))
	return ability


static func _normalize_nested_grants(actions_value: Variant) -> void:
	if not actions_value is Array:
		return
	for action_value: Variant in actions_value as Array:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		if StringName(action.get("type", &"")) in [
			ACTION_GRANT_TRIGGER_CARD_ABILITY,
			ACTION_GRANT_ABILITY_TO_SELF,
		]:
			var granted_value: Variant = action.get("ability", null)
			if granted_value is Dictionary:
				action["ability"] = normalize_ability(granted_value as Dictionary)
		_normalize_nested_grants(action.get("actions", []))


static func _validate_ability(
	card_id: StringName,
	ability: Dictionary,
	errors: Array[String]
) -> void:
	if ability.has("id"):
		errors.append("Card %s ability must not declare an id" % card_id)
	for key: Variant in ability.keys():
		if StringName(key) not in [&"retained_on_flip", &"triggers", &"activation", &"modifiers"]:
			errors.append("Card %s ability has unsupported field %s" % [card_id, key])
	if ability.has("retained_on_flip") and typeof(ability["retained_on_flip"]) != TYPE_BOOL:
		errors.append("Card %s ability has non-Boolean retained_on_flip" % card_id)
	if not ability.has("triggers") and not ability.has("activation") and not ability.has("modifiers"):
		errors.append("Card %s ability requires triggers, activation, or modifiers" % card_id)
	if ability.has("triggers"):
		_validate_triggers(card_id, ability["triggers"], errors)
	if ability.has("activation"):
		_validate_activation(card_id, ability["activation"], errors)
	if ability.has("modifiers"):
		_validate_modifiers(card_id, ability["modifiers"], errors)


static func _validate_modifiers(card_id: StringName, modifiers_value: Variant, errors: Array[String]) -> void:
	if not modifiers_value is Array or (modifiers_value as Array).is_empty():
		errors.append("Card %s modifier ability requires a non-empty modifier array" % card_id)
		return
	for modifier_value: Variant in modifiers_value as Array:
		if not modifier_value is Dictionary:
			errors.append("Card %s has a non-dictionary modifier" % card_id)
			continue
		var modifier: Dictionary = modifier_value
		var modifier_type := StringName(modifier.get("type", &""))
		if modifier_type not in KNOWN_MODIFIERS:
			errors.append("Card %s uses unknown modifier %s" % [card_id, modifier_type])
		var allowed_keys: Array[StringName] = [&"type"]
		if modifier_type == MODIFIER_DEFENDING_POWER_OVERRIDE:
			allowed_keys.append(&"value")
			var value: Variant = modifier.get("value", null)
			if typeof(value) != TYPE_INT or int(value) < 0:
				errors.append("Card %s modifier %s requires a non-negative integer value" % [card_id, modifier_type])
		for key: Variant in modifier.keys():
			if StringName(key) not in allowed_keys:
				errors.append("Card %s modifier %s has unsupported field %s" % [card_id, modifier_type, key])


static func _validate_triggers(card_id: StringName, trigger_value: Variant, errors: Array[String]) -> void:
	if not trigger_value is Array:
		errors.append("Card %s trigger ability requires a trigger array" % card_id)
		return
	var triggers: Array = trigger_value
	if triggers.is_empty():
		errors.append("Card %s trigger ability requires at least one trigger" % card_id)
		return
	for trigger_value_item: Variant in triggers:
		if not trigger_value_item is Dictionary:
			errors.append("Card %s has a non-dictionary trigger" % card_id)
			continue
		_validate_trigger(card_id, trigger_value_item as Dictionary, errors)


static func _validate_trigger(card_id: StringName, trigger: Dictionary, errors: Array[String]) -> void:
	var event_id := StringName(trigger.get("event", &""))
	if event_id not in KNOWN_TRIGGER_EVENTS:
		errors.append("Card %s uses unknown trigger event %s" % [card_id, event_id])
	for key: Variant in trigger.keys():
		if StringName(key) not in [&"event", &"conditions", &"actions"]:
			errors.append("Card %s trigger %s has unsupported field %s" % [card_id, event_id, key])
	var conditions_value: Variant = trigger.get("conditions", [])
	if not conditions_value is Array:
		errors.append("Card %s trigger %s requires a conditions array" % [card_id, event_id])
	else:
		for condition_value: Variant in conditions_value as Array:
			if not condition_value is Dictionary:
				errors.append("Card %s trigger %s has a non-dictionary condition" % [card_id, event_id])
				continue
			_validate_condition(card_id, "trigger %s" % event_id, condition_value as Dictionary, errors)
	var actions_value: Variant = trigger.get("actions", null)
	if not actions_value is Array or (actions_value as Array).is_empty():
		errors.append("Card %s trigger %s requires a non-empty action array" % [card_id, event_id])
		return
	for action_value: Variant in actions_value as Array:
		if not action_value is Dictionary:
			errors.append("Card %s trigger %s has a non-dictionary action" % [card_id, event_id])
			continue
		_validate_action(card_id, "trigger %s" % event_id, action_value as Dictionary, false, errors)


static func _validate_condition(
	card_id: StringName,
	context_name: String,
	condition: Dictionary,
	errors: Array[String]
) -> void:
	var condition_type := StringName(condition.get("type", &""))
	if condition_type not in KNOWN_TRIGGER_CONDITIONS:
		errors.append("Card %s %s uses unknown condition %s" % [card_id, context_name, condition_type])
		return
	var allowed_keys: Array[StringName] = [&"type"]
	if condition_type == CONDITION_KI_AT_LEAST:
		allowed_keys.append(&"amount")
		var threshold: Variant = condition.get("amount", null)
		if typeof(threshold) != TYPE_INT or int(threshold) < 0:
			errors.append("Card %s %s requires a non-negative integer ki_at_least amount" % [card_id, context_name])
	for key: Variant in condition.keys():
		if StringName(key) not in allowed_keys:
			errors.append("Card %s %s condition %s has unsupported field %s" % [card_id, context_name, condition_type, key])


static func _validate_activation(
	card_id: StringName,
	activation_value: Variant,
	errors: Array[String]
) -> void:
	if not activation_value is Dictionary:
		errors.append("Card %s activation must be a Dictionary" % card_id)
		return
	var activation: Dictionary = activation_value
	for key: Variant in activation.keys():
		if StringName(key) not in [&"input", &"target_rule", &"costs", &"actions"]:
			errors.append("Card %s activation has unsupported field %s" % [card_id, key])
	var input_id := StringName(activation.get("input", &""))
	if input_id not in KNOWN_ACTIVATION_INPUTS:
		errors.append("Card %s uses unknown activation input %s" % [card_id, input_id])
	var target_rule := StringName(activation.get("target_rule", &""))
	if target_rule not in KNOWN_TARGET_RULES:
		errors.append("Card %s uses unknown target rule %s" % [card_id, target_rule])
	var costs_value: Variant = activation.get("costs", null)
	if not costs_value is Array or (costs_value as Array).is_empty():
		errors.append("Card %s activation requires a non-empty costs array" % card_id)
	else:
		for cost_value: Variant in costs_value as Array:
			if not cost_value is Dictionary:
				errors.append("Card %s activation has a non-dictionary cost" % card_id)
				continue
			_validate_action(card_id, "activation cost", cost_value as Dictionary, true, errors)
	var actions_value: Variant = activation.get("actions", null)
	if not actions_value is Array or (actions_value as Array).is_empty():
		errors.append("Card %s activation requires a non-empty actions array" % card_id)
	else:
		for action_value: Variant in actions_value as Array:
			if not action_value is Dictionary:
				errors.append("Card %s activation has a non-dictionary action" % card_id)
				continue
			_validate_action(card_id, "activation", action_value as Dictionary, false, errors)


static func _validate_action(
	card_id: StringName,
	context_name: String,
	action: Dictionary,
	is_cost: bool,
	errors: Array[String]
) -> void:
	var action_type := StringName(action.get("type", &""))
	if action_type not in KNOWN_ACTIONS:
		errors.append("Card %s %s uses unknown action %s" % [card_id, context_name, action_type])
		return
	if is_cost and action_type != ACTION_SPEND_KI:
		errors.append("Card %s activation uses unsupported cost action %s" % [card_id, action_type])
	var allowed_keys: Array[StringName] = [&"type", &"on_invalid_context"]
	if action_type in [ACTION_DRAW_CARDS, ACTION_GAIN_KI, ACTION_SPEND_KI, ACTION_ADD_POWERS]:
		allowed_keys.append(&"amount")
		var amount: Variant = action.get("amount", null)
		if typeof(amount) != TYPE_INT or int(amount) <= 0:
			errors.append("Card %s %s action %s requires a positive integer amount" % [card_id, context_name, action_type])
	if action_type == ACTION_ADD_POWERS and action.has("target"):
		allowed_keys.append(&"target")
		if StringName(action.get("target", &"")) != ACTION_TARGET_ABILITY_SOURCE:
			errors.append(
				"Card %s %s action %s requires a known target"
				% [card_id, context_name, action_type]
			)
	if action_type == ACTION_FLIP_SELF:
		allowed_keys.append(&"new_owner")
		if StringName(action.get("new_owner", &"")) != OWNER_ABILITY_SOURCE:
			errors.append(
				"Card %s %s action %s requires a known new_owner"
				% [card_id, context_name, action_type]
			)
	if action_type == ACTION_FOR_EACH_SELECTED_CARD:
		allowed_keys.append(&"selector")
		allowed_keys.append(&"actions")
		_validate_selector(card_id, context_name, action.get("selector", null), errors)
		var nested_actions_value: Variant = action.get("actions", null)
		if not nested_actions_value is Array or (nested_actions_value as Array).is_empty():
			errors.append("Card %s %s selection action requires a non-empty actions array" % [card_id, context_name])
		else:
			for nested_value: Variant in nested_actions_value as Array:
				if not nested_value is Dictionary:
					errors.append("Card %s %s selection action has a non-dictionary action" % [card_id, context_name])
					continue
				_validate_action(
					card_id,
					"%s selected card" % context_name,
					nested_value as Dictionary,
					false,
					errors
				)
	if action_type == ACTION_ADD_CARD_TO_HAND:
		allowed_keys.append(&"card_id")
		allowed_keys.append(&"recipient")
		var added_card_value: Variant = action.get("card_id", null)
		var added_card_id: StringName = (
			StringName(added_card_value)
			if typeof(added_card_value) in [TYPE_STRING, TYPE_STRING_NAME]
			else &""
		)
		if added_card_id not in ALL_CARD_IDS:
			errors.append(
				"Card %s %s action %s requires a known card_id"
				% [card_id, context_name, action_type]
			)
		var recipient_value: Variant = action.get("recipient", null)
		var recipient: StringName = (
			StringName(recipient_value)
			if typeof(recipient_value) in [TYPE_STRING, TYPE_STRING_NAME]
			else &""
		)
		if recipient not in KNOWN_RECIPIENTS:
			errors.append(
				"Card %s %s action %s requires a known recipient"
				% [card_id, context_name, action_type]
			)
	if action_type in [ACTION_REVEAL_HAND_CARDS, ACTION_ENABLE_FUTURE_DRAW_REVEAL]:
		allowed_keys.append(&"recipient")
		var reveal_recipient := StringName(action.get("recipient", &""))
		if reveal_recipient not in KNOWN_RECIPIENTS:
			errors.append("Card %s %s action %s requires a known recipient" % [card_id, context_name, action_type])
	if action_type == ACTION_REVEAL_HAND_CARDS:
		allowed_keys.append(&"filter")
		var reveal_filter := StringName(action.get("filter", &""))
		if reveal_filter not in KNOWN_REVEAL_FILTERS:
			errors.append("Card %s %s reveal action requires a known filter" % [card_id, context_name])
	if action_type in [ACTION_GRANT_TRIGGER_CARD_ABILITY, ACTION_GRANT_ABILITY_TO_SELF]:
		allowed_keys.append(&"ability")
		var granted_value: Variant = action.get("ability", null)
		if not granted_value is Dictionary:
			errors.append("Card %s %s grant action requires an ability Dictionary" % [card_id, context_name])
		else:
			_validate_ability(card_id, granted_value as Dictionary, errors)
	if action.has("on_invalid_context"):
		if StringName(action.get("on_invalid_context", &"")) != STOP_RULE:
			errors.append("Card %s %s action %s has invalid on_invalid_context policy" % [card_id, context_name, action_type])
	for key: Variant in action.keys():
		if StringName(key) not in allowed_keys:
			errors.append("Card %s %s action %s has unsupported field %s" % [card_id, context_name, action_type, key])


static func _validate_selector(
	card_id: StringName,
	context_name: String,
	selector_value: Variant,
	errors: Array[String]
) -> void:
	if not selector_value is Dictionary:
		errors.append("Card %s %s selection action requires a selector Dictionary" % [card_id, context_name])
		return
	var selector: Dictionary = selector_value
	for key: Variant in selector.keys():
		if StringName(key) not in [&"zones", &"conditions", &"limit", &"required_count"]:
			errors.append("Card %s %s selector has unsupported field %s" % [card_id, context_name, key])
	var zones_value: Variant = selector.get("zones", null)
	if not zones_value is Array or (zones_value as Array).is_empty():
		errors.append("Card %s %s selector requires a non-empty zones array" % [card_id, context_name])
	else:
		var seen_zones: Dictionary = {}
		for zone_value: Variant in zones_value as Array:
			if typeof(zone_value) != TYPE_STRING and typeof(zone_value) != TYPE_STRING_NAME:
				errors.append("Card %s %s selector has a non-string zone" % [card_id, context_name])
				continue
			var zone := StringName(zone_value)
			if zone not in KNOWN_CARD_ZONES:
				errors.append("Card %s %s selector uses unknown zone %s" % [card_id, context_name, zone])
			elif seen_zones.has(zone):
				errors.append("Card %s %s selector repeats zone %s" % [card_id, context_name, zone])
			seen_zones[zone] = true
	var conditions_value: Variant = selector.get("conditions", null)
	if not conditions_value is Array:
		errors.append("Card %s %s selector requires a conditions array" % [card_id, context_name])
	else:
		for condition_value: Variant in conditions_value as Array:
			if not condition_value is Dictionary:
				errors.append("Card %s %s selector has a non-dictionary condition" % [card_id, context_name])
				continue
			_validate_selector_condition(
				card_id,
				context_name,
				condition_value as Dictionary,
				errors
			)
	if selector.has("limit"):
		var limit_value: Variant = selector.get("limit", null)
		if typeof(limit_value) != TYPE_INT or int(limit_value) <= 0:
			errors.append("Card %s %s selector requires a positive integer limit" % [card_id, context_name])
	if selector.has("required_count"):
		var count_value: Variant = selector.get("required_count", null)
		if typeof(count_value) != TYPE_INT or int(count_value) <= 0:
			errors.append("Card %s %s selector requires a positive integer required_count" % [card_id, context_name])


static func _validate_selector_condition(
	card_id: StringName,
	context_name: String,
	condition: Dictionary,
	errors: Array[String]
) -> void:
	var condition_type := StringName(condition.get("type", &""))
	if condition_type not in KNOWN_SELECTOR_CONDITIONS:
		errors.append("Card %s %s selector uses unknown condition %s" % [card_id, context_name, condition_type])
		return
	var allowed_keys: Array[StringName] = [&"type"]
	if condition_type == CONDITION_SELECTED_CARD_WEAPON_IS:
		allowed_keys.append(&"weapon")
		var weapon_value: Variant = condition.get("weapon", null)
		if typeof(weapon_value) != TYPE_STRING or String(weapon_value).is_empty():
			errors.append("Card %s %s selector weapon condition requires a non-empty String weapon" % [card_id, context_name])
	for key: Variant in condition.keys():
		if StringName(key) not in allowed_keys:
			errors.append("Card %s %s selector condition %s has unsupported field %s" % [card_id, context_name, condition_type, key])
