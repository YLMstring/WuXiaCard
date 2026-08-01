# Ending System Implementation Plan

**Spec:** `docs/superpowers/specs/2026-08-01-ending-system-design.md`

## Objective

End a run after a configurable number of victories, record effective duels and
defeated enemies transactionally, calculate and preserve the best score for
each sect, and present the completed run on a dedicated ending scene that
reuses the main-menu art and title treatment. A tap returns to the ordinary
main menu with the run closed and the default deck restored.

## Task 1: Establish the behavioral baseline

**Files**

- Inspect only

1. Confirm the current worktree state and preserve user-owned changes.
2. Run `tools/run_tests.ps1` and record the known pre-existing failures.
3. Run the profile-store and main-flow suites independently so new ending
   failures can be separated from stale expectations.
4. Do not repair unrelated failing tests as part of this feature.

## Task 2: Add versioned progression and achievement data

**Files**

- Modify `scripts/deck_profile_store.gd`
- Modify focused profile-store tests

Add failing tests for:

- default `effective_duel_count`, `defeated_enemy_ids`, and
  `best_scores_by_sect` fields;
- a defeat incrementing only effective duels;
- a non-final victory incrementing effective duels, appending the current
  enemy, and advancing progression;
- a final victory producing an immutable ending summary, bypassing further
  enemy selection, resetting the run/default deck, and preserving unlocks;
- `floor(15000 / effective_duel_count)` scoring;
- best-score-per-sect insertion, improvement, and non-regression;
- run reset preserving achievements and full reset clearing them; and
- migration of legacy active runs by closing the run while preserving unlocks.

Bump the profile schema and introduce one atomic completed-duel operation.
Return a structured result containing success, the saved profile, completion
state, and ending summary. Save once after all related mutations. Keep abandon
outside this operation so it changes no counters.

## Task 3: Build the ending presentation

**Files**

- Add `scripts/ending_controller.gd`
- Add `scenes/ending.tscn`
- Add `tests/test_ending_scene.gd`
- Modify `tools/run_tests.ps1`

Instance the existing main-menu scene as the visual foundation. Hide its three
actions and normal notice, retain the exact background, title, glow, breathing,
and responsive framing, then add:

- a score line below the title;
- a longer Chinese story paragraph below the score; and
- a full-screen tap target that emits a return request.

Build prose from pure summary data. Resolve the selected sect display name and
every defeated enemy name in chronological order. Use the flawless sentence
only when the completed run has no losses; otherwise use the comeback sentence.
Use the project's existing Chinese line-breaking safeguards so punctuation is
not stranded at the beginning of a line.

Test summary rendering, all enemy names in order, flawless/loss branches,
hidden menu actions, responsive layout, and tap-to-return.

## Task 4: Integrate final-victory routing

**Files**

- Modify `scripts/main_flow_controller.gd`
- Modify `tests/test_main_flow.gd`

Expose a tweakable victory target with a default of 15. On duel return:

1. abandon returns directly to deck building without recording a duel;
2. defeat records one effective duel and opens the lower-tier reward;
3. ordinary victory records the duel, advances, and opens the normal reward;
4. final victory records completion and opens the ending directly, with no
   reward scene; and
5. save failure opens neither reward nor ending and returns safely to deck
   building with a warning.

Connect the ending scene's return request to the ordinary main menu. Confirm
that `踏入江湖` starts sect selection after a completed run because `run_active`
has already been cleared.

Add a threshold-one integration test so the entire final-victory path can be
proved without playing fifteen duels.

## Task 5: Update project documentation

**Files**

- Modify `docs/ARCHITECTURE.md`
- Modify `docs/DECISIONS.md`
- Modify `docs/HANDOFF.md`
- Modify `docs/TESTING.md`

Document the new scene, persisted fields, atomic duel-completion boundary,
score formula, final-victory routing, migration behavior, and focused test
commands. Keep the approved design spec as the detailed source of truth.

## Task 6: Verify and playtest

1. Run each new or modified focused suite until it passes.
2. Run `tools/run_tests.ps1` and confirm there are no new failures beyond the
   recorded baseline.
3. Launch the game with a one-victory test threshold.
4. Play through sect selection, deck building, a completed duel, ending
   presentation, and tap-to-main-menu.
5. Verify the reward scene is skipped, the score/story are readable at the
   portrait reference size, the run is closed, the default deck is restored,
   and the best sect score remains after returning to the menu.
6. Restore the production threshold to 15 and commit the completed feature.
