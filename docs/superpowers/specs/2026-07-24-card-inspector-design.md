# In-Game Card Inspector Design

Date: 2026-07-24

## Goal

Let the player inspect any revealed card during a duel. A single tap opens a board-sized parchment panel showing the card's catalog information. A later tap anywhere closes the inspector and returns to the unchanged duel.

The feature is designed for portrait mobile play but must remain responsive on desktop.

## Information Display

The inspector uses the runtime card snapshot and displays:

1. `glyph` as the card name
2. `sect` tag
3. `tier` tag, formatted as `<number>阶`
4. `weapon` tag
5. `description` under the rules heading
6. `flavor` under the flavor heading

The metadata tags must always appear in this order:

`sect` → `tier` → `weapon`

Any missing or empty displayed value uses a restrained `—` placeholder. Empty fields are not removed, so the information structure remains stable across cards.

## Visual Direction

The inspector combines:

- A parchment-scroll frame with a wuxia appearance
- A clean ink-sheet information hierarchy
- A large card name with a dark divider
- Compact sect, tier, and weapon tags
- A clearly labeled rules section
- A separately styled, indented flavor section
- A subtle “tap anywhere to return” hint

The parchment occupies exactly the current board rectangle. The board grid and score panels are hidden while inspection is open. Both hands, the opponent name, the Exit button, and turn status remain visible beneath the modal layer, but cannot be activated.

If the content is taller than the available parchment viewport, it scrolls vertically. A swipe scrolls the content and does not dismiss the inspector.

## Components

### CardInspector

A reusable `CardInspector` Control scene and script owns:

- The full-screen transparent modal input layer
- The board-sized parchment panel
- Responsive layout within a supplied board rectangle
- Text and metadata population from a duplicated card-data snapshot
- Vertical overflow scrolling
- Tap-versus-scroll gesture detection
- An `inspection_closed` signal

The inspector does not read duel state or mutate card data.

### CardView

`CardView` gains an `inspection_requested(card_data)` signal and pending-pointer gesture state.

Pointer behavior:

- Press begins a possible tap.
- Release without meaningful movement emits `inspection_requested` when the card is revealed.
- Movement beyond the drag threshold begins the existing drag behavior when the card is playable.
- A revealed but non-playable card can still be inspected.
- A face-down card never emits private information.
- Mouse and touch use the same gesture rules.

The drag threshold prevents normal tap jitter from beginning a drag. Once dragging starts, the existing drag, drop, cancellation, and focus-loss behavior remains authoritative.

### DuelController

`DuelController` owns whether inspection is allowed and whether the modal is open.

It:

- Connects every spawned card's inspection signal
- Accepts inspection during player idle, opponent AI thinking, and match completion
- Rejects inspection during the resolving state so animations are never frozen midway
- Hides and restores the board grid and score panels
- Blocks all duel actions and presentation starts while inspection is open
- Supplies the current board rectangle on open and after viewport resize
- Restores the prior duel presentation when inspection closes

## AI Search Behavior

The opponent AI search may continue on its existing worker thread while inspection is open because it searches an isolated state snapshot and cannot directly change the duel.

The AI may not apply or present a move while inspection is open:

1. Search continues against the unchanged state.
2. If search finishes, its result waits.
3. Closing the inspector restores the duel presentation.
4. The controller validates the result against the current state.
5. A still-legal result is then presented normally.

The inspector does not suspend or extend the AI's real-time search deadline. Reading time may therefore contribute to the AI's thinking time.

During AI search, the normal progress loop must not overwrite the inspector's modal status presentation.

## Closing and Scrolling

The transparent modal layer captures input across the full viewport.

- A tap without meaningful movement closes inspection.
- A drag beginning inside scrollable content scrolls it instead.
- The closing tap never passes through to cards, the Exit button, or other duel controls.
- Repeated close requests are idempotent.
- Closing restores the same board, scores, turn ownership, hands, and card data that existed before opening.

## Error and Privacy Handling

- Face-down cards cannot open the inspector.
- The controller receives a deep duplicate of card data, so moving or freeing the original view cannot invalidate displayed information.
- Missing strings and invalid/missing tier values display `—`.
- Requests made during resolution or while an inspector is already open are ignored safely.
- A resize while open recomputes the parchment rectangle without reopening or losing scroll content.
- No catalog value is modified by inspection.

## Verification

Automated coverage must verify:

- Mouse and touch taps inspect revealed cards.
- Movement beyond the threshold preserves drag-and-drop behavior.
- Revealed cards in either hand and on the board can be inspected.
- Face-down opponent cards reveal no data.
- The title uses `glyph`.
- Tags appear in sect, tier, weapon order.
- Empty metadata, description, and flavor values display `—`.
- Long text scrolls within the board-sized parchment.
- A scroll gesture does not close the inspector.
- A tap closes without passing through.
- The board and score panels hide and restore.
- No action or presentation begins while inspection is open.
- AI search may finish but cannot commit until close.
- Inspection is rejected during resolution.
- Viewport resizing keeps the parchment aligned with the board.
- Repeated open and close cycles preserve duel state.

Runtime playtesting must exercise:

1. Inspecting a player-hand card without accidentally dragging it
2. Dragging that same card normally after closing
3. Inspecting a revealed board card
4. Attempting to inspect a face-down opponent card
5. Scrolling long flavor text on a portrait viewport
6. Opening during AI thinking and confirming no move appears until close
7. Closing by tapping outside the parchment and returning to the same duel

## Out of Scope

- Editing card data from the inspector
- Inspecting unrevealed opponent cards
- Showing powers, ki, abilities beyond the catalog description, or the card picture
- Multiple inspector pages or card-to-card navigation
- Opening inspection during resolution animations
- Cancelling, pausing, or extending AI search
