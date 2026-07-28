# Sect Selection Preview Card Backs Implementation Plan

**Design:** `docs/superpowers/specs/2026-07-28-sect-selection-preview-card-backs-design.md`

**Goal:** Fill every unused sect-selection preview-hand slot with the existing
decorative face-down card back while preserving real preview-card behavior.

## Task 1: Specify preview-hand placeholder behavior

**Files:**
- Modify: `tests/test_sect_selection_integration.gd`
- Inspect: `scripts/card_view.gd`
- Modify: `scripts/sect_selection_controller.gd`

1. Add integration checks for five face-down, non-inspectable cards in both
   preview hands before a sect is selected.
2. Select sects with different card counts and verify real previews replace
   placeholders from left to right.
3. Verify every unused slot retains one face-down placeholder.
4. Verify revealed preview cards still emit inspection requests.

## Task 2: Reuse the existing card-back presentation

**Files:**
- Modify: `scripts/sect_selection_controller.gd`
- Modify only if needed: `scripts/card_view.gd`

1. Add a focused helper for spawning a data-free face-down `CardView`.
2. During each preview-hand refresh, populate all five physical slots:
   - spawn a normal revealed preview card when a card ID exists;
   - otherwise spawn a decorative face-down placeholder.
3. Do not connect inspection, hold, or drag behavior for placeholders.
4. Keep placeholder ownership visual aligned with the hand: opponent backs
   above and player backs below.

## Task 3: Verify the focused change

**Files:**
- Verify all files above

1. Run script-error checks for changed GDScript files.
2. Run the sect-selection integration suite and the complete test suite.
3. Run `git diff --check` and confirm no unrelated changes are included.
4. Boot the main scene at portrait proportions.
5. Visually verify ten initial card backs, then select a sect and confirm real
   previews replace backs while unused slots remain filled.
6. Review runtime diagnostics and commit the focused change.
