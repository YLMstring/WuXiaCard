# Native Resolution Stack Implementation Plan

**Goal:** Replace recursively nested native gameplay resolution with one explicit
LIFO engine, add deterministic resolution-loop termination, and preserve every
non-loop state and presentation event exactly.

## Task 1: Add terminal-reason data and exact result presentation

- Add a compact terminal-reason scalar shared by `DuelState`,
  `DuelCompactState`, and `DuelNativeCompactKernel`.
- Derive and lock `ACTION_LIMIT` and `FIVEFOLD_REPETITION` at their existing
  turn-boundary terminal checks; reserve `RESOLUTION_LOOP` for the new engine.
- Keep full-board and neither-side-can-act as normal terminal values with no
  displayed reason.
- Format victory and defeat results using the approved prefixes while
  preserving player-first scores, the existing tie-as-defeat rule, and replayed
  final text.
- Add compact round-trip, native terminal, controller, and replay regressions.

## Task 2: Introduce the explicit engine and test-only dual path

- Add private native frame types, a `ResolutionEngine`, a compact result
  accumulator, and a deterministic run loop in dedicated internal source files.
- Add a test-only iterative transition entry that accepts the same native state
  and action as production without changing live routing.
- Let the first engine version use an explicit root continuation while delegating
  unconverted leaf work to the current resolver.
- Add a differential harness comparing full compact payload, ordered events,
  captures, exiles, and legal actions for old versus new transitions.
- Build the native library and run focused production-rules tests.

## Task 3: Migrate event and action sequencing

- Convert event discovery/revalidation into `EVENT` frames using stable ability
  handles and trigger indices.
- Convert ordered action lists, `ACTION_IF`, and
  `ACTION_FOR_EACH_SELECTED_CARD` into resumable sequence frames.
- Preserve selector snapshot versus live reread behavior per existing opcode.
- Convert direct ki/power mutations so consequential events or zero-power exile
  are pushed as child frames rather than called recursively.
- Differential-test every catalog event/opcode represented in the 512-state
  migration corpus before continuing.

## Task 4: Migrate flip and exile lifecycles

- Convert before-flip, prevention, ownership change, ability cleanup,
  after-flip, and delayed self-after-flip cleanup into one resumable frame.
- Convert before-exile validation, zone mutation, hand-size consequences,
  after-exile, and exact-context cancellation into one resumable frame.
- Replace the recursive exile guard with engine-owned in-flight frame state.
- Add focused regressions for JinGang prevention, QianShou copies, YuSui
  cancellation/re-entry, four-zero exile, and cards exiled during their own
  trigger.

## Task 5: Migrate draw, discard, hand addition, movement, and swap

- Convert draw and effect-driven hand addition continuations, including empty
  deck fallback, reveal ordering, and difficulty hand-size reactions.
- Convert generic batch discard while preserving lock-all, move-all,
  per-instance trigger order, one batch-finished event, and one visual shift.
- Convert single movement and both swap legs with before/after event
  revalidation and rollback rules.
- Differential-test Shaolin discard families, SanRu pile rereads, YanHui hand
  returns, TaiShan swaps, and FuMo movement reactions.

## Task 6: Migrate summon and attack lifecycles

- Convert summon before/summoned/after-summoned windows, global discovery,
  flip-history cancellation, redirect snapshots, and standard-attack handoff.
- Convert target snapshotting, initial comparison, be-attacked reactions,
  prevention/flip results, attacker-flipped early stop, target continuation,
  and after-attack events.
- Preserve the per-owner attack cap without using it as a recursion guard.
- Differential-test all summon counterattacks, long-range locked targeting,
  friendly-fire redirection, multiple targets, resummons, and extra attacks.

## Task 7: Migrate action roots and turn boundaries

- Convert play and activation roots, activation cost/action continuation, last
  hand-play memory, and accumulated extra-play requests.
- Convert end-turn, before-full-board-end, empty-turn start/end traversal,
  boundary restoration, repetition recording, and next-owner selection.
- Ensure reaching the action cap does not interrupt the current turn or an
  already granted extra play.
- Confirm all public adapters and AI transitions can finish without entering any
  recursive gameplay resolver.

## Task 8: Add canonical loop fingerprints and loop terminal

- Build the loop key from the complete pending-frame/continuation fingerprint,
  authoritative `turn_count`, and board cells in `0..8` order containing only
  catalog ID plus owner. Deliberately exclude powers, ki, off-board zones,
  ability state, and `owner_turn_serial` from the state portion of the key.
- Canonicalize instance references inside frame payloads while preserving
  same-instance relationships; exclude raw instance ID values and
  presentation-only data.
- Count non-consecutive appearances of each loop key within one root
  resolution. Continue through appearance nineteen; on appearance twenty,
  preserve the current state, clear pending frames, lock `RESOLUTION_LOOP`, and
  score immediately without turn-boundary or before-duel-end triggers.
- Separately detect a causal frame block nested twenty times while the board
  ID/owner structure and `turn_count` at each frame creation remain equal. This
  catches recursive stack growth that can never return to the same full-stack
  fingerprint; keep the ordinary full-stack detector for fixed-depth cycles.
- Add positive numeric-growth and fresh-instance loops; verify state changes
  deliberately omitted from the key still accumulate; add different-frame and
  different-`turn_count` negative tests.
- Add a separate high emergency step ceiling that reports an internal error and
  is never presented as a gameplay loop.

## Task 9: Switch production and retire recursion

- Run full old/new differential coverage across the deterministic 512-state
  corpus and multi-action seeded duels.
- Switch player, testing mode, greedy fallback, and AI to the iterative engine in
  one production change.
- Run fixed-depth AI action/score parity and performance comparisons.
- Delete the recursive gameplay resolver and test-only routing after parity is
  sealed; keep one authoritative implementation.
- Update architecture, handoff, testing, known-issues, and native README docs.

## Task 10: Final verification and Android validation

- Build Windows debug-ABI and Release native libraries.
- Run the complete canonical suite.
- Run the former crash combination and a thousands-step native-stack stress
  test.
- Export Android Release, then perform a muted multi-duel device test while
  watching native crashes, memory, and frame time.
- Confirm replay preserves each approved terminal result string and that normal
  terminal results remain unchanged.
