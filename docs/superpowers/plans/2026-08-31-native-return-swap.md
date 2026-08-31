# 原生移回手牌与相邻交换实施计划

**设计：**
`docs/superpowers/specs/2026-08-31-native-return-swap-design.md`

**目标：** 在不接入生产路径、不实现弃牌事务的前提下，为测试专用 C++ 紧凑内核
加入普通场上牌移回手牌和相邻交换，争取把 14 个真实 Quick 开局的原生支持数从
`341/490` 提高到 `352/490`，并保持所有受支持分支与 `DuelSimulator` 零差异。

## 工作规则

- 复用本任务刚完成的完整 `71/71` 套件基线；设计和计划文档没有改变相关代码。
- `DuelSimulator` 始终是 oracle；原生实现不得检查具体卡牌 ID。
- 每次出牌仍在私有原生分支执行；抵达未知声明时不返回部分结果。
- 稳定 card index 不复用：被普通返回销毁的旧实例成为不可定位墓碑。
- `preserve_instance = true`、弃牌、任意移动和生产搜索接入不在本计划内。
- 每个行为阶段先用合成 parity fixture 验证，再查看真实 Quick 覆盖。
- 行为改动完成后运行原生探针和完整套件；不运行 Extended AI 赛程。

## 任务一：为 compact root 增加全新实例原型

**修改：**

- `scripts/duel_compact_state.gd`
- `tests/test_duel_compact_state.gd`
- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`

步骤：

1. `DuelCompactState` 捕获完所有运行时实例后，收集根状态中不同的 `card_id`。
2. 对每个 ID 调用一次 `CardCatalog.create_instance()`，把默认 immutable template 和
   normalized ability set 驻留到现有池中。
3. 新增共享的 prototype 数组；每项只保存 card ID、template index、默认四边、起始
   内力和默认 ability-set index。
4. `duplicate_compact()` 共享 prototype 数组；完整 variant payload 输出它，mutable
   branch payload 不重复深拷贝它。
5. `load_variant_payload()` 接受缺少该字段的旧 format-1 payload；有字段时严格验证
   类型、四边长度和池下标。
6. 原生 root 加载并编译为 card-ID 查找表；分支复制共享只读原型，不把目录
   Dictionary 放入热路径。
7. 原生 materialized payload 原样带回 prototype metadata。

验证：

- compact round-trip 状态键和 `state_version` 保持不变。
- 修改过点数、内力和能力的运行时牌，其 prototype 仍是目录初始值。
- 旧 payload 无 prototype 时仍可加载和执行不需要新实例的路径。
- 运行 `test_duel_compact_state.gd` 与原生探针现有用例，覆盖数暂时允许不变。

## 任务二：实现普通场上牌移回手牌

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 增加 `RETURN_CARD_TO_HAND` opcode、`CARD_ORIGINAL` owner opcode，以及编译后的
   recipient/preserve-instance 字段。
2. 严格接受普通返回声明；`preserve_instance = true` 或未知字段保持 unsupported。
3. 复用当前 action-context 卡牌引用和 selected-card 条件复验；只接受仍在场的精确
   目标。
4. 满手时以 `return_to_full_hand` 调用现有完整 exile 生命周期。
5. 非满手时在旧目标仍在场时扫描所有可定位实例，生成与 oracle 相同的新 ID。
6. 清空旧 board cell，但保留旧 card index 为不可定位墓碑；不得复用其 index。
7. 从 prototype 向所有 packed/native card 数组追加一个新 index，创建默认能力条目和
   新临时能力句柄，设置原所属方、公开顺序和最左空手牌槽，再追加到接收方 hand。
8. 精确生成 `card_returned_to_hand` 和紧随其后的 `card_revealed`；事件卡牌快照必须是
   公开后的完整新实例。
9. 输出 payload 允许未被任何 zone 引用的旧墓碑；restore 后的权威状态不得包含它。

验证：

- mutated 目标返回后恢复默认点数、内力和先天能力。
- 新旧 instance ID、ID 冲突扫描、逻辑 hand index、物理 slot 和公开顺序准确。
- 多目标按最初快照顺序执行；旧目标消失后不补选。
- 满手外部移除时点与事件准确。
- 缺少 prototype 的分支原子拒绝。
- 原生探针所有 accepted 分支继续零差异。

## 任务三：实现两段移动生命周期和相邻交换

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 增加 `SELF_SWAPPED_WITH_ABILITY_SOURCE` opcode，以及移动事件上下文中的旧 cell、
   目标 cell 和 previous cell。
2. 增加本切片需要的 `MOVING_CARD_IS_SELF`、`MOVING_CARD_IS_ALLY` typed condition；
   不把其它移动条件误判为已支持。
3. 编写通用 `resolve_movement_event()`：发现全场监听器，使用移动牌作为 trigger card，
   逐组复验并合并事件/captures/exiles。
4. 第一段先派发能力来源的 `CARD_BEFORE_MOVED`，复验双方，预留 selected target，移动
   来源并发 `card_moved`、`CARD_AFTER_MOVED`。
5. 第二段派发 selected target 的 before，复验后移至来源旧 cell，再发 moved/after。
6. 任一 reached listener 未支持则让整个私有 transition unsupported；任一牌被归零
   移除、换所属方或不再相邻时按 oracle 结束/回滚相应 reservation。
7. 成功 action 返回能力来源的新 cell；外层 summon 标准攻击重新定位该实例，从新
   cell 开始。

验证：

- 无监听器相邻交换产生两个有序 `card_moved`。
- before-move 改点和归零移除能取消对应移动。
- after-move 监听器在新 cell 观察移动牌。
- 未支持移动 listener 原子拒绝且无部分输出。
- `TaiShan18Pan2`、`KuiHua3` 合成局面与 oracle 完整 parity。
- 交换后的标准攻击方向和目标与 oracle 一致。

## 任务四：真实 Quick、性能、完整回归和文档

**修改：**

- `tests/benchmarks/duel_native_compact_probe.gd`
- `docs/AI_SEARCH.md`
- `docs/HANDOFF.md`
- `native/duel_core/README.md`

步骤：

1. 运行相同 14 个 Quick 开局、490 个合法根出牌，保留按卡牌和首个拒绝原因统计。
2. 要求 exact parity 等于 supported、mismatch 为零、unsupported 无部分结果。
3. 目标覆盖为 `352/490`；若低于目标，记录新抵达的真实 downstream 拒绝，不放宽
   gate 伪造覆盖。
4. 运行 5,000-transition 和 100,000-clone 探针，记录 Debug 构建速度；不以微基准
   单独决定生产采用。
5. 运行 `git diff --check`。
6. 运行完整：

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
   ```

7. 文档写明 prototype boundary、墓碑索引、返回/交换 opcode、最新覆盖、拒绝分类、
   parity checks 和性能。
8. 确认工作区没有构建产物、卡牌 ID 分支或生产 native 引用后提交。

## 停止条件

- prototype 不能从目录初始值无损表达时，不从当前运行时实例猜测。
- 第一张返回会使后续 selection snapshot 错认新实例时，先修正稳定身份，不继续扩大。
- 任一 accepted 分支与 oracle 状态或事件不同，停止扩大覆盖并修最小差异。
- swap 的 reached movement listener 无法精确复刻时保守拒绝，不跳过事件。
- 完整套件失败时不宣布完成或接入生产。
