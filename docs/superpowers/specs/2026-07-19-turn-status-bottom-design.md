# Turn Status Bottom Placement

## Goal

Place `TurnStatus` below the player's hand at the bottom of the portrait duel screen while preserving responsive layout across mobile aspect ratios.

## Design

- Keep `TurnStatus` as a direct child of the duel root and retain its existing text, styling, and state-update behavior.
- In `_layout_duel()`, set its horizontal position and width to match `PlayerHand`.
- Set its vertical position to the bottom of `PlayerHand` plus an 8-pixel gap.
- Keep the label 26 pixels high and clamp its vertical position so the full label remains inside an 8-pixel bottom safe margin.
- Replace the scene's initial offsets with bottom-area fallback offsets so the editor preview matches runtime placement.

## Data Flow

Viewport resize → `_layout_duel()` recalculates `PlayerHand` → `TurnStatus` is positioned from the final hand rectangle.

## Verification

- Add an integration assertion that `TurnStatus` is below `PlayerHand`.
- Assert their left edge and width match.
- Assert the status label remains within the viewport bottom safe margin.
- Run the duel rules test, integration test, and project boot.
- Open a fresh playtest for visual confirmation at portrait size.

## Scope

No changes to turn-state logic, wording, hand position, board position, typography, or gameplay behavior.
