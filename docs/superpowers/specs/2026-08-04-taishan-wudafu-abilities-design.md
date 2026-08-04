# 泰山十八盘 2–3 / 五大夫剑 1–3 Ability Design

## Scope

Implement the five catalog descriptions without card-ID-specific simulator logic. All effects use the deterministic duel state and therefore work identically for live play, replay, and AI simulation.

## Shared timing and protection

All entrance effects subscribe to `TRIGGER_CARD_AFTER_SUMMONED`, after summon reactions such as 苍松迎客 have resolved.

The temporary protection granted by these cards is the established 来鹤清泉 pattern:

- On `CARD_BEFORE_FLIPPED` for the protected card, prevent that flip.
- After an enemy card actually flips ownership, remove this protection.
- At the start of the protected card owner's turn, remove this protection.
- The granted protection is not retained when ownership flips.

## 泰山十八盘

### Tier 2

After this card is summoned, select enemy board cards orthogonally adjacent to it. The effect resolves only when the complete selection contains exactly one card. Swap this card with that selected enemy using the established reserve-and-reappear swap sequence.

The selected enemy is revalidated immediately before the swap. If it has moved, left the board, changed ownership, or stopped being adjacent, the swap does nothing. No alternate enemy is selected during resolution.

### Tier 3

Has the tier-2 entrance ability plus the temporary protection as a separate ability. Keeping these as separate abilities lets ownership flipping remove both normally and lets the protection remove only itself.

## 五大夫剑

Friendly heavy-sword selection includes 五大夫剑 itself. Selection uses board order (cells 0 through 8) and every selected card is revalidated before its nested actions.

### Tier 1

After being summoned, grant the temporary protection to itself.

### Tier 2

After being summoned, select every allied board card whose weapon is `重剑`, including itself, and grant each a fresh copy of the temporary protection.

### Tier 3

After being summoned:

1. Snapshot all allied board cards whose weapon is `重剑`, including itself.
2. For every still-matching selected card, draw one card for 五大夫剑's owner. Existing deck exhaustion and five-card hand limits apply to every draw.
3. Select/revalidate all allied heavy-sword cards and grant each a fresh copy of the temporary protection.

The draw phase completes before the grant phase. A failed draw caused by an empty deck or full hand does not stop later draws or protection grants.

## Reusable primitives

Extend the selector vocabulary with:

- `CONDITION_SELECTED_CARD_IS_ENEMY`
- `CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE`
- selector `required_count`, which requires the snapshot to contain exactly that many matches before any nested action runs

Add generic selected-card actions:

- Grant a declared ability to the current action subject. At top level this means the ability source; inside `ACTION_FOR_EACH_SELECTED_CARD` it means the selected card.
- Swap the original ability source with the current selected card, preserving the established swap event sequence.

These primitives must not reference the five implementing card IDs.

## Failure semantics

- A selector count mismatch produces `NO_EFFECT` and runs no nested action.
- A selected card that no longer satisfies one or more conditions is skipped, matching the existing selection rule.
- Missing/full draw contexts and missing swap subjects produce `NO_EFFECT`, not `INVALID_CONTEXT`.
- No new action declares `on_invalid_context`; one failure does not stop unrelated later actions.

## Verification

Tests cover catalog validation, exact-one adjacency, zero/two-enemy non-resolution, the four-direction swap, tier-3 protection, self-inclusion, allied/enemy and weapon filtering, draw-before-grant ordering, hand/deck limits, temporary protection removal, and deterministic simulator behavior.
