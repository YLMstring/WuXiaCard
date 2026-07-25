# Fixed Duel Canvas with Decorative Screen Extensions

Date: 2026-07-25
Status: Approved visual and behavioral design

## Goal

Preserve the duel's original 9:16 composition on every display while replacing
Godot's black letterbox regions with artwork that belongs to the game's restrained
wuxia presentation.

The feature must solve both observed problems:

- Tall phones must not show black bars above and below the duel.
- Summer Engine's wide PC preview must not stretch the cards, board, or spacing
  across a landscape viewport.

## Layout Architecture

The root `Duel` control continues to fill Godot's expanded viewport. It contains
two distinct layout layers:

1. `DecorBackdrop` fills the physical viewport and owns only non-interactive
   presentation outside the duel.
2. `DuelCanvas` is centered within the viewport at an immutable 9:16 aspect ratio.
   All existing interactive duel nodes become children of this canvas and lay
   themselves out using its local size.

The canvas uses the largest centered 9:16 rectangle that fits inside the current
viewport:

- If the viewport is taller than 9:16, the canvas uses the full viewport width
  and leaves decorative space above and below.
- If the viewport is wider than 9:16, the canvas uses the full viewport height
  and leaves decorative space on the left and right.
- At exactly 9:16, the canvas fills the viewport and no extension is visible.

This is a fitted canvas, not a cropped or non-uniformly stretched canvas. Existing
card proportions, the board aspect ratio, hand slot sizes, and internal spacing
remain proportional to the approved 9:16 layout.

Godot remains configured with:

```ini
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
```

`expand` makes the entire physical viewport drawable. `DuelCanvas` restores the
fixed gameplay composition within that drawable area.

## Decorative Treatment

`DecorBackdrop` has `mouse_filter = MOUSE_FILTER_IGNORE`, renders below
`DuelCanvas`, and contains no gameplay state or information.

### Taller-than-9:16 screens

The upper extension uses the approved lacquered treatment:

- Dark brown-cinnabar field coordinated with the duel header.
- Thin antique-gold horizontal rules.
- Sparse diamond-and-dot ornament centered between the rules.
- No text, controls, or mountain silhouettes.

The lower extension uses the approved rounded ink-wash treatment:

- A continuation of the duel's parchment background.
- Two translucent, overlapping mountain ridges.
- The ridge scale and height match the larger rounded profile shown in revision
  A2, not the smaller profile from the first hybrid mockup.
- Ridges use broad curves and low foothills, with no triangular or pointed peaks.
- Pale mist overlaps the ridges so they remain atmospheric rather than becoming
  a focal illustration.

The 9:16 duel stays centered, so the upper and lower extension rectangles have
equal height when system safe-area allocation is equal.

### Wider-than-9:16 screens

The left and right extensions use mirrored ink-wash mounting:

- Parchment-to-muted-sage gradients.
- Soft, translucent ink diffusion and mist ellipses.
- Symmetric intensity and placement.
- No mountain silhouettes.
- No lacquer ornament rotated or repurposed vertically.

The result should read as a portrait game mounted within a quiet painted field,
not as empty sidebars.

## Scene and Script Responsibilities

### `Duel`

- Observes viewport resizing.
- Calculates the fitted 9:16 `duel_rect`.
- Positions and sizes `DuelCanvas`.
- Passes the viewport size and `duel_rect` to `DecorBackdrop`.

### `DuelCanvas`

- Owns all current duel presentation and interaction nodes: header, hands, board,
  score panels, status, inspector, drag layer, and visual effects.
- Provides the local coordinate system used by `_layout_duel()`.
- Does not know how the outer decorative area is rendered.

Non-visual audio players may remain direct children of `Duel`; their behavior
does not depend on the canvas rectangle.

### `DecorBackdrop`

- Draws the base parchment and the aspect-specific decorations.
- Selects tall, wide, or exact-aspect presentation from the relationship between
  the viewport and `duel_rect`.
- Redraws on size changes.
- Never receives input and never affects rules, turns, AI, or card state.

Procedural drawing is preferred over resolution-specific raster images for the
lacquer rules, ornaments, fog, and rounded ridges. This keeps the extension
stable across unusual phone aspect ratios without adding multiple texture sizes.

## Interaction and Modal Behavior

- Drag-and-drop coordinates remain local to `DuelCanvas`; decorative regions
  cannot become valid drag targets.
- Card inspection remains confined to the 9:16 canvas and continues to replace
  the board area rather than covering the extensions.
- Decorative regions cannot start a drag, select a card, activate an ability, or
  become a target. Because the decoration itself ignores input, the existing
  root-level "tap anywhere to close inspection" behavior may still receive a tap
  made in an extension region.
- AI thinking, turn resolution, visual effects, and audio timing are unchanged.
- Safe-area handling is independent of this feature. The backdrop may fill the
  drawable viewport, while interactive controls remain inside `DuelCanvas`.

## Testing

Automated integration coverage must resize the root viewport to at least:

- `540 × 960` — exact 9:16 baseline.
- `405 × 900` — tall phone.
- `1280 × 839` or an equivalent wide PC preview.

The tests must verify:

- `DuelCanvas` always has a 9:16 aspect ratio.
- `DuelCanvas` is centered in the viewport.
- The exact 9:16 baseline fills the viewport.
- Tall screens expose only upper and lower extension regions.
- Wide screens expose only left and right extension regions.
- Cards retain their baseline aspect ratio and relative hand-slot proportions
  inside the canvas.
- Board-to-hand spacing remains equal.
- The decorative layer ignores input.
- Tall mode selects lacquer above and rounded ridges below.
- Wide mode selects symmetric ink wash without mountains.

The full existing test suite must pass. Runtime visual verification must inspect
one tall portrait render and one wide PC render. Android hardware verification
remains required after re-export because desktop viewport tests cannot validate
device cutouts or manufacturer-specific safe-area behavior.

## Acceptance Criteria

The feature is accepted when:

1. A tall Android display shows no black letterbox regions.
2. The duel itself looks identical in proportion to the original 9:16 design.
3. The top extension uses the restrained lacquer ornament.
4. The bottom extension uses clearly visible but rounded, mist-softened mountains.
5. A wide Summer Engine game view preserves the portrait duel without stretched
   cards and uses mountain-free mirrored ink-wash side mounting.
6. Decorations never intercept gameplay input or alter game state.
7. Exact 9:16 displays remain visually and behaviorally unchanged.

## Out of Scope

- Landscape gameplay redesign.
- Functional controls or information in the extension areas.
- Animated parallax, weather, particles, or audio tied to the backdrop.
- Platform-specific art variants.
- Changes to card, board, AI, rules, or card-inspection behavior.
