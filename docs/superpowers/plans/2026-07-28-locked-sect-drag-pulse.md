# Locked Sect Drag Pulse Implementation Plan

**Design:** `docs/superpowers/specs/2026-07-28-locked-sect-drag-pulse-design.md`

**Goal:** Play one restrained card-area pulse when a locked sect reaches the
hold threshold, without changing selection, inspection, scrolling, or drag
rules.

## Task 1: Specify reusable slot feedback

**Files:**
- Modify: `tests/test_deck_library_grid.gd`
- Modify: `scripts/deck_library_slot.gd`
- Modify: `scripts/deck_library_grid.gd`

1. Add failing checks for a focused grid operation that pulses a currently
   bound logical slot and safely ignores an off-screen slot.
2. Add a `DeckLibrarySlot` rejected-drag pulse counter/debug observation so
   tests can distinguish the feedback from the existing drag-arm lift.
3. Implement a tracked `CardHost` tween:
   - scale from 1.0 to 1.035 and back;
   - total duration 0.18 seconds;
   - restart cleanly when requested again;
   - no color, sound, or label change.
4. Kill the active tween and restore unit scale on rebind and tree exit.
5. Expose the focused logical-index operation through `DeckLibraryGrid` without
   exposing pooled-slot internals to the controller.

## Task 2: Trigger only for locked sect holds

**Files:**
- Modify: `scripts/sect_selection_controller.gd`
- Modify: `tests/test_sect_selection_integration.gd`

1. In the existing locked branch of `hold_recognized`, request the grid pulse
   for that logical index after updating previews and status.
2. Keep unlocked holds on their existing lift/drag path.
3. Verify:
   - locked tap produces no pulse;
   - one locked hold produces one pulse;
   - a second attempt restarts and produces one additional pulse;
   - unlocked hold produces no rejected-drag pulse;
   - locked entries remain non-draggable and emit no deck-builder request.
4. Preserve the current user-authored default status text.

## Task 3: Verify and playtest

**Files:**
- Verify all files above

1. Run script-error checks for every changed GDScript.
2. Run the grid and sect-selection suites, then the complete thirteen-suite
   runner.
3. Run `git diff --check` and verify no unrelated edits are included.
4. Start the main scene, inspect the sect-selection render, and review fresh
   diagnostics.
5. Exercise the locked-hold pulse at portrait scale and confirm that it is
   visible but restrained, while tap, scroll, unlocked drag, and inspection
   remain unchanged.
