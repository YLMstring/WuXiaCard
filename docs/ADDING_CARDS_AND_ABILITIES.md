# Adding Cards and Abilities

## Card Catalog Schema

Production card definitions live only in `scripts/card_catalog.gd`. Add each ID
to `ALL_CARD_IDS` and `_CARD_DEFINITIONS`.

Required fields:

```gdscript
&"example_id": {
    "id": &"example_id",
    "glyph": "一到七字",
    "picture": "res://pics/example.png",
    "sect": "",
    "tier": 1,
    "weapon": "",
    "description": "",
    "flavor": "",
    "powers": [4, 5, 6, 7], # top, right, bottom, left
    "abilities": [],
}
```

Optional:

```gdscript
"starting_ki": 1
```

Catalog rules:

- `glyph` is the card name; the retired `name` field is forbidden.
- Glyph length is 1–7 characters.
- `picture` is a nonempty existing Godot resource path.
- `sect`, `weapon`, `description`, and `flavor` are Strings.
- `tier` is an integer at least 1.
- Exactly four integer powers are required.
- Starting ki is a nonnegative integer.
- Abilities have no ID.
- At most one ability entry may declare `activation`.
- Unknown events, conditions, actions, inputs, targets, fields, and policies are
  rejected.

`&"text"` is a Godot `StringName`, used for stable vocabulary identifiers.
Display text remains a normal String.

## Instances and Runtime Abilities

`CardCatalog.create_instance()` copies definition data into a runtime
Dictionary, assigns `instance_id` and `original_owner`, initializes ki, and
creates `active_abilities`.

Abilities without `retained_on_flip` normalize to `false`. Add the flag only
for an unusual ability that survives an ownership flip.

Starting encounter hands are in `scripts/duel_decks.gd`. The side pool currently
contains all catalog IDs. Never reuse one runtime Dictionary for two physical
copies; every copy needs a unique `instance_id`.

## Triggered Ability Shape

```gdscript
{
    "retained_on_flip": true,
    "triggers": [{
        "event": CARD_BE_ATTACKED,
        "conditions": [
            {"type": CONDITION_ATTACKER_CARD_IS_SELF},
        ],
        "actions": [
            {"type": ACTION_EXILE_ATTACKED_CARD},
        ],
    }],
}
```

Conditions are ANDed in declaration order. Actions resolve in declaration
order. Global trigger sources resolve by row-major board cell, then ability
array order, then trigger array order.

Every rule uses stable card instance and cell context. Stale or missing context
returns `NO_EFFECT` by default, so later actions continue. To stop only that
rule's remaining actions, opt in on the action:

```gdscript
{
    "type": ACTION_MOVE_SELF_TO_TARGET,
    "on_invalid_context": STOP_RULE,
}
```

## Current Examples

Draw after summon reactions:

```gdscript
{
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [
            {"type": CONDITION_TRIGGER_CARD_IS_SELF},
        ],
        "actions": [
            {"type": ACTION_DRAW_CARDS, "amount": 2},
        ],
    }],
}
```

Summon reaction:

```gdscript
{
    "triggers": [{
        "event": TRIGGER_CARD_SUMMONED,
        "conditions": [
            {"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
            {"type": CONDITION_TRIGGER_CARD_IN_RANGE},
        ],
        "actions": [
            {"type": ACTION_ATTACK_TRIGGER_CARD},
        ],
    }],
}
```

Move-and-attack activation:

```gdscript
{
    "activation": {
        "input": ACTIVATION_DRAG_TO_TARGET,
        "target_rule": TARGET_ADJACENT_EMPTY_BOARD,
        "costs": [
            {"type": ACTION_SPEND_KI, "amount": 1},
        ],
        "actions": [
            {"type": ACTION_MOVE_SELF_TO_TARGET},
            {"type": ACTION_STANDARD_ATTACK_WITH_SELF},
        ],
    },
}
```

Meng Huo:

```gdscript
{
    "triggers": [
        {
            "event": CARD_AFTER_FLIPPED,
            "conditions": [
                {"type": CONDITION_ATTACKER_CARD_IS_SELF},
            ],
            "actions": [
                {"type": ACTION_GAIN_KI, "amount": 1},
            ],
        },
        {
            "event": TRIGGER_END_OWNER_TURN,
            "conditions": [
                {"type": CONDITION_TURN_OWNER_IS_SELF},
                {"type": CONDITION_KI_AT_LEAST, "amount": 1},
            ],
            "actions": [
                {"type": ACTION_SPEND_ALL_KI},
                {"type": ACTION_REQUEST_EXTRA_TURN},
            ],
        },
    ],
}
```

## Resolution Timing

Normal summon:

1. place and emit `card_placed`;
2. resolve global `TRIGGER_CARD_SUMMONED`;
3. if the exact summoned instance remains in its cell, resolve its current
   `TRIGGER_CARD_AFTER_SUMMONED` rules for its current owner;
4. standard attack only if it still belongs to the summoning owner;
5. finish the turn.

Every attack:

1. record exact attacker and target context;
2. resolve global `CARD_BE_ATTACKED`;
3. revalidate exact instances, cells, and enemy relationship;
4. flip only if still valid;
5. resolve `CARD_AFTER_FLIPPED`.

Movement is not a summon. Exile is not a flip.

## Adding a New Primitive

Do not add a `card_id` branch to simulator, search, or controller.

1. Add vocabulary and schema validation in `card_catalog.gd`.
2. Add catalog rejection/acceptance tests.
3. Add targeting or conditions in `duel_targeting.gd` /
   `duel_triggers.gd`.
4. Add the generic action to `duel_ability_executor.gd`.
5. Let `duel_simulator.gd` service typed phase requests.
6. Emit ordered pure-data transition events.
7. Add simulator tests for identity, timing, ownership, retention, invalid
   context, and ordering.
8. Add controller presentation only after the simulator passes.
9. Verify greedy and deep AI use the same simulator behavior.

If an ability needs a player choice after an action begins, first design the
currently missing queued-choice mechanism. Do not resolve it only in UI code.

## Required Edge Cases

For every new ability, consider:

- source or target removed, moved, or replaced before resolution;
- source ownership changed;
- ability lost during a previous flip;
- duplicate copies and stable instance identity;
- empty/full hand or deck;
- multiple simultaneous triggers;
- action invalid-context policy;
- cumulative activation costs;
- extra turns and active-player changes;
- terminal state reached mid-resolution;
- AI clone/search behavior;
- face-down information leakage;
- deterministic event and action ordering.

## Art and Inspector

Card art is centered and scaled so its full texture rectangle occupies 80% of
the card's shorter side. Powers render above the picture. Card backs keep their
separate design.

Inspector text uses `glyph`, then tags in sect/tier/weapon order, followed by
description and flavor. Chinese text must use the current smart/arbitrary
wrapping path so Android does not treat a sentence as one unbreakable word.

## Verification

Run catalog tests first, simulator tests next, then the full runner. For visible
changes, also play with mouse and touch-sized portrait input. Catalog
`abilities` plus simulator tests—not printed description—are proof that an
ability is implemented.
