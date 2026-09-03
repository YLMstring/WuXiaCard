# 原生搜索树第一阶段优化实施计划

日期：2026-09-03
设计：`docs/superpowers/specs/2026-09-03-native-search-ordering-phase-one-design.md`

## 工作规则

- `DuelNativeCompactKernel` 继续是唯一规则和深度搜索实现。
- 固定深度评分与规范根动作一致是硬门槛；任何差异先修正，不用胜率或十秒结果掩盖。
- 复用刚完成的四局阶段前基线，不在改代码前重复运行：
  - 新深度：`.summer/local/ai-benchmarks/production-opening-depth-extra-play-cap-1788438499.json`；
  - 老深度：`.summer/local/ai-benchmarks/production-opening-depth-extra-play-cap-1788438579.json`。
- 高精度分项计时只在 benchmark 显式开启，生产默认关闭。
- 每个优化通过开关独立消融；无稳定收益或有正确性回归的候选不进入生产默认。
- 聚焦测试和微基准可在每个任务后运行；完整套件只在全部行为改动完成后运行一次。
- 所有引擎运行使用 `--audio-driver Dummy`，不播放音乐或音效。
- `.summer/local/ai-benchmarks/` 报告不进入版本控制。

## 任务一：建立原生排序消融与诊断契约

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `scripts/duel_native_rules.gd`
- `scripts/duel_search.gd`
- `tests/test_duel_search.gd`
- `tests/test_native_production_rules.gd`
- `tests/benchmarks/production_opening_depth_profile.gd`

### Red

1. 增加测试，要求同一原生 minimax 接受：
   - `use_internal_pv_ordering`；
   - `use_history_ordering`；
   - `collect_search_diagnostics`。
2. 验证默认搜索结果继续包含现有节点、动作、transition、cutoff 和深度字段。
3. 验证关闭诊断时新增高频计时字段为零或明确缺省，开启后字段存在且非负。
4. 验证 GDScript 包装层完整转发三个选项，不改变深度模式、预算或评估器。

### Green

1. 在原生 `NativeSearchLimits`/搜索入口接入三个布尔选项。
2. 先只接线，不改变动作顺序：PV/history 开关暂不产生效果。
3. 扩展 `NativeSearchStats` 和结果 Dictionary，加入合法动作生成、排序、transition、评价、状态键与 cutoff 桶字段。
4. 所有时钟调用放在 `collect_search_diagnostics` 条件内；关闭时热循环只保留现有整数计数。
5. 将新增字段转发到进度快照、最终结果和开局报告。

### Verify

1. 构建 Windows Debug 原生库：

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/build_duel_native.ps1 -Configuration Debug -GodotCppTarget template_debug
   ```

2. 运行 `test_duel_search.gd` 与 `test_native_production_rules.gd`。
3. 用一个短预算开局诊断确认计时字段不再全为零；此处不运行正式四局十秒基准。

## 任务二：优化排序热路径但保持现有顺序

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/test_native_production_rules.gd`

### Red

1. 增加包含主动能力、普通出牌、相同结构分和平分规范键的排序夹具。
2. 保存当前结构排序的完整动作顺序作为预期。
3. 增加重复调用测试，要求动作顺序完全确定。

### Green

1. 为每个动作一次性计算 PV 标记、history 分和结构分，比较器只读取缓存值。
2. 将 `order_search_actions()` 改为按值接收 vector；调用处移动交付合法动作结果，去掉完整复制。
3. 消除同一来源动作间冗余的 `StringName` 到 `String` 转换。
4. PV 完整匹配继续比较动作类型、来源位置、来源实例、目标种类、目标位置和主动能力序号。
5. 最终平局仍调用规范动作比较，现有动作顺序不得变化。

### Verify

1. 运行排序夹具和固定深度搜索测试。
2. 使用开启诊断的固定节点探针比较 `time_order_usec` 与 nodes/s。
3. 若排序耗时或总吞吐稳定退化，先停止并分析，不继续叠加后续排序策略。

## 任务三：增加快速合法动作计数

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/test_native_production_rules.gd`
- 必要时扩展现有原生真实状态探针，不新建第二套规则夹具。

### Red

1. 从真实 Quick 开局及派生状态收集双方状态，覆盖：
   - 普通手牌出牌；
   - 无空位；
   - 已获得额外出牌后的仅手牌行动；
   - 多个主动能力；
   - 棋盘和手牌目标；
   - 无法支付内力；
   - 无合法目标。
2. 对每个状态和双方断言快速计数等于完整动作 vector 长度。

### Green

1. 实现 `count_legal_native_actions()`，与完整生成共享或逐项复用同一合法性辅助函数。
2. 计数路径不创建 `NativeAction`、不复制实例 ID、不保存目标 vector；目标规则若只能返回 vector，先增加只计数的通用内部适配。
3. `evaluate_baseline()` 的双方 mobility 项改用快速计数。
4. 真正展开节点、控制器查询和动作物化继续使用完整动作生成。

### Verify

1. 运行全部计数等价夹具。
2. 运行固定深度评分和动作测试。
3. 用同一固定节点探针比较 `time_evaluate_usec` 与 nodes/s。
4. 完成任务二和三后，运行第一次正式四局：

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_production_opening_profile.ps1 -BudgetSeconds 10 -OpeningSet extra_play_cap -DepthMode self_turn
   ```

5. 记录四局深度、深度二耗时或根动作进度、nodes/s 和分项时间。

## 任务四：实现树内 PV 排序

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/test_duel_search.gd`
- `tests/test_native_production_rules.gd`

### Red

1. 构造至少两层内部节点，证明当前实现只有根动作获得上一轮优先级。
2. 增加候选测试：完整完成较浅迭代后，较深迭代在相同内部局面优先上一轮动作。
3. 增加非法/过期提示测试，要求忽略提示并回到 history/结构/规范排序。
4. 增加被取消或超时的迭代测试，要求其局部最佳动作不升级为下一轮提示。
5. 对 `use_internal_pv_ordering=false/true` 做固定深度评分和规范动作等价。

### Green

1. 新增 state-only 排序提示键，与现有“局面＋剩余边界”的严格计划键分离。
2. 每个节点最多计算一次状态 checksum，并在两类键用途之间复用。
3. 维护上一完整迭代和当前迭代两张排序提示表。
4. 只有完整完成根迭代后才交换提示表；中断迭代直接丢弃。
5. 查到提示后在当前合法动作中做完整字段匹配，匹配成功才排第一。
6. 填写 PV 查询、命中、合法和非法诊断计数。

### Verify

1. 运行 PV 生命周期、非法提示和固定深度 A/B 测试。
2. 用固定节点探针比较 PV 开关两侧的节点数、cutoff 桶和时间。
3. 运行第二次正式四局新深度基准并保存报告。
4. 重点判断新深度一到二时 PV 命中覆盖是否如预期较低，不因收益有限擅自改变深度语义。

## 任务五：实现通用 History heuristic

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/test_duel_search.gd`
- `tests/test_native_production_rules.gd`

### Red

1. 验证 history 键不包含卡牌 ID、名称、运行时实例或物理手牌槽编号。
2. 验证通用状态特征完全相同的两张手牌可以共享 history。
3. 验证不同四边点数、内力、能力数量、目标或主动能力序号产生不同键。
4. 构造 cutoff，验证只有造成 cutoff 的动作获得奖励。
5. 验证奖励为 `(remaining_owner_turn_boundaries + 1)^2`、分数饱和且新公开深度迭代衰减到 `75%`。
6. 验证排序优先级严格为 PV、history、结构分、规范键。
7. 对 history 开关做固定深度评分和规范动作等价。

### Green

1. 实现紧凑、卡牌无关的 `HistoryKey` 及哈希。
2. History 表生命周期限制在一次根搜索调用内，不跨 AI 决策持久化。
3. 在真实 `beta <= alpha` cutoff 后更新对应动作。
4. 每个公开深度迭代开始时衰减所有条目；第一版不惩罚失败动作。
5. 将 history 分接入任务二的预计算排序记录。
6. 填写 history 查询、命中和 cutoff 诊断计数。

### Verify

1. 运行 history 键、奖励、衰减、排序与固定深度等价测试。
2. 固定节点比较 `use_history_ordering=false/true` 的节点数、cutoff 位置和 elapsed。
3. 运行最终正式四局新深度基准。
4. 对每局分别报告，不用四局平均掩盖风清扬先手对东方不败的困难局面。

## 任务六：正确性、内存与生产验证

**修改：**

- 仅在发现覆盖缺口或集成错误时修改相关测试/实现。

### Verify

1. 构建最新 Windows Debug 原生库。
2. 运行搜索和原生生产规则聚焦套件。
3. 运行现有重复搜索内存回归，确认工作集在搜索结束后回落，PV/history 表不跨调用累积。
4. 运行完整套件：

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
   ```

5. 以 Dummy 音频运行静音生产路径，确认普通 AI 行动、额外出牌续用/重搜、超时发布和界面深度显示正常。
6. 运行 `git diff --check`，确认没有基准 JSON、临时日志、构建目录或平台密钥进入版本控制。

## 任务七：记录证据与决定生产默认

**修改：**

- `docs/AI_SEARCH.md`
- `docs/HANDOFF.md`
- 必要时 `docs/TESTING.md`

### 步骤

1. 记录每项消融的固定深度一致性、节点变化、nodes/s、cutoff 桶和四局结果。
2. 只有满足正确性门槛且有稳定收益的 PV/history 开关才设为生产默认开启。
3. `collect_search_diagnostics` 保持生产默认关闭。
4. 记录未达到目标的局面及下一阶段应优先评估的方向，不把置换表、PVS 或近似剪枝提前混入本阶段。
5. 保留最终报告文件名，但不提交报告本身。

## 完成标准

- 快速合法动作计数与完整动作生成在覆盖状态中完全一致。
- 结构参考、PV 和 history 配置在固定深度得到相同评分及规范根动作。
- 四局无 fallback、unsupported 或无效动作，原先两局深度二完成不退化。
- 风清扬镜像目标为十秒内完成新深度二；风清扬先手对东方不败目标为线性估算十八秒或更低。
- 完整测试套件通过，静音生产路径正常，重复搜索无持续内存增长。
- 文档准确记录实测结果，工作区不包含生成报告或构建产物。

## 建议提交序列

1. 接入搜索诊断和消融选项。
2. 优化排序热路径与快速合法动作计数。
3. 实现并验证树内 PV 排序。
4. 实现并验证 history heuristic。
5. 更新性能证据与维护文档。
