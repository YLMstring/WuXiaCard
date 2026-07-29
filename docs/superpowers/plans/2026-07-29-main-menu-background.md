# Main Menu Background Implementation Plan

**Design:** `docs/superpowers/specs/2026-07-29-main-menu-background-design.md`

1. Generate one high-resolution square, crop-safe ink-wash master with no text
   or UI.
2. Inspect the full master and representative portrait, tall-phone, landscape,
   and ultrawide center crops.
3. If the required arena, duelists, and negative-space zones survive, copy the
   master to `pics/main_menu_background.png`.
4. Confirm the PNG imports cleanly and commit only the plan and selected asset.
