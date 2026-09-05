# Native Kernel Source Split Design

## Goal

Split the monolithic `DuelNativeCompactKernel` implementation into focused C++
translation units without changing gameplay, search behavior, public APIs, data
layout, or runtime ownership.

## Approach

Keep `DuelNativeCompactKernel` as the single Godot-facing class and retain its
existing header for the first phase. Move existing member-function definitions
mechanically into implementation files grouped by stable responsibility:

- `duel_native_compact_kernel.cpp`: Godot binding, payload loading, public
  transition entry points, and result materialization.
- `duel_native_search.cpp`: evaluation, action ordering, history, PV,
  transposition-table handling, and iterative/fixed-depth search.
- `duel_native_compile.cpp`: declaration parsing, compilation, and support
  validation.
- `duel_native_policy.cpp`: runtime ability queries, activation targeting, and
  attack-policy construction.
- `duel_native_resolution.cpp`: attack, summon, flip, and direct resolution
  lifecycles.
- `duel_native_events.cpp`: event discovery, conditions, selectors, and event
  dispatch.
- `duel_native_actions.cpp`: compiled-action execution and concrete state
  mutations.
- `duel_native_lifecycle.cpp`: movement, turn completion, terminal handling,
  state export, and checksum calculation.

Small implementation helpers shared by multiple translation units move into a
private internal header. They remain internal-linkage inline helpers and do not
become part of the GDExtension API.

## Constraints

- Do not rename methods, change signatures, reorder event processing, or alter
  algorithms.
- Do not split the kernel into new runtime classes in this phase.
- Do not change native state layout or public Godot bindings.
- Explicitly list every new source file in CMake.
- Preserve unrelated user-owned files and changes.

## Verification

1. Build the Windows Release native library using the existing template-debug
   ABI.
2. Run the full canonical test suite.
3. Confirm the split does not introduce duplicate or missing member definitions.
4. Review the diff as a mechanical relocation plus build-list update only.

Performance should be unchanged at runtime. The expected gains are code
navigability, smaller incremental rebuilds, and reduced edit conflicts.
