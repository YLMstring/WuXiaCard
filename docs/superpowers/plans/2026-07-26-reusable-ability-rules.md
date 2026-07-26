# Reusable Ability Rules Implementation Plan

**Design source:** `docs/superpowers/specs/2026-07-26-reusable-ability-rules-design.md`

**Scope:** Atomically migrate every current card ability from named effect IDs
and bespoke resolution to identity-free declarative abilities. Preserve all
unrelated gameplay, AI budgets, visuals, sounds, and user-owned settings.

**Baseline:** 7 suites, 772 checks passing on 2026-07-26.

## Checkpoint 1 — Lock the New Catalog Contract

**Files**

- Modify `tests/test_card_catalog.gd`
- Modify `scripts/card_catalog.gd`

**Tests first**

Add assertions for:

- `abilities` replacing `effects`;
- `active_abilities` replacing `active_effects`;
- no ability `id`;
- exact declarations for CangSongYingKe2, Fa Zheng, Strategist, Gate General,
  Tiger General, Meng Huo, Jiang Wei, and Sun Zan;
- default `retained_on_flip = false`;
- multiple passive abilities being valid;
- more than one activation being rejected;
- trigger, condition, action, target, input, cost, and invalid-context-policy
  validation;
- `on_invalid_context` omitted or equal to `STOP_RULE`;
- old `id`, `draw_count`, flat activation, and unknown vocabulary being
  rejected.

**Implementation**

- Replace effect-ID constants with the approved event, condition, action,
  activation-input, target-rule, action-result, and invalid-context constants.
- Rewrite all current card declarations.
- Rename definition and instance fields.
- Normalize abilities without injecting any ID.
- Validate trigger and activation shapes structurally.
- Validate action-specific fields and positive/nonnegative amounts.
- Keep card IDs and all display metadata unchanged.

**Focused verification**

Run `test_card_catalog.gd`.

## Checkpoint 2 — Migrate Runtime Ability and Action Identity

**Files**

- Add `scripts/duel_abilities.gd`
- Modify `scripts/duel_action.gd`
- Modify `scripts/duel_rules.gd`
- Modify `scripts/duel_state.gd`
- Modify `scripts/duel_state_key.gd`
- Modify `scripts/duel_evaluator.gd`
- Modify `scripts/duel_targeting.gd`
- Modify catalog and search fixtures that directly construct cards/actions

**Tests first**

Add or migrate coverage for:

- activation lookup by structure;
- activation replacement preserving passive entries;
- `card_uses_ki` checking activation presence only;
- action equality and canonical keys without `ability_id`;
- deep-copy isolation of nested `active_abilities`;
- state keys changing when active ability data changes.

**Implementation**

- Move activation lookup/replacement, retention removal, and ki-use queries into
  `DuelAbilities`.
- Remove `ability_id` from `DuelAction`; activation identity is source
  `instance_id` plus current structural activation.
- Rename fixture/runtime/state-key/evaluator fields to `active_abilities`.
- Make targeting read `activation.target_rule`.
- Preserve deterministic action enumeration and canonical ordering.

**Focused verification**

Run catalog, rules, and search suites.

## Checkpoint 3 — Build the Generic Ability Executor

**Files**

- Add `scripts/duel_ability_executor.gd`
- Rewrite `scripts/duel_triggers.gd`
- Replace or remove obsolete responsibilities in `scripts/duel_effects.gd`
- Modify `tests/test_duel_simulator.gd`

**Tests first**

Add isolated cases for:

- `ACTION_DRAW_CARDS`;
- `ACTION_EXILE_ATTACKED_CARD`;
- `ACTION_ATTACK_TRIGGER_CARD`;
- `ACTION_GAIN_KI`;
- `ACTION_SPEND_KI`;
- `ACTION_SPEND_ALL_KI`;
- `ACTION_REQUEST_EXTRA_TURN`;
- `ACTION_MOVE_SELF_TO_TARGET`;
- `ACTION_STANDARD_ATTACK_WITH_SELF`;
- all activation costs validating before payment;
- default stale context returning `NO_EFFECT` and continuing;
- explicit `on_invalid_context: STOP_RULE` stopping only that rule;
- already-paid costs remaining spent;
- stable `instance_id`, expected-zone, cell, and current-owner revalidation.

**Implementation**

- Represent trigger groups with source cell, source instance, ability index,
  trigger index, event ID, and deep-copied context.
- Revalidate the source card and indexed rule without an ability ID.
- Centralize condition evaluation.
- Execute costs/actions in declared order and return typed attack and extra-turn
  requests.
- Keep draw, ki, exile, movement, flip retention, and transition generation in
  pure state code.
- Make `ability_lost` identity-free.

**Focused verification**

Run simulator tests after each action family is implemented.

## Checkpoint 4 — Adopt the New Simulator Phases

**Files**

- Modify `scripts/duel_simulator.gd`
- Modify `scripts/duel_triggers.gd`
- Modify `scripts/duel_ability_executor.gd`
- Modify `tests/test_duel_simulator.gd`
- Modify `tests/test_duel_search.gd`

**Tests first**

Cover:

- row-major global discovery, then ability and trigger array order;
- summon sequence: place, `TRIGGER_CARD_SUMMONED`,
  `TRIGGER_CARD_AFTER_SUMMONED`, standard attack, turn end;
- non-retained draw lost after CangSong flip;
- retained after-summoned draw for the new owner;
- no after-summoned rule after exile, movement, or replacement;
- standard summon attack requiring the exact instance, original cell, and
  summoning owner;
- `CARD_BE_ATTACKED` before every attack source;
- Gate/Tiger exile making the original attack fail final revalidation;
- stale attacked-card exile doing nothing;
- Meng Huo ki only after an actual ownership flip;
- multiple Meng Huos spending all ki for one total extra turn;
- activation move and standard attack using the shared attack path;
- unchanged greedy and deep-search deterministic behavior.

**Implementation**

- Replace on-play and flip-replacement branches with event/rule execution.
- Give every attack an exact attacker/target context and pre-resolution
  `CARD_BE_ATTACKED` event.
- Revalidate the original attack after all triggers.
- Resolve typed attack requests through the same attack procedure.
- Resolve after-summoned rules from the summoned instance's current retained
  abilities and current owner.
- Deduplicate extra-turn requests at the simulator boundary.

**Focused verification**

Run simulator and search suites.

## Checkpoint 5 — Migrate Presentation and Live Input

**Files**

- Modify `scripts/duel_controller.gd`
- Modify `scripts/card_view.gd`
- Modify `tests/test_card_inspector.gd`
- Modify `tests/test_duel_integration.gd`

**Tests first**

Cover:

- controller-created activation actions without ability IDs;
- drag target discovery from the structural activation;
- identity-free `ability_activated`, `ki_changed`, and `ability_lost` events;
- generic ability-loss animation followed by final runtime-data sync;
- zero-ki activation cards showing the dim bead;
- zero-ki passive-only cards hiding it;
- current draw, flip, exile, move, and extra-turn presentation order.

**Implementation**

- Build actions from source instance and target only.
- Rename all view data to `active_abilities`.
- Replace remove-by-effect-ID presentation with generic loss feedback.
- Let final logical-state synchronization provide the authoritative remaining
  ability list.
- Preserve existing animation/audio timing; add no new reaction cue.

**Focused verification**

Run inspector and integration suites.

## Checkpoint 6 — Remove the Legacy Vocabulary

**Files**

- Modify all remaining scripts and tests found by repository search
- Modify `docs/HANDOFF.md`
- Modify `docs/ARCHITECTURE.md`
- Modify `docs/DECISIONS.md`
- Modify `docs/ADDING_CARDS_AND_EFFECTS.md`
- Modify `docs/TESTING.md` where terminology is user-facing

**Implementation**

- Remove remaining production/test references to:
  - `EFFECT_*`;
  - `KNOWN_EFFECT_IDS`;
  - `TRIGGER_ACTION_*`;
  - `TRIGGER_AFTER_SUCCESSFUL_FLIP_BY_SELF`;
  - `effects`;
  - `active_effects`;
  - `draw_count`;
  - `ability_id`;
  - `effect_id`.
- Update maintainer examples to the exact new declarations.
- Do not rewrite historical specs and plans; they remain historical records.
- Preserve the unrelated `scripts/game_settings.gd` user edit.

**Focused verification**

Use `rg` over production scripts, active tests, and current maintainer docs.

## Checkpoint 7 — Final Verification and Playtest

1. Run `git diff --check`.
2. Run the complete test command with process-local `Path` normalization:

   ```powershell
   $normalizedPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
   Remove-Item Env:PATH -ErrorAction SilentlyContinue
   $env:Path = $normalizedPath
   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
   ```

3. Confirm all suites pass with no `ERROR:`, `SCRIPT ERROR`, `_FAILED`, or
   `CHECK_FAILED`.
4. Run the production project at portrait dimensions.
5. Manually verify:
   - ordinary drag-and-drop play;
   - CangSong summon reaction;
   - draw after the reaction window;
   - Gate/Tiger exile;
   - Jiang Wei/Sun Zan activation and ki;
   - Meng Huo ki and extra-turn presentation;
   - AI can choose and apply actions.
6. Review `git status --short` and ensure the user's pre-existing
   `scripts/game_settings.gd` edit is neither overwritten nor included in the
   implementation commit.

## Commit Boundary

After all verification passes, commit the gameplay migration and current
maintainer-document updates together. Do not push or alter remote state.
