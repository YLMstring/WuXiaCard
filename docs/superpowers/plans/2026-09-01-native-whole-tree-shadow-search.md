# 原生整树影子搜索实施计划

日期：2026-09-01

1. 在 `DuelNativeCompactKernel` 中加入纯 C++ `NativeAction`，把合法动作枚举改造成可接受任意 `NativeState` 的内部函数，公开字典接口只负责转换结果。
2. 把公开的出牌与主动能力转移提炼为任意源状态到独立目标状态的内部事务；保留现有公开结果和事件顺序，先用现有 1,635 项原生探针防回归。
3. 逐项实现 `DuelEvaluator` baseline 原生评分，以及无需剪枝的固定完整轮次 minimax；同分使用规范动作键稳定决胜，遇到不支持分支整体失败。
4. 在 `duel_native_compact_probe.gd` 中加入 14 个真实 Quick 开局的深度一影子对照，并补充小型深度二、额外出牌、主动能力和自动空回合夹具。
5. 构建 Debug GDExtension，运行聚焦原生探针和搜索测试，记录评分、动作、节点与耗时。
6. 更新 `docs/AI_SEARCH.md`、`docs/ARCHITECTURE.md`、`docs/HANDOFF.md`，随后运行完整测试套件；生产调用点保持不变。
