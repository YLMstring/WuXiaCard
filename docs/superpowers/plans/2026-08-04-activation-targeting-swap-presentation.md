# Activation Targeting and Swap Presentation Implementation Plan

Date: 2026-08-04

Design source:
`docs/superpowers/specs/2026-08-04-activation-targeting-swap-presentation-design.md`

## Objective

Keep every board activation source anchored while the player targets with a
live ink trace, then present committed single-card movement and reciprocal
swaps with real card motion, one movement sound, and no movement trail. Stage
泰山十八盘's automatic swap after its original-square landing and passive pulse,
without changing simulator, AI, replay-record, or card-catalog behavior.

## Execution rules

- Preserve physical hand-card dragging exactly as it works now.
- Keep the simulator authoritative; presentation reads existing transition
  events and never changes logical outcomes.
- Detect movement and swaps from generic `card_moved` data. Do not branch on
  有凤来仪 or 泰山十八盘 card IDs.
- Add failing focused tests before each behavioral layer.
- Preserve unrelated working-tree changes and exclude incidental Summer editor
  rewrites of `project.godot` and `project.godot.bak`.
- Run focused tests after every red/green step and broader controller, replay,
  simulator, selector, and search regressions before completion.
- Commit locally only; do not push.

## Task 1: Establish the baseline and focused presentation suite

Files:

- Create `tests/test_activation_targeting_swap_presentation.gd`.
- Modify `tools/run_tests.ps1` to register the focused suite.

Steps:

1. Record `git status --short`, run the existing focused 泰山/五大夫 controller
   suite, 有凤来仪 integration coverage, replay tests, and the canonical runner.
   Distinguish pre-existing stale failures from new failures.
2. Build a focused production-controller fixture that instantiates
   `scenes/duel.tscn` with a temporary valid profile and deterministic hands.
3. Add red assertions proving:
   - a hand card follows pointer movement;
   - an activatable board card stays in its original global rectangle;
   - a targeting trace exists and follows the pointer;
   - valid and invalid releases remove the trace;
   - logical state does not change before valid release;
   - reciprocal movements expose a swap presentation trace rather than two
     unrelated instant remaps.
4. Run only the new suite and retain the failing output as red evidence.

## Task 2: Separate drag input from card translation

Files:

- Modify `scripts/card_view.gd`.
- Modify `scripts/duel_controller.gd`.
- Extend `tests/test_activation_targeting_swap_presentation.gd`.

Steps:

1. Add a small CardView drag-visual setting that defaults to following the
   pointer. `_move_drag()` always emits `drag_moved`, but changes global position
   only when pointer-following is enabled.
2. Reset the setting in every drag completion/cancellation path so recycled
   hand and board views cannot inherit the wrong mode.
3. In `_on_card_drag_started()`, determine source zone before any reparenting:
   - hand source: retain the current DragLayer reparent and physical drag;
   - board source: disable pointer-following, retain the board-cell parent and
     original position, and keep the existing selected style and 1.05 scale.
4. Update `_return_card_home()` and focus-loss handling so an anchored board
   card is normalized in place rather than redundantly moved through DragLayer.
5. Make the first red assertions green while trace assertions remain red.

## Task 3: Add the live activation-targeting trace

Files:

- Modify `scripts/duel_controller.gd`.
- Extend `tests/test_activation_targeting_swap_presentation.gd`.

Steps:

1. Add controller-owned targeting-trace state separate from committed movement
   presentation. Create one `Line2D` under `DuelCanvas/DragLayer` when a board
   activation drag begins.
2. Use the approved fixed-canvas style: 6-pixel width and
   `Color(0.12, 0.42, 0.38, 0.72)`, starting at the source card center and ending
   at the current pointer position.
3. Update the line on every `drag_moved` signal without playing movement audio.
   Keep current legal-cell and hovered-cell highlights unchanged.
4. Centralize cleanup so valid release, invalid release, focus loss, gesture
   cancellation, scene exit, and `_clear_drag_context()` all remove the line and
   clear its references exactly once.
5. Add narrow debug accessors for trace presence/end position and targeting
   cleanup. Avoid exposing mutable nodes or production state.
6. Verify invalid release commits no action, shakes the source in its original
   cell, and leaves no trace or highlight.

## Task 4: Stage movement events instead of eagerly remapping views

Files:

- Modify `scripts/duel_controller.gd`.
- Extend `tests/test_activation_targeting_swap_presentation.gd`.
- Update `tests/test_taishan_wudafu_integration.gd` where its immediate-remap
  expectation must now await presentation completion.

Steps:

1. Capture board views before simulator application for both play and activate
   actions. For hand play, add the newly placed view to the captured layout at
   the selected original cell after placement reparenting.
2. Remove the eager `_remap_board_views_from_movements()` call that currently
   moves views to final cells before ability pulses and movement events.
3. Change transition presentation to an indexed event loop so it can inspect
   the next movement event and consume one event or a reciprocal pair.
4. At each `card_moved` event, validate the exact pre-movement instance, owner,
   source cell, and target cell against the captured view layout.
5. Reconcile `board_cards` incrementally after each committed movement group.
   Later attack/flip/exile presentation must see the already-presented cell
   layout and await movement completion.
6. If an event is malformed or a view is missing, normalize and reconcile all
   surviving views directly to `duel_state`, then continue without changing
   logical results.
7. Keep `debug_get_board_card_instance_id()` accurate before, during, and after
   the staged presentation.

## Task 5: Present real single-card and reciprocal swap motion

Files:

- Modify `scripts/duel_controller.gd`.
- Extend `tests/test_activation_targeting_swap_presentation.gd`.
- Extend existing 有凤来仪 controller coverage in
  `tests/test_duel_integration.gd` only if the focused fixture cannot exercise
  both activation branches safely.

Steps:

1. Add exported presentation values:
   - `swap_duration = 0.28`;
   - `swap_arc_ratio = 0.12`;
   - `entrance_original_slot_duration = 0.30`;
   - targeting-trace width and color from the approved spec.
2. Implement committed single-card movement:
   - preserve the view's original global rectangle;
   - temporarily reparent it to DragLayer;
   - play movement audio once;
   - tween it to the destination rectangle;
   - reparent and normalize it in the destination cell;
   - create no movement trail.
3. Detect a swap only when consecutive movement events are reciprocal A→B and
   B→A and both exact views are present.
4. Implement reciprocal motion by reparenting both views to DragLayer and
   tweening them simultaneously along opposing quadratic arcs. Use a
   perpendicular midpoint offset equal to 12% of the shorter cell side, with
   opposite signs for the two cards.
5. Include eased landing within the 0.28-second duration, play movement audio
   once for the pair, create no movement trail, then normalize and reparent both
   views into their final cells.
6. Add immutable debug traces/counters for ordinary movement, reciprocal swap,
   and movement-sound requests so headless tests can assert one presentation
   and one sound without depending on transient audio playback state.
7. Remove the old post-commit brush-trail call from movement presentation. Do
   not reuse the live targeting trace as a movement trail.

## Task 6: Preserve 泰山 entrance timing and effect order

Files:

- Modify `scripts/duel_controller.gd`.
- Extend `tests/test_taishan_wudafu_integration.gd`.
- Extend `tests/test_activation_targeting_swap_presentation.gd`.

Steps:

1. Track the beginning of a hand-play presentation. When that play later emits
   movement events for the played instance, keep its pre-movement view layout
   visible for at least 0.30 seconds total.
2. Count placement settling and the normal `ability_triggered` pulse toward the
   0.30-second phase. Wait only the remaining duration; do not add an extra
   unconditional 0.30-second pause.
3. Verify the passive pulse finds 泰山 in its originally selected cell, then the
   reciprocal movement presentation runs, then `attack_started` finds the same
   instance in its new cell.
4. Preserve the existing rule that the swap action declares no attack. Do not
   change `duel_simulator.gd` or the card declaration for presentation timing.
5. In fast mode, set entrance hold and movement durations to zero while keeping
   identical event consumption and final board-view mappings.

## Task 7: Replay, cancellation, and final verification

Files:

- Modify `tests/test_duel_replay.gd` if focused coverage requires a replay
  presentation assertion.
- Modify production files only for issues found by verification.

Steps:

1. Verify replay presents committed ordinary movement and reciprocal swaps but
   never creates a targeting trace, because pointer gestures are not recorded.
2. Verify focus loss and scene exit during targeting remove the live trace and
   leave the anchored source normalized. Verify an interrupted movement tween
   reconciles surviving views before interaction resumes.
3. Run the focused targeting/swap suite, 泰山/五大夫 simulator and controller
   suites, 有凤来仪 integration coverage, replay suites, selector suite, search
   suite, and the canonical runner. Compare broad failures against the recorded
   baseline.
4. Run `git diff --check`, inspect `git status --short`, and review the complete
   diff for card-ID branches, movement trails, incidental project-setting
   rewrites, and unrelated changes.
5. Check every modified GDScript with Summer script diagnostics. Clear the
   console and boot the main scene with zero new errors.
6. Play the production portrait duel and verify on mouse and touch paths:
   - hand cards still physically drag;
   - board activations keep their source anchored with a live targeting trace;
   - invalid release cleans up in place;
   - 有凤来仪 moves or swaps only after release, with one sound and no trail;
   - 泰山 lands, pulses in the original square, swaps, then attacks from the new
     square;
   - replay shows the same committed motion without targeting traces.
7. Read diagnostics, console, and debugger errors after the walkthrough. Fix
   any new issue and rerun focused plus affected regression suites.
8. Commit the complete implementation locally with a behavior-focused message;
   do not push.
