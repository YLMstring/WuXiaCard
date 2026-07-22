# Deep-Search Opponent AI

## Goal

Replace the prototype's one-ply greedy opponent with a scalable, near-optimal search architecture. The AI must reason many moves ahead, support future deterministic effects such as card removal, extra draws, effect chains, and extra turns, and remain responsive on portrait-oriented mobile devices.

## Product Decisions

- The AI may use perfect information, including both hands and the complete known deck order.
- Easier opponents search for 5 seconds per move.
- Harder opponents search for 10 seconds per move.
- Shen Lian uses the hard profile, so his search budget is 10 seconds.
- Difficulty changes only the search time budget. Every opponent uses the same evaluator and selects the best move found within its budget.
- The budget is a maximum rather than an artificial delay. A completely solved position returns immediately.
- Search is deterministic for the same state, profile, and completed search depth.
- The initial search algorithm is iterative-deepening minimax with alpha-beta pruning. The simulator boundary must permit a future MCTS or hybrid search implementation without changing gameplay rules.
- If depth 1 does not complete, search fails safely, or the returned action is invalid, the opponent uses the existing deterministic greedy choice.
- Testing mode remains a script setting read when a duel is created. It cannot be toggled in-game, and no AI search starts for a testing-mode duel.

## Architecture

### `DuelState`

A pure-data snapshot containing every fact needed to continue a match:

- Board contents and ownership
- Both players' hands
- Known deck contents and draw positions
- Discard, removed, or other card zones
- Active player
- Turn count
- Active and queued effects
- Pending target or choice information
- Repetition history or sufficient state hashes to detect repetition

The state contains no scene nodes, UI references, tweens, audio, or other presentation data.

### `DuelAction`

A value describing one complete legal decision. It currently supports playing a hand card or activating a board card, together with a typed target. It remains extensible to optional choices, passes, hand-slot targets, and future decisions introduced by card effects.

### `DuelSimulator`

The single deterministic rules authority for search and live gameplay. It:

- Generates every legal `DuelAction` for a state
- Applies a move to copied state data
- Resolves captures, draws, removals, extra turns, and chained effects in a defined order
- Reports terminal results
- Detects repetition and maximum-turn draws

The live duel controller already consumes the same resolved transitions as the AI. Card effects belong here rather than in the search engine, preventing new cards from requiring AI-specific rule code.

### `DuelEvaluator`

Scores non-terminal states from the searching player's perspective. Initial evaluation features are:

- Board ownership and score difference
- Strength and flexibility of cards still available
- Number and quality of legal moves
- Exposed edges and immediate recapture risk
- Extra-turn and pending-effect advantage
- Known upcoming draws
- Stored ki and active generic ability value

Terminal wins and losses use scores outside the range of every heuristic score so an actual result always outweighs temporary material advantage.

The heuristic is used only at a non-terminal search horizon. Every deeper completed iteration replaces shallower estimates with better-informed values. If the reachable tree is completely solved, all relevant leaves have exact terminal outcomes and the heuristic no longer affects the chosen move.

The evaluator remains card-agnostic. It reads resolved state, legal actions, card powers, ki, and generic effect metadata rather than checking named cards such as Meng Huo. A separate inexpensive tactical estimate may order promising moves first, but move ordering cannot change the result of a completed depth.

### `DuelSearch`

Runs time-bounded iterative deepening:

1. Complete depth 1 and retain its best move.
2. Repeat at increasing depths while time remains.
3. Use alpha-beta pruning, deterministic move ordering, and a transposition table.
4. Stop at the 5- or 10-second deadline.
5. Return the best move from the deepest fully completed iteration.

A partially searched depth never replaces the last fully completed result. Move ordering considers the previous iteration's best move first, followed by terminal results, ownership-changing captures or removals, extra-turn creation, activate actions, and stable canonical action order.

Search follows `DuelState.active_player`; it does not assume turns strictly alternate. The transposition key includes all state that can affect future play: board, zones, deck positions, active player, pending choices, active effects, and queued resolutions.

Transposition entries record search depth, score, and exact/lower/upper-bound type. The state key covers board card identity, power, ownership, ki, and active effects; ordered hands and decks; discard and removed zones; active player; turn count; queued effects; pending choices; and repetition state.

### `DuelSearchSession`

`DuelSearchSession` owns one worker thread and is the only bridge between the pure search engine and the live controller. It stores:

- An isolated duplicated starting state
- The deterministic greedy fallback computed before deep search begins
- The selected profile deadline and cancellation flag
- A mutex-protected progress snapshot
- The last fully completed search result
- The final action and completion reason

The progress snapshot contains elapsed time, completed depth, visited nodes, alpha-beta cutoffs, transposition hits, and whether the reachable tree was solved. The worker checks cancellation and deadline throughout recursion, never accesses scene nodes, and never mutates the live duel state.

### `AIProfile`

Provides the time budget and future search tuning. The first profiles are:

- Easy: 5 seconds
- Hard: 10 seconds

Both profiles use identical evaluation weights and move-selection policy.

Shen Lian currently selects Hard. The controller exposes the budget as script configuration so future encounters can select another profile without changing search code.

## Runtime Flow

1. At the opponent's turn, the controller creates a complete `DuelState` snapshot and records its state version.
2. The controller computes and retains the current greedy action as a fallback.
3. A `DuelSearchSession` runs iterative deepening on copied pure data away from the main UI thread.
4. The UI remains responsive and displays `Shen Lian considers… <elapsed>s · depth <completed>`.
5. Search checks its deadline and cancellation token throughout recursion. It returns immediately if the complete reachable tree is solved.
6. The controller polls copied progress data and logs final elapsed time, depth, nodes, cutoffs, cache hits, completion reason, and chosen action.
7. On completion, the controller rejects the result if the scene ended, the match restarted, the match completed, or the state version changed.
8. The controller verifies that the returned move remains legal. An incomplete depth-1 search, worker failure, or invalid result uses the stored greedy fallback.
9. The selected action commits through the normal production action path.

Scene exit, match restart, and match completion cancel and join outstanding work without applying stale results. Testing mode is fixed before scene creation and never creates a search session, so there is no in-game testing-mode cancellation path.

## Variable-Length Match Safety

Card removal and extra draws can create long or cyclic matches. Search therefore requires:

- Repetition detection with a defined draw value
- A configurable maximum simulated turn count
- Deadline checks throughout recursive search
- A stable terminal policy shared by live gameplay and simulation

Near-perfect means the best result discovered within the budget. Exact play is achieved only when the reachable game tree is completely solved.

## Extensibility

The search engine knows nothing about individual effects. Adding an effect requires:

1. A deterministic simulator implementation
2. Complete state serialization/hash coverage
3. Legal-move and resolution tests
4. An evaluator feature only when the effect creates strategic value not represented by existing features

Because search depends only on the simulator interface, MCTS or a hybrid strategy can be added later as another search implementation.

## Verification

### Rules and simulator parity

- Every production move and simulated move produces the same resulting state.
- Captures, draws, removals, extra turns, targeting, and chained effects have isolated tests.

### Search correctness

- Tactical positions demonstrate cases where greedy play loses and deeper search succeeds.
- Terminal wins are chosen over heuristic gains.
- Extra-turn states maximize for the player who actually retains the turn.
- Repetition and maximum-turn positions resolve consistently.
- Identical inputs produce identical moves at identical completed depths.
- Interrupted depth 1 returns the deterministic greedy fallback.
- A partially completed deeper iteration does not replace the last completed result.
- A completely solved position returns before its time budget expires.
- Transposition exact/lower/upper bounds match uncached alpha-beta results.
- State-key fixtures change when any future-relevant field changes.

### Runtime safety

- Cancelling a search prevents its move from being applied.
- Results from outdated state versions are rejected.
- The UI remains responsive throughout 5- and 10-second searches.
- No scene nodes or mutable live game objects are accessed by the worker search.
- Testing-mode duels never start a worker.
- Worker failure and invalid results commit the retained greedy action rather than ending the match.

### Performance

Record completed depth, visited nodes, alpha-beta cutoffs, transposition hits, evaluation score, completion reason, and elapsed time. Display elapsed time and completed depth in the turn-status line during the first implementation so search behavior can be observed directly. Benchmark both profiles on representative mobile-class hardware and maintain deterministic benchmark positions as rules expand.

## Migration Strategy

The project has completed the safe foundation: `DuelState`, `DuelAction`, `DuelSimulator`, production controller parity, fixed-depth alpha-beta search, and tactical fixtures. The current implementation increment is:

1. Separate evaluation and canonical state-key responsibilities from search recursion.
2. Add deterministic move ordering and bound-aware transposition entries.
3. Add iterative deepening, deadline checks, statistics, and solved-tree detection.
4. Add `DuelSearchSession` worker execution, progress polling, cancellation, and greedy fallback.
5. Integrate Shen Lian's 10-second hard profile and visible telemetry into the live controller.
6. Replace `DuelSimulator.choose_greedy_action()` in normal opponent turns only after the search path passes unit, integration, cancellation, responsiveness, and production gameplay verification.

The existing greedy opponent remains the fallback throughout migration and at runtime.

## Scope Boundaries

This design does not add special-effect cards, deck-building UI, hidden information, randomness, multiplayer, machine learning, online services, or opponent personality errors. It establishes the deterministic decision architecture those future card rules can use.
