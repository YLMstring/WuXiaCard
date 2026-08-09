# 剑发琴音、雁回祝融与额外出牌 Implementation Plan

**Spec:** `docs/superpowers/specs/2026-08-09-jianfa-yanhui-extra-card-play-design.md`

**Goal:** Implement 剑发琴音1–3 and 雁回祝融3–4 through reusable English
catalog declarations, replace extra turns with stackable play-only action
windows, shuffle both opening hands, and migrate 万花剑法/金针渡劫 away from
their card-shaped executor actions.

**Architecture:** `DuelSimulator` remains authoritative. `DuelState` stores the
play-only allowance and owner-turn lifecycle separately from action-count
progress. Catalog declarations refer to generic card and cell references;
`DuelAbilityExecutor` resolves those references and delegates full summon timing
back to the simulator. Controller, AI, replay, and testing mode consume the same
state and transitions.

---

## Task 1: Establish the green baseline

**Files:**

- Read: `AGENTS.md`
- Read: `docs/HANDOFF.md`
- Run: `tools/run_tests.ps1`

1. Confirm the worktree contains no uncommitted user changes.
2. Run all current suites before production edits.
3. Record any pre-existing warnings separately; do not fix unrelated warnings.

## Task 2: Add focused failing tests for the new contract

**Files:**

- Create: `tests/test_jianfa_yanhui_extra_card_play.gd`
- Modify: `tools/run_tests.ps1`
- Extend: `tests/test_duel_simulator.gd`
- Extend: `tests/test_jinzhen_wanhua_abilities.gd`

1. Assert registration and validation of all new English target, condition,
   action, card-reference, card-specification, cell-reference, and owner IDs.
2. Assert the exact catalog declarations for 剑发琴音1–3 and 雁回祝融3–4.
3. Add red tests for opening-hand shuffle determinism and independence.
4. Add red tests for stackable extra-card-play allowances, play-only legal
   actions, one end/start dispatch per owner turn, same-turn temporary ability
   retention, unusable allowance expiry, and Meng Huo request coalescing.
5. Add red tests for generic return/summon card references and initial-cell
   references, including full hands and stale exact instances.
6. Convert existing 万花剑法 and 金针渡劫 assertions to require generic action
   declarations while preserving all runtime outcomes.
7. Run the focused suites and confirm they fail only for missing new behavior.

## Task 3: Model extra-card-play state exactly

**Files:**

- Modify: `scripts/duel_state.gd`
- Modify: `scripts/duel_state_key.gd`
- Modify: `scripts/duel_simulator.gd`
- Modify: `scripts/duel_search.gd`
- Extend: `tests/test_duel_simulator.gd`
- Extend: `tests/test_duel_search.gd`

1. Add copied/serialized fields for remaining extra card plays, whether end-turn
   triggers resolved for the current owner turn, and a stable owner-turn serial.
2. Keep `turn_count` as successful action count so every extra play remains
   visible to replay/search and the 200-action guard.
3. Restrict legal-action generation to hand plays whenever an allowance is
   being consumed; activation actions must be absent and rejected as illegal.
4. Consume one allowance at the start of each play-only action, then merge any
   newly granted allowances produced during its resolution.
5. Split action completion from owner-turn completion. Continue with the same
   owner while a legal allowance remains; dispatch end-owner-turn once; allow
   Meng Huo to add one post-end play; then clean up and dispatch the next
   owner's start trigger without repeating end triggers.
6. Restore temporary abilities by owner-turn serial only when that complete
   multi-action turn finally closes.
7. Drop unusable allowances when the owner has no legal hand play, without
   delaying a terminal full board.
8. Include every new field in compact search keys and duplicate-state equality
   expectations.

## Task 4: Replace extra-turn vocabulary and presentation

**Files:**

- Modify: `scripts/card_catalog.gd`
- Modify: `scripts/duel_ability_executor.gd`
- Modify: `scripts/duel_simulator.gd`
- Modify: `scripts/duel_controller.gd`
- Modify: `scripts/duel_search.gd`
- Modify: `scripts/extra_turn_vfx.gd`
- Extend: `tests/test_duel_integration.gd`

1. Replace `ACTION_REQUEST_EXTRA_TURN` with
   `ACTION_GRANT_EXTRA_CARD_PLAY`, validating a positive `amount`.
2. Change Meng Huo's end-turn declaration to the new action while retaining
   all-source ki spend and one-grant-per-batch coalescing.
3. Replace `extra_turn_granted` with `extra_card_play_granted`, carrying owner,
   amount, and source instance IDs as pure data.
4. Remove golden convergence beads from the production VFX. Retain only the
   short gold board outline and status feedback, labeled `额外出牌`.
5. Make the controller enable only the active owner's hand during a play-only
   window; board activations remain disabled.
6. Let the existing opponent action coordinator launch a fresh full-budget
   search for every new allowance window. No search continuation or shared
   deadline crosses actions.
7. Update move ordering/event heuristics to recognize the renamed event without
   named-card logic.

## Task 5: Shuffle both opening hands

**Files:**

- Modify: `scripts/duel_controller.gd`
- Extend: `tests/test_enemy_memory.gd`
- Extend: `tests/test_duel_replay.gd`

1. Add `player_hand_shuffle_seed` with the same semantics as the existing
   opponent seed: zero randomizes, positive values reproduce, negative values
   leave catalog/profile order untouched for fixtures.
2. Shuffle player and opponent main-deck ID arrays independently before
   creating runtime instances and deriving replay initial state.
3. Preserve deck membership/mastery eligibility independently from shuffled
   physical hand order.
4. Verify replay captures the exact shuffled opening hands and enemy memory
   remains glyph-based rather than slot-based.

## Task 6: Implement generic card return and summon references

**Files:**

- Modify: `scripts/card_catalog.gd`
- Modify: `scripts/duel_ability_executor.gd`
- Modify: `scripts/duel_simulator.gd`
- Modify: `scripts/duel_card_selector.gd`
- Extend: `tests/test_jinzhen_wanhua_abilities.gd`

1. Register `ACTION_RETURN_CARD_TO_HAND` and `ACTION_SUMMON_CARD` with strict
   schemas for card references, recipients, fresh-copy specs, initial cells, and
   first-adjacent-empty cells.
2. Snapshot the referenced exact instance IDs, catalog IDs, initial owners, and
   initial board cells at rule-group start. Do not create a reservation zone.
3. Implement return as exact-instance removal plus a fresh catalog hand copy for
   the declared recipient. A full recipient hand removes the old instance.
4. Implement summon from either an exact currently selected hand instance or a
   fresh copy of a referenced card. Delegate before/global/after summon phases
   and standard attack to the simulator's common summon resolver.
5. Revalidate the exact selected hand instance immediately before it is played;
   stale or moved references skip without rolling back prior actions.
6. Delete `ACTION_RETURN_SELF_TO_ABILITY_SOURCE_HAND` and migrate 金针渡劫 to
   selected-card plus `OWNER_ABILITY_SOURCE`.
7. Delete `ACTION_SUMMON_FRESH_COPY_IN_FIRST_ADJACENT_EMPTY` and migrate
   万花剑法 to the new fresh-copy and adjacent-cell declaration.
8. Preserve current fade/exile/ink-summon event ordering and all retained-on-
   flip behavior.

## Task 7: Implement 剑发琴音 declarations and movement

**Files:**

- Modify: `scripts/card_catalog.gd`
- Modify: `scripts/duel_triggers.gd`
- Modify: `scripts/duel_ability_executor.gd`
- Extend: `tests/test_jianfa_yanhui_extra_card_play.gd`

1. Register `CONDITION_SOURCE_HAS_EMPTY_BETWEEN_ENEMY` and
   `ACTION_MOVE_SELF_TO_FIRST_EMPTY_BETWEEN_ENEMY`.
2. Find orthogonal source-empty-enemy lines and choose the lowest-index middle
   cell when multiple directions qualify.
3. Route the move through existing before-move timing and revalidation.
4. Declare tiers 1–3 after-summon movement and verify the normal attack resolves
   from the source's new exact cell.
5. Declare tier 2–3 adjacent-empty activations: spend one ki, move with
   `STOP_RULE`, then grant exactly one extra card play.
6. Give tier 3 the same all-source before-move temporary suppression declaration
   already used by 天柱云气4.

## Task 8: Implement 雁回祝融 declarations

**Files:**

- Modify: `scripts/card_catalog.gd`
- Modify: `scripts/duel_targeting.gd`
- Modify: `scripts/duel_ability_executor.gd`
- Modify: `scripts/duel_simulator.gd`
- Extend: `tests/test_jianfa_yanhui_extra_card_play.gd`

1. Register `TARGET_OTHER_ALLY_BOARD`; it must exclude the exact ability source.
2. Declare the shared before-flip hand selector for the leftmost light sword,
   requiring exactly one selected result after applying limit one.
3. Return the ability source to its owner's hand, or remove it when full; then
   summon the still-present exact selected sword at the source's initial cell.
4. Verify the replacement resolves all summon phases and standard attack, and
   the original committed flip stops because its exact target left the board.
5. Give tier 4 one ki and the other-ally activation. Return/remove the exact
   target, then summon a fresh source catalog copy at the target's initial cell.
6. Require a legal vacated cell immediately before summon; a later occupation
   skips the summon without restoring the returned card.

## Task 9: Update documentation and production integration

**Files:**

- Create: `tests/test_jianfa_yanhui_extra_card_play_integration.gd`
- Modify: `tools/run_tests.ps1`
- Modify: `docs/HANDOFF.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/DECISIONS.md`
- Modify: `docs/ADDING_CARDS_AND_ABILITIES.md`
- Modify: `docs/AI_SEARCH.md`
- Modify: `docs/TESTING.md`

1. Drive production controller fixtures through a player extra play, testing-
   mode opponent extra play, AI extra play, and both new card families.
2. Assert only hand cards become playable, every AI allowance schedules a new
   decision, and replay records each successful extra action once.
3. Verify movement, return fade/removal, summon, attack, and board-outline event
   presentation ordering with fast durations.
4. Assert the extra-play VFX creates no golden bead children or convergence
   trace while retaining one board pulse per grant event.
5. Document the new owner-turn lifecycle, generic references, migrated actions,
   opening shuffle seeds, card declarations, and maintenance cautions.

## Task 10: Verify and commit

**Files:**

- Review every modified production, test, and documentation file

1. Run the focused rules and integration suites.
2. Run catalog, selector, simulator, search, replay, enemy-memory,
   JinZhen/WanHua, temporary-suppression, and duel integration regressions.
3. Run the complete `tools/run_tests.ps1` and require every suite to pass.
4. Check every changed GDScript with Summer script diagnostics.
5. Start the production scene in testing mode and walk: player opening shuffle,
   剑发琴音 activation then extra hand play, 雁回祝融 before-flip replacement,
   雁回祝融4 other-ally activation, Meng Huo post-end extra play, and migrated
   万花剑法/金针渡劫 paths where tooling permits.
6. Probe no-hand/no-cell allowance expiry, repeated extra plays, and inspection
   during the restricted action window; inspect console/debugger afterward.
7. Run `git diff --check`, inspect exact status/diff, and preserve unrelated
   user changes.
8. Create one focused local implementation commit. Do not push.
