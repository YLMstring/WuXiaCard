class_name CardCatalog
extends RefCounted

const ACTIVATION_DRAG_TO_TARGET: StringName = &"drag_to_target"
const TARGET_ADJACENT_EMPTY_BOARD: StringName = &"adjacent_empty_board"
const TRIGGER_CARD_SUMMONED: StringName = &"card_summoned"
const TRIGGER_CARD_AFTER_SUMMONED: StringName = &"card_after_summoned"
const CARD_BE_ATTACKED: StringName = &"card_be_attacked"
const CARD_AFTER_FLIPPED: StringName = &"card_after_flipped"
const TRIGGER_END_OWNER_TURN: StringName = &"end_owner_turn"
const CONDITION_KI_AT_LEAST: StringName = &"ki_at_least"
const CONDITION_TRIGGER_CARD_IS_ENEMY: StringName = &"trigger_card_is_enemy"
const CONDITION_TRIGGER_CARD_IN_RANGE: StringName = &"trigger_card_in_range"
const CONDITION_TRIGGER_CARD_IS_SELF: StringName = &"trigger_card_is_self"
const CONDITION_ATTACKER_CARD_IS_SELF: StringName = &"attacker_card_is_self"
const CONDITION_TURN_OWNER_IS_SELF: StringName = &"turn_owner_is_self"
const ACTION_DRAW_CARDS: StringName = &"draw_cards"
const ACTION_EXILE_ATTACKED_CARD: StringName = &"exile_attacked_card"
const ACTION_ATTACK_TRIGGER_CARD: StringName = &"attack_trigger_card"
const ACTION_GAIN_KI: StringName = &"gain_ki"
const ACTION_SPEND_KI: StringName = &"spend_ki"
const ACTION_SPEND_ALL_KI: StringName = &"spend_all_ki"
const ACTION_REQUEST_EXTRA_TURN: StringName = &"request_extra_turn"
const ACTION_MOVE_SELF_TO_TARGET: StringName = &"move_self_to_target"
const ACTION_STANDARD_ATTACK_WITH_SELF: StringName = &"standard_attack_with_self"
const ACTION_RESULT_APPLIED: StringName = &"applied"
const ACTION_RESULT_NO_EFFECT: StringName = &"no_effect"
const ACTION_RESULT_INVALID_CONTEXT: StringName = &"invalid_context"
const STOP_RULE: StringName = &"stop_rule"
const KNOWN_ACTIVATION_INPUTS: Array[StringName] = [ACTIVATION_DRAG_TO_TARGET]
const KNOWN_TARGET_RULES: Array[StringName] = [TARGET_ADJACENT_EMPTY_BOARD]
const KNOWN_TRIGGER_EVENTS: Array[StringName] = [
	TRIGGER_CARD_SUMMONED,
	TRIGGER_CARD_AFTER_SUMMONED,
	CARD_BE_ATTACKED,
	CARD_AFTER_FLIPPED,
	TRIGGER_END_OWNER_TURN,
]
const KNOWN_TRIGGER_CONDITIONS: Array[StringName] = [
	CONDITION_KI_AT_LEAST,
	CONDITION_TRIGGER_CARD_IS_ENEMY,
	CONDITION_TRIGGER_CARD_IN_RANGE,
	CONDITION_TRIGGER_CARD_IS_SELF,
	CONDITION_ATTACKER_CARD_IS_SELF,
	CONDITION_TURN_OWNER_IS_SELF,
]
const KNOWN_ACTIONS: Array[StringName] = [
	ACTION_DRAW_CARDS,
	ACTION_EXILE_ATTACKED_CARD,
	ACTION_ATTACK_TRIGGER_CARD,
	ACTION_GAIN_KI,
	ACTION_SPEND_KI,
	ACTION_SPEND_ALL_KI,
	ACTION_REQUEST_EXTRA_TURN,
	ACTION_MOVE_SELF_TO_TARGET,
	ACTION_STANDARD_ATTACK_WITH_SELF,
]

const ALL_CARD_IDS: Array[StringName] = [
	&"CangSongYingKe1",
	&"CangSongYingKe2",
	&"CangSongYingKe3",
	&"CangSongYingKe4",
	&"YouFenLaiYi2",
	&"YouFenLaiYi3",
	&"YouFenLaiYi4",
	&"fa_zheng",
	&"fire_envoy",
	&"tiger_general",
	&"strategist",
	&"sun_zan",
	&"hanfeng_liezhen",
	&"huixue_liuguang",
	&"qiyao_lianfeng",
	&"wanyue_guizong",
	&"yuyan_tousuo",
	&"wusuo_changqiao",
	&"feixing_ruye",
	&"qianji_tingyu",
	&"hengsha_duanlu",
	&"chilian_huifeng",
	&"shahai_zhuri",
	&"damo_guzhan",
	&"dielang_tuizhou",
	&"huichao_tingjin",
	&"canghai_sandie",
	&"haitian_yizhang",
	&"zhujian_cangfeng",
	&"luming_wenlu",
	&"jingwei_dingju",
	&"zhishang_shanhe",
	&"gate_general",
	&"meng_huo",
]

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
		"powers": [3, 7, 7, 4],
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
		"powers": [3, 7, 7, 4],
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
		"description": "对手招式进场时，若在我的攻击范围内，我对其发起攻击。我翻面前，耗尽我的内力以获取一张我的复制。",
		"flavor": "华山剑法的绝招。华山上有数株古松，枝叶向下伸展，有如张臂欢迎上山的游客一般，称为“迎客松”。这招“苍松迎客”，便是从这几株古松的形状上变化而出。",
		"powers": [3, 7, 7, 4],
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
	&"CangSongYingKe4": {
		"id": &"CangSongYingKe4",
		"glyph": "苍松迎客",
		"picture": "res://pics/LKT010_568.png",
		"sect": "华山派",
		"tier": 4,
		"weapon": "剑法",
		"description": "对手招式进场时，若在我的攻击范围内，我对其发起攻击。我翻面前，耗尽我的内力以获取一张我的复制。",
		"flavor": "华山剑法的绝招。华山上有数株古松，枝叶向下伸展，有如张臂欢迎上山的游客一般，称为“迎客松”。这招“苍松迎客”，便是从这几株古松的形状上变化而出。",
		"powers": [4, 7, 8, 4],
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
	&"YouFenLaiYi2": {
		"id": &"YouFenLaiYi2",
		"glyph": "有凤来仪",
		"picture": "res://pics/LKT010_558.png",
		"sect": "华山派",
		"tier": 2,
		"weapon": "剑法",
		"description": "锁定，指定：移动至一个相邻空格，然后发起攻击。",
		"flavor": "华山剑法的杀招，剑势飞舞而出，轻盈灵动。招数本极寻常，但五个后着变化繁复，威力极大。",
		"powers": [6, 6, 6, 6],
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
		"powers": [6, 6, 6, 6],
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
		"powers": [6, 6, 6, 6],
		"starting_ki": 3,
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
	&"fa_zheng": {
		"id": &"fa_zheng",
		"glyph": "法",
		"picture": "res://pics/LKT010_005.png",
		"sect": "",
		"tier": 1,
		"weapon": "",
		"description": "",
		"flavor": "",
		"powers": [5, 4, 4, 3],
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
	&"strategist": {
		"id": &"strategist",
		"glyph": "策",
		"picture": "res://pics/LKT010_009.png",
		"sect": "",
		"tier": 1,
		"weapon": "",
		"description": "",
		"flavor": "",
		"powers": [4, 4, 4, 4],
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
	&"sun_zan": {
		"id": &"sun_zan",
		"glyph": "孙",
		"picture": "res://pics/LKT010_010.png",
		"sect": "",
		"tier": 1,
		"weapon": "",
		"description": "",
		"flavor": "",
		"powers": [3, 5, 8, 8],
		"starting_ki": 1,
		"abilities": [
			{
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
	&"hanfeng_liezhen": {
		"id": &"hanfeng_liezhen",
		"glyph": "寒峰列阵",
		"picture": "res://pics/LKT010_011.png",
		"sect": "玄岳剑宗",
		"tier": 1,
		"weapon": "剑阵",
		"description": "依山势错步列锋，以数道交叠剑路封住对手的进退方向。",
		"flavor": "玄岭初雪时，外门弟子会在石阶上反复排阵，直到每一道足印都被风重新抹平。",
		"powers": [4, 5, 3, 6],
		"abilities": [],
	},
	&"huixue_liuguang": {
		"id": &"huixue_liuguang",
		"glyph": "回雪流光",
		"picture": "res://pics/LKT010_012.png",
		"sect": "玄岳剑宗",
		"tier": 2,
		"weapon": "剑阵",
		"description": "剑锋随回旋步法折返，前一道寒光未散，后一道剑势已从侧面掩至。",
		"flavor": "相传此式创于一场大雪，祖师只出一剑，崖边积雪却绕身三周方才落地。",
		"powers": [6, 3, 5, 4],
		"abilities": [],
	},
	&"qiyao_lianfeng": {
		"id": &"qiyao_lianfeng",
		"glyph": "七曜连锋",
		"picture": "res://pics/LKT010_013.png",
		"sect": "玄岳剑宗",
		"tier": 3,
		"weapon": "剑阵",
		"description": "七处剑位首尾呼应，任一处受阻，其余剑势便立刻补上缺口。",
		"flavor": "剑坪上的七盏铜灯从不同时熄灭，那是玄岳弟子留给夜归同门的路标。",
		"powers": [7, 5, 6, 4],
		"abilities": [],
	},
	&"wanyue_guizong": {
		"id": &"wanyue_guizong",
		"glyph": "万岳归宗",
		"picture": "res://pics/LKT010_014.png",
		"sect": "玄岳剑宗",
		"tier": 5,
		"weapon": "剑阵",
		"description": "收束四方剑势于一点，以沉雄如山的正锋压垮对手最后的守势。",
		"flavor": "历代宗主继位时皆要独登万仞台。下山之后，他们从不再谈那一夜看见了什么。",
		"powers": [8, 7, 5, 8],
		"abilities": [],
	},
	&"yuyan_tousuo": {
		"id": &"yuyan_tousuo",
		"glyph": "雨燕投梭",
		"picture": "res://pics/LKT010_015.png",
		"sect": "烟雨楼",
		"tier": 1,
		"weapon": "暗器",
		"description": "借袖口遮掩投出细梭，轨迹轻捷多变，如雨燕贴水掠行。",
		"flavor": "烟雨楼的铜梭从不刻名，只在尾端留一道浅痕，方便主人在暗处以指腹辨认。",
		"powers": [3, 6, 4, 5],
		"abilities": [],
	},
	&"wusuo_changqiao": {
		"id": &"wusuo_changqiao",
		"glyph": "雾锁长桥",
		"picture": "res://pics/LKT010_016.png",
		"sect": "烟雨楼",
		"tier": 2,
		"weapon": "暗器",
		"description": "以烟丸遮断视线，再从桥栏、瓦隙与水面反射中寻找出手角度。",
		"flavor": "江南有座无名旧桥，每逢晨雾便少一块青砖，却从来没人见过取砖的人。",
		"powers": [5, 4, 6, 3],
		"abilities": [],
	},
	&"feixing_ruye": {
		"id": &"feixing_ruye",
		"glyph": "飞星入夜",
		"picture": "res://pics/LKT010_017.png",
		"sect": "烟雨楼",
		"tier": 3,
		"weapon": "暗器",
		"description": "连续掷出明暗两组星镖，以可见寒芒诱使对手忽略真正的杀机。",
		"flavor": "楼中弟子说，最亮的星只负责引路，真正决定归途的那一颗从不发光。",
		"powers": [7, 3, 5, 6],
		"abilities": [],
	},
	&"qianji_tingyu": {
		"id": &"qianji_tingyu",
		"glyph": "千机听雨",
		"picture": "res://pics/LKT010_018.png",
		"sect": "烟雨楼",
		"tier": 4,
		"weapon": "暗器",
		"description": "从雨声的细微变化判断周围动静，并以连环机括封锁多个方位。",
		"flavor": "暴雨之夜，烟雨楼主常独坐檐下。若茶盏中的涟漪忽然停住，整座楼便会同时熄灯。",
		"powers": [6, 8, 4, 7],
		"abilities": [],
	},
	&"hengsha_duanlu": {
		"id": &"hengsha_duanlu",
		"glyph": "横沙断路",
		"picture": "res://pics/LKT010_019.png",
		"sect": "赤砂门",
		"tier": 1,
		"weapon": "刀法",
		"description": "横刀卷起沙尘迫使对手停步，再以宽阔刀势截断前路。",
		"flavor": "赤砂门的第一堂刀课不教劈砍，只教弟子在风沙里睁着眼睛看清来路。",
		"powers": [6, 4, 3, 5],
		"abilities": [],
	},
	&"chilian_huifeng": {
		"id": &"chilian_huifeng",
		"glyph": "赤练回风",
		"picture": "res://pics/LKT010_020.png",
		"sect": "赤砂门",
		"tier": 1,
		"weapon": "刀法",
		"description": "短促旋身带动刀锋折返，能在一次进势中兼顾前后两面。",
		"flavor": "门中刀穗皆以赤练草编成，草叶越旧，颜色反而越深。",
		"powers": [4, 6, 5, 3],
		"abilities": [],
	},
	&"shahai_zhuri": {
		"id": &"shahai_zhuri",
		"glyph": "沙海逐日",
		"picture": "res://pics/LKT010_021.png",
		"sect": "赤砂门",
		"tier": 2,
		"weapon": "刀法",
		"description": "以不停歇的追击积累气势，刀路随着步幅逐渐放大，逼迫对手正面应战。",
		"flavor": "赤砂门人远行不带日晷，他们看刀背上的光，便知道自己还能追多久。",
		"powers": [7, 5, 4, 6],
		"abilities": [],
	},
	&"damo_guzhan": {
		"id": &"damo_guzhan",
		"glyph": "大漠孤斩",
		"picture": "res://pics/LKT010_022.png",
		"sect": "赤砂门",
		"tier": 3,
		"weapon": "刀法",
		"description": "摒弃多余变化，将全身力量凝于一次孤绝重斩，以气魄先破敌胆。",
		"flavor": "大漠深处立着半截黑色石碑，上面只有一道刀痕，百年来无人知道另一半去了哪里。",
		"powers": [8, 4, 7, 5],
		"abilities": [],
	},
	&"dielang_tuizhou": {
		"id": &"dielang_tuizhou",
		"glyph": "叠浪推舟",
		"picture": "res://pics/LKT010_023.png",
		"sect": "听潮谷",
		"tier": 1,
		"weapon": "掌法",
		"description": "连续送出轻重不同的掌劲，后劲推前劲，如叠浪托舟而行。",
		"flavor": "谷中孩童学会走路后，先要学会在小舟上站稳，才会正式拜师。",
		"powers": [5, 3, 6, 4],
		"abilities": [],
	},
	&"huichao_tingjin": {
		"id": &"huichao_tingjin",
		"glyph": "回潮听劲",
		"picture": "res://pics/LKT010_024.png",
		"sect": "听潮谷",
		"tier": 2,
		"weapon": "掌法",
		"description": "以掌心感知来力方向，先顺势卸劲，再借回潮之势反送回去。",
		"flavor": "听潮谷的练功石没有一块完整，裂纹却都朝向海面。",
		"powers": [4, 6, 3, 7],
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
	var activation_count: int = 0
	for ability_value: Variant in abilities_value as Array:
		if not ability_value is Dictionary:
			errors.append("Card %s has a non-dictionary ability" % card_id)
			continue
		var ability: Dictionary = ability_value
		if ability.has("activation"):
			activation_count += 1
		_validate_ability(card_id, ability, errors)
	if activation_count > 1:
		errors.append("Card %s declares more than one activation" % card_id)


static func _normalize_abilities(raw_abilities: Array) -> Array:
	var normalized_abilities: Array = []
	for ability_value: Variant in raw_abilities:
		var ability: Dictionary = (ability_value as Dictionary).duplicate(true)
		if not ability.has("retained_on_flip"):
			ability["retained_on_flip"] = false
		normalized_abilities.append(ability)
	return normalized_abilities


static func _validate_ability(
	card_id: StringName,
	ability: Dictionary,
	errors: Array[String]
) -> void:
	if ability.has("id"):
		errors.append("Card %s ability must not declare an id" % card_id)
	for key: Variant in ability.keys():
		if StringName(key) not in [&"retained_on_flip", &"triggers", &"activation"]:
			errors.append("Card %s ability has unsupported field %s" % [card_id, key])
	if ability.has("retained_on_flip") and typeof(ability["retained_on_flip"]) != TYPE_BOOL:
		errors.append("Card %s ability has non-Boolean retained_on_flip" % card_id)
	if not ability.has("triggers") and not ability.has("activation"):
		errors.append("Card %s ability requires triggers or activation" % card_id)
	if ability.has("triggers"):
		_validate_triggers(card_id, ability["triggers"], errors)
	if ability.has("activation"):
		_validate_activation(card_id, ability["activation"], errors)


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
	if action_type in [ACTION_DRAW_CARDS, ACTION_GAIN_KI, ACTION_SPEND_KI]:
		allowed_keys.append(&"amount")
		var amount: Variant = action.get("amount", null)
		if typeof(amount) != TYPE_INT or int(amount) <= 0:
			errors.append("Card %s %s action %s requires a positive integer amount" % [card_id, context_name, action_type])
	if action.has("on_invalid_context"):
		if StringName(action.get("on_invalid_context", &"")) != STOP_RULE:
			errors.append("Card %s %s action %s has invalid on_invalid_context policy" % [card_id, context_name, action_type])
	for key: Variant in action.keys():
		if StringName(key) not in allowed_keys:
			errors.append("Card %s %s action %s has unsupported field %s" % [card_id, context_name, action_type, key])
