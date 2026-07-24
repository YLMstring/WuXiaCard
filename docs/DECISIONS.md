# Durable Product and Rules Decisions

These decisions were explicitly established during development and should not be silently changed.

## Match and Layout

- The game is portrait-first and intended for mobile.
- Board cells use row-major order, left-to-right then top-to-bottom.
- Card powers are top, right, bottom, left.
- The center board is visually separated from two five-slot hands. Empty slots remain; cards do not grow or repack as hand size falls.
- Mouse and touch should produce equivalent gameplay behavior.
- Opponent name is shown at top-left and exit at top-right.

## Information and Testing

- Normal mode hides the opponent's hand with card backs.
- Future abilities may reveal hidden cards, so concealment is presentation state, not deletion of card data.
- The AI is allowed perfect information, including both hands and shuffled deck order.
- Testing mode lets the player manually control both sides and reveals both hands.
- Testing mode is a script setting, not an in-game toggle.

## Turn and Activation Rules

- On a turn, choose exactly one: play a hand card or activate a card already on the board.
- Every activate ability costs one ki.
- A card can have at most one activate ability. Receiving a new one replaces the old activate ability without deleting unrelated effects.
- Ki is independent from abilities and survives ownership flips.
- A zero-ki card with no activate ability does not show a ki bead.
- `card_uses_ki()` intentionally counts activate abilities only. Passive Meng Huo effects do not make a zero-ki bead appear.

## Ownership and Effect Retention

- A successful flip means ownership actually changes.
- Effects default to lost on flip. Catalog authors do not need to declare the common default.
- Only an effect with `retained_on_flip = true` survives.
- Once an effect is lost, later ownership changes do not restore it.
- Ki remains on the card when effects are lost.

## Implemented Abilities

### Gate General and Tiger General

When either would flip a card through any present or future attack/combo source, it removes that card instead.

- This replacement effect survives ownership flips.
- The removed card goes to its original owner's removed zone.
- The removed card keeps its original ownership identity.
- Removal is not a successful flip and does not generate Meng Huo ki.

### Fa Zheng and Strategist

When played, draw the catalog-declared number of cards (`2` currently).

- Draw from the side deck, not the starting/main hand.
- Never exceed five total cards in hand; reduce the draw count as needed.
- Stop if the side deck is empty.
- Cards are drawn/presented sequentially with an Ink Summon visual.
- There is a small post-draw delay so later board effects do not visually clash.
- The dedicated draw sound was deliberately removed because it was noisy.
- Like most effects, the ability is lost on ownership flip; no catalog flag is needed for that default.

### Jiang Wei and Sun Zan

They start with one ki and have a movement activate ability.

- Drag the owned board card to an orthogonally adjacent empty cell.
- Pay one ki.
- Resolve a standard attack from the destination.
- Moving does not retrigger on-play effects.

The action/target model should also support future non-movement activations with ally-square, enemy-square, or hand-slot targets.

### Meng Huo

- Whenever Meng Huo is the source of an attack that actually flips a card, that Meng Huo gains one ki.
- Exiling/removing a target does not count.
- At the end of its owner's turn, an eligible Meng Huo spends all its ki to request an extra turn.
- If multiple Meng Huos request it together, all eligible Meng Huos spend their ki but only one extra turn is granted.
- Extra-turn chains are allowed if a later turn earns ki again.
- The extra turn is granted only when the owner has a legal action.
- Ownership flip removes this passive ability, but retained ki remains.
- The extra-turn visual uses converging golden beads; it adds no new sound.

## Deck Semantics

- “Main deck” currently means the five cards forming the starting hand. Those cards are not also waiting to be drawn.
- “Side deck” is the separate draw pile.
- The current side pool contains a fresh copy of every catalog card and can therefore duplicate a card present in the starting hand.
- Each side currently receives ten side-deck cards, shuffled independently.
- A zero RNG seed means nondeterministic setup; a nonzero seed supports deterministic tests.

## Inspector

- A single tap on a revealed card opens an inspector occupying exactly the board rectangle.
- A face-down card cannot open it or leak metadata.
- The inspector hides the board and score while keeping hands, top bar, and status visible.
- It is modal: gameplay input is blocked.
- It cannot open while an action is resolving.
- AI search may continue while the inspector is open, but a completed AI result must wait to apply until it closes.
- Tap closes; swipe scrolls and does not close.
- Metadata order is sect, tier, weapon; name uses `glyph`; empty content displays a placeholder.

## AI

- Target behavior is near-perfect play within a fixed time budget.
- Current hard-opponent budget is 10 seconds; future easier opponents can use 5 seconds.
- Difficulty changes only the time budget, not the evaluator or intentional move weakening.
- Use the best result from the deepest fully completed iteration.
- Ignore an incomplete deeper iteration.
- If depth one cannot complete, worker search fails, or its action becomes invalid, use deterministic greedy fallback.
- Search can finish early if it proves/solves the position.
