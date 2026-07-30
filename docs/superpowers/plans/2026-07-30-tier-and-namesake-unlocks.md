# Tier and Namesake Unlocks Implementation Plan

**Spec:** `docs/superpowers/specs/2026-07-30-tier-and-namesake-unlocks-design.md`

## Objective

Centralize card-unlock expansion in `DeckProfileStore`, automatically unlock
the selected sect's cards when the player crosses a character-tier boundary,
and append newly inherited lower-tier namesakes to the bottom of the library.

## Constraints

- Character tier remains capped at 5; level 15 is still tier 5.
- Primary unlocks keep their existing top-of-library behavior.
- Namesake matching requires equal `glyph` and equal `sect`, with a strictly
  lower tier.
- Existing valid saves do not gain cards during load or repair.
- Progression, unlock placement, profile validation, and saving are atomic.
- Current public success/failure behavior remains compatible:
  single invalid or duplicate unlocks fail, while batch no-ops succeed.

## Task 1: Establish unlock-expansion tests

**Files**

- Modify `tests/test_deck_profile_store.gd`

Add focused fixtures that create valid profiles with selected family members
intentionally locked without changing the catalog.

Add tests proving:

1. directly unlocking a high-tier card adds that primary card at library index
   zero;
2. its still-locked lower-tier cards with the same `glyph` and sect are
   appended after the previously occupied library;
3. inherited cards preserve catalog order;
4. an explicitly requested card remains primary even if another requested card
   could inherit it;
5. already unlocked, equal-tier, higher-tier, and same-glyph/different-sect
   cards are not inherited;
6. repeated primary IDs and overlapping cascades never duplicate ownership;
7. single unlock, batch unlock, sect-start, and reward-claim paths all use the
   same cascade behavior;
8. loading and repairing an existing valid profile do not apply a cascade.

Run `test_deck_profile_store.gd` and confirm the new assertions fail for the
expected missing behavior before implementation.

## Task 2: Add one pure unlock-expansion primitive

**Files**

- Modify `scripts/deck_profile_store.gd`

Add an internal helper that accepts a valid profile and ordered requested
primary IDs, then returns:

- ordered, distinct, still-locked primary additions;
- ordered, distinct inherited additions discovered by scanning
  `Catalog.get_all_card_ids()`;
- the resulting padded library;
- the resulting unlocked-card ID list; and
- a success flag plus combined `added_ids`.

Keep the `glyph`/sect/lower-tier comparison in a small pure predicate so tests
can cover coincidental same-glyph cards from different sects with synthetic
definitions even though the current catalog has no such pair.

Expansion rules:

1. collect all primaries before searching for inherited cards;
2. exclude existing ownership and every primary from inheritance;
3. compare catalog definitions by `glyph`, `sect`, and numeric tier;
4. scan inherited candidates in catalog order;
5. place cards as
   `primary + occupied library + inherited`;
6. reject results beyond `LIBRARY_CAPACITY`;
7. do not save or mutate the caller's profile inside the helper.

Keep single-unlock input validation outside the helper so unknown or duplicate
single unlocks retain their current failure behavior.

## Task 3: Route every unlock path through the primitive

**Files**

- Modify `scripts/deck_profile_store.gd`
- Extend `tests/test_deck_profile_store.gd`

Replace the duplicated library/unlocked-array construction in:

- `unlock_and_save`;
- `unlock_cards_and_save`;
- `begin_run_and_save`; and
- `claim_pending_reward_and_save`.

Each public method should:

1. validate its operation-specific preconditions;
2. duplicate the original profile;
3. apply the pure unlock result to that candidate;
4. apply any operation-specific state change, such as clearing pending rewards;
5. validate the complete candidate;
6. save once; and
7. return the original profile unchanged on failure.

Return all newly owned cards in `added_ids`, with primaries first and inherited
cards second. Existing callers that only inspect membership or emptiness remain
compatible.

Run the profile-store suite after each path is migrated.

## Task 4: Add automatic sect-tier progression

**Files**

- Modify `scripts/deck_profile_store.gd`
- Extend `tests/test_deck_profile_store.gd`

Add a catalog-order helper that resolves the selected sect's display `glyph`
from `SectCatalog`, then returns card IDs whose `sect` matches that glyph and
whose tier exactly matches the requested character tier.

In `advance_after_victory_and_save`:

1. calculate current level/tier and next level/tier;
2. select the next enemy as today;
3. if the next tier is higher, collect the exact-tier sect cards;
4. apply the unlock primitive to the same candidate profile;
5. update level, enemy, and remembered glyphs;
6. validate and save the complete candidate once.

Add boundary tests for levels 2, 5, 8, and 11, plus non-boundary victories and
level 15. Verify that:

- only the selected sect and exact new tier unlock;
- cards appear at the top in catalog order;
- lower-tier namesakes appear at the bottom;
- a failed save leaves level, enemy, and ownership unchanged; and
- tier 5 remains the maximum.

## Task 5: Verify reward ordering through the main flow

**Files**

- Modify `tests/test_main_flow.gd` if its existing test harness can express the
  boundary cleanly; otherwise add the assertion to
  `tests/test_deck_profile_store.gd`.

Construct a profile one victory below a tier boundary, advance it, then create
the reward offer. Verify automatically unlocked sect-tier cards are absent from
the candidates because progression saved them first.

No controller sequencing change should be necessary:
`main_flow_controller.gd` already advances victory progression before calling
`create_reward_offer_and_save`.

## Task 6: Update maintainer documentation

**Files**

- Modify `docs/ADDING_CARDS_AND_ABILITIES.md`
- Modify `docs/ARCHITECTURE.md`
- Modify `docs/DECISIONS.md`
- Modify `docs/HANDOFF.md`

Document:

- tier-boundary sect unlocks;
- same-name matching by both `glyph` and sect;
- primary-top/inherited-bottom ordering;
- atomic persistence;
- no retroactive repair-time cascade; and
- tier 5 as the current cap through level 15.

## Task 7: Final verification

1. Run script-error checks on `deck_profile_store.gd` and changed tests.
2. Run `test_deck_profile_store.gd`.
3. Run `test_main_flow.gd`.
4. Run deck-builder, sect-selection, reward-selection, and reward-profile
   integration suites for regression coverage.
5. Run the complete test runner and distinguish any pre-existing failures from
   new regressions.
6. Run `git diff --check`.
7. Inspect the exact diff and repository status.
8. Commit the implementation and tests without pushing.
