# Unified Lacquer Header Implementation Plan

**Goal:** Make the tall decorative extension and duel header one continuous warm lacquer treatment, with the lower gold line on the seam and the ornament row centered between both lines.

**Design reference:** `docs/superpowers/specs/2026-07-25-unified-lacquer-header-design.md`

## Task 1: Lock the approved geometry and color with tests

**Files:**

- Modify: `tests/test_duel_backdrop.gd`
- Modify: `tests/test_duel_integration.gd`

**Steps:**

1. Add backdrop assertions for a pure lacquer-layout helper:
   - Upper line retains the existing inset.
   - Lower line resolves to `rect.end.y - 0.5`.
   - Ornament Y is the midpoint of the two lines.
2. Add an integration assertion that `DuelCanvas/TopWash.color` equals `DuelBackdrop.LACQUER_COLOR`.
3. Run the backdrop and integration suites and confirm that the new assertions fail for the intended reasons.

## Task 2: Implement the unified treatment

**Files:**

- Modify: `scripts/duel_backdrop.gd`
- Modify: `scenes/duel.tscn`

**Steps:**

1. Add a typed static helper that calculates the upper line, seam line, and ornament Y coordinates from the extension rectangle.
2. Use that helper in `_draw_lacquer_extension()`.
3. Draw the lower gold line half a pixel inside the seam.
4. Draw every ornament at the calculated midpoint between the gold lines.
5. Change `TopWash.color` to the exact lacquer color `#452824`.

## Task 3: Verify the result

**Steps:**

1. Check `scripts/duel_backdrop.gd` for parse and compile errors.
2. Run the full seven-suite test runner.
3. Run the game and inspect a tall runtime frame:
   - No color discontinuity between extension and header.
   - Lower gold line remains visible at the seam.
   - Ornament row is centered between both gold lines.
4. Check runtime diagnostics for new errors.
5. Audit the diff and commit only the implementation files.
