# 2026-09-06 玉碎昆冈 3–4 设计

## 范围与时点

实装目录新增的 `YuSuiKunGang3`、`YuSuiKunGang4`。目录文字中的“我被移除时”
统一落在 `CARD_BEFORE_EXILED`，不是移除完成后的 `CARD_AFTER_EXILED`。

- 进场换位只在进场后恰有一个相邻敌方时发动；其它相邻友方不计入数量。
- “回合开始和结束时”指任意一方的回合开始与回合结束，各减一次点数。
- 两条标记为“锁定”的能力均设置 `retained_on_flip = true`；进场换位不保留。
- 移除前翻面按棋盘 `0 → 8` 快照所有当时相邻牌，并在每张结算前重新检查相邻条件。
  每张牌都翻为其当前所属方的敌方，且照常经过防止翻面与翻面触发流程。
- 三级完成相邻翻面后，将精确触发实例变成 `BaGuaFangWei`，从当时位置暂离，
  再在该位置以移除前所属方的敌方身份重新进场。实例 ID 不变；重进场走完整进场流程和
  标准攻击。所属方已改变，所以外层原移除请求在重检时自然失效，不产生
  `card_exiled`。

## 通用原语扩展

新增所属方引用：

```gdscript
const OWNER_OPPONENT_OF_CARD_CURRENT := &"opponent_of_card_current_owner"
```

`ACTION_FLIP_SELF.new_owner` 接受该引用，表示把当前动作主体翻为其结算时当前所属方的
敌方。它用于批量翻面时逐张计算所属方，不能用能力来源方替代。

`ACTION_SUMMON_CARD` 新增可选顶层 `owner`。省略时仍以能力来源方进场；声明时按该
所属方引用决定实际进场方。若精确卡牌引用刚在同一动作链中由
`ACTION_DEPART_CARD_FOR_RESUMMON` 暂离，`ACTION_SUMMON_CARD` 可以令该同一实例重新
进场；成功后消费暂离记录，不能重复召唤。

## 完整目录声明

### 共通进场换位

```gdscript
const YUSUI_SWAP_SINGLE_ADJACENT_ENEMY := {
    "triggers": [{
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
    }],
}
```

### 共通回合边界减点

```gdscript
const YUSUI_TURN_BOUNDARY_DECAY := {
    "retained_on_flip": true,
    "triggers": [
        {
            "event": TRIGGER_START_OWNER_TURN,
            "actions": [{
                "type": ACTION_CHANGE_POWERS,
                "amount": -1,
                "card": CARD_REF_ABILITY_SOURCE,
            }],
        },
        {
            "event": TRIGGER_END_OWNER_TURN,
            "actions": [{
                "type": ACTION_CHANGE_POWERS,
                "amount": -1,
                "card": CARD_REF_ABILITY_SOURCE,
            }],
        },
    ],
}
```

### 四级移除前翻相邻牌

```gdscript
const YUSUI_FLIP_ADJACENT_BEFORE_EXILE := {
    "retained_on_flip": true,
    "triggers": [{
        "event": CARD_BEFORE_EXILED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{
            "type": ACTION_FOR_EACH_SELECTED_CARD,
            "selector": {
                "zones": [CARD_ZONE_BOARD],
                "conditions": [{"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE}],
            },
            "actions": [{
                "type": ACTION_FLIP_SELF,
                "new_owner": OWNER_OPPONENT_OF_CARD_CURRENT,
            }],
        }],
    }],
}
```

### 三级移除前翻面并变身重进场

```gdscript
const YUSUI_FLIP_ADJACENT_AND_REBIRTH_BEFORE_EXILE := {
    "retained_on_flip": true,
    "triggers": [{
        "event": CARD_BEFORE_EXILED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [
            {
                "type": ACTION_FOR_EACH_SELECTED_CARD,
                "selector": {
                    "zones": [CARD_ZONE_BOARD],
                    "conditions": [{"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE}],
                },
                "actions": [{
                    "type": ACTION_FLIP_SELF,
                    "new_owner": OWNER_OPPONENT_OF_CARD_CURRENT,
                }],
            },
            {
                "type": ACTION_TRANSFORM_CARD,
                "card": CARD_REF_TRIGGER_CARD,
                "card_id": &"BaGuaFangWei",
            },
            {
                "type": ACTION_DEPART_CARD_FOR_RESUMMON,
                "card": CARD_REF_TRIGGER_CARD,
                "on_invalid_context": STOP_RULE,
            },
            {
                "type": ACTION_SUMMON_CARD,
                "card": CARD_REF_TRIGGER_CARD,
                "cell": {
                    "type": CELL_REF_INITIAL_CARD_CELL,
                    "card": CARD_REF_TRIGGER_CARD,
                },
                "owner": OWNER_OPPONENT_OF_ABILITY_SOURCE,
            },
        ],
    }],
}
```

### 两张牌的完整能力数组

```gdscript
&"YuSuiKunGang3": {
    # 其它目录字段保持当前定义。
    "abilities": [
        YUSUI_SWAP_SINGLE_ADJACENT_ENEMY,
        YUSUI_TURN_BOUNDARY_DECAY,
        YUSUI_FLIP_ADJACENT_AND_REBIRTH_BEFORE_EXILE,
    ],
}

&"YuSuiKunGang4": {
    # 其它目录字段保持当前定义。
    "abilities": [
        YUSUI_SWAP_SINGLE_ADJACENT_ENEMY,
        YUSUI_TURN_BOUNDARY_DECAY,
        YUSUI_FLIP_ADJACENT_BEFORE_EXILE,
    ],
}
```
