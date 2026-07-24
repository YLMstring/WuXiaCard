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
- `duel_action.gd` — pure action descriptor. Current action types are play and activate. It already distinguishes source zone and target kind so future effects can target board cells or hand slots.
- `card_catalog.gd` — card definitions, schema constants, normalization, instance creation, and validation.
- `duel_decks.gd` — starting hand lists and side-pool creation.

Neither state nor action data may contain Nodes, Controls, audio players, tweens, or live scene references.

### Rules

- `duel_simulator.gd` — legal-action enumeration, legality checks, action application, attacks, turns, terminal checks, scoring, and greedy fallback.
- `duel_rules.gd` — baseline board geometry, power comparison, scoring helpers, and some legacy prototype helpers. `DuelRules.make_card()` still accepts legacy `name` metadata for test fixtures; production card data does not.
- `duel_effects.gd` — effect primitives: draw, exile instead of flip, normal flip/effect loss, activate-effect lookup/replacement, and ki-use detection.
- `duel_targeting.gd` — generic target discovery/validation. The implemented rule is adjacent empty board cell.
- `duel_triggers.gd` — trigger discovery and revalidation, conditions, ki actions, and extra-turn requests.

`DuelSimulator.apply_action()` mutates the supplied state and returns a transition dictionary containing pure-data events. Tests and AI use this exact path.

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
- `active_effects`

Use `instance_id` whenever an action or view must identify a specific copy. Logical hand arrays compact when a card leaves, while five visual hand slots remain fixed; indices alone are therefore unsafe across presentation delays.

## Transition Events

Effects and triggers communicate presentation needs through dictionaries such as:

- `card_flipped`
- `card_exiled`
- `ability_lost`
- `card_drawn`
- `ki_changed`
- extra-turn events emitted during turn resolution

New rules should follow the same pattern: mutate only simulation data, emit enough stable identifiers for the controller, and keep event ordering deterministic.

## Extension Boundary

Add reusable vocabulary before adding named-card branches:

1. catalog identifier and schema validation;
2. target/condition/action primitive;
3. simulator resolution and event;
4. simulator tests;
5. controller presentation;
6. integration tests.

Search and evaluation must not check `card_id == ...`. Named content belongs in catalog data assembled from generic primitives.

## Deferred Architecture

`DuelState.effect_queue` and `pending_choice` reserve space for future multi-step effects, but there is not yet a general decision/interrupt engine. Do not pretend it exists.

The current “compact” key hashes a canonical string. Search still deep-duplicates Dictionary-heavy states. A true compact, indexed simulation state was deliberately deferred until more reusable effect primitives stabilize; otherwise each new effect would require parallel maintenance in two rule engines.
