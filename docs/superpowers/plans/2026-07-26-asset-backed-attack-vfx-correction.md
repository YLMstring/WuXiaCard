# Asset-Backed Attack VFX Correction Plan

**Design:** `docs/superpowers/specs/2026-07-26-flying-white-attack-vfx-design.md`

**Goal:** Replace the procedural attack connector with the supplied
`res://inkpics/attack.png`, reveal it from the attacker side at the approved
64 × 22 size, and keep it on the first board-cell seam beside the attacker even
when a future target is farther away.

**Architecture:** Keep the existing simulator `attack_started` event and ordered
presentation timing unchanged. Replace only the `AttackVfx` renderer and the
controller's presentation geometry. `AttackVfx` owns one reusable clipped
`TextureRect`; `DuelController` converts source/target cell indices into an
orthogonal first-neighbor seam center and rotation.

## Task 1: Establish the correction baseline and failing presentation tests

**Files:**
- Modify: `tests/test_duel_integration.gd`
- Verify unchanged: `tests/test_duel_simulator.gd`
- Verify unchanged: `tests/test_duel_search.gd`

1. Run all seven suites and record the fresh pre-change baseline.
2. Preserve the simulator assertions for `attack_started` timing, payload,
   invalid-attack suppression, interception, and multi-target order.
3. Replace procedural endpoint, diagonal, and three-fleck integration
   expectations with asset-backed expectations.
4. Assert the overlay uses `res://inkpics/attack.png` and a 64 × 22
   logical-pixel display box while preserving the texture's aspect ratio.
5. Assert local reveal grows from x = 0 toward the local right before any
   parent rotation is applied.
6. Assert the four approved rotations: right `0`, left `PI`, down `PI / 2`,
   and up `-PI / 2`.
7. Assert adjacent horizontal/vertical attacks center on their shared cell
   seam.
8. Assert synthetic same-row and same-column non-neighbor targets produce the
   same center, rotation, and size as the corresponding first-neighbor target.
9. Assert an empty first neighboring cell still produces placement.
10. Assert equal-cell, diagonal, out-of-range, and off-board-first-step inputs
    produce no placement and no delay.
11. Keep serialization, zero-duration cleanup, input transparency, z-order,
    ordered event presentation, and one-playback-per-event assertions.
12. Run the integration suite and confirm the new renderer/geometry
    expectations fail before implementation.

## Task 2: Replace procedural drawing with the supplied bitmap

**Files:**
- Add: `inkpics/attack.png`
- Modify: `scripts/attack_vfx.gd`
- Preserve/import metadata: `scripts/attack_vfx.gd.uid`
- Modify only if required by the editor import: `scenes/duel.tscn`

1. Preload `res://inkpics/attack.png` once in `AttackVfx`.
2. Remove ink-color input, edge-ray geometry, procedural fragments, generated
   flecks, `_draw()`, and their obsolete debug observations.
3. Create one reusable local effect root sized 64 × 22 with its pivot at the
   center.
4. Add a clipping child whose width is the reveal progress multiplied by 64,
   keeping its left edge fixed at local x = 0.
5. Add one `TextureRect` at local origin, sized 64 × 22, using the supplied
   texture with keep-aspect-centered stretching and no tint.
6. Change the serialized API to
   `play_attack(seam_global_center, rotation_radians, duration)`.
7. Convert the global seam center into overlay-local coordinates, place the
   effect around that center, and rotate only the effect root so the clipping
   direction remains local-left-to-right.
8. Preserve the current reveal/hold/fade phase ratios and total configured
   duration.
9. Preserve queued-call serialization and zero-duration behavior.
10. Reset visibility, alpha, clip width, rotation, and playing state after
    every call without freeing/recreating the texture hierarchy.
11. Expose focused diagnostics for playback count, last center, last rotation,
    display size, texture path, clip size, and clean state.
12. Run the integration suite and confirm the renderer-level expectations pass.

## Task 3: Resolve the first neighboring seam in the controller

**Files:**
- Modify: `scripts/duel_controller.gd`
- Modify: `tests/test_duel_integration.gd`

1. Remove the obsolete exported `attack_ink_color`; keep
   `attack_vfx_duration`.
2. Add a pure placement helper taking `source_cell` and `target_cell`.
3. Validate both indices against the 3 × 3 row-major board.
4. Accept only targets sharing the source row or column and reject identical
   or diagonal cells.
5. Select the immediate neighboring cell by one row/column step toward the
   target, independently of the target's distance.
6. Resolve source and neighbor `board_cells` and their live global rectangles.
7. Calculate the seam center from the average of their facing edges and the
   midpoint of their aligned centers.
8. Return the approved rotation and neighbor index with that center.
9. In `attack_started` presentation, confirm the source card view still matches
   `source_instance_id` and `source_cell`, but do not require a target card view
   or a card in the neighboring cell.
10. Append the existing trace plus the derived neighbor/placement diagnostics,
    then await the new `play_attack()` API.
11. Skip invalid placement immediately without changing rules state or delaying
    subsequent events.
12. Keep draw-gap ordering, ability pulses, exile, capture, and multi-target
    serialization unchanged.
13. Run integration, simulator, and search suites.

## Task 4: Update documentation and verify the correction

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/DECISIONS.md`
- Modify: `docs/TESTING.md` only if recorded check counts change

1. Replace the procedural/vector-to-target description with the supplied
   bitmap, 64 × 22 fixed box, attacker-side reveal, and first-seam placement.
2. Record that long-range orthogonal attacks do not stretch the image and that
   diagonal attacks require a future mechanic-defined first step.
3. Keep `attack_started` documented as presentation-only transition data before
   `CARD_BE_ATTACKED`.
4. Run script-error checks for every modified GDScript.
5. Run
   `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`.
6. Launch the duel at normal speed and play ordinary, reaction, intercepted,
   movement-activation, and multi-target attacks.
7. Visually confirm the exact PNG reveals from the attacker, remains centered
   on the first seam, rotates correctly in all four directions, and leaves no
   residual visual.
8. Check portrait framing and wide-PC decorative framing.
9. Inspect fresh runtime diagnostics and console output.
10. Run `git diff --check` and inspect `git status --short`.
11. Preserve `scripts/game_settings.gd` and every unrelated user-owned change.
12. Commit only the asset, renderer, controller, focused tests, UID/import
    metadata required by Godot, and focused documentation.
