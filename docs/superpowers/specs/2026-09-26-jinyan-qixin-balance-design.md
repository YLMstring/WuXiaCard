# 金雁功与七星聚会平衡调整

## 已确认的目录规则

以玩家已写入 `scripts/card_catalog.gd` 的五张卡牌描述为准。金雁功 2–4 阶在**当前持有者的回合结束**时抽一张牌，不再进场后抽牌；抽到的牌仍由在场金雁功赋予内力，4 阶还授予原有保护能力。卡被翻面后，非保留的抽牌和抽牌增益能力照既有规则消失；3–4 阶锁定移动仍保留。七星聚会 3–4 阶只给**其它**友方进场牌增益；进场牌仍须与任一友方相邻。七星聚会 1–2 阶的能力及 4 阶的锁定攻击修正不变。

## 实现边界

金雁功复用 `TRIGGER_END_OWNER_TURN` 和 `CONDITION_TURN_OWNER_IS_SELF`，无需新回合时钟或状态。七星聚会给现有 `CONDITION_TRIGGER_CARD_IS_SELF` 增加可选布尔 `inverted: true`；与既有 `CONDITION_TRIGGER_CARD_IS_ALLY` 组合即为“其它友方”。该条件只比较确切实例，不添加全棋盘扫描。未写 `inverted` 时保持原有的正向语义；若进场连锁中该牌已离场或转为敌方，原有友方条件仍阻止结算。

金雁功进场后结束本回合时可能在同一次 `apply_action` 内抽牌；测试必须区分事件阶段，不能仅以整次行动后的手牌数量判断触发时机。验证覆盖自身回合末、敌方回合末、七星聚会自身进场和其它友方进场。变更不改 UI、存档结构或搜索规则；普通目录能力仍由 native 编译一次，再在模拟与搜索中复用。

## 完整能力声明

以下为受影响卡牌使用的完整声明；原有移动、保护、抽牌增益及攻击修正的内容和能力顺序保持不变。

```gdscript
const TIYUNZONG_LOCKED_FLIP_MOVE: Dictionary = {
	"retained_on_flip": true,
	"triggers": [{
		"event": CARD_BEFORE_FLIPPED,
		"conditions": [
			{"type": CONDITION_TRIGGER_CARD_IS_SELF},
			{"type": CONDITION_SOURCE_HAS_ADJACENT_EMPTY_CELL},
		],
		"actions": [
			{"type": ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY, "on_invalid_context": STOP_RULE},
			{"type": ACTION_PREVENT_TRIGGER_FLIP},
		],
	}],
}

const QZ_SPEND_KI_TO_PREVENT_FLIP: Dictionary = {
	"triggers": [{
		"event": CARD_BEFORE_FLIPPED,
		"conditions": [
			{"type": CONDITION_TRIGGER_CARD_IS_SELF},
			{"type": CONDITION_TRIGGER_CARD_HAS_ADJACENT_ALLY},
			{"type": CONDITION_KI_AT_LEAST, "amount": 1},
		],
		"actions": [
			{"type": ACTION_SPEND_KI, "amount": 1, "on_invalid_context": STOP_RULE},
			{"type": ACTION_PREVENT_TRIGGER_FLIP},
		],
	}],
}

const KUIHUA_MINIMUM_DEFENSE_RETAINED: Dictionary = {
	"retained_on_flip": true,
	"modifiers": [{"type": MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE}],
}

const QZ_JINYAN_END_TURN_DRAW: Dictionary = {
	"triggers": [{
		"event": TRIGGER_END_OWNER_TURN,
		"conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
		"actions": [{"type": ACTION_DRAW_CARDS, "amount": 1}],
	}],
}

const QZ_JINYAN_ALLY_DRAW_GAIN_KI: Dictionary = {
	"triggers": [{
		"event": CARD_AFTER_DRAWN,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_ALLY}],
		"actions": [{"type": ACTION_GAIN_KI, "amount": 1,
		             "card": CARD_REF_TRIGGER_CARD}],
	}],
}

const QZ_JINYAN_ALLY_DRAW_GAIN_KI_AND_PROTECT: Dictionary = {
	"triggers": [{
		"event": CARD_AFTER_DRAWN,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_ALLY}],
		"actions": [
			{"type": ACTION_GAIN_KI, "amount": 1, "card": CARD_REF_TRIGGER_CARD},
			{"type": ACTION_GRANT_TRIGGER_CARD_ABILITY,
			 "ability": QZ_SPEND_KI_TO_PREVENT_FLIP},
		],
	}],
}

const QZ_QIXIN_ANY_ALLIED_NEIGHBOR_ENTRY: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_SUMMONED,
		"conditions": [
			{"type": CONDITION_TRIGGER_CARD_IS_ALLY},
			{"type": CONDITION_TRIGGER_CARD_IS_SELF, "inverted": true},
			{"type": CONDITION_TRIGGER_CARD_HAS_ADJACENT_ALLY},
		],
		"actions": [
			{"type": ACTION_GAIN_KI, "amount": 1, "card": CARD_REF_TRIGGER_CARD},
			{"type": ACTION_GRANT_TRIGGER_CARD_ABILITY,
			 "ability": QZ_SPEND_KI_TO_PREVENT_FLIP},
		],
	}],
}
```

除显式声明 `retained_on_flip: true` 的移动和攻击修正外，其它能力保持默认不随翻面保留。

受影响的卡牌必须采用以下**精确能力顺序**：

```gdscript
&"JinYanGong2": [QZ_JINYAN_END_TURN_DRAW, QZ_JINYAN_ALLY_DRAW_GAIN_KI]
&"JinYanGong3": [TIYUNZONG_LOCKED_FLIP_MOVE,
	QZ_JINYAN_END_TURN_DRAW, QZ_JINYAN_ALLY_DRAW_GAIN_KI]
&"JinYanGong4": [TIYUNZONG_LOCKED_FLIP_MOVE,
	QZ_JINYAN_END_TURN_DRAW, QZ_JINYAN_ALLY_DRAW_GAIN_KI_AND_PROTECT]
&"QiXinJuHui3": [QZ_SPEND_KI_TO_PREVENT_FLIP,
	QZ_QIXIN_ANY_ALLIED_NEIGHBOR_ENTRY]
&"QiXinJuHui4": [KUIHUA_MINIMUM_DEFENSE_RETAINED,
	QZ_SPEND_KI_TO_PREVENT_FLIP, QZ_QIXIN_ANY_ALLIED_NEIGHBOR_ENTRY]
```

七星聚会 1–2 阶的能力数组不变。金雁功的抽牌与其它回合末触发一起按棋盘格与能力顺序结算；牌库空或手牌满时沿用现有 `ACTION_DRAW_CARDS` 行为。
