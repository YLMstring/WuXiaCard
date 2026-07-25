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
- The upper decorative gold line keeps its existing inset.
- The lower decorative gold line sits visually at the seam between the decorative extension and the fixed 9:16 duel canvas.
- The lower line is drawn half a pixel inside the decorative extension so it remains visible instead of being covered or clipped at the boundary.
- The central diamond-and-dot ornament row is vertically centered between the two gold lines.
- The existing ornament spacing, ornament scale, antique-gold color, bottom edge, and shadow remain unchanged.

## Shared Styling Source

`DuelBackdrop` owns the lacquer base color and a reusable tint-texture factory. Both the procedural decoration and `_style_duel_header()` use that shared factory. This keeps their rendered appearance synchronized if the tint is adjusted later.

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
- Confirm the lower gold line is visible at the seam.
- Confirm the ornament row is centered between both gold lines.
- Run the backdrop and integration test suites.
- Inspect a tall runtime frame.
