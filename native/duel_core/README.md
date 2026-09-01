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
- compiles all eight current activation target rules, enumerates legal runtime
  activations, validates cumulative ki costs and exact targets, and executes
  activation transactions through the shared action/turn lifecycle;
- supports targeted move/swap/reveal, generated re-summon, ki distribution,
  public fresh/perfect hand copies, and referenced-card standard attacks as
  generic actions reached by current catalog activations;
- returns a full compact payload plus the same capture/exile/event arrays as
  `DuelSimulator`;
- uses an action-specific conservative gate and atomically rejects any reached
  future declaration that has not been compiled instead of approximating it;
- measures native core cloning, plain hand-play transitions, and a fixed
  activation transaction.

The current probe reports 490/490 exact hand-play transitions in the 14 real
Quick openings, 36/36 legal actions covering all 20 catalog activation
declarations, and 104/104 activation actions across 136 deterministic
Quick-derived states. It deliberately does not implement state keys,
evaluation, a complete native search tree, or production integration yet.
Future declaration vocabulary remains outside the slice until separately
proven. Production does not call the extension. The probe compares every
covered state field and ordered event against `DuelSimulator`, which remains
the oracle for every native primitive.
