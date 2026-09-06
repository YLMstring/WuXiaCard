# 2026-09-06 卡牌目录平衡调整与悔棋设计

## 范围

本次实现当前目录中三组尚未落地的改动：

- 寒冰真气的指定减点统一为四边 `-4`；
- 剑发琴音 1–3 进场后先抽一张牌，再独立判断是否移动；
- 来鹤清泉 1–4 按当前文本重组能力，并在玩家初始五张主卡组携带时开放悔棋。

## 目录声明

### 寒冰真气 3–4

沿用 `HANBIN_ACTIVATION`：

```gdscript
{
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
            {"type": ACTION_REVEAL_CARD, "card": CARD_REF_SELECTED_CARD},
        ],
    },
}
```

四边 `-1` 的特殊牌仍可被主动指定和揭示，但减点无效。

### 剑发琴音 1–3

抽牌与移动必须是两个能力条目，保证抽牌不受移动条件影响：

```gdscript
const JIANFA_ENTRY_DRAW := {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{"type": ACTION_DRAW_CARDS, "amount": 1}],
    }],
}

const JIANFA_ENTRY_MOVE := {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [
            {"type": CONDITION_TRIGGER_CARD_IS_SELF},
            {"type": CONDITION_SOURCE_HAS_EMPTY_BETWEEN_ENEMY},
        ],
        "actions": [{"type": ACTION_MOVE_SELF_TO_FIRST_EMPTY_BETWEEN_ENEMY}],
    }],
}
```

目录顺序为先 `JIANFA_ENTRY_DRAW`、后 `JIANFA_ENTRY_MOVE`。2 级再追加
`JIANFA_ACTIVATION`；3 级在移动能力后追加 `JIANFA_MOVE_SUPPRESSION` 和
`JIANFA_ACTIVATION`。

### 来鹤清泉 1–4

顶层元数据声明：

```gdscript
"main_deck_effects": [MAIN_DECK_EFFECT_UNDO_LAST_PLAYER_DECISION]
```

只有玩家开局实际携带的五张主卡组牌参与检查；牌在对局中位于手牌、场上、
弃牌区或移除区均不影响资格。1 级无局内能力；2 级只有翻面保护；3 级按顺序为
揭示当前敌方手牌、翻面保护；4 级按顺序为揭示当前敌方手牌、揭示后续敌方抽牌、
翻面保护。5 级岱宗如何保持现有声明，且不提供悔棋。

三个可复用能力条目为：

```gdscript
const LAIHE_REVEAL_CURRENT_HAND := {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{
            "type": ACTION_REVEAL_HAND_CARDS,
            "recipient": RECIPIENT_OPPONENT,
            "filter": REVEAL_FILTER_ALL,
        }],
    }],
}

const LAIHE_REVEAL_FUTURE_DRAWS := {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{
            "type": ACTION_ENABLE_FUTURE_DRAW_REVEAL,
            "recipient": RECIPIENT_OPPONENT,
        }],
    }],
}

const LAIHE_FLIP_PROTECTION := {
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
```

## 悔棋边界

玩家每次提交一个合法行动前保存一个检查点。检查点包含完整 `DuelState`、当时的
回放动作数量和熟练度候选列表。若之后敌方已经行动，仍回到该玩家行动之前，因此
敌方回应和连锁额外出牌一并撤回。

悔棋仅可在未结束对局的玩家决策阶段触发；结算中、敌方行动中、查看卡牌时、回放中
和终局后均不可触发。成功悔棋后消费当前检查点；玩家再次行动会建立新的检查点，
整局不设次数上限。恢复使用静态重建，不播放倒放动画。

左侧按钮优先级为：终局时播放回放；玩家决策阶段且有合法悔棋检查点时悔棋；其它
进行中状态沿用查看敌方上一张手牌出牌的功能。回放记录同步截断，熟练度候选同步
恢复；`DuelState` 内的上一张手牌记录也随检查点自然恢复。

