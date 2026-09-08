# 目录累计平衡改动能力设计

日期：2026-09-08

## 目标与范围

本次实现 `4f7b64f..cab9cb7` 之间 `scripts/card_catalog.gd` 的全部玩法改动，而不是只处理最后一次提交。涉及以下十一张牌：

- `HanBinZhenQi3`、`HanBinZhenQi4`
- `FeiTian5`
- `KuiHua1`
- `DuGu9Jian1`、`DuGu9Jian2`、`DuGu9Jian3`
- `LaiHeQinQuan4`、`LaiHeQinQuan5`
- `XiXinDaFa4`、`XiXinDaFa5`

牌面名称、图片、门派、品阶、武器、描述、背景文字和基础点数以当前目录为准。本设计只补齐目录声明与原生规则，不增加卡牌 ID 分支，不恢复 GDScript 规则后端，也不改变 AI 的完全信息视野。

## 方案

采用最小通用原语方案：复用现有触发、选择、抽牌、移除、额外出牌、揭示、加内力和变身动作，只增加一个动态数值、一个永久失效动作、一个动作条件，并给两个现有原语增加可选字段。

未采用以下方案：

- 不给现有动作叠加多组只服务单张牌的模式字段，以免验证和执行语义变得含混。
- 不增加寒冰真气、岱宗如何、吸星大法或独孤九剑专属的原生 opcode；搜索与结算继续只认识通用目录原语。

## 新增与扩展的目录原语

### `VALUE_CARD_KI`

声明：

```gdscript
const VALUE_CARD_KI: StringName = &"card_ki"
```

数值规格：

```gdscript
{
    "type": VALUE_CARD_KI,
    "card": CARD_REF_ABILITY_SOURCE,
}
```

它读取动作执行时指定精确运行时实例的当前内力。首个使用者是 `ACTION_GAIN_KI.amount`。`ACTION_GAIN_KI.amount` 因此接受原有正整数或上述数值规格；动态结果小于等于零，或引用实例已无效，本动作返回 `NO_EFFECT`，不阻断同一列表中的后续动作。它不会消耗被读取牌的内力。

### `ACTION_PERMANENTLY_REMOVE_NON_RETAINED_ABILITIES`

声明：

```gdscript
const ACTION_PERMANENTLY_REMOVE_NON_RETAINED_ABILITIES: StringName = (
    &"permanently_remove_non_retained_abilities"
)
```

动作规格：

```gdscript
{
    "type": ACTION_PERMANENTLY_REMOVE_NON_RETAINED_ABILITIES,
    "card": CARD_REF_SELECTED_CARD,
}
```

动作永久删除目标运行时实例的全部非保留能力，保留所有显式声明 `retained_on_flip = true` 的能力。它同时删除触发、修正器和主动能力所在的非保留能力条目；不改牌的 ID、点数、内力、所属方、原所属方、位置或揭示状态。

每个实际删除的能力继续发出既有永久 `ability_lost` 纯数据事件，事件携带动作来源实例与目标实例。由于岱宗如何是外部来源，目标牌不播放“自己令自己失去能力”时才有的闪动。若目标没有可删除能力，动作是 `NO_EFFECT`；岱宗如何后续是否给予额外出牌仍只取决于揭示状态。

### `CONDITION_SELECTED_CARD_REVEALED_TO_SELF`

声明：

```gdscript
const CONDITION_SELECTED_CARD_REVEALED_TO_SELF: StringName = (
    &"selected_card_revealed_to_self"
)
```

该条件仅用于 `ACTION_IF`，读取当前选择的精确牌实例，判断其是否已经向能力来源的当前所属方揭示。它不揭示目标，也不重新选择目标。

### `CONDITION_KI_AT_LEAST.inverted`

原有声明：

```gdscript
{"type": CONDITION_KI_AT_LEAST, "amount": 1}
```

扩展后的零内力判断：

```gdscript
{
    "type": CONDITION_KI_AT_LEAST,
    "amount": 1,
    "inverted": true,
}
```

`inverted` 为可省略布尔值，默认 `false`。为 `true` 时对最终比较结果取反，因此上例表示能力来源当前内力小于一，也就是零内力。非法来源仍为条件失败，而不是因反转变成成功。

### `ACTION_TRANSFORM_CARD.preserve_powers`

扩展声明：

```gdscript
{
    "type": ACTION_TRANSFORM_CARD,
    "card": CARD_REF_SELECTED_CARD,
    "card_id": &"TaiZuChangQuan",
    "preserve_powers": true,
}
```

`preserve_powers` 为可省略布尔值，默认 `false`，保持现有变身行为。为 `true` 时，变身后保留旧实例当时的四边点数；除此之外仍按现有变身规则处理：

- 保留同一个 `instance_id`、当前所属方、原所属方、当前区域/格子/手牌槽与揭示状态；
- 牌面 ID、名称、图片、武器及目录派生字段改为新牌；
- 内力重置为新牌目录初始内力；
- 运行时能力替换为新牌目录能力，不保留旧牌获得或剩余的能力；
- 发出既有 `card_transformed` 事件，不发出 `powers_changed`，因为四边数值没有变化。

### 下一张手牌失效的既有原语

保留 `ACTION_ADD_PENDING_NON_RETAINED_SUPPRESSION`、现有双方计数及其状态键格式。唯一语义调整是移除“心法牌跳过且不消耗层数”的旧特例：现在目标方下一张真正从手牌打出的任意牌都会消耗一层，并在进场流程开始前永久删除其非保留能力。保留能力照常保留；即使该牌没有可删除能力，本层也会被消耗。

## 完整目录声明

以下声明是本次落地后的规范文本。辅助常量名称也视为设计的一部分；实际格式可按项目现有 GDScript 排版调整，但字段、数组顺序和语义不得变化。

### 寒冰真气

```gdscript
const HANBIN_POWER_BATCH: StringName = &"hanbin_frozen_turn"

const HANBIN_FROZEN_TURN: Dictionary = {
    "triggers": [{
        "event": TRIGGER_END_OWNER_TURN,
        "conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
        "actions": [
            {
                "type": ACTION_CHANGE_POWERS,
                "amount": -1,
                "card": CARD_REF_ABILITY_SOURCE,
                "power_change_batch_group": HANBIN_POWER_BATCH,
            },
            {
                "type": ACTION_FOR_EACH_SELECTED_CARD,
                "selector": {
                    "zones": [CARD_ZONE_HAND],
                    "conditions": [
                        {"type": CONDITION_SELECTED_CARD_IS_ALLY},
                        {"type": CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE},
                    ],
                },
                "actions": [{
                    "type": ACTION_CHANGE_POWERS,
                    "amount": -1,
                    "card": CARD_REF_SELECTED_CARD,
                }],
                "power_change_batch_group": HANBIN_POWER_BATCH,
            },
        ],
    }],
}

const HANBIN_ACTIVATION: Dictionary = {
    "activation": {
        "input": ACTIVATION_DRAG_TO_TARGET,
        "target_rule": TARGET_ENEMY_HAND_CARD,
        "costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
        "actions": [
            {
                "type": ACTION_CHANGE_POWERS,
                "amount": -4,
                "card": CARD_REF_SELECTED_CARD,
            },
            {
                "type": ACTION_REVEAL_CARD,
                "card": CARD_REF_SELECTED_CARD,
                "observer": OWNER_ABILITY_SOURCE,
            },
        ],
    },
}

const HANBIN_AFTER_FLIP_GRANT: Dictionary = {
    "triggers": [{
        "event": CARD_AFTER_FLIPPED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{
            "type": ACTION_GRANT_ABILITY_TO_SELF,
            "ability": HANBIN_FROZEN_TURN,
        }],
    }],
}

const HANBIN_ZERO_KI_END_TURN_FLIP: Dictionary = {
    "triggers": [{
        "event": TRIGGER_END_OWNER_TURN,
        "conditions": [
            {"type": CONDITION_TURN_OWNER_IS_SELF},
            {
                "type": CONDITION_KI_AT_LEAST,
                "amount": 1,
                "inverted": true,
            },
        ],
        "actions": [{
            "type": ACTION_FLIP_SELF,
            "new_owner": OWNER_OPPONENT_OF_ABILITY_SOURCE,
        }],
    }],
}

# HanBinZhenQi3
"abilities": [HANBIN_ACTIVATION, HANBIN_AFTER_FLIP_GRANT]

# HanBinZhenQi4
"abilities": [
    HANBIN_ZERO_KI_END_TURN_FLIP,
    HANBIN_ACTIVATION,
    HANBIN_AFTER_FLIP_GRANT,
]
```

冻结效果在来源当前所属方回合结束时执行。来源自身与当时其所属方手牌中的所有合法牌各减一点；四边 `-1` 牌和其它不可改变点数的牌跳过。逻辑结算保持动作顺序，展示继续用同一 `power_change_batch_group` 同时播放所有实际点数变化。四阶牌只有在回合结束检查时为零内力才翻面；失去最后内力的瞬间不再翻面。该次翻面新获得的结束阶段能力不回溯加入正在结算的同一个结束事件。

### 飞天神行

```gdscript
# FeiTian5
"abilities": [{
    "triggers": [{
        "event": TRIGGER_END_OWNER_TURN,
        "conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
        "actions": [{
            "type": ACTION_GRANT_EXTRA_CARD_PLAY,
            "amount": 1,
        }],
    }],
}]
```

它使用现有“每方每个实际回合最多成功获得一次额外出牌”的规则。已经获得过额外出牌时，本次授予无效，不形成跨回合储存。

### 天人化生

```gdscript
const KUIHUA_HEAVEN_HUMAN: Dictionary = {
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

# KuiHua1
"powers": [-1, -1, -1, -1]
"effect_gate": EFFECT_GATE_SELF_CASTRATION
"abilities": [KUIHUA_HEAVEN_HUMAN]
```

两次返回都沿用现有“上一张从手牌打出”的精确实例记录。只有该实例仍在场时才会返回；手牌已满时使用现有返回失败/外部移除语义。无论一个或两个返回是否成功，后续抽牌和额外出牌按声明继续结算。自宫门槛不变：未满足时整张牌的能力无效。

### 独孤九剑

```gdscript
const DUGU_NO_FORM: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_BEFORE_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [
            {
                "type": ACTION_REVEAL_HAND_CARDS,
                "recipient": RECIPIENT_OPPONENT,
                "filter": REVEAL_FILTER_ALL,
            },
            {
                "type": ACTION_ENABLE_FUTURE_DRAW_REVEAL,
                "recipient": RECIPIENT_OPPONENT,
            },
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
                    {"type": ACTION_DRAW_CARDS, "amount": 1},
                ],
            },
        ],
    }],
}

const DUGU_ANTICIPATE: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_BEFORE_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [
            {"type": ACTION_EXILE_SELF},
            {"type": ACTION_DRAW_CARDS, "amount": 1},
            {"type": ACTION_GRANT_EXTRA_CARD_PLAY, "amount": 1},
            {
                "type": ACTION_ADD_PENDING_NON_RETAINED_SUPPRESSION,
                "recipient": RECIPIENT_OPPONENT,
                "amount": 1,
            },
        ],
    }],
}

const DUGU_BREAK_ALL: Dictionary = {
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
                    "conditions": [{"type": CONDITION_SELECTED_CARD_IS_ENEMY}],
                },
                "actions": [{
                    "type": ACTION_TRANSFORM_CARD,
                    "card": CARD_REF_SELECTED_CARD,
                    "card_id": &"TaiZuChangQuan",
                    "preserve_powers": true,
                }],
            },
            {"type": ACTION_GRANT_EXTRA_CARD_PLAY, "amount": 1},
        ],
    }],
}

# DuGu9Jian1
"abilities": [DUGU_NO_FORM]

# DuGu9Jian2
"abilities": [DUGU_ANTICIPATE]

# DuGu9Jian3
"abilities": [DUGU_BREAK_ALL]
```

无招胜有招先使当前敌方手牌和后续抽到的牌对能力来源方可见，再进行原有移除与逐张抽牌。未来揭示沿用现有持久对局状态，不依赖这张牌继续存在。

料敌机先的待失效层可叠加。每次对手从手牌正常打出一张牌时只消耗一层；这张牌在 `CARD_BEFORE_SUMMONED` 的其它能力发现与结算前就只剩保留能力，因此本次进场不会触发被删掉的非保留进场前能力。

破尽天下按棋盘 `0..8` 快照敌方实例并依次变身。每个仍在场且仍为敌方的选中实例变成同一运行时实例的太祖长拳，保留其变身前的当前四边点数；内力归零，能力变为太祖长拳的能力。某张目标在轮到它前失效时只跳过该目标，不重新补选。

### 来鹤清泉与岱宗如何

```gdscript
const LAIHE_DUEL_START_REVEAL: Dictionary = {
    "active_zones": [CARD_ZONE_HAND],
    "triggers": [{
        "event": TRIGGER_DUEL_STARTED,
        "actions": [{
            "type": ACTION_REVEAL_HAND_CARDS,
            "recipient": RECIPIENT_OPPONENT,
            "filter": REVEAL_FILTER_ALL,
        }],
    }],
}

const LAIHE_FLIP_PROTECTION: Dictionary = {
    "triggers": [
        {
            "event": CARD_BEFORE_FLIPPED,
            "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
            "actions": [{"type": ACTION_PREVENT_TRIGGER_FLIP}],
        },
        {
            "event": CARD_AFTER_FLIPPED,
            "conditions": [{"type": CONDITION_TRIGGER_CARD_WAS_ENEMY}],
            "actions": [{"type": ACTION_REMOVE_THIS_ABILITY}],
        },
        {
            "event": TRIGGER_START_OWNER_TURN,
            "conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
            "actions": [{"type": ACTION_REMOVE_THIS_ABILITY}],
        },
    ],
}

const DAIZONG_HAND_SUPPRESSION_ACTIVATION: Dictionary = {
    "activation": {
        "input": ACTIVATION_DRAG_TO_TARGET,
        "target_rule": TARGET_ENEMY_HAND_CARD,
        "costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
        "actions": [
            {
                "type": ACTION_PERMANENTLY_REMOVE_NON_RETAINED_ABILITIES,
                "card": CARD_REF_SELECTED_CARD,
            },
            {
                "type": ACTION_IF,
                "conditions": [{
                    "type": CONDITION_SELECTED_CARD_REVEALED_TO_SELF,
                }],
                "actions": [{
                    "type": ACTION_GRANT_EXTRA_CARD_PLAY,
                    "amount": 1,
                }],
            },
        ],
    },
}

# LaiHeQinQuan4
"main_deck_effects": [MAIN_DECK_EFFECT_UNDO_LAST_PLAYER_DECISION]
"abilities": [LAIHE_DUEL_START_REVEAL, LAIHE_FLIP_PROTECTION]

# LaiHeQinQuan5
"starting_ki": 3
"main_deck_effects": [MAIN_DECK_EFFECT_UNDO_LAST_PLAYER_DECISION]
"abilities": [DAIZONG_HAND_SUPPRESSION_ACTIVATION, LAIHE_FLIP_PROTECTION]
```

来鹤清泉四阶仅在对局初始化完成后的 `TRIGGER_DUEL_STARTED` 揭示对手五张初始手牌；它不启用后续抽牌揭示，也不在后来进场时再次揭示。若双方手牌都有该能力，按现有手牌固定槽顺序完成同一开局事件。

岱宗如何可以主动指定任何对手手牌，隐藏与已揭示目标都合法，耗一点内力后永久删除目标非保留能力。目标在动作开始时已经向能力来源方揭示，才尝试给予一次额外出牌；判断发生在失效动作之后，但失效不改变揭示状态。其旧有“记忆牌揭示”和“已揭示敌方进场防守视为零”两条能力完全移除。翻面保护和主卡组悔棋效果保留。

### 吸星大法与北冥神功

```gdscript
const XIXING_BEIMING_TRANSFER: Dictionary = {
    "type": ACTION_TRANSFER_CARD_RESOURCE,
    "from": CARD_REF_SELECTED_CARD,
    "to": CARD_REF_ABILITY_SOURCE,
    "amount": 1,
    "resource": RESOURCE_KI,
    "fallback_resource": RESOURCE_POWERS,
}

const XIXING_BEIMING_TRANSFERABLE: Dictionary = {
    "type": CONDITION_SELECTED_CARD_CAN_TRANSFER_RESOURCE,
    "amount": 1,
    "resource": RESOURCE_KI,
    "fallback_resource": RESOURCE_POWERS,
}

const XIXING_BEIMING_TURN_ABSORB: Dictionary = {
    "triggers": [{
        "event": TRIGGER_START_OWNER_TURN,
        "conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
        "actions": [
            {
                "type": ACTION_FOR_EACH_SELECTED_CARD,
                "selector": {
                    "zones": [CARD_ZONE_HAND],
                    "conditions": [
                        {"type": CONDITION_SELECTED_CARD_IS_ALLY},
                        XIXING_BEIMING_TRANSFERABLE,
                    ],
                    "limit": 1,
                },
                "actions": [XIXING_BEIMING_TRANSFER],
            },
            {
                "type": ACTION_FOR_EACH_SELECTED_CARD,
                "selector": {
                    "zones": [CARD_ZONE_BOARD],
                    "conditions": [
                        {"type": CONDITION_SELECTED_CARD_IS_ALLY},
                        {"type": CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
                        {"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
                        XIXING_BEIMING_TRANSFERABLE,
                    ],
                },
                "actions": [XIXING_BEIMING_TRANSFER],
            },
        ],
    }],
}

const XIXING_BEIMING_ZERO_DEFENSE: Dictionary = {
    "modifiers": [{
        "type": MODIFIER_DEFENDING_POWER_OVERRIDE,
        "value": 0,
    }],
}

const XIXING_BEIMING_AFTER_FLIP_BROADCAST_KI: Dictionary = {
    "triggers": [{
        "event": CARD_AFTER_FLIPPED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [
            {
                "type": ACTION_FOR_EACH_SELECTED_CARD,
                "selector": {
                    "zones": [CARD_ZONE_HAND, CARD_ZONE_BOARD],
                    "conditions": [
                        {"type": CONDITION_SELECTED_CARD_IS_ALLY},
                        {"type": CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
                    ],
                },
                "actions": [{
                    "type": ACTION_GAIN_KI,
                    "amount": {
                        "type": VALUE_CARD_KI,
                        "card": CARD_REF_ABILITY_SOURCE,
                    },
                    "card": CARD_REF_SELECTED_CARD,
                }],
            },
            {"type": ACTION_STANDARD_ATTACK_WITH_SELF},
        ],
    }],
}

const XIXING_BEIMING_AFTER_INITIAL_FLIP_GRANT: Dictionary = {
    "triggers": [{
        "event": CARD_AFTER_FLIPPED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [
            {
                "type": ACTION_GRANT_ABILITY_TO_SELF,
                "ability": XIXING_BEIMING_TURN_ABSORB,
            },
            {
                "type": ACTION_GRANT_ABILITY_TO_SELF,
                "ability": XIXING_BEIMING_ZERO_DEFENSE,
            },
            {
                "type": ACTION_GRANT_ABILITY_TO_SELF,
                "ability": XIXING_BEIMING_AFTER_FLIP_BROADCAST_KI,
            },
        ],
    }],
}

const XIXING_BEIMING_ENTRY_FLIP: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{
            "type": ACTION_FLIP_SELF,
            "new_owner": OWNER_OPPONENT_OF_ABILITY_SOURCE,
        }],
    }],
}

const XIXING_SELF_ATTACKS_ALL: Dictionary = {
    "retained_on_flip": true,
    "modifiers": [{"type": MODIFIER_SELF_ATTACKS_ALL}],
}

# XiXinDaFa4
"abilities": [
    XIXING_SELF_ATTACKS_ALL,
    XIXING_BEIMING_ENTRY_FLIP,
    XIXING_BEIMING_AFTER_INITIAL_FLIP_GRANT,
]

# XiXinDaFa5
"abilities": [
    XIXING_BEIMING_ENTRY_FLIP,
    XIXING_BEIMING_AFTER_INITIAL_FLIP_GRANT,
]
```

来源翻面后的广播按手牌固定槽顺序、再按棋盘 `0..8` 顺序选择当时所有其它友方；不要求目标能消耗内力，四边 `-1` 牌也能获得内力。每个目标执行时读取来源当时的当前内力并增加等量内力，来源本身不减少。所有目标完成后来源发起一次标准攻击；若来源已离场，攻击按既有无效上下文规则跳过。

## 原生编译与状态

目录验证器、原生声明编译器与执行器需要识别上述新字段。所有规则在 `DuelNativeCompactKernel` 中实现，玩家、测试模式、贪心回退和深度 AI 共用同一路径。

本次不新增持久对局状态字段：料敌机先继续使用现有双方待失效计数，所以紧凑状态布局、状态键和置换表键的字段集合不变。能力声明和运行时能力变化仍由现有状态校验和覆盖。`preserve_powers`、动态内力值和新动作/条件只存在于已编译声明中。

## 事件与展示

- 寒冰真气的多张减点沿用现有 `powers_changed` 与批组展示；变化前停顿、同时动画和四零移除顺序不变。
- 内力广播为每个实际目标发出既有 `ki_changed`，不新增卡牌专用事件。
- 永久失效发出既有永久 `ability_lost`；来源实例为岱宗如何或待失效来源上下文。
- 破尽天下发出逐张 `card_transformed`；点数没有变化，因此不播放点数变化动画。
- 其它动作继续使用既有移除、抽牌、返回手牌、揭示、翻面、标准攻击和额外出牌事件。

控制器只消费这些通用事件，不增加卡牌 ID 判断。

## 验证与测试

实现按以下层次验证：

1. 目录验证：新常量均进入已知列表；拒绝错误类型、未知引用、非法 `inverted`、非法 `preserve_powers` 和不适用的动态数值规格；十一张牌的完整声明通过验证。
2. 寒冰真气：三/四阶冻结均在回合结束触发，覆盖全部合法手牌、跳过四边 `-1`，批组一致；四阶失去最后内力时不翻，零内力结束回合才翻，有内力不翻。
3. 飞天神行：自己回合结束授予额外出牌，敌方回合结束不触发，既有每回合一次上限继续生效。
4. 天人化生：自宫门槛、进场前自移除、抽牌、双方上一张手牌出牌返回、额外出牌以及手满失败路径。
5. 无招胜有招：立即揭示当前手牌、后续抽牌持续揭示，并保持原有自身/相邻移除与逐张抽牌顺序。
6. 料敌机先：任意武器牌均消耗待失效层；非保留能力在其进场前失效，保留能力继续存在；无能力目标也消耗层；多层逐张消耗。
7. 破尽天下：多个敌方按行优先变身；同一实例、当前/原所属方、位置、揭示状态和四边点数保留；ID/牌面、内力和能力换成太祖长拳；友方不变。
8. 来鹤清泉四阶：只在对局开始揭示五张初始敌方手牌，不揭示后续抽牌，后来进场不重复揭示。
9. 岱宗如何：隐藏与已揭示对手手牌均可指定且永久失去非保留能力；只有已揭示目标给予额外出牌；目标无可删能力仍按揭示状态处理；旧两条岱宗能力不再存在。
10. 吸星/北冥：翻面后手牌再棋盘顺序给所有其它友方增加来源当前内力，包含没有主动能力和四边 `-1` 的牌，排除来源且不消耗来源内力，最后攻击；零内力广播无效果但仍尝试攻击。
11. 生产一致性：原生完整规则、动作生成/应用、状态复制、状态键、搜索契约和控制器集成测试通过；原生库重新编译后运行全套 `tools/run_tests.ps1`。

完成自动测试后，以静音方式在 portrait 视口实际走一遍至少一个主动指定、一个结束阶段、一个进场前和一个翻面后场景，再宣告功能完成。
