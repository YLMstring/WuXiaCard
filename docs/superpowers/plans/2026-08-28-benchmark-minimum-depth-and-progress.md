# 基准最低完成深度与逐局进度实施计划

**设计：** `docs/superpowers/specs/2026-08-28-benchmark-minimum-depth-design.md`

**目标：** 节点制基准在共同的完整轮次深度一上比较 Baseline 与
LazyOnly；Extended 每完成一局立即输出并留下可中断保留的 JSONL
检查点，不再依赖额外 Pilot。

## 工作规则

- 复用本任务内最近一次 68 套件完整通过结果作为修改前基线；代码改变后
  必须重新运行完整套件。
- 生产十秒 deadline 保持硬限制，不设置 `min_completed_depth`。
- Quick、Pilot、Extended 的 Baseline 与 Enhanced 变体使用完全相同的
  `max_nodes = 1500`、`min_completed_depth = 1`。
- 搜索和报告保持卡牌无关；不改评估器、排序、牌组、赛程、种子或门槛。
- Extended 逐局数据只在一局完整返回后落盘；部分检查点不参与最终判定。
- 所有引擎运行继续使用 headless 与 Dummy 音频。
- 保留工作区现有未提交改动，不暂存无关文件。

## 任务一：最低完成深度搜索契约

**修改：**

- `scripts/duel_search.gd`
- `tests/test_duel_search.gd`

### Red

1. 默认 `max_nodes = 1` 仍在深度一中断且不发布部分结果。
2. 加 `min_completed_depth = 1` 后，相同搜索必须完成深度一并报告门槛启用。
3. 深度一低于节点上限时继续尝试深度二，节点总数不重置。
4. 深度一超过上限时，下一层不搜索子节点。
5. cancellation 与 deadline 仍可中断受保护的深度一。
6. 检查 `min_completed_depth`、`minimum_depth_guard_used` 和
   `nodes_over_limit` 的规范化与数值。

### Green

1. 在搜索上下文保存规范化最低深度、最新完成深度与门槛使用标记。
2. `_should_stop()` 只在完成深度不足时忽略节点限制；取消与 deadline
   始终是硬停止。
3. 每次完整迭代后立即更新上下文完成深度，再决定是否允许下一层。
4. 所有返回路径通过 `_make_result()` 输出新增诊断。

### Verify

- 运行 `test_duel_search.gd`。

## 任务二：基准诊断、逐局回调与 JSONL 检查点

**修改：**

- `tests/benchmarks/duel_ai_benchmark.gd`
- `tests/test_duel_ai_benchmark.gd`

### Red

1. Quick、Pilot、Extended 的节点配置含最低深度，Production 不含。
2. 决策记录和最终汇总保存两套 profile 的门槛使用数、超限总量/最大值、
   总节点、fallback 与深度分布。
3. 一个四场 smoke 每完成一局调用一次进度回调，索引和总数正确。
4. 每个进度记录能独立 JSON 编解码，包含规定的计分、时间、状态和 profile
   诊断，且不包含完整决策或状态。
5. 连续追加后逐行解析数量与已完成局数一致；无效完整结果也写一行。

### Green

1. 给 `run_enemy_matchups()` 增加可选逐局回调和总场数预展开，不改变现有
   纯调用者默认行为。
2. 抽取卡牌无关的 profile 诊断聚合函数，供最终汇总与逐局记录复用。
3. Extended 在启动时建立共享 artifact stem，初始化空 `.progress.jsonl`，
   每局追加并关闭文件。
4. 每局打印一条稳定 `AI_BENCHMARK_GAME` 行；最终 JSON 引用检查点路径与
   schema version。
5. Quick、Pilot、Production 保留原最终报告；逐局持久检查点只由 Extended
   命令行模式启用。

### Verify

- 运行 `test_duel_ai_benchmark.gd`。
- 用短 smoke 验证 checkpoint 行数、字段和最终 artifact stem。

## 任务三：PowerShell 实时转发

**修改：**

- `tools/run_ai_benchmark.ps1`

### Red

1. 用可控短子进程证明一条进度在进程退出前可见。
2. stdout/stderr 最后一批内容会被排空且不重复。
3. 非零退出、`AI_BENCHMARK_FAILED`、`SCRIPT ERROR:` 与行首 `ERROR:`
   继续使 wrapper 失败。

### Green

1. 去掉 `Start-Process -Wait`，保留 stdout/stderr 重定向。
2. 进程运行时按已读取行数增量读取两个文件，短间隔等待并实时 `Write-Host`。
3. 进程退出后最后排空一次，再使用累计文本执行原有错误检测。
4. `finally` 保持临时文件清理；不改变 Dummy 音频和 Hidden window。

### Verify

- 运行 Quick 或专用短 smoke，观察至少一条进度先于最终摘要出现。

## 任务四：文档与回归

**修改：**

- `docs/AI_SEARCH.md`
- `docs/TESTING.md`
- `docs/HANDOFF.md`

步骤：

1. 记录软节点门槛、硬停止条件、新诊断及生产路径隔离。
2. 记录 Extended 逐局行、JSONL 路径、中断语义和最终 JSON 关系。
3. 删除“先跑 Pilot 才可启动 Extended”的现行说明；保留 Pilot 命令作为
   可选工具，不再作为门槛。
4. 运行搜索与 benchmark 聚焦套件。
5. 运行 `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`。
6. 运行 `git diff --check`，确认没有报告或临时文件进入版本控制。

## 任务五：正式 Extended LazyOnly

步骤：

1. 在完整回归通过后，以 Dummy 音频启动
   `tools/run_ai_benchmark.ps1 -Mode Extended -Variant LazyOnly`。
2. 固定使用软 1500 节点、最低完成深度一，不再运行 Pilot，不动态调档。
3. 每局检查实时行与 JSONL；根据累计耗时报告 ETA，但不自行因胜率或速度
   改赛程或停止。
4. 跑完后核对 112 行检查点、112 场最终 JSON、门槛/超限统计和完整性。

## 完成标准

- 节点制基准的每次有效决策至少完成完整轮次深度一，除非遭遇硬停止。
- 1500 是共享软总节点门槛，不是深度一后的新增额度。
- Baseline 与 LazyOnly 的限制完全一致，生产十秒路径不受影响。
- Extended 每局即时输出、每局追加一条可独立解析的检查点记录。
- 中断不会破坏已完成记录，部分检查点不会冒充最终结果。
- 聚焦和完整测试通过后，直接完成真实 Extended LazyOnly 赛程。
