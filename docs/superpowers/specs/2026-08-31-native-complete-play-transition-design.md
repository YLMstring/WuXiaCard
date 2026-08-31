# Native Complete Play-Transition Lifecycle

Date: 2026-08-31

## Status and Goal

This document defines the next test-only `DuelNativeCompactKernel` slice. The
authoritative rules remain `DuelSimulator`, and production search must not call
the native kernel yet.

The goal is implementation efficiency rather than an incremental coverage
target. The slice completes one coherent rules boundary: a legal hand play from
placement through summon reactions, attacks and nested actions, action finish,
owner-turn finish, terminal adjudication, and the next actionable owner turn.
The existing real-Quick rejection report remains useful as a regression
inventory, but it does not determine implementation order or acceptance.

The slice includes the remaining declarations currently reached by ordinary
play transitions: summon-before rules, event-context conditions, targeted
reaction attacks, conditional movement, in-place fresh re-summon, empty-deck
fallback draws, extra card plays, temporary and pending ability suppression,
turn-start and turn-end events, and automatic empty turns. Root activation
transitions, production AI integration, and unresolved queued-choice execution
remain outside this slice.

## Why the Play and Turn Boundaries Are One Slice

Separating summon-before support from turn lifecycle would duplicate and then
replace action-finish logic:

- `YunWu13Shi` temporarily removes non-retained abilities until the current
  owner turn ends, so correct summon-before execution requires exact boundary
  restoration.
- `DuGu9Jian` may grant an extra card play during summon-before resolution, so
  that same action must decide whether to remain in the current owner turn or
  dispatch end-turn rules.
- pending non-retained suppression created by one play is consumed by a later
  non-internal card play, potentially in the next owner turn.
- an end-turn rule may itself grant an extra card play, after which the next
  action must resume the already-partially-finished owner turn without firing
  end-turn rules twice.

The efficient boundary is therefore the complete authoritative
`_apply_play_action()` plus `_finish_action()` lifecycle, not an arbitrary list
of currently rejected card roots.

## Native Structure

The current monolithic `apply_play_transition()` will become an orchestration
method over reusable typed helpers.

### Summon lifecycle

`resolve_summon_lifecycle()` accepts an exact runtime card index, target cell,
owner, summon reason, and source metadata. It is shared by a hand play and by a
fresh in-place re-summon. It must preserve the oracle order:

1. place the card in the board state while buffering the visible placement or
   summon event;
2. consume any pending non-retained suppression applicable to this hand play;
3. dispatch `CARD_BEFORE_SUMMONED` and emit its results before the buffered
   placement/summon event;
4. dispatch `CARD_SUMMONED` globally;
5. if the exact instance still exists, dispatch `CARD_AFTER_SUMMONED` using its
   current cell and owner;
6. if the exact instance still exists and still belongs to its summoning owner,
   resolve its standard summon attack.

If the card leaves the board during an earlier stage, later self-dependent
stages do not run. If its owner changes during summon resolution, its standard
attack is cancelled by the existing general ownership rule; no card-specific
exception is added.

The placement/summon event shape remains source-sensitive: a hand play emits
`card_placed`, while an ability-created fresh card emits `card_summoned` with
the same source, prior-zone identity, reason, and card snapshot fields as the
oracle.

### Attack lifecycle

`resolve_attack_request()` owns the common attack transaction used by summon
standard attacks and `ACTION_ATTACK_TRIGGER_CARD`. It receives an exact
attacker, an optional locked target, attack reason, repeat flag, and typed
attack policy. It reuses the existing generic modifier and target-policy code.

The helper preserves the twenty-attacks-per-owner-turn limit, initial target
and power legality, `CARD_BE_ATTACKED`, flip prevention, flip timing, ownership
changes, attack-flip records, and `CARD_AFTER_ATTACK`. A targeted reaction does
not retarget if its locked exact target becomes invalid. An attacker that leaves
the board or changes owner terminates the remaining attack loop.

### Movement lifecycle

`move_card_between_cells()` becomes the common primitive for conditional entry
movement and existing swaps. `ACTION_MOVE_SELF_TO_FIRST_EMPTY_BETWEEN_ENEMY`
scans the board in the same row-major cell and direction order as the oracle,
locks the first matching middle cell, then runs the complete before/moved/after
movement lifecycle. Revalidation uses exact card indices and owners.

### Action finish and owner-turn lifecycle

`finish_action()` mirrors the authoritative ordering:

1. increment action count and state version;
2. apply extra-card-play requests generated during the action;
3. if a legal extra hand play remains, keep the same active owner and return;
4. otherwise dispatch `TRIGGER_END_OWNER_TURN` once;
5. apply extra-card-play requests generated at end turn and return to the same
   owner if one remains legal;
6. dispatch the before-full-board-end event when applicable;
7. restore temporary ability-suppression batches expiring at this boundary;
8. increment `owner_turn_serial`, reset both attack counters and the
   end-turn-resolved flag, and record board repetition;
9. adjudicate terminal state after the completed turn and before the next
   start-turn event;
10. advance to the other owner and dispatch `TRIGGER_START_OWNER_TURN`;
11. if that owner has no legal action, still dispatch its start and end events,
    complete its boundary, adjudicate again, and continue until an actionable
    or terminal state is reached.

An input with remaining extra card plays consumes one before resolving the new
hand play. An input whose end-turn rules were already resolved may finish that
owner turn without dispatching them again. Reaching the action limit does not
interrupt already-granted extra plays.

## Typed Event Context and Declarations

`EventContext`, the declaration compiler, and the action executor gain generic
typed support for the following current declaration vocabulary:

- trigger card is in the ability source's attack range;
- the ability source has an empty cell between itself and an enemy;
- the trigger card was outside the ability source owner's hand;
- the current turn owner is the ability source owner;
- attack the exact trigger card;
- move self to the first empty cell between self and an enemy;
- re-summon an exact referenced card in place;
- reveal hand cards using typed recipient and reveal-filter opcodes;
- grant extra card plays;
- temporarily remove non-retained abilities;
- add pending non-retained suppression for a relative owner.

Range checks use the same general attack-range and modifier semantics as
`DuelRules`; they are not adjacency shortcuts. Outside-hand checks use the
pre-exile zone and owner snapshot carried by the event context. Turn conditions
use the explicit `turn_owner` context and never infer the value from the active
player after nested resolution.

No native compiler or executor branch may inspect a named card ID.

## Temporary and Pending Ability Suppression

Each native runtime card gains typed suppression batches. A batch stores its
expiry `owner_turn_serial` and ordered entries containing the removed runtime
ability handle, compiled declaration index, and original array position. The
batch belongs to the exact runtime card index, so it follows that same instance
between board, hand, discard, and removed zones.

At an owner-turn boundary, restoration visits every live zone in authoritative
order, restores expired entries at their original relative positions, and emits
one `ability_gained` event per restored ability. A destroyed instance's batches
cannot attach to a fresh card that happens to share its card ID. Permanent
non-retained removal clears temporary batches just as the oracle does.

The compact boundary continues to serialize the existing
`temporary_suppression_batches` declaration shape. Loading compiles it into
typed runtime batches; restoring a payload reconstructs the lossless declaration
data so a returned state can be loaded by another native call or restored to
`DuelState` with exact parity.

Pending non-retained suppression remains stored by owner in the existing compact
scalars. A hand play by that owner consumes one charge only for a non-internal
card. Consumption occurs before summon-before triggers, removes every current
non-retained ability permanently, clears its temporary batches, and emits the
same suppression-consumed and ability-lost events as the oracle.

## Fresh In-Place Re-summon

`ACTION_RESUMMON_CARD_IN_PLACE` resolves an exact referenced board card:

1. revalidate the card, current cell, and current owner;
2. emit `card_departed_for_resummon` and remove the old instance without exile
   or discard processing;
3. append a fresh runtime card from the immutable prototype for the same card
   ID, with a collision-free generated instance ID and catalog-default powers,
   ki, abilities, and suppression state;
4. preserve the current owner as the new instance's owner and original owner;
5. run the shared fresh summon lifecycle in the vacated cell.

The old card index remains an unreferenced tombstone so previously snapshotted
references observe that exact instance as gone. Missing fresh metadata is an
unsupported branch, never an approximation.

## Draws and Empty-Deck Fallback

Draw actions remain sequential. When a requested draw reaches an empty deck,
the draw primitive creates two fresh `TaiZuChangQuan` cards in deck order and
then draws the current top card. A multi-card draw may therefore refill more
than once. Every generated card receives a collision-free instance ID and the
same owner, hand slot, reveal state, difficulty hand-change processing, and
draw events as the oracle.

`DuelCompactState` explicitly includes the fallback prototype in the immutable
fresh-card table; the native executor never calls the catalog or checks the
fallback card ID in transition code. The prototype is identified through a
dedicated compact rule-metadata reference established at root capture.

The difficulty-eight hand rule is resolved after every hand-size mutation. The
first time the opponent hand becomes exactly one card, it draws once and records
the consumed flag. Difficulty nine inherits this rule; its opening power bonus
is already reflected in the captured root state and needs no transition-time
special case here.

## Terminal and Repetition Ordering

Full-board, action-limit, and fivefold-repetition adjudication occur only after
the current owner turn has completed and before the next owner-turn start event.
Extra plays already granted remain actionable even when the action count has
reached or exceeded the limit. Empty turns still record their boundaries and
board signatures. Before a full-board terminal result, the generic
`TRIGGER_BEFORE_DUEL_END` event is dispatched and may change the state enough to
prevent immediate adjudication.

## Atomic Unsupported-Branch Behavior

Every public call executes against a private `NativeState next`. Declaration
shapes are compiled up front, but branch-dependent unsupported constructs reject
only when the branch is actually reached. A failure at any nested summon,
attack, exile, draw, movement, turn, or terminal event returns
`supported = false` without a state payload, events, captures, or exiles. The
loaded root state is unchanged.

No helper is allowed to publish a partially resolved transition merely because
earlier substeps were valid.

## Testing and Acceptance

Focused native-oracle parity fixtures will cover:

- summon-before self-exile and event ordering;
- reveal-all hand behavior;
- extra plays granted during summon-before and end-turn rules;
- resuming a partially finished owner turn without duplicate end triggers;
- pending suppression consumption by a non-internal card and its exemption for
  an internal card;
- temporary suppression across board/hand/discard/removed zones, exact-position
  restoration, permanent removal, and fresh-instance isolation;
- trigger-range reaction attacks and locked-target invalidation;
- conditional first-empty-between-enemy movement with full movement events;
- fresh in-place re-summon followed by entry abilities and standard attack;
- sequential empty-deck fallback draws and repeated refill;
- difficulty-eight first-one-card draw behavior;
- terminal ordering at the action limit and full board;
- start/end events for automatic empty turns;
- fivefold repetition recording across empty turns;
- a deeply reached unsupported declaration returning no partial output.

The fixed real-Quick probe must continue to report the same legal opening set.
Every newly or previously supported transition must match `DuelSimulator`
exactly in restored state, canonical state key, state version, captures, exiles,
and ordered event payloads. Coverage may rise as a consequence, but no numeric
coverage threshold is an acceptance criterion.

After focused probes pass, run the canonical full suite:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
```

Record the native microbenchmark after correctness is established. A regression
is investigated, but correctness and architectural closure take priority over
preserving a particular prototype speed ratio.

## Production Boundary

This design does not authorize production integration. `DuelSimulator` remains
authoritative for human play, testing mode, greedy fallback, and deep AI. Native
adoption still requires action generation, activations, evaluation, state keys,
tree traversal, packaging, and broader generated-state parity to be proven as a
coherent native search path.
