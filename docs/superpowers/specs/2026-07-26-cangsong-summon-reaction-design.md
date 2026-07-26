# CangSongYingKe2 Summon-Reaction Design

## Goal

Implement CangSongYingKe2’s printed ability:

> 对手招式进场时，若我可以，对其发起攻击。

Whenever a card is summoned, each eligible enemy CangSongYingKe2 may immediately attack that exact card before its remaining summon resolution.

The implementation also adds reusable summon-trigger, condition, action, and attack-range primitives for future effects.

## Catalog Declaration

CangSongYingKe2 declares:

```gdscript
{
    "id": EFFECT_WELCOMING_PINE,
    "triggers": [
        {
            "event": TRIGGER_CARD_SUMMONED,
            "conditions": [
                {"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
                {"type": CONDITION_TRIGGER_CARD_IN_RANGE},
            ],
            "actions": [
                {"type": TRIGGER_ACTION_ATTACK_TRIGGER_CARD},
            ],
        },
    ],
}
```

The effect omits `retained_on_flip`, so catalog normalization makes it `false`. A CangSongYingKe2 that was previously flipped permanently loses this ability.

## Reusable Trigger Vocabulary

### `TRIGGER_CARD_SUMMONED`

This event occurs immediately after a card newly enters a board cell and before the summoning source continues its remaining resolution. For a normal hand play, that means before the card’s existing on-play effects and standard attack.

It applies to:

- normal cards played from hand;
- future effect-created summons.

It does not apply to:

- movement from one board cell to another;
- ownership changes;
- cards drawn into hand.

The trigger context contains:

- triggering card cell;
- triggering card instance ID;
- triggering card current owner;
- summon source/reason, such as hand play or future effect summon.

### Composable Conditions

Trigger rules use a `conditions` array. All entries are ANDed in declared order. An omitted or empty array passes.

Existing Meng Huo ki conditions migrate to this common representation:

```gdscript
"conditions": [
    {"type": CONDITION_KI_AT_LEAST, "amount": 1},
]
```

Supported condition primitives for this feature:

- `CONDITION_KI_AT_LEAST`
- `CONDITION_TRIGGER_CARD_IS_ENEMY`
- `CONDITION_TRIGGER_CARD_IN_RANGE`

`TRIGGER_CARD_IS_ENEMY` compares the source card’s current owner with the triggering card’s current owner.

`TRIGGER_CARD_IN_RANGE` delegates to the shared attack-eligibility query with the source and triggering card cells plus the summon-reaction context.

### `TRIGGER_ACTION_ATTACK_TRIGGER_CARD`

This action requests a single attack from the trigger source against the triggering card. It does not perform a normal four-direction attack and cannot choose a different target.

The simulator resolves attack requests one trigger group at a time, so state changes from an earlier reaction are visible to every later group.

## Shared Attack Eligibility

The rules layer exposes a context-aware query for one source-target pair.

For the current rules, an attack is eligible only when:

- both cells are occupied;
- source and target have different owners;
- target is orthogonally adjacent to source;
- source power facing the target is strictly greater than target power facing the source.

Equal powers and diagonal cells fail.

The query receives an attack context, including the reason `card_summoned_reaction`. Future effects may modify range, comparison, direction, or power without changing CangSongYingKe2’s trigger implementation.

The existing standard four-edge attack discovery also uses this shared query, ensuring future modifiers have one authoritative integration point.

## Resolution Order

For a normal play from hand:

1. Remove the chosen card from hand.
2. Normalize its runtime card data.
3. Put it in the target board cell.
4. Emit the existing `card_placed` event.
5. Discover `TRIGGER_CARD_SUMMONED` groups by scanning board cells from index 0 through 8.
6. Resolve groups sequentially:
   - revalidate the source card, effect, trigger rule, conditions, and triggering card identity;
   - execute `ATTACK_TRIGGER_CARD` only if all remain valid;
   - resolve through the existing flip/exile resolver;
   - resolve existing successful-flip triggers, including ki gain when applicable.
7. After each group, stop summon reactions if the triggering card:
   - left the board; or
   - no longer belongs to its summoning owner.
8. If interrupted, skip the triggering card’s on-play effects and standard attack.
9. If it remains in its original cell with its summoning owner after all groups, resolve its normal on-play effects and standard attack.
10. Finish the turn normally.

Future effect-created summons call the same summon-reaction pipeline at step 5, then their summoning effect decides what remaining resolution follows. Board movement does not call it.

## Multiple Reactions

- Reactions use canonical board-cell order: left to right across the top row, then the middle row, then the bottom row.
- Every group is revalidated immediately before its action.
- Once the triggering card flips or is removed, later groups do nothing.
- If a future prevention effect causes an attack to leave the triggering card enemy-owned, the next eligible group may react.

## Existing Effect Interactions

- The attack uses the existing flip/exile resolver.
- A source with the exile-instead-of-flip replacement removes the triggering card instead.
- A normal flip removes non-retained effects from the triggering card and emits existing `ability_lost` events.
- Existing after-successful-flip triggers resolve normally.
- Draw-on-play effects are cancelled when a hand-played card is interrupted.
- The turn still finishes after an interrupted summon.

## Events and Presentation

No new `reaction_attack_declared` or `card_play_interrupted` transition events are added.

Existing events remain authoritative:

- `card_placed`
- `card_flipped`
- `card_exiled`
- `ability_lost`
- existing trigger-produced events such as `ki_changed`

The controller adds no special reaction cue in this feature. Existing flip/exile animation and sound play in their normal order. A reusable reaction cue may be designed later.

## AI and Determinism

The simulator is the only authority for summon reactions. Search, greedy fallback, testing mode, and live play all apply the same transitions.

No card-ID branch is added to AI or simulator logic. Behavior comes from the catalog’s declarative trigger, conditions, and action.

All discovery and resolution ordering is deterministic, preserving reproducible search results and compact simulation compatibility.

## Verification

Tests cover:

- CangSongYingKe2’s exact catalog declaration;
- catalog rejection of unknown trigger, condition, and action IDs;
- migration and preservation of Meng Huo’s ki condition;
- shared attack eligibility for orthogonal, diagonal, greater, equal, friendly, and missing-cell cases;
- standard attacks still using the shared eligibility query;
- reaction timing before draw-on-play and normal attack;
- cancellation of both after a successful reaction;
- continued normal resolution when no condition passes;
- multiple reactors in board order;
- stopping after flip or exile;
- exile replacement;
- ability loss after CangSong is flipped;
- stable triggering-card identity;
- existing successful-flip triggers;
- full simulator, search, and live integration paths.
