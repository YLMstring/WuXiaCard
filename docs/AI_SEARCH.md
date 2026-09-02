# AI Search

## Current authority

There is one production rules implementation and one production deep-search
implementation: `DuelNativeCompactKernel` in `native/duel_core/`.

- `scripts/duel_simulator.gd` is the public rules facade for human play,
  testing mode, replay, greedy fallback, and AI actions.
- `scripts/duel_native_rules.gd` converts `DuelState` to the compact native
  payload and restores pure-data states and events.
- `scripts/duel_search.gd` normalizes public search results and delegates the
  complete descendant tree to the native kernel.
- `scripts/duel_search_session.gd` owns the worker thread, cancellation, and
  progress transport.

The former independent GDScript rules/search Oracle was retired on 2026-09-02.
Do not add a second transition engine or a fallback that silently resolves a
native rejection through GDScript. The last passing pre-removal seal is
recoverable from commit `e68885d`; it passed 4,812 checks across 56 deterministic
walks and 584 actions. That commit is recovery evidence, not an implementation
to keep synchronized.

## Information model

The opponent has perfect simulation information: both complete hands and exact
deck order. Concealment is presentation-only. Search remains card-agnostic and
may evaluate generic ownership, zones, powers, ki, legal actions, and active
ability counts, but it must never branch on a named `card_id`.

The native kernel loads one isolated root, compiles immutable catalog
declarations, and keeps legal-action enumeration, branch copies, rules
resolution, evaluation, ordering, alpha-beta traversal, and iterative deepening
inside C++. Only completed-depth progress, the chosen action, and the current
owner's principal continuation cross back to GDScript.

## Depth and publication

Search depth is measured in authoritative `owner_turn_serial` boundaries, not
action plies. Two selectable modes share the same native search implementation:

- `complete_round` is the current production default. Public depth `d` consumes
  `2 × d` boundaries: depth one finishes the current owner's remaining turn and
  the following opponent turn.
- `self_turn` is an opt-in comparison mode. Public depth `d` consumes
  `2 × d - 1` boundaries: depth one finishes the current owner's remaining
  turn; depth two additionally finishes the opponent turn and the root owner's
  next turn.

Automatic empty turns consume the boundaries they actually cross and do not
add artificial depth. Same-turn extra plays add work but no boundary.

Iterative deepening publishes only the deepest fully completed iteration. An
incomplete deeper attempt is diagnostic data and never replaces the last
complete action. Production uses a hard ten-second deadline. Node-limited
Quick and Extended diagnostics use `min_completed_depth = 1`: a nominal node
limit may be exceeded until depth one completes, while deadlines and explicit
cancellation remain hard.

If no iteration completes, the worker fails, or the returned action is stale or
illegal, the controller uses deterministic greedy fallback. Search may finish
early when the position is solved.

## Same-turn continuation

The completed principal line may include additional actions by the same owner
within the current `owner_turn_serial`. `DuelTurnPlan` reuses them without a new
thinking pause only while all of these still match:

- exact compact state key;
- owner ID;
- owner-turn serial;
- current legality of the next action.

Any mismatch clears the remainder and starts a normal fresh search.

## Search result contract

`DuelSearch.find_best_action_iterative()` is the public entry point.
`find_best_action_iterative_native()` is retained as an explicit compatibility
alias for native-focused tests, not as a different algorithm.

The result includes at least:

- `action`, `score`, `completed_depth`, and `has_completed_depth`;
- `nodes`, generated/applied transition counts, cutoffs, and root progress;
- completion reason and elapsed time;
- minimum-depth guard/overrun diagnostics;
- completed-depth snapshots and `turn_plan`.

Legacy profile fields may still appear in report schemas, but they no longer
select the removed GDScript PVS, tactics, evaluation cache, or evaluator
variants. Add future native strategies as explicit native features with tests;
do not revive the old backend switch.

## Correctness gates

Rules and search changes require:

1. focused native simulator fixtures for the changed semantics and ordered
   events;
2. catalog declaration coverage and strict unsupported-declaration audits;
3. `test_duel_simulator.gd`, `test_native_production_rules.gd`, and
   `test_duel_search.gd`;
4. controller integration coverage when transition presentation changes;
5. the full canonical suite;
6. a silent production-path playtest.

Native rejection is an integration fault, not permission to approximate a
transition or fall back to another engine.

## Benchmarks

Run the real enemy-catalog benchmark with Dummy audio:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_ai_benchmark.ps1 -Mode Quick
powershell -ExecutionPolicy Bypass -File tools/run_ai_benchmark.ps1 -Mode Extended
powershell -ExecutionPolicy Bypass -File tools/run_ai_benchmark.ps1 -Mode Production
```

- Quick: 7 matchups / 28 games, nominal 1,500 nodes per decision.
- Extended: all 28 matchups / 112 games, nominal 1,500 nodes, one progress
  record written immediately after every game.
- Production: 4 matchups / 16 games using the real ten-second budget.

All seats now run the same native backend. Historical `enhanced` and `baseline`
labels remain in serialized benchmark records only as balanced assignment
labels; match-point percentages are not an A/B strength claim. The Extended
gate checks schedule completeness, terminal completion, and valid execution.

Profile the 14 unique real Quick openings separately with:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_production_opening_profile.ps1
powershell -ExecutionPolicy Bypass -File tools/run_production_opening_profile.ps1 -DepthMode self_turn
```

Reports are written under `.summer/local/ai-benchmarks/` and must not be
committed. Compare measurements from the same engine build, binary type,
machine state, fixture version, limits, and opening digest.

The 2026-09-02 ten-second `self_turn` profile completed depth two in all 14
unique real Quick openings and depth three in 9/14. The two previously slow
Dongfang Bubai/Zhang Sanfeng openings completed depth two in 9.46 seconds and
0.84 seconds respectively. This is reachability evidence only; it does not by
itself establish that `self_turn` is stronger than `complete_round`.

## Current limitations

- Native transpositions are not implemented.
- Android ARM64 and release-package performance are distribution gates; do not
  infer them from Windows Debug measurements.
- A future declaration outside the compiled vocabulary must fail atomically
  until the native kernel and independent tests support it.
