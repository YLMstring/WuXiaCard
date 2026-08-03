# Full-Board Duel Ending and Mobile Library Drag

## Scope

This change adjusts two existing behaviors without adding new presentation or content:

1. A duel ends before another turn starts when all nine board cells remain occupied.
2. A held library card cannot move the library scroll while it is being dragged.

## Full-board duel timing

After a play or activation, the simulator completes that action and all reactions it causes. It then resolves the current owner's end-of-turn triggers. After those triggers finish, the simulator checks the board:

- If all nine cells are occupied, the state is terminal immediately.
- The active player does not change.
- No extra turn is granted.
- No `TRIGGER_START_OWNER_TURN` event is resolved.
- The completed move still advances the turn counter.
- If an end-of-turn effect reopened any cell, normal turn selection and start-of-turn triggers continue.

A full board is terminal even if an occupied card has an otherwise legal activate ability. Pending effect-queue work still resolves before terminal evaluation.

## Mobile library gesture arbitration

Normal swipe scrolling remains available until a card hold successfully arms a drag. At that moment, the library preserves its current scroll offset and temporarily prevents its native `ScrollContainer` from handling the same pointer's drag motion. The card can then move independently while the library stays fixed.

Scrolling is restored when the card drag ends, is cancelled, interaction is disabled, focus is lost, or the grid exits the scene. Movement that exceeds the threshold before the hold completes remains an ordinary library scroll and never arms a card drag.

## Testing

Simulator regressions cover:

- A ninth-card play ends the duel after end-of-turn resolution without a start-of-turn trigger.
- An end-of-turn effect that reopens a cell allows the next turn to start normally.
- A full board is terminal even when activate abilities would otherwise be legal.

Library regressions cover:

- Arming a drag disables native scroll handling without changing the saved offset.
- Ending or cancelling the gesture restores native scrolling.
- Swipe-before-hold scrolling remains unchanged.
