# 2026-09-07 胡家刀法与春蚕掌法五张牌设计

## 目标与范围

实装以下五张江湖牌及其目录声明：

- `HuJiaDao1`：八方藏刀式；
- `HuJiaDao2`：怀中抱月；
- `HuJiaDao3`：闭门铁扇刀；
- `ChunCanZhang2`：二阶春蚕掌法；
- `ChunCanZhang3`：三阶春蚕掌法。

本次同时建立通用的手牌生效能力与虚拟光环机制、补充攻击实际使用方向的上下文，
并清理与现有通用条件重复的 `CONDITION_ATTACKED_CARD_IS_SELF`。规则必须继续由
`DuelSimulator` 的原生内核统一执行，玩家、测试模式、贪心回退和深度搜索不得产生
不同结算。

本次不调整卡牌名称、品阶、门派、武器、图片、背景文本和目录中已经给出的点数，
也不包含 Windows 或 Android 导出。

## 已确认的共同语义

### 手牌能力

能力默认维持当前生效区域。只有显式声明：

```gdscript
"active_zones": [CARD_ZONE_HAND]
```

的能力才会在手牌中参与普通事件发现、修正器查询或光环计算。手牌能力仍然属于该
手牌实例自身的运行时能力，会受到能力丢失、临时压制、效果门控和区域变化影响。
卡牌离开声明的生效区域后，尚未发现的能力和光环立即失效。

现有 `CARD_AFTER_DISCARDED` 的弃牌区特殊发现规则保持不变；未声明
`active_zones` 的旧牌不会因为本次扩展而开始在手牌中触发。

### 虚拟光环

能力可以声明一个或多个虚拟光环：

```gdscript
"auras": [{
    "selector": {
        "zones": [CARD_ZONE_BOARD],
        "conditions": [...],
    },
    "ability": {...},
}]
```

光环声明是光环拥有者运行时能力的一部分，因此拥有者所在区域、所属方、能力是否
存在以及效果是否启用，都是局面状态。光环接收者只在规则查询和事件发现时被视为
拥有嵌套能力；不得把嵌套能力写入接收者的 `active_abilities`，不得给接收者增加新的
持久字段，也不得为同一可推导信息扩充搜索状态键。

已经为一个事件发现的虚拟触发是该次结算的临时快照。光环来源随后离开手牌，不会
撤销本次已经发现的虚拟触发；后续事件重新根据当前状态计算光环。虚拟触发在真正
执行前仍按接收者实例、位置、所属方和声明条件进行普通重验。

本次不增加 `stacking_key` 或其它专门去重字段。多张相同光环按普通能力发现。若第一
份虚拟触发已经令接收者离场，后续份数会因接收者重验失败而自然失效。

### 攻击翻面与实际使用方向

现有：

```gdscript
CONDITION_ATTACK_FLIPPED_ALLY_IN_RANGE
CONDITION_ATTACK_FLIPPED_ENEMY
```

只检查攻击点数比较本身直接造成的翻面。`CARD_BE_ATTACKED`、
`CARD_BEFORE_FLIPPED` 或其它连锁能力造成的翻面不进入 `attack_flips`，也不会令这两个
条件成立。新增的 `CONDITION_ATTACK_FLIPPED_ANY_CARD` 沿用完全相同的口径。

一次确实开始的攻击在临时 `EventContext` 中记录：

```gdscript
attack_flipped_any_card
used_attacker_power_directions
```

- `attack_flipped_any_card` 只在本次攻击通过点数比较直接翻面至少一张牌时为真；翻面
  被阻止、目标提前离场或触发能力造成翻面均不计入。
- `used_attacker_power_directions` 是本次完整攻击中用于建立成功攻击资格的攻击者方向
  集合，方向仍为上、右、下、左的 `0..3`。
- 相邻或同一直线目标只记录朝向目标且比较获胜的一边。
- 对可斜向攻击的目标，纵向与横向分别进行语义上的胜负判断。哪一边比较获胜就记录
  哪一边；两边都获胜则两边都记录。
- 同一方向命中多个目标只记录一次。
- 目标在 `CARD_BE_ATTACKED` 中离场，不撤销此前已经成功比较并记录的方向。
- 没有任何合法目标、没有开始任何一次点数比较的攻击不发出
  `TRIGGER_CARD_AFTER_ATTACK`，也没有已用方向。

## 新增通用声明

### 事件与条件

```gdscript
const TRIGGER_DUEL_STARTED: StringName = &"duel_started"
const CONDITION_ATTACK_FLIPPED_ANY_CARD: StringName = &"attack_flipped_any_card"
```

`CONDITION_ATTACK_FLIPPED_ANY_CARD` 接受可省略的布尔参数 `inverted`，默认 `false`。
`inverted = true` 表示本次攻击没有通过攻击点数比较直接造成任何翻面。

`TRIGGER_DUEL_STARTED` 在双方初始五张手牌、双方牌库和开局八卦方位全部建立后结算
一次，发生在回放初始状态快照、首帧手牌展示和首个拥有者回合开始时点之前。开局
能力产生的状态变化直接包含在回放初始状态中，不会在进入对局画面后补播动画。

### 动作

```gdscript
const ACTION_SET_ATTACK_USED_POWERS: StringName = &"set_attack_used_powers"
```

声明字段为：

```gdscript
{
    "type": ACTION_SET_ATTACK_USED_POWERS,
    "card": CARD_REF_ATTACKER_CARD,
    "value": 0,
}
```

本次只允许显式的攻击者引用和整数目标值。动作读取当前攻击上下文中的已用方向，
定位同一个攻击者实例，并只设置这些方向。攻击者已经离开所有合法区域，或相关方向
均已等于目标值时，动作无效。

实际变化合并为现有 `powers_changed` 数据事件，沿用当前点数变化前停顿、并行动画、
状态更新和四边归零移除流程。动作不得增加专用表现事件；四边变为零时照常移至原始
拥有者的移除区。

### 修正器

```gdscript
const MODIFIER_CANNOT_ATTACK: StringName = &"cannot_attack"
const MODIFIER_OPPONENT_PLAY_CELL_ONLY_IF_NO_OTHER_ACTION: StringName = (
    &"opponent_play_cell_only_if_no_other_action"
)
```

`MODIFIER_CANNOT_ATTACK` 阻止该牌发起所有攻击，包括进场标准攻击、指定攻击、反应
攻击和额外或重复攻击。没有确实开始的攻击，因此不增加攻击次数，不发攻击事件，也
不触发攻击后能力。它不阻止抽牌、移动、交换、加减点或其它非攻击效果。

`MODIFIER_OPPONENT_PLAY_CELL_ONLY_IF_NO_OTHER_ACTION` 带一个 `cell` 整数参数。合法
行动查询先建立不应用这类限制的基础行动集，再收集对方当前有效手牌能力所限制的
格子。如果基础行动集中存在任一合法主动能力，或存在向非受限格子的合法手牌出牌，
则删除向受限格子的手牌出牌；若基础行动只剩受限格子的手牌出牌，则保留这些行动。
行动验证、玩家交互、测试模式、贪心回退和 AI 搜索统一使用过滤后的行动集。

## 旧受击条件清理

删除：

```gdscript
CONDITION_ATTACKED_CARD_IS_SELF
```

当前目录中所有使用均位于 `CARD_BE_ATTACKED`，该事件的 `trigger_card` 就是被攻击牌。
所有现行目录声明和测试改用：

```gdscript
CONDITION_TRIGGER_CARD_IS_SELF
```

随后从 `KNOWN_TRIGGER_CONDITIONS`、原生 `ConditionOpcode`、编译映射和条件执行分支中
删除旧条件。历史设计文档保留当时的原语名称作为历史记录，不作为当前实现来源。

## 五张牌的完整声明

### 八方藏刀式

```gdscript
const HUJIA_HIDDEN_BLADE: Dictionary = {
    "active_zones": [CARD_ZONE_HAND],
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
        ],
    }],
    "modifiers": [{
        "type": MODIFIER_OPPONENT_PLAY_CELL_ONLY_IF_NO_OTHER_ACTION,
        "cell": 4,
    }],
}
```

开局能力结算时揭示当时仍在手牌中的这张八方藏刀式，并向其拥有者揭示届时仍位于
敌方手牌中的所有牌。目标不在对局建立时预先锁定；但这是一次性开局效果，之后新抽
入敌方手牌的牌不会持续自动揭示。

中央格限制仅在该实例仍位于其拥有者手牌、且该能力有效时存在。场上主动能力也算
“其它选择”。多个相同限制不会产生额外效果。

### 怀中抱月

```gdscript
const HUJIA_EMBRACE_MOON_GRANTED: Dictionary = {
    "modifiers": [{
        "type": MODIFIER_DEFENDING_POWER_OVERRIDE,
        "value": 0,
    }],
    "triggers": [{
        "event": CARD_BE_ATTACKED,
        "conditions": [{
            "type": CONDITION_TRIGGER_CARD_IS_SELF,
        }],
        "actions": [
            {"type": ACTION_DRAW_CARDS, "amount": 1},
            {"type": ACTION_EXILE_SELF},
        ],
    }],
}

const HUJIA_EMBRACE_MOON_HAND: Dictionary = {
    "active_zones": [CARD_ZONE_HAND],
    "triggers": [{
        "event": CARD_BE_ATTACKED,
        "conditions": [{
            "type": CONDITION_TRIGGER_CARD_IS_ALLY,
        }],
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
    }],
    "auras": [{
        "selector": {
            "zones": [CARD_ZONE_BOARD],
            "conditions": [{
                "type": CONDITION_SELECTED_CARD_IS_ALLY,
            }],
        },
        "ability": HUJIA_EMBRACE_MOON_GRANTED,
    }],
}
```

只要怀中抱月位于手牌，所有当前友方场上牌在攻击合法性判断中使用防守点数零。一次
攻击确实选中友方后，普通场上 `CARD_BE_ATTACKED` 能力先按既有顺序结算；仍合法的
手牌能力再按物理手牌从左到右揭示并减少各自四边一点；最后按场上格子 `0..8` 结算
光环派生的虚拟受击能力。

如果最后一张怀中抱月因本次减点四边归零并被移除，本次已经发现的虚拟能力仍令当前
被攻击友方抽一张牌并移除。从下一次攻击开始光环消失。若更早的普通场上能力已经令
被攻击牌离场或不再是友方，手牌能力的 `CONDITION_TRIGGER_CARD_IS_ALLY` 按现有实时
重验失败。

多张怀中抱月都会各自揭示并减一。多份虚拟能力正常进入发现结果；第一份令被攻击牌
离场后，后续份数因虚拟能力来源牌已不在场而失效，因此同一次受击实际只抽一张牌。

### 闭门铁扇刀

```gdscript
const HUJIA_CLOSED_DOOR_HAND: Dictionary = {
    "active_zones": [CARD_ZONE_HAND],
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_ATTACK,
        "conditions": [{
            "type": CONDITION_ATTACKER_CARD_IS_ENEMY,
        }],
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
    }],
}
```

进场标准攻击、指定攻击、反应攻击以及额外或重复攻击，只要至少进行了一次成功的攻击
资格比较，都会发出统一的攻击后时点。发起者在攻击开始时是能力来源的敌方即可触发；
后续所属方变化不改写这一快照。

若攻击直接造成任何翻面，归零分支不执行。若攻击没有直接造成翻面，即使攻击连锁中
的其它能力造成了翻面，仍将本次攻击实际获胜并使用过的攻击者方向设为零。

多张闭门铁扇刀分别揭示并加一，也会依次尝试归零。第一次归零后，后续相同设置因
数值未发生变化而无效；攻击者已经因四边归零离场时，后续设置同样无效，但其它手牌
中的闭门铁扇刀仍完成自己的揭示和加点。

### 春蚕掌法

```gdscript
const CHUNCAN_CANNOT_ATTACK: Dictionary = {
    "modifiers": [{
        "type": MODIFIER_CANNOT_ATTACK,
    }],
}
```

该能力不声明 `retained_on_flip`，不是锁定能力。未翻面时阻止春蚕掌法发起任何攻击；
翻面失去该能力后，新所属方可按普通规则令其攻击。

五张牌最终引用：

```gdscript
HuJiaDao1.abilities = [HUJIA_HIDDEN_BLADE]
HuJiaDao2.abilities = [HUJIA_EMBRACE_MOON_HAND]
HuJiaDao3.abilities = [HUJIA_CLOSED_DOOR_HAND]
ChunCanZhang2.abilities = [CHUNCAN_CANNOT_ATTACK]
ChunCanZhang3.abilities = [CHUNCAN_CANNOT_ATTACK]
```

## 原生数据流与顺序

1. `DuelInitialStateFactory` 建立双方五张主卡组手牌、牌库、难度状态与静态八卦方位。
2. 初始状态通过原生事件入口结算一次 `TRIGGER_DUEL_STARTED`。
3. 手牌事件发现只扫描能力显式声明的生效区域，并保留物理手牌顺序。
4. 光环查询从当前有效来源能力即时导出修正器；事件发现为符合 selector 的目标建立
   临时虚拟能力组，不改变任何目标运行时数据。
5. 攻击目标查询在成功点数比较时累积已用方向。攻击本身成功执行所有权翻转时记录
   `attack_flipped_any_card`；触发能力翻面不写入该字段。
6. `TRIGGER_CARD_AFTER_ATTACK` 携带只读攻击上下文。闭门铁扇刀通过通用条件和动作
   读取上下文并产生普通点数变化。
7. 所有新查询和动作均在原生内核中实现；GDScript 只负责目录、纯状态桥接和表现。

## 表现

- 对局开局揭示发生在首次绘制手牌前，直接显示正确正反面，不补播揭示动画。
- 对局中的怀中抱月和闭门铁扇刀使用现有 `card_revealed` 表现。
- 手牌和场上牌的加减点、方向归零及四边归零移除，全部使用现有
  `powers_changed`、批量点数动画和移除动画。
- 虚拟光环本身不增加图标、bead、提示或专用动画。
- 八方藏刀式的中央格限制只影响交互合法性，不增加额外提示。

## 无效与重验规则

- 手牌能力来源在执行前已离开手牌、失去能力或效果被禁用：该来源的尚未结算能力
  失效。
- 光环接收者在虚拟触发执行前已离场、已不满足友方条件或能力时点不再匹配：该份
  虚拟触发失效。
- 攻击者在闭门铁扇刀归零前已离开合法区域：归零动作无效，手牌来源的揭示和加点
  不回滚。
- 没有已用方向或所有已用方向本来就是目标值：设置动作无效，不发空的点数动画。
- 八方藏刀式离开手牌后，下一次合法行动查询立即恢复中央格，不缓存旧限制。

## 测试计划

新增一套集中单元测试，并扩展目录、原生规则、搜索与集成覆盖。

### 目录与迁移

- 五张牌的能力数组与本文 declaration 完全一致。
- 新事件、条件、动作、修正器、`active_zones` 和 `auras` 接受合法声明并拒绝未知字段。
- 当前目录和测试不再引用 `CONDITION_ATTACKED_CARD_IS_SELF`；所有旧受击牌使用
  `CONDITION_TRIGGER_CARD_IS_SELF` 且行为保持。

### 八方藏刀式

- 双方均可从手牌触发开局揭示；只揭示能力结算时实际位于敌方手牌的牌。
- 存在合法主动能力时中央格出牌非法。
- 存在任意非中央合法出牌时中央格出牌非法。
- 基础行动只剩中央格出牌时中央格合法。
- 来源离开手牌、能力失效或被压制后中央格限制消失。
- 玩家、敌人、贪心查询和深度搜索看到相同合法行动。

### 怀中抱月

- 光环存在时所有当前友方防守点数视为零，离开手牌后恢复正常。
- 确实被攻击时手牌来源揭示并四边减一；不足以发动攻击时不触发。
- 虚拟能力令被攻击友方抽一张并移除。
- 多张来源分别揭示减点，但当前被攻击牌实际只完成一次抽牌与移除。
- 最后一张来源因减点四边归零后，本次已经发现的虚拟能力仍完成；下一次攻击不再
  享受光环。
- 虚拟能力不写入接收者运行时能力、不改变紧凑状态往返或搜索键。

### 闭门铁扇刀

- 相邻及同轴攻击只归零实际使用方向。
- 斜向攻击只有纵向获胜、只有横向获胜、两边均获胜三种情况分别记录正确方向。
- 任一攻击直接翻面后不归零；攻击触发的其它能力造成翻面仍然归零。
- 目标在 `CARD_BE_ATTACKED` 离场时，已经使用的方向仍会归零。
- 没有合法目标、没有点数比较时不触发攻击后能力。
- 多张来源分别揭示加点，重复归零不产生空事件。
- 归零形成四边全零时照常移除攻击者。

### 春蚕掌法

- 未翻面时阻止进场标准、指定、反应、额外和重复攻击。
- 被禁止的攻击不计入每方每回合攻击次数上限，也不触发攻击后能力。
- 翻面后能力按非锁定规则移除，随后可以正常攻击。

### 回归

- 新敌人“雪山飞狐·胡斐”的五张卡组通过敌人目录测试。
- `test_native_production_rules.gd` 覆盖五张牌的完整运行时声明与合法行动。
- 开局状态、回放初始快照、手牌揭示、点数动画及移除表现通过对应集成测试。
- 实施完成后运行 Windows 原生库编译、全部定向测试和完整测试套件；不进行发布导出。
