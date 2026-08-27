# AI 搜索强化实施计划

**设计：** `docs/superpowers/specs/2026-08-27-ai-search-strengthening-design.md`
**目标：** 在保持完美信息、10 秒硬上限和 `DuelSimulator` 唯一规则路径的前提下，通过按需后继状态、PVS、有界战术延伸和经自动对战筛选的通用评估特征，让强化 AI 在双方换边基准中稳定强于当前搜索。

## 工作规则

- 开始实现前运行当前完整套件，记录所有显式通过标记；本次设计文档提交不能替代代码基线。
- 每个行为变化先增加失败测试，再做最小实现，再运行聚焦套件。
- `DuelSimulator` 始终是唯一动作合法性和规则结算路径；搜索、排序、评估和基准不得复制卡牌能力。
- 搜索和评估不得检查 `card_id`、牌名或 glyph。基准 fixture 可以引用具体卡牌来构造代表性状态。
- `baseline` 与 `enhanced` 只允许在搜索策略和评估配置上不同，必须共享状态、规则和动作 API。
- 固定深度正确性优先于胜率。PVS、排序或缓存若改变同深度 minimax 分数，立即停止强度调优并修复。
- 每项强化单独消融；未达到强度或性能门槛的功能不进入生产默认配置。
- 不把 8/32 局基准和真实 10 秒样本加入日常完整套件。
- 所有代理运行的可视或实机测试使用 Dummy 音频驱动或静音总线，不播放音乐和音效，也不修改玩家默认设置。
- 当前实现不自动提交；完成验证后交由用户决定实现提交。

## 任务 0：确认代码基线与搜索样本

**修改文件：** 无。

步骤：

1. 运行 `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`，保存所有套件通过标记和总耗时。
2. 单独运行 `test_duel_search.gd` 的现有 runtime benchmark，记录 10 秒样本的深度、节点、剪枝、置换表命中和完成原因。
3. 记录当前 `DuelSearch.find_best_action_iterative()` 在 `_make_opening_state()` 及至少三个中后盘状态上的固定深度动作和分数，作为重构等价性样本。
4. 检查 `git status --short`，保留用户已有修改；若搜索相关文件存在未确认改动，先停止并核对归属。

验收：完整套件通过，搜索样本可重复，工作区归属明确。

## 任务 1：建立搜索配置、统计字段与旧算法基线

**新建：**

- `scripts/duel_search_profile.gd`
- 对应 `.uid`

**修改：**

- `scripts/duel_search.gd`
- `scripts/duel_search_session.gd`
- `scripts/duel_controller.gd`
- `tests/test_duel_search.gd`
- `tests/test_duel_integration.gd`

### Red

1. 增加配置测试：`baseline` 明确关闭 lazy transition、PVS、战术延伸、新评估特征；`enhanced` 默认打开已经验收的功能。
2. 要求配置规范化拒绝负深度、负扫描上限和未知 profile，并返回确定性默认值。
3. 扩展搜索结果断言，要求始终包含：
   - `max_tactical_depth`
   - `generated_actions`
   - `applied_transitions`
   - `pvs_probes`
   - `pvs_researches`
   - `evaluation_cache_hits`
4. 要求 session 的初始、失败、取消和回退报告也具有完整零值字段。
5. 要求控制器日志打印扩展字段，但不把它们写入状态、回放或存档。

### Green

1. 在 `DuelSearchProfile` 集中声明 baseline/enhanced 字典和规范化逻辑；默认生产配置为 enhanced。
2. 暂时让 enhanced 与 baseline 都走当前旧算法，仅增加配置分支和统计零值，确保行为不变。
3. 将配置随 `limits` 传入工作线程；线程内只使用深拷贝的纯数据配置。
4. 扩展 `_make_result()`、session 失败结果和控制器报告格式。

### Verify

- 运行 `test_duel_search.gd`。
- 运行 `test_duel_integration.gd`。
- 比较任务 0 的固定深度动作、分数和旧统计，确认 baseline 行为未改变。

## 任务 2：建立版本化 fixture 与双方换边基准

**新建：**

- `tests/benchmarks/ai_benchmark_fixtures.gd`
- `tests/benchmarks/duel_ai_benchmark.gd`
- `tests/test_duel_ai_benchmark.gd`
- `tools/run_ai_benchmark.ps1`
- 对应 GDScript `.uid`

**修改：**

- `tools/run_tests.ps1`
- `docs/TESTING.md`

### Red

1. fixture 校验要求每项显式包含：ID、难度、active owner、九格棋盘、双方有序手牌、双方有序牌库、弃牌区、移除区、回合数据和重复历史。
2. 要求所有运行时实例 ID 唯一，所有目录 ID 有效，双方区域不共享可变 Dictionary 或 powers Array。
3. 要求同一 fixture 重建两次得到相同 `DuelStateKey`。
4. 要求 paired runner 第二局只交换 baseline/enhanced 控制的 owner，不重新洗牌、不改变初始状态。
5. 要求非法动作、缺失动作、搜索错误和未达终局分别产生明确记录。
6. 要求基线对基线的成对 smoke fixture 得到对称汇总和 50% 对战积分。

### Green

1. 初始实现 4 个 quick fixture，覆盖：
   - 空棋盘开局；
   - 中盘混合所属方；
   - 双方具有内力和主动能力；
   - 接近终局或重复/行动上限边界。
2. runner 每一步调用所控制 profile 的 `DuelSearch`，然后仅通过 `DuelSimulator.apply_action()` 前进。
3. 输出逐步、逐局和总计 Dictionary；写入 `.summer/local/ai-benchmarks/` 下的 JSON，不跟踪产物。
4. PowerShell 入口支持：
   - `-Mode Quick`：4 fixtures × 2，1,500 nodes/action；
   - `-Mode Extended`：16 fixtures × 2，10,000 nodes/action；
   - `-Mode Production`：2 fixtures × 2，10 seconds/action。
5. 无参数的 `test_duel_ai_benchmark.gd` 只验证 fixture、paired runner 和一个极小节点 smoke，不运行正式 8 局 quick benchmark。
6. 将该快速正确性套件加入 `tools/run_tests.ps1`。

### Verify

- 运行 `test_duel_ai_benchmark.gd`，确认显式通过标记。
- 运行 `tools/run_ai_benchmark.ps1 -Mode Quick`；此时 baseline 与 enhanced 尚等价，积分应为 50%，动作和分数应成对一致。

## 任务 3：拆分卡牌无关的动作排序

**新建：**

- `scripts/duel_search_ordering.gd`
- 对应 `.uid`

**修改：**

- `scripts/duel_search.gd`
- `tests/test_duel_search.gd`

### Red

1. 直接测试排序优先级：上一轮根主变 > 置换表最佳动作 > 历史分 > 结构分 > canonical key。
2. 用不同实例 ID 但相同结构的动作验证历史键不包含 `card_id`、牌名或 glyph。
3. 验证结构分只读取动作类型、来源/目标、当前所属方、点数、相邻关系和额外出牌状态，不执行 transition。
4. 验证分数完全相同的动作按 canonical key 稳定排序。

### Green

1. 将排序记录从“action + 已结算 transition”改为纯 action descriptor。
2. 增加通用 history key 和搜索内历史表；发生 beta/alpha cutoff 时按剩余深度平方累计，单次搜索结束即丢弃。
3. 保留 baseline 的原 `_ordered_transitions()` 路径，供消融与对照；enhanced 暂时只使用新 descriptor 排序，但尚不启用 PVS 或战术延伸。

### Verify

- 运行排序和搜索聚焦测试。
- 重复运行固定深度样本，确认相同状态仍得到相同动作与分数。

## 任务 4：让 alpha-beta 按需结算后继状态

**修改：**

- `scripts/duel_search.gd`
- `tests/test_duel_search.gd`
- `tests/test_duel_ai_benchmark.gd`

### Red

1. 要求 `generated_actions` 统计所有进入排序的合法动作，`applied_transitions` 只统计实际调用 `apply_action()` 的动作。
2. 构造内部节点首个动作即可 cutoff 的状态，要求 enhanced 的 `applied_transitions < generated_actions`。
3. 同一状态 baseline 必须保持 eager 行为，作为消融对照。
4. 在无 cutoff 的小树中，要求所有必要动作都被结算，不能因 lazy 路径漏分支。
5. baseline/enhanced 在深度 1–3 的可穷举状态上返回相同 minimax 分数和根动作。
6. 截止时间或 node limit 在结算前触发时，不能增加 transition 计数或发布部分深度结果。

### Green

1. enhanced 的根和递归循环在访问 action 时才调用 `DuelSimulator.apply_action()`。
2. transition 生成后立即递归，不缓存 live scene 引用；需要复用的纯 transition 只留在当前栈帧。
3. cutoff 后停止循环，不结算剩余动作。
4. 使用真实 transition 结果更新 history 和 TT best action；不反向提前结算同节点的剩余动作。

### Verify

- 运行 `test_duel_search.gd` 和 `test_duel_ai_benchmark.gd`。
- 运行 Quick 基准，对比 baseline/enhanced 的 transition 数、完整深度和积分。
- 只有同深度等价且 transition 数下降时，才让 enhanced 默认保留 lazy 路径。

## 任务 5：实装 PVS 并证明同深度等价

**修改：**

- `scripts/duel_search.gd`
- `tests/test_duel_search.gd`
- `tests/test_duel_ai_benchmark.gd`

### Red

1. 对最大化和最小化节点分别构造首动作最佳、后续动作越窗和后续动作不越窗 fixture。
2. 要求后续动作先增加 `pvs_probes`；只有越窗时增加 `pvs_researches`。
3. baseline、lazy-only、lazy+PVS 在深度 1–4 的固定小树中返回相同分数。
4. 根动作同分时仍按 canonical key 选择，不因 PVS 首动作改变平局结果。
5. PVS probe 或重搜中发生取消、deadline、node limit 时，不发布未完成深度。
6. TT exact/lower/upper bound 在 PVS 开关前后保持正确。

### Green

1. 排序首动作使用完整窗口。
2. 后续动作使用最窄整数窗口；只有结果可能改善当前最佳值时完整重搜。
3. 最大化与最小化路径分别正确处理 alpha/beta，不将 probe 分数误存为 exact。
4. 所有 probe、重搜和 cutoff 更新报告计数。

### Verify

- 运行搜索聚焦测试至少两次。
- 运行 Quick 基准的 lazy-only 与 lazy+PVS 消融。
- 若 PVS 未降低 transition/节点成本或降低对战积分，则从生产 enhanced 配置关闭，但保留正确性测试覆盖配置开关。

## 任务 6：实装有界战术延伸

**新建：**

- `scripts/duel_search_tactics.gd`
- 对应 `.uid`

**修改：**

- `scripts/duel_search.gd`
- `scripts/duel_search_profile.gd`
- `tests/test_duel_search.gd`
- `tests/test_duel_ai_benchmark.gd`

### Red

1. 直接测试 transition 分类：实际翻面、所属方改变、移除、四零移除、重新进场、额外出牌和立即终局均为 volatile；纯移动、纯抽牌和无效果动作默认不延伸。
2. 要求分类只读取通用 transition 数据和事件类型，不检查目录 ID。
3. 深度零存在 volatile 动作时，要求 `max_tactical_depth > completed_depth`；安静局面保持相等。
4. 默认最大额外深度固定为 2，候选扫描上限为 12，实际延伸动作上限为 4。
5. 构造超过扫描及动作上限的局面，验证计数和停止边界。
6. stand-pat 评估与最大化/最小化比较正确；延伸不能迫使一方选择比静态值更差的可跳过战术线。
7. 战术搜索中的取消、deadline 和 node limit 使用同一停止协议。
8. bounded tactical horizon 不能误报整棵树 `solved`。

### Green

1. `DuelSearchTactics` 只负责判断已生成 transition 是否 volatile。
2. 普通深度到零时先获取 stand-pat 分数，再按 enhanced 顺序最多扫描 12 个候选并最多搜索 4 个 volatile transition。
3. 每条延伸线最多两层；递归继续复用 alpha-beta、PVS、TT 和停止检查。
4. baseline 和 tactical-disabled 配置直接返回普通叶节点评估。
5. 报告记录最大实际战术深度，不把它冒充完整深度。

### Verify

- 运行搜索和 benchmark 正确性套件。
- 对比 enhanced 无延伸/有延伸的 Quick 基准胜率、分差、节点、深度和回退率。
- 若强度门槛未提升或回退率上升，关闭生产延伸并删除无收益的额外分类分支。

## 任务 7：增加叶节点评估缓存

**修改：**

- `scripts/duel_search.gd`
- `scripts/duel_evaluator.gd`
- `tests/test_duel_search.gd`

### Red

1. 同一状态、root owner、评估 profile 重复到达叶节点时，第二次命中缓存且分数完全一致。
2. root owner 或评估 profile 不同必须产生不同缓存键。
3. 缓存只存在于一次顶层搜索；下一次搜索从零命中开始。
4. 取消或不完整 transition 不得写入评估缓存。

### Green

1. 使用 `StateKey.build_compact(state) + root_owner + evaluator_profile` 组成叶缓存键。
2. 普通叶与 stand-pat 共用缓存；终局分数可以复用但不绕过 `Simulator.is_terminal()` 正确性判断。
3. 报告 `evaluation_cache_hits`。

### Verify

- 运行搜索聚焦测试。
- 运行 Quick 基准，确认缓存不改变动作/分数，并记录节省的 evaluator 调用。

## 任务 8：逐组强化评估器

**修改：**

- `scripts/duel_evaluator.gd`
- `scripts/duel_search_profile.gd`
- `tests/test_duel_search.gd`
- `tests/test_duel_ai_benchmark.gd`

### 第 1 组：可使用资源

Red：

1. 有可消耗内力能力的牌，其内力价值高于没有任何耗内力途径的同状态牌。
2. 当前能支付费用且存在合法目标的主动能力计入行动力；不能支付或没有目标的不计。
3. 四边 `-1`、普通点数、被压制能力和 retained 能力通过通用语义评分，不检查卡名。

Green：新增集中权重和通用 helper，保持终局与场面分层级不变。

Gate：在相同 enhanced 搜索下运行新旧评估 profile 的 Quick 和 Extended 消融；未提升积分或平均分差则删除该组生产逻辑。

### 第 2 组：临近终局与节奏

Red：

1. 棋盘接近填满、接近行动上限或接近第五次重复时，真实场面分差权重提高。
2. 额外出牌和 active owner 提供有限节奏分，但不能覆盖一张场面牌的战略价值。
3. 双方镜像状态从相反 root owner 评估时分数取反或保持允许的终局时间微差。

Green：新增终局接近度与节奏 helper，所有非终局总分继续严格小于 `WIN_SCORE`。

Gate：独立运行消融；不达标则删除该组。

### 第 3 组：攻防结构

Red：

1. 相邻可被成功攻击的危险边降低价值。
2. 当前可成功攻击的边提高价值，但重复计算同一目标受到上限约束。
3. 评估防守覆盖、无限范围或目标策略时只调用通用规则/能力语义，不复制命名能力。
4. 对称棋盘的攻防结构分互相抵消。

Green：实现有明确扫描上限的通用攻防 helper；不在评估器内部应用动作。

Gate：独立运行消融；若节点率下降导致完整深度或胜率退化，删除该组。

### Verify

- 每组运行 `test_duel_search.gd`。
- 每组先 Quick、后 Extended；保存 `.summer/local/ai-benchmarks/` JSON 对照。
- 最终 enhanced evaluator 只启用通过 Gate 的组。

## 任务 9：扩展到 16 个 fixture 并执行正式消融

**修改：**

- `tests/benchmarks/ai_benchmark_fixtures.gd`
- `tests/test_duel_ai_benchmark.gd`
- `tools/run_ai_benchmark.ps1`

步骤：

1. 将清单从 4 个扩展为 16 个完整状态；保持 quick 4 项为稳定子集。
2. 覆盖早中晚盘、不同空位数、不同手牌数、主动能力、内力、额外出牌状态、移除/弃牌资源、重复历史和进阶难度。
3. 校验每项状态键、实例唯一性、区域独立性和终局/非终局预期。
4. 让 `-Mode Extended` 明确加载全部 16 个 fixture、执行 32 局换边对战，并在摘要中打印积分、完整深度不退化比例、回退率和门槛判定；任一门槛失败时返回非零退出码。
5. 依次运行以下 paired Extended 对照：
   - baseline vs lazy；
   - lazy vs lazy+PVS；
   - 搜索增强无战术延伸 vs 有战术延伸；
   - 冻结旧评估 vs 每个候选评估组；
   - 最终 baseline vs 最终 enhanced。
6. 最终 enhanced 必须达到设计中的 55% 积分、75% 深度不退化、回退率不升和双方换边综合提升。
7. 未达标时根据消融结果只关闭失败组件，不靠同时修改多个权重追分。

## 任务 10：生产线程、控制器报告与 10 秒样本

**修改：**

- `scripts/duel_search_session.gd`
- `scripts/duel_controller.gd`
- `tests/test_duel_search.gd`
- `tests/test_duel_integration.gd`

步骤：

1. 确认生产 session 默认使用最终 enhanced profile；测试入口可显式选择 baseline 或关闭单项功能。
2. 线程进度与最终结果复制所有新统计字段，仍受 mutex 保护。
3. 取消检查覆盖 lazy action 循环、PVS probe/重搜、战术扫描和延伸。
4. 扩展 `AI_SEARCH` 单行日志，保持旧字段兼容并追加设计规定的字段。
5. 测试第一层未完成、深层中断、worker failure、stale result、非法结果和退出场景时的贪心回退。
6. 测试检查器打开期间继续思考、关闭后才应用动作；不新增 UI 文案或动画。
7. 运行 Production 基准 2 fixtures × 2，使用真实 10 秒预算并 Dummy 音频驱动。
8. 记录每局耗时、完整/战术深度、节点率、回退率和最终积分；任何超过硬上限的持续超时均为阻塞项。

## 任务 11：文档、完整回归与生产路径验证

**修改：**

- `docs/AI_SEARCH.md`
- `docs/HANDOFF.md`
- `docs/TESTING.md`
- `docs/KNOWN_ISSUES.md`

步骤：

1. 记录 baseline/enhanced 配置、lazy transition、PVS、战术延伸、评估缓存、最终保留的评估组和基准命令。
2. 更新已知性能瓶颈和紧凑状态仍延后的原因。
3. 运行所有聚焦搜索、session、benchmark 正确性和控制器套件。
4. 运行 `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`，要求每个套件有显式通过标记。
5. 运行 Quick 与 Extended 基准，保存最终 JSON 和摘要。
6. 用 Dummy 音频启动生产对局，在 540×960 逻辑视口走完：
   - 普通敌方思考并行动；
   - 额外出牌触发新搜索；
   - 思考期间打开/关闭卡牌详情；
   - 思考期间退出并取消线程；
   - testing mode 不启动 AI。
7. 检查控制台、调试器、线程泄漏、非法动作、超时和 stale commit。
8. 运行 `git diff --check`，审阅完整差异，确认搜索/评估无命名卡牌分支，基准产物未进入 Git。
9. 报告最终测试标记、Quick/Extended/Production 结果、每项消融数据和仍存在的性能限制；不自动提交实现。

## 完成标准

- 完整测试套件通过。
- 固定深度正确性与 baseline minimax 一致。
- enhanced 的未访问动作不生成 transition。
- PVS 和缓存不改变完整深度结果。
- 战术延伸严格受 2 层、12 候选、4 动作上限约束。
- Extended 基准达到至少 55% 对战积分，至少 75% 决策样本完整深度不退化，回退率不升。
- Production 四局样本遵守 10 秒硬上限并表现为整体提升。
- 所有正式搜索仍通过 `DuelSimulator`，AI 继续读取双方完整手牌和牌库顺序。
- 文档与报告字段更新，工作区不含基准产物或临时文件。
