# 太极拳、太极剑六张牌设计

日期：2026-08-17

## 目标

实装以下六张武当牌的完整描述能力，同时把钟馗抉目的友方攻击规则迁移到同一套通用攻击目标策略：

- `TaiJiSanHuan4`：三环套月 4
- `TaiJiSanHuan5`：三环套月 5
- `TaiJiDaKui5`：大魁星 5
- `TaiJiLuanHuan4`：太极拳·乱环诀 4
- `TaiJiLuanHuan5`：太极拳·乱环诀 5
- `TaiJiYinYang5`：太极拳·阴阳诀 5

所有规则继续以 `DuelSimulator` 为唯一权威路径。目录声明不得依赖命名卡牌分支，搜索、测试模式、真人对局和回放必须复用同一实现。

## 已确认的全局语义

### 点数比较颠倒

新增普通非保留修饰 `MODIFIER_POWER_COMPARISON_REVERSED`。

1. 先计算双方本次比较的有效点数，包括防守点数覆盖、最小边防守等修饰。
2. 若本次比较的任一参与牌具有颠倒修饰，则整次比较颠倒一次。
3. 两张牌都具有该修饰时仍只颠倒一次，不叠加，也不抵消。
4. 颠倒后严格较小的一方获胜；点数相等始终不成功。
5. 该规则同时适用于攻击者和防守者，适用于普通攻击、指定攻击和所有复用标准攻击判定的能力。

### 通用攻击目标策略

标准攻击和指定攻击统一使用结构化目标策略，而不是零散的 `allow_allied_targets` 与 `capture_owner_id` 布尔组合。目标关系至少支持：

- 默认：仅攻击攻击者的敌方；
- 仅友方：仅攻击攻击者的友方；
- 不分敌我：攻击攻击者的友方与敌方。

目录常量分别命名为 `ATTACK_TARGET_ENEMIES_ONLY`、`ATTACK_TARGET_ALLIES_ONLY` 和 `ATTACK_TARGET_ALL`。默认声明可省略 `ATTACK_TARGET_ENEMIES_ONLY`。

当目标是攻击者友方时，攻击成功后默认将目标翻成攻击者的敌方，即二人对局中的另一所属方。只有未来要求非标准归属结果的能力才显式覆盖翻面所属方。

钟馗抉目的 `MODIFIER_ENEMY_ATTACKS_ALL` 保持玩家可见行为不变，但内部改为返回“不分敌我”的同一种通用目标策略。其敌方攻击友方成功后，目标仍翻成攻击者的敌方。

### 每回合攻击上限

每名玩家在每个完整玩家回合内最多成功发起 20 次攻击。

- 一次四方向标准攻击只要至少一个目标通过初始合法性与点数检查，计一次；同时命中多个方向仍只计一次。
- 一次指定单目标攻击通过初始检查并发出 `attack_started` 时，计一次。
- 完全没有合法目标或点数不足的攻击尝试不计数。
- 达到 20 次后，该所属方本回合内后续攻击请求全部无效：不发 `attack_started`，不触发被攻击、翻面或攻击后能力。
- 被拒绝的攻击不阻止同一规则中后续非攻击动作继续执行。
- 每个完整玩家回合开始前，双方计数同时清零。额外出牌属于同一回合，不清零。
- 在对方回合中通过反应能力发起的攻击，计入实际攻击所属方在当前完整回合的额度。
- 计数归属于攻击成功发起时的攻击者所属方，之后的翻面不转移已经发生的计数。

`DuelState` 增加双方当前完整回合的攻击计数。该数据必须参与状态复制、搜索键和回放初始状态，避免 AI 合并攻击额度不同的局面。

## 进场攻击改写

新增普通非保留修饰 `MODIFIER_ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES`，用于三环套月与大魁星。

该修饰只影响一张牌正常进场流程末尾的普通进场攻击，不影响：

- `CARD_AFTER_SUMMONED` 中由其他能力发起的攻击；
- 移动后的攻击；
- 激活能力或后续回合中的攻击。

规则使用两阶段精确实例检查：

1. 新牌刚进入目标格时，记录所有当时与它正交相邻、属于敌方且携带该修饰的精确 `instance_id`。
2. 普通进场攻击前，对这些快照来源逐一重验：仍在场、仍与进场牌相邻、仍与进场牌敌对、修饰仍有效。
3. 至少一个来源通过重验时，本次进场攻击改为“仅攻击攻击者友方”。
4. 成功攻击友方后，目标按通用默认翻成攻击者的敌方。

同名替换实例、离场后重新进场的实例不能冒充最初记录的修饰来源。

## 移除区选择与同实例进场

选择器新增 `CARD_ZONE_REMOVED`，顺序为所属方 `removed_cards` 数组的现有顺序。新增选择条件 `CONDITION_SELECTED_CARD_HAS_NONZERO_POWER`：只要四边中至少一边不为零即合法。三环套月五阶还同时声明现有的 `CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE`，从而排除四边全为 `-1`、没有普通点数的牌。

`ACTION_SUMMON_CARD` 扩展为能从移除区召唤 `CARD_REF_SELECTED_CARD`：

- 使用同一个运行时实例；
- 保留被移除时的四边点数、内力、剩余能力、原始所属方和其他运行时数据；
- 成功占据目标格时从移除区真正删除该实例；
- 新的当前所属方设为能力来源的当前所属方；
- 进入完整的进场前、进场、进场后和普通进场攻击流程；
- 不创建新目录副本，不恢复已经失去的能力。

三环套月选择时，四边全为零或全为 `-1` 的牌保留在移除区并被跳过；继续寻找下一张合法牌。

新增目标规则 `TARGET_ANY_EMPTY_BOARD` 和格子引用 `CELL_REF_ACTIVATION_TARGET`，用于指定棋盘上的任意空位。

新增目标规则 `TARGET_ANY_ENEMY_BOARD`，用于指定场上的任意敌方牌。激活目标卡继续复用现有 `CARD_REF_SELECTED_CARD` 快照，不新增重复的卡牌引用类型。

## 卡牌声明

以下结构表达目录声明的意图；最终字段名须通过目录验证器并保持通用。

### 三环套月 4

```gdscript
"abilities": [{
    "modifiers": [{
        "type": MODIFIER_ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES,
    }],
}]
```

该能力未声明 `retained_on_flip`，翻面时失去。

### 三环套月 5

第一条能力与四阶相同。第二条为激活：

```gdscript
{
    "activation": {
        "input": ACTIVATION_DRAG_TO_TARGET,
        "target_rule": TARGET_ANY_EMPTY_BOARD,
        "costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
        "actions": [
            {
                "type": ACTION_FOR_EACH_SELECTED_CARD,
                "selector": {
                    "zones": [CARD_ZONE_REMOVED],
                    "conditions": [
                        {"type": CONDITION_SELECTED_CARD_IS_ALLY},
                        {"type": CONDITION_SELECTED_CARD_HAS_NONZERO_POWER},
                        {"type": CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE},
                    ],
                    "limit": 1,
                },
                "actions": [{
                    "type": ACTION_SUMMON_CARD,
                    "card": CARD_REF_SELECTED_CARD,
                    "cell": {"type": CELL_REF_ACTIVATION_TARGET},
                    "owner": OWNER_ABILITY_SOURCE,
                }],
            },
            {"type": ACTION_DRAW_CARDS, "amount": 1},
        ],
    },
}
```

移除区为空，或只有全零牌、四边全 `-1` 牌时，激活仍可选择空位并消耗一内力；选择器产生 `NO_EFFECT`，之后照常抽一张牌。复活实例的完整进场流程结束后才抽牌。

### 大魁星 5

第一条能力与三环套月四阶相同。第二条为激活：

```gdscript
{
    "activation": {
        "input": ACTIVATION_DRAG_TO_TARGET,
        "target_rule": TARGET_ANY_ENEMY_BOARD,
        "costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
        "actions": [
            {
                "type": ACTION_CHANGE_POWERS,
                "card": CARD_REF_SELECTED_CARD,
                "amount": 1,
            },
            {
                "type": ACTION_FOR_EACH_SELECTED_CARD,
                "selector": {
                    "zones": [CARD_ZONE_BOARD],
                    "conditions": [{"type": CONDITION_SELECTED_CARD_IS_ENEMY}],
                },
                "actions": [{
                    "type": ACTION_STANDARD_ATTACK_WITH_SELF,
                    "target_policy": ATTACK_TARGET_ALLIES_ONLY,
                }],
            },
        ],
    },
}
```

最终实现使用明确的任意敌方棋盘目标规则，不要求相邻。主动指定四边 `-1` 的阴阳掌力仍合法：耗内力和后续批量攻击照常，加点动作自身为 `NO_EFFECT`。

批量攻击在加点动作完成后按行优先快照全部当前敌方。每张实例的完整攻击链结束后再处理下一张；轮到时若已离场或已不再是敌方则跳过。每次攻击仅选择攻击者友方，并按通用规则将成功目标翻成攻击者敌方。

### 太极拳·乱环诀 4

```gdscript
"abilities": [{
    "modifiers": [{"type": MODIFIER_POWER_COMPARISON_REVERSED}],
}]
```

### 太极拳·乱环诀 5

保留四阶比较修饰，并增加独立攻击后能力：

```gdscript
{
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_ATTACK,
        "conditions": [{"type": CONDITION_ATTACKER_CARD_IS_SELF}],
        "actions": [{
            "type": ACTION_FOR_EACH_SELECTED_CARD,
            "selector": {
                "zones": [CARD_ZONE_BOARD],
                "conditions": [
                    {"type": CONDITION_SELECTED_CARD_IS_ALLY},
                    {"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
                ],
            },
            "actions": [{"type": ACTION_STANDARD_ATTACK_WITH_SELF}],
        }],
    }],
}
```

触发时按行优先快照所有当前相邻友方。攻击过程中后来才进入相邻位置的牌不追加；已离场或已变成敌方的快照成员轮到时跳过。乱环效果发起的攻击可以再次触发任意乱环效果，不加递归标记；每方每完整回合 20 次攻击上限负责有限终止。

### 太极拳·阴阳诀 5

保留乱环诀的比较修饰，并增加独立攻击后能力。它在自身真实攻击完整结束后，按当时棋盘快照全部当前敌方。本次攻击中已翻成友方的牌不获得效果；连锁中刚成为敌方且在快照时仍是敌方的牌会获得。

赋予的两个能力必须分开声明，以表达不同翻面保留属性：

```gdscript
const TAIJI_ZERO_DEFENSE: Dictionary = {
    "modifiers": [{"type": MODIFIER_DEFENDING_POWER_OVERRIDE, "value": 0}],
}

const TAIJI_EXILE_WHEN_ATTACKED: Dictionary = {
    "retained_on_flip": true,
    "triggers": [{
        "event": CARD_BE_ATTACKED,
        "conditions": [{"type": CONDITION_ATTACKED_CARD_IS_SELF}],
        "actions": [{"type": ACTION_EXILE_SELF}],
    }],
}
```

攻击后规则对每个快照敌方依次执行两个 `ACTION_GRANT_ABILITY_TO_SELF`。选择器嵌套动作中的“self”指当前选择对象。现有幂等能力授予规则保证每个精确能力最多一份。

- 防守视为零未声明保留，翻面时失去。
- 被攻击时移除声明 `retained_on_flip = true`，翻面后保留。
- 阴阳诀后来翻面、离场或失去能力，不撤销已经赋予的效果。
- 被赋予者一旦通过初始攻击检查，先发出 `attack_started` 并计入攻击额度，再在 `CARD_BE_ATTACKED` 中移除自身；不产生成功翻面。

## 钟馗抉目迁移

`KUIHUA_INDISCRIMINATE_ATTACK` 的目录声明可以保留现有修饰名称，以避免无意义的存档和测试改名；`DuelSimulator` 不再为它手工组装旧式布尔策略，而是通过通用目标策略解析：

```gdscript
{
    "target_relation": ATTACK_TARGET_ALL,
}
```

迁移后必须保持以下行为：

- 只有钟馗抉目完成一次真实攻击后才获得该效果；
- 其敌方的标准攻击可以同时选择友方与敌方；
- 攻击者友方被成功攻击后翻成攻击者敌方；
- 最小边防守、需自宫效果门和现有翻面/回手能力不变。

## 事件与表现

不新增太极专属控制器规则。所有玩家可见反馈复用已有纯数据事件：

- `powers_changed`
- `card_summoned`
- `card_drawn`
- `ability_gained`
- `ability_triggered`
- `attack_started`
- `card_flipped`
- `card_exiled`

第 21 次及以后被额度拒绝的攻击不发任何攻击类事件，避免播放虚假动画。三环的持续修饰和比较颠倒不额外播放被动脉冲；其结果通过实际目标、攻击和翻面表现出来。

## 失败与重验规则

- 激活目标在提交和结算前都使用精确目标规则重验。
- 三环复活只有在目标格仍为空、选择实例仍位于正确移除区时才从移除区取出。失败返回 `NO_EFFECT`，抽牌继续。
- 批量选择使用稳定精确实例快照；每个成员轮到时重验声明中的所属方、区域与相邻条件。
- 攻击额度只在初始攻击检查成功后增加。后续 `CARD_BE_ATTACKED` 移动或移除目标不会退回额度。
- 同一比较中颠倒修饰只读取一次布尔“是否存在”，不会按来源数量累加。

## 测试计划

新增聚焦套件 `tests/test_taiji_abilities.gd`，并加入 `tools/run_tests.ps1`。至少覆盖：

1. 六张牌目录声明、能力条目拆分、翻面保留和验证器拒绝非法字段。
2. 攻击者颠倒、防守者颠倒、双方颠倒、平局，以及防守覆盖为零后再颠倒。
3. 三环初始相邻/不相邻与攻击前保持/失去相邻的四种组合，以及精确来源替换失效。
4. 三环只影响普通进场攻击，不影响同一进场窗口中的能力攻击。
5. 三环五阶从任意空格复活同一实例，保留点数/内力/剩余能力，依次跳过并保留全零牌和四边全 `-1` 牌，成功后从移除区删除。
6. 三环五阶在无合法移除牌时仍耗内力并抽牌；复活完整进场链先于抽牌。
7. 大魁星指定任意敌方、对普通牌加一、对四边 `-1` 阴阳掌力加点无效但后续继续。
8. 大魁星按行优先批量攻击、途中离场/变友跳过、仅攻击攻击者友方并翻成攻击者敌方。
9. 乱环五阶只在真实攻击后快照相邻友方，并允许递归展开。
10. 普通多目标攻击计一次、指定攻击计一次、失败攻击不计；第 20 次成功、第 21 次静默无效；完整新回合重置，额外出牌不重置。
11. 阴阳诀以攻击后当前敌方为准，两个能力幂等，零防守不保留，自我移除保留，来源离场不撤销。
12. 被赋予自我移除的牌在 `CARD_BE_ATTACKED` 中离场，攻击计数保留且不触发成功翻面。
13. 钟馗抉目迁移后仍可令敌方攻击双方，友方目标成功后翻成攻击者敌方。
14. `DuelState` 复制和 `DuelStateKey` 区分攻击计数不同的状态。

实现前按仓库规则确认可复用的通过基线；实现后运行聚焦套件、完整套件，并在正式游戏路径中实际走一次三环复活或乱环连锁流程。
