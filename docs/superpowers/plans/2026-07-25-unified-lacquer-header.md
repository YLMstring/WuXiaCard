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
- Modify: `scripts/duel_controller.gd`
- Modify: `scenes/duel.tscn`

**Steps:**

1. Add a typed static helper that calculates the upper line, seam line, and ornament Y coordinates from the extension rectangle.
2. Use that helper in `_draw_lacquer_extension()`.
3. Draw the lower gold line half a pixel inside the seam.
4. Draw every ornament at the calculated midpoint between the gold lines.
5. Make `_style_duel_header()` use `DuelBackdrop.LACQUER_COLOR` as the runtime source of truth.
6. Change the scene's initial `TopWash.color` to `#452824` so editor previews also match.

## Task 3: Share the visible lacquer tint

**Files:**

- Modify: `tests/test_duel_backdrop.gd`
- Modify: `tests/test_duel_integration.gd`
- Modify: `scripts/duel_backdrop.gd`
- Modify: `scripts/duel_controller.gd`

**Steps:**

1. Add failing assertions for a shared lacquer-tint texture factory:
   - Gradient offsets are `0.0`, `0.52`, and `1.0`.
   - Both edge colors are transparent.
   - The center color is `Color(0.42, 0.25, 0.22, 0.66)`.
   - The requested texture width is retained.
2. Add an integration assertion that `TopWash/CenterTint` uses the shared gradient definition.
3. Implement the typed texture factory in `DuelBackdrop`.
4. Draw that texture across the lacquer extension before drawing the gold rules and ornaments.
5. Use the same factory for `TopWash/CenterTint` in `_style_duel_header()`.

## Task 4: Verify the result

**Steps:**

1. Check `scripts/duel_backdrop.gd` for parse and compile errors.
2. Run the full seven-suite test runner.
3. Run the game and inspect a tall runtime frame:
   - No visible tint discontinuity between extension and header at the left, center, or right.
   - Lower gold line remains visible at the seam.
   - Ornament row is centered between both gold lines.
4. Check runtime diagnostics for new errors.
5. Audit the diff and commit only the implementation files.

## Task 5: Match the tint rendering and replace the return chrome

**Files:**

- Add: `pics/back_arrow.svg`
- Modify: `scenes/duel.tscn`
- Modify: `scripts/duel_controller.gd`
- Modify: `tests/test_duel_integration.gd`

**Steps:**

1. Add failing integration assertions that:
   - `TopWash/CenterTint` uses `TextureRect.STRETCH_SCALE`.
   - The return control has empty text, a local icon, tooltip “返回,” and at least a 44×44 interaction area.
   - Its normal, hover, pressed, and focus styleboxes are visually empty.
   - Its existing pressed signal remains connected.
2. Add a 24×24 white SVG back arrow that can be tinted by the button theme.
3. Set `CenterTint` to full scaling so its gradient matches the procedural decoration across the width.
4. Make `ExitButton` a 44×44 icon-only control with no visible stylebox chrome.
5. Preserve the existing gold normal/hover/pressed/focus color progression on the icon.
6. Run the full suite and inspect tall and wide runtime frames.
