# Kunlun Cards Implementation Plan

> Execute with superpowers:executing-plans, using the user's previously selected native execution method.

**Goal:** 实装确认后的昆仑卡牌及连续行动尝试规则。
**Architecture:** 扩展目录原语，复用唯一 native 模拟器与控制器事件展示。
**Tech Stack:** Godot 4.7, GDScript, C++ Release.
**Spec:** `docs/superpowers/specs/2026-10-05-kunlun-cards-design.md`

## Global Constraints

- 保留目录手动修改，直接在本地 main 工作；不提交或导出 Android。
- 仅卡牌规则；不添加可选昆仑门派。16 个紧凑槽位，复用 11。
- 连续行动尝试先触发抽牌，首个实际可用类型生效，共用一次额度。
- 先失败测试再实现；完整测试、Release A/B、静音竖屏生产路径。

## Review Focus

- 无动作的早期候选不可阻止后一类型；抽牌改变可用性时检查最终状态。
- 特殊四 -1 点数可复制；四零仍走移除。
- 清除己方同类光环不影响另一方或其它标签。
- 生成八卦不递归扩展快照，不绕过召唤上限。
- 斜攻能力同时影响原生攻击、提示与闪避；旧无限攻击保持原语义。

## Task 1: Native rules and catalog

**Files:** `scripts/card_catalog.gd`, `scripts/duel_state.gd`, `scripts/duel_compact_state.gd`, `scripts/duel_state_key.gd`, `scripts/duel_native_rules.gd`, `native/duel_core/src/*`, `tests/test_kunlun_abilities.gd`, existing compact/GuMu fixtures.
**Interfaces:** `DuelSimulator.apply_action`, native compiled actions, scalar 11 `extra_activation_only`, trigger `continuous_action_attempt`.

- [x] Retain current source and matching Release DLLs; baseline 90/90 in 297.82s reused (only prose changed).
- [x] Write/run real catalog fixtures RED for formations, diagonal attacks, point-copy activations, movement and continuous action selection.
- [x] Extend generic declarations and state slot; instantiate exact approved ability arrays.
- [x] Run focused native/card/state/search suites GREEN and malformed declaration audits (234 Kunlun checks).

## Task 2: Presentation and production walkthrough

**Files:** `scripts/duel_controller.gd`, production controller integration fixture.
**Interfaces:** granted event `activation_only` controls text only; rules remain authoritative native.

- [x] Add RED for “额外指定” presentation and constrained legal input; retained old label fails / current passes.
- [x] Reuse existing VFX, powers/movement/summon/attack events.
- [x] Run muted portrait controller flows including both owners and actual AI (149 visible / 33 headless checks).

## Task 3: Final verification and documentation

**Files:** `tools/run_tests.ps1`, `docs/HANDOFF.md`, architecture/ability/testing docs.
**Interfaces:** canonical full suite and same-machine fixed-5000-node Release comparison.

- [x] Rebuild both Windows native ABIs; interleaved A/B unchanged fixtures; initial timing difference reported and isolated follow-up found no stable regression (60 samples/version, +0.31% pooled median).
- [x] Run canonical full suite (92/92, 297.70s); one fresh read-only whole-change reviewer; no substantive remaining findings.
- [x] Update design with final declarations and evidence, handoff and plan status.
