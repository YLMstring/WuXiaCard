# Zi Xia Gong and Generic Card Selection Implementation Plan

**Spec:** `docs/superpowers/specs/2026-07-31-zixia-gong-abilities-design.md`

## Objective

Implement ZiXiaGong1–4 through one reusable `ACTION_FOR_EACH_SELECTED_CARD`
wrapper, generic selected-card conditions, a current action-subject context,
permanent runtime power modification, and owner-turn start triggers. Keep
`DuelSimulator` authoritative for live play, testing mode, greedy fallback, and
deep search.

## Task 1: Establish the behavioral baseline

**Files**

- Inspect only; do not modify production files

1. Run `git status --short` and preserve all user-owned edits.
2. Run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
   ```

3. Record any pre-existing failures separately. Do not attribute an existing
   failure to this feature.
4. Confirm the current Zi Xia Gong catalog entries still have empty ability
   arrays before adding failing tests.

## Task 2: Specify and validate the generic catalog vocabulary

**Files**

- Modify `tests/test_card_catalog.gd`
- Modify `scripts/card_catalog.gd`

Add failing catalog tests for:

- `TRIGGER_START_OWNER_TURN`;
- `CARD_ZONE_HAND` and `CARD_ZONE_BOARD`;
- `ACTION_FOR_EACH_SELECTED_CARD`;
- `ACTION_ADD_POWERS`;
- `CONDITION_SELECTED_CARD_IS_ALLY`;
- `CONDITION_SELECTED_CARD_WEAPON_IS`; and
- `CONDITION_SELECTED_CARD_IS_NOT_SOURCE`.

Test one valid nested wrapper and reject:

- a missing or non-dictionary selector;
- a missing, empty, unknown, or duplicate zone;
- a non-array conditions value;
- an unknown or malformed selected-card condition;
- an empty or non-array nested action list;
- an unknown or malformed nested action;
- a zero, negative, or non-integer selector limit; and
- a zero, negative, or non-integer power amount.

Implement separate known-zone and known-selector-condition lists. Extend action
validation recursively so nested declarations use the same leaf-action schema
and invalid-context policy as root actions. `ACTION_FOR_EACH_SELECTED_CARD`
must not be accepted as an activation cost.

Run `test_card_catalog.gd` until the schema tests pass.

## Task 3: Add a pure card selector

**Files**

- Add `scripts/duel_card_selector.gd`
- Add `tests/test_duel_card_selector.gd`
- Modify `tools/run_tests.ps1`

Create a pure selector module that:

1. visits declared zones in declaration order;
2. visits the ability source owner's hand in logical slot order before the
   other owner's hand;
3. visits board cells in row-major order `0..8`;
4. evaluates selected-card conditions relative to the immutable ability
   source;
5. snapshots unique runtime `instance_id` values;
6. applies `limit` to the initial matching snapshot; and
7. can locate a snapshotted instance in its current hand or board location.

Represent each selected card with pure data only: instance ID plus its current
zone, owner, index/cell, and runtime card dictionary. Store no Nodes or visual
references.

Implement these condition semantics:

- `SELECTED_CARD_IS_ALLY`: current selected owner equals current source owner;
- `SELECTED_CARD_WEAPON_IS`: selected runtime card's `weapon` exactly equals
  the declared String;
- `SELECTED_CARD_IS_NOT_SOURCE`: selected instance differs from the immutable
  source instance.

For revalidation, look up the instance in current state and re-run only the
declared conditions. Do not re-run the original zone filter. Movement between
cells or zones therefore remains valid while all conditions remain true. A
missing instance or any false condition means the card is skipped as
`NO_EFFECT`.

Test deterministic ordering, both owners, mixed zones, limit behavior,
duplicate-zone rejection through the catalog, movement without invalidation,
ownership/weapon changes causing a skip, and missing-instance handling.

Add the new suite to `tools/run_tests.ps1` and run it independently.

## Task 4: Separate immutable ability source from current action subject

**Files**

- Modify `tests/test_duel_simulator.gd`
- Modify `scripts/duel_ability_executor.gd`
- Use `scripts/duel_card_selector.gd`

Add failing executor/simulator fixtures proving:

- root actions still treat the ability source as their subject;
- nested actions treat each selected card as their subject;
- the original source remains available to selector conditions;
- every nested action for one subject completes before the next subject;
- movement of the subject updates later nested actions without moving the
  immutable source identity;
- an empty selection returns `NO_EFFECT`; and
- a failed revalidation skips only that selected card and continues.

Refactor executor internals around two pure identities:

- immutable `ability_source`: instance ID, expected owner, and current board
  cell when present;
- mutable `action_subject`: selected or source instance, current owner, zone,
  and current index/cell.

Keep the existing public root execution entry point so activation and trigger
callers do not duplicate behavior. Root calls initialize subject from source.
The wrapper snapshots through `DuelCardSelector`, revalidates each candidate,
and recursively executes nested actions with that candidate as subject.

Leaf actions that mean “self” operate on the current subject. Action events
continue to identify the card actually changed or acting. The passive
`ability_triggered` event continues to identify the immutable ability source.

If a nested declaration explicitly uses `on_invalid_context = STOP_RULE`, its
existing meaning is preserved: propagate `INVALID_CONTEXT` and stop the whole
trigger rule, not merely the current selected card. Ordinary stale context
remains `NO_EFFECT`.

Run `test_duel_simulator.gd` after this refactor before adding Zi Xia Gong data.

## Task 5: Add permanent power modification and location-aware ki

**Files**

- Modify `tests/test_duel_simulator.gd`
- Modify `scripts/duel_ability_executor.gd`
- Verify `scripts/duel_state.gd`
- Verify `scripts/duel_state_key.gd`

Implement `ACTION_ADD_POWERS` for the current subject:

- require a positive amount;
- add it to all four runtime powers in `[top, right, bottom, left]` order;
- replace the runtime powers array with an independently owned array; and
- emit `powers_changed` with instance ID, owner, current zone/index or cell,
  previous powers, new powers, and action reason.

Generalize `ACTION_GAIN_KI` subject lookup so it can modify a selected hand or
board card. Its existing root behavior and `ki_changed` event order must remain
unchanged.

Add tests for hand and board subjects, all four edges, repeated permanent
bonuses, ordered ki/power events, non-aliased previous/new power arrays, and
state-copy isolation. Verify that `DuelState.duplicate_state()` and
`DuelStateKey` already include mutable hand/board powers; modify them only if a
failing regression test proves otherwise.

## Task 6: Add owner-turn start timing

**Files**

- Modify `tests/test_duel_simulator.gd`
- Modify `scripts/duel_simulator.gd`
- Verify `scripts/duel_triggers.gd`

Add `TRIGGER_START_OWNER_TURN` to normal global row-major trigger discovery.

After `_finish_turn` resolves end-owner-turn rules, extra-turn requests, and
chooses the next active owner:

1. dispatch `TRIGGER_START_OWNER_TURN` with the chosen `turn_owner_id`;
2. append its pure-data events after the turn-change decision;
3. resolve any generic attack requests through the normal simulator path; and
4. finish the transition before the next owner can act.

Run start-turn triggers for granted extra turns as well as ordinary owner
changes. Preserve existing end-turn and Meng Huo event order.

Test ordinary alternation, granted extra turns, multiple sources in board
order, condition revalidation, lost abilities, and no accidental start event
for the owner whose turn just ended.

## Task 7: Declare ZiXiaGong1–4 and prove gameplay behavior

**Files**

- Modify `scripts/card_catalog.gd`
- Modify `tests/test_card_catalog.gd`
- Modify `tests/test_duel_simulator.gd`

Replace the four empty ability arrays with the approved declarations:

- ZiXiaGong1: after self summon, select allied sword cards from hand and board,
  then grant each one ki;
- ZiXiaGong2: perform the same wrapper, then draw one card;
- ZiXiaGong3: at owner-turn start, select allied hand cards and add one to all
  four powers;
- ZiXiaGong4: use ZiXiaGong3's start rule and, at owner-turn end, select the
  first two allied board cards other than source and add one to all powers.

Do not add `retained_on_flip`; default non-retention is required.

Catalog tests must assert the exact nested declarations. Simulator tests must
cover:

- allied/enemy, sword/non-sword, hand/board filtering;
- post-summon reaction ordering and ability loss before after-summon;
- ZiXiaGong2 ki events before draw and the five-card hand cap;
- permanent hand bonuses on normal and extra turn starts;
- ZiXiaGong4's `0..8` first-two order and self exclusion;
- fewer than two valid targets;
- multiple sources stacking sequentially;
- ownership-relative behavior after flips; and
- no effect after the ability is permanently lost.

Run catalog and simulator suites twice to verify deterministic ordering and no
cross-run runtime mutation.

## Task 8: Present hand and board runtime changes

**Files**

- Modify `scripts/card_view.gd`
- Modify `scripts/duel_controller.gd`
- Modify `tests/test_duel_integration.gd`

Add a CardView runtime-power update API that refreshes all four labels without
changing drag, face-down, art, or ownership state.

Add one controller lookup by `instance_id` across:

- board views;
- player hand views; and
- opponent hand views.

Use it for `ki_changed` and new `powers_changed` events. Keep opponent cards
face-down in normal mode; syncing mutable data must not reveal metadata.

Preserve existing presentation sequencing:

- one passive source pulse before the wrapper's events;
- no new pulse per selected target;
- existing ki gain pulse only when its bead is visible;
- no new bespoke sound or VFX; and
- consecutive-source pulse suppression resets after each move as before.

Integration tests should verify visible hand and board power labels, hand ki
updates, face-down concealment, event traces, and one source pulse for a
multi-card effect.

## Task 9: Verify search uses the same mutable state

**Files**

- Modify `tests/test_duel_search.gd`
- Modify production search files only if a failing test requires it

Add regressions proving:

- states differing only by modified hand or board powers have different state
  keys;
- search clones do not alias mutable power arrays;
- deeper search observes start/end-trigger power changes; and
- greedy fallback and iterative deepening both call the same simulator rules
  without checking Zi Xia Gong card IDs.

Do not add a second compact rules engine. The current
`DuelStateKey.build_compact()` remains a canonical hash of the authoritative
dictionary state.

## Task 10: Update durable maintainer documentation

**Files**

- Modify `docs/ADDING_CARDS_AND_ABILITIES.md`
- Modify `docs/ARCHITECTURE.md`
- Modify `docs/DECISIONS.md`
- Modify `docs/HANDOFF.md`
- Modify `docs/TESTING.md`

Document:

- generic selector/wrapper syntax;
- source-versus-subject execution context;
- selected-card condition revalidation;
- snapshot, order, movement, limit, and skip semantics;
- `TRIGGER_START_OWNER_TURN`;
- permanent runtime power changes and `powers_changed`; and
- the Zi Xia Gong family as the canonical example.

Update suite names/count guidance after adding the selector test.

## Task 11: Final verification and playtest

1. Run focused suites:

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 `
     -Tests test_card_catalog.gd,test_duel_card_selector.gd,test_duel_simulator.gd,test_duel_search.gd,test_duel_integration.gd
   ```

2. Run the complete suite:

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
   ```

3. Run `git diff --check` and inspect the complete diff for card-specific
   branches outside `card_catalog.gd`.
4. Boot the production game at the 540×960 portrait viewport.
5. In testing mode, exercise all four cards with sword/non-sword hand and board
   targets, fewer-than-two ZiXiaGong4 targets, stacked copies, a normal next
   turn, and an extra turn.
6. In normal mode, confirm opponent hand concealment remains intact.
7. Let the production AI complete turns from states containing Zi Xia Gong and
   inspect fresh console/debugger output for divergence or script errors.
8. Commit focused implementation changes without pushing.
