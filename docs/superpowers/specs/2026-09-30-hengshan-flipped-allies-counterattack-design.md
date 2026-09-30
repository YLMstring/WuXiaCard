# 恒山派共通反击：逐一攻击本次被翻面的友方

## 目标与范围

把恒山派共通能力的文字统一改为：

> 敌方攻击后，若本次攻击中有友方被翻面，我对这些被翻面的牌发起攻击，若如此做，失去此效果。

受影响的是 `TianChangZhang4`、`HenShanJianZhen2/3/4`、`JinZhenDuJie3/4`、`MianLiCangZhen2/3` 的描述，以及这些牌自带或授予的同一份 `HENGSHAN_COUNTERATTACK`。不修改其它攻击、翻面、能力授予规则。

## 结算语义

1. 只统计敌方本次攻击本身直接翻面的原友方牌；由攻击中的其它能力连锁翻面的牌不进入 `attack_flips`，沿用现有口径。
2. 在敌方整次攻击结束后，用当前棋盘状态确定反击目标。目标须仍为敌方、仍在场，并在反击者当前的标准攻击范围内，且符合正常攻击的点数/目标策略。攻击仍使用正常点数比较、免疫、翻面和事件结算，不越过距离限制。
3. 按当前棋盘格 `0..8` 的顺序，对符合条件的牌逐一发起**定向**攻击。每张被翻面的牌最多选中一次；不会把反击扩大成一次覆盖其它敌牌的普通攻击。选择时快照实例，每击前复验；目标随后离场、换位、易主或不再可攻击时跳过，不补选其它牌。
4. 没有一张牌能进入攻击结算时，不消耗此能力。首次确实能够发起定向攻击时，先移除此能力，再发动第一击，以阻止攻击连锁重复触发；余下目标继续处理。实际翻面成功不是消耗条件。若攻击在进入结算后被防护效果阻止，能力仍已消耗。
5. 反击者在敌方攻击中自己被翻面时，按现有翻面失去能力的规则处理，不保留额外的反击机会。多个反击者仍按现有事件发现和逐个复验顺序结算，各自只攻击当时仍符合条件的目标。

## 两种方案与选择

- **采用：扩展现有通用组合。** `ACTION_FOR_EACH_SELECTED_CARD` 用现有攻击记录选择目标，扩展选择条件以表达“本次从我方翻走”、扩展攻击可行性筛选及 `ACTION_STANDARD_ATTACK_WITH_CARD` 的可选定向目标。目录能完整表达多目标顺序和一次性消耗，现有普通攻击实现继续负责攻防结算。
- 专用 `ACTION_COUNTERATTACK_FLIPPED_ALLIES` 可以把筛选与消耗封装在一次 C++ 动作中，但会把一种卡牌效果固化成新原语，重复已有选择器及攻击流程。此处不采用。

新增的筛选只在匹配 `CARD_AFTER_ATTACK` 且存在原友方翻面记录时检查固定 9 格棋盘；不能给普通攻击目标查询或全局事件发现增加无条件扫描。新增的可选字段保持旧目录声明及旧卡牌行为不变。

## 目录原语声明

新增 `CONDITION_ATTACK_FLIPPED_ALLY` 作为廉价触发前置条件，只看 `attack_flips` 是否有 `previous_owner` 等于能力来源所属方的记录，不检查范围或点数。保留旧 `CONDITION_ATTACK_FLIPPED_ALLY_IN_RANGE` 给其它既有声明；它按基础范围判断，不能替代这里的完整标准攻击策略（其中可能含动态范围修正）。

扩展 `CONDITION_SELECTED_CARD_FLIPPED_BY_CURRENT_ATTACK`：无额外字段时保持原有“本次攻击翻面的原敌方”语义；带 `"previous_owner": OWNER_ABILITY_SOURCE` 时匹配 `attack_flips` 中 `previous_owner` 等于能力来源所属方的同一实例。新增 `CONDITION_SELECTED_CARD_CAN_BE_ATTACKED_BY_SOURCE`，按当前标准攻击策略判断能力来源是否能对所选牌发起攻击，包括范围、目标所属方和现有“点数不足仍可尝试”的修正效果。扩展 `ACTION_STANDARD_ATTACK_WITH_CARD`：可选 `"target": CARD_REF_SELECTED_CARD`，此时以 `"card"` 指定的牌为攻击者，锁定所选实例与当前格，走原有定向攻击流程；省略 `target` 时维持原标准攻击。

完整共通能力声明如下。它没有 `retained_on_flip`、`modifiers`、`activation`、`costs` 或批次元数据；攻击失效时不设置 `STOP_RULE`，由筛选与逐项复验跳过：

```gdscript
const HENGSHAN_COUNTERATTACK: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_ATTACK,
        "conditions": [
            {"type": CONDITION_ATTACKER_CARD_IS_ENEMY},
            {"type": CONDITION_ATTACK_FLIPPED_ALLY},
        ],
        "actions": [{
            "type": ACTION_FOR_EACH_SELECTED_CARD,
            "selector": {
                "zones": [CARD_ZONE_BOARD],
                "conditions": [
                    {"type": CONDITION_SELECTED_CARD_IS_ENEMY},
                    {"type": CONDITION_SELECTED_CARD_FLIPPED_BY_CURRENT_ATTACK,
                     "previous_owner": OWNER_ABILITY_SOURCE},
                    {"type": CONDITION_SELECTED_CARD_CAN_BE_ATTACKED_BY_SOURCE},
                ],
            },
            "actions": [
                {"type": ACTION_REMOVE_THIS_ABILITY},
                {"type": ACTION_STANDARD_ATTACK_WITH_CARD,
                 "card": CARD_REF_ABILITY_SOURCE,
                 "target": CARD_REF_SELECTED_CARD},
            ],
        }],
    }],
}
```

## 受影响卡牌的完整 `abilities` 声明

以下是八张牌目标目录的精确能力数组。`TIANCHANG_SUMMON_POWER`、`JINZHEN_RETURN`、`MIANLI_RESUMMON` 均保持现状，但在此列出完整声明以说明顺序；除共通反击以外的剑阵能力也不改变。

```gdscript
const TIANCHANG_SUMMON_POWER: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
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
                "type": ACTION_CHANGE_POWERS,
                "amount": 1,
                "card": CARD_REF_ABILITY_SOURCE,
            }],
        }],
    }],
}

const JINZHEN_RETURN: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{
            "type": ACTION_FOR_EACH_SELECTED_CARD,
            "selector": {
                "zones": [CARD_ZONE_BOARD],
                "conditions": [
                    {"type": CONDITION_SELECTED_CARD_IS_ENEMY},
                    {"type": CONDITION_SELECTED_CARD_ORIGINAL_OWNER_IS_SELF},
                ],
                "limit": 1,
            },
            "actions": [{
                "type": ACTION_RETURN_CARD_TO_HAND,
                "card": CARD_REF_SELECTED_CARD,
                "recipient": OWNER_ABILITY_SOURCE,
            }],
        }],
    }],
}

const MIANLI_RESUMMON: Dictionary = {
    "triggers": [{
        "event": CARD_AFTER_FLIPPED,
        "conditions": [
            {"type": CONDITION_ATTACKER_CARD_IS_SELF},
            {"type": CONDITION_TRIGGER_CARD_ORIGINAL_OWNER_IS_SELF},
        ],
        "actions": [{
            "type": ACTION_RESUMMON_CARD_IN_PLACE,
            "card": CARD_REF_TRIGGER_CARD,
        }],
    }],
}

TianChangZhang4["abilities"] = [TIANCHANG_SUMMON_POWER, HENGSHAN_COUNTERATTACK]
JinZhenDuJie3["abilities"] = [JINZHEN_RETURN, HENGSHAN_COUNTERATTACK]
JinZhenDuJie4["abilities"] = [JINZHEN_RETURN, HENGSHAN_COUNTERATTACK]
MianLiCangZhen2["abilities"] = [HENGSHAN_COUNTERATTACK]
MianLiCangZhen3["abilities"] = [MIANLI_RESUMMON, HENGSHAN_COUNTERATTACK]

HenShanJianZhen2["abilities"] = [{
    "triggers": [{
        "event": TRIGGER_END_OWNER_TURN,
        "conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
        "actions": [
            {"type": ACTION_GRANT_ABILITY_TO_SELF,
             "ability": HENGSHAN_COUNTERATTACK},
            {"type": ACTION_FOR_EACH_SELECTED_CARD,
             "selector": {
                 "zones": [CARD_ZONE_BOARD],
                 "conditions": [
                     {"type": CONDITION_SELECTED_CARD_IS_ALLY},
                     {"type": CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
                     {"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
                 ],
             },
             "actions": [{"type": ACTION_GRANT_ABILITY_TO_SELF,
                          "ability": HENGSHAN_COUNTERATTACK}]},
        ],
    }],
}]

HenShanJianZhen3["abilities"] = [{
    "triggers": [{
        "event": TRIGGER_END_OWNER_TURN,
        "conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
        "actions": [{
            "type": ACTION_FOR_EACH_SELECTED_CARD,
            "selector": {
                "zones": [CARD_ZONE_BOARD],
                "conditions": [{"type": CONDITION_SELECTED_CARD_IS_ALLY}],
            },
            "actions": [{"type": ACTION_GRANT_ABILITY_TO_SELF,
                         "ability": HENGSHAN_COUNTERATTACK}],
        }],
    }],
}]

HenShanJianZhen4["abilities"] = [
    {"triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{
            "type": ACTION_FOR_EACH_SELECTED_CARD,
            "selector": {
                "zones": [CARD_ZONE_BOARD],
                "conditions": [
                    {"type": CONDITION_SELECTED_CARD_IS_ENEMY},
                    {"type": CONDITION_SELECTED_CARD_SURROUNDED_BY_ALLIES},
                ],
            },
            "actions": [{"type": ACTION_FLIP_SELF,
                         "new_owner": OWNER_ABILITY_SOURCE}],
        }],
    }]},
    {"triggers": [{
        "event": TRIGGER_END_OWNER_TURN,
        "conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
        "actions": [{
            "type": ACTION_FOR_EACH_SELECTED_CARD,
            "selector": {
                "zones": [CARD_ZONE_BOARD],
                "conditions": [{"type": CONDITION_SELECTED_CARD_IS_ALLY}],
            },
            "actions": [{"type": ACTION_GRANT_ABILITY_TO_SELF,
                         "ability": HENGSHAN_COUNTERATTACK}],
        }],
    }]},
]
```

八张牌的 `description` 仅将旧句“敌方攻击后，若本次攻击中有在我攻击范围内的友方被翻面，我发起攻击，然后失去此效果。”逐字替换为本设计首节的新句；每张牌已有的其它描述、力量、武器、图像与风味文字不变。

## 验证

- 先补纯模拟器回归：一击翻多张牌时仅定向攻击可攻击的原友方；范围外、点数不足、被阻止翻面、连锁翻面、目标易主/换位/离场；没有可发起的攻击时保留能力；有攻击时只消耗一次；双方嵌套反击不重复。
- 检查授予型剑阵与自带型能力、目录校验、编译拒绝非法字段、金珠“护”的识别，以及每个定向攻击分别产生的纯数据事件。历史两类 `selected_card_flipped_by_current_attack` 用法必须保持旧行为。
- 原生 Release 构建后运行完整套件，再在静音、竖屏生产路径中走一次敌方多目标翻面与反击的可见流程。原生规则扩展进入搜索过渡路径，按仓库性能要求保留同机旧版与新版 Release 构建，用相同固定节点夹测；如有可重复退化，先报告。
