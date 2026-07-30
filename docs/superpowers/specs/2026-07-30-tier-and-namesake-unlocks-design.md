# Tier and Namesake Unlocks

## Goal

Extend run progression with two automatic card-unlock rules:

1. reaching a new character tier unlocks every card of that exact tier from the
   player's selected sect;
2. unlocking a card also unlocks any still-locked, lower-tier versions with the
   same `glyph` and sect.

The rules must preserve the library's existing visual ordering conventions and
must save as one atomic profile change.

## Approved Rules

### Character tiers

Character tier remains capped at tier 5:

- level 0 or 1: tier 1;
- levels 2 through 4: tier 2;
- levels 5 through 7: tier 3;
- levels 8 through 10: tier 4;
- levels 11 through 15: tier 5.

Level 15 does not introduce tier 6.

### Sect-tier unlocks

When a victory advances the character across a tier boundary, the profile store
collects every catalog card whose:

- `sect` equals the selected sect's `glyph`; and
- `tier` equals the newly reached character tier.

These exact-tier cards are primary unlocks. They are inserted at the top of the
library in card-catalog order. A victory that does not change character tier
does not perform this automatic unlock.

The tier unlock is applied and saved as part of the same transaction as the
level and next-enemy advancement. It occurs before reward candidates are
generated, so automatically unlocked cards cannot also appear in the following
reward offer.

Starting a run continues to unlock every tier-1 card of the selected sect.

### Lower-tier namesake unlocks

Every explicit unlock path expands its primary unlocks before saving. For each
new primary card, the profile store finds all still-locked cards that:

- have the same `glyph`;
- have the same `sect`; and
- have a strictly lower `tier`.

Matching both `glyph` and sect prevents unrelated cards with coincidentally
identical names from unlocking one another. Equal-tier and higher-tier cards
are never inherited.

Inherited lower-tier cards are appended after every card currently occupying
the library, in card-catalog order. They are not inserted beside the primary
card and do not displace existing library order.

The rule applies to all unlock sources, including:

- a single direct unlock;
- a batch unlock;
- starting a run through sect selection;
- claiming a reward; and
- automatic sect-tier progression.

Already unlocked cards and duplicate candidates are ignored.

## Architecture

`deck_profile_store.gd` remains the sole owner of persistent unlock behavior.
It gains one internal unlock-expansion and placement operation that receives an
ordered list of requested primary card IDs and produces two ordered groups:

- `primary_additions`: valid, distinct, still-locked requested cards;
- `inherited_additions`: valid, distinct, still-locked lower-tier namesakes.

Primary order follows the caller's order. Tier progression supplies cards in
catalog order. Inherited order always follows catalog order.

The operation constructs the occupied library as:

`primary_additions + existing_library + inherited_additions`

It updates the unlocked-card collection consistently with those additions,
validates the complete candidate profile, and saves only once.

The existing public unlock methods retain their roles but delegate their
ordering and cascade behavior to this shared operation. Profile loading and
repair do not invoke the cascade, so merely opening an older valid save never
grants new cards or changes its library order.

`advance_after_victory_and_save` compares the current and next character tiers.
When the next tier is greater, it resolves the selected sect, gathers that
tier's cards, applies the shared unlock operation to the same candidate profile,
then updates the level, enemy, and remembered-card state before the single
save.

## Failure Handling

The unlock and progression changes are atomic:

- a single direct unlock still rejects an unknown card ID, while batch
  collection ignores unknown entries, preserving the current public APIs;
- an invalid source profile rejects the operation without mutation;
- if all requested cards are already unlocked, the operation is a successful
  no-op;
- if the resulting library exceeds its 1,000-slot capacity, the entire
  operation fails;
- if validation or saving fails, the original profile is returned unchanged;
- a failed tier-unlock transaction also prevents that victory's level and enemy
  advancement from being persisted.

Pending reward cards remain excluded from the unlocked set until one is
claimed. Claiming a reward clears the pending offer only if the complete unlock
transaction succeeds.

## Verification

Profile-store tests will cover:

- each tier boundary at levels 2, 5, 8, and 11;
- non-boundary victories and level 15 producing no tier change;
- exact-tier and selected-sect filtering;
- catalog ordering of automatic tier unlocks;
- primary cards inserted at the top;
- inherited lower-tier namesakes appended at the bottom;
- same-glyph cards from another sect remaining locked;
- equal-tier and higher-tier namesakes remaining locked;
- duplicate and already-unlocked suppression across multiple primaries;
- single, batch, sect-start, reward, and progression unlock paths;
- automatic tier cards being excluded from the subsequent reward pool;
- full-library and save failures leaving the profile unchanged; and
- loading or repairing an existing profile not retroactively applying unlocks.

The main-flow integration test will verify that victory advancement completes
the tier unlock before reward selection is shown.
