# Card Ability Pulses Implementation Plan

**Design:** `docs/superpowers/specs/2026-07-26-card-ability-pulses-design.md`

**Goal:** Present one short whole-card pulse before each successfully accepted
passive ability rule, suppress consecutive pulses from the same card within one
move, and remove the older ability-specific whole-card pulses.

**Architecture:** `DuelTriggers` prepends a presentation-only
`ability_triggered` event to every revalidated passive trigger group.
`DuelController` consumes those events in order, awaits the existing card pulse,
and keeps the last pulsed instance ID local to one transition presentation.

## Task 1: Lock trigger-event semantics with simulator tests

**Files:**
- Modify: `tests/test_duel_simulator.gd`

1. Assert that an accepted passive rule emits `ability_triggered` before its
   action events with source cell, instance ID, and owner.
2. Assert that stale groups and groups whose conditions fail at resolution emit
   no event.
3. Add a passive rule whose action returns `NO_EFFECT` and assert that its trigger
   event remains.
4. Assert that `execute_activation()` and activation transitions never emit
   `ability_triggered`.
5. Update existing exact event sequences/counts to include the new presentation
   event without changing gameplay assertions.
6. Run the simulator suite and confirm the new expectations fail before
   implementation.

## Task 2: Emit the canonical passive-trigger event

**Files:**
- Modify: `scripts/duel_triggers.gd`

1. Keep current group revalidation and condition checks unchanged.
2. Execute the accepted rule through `DuelAbilityExecutor`.
3. Prepend one `ability_triggered` event containing `source_cell`,
   `source_instance_id`, and `source_owner_id`.
4. Preserve action events, attack requests, extra-turn requests, result status,
   and source-cell updates.
5. Do not change `execute_activation()` or emit the event during activation.
6. Run simulator and search suites.

## Task 3: Add ordered generic pulse presentation

**Files:**
- Modify: `scripts/duel_controller.gd`
- Modify: `tests/test_duel_integration.gd`

1. Add an exported passive ability pulse duration and set it to zero in fast
   mode.
2. In `_present_transition_events()`, create a local empty
   `last_pulsed_instance_id`.
3. On `ability_triggered`, resolve the current board view by instance ID.
4. If the view exists and differs from the last actually pulsed instance, append
   it to a debug-observable pulse trace, await `play_effect_pulse()`, and remember
   it.
5. Do not change the remembered ID for skipped or missing views.
6. Remove the `card_exiled` source-pulse branch and its old
   `exile_pulse_duration` setting while retaining exile feedback.
7. Test `A -> A`, `A -> B -> A`, a missing source, and a new transition beginning
   again with A.
8. Test production draw, CangSong, Gate/Tiger, and Meng Huo event order.

## Task 4: Remove Meng Huo's extra-turn source-card pulse

**Files:**
- Modify: `scripts/extra_turn_vfx.gd`
- Modify: `tests/test_duel_integration.gd`

1. Remove the source-control scale tween and its pulse-scale constant from
   `play_convergence()`.
2. Keep source geometry, bead convergence, board-outline pulse, cleanup,
   serialization, and existing debug counters.
3. Rename local parameters only where doing so clarifies that the remaining
   duration controls the board pulse.
4. Update integration assertions to confirm beads and one board pulse remain.
5. Confirm Meng Huo receives its generic pulse before ki spending while no
   second whole-card pulse occurs during convergence.

## Task 5: Document, verify, and commit

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/DECISIONS.md`
- Modify: `docs/TESTING.md` if check counts change

1. Document `ability_triggered` as a presentation-only passive-trigger event and
   record the per-move suppression rule.
2. Run script-error checks for every changed GDScript.
3. Run `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`.
4. Start the duel through Summer Engine and manually exercise CangSong, draw,
   Gate/Tiger, Meng Huo, and one activate ability at normal speed.
5. Inspect runtime debugger, console, and diagnostics.
6. Run `git diff --check` and confirm the user's existing
   `scripts/game_settings.gd` edit is unchanged and unstaged.
7. Commit only the implementation and documentation files.
