# 剑发琴音、雁回祝融与额外出牌设计

日期：2026-08-09

## 目标

实装衡山派的剑发琴音1–3和雁回祝融3–4，并完成三项规则升级：

1. 玩家与敌人的五张起始手牌在每场对局开始时分别独立洗混；
2. 现有“额外回合”改为可累加、只能从手牌出牌的“额外出牌”；
3. 万花剑法改用新的通用召唤动作，不再依赖专用相邻复制动作。

`DuelSimulator` 继续作为玩家、测试模式、AI和回放的唯一规则权威。控制器只呈现模拟器返回的纯数据事件。

## 已确认的规则

### 起始手牌洗混

- 玩家与敌方主卡组分别洗混，互不共享洗牌顺序。
- 两方各有可注入的固定测试种子；生产环境使用随机种子。
- 回放在两方起始手牌和侧卡组洗混完成后保存初始状态，因此重放保持实际开局顺序。
- 测试可以使用负种子停用指定一方的起手洗牌，延续当前敌方测试约定。

### 额外出牌

- 新目录动作 `ACTION_GRANT_EXTRA_CARD_PLAY` 接受正整数 `amount`。
- 每次有效授予把额度累加到当前行动方。
- 额外出牌期间只能使用 `TYPE_PLAY`，不能发动指定能力。
- 每次额外出牌都是一个独立的AI决策窗口，重新获得该敌人的完整5秒或10秒搜索预算。
- 每一个真实行动（包括额外出牌）继续令 `turn_count` 增加1，用于回放、搜索和200行动防循环上限。
- 额外增加独立的玩家回合状态，使额外出牌不重复触发回合开始或回合结束效果。
- 行动授予的额度先全部使用；额度归零后，回合结束触发器只结算一次。
- 孟获在该次回合结束结算中花费所有符合条件的孟获内力，但同一批请求合并为总共1次额外出牌。
- 孟获授予的额外出牌完成后，不再次派发回合结束事件；直接完成本回合清理并进入下一方回合。
- “直到当前回合结束”的临时效果覆盖整段额外出牌序列，在最终换手前统一恢复。
- 孟获在回合结束事件已经处理后又于额外出牌期间获得的内力，保留到其下一个玩家回合结束时处理。
- 若当前没有手牌或没有空格，剩余额度无法使用并失效；随后按上述时序结束回合或对局。
- 事件由 `extra_card_play_granted` 表达。表现复用原金色棋盘描边并显示“额外出牌”，删除金珠汇聚，不显示来源飞珠。

实现采用状态机原生支持：`DuelState`保存剩余额度、回合结束触发器是否已处理，以及独立玩家回合编号。搜索键、状态复制、回放快照和AI合法行动生成都必须包含这些字段。

## 通用目录词汇

新增或替换以下英文声明：

```gdscript
const TARGET_OTHER_ALLY_BOARD := &"other_ally_board"

const CONDITION_SOURCE_HAS_EMPTY_BETWEEN_ENEMY := \
	&"source_has_empty_between_enemy"

const ACTION_MOVE_SELF_TO_FIRST_EMPTY_BETWEEN_ENEMY := \
	&"move_self_to_first_empty_between_enemy"
const ACTION_GRANT_EXTRA_CARD_PLAY := &"grant_extra_card_play"
const ACTION_RETURN_CARD_TO_HAND := &"return_card_to_hand"
const ACTION_SUMMON_CARD := &"summon_card"

const CARD_REF_ABILITY_SOURCE := &"ability_source"
const CARD_REF_SELECTED_CARD := &"selected_card"
const CARD_SPEC_FRESH_COPY := &"fresh_copy"
const CELL_REF_INITIAL_CARD_CELL := &"initial_card_cell"
const CELL_REF_FIRST_ADJACENT_EMPTY := &"first_adjacent_empty"
```

`ACTION_RETURN_CARD_TO_HAND`接受卡牌引用。返回手牌遵守现有规则：返回的是目录新副本；若手牌已满，该实例改为移除。

`ACTION_SUMMON_CARD`接受两个声明对象：

- `card`可以是当前被选实例，也可以是某张引用卡的目录新副本；
- `cell`可以是某张引用卡在本规则开始时的格位，也可以是相对某张引用卡的首个相邻空格。

规则开始时只保存引用卡的不可变身份和初始位置，不创建临时卡牌区域。每项动作执行前继续按精确 `instance_id` 验证所引用实例；若声明允许 `INVALID_CONTEXT`，才停止该规则的剩余动作。

## 剑发琴音

### 进场移动

剑发琴音1–3在 `TRIGGER_CARD_AFTER_SUMMONED` 响应自身：

1. 检查上下左右方向是否存在“能力来源—空格—敌方”的三格直线；
2. 若存在多个合法中间空格，按棋盘格索引升序选择第一个；
3. 移动到该空格；
4. 进场流程继续，剑发琴音从新位置执行正常攻击。

该行为由 `CONDITION_SOURCE_HAS_EMPTY_BETWEEN_ENEMY` 与 `ACTION_MOVE_SELF_TO_FIRST_EMPTY_BETWEEN_ENEMY` 表达。动作在解析移动前继续派发通用 `CARD_BEFORE_MOVED`。

### 指定能力

剑发琴音2–3拥有1点初始内力和以下指定能力：

```gdscript
"activation": {
	"input": ACTIVATION_DRAG_TO_TARGET,
	"target_rule": TARGET_ADJACENT_EMPTY_BOARD,
	"costs": [{"type": &"ki", "amount": 1}],
	"actions": [
		{
			"type": ACTION_MOVE_SELF_TO_TARGET,
			"on_invalid_context": STOP_RULE,
		},
		{"type": ACTION_GRANT_EXTRA_CARD_PLAY, "amount": 1},
	],
}
```

只有移动成功才授予额外出牌。剑发琴音3另有 `CARD_BEFORE_MOVED` 能力：任何来源令其移动前，使当时所有相邻敌方失去非保留能力，直到整个当前玩家回合结束。该部分复用天柱云气4现有声明。

## 雁回祝融

### 翻面前替换

雁回祝融3–4在 `CARD_BEFORE_FLIPPED` 响应自身，并用手牌选择器取得最左侧轻剑。必须至少有一张符合条件的手牌才能执行：

```gdscript
{
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
}
```

- 若手牌未满，雁回祝融以目录新副本进入手牌；若已满，雁回祝融被移除。
- 所选轻剑随后从其当前手牌位置进入雁回祝融原格，完整执行进场前、进场、进场后和正常攻击。
- 原翻面追踪原雁回祝融实例；该实例已经离场，因此原翻面不再发生。
- 不使用预留或临时卡牌区域。

### 四阶指定能力

雁回祝融4拥有1点初始内力，只能指定其他友方：

```gdscript
"activation": {
	"input": ACTIVATION_DRAG_TO_TARGET,
	"target_rule": TARGET_OTHER_ALLY_BOARD,
	"costs": [{"type": &"ki", "amount": 1}],
	"actions": [
		{
			"type": ACTION_RETURN_CARD_TO_HAND,
			"card": CARD_REF_SELECTED_CARD,
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
}
```

目标返回手牌时使用目录新副本；满手时目标被移除。无论目标回手还是移除，只要原格仍合法，就在原格生成新的雁回祝融4并完整结算召唤和攻击。

## 万花剑法迁移

删除专用动作 `ACTION_SUMMON_FRESH_COPY_IN_FIRST_ADJACENT_EMPTY`。万花剑法的受击复制改为：

```gdscript
{
	"type": ACTION_SUMMON_CARD,
	"card": {
		"type": CARD_SPEC_FRESH_COPY,
		"of": CARD_REF_ABILITY_SOURCE,
	},
	"cell": {
		"type": CELL_REF_FIRST_ADJACENT_EMPTY,
		"card": CARD_REF_ABILITY_SOURCE,
	},
}
```

既有行为不变：按棋盘格顺序选择首个相邻空格，新副本完整进场并攻击；没有合法空格时为 `NO_EFFECT`。

## 数据流和表现

- 执行器返回额外出牌请求、返回手牌、移除、召唤、移动和能力事件；模拟器决定额度和回合边界。
- 控制器按事件顺序播放现有移动、回手渐隐、移除和墨召表现。
- `extra_card_play_granted` 只播放简短棋盘描边与状态文字，不再创建金珠。
- 状态文字在额外出牌期间明确提示只能拖动手牌。
- AI每完成一次额外出牌后，由现有行动协调器对最新状态重新发起一次完整预算搜索。
- 回放记录每次额外出牌为独立成功行动，并从保存的额度/回合阶段状态重演。

## 失败与边界处理

- 移动目标不再合法：移动动作返回允许声明的 `INVALID_CONTEXT`，不授予额外出牌。
- 所选轻剑在轮到召唤动作前不再位于原持有者手牌：召唤动作跳过；雁回祝融先前的回手或移除不回滚。
- 雁回祝融4目标在返回动作前失效：规则停止，不生成复制；目标成功离场后原格若被未来触发占用，召唤动作跳过。
- 额外出牌额度只属于当前活动玩家；换手时必须清零。
- 对局在效果队列清空且棋盘仍满时按现有规则结束，不为了不可使用的额外出牌延迟结束。
- 搜索键必须包含额度、结束触发器状态和玩家回合编号，避免把不同阶段误判为相同局面。

## 测试与验收

新增聚焦模拟器测试并更新现有孟获、万花剑法、AI、回放和集成测试：

- 两方起手独立洗混、同种子可重现、负种子可停用；
- 剑发琴音所有阶级、多个方向的棋盘顺序、移动后攻击及移动失败；
- 额外出牌只能打手牌、额度累加、无合法出牌时失效；
- 多孟获仍合并一次，且额外出牌中不重复开始/结束触发；
- 临时能力在整个序列结束前不恢复；
- AI每次机会重新搜索并只产生手牌行动；
- 雁回祝融最左轻剑、满手移除、原翻面取消、新卡正常进场攻击；
- 雁回祝融4排除自身、回手/满手移除和源复制；
- 万花剑法迁移后行为与事件顺序保持不变；
- 金珠节点不再参与额外出牌表现，棋盘描边和提示仍按顺序完成；
- 全量测试通过后，在生产场景的测试模式中实际走查一次剑发琴音指定额外出牌、一次雁回祝融替换及一次孟获额外出牌，并检查控制台和调试器。
