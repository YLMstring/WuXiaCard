# Meng Huo Extra-Turn VFX Implementation Plan

**Goal:** Add the approved Ki Convergence presentation to the canonical `extra_turn_granted` event without changing duel rules.

**Architecture:** A reusable full-screen `Control` draws and animates temporary ki beads plus a board-outline pulse. `DuelController` converts event source instance IDs into local rectangles and awaits this overlay from the existing ordered event presenter.

## Task 1: Add focused failing integration coverage

**Files:**
- Modify: `tests/test_duel_integration.gd`

1. Extend the existing Meng Huo presentation fixture to assert that the duel scene contains an input-transparent extra-turn overlay.
2. Add debug-observable presentation counters for source beads and board pulses.
3. Verify one Meng Huo produces one bead and one board pulse.
4. Verify duplicate source IDs deduplicate to one bead.
5. Verify two valid source IDs produce two beads but one pulse.
6. Verify missing source views still produce one pulse.
7. Run the integration suite and confirm the new assertions fail before implementation.

## Task 2: Implement the reusable procedural overlay

**Files:**
- Create: `scripts/extra_turn_vfx.gd`
- Modify: `scenes/duel.tscn`

1. Add an `ExtraTurnVfx` full-rect `Control` above gameplay UI with `mouse_filter = IGNORE`.
2. Store source rectangles, board rectangle, animation progress, and debug counters.
3. Draw each temporary bead procedurally in gold, beginning near the source's upper-right corner and converging on its center.
4. Draw one expanding/fading rounded board outline after convergence.
5. Pulse source controls once at bead arrival, restoring their scale even at zero duration.
6. Deduplicate invalid/duplicate source rectangles, clean all temporary state after each call, and serialize repeated calls.
7. Expose read-only debug accessors used by integration tests.

## Task 3: Connect canonical extra-turn events

**Files:**
- Modify: `scripts/duel_controller.gd`

1. Add typed access to the overlay and exported convergence/pulse timing and color tunables.
2. Set new durations to zero in `debug_set_fast_mode(true)`.
3. Resolve `source_instance_ids` from `extra_turn_granted` into valid board-card views without checking card names.
4. Pass source controls and the current board rectangle to the overlay.
5. Await the overlay before restoring the turn-status color.
6. Preserve the existing presentation trace and rules flow.

## Task 4: Verify behavior and regressions

**Files:**
- Modify if needed: `tests/test_duel_integration.gd`

1. Run script-error checks on every changed GDScript.
2. Run card-catalog, simulator, search, and integration suites.
3. Start the game through Summer Engine with a clean console.
4. Trigger Meng Huo's extra turn in a controlled playtest and capture the convergence and board-pulse phases.
5. Trigger a chained extra turn to verify repeated playback and cleanup.
6. Inspect console, debugger errors, and final diagnostics.
7. Review `git diff --check`, stage only intended files, and commit the implementation.
