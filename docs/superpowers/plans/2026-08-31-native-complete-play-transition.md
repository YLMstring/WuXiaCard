# 原生完整出牌与回合生命周期实施计划

**设计：**
`docs/superpowers/specs/2026-08-31-native-complete-play-transition-design.md`

**目标：** 以实现效率和减少返工为优先，一次完成测试专用 C++ 紧凑内核中
`apply_play_transition` 从手牌出牌、进场与连锁、行动收尾、回合结束、终局判断到
下一个可行动回合的完整生命周期。所有已接受分支必须与 `DuelSimulator` 精确一致；
不以阶段覆盖率作为任务排序或验收标准，不接入生产搜索。

## 工作规则

- 复用本任务刚完成的 `71/71` 完整套件和 `1,034` 项原生探针基线；文档改动没有
  改变相关代码，实施前不重复运行基线。
- `DuelSimulator` 始终是 oracle；C++ 条件、动作和流程不得检查具体卡牌 ID。
- 先抽取共享事务，再启用新声明，避免为苍松、独孤、云雾、葵花等分别写路径。
- 每个行为任务先添加最小 native-oracle parity fixture，确认旧实现不能通过，再实现。
- 每次原生行为任务只运行相关探针和必要的聚焦 GDScript 套件；完整套件只在所有
  行为改动完成后运行一次。
- 所有公开原生调用继续使用私有 `NativeState next`；深层 unsupported 不得返回部分
  state、events、captures 或 exiles。
- 不运行 Quick/Extended AI 对战赛程；这一步仍是 transition kernel 正确性工作。
- 每个任务形成独立提交，方便定位 parity 回归和性能变化。

## 任务一：固定完整生命周期声明清单与紧凑元数据边界

**修改：**

- `scripts/duel_compact_state.gd`
- `tests/test_duel_compact_state.gd`
- `tests/benchmarks/duel_native_compact_probe.gd`
- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`

步骤：

1. 在探针中增加只用于诊断的递归 trigger-declaration inventory：遍历目录能力中的
   triggers、conditions、selectors 和嵌套 actions，打印本切片会触达的通用词汇；
   不按卡牌数量或门派数量写脆弱断言。
2. 为完整生命周期建立聚焦 fixture 分组和统一 parity helper，能比较 restored state、
   canonical key、state version、captures、exiles 和完整有序 events。
3. 在 compact rule metadata 中增加空牌库 fallback prototype 的专用引用；捕获根状态
   时显式驻留该目录初始原型，而不是让 C++ 热路径按 ID 查目录。
4. 保持 format-1 向后兼容：旧 payload 可加载，但抵达空牌库 fallback 时保守
   unsupported；新 payload 严格验证 prototype 下标。
5. 增加 suppression batch 的 lossless round-trip fixture，覆盖能力声明、原位置和到期
   owner-turn serial；本任务先不改变原生执行结果。

验证：

- 运行 `test_duel_compact_state.gd`。
- 运行现有原生探针，要求原有 accepted 分支仍零 mismatch。
- inventory 只作诊断，不把当前支持数量写成永久测试常量。

建议提交：`Add native lifecycle metadata fixtures`

## 任务二：抽取共享 summon、attack、movement 与 finish 骨架

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 从 `apply_play_transition()` 抽取 `resolve_attack_request()`，让现有标准进场攻击通过
   typed request 调用它；保持目标选择、二十次上限、翻面和 after-attack 顺序不变。
2. 抽取 `move_card_between_cells()`，复用已有 swap 的 before/moved/after 事件解析、
   exact-instance 复验和 source-cell 更新。
3. 抽取 `resolve_summon_lifecycle()` 骨架；本任务只接回现有 hand-play 的已支持阶段，
   仍不解除 before-summoned/card-summoned gate。
4. 抽取 `finish_action()`，先严格保持现有无回合 trigger、无 extra-play 分支的结果。
5. 将事件、captures、exiles 合并集中到 `Resolution` helper，移除主方法内重复代码，
   但不更改公开 payload。
6. 保持 action counter、state version、last-hand-play、repetition 和 empty-turn 的现有
   accepted 行为完全一致。

验证：

- 为抽取前已支持的普通进场攻击、翻面、移除、discard/transform/return/swap 路径运行
  原生探针。
- exact parity 数和 accepted 数都不得变化；本任务是纯结构重构。
- 运行 `git diff --check`。

建议提交：`Extract native play lifecycle transactions`

## 任务三：类型化临时失能与待消费永久失能

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 增加 `RuntimeSuppressionBatch` 和 entry 类型，保存到期 serial、原能力位置、compiled
   ability index 和稳定 handle；每个 runtime card index 自带批次数组。
2. load 时把 compact `temporary_suppression_batches` 编译为 typed entries；materialize
   时重建相同声明结构，确保下一次 native load 和 `DuelState.restore()` 无损。
3. 实现临时移除非保留能力：保留 retained entries，按原顺序记录其余 entries，生成
   `ability_lost temporary=true`，没有可移除项时 no-effect。
4. 实现所有 live zones 的到期恢复：board row-major，然后双方 hand/deck/discard/
   removed；按原位置插回并生成 `ability_gained temporary=true`。
5. 将恢复 helper 接到任务二的 owner-turn boundary：先恢复到期能力，再递增 serial；
   后续任务八只在这一位置前后增加 end/start trigger，不重写恢复流程。
6. 永久非保留能力删除和翻面删除继续清空该实例的临时批次，避免回合结束复活。
7. 解除已有 suppression-set gate，但仅接受能无损编译的 batch；未知 batch 原子拒绝。
8. 支持输入 state 中双方 pending suppression scalar。非心法手牌进场前消费一个，
   永久移除其非保留能力并发 suppression-consumed/ability-lost；心法不消费。
9. 消费和临时移除都作用于 exact runtime index；同 ID 全新实例不得继承旧批次。

合成 parity fixture：

- 场上、手牌、牌库、弃牌和移除区的能力恢复顺序；
- 多个 batch 反向到期后按原相对位置恢复；
- suppressed 实例中途移动区域后仍恢复；
- suppressed 实例销毁并生成同 ID 新实例后不恢复；
- 翻面/永久删除清除 batch；
- 非心法消费 pending suppression，心法跳过且保留计数；
- 已部分结束回合的 input payload 可无损往返。

验证：

- 聚焦 suppression parity fixture 全部通过。
- 运行原生完整探针，旧 accepted 分支保持零差异。

建议提交：`Add native runtime ability suppression`

## 任务四：补齐通用事件条件、反应攻击、条件移动与资源转移

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 扩展 `EventContext`：turn owner、trigger pre-zone/pre-owner、previous owner、winning
   owners、完整 attack-flip records 和 summon trigger context。
2. 编译并执行本生命周期需要的 generic conditions：
   - trigger ally/enemy/self、trigger adjacent/in-range；
   - source has empty between enemy；
   - trigger outside source-owner hand、trigger was enemy；
   - turn owner is self、owner did not win；
   - attack flipped ally in source range；
   - 已有 ki/moving/discard/action-list conditions 保持原义。
3. `trigger_card_in_range` 复用 generic attack range/modifier 规则，不能简化为相邻。
4. 增加 `ATTACK_TRIGGER_CARD` 和 `STANDARD_ATTACK_WITH_SELF` opcode，统一调用任务二
   的 attack request；targeted reaction 锁定 exact target，不自动顺延。
5. 增加 `MOVE_SELF_TO_FIRST_EMPTY_BETWEEN_ENEMY` opcode，按 oracle 的 cell/direction
   顺序锁定首个目标，再走共享 movement transaction。
6. 增加 `TRANSFER_CARD_RESOURCE` opcode：先转移 ki；不能转移时以 powers 为 fallback，
   复用现有逐次 ki/power 事件和四边为零移除链。
7. action subject、ability source、trigger、selected card 的 owner/cell snapshot 必须各自
   保持，嵌套 selector 不得把它们混为同一实例。

合成 parity fixture：

- 苍松式全场进场反应：范围内、范围外、目标消失、来源变更所属方；
- 剑发琴音首个中间空位移动和 movement listener；
- 梯云纵移除来源在己方手牌、敌方手牌和场上三种上下文；
- 太岳三青峰按 selector 顺序发起多个标准攻击；
- 吸星/北冥优先 ki、fallback powers、四边 `-1` 跳过与四边归零移除；
- 恒山反击只识别本次攻击中、仍处于来源攻击范围的友方翻面记录；
- 万花终局条件区分 winning owner。

验证：

- 聚焦 context/action parity fixtures 通过。
- 任一 exact target 在 `CARD_BE_ATTACKED` 中失效时不顺延。
- 深层 unsupported listener 不返回部分结果。

建议提交：`Add native event reaction primitives`

## 任务五：接通 summon-before、global summoned 与 extra-play 早退

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 移除 played-card before-summoned 整体 gate，按设计顺序在私有 board state 上派发
   `TRIGGER_CARD_BEFORE_SUMMONED`，随后插入 buffered placement event。
2. 接通全场 `TRIGGER_CARD_SUMMONED`；若 exact trigger instance 仍在场，再以其当前
   cell/owner 为 context，按 `0→8` 对全场所有监听器派发
   `TRIGGER_CARD_AFTER_SUMMONED`，而不是只检查进场牌自身。
3. 编译并执行 `REVEAL_HAND_CARDS`：typed recipient/filter，逐物理当前 hand 顺序更新
   reveal code，并生成完整 `card_revealed`。
4. 编译并执行 `GRANT_EXTRA_CARD_PLAY`，以 request 形式记录 owner、source 和 amount；
   action list 不直接改回合。
5. 编译并执行 `ADD_PENDING_NON_RETAINED_SUPPRESSION`，更新相对 owner scalar 并生成
   完整 added event。
6. 启用任务三已完成的 `TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES` opcode。
7. 扩展任务二的 `finish_action()`：先增加 action/state version，汇总当前行动的 extra
   requests；若同 owner 仍有合法 hand play，保留 active owner 并早退，不派发 end turn。
8. 输入已有 extra play 时，开始出牌即消费一个；仅允许继续出牌，不允许根主动能力。
9. last-hand-play 仍记录这次从手牌打出的原实例，即使它在 summon-before 中自我移除。

合成 parity fixture：

- `DuGu9Jian1` 揭示、无移除离场/移除、抽牌、相邻处理的精确事件顺序；
- `DuGu9Jian2/3` 自我移除后仍正确使用 ability-source snapshot；
- summon-before 额外出牌保留同一 active owner；
- pending suppression 在下一张非心法 hand play 进入 before-summoned 前消费；
- `YunWu13Shi2/3` 全场敌方临时失能，随后按任务三的边界 helper 恢复；
- `TRIGGER_CARD_SUMMONED` 全场监听器按 row-major 顺序处理 ally/adjacent 条件；
- `TRIGGER_CARD_AFTER_SUMMONED` 同样全场发现，非进场牌上的监听器也会结算；
- before-summoned 中来源离场后跳过仅依赖其仍在场的 after/attack 阶段。

验证：

- 聚焦独孤、云雾、万岳 fixture 与 oracle 完整 parity。
- 运行原生完整探针，accepted 仍全部零 mismatch。

建议提交：`Add native summon-before lifecycle`

## 任务六：实现通用原地全新重新进场

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 编译 `RESUMMON_CARD_IN_PLACE` 的 exact card reference；未知字段或缺 prototype 时
   unsupported。
2. 重新定位目标当前 cell/owner，发 `card_departed_for_resummon`，无 exile/discard 地
   清除旧实例；旧 index 成为不可定位墓碑。
3. 从 fresh prototype 追加新 index，生成与 oracle 相同且无冲突的 instance ID；使用
   当前 owner 同时初始化 owner/original owner，重置点数、ki、能力和 suppression。
4. 调用任务二/五的共享 `resolve_summon_lifecycle()`，reason、source identity、事件
   payload 和进场攻击完全由通用流程生成。
5. 重新进场递归触发再次重新进场时允许继续，但每层仍受攻击次数和 unsupported
   原子性保护。

合成 parity fixture：

- `KuiHua3` 攻击确实翻面敌方后原位全新进场；
- 没有敌方被翻面时不触发；
- 旧实例不在 board/hand/discard/removed 任一区域；
- 新实例获得目录初始状态并完整触发 entry ability/attack；
- 重新进场前后目标 cell 或 source 已失效时 no-effect；
- 缺 prototype 和递归深层 unsupported 都不返回部分结果。

验证：

- 聚焦 resummon parity fixture 通过。
- 原生完整探针所有 accepted 分支零 mismatch。

建议提交：`Add native fresh in-place resummon`

## 任务七：完成逐张抽牌、空牌库补牌和难度八手牌变化

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 将 native `draw_cards()` 明确为逐张事务；每张之间完整处理公开、手牌变化、触发和
   下一张实时 top card。
2. deck 为空时通过 compact rule metadata 指向的 prototype 直接生成并抽到一张
   fallback 牌；不向 deck 额外塞牌，deck 继续为空。
3. 多张 draw 在同一个 action 内逐次检查空 deck，因此可逐次生成多张 fallback；full
   hand、draw reveal、draw triggers 和 effect-driven public reveal 保持 oracle 语义。
4. 抽取 `resolve_difficulty_hand_change()`；每次 hand size 变化后检查难度八：仅敌方手牌
   首次变为一时抽一张并记录 consumed flag。
5. 难度九沿用难度八 hand rule；开局随机手牌加点已存在于 captured state，本任务不
   重放初始化效果。
6. 移除 difficulty `>= 8` 和 empty-deck fallback 的 blanket gate，只在缺 rule metadata
   或抵达未知 hand-change 声明时原子拒绝。

合成 parity fixture：

- 空 deck 抽一张后直接获得一张 fallback，deck 仍为空；
- 空 deck 连抽两张、三张时逐张生成对应数量的 fallback；
- full hand 下逐张行为；
- fallback generated ID 冲突扫描；
- 难度八敌方从二变一触发一次、之后再次变一不触发；
- 玩家手牌变一不触发；难度七不触发；难度九继承；
- difficulty draw 自身使手牌离开一后不递归重复。

验证：

- 聚焦 draw/difficulty parity fixtures 通过。
- compact round-trip 和原生完整探针保持零 mismatch。

建议提交：`Add native empty-deck and hand-change rules`

## 任务八：完成 end/start turn、终局与连续空回合

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 扩展 `finish_action()`：若没有可继续的 extra play，且 end triggers 未结算，派发
   `TRIGGER_END_OWNER_TURN`；标记 resolved，再应用其 extra requests。
2. end-turn 产生合法 extra play 时保留同 owner 和 resolved flag；下一次 play 完成后
   不重复派发 end trigger。
3. 在 full board 时派发 `TRIGGER_BEFORE_DUEL_END`，使用 winning-owner context；若事件
   改变局面，重新依据权威终局规则判断。
4. 调用任务三的临时能力恢复，随后增加 owner-turn serial、清攻击计数、清 end flag、
   记录 card-ID/owner board repetition signature。
5. 仅在完整 owner-turn boundary 后检查 action limit、五次完全重复和满场，且必须在
   下一人的 start event 之前停止。
6. 未终局时切换 owner，派发 `TRIGGER_START_OWNER_TURN`；start trigger 可攻击、改点、
   转移资源、移除、授予/删除能力并产生完整连锁。
7. 若 start triggers 后仍无任何合法行动，仍派发该 owner 的 end triggers、before-end、
   restore 和 boundary，再判断终局；循环直到出现可行动 owner 或终局。
8. empty turn 的 extra play 只有存在合法 hand play 时才停止循环；否则清零并继续。
9. 移除 start/end blanket gates；reached unknown declaration 仍原子拒绝。

合成 parity fixture：

- 普通 player→opponent 与 opponent→player 边界；
- `ZiXiaGong` start/end 批量加点；
- `HanBinZhenQi` start 批量减点与四边归零移除；
- `SanQinFeng` start 多次攻击及二十次上限；
- `XiXing/BeiMing` start 资源转移；
- `HenShanJianZhen` end 动态授予能力；
- `KuiHua1` end 额外出牌与 resolved flag；
- `SanRuDiYu3` end 自我移除；
- `WanHuaJianFa` before-duel-end 自我移除并阻止原满场终局；
- action 达上限但已获 extra play 时继续，最终 action count 可超过上限；
- 无行动方仍完整 start/end；连续双方空回合直到终局；
- 第五次相同 card ID/owner board signature 在 boundary 后立即计分；
- end 后已终局时绝不触发下一方 start effect。

验证：

- 聚焦 lifecycle parity fixtures 全部通过。
- 原生完整探针 accepted 分支 state/events/captures/exiles 零 mismatch。
- 不允许通过跳过 listener 或提前终局获得表面通过。

建议提交：`Complete native owner-turn lifecycle`

## 任务九：完整回归、性能记录和文档收口

**修改：**

- `tests/benchmarks/duel_native_compact_probe.gd`
- `docs/AI_SEARCH.md`
- `docs/HANDOFF.md`
- `native/duel_core/README.md`

步骤：

1. 运行固定 14 个真实 Quick 开局，确认 legal opening/action 枚举未被 native 实现改变。
2. 要求 `exact_parity == supported`、`mismatches == 0`；记录任何仍 unsupported 的首个
   真实原因，但不设置覆盖率验收门槛。
3. 运行本计划所有 catalog-wide synthetic lifecycle fixtures，检查普通进场、嵌套攻击、
   extra play 和连续 empty-turn 都能 materialize 后再次 load。
4. 运行 5,000-transition 与 100,000-clone probe 一次，记录重构后的 Debug 速度和主要
   变化原因；不为了保留旧倍数破坏通用结构。
5. 运行 `git diff --check`，检查原生源码没有 named card-ID comparisons，也没有生产
   native 引用或构建产物。
6. 运行唯一一次行为改动后的完整套件：

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
   ```

7. 更新文档，说明 shared summon/attack/movement/finish transaction、typed suppression、
   fallback metadata、extra play、turn/terminal ordering、最新 probe checks 和性能。
8. 确认生产仍使用 `DuelSimulator`/LazyOnly，工作区只含计划内文件后提交文档收口。

建议提交：`Document complete native play lifecycle`

## 停止条件

- 任何 accepted 分支与 oracle 的状态、state key、state version 或有序事件不一致时，
  立即停止扩大声明范围，先修最小差异。
- 无法准确保存 action subject、ability source、trigger 和 selected card 四种身份时，
  不以当前 cell 或卡牌 ID 猜测。
- 临时能力批次无法跨 native materialize/load 无损恢复时，不解除 suppression gate。
- extra play 与 end-turn-resolved ordering 未经 parity fixture 证明前，不接 start-turn loop。
- empty-turn 循环无法保证每轮完整 start/end 和终局时点时，不用跳过事件的近似实现。
- fallback prototype 缺失时保持 unsupported，不在 C++ 中硬编码目录卡牌属性。
- 完整套件失败、原生探针出现 mismatch 或工作区混入构建产物时，不宣布完成。
