# 跨门派同名牌的随机获取限制

日期：2026-10-04。用户已确认设计并授权实施。

## 目标与规则

昆仑派新加入的 `JinZhenDuJie1a`–`JinZhenDuJie4a` 与恒山派
`JinZhenDuJie1`–`JinZhenDuJie4` 同名，并复用已有能力。玩家随机获取
其中一个门派的版本后，不应继续随机获取另一个门派的同名版本。

“同名”按目录 `glyph` 完全相同判断；“其它门派”按目录 `sect` 不同判断。
不比较卡牌 ID、能力声明、品阶或武器。

随机候选牌只要与任意一张已解锁牌同名、但门派不同，就排除。该限制
跨全部品阶。例如解锁昆仑派一阶金针渡劫，会排除恒山派一至四阶金针渡劫；
昆仑派自己的更高品阶仍按原有条件参加随机选择。

本规则覆盖开局三张随机牌及胜利、失败的普通随机奖励。门派固定解锁
照常，包括开局解锁本门派一阶牌和升阶解锁本门派对应品阶牌。显式解锁、
测试模式及目录声明的指定保底奖励不因本规则被拒绝。战斗中的副牌构建、
抽牌、生成牌和敌人牌组不使用此规则。

已有解锁牌不删除。若旧存档或固定解锁使两个门派的同名牌都已经解锁，
两个门派中仍未解锁的同名牌都会被普通随机池排除；固定解锁仍照常。
现有已保存的待选奖励保持原样，本规则用于此后新生成的随机候选。

## 开局顺序

用户确认本门派固定解锁照常，而且开局选择昆仑派后，其一阶金针渡劫
必须先影响随机池，开局随机三张牌不能再抽到恒山派的金针渡劫。

当前 `begin_run_and_save()` 先调用 `_pick_starting_tier_one_ids()`，再把
本门派一阶牌和随机牌交给 `_build_unlock_expansion()` 统一解锁。
现有抽样已按 `glyph` 去重三张随机牌，并避开固定主牌的同名牌，
但尚未考虑本门派即将解锁的牌所造成的跨门派排除。

抽取开局三张牌时，使用“原已解锁牌 + 本门派即将解锁的一阶牌”构造
本次过滤条件，达到先解锁本门派牌、再抽随机牌的规则效果。
无需提前保存或修改传入的 profile。最终仍在现有一次事务中解锁所有牌、
安排主牌和牌库、创建旅程并保存；失败时返回原 profile。

当前门派目录尚未注册可选昆仑派，因此本次不增加昆仑派选择入口。
恒山开局使用完整生产流程验证；昆仑侧把真实昆仑一阶 ID 传入同一个
生产开局抽样函数，验证未来门派注册后所需的过滤行为。

三张随机牌彼此不能同名，不论门派是否相同，也不能与两张固定主牌同名。
已有的候选不足时使用已拥有牌回退也必须遵守这些限制和跨门派过滤，
不得为了凑齐三张而重引入被排除的牌。仍不足三张时沿用开局失败的原行为，
不改变存档。

## 方案选择

推荐在每次随机候选构建时，从已解锁 ID 推导 `glyph -> sect 集合`，
开局再加入本门派一阶 ID。候选与该名字的任一已解锁门派不同，就排除。
同一轮候选筛选只构建一次此查询表，按已有目录循环过滤。

另一方案是在每次解锁时保存被排除的卡牌 ID 列表。这会引入第二份可推导
状态，并要求处理新增目录牌、旧存档、旅程重置和保存失败后的同步；本需求
没有需要记录独立历史的规则，因此不采用。

不改成先按卡名分组再均匀抽取：那会改变多版本卡名的抽中权重，与本次
避免跨门派重复的需求无关。保留现有随机打乱与选取方式。

## 代码范围与数据流

- `scripts/deck_profile_store.gd`：一个共享的同名跨门派候选过滤判断，
  供 `_pick_starting_tier_one_ids()` 和 `create_reward_offer_and_save()` 使用。
- 开局过滤输入包含 `sect_tier_one_ids`，确保即将发生的本门派解锁先影响抽样。
- 奖励过滤输入来自 `get_unlocked_ids(profile)`；胜利升阶事务已先解锁
  本门派对应品阶牌，再创建奖励，沿用该顺序。
- `_build_unlock_expansion()` 保留同名同门派低阶关联解锁与牌库排序。
  新解锁记录自然影响后续随机筛选，无需在每个解锁入口维护排除名单。
- 不增加 profile 字段或 schema 版本，不向 `DuelState`、紧凑状态或 AI 查询
  加入此规则。筛选发生在旅程/奖励生成期间，不属于搜索热路径。
- 保留各入口的其它现有筛选条件，不借此调整门派池或抽样权重。

## 当前目录能力声明

本次不修改卡牌规则或新增原语。记录两套金针渡劫现有完整能力声明及
准确的 `abilities` 数组，避免把“同名”错误实现成能力相等判断。

```gdscript
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
            "actions": [{
                "type": ACTION_RETURN_CARD_TO_HAND,
                "card": CARD_REF_SELECTED_CARD,
                "recipient": OWNER_ABILITY_SOURCE,
            }],
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
                    {
                        "type": CONDITION_SELECTED_CARD_FLIPPED_BY_CURRENT_ATTACK,
                        "previous_owner": OWNER_ABILITY_SOURCE,
                    },
                    {"type": CONDITION_SELECTED_CARD_CAN_BE_ATTACKED_BY_SOURCE},
                ],
            },
            "actions": [
                {"type": ACTION_REMOVE_THIS_ABILITY},
                {
                    "type": ACTION_STANDARD_ATTACK_WITH_CARD,
                    "card": CARD_REF_ABILITY_SOURCE,
                    "target": CARD_REF_SELECTED_CARD,
                },
            ],
        }],
    }],
}
```

所有八张牌的 `glyph` 均为 `金针渡劫`：

| 卡牌 ID | 门派 | 品阶 | 精确 abilities 数组 |
|---|---|---:|---|
| `JinZhenDuJie1a` | 昆仑派 | 1 | `[]` |
| `JinZhenDuJie2a` | 昆仑派 | 2 | `[JINZHEN_RETURN]` |
| `JinZhenDuJie3a` | 昆仑派 | 3 | `[JINZHEN_RETURN, HENGSHAN_COUNTERATTACK]` |
| `JinZhenDuJie4a` | 昆仑派 | 4 | `[JINZHEN_RETURN, HENGSHAN_COUNTERATTACK]` |
| `JinZhenDuJie1` | 恒山派 | 1 | `[]` |
| `JinZhenDuJie2` | 恒山派 | 2 | `[JINZHEN_RETURN]` |
| `JinZhenDuJie3` | 恒山派 | 3 | `[JINZHEN_RETURN, HENGSHAN_COUNTERATTACK]` |
| `JinZhenDuJie4` | 恒山派 | 4 | `[JINZHEN_RETURN, HENGSHAN_COUNTERATTACK]` |

## 验证计划

1. 使用真实目录的恒山/昆仑金针渡劫做 profile 测试，验证一阶解锁能
   排除其它门派全部品阶，反向解锁也成立。
2. 验证本门派同名高阶仍可随机出现，不同卡名不受影响；已有两门派
   同名解锁时两边后续随机候选都被过滤，旧解锁不删除。
3. 覆盖普通胜利与失败奖励，以及关联低阶解锁、升阶固定解锁后的筛选。
   固定解锁和原有保底奖励继续按原规则执行。
4. 用确定种子的昆仑派开局验证：一阶昆仑金针已经解锁，三张随机牌无
   恒山金针，三张牌彼此以及五张主牌均无同名。恒山开局作反向验证。
5. 让精简候选夹具包含跨门派同名牌，验证正常候选和已拥有牌回退均
   不突破过滤；不足三张和保存失败保留原 profile。
6. 保存再加载验证过滤可由解锁记录重建；旅程重置后依照重置后的解锁
   记录重新推导，不残留上一轮排除名单。
7. 运行完整套件。静音走一次真实开局、奖励领取和再次生成奖励流程，
   在竖屏界面检查卡名与获得结果，不改玩家正常音量配置。

维护收益是避免为可推导规则增加存档状态，并让所有解锁入口自然生效。
本设计不声称提高运行性能；战斗规则和 AI 搜索不在修改范围内。

## 修改前基线

当前提交 `d415920a6bb0c2befd6e0911c4a2f27daebc0116`，开始时工作区干净。
已运行规范完整测试命令：89 个套件中 88 个通过，
`test_yusui_kungang_abilities.gd` 有 4 个失败断言。
组牌存档、奖励存档及两者界面集成套件均通过。

失败来自该测试仍以 `YuSuiKunGang4` 的旧初始点数 `[3, 5, 5, 3]`
验证回合衰减，而本提交已把这个 ID 改成武当派“天地同寿”，初始点数为
`[5, 5, 5, 5]`。它的回合衰减声明未改变。这是本次实现前已存在的
目录与测试期望不一致，不应回退目录来恢复旧断言。
基线日志保存在 `.summer/local/cross-sect-namesakes-20261004/baseline.log`。

## 实施与验收

共享过滤已接入开局和普通奖励候选构建，正式卡牌声明、副牌逻辑及
存档 schema 未修改。新增专项套件先出现 19 个预期规则失败，再通过
63 项检查。原奖励夹具现在选择不与已拥有牌跨门派同名的测试候选，
保留原进阶上限及门派池断言；旧点数测试从目录取得初值，独立检查
未衰减、一次减一和两次减一后的结果。

最终完整套件 90/90 通过，耗时 295.07 秒。静音 540×960 正式
`main.tscn` 流程通过 20 项检查：从菜单加入恒山派、确认开局去重、
展示过滤奖励、检视后连续点击领取十次、回到组牌、再次奖励、长按
领取以及候选耗尽时跳过奖励。使用独立测试存档，未修改玩家音量默认值。
开局、奖励和领取后三张截图已检查，日志无运行时错误。

一次独立只读审查未发现实质问题。可选昆仑门派尚未注册的边界、
指定保底奖励与副牌维持原行为均符合已确认设计。
验证日志、截图与流程脚本保存在
`.summer/local/cross-sect-namesakes-20261004/`。
