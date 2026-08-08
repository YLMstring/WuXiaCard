# 云雾十三式、一剑落九雁与天柱云气 Implementation Plan

**Spec:** `docs/superpowers/specs/2026-08-08-hengshan-three-families-design.md`

**Goal:** Implement all eight approved 衡山派 cards through reusable English
catalog declarations, exact-instance temporary ability loss, pre-summon and
before-move timing, attack-summary selection, and existing movement/presentation
paths without named-card branches in runtime rules.

**Architecture:** `DuelSimulator` remains authoritative. Catalog declarations
describe every card. `DuelTriggers` discovers and revalidates event rules;
`DuelCardSelector` selects exact instances with event context; and
`DuelAbilityExecutor` performs generic actions while routing before-move timing
back through the simulator. Temporary ability batches live on card instances so
state duplication and AI keys remain exact.

---

## Task 1: Restore a green pre-feature baseline

**Files:**

- Modify: `tests/test_card_catalog.gd`
- Modify: `tests/test_sect_catalog.gd`

1. Update the hard-coded catalog total to the current production IDs added in
   commit `f8be43d`; preserve uniqueness and definition coverage assertions.
2. Update only the stale sect name/picture/region expectations to match current
   `scripts/sect_catalog.gd` production data.
3. Run both suites and confirm they pass.
4. Preserve every production catalog value; do not solve stale tests by
   reverting user data.

## Task 2: Add focused failing rules tests

**Files:**

- Create: `tests/test_hengshan_three_families.gd`
- Modify: `tools/run_tests.ps1`

1. Assert registration of all new English event, condition, selector-condition,
   and action constants.
2. Assert exact ability counts and declarations for all eight card IDs.
3. Add red tests for pre-summon priority, temporary ability batches, retained
   abilities, same-turn grants, flip permanence, and turn-end restoration.
4. Add red tests for attack-flip selection, adjacency-only swap, exact-instance
   movement/replacement, and tier-three follow-up attacks.
5. Add red tests for automatic lowest-index movement, failed-move draw gating,
   external movement, and both halves of swaps.
6. Register a unique pass marker and run once to confirm failure is caused by
   missing production vocabulary/behavior.

## Task 3: Implement temporary non-retained ability batches

**Files:**

- Modify: `scripts/duel_abilities.gd`
- Modify: `scripts/duel_ability_executor.gd`
- Modify: `scripts/duel_simulator.gd`
- Extend: `tests/test_hengshan_three_families.gd`

1. Add card-instance storage for chronological suppression batches. Each entry
   records a deep-copied ability, its index in that batch's pre-removal active
   list, and the current `turn_count` expiry.
2. Implement `ACTION_TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES` against the
   current subject, leaving every `retained_on_flip` ability active.
3. Emit one `ability_lost` event for each actual removal, with stable instance,
   owner, zone, and logical index metadata.
4. Restore expiring batches after all `TRIGGER_END_OWNER_TURN` groups and before
   turn-count/extra-turn progression. Restore batches newest-first and entries
   by saved index so retained and newly granted abilities keep deterministic
   order.
5. Emit one `ability_gained` event for each restored ability. New abilities
   gained after an earlier suppression remain active unless a later suppression
   explicitly removes them.
6. Extend permanent flip loss to clear all temporarily stored non-retained
   abilities without emitting duplicate loss events.
7. Traverse every duel card zone once at cleanup, keyed by exact `instance_id`,
   so movement or a future same-instance zone transfer cannot lose expiry.
8. Test repeated batches, deep-copy isolation, state duplication, state-key
   differences, flip-before-expiry, and retained abilities.

## Task 4: Add the own-card pre-summon phase

**Files:**

- Modify: `scripts/card_catalog.gd`
- Modify: `scripts/duel_triggers.gd`
- Modify: `scripts/duel_simulator.gd`
- Extend: `tests/test_hengshan_three_families.gd`

1. Register `TRIGGER_CARD_BEFORE_SUMMONED` and strict validation.
2. Reuse the existing own-cell discovery behavior used by
   `TRIGGER_CARD_AFTER_SUMMONED` so only the exact summoned instance can resolve
   this phase.
3. Insert the phase after logical placement/summon event creation but before
   global `TRIGGER_CARD_SUMMONED` for both hand plays and generated summons.
4. Revalidate exact instance and current owner between pre-, global-, after-,
   and standard-attack phases.
5. Test that 云雾十三式 suppresses an earlier-row 苍松迎客 reaction before the
   global summoned groups are discovered/resolved.

## Task 5: Add generic before-move resolution

**Files:**

- Modify: `scripts/card_catalog.gd`
- Modify: `scripts/duel_triggers.gd`
- Modify: `scripts/duel_ability_executor.gd`
- Modify: `scripts/duel_simulator.gd`
- Extend: `tests/test_hengshan_three_families.gd`

1. Register `CARD_BEFORE_MOVED` and
   `CONDITION_MOVING_CARD_IS_SELF` with strict validation.
2. Thread a synchronous before-move resolver callable through activation,
   trigger-group, recursive selected-card, move, and swap execution paths.
3. Before each `_move_card_between_cells` mutation, perform initial legality,
   resolve `CARD_BEFORE_MOVED` with exact mover/source/target context, then
   revalidate the same request.
4. Merge all nested captures, exiles, events, and serviced requests before
   appending the existing `card_moved` event.
5. Keep the approved swap reservation sequence. Fire one before-move event for
   the source card while the target is reserved, and one for the target card
   after it is restored and the source is reserved.
6. Preserve adjacency checks in every swap action. A moved target that is no
   longer adjacent returns `NO_EFFECT`.
7. Add `ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY`, choosing the lowest row-major
   empty neighbor and returning `NO_EFFECT` when none exists.
8. Test ordinary activation movement, automatic movement, both swap movers,
   initial invalid requests, and event ordering before `card_moved`.

## Task 6: Extend event-aware selection and source tracking

**Files:**

- Modify: `scripts/card_catalog.gd`
- Modify: `scripts/duel_card_selector.gd`
- Modify: `scripts/duel_ability_executor.gd`
- Modify: `scripts/duel_triggers.gd`
- Modify: `scripts/duel_simulator.gd`
- Extend: `tests/test_hengshan_three_families.gd`

1. Register `CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE`,
   `CONDITION_SOURCE_HAS_ADJACENT_EMPTY_CELL`, and
   `CONDITION_SELECTED_CARD_FLIPPED_BY_CURRENT_ATTACK`.
2. Pass a deep-copied event context into selector snapshot and revalidation.
3. Match attack-flipped candidates by exact `instance_id` in `attack_flips`,
   not current owner or historical cell.
4. Include the attacker's current exact cell in `TRIGGER_CARD_AFTER_ATTACK`
   context so `CONDITION_ATTACKER_CARD_IS_SELF` remains valid after movement.
5. Make `for_each_selected_card` relocate the ability source after nested
   actions and return that current cell to outer action sequencing.
6. Preserve `required_count` and `STOP_RULE`: zero/multiple targets or a failed
   adjacency-only swap prevents tier-three follow-up attack.
7. Test direct-flip-only summaries, nested attacks as separate summaries,
   still-adjacent movement success, non-adjacent movement failure, removal, and
   fresh-instance replacement.

## Task 7: Declare all eight cards

**Files:**

- Modify: `scripts/card_catalog.gd`
- Extend: `tests/test_hengshan_three_families.gd`

1. Declare shared English-constant ability dictionaries only; keep all
   player-visible descriptions and existing non-ability card data unchanged.
2. Give 云雾十三式2 the pre-summon all-enemy suppression declaration.
3. Give 云雾十三式3 the same suppression plus exactly-one-adjacent-enemy
   after-summon swap.
4. Leave 一剑落九雁1 with no abilities.
5. Give 一剑落九雁2 exactly-one-current-attack-flip adjacency-only swap.
6. Give 一剑落九雁3 the same swap with `STOP_RULE`, then standard attack from
   the ability source's new cell.
7. Give 天柱云气2–4 the adjacent-enemy summon reaction and lowest-index move;
   append draw only to tiers three and four after successful movement.
8. Give 天柱云气4 the independent all-movement `CARD_BEFORE_MOVED`
   suppression declaration.
9. Validate declarations and confirm no runtime named-card checks exist.

## Task 8: Add production integration and documentation

**Files:**

- Create: `tests/test_hengshan_three_families_integration.gd`
- Modify: `tools/run_tests.ps1`
- Modify: `docs/HANDOFF.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/DECISIONS.md`
- Modify: `docs/ADDING_CARDS_AND_ABILITIES.md`
- Modify: `docs/TESTING.md`

1. Drive a production controller fixture with fast presentation durations.
2. Verify ability-loss/gain events refresh exact card views and ki beads.
3. Verify automatic movement, swap, draw, and follow-up attack reuse existing
   controller presentation without card-specific branches.
4. Verify ability pulse ordering and no duplicate movement presentation.
5. Register the integration suite and document all reusable timing/state rules,
   declarations, tests, and maintenance cautions.

## Task 9: Verify and commit

**Files:**

- Review every modified production, test, and documentation file

1. Run the focused rules and integration suites.
2. Run catalog, selector, simulator, search, replay, movement/swap,
   ki-presentation, and nearest ability regression suites.
3. Run the complete `tools/run_tests.ps1` and require every suite to pass.
4. Check all changed GDScript files with Summer script diagnostics.
5. Start the production duel scene, walk a golden-path fixture through each of
   the three families where tooling permits, then inspect console, debugger,
   and overall diagnostics.
6. Run `git diff --check`, inspect the exact diff/status, and preserve unrelated
   user changes.
7. Create one focused local implementation commit. Do not push.
