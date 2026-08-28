# PVS 纯消融评估实施计划

**设计：** `docs/superpowers/specs/2026-08-28-pvs-pure-ablation-design.md`

**目标：** 增加 `LazyPVS` 双侧纯消融配置，通过固定深度等价和完整回归后，
直接运行 112 场 `Lazy + PVS` 对 `LazyOnly` Extended。

## 工作规则

- 复用最近一次 68 套件通过作为修改前基线；代码改变后重新跑完整套件。
- 先写失败配置测试，再实现最小双侧 variant 接线。
- 生产 `DuelSearchProfile` 默认值保持 `use_pvs = false`。
- 不修改搜索、评估、排序、模拟器、赛程、种子或节点档位。
- 不运行 Quick 或 Pilot。
- 正式运行使用 headless、Dummy 音频和现有逐局 JSONL 检查点。
- 不自动提交实现，不自动把 PVS 加入生产。

## 任务一：双侧纯消融配置

**修改：**

- `tests/benchmarks/duel_ai_benchmark.gd`
- `tests/test_duel_ai_benchmark.gd`
- `tools/run_ai_benchmark.ps1`

### Red

1. `LazyPVS` 返回 Enhanced 和 Baseline 两组显式 override。
2. 两组都启用 Lazy transitions，关闭战术延伸与评估缓存，使用 baseline
   evaluator。
3. 两组唯一有效搜索差异为 Enhanced `use_pvs = true`、Baseline
   `use_pvs = false`。
4. 现有 `LazyOnly` 和其它变体映射保持不变。
5. PowerShell 参数校验接受 `LazyPVS`。

### Green

1. 将单侧 `_variant_overrides()` 提升为返回
   `enhanced_overrides`/`baseline_overrides` 的 variant 配置。
2. 旧变体继续只设置 Enhanced；Baseline 默认为空，维持原语义。
3. `LazyPVS` 显式返回两侧完整配置，并分别传入
   `run_enemy_matchups()`。
4. Pilot 虽保留可调用，但本任务不运行；其现有单侧行为通过 variant 配置
   继续兼容。
5. PowerShell `ValidateSet` 增加 `LazyPVS`。

### Verify

- 运行 `test_duel_ai_benchmark.gd`。
- 解析 `tools/run_ai_benchmark.ps1`，确认无 PowerShell 语法错误。

## 任务二：固定深度正确性门槛

**修改：** 原则上无；只有发现覆盖缺口时才补测试。

步骤：

1. 运行 `test_duel_search.gd` 的固定深度 PVS 等价覆盖。
2. 运行 `tests/benchmarks/real_quick_search_equivalence.gd`：14 个真实 Quick
   开局、固定完整轮次深度一，比较 Baseline、LazyOnly、Lazy+PVS。
3. 要求 Lazy+PVS 与 LazyOnly/基准评分和根动作完全相同，PVS probe 大于
   零且关闭方为零。
4. 任一差异立即停止，不启动 Extended。

## 任务三：文档与完整回归

**修改：**

- `docs/AI_SEARCH.md`
- `docs/TESTING.md`
- `docs/HANDOFF.md`

步骤：

1. 记录 `LazyPVS` 是纯 benchmark 消融，生产仍关闭 PVS。
2. 记录双方显式配置、正确性门槛和 Extended 命令。
3. 运行搜索和 benchmark 聚焦套件。
4. 运行 `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`，要求
   68 套件全部通过。
5. 运行 `git diff --check`，确认没有报告、检查点或临时文件进入版本控制。

## 任务四：正式 Extended

步骤：

1. 直接运行
   `tools/run_ai_benchmark.ps1 -Mode Extended -Variant LazyPVS`。
2. 固定 28 matchup/112 场、1500 软节点、最低完整深度一。
3. 每局核对终局、fallback、PVS probe/research、深度、节点超限和 ETA。
4. 完成后核对 112 行检查点与最终 JSON。
5. 分析总体/先后手/matchup 得分、固定深度语义、节点/秒、累计搜索时间、
   完成深度、probe/research 和首次轨迹分歧。
6. 按 `<50%`、`50%–<55%`、`>=55%` 预声明口径报告，不自动启用生产
   PVS。

## 完成标准

- `LazyPVS` 双方除 PVS 外的有效搜索配置一致。
- 固定深度夹具和 14 个真实开局动作/评分完全等价。
- 聚焦与完整 68 套件通过。
- Extended 112 场完整运行且逐局检查点有效。
- 结果能回答 PVS 是否失分、是否提速、是否提高完成深度；生产配置不变。
