# Card Catalog and Exile-on-Flip Effect Design

**Date:** 2026-07-19  
**Status:** Approved for implementation planning

## Purpose

Move card definitions out of `duel_controller.gd` into a dedicated, data-driven catalog and add the first extensible special effect: when Tiger General or Gate General would flip an enemy card, that target is exiled instead.

This slice establishes the data and effect-resolution boundaries needed by future deck-building, chained effects, and deep AI search. It does not build the deck-building UI, add other special effects, or replace the current production AI.

## Card Catalog

`scripts/card_catalog.gd` is the sole source of reusable card definitions. Definitions are keyed by stable IDs such as `tiger_general` and `gate_general`. Each definition contains:

- `id`: stable identity used by decks, saves, tests, and simulation.
- `name`: display name.
- `glyph`: current text-based artwork glyph.
- `powers`: top, right, bottom, and left values in existing rules order.
- `effects`: ordered declarative effect descriptors.

An effect descriptor contains an effect ID and `retained_on_flip: bool`. Tiger General and Gate General each declare `exile_instead_of_flip` with `retained_on_flip: true`.

The catalog validates all definitions during development. IDs must be unique and non-empty; powers must contain exactly four integers; effect IDs must be known; and retention must be explicitly declared. Invalid definitions fail fast instead of producing partially functional cards.

Catalog callers receive deep copies. No match logic may mutate the canonical definitions.

## Deck Separation

`scripts/duel_decks.gd` declares the current encounter's player and opponent lists using card IDs only. The duel controller no longer hard-codes names, glyphs, powers, or effects.

This is also the future deck-building boundary: constructed decks will store stable card IDs and quantities, then ask the catalog to create match-local instances. The deck builder itself is outside this implementation slice.

## Match-Local Card Instances

At duel setup, each deck entry becomes a match-local card instance. The instance contains enough pure data for state copying and background AI search:

- A deterministic match-local instance ID.
- The stable catalog card ID.
- Display data and powers copied from the catalog.
- The owner who brought the card into the match (`original_owner`).
- A mutable `active_effects` list copied from the definition.

The immutable catalog describes what a fresh card starts with. The runtime instance records what remains true after effects and ownership changes.

When a normal flip changes ownership, every active effect with `retained_on_flip: false` is removed from that instance permanently. Flipping the card back never restores it. Retained effects remain active for the new owner. The simulator emits an `ability_lost` event for each removed ability so presentation can reflect the state change. Exiling a target does not count as an ownership flip and therefore does not emit `ability_lost` before removal.

## Effect Resolution

The pure simulator remains the authority for all outcomes. Any placement, combo, or future effect that would flip a card produces an `attempt_flip` event with a source card and target card.

`scripts/duel_effects.gd` resolves that attempt against the source card's current `active_effects`. Effects are evaluated in their catalog order. A replacement effect consumes the attempt, so later replacement effects do not also transform the same flip. This produces deterministic results for tests and AI search.

For `exile_instead_of_flip`:

1. Verify the source still has the active effect.
2. Replace the flip with a `card_exiled` event.
3. Append the complete target instance to `removed_cards[target.original_owner]`.
4. Set the target board cell to empty.
5. Award no ownership point for the exiled card.

Every valid target is resolved in the existing canonical direction order: top, right, bottom, left. A single source may therefore exile up to four cards in one resolution. Tiger General and Gate General keep the ability after being flipped because their catalog descriptors declare retention.

Allied cards, empty cells, ties, and weaker edge comparisons never create an `attempt_flip` event.

## Scoring and Match Flow

Scores count only current board ownership. An exiled card counts for neither player, although the newly placed source card still contributes normally.

Exiled cells become immediately legal for future placement. A full board ends the match only when it leaves neither player with a legal move. If the active player cannot move but the opponent can, the active player passes. The match ends when neither player has a legal move and the effect queue is empty. The existing maximum-turn guard remains a safety fallback for future draw, removal, and extra-turn loops.

## Presentation and Feedback

The simulator applies a move atomically and returns ordered transition events. The controller locks input while presenting those events and never recalculates rules.

- **Visual:** The source pulses once. Dark red ink strikes each target in resolution order. Each target shrinks and dissolves without playing the normal ownership-flip animation. The cell is visibly empty when the animation completes.
- **Audio:** A low brush-slash plays on activation, followed by a soft paper-tear for each exiled target.
- **Mechanical:** Cleared cells become selectable, scores refresh before the next turn, and any lost ability is represented by an `ability_lost` presentation event.

The duel scene gains one `RemovalAudio` child. `CardView` gains focused exile and ability-loss presentation methods; it does not gain rule logic.

Presentation tunables remain outside the pure simulator:

- Source pulse duration.
- Exile shrink/dissolve duration.
- Delay between multiple targets.
- Exile ink color.
- Removal audio volume.

## Component Boundaries

```text
Duel
├── BoardGrid                         existing
├── RemovalAudio                      new presentation node
└── CardView instances                exile/ability-loss presentation

scripts/card_catalog.gd               immutable definitions and validation
scripts/duel_decks.gd                  encounter card-ID lists
scripts/duel_effects.gd                pure replacement and retention rules
scripts/duel_rules.gd                  detects valid would-be flips
scripts/duel_simulator.gd              applies moves and ordered effects
scripts/duel_state.gd                  copies runtime cards and removed zones
scripts/duel_controller.gd             consumes transition events
scripts/card_view.gd                   displays runtime card state
```

The rules layer detects comparisons, the effects layer transforms attempts, the simulator mutates a copied logical state, and the controller presents the already-decided transition. This boundary lets greedy AI, alpha-beta search, and future search algorithms observe exactly the same effects as live play.

## Failure Handling

- Unknown card or effect IDs are development errors surfaced by catalog/deck validation.
- An attempt against an empty or allied cell is ignored before effect resolution.
- An already-consumed replacement event cannot be processed twice.
- Presentation checks that the referenced `CardView` still exists; logical state remains authoritative if a visual node is missing.
- Effect-queue and turn limits prevent future recursive effects from hanging a match.

## Verification

Automated tests will cover:

- Catalog uniqueness, required fields, four-power validation, known effect IDs, and explicit retention.
- Deck resolution from IDs without controller-owned card definitions.
- Single-target and four-target exile.
- Canonical top-right-bottom-left event order.
- No exile on allied cards, ties, weaker comparisons, or empty cells.
- Removed-card storage under the target's original owner.
- No score for exiled cards and reuse of emptied cells.
- Retained abilities surviving ownership changes.
- Non-retained abilities being lost permanently, including after a later flip back.
- A previously flipped Tiger General or Gate General still exiling targets.
- Deep-copy isolation for active effects and removed-card zones.
- Greedy and search prototypes evaluating the effect through simulator state.
- Real drag-and-drop and AI placements producing the correct visual board.
- Match continuation after cells reopen and completion when neither side can move.

Final verification requires the full headless rule, simulator, and integration suites plus a manual Summer Engine playthrough that exercises both a player-triggered and opponent-triggered exile.

## Implementation Scope

This implementation will deliver the catalog, encounter deck separation, match-local active effects, retention behavior, exile resolution, presentation hooks, and tests. It will not deliver the future deck builder, additional effect types, full timed deep-search AI, or restoration of permanently exiled cards.
