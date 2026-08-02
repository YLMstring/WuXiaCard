# Duel Replay Implementation Plan

Date: 2026-08-02
Design: `docs/superpowers/specs/2026-08-02-duel-replay-design.md`

## Objective

Add a repeatable, in-memory replay to the duel scene. Record the exact initial
simulation state and every successful real action, rebuild the duel from that
snapshot after completion, and replay the actions through `DuelSimulator` with
normal VFX and a configurable two-second inter-turn delay. Preserve normal
opponent concealment, allow inspection between actions, and suppress all real
duel side effects during playback.

## Constraints

- `DuelSimulator` remains the only gameplay rules path.
- Replay data is pure and contains no scene nodes.
- Replay is not persisted and does not affect profiles, mastery, enemy memory,
  rewards, progression, or AI.
- Existing fixed hand slots, runtime `instance_id` mappings, and normal/testing
  concealment rules remain authoritative.
- The user-supplied `res://inkpics/replay.png` is used directly.
- Production replay delay is 2.0 seconds; tests use zero or controlled time.
- Preserve the user's uncommitted replay image and import metadata.

## Task 1: Establish a clean baseline

**Files:** none

1. Run `git status --short` and confirm that only the user's replay image and
   import metadata are uncommitted.
2. Run `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`.
3. Record the 28-suite baseline before changing behavior.

## Task 2: Add a pure replay record

**Files:**

- Create `scripts/duel_replay_record.gd`
- Create `tests/test_duel_replay_record.gd`
- Modify `tools/run_tests.ps1`

1. Write failing tests for a replay record that:
   - duplicates the initialized `DuelState` rather than retaining a mutable
     reference;
   - stores immutable `DuelAction.duplicate_action()` entries in order;
   - ignores no action implicitly—the controller decides which successful
     actions reach it;
   - stores a duplicate final state, outcome, and final status;
   - exposes fresh duplicates to playback so one replay cannot mutate the next;
   - reports readiness only after initial state, at least one action, final
     state, and a victory/defeat outcome exist.
2. Run the new test and confirm that it fails because the record is absent.
3. Implement `DuelReplayRecord` as a `RefCounted` pure-data boundary with
   `begin()`, `record_action()`, `complete()`, `is_ready()`, and duplicate
   accessors.
4. Add the suite to the canonical runner.
5. Run the focused test to green.

## Task 3: Record real duel actions without side effects

**Files:**

- Modify `scripts/duel_controller.gd`
- Create `tests/test_duel_replay.gd`
- Modify `tools/run_tests.ps1`

1. Add failing controller tests that verify:
   - the initial snapshot matches the exact initialized state, including hand
     and shuffled side-deck order;
   - illegal moves do not enter the log;
   - successful player plays, opponent plays, and activations enter the log in
     resolution order as independent action copies;
   - the replay record becomes ready only when `_finish_match()` captures the
     final snapshot and outcome;
   - replay-button requests before completion are state-preserving no-ops.
2. Add controller-owned replay state:
   - one `DuelReplayRecord`;
   - `_is_replaying` and `_is_replay_presenting_action` guards;
   - a replay generation/cancellation token;
   - exported `replay_turn_delay = 2.0`.
3. Begin the record immediately after the authoritative initial `DuelState` is
   finalized.
4. In `_commit_action()`, append a duplicate only after
   `Simulator.apply_action()` returns a valid transition and only when not
   replaying.
5. Gate mastery recording and `opponent_card_played` emission behind
   `not _is_replaying`.
6. Complete the record in `_finish_match()` only for the real duel. Do not
   overwrite the recorded final snapshot when replay reaches terminal state.
7. Add read-only debug accessors needed by tests; do not expose mutable replay
   internals.
8. Run the focused controller replay test to green.

## Task 4: Rebuild presentation from an arbitrary authoritative state

**Files:**

- Modify `scripts/duel_controller.gd`
- Extend `tests/test_duel_replay.gd`

1. Add failing tests for rebuilding the initial state after a completed duel:
   - all board views are removed;
   - both five-slot hands remain intact;
   - hand and board card views match logical `instance_id`, owner, powers, ki,
     and active abilities;
   - scores reset from the rebuilt board;
   - opponent hand cards are face-down in normal mode and revealed in testing
     mode;
   - no stale drag context, highlights, or temporary card views remain.
2. Extract focused helpers that clear card views without deleting the fixed
   hand slots or board cells.
3. Add `_rebuild_views_from_state(state)` to duplicate the supplied state,
   rebuild hand cards into fixed physical slots, rebuild board cards into their
   exact cells, restore runtime data/ownership, clear transient input state,
   update scores, and reapply concealment.
4. Use existing `CardView.configure()`, signal wiring, and runtime sync paths;
   do not create a replay-only card presentation type.
5. Run the focused test and the existing duel integration suite.

## Task 5: Replay logged actions through the simulator

**Files:**

- Modify `scripts/duel_controller.gd`
- Extend `tests/test_duel_replay.gd`

1. Add failing tests that complete a deterministic scripted duel, start replay
   with zero delay, and verify:
   - opening state is rebuilt before the first action;
   - every recorded action is applied exactly once in order;
   - normal transition presentation traces are produced again;
   - final logical state, board ownership, score, outcome, and status match the
     original completion;
   - mastery candidates and opponent-memory signal counts do not change;
   - no AI search starts;
   - a replay press while replaying cannot create a second playback loop;
   - replay can be started a second time after completion.
2. Add `_start_replay()` and an awaited replay loop:
   - validate record readiness and current lifecycle;
   - cancel any search;
   - increment/capture the cancellation generation;
   - enter replay state and rebuild from a fresh initial duplicate;
   - locate each source card view by exact `source_instance_id`;
   - call the shared simulator/presentation commit path with automatic turns,
     logging, mastery, and memory disabled;
   - wait between fully resolved actions except after the final action;
   - finish on the recorded result and re-enable replay.
3. Update `_sync_hand_playability()` and `_can_manually_drag()` so no real card
   play/activation is possible while `_is_replaying`.
4. Ensure terminal replay resolution does not replace the real replay record or
   emit navigation.
5. Run replay, duel outcome, mastery, enemy-memory, and duel integration suites.

## Task 6: Pause inter-turn timing for inspection

**Files:**

- Modify `scripts/duel_controller.gd`
- Extend `tests/test_duel_replay.gd`

1. Add failing tests that verify:
   - revealed cards can open the inspector during a settled replay gap;
   - concealed opponent cards cannot open it;
   - inspection is rejected during action presentation;
   - the delay countdown does not advance while inspection is open;
   - closing inspection resumes the remaining delay rather than restarting or
     skipping it.
2. Permit `_on_card_inspection_requested()` during replay only when
   `_is_replay_presenting_action` is false.
3. Implement the inter-turn delay as a frame-driven remaining-time loop. Only
   decrement while the inspector is closed and the replay generation is still
   current.
4. Preserve the existing inspector layout/status restoration behavior.
5. Run card-inspector and focused replay suites.

## Task 7: Add the replay icon and touch feedback

**Files:**

- Modify `scenes/duel.tscn`
- Modify `scripts/duel_controller.gd`
- Extend `tests/test_duel_replay.gd`
- Extend `tests/test_duel_integration.gd`
- Add the user-owned `inkpics/replay.png` and `inkpics/replay.png.import` to the
  implementation commit

1. Add failing UI assertions for:
   - an icon-only flat `ReplayButton` under `DuelCanvas`;
   - the exact supplied replay texture;
   - an approximately 44×44 touch target;
   - placement left of the board and vertical center alignment at portrait,
     tall, and wide aspect ratios;
   - no overlap with the board or hands.
2. Add the flat button using the supplied texture. Preserve aspect ratio and
   make the visible mark fit comfortably inside the hit area.
3. Position it from `_layout_duel()` using the calculated board rectangle, not
   hard-coded screen coordinates.
4. Connect `pressed` to replay startup. Leave the button input-enabled so touch
   feedback works in every lifecycle state; the handler performs the no-op
   gating.
5. Connect `button_down`/`button_up` and implement short reusable feedback:
   - set the pivot to the center;
   - scale down slightly and reduce opacity on touch-down;
   - restore with a brief eased/spring-like tween on release;
   - kill/restart the prior feedback tween so repeated touches do not leave a
     stale transform.
6. Run focused replay, backdrop/layout, and duel integration suites.

## Task 8: Recovery and exit lifecycle

**Files:**

- Modify `scripts/duel_controller.gd`
- Extend `tests/test_duel_replay.gd`
- Extend `tests/test_duel_outcome.gd`

1. Add failing tests for:
   - an invalid recorded action restoring the immutable final snapshot and
     original status without emitting memory/mastery side effects;
   - exit during replay cancelling future delayed work and emitting the real
     victory/defeat;
   - scene exit invalidating replay work before nodes are freed.
2. Add one recovery helper that rebuilds from a fresh final-state duplicate,
   restores outcome/status/complete lifecycle, clears replay flags, and warns.
3. Increment the replay generation in `_on_exit_pressed()` and `_exit_tree()`.
4. Keep `_return_emitted` as the single navigation emission guard.
5. Run replay and outcome suites.

## Task 9: Documentation and complete verification

**Files:**

- Modify `docs/ARCHITECTURE.md`
- Modify `docs/DECISIONS.md`
- Modify `docs/HANDOFF.md`
- Modify `docs/TESTING.md`

1. Document the in-memory initial-state/action-log/final-state replay contract,
   simulator reuse, concealment, inspection pause, side-effect suppression,
   and future randomness requirement.
2. Run `git diff --check`.
3. Run all replay-focused and neighboring suites.
4. Run the canonical full test command and require every suite to pass with no
   `ERROR:`, `SCRIPT ERROR`, `_FAILED`, or `CHECK_FAILED` output.
5. Use Summer Engine at a portrait viewport to:
   - complete a duel;
   - confirm the supplied icon's placement and touch feedback;
   - replay with the production two-second cadence;
   - inspect a revealed card during a gap and confirm timing pauses;
   - confirm the opponent hand remains concealed;
   - run replay twice;
   - exit during replay and confirm correct post-duel routing.
6. Read fresh runtime diagnostics, console, and debugger output.
7. Commit the verified implementation without pushing.
