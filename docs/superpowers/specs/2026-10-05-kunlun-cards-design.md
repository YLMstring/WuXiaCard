# 昆仑派卡牌规则实装设计

日期：2026-10-05。状态：待玩家确认；尚未修改生产代码。

## 范围与确认规则

以当前 `scripts/card_catalog.gd` 为目录：17 张牌已经进入
`ALL_CARD_IDS`；金针渡劫四张已有实现，保留原能力。补齐其余 13 张牌。
同时将夭矫空碧三、四阶的抽牌监听统一为连续行动尝试，纳入额外指定。
本次只实装卡牌规则，不增加昆仑可选门派、解锁敌人或敌人配置。
目录中的名称、点数、图片、武器、气和效果文字保持原样。

玩家已确认：

- 无声无色的额外机会只能指定，不能出牌；指定照常支付一点气。
- 额外指定与额外出牌共用每回合一次成功授予额度；优先先获得的类型，
  但它若没有任何合法动作，则改选实际获得的另一种可用类型。
- 阴阳两仪三、四阶抽牌加一仅自身在场时生效；先抽牌、后移除。
- 雨打飞花指定先移除己方所有同类玩家斜攻效果，再令目标攻击。
- 夭矫空碧三、四阶最新描述为“每当你尝试连续行动前，抽一张牌。”；
  额外出牌与额外指定都触发，包括已达成功授予上限的尝试。

额外指定允许使用己方任意可合法发动的指定能力；没有合法指定且没有
其它已请求的可用额外类型时，继续回合收尾，不跨回合储存机会。
两类请求都在检查成功授予上限之前
触发统一的“连续行动尝试”规则事件，让夭矫空碧先完整结算抽牌。
完成此事件后再检查额度、授予类型和是否还有对应合法行动；不能因额度
已满、气不足或当前没有合法指定而提前跳过这次抽牌。
普通的首次行动、仅询问合法行动、AI 开始下一深度、执行已经获得的
连续行动机会均不自行再次触发；只有实际执行效果所产生的授予请求触发。
若授予额外出牌时声明弃牌堆来源但授予失败，不设置来源标记。

同一次动作收尾中，两类请求按既有结算顺序保留为临时候选；每份请求的
尝试事件照常完整结算。准备交还行动控制时，按此时的实际状态选择
最早且有合法动作的候选类型：额外出牌检查合法手牌出牌，额外指定检查
可付气且有合法目标的指定。只检查合法性，不预演效果是否成功。
两种都可用时选择先获得的类型；先一种不可用时选择后一种；都不可用
时继续收尾。未曾请求另一种类型时，不凭空授予替代机会。
同一成功机会只消耗一次共用额度；不可用的候选不抢占额度。额度已在
之前的实际连续行动中消耗后，本次所有请求仍触发抽牌，但不能再授予。
候选只属于当前收尾过程，不存入玩家存档或另建跨回合状态；类型选定
后，未选中的候选不变成第二次连续行动，也不让玩家自行切换类型。

例如：先请求额外出牌、再请求额外指定，且手牌不能合法打出而场上有
可合法指定的牌，则进入额外指定；顺序相反且没有可用指定，则进入
额外出牌。夭矫空碧在这些请求前抽到的牌也计入最终合法性判断。

## 实现取舍

推荐扩展现有原语字段并复用现有结算：过滤抽牌、选择器、移除、
气消耗、翻面、攻击、玩家光环及移动规则继续走原生模拟器。
仅新增一个通用清除玩家光环动作；不把昆仑卡名写进 AI 或控制器。

另一方案是为每种昆仑能力新增专用动作和指定回合系统，改动更大且
会重复现有结算；不采用。用“不限范围”模拟斜向相邻也不采用，
因为会错误允许远处和正交目标。

必要的通用扩展：

1. `ACTION_SUMMON_CARD` 接受 `card_id`，与 `card` 互斥；构造新实例并
   复用现有召唤生命周期、首个空格和每回合特殊召唤上限。
2. `ACTION_CHANGE_POWERS` 接受 `copy_from`，与 `amount` 互斥；按上右下左
   复制目标此时的四点数，不改变其气、所有者或能力。复制模式可替换
   接收者的四个 `-1`，也可复制四个 `-1`；不能用普通加减实现此规则。
   点数相同返回 `NO_EFFECT`，后续攻击继续；复制四个零仍走四零移除。
3. `ACTION_GRANT_EXTRA_CARD_PLAY` 增加 `activation_only: true`：共用
   请求队列和成功授予上限，按请求顺序选择首个实际可用类型，
   选定仅指定时限定后续选择为指定。授予事件带此字段，
   界面显示“额外指定”；旧声明缺省仍是现有额外机会。
   规则触发标识 `TRIGGER_EXTRA_CARD_PLAY_GRANTED` 改为
   `TRIGGER_CONTINUOUS_ACTION_ATTEMPT`（`continuous_action_attempt`），
   对两类请求都在额度检查前逐次发出，不另建重复监听或保存成功标记。
   成功授予的展示事件 `extra_card_play_granted` 保留，与尝试规则事件区分。
4. `MODIFIER_NON_ORTHOGONAL_ATTACK_ANY_AXIS` 可增加
   `allow_diagonal_adjacent: true` 与 `forbid_orthogonal_adjacent: true`。
   前者允许斜向紧邻，不要求不限范围；后者禁止正交紧邻。
   两项均缺省为 false，旧规则不变。其它能力若允许正交距离二或更远，
   雨打飞花不额外禁止它们；远处斜向仍需原有不限范围能力。
   点数比较复用已有非直线任一轴胜出规则、特殊点数及反转规则。
5. `ACTION_GRANT_OWNER_AURA` 接受可选 `tag`。新
   `ACTION_REMOVE_OWNER_AURAS` 按 `tag` 清除能力来源当前所属玩家的
   全部匹配光环。标签仅用于不可变编译声明与清除匹配，不建立另一个
   玩家状态表。其它标签、对方光环、卡上直接持有的能力均不受影响。

紧凑格式更新版本，复用已废弃的槽位 11 存放仅指定标记，仍为 16 槽。
撤销、回放、状态复制、键与 native 边界都传递此标记；移除废弃的
`difficulty_eight_draw_consumed` 运行字段与相关测试残留。
本次对局状态不落盘，不增加旧紧凑快照迁移；已有玩家存档不变。

## 结算边界

- 阴阳两仪用 `CARD_SUMMONED` 处理“进场时”：抽两/四张阵法牌；
  自身移除；按棋盘 0..8 快照选择友方阵法，每张在其当前首个相邻空位
  生成一张八卦。每次生成完整结算之后再处理下一张，不递归扩展选择
  快照。无匹配牌、手牌满或无空位只影响对应动作，不加 `STOP_RULE`。
  三、四阶监听每次成功抽牌；仅友方抽牌，四 `-1` 不接受普通加一。
  来源被中途移除、翻面失效或压制后遵循现有触发重新校验。
- 雨打飞花一阶进场后给自己斜攻能力；二阶以上授予固定玩家光环。
  玩家光环在来源离场、被翻面或失效后仍持续，符合“你获得”既有规则。
  三、四阶指定可选择任意其它友方，先清己方所有带同类标签的光环，
  再让该实例按此时现存规则攻击；没有可攻击目标也仍消耗气并清效果。
  一阶自身斜攻能力不是玩家光环，不被该指定清除。
  四阶终局移除复用 `WANHUA_ENDING`，包括锁定与现有满盘终局快照语义，
  不改变全游戏的终局触发边界。
- 无声无色三、四阶复用古墓进场前暂时压制敌方，锁定能力不受影响，
  当前回合结束恢复。所有阶进场后尝试获得仅指定机会。
  指定目标是正交相邻友方，复制其当时点数，先自己完整攻击；
  二、三阶再让指定实例攻击；四阶再按此时棋盘顺序选择当前相邻友方
  逐一完整攻击。每一步仍检查实例、所属方及在场状态，不硬保留离场牌。
- 玉碎昆冈复用 `JIANFA_ENTRY_MOVE`，多个符合位置按原棋盘顺序处理。
  `CARD_AFTER_MOVED` 只在自己实际移动/换位后触发：选当前相邻敌方逐一
  非攻击翻面，二阶最后翻自己，三阶最后移除自己。无实际移动不触发。
  不新增移动免攻击、攻击免疫或忽略锁定等例外。

## 完整能力声明

以下 GDScript 为拟加入目录的完整声明。现有常量名称直接复用；新动作
`ACTION_REMOVE_OWNER_AURAS` 的通用字段定义见上文。

```gdscript
const KUNLUN_DRAW_POWER: Dictionary = {
    "triggers": [{
        "event": CARD_AFTER_DRAWN,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_ALLY}],
        "actions": [{"type": ACTION_CHANGE_POWERS, "amount": 1,
                     "card": CARD_REF_TRIGGER_CARD}],
    }],
}

const KUNLUN_FORMATION_GENERATE: Dictionary = {
    "type": ACTION_FOR_EACH_SELECTED_CARD,
    "selector": {
        "zones": [CARD_ZONE_BOARD],
        "conditions": [
            {"type": CONDITION_SELECTED_CARD_IS_ALLY},
            {"type": CONDITION_SELECTED_CARD_WEAPON_IS, "weapon": "阵法"},
        ],
    },
    "actions": [{
        "type": ACTION_SUMMON_CARD,
        "card_id": &"BaGuaFangWei",
        "owner": OWNER_ABILITY_SOURCE,
        "cell": {"type": CELL_REF_FIRST_ADJACENT_EMPTY,
                 "card": CARD_REF_SELECTED_CARD},
    }],
}

const KUNLUN_FORMATION_ENTRY_TWO: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [
            {"type": ACTION_DRAW_CARDS, "amount": 2, "weapon": "阵法"},
            {"type": ACTION_EXILE_SELF},
            KUNLUN_FORMATION_GENERATE,
        ],
    }],
}

const KUNLUN_FORMATION_ENTRY_FOUR: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [
            {"type": ACTION_DRAW_CARDS, "amount": 4, "weapon": "阵法"},
            {"type": ACTION_EXILE_SELF},
            KUNLUN_FORMATION_GENERATE,
        ],
    }],
}

const KUNLUN_DIAGONAL_ATTACK: Dictionary = {
    "modifiers": [{
        "type": MODIFIER_NON_ORTHOGONAL_ATTACK_ANY_AXIS,
        "allow_diagonal_adjacent": true,
        "forbid_orthogonal_adjacent": true,
    }],
}

const KUNLUN_DIAGONAL_SELF_ENTRY: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{"type": ACTION_GRANT_ABILITY_TO_SELF,
                     "ability": KUNLUN_DIAGONAL_ATTACK}],
    }],
}

const KUNLUN_DIAGONAL_OWNER_AURA: Dictionary = {
    "auras": [{
        "selector": {
            "zones": [CARD_ZONE_BOARD],
            "conditions": [{"type": CONDITION_SELECTED_CARD_IS_ALLY}],
        },
        "ability": KUNLUN_DIAGONAL_ATTACK,
    }],
}

const KUNLUN_DIAGONAL_OWNER_ENTRY: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{
            "type": ACTION_GRANT_OWNER_AURA,
            "tag": &"diagonal_adjacent_attack",
            "aura": KUNLUN_DIAGONAL_OWNER_AURA,
        }],
    }],
}

const KUNLUN_RESTORE_ATTACK_ACTIVATION: Dictionary = {
    "activation": {
        "input": ACTIVATION_DRAG_TO_TARGET,
        "target_rule": TARGET_OTHER_ALLY_BOARD,
        "costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
        "actions": [
            {"type": ACTION_REMOVE_OWNER_AURAS,
             "tag": &"diagonal_adjacent_attack"},
            {"type": ACTION_STANDARD_ATTACK_WITH_CARD,
             "card": CARD_REF_SELECTED_CARD},
        ],
    },
}

const KUNLUN_EXTRA_ACTIVATION: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{"type": ACTION_GRANT_EXTRA_CARD_PLAY,
                     "amount": 1, "activation_only": true}],
    }],
}

const KUNLUN_COPY_ATTACK_SELF: Dictionary = {
    "activation": {
        "input": ACTIVATION_DRAG_TO_TARGET,
        "target_rule": TARGET_ADJACENT_ALLY_BOARD,
        "costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
        "actions": [
            {"type": ACTION_CHANGE_POWERS, "copy_from": CARD_REF_SELECTED_CARD,
             "card": CARD_REF_ABILITY_SOURCE},
            {"type": ACTION_STANDARD_ATTACK_WITH_SELF},
        ],
    },
}

const KUNLUN_COPY_ATTACK_PAIR: Dictionary = {
    "activation": {
        "input": ACTIVATION_DRAG_TO_TARGET,
        "target_rule": TARGET_ADJACENT_ALLY_BOARD,
        "costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
        "actions": [
            {"type": ACTION_CHANGE_POWERS, "copy_from": CARD_REF_SELECTED_CARD,
             "card": CARD_REF_ABILITY_SOURCE},
            {"type": ACTION_STANDARD_ATTACK_WITH_SELF},
            {"type": ACTION_STANDARD_ATTACK_WITH_CARD,
             "card": CARD_REF_SELECTED_CARD},
        ],
    },
}

const KUNLUN_COPY_ATTACK_ADJACENT: Dictionary = {
    "activation": {
        "input": ACTIVATION_DRAG_TO_TARGET,
        "target_rule": TARGET_ADJACENT_ALLY_BOARD,
        "costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
        "actions": [
            {"type": ACTION_CHANGE_POWERS, "copy_from": CARD_REF_SELECTED_CARD,
             "card": CARD_REF_ABILITY_SOURCE},
            {"type": ACTION_STANDARD_ATTACK_WITH_SELF},
            {
                "type": ACTION_FOR_EACH_SELECTED_CARD,
                "selector": {
                    "zones": [CARD_ZONE_BOARD],
                    "conditions": [
                        {"type": CONDITION_SELECTED_CARD_IS_ALLY},
                        {"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
                    ],
                },
                "actions": [{"type": ACTION_STANDARD_ATTACK_WITH_SELF}],
            },
        ],
    },
}

const KUNLUN_MOVE_FLIP_SELF: Dictionary = {
    "triggers": [{
        "event": CARD_AFTER_MOVED,
        "conditions": [{"type": CONDITION_MOVING_CARD_IS_SELF}],
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
                "actions": [{"type": ACTION_FLIP_SELF,
                             "new_owner": OWNER_ABILITY_SOURCE}],
            },
            {"type": ACTION_FLIP_SELF,
             "new_owner": OWNER_OPPONENT_OF_ABILITY_SOURCE},
        ],
    }],
}

const KUNLUN_MOVE_EXILE_SELF: Dictionary = {
    "triggers": [{
        "event": CARD_AFTER_MOVED,
        "conditions": [{"type": CONDITION_MOVING_CARD_IS_SELF}],
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
                "actions": [{"type": ACTION_FLIP_SELF,
                             "new_owner": OWNER_ABILITY_SOURCE}],
            },
            {"type": ACTION_EXILE_SELF},
        ],
    }],
}
```

完整复用声明如下（不是仅列名称）：

```gdscript
const JIANFA_ENTRY_MOVE: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [
            {"type": CONDITION_TRIGGER_CARD_IS_SELF},
            {"type": CONDITION_SOURCE_HAS_EMPTY_BETWEEN_ENEMY},
        ],
        "actions": [{"type": ACTION_MOVE_SELF_TO_FIRST_EMPTY_BETWEEN_ENEMY}],
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

const WANHUA_ENDING: Dictionary = {
    "retained_on_flip": true,
    "triggers": [{
        "event": TRIGGER_BEFORE_DUEL_END,
        "conditions": [{"type": CONDITION_OWNER_DID_NOT_WIN}],
        "actions": [{"type": ACTION_EXILE_SELF}],
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
            "actions": [{"type": ACTION_RETURN_CARD_TO_HAND,
                         "card": CARD_REF_SELECTED_CARD,
                         "recipient": OWNER_ABILITY_SOURCE}],
        }],
    }],
}

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
                 "card": CARD_REF_ABILITY_SOURCE, "target": CARD_REF_SELECTED_CARD},
            ],
        }],
    }],
}
```

夭矫空碧同步后的完整声明（只改变抽牌监听名称和涵盖的请求类型，保留
当前锁定闪避及移除规则）：

```gdscript
const GUMU_DRAW_BEFORE_CONTINUOUS_ACTION_ATTEMPT: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CONTINUOUS_ACTION_ATTEMPT,
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

const GUMU_ALLY_ATTACK_EVASION_OR_EXILE: Dictionary = {
    "retained_on_flip": true,
    "triggers": [{
        "event": CARD_BE_ATTACKED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_ALLY}],
        "actions": [{
            "type": ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY,
            "card": CARD_REF_TRIGGER_CARD,
            "prefer_outside_attacker_range": true,
            "on_no_effect": [{"type": ACTION_EXILE_CARD,
                              "card": CARD_REF_TRIGGER_CARD}],
        }],
    }],
}
```

## 每张卡的精确能力数组

未写 `retained_on_flip` 的能力均按既有规则不锁定；指定成本始终一点气。

| ID | 精确 `abilities` 数组 |
| --- | --- |
| YinYangLiangYi2 | `[KUNLUN_FORMATION_ENTRY_TWO]` |
| YinYangLiangYi3 | `[KUNLUN_FORMATION_ENTRY_TWO, KUNLUN_DRAW_POWER]` |
| YinYangLiangYi4 | `[KUNLUN_FORMATION_ENTRY_FOUR, KUNLUN_DRAW_POWER]` |
| YuDaFeiHua1 | `[KUNLUN_DIAGONAL_SELF_ENTRY]` |
| YuDaFeiHua2 | `[KUNLUN_DIAGONAL_OWNER_ENTRY]` |
| YuDaFeiHua3 | `[KUNLUN_DIAGONAL_OWNER_ENTRY, KUNLUN_RESTORE_ATTACK_ACTIVATION]` |
| YuDaFeiHua4 | `[WANHUA_ENDING, KUNLUN_DIAGONAL_OWNER_ENTRY, KUNLUN_RESTORE_ATTACK_ACTIVATION]` |
| WuShengWuSe1 | `[KUNLUN_EXTRA_ACTIVATION, KUNLUN_COPY_ATTACK_SELF]` |
| WuShengWuSe2 | `[KUNLUN_EXTRA_ACTIVATION, KUNLUN_COPY_ATTACK_PAIR]` |
| WuShengWuSe3 | `[GUMU_SUPPRESS_ENEMIES_BEFORE_SUMMON, KUNLUN_EXTRA_ACTIVATION, KUNLUN_COPY_ATTACK_PAIR]` |
| WuShengWuSe4 | `[GUMU_SUPPRESS_ENEMIES_BEFORE_SUMMON, KUNLUN_EXTRA_ACTIVATION, KUNLUN_COPY_ATTACK_ADJACENT]` |
| YuSuiKunGang2a | `[JIANFA_ENTRY_MOVE, KUNLUN_MOVE_FLIP_SELF]` |
| YuSuiKunGang3a | `[JIANFA_ENTRY_MOVE, KUNLUN_MOVE_EXILE_SELF]` |
| JinZhenDuJie1a | `[]` |
| JinZhenDuJie2a | `[JINZHEN_RETURN]` |
| JinZhenDuJie3a | `[JINZHEN_RETURN, HENGSHAN_COUNTERATTACK]` |
| JinZhenDuJie4a | `[JINZHEN_RETURN, HENGSHAN_COUNTERATTACK]` |
| KongBi3 | `[GUMU_DRAW_BEFORE_CONTINUOUS_ACTION_ATTEMPT, GUMU_ALLY_ATTACK_EVASION]` |
| KongBi4 | `[GUMU_DRAW_BEFORE_CONTINUOUS_ACTION_ATTEMPT, GUMU_ALLY_ATTACK_EVASION_OR_EXILE]` |

## 验证与性能

修改前运行完整套件并保留原源码与匹配 Release DLL。先加入失败的原生
模拟器测试，再实现：覆盖双所有者、各阶差异、实际移动与失败移动、
换位双方、无空位/满手/无匹配牌、逐次生成、点数复制与 `-1`/四零、
气不足、仅指定机会与出牌拒绝、上限竞争、没有合法指定、恢复与键区分、
两类型先后顺序、两种均可用时不切换、先一种无动作时双向回退、两种
均无动作或未曾请求替代类型时不凭空授予、失败候选不消耗共用额度、
抽牌或其它尝试反应改变候选可用性时以交还控制前的实际状态选择、
额外出牌/指定两类尝试在上限已满时仍先抽牌、满手与无合法指定仍处理
尝试事件、普通指定和合法行动查询不误触发、双方多份夭矫空碧各自抽牌、
多来源光环/其它标签/对方不受影响、来源离场与翻面、锁定终局等。

攻击范围、攻击目标提示和闪避空格范围统一读取扩展修饰，不能只有 AI
或显示支持。光环清除只访问对应玩家已编译的光环列表；不扫描所有
手牌、弃牌、移除区。仅指定标记通过槽位常数时间判断，不加牌名分支。
保留缺省无新规则的快速分支，编译时汇总可用修饰位。

在同机相同配置下对原有固定 5,000 节点 Release 夹具交错 A/B，核对
动作、分数、节点与遍历一致；若可复现退化，立即报告再继续。
新牌夹具另外验证真实搜索与仅指定合法性，不把不同规则下的速度称作
优化收益。最终完整套件、两套 Windows native ABI、静音 540×960 实际
生产控制器玩法与事件动画必须通过；本次不导出 Android。
