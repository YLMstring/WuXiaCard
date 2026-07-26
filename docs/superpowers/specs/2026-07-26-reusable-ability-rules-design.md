# Reusable Ability Rules Design

## Goal

Replace the duel's current mixture of effect IDs, special-case helpers, and
trigger-specific code with one declarative ability-rule system.

Every current card ability will be expressed with reusable:

- events;
- conditions;
- activation input and target rules;
- costs;
- actions.

The simulator remains the authority for summon, attack, activation, flip,
movement, and turn phases. The rule system describes what an ability requests;
it does not duplicate those core game procedures.

This migration covers all current abilities at once:

- CangSongYingKe2's summon reaction;
- Fa Zheng and Strategist's draw ability;
- Gate General and Tiger General's exile behavior;
- Meng Huo's ki gain and extra turn;
- Jiang Wei and Sun Zan's move-and-attack activation.

## Terminology and Runtime Shape

The catalog field `effects` becomes `abilities`. Runtime cards use
`active_abilities` instead of `active_effects`.

An ability entry has no mandatory `id`. Its behavior is defined entirely by its
declared rules. Named effect-ID constants and behavior dispatch by effect ID are
removed.

An ability can contain:

- zero or more `triggers`;
- zero or one `activation`;
- optional `retained_on_flip`.

`retained_on_flip` defaults to `false`. When a card changes ownership by being
flipped, all non-retained ability entries are permanently removed. Retained
entries remain and subsequently act for the card's new owner.

A card may have multiple passive ability entries. Across all of a card's
entries, at most one may contain `activation`. If a future rule gives a card a
new activation, the ability entry containing the old activation is removed or
replaced while unrelated passive entries remain.

Runtime cards and event contexts use `instance_id` as their stable identity.
Card catalog IDs remain; ability IDs do not.

## Declarative Schema

### Triggered ability

```gdscript
{
    "retained_on_flip": true,
    "triggers": [
        {
            "event": CARD_BE_ATTACKED,
            "conditions": [
                {"type": CONDITION_ATTACKER_CARD_IS_SELF},
            ],
            "actions": [
                {"type": ACTION_EXILE_ATTACKED_CARD},
            ],
        },
    ],
}
```

Conditions in one rule are ANDed in declaration order. An omitted or empty
`conditions` array passes.

Actions execute in declaration order. Each action revalidates the context it
uses immediately before execution.

### Activated ability

Activation input and target selection remain explicit because they are UI and
legal-action concerns. Costs and effects use the common action vocabulary.

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

All costs are validated before any cost is paid. If every cost is valid, costs
are paid in declaration order and the action list begins. A later action
becoming inapplicable does not refund paid costs.

The action is still identified to the simulator by source-card `instance_id`,
source cell, input kind, and selected target. It is not identified by an ability
ID.

### Optional invalid-context policy

An action whose referenced card, cell, or target is no longer valid normally
does nothing and allows the remaining actions in that rule to continue.

Stopping the rule must be requested explicitly in that action's catalog data:

```gdscript
{
    "type": ACTION_MOVE_SELF_TO_TARGET,
    "on_invalid_context": STOP_RULE,
}
```

`on_invalid_context` may currently be omitted or set to `STOP_RULE`. Other
values are rejected by catalog validation.

## Action Results and Invalid Context

The executor exposes three results:

- `APPLIED`: the action changed state or successfully issued its request;
- `NO_EFFECT`: the action could not apply; continue with the next action;
- `INVALID_CONTEXT`: stop the remaining actions in this rule only.

An underlying stale or missing context maps to `NO_EFFECT` by default. It maps
to `INVALID_CONTEXT` only when that action declaration explicitly contains
`"on_invalid_context": STOP_RULE`.

This means, by default:

- if a movement action cannot move, a later standard-attack action still tries
  to attack from the card's current cell;
- if Gate General or Tiger General tries to exile an attacked card that has
  already moved, left the board, or been replaced, the exile does nothing and
  any later actions in that same rule still run.

`INVALID_CONTEXT` never cancels later trigger rules, the enclosing event, or the
turn. It only stops the current rule's remaining actions. Activation costs
already paid remain spent.

## Stable Event Contexts

Every event context records stable locators for relevant cards:

- `instance_id`;
- expected zone;
- expected board cell when applicable;
- current owner at the point the event is emitted.

Conditions and actions resolve a locator against current state. A card with the
same catalog ID—or a different instance now occupying the same cell—is not the
same object.

Owner-sensitive actions use the ability card's current owner at execution time,
not a permanently captured original owner. This is what allows a retained
ability to work for a card's new owner after a flip.

## Deterministic Trigger Ordering

For a global board event, eligible source cards are considered in canonical
board order:

1. left to right across the top row;
2. left to right across the middle row;
3. left to right across the bottom row.

Within one source card:

1. `active_abilities` array order;
2. trigger array order within that ability.

Each rule is rediscovered or revalidated against current state immediately
before it resolves. State changes made by an earlier rule are visible to later
rules.

The same ordering applies to `TRIGGER_CARD_SUMMONED`, `CARD_BE_ATTACKED`,
successful-flip events, and end-turn events. It is shared by live play, testing
mode, greedy AI, and deep search.

## Summon Resolution

A normal card play resolves in this order:

1. Remove the selected card from hand and place it in the chosen board cell.
2. Emit the existing `card_placed` transition.
3. Emit and globally resolve `TRIGGER_CARD_SUMMONED` in deterministic order.
4. If the exact summoned instance remains on the board, resolve
   `TRIGGER_CARD_AFTER_SUMMONED` from that card's current
   `active_abilities`.
5. Perform the summoned card's standard attack only if the exact instance still
   occupies its summoned cell and still belongs to the summoning player.
6. Finish the turn.

`TRIGGER_CARD_SUMMONED` is the reaction window used by CangSongYingKe2.
`TRIGGER_CARD_AFTER_SUMMONED` is the summoned card's own post-reaction window.

At step 4:

- an unchanged card resolves for its current owner;
- a flipped card exposes only its retained abilities, which resolve for its new
  owner;
- an exiled, moved-away, or replaced card has no after-summoned rule to resolve.

Consequently, the current non-retained draw ability cannot draw after
CangSongYingKe2 flips the summoned card. If a future draw ability is retained,
it can draw for the card's new owner. The standard summon attack remains
cancelled after an ownership change even when a retained after-summoned ability
resolves.

Future effect-created summons enter the same two summon event phases. Movement,
ownership changes, and drawing into hand do not emit summon events.

## Attack Resolution

Every attack source—normal summon attack, activated move-and-attack,
CangSongYingKe2 reaction, and future combo attacks—uses one attack procedure:

1. Record exact attacker and attacked-card contexts.
2. Emit `CARD_BE_ATTACKED` before resolving the attack.
3. Discover eligible trigger rules in deterministic board, ability, and trigger
   order.
4. Revalidate and resolve each rule.
5. Revalidate the original attack.
6. Perform it only if the exact attacker and attacked instances remain in their
   recorded cells and are still enemies.

If either card moved, disappeared, was replaced, or no longer has the required
enemy relationship, the original attack does nothing.

There is no separate replacement-rule collection, cancellation flag, or
"first replacement wins" mechanism. Gate General and Tiger General use normal
triggers. Their successful exile naturally makes the original attack fail final
revalidation.

## Current Ability Declarations

### CangSongYingKe2

```gdscript
{
    "triggers": [
        {
            "event": TRIGGER_CARD_SUMMONED,
            "conditions": [
                {"type": CONDITION_TRIGGER_CARD_IS_ENEMY},
                {"type": CONDITION_TRIGGER_CARD_IN_RANGE},
            ],
            "actions": [
                {"type": ACTION_ATTACK_TRIGGER_CARD},
            ],
        },
    ],
}
```

`ACTION_ATTACK_TRIGGER_CARD` sends a request to the simulator's shared attack
procedure. It does not duplicate combat logic.

### Fa Zheng and Strategist

```gdscript
{
    "triggers": [
        {
            "event": TRIGGER_CARD_AFTER_SUMMONED,
            "conditions": [
                {"type": CONDITION_TRIGGER_CARD_IS_SELF},
            ],
            "actions": [
                {"type": ACTION_DRAW_CARDS, "amount": 2},
            ],
        },
    ],
}
```

The entry omits `retained_on_flip`, so it is lost on flip. Drawing uses the
ability card's current owner and the existing shuffled side-deck, hand-limit,
draw-transition, visual-effect, and timing behavior.

### Gate General and Tiger General

```gdscript
{
    "retained_on_flip": true,
    "triggers": [
        {
            "event": CARD_BE_ATTACKED,
            "conditions": [
                {"type": CONDITION_ATTACKER_CARD_IS_SELF},
            ],
            "actions": [
                {"type": ACTION_EXILE_ATTACKED_CARD},
            ],
        },
    ],
}
```

The ability belongs to the attacking Gate General or Tiger General. Before its
attack resolves, it exiles the exact attacked instance if that card is still in
the recorded cell. If the attacked card has already moved to another area or
been replaced, the action returns `NO_EFFECT` by default.

The retained declaration preserves the current rule that this ability remains
after its owner is flipped.

### Meng Huo

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
                {"type": ACTION_REQUEST_EXTRA_TURN},
            ],
        },
    ],
}
```

`CARD_AFTER_FLIPPED` is emitted only when the attacked card actually changes
ownership. Exile and failed attacks do not count.

At the end of its owner's turn, every eligible Meng Huo resolves in canonical
order and spends all its ki. Multiple Meng Huos may request an extra turn, but
the simulator grants at most one extra turn for that end-turn resolution.
Their ki is all spent. An extra turn may produce another extra turn later if ki
is earned again.

`CONDITION_TURN_OWNER_IS_SELF` compares the player whose turn is ending with the
ability card's current owner.

### Jiang Wei and Sun Zan

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

The move emits the existing `card_moved` transition.
`ACTION_STANDARD_ATTACK_WITH_SELF` asks the simulator to run the standard attack
from the card's current cell after movement. If movement produces `NO_EFFECT`,
the attack still tries from the card's existing cell unless the catalog
explicitly gives the movement action `on_invalid_context: STOP_RULE`.

Ki is independent state. Activations cost ki, but passive-only abilities do not
make a zero-ki card display the ki bead. `card_uses_ki` therefore checks only
for an activation, not for passive actions that gain or spend ki.

## Shared Vocabulary

The initial reusable action set is:

- `ACTION_DRAW_CARDS`;
- `ACTION_EXILE_ATTACKED_CARD`;
- `ACTION_ATTACK_TRIGGER_CARD`;
- `ACTION_GAIN_KI`;
- `ACTION_SPEND_KI`;
- `ACTION_SPEND_ALL_KI`;
- `ACTION_REQUEST_EXTRA_TURN`;
- `ACTION_MOVE_SELF_TO_TARGET`;
- `ACTION_STANDARD_ATTACK_WITH_SELF`.

`SELF` always means the card containing the currently resolving ability.

Pure state actions—draw, ki, exile, and movement—are executed by the common
executor and emit their existing transition events. Attack and extra-turn
actions return typed requests to the simulator so their authoritative phase
logic remains centralized.

The rule system contains only data and pure simulation code. It does not store
scene nodes or call presentation code.

## Responsibilities

### `card_catalog.gd`

- defines event, condition, action, activation-input, target-rule, result, and
  invalid-context-policy constants;
- validates the complete identity-free `abilities` schema;
- rejects unknown keys and constants where practical;
- normalizes omitted `retained_on_flip` to `false`;
- creates runtime `active_abilities`.

### `duel_abilities.gd`

- finds a card's activation structurally;
- replaces an existing activation without removing passive entries;
- removes non-retained abilities on flip;
- answers `card_uses_ki` from activation presence only.

The old ID-driven responsibilities in `duel_effects.gd` move here or into the
executor; no compatibility wrapper remains.

### `duel_triggers.gd`

- creates stable event contexts;
- discovers rules in deterministic order;
- evaluates shared conditions;
- revalidates source ability and event context before resolution.

### `duel_ability_executor.gd`

- validates all activation costs before payment;
- executes shared cost and action declarations;
- applies the explicit invalid-context policy;
- mutates pure state for draw, ki, exile, and movement;
- emits existing transition records;
- returns typed attack and extra-turn requests.

### `duel_targeting.gd`

- continues to determine legal activation targets from `target_rule`;
- remains extensible to ally cells, enemy cells, hand slots, and future target
  domains.

### `duel_simulator.gd`

- owns summon, attack, activation, and end-turn phases;
- emits events at the specified timing points;
- services attack and extra-turn requests;
- performs final stable-identity revalidation;
- remains the single authority used by live play and every AI path.

## Presentation and Transition Events

Existing state transitions remain authoritative, including:

- `card_placed`;
- `card_moved`;
- `card_flipped`;
- `card_exiled`;
- `card_drawn`;
- `ki_changed`;
- `extra_turn_granted`;
- `ability_lost`.

`ability_lost` becomes identity-free. It may identify the source card instance
and provide generic presentation data, but it does not expose an effect or
ability ID. After transitions play, the controller synchronizes the card's
final `active_abilities`.

No reusable reaction cue, reaction-declared event, card-play-interrupted event,
or general player-choice stack is added in this migration.

## Migration

This is one atomic schema migration. There is no compatibility layer for:

- `effects`;
- `active_effects`;
- effect ID constants;
- `draw_count`;
- ID-based `ability_id` fields in legal actions;
- bespoke dispatch by named effect.

Catalog declarations, runtime state, state-key generation, legal actions,
controller presentation, tests, and developer documentation migrate together.
Saved in-progress duel compatibility is not required.

The implementation must preserve unrelated user edits, including game settings
and UI changes.

## AI, Compact Simulation, and Determinism

Search, greedy fallback, testing mode, and live play all invoke the same
simulator paths. The AI contains no card-ID or ability-ID branches.

Rule data and runtime ability data are included in canonical state keys where
they affect future play. Stable ordering and pure data preserve reproducible
search results and compact-simulation compatibility.

The refactor must not alter search budgets, perfect-information policy,
fallback policy, or evaluation heuristics.

## Validation and Verification

Catalog and schema tests cover:

- exact declarations for every current ability;
- omitted `retained_on_flip` becoming `false`;
- multiple passive entries;
- rejection of multiple activations;
- replacement of an old activation while preserving passives;
- rejection of old identity-based fields and unknown vocabulary;
- rejection of invalid `on_invalid_context` values.

Rule tests cover:

- summon reaction before after-summoned draw;
- non-retained draw being lost after a flip;
- retained after-summoned draw using the card's new owner;
- no after-summoned rule after exile, movement, or replacement;
- standard summon attack requiring the original summoning owner;
- row-major ordering for `TRIGGER_CARD_SUMMONED` and `CARD_BE_ATTACKED`;
- stable instance validation when a cell's occupant is replaced;
- stale attacked-card exile returning `NO_EFFECT`;
- default `NO_EFFECT` continuing later actions;
- explicit `STOP_RULE` stopping only the current rule;
- paid activation costs never being rolled back;
- successful-flip-only Meng Huo ki gain;
- all eligible Meng Huos spending ki for one total extra turn;
- move-and-attack cost, target, transition, and attack ordering;
- passive-only zero-ki cards hiding the ki bead.

Integration tests cover:

- parity for all migrated cards;
- identity-free `ability_lost` presentation;
- state-key determinism;
- greedy and deep-search simulator parity;
- full existing automated suite.

After implementation, a live playtest verifies flip, exile, delayed draw,
movement, ki, extra-turn presentation, and normal drag-and-drop play.
