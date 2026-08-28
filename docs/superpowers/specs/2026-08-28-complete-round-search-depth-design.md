# Complete-Round Search Depth Design

**Status:** Implemented and verified
**Date:** 2026-08-28

## Goal

Replace action-ply search depth with complete-round depth. A completed search
depth must include the current owner's entire remaining owner turn and the
opponent's entire following owner turn before a nonterminal leaf may use the
heuristic evaluator.

This removes the current depth-parity problem. The AI must not prefer a line
merely because the horizon falls immediately after its own card play but before
the opponent can answer.

This design also prevents repeated ten-second pauses during one AI owner turn.
Extra card plays already searched as part of the chosen complete-round line
reuse that line instead of starting a new search.

## Definitions

### Action node

One legal `DuelAction` applied through the authoritative `DuelSimulator`. An
ordinary owner turn normally contains one action node. An extra-card-play chain
may contain several consecutive action nodes owned by the same player.

### Owner-turn boundary

One completed owner turn, represented authoritatively by an increment of
`DuelState.owner_turn_serial`. The boundary occurs only after all granted extra
card plays, end-owner-turn effects, terminal checks, and turn-scoped
restoration for that owner turn have resolved.

### Complete-round depth

One complete-round depth unit equals two completed owner-turn boundaries:

1. the owner active at the root completes the rest of the current owner turn;
2. the opposing owner completes the following owner turn.

The resulting nonterminal leaf is normally the root owner’s next actionable
decision state. If that owner or later owners have empty turns, deterministic
advancement may move farther before any actionable state exists; that atomic
simulator result is still the leaf.

## Chosen Model: Owner-Turn-Boundary Budget

For target complete-round depth `n`, search begins with an owner-turn-boundary
budget of:

```text
remaining_owner_turn_boundaries = 2 * n
```

For every simulated action:

```text
transition_cost = max(
    next_state.owner_turn_serial - current_state.owner_turn_serial,
    0
)

child_remaining = remaining_owner_turn_boundaries - transition_cost
```

The search recurses while `child_remaining > 0`. At `child_remaining <= 0`, a
nonterminal state may be evaluated. Terminal states are always detected and
scored before the depth boundary is considered.

The simulator remains authoritative. Search must never synthesize turn
advancement, split a simulator transition, skip trigger resolution, or infer a
boundary from `active_player` alone.

## Transition Semantics

### Ordinary actions

An ordinary action that closes its owner turn normally increments
`owner_turn_serial` once and therefore consumes one owner-turn boundary.

Without extra plays or empty turns:

```text
complete-round depth 1 = current owner action + opponent action
complete-round depth 2 = current owner action + opponent action
                       + current owner action + opponent action
```

This corresponds to old action depths two and four only in ordinary alternating
positions. The new unit must not be described as a fixed two-to-one conversion
when extra plays or empty turns exist.

### Extra card plays

An extra card play belongs to the current owner turn. While the owner retains a
legal extra play, `owner_turn_serial` does not increase, so the transition costs
zero owner-turn boundaries.

Every extra play remains a real search node with its full legal-action branch.
It still consumes time and nodes, participates in alpha-beta search, and may
make a complete round substantially more expensive. Search may not skip or
heuristically summarize the chain.

### Empty owner turns

Empty owner turns do not create search branches. `DuelSimulator` already emits
the start-owner-turn trigger, checks for legal actions, emits the end-owner-turn
trigger when still empty, completes the owner-turn boundary, and advances
again inside the same transition.

Each automatically completed empty owner turn increments `owner_turn_serial`
and therefore consumes one boundary from the remaining budget. A transition
may consume two or more boundaries at once.

If a start/end trigger creates a legal action or a usable extra play, the owner
turn is no longer empty. The simulator stops at that actionable state and the
search branches normally.

### Atomic overshoot

A simulator transition may cross the nominal horizon because it automatically
resolves one or more deterministic empty turns. Search evaluates the final
actionable state returned by that complete transition. It must not reconstruct
or evaluate an intermediate pre-trigger or pre-start-turn state.

### Terminal states

If a branch becomes terminal after either owner's turn, it receives the normal
terminal score immediately. Search does not continue merely to consume the
remaining round budget.

## Minimax and Alpha-Beta Semantics

The maximizing/minimizing owner remains determined by
`state.active_player == root_owner`. Consecutive extra card plays therefore
naturally produce consecutive maximizing nodes for the root owner or
consecutive minimizing nodes for the opponent.

Lazy transitions, deterministic action ordering, alpha-beta bounds, optional
PVS, and the card-agnostic evaluator remain conceptually unchanged. They
operate over a variable number of action nodes inside each complete-round
depth.

Search must not add card-ID knowledge or a special case for any ability that
grants extra plays.

## Iterative Deepening and Deadlines

Iterative deepening attempts complete-round depths in order:

```text
1, 2, 3, ...
```

Only a fully completed iteration may:

- replace the retained best action and score;
- publish a completed-depth progress update;
- provide a reusable same-turn continuation plan.

If depth two times out, hits a node limit, or is cancelled, search returns the
fully completed depth-one result. Work from the partial depth-two iteration is
discarded. If depth one never completes, the existing legal greedy fallback is
used.

Deadline and cancellation checks continue at ordinary search nodes, including
zero-boundary-cost extra plays. A long extra-play chain may therefore cause the
current iteration to be abandoned, but it must never be turned into a
heuristically scored partial round.

No separate artificial action limit is added by this feature. Existing
deadline, node-limit, cancellation, terminal, and gameplay safeguards remain
authoritative.

## Search Result and Diagnostics

The meanings of the public search fields change as follows:

- `completed_depth`: deepest fully completed complete-round depth;
- `iteration_depth`: complete-round depth currently being attempted when the
  search stopped;
- `max_depth`: maximum complete-round depth requested by the caller.

Nodes, generated actions, applied transitions, cutoffs, and partial root-action
progress remain counts of actual action-node work. Logs and the player-visible
thinking message label depth using the new complete-round unit.

Any fixed-depth benchmark or equivalence diagnostic must be updated explicitly.
For an ordinary alternating position, a former action-depth-four comparison
becomes complete-round-depth two.

## Transposition Table

The transposition table continues to key gameplay state with
`DuelStateKey.build_compact()`. Its stored depth coverage changes from remaining
action plies to remaining owner-turn boundaries.

A cached entry may satisfy a lookup only when its stored remaining-boundary
coverage is at least the caller's requested remaining-boundary budget, subject
to the existing exact/lower/upper bound rules. Entries from different depth
units must never be compared.

Zero-cost extra-play transitions do not reduce remaining-boundary coverage, but
their changed gameplay state—including hand, board, extra-play allowance,
owner-turn serial, and other runtime data—continues to produce a distinct state
key.

## Reusing the Same-Turn Continuation

### Purpose

The initial complete-round search already chooses the optimal extra plays on
its retained principal line. Starting a fresh ten-second search for every extra
play repeats work, creates long pauses, and gives extra-play decks more total
thinking time than ordinary decks.

### Retained plan

After each fully completed iteration, search retains the chosen principal-line
actions belonging to the root owner's current owner turn. Each plan entry
contains pure data:

```text
state_key
owner_turn_serial
owner_id
action
```

The first entry is the root action. Following entries are retained only while:

- `active_player` is still the root owner;
- `owner_turn_serial` still equals the root state's serial;
- the branch contains another legal action selected by the completed search.

The plan stops when the owner turn ends, even if deterministic empty turns make
the root owner active again immediately. A changed `owner_turn_serial` denotes
a new owner turn and requires a new normal search.

The plan must be snapshotted from the deepest fully completed iteration before
a deeper iteration starts. A partial deeper iteration may not overwrite it.

### Consumption

After applying an AI action, the controller checks the next retained plan entry
before starting another `DuelSearchSession`. It consumes the planned action
immediately only when:

- the duel is nonterminal;
- the AI remains the active owner in the same `owner_turn_serial`;
- the exact current compact state key matches the entry;
- the planned action remains legal.

No new thinking delay or thinking indicator is shown for a successfully reused
extra-play action. Normal card presentation and animation cadence still run.

### Invalidation and fallback

The entire remaining plan is discarded when:

- the initial search did not complete depth one and used the greedy fallback;
- no continuation entry exists;
- owner, owner-turn serial, or state key differs;
- the planned action is no longer legal;
- the duel ends, replay begins, the scene exits, or the AI owner turn ends.

If the duel still requires an AI action after invalidation, the controller
starts the ordinary ten-second production search. It never executes a stale or
partially searched action.

## Expected Production Behavior

The 2026-08-28 production LazyOnly opening profile measured 14 real Quick
openings:

- all 14 completed old action depth two within ten seconds;
- nine completed old action depth three;
- none completed old action depth four.

In ordinary alternating openings, this predicts that complete-round depth one
should complete reliably, while complete-round depth two will not yet complete
within ten seconds. Extra-play branches may make even depth one more expensive,
but their whole current-owner chain is strategically required by this design.

The performance target remains completing complete-round depth two within the
production budget. Transition/state-copy work and canonical state-key
construction are separate optimization work and are not part of this change.

## Verification

### Depth semantics

1. In a quiet alternating fixture, depth one includes one action by each owner
   and evaluates only after two owner-turn boundaries.
2. Depth two in the same fixture matches the score/action of the former
   action-depth-four search.
3. One and several root-owner extra plays consume zero boundaries until the
   owner turn actually closes.
4. Opponent extra plays likewise remain inside the opponent half of the round.
5. An automatically completed empty owner turn consumes a boundary without
   creating a legal-action branch.
6. A start/end trigger that makes an empty turn actionable stops automatic
   advancement and is searched normally.
7. A single atomic transition that crosses several empty turns is evaluated
   only at its final actionable state.
8. A terminal result after the first half-round receives the unchanged
   terminal score immediately.

### Iterative deepening and caching

9. An interrupted depth-one iteration publishes no partial result and uses the
   greedy fallback.
10. An interrupted depth-two iteration retains the completed depth-one action,
    score, and plan.
11. Progress callbacks publish only completed complete-round depths.
12. Transposition lookups respect remaining-boundary coverage and preserve
    exact/lower/upper bound semantics.
13. Baseline, LazyOnly, and Lazy+PVS retain fixed-complete-round score/action
    equivalence.

### Continuation reuse

14. A completed search returns the exact planned extra action for the matched
    same-turn state.
15. Multiple extra plays consume successive plan entries without starting new
    search sessions.
16. A changed state key, owner, serial, or legal-action result invalidates the
    plan and starts a normal search.
17. A greedy fallback produces no reusable plan.
18. Returning to the AI after an automatically skipped opponent empty turn has
    a new serial and starts a normal search.
19. Replay never consumes a live AI continuation plan.

### Regression and measurement

20. Simulator and gameplay results remain unchanged because only search-depth
    accounting and controller search reuse change.
21. Search diagnostics and UI display complete-round depth consistently.
22. Re-run the 14-opening production profile with the ten-second budget and
    record complete-round depth distribution, nodes/s, fallback rate, and
    continuation reuse.
23. Run the canonical full suite and play an AI extra-play path with audio
    muted, verifying that only the first action pauses for thought.

## Documentation and Expected Implementation Surface

Implementation is expected to update:

- `scripts/duel_search.gd` for remaining-boundary depth accounting, completed
  principal-line continuation capture, and diagnostics;
- `scripts/duel_search_session.gd` for pure-data plan transport;
- `scripts/duel_controller.gd` for exact-state continuation consumption and
  invalidation;
- search, session, integration, and benchmark tests;
- `docs/AI_SEARCH.md`, `docs/ARCHITECTURE.md`, `docs/HANDOFF.md`, and
  `docs/TESTING.md` after implementation.

No catalog declaration, card-specific behavior, simulator rule, save schema,
replay format, music rule, or player-visible card description changes.

## Superseded Design

This design supersedes
`2026-08-28-dynamic-initiative-evaluation-design.md`. The large dynamic
initiative term proposed there must not be implemented as part of this work.
Complete-round leaves solve the identified parity problem at the search
boundary instead of compensating for it in evaluation.

## Out of Scope

- Changing the production ten-second budget.
- Implementing compact search state, faster state keys, or other performance
  optimizations.
- Enabling PVS, tactical extension, or evaluation caching in production.
- Adding named-card evaluator knowledge.
- Changing perfect-information access to hands or deck order.
- Changing gameplay owner-turn, empty-turn, extra-play, or terminal rules.
