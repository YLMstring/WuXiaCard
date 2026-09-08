# 2026-09-08 胡家刀法牌手光环重构设计

## 目标与范围

按最新目录文本重做 `HuJiaDao1`、`HuJiaDao2`、`HuJiaDao3`，并将此前的
“手牌能力 + 手牌来源虚拟光环”模型替换为牌手持有的光环状态。

本次规则边界为：

- `TRIGGER_DUEL_STARTED` 只扫描双方初始手牌；
- 除事件生命周期明确指定的单张牌外，其余普通卡牌触发只扫描场上九格；
- 卡牌运行时能力不能持有光环；
- 只有牌手可以持有光环；
- 每份牌手光环额外保存其精确来源牌引用；
- 三张胡家刀法的光环均在任意一方回合结束时检查来源牌，若来源牌不在
  手牌中，则在该时点失去；不会在来源牌离手时立即失去。

此前文档
`docs/superpowers/specs/2026-09-07-hujia-chuncan-five-cards-design.md`
继续作为春蚕掌法、攻击翻面口径和攻击实际使用方向的历史设计依据；其中
胡家刀法的 `active_zones`、手牌普通触发和卡牌持有 `auras` 的设计由本文取代。

本次不修改三张牌的名称、图片、门派、品阶、武器、点数或背景文本，也不修改
春蚕掌法、攻击结果上下文和现有点数动画。

## 核心模型

### 开局手牌扫描

`TRIGGER_DUEL_STARTED` 是唯一进行全手牌能力发现的事件。它在双方五张初始
手牌、牌库、难度和静态八卦方位建立后，按以下顺序发现一次：

1. 玩家手牌，物理槽位从左到右；
2. 敌方手牌，物理槽位从左到右。

发现结果是一次性快照。开局动作中新获得的牌手光环不会反过来参与同一次
`TRIGGER_DUEL_STARTED` 发现。开局结算仍发生在回放初始快照和首次画面绘制前，
因此揭示与光环安装直接成为初始状态，不补播动画。

开局手牌能力不再声明 `active_zones`。一张牌具有 `TRIGGER_DUEL_STARTED` 并不
意味着它能在手牌中响应其它事件。

### 普通卡牌事件发现

除现有事件生命周期明确指定的单张触发牌外，普通卡牌事件发现只按场上
`0..8` 扫描。不得再遍历双方手牌、弃牌区或移除区后依靠生效区域过滤。

现有 `CARD_AFTER_DISCARDED` 对“刚被丢弃的精确触发牌”的直接发现继续保留；
这是弃牌生命周期的一部分，不是对弃牌区的全区扫描。同类精确生命周期入口
沿用相同原则。

### 牌手光环

每名牌手拥有有序的运行时光环列表。每个条目只保存：

```text
runtime_handle
source_instance_id
compiled_aura_declaration
```

其中 `compiled_aura_declaration` 指向不可变编译声明，不随状态复制而深拷贝。
`source_instance_id` 是牌手光环相对于普通能力额外保存的唯一卡牌引用。光环
不会写入来源牌或接收牌的 `active_abilities`，接收牌也不会新增持久字段。

光环所属方固定为获得它的牌手，不随来源牌后来进场、翻面或移动而改变。
友方、敌方、自己和对手均相对光环所属方判断。来源牌引用始终指向开局授予
光环的同一个运行时实例。

同一牌手可以持有多份相同声明的光环。每份光环有独立 handle 和来源引用，
不设置 `stacking_key`，不按卡牌 ID 或声明内容去重。

### 光环的能力来源

牌手光环自身的触发和修正器属于光环持有者，但同时携带保存的来源牌引用。
因此：

- `CARD_REF_ABILITY_SOURCE` 定位光环保存的精确来源牌；
- `OWNER_ABILITY_SOURCE` 返回光环持有者，而不是来源牌后来可能改变的所属方；
- `ACTION_REMOVE_THIS_ABILITY` 从牌手光环触发中执行时，只删除该触发所属的
  精确光环 handle，不删除来源牌的任何能力。

牌手光环触发结算前不以来源牌的位置、区域、当前所属方、效果门控或运行时能力
作为通用有效性条件；这些检查一律视为通过。只有声明中明确写出的条件或动作才
读取来源牌，例如回合结束时的 `CONDITION_ABILITY_SOURCE_IN_ZONE`，以及揭示、
加减点动作。来源牌无法被具体动作定位时，该动作按普通无效动作处理，不使整份
光环触发失效。

光环赋予场上接收牌的虚拟能力仍以接收牌作为该虚拟能力的 `ability_source`，
使 `CONDITION_TRIGGER_CARD_IS_SELF` 和 `ACTION_EXILE_SELF` 指向接收牌；事件组同时
保存提供它的牌手光环 handle，以便执行前确认该光环仍存在。

### 普通卡牌触发的再次确认

普通卡牌能力在发现时仍检查来源效果门控、发现区域、事件 ID 和声明条件。发现
后保存精确来源实例、能力 handle 和触发条目索引。

轮到该触发结算时，只进行以下通用再次确认：

1. 精确来源实例仍能在当前状态中定位；
2. 来源实例仍在发现时的同一个区域；
3. 原能力 handle 仍存在于该实例；
4. 原触发条目仍能从该能力取得；
5. 使用来源实例当前的位置和当前所属方，重新执行声明条件。

来源必须保持在发现时的区域，但不必保持发现时的格子或所属方，也不再复查
`card_effects_enabled`。来源在场上换格后会追踪到新位置继续结算，不再仅对
`trigger_card` 提供移动特例；来源从场上进入手牌、弃牌区或移除区等跨区域变化
会使触发失效。来源翻面后若精确能力因非保留规则被移除，仍会因 handle 不存在
而失效；若能力仍然存在，则以结算时的新所属方判断友方、敌方、“你”和“对手”。

条件重验不会重建事件快照。攻击者发起攻击时的所属方、攻击是否直接翻面、实际
使用方向等快照字段保持不变；但条件中相对来源的敌我关系使用来源结算时所属方。
通过确认后，`ability_triggered` 和动作上下文也使用来源当前格子、区域和所属方。
各动作仍独立检查自己的目标与前提。

## 新增与删除的目录原语

### 新增动作

```gdscript
const ACTION_GRANT_OWNER_AURA: StringName = &"grant_owner_aura"
```

完整声明格式：

```gdscript
{
    "type": ACTION_GRANT_OWNER_AURA,
    "aura": OWNER_AURA_DECLARATION,
}
```

动作将一份新光环授予 `OWNER_ABILITY_SOURCE`，保存当前精确能力来源实例并分配
新的运行时 handle。`aura` 必须是非空、可完整原生编译的牌手光环声明。每次动作
均新增一份光环，不去重。

牌手光环声明允许：

```text
triggers
modifiers
auras
```

其中 `auras` 继续使用现有 selector + nested ability 结构，为符合条件的场上牌
即时派生虚拟能力。牌手光环声明禁止 `activation`、`active_zones` 和
`retained_on_flip`；牌手光环不会翻面，也不是可主动使用的卡牌能力。

### 新增条件

```gdscript
const CONDITION_ABILITY_SOURCE_IN_ZONE: StringName = &"ability_source_in_zone"
```

完整声明格式：

```gdscript
{
    "type": CONDITION_ABILITY_SOURCE_IN_ZONE,
    "zone": CARD_ZONE_HAND,
    "inverted": true,
}
```

`zone` 必须是 `CARD_ZONE_HAND`、`CARD_ZONE_BOARD`、`CARD_ZONE_DISCARD` 或
`CARD_ZONE_REMOVED`。`inverted` 可省略，默认 `false`。条件按精确
`instance_id` 定位当前能力来源；无法定位等同于“不在指定区域”。

### 删除卡牌生效区域和卡牌光环

从卡牌能力 schema、目录验证、原生编译和运行时查询中删除：

```gdscript
"active_zones"
"auras"
```

`auras` 只允许出现在 `ACTION_GRANT_OWNER_AURA.aura` 的牌手光环声明中，不允许
直接出现在任何卡牌的 `abilities` 条目中。目录中现有四处 `active_zones` 全部移除：
三张胡家刀法改用牌手光环，来鹤清泉的开局能力由开局专用手牌扫描发现。

## 三张胡家刀法的完整声明

### 共用光环失效触发

```gdscript
const HUJIA_OWNER_AURA_EXPIRE: Dictionary = {
    "event": TRIGGER_END_OWNER_TURN,
    "conditions": [{
        "type": CONDITION_ABILITY_SOURCE_IN_ZONE,
        "zone": CARD_ZONE_HAND,
        "inverted": true,
    }],
    "actions": [{"type": ACTION_REMOVE_THIS_ABILITY}],
}
```

这里不声明 `CONDITION_TURN_OWNER_IS_SELF`，因此任意一方的回合结束都会检查。
条件在该光环触发真正执行前重验。场上牌的回合结束效果先结算；如果它们在
此前令来源牌重新进入手牌，光环保留，反之则移除。

### 八方藏刀式

```gdscript
const HUJIA_HIDDEN_BLADE_AURA: Dictionary = {
    "triggers": [HUJIA_OWNER_AURA_EXPIRE],
    "modifiers": [{
        "type": MODIFIER_OPPONENT_PLAY_CELL_ONLY_IF_NO_OTHER_ACTION,
        "cell": 4,
    }],
}

const HUJIA_HIDDEN_BLADE: Dictionary = {
    "triggers": [{
        "event": TRIGGER_DUEL_STARTED,
        "actions": [
            {
                "type": ACTION_REVEAL_CARD,
                "card": CARD_REF_ABILITY_SOURCE,
                "observer": OWNER_OPPONENT_OF_ABILITY_SOURCE,
            },
            {
                "type": ACTION_REVEAL_HAND_CARDS,
                "recipient": RECIPIENT_OPPONENT,
                "filter": REVEAL_FILTER_ALL,
            },
            {
                "type": ACTION_GRANT_OWNER_AURA,
                "aura": HUJIA_HIDDEN_BLADE_AURA,
            },
        ],
    }],
}
```

开局揭示这张牌，并向其所属牌手揭示当时全部敌方手牌，然后授予牌手中央格
限制光环。新抽入的敌方牌不会自动揭示。中央格限制继续使用现有语义：只要
存在合法主动能力或向其它格子的合法手牌出牌，对手就不能在中央格出牌；若
别无选择，中央格仍合法。

### 怀中抱月

```gdscript
const HUJIA_EMBRACE_MOON_GRANTED: Dictionary = {
    "modifiers": [{
        "type": MODIFIER_DEFENDING_POWER_OVERRIDE,
        "value": 0,
    }],
    "triggers": [{
        "event": CARD_BE_ATTACKED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [
            {"type": ACTION_DRAW_CARDS, "amount": 1},
            {"type": ACTION_EXILE_SELF},
        ],
    }],
}

const HUJIA_EMBRACE_MOON_AURA: Dictionary = {
    "triggers": [
        {
            "event": CARD_BE_ATTACKED,
            "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_ALLY}],
            "actions": [
                {
                    "type": ACTION_REVEAL_CARD,
                    "card": CARD_REF_ABILITY_SOURCE,
                    "observer": OWNER_OPPONENT_OF_ABILITY_SOURCE,
                },
                {
                    "type": ACTION_CHANGE_POWERS,
                    "amount": -1,
                    "card": CARD_REF_ABILITY_SOURCE,
                },
            ],
        },
        HUJIA_OWNER_AURA_EXPIRE,
    ],
    "auras": [{
        "selector": {
            "zones": [CARD_ZONE_BOARD],
            "conditions": [{"type": CONDITION_SELECTED_CARD_IS_ALLY}],
        },
        "ability": HUJIA_EMBRACE_MOON_GRANTED,
    }],
}

const HUJIA_EMBRACE_MOON: Dictionary = {
    "triggers": [{
        "event": TRIGGER_DUEL_STARTED,
        "actions": [{
            "type": ACTION_GRANT_OWNER_AURA,
            "aura": HUJIA_EMBRACE_MOON_AURA,
        }],
    }],
}
```

光环存在时，所有当前友方场上牌在攻击合法性判断中使用防守点数零。友方确实
被攻击时，事件顺序为：

1. 场上普通 `CARD_BE_ATTACKED` 触发；
2. 牌手光环自身触发：揭示精确来源牌并令其四边减一；
3. 光环赋予接收牌的虚拟触发：抽一张牌，然后移除该接收牌。

来源牌减至四边为零并进入移除区不会立即删除光环；本次虚拟触发仍完成，光环
到本回合结束检查时才移除。来源牌以其它方式离开手牌同理。来源牌只要仍可
定位就照常揭示；若它位于牌库或四边为 `-1`，减点动作无效，但不影响光环的
其它部分。

多份怀中抱月光环分别揭示并减少各自来源牌。每份光环都会派生一份接收牌能力；
第一份成功移除接收牌后，其余份数因接收牌重验失败而不再抽牌。

### 闭门铁扇刀

```gdscript
const HUJIA_CLOSED_DOOR_AURA: Dictionary = {
    "triggers": [
        {
            "event": TRIGGER_CARD_AFTER_ATTACK,
            "conditions": [{"type": CONDITION_ATTACKER_CARD_IS_ENEMY}],
            "actions": [
                {
                    "type": ACTION_REVEAL_CARD,
                    "card": CARD_REF_ABILITY_SOURCE,
                    "observer": OWNER_OPPONENT_OF_ABILITY_SOURCE,
                },
                {
                    "type": ACTION_CHANGE_POWERS,
                    "amount": 1,
                    "card": CARD_REF_ABILITY_SOURCE,
                },
                {
                    "type": ACTION_IF,
                    "conditions": [{
                        "type": CONDITION_ATTACK_FLIPPED_ANY_CARD,
                        "inverted": true,
                    }],
                    "actions": [{
                        "type": ACTION_SET_ATTACK_USED_POWERS,
                        "card": CARD_REF_ATTACKER_CARD,
                        "value": 0,
                    }],
                },
            ],
        },
        HUJIA_OWNER_AURA_EXPIRE,
    ],
}

const HUJIA_CLOSED_DOOR: Dictionary = {
    "triggers": [{
        "event": TRIGGER_DUEL_STARTED,
        "actions": [{
            "type": ACTION_GRANT_OWNER_AURA,
            "aura": HUJIA_CLOSED_DOOR_AURA,
        }],
    }],
}
```

敌方攻击的判断相对光环所属牌手。只要攻击至少完成一次成功的攻击资格比较，
攻击后触发就揭示精确来源牌并令其四边加一；若攻击本身未直接造成任何翻面，
再把该次攻击实际使用过的攻击者方向设为零。连锁能力造成的翻面仍不算攻击
本身翻面，实际使用方向的现有口径不变。

多份光环分别揭示、加点和尝试归零。来源牌已经离手时，光环仍可在本回合结束
前触发；来源牌动作若因当前位置无效，不阻止后续归零动作。

### 最终卡牌引用

```gdscript
HuJiaDao1.abilities = [HUJIA_HIDDEN_BLADE]
HuJiaDao2.abilities = [HUJIA_EMBRACE_MOON]
HuJiaDao3.abilities = [HUJIA_CLOSED_DOOR]
```

三张卡牌的 `abilities` 中都不含 `active_zones` 或 `auras`。

## 原生状态和结算顺序

GDScript `DuelState` 增加按所属方分组的纯数据牌手光环列表和下一个光环 handle。
紧凑边界对光环声明进行池化；原生 `NativeState` 使用两个紧凑 vector，每个条目
只保存编译声明索引、来源牌索引和 handle。牌手光环列表、顺序、handle、来源和
下一个 handle 都参与状态复制、导入导出、结构校验、checksum 与 TT 状态键。

普通事件发现固定为：

1. 事件生命周期指定的精确单牌入口，若该事件具有此入口；否则扫描场上 `0..8`；
2. 玩家和敌方当前持有的牌手光环自身触发，按所属方和获得顺序；
3. 各牌手光环向场上接收牌派生的虚拟触发，按接收格 `0..8`、所属方和光环获得
   顺序。

事件组保存稳定 handle，不用可变化的数组下标标识尚未结算的光环。执行前确认：

- 对应牌手仍持有该 handle；
- 直接光环触发的声明条件相对光环持有者仍成立；
- 虚拟触发的精确接收牌仍能定位，并以其当前位置、区域和所属方重新检查
  selector 与触发条件。

这里不对光环保存的来源牌做任何通用确认。来源牌是否仍在手牌，只由光环声明
中的 `CONDITION_ABILITY_SOURCE_IN_ZONE` 在回合结束时判断；来源牌揭示、加减点
能否生效，只由对应动作自行判断。

光环失效不会令此前同一事件中已经执行的动作回滚；尚未执行且依赖已删除光环的
事件组会因 handle 重验失败而失效。

## 表现

- 开局揭示与光环获得发生在初始画面前，不增加动画等待；
- 光环触发中的来源牌揭示沿用 `card_revealed`；
- 来源牌加减点和攻击方向归零沿用现有 `powers_changed` 批量动画；
- 牌手光环不显示 ki bead，不复制到卡牌检查器，也不改变卡牌能力描述；
- 光环获得和失去可以保留纯数据 transition 事件供调试与回放校验，但控制器不
  为其新增视觉动画。

## 性能约束与报告门禁

本次重构的主要性能目标是消除每次事件和修正器查询对手牌、弃牌区、移除区及
手牌光环提供者的重复扫描：

- 对局开始只扫描两手共最多十张牌一次；
- 普通卡牌事件只扫描最多九张场上牌；
- 光环查询只遍历两名牌手实际持有的紧凑光环列表；
- 没有牌手光环时必须通过常数时间空列表检查返回；
- 编译后的事件/修正器能力摘要用于跳过不可能匹配的光环类别；
- 不得通过重新遍历所有卡牌区域来查找光环来源，来源实例在紧凑状态中使用稳定
  card index，跨 GDScript 边界时才用 `instance_id` 恢复。

实施后使用相同 C++ Release、相同真实 Quick 开局、相同 5,000 节点、生产
PV/history/8 MiB TT 重新运行细分计时。报告必须同时给出：

- 当前普通光环路径 `5.239s` 基线；
- 诊断性完全关闭派生光环查询的 `1.849s` 参考下界；
- 新牌手光环实现的总时间、apply、attack 和 event discovery；
- 动作、评分、完成深度、节点、事件/攻击计数和 TT 结果是否一致。

由于规则语义发生变化，含胡家刀法的局面允许动作或评分改变，但必须解释原因；
不含胡家刀法且状态相同的对照必须保持结果一致。发现任何可复现性能回退时立即
报告，不继续叠加其它功能。

## 测试计划

### 目录与原生支持

- 三张牌的最终 `abilities` 与本文 declaration 完全一致；
- `ACTION_GRANT_OWNER_AURA` 接受完整合法光环，拒绝空值、未知字段和不支持原语；
- `CONDITION_ABILITY_SOURCE_IN_ZONE` 校验 zone 和可省略布尔 `inverted`；
- 卡牌能力声明 `active_zones` 或 `auras` 时目录校验失败；
- 牌手光环声明 activation、active_zones 或 retained_on_flip 时校验失败；
- 当前目录不再包含任何 `active_zones`，卡牌能力不再直接包含 `auras`；
- 来鹤清泉的开局手牌揭示行为保持。

### 扫描边界

- `TRIGGER_DUEL_STARTED` 只发现双方手牌能力，并保持物理槽位顺序；
- 手牌中的普通 `CARD_BE_ATTACKED` 或攻击后能力不参与普通发现；
- 普通事件不遍历弃牌区或移除区；
- `CARD_AFTER_DISCARDED` 仍能发现刚被丢弃精确实例的合法自触发；
- 无光环普通局面的结果、事件顺序和搜索键保持不变。

### 普通触发再次确认

- 来源从发现格移动到其它格后，精确能力仍从新位置继续结算；
- 来源从发现区域进入其它区域后，已发现触发失效；
- 来源改变所属方但保留精确能力时，以结算时的新所属方重验条件和执行动作；
- 来源翻面导致精确能力被移除时，能力 handle 重验失败，不再结算；
- 来源效果门控在发现后被关闭，已发现触发仍继续结算；
- 来源效果门控在事件发现前已经关闭，该触发不会被发现；
- 来源实例彻底无法定位，或精确能力 handle 已不存在，触发失效；
- 事件攻击快照保持不变，不因来源移动或翻面而重新计算。

### 光环状态

- 开局动作把独立光环授予正确牌手并保存精确来源；
- 光环不进入任何卡牌的 `active_abilities`；
- 紧凑状态往返、复制和 checksum 保留光环及顺序；
- 两张同名来源安装两份独立光环；移除一份不会误删另一份；
- 来源翻面后，光环所属牌手不改变；
- 光环触发不因来源移动、换区、翻面、改变所属方、门控关闭或能力丢失而被
  通用重验拦截；
- 光环来源无法定位时，光环本身仍可结算，只有引用来源的具体条件或动作无效；
- 来源离开手牌后，光环在当前回合余下时间仍然有效；
- 任意一方回合结束时来源仍不在手牌，删除精确光环；
- 回合结束前来源重新回到手牌，光环保留。

### 八方藏刀式

- 开局揭示自身和当时全部敌方手牌；
- 后续抽牌不自动揭示；
- 光环存在时中央格限制生效，别无选择时中央格仍合法；
- 来源离手后，本回合内限制仍生效，回合结束移除后恢复。

### 怀中抱月

- 光环存在时所有当前友方防守点数视为零；
- 点数不足以形成成功攻击时不触发受击效果；
- 确实受击时先揭示并减少来源，再由接收牌抽一张并移除自身；
- 来源因减点归零离手时，本次结算和本回合余下光环效果继续；
- 多份光环分别处理来源，但已被第一份移除的接收牌不会重复抽牌。

### 闭门铁扇刀

- 每次确实发生的敌方攻击后，揭示并增加精确来源牌点数；
- 攻击本身未翻面时，只归零该攻击实际使用过的方向；
- 连锁能力翻面不阻止归零，攻击本身翻面则阻止；
- 来源离手后，本回合结束前仍按上述规则触发。

### 回归与性能

- 新胡斐敌人卡组和敌人目录测试通过；
- `test_hujia_chuncan_abilities.gd` 改为牌手光环语义；
- `test_duel_compact_state.gd`、`test_duel_state_key.gd`、
  `test_native_production_rules.gd` 覆盖完整运行时状态；
- 原生 Release 编译、所有定向测试和完整套件通过；
- 静音实机走通开局、来源离手和回合结束失效；
- 完成同口径固定节点性能对照并立即报告结果。
