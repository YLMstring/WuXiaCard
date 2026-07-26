# Flying-White Attack VFX Design

## Goal

Make every card-to-card attack visibly travel from its source card to its target
before the outcome resolves. The effect must fit the duel's classical ink-wash
language, remain readable on portrait mobile screens, preserve ordered combat
presentation, and support future attacks against non-neighbor targets.

## Approved Visual Direction

Use a **Flying-White Thrust**: a short, directional dry-brush stroke with broken
ink coverage and visible rice-paper gaps.

The effect contains:

- a near-black, irregular brush body;
- thinner gray-brown dry-brush fragments that create the flying-white texture;
- exactly three restrained ink flecks carried toward the target;
- a tapered leading edge that makes the attack direction unmistakable.

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

## Vector-Based Geometry

Presentation must not assume that source and target cells are adjacent or
orthogonal.

Given the attacker and target card view rectangles:

1. calculate the normalized vector from attacker center to target center;
2. intersect that vector with the attacker's rectangle to find its attacking
   edge;
3. intersect the reverse vector with the target rectangle to find its facing
   edge;
4. move each endpoint slightly inside its card rectangle;
5. draw the stroke from the attacker endpoint to the target endpoint.

For current adjacent attacks, the stroke begins just inside the attacker's
attacking edge, crosses the narrow board-cell seam, and ends just inside the
neighbor card's facing edge. For future non-neighbor attacks, the same API and
calculation naturally extend the stroke across the actual distance. Arbitrary
source-to-target vectors remain valid even if a future ability permits diagonal
or otherwise unusual targeting.

Endpoints are calculated from live view rectangles rather than board-cell size,
so the effect remains correct under portrait scaling, wide-screen decorative
extensions, and Android display differences.

## Rendering Component

Add a reusable, input-transparent full-canvas `AttackVfx` control above board
cards and below drag/modal UI.

`AttackVfx` receives source and target rectangles, duration, and ink color. It
owns all temporary drawing state and performs one serialized playback at a
time.

The stroke is procedural:

- split the source-to-target segment into a small deterministic set of tapered
  brush fragments;
- leave narrow gaps between fragments to expose the paper beneath;
- use a perpendicular vector to vary fragment width and create an imperfect
  brush silhouette;
- place exactly three deterministic flecks near the target-facing end;
- reveal fragments from source to target, hold briefly, then fade together.

No particle nodes, textures, random allocations per frame, or persistent child
nodes are required. Geometry is rebuilt once per playback and drawn through
`_draw()`, keeping mobile cost bounded.

## Duration and Existing Capture Pause

Default playback lasts approximately `0.15` seconds:

- about `0.06` seconds to write the stroke;
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
2. resolve source and target views by stable instance ID;
3. obtain their live global rectangles;
4. pass them to `AttackVfx`;
5. await playback before processing the next event.

If either card view is missing, invalid, or no longer mapped, the controller
skips the visual without delay. Rules state is already authoritative and is
never changed to satisfy presentation.

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

- the input-transparent overlay and reusable playback API;
- horizontal, vertical, adjacent, and synthetic non-neighbor geometry;
- source-to-target direction;
- missing source or target views;
- zero-duration fast-mode cleanup;
- one playback per attack event;
- cue presentation before ability pulse, exile, or flip;
- removal of the old silent pre-flip wait without removing the flip animation.

Manual playtesting checks normal, reaction, exile, movement-activation, and
multi-target attacks at normal speed on the portrait duel. It confirms the
stroke crosses current adjacent seams, points toward the target, does not obscure
the board for too long, and produces no runtime errors or accumulating visuals.
