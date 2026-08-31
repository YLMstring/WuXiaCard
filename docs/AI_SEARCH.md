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

## State-Copy Contract

Search branches receive independent runtime state. Card dictionaries, powers,
ability-membership arrays, revelation audiences, temporary suppression batches,
and all state-level queues/maps are copied. Normalized ability declarations and
their nested trigger/action/condition data are immutable and may be shared
between branches. Gameplay code may add, remove, replace, suppress, or restore
whole ability declarations, but must never mutate a declaration in place.

`DuelState.duplicate_state_deep_reference()` retains the former fully deep
copying path as a test and benchmark oracle; production transitions use the
selective runtime copy.

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

## Selective Runtime State-Copy Profile (2026-08-29)

`DuelState.duplicate_state()` now copies the runtime card dictionary plus every
mutable nested container: powers, ability membership, revelation audiences,
and temporary suppression batches. Normalized ability declarations and their
nested contents are immutable and shared. The former fully deep-copying path is
retained as `duplicate_state_deep_reference()` for parity checks and timing.

The 512-state/1,024-action transition microbenchmark compared the two copy
paths directly. Selective copying reduced 3,072 copies from `0.914s` to
`0.616s` (`1.483x` throughput), with all 512 canonical state keys equal. The
complete transition pass fell from the pre-change `4.733s` to `4.478s`, about
`5.4%`.

Against the preceding 14-opening production report, using the same real Quick
openings and ten-second budget:

- aggregate throughput increased from `547.48` to `592.05` nodes/s (`+8.14%`);
- mean complete-round depth-one time fell from `0.572s` to `0.512s` (`-10.51%`);
- complete-round depth two increased from `2/14` to `3/14` openings;
- all openings completed depth one with zero fallback;
- all 14 depth-one scores, root actions, and exact opening-state digests
  matched the preceding report.

The retained report is
`.summer/local/ai-benchmarks/production-opening-depth-1787994355.json`.

## Immutable Trigger Snapshot and Played-Card Move Profile (2026-08-29)

Two remaining redundant deep copies were removed under the immutable ability
declaration contract. Playing a hand card now moves the already isolated
runtime card from the copied hand onto the copied board. Trigger groups and
their resolving contexts share the immutable ability declaration used as the
snapshot; the surrounding mutable context is still deep-copied.

An in-process interleaved old/new comparison covered 1,024 real actions. All
resulting state keys, captures, exiles, events, and source states matched. The
three-pass transition time fell from `4.174s` to `4.061s`, about `2.8%`.

The same 14-opening production profile showed a smaller, near-noise real-search
change: throughput rose from `592.05` to `597.47` nodes/s (`+0.92%`), while the
three fixed 5,000-node probes improved only `0.29%`. Complete-round depth two
remained `3/14`; mean depth-one time fluctuated from `0.512s` to `0.518s`.
All 14 depth-one scores, actions, and exact opening-state digests still matched.
The change is retained because it removes work without adding runtime state,
branches, or maintenance machinery—not because the production profile proves
a large speedup.

The retained report is
`.summer/local/ai-benchmarks/production-opening-depth-1788002470.json`.

## Selective Runtime Action-Context Copy Profile (2026-08-30)

`DuelAbilityExecutor.execute_actions()` and its generic selected-card loop now
isolate runtime contexts with a shallow top-level copy. The
`card_reference_snapshots` mapping is copied separately because actions add and
replace reference keys. Snapshot payloads, selector conditions, ability
declarations, and the other nested context values remain shared under their
read-only contract. Top-level fields such as discard-batch size remain isolated
by the outer copy.

The 512-state/1,024-action transition benchmark measured 3,072 calls per mode.
An in-process interleaved old/new comparison reduced transition time from
`4.482s` to `4.192s` (`+6.92%` throughput). All 3,072 resulting exact state
keys, captures, exiles, and event arrays matched. A separate ordinary before/
after run moved from `3.936s` to `3.769s` (`+4.23%`). The simulator regression
suite also verifies that nested selected-card execution cannot add reference
snapshots to its caller's context.

Against the preceding 14-opening production report, with the same real Quick
openings and ten-second budget:

- aggregate throughput increased from `597.47` to `629.57` nodes/s (`+5.37%`);
- mean complete-round depth-one time fell from `0.518s` to `0.481s` (`-7.22%`);
- the fixed 15,000-node timing probe fell from `23.531s` to `22.022s` (`-6.41%`);
- complete-round depth two remained `3/14`, and every opening completed depth
  one without fallback;
- all 14 depth-one scores, actions, and exact opening-state digests matched.

The retained report is
`.summer/local/ai-benchmarks/production-opening-depth-1788048800.json`.

## Compact-State Foundation (2026-08-30)

`DuelCompactState` is an experimental, lossless snapshot boundary for a future
native simulator. It is not a second rules engine and production search does
not use it yet. `DuelSimulator` remains authoritative.

The compact layout stores:

- board occupancy as nine card indices plus owner bytes;
- hand, deck, discard, and removed-zone order as packed card-index arrays;
- each runtime instance ID once;
- four powers in one contiguous integer array;
- original owner, ki, hand slot, and runtime-field presence in packed arrays;
- reveal audiences in a five-state byte code that preserves both membership
  and the observable `[1, 2]` versus `[2, 1]` order;
- immutable card templates, active-ability sets, and suppression sets in
  interned pools shared by branch copies;
- uncommon state-level containers in a lossless mutable side payload until
  each receives a proven native representation.

The codec restores a complete `DuelState`, including live-only `state_version`.
Its regression suite covers a deliberately nonempty edge state plus 512 exact
states derived from all 14 real Quick openings. Exact canonical state keys and
state versions match after every round trip. This coverage caught and fixed an
initial reveal-order loss that a simple visibility bitmask would have hidden.

The retained 512-state microbenchmark reports:

- average full source payload: `41,604.4` encoded bytes;
- average standalone compact snapshot including immutable pools: `26,322.2`
  bytes (`63.3%` of source);
- average mutable branch payload excluding shared immutable pools: `5,295.9`
  bytes (`12.7%` of source);
- 2,560 ordinary state copies: `0.495s`;
- 2,560 compact branch copies: `0.069s`, about `7.19x` faster;
- 512 captures: `0.676s`; 512 full restores: `10.958s`;
- zero round-trip mismatches.

The capture/restore result fixes the native boundary: conversion may happen
once when search starts and once for the selected result, but never once per
node. The whole searched tree must remain compact and native. Porting only
state copying would leave most trigger and action-resolution cost in GDScript
and cannot justify the extension maintenance burden.

The first C++ GDExtension prototype should therefore:

1. consume the documented compact root layout in one coarse call;
2. keep branch states, cloning, keys, and representative transitions native;
3. return complete pure-data states/events only at the boundary;
4. compare every native transition against `DuelSimulator` on generated real
   states before it can enter production;
5. remain disabled in production until the same authoritative transition path
   can serve human play, testing mode, greedy fallback, and deep AI;
6. benchmark transition throughput, nodes/second, completed depth, Windows
   loading, and Android ARM64 packaging—not merely native loop speed.

The existing simulator remains the oracle throughout migration. No named-card
branch may enter native search code; catalog declarations and generic rules
remain the semantic source of truth.

### Native boundary probe

The first opt-in Windows GDExtension probe is now present under
`native/duel_core/`. It pins official `godot-cpp` commit
`101ae38034304346a46ea9ea84ae156d3e860496`, generates bindings for API 4.6,
and keeps its DLL, generated `.gdextension`, and CMake intermediates out of
version control. Production scripts do not reference the extension.

`DuelNativeCompactKernel` accepts both the original mutable clone-probe payload
and a complete compact payload with immutable metadata pools. It converts the
packed runtime arrays into owned C++ vectors, validates all fixed lengths, and
keeps branch cloning native. Production integration remains forbidden until
complete transition semantics and Windows/Android packaging are both proven.

### Native play-transition slices

The opt-in kernel implements a deliberately narrow generic play path. Its first
slice resolves normalized hand plays through placement, orthogonal power
comparison, standard adjacent attacks, ownership flips,
`last_hand_play_by_owner`, action/state version increments, owner-turn
boundaries, empty-turn advancement, attack-count reset, repetition recording,
and action-limit/full-board/fivefold terminal checks. The result is a complete
compact payload plus capture, exile, and event arrays suitable for one boundary
restore.

Unsupported semantics are never approximated. The prototype resolves each
action on a private native branch and rejects the whole branch when a relevant
declaration or runtime feature lies outside the covered slice; rejected results
contain no payload, events, captures, or exiles. State abilities, temporary
suppression, queued effects, pending choices, extra plays, a partially resolved
turn end, pending hand-play suppression, mixed negative powers, and difficulty
8/9 hand rules remain unsupported. Exact four-sided `-1` cards are supported as
the generic special-negative shape: they can be attacked, cannot win an attack,
and are not legal power-change subjects.

The second slice compiles every interned immutable ability set once when the
compact root is loaded. Search nodes consult typed event, condition, action, and
modifier opcodes instead of walking nested `Dictionary` declarations. Each
runtime card carries an ordered branch-local list of compiled ability entries
with stable transient handles. Real removal erases an entry; trigger discovery
snapshots handles rather than array positions, so deleting an earlier ability
does not invalidate an already discovered later trigger merely because it
shifts index. Derived `active_abilities` arrays are interned at the output
boundary. Draws consume the exact deck front one card at a time, fill the
physical leftmost empty hand slot, reconstruct the complete runtime card
snapshot in each `card_drawn` event, obey the five-card hand cap, and finish
before the standard summon attack.

The current lifecycle slice supports `card_be_attacked`,
`card_before_flipped`, `card_flip_prevented`, `card_after_flipped`,
`card_before_exiled`, `card_after_exiled`, and `card_after_attack`, in addition
to `card_after_summoned`. Trigger groups are discovered in board row-major order
as snapshots and revalidated immediately before resolution. Supported generic
actions are constant unfiltered draws, trigger/source/attacker exile, self
exile, flip prevention, and removal of the resolving ability. Supported
modifiers now include constant defending-power override, other-ally attack
requirements, minimum-side defense, configurable orthogonal range two,
comparison reversal, adjacent-summon allies-only redirection, unlimited range,
non-orthogonal axes, first-legal target locking, owner-turn enemy attack
prohibition, attacker-local indiscriminate attacks, and global
`enemy_attacks_all` with its capture-owner rule.

The generic native attack module resolves policy precedence, generates
candidates in the same directional or row-major order as `DuelRules`, applies
geometry/intervening-card permissions, compares powers once, locks the target
cells, and revalidates only non-power legality after `card_be_attacked`.
Adjacent-summon redirection snapshots exact source instances when the card
enters and requires the same source to remain adjacent, hostile, present, and
enabled immediately before the standard attack. The authoritative GDScript
path now also enforces the previously approved one-comparison rule for locked
targets. Four-sided `-1` semantics take precedence over comparison reversal in
both implementations: an ordinary numbered card can still attack such a
defender, while such an attacker cannot win by reversing the comparison.

Normal flip changes ownership, emits the canonical flip and ability-loss
events, preserves `retained_on_flip`, defers isolated self-after-flip abilities
until their event has resolved, and then removes those deferred abilities.
Exile preserves the exact runtime instance, dispatches before/after events,
removes board/hand/discard subjects without repacking hand slots, returns the
instance to its valid original owner's removed zone, and guards recursive exile.
These declarations are card-agnostic; the real `BaGuaFangWei` and
`LeiZHenJian1`–`LeiZHenJian3` work through the same opcodes as synthetic probes.

The medium generic-executor slice recursively compiles nested action lists and
passes an explicit immutable action context through selection and execution.
Selectors cover board, hand, deck, and discard with the catalog's ordering,
owner, power, ability, and geometry conditions. Selection snapshots exact
instances; each chosen target is revalidated before use and an invalid target
is skipped without refilling the selection. Nested actions include
`for_each_selected_card`; power changes support fixed and hand-count amounts,
batch event assignment, and canonical four-zero exile. Ki gain/spend emits and
immediately resolves `card_ki_changed`; non-attack self-flips use the same
before/prevented/after lifecycle as other flips. Dynamic passive grants append
once, while a granted activation replaces every existing activation and
preserves passive abilities. Newly granted declaration trees are recursively
interned, so an unsupported future branch is rejected only if execution
actually reaches it.

The return/movement slice adds immutable catalog-fresh prototypes to each
compact root. An ordinary board return destroys the located runtime instance,
appends a new default card index with a collision-free generated instance ID,
fills the recipient's physical-leftmost hand slot, and emits the public
`card_returned_to_hand` / `card_revealed` pair. The destroyed index remains an
unreferenced tombstone inside that native branch so stable indices are never
reused; restoration naturally omits it because no board or zone references it.
A full recipient hand instead runs the existing before/after exile lifecycle
with reason `return_to_full_hand`.

`self_swapped_with_ability_source` is implemented as two ordered movements.
Each leg dispatches the global `card_before_moved`, emits `card_moved`, then
dispatches `card_after_moved`; exact instances, cells, owners, and movement
conditions are revalidated between steps. A before-move power loss can remove
the mover and cancel relocation. Unknown reached movement actions reject the
private native branch atomically, while dormant unsupported declarations do
not reduce coverage.

The discard/transform slice adds list-local execution state for the current
action source cell and most recent successful discard-batch size. `if` child
actions share that state, while each selected-card child list receives the
same shallow contextual isolation as the oracle. Single and batch discard
snapshot exact card indices, revalidate without refill, move every valid card
before reactions, emit the canonical shared batch ID and one final physical
hand-slot shift, then resolve each discarded instance's own
`card_after_discarded` rule before one row-major `discard_batch_finished`.
Discard-only trigger discovery never scans unrelated cards. Nested discard
events preserve both the discarded listener and the original ability-source
snapshot, which may be different instances.

Fresh prototype capture now follows transform declarations transitively, so a
root containing `SanRuDiYu1` carries only the reachable
`SanRuDiYu1`–`SanRuDiYu3` chain rather than the whole catalog. Transform
rebuilds powers, ki, template/card ID, active abilities, runtime handles, and
suppression from the fresh prototype while preserving the same instance ID,
original owner, current zone owner, reveal order, and hand slot. A preserved
discard return moves that exact index to the recipient's leftmost empty hand
slot and reveals it to the opponent only if newly visible; a full hand exiles
the same transformed instance with `return_to_full_hand`.

The support gate is action-specific: abilities in hand/deck remain dormant, an
unrelated listener whose supported conditions are false remains dormant, and
only declarations reached by the current event cause mid-branch rejection.
Empty-deck generated cards, future draw revelation, after-draw listeners,
summon and non-swap movement flows, nested or extra attacks, start/end-turn
lifecycle, and still-uncompiled condition/action
variants remain rejected rather than approximated.

The native probe covers the original five oracle transitions,
`TuNaShu1`–`TuNaShu3` for both owners, both-owner Bagua exile, all three LeiZhen
tiers, defending-power override, indiscriminate attacks, attacker/target exile,
flip prevention, retained/ordinary/deferred flip cleanup, after-attack ability
removal, after-exile snapshot conditions, recursive-safety rejection, gapped
physical hand slots, hand-cap truncation, and draw ordering. The expanded
generic-attack fixtures additionally cover all remaining attack
modifiers, policy precedence, both intervening-card permissions, special
negative powers under reversal, summon-redirect source revalidation, and
unlimited/non-orthogonal first-target locking, post-reaction other-ally
revalidation, and first-target exile without fallback. Selector/nested-action
fixtures additionally cover all four zones, ordering and owner filters,
no-refill revalidation, dynamic and batched power changes, four-zero exile,
immediate ki-change dispatch, non-attack flip, passive-grant deduplication,
activation replacement, and declarations containing unsupported future
branches. Return/swap fixtures cover mutated-to-fresh reconstruction, generated
ID collisions, hand slots and public reveal order, full-hand exile, missing
prototype rejection, both real swap declarations, before/after movement
listeners, mover removal, and unsupported-listener rejection. Before the
discard slice, that probe covered 973 checks with exact parity.

Discard/transform fixtures additionally cover conditional true/false branches,
single and batch discard, noncontiguous physical-slot compression, actual
batch-size gating, in-place catalog reconstruction, inherited source context,
new and already-public preserved returns, and same-instance full-hand exile.
Across 1,034 checks, restored canonical state keys, live state versions,
captures, exiles, and every event match `DuelSimulator`.

The same probe enumerates every legal root play in the 14 unique real Quick
openings. Before the return/swap slice it found 490 legal plays: 341 were
supported and all 341 had exact full-state/event parity; 149 were explicitly
rejected with zero partial results. The first rejection reasons were 46
unsupported actions, 35 start-turn rules, 28 end-turn rules, 19 unsupported
trigger conditions, 14 before-summoned rules, and 7 empty-deck fallback draws. The probe also prints
the corresponding reason counts by source card ID, currently covering 22
cards. This is a coverage report, not an adoption threshold.

After discard transactions, conditional lists, transform, and preserved return
support, the same fixed openings now support 384 of 490 plays, all 384 with
exact parity and zero mismatches. The remaining 106 rejections are 35
start-turn rules, 28 end-turn rules, 19 unsupported trigger conditions, 14
before-summoned rules, 7 empty-deck fallback draws, and 3 unsupported actions.
Those last three are `KuiHua3` roots that complete their swap before reaching
the still-uncompiled re-summon action; the conservative gate correctly rejects
the whole private branch instead of returning a partial result.

The latest 5,000-transition Debug plain-card probe returned full compact
payloads and events in `343,789` microseconds versus `4,018,571` microseconds
for the authoritative GDScript transition loop, about `11.69x` faster. This is
evidence that a coarse native transition can be worthwhile, not a
production-search forecast: it excludes compact-to-`DuelState` restoration,
general declarations/triggers, state keys, evaluation, and tree traversal. The
same run completed 100,000 native branch clones at about `714,536` clones per
second.

## Missing AI Work

- Fivefold board repetition is adjudicated by the shared simulator before the
  search receives another actionable state; there is no search-only draw rule.
- Native root-action coverage is still 384/490 on the real Quick openings; the
  categorized rejections identify the next generic declaration slices.
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
