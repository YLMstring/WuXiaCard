# Testing Mode and Hidden Opponent Hand Design

## Goal

Add a developer-controlled testing mode that lets one person manually play both sides of a duel. In normal mode, preserve the existing AI-controlled opponent while hiding the identities and powers of cards still in the opponent's hand.

The mode is selected before launch in a script. It cannot be changed through the game UI or during a duel.

## Selected Approach

Create a small, dedicated game-settings script with a constant testing-mode flag. The duel controller reads the flag when it initializes and uses it to choose input ownership, AI behavior, and initial hand visibility.

This is preferred over an inspector property because it gives developer-only settings one explicit home and avoids accidentally saving a scene in testing mode. A command-line or build-feature flag is unnecessary at the current project scale.

## Configuration

`scripts/game_settings.gd` will expose a constant named `TESTING_MODE`.

- `false`: normal duel behavior.
- `true`: manual control of both players.

The setting is read as immutable configuration for the lifetime of the duel. There is no runtime setter, menu option, keyboard shortcut, or hidden gesture.

The controller copies the constant into its mode field when the controller instance is created. Production code never changes that field. Automated tests may assign the field before adding a newly instantiated duel to the scene tree, allowing both modes to be covered without editing the global setting or introducing an in-game toggle.

## Normal Mode Behavior

- The player hand is face-up and can be dragged only during the player's turn.
- The opponent hand contains one face-down card back for each remaining opponent card.
- A face-down card hides its name, glyph, four power values, effects, and tooltip.
- The underlying card data remains unchanged so the AI retains perfect information and future reveal effects can expose cards without reconstructing them.
- Opponent cards are not draggable.
- The existing opponent AI selects and commits opponent moves.
- When an opponent card leaves the hand for the board, it becomes face-up before its placement presentation finishes.
- Empty hand slots remain visible after cards are played, preserving the fixed five-slot layout.

## Testing Mode Behavior

- Both hands are face-up from the start.
- The AI is disabled completely; an opponent turn waits indefinitely for manual input.
- Turns and all simulator legality rules remain unchanged.
- Only cards belonging to the currently active player are draggable.
- On a player turn, the bottom hand is playable.
- On an opponent turn, the top hand is playable.
- The same drag, drop, placement, capture, exile, scoring, pass, and terminal-match paths are used for both owners.
- Turn-status text explicitly identifies testing mode and the side awaiting input.

Testing mode is a controller and presentation option, not a separate ruleset. It must not alter card definitions, decks, simulator state, scoring, effects, or move legality.

## Components

### Game settings

The settings script owns only developer-selected configuration. The duel controller depends on it; the simulator and rules do not.

### Card view visibility

`CardView` gains an explicit face-down presentation state and a method to change it. Applying the state updates all private visual surfaces together:

- face labels and glyph;
- tooltip;
- card-front styling;
- card-back styling.

The card keeps its `card_data` while face-down. Restoring face-up presentation derives visible content from that existing data. Calling the method repeatedly with the same value is safe.

This interface is intentionally reusable by future reveal and conceal abilities.

### Duel controller ownership

The controller generalizes its existing player-only drag handlers:

1. Determine the dragged card's owner and source hand.
2. Reject the drag unless that owner matches the simulator's active player and the controller's current turn state.
3. Store the simulator hand index before reparenting the card to the drag layer.
4. Commit the move using that card's owner.
5. Return invalid drops to the card's recorded home slot.

After every transition, one controller method synchronizes hand playability from the active owner. In normal mode it invokes AI when the active owner is the opponent. In testing mode it enables the opponent hand and waits for the user instead.

## Turn and Pass Flow

The simulator remains authoritative for `active_player`, including automatic passes when only one side has legal moves. The controller reads the resulting active owner after each move:

- terminal state: disable both hands and show the result;
- player active: enable the bottom hand;
- opponent active in normal mode: disable both hands while the AI acts;
- opponent active in testing mode: enable the top hand and wait for a drag.

This prevents the testing feature from duplicating or bypassing simulator logic.

## Error and Edge Handling

- A drag from the inactive side is rejected without mutating duel state.
- Dropping outside the board or on an occupied cell returns the card to its original slot.
- A face-down card must never expose private information through tooltip text.
- Any opponent card placed on the board is revealed even if placement is invoked through tests or a future non-drag effect.
- Finishing the match disables both hands in both modes.
- Existing focus-loss drag cancellation continues to return either owner's card safely.

## Verification

Automated integration coverage will verify:

- normal mode creates five face-down opponent cards with no visible glyph, powers, or tooltip;
- normal mode keeps opponent cards non-playable and still performs an AI reply;
- an AI-played opponent card is face-up on the board;
- testing mode starts with both hands visible;
- testing mode does not automatically make an opponent move;
- after a manual player move, only the opponent hand becomes playable;
- dragging and committing an opponent card advances the same production simulator path;
- after the opponent move, control returns to the player hand;
- invalid opponent drops and focus loss return the card to its original top-hand slot;
- the existing fixed hand-slot layout remains unchanged.

A manual portrait playtest will confirm that card backs are visually clear, turns can be alternated comfortably on mouse and touch, and no opponent information leaks in normal mode.

## Out of Scope

- An in-game mode toggle or developer menu.
- A reveal-card ability; only the reusable face-down interface is prepared.
- Changing AI strength or search behavior.
- Multiple human devices, networking, or hot-seat identity prompts.
- New final card artwork. The first card back will use deterministic placeholder styling consistent with the current prototype UI.
