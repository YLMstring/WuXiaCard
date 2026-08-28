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
produced no final JSON. After implementation and focused verification, run a
small Pilot first to measure the real overrun distribution and projected
Extended duration. Report that evidence to the user before launching another
112-game Extended run.

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

### Regression

13. Search, benchmark, simulator, and integration suites pass.
14. The canonical full suite passes.
15. A post-change Pilot reports zero ordinary node-limit fallback unless a
    hard stop or invalid state occurs, and provides enough timing evidence to
    estimate the next Extended run before it is launched.

## Expected Implementation Surface

- `scripts/duel_search.gd`: minimum-depth-aware node stop and diagnostics;
- `tests/benchmarks/duel_ai_benchmark.gd`: benchmark limits and aggregate
  reporting;
- `tests/test_duel_search.gd`: protected-depth and hard-stop coverage;
- `tests/test_duel_ai_benchmark.gd`: mode and report coverage;
- `docs/AI_SEARCH.md`, `docs/TESTING.md`, and `docs/HANDOFF.md`: durable behavior
  and workflow notes after implementation.

No production controller or simulator change is required.
