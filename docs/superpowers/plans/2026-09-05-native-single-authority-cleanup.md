# Native Single-Authority Combat Cleanup Plan

**Goal:** Remove the retired GDScript combat engine and route every live combat
decision through `DuelNativeCompactKernel` without changing player-visible
behavior.

## Task 1: Seal and expose native public combat queries

- Extend `DuelNativeCompactKernel` bindings with exact action legality,
  terminal status, owner score difference, and deterministic greedy choice.
- Reuse the existing native legal-action enumeration for all queries.
- Extend `duel_native_rules.gd` with compact-boundary adapters returning
  `DuelAction` objects and ordinary negative results for legal-query misses.
- Add focused native query tests for both owners, activation targets and costs,
  extra plays, terminal boundaries, and greedy tie order.
- Build the Windows debug ABI and run focused native/search/simulator suites.

## Task 2: Run the legality migration seal

- Before changing `DuelSimulator`, compare old and native ordered legal actions,
  action legality, terminal results, and greedy choices across the deterministic
  state corpus used by compact-state tests.
- Diagnose every mismatch and either fix the native public adapter or record an
  intentional replacement backed by current rules and tests.
- Keep the comparison only until production is switched; do not retain a
  permanent second-engine parity obligation.

## Task 3: Switch live facades to native authority

- Replace `DuelSimulator` legality, enumeration, terminal, score, and greedy
  implementations with `DuelNativeRules` calls.
- Let `DuelNativeRules.apply_action()` return supported invalid actions without
  reporting an integration failure; unsupported declarations remain fatal.
- Make controller target affordances derive from native legal actions.
- Run simulator, search, replay, controller integration, and benchmark-smoke
  suites.

## Task 4: Migrate unique retired-engine coverage

- Inventory every direct call to `Executor`, `Triggers`, and `Selector` in
  tests.
- Re-express unique behavior through catalog-driven simulator actions or direct
  native event/attack/flip adapters.
- Remove assertions that only test obsolete implementation details when an
  equivalent native behavior assertion already exists.
- Add a native stable-trigger-identity regression before deleting
  `test_duel_trigger_revalidation.gd`.

## Task 5: Delete retired modules and trim survivors

- Move the empty-deck fallback prototype ID into `duel_compact_state.gd`.
- Delete `duel_triggers.gd`, `duel_card_selector.gd`,
  `duel_ability_executor.gd`, and `duel_targeting.gd` after zero-reference
  checks.
- Delete obsolete dedicated test suites and remove them from
  `tools/run_tests.ps1`.
- Remove attack/range/capture/AI implementations from `duel_rules.gd` when no
  retained caller remains.
- Remove mutation/combat-policy functions from `duel_abilities.gd`, preserving
  activation and presentation inspection required by the controller and card
  view.

## Task 6: Documentation and final verification

- Update `HANDOFF.md`, `ARCHITECTURE.md`, `ADDING_CARDS_AND_ABILITIES.md`,
  `TESTING.md`, and `native/duel_core/README.md` to describe the single native
  authority.
- Confirm repository-wide zero current references to retired modules or advice
  to add GDScript combat primitives.
- Rebuild Windows debug and release-ABI native binaries.
- Run the complete suite with Dummy audio.
- Silently play the production human, testing-mode, activation, AI, fallback,
  and terminal flows; inspect diagnostics afterward.
