# 抱残守缺与礼敬如来能力设计

日期：2026-08-24

## 范围

实装以下少林派卡牌的完整卡面能力：

- `BaoCanShouQue2`、`BaoCanShouQue3`、`BaoCanShouQue4`
- `LiJingRuLai3`、`LiJingRuLai4`

规则继续由 `DuelSimulator`、`DuelTriggers` 与
`DuelAbilityExecutor` 统一结算；`DuelController` 只消费既有的弃牌、
点数变化、移除、召唤、攻击和翻面事件，不新增卡名分支。

最新目录提交中 `ALL_CARD_IDS` 的 `SanRuDiYu2` 与 `SanRuDiYu3` 项缺少
结尾逗号，已使目录脚本无法解析。实施时只补齐这两个逗号，不改变三入地狱
系列的能力或数据。

## 通用原语

新增以下卡牌无关声明词汇：

```gdscript
const ACTION_IF: StringName = &"if"
const CONDITION_SOURCE_OWNER_HAND_EMPTY: StringName = &"source_owner_hand_empty"
const CARD_REF_ATTACKER_CARD: StringName = &"attacker_card"
```

`ACTION_IF` 在轮到该 action 执行时重新检查其 `conditions`。全部满足才依次
执行嵌套 `actions`；条件不满足返回 `NO_EFFECT`，外层规则继续。条件只检查
一次，进入嵌套 actions 后不因后续状态变化重新检查。

`CONDITION_SOURCE_OWNER_HAND_EMPTY` 使用能力来源在本次规则开始时保存的所属方；
即使来源已被移除，仍检查该所属方当前的手牌。这样可以在完整移除连锁结束后
得到准确结果。

`CARD_REF_ATTACKER_CARD` 从攻击上下文的 `attacker_instance_id` 建立与现有卡牌
引用相同的快照。它可供移除、初始位置引用、复制等现有通用 action 使用。
上下文不存在攻击者时，引用解析为无效果。

目录验证必须接受并递归验证 `ACTION_IF.conditions`、`ACTION_IF.actions` 与新的
卡牌引用；未知字段、未知条件和非法嵌套继续报错。搜索层不识别卡牌 ID，
只通过模拟后的通用状态和事件评估结果。

## 共同进场弃牌能力

`BaoCanShouQue2`–`4` 与 `LiJingRuLai3` 使用同一能力：

```gdscript
{
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{
            "type": ACTION_FOR_EACH_SELECTED_CARD,
            "selector": {
                "zones": [CARD_ZONE_HAND],
                "conditions": [{"type": CONDITION_SELECTED_CARD_IS_ALLY}],
                "limit": 1,
            },
            "actions": [
                {"type": ACTION_DISCARD_CARD, "card": CARD_REF_SELECTED_CARD},
                {
                    "type": ACTION_CHANGE_POWERS,
                    "amount": 2,
                    "card": CARD_REF_ABILITY_SOURCE,
                },
            ],
        }],
    }],
}
```

手牌按现有物理槽位从左到右选择。没有手牌时不弃牌、不加点；成功弃掉一张
后自身四边各加二。弃牌使用现有渐隐动画，右侧手牌沿用现有集体左移事件，
随后再展示点数变化。

`LiJingRuLai4` 使用两个连续的单牌选择器。第一个只丢弃当前最左手牌；
第二个丢弃新的最左手牌，并在成功后令来源四边各加三。因此：

- 手牌为零：不弃牌、不加点。
- 手牌为一：弃掉这一张，不加点。
- 手牌至少为二：依次弃掉最左两张，然后加三点。

## 翻面被阻止后的移除

`BaoCanShouQue3`、`BaoCanShouQue4` 与 `LiJingRuLai4` 各自声明独立的锁定
能力：

```gdscript
{
    "retained_on_flip": true,
    "triggers": [{
        "event": CARD_FLIP_PREVENTED,
        "conditions": [{"type": CONDITION_ATTACKER_CARD_IS_SELF}],
        "actions": [
            {"type": ACTION_EXILE_CARD, "card": CARD_REF_TRIGGER_CARD},
        ],
    }],
}
```

只有该牌作为攻击者、且一次已经成立的翻面被显式阻止时触发。目标按
`instance_id` 追踪到当前格并真正进入其最初所属方的移除区；目标已经离场时
无效果。普通攻击因目标移走或其它失效原因未发生翻面，不算“翻面被阻止”。

## 抱残守缺的被攻击能力

`BaoCanShouQue2` 与 `BaoCanShouQue3` 声明：

```gdscript
{
    "retained_on_flip": true,
    "triggers": [{
        "event": CARD_BE_ATTACKED,
        "conditions": [{"type": CONDITION_ATTACKED_CARD_IS_SELF}],
        "actions": [
            {"type": ACTION_EXILE_CARD, "card": CARD_REF_ABILITY_SOURCE},
            {"type": ACTION_EXILE_CARD, "card": CARD_REF_ATTACKER_CARD},
        ],
    }],
}
```

`CARD_BE_ATTACKED` 只在攻击最初通过范围、阵营和点数检查并发出
`attack_started` 后发生。先完整移除抱残守缺，再完整移除攻击者；双方均进入
各自最初所属方的移除区。攻击随后因实例离场而结束，不翻面。

`BaoCanShouQue4` 在上述两次移除后追加：

```gdscript
{
    "type": ACTION_IF,
    "conditions": [{"type": CONDITION_SOURCE_OWNER_HAND_EMPTY}],
    "actions": [
        {
            "type": ACTION_SUMMON_CARD,
            "card": {
                "type": CARD_SPEC_FRESH_COPY,
                "of": CARD_REF_ABILITY_SOURCE,
            },
            "cell": {
                "type": CELL_REF_INITIAL_CARD_CELL,
                "card": CARD_REF_ABILITY_SOURCE,
            },
        },
        {
            "type": ACTION_SUMMON_CARD,
            "card": {
                "type": CARD_SPEC_FRESH_COPY,
                "of": CARD_REF_ABILITY_SOURCE,
            },
            "cell": {
                "type": CELL_REF_INITIAL_CARD_CELL,
                "card": CARD_REF_ATTACKER_CARD,
            },
        },
    ],
}
```

手牌为空条件在双方所有移除前事件与连锁动作结算完后检查。若移除过程抽到了
牌，则不生成复制。条件成立后只检查这一次：先在抱残守缺原格生成全新的
`BaoCanShouQue4` 实例并完整结算进场触发与标准攻击，再尝试在攻击者原格生成
第二个全新实例。第一张的连锁使第二格不再为空时，第二次召唤无效果。两张
复制的当前所属方与被移除的抱残守缺一致，实例 ID 各自全新。

## 测试与验收

新增聚焦模拟器测试覆盖：

- 五张卡的精确 declaration、锁定标记和能力条目分离。
- 物理最左手牌选择、弃牌事件、手牌左移与加点顺序。
- `LiJingRuLai4` 在零张、一张、两张及更多手牌下的结果。
- 只有显式 `CARD_FLIP_PREVENTED` 且攻击者为自身时才移除目标。
- 抱残守缺只在真实攻击成立后移除双方，弱攻击不触发。
- 双方移除的事件顺序、原所属方移除区和攻击终止。
- 四阶在移除连锁抽牌后不生成；手牌仍空时按两个原格依次完整召唤。
- 第一张复制占据第二格时第二次召唤安全无效果。
- 新实例、独立实例 ID、进场触发、标准攻击及二十次攻击上限仍生效。
- 新通用 action、condition、card reference 的目录验证与状态复制行为。

表现层复用现有事件，不新增专用视觉。完成后运行聚焦目录、模拟器和集成测试，
再运行一次完整测试套件，并在 540×960 生产对局中实际走查弃牌、加点、移除、
复制进场和攻击链。
