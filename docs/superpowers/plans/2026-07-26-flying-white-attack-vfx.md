# Flying-White Attack VFX Implementation Plan

**Design:** `docs/superpowers/specs/2026-07-26-flying-white-attack-vfx-design.md`

**Goal:** Show one short directional dry-brush stroke from the attacking card to
the attacked card before every initially valid attack resolves, including
attacks later intercepted by exile.

**Architecture:** `DuelSimulator` emits a presentation-only `attack_started`
event immediately after the attack's first identity/ownership validation.
`DuelController` consumes the event in transition order and awaits a reusable
full-canvas `AttackVfx` control. The VFX derives endpoints from live card
rectangles and never participates in rules, state, search, or targeting.

## Task 1: Lock attack-event semantics with simulator tests

**Files:**
- Modify: `tests/test_duel_simulator.gd`
- Verify: `tests/test_duel_search.gd`

1. Run the full suite before behavioral edits and record the fresh baseline.
2. Add an event helper/assertion for `attack_started` payloads.
3. Assert that a normal standard attack emits:
   `attack_started -> card_flipped -> ability_lost`.
4. Assert all seven stable event fields:
   `source_cell`, `source_instance_id`, `source_owner_id`, `target_cell`,
   `target_instance_id`, `target_owner_id`, and `attack_reason`.
5. Assert a CangSong reaction emits its ability pulse event, then
   `attack_started`, then its flip outcome.
6. Assert a movement activation followed by a standard attack emits
   `card_moved`, then `attack_started`, then its outcome.
7. Assert an intercepted Gate/Tiger attack still emits `attack_started` before
   the target's `CARD_BE_ATTACKED` pulse and exile event.
8. Add or extend a multi-target fixture and assert one cue per initially valid
   target in the same canonical order as attack resolution.
9. Assert invalid/stale attacker or target identities emit no cue.
10. Update existing exact event arrays/counts while leaving all next-state,
    capture, exile, ki, and turn assertions unchanged.
11. Run the simulator suite and confirm the new expectations fail before the
    implementation.

## Task 2: Emit the canonical presentation event

**Files:**
- Modify: `scripts/duel_simulator.gd`

1. In `_resolve_attack_target()`, keep the existing initial
   `_attack_is_valid()` guard as the single admission check.
2. Build `attack_started` from the validated source and target slots before
   resolving `Catalog.CARD_BE_ATTACKED`.
3. Append the event to the result before any pre-attack trigger events.
4. Use the existing attack `reason` unchanged as `attack_reason`.
5. Keep the post-trigger revalidation, normal flip, after-flip triggers,
   captures, exiles, and extra-turn requests unchanged.
6. Do not add the event to the catalog vocabulary, `DuelState`, state keys,
   legal-action generation, evaluator, or search.
7. Run simulator and search suites; confirm state/search behavior is unchanged.

## Task 3: Build the reusable procedural overlay test-first

**Files:**
- Create: `scripts/attack_vfx.gd`
- Modify: `scenes/duel.tscn`
- Modify: `tests/test_duel_integration.gd`

1. Add an integration fixture for a full-canvas, input-transparent
   `DuelCanvas/AttackVfx` control with a z-index above board cards and below
   `ExtraTurnVfx`, `DragLayer`, and modal UI.
2. Define a serialized API:
   `play_attack(source_global_rect, target_global_rect, duration, ink_color)`.
3. Convert both global rectangles into overlay-local coordinates.
4. Derive the normalized source-to-target center vector.
5. Intersect that vector with the source rectangle and its reverse with the
   target rectangle; inset both edge points slightly into their respective
   cards.
6. Keep the ray/rectangle intersection vector-based. Do not branch on board
   indices, adjacency, cardinal directions, or cell size.
7. Build a deterministic tapered brush body and gray-brown flying-white
   fragments once per playback.
8. Build exactly three restrained deterministic ink flecks near the
   target-facing end.
9. Reveal source-to-target, hold, and fade over the configured duration, using
   the approved approximate `0.06 / 0.035 / 0.055` second phase proportions.
10. Serialize overlapping calls, avoid per-frame random generation, and clear
    every temporary array/flag after completion.
11. For zero duration, still prepare geometry, record playback, finish all
    phases, and clean up without waiting.
12. Expose narrow debug observations for tests: playback count, last start/end,
    last fleck count, and clean/playing state.
13. Test left, right, up, down, diagonal, and synthetic non-neighbor
    rectangles; assert both endpoints lie just inside their facing edges and
    the stroke points source-to-target.
14. Test exactly three flecks, zero-duration cleanup, serialization, and
    `MOUSE_FILTER_IGNORE`.

## Task 4: Present attacks in transition order

**Files:**
- Modify: `scripts/duel_controller.gd`
- Modify: `tests/test_duel_integration.gd`

1. Preload/type and bind `DuelCanvas/AttackVfx`.
2. Add exported attack duration and ink color settings; set duration to zero in
   `debug_set_fast_mode(true)`.
3. Add a debug-observable attack playback trace keyed by source and target
   instance IDs.
4. Handle `attack_started` in `_present_transition_events()` before the
   existing `ability_triggered`, exile, and flip branches.
5. Resolve both views by stable instance ID, not stored child order or cell
   alone.
6. If both views exist and remain valid, get their live global rectangles,
   append the trace, and await `AttackVfx.play_attack()`.
7. If either view is missing, skip immediately without fabricating geometry or
   delaying later events.
8. Rename `capture_step_delay` to `capture_flip_duration` so its remaining
   purpose is explicit.
9. Remove only the silent timer before `card_flipped`; retain capture audio,
   capture flip animation, ownership synchronization, ability-loss animation,
   and draw-to-board spacing.
10. Test the ordered presentation traces:
    - normal: attack cue before flip;
    - reaction: source pulse before attack cue, then flip;
    - intercepted attack: attack cue before target pulse and exile;
    - activation: movement before attack cue;
    - multi-target: one fully awaited cue/outcome sequence per target.
11. Test missing source/target views and confirm later events still present.

## Task 5: Document and verify the completed feature

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/DECISIONS.md`
- Modify: `docs/TESTING.md` if check counts change

1. Document `attack_started` as presentation-only transition data emitted before
   `CARD_BE_ATTACKED`.
2. Record that every initially valid attack receives the cue even if a later
   rule exiles or otherwise redirects its outcome.
3. Record vector-based, non-neighbor-compatible geometry and the exact
   three-fleck visual rule.
4. Run script-error checks for every changed GDScript.
5. Run `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`.
6. Start the duel at normal speed and manually play:
   ordinary capture, CangSong reaction, Gate/Tiger interception, movement
   activation, and a multi-target summon.
7. Confirm strokes begin and end just inside facing card edges, cross the
   current narrow seam, point toward targets, serialize cleanly, and leave no
   residual overlay.
8. Inspect the fresh runtime console/debugger for errors.
9. Run `git diff --check`, inspect `git status --short`, and preserve all
   unrelated user-owned changes.
10. Commit only the implementation, tests, and focused documentation.
