# Duel Native Compact Prototype

This directory contains an opt-in GDExtension experiment. It does not replace
`DuelSimulator` and is not loaded by a clean checkout until it is built.

The pinned `godot-cpp` submodule targets the Godot 4.6 extension API. Build the
Windows x86-64 prototype with:

```powershell
powershell -ExecutionPolicy Bypass -File tools/build_duel_native.ps1
```

Run the native layout/clone probe with:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_native_compact_probe.ps1
```

Build products and the generated `.gdextension` file live under `bin/` and are
ignored by Git. CMake intermediates live under `.summer/local/native-build/`
so Godot never mistakes MSVC `.obj` files for importable Wavefront models.

Current scope:

- accepts one coarse full compact-state payload while retaining the earlier
  mutable-core clone probe;
- converts packed Godot arrays into owned C++ vectors;
- validates the documented array shape;
- resolves test-only generic normalized hand plays, including ordinary
  orthogonal power comparison, standard attack, ownership flip, hand-play
  memory, turn boundaries, empty-turn advancement, and terminal checks;
- compiles immutable ability declarations once per loaded compact root and
  stores each runtime card's ordered ability entries with transient trigger
  handles, so real removal and later-entry index shifts preserve oracle trigger
  semantics;
- executes those draws sequentially from the deck front, fills the physical
  leftmost hand slot, and reconstructs complete `card_drawn` snapshots before
  standard attacks;
- recursively compiles nested actions and executes generic selectors over the
  board, hand, deck, and discard using snapshot-then-revalidate/no-refill
  targeting;
- resolves fixed and dynamic power changes, power-change batches, four-zero
  exile, ki gain/spend and immediate ki-change triggers, non-attack flips, and
  dynamic passive or activation grants;
- carries immutable catalog-fresh prototypes at the compact root and supports
  ordinary board returns by appending a fresh public hand instance while
  retaining the destroyed old index as an unreferenced tombstone; full hands
  use the normal exile lifecycle;
- expands those prototypes through the deterministic transitive closure of
  reachable transform targets, then rebuilds transformed runtime cards in
  place without changing instance identity, ownership, zone, or visibility;
- executes strict conditional action lists with list-local mutable context,
  including source-owner empty-hand and actual discard-batch-size checks;
- resolves single and batch discard as one snapshot/no-refill transaction,
  emits canonical batch identities and one physical-slot shift, dispatches
  discarded-card self triggers before the global batch-finished event, and
  preserves the original ability-source snapshot through those nested events;
- returns preserved discard instances to the leftmost hand slot, reveals them
  publicly only when needed, and exiles the same instance when the hand is full;
- resolves `self_swapped_with_ability_source` as two ordered movements, with
  global before/after movement events, exact instance/owner revalidation, and
  mover-removal cancellation;
- returns a full compact payload plus the same capture/exile/event arrays as
  `DuelSimulator`;
- uses an action-specific conservative gate and explicitly rejects relevant
  unsupported summon/draw/attack/turn declarations, generated empty-deck
  draws, temporary suppression, extra/nested attacks, non-swap movement,
  pending choices/effects, or
  difficulty 8/9 hand rules instead of approximating them;
- measures native core cloning and the covered transition slice.

It deliberately does not implement the remaining action/condition vocabulary,
generated empty-deck draws, summon/general movement and extra-attack
primitives, start/end-turn lifecycle, state keys, evaluation, or search yet.
Production does not call it. The probe compares every covered state field and
event against `DuelSimulator`, which remains the oracle for every native
primitive.
