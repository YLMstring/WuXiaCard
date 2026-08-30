# Native Attack, Flip, and Exile Slice Design

Date: 2026-08-30

## Objective

Extend the opt-in native compact-state prototype from one isolated
self-after-summoned draw rule to a complete attack lifecycle slice. The slice
will compile and resolve enough generic declarations to cover opening
`BaGuaFangWei` and the complete passive behavior of `LeiZHenJian1` through
`LeiZHenJian3`, without checking any card ID, glyph, tier, sect, or name.

The work is intentionally larger than another single-action port. It establishes
a reusable native event dispatcher, mutable runtime ability membership, special
negative-power attack semantics, ownership flips, and the full exile lifecycle.
`DuelSimulator` remains the authoritative oracle. Production search,
controllers, testing mode, and greedy fallback continue to ignore the extension.

## Chosen Vertical Slice

The phase follows one standard attack from its initially selected targets until
each target has either been flipped, exiled, or invalidated. It includes the
events and mutations needed along that path instead of adding isolated card
special cases.

The declaration compiler will recognize the following event families:

- `CARD_BE_ATTACKED`;
- `CARD_BEFORE_FLIPPED`;
- `CARD_FLIP_PREVENTED`;
- `CARD_AFTER_FLIPPED`;
- `CARD_BEFORE_EXILED`;
- `CARD_AFTER_EXILED`;
- `TRIGGER_CARD_AFTER_ATTACK`;
- the already supported `TRIGGER_CARD_AFTER_SUMMONED`.

The first compiled conditions are:

- `CONDITION_TRIGGER_CARD_IS_SELF`;
- `CONDITION_ATTACKED_CARD_IS_SELF`;
- `CONDITION_ATTACKER_CARD_IS_SELF`;
- `CONDITION_ATTACKER_CARD_IS_ENEMY`;
- `CONDITION_TRIGGER_CARD_WAS_ON_BOARD`;
- `CONDITION_ATTACK_FLIPPED_ENEMY`;
- `CONDITION_TRIGGER_CARD_POWERS_COULD_CHANGE`.

The first compiled actions are:

- `ACTION_EXILE_CARD` for `CARD_REF_TRIGGER_CARD`,
  `CARD_REF_ABILITY_SOURCE`, or `CARD_REF_ATTACKER_CARD`;
- `ACTION_EXILE_SELF`;
- `ACTION_PREVENT_TRIGGER_FLIP`;
- the existing constant, unfiltered `ACTION_DRAW_CARDS` primitive at any
  supported event boundary;
- `ACTION_REMOVE_THIS_ABILITY`.

The first compiled attack modifiers are:

- `MODIFIER_DEFENDING_POWER_OVERRIDE` with a constant integer value;
- `MODIFIER_ENEMY_ATTACKS_ALL`, including its generic target and capture-owner
  policy.

This exact combination covers Bagua's retained self-before-flip exile and the
LeiZhen family's defending-power override, self-exile when attacked,
before-exile draw, and tier-three indiscriminate enemy attack rule. The native
executor remains declaration-driven; those catalog cards are parity fixtures,
not dispatch keys.

## Compiled Event Runtime

Each interned immutable ability set is compiled once when the compact root is
loaded. A compiled ability records:

- its original ability and trigger indices;
- `retained_on_flip`;
- event opcode;
- condition opcodes and their immutable arguments;
- action opcodes and their immutable arguments;
- modifier opcodes and constant values;
- an opaque unsupported flag for semantics outside this phase.

No searched branch walks nested Godot `Dictionary` declarations. Event
discovery scans board cells in row-major order and snapshots groups before any
group resolves. Each group stores the event, source cell, source instance,
source owner, ability index, and trigger index. Immediately before execution,
native code revalidates that the same source instance still occupies the
expected location, still has the expected owner, and still has that ability
enabled. Earlier groups may therefore invalidate later groups without causing
rediscovery or replacement.

Events are dispatched only when the authoritative transition reaches their
boundary. An unsupported declaration in a dormant zone or an unrelated event
family does not reject the action. If relevance cannot be proven false cheaply,
the gate rejects conservatively.

## Mutable Ability Membership

Immutable declaration contents remain shared. Each runtime card gains native
branch-local membership state over the ability set captured at the root. The
representation is a compact enabled bitmap or equivalent packed membership
array, not a copied declaration tree.

The membership state supports:

- removing ordinary non-retained abilities during a flip;
- retaining every ability with `retained_on_flip = true`;
- keeping old isolated self-`CARD_AFTER_FLIPPED` abilities available until
  their deferred event resolves;
- removing those deferred old abilities after the event;
- removing the currently resolving entry for `ACTION_REMOVE_THIS_ABILITY`.

At the GDScript result boundary, derived active-ability arrays are materialized
from immutable declarations and enabled membership. The boundary may append
derived sets to the returned metadata pool, but native branches do not allocate
or traverse Godot declaration Dictionaries per node.

Runtime ability grants, replacements, or copied/granted declarations remain
unsupported in this phase. A root snapshot that already contains a dynamically
granted normalized ability is valid because that current ability set becomes
its immutable root set; an action that would add or replace membership during
the native transition is rejected.

## Standard Attack Flow

Target selection preserves the current locked-target rule. For every standard
attack invocation:

1. Check the attack limit and any supported prohibition or target policy.
2. Select initially legal targets in the authoritative order and compare powers
   exactly once.
3. If no target passes, emit no `attack_started` and do not run
   `TRIGGER_CARD_AFTER_ATTACK`.
4. If at least one target passes, increment the attack count once for the
   invocation.
5. For each locked target, emit `attack_started` and dispatch
   `CARD_BE_ATTACKED`.
6. Revalidate the exact attacker and target instances. If the target was
   removed or otherwise became invalid, end only that target's resolution and
   do not search for a replacement.
7. Determine the committed new owner and dispatch `CARD_BEFORE_FLIPPED`.
8. If a supported action explicitly prevents the flip, emit
   `CARD_FLIP_PREVENTED` and dispatch that event. Removing the target is not flip
   prevention and emits no prevention event.
9. If both instances remain valid, resolve the staged ownership and ability
   cleanup described below.
10. If the attacker changes owner or leaves the board during a target's chain,
    stop the remaining target loop. Moving alone would not cancel a locked
    target, but movement is outside this phase and therefore rejected if it
    becomes relevant.
11. After the target loop, dispatch `TRIGGER_CARD_AFTER_ATTACK` exactly once
    when at least one `attack_started` event was emitted, even if every attacked
    target was later removed before flipping.

The `MODIFIER_ENEMY_ATTACKS_ALL` policy may add adjacent cards owned by the
attacker to the initially legal target set. A successful attack on an old ally
uses the modifier source's owner as the capture owner, matching the generic
simulator policy.

## Staged Flip Flow

For a committed flip that was not prevented or invalidated:

1. Snapshot the old isolated self-`CARD_AFTER_FLIPPED` entries.
2. Change ownership first while preserving ki and mutable powers.
3. Remove old non-retained abilities other than the deferred self-after-flip
   entries and emit the exact `ability_lost` events in authoritative order.
4. Emit `card_flipped` and record the target cell in captures.
5. Dispatch `CARD_AFTER_FLIPPED` using the old trigger context and the card's
   new current owner.
6. Remove the deferred old self-after-flip entries and emit their cleanup
   events.
7. Preserve every `retained_on_flip` entry throughout the sequence.

Any supported action that removes the target during `CARD_AFTER_FLIPPED`
continues through the exile transaction. Unsupported after-flip actions abort
the private native branch and return `supported = false`; no partial state or
events escape.

## Special Negative Powers

A card whose four powers are exactly `[-1, -1, -1, -1]` is no longer a global
reason to reject the compact state.

- A nonnegative facing attack power beats `-1` through the ordinary comparison,
  so any ordinary numbered card can attack it.
- A `-1` attacker does not beat a nonnegative defender or another `-1` card.
- Special-negative cards remain illegal targets for power-changing effects.
- This phase does not support mixed negative/nonnegative power arrays; those
  states remain explicitly unsupported.

The behavior is defined by powers and declarations, not by the Bagua or YinYang
card IDs. YinYang's summon-time exile, filtered draw, selectors, and granted
abilities remain outside this phase, so playing it is still rejected even
though merely storing the card or attacking it can use the generic negative
power rule when all other relevant semantics are covered.

## Exile Transaction

A supported exile action resolves as one generic exact-instance transaction:

1. Snapshot the target's instance, zone, logical index, current owner, original
   owner, card contents, and pre-exile powers.
2. Dispatch `CARD_BEFORE_EXILED` for board and hand subjects.
3. Re-locate the same instance in its original zone and owner after the before
   event.
4. If it still exists there, remove it from board, hand, or discard. Hand exile
   erases only its physical hand-slot field and does not close the gap.
5. Append the same runtime instance to its valid original owner's removed zone,
   falling back to its current owner only when the original owner is invalid.
6. Emit the exact `card_exiled` payload and add the former board cell to the
   transition exile array when applicable.
7. Dispatch `CARD_AFTER_EXILED` using the pre-exile snapshot context.

The native executor tracks an exile-in-progress instance stack so recursive
attempts to exile the same instance are no-ops, matching the authoritative
cycle guard. Difficulty-eight hand-size reactions, selector-driven exile, and
generated copies remain unsupported and cause conservative rejection when
relevant.

## Failure Semantics

The native method always mutates a private branch. If discovery or execution
reaches an uncompiled relevant condition, action, modifier, event side effect,
or runtime feature, it discards that branch and returns:

- `supported = false`;
- `valid = false`;
- a diagnostic reason;
- no partial payload, captures, exiles, or event stream.

An understood but illegal hand index, instance ID, or target cell continues to
return `supported = true, valid = false`. Unsupported semantics never silently
become no-ops and never masquerade as ordinary action illegality.

## Verification

The focused native probe will compare exact oracle transitions for:

- Bagua attacked and exiled before its pending flip for either owner;
- multiple locked targets where one target is exiled and later targets continue;
- attacker removal terminating the remaining target loop, while an unsupported
  ownership-changing reaction is rejected rather than approximated;
- LeiZhen tiers one through three, including defending-power override,
  attacked self-exile, before-exile draw, and indiscriminate allied targets;
- a target removed during `CARD_BE_ATTACKED`, proving that no flip occurs while
  `TRIGGER_CARD_AFTER_ATTACK` still receives a real attack;
- mixed retained, ordinary non-retained, and isolated self-after-flip abilities,
  including exact `ability_lost` and `card_flipped` ordering;
- row-major multi-source discovery followed by execution-time source
  revalidation;
- exile destination, same-instance identity, hand-slot behavior, recursive
  exile protection, and before/after-exile event order;
- explicit rejection of unsupported movement, selector, grant, nested attack,
  or other newly relevant rules;
- unchanged ability-free and TuNa parity fixtures.

Every accepted transition must match `DuelSimulator` in canonical state key,
live `state_version`, captures, exiles, and the complete event array.

A separate opt-in coverage probe will build the same 14 real Quick openings
used by production profiling, enumerate every legal root action, and report:

- total legal actions;
- native-supported actions;
- exact-parity supported actions;
- unsupported reason counts;
- invalid or mismatching native actions.

The coverage report has no adoption threshold in this phase. Its purpose is to
identify the next highest-impact unsupported primitive. Any accepted mismatch
is a hard failure. The native extension must build, the focused parity and
coverage probes must complete, `git diff --check` must pass, and the full
repository test suite must pass before completion is reported.

## Explicit Non-Goals

- no production or controller integration;
- no card-ID branches;
- no movement, swap, resummon, or summon action;
- no discard, card copy, fresh generated instance, or empty-deck fallback;
- no selectors or batch selection;
- no activation, cost payment, or ki mutation;
- no power-changing action;
- no nested attack action or attack loop created by a declaration;
- no runtime ability grant or replacement;
- no Android or release-packaging decision;
- no claim that the native engine can yet search a complete real duel.
