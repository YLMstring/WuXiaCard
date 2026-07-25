# Unified Lacquer Header Design

## Goal

Make the tall-screen decorative top extension and the duel header read as one continuous warm lacquer surface.

## Approved Appearance

- The decorative top extension and `TopWash` use the exact same base color: `#452824`.
- The upper decorative gold line keeps its existing inset.
- The lower decorative gold line sits visually at the seam between the decorative extension and the fixed 9:16 duel canvas.
- The lower line is drawn half a pixel inside the decorative extension so it remains visible instead of being covered or clipped at the boundary.
- The central diamond-and-dot ornament row is vertically centered between the two gold lines.
- The existing ornament spacing, ornament scale, antique-gold color, `TopWash` center tint, bottom edge, and shadow remain unchanged.

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
- Confirm the lower gold line is visible at the seam.
- Confirm the ornament row is centered between both gold lines.
- Run the backdrop and integration test suites.
- Inspect a tall runtime frame.
