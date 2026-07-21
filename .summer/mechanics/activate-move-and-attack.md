# Mechanic: Ki-Powered Move and Attack

**Canonical specification:** `docs/superpowers/specs/2026-07-21-ki-activate-actions-design.md`

**Input:** On your turn, drag an eligible owned board card to a highlighted target instead of playing a hand card.

**Response:** Spend 1 ki, move the same card instance to an orthogonally adjacent empty cell, then resolve its normal four-edge attack from the destination. On-play effects do not retrigger.

**Feedback:**

- Visual: numbered jade ki bead, gold source outline, teal valid targets, brush-like movement trail.
- Audio: restrained movement whoosh, followed by existing capture/removal sounds.
- Mechanical: the source cell opens, the destination fills, ki decreases, and the action ends the turn.

**Failure modes:** Invalid target, wrong owner, missing ability, or zero ki returns the card without cost or turn loss. A flip permanently removes the non-retained activate ability but preserves ki.

**Depth:** Spending finite ki trades a hand play for board repositioning. It can attack immediately, open a placement cell, escape an exposed edge, or set up a later position even when it captures nothing.

**First cards:** Every Jiang Wei and Sun Zan instance starts with 1 ki and the move-and-attack activate ability.

**Invariant:** A card has at most one activate ability. Receiving a new activate ability replaces the old one while leaving other effects intact.
