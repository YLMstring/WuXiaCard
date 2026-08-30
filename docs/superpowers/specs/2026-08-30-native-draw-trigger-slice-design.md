# Native Self-Draw Trigger Slice Design

Date: 2026-08-30

## Objective

Extend the opt-in native compact-state prototype from ability-free play to the
first catalog-declared ability path. The slice will resolve a normalized card
whose only relevant rule is:

1. event: `TRIGGER_CARD_AFTER_SUMMONED`;
2. condition: exactly one `CONDITION_TRIGGER_CARD_IS_SELF`;
3. action: exactly one unfiltered `ACTION_DRAW_CARDS` with a positive constant
   amount.

This shape covers the complete entry ability of `TuNaShu1`, `TuNaShu2`, and
`TuNaShu3` without adding any card-ID branch. `DuelSimulator` remains the
oracle and production continues to ignore the extension.

## Chosen Approach

Compile immutable declarations once when the compact root is loaded. Do not
interpret nested Godot Dictionaries at every transition.

Each compact active-ability set receives a native summary containing:

- whether its full declaration shape was understood;
- the event indexed by each trigger;
- a supported self-after-summon draw instruction and constant amount, when
  present;
- conservative flags for other events, modifiers, or activations that may
  affect the requested transition.

The compiler is generic: it recognizes declaration constants and structure,
not catalog card IDs, names, glyphs, tiers, or sects. An unsupported declaration
is retained as an opaque capability flag so the transition can reject it when
it becomes relevant.

Directly interpreting Dictionaries was rejected because it would preserve
Variant traversal in the per-node hot path. Porting the full GDScript executor
was also rejected because it would create a large second rules engine before a
small declaration compiler and parity boundary were proven.

## Supported Transition Flow

The public test-only transition entry point becomes `apply_play_transition`.
The previous ability-free cases remain supported through the same method.

For a supported draw-trigger play, native resolution follows the authoritative
order:

1. remove the exact logical hand instance and erase only its physical hand-slot
   field;
2. place that same instance in the selected empty board cell;
3. emit `card_placed`;
4. pass the before-summon and summoned event boundaries only when no rule can
   respond to them;
5. discover after-summon rules in board cell order;
6. for the played card's matching self rule, emit `ability_triggered` and draw
   cards sequentially;
7. for each successful draw, remove the selected deck instance, assign the
   current leftmost empty physical slot, append it to logical hand order, and
   emit the exact `card_drawn` payload including the reconstructed runtime card;
8. resolve standard attacks and the existing turn/terminal flow;
9. return a complete compact payload plus capture, exile, and event arrays.

The draw amount is capped naturally by five occupied physical/logical hand
slots, matching `DuelAbilityExecutor`. A full hand therefore produces
`ability_triggered` but no `card_drawn` event. Deck order and instance identity
are preserved.

## Conservative Rejection Rules

The native method returns `supported = false` before committing a result when
exact semantics are not covered. The first draw slice rejects:

- a matching declaration whose trigger, condition list, action list, amount,
  or optional weapon filter differs from the supported shape;
- a draw that would reach an empty deck and require creation of a fresh
  `TaiZuChangQuan` instance;
- any future-draw reveal audience that would emit `card_revealed`;
- difficulty 8 or 9 hand rules;
- any board rule that can respond to `CARD_AFTER_DRAWN` when at least one card
  would actually be drawn;
- any relevant before-summon, summoned, after-summon, attack, flip, end-turn,
  start-turn, or before-duel-end rule whose semantics are not compiled;
- modifiers that can affect target selection, power comparison, attack range,
  attack permission, or terminal legal-action checks;
- a standard attack that would need to flip an ability-bearing target until
  native retained/deferred ability removal is implemented;
- temporary suppression, queued effects, pending choices, extra plays,
  partially resolved turn ends, pending hand-play suppression, and special
  negative powers, as in the first slice.

Abilities in hand, deck, discard, or removed zones are dormant under the game
rule that card effects do not trigger from hand unless explicitly handled.
They do not make a play unsupported merely by existing. A board ability makes
the play unsupported only when its indexed event/modifier can affect this
specific transition. When that relevance cannot be proven false cheaply, the
gate rejects conservatively.

`valid = false, supported = true` remains reserved for an understood but
illegal hand index, instance ID, or target cell. Unsupported semantics never
masquerade as an illegal action and never silently become no-ops.

## Data Representation

No new per-branch Godot Dictionary is introduced for declarations. Compiled
rules are immutable metadata shared by native branches. Mutable draw state uses
the existing compact arrays:

- owner deck and hand zone card-index vectors;
- per-card physical hand slots and runtime flags;
- template and mutable fields used to reconstruct the `card_drawn.card` event;
- side payload fields, which remain boundary-only until later native packing.

The compact GDScript loader remains the one-time result bridge. Search must not
restore `DuelState` per child.

## Verification

The opt-in native probe will add exact comparisons for:

- `TuNaShu1`, `TuNaShu2`, and `TuNaShu3` with sufficient ordered decks;
- both owners drawing;
- a partially occupied physical hand with a gap, proving leftmost-slot use;
- hand-cap truncation;
- ability-trigger and card-drawn event ordering before standard attacks;
- explicit rejection of empty-deck fallback, a draw listener, a filtered draw,
  and another unsupported after-summon action;
- unchanged ability-free transition fixtures.

Every accepted case must match `DuelSimulator` in canonical state key,
`state_version`, captures, exiles, and the complete event array. The native
extension must build successfully, the focused probe must pass, and the full
repository suite must pass before the slice is reported complete.

The probe will separately measure the covered draw transition against the same
authoritative GDScript action loop. The result is diagnostic only. It will not
enable production search or justify a production speed claim until native state
keys, legal actions, evaluation, tree traversal, generated-card fallback, and
the broader declaration executor are present.

## Explicit Non-Goals

- no production or controller integration;
- no named-card native logic;
- no filtered draw, empty-deck generated card, reveal, or draw-reaction chain;
- no selector, power-change, discard, exile, movement, summon, activation, or
  ki primitive in this slice;
- no Windows release or Android packaging decision;
- no claim that `TuNaShu` makes a complete real Quick opening native-compatible,
  because opening Bagua and other declarations remain outside this slice.
