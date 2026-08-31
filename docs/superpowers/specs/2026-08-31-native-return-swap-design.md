# Native Return-to-Hand and Adjacent-Swap Slice

Date: 2026-08-31

## Status and Goal

This document defines the next test-only `DuelNativeCompactKernel` slice. The
authoritative rules remain `DuelSimulator`, and production search must not call
the native kernel yet.

The slice adds the two generic actions responsible for eleven currently
rejected legal root plays in the fourteen real Quick openings:

- `ACTION_RETURN_CARD_TO_HAND` for a board card returning as a fresh catalog
  instance;
- `ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE` for an adjacent two-card swap.

The implementation must remain card-agnostic, preserve exact runtime identity
semantics, return no partial output when an unsupported reached branch is
encountered, and maintain full state/event parity with `DuelSimulator`.

Discard-pile same-instance returns, ordinary discard transactions, arbitrary
movement actions, summons, and search integration are outside this slice.

## Why Fresh-Card Metadata Crosses the Root Boundary

An ordinary return from the board does not move the current runtime card into
the hand. `DuelSimulator` destroys that board instance and calls
`CardCatalog.create_instance()` to create a new instance with catalog-default
powers, starting ki, and normalized innate abilities. Copying the current
runtime card would be incorrect after power changes, ownership flips, ability
loss, suppression, or dynamic grants. Calling back into GDScript from every
native node would defeat the coarse native boundary.

`DuelCompactState` will therefore expose an immutable fresh-card prototype
table for every distinct card ID present in the captured root state. A return
can only copy an ID belonging to an existing target, so this finite table is
sufficient for this slice. Each prototype records:

- the immutable card-template pool index;
- four catalog-default powers;
- catalog starting ki;
- the normalized innate active-ability-set pool index;
- the card ID needed for lookup and generated-instance naming.

Prototype capture uses `CardCatalog.create_instance()` once at the GDScript
root boundary, interns the same immutable template and ability pools already
used by compact state, and strips the placeholder instance ID, owner, reveal
audience, and hand slot. Compact copies share the table. The native output
payload carries it unchanged so a restored `DuelCompactState` remains a valid
root for another native call. It does not affect `DuelState.restore()` because
it is rule metadata rather than live duel state.

The metadata is an additive format-1 field. Old payloads remain restorable and
can execute branches that do not require a fresh prototype. A return action
whose target ID has no prototype is unsupported, not approximated.

## Compiled Declarations

### Return to hand

The compiler accepts this generic declaration shape:

```gdscript
{
    "type": ACTION_RETURN_CARD_TO_HAND,
    "card": CARD_REF_SELECTED_CARD,
    "recipient": OWNER_CARD_ORIGINAL,
}
```

`card` may use an already supported exact card reference. `recipient` supports
`OWNER_CARD_CURRENT`, `OWNER_CARD_ORIGINAL`, and `OWNER_ABILITY_SOURCE` through
typed owner opcodes. `preserve_instance` must be absent or false. A declaration
with `preserve_instance = true`, unknown fields, or an unsupported owner/card
reference remains unsupported.

The selected-card wrapper continues to snapshot exact instances, then
revalidates its declared selector conditions immediately before each return.
An invalidated target produces `NO_EFFECT` and does not refill the original
selection.

### Swap with the ability source

The compiler accepts:

```gdscript
{"type": ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE}
```

plus the existing generic `on_invalid_context` field. Inside
`ACTION_FOR_EACH_SELECTED_CARD`, the action subject is the selected card and
the original source remains the ability source. Both exact instances must still
be on the board, be different cards, retain their snapshotted owners, and be
orthogonally adjacent when the action resolves.

## Return-to-Hand Resolution

For a valid board subject:

1. Resolve the recipient relative to the action context and subject snapshot.
2. If the recipient already has five cards, run the existing external exile
   lifecycle on the old board instance with reason `return_to_full_hand`.
   `CARD_BEFORE_EXILED` and `CARD_AFTER_EXILED` must retain their ordinary
   ordering and conservative unsupported-branch behavior.
3. Otherwise, compute the first generated ID matching
   `generated_<card_id>_<serial>` while the old target still exists, exactly as
   the oracle does.
4. Remove the old instance from the board without exile/discard events.
5. Append a new runtime card from the fresh prototype. Set the new original
   owner to the recipient, reset powers/ki/abilities to catalog defaults, clear
   suppression, and assign the recipient's leftmost empty physical hand slot.
6. Start the reveal audience as `[recipient]`, then make this effect-driven hand
   addition public to the opponent. Preserve the observable audience order:
   player return is `[1, 2]`, opponent return is `[2, 1]`.
7. Emit `card_returned_to_hand` with the old and new instance IDs, old board
   target cell, new logical hand index, physical hand slot, source identity,
   owner, card ID, and the complete post-reveal fresh card snapshot. Emit
   `card_revealed` immediately afterward when the opponent was newly added.

The old compact card index becomes an internal tombstone: it is absent from the
board and every zone, so `locate_card()` cannot find it. It must not be reused
within the branch because later selector snapshots may still carry that stable
index and must observe the old exact instance as gone. Generated-ID scans and
future semantic state keys consider only located live cards. Boundary restore
already ignores compact card records not referenced by a board cell or zone.

Difficulty-eight hand-size reactions remain protected by the existing native
support gate; this slice does not silently skip them.

## Adjacent-Swap Resolution

The swap mirrors `_swap_board_cards()` and is not a direct exchange of two
indices:

1. Re-resolve the ability source and action subject by stable card index,
   instance identity, owner, board presence, and adjacency.
2. Dispatch `CARD_BEFORE_MOVED` for the ability source moving into the subject's
   cell. Revalidate both cards afterward.
3. Temporarily reserve the subject, move the ability source, emit its
   `card_moved`, and dispatch its `CARD_AFTER_MOVED`.
4. Dispatch `CARD_BEFORE_MOVED` for the subject moving into the source's old
   cell. Revalidate again, move it, emit its `card_moved`, and dispatch its
   `CARD_AFTER_MOVED`.
5. Leave the ability source in the subject's old cell and return that cell as
   the action source cell. The surrounding summon transition then begins the
   source's standard attack from its new position.

Movement event contexts expose the moving card as the trigger card, its owner,
the old source cell, the requested target cell, and the after-move previous
cell. The slice adds typed equivalents of the simple oracle conditions needed
to identify the moving card as self or ally. Existing generic power changes may
therefore affect a moving card before mutation. Any reached movement listener
containing a still-unsupported condition or action rejects the entire private
native transition with no returned payload/events/captures/exiles.

The native implementation may use temporary reservations internally, but its
observable state and ordered events must match the oracle. If either movement
leg becomes invalid, the board reservation is restored according to oracle
semantics; event-triggered state changes that the oracle retains are retained
inside the private branch. If matching those semantics is not possible for a
reached listener, the branch is unsupported rather than partially applied.

## Testing

Focused synthetic parity fixtures will cover:

- a board card returned to its original owner as a new instance;
- catalog-default powers, starting ki, and innate abilities after returning a
  mutated runtime target;
- generated-ID collision scanning while the old instance is still present;
- leftmost physical hand-slot assignment and append-only logical hand order;
- complete `card_returned_to_hand` then `card_revealed` event payloads;
- multiple snapshotted adjacent targets returning sequentially without refill;
- a target removed or moved before its turn becoming `NO_EFFECT`;
- a full recipient hand using ordinary external exile timing;
- absence of a required fresh prototype causing an atomic unsupported result;
- adjacent source/subject swap with two ordered movement lifecycles;
- before-move power changes that remove or invalidate a mover;
- an unsupported reached movement listener causing an atomic rejection;
- the summon source's standard attack originating from its post-swap cell.

The real Quick coverage report must still enumerate the same fourteen unique
openings and 490 legal root plays. The intended result is support for up to the
five `NianhuaWeiXiao4` return branches and six `KuiHua3`/`TaiShan18Pan2` swap
branches, raising coverage from `341/490` toward `352/490`. Exact coverage may
be lower if a newly reached downstream listener is correctly rejected. Every
supported transition must have exact state, state-version, capture, exile, and
event parity, with zero mismatches and zero partial unsupported results.

After the focused native probe passes, run the canonical full suite:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
```

## Production Boundary and Follow-Up

This slice does not authorize production integration. `DuelSimulator` remains
the only authoritative path for humans, testing mode, greedy fallback, and deep
AI. The native kernel remains an oracle-checked experiment until legal-action
generation, state keys, evaluation, search, Android packaging, and materially
broader declaration coverage are proven in one native tree.

The next coverage decision after this slice will be based on the new per-card
rejection report. The discarded-card same-instance return path belongs with a
future discard transaction slice, not this one.
