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
- `duel_action.gd` — pure action descriptor. Current action types are play and activate. It distinguishes source zone and target kind so future abilities can target board cells or hand slots. Activation actions use source-card `instance_id` plus catalog-ordered `activation_index`, never an ability ID.
- `card_catalog.gd` — card definitions, schema constants, normalization, instance creation, and validation.
- `deck_profile_store.gd` — versioned persistent deck profile, validation/repair, atomic save, unlock insertion, and main-deck/library exchanges.
- `duel_decks.gd` — saved starting-hand lookup plus opponent-hand and side-pool construction.

Neither state nor action data may contain Nodes, Controls, audio players, tweens, or live scene references.

### Rules

- `duel_simulator.gd` — legal-action enumeration, legality checks, action application, attacks, turns, terminal checks, scoring, and greedy fallback.
- `duel_rules.gd` — baseline board geometry, power comparison, scoring helpers, and some legacy prototype helpers. `DuelRules.make_card()` still accepts legacy `name` metadata for test fixtures; production card data does not.
- `duel_abilities.gd` — ordered structural activation lookup, replace-all activation grants, flip retention, and ki-use detection.
- `duel_ability_executor.gd` — generic costs and actions: draw, exile, attack requests, ki, movement, ordered swaps, extra-turn requests, normal flip, and invalid-context policy.
- `duel_targeting.gd` — generic target discovery/validation. Implemented rules cover adjacent empty, allied, and enemy board cells.
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
- `deck_builder_controller.gd` — owns deck-builder profile loading, fixed hand slots, library-to-hand exchange, inspection, and the navigation-neutral `back_requested` signal.
- `deck_library_grid.gd` / `deck_library_grid.tscn` — four-column, 1,000-slot virtualized and scrollable library surface.
- `deck_library_slot.gd` / `deck_library_slot.tscn` — reusable library slot gesture boundary: tap to inspect, hold then drag to exchange, or immediate movement to scroll.
- `parchment_chrome.gd` — shared inspector/library scroll body, shadow, border, and rod styling.
- `card_view.gd` / `card_view.tscn` — face/card-back rendering, art, powers, ki badge, drag gestures, and per-card animation.
- `card_inspector.gd` / `card_inspector.tscn` — modal parchment inspector for revealed cards.
- `ink_bloom.gd` — draw summon visual.
- `attack_vfx.gd` — serialized, clipped playback of the supplied flying-white
  attack bitmap.
- `extra_turn_vfx.gd` — Meng Huo extra-turn convergence visual.

The controller may choose timing, sound, animation, and labels. It must not independently decide captures, draws, targets, ki costs, or turn ownership.

## Deck-Building Data Flow

```text
user://wuxia_deck_profile.json
             |
             v
     DeckProfileStore
       /           \
      v             v
DeckBuilder      DuelDecks
Controller           |
      |               v
      v          starting hand
virtual library     in duel
and fixed hand
```

The persisted profile owns the five-card main deck and a logical library of
exactly 1,000 entries. Occupied library entries form a compact prefix followed
by empty entries. A card ID may appear in exactly one of the main deck or
library. Save data is schema-versioned, validated on load, repaired when
possible, and replaced with a valid default when necessary.

`DeckLibraryGrid` never creates 1,000 Controls. It maintains a pool of 20 slot
views: three visible rows plus one buffer row above and below. Scrolling
rebinds that pool to logical library indices. Recycling pauses while a
long-press or drag is active so the source slot cannot change identity during
an exchange.

The library has 250 logical rows of four standard 3:4 card faces. Slot views
apply the catalog tier to the separate name label, reset that override whenever
they are rebound, and start the first logical row eight pixels below the scroll
content origin. Seven-pixel side insets keep the outer card shadows and scaled
hold cue inside the clipped scroll viewport.

The library uses the inspector's exact parchment chrome. Its vertical scrollbar
is deliberately hidden while scrolling remains enabled. Android/iOS use
`ScrollContainer`'s native touch drag; desktop mouse swipes are translated
locally by the library so the project does not need global mouse-to-touch
emulation, which could interfere with duel card dragging.

The deck builder is a separate scene, `res://scenes/deck_builder.tscn`. It
emits `back_requested` and deliberately does not know which future scene owns
navigation. The playable duel remains `res://main.tscn`.

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
hook. The controller validates the source instance, derives an orthogonal
direction from the source/target cells, and centers the fixed 64 × 22 bitmap on
the first neighboring cell seam. A farther same-row or same-column target does
not stretch or relocate the image.

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
