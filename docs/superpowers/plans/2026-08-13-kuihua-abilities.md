# 挥剑自宫与葵花牌组能力实施计划

## 目标

按 `docs/superpowers/specs/2026-08-13-kuihua-abilities-design.md` 实装
`KuiHua0–4`，保持模拟器权威、搜索卡牌无关，并统一修正“被攻击时”“攻击后”、
全局能力门控、不分敌我的攻击归属、重新进场与逐格移除复制规则。

所有 GDScript 新增接口使用显式类型。规则层不得读取场景节点、存档对象或按葵花卡牌 ID
分支；生产控制器只负责把存档解锁结果转换为对局初始纯数据并展示模拟器事件。

## 任务 1：建立基线与失败用例

文件：

- 新建 `tests/test_kuihua_abilities.gd`
- 修改 `tools/run_tests.ps1`
- 必要时修改现有攻击后、阴阳掌力和状态键测试

步骤：

1. 运行完整基线测试，记录用户最近目录改动造成的既有失败，不把预存失败误算为本次回归。
2. 固定 `KuiHua1–4` 非空目录声明、卡牌级门控和 `KuiHua0–4` 默认解锁状态。
3. 为玩家门控开关、敌方默认开启、翻面后的当前拥有者门控、状态复制和状态键写失败用例。
4. 为零目标不触发攻击后、至少一个 `attack_started` 才触发一次、被攻击阶段令目标离场仍
   触发攻击后写失败用例。
5. 为四张牌的主要成功路径、失败路径、实例身份与事件顺序写失败用例。

## 任务 2：通用能力门控与生产初始化

文件：

- 修改 `scripts/card_catalog.gd`
- 修改 `scripts/duel_state.gd`
- 修改 `scripts/duel_state_key.gd`
- 修改 `scripts/duel_abilities.gd`
- 修改 `scripts/duel_triggers.gd`
- 修改 `scripts/duel_targeting.gd`
- 修改 `scripts/duel_simulator.gd`
- 修改 `scripts/duel_controller.gd`
- 修改目录、状态、搜索与回放测试

步骤：

1. 注册 `EFFECT_GATE_SELF_CASTRATION`，允许卡牌级 `effect_gate`，拒绝未知或错误类型声明。
2. 给 `DuelState` 增加双方门控集合，并纳入深复制和状态键。
3. 提供通用的“当前拥有者是否启用卡牌效果”查询；触发发现与重验、修正读取、主动能力
   枚举和合法动作生成统一调用，门控关闭时不删除 `active_abilities`。
4. 对局创建时从档案解锁快照设置玩家门控，敌方固定开启；回放使用已保存状态，不重复
   读取存档。
5. 证明 AI 克隆、贪心和深度搜索不会把门控不同的状态合并。

## 任务 3：统一攻击后边界

文件：

- 修改 `scripts/duel_simulator.gd`
- 修改 `tests/test_yinyang_zhangli_abilities.gd`
- 修改所有依赖零目标攻击后旧语义的测试

步骤：

1. 普通标准攻击记录本轮是否至少成功进入一个 `_resolve_attack_target` 并产生
   `attack_started`。
2. 只有该标记为真时才结算一次 `TRIGGER_CARD_AFTER_ATTACK`；多目标仍只结算一次。
3. 定向攻击采用相同判断；初始攻击合法但在 `CARD_BE_ATTACKED` 后失效仍算确实攻击。
4. 更新阴阳掌力零目标测试，确认首次零目标不会请求重复攻击。
5. 回归天长掌法、恒山反击、金针和其他现有攻击后规则。

## 任务 4：不分敌我的通用攻击策略

文件：

- 修改 `scripts/card_catalog.gd`
- 修改 `scripts/duel_abilities.gd`
- 修改 `scripts/duel_rules.gd`
- 修改 `scripts/duel_simulator.gd`
- 扩展 `tests/test_kuihua_abilities.gd`

步骤：

1. 注册非保留的通用全局攻击策略修正，表达“指定一方的敌方攻击可选择友方目标，成功
   翻面归指定一方”。
2. 标准攻击开始时从当前有效能力收集一份卡牌无关策略；多个相同阵营来源合并为同一策略。
3. 泛化目标收集与范围/点数检查，使策略可允许同阵营目标；普通路径保持只攻击敌方。
4. `CARD_BE_ATTACKED` 后重检和最终翻面继续使用同一策略，避免同阵营目标被默认检查取消。
5. 覆盖四方向顺序、距离二、点数不足、多来源幂等、来源翻面/离场/门控关闭后恢复默认。

## 任务 5：泛化精确卡牌重新进场

文件：

- 修改 `scripts/card_catalog.gd`
- 修改 `scripts/duel_ability_executor.gd`
- 修改 `scripts/duel_simulator.gd`
- 修改绵里藏针相关测试
- 扩展 `tests/test_kuihua_abilities.gd`

步骤：

1. 将 `ACTION_RESUMMON_TRIGGER_CARD_IN_PLACE` 泛化为带 `card` 引用的
   `ACTION_RESUMMON_CARD_IN_PLACE`。
2. 精确定位目标当前实例和格子，无移除区写入地令旧实例离场，并请求同目录 ID、当前拥有者
   的全新实例在原格完整进场。
3. 复用 `card_departed_for_resummon` 与现有召唤事件；错误引用、离场目标或占用格返回
   `NO_EFFECT`。
4. 绵里藏针改用 `CARD_REF_TRIGGER_CARD` 并保持所有既有时序。
5. 飞燕穿柳使用 `CARD_REF_ABILITY_SOURCE`，验证连锁生成唯一实例且旧实例不进移除区。

## 任务 6：声明并实现 `KuiHua1–3`

文件：

- 修改 `scripts/card_catalog.gd`
- 修改 `scripts/duel_triggers.gd`
- 修改 `scripts/duel_ability_executor.gd`
- 扩展 `tests/test_kuihua_abilities.gd`

步骤：

1. 天人化生声明回合结束额外出牌，复用现有请求合并和额外出牌边界。
2. 钟馗抉目声明被成功攻击时返回、翻面保留的最小防御点数攻击修正，以及实际攻击后幂等
   授予不分敌我规则。
3. 增加通用条件“本次攻击翻动了攻击前的敌方”，使用 `attack_flips` 中的旧拥有者与攻击者
   开场拥有者比较。
4. 飞燕穿柳声明恰好一个相邻敌方时交换，交换后由召唤管线标准攻击；攻击后满足条件则
   重新进场。
5. 覆盖满手返回移除、交换失败停止、没有翻面不重进场，以及门控关闭时所有效果无效。

## 任务 7：声明并实现 `KuiHua4`

文件：

- 修改 `scripts/card_catalog.gd`
- 必要时泛化 `scripts/duel_ability_executor.gd` 的动作上下文引用
- 扩展 `tests/test_kuihua_abilities.gd`

步骤：

1. 声明被成功攻击时返回手牌。
2. 声明进场后先抽一张，再按 `0..8` 选择当前友方且原始拥有者为敌方的场上牌。
3. 每个目标先以现有 `ACTION_EXILE_SELF` 标准移除，再在其初始格用能力来源的
   `CARD_SPEC_FRESH_COPY` 执行 `ACTION_SUMMON_CARD`。
4. 保证选择目标离场后，动作上下文仍能解析其初始格和原始能力来源；移除失败时不得生成。
5. 覆盖逐张复制完整进场、抽牌先后、满手/空牌库、实例重检、来源状态变化和递归终止。

## 任务 8：表现、文档与完成验证

文件：

- 必要时修改 `scripts/duel_controller.gd`
- 新建或扩展葵花集成测试
- 修改 `docs/HANDOFF.md`
- 修改 `docs/DECISIONS.md`
- 修改 `docs/ADDING_CARDS_AND_ABILITIES.md`
- 修改 `docs/TESTING.md`

步骤：

1. 复用返回手牌、交换、移除、抽牌、能力获得、重新进场和生成牌表现；只在现有事件缺少
   必需字段时扩展纯数据事件，不添加卡牌 ID 分支。
2. 集成验证门控关闭、钟馗同阵营攻击归属、飞燕攻击结束后重进场、群邪逐张移除复制。
3. 更新规则文档中的能力门控、攻击后边界、通用重新进场声明和四张牌完整能力。
4. 运行聚焦目录、模拟器、搜索、回放和控制器套件。
5. 运行 `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`。
6. 启动生产主场景，在 `540×960` 竖屏路径实际游玩并检查动画顺序、回放一致性和控制台。
7. 运行 `git diff --check`，检查工作区只包含本次实现及用户原有改动；不提交实现，交由用户
   审阅提交。
