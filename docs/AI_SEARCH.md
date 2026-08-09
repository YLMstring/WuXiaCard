# AI Search

## Current Behavior

The opponent is a perfect-information deterministic search player. It sees both hands and exact deck order. The controller starts a `DuelSearchSession` worker with a cloned state and a deadline.

`DuelSearch.find_best_action_iterative()` performs iterative-deepening minimax with alpha-beta pruning. Completed depths publish progress. The final move is taken from the deepest fully completed depth; partially searched deeper work is discarded.

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

The controller logs:

```text
AI_SEARCH elapsed=... depth=... nodes=... cutoffs=... cache_hits=... reason=... fallback=... action=...
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

Do not add named-card knowledge to the evaluator. If an effect creates a generic strategic property not represented by existing features, add a generic measurable feature.

## Determinism

Legal actions have canonical keys and deterministic ordering. Equal results use stable tie-breaking. This makes tests and repeated debugging meaningful.

The transposition table is capped at 50,000 entries. `DuelStateKey.build_compact()` currently returns a length plus forward/reverse hashes derived from a canonical serialization. This saves key memory but is not a compact state implementation and has a theoretical collision risk.

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

- Improve deterministic move ordering.
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

- No repetition-draw adjudication.
- No compact-state parity harness.
- No difficulty profiles beyond budget.
- No persistent opening/endgame database.
- No stochastic/hidden-information policy because perfect information is intentional.
- Evaluation will need generic extensions as new ability primitives appear.
