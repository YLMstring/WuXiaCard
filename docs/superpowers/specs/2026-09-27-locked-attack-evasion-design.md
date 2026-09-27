# 锁定攻击闪避：金雁功三／四、梯云纵三／四

## 规则

卡面文字统一改为“锁定：被攻击时，尝试移出攻击范围。”攻击开始后、翻面前，若本牌有相邻空格，则按棋盘格序 `0..8` 依次检查：优先移至第一个不在当前攻击者几何攻击范围内的相邻空格；若每个相邻空格仍在范围内，则移至首个相邻空格；没有相邻空格就不移动。二格攻击的遮挡检查以移动完成后的棋盘为准，因此本牌原格视为空格。行动是否翻面，由既有攻击流程在反应结束后重新检查目标范围决定；移入仍可被攻击的位置不会获得额外的翻面保护。非攻击导致的翻面不会触发闪避。该锁定能力翻面后保留。

扩展现有 `ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY` 的可选布尔字段 `prefer_outside_attacker_range`，默认缺省为 `false`，保留其他牌的首格移动行为。只有带该字段且有攻击者上下文时才计算安全空格；这项计算不进入普通移动或通用攻击查询的热路径。移动仍走现有 `move_card_between_cells`，发出原有移动事件。

## 完整能力声明

以下声明与 `scripts/card_catalog.gd` 中对应常量一致；未改的能力也完整列出，以固定受影响卡牌的能力顺序。

```gdscript
const LOCKED_ATTACK_EVASION: Dictionary = {
    "retained_on_flip": true,
    "triggers": [{
        "event": CARD_BE_ATTACKED,
        "conditions": [
            {"type": CONDITION_TRIGGER_CARD_IS_SELF},
            {"type": CONDITION_SOURCE_HAS_ADJACENT_EMPTY_CELL},
        ],
        "actions": [{
            "type": ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY,
            "prefer_outside_attacker_range": true,
        }],
    }],
}

const TIYUNZONG_RESUMMON_ACTIVATION: Dictionary = {
    "activation": {
        "input": ACTIVATION_DRAG_TO_TARGET,
        "target_rule": TARGET_OTHER_ALLY_BOARD,
        "costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
        "actions": [
            {"type": ACTION_DEPART_CARD_FOR_RESUMMON, "card": CARD_REF_SELECTED_CARD,
             "on_invalid_context": STOP_RULE},
            {"type": ACTION_DEPART_CARD_FOR_RESUMMON, "card": CARD_REF_ABILITY_SOURCE,
             "on_invalid_context": STOP_RULE},
            {"type": ACTION_SUMMON_CARD,
             "card": {"type": CARD_SPEC_FRESH_COPY, "of": CARD_REF_SELECTED_CARD},
             "cell": {"type": CELL_REF_INITIAL_CARD_CELL, "card": CARD_REF_ABILITY_SOURCE}},
            {"type": ACTION_SUMMON_CARD,
             "card": {"type": CARD_SPEC_FRESH_COPY, "of": CARD_REF_ABILITY_SOURCE},
             "cell": {"type": CELL_REF_INITIAL_CARD_CELL, "card": CARD_REF_SELECTED_CARD}},
            {"type": ACTION_SPEND_KI, "amount": 1, "card": CARD_REF_LAST_SUMMONED_CARD,
             "on_invalid_context": STOP_RULE},
            {"type": ACTION_GRANT_EXTRA_CARD_PLAY, "amount": 1,
             "card": CARD_REF_LAST_SUMMONED_CARD},
        ],
    },
}

const TIYUNZONG_DRAW_ON_ALLY_EFFECT_EXILE: Dictionary = {
    "triggers": [{
        "event": CARD_BEFORE_EXILED,
        "conditions": [{"type": CONDITION_EXILE_EFFECT_SOURCE_IS_ALLY}],
        "actions": [{"type": ACTION_DRAW_CARDS, "amount": 1}],
    }],
}

const QZ_JINYAN_END_TURN_NO_ENEMY_FLIP_DRAW: Dictionary = {
    "triggers": [{
        "event": TRIGGER_END_OWNER_TURN,
        "conditions": [
            {"type": CONDITION_TURN_OWNER_IS_SELF},
            {"type": CONDITION_ACTIVE_OWNER_DID_NOT_FLIP_ENEMY_THIS_TURN},
        ],
        "actions": [{"type": ACTION_DRAW_CARDS, "amount": 1}],
    }],
}

const QZ_JINYAN_ALLY_DRAW_GAIN_KI: Dictionary = {
    "triggers": [{
        "event": CARD_AFTER_DRAWN,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_ALLY}],
        "actions": [{"type": ACTION_GAIN_KI, "amount": 1,
                     "card": CARD_REF_TRIGGER_CARD}],
    }],
}

const QZ_SPEND_KI_TO_PREVENT_FLIP: Dictionary = {
    "triggers": [{
        "event": CARD_BEFORE_FLIPPED,
        "conditions": [
            {"type": CONDITION_TRIGGER_CARD_IS_SELF},
            {"type": CONDITION_TRIGGER_CARD_HAS_ADJACENT_ALLY},
            {"type": CONDITION_KI_AT_LEAST, "amount": 1},
        ],
        "actions": [
            {"type": ACTION_SPEND_KI, "amount": 1, "on_invalid_context": STOP_RULE},
            {"type": ACTION_PREVENT_TRIGGER_FLIP},
        ],
    }],
}

const QZ_JINYAN_ALLY_DRAW_GAIN_KI_AND_PROTECT: Dictionary = {
    "triggers": [{
        "event": CARD_AFTER_DRAWN,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_ALLY}],
        "actions": [
            {"type": ACTION_GAIN_KI, "amount": 1, "card": CARD_REF_TRIGGER_CARD},
            {"type": ACTION_GRANT_TRIGGER_CARD_ABILITY,
             "ability": QZ_SPEND_KI_TO_PREVENT_FLIP},
        ],
    }],
}

&"JinYanGong3": {"abilities": [
    LOCKED_ATTACK_EVASION,
    QZ_JINYAN_END_TURN_NO_ENEMY_FLIP_DRAW,
    QZ_JINYAN_ALLY_DRAW_GAIN_KI,
]}
&"JinYanGong4": {"abilities": [
    LOCKED_ATTACK_EVASION,
    QZ_JINYAN_END_TURN_NO_ENEMY_FLIP_DRAW,
    QZ_JINYAN_ALLY_DRAW_GAIN_KI_AND_PROTECT,
]}
&"TiYunZong3": {"abilities": [
    LOCKED_ATTACK_EVASION,
    TIYUNZONG_RESUMMON_ACTIVATION,
]}
&"TiYunZong4": {"abilities": [
    TIYUNZONG_DRAW_ON_ALLY_EFFECT_EXILE,
    LOCKED_ATTACK_EVASION,
    TIYUNZONG_RESUMMON_ACTIVATION,
]}
```

## 验证

定向模拟测试覆盖首个安全空格优先、二格攻击在原格腾空后仍可穿过、没有安全空格时首格回退且攻击继续、无空格时正常翻面、非攻击翻面不闪避，以及翻面后仍保留反应。对局场景集成用例验证真实控制器的移动呈现。完整测试套件通过 85 组。

保留变更前源码和对应的 Release 原生库，使用相同引擎、两个相同开局、每局一秒、`self_turn` 配置进行 A/B/A/B 对照。旧版两次为 11914.8、11951.7 节点／秒；新版两次为 12369.7、12432.9 节点／秒。两版在两局均完成深度二；开局状态摘要、首选动作、深度二分数（`-105082`、`195043`）和深度二节点数（`933`、`1324`）完全一致。该短时样本只用于筛查明显回退，不构成提速结论，也不能代表含本能力的局面。
