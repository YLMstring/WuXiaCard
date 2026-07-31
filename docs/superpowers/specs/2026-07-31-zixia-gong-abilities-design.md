# Zi Xia Gong 1–4 Ability Design

## Goal

Implement the four existing `ZiXiaGong1`–`ZiXiaGong4` catalog descriptions through a reusable “select cards, then do actions for each” primitive. The effects must work identically in the live duel and compact AI simulation, including permanent runtime ki and power changes.

## Catalog declarations

Add these catalog constants:

```gdscript
const TRIGGER_START_OWNER_TURN: StringName = &"start_owner_turn"

const CARD_ZONE_HAND: StringName = &"hand"
const CARD_ZONE_BOARD: StringName = &"board"

const ACTION_FOR_EACH_SELECTED_CARD: StringName = &"for_each_selected_card"
const ACTION_ADD_POWERS: StringName = &"add_powers"

const CONDITION_SELECTED_CARD_IS_ALLY: StringName = &"selected_card_is_ally"
const CONDITION_SELECTED_CARD_WEAPON_IS: StringName = &"selected_card_weapon_is"
const CONDITION_SELECTED_CARD_IS_NOT_SOURCE: StringName = &"selected_card_is_not_source"
```

`ACTION_FOR_EACH_SELECTED_CARD` contains:

- `selector`: required selector dictionary.
- `actions`: required non-empty array of ordinary action declarations.

The selector contains:

- `zones`: required non-empty array containing `CARD_ZONE_HAND`, `CARD_ZONE_BOARD`, or both.
- `conditions`: required array of selected-card conditions.
- `limit`: optional positive integer. Initial selection stops after this many matching cards.

Selectors consider both players' cards in the declared zones. Ownership and other restrictions are expressed through conditions rather than dedicated selector fields. For a hand zone, the source owner's hand is visited in slot order before the other player's hand. Board cards are visited in established board-cell order `0` through `8`. If both zones are declared, zones are visited in declaration order.

The selector takes an ordered snapshot of matching runtime card instance IDs when the wrapper begins. Each selected card resolves all nested actions before the next selected card begins. Immediately before a card's nested actions, only the selector's conditions are evaluated again. The card is skipped as `NO_EFFECT` if one or more conditions are no longer met. Movement or a zone change does not itself invalidate the snapshot or cause a skip unless an explicit condition tests that fact.

Within nested actions, the selected card becomes the current action subject. The original ability source remains separately available as the source card. Outside a selection wrapper, the ability source remains the current action subject. This lets the existing `ACTION_GAIN_KI` modify selected cards without changing its existing declarations.

`ACTION_ADD_POWERS` adds its required positive `amount` to all four powers of the current action subject. The modification is permanent for that runtime card instance.

The catalog validator must recursively validate nested actions. It must reject unknown or empty zone arrays, unknown selector conditions, non-positive limits, malformed condition fields, empty nested action arrays, and invalid recursive action declarations.

## Card rules

### ZiXiaGong1

On `TRIGGER_CARD_AFTER_SUMMONED`, if the trigger card is self, select cards from hand and board that satisfy `CONDITION_SELECTED_CARD_IS_ALLY` and `CONDITION_SELECTED_CARD_WEAPON_IS` with `weapon: "剑法"`. For each selected card, run `ACTION_GAIN_KI` with `amount: 1`.

### ZiXiaGong2

On `TRIGGER_CARD_AFTER_SUMMONED`, if the trigger card is self:

1. Use the same selected-card wrapper as ZiXiaGong1 to grant one ki to every allied `剑法` card in hand and on the board.
2. Draw one card.

The actions resolve in that order. The existing maximum-hand-size draw rule remains unchanged.

### ZiXiaGong3

At `TRIGGER_START_OWNER_TURN`, when the turn owner is self, select allied hand cards and run `ACTION_ADD_POWERS` with `amount: 1` for each.

### ZiXiaGong4

ZiXiaGong4 has both of these triggers:

- At `TRIGGER_START_OWNER_TURN`, when the turn owner is self, select allied hand cards and run `ACTION_ADD_POWERS` with `amount: 1` for each.
- At `TRIGGER_END_OWNER_TURN`, when the turn owner is self, select board cards satisfying `CONDITION_SELECTED_CARD_IS_ALLY` and `CONDITION_SELECTED_CARD_IS_NOT_SOURCE`, with `limit: 2`, then run `ACTION_ADD_POWERS` with `amount: 1` for each.

“First” uses board-cell order `0` through `8`. ZiXiaGong4 excludes itself. If only one valid other ally exists, that card is modified; if none exist, the action has no effect.

None of these abilities declares `retained_on_flip`, so the existing default applies: the ability is permanently lost when its ownership is flipped.

## Trigger timing

`TRIGGER_CARD_AFTER_SUMMONED` remains after summon reactions such as CangSongYingKe's immediate attack. Therefore ZiXiaGong1 or ZiXiaGong2 resolves only if its ability still exists when the after-summon trigger is revalidated. If it was removed, exiled, or flipped and lost the ability during earlier reactions, it does not grant ki or draw.

`TRIGGER_START_OWNER_TURN` is dispatched after the next active player has been chosen and before that player may perform an action. It also occurs when an extra turn begins. Start-turn rules are resolved with the same deterministic board-order discovery and sequential trigger resolution used by existing passive rules.

End-turn ZiXiaGong4 effects resolve within the existing end-owner-turn trigger phase, before the active player changes.

Multiple valid Zi Xia Gong sources resolve independently and stack. Their rule groups resolve sequentially in established board order.

## Runtime state and transition events

Ki and powers are modified on runtime card dictionaries, never on immutable catalog definitions. Every action execution context carries both the immutable ability-source identity and a current action-subject identity. A selection wrapper changes only the subject for its nested actions.

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

Having no eligible selected cards is `NO_EFFECT`, not `INVALID_CONTEXT`.

After the initial snapshot, moving a selected card—including moving it to another zone—does not by itself remove it from the wrapper. Before its turn, its selector conditions are re-evaluated against current state. It is skipped, and only skipped, when one or more of those conditions are no longer met. A skipped card contributes `NO_EFFECT` and does not stop later selected cards or later outer actions.

If the runtime card instance no longer exists, its conditions cannot all be met and it is skipped as `NO_EFFECT`. The wrapper and `ACTION_ADD_POWERS` do not declare permission to return `INVALID_CONTEXT`.

## Verification

Focused automated coverage must verify:

- Catalog validation accepts valid nested wrappers and rejects malformed selectors, selected-card conditions, and nested actions.
- Selection snapshots cards in declared zone order and resolves every nested action for one card before advancing.
- Moving a selected card does not skip it while its conditions remain true.
- A selected card is skipped only when at least one declared selector condition becomes false.
- ZiXiaGong1 grants one ki to allied sword cards in hand and on board, but not non-sword, enemy, or unrelated cards.
- ZiXiaGong2 grants ki before drawing and respects the hand-size cap.
- ZiXiaGong1–2 do not resolve if the ability is lost during summon reactions.
- ZiXiaGong3 modifies every hand card at each owner-turn start, including extra turns.
- ZiXiaGong4 modifies hand cards at start and the first two other allies in board order at end.
- Fewer than two end-turn targets produce a partial result or no effect without invalid context.
- Multiple sources stack in deterministic order.
- Ownership-relative targeting and default loss-on-flip behavior remain correct.
- Runtime power arrays are copied safely in compact simulation.
- Catalog validation accepts the four Zi Xia Gong declarations.

Manual playtesting must confirm that hand and board values visibly refresh, turn timing feels correct, and AI turns complete without simulation/live-state divergence.
