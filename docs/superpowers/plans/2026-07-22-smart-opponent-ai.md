# Smart Opponent AI Implementation Plan

**Design:** `docs/superpowers/specs/2026-07-19-deep-search-ai-design.md`  
**Scope:** Upgrade Shen Lian from the production greedy selector to a responsive, perfect-information, 10-second maximum iterative-deepening alpha-beta search. Preserve the current greedy AI as the deterministic fallback and preserve testing mode as a pre-game script setting with no AI worker.

## Working Rules

- Keep `DuelSimulator` as the only gameplay-rules authority. Search and evaluation must not implement named-card behavior.
- Search a deep-copied `DuelState`; never read or mutate scene nodes, card views, or the live controller from the worker.
- Follow `state.active_player` at every node. Never assume owners alternate because extra turns may chain.
- Replace the selected move only after an entire depth completes. Discard partial-depth results.
- Treat 10 seconds as Shen Lian's maximum search time, not a forced delay. Return immediately when the reachable result is solved.
- Compute the existing greedy action before starting the worker. Use it when depth 1 is interrupted, the worker fails, or the deep result is stale or illegal.
- Keep move choice deterministic for the same state and completed depth. Search statistics may vary with hardware, but canonical tie-breaking may not.
- Use explicit synchronization for all cross-thread state. The worker may share only a cancellation flag, immutable inputs, copied progress, and copied result data through a mutex-protected session API.
- Keep runtime deadlines based on a monotonic clock. Add deterministic node/depth limits for tests so correctness does not depend on wall-clock scheduling.
- Require explicit test pass markers or named Summer verification reports. An unmarked process exit is not a pass.

## Checkpoint 0: Confirm the Current Baseline

**Files changed:** none.

Run the rules, catalog, simulator/search, and integration suites. Record their exact pass markers. Boot the production duel and record diagnostics. Confirm Git status is clean at the smart-AI design commit and that the known focus and integer-division warnings are the only pre-existing warnings.

## Checkpoint 1: Extract a Generic Evaluator

**Create:**

- `scripts/duel_evaluator.gd`
- `scripts/duel_evaluator.gd.uid`
- `tests/test_duel_search.gd`
- `tests/test_duel_search.gd.uid`

**Modify:**

- `scripts/duel_search.gd`

### Red

Add focused evaluator/search tests requiring:

- terminal wins, losses, and draws to outrank every heuristic value;
- terminal scoring to prefer faster wins and slower losses without depending on a named card;
- ownership difference to dominate small positional bonuses;
- hand and ordered-deck resources, total remaining power, mobility, board-card ki, and active generic effects to contribute from the requested root owner's perspective;
- exposed edges and immediate capture danger to reduce value;
- active-player tempo and already-resolved extra-turn advantage to be represented generically;
- swapping root owner to negate the strategic interpretation of the same state;
- the existing depth-4 greedy-trap fixture and activate-action fixture to retain their expected choices.

### Green

Move `_evaluate` out of `DuelSearch` into a scene-free `DuelEvaluator.evaluate(state, root_owner)` API. Keep all weights in one constants section and bound the largest possible non-terminal score strictly inside `DuelSearch.WIN_SCORE`.

Use generic state and effect data only:

- board ownership and powers;
- hands and decks, including card count and total side power;
- legal-action counts through `DuelSimulator`;
- adjacency comparisons for exposure and immediate danger;
- current ki and active-effect/activation metadata;
- active-player tempo.

Do not branch on card IDs, glyphs, names, or Meng Huo/Jiang Wei/Sun Zan constants. Preserve the public fixed-depth `find_best_action(state, max_depth, root_owner)` API by delegating its leaf evaluation to `DuelEvaluator`.

### Verify

Run the new search suite and the full simulator suite.

## Checkpoint 2: Add Canonical State and Action Keys

**Create:**

- `scripts/duel_state_key.gd`
- `scripts/duel_state_key.gd.uid`

**Modify:**

- `scripts/duel_action.gd`
- `tests/test_duel_search.gd`

### Red

Add fixtures requiring the state key to remain identical for deep copies and to change when any future-relevant field changes:

- board occupancy, owner, card identity, powers, ki, or active effects;
- either ordered hand or ordered side deck;
- discard or removed zones;
- active player or turn count;
- active effects, effect queue, or pending choice;
- repetition history or maximum-turn policy.

Require dictionaries with the same semantic data but different insertion order to serialize identically. Require `DuelAction` keys to distinguish action type, source zone/index/instance, ability, target kind, and target index while remaining stable across duplicated actions.

Do not include `state_version` in the transposition key because it guards live-controller staleness rather than changing simulated future rules.

### Green

Implement explicit, deterministic serialization instead of using `Dictionary.hash()` or iteration order. Serialize board cells and ordered zones in their gameplay order. Serialize arbitrary nested dictionaries with sorted keys and arrays in order. Normalize `StringName`, integers, booleans, and null into unambiguous tagged values.

Add `DuelAction.canonical_key()` for deterministic tie-breaking, principal-variation matching, and result validation.

### Verify

Run the key fixtures repeatedly in one process and across two fresh headless processes.

## Checkpoint 3: Build the Anytime Search Core

**Modify:**

- `scripts/duel_search.gd`
- `tests/test_duel_search.gd`
- `tests/test_duel_simulator.gd`

### Public API

Keep:

- `find_best_action(state, max_depth, root_owner)` for deterministic fixed-depth tests and callers.

Add a pure worker-safe entry point returning a dictionary result:

- `find_best_action_iterative(state, root_owner, limits, should_cancel, on_progress)`.

`limits` supports a runtime monotonic deadline plus optional maximum depth and node count for deterministic tests. Runtime uses the deadline; tests use depth/node limits wherever possible.

The result contains:

- copied `action`;
- `score`;
- `completed_depth`;
- `nodes`, `cutoffs`, and `transposition_hits`;
- `elapsed_seconds`;
- `solved`;
- `completion_reason` (`solved`, `deadline`, `cancelled`, `node_limit`, or `no_legal_action`);
- `has_completed_depth`.

### Red

Add tests requiring:

- depths to complete in increasing order and only completed depths to publish a new best action;
- an interrupted depth 1 to report no completed result;
- an interrupted deeper iteration to retain the prior depth's action and score;
- identical completed depths to return identical actions and scores;
- same-owner extra-turn children to maximize again rather than alternate sides;
- terminal branches to beat heuristic gains;
- the existing greedy trap to choose the deep move once the required depth completes;
- move ordering to preserve canonical tie-breaking;
- transposition exact, lower-bound, and upper-bound entries to match an uncached reference search;
- cache hits to occur on a transposition fixture;
- cancellation/deadline checks to stop inside recursion within a bounded number of additional nodes;
- a fully terminal reachable tree to report `solved` before the deadline;
- a horizon-evaluated tree not to report solved.

### Green

Refactor the recursive result to carry score and horizon/solved information. Add:

- iterative-deepening loop;
- monotonic deadline, node-limit, and cancellation checks near node entry and action loops;
- one transposition table per search session, reused across depths;
- depth-aware exact/lower/upper-bound entries;
- principal-variation action from the previous iteration;
- deterministic ordered transition records so actions are simulated once for ordering and recursion;
- counters for nodes, cutoffs, and cache hits;
- progress publication only after a depth completes, plus elapsed-only updates at a throttled interval.

Order actions by previous principal move, terminal result, ownership-changing capture/removal, extra-turn creation, activate action, tactical estimate, and canonical action key. Replace best actions only on strict score improvement so the first canonical equal choice remains stable.

Conservatively report `solved` only when the completed root result depends on no non-terminal horizon evaluation; alpha-beta-pruned branches may remain unvisited when their bounds prove they cannot change the root choice.

### Verify

Run search fixtures at least twice. Compare cached and uncached results. Record deterministic benchmark statistics for the opening state without asserting hardware-dependent elapsed time or depth.

## Checkpoint 4: Add the Worker Search Session

**Create:**

- `scripts/duel_search_session.gd`
- `scripts/duel_search_session.gd.uid`

**Modify:**

- `tests/test_duel_search.gd`

### Red

Add session tests requiring:

- `start` to deep-copy the supplied state and retain a copied greedy fallback;
- one worker maximum per session;
- progress reads to return copies rather than shared mutable dictionaries;
- cancellation to terminate and join safely;
- completion to return a copied action and complete statistics;
- a zero/tiny deterministic limit to select the greedy fallback;
- forced worker failure to select the greedy fallback with a failure completion reason;
- repeated start/cancel/free cycles to leave no running threads;
- mutation of the original state after `start` not to affect the worker result.

### Green

Implement `DuelSearchSession` as a `RefCounted` owner of `Thread` and `Mutex`. Its public main-thread API should be small:

- `start(state, root_owner, budget_seconds, greedy_fallback, optional_test_limits)`;
- `get_progress()`;
- `is_complete()`;
- `cancel()`;
- `finish_and_get_result()`.

The thread entry calls only pure search APIs. All shared progress, cancellation, errors, and final results are read or written while holding the mutex. `finish_and_get_result()` joins exactly once. The session's cleanup path requests cancellation and joins any live worker. The optional test-limit dictionary may include a `force_failure` flag used only by the session suite; normal controller code never supplies it.

Do not use signals emitted from the worker, `call_deferred`, scene-tree timers, nodes, resources tied to the scene tree, or direct controller callbacks.

### Verify

Run the search suite under normal and repeated-session stress fixtures. Check for thread leaks and script errors.

## Checkpoint 5: Integrate Shen Lian's Hard Profile

**Modify:**

- `scripts/duel_controller.gd`
- `tests/test_duel_integration.gd`

### Red

Add production-controller tests requiring:

- normal mode to start a search session only on an opponent turn;
- testing mode to start no search session and leave the opponent under manual control;
- Shen Lian's default budget to be 10 seconds;
- fast test mode to use a deterministic immediate/tiny search limit rather than waiting 10 seconds;
- the turn status to display elapsed seconds and last completed depth while searching;
- the UI/process-frame heartbeat to advance while the worker searches;
- a solved result to commit before the configured budget;
- depth-1 interruption and injected worker failure to commit the greedy fallback;
- a stale state version, completed match, or exiting scene to reject the worker result;
- returned actions to be revalidated against current legal actions by full canonical identity;
- play and activate results to commit through the existing `_commit_action` path;
- an opponent extra turn to start a fresh search from the new state;
- cancellation and scene cleanup to leave no worker running.

### Green

Add exported/configurable search settings with Shen Lian defaulting to 10 seconds. Replace the normal-mode call to `Simulator.choose_greedy_action(duel_state)` with this coordinator:

1. duplicate the current state and record `state_version`;
2. compute the greedy fallback;
3. start `DuelSearchSession`;
4. await process frames while polling copied progress and updating `TurnStatus`;
5. join and collect the result;
6. reject stale/finished-scene results;
7. validate the deep action against current legal actions;
8. use the greedy fallback when the search has no valid completed result;
9. commit through `_commit_action`.

Cancel and join the session from `_exit_tree`, match completion, and any restart/setup path. Do not add an in-game testing-mode toggle or cancellation branch. Keep opponent cards face-down even though the worker receives perfect information.

Log one compact final line per search containing elapsed time, depth, nodes, cutoffs, transposition hits, completion reason, whether fallback was used, and the canonical action key.

### Verify

Run integration with fast deterministic limits. Use a production-scene verification probe to prove the UI advances frames during search and the committed action matches the reported result.

## Checkpoint 6: Full Regression, Ten-Second Playtest, and Mobile-Safety Evidence

Run every repository suite and require explicit pass markers. Check all modified/new GDScripts for parse errors. Run `git diff --check`, review the complete diff, and confirm no named-card logic entered the evaluator/search/session.

Walk these production paths with fast mode off:

1. Start a normal duel and end the player's turn. Observe `Shen Lian considers… <elapsed>s · depth <completed>` updating without freezing animations or input-independent UI.
2. Record the actual elapsed time, completed depth, nodes, cutoffs, cache hits, completion reason, and chosen action. Confirm it never exceeds the 10-second search budget beyond small polling/join overhead.
3. Use a nearly finished position whose reachable tree is solved early. Confirm Shen Lian moves before 10 seconds.
4. Force a depth-1 interruption with a test limit. Confirm the existing greedy move is committed.
5. Give Shen Lian an activate action and verify the searched activate result drags/commits through normal production presentation.
6. Give Shen Lian an extra turn and verify a new search begins for the retained opponent owner.
7. Exit while thinking and confirm cancellation finishes without a stale move or thread error.
8. Start in testing mode and confirm the opponent remains manually controlled and no search telemetry appears.
9. Recheck draw, Ink Summon, exile replacement, movement activation, Meng Huo chained turns, hidden opponent cards, fixed hand slots, score, and match completion.

After the walkthrough, read console, debugger, and aggregate diagnostics. New errors, thread warnings, stale commits, UI stalls, nondeterministic equal-score choices, or a missed deadline are blockers.

Run one release-like Android/mobile-class benchmark if an Android export target or representative throttled machine is available. Record rather than hard-code achieved depth because the 10-second time budget, not a fixed depth, defines the profile.

## Final Commit and Handoff

Confirm the worktree contains only intended implementation/test changes. Commit the verified implementation as `Add smart opponent search`. Do not push unless explicitly requested. Report:

- final commit ID;
- suite pass markers and counts;
- actual production search elapsed time and completed depth;
- whether the opening was solved or deadline-limited;
- known pre-existing warnings;
- any mobile benchmark limitation.
