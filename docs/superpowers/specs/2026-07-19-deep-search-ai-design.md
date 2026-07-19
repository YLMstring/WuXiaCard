# Deep-Search Opponent AI

## Goal

Replace the prototype's one-ply greedy opponent with a scalable, near-optimal search architecture. The AI must reason many moves ahead, support future deterministic effects such as card removal, extra draws, effect chains, and extra turns, and remain responsive on portrait-oriented mobile devices.

## Product Decisions

- The AI may use perfect information, including both hands and the complete known deck order.
- Easier opponents search for 5 seconds per move.
- Harder opponents search for 10 seconds per move.
- Difficulty changes only the search time budget. Every opponent uses the same evaluator and selects the best move found within its budget.
- Search is deterministic for the same state, profile, and completed search depth.
- The initial search algorithm is iterative-deepening minimax with alpha-beta pruning. The simulator boundary must permit a future MCTS or hybrid search implementation without changing gameplay rules.

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

### `DuelMove`

A value describing one complete legal decision. The initial form identifies a hand card and board cell. It must be extensible to effect targets, optional choices, passes, and any future decision introduced by a card effect.

### `DuelSimulator`

The single deterministic rules authority for search and live gameplay. It:

- Generates every legal `DuelMove` for a state
- Applies a move to copied state data
- Resolves captures, draws, removals, extra turns, and chained effects in a defined order
- Reports terminal results
- Detects repetition and maximum-turn draws

The live duel controller must eventually consume the same resolved transitions as the AI. Card effects belong here rather than in the search engine, preventing new cards from requiring AI-specific rule code.

### `DuelEvaluator`

Scores non-terminal states from the searching player's perspective. Initial evaluation features are:

- Board ownership and score difference
- Strength and flexibility of cards still available
- Number and quality of legal moves
- Exposed edges and immediate recapture risk
- Extra-turn and pending-effect advantage
- Known upcoming draws

Terminal wins and losses use scores outside the range of every heuristic score so an actual result always outweighs temporary material advantage.

### `DuelSearch`

Runs time-bounded iterative deepening:

1. Complete depth 1 and retain its best move.
2. Repeat at increasing depths while time remains.
3. Use alpha-beta pruning, deterministic move ordering, and a transposition table.
4. Stop at the 5- or 10-second deadline.
5. Return the best move from the deepest fully completed iteration.

Search follows `DuelState.active_player`; it does not assume turns strictly alternate. The transposition key includes all state that can affect future play: board, zones, deck positions, active player, pending choices, active effects, and queued resolutions.

### `AIProfile`

Provides the time budget and future search tuning. The first profiles are:

- Easy: 5 seconds
- Hard: 10 seconds

Both profiles use identical evaluation weights and move-selection policy.

## Runtime Flow

1. At the opponent's turn, the controller creates a complete `DuelState` snapshot.
2. Search operates on copied pure data away from the main UI thread.
3. The UI remains responsive and displays the opponent's thinking status.
4. Search periodically checks its deadline and cancellation token.
5. On completion, the controller rejects the result if the scene ended, the match restarted, or the state version changed.
6. The controller verifies that the returned move remains legal and commits it through the normal production move path.

If the search cannot finish depth 1 before cancellation, it returns a deterministic legal fallback move. Scene exit and match restart cancel outstanding work without applying stale results.

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

### Runtime safety

- Cancelling a search prevents its move from being applied.
- Results from outdated state versions are rejected.
- The UI remains responsive throughout 5- and 10-second searches.
- No scene nodes or mutable live game objects are accessed by the worker search.

### Performance

Record completed depth, visited nodes, alpha-beta cutoffs, transposition hits, evaluation score, and elapsed time. Benchmark both profiles on representative mobile-class hardware and maintain deterministic benchmark positions as rules expand.

## Migration Strategy

1. Extract the existing board and hand data into the first `DuelState` representation without changing behavior.
2. Make live placement and current greedy AI use `DuelSimulator`.
3. Prove simulator parity with the existing 15 rule checks and integration suite.
4. Add depth-limited minimax and tactical fixtures.
5. Add alpha-beta pruning, move ordering, and the transposition table.
6. Add iterative deepening, time budgets, cancellation, and worker execution.
7. Replace `DuelRules.choose_ai_move()` only after the search path passes gameplay verification.

This migration keeps the currently working opponent available until the new engine is independently proven.

## Scope Boundaries

This design does not add special-effect cards, deck-building UI, hidden information, randomness, multiplayer, machine learning, online services, or opponent personality errors. It establishes the deterministic decision architecture those future card rules can use.
