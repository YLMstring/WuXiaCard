# Main Menu Background Design

## Goal

Create a dramatic ink-wash main-menu background for **九宫论剑** that remains
composed behind responsive Godot UI on standard portrait phones, extra-tall
phones, and wide desktop displays.

## Art Direction

The scene depicts two tiny martial masters facing each other across a
monumental nine-square stone arena on a storm-lit mountaintop. The arena is
viewed from a slightly elevated cinematic angle and reads clearly as a
three-by-three grid without resembling the literal duel interface.

The image combines:

- expressive black and charcoal ink clouds;
- layered, rounded mountain silhouettes;
- pale mist flowing across and between the stone squares;
- restrained lacquer-red banners or cloth accents;
- sparse antique-gold light catching stone edges and mist;
- elegant classical Chinese ink-painting texture with cinematic scale.

The mood is tense, mythic, and prestigious rather than violent or grim.

## Responsive Composition

The artwork contains no text or UI. Godot will render the title `九宫论剑` and
the three actions `踏入江湖`, `名震武林`, and `封剑归隐`.

All essential imagery stays within the central crop-safe region:

- the upper center remains relatively calm for the title;
- the middle-to-lower center remains readable behind the menu actions;
- the two masters and the recognizable core of the nine-square arena survive
  both narrow portrait and wide landscape crops;
- outer mountains, cloud banks, mist, and ink texture provide expendable
  material at every edge.

The final master should support center-crop rendering rather than stretching.
No single edge contains unique narrative information.

## Asset Requirements

- Raster illustration suitable for a full-screen game menu.
- High-resolution square master to support opposing portrait and landscape
  crops.
- No lettering, logos, interface elements, decorative frame, or watermark.
- No oversized foreground character portrait.
- Avoid anime styling, photorealism, neon colors, sharp alpine peaks, cluttered
  central detail, and excessive red or gold.
- Final approved asset will be copied into
  `res://pics/main_menu_background.png`.

## Review

Before project integration, inspect the generated master and representative
9:16, 9:20, 16:9, and ultrawide center crops. The arena, duelists, title space,
and menu space must remain legible in each.
