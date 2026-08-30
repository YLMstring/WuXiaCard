# Native Generic Attack Modifier Slice Design

Date: 2026-08-30

## Objective

Extend the opt-in native compact-state prototype so its standard-attack path
uses the same generic target-policy, geometry, power-comparison, and locked
target semantics as `DuelRules` and `DuelSimulator`. This phase compiles the
remaining generic attack modifiers instead of adding card-ID branches.

`DuelSimulator` remains the authoritative gameplay implementation and parity
oracle. Production search, controllers, testing mode, and greedy fallback do
not enable the native path in this phase.

## Scope

The native declaration compiler will support these remaining modifiers:

- `MODIFIER_ATTACK_REQUIRES_OTHER_ALLY`;
- `MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE`;
- `MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO`, including the immutable
  `allow_intervening_ally` and `allow_intervening_enemy` fields;
- `MODIFIER_POWER_COMPARISON_REVERSED`;
- `MODIFIER_ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES`;
- `MODIFIER_UNLIMITED_ATTACK_RANGE`;
- `MODIFIER_NON_ORTHOGONAL_ATTACK_ANY_AXIS`;
- `MODIFIER_STANDARD_ATTACK_FIRST_LEGAL_TARGET`;
- `MODIFIER_ENEMY_CANNOT_ATTACK_DURING_OWNER_TURN`;
- `MODIFIER_SELF_ATTACKS_ALL`.

The already compiled `MODIFIER_DEFENDING_POWER_OVERRIDE` and
`MODIFIER_ENEMY_ATTACKS_ALL` will move behind the same generic attack-policy
and legality helpers. Every modifier is governed by the runtime enabled-ability
membership introduced by the previous native phase. A modifier stops applying
as soon as its ability is removed, unless it is retained by the existing flip
rules.

This slice covers only standard attacks that reach already supported lifecycle
events and actions. Movement, nested attacks, power changes, summon actions,
ability grants, and other unsupported effects remain outside the phase. If an
accepted-looking attack reaches one of those effects, the complete private
native branch is rejected; no partial transition is exposed.

## Attack Policy Precedence

Every standard attack begins by resolving one immutable attack policy for that
invocation:

1. Start with the policy explicitly supplied by the caller, if any.
2. If the attacker has `MODIFIER_SELF_ATTACKS_ALL`, replace the target policy
   with all cards and return that result immediately.
3. Otherwise, if the caller supplied a non-empty policy, keep it unchanged.
4. Otherwise scan the board in row-major order for the first enemy card whose
   enabled ability supplies `MODIFIER_ENEMY_ATTACKS_ALL`. If found, attack all
   cards and record that modifier source's owner as the capture owner.
5. If none of the above applies, attack enemies only.

An allied target flipped by the generic enemy-attacks-all policy becomes owned
by the modifier source's owner. An allied target attacked only because the
attacker has self-attacks-all follows the current default capture-owner rule:
it becomes owned by the side opposing the attacker.

`MODIFIER_ENEMY_CANNOT_ATTACK_DURING_OWNER_TURN` prohibits an attack only when
the attacker is not owned by the active-turn player and an enabled source owned
by the active-turn player is on the board. This is implemented in the shared
attack gate even though ordinary summon attacks normally occur for the active
side, so later generic attack callers receive identical behavior.

## Adjacent Summon Redirection

`MODIFIER_ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES` preserves both timing
requirements in the card text.

When a card is initially placed for a summon, before summon-triggered effects
resolve, the transition snapshots the instance IDs of adjacent enemy cards
that currently provide this modifier. Immediately before the summoned card's
standard attack, those exact source instances are checked again in row-major
source order. A source redirects the attack to allies only if it:

- is still on the board;
- is still adjacent to the summoned attacker;
- is still an enemy of the summoned attacker; and
- still has the modifier enabled.

The first source that passes all four checks supplies the allies-only policy.
A card that moves adjacent only after the summon does not qualify. A source
that was adjacent at summon time but moves away, leaves play, changes sides, or
loses the ability before the attack does not qualify. Replacing it with a new
card of the same catalog ID does not qualify because runtime identity is the
`instance_id`, not the card ID.

## Candidate Generation and Locking

The generic attack module has four stages: candidate generation, initial
legality, target locking, and target-by-target resolution.

Without unlimited range, candidates are generated in the current directional
order. For each of top, right, bottom, and left, the adjacent cell is appended
first and the distance-two cell second when it remains on the board. With
`MODIFIER_UNLIMITED_ATTACK_RANGE`, candidates are every other board cell in
row-major order `0..8`.

Initial legality applies all of the following before a target is locked:

- the resolved enemies-only, allies-only, or all-cards policy;
- `MODIFIER_ATTACK_REQUIRES_OTHER_ALLY`, which requires at least two cards
  currently owned by the attacker on the board;
- same-axis geometry unless unlimited range is active;
- non-orthogonal geometry only when
  `MODIFIER_NON_ORTHOGONAL_ATTACK_ANY_AXIS` is active;
- maximum distance one unless range two or unlimited range permits more;
- for orthogonal distance two, the required
  `MODIFIER_ORTHOGONAL_ATTACK_RANGE_TWO` and the modifier's intervening-ally
  or intervening-enemy permission;
- the complete initial power comparison.

If `MODIFIER_STANDARD_ATTACK_FIRST_LEGAL_TARGET` is active, selection stops
after the first candidate that passes the complete initial legality check. The
selected target list is then locked. If a locked target later disappears or
becomes invalid during `CARD_BE_ATTACKED`, the attack does not search for a
replacement, including when first-legal-only selected that target.

## Power Comparison

Power is compared only during initial target selection. After
`CARD_BE_ATTACKED`, the exact attacker and target instances and all non-power
legality conditions are revalidated, but powers are not compared again.

For ordinary orthogonal attacks, the attacker's facing side is compared with
the target's defending side. `MODIFIER_DEFENDING_POWER_OVERRIDE` applies to
each queried defending side. If the attacker has
`MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE`, the defending value becomes the
minimum of the target's four effective defending sides.

For a permitted non-orthogonal attack, the attack succeeds if either the
vertical-facing pair or horizontal-facing pair succeeds. The same defending
override, minimum-side, and reversal rules apply to each pair.

`MODIFIER_POWER_COMPARISON_REVERSED` is active if either the attacker or target
has it. For ordinary numbered sides it changes a winning comparison from
attacker greater than defender to attacker less than defender.

### Four-Sided Negative-Power Precedence

The special meaning of a card whose four powers are exactly
`[-1, -1, -1, -1]` takes precedence over comparison reversal:

- any nonnegative attacking side can attack a four-sided `-1` defender;
- a four-sided `-1` attacker cannot beat a nonnegative defender;
- a four-sided `-1` attacker cannot beat another four-sided `-1` defender;
- comparison reversal applies only when both cards use ordinary numbered
  powers for this comparison.

This is a gameplay-rule correction, not merely a native compatibility gate.
The authoritative GDScript rule and native implementation will change
together, with regression tests proving that reversal cannot alter the special
negative-power semantics. Mixed negative and nonnegative power arrays remain
unsupported by the native compact state.

## Resolution and Revalidation

If no candidate passes initial legality, the invocation emits no
`attack_started`, does not increment the per-turn attack count, and does not
dispatch after-attack abilities.

If at least one target is locked, the attack invocation increments the
per-player per-turn attack count once. Each locked target then resolves in
order:

1. Emit `attack_started` and dispatch `CARD_BE_ATTACKED`.
2. Re-locate the exact attacker and target instances.
3. Recheck target policy, the other-ally requirement, geometry, range, and
   intervening-card permissions with power comparison explicitly skipped.
4. If the target fails revalidation, end only that target's resolution and do
   not choose a replacement.
5. Otherwise continue through the existing before-flip, flip-prevention,
   ownership-change, ability-cleanup, after-flip, and exile lifecycle.
6. If the attacker leaves the board or changes owner during the chain, stop
   the remaining locked-target loop. Movement does not intrinsically cancel an
   attack: the new geometry is revalidated, and an unlimited attack remains in
   range. Relevant movement effects are nevertheless rejected until the
   movement slice is implemented.

After the locked-target loop, `TRIGGER_CARD_AFTER_ATTACK` runs once if at least
one `attack_started` event occurred, including when every attacked target was
subsequently removed before it could flip. A successful explicitly targeted
attack counts toward the same twenty-attack limit. Attacks that never had a
legal target do not count and do not trigger after-attack effects.

## Declaration Compilation and Failure Semantics

Modifier declarations compile into typed immutable fields, including the two
range-two intervening permissions. Search branches do not walk nested Godot
`Dictionary` declarations. A modifier lookup scans only enabled runtime
ability entries and preserves row-major source precedence where a global
source is required.

The native method continues to mutate only a private branch. A relevant
unsupported declaration field, condition, action, event side effect, or
runtime feature discards that branch and returns `supported = false` and
`valid = false`, with a diagnostic reason and no partial state, captures,
exiles, or event stream. Ordinary illegality returns `supported = true` and
`valid = false`.

## Verification

Focused synthetic parity fixtures will cover positive and negative cases for
every modifier listed in this document, including:

- other-ally presence and loss during `CARD_BE_ATTACKED`;
- minimum-side defense combined with defending-power override;
- distance-two attacks with empty, allied, and enemy intervening cells under
  each permission combination;
- ordinary and four-sided `-1` comparisons with reversal on the attacker,
  defender, or both;
- adjacent-summon redirection where the source remains valid, moves away,
  changes owner, loses its ability, leaves play, or is replaced by a new
  same-ID instance;
- unlimited and non-orthogonal geometry at board edges and corners;
- first-legal-only target locking and loss of the locked target during
  `CARD_BE_ATTACKED`;
- enemy attack prohibition during the modifier owner's turn;
- precedence among self-attacks-all, explicit policy, enemy-attacks-all, and
  adjacent-summon allies-only policy;
- attacker flip or exile terminating the remaining target loop;
- modifier removal on flip and retained modifier survival.

Real catalog parity fixtures will exercise representative declarations such as
the Qixin retained attack modifiers, orthogonal range-two cards, Taiji summon
redirection, RaoZhi/WuXiang targeting, ShenMen attack prohibition, Xixing
self-attacks-all, and comparison reversal without dispatching on those card
IDs.

The opt-in coverage probe will rebuild the same fourteen real Quick openings,
enumerate every legal root action, and report total legal actions, native
supported actions, exact-parity actions, rejected reasons, and mismatches.
There is no adoption threshold in this phase; any accepted mismatch is a hard
failure.

Before completion, the native extension must build, the focused probe must
pass, `git diff --check` must pass, and the full repository test suite must
pass. Agent-visible playtests, if needed, use dummy audio. Production search
remains on the GDScript path.

## Explicit Non-Goals

- no production or controller integration;
- no card-ID or card-name branches;
- no movement, swap, resummon, or summon action;
- no nested attack action;
- no power-changing action;
- no selector or batch-selection implementation;
- no activation, cost payment, or ki mutation;
- no runtime ability grant or replacement;
- no relaxation of the existing private-branch rejection contract;
- no claim that the native engine can yet search a complete real duel.
