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

## Godot 4.7 binding compatibility

The pinned Godot 4.7 `godot-cpp` generator implements `Dictionary` move
assignment as a copy into the destination's already initialized storage. Its
generated implementation omits destruction of the previous destination and
therefore leaks one Dictionary reference whenever code assigns a temporary
Dictionary, including every native search transition's deep-copied side
payload.

`godot_cpp_binding_hooks.py` is passed to the supported
`GODOTCPP_BINDING_HOOK_FILE` generator hook and inserts the missing destructor
before that copy. This applies to Windows and Android generated bindings. Keep
the hook until the pinned generator itself emits an equivalent release; verify
any upgrade with the repeated native-search memory regression in
`test_native_production_rules.gd`.

## Runtime scope

The kernel:

- owns a compact representation of board, both hands, decks, discard/removed
  zones, runtime abilities, turn state, memory, revelation, and difficulty
  latches;
- compiles immutable catalog declarations and catalog-fresh prototypes once per
  loaded root;
- enumerates and validates hand plays and catalog-ordered activations, and
  exposes the same legality, terminal, score, greedy, and board-attack queries
  used by the GDScript facades and focused fixtures;
- resolves the full summon, attack, flip, exile, discard, draw, transform,
  return, movement, swap, suppression, and turn-boundary lifecycles;
- discovers full-board trigger groups in deterministic row-major order and
  preserves stable trigger identity while earlier abilities move or disappear;
- executes recursive generic conditions, selectors, costs, actions, and
  generated attacks/summons without named-card branches;
- returns complete compact state plus ordered pure-data events, captures, and
  exiles for controller presentation;
- exposes direct event/action/attack/non-attack-flip adapters used by focused
  semantic fixtures, all through the same production primitives;
- performs complete-round iterative deepening, structural ordering, alpha-beta
  pruning, hard deadline/node checks, minimum-depth guard diagnostics,
  cancellation, completed-depth snapshots, and same-owner principal actions;
- reuses exact-depth `EXACT`/`LOWER`/`UPPER` results through a fixed two-way
  transposition table. Production allocates at most 8 MiB per root decision on
  desktop and Android and releases it when that decision ends.

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

- The transposition table is deliberately local to one root decision and does
  not reuse deeper entries for a different remaining owner-turn depth.
- New declaration vocabulary must add native compilation/execution and focused
  tests before catalog use.
- Windows Debug and Release behavior is covered locally. Android ARM64 and
  release-package performance must be measured independently before distribution.
