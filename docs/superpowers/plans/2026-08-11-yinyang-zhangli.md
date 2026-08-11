# 阴阳掌力与 −1 点数规则实现计划

日期：2026-08-11

设计依据：`docs/superpowers/specs/2026-08-11-yinyang-zhangli-design.md`

## Task 1：建立聚焦失败夹具

**文件：**

- 新增：`tests/test_yinyang_zhangli_abilities.gd`
- 修改：`tools/run_tests.ps1`

1. 增加四边全 `-1`、单边 `-1`、普通零点牌夹具。
2. 断言阴阳掌力 3/4 已声明非空的通用能力数据。
3. 断言 `CardView` 对完整 `-1` 哨兵隐藏四个点数标签，但普通牌及单边
   `-1` 仍显示点数。
4. 断言相邻普通非负点数可攻击完整 `-1` 敌方。
5. 断言直接正负点数变化不修改哨兵且不产生事件。
6. 断言带 `limit = 2` 的点数选择跳过哨兵并选择后续合法实例。
7. 在实现前运行新套件，确认因缺少规则而失败。

## Task 2：实现通用 −1 点数语义

**文件：**

- 修改：`scripts/duel_rules.gd`
- 修改：`scripts/card_view.gd`
- 修改：`scripts/duel_card_selector.gd`
- 修改：`scripts/duel_ability_executor.gd`
- 修改：`scripts/card_catalog.gd`
- 修改：`tests/test_card_catalog.gd`
- 扩展：`tests/test_yinyang_zhangli_abilities.gd`

1. 在纯规则层增加四边全 `-1` 判定与点数可变判定。
2. `CardView` 只对完整哨兵隐藏四个既有标签，不更改卡图、标题、内力、
   检查或暗牌逻辑。
3. 新增 selector condition：所选卡牌点数可改变。
4. `ACTION_CHANGE_POWERS` 在执行器中拒绝完整哨兵，作为所有引用路径的最终防线。
5. 把所有 selected-card 点数变化声明补上新条件，使 `limit` 在过滤后计算。
6. 目录验证拒绝缺少该条件的 selected-card 点数变化 wrapper，防止未来遗漏。
7. 运行目录、规则、新聚焦套件和现有万岳/大嵩阳测试。

## Task 3：实现距离两格攻击修饰

**文件：**

- 修改：`scripts/card_catalog.gd`
- 修改：`scripts/duel_abilities.gd`
- 修改：`scripts/duel_rules.gd`
- 扩展：`tests/test_yinyang_zhangli_abilities.gd`

1. 新增通用正交距离两格攻击 modifier，布尔字段声明是否允许中间友方。
2. 目录验证 modifier 类型、字段和布尔值。
3. `DuelRules` 以卡牌当前能力枚举相邻与两格目标；维持上、右、下、左顺序。
4. 三级只允许中间空格；四级允许中间空格或当前友方；中间敌方始终阻挡。
5. 两格攻击继续用朝向目标的对应攻防边严格比较，不建立第二套攻击结算。
6. 覆盖四向、边界、横向跨行、所有权变化和 modifier 叠加的四级超集行为。

## Task 4：实现非递归再攻原语

**文件：**

- 修改：`scripts/card_catalog.gd`
- 修改：`scripts/duel_triggers.gd`
- 修改：`scripts/duel_ability_executor.gd`
- 修改：`scripts/duel_simulator.gd`
- 扩展：`tests/test_yinyang_zhangli_abilities.gd`

1. 新增“当前攻击不是重复攻击”触发条件。
2. 为 `ACTION_STANDARD_ATTACK_WITH_SELF` 增加经过验证的纯数据
   `repeat_attack` 布尔字段。
3. 标记随 attack request 进入模拟器，并放入对应 `TRIGGER_CARD_AFTER_ATTACK`
   上下文。
4. 阴阳掌力授予能力只在非重复攻击后请求一次带标记的完整标准攻击。
5. 第二次攻击重新读取精确实例、位置、拥有者与合法目标；不阻止其他攻击后规则。
6. 覆盖无目标、移动、离场、翻面失去能力、其他攻击后能力仍响应和无第三次攻击。

## Task 5：允许有序能力在自我移除后继续

**文件：**

- 修改：`scripts/duel_card_selector.gd`
- 修改：`scripts/duel_ability_executor.gd`
- 扩展：`tests/test_yinyang_zhangli_abilities.gd`

1. 复用能力开始时的纯数据来源快照，保留结算拥有者而不保留节点或 live Dictionary。
2. 抽牌动作只在精确能力来源已经按本规则自我移除时回退到快照拥有者。
3. 选择器在来源离场后可用快照拥有者完成 ally/enemy、weapon 和 not-source 条件；
   任何需要实时棋盘位置的条件在来源离场后失败，不使用陈旧位置。
4. 保持 `card_exiled`、`card_drawn`、`ability_gained` 的严格事件顺序。
5. 覆盖空牌库、无掌法、新抽到掌法、来源提前被其他效果移除和不同拥有者。

## Task 6：声明阴阳掌力 3/4

**文件：**

- 修改：`scripts/card_catalog.gd`
- 扩展：`tests/test_yinyang_zhangli_abilities.gd`
- 扩展：`tests/test_card_catalog.gd`
- 扩展：`tests/test_duel_simulator.gd`

1. 定义共享非递归再攻能力和三级/四级距离修饰能力。
2. 为两张卡声明自身进场后规则：自我移除、抽一张、选择当前手牌友方掌法并授予。
3. 三级和四级共享完全相同的再攻能力，利用结构去重防止叠加。
4. 四级范围为三级超集；先后授予任意顺序都保持四级效果。
5. 验证授予只影响当时手牌精确实例，翻面后按非保留规则丢失。
6. 验证自身离场后不进行普通进场攻击，AI/回放均走同一 transition。

## Task 7：表现与集成覆盖

**文件：**

- 扩展：`tests/test_card_inspector.gd` 或聚焦 `CardView` 夹具
- 扩展：`tests/test_duel_integration.gd`（仅在生产呈现路径需要额外断言时）
- 修改：`docs/HANDOFF.md`
- 修改：`docs/ARCHITECTURE.md`
- 修改：`docs/DECISIONS.md`
- 修改：`docs/ADDING_CARDS_AND_ABILITIES.md`
- 修改：`docs/AI_SEARCH.md`
- 修改：`docs/TESTING.md`

1. 验证已揭示手牌和场上阴阳掌力不显示点数，暗牌仍不泄漏数据。
2. 验证控制器按纯数据事件呈现自我渐隐、抽牌、能力同步和两次攻击。
3. 更新通用 −1 点数、selector 合法性、远程攻击与 repeat attack 上下文文档。
4. 说明搜索仍为卡牌无关，状态键通过 active abilities/modifiers 区分授予状态。

## Task 8：完整验证与实际走查

1. 运行聚焦套件：目录、规则、选择器、执行器、阴阳掌力、模拟器和表现测试。
2. 运行完整命令：

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
   ```

3. 在 540×960 运行生产路径，走查：
   - 阴阳掌力数字隐藏；
   - 自我移除后抽到掌法并获得能力；
   - 三级隔空攻击与四级隔友攻击；
   - 第二次攻击重新读取棋盘且不产生第三次攻击；
   - 紫霞功跳过阴阳掌力并选择下一合法目标。
4. 检查 Summer diagnostics、console 与 debugger，确认无新增错误或警告。
5. 运行 `git diff --check` 并核对只包含本任务及已存在的用户改动。
