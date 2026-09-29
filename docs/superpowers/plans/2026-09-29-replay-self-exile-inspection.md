# Replay Self-Exile Inspection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pause both replay modes to inspect an enemy-played card that exiles itself during that play, then resume the original event presentation.

**Architecture:** Keep the simulator and replay records unchanged. In `DuelController._commit_action`, inspect the returned event array for self-exile of the exact played instance; during replay only, open the existing inspector using the revealed `CardView` snapshot and await its close before presenting events.

**Tech Stack:** Godot 4.7 GDScript, existing native simulator, SceneTree integration tests.

**Spec:** `docs/superpowers/specs/2026-09-29-replay-self-exile-inspection-design.md`

## Global Constraints

- Both full-match and opponent-turn replay must pause; normal play must not.
- Match `TYPE_PLAY`, opponent ownership, `card_exiled`, `self_removal`, and played `instance_id`; never infer from card name.
- Do not expose face-down hand data or change `DuelState`, `DuelAction`, simulator events, or replay persistence.
- Fast test presentation bypasses the modal; the focused test uses normal presentation with short animation timings.
- Full suite: `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`; visible playtest muted at 540×960.

## Review Focus

- Another card is exiled by the play: the played card must not open the inspector.
- A player card self-exiles: no automatic inspector.
- An enemy activation self-exiles: no automatic inspector.
- A replay is cancelled while the inspector is open: no stale continuation or overlay.
- Repeated plays of the same card name: one inspection per qualifying instance and action.

---

### Task 1: Replay-only presentation pause

**Files:**
- Modify: `scripts/duel_controller.gd` near `_commit_action` and the inspector handlers.
- Create: `tests/test_replay_self_exile_inspection.gd`.
- Modify: `tools/run_tests.ps1` to include the focused test.

**Interfaces:**
- Consumes: `ActionData.TYPE_PLAY`, `DuelRules.OPPONENT_OWNER`, `transition["events"]`, `CardView.card_data`, existing inspector close signal and replay flags.
- Produces: `_should_inspect_replayed_self_exile(action: ActionData, owner_id: int, events: Array) -> bool` and `_present_replay_self_exile_inspection(card: CardView) -> bool`, where false means replay was cancelled or the controller left the tree.

- [x] **Step 1: Add failing integration coverage.** Build a small `YuNvWuFeng` fixture and exercise live opponent play, full replay, and opponent-turn replay. Assert that each replay pauses once before `card_exiled`, shows the played card's name/description, and continues after `debug_close_inspection()`. Cover the five Review Focus cases with fixture variants or direct predicate checks.
- [x] **Step 2: Run the focused test and confirm the replay assertions fail.** Use the resolved Summer executable with `--headless --audio-driver Dummy --path C:/mygame --script res://tests/test_replay_self_exile_inspection.gd`.
- [x] **Step 3: Implement the predicate and the replay-only inspector pause.** Evaluate the predicate after `Simulator.apply_action` succeeds; reveal and place the card normally, then pause before `_present_transition_events`. Reuse the existing inspector presentation and close handler while preserving the normal tap guard. Check replay generation and tree validity after waiting; ensure cancel/recovery closes any replay-owned inspector.
- [x] **Step 4: Run the focused test and confirm it passes.** The replay must remain on the same action while the modal is open and resume the native event order on close.
- [x] **Step 5: Run the complete suite and muted portrait playtest.** Confirm 86 existing suites plus the new focused suite pass, then exercise both replay entries in the production scene; inspect logs.
- [x] **Step 6: Commit the focused code and test changes locally.** Do not push or alter remote state.

Verification: the focused test failed on the missing replay modal before implementation, then passed all 34 headless checks. The final full suite passed 87 suites. A muted 540×960 rendered run passed 35 checks and its inspector screenshot showed complete card text and close affordance. A separate telemetry test produced an intermittent engine-exit resource warning on one full-suite run and one of three isolated reruns; its assertions passed, and the final full-suite run was clean.
