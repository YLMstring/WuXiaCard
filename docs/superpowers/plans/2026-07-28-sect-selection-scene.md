# Sect Selection Scene Implementation Plan

**Design:** `docs/superpowers/specs/2026-07-28-sect-selection-scene-design.md`

**Goal:** Start the game on a sect-selection scene that exactly reuses the
deck-builder presentation, previews a selected sect's strongest and weakest
cards, inspects sects and cards, and unlocks the selected sect's tier-1 cards
before entering deck building.

**Architecture:** Keep `DeckBuilderController` behavior intact. Build
`sect_selection.tscn` as an inherited presentation of `deck_builder.tscn` with
its own controller and hidden first/second controls. Extend the existing
virtualized library and `CardView` through backward-compatible display options
for prepared sect definitions, hidden powers, and per-entry drag eligibility.
Extend `DeckProfileStore` with versioned sect ownership and one transactional
batch-card-unlock operation.

## Task 1: Establish the baseline and profile contract

**Files:**
- Modify: `tests/test_deck_profile_store.gd`
- Modify: `scripts/deck_profile_store.gd`
- Verify: `tests/test_sect_catalog.gd`
- Verify: `tests/test_deck_builder_integration.gd`

1. Run `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1` and retain
   the fresh twelve-suite baseline before behavioral changes.
2. Add failing profile checks for schema version 2 and
   `unlocked_sect_ids`.
3. Specify a new profile containing only `xuanyue_jianzong` in its unlocked
   sect list while preserving the current default deck and unlocked cards.
4. Specify migration of schema-1 profiles:
   - add `xuanyue_jianzong`;
   - preserve all valid card ownership, library order, and main-deck order;
   - unlock no additional cards.
5. Specify repair of missing, duplicated, malformed, and unknown sect IDs.
   Every repaired profile must contain `xuanyue_jianzong`.
6. Add `get_unlocked_sect_ids(profile)` and validate that every saved sect ID
   exists in `SectCatalog`, is unique, and includes the default sect.
7. Add a transactional
   `unlock_cards_and_save(profile, ordered_card_ids)` operation:
   - filter unknown and already-unlocked IDs;
   - preserve input order;
   - insert the new batch ahead of the existing occupied library prefix;
   - add the same IDs to ownership without duplicates;
   - save once and return the candidate only on success;
   - treat a valid empty/no-op batch as successful without rewriting the file;
   - reject capacity overflow or save failure without mutating the caller's
     profile.
8. Test the exact tier-1 batches currently associated with all five sects,
   including two-card batches, order preservation, repeat selection, and a
   partially pre-unlocked batch.
9. Run the profile, card-catalog, sect-catalog, and deck-builder suites.

## Task 2: Generalize reusable card and library presentation

**Files:**
- Modify: `scripts/card_view.gd`
- Modify: `scripts/deck_library_slot.gd`
- Modify: `scripts/deck_library_grid.gd`
- Modify: `tests/test_deck_library_grid.gd`
- Verify: `tests/test_deck_builder_integration.gd`
- Verify: `tests/test_duel_integration.gd`

1. Add a `power_numbers_enabled` state and
   `set_power_numbers_enabled(value)` to `CardView`. Power labels are visible
   only when the card is face-up and the flag is enabled. The default remains
   enabled so duel and deck-builder cards do not change.
2. Extend `DeckLibrarySlot.bind()` with backward-compatible options for:
   - whether the entry may arm a drag;
   - whether its power numbers are shown.
3. Add a `hold_recognized` signal emitted once when the hold threshold is
   reached for any occupied entry.
4. Track a completed hold separately from a tap. Releasing a non-draggable
   held entry must not open the inspector, while a short release still emits
   inspection.
5. Keep unlocked-card behavior unchanged: a hold arms the existing drag, the
   first following movement shows the visual vacancy, and release/cancellation
   resets the slot.
6. Extend `DeckLibraryGrid` with a prepared-entry API that accepts:
   - dictionaries or empty values;
   - display owner IDs;
   - per-entry drag-enabled flags;
   - a power-number visibility setting.
7. Preserve `set_library_slots()` as the existing card-ID adapter so all
   deck-builder callers and tests remain compatible.
8. Forward `hold_recognized` with logical index and display data. Keep
   virtualization, four-column sizing, 1,000 logical slots, the 20-control
   pool, scrolling, and gesture freezing unchanged.
9. Add focused tests for hidden powers, locked-entry taps, locked-entry holds,
   unlocked holds/drags, prepared-definition recycling, and reset of every
   per-entry display flag.
10. Run the grid, deck-builder, inspector, and duel integration suites.

## Task 3: Create the exact-look sect-selection scene

**Files:**
- Create: `scenes/sect_selection.tscn`
- Create: `scripts/sect_selection_controller.gd`
- Create: `tests/test_sect_selection_integration.gd`
- Modify: `tools/run_tests.ps1`

1. Register `test_sect_selection_integration.gd` in the test runner before
   implementation and confirm the missing scene fails cleanly.
2. Make `sect_selection.tscn` inherit `deck_builder.tscn`, override only the
   root script, and hide/disable `GoFirstButton` and `GoSecondButton`.
3. Preserve all inherited node paths and visual properties:
   `DecorBackdrop`, fixed `DuelCanvas`, lacquer header, opponent label, back
   icon, both hands, `DeckLibraryGrid`, `藏经阁`, status line, drag layer, and
   `CardInspector`.
4. Give `SectSelectionController` focused inputs matching the reused shell:
   profile path, upcoming enemy name, hold duration, and library aspect ratio.
5. On ready:
   - validate both catalogs;
   - load or repair the profile;
   - create five empty slots in each hand;
   - populate the grid with all `SectCatalog` definitions in catalog order,
     followed by empty logical slots;
   - use blue/player display ownership for unlocked sects and red/opponent
     display ownership for locked sects;
   - enable dragging only for unlocked sects;
   - hide powers and ki badges for sect entries;
   - connect inspection, hold, drag, back, resize, and inspector signals.
6. Reuse the deck-builder's exact header styling and fixed-canvas layout
   calculations. Do not add scene-specific visual offsets.
7. Add integration checks for identical core geometry, the unchanged title,
   absent first/second controls, five sects in catalog order, 995 empty logical
   slots, correct blue/red ownership, hidden powers/ki, five empty upper slots,
   and five empty lower slots.

## Task 4: Implement preview, inspection, and drag selection

**Files:**
- Modify: `scripts/sect_selection_controller.gd`
- Modify: `tests/test_sect_selection_integration.gd`

1. Resolve a sect entry by its catalog ID. Find associated cards by comparing
   each card definition's `sect` text with the sect definition's `glyph`.
2. Build stable preview orders from `CardCatalog` order:
   - upper hand: tier descending, catalog index ascending on ties;
   - lower hand: tier ascending, catalog index ascending on ties;
   - take at most five and leave all remaining slots empty.
3. On a short tap, refresh both hands before presenting the sect definition in
   `CardInspector`.
4. On `hold_recognized`, refresh both hands without opening the inspector.
5. Make every preview card face-up and non-playable regardless of testing mode.
   Connect its inspection signal to the existing inspector. Never connect card
   drag signals.
6. Preserve selected previews when either sect or card inspection closes.
7. On an unlocked sect drag:
   - create a non-owning drag proxy with powers and ki hidden;
   - preserve the inherited hold scale and source vacancy behavior;
   - accept a drop anywhere inside `PlayerHand.get_global_rect()`;
   - cancel safely elsewhere.
8. On a valid drop, collect the sect's tier-1 IDs in catalog order and call the
   profile store's batch unlock operation.
9. On success, update the in-memory profile and emit
   `deck_builder_requested`. On failure, stay interactive and show `保存失败`.
10. A locked hold shows a locked notice, creates no proxy, and never emits a
    deck-builder request.
11. Emit `back_requested` from the inherited return icon without changing the
    scene directly.
12. Add deterministic debug observations only for selected sect, preview IDs,
    inspection state, status, and successful selection.
13. Test tap ordering, sect inspection, card inspection, close-and-restore,
    highest/lowest sort direction, tie breaking, empty padding, locked hold,
    unlocked hold/drag, full-hand hit testing, cancellation, save rollback,
    tier-1 batch order, and repeat selection.

## Task 5: Integrate startup and scene navigation

**Files:**
- Modify: `scripts/main_flow_controller.gd`
- Modify: `tests/test_main_flow.gd`
- Verify: `main.tscn`
- Verify: `tests/test_deck_builder_integration.gd`
- Verify: `tests/test_duel_integration.gd`

1. Preload `sect_selection.tscn` and start `MainFlowController` with
   `_show_sect_selection()`.
2. Pass the configured profile path and opponent name into the sect-selection
   controller.
3. Connect `deck_builder_requested` to `_show_deck_builder()`.
4. Leave sect-selection and deck-builder `back_requested` signals
   navigation-neutral until a main menu exists.
5. Preserve existing routes:
   - deck-builder first/second choice enters the duel;
   - duel return enters deck building rather than sect selection.
6. Update the main-flow suite to assert:
   - initial screen is `SectSelectionController`;
   - its back request leaves the current screen unchanged;
   - choosing the default unlocked sect enters `DeckBuilderController`;
   - builder back remains navigation-neutral;
   - first/second choices and duel return retain their current behavior.
7. Use only isolated test profile paths and clean their exact temporary and
   backup files.

## Task 6: Verify behavior and presentation

**Files:**
- Verify all files above

1. Run script-error checks for every changed or created GDScript.
2. Run the focused profile, library-grid, sect-selection, main-flow,
   deck-builder, inspector, backdrop, and duel integration suites.
3. Run
   `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1` and require
   all thirteen suites to emit their pass markers with no `ERROR:`,
   `SCRIPT ERROR`, `_FAILED`, or `CHECK_FAILED`.
4. Run the main scene at 540×960 and verify:
   - the sect-selection scene is the first screen;
   - it looks exactly like deck building apart from the specified content and
     missing choice controls;
   - initial hands are empty;
   - taps update previews before opening inspection;
   - holds update previews;
   - locked sects do not drag;
   - the unlocked sect drags over the whole lower hand;
   - tier-1 cards appear at the library top in catalog order;
   - deck building and duel navigation remain correct.
5. Repeat the interaction path with touch emulation at a tall Android-like
   viewport and verify swipe scrolling, tap/hold arbitration, drag vacancy,
   portrait geometry, and decorative overflow.
6. Inspect fresh runtime output after each path.
7. Run `git diff --check` and inspect `git status --short`, preserving all
   unrelated user-owned changes.
