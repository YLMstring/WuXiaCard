# 原生主动能力事务实施计划

**设计：**
`docs/superpowers/specs/2026-09-01-native-activation-transitions-design.md`

**目标：** 一次完成测试专用 C++ 紧凑内核中当前牌库全部主动能力的编译、合法行动枚举、
费用和目标验证、效果执行、指定后触发与共用回合收尾。所有接受的主动行动必须与
`DuelSimulator` 的完整状态和事件精确一致；本计划不接入生产搜索。

## 工作规则

- 复用刚通过的 `71/71` 完整套件与 1,487 项原生探针基线；相关代码改变前不重复基线。
- `DuelSimulator` 是唯一 oracle，C++ 不检查具体卡牌 ID。
- 复用现有编译动作池、运行时能力句柄、移动/攻击/进场/弃牌/抽牌与 `finish_action`。
- 每个行为任务先增加 native-oracle fixture，再实现；每阶段只跑原生探针。
- 完整套件只在全部主动能力完成后运行一次。
- 所有公开执行入口继续复制私有 `NativeState next`；失败不得泄露部分结果。
- 每个任务独立提交。

## 任务一：编译主动声明并精确枚举合法目标

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 增加 `TargetRuleOpcode` 和 `CompiledActivation`，编译目标规则、累计内力、费用动作与
   效果动作；删除只记录 `has_activation` 的占位逻辑。
2. 从运行时有序能力条目中提取当前有效主动能力，编号只计入带有效 activation 的条目。
3. 实现八种目标规则，保持相邻方向、棋盘行优先和逻辑手牌顺序。
4. 实现精确 `can_pay_activation` 与 `has_legal_activation_for_owner`，替换终局和空回合的
   粗略“存在主动能力”判断。
5. 增加原生合法行动枚举入口，输出 action type/source/instance/target/activation index；
   顺序与 oracle 完全一致，额外出牌期间只枚举手牌出牌。
6. 为八种目标规则、内力不足、空目标、效果门控和多个主动能力顺序建立 fixture。

验证：原生探针通过；原有 490 个根手牌出牌仍零差异。

建议提交：`Compile native activation targets`

## 任务二：实现主动事务、费用与指定后事件

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 增加 `apply_activate_transition` 公开入口，重新验证当前方、来源实例、主动索引、费用和
   指定目标。
2. 建立 ability-source 与 selected-card 的不可变引用上下文，生成 `ability_activated`。
3. 用共用执行器按声明顺序支付编译费用，再执行主动动作；累积攻击、进场和额外出牌请求。
4. 扩展 `EventContext` 的 activation source/owner/target 信息，结算全场
   `card_after_targeted_activation`。
5. 调用共用 `finish_action`，保持额外出牌、结束节点、空回合和终局顺序。
6. 深层 unsupported 或失效 context 原子拒绝；根状态和返回数组保持为空。
7. 为普通指定、来源移动、来源离场、目标移动/离场和主动后的额外出牌建立 fixture。

验证：原生探针通过，主动事务的 state key、state version、captures、exiles、events
均与 oracle 相同。

建议提交：`Add native activation transactions`

## 任务三：补齐主动专用动作和格子引用

**修改：**

- `native/duel_core/src/duel_native_compact_kernel.h`
- `native/duel_core/src/duel_native_compact_kernel.cpp`
- `tests/benchmarks/duel_native_compact_probe.gd`

步骤：

1. 编译执行 `move_self_to_target`，复用全场 before/moved/after 移动事务和来源重定位。
2. 编译执行 `swap_self_with_target`，锁定指定实例并按 oracle 两段顺序移动、逐段重验。
3. 编译执行 `reveal_card`，支持手牌目标、观察者换算、公开顺序和仅首次公开事件。
4. 让 `CELL_REF_ACTIVATION_TARGET` 从主动 action context 读取原始指定棋盘格。
5. 覆盖有凤来仪三种主动、寒冰真气、剑法精要以及手牌目标在费用后失效的场景。

验证：相关真实卡牌 fixture 与原生完整探针通过。

建议提交：`Add native targeted activation actions`

## 任务四：覆盖全部真实主动能力与真实状态语料

**修改：**

- `tests/benchmarks/duel_native_compact_probe.gd`
- 必要时修改通用原生条件/动作实现

步骤：

1. 为燃木刀法、无相劫指、梯云纵、三环套月、大魁星和雁回祝融增加真实声明 fixture。
2. 覆盖主动动作中生成进场、重新进场、批量攻击、弃牌连锁、移除区实例和来源新实例。
3. 覆盖多个先天主动能力、动态主动替换、能力失去后编号变化与过期 action 拒绝。
4. 从真实 Quick 派生状态收集全部 oracle 合法主动行动；逐行动比较完整结果。
5. 若真实语料缺少某种目录主动能力，用目录实例构造补充状态；不以卡牌数量写脆弱断言。
6. 保持所有手牌出牌 parity fixture 同时运行，防止共享动作回归。

验证：固定真实语料的合法主动行动全部 supported 且 exact parity，零 mismatch。

建议提交：`Cover native catalog activations`

## 任务五：完整回归、性能和文档收口

**修改：**

- `docs/AI_SEARCH.md`
- `docs/HANDOFF.md`
- `docs/ARCHITECTURE.md`
- `native/duel_core/README.md`（若存在）

步骤：

1. 重新构建 Windows Debug GDExtension，运行完整原生探针。
2. 记录手牌出牌和主动行动各自的总数、支持数、精确一致数与拒绝原因。
3. 增加固定主动事务微基准，记录原生与 oracle 的 Debug 吞吐；不为保留倍数牺牲通用性。
4. 检查 C++ 不含 named-card 分支，生产路径没有新增原生依赖，构建产物未进入 Git。
5. 运行唯一一次行为完成后的完整套件：

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
   ```

6. 更新文档并提交；明确生产仍使用 `DuelSimulator`。

建议提交：`Document native activation coverage`

## 停止条件

- 任一 accepted 主动行动与 oracle 的状态或有序事件不同，先修最小差异再扩大范围。
- 无法区分逻辑手牌索引、物理手牌槽或 exact instance 时，不猜测目标。
- 来源移动/离场后不能保留正确 ability-source snapshot 时，不用当前格近似。
- 激活索引若错误采用完整能力数组索引而非有效主动能力数组索引，立即停止并修正。
- 深层 unsupported 返回部分结果、完整探针出现 mismatch 或完整套件失败时，不宣布完成。
