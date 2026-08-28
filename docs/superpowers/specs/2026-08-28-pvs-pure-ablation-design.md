# PVS 纯消融评估设计

**状态：** 已确认，待书面审阅
**日期：** 2026-08-28

## 目标

在不改变生产 AI 的前提下，单独评估 Principal Variation Search（PVS）
相对当前生产 `LazyOnly` 搜索的正确性、速度和实战强度。

正式比较必须是 `Lazy + PVS` 对 `LazyOnly`。双方使用相同规则、评估器、
Lazy transition、赛程、种子和搜索限制，唯一影响搜索行为的配置差异是
`use_pvs`。

## 不在范围内

- 不启用战术延伸或增强评估器；
- 不启用评估缓存；
- 不修改卡牌、模拟器、排序器或 production 十秒预算；
- 不运行 Quick 或 Pilot 作为筛选；
- 不根据中途胜率修改赛程、种子、节点档位或停止规则；
- 不因本次结果自动打开生产 PVS。

## 基准变体

PowerShell 和 GDScript benchmark CLI 增加 `LazyPVS` 变体。

Enhanced 方显式使用：

```gdscript
{
    "use_lazy_transitions": true,
    "use_pvs": true,
    "use_tactical_extension": false,
    "use_evaluation_cache": false,
    "evaluator_profile": &"baseline",
}
```

对照方显式使用：

```gdscript
{
    "use_lazy_transitions": true,
    "use_pvs": false,
    "use_tactical_extension": false,
    "use_evaluation_cache": false,
    "evaluator_profile": &"baseline",
}
```

Benchmark 的 Enhanced/Baseline 名称继续负责归属对局积分。对照方虽然使用
`baseline` profile 名称，但覆盖所有会影响本次搜索的功能开关；代码测试必须
证明规范化后的有效搜索配置除 `name`、无效的战术默认上限和 `use_pvs` 外一致。
战术延伸关闭，因此 profile 名称造成的默认战术上限不参与搜索。

现有变体的行为保持不变。未知变体仍沿用当前默认处理，不得被误当作
`LazyPVS`。

## 正确性门槛

PVS 只能改变搜索工作量，不能改变相同完整深度下的 minimax 语义。
启动正式 Extended 前必须满足：

1. 现有固定完整轮次深度夹具中，PVS 开关返回相同评分和相同规范根动作；
2. 真实敌人目录开局的固定深度等价检查无评分或动作不一致；
3. 开启方产生至少一个 PVS probe，关闭方始终为零；
4. PVS probe、完整窗口重搜、取消、deadline、节点限制和最低深度保护均不
   发布未完成迭代；
5. `LazyPVS` 配置测试证明双方仅有 PVS 行为差异；
6. 聚焦搜索/benchmark 套件以及仓库完整 68 套件通过。

任一正确性条件失败时停止，不启动 Extended。性能或胜率不用于豁免正确性
失败。

## Extended 赛程

正确性通过后，直接运行：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_ai_benchmark.ps1 -Mode Extended -Variant LazyPVS
```

赛程沿用刚完成的真实敌人目录 Extended：

- 28 个 matchup、112 场确定性四场交叉；
- 名义 `max_nodes = 1500`；
- `min_completed_depth = 1`；
- 双方相同软节点和硬停止规则；
- Dummy 音频；
- 每局实时 `AI_BENCHMARK_GAME` 输出；
- 每局追加一条 JSONL 检查点；
- 最终 JSON 与检查点共享 artifact stem。

不运行 Quick 或 Pilot。运行途中只报告进度和诊断，不因胜率、速度或局部
异常动态换档；进程级失败或正确性错误仍按现有规则终止。

## 诊断与分析

最终报告沿用现有完整 game/decision 数据，并重点比较：

- Enhanced match points 与先后手、等级、matchup、敌人牌组 breakdown；
- 初始完整深度非退化率；
- fallback、未完成局、无效局；
- 完成深度分布；
- 总节点、平均节点和节点/秒；
- generated actions 与 applied transitions；
- PVS probes、完整窗口 researches 及重搜率；
- 最低深度保护次数、节点超限总量和最大值；
- 两算法同一初始状态的动作、评分和首次轨迹分歧。

若双方轨迹分叉，胜负不能仅凭首次深度差归因；应区分相同轨迹、同深度动作
差异和不同完成深度造成的策略差异。

## 结果口径

本次 `LazyPVS` 是消融变体，不使用 `Extended Final` 的退出码门槛自动修改
生产配置。结果按以下口径解释：

- 低于 50%：在本次确定性赛程中观察到 PVS 净失分；
- 50% 至低于 55%：强度基本持平，未证明稳定增强；
- 不低于 55%：达到预先声明的明确强度收益线。

无论积分如何，相同深度动作/评分不一致均视为正确性失败。即使达到 55%，
也只向用户报告证据，由用户另行决定是否将 PVS 加入生产 profile。

## 验证

### 配置与搜索

1. `LazyPVS` Enhanced 配置只比对照方多启用 PVS；
2. 其它已有变体配置不变；
3. 固定深度 PVS 开关评分和动作相同；
4. PVS probes 大于零，关闭方 probes 为零；
5. 重搜计数非负，所有硬停止与软最低深度行为保持正确。

### Benchmark

6. PowerShell 接受 `LazyPVS`；
7. GDScript CLI 将双方 override 分别送入 runner；
8. Extended limits、112 场 manifest、逐局检查点与实时输出不变；
9. 最终报告可明确识别 `variant = LazyPVS` 并保留双方 PVS 统计；
10. benchmark smoke 证明对照方确实使用 Lazy transitions 而非 eager baseline。

### 回归与正式运行

11. 搜索和 benchmark 聚焦套件通过；
12. 完整 68 套件通过；
13. 直接完成 112 场 `LazyPVS` Extended，不运行 Quick 或 Pilot；
14. 检查点恰好 112 行，最终 JSON 无缺失、重复、fallback、未完成或无效局；
15. 报告强度、性能、深度、PVS 重搜与轨迹分歧，不自动修改生产配置。

## 预计改动范围

- `tests/benchmarks/duel_ai_benchmark.gd`：双侧 variant 配置与 PVS 消融接线；
- `tests/test_duel_ai_benchmark.gd`：纯配置差异和报告覆盖；
- `tests/test_duel_search.gd`：必要时扩充真实状态固定深度 PVS 等价覆盖；
- `tools/run_ai_benchmark.ps1`：接受 `LazyPVS` 参数；
- `docs/AI_SEARCH.md`、`docs/TESTING.md`、`docs/HANDOFF.md`：实现后记录命令、
  边界和结果。

不需要修改生产控制器、模拟器、卡牌目录或默认 `DuelSearchProfile`。
