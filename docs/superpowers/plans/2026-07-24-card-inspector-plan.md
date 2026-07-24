# In-Game Card Inspector Implementation Plan

Date: 2026-07-24  
Design: `docs/superpowers/specs/2026-07-24-card-inspector-design.md`

## Task 1: Add focused inspector tests first

Files:

- Add `tests/test_card_inspector.gd`
- Update `tests/test_duel_integration.gd`

Steps:

1. Add a direct scene test for the inspector's field population, fixed tag order, placeholders, responsive board rectangle, and vertical overflow structure.
2. Add input tests showing that a tap closes but a gesture exceeding the scroll threshold does not.
3. Add CardView gesture coverage showing a revealed tap emits inspection, a face-down tap does not, and motion beyond threshold enters the existing drag path.
4. Add duel-level checks for hiding/restoring the board and scores, modal action blocking, repeated open/close state preservation, and resolution-state rejection.
5. Add an AI-gating integration check in which search may complete during inspection but its selected action is not committed until close.
6. Run the focused tests and confirm the new checks fail for the expected missing feature.

## Task 2: Build the reusable parchment inspector

Files:

- Add `scenes/card_inspector.tscn`
- Add `scripts/card_inspector.gd`

Steps:

1. Create a full-viewport modal `Control` with a board-positioned parchment panel.
2. Build the parchment from Godot UI controls: shadow, parchment body, top/bottom rods, margin container, vertical scroll container, title, ordered metadata tags, rules block, flavor block, and close hint.
3. Use containers, wrapping labels, and theme overrides so the panel remains responsive in portrait layouts.
4. Expose `present(card_data, board_rect)`, `set_board_rect(board_rect)`, `close()`, and `is_open()` APIs.
5. Deep-copy presented data and normalize missing `glyph`, `sect`, `tier`, `weapon`, `description`, and `flavor` values to `—`.
6. Format valid tiers as `<number>阶`.
7. Track pointer movement so a tap emits `inspection_closed`, while a scroll-sized gesture remains open.
8. Keep the inspector independent of duel state, catalog lookup, and card views.
9. Run `test_card_inspector.gd`.

## Task 3: Separate tap from drag in CardView

Files:

- Update `scripts/card_view.gd`
- Update `tests/test_duel_integration.gd`

Steps:

1. Add `inspection_requested(card_data)` and an exported tap/drag movement threshold.
2. Change GUI press handling to begin a pending pointer gesture instead of immediately beginning a drag.
3. On pointer motion beyond the threshold, begin the existing drag path only when the card is playable.
4. On release below the threshold, emit a deep card-data snapshot only when the card is revealed.
5. Cancel both pending taps and active drags safely on application focus loss.
6. Preserve `_try_begin_drag` as the authoritative drag transition so existing production and test paths remain valid.
7. Verify mouse and touch behavior with focused integration checks.

## Task 4: Integrate modal inspection into the duel

Files:

- Update `scenes/duel.tscn`
- Update `scripts/duel_controller.gd`
- Update `tests/test_duel_integration.gd`

Steps:

1. Instance `CardInspector` above ordinary duel UI but below existing transient VFX where appropriate.
2. Connect every spawned CardView's inspection signal in `_spawn_card_in_slot`.
3. Accept requests only in player, opponent, or complete states; reject resolving-state and duplicate requests.
4. On open, store required presentation state, hide the board and score overlay, disable playability, show the inspector, and set modal status text.
5. Add the inspection-open guard to manual drag/action entry points.
6. On close, restore the board and scores, recompute hand playability and status, and leave logical duel state untouched.
7. Update `_layout_duel` so an open inspector follows the exact board rectangle across resize.
8. Suppress AI progress text while inspection owns the status presentation.
9. If search completes while inspection is open, wait frame-by-frame before result validation and action presentation.
10. Ensure exit-tree cancellation and match completion remain safe whether inspection is open or closed.

## Task 5: Reconcile current catalog/deck test fixtures

Files:

- Update `tests/test_card_catalog.gd`
- Update `tests/test_duel_integration.gd`

Steps:

1. Replace obsolete expected `xu_shu` and `zhang_ren` encounter IDs with the approved `CangSongYingKe2` and `CangSongYingKe1` IDs.
2. Keep exact catalog picture and metadata assertions aligned with the two updated definitions.
3. Add inspector assertions using the populated tier-two card and placeholder assertions using an incomplete legacy card.
4. Do not stage or modify the user's `scripts/duel_decks.gd` working-tree change.

## Task 6: Full verification and portrait playtest

Files:

- No production edits unless verification exposes a defect

Steps:

1. Run script diagnostics for every modified GDScript.
2. Run:
   - `tests/test_card_inspector.gd`
   - `tests/test_card_catalog.gd`
   - `tests/test_duel_rules.gd`
   - `tests/test_duel_simulator.gd`
   - `tests/test_duel_search.gd`
   - `tests/test_duel_integration.gd`
3. Clear the Summer console and launch the main scene in portrait mode.
4. Walk the approved golden path:
   - Tap the revealed tier-two card to inspect
   - Confirm sect, tier, weapon, description, and flavor presentation
   - Scroll long flavor text
   - Tap to close
   - Drag and play the same card normally
   - Inspect a revealed board card
   - Confirm a face-down opponent card cannot open the inspector
   - Open during AI thinking and confirm no move presents before close
5. Capture the open inspector and restored duel as runtime frames.
6. Read diagnostics, console output, and debugger errors.
7. Review `git diff --check` and stage only inspector-related production files, tests, and docs.
8. Commit the verified feature without staging `scripts/duel_decks.gd` or other user-owned edits.
