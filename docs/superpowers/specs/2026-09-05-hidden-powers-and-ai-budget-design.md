# Hidden Powers and AI Budget Design

## Player-visible rules

- An unrevealed card normally keeps its identity, picture, description, and
  inspection interaction concealed, but shows its four numbered powers.
- A card whose four powers use the special `-1` semantics still shows no power
  numbers.
- Difficulty eight and above restores the old concealment behavior: unrevealed
  enemy cards show no power numbers in the duel, deck-builder, and reward
  screens.
- Difficulty eight no longer draws a card when the enemy hand first reaches one
  card.
- The normal enemy search deadline is five seconds. Difficulty nine and above
  doubles it to ten seconds. The existing two-second minimum presentation delay
  is unchanged.
- Difficulty nine no longer increases a random enemy opening-hand card's
  powers.
- Dongfang Bubai and Zhang Sanfeng are normal level-fifteen enemies again.

## Implementation

`CardView` receives a separate concealed-power visibility switch. Face-down
state continues to control identity/picture/inspection, while power labels use
both the existing global power-number switch and the new concealed-power
switch.

`DifficultyRules` owns the cumulative difficulty-eight concealment gate and
the difficulty-nine search-time multiplier. Controllers configure the card
view from the active run difficulty. `DuelController` passes the effective
deadline to the existing search session.

The retired difficulty-eight latch remains serialized for compact-state and
replay compatibility, but its draw hook becomes inactive. The difficulty-nine
opening mutation is removed from opening setup.

The two former benchmark-only enemy rows move into the normal ordered catalog;
the benchmark roster continues to derive from the same definitions without
duplicates.

## Verification

- Unit tests cover the revised difficulty texts and gates.
- Card/controller integration tests cover visible face-down powers at ordinary
  difficulty and hidden face-down powers at difficulty eight.
- Search-budget tests cover five seconds normally and ten seconds at difficulty
  nine.
- Enemy-catalog tests cover the 34-entry normal roster and three level-fifteen
  candidates.
- Opening and simulator tests prove the retired difficulty effects no longer
  occur.
- Run the full canonical suite after implementation.
