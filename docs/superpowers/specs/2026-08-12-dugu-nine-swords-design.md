# 无招胜有招、料敌机先与破尽天下设计

## 目标

实装以下三张五阶江湖剑法的完整目录描述，同时保持 `DuelSimulator`
权威、搜索卡牌无关、运行时身份使用 `instance_id`，并让回放与 AI 状态完整包含新增的
历史和跨回合效果：

- `DuGu9Jian1`：无招胜有招
- `DuGu9Jian2`：料敌机先
- `DuGu9Jian3`：破尽天下

三张牌的规则只通过目录声明和通用规则词汇表达。模拟器、搜索和控制器不得根据上述
卡牌 ID 分支。

## 已确认语义

### 无招胜有招

无招胜有招在自身的 `TRIGGER_CARD_BEFORE_SUMMONED` 阶段结算。它先移除自身，并立即
让其移除前的当前拥有者抽一张牌；随后按相邻格编号从小到大，逐张移除结算开始时与其
正交相邻的精确卡牌，并在每次移除后立即让该牌移除前的当前拥有者抽一张牌。

每个目标使用精确 `instance_id` 快照。轮到目标结算时若它已经离场，则跳过该目标并继续。
抽牌因手牌已满或牌库为空而无效果时，同样继续结算后续目标。被移除的牌仍进入其
`original_owner` 的移除区；抽牌归属依据移除前的当前拥有者。

### 料敌机先

每位玩家都记录最近一张成功从手牌中打出的牌。料敌机先读取的是打出料敌机先之前的旧
记录，不包括料敌机先自身。模拟器在本次出牌覆盖历史之前冻结双方旧记录，供本次进场前
能力使用。

料敌机先依次结算：

1. 移除自身，并让其移除前当前拥有者抽一张牌；
2. 将对手旧记录中的精确牌从场上返回到当时出牌者的手牌；
3. 将己方旧记录中的精确牌从场上返回到当时出牌者的手牌；
4. 获得一次额外手牌出牌。

记录目标即使后来翻面，也返回原出牌者而非当前拥有者。返回采用现有标准规则：场上旧
实例消失，目标手牌得到一张目录初始值的全新实例。目标不在场时跳过；目标手牌已满时，
将场上目标移除。任何一步无效果都不阻断后续步骤和额外出牌。

### 破尽天下

破尽天下在进场前移除自身并抽一张牌，然后揭示所有当前敌方手牌，并给对手增加一层
跨回合的待压制效果。

待压制层只在该玩家成功从手牌打出非心法牌时消耗。心法牌不受影响，也不消耗层数。
命中的非心法牌在发现和结算任何自身 `TRIGGER_CARD_BEFORE_SUMMONED` 能力之前，永久
失去全部未标记 `retained_on_flip = true` 的能力；保留能力不被移除，仍可正常触发。

多层待压制分别作用于之后成功打出的多张非心法牌，每张牌最多消耗一层，不会让多层同时
落在同一张牌上。

## 状态模型

`DuelState` 新增以下纯数据字段：

```gdscript
var last_hand_play_by_owner: Dictionary = {
	Rules.PLAYER_OWNER: {},
	Rules.OPPONENT_OWNER: {},
}

var pending_non_retained_suppression_by_owner: Dictionary = {
	Rules.PLAYER_OWNER: 0,
	Rules.OPPONENT_OWNER: 0,
}
```

上一张手牌出牌记录的形状为：

```gdscript
{
	"played_by_owner_id": 1,
	"card_id": &"example_card",
	"instance_id": &"runtime_instance",
}
```

记录只保存规则所需身份，不保存展示节点或隐蔽手牌元数据。两个字段必须在
`duplicate_state()`、回放初始状态和 `DuelStateKey` 中深复制/编码，否则 AI 可能把规则
不同的局面错误合并。

## 出牌时序

成功合法的手牌出牌按以下顺序进入规则管线：

1. 读取并深复制双方现有 `last_hand_play_by_owner`，形成不可变的
   `previous_hand_play_by_owner` 上下文；
2. 将手牌精确实例放入目标格，但尚未发现进场前触发；
3. 若该实例不是心法，且出牌者有待压制层，则永久移除其全部非保留能力、消耗一层，并
   发出能力失去和压制命中事件；
4. 使用压制后的实际能力数组发现并结算该实例的 `TRIGGER_CARD_BEFORE_SUMMONED`；
5. 发出普通放置事件并继续全局进场、进场后和标准攻击阶段；
6. 将本次成功手牌出牌写入出牌者的 `last_hand_play_by_owner`。

第 6 步即使该实例已在进场前被移除也必须执行，因为它仍然是一张成功从手牌打出的牌。
料敌机先动作只能读取第 1 步的快照，不能读取或修改实时历史。

## 通用目录词汇

不新增“移除自身与相邻牌并抽牌”或“返回上一张手牌出牌”这类组合动作。无招胜有招直接
组合现有动作和现有相邻条件；新增词汇只描述历史选择关系和独立状态变更：

```gdscript
const ACTION_ADD_PENDING_NON_RETAINED_SUPPRESSION := &"add_pending_non_retained_suppression"

const CONDITION_SELECTED_CARD_IS_PREVIOUS_HAND_PLAY := &"selected_card_is_previous_hand_play"
```

无招胜有招先在 wrapper 外用现有 `ACTION_EXILE_SELF` 和 `ACTION_DRAW_CARDS` 处理自身，
再由现有 `ACTION_FOR_EACH_SELECTED_CARD` 和
`CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE` 选择相邻牌。棋盘候选本来就按格编号升序
扫描，不新增排序类型。来源此时虽已离场，现有条件仍应从 `CARD_REF_ABILITY_SOURCE` 的
动作上下文快照读取其初始 `zone/index`；这是对现有精确来源快照解析的补全，不是新条件。
候选牌仍须是 selector 开始时快照的同一实例且仍在棋盘。

`CONDITION_SELECTED_CARD_IS_PREVIOUS_HAND_PLAY` 的 `played_by` 字段接受现有
`OWNER_ABILITY_SOURCE` / `OWNER_OPPONENT_OF_ABILITY_SOURCE`，并把候选精确实例与
`previous_hand_play_by_owner` 中对应记录比较。它不返回别的目标，也不改变历史。

现有 `ACTION_DRAW_CARDS` 新增可选的 `card` 与 `recipient` 字段。两者必须一起声明：
`card` 接受现有精确卡牌引用；`recipient` 接受现有所有者引用。抽牌接收者由该卡牌引用的
结算快照解析，因此目标先被现有 `ACTION_EXILE_SELF` 移除后仍能按其移除前当前所有者
抽牌。不声明这两个字段时，保持现有“由当前动作主体的拥有者抽牌”语义。

`ACTION_ADD_PENDING_NON_RETAINED_SUPPRESSION` 的 `recipient` 使用现有
`RECIPIENT_SELF` / `RECIPIENT_OPPONENT`，`amount` 必须为正整数。当前三张牌只声明给对手
增加一层。

## 完整 declaration

以下 declaration 使用项目现有词汇和上节新增词汇。三条进场前能力都不声明
`retained_on_flip`，因此按目录默认值规范化为 `false`。

### 无招胜有招

```gdscript
const DUGU_NO_FORM: Dictionary = {
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
						"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE,
					}],
				},
				"actions": [
					{"type": ACTION_EXILE_SELF},
					{
						"type": ACTION_DRAW_CARDS,
						"amount": 1,
						"card": CARD_REF_SELECTED_CARD,
						"recipient": OWNER_CARD_CURRENT,
					},
				],
			},
		],
	}],
}
```

卡牌定义：

```gdscript
&"DuGu9Jian1": {
	# 其余现有字段保持不变
	"abilities": [DUGU_NO_FORM],
}
```

### 料敌机先

```gdscript
const DUGU_ANTICIPATE: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_BEFORE_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [
			{"type": ACTION_EXILE_SELF},
			{
				"type": ACTION_DRAW_CARDS,
				"amount": 1,
				"card": CARD_REF_ABILITY_SOURCE,
				"recipient": OWNER_CARD_CURRENT,
			},
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
```

`ACTION_DRAW_CARDS` 通过显式卡牌引用读取移除前所有者快照；
`ACTION_GRANT_EXTRA_CARD_PLAY` 也必须在能力来源已被前一动作移除后，依靠进场前捕获的
能力来源所有者快照继续结算。不能通过调换目录动作顺序规避来源离场。

卡牌定义：

```gdscript
&"DuGu9Jian2": {
	# 其余现有字段保持不变
	"abilities": [DUGU_ANTICIPATE],
}
```

### 破尽天下

```gdscript
const DUGU_BREAK_ALL: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_BEFORE_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [
			{"type": ACTION_EXILE_SELF},
			{
				"type": ACTION_DRAW_CARDS,
				"amount": 1,
				"card": CARD_REF_ABILITY_SOURCE,
				"recipient": OWNER_CARD_CURRENT,
			},
			{
				"type": ACTION_REVEAL_HAND_CARDS,
				"recipient": RECIPIENT_OPPONENT,
				"filter": REVEAL_FILTER_ALL,
			},
			{
				"type": ACTION_ADD_PENDING_NON_RETAINED_SUPPRESSION,
				"recipient": RECIPIENT_OPPONENT,
				"amount": 1,
			},
		],
	}],
}
```

揭示和增加待压制层同样使用能力来源所有者快照，因此自我移除不会使后续动作失去归属。

卡牌定义：

```gdscript
&"DuGu9Jian3": {
	# 其余现有字段保持不变
	"abilities": [DUGU_BREAK_ALL],
}
```

## 事件与表现

复用现有事件：

- `card_exiled`
- `card_drawn`
- `card_returned_to_hand`
- `card_revealed`
- `ability_lost`
- `extra_card_play_granted`

新增纯数据事件：

```gdscript
{
	"type": &"non_retained_suppression_added",
	"owner_id": 2,
	"amount": 1,
	"pending_count": 2,
}

{
	"type": &"non_retained_suppression_consumed",
	"owner_id": 2,
	"instance_id": &"played_card_instance",
	"pending_count": 1,
}
```

压制命中时，先发 `non_retained_suppression_consumed`，再按旧能力数组顺序为每个实际移除
条目发出 `ability_lost`，然后才允许进场前能力发现。心法出牌不发上述事件。

控制器继续使用现有移除、抽牌、返回、揭示和能力失去表现。待压制的增加与消耗暂不新增
场景节点、常驻图标或专属动画；事件保留给未来表现扩展。对手手牌在 `card_revealed` 之前
不得因状态记录或调试事件泄漏卡牌元数据。

## 无效上下文与所有权

- 自我移除后的后续动作使用能力来源的原始所有者快照。
- 无招胜有招相邻目标以动作开始时的当前格和精确实例为准；之后目标移动或离场时跳过，
  不改选其他牌。
- 料敌机先记录目标只在棋盘区时可返回。手牌、移除区或不存在均为无效果。
- 料敌机先返回接收者固定为记录中的 `played_by_owner_id`。
- 满手返回使用现有外部移除规则，进入卡牌原始所有者移除区。
- 破尽天下层数属于目标玩家，不属于来源卡；来源离场、翻面或对局跨回合均不清除它。
- 非心法牌即使全部能力均为保留能力，仍消耗一层；结果可以没有 `ability_lost` 事件。

## 测试设计

新增纯模拟器套件 `tests/test_dugu_nine_swords_abilities.gd`，至少覆盖：

### 目录与状态

- 三张卡具有非空且完全匹配本设计的 declaration；
- 新历史条件、抽牌字段和独立压制动作通过目录校验，未知值/字段被拒绝；
- `DuelState.duplicate_state()` 深复制历史与待压制层；
- `DuelStateKey` 区分不同历史目标和不同剩余层数。

### 无招胜有招

- 自身先移除，相邻格按编号升序；
- 来源移除后，现有相邻条件仍以来源初始格重验，但不会改选后来移动进来的牌；
- 每次 `card_exiled` 后立即跟随对应拥有者的 `card_drawn`；
- 翻面相邻牌按当前拥有者抽牌、按原始拥有者进入移除区；
- 满手、空牌库、目标提前离场均不阻断后续；
- 非相邻牌保持不变，牌不会进入普通放置/攻击后续阶段。

### 料敌机先

- 本次料敌机先不覆盖它读取的己方旧记录；
- 对手目标先返回，己方目标后返回；
- 翻面目标仍返回原出牌者；
- 目标不存在时跳过；满手时移除；成功返回产生全新标准实例；
- 自身移除后仍抽牌并授予一次额外出牌；
- 额外出牌仍遵守现有手牌出牌限制和回合边界；
- 返回动作不会把新实例错误写为“上一张从手牌打出的牌”。

### 破尽天下

- 自身移除、抽牌、揭示当前敌方手牌、增加层数的事件顺序；
- 层数跨回合保留；心法不受影响且不消耗；
- 下一张非心法牌在自身进场前发现之前永久失去所有非保留能力；
- `retained_on_flip = true` 能力保留并可触发；
- 多层分别命中多张牌，每张最多消耗一层；
- 没有非保留能力的非心法牌仍消耗一层；
- 正常模式在揭示事件前不泄漏敌方手牌。

### 回归与生产路径

- 运行目录、模拟器、状态键、搜索、回放、揭示和集成定向套件；
- 运行 `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`；
- 在 540×960 生产场景中分别走三张牌的正常路径，检查移除/抽牌/返回/揭示动画顺序，
  并确认无运行时错误。

## 非目标

- 不新增对局中的常驻压制层图标；
- 不新增玩家中途选择或队列式交互；
- 不修改三张牌的中文描述、点数、图片或解锁规则；
- 不为这些卡在模拟器、搜索或控制器添加 ID 分支；
- 不把历史记录扩展为完整出牌日志。
