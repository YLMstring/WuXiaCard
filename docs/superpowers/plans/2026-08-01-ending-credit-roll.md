# Compact Ending Credit Roll Implementation Plan

**Spec:** `docs/superpowers/specs/2026-08-01-ending-credit-roll-design.md`

## Objective

Move all ending content into the clear sky beneath the title and above the
arena. Keep a smaller score fixed, clip a smaller story beneath it, roll only
the amount of hidden story text upward, ignore early taps, and enable the
existing return request only after the final line is fully visible.

## Task 1: Record the current baseline

**Files**

- Inspect only

1. Preserve the creator's latest ending prose changes.
2. Run `test_ending_scene.gd` and record its current passing checks.
3. Run the full suite and confirm the same four known stale suites fail.
4. Do not repair unrelated catalog, library-grid, deck-builder, or duel-test
   expectations.

## Task 2: Specify the compact scene hierarchy

**Files**

- Modify `tests/test_ending_scene.gd`
- Modify `scenes/ending.tscn`

Add failing checks for a dedicated `StoryClip` Control that clips children and
contains the story Label. Keep Score outside that clip so it cannot move with
the roll. Check that score and clip rectangles stay inside the main-menu safe
area, the arena-facing lower area is unused, and the title-to-score gap is
positive and substantial.

Run the ending-scene suite to demonstrate the hierarchy tests fail before the
scene change.

## Task 3: Implement measured story overflow and motion

**Files**

- Modify `scripts/ending_controller.gd`
- Modify `tests/test_ending_scene.gd`

Add an exported logical-pixel scroll speed. Track current offset, maximum
offset, and completion state. After applying text and after layout changes:

1. measure the wrapped Label's rendered minimum height;
2. size the Label to that height;
3. compute `max(content_height - clip_height, 0)`;
4. clamp current offset to the new maximum; and
5. place the story at local Y `-current_offset`.

Advance offset from `_process(delta)` only while overflow remains. Clamp at the
maximum and stop processing when the final line is fully visible. Short text
completes immediately.

Expose read-only debug accessors and one deterministic debug advance method so
tests can verify motion without wall-clock waits. Test upward movement, exact
final clamping, score immobility, no movement after completion, and safe resize
recomputation.

## Task 4: Lock navigation until the roll completes

**Files**

- Modify `scripts/ending_controller.gd`
- Modify `tests/test_ending_scene.gd`
- Verify `tests/test_ending_flow.gd`

Consume mouse/touch releases during the roll without emitting
`return_requested`. Once the roll is complete, keep the existing emit-once
behavior. Update the scene test to prove an early tap does nothing and a final
tap returns exactly once. In flow integration, force the ending roll to its
completed state before emitting the return interaction so the navigation test
continues to exercise the production gate.

## Task 5: Tune the compact safe-area layout

**Files**

- Modify `scripts/ending_controller.gd`
- Modify `tests/test_ending_scene.gd`

Lay out content from the fixed 9:16 safe rectangle:

- leave breathing room after the existing title;
- place the fixed score below that gap;
- use approximately 60 percent of the former score font size;
- place a clipped story viewport immediately below the score;
- reduce story font slightly while keeping `language = "zh"` and smart wrap;
  and
- end the story viewport above the painted arena.

Assert layout at portrait and wide host sizes. Keep all ratios and clamps in
named constants so later visual tuning is localized.

## Task 6: Update focused documentation

**Files**

- Modify `docs/ARCHITECTURE.md`
- Modify `docs/DECISIONS.md`
- Modify `docs/HANDOFF.md`
- Modify `docs/TESTING.md`

Document the clipped scene hierarchy, measured constant-speed roll, early-tap
lock, completion gate, and tuning/test points. Do not change progression or
ending-content rules.

## Task 7: Verify and playtest

1. Run `test_ending_scene.gd`, `test_ending_flow.gd`, and `test_main_flow.gd`.
2. Run `git diff --check` and the full test runner; confirm only the recorded
   four stale suites fail.
3. Run the ending scene visibly at a portrait reference size and a wide host
   size.
4. Verify the title remains unchanged, the breathing gap is clear, score stays
   fixed, story is clipped above the arena, and final text stops fully visible.
5. Probe early input, completed input, and repeated taps; confirm only one
   post-roll return request is emitted.
6. Inspect fresh runtime diagnostics, then commit the implementation.
