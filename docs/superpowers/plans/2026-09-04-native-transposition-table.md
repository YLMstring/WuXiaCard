# 原生置换表实施计划

日期：2026-09-04  
设计：`docs/superpowers/specs/2026-09-04-native-transposition-table-design.md`

## 工作规则

- `DuelNativeCompactKernel` 继续是唯一生产规则与搜索实现。
- 桌面与 Android 的生产默认容量均为 8 MiB。
- 固定深度评分和 canonical 根动作等价是硬门槛。
- 置换表关闭时不分配、不查询、不维护条目。
- 每项聚焦验证使用 Dummy 音频；行为改动全部完成后只跑一次完整套件。
- 基准 JSON、DLL、SO、APK 和构建目录不提交。

## 任务一：建立配置和结果契约

**修改：**

- `scripts/duel_search.gd`
- `scripts/duel_native_rules.gd`
- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/test_duel_search.gd`
- `tests/test_native_production_rules.gd`

### Red

1. 断言生产入口默认传入 `use_transposition_table=true` 和 `transposition_table_mib=8`。
2. 断言直接原生入口默认关闭。
3. 断言禁用时容量、槽位、查询、命中、写入和替换诊断均为零。

### Green

1. 将开关和 MiB 容量从 GDScript 传入原生迭代搜索入口。
2. 在进度快照、最终结果和包装层 schema 中透传配置与诊断字段。
3. 暂不复用评分；先保证 API、默认值及关闭路径稳定。

### Verify

1. 构建 Windows Debug 原生库。
2. 运行 `test_duel_search.gd` 和 `test_native_production_rules.gd`。

## 任务二：实现固定两路表和紧凑动作

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/test_native_production_rules.gd`

### Red

1. 覆盖 0 MiB、8 MiB、容量向下取整和严格字节上限。
2. 覆盖空槽、同键更新、generation、深度、EXACT 优先及确定性冲突替换。
3. 覆盖紧凑动作从当前精确状态恢复并重新匹配合法动作；非法缓存动作被忽略。

### Green

1. 增加固定连续数组、两路组相联的 `TranspositionTable`。
2. 表在一次根搜索开始时分配，在返回时随局部对象释放，并跨迭代加深共享。
3. 条目保存完整精确键、评分、边界、剩余深度、generation、视野标记和紧凑动作。
4. 分配失败时安全关闭并记录 fallback。

### Verify

1. 运行表结构和动作恢复聚焦测试。
2. 检查 8 MiB 请求下实际条目字节数不超过上限。

## 任务三：接入 alpha-beta 查询、写入与 PV

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/test_native_production_rules.gd`

### Red

1. 覆盖 `EXACT` 直接返回、`LOWER` 抬高 alpha、`UPPER` 压低 beta 和边界截断。
2. 覆盖相同局面不同剩余回合边界不命中。
3. 覆盖超时、取消、节点限制和转移失败不写入。
4. 覆盖缓存条目的视野标记传播，避免错误 `solved`。
5. 覆盖缓存最佳动作排序优先级：`PV > TT > structural > History > canonical`。
6. 覆盖 EXACT 命中仍能恢复同回合 `principal_actions`。

### Green

1. 每个节点只计算一次 checksum，并同时供 TT、PV 和机会统计使用。
2. 查询发生在合法动作生成前；只在需要验证 TT 动作或继续展开时生成动作。
3. 捕获原始 alpha/beta，正常完成后写入 EXACT/LOWER/UPPER。
4. 用子树局部视野计数传播 horizon；缓存命中也传播。
5. 不完整节点直接返回且不写入任何条目。
6. 将合法 TT 动作接入排序和 principal-line 恢复。

### Verify

1. 运行边界、终止、PV 和固定深度 A/B 聚焦测试。
2. 对真实开局及派生局面比较 TT 开关两侧的评分与 canonical 根动作。

## 任务四：基准工具和容量消融

**修改：**

- `tests/benchmarks/production_opening_depth_profile.gd`
- `tools/run_production_opening_profile.ps1`

### Red/Green

1. 增加 `use_transposition_table` 和 `transposition_table_mib` 命令行选项。
2. 每局报告真实命中、EXACT 返回、边界截断、写入、冲突、替换、合法/非法缓存动作及分配结果。
3. 正常性能运行关闭高频诊断；单独运行 8 MiB 诊断样本。

### Verify

对同一四个 `extra_play_cap` 十秒 `self_turn` 开局依次运行：关闭、4、8、16、32 MiB。逐局比较完成深度、深度二进度、节点吞吐、动作和评分。

## 任务五：生产默认、完整验证和文档

**修改：**

- `scripts/duel_search.gd`
- `docs/AI_SEARCH.md`
- `docs/HANDOFF.md`
- 必要时 `docs/TESTING.md`

### 步骤

1. 在正确性测试通过后启用生产默认 8 MiB。
2. 构建 Windows Debug/Release 与 Android ARM64 Release 原生库。
3. 运行完整套件：

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
   ```

4. 静音走一遍生产 AI 普通出牌与额外出牌路径，确认深度显示、计划复用和超时发布正常。
5. 运行容量消融；若其它容量显著更好，只报告，不自行更改 8 MiB 默认。
6. 更新架构事实、实测证据、已知限制和后续优化方向。
7. 运行 `git diff --check`，确保没有生成物、签名材料或临时报告进入提交。

## 完成标准

- TT 开关两侧固定深度评分与 canonical 根动作一致。
- 超时、取消、节点限制和失败节点不污染表。
- 同回合 principal line 在缓存命中后仍完整合法。
- 8 MiB 是桌面和 Android 的共同生产默认，且实际表内存不超过请求上限。
- 四个真实开局无 fallback、unsupported 或非法动作，8 MiB 没有稳定性能倒退。
- 完整测试套件和本地 Windows/Android Release 构建通过。

