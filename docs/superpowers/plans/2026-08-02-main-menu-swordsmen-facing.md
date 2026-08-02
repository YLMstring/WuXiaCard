# Main-Menu Swordsmen Facing Correction Plan

**Spec:** `docs/superpowers/specs/2026-08-02-main-menu-swordsmen-facing-design.md`

1. Preserve the current `pics/main_menu_background_phone.png` as the visual
   reference and generate a separate edited candidate.
2. Repose only the two swordsmen: lower-left toward upper-right, upper-right
   toward lower-left. Preserve every environmental and compositional detail.
3. Inspect the candidate at original resolution and at the production portrait
   crop. Reject it if slabs, scenery, scale, positions, palette, or dimensions
   drift.
4. Replace the production image with the approved candidate and allow Godot to
   reimport it.
5. Run the main menu, capture the rendered result, check diagnostics, and commit
   the asset change locally.
