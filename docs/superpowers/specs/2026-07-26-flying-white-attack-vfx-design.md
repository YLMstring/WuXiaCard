# Asset-Backed Flying-White Attack VFX Design

## Goal

Make every card-to-card attack visibly originate from its source card and cross
the first board-cell boundary in the attack direction before the outcome
resolves. The effect must use the supplied ink artwork exactly, remain readable
on portrait mobile screens, preserve ordered combat presentation, and stay
fixed beside the attacker when a future attack reaches a non-neighbor target.

## Approved Visual Direction

Use `res://inkpics/attack.png` as the complete **Flying-White Thrust**. The
650 × 226 transparent PNG is the approved visual source; its heavier left side
is always the attacker side.

Apart from the approved reveal and fade animation, the runtime must not redraw,
procedurally approximate, recolor, add flecks to, or otherwise alter the
artwork. It displays the texture inside a 64 × 22 logical-pixel box with its
original aspect ratio preserved. This is the approved balanced size.

It introduces no new sound, haptic, gold, jade, or bright impact color. Existing
capture, exile, movement, ability, and extra-turn feedback keeps its own visual
and audio identity.

## Attack Timing and Rules Boundary

Every initially valid attack emits one presentation-only `attack_started` event
before `CARD_BE_ATTACKED` rules resolve.

`attack_started` is not a catalog trigger, condition, action, or reusable
reaction hook. Abilities cannot subscribe to it. Its only purpose is to order
presentation and identify the exact visual source and target.

The event contains:

- `source_cell`
- `source_instance_id`
- `source_owner_id`
- `target_cell`
- `target_instance_id`
- `target_owner_id`
- `attack_reason`

The ordered sequence is:

1. validate the exact attacker and target;
2. emit `attack_started`;
3. resolve `CARD_BE_ATTACKED` rules;
4. revalidate the exact attacker and target;
5. resolve exile, flip, or another future replacement outcome;
6. resolve after-flip rules when ownership actually changes.

Because the cue represents the attack attempt, it still plays when Gate General
or Tiger General later replaces the flip with exile. Invalid attacks emit no
cue. Reaction, summon, activation, combo, and future attack sources all pass
through the same attack resolver and receive the same cue.

`attack_started` is transition data only. It is not stored in `DuelState`, does
not enter state keys, and does not change legal actions, search, evaluation, or
simulation outcomes.

## First-Boundary Geometry

The image is always centered on the first board-cell seam beside the attacker.
It never stretches, travels, or relocates to the actual target edge.

For the current orthogonal board:

1. derive the row/column direction from `source_cell` toward `target_cell`;
2. identify the cell immediately next to `source_cell` in that direction;
3. obtain the live rectangles of the source cell and that neighboring cell;
4. center the 64 × 22 image box on the midpoint of their shared seam;
5. rotate the image so its local left side remains attached to the attacker.

The direction-to-rotation mapping is:

- attacker left of the seam: `0°`;
- attacker right of the seam: `180°`;
- attacker above the seam: `90°`;
- attacker below the seam: `-90°`.

For a future non-neighbor attack along a row or column, only step 1 changes
which direction is chosen. The image still crosses the first seam beside the
attacker at the same fixed size, even when the neighboring cell is empty or is
not the target.

Diagonal or non-grid-line attacks are outside this specification. If a future
mechanic permits one, that mechanic must define its first neighboring step
before using this presentation component.

Placement uses live board-cell rectangles, so it remains correct under portrait
scaling, wide-screen decorative extensions, and Android display differences.

## Rendering Component

Keep the reusable, input-transparent full-canvas `AttackVfx` control above board
cards and below drag/modal UI.

`AttackVfx` receives the shared-seam center, rotation, duration, and supplied
texture. It owns all temporary display state and performs one serialized
playback at a time.

The component contains a locally oriented 64 × 22 clipping region and a
`TextureRect` that preserves the PNG's aspect ratio. Playback expands the clip
from local left to local right, briefly holds the fully revealed image, then
fades it as one unit. The component is rotated only after its local reveal
direction is established, so the reveal always begins at the attacker.

There is no `_draw()` brush geometry, particle system, generated fleck, or
per-frame texture allocation. The single preloaded texture and one reusable
clip/texture hierarchy keep mobile cost bounded.

## Duration and Existing Capture Pause

Default playback remains approximately `0.15` seconds:

- about `0.06` seconds to reveal the bitmap from its attacker-facing side;
- about `0.035` seconds to hold the impact;
- about `0.055` seconds to fade.

The attack cue replaces the current silent pre-flip wait. A successful target
flip begins immediately after the stroke completes, using its existing capture
sound and flip duration. This prevents the new effect from making every attack
feel slower.

Multi-target attacks remain serialized in canonical attack order. Each target
receives its own stroke immediately before its own reaction/outcome sequence.

Fast test mode uses zero duration while still recording the requested playback
and cleaning temporary state.

## Controller Integration

`DuelController` handles `attack_started` in the existing ordered transition
presenter:

1. append the event to the presentation trace;
2. derive the orthogonal direction from `source_cell` and `target_cell`;
3. resolve the source board cell and its first neighboring board cell;
4. calculate their live shared seam and the required rotation;
5. pass the placement to `AttackVfx`;
6. await playback before processing the next event.

The neighboring cell need not contain a card. The target can be farther away
without affecting the image's placement or size. If the source cell, direction,
or first neighboring cell cannot be resolved, the controller skips the visual
without delay. Rules state is already authoritative and is never changed to
satisfy presentation.

## Verification

Simulator tests cover:

- `attack_started` before `CARD_BE_ATTACKED` trigger events;
- ordinary summon attacks;
- reaction attacks;
- activation movement followed by attack;
- exile interception retaining the initial cue;
- invalid and stale attacks emitting no cue;
- multi-target cue ordering;
- unchanged next-state and search behavior.

Integration tests cover:

- the input-transparent overlay and asset-backed playback API;
- the exact `res://inkpics/attack.png` resource path;
- the fixed 64 × 22 logical-pixel display box with preserved aspect ratio;
- local-left-to-right reveal before rotation;
- all four orthogonal attacker rotations;
- horizontal and vertical adjacent placement on the shared seam;
- synthetic non-neighbor attacks staying on the first seam at the same size;
- an empty first neighboring cell;
- missing source cells, invalid directions, and missing neighboring cells;
- zero-duration fast-mode cleanup;
- one playback per attack event;
- cue presentation before ability pulse, exile, or flip;
- removal of procedural brush/fleck drawing and the old silent pre-flip wait
  without removing the flip animation.

Manual playtesting checks normal, reaction, exile, movement-activation, and
multi-target attacks at normal speed on the portrait duel. It confirms the exact
supplied bitmap reveals from the attacker, crosses only the first adjacent seam,
rotates correctly in all four directions, stays fixed for a synthetic
non-neighbor attack, does not obscure the board for too long, and produces no
runtime errors or accumulating visuals. A wide-PC check confirms that decorative
letterboxing does not alter board-relative placement.
