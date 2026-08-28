# Benchmark Minimum Completed Depth Design

**Status:** Approved for implementation
**Date:** 2026-08-28

## Goal

Keep the deterministic 1,500-node Quick/Extended comparison budget while
preventing the complete-round search from falling back merely because depth one
costs more than 1,500 nodes.

For node-limited benchmarks, both Baseline and LazyOnly must finish
complete-round depth one before the node limit may stop them. After depth one,
the existing node count remains the shared budget: if fewer than 1,500 nodes
have been visited, search continues into depth two until the total reaches
1,500; if depth one already used 1,500 or more, search returns immediately.

## Scope

The minimum-depth guard is opt-in search configuration used by node-limited AI
benchmarks:

- Quick;
- Pilot;
- Extended;
- focused benchmark tests that explicitly request it.

Production remains governed by its ten-second hard deadline and does not set
the guard. Ordinary search tests and other `max_nodes` callers retain their
current hard-node-limit behavior unless they opt in explicitly.

No evaluator, move ordering, simulator rule, card declaration, production
search budget, or benchmark matchup changes.

## Search Limit Contract

The search limits dictionary gains:

```gdscript
"min_completed_depth": 1
```

The default is zero. A zero or missing value preserves the current behavior.
The normalized value is clamped to zero or greater.

The search context records the deepest fully completed iteration. The node
stop condition becomes:

```text
if nodes >= max_nodes
and completed_depth >= min_completed_depth:
    stop with node_limit
```

While `completed_depth < min_completed_depth`, reaching `max_nodes` marks that
the minimum-depth guard was used but does not abort the iteration. Node checks
continue normally, so the search stops promptly when the protected iteration
finishes and the next iteration begins.

Example with `max_nodes = 1500` and `min_completed_depth = 1`:

- depth one finishes at 900 nodes: depth two begins and stops at 1,500;
- depth one finishes at 1,500 nodes: depth two immediately observes the limit
  and the depth-one result is returned;
- depth one finishes at 2,200 nodes: the 700-node overrun is retained in the
  report and depth two stops before searching a child;
- the whole game tree is solved during depth one: the solved result returns
  normally without starting another iteration.

The guard does not turn 1,500 into a fresh post-depth-one allowance. Total
nodes are never reset.

## Hard Stops

The minimum-depth guard softens only `max_nodes`.

These conditions remain hard and may interrupt depth one:

- explicit cancellation;
- worker/thread failure;
- a deadline when a caller supplies one;
- scene shutdown or process termination.

A root state with no legal action retains the existing no-action result. The
guard does not fabricate a completed depth or an action.

Node-limited Quick, Pilot, and Extended do not normally supply a deadline, so a
valid finite depth-one tree is allowed to finish even when it substantially
exceeds 1,500 nodes. Existing gameplay safeguards remain authoritative inside
every simulator transition.

## Fairness

Baseline and LazyOnly receive identical limits, including the same minimum
completed depth. The benchmark still compares the algorithms on the same
states, decks, owners, seeds, and total nominal node budget.

The actual work may differ because each algorithm can require a different
number of nodes to finish depth one. That difference is intentional and must be
reported rather than hidden: a complete minimax result at the common semantic
horizon is more meaningful than comparing unrelated greedy fallbacks.

All variants use the guard. `LazyOnly` continues to mean lazy transitions on,
PVS/tactical extension/evaluation cache off, and the baseline evaluator.

## Diagnostics and Reports

Search results add:

```text
min_completed_depth
minimum_depth_guard_used
nodes_over_limit
```

Definitions:

- `min_completed_depth`: normalized configured minimum;
- `minimum_depth_guard_used`: true when the node count reached the nominal
  limit before the protected minimum depth completed;
- `nodes_over_limit`: `max(nodes - max_nodes, 0)` for a positive node limit,
  otherwise zero.

Benchmark decision records preserve these fields. Summary data reports, for
each profile:

- number and percentage of decisions using the guard;
- total and maximum nodes over the nominal limit;
- ordinary fallback rate and completed-depth distribution.

The report continues to store `limits.max_nodes = 1500` and additionally stores
`limits.min_completed_depth = 1`. A result must not describe the run as a hard
1,500-node cap.

## Benchmark Wiring

The fixed Extended constant remains 1,500. Quick, Pilot, and Extended add
`min_completed_depth = 1` beside their node limit. Production adds nothing.

The previously aborted 1,500-node Extended LazyOnly run is not evidence and
produced no final JSON. The next benchmark is the real Extended LazyOnly run;
there is no separate Pilot prerequisite. Extended exposes enough evidence after
every completed game to observe actual overruns and estimate remaining runtime
without running a second calibration schedule.

## Extended Per-Game Progress

Extended reports progress after each individual game, not only after each
four-game matchup. The total game count is calculated before play by expanding
the selected matchup manifest, so every progress record can show `game_index`
and `total_games` even if the manifest changes later.

After a game returns a complete result, the benchmark performs these steps in
order:

1. add the game to the in-memory final report;
2. append one compact JSON object to the progress checkpoint and close it;
3. print one stable `AI_BENCHMARK_GAME` progress line;
4. continue to the next game.

The progress line includes:

- completed and total games;
- game and matchup identifiers;
- this game's elapsed time, cumulative elapsed time, and a simple projected
  remaining duration based on completed games;
- this game's Enhanced match points and cumulative match-point percentage;
- terminal and invalid status;
- per-profile decision count, fallback count, completed-depth distribution,
  minimum-depth-guard count, and total/max node overrun.

The line is diagnostic only. It does not apply the Extended pass gate early,
change the schedule, stop the run, or alter the fixed soft 1,500-node tier.

## Incremental Checkpoint

At process startup, Extended chooses one timestamped artifact stem shared by
the final report and checkpoint. The checkpoint is newline-delimited JSON at:

```text
.summer/local/ai-benchmarks/extended-<variant>-v<version>-<timestamp>.progress.jsonl
```

Each line is an independently parseable record for exactly one completed game.
It contains:

```text
schema_version
mode
variant
game_index
total_games
game_id
matchup_id
terminal
invalid_reason
actions
enhanced_match_points
cumulative_enhanced_match_points
cumulative_enhanced_match_points_percent
game_elapsed_seconds
cumulative_elapsed_seconds
projected_total_seconds
profile_diagnostics
```

`profile_diagnostics` stores the same compact per-profile counts used by the
console line: decisions, fallbacks, completed-depth distribution, guard uses,
total nodes over the nominal limit, maximum nodes over the limit, and total
visited nodes. It does not duplicate full decision records or serialized game
states; those remain in the final report.

The checkpoint append happens only after the full game result exists. Opening,
appending one line, and closing the file is the durability boundary, preventing
an interrupted later game from corrupting earlier records. A terminally invalid
or watchdog-limited game is still a completed result and receives a checkpoint
line. A crash before a game returns produces no line for that game.

On successful completion, the full JSON report is written once under the same
artifact stem and records the checkpoint path and progress schema version. The
checkpoint is retained as an audit trail. If the process is interrupted, the
checkpoint remains useful progress evidence, but a partial checkpoint is never
treated as a final benchmark or used to evaluate the Extended pass gate.

## Live Console Delivery

The current PowerShell launcher redirects both child streams to temporary
files and prints them only after Summer exits. Therefore Godot-side per-game
`print()` calls alone are insufficient.

The launcher keeps redirection for reliable exit/error inspection but tails the
growing output files while the child is running and forwards each newly
completed line immediately. It waits without a tight busy loop, drains both
streams after process exit, and preserves the existing nonzero-exit and
`AI_BENCHMARK_FAILED`/script-error detection. It must not print any line twice.

This gives an interactive console immediate per-game output. The JSONL file is
the authoritative source for detached or externally monitored runs because it
is structured and survives interruption.

## Verification

### Search

1. With only `max_nodes = 1`, depth one still aborts and exposes no partial
   result, preserving the default hard limit.
2. With `max_nodes = 1` and `min_completed_depth = 1`, depth one completes and
   returns no fallback.
3. If depth one completes below the node limit, depth two begins and stops at
   the shared total limit.
4. If depth one completes above the limit, depth two performs no child search.
5. A cancelled protected depth-one iteration still aborts immediately.
6. A protected search with a deadline still respects the deadline.
7. A solved depth-one tree returns solved rather than `node_limit`.
8. Diagnostic fields accurately report guard use and overrun nodes.

### Benchmark

9. Quick, Pilot, and Extended configure `max_nodes = 1500` and
   `min_completed_depth = 1` where applicable; Production does not.
10. Baseline and every Enhanced variant receive the identical guard.
11. Decision records and summaries preserve guard-use and overrun diagnostics.
12. A focused benchmark fixture that previously fell back at a tiny node limit
    completes depth one for both profiles.
13. Extended appends exactly one independently parseable checkpoint record per
    completed game, including terminally invalid results.
14. Extended prints one `AI_BENCHMARK_GAME` line per completed game with the
    correct index, cumulative points, timing estimate, and profile diagnostics.
15. A deliberately interrupted run leaves every previously appended line valid
    and writes no partial record for the interrupted game.
16. A completed run writes its final JSON under the checkpoint's artifact stem
    and references that checkpoint.
17. The PowerShell launcher exposes a child progress line before process exit,
    drains the final lines, and emits no duplicates.

### Regression

18. Search, benchmark, simulator, and integration suites pass.
19. The canonical full suite passes.
20. The real Extended LazyOnly run is launched directly after verification. Its
    per-game checkpoint and console records provide overrun and ETA evidence;
    no separate Pilot is required.

## Expected Implementation Surface

- `scripts/duel_search.gd`: minimum-depth-aware node stop and diagnostics;
- `tests/benchmarks/duel_ai_benchmark.gd`: benchmark limits, aggregate
  reporting, per-game progress records, and checkpoint output;
- `tools/run_ai_benchmark.ps1`: live child-output forwarding while retaining
  complete error detection;
- `tests/test_duel_search.gd`: protected-depth and hard-stop coverage;
- `tests/test_duel_ai_benchmark.gd`: mode and report coverage;
- `docs/AI_SEARCH.md`, `docs/TESTING.md`, and `docs/HANDOFF.md`: durable behavior
  and workflow notes after implementation.

No production controller or simulator change is required.
