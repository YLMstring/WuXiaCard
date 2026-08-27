# 敌人目录 AI 互战基准实施计划

**设计：** `docs/superpowers/specs/2026-08-27-enemy-catalog-ai-benchmark-design.md`

**目标：** 让 AI 强度结论来自 34 套真实敌人卡组的确定性交叉对战，而不是当前八张基础牌构成的手工局面；正式对局与基准共享同一纯数据开局工厂，正常敌人流程仍排除东方不败和张三丰。

## 工作规则

- 开始改代码前运行 `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`；若本任务中已有仍然有效的完整通过结果则复用，不连续重复基线。
- 先写失败测试，再做最小实现，再跑聚焦套件。
- `DuelSimulator` 仍是所有互战的唯一合法行动和规则结算路径。
- baseline/enhanced 继续读取双方完整手牌与准确牌库顺序；本任务不修改搜索算法或评估权重。
- 正常敌人选择、存档、奖励和进度不得看到两套 benchmark-only 敌人。
- 新的正式强度比赛不得进入日常完整套件；完整套件只保留结构、确定性和极小 smoke。
- 所有代理运行的对局使用 headless 与 Dummy 音频，不播放音乐或音效。
- 先运行 Pilot 再锁定 Extended 节点档位；不根据最终胜率改配对、种子或门槛。
- 基准 JSON 保留在 `.summer/local/ai-benchmarks/`，不得提交。
- 本次实现完成后不自动提交，由用户决定。

## 任务 0：确认基线和现有基准产物边界

**修改文件：** 无。

步骤：

1. 运行 `git status --short`，确认设计提交之外不存在未归属修改。
2. 运行或复用当前任务内最新的完整套件通过结果；记录搜索、敌人目录、模拟器、对局集成和基准 smoke 的检查数。
3. 显式运行当前 `Quick` 并保存最后一份旧式 JSON，作为迁移前格式样本，不作为新强度结论。
4. 记录当前 `DuelController` 在固定正种子下的手牌顺序、副牌库顺序、八卦格、effect gates、remembered glyphs 和完整状态键。

验收：工作区归属明确，生产开局有可复现的迁移前 oracle，旧 JSON 格式已留作兼容参考。

## 任务 1：把两套注释敌人转为 benchmark-only 目录数据

**修改：**

- `scripts/enemy_catalog.gd`
- `tests/test_enemy_catalog.gd`

### Red

1. 要求正常 `get_all_enemy_ids()` 仍返回 32 个启用敌人，且不包含东方不败、张三丰。
2. 要求新的 benchmark roster 返回 34 个定义，顺序为现有 32 个后接东方不败、张三丰。
3. 断言东方不败的五张牌为 `KuiHua1, KuiHua4, KuiHua3, KuiHua2, KuiHua2`。
4. 断言张三丰的五张牌为 `TaiJiLuanHuan5, TaiJiYinYang5, TaiJiSanHuan5, TaiJiDaKui5, DuGu9Jian1`。
5. 要求两者不能被 `get_enemy_ids_for_level()`、`pick_random_enemy_id()` 或正常 profile 敌人选择命中。
6. benchmark-only 行也必须通过五张牌、合法 ID、等级、名字、唯一卡组和自宫声明校验。

### Green

1. 将两条注释声明移入单独的 `_BENCHMARK_ONLY_ENEMY_ROWS`，不加入 `ALL_ENEMY_IDS` 或正常定义 map。
2. 增加只读的 `get_ai_benchmark_definitions()`，返回启用与 benchmark-only 定义的深拷贝有序数组。
3. 将公共行校验抽成可同时检查 active/dormant 的 helper；正常目录唯一卡组检查继续保持原语义。
4. benchmark-only 默认 `self_castration_enabled = true`，但返回的定义中规范化为显式 Boolean，避免 runner 猜测。

### Verify

- 运行 `test_enemy_catalog.gd`。
- 运行 profile/ending 相关聚焦测试，确认正常敌人数量和选择路径未变。

## 任务 2：提取纯数据生产开局工厂

**新建：**

- `scripts/duel_initial_state_factory.gd`
- 对应 `.uid`

**修改：**

- `scripts/duel_controller.gd`
- `tests/test_duel_opening_setup.gd`
- `tests/test_duel_integration.gd`

### Red

1. 构造固定双方主卡组与正种子，要求工厂重复构建得到相同 `DuelStateKey`，但任何 Dictionary、Array 或 card 实例均不别名。
2. 要求两手牌独立洗牌，且每套卡组换 owner 后仍保持由 deck ID 指定的相同排列。
3. 要求副牌库严格调用 `DeckRules` 派生，固定种子顺序可复现，所有 instance ID 唯一。
4. 难度 0 后手必须得到两张静态八卦；不产生进场事件、攻击、行动数或动画数据。
5. 验证双方 effect gates 与 remembered glyphs 使用输入深拷贝。
6. 验证原控制器固定种子开局与工厂输出状态键完全相同。
7. 保留 `0` 随机、负手牌种子不洗牌、负 opening seed 空场等现有调试语义。

### Green

1. 将创建实例、洗手牌、派生/洗副牌库、难度开局手牌效果、八卦初始棋盘和 `DuelState` 构造移入工厂。
2. 工厂只接收纯数据配置并返回 `DuelState`；不读取存档，不持有 scene 节点。
3. `DuelController._ready()` 继续负责读取玩家 profile、敌人输入、mastery 和 UI，但把整理后的配置交给工厂。
4. 控制器以工厂返回 state 创建 hand/board views、开始 replay，并维持原先后续流程。
5. 公开的正种子路径使用稳定 Fisher–Yates；随机与禁用语义保持与原控制器一致。

### Verify

- 运行 `test_duel_opening_setup.gd` 和 `test_duel_integration.gd`。
- 用同一种子实例化两次 `duel.tscn`，比较双方手牌、副牌库、八卦与状态键。
- 确认正常模式、testing mode 和 replay 初始快照均未改变。

## 任务 3：构建34套 roster 与28组确定性 manifest

**新建：**

- `tests/benchmarks/enemy_ai_benchmark_manifest.gd`
- 对应 `.uid`

**修改：**

- `tests/test_duel_ai_benchmark.gd`

### Red

1. roster 必须恰好34项、ID唯一、每套五张合法卡、等级分布与设计一致。
2. 同级全部无序组合必须产生25组；风清扬与三套15级牌额外产生3组；总数必须为28。
3. manifest 不得出现自战、重复无序 pair 或正常目录外的其它敌人。
4. 每组展开四场后总数为112；对每个 profile，A/B 都必须各作为 owner 1/first 和 owner 2/second一次。
5. manifest 重建两次必须完全相等；不得依赖 Dictionary 遍历顺序。
6. Quick、Pilot、Production 的固定敌人 ID 清单必须存在于 roster 并产生设计规定的场数。

### Green

1. 按 level 和 catalog order 构建 roster 索引及全部 matchups。
2. 使用显式 game-assignment 数据生成四场交叉，不在 runner 内隐式猜交换关系。
3. 集中声明 Quick 七组、Pilot 三组和 Production 四组 ID 对。
4. 为 manifest 提供纯查询 API：全部、按 mode、按 matchup ID 和 card-ID coverage。

### Verify

- 运行 `test_duel_ai_benchmark.gd`。
- 输出一次 manifest 摘要，人工核对28组和两套 benchmark-only 卡组。

## 任务 4：为每场敌人互战构建完整生产状态

**新建：**

- `tests/benchmarks/enemy_ai_benchmark_state_factory.gd`
- 对应 `.uid`

**修改：**

- `tests/test_duel_ai_benchmark.gd`

### Red

1. 同一 matchup/game assignment 重建两次必须拥有相同状态键、牌序、八卦和 gates，且无可变别名。
2. profile 交换但 deck assignment 不变时，开局状态键必须相同。
3. A/B 换 owner 后，每套 deck 的手牌及副牌库内部排列保持一致，只改变 owner/instance identity。
4. 少镖头·林平之所在 owner 不含自宫 gate；其它 active/dormant enemy owner 含 gate。
5. 双方 remembered glyphs 各自恰好是对方五张主卡的去重 glyph 顺序。
6. runtime instance ID 在 board、hands、decks、discard、removed 全区域唯一。

### Green

1. 声明 fixture version 和 master seed，使用自有稳定整数 hash 派生各 deck 与 matchup 的种子。
2. 将双方 card IDs、gates、memories、difficulty 0、owner 1 和种子传给共享 `DuelInitialStateFactory`。
3. instance prefix 包含 matchup、assignment、owner、zone 与 ordinal；不把 search profile 写入 state。
4. 返回 state 与可序列化 metadata，供 runner 和 JSON 复用。

### Verify

- 运行 benchmark 正确性套件至少两次。
- 比较 profile swap 两场的 initial state key；比较 deck swap 两场的每 deck 排列。

## 任务 5：重构 runner 以支持四场交叉与分组报告

**修改：**

- `tests/benchmarks/duel_ai_benchmark.gd`
- `tests/test_duel_ai_benchmark.gd`

### Red

1. 四场交叉的 match points 必须归属于控制相应 deck/owner 的 profile，而不是固定 owner。
2. 相同 profile 对相同 profile 的 smoke 必须产生对称分母；draw 计0.5。
3. 256次成功行动 watchdog、非法行动、无合法动作、无效 transition 和非终局必须分别报告明确原因。
4. 缺少任一 assignment、重复 game ID 或对局 metadata/state 不一致必须使汇总失败。
5. 聚合器必须正确生成总体、等级、matchup、enemy deck、first/second 五类 breakdown。
6. 报告的 card coverage 必须来自实际调度的五张主卡，不用目录总数冒充。

### Green

1. 将旧 runner 的“固定 fixture + profile owner swap”抽象为“game specification + profile_by_owner”。
2. 每个 game 仍逐步调用 `DuelSearch.find_best_action_iterative()` 和 `DuelSimulator.apply_action()`。
3. 保留现有逐决策统计，并追加 enemy、assignment、seed、deck、level 与 failure metadata。
4. 运行结束后由独立聚合 helper 生成 breakdown，runner 不在搜索循环内维护多份统计。
5. 保留旧 synthetic fixture 的极小 smoke 入口，但旧8场 Quick 不由日常测试调用。

### Verify

- 运行 `test_duel_ai_benchmark.gd`。
- 用很小 node limit 跑一个四场 enemy matchup，确认四场都终局或产生显式 watchdog/failure，JSON 可重建调度。

## 任务 6：实现模式、PowerShell 入口与紧凑输出

**修改：**

- `tests/benchmarks/duel_ai_benchmark.gd`
- `tools/run_ai_benchmark.ps1`
- `tests/test_duel_ai_benchmark.gd`

### Red

1. mode 解析只接受 `Quick`, `Pilot`, `Extended`, `Production` 与内部测试 smoke；未知 mode 非零退出。
2. Quick 必须是设计指定7组/28场/1,500节点。
3. Pilot 必须按10,000→5,000→3,000→1,500逐级尝试，并输出各档实测与112场投影。
4. Extended 必须加载全部28组/112场和一个固定、非运行时动态的 node tier。
5. Production 必须加载指定4组/16场和10秒 deadline。
6. Extended Final 的55%积分、75%初始深度、回退率、完整对局和合法性门槛必须决定进程退出码。
7. 控制台每 matchup 仅打印一行进度，最终只打印紧凑摘要；逐决策数据只进 JSON。

### Green

1. 用 mode config 集中声明 matchup subset、node/deadline limit、watchdog 与 gate policy。
2. PowerShell 入口继续使用 headless、Hidden window、Dummy audio 和临时 stdout/stderr。
3. JSON 文件名包含 mode、variant、fixture version 和时间戳；失败时尽量保留带 reason 的 partial report。
4. 将旧 synthetic formal Quick 从公开 mode 移除或改为明确的 legacy 调试参数，不进入默认命令帮助。

### Verify

- 运行 PowerShell 参数与 benchmark suite 聚焦测试。
- 运行新的 Quick，核对28场、进度行数、JSON metadata 和非零失败行为。

## 任务 7：运行 Pilot 并锁定 Extended 节点档位

**修改：**

- `tests/benchmarks/duel_ai_benchmark.gd`
- `docs/AI_SEARCH.md`
- `docs/TESTING.md`

步骤：

1. 用 Dummy audio 运行 Pilot 的10,000节点档，保存三组/12场实际总耗时和每决策分布。
2. 按实际游戏总时间线性投影112场；超过30分钟则依次运行5,000、3,000、1,500节点。
3. 选择预计不超过30分钟的最高档；若1,500仍超时，停止并向用户报告，不自行缩减28组 manifest。
4. 将选定 node tier 写死进 mode config，并在文档记录日期、引擎版本、档位、Pilot实测和投影。
5. 重跑 mode config 测试，证明 Extended 不读取机器测速动态改变档位。

验收：节点档位由预先声明的时间规则选出，没有观察胜率后调档或改种子。

## 任务 8：正式运行 Quick、Extended 和 Production

**修改文件：** 原则上无；结果写入 ignored benchmark 目录。

步骤：

1. 运行 Quick，记录28场积分、分层统计、深度、fallback、吞吐和卡牌覆盖率。
2. 运行 Extended，要求调度112场；无论是否通过55%门槛，都保留真实 JSON 和非零/零退出结果。
3. 检查 Enhanced/Baseline 都在每组使用两套牌并分别先后手一次。
4. 运行 Production 16场；若预计或实际超过15分钟，保留结果并报告，不动态删比赛。
5. 对比旧手工基准，只说明样本变化，不能将新旧百分比当作同一总体的直接回归。
6. 本任务不根据结果调整 AI、评估权重、matchup、seed 或门槛；需要进一步强化时另开设计。

验收：新报告能回答增强AI在真实敌人牌组总体、不同等级、不同卡组和先后手下的表现。

## 任务 9：文档、完整回归与生产开局实测

**修改：**

- `docs/AI_SEARCH.md`
- `docs/TESTING.md`
- `docs/HANDOFF.md`
- `docs/KNOWN_ISSUES.md`

步骤：

1. 记录34套 roster、28组/112场交叉规则、两个 benchmark-only 敌人和正常流程隔离。
2. 记录 Quick/Pilot/Extended/Production 的固定规模、已校准 node tier、预期时间、命令和 JSON 路径。
3. 明确日常套件不运行旧8场 Quick 或任何正式 enemy strength match。
4. 运行 enemy catalog、opening setup、benchmark、search、simulator 和 duel integration 聚焦套件。
5. 运行 `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`，要求所有套件显式通过；不因此前运行过但之后代码已变而复用旧结果。
6. 用 Dummy audio 驱动一次真实 `duel.tscn` 固定种子开局，核对 factory state、hand/deck views、八卦、AI线程和动作提交。
7. 运行 `git diff --check`，确认没有 benchmark JSON、临时文件、正常敌人池变化或搜索中的命名卡牌分支。
8. 报告完整套件、Pilot档位、三种模式结果和任何未达门槛，不自动提交实现。

## 完成标准

- 正常敌人池仍为32名，东方不败和张三丰只存在于34套 benchmark roster。
- 生产控制器和基准共享纯数据 `DuelInitialStateFactory`，固定种子状态键一致。
- manifest 固定为28组、112场，四场交叉严格平衡 deck、owner、先后手和 profile。
- Quick为7组/28场/1,500节点；Extended为全部112场并使用Pilot锁定档位；Production为4组/16场/10秒。
- 日常完整套件只运行轻量结构与 smoke，不运行旧Quick正式比赛或新强度比赛。
- Extended真实结果按55%积分、75%深度、回退率和完整性门槛原样判定，不为过线调整数据。
- 所有对局只通过 `DuelSimulator` 前进，双方AI保持完整手牌与牌库顺序可见。
- 完整测试套件通过，生产固定种子开局和AI线程路径实测通过。
- 文档更新，工作区不含报告产物；实现不自动提交。
