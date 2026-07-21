# Ki and Activate Actions Design

## Goal

Add the first activated card ability: on its owner's turn, Jiang Wei or Sun Zan may spend 1 ki to move to an orthogonally adjacent empty board cell and perform the normal four-edge attack from the destination.

The feature establishes a general action and targeting foundation for future activated abilities that target empty, allied, or enemy board cells and hand slots. A turn contains exactly one complete action: play a card or activate a card, never both.

## Approved Rules

- Jiang Wei and Sun Zan each declare `starting_ki = 1` and one `move_and_attack` activate ability in `card_catalog.gd`.
- Every fresh instance, including side-deck copies, receives the catalog's starting ki.
- Ki is runtime card state independent from the card's effects.
- Every successful activate action costs exactly 1 ki. Invalid or cancelled actions spend nothing.
- A card may have at most one activate ability. Granting a new activate ability removes its old activate ability first; other passive, replacement, and triggered effects remain.
- The new activate ability omits retention metadata and therefore uses the existing default `retained_on_flip = false`.
- When the card is flipped, its activate ability is permanently lost, while its current ki is unchanged.
- The movement target must be an orthogonally adjacent empty board cell. Diagonal, occupied, wrapped, source, and nonadjacent cells are illegal.
- Repositioning is legal even when no enemy will be flipped or exiled.
- The same card instance moves; its original board cell becomes empty.
- After movement, the card compares its four powers from the destination in the existing top, right, bottom, left order.
- Existing flip-replacement effects on the moving card can modify those attack attempts. On-play effects never retrigger during movement.
- The complete activation ends the turn exactly once.

## Catalog and Runtime Schema

Add a known activate effect ID and a known target-rule ID:

```gdscript
const EFFECT_ACTIVATE_MOVE_AND_ATTACK := &"activate_move_and_attack"
const TARGET_ADJACENT_EMPTY_BOARD := &"adjacent_empty_board"
```

Jiang Wei and Sun Zan declare:

```gdscript
"starting_ki": 1,
"effects": [
	{
		"id": EFFECT_ACTIVATE_MOVE_AND_ATTACK,
		"activation": true,
		"target_rule": TARGET_ADJACENT_EMPTY_BOARD,
	},
]
```

`starting_ki` defaults to `0` for definitions that omit it and must be a nonnegative integer when present. Runtime instances copy it into mutable `ki`. Copying a card or `DuelState` deep-copies that value with all other card data.

Activate effects require `activation = true` and a known target rule. A catalog definition containing more than one activate effect is invalid. Runtime effect-granting code must use a replace helper that removes the current activate effect before installing a new one. This single-slot rule does not limit non-activate effects.

The global activate cost is 1 ki for this ruleset; it is not effect-specific catalog data. This preserves the approved rule that activating any ability costs 1 while keeping ki independent from the ability itself.

## Generalized Duel Action

Replace the placement-specific `DuelMove` contract with a generalized `DuelAction`. One object represents one complete decision and contains pure values:

- `action_type`: `play` or `activate`;
- `source_zone`: `hand` or `board`;
- `source_index`: logical hand index or board cell;
- `source_instance_id`: stable validation and presentation identity;
- `ability_id`: empty for play, explicit for activate;
- `target_kind`: initially `board_cell`, later also `hand_slot`;
- `target_index`: board cell or physical/logical target index as defined by the target kind.

Catalog target rules describe filters such as adjacent, empty, ally, or enemy. The action target describes the selected domain and index. This separation supports future ally-square and enemy-square effects without multiplying action classes.

`duplicate_action()` and equality compare every field. Existing search and controller code must stop depending on the old `Vector2i(hand_index, cell_index)` representation.

## Pure Targeting Layer

Add `DuelTargeting` as a scene-free module. Given a state, owner, source, and activate effect, it returns typed legal target descriptors in deterministic order and can validate a submitted target against the same rules.

The first target rule, `adjacent_empty_board`, uses the board's canonical top, right, bottom, left directions. It rejects row wrapping and includes every empty neighbor even when movement would produce no successful attack.

The controller never decides target legality. It converts UI nodes into a typed target and asks the simulator/targeting layer. AI and human actions therefore share exactly the same legal target set.

## Legal Actions and State Transition

`DuelSimulator.get_legal_actions_for_owner` returns both:

1. Every legal hand-card play to an empty board cell.
2. Every legal activation for board cards currently owned by that owner, with an active activate effect, at least 1 ki, and one or more targets generated by `DuelTargeting`.

`apply_action` validates the entire action before copying or mutating anything. A rejected action returns the original state, `valid = false`, and no events.

A successful play keeps the current behavior and event order.

A successful movement activation operates on a duplicated state:

1. Find and revalidate the source by board cell and instance ID.
2. Revalidate current ownership, active ability ID, at least 1 ki, and target legality.
3. Decrement the source card's ki by 1.
4. Emit `ability_activated` and `ki_changed` with source instance ID and resulting ki.
5. Clear the source board cell and place the same slot/card data at the destination.
6. Emit `card_moved` with source cell, target cell, owner, ability ID, and instance ID.
7. Query normal would-flip targets from the destination.
8. Resolve each attempt through the existing flip/exile resolver in top, right, bottom, left order.
9. Increment turn and state versions once and select the next owner.

No on-play resolver is called. Movement itself does not reconstruct the card, change original ownership, or reset effects or ki.

## Turn, Pass, Terminal, and AI Behavior

All turn-flow queries use legal actions rather than placement moves:

- A side with an empty hand can still act if it has a legal activation.
- A full board offers no movement target.
- The next owner is preferred when that owner has any legal play or activation.
- The current owner receives another turn only under the existing no-action fallback rule.
- A match is terminal only when neither owner has a legal action and no effect remains queued, or when the maximum-turn safeguard is reached.

Greedy AI evaluates both play and activate actions by applying them through the same simulator. It first maximizes immediate score difference. On equal score, it prefers a play over an activation to avoid spending scarce ki without immediate gain. Within one action type it uses boundary power at the destination, then stable source and target order for deterministic choices.

The future deep-search engine requires no special activate path: copied state contains board location, current ki, active ability, and all legal replies.

## Drag-and-Drop Presentation

Hand-card dragging continues to submit play actions. During the active owner's turn, a board card is draggable when it has an activate ability, enough ki, and at least one legal target.

Activation drag behavior:

1. Lift the source card and apply the approved gold source outline.
2. Highlight its legal activate targets in teal, visually distinct from ordinary placement targets.
3. Keep the logical card at its source until the simulator accepts the drop.
4. On an invalid or cancelled drop, return it to its source and play the existing invalid shake; spend no ki and keep the turn.
5. On a valid drop, lock input, play a short brush-like trail and soft movement whoosh, move the view to the target cell, update the ki bead, then present ordered flip/exile events.
6. Update ownership playability and turn status only after all presentation events finish.

Opponent AI and testing-mode manual opponent activations use the same event presenter. Turn text reads `Your turn · play a card or activate` when either action category is available.

## Ki Bead

Add a small numbered jade bead to the lower-right free corner of `CardView`, away from the four centered edge powers.

For a face-up card, display the bead when either:

- `ki > 0`; or
- the card still has an activate ability.

An activate card with `0` ki shows a dimmed `0`. A card with remaining ki but no activate ability still shows its resource. A card with `0` ki and no activate ability shows no bead. Face-down opponent hand cards never display ki because doing so could leak card identity or state.

The bead refreshes after configure, draw, movement cost, effect loss, ownership flip, and future ki or ability changes.

## Feedback Layers

- **Visual:** jade ki bead, source lift and gold outline, teal valid targets, brush-like movement trail, destination settle, then existing flip/exile animation.
- **Audio:** one restrained movement whoosh on a successful activation, followed by existing capture or removal sounds. Invalid drops add no new sound.
- **Mechanical:** the source cell opens, the destination becomes occupied by the same instance, 1 ki is consumed, and standard edge attacks resolve from the new position.

Presentation timings and movement-audio volume are exported controller tunables and can be zeroed in integration fast mode. They never enter simulator state.

## Scene and Component Sketch

```text
WuxiaCard/Duel
├── BoardCenter/BoardGrid                         existing; accepts play and activate targets
├── DragLayer                                     existing; hosts dragged hand or board card
├── MovementAudio (AudioStreamPlayer)             new; successful activation cue
└── transient movement-trail Control              new at runtime; presentation only

CardView
└── Overlay
    └── KiBadge (PanelContainer + Label)           new; corner resource display

scripts/duel_action.gd                             generalized decision value
scripts/duel_targeting.gd                          pure target generation/validation
scripts/duel_simulator.gd                          legal actions and transitions
scripts/duel_effects.gd                            activate-slot helpers and flip resolution
scripts/card_catalog.gd                            starting ki and ability declarations
scripts/duel_controller.gd                         input and event presentation
```

## Failure and Edge Handling

- Wrong-owner, missing-source, stale-instance, zero-ki, missing-ability, unknown-ability, unsupported-target, occupied, diagonal, wrapped, and nonadjacent actions fail without mutation.
- A source with ki but no activate ability cannot activate.
- A source with an activate ability but zero ki cannot begin an activation drag.
- Losing the ability on flip does not erase ki; flipping back does not restore the lost ability.
- Movement to a non-attacking position remains legal and consumes ki.
- Side-deck copies have independent ki and effect dictionaries.
- Search branch mutation cannot affect source or sibling states.
- If a future effect grants an activate ability, it replaces the old activate slot deterministically.
- Multiple activate abilities on one card are not supported by design and never require target-based UI disambiguation.

## Verification

Catalog tests verify:

- Jiang Wei and Sun Zan declare `starting_ki = 1` and `activate_move_and_attack`;
- other cards default to zero starting ki;
- main- and side-deck instances receive independent mutable ki;
- starting ki validation rejects negative and non-integer values;
- activate effects require a known target rule;
- more than one activate effect is rejected;
- replacing an activate effect preserves all non-activate effects.

Targeting and simulator tests verify:

- top/right/bottom/left adjacent targets without row wrapping;
- occupied, diagonal, distant, wrong-owner, missing-ability, and zero-ki rejection;
- legal no-capture repositioning;
- play and activate actions coexist in deterministic legal-action lists;
- invalid actions preserve exact state and ki;
- a successful action spends exactly 1 ki and moves the same instance;
- event order is activation, ki change, movement, then ordered flip/exile results;
- movement never triggers on-play draw effects;
- flip removes the activate ability while preserving ki permanently;
- state-copy isolation includes ki, effects, and moved board slots;
- legal activation affects pass, next-owner, and terminal decisions;
- greedy AI considers activations but conserves ki on equal-score play ties;
- deep-search-compatible action duplication and equality include every typed field.

Integration and playtesting verify:

- face-up ki bead visibility and all approved zero/ability combinations;
- face-down opponent cards leak no ki;
- player board-card drag, gold source, teal targets, invalid return, and valid movement;
- opponent AI and testing-mode opponent activation;
- movement trail, restrained whoosh, ki decrement, destination settle, and later capture/removal feedback;
- input remains locked through presentation and exactly one turn is consumed;
- existing hand placement, fixed hand slots, draw, concealment, exile, ability loss, scores, and match completion remain correct.

## Out of Scope

- Ki gain, transfer, theft, or regeneration effects.
- Granting or replacing activate abilities through a playable card effect.
- More than one activate ability on a card.
- Implementing ally-cell, enemy-cell, or hand-slot abilities themselves.
- Ability-choice UI or pending multi-step choices.
- Changes to deep-search budgets or evaluation beyond legal-action compatibility.
