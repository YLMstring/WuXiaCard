# 进阶零降难与进阶序列后移实施计划

## 目标

将难度范围扩展为 `0..10`，新增十二敌人、深度一的新进阶零，并把旧
进阶体系整体后移；对现有存档和门派最高分进行一次性、可验证的迁移，
同时在结局滚动文字末尾提示本轮新解锁的进阶。

## 实施顺序

### 1. 先建立失败测试

修改以下测试，使其明确表达新规则并在旧实现上失败：

- `tests/test_difficulty_rules.gd`
  - 十一个进阶文本；
  - 敌人数 `12/13/14/15`；
  - 搜索深度 `1/2/3/无限`；
  - 所有旧进阶效果门槛加一。
- `tests/test_deck_profile_store.gd`
  - 新 schema 与最大进阶十；
  - schema 13 的零档、非零档、活动轮次和最高分迁移；
  - 全进阶解锁上限。
- `tests/test_ending_profile.gd`
  - 进阶零至二均封顶 500；
  - 新敌人数门槛；
  - 首次解锁摘要携带新进阶，重复通关和进阶十不携带。
- `tests/test_ending_scene.gd` / `tests/test_ending_flow.gd`
  - 滚动正文末尾追加汉字解锁提示。
- `tests/test_sect_selection_integration.gd`、
  `tests/test_reward_selection_integration.gd`、
  `tests/test_main_flow.gd` 和相关对局测试
  - 进阶十显示、选择循环、全解锁和新阈值。

运行上述聚焦测试，确认它们因旧规则失败。

### 2. 更新集中难度规则

修改 `scripts/difficulty_rules.gd`：

- `MAX_DIFFICULTY = 10`；
- 插入新进阶一文本；
- 更新胜利数、八卦、奖励、隐藏点数、思考时间和搜索深度门槛。

修改 `scripts/duel_initial_state_factory.gd`、`scripts/duel_state.gd` 和
`scripts/duel_controller.gd` 中仍写死 `0..9` 的运行难度边界。

### 3. 实现 schema 14 存档迁移

修改 `scripts/deck_profile_store.gd`：

- 升级 schema，增加本次进阶插入的迁移版本常量；
- 当前 schema 的最大进阶改为十，低难度分数上限覆盖 `0..2`；
- schema 13 难度字段按“零不动、非零加一”迁移；
- schema 13 的旧零成绩写入新零与新一，旧一至九写入新二至十，随后
  恢复向低难度传播不变量；
- 更旧 schema 先按既有规则修复成旧难度语义，再应用同一插入迁移；
- 全进阶解锁、校验、读取和通关解锁统一使用最大值十。

### 4. 实现结局解锁提示

在 `record_completed_duel_and_save()` 中比较解锁前后的
`max_unlocked_difficulty`。若本次确实提高，将新编号写入仅存在于返回值
中的 `ending_summary.unlocked_difficulty`；否则省略或写为无效值。

修改 `scripts/ending_controller.gd`，集中格式化零至十的汉字编号，并在
`build_story()` 末尾追加“（已解锁进阶n！）”。不增加存档字段。

### 5. 更新选择和检查 UI

将门派选择与奖励检查使用的汉字数组扩展到“十”，确保箭头在
`0..10` 循环，进阶十的标题、效果和最高分文本正确。保持进阶零无文本、
只有进阶零可用时隐藏箭头等既有交互。

### 6. 更新当前文档

同步修改：

- `docs/HANDOFF.md`
- `docs/DECISIONS.md`
- `docs/AI_SEARCH.md`

历史设计文档保持历史原貌，不批量改写。

### 7. 验证

1. 逐个运行难度、存档、结局、门派选择、奖励和主流程聚焦测试。
2. 运行 `git diff --check`。
3. 运行完整命令：

   `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`

4. 用 Dummy 音频在 540×960 生产路径检查进阶十和结局解锁文字。
5. 本次不修改 C++ 搜索算法；若测试证明纯难度参数变化无需原生重编，
   不额外构建原生库或 Android 包。

