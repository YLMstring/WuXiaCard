# 吸星大法、北冥神功与易筋神功设计

日期：2026-08-20

## 目标

实装 `XiXinDaFa4`（吸星大法）、`XiXinDaFa5`（北冥神功）与
`YiJJ5`（易筋神功）的完整卡牌描述。所有规则走 `DuelSimulator` 的
catalog 声明与纯数据事件路径，不在 `DuelController`、搜索或界面中加入卡名分支。

四边存储值严格等于 `[-1, -1, -1, -1]` 的牌不能被吸取点数；它仍可被
吸取内力，也仍可从易筋神功获得内力。

## 通用规则原语

### `ACTION_TRANSFER_CARD_RESOURCE`

新增通用资源转移动作。声明包含：

```gdscript
{
	"type": ACTION_TRANSFER_CARD_RESOURCE,
	"from": CARD_REF_SELECTED_CARD,
	"to": CARD_REF_ABILITY_SOURCE,
	"amount": 1,
	"resource": RESOURCE_KI,
	"fallback_resource": RESOURCE_POWERS,
}
```

执行规则：

1. 解析并重新验证两个精确实例。
2. 首先尝试从 `from` 向 `to` 转移一单位首选资源。
3. 首选资源不可用时，才尝试 `fallback_resource`。
4. 只有来源牌实际损失资源，接收牌才获得资源。
5. 内力转移使来源内力减一、接收方内力加一，并分别发出既有
   `ki_changed` 事件。
6. 一单位点数表示来源四边各减一、接收方四边各加一。来源每边最低为
   0；只要至少一边实际减少，接收方四边都各加一。
7. 四边 `-1` 拒绝点数转移。四边已经没有任何可减少点数的普通牌也不
   会令接收方增长。
8. 来源因点数变为四边 0 时，沿用普通点数变化的真实移除流程。

同一次点数转移中的来源减点与接收方加点属于同一展示批次；两张牌先
共同停顿，再同时播放点数变化。不同被吸取目标仍按规则顺序逐张结算。

### `ACTION_DISTRIBUTE_KI`

新增通用循环分配内力动作。声明包含来源牌、目标选择器和每次转移数量：

```gdscript
{
	"type": ACTION_DISTRIBUTE_KI,
	"from": CARD_REF_ABILITY_SOURCE,
	"amount": 1,
	"selector": {
		"zones": [CARD_ZONE_BOARD, CARD_ZONE_HAND],
		"conditions": [
			{"type": CONDITION_SELECTED_CARD_IS_ALLY},
			{"type": CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
			{"type": CONDITION_SELECTED_CARD_CAN_SPEND_KI},
		],
	},
}
```

选择器先按区域顺序建立精确实例快照：场上按格子 `0→8`，然后当前所属
方手牌从左到右。动作循环遍历快照，每次将来源的一点内力转给当前合法
目标，直到来源内力耗尽。

每次转移前，目标必须仍存在、仍为来源当前所属方的其它友方牌，并仍有
当前生效的耗内力能力。失效目标从后续轮次跳过，不补入快照外的新牌。
若一整轮没有合法接收者，动作停止并让来源保留剩余内力。

### 既有动作扩展

`ACTION_GAIN_KI` 增加可选的 `card` 引用，行为与 `ACTION_SPEND_KI` 的
可选引用一致。未声明 `card` 时仍默认作用于能力来源，保持现有声明简洁。

新增 `CONDITION_SELECTED_CARD_CAN_SPEND_KI`，通过一个独立的通用资格
函数检查牌当前仍生效的完整能力声明。只要任一能力的主动费用或自动触发
动作树（包括嵌套动作）含有 `ACTION_SPEND_KI` 或
`ACTION_SPEND_ALL_KI`，该牌就能耗内力。有凤来仪这类主动耗内力能力与
太岳三青峰这类自动耗内力能力都符合条件。

资格判断只读取 `active_abilities` 中当前没有被效果门禁、翻面清理或临时
压制停用的条目。已经失去或当前受压制的耗内力能力不提供资格。该判断与牌
当前在手牌还是场上无关；手牌中的能力不会因此触发，只是该牌可以接收
内力。现有 `card_uses_ki` 与内力珠显示语义保持不变，避免借本规则改动既有
界面表现。

新增数据驱动的 `CONDITION_SELECTED_CARD_CAN_TRANSFER_RESOURCE`。它接收
与转移动作相同的 `resource`、`fallback_resource` 和 `amount`，只判断候选
牌当前是否至少能提供首选资源或回退资源，不改变状态。吸取手牌时先用这个
条件过滤，再应用 `limit = 1`，因此最左候选若无内力且不能提供点数，会继续
向右选择下一张合法牌。执行转移动作时仍按相同规则重新验证精确实例。

新增 `MODIFIER_SELF_ATTACKS_ALL`。携带者自己的普通攻击与指定攻击可将
敌方和友方都作为目标。攻击者友方被成功攻击后，沿用通用规则翻成攻击者
的敌方。该 modifier 不影响其它牌的攻击。

## 共用吸功能力

吸星大法与北冥神功首次翻面后获得三个互相独立的非保留能力条目。

### 回合开始吸取

在来源当前所属方的回合开始时：

1. 用手牌选择器从左到右寻找当前所属方第一张存在可转移资源的手牌。
2. 对它执行一次 `ACTION_TRANSFER_CARD_RESOURCE`。
3. 再用场上选择器按格子 `0→8` 快照所有与来源相邻的其它友方。
4. 按快照顺序逐张执行相同转移动作。

每张目标独立判断：目标有内力时转移一点内力；目标没有内力时改为吸取
一点点数。四边 `-1` 的无内力目标以及没有任何可减少点数的普通目标在
选择阶段即不合法；手牌选择继续向右寻找下一张合法牌。四边 `-1` 的有
内力目标仍正常转移内力。每张目标完全结算后才处理下一张。

相邻目标轮到结算时必须仍与来源相邻。移动、离场、翻面后变成敌方或其它
失效情况都令该快照目标跳过，不顺延选取新目标。

### 防守视为零

非保留 modifier 令来源在判断能否被攻击时四边防守点数都视为 0。它不
修改或隐藏存储点数，不影响显示，也不影响来源主动攻击时的点数。

### 再次翻面后分配并攻击

独立的自身 `CARD_AFTER_FLIPPED` 条目先执行 `ACTION_DISTRIBUTE_KI`，再
执行 `ACTION_STANDARD_ATTACK_WITH_SELF`。即使没有合法内力接收者，来源
也保留剩余内力并照常尝试攻击。

该条目是首次翻面后新授予的非保留能力。来源再次翻面时，普通非保留能力
先失去；这个隔离的自身翻面后条目结算分配和攻击，然后按全局翻面清理规则
失去。来源离场、没有合法攻击目标或已达到当前所属方每回合 20 次攻击上限
时，攻击沿用现有规则自然无效。

## 吸星大法 `XiXinDaFa4`

初始能力严格拆成三个条目：

1. `retained_on_flip = true` 的 `MODIFIER_SELF_ATTACKS_ALL` 锁定能力。
2. 自身进场后仅执行 `ACTION_FLIP_SELF` 的非保留触发。
3. 隔离的自身 `CARD_AFTER_FLIPPED` 非保留触发，依次授予“回合开始
   吸取”“防守视为零”“再次翻面后分配并攻击”三个能力条目。

进场后的第一次自我翻面只改变所属方并授予三个新效果，不执行内力分配或
额外攻击。由于所属方已经改变，沿用既有规则取消这次标准进场攻击；翻面
保留的不分敌我 modifier 只影响来源之后实际发起的攻击。

## 北冥神功 `XiXinDaFa5`

北冥神功使用与吸星大法相同的进场自翻、首次翻面授予和三个后续效果。
它不声明 `MODIFIER_SELF_ATTACKS_ALL`，所以所有攻击按当时的普通敌我规则
选择目标。

## 易筋神功 `YiJJ5`

### 进场后

1. 用手牌选择器快照来源当前所属方当时已有的全部手牌。
2. 对每个快照实例执行 `ACTION_CHANGE_POWERS +1`。
3. 对每个快照实例执行带 `card = CARD_REF_SELECTED_CARD` 的
   `ACTION_GAIN_KI +1`。
4. 完成全部旧手牌强化后，执行默认 `ACTION_DRAW_CARDS` 一张。

所有旧手牌的点数变化使用同一展示批次，同时停顿并同时播放。四边 `-1`
的牌忽略点数增加，但同一选择规则中的内力增加仍会执行。后抽到的牌不在
快照中，因此不获得这次强化。

### 翻面回到最初一方后

另设一个隔离的、`retained_on_flip = true` 的自身
`CARD_AFTER_FLIPPED` 条目。它同时要求：

- 触发牌是自身；
- 翻面完成后的当前所属方等于该实例的 `original_owner`。

条件满足时，重复“强化翻面后当前所属方的旧手牌，然后抽一张”的完整流程。
翻到非最初一方时不触发。该锁定条目持续保留，以后每次重新回到最初一方
都能再次触发。

## 完整 catalog declaration

下面的声明是实现时写入 `card_catalog.gd` 的完整目标形态。除注册对应的
action、condition、resource 和 modifier 常量外，不允许在执行器中补充任何
卡名隐式语义。

```gdscript
const RESOURCE_KI: StringName = &"ki"
const RESOURCE_POWERS: StringName = &"powers"

const ACTION_TRANSFER_CARD_RESOURCE: StringName = &"transfer_card_resource"
const ACTION_DISTRIBUTE_KI: StringName = &"distribute_ki"
const CONDITION_SELECTED_CARD_CAN_SPEND_KI: StringName = &"selected_card_can_spend_ki"
const CONDITION_SELECTED_CARD_CAN_TRANSFER_RESOURCE: StringName = (
	&"selected_card_can_transfer_resource"
)
const MODIFIER_SELF_ATTACKS_ALL: StringName = &"self_attacks_all"

const XIXING_BEIMING_TRANSFER: Dictionary = {
	"type": ACTION_TRANSFER_CARD_RESOURCE,
	"from": CARD_REF_SELECTED_CARD,
	"to": CARD_REF_ABILITY_SOURCE,
	"amount": 1,
	"resource": RESOURCE_KI,
	"fallback_resource": RESOURCE_POWERS,
}

const XIXING_BEIMING_TURN_ABSORB: Dictionary = {
	"triggers": [{
		"event": TRIGGER_START_OWNER_TURN,
		"conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
		"actions": [
			{
				"type": ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [CARD_ZONE_HAND],
					"conditions": [
						{"type": CONDITION_SELECTED_CARD_IS_ALLY},
						{
							"type": CONDITION_SELECTED_CARD_CAN_TRANSFER_RESOURCE,
							"amount": 1,
							"resource": RESOURCE_KI,
							"fallback_resource": RESOURCE_POWERS,
						},
					],
					"limit": 1,
				},
				"actions": [XIXING_BEIMING_TRANSFER],
			},
			{
				"type": ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [CARD_ZONE_BOARD],
					"conditions": [
						{"type": CONDITION_SELECTED_CARD_IS_ALLY},
						{"type": CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
						{"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
						{
							"type": CONDITION_SELECTED_CARD_CAN_TRANSFER_RESOURCE,
							"amount": 1,
							"resource": RESOURCE_KI,
							"fallback_resource": RESOURCE_POWERS,
						},
					],
				},
				"actions": [XIXING_BEIMING_TRANSFER],
			},
		],
	}],
}

const XIXING_BEIMING_ZERO_DEFENSE: Dictionary = {
	"modifiers": [{
		"type": MODIFIER_DEFENDING_POWER_OVERRIDE,
		"value": 0,
	}],
}

const XIXING_BEIMING_AFTER_FLIP_DISTRIBUTE: Dictionary = {
	"triggers": [{
		"event": CARD_AFTER_FLIPPED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [
			{
				"type": ACTION_DISTRIBUTE_KI,
				"from": CARD_REF_ABILITY_SOURCE,
				"amount": 1,
				"selector": {
					"zones": [CARD_ZONE_BOARD, CARD_ZONE_HAND],
					"conditions": [
						{"type": CONDITION_SELECTED_CARD_IS_ALLY},
						{"type": CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
						{"type": CONDITION_SELECTED_CARD_CAN_SPEND_KI},
					],
				},
			},
			{"type": ACTION_STANDARD_ATTACK_WITH_SELF},
		],
	}],
}

const XIXING_BEIMING_AFTER_INITIAL_FLIP_GRANT: Dictionary = {
	"triggers": [{
		"event": CARD_AFTER_FLIPPED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [
			{
				"type": ACTION_GRANT_ABILITY_TO_SELF,
				"ability": XIXING_BEIMING_TURN_ABSORB,
			},
			{
				"type": ACTION_GRANT_ABILITY_TO_SELF,
				"ability": XIXING_BEIMING_ZERO_DEFENSE,
			},
			{
				"type": ACTION_GRANT_ABILITY_TO_SELF,
				"ability": XIXING_BEIMING_AFTER_FLIP_DISTRIBUTE,
			},
		],
	}],
}

const XIXING_BEIMING_ENTRY_FLIP: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_FLIP_SELF,
			"new_owner": OWNER_OPPONENT_OF_ABILITY_SOURCE,
		}],
	}],
}

const XIXING_SELF_ATTACKS_ALL: Dictionary = {
	"retained_on_flip": true,
	"modifiers": [{"type": MODIFIER_SELF_ATTACKS_ALL}],
}

const YIJIN_HAND_BATCH: StringName = &"yijin_all_hand"

const YIJIN_STRENGTHEN_HAND_ACTIONS: Array = [
	{
		"type": ACTION_FOR_EACH_SELECTED_CARD,
		"selector": {
			"zones": [CARD_ZONE_HAND],
			"conditions": [
				{"type": CONDITION_SELECTED_CARD_IS_ALLY},
				{"type": CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE},
			],
		},
		"actions": [{
			"type": ACTION_CHANGE_POWERS,
			"amount": 1,
			"card": CARD_REF_SELECTED_CARD,
		}],
		"power_change_batch_group": YIJIN_HAND_BATCH,
	},
	{
		"type": ACTION_FOR_EACH_SELECTED_CARD,
		"selector": {
			"zones": [CARD_ZONE_HAND],
			"conditions": [{"type": CONDITION_SELECTED_CARD_IS_ALLY}],
		},
		"actions": [{
			"type": ACTION_GAIN_KI,
			"amount": 1,
			"card": CARD_REF_SELECTED_CARD,
		}],
	},
	{"type": ACTION_DRAW_CARDS, "amount": 1},
]

const YIJIN_AFTER_SUMMONED: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": YIJIN_STRENGTHEN_HAND_ACTIONS,
	}],
}

const YIJIN_RETURNED_TO_ORIGINAL: Dictionary = {
	"retained_on_flip": true,
	"triggers": [{
		"event": CARD_AFTER_FLIPPED,
		"conditions": [
			{"type": CONDITION_TRIGGER_CARD_IS_SELF},
			{"type": CONDITION_TRIGGER_CARD_ORIGINAL_OWNER_IS_SELF},
		],
		"actions": YIJIN_STRENGTHEN_HAND_ACTIONS,
	}],
}
```

对应卡牌定义中的最终 `abilities` 数组为：

```gdscript
&"XiXinDaFa4": {
	# 其它现有字段保持不变。
	"abilities": [
		XIXING_SELF_ATTACKS_ALL,
		XIXING_BEIMING_ENTRY_FLIP,
		XIXING_BEIMING_AFTER_INITIAL_FLIP_GRANT,
	],
},

&"XiXinDaFa5": {
	# 其它现有字段保持不变。
	"abilities": [
		XIXING_BEIMING_ENTRY_FLIP,
		XIXING_BEIMING_AFTER_INITIAL_FLIP_GRANT,
	],
},

&"YiJJ5": {
	# 其它现有字段保持不变。
	"abilities": [
		YIJIN_AFTER_SUMMONED,
		YIJIN_RETURNED_TO_ORIGINAL,
	],
},
```

## 事件与展示

通用动作只产生纯数据事件。控制器继续消费已有的 `ki_changed`、
`powers_changed`、`card_exiled` 和攻击事件，不加入三张卡的专用分支。

吸取不同目标按声明顺序展示；同一次点数转移的两张牌同时变化。易筋神功
影响的所有可变点数手牌在同一批次同时变化。内力事件保持转移的严格先后
顺序，确保来源和目标状态在攻击前已完全更新。

### 标准攻击中途翻面

标准攻击的当前目标以及由它引发的全部连锁先完整结算。若这段结算事件中
出现攻击者精确实例的任意 `card_flipped`，立即结束本次标准攻击的剩余目标
循环。即使攻击者在同一段连锁中连续翻面两次并最终回到原所属方，也仍然
视为中途翻面过，不再进行后续攻击。攻击者移动、离场或更换实例时继续沿用
既有终止规则。

### 能力同步与资源动画

展示 `ability_gained` 或 `ability_lost` 时仍需同步最终能力声明和由能力决定
的外观，但不得提前覆盖卡牌画面当前显示的 `powers` 与 `ki`。翻面动画、
能力获得或失去动画以及点数变化前的停顿期间，卡牌持续显示事件发生前的
资源数值；只有轮到对应 `powers_changed` 或 `ki_changed` 事件时，才写入并
播放新的资源数值。该规则是通用展示规则，不为吸星大法添加卡名分支。

## 测试

新增聚焦测试套件并加入 `tools/run_tests.ps1`，覆盖：

- 三张卡的完整能力条目、保留标记、隔离的自身翻面后声明和 catalog 校验；
- 内力优先、点数回退、来源实际增长、部分零边、四边归零移除；
- 四边 `-1` 无法被吸取点数，但可以被吸取内力；
- 手牌最左候选没有可转移资源时继续向右，直到找到第一张可吸取牌或耗尽
  手牌候选；
- 最左手牌优先、相邻友方 `0→8` 顺序和逐牌重验证；
- 内力分配按场上后手牌顺序循环、失效目标跳过、无人接收时保留内力；
- 可耗内力资格同时识别有凤来仪式主动费用、太岳三青峰式自动触发动作、
  嵌套耗内力动作与 `ACTION_SPEND_ALL_KI`，并排除已失去或受压制的能力；
- 首次自翻仅授予能力，再次翻面才分配并攻击；
- 吸星自己的攻击不分敌我，北冥保持普通目标策略；
- 标准攻击首个目标的连锁令攻击者翻面后，即使翻回原所属方也停止剩余目标；
- 易筋旧手牌的同步点数变化、逐牌内力增加、抽牌顺序、四边 `-1` 例外；
- 易筋只在翻回最初一方后重复触发。

展示集成测试另覆盖：翻面与能力同步发生在点数批次之前时，卡牌在整个
前置动画和停顿期间保持 `previous_powers`，随后才进入点数变化动画。

实现后运行新增套件、相关模拟器/展示套件、完整 Windows 测试命令，并实际
启动对局检查吸取、分配、点数批次和后续攻击的播放顺序。
