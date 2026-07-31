# CangSongYingKe 3–4 and SanQinFeng 1–3 Ability Design

## Goal

Implement the catalog abilities described by `CangSongYingKe3`,
`CangSongYingKe4`, and `SanQinFeng1` through `SanQinFeng3` while extending
the reusable trigger/action system rather than adding card-specific simulator
branches.

The work adds:

- a reusable `CARD_BEFORE_FLIPPED` trigger for every ownership-changing flip;
- a reusable `ACTION_ADD_CARD_TO_HAND` action;
- fully sequential resolution for attack actions nested inside
  `ACTION_FOR_EACH_SELECTED_CARD`; and
- declarative catalog rules for all five cards.

Abilities continue to be lost on flip unless their declaration explicitly
sets `retained_on_flip`.

## New Flip Trigger

`CARD_BEFORE_FLIPPED` is emitted only for a flip that has passed the
pre-trigger validity checks and would change the target card's ownership.
The trigger context identifies:

- the exact card instance that is about to flip;
- its current board cell and owner;
- the intended new owner;
- the reason for the flip; and
- attack context when the flip came from an attack.

`CONDITION_TRIGGER_CARD_IS_SELF` can therefore subscribe the card that is
about to flip without needing a card-specific condition.

### Attack Flip Order

An attack that may flip a card resolves in this order:

1. Emit `attack_started`.
2. Discover and resolve `CARD_BE_ATTACKED`.
3. Locate the exact attacker and target again and recheck ownership, attack
   range, and every normal attack-validity rule.
4. If step 3 fails, stop. Emit neither `CARD_BEFORE_FLIPPED` nor
   `CARD_AFTER_FLIPPED`.
5. Emit and resolve `CARD_BEFORE_FLIPPED`.
6. Locate and validate the pending flip again.
7. If step 6 succeeds, change ownership and emit the normal flip events.
8. Resolve `CARD_AFTER_FLIPPED`.

If a `CARD_BEFORE_FLIPPED` rule itself invalidates the pending flip, its
already-resolved costs and effects remain. The flip and
`CARD_AFTER_FLIPPED` do not occur.

Attack flips remain range-bound. If either card moves during
`CARD_BE_ATTACKED` and the exact target is no longer in the exact attacker's
range, step 3 fails and no before-flip event is emitted. If movement happens
during `CARD_BEFORE_FLIPPED`, that event has already resolved; the second
attack-validity check then cancels the flip when the target is out of range.

### Non-Attack Flip Order

Future non-attack flip effects use the same before/after trigger pair, but
their pending flip follows the target's runtime `instance_id`. Moving the
target to another board cell does not itself cancel a non-attack flip.

After `CARD_BEFORE_FLIPPED`, a non-attack flip is cancelled if the exact
target:

- no longer exists on the board;
- has already changed to the intended new owner; or
- fails another rule explicitly belonging to that non-attack flip effect.

Resolved trigger costs and effects are never rolled back.

## Add Card to Hand Action

The catalog action has this shape:

```gdscript
{
    "type": ACTION_ADD_CARD_TO_HAND,
    "card_id": &"CangSongYingKe3",
    "recipient": RECIPIENT_SELF,
}
```

`recipient` accepts exactly:

- `RECIPIENT_SELF`: the current owner of the ability source; or
- `RECIPIENT_OPPONENT`: the other duel owner relative to the ability source.

`card_id` must be a known card catalog ID. Catalog validation rejects unknown
IDs, unknown recipient values, missing fields, and unsupported fields.

The action creates a fresh runtime instance from the requested catalog
definition. It does not copy mutable powers, ki, ability loss, or any other
runtime state from the source card. The instance receives:

- its catalog powers and metadata;
- its catalog starting ki;
- a fresh copy of its catalog abilities; and
- a deterministic, collision-free runtime instance ID.

The card is added directly to the chosen hand. It is not removed from or
looked up in the side deck. The action respects the five-card hand limit.
When the chosen hand is full, it returns `NO_EFFECT`; actions that resolved
earlier in the rule, including ki spending, remain resolved.

A successful action emits a generic `card_added_to_hand` transition event
containing the recipient, new instance ID, card data, logical hand index, and
the source instance. The event is distinct from `card_drawn` because no deck
was involved.

Generated IDs are deterministic from duel state. The allocator checks every
card-bearing state zone so AI state copies and repeated searches create the
same IDs for the same transition without colliding with an existing physical
card.

## Sequential Selected-Card Actions

`ACTION_FOR_EACH_SELECTED_CARD` keeps its existing contract:

1. Snapshot matching runtime instance IDs in selector order.
2. Before each selected card, locate it again and re-evaluate only the
   selector's declared conditions.
3. Skip it only when it is missing or one or more conditions no longer match.
4. Resolve all nested actions for that selected card.
5. Resolve all nested attack requests, reactions, movement, flips, exiles,
   and resulting events completely.
6. Only then advance to and revalidate the next selected card.

The simulator supplies the action executor with an attack-resolution
callback. This lets a nested `ACTION_STANDARD_ATTACK_WITH_SELF` finish inside
the wrapper's current selected-card step instead of collecting every attack
until after selection has completed.

The action result accumulates direct events, captures, exiles, extra-turn
requests, and unresolved requests without changing their order. Callers that
do not provide a resolver may continue receiving attack requests for
isolated executor tests. Production simulator paths provide the resolver.

Start-turn processing returns and merges a complete resolution result.
Captures and exiles caused by start-turn abilities therefore appear in the
same parent transition as the move that ended the previous turn.

## CangSongYingKe3 and CangSongYingKe4

Both cards retain the existing summon-reaction rule from
`CangSongYingKe2`:

```gdscript
{
    "event": TRIGGER_CARD_SUMMONED,
    "conditions": [
        {"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
        {"type": CONDITION_TRIGGER_CARD_IN_RANGE},
    ],
    "actions": [
        {"type": ACTION_ATTACK_TRIGGER_CARD},
    ],
}
```

Each card adds a second trigger that references its own exact catalog ID:

```gdscript
{
    "event": CARD_BEFORE_FLIPPED,
    "conditions": [
        {"type": CONDITION_TRIGGER_CARD_IS_SELF},
        {"type": CONDITION_KI_AT_LEAST, "amount": 1},
    ],
    "actions": [
        {"type": ACTION_SPEND_KI, "amount": 1},
        {
            "type": ACTION_ADD_CARD_TO_HAND,
            "card_id": &"CangSongYingKe3",
            "recipient": RECIPIENT_SELF,
        },
    ],
}
```

`CangSongYingKe4` substitutes `&"CangSongYingKe4"` for the card ID.

The trigger resolves before ownership changes, so `RECIPIENT_SELF` is the
card's owner immediately before the flip. It spends exactly 1 ki. A full hand
still consumes that ki even though the add-card action returns `NO_EFFECT`.
The newly created card is a fresh, fully active catalog copy.

## SanQinFeng1–3

All three cards receive the same start-turn rule, with selector limits 1, 2,
and 3 respectively:

```gdscript
{
    "event": TRIGGER_START_OWNER_TURN,
    "conditions": [
        {"type": CONDITION_TURN_OWNER_IS_SELF},
        {"type": CONDITION_KI_AT_LEAST, "amount": 1},
    ],
    "actions": [
        {"type": ACTION_SPEND_KI, "amount": 1},
        {
            "type": ACTION_FOR_EACH_SELECTED_CARD,
            "selector": {
                "zones": [CARD_ZONE_BOARD],
                "conditions": [
                    {"type": CONDITION_SELECTED_CARD_IS_ALLY},
                    {
                        "type": CONDITION_SELECTED_CARD_WEAPON_IS,
                        "weapon": "剑法",
                    },
                ],
                "limit": 1,
            },
            "actions": [
                {"type": ACTION_STANDARD_ATTACK_WITH_SELF},
            ],
        },
    ],
}
```

The limit is 2 for `SanQinFeng2` and 3 for `SanQinFeng3`.

Selection is board row-major and includes the ability source itself when it
matches. The source spends exactly 1 ki whenever the start-turn trigger
qualifies, even if there are no matching allied sword cards or none of the
selected cards has an attack target.

Each selected card performs its normal four-direction standard attack. That
attack resolves completely before the next snapshot member is revalidated.
For example, if an earlier attack causes a later selected card to stop being
an allied sword card, the later card is skipped.

Multiple SanQinFeng sources are discovered in normal row-major trigger order.
Each source is revalidated before its rule resolves. An earlier source's
attacks may therefore invalidate a later source's discovered trigger.

## Presentation

Normal passive-trigger pulsing remains generic:

- CangSong pulses before spending ki and adding its copy.
- SanQinFeng pulses before spending ki and beginning its ordered attacks.
- Existing consecutive-pulse suppression still applies.

`card_added_to_hand` uses the existing silent Ink Summon hand-addition
presentation:

- player cards are revealed;
- opponent cards remain face-down in normal mode;
- opponent cards are revealed in testing mode; and
- the hand view is created before later flip presentation begins.

SanQinFeng's ordered attacks use the normal asset-backed attack effect and
all existing flip/exile feedback. No card-specific visual effect is added.

## AI and Determinism

All new behavior executes in copied `DuelState`; scene nodes and timers never
enter simulator code. Generated hand cards and every attack result are
visible to greedy evaluation and deep search.

The action executor, selector, flip pipeline, and card allocator must remain
deterministic. State copies may not alias generated card dictionaries,
abilities, powers, or hand arrays. The state key already includes card data
in hands and on the board, so generated cards affect transposition keys.

## Validation and Testing

Automated coverage must include:

- catalog validation for `CARD_BEFORE_FLIPPED`,
  `ACTION_ADD_CARD_TO_HAND`, known/unknown card IDs, both recipients, and
  malformed fields;
- fresh-instance isolation and deterministic unique IDs;
- successful self and opponent hand additions;
- full-hand `NO_EFFECT` without rolling back an earlier ki spend;
- attack invalidation after `CARD_BE_ATTACKED` producing neither before- nor
  after-flip triggers;
- attack invalidation during `CARD_BEFORE_FLIPPED` retaining prior effects
  but producing no flip or after-flip trigger;
- a non-attack pending flip following a moved target instance;
- CangSong copying for its pre-flip owner with fresh catalog state;
- CangSong summon reaction remaining intact;
- SanQinFeng selector limits 1, 2, and 3;
- row-major selection including the source itself;
- spending ki when no sword can attack;
- complete sequential attacks and later-card condition revalidation;
- start-turn captures and exiles propagating into the parent transition;
- state-copy and search-key isolation for generated cards; and
- production hand presentation with opponent concealment.

Focused catalog, selector, simulator, search, and duel-integration suites run
before the full test runner. Runtime verification boots the production game,
checks script/runtime diagnostics, exercises a CangSong copy transition, and
exercises a multi-card SanQinFeng start-turn sequence.

## Out of Scope

- New visual or audio assets.
- Optional player choices for automatic passive abilities.
- Raising the five-card hand limit.
- Taking `ACTION_ADD_CARD_TO_HAND` cards from a deck or discard pile.
- Card-specific simulator branches for these five cards.
