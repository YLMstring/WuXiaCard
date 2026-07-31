# Main-Deck and Side-Deck Rules Implementation Plan

**Spec:** `docs/superpowers/specs/2026-07-31-main-and-side-deck-rules-design.md`

## Objective

Enforce unique player main-deck glyphs, allow exact duplicate enemy cards, and
derive each owner's side deck from that owner's actual main deck using sect,
tier, and highest-tier-per-glyph rules.

## Task 1: Add pure deck-rule tests

**Files**

- Add `tests/test_deck_rules.gd`
- Modify `tools/run_tests.ps1`

Create focused tests for:

- glyph lookup and player-deck uniqueness;
- normal two-way exchange;
- direct same-name version replacement;
- three-way rotation with the selected card, displaced card, and old version in
  their approved destinations;
- no gap or card loss after any exchange;
- normalization retaining the highest-tier deck version;
- equal-tier normalization retaining the earliest occurrence;
- stable library filler order and removed-duplicate bottom order;
- side thresholds per sect;
- overlapping thresholds collapsing to the maximum tier per sect;
- full-catalog eligibility independent of unlock ownership;
- `江湖` contributing nothing;
- highest-tier candidate retention per glyph;
- equal-tier ties retaining the earliest catalog entry;
- final catalog ordering; and
- duplicate main entries not multiplying side-deck entries.

Add small pure predicate/comparison seams for synthetic `江湖`,
same-glyph/different-sect, and equal-tier-tie fixtures not represented by the
current catalog.

Run the new suite first and record the expected missing-script failure.

## Task 2: Implement `deck_rules.gd`

**Files**

- Add `scripts/deck_rules.gd`

Implement typed static helpers:

- safe catalog definition/glyph lookup;
- `has_unique_glyphs(card_ids)`;
- pure player exchange construction from copied main/library arrays;
- pure player placement normalization from unlocked IDs, preferred deck slots,
  and preferred library order;
- side-deck derivation from arbitrary main-deck IDs;
- candidate eligibility and best-candidate comparison predicates.

Side-deck derivation should:

1. compute the greatest contributed tier for each non-`江湖` sect;
2. scan catalog IDs in catalog order for eligible candidates;
3. retain the greatest tier per glyph without replacing equal-tier earlier
   entries; and
4. scan catalog order again to produce retained IDs.

No helper saves data or creates runtime card instances.

Run `test_deck_rules.gd` until it passes.

## Task 3: Enforce and repair player main-deck uniqueness

**Files**

- Modify `scripts/deck_profile_store.gd`
- Modify `tests/test_deck_profile_store.gd`

In validation, reject repeated nonempty glyphs in the five-card player deck.

In repair, delegate player deck/library placement to `DeckRules` after
sanitizing unlocked IDs. Preserve highest-tier winners in their original deck
slots, fill gaps from stable library order with unused glyphs, append removed
duplicate deck cards at the library bottom, and fall back to the default
profile if five unique glyphs cannot be assembled.

Add migration/repair tests with:

- lower- and higher-tier versions in different slots;
- equal-tier synthetic ordering through the pure helper;
- multiple duplicate glyph groups;
- library fillers that would themselves repeat a retained glyph; and
- insufficient distinct glyphs causing a valid fallback.

Run the profile-store suite.

## Task 4: Implement atomic two-way and three-way exchanges

**Files**

- Modify `scripts/deck_profile_store.gd`
- Extend `tests/test_deck_profile_store.gd`

Replace the direct two-element assignment in `exchange_and_save` with the pure
exchange result.

Verify:

- incoming absent glyph uses the current two-way swap;
- incoming glyph in the target slot replaces that version directly;
- incoming glyph in another slot performs the three-way rotation;
- the library source receives the old same-name version;
- main deck and occupied library stay the same sizes;
- profile validation passes after successful exchanges; and
- save failure returns the exact original profile.

## Task 5: Refresh every affected deck-builder slot

**Files**

- Modify `scripts/deck_builder_controller.gd`
- Modify `tests/test_deck_builder_integration.gd`

After any successful library-to-main exchange, refresh all five player slots,
the virtual library, and first-player eligibility. This avoids stale visuals
when the three-way rotation changes a second deck slot.

Add an integration case that drags a higher version onto a different slot and
checks both changed hand views plus the library source.

## Task 6: Allow enemy duplicates

**Files**

- Modify `scripts/enemy_catalog.gd`
- Modify `tests/test_enemy_catalog.gd`

Remove only the per-definition repeated-card rejection. Preserve:

- exactly five entries;
- known card IDs;
- valid enemy name and level; and
- existing cross-enemy deck-signature policy.

Add fixtures proving repeated exact IDs and repeated glyphs are accepted while
unknown IDs and incorrect deck sizes still fail.

## Task 7: Derive owner-specific side decks

**Files**

- Modify `scripts/duel_decks.gd`
- Modify `scripts/duel_controller.gd`
- Modify `tests/test_card_catalog.gd`
- Modify `tests/test_duel_integration.gd`

Change `DuelDecks.get_side_deck_card_ids` to require main-deck IDs and delegate
to `DeckRules`.

In `DuelController._ready`:

1. retain the actual player main-deck ID array;
2. retain the effective enemy main-deck ID array, including duplicates;
3. create main-hand runtime cards from those arrays;
4. derive player and enemy side IDs separately;
5. create fresh side runtime instances; and
6. apply the existing independent shuffles.

Update tests that currently expect every catalog card in both side decks.
Assert derived expected IDs separately for each owner, deterministic shuffle
under fixed seeds, and unique runtime instance IDs across main and side zones.

Add an integration fixture with exact duplicate enemy main cards and verify the
hand contains separate runtime instances while its side deck still contains at
most one retained card per glyph.

## Task 8: Update maintainer documentation

**Files**

- Modify `docs/ADDING_CARDS_AND_ABILITIES.md`
- Modify `docs/ARCHITECTURE.md`
- Modify `docs/DECISIONS.md`
- Modify `docs/HANDOFF.md`

Document player glyph uniqueness, enemy duplicate freedom, three-way exchange,
legacy repair, owner-specific derived side decks, `江湖`, highest-tier glyph
retention, and the fact that player unlock ownership does not limit side-deck
candidates.

## Task 9: Verification

1. Check script errors for all changed GDScript files.
2. Run `test_deck_rules.gd`.
3. Run profile-store, enemy-catalog, card-catalog, deck-builder, duel simulator,
   and duel integration suites.
4. Run the full test runner and separate known stale baseline failures from new
   regressions.
5. Boot the main scene and walk a production deck exchange into a duel.
6. Verify both owner side decks and duplicate enemy runtime IDs through the
   production scene's debug hooks.
7. Read runtime diagnostics and console output.
8. Run `git diff --check`, inspect the exact diff, and commit without pushing.
