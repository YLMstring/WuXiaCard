# 古墓派三阶生成玉女无锋

状态：创作者已确认规则方案；待审核本文档后实施。本文档以 2026-09-28 的 `scripts/card_catalog.gd` 卡面文字为准，取代此前古墓派设计文档中三阶剑法的指定发动能力段落。其余古墓派规则仍以现行代码及原设计文档为准。

## 范围与行为

- `LangJiTianYa3`、`XiaoYuanYiJu3`、`LengYueKuiRen3` 去掉原有耗一内力、指定敌方减点并给予弃牌堆来源额外出牌的发动能力。它们不再拥有该发动入口，也不设置初始内力。各自的二次攻击尝试、点数不足减点和下一张手牌赋能照旧。
- 这三张牌每次进场时，若**当前拥有者**手中不存在 `card_id == YuNvWuFeng` 的牌，就用 `ACTION_ADD_CARD_TO_HAND` 获取一张全新的玉女无锋。检查目标拥有者的全部五个物理手牌槽，不按 `glyph`、品阶或来源判重。同一进场事件中按规则顺序执行；先生成的一张会让后续同类进场跳过。手牌已满时不添加，返回 `NO_EFFECT`，其它能力继续执行。没有延迟补牌或待生成状态。
- 新增的玉女无锋保持目录给出的六阶、四侧 `-1`、剑法和现有图片/文案。六阶按现有牌池与进阶规则自然处理，不另设衍生牌的奖励、解锁或牌池排除机制；测试可显式构造它。
- 玉女无锋的第一项锁定能力使**它自身**从手牌打出的那次结算视为弃牌堆来源。实体仍从手牌槽取走，仍消耗正常或额外出牌机会；沿用既有来源改写语义，不消费“下一张从手牌中打出”效果队列，不更新 `last_hand_play_by_owner`，也不消费只针对手牌来源的待失效层。来源改写仅在该牌被打出时检查这一张牌的现存锁定修饰，不全场扫描，也不按 `YuNvWuFeng` ID 硬编码。它不对之后的其它牌施加持久状态。
- 玉女无锋的第二项锁定能力在 `TRIGGER_CARD_SUMMONED` 响应自身进场：按选择器顺序逐个处理当时相邻且仍为敌方的牌，各使四侧点数减一，再**独立**尝试获得一次额外出牌。即使没有合法相邻敌方、所有减点都无效果或额外出牌已达本回合上限，额外出牌动作仍会尝试；现有 `TRIGGER_EXTRA_CARD_PLAY_GRANTED` 依然在每次尝试前触发。成功得到的那次机会取手牌实体牌，但按弃牌堆来源结算；机会没用掉时现有规则负责清除标记。四侧 `-1` 的特殊牌不能被减点，按现有点数规则跳过。
- 进场顺序保持当前模拟器生命周期：逻辑落位 → `CARD_BEFORE_SUMMONED` → `card_placed` → `CARD_SUMMONED`（三阶生成／玉女无锋减点和请求额外出牌）→ `CARD_AFTER_SUMMONED`（三阶原有下张手牌赋能等）→ 标准攻击 → 动作收尾。玉女无锋的 `-1` 点数按现有攻击比较规则处理，不添加专属攻击分支。翻面后两项锁定能力都保留；若测试人工强行移除了锁定能力，则不再额外保证对应效果。

## 方案选择与实现边界

推荐的路径仅扩展现有 `ACTION_ADD_CARD_TO_HAND`：可选 `only_if_absent: true` 仅在固定 `card_id` 用法合法，执行时在目标手牌中查找同 ID；不存在才创建新实例。默认行为完全不变。相比新建“手牌是否含某 ID”条件并以 `ACTION_IF` 包裹添牌，这次少改一条条件编译与执行路径，也不会为单一用例建立通用查询框架。直接在模拟器中识别玉女无锋 ID 虽可少写目录声明，但违反卡牌无关规则边界，不采用。

新增 `MODIFIER_HAND_PLAY_AS_DISCARD` 仅在被打出的那张手牌身上检查。它是出牌入口的前置修饰；不改变普通能力只在棋盘发现事件的约定。实现可在现有编译能力列表中对该实例做一次定向检查，并与既有 `next_hand_play_from_discard_owner` 标记取逻辑或；不新增可变状态、全场扫描或第二条结算路径。修饰存在于保留能力中，因而按现有“锁定／翻面保留”语义存续。`ACTION_GRANT_EXTRA_CARD_PLAY` 的 `next_hand_play_source: CARD_ZONE_DISCARD` 直接复用旧三阶能力已使用的实现。

`card_added_to_hand`、`powers_changed`、`extra_card_play_granted`、`ability_triggered` 等现有纯数据事件提供界面反馈；控制器不分支实现新规则。校验器须拒绝 `only_if_absent` 的非布尔值、与动态 `card` 规格同时使用或未知固定卡 ID。原有 `ACTION_ADD_CARD_TO_HAND` 形式、载入失败的原子性、当前五槽上限与确定性 `instance_id` 保持不变。

## 完整目录能力声明

下列声明及四张牌的数组是实施目标；不省略它们引用的嵌套能力。`MODIFIER_HAND_PLAY_AS_DISCARD` 是唯一新增修饰词汇，`only_if_absent` 是现有添牌动作的可选字段。其它词汇、触发时机和常量均已存在。

```gdscript
const MODIFIER_HAND_PLAY_AS_DISCARD: StringName = &"hand_play_as_discard"

const KUIHUA3_SWAP_SINGLE_ADJACENT_ENEMY: Dictionary = {
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

const GUMU_SUPPRESS_ENEMIES_BEFORE_SUMMON: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_BEFORE_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{
            "type": ACTION_FOR_EACH_SELECTED_CARD,
            "selector": {
                "zones": [CARD_ZONE_BOARD],
                "conditions": [{"type": CONDITION_SELECTED_CARD_IS_ENEMY}],
            },
            "actions": [{"type": ACTION_TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES}],
        }],
    }],
}

const GUMU_MINIMUM_DEFENSE_ON_ATTACK: Dictionary = {
    "retained_on_flip": true,
    "modifiers": [{"type": MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE}],
}

const GUMU_ATTACK_EACH_TARGET_TWICE: Dictionary = {
    "modifiers": [{"type": MODIFIER_ATTACK_EACH_TARGET_TWICE}],
}

const GUMU_WEAKEN_TARGET_ON_POWER_FAILURE: Dictionary = {
    "modifiers": [{"type": MODIFIER_WEAKEN_TARGET_ON_POWER_FAILURE}],
}

const GUMU_QUEUE_NEXT_SWAP: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{
            "type": ACTION_QUEUE_NEXT_HAND_PLAY_ABILITY,
            "ability": KUIHUA3_SWAP_SINGLE_ADJACENT_ENEMY,
        }],
    }],
}

const GUMU_QUEUE_NEXT_SUPPRESSION: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{
            "type": ACTION_QUEUE_NEXT_HAND_PLAY_ABILITY,
            "ability": GUMU_SUPPRESS_ENEMIES_BEFORE_SUMMON,
        }],
    }],
}

const GUMU_QUEUE_NEXT_MINIMUM_DEFENSE: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{
            "type": ACTION_QUEUE_NEXT_HAND_PLAY_ABILITY,
            "ability": GUMU_MINIMUM_DEFENSE_ON_ATTACK,
        }],
    }],
}

const GUMU_TIER_THREE_ADD_YUNV: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{
            "type": ACTION_ADD_CARD_TO_HAND,
            "card_id": &"YuNvWuFeng",
            "recipient": RECIPIENT_SELF,
            "only_if_absent": true,
        }],
    }],
}

const GUMU_YUNV_DISCARD_SOURCE: Dictionary = {
    "retained_on_flip": true,
    "modifiers": [{"type": MODIFIER_HAND_PLAY_AS_DISCARD}],
}

const GUMU_YUNV_ENTER: Dictionary = {
    "retained_on_flip": true,
    "triggers": [{
        "event": TRIGGER_CARD_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [
            {
                "type": ACTION_FOR_EACH_SELECTED_CARD,
                "selector": {
                    "zones": [CARD_ZONE_BOARD],
                    "conditions": [
                        {"type": CONDITION_SELECTED_CARD_IS_ENEMY},
                        {"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
                    ],
                },
                "actions": [{"type": ACTION_CHANGE_POWERS, "amount": -1}],
            },
            {
                "type": ACTION_GRANT_EXTRA_CARD_PLAY,
                "amount": 1,
                "next_hand_play_source": CARD_ZONE_DISCARD,
            },
        ],
    }],
}

&"YuNvWuFeng": {
    "abilities": [GUMU_YUNV_DISCARD_SOURCE, GUMU_YUNV_ENTER],
}
&"LangJiTianYa3": {
    "abilities": [GUMU_TIER_THREE_ADD_YUNV, GUMU_ATTACK_EACH_TARGET_TWICE,
        GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, GUMU_QUEUE_NEXT_SWAP],
}
&"XiaoYuanYiJu3": {
    "abilities": [GUMU_TIER_THREE_ADD_YUNV, GUMU_ATTACK_EACH_TARGET_TWICE,
        GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, GUMU_QUEUE_NEXT_SUPPRESSION],
}
&"LengYueKuiRen3": {
    "abilities": [GUMU_TIER_THREE_ADD_YUNV, GUMU_ATTACK_EACH_TARGET_TWICE,
        GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, GUMU_QUEUE_NEXT_MINIMUM_DEFENSE],
}
```

四张牌除 `abilities` 外的现有目录字段（含原文描述、数值、图片和门派）保持不变。删去已无引用的 `GUMU_TIER_THREE_ACTIVATION` 声明；其它牌数组不改。

## 验证

- 目录测试验证四个数组、锁定保留、非法 `only_if_absent` 声明被拒绝。模拟器测试分别覆盖三阶首次生成、已持有同 ID 时跳过、其它卡不拦截、手牌满、再次进场、翻面归属、玉女无锋自身弃牌堆来源、它给予的额外机会与效果队列隔离、相邻多敌逐张减点和移除、没有相邻敌仍请求额外出牌、上限前的尝试事件、旧主动入口消失。保留原有二次攻击及分次动画事件测试。
- UI 集成检查事件顺序和生成牌显示，不在控制器添加规则。静音、540×960 竖屏下实测三阶进场、生成牌出场、额外出牌与相邻减点效果。
- 变更前全套有两处已知失败：`test_sect_catalog.gd` 对新增古墓派进阶期望仍为 0；`test_gumu_abilities.gd` 仍测试已被卡面取消的三阶耗内力发动。实施时更新这些过时断言，完成后运行完整套件。
- 出牌入口是 AI 热路径。修改前保留准确源和匹配的 Release native 二进制，用同机器、同一固定节点数与夹具做交错 A/B；核对动作、分数和搜索遍历，记录相对耗时。没有测量不宣称性能改善；发现可重复回退立即报告。
