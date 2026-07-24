# Adding Cards and Effects

## Card Catalog Schema

Production card definitions live only in `scripts/card_catalog.gd`. Add each ID to `ALL_CARD_IDS` and `_CARD_DEFINITIONS`.

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
    "effects": [],
}
```

Optional:

```gdscript
"starting_ki": 1
```

Rules enforced by catalog validation:

- `glyph` is the card name; the retired `name` field is forbidden.
- Glyph length is 1–7 characters.
- `picture` must be a nonempty existing Godot resource path.
- `sect`, `weapon`, `description`, and `flavor` must be Strings, even when empty.
- `tier` is an integer at least 1.
- Exactly four integer powers are required.
- Starting ki is a nonnegative integer.
- At most one effect may declare an activation.
- Unknown effect, trigger, condition, and action IDs are rejected.

`&"text"` is a Godot `StringName`, used for stable identifiers. Display text remains a normal String.

## Instances and Decks

`CardCatalog.create_instance()` copies definition data into a runtime Dictionary, assigns the supplied `instance_id` and `original_owner`, initializes ki, and normalizes effects.

Effects without `retained_on_flip` are normalized to `false`. Add that field only for the unusual ability that must survive.

Starting encounter hands are in `scripts/duel_decks.gd`. The side pool currently comes from all catalog IDs. Do not reuse a runtime Dictionary for two physical copies; every copy needs a unique `instance_id`.

## Existing Declarative Examples

Draw on play:

```gdscript
{
    "id": EFFECT_DRAW_CARDS_ON_PLAY,
    "draw_count": 2,
}
```

Activate movement:

```gdscript
{
    "id": EFFECT_MOVE_AND_ATTACK,
    "activation": ACTIVATION_DRAG_TO_TARGET,
    "target_rule": TARGET_ADJACENT_EMPTY_BOARD,
}
```

Retained flip replacement:

```gdscript
{
    "id": EFFECT_EXILE_INSTEAD_OF_FLIP,
    "retained_on_flip": true,
}
```

Passive triggers:

```gdscript
{
    "id": EFFECT_BATTLE_MOMENTUM,
    "triggers": [
        {
            "event": TRIGGER_AFTER_SUCCESSFUL_FLIP_BY_SELF,
            "actions": [
                {"type": TRIGGER_ACTION_GAIN_KI, "amount": 1},
            ],
        },
    ],
}
```

## Adding a New Primitive

Do not add a `card_id` branch to the simulator or search. Add generic vocabulary:

1. Define identifiers and validation in `card_catalog.gd`.
2. Add catalog tests for valid and invalid shapes.
3. If targeted, implement generic discovery in `duel_targeting.gd`.
4. If triggered, implement event discovery/action resolution in `duel_triggers.gd`.
5. Implement resolution in `duel_effects.gd` or `duel_simulator.gd`.
6. Emit ordered pure-data transition events.
7. Add simulator tests for legality, state mutation, event order, ownership, retention, ki, and terminal edge cases.
8. Teach `duel_controller.gd` to present the new events.
9. Add an integration test for the live path.
10. Confirm AI can enumerate/apply the action using the same simulator.

If an ability needs a player choice after an action begins, first design the currently missing queued-choice mechanism. Do not resolve it only in UI code.

## Required Edge Cases

For every new effect, consider:

- source or target removed before resolution;
- source ownership changed;
- effect lost during a previous flip;
- duplicate card copies and stable instance identity;
- empty/full hand or deck;
- multiple simultaneous triggers;
- extra turns and active-player changes;
- terminal state reached mid-resolution;
- AI clone/search behavior;
- face-down information leakage;
- deterministic event and action ordering.

## Art and Inspector

Card art is centered and scaled so its full texture rectangle occupies 80% of the card's shorter side. Powers render above the picture. Card backs keep their separate design.

Inspector text uses `glyph`, then tags in sect/tier/weapon order, followed by description and flavor. Chinese text must use the current smart/arbitrary wrapping path so Android does not treat the full sentence as one unbreakable word.

## Verification

Run catalog tests first, then simulator tests, then the full runner. For visible changes, also play with mouse and touch-sized portrait input. Never rely on printed description as proof that an effect is implemented; catalog `effects` plus simulator tests are the evidence.
