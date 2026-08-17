# 武当派九张新卡能力设计

日期：2026-08-17

## 范围

本设计实装以下九张卡牌的完整描述能力：

- `RaoZhiRouJian2`、`RaoZhiRouJian3`、`RaoZhiRouJian4`
- `ShenMen13Jian1`、`ShenMen13Jian2`、`ShenMen13Jian3`
- `WuDangMianZhang1`、`WuDangMianZhang2`、`WuDangMianZhang3`

卡牌 ID、名称、图片、门派、等级、武器、描述、风味和基础点数以当前 `scripts/card_catalog.gd` 为准。本设计只补齐能力声明和所需通用规则，不在模拟器或搜索中加入卡牌 ID 分支。

## 设计原则

- `DuelSimulator` 仍是玩家、测试模式、贪心回退和深度搜索唯一权威规则路径。
- 新规则拆成可复用的事件、条件、动作和 modifier，由卡牌目录组合声明。
- 指定攻击与普通攻击保持不同语义。绕指柔剑的“首个目标”只改变普通攻击，不改写指定攻击的目标。
- 所有未标记锁定的能力按默认规则在翻面后失去。
- 所有连锁攻击继续受每方每回合最多发起 20 次攻击的现有上限约束。

## 通用攻击修正器

### 无限攻击范围

新增通用 modifier，令攻击者可以检查棋盘上任意其它格子的牌：

- 不要求同一行或同一列；
- 不受距离限制；
- 无视中间格子的卡牌；
- 仍受当前目标策略、点数比较、攻击许可和攻击上限约束。

普通攻击目标枚举按棋盘编号 `0 → 8` 进行。没有无限范围 modifier 的卡牌继续使用现有正交范围枚举。

### 非直线双轴择一比较

新增通用 modifier。攻击者与目标不在同一行且不在同一列时，同时确定两个相对方向：

- 纵向：攻击者朝向目标的上或下点数，对目标相反方向的点数；
- 横向：攻击者朝向目标的左或右点数，对目标相反方向的点数。

两组比较只要任意一组满足当前有效比较规则，攻击便在点数层面成立。太极的颠倒比较等通用修正分别作用于每一组比较。同一行或同一列时仍只比较唯一一组正对点数。

示例：攻击者在中宫 `4`，目标在左上 `0`，比较“攻击者上 vs 目标下”和“攻击者左 vs 目标右”，任意一组成功即可。

### 普通攻击只取首个合法目标

新增通用 modifier。普通攻击先套用当前有效目标策略，再按 `0 → 8` 选择首个合法目标，最多攻击一张：

- `enemies_only`：首个敌方；
- `allies_only`：首个友方；
- `all`：首个其它牌。

该 modifier 会受到钟馗抉目、一字电剑等目标策略影响。它不改变指定攻击：指定攻击仍尝试其明确指定的实例。

普通攻击开始时一旦选定目标，后续通过 `instance_id` 追踪该实例。若目标在 `CARD_BE_ATTACKED` 中被移除、所有权不再符合本次目标策略，或其它非移动条件失效，本次攻击结束且不顺延第二张。单纯移动不会令无限范围攻击失效。

## 全局攻击提交规则修正

当前实现会在 `CARD_BE_ATTACKED` 前后各进行一次完整点数比较。本设计将全局规则修正为：点数只在攻击开始前比较一次。

统一攻击顺序为：

1. 检查攻击许可、目标策略、范围和点数；
2. 若成立，记录攻击次数并发出 `attack_started`；
3. 结算全场 `CARD_BE_ATTACKED`；
4. 按精确实例重新定位攻击者和目标；
5. 只重新检查实例仍在场、相关所有权、目标策略、普通范围和非点数攻击许可，不再比较点数；
6. 若仍有效，进入 `CARD_BEFORE_FLIPPED`；
7. 沿用现有已提交翻面规则：进入 `CARD_BEFORE_FLIPPED` 后，单纯移动不会取消翻面；
8. 完成所有权改变、`CARD_AFTER_FLIPPED` 和攻击后事件。

因此，`CARD_BE_ATTACKED` 中发生的点数增减或攻防点数 modifier 变化不会取消已经成功开始的攻击。普通卡牌移动出攻击范围仍会在步骤 5 取消；拥有无限范围的绕指柔剑不会因移动取消。

## 禁止敌方攻击

新增通用 modifier：在该牌当前所有者的回合内，敌方不能发起攻击。

每个普通或指定攻击请求在记录攻击次数和发出 `attack_started` 前统一检查。它覆盖：

- 出牌后的普通攻击；
- 效果发起的普通攻击；
- 指定攻击；
- 被翻面牌的强制攻击；
- 攻击后反应和其它连锁攻击。

禁攻牌离场、改变所有权、失去该能力，或当前回合所有者改变后，限制立即按最新状态重新计算。被禁止的请求不记录攻击次数，也不发出攻击事件。

## 翻面前移除的护身能力

绕指柔剑 3/4 和武当绵掌 2/3 使用同一个非锁定能力条目，包含两个触发：

1. `CARD_BEFORE_FLIPPED`，触发牌是自己：通过通用 `ACTION_EXILE_CARD + CARD_REF_TRIGGER_CARD` 将自己真实移除。实例进入原始所有者的移除区，本次翻面取消。
2. `CARD_AFTER_FLIPPED`，攻击者是自己且被翻面牌是其它牌：执行 `ACTION_REMOVE_THIS_ABILITY`，永久失去整个护身能力条目。

若一次攻击原本可翻面多张牌，在成功翻面第一张后立即失去护身能力。后续攻击中该牌可以被正常翻面。非攻击翻面也会触发第一项护身；只有该牌作为攻击者成功翻面其它牌才会消耗护身。

## 令被翻面的牌发起攻击

新增通用引用攻击 action，接受 `CARD_REF_TRIGGER_CARD` 等精确卡牌引用，使该在场实例发起一次普通攻击。

神门十三剑 2/3 和武当绵掌 3 在 `CARD_AFTER_FLIPPED` 中检查攻击者是自己，然后对触发牌执行该 action：

- 每成功翻面一张牌便立即处理一次；
- 被翻面牌已经完成所有权改变和非锁定能力清理；
- 使用该实例的当前所有者、当前点数、当前保留能力和当前目标策略；
- 其攻击完整结算后才继续原攻击的下一目标或下一触发；
- 会正常触发攻击后能力和进一步连锁；
- 若实例已经离场、所有权再次变化导致请求失效或没有合法目标，则安全地 `NO_EFFECT`。

该 action 不携带卡牌 ID 语义，可供其它“令某张牌攻击”的能力复用。

## 指定能力结算后事件

新增全场事件，用于表示一次合法指定型 activation 已经完整结算：

- activation 必须具有明确目标；无目标能力、普通出牌和自动触发不发出该事件；
- 先验证并支付内力成本；
- 完整结算移动、交换、点数、攻击、召唤等 action 和嵌套请求；
- 在回合结束边界前发出事件；
- 即使目标状态变化使部分 action 最终 `NO_EFFECT`，只要 activation 本身合法并已经支付成本，仍视为使用了指定效果。

事件上下文携带发动卡牌的精确实例和发动时所有者。绕指柔剑 4 监听该事件；若它结算时仍在场，且发动时所有者与绕指柔剑 4 的当前所有者相同（包括绕指柔剑 4 自己发动），便发起一次普通攻击。发动卡牌在能力结算中移动、离场或改变所有权，不会改变“使用时是友方”的事实。

多个绕指柔剑 4 按场上格子 `0 → 8` 依次触发。每次反应攻击完整结算后再处理下一张。该反应能力不是锁定能力，绕指柔剑 4 翻面后失去。

## 具体 declaration

以下名称是本次实现采用的确切目录 vocabulary。所有名称都必须加入对应 `KNOWN_*` 白名单并接受目录校验：

```gdscript
const CARD_AFTER_TARGETED_ACTIVATION: StringName = &"card_after_targeted_activation"

const CONDITION_ACTIVATION_OWNER_IS_ALLY: StringName = &"activation_owner_is_ally"

const ACTION_STANDARD_ATTACK_WITH_CARD: StringName = &"standard_attack_with_card"

const MODIFIER_UNLIMITED_ATTACK_RANGE: StringName = &"unlimited_attack_range"
const MODIFIER_NON_ORTHOGONAL_ATTACK_ANY_AXIS: StringName = &"non_orthogonal_attack_any_axis"
const MODIFIER_STANDARD_ATTACK_FIRST_LEGAL_TARGET: StringName = &"standard_attack_first_legal_target"
const MODIFIER_ENEMY_CANNOT_ATTACK_DURING_OWNER_TURN: StringName = &"enemy_cannot_attack_during_owner_turn"
```

`ACTION_STANDARD_ATTACK_WITH_CARD` 必须声明 `card`，值必须属于 `KNOWN_CARD_REFERENCES`。本批卡牌使用 `CARD_REF_TRIGGER_CARD`。其它新增 condition 和 modifier 不接受额外字段。

### 可复用能力常量

绕指柔剑的三个锁定攻击修正器写在同一个能力条目中：

```gdscript
const RAOZHI_LOCKED_ATTACK_MODIFIERS: Dictionary = {
    "retained_on_flip": true,
    "modifiers": [
        {"type": MODIFIER_UNLIMITED_ATTACK_RANGE},
        {"type": MODIFIER_NON_ORTHOGONAL_ATTACK_ANY_AXIS},
        {"type": MODIFIER_STANDARD_ATTACK_FIRST_LEGAL_TARGET},
    ],
}
```

绕指柔剑 3/4 与武当绵掌 2/3 共用护身能力。此 declaration 不写 `retained_on_flip`，因此默认非锁定：

```gdscript
const WUDANG_EXILE_BEFORE_FLIP_UNTIL_OWN_FLIP: Dictionary = {
    "triggers": [
        {
            "event": CARD_BEFORE_FLIPPED,
            "conditions": [
                {"type": CONDITION_TRIGGER_CARD_IS_SELF},
            ],
            "actions": [
                {
                    "type": ACTION_EXILE_CARD,
                    "card": CARD_REF_TRIGGER_CARD,
                },
            ],
        },
        {
            "event": CARD_AFTER_FLIPPED,
            "conditions": [
                {"type": CONDITION_ATTACKER_CARD_IS_SELF},
            ],
            "actions": [
                {"type": ACTION_REMOVE_THIS_ABILITY},
            ],
        },
    ],
}
```

神门十三剑 2/3 与武当绵掌 3 共用“令被翻面牌攻击”能力：

```gdscript
const WUDANG_FLIPPED_CARD_ATTACK: Dictionary = {
    "triggers": [{
        "event": CARD_AFTER_FLIPPED,
        "conditions": [
            {"type": CONDITION_ATTACKER_CARD_IS_SELF},
        ],
        "actions": [{
            "type": ACTION_STANDARD_ATTACK_WITH_CARD,
            "card": CARD_REF_TRIGGER_CARD,
        }],
    }],
}
```

神门十三剑 3 的回合禁攻能力默认非锁定：

```gdscript
const SHENMEN_OWNER_TURN_ATTACK_LOCK: Dictionary = {
    "modifiers": [{
        "type": MODIFIER_ENEMY_CANNOT_ATTACK_DURING_OWNER_TURN,
    }],
}
```

绕指柔剑 4 的指定能力反应默认非锁定。`CARD_AFTER_TARGETED_ACTIVATION` 只为合法且已支付成本的指定型 activation 发出，因此 declaration 不再重复检查“是否指定”：

```gdscript
const RAOZHI_TARGETED_ACTIVATION_REACTION: Dictionary = {
    "triggers": [{
        "event": CARD_AFTER_TARGETED_ACTIVATION,
        "conditions": [
            {"type": CONDITION_ACTIVATION_OWNER_IS_ALLY},
        ],
        "actions": [
            {"type": ACTION_STANDARD_ATTACK_WITH_SELF},
        ],
    }],
}
```

### 九张牌的 abilities 字段

目录中的九张牌使用以下确切组合：

```gdscript
&"RaoZhiRouJian2": {
    # 其它元数据保持目录现值。
    "abilities": [
        RAOZHI_LOCKED_ATTACK_MODIFIERS,
    ],
},

&"RaoZhiRouJian3": {
    "abilities": [
        RAOZHI_LOCKED_ATTACK_MODIFIERS,
        WUDANG_EXILE_BEFORE_FLIP_UNTIL_OWN_FLIP,
    ],
},

&"RaoZhiRouJian4": {
    "abilities": [
        RAOZHI_LOCKED_ATTACK_MODIFIERS,
        WUDANG_EXILE_BEFORE_FLIP_UNTIL_OWN_FLIP,
        RAOZHI_TARGETED_ACTIVATION_REACTION,
    ],
},

&"ShenMen13Jian1": {
    "abilities": [],
},

&"ShenMen13Jian2": {
    "abilities": [
        WUDANG_FLIPPED_CARD_ATTACK,
    ],
},

&"ShenMen13Jian3": {
    "abilities": [
        WUDANG_FLIPPED_CARD_ATTACK,
        SHENMEN_OWNER_TURN_ATTACK_LOCK,
    ],
},

&"WuDangMianZhang1": {
    "abilities": [],
},

&"WuDangMianZhang2": {
    "abilities": [
        WUDANG_EXILE_BEFORE_FLIP_UNTIL_OWN_FLIP,
    ],
},

&"WuDangMianZhang3": {
    "abilities": [
        WUDANG_EXILE_BEFORE_FLIP_UNTIL_OWN_FLIP,
        WUDANG_FLIPPED_CARD_ATTACK,
    ],
},
```

这些共享常量由目录规范化和实例创建流程进行深拷贝；运行时卡牌之间不得共享可变 ability Dictionary。

## 九张卡牌声明

### 绕指柔剑

- `RaoZhiRouJian2`
  - 一个 `retained_on_flip = true` 能力条目，包含无限范围、非直线双轴择一、普通攻击首个合法目标三个 modifier。
- `RaoZhiRouJian3`
  - 继承同样的锁定 modifier 条目；
  - 另有一个非锁定护身能力条目。
- `RaoZhiRouJian4`
  - 继承同样的锁定 modifier 条目；
  - 一个非锁定护身能力条目；
  - 一个非锁定的友方指定效果后反应攻击条目。

绕指柔剑翻面后仍保留三个攻击修正器，但会失去尚未消耗的护身能力和指定效果反应。

### 神门十三剑

- `ShenMen13Jian1`：无能力。
- `ShenMen13Jian2`：自身翻面其它牌后，令该精确实例立即发起普通攻击。
- `ShenMen13Jian3`：包含神门十三剑 2 的能力，并增加非锁定的己方回合敌方禁攻 modifier。

### 武当绵掌

- `WuDangMianZhang1`：无能力。
- `WuDangMianZhang2`：非锁定护身能力。
- `WuDangMianZhang3`：非锁定护身能力，并在自身翻面其它牌后令该实例立即发起普通攻击。

## 事件与展示

新能力继续复用现有纯数据展示事件：

- 被接受的被动触发自动发出 `ability_triggered`，使用现有卡牌脉冲；
- 强制攻击使用现有 `attack_started` 和攻击动画；
- 护身移除使用现有 `card_exiled` 和移除动画；
- 能力消耗使用现有 `ability_lost` 展示。

不为任何卡牌新增控制器专用规则分支。若新增的指定能力后事件本身没有独立视觉需求，控制器无需为事件边界增加动画。

## 测试计划

### 目录与声明

- 九张卡牌元数据继续通过目录校验；
- 各等级能力数量、触发、modifier 和锁定拆分精确匹配本设计；
- 新事件、条件、动作和 modifier 通过白名单校验，未知字段继续被拒绝。

### 规则层

- 无限范围可攻击任意位置并穿过中间牌；
- 同一直线只比较一组点数；
- 非直线横纵两组任一成功即可，均失败才不可攻击；
- 太极颠倒比较等现有比较 modifier 与两组比较正确组合；
- 首个目标按 `0 → 8`，并分别覆盖 `enemies_only`、`allies_only`、`all`；
- 指定攻击保持明确目标，不受首目标 modifier 改写。

### 攻击提交回归

- `CARD_BE_ATTACKED` 中降低攻击者点数，已经开始的攻击仍翻面；
- `CARD_BE_ATTACKED` 中提高防守者点数，已经开始的攻击仍翻面；
- 普通牌在该事件中移出范围会取消；
- 绕指柔剑的攻击者或目标移动后仍继续；
- 目标被移除或所有权不再符合策略时取消且不顺延。

### 卡牌时序

- 护身能力在任何翻面前真实移除自己并取消翻面；
- 自身成功翻面第一张其它牌后永久失去护身；
- 绕指柔剑翻面后三个锁定攻击 modifier 保留，其它非锁定能力失去；
- 神门十三剑／武当绵掌令同一被翻面实例立即攻击，并允许正常攻击后连锁；
- 己方回合内敌方的普通、指定和连锁攻击均被神门十三剑 3 禁止；
- 合法友方指定能力完整结算后触发绕指柔剑 4；无目标能力、普通出牌和自动效果不触发；
- 多个反应源按行优先顺序结算；
- 离场或失效实例安全 `NO_EFFECT`；
- 所有连锁遵守现有 20 次攻击上限。

### 完整验证

依次运行新增定向测试、目录测试、规则测试、模拟器测试、搜索测试和生产集成测试，最后执行：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
```

启动 `main.tscn`，在 540×960 纵向视口走查至少一条护身移除、一条被翻面牌强制攻击、一条绕指柔剑远程首目标攻击和一条指定能力后反应攻击流程，并检查控制台与调试器。
