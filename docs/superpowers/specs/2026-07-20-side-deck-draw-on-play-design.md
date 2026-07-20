# Side Deck and Draw-on-Play Ability Design

## Goal

Add a simulator-visible “when played, draw cards” ability and give it to Fa Zheng and Strategist. Introduce real per-owner side decks so drawn cards become legal future moves for players, testing mode, greedy AI, and deeper search.

The draw amount is declared per effect in `card_catalog.gd`. Most future abilities do not survive an ownership flip, so missing retention metadata defaults to `false`.

## Terminology

- **Main deck:** the five cards that form a side’s starting hand. For this prototype, the existing player and opponent five-card lists remain unchanged.
- **Side deck:** the draw source used by effects. It is separate from the main deck and may contain another copy of a card that is already in the main deck.
- **Hand:** the currently playable cards. It has a hard maximum of five cards.

## Match Setup

Each owner receives:

- its existing five-card main deck as the starting hand;
- a side deck containing one fresh copy of every card in `CardCatalog.ALL_CARD_IDS`;
- an independently shuffled side-deck order.

The starting hand is not removed from the side deck because the two zones come from separate deck lists. A player can therefore begin with Fa Zheng and later draw a second Fa Zheng from the side deck.

Every main-deck and side-deck card is instantiated once at match setup with a unique match-local instance ID. Shuffling moves complete side-deck instances; drawing never reconstructs a card from its catalog definition.

Production matches generate a fresh shuffle. Tests can inject ordered side-deck instances or a fixed pre-tree shuffle seed so assertions remain deterministic. Once setup is complete, the actual deck order is stored in `DuelState` and is perfect information for AI search, as previously approved.

## Catalog Schema

Add the known effect ID `draw_cards_on_play`.

Fa Zheng and Strategist declare:

```gdscript
{
	"id": EFFECT_DRAW_CARDS_ON_PLAY,
	"draw_count": 2,
}
```

`draw_count` must be a positive integer. The catalog validator rejects missing, non-integer, zero, or negative values for this effect.

`retained_on_flip` becomes optional for every catalog effect:

- omitted means `false`;
- present values must be Boolean;
- Gate General and Tiger General continue to explicitly declare `true` for `exile_instead_of_flip`.

When a catalog definition becomes a runtime card instance, each active effect is normalized to contain an explicit Boolean retention value. This keeps match-state and effect-resolution code simple while allowing ordinary catalog declarations to omit the default.

If a card with `draw_cards_on_play` is later flipped, the existing ability-loss process permanently removes that effect because its normalized retention value is `false`.

## Draw Resolution

The hand limit is five. For a requested draw amount, the actual draw count is:

```text
minimum(requested count, 5 - current hand size, remaining side-deck size)
```

Examples:

- Play Fa Zheng from a full hand: hand falls from five to four, then draws one card and returns to five.
- Play Fa Zheng while holding three cards: hand falls to two, then draws two cards and reaches four.
- Request two with one card left in the side deck: draw one.
- Request two with an empty side deck or full hand: draw zero.

There is no reshuffle, fatigue, damage, discard, or failed-draw penalty.

Drawn cards are removed from the top of the shuffled side deck and appended to the end of the logical hand in draw order. Array index `0` is the top of each side deck.

## Effect and Event Order

`DuelSimulator.apply_move` remains the single authoritative transition:

1. Validate the move and copy the source state.
2. Remove the played card from hand and place it on the board.
3. Emit `card_placed`.
4. Resolve the placed card’s on-play effects in catalog order.
5. For each actual draw, move one side-deck instance into the hand and emit `card_drawn`.
6. Resolve flip or exile attempts in existing top/right/bottom/left order.
7. Advance turn count and select the next active owner.

Each `card_drawn` event contains pure values: owner ID, card ID, instance ID, and resulting logical hand index. The complete card stays in the copied `DuelState`; presentation looks it up by instance ID.

The draw resolver is pure and scene-free. It accepts the copied state, source card/cell, and owner, mutates only that copied state, and returns ordered events. The existing flip-attempt resolver remains separate.

## Simulator, AI, and Terminal Behavior

Because drawing occurs inside `apply_move`:

- greedy AI commits the same state change as a human move;
- alpha-beta search sees the exact future side-deck order and newly available hand moves;
- copied search branches cannot mutate sibling deck or hand state;
- testing mode and normal mode use identical draw rules.

No special AI heuristic is added in this feature. Greedy AI remains short-sighted by design; deeper search can value the additional future moves.

A non-empty side deck does not by itself create a legal move. If a side has no hand cards, it cannot trigger an on-play draw. Existing pass and terminal rules continue to depend on legal hand-to-board moves and the effect queue, not unused side-deck contents.

## Controller and Hand Presentation

The existing five physical hand slots remain fixed, and card size does not change.

When a `card_drawn` event is presented:

1. Find the drawn runtime card in the new logical hand by instance ID.
2. Spawn its `CardView` into the first empty physical hand slot.
3. Show it face-up for the player and in testing mode.
4. Show it face-down for the normal-mode opponent.
5. Present the approved **Ink Summon** arrival: an ink bloom opens over the slot, then the card rises out of it and settles into place.

Draw events are presented sequentially, never simultaneously. Each card receives a default `0.12` second ink-bloom phase followed by a `0.28` second rise-and-settle phase. A second drawn card starts only after the first has settled. These durations are exported presentation tunables rather than simulator rules.

A dedicated draw sound accompanies each Ink Summon. The sound combines a short brush-stroke texture at bloom onset with a low plucked note near card settlement. It uses its own audio player and is audibly distinct from placement, flip, and exile sounds. The prototype may synthesize this as one timed WAV stream so the two sound components cannot drift apart.

After the final `card_drawn` event, the presenter waits a default `0.20` seconds before the first flip or exile event. This presentation-only gap prevents the draw confirmation from clashing with capture audio. It does not delay or alter the already-computed simulator transition.

Integration fast mode sets the Ink Summon durations and the post-draw gap to zero and suppresses draw audio.

Physical slot order can differ from logical hand order after a card fills an interior empty slot. Therefore controller selection and AI presentation must stop treating visual traversal order as simulator hand order. Drag commits and AI-selected cards map through stable instance IDs:

- card view → instance ID → current logical hand index;
- simulator hand index → instance ID → matching card view.

This preserves empty-slot behavior, correct move selection, and fixed card size without repacking the hand.

Input stays locked while draw and subsequent flip/exile events are presented. Turn ownership and playability update only after the ordered transition finishes.

## Error and Edge Handling

- A draw can never increase a hand beyond five.
- An empty or depleted side deck resolves cleanly with no event for cards that were not drawn.
- Main-deck and side-deck copies always have different instance IDs.
- Drawn cards receive fresh catalog effects independent of another copy’s lost effects.
- Hidden opponent draws expose no glyph, powers, name, tooltip, or effect information.
- A drawn Fa Zheng or Strategist can later trigger its own draw effect when played.
- Multiple future on-play draw effects resolve sequentially; each recalculates remaining hand space and deck size.
- Existing exile effects, ability loss, scores, passes, testing mode, and face-down reveal-on-play behavior remain unchanged.

## Verification

Catalog tests will verify:

- the new effect is known;
- Fa Zheng and Strategist declare `draw_count = 2` without retention metadata;
- missing retention normalizes to `false` in runtime instances;
- explicit retained exile effects remain `true`;
- invalid draw counts fail validation;
- each side-deck list contains all ten catalog IDs exactly once.

Simulator tests will verify:

- event order is placement, actual draws, then flip/exile events;
- full-hand play draws only one card;
- lower hand counts can draw two;
- hand limit, empty deck, and partially depleted deck behavior;
- exact top-deck order and removal;
- state-copy isolation for hands, decks, and active effects;
- a drawn copy remains independent from a flipped copy that lost its ability;
- greedy and deeper search transitions retain the correct deck state;
- side-deck contents alone do not prevent terminal state.

Integration tests will verify:

- production main decks remain the current five starting cards;
- production side decks contain shuffled fresh instances of all ten cards;
- playing Fa Zheng creates the correct player hand view without resizing cards;
- playing Strategist creates a concealed opponent view in normal mode;
- testing mode reveals both owners’ drawn cards;
- multiple drawn cards are presented sequentially in simulator event order;
- fast mode suppresses Ink Summon delays and draw audio while preserving the resulting hand views;
- the post-draw presentation gap occurs before flip or exile presentation, not inside simulator state resolution;
- interior empty slots are filled while instance-ID mapping still commits the intended card;
- AI replies, focus-loss recovery, exile presentation, and fixed five-slot layout still pass.

A manual portrait playtest will cover player draw, opponent concealed draw, testing-mode opponent draw, sequential two-card Ink Summons, distinct brush/pluck audio, separation from the following flip sound, invalid drops after drawing, and repeated play of a drawn on-play card.

## Out of Scope

- Deck-building UI or persistence.
- Editing main-deck or side-deck contents in game.
- Side-deck count indicators or card previews.
- Mulligans, ordinary per-turn draws, discard, reshuffle, fatigue, or hand overflow choices.
- A general trigger stack for every future timing window.
- Changes to AI time budgets or heuristic evaluation.
