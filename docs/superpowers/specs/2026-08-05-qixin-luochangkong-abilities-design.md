# 七星落长空 2–4 Ability Design

## Scope

Implement the catalog descriptions of `QiXinLuoChangKong2`,
`QiXinLuoChangKong3`, and `QiXinLuoChangKong4` through the reusable ability
system. The simulator, AI, replay, and live duel must all use the same rules.
No card-specific ID checks are allowed.

## Approved Rules

### Shared retained attack modifiers

All three cards have one ability with `retained_on_flip: true` and two
parameterless modifiers:

```gdscript
{
    "retained_on_flip": true,
    "modifiers": [
        {"type": MODIFIER_ATTACK_REQUIRES_OTHER_ALLY},
        {"type": MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE},
    ],
}
```

`MODIFIER_ATTACK_REQUIRES_OTHER_ALLY` prevents the card from performing any
attack unless another board card currently has the same owner. The check
applies to ordinary summon attacks, reaction attacks, activated attacks, and
future effects that request an attack. It is evaluated whenever attack
validity is checked, including the existing post-`CARD_BE_ATTACKED` recheck.
If the other ally disappears during that event, the attack emits no flip.

`MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE` changes only combat comparison.
When this card attacks, the defender's value is the minimum of its four
current effective defending powers. Stored powers are not changed. Existing
defending-power overrides are applied per side before the minimum is taken;
therefore a card whose defending sides are all treated as zero has a minimum
of zero.

Because the modifier ability is retained, both rules survive ownership flips.
The other-ally requirement is then evaluated against the card's current owner.

### Tier-three reaction

`QiXinLuoChangKong3` and `QiXinLuoChangKong4` have a separate, non-retained
reaction ability using the existing declaration:

```gdscript
{
    "triggers": [{
        "event": TRIGGER_CARD_SUMMONED,
        "conditions": [
            {"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
            {"type": CONDITION_TRIGGER_CARD_IN_RANGE},
        ],
        "actions": [{"type": ACTION_ATTACK_TRIGGER_CARD}],
    }],
}
```

The trigger can resolve while the card is alone, but the requested attack is
rejected by the shared attack-validity rule. The reaction ability is lost if
the card changes ownership.

### Tier-four temporary protection

`QiXinLuoChangKong4` also has a separate copy of
`TEMPORARY_FLIP_PROTECTION`. It prevents this card's flip before it occurs and
permanently removes itself after either:

- an enemy card actually flips; or
- the protected card's current owner's turn begins.

Movement, ownership changes, or later returning to the original owner never
restore a removed protection ability. This matches the existing 来鹤清泉
behavior.

## Architecture

### Catalog and validation

Add both modifier constants to `card_catalog.gd`, register them in
`KNOWN_MODIFIERS`, and add `QiXinLuoChangKong3` and
`QiXinLuoChangKong4` to `ALL_CARD_IDS`.

Modifier validation becomes type-specific:

- `MODIFIER_DEFENDING_POWER_OVERRIDE` continues to require a non-negative
  integer `value`.
- The two new Boolean modifiers permit only the `type` field and reject a
  `value` or any unknown field.

The three card declarations use separate abilities so their retention rules
remain explicit.

### Ability queries and combat rules

`duel_abilities.gd` remains the generic ability-query layer. It exposes the
new modifier checks and computes a defender's minimum effective side when the
attacker requests that mode.

The rules layer separates attack range from attack permission:

- `DuelRules.is_target_in_attack_range()` validates the cards, adjacency,
  enemy ownership, attacking edge, and effective defending power. Trigger
  condition `CONDITION_TRIGGER_CARD_IN_RANGE` uses this query.
- `DuelRules.can_attack_target()` first checks continuous permission rules,
  including `attack_requires_other_ally`, and then delegates to the range
  query.

This separation lets the tier-three reaction trigger and pulse while the card
is alone, as approved, while its resulting attack request produces no
`attack_started` event and no flip.

The shared range calculation:

1. validates the two board cards and adjacency;
2. rejects allied targets;
3. calculates the normal attacking edge;
4. calculates either the facing effective defense or the minimum of all four
   effective defenses; and
5. applies the existing strict `attacking_power > defending_power` rule.

No new trigger event is introduced. Static modifiers do not pulse. The
tier-three reaction and tier-four protection retain their existing trigger
presentation behavior.

## Invalid and Changing Contexts

Malformed cards, missing power arrays, invalid cells, non-adjacent targets,
and missing owners continue to make the attack illegal without changing
state. If movement or another effect invalidates an already-declared attack,
the existing second validity check stops the flip. These outcomes are normal
no-effect combat results, not `INVALID_CONTEXT` action results.

## Tests

Add a focused simulator suite covering:

- all three catalog declarations and catalog validation;
- every attack source failing while the card is alone;
- an additional ally enabling attacks;
- current effective side powers being reduced to their minimum for defense;
- no mutation of stored defender powers;
- modifier retention across a flip and ally evaluation against the new owner;
- tier-three reactions with another ally producing an attack;
- tier-three reactions without another ally still triggering but producing no
  attack or flip;
- tier-four flip prevention;
- permanent protection loss after an enemy flip;
- permanent protection loss at the current owner's turn start; and
- state-copy isolation for the new active ability declarations.

The suite is added to `tools/run_tests.ps1`. Existing focused tests for
苍松迎客, 来鹤清泉, and 泰山 cards provide regression coverage for the reused
trigger and protection primitives.
