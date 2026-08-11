# 万岳朝宗、大嵩阳神掌与点数变化系统 Implementation Plan

**Spec:** `docs/superpowers/specs/2026-08-11-wanyue-dasongyang-power-change-design.md`

**Goal:** Implement 万岳朝宗1–4 and 大嵩阳神掌1–4 through a reusable signed
power-change action, dynamic card-count values, zero-floor removal, and batched
parallel presentation without introducing card-ID-specific gameplay branches.

**Architecture:** `DuelSimulator` remains authoritative. Catalog declarations
refer to generic card/value vocabulary; `DuelAbilityExecutor` mutates exact
runtime instances and emits pure-data events. Batch IDs exist only in transition
events, never in `DuelState`. `DuelController` groups presentation by batch and
`CardView` owns only the visual tween. Search, replay, testing mode, and live
play continue through the same simulator state and transitions.

---

## Task 1: Restore a truthful green baseline

**Files:**

- Modify: `tests/test_card_catalog.gd`
- Modify: `tests/test_sect_catalog.gd`
- Run: `tools/run_tests.ps1`

1. Confirm the worktree is clean before edits and preserve any newly appearing
   user-owned changes.
2. Update the catalog count/uniqueness fixture to the current production set of
   76 cards rather than the pre-嵩山 count.
3. Synchronize the `SongShanPai` sect assertions with the current production
   name, picture, region, prestige, and specialty. Do not rewrite production
   catalog data to satisfy stale tests.
4. Run `test_card_catalog.gd` and `test_sect_catalog.gd` directly and require
   both to pass.
5. Run the complete test runner and establish a green pre-feature baseline.
   Record engine warnings separately from assertion failures.

## Task 2: Add focused red tests for the complete contract

**Files:**

- Create: `tests/test_wanyue_dasongyang_abilities.gd`
- Create: `tests/test_power_change_integration.gd`
- Modify: `tests/test_card_catalog.gd`
- Modify: `tests/test_duel_simulator.gd`
- Modify: `tests/test_duel_search.gd`
- Modify: `tools/run_tests.ps1`

1. Register both new suites in the canonical runner before production changes.
2. Add catalog validation tests for `ACTION_CHANGE_POWERS`,
   `VALUE_CARD_COUNT`, `CARD_REF_TRIGGER_CARD`, and
   `CONDITION_TRIGGER_CARD_IS_ALLY`.
3. Require signed nonzero integer amounts and valid dynamic value dictionaries;
   reject zero, unknown card references, zones, owners, value types, and extra
   fields.
4. Add migration assertions that no production declaration or known-action
   registry retains `ACTION_ADD_POWERS`.
5. Add executor-level red fixtures for permanent positive changes, per-side
   zero clamping, dynamic zero no-effect, hand/board targeting, exact identity,
   original-owner removed zones, and `powers_changed` before `card_exiled`.
6. Add batch fixtures for several distinct cards, repeated changes to one exact
   instance, mixed surviving/dying cards, separate trigger sources, and hidden
   hand targets.
7. Add card-family fixtures for all eight tier declarations and the summon/
   start-turn timing described in the spec.
8. Add search-copy/key fixtures proving runtime power and removed-zone changes
   remain isolated and distinguishable.
9. Run only the new and extended focused suites; confirm failures are caused by
   missing vocabulary/behavior, not malformed fixtures.

## Task 3: Generalize catalog power-change vocabulary

**Files:**

- Modify: `scripts/card_catalog.gd`
- Modify: `tests/test_card_catalog.gd`
- Modify: `tests/test_duel_simulator.gd`
- Modify: `tests/test_tianchang_hengshan_abilities.gd`

1. Add `ACTION_CHANGE_POWERS`, `VALUE_CARD_COUNT`,
   `CARD_REF_TRIGGER_CARD`, and `CONDITION_TRIGGER_CARD_IS_ALLY` to the strict
   known-vocabulary registries.
2. Define a reusable `amount` schema that accepts either a nonzero signed
   integer or a supported dynamic value dictionary.
3. Validate `VALUE_CARD_COUNT` with exactly one known zone and one known owner
   reference. Initial support is intentionally limited to the hand zone needed
   by 万岳; do not create unused arithmetic-expression machinery.
4. Validate explicit `card` references for the ability source, trigger card,
   and current selector subject without weakening schemas for unrelated actions.
5. Preserve recursive validation inside `ACTION_FOR_EACH_SELECTED_CARD`.
6. Migrate every current `ACTION_ADD_POWERS` declaration—including 紫霞功 and
   天长掌法—to `ACTION_CHANGE_POWERS` with equivalent positive amounts and card
   references.
7. Delete the old action constant, registry entry, validator branch, executor
   dispatch, and test vocabulary only after all declarations are migrated.
8. Run catalog, simulator, and 天长/恒山 focused suites to prove the positive-
   only behavior has not changed.

## Task 4: Implement exact signed power changes and zero removal

**Files:**

- Modify: `scripts/duel_ability_executor.gd`
- Modify: `scripts/duel_state.gd` only if an existing lookup helper must be
  exposed without adding presentation state
- Extend: `tests/test_duel_simulator.gd`
- Extend: `tests/test_wanyue_dasongyang_abilities.gd`

1. Resolve the declared target to one exact runtime `instance_id` in hand or on
   board and revalidate its expected current owner immediately before mutation.
2. Resolve literal amounts directly and `VALUE_CARD_COUNT` against the current
   state at execution time. A resolved zero returns `NO_EFFECT` with no event.
3. Apply positive amounts without a ceiling. For negative amounts, clamp each
   current side independently with `max(0, current + amount)`.
4. Emit `powers_changed` with target identity/location, previous/final arrays,
   resolved amount, ability-source identity, and the new action reason.
5. If and only if a negative result has four zero sides, remove the exact
   instance after emitting `powers_changed`, append it to its `original_owner`
   removed zone, and emit the existing `card_exiled` event.
6. Mark the exile as self-removal only when the ability-source instance is the
   exact target instance; otherwise retain normal external-exile presentation.
7. Reuse/refactor the existing exact-card exile helper so hand and board removal
   share one event/zone path. Do not duplicate removed-zone bookkeeping.
8. Ensure stale, missing, already removed, and owner-changed targets produce
   stable no-effect behavior without affecting later selected cards.
9. Run the executor/simulator fixtures after each red-green increment.

## Task 5: Attach deterministic presentation batches to action results

**Files:**

- Modify: `scripts/duel_ability_executor.gd`
- Modify: `scripts/duel_simulator.gd` only where action results are merged into
  one transition
- Extend: `tests/test_duel_simulator.gd`
- Extend: `tests/test_wanyue_dasongyang_abilities.gd`

1. Allocate batch IDs deterministically within one transition; do not store a
   counter or batch identifier in `DuelState` or the compact search key.
2. Treat one top-level catalog action result as one power presentation batch.
   A selector wrapper must propagate the same batch through every nested
   `ACTION_CHANGE_POWERS` execution it aggregates.
3. Give all `powers_changed` events in that result the same
   `power_change_batch_id` and copy it onto directly caused `card_exiled`
   events.
4. Give different top-level actions and different accepted trigger-source
   groups different IDs, preserving source pulse and event order.
5. Keep every logical `powers_changed` event even when the same exact instance
   changes repeatedly inside one batch; coalescing is presentation-only.
6. Verify clone/search results do not depend on batch IDs and identical actions
   generate reproducible event groupings.

## Task 6: Declare 万岳朝宗 and 大嵩阳神掌 generically

**Files:**

- Modify: `scripts/card_catalog.gd`
- Modify: `scripts/duel_triggers.gd`
- Extend: `tests/test_wanyue_dasongyang_abilities.gd`

1. Implement `CONDITION_TRIGGER_CARD_IS_ALLY` relative to the trigger source's
   current owner, parallel to the existing enemy condition.
2. Add the shared 万岳 self-power ability: after self summon, count the current
   owner's hand and change the exact source; at owner-turn start, change the
   exact source by `-1`.
3. Add tier-two/three adjacent allied summon `+1` and tier-four `+2` reactions.
4. Add 大嵩阳神掌 tier declarations: `+1`; `+1/-1`; `+1/-2`; `+2/-2` for
   adjacent allied/enemy summoned cards respectively.
5. Keep every ability non-retained. Movement and swap events must not match the
   summon trigger.
6. Verify global summon sources resolve in board order, revalidate the exact
   summoned instance, and stop modifying it after a prior source removes it.
7. Verify 万岳 counts after leaving hand and after all global summon reactions,
   before its normal attack.
8. Verify extra-card-play windows do not repeat start-owner-turn decay.
9. Verify a summoned card killed during global reactions performs neither its
   own after-summon rules nor its normal attack, while later independent source
   groups still resolve safely.

## Task 7: Preserve terminal, search, replay, and information rules

**Files:**

- Modify: `scripts/duel_simulator.gd` only if focused tests expose premature
  terminal evaluation
- Modify: `scripts/duel_state_key.gd` only if current removed/power coverage is
  incomplete
- Modify: `scripts/duel_search.gd` only if current evaluation bypasses runtime
  powers
- Extend: `tests/test_duel_search.gd`
- Extend: `tests/test_duel_replay.gd`
- Extend: `tests/test_wanyue_dasongyang_abilities.gd`

1. Confirm summon resolution checks terminal state only after global reactions,
   self after-summon, normal attack, and directly caused removals have settled.
2. Add a full-board fixture where power death reopens a cell; the duel must not
   end on the transiently full board.
3. Confirm compact state keys already include all runtime power arrays and
   removed zones; patch only demonstrated omissions.
4. Confirm attack resolution and heuristic evaluation read runtime `powers`,
   not immutable catalog definitions.
5. Verify replay reconstructs identical logical power/exile/batch event order
   without recording Tween state.
6. Verify face-down enemy hand mutations do not expose card identity, values,
   batch membership, or animation feedback.

## Task 8: Present one parallel animation per visible batch

**Files:**

- Modify: `scripts/card_view.gd`
- Modify: `scripts/duel_controller.gd`
- Extend: `tests/test_zixia_integration.gd`
- Implement: `tests/test_power_change_integration.gd`

1. Add a `CardView` power-change animation taking previous powers, final powers,
   signed direction, duration, and frame-glow color. Keep all four labels at
   fixed positions and animate only centered scale plus frame modulation.
2. Keep every visible target at its previous powers for one shared approximately
   0.12-second pre-delay, then use approximately 0.25 seconds for the animation.
   Positive changes pulse slightly larger with
   restrained warm gold-green glow; negative changes pulse slightly smaller
   with dark red glow. Update all four displayed results together.
3. In `_present_transition_events`, detect the first event of a power batch,
   collect all power events sharing its batch ID, and group them by exact
   `instance_id`.
4. For a repeated exact instance, use the earliest `previous_powers` and latest
   `powers`; still append every original event to debug/presentation traces.
5. Await one shared visible pre-delay, then start every visible card animation
   in the same frame before awaiting a single animation barrier. Total batch
   duration must remain approximately 0.37 seconds regardless of one, two, or
   many affected cards.
6. Mark grouped power events consumed, then continue through the original flat
   event order. Directly caused `card_exiled` events therefore run only after
   the shared power barrier and remain ordered among themselves.
7. Update face-down hand view data without playing or waiting for an animation.
   If a batch has no visible card, do not create an empty pre-delay or animation
   delay.
8. Guard against missing/freed views, inspection state, replay exit, and zero-
   duration test configuration without changing simulator state.
9. Assert that old values remain visible through the shared pre-delay, plus fixed
   label positions, simultaneous start timestamps, one shared wait, final values,
   distinct add/subtract glow, repeated-instance coalescing, and full-zero
   animation-before-exile behavior.

## Task 9: Update durable documentation

**Files:**

- Modify: `docs/HANDOFF.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/DECISIONS.md`
- Modify: `docs/ADDING_CARDS_AND_ABILITIES.md`
- Modify: `docs/AI_SEARCH.md`
- Modify: `docs/TESTING.md`

1. Document the signed action, dynamic card count, explicit card references,
   zero floor, original-owner removal, and self/external presentation marker.
2. Document 万岳 and 大嵩阳神掌 tier semantics and their exact summon/start-turn
   timing.
3. Document that batch IDs are transition-only presentation metadata and do not
   belong in state or search keys.
4. Document parallel visible batching, repeated-instance visual coalescing,
   hidden-card no-wait behavior, and animation-before-removal ordering.
5. Update the handoff implemented-rules snapshot only after the feature and
   production-path verification pass.

## Task 10: Verify the production path and hand off for commit

**Files:**

- Review every modified production, test, runner, and documentation file

1. Run the new catalog/rules/integration suites directly.
2. Run catalog, simulator, selector, search, replay, Zi Xia, Tian Chang/Heng
   Shan, ki presentation, and duel integration regressions.
3. Run the canonical full suite:

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
   ```

   Require every suite to pass; do not compare only against the formerly red
   baseline.
4. Run `git diff --check`, inspect exact status/diff, and verify no unrelated
   user changes were overwritten.
5. Launch the production scene at 540×960 and walk these flows with normal mouse
   behavior mirroring touch:
   - 万岳 enters from a five-card hand and gains four per side after reactions;
   - multiple allied cards gain power in one visibly parallel batch;
   - 大嵩阳神掌 buffs an ally and debuffs an enemy at every tier amount;
   - a board card and a hand card reach four zeros and use the correct removal;
   - a summoned card killed before its after-summon phase does not attack;
   - multiple dying cards wait for one shared batch animation, then disappear
     in deterministic order;
   - normal opponent hand concealment survives unseen power changes;
   - replay reproduces the same logical and visible sequence.
6. Inspect script diagnostics, console, and debugger after the walkthrough.
7. Report the final changed-file list, focused/full test evidence, manual flow
   evidence, and any remaining warnings. Leave changes uncommitted for the user
   unless a separate Git approval succeeds; never push without explicit request.
