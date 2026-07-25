# Unified Lacquer Header Design

## Goal

Make the tall-screen decorative top extension and the duel header read as one continuous warm lacquer surface.

## Approved Appearance

- The decorative top extension and `TopWash` use the exact same base color: `#452824`.
- The decorative top extension and `TopWash` also use the same horizontal warm tint:
  - Offsets: `0.0`, `0.52`, `1.0`.
  - Edge colors: fully transparent.
  - Center color: `Color(0.42, 0.25, 0.22, 0.66)`.
- The tint is aligned by normalized horizontal position across the full width, so the visible color immediately above and below the seam matches at every X coordinate.
- `TopWash/CenterTint` scales the gradient to its full rectangle. It does not preserve the one-pixel texture's aspect ratio or crop to its bright center.
- The upper decorative gold line keeps its existing inset.
- The lower decorative gold line sits visually at the seam between the decorative extension and the fixed 9:16 duel canvas.
- The lower line is drawn half a pixel inside the decorative extension so it remains visible instead of being covered or clipped at the boundary.
- The central diamond-and-dot ornament row is vertically centered between the two gold lines.
- The existing ornament spacing, ornament scale, antique-gold color, bottom edge, and shadow remain unchanged.

## Shared Styling Source

`DuelBackdrop` owns the lacquer base color and a reusable tint-texture factory. Both the procedural decoration and `_style_duel_header()` use that shared factory. This keeps their rendered appearance synchronized if the tint is adjusted later.

## Return Icon

- The visible “返回” button is replaced by a 24×24 left-pointing back-arrow icon.
- The arrow is gold and follows the existing normal, hover, pressed, and focus color progression.
- No visible background, border, frame, or focus rectangle remains.
- A transparent 44×44 `Button` interaction target remains for reliable mobile tapping, keyboard focus, tooltip text “返回,” and the existing `_on_exit_pressed()` action.
- The icon is a local SVG so its shape is stable across fonts and platforms.

## Geometry

For the top decorative extension:

- `first_y = rect.position.y + inset`
- `second_y = rect.end.y - 0.5`
- `ornament_y = (first_y + second_y) * 0.5`

The calculation remains responsive to the height of the decorative extension.

## Scope

This change affects only the tall-screen top treatment. It does not change:

- The fixed 9:16 duel canvas or its layout.
- Bottom mountain decoration.
- Wide-screen side decoration.
- Input handling or gameplay.

## Verification

- Confirm the decorative extension and `TopWash` have no visible color mismatch.
- Confirm the warm center tint continues smoothly through the seam at the left edge, center, and right edge.
- Confirm `CenterTint` scales rather than aspect-crops the gradient.
- Confirm the lower gold line is visible at the seam.
- Confirm the ornament row is centered between both gold lines.
- Confirm the return control shows only the gold arrow while retaining a 44×44 interaction target and the existing exit action.
- Run the backdrop and integration test suites.
- Inspect a tall runtime frame.
