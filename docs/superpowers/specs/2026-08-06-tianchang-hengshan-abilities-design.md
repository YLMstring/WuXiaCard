# 天长掌法 3–4 and 恒山剑阵 2–4 Ability Design

## Scope

Implement the catalog descriptions of **TianChangZhang3**,
**TianChangZhang4**, **HenShanJianZhen2**, **HenShanJianZhen3**, and
**HenShanJianZhen4** through the reusable ability system. The simulator, AI,
replay, and live duel must share the same rules. No card-ID-specific runtime
branches are allowed.

## Approved Rules

### 天长掌法 summon power

TianChangZhang3 and TianChangZhang4 resolve their power increase during
TRIGGER_CARD_AFTER_SUMMONED, before the summoned card's ordinary attack.
They count the enemy cards orthogonally adjacent to the summoned card at that
time. For each matching enemy, all four current powers of 天长掌法 increase by
one. Empty cells and adjacent allies do not count. The resulting power change
is permanent runtime card state and is not reversed by a later ownership flip.

The declaration uses the existing selector loop and an extended
ACTION_ADD_POWERS target:

~~~gdscript
{
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{
            "type": ACTION_FOR_EACH_SELECTED_CARD,
            "selector": {
                "zones": [CARD_ZONE_BOARD],
                "conditions": [
                    {"type": CONDITION_SELECTED_CARD_IS_ENEMY},
                    {"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
                ],
            },
            "actions": [{
                "type": ACTION_ADD_POWERS,
                "amount": 1,
                "target": ACTION_TARGET_ABILITY_SOURCE,
            }],
        }],
    }],
}
~~~

### Shared one-use counterattack

TianChangZhang4 begins with, and each 恒山剑阵 can grant, the same
non-retained counterattack ability:

~~~gdscript
const HENGSHAN_COUNTERATTACK: Dictionary = {
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_ATTACK,
        "conditions": [
            {"type": CONDITION_ATTACKER_CARD_IS_ENEMY},
            {"type": CONDITION_ATTACK_FLIPPED_ALLY_IN_RANGE},
        ],
        "actions": [
            {"type": ACTION_REMOVE_THIS_ABILITY},
            {"type": ACTION_STANDARD_ATTACK_WITH_SELF},
        ],
    }],
}
~~~

A standard attack is one complete attack sequence, not one direction. The new
event fires exactly once after all four directions and all flip-triggered
effects from that attack finish. A reaction therefore fires at most once for
that standard attack, even when several cards were flipped.

The event records only cards that actually changed ownership during the
attack. Prevented flips, failed range rechecks, cards already owned by the
attacker, and other no-effect attempts are excluded. For each recorded card,
the context preserves its owner before the successful flip and its exact
instance ID.

When the condition resolves, it uses the final board state after the entire
attack and its flip triggers. At least one recorded card must have been
friendly to the reacting card immediately before that flip, still exist on
the board, and occupy a cell in the reacting card's current attack range.

The attacker is compared with the reacting card's current owner. A missing or
moved attacker does not erase the event's recorded attacking owner.

The ability is non-retained and is lost normally if its card changes owner.
Identical granted copies do not stack. Once its conditions match, the
declaration removes the exact resolving ability before requesting the attack.
This internal reservation prevents that same copy from firing again during a
nested counterattack chain. The card then performs a normal standard attack
from its current square; having no legal targets still consumes the effect.

### 恒山剑阵 grants

All three 恒山剑阵 cards grant HENGSHAN_COUNTERATTACK at the end of their
current owner's turn, using TRIGGER_END_OWNER_TURN and
CONDITION_TURN_OWNER_IS_SELF.

- HenShanJianZhen2 grants it to itself and every orthogonally adjacent ally.
- HenShanJianZhen3 grants it to every allied board card, including itself.
- HenShanJianZhen4 grants it to every allied board card, including itself.

Selection snapshots the matching exact instances and revalidates each card
before granting. An identical unused counterattack already present on a card
causes the grant to do nothing for that card rather than adding another copy.

### 恒山剑阵4 enclosure flip

After HenShanJianZhen4 is summoned, and before its ordinary attack, it
selects every enemy card surrounded by allies and flips those selected cards
sequentially to the ability source's owner through the normal non-attack flip
pipeline.

"Surrounded" means that every orthogonally adjacent cell that exists on the
3x3 board is occupied by an ally of 恒山剑阵's owner:

- a corner enemy requires both existing adjacent cells;
- a non-corner edge enemy requires all three existing adjacent cells; and
- the center enemy requires all four adjacent cells.

Empty cells, enemies, or cards whose ownership changes away from the ability
source's owner break enclosure. The selector revalidates every condition
immediately before each flip. A selected card that moves, leaves the board,
ceases to be an enemy, or is no longer surrounded is skipped. Other selected
cards continue resolving.

Each successful flip emits the standard CARD_BEFORE_FLIPPED and
CARD_AFTER_FLIPPED triggers. Flip prevention and movement during those
triggers retain the established non-attack-flip behavior.

## Architecture

### Catalog and validation

Add TianChangZhang4, HenShanJianZhen3, and HenShanJianZhen4 to
ALL_CARD_IDS. Add and validate:

- event TRIGGER_CARD_AFTER_ATTACK;
- trigger conditions CONDITION_ATTACKER_CARD_IS_ENEMY and
  CONDITION_ATTACK_FLIPPED_ALLY_IN_RANGE;
- selector condition CONDITION_SELECTED_CARD_SURROUNDED_BY_ALLIES;
- action target ACTION_TARGET_ABILITY_SOURCE for ACTION_ADD_POWERS; and
- a generic non-attack flip action whose new owner is the ability source's
  owner.

Only ACTION_ADD_POWERS accepts its optional target field. Omitting it keeps
the current behavior of affecting the action's current subject. The new flip
action acts on the current subject, which makes it reusable inside selector
loops, and accepts only the supported owner reference.

### Attack summary

The simulator separates one complete attack from its individual directional
target resolutions. Individual target resolution continues to own
CARD_BE_ATTACKED, attack-range rechecks, CARD_BEFORE_FLIPPED, the ownership
change, and CARD_AFTER_FLIPPED. The enclosing standard-attack resolver
collects successful flip records from every direction and resolves
TRIGGER_CARD_AFTER_ATTACK once at the end.

Targeted attacks also represent a complete one-target attack and emit the same
event once after their target and flip-triggered effects finish. This keeps
the event reusable for existing and future effects that request a targeted
attack.

Every counterattack uses the same attack resolver, so it produces its own
after-attack event and can legitimately start a chain of distinct one-use
counter abilities. Removing the resolving ability before its attack prevents
self-reentrancy without suppressing other cards' reactions.

### Generic non-attack flip request

The executor must not bypass flip triggers. The new action creates a flip
request containing the selected exact instance, the ability source owner, and
a reason. The simulator resolves that request through resolve_non_attack_flip.
Flip requests propagate through nested selector actions and trigger groups in
the same way as attack requests, captures, exiles, and presentation events.

## Invalid and Changing Contexts

Missing cards, stale instance IDs, malformed selectors, or invalid owner
references produce normal no-effect results. They do not become
INVALID_CONTEXT unless a catalog declaration explicitly opts into that
behavior under the existing rules.

After-attack conditions use exact instance identity. A card recorded as
flipped but removed before the attack finishes cannot satisfy the final range
condition. A recorded card that remains on the board can satisfy it from its
new final cell. The reacting card must also still exist with the same owner
and exact non-retained ability when its queued trigger group resolves.

## Tests

Add focused catalog and simulator tests covering:

- complete catalog validation and all five declarations;
- 天长掌法 gaining zero through four power per side from adjacent enemies;
- allies and empty cells not contributing to the power increase;
- the increase resolving before the ordinary summon attack;
- one after-attack event for a full four-direction standard attack;
- only actual ownership changes entering the attack summary;
- final-board-position range evaluation, including moved, removed, and
  out-of-range flipped allies;
- one counterattack despite multiple qualifying flips;
- counter ability consumption when the attack has no legal target;
- safe nested counterattack chains without reusing a consumed ability;
- tier-two self-plus-adjacent granting and exclusions;
- tier-three and tier-four all-allies granting;
- identical grant deduplication across repeated turn ends;
- tier-four enclosure at corner, edge, and center cells;
- empty or enemy neighboring cells breaking enclosure;
- sequential selector revalidation after movement or ownership changes;
- normal before/after-flip triggers and prevention for enclosure flips; and
- copied simulation states remaining isolated.

The focused suite is added to tools/run_tests.ps1. Existing ability,
simulator, replay, and AI suites remain regression coverage because all four
consumers use the same deterministic transition path.
