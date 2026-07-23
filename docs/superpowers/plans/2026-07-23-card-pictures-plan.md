# Card Pictures Implementation Plan

## Objective

Map the first ten existing silhouette PNGs to the ten production cards and render each face-up picture as a centered square whose side is exactly 80% of the card's shorter side, with power numbers above it and the existing card back unchanged.

## Task 1: Extend the catalog contract

**Files:** `scripts/card_catalog.gd`, `tests/test_card_catalog.gd`

1. Add `picture` paths `res://pics/LKT010_001.png` through `LKT010_010.png` to definitions in `ALL_CARD_IDS` order.
2. Copy `picture` into every production runtime instance.
3. Validate that `picture` is a non-empty String and `ResourceLoader.exists(path)` returns true.
4. Test exact mapping order, invalid type/path rejection, runtime copying, and definition-copy isolation.

## Task 2: Add the face-up picture layer

**Files:** `scenes/card_view.tscn`, `scripts/card_view.gd`

1. Add a mouse-ignoring `TextureRect` under `Overlay`, behind powers and effects.
2. Configure it to ignore the source texture's minimum size and preserve aspect ratio without cropping.
3. Load the runtime `picture` path when CardView refreshes; rely on Godot's resource cache for repeated paths.
4. On every card resize, set the TextureRect to a centered square with side `0.8 * min(width, height)`.
5. Show it only for face-up cards with a valid texture; hide it for face-down or fixture cards without pictures.
6. Keep the disabled glyph and tooltip presentation unchanged.

## Task 3: Make overlay order explicit

**Files:** `scenes/card_view.tscn`, `tests/test_duel_integration.gd`

1. Give the picture the base z-index.
2. Give all four power labels a higher z-index than the picture.
3. Preserve the ki badge and Ink Slash / Ink Summon effect ordering.

## Task 4: Update integration coverage

**File:** `tests/test_duel_integration.gd`

1. Replace obsolete glyph-display checks with picture geometry and TextureRect configuration checks.
2. Verify exact 80% centered sizing at representative hand and board dimensions.
3. Verify production cards load their declared texture while picture-less fixtures remain blank.
4. Verify conceal hides the picture, the diamond remains, and reveal restores the same texture.
5. Verify power labels render above the picture.

## Task 5: Verification and commit

1. Run catalog, rules, simulator, search, and integration suites headlessly.
2. Launch the portrait game and inspect pictures in both hands and on the board.
3. Commit a move through the production path and check conceal/reveal plus runtime diagnostics.
4. Review the diff and commit the feature without staging generated `.png.import` files.
