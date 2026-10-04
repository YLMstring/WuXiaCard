# 跨门派同名随机过滤 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking. 用户已授权开始，沿用本会话 native 执行方式。

**Goal:** 开局和普通奖励不再随机获取其它门派已解锁同名牌。

**Architecture:** 在 DeckProfileStore 从解锁 ID 构建名字与门派的临时索引；候选生成共享过滤。开局输入额外包含即将解锁的本门派一阶 ID，最终保存仍为一次原子事务。

**Tech Stack:** Godot 4.7 GDScript，Windows PowerShell 测试工具。

**Spec:** `docs/superpowers/specs/2026-10-04-cross-sect-namesake-random-filter-design.md`

## Global Constraints

- 同名按 `glyph`，其它门派按 `sect`，跨品阶过滤；本门派固定解锁照常。
- 不新增存档状态，不修改战斗、副牌或 AI；保底奖励及已保存待选奖励照常。
- 当前无可选昆仑派；通过真实抽样入口验证其一阶开局过滤，不新增门派。
- 复用本次已运行完整基线：88/89 通过；失败测试四项仍使用目录变更前的初始点数。
- 用户之前要求在本地 main 工作，本次继续直接在当前工作区实现并保留无关改动。

## Review Focus

- 低阶解锁必须排除其它门派所有品阶，而不能仅排除同阶。
- 开局过滤必须考虑即将解锁的门派牌；已拥有牌回退不能绕过过滤。
- 同门派高阶、固定升阶解锁及保底奖励不应被误伤。
- 旧存档同时拥有两个门派同名牌时不删除旧牌，后续普通随机都排除。
- 保存失败不能更改传入 profile；重新加载和重置使用最新解锁记录推导。

### Task 1: 随机候选过滤与回归

**Files:** `scripts/deck_profile_store.gd`，`tests/test_cross_sect_namesake_rewards.gd`，`tools/run_tests.ps1`。

**Interfaces:**
- `_build_random_namesake_filter(unlocked_ids: Array) -> Dictionary`：`glyph -> sect 集合`。
- `_card_passes_random_namesake_filter(definition: Dictionary, filter: Dictionary) -> bool`。
- 现有开局抽样函数签名不变；用原解锁 ID 加 `sect_tier_one_ids` 构造过滤。

- [x] 新增真实目录夹具：昆仑/恒山一阶已拥有，各品阶普通胜败奖励排除异门派，同门派高阶及不同名保留；两门派均已拥有时保留原牌但排除后续随机。
- [x] 添加开局抽样、关联解锁、固定升阶、重新加载、重置与保存失败的覆盖，注册到完整 runner。
- [x] 静音运行新套件，确认缺失过滤导致失败，保存 RED 日志。
- [x] 实现两个共享函数，在两个候选入口过滤，保留抽样与保存顺序。
- [x] 运行新套件与现有组牌/奖励套件，确认 GREEN。

### Task 2: 基线修正、实际流程与完整验证

**Files:** `tests/test_yusui_kungang_abilities.gd`，架构/决策/handoff 文档，本计划与设计文档。

**Interfaces:** Task 1 的候选过滤行为；无新公开接口。

- [x] 把旧玉碎测试的四个点数断言改为真实目录初始点数及独立手算衰减结果，不变更生产卡牌规则。
- [x] 静音运行该套件，保留原有回合归属与翻面保留效果检查。
- [x] 运行规范完整命令，要求所有套件 PASS，无 ERROR。
- [x] 静音竖屏实例化生产流程，验证开局、奖励领取和下一次奖励生成；测试使用独立存档，保留结果/截图。
- [x] 更新文档，核对完整 diff，对实现做一次独立审查并处理实质问题。

验证命令：`powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`。
单套件：Summer.exe `--headless --audio-driver Dummy --path C:/mygame --script res://tests/<suite>.gd`。
