# Card Catalog Metadata Implementation Plan

## Objective

Replace production `name` data with a 1–7 character `glyph` title, add future-facing card metadata, and render titles vertically in top-to-bottom then left-to-right order without changing duel behavior or re-enabling tooltips.

## Task 1: Catalog contract and validation

**Files:** `scripts/card_catalog.gd`, `tests/test_card_catalog.gd`

1. Update every production definition to remove `name` and add required `sect`, `tier`, `weapon`, `description`, and `flavor` fields.
2. Copy the new fields, plus `glyph`, into every production runtime instance.
3. Validate that `glyph` is a String of 1–7 characters, the four text metadata fields are Strings, `tier` is an integer of at least 1, and retired `name` is absent.
4. Extend catalog tests to cover the new definition/runtime contract, boundary glyph lengths, invalid field types, invalid tiers, and copy isolation.

## Task 2: Production consumers

**Files:** `scripts/duel_simulator.gd`, `tests/test_duel_simulator.gd`, `tests/test_duel_integration.gd`

1. Derive a fixture card's fallback `card_id` from `glyph` rather than `name`.
2. Change production-instance isolation and concealed-hand assertions to use `glyph` and metadata.
3. Preserve the fixture-only `DuelRules.make_card` name argument so unrelated simulator fixtures do not need a broad migration.
4. Preserve the user's disabled card-tooltip behavior and update the stale reveal assertion accordingly.

## Task 3: Vertical multi-character card titles

**Files:** `scripts/card_view.gd`, `tests/test_duel_integration.gd`

1. Add a deterministic title formatter: 1–4 characters form one vertical column; 5–7 form two balanced columns, with input consumed down the left column and then down the right.
2. Render the formatted title only for face-up cards; keep the existing face-down diamond unchanged.
3. Calculate title font size from the card's available width, height, row count, and column count so all supported titles remain centered and legible across hand and board card sizes.
4. Add integration checks for one-, four-, five-, and seven-character ordering and for face-down/reveal behavior.

## Task 4: Verification

1. Run catalog, rules, simulator, search, and integration test suites headlessly.
2. Run the project and visually inspect representative one-column and two-column titles in portrait layout.
3. Confirm no unexpected debugger errors and review the final diff for unrelated changes.
4. Commit the completed feature as one implementation checkpoint.
