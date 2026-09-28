# 古墓派十五张卡牌与统一的下次手牌效果队列

状态：**已获创作者确认，实施中**。本文件以 `scripts/card_catalog.gd` 的当前卡面文字、数值、图片、门派和品阶为准，保留创作者对夭矫空碧 3／4 阶描述的改动。范围仅为把下列十五个 ID 按现有定义顺序加入 `ALL_CARD_IDS` 并实装能力；本次不新增可选门派、敌人或解锁门槛。

## 已确认的规则

- “下一张从手牌中打出的牌”可跨回合等待，来源牌移区、翻面或离场不撤销。玩家各持独立队列；每条待效果记录**赋予者的卡面名称 `glyph`**。一次合格手牌出牌按入队顺序执行每个赋予者名称的首条记录；同名的第二条及后续记录保持原相对顺序，顺延到以后出牌。不同卡名的效果可叠加；料敌机先也按相同规则参与。
- 三阶剑法的指定能力耗一内力。所给的额外机会仍取走手牌中的实体牌并占用一次出牌机会，但这次牌**按弃牌堆来源**结算：不消耗“下一张从手牌中打出”的待赋能，也不触发料敌机先的待失效层；不更新 `last_hand_play_by_owner`。若额外机会没有用来打出手牌，来源改写随该机会／本回合结束失效，不带到下一回合。
- 二阶以上的文字拆为**两个独立能力**：一项令攻击对每个目标最多尝试两次，另一项令每次因点数比较失败的尝试使目标四侧点数各减一。两项可以分别授予或失去，互不作为对方的前提。共同存在时按目标 A 连续尝试最多两次、再处理目标 B；首次成功翻面后不对该目标作第二次尝试。范围不符、禁攻、目标不再合法或攻击次数上限不算“点数不足”，不减点数。一次标准攻击仍只占一次攻击次数，`CARD_AFTER_ATTACK` 仍在整批目标之后触发一次。
- 夭矫空碧 3／4 阶现行卡面是“每当你**尝试**额外出牌前，抽一张牌”。`TRIGGER_EXTRA_CARD_PLAY_GRANTED` 在每次有效的 `ACTION_GRANT_EXTRA_CARD_PLAY` 请求**尝试增加一个机会之前**触发；`amount` 大于一时逐个尝试、逐次触发。即使已达上限、机会最终没有增加，也先抽牌。若额外机会真的增加，仍沿用原有机会变化事件供界面呈现；不要把这两个时机混同。
- 天罗地网四阶在自身进场后生成待赋能条目时，快照自身**非印刷、当时仍有效**的能力；不复制印刷能力，也不重复复制本次已明确给予的“敌方移动后减点数”能力。之后来源离场或这些能力失效，已排队的快照仍等待下一张合格手牌；快照之后才新获得的能力不追加入这条队列。后天能力按原有声明和顺序结算。
- 夭矫空碧四阶的“友方”包括自己；由**被攻击的那张友方牌**移动，按现有避险规则先找攻击范围外的首个相邻空格，找不到则移至首个相邻空格。若移后仍在范围内，攻击照常继续。

## 队列与料敌机先

玩家各自只有一条按时间排序的待效果队列。每条记录使用同一种结构：`grantor_name`（排队当时赋予者卡牌的 `glyph`，复制成字符串，不依赖该实例继续存在）和有序 `actions`（这**一次赋予**要在下一张牌上执行的动作快照）。判重只看卡名，不另存实例号或品阶作为判重键，也不另设料敌机先专用条目类型或独立计数。古墓派把赋能动作排入队列；料敌机先保留目录里的 `ACTION_ADD_PENDING_NON_RETAINED_SUPPRESSION`，但它的执行结果只是以 `grantor_name = "料敌机先"` 向对手同一队列排入永久失效动作。一次进场同时给予数种能力，例如天罗地网四阶的移动惩罚和后来获得的其它能力，属于**同一条记录里的多个动作**，不能因名称相同而互相顺延。

每张**按手牌来源**结算的牌在进场能力发现前，检查开始时的队列快照。按 FIFO 遍历，以 `grantor_name` 判断重复：每个名称的首条记录进入本次执行集，之后同名的记录进入顺延集。本次执行集按原有相对顺序逐条、逐动作结算；顺延集按原有相对顺序留在队列前端。处理期间新排入的记录接在顺延集之后，只能从下张合格手牌开始参与选择。特殊的弃牌堆来源机会不消费队列中的任何记录。牌的 ID、品阶、`instance_id` 不参与重复判定：两张不同品阶的同名古墓派牌也会顺延；不同卡名即使赋予完全相同的能力也不顺延，实际能力是否叠加再由现有赋能去重规则决定。

队列记录的例子如下（这是运行时纯数据形状示意，不是额外的目录能力）：

```gdscript
{"grantor_name": "冷月窥人", "actions": [{
    "type": ACTION_GRANT_TRIGGER_CARD_ABILITY,
    "ability": GUMU_MINIMUM_DEFENSE_ON_ATTACK,
}]}
{"grantor_name": "料敌机先", "actions": [{
    "type": ACTION_PERMANENTLY_REMOVE_NON_RETAINED_ABILITIES,
    "card": CARD_REF_TRIGGER_CARD,
}]}
```

例：队列依次为 `[料敌机先①，浪迹天涯①，料敌机先②，冷月窥人①，浪迹天涯②]`。下一张合格手牌按 `料敌机先① → 浪迹天涯① → 冷月窥人①` 结算；队列留下 `[料敌机先②，浪迹天涯②]`，由再下一张合格手牌结算。先排料敌机先、后排赋能，则先移除原有非保留能力、再取得新能力；先排赋能、后排料敌机先，则本次新取得的非保留能力也会被移除。保留能力不受移除影响；没有可移除能力时，料敌机先的该条记录仍算已消费。同名多次料敌机先由此仍是一张合格手牌只用一条，无需专用分支。

这取代料敌机先现有的双人待失效计数，不再维护“计数 + 队列”两份可变状态。对局界面警告从队列中统计尚待执行的永久失效记录；执行每项时仍发 `non_retained_suppression_consumed`，剩余数量包含顺延记录和处理期间新排入的同类记录，避免抽取本次执行集后误报为零。旧紧凑状态中的标量 8／9 在加载时展开为相同数量、赋予者卡名为“料敌机先”的普通记录；旧状态没有与古墓赋能交错的历史，按原计数顺序排列即可。新版本状态仅以队列为准，不追加标量槽位。`DuelState` 复制、紧凑状态往返、状态键、重放、AI 状态摘要与旧档恢复都必须覆盖队列。旧档中的多层料敌机先继续逐张消耗；旧录像若持久化，应核查与新规则版本的兼容性。

一次性队列在为空时通过常数时间检查跳过；仅实物出牌且来源为手牌时才处理，不增加普通事件发现、攻击范围查询或每个搜索节点的全场扫描。记录的卡名和动作是纯数据声明／快照，不保存 UI 节点或来源牌活引用。动态能力是否后天获得应有明确来源标记；不能靠“当前数组尾部”或与印刷声明值相等来猜测，因能力会失效、恢复与重获。队列的顺序、赋予者名称和动作须进入状态键；能力的后天来源标记也须随当前卡牌进入状态键。天罗地网四阶排队的后天能力应在入队时展开为快照，避免后来读取已经离场的来源牌。

另两条可选路径已排除：用多个一次性玩家光环表示待效果，需在动态能力复制、同次出牌合并以及料敌机先顺序结算处增加隐式同步；给每张古墓牌添加专用模拟器分支违反现有卡牌无关规则架构。队列只统一确实同属“下一张合格手牌”的效果，不扩展成任意定时器框架。

## 目录能力声明草案

下列为拟写入 `scripts/card_catalog.gd` 的完整声明。`ACTION_QUEUE_NEXT_HAND_PLAY_ABILITY`、`TRIGGER_EXTRA_CARD_PLAY_GRANTED`、`MODIFIER_ATTACK_EACH_TARGET_TWICE` 和 `MODIFIER_WEAKEN_TARGET_ON_POWER_FAILURE` 是本次最小新增通用词汇。排队动作可选的 `include_acquired_from` 字段在**同一次排队**中快照额外获得的能力，作为同一条记录的后续动作；已有动作只在标明的字段处扩展。`KUIHUA3_SWAP_SINGLE_ADJACENT_ENEMY` 与 `LOCKED_ATTACK_EVASION` 是现有声明，完整列出以固定组合。

```gdscript
const ACTION_QUEUE_NEXT_HAND_PLAY_ABILITY: StringName = &"queue_next_hand_play_ability"
const TRIGGER_EXTRA_CARD_PLAY_GRANTED: StringName = &"extra_card_play_granted"
const MODIFIER_ATTACK_EACH_TARGET_TWICE: StringName = &"attack_each_target_twice"
const MODIFIER_WEAKEN_TARGET_ON_POWER_FAILURE: StringName = &"weaken_target_on_power_failure"

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

const GUMU_TIER_THREE_ACTIVATION: Dictionary = {
    "retained_on_flip": true,
    "activation": {
        "input": ACTIVATION_DRAG_TO_TARGET,
        "target_rule": TARGET_ANY_ENEMY_BOARD,
        "costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
        "actions": [
            {"type": ACTION_CHANGE_POWERS, "amount": -1,
             "card": CARD_REF_SELECTED_CARD},
            {"type": ACTION_GRANT_EXTRA_CARD_PLAY, "amount": 1,
             "next_hand_play_source": CARD_ZONE_DISCARD},
        ],
    },
}

const GUMU_DRAW_BEFORE_EXTRA_PLAY_ATTEMPT: Dictionary = {
    "triggers": [{
        "event": TRIGGER_EXTRA_CARD_PLAY_GRANTED,
        "conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
        "actions": [{"type": ACTION_DRAW_CARDS, "amount": 1}],
    }],
}

const GUMU_ALLY_ATTACK_EVASION: Dictionary = {
    "retained_on_flip": true,
    "triggers": [{
        "event": CARD_BE_ATTACKED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_ALLY}],
        "actions": [{
            "type": ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY,
            "card": CARD_REF_TRIGGER_CARD,
            "prefer_outside_attacker_range": true,
        }],
    }],
}

const GUMU_ENEMY_MOVE_WEAKEN: Dictionary = {
    "retained_on_flip": true,
    "triggers": [{
        "event": CARD_AFTER_MOVED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_ENEMY}],
        "actions": [{"type": ACTION_CHANGE_POWERS, "amount": -1,
                     "card": CARD_REF_TRIGGER_CARD}],
    }],
}

const GUMU_TIANLUO_QUEUE: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [
            {"type": ACTION_GRANT_ABILITY_TO_SELF,
             "ability": GUMU_ENEMY_MOVE_WEAKEN},
            {"type": ACTION_QUEUE_NEXT_HAND_PLAY_ABILITY,
             "ability": GUMU_ENEMY_MOVE_WEAKEN},
        ],
    }],
}

const GUMU_TIANLUO_QUEUE_WITH_ACQUIRED: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [
            {"type": ACTION_GRANT_ABILITY_TO_SELF,
             "ability": GUMU_ENEMY_MOVE_WEAKEN},
            {"type": ACTION_QUEUE_NEXT_HAND_PLAY_ABILITY,
             "ability": GUMU_ENEMY_MOVE_WEAKEN,
             "include_acquired_from": CARD_REF_ABILITY_SOURCE,
             "exclude_ability": GUMU_ENEMY_MOVE_WEAKEN},
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
            {"type": ACTION_ADD_PENDING_NON_RETAINED_SUPPRESSION,
             "recipient": RECIPIENT_OPPONENT, "amount": 1},
        ],
    }],
}
```

### 每张牌的精确 `abilities` 数组

```gdscript
&"LangJiTianYa1":  {"abilities": [GUMU_QUEUE_NEXT_SWAP]}
&"LangJiTianYa2":  {"abilities": [GUMU_ATTACK_EACH_TARGET_TWICE, GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, GUMU_QUEUE_NEXT_SWAP]}
&"LangJiTianYa3":  {"abilities": [GUMU_TIER_THREE_ACTIVATION, GUMU_ATTACK_EACH_TARGET_TWICE, GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, GUMU_QUEUE_NEXT_SWAP]}
&"XiaoYuanYiJu1": {"abilities": [GUMU_QUEUE_NEXT_SUPPRESSION]}
&"XiaoYuanYiJu2": {"abilities": [GUMU_ATTACK_EACH_TARGET_TWICE, GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, GUMU_QUEUE_NEXT_SUPPRESSION]}
&"XiaoYuanYiJu3": {"abilities": [GUMU_TIER_THREE_ACTIVATION, GUMU_ATTACK_EACH_TARGET_TWICE, GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, GUMU_QUEUE_NEXT_SUPPRESSION]}
&"LengYueKuiRen1": {"abilities": [GUMU_QUEUE_NEXT_MINIMUM_DEFENSE]}
&"LengYueKuiRen2": {"abilities": [GUMU_ATTACK_EACH_TARGET_TWICE, GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, GUMU_QUEUE_NEXT_MINIMUM_DEFENSE]}
&"LengYueKuiRen3": {"abilities": [GUMU_TIER_THREE_ACTIVATION, GUMU_ATTACK_EACH_TARGET_TWICE, GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, GUMU_QUEUE_NEXT_MINIMUM_DEFENSE]}
&"KongBi2":       {"abilities": [LOCKED_ATTACK_EVASION]}
&"KongBi3":       {"abilities": [GUMU_ALLY_ATTACK_EVASION]}
&"KongBi4":       {"abilities": [GUMU_DRAW_BEFORE_EXTRA_PLAY_ATTEMPT, GUMU_ALLY_ATTACK_EVASION]}
&"TianLuoDiWang2": {"abilities": [GUMU_TIANLUO_QUEUE]}
&"TianLuoDiWang3": {"abilities": [GUMU_ATTACK_EACH_TARGET_TWICE, GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, GUMU_TIANLUO_QUEUE]}
&"TianLuoDiWang4": {"abilities": [GUMU_ATTACK_EACH_TARGET_TWICE, GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, GUMU_TIANLUO_QUEUE_WITH_ACQUIRED]}
```

`KUIHUA3_SWAP_SINGLE_ADJACENT_ENEMY` 是传给下一张牌的完整能力，而非浪迹天涯自身进场时执行的能力。小园艺菊的临时失效截至当前玩家回合结束；若它在进场前触发后，目标敌牌移动、翻面或离场，按现有临时失效批次恢复规则处理。天罗地网自身获得的移动惩罚是动态能力，因此未到 `CARD_AFTER_SUMMONED` 前没有该效果。

## 结算和边界

1. **双次尝试与失败减点分别判定**：只在攻击者持有 `MODIFIER_ATTACK_EACH_TARGET_TWICE` 时增加同一目标的第二次尝试；仅持有 `MODIFIER_WEAKEN_TARGET_ON_POWER_FAILURE` 时仍只尝试一次，但那次点数比较失败便减点；仅持有双次尝试而没有减点能力时，两次比较不会额外减点。没有这些 modifier 的攻击维持原始热路径。先确认范围、阵营和禁攻，再比较点数。失败减点只发点数变化事件；可以在目标四侧全零时按现有移除流程处理。成功的尝试才触发 `CARD_BE_ATTACKED` 和后续翻面；目标每次移动、被移除或换阵营后都以精确实例重验。
2. **待效果顺序**：实际合法的手牌出牌提交点按 `grantor_name` 选取本次记录，先于 `CARD_BEFORE_SUMMONED` 执行；落位失败、非法动作及模拟器回滚不消费或顺延。每个卡名本次最多一条，记录内部的全部动作都按声明顺序对该牌执行，不给失效动作另设优先级。赋能走现有能力增益事件和“新主动能力替换旧主动能力”规则。来自不同卡名的相同能力可同次尝试授予，实际是否共存遵循现有去重规则。若同一次牌先赋能后被料敌机先删掉，仍按顺序发增益和失效事件。
3. **来源改写**：指定能力造成的额外机会仅有一次弃牌堆来源标记；物理牌仍从手牌取走，因此五个固定手牌槽和资源清理不变。该标记不让用户直接选择弃牌堆里的牌，也不改变常规出牌的来源。若在这次机会内触发另一笔额外出牌，不凭空延长原标记。
4. **额外机会抽牌**：每尝试获得一个额外出牌机会，先派发 `TRIGGER_EXTRA_CARD_PLAY_GRANTED`，再执行该机会的现有上限检查；上限已满仍抽牌，随后不会凭空多出机会。多个夭矫空碧来源各抽一张。非法上下文、并未执行到 `ACTION_GRANT_EXTRA_CARD_PLAY` 的分支不派发；抽牌本身若引发后续额外出牌请求，按事件深度限制正常处理。规则事件的归属是该次尝试获得机会的玩家，界面仍只在机会实际增加时呈现机会变化。
5. **状态兼容**：新队列须通过紧凑状态及持久状态往返、AI 搜索复制和状态键；加载旧状态时将原两位玩家各自的料敌机先计数展开为相同数量、卡名为“料敌机先”的通用记录。旧提示和事件继续可用；多层料敌机先仍逐张消耗。录制于旧规则的持久录像若存在，需要核查其版本和语义。

## 测试与性能门槛

先把 15 个 ID 与基础能力数组登记，恢复可通过的目录测试基线，再写纯模拟器失败用例：每个家族各阶能力和阵列顺序；跨回合及不同卡名赋能叠加；同名不同实例、同名不同品阶、同一实例多次排队均逐张顺延；特殊出牌不消费队列／不更新手牌历史；料敌机先多层逐张消费、与不同名赋能相遇时两种先后顺序及旧状态迁移；天罗地网四阶一次赋予的多项能力在同一条记录中同时执行；只有双次尝试、只有失败减点、两者都有以及两者都没有的攻击；二次攻击首次失败／二次成功／两次失败／首次成功／点数归零、攻击上限与目标反应；达到额外出牌上限仍先抽牌；友方闪避包含自身和第三方；天罗地网只复制活跃后天能力。再加控制器集成用例，检查移动、点数变化、抽牌和能力事件呈现。

改动原生攻击流程和状态键前，保留当前源码与其匹配的 Release 原生构建；使用相同引擎、配置和固定局面交错运行旧／新构建，比较完成深度的动作、分数、节点、状态摘要，并记录吞吐。规则本身改变时含古墓牌局面的动作可以不同；无古墓牌局面应一致。报告任何可重复回退。最后运行完整套件和静音 540×960 对局流程。当前变更前全套测试因这 15 张定义尚未进入 `ALL_CARD_IDS` 而失败，属于本次工作修复范围。
