# 雨打飞花四阶规则更新与光环翻面修复

日期：2026-10-06。状态：用户已确认，已实施并完成验证。

## 目录与规则

依据当前 `scripts/card_catalog.gd` 的四张雨打飞花，不改变名称、点数、
图片、起始气和目录文字。每阶进场后均授予当前玩家同一种光环：所有
在场友方可以攻击同一条对角线上的敌方，不能攻击横纵相邻敌方；斜向
比较仍只需彼此正对的两组点数中有一组较大。

对角线是行差和列差绝对值相同且非零，包括角格到对角角格的两格距离。
不包含行差一、列差二的偏斜方向。远端对角目标不受中间卡牌阻挡，按
“所有对角线方向”直接枚举目标；远端横纵攻击不额外开放，原本其它
能力允许的远端横纵攻击保持其原规则。

一阶无指定；二阶支付一点气，选择其它在场友方，先移除己方全部雨打
飞花光环，然后令所选牌攻击。三、四阶随后获取一张自身普通复制到
手牌，复用 `fresh_copy`：新实例、目录原始点数/能力/起始气，不继承
当前点数增减、后天效果和已消耗气。满手处理复用现有获取卡牌动作。
四阶保留原锁定终局移除。指定仍不受攻击是否成功翻面影响，没有新增
STOP_RULE；攻击及反应结束后再执行获取复制。

已授予的光环属于授予时的玩家。来源翻面、失去能力或离场不会自动
撤销光环，也不能将光环送给对手。受光环影响的牌翻面后不再是原玩家
友方，因此不再享受光环；重新归属原玩家后重新享受。

## 实现方案与取舍

推荐扩展现有 `non_orthogonal_attack_any_axis` 的可选布尔字段
`allow_diagonal_all`，不新增原语；保留原 `allow_diagonal_adjacent` 的
语义和默认值。实际攻击、攻击目标提示、攻击前闪避空格范围同步读取。
一阶改用已有玩家光环；二阶复用已有指定；三、四阶在指定末尾组合
`add_card_to_hand` 与 `fresh_copy`。保留内部历史标签
`diagonal_adjacent_attack`，减少无关改名。

替代方案：使用无限范围并组合既有斜向比较，会多开放远端横纵与偏斜
目标；不采用。为每张牌写专用规则则使 AI、控制器与模拟器分裂；不采用。

光环 bug 根因：`resolve_selector_source` 用来源实体的实时所属覆盖
光环持有者，`selected_card_is_ally` 随之把对手视为友方。仅为玩家
光环的目标筛选明确固定所属参照；来源的实时位置/区域仍用于空间
条件。普通卡牌规则仍跟随当前所属，不改变普通翻面结算。修复同时
覆盖光环修饰查询和嵌套光环触发的发现/再次校验，避免显示与结算分歧。
固定所属通过筛选函数的可选参数传入，不增加紧凑状态槽位、玩家存档
或 side_payload，也不改变普通卡牌上下文。

## 完整目录能力声明

```gdscript
const KUNLUN_DIAGONAL_ATTACK: Dictionary = {
    "modifiers": [{
        "type": MODIFIER_NON_ORTHOGONAL_ATTACK_ANY_AXIS,
        "allow_diagonal_all": true,
        "forbid_orthogonal_adjacent": true,
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

const KUNLUN_RESTORE_ATTACK_COPY_ACTIVATION: Dictionary = {
    "activation": {
        "input": ACTIVATION_DRAG_TO_TARGET,
        "target_rule": TARGET_OTHER_ALLY_BOARD,
        "costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
        "actions": [
            {"type": ACTION_REMOVE_OWNER_AURAS,
             "tag": &"diagonal_adjacent_attack"},
            {"type": ACTION_STANDARD_ATTACK_WITH_CARD,
             "card": CARD_REF_SELECTED_CARD},
            {"type": ACTION_ADD_CARD_TO_HAND,
             "card": {"type": CARD_SPEC_FRESH_COPY,
                      "of": CARD_REF_ABILITY_SOURCE},
             "recipient": RECIPIENT_SELF},
        ],
    },
}

const WANHUA_ENDING: Dictionary = {
    "retained_on_flip": true,
    "triggers": [{
        "event": TRIGGER_BEFORE_DUEL_END,
        "conditions": [{"type": CONDITION_OWNER_DID_NOT_WIN}],
        "actions": [{"type": ACTION_EXILE_SELF}],
    }],
}
```

每张牌最终精确 `abilities`：

| ID | abilities |
| --- | --- |
| YuDaFeiHua1 | `[KUNLUN_DIAGONAL_OWNER_ENTRY]` |
| YuDaFeiHua2 | `[KUNLUN_DIAGONAL_OWNER_ENTRY, KUNLUN_RESTORE_ATTACK_ACTIVATION]` |
| YuDaFeiHua3 | `[KUNLUN_DIAGONAL_OWNER_ENTRY, KUNLUN_RESTORE_ATTACK_COPY_ACTIVATION]` |
| YuDaFeiHua4 | `[WANHUA_ENDING, KUNLUN_DIAGONAL_OWNER_ENTRY, KUNLUN_RESTORE_ATTACK_COPY_ACTIVATION]` |

原 `KUNLUN_DIAGONAL_SELF_ENTRY` 如已无引用则删除，不保留失效声明。

## 验证

先运行完整基线，保留修改前源码和匹配 Windows Release DLL。先加入
失败回归，再修改：双所有者、四阶能力数组、全体/新入场友方、角到角
斜攻、两组中只赢一组、横纵相邻禁攻、偏斜排除、攻击提示和闪避范围；
来源攻击/非攻击翻面、清除能力、移除后光环不撤销/不转移，受影响牌
翻面/翻回，嵌套光环触发的固定持有者与实时空间条件，以及普通卡牌
筛选不被改成固定所属。指定覆盖多来源清除、对手/其它标签不受影响、
二阶不复制、三四阶复制、满手、气不足、反击/来源离场与事件先后。

运行所有套件；静音 540×960 生产控制器走新光环、指定、复制和翻面。
对缺省无新牌固定节点 Release 搜索夹具作同机交错 A/B，核对动作、
分数与遍历一致；如有稳定退化立即报告，不声称提速。本次不导出安卓。

修改前基线：93/93 套件通过，323.45 秒。日志
`.summer/local/rain-update-baseline.log`；修改前源码、目录与两套匹配
Release DLL 保留于 `.summer/local/rain-update-20261006/baseline-source/`。
先前专项复现保留于 `.summer/local/rain-aura-flip-check.*`：双所有者均
复现来源翻面后原持有者效果消失、对手斜向范围被开放的问题。

实装结果：旧版新增回归出现 54 个预期断言失败，没有脚本错误；新版
最终专项 207 项通过。既有昆仑 234 项、控制器 33 项、古墓 315 项、
普通触发再次校验 20 项均通过。新增生产控制器流程在快速模式和静音
540×960 正常动画时长下各通过 86 项；截图为
`.summer/local/rain-update-20261006/rain-copy.png`。双所有者恒山反击专项
另通过 6 项，确认友方攻击、反击、获取复制的事件顺序。

两套 Windows Release ABI 重建成功。五组同机固定 5,000 节点夹具按
旧/新/新/旧交错运行，动作、分数、节点与遍历元组全部一致。第五组
小幅变化另做新/旧/旧/新独立复测，30 样本/版本合并中位耗时为
0.311726/0.3132445 秒（+0.49%），配对差异有正有负，未复现稳定退化；
不声称提速。旧源码/DLL、原始测量及 `performance.md` 全部保留于
`.summer/local/rain-update-20261006/`。

最终完整套件 95/95，320.31 秒，没有记录错误。日志为
`.summer/local/rain-update-20261006/final-suite.log`。本次未导出安卓。
