# 衡山三组卡牌能力设计

日期：2026-08-08

## 范围

本次实装八张已经存在于 `card_catalog.gd` 的衡山派卡牌：

- 云雾十三式2–3；
- 一剑落九雁1–3；
- 天柱云气2–4。

卡牌的图片、点数、品阶、武器、描述和风味文本保持现状。本次只补充声明式能力、通用规则原语、状态处理、表现同步、测试和维护文档。

## 核心语义

### 暂时失去效果

“失去效果”表示失去所有 ability，但带有 `retained_on_flip = true` 的 ability 永远不会因此失去。

“失去效果，直到当前回合结束”按精确卡牌实例处理：

1. 效果结算时，将该实例当时拥有的全部非保留 ability 从活动列表中移出；
2. 按批次记录每项 ability 的原始位置和到期回合；
3. 同回合稍后新获得的 ability 立即生效，不受已经结算完毕的旧失效效果影响；
4. 若同回合再次受到一次失效效果，新获得的非保留 ability 可被新效果移出；
5. 回合结束触发全部结算完毕后，按批次逆序和原始位置恢复仍应恢复的 ability；
6. 若该实例在恢复前翻面，活动及暂存区内的所有非保留 ability 永久丢失，不能在回合末恢复；
7. 保留 ability 始终留在活动列表，不产生对应的失去或恢复事件。

暂存数据保存在卡牌实例 Dictionary 中。`DuelState` 的深复制和完整状态键编码会自然包含该数据，使 AI、回放和真人规则保持一致。精确实例在棋盘上移动或交换不会丢失暂存数据。若实例离开棋盘但仍存在于其他区域，回合末仍按实例恢复；被翻面时则按上述规则永久清除非保留暂存能力。

每项实际移除的 ability 产生一个 `ability_lost` 事件；每项实际恢复的 ability 产生一个 `ability_gained` 事件。回合末恢复发生在 `TRIGGER_END_OWNER_TURN` 全部结算之后，因此恢复的 ability 不会补触发刚结束的回合结束事件。

### 进场前阶段

新增 `TRIGGER_CARD_BEFORE_SUMMONED`。正常手牌进场和效果生成的进场均采用以下顺序：

1. 将精确实例逻辑放入目标格并产生现有放置/生成事件；
2. 只结算该精确实例自身的 `TRIGGER_CARD_BEFORE_SUMMONED`；
3. 结算全场 `TRIGGER_CARD_SUMMONED`；
4. 结算该实例自身的 `TRIGGER_CARD_AFTER_SUMMONED`；
5. 若原有进场攻击条件仍成立，执行标准攻击。

因此云雾十三式会先于苍松迎客等全场进场反应使敌方失效。该牌在规则上已经占据目标格，便于选择相对敌我和棋盘目标，但其“进场前”阶段优先于任何全场进场反应。

### 移动前阶段

新增 `CARD_BEFORE_MOVED`。所有实际卡牌移动都必须从同一规则路径派发该事件，包括：

- 指定移动；
- 自动移动到首个相邻空格；
- 交换过程中来源牌与目标牌各自的实际移动；
- 未来其他能力造成的移动。

事件上下文包含移动牌的精确实例、当前拥有者、当前格和预定目标格。只有先通过初始合法性检查的移动请求才派发移动前事件；事件全部结算后，规则重新验证精确实例、起点和目标格，再执行现有 `card_moved` 状态变更与表现事件。若移动请求在初始检查时已经失败，例如没有相邻空格，则不派发移动前事件；若未来的移动前效果令一个原本合法的请求失效，则保留已经结算的移动前效果，但不产生 `card_moved`。

交换继续遵循既定概念顺序：先暂存目标牌，来源牌移动；再暂存来源牌、放回目标牌，目标牌移动；最后放回来源牌。两张牌分别在自身实际移动前派发一次 `CARD_BEFORE_MOVED`。交换开始及执行时都要求两张牌相邻；任何交换效果在结算时若不再相邻都会失败。

## 通用声明式原语

新增或扩展以下目录词汇：

- 事件 `TRIGGER_CARD_BEFORE_SUMMONED`；
- 事件 `CARD_BEFORE_MOVED`；
- 条件 `CONDITION_MOVING_CARD_IS_SELF`；
- 条件 `CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE`；
- 条件 `CONDITION_SOURCE_HAS_ADJACENT_EMPTY_CELL`；
- 选择条件 `CONDITION_SELECTED_CARD_FLIPPED_BY_CURRENT_ATTACK`；
- action `ACTION_TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES`；
- action `ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY`。

所有目录中的事件、条件、动作、selector 字段和值都使用上述英文常量；中文只用于本文解释和玩家可见的卡牌文本。

`for_each_selected_card` 接收当前事件上下文，使选择器能够根据 `attack_flips` 选择精确实例。选择和重验证都跟踪 `instance_id`。选择器的 `required_count` 继续决定整组是否执行。

`for_each_selected_card` 在嵌套动作结束后重新定位能力来源，并将能力来源的当前棋盘格返回给外层动作。这样交换之后的外层标准攻击会从能力来源的新位置发起，而不是从历史格或被选择牌的位置发起。

“首个”继续使用项目既定的行优先棋盘顺序，即选择最低棋盘索引。

## 卡牌声明

### 云雾十三式2

```gdscript
{
	"event": TRIGGER_CARD_BEFORE_SUMMONED,
	"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
	"actions": [{
		"type": ACTION_FOR_EACH_SELECTED_CARD,
		"selector": {
			"zones": [CARD_ZONE_BOARD],
			"conditions": [{"type": CONDITION_SELECTED_CARD_IS_ENEMY}],
		},
		"actions": [{
			"type": ACTION_TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES,
		}],
	}],
}
```

### 云雾十三式3

拥有云雾十三式2的进场前 ability，并额外拥有：

```gdscript
{
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
}
```

若相邻敌方不是恰好一张，或在动作重验证时不再相邻，则不交换。

### 一剑落九雁1

没有 ability。

### 一剑落九雁2

```gdscript
{
	"event": TRIGGER_CARD_AFTER_ATTACK,
	"conditions": [{"type": CONDITION_ATTACKER_CARD_IS_SELF}],
	"actions": [{
		"type": ACTION_FOR_EACH_SELECTED_CARD,
		"selector": {
			"zones": [CARD_ZONE_BOARD],
			"conditions": [{
				"type": CONDITION_SELECTED_CARD_FLIPPED_BY_CURRENT_ATTACK,
			}],
			"required_count": 1,
		},
		"actions": [{"type": ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE}],
	}],
}
```

只统计当前攻击者这一次攻击直接造成的成功翻面，不把翻面触发后由其他牌发起的独立攻击合并进来。目标移动后仍跟踪精确实例，但交换时必须仍与能力来源相邻；目标离场、被新实例替换或不再相邻时，交换失败。

### 一剑落九雁3

与二阶使用相同选择和交换，随后追加：

```gdscript
{"type": ACTION_STANDARD_ATTACK_WITH_SELF}
```

选择 wrapper 声明 `"on_invalid_context": STOP_RULE`。交换 action 失败时 wrapper 返回无效果并停止外层规则，因此不会继续攻击。新标准攻击是独立完整攻击，也会正常产生自己的攻击后事件。

### 天柱云气2

```gdscript
{
	"event": TRIGGER_CARD_SUMMONED,
	"conditions": [
		{"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
		{"type": CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE},
		{"type": CONDITION_SOURCE_HAS_ADJACENT_EMPTY_CELL},
	],
	"actions": [{
		"type": ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY,
		"on_invalid_context": STOP_RULE,
	}],
}
```

移动 action 失败时整条剩余动作停止。

### 天柱云气3

在二阶移动成功后追加：

```gdscript
{"type": ACTION_DRAW_CARDS, "amount": 1}
```

若没有空格或移动失败，不抽牌。

### 天柱云气4

拥有三阶进场反应，并额外拥有独立的移动前 ability：

```gdscript
{
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
		"actions": [{
			"type": ACTION_TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES,
		}],
	}],
}
```

该 ability 不限于天柱云气自己发起的移动。任何其他卡牌或能力令它移动，包括交换中的任一实际移动，都会触发。

多张天柱云气对同一次敌方进场按来源牌当前棋盘索引依次发现和重验证。前一张移动后，后一张使用当时最新棋盘状态重新检查相邻关系和空格。

## 表现

不新增专属 VFX 或音效：

- 能力来源继续使用现有触发脉冲；
- 移动、交换和抽牌继续使用现有表现；
- `ability_lost` 与 `ability_gained` 继续驱动牌面和气珠刷新；
- 同一次规则结算仍遵守现有连续脉冲抑制。

控制器只呈现模拟器事件，不自行判断失效、恢复、选择、移动、交换或抽牌。

## 无效上下文与边界

- 没有相邻空格时，天柱云气进场反应不触发，不脉冲、不移动、不抽牌。
- 动作开始后若移动上下文失效，移动返回无效果；带有 `STOP_RULE` 的声明阻止后续抽牌。
- 一剑落九雁的精确翻面目标不在棋盘、被替换或不再相邻时，交换无效果；三阶后续攻击停止。
- 暂时失效不复制 ability，不改变 `retained_on_flip` 字段，也不影响 powers、ki、original_owner 或其他卡牌数据。
- 新获得的 ability 只受其获得之后发生的新失效效果影响。
- 翻面清除暂存非保留 ability 后，翻回也不会恢复。
- 当前新增的移动前 action 只改变 ability，不会填充目标格或移动触发来源。未来若移动前 action 改变棋盘上下文，移动会按事件后的状态重新验证；已经结算的移动前效果不回滚。

## 测试与验证

新增聚焦规则和生产集成覆盖：

1. 云雾十三式先于全场进场反应结算；
2. 非保留 ability 暂时失去并在回合结束后恢复；
3. 保留 ability 始终存在且不产生伪失去/恢复；
4. 同回合新 ability 立即生效，后续新失效仍能移除它；
5. 翻面永久清除活动及暂存非保留 ability；
6. 多批次恢复保持 ability 顺序；
7. 一剑落九雁处理零、一张和多张直接翻面；
8. 精确目标移动后仍相邻可以交换，不相邻、离场或替换则失败；
9. 三阶只在交换成功后从新位置攻击；
10. 天柱云气只响应相邻敌方进场，选择最低索引空格；
11. 无空格或移动失败时不抽牌；
12. 外部普通移动和交换双方都会派发移动前事件；
13. 状态深复制和状态键区分暂存 ability；
14. 控制器正确同步 ability、气珠、移动、交换和抽牌表现。

完成后运行新增聚焦套件、所有受影响既有套件、完整 `tools/run_tests.ps1`、脚本错误检查和正式决斗场景玩法验证。

改动前基线已有两组陈旧测试：卡牌目录仍断言旧总数，门派目录仍断言最近生产目录更新前的字段。本次只把这些测试同步到当前生产数据，不回退用户的目录改动，也不把它们误记为新能力回归。
