# Real Quick Search Equivalence Diagnostic

## Goal

Verify that the search optimizations used by the AI preserve fixed-depth minimax
results on every distinct opening state in the real Quick enemy schedule.

## Scope

- Read the seven Quick matchups from `EnemyAIBenchmarkManifest`.
- Expand their 28 balanced games and rebuild them with
  `EnemyAIBenchmarkStateFactory`.
- Deduplicate by canonical initial-state key while preserving manifest order.
- Require exactly 14 distinct opening states.
- Make no production gameplay or search changes.
- Keep this diagnostic out of the daily 68-suite runner because unrestricted
  depth-three searches may be expensive.

## Search Configurations

Each opening is searched from its active owner to fixed depth three, without a
node limit, deadline, or time budget. All configurations use the baseline
evaluator, disable the evaluation cache, and disable tactical extension.

1. **Baseline:** eager transitions and ordinary alpha-beta.
2. **Lazy-only:** lazy transitions with PVS disabled.
3. **Lazy+PVS:** lazy transitions with PVS enabled.

## Required Equivalence

For each opening, all three configurations must produce:

- the same completed depth;
- the same minimax score;
- the same canonical root action.

The diagnostic fails if any result is missing, falls short of the fixed depth,
or differs. A failure prints the matchup, initial-state key, profile label,
completed depth, score, and canonical action so the exact real fixture can be
reproduced.

## Location and Invocation

Implement the standalone SceneTree diagnostic at
`tests/benchmarks/real_quick_search_equivalence.gd`. Run it directly through
Summer Engine in headless mode with the Dummy audio driver. A successful run
prints one summary marker containing the number of openings and comparisons;
any mismatch exits nonzero.

## Verification

1. Run the standalone diagnostic to completion and inspect every mismatch.
2. Run `test_duel_search.gd` to ensure the existing synthetic fixed-depth
   equivalence checks still pass.
3. Run `test_duel_ai_benchmark.gd` to ensure manifest and state-factory
   contracts still pass.
