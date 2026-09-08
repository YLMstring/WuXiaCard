# 目录累计平衡改动实施计划

依据：`docs/superpowers/specs/2026-09-08-catalog-balance-abilities-design.md`

## 1. 先更新测试契约

- 在 `tests/test_card_catalog.gd` 更新 `KuiHua1` 的旧结束阶段断言，增加新原语字段的合法/非法声明验证，并确认 `FeiTian5` 的目录结构。
- 在 `tests/test_hanbin_tianwai_abilities.gd` 改为结束阶段全手牌减点与零内力结束阶段翻面，并覆盖有内力、刚失去最后内力、四边 `-1`、同批动画事件。
- 在 `tests/test_dugu_nine_swords_abilities.gd` 覆盖未来抽牌揭示、任意武器待失效、保留能力、空能力消耗层，以及保留点数的太祖长拳变身。
- 在 `tests/test_kuihua_abilities.gd` 把一阶测试改为旧料敌机先的双方返回流程和自宫门槛。
- 在 `tests/test_laihe_qinquan_abilities.gd` 覆盖四阶开局揭示与五阶主动指定永久失效/揭示奖励。
- 在 `tests/test_internal_energy_abilities.gd` 把逐点分配改成其它友方各获得来源当前内力，并覆盖零内力、四边 `-1` 与无主动能力目标。
- 更新仍直接断言旧 `KuiHua1` 行为的 `tests/test_duel_simulator.gd`、`tests/test_duel_integration.gd` 和额外出牌上限 fixture。

## 2. 扩展目录声明与验证器

- 在 `scripts/card_catalog.gd` 注册 `VALUE_CARD_KI`、`ACTION_PERMANENTLY_REMOVE_NON_RETAINED_ABILITIES`、`CONDITION_SELECTED_CARD_REVEALED_TO_SELF`。
- 让 `CONDITION_KI_AT_LEAST` 接受可选布尔 `inverted`，让 `ACTION_TRANSFORM_CARD` 接受可选布尔 `preserve_powers`，让 `ACTION_GAIN_KI` 接受合法 `VALUE_CARD_KI` 数值规格。
- 按规格替换十一张牌的完整 `abilities` 声明，删除已经不再被引用的旧来鹤/岱宗声明。

## 3. 扩展原生编译表示

- 在 `native/duel_core/src/duel_native_compact_kernel.h` 增加动作 opcode、动作条件 opcode，以及动态内力/保留点数所需的紧凑字段。
- 在 `native/duel_core/src/duel_native_compile.cpp` 严格编译并拒绝畸形声明；保持所有省略字段的旧默认语义。

## 4. 实现原生结算

- 在 `native/duel_core/src/duel_native_events.cpp`/`duel_native_actions.cpp` 执行反转内力条件与选择牌揭示条件。
- 在加内力前解析 `VALUE_CARD_KI`，零值为无效果。
- 实现精确目标的永久非保留能力删除并复用既有 `ability_lost` 事件。
- 让变身在 `preserve_powers` 时跳过四边点数覆盖。
- 删除待失效消费中的心法跳过特例，不改状态字段。

## 5. 编译与分层验证

- 运行目录、寒冰、独孤九剑、葵花、来鹤和内力专项测试，先观察预期失败，再编译原生 Debug DLL 并修至通过。
- 运行 `test_native_production_rules.gd` 及所有受旧 `KuiHua1` fixture 影响的集成测试。
- 运行完整 `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`。
- 静音启动游戏，在 portrait 视口实际验证主动指定、结束阶段、进场前和翻面后各一个场景；不修改玩家正常音频默认值。

## 6. 收尾

- 更新 `docs/HANDOFF.md` 与必要的 `docs/DECISIONS.md`/`docs/ADDING_CARDS_AND_ABILITIES.md`，记录新增通用原语和十一张牌的新权威行为。
- 检查工作树，只提交本任务文件，并报告测试结果、原生库重编结果和剩余风险。
