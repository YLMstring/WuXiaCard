# Main Menu Background Design

## Goal

Create a dramatic ink-wash main-menu background for **九宫论剑** that remains
composed behind responsive Godot UI on standard portrait phones, extra-tall
phones, and wide desktop displays.

## Art Direction

The scene depicts two tiny martial masters facing each other diagonally across
a monumental nine-square stone arena on a storm-lit mountaintop. The arena is
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
- both swordsmen and the complete nine-square arena remain visible on every
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
- Exactly two swordsmen.
- One stands near the visual center of the middle-left slab and faces
  diagonally up-right.
- The other stands near the visual center of the top-right slab and faces
  diagonally down-left.
- Heads, torsos, feet, and weapons reinforce the same line of confrontation.
- A clearly visible margin of empty stone separates each complete figure from
  all four seams of their assigned slab.
- The other seven slabs remain empty.
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
complete arena, both swordsmen, title space, and menu space must remain legible
in each.
