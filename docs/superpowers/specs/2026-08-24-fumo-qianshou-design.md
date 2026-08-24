# 金刚伏魔圈与千手如来掌设计

日期：2026-08-24

## 范围

实装 `FuMoQuan3`、`FuMoQuan4` 与 `QianShouRuLai5` 的完整卡牌描述，补充可复用的移除后事件、运行时完美复制、移动牌阵营条件及隔敌攻击范围声明。所有规则继续由 `DuelSimulator` 权威结算，卡牌目录只组合通用 declaration，不在模拟器、搜索或表现层检查卡牌 ID。

## 已确认语义

- “完美复制”复制目标当时的完整运行时状态，包括当前四边点数、内力、当前有效能力及其它卡牌运行时字段；物理副本必须获得新的 `instance_id`。
- 千手如来掌在原格生成的复制视为普通进场：完整结算进场前、全场进场后能力和标准攻击。
- 千手如来掌会响应“四边降为 0 而被移除”的普通点数牌。
- 四边为 `-1` 的无点数牌不满足“有点数的牌”。
- 金刚伏魔圈反复满足空手条件时，相同的获授反应能力只保留一份，不叠加。
- 多个千手如来掌响应同一次移除时按全场行优先顺序结算；第一张成功占据原格后，其余进场动作因格位不空而无效。
- 金刚伏魔圈授予的反应能力不标记 `retained_on_flip`，因此按通用规则在翻面时失去。

## 通用词汇

### 移除后事件

新增全场触发事件：

```gdscript
const CARD_AFTER_EXILED: StringName = &"card_after_exiled"
```

每次真实移除完成后发出一次。事件上下文必须保存：

- 被移除实例在离场前的深拷贝快照；
- 被移除实例的 `instance_id`、离场前当前所属方和原所属方；
- 离场前所在区域与格位；
- 移除原因，包括点数归零；
- 原格引用，供后续进场动作使用。

全场来源在移除完成后从仍在场的牌中按 `0..8` 发现并快照；新生成的牌不加入当前这次事件的来源队列，避免同一事件递归发现。

新增通用条件：

```gdscript
{"type": CONDITION_TRIGGER_CARD_POWERS_COULD_CHANGE}
```

它读取离场前快照，并与 `CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE` 共用 `Rules.can_change_powers()` 判断。四边均为普通非负整数时成立，包含 `[0, 0, 0, 0]`；四边 `-1` 的无点数牌不成立。

### 运行时完美复制

新增卡牌规格：

```gdscript
{
    "type": CARD_SPEC_PERFECT_COPY,
    "of": CARD_REF_ABILITY_SOURCE,
}
```

该规格深拷贝引用卡牌快照，重新生成唯一且确定性的 `instance_id`。它保留 `card_id`、`original_owner`、点数、内力、有效能力、揭示等卡牌运行时数据，但清除原区域的物理放置信息（如手牌槽位）；目的区域重新分配位置。副本当前所属方由接收手牌或执行进场动作的一方决定。

`ACTION_ADD_CARD_TO_HAND` 与 `ACTION_SUMMON_CARD` 都接受此规格。前者沿用五张手牌上限与最左空槽规则；后者沿用完整普通进场管线。复制数据在规格实际执行时从稳定引用快照读取，不移动原实例。

原格复用现有 `CELL_REF_INITIAL_CARD_CELL`，并把 `CARD_REF_TRIGGER_CARD` 指向移除前快照；不新增专用格位词汇。

### 移动牌阵营条件

新增触发条件：

```gdscript
{"type": CONDITION_MOVING_CARD_IS_ALLY}
```

在 `CARD_BEFORE_MOVED` 中，“友方”相对能力来源结算时的当前所属方判断，并包含来源自身。移动上下文同时把 `CARD_REF_TRIGGER_CARD` 指向即将移动的精确实例，供通用动作引用。每次真实移动及交换的每一条腿仍独立发出移动前事件。

### 隔敌攻击范围

扩展现有 `MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO`：

```gdscript
{
    "type": MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO,
    "allow_intervening_ally": false,
    "allow_intervening_enemy": true,
}
```

它只允许直线上距离为二且中间恰为敌方的目标；普通相邻攻击保持不变。声明本身为锁定能力。范围检查由现有通用攻击合法性路径使用，因此自动反应攻击和普通/指定攻击共享同一规则。

## 卡牌 declaration

### 金刚伏魔圈 3/4 共通能力

```gdscript
const FUMO_SUMMON_REACTION: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [
            {"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
            {"type": CONDITION_TRIGGER_CARD_IN_RANGE},
        ],
        "actions": [
            {"type": ACTION_ATTACK_TRIGGER_CARD},
        ],
    }],
}

const FUMO_SHARED: Dictionary = {
    "triggers": [
        {
            "event": CARD_BEFORE_MOVED,
            "conditions": [
                {"type": CONDITION_MOVING_CARD_IS_ALLY},
            ],
            "actions": [
                {
                    "type": ACTION_CHANGE_POWERS,
                    "amount": -1,
                    "card": CARD_REF_TRIGGER_CARD,
                },
            ],
        },
        {
            "event": TRIGGER_END_OWNER_TURN,
            "conditions": [
                {"type": CONDITION_TURN_OWNER_IS_SELF},
            ],
            "actions": [{
                "type": ACTION_IF,
                "conditions": [
                    {"type": CONDITION_SOURCE_OWNER_HAND_EMPTY},
                ],
                "actions": [{
                    "type": ACTION_FOR_EACH_SELECTED_CARD,
                    "selector": {
                        "zones": [CARD_ZONE_BOARD],
                        "conditions": [
                            {"type": CONDITION_SELECTED_CARD_IS_ALLY},
                        ],
                    },
                    "actions": [{
                        "type": ACTION_GRANT_ABILITY_TO_SELF,
                        "ability": FUMO_SUMMON_REACTION,
                    }],
                }],
            }],
        },
    ],
}
```

`ACTION_GRANT_ABILITY_TO_SELF` 在选牌包装器中作用于当前选中牌；结构完全相同的被动能力沿用现有幂等去重。点数减少可能把移动牌降为四边 0 并移除；随后移动请求因精确实例不再在原格而自然失效。四边 `-1` 牌沿用通用点数变化无效规则，移动继续。

`FuMoQuan3.abilities = [FUMO_SHARED]`。

`FuMoQuan4` 额外加入：

```gdscript
const LOCKED_RANGE_TWO_ENEMY: Dictionary = {
    "retained_on_flip": true,
    "modifiers": [{
        "type": MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO,
        "allow_intervening_enemy": true,
    }],
}
```

即 `FuMoQuan4.abilities = [FUMO_SHARED, LOCKED_RANGE_TWO_ENEMY]`。这里的 `retained_on_flip` 仅表达描述中的“锁定”。

### 千手如来掌 5

```gdscript
const QIANSHOU_RESUMMON_PERFECT_COPY: Dictionary = {
    "triggers": [{
        "event": CARD_AFTER_EXILED,
        "conditions": [
            {"type": CONDITION_TRIGGER_CARD_WAS_ON_BOARD},
            {"type": CONDITION_TRIGGER_CARD_POWERS_COULD_CHANGE},
        ],
        "actions": [{
            "type": ACTION_SUMMON_CARD,
            "card": {
                "type": CARD_SPEC_PERFECT_COPY,
                "of": CARD_REF_ABILITY_SOURCE,
            },
            "cell": {
                "type": CELL_REF_INITIAL_CARD_CELL,
                "card": CARD_REF_TRIGGER_CARD,
            },
        }],
    }],
}

const QIANSHOU_DISCARD_PROTECTION: Dictionary = {
    "triggers": [{
        "event": CARD_BEFORE_FLIPPED,
        "conditions": [
            {"type": CONDITION_TRIGGER_CARD_IS_SELF},
        ],
        "actions": [{
            "type": ACTION_FOR_EACH_SELECTED_CARD,
            "selector": {
                "zones": [CARD_ZONE_HAND],
                "conditions": [
                    {"type": CONDITION_SELECTED_CARD_IS_ALLY},
                ],
                "limit": 1,
                "required_count": 1,
            },
            "actions": [
                {
                    "type": ACTION_DISCARD_CARD,
                    "card": CARD_REF_SELECTED_CARD,
                },
                {"type": ACTION_PREVENT_TRIGGER_FLIP},
                {
                    "type": ACTION_SPEND_KI,
                    "amount": 1,
                    "card": CARD_REF_ABILITY_SOURCE,
                    "on_invalid_context": STOP_RULE,
                },
                {
                    "type": ACTION_ADD_CARD_TO_HAND,
                    "card": {
                        "type": CARD_SPEC_PERFECT_COPY,
                        "of": CARD_REF_SELECTED_CARD,
                    },
                    "recipient": RECIPIENT_SELF,
                },
            ],
        }],
    }],
}
```

最终：

```gdscript
"abilities": [
    QIANSHOU_RESUMMON_PERFECT_COPY,
    QIANSHOU_DISCARD_PROTECTION,
]
```

左侧选择沿用物理 `hand_slot_index` 顺序。没有手牌时不会进入包装器，既不阻止翻面也不耗内力。成功弃牌后先阻止当前翻面；无内力时在耗内力动作停止该条规则，不获得复制，但翻面仍已被阻止。若弃牌自身事件先将手牌补满，内力仍照常消耗，随后加牌无效。加入手牌的完美复制读取被选中实例在此次规则中的稳定运行时快照，而不是创建目录初始状态。

## 事件顺序与边界

1. 外部移除或点数归零确定精确实例及离场前快照。
2. 完成移除区写入并发出现有 `card_exiled` 表现事件。
3. 清除外层动作的 ability-source 引用，发出 `CARD_AFTER_EXILED`，快照仍在场且合法的来源，按行优先依次结算；每个触发组重新绑定自己的能力来源。
4. 千手如来掌在原格尝试普通进场；每次成功进场的完整连锁结算完毕后才处理下一个移除后来源。
5. 原格已被占、来源已离场/翻面失去能力或引用失效时，该动作仅 `NO_EFFECT`，不影响后续来源。
6. 千手如来掌自身是被移除牌时已经不在全场来源集合，因此不会用自己的离场触发自身复制；其它仍在场的千手如来掌仍可响应。
7. 伏魔圈的移动前减点按来源行优先分别结算；多个来源会累计减点。某次减点移除移动牌后，剩余来源及最终移动按失效上下文自然跳过。
8. 伏魔圈授予的进场反应发生在被进场牌的标准攻击之前；只有触发牌在该反应实际开始时仍是敌方且位于来源当前攻击范围内才攻击。

## 测试与表现

先添加目录声明与纯模拟器回归测试，再实现通用词汇。至少覆盖：

- 两级伏魔圈的完整 declaration 与 4 级锁定隔敌范围；
- 自身/其它友方移动前减点、多个来源累计、降为 0 取消移动、`-1` 牌跳过减点；
- 空手回合结束授予全体友方、非空手不授予、重复授予去重；
- 敌方进场范围内反击、范围外不反击、反击在其标准攻击之前；
- 移除普通牌及四边归零时生成完美复制；四边 `-1` 不触发；
- 完美复制保留点数、内力和动态能力但拥有新实例 ID；正常进场连锁与标准攻击完整发生；
- 多来源竞争原格、来源自身被移除、原格被连锁占用；
- 千手翻面保护的无手牌、无内力、满手补牌、完美复制运行时状态与弃牌动画事件顺序；
- 搜索克隆和重放只消费纯数据事件，不需要控制器卡名分支。

本功能没有新的专属视觉效果。点数变化、移除、普通进场、攻击、弃牌和加牌全部复用现有事件与动画。完成后运行相关目录/模拟器套件，再运行一次完整 `tools/run_tests.ps1`，并实际启动对局走查两张牌的关键流程。
