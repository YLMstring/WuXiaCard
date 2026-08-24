# 燃木刀法、一空到底与无相劫指能力设计

日期：2026-08-24

## 范围

实装以下少林派卡牌的完整能力：

- `RanMuDaoFa2`、`RanMuDaoFa3`
- `YiKongDaoDi4`、`YiKongDaoDi5`
- `WuXiangJieZhi3`、`WuXiangJieZhi4`

同时把 `LiJingRuLai4` 的两张牌支付迁移到新的通用批量弃牌路径。

规则继续以 `DuelSimulator` 为唯一权威路径。目录只声明通用事件、条件、
selector 和 action；模拟器、搜索及控制器不得按上述卡牌 ID 分支。

当前任务开始前工作区干净，上一轮完整测试套件已经通过。实施后仍须运行聚焦
测试和一次完整套件。

## 通用声明词汇

新增以下卡牌无关词汇：

```gdscript
const TARGET_ALLY_HAND_CARD: StringName = &"ally_hand_card"
const ACTION_DISCARD_CARDS: StringName = &"discard_cards"
const TRIGGER_DISCARD_BATCH_FINISHED: StringName = &"discard_batch_finished"
const CONDITION_DISCARD_OWNER_IS_SELF: StringName = &"discard_owner_is_self"
const CONDITION_LAST_DISCARD_BATCH_SIZE_AT_LEAST: StringName = (
    &"last_discard_batch_size_at_least"
)
const SELECT_ORDER_HAND_RIGHT_TO_LEFT: StringName = &"hand_right_to_left"
```

`TARGET_ALLY_HAND_CARD` 令场上的主动能力可以指定其当前所属方的一张手牌。
合法行动仍以目标的逻辑手牌索引储存，但界面高亮与拖放必须命中对应的固定物理
手牌槽；目标快照继续依靠 `instance_id`，不依赖视图子节点顺序。

selector 默认按物理手牌槽从左到右访问。仅在声明
`order = SELECT_ORDER_HAND_RIGHT_TO_LEFT` 时，手牌区改为从物理最右占用槽向左
访问。该顺序是通用 selector 数据，不得写成一空到底的卡名规则。

## 批量弃牌事务

通用批量声明形状为：

```gdscript
{
    "type": ACTION_DISCARD_CARDS,
    "selector": {
        "zones": [CARD_ZONE_HAND],
        "conditions": [{"type": CONDITION_SELECTED_CARD_IS_ALLY}],
    },
}
```

action 开始时完成一次 selector 快照，锁定仍合法的精确实例。所有锁定实例先
同时离开手牌并进入各自当前所属方的弃牌堆，之后才按锁定时的物理槽顺序逐张
结算它们各自的 `CARD_AFTER_DISCARDED`。结算期间抽到、返回或生成到手牌中的牌
不加入本批次；第一张弃牌的连锁开始时，同批其它牌已经位于弃牌区。

每张成功弃牌继续产生独立的 `card_discarded` 纯数据事件，但同批事件共享：

```gdscript
{
    "discard_batch_id": StringName,
    "discard_batch_size": int,
    "discard_batch_index": int,
}
```

同批牌移除后只计算一次存活手牌的最终物理槽位，并用一个
`hand_cards_shifted` 事件描述全部移动。控制器收集连续的同批弃牌事件，同时
播放现有渐隐动画；渐隐完成后再统一移动存活手牌。批次中每张牌的自身弃牌后
连锁仍按锁定顺序展示。

所有自身弃牌后连锁完成后，若本批至少成功弃掉一张牌，才全场发出一次
`TRIGGER_DISCARD_BATCH_FINISHED`。上下文至少包含：

```gdscript
{
    "discard_batch_id": StringName,
    "discard_owner_id": int,
    "discarded_instance_ids": Array[StringName],
    "discarded_count": int,
}
```

同一批次的牌必须来自同一所属方；目录验证拒绝无法保证这一点的 selector。
全场来源按格子 `0..8` 发现。`CONDITION_DISCARD_OWNER_IS_SELF` 比较批次所属方
与能力来源结算时的当前所属方。

现有 `ACTION_DISCARD_CARD` 自动作为大小为一的批次：先弃牌并结算该牌自身的
`CARD_AFTER_DISCARDED`，再发一次批次结束事件。批次中某张牌的连锁主动发起
另一项弃牌时，新弃牌属于一个独立的嵌套批次；内层批次完全结束后，外层才继续。

批次成功弃掉的数量写入当前规则上下文。后续 `ACTION_IF` 可以使用：

```gdscript
{
    "type": CONDITION_LAST_DISCARD_BATCH_SIZE_AT_LEAST,
    "amount": 2,
}
```

该值只在同一规则的下一项弃牌 action 覆盖它之前有效；不得写入 `DuelState`、
回放记录或永久卡牌状态。没有成功弃牌时不发批次事件，数量为零。

## 一空到底

`YiKongDaoDi4` 声明：

```gdscript
const YIKONG_EXILE_DISCARD_DRAW: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_BEFORE_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [
            {"type": ACTION_EXILE_SELF, "on_invalid_context": STOP_RULE},
            {
                "type": ACTION_DISCARD_CARDS,
                "selector": {
                    "zones": [CARD_ZONE_HAND],
                    "conditions": [{"type": CONDITION_SELECTED_CARD_IS_ALLY}],
                },
            },
            {"type": ACTION_DRAW_CARDS, "amount": 5},
        ],
    }],
}
```

牌在 `TRIGGER_CARD_BEFORE_SUMMONED` 中先真正进入其最初所属方的移除区。后续
动作使用规则开始时保存的来源所属方，因此即使来源已经离场，仍同时弃掉该方
当时剩余的全部手牌，完整结算弃牌连锁，再逐张尝试抽五张。空牌库和手牌容量
沿用现有抽牌规则。

因为来源在全场 `card_summoned` 前已经离场，本次打出不产生 `card_placed`、
全场进场、进场后或标准攻击。

`YiKongDaoDi5` 在上述抽牌后追加：

```gdscript
{
    "type": ACTION_DISCARD_CARDS,
    "selector": {
        "zones": [CARD_ZONE_HAND],
        "conditions": [{"type": CONDITION_SELECTED_CARD_IS_ENEMY}],
        "order": SELECT_ORDER_HAND_RIGHT_TO_LEFT,
        "limit": 1,
    },
}
```

目标是对手当前物理最右侧占用槽。对手空手时不弃牌、不发批次结束事件，之前
的一空效果保持完成。

## 燃木刀法

二至三级共用独立锁定主动能力：

```gdscript
const RANMU_LOCKED_ACTIVATION: Dictionary = {
    "retained_on_flip": true,
    "activation": {
        "input": ACTIVATION_DRAG_TO_TARGET,
        "target_rule": TARGET_ALLY_HAND_CARD,
        "costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
        "actions": [
            {
                "type": ACTION_DISCARD_CARD,
                "card": CARD_REF_SELECTED_CARD,
                "on_invalid_context": STOP_RULE,
            },
            {
                "type": ACTION_FOR_EACH_SELECTED_CARD,
                "selector": {
                    "zones": [CARD_ZONE_BOARD],
                    "conditions": [{"type": CONDITION_SELECTED_CARD_IS_ALLY}],
                },
                "actions": [{
                    "type": ACTION_CHANGE_POWERS,
                    "amount": 1,
                    "card": CARD_REF_SELECTED_CARD,
                }],
            },
            {"type": ACTION_GRANT_EXTRA_CARD_PLAY, "amount": 1},
        ],
    },
}
```

主动能力消耗一点内力并指定当前所属方的一张手牌。成功弃牌及其完整连锁之后，
场上所有当前友方（包含燃木刀法自身）四边同时加一；手牌不加点。随后获得一次
额外手牌出牌。目标失效时停止本条规则，不加点也不获得额外出牌；已支付的内力
不退还。

`RanMuDaoFa3` 另有独立、非锁定能力：

```gdscript
const RANMU_AFTER_ATTACK: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_ATTACK,
        "conditions": [{"type": CONDITION_ATTACKER_CARD_IS_SELF}],
        "actions": [{
            "type": ACTION_FOR_EACH_SELECTED_CARD,
            "selector": {
                "zones": [CARD_ZONE_BOARD],
                "conditions": [{"type": CONDITION_SELECTED_CARD_IS_ALLY}],
            },
            "actions": [{
                "type": ACTION_CHANGE_POWERS,
                "amount": 1,
                "card": CARD_REF_SELECTED_CARD,
            }],
        }],
    }],
}
```

沿用现有真实攻击定义：至少一个目标通过最初合法性和点数比较并发出
`attack_started` 才有攻击后事件。无目标或点数不足不加点。该能力不锁定，
翻面后失去。

## 无相劫指

三级和四级复用绕指柔剑已经使用的三种通用攻击修正器，并将共享常量重命名为
卡牌无关名称：

```gdscript
const LOCKED_FIRST_LEGAL_UNLIMITED_ATTACK: Dictionary = {
    "retained_on_flip": true,
    "modifiers": [
        {"type": MODIFIER_UNLIMITED_ATTACK_RANGE},
        {"type": MODIFIER_NON_ORTHOGONAL_ATTACK_ANY_AXIS},
        {"type": MODIFIER_STANDARD_ATTACK_FIRST_LEGAL_TARGET},
    ],
}
```

普通攻击开始时按格子 `0..8` 选择当时首个合法敌方，且只锁定这一张。非直线
目标只需两组彼此正对点数中至少一组满足正常攻击比较。目标随后在
`CARD_BE_ATTACKED` 中离场或变得不可攻击时，本次攻击结束，不顺延第二张；
移动不会因距离而使无限范围攻击失效。指定攻击不被该目标策略改写。

三级和四级另有独立锁定主动能力：

```gdscript
const WUXIANG_LOCKED_DISCARD_DRAW: Dictionary = {
    "retained_on_flip": true,
    "activation": {
        "input": ACTIVATION_DRAG_TO_TARGET,
        "target_rule": TARGET_ALLY_HAND_CARD,
        "costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
        "actions": [
            {
                "type": ACTION_DISCARD_CARD,
                "card": CARD_REF_SELECTED_CARD,
                "on_invalid_context": STOP_RULE,
            },
            {"type": ACTION_DRAW_CARDS, "amount": 1},
        ],
    },
}
```

弃牌自身连锁和一次批次结束事件全部完成后再抽一张。目标失效时不抽牌，已支付
内力不退还。

`WuXiangJieZhi4` 再增加独立锁定能力：

```gdscript
const WUXIANG_LOCKED_DISCARD_ATTACK: Dictionary = {
    "retained_on_flip": true,
    "triggers": [{
        "event": TRIGGER_DISCARD_BATCH_FINISHED,
        "conditions": [{"type": CONDITION_DISCARD_OWNER_IS_SELF}],
        "actions": [{"type": ACTION_STANDARD_ATTACK_WITH_SELF}],
    }],
}
```

所属方因任何来源成功弃牌都满足，包括燃木、无相自身、一空、礼敬如来和敌方
强制弃牌。单张弃牌攻击一次；任意大小的一个批次也只在全部自身连锁完成后攻击
一次。多张无相来源按格子 `0..8` 各攻击一次。无合法目标时不形成真实攻击，
仍遵守每方每回合最多二十次攻击的现有限制。

## 礼敬如来四级迁移

`LiJingRuLai4` 的进场能力改为：

```gdscript
const SHAOLIN_DISCARD_TWO_GAIN_THREE: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [
            {
                "type": ACTION_DISCARD_CARDS,
                "selector": {
                    "zones": [CARD_ZONE_HAND],
                    "conditions": [{"type": CONDITION_SELECTED_CARD_IS_ALLY}],
                    "limit": 2,
                },
            },
            {
                "type": ACTION_IF,
                "conditions": [{
                    "type": CONDITION_LAST_DISCARD_BATCH_SIZE_AT_LEAST,
                    "amount": 2,
                }],
                "actions": [{
                    "type": ACTION_CHANGE_POWERS,
                    "amount": 3,
                    "card": CARD_REF_ABILITY_SOURCE,
                }],
            },
        ],
    }],
}
```

开始时锁定当时物理最左两张并同时弃置。零张时无事发生；一张时弃掉该牌但
不加点；至少两张时只弃掉锁定的两张，完整结算它们的自身连锁和一次批次结束
事件，再令仍在场的礼敬如来四边各加三。无相劫指四级对这两张牌只响应一次。

## 展示

- 批量弃牌复用现有渐隐素材；同一批次所有牌同时渐隐。
- 同批弃牌之后只播放一次存活手牌的集体位移动画。
- 一空的抽牌继续逐张展示，并严格位于弃牌连锁之后。
- 燃木的多目标加点沿用现有共享停顿和同时加点动画。
- 无相的相邻攻击沿用墨痕；非相邻攻击沿用攻击者移动到目标上方再返回的动画。
- 不新增任何按卡牌 ID 选择动画的控制器逻辑。

## 测试与验收

目录与模拟器聚焦测试覆盖：

- 新 action、事件、条件、selector 顺序和己方手牌目标的合法/非法声明。
- 批量弃牌先原子移除全部锁定实例，再按物理左到右结算自身弃牌能力。
- 结算期间的新手牌不加入原批次；嵌套弃牌形成独立批次。
- 同批只发一次批次结束事件；零成功弃牌不发事件。
- 一空自移除后不进入任何后续召唤节点，随后批量弃牌并逐张抽五张。
- 一空五级只弃对手物理最右手牌；对手空手安全无效果。
- 燃木主动能力的目标、耗内力、弃牌、场上友方同时加点和额外出牌。
- 燃木三级只在真实攻击后加点，翻面后失去该非锁定能力。
- 无相三种攻击修正器、指定攻击不改目标、主动弃一抽一。
- 无相四级对单牌和整批各响应一次，敌方批次不响应，多来源按 `0..8`。
- 礼敬如来四级在零、一、二张及更多手牌下的弃牌、加点和无相触发次数。
- 所有攻击仍受每方每回合二十次上限约束。

展示集成测试覆盖同批弃牌同时渐隐、一次手牌位移，以及抽牌或无相攻击发生在
批次展示和规则连锁之后。实施完成后运行一次完整测试套件，并在 `540×960`
生产对局中走查主动指定、批量弃牌、抽牌、加点和远距离攻击。
