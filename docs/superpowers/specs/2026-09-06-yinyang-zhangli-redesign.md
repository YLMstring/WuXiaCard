# 阴阳掌力重做设计

日期：2026-09-06

## 目标

以当前卡牌目录文本为准，替换旧版阴阳掌力的“抽两张掌法、向手牌
掌法授予距离与重复攻击”结算。新的三级与四级阴阳掌力在进场时移除
自己、抽一张掌法牌，使场上所有友方掌法获得对应距离能力，然后令
这些场上友方掌法依次发起一次普通攻击。

四边 `[-1, -1, -1, -1]` 的特殊点数语义不变。

## 结算顺序

1. 阴阳掌力在 `CARD_SUMMONED` 窗口移除自身。
2. 从所属方牌库中抽第一张掌法牌；跳过的非掌法保持原相对顺序。
   没有匹配牌时不生成太祖长拳，手牌容量仍可令抽牌无效。
3. 第一次按棋盘 `0→8` 选择当前场上的所有友方掌法，向每张仍合法的
   实例授予本阶距离能力。阴阳掌力已在移除区，因此不在选择范围内；
   手牌中的掌法（包括刚抽到的牌）也不获得能力。
4. 第二次按棋盘 `0→8` 取得当前场上所有友方掌法的快照，逐张完成一
   次普通攻击。每张牌开始结算前仍按通用规则复核实例、区域和所属方；
   前一张牌引起的连锁结算可以令后续牌失效，但不会改为寻找替代牌。
5. 本次攻击不是“重复攻击”，遵守普通攻击的目标、20 次攻击上限、
   无合法目标不触发攻击后效果等通用规则。

所有距离能力均为非保留能力，获得者翻面时失去。三级允许隔一个空位
攻击；四级允许隔一个空位或一个友方攻击。敌方仍会阻断距离二攻击。

## 目录原语声明

保留现有距离能力：

```gdscript
const YINYANG_RANGE_THREE: Dictionary = {
    "modifiers": [{
        "type": MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO,
        "allow_intervening_ally": false,
    }],
}

const YINYANG_RANGE_FOUR: Dictionary = {
    "modifiers": [{
        "type": MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO,
        "allow_intervening_ally": true,
    }],
}
```

三级与四级共用以下结构，仅替换授予的距离能力：

```gdscript
{
    "triggers": [{
        "event": TRIGGER_CARD_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [
            {"type": ACTION_EXILE_SELF},
            {"type": ACTION_DRAW_CARDS, "amount": 1, "weapon": "掌法"},
            {
                "type": ACTION_FOR_EACH_SELECTED_CARD,
                "selector": {
                    "zones": [CARD_ZONE_BOARD],
                    "conditions": [
                        {"type": CONDITION_SELECTED_CARD_IS_ALLY},
                        {
                            "type": CONDITION_SELECTED_CARD_WEAPON_IS,
                            "weapon": "掌法",
                        },
                    ],
                },
                "actions": [{
                    "type": ACTION_GRANT_ABILITY_TO_SELF,
                    "ability": YINYANG_RANGE_THREE, # 四级改为 YINYANG_RANGE_FOUR
                }],
            },
            {
                "type": ACTION_FOR_EACH_SELECTED_CARD,
                "selector": {
                    "zones": [CARD_ZONE_BOARD],
                    "conditions": [
                        {"type": CONDITION_SELECTED_CARD_IS_ALLY},
                        {
                            "type": CONDITION_SELECTED_CARD_WEAPON_IS,
                            "weapon": "掌法",
                        },
                    ],
                },
                "actions": [{"type": ACTION_STANDARD_ATTACK_WITH_SELF}],
            },
        ],
    }],
}
```

`YINYANG_REPEAT_ATTACK` 不再由任何阴阳掌力授予；若目录中已无其它引用，
实现时一并删除该旧常量及只为它保留的过期测试。

## 验证

- 目录声明：抽牌数量为一，两个选择器均限定棋盘、友方、掌法；没有
  重复攻击授予。
- 三级：现有场上友方掌法和刚抽到的手牌掌法并存时，仅场上掌法获得
  隔空能力并攻击。
- 四级：仅场上掌法获得隔空或隔友方能力并攻击。
- 顺序：移除、单张过滤抽牌、全部授予事件、逐张攻击事件。
- 边界：没有掌法可抽、没有场上友方掌法、后续攻击者在前序连锁中
  失效、获得者翻面后失去能力。
- 运行目录、模拟器、搜索、集成与完整自动化套件；之后重新构建 ARM64
  原生库并导出、校验 Android Release APK。
