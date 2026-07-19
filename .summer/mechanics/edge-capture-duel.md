# Mechanic: Drag-and-Drop Edge-Capture Duel

## Player verb

Drag a card from the player's hand and release it over an empty cell on a 3×3 board.

## Input

- Press/touch a playable hand card to begin one active drag.
- The card follows the pointer with a 48 logical-pixel upward offset on touch so the destination remains visible.
- Release over an empty board cell to place the card.
- Release elsewhere or over an occupied cell to return it to the hand without spending the turn.
- Mouse input mirrors touch input for desktop development.

## Response

1. A legal drop snaps the card into the target cell and removes it from the hand.
2. The placed card compares its top, right, bottom, and left powers with adjacent enemy cards.
3. A strictly greater touching power captures the adjacent card. Equal values do not capture.
4. Directly adjacent captures resolve one at a time; combo/chain rules are not part of this slice.
5. Ownership and score update, then the deterministic opponent takes its turn.
6. The match ends when all nine cells are occupied. Board ownership determines the result.

## Feedback

- **Visual:** the dragged card lifts and casts a stronger shadow; legal cells receive a gold highlight; placement snaps into the cell; captured cards flip sequentially and change ownership color.
- **Audio:** procedural placeholder paper/tap sound on placement and a sharper cue on capture. Final sound assets are deferred to the audio phase.
- **Mechanical:** input locks during placement/capture/opponent resolution; captures pause briefly in sequence; mobile receives light placement haptics and stronger multi-capture haptics.

## Failure modes

- Invalid/occupied drop: return to the hand and shake; turn remains the player's.
- Opponent or resolution state: hand cards cannot begin a drag.
- Second pointer during a drag: ignored.
- Pointer cancellation or focus loss: safely return the card to its hand.
- Repeated release events: a turn-state lock prevents duplicate placement.

## Strategic depth

- Protect weak edges with board boundaries or friendly cards.
- Choose between an immediate capture and preserving a strong answer for later.
- Expose bait when it enables a stronger recapture.
- Learn the deterministic opponent priority: most immediate captures, then most boundary-protected power, then stable card/cell order.
- No abilities, elements, combos, or rule variants in this vertical slice.

## Approved portrait layout

- Opponent name in the upper-left; Exit in the upper-right.
- Opponent and player hands each show five portrait cards across the usable width.
- Card powers sit at the midpoint of all four sides, never in the corners.
- The board uses a width/height ratio of approximately 0.78 so every cell matches a portrait card.
- The board sits between both hands with equal measured gaps. At the 540×960 reference viewport, both gaps are approximately 50 logical pixels.
- Score counters overlay to the right of the board and do not influence horizontal centering.
- No right-side arrow.

## Tunables

```gdscript
@export var board_aspect_ratio: float = 0.78
@export var drag_touch_offset: float = 48.0
@export var snap_duration: float = 0.12
@export var capture_step_delay: float = 0.18
@export var opponent_think_delay: float = 0.55
@export var invalid_shake_duration: float = 0.18
@export var placement_haptic_ms: int = 20
@export var multi_capture_haptic_ms: int = 45
```

## Scene graph

```text
Main (Control)
└─ Duel (instance: res://scenes/duel.tscn)

Duel (Control, script: duel_controller.gd)
├─ Background (ColorRect)
├─ TopWash (ColorRect)
├─ BoardCenter (Control, full rect)
│  └─ BoardGrid (GridContainer, 3 columns)
├─ TopBar (HBoxContainer)
│  ├─ OpponentName (Label)
│  └─ ExitButton (Button)
├─ OpponentHand (HBoxContainer)
├─ PlayerHand (HBoxContainer)
├─ ScoreOverlay (VBoxContainer)
│  ├─ OpponentScore (Label)
│  └─ PlayerScore (Label)
├─ TurnStatus (Label)
├─ DragLayer (Control, full rect)
├─ PlacementAudio (AudioStreamPlayer)
└─ CaptureAudio (AudioStreamPlayer)

CardView (PanelContainer, script: card_view.gd)
├─ ArtPlaceholder (Label)
├─ TopPower (Label)
├─ RightPower (Label)
├─ BottomPower (Label)
└─ LeftPower (Label)
```

## Verification path

- Automated rules tests cover four-direction capture, ties, ownership scoring, legal moves, and deterministic AI selection.
- A runtime integration test instantiates the real duel scene, drives a complete nine-card match through the same commit path used after a drag, and validates completion/score invariants.
- Manual golden path: drag a player card into a legal cell, observe captures and opponent response, repeat to a full board, and confirm the result state.

## Open questions

None for this implementation pass.
