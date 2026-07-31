# CangSong and SanQinFeng Abilities Implementation Plan

**Spec:** `docs/superpowers/specs/2026-07-31-cangsong-sanqinfeng-abilities-design.md`

## Objective

Implement `CangSongYingKe3`, `CangSongYingKe4`, and `SanQinFeng1` through
`SanQinFeng3` through reusable catalog primitives. Add committed before-flip
timing, fresh catalog-card creation in either hand, and truly sequential
selected-card attacks while keeping the pure simulator authoritative for live
play and AI search.

## Task 1: Record the current baseline

**Files**

- Inspect only

1. Confirm `git status --short` is clean.
2. Run `tools/run_tests.ps1`.
3. Record every pre-existing failing suite and its exact checks.
4. Run the catalog, selector, simulator, search, and duel-integration suites
   independently when the full-run output needs isolation.
5. Do not repair unrelated stale expectations as part of this feature.

## Task 2: Add failing catalog-schema tests

**Files**

- Modify `tests/test_card_catalog.gd`
- Modify `scripts/card_catalog.gd`

Add tests for:

- `CARD_BEFORE_FLIPPED` as a known trigger event;
- `ACTION_ADD_CARD_TO_HAND`;
- `RECIPIENT_SELF` and `RECIPIENT_OPPONENT`;
- required known `card_id`;
- required known recipient;
- rejection of missing, wrong-type, unknown, and unsupported fields; and
- exact CangSong and SanQinFeng declarations.

Extend action validation without accepting the add-card action as an
activation cost. Validate `card_id` against `ALL_CARD_IDS` and validate the
recipient against a dedicated known-recipient list.

Run `test_card_catalog.gd` after the schema change.

## Task 3: Implement deterministic fresh-card creation

**Files**

- Modify `scripts/duel_ability_executor.gd`
- Add or modify focused tests in `tests/test_duel_simulator.gd`
- Verify `scripts/duel_state.gd`
- Verify `scripts/duel_state_key.gd`

Implement `ACTION_ADD_CARD_TO_HAND` for the current action subject:

1. Resolve the subject and its current owner.
2. Map `SELF` or `OPPONENT` to the recipient owner.
3. If that hand already has five cards, return `NO_EFFECT`.
4. Find a deterministic unused generated instance ID by scanning every
   card-bearing state zone.
5. Call `CardCatalog.create_instance` with the requested exact card ID.
6. Append the fresh instance to the recipient hand.
7. Emit `card_added_to_hand` with source, recipient, logical index, instance
   ID, and a deep-copied card payload.

The instance allocator must inspect board, both hands, both side decks,
discard piles, and removed-card zones. It must not reuse an ID held by any
physical card in the state.

Test self/opponent recipients, fresh catalog powers/ki/abilities, independent
nested arrays, full-hand `NO_EFFECT`, deterministic IDs across equal state
copies, and collision avoidance across every zone.

## Task 4: Add the committed before-flip pipeline

**Files**

- Modify `scripts/duel_simulator.gd`
- Modify `scripts/duel_triggers.gd` only if context lookup needs a generic
  helper
- Modify `tests/test_duel_simulator.gd`

Centralize ownership-changing flip attempts in a helper that accepts:

- target instance ID;
- current or discoverable target cell;
- intended new owner;
- flip reason; and
- optional attack context.

For attack flips:

1. Resolve `CARD_BE_ATTACKED`.
2. Revalidate exact attacker, exact target, ownership, and range.
3. If invalid, emit neither before- nor after-flip.
4. Resolve `CARD_BEFORE_FLIPPED` with the target as trigger card.
5. Locate exact attacker and target again.
6. Ignore board movement and range at this committed stage.
7. Cancel only on non-movement invalidators such as missing source/target or
   target already having the intended owner.
8. Flip and resolve `CARD_AFTER_FLIPPED`.

For non-attack flips, follow the exact target instance across board movement
and apply the same before/after event pair. Provide a focused pure helper that
future non-attack effects can call even though no production card uses it yet.

Tests must prove both revalidation stages and event order. Use synthetic
fixture abilities/actions where necessary; do not special-case production
card IDs.

## Task 5: Make nested selected-card attacks truly sequential

**Files**

- Modify `scripts/duel_ability_executor.gd`
- Modify `scripts/duel_triggers.gd`
- Modify `scripts/duel_simulator.gd`
- Modify `tests/test_duel_simulator.gd`
- Verify `tests/test_duel_card_selector.gd`

Add an optional production resolution callback to executor action processing.
When present, every attack request produced by a nested action is resolved
immediately and its captures, exiles, events, and extra-turn requests are
merged into that action result before execution continues.

Thread the callback through:

- normal trigger group resolution;
- activation action resolution;
- recursive `ACTION_FOR_EACH_SELECTED_CARD`; and
- any existing root action path that can produce an attack request.

Keep the callback optional so isolated executor tests can still assert raw
attack requests.

Prove:

- one selected sword's attack completes before the next is revalidated;
- an earlier attack flipping/exiling a later selection makes it skip;
- nested reaction attacks remain ordered;
- later outer actions run only after the wrapper's attacks;
- existing CangSong summon reactions and YouFen activations preserve order;
  and
- recursion does not duplicate captures, exiles, or presentation events.

## Task 6: Return complete start-turn resolutions

**Files**

- Modify `scripts/duel_simulator.gd`
- Modify `tests/test_duel_simulator.gd`

Change `_finish_turn` to return a complete resolution dictionary rather than
only an event array. Merge its captures, exiles, events, and nested requests
into both play and activation transitions.

Preserve:

- end-owner-turn triggers before owner selection;
- Meng Huo extra-turn selection and event order;
- start-owner-turn triggers after the next owner is fixed; and
- state version and turn-count behavior.

Add tests for captures/exiles caused at ordinary and extra-turn starts,
including exact parent-transition fields.

## Task 7: Declare the five catalog abilities

**Files**

- Modify `scripts/card_catalog.gd`
- Modify `tests/test_card_catalog.gd`
- Modify `tests/test_duel_simulator.gd`

For `CangSongYingKe3` and `CangSongYingKe4`:

- preserve their summon reaction;
- subscribe to `CARD_BEFORE_FLIPPED`;
- require trigger card self and at least 1 ki;
- spend exactly 1 ki;
- add their own exact card ID to `RECIPIENT_SELF`; and
- keep default ability loss on flip.

For `SanQinFeng1`, `SanQinFeng2`, and `SanQinFeng3`:

- subscribe to owner-turn start;
- require at least 1 ki;
- spend exactly 1 ki before selection;
- select allied board sword cards in row-major order;
- use limits 1, 2, and 3;
- include the source itself;
- order each selected subject to perform a standard attack; and
- spend ki even when selection or attacks produce no effect.

Test both owners, full hands, fewer matches than the limit, multiple sources,
ability loss after flip, pre-flip owner semantics, and fresh-copy behavior.

## Task 8: Present generic hand additions

**Files**

- Modify `scripts/duel_controller.gd`
- Reuse existing `scripts/card_view.gd`
- Modify `tests/test_duel_integration.gd`
- Add a focused integration suite only if isolating the behavior materially
  improves reliability

Handle `card_added_to_hand` through the existing silent Ink Summon
presentation path without pretending to remove a card from a side deck.

The controller must:

- create the hand card view at its logical slot;
- reveal player additions;
- conceal normal-mode opponent additions;
- reveal testing-mode opponent additions;
- preserve fixed five-slot sizing; and
- complete the hand addition before later flip feedback.

Confirm CangSong and SanQinFeng retain generic passive pulses and standard
attack VFX without card-specific presentation branches.

## Task 9: Update durable documentation

**Files**

- Modify `docs/ADDING_CARDS_AND_ABILITIES.md`
- Modify `docs/ARCHITECTURE.md`
- Modify `docs/DECISIONS.md`
- Modify `docs/HANDOFF.md`
- Modify `docs/TESTING.md`

Document:

- attack and non-attack before-flip timing;
- the committed-movement rule after `CARD_BEFORE_FLIPPED`;
- add-card declaration and recipient semantics;
- deterministic generated instance IDs;
- sequential selected-card attack resolution; and
- the five production ability declarations.

Keep examples declarative and free of card-specific simulator instructions.

## Task 10: Verify and playtest

1. Run focused suites after the final edit:

   - catalog;
   - selector;
   - simulator;
   - search;
   - YouFen integration;
   - Zi Xia integration;
   - duel integration; and
   - any new focused integration suite.

2. Run `tools/run_tests.ps1` and compare failures to Task 1.
3. Run `git diff --check`.
4. Start the production main scene.
5. Check Summer diagnostics first, then inspect console/debugger details only
   if diagnostics report errors.
6. Use a disposable runtime verification probe to prove:

   - CangSong spends ki, adds a fresh copy, then flips;
   - full-hand CangSong spends ki without adding;
   - SanQinFeng attacks at least two selected swords in order; and
   - normal-mode opponent hand additions remain concealed.

7. Stop the verification session if it was started only for this task.
8. Commit implementation and documentation without pushing.

## Completion Criteria

- All five cards match their approved descriptions and edge cases.
- The new trigger/action vocabulary passes catalog validation.
- Attack movement before the before-flip event can prevent that event.
- Movement during the before-flip event never cancels the committed flip.
- Non-attack flips follow moved target instances.
- Selected standard attacks resolve and revalidate sequentially.
- AI search sees generated cards and every nested combat mutation.
- Runtime presentation preserves concealment and event order.
- Focused tests are green.
- The full suite has no failures beyond the recorded baseline.
- Production runtime diagnostics contain no new script or debugger errors.
