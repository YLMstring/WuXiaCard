# 阴阳掌力二至四级平衡调整设计

日期：2026-09-11

## 目标

以当前卡牌目录文本为准，实装 `YinYangZhang2`、`YinYangZhang3` 与
`YinYangZhang4` 的新能力。三张牌都在进场时移除自己、过滤抽取掌法、
向当前场上的友方掌法授予距离能力，然后令这些友方掌法发起攻击。

二级保留旧版“隔一个空位”能力；三级允许隔一个空位或一个友方；四级
在三级基础上增加一次按加点批次触发的攻击。

## 共同结算顺序

三张牌都在 `CARD_SUMMONED` 时点按以下顺序结算：

1. 将阴阳掌力自身移除；
2. 按牌库顺序过滤抽取掌法牌，二级抽一张，三级和四级抽两张；
3. 按棋盘 `0→8` 快照当前场上的所有友方掌法，并向仍合法的实例授予
   本阶能力；
4. 再按棋盘 `0→8` 快照当前场上的所有友方掌法，并令其逐张完成一次
   普通攻击。

两个选择阶段互相独立。授予能力后因前序连锁离场、翻面或改变阵营的
牌，按通用的逐实例复核规则决定是否继续结算；不会用后来出现的牌替补。
阴阳掌力已经在移除区，不参与授予或攻击。刚抽入手牌的掌法不获得能力，
也不在本次结算中攻击。

过滤抽牌沿用现有 `ACTION_DRAW_CARDS` 语义：跳过非掌法而不改变其相对
顺序；手牌容量不足时只抽到可容纳的数量；没有掌法时不生成太祖长拳
保底。每张成功抽取仍逐张完成抽牌事件与展示。

## 授予能力

所有授予能力均为非锁定、非翻面保留能力，获得者翻面后按通用规则失去。

- 二级：可以攻击直线上距离二、且中间格为空的敌方；中间为任何卡牌时
  均受阻。
- 三级：可以攻击直线上距离二、且中间格为空或为友方的敌方；中间为
  敌方时受阻。
- 四级：距离规则与三级相同，并监听一次完整的友方加点批次；符合条件时
  由能力获得者自身发起一次普通攻击。

距离二攻击继续沿用普通攻击的点数比较、目标策略、指定攻击例外、攻击
次数上限和攻击后事件。授予能力只扩展攻击范围，不改变目标阵营或点数
比较。

## 加点批次事件

新增通用目录事件：

```gdscript
const TRIGGER_POWER_INCREASE_BATCH_FINISHED: StringName = (
    &"power_increase_batch_finished"
)
```

新增通用触发条件：

```gdscript
const CONDITION_POWER_INCREASE_BATCH_INCLUDES_ALLY: StringName = (
    &"power_increase_batch_includes_ally"
)
```

一次现有的点数动画批次对应一次规则事件：

- 单个 `ACTION_CHANGE_POWERS` 是一个批次；
- 一个 `ACTION_FOR_EACH_SELECTED_CARD` 直接产生的多张点数变化属于同一
  批次；
- 相邻且声明相同 `power_change_batch_group` 的动作属于同一批次；
- 两个未归入同一批次的先后加点动作分别触发；
- 攻击、进场或其它嵌套结算产生的点数变化保留各自的现有批次边界，
  不并入外层动作。

批次中至少有一张牌实际获得正数点数时，才发出一次
`TRIGGER_POWER_INCREASE_BATCH_FINISHED`。事件上下文保存本批次实际获得
点数的所属方集合，不进入 `DuelState`、存档、回放状态或搜索状态键。
条件以每条能力结算时的当前所属方为准：集合包含该所属方即通过。

同一批次同时增加两张或更多友方牌时，每张具有四级授予能力的场上友方
掌法只攻击一次。若同一批次同时增加双方卡牌，则双方各自符合条件的
能力来源各攻击一次。纯减点、零变化、四边 `-1` 的免疫目标以及其它未
产生正数 `powers_changed` 的尝试都不触发。

规则事件在该批次全部点数改变和对应的四边归零移除链完成后结算，且在
动作列表中的下一个非同批次动作之前结算。展示事件顺序为本批次现有的
`powers_changed` / `card_exiled`，随后才是 `ability_triggered` 与攻击事件，
因此现有并行加点动画播完后再播放反应攻击。

原生内核在批次没有实际正数变化时直接返回；有正数变化时先使用轻量的
监听能力检查，只有可能存在该事件的场上来源时才进入完整事件发现，避免
让不含四级授予能力的普通加点无条件承担完整触发扫描。

## 目录原语声明

二级授予能力：

```gdscript
const YINYANG_RANGE_TWO: Dictionary = {
    "modifiers": [{
        "type": MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO,
        "allow_intervening_ally": false,
    }],
}
```

三级授予能力：

```gdscript
const YINYANG_RANGE_THREE: Dictionary = {
    "modifiers": [{
        "type": MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO,
        "allow_intervening_ally": true,
    }],
}
```

四级授予能力：

```gdscript
const YINYANG_RANGE_FOUR: Dictionary = {
    "modifiers": [{
        "type": MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO,
        "allow_intervening_ally": true,
    }],
    "triggers": [{
        "event": TRIGGER_POWER_INCREASE_BATCH_FINISHED,
        "conditions": [{
            "type": CONDITION_POWER_INCREASE_BATCH_INCLUDES_ALLY,
        }],
        "actions": [{"type": ACTION_STANDARD_ATTACK_WITH_SELF}],
    }],
}
```

共同的场上友方掌法选择器：

```gdscript
const YINYANG_ALLIED_BOARD_PALMS: Dictionary = {
    "zones": [CARD_ZONE_BOARD],
    "conditions": [
        {"type": CONDITION_SELECTED_CARD_IS_ALLY},
        {
            "type": CONDITION_SELECTED_CARD_WEAPON_IS,
            "weapon": "掌法",
        },
    ],
}
```

二级完整能力：

```gdscript
const YINYANG_ZHANGLI_TWO: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [
            {"type": ACTION_EXILE_SELF},
            {"type": ACTION_DRAW_CARDS, "amount": 1, "weapon": "掌法"},
            {
                "type": ACTION_FOR_EACH_SELECTED_CARD,
                "selector": YINYANG_ALLIED_BOARD_PALMS,
                "actions": [{
                    "type": ACTION_GRANT_ABILITY_TO_SELF,
                    "ability": YINYANG_RANGE_TWO,
                }],
            },
            {
                "type": ACTION_FOR_EACH_SELECTED_CARD,
                "selector": YINYANG_ALLIED_BOARD_PALMS,
                "actions": [{"type": ACTION_STANDARD_ATTACK_WITH_SELF}],
            },
        ],
    }],
}
```

三级完整能力：

```gdscript
const YINYANG_ZHANGLI_THREE: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [
            {"type": ACTION_EXILE_SELF},
            {"type": ACTION_DRAW_CARDS, "amount": 2, "weapon": "掌法"},
            {
                "type": ACTION_FOR_EACH_SELECTED_CARD,
                "selector": YINYANG_ALLIED_BOARD_PALMS,
                "actions": [{
                    "type": ACTION_GRANT_ABILITY_TO_SELF,
                    "ability": YINYANG_RANGE_THREE,
                }],
            },
            {
                "type": ACTION_FOR_EACH_SELECTED_CARD,
                "selector": YINYANG_ALLIED_BOARD_PALMS,
                "actions": [{"type": ACTION_STANDARD_ATTACK_WITH_SELF}],
            },
        ],
    }],
}
```

四级完整能力：

```gdscript
const YINYANG_ZHANGLI_FOUR: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [
            {"type": ACTION_EXILE_SELF},
            {"type": ACTION_DRAW_CARDS, "amount": 2, "weapon": "掌法"},
            {
                "type": ACTION_FOR_EACH_SELECTED_CARD,
                "selector": YINYANG_ALLIED_BOARD_PALMS,
                "actions": [{
                    "type": ACTION_GRANT_ABILITY_TO_SELF,
                    "ability": YINYANG_RANGE_FOUR,
                }],
            },
            {
                "type": ACTION_FOR_EACH_SELECTED_CARD,
                "selector": YINYANG_ALLIED_BOARD_PALMS,
                "actions": [{"type": ACTION_STANDARD_ATTACK_WITH_SELF}],
            },
        ],
    }],
}
```

二、三、四级卡牌分别引用
`YINYANG_ZHANGLI_TWO`、`YINYANG_ZHANGLI_THREE`、
`YINYANG_ZHANGLI_FOUR`。

## 原生实现范围

新增事件和条件进入目录校验、原生声明编译与事件条件匹配。内核根据现有
点数批次边界汇总实际正数变化的所属方，在批次关闭时调用通用事件分发。
搜索代码不检查阴阳掌力的卡牌 ID，也不增加 GDScript 规则旁路。


`powers_changed` 仍是展示事件；目录能力只监听新的规则事件，避免把 UI
数据反向当作规则权威。新的事件上下文是一次转换内的临时数据，不改变
紧凑状态 ABI、置换表键、存档格式或回放快照。

## 测试与性能验证

目录和模拟器测试覆盖：

1. 二级抽一张、授予隔空能力并令场上友方掌法攻击；
2. 三级抽两张，授予隔空或隔友方能力；
3. 四级获得者在同批两张友方加点后只攻击一次；
4. 两个独立加点批次触发两次；相同显式批次组只触发一次；
5. 仅敌方增加、纯减点、无效目标和四边 `-1` 目标不触发；
6. 多张四级能力获得者各响应一次，并按棋盘顺序结算；
7. 授予能力翻面后失去，离场来源不再响应；
8. 事件顺序为整批点数事件完成后再出现能力闪动和攻击；
9. 三级和四级能越过一个友方，二级不能，三者都不能越过敌方；
10. 抽牌容量、无掌法牌库及后续攻击者失效继续沿用现有边界。

实施前保留当前源代码和匹配的 Windows Release 原生库。实现后重编
Windows Debug/Release 原生库，运行相关阴阳掌力测试和完整 78 套自动化
测试；再用不含阴阳掌力四级能力的固定加点局面做同机 Release A/B，确认
新增空路径检查没有可重复的性能回退。若中位耗时回退达到 3% 或动作、
评分、遍历发生非预期变化，立即报告并停止后续交付。
