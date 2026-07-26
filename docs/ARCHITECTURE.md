# Architecture

## Core Principle

There is one gameplay rules path:

```text
Human input / testing input / AI action
                  |
                  v
             DuelAction
                  |
                  v
             DuelSimulator
          / rules transition \
         v                    v
  new DuelState        pure-data events
                              |
                              v
                       DuelController
                              |
                              v
                   cards, VFX, audio, UI
```

The simulator must remain authoritative. If live play and AI would resolve the same action differently, the architecture has been broken.

## Production Modules

### Data

- `duel_state.gd` — pure mutable simulation data: board, hands, decks, discard/removed zones, active player, turn count, queued-effect scaffolding, and state version.
- `duel_action.gd` — pure action descriptor. Current action types are play and activate. It distinguishes source zone and target kind so future abilities can target board cells or hand slots. Activation actions use source-card `instance_id`, never an ability ID.
- `card_catalog.gd` — card definitions, schema constants, normalization, instance creation, and validation.
- `duel_decks.gd` — starting hand lists and side-pool creation.

Neither state nor action data may contain Nodes, Controls, audio players, tweens, or live scene references.

### Rules

- `duel_simulator.gd` — legal-action enumeration, legality checks, action application, attacks, turns, terminal checks, scoring, and greedy fallback.
- `duel_rules.gd` — baseline board geometry, power comparison, scoring helpers, and some legacy prototype helpers. `DuelRules.make_card()` still accepts legacy `name` metadata for test fixtures; production card data does not.
- `duel_abilities.gd` — structural activation lookup/replacement, flip retention, and ki-use detection.
- `duel_ability_executor.gd` — generic costs and actions: draw, exile, attack requests, ki, movement, extra-turn requests, normal flip, and invalid-context policy.
- `duel_targeting.gd` — generic target discovery/validation. The implemented rule is adjacent empty board cell.
- `duel_triggers.gd` — deterministic trigger discovery, stable-context revalidation, composable conditions, the canonical passive-trigger presentation event, and delegation to the shared executor.

`DuelSimulator.apply_action()` mutates the supplied state and returns a transition dictionary containing pure-data events. Tests and AI use this exact path.

For a normal hand play, the simulator places the card and emits `card_placed`, resolves global `TRIGGER_CARD_SUMMONED` groups in row-major source order, then resolves the exact summoned card's retained `TRIGGER_CARD_AFTER_SUMMONED` rules. Its standard attack follows only if the exact instance remains in its summoned cell under the summoning owner. Board movement emits neither summon event.

Every initially valid attack first emits the presentation-only `attack_started`
transition event, then emits `CARD_BE_ATTACKED`, resolves eligible rules in
row-major order, and revalidates the exact attacker and target before flipping.
Gate General and Tiger General exile through an ordinary trigger action; there
is no separate replacement subsystem. The initial attack cue remains even when
one of those rules prevents the flip.

An action with stale or missing context returns `NO_EFFECT` and later actions continue. Only a declaration with `on_invalid_context = STOP_RULE` stops that rule's remaining actions.

### Search

- `duel_search.gd` — deterministic iterative deepening, minimax/alpha-beta, move ordering, and a capped transposition table.
- `duel_search_session.gd` — worker thread, mutex-protected progress, cancellation, failure conversion, and join.
- `duel_evaluator.gd` — card-agnostic heuristic.
- `duel_state_key.gd` — canonical serialization and transposition key.

The worker receives an isolated state copy. Scene objects must never cross the thread boundary.

### Presentation

- `duel_controller.gd` — creates the encounter, translates drag gestures into actions, calls the simulator, and presents transition events sequentially.
- `card_view.gd` / `card_view.tscn` — face/card-back rendering, art, powers, ki badge, drag gestures, and per-card animation.
- `card_inspector.gd` / `card_inspector.tscn` — modal parchment inspector for revealed cards.
- `ink_bloom.gd` — draw summon visual.
- `attack_vfx.gd` — serialized vector-based flying-white attack strokes.
- `extra_turn_vfx.gd` — Meng Huo extra-turn convergence visual.

The controller may choose timing, sound, animation, and labels. It must not independently decide captures, draws, targets, ki costs, or turn ownership.

## State Shape

The board is an Array of nine entries. An empty cell is `null`; an occupied entry contains owner plus a card Dictionary. Hands and decks are keyed by owner ID. Card Dictionaries include immutable definition-derived fields plus mutable runtime fields:

- `instance_id`
- `card_id`
- display metadata
- `powers`
- `original_owner`
- `ki`
- `active_abilities`

Use `instance_id` whenever an action or view must identify a specific copy. Logical hand arrays compact when a card leaves, while five visual hand slots remain fixed; indices alone are therefore unsafe across presentation delays.

## Transition Events

Effects and triggers communicate presentation needs through dictionaries such as:

- `card_flipped`
- `card_exiled`
- `ability_lost`
- `card_drawn`
- `ki_changed`
- `ability_triggered`
- `attack_started`
- extra-turn events emitted during turn resolution

`attack_started` contains stable source/target cells, instance IDs, owners, and
the attack reason. It is emitted after initial attack validation and before
`CARD_BE_ATTACKED`; it is presentation data, not a catalog event or ability
hook. The controller resolves live card rectangles by instance ID and derives
the stroke from their facing edges, so current adjacent attacks and future
non-neighbor attacks share the same geometry path.

`ability_triggered` is emitted only after a passive rule survives revalidation and
its conditions match. It precedes that rule's action events and drives the
generic whole-card pulse. Activations do not emit it. The controller suppresses
only consecutive pulses from the same instance within one presented move; the
memory resets for the next move.

`ability_lost` is identity-free. It identifies the affected card instance but not a named ability. New rules follow the same pattern: mutate only simulation data, emit enough stable identifiers for the controller, and keep event ordering deterministic.

## Extension Boundary

Add reusable vocabulary before adding named-card branches:

1. catalog event/condition/action identifier and schema validation;
2. target/condition/action primitive;
3. simulator resolution and event;
4. simulator tests;
5. controller presentation;
6. integration tests.

Search and evaluation must not check `card_id == ...`. Named content belongs in catalog data assembled from generic primitives.

## Deferred Architecture

`DuelState.effect_queue` and `pending_choice` reserve space for future multi-step effects, but there is not yet a general decision/interrupt engine. Do not pretend it exists.

The current “compact” key hashes a canonical string. Search still deep-duplicates Dictionary-heavy states. A true compact, indexed simulation state was deliberately deferred until more reusable ability primitives stabilize; otherwise each new primitive would require parallel maintenance in two rule engines.
