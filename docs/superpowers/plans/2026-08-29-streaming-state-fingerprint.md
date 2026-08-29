# 流式全状态指纹实施计划

**设计：**
`docs/superpowers/specs/2026-08-29-streaming-state-fingerprint-design.md`

**目标：** 在保持全状态字段覆盖和固定深度搜索语义不变的前提下，用
通用流式双指纹替代 `build_compact()` 的巨型 canonical 字符串构造，并在
14 个真实生产开局上达到至少 `20%` 的合计节点吞吐提升。

## 工作规则

- 开始时确认工作树干净，并复用最近一次 68 套件通过作为代码改动前功能
  基线；状态键行为改变后再运行完整套件。
- 可见或设备测试继续使用 Dummy/静音音频；不修改玩家的正常音频默认值。
- 先补齐性能报告字段并运行改动前生产档案，再修改状态键实现。
- 先写失败测试，再实现最小流式指纹。
- `DuelStateKey.build()` 的完整 canonical 行为保持不变。
- 指纹器保持 Variant 通用，不检查卡牌 ID、门派、能力名称或搜索含义。
- 不排除任何展示字段，不实现方案 B 的语义裁剪。
- 不给 `DuelState` 或 `DuelSimulator` 增加增量指纹、dirty 标记或专用修改
  入口。
- 新实现先保持未提交；正确性或 `20%` 吞吐门槛失败时停止上线，不用
  含糊结论代替门槛。
- 不运行 Extended 112 场强度赛程。本任务是固定深度等价的纯性能优化，
  使用 14 开局固定深度 oracle 和生产十秒档案验证。

## 任务一：补齐可比较的开局档案

**修改：**

- `tests/benchmarks/production_opening_depth_profile.gd`

步骤：

1. 在每个已完成深度 snapshot 中记录：
   - `score`；
   - 根动作 `canonical_key()`；
   - 当层累计节点和耗时。
2. 在开局样本中记录初始 compact key 长度，以及完整 `build()` 输出的
   SHA-256 digest；digest 只用于证明 payload 重构前后精确编码逐字不变，
   不参与搜索。
3. 在 summary 中增加：
   - 总节点；
   - 总搜索秒数；
   - `nodes_per_second = total_nodes / total_search_seconds`；
   - 深度一动作/评分快照数量；
   - 平均初始 compact key 长度。
4. timing probe 继续记录 `time_key_usec`，summary 额外汇总三个 probe 的
   总节点、总耗时、总 key 微秒和每节点 key 微秒。
5. 不改变开局、种子、预算、搜索配置、计时探针节点数或搜索调用次数。

### Verify

- 运行 `test_duel_search.gd`，确认报告字段改动没有改变搜索。
- 用一开局、短预算运行 profiler 冒烟，检查 JSON 字段和完成标记。
- 运行 `git diff --check`。

## 任务二：生成改动前基线

**不修改生产代码。**

步骤：

1. 运行：

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_production_opening_profile.ps1 -BudgetSeconds 10 -MaxOpenings 14
   ```

2. 保存生成的 ignored JSON 绝对路径，称为 `legacy_report`。
3. 从 `legacy_report` 固定记录：
   - 14 个开局各自的深度一 score/action key；
   - 14 个开局各自的完整 exact-key digest；
   - 总节点、总秒数和合计节点/秒；
   - timing probes 的每节点 key 微秒；
   - 完成深度、fallback、停止原因和深度二根动作进度；
   - 平均初始 compact key 长度。
4. 要求 14 个开局均完成深度一；否则停止并先处理基线环境问题。

该报告不提交 Git，并且不能用历史文档中的 `255.5 nodes/s` 代替本次新鲜
基线。

## 任务三：建立流式指纹失败测试

**新增：**

- `tests/test_duel_state_key.gd`

**修改：**

- `tools/run_tests.ps1`
- `tests/test_duel_search.gd`（只在现有顶层字段覆盖缺口需要补充时修改）

### Red

1. 新 suite 期待 `StateKey.build_compact(state)` 使用 `v2:` 前缀；当前实现
   应失败。
2. 期待通用 Variant 指纹入口能够直接测试嵌套值；入口尚未实现时失败。
3. 固定结构测试覆盖：
   - `null`、布尔、整数、浮点数；
   - 空字符串、英文、中文；
   - `String` 与同文本 `StringName` 不同；
   - 数组交换顺序后不同；
   - Dictionary 改变插入顺序后相同；
   - Dictionary 增删或修改 value 后不同；
   - 多层 Array/Dictionary 嵌套。
4. 状态测试覆盖深复制相等、`state_version` 排除和所有现有高风险状态字段
   差异。复用或迁移 `test_duel_search.gd` 中已有断言，避免重复维护。
5. 把 `test_duel_state_key.gd` 加入日常完整套件，输出独立通过标记。

要求先观察到缺少 `v2`/通用指纹入口的预期失败，再进入实现。

## 任务四：实现统一 payload 与通用流式指纹

**新增：**

- `scripts/duel_variant_fingerprint.gd`

**修改：**

- `scripts/duel_state_key.gd`

步骤：

1. 从 `DuelStateKey.build()` 提取 `_state_payload(state)`；完整 `build()` 改为
   `_encode(_state_payload(state))`，输出必须与改动前逐字相同。
2. `DuelVariantFingerprint` 接收 Variant 和一个 canonical Dictionary-key
   编码 Callable，返回：

   ```text
   v2:<element_count>:<hash_a>:<hash_b>
   ```

3. 使用一个可变 accumulator 实例贯穿递归，避免为每个子节点创建
   Dictionary/Array 结果对象。
4. 两个 64 位 accumulator 使用固定但不同的种子和有序混合常量；固定
   Variant 向量锁定输出，确保后续平台或重构不会静默改变算法。
5. 每个输入先吸收独立类型标记，再吸收：
   - 标量值；
   - 文本 UTF-8 长度与内容；
   - 容器长度；
   - 数组索引顺序；
   - Dictionary 稳定排序后的键和值。
6. Dictionary 继续用 `DuelStateKey` 现有 canonical key 编码规则生成短
   key 的排序文本。`DuelStateKey` 通过一个通用 Variant compact wrapper
   把现有 `_encode` Callable 传给指纹器，避免两个脚本互相 preload，也避免
   复制第二套排序编码。指纹器不得依赖 Dictionary 原始迭代顺序。
7. 文本处理不得重新建立完整状态 canonical 字符串、不得全局
   `hex_encode()`、不得反转完整状态字符串。按类型化 token 更新 accumulator，
   避免每字节创建 Variant 容器。
8. 为旧算法保留明确标记为测试/基准用途的
   `build_compact_legacy_for_benchmark(state)`，实现仍为完整 `build()` 加长度、
   正向 hash 和反向 hash。生产调用继续使用 `build_compact()` 的 `v2` 路径。
9. `DuelStateKey.build_compact(null)` 返回固定 `v2` null 键。

### Green

- 运行 `test_duel_state_key.gd`，要求所有固定结构和状态差异测试通过。
- 运行 `test_duel_search.gd`，要求搜索、置换表和连续行动计划测试通过。
- 比较一组状态改动前后的 `build()` 完整字符串，确认提取 payload 没有改变
  精确编码。

## 任务五：碰撞语料与旧键微基准

**修改：**

- `tests/test_duel_state_key.gd`

**新增：**

- `tests/benchmarks/duel_state_key_microbenchmark.gd`

步骤：

1. 从 14 个真实 Quick 开局开始，以 action canonical key 顺序获取合法动作。
2. 对每个状态只扩展固定数量的最前合法动作，按确定性队列继续，直到收集
   至少 512 个不同 exact canonical 状态；不得使用随机选择。
3. 维护 `v2 compact key → exact build()` 映射。同一 compact key 对应不同
   exact key 时立即失败并打印两个状态来源。
4. 同时确认 exact key 相同的深复制状态得到相同 compact key。
5. 微基准对同一固定语料分别多次调用 legacy 与 `v2`，报告：
   - 调用次数；
   - 总秒数和 keys/s；
   - 平均 key 长度；
   - sink/checksum，防止循环被无效化。
6. 微基准只作快速诊断，不加入日常完整套件，也不能代替生产十秒档案的
   `20%` 门槛。

### Verify

- `test_duel_state_key.gd` 报告至少 512 个 distinct exact states、零碰撞。
- `test_duel_search.gd` 继续通过。
- 如 `v2` 微基准不快于 legacy，停止并分析 accumulator 热点，不运行
  14 开局生产档案。

## 任务六：固定深度语义等价

**修改：**

- `tests/benchmarks/real_quick_search_equivalence.gd`

步骤：

1. 给 oracle 增加可选 `--expected-report=<absolute path>` 参数。未传时保持
   现有行为；传入时加载任务二的 `legacy_report`，按 game ID 提取每个开局
   的深度一 score/action key。
2. 运行 `tests/benchmarks/real_quick_search_equivalence.gd`，要求 14 开局、
   28 个 profile 比较全部通过。
3. oracle 同时把当前 LazyOnly 固定深度一 score/action key 与
   `legacy_report` 比较。
4. oracle 同时计算当前 14 个开局的 `build()` SHA-256 digest，与
   `legacy_report` 中的 digest 比较，证明提取统一 payload 没有改变完整
   精确编码。
5. 要求 14/14 的 score、action key 和 exact-key digest 完全相同，且开局
   集合没有缺失或重复。
6. 任一差异立即停止，不以更高限时胜率或偶然更深搜索覆盖固定深度差异。

## 任务七：改动后生产档案与门槛判定

步骤：

1. 使用与任务二完全相同的命令运行 14 开局生产档案，得到
   `streaming_report`。
2. 计算：

   ```text
   legacy_nps    = legacy_total_nodes / legacy_total_seconds
   streaming_nps = streaming_total_nodes / streaming_total_seconds
   gain_percent  = (streaming_nps / legacy_nps - 1) * 100
   ```

3. 要求：
   - `gain_percent >= 20`；
   - 14 个开局都至少完成深度一；
   - fallback 不增加；
   - timing probes 的 `time_key_usec / nodes` 低于 legacy；
   - 深度一动作和评分仍与 legacy 完全相同。
4. 记录深度二完成数和各未完成迭代的根动作进度，但不把它们当作硬门槛。
5. 报告新旧平均 compact key 长度、key 时间、总吞吐和完成深度。

### 失败分支

- 正确性失败：停止，修复后从聚焦测试重新开始。
- 正确性通过但微基准变慢：停止，不跑生产档案。
- 生产吞吐提升 `<20%`：保留报告，不更新生产完成文档，不提交为成功；
  请用户决定继续优化 A、转向 B 或撤掉实现。

## 任务八：完整回归、文档和提交

**仅在任务七全部通过后执行。**

**修改：**

- `docs/AI_SEARCH.md`
- `docs/HANDOFF.md`
- `docs/TESTING.md`

步骤：

1. 记录 `v2` 是通用全状态流式指纹，不是语义裁剪或增量状态。
2. 记录 legacy 与 streaming 报告路径、节点/秒、提升百分比、key 时间变化、
   固定深度等价和完成深度。
3. 文档明确完整 `build()` 仍是精确判定器，compact key 仍有理论碰撞风险。
4. 运行：

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
   ```

5. 要求所有套件通过；新增 state-key suite 后总套件数应以实际输出为准，
   不编写会随套件增长而过期的固定数量断言。
6. 运行 `git diff --check`、PowerShell 语法解析和 `git status --short`。
7. 确认 `.summer/local/ai-benchmarks/` 报告、临时日志和 Godot 缓存未进入
   暂存区。
8. 只暂存本计划列出的实现、测试与文档，创建一个描述行为的聚焦提交。

## 完成标准

- 精确 `DuelStateKey.build()` 输出不变。
- `build_compact()` 使用版本化全状态流式双指纹，不生成完整 canonical
  value 字符串。
- Variant 固定向量、状态差异和 Dictionary 稳定排序覆盖通过。
- 至少 512 个真实确定性状态零碰撞。
- 14 个真实开局固定深度 score/action 逐项等价。
- 新鲜生产档案合计节点/秒提升至少 `20%`，每节点 key 时间下降，且不增加
  fallback 或深度一失败。
- 完整自动化套件通过，报告未进入 Git，文档记录可复现证据。
