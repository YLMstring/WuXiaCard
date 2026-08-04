# Activation Targeting and Swap Presentation Design

## Scope

Improve board-card activation targeting and movement presentation without
changing duel rules, action legality, simulator state, AI decisions, replay
records, or card declarations.

This design covers two related presentation problems:

- Every board-card activate ability uses trace-only targeting while its source
  card remains anchored in its board square.
- Reciprocal card movements are presented as a readable two-card swap shared
  by 有凤来仪, 泰山十八盘, and future effects that emit the same movement events.

Hand-card play retains its current physical drag behavior.

## Board activation targeting

### Start and update

When a playable board card begins a drag gesture, the controller identifies the
gesture as an activation before the card can follow the pointer. The card stays
parented to its board cell and keeps its original global position. It retains
the existing selected drag style and `1.05` scale while anchored, but it does
not translate away from the square.

A live ink targeting trace begins at the source card's center and ends at the
current pointer position. The trace updates throughout mouse and touch drags.
Existing legal-cell and hovered-target highlighting remains active.

The trace is a targeting cue, not a movement event. It does not play movement
audio and is never stored in replay data.

### Release and cancellation

Releasing over a legal target removes the targeting trace and commits the
selected activation. The source card does not move until the committed action's
transition events are presented.

Releasing over an invalid target, losing application focus, or otherwise
cancelling the gesture removes the trace, clears highlights, restores the
source card's normal selected state, and plays the existing invalid shake while
the card remains in its original cell.

This behavior applies to every board-card activate ability. The trace is
independent of the resulting action, so future ally-square, enemy-square, hand-
slot, and other targeted abilities can reuse it without implying that the
source card will move.

## Committed movement presentation

### Single-card movement

A single `card_moved` event remains an ordinary movement. After target
selection, the real card view moves from its source to its destination and uses
the existing movement sound. It creates no movement trail. This covers
有凤来仪's empty-square move and future committed movement actions.

### Reciprocal swap detection

Two consecutive `card_moved` events form one swap only when they are reciprocal:

- the first card moves from cell A to cell B;
- the second card moves from cell B to cell A; and
- both referenced card views are still valid in the captured pre-movement
  presentation state.

The first movement event identifies the initiating card. A reciprocal pair is
presented once rather than as two unrelated moves.

### Swap animation

Both card views temporarily move into the existing duel overlay while
preserving their original global rectangles. They travel simultaneously along
shallow opposing arcs around the midpoint, avoiding a direct visual overlap.

The animation lasts `0.28` seconds, including its eased landing into the
destination cells. Movement audio plays once. Neither card creates a movement
trail.

After the animation completes, both views are reparented into their logical
destination cells, their transforms are normalized, and the controller's board
view mapping matches the already-resolved simulator state.

有凤来仪 and 泰山十八盘 use this same event-driven swap presentation. No card ID
is consulted by the presentation code.

## 泰山十八盘 entrance sequence

泰山十八盘's automatic entrance swap uses this order:

1. The hand-play card lands and settles visibly in its originally selected
   square.
2. Its normal passive-ability pulse occurs in that original square. Placement
   settling and the readable original-square phase total `0.30` seconds.
3. The reciprocal movement events play the generic swap animation.
4. The card settles in its new square.
5. Its ordinary post-summon attack is presented from the new square.

The swap action itself still declares no attack. The attack remains the normal
summon attack already produced by the simulator after entrance effects resolve.

## Controller event staging

The simulator may finish the complete action immediately, but the controller
captures board views before applying the visual transition and presents events
in order.

The controller must not remap views to their final cells before movement events
are reached. Passive pulses therefore occur against the pre-movement view
layout. When a movement event is reached, the controller either presents a
single move or groups a reciprocal pair into a swap. Later attack, flip, exile,
draw, and other event presentations await movement completion.

Replay uses the same controller event staging and therefore shows the same
target-independent committed movement and swap animations. Targeting traces are
not replayed because input gestures are not part of replay records.

## Tunable presentation values

The controller exposes presentation-only values with these initial defaults:

- entrance original-square phase: `0.30` seconds total;
- swap travel duration: `0.28` seconds;
- shallow arc offset: `12%` of the shorter board-cell side;
- targeting trace: `6` pixels wide on the fixed 540-pixel canvas, using the
  ink teal `Color(0.12, 0.42, 0.38, 0.72)`.

Fast test mode sets new waits and movement durations to zero while preserving
the same final remapping and event order.

## Failure handling

Presentation failure must never alter duel results.

- If a reciprocal pair is incomplete, malformed, or references a missing view,
  the controller immediately reconciles affected views to the logical state.
- If a tween is interrupted by scene exit or replay cancellation, surviving
  views are normalized and reconciled before further interaction.
- Invalid targeting never commits an action and never moves the source view.
- Input is already disabled while the controller is resolving an action, so no
  second drag can begin during committed movement.

## Verification

Focused controller tests cover:

- hand-card dragging still moves the physical card;
- every board-card activation keeps its source view anchored while dragging;
- the targeting trace follows mouse and touch input and disappears on valid,
  invalid, focus-loss, and cancelled endings;
- invalid release shakes the anchored card and commits no action;
- 有凤来仪 empty-square movement starts only after target commitment and keeps
  its movement sound without creating a movement trail;
- 有凤来仪 reciprocal movement produces one swap animation and one sound, with
  no movement trail;
- 泰山十八盘 remains in its original square for placement and pulse, swaps, then
  presents its ordinary attack from the new square;
- both swap card-view identities match the simulator's final board cells;
- malformed or missing-view movement events fall back to safe reconciliation;
- fast mode and replay reach the same final view mapping without extra input
  traces.

Existing simulator, selector, ability, replay, and AI-search suites remain green
because this feature changes presentation only.
