# 有凤来仪 Multiple Activations and Ordered Swap Design

## Goal

Implement the two unfinished 有凤来仪 abilities described in the card catalog and make multiple activate abilities a supported card primitive.

- **有凤来仪·二** keeps its existing ability: move to an adjacent empty square, then attack.
- **有凤来仪·三** also gains: swap with an adjacent allied card, then attack.
- **有凤来仪·四** gains both the allied-swap ability and: swap with an adjacent enemy card, then attack.

Every activation costs 1 ki. All three cards retain their activate abilities when ownership flips.

## Catalog Representation

An `abilities` array may contain multiple entries whose `"kind"` is `ABILITY_ACTIVATE`.

Activate abilities remain listed in gameplay priority order. Each entry declares:

- its target rule;
- its ki cost;
- whether it is retained when flipped;
- its ordered reusable actions.

The new reusable target rules are:

- `TARGET_ADJACENT_ALLY_BOARD`
- `TARGET_ADJACENT_ENEMY_BOARD`

The new reusable action is:

- `ACTION_SWAP_SELF_WITH_TARGET`

The swap action is followed by the existing standard-attack action in each catalog entry. Swap logic itself does not attack.

Catalog validation accepts multiple activate abilities, validates every entry independently, and no longer rejects a card solely because it has more than one activation.

## Runtime Activation Identity

`DuelAction` gains an `activation_index`, which identifies an activate ability by its order among the card's activate abilities. Existing callers default to index `0`.

The activation index participates in:

- action construction;
- equality;
- canonical/search keys;
- legality checks;
- execution.

This prevents two abilities with the same source and target from collapsing into one AI action.

The abilities helper exposes all activate abilities while preserving catalog order. Existing single-activation access remains compatible by returning the first entry. A card uses ki when it has at least one activate ability.

A dynamically granted activate ability keeps the existing replacement rule: it removes all activate abilities currently on the card and installs the new one. Multiple innate catalog abilities do not change that rule.

## Player Target Selection

Dragging an on-board card gathers legal targets from all of its activate abilities.

If more than one activate ability can legally target the same square, the player automatically uses the first legal ability in catalog order. No chooser or additional UI is introduced.

The drag result records the selected activation index so execution uses the same ability that targeting selected.

## AI and Simulator

Legal-action generation enumerates every activate ability independently, preserving catalog order. The AI may therefore compare the strategic value of different activations even if they share a target.

Applying an activate action:

1. resolves the selected activation by `activation_index`;
2. rechecks its target rule;
3. spends its declared ki cost;
4. executes its actions in order;
5. consumes the player's move for the turn, as existing activations do.

An invalid or stale activation index makes the action illegal and causes no state change.

## Ordered Swap Semantics

Let card **A** activate the swap and card **B** occupy the selected adjacent target square.

The swap is not an atomic exchange. It is the following ordered operation:

1. Reserve B outside the board.
2. Resolve the future `before A moves` hook.
3. Move A from A's original square to B's original square.
4. Resolve the future `after A moves` hook.
5. Reserve A outside the board.
6. Restore B to B's original square.
7. Resolve the future `before B moves` hook.
8. Move B from B's original square to A's original square.
9. Resolve the future `after B moves` hook.
10. Restore A to B's original square.
11. A performs the existing standard attack from B's original square.

Reservation and restoration are bookkeeping operations, not zone changes or movement:

- they emit no summon, exile, before-move, after-move, or other rule events;
- they do not change ownership, card identity, ki, or abilities;
- they produce no visual effect by themselves.

Only steps 3 and 8 are gameplay moves. This produces an unambiguous future movement-event order: A moves first, then B.

The implementation must route these two moves through one reusable ordered-movement boundary so future before/after movement triggers can be added without redefining swap. This feature does not yet define move cancellation, redirection, or replacement behavior; those mechanics require their own design before such effects are added.

## Visual Reconciliation

The temporary reserved states are simulation details and are never rendered.

After a successful swap, the controller reconciles both card views with the final board:

- A appears in B's former square;
- B appears in A's former square;
- A then uses the normal attack presentation from its new square.

No disappear/reappear animation is added by this feature.

## Card Definitions

### 有凤来仪·二

1. Adjacent empty target:
   - spend 1 ki;
   - move self to target;
   - standard attack.

### 有凤来仪·三

1. The same adjacent-empty activation.
2. Adjacent allied-card target:
   - spend 1 ki;
   - ordered swap with target;
   - standard attack.

### 有凤来仪·四

1. The same adjacent-empty activation.
2. The same adjacent-allied-card swap activation.
3. Adjacent enemy-card target:
   - spend 1 ki;
   - ordered swap with target;
   - standard attack.

## Failure and Edge Cases

- A swap target must still occupy the selected adjacent square and satisfy the selected ally/enemy relation when the action executes.
- The source must still occupy its recorded square and possess enough ki.
- If any legality check fails before execution begins, nothing moves and no ki is spent.
- Once the ordered swap begins, the current rules contain no interrupting movement effects, so it completes as one activation action.
- A full legal swap preserves the total number of cards on the board and preserves both card dictionaries.
- Standard attack resolves only after both cards reach their final squares.

## Tests

Automated coverage will verify:

- catalog validation accepts and validates multiple activate abilities;
- 有凤来仪·二, ·三, and ·四 expose one, two, and three activations respectively;
- every activation retains on flip and costs 1 ki;
- `card_uses_ki` recognizes any activate ability;
- dynamically granting an activation replaces all existing activations;
- activation indices affect action equality and canonical keys;
- simulator action generation includes each legal activation;
- player drag chooses the first listed legal activation when targets overlap;
- ally and enemy target rules reject wrong ownership, non-adjacent squares, and empty squares;
- swaps preserve card identity, ownership, abilities, and remaining ki;
- A moves before B, and attack occurs after both moves;
- controller views match the simulator's final board after a swap;
- invalid or stale activation indices cause no state change;
- existing single-activation cards and AI searches continue to work.
