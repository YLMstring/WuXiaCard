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
- resolves one test-only generic transition slice: normalized, ability-free
  hand play, ordinary orthogonal power comparison, standard attack, ownership
  flip, hand-play memory, turn boundary, empty-turn advancement, action-limit,
  full-board, and fivefold-repetition terminal checks;
- returns a full compact payload plus the same capture/exile/event arrays as
  `DuelSimulator`;
- explicitly rejects states with abilities, temporary suppression, extra
  plays, pending choices/effects, special negative powers, or difficulty 8/9
  hand rules instead of approximating them;
- measures native core cloning and the covered transition slice.

It deliberately does not implement the general ability executor, targeting,
draw/discard/exile/movement primitives, state keys, evaluation, or search yet.
Production does not call it. The probe compares every covered state field and
event against `DuelSimulator`, which remains the oracle for every native
primitive.
