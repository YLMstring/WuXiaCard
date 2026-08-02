# Card Mastery System Design

## Summary

Add a persistent, global achievement for mastering exact catalog cards. A card
is mastered when its exact ID was present in the player's main deck at duel
start, the player successfully played any hand copy of that exact ID during
the duel, and the duel ended in victory. Mastery determines the red/blue face
color of revealed cards in the deck-builder library and reward selection.

## Mastery Rule

At duel start, snapshot the five exact player main-deck card IDs. Whenever a
legal player play action successfully places a card from hand, compare that
card's exact `card_id` with the snapshot. A match adds the ID to a duel-local,
ordered, deduplicated mastery-candidate list.

The played instance does not need to be the original starting-hand instance.
An identical side-deck copy or freshly created copy qualifies when its exact ID
was in the starting main deck. A card that only shares the same `glyph`, sect,
or tier does not qualify when its catalog ID differs.

Only victory awards the recorded candidates. Defeat and abandonment discard
them. Ordinary and final victories both award mastery. A qualifying card still
counts if it is later flipped, moved, exiled, or otherwise leaves the board.
Activating a board card does not count as playing it from hand.

## Persistent Profile Data

Advance the profile schema from 7 to 8 and add:

```gdscript
"mastered_card_ids": []
```

The field is an ordered, deduplicated list of exact catalog IDs. It is global
progress and is independent of whether a card is currently unlocked.

- Normal run completion preserves mastery.
- `闭关重修` preserves mastery.
- `封剑归隐` restores the default profile and therefore clears mastery.
- A new profile starts with no mastered cards.

Schema-7 profiles migrate in place with an empty mastery list. A schema-7
active run keeps its selected sect, level, enemy, deck, unlocks, duel history,
enemy memory, pending reward, and best scores. Older legacy profiles retain
their existing migration behavior, including closing active runs whose history
cannot be reconstructed.

Profile validation accepts only catalog-known string IDs and rejects duplicate
mastery entries. Repair filters unknown and duplicate IDs while preserving the
first valid occurrence. Mastery does not require membership in
`unlocked_card_ids`.

## Runtime Ownership and Data Flow

Mastery is meta-progression, not a duel rule. It does not enter `DuelState`,
affect legal actions, change card behavior, or influence AI search.

`DuelController` owns the live duel snapshot and candidate list. After a legal
player hand-play succeeds, it records the played card ID when that ID appears
in the starting main-deck snapshot. It exposes a read-only copy of the ordered
candidate IDs.

When the duel return icon reports an outcome, `MainFlowController` reads the
candidate IDs before replacing the duel screen. It supplies candidates only
for a victory. The existing completed-duel transaction receives those IDs and
merges them into the profile before validating and saving.

The profile store filters incoming candidates against catalog IDs and the
current five-card main deck. Already-mastered IDs are ignored. Newly mastered
IDs append in their first-play order. Mastery, completed-duel history,
progression, tier unlocks, final score, and run closure are committed by the
same atomic save. A save failure rolls all of them back together.

## Presentation Rules

The existing card-owner color mapping remains the rendering primitive:

- `DuelRules.PLAYER_OWNER` renders blue.
- `DuelRules.OPPONENT_OWNER` renders red.

Controllers calculate display owners from mastery instead of changing
`CardView`:

- A revealed library card is blue when its exact ID is mastered and red
  otherwise.
- A revealed reward card is blue when its exact ID is mastered and red
  otherwise. Reward cards mastered in earlier runs therefore remain blue.
- A reward drag proxy preserves its revealed source card's calculated color.
- A library drag proxy preserves its revealed source card's calculated color.
- Revealed enemy-hand cards remain red.
- Player-hand cards remain blue.
- Face-down reward placeholders retain their current independent random
  blue/red colors.
- Empty library slots retain their current empty-slot appearance.
- Duel, sect-selection, inspector, and other card-color behavior is unchanged.

The deck builder removes its random occupied-library color roll. Reward
selection keeps randomness only for its face-down placeholder positions; its
revealed choices use mastery-derived colors.

## Error Handling and Boundaries

- A failed or illegal play never creates a candidate.
- Repeated plays of the same qualifying ID create only one candidate.
- Unknown or non-main-deck candidate IDs are ignored at the persistence
  boundary and cannot create corrupt mastery data.
- Defeat and abandonment never pass candidates into the victory transaction.
- Existing mastery survives reward generation, reward claiming, deck
  exchanges, tier unlocks, and enemy changes.
- No mastery notice, sound, animation, icon, or inspector field is added in
  this feature.

## Testing

Profile-store coverage will verify:

- schema-8 defaults, validation, repair, and accessors;
- schema-7 migration preserving active runs and adding an empty mastery list;
- stable deduplication and rejection/filtering of invalid candidate IDs;
- mastery being awarded atomically on ordinary and final victories;
- defeat and abandonment producing no mastery;
- run reset and run completion preserving mastery;
- full-progress reset clearing mastery;
- save failure rolling back mastery with the rest of the victory transaction.

Duel and flow integration coverage will verify:

- successful play of an original main-deck instance creates a candidate;
- an identical drawn or freshly created copy also creates a candidate;
- a same-glyph but different-ID card does not create a candidate;
- activation and failed play do not create candidates;
- candidates survive later movement, ownership change, or removal;
- victory persists candidates while defeat and abandonment do not;
- final victory persists mastery before the run is closed.

Presentation coverage will verify:

- mastered library and revealed reward cards are blue;
- unmastered library and revealed reward cards are red;
- library and reward drag previews preserve source color;
- revealed enemy-hand cards remain red;
- reward card backs still use deterministic seeded random colors in tests;
- empty library slots and other scenes retain their current behavior.

Manual playtesting will cover a portrait run from deck building through a
victory and back to the library, confirming the played qualifying card changes
from red to blue and remains blue after restarting the run flow.
