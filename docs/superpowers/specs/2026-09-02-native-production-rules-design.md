# Native Production Rules Design

Date: 2026-09-02

## Goal

Make the native compact rules kernel the mandatory production transition path
for both the human player and AI search while retaining the existing GDScript
implementation as an explicit Oracle for tests and parity diagnosis.

At the same time, complete the two live catalog primitives required by
`LaiHeQinQuan4` and `LaiHeQinQuan5`, and remove two registered but unused legacy
primitives.

## Scope

This change covers production action transitions only. The existing GDScript
iterative-deepening search, ordering, pruning, deadlines, cancellation, and
same-turn plan reuse remain in place. Because that search calls the shared
transition entry point, every state it explores will nevertheless be produced
by the native rules kernel.

The test-only native whole-tree minimax remains test-only. Replacing the search
driver itself is a separate project.

## Catalog Vocabulary

### Implement

- `trigger_card_revealed_to_self`
  - Valid when the trigger card is revealed to the current owner of the ability
    source.
  - Uses the same runtime reveal information and source-owner relationship as
    the Oracle.
- `grant_trigger_card_ability`
  - Grants the declared normalized ability to the exact trigger-card instance.
  - It preserves passive abilities and replaces all activation-bearing
    abilities when the granted ability contains an activation, matching the
    existing dynamic-grant rule.
  - It must preserve declaration identity, trigger-handle behavior, event
    ordering, and runtime instance identity exactly as the Oracle does.

These primitives restore native parity for the live `LaiHeQinQuan4` and
`LaiHeQinQuan5` declarations.

### Remove

- `attack_targeted_attacker_ally`
- `spend_all_ki`

Neither primitive is used by a current card. Remove their catalog constants,
known-vocabulary entries, obsolete Oracle branches or payment recognition, and
stale tests. No compatibility alias is retained because there are no external
users or persisted runtime ability declarations.

## Production Architecture

`DuelSimulator` remains the public gameplay-rules facade required by repository
architecture. Its production `apply_action()` entry point delegates to one
native adapter that:

1. captures the supplied `DuelState` into `DuelCompactState`;
2. loads that root into `DuelNativeCompactKernel`;
3. invokes the matching native play or activation transaction;
4. restores the returned compact payload to a `DuelState`;
5. returns the canonical state, captures, exiles, and ordered presentation
   events in the existing transition dictionary shape.

`DuelController`, greedy fallback, and `DuelSearch` continue calling
`DuelSimulator.apply_action()`. Therefore the player, production AI, replay,
and any other normal caller share the same native rules path without acquiring
native-specific branches.

The old GDScript implementation moves behind an explicit
`apply_action_oracle()` entry point. Tests and parity tools may call it
directly. Production code must not call it.

## Failure Policy

There is no automatic Oracle fallback.

The following are fatal integration errors for a production transition:

- `DuelNativeCompactKernel` is unavailable;
- compact capture, native root loading, or result restoration fails;
- a reached declaration is unsupported;
- the native transaction reports an invalid result for an action already
  validated by the public facade;
- the result payload or transition arrays are malformed.

The adapter reports the precise native reason and returns no partially mutated
state. The controller must stop the affected action instead of continuing the
duel through the Oracle. Search must treat the failure as an integration fault,
not as an ordinary illegal child.

This fail-fast policy is intentional: with no external users, exposing missing
coverage immediately is preferable to silently running two production rule
engines.

## Oracle and Test Isolation

The Oracle remains independently callable and must not call the production
native facade recursively. Native parity tests follow this structure:

1. duplicate one identical input state;
2. resolve one branch through `apply_action_oracle()`;
3. resolve the other through the production native entry point;
4. compare exact state payload, captures, exiles, and every ordered event.

Existing rule-focused tests may continue to use the Oracle where their purpose
is to specify the reference semantics. Production integration tests must use
`apply_action()` and require the native extension.

## Coverage Guard

Add a native catalog audit covering every primitive reachable from every
current card, including nested `if`, selector actions, granted abilities, and
activation costs/actions. It must fail if any live declaration compiles to an
unsupported opcode or invalid native declaration.

Registered vocabulary that is not used by any card is not sufficient reason to
add native code. Unused primitives should instead be removed unless a concrete
near-term card requires them.

Focused parity fixtures cover both `LaiHeQinQuan4` and `LaiHeQinQuan5`:

- an unrevealed enemy summon does not receive the ability;
- a revealed enemy summon receives defending-power override zero;
- the ability is granted to the exact entering instance;
- source ownership and reveal direction are checked for both sides;
- state, event ordering, and later attack behavior match the Oracle.

## Performance

The first production integration may pay compact capture and restoration costs
at every GDScript search edge. Correctness is the adoption gate for this step,
but the existing production benchmark must record the resulting throughput and
completed depth before the change is considered finished.

If the round-trip adapter materially reduces search depth, the next optimization
is to keep the AI root and descendant tree native while preserving the same
production transition semantics. It is not acceptable to restore Oracle search
transitions merely to hide adapter overhead.

## Verification

Before completion:

1. build the Windows x86-64 GDExtension;
2. run the focused native probe, including the two new primitives and complete
   live-catalog audit;
3. run the full canonical test suite;
4. run the production search equivalence and timing corpus;
5. start a muted production game and exercise at least one ordinary player
   play and one AI response through the native adapter;
6. exercise the revealed-card branch of `LaiHeQinQuan4` or
   `LaiHeQinQuan5` with a deterministic fixture or testing-mode walkthrough;
7. confirm production scripts contain no call to `apply_action_oracle()`.

Android native packaging remains a known release gate. Until an Android ARM64
extension is built and verified, this design makes the current Windows
development production path native-mandatory but does not claim an Android
release is ready.

## Non-Goals

- No Oracle fallback in normal play.
- No production enablement of the test-only native minimax.
- No change to AI evaluation, ordering, pruning, time budget, or information
  access.
- No new card behavior beyond matching the current catalog declarations.
- No Android release claim in this change.
