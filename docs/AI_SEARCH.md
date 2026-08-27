# AI Search

## Current Behavior

The opponent is a perfect-information deterministic search player. It sees both hands and exact deck order. The controller starts a `DuelSearchSession` worker with a cloned state and a deadline.

`DuelSearch.find_best_action_iterative()` performs iterative-deepening minimax
with alpha-beta pruning. The production `enhanced` profile adds deterministic
generic action ordering, lazy transition application, principal-variation
search (PVS). Its bounded tactical extension remains available by explicit
profile override, but is disabled in production until it can preserve mandatory
action semantics instead of treating stand-pat evaluation as a legal pass.
Completed depths publish progress. The final move is taken from the deepest
fully completed depth; partially searched deeper work is discarded.

The `baseline` profile preserves the pre-strengthening eager alpha-beta path for
paired comparison. It disables PVS and tactical extension.
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
and exposes only legal hand plays. The controller starts a fresh search session
with the full configured budget for every AI extra-play opportunity.

The controller logs elapsed time, ordinary/tactical depth, generated versus
actually applied actions, cache/PVS counters, completion reason, and
fallback use:

```text
AI_SEARCH elapsed=... depth=... tactical_depth=... nodes=... generated=... applied=... pvs_probes=... reason=... fallback=... action=...
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

Ordering priority is previous principal variation, transposition-table best
action, generic history score, generic structural score, then canonical key.
History keys describe action shape plus generic source-card powers, ki, and
ability count without catalog or runtime card identity. This prevents a cutoff
earned by one changing hand-slot occupant from contaminating an unrelated card
that later occupies the same slot. Lazy search sorts legal actions first and
asks the simulator for a transition only if the branch is actually visited.

PVS searches the first ordered child with the full window and later children
with a null window, repeating a child with the full window only when required.
It is an exact alpha-beta optimization and has fixed-depth score/action
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

The transposition table is capped at 50,000 entries. `DuelStateKey.build_compact()` currently returns a length plus forward/reverse hashes derived from a canonical serialization. This saves key memory but is not a compact state implementation and has a theoretical collision risk.

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

## Deferred Optimization

A true compact simulator could store indexed cards and packed primitive arrays instead of nested Dictionaries. It would improve copy and hashing cost, but every gameplay primitive would then need a faithful compact implementation. The creator chose to establish reusable ability primitives first, then revisit this optimization to avoid duplicated maintenance churn.

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

`tests/benchmarks/ai_benchmark_fixtures.gd` defines immutable versioned
fixtures. Every fixture is played twice, swapping which owner receives the
enhanced profile, so first-player and owner bias do not decide the comparison.
The AI continues to see both complete hands and exact deck order.

Run the harness with `tools/run_ai_benchmark.ps1`. `Quick` uses four fixtures
and 1,500 nodes per decision; `Extended` uses 16 fixtures and 10,000 nodes;
`Production` uses two fixtures and the real ten-second budget. Extended Final
requires at least 55% match points, at least 75% initial-depth non-regression,
no worse fallback rate, and no incomplete games. JSON evidence is written to
`.summer/local/ai-benchmarks/` and is intentionally ignored by Git.
