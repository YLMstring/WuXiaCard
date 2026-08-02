# Main-Menu Center Duel Implementation Plan

**Spec:** `docs/superpowers/specs/2026-08-02-main-menu-center-duel-design.md`

1. Generate a separate candidate from the current production background.
2. Validate that exactly two active fencers occupy only the center slab and
   that twelve to sixteen varied spectators occupy all eight surrounding slabs.
3. Inspect at full resolution and production phone scale. Reject any candidate
   with seam crossings, an obscured duel, repeated-looking spectators, lost
   title space, or unacceptable environmental drift.
4. After visual approval, replace `pics/main_menu_background_phone.png` with
   the selected candidate and allow Godot to reimport it.
5. Run the main menu, capture portrait and wide presentation, inspect runtime
   diagnostics, and commit the verified asset locally.
