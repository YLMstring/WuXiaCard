# 原生弃牌、条件、变形与保留实例回手设计

## 状态

- 日期：2026-08-31
- 状态：已确认，待实施
- 权威规则：`DuelSimulator`、`DuelAbilityExecutor`、`DuelTriggers`
- 实现目标：测试专用 `DuelNativeCompactKernel`
- 生产接入：不在本切片范围内

## 目标

为测试专用 C++ 紧凑内核实现完整的现有弃牌事务，并顺带实现能在同一
状态模型内准确表达的简单通用动作：

- `ACTION_DISCARD_CARD`
- `ACTION_DISCARD_CARDS`
- `ACTION_IF`
- `ACTION_TRANSFORM_CARD`
- `ACTION_RETURN_CARD_TO_HAND` 的 `preserve_instance = true` 形式

本切片必须保持声明驱动和卡牌无关。`DuelSimulator` 继续作为唯一 oracle；
原生分支只有在完整理解实际抵达的声明时才能返回结果。

## 非目标

本切片不实现：

- `ACTION_SUMMON_CARD` 及任何进场/标准攻击管线；
- `ACTION_STANDARD_ATTACK_WITH_SELF` 或其它额外攻击；
- `ACTION_ADD_CARD_TO_HAND`；
- 通用移动、重新进场、临时能力压制；
- 难度八、九的手牌变化规则；
- 生产搜索接入、Android 打包或原生状态键。

弃牌后实际抵达上述未知动作时，整个私有原生 transition 必须原子拒绝，
不得返回部分 payload、事件、captures 或 exiles。

## 架构

### 编译后的声明

原生声明编译器增加对应 action opcode。`ACTION_IF` 只编译本切片已证明的
两种 action condition：

- `CONDITION_LAST_DISCARD_BATCH_SIZE_AT_LEAST`
- `CONDITION_SOURCE_OWNER_HAND_EMPTY`

未知字段、未知 card reference、未知 selector 或未知 condition 保持
unsupported。条件为假是正常 `NO_EFFECT`，不是 unsupported。

### 动作列表共享状态

同一次 `execute_actions` 调用需要一个可变的列表级执行上下文，其中保存
`last_discard_batch_size`。弃牌动作将它写成实际进入弃牌堆的数量；后续
同列表 `ACTION_IF` 读取该值。

嵌套 `for_each_selected_card` 仍为每个目标建立动作主体上下文，同时保留：

- 原始能力来源；
- 精确 selected card；
- 已快照的选择条件；
- 当前列表可见的弃牌批次结果。

上下文不得写入 `DuelState`，也不得成为跨事件持久状态。

### 弃牌触发来源

`CARD_AFTER_DISCARDED` 是特殊的离场自触发边界。它不扫描全场，只发现当前
位于弃牌堆中的精确 trigger instance 的自身能力，并以稳定 ability handle
重新验证。其它手牌、弃牌堆卡牌和场上卡牌都不能响应这个事件。

`TRIGGER_DISCARD_BATCH_FINISHED` 使用普通全场 row-major 发现流程，并在
`EventContext` 中携带：

- discard owner；
- batch ID；
- 实际 batch size；
- 原始 ability source instance 和 owner。

本切片编译 `CONDITION_DISCARD_OWNER_IS_SELF`。若监听器的实际动作仍未知，
该分支原子拒绝。

## 弃牌事务

### 目标锁定

`ACTION_DISCARD_CARD` 解析一个精确 card reference，并委托给与批量相同的
事务函数。

`ACTION_DISCARD_CARDS` 使用现有 compiled selector：

- 按声明的 zone 顺序访问；
- 手牌按物理 `hand_slot_index` 排序；
- `hand_right_to_left` 在物理顺序上反转；
- 先快照全部 instance；
- 不因后续目标失效而补选。

事务开始时再次定位每个锁定实例。只接受仍在手牌中的牌，且一个批次只能
弃掉同一当前 owner 的牌。首个合法目标确定 batch owner；其它 owner 的目标
跳过。

### 搬移与事件顺序

对最终合法目标按锁定顺序执行：

1. 从该 owner 的逻辑 hand vector 中删除精确 card index；
2. 记录删除当时的实时 logical hand index；
3. 记录原 `hand_slot_index`，清除手牌槽位 flag 和数值；
4. 将同一 card index 追加到该 owner 的 discard vector；
5. 保存完整运行时卡牌快照用于事件。

所有目标都进入弃牌堆后，按以下顺序生成和结算：

1. 每张实际弃牌一个 `card_discarded`，共享同一个 batch ID 和最终 batch size；
2. 根据所有被弃物理槽位一次性压缩剩余手牌；若存在移动，生成一个
   `hand_cards_shifted`；
3. 按实际弃牌顺序逐张结算其自身 `CARD_AFTER_DISCARDED`；
4. 最后向全场结算一次 `discard_batch_finished`。

批次触发链可以让较早弃牌变形、回手或离开弃牌堆，但不能改变后续预锁定
目标的顺序，也不能补选新目标。

### Batch ID

batch ID 与 oracle 完全一致：

```text
discard:<ability_source_instance_id>:<owner_id>:<turn_count>:<discard_size_before>
```

其中 `discard_size_before` 是本批次搬移任何牌之前的弃牌堆大小。

### 物理手牌槽位压缩

对每张剩余手牌计算其原槽位之前存在多少个本批次弃牌槽位：

```text
to_slot = from_slot - removed_slots_before(from_slot)
```

只记录槽位确实变化的牌。`moves` 按 `from_slot` 升序，字段严格为：

- `instance_id`
- `from_slot`
- `to_slot`

弃牌是唯一会压缩物理手牌槽位的离场方式。

## 条件动作

`ACTION_IF` 按声明顺序检查全部条件。所有条件为真时，在同一个列表级执行
上下文中执行 child actions；任一条件为假时返回 `NO_EFFECT`，后续顶层动作
继续。

`CONDITION_LAST_DISCARD_BATCH_SIZE_AT_LEAST` 比较当前列表最近一次弃牌动作的
实际成功数量。没有先前批次时视为零。

`CONDITION_SOURCE_OWNER_HAND_EMPTY` 优先使用原能力来源 owner snapshot；如果
来源已离场，仍按该 snapshot 检查其当前 hand vector。

这使 `LiJingRuLai4` 只有确实弃掉两张牌时才加三，也使已经离场的来源仍可
执行声明中的空手条件检查。

## 变形

### 可达原型收集

紧凑根状态的 fresh prototype 收集从当前所有 runtime card ID 开始。创建一个
原型后，递归扫描其 normalized active abilities 中的
`ACTION_TRANSFORM_CARD.card_id`，把合法目录目标加入待处理队列，直到闭包稳定。

因此含 `SanRuDiYu1` 的根会带上 `SanRuDiYu2`，并通过二阶原型继续带上
`SanRuDiYu3`。不把整个目录无条件复制进每个根状态；原型数组仍由 branch
共享。

### 运行时替换

`ACTION_TRANSFORM_CARD` 定位精确 card reference，并从对应 fresh prototype
重建该 card index 的：

- card/template ID；
- 四边点数；
- ki；
- active ability set 和新的 runtime ability handles。

它保留：

- `instance_id`；
- `original_owner`；
- 当前 board/hand/discard/removed 区域及当前区域 owner；
- reveal audience code 及顺序；
- 当前 hand slot（若仍在手牌）。

旧 suppression set 被清除。正在执行的旧 trigger group 使用已发现的稳定
规则快照继续完成当前 action list；新能力只参与后续事件发现。

成功时生成与 oracle 相同的 `card_transformed`，包含旧/新 card ID、位置、
owner、instance ID 和完整变形后卡牌快照。

缺少合法目录目标或到达的原型缺失是 compact-root/支持范围错误，必须
unsupported。精确实例已经离开可定位区域则是 `NO_EFFECT`。

## 保留实例回手

`ACTION_RETURN_CARD_TO_HAND` 在 `preserve_instance = true` 时只接受仍位于
弃牌堆的精确目标。

手牌未满时：

1. 从当前 owner 的 discard vector 删除同一个 card index；
2. 分配接收方最左空物理槽位；
3. 将同一个 index 追加到接收方 hand vector；
4. 设置手牌槽位 flag；
5. 按非抽牌加入手牌规则向对手永久公开；
6. 生成 `card_returned_to_hand`；仅在新增公开对象时紧跟
   `card_revealed`。

事件的 `old_instance_id` 和 `instance_id` 相同，`target_cell = -1`，事件卡牌
快照必须反映最终公开状态和 hand slot。

手牌已满时，精确弃牌实例不留在弃牌堆，而是通过现有完整 exile 生命周期
以 `return_to_full_hand` 原因进入其 original owner 的 removed zone。

## 原子性与错误处理

`apply_play_transition` 始终复制根状态后执行。下列情况令私有分支
unsupported，并返回空 events/captures/exiles 且无 payload：

- 实际抵达未知 action/condition；
- 变形声明引用未知目录 ID；
- 可达变形目标缺少 fresh prototype；
- 弃牌自身或 batch-finished 监听器抵达未实现的召唤/攻击等语义；
- 已支持动作的声明形状不合法。

普通运行时失效，例如目标已离开手牌、保留实例已离开弃牌堆、条件为假，
返回 `NO_EFFECT` 并按现有 `on_invalid_context` 规则决定是否停止当前 rule。

## 验证

### 合成 parity fixture

原生探针至少覆盖：

- 单张弃牌及实时 logical index；
- 两至三张批量弃牌、预锁定顺序与一个 shift event；
- 物理右到左选择；
- 部分锁定目标失效和实际 batch size；
- `LiJingRuLai3`、`LiJingRuLai4` 的条件加点；
- `CARD_AFTER_DISCARDED` 只发现精确弃牌自身；
- 多张弃牌的自触发顺序；
- `discard_batch_finished` 在所有自触发之后；
- `SanRuDiYu1 -> SanRuDiYu2`、`SanRuDiYu2 -> SanRuDiYu3` 的变形和同实例回手；
- 已公开/未公开保留实例的 reveal 事件差异；
- 满手保留实例的普通 exile；
- 缺少原型和未知弃牌后动作的原子拒绝。

每个 accepted fixture 必须比较：

- canonical state key；
- live `state_version`；
- captures；
- exiles；
- 完整事件数组及顺序。

### 真实 Quick 覆盖

运行固定 14 个真实 Quick 开局、490 个合法根出牌。要求：

- `exact_parity == supported`；
- mismatch 为零；
- rejected 分支没有部分输出；
- 记录新增支持数和每个新抵达的下游拒绝。

不预设最低覆盖数字；不得通过跳过弃牌触发或批次结束事件伪造支持。

### 性能与完整回归

记录 5,000 次 Debug 原生 transition 和 100,000 次 native branch clone，
但微基准不构成生产采用证据。

行为实现完成后运行：

```powershell
git diff --check
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
```

完整套件必须全部通过，并更新：

- `docs/AI_SEARCH.md`
- `docs/HANDOFF.md`
- `native/duel_core/README.md`

## 停止条件

- 已接受分支与 `DuelSimulator` 有任何状态或事件差异时，先修最小差异，不扩大范围；
- 自弃牌触发需要召唤或攻击时保持 unsupported，不跳过触发；
- 变形原型闭包不能无损表达目录初始状态时停止实现变形；
- 列表级 batch size 不能准确穿透现有嵌套上下文时，先修上下文边界；
- 完整套件失败时不得宣布完成或接入生产。
