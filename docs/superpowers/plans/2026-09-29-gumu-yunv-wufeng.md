# GuMu Tier-Three and YuNv Wufeng Implementation Plan

> **For agentic workers:** Execute natively in this session, task by task. Do not delegate. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Replace three GuMu tier-three activations with conditional YuNv Wufeng generation and implement the new card's locked play-source and entry effects.

**Architecture:** Catalog declarations drive the single native simulator path. Extend `ACTION_ADD_CARD_TO_HAND` with an optional duplicate guard, and add one compiled modifier checked only on the played hand instance before the existing queue/source decision. Reuse the existing summon events, adjacent selector, power change, extra-play grant, and pure-data presentation events.

**Tech Stack:** Godot 4.7 GDScript, C++ GDExtension, PowerShell test/build scripts.

**Spec:** `docs/superpowers/specs/2026-09-28-gumu-yunv-wufeng-design.md`

## Global Constraints

- `DuelSimulator`/native kernel remains the only rules path; `DuelController` only presents events.
- No named card IDs or whole-board/zone scans in search or generic play rules; inspect only the played instance or a five-card recipient hand when the option is set.
- Preserve fixed five physical hand slots, `instance_id`, existing extra-play cap/attempt behavior, and the FIFO next-hand effect queue.
- Record a matching pre-change Release native binary and exact source; use muted headless/device playtests; run the full suite after behavior changes.

## Review Focus

- Same-ID YuNv Wufeng already in a noncontiguous hand slot: no duplicate generation (Task 1).
- Hand full during tier-three entry: generation returns `NO_EFFECT` but later entry/attack effects continue (Task 1).
- Source override plus an existing discard-source opportunity: the marker clears once and the queue stays intact (Task 2).
- Multiple adjacent enemies, one exiled by power reaching zero: next selected enemy revalidates and is still processed (Task 3).
- Extra-play cap already used: grant attempt still emits pre-grant trigger behavior without adding a new opportunity (Task 3).

---

### Task 1: Conditional hand addition

**Files:** `scripts/card_catalog.gd`, `native/duel_core/src/duel_native_compile.cpp`, `native/duel_core/src/duel_native_compact_kernel.h`, `native/duel_core/src/duel_native_actions.cpp`, `tests/test_card_catalog.gd`, `tests/test_gumu_abilities.gd`.

**Interfaces:** `ACTION_ADD_CARD_TO_HAND` accepts optional `only_if_absent: bool` only with fixed `card_id`. Native `CompiledAction` carries that bool. Existing declarations omit it and retain prior behavior.

- [x] Add failing catalog validation cases for a non-Boolean guard and dynamic `card` specification; add simulator cases with a synthetic trigger for missing/present/full recipient hand, including a noncontiguous slot.
- [x] Run focused catalog and GuMu suites; verify new assertions fail for the intended reason.
- [x] Compile the optional flag and check recipient hand IDs before allocating a new card or instance ID.
- [x] Run focused suites; verify guard cases pass.

### Task 2: Locked hand-play source modifier

**Files:** `scripts/card_catalog.gd`, `native/duel_core/src/duel_native_compile.cpp`, `native/duel_core/src/duel_native_compact_kernel.h`, `native/duel_core/src/duel_native_compact_kernel.cpp`, `tests/test_gumu_abilities.gd`, `tests/test_duel_compact_state.gd`.

**Interfaces:** `MODIFIER_HAND_PLAY_AS_DISCARD` has no fields. `apply_play_action` checks only compiled active abilities on the played instance and ORs its result with `next_hand_play_from_discard_owner`. It must do so before `consume_next_hand_play_effects` and pass `-1` to `finish_action` for either source override.

- [x] Add failing tests with a synthetic retained modifier on a hand card for queue/history isolation and the existing opportunity marker; add a flip-retention assertion.
- [x] Run focused GuMu and compact-state suites; verify intended failures.
- [x] Compile the modifier and implement the one-instance check in the native hand-play entry; no persistent new scalar.
- [x] Rebuild native Debug and run the focused suites.

### Task 3: Catalog declarations and presentation

**Files:** `scripts/card_catalog.gd`, `tests/test_gumu_abilities.gd`, `tests/test_duel_integration.gd`, `tests/test_sect_catalog.gd`, `docs/ADDING_CARDS_AND_ABILITIES.md`, `docs/HANDOFF.md`.

**Interfaces:** Exact declarations and four `abilities` arrays are in the spec. Three tier-three cards use `GUMU_TIER_THREE_ADD_YUNV`; YuNv uses `GUMU_YUNV_DISCARD_SOURCE` and `GUMU_YUNV_ENTER`. No controller-specific gameplay branch.

- [x] Add failing simulator/event-order tests for three tier-three variants, YuNv's adjacent enemies, empty-neighbor grant, and capped grant attempt; replace old activation-only assertions with the new rules.
- [x] Run focused GuMu and integration suites; verify intentional failures.
- [x] Add the exact catalog declarations, remove unused old activation, update focused technical docs and stale GuMu sect difficulty test expectation.
- [x] Rebuild native Debug and run the focused suites; inspect ordered pure-data events for presentation.

### Task 4: Final verification and performance

**Files:** No production changes unless a failing check identifies a focused defect.

**Interfaces:** Canonical full suite is `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`. Native Release build is `tools/build_duel_native.ps1 -Configuration Release -GodotCppTarget template_debug`.

- [x] Run the full suite and inspect every failure; fix only defects in this scope.
- [x] Run the production flow muted at a 540×960 portrait viewport and inspect generation, entry feedback, and extra play.
- [x] Build Release and run fixed-fixture transition/search A/B against the retained source+binary, interleaving runs where practical; record configuration, timing, action/score/traversal agreement, and any repeatable regression immediately.
- [x] Review final diff, `git status --short`, and report code changes, verification evidence, and limitations.

## Execution evidence (2026-09-29)

- Canonical full suite: `ALL_TEST_SUITES_PASSED: 86 suite(s)`. The first run exposed a reward-scene fixture that replaced QuanZhen but not GuMu when temporarily inspecting a difficulty-zero score; the fixture now replaces every sect unavailable at difficulty zero.
- Muted offscreen production-scene walkthrough at the project's 540×960 logical viewport: tier-three entry left one generated YuNv in a fixed hand slot; YuNv entry produced the existing extra-play feedback and retained the player's action. Runtime errors: zero. The editor reported four pre-existing GDScript warnings in unrelated files.
- Retained pre-change source and its matching Release DLL: `.summer/local/perf-baselines/2026-09-29-gumu-yunv/` (source commit `4a37b8124e7235e12cf75181b09aebc744560da3`). Transition fixture agreed on 512 states, 1,024 action pairs, 3,072 applications, legal checks, and sink value 6. An interleaved Release pair measured old/new application time at 15.129/14.713 seconds.
- Fixed-node Release search used the same opening and 5,000 nodes per run. Two old/new elapsed-time pairs were 0.351/0.389 and 0.410/0.371 seconds; both chose the same action and score `-105082`. The direction reversed, so these samples do not establish a repeatable performance change.
