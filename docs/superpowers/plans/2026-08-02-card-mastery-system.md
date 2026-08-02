# Card Mastery System Implementation Plan

**Goal:** Persist exact-card mastery after qualifying player hand plays followed
by victory, and use mastery instead of randomness for revealed library/reward
card colors.

**Design:** `docs/superpowers/specs/2026-08-02-card-mastery-system-design.md`

## Task 1: Add schema-8 mastery persistence

**Files**

- Modify: `scripts/deck_profile_store.gd`
- Modify: `tests/test_deck_profile_store.gd`

**Steps**

1. Add failing tests asserting that a default profile uses schema 8, contains
   an empty `mastered_card_ids`, exposes a typed mastery accessor, rejects
   malformed/duplicate mastery data, and repairs unknown/duplicate IDs in
   stable first-occurrence order.
2. Add a schema-7 active-run migration fixture and assert that upgrading adds
   empty mastery while preserving the active run, sect, level, enemy, deck,
   unlocks, memory, pending reward, history, and best scores. Keep the existing
   older-schema active-run closure assertions.
3. Raise `SCHEMA_VERSION` to 8. Add `mastered_card_ids` to default creation,
   validation, repair, and returned profile dictionaries. Separate the
   reconstructable schema-7 upgrade path from older legacy migration behavior.
4. Add `get_mastered_card_ids(profile)` and `is_card_mastered(profile, card_id)`
   accessors.
5. Run:

   ```powershell
   & "$env:LOCALAPPDATA\SummerEngine\current\Summer.exe" --headless --path C:\mygame --script res://tests/test_deck_profile_store.gd
   ```

## Task 2: Merge mastery into the atomic victory transaction

**Files**

- Modify: `scripts/deck_profile_store.gd`
- Modify: `tests/test_deck_profile_store.gd`
- Modify: `tests/test_ending_profile.gd`

**Steps**

1. Add failing transaction tests for an ordinary victory with ordered,
   duplicate, unknown, and non-main-deck candidates. Assert that only valid
   current-main-deck IDs append, existing mastery remains stable, and defeat
   adds none.
2. Extend `record_completed_duel_and_save()` with an optional mastery-candidate
   argument. Filter it against catalog IDs and the profile's current main deck,
   then merge only for `REWARD_VICTORY` before the single save.
3. Assert save failure returns the unchanged profile and persists no partial
   mastery.
4. Add final-victory coverage proving mastery is recorded before the closed-run
   profile is built and remains present after run closure.
5. Extend reset coverage: `reset_run_and_save()` preserves mastery;
   `reset_all_progress_and_save()` clears it through the default profile.
6. Run the profile and ending-profile suites.

## Task 3: Track qualifying hand plays in the live duel

**Files**

- Modify: `scripts/duel_controller.gd`
- Modify: `tests/test_duel_integration.gd`

**Steps**

1. Add failing integration tests for the candidate boundary:
   - a successful player play of a starting main-deck ID records that ID;
   - repeated plays deduplicate;
   - a newly created or drawn exact-ID copy qualifies;
   - a same-glyph, different-ID card does not qualify;
   - opponent plays, activation, and invalid plays add nothing.
2. Snapshot the player's exact main-deck IDs before runtime instances are
   created. Store an ordered candidate list plus membership sets in
   `DuelController`; keep them outside `DuelState`.
3. After `Simulator.apply_action()` returns a valid player `TYPE_PLAY`
   transition, read the played card's exact ID and record it when eligible.
   Record before later presentation/removal so subsequent effects cannot erase
   the achievement candidate.
4. Expose `get_mastery_candidate_ids()` as a read-only duplicate plus a focused
   debug accessor if tests require it.
5. Run `test_duel_integration.gd` and `test_duel_search.gd` to prove the
   meta-progression tracking does not alter search.

## Task 4: Wire candidates through the main flow

**Files**

- Modify: `scripts/main_flow_controller.gd`
- Modify: `tests/test_main_flow.gd`
- Modify: `tests/test_ending_flow.gd`

**Steps**

1. Add failing flow cases for victory, defeat, abandonment, and final victory.
2. In `_on_duel_return_requested()`, read mastery candidates from the current
   duel before any screen replacement. Pass them to
   `record_completed_duel_and_save()` only when the reported outcome is
   victory.
3. Preserve compatibility with tests or callers that emit the existing
   one-argument `return_requested(outcome)` signal directly; such calls simply
   yield an empty candidate list unless the current duel has recorded plays.
4. Assert ordinary victory shows persisted mastery in the following reward and
   deck-builder profile, defeat/abandon add none, and final victory preserves
   mastery in the closed profile.
5. Run `test_main_flow.gd` and `test_ending_flow.gd`.

## Task 5: Make deck-builder library colors mastery-driven

**Files**

- Modify: `scripts/deck_builder_controller.gd`
- Modify: `tests/test_deck_builder_integration.gd`

**Steps**

1. Replace seeded-random occupied-library assertions with fixtures containing
   mastered and unmastered exact IDs.
2. Replace `_roll_library_display_owners()` with a deterministic refresh that
   assigns player/blue to mastered IDs and opponent/red to unmastered IDs.
   Leave empty slots on their existing neutral path.
3. Recompute the mapping after profile exchanges while preserving logical-slot
   alignment.
4. Assert library drag proxies retain the source slot's mastery color and that
   enemy hand reveal remains opponent/red in testing mode.
5. Remove the obsolete `library_color_seed` export and test setup.
6. Run `test_deck_builder_integration.gd` and
   `test_deck_library_grid.gd`.

## Task 6: Make revealed reward colors mastery-driven while preserving random backs

**Files**

- Modify: `scripts/reward_selection_controller.gd`
- Modify: `tests/test_reward_selection_integration.gd`

**Steps**

1. Create a reward fixture with at least one mastered offered exact ID and one
   unmastered offered exact ID. Assert blue/red revealed colors respectively.
2. Split display-owner generation so revealed rewards use mastery and unused
   face-down placeholders retain the existing seeded independent random roll.
3. Preserve `reward_color_seed` for deterministic placeholder tests.
4. Assert reward drag proxies preserve source mastery color and revealed enemy
   hand cards remain red in testing mode.
5. Run `test_reward_selection_integration.gd` and
   `test_deck_library_grid.gd`.

## Task 7: Update durable documentation

**Files**

- Modify: `docs/HANDOFF.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/DECISIONS.md`
- Modify: `docs/TESTING.md`

**Steps**

1. Document schema 8, global exact-ID mastery, qualifying copy semantics,
   victory-only atomic persistence, reset behavior, and deterministic revealed
   library/reward colors.
2. Update testing-suite descriptions and migration cautions.
3. Search for stale statements claiming library/reward occupied cards are
   randomized and correct only current-source documentation, not historical
   specs/plans.

## Task 8: Verify the complete feature

1. Run focused suites after each task, then run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
   ```

2. Require every suite's `_PASSED` marker, exit code zero, and no `ERROR:`,
   `SCRIPT ERROR`, `_FAILED`, or `CHECK_FAILED` text.
3. Run `git diff --check` and inspect `git status --short` for unrelated files.
4. Launch the production main flow in Summer Engine at the portrait reference
   viewport. Start/resume a run, put an unmastered card in the main deck, play
   an exact-ID copy, win, press return, and verify the card is blue in the
   reward/library flow. Also verify an unmastered revealed card is red, reward
   placeholder backs retain both possible colors under controlled seeds, and
   revealed enemy-hand cards remain red.
5. Read fresh diagnostics, console, and debugger output. Stop the game after
   verification.
6. Commit the implementation in focused local commits; do not push.
