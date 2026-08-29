# AI Search

## Current Behavior

The opponent is a perfect-information deterministic search player. It sees both hands and exact deck order. The controller starts a `DuelSearchSession` worker with a cloned state and a deadline.

`DuelSearch.find_best_action_iterative()` performs iterative-deepening minimax
with alpha-beta pruning. The production `enhanced` profile adds deterministic
generic action ordering and lazy transition application. Principal-variation
search (PVS) remains available by explicit profile override. The bounded
tactical extension is also opt-in and remains disabled in production until it
can preserve mandatory action semantics instead of treating stand-pat
evaluation as a legal pass.
Completed depths publish progress. The final move is taken from the deepest
fully completed depth; partially searched deeper work is discarded.

Depth is measured in complete rounds, not individual actions. Complete-round
depth one contains the remainder of the root owner's current owner turn and the
opponent's following owner turn. Internally that is a budget of two authoritative
`owner_turn_serial` boundaries. Every transition subtracts the serial increase
reported by `DuelSimulator`: extra plays in the same owner turn cost zero
boundaries, while automatically resolved empty turns may consume more than one.
Terminal states are still scored before the horizon check.

The `baseline` profile preserves the pre-strengthening eager alpha-beta path for
paired comparison. It disables PVS and tactical extension.
Production Enhanced therefore runs the same configuration as the benchmark
`LazyOnly` variant: lazy transitions on, PVS/tactics/evaluation cache off, and
the baseline evaluator.
Both profiles call the same authoritative `DuelSimulator`; neither contains
named-card branches.

Default production budget is the exported `opponent_search_budget_seconds = 10.0` on `DuelController`. A future easy opponent can receive 5 seconds without changing evaluation strength.

## Failure and Deadline Policy

A deterministic greedy action is computed before deep search and serves as fallback when:

- depth one cannot complete within the deadline;
- the worker fails;
- search returns no usable action;
- the chosen action is no longer legal when presentation is ready to apply it.

The deadline is a maximum. A solved/terminal result may return early. Search
follows `state.active_player`, so a granted extra card play keeps the same owner
and exposes only legal hand plays. The deepest completed iteration also returns
the chosen same-owner-turn continuation as pure-data actions. After the first AI
action, the controller reuses the next action immediately when owner, owner-turn
serial, exact compact state key, and legality all still match. A fallback or any
mismatch clears the whole plan and starts a fresh ordinary search if another AI
action is still required.

Node-limited benchmark callers may opt into `min_completed_depth = 1`. In that
mode, `max_nodes` is a soft shared total until complete-round depth one finishes:
the node counter is never reset, and a deeper iteration stops as soon as it
observes the already-reached limit. Explicit cancellation, worker failure, and
any supplied deadline remain hard stops. Production supplies only its ten-second
deadline and never enables this benchmark guard. Results expose
`minimum_depth_guard_used` and `nodes_over_limit` so the extra work is visible.

The controller logs elapsed time, complete-round/tactical depth, generated versus
actually applied actions, cache/PVS counters, completion reason, and
fallback use:

```text
AI_SEARCH elapsed=... round_depth=... tactical_depth=... nodes=... generated=... applied=... pvs_probes=... reason=... fallback=... action=...
```

Use this line for profiling regressions.

## Evaluator

`duel_evaluator.gd` is intentionally card-agnostic. It scores generic properties:

- win/loss terminal value;
- owned cards and zone resources;
- card power;
- legal-action mobility;
- ki;
- active-ability count;
- danger and tempo.

The heuristic matters at the leaf of an incomplete game tree: when the current depth limit is reached before a terminal position, it estimates which state is preferable. Terminal wins/losses dominate positional terms.

The production enhanced search deliberately retains the baseline evaluator.
Candidate generic terms for usable ki, attack potential, endgame pressure, and
extra-play tempo remain available behind an explicit evaluator-profile override,
but paired ablation did not demonstrate a strength gain. The leaf-evaluation
cache is likewise opt-in because its Dictionary key cost made the measured
search slower despite real cache hits.

Do not add named-card knowledge to the evaluator. If an effect creates a generic strategic property not represented by existing features, add a generic measurable feature.

## Determinism

Legal actions have canonical keys and deterministic ordering. Equal results use stable tie-breaking. This makes tests and repeated debugging meaningful.

At the root, an apparent equal score from a later alpha-beta child may be only
a fail-low/fail-high bound. Before a smaller canonical key replaces the proven
best action, search verifies that candidate in the integer window immediately
around the current best score. This preserves stable tie-breaking without
allowing a bound-equal but objectively worse action to become the played move.

Ordering priority is previous principal variation, transposition-table best
action, generic history score, generic structural score, then canonical key.
History keys describe action shape plus generic source-card powers, ki, and
ability count without catalog or runtime card identity. This prevents a cutoff
earned by one changing hand-slot occupant from contaminating an unrelated card
that later occupies the same slot. Lazy search sorts legal actions first and
asks the simulator for a transition only if the branch is actually visited.

PVS searches the first ordered child with the full window and later children
with a null window, repeating a child with the full window only when required.
It is an exact alpha-beta optimization and has fixed complete-round-depth score/action
equivalence tests.

When explicitly enabled, the tactical extension first evaluates the
stand-pat state, scans at most 12 ordered actions, and searches at most four
volatile transitions for at most two extra plies. Volatility is defined only by
generic transition facts such as capture, exile, ownership change, terminal
state, summon/resummon/return, or extra-play grant. Pure draw and movement are
quiet. These bounds are intentional safeguards against effect-chain explosion.
It is not production-safe yet: a nonterminal owner must execute a legal action,
so stand-pat cannot remain a competing outcome when every legal continuation is
worse.

The transposition table is capped at 50,000 entries. `DuelStateKey.build()`
retains the exact canonical serialization used by fixtures and diagnostics.
Production `DuelStateKey.build_compact()` serializes the same complete explicit
state payload with Godot's native Variant binary encoder, hashes it with
SHA-256, and uses the first 128 bits plus the encoded byte length as a `v2`
fingerprint. No gameplay or presentation fields are intentionally omitted. It
is still a finite fingerprint with a theoretical collision risk, not a compact
simulation representation.

Runtime power arrays and every owner's removed zone are part of canonical
state. A zero-power removal therefore produces a distinct search state and
deep copies do not alias either structure. `power_change_batch_id` is excluded
because it belongs to transition presentation, not gameplay state.

## Concurrency Contract

- Search receives a deep state copy.
- Worker code never touches Nodes or scene state.
- Progress/result Dictionaries are protected by a mutex.
- Cancellation must be requested and the thread joined during shutdown.
- The inspector may stay open while thinking; application of a finished move waits until the modal inspector closes.

Any new asynchronous UI must preserve these rules.

## Why a Small Board Can Still Be Slow

The branching factor includes every hand-card/cell pairing plus activations. Draw effects increase hand options; movement reopens positions; extra card plays break simple alternation; removal can extend the match; and identical-looking card copies remain distinct runtime instances. The search repeatedly duplicates Dictionary-heavy states and processes full event-producing rules.

Even moderate branching compounds exponentially. A 3×3 board does not imply a tiny game tree when hands, decks, effects, and repeated movement exist.

## Safe Optimizations Now

- Reuse transposition results carefully.
- Avoid controller/UI work in simulation.
- Profile clone/key/evaluation costs.
- Add generic pruning bounds that preserve exact results.
- Keep event production minimal but complete.

## Historical Action-Depth Opening Profile (2026-08-28)

Before the complete-round migration, the production Enhanced/LazyOnly profile
was measured on the 14 unique real Quick openings using ordinary action-ply
depth. This is historical evidence only. The current profiler uses Dummy audio,
records every completed iterative-deepening layer, preserves partial root
progress from the interrupted layer, runs three opt-in timing probes, and writes
JSON evidence under `.summer/local/ai-benchmarks/`.

With a ten-second budget on the development machine:

- no opening completed ordinary action depth four;
- nine openings completed depth three and five completed only depth two;
- mean completed depth was `2.643`;
- among the nine depth-three completions, mean time to finish depth three was
  `6.214s`;
- the searches visited 38,730 nodes over 140.039 seconds, or about 277 nodes/s;
- all openings had 35 legal root plays;
- two of the nine depth-four attempts completed 17/35 and 19/35 root actions;
  linear estimates put those complete depth-four searches at `16.01s` and
  `15.33s`, requiring about `1.60x` and `1.53x` speedups respectively;
- the other seven depth-four attempts were still inside their first root
  action when the deadline expired, so their required speedups cannot be
  estimated safely from root-action fractions.

Three 5,000-node opt-in timing probes attributed approximately 43.6% of search
time to authoritative simulator transitions, 36.0% to canonical state-key
construction, 10.0% to leaf evaluation, 3.8% to legal-action ordering, and
6.5% to remaining search control. The timers are disabled in production. This
identifies transition/state-copy work and state keys as the first optimization
targets; evaluator or ordering tweaks alone cannot supply the needed gain.

Run the migrated profiler with
`tools/run_production_opening_profile.ps1`. Its report has
`depth_unit = complete_round`, `target_depth = 2`, and generic target-depth
estimates so old action-ply data cannot be mistaken for current search depth.

## Complete-Round Opening Profile (2026-08-28)

The first migrated 14-opening production run used the same ten-second
Enhanced/LazyOnly configuration:

- all 14 openings completed complete-round depth one without fallback;
- no opening completed complete-round depth two;
- mean time to complete depth one was `1.365s`;
- the searches visited 35,788 nodes over 140.078 seconds, about 255.5 nodes/s;
- the closest depth-two attempt completed 34/35 root actions and was linearly
  estimated at `10.28s` total;
- the other partial depth-two attempts varied widely, including branches still
  inside their first root action, so a single average speedup target would be
  misleading.

Three 5,000-node timing probes attributed approximately 38.1% of time to
simulator transitions, 43.8% to canonical state keys, 8.2% to evaluation, 3.9%
to ordering, and 6.0% to remaining search control. State-key construction and
authoritative transition/state-copy work remain the main performance targets.

## Full-State Fingerprint Profile (2026-08-29)

The full-state `v2` fingerprint was compared against a fresh legacy run on the
same 14 real Quick openings, with Enhanced/LazyOnly search, a ten-second budget
per opening, complete-round depth, and Dummy audio:

- aggregate throughput increased from `246.09` to `411.09` nodes/s, a `67.05%`
  improvement;
- key timing fell from `1695.08` to `114.69` microseconds per probe node, a
  `93.23%` reduction;
- mean depth-one completion time fell from `1.416s` to `0.798s`;
- depth two completed in `2/14` openings instead of `0/14`;
- all openings still completed depth one with zero fallback;
- all 14 depth-one scores, root action keys, and exact-state digests matched the
  legacy report.

The standalone 512-state microbenchmark measured `1328.7` new keys/s versus
`80.6` legacy keys/s (`16.49x`) with zero observed collisions. An initial
all-GDScript recursive accumulator measured only `0.543x` legacy speed, so the
production path deliberately uses native binary encoding and native SHA-256;
the generic recursive fingerprinter remains only for fixed structural vectors.

## Legal-Action Existence Profile (2026-08-29)

Terminal checks and empty-turn advancement only need to know whether an owner
has at least one legal action. They now call
`DuelSimulator.has_legal_action_for_owner()`, which returns after the first
legal placement or activation instead of allocating the complete action list.
Ordered search expansion still uses the authoritative full action generator.

The fast Boolean query matched full generation for both owners across 512 real
Quick-derived states (`1024/1024`). Against the preceding full-state fingerprint
profile on the same 14 openings and ten-second budget:

- aggregate throughput increased from `411.09` to `490.18` nodes/s (`+19.24%`);
- mean depth-one completion time fell from `0.798s` to `0.629s` (`-21.19%`);
- the three 5,000-node timing probes completed `1.203x` faster;
- depth two remained `2/14`, all openings completed depth one, and fallback
  remained zero;
- all depth-one scores, root actions, and exact-state digests remained equal.

The standalone transition microbenchmark improved only about `0.7%`, because
its one terminal query per transition underrepresents the search-wide benefit:
`is_terminal()` runs at every visited node, including nodes that do not apply a
child transition.

## Read-Only Modifier Query Profile (2026-08-29)

Attack validation and generic effect evaluation repeatedly inspect active card
modifiers. The public `DuelAbilities.get_modifiers()` still returns independent
deep copies, preserving its existing caller contract. Internal read-only query
helpers now use private modifier views instead, avoiding deep-copying every
modifier dictionary merely to compare its type or read a value. No card ID or
ability-specific search branch was introduced.

An attempted search-only transition result that skipped top-level presentation
aggregation matched all `1024/1024` measured real actions, but improved the
transition microbenchmark by only `1.2%`; it was reverted rather than adding a
second simulator mode for negligible gain.

For the retained modifier-query change, the 512-state/1,024-action transition
microbenchmark improved from an interleaved old-path median of about `5.044s`
to `4.804s`, approximately `4.8%`. Against the preceding 14-opening production
report:

- aggregate throughput increased from `490.18` to `547.48` nodes/s (`+11.69%`);
- mean complete-round depth-one time fell from `0.629s` to `0.572s` (`-9.12%`);
- depth two remained `2/14`; every opening completed depth one with zero fallback;
- all 14 depth-one scores, root actions, and exact opening-state digests matched.

The retained report is
`.summer/local/ai-benchmarks/production-opening-depth-1787978600.json`.

## Deferred Optimization

A true compact simulator could store indexed cards and packed primitive arrays instead of nested Dictionaries. It would improve copy and transition cost, but every gameplay primitive would then need a faithful compact implementation. The creator chose to establish reusable ability primitives first, then revisit this optimization to avoid duplicated maintenance churn.

When implementing it:

1. preserve one rules semantics contract;
2. compare compact transitions against `DuelSimulator` on generated states;
3. encode every mutable field, including effect retention, ki, deck order,
   owner-turn serial, extra-card-play allowance, end-boundary state, and pending
   choices;
4. keep the existing simulator as an oracle until parity tests are broad;
5. benchmark nodes/second and search depth, not just allocation size.

## Missing AI Work

- Fivefold board repetition is adjudicated by the shared simulator before the
  search receives another actionable state; there is no search-only draw rule.
- No compact-state parity harness.
- Tactical extension needs a forced-action-correct redesign before it can be
  restored as an `enhanced` default.
- No difficulty profiles beyond budget.
- No persistent opening/endgame database.
- No stochastic/hidden-information policy because perfect information is intentional.
- Evaluation will need generic extensions as new ability primitives appear.

## Paired Strength Benchmark

The formal harness uses the 34-deck enemy benchmark roster and deterministic
four-game crossover assignments. Each matchup gives both profiles each enemy
deck and each owner/initiative position once. The AI continues to see both
complete hands and exact deck order.

Run it with `tools/run_ai_benchmark.ps1`. `Quick` uses 7 matchups/28 games;
`Extended` uses all 28 matchups/112 games. Both use the fixed nominal 1,500-node
limit plus `min_completed_depth = 1` for both profiles. `Production` uses 4
matchups/16 games with the real ten-second deadline and no minimum-depth guard.
Pilot remains an optional diagnostic mode, not a prerequisite for Extended.

Extended writes one `AI_BENCHMARK_GAME` console line and appends one compact
JSONL checkpoint record after every completed game. The checkpoint is named
`extended-<variant>-v<version>-<timestamp>.progress.jsonl`; it survives an
interrupted later game, while only the final 112-game JSON is eligible for the
benchmark result. The PowerShell wrapper forwards child output during the run
instead of buffering it until exit.

Extended Final requires at least 55% match points, at least 75% initial-depth
non-regression, no worse fallback rate, and no incomplete games. JSON evidence
is written to `.summer/local/ai-benchmarks/` and is intentionally ignored by
Git.

`LazyPVS` is an explicit pure-ablation variant. Its Enhanced side uses Lazy
transitions plus PVS; its control side also uses Lazy transitions but disables
PVS. Both sides disable tactics/evaluation cache and use the baseline evaluator.
Production remains `LazyOnly`. Before a `LazyPVS` Extended run, both the focused
search suite and the 14-opening fixed-complete-round-depth equivalence script
must return identical scores and root actions. Run the formal ablation directly
with:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_ai_benchmark.ps1 -Mode Extended -Variant LazyPVS
```

This is a 112-game run using the same soft 1,500-node/minimum-depth-one rules;
it does not require Quick or Pilot. Below 50% is observed net loss, 50% to below
55% is neutral strength, and 55% or above reaches the declared gain line. The
result never enables production PVS automatically.

The 2026-08-29 Extended `LazyPVS` ablation completed all 112 games without
fallbacks, incomplete games, or invalid games. Lazy+PVS scored `55/112`
(`49.1%`) against LazyOnly and therefore missed the declared gain line. It
searched `747,415` nodes in `4,920.7s`, compared with LazyOnly's `752,789`
nodes in `4,686.0s`: PVS reduced nodes by only `0.7%` while increasing search
time by `5.0%` and reducing node throughput by `5.45%`. Its `532,646`
null-window probes caused `5,872` full-window re-searches (`1.10%`). All 56
paired initial-depth samples completed the same depth. Production therefore
keeps PVS disabled; the complete ignored report is
`.summer/local/ai-benchmarks/extended-lazypvs-v2-2026-08-28T23-29-44.json`.
