# Adding Cards and Abilities

## Card Catalog Schema

Production card definitions live only in `scripts/card_catalog.gd`. Add each ID
to `ALL_CARD_IDS` and `_CARD_DEFINITIONS`.

Required fields:

```gdscript
&"example_id": {
    "id": &"example_id",
    "glyph": "一到七字",
    "picture": "res://pics/example.png",
    "sect": "",
    "tier": 1,
    "weapon": "",
    "description": "",
    "flavor": "",
    "powers": [4, 5, 6, 7], # top, right, bottom, left
    "abilities": [],
}
```

Optional:

```gdscript
"starting_ki": 1
```

A card that must enter one qualifying defeat offer per run may declare:

```gdscript
"guaranteed_defeat_reward": {
    "min_character_tier": 5,
    "requires_unlocked_effect_gate": EFFECT_GATE_SELF_CASTRATION,
}
```

The profile store requires the card to be locked, the character to meet the
minimum tier, and at least one unlocked card to declare the required
`effect_gate`. A successfully saved offer records the guaranteed card as shown
for that run, even when the player claims a different reward.

Catalog rules:

- `glyph` is the card name; the retired `name` field is forbidden.
- Glyph length is 1–7 characters.
- `picture` is a nonempty existing Godot resource path.
- `sect`, `weapon`, `description`, and `flavor` are Strings.
- `tier` is an integer at least 1.
- Exactly four integer powers are required.
- Starting ki is a nonnegative integer.
- Abilities have no ID.
- Multiple ability entries may declare `activation`; their array order is
  activation priority.
- Unknown events, conditions, actions, inputs, targets, fields, and policies are
  rejected.

`&"text"` is a Godot `StringName`, used for stable vocabulary identifiers.
Display text remains a normal String.

## Card Families and Progression Unlocks

Cards form an unlock family when both `glyph` and `sect` match. Whenever a card
is newly unlocked, every still-locked family member at a strictly lower tier
also unlocks. The requested card is a primary unlock and enters the library
top; inherited lower-tier cards follow catalog order and append at the occupied
library bottom.

Because catalog order controls inherited ordering, list related cards in their
intended stable order in `ALL_CARD_IDS`.

The selected sect is matched through the sect catalog's `glyph`. Crossing into
character tiers 2, 3, 4, or 5 unlocks all cards of that exact tier whose `sect`
matches the selected sect. Current tier boundaries are levels 2, 5, 8, and 11,
with tier 5 remaining the cap through level 15.

Unlocks occur only through explicit profile-store operations. Do not add family
expansion to profile validation or repair: loading an older valid save must not
silently grant cards or reorder its library.

## Instances and Runtime Abilities

`CardCatalog.create_instance()` copies definition data into a runtime
Dictionary, assigns `instance_id` and `original_owner`, initializes ki, and
creates `active_abilities`.

Abilities without `retained_on_flip` normalize to `false`. Add the flag only
for an unusual ability that survives an ownership flip.

Starting encounter hands are in `scripts/duel_decks.gd`. Each owner's side deck
is derived from that owner's main deck through `scripts/deck_rules.gd`. A
non-`江湖` main card contributes every catalog card of the same sect whose tier
does not exceed its own; overlapping contributions merge, and only the
highest-tier card for each `glyph` survives. Equal-tier ties keep the earlier
catalog entry. Player unlock ownership does not restrict this candidate pool.

Never reuse one runtime Dictionary for two physical copies; every copy needs a
unique `instance_id`. Enemy main decks may contain repeated IDs, but each
physical copy still receives a distinct runtime ID.

## Triggered Ability Shape

```gdscript
{
    "retained_on_flip": true,
    "triggers": [{
        "event": CARD_BE_ATTACKED,
        "conditions": [
            {"type": CONDITION_ATTACKER_CARD_IS_SELF},
        ],
        "actions": [
            {
                "type": ACTION_EXILE_CARD,
                "card": CARD_REF_TRIGGER_CARD,
            },
        ],
    }],
}
```

Conditions are ANDed in declaration order. Actions resolve in declaration
order. Global trigger sources resolve by row-major board cell, then ability
array order, then trigger array order.

Every accepted passive trigger automatically emits the generic card-pulse cue
before its actions. Do not declare presentation actions in the catalog for this.
Activate abilities intentionally do not pulse.

When several activate abilities accept the same dragged target, live input uses
the first legal activation in catalog order. AI actions retain an
`activation_index`, so search can evaluate every activation separately.
A dynamically granted activation still replaces all current activate abilities
while preserving passive abilities.

Every rule uses stable card instance and cell context. Stale or missing context
returns `NO_EFFECT` by default, so later actions continue. To stop only that
rule's remaining actions, opt in on the action:

```gdscript
{
    "type": ACTION_MOVE_SELF_TO_TARGET,
    "on_invalid_context": STOP_RULE,
}
```

## Current Examples

Generic ordered card selection:

```gdscript
{
    "type": ACTION_FOR_EACH_SELECTED_CARD,
    "selector": {
        "zones": [CARD_ZONE_HAND, CARD_ZONE_BOARD],
        "conditions": [
            {"type": CONDITION_SELECTED_CARD_IS_ALLY},
            {
                "type": CONDITION_SELECTED_CARD_WEAPON_IS,
                "weapon": "剑法",
            },
        ],
        "limit": 2,
    },
    "actions": [
        {"type": ACTION_GAIN_KI, "amount": 1},
    ],
}
```

Zones are visited in declaration order. The source owner's hand is visited
before the other hand; board order is `0..8`. Selection snapshots matching
instance IDs. Each card completes all nested actions before the next card.
Before resolution, only the declared selector conditions are checked again:
movement or a zone change remains valid unless a condition becomes false.
Inside the wrapper, the selected card is the action subject while the original
ability source remains available to source-relative conditions.

For physical rightmost hand selection, declare
`"order": SELECT_ORDER_HAND_RIGHT_TO_LEFT`. The order is applied within each
owner's fixed hand slots; do not rely on logical array insertion order.

Batch discard uses the selector directly:

```gdscript
{
    "type": ACTION_DISCARD_CARDS,
    "selector": {
        "zones": [CARD_ZONE_HAND],
        "conditions": [
            {"type": CONDITION_SELECTED_CARD_IS_ALLY},
        ],
        "limit": 2,
    },
}
```

The action snapshots exact instances, moves all selected cards to discard,
emits one `card_discarded` event per card with a shared `discard_batch_id`,
performs one final physical hand-slot shift, resolves each discarded card's
self-`CARD_AFTER_DISCARDED` chain in selection order, then emits one global
`TRIGGER_DISCARD_BATCH_FINISHED`. `ACTION_DISCARD_CARD` delegates to the same
transaction as a batch of one. A later `ACTION_IF` in the same action list can
test `CONDITION_LAST_DISCARD_BATCH_SIZE_AT_LEAST` with an `amount`; global
batch reactions can test `CONDITION_DISCARD_OWNER_IS_SELF`.

Actions that default to the current subject, such as `ACTION_DRAW_CARDS`, keep
that subject's owner/location snapshot for the duration of one action list.
This permits the concise sequence `ACTION_EXILE_SELF` followed by
`ACTION_DRAW_CARDS`: after removal, the draw still belongs to the subject's
pre-removal current owner. Add explicit recipient fields only to actions whose
rule intentionally differs from that default.

Signed power change with an explicit exact target:

```gdscript
{
    "type": ACTION_CHANGE_POWERS,
    "amount": -2,
    "card": CARD_REF_TRIGGER_CARD,
}
```

The supported dynamic form currently counts cards in one owner's hand:

```gdscript
{
    "type": ACTION_CHANGE_POWERS,
    "amount": {
        "type": VALUE_CARD_COUNT,
        "zone": CARD_ZONE_HAND,
        "owner": OWNER_ABILITY_SOURCE,
    },
    "card": CARD_REF_ABILITY_SOURCE,
}
```

The action accepts ability-source, selected-card, and trigger-card references.
Attack reaction contexts also expose `CARD_REF_ATTACKER_CARD`; it snapshots the
exact attacker and its initial board cell before reaction actions can remove or
move either participant.
Literal amounts must be nonzero signed integers. A dynamic count resolving to
zero is `NO_EFFECT`. Subtraction floors each side at zero; four zeros remove the
exact instance to its original owner's removed zone after emitting the power
event. Do not encode arithmetic or named-card behavior in the executor.

Conditional action blocks use a separate action-condition vocabulary:

```gdscript
{
    "type": ACTION_IF,
    "conditions": [{"type": CONDITION_SOURCE_OWNER_HAND_EMPTY}],
    "actions": [
        # Generic nested actions.
    ],
}
```

All conditions are checked once when `ACTION_IF` begins. If they pass, its
nested actions resolve in order without rechecking the condition between them.
`CONDITION_SOURCE_OWNER_HAND_EMPTY` reads the ability source's snapshotted
current owner, so it remains meaningful after that source has been removed.

Draw in the after-summoned window:

```gdscript
{
    "triggers": [{
        "event": TRIGGER_CARD_AFTER_SUMMONED,
        "conditions": [
            {"type": CONDITION_TRIGGER_CARD_IS_SELF},
        ],
        "actions": [
            {"type": ACTION_DRAW_CARDS, "amount": 2},
        ],
    }],
}
```

Filtered draw is exceptional and may add a nonempty weapon string:

```gdscript
{"type": ACTION_DRAW_CARDS, "amount": 2, "weapon": "掌法"}
```

It removes the first matching cards without disturbing skipped deck entries.
Unlike an ordinary empty-deck draw, a filtered draw with no match creates no
fallback card. Each successful card still resolves the normal per-card draw
events.

Summon reaction:

```gdscript
{
    "triggers": [{
        "event": TRIGGER_CARD_SUMMONED,
        "conditions": [
            {"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
            {"type": CONDITION_TRIGGER_CARD_IN_RANGE},
        ],
        "actions": [
            {"type": ACTION_ATTACK_TRIGGER_CARD},
        ],
    }],
}
```

Create a fresh catalog card in a hand:

```gdscript
{
    "type": ACTION_ADD_CARD_TO_HAND,
    "card_id": &"CangSongYingKe3",
    "recipient": RECIPIENT_SELF,
}
```

`recipient` is relative to the current action subject's owner and accepts
`RECIPIENT_SELF` or `RECIPIENT_OPPONENT`. The action does not draw from a deck.
It creates a fresh catalog instance with a deterministic unique runtime ID and
returns `NO_EFFECT` when the destination hand already contains five cards.

The same action can derive the catalog ID from an existing card-reference
snapshot instead of naming a fixed card:

```gdscript
{
    "type": ACTION_ADD_CARD_TO_HAND,
    "card": {
        "type": CARD_SPEC_FRESH_COPY,
        "of": CARD_REF_SELECTED_CARD,
    },
    "recipient": RECIPIENT_SELF,
}
```

Declare exactly one of `card_id` or `card`. A fresh-copy specification reads
only the referenced snapshot's `card_id`; it creates a new instance with the
catalog powers, starting ki, and complete abilities. It neither copies runtime
changes nor moves the referenced instance from its current zone.

Attack with the first three matching board cards, fully resolving each attack
before revalidating the next snapshot member:

```gdscript
{
    "type": ACTION_FOR_EACH_SELECTED_CARD,
    "selector": {
        "zones": [CARD_ZONE_BOARD],
        "conditions": [
            {"type": CONDITION_SELECTED_CARD_IS_ALLY},
            {
                "type": CONDITION_SELECTED_CARD_WEAPON_IS,
                "weapon": "剑法",
            },
        ],
        "limit": 3,
    },
    "actions": [
        {"type": ACTION_STANDARD_ATTACK_WITH_SELF},
    ],
}
```

Move-and-attack activation:

```gdscript
{
    "activation": {
        "input": ACTIVATION_DRAG_TO_TARGET,
        "target_rule": TARGET_ADJACENT_EMPTY_BOARD,
        "costs": [
            {"type": ACTION_SPEND_KI, "amount": 1},
        ],
        "actions": [
            {"type": ACTION_MOVE_SELF_TO_TARGET},
            {"type": ACTION_STANDARD_ATTACK_WITH_SELF},
        ],
    },
}
```

Swap-and-attack activation:

```gdscript
{
    "retained_on_flip": true,
    "activation": {
        "input": ACTIVATION_DRAG_TO_TARGET,
        "target_rule": TARGET_ADJACENT_ALLY_BOARD,
        "costs": [
            {"type": ACTION_SPEND_KI, "amount": 1},
        ],
        "actions": [
            {"type": ACTION_SWAP_SELF_WITH_TARGET},
            {"type": ACTION_STANDARD_ATTACK_WITH_SELF},
        ],
    },
}
```

Meng Huo:

```gdscript
{
    "triggers": [
        {
            "event": CARD_AFTER_FLIPPED,
            "conditions": [
                {"type": CONDITION_ATTACKER_CARD_IS_SELF},
            ],
            "actions": [
                {"type": ACTION_GAIN_KI, "amount": 1},
            ],
        },
        {
            "event": TRIGGER_END_OWNER_TURN,
            "conditions": [
                {"type": CONDITION_TURN_OWNER_IS_SELF},
                {"type": CONDITION_KI_AT_LEAST, "amount": 1},
            ],
            "actions": [
                {"type": ACTION_SPEND_ALL_KI},
                {"type": ACTION_GRANT_EXTRA_CARD_PLAY, "amount": 1},
            ],
        },
    ],
}
```

## Resolution Timing

`TRIGGER_START_OWNER_TURN` resolves after the simulator chooses the next active
owner and before that owner may act. Extra-card-play grants remain inside the
same owner turn, permit hand plays only, and do not repeat either owner-turn
boundary. `TRIGGER_END_OWNER_TURN` resolves once before any end-trigger grant.

Normal summon:

1. place the exact instance logically;
2. resolve that instance's `TRIGGER_CARD_BEFORE_SUMMONED` rules;
3. emit `card_placed`, then resolve global `TRIGGER_CARD_SUMMONED`;
4. if the exact summoned instance remains on the board, discover and resolve
   all matching `TRIGGER_CARD_AFTER_SUMMONED` rules across the board in
   row-major source order; use `CONDITION_TRIGGER_CARD_IS_SELF` for ordinary
   entrance abilities that should only respond to the summoned card itself;
5. standard attack only if it still belongs to the summoning owner;
6. consume or grant any extra-card-play allowance; while a legal allowance
   remains, keep the same owner active without resolving turn boundaries;
7. resolve end-turn rules once, service a possible coalesced end-trigger grant,
   then restore turn-scoped suppressions and finish the owner turn.

Every attack:

1. record exact attacker and target context;
2. resolve global `CARD_BE_ATTACKED`;
3. relocate both exact instances and revalidate the normal attack, including
   range and power;
4. if valid, resolve global `CARD_BEFORE_FLIPPED`;
5. if an explicit prevention request matches, emit and globally resolve
   `CARD_FLIP_PREVENTED`, then end this flip without after-flip timing;
6. relocate both exact instances again, but do not recheck attack range;
7. cancel only if a non-movement invalidator now prevents the committed flip;
8. flip the exact target instance in its current cell;
9. resolve `CARD_AFTER_FLIPPED`.

If step 3 fails, neither flip trigger is emitted. Once
`CARD_BEFORE_FLIPPED` begins, movement by itself never cancels the committed
flip. Removal, source ownership change, or the target already belonging to the
intended owner still prevents it. Non-attack flips use the same before/after
events and follow the exact target instance across movement.

Movement is not a summon. Exile is not a flip.

Discard is also not exile. `ACTION_DISCARD_CARD` moves an exact hand reference
to `CARD_ZONE_DISCARD`; `ACTION_RETURN_CARD_TO_HAND` with
`preserve_instance = true` can return that exact dictionary and `instance_id`
without recreating the catalog card. After the discard and physical hand shift
events, `CARD_AFTER_DISCARDED` discovers only the exact discarded card's own
rules in its discard pile. Other off-board cards and board sources are outside
this self-reaction boundary.

`ACTION_TRANSFORM_CARD` replaces an exact runtime card with a fresh catalog
snapshot for its declared `card_id`, while preserving `instance_id`,
`original_owner`, zone ownership, hand slot when applicable, and reveal
audiences. It emits `card_transformed`. A following preserved-instance return
therefore moves the transformed dictionary rather than reconstructing it. If
that destination hand is full, the exact discard instance uses normal external
exile instead.

Hand arrays remain compact logical storage for action indices, but visible and
automatic left-to-right order comes from each runtime card's
`hand_slot_index`. Draws, created cards, and returns enter the leftmost empty
physical slot. A successful discard emits `card_discarded`, then one optional
`hand_cards_shifted` event whose `moves` entries contain `instance_id`,
`from_slot`, and `to_slot`; every card to the discarded card's right moves left
exactly one slot and the controller animates the batch simultaneously. No other
hand departure repacks slots.

Every actual move first resolves the catalog boundary `CARD_BEFORE_MOVED` for
the exact moving instance. The requested move then rechecks source identity and
its destination. Both legs of every swap use this boundary, and every swap is
orthogonally adjacent at resolution. A failed swap returns `NO_EFFECT`; a rule
that must stop afterward declares `on_invalid_context = STOP_RULE`. A
successful mutation then resolves `CARD_AFTER_MOVED` for the exact moving
instance.

`ACTION_TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES` stores each removed ability
on that exact card until the current turn ends. Retained abilities are never
removed. A later grant is immediately active; a later suppression may remove it
in a new batch. Flipping the card clears every stored non-retained batch, so
those abilities never return.

Ability-created summons use generic `ACTION_SUMMON_CARD`. Its `card` spec is
either an exact reference such as `CARD_REF_SELECTED_CARD`, or a
`CARD_SPEC_FRESH_COPY` of another card reference, or the declared owner's
current `CARD_SPEC_TOP_DISCARD`. Its `cell` spec may refer to an exact card's
initial cell, the lowest-index adjacent empty cell, the first empty cell
adjacent to an enemy, or an adjacent-first/any-empty fallback. Exact hand,
discard, and removed instances leave that zone; fresh specifications create a
unique catalog instance. A discard instance keeps its point, ki,
`instance_id`, and `original_owner`, but its board owner becomes the summoning
ability's owner. Every successful summon resolves both summon trigger phases
and a standard attack. Sequential summon actions finish each complete summon
chain before attempting the next action, so a later top-discard specification
reads the live pile after all earlier chains; an occupied destination makes
only that later summon return `NO_EFFECT`.

`ACTION_RETURN_CARD_TO_HAND` accepts an exact card reference and owner-relative
recipient, including `OWNER_CARD_ORIGINAL`. It follows the instance across
board movement and creates a fresh catalog hand instance for that recipient;
a full hand uses normal external exile instead. With `preserve_instance =
true`, it instead moves the exact discard dictionary and uses the same
full-hand exile fallback. Selected-card wrappers still revalidate their
declared conditions immediately before the action. `ACTION_EXILE_SELF` removes
only an on-board source and marks its event for fade presentation.

`TRIGGER_BEFORE_DUEL_END` runs only during a full-board end attempt and receives
an immutable `winning_owner_ids` snapshot.

`ACTION_RESUMMON_CARD_IN_PLACE` accepts a `card` reference such as
`CARD_REF_TRIGGER_CARD` or `CARD_REF_ABILITY_SOURCE`. It follows that exact
instance across movement, removes the old board instance without exile, and
creates a fresh exact-ID instance in its current cell for the ability source's
current owner. The fresh instance completes normal summoned, after-summoned,
and standard-attack phases. A missing or already removed instance returns
`NO_EFFECT`.

Power-change batches are transition presentation metadata. One top-level action
shares a batch across every nested selected card; different top-level actions
and trigger sources stay ordered as separate batches. Do not store a batch ID
in `DuelState`, catalog definitions, or a replay record.

## Revelation, Prevention, and Passive Modifiers

- `ACTION_REVEAL_HAND_CARDS` accepts `recipient` and an `all` or `remembered`
  filter. It emits `card_revealed` only for newly revealed exact instances.
- `ACTION_ENABLE_FUTURE_DRAW_REVEAL` stores a duel-state audience independently
  of the source card. Future successful draws reveal after `card_drawn`.
- `CONDITION_TRIGGER_CARD_REVEALED_TO_SELF` checks gameplay reveal data, never
  presentation-only testing visibility.
- `ACTION_GRANT_TRIGGER_CARD_ABILITY` deep-copies and normalizes its nested
  `ability`. Structurally identical passive grants are idempotent; a granted
  activation still replaces existing activations.
- `ACTION_PREVENT_TRIGGER_FLIP` produces a typed request for the exact trigger
  instance and intended new owner. All before-flip groups finish before the
  simulator applies one cancellation.
- `ACTION_REMOVE_THIS_ABILITY` removes the exact resolving ability by source
  instance, index, and structural snapshot.
- Modifier-only abilities are valid. The current
  `MODIFIER_DEFENDING_POWER_OVERRIDE` changes only defender-side attackability;
  it does not mutate the four stored powers.

## Adding a New Primitive

Do not add a `card_id` branch to simulator, search, or controller.

1. Add vocabulary and schema validation in `card_catalog.gd`.
2. Add catalog rejection/acceptance tests.
3. Add targeting or conditions in `duel_targeting.gd` /
   `duel_triggers.gd`.
4. Add the generic action to `duel_ability_executor.gd`.
5. Let `duel_simulator.gd` service typed phase requests.
6. Emit ordered pure-data transition events.
7. Add simulator tests for identity, timing, ownership, retention, invalid
   context, and ordering.
8. Add controller presentation only after the simulator passes.
9. Verify greedy and deep AI use the same simulator behavior.

If an ability needs a player choice after an action begins, first design the
currently missing queued-choice mechanism. Do not resolve it only in UI code.

## Required Edge Cases

For every new ability, consider:

- source or target removed, moved, or replaced before resolution;
- source ownership changed;
- ability lost during a previous flip;
- duplicate copies and stable instance identity;
- empty/full hand or deck;
- multiple simultaneous triggers;
- action invalid-context policy;
- cumulative activation costs;
- extra card plays, stacked allowances, and active-player changes;
- terminal state reached mid-resolution;
- AI clone/search behavior;
- face-down information leakage;
- deterministic event and action ordering.

## Art and Inspector

Card art is centered and scaled so its full texture rectangle occupies 80% of
the card's shorter side. Powers render above the picture. Card backs keep their
separate design.

Inspector text uses `glyph`, then tags in sect/tier/weapon order, followed by
description and flavor. Chinese text must use the current smart/arbitrary
wrapping path so Android does not treat a sentence as one unbreakable word.

## Verification

Run catalog tests first, simulator tests next, then the full runner. For visible
changes, also play with mouse and touch-sized portrait input. Catalog
`abilities` plus simulator tests—not printed description—are proof that an
ability is implemented.
