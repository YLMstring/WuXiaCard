# 天长掌法 3–4 and 恒山剑阵 2–4 Implementation Plan

**Spec:** `docs/superpowers/specs/2026-08-06-tianchang-hengshan-abilities-design.md`

**Goal:** Implement the five approved cards using reusable power-targeting,
attack-summary, enclosure-selection, and non-attack-flip primitives without
card-ID-specific runtime branches.

**Architecture:** Catalog declarations remain the source of gameplay rules.
The simulator owns complete-attack boundaries and generic effect resolution;
the trigger layer evaluates attack summaries against the final board; the
selector revalidates enclosure; and the executor routes power and flip actions
through their established mutation pipelines.

---

## Task 1: Add a focused failing test suite

**Files:**

- Create: `tests/test_tianchang_hengshan_abilities.gd`
- Modify: `tools/run_tests.ps1`

1. Add helpers matching the existing focused card suites.
2. Assert catalog validation, all five IDs, exact declarations, and reusable
   primitive registration.
3. Add failing behavioral tests for summon power, complete-attack reactions,
   grant ranges, enclosure, and flip-trigger integration.
4. Register the suite and require a unique pass marker.
5. Run it once and confirm failure is caused by the missing implementation.

## Task 2: Add generic catalog vocabulary and validation

**Files:**

- Modify: `scripts/card_catalog.gd`
- Extend: `tests/test_tianchang_hengshan_abilities.gd`

1. Register `TRIGGER_CARD_AFTER_ATTACK`.
2. Register `CONDITION_ATTACKER_CARD_IS_ENEMY` and
   `CONDITION_ATTACK_FLIPPED_ALLY_IN_RANGE`.
3. Register `CONDITION_SELECTED_CARD_SURROUNDED_BY_ALLIES`.
4. Add `ACTION_TARGET_ABILITY_SOURCE` as the optional target accepted only by
   `ACTION_ADD_POWERS`.
5. Register `ACTION_FLIP_SELF` and owner reference
   `OWNER_ABILITY_SOURCE`, with strict field validation.
6. Add validator tests for valid declarations, unknown values, wrong fields,
   and malformed types.

## Task 3: Extend selectors and power actions

**Files:**

- Modify: `scripts/duel_card_selector.gd`
- Modify: `scripts/duel_ability_executor.gd`
- Extend: `tests/test_tianchang_hengshan_abilities.gd`

1. Implement surrounded-by-allies relative to the exact ability source owner.
2. Use board adjacency helpers so corners have two neighbors, edges three,
   and center four.
3. Make selector snapshots and revalidation use the same condition function.
4. Extend `ACTION_ADD_POWERS` to resolve either the current subject or exact
   ability source, preserving current behavior when `target` is omitted.
5. Test zero-through-four adjacent enemies, ally exclusion, enclosure shapes,
   broken enclosure, and stale selected instances.

## Task 4: Add complete-attack summaries and reaction conditions

**Files:**

- Modify: `scripts/duel_simulator.gd`
- Modify: `scripts/duel_triggers.gd`
- Extend: `tests/test_tianchang_hengshan_abilities.gd`

1. Keep directional target resolution unchanged but return internal successful
   attack-flip records containing exact instance and previous owner.
2. Resolve one `TRIGGER_CARD_AFTER_ATTACK` after a standard attack finishes all
   directions and their flip triggers.
3. Resolve the same event once after a targeted attack finishes.
4. Evaluate attacker-enemy status from the recorded attacking owner.
5. Evaluate qualifying flipped allies by previous ownership plus exact final
   location in the reacting card's current attack range.
6. Exclude prevented, canceled, no-change, removed, and final-out-of-range
   cards.
7. Test one event per attack, one reaction for multiple flips, final-position
   semantics, and nested reactions.

## Task 5: Route generic non-attack flip requests

**Files:**

- Modify: `scripts/duel_ability_executor.gd`
- Modify: `scripts/duel_triggers.gd`
- Modify: `scripts/duel_simulator.gd`
- Extend: `tests/test_tianchang_hengshan_abilities.gd`

1. Add flip requests to executor, selector, trigger-group, and simulator result
   aggregation.
2. Make `ACTION_FLIP_SELF` capture the current exact subject and resolve
   `OWNER_ABILITY_SOURCE` from the original ability context.
3. Resolve each request through `resolve_non_attack_flip()` sequentially.
4. Preserve established `CARD_BEFORE_FLIPPED`, prevention, movement, actual
   ownership-change, and `CARD_AFTER_FLIPPED` behavior.
5. Revalidate each snapshotted enclosure target immediately before its action.
6. Test prevention, movement, removal, and later selections continuing after a
   skipped target.

## Task 6: Declare all five cards

**Files:**

- Modify: `scripts/card_catalog.gd`
- Extend: `tests/test_tianchang_hengshan_abilities.gd`

1. Add the three missing tier IDs to `ALL_CARD_IDS`.
2. Add shared `HENGSHAN_COUNTERATTACK` with remove-before-attack action order.
3. Declare both 天长掌法 summon-power abilities and tier four's counter.
4. Declare 恒山剑阵2 self-plus-adjacent grant.
5. Declare 恒山剑阵3 all-allies grant.
6. Declare 恒山剑阵4 enclosure flip plus all-allies grant.
7. Confirm identical grant declarations deduplicate and non-retained behavior
   survives catalog normalization and state duplication correctly.

## Task 7: Verify presentation integration and regressions

**Files:**

- Review modified scripts and tests

1. Confirm new trigger abilities use the existing pulse/presentation event
   flow and no card-specific presentation branch is added.
2. Run the focused suite and catalog, selector, simulator, trigger, AI, replay,
   and related ability regression suites.
3. Run Summer script diagnostics and a headless project verification.
4. Run `git diff --check` and inspect status for unrelated user changes.
5. Confirm no runtime TianChangZhang or HenShanJianZhen ID checks exist outside
   catalog data and tests.
