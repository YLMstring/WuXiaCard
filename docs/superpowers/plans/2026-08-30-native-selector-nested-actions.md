# 原生选择器、嵌套动作与运行时能力实施计划

**设计：**
`docs/superpowers/specs/2026-08-30-native-selector-nested-actions-design.md`

**目标：** 在不接入生产路径、不增加卡牌 ID 分支的前提下，为测试专用 C++ 紧凑
状态原型实现通用选择器、递归子动作、改点、内力、非攻击翻面和动态授予能力，并把
14 个真实 Quick 开局的原生支持数从当前 `271/490` 提高，同时保持所有受支持分支
与 `DuelSimulator` 逐状态、逐事件零差异。

## 工作规则

- 复用本任务最近一次完整 70 套件通过作为代码改动前基线；设计提交之后没有相关
  生产代码变化，不重复跑基线。
- 先写权威 GDScript 触发换位的失败回归，再修改规则实现。
- `DuelSimulator` 始终是唯一规则权威和原生 oracle。
- 原生代码只编译通用声明，不检查卡牌 ID、名称、门派或 Quick 对局名称。
- 每个原生出牌继续在私有分支执行；未知声明不得返回部分状态或事件。
- 每完成一个可独立验证的阶段，先运行最小聚焦测试或原生探针，再进入下一阶段。
- 原生支持数上升不是正确性的替代品；accepted mismatch 必须始终为零。
- 不运行 Extended 强度赛程，也不把原生路径接入生产搜索。
- 可见测试使用 Dummy 音频或静音总线，不修改正常音频默认值。

## 任务一：修正权威触发器的能力换位语义

**新增：**

- `tests/test_duel_trigger_revalidation.gd`

**修改：**

- `scripts/duel_triggers.gd`
- `scripts/duel_ability_executor.gd`
- `scripts/duel_abilities.gd`
- `tools/run_tests.ps1`

### Red

1. 构造一张有两个 `CARD_AFTER_SUMMONED` 能力的测试牌：第一个能力执行
   `ACTION_REMOVE_THIS_ABILITY`，第二个能力抽一张牌。
2. 当前实现发现两个触发后，第一个能力删除自身会令第二个能力从下标 1 移到 0；
   断言第二个能力仍触发并抽牌。现有下标重验应使该测试失败。
3. 增加反例：第一个触发令来源翻面并真正失去第二个非保留能力，第二个触发必须取消。
4. 断言 `ability_triggered`、`ability_lost` 和抽牌事件顺序准确。

### Green

1. 触发发现继续保存发现时能力下标和完整能力快照，同时保存事件窗口内的能力条目
   引用身份。
2. `_get_current_rule()` 先检查原下标，再按引用身份寻找换位后的同一条目；不得只按
   结构相等把后来重新获得的能力当成旧触发来源。
3. 向动作上下文同时写入：
   - `resolving_ability_index`：发现时下标，继续用于批次 ID；
   - `resolving_ability_current_index`：重验后的当前下标，用于删除。
4. `ACTION_REMOVE_THIS_ABILITY` 使用当前下标，并再次确认引用身份。
5. 所有能力数组增删帮助函数只复制数组容器，保留未变能力 Dictionary 的引用；新授予
   或恢复能力仍建立新的不可变 Dictionary 引用。
6. 不向目录声明、卡牌数据、存档或状态键添加能力 ID。

### Verify

- 单独运行 `test_duel_trigger_revalidation.gd`。
- 运行现有 `test_card_catalog.gd` 和 `test_duel_simulator.gd`。
- 运行 `git diff --check`。

## 任务二：把原生能力状态改为有序运行时条目

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 新增不可变的单能力编译池和每个能力集合对应的有序能力池编号数组。
2. 新增 `RuntimeAbilityEntry`，至少保存编译能力池编号和分支局部临时句柄；每张运行时
   卡牌保存有序条目数组。
3. 加载紧凑 payload 时，从 `active_ability_set_pool` 构建并按结构驻留单能力池；相同
   声明内容共享编译项，数组中的每个出现位置仍有独立运行时条目。
4. 分支复制保留现有条目句柄；新授予或恢复条目分配新句柄。句柄不参与规范状态键，
   也不跨完整出牌边界输出。
5. 把能力存在、主动能力、修饰器、事件发现、翻面清理和
   `remove_this_ability` 的查询从 root set + enabled bitmap 迁移到有序条目数组。
6. 删除能力时真实 `erase` 条目；保留能力清理时稳定保持原相对顺序。
7. 输出 payload 时按卡牌当前条目顺序物化能力数组，驻留到输出
   `active_ability_set_pool` 并写回 set index。
8. 校验和只吸收有规则意义的有序能力池编号，不吸收临时句柄。

### Verify

- 先保持现有原生声明范围不变，构建 GDExtension。
- 运行完整 `duel_native_compact_probe.gd`，要求原有 754 项及 `271/490` 覆盖保持
  零差异。
- 比较能力删除、翻面保留和输出恢复的状态键与事件，确认纯表示重构没有行为变化。

## 任务三：建立递归动作编译器与执行上下文

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 把现有内联动作解析提取为 `compile_action()`，把条件和能力解析分别提取为有明确
   失败标记的帮助函数。
2. `CompiledAction` 增加：
   - 子动作数组；
   - 可选选择器；
   - 卡牌/所属方引用；
   - 固定或动态数值；
   - `power_change_batch_group`；
   - `STOP_RULE`；
   - 可选授予能力池编号。
3. 未知字段、错误类型、非法空子动作或未支持动作编译为 `UNSUPPORTED`，而不是忽略
   多余字段。
4. 新增 `ActionContext`，分离最初能力来源、当前主体、选中牌、触发牌、攻击者、
   攻击翻面实例集合及事件/能力/触发器/动作位置。
5. `execute_actions()` 按序执行递归节点，并区分：
   - `APPLIED`；
   - `NO_EFFECT`；
   - `INVALID_CONTEXT`；
   - `UNSUPPORTED`。
6. 先用已有抽牌、移除、阻止翻面和移除当前能力动作证明新执行器与旧平铺路径事件
   完全一致，再删除旧内联分支。

### Verify

- 原生构建通过。
- 原有原生探针全部通过，Quick 支持数和拒绝分类暂时允许不变。
- 新增合成测试证明未知嵌套动作拒绝整个私有分支且不泄漏部分结果。

## 任务四：实现完整通用选择器

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 编译四个区域、手牌反向顺序、`limit`、`required_count` 和全部现有选择条件。
2. 扫描顺序严格复刻 `DuelCardSelector`：
   - 手牌来源方在前，按物理槽排序；
   - 场上 `0..8`；
   - 弃牌/移除区来源方在前，保持数组顺序。
3. 快照去重后的精确 card index/instance；达到 `limit` 时按权威规则处理
   `required_count`。
4. 每个目标执行前跨区域重新定位，并只重验声明条件；失败目标跳过，不补选。
5. 活跃来源已离场时使用事件开始保存的来源快照；移除区中的来源不取代该快照。
6. 每个目标创建子上下文：当前主体和 selected card 指向目标，ability source 保持
   原来源。
7. 攻击上下文从布尔 `attack_flipped_enemy` 扩展为同时保存本次攻击实际翻面的精确
   card index 集合，用于 `FLIPPED_BY_CURRENT_ATTACK`。
8. `CAN_SPEND_KI` 使用当前运行时主动能力和效果门控；资源转移条件只判断合法性，
   本阶段不执行转移动作。

### Verify

- 合成测试覆盖四区域顺序、手牌空槽、反向、去重、数量、相邻/包围、原所属方、
  四边 `-1`、上一张出牌、可耗内力和资源条件。
- 覆盖重验跳过、不补选、来源离场快照和每目标完整子动作顺序。
- 所有新增合成结果逐事件对照 `DuelSimulator`。

## 任务五：实现改点、批次和归零移除

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 编译固定非零整数和现有手牌计数动态值。
2. 解析 selected/source/trigger/attacker 精确卡牌引用；目标缺失时返回 `NO_EFFECT`。
3. 四边全 `-1` 返回无效果；普通四边逐边加减并下限归零。
4. 生成与权威实现字段完全相同的 `powers_changed`。
5. 负向变化得到四个零时，以 `power_reached_zero` 调用现有完整 exile 生命周期；
   `powers_changed` 必须先于移除链。
6. 按发现时事件、能力、触发器和动作位置生成精确 `power_change_batch_id`；选择器外层
   为所有子目标统一补批次，显式 group 可跨动作位置合并。
7. 给相同批次的 `powers_changed` 和连带 `card_exiled` 同时写入批次字段。

### Verify

- 固定加减、动态手牌数、手牌和场上目标、下限零、四边 `-1`。
- 一次选择器多目标共享批次、不同动作不同批次、显式 group 合并。
- 归零移除前/后监听器、事件顺序和拒绝原子性。

## 任务六：实现内力事件、翻面和动态授予能力

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 实现固定正整数 `GAIN_KI`/`SPEND_KI`，支持缺省当前主体及四种卡牌引用。
2. 内力不足返回 `NO_EFFECT`；成功生成完整 `ki_changed` 后立即派发
   `CARD_KI_CHANGED`，再继续下一动作。
3. 编译并执行 `KI_CHANGED_CARD_IS_SELF`、`KI_REACHED_ZERO` 和带 amount 的
   `KI_AT_LEAST`。
4. 实现 `FLIP_SELF` 的相对所属方解析，并复用原生现有 before/prevent/flip/after/
   cleanup 生命周期；当前主体不在场或所属方已经相同时无效果。
5. 编译授予动作中的嵌套能力声明，并允许其包含暂未支持的未来节点。
6. 被动授予按编译能力结构去重并追加；主动授予删除所有当前主动条目、保留被动后
   追加新主动。实际变化才发 `ability_gained`。
7. 新授予能力若立即提供已支持修饰或当前事件触发，按正常事件重验；未知部分只有在
   实际抵达时拒绝。
8. 保持多个先天主动能力的目录顺序；不把“动态授予替换全部主动”错误推广到初始
   能力加载。

### Verify

- 内力增加、消耗、余额不足及逐张选择目标。
- `CARD_KI_CHANGED` 在下一动作前触发，并可导致非攻击翻面。
- 翻面阻止、所有权变化、保留能力和延迟自身翻面后能力。
- 被动重复、被动追加、三项先天主动保留、动态主动全部替换。
- 含未知未来动作的授予成功，未知事件实际抵达时分支原子拒绝。

## 任务七：真实 Quick 覆盖与拒绝分析

**修改：**

- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 保持完全相同的 14 个真实 Quick 开局和 490 个合法根出牌。
2. 除总体拒绝原因外，增加按来源卡牌 ID 和首个拒绝原因的诊断汇总；仅用于测试输出，
   不进入生产代码。
3. 对每个受支持分支继续比较：valid、完整恢复状态、规范状态键、state version、
   captures、exiles 和事件数组。
4. 要求：
   - supported 大于 271；
   - exact parity 等于 supported；
   - mismatches 为零；
   - unsupported 分支无部分结果。
5. 若支持数没有上升，按新诊断找出仍挡在已实现声明前的首个门槛；不以放宽 gate 或
   跳过事件伪造提升。
6. 记录本阶段实际解锁的卡牌/动作族，以及剩余拒绝中 turn boundary、movement、
   suppression、discard、nested attack 和其它类别的数量。

## 任务八：性能、完整回归、文档和提交

**修改：**

- `docs/AI_SEARCH.md`
- `docs/HANDOFF.md`
- `native/duel_core/README.md`
- 如测试总数变化，更新相应测试文档。

步骤：

1. 运行原生构建和完整紧凑状态探针。
2. 重跑 5,000 次普通已覆盖出牌基准，报告相对 GDScript 倍率；再增加至少一个真正
   经过选择器和改点/授予能力的复杂路径基准，避免只测旧快路径。
3. 重跑 100,000 次分支复制基准，记录有序运行时能力条目对复制吞吐的影响。
4. 不使用固定 3% 淘汰线，但任何异常数量级回退必须先定位并修复或明确报告。
5. 运行 `git diff --check`。
6. 运行完整：

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
   ```

7. 文档记录：新支持 opcode/selector、权威触发换位规则、最新 Quick 覆盖和拒绝分类、
   探针检查数、性能结果、仍禁止生产采用的原因。
8. 自审只检查本任务改动，确认没有生产路径引用 native 扩展、没有卡牌 ID 分支、没有
   无关文件或构建产物进入提交。
9. 提交一个聚焦实现提交；不推送、不发布、不打标签。

## 停止条件

- 权威触发换位测试无法明确区分“能力仍存在”和“能力重新获得”时，先修正运行时
  句柄方案，不用结构相等近似。
- 任一原生 accepted 分支与权威状态或事件不同，停止扩大覆盖并修复该最小差异。
- 未支持分支返回部分结果时立即停止；原子拒绝优先于覆盖率。
- Quick 支持数未超过 271 时，不把本阶段宣布为覆盖提升完成。
- 完整套件失败时不提交实现完成状态。
