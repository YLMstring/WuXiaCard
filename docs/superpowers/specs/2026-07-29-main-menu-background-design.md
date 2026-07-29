# Main Menu Background Design

## Goal

Create a dramatic ink-wash main-menu background for **九宫论剑** that remains
composed behind responsive Godot UI on standard portrait phones, extra-tall
phones, and wide desktop displays.

## Art Direction

The scene depicts one tiny martial champion surrounded by eight swordsmen on a
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

All essential imagery stays inside the square master:

- the upper center remains relatively calm for the title;
- the middle-to-lower center remains readable behind the menu actions;
- all nine swordsmen and the complete nine-square arena remain visible on every
  supported aspect ratio;
- outer mountains, cloud banks, mist, and ink texture transition naturally
  into decorative screen extensions.

The final master is never stretched or cropped. Godot displays the entire
square at the largest size that fits the viewport, then fills the remaining
top-and-bottom or left-and-right bands with matching mist, paper, mountain, and
ink extensions. These extensions are decorative and contain no title, menu
actions, swordsmen, or unique narrative information.

## Asset Requirements

- Raster illustration suitable for a full-screen game menu.
- High-resolution square master to support opposing portrait and landscape
  crops.
- Exactly nine swordsmen: one champion entirely on the center slab and one
  opponent entirely on each surrounding slab.
- Every opponent faces or turns toward the central champion in a radial siege.
- Every swordsman stands near the visual center of their assigned slab, with a
  clearly visible margin of empty stone separating feet, body, robes, and
  weapon from all four seams.
- Restrained attack stances vary naturally without changing this centered
  placement.
- If narrow-screen visibility requires adjustment, reduce figure scale rather
  than moving figures toward seams.
- No swordsman touches, crosses, or stands between grid seams.
- No lettering, logos, interface elements, decorative frame, or watermark.
- No oversized foreground character portrait.
- Avoid anime styling, photorealism, neon colors, sharp alpine peaks, cluttered
  central detail, and excessive red or gold.
- Final approved asset will be copied into
  `res://pics/main_menu_background.png`.

## Review

Before project integration, inspect the generated master and representative
9:16, 9:20, 16:9, and ultrawide contain-plus-extension compositions. The
complete arena, all nine swordsmen, title space, and menu space must remain
legible in each.
