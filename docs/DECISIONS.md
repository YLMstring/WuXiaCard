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
- A card may have multiple innate catalog activations in listed priority order.
  Receiving a new activation replaces every current activation-bearing ability
  without deleting unrelated passive abilities.
- Ki is independent from abilities and survives ownership flips.
- A zero-ki card with no activate ability does not show a ki bead.
- `card_uses_ki()` intentionally counts activations only. Passive Meng Huo abilities do not make a zero-ki bead appear.

## Ownership and Ability Retention

- A successful flip means ownership actually changes.
- Abilities default to lost on flip. Catalog authors do not need to declare the common default.
- Only an ability with `retained_on_flip = true` survives.
- Once an ability is lost, later ownership changes do not restore it.
- Ki remains on the card when abilities are lost.

## Rule Resolution

- Abilities have no behavior ID; runtime actions identify their source card by `instance_id`.
- Global triggers resolve by row-major board cell, then ability order, then trigger order.
- Every accepted passive trigger emits `ability_triggered` before its actions.
  The controller pulses that source card unless it was the last card pulsed in
  the same move. Pulse memory resets between moves.
- Every initially valid attack emits `attack_started` before
  `CARD_BE_ATTACKED`. This presentation-only cue remains even when a later rule
  exiles or otherwise prevents the target from flipping.
- Activate abilities do not pulse.
- Missing, moved, or replaced context defaults to `NO_EFFECT`, and later actions in that rule continue.
- Only an action explicitly declaring `on_invalid_context = STOP_RULE` stops that rule's remaining actions.
- Stopping one rule never cancels later trigger groups, the enclosing event, or the turn.

## Attack Presentation

- Every attack uses one serialized reveal of `res://inkpics/attack.png` before
  its pre-attack rules resolve.
- The supplied bitmap is not redrawn, recolored, or supplemented with generated
  flecks. It uses a fixed 64 × 22 keep-aspect display box.
- The image's local left side is the attacker side. Reveal always grows
  local-left-to-right, then the whole visual rotates to face right, left, down,
  or up.
- The visual is centered on the first neighboring cell seam beside the
  attacker. A farther orthogonal target does not stretch the image, and the
  neighboring cell may be empty or different from the target.
- Diagonal attacks require their future mechanic to define a first neighboring
  step before using this presentation.
- The cue adds no sound, haptic, bright color, or gameplay state.
- It replaces the former silent pre-flip wait; capture audio and the flip
  animation remain.

## Implemented Abilities

### Gate General and Tiger General

When either would flip a card through any present or future attack/combo source, it removes that card instead.

- This pre-attack trigger survives ownership flips.
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
- Like most abilities, the draw rule is lost on ownership flip; no catalog flag is needed for that default.

### Jiang Wei and Sun Zan

They start with one ki and have a movement activate ability.

- Drag the owned board card to an orthogonally adjacent empty cell.
- Pay one ki.
- Resolve a standard attack from the destination.
- Moving does not emit summon events.

The action/target model should also support future non-movement activations with ally-square, enemy-square, or hand-slot targets.

### Meng Huo

- Whenever Meng Huo is the source of an attack that actually flips a card, that Meng Huo gains one ki.
- Exiling/removing a target does not count.
- At the end of its owner's turn, an eligible Meng Huo spends all its ki to request an extra turn.
- If multiple Meng Huos request it together, all eligible Meng Huos spend their ki but only one extra turn is granted.
- Extra-turn chains are allowed if a later turn earns ki again.
- The extra turn is granted only when the owner has a legal action.
- Ownership flip removes this passive ability, but retained ki remains.
- The extra-turn visual uses converging golden beads and a board-outline pulse;
  its former source-card pulse is replaced by the generic pre-trigger pulse. It
  adds no new sound.

### CangSongYingKe2

Whenever an enemy card is summoned into an orthogonally adjacent slot that CangSongYingKe2 can beat by the normal strict power comparison, CangSongYingKe2 immediately attacks that exact card.

- The reaction resolves after `card_placed` but before the summoned card's `TRIGGER_CARD_AFTER_SUMMONED` rules and standard attack.
- If the reaction flips or removes the summoned card, those remaining phases are cancelled and the turn still ends normally.
- Multiple eligible reactors resolve in row-major board order and stop once the summoned card leaves or changes ownership.
- Reaction attacks use the existing flip/exile path and successful-flip triggers.
- Movement is not a summon.
- The ability is lost on flip by the default non-retention rule.
- The reaction uses the generic passive-trigger card pulse before its existing
  flip/removal presentation.

## Deck Semantics

- “Main deck” currently means the five cards forming the starting hand. Those cards are not also waiting to be drawn.
- “Side deck” is the separate draw pile.
- The current side pool contains a fresh copy of every catalog card and can therefore duplicate a card present in the starting hand.
- Each side currently receives ten side-deck cards, shuffled independently.
- A zero RNG seed means nondeterministic setup; a nonzero seed supports deterministic tests.
- The player's main deck is persisted in a versioned profile and is read by new duel scenes.
- The collection library has 1,000 logical positions. Unlocked cards occupy a compact prefix; all remaining positions are empty slots.
- A persistent card ID exists in exactly one place: the five-card main deck or the occupied library prefix.
- The initial unlocked pool contains every current catalog card except `CangSongYingKe1`. With the default five-card main deck, four cards begin in the library.
- A newly unlocked card is inserted at library position one. Existing library cards shift down and empty slots remain at the tail.

## Deck Builder

- Deck building is a separate scene at `res://scenes/deck_builder.tscn`; it does not run the duel simulator, scores, AI, combat VFX, or audio.
- It reuses the duel's fixed 9:16 presentation, decorative backdrop, top header, five-slot opponent hand, five-slot player hand, CardView, and CardInspector.
- The opponent hand represents the upcoming enemy. It stays face-down in normal mode and is revealed in script-controlled testing mode.
- The center parchment is titled `藏经阁` and displays four standard 3:4 library cards per row with exactly three visible rows.
- Its exterior uses the exact same parchment geometry and shared style code as the card inspector.
- The vertical scrollbar is hidden. Players navigate by swiping up/down; desktop mouse swipes are handled locally without enabling project-wide mouse-to-touch emulation.
- The first card row begins eight pixels below the title-divider content boundary.
- Seven-pixel side insets keep the first and fourth card borders, shadows, and hold lift visible inside the clipped scroll viewport.
- Library card names use tier colors: slate grey for tier 1, forest green for 2, steel blue for 3, muted violet for 4, dark orange for 5, and crimson for every other value.
- The 1,000 logical library slots form 250 rows and are virtualized. Only three visible rows plus one buffer row above and below—20 slot Controls total—are live.
- A short tap on any revealed card opens the existing inspector. Closing it restores the prior library scroll position.
- Immediate pointer movement scrolls the library. Holding a library card for roughly 0.25 seconds arms a drag.
- Dropping an armed library card onto one of the five main-deck slots exchanges the two cards. The displaced main-deck card returns to the exact logical library position from which the dragged card came.
- Invalid drops and empty library slots do nothing.
- Exchanges save immediately. If persistence fails, the displayed exchange is rolled back.
- The header icon only emits `back_requested`; a future scene router will decide where to navigate.
- The deck builder has no score panels.

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
