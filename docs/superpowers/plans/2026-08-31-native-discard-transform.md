# 原生弃牌、条件、变形与保留实例回手实施计划

**设计：**
`docs/superpowers/specs/2026-08-31-native-discard-transform-design.md`

**目标：** 在不接入生产路径、不实现召唤或额外攻击的前提下，为测试专用
C++ 紧凑内核加入完整弃牌事务、两种通用条件动作、目录变形和保留实例回手，
并保持所有受支持分支与 `DuelSimulator` 零差异。

## 工作规则

- 复用本任务刚完成的完整 `71/71` 套件基线；设计和计划文档不改变相关代码。
- `DuelSimulator` 始终是 oracle；原生实现不得检查具体卡牌 ID。
- 每次出牌仍在私有原生分支执行；抵达未知声明时不返回部分结果。
- 选择快照使用稳定 card index；弃牌移动同一 index，不创建新实例。
- 只有普通 board return 销毁旧 index；preserved discard return 复用原 index。
- 每个行为阶段先写合成 parity fixture 并确认红灯，再实现最小原语。
- 行为改动完成后运行原生探针和完整套件；不运行 Extended AI 赛程。

## 任务一：递归收集变形可达原型

**修改：**

- `scripts/duel_compact_state.gd`
- `tests/test_duel_compact_state.gd`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 增加 compact fixture：根状态只含 `SanRuDiYu1`，要求 fresh prototype 包含
   `SanRuDiYu1`、`SanRuDiYu2`、`SanRuDiYu3`，不包含无关目录牌。
2. 将 prototype 捕获改成 card-ID 队列；当前 runtime IDs 是初始种子。
3. 每创建一个目录原型，递归遍历其 normalized abilities 和嵌套 actions，收集
   合法 `transform_card.card_id`。
4. 去重并保持确定性队列顺序；循环变形引用不得死循环。
5. 旧 format-1 payload 兼容性和原型严格验证保持不变。

验证：

- 运行 `test_duel_compact_state.gd`。
- 运行现有原生探针，要求 `349/490`、零 mismatch 保持不变。

## 任务二：增加列表级条件上下文

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 增加 compiled action-condition 类型：最近弃牌数量至少 N、能力来源方手牌为空。
2. 增加 `IF` opcode，严格编译非空 conditions/actions，递归编译 child actions。
3. 为一次 `execute_actions` 建立可变 `ActionExecutionState`，初始最近批次大小为零。
4. 普通顶层动作共享该状态；`IF` child actions 共享；每个 selector target 的嵌套
   action list 使用符合 oracle 的局部动作上下文，同时保留正确能力来源。
5. 条件为假返回 no-effect；未知条件或非法声明保持 unsupported。
6. 用合成动作先直接写入测试用批次值，或与任务三 fixture 一同验证条件真假和
   `on_invalid_context` 行为。

验证：

- 条件为假不停止后续顶层动作。
- 来源离场后仍使用能力来源 owner snapshot 检查手牌。
- 未知 action condition 原子拒绝。

## 任务三：实现单张与批量弃牌事务

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 增加 `DISCARD_CARD`、`DISCARD_CARDS` opcode；前者严格编译 card reference，
   后者复用现有 selector compiler。
2. 增加共享 `discard_locked_cards()`：按快照顺序复验 hand 目标，只接受同一 owner，
   记录实时 logical index 和原物理 slot。
3. 所有合法 index 先移动到 owner discard vector，并清除 hand-slot flag。
4. 按 oracle 公式创建 batch ID，并生成完整 `card_discarded` 快照。
5. 一次计算全部剩余手牌的 slot 压缩，更新 compact slot 数组并生成按 from-slot
   排序的单个 `hand_cards_shifted`。
6. 把实际数量写回列表级执行状态。
7. 扩展 `EventContext` 以携带 discard owner、batch ID 和 batch size。
8. 扩展 `EventGroup` 的 source zone/index；`CARD_AFTER_DISCARDED` 只发现精确
   discard trigger instance，自身 rule 用稳定 handle 复验。
9. 逐张自触发完成后，全场 row-major 结算一次 `discard_batch_finished`；编译并
   支持 `CONDITION_DISCARD_OWNER_IS_SELF`。
10. 任何 reached listener 未支持则让整个私有 transition unsupported。

合成 parity fixture：

- 单张 discard；
- 两张和三张 batch；
- 物理左到右与右到左；
- 非连续 hand slots 的一次性压缩；
- 锁定后目标失效不补选；
- 自触发严格限于弃掉实例；
- 多张自触发和 batch-finished 的先后顺序；
- `LiJingRuLai3`、`LiJingRuLai4`；
- 未支持 batch listener 原子拒绝。

验证：

- 所有 accepted fixture 的 state key、state version、events、captures、exiles
  与 oracle 完全一致。
- 查看真实 Quick 新覆盖和首个下游拒绝，不以跳过触发提高数字。

## 任务四：实现卡牌变形

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 增加 `TRANSFORM_CARD` opcode，严格编译 card reference 和非空 card ID。
2. 定位精确 runtime index；缺少可达 fresh prototype 时 unsupported。
3. 从原型替换 template、card ID、四边、ki、ability-set index 和 runtime ability
   entries，并为新 entries 分配新 handles。
4. 清除 suppression flag/index，保留 instance ID、original owner、当前 zone/owner、
   reveal code 和 hand slot。
5. 生成完整 `card_transformed`；正在执行的旧 compiled rule 继续当前 action list。

验证：

- discard 中 `SanRuDiYu1 -> SanRuDiYu2`。
- discard 中 `SanRuDiYu2 -> SanRuDiYu3`。
- 运行时旧点数、ki、能力和 suppression 被目录初始值替换。
- 缺原型分支原子拒绝。

## 任务五：实现保留实例回手

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 让 `CompiledAction` 明确记录 `preserve_instance`；普通 return 行为保持不变。
2. preserved return 只接受 discard 中的精确 index，并按现有 recipient owner opcode
   解析接收方。
3. 非满手时从 discard 删除同一 index、分配最左槽、追加到 hand，并按现有 reveal
   code 顺序公开给对手。
4. 生成 `card_returned_to_hand`；仅新增 observer 时生成 `card_revealed`。
5. 满手时复用 `exile_card(..., "return_to_full_hand")`，保留完整前后移除触发。

验证：

- 三入地狱 1、2 完成 transform 后以同一 instance ID 回手。
- 已公开与仅 owner 可见两种 reveal 事件准确。
- 非连续 hand slot 填最左空位。
- 满手后同一实例进入 original owner removed zone。
- 目标在 discard 自触发中已离开时 no-effect。

## 任务六：真实 Quick、性能、完整回归和文档

**修改：**

- `tests/benchmarks/duel_native_compact_probe.gd`
- `docs/AI_SEARCH.md`
- `docs/HANDOFF.md`
- `native/duel_core/README.md`

步骤：

1. 运行固定 14 个 Quick 开局、490 个合法根出牌。
2. 要求 exact parity 等于 supported、mismatch 为零、unsupported 无部分结果。
3. 记录按卡牌和首个拒绝原因统计；明确新抵达的 summon/attack/add-card 拒绝。
4. 运行 5,000-transition 和 100,000-clone Debug 探针。
5. 运行 `git diff --check`。
6. 运行完整：

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
   ```

7. 文档写明列表级 batch 状态、discard-only trigger discovery、原型闭包、变形和
   preserved return 语义、最新覆盖、拒绝分类、parity checks 和性能。
8. 确认工作区没有构建产物、卡牌 ID 分支或生产 native 引用后提交。

## 停止条件

- accepted 分支与 oracle 有任何状态或事件差异时，停止扩大并修最小差异。
- 自弃牌或 batch listener 抵达 summon/attack 时保持 unsupported，不跳过事件。
- prototype 闭包无法确定性、无损表达时停止 transform 实现。
- batch size 无法准确穿透动作列表边界时先修上下文，不用 state side payload 代替。
- 完整套件失败时不宣布完成或接入生产。
