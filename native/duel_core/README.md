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

- accepts one coarse compact-state payload;
- converts packed Godot arrays into owned C++ vectors;
- validates the documented array shape;
- measures native core cloning without crossing the language boundary per
  iteration.

It deliberately does not implement legal actions, triggers, card declarations,
state keys, evaluation, or transitions yet. The existing simulator remains the
oracle for every future native primitive.
