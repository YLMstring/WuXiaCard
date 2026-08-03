# LaiHeQinQuan1–5 Ability Design

Date: 2026-08-03

## Goal

Implement the five catalog descriptions for `LaiHeQinQuan1` through
`LaiHeQinQuan5` through reusable, card-agnostic simulator primitives. The
feature adds duel-local information revelation, persistent future-draw
revelation, temporary flip prevention, and a granted defender-side power
modifier. Human play, testing mode, replay, greedy fallback, and deep AI must
all use the same simulator state and rules.

## Approved Gameplay Semantics

- For `LaiHeQinQuan4` and `LaiHeQinQuan5`, “曾经出过的牌” means card glyphs
  remembered from previous duels against the current enemy. It does not include
  a glyph first seen earlier in the current duel.
- Once an exact card instance is revealed to an owner, it remains revealed to
  that owner for the rest of the duel.
- `LaiHeQinQuan3` permanently enables revelation of later cards drawn into the
  affected enemy hand. This continues even if the source flips, loses its
  ability, moves, or leaves the board.
- The protection on `LaiHeQinQuan2`, `LaiHeQinQuan3`, and `LaiHeQinQuan5`
  prevents every attempted flip of that exact source until the protection
  expires. A prevented flip does not consume the protection.
- Protection expires after any card that was enemy-owned relative to the
  protected source actually changes ownership, regardless of which card or
  effect caused the flip. It also expires at the start of the protected
  source’s owner turn.
- An attempted or prevented flip is not an actual flip and therefore cannot
  satisfy the enemy-flipped expiration condition.
- The weakness granted by `LaiHeQinQuan4` and `LaiHeQinQuan5` affects only the
  card’s powers when that card is the prospective attack target. Its displayed
  powers and the powers it uses while attacking remain unchanged.
- Granted weakness belongs to the affected card. It remains if the granting
  source flips, moves, or leaves play, but it is lost when the affected card
  flips because it is a normal non-retained ability.

## Chosen Architecture

Use explicit duel state and generic catalog primitives. Do not branch on a
LaiHe card ID in the simulator, controller, AI, targeting, or rules code. Do not
introduce a universal duration/status engine as part of this feature.

### Runtime Revelation State

Every runtime card dictionary has a `revealed_to_owner_ids` array. It contains
the owners who have gameplay knowledge of that exact instance. Revelation is
idempotent: adding an already-present owner is a `NO_EFFECT`. The field travels
with the card across hand, board, movement, ownership changes, and any future
zone changes. Catalog-created cards initialize it with their starting owner;
fixture normalization supplies the same default when the field is absent.

Testing-mode visibility and AI perfect information are presentation/search
privileges only. They do not mutate `revealed_to_owner_ids`, emit reveal events,
or satisfy reveal-based trigger conditions.

`DuelState` gains:

- `remembered_glyphs_by_owner`: remembered enemy glyph snapshots keyed by the
  observing owner;
- `future_draw_reveal_audiences`: observers who permanently reveal cards newly
  entering each hand through a draw.

Both fields are deeply duplicated and included in `DuelStateKey`. The replay
record already snapshots and duplicates complete duel states, so the new data
must be preserved by that path as well.

When production creates a duel, `MainFlowController` passes the profile’s
current remembered enemy glyphs to `DuelController`. The controller copies
them into the player observer’s state entry before recording the replay’s
initial state. New enemy glyphs saved while that duel is underway do not alter
the current duel snapshot; they become available on the next duel against that
enemy.

### Catalog Vocabulary

Add these stable identifiers and schema rules:

- `ACTION_REVEAL_HAND_CARDS`
  - requires `recipient`, relative to the action source;
  - requires `filter`, either `REVEAL_FILTER_ALL` or
    `REVEAL_FILTER_REMEMBERED`;
  - reveals matching current hand cards to the action source owner in logical
    hand order.
- `ACTION_ENABLE_FUTURE_DRAW_REVEAL`
  - requires `recipient`, relative to the action source;
  - permanently adds the source owner to the recipient hand’s future-draw
    reveal audiences.
- `CONDITION_TRIGGER_CARD_REVEALED_TO_SELF`
  - follows the exact trigger instance to its current board cell;
  - succeeds only if it is revealed to the ability source owner.
- `CONDITION_TRIGGER_CARD_WAS_ENEMY`
  - uses the pre-flip `trigger_owner_id` in a completed
    `CARD_AFTER_FLIPPED` context;
  - succeeds only when that prior owner opposed the ability source owner.
- `ACTION_GRANT_TRIGGER_CARD_ABILITY`
  - requires a schema-valid nested `ability` declaration;
  - follows the exact trigger instance on the board;
  - appends a passive ability, while an exact structurally identical ability
    already present makes the action an idempotent `NO_EFFECT`;
  - if a future declaration grants an activation, it uses the existing rule
    that dynamically granted activations replace all current activations while
    preserving passives.
- `ACTION_PREVENT_TRIGGER_FLIP`
  - is valid only during `CARD_BEFORE_FLIPPED` for the exact trigger instance;
  - adds a pure-data prevention request to the trigger resolution result.
- `ACTION_REMOVE_THIS_ABILITY`
  - removes the exact currently resolving ability by source instance, ability
    index, and structural snapshot;
  - emits the ordinary `ability_lost` transition;
  - stale or changed context returns `NO_EFFECT`.
- Ability declarations may contain a `modifiers` array and may be
  modifier-only. This feature adds `MODIFIER_DEFENDING_POWER_OVERRIDE`, which
  requires a positive integer `value`.

For conflicting defender-power overrides, applicable modifiers are evaluated
in active-ability order and the last applicable override wins. Identical
granted weakness abilities do not duplicate, so the current cards always have
one value of `1`.

### Flip Prevention Contract

Actions do not directly mutate a shared event dictionary. Instead, trigger
resolution accumulates typed prevention requests alongside its existing
events, captures, exiles, attacks, and extra-turn requests.

After all already-discovered `CARD_BEFORE_FLIPPED` groups resolve, the attack
and non-attack flip paths check whether a request matches the exact pending
target instance and intended new owner. If matched, the simulator emits one
`card_flip_prevented` transition, does not change ownership, does not remove
non-retained abilities, does not record a capture, and does not emit
`CARD_AFTER_FLIPPED`.

All before-flip reactions still resolve in normal row-major, ability-array,
and trigger-array order. Movement during the before-flip event continues to
follow the project’s committed-flip rule and does not invalidate prevention.
Removal or another non-movement invalidator may still make the pending flip a
no-op before the prevention check matters.

### Defender Power Query

`DuelRules.can_attack_target()` continues to use the attacker’s printed/runtime
power normally. For the target-facing side it asks a small generic helper for
the effective defending power. The helper starts with the target’s stored
power, then applies active `MODIFIER_DEFENDING_POWER_OVERRIDE` declarations in
order. No card ID is inspected. Because AI, reaction attacks, standard attacks,
and legality checks already call `can_attack_target()`, they automatically use
the same modifier.

## Catalog Declarations

The five cards use separate ability entries where an effect needs an independent
lifetime.

### LaiHeQinQuan1

One `TRIGGER_CARD_AFTER_SUMMONED` rule with
`CONDITION_TRIGGER_CARD_IS_SELF` performs
`ACTION_REVEAL_HAND_CARDS` for `RECIPIENT_OPPONENT` with
`REVEAL_FILTER_ALL`.

### LaiHeQinQuan2

It contains the LaiHeQinQuan1 reveal ability plus a separate protection
ability with three triggers:

1. `CARD_BEFORE_FLIPPED` + `CONDITION_TRIGGER_CARD_IS_SELF` performs
   `ACTION_PREVENT_TRIGGER_FLIP`.
2. `CARD_AFTER_FLIPPED` + `CONDITION_TRIGGER_CARD_WAS_ENEMY` performs
   `ACTION_REMOVE_THIS_ABILITY`.
3. `TRIGGER_START_OWNER_TURN` + `CONDITION_TURN_OWNER_IS_SELF` performs
   `ACTION_REMOVE_THIS_ABILITY`.

The protection ability omits `retained_on_flip`, like ordinary abilities.

### LaiHeQinQuan3

Its after-summon self rule performs, in order:

1. reveal the current opponent hand with `REVEAL_FILTER_ALL`;
2. enable future-draw revelation for that opponent hand.

It also contains the same separate protection ability as LaiHeQinQuan2.

### LaiHeQinQuan4

Its after-summon self rule reveals the current opponent hand with
`REVEAL_FILTER_REMEMBERED`.

A separate global `TRIGGER_CARD_SUMMONED` rule requires both
`CONDITION_TRIGGER_CARD_IS_ENEMY` and
`CONDITION_TRIGGER_CARD_REVEALED_TO_SELF`. It grants the trigger card this
non-retained modifier-only ability:

```gdscript
{
    "modifiers": [{
        "type": MODIFIER_DEFENDING_POWER_OVERRIDE,
        "value": 1,
    }],
}
```

The project’s existing row-major global trigger order remains authoritative;
this grant receives no special priority over other summon reactions.

### LaiHeQinQuan5

It contains LaiHeQinQuan4’s remembered-hand reveal and revealed-summon weakness
abilities plus the separate protection ability from LaiHeQinQuan2.

## Presentation

Every newly revealed exact instance emits `card_revealed` with source instance,
hand owner, observing owner, target instance, and logical hand index. Existing
ability-pulse presentation occurs before the reveal action. No separate reveal
VFX or sound is introduced in this feature.

For a normal human player, `DuelController` exposes an opponent hand card when
the player owner appears in its `revealed_to_owner_ids`. It remains enemy-red
and becomes inspectable. Player-owned hand cards remain visible as before.

A future draw first emits and presents `card_drawn`, then emits
`card_revealed` when an applicable permanent audience exists. This keeps the
fixed hand-slot draw flow intact while ensuring the resulting card is visible.

Granted weakness does not change displayed power labels and adds no badge. In
addition to the granting source’s automatic trigger pulse, the affected
`CardView` renders only its central artwork at 70% opacity while an active
`MODIFIER_DEFENDING_POWER_OVERRIDE` is present. The frame, ownership color,
powers, ki bead, and interaction remain fully opaque. Removing the final such
modifier, including through an ownership flip, restores the artwork to normal
opacity. Rebuilding views during replay or scene synchronization derives both
this fade and concealment from runtime card data, while replay itself preserves
the original opponent concealment rules.

## No-Effect and Identity Rules

- Empty hands, no remembered matches, already-revealed cards, an already-enabled
  future reveal, and an identical granted ability are safe `NO_EFFECT`s.
- Reveal and grant operations use stable instance IDs. Movement alone does not
  invalidate the exact trigger instance; removal from the required zone or a
  failed declared condition does.
- A full hand does not affect revelation. Future-draw revelation simply has no
  card to reveal when a draw action cannot add one.
- Multiple LaiHe sources resolve through normal global ordering. Repeated
  reveals and identical weakness grants remain idempotent.
- The protection source must still exist under the expected owner with the
  exact resolving ability for prevention or self-removal to apply.

## Verification

Add catalog tests for every new identifier, field, nested ability, modifier,
recipient/filter requirement, invalid context field, and all five production
declarations.

Add simulator tests covering:

- current-hand reveal and unchanged newly drawn cards for LaiHeQinQuan1;
- protection against attack and non-attack flips;
- no ownership change, capture, ability loss, or `CARD_AFTER_FLIPPED` after a
  prevented flip;
- shield persistence after prevented attempts;
- expiration after any actual enemy flip and at the next owner-turn start;
- current-hand plus permanent future-draw reveal for LaiHeQinQuan3, including
  after the source flips or leaves play;
- remembered-glyph filtering from the initial duel snapshot and exclusion of a
  glyph learned during the current duel;
- weakness only for trigger cards revealed to the source owner;
- defender power treated as 1 while display/runtime powers and offensive use
  stay unchanged;
- granted weakness surviving source loss and disappearing on affected-card
  flip;
- idempotent duplicate reveals and grants;
- state duplication, state-key differentiation, replay reconstruction, and AI
  legal action consistency.

Add controller/integration tests confirming that newly revealed opponent hand
views become face-up, stay red, and become inspectable; testing-mode-only
visibility does not satisfy gameplay reveal conditions; future draws reveal
after occupying their fixed slot; weakened cards fade only their central art to
70% opacity and restore it after losing the modifier; and replay presents the
same revelation sequence without leaking other concealed cards.

Run focused catalog, simulator, and integration suites, then the complete test
runner. Finally play the affected production path at the 540×960 portrait
reference viewport and inspect runtime diagnostics.

## Out of Scope

- A universal status-duration or modifier-priority engine.
- New reveal animations, sounds, weakness badges, or altered power labels.
- Updating persistent enemy memory during the already-running duel state.
- Any card-specific simulator, AI, targeting, or controller branch.
