# Card Catalog Metadata Design

## Goal

Make `glyph` the sole production card name and prepare catalog entries for future deck-building, filtering, card information, and narrative presentation.

## Production Card Schema

Every definition in `CardCatalog` must contain these flat fields:

```gdscript
{
	"id": &"xu_shu",
	"glyph": "徐",
	"sect": "",
	"tier": 1,
	"weapon": "",
	"description": "",
	"flavor": "",
	"powers": [3, 2, 3, 2],
	"effects": [],
}
```

The old `name` field is removed from both definitions and production runtime instances. `glyph` is the only card display name from this point forward; it may contain one or more characters despite the historical field name.

`sect`, `weapon`, `description`, and `flavor` are ordinary `String` values. They are required but may be empty during this migration. `tier` is a required integer of at least `1`. All existing cards initially use empty text metadata and tier `1`; no faction, equipment, rules text, or lore is invented in this change.

## Runtime Data

`CardCatalog.create_instance` copies all five metadata fields into every production card instance. This makes them available to hands, decks, board cards, removed cards, future deck-building screens, and future simulator effects without another conversion layer.

Production code must not read or synthesize `name`. The simulator's missing-`card_id` fallback derives an identifier from `glyph` instead of `name`.

`DuelRules.make_card` remains a lightweight fixture helper and may retain its first descriptive argument and legacy `name` key. Those dictionaries exist only in rules/simulator/search fixtures, not in the production catalog contract. Catalog and integration tests must ensure production instances do not carry `name`.

## Validation

Catalog validation requires:

- a non-empty `glyph` string;
- present `sect`, `weapon`, `description`, and `flavor` fields whose values are strings;
- a present integer `tier` of at least `1`;
- the existing ID, powers, starting-ki, effect, trigger, and activation rules;
- absence of the retired `name` field.

Empty metadata strings are valid for now. Validation becomes stricter later only when the game establishes concrete sect, weapon, description, or flavor requirements.

## Consumers and Compatibility

`CardView` continues to display `glyph`. The user's disabled-tooltip behavior remains unchanged. Tests that previously used production `name` to confirm hidden-card data or state-copy isolation switch to `glyph` and the new metadata fields.

No visual layout, duel rules, AI evaluation, deck composition, or effect behavior changes in this migration.

## Testing

Automated tests verify that:

- every catalog definition has the new required fields and no `name`;
- invalid metadata types and tiers fail validation;
- production instances copy all metadata and omit `name`;
- returned definitions and runtime instances remain deep-copy isolated;
- hidden opponent cards retain private metadata while exposing none through tooltips;
- side-deck and duplicated-state isolation no longer depends on `name`;
- all existing rules, simulator, search, and integration suites continue to pass.
