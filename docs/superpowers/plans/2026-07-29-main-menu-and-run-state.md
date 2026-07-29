# Main Menu and Run State Implementation Plan

**Design:** `docs/superpowers/specs/2026-07-29-main-menu-and-run-state-design.md`

## Task 1: Add explicit run state to the profile

**Files:**
- Modify: `scripts/deck_profile_store.gd`
- Modify: `tests/test_deck_profile_store.gd`

1. Raise the profile schema to version 3.
2. Add `run_active` and `selected_sect_id` to defaults, validation, repair, and
   schema-2 migration.
3. Add atomic operations to begin a run, reset a run while preserving unlocks,
   and reset all progress.
4. Verify default-deck restoration and stable ordering of every other unlocked
   card.
5. Run the profile-store suite.

## Task 2: Build the responsive main-menu scene

**Files:**
- Create: `scenes/main_menu.tscn`
- Create: `scripts/main_menu_controller.gd`
- Create: `scripts/main_menu_backdrop.gd`
- Create: `tests/test_main_menu.gd`
- Modify: `tools/run_tests.ps1`

1. Render the complete square background without cropping.
2. Draw responsive decorative extensions outside the square.
3. Add the title, three invisible-panel buttons, and notice label.
4. Implement touch-safe layout and restrained hover/pressed feedback.
5. Implement isolated 5-press and 10-press counters with three-second reset.
6. Expose navigation/reset signals and focused debug observations.
7. Verify labels, thresholds, cancellation, timeout, and layout.

## Task 3: Route the application through the menu

**Files:**
- Modify: `scripts/main_flow_controller.gd`
- Modify: `scripts/sect_selection_controller.gd`
- Modify: `tests/test_main_flow.gd`
- Modify: `tests/test_sect_selection_integration.gd`

1. Start `main.tscn` on the main menu.
2. Route `踏入江湖` to sect selection or deck building from saved run state.
3. Save run activation atomically when a sect is confirmed.
4. Return sect selection and deck building to the menu through their back
   requests.
5. Handle confirmed reset requests and completion/failure notices.
6. Preserve duel-to-deck-builder navigation.
7. Verify inactive and active routes plus both reset flows.

## Task 4: Verify the production experience

**Files:**
- Verify all files above

1. Run script-error checks for every changed GDScript.
2. Run focused suites and the complete test runner.
3. Run `git diff --check` and inspect the focused diff.
4. Start the production main scene.
5. Walk the menu, inactive-run route, back navigation, active-run route, and
   reset confirmations.
6. Inspect portrait and wide runtime frames and review diagnostics.
7. Commit only the planned feature files.
