# Mechanic: Exile Instead of Flip

**Canonical specification:** `docs/superpowers/specs/2026-07-19-card-catalog-exile-effect-design.md`

## Input

The player drags Tiger General or Gate General onto a legal board cell, or any future combo/effect makes one of those cards attempt a flip. AI placement uses the same simulator action.

## Response

Every enemy card that would be flipped is exiled in top-right-bottom-left order. Exiled cards enter their original owner's removed-card zone, count for neither player, and leave reusable board cells.

## Ability Retention

Every catalog ability declares `retained_on_flip`. Retained abilities work for the card's new owner. Non-retained abilities are removed permanently from that match-local card instance and do not return if the card flips back. Tiger General and Gate General retain `exile_instead_of_flip`.

## Feedback

- **Visual:** Source pulse, dark red ink strike, target shrink and dissolve.
- **Audio:** Low brush-slash activation and a soft paper-tear per target.
- **Mechanical:** No flip occurs, scores count only surviving board cards, and cleared cells become legal placements.

## Failure Modes

- Allied, empty, tied, and stronger targets are unaffected.
- Unknown card/effect IDs fail catalog validation during development.
- Input is locked while ordered transition events are presented.
- Effect and turn guards prevent future recursive loops.

## Depth

Exiling denies ownership but also reopens valuable cells. Players must weigh immediate score denial against giving either side a new placement opportunity. Retention adds another axis: flipping some cards may permanently strip their abilities, while retained effects can be turned against their original owner.

## Tunables

- Source pulse duration.
- Exile dissolve duration.
- Delay between targets.
- Ink color.
- Removal audio volume.

## Scene and Script Sketch

```text
Duel
├── RemovalAudio                      new
└── CardView                          add exile/ability-loss presentation

card_catalog.gd                       definitions and retention declarations
duel_decks.gd                         encounter card IDs
duel_effects.gd                       pure event replacements
duel_simulator.gd                     authoritative state transition
duel_controller.gd                    ordered presentation only
```
