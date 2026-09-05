# Native Single-Authority Combat Cleanup

Date: 2026-09-05

## Goal

Combat legality, resolution, terminal detection, and fallback action choice have
one authoritative implementation: `native/duel_core/`. GDScript remains the
Godot-facing data and presentation layer, but it must not independently decide
whether a combat action is legal or how a combat rule resolves.

This cleanup is primarily about correctness and maintainability. The retired
GDScript engine does not run inside native AI search nodes, so deleting it is
not expected to materially improve AI nodes per second. It will reduce loaded
script size, remove misleading code paths, and prevent future rule changes from
being applied to the wrong engine.

## Current Audit

### Retired implementations

The following modules are not authoritative and do not participate in native
AI descendant search:

- `scripts/duel_triggers.gd` (632 lines): old trigger discovery and dispatch;
  referenced only by tests and the old executor.
- `scripts/duel_card_selector.gd` (445 lines): old selector execution;
  referenced only by tests, the old trigger engine, and the old executor.
- Most of `scripts/duel_ability_executor.gd` (3,984 lines): old action
  execution. Production currently imports it only for `can_pay_costs()` and
  `EMPTY_DECK_DRAW_CARD_ID`.

### Duplicated live combat decisions

`scripts/duel_simulator.gd` still independently enumerates and validates human
actions through `duel_abilities.gd`, `duel_targeting.gd`, and
`DuelAbilityExecutor.can_pay_costs()`. It also independently evaluates terminal
state and chooses the greedy fallback. The native kernel already owns legal
action enumeration and the recursive search versions of those rules. This
overlap can make the UI reject an action that native accepts, or submit one
that native rejects.

### Legitimate GDScript responsibilities

These are not a second combat engine and remain in GDScript:

- `duel_state.gd` and `duel_action.gd`: pure public data objects;
- `duel_compact_state.gd` and `duel_native_rules.gd`: serialization and strict
  GDExtension boundary;
- `duel_controller.gd`: input, animation, audio, inspection, and replay
  presentation;
- initial-state, opening-layout, deck, progression, and replay construction;
- catalog inspection used only to render activation affordances, modifier
  visuals, and ki beads;
- trivial board/presentation utilities such as owner constants, empty-board
  construction, occupied-card counts, and four-`-1` point visibility.

## Target Architecture

```text
controller / replay / tests
          |
          v
 DuelSimulator (thin public facade)
          |
          v
 DuelNativeRules (state/action conversion and error boundary)
          |
          v
 DuelNativeCompactKernel
   - legal action enumeration and validation
   - play and activation transitions
   - triggers, selectors, costs, attacks, flips, movement, zones
   - terminal detection and outcome score
   - deterministic greedy fallback
   - deep AI search
```

The controller may inspect declarations to decide what to display, but it must
obtain selectable actions and final legality from `DuelSimulator`. It must not
reconstruct target or cost rules from catalog declarations.

## Native Public Queries

The existing bound native methods `get_legal_actions_for_owner()` and
`count_legal_actions_for_owner()` become the source for all human, testing-mode,
fallback, replay-validation, and test action queries.

The kernel boundary will additionally expose:

- exact action legality for a materialized play or activation action;
- terminal-state status using the same function used by native search;
- board owner-count difference for outcome and benchmark reporting;
- deterministic greedy fallback matching the current immediate-result scoring
  and tie order.

Every query loads the same compact payload used by transitions and search.
Normal invalid user actions return a normal negative result; malformed state,
unsupported declarations, missing native code, and malformed native responses
remain integration failures.

`DuelNativeRules.apply_action()` will no longer depend on GDScript prevalidation.
It will distinguish a supported-but-illegal action from an unsupported native
rule so invalid input can be rejected without producing a false integration
error.

## GDScript Reduction

After production switches to native public queries:

1. Delete `scripts/duel_triggers.gd`.
2. Delete `scripts/duel_card_selector.gd`.
3. Move the empty-deck fallback card ID into the compact boundary, where its
   prototype is collected, then delete `scripts/duel_ability_executor.gd`.
4. Delete `scripts/duel_targeting.gd` after its final production caller is
   removed.
5. Reduce `scripts/duel_simulator.gd` to native query/transition adapters plus
   pure convenience wrappers.
6. Reduce `scripts/duel_rules.gd` to constants and non-authoritative
   board/presentation utilities. Remove attack, capture, range, and AI-choice
   implementations once no production or retained test calls them.
7. Reduce `scripts/duel_abilities.gd` to catalog/presentation inspection used
   by `card_view.gd` and `duel_controller.gd`. Remove runtime mutation and
   combat-policy helpers owned by C++.
8. Update current architecture, testing, card-authoring, handoff, and native
   README documentation. Historical specifications under `docs/superpowers/`
   remain historical and are not rewritten.

Deleting a file is permitted only after a repository-wide reference scan shows
no production import and all retained tests use the native path.

## Test Migration

Tests must protect behavior rather than preserve the retired implementation.

- Delete `test_duel_trigger_revalidation.gd` and
  `test_duel_card_selector.gd` only after their unique stable-identity,
  ordering, and revalidation cases exist as native event/action fixtures.
- Remove direct `Executor.execute_actions()`, `resolve_normal_flip()`,
  `Triggers.discover()/resolve_group()`, and `Selector.snapshot()/revalidate()`
  sections from card suites only when an equivalent catalog-driven native
  transition or direct native event/attack/flip fixture asserts the same state
  and ordered events.
- Preserve controller integration tests; they verify presentation of native
  events and are not old-engine tests.
- Add native public-query tests for both owners, multiple activations, hand and
  board targets, combined costs, extra-play restrictions, no-action turns,
  fivefold repetition, full boards, pending effects, and deterministic greedy
  ties.

Before removing the old legality code, run a temporary migration seal over the
existing deterministic state corpus. For every state and both owners, compare
the canonical identities and order of old and native legal actions, terminal
status, and greedy choice. Resolve any difference explicitly; do not silently
bless native output merely because native is the intended authority. After the
switch, retained tests assert native behavior directly and the temporary dual
implementation comparison is removed.

## Implementation Sequence

1. Add and test missing native public queries without changing production.
2. Run the temporary old-versus-native migration seal.
3. Switch `DuelNativeRules` and `DuelSimulator` public queries to native.
4. Run focused simulator, search, replay, controller, and benchmark-smoke
   suites.
5. Migrate unique direct old-engine fixtures and remove redundant ones.
6. Delete retired modules, trim retained helpers, and remove test-runner entries
   for deleted suites.
7. Update current documentation and perform a final zero-reference audit.
8. Rebuild Windows native Debug and release-ABI binaries, run the complete
   suite with Dummy audio, and silently play human, testing-mode, greedy
   fallback, and AI flows.

Each stage must leave the suite runnable. No Android package is produced by
this cleanup unless separately requested.

## Acceptance Criteria

- Player, testing mode, replay validation, greedy fallback, and AI all obtain
  combat legality from the native kernel.
- No production GDScript evaluates activation costs or target legality.
- Trigger, selector, action-execution, attack, movement, flip, exile, draw,
  terminal, and fallback behavior have no second GDScript implementation.
- The four retired rule modules and their obsolete direct tests are absent.
- Retained GDScript combat-named files contain only data conversion,
  presentation inspection, initialization, or facade code.
- Repository-wide scans find no current documentation directing contributors
  to implement combat primitives in GDScript.
- The final native build succeeds and the complete automated suite passes.
- Silent production playthroughs cover human actions, an activation, an
  opponent AI action, an extra play when available, and terminal routing.

## Risks and Controls

- **Hidden coverage loss:** migrate unique assertions before deleting old
  tests, and compare check inventories during review.
- **Action-order changes:** compare canonical ordered actions across the
  deterministic corpus before switching production.
- **Invalid-input diagnostics changing:** separate ordinary illegal actions
  from unsupported/malformed native integration failures.
- **UI target regressions:** controller selection must be derived from native
  legal actions, with portrait interaction tests retained.
- **Accidental broad deletion:** require zero-reference scans for each removed
  file and preserve GDScript data/presentation responsibilities explicitly
  listed above.
