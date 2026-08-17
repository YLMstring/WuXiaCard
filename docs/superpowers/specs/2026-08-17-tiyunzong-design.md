# 梯云纵设计

日期：2026-08-17

## 范围

实装 `TiYunZong2`、`TiYunZong3`、`TiYunZong4` 的完整卡牌描述。规则继续由 `DuelSimulator` 统一执行，卡牌目录只通过通用事件、条件、引用和 action 声明能力；搜索和控制器不得判断梯云纵卡牌 ID。

## 已确认语义

- 指定能力选择任意一个其它友方，不要求相邻。
- 激活开始时，旧梯云纵按通用规则支付 1 内力。
- 被选友方和旧梯云纵均无移除地离场，旧运行时实例永久消失，不进入移除区。
- 被选友方先在旧梯云纵原格以全新同 ID 实例完整进场；该实例使用目录初始点数、内力和能力。
- 被选友方的进场前、进场、进场后和普通攻击全部结算后，新梯云纵才在被选友方原格以全新同 ID 实例完整进场并攻击。
- 两次进场都使用能力发动时快照的原格。第一张牌结算期间可以移动、离场或占据第二个原格。
- 若新梯云纵进场失败，不回滚此前离场和第一张牌的进场，也不消耗新梯云纵内力、不提供额外出牌。
- 新梯云纵完整进场并攻击后，立刻消耗它的 1 内力，再给予其当前所属方一次额外出牌。
- 三、四阶翻面前若存在相邻空格，移动到编号最小的相邻空格并阻止本次翻面；若移动失败或没有相邻空格，本次翻面照常进行。
- 翻面移动能力为锁定能力，设置 `retained_on_flip = true`。
- 四阶仅在被移除牌不位于梯云纵当前所属方手牌时抽一张。敌方手牌、双方场上牌和梯云纵自身被移除均可触发；己方手牌中的牌被移除不触发。
- 无移除离场不属于“被移除”，不会触发四阶抽牌。
- 四阶判断使用移除前区域和所属方；触发来源必须仍在场，手牌中的梯云纵能力不触发。

## 通用词汇

新增：

```gdscript
const CONDITION_TRIGGER_CARD_OUTSIDE_SOURCE_OWNER_HAND = \
	&"trigger_card_outside_source_owner_hand"
const ACTION_DEPART_CARD_FOR_RESUMMON = &"depart_card_for_resummon"
const CARD_REF_LAST_SUMMONED_CARD = &"last_summoned_card"
```

扩展现有 action：

```gdscript
ACTION_SPEND_KI
ACTION_GRANT_EXTRA_CARD_PLAY
```

二者增加可选 `card` 字段。省略时保持现有默认行为，作用于当前 action 主体；声明引用时，作用于该精确卡牌当前实例。激活 `costs` 中的 `ACTION_SPEND_KI` 不允许声明 `card`，仍只支付发动者的内力。

## 通用 action 与引用行为

### `ACTION_DEPART_CARD_FOR_RESUMMON`

声明格式：

```gdscript
{
	"type": ACTION_DEPART_CARD_FOR_RESUMMON,
	"card": CARD_REF_SELECTED_CARD,
}
```

行为：

- 通过精确引用定位一张当前仍在场的牌；
- 将旧实例从场上清空，但不加入任何移除区；
- 不发出 `CARD_BEFORE_EXILED`，不触发任何“被移除”能力；
- 发出已有的 `card_departed_for_resummon` 纯数据事件，复用现有淡出表现；
- 引用失效、实例已离场或不在场时返回 `NO_EFFECT`。

当离场对象是能力来源时，后续 action 仍使用发动时保存的 `CARD_REF_ABILITY_SOURCE`、目标引用、原格和所属方快照。

### `CARD_REF_LAST_SUMMONED_CARD`

每次顶层 `ACTION_SUMMON_CARD` 创建请求时，将该次请求的精确新实例、卡牌 ID、所属方和目标格写入 `CARD_REF_LAST_SUMMONED_CARD`。召唤请求仍按现有机制立即完整结算。

后续 action 必须重新定位该引用；若召唤被阻止、目标格被占或实例在进场流程中离场，引用重验失败，后续耗内力和额外出牌均不发生。嵌套触发产生的其它召唤不会覆盖外层 action 序列保存的引用。

## 移除前事件扩展

`CARD_BEFORE_EXILED` 当前只为场上牌发出。为支持“你的手牌之外”，将其统一扩展到场上和手牌中的真实移除：

- `trigger_zone` 保存移除前的 `CARD_ZONE_BOARD` 或 `CARD_ZONE_HAND`；
- `trigger_logical_index` 保存移除前格子或手牌逻辑索引；
- `trigger_owner_id` 保存移除前当前所属方；
- `CARD_REF_TRIGGER_CARD` 保存被移除精确实例快照。

触发能力来源仍只从场上扫描，因此手牌能力不会因此生效。既有“自身被移除”声明保持原行为。

`CONDITION_TRIGGER_CARD_OUTSIDE_SOURCE_OWNER_HAND` 在以下情况返回真：

```gdscript
not (
	context.trigger_zone == CARD_ZONE_HAND
	and context.trigger_owner_id == ability_source.current_owner
)
```

## 目录 declaration

```gdscript
const TIYUNZONG_RESUMMON_ACTIVATION = {
	"activation": {
		"input": ACTIVATION_DRAG_TO_TARGET,
		"target_rule": TARGET_OTHER_ALLY_BOARD,
		"costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
		"actions": [
			{
				"type": ACTION_DEPART_CARD_FOR_RESUMMON,
				"card": CARD_REF_SELECTED_CARD,
				"on_invalid_context": STOP_RULE,
			},
			{
				"type": ACTION_DEPART_CARD_FOR_RESUMMON,
				"card": CARD_REF_ABILITY_SOURCE,
				"on_invalid_context": STOP_RULE,
			},
			{
				"type": ACTION_SUMMON_CARD,
				"card": {
					"type": CARD_SPEC_FRESH_COPY,
					"of": CARD_REF_SELECTED_CARD,
				},
				"cell": {
					"type": CELL_REF_INITIAL_CARD_CELL,
					"card": CARD_REF_ABILITY_SOURCE,
				},
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
			{
				"type": ACTION_SPEND_KI,
				"amount": 1,
				"card": CARD_REF_LAST_SUMMONED_CARD,
				"on_invalid_context": STOP_RULE,
			},
			{
				"type": ACTION_GRANT_EXTRA_CARD_PLAY,
				"amount": 1,
				"card": CARD_REF_LAST_SUMMONED_CARD,
			},
		],
	},
}

const TIYUNZONG_LOCKED_FLIP_MOVE = {
	"retained_on_flip": true,
	"triggers": [{
		"event": CARD_BEFORE_FLIPPED,
		"conditions": [
			{"type": CONDITION_TRIGGER_CARD_IS_SELF},
			{"type": CONDITION_SOURCE_HAS_ADJACENT_EMPTY_CELL},
		],
		"actions": [
			{
				"type": ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY,
				"on_invalid_context": STOP_RULE,
			},
			{"type": ACTION_PREVENT_TRIGGER_FLIP},
		],
	}],
}

const TIYUNZONG_DRAW_OUTSIDE_HAND_EXILE = {
	"triggers": [{
		"event": CARD_BEFORE_EXILED,
		"conditions": [{
			"type": CONDITION_TRIGGER_CARD_OUTSIDE_SOURCE_OWNER_HAND,
		}],
		"actions": [{"type": ACTION_DRAW_CARDS, "amount": 1}],
	}],
}
```

卡牌能力：

```gdscript
TiYunZong2.abilities = [
	TIYUNZONG_RESUMMON_ACTIVATION,
]

TiYunZong3.abilities = [
	TIYUNZONG_RESUMMON_ACTIVATION,
	TIYUNZONG_LOCKED_FLIP_MOVE,
]

TiYunZong4.abilities = [
	TIYUNZONG_RESUMMON_ACTIVATION,
	TIYUNZONG_LOCKED_FLIP_MOVE,
	TIYUNZONG_DRAW_OUTSIDE_HAND_EXILE,
]
```

## 顺序、失败与所有权

- 激活目标在提交和第一个离场 action 前均按“其它友方”重验。
- 第一个离场失败时停止整个声明；第二个离场失败时保留第一个已发生的离场并停止。
- 第一张新牌的完整进场结果不会回滚。
- 第二张召唤失败时，`CARD_REF_LAST_SUMMONED_CARD` 无法重新定位，因此带 `STOP_RULE` 的耗内力停止余下声明。
- 新实例的当前所属方均为激活开始时的能力来源所属方。
- 新梯云纵若在自己的进场流程中被翻面或移动，后续耗内力通过精确实例 ID 跟随它，并以耗内力时的当前所属方提供额外出牌。
- 新梯云纵若在进场流程中离场，耗内力失败且不提供额外出牌。
- 多张四阶按场上 `0→8` 顺序各自抽牌；每次抽牌完整结算后才处理下一来源。
- 己方手牌被虎爪绝户手等效果移除不触发梯云纵 4，因此不会形成抽牌—移除循环。

## 事件与表现

不新增梯云纵专属控制器分支。复用：

- `ability_activated`
- `ki_changed`
- `card_departed_for_resummon`
- `card_summoned`
- `attack_started`
- `card_flipped`
- `card_moved`
- `card_flip_prevented`
- `card_drawn`
- `extra_card_play_granted`

两张旧实例依次淡出；两个新实例按声明顺序分别完成墨迹进场和攻击。新梯云纵攻击完成后才播放内力消耗并开放额外出牌。

## 测试

新增定向套件覆盖：

- 三张卡的目录声明与新增词汇校验；
- 目标规则拒绝自身和敌方，允许不相邻友方；
- 原激活支付内力，两张旧实例无移除离场；
- 两个全新实例 ID、目录初始状态和指定的顺序/原格；
- 第一张完整攻击后第二张才进场，新梯云纵完整攻击后才耗内力并提供额外出牌；
- 第二格被占时不回滚第一张，也不耗内力、不提供额外出牌；
- 三、四阶有空格时移动到最低编号并阻止翻面，无空格时正常翻面；
- 锁定移动能力翻面保留；
- 四阶对自身、友方场上牌、敌方场上牌和敌方手牌移除抽牌，对己方手牌移除不抽牌；
- 无移除离场不触发四阶；
- 多来源顺序、来源离场、目标失效和状态复制；
- 相关移动、召唤、移除、回放、搜索和集成套件不回归。

最后运行完整测试套件，并启动 `res://main.tscn` 检查竖屏生产路径和运行时错误。
