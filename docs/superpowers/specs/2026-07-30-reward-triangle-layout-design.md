# Reward Triangle Layout Design

## Goal

Use the reward scroll's empty vertical space more effectively by arranging its
three reward cards as a large upward-pointing triangle.

## Layout

- Reward card 1 occupies the centered upper position.
- Reward cards 2 and 3 occupy the lower-left and lower-right positions.
- The three cards retain the standard 3:4 card ratio.
- Each slot targets 1.4 times the current three-column slot width and is
  clamped only when necessary to keep both rows, names, and gaps inside the
  parchment.
- Card names remain centered beneath their cards with the existing name gap.
- The complete triangle is centered inside the usable parchment area below the
  title and divider.

## Architecture

`DeckLibraryGrid` gains an explicit reward-triangle layout option. Its existing
virtual grid remains the default and is unchanged for deck-building and sect
selection. `reward_selection.tscn` enables the triangle option for its
three-slot grid.

The triangle option changes only slot size and position calculation. It
continues to use `DeckLibrarySlot`, so card rendering, tier-name colors,
inspection, hold feedback, drag vacancy, and drag signals remain shared.

## Interaction

- Tapping any reward card opens the existing card inspector.
- Holding and dragging any reward card behaves exactly as it does now.
- Dragging a reward card to the player's hand claims it.
- Empty or missing reward entries retain the existing card-back behavior.
- The triangle does not scroll because it contains exactly three reward slots.

## Display Colors

- Each of the three reward slots independently rolls red or blue with equal
  probability whenever the reward scene opens.
- Placeholder card backs participate in the same independent color roll.
- Rolled colors remain stable for the lifetime of that reward scene.
- Display color does not change card ownership, reward contents, inspection,
  dragging, or claiming.

## Validation

- Assert that the first slot is horizontally centered above the other two.
- Assert that the second and third slots share the same lower vertical
  coordinate and are symmetric around the scroll center.
- Assert that reward cards preserve the 3:4 ratio and reach the 1.4-times
  width target at the reference portrait size.
- With a fixed test seed, assert the expected red/blue owner sequence for all
  three slots, including placeholders.
- Run the reward-selection integration tests.
- Render the reward scene at portrait and wide-window sizes and confirm that
  all three card names remain visible and the triangle stays centered.
