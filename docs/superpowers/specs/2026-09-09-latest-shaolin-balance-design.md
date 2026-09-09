# 易筋神功四与无相劫指四目录改动设计

日期：2026-09-09

## 范围

实装目录提交 `878afe9`、`9ca2722` 与 `b4e2983` 中的最新平衡调整：

- 新增四阶卡 `YiJJ4`（易筋神功）。
- 玄慈的卡组改用 `YiJJ4` 与 `WuXiangJieZhi3`。
- `WuXiangJieZhi4` 的起始内力改为 3；其“弃牌后攻击”改为先消耗
  1 点内力，无法支付时不攻击。

本次只使用既有通用目录原语，不增加 C++ opcode，不在规则、搜索或界面中加入
具体卡牌 ID 分支。

## 易筋神功四

`YiJJ4` 复用现有进场后能力：

```gdscript
const YIJIN_AFTER_SUMMONED: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [
            {"type": CONDITION_TRIGGER_CARD_IS_SELF},
        ],
        "actions": YIJIN_STRENGTHEN_HAND_ACTIONS,
    }],
}

const YIJIN_STRENGTHEN_HAND_ACTIONS: Array[Dictionary] = [
    {
        "type": ACTION_FOR_EACH_SELECTED_CARD,
        "selector": {
            "zones": [CARD_ZONE_HAND],
            "conditions": [
                {"type": CONDITION_SELECTED_CARD_IS_ALLY},
                {"type": CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE},
            ],
        },
        "actions": [
            {
                "type": ACTION_CHANGE_POWERS,
                "amount": 1,
                "card": CARD_REF_SELECTED_CARD,
            },
        ],
        "power_change_batch_group": YIJIN_HAND_BATCH,
    },
    {
        "type": ACTION_FOR_EACH_SELECTED_CARD,
        "selector": {
            "zones": [CARD_ZONE_HAND],
            "conditions": [
                {"type": CONDITION_SELECTED_CARD_IS_ALLY},
            ],
        },
        "actions": [
            {
                "type": ACTION_GAIN_KI,
                "amount": 1,
                "card": CARD_REF_SELECTED_CARD,
            },
        ],
    },
    {"type": ACTION_DRAW_CARDS, "amount": 1},
]
```

两个选择器分别在各自动作开始时读取当前友方手牌实例。所有旧手牌依次获得一点数和一点
内力，随后才抽一张牌；新抽到的牌不接受本次强化。四边均为 `-1` 的无点数牌
跳过点数变化，但仍获得 1 点内力。点数变化继续使用既有批次动画。

`YiJJ4` 不声明 `YIJIN_RETURNED_TO_ORIGINAL`，因此翻回最初一方时不会再次强化或
抽牌。

卡牌目录声明保持为：

```gdscript
&"YiJJ4": {
    "id": &"YiJJ4",
    "glyph": "易筋神功",
    "picture": "res://pics/LKT010_082.png",
    "sect": "少林派",
    "tier": 4,
    "weapon": "心法",
    "description": "进场后，所有手牌加一点数和内力，抽一张牌。",
    "powers": [3, 3, 3, 3],
    "abilities": [YIJIN_AFTER_SUMMONED],
}
```

## 无相劫指四

弃牌批次完成后的独立锁定能力调整为：

```gdscript
const WUXIANG_LOCKED_ATTACK_AFTER_DISCARD_BATCH: Dictionary = {
    "retained_on_flip": true,
    "triggers": [{
        "event": TRIGGER_DISCARD_BATCH_FINISHED,
        "conditions": [
            {"type": CONDITION_DISCARD_OWNER_IS_SELF},
            {"type": CONDITION_KI_AT_LEAST, "amount": 1},
        ],
        "actions": [
            {
                "type": ACTION_SPEND_KI,
                "amount": 1,
                "on_invalid_context": STOP_RULE,
            },
            {"type": ACTION_STANDARD_ATTACK_WITH_SELF},
        ],
    }],
}
```

条件在触发结算前检查能力来源的当前内力。至少有 1 点时，先扣除 1 点，再发起
一次标准攻击；不足时整条触发不进入动作阶段。`STOP_RULE` 作为结算中的防御性
保护：若条件通过后被更早的同批触发耗尽内力，本条只停止自身后续攻击，不回滚
已经发生的其它效果。

该能力继续在整个弃牌批次结束后只触发一次，而不是每弃一张牌触发一次；翻面
保留规则不变。主动弃牌能力本身仍另付 1 点内力，若它造成自己的弃牌后攻击，
两项费用分别支付。

## 敌人卡组

玄慈卡组按目录改为：

```gdscript
[
    &"YiKongDaoDi4",
    &"YiJJ4",
    &"SanRuDiYu1",
    &"WuXiangJieZhi3",
    &"LiJingRuLai4",
]
```

只更新目录及目录测试，不增加敌人专用规则。

## 测试与导出

实施前完整基线已通过 78 个套件。实施后新增或更新以下回归覆盖：

- `YiJJ4` 可被目录、门派和敌人卡组正常引用。
- `YiJJ4` 只强化进场前已有手牌，随后抽牌；无点数牌只增加内力。
- `WuXiangJieZhi4` 有内力时扣除 1 点并攻击，无内力时不攻击。
- 批量弃牌只产生一次付费攻击；多个来源仍按场上行优先顺序结算，并各自支付。
- 主动弃牌的费用和弃牌后攻击费用分别支付。

聚焦测试通过后运行完整测试套件。Android 导出前重新编译 ARM64 Release 原生库，
检查 Android preset 与签名配置，并生成现有项目约定的 Android Release APK；测试
与导出过程使用 Dummy 音频或保持无可听播放。
