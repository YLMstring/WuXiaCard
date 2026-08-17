class_name CardCatalog
extends RefCounted

const EFFECT_GATE_SELF_CASTRATION: StringName = &"self_castration"
const KNOWN_EFFECT_GATES: Array[StringName] = [
	EFFECT_GATE_SELF_CASTRATION,
]

const ACTIVATION_DRAG_TO_TARGET: StringName = &"drag_to_target"
const TARGET_ADJACENT_EMPTY_BOARD: StringName = &"adjacent_empty_board"
const TARGET_ADJACENT_ALLY_BOARD: StringName = &"adjacent_ally_board"
const TARGET_ADJACENT_ENEMY_BOARD: StringName = &"adjacent_enemy_board"
const TARGET_OTHER_ALLY_BOARD: StringName = &"other_ally_board"
const TARGET_ENEMY_HAND_CARD: StringName = &"enemy_hand_card"
const TARGET_ANY_EMPTY_BOARD: StringName = &"any_empty_board"
const TARGET_ANY_ENEMY_BOARD: StringName = &"any_enemy_board"
const TRIGGER_CARD_SUMMONED: StringName = &"card_summoned"
const TRIGGER_CARD_BEFORE_SUMMONED: StringName = &"card_before_summoned"
const TRIGGER_CARD_AFTER_SUMMONED: StringName = &"card_after_summoned"
const TRIGGER_CARD_AFTER_ATTACK: StringName = &"card_after_attack"
const CARD_BE_ATTACKED: StringName = &"card_be_attacked"
const CARD_BEFORE_EXILED: StringName = &"card_before_exiled"
const CARD_AFTER_DRAWN: StringName = &"card_after_drawn"
const CARD_BEFORE_MOVED: StringName = &"card_before_moved"
const CARD_AFTER_MOVED: StringName = &"card_after_moved"
const CARD_BEFORE_FLIPPED: StringName = &"card_before_flipped"
const CARD_AFTER_FLIPPED: StringName = &"card_after_flipped"
const CARD_AFTER_TARGETED_ACTIVATION: StringName = &"card_after_targeted_activation"
const CARD_KI_CHANGED: StringName = &"card_ki_changed"
const TRIGGER_START_OWNER_TURN: StringName = &"start_owner_turn"
const TRIGGER_END_OWNER_TURN: StringName = &"end_owner_turn"
const TRIGGER_BEFORE_DUEL_END: StringName = &"before_duel_end"
const CONDITION_KI_AT_LEAST: StringName = &"ki_at_least"
const CONDITION_TRIGGER_CARD_IS_ALLY: StringName = &"trigger_card_is_ally"
const CONDITION_TRIGGER_CARD_IS_ENEMY: StringName = &"trigger_card_is_enemy"
const CONDITION_TRIGGER_CARD_IN_RANGE: StringName = &"trigger_card_in_range"
const CONDITION_TRIGGER_CARD_IS_SELF: StringName = &"trigger_card_is_self"
const CONDITION_ATTACKER_CARD_IS_SELF: StringName = &"attacker_card_is_self"
const CONDITION_TURN_OWNER_IS_SELF: StringName = &"turn_owner_is_self"
const CONDITION_TRIGGER_CARD_REVEALED_TO_SELF: StringName = &"trigger_card_revealed_to_self"
const CONDITION_TRIGGER_CARD_WAS_ENEMY: StringName = &"trigger_card_was_enemy"
const CONDITION_ATTACKER_CARD_IS_ENEMY: StringName = &"attacker_card_is_enemy"
const CONDITION_ATTACKER_CARD_IS_OTHER_ALLY: StringName = &"attacker_card_is_other_ally"
const CONDITION_DRAWN_CARD_IS_ENEMY: StringName = &"drawn_card_is_enemy"
const CONDITION_ATTACK_FLIPPED_ALLY_IN_RANGE: StringName = &"attack_flipped_ally_in_range"
const CONDITION_ATTACK_FLIPPED_ENEMY: StringName = &"attack_flipped_enemy"
const CONDITION_ATTACKED_CARD_IS_SELF: StringName = &"attacked_card_is_self"
const CONDITION_OWNER_DID_NOT_WIN: StringName = &"owner_did_not_win"
const CONDITION_TRIGGER_CARD_ORIGINAL_OWNER_IS_SELF: StringName = &"trigger_card_original_owner_is_self"
const CONDITION_MOVING_CARD_IS_SELF: StringName = &"moving_card_is_self"
const CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE: StringName = &"trigger_card_adjacent_to_source"
const CONDITION_SOURCE_HAS_ADJACENT_EMPTY_CELL: StringName = &"source_has_adjacent_empty_cell"
const CONDITION_SOURCE_HAS_EMPTY_BETWEEN_ENEMY: StringName = &"source_has_empty_between_enemy"
const CONDITION_KI_CHANGED_CARD_IS_SELF: StringName = &"ki_changed_card_is_self"
const CONDITION_KI_REACHED_ZERO: StringName = &"ki_reached_zero"
const CONDITION_SELECTED_CARD_IS_ALLY: StringName = &"selected_card_is_ally"
const CONDITION_SELECTED_CARD_IS_ENEMY: StringName = &"selected_card_is_enemy"
const CONDITION_SELECTED_CARD_WEAPON_IS: StringName = &"selected_card_weapon_is"
const CONDITION_SELECTED_CARD_IS_NOT_SOURCE: StringName = &"selected_card_is_not_source"
const CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE: StringName = &"selected_card_adjacent_to_source"
const CONDITION_SELECTED_CARD_SURROUNDED_BY_ALLIES: StringName = &"selected_card_surrounded_by_allies"
const CONDITION_SELECTED_CARD_ORIGINAL_OWNER_IS_SELF: StringName = &"selected_card_original_owner_is_self"
const CONDITION_SELECTED_CARD_ORIGINAL_OWNER_IS_ENEMY: StringName = &"selected_card_original_owner_is_enemy"
const CONDITION_SELECTED_CARD_FLIPPED_BY_CURRENT_ATTACK: StringName = &"selected_card_flipped_by_current_attack"
const CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE: StringName = &"selected_card_powers_can_change"
const CONDITION_SELECTED_CARD_HAS_NONZERO_POWER: StringName = &"selected_card_has_nonzero_power"
const CONDITION_SELECTED_CARD_IS_PREVIOUS_HAND_PLAY: StringName = &"selected_card_is_previous_hand_play"
const CONDITION_ATTACK_IS_NOT_REPEAT: StringName = &"attack_is_not_repeat"
const CONDITION_ACTIVATION_OWNER_IS_ALLY: StringName = &"activation_owner_is_ally"
const ACTION_DRAW_CARDS: StringName = &"draw_cards"
const ACTION_EXILE_CARD: StringName = &"exile_card"
const ACTION_ATTACK_TRIGGER_CARD: StringName = &"attack_trigger_card"
const ACTION_GAIN_KI: StringName = &"gain_ki"
const ACTION_SPEND_KI: StringName = &"spend_ki"
const ACTION_SPEND_ALL_KI: StringName = &"spend_all_ki"
const ACTION_GRANT_EXTRA_CARD_PLAY: StringName = &"grant_extra_card_play"
const ACTION_MOVE_SELF_TO_TARGET: StringName = &"move_self_to_target"
const ACTION_SWAP_SELF_WITH_TARGET: StringName = &"swap_self_with_target"
const ACTION_STANDARD_ATTACK_WITH_SELF: StringName = &"standard_attack_with_self"
const ACTION_STANDARD_ATTACK_WITH_CARD: StringName = &"standard_attack_with_card"
const ACTION_FOR_EACH_SELECTED_CARD: StringName = &"for_each_selected_card"
const ACTION_CHANGE_POWERS: StringName = &"change_powers"
const ACTION_ADD_CARD_TO_HAND: StringName = &"add_card_to_hand"
const ACTION_REVEAL_HAND_CARDS: StringName = &"reveal_hand_cards"
const ACTION_ENABLE_FUTURE_DRAW_REVEAL: StringName = &"enable_future_draw_reveal"
const ACTION_GRANT_TRIGGER_CARD_ABILITY: StringName = &"grant_trigger_card_ability"
const ACTION_GRANT_ABILITY_TO_SELF: StringName = &"grant_ability_to_self"
const ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE: StringName = &"self_swapped_with_ability_source"
const ACTION_PREVENT_TRIGGER_FLIP: StringName = &"prevent_trigger_flip"
const ACTION_REMOVE_THIS_ABILITY: StringName = &"remove_this_ability"
const ACTION_FLIP_SELF: StringName = &"flip_self"
const ACTION_RETURN_CARD_TO_HAND: StringName = &"return_card_to_hand"
const ACTION_SUMMON_CARD: StringName = &"summon_card"
const ACTION_EXILE_SELF: StringName = &"exile_self"
const ACTION_RESUMMON_CARD_IN_PLACE: StringName = &"resummon_card_in_place"
const ACTION_TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES: StringName = &"temporarily_remove_non_retained_abilities"
const ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY: StringName = &"move_self_to_first_adjacent_empty"
const ACTION_MOVE_SELF_TO_FIRST_EMPTY_BETWEEN_ENEMY: StringName = &"move_self_to_first_empty_between_enemy"
const ACTION_REVEAL_CARD: StringName = &"reveal_card"
const ACTION_SWAP_SELF_WITH_TRIGGER_CARD: StringName = &"swap_self_with_trigger_card"
const ACTION_ADD_PENDING_NON_RETAINED_SUPPRESSION: StringName = &"add_pending_non_retained_suppression"
const CARD_REF_ABILITY_SOURCE: StringName = &"ability_source"
const CARD_REF_SELECTED_CARD: StringName = &"selected_card"
const CARD_REF_TRIGGER_CARD: StringName = &"trigger_card"
const CARD_SPEC_FRESH_COPY: StringName = &"fresh_copy"
const CELL_REF_INITIAL_CARD_CELL: StringName = &"initial_card_cell"
const CELL_REF_FIRST_ADJACENT_EMPTY: StringName = &"first_adjacent_empty"
const CELL_REF_ACTIVATION_TARGET: StringName = &"activation_target"
const OWNER_ABILITY_SOURCE: StringName = &"ability_source"
const OWNER_CARD_CURRENT: StringName = &"card_current_owner"
const OWNER_OPPONENT_OF_ABILITY_SOURCE: StringName = &"opponent_of_ability_source"
const VALUE_CARD_COUNT: StringName = &"card_count"
const REVEAL_FILTER_ALL: StringName = &"all"
const REVEAL_FILTER_REMEMBERED: StringName = &"remembered"
const MODIFIER_DEFENDING_POWER_OVERRIDE: StringName = &"defending_power_override"
const MODIFIER_ATTACK_REQUIRES_OTHER_ALLY: StringName = &"attack_requires_other_ally"
const MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE: StringName = &"defending_power_uses_minimum_side"
const MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO: StringName = &"orthogonal_attack_range_two"
const MODIFIER_ENEMY_ATTACKS_ALL: StringName = &"enemy_attacks_all"
const MODIFIER_POWER_COMPARISON_REVERSED: StringName = &"power_comparison_reversed"
const MODIFIER_ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES: StringName = &"adjacent_enemy_summon_attacks_allies"
const MODIFIER_UNLIMITED_ATTACK_RANGE: StringName = &"unlimited_attack_range"
const MODIFIER_NON_ORTHOGONAL_ATTACK_ANY_AXIS: StringName = &"non_orthogonal_attack_any_axis"
const MODIFIER_STANDARD_ATTACK_FIRST_LEGAL_TARGET: StringName = &"standard_attack_first_legal_target"
const MODIFIER_ENEMY_CANNOT_ATTACK_DURING_OWNER_TURN: StringName = &"enemy_cannot_attack_during_owner_turn"
const ATTACK_TARGET_ENEMIES_ONLY: StringName = &"enemies_only"
const ATTACK_TARGET_ALLIES_ONLY: StringName = &"allies_only"
const ATTACK_TARGET_ALL: StringName = &"all"
const CARD_ZONE_HAND: StringName = &"hand"
const CARD_ZONE_BOARD: StringName = &"board"
const CARD_ZONE_REMOVED: StringName = &"removed"
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
	TARGET_OTHER_ALLY_BOARD,
	TARGET_ENEMY_HAND_CARD,
	TARGET_ANY_EMPTY_BOARD,
	TARGET_ANY_ENEMY_BOARD,
]
const KNOWN_TRIGGER_EVENTS: Array[StringName] = [
	TRIGGER_CARD_SUMMONED,
	TRIGGER_CARD_BEFORE_SUMMONED,
	TRIGGER_CARD_AFTER_SUMMONED,
	TRIGGER_CARD_AFTER_ATTACK,
	CARD_BE_ATTACKED,
	CARD_BEFORE_EXILED,
	CARD_AFTER_DRAWN,
	CARD_BEFORE_MOVED,
	CARD_AFTER_MOVED,
	CARD_BEFORE_FLIPPED,
	CARD_AFTER_FLIPPED,
	CARD_AFTER_TARGETED_ACTIVATION,
	CARD_KI_CHANGED,
	TRIGGER_START_OWNER_TURN,
	TRIGGER_END_OWNER_TURN,
	TRIGGER_BEFORE_DUEL_END,
]
const KNOWN_TRIGGER_CONDITIONS: Array[StringName] = [
	CONDITION_KI_AT_LEAST,
	CONDITION_TRIGGER_CARD_IS_ALLY,
	CONDITION_TRIGGER_CARD_IS_ENEMY,
	CONDITION_TRIGGER_CARD_IN_RANGE,
	CONDITION_TRIGGER_CARD_IS_SELF,
	CONDITION_ATTACKER_CARD_IS_SELF,
	CONDITION_TURN_OWNER_IS_SELF,
	CONDITION_TRIGGER_CARD_REVEALED_TO_SELF,
	CONDITION_TRIGGER_CARD_WAS_ENEMY,
	CONDITION_ATTACKER_CARD_IS_ENEMY,
	CONDITION_ATTACKER_CARD_IS_OTHER_ALLY,
	CONDITION_DRAWN_CARD_IS_ENEMY,
	CONDITION_ATTACK_FLIPPED_ALLY_IN_RANGE,
	CONDITION_ATTACK_FLIPPED_ENEMY,
	CONDITION_ATTACKED_CARD_IS_SELF,
	CONDITION_OWNER_DID_NOT_WIN,
	CONDITION_TRIGGER_CARD_ORIGINAL_OWNER_IS_SELF,
	CONDITION_MOVING_CARD_IS_SELF,
	CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE,
	CONDITION_SOURCE_HAS_ADJACENT_EMPTY_CELL,
	CONDITION_SOURCE_HAS_EMPTY_BETWEEN_ENEMY,
	CONDITION_KI_CHANGED_CARD_IS_SELF,
	CONDITION_KI_REACHED_ZERO,
	CONDITION_ATTACK_IS_NOT_REPEAT,
	CONDITION_ACTIVATION_OWNER_IS_ALLY,
]
const KNOWN_SELECTOR_CONDITIONS: Array[StringName] = [
	CONDITION_SELECTED_CARD_IS_ALLY,
	CONDITION_SELECTED_CARD_IS_ENEMY,
	CONDITION_SELECTED_CARD_WEAPON_IS,
	CONDITION_SELECTED_CARD_IS_NOT_SOURCE,
	CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE,
	CONDITION_SELECTED_CARD_SURROUNDED_BY_ALLIES,
	CONDITION_SELECTED_CARD_ORIGINAL_OWNER_IS_SELF,
	CONDITION_SELECTED_CARD_ORIGINAL_OWNER_IS_ENEMY,
	CONDITION_SELECTED_CARD_FLIPPED_BY_CURRENT_ATTACK,
	CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE,
	CONDITION_SELECTED_CARD_HAS_NONZERO_POWER,
	CONDITION_SELECTED_CARD_IS_PREVIOUS_HAND_PLAY,
]
const KNOWN_CARD_ZONES: Array[StringName] = [CARD_ZONE_HAND, CARD_ZONE_BOARD, CARD_ZONE_REMOVED]
const KNOWN_ACTIONS: Array[StringName] = [
	ACTION_DRAW_CARDS,
	ACTION_EXILE_CARD,
	ACTION_ATTACK_TRIGGER_CARD,
	ACTION_GAIN_KI,
	ACTION_SPEND_KI,
	ACTION_SPEND_ALL_KI,
	ACTION_GRANT_EXTRA_CARD_PLAY,
	ACTION_MOVE_SELF_TO_TARGET,
	ACTION_SWAP_SELF_WITH_TARGET,
	ACTION_STANDARD_ATTACK_WITH_SELF,
	ACTION_STANDARD_ATTACK_WITH_CARD,
	ACTION_FOR_EACH_SELECTED_CARD,
	ACTION_CHANGE_POWERS,
	ACTION_ADD_CARD_TO_HAND,
	ACTION_REVEAL_HAND_CARDS,
	ACTION_ENABLE_FUTURE_DRAW_REVEAL,
	ACTION_GRANT_TRIGGER_CARD_ABILITY,
	ACTION_GRANT_ABILITY_TO_SELF,
	ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE,
	ACTION_PREVENT_TRIGGER_FLIP,
	ACTION_REMOVE_THIS_ABILITY,
	ACTION_FLIP_SELF,
	ACTION_RETURN_CARD_TO_HAND,
	ACTION_SUMMON_CARD,
	ACTION_EXILE_SELF,
	ACTION_RESUMMON_CARD_IN_PLACE,
	ACTION_TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES,
	ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY,
	ACTION_MOVE_SELF_TO_FIRST_EMPTY_BETWEEN_ENEMY,
	ACTION_REVEAL_CARD,
	ACTION_SWAP_SELF_WITH_TRIGGER_CARD,
	ACTION_ADD_PENDING_NON_RETAINED_SUPPRESSION,
]
const KNOWN_CARD_REFERENCES: Array[StringName] = [
	CARD_REF_ABILITY_SOURCE,
	CARD_REF_SELECTED_CARD,
	CARD_REF_TRIGGER_CARD,
]
const KNOWN_OWNER_REFERENCES: Array[StringName] = [
	OWNER_ABILITY_SOURCE,
	OWNER_CARD_CURRENT,
	OWNER_OPPONENT_OF_ABILITY_SOURCE,
]
const KNOWN_VALUE_TYPES: Array[StringName] = [VALUE_CARD_COUNT]
const KNOWN_RECIPIENTS: Array[StringName] = [RECIPIENT_SELF, RECIPIENT_OPPONENT]
const KNOWN_REVEAL_FILTERS: Array[StringName] = [REVEAL_FILTER_ALL, REVEAL_FILTER_REMEMBERED]
const KNOWN_MODIFIERS: Array[StringName] = [
	MODIFIER_DEFENDING_POWER_OVERRIDE,
	MODIFIER_ATTACK_REQUIRES_OTHER_ALLY,
	MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE,
	MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO,
	MODIFIER_ENEMY_ATTACKS_ALL,
	MODIFIER_POWER_COMPARISON_REVERSED,
	MODIFIER_ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES,
	MODIFIER_UNLIMITED_ATTACK_RANGE,
	MODIFIER_NON_ORTHOGONAL_ATTACK_ANY_AXIS,
	MODIFIER_STANDARD_ATTACK_FIRST_LEGAL_TARGET,
	MODIFIER_ENEMY_CANNOT_ATTACK_DURING_OWNER_TURN,
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
	&"TaiZuChangQuan",
	&"TaiJiSanHuan4",
	&"TaiJiSanHuan5",
	&"TaiJiDaKui5",
	&"TaiJiLuanHuan4",
	&"TaiJiLuanHuan5",
	&"TaiJiYinYang5",
	&"RaoZhiRouJian2",
	&"RaoZhiRouJian3",
	&"RaoZhiRouJian4",
	&"ShenMen13Jian1",
	&"ShenMen13Jian2",
	&"ShenMen13Jian3",
	&"WuDangMianZhang1",
	&"WuDangMianZhang2",
	&"WuDangMianZhang3",
	&"HuZhuaJueHuSHou1",
	&"HuZhuaJueHuSHou2",
	&"HuZhuaJueHuSHou3",
	&"HuZhuaJueHuSHou4",
	&"TuNaShu1",
	&"TuNaShu2",
	&"TuNaShu3",
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
	&"JianFaQinYin2",
	&"JianFaQinYin3",
	&"YanHuiZhuRong3",
	&"YanHuiZhuRong4",
	&"WanYueChaoZong1",
	&"WanYueChaoZong2",
	&"WanYueChaoZong3",
	&"WanYueChaoZong4",
	&"DaSongYangZhang1",
	&"DaSongYangZhang2",
	&"DaSongYangZhang3",
	&"DaSongYangZhang4",
	&"YinYangZhang3",
	&"YinYangZhang4",
	&"HanBinZhenQi3",
	&"HanBinZhenQi4",
	&"TianWaiYuLong2",
	&"TianWaiYuLong3",
	&"DuGu9Jian1",
	&"DuGu9Jian2",
	&"DuGu9Jian3",
	&"LeiZHenJian1",
	&"LeiZHenJian2",
	&"LeiZHenJian3",
	&"KuiHua1",
	&"KuiHua2",
	&"KuiHua3",
	&"KuiHua4",
	&"KuiHua0",
]

const HANBIN_POWER_BATCH: StringName = &"hanbin_frozen_turn"

const HANBIN_FROZEN_TURN: Dictionary = {
	"triggers": [{
		"event": TRIGGER_START_OWNER_TURN,
		"conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
		"actions": [
			{
				"type": ACTION_CHANGE_POWERS,
				"amount": -1,
				"card": CARD_REF_ABILITY_SOURCE,
				"power_change_batch_group": HANBIN_POWER_BATCH,
			},
			{
				"type": ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [CARD_ZONE_HAND],
					"conditions": [
						{"type": CONDITION_SELECTED_CARD_IS_ALLY},
						{"type": CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE},
					],
					"limit": 2,
				},
				"actions": [{
					"type": ACTION_CHANGE_POWERS,
					"amount": -1,
					"card": CARD_REF_SELECTED_CARD,
				}],
				"power_change_batch_group": HANBIN_POWER_BATCH,
			},
		],
	}],
}

const HANBIN_ACTIVATION: Dictionary = {
	"activation": {
		"input": ACTIVATION_DRAG_TO_TARGET,
		"target_rule": TARGET_ENEMY_HAND_CARD,
		"costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
		"actions": [
			{
				"type": ACTION_CHANGE_POWERS,
				"amount": -1,
				"card": CARD_REF_SELECTED_CARD,
			},
			{
				"type": ACTION_REVEAL_CARD,
				"card": CARD_REF_SELECTED_CARD,
				"observer": OWNER_ABILITY_SOURCE,
			},
		],
	},
}

const HANBIN_AFTER_FLIP_GRANT: Dictionary = {
	"triggers": [{
		"event": CARD_AFTER_FLIPPED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_GRANT_ABILITY_TO_SELF,
			"ability": HANBIN_FROZEN_TURN,
		}],
	}],
}

const HANBIN_LAST_KI_FLIP: Dictionary = {
	"triggers": [{
		"event": CARD_KI_CHANGED,
		"conditions": [
			{"type": CONDITION_KI_CHANGED_CARD_IS_SELF},
			{"type": CONDITION_KI_REACHED_ZERO},
		],
		"actions": [{
			"type": ACTION_FLIP_SELF,
			"new_owner": OWNER_OPPONENT_OF_ABILITY_SOURCE,
		}],
	}],
}

const TIANWAI_SWAP_ATTACK: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_SUMMONED,
		"conditions": [
			{"type": CONDITION_TRIGGER_CARD_IS_ALLY},
			{"type": CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE},
		],
		"actions": [
			{
				"type": ACTION_SWAP_SELF_WITH_TRIGGER_CARD,
				"on_invalid_context": STOP_RULE,
			},
			{"type": ACTION_STANDARD_ATTACK_WITH_SELF},
		],
	}],
}

const TIANWAI_POWER_SWAP_ATTACK: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_SUMMONED,
		"conditions": [
			{"type": CONDITION_TRIGGER_CARD_IS_ALLY},
			{"type": CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE},
		],
		"actions": [
			{
				"type": ACTION_CHANGE_POWERS,
				"amount": 1,
				"card": CARD_REF_TRIGGER_CARD,
			},
			{
				"type": ACTION_SWAP_SELF_WITH_TRIGGER_CARD,
				"on_invalid_context": STOP_RULE,
			},
			{"type": ACTION_STANDARD_ATTACK_WITH_SELF},
		],
	}],
}

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

const RAOZHI_LOCKED_ATTACK_MODIFIERS: Dictionary = {
	"retained_on_flip": true,
	"modifiers": [
		{"type": MODIFIER_UNLIMITED_ATTACK_RANGE},
		{"type": MODIFIER_NON_ORTHOGONAL_ATTACK_ANY_AXIS},
		{"type": MODIFIER_STANDARD_ATTACK_FIRST_LEGAL_TARGET},
	],
}

const WUDANG_EXILE_BEFORE_FLIP_UNTIL_OWN_FLIP: Dictionary = {
	"triggers": [
		{
			"event": CARD_BEFORE_FLIPPED,
			"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{"type": ACTION_EXILE_CARD, "card": CARD_REF_TRIGGER_CARD}],
		},
		{
			"event": CARD_AFTER_FLIPPED,
			"conditions": [{"type": CONDITION_ATTACKER_CARD_IS_SELF}],
			"actions": [{"type": ACTION_REMOVE_THIS_ABILITY}],
		},
	],
}

const WUDANG_FLIPPED_CARD_ATTACK: Dictionary = {
	"triggers": [{
		"event": CARD_AFTER_FLIPPED,
		"conditions": [{"type": CONDITION_ATTACKER_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_STANDARD_ATTACK_WITH_CARD,
			"card": CARD_REF_TRIGGER_CARD,
		}],
	}],
}

const SHENMEN_OWNER_TURN_ATTACK_LOCK: Dictionary = {
	"modifiers": [{"type": MODIFIER_ENEMY_CANNOT_ATTACK_DURING_OWNER_TURN}],
}

const RAOZHI_TARGETED_ACTIVATION_REACTION: Dictionary = {
	"triggers": [{
		"event": CARD_AFTER_TARGETED_ACTIVATION,
		"conditions": [{"type": CONDITION_ACTIVATION_OWNER_IS_ALLY}],
		"actions": [{"type": ACTION_STANDARD_ATTACK_WITH_SELF}],
	}],
}

const QIXIN_SUMMON_REACTION: Dictionary = {
	"triggers": [
		{
			"event": TRIGGER_CARD_AFTER_SUMMONED,
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
		"actions": [{
			"type": ACTION_RESUMMON_CARD_IN_PLACE,
			"card": CARD_REF_TRIGGER_CARD,
		}],
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
			"actions": [{
				"type": ACTION_RETURN_CARD_TO_HAND,
				"card": CARD_REF_SELECTED_CARD,
				"recipient": OWNER_ABILITY_SOURCE,
			}],
		}],
	}],
}

const WANHUA_COPY_TRIGGER: Dictionary = {
	"event": CARD_BE_ATTACKED,
	"conditions": [{"type": CONDITION_ATTACKED_CARD_IS_SELF}],
	"actions": [{
		"type": ACTION_SUMMON_CARD,
		"card": {
			"type": CARD_SPEC_FRESH_COPY,
			"of": CARD_REF_ABILITY_SOURCE,
		},
		"cell": {
			"type": CELL_REF_FIRST_ADJACENT_EMPTY,
			"card": CARD_REF_ABILITY_SOURCE,
		},
	}],
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
		"event": TRIGGER_CARD_SUMMONED,
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
				"type": ACTION_CHANGE_POWERS,
				"amount": 1,
				"card": CARD_REF_ABILITY_SOURCE,
			}],
		}],
	}],
}

const WANYUE_SELF_POWER: Dictionary = {
	"triggers": [
		{
			"event": TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{
				"type": ACTION_CHANGE_POWERS,
				"amount": {
					"type": VALUE_CARD_COUNT,
					"zone": CARD_ZONE_HAND,
					"owner": OWNER_ABILITY_SOURCE,
				},
				"card": CARD_REF_ABILITY_SOURCE,
			}],
		},
		{
			"event": TRIGGER_START_OWNER_TURN,
			"conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
			"actions": [{
				"type": ACTION_CHANGE_POWERS,
				"amount": -1,
				"card": CARD_REF_ABILITY_SOURCE,
			}],
		},
	],
}

const WANYUE_ADJACENT_ALLY_POWER: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_SUMMONED,
		"conditions": [
			{"type": CONDITION_TRIGGER_CARD_IS_ALLY},
			{"type": CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE},
		],
		"actions": [{
			"type": ACTION_CHANGE_POWERS,
			"amount": 1,
			"card": CARD_REF_TRIGGER_CARD,
		}],
	}],
}

const WANYUE_ADJACENT_ALLY_POWER_TWO: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_SUMMONED,
		"conditions": [
			{"type": CONDITION_TRIGGER_CARD_IS_ALLY},
			{"type": CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE},
		],
		"actions": [{
			"type": ACTION_CHANGE_POWERS,
			"amount": 2,
			"card": CARD_REF_TRIGGER_CARD,
		}],
	}],
}

const DASONGYANG_ADJACENT_ALLY_POWER: Dictionary = WANYUE_ADJACENT_ALLY_POWER

const DASONGYANG_ADJACENT_ALLY_POWER_TWO: Dictionary = WANYUE_ADJACENT_ALLY_POWER_TWO

const DASONGYANG_ADJACENT_ENEMY_POWER: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_SUMMONED,
		"conditions": [
			{"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
			{"type": CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE},
		],
		"actions": [{
			"type": ACTION_CHANGE_POWERS,
			"amount": -1,
			"card": CARD_REF_TRIGGER_CARD,
		}],
	}],
}

const DASONGYANG_ADJACENT_ENEMY_POWER_TWO: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_SUMMONED,
		"conditions": [
			{"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
			{"type": CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE},
		],
		"actions": [{
			"type": ACTION_CHANGE_POWERS,
			"amount": -2,
			"card": CARD_REF_TRIGGER_CARD,
		}],
	}],
}

const JIANFA_ENTRY_MOVE: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_SUMMONED,
		"conditions": [
			{"type": CONDITION_TRIGGER_CARD_IS_SELF},
			{"type": CONDITION_SOURCE_HAS_EMPTY_BETWEEN_ENEMY},
		],
		"actions": [{"type": ACTION_MOVE_SELF_TO_FIRST_EMPTY_BETWEEN_ENEMY}],
	}],
}

const JIANFA_ACTIVATION: Dictionary = {
	"activation": {
		"input": ACTIVATION_DRAG_TO_TARGET,
		"target_rule": TARGET_ADJACENT_EMPTY_BOARD,
		"costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
		"actions": [
			{"type": ACTION_MOVE_SELF_TO_TARGET, "on_invalid_context": STOP_RULE},
			{"type": ACTION_GRANT_EXTRA_CARD_PLAY, "amount": 1},
		],
	},
}

const JIANFA_MOVE_SUPPRESSION: Dictionary = {
	"triggers": [{
		"event": CARD_AFTER_MOVED,
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
}

const YANHUI_FLIP_REPLACEMENT: Dictionary = {
	"triggers": [{
		"event": CARD_BEFORE_FLIPPED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_FOR_EACH_SELECTED_CARD,
			"selector": {
				"zones": [CARD_ZONE_HAND],
				"conditions": [{
					"type": CONDITION_SELECTED_CARD_WEAPON_IS,
					"weapon": "轻剑",
				}],
				"limit": 1,
				"required_count": 1,
			},
			"actions": [
				{
					"type": ACTION_RETURN_CARD_TO_HAND,
					"card": CARD_REF_ABILITY_SOURCE,
					"recipient": OWNER_ABILITY_SOURCE,
				},
				{
					"type": ACTION_SUMMON_CARD,
					"card": CARD_REF_SELECTED_CARD,
					"cell": {
						"type": CELL_REF_INITIAL_CARD_CELL,
						"card": CARD_REF_ABILITY_SOURCE,
					},
				},
			],
		}],
	}],
}

const YINYANG_REPEAT_ATTACK: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_ATTACK,
		"conditions": [
			{"type": CONDITION_ATTACKER_CARD_IS_SELF},
			{"type": CONDITION_ATTACK_IS_NOT_REPEAT},
		],
		"actions": [{
			"type": ACTION_STANDARD_ATTACK_WITH_SELF,
			"repeat_attack": true,
		}],
	}],
}

const YINYANG_RANGE_THREE: Dictionary = {
	"modifiers": [{
		"type": MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO,
		"allow_intervening_ally": false,
	}],
}

const YINYANG_RANGE_FOUR: Dictionary = {
	"modifiers": [{
		"type": MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO,
		"allow_intervening_ally": true,
	}],
}

const YINYANG_ZHANGLI_THREE: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [
			{"type": ACTION_EXILE_SELF},
			{"type": ACTION_DRAW_CARDS, "amount": 1},
			{
				"type": ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [CARD_ZONE_HAND],
					"conditions": [
						{"type": CONDITION_SELECTED_CARD_IS_ALLY},
						{
							"type": CONDITION_SELECTED_CARD_WEAPON_IS,
							"weapon": "掌法",
						},
					],
				},
				"actions": [
					{"type": ACTION_GRANT_ABILITY_TO_SELF, "ability": YINYANG_REPEAT_ATTACK},
					{"type": ACTION_GRANT_ABILITY_TO_SELF, "ability": YINYANG_RANGE_THREE},
				],
			},
		],
	}],
}

const YINYANG_ZHANGLI_FOUR: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [
			{"type": ACTION_EXILE_SELF},
			{"type": ACTION_DRAW_CARDS, "amount": 1},
			{
				"type": ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [CARD_ZONE_HAND],
					"conditions": [
						{"type": CONDITION_SELECTED_CARD_IS_ALLY},
						{
							"type": CONDITION_SELECTED_CARD_WEAPON_IS,
							"weapon": "掌法",
						},
					],
				},
				"actions": [
					{"type": ACTION_GRANT_ABILITY_TO_SELF, "ability": YINYANG_REPEAT_ATTACK},
					{"type": ACTION_GRANT_ABILITY_TO_SELF, "ability": YINYANG_RANGE_FOUR},
				],
			},
		],
	}],
}

const DUGU_NO_FORM: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_BEFORE_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [
			{
				"type": ACTION_REVEAL_HAND_CARDS,
				"recipient": RECIPIENT_OPPONENT,
				"filter": REVEAL_FILTER_ALL,
			},
			{"type": ACTION_EXILE_SELF},
			{"type": ACTION_DRAW_CARDS, "amount": 1},
			{
				"type": ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [CARD_ZONE_BOARD],
					"conditions": [{
						"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE,
					}],
				},
				"actions": [
					{"type": ACTION_EXILE_SELF},
					{"type": ACTION_DRAW_CARDS, "amount": 1},
				],
			},
		],
	}],
}

const DUGU_ANTICIPATE: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_BEFORE_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [
			{"type": ACTION_EXILE_SELF},
			{"type": ACTION_DRAW_CARDS, "amount": 1},
			{
				"type": ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [CARD_ZONE_BOARD],
					"conditions": [{
						"type": CONDITION_SELECTED_CARD_IS_PREVIOUS_HAND_PLAY,
						"played_by": OWNER_OPPONENT_OF_ABILITY_SOURCE,
					}],
					"limit": 1,
				},
				"actions": [{
					"type": ACTION_RETURN_CARD_TO_HAND,
					"card": CARD_REF_SELECTED_CARD,
					"recipient": OWNER_OPPONENT_OF_ABILITY_SOURCE,
				}],
			},
			{
				"type": ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [CARD_ZONE_BOARD],
					"conditions": [{
						"type": CONDITION_SELECTED_CARD_IS_PREVIOUS_HAND_PLAY,
						"played_by": OWNER_ABILITY_SOURCE,
					}],
					"limit": 1,
				},
				"actions": [{
					"type": ACTION_RETURN_CARD_TO_HAND,
					"card": CARD_REF_SELECTED_CARD,
					"recipient": OWNER_ABILITY_SOURCE,
				}],
			},
			{"type": ACTION_GRANT_EXTRA_CARD_PLAY, "amount": 1},
		],
	}],
}

const DUGU_BREAK_ALL: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_BEFORE_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [
			{"type": ACTION_EXILE_SELF},
			{"type": ACTION_DRAW_CARDS, "amount": 1},
			{"type": ACTION_GRANT_EXTRA_CARD_PLAY, "amount": 1},
			{
				"type": ACTION_ADD_PENDING_NON_RETAINED_SUPPRESSION,
				"recipient": RECIPIENT_OPPONENT,
				"amount": 1,
			},
		],
	}],
}

const KUIHUA_RETURN_TO_HAND: Dictionary = {
	"triggers": [{
		"event": CARD_BE_ATTACKED,
		"conditions": [{"type": CONDITION_ATTACKED_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_RETURN_CARD_TO_HAND,
			"card": CARD_REF_ABILITY_SOURCE,
			"recipient": OWNER_CARD_CURRENT,
		}],
	}],
}

const KUIHUA_MINIMUM_DEFENSE_RETAINED: Dictionary = {
	"retained_on_flip": true,
	"modifiers": [{"type": MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE}],
}

const KUIHUA_INDISCRIMINATE_ATTACK: Dictionary = {
	"modifiers": [{"type": MODIFIER_ENEMY_ATTACKS_ALL}],
}

const KUIHUA2_GAIN_INDISCRIMINATE_ATTACK: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_ATTACK,
		"conditions": [{"type": CONDITION_ATTACKER_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_GRANT_ABILITY_TO_SELF,
			"ability": KUIHUA_INDISCRIMINATE_ATTACK,
		}],
	}],
}

const KUIHUA3_SWAP_SINGLE_ADJACENT_ENEMY: Dictionary = {
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
}

const KUIHUA3_RESUMMON_AFTER_ENEMY_FLIP: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_ATTACK,
		"conditions": [
			{"type": CONDITION_ATTACKER_CARD_IS_SELF},
			{"type": CONDITION_ATTACK_FLIPPED_ENEMY},
		],
		"actions": [{
			"type": ACTION_RESUMMON_CARD_IN_PLACE,
			"card": CARD_REF_ABILITY_SOURCE,
		}],
	}],
}

const KUIHUA4_DRAW_EXILE_AND_COPY: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [
			{"type": ACTION_DRAW_CARDS, "amount": 1},
			{
				"type": ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [CARD_ZONE_BOARD],
					"conditions": [
						{"type": CONDITION_SELECTED_CARD_IS_ALLY},
						{"type": CONDITION_SELECTED_CARD_ORIGINAL_OWNER_IS_ENEMY},
					],
				},
				"actions": [
					{
						"type": ACTION_EXILE_SELF,
						"on_invalid_context": STOP_RULE,
					},
					{
						"type": ACTION_SUMMON_CARD,
						"card": {
							"type": CARD_SPEC_FRESH_COPY,
							"of": CARD_REF_ABILITY_SOURCE,
						},
						"cell": {
							"type": CELL_REF_INITIAL_CARD_CELL,
							"card": CARD_REF_SELECTED_CARD,
						},
					},
				],
			},
		],
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
		"powers": [3, 8, 8, 2],
		"abilities": [],
	},
	&"CangSongYingKe2": {
		"id": &"CangSongYingKe2",
		"glyph": "苍松迎客",
		"picture": "res://pics/LKT010_568.png",
		"sect": "华山派",
		"tier": 2,
		"weapon": "剑法",
		"description": "对手招式进场后，若在我的攻击范围内，我对其发起攻击。",
		"flavor": "华山剑法的绝招。华山上有数株古松，枝叶向下伸展，有如张臂欢迎上山的游客一般，称为“迎客松”。这招“苍松迎客”，便是从这几株古松的形状上变化而出。",
		"powers": [3, 8, 8, 2],
		"abilities": [QIXIN_SUMMON_REACTION],
	},
	&"CangSongYingKe3": {
		"id": &"CangSongYingKe3",
		"glyph": "苍松迎客",
		"picture": "res://pics/LKT010_568.png",
		"sect": "华山派",
		"tier": 3,
		"weapon": "剑法",
		"description": "对手招式进场后，若在我的攻击范围内，我对其发起攻击。我翻面前，耗内力以获取一张我的复制。",
		"flavor": "华山剑法的绝招。华山上有数株古松，枝叶向下伸展，有如张臂欢迎上山的游客一般，称为“迎客松”。这招“苍松迎客”，便是从这几株古松的形状上变化而出。",
		"powers": [3, 8, 8, 2],
		"abilities": [QIXIN_SUMMON_REACTION,
			{
				"triggers": [
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
		"description": "对手招式进场后，若在我的攻击范围内，我对其发起攻击。我翻面前，耗内力以获取一张我的复制。",
		"flavor": "华山剑法的绝招。华山上有数株古松，枝叶向下伸展，有如张臂欢迎上山的游客一般，称为“迎客松”。这招“苍松迎客”，便是从这几株古松的形状上变化而出。",
		"powers": [5, 8, 8, 4],
		"abilities": [QIXIN_SUMMON_REACTION,
			{
				"triggers": [
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
		"powers": [7, 5, 6, 7],
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
		"powers": [7, 5, 6, 7],
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
		"powers": [7, 6, 6, 7],
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
										{"type": CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE},
									],
								},
								"actions": [
									{
										"type": ACTION_CHANGE_POWERS,
										"amount": 1,
										"card": CARD_REF_SELECTED_CARD,
									},
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
										{"type": CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE},
									],
								},
								"actions": [
									{
										"type": ACTION_CHANGE_POWERS,
										"amount": 1,
										"card": CARD_REF_SELECTED_CARD,
									},
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
										{"type": CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE},
									],
									"limit": 2,
								},
								"actions": [
									{
										"type": ACTION_CHANGE_POWERS,
										"amount": 1,
										"card": CARD_REF_SELECTED_CARD,
									},
								],
							},
						],
					},
				],
			},
		],
	},
	&"TaiZuChangQuan": {
		"id": &"TaiZuChangQuan",
		"glyph": "太祖长拳",
		"picture": "res://pics/LKT010_012.png",
		"sect": "江湖",
		"tier": 1,
		"weapon": "拳法",
		"description": "",
		"flavor": "宋太祖赵匡胤传下的拳法，是武林中最为流行的武功。",
		"powers": [5, 5, 5, 5],
		"abilities": [],
	},
	&"TiYunZong2": {
		"id": &"TiYunZong2",
		"glyph": "梯云纵",
		"picture": "res://pics/LKT010_312.png",
		"sect": "武当派",
		"tier": 2,
		"weapon": "轻功",
		"description": "指定：选择一个其它友方，令其与我依次在彼此的位置重新进场，然后耗内力以额外出一张牌。",
		"flavor": "武当派名闻天下的轻功，长于纵跃，在空中轻轻回旋，姿态飘逸。",
		"powers": [1, 3, 1, 3],
		"starting_ki": 1,
		"abilities": [],
	},
	&"TiYunZong3": {
		"id": &"TiYunZong3",
		"glyph": "梯云纵",
		"picture": "res://pics/LKT010_312.png",
		"sect": "武当派",
		"tier": 3,
		"weapon": "轻功",
		"description": "锁定：我翻面前，改为向相邻空格移动。指定：选择一个其它友方，令其与我依次在彼此的位置重新进场，然后耗内力以额外出一张牌。",
		"flavor": "武当派名闻天下的轻功，长于纵跃，在空中轻轻回旋，姿态飘逸。",
		"powers": [1, 3, 1, 3],
		"starting_ki": 1,
		"abilities": [],
	},
	&"TiYunZong4": {
		"id": &"TiYunZong4",
		"glyph": "梯云纵",
		"picture": "res://pics/LKT010_312.png",
		"sect": "武当派",
		"tier": 4,
		"weapon": "轻功",
		"description": "每当有牌被移除时，你抽一张牌。锁定：我翻面前，改为向相邻空格移动。指定：选择一个其它友方，令其与我依次在彼此的位置重新进场，然后耗内力以额外出一张牌。",
		"flavor": "武当派名闻天下的轻功，长于纵跃，在空中轻轻回旋，姿态飘逸。",
		"powers": [1, 3, 1, 3],
		"starting_ki": 1,
		"abilities": [],
	},
	&"TaiJiSanHuan4": {
		"id": &"TaiJiSanHuan4",
		"glyph": "三环套月",
		"picture": "res://pics/LKT010_567.png",
		"sect": "武当派",
		"tier": 4,
		"weapon": "剑法",
		"description": "在相邻进场且保持相邻的敌方进场攻击不会选中我的友方，反而会选中我的敌方。",
		"flavor": "太极剑法中的招式，神在剑先，绵绵不绝。",
		"powers": [5, 5, 5, 5],
		"abilities": [{
			"modifiers": [{"type": MODIFIER_ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES}],
		}],
	},
	&"TaiJiSanHuan5": {
		"id": &"TaiJiSanHuan5",
		"glyph": "三环套月",
		"picture": "res://pics/LKT010_567.png",
		"sect": "武当派",
		"tier": 5,
		"weapon": "剑法",
		"description": "在相邻进场且保持相邻的敌方进场攻击不会选中我的友方，反而会选中我的敌方。指定：选择一个空位，令你首张被移除的牌在此进场，抽一张牌。",
		"flavor": "太极剑法中的招式，神在剑先，绵绵不绝。",
		"powers": [5, 5, 5, 5],
		"starting_ki": 3,
		"abilities": [
			{
				"modifiers": [{"type": MODIFIER_ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES}],
			},
			{
				"activation": {
					"input": ACTIVATION_DRAG_TO_TARGET,
					"target_rule": TARGET_ANY_EMPTY_BOARD,
					"costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
					"actions": [
						{
							"type": ACTION_FOR_EACH_SELECTED_CARD,
							"selector": {
								"zones": [CARD_ZONE_REMOVED],
								"conditions": [
									{"type": CONDITION_SELECTED_CARD_IS_ALLY},
									{"type": CONDITION_SELECTED_CARD_HAS_NONZERO_POWER},
								],
								"limit": 1,
							},
							"actions": [{
								"type": ACTION_SUMMON_CARD,
								"card": CARD_REF_SELECTED_CARD,
								"cell": {"type": CELL_REF_ACTIVATION_TARGET},
							}],
						},
						{"type": ACTION_DRAW_CARDS, "amount": 1},
					],
				},
			},
		],
	},
	&"TaiJiDaKui5": {
		"id": &"TaiJiDaKui5",
		"glyph": "大魁星",
		"picture": "res://pics/LKT010_544.png",
		"sect": "武当派",
		"tier": 5,
		"weapon": "剑法",
		"description": "在相邻进场且保持相邻的敌方进场攻击不会选中我的友方，反而会选中我的敌方。指定：选择场上的一张敌方牌，令其点数加一，然后所有敌方发起攻击，但攻击时会且只会选中我的敌方。",
		"flavor": "太极剑法中的招式，圆转如意，严密异常。",
		"powers": [5, 5, 5, 5],
		"starting_ki": 1,
		"abilities": [
			{
				"modifiers": [{"type": MODIFIER_ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES}],
			},
			{
				"activation": {
					"input": ACTIVATION_DRAG_TO_TARGET,
					"target_rule": TARGET_ANY_ENEMY_BOARD,
					"costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
					"actions": [
						{
							"type": ACTION_CHANGE_POWERS,
							"amount": 1,
							"card": CARD_REF_SELECTED_CARD,
						},
						{
							"type": ACTION_FOR_EACH_SELECTED_CARD,
							"selector": {
								"zones": [CARD_ZONE_BOARD],
								"conditions": [{"type": CONDITION_SELECTED_CARD_IS_ENEMY}],
							},
							"actions": [{
								"type": ACTION_STANDARD_ATTACK_WITH_SELF,
								"target_policy": ATTACK_TARGET_ALLIES_ONLY,
							}],
						},
					],
				},
			},
		],
	},
	&"TaiJiLuanHuan4": {
		"id": &"TaiJiLuanHuan4",
		"glyph": "太极拳·乱环诀",
		"picture": "res://pics/LKT010_004.png",
		"sect": "武当派",
		"tier": 4,
		"weapon": "拳法",
		"description": "我和其它牌比较大小时，将结果颠倒。",
		"flavor": "乱环术法最难通，上下随合妙无穷。陷敌深入乱环内，四两能拨千斤动。手脚齐进竖找横，掌中乱环落不空。欲知环中法何在，发落点对即成功。",
		"powers": [5, 5, 5, 5],
		"abilities": [{
			"modifiers": [{"type": MODIFIER_POWER_COMPARISON_REVERSED}],
		}],
	},
	&"TaiJiLuanHuan5": {
		"id": &"TaiJiLuanHuan5",
		"glyph": "太极拳·乱环诀",
		"picture": "res://pics/LKT010_004.png",
		"sect": "武当派",
		"tier": 5,
		"weapon": "拳法",
		"description": "我和其它牌比较大小时，将结果颠倒。我攻击后，令所有相邻友方发起攻击。",
		"flavor": "乱环术法最难通，上下随合妙无穷。陷敌深入乱环内，四两能拨千斤动。手脚齐进竖找横，掌中乱环落不空。欲知环中法何在，发落点对即成功。",
		"powers": [5, 5, 5, 5],
		"abilities": [
			{
				"modifiers": [{"type": MODIFIER_POWER_COMPARISON_REVERSED}],
			},
			{
				"triggers": [{
					"event": TRIGGER_CARD_AFTER_ATTACK,
					"conditions": [{"type": CONDITION_ATTACKER_CARD_IS_SELF}],
					"actions": [{
						"type": ACTION_FOR_EACH_SELECTED_CARD,
						"selector": {
							"zones": [CARD_ZONE_BOARD],
							"conditions": [
								{"type": CONDITION_SELECTED_CARD_IS_ALLY},
								{"type": CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
								{"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
							],
						},
						"actions": [{"type": ACTION_STANDARD_ATTACK_WITH_SELF}],
					}],
				}],
			},
		],
	},
	&"TaiJiYinYang5": {
		"id": &"TaiJiYinYang5",
		"glyph": "太极拳·阴阳诀",
		"picture": "res://pics/LKT010_112.png",
		"sect": "武当派",
		"tier": 5,
		"weapon": "拳法",
		"description": "我和其它牌比较大小时，将结果颠倒。我攻击后，令所有敌方获得以下效果：【判断是否能被攻击时，所有点数视为零。锁定：被攻击时，将我移除。】",
		"flavor": "太极阴阳少人修，吞吐开合问刚柔。正隅收放任君走，动静变里何须愁？生克二法随着用，闪进全在动中求。轻重虚实怎的是？重里现轻勿稍留。",
		"powers": [5, 5, 5, 5],
		"abilities": [
			{
				"modifiers": [{"type": MODIFIER_POWER_COMPARISON_REVERSED}],
			},
			{
				"triggers": [{
					"event": TRIGGER_CARD_AFTER_ATTACK,
					"conditions": [{"type": CONDITION_ATTACKER_CARD_IS_SELF}],
					"actions": [{
						"type": ACTION_FOR_EACH_SELECTED_CARD,
						"selector": {
							"zones": [CARD_ZONE_BOARD],
							"conditions": [{"type": CONDITION_SELECTED_CARD_IS_ENEMY}],
						},
						"actions": [
							{
								"type": ACTION_GRANT_ABILITY_TO_SELF,
								"ability": {
									"modifiers": [{
										"type": MODIFIER_DEFENDING_POWER_OVERRIDE,
										"value": 0,
									}],
								},
							},
							{
								"type": ACTION_GRANT_ABILITY_TO_SELF,
								"ability": {
									"retained_on_flip": true,
									"triggers": [{
										"event": CARD_BE_ATTACKED,
										"conditions": [{"type": CONDITION_ATTACKED_CARD_IS_SELF}],
										"actions": [{"type": ACTION_EXILE_CARD, "card": CARD_REF_TRIGGER_CARD}],
									}],
								},
							},
						],
					}],
				}],
			},
		],
	},
	&"RaoZhiRouJian2": {
		"id": &"RaoZhiRouJian2",
		"glyph": "绕指柔剑",
		"picture": "res://pics/LKT010_560.png",
		"sect": "武当派",
		"tier": 2,
		"weapon": "剑法",
		"description": "锁定：我的攻击范围无限，攻击与我不在同一直线上的牌时，只需彼此正对的两组点数中有一组较大。锁定：我攻击时，改为只攻击场上首个我能攻击的敌方。",
		"flavor": "武当派的七十二招绕指柔剑，轻柔曲折，飘忽不定，全仗浑厚内力逼弯剑刃，使剑招闪烁无常，敌人难以挡架。",
		"powers": [8, 3, 8, 3],
		"abilities": [RAOZHI_LOCKED_ATTACK_MODIFIERS],
	},
	&"RaoZhiRouJian3": {
		"id": &"RaoZhiRouJian3",
		"glyph": "绕指柔剑",
		"picture": "res://pics/LKT010_560.png",
		"sect": "武当派",
		"tier": 3,
		"weapon": "剑法",
		"description": "翻面前，将我移除，我将其它牌翻面后，失去此效果。锁定：我的攻击范围无限，攻击与我不在同一直线上的牌时，只需彼此正对的两组点数中有一组较大。锁定：我攻击时，改为只攻击场上首个我能攻击的敌方。",
		"flavor": "武当派的七十二招绕指柔剑，轻柔曲折，飘忽不定，全仗浑厚内力逼弯剑刃，使剑招闪烁无常，敌人难以挡架。",
		"powers": [8, 3, 8, 3],
		"abilities": [
			RAOZHI_LOCKED_ATTACK_MODIFIERS,
			WUDANG_EXILE_BEFORE_FLIP_UNTIL_OWN_FLIP,
		],
	},
	&"RaoZhiRouJian4": {
		"id": &"RaoZhiRouJian4",
		"glyph": "绕指柔剑",
		"picture": "res://pics/LKT010_560.png",
		"sect": "武当派",
		"tier": 4,
		"weapon": "剑法",
		"description": "翻面前，将我移除，我将其它牌翻面后，失去此效果。锁定：我的攻击范围无限，攻击与我不在同一直线上的牌时，只需彼此正对的两组点数中有一组较大。锁定：我攻击时，改为只攻击场上首个我能攻击的敌方。你使用友方的指定效果后，我发起攻击。",
		"flavor": "武当派的七十二招绕指柔剑，轻柔曲折，飘忽不定，全仗浑厚内力逼弯剑刃，使剑招闪烁无常，敌人难以挡架。",
		"powers": [8, 3, 8, 3],
		"abilities": [
			RAOZHI_LOCKED_ATTACK_MODIFIERS,
			WUDANG_EXILE_BEFORE_FLIP_UNTIL_OWN_FLIP,
			RAOZHI_TARGETED_ACTIVATION_REACTION,
		],
	},
	&"ShenMen13Jian1": {
		"id": &"ShenMen13Jian1",
		"glyph": "神门十三剑",
		"picture": "res://pics/LKT010_548.png",
		"sect": "武当派",
		"tier": 1,
		"weapon": "剑法",
		"description": "",
		"flavor": "张三丰所创剑法，一十三记招式各不相同，但所刺之处全是敌人手腕的神门穴。",
		"powers": [3, 3, 8, 8],
		"abilities": [],
	},
	&"ShenMen13Jian2": {
		"id": &"ShenMen13Jian2",
		"glyph": "神门十三剑",
		"picture": "res://pics/LKT010_548.png",
		"sect": "武当派",
		"tier": 2,
		"weapon": "剑法",
		"description": "我将其它牌翻面后，令其发起攻击。",
		"flavor": "张三丰所创剑法，一十三记招式各不相同，但所刺之处全是敌人手腕的神门穴。",
		"powers": [3, 3, 8, 8],
		"abilities": [WUDANG_FLIPPED_CARD_ATTACK],
	},
	&"ShenMen13Jian3": {
		"id": &"ShenMen13Jian3",
		"glyph": "神门十三剑",
		"picture": "res://pics/LKT010_548.png",
		"sect": "武当派",
		"tier": 3,
		"weapon": "剑法",
		"description": "我将其它牌翻面后，令其发起攻击。敌方无法在你的回合进行攻击。",
		"flavor": "张三丰所创剑法，一十三记招式各不相同，但所刺之处全是敌人手腕的神门穴。",
		"powers": [3, 3, 8, 8],
		"abilities": [
			WUDANG_FLIPPED_CARD_ATTACK,
			SHENMEN_OWNER_TURN_ATTACK_LOCK,
		],
	},
	&"WuDangMianZhang1": {
		"id": &"WuDangMianZhang1",
		"glyph": "武当绵掌",
		"picture": "res://pics/LKT010_081.png",
		"sect": "武当派",
		"tier": 1,
		"weapon": "掌法",
		"description": "",
		"flavor": "武当派绝学，以借力打力为根本，有若絮飘雪扬，软绵绵不着力气。",
		"powers": [3, 8, 3, 8],
		"abilities": [],
	},
	&"WuDangMianZhang2": {
		"id": &"WuDangMianZhang2",
		"glyph": "武当绵掌",
		"picture": "res://pics/LKT010_081.png",
		"sect": "武当派",
		"tier": 2,
		"weapon": "掌法",
		"description": "翻面前，将我移除，我将其它牌翻面后，失去此效果。",
		"flavor": "武当派绝学，以借力打力为根本，有若絮飘雪扬，软绵绵不着力气。",
		"powers": [3, 8, 3, 8],
		"abilities": [WUDANG_EXILE_BEFORE_FLIP_UNTIL_OWN_FLIP],
	},
	&"WuDangMianZhang3": {
		"id": &"WuDangMianZhang3",
		"glyph": "武当绵掌",
		"picture": "res://pics/LKT010_081.png",
		"sect": "武当派",
		"tier": 3,
		"weapon": "掌法",
		"description": "翻面前，将我移除，我将其它牌翻面后，失去此效果。我将其它牌翻面后，令其发起攻击。",
		"flavor": "武当派绝学，以借力打力为根本，有若絮飘雪扬，软绵绵不着力气。",
		"powers": [3, 8, 3, 8],
		"abilities": [
			WUDANG_EXILE_BEFORE_FLIP_UNTIL_OWN_FLIP,
			WUDANG_FLIPPED_CARD_ATTACK,
		],
	},
	&"HuZhuaJueHuSHou1": {
		"id": &"HuZhuaJueHuSHou1",
		"glyph": "虎爪绝户手",
		"picture": "res://pics/LKT010_162.png",
		"sect": "武当派",
		"tier": 1,
		"weapon": "指法",
		"description": "",
		"flavor": "俞莲舟从武当虎爪手中脱胎所创，令人断子绝孙，毁灭门户的杀手。",
		"powers": [8, 8, 4, 4],
		"abilities": [],
	},
	&"HuZhuaJueHuSHou2": {
		"id": &"HuZhuaJueHuSHou2",
		"glyph": "虎爪绝户手",
		"picture": "res://pics/LKT010_162.png",
		"sect": "武当派",
		"tier": 2,
		"weapon": "指法",
		"description": "锁定：我攻击时，移除目标。",
		"flavor": "俞莲舟从武当虎爪手中脱胎所创，令人断子绝孙，毁灭门户的杀手。",
		"powers": [8, 8, 4, 4],
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
							{"type": ACTION_EXILE_CARD, "card": CARD_REF_TRIGGER_CARD},
						],
					},
				],
			},
		],
	},
	&"HuZhuaJueHuSHou3": {
		"id": &"HuZhuaJueHuSHou3",
		"glyph": "虎爪绝户手",
		"picture": "res://pics/LKT010_162.png",
		"sect": "武当派",
		"tier": 3,
		"weapon": "指法",
		"description": "其它友方攻击后，我发起攻击。锁定：我攻击时，移除目标。",
		"flavor": "俞莲舟从武当虎爪手中脱胎所创，令人断子绝孙，毁灭门户的杀手。",
		"powers": [8, 8, 4, 4],
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
							{"type": ACTION_EXILE_CARD, "card": CARD_REF_TRIGGER_CARD},
						],
					},
				],
			},
			{
				"triggers": [{
					"event": TRIGGER_CARD_AFTER_ATTACK,
					"conditions": [{"type": CONDITION_ATTACKER_CARD_IS_OTHER_ALLY}],
					"actions": [{"type": ACTION_STANDARD_ATTACK_WITH_SELF}],
				}],
			},
		],
	},
	&"HuZhuaJueHuSHou4": {
		"id": &"HuZhuaJueHuSHou4",
		"glyph": "虎爪绝户手",
		"picture": "res://pics/LKT010_162.png",
		"sect": "武当派",
		"tier": 4,
		"weapon": "指法",
		"description": "其它友方攻击后，我发起攻击。锁定：我攻击时，移除目标。锁定：敌方抽牌时，移除其抽到的牌。",
		"flavor": "俞莲舟从武当虎爪手中脱胎所创，令人断子绝孙，毁灭门户的杀手。",
		"powers": [8, 8, 4, 4],
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
							{"type": ACTION_EXILE_CARD, "card": CARD_REF_TRIGGER_CARD},
						],
					},
				],
			},
			{
				"triggers": [{
					"event": TRIGGER_CARD_AFTER_ATTACK,
					"conditions": [{"type": CONDITION_ATTACKER_CARD_IS_OTHER_ALLY}],
					"actions": [{"type": ACTION_STANDARD_ATTACK_WITH_SELF}],
				}],
			},
			{
				"retained_on_flip": true,
				"triggers": [{
					"event": CARD_AFTER_DRAWN,
					"conditions": [{"type": CONDITION_DRAWN_CARD_IS_ENEMY}],
					"actions": [{"type": ACTION_EXILE_CARD, "card": CARD_REF_TRIGGER_CARD}],
				}],
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
	&"TuNaShu3": {
		"id": &"TuNaShu3",
		"glyph": "吐纳术",
		"picture": "res://pics/LKT010_002.png",
		"sect": "江湖",
		"tier": 3,
		"weapon": "心法",
		"description": "进场后，抽三张牌。",
		"flavor": "江湖上常见的呼吸吐纳功夫，简单易学。",
		"powers": [1, 2, 3, 2],
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_CARD_AFTER_SUMMONED,
						"conditions": [
							{"type": CONDITION_TRIGGER_CARD_IS_SELF},
						],
						"actions": [
							{"type": ACTION_DRAW_CARDS, "amount": 3},
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
		"description": "我翻面前，阻止翻面，敌方翻面后或回合开始时，失去此效果。进场后，揭示敌方手牌中曾经出过的牌。敌方手牌中已揭示的牌进场时，使其获得以下效果：判断是否能被攻击时，所有点数视为零。",
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
		"description": "锁定：场上没有其它友方时无法攻击。锁定：防御者的点数视为其最小一侧的点数。对手招式进场后，若在我的攻击范围内，我对其发起攻击。",
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
		"description": "锁定：场上没有其它友方时无法攻击。锁定：防御者的点数视为其最小一侧的点数。对手招式进场后，若在我的攻击范围内，我对其发起攻击。我翻面前，阻止翻面，敌方翻面后或回合开始时，失去此效果。",
		"flavor": "泰山派剑法的精要所在。单只这一剑，便罩住对方胸口的膻中、神藏、灵墟、神封、步廊、幽门、通谷七处大穴，不论闪向何处，总有一穴会让剑尖刺中。须得轻功高强，立即倒纵出丈许之外，方可避过。",
		"powers": [7, 6, 6, 6],
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
		"description": "进场时，每有一个相邻敌方，我的点数加一。",
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
		"description": "进场时，每有一个相邻敌方，我的点数加一。敌方攻击后，若本次攻击中有在我攻击范围内的友方被翻面，我发起攻击，然后失去此效果。",
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
		"powers": [4, 7, 6, 5],
		"abilities": [JIANFA_ENTRY_MOVE],
	},
	&"JianFaQinYin2": {
		"id": &"JianFaQinYin2",
		"glyph": "剑发琴音",
		"picture": "res://pics/LKT010_556.png",
		"sect": "衡山派",
		"tier": 2,
		"weapon": "轻剑",
		"description": "进场后，若与直线上的敌方相距一个空位，移动至该空位。指定：移动至一个相邻空格，然后额外出一张牌。",
		"flavor": "莫大先生的绝技，所谓“琴中藏剑，剑发琴音”，手中短剑嗡嗡作响，犹如灵蛇颤动不绝，将对手裹在剑光之中。",
		"powers": [4, 7, 6, 5],
		"starting_ki": 1,
		"abilities": [JIANFA_ENTRY_MOVE, JIANFA_ACTIVATION],
	},
	&"JianFaQinYin3": {
		"id": &"JianFaQinYin3",
		"glyph": "剑发琴音",
		"picture": "res://pics/LKT010_556.png",
		"sect": "衡山派",
		"tier": 3,
		"weapon": "轻剑",
		"description": "进场后，若与直线上的敌方相距一个空位，移动至该空位。我移动后，所有相邻敌方失去效果，直到当前回合结束。指定：移动至一个相邻空格，然后额外出一张牌。",
		"flavor": "莫大先生的绝技，所谓“琴中藏剑，剑发琴音”，手中短剑嗡嗡作响，犹如灵蛇颤动不绝，将对手裹在剑光之中。",
		"powers": [4, 7, 6, 5],
		"starting_ki": 1,
		"abilities": [JIANFA_ENTRY_MOVE, JIANFA_MOVE_SUPPRESSION, JIANFA_ACTIVATION],
	},
	&"YanHuiZhuRong3": {
		"id": &"YanHuiZhuRong3",
		"glyph": "雁回祝融",
		"picture": "res://pics/LKT010_474.png",
		"sect": "衡山派",
		"tier": 3,
		"weapon": "剑法",
		"description": "我翻面前，若手牌中有轻剑牌，我移回手牌，然后在相同位置打出最左侧的轻剑牌。",
		"flavor": "衡山五神剑中最为精深的招式，将祝融剑法数十招中的精奥之处融会简化而入一招，一招之中有攻有守，威力之强，为衡山剑法之冠。",
		"powers": [4, 3, 3, 3],
		"abilities": [YANHUI_FLIP_REPLACEMENT],
	},
	&"YanHuiZhuRong4": {
		"id": &"YanHuiZhuRong4",
		"glyph": "雁回祝融",
		"picture": "res://pics/LKT010_474.png",
		"sect": "衡山派",
		"tier": 4,
		"weapon": "剑法",
		"description": "我翻面前，若手牌中有轻剑牌，我移回手牌，然后在相同位置打出最左侧的轻剑牌。指定：选择一个其它友方，将其移回手牌，然后在相同位置生成我的复制。",
		"flavor": "衡山五神剑中最为精深的招式，将祝融剑法数十招中的精奥之处融会简化而入一招，一招之中有攻有守，威力之强，为衡山剑法之冠。",
		"powers": [4, 3, 3, 3],
		"starting_ki": 1,
		"abilities": [
			YANHUI_FLIP_REPLACEMENT,
			{
				"activation": {
					"input": ACTIVATION_DRAG_TO_TARGET,
					"target_rule": TARGET_OTHER_ALLY_BOARD,
					"costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
					"actions": [
						{
							"type": ACTION_RETURN_CARD_TO_HAND,
							"card": CARD_REF_SELECTED_CARD,
							"recipient": OWNER_ABILITY_SOURCE,
						},
						{
							"type": ACTION_SUMMON_CARD,
							"card": {
								"type": CARD_SPEC_FRESH_COPY,
								"of": CARD_REF_ABILITY_SOURCE,
							},
							"cell": {
								"type": CELL_REF_INITIAL_CARD_CELL,
								"card": CARD_REF_SELECTED_CARD,
							},
						},
					],
				},
			},
		],
	},
	&"WanYueChaoZong1": {
		"id": &"WanYueChaoZong1",
		"glyph": "万岳朝宗",
		"picture": "res://pics/LKT010_476.png",
		"sect": "嵩山派",
		"tier": 1,
		"weapon": "剑法",
		"description": "进场后，每有一张手牌，我点数加一。回合开始时，我点数减一。",
		"flavor": "嫡系正宗的嵩山剑法，举剑过顶，弯腰躬身，端严雄伟。",
		"powers": [4, 3, 3, 4],
		"abilities": [WANYUE_SELF_POWER],
	},
	&"WanYueChaoZong2": {
		"id": &"WanYueChaoZong2",
		"glyph": "万岳朝宗",
		"picture": "res://pics/LKT010_476.png",
		"sect": "嵩山派",
		"tier": 2,
		"weapon": "剑法",
		"description": "进场后，每有一张手牌，我点数加一。回合开始时，我点数减一。友方在相邻空格进场时，使其点数加一。",
		"flavor": "嫡系正宗的嵩山剑法，举剑过顶，弯腰躬身，端严雄伟。",
		"powers": [4, 3, 3, 4],
		"abilities": [WANYUE_SELF_POWER, WANYUE_ADJACENT_ALLY_POWER],
	},
	&"WanYueChaoZong3": {
		"id": &"WanYueChaoZong3",
		"glyph": "万岳朝宗",
		"picture": "res://pics/LKT010_476.png",
		"sect": "嵩山派",
		"tier": 3,
		"weapon": "剑法",
		"description": "进场后，每有一张手牌，我点数加一。回合开始时，我点数减一。友方在相邻空格进场时，使其点数加一。",
		"flavor": "嫡系正宗的嵩山剑法，举剑过顶，弯腰躬身，端严雄伟。",
		"powers": [5, 4, 4, 5],
		"abilities": [WANYUE_SELF_POWER, WANYUE_ADJACENT_ALLY_POWER],
	},
	&"WanYueChaoZong4": {
		"id": &"WanYueChaoZong4",
		"glyph": "万岳朝宗",
		"picture": "res://pics/LKT010_476.png",
		"sect": "嵩山派",
		"tier": 4,
		"weapon": "剑法",
		"description": "进场后，每有一张手牌，我点数加一。回合开始时，我点数减一。友方在相邻空格进场时，使其点数加二。",
		"flavor": "嫡系正宗的嵩山剑法，举剑过顶，弯腰躬身，端严雄伟。",
		"powers": [5, 4, 4, 5],
		"abilities": [WANYUE_SELF_POWER, WANYUE_ADJACENT_ALLY_POWER_TWO],
	},
	&"DaSongYangZhang1": {
		"id": &"DaSongYangZhang1",
		"glyph": "大嵩阳神掌",
		"picture": "res://pics/LKT010_089.png",
		"sect": "嵩山派",
		"tier": 1,
		"weapon": "掌法",
		"description": "友方在相邻空格进场时，使其点数加一。",
		"flavor": "嵩山派掌法，一掌出手，全身犹如渊停岳峙，气度凝重。",
		"powers": [7, 7, 3, 4],
		"abilities": [DASONGYANG_ADJACENT_ALLY_POWER],
	},
	&"DaSongYangZhang2": {
		"id": &"DaSongYangZhang2",
		"glyph": "大嵩阳神掌",
		"picture": "res://pics/LKT010_089.png",
		"sect": "嵩山派",
		"tier": 2,
		"weapon": "掌法",
		"description": "友方在相邻空格进场时，使其点数加一。敌方在相邻空格进场时，使其点数减一。",
		"flavor": "嵩山派掌法，一掌出手，全身犹如渊停岳峙，气度凝重。",
		"powers": [7, 7, 3, 4],
		"abilities": [DASONGYANG_ADJACENT_ALLY_POWER, DASONGYANG_ADJACENT_ENEMY_POWER],
	},
	&"DaSongYangZhang3": {
		"id": &"DaSongYangZhang3",
		"glyph": "大嵩阳神掌",
		"picture": "res://pics/LKT010_089.png",
		"sect": "嵩山派",
		"tier": 3,
		"weapon": "掌法",
		"description": "友方在相邻空格进场时，使其点数加一。敌方在相邻空格进场时，使其点数减二。",
		"flavor": "嵩山派掌法，一掌出手，全身犹如渊停岳峙，气度凝重。",
		"powers": [7, 7, 3, 4],
		"abilities": [DASONGYANG_ADJACENT_ALLY_POWER, DASONGYANG_ADJACENT_ENEMY_POWER_TWO],
	},
	&"DaSongYangZhang4": {
		"id": &"DaSongYangZhang4",
		"glyph": "大嵩阳神掌",
		"picture": "res://pics/LKT010_089.png",
		"sect": "嵩山派",
		"tier": 4,
		"weapon": "掌法",
		"description": "友方在相邻空格进场时，使其点数加二。敌方在相邻空格进场时，使其点数减二。",
		"flavor": "嵩山派掌法，一掌出手，全身犹如渊停岳峙，气度凝重。",
		"powers": [7, 7, 3, 4],
		"abilities": [DASONGYANG_ADJACENT_ALLY_POWER_TWO, DASONGYANG_ADJACENT_ENEMY_POWER_TWO],
	},
	&"YinYangZhang3": {
		"id": &"YinYangZhang3",
		"glyph": "阴阳掌力",
		"picture": "res://pics/LKT010_089.png",
		"sect": "嵩山派",
		"tier": 3,
		"weapon": "掌法",
		"description": "进场时，将我移除，抽一张牌，手牌中的掌法获得以下效果：我可以攻击直线上相隔一个空位的敌方。攻击后，再次发起攻击（不触发本效果）。",
		"flavor": "孝感乐厚的成名功夫，双掌掌力不同，一阴一阳，阳掌先出，阴力却先行着体。",
		"powers": [-1, -1, -1, -1],
		"abilities": [YINYANG_ZHANGLI_THREE],
	},
	&"YinYangZhang4": {
		"id": &"YinYangZhang4",
		"glyph": "阴阳掌力",
		"picture": "res://pics/LKT010_089.png",
		"sect": "嵩山派",
		"tier": 4,
		"weapon": "掌法",
		"description": "进场时，将我移除，抽一张牌，手牌中的掌法获得以下效果：我可以攻击直线上相隔一个空位，或相隔一个友方的敌方。攻击后，再次发起攻击（不触发本效果）。",
		"flavor": "孝感乐厚的成名功夫，双掌掌力不同，一阴一阳，阳掌先出，阴力却先行着体。",
		"powers": [-1, -1, -1, -1],
		"abilities": [YINYANG_ZHANGLI_FOUR],
	},
	&"HanBinZhenQi3": {
		"id": &"HanBinZhenQi3",
		"glyph": "寒冰真气",
		"picture": "res://pics/LKT010_078.png",
		"sect": "嵩山派",
		"tier": 3,
		"weapon": "心法",
		"description": "指定：选择对手的一张手牌，使其点数减一并揭示。我翻面后：获得以下效果：回合开始时，我和最左侧的两张手牌点数减一。",
		"flavor": "左冷禅修炼十余年的至阴至寒功夫，所发寒气远胜冰雪，可将对手全身冻结为冰。",
		"powers": [2, 1, 1, 2],
		"starting_ki": 1,
		"abilities": [HANBIN_ACTIVATION, HANBIN_AFTER_FLIP_GRANT],
	},
	&"HanBinZhenQi4": {
		"id": &"HanBinZhenQi4",
		"glyph": "寒冰真气",
		"picture": "res://pics/LKT010_078.png",
		"sect": "嵩山派",
		"tier": 4,
		"weapon": "心法",
		"description": "失去最后的内力时，使我翻面。指定：选择对手的一张手牌，使其点数减一并揭示。我翻面后：获得以下效果：回合开始时，我和最左侧的两张手牌点数减一。",
		"flavor": "左冷禅修炼十余年的至阴至寒功夫，所发寒气远胜冰雪，可将对手全身冻结为冰。",
		"powers": [2, 1, 1, 2],
		"starting_ki": 1,
		"abilities": [
			HANBIN_LAST_KI_FLIP,
			HANBIN_ACTIVATION,
			HANBIN_AFTER_FLIP_GRANT,
		],
	},
	&"TianWaiYuLong2": {
		"id": &"TianWaiYuLong2",
		"glyph": "天外玉龙",
		"picture": "res://pics/LKT010_493.png",
		"sect": "嵩山派",
		"tier": 2,
		"weapon": "剑法",
		"description": "友方在相邻空格进场时，我与其交换位置，然后发起攻击。",
		"flavor": "嵩山派正宗剑法，奔腾矫夭，气势雄浑，但见长剑自半空中横过，剑身似曲似直，时弯时进，便如一件活物一般。",
		"powers": [3, 3, 7, 7],
		"abilities": [TIANWAI_SWAP_ATTACK],
	},
	&"TianWaiYuLong3": {
		"id": &"TianWaiYuLong3",
		"glyph": "天外玉龙",
		"picture": "res://pics/LKT010_493.png",
		"sect": "嵩山派",
		"tier": 3,
		"weapon": "剑法",
		"description": "友方在相邻空格进场时，使其点数加一。友方在相邻空格进场时，我与其交换位置，然后发起攻击。",
		"flavor": "嵩山派正宗剑法，奔腾矫夭，气势雄浑，但见长剑自半空中横过，剑身似曲似直，时弯时进，便如一件活物一般。",
		"powers": [3, 4, 7, 8],
		"abilities": [TIANWAI_POWER_SWAP_ATTACK],
	},
	&"DuGu9Jian1": {
		"id": &"DuGu9Jian1",
		"glyph": "无招胜有招",
		"picture": "res://pics/LKT010_007.png",
		"sect": "江湖",
		"tier": 5,
		"weapon": "剑法",
		"description": "进场前，揭示所有敌方手牌，将自己和相邻牌移除。每以此法移除一张牌，其当前拥有者抽一张牌。",
		"flavor": "令狐冲于独孤九剑中领悟的剑理，剑上无招，敌人便没法可破，无招胜有招，乃剑法之极诣。",
		"powers": [-1, -1, -1, -1],
		"abilities": [DUGU_NO_FORM],
	},
	&"DuGu9Jian2": {
		"id": &"DuGu9Jian2",
		"glyph": "料敌机先",
		"picture": "res://pics/LKT010_351.png",
		"sect": "江湖",
		"tier": 5,
		"weapon": "剑法",
		"description": "进场前，将我移除，抽一张牌。将对手上一张从手牌中打出的牌从场上移回其手牌，将你上一张从手牌中打出的牌从场上移回你的手牌，然后额外出一张牌。",
		"flavor": "独孤九剑的精要所在，任何人一招之出，必定有若干朕兆。你料到他要出什么招，却抢在他头里。敌人手还没提起，你长剑已指向他要害，他再快也没你快。",
		"powers": [-1, -1, -1, -1],
		"abilities": [DUGU_ANTICIPATE],
	},
	&"DuGu9Jian3": {
		"id": &"DuGu9Jian3",
		"glyph": "破尽天下",
		"picture": "res://pics/LKT010_501.png",
		"sect": "江湖",
		"tier": 5,
		"weapon": "剑法",
		"description": "进场前，将我移除，抽一张牌，然后额外出一张牌。对手下一张从手牌中打出的非心法牌失去效果。",
		"flavor": "独孤九剑，有进无退！招招都是进攻，攻敌之不得不守，自己当然不用守了。",
		"powers": [-1, -1, -1, -1],
		"abilities": [DUGU_BREAK_ALL],
	},
	&"LeiZHenJian1": {
		"id": &"LeiZHenJian1",
		"glyph": "雷震剑法",
		"picture": "res://pics/LKT010_551.png",
		"sect": "棋仙派",
		"tier": 1,
		"weapon": "剑法",
		"description": "判断是否能被攻击时，所有点数视为零。锁定：被攻击时，将我移除。",
		"flavor": "棋仙派剑法，六六三十六招竟无一招实招，那是雷震之前的闪电，把敌人弄得头晕眼花之后，跟着而上的便是雷轰霹雳的猛攻。",
		"powers": [7, 7, 7, 7],
		"abilities": [
			{"modifiers": [{"type": MODIFIER_DEFENDING_POWER_OVERRIDE, "value": 0}]},
			{
				"retained_on_flip": true,
				"triggers": [{
					"event": CARD_BE_ATTACKED,
					"conditions": [{"type": CONDITION_ATTACKED_CARD_IS_SELF}],
					"actions": [{"type": ACTION_EXILE_CARD, "card": CARD_REF_TRIGGER_CARD}],
				}],
			},
		],
	},
	&"LeiZHenJian2": {
		"id": &"LeiZHenJian2",
		"glyph": "雷震剑法",
		"picture": "res://pics/LKT010_551.png",
		"sect": "棋仙派",
		"tier": 2,
		"weapon": "剑法",
		"description": "我被移除时，抽一张牌。判断是否能被攻击时，所有点数视为零。锁定：被攻击时，将我移除。",
		"flavor": "棋仙派剑法，六六三十六招竟无一招实招，那是雷震之前的闪电，把敌人弄得头晕眼花之后，跟着而上的便是雷轰霹雳的猛攻。",
		"powers": [7, 7, 7, 7],
		"abilities": [
			{"modifiers": [{"type": MODIFIER_DEFENDING_POWER_OVERRIDE, "value": 0}]},
			{
				"retained_on_flip": true,
				"triggers": [{
					"event": CARD_BE_ATTACKED,
					"conditions": [{"type": CONDITION_ATTACKED_CARD_IS_SELF}],
					"actions": [{"type": ACTION_EXILE_CARD, "card": CARD_REF_TRIGGER_CARD}],
				}],
			},
			{
				"triggers": [{
					"event": CARD_BEFORE_EXILED,
					"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
					"actions": [{"type": ACTION_DRAW_CARDS, "amount": 1}],
				}],
			},
		],
	},
	&"LeiZHenJian3": {
		"id": &"LeiZHenJian3",
		"glyph": "一字电剑",
		"picture": "res://pics/LKT010_551.png",
		"sect": "江湖",
		"tier": 3,
		"weapon": "剑法",
		"description": "敌方攻击时不分敌我。我被移除时，抽一张牌。判断是否能被攻击时，所有点数视为零。锁定：被攻击时，将我移除。",
		"flavor": "一字电剑每招之出，皆如闪电横空，耀人眼目，令人惊心动魄，神驰目眩，难以抵挡剑法的后着。",
		"powers": [7, 7, 7, 7],
		"abilities": [
			{"modifiers": [{"type": MODIFIER_DEFENDING_POWER_OVERRIDE, "value": 0}]},
			{
				"retained_on_flip": true,
				"triggers": [{
					"event": CARD_BE_ATTACKED,
					"conditions": [{"type": CONDITION_ATTACKED_CARD_IS_SELF}],
					"actions": [{"type": ACTION_EXILE_CARD, "card": CARD_REF_TRIGGER_CARD}],
				}],
			},
			{
				"triggers": [{
					"event": CARD_BEFORE_EXILED,
					"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
					"actions": [{"type": ACTION_DRAW_CARDS, "amount": 1}],
				}],
			},
			{"modifiers": [{"type": MODIFIER_ENEMY_ATTACKS_ALL}]},
		],
	},
	&"KuiHua1": {
		"id": &"KuiHua1",
		"glyph": "天人化生",
		"picture": "res://pics/LKT010_006.png",
		"sect": "江湖",
		"tier": 5,
		"weapon": "心法",
		"description": "需自宫。回合结束时，额外出一张牌。",
		"flavor": "东方不败从《葵花宝典》中领悟的人生妙谛，天人化生，万物滋长。",
		"powers": [3, 3, 3, 3],
		"effect_gate": EFFECT_GATE_SELF_CASTRATION,
		"abilities": [
			{
				"triggers": [
					{
						"event": TRIGGER_END_OWNER_TURN,
						"conditions": [
							{"type": CONDITION_TURN_OWNER_IS_SELF},
						],
						"actions": [
							{"type": ACTION_GRANT_EXTRA_CARD_PLAY, "amount": 1},
						],
					},
				],
			},
		],
	},
	&"KuiHua2": {
		"id": &"KuiHua2",
		"glyph": "钟馗抉目",
		"picture": "res://pics/LKT010_482.png",
		"sect": "江湖",
		"tier": 1,
		"extra_victory_reward_tiers": [5],
		"weapon": "轻剑",
		"description": "需自宫。被攻击时，移回手牌。锁定：防御者的点数视为其最小一侧的点数。我攻击后，获得以下效果：敌方攻击时不分敌我。",
		"flavor": "林家七十二路辟邪剑法中的招式，看似平平无奇，中间却藏有许多旁人猜测不透的奥妙，突然之间会变得迅速无比，如鬼似魅，令人难防。",
		"powers": [6, 4, 6, 4],
		"effect_gate": EFFECT_GATE_SELF_CASTRATION,
		"abilities": [
			KUIHUA_RETURN_TO_HAND,
			KUIHUA_MINIMUM_DEFENSE_RETAINED,
			KUIHUA2_GAIN_INDISCRIMINATE_ATTACK,
		],
	},
	&"KuiHua3": {
		"id": &"KuiHua3",
		"glyph": "飞燕穿柳",
		"picture": "res://pics/LKT010_542.png",
		"sect": "江湖",
		"tier": 1,
		"extra_victory_reward_tiers": [5],
		"weapon": "轻剑",
		"description": "需自宫。被攻击时，移回手牌。进场后，若只有一个相邻敌方，与其交换位置。我攻击后，若本次攻击中有敌方被翻面，我重新进场。",
		"flavor": "林家七十二路辟邪剑法中的招式，看似平平无奇，中间却藏有许多旁人猜测不透的奥妙，突然之间会变得迅速无比，如鬼似魅，令人难防。",
		"powers": [4, 6, 4, 6],
		"effect_gate": EFFECT_GATE_SELF_CASTRATION,
		"abilities": [
			KUIHUA_RETURN_TO_HAND,
			KUIHUA3_SWAP_SINGLE_ADJACENT_ENEMY,
			KUIHUA3_RESUMMON_AFTER_ENEMY_FLIP,
		],
	},
	&"KuiHua4": {
		"id": &"KuiHua4",
		"glyph": "群邪辟易",
		"picture": "res://pics/LKT010_488.png",
		"sect": "江湖",
		"tier": 1,
		"extra_victory_reward_tiers": [5],
		"weapon": "轻剑",
		"description": "需自宫。被攻击时，移回手牌。进场后，抽一张牌，将所有最初是敌方的友方移除，并在相同位置生成我的复制。",
		"flavor": "林家七十二路辟邪剑法中的招式，看似平平无奇，中间却藏有许多旁人猜测不透的奥妙，突然之间会变得迅速无比，如鬼似魅，令人难防。",
		"powers": [5, 5, 5, 5],
		"effect_gate": EFFECT_GATE_SELF_CASTRATION,
		"abilities": [
			KUIHUA_RETURN_TO_HAND,
			KUIHUA4_DRAW_EXILE_AND_COPY,
		],
	},
	&"KuiHua0": {
		"id": &"KuiHua0",
		"glyph": "挥剑自宫",
		"picture": "res://pics/LKT010_007.png",
		"sect": "江湖",
		"tier": 6,
		"weapon": "轻剑",
		"description": "解锁我之后，自动激活所有需自宫牌的效果（无需携带）。",
		"flavor": "辟邪剑谱的第一道法诀，武林称雄，挥剑自宫。",
		"powers": [-1, -1, -1, -1],
		"unlocks_effect_gate": EFFECT_GATE_SELF_CASTRATION,
		"guaranteed_defeat_reward": {
			"min_character_tier": 5,
			"requires_unlocked_effect_gate": EFFECT_GATE_SELF_CASTRATION,
		},
		"abilities": [],
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
		"effect_gate": StringName(definition.get("effect_gate", &"")),
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
	if definition.has("extra_victory_reward_tiers"):
		var reward_tiers_value: Variant = definition.get("extra_victory_reward_tiers")
		if typeof(reward_tiers_value) != TYPE_ARRAY:
			errors.append("Card %s requires an Array extra_victory_reward_tiers" % card_id)
		else:
			var observed_reward_tiers: Dictionary = {}
			for reward_tier_value: Variant in reward_tiers_value as Array:
				if (
					typeof(reward_tier_value) != TYPE_INT
					or int(reward_tier_value) < 1
					or observed_reward_tiers.has(int(reward_tier_value))
				):
					errors.append(
						"Card %s requires unique positive integer extra victory reward tiers"
						% card_id
					)
					break
				observed_reward_tiers[int(reward_tier_value)] = true
	if definition.has("guaranteed_defeat_reward"):
		_validate_guaranteed_defeat_reward(
			card_id,
			definition.get("guaranteed_defeat_reward"),
			errors
		)
	var powers: Array = definition.get("powers", [])
	if powers.size() != 4:
		errors.append("Card %s requires four powers" % card_id)
	for power: Variant in powers:
		if typeof(power) != TYPE_INT:
			errors.append("Card %s has a non-integer power" % card_id)
	if definition.has("effects"):
		errors.append("Card %s still declares retired effects data" % card_id)
	for gate_field: StringName in [&"effect_gate", &"unlocks_effect_gate"]:
		if not definition.has(gate_field):
			continue
		var gate_value: Variant = definition.get(gate_field, null)
		if typeof(gate_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			errors.append("Card %s requires a String effect gate in %s" % [card_id, gate_field])
			continue
		if StringName(gate_value) not in KNOWN_EFFECT_GATES:
			errors.append("Card %s uses unknown effect gate %s" % [card_id, gate_value])
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


static func _validate_guaranteed_defeat_reward(
	card_id: StringName,
	declaration_value: Variant,
	errors: Array[String]
) -> void:
	if typeof(declaration_value) != TYPE_DICTIONARY:
		errors.append("Card %s requires a Dictionary guaranteed_defeat_reward" % card_id)
		return
	var declaration: Dictionary = declaration_value as Dictionary
	var known_fields: Array[StringName] = [
		&"min_character_tier",
		&"requires_unlocked_effect_gate",
	]
	for raw_key: Variant in declaration.keys():
		if StringName(String(raw_key)) not in known_fields:
			errors.append(
				"Card %s guaranteed_defeat_reward uses unknown field %s"
				% [card_id, raw_key]
			)
	var minimum_tier: Variant = declaration.get("min_character_tier", null)
	if typeof(minimum_tier) != TYPE_INT or int(minimum_tier) < 1:
		errors.append(
			"Card %s guaranteed_defeat_reward requires a positive integer min_character_tier"
			% card_id
		)
	var gate_value: Variant = declaration.get("requires_unlocked_effect_gate", null)
	if (
		typeof(gate_value) not in [TYPE_STRING, TYPE_STRING_NAME]
		or StringName(gate_value) not in KNOWN_EFFECT_GATES
	):
		errors.append(
			"Card %s guaranteed_defeat_reward requires a known unlocked effect gate"
			% card_id
		)


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
	if _ability_has_self_after_flip_trigger(ability):
		var triggers_value: Variant = ability.get("triggers", [])
		if (
			not triggers_value is Array
			or (triggers_value as Array).size() != 1
			or ability.has("activation")
			or ability.has("modifiers")
		):
			errors.append(
				"Card %s self-after-flip ability must be an isolated trigger entry"
				% card_id
			)


static func _ability_has_self_after_flip_trigger(ability: Dictionary) -> bool:
	for trigger_value: Variant in ability.get("triggers", []):
		if not trigger_value is Dictionary:
			continue
		var trigger: Dictionary = trigger_value
		if StringName(trigger.get("event", &"")) != CARD_AFTER_FLIPPED:
			continue
		for condition_value: Variant in trigger.get("conditions", []):
			if (
				condition_value is Dictionary
				and StringName((condition_value as Dictionary).get("type", &""))
				== CONDITION_TRIGGER_CARD_IS_SELF
			):
				return true
	return false


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
		if modifier_type == MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO:
			allowed_keys.append(&"allow_intervening_ally")
			if typeof(modifier.get("allow_intervening_ally", null)) != TYPE_BOOL:
				errors.append(
					"Card %s modifier %s requires a Boolean allow_intervening_ally"
					% [card_id, modifier_type]
				)
		if modifier_type == MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO:
			allowed_keys.append(&"allow_intervening_ally")
			if typeof(modifier.get("allow_intervening_ally", null)) != TYPE_BOOL:
				errors.append(
					"Card %s modifier %s requires a Boolean allow_intervening_ally"
					% [card_id, modifier_type]
				)
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
	if action_type in [ACTION_DRAW_CARDS, ACTION_GAIN_KI, ACTION_SPEND_KI, ACTION_GRANT_EXTRA_CARD_PLAY]:
		allowed_keys.append(&"amount")
		var amount: Variant = action.get("amount", null)
		if typeof(amount) != TYPE_INT or int(amount) <= 0:
			errors.append("Card %s %s action %s requires a positive integer amount" % [card_id, context_name, action_type])
	if action_type == ACTION_ADD_PENDING_NON_RETAINED_SUPPRESSION:
		allowed_keys.append(&"recipient")
		allowed_keys.append(&"amount")
		if StringName(action.get("recipient", &"")) not in KNOWN_RECIPIENTS:
			errors.append("Card %s %s suppression action requires a known recipient" % [card_id, context_name])
		var suppression_amount: Variant = action.get("amount", null)
		if typeof(suppression_amount) != TYPE_INT or int(suppression_amount) <= 0:
			errors.append("Card %s %s suppression action requires a positive integer amount" % [card_id, context_name])
	if action_type == ACTION_STANDARD_ATTACK_WITH_SELF:
		allowed_keys.append(&"repeat_attack")
		allowed_keys.append(&"target_policy")
		if action.has("repeat_attack") and typeof(action.get("repeat_attack")) != TYPE_BOOL:
			errors.append(
				"Card %s %s action %s requires a Boolean repeat_attack"
				% [card_id, context_name, action_type]
			)
		if action.has("target_policy") and StringName(action.get("target_policy", &"")) not in [
			ATTACK_TARGET_ENEMIES_ONLY,
			ATTACK_TARGET_ALLIES_ONLY,
			ATTACK_TARGET_ALL,
		]:
			errors.append(
				"Card %s %s action %s requires a known target_policy"
				% [card_id, context_name, action_type]
			)
	if action_type == ACTION_STANDARD_ATTACK_WITH_CARD:
		allowed_keys.append(&"card")
		if StringName(action.get("card", &"")) not in KNOWN_CARD_REFERENCES:
			errors.append(
				"Card %s %s action %s requires a known card reference"
				% [card_id, context_name, action_type]
			)
	if action_type == ACTION_CHANGE_POWERS:
		allowed_keys.append(&"amount")
		allowed_keys.append(&"card")
		_validate_power_change_amount(
			card_id,
			context_name,
			action.get("amount", null),
			errors
		)
		if StringName(action.get("card", &"")) not in KNOWN_CARD_REFERENCES:
			errors.append(
				"Card %s %s action %s requires a known card reference"
				% [card_id, context_name, action_type]
			)
	if action_type == ACTION_EXILE_CARD:
		allowed_keys.append(&"card")
		if StringName(action.get("card", &"")) not in KNOWN_CARD_REFERENCES:
			errors.append(
				"Card %s %s action %s requires a known card reference"
				% [card_id, context_name, action_type]
			)
	if action_type in [ACTION_CHANGE_POWERS, ACTION_FOR_EACH_SELECTED_CARD]:
		if action.has("power_change_batch_group"):
			allowed_keys.append(&"power_change_batch_group")
			var batch_group_value: Variant = action.get("power_change_batch_group", null)
			if (
				typeof(batch_group_value) not in [TYPE_STRING, TYPE_STRING_NAME]
				or String(batch_group_value).is_empty()
			):
				errors.append(
					"Card %s %s action %s requires a non-empty power_change_batch_group"
					% [card_id, context_name, action_type]
				)
	if action_type == ACTION_FLIP_SELF:
		allowed_keys.append(&"new_owner")
		if StringName(action.get("new_owner", &"")) not in [
			OWNER_ABILITY_SOURCE,
			OWNER_OPPONENT_OF_ABILITY_SOURCE,
		]:
			errors.append(
				"Card %s %s action %s requires a known new_owner"
				% [card_id, context_name, action_type]
			)
	if action_type == ACTION_FOR_EACH_SELECTED_CARD:
		allowed_keys.append(&"selector")
		allowed_keys.append(&"actions")
		var selector_value: Variant = action.get("selector", null)
		_validate_selector(card_id, context_name, selector_value, errors)
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
			if (
				_actions_change_selected_card_powers(nested_actions_value as Array)
				and not _selector_has_condition(
					selector_value,
					CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE
				)
			):
				errors.append(
					"Card %s %s selected-card power changes require %s"
					% [
						card_id,
						context_name,
						CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE,
					]
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
	if action_type == ACTION_RETURN_CARD_TO_HAND:
		allowed_keys.append(&"card")
		allowed_keys.append(&"recipient")
		if StringName(action.get("card", &"")) not in KNOWN_CARD_REFERENCES:
			errors.append("Card %s %s return action requires a known card reference" % [card_id, context_name])
		if StringName(action.get("recipient", &"")) not in KNOWN_OWNER_REFERENCES:
			errors.append("Card %s %s return action requires a known recipient" % [card_id, context_name])
	if action_type == ACTION_SUMMON_CARD:
		allowed_keys.append(&"card")
		allowed_keys.append(&"cell")
		_validate_summon_card_spec(card_id, context_name, action.get("card", null), errors)
		_validate_summon_cell_spec(card_id, context_name, action.get("cell", null), errors)
	if action_type == ACTION_RESUMMON_CARD_IN_PLACE:
		allowed_keys.append(&"card")
		if StringName(action.get("card", &"")) not in KNOWN_CARD_REFERENCES:
			errors.append(
				"Card %s %s resummon action requires a known card reference"
				% [card_id, context_name]
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
	if action_type == ACTION_REVEAL_CARD:
		allowed_keys.append(&"card")
		allowed_keys.append(&"observer")
		if StringName(action.get("card", &"")) not in KNOWN_CARD_REFERENCES:
			errors.append("Card %s %s reveal-card action requires a known card reference" % [card_id, context_name])
		if StringName(action.get("observer", &"")) not in KNOWN_OWNER_REFERENCES:
			errors.append("Card %s %s reveal-card action requires a known observer" % [card_id, context_name])
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


static func _actions_change_selected_card_powers(actions: Array) -> bool:
	for action_value: Variant in actions:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		var action_type := StringName(action.get("type", &""))
		if (
			action_type == ACTION_CHANGE_POWERS
			and StringName(action.get("card", &"")) == CARD_REF_SELECTED_CARD
		):
			return true
		if (
			action_type == ACTION_FOR_EACH_SELECTED_CARD
			and action.get("actions", null) is Array
			and _actions_change_selected_card_powers(action.get("actions", []) as Array)
		):
			return true
	return false


static func _selector_has_condition(
	selector_value: Variant,
	expected_condition: StringName
) -> bool:
	if not selector_value is Dictionary:
		return false
	for condition_value: Variant in (selector_value as Dictionary).get("conditions", []):
		if (
			condition_value is Dictionary
			and StringName((condition_value as Dictionary).get("type", &""))
			== expected_condition
		):
			return true
	return false


static func _validate_power_change_amount(
	card_id: StringName,
	context_name: String,
	value: Variant,
	errors: Array[String]
) -> void:
	if typeof(value) == TYPE_INT:
		if int(value) == 0:
			errors.append(
				"Card %s %s action %s requires a nonzero integer amount"
				% [card_id, context_name, ACTION_CHANGE_POWERS]
			)
		return
	if not value is Dictionary:
		errors.append(
			"Card %s %s action %s requires a signed integer or value specification"
			% [card_id, context_name, ACTION_CHANGE_POWERS]
		)
		return
	var spec: Dictionary = value
	if StringName(spec.get("type", &"")) != VALUE_CARD_COUNT:
		errors.append(
			"Card %s %s power amount uses an unknown value type"
			% [card_id, context_name]
		)
	if StringName(spec.get("zone", &"")) != CARD_ZONE_HAND:
		errors.append(
			"Card %s %s card-count value requires the hand zone"
			% [card_id, context_name]
		)
	if StringName(spec.get("owner", &"")) not in KNOWN_OWNER_REFERENCES:
		errors.append(
			"Card %s %s card-count value requires a known owner reference"
			% [card_id, context_name]
		)
	for key: Variant in spec.keys():
		if StringName(key) not in [&"type", &"zone", &"owner"]:
			errors.append(
				"Card %s %s power amount has unsupported field %s"
				% [card_id, context_name, key]
			)


static func _validate_summon_card_spec(
	card_id: StringName,
	context_name: String,
	value: Variant,
	errors: Array[String]
) -> void:
	if typeof(value) in [TYPE_STRING, TYPE_STRING_NAME]:
		if StringName(value) not in KNOWN_CARD_REFERENCES:
			errors.append("Card %s %s summon action requires a known card reference" % [card_id, context_name])
		return
	if not value is Dictionary:
		errors.append("Card %s %s summon action requires a card specification" % [card_id, context_name])
		return
	var spec: Dictionary = value
	if StringName(spec.get("type", &"")) != CARD_SPEC_FRESH_COPY:
		errors.append("Card %s %s summon action uses an unknown card specification" % [card_id, context_name])
	if StringName(spec.get("of", &"")) not in KNOWN_CARD_REFERENCES:
		errors.append("Card %s %s fresh-copy summon requires a known card reference" % [card_id, context_name])
	for key: Variant in spec.keys():
		if StringName(key) not in [&"type", &"of"]:
			errors.append("Card %s %s summon card specification has unsupported field %s" % [card_id, context_name, key])


static func _validate_summon_cell_spec(
	card_id: StringName,
	context_name: String,
	value: Variant,
	errors: Array[String]
) -> void:
	if not value is Dictionary:
		errors.append("Card %s %s summon action requires a cell specification" % [card_id, context_name])
		return
	var spec: Dictionary = value
	var cell_type := StringName(spec.get("type", &""))
	if cell_type not in [
		CELL_REF_INITIAL_CARD_CELL,
		CELL_REF_FIRST_ADJACENT_EMPTY,
		CELL_REF_ACTIVATION_TARGET,
	]:
		errors.append("Card %s %s summon action uses an unknown cell specification" % [card_id, context_name])
	if (
		cell_type != CELL_REF_ACTIVATION_TARGET
		and StringName(spec.get("card", &"")) not in KNOWN_CARD_REFERENCES
	):
		errors.append("Card %s %s summon cell requires a known card reference" % [card_id, context_name])
	for key: Variant in spec.keys():
		if StringName(key) not in [&"type", &"card"]:
			errors.append("Card %s %s summon cell specification has unsupported field %s" % [card_id, context_name, key])


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
	if condition_type == CONDITION_SELECTED_CARD_IS_PREVIOUS_HAND_PLAY:
		allowed_keys.append(&"played_by")
		if StringName(condition.get("played_by", &"")) not in [
			OWNER_ABILITY_SOURCE,
			OWNER_OPPONENT_OF_ABILITY_SOURCE,
		]:
			errors.append("Card %s %s previous-play condition requires a relative owner" % [card_id, context_name])
	for key: Variant in condition.keys():
		if StringName(key) not in allowed_keys:
			errors.append("Card %s %s selector condition %s has unsupported field %s" % [card_id, context_name, condition_type, key])
