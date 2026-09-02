# Duel Native Core

This directory contains the single production rules and deep-search kernel.
`DuelSimulator` and `DuelSearch` remain the public GDScript facades, but every
authoritative transition and descendant search node resolves through
`DuelNativeCompactKernel`.

The pinned `godot-cpp` submodule targets Godot 4.7. Build the ignored Windows
x86-64 editor/test binary with:

```powershell
powershell -ExecutionPolicy Bypass -File tools/build_duel_native.ps1
```

Build the release-package ABI with:

```powershell
powershell -ExecutionPolicy Bypass -File tools/build_duel_native.ps1 `
  -GodotCppTarget template_release
```

Build products and the generated `.gdextension` live under `bin/` and are
ignored by Git. CMake intermediates live under
`.summer/local/native-build/` so Godot does not import compiler objects.

## Runtime scope

The kernel:

- owns a compact representation of board, both hands, decks, discard/removed
  zones, runtime abilities, turn state, memory, revelation, and difficulty
  latches;
- compiles immutable catalog declarations and catalog-fresh prototypes once per
  loaded root;
- enumerates and validates hand plays and catalog-ordered activations;
- resolves the full summon, attack, flip, exile, discard, draw, transform,
  return, movement, swap, suppression, and turn-boundary lifecycles;
- discovers full-board trigger groups in deterministic row-major order and
  preserves stable trigger identity while earlier abilities move or disappear;
- executes recursive generic conditions, selectors, costs, actions, and
  generated attacks/summons without named-card branches;
- returns complete compact state plus ordered pure-data events, captures, and
  exiles for controller presentation;
- exposes direct event/attack/non-attack-flip adapters used by focused semantic
  fixtures, all through the same production primitives;
- performs complete-round iterative deepening, structural ordering, alpha-beta
  pruning, hard deadline/node checks, minimum-depth guard diagnostics,
  cancellation, completed-depth snapshots, and same-owner principal actions.

Unsupported reached declarations reject atomically. They must never be
approximated or passed to a second rules engine.

## Authority and retirement boundary

The independently maintained GDScript rules/search Oracle was removed on
2026-09-02 after the final deterministic seal passed 4,812 checks across 56
walks and 584 actions. Its recoverable endpoint is commit `e68885d`. Do not
restore it as a runtime fallback or require new card work to maintain two
engines.

Current correctness comes from native catalog audits, fine-grained semantic
fixtures, complete-runtime card/action fixtures, production search contracts,
controller integration tests, and the full suite. See `docs/AI_SEARCH.md` and
`docs/TESTING.md`.

## Known limits

- Native transpositions are not implemented.
- New declaration vocabulary must add native compilation/execution and focused
  tests before catalog use.
- Windows Debug and Release behavior is covered locally. Android ARM64 and
  release-package performance must be measured independently before distribution.
