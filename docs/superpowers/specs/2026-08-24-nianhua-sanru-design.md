# 拈花微笑与三入地狱设计

日期：2026-08-24

## 目标

实装 `NianhuaWeiXiao3`、`NianhuaWeiXiao4`、`SanRuDiYu1`、
`SanRuDiYu2` 与 `SanRuDiYu3` 的完整能力。实现必须保持
`DuelSimulator` 为唯一规则路径，并通过通用事件、引用、动作和位置策略表达，
不得在模拟器、控制器或搜索逻辑中按这些卡牌 ID 分支。

## 已确认的行为

### 被丢弃后

- 新增 `CARD_AFTER_DISCARDED`。只有牌已从手牌移入弃牌堆，并已发出弃牌与
  手牌左移动画事件后，才进入该规则时点。
- 该时点只发现本次被丢弃牌自身的能力。手牌、弃牌堆中的其他牌不会因此
  触发能力；场上的牌也不参与这个自触发发现边界。
- `NianhuaWeiXiao4` 从弃牌堆进场时使用同一个实例，保留 `instance_id`、
  当前点数、内力与 `original_owner`。
- 若没有与敌方相邻的空位，`NianhuaWeiXiao4` 留在弃牌堆，能力无效果。
- `SanRuDiYu1`、`SanRuDiYu2` 先在弃牌堆内变形，再将变形后的同一实例
  抽回手牌。
- 变形保留 `instance_id`、所在弃牌堆和 `original_owner`，但卡牌 ID、牌面、
  点数、能力和初始内力完整替换为下一阶段的目录数据。
- 若回手牌动作结算时手牌已满，变形后的同一实例进入移除区。

### 拈花微笑进场

- 能力开始时，按场地索引 `0→8` 锁定所有当时与来源相邻的牌实例。
- 目标逐张结算，后续移动、翻面或离场不会补选其他目标。
- 每张目标移回其 `original_owner` 的手牌。
- 沿用现有场上牌移回手牌语义：正常返回会按目录创建手牌实例；若目标
  所属方手牌已满，场上目标实例进入移除区。
- `NianhuaWeiXiao4` 的弃牌进场属于完整召唤，会触发全场进场能力并进行
  标准攻击；随后其自身的进场后能力按正常顺序结算。

### 三入地狱进场

- `SanRuDiYu1` 尝试在首个相邻空位打出一张自己弃牌堆最上方的牌。
- `SanRuDiYu2` 依次执行两次上述动作。
- `SanRuDiYu3` 依次执行三次。每次优先选择当前首个相邻空位；没有相邻
  空位时，再按 `0→8` 选择当前首个任意空位。
- 每一次动作开始时才读取当时的弃牌堆顶，不预先锁定两张或三张牌。
- 上一张牌必须先完整完成召唤、进场事件、标准攻击与全部连锁，才执行下一
  次动作。因此，连锁中新加入弃牌堆的牌可以成为下一次读取到的堆顶。
- 被打出的牌离开弃牌堆并保留同一个 `instance_id`、现有点数、内力和
  `original_owner`；其当前所属方改为三入地狱能力所属方。
- 弃牌堆为空、没有合法空位或引用在结算前失效时，该次动作无效果；后续
  已声明动作仍按顺序尝试。

### 回合结束与攻击距离

- 三张地狱牌都在其当前所属方的回合结束时移除自身。
- 回合结束移除是独立且非保留的能力；翻面后正常失去。
- 五张牌的攻击距离能力全部锁定，独立声明并设置
  `retained_on_flip = true`。
- `NianhuaWeiXiao3`、`SanRuDiYu1` 可以攻击直线上距离为二、且中间为空位
  的敌方。
- `NianhuaWeiXiao4`、`SanRuDiYu2`、`SanRuDiYu3` 可以攻击直线上距离为二、
  且中间为空位或友方的敌方。
- 翻面只保留上述锁定距离能力，不保留弃牌、进场或回合结束能力。

## 通用声明扩展

新增以下卡牌无关的目录词汇：

```gdscript
const CARD_AFTER_DISCARDED := &"card_after_discarded"

const ACTION_TRANSFORM_CARD := &"transform_card"

const CARD_SPEC_TOP_DISCARD := &"top_discard"

const CELL_REF_FIRST_EMPTY_ADJACENT_TO_ENEMY := \
	&"first_empty_adjacent_to_enemy"

const CELL_REF_FIRST_ADJACENT_OR_ANY_EMPTY := \
	&"first_adjacent_or_any_empty"

const OWNER_CARD_ORIGINAL := &"card_original_owner"
```

`ACTION_SUMMON_CARD` 扩展为可以接收弃牌堆中的精确实例，以及动态解析
`CARD_SPEC_TOP_DISCARD`。`ACTION_RETURN_CARD_TO_HAND` 的
`preserve_instance = true` 路径扩展为满手时移除该实例。

`ACTION_TRANSFORM_CARD` 必须发出纯数据 `card_transformed` 事件。召唤、返回、
移除继续复用已有纯数据事件，控制器只负责呈现模拟器事件。

## 具体 declaration

### 拈花微笑共通进场能力

```gdscript
const NIANHUA_RETURN_ADJACENT: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_FOR_EACH_SELECTED_CARD,
			"selector": {
				"zones": [CARD_ZONE_BOARD],
				"conditions": [{
					"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE,
				}],
			},
			"actions": [{
				"type": ACTION_RETURN_CARD_TO_HAND,
				"card": CARD_REF_SELECTED_CARD,
				"recipient": OWNER_CARD_ORIGINAL,
			}],
		}],
	}],
}
```

### 拈花微笑四阶弃牌进场

```gdscript
const NIANHUA_DISCARD_SUMMON: Dictionary = {
	"triggers": [{
		"event": CARD_AFTER_DISCARDED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_SUMMON_CARD,
			"card": CARD_REF_TRIGGER_CARD,
			"cell": {
				"type": CELL_REF_FIRST_EMPTY_ADJACENT_TO_ENEMY,
				"owner": OWNER_ABILITY_SOURCE,
			},
		}],
	}],
}
```

### 一入、二入地狱弃牌升级

```gdscript
const SANRU_ONE_TRANSFORM: Dictionary = {
	"triggers": [{
		"event": CARD_AFTER_DISCARDED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [
			{
				"type": ACTION_TRANSFORM_CARD,
				"card": CARD_REF_TRIGGER_CARD,
				"card_id": &"SanRuDiYu2",
			},
			{
				"type": ACTION_RETURN_CARD_TO_HAND,
				"card": CARD_REF_TRIGGER_CARD,
				"recipient": OWNER_CARD_CURRENT,
				"preserve_instance": true,
			},
		],
	}],
}
```

`SANRU_TWO_TRANSFORM` 使用相同结构，将 `card_id` 改为
`&"SanRuDiYu3"`。

### 从当前弃牌堆顶召唤

```gdscript
const SANRU_SUMMON_TOP_ADJACENT: Dictionary = {
	"type": ACTION_SUMMON_CARD,
	"card": {
		"type": CARD_SPEC_TOP_DISCARD,
		"owner": OWNER_ABILITY_SOURCE,
	},
	"cell": {
		"type": CELL_REF_FIRST_ADJACENT_EMPTY,
		"card": CARD_REF_ABILITY_SOURCE,
	},
}

const SANRU_SUMMON_TOP_WITH_FALLBACK: Dictionary = {
	"type": ACTION_SUMMON_CARD,
	"card": {
		"type": CARD_SPEC_TOP_DISCARD,
		"owner": OWNER_ABILITY_SOURCE,
	},
	"cell": {
		"type": CELL_REF_FIRST_ADJACENT_OR_ANY_EMPTY,
		"card": CARD_REF_ABILITY_SOURCE,
	},
}
```

三张牌分别在自身 `TRIGGER_CARD_AFTER_SUMMONED` 条目中声明一次、两次、三次
上述动作；不使用会预先快照弃牌堆目标的批量 selector，也不新增卡牌专用的
“打出弃牌堆顶若干张”动作。

### 回合结束移除

```gdscript
const SANRU_END_TURN_EXILE: Dictionary = {
	"triggers": [{
		"event": TRIGGER_END_OWNER_TURN,
		"conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
		"actions": [{"type": ACTION_EXILE_SELF}],
	}],
}
```

该条目不设置 `retained_on_flip`。

### 锁定攻击距离

```gdscript
const LOCKED_RANGE_TWO_EMPTY: Dictionary = {
	"retained_on_flip": true,
	"modifiers": [{
		"type": MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO,
		"allow_intervening_ally": false,
	}],
}

const LOCKED_RANGE_TWO_EMPTY_OR_ALLY: Dictionary = {
	"retained_on_flip": true,
	"modifiers": [{
		"type": MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO,
		"allow_intervening_ally": true,
	}],
}
```

最终能力组合：

- `NianhuaWeiXiao3`：`NIANHUA_RETURN_ADJACENT`、
  `LOCKED_RANGE_TWO_EMPTY`。
- `NianhuaWeiXiao4`：`NIANHUA_DISCARD_SUMMON`、
  `NIANHUA_RETURN_ADJACENT`、`LOCKED_RANGE_TWO_EMPTY_OR_ALLY`。
- `SanRuDiYu1`：`SANRU_ONE_TRANSFORM`、一次相邻弃牌召唤、
  `SANRU_END_TURN_EXILE`、`LOCKED_RANGE_TWO_EMPTY`。
- `SanRuDiYu2`：`SANRU_TWO_TRANSFORM`、两次相邻弃牌召唤、
  `SANRU_END_TURN_EXILE`、`LOCKED_RANGE_TWO_EMPTY_OR_ALLY`。
- `SanRuDiYu3`：三次带后备空位的弃牌召唤、
  `SANRU_END_TURN_EXILE`、`LOCKED_RANGE_TWO_EMPTY_OR_ALLY`。

每段文字能力使用独立能力条目，避免锁定能力与会在翻面时失去的能力共享
同一个 `retained_on_flip` 边界。

## 数据流与呈现

1. 丢弃动作删除精确手牌实例并加入当前所属方弃牌堆。
2. 模拟器发出 `card_discarded` 与可选的 `hand_cards_shifted`。
3. 模拟器解析 `CARD_AFTER_DISCARDED` 的被丢弃牌自身规则。
4. 变形发出 `card_transformed`；回手牌发出携带变形后快照的现有返回事件。
5. 弃牌堆召唤从模拟器移除精确实例，创建标准召唤请求，再走统一召唤、
   进场触发和标准攻击路径。
6. 控制器按事件顺序复用弃牌渐隐、手牌左移、召唤、返回、移除和攻击动画；
   不加入玩法分支。

## 验证

新增聚焦模拟器回归，至少覆盖：

- `NianhuaWeiXiao4` 有、无合法空位时的弃牌反应与实例身份。
- 拈花微笑相邻目标快照、`0→8` 顺序、返回最初所属方和满手移除。
- 一入、二入变形后的完整目录数据、同一 `instance_id`、正常回手与满手移除。
- 三张地狱牌从弃牌堆召唤同一实例并改为能力所属方。
- 每次召唤完成全部连锁后，下一次重新读取当前弃牌堆顶。
- 三入地狱相邻优先与非相邻后备空位顺序。
- 进场牌完整触发进场能力和标准攻击。
- 三张地狱牌在当前所属方回合结束时移除；翻面后失去该能力。
- 五张牌翻面后仍保留正确的锁定距离 modifier。
- 目录 schema、纯数据事件和控制器集成顺序。

实现后运行聚焦测试，再运行：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
```

最后在 540×960 竖屏生产路径中实际走一遍弃牌变形、弃牌进场、连续召唤和
相邻退回流程。
