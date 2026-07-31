# Zi Xia Gong 1–4 Ability Design

## Goal

Implement the four existing `ZiXiaGong1`–`ZiXiaGong4` catalog descriptions through reusable trigger and action primitives. The effects must work identically in the live duel and compact AI simulation, including permanent runtime ki and power changes.

## Catalog declarations

Add these catalog constants:

```gdscript
const TRIGGER_START_OWNER_TURN: StringName = &"start_owner_turn"

const CARD_ZONE_HAND: StringName = &"hand"
const CARD_ZONE_BOARD: StringName = &"board"

const ACTION_GRANT_KI_TO_ALLIES: StringName = &"grant_ki_to_allies"
const ACTION_ADD_POWERS_TO_ALLIES: StringName = &"add_powers_to_allies"
```

The new actions share these selector fields:

- `amount`: required positive integer.
- `zones`: required non-empty array containing `CARD_ZONE_HAND`, `CARD_ZONE_BOARD`, or both.
- `weapon`: optional exact weapon-name filter.
- `exclude_self`: optional boolean, default `false`.
- `limit`: optional positive integer. Selection stops after this many valid cards.

Selectors always act relative to the ability source's current owner. Hand cards are visited in hand-slot order. Board cards are visited in established board-cell order `0` through `8`. If both zones are declared, hand cards are visited before board cards.

`ACTION_GRANT_KI_TO_ALLIES` adds `amount` ki to every selected runtime card. `ACTION_ADD_POWERS_TO_ALLIES` adds `amount` to all four powers of every selected runtime card. Both modifications are permanent for that runtime card instance.

The catalog validator must reject unknown zones, empty zone arrays, non-positive amounts or limits, non-boolean `exclude_self`, and invalid optional weapon values.

## Card rules

### ZiXiaGong1

On `TRIGGER_CARD_AFTER_SUMMONED`, if the trigger card is self, grant one ki to every allied `剑法` card in the owner's hand and on the board.

### ZiXiaGong2

On `TRIGGER_CARD_AFTER_SUMMONED`, if the trigger card is self:

1. Grant one ki to every allied `剑法` card in the owner's hand and on the board.
2. Draw one card.

The actions resolve in that order. The existing maximum-hand-size draw rule remains unchanged.

### ZiXiaGong3

At `TRIGGER_START_OWNER_TURN`, when the turn owner is self, add one to all four powers of every card in the owner's hand.

### ZiXiaGong4

ZiXiaGong4 has both of these triggers:

- At `TRIGGER_START_OWNER_TURN`, when the turn owner is self, add one to all four powers of every card in the owner's hand.
- At `TRIGGER_END_OWNER_TURN`, when the turn owner is self, add one to all four powers of the first two other allied board cards.

“First” uses board-cell order `0` through `8`. ZiXiaGong4 excludes itself. If only one valid other ally exists, that card is modified; if none exist, the action has no effect.

None of these abilities declares `retained_on_flip`, so the existing default applies: the ability is permanently lost when its ownership is flipped.

## Trigger timing

`TRIGGER_CARD_AFTER_SUMMONED` remains after summon reactions such as CangSongYingKe's immediate attack. Therefore ZiXiaGong1 or ZiXiaGong2 resolves only if its ability still exists when the after-summon trigger is revalidated. If it was removed, exiled, or flipped and lost the ability during earlier reactions, it does not grant ki or draw.

`TRIGGER_START_OWNER_TURN` is dispatched after the next active player has been chosen and before that player may perform an action. It also occurs when an extra turn begins. Start-turn rules are resolved with the same deterministic board-order discovery and sequential trigger resolution used by existing passive rules.

End-turn ZiXiaGong4 effects resolve within the existing end-owner-turn trigger phase, before the active player changes.

Multiple valid Zi Xia Gong sources resolve independently and stack. Their rule groups resolve sequentially in established board order.

## Runtime state and transition events

Ki and powers are modified on runtime card dictionaries, never on immutable catalog definitions.

Each changed card emits a deterministic transition event:

- Existing `ki_changed` is emitted for hand or board cards with instance ID, owner, previous ki, and new ki.
- A new `powers_changed` event is emitted with instance ID, owner, previous four powers, and new four powers.

Events are emitted in selector order. These events let the live controller refresh affected card views while the simulator receives the same state changes without depending on presentation.

Cards with no activate ability may accumulate ki normally. Existing ki-bead visibility rules remain unchanged.

## Presentation

Passive ability sources use the existing pre-trigger card pulse. Activate abilities remain unaffected.

The controller must find affected card views by runtime instance ID in both hands and on the board. It refreshes power labels after `powers_changed` and ki state after `ki_changed`. No new bespoke visual effect or sound is introduced.

The existing “do not pulse the same card consecutively” behavior and per-move pulse reset remain unchanged.

## AI and compact simulation

The compact simulation must preserve each runtime card's mutable ki and four powers in both hands and on the board. Search clones must copy these values without aliasing arrays.

Legal move generation remains unchanged, but evaluation and attack resolution must read the modified runtime powers. Start-turn and end-turn triggers must run through the same rule engine during search so stacked Zi Xia Gong bonuses are visible to deeper plies.

## No-effect and invalid-context behavior

Having no eligible targets is `NO_EFFECT`, not `INVALID_CONTEXT`.

Normal state changes during earlier rules—such as a target card leaving a zone—simply change the cards selected when this action begins. These two actions do not declare permission to return `INVALID_CONTEXT`, so they never stop the remainder of their rule for an empty selection.

## Verification

Focused automated coverage must verify:

- ZiXiaGong1 grants one ki to allied sword cards in hand and on board, but not non-sword, enemy, or unrelated cards.
- ZiXiaGong2 grants ki before drawing and respects the hand-size cap.
- ZiXiaGong1–2 do not resolve if the ability is lost during summon reactions.
- ZiXiaGong3 modifies every hand card at each owner-turn start, including extra turns.
- ZiXiaGong4 modifies hand cards at start and the first two other allies in board order at end.
- Fewer than two end-turn targets produce a partial result or no effect without invalid context.
- Multiple sources stack in deterministic order.
- Ownership-relative targeting and default loss-on-flip behavior remain correct.
- Runtime power arrays are copied safely in compact simulation.
- Catalog validation accepts the four declarations and rejects malformed new action fields.

Manual playtesting must confirm that hand and board values visibly refresh, turn timing feels correct, and AI turns complete without simulation/live-state divergence.
