# Card Pictures Design

## Goal

Give every production card a proper face-up picture using the existing transparent PNG library while preserving the current card back, card dimensions, powers, effects, input behavior, and portrait layout.

## Catalog Contract

Every production card definition gains a required ordinary String field named `picture`. The ten current definitions map in `ALL_CARD_IDS` order to:

1. `res://pics/LKT010_001.png`
2. `res://pics/LKT010_002.png`
3. `res://pics/LKT010_003.png`
4. `res://pics/LKT010_004.png`
5. `res://pics/LKT010_005.png`
6. `res://pics/LKT010_006.png`
7. `res://pics/LKT010_007.png`
8. `res://pics/LKT010_008.png`
9. `res://pics/LKT010_009.png`
10. `res://pics/LKT010_010.png`

`CardCatalog.create_instance` copies `picture` into runtime card data. Catalog validation requires a non-empty String path that resolves to an existing resource. This keeps deck-building, future card-information screens, and runtime card views on the same declarative data contract.

Fixture cards created outside the production catalog may omit `picture`; CardView then displays a blank face rather than failing. Invalid or missing paths in production definitions fail catalog validation and automated tests.

## Face-Up Presentation

CardView gains a `TextureRect` picture layer centered on the card. Its bounding square is recalculated whenever the card resizes:

- square side length equals exactly `0.8 * min(card_width, card_height)`;
- the square is centered on both axes;
- the complete 1000×1000 texture canvas is fitted into that square;
- transparent padding is included in the scaling calculation;
- aspect ratio is preserved;
- the image is never cropped, stretched, or used to change the card's minimum size.

The picture is visible only for a face-up card with a valid texture. Concealing a card hides the picture and shows the existing centered diamond card back. Revealing it restores the same picture from retained private runtime data. The user's disabled glyph and tooltip presentation remains unchanged.

## Layer Order

The face-up picture sits at the base presentation layer. All four power labels receive a higher `z_index`, so their numbers remain readable even if opaque pixels overlap them. The existing ki badge stays above both, and Ink Slash / Ink Summon effects keep their current higher layers.

No color tint, outline, shadow, background removal, per-image crop, or per-image offset is introduced. All 573 source pictures use the same rule.

## Loading and Generated Files

CardView loads the declared resource path through Godot's resource loader; Godot's resource cache prevents duplicate texture decoding across card instances. The source PNG files remain the authoritative assets.

The 573 generated `.png.import` files are not modified, staged, or committed as part of this feature.

## Testing

Automated coverage verifies:

- all production definitions declare valid existing picture resources;
- the ten initial mappings are stable and copied into runtime instances;
- the picture square is centered and uses exactly 80% of the shorter card side at hand and board sizes;
- the TextureRect preserves aspect ratio and ignores texture size for layout;
- power labels render above the picture;
- face-down cards hide the picture and preserve the diamond back;
- repeated conceal/reveal restores the correct picture without tooltip or glyph leakage;
- fixture cards without pictures remain valid blank-faced test fixtures;
- existing rules, simulator, search, and duel integration behavior remains unchanged.
