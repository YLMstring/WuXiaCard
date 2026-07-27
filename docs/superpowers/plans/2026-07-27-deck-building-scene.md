# Deck-Building Scene Implementation Plan

**Design:** `docs/superpowers/specs/2026-07-27-deck-building-scene-design.md`

**Goal:** Add a separately runnable portrait deck-building scene with the
existing duel chrome, a virtualized 1,000-slot `藏经阁`, persistent five-card
main-deck selection, hold-then-drag card exchanges, testing-mode opponent
visibility, and reusable card inspection.

**Architecture:** Keep duel rules and presentation untouched. Introduce a pure
`DeckProfileStore` for versioned collection persistence, a reusable
`DeckLibrarySlot` for tap/hold/scroll gesture arbitration, a virtualized
`DeckLibraryGrid`, and a focused `DeckBuilderController`. Reuse `CardView`,
`CardInspector`, `DuelBackdrop`, existing visual assets, and `DuelDecks` data.
Only `DuelDecks` and the test runner integrate with existing runtime paths.

## Task 1: Establish the baseline and profile contract

**Files:**
- Create: `tests/test_deck_profile_store.gd`
- Modify: `tools/run_tests.ps1`
- Verify: `tests/test_card_catalog.gd`
- Verify: `tests/test_duel_integration.gd`

1. Run `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1` before
   behavioral edits and record the fresh seven-suite baseline.
2. Add `test_deck_profile_store.gd` to the runner before implementation so the
   new suite fails for the missing class.
3. Give every profile test a unique `user://` path and clean up only that exact
   file plus its temporary/backup siblings; never touch the production save.
4. Specify constants and default data:
   - schema version `1`;
   - library capacity `1000`;
   - main-deck capacity `5`;
   - default five IDs in current player-deck order;
   - unlocked defaults equal all catalog IDs except `CangSongYingKe1`;
   - the four non-deck unlocked cards occupy the first four library positions;
   - positions 5–1,000 are empty.
5. Assert the complete profile invariant:
   - five valid, unique, unlocked main-deck IDs;
   - exactly 1,000 library values;
   - occupied library values form one compact prefix;
   - no duplicate appears across deck and library;
   - the union of placements equals the unlocked set.
6. Specify successful exchange behavior for each hand position and several
   logical library indices. Assert the displaced hand card takes the exact
   source position, the main-deck order changes only at the target, the occupied
   prefix remains compact, and no unrelated entry changes.
7. Specify unlock behavior:
   - a new valid card is inserted at library position 1;
   - existing library cards shift in stable order;
   - the deck is unchanged;
   - duplicate and unknown unlock requests are no-ops;
   - a full library rejects a new unlock without data loss.
8. Specify save/load round trips, exact slot persistence, and stable deck order.
9. Specify recovery for malformed JSON, missing fields, unknown IDs, duplicate
   placements, a wrong library length, gaps inside the occupied prefix, and
   unlocked-but-unplaced cards.
10. Assert repair prefers deck placements, then first library occurrences;
    compacts valid library order; restores missing unlocked cards at the top;
    and falls back to defaults only when five valid owned cards cannot be
    reconstructed.
11. Specify atomic-save failure behavior through a narrow injectable file
    operation seam or test-only failing path. The store must report failure
    without mutating the caller's last valid profile.
12. Run the new suite and confirm the missing implementation causes a clean,
    expected failure.

## Task 2: Implement versioned deck persistence and duel deck loading

**Files:**
- Create: `scripts/deck_profile_store.gd`
- Modify: `scripts/duel_decks.gd`
- Modify: `tests/test_deck_profile_store.gd`
- Modify: `tests/test_duel_integration.gd`

1. Implement `DeckProfileStore` as a `RefCounted` data service with no scene or
   UI dependency.
2. Give it a production default path such as
   `user://wuxia_deck_profile.json` and allow a caller-supplied path for tests.
3. Keep JSON values as strings and `null`; normalize IDs to `StringName` only
   at the catalog/runtime boundary.
4. Expose focused operations:
   - create defaults;
   - load and validate;
   - repair;
   - save atomically;
   - exchange a library index with a deck index;
   - unlock one catalog ID;
   - return the ordered main-deck IDs.
5. Keep the canonical default player IDs in one place. Preserve
   `DuelDecks.PLAYER_CARD_IDS` compatibility as a constant alias or copied
   constant so existing tests and callers do not break.
6. Implement validation with explicit result data rather than assertions. A
   corrupt user save must never prevent boot.
7. Write to a sibling temporary file, validate the serialized result, then
   replace the production save. Preserve the last valid file if any step fails.
8. Make exchanges transactional: validate a copied candidate, save it, and
   return the candidate only on success. On failure, return the unchanged
   profile plus a failure result.
9. Add an optional profile path to
   `DuelDecks.get_player_card_ids(profile_path := DEFAULT_PATH)`. Production
   callers keep the no-argument path; tests use isolated paths.
10. Keep `get_opponent_card_ids()` and `get_side_deck_card_ids()` unchanged.
11. Add an exported, pre-ready-settable `deck_profile_path` to
    `DuelController`. Its default remains the production path, and the
    controller still calls `DuelDecks` rather than knowing profile JSON.
12. Assert a duel instantiated against a temporary saved profile creates its
    player hand in the saved order while its side deck remains the full catalog.
13. Run profile, catalog, simulator, search, and duel integration suites.

## Task 3: Build the reusable library slot and gesture arbiter test-first

**Files:**
- Create: `scenes/deck_library_slot.tscn`
- Create: `scripts/deck_library_slot.gd`
- Create: `tests/test_deck_library_grid.gd`
- Modify: `tools/run_tests.ps1`
- Verify: `tests/test_card_inspector.gd`

1. Add `test_deck_library_grid.gd` to the test runner and first assert the
   required slot scene and signals are absent.
2. Build one `DeckLibrarySlot` control with:
   - an empty-slot panel;
   - a `CardView` child used only for visuals;
   - a name label below the card;
   - a timer or deadline for the tunable 0.25-second hold threshold.
3. Set the nested `CardView` to input-ignore in this context. Do not change the
   duel's `CardView` gesture behavior.
4. Expose one `bind(logical_index, card_data_or_empty)` operation that fully
   clears stale artwork, powers, ki, face-down state, label text, drag state,
   timers, and modulation before applying new content.
5. Emit narrow signals carrying the current logical index:
   - `inspection_requested`;
   - `drag_armed`;
   - `drag_started`;
   - `drag_moved`;
   - `drag_ended`.
6. Let pointer movement before the hold deadline propagate to the parent
   `ScrollContainer`; cancel the pending tap/hold without emitting inspection
   or drag.
7. On release before the hold deadline with movement inside the tap threshold,
   emit inspection exactly once for an occupied revealed card.
8. When the hold deadline expires without meaningful movement, arm drag and
   show the approved restrained lift cue. Begin the drag only on subsequent
   movement.
9. Empty slots allow parent scrolling but never arm, drag, or inspect.
10. Cancel all pending state on rebind, inspector opening, focus loss, scene
    exit, and pointer-ID mismatch.
11. Test mouse and `InputEventScreenTouch`/`InputEventScreenDrag` paths for:
    tap, pre-hold scroll, successful hold, post-hold drag, early release, empty
    slots, focus loss, and rebinding while pending.
12. Assert the optional slot wrapper leaves the existing `CardView` tap/drag
    tests and duel behavior unchanged.

## Task 4: Build the virtualized 1,000-slot parchment grid

**Files:**
- Create: `scenes/deck_library_grid.tscn`
- Create: `scripts/deck_library_grid.gd`
- Modify: `tests/test_deck_library_grid.gd`

1. Create a parchment frame matching the inspector's body, rods, border,
   shadow, and color treatment without changing `CardInspector`.
2. Add a fixed title `藏经阁`, a vertically scrolling viewport, and an internal
   logical content control sized for exactly 200 rows.
3. Calculate five equal columns from the available width while preserving
   CardView's 3:4 card aspect and reserving one label line under each card.
4. At the reference 540×960 duel canvas, lay out exactly three complete rows in
   the visible parchment body.
5. Instantiate a fixed pool for three visible rows plus one buffer row above and
   below. Do not instantiate 1,000 slots or 200 row containers.
6. On scroll-value changes:
   - map the offset to the first logical row;
   - clamp to rows 0–197 at the bottom;
   - position the row pool at the corresponding logical Y coordinates;
   - bind each slot to its logical index and current profile value.
7. Keep a stable logical-index-to-visible-slot lookup for controller refreshes.
8. Forward slot inspection and drag signals with logical indices. Freeze row
   recycling while a card drag is armed or active so its source identity cannot
   change.
9. Expose focused operations:
   - `set_library_slots`;
   - `set_scroll_offset` / `get_scroll_offset`;
   - `refresh_logical_index`;
   - `set_interaction_enabled`;
   - `cancel_active_gesture`;
   - debug observations for visible logical rows and pool size.
10. Test top, middle, and bottom bindings, including logical slot 1,000.
11. Test that recycled occupied slots become visually and interactively empty,
    and empty slots become fully configured cards without retaining stale state.
12. Test that scroll offset survives data refresh and inspection disable/enable.
13. Test that the pool size remains constant while traversing all 200 rows.

## Task 5: Compose the deck-building scene and controller test-first

**Files:**
- Create: `scenes/deck_builder.tscn`
- Create: `scripts/deck_builder_controller.gd`
- Create: `tests/test_deck_builder_integration.gd`
- Modify: `tools/run_tests.ps1`

1. Add the new integration suite to the runner and assert the required scene
   contract before implementation.
2. Build `deck_builder.tscn` as a separate full-rect scene with:
   - `DecorBackdrop`;
   - fixed 540×960 `DuelCanvas`;
   - the existing topwash structure and back-arrow asset;
   - enemy seal, upcoming enemy label, and icon-only back button;
   - five-slot opponent hand;
   - `DeckLibraryGrid` in the duel board rectangle;
   - five-slot player hand;
   - a bottom status label;
   - full-canvas drag layer;
   - existing `CardInspector`.
3. Do not add board cells, score panels, audio players, attack VFX, AI, or duel
   simulator dependencies.
4. Implement the same `DuelBackdrop.fit_duel_rect()` and equal hand-to-center
   spacing principles used by `_layout_duel()`. Keep the three-row library
   inside the current board/inspector rectangle.
5. Reuse the duel's hand-slot creation and style values in focused helper
   methods inside `DeckBuilderController`; do not refactor the large working
   duel controller for this feature.
6. Give the controller exported/test-settable inputs:
   - profile path;
   - upcoming enemy name;
   - upcoming enemy five-card IDs;
   - a pre-ready-settable testing-mode value defaulting to
     `Settings.TESTING_MODE`;
   - hold duration;
   - zero-duration/debug fast mode where applicable.
7. On `_ready()`:
   - validate the card catalog;
   - load or repair the profile;
   - create five opponent cards from `DuelDecks.get_opponent_card_ids()`;
   - hide them unless `Settings.TESTING_MODE`;
   - create five revealed player main-deck cards;
   - bind all 1,000 library values to the virtual grid;
   - connect back, inspection, and drag signals;
   - lay out the fixed canvas.
8. Emit `back_requested` from the back button and perform no navigation,
   quitting, or tree change.
9. On a library drag:
   - record the logical source index and pre-swap profile;
   - render a non-owning proxy in `DragLayer`;
   - keep the real virtual slot bound and visually reserved;
   - hit-test only the five player-hand slot rectangles;
   - commit through `DeckProfileStore` on a valid drop;
   - update the one hand slot and one visible library slot without changing
     scroll offset;
   - restore the pre-swap state on invalid drop or save failure.
10. Use the bottom status line for the normal instruction, inspection text, and
    a brief `保存失败` message when persistence fails.
11. On inspection, disable the grid, preserve its scroll offset, show the
    existing inspector in the library rectangle, and restore the exact offset
    and instruction after closing.
12. Permit inspection of player and library cards. Permit opponent inspection
    only when testing mode reveals them.
13. Add debug observations or helpers only where tests need deterministic
    access to logical profile data, visible rows, drag outcome, inspection
    state, and emitted back count.
14. Test:
    - required node structure and absence of score panels;
    - five fixed hand slots;
    - four initial cards then empty slots;
    - opponent privacy in normal mode and reveal in testing mode;
    - tap/hold/scroll routing;
    - valid exchanges to all five hand slots;
    - invalid/cancelled drops;
    - persistence failure rollback;
    - inspection and offset restoration;
    - back signal without navigation.

## Task 6: Lock responsive layout and saved-deck integration

**Files:**
- Modify: `tests/test_deck_builder_integration.gd`
- Modify: `tests/test_duel_integration.gd`
- Modify: `scripts/duel_decks.gd` if integration adjustments remain
- Verify: `scripts/duel_backdrop.gd`
- Verify: `project.godot`

1. Exercise the deck builder at:
   - 540×960 reference portrait;
   - a taller Android-like viewport;
   - a wide PC viewport.
2. Assert the internal canvas remains exactly 9:16 and centered, while
   `DecorBackdrop` classifies and decorates the exterior using existing rules.
3. Assert opponent hand, library, and player hand remain inside the fixed
   canvas and preserve equal center-to-hand spacing.
4. Assert the title, three complete rows, card-name line, status line, and back
   icon do not overlap at the minimum supported portrait size.
5. Scroll to the last logical row and assert slot 1,000 remains reachable and
   fully within the scroll viewport.
6. Save a non-default deck through a temporary controller profile, instantiate a
   duel configured with the same temporary path, and assert its starting hand
   matches the saved order.
7. Assert opponent main deck and both side decks are unchanged.
8. Run deck profile, library grid, deck builder integration, duel integration,
   backdrop, inspector, simulator, and search suites.

## Task 7: Document, verify, and playtest

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/DECISIONS.md`
- Modify: `docs/TESTING.md`
- Verify: `docs/HANDOFF.md` if its scene/data map names the deck provider

1. Document the new scene boundary, profile schema, save path, repair rules,
   virtualized-grid responsibility, and `back_requested` navigation contract.
2. Record why the deck builder is separate from `DuelController`, why the grid
   virtualizes 1,000 slots, and why mobile drag uses hold-then-drag.
3. Add the three new suites to the testing guide and update the authoritative
   suite/check-count baseline from a fresh complete run.
4. Run script-error checks for every created or changed GDScript.
5. Run `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1` after the
   final edit and require all ten suites to pass with no `ERROR:`,
   `SCRIPT ERROR`, `_FAILED`, or `CHECK_FAILED`.
6. Run `scenes/deck_builder.tscn` directly at normal speed and manually verify:
   - opponent privacy and testing reveal;
   - four cards followed by empty slots;
   - three visible rows;
   - smooth scrolling toward the bottom;
   - tap to inspect;
   - hold cue, drag, valid swap, cancellation, and reload persistence;
   - back signal without navigation.
7. Test mouse input and Android-like touch emulation. If an Android device/build
   is available, verify physical touch scrolling and hold-then-drag there.
8. Inspect fresh runtime console/debugger output after each manual path.
9. Run `git diff --check`, inspect `git status --short`, and preserve all
   unrelated user-owned changes.
10. Commit only the focused implementation, tests, and documentation.

## Task 8: Refine library density, ratio, spacing, and tier names

**Files:**
- Modify: `scripts/deck_library_grid.gd`
- Modify: `scripts/deck_library_slot.gd`
- Modify: `tests/test_deck_library_grid.gd`
- Modify: `tests/test_deck_builder_integration.gd`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/DECISIONS.md`
- Modify: `docs/TESTING.md`

1. Add failing virtual-grid checks for four columns, a 20-control pool, 250
   logical rows, reachability of logical slot 1,000, and unchanged three-row
   visibility.
2. Add a failing slot-layout check that the rendered CardView host remains at
   the standard 3:4 width-to-height ratio after the library is laid out.
3. Add failing checks for the six approved name colors:
   - tier 1 `#66717A`;
   - tier 2 `#3E7659`;
   - tier 3 `#3F6F9C`;
   - tier 4 `#715A96`;
   - tier 5 `#9A612D`;
   - every other value `#963F4A`.
4. Add a failing geometry check for an 8-pixel first-row inset below the
   scroll content origin.
5. Change the virtual grid constants to four columns and 250 rows. Keep three
   visible rows and one buffer row on each side, yielding exactly 20 live slot
   controls.
6. Calculate card height from column width at 3:4, center the card-and-name
   group within its row, and leave all duel/hand CardView sizing untouched.
7. Apply tier name color inside `DeckLibrarySlot.bind()` and reset the override
   on every rebind so recycled slots never inherit stale colors.
8. Offset logical row positions by 8 pixels and include that inset in the
   content minimum height and bottom scroll range.
9. Update deck-builder integration expectations from 25 to 20 pooled controls
   and from a partial first row to a full four-card first row.
10. Run script-error checks, the focused library suite, then the complete
    ten-suite runner.
11. Restart `res://scenes/deck_builder.tscn` and manually verify proportions,
    spacing, tier-name readability, swipe scrolling, inspection, and
    hold-then-drag exchange.
