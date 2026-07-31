# Main-Deck Uniqueness and Derived Side Decks

## Goal

Introduce the proper deck rules:

1. the player's five-card main deck cannot contain two cards with the same
   visible name (`glyph`);
2. enemy main decks may contain repeated names and repeated exact card IDs;
3. each owner's side deck is derived from that owner's actual main deck,
   using sect and tier thresholds before retaining only the highest-tier card
   for each glyph.

The rules must preserve the current five-slot deck-building interaction,
profile persistence, independent side-deck shuffling, and unique runtime
identity for every physical card copy.

## Name Identity

Every rule in this feature interprets "same name" as equal `glyph` only.
Sect does not participate in main-deck uniqueness or final side-deck
deduplication.

This differs intentionally from progression's lower-tier namesake unlock rule,
which requires both equal `glyph` and equal sect.

## Player Main Deck

The player main deck always contains exactly five cards with five distinct
glyphs.

### Normal exchange

If the library card's glyph does not occur in the main deck, the existing
two-way exchange remains:

1. the library card enters the chosen deck slot;
2. the displaced deck card enters the original library source slot.

### Same-name version exchange

If the library card's glyph already occurs in another main-deck slot, dropping
it onto a different slot performs a closed three-way rotation:

1. the library card enters the chosen deck slot;
2. the card displaced from the chosen slot enters the old same-name card's
   deck slot;
3. the old same-name card enters the original library source slot.

No empty slot is introduced. The main deck remains five cards and the occupied
library remains compact.

If the chosen deck slot itself contains the old same-name card, the operation
reduces to the normal two-way exchange: the new version enters that slot and
the old version enters the library source slot.

All exchanges are constructed on a copied profile, validated, and saved once.
Invalid indices, an empty library source, an invalid source profile, or a save
failure return the original profile unchanged.

After any successful exchange, the deck-building controller refreshes all five
player slots because a three-way rotation can change two positions.

## Player Profile Validation and Repair

Profile validation rejects a player main deck containing repeated glyphs.
This restriction does not apply to enemy definitions.

When an older save contains repeated player glyphs, repair:

1. groups current main-deck cards by glyph;
2. retains the highest-tier version of each glyph in its original slot;
3. for an equal-tier tie, retains the earliest deck occurrence;
4. removes the other same-name cards temporarily;
5. fills each vacant deck slot from the existing library order, choosing the
   first unlocked card whose glyph is not already in the repaired deck;
6. removes those selected fillers from the library; and
7. appends the removed duplicate deck cards to the occupied library bottom in
   their original deck order.

If five unlocked cards with distinct glyphs cannot be assembled, repair falls
back to the normal valid default profile.

No schema field is added, but profile validity changes. Loading a previously
valid duplicate-name player deck therefore repairs and saves it once.

## Enemy Main Decks

Enemy definitions still require exactly five known catalog IDs. They no longer
reject:

- two cards with the same glyph;
- different-tier versions of one glyph; or
- multiple exact copies of one card ID.

Each main-deck occurrence creates a fresh runtime card instance, so exact
copies receive distinct `instance_id` values.

Existing enemy-deck signature validation remains otherwise unchanged.

## Side-Deck Construction

The same pure construction rule applies independently to the player's saved
main deck and the current enemy's catalog deck.

The complete card catalog supplies candidates, regardless of player unlock
ownership.

### Candidate collection

For every main-deck card:

1. ignore an unknown card ID defensively;
2. read its sect and tier;
3. if its sect is `江湖`, contribute no candidates, including not the main card
   itself;
4. otherwise, include every catalog card with the same sect and tier less than
   or equal to the main card's tier.

Candidate sets are merged. Multiple main cards from one sect are equivalent to
the highest tier threshold contributed for that sect. Duplicate exact cards in
an enemy main deck do not multiply side-deck copies.

### Highest-tier glyph retention

After candidate collection:

1. group eligible candidates by `glyph`;
2. retain the highest-tier candidate in each group;
3. when eligible candidates share both glyph and highest tier, retain the
   earliest one in card-catalog order; and
4. return retained IDs in card-catalog order.

The result contains at most one card per glyph.

### Runtime integration

`DuelController` obtains the player and enemy main-deck ID arrays first, then
asks `DuelDecks` to derive one side-deck ID array for each owner. It creates a
fresh runtime instance for every retained ID and applies the existing
independent side-deck shuffle.

Opponent-hand shuffling does not affect the derived candidate set because side
deck construction is order-independent before its catalog-order output.

An empty derived side deck is valid. Existing draw behavior stops when no card
can be drawn.

## Architecture

A new pure `deck_rules.gd` module is the single authority for:

- catalog glyph lookup;
- player-main-deck glyph uniqueness;
- same-name exchange planning;
- duplicate-name player-deck normalization; and
- side-deck derivation.

`deck_profile_store.gd` delegates validation, repair, and exchange construction
to these rules while retaining persistence and atomic-save ownership.

`deck_builder_controller.gd` retains gesture handling and presentation, but
refreshes every player hand slot after a successful exchange.

`enemy_catalog.gd` retains enemy metadata validation while allowing duplicate
deck entries.

`duel_decks.gd` retains profile and enemy main-deck lookup and delegates derived
side-deck construction to `deck_rules.gd`.

`duel_controller.gd` passes the actual owner-specific main-deck lists instead
of requesting the former global all-catalog side pool.

No side-deck IDs are persisted. They remain derived data, so catalog metadata
and main-deck changes cannot leave stale side-deck saves.

## Verification

Pure deck-rule tests cover:

- distinct and repeated player glyphs;
- normal two-way exchange planning;
- direct same-slot version replacement;
- three-way rotation with no empty slot;
- repair retaining the highest-tier deck version;
- equal-tier repair ties retaining the earliest deck occurrence;
- stable library filler and removed-card ordering;
- sect/tier candidate thresholds;
- overlapping thresholds from multiple main cards;
- full-catalog inclusion regardless of unlocks;
- `江湖` contributing nothing;
- highest-tier glyph retention;
- equal-tier ties retaining the earliest catalog entry;
- final catalog ordering; and
- duplicate enemy main entries not multiplying side-deck cards.

Profile and deck-builder tests cover validation, repair persistence, visual
refresh of both changed deck slots, and atomic rollback.

Enemy-catalog tests prove exact duplicate IDs are accepted while unknown IDs
and non-five-card decks still fail.

Duel integration tests prove:

- player and enemy side decks derive from their respective main decks;
- different main decks can produce different side decks;
- both side decks still shuffle deterministically under a fixed seed;
- main and side physical cards have distinct runtime instance IDs; and
- repeated exact enemy main cards become separate runtime instances.
