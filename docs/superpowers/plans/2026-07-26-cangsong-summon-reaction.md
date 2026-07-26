# CangSong Summon Reaction Implementation Plan

**Goal:** Implement CangSongYingKe2’s declarative summon reaction through the shared simulator so live play, testing mode, greedy fallback, and deep search all resolve it identically.

**Design reference:** `docs/superpowers/specs/2026-07-26-cangsong-summon-reaction-design.md`

**Architecture:** Extend the existing catalog trigger vocabulary, route all source-target attack checks through one context-aware rules query, and let `DuelTriggers` emit pure attack requests for `DuelSimulator` to resolve. The controller remains presentation-only and learns only to tolerate a played card that the completed simulation has already flipped or removed.

## Task 1: Lock the catalog schema and migrate Meng Huo

**Files:**

- Modify: `tests/test_card_catalog.gd`
- Modify: `scripts/card_catalog.gd`

**Steps:**

1. Add failing catalog assertions for:
   - `EFFECT_WELCOMING_PINE`;
   - `TRIGGER_CARD_SUMMONED`;
   - `CONDITION_TRIGGER_CARD_IS_ENEMY`;
   - `CONDITION_TRIGGER_CARD_IN_RANGE`;
   - `TRIGGER_ACTION_ATTACK_TRIGGER_CARD`;
   - CangSongYingKe2’s exact approved trigger declaration;
   - default `retained_on_flip = false` on its runtime effect.
2. Change Meng Huo’s end-turn rule test from the old singular `condition` dictionary to:

   ```gdscript
   "conditions": [
       {"type": CONDITION_KI_AT_LEAST, "amount": 1},
   ]
   ```

3. Add malformed-schema fixtures covering:
   - unknown trigger event;
   - `conditions` that is not an array;
   - a non-dictionary condition;
   - unknown condition type;
   - missing, non-integer, or negative `ki_at_least.amount`;
   - unsupported fields on conditions and actions;
   - unknown action type.
4. Run the catalog suite directly and confirm the new assertions fail for missing vocabulary/schema support.
5. Add the approved identifiers to the known effect, event, condition, and action sets.
6. Declare CangSongYingKe2’s effect in `_CARD_DEFINITIONS`.
7. Migrate Meng Huo’s declaration to `conditions`.
8. Make trigger validation generic for every trigger-bearing known effect:
   - allow only `event`, `conditions`, and `actions`;
   - treat missing or empty `conditions` as valid;
   - validate each typed condition dictionary;
   - keep actions non-empty and validate allowed fields per action type.
9. Re-run `test_card_catalog.gd` and confirm all catalog/schema checks pass.

## Task 2: Add one authoritative source-target attack query

**Files:**

- Modify: `tests/test_duel_rules.gd`
- Modify: `scripts/duel_rules.gd`

**Steps:**

1. Add failing tests for `can_attack_target(board, source_cell, target_cell, context)`:
   - greater power against an orthogonal enemy succeeds;
   - equal power fails;
   - diagonal and non-neighbor cells fail;
   - friendly ownership fails;
   - missing or invalid source/target cells fail;
   - horizontal row wrapping fails;
   - a context dictionary such as `{"reason": &"card_summoned_reaction"}` is accepted without changing today’s result.
2. Add a regression assertion that `get_would_flip_indices()` retains top-right-bottom-left ordering and returns the same targets through the new query.
3. Implement the typed, pure source-target query using canonical direction geometry and opposing power indices.
4. Refactor `get_would_flip_indices()` to call the query instead of duplicating comparison logic.
5. Run `test_duel_rules.gd` and `test_duel_simulator.gd` to prove baseline standard attacks retain their behavior.

## Task 3: Discover and revalidate composable summon triggers

**Files:**

- Modify: `tests/test_duel_simulator.gd`
- Modify: `scripts/duel_triggers.gd`

**Steps:**

1. Add focused trigger-layer fixtures that fail until:
   - `TRIGGER_CARD_SUMMONED` scans sources in board-cell order `0..8`;
   - trigger context preserves the triggering cell, instance ID, owner, and summon reason;
   - all declared conditions are ANDed;
   - Meng Huo’s migrated ki condition still gates its end-turn actions;
   - source instance, current owner, active effect, trigger index, trigger target identity, and conditions are revalidated at resolution time.
2. Extend discovery:
   - retain source-only discovery for successful-flip triggers;
   - retain owner-wide discovery for end-turn triggers;
   - scan every occupied board cell for summon triggers;
   - copy the trigger context into each discovered group.
3. Replace the singular condition helper with an array-based evaluator:
   - `CONDITION_KI_AT_LEAST` reads the current source card’s ki;
   - `CONDITION_TRIGGER_CARD_IS_ENEMY` compares current owners;
   - `CONDITION_TRIGGER_CARD_IN_RANGE` calls `DuelRules.can_attack_target()` with the summon-reaction context.
4. Extend `resolve()` to return an `attack_requests` array alongside existing `events` and `extra_turn_requests`.
5. For `TRIGGER_ACTION_ATTACK_TRIGGER_CARD`, append a pure-data request containing stable source and target cells, instance IDs, owners, effect ID, and reason. Do not mutate combat state in `DuelTriggers`.
6. Re-run catalog and simulator suites. Existing Meng Huo trigger behavior must remain unchanged.

## Task 4: Resolve summon reactions before on-play effects

**Files:**

- Modify: `tests/test_duel_simulator.gd`
- Modify: `scripts/duel_simulator.gd`

**Steps:**

1. Add test helpers that build runtime cards with generic effects and stable instance IDs; avoid named-card checks in simulator logic.
2. Add failing simulator cases for:
   - an in-range CangSong reaction flips a newly played enemy before its normal attack;
   - a reacted Fa Zheng/Strategist does not draw;
   - no reaction occurs for equal power, diagonal placement, friendly summon, lost ability, or failed range;
   - multiple potential reactors are considered in board-cell order;
   - later reactors stop after the trigger card changes ownership;
   - an exile replacement on the reacting source removes the trigger card and stops the chain;
   - the triggering card’s stable instance ID prevents a different occupant from being attacked;
   - a reaction flip still invokes existing `TRIGGER_AFTER_SUCCESSFUL_FLIP_BY_SELF` behavior;
   - an interrupted summon still finishes the turn;
   - event order starts with `card_placed`, then existing flip/exile/lost/ki events, with no draw event and no newly invented reaction/interruption event.
3. Extract a shared single-target attack resolver from `_resolve_attacks()`:
   - call the existing `Effects.resolve_flip_attempt()`;
   - classify captures and exiles;
   - run existing successful-flip triggers;
   - return ordered events.
4. Make standard four-direction attacks call that single-target resolver, preserving their current target order.
5. Add a summon-reaction resolver used immediately after `card_placed`:
   - accept an explicit summon reason/context so future effect-created summons can call the same entry point without duplicating rules;
   - discover groups with the summoning cell, instance ID, original summoning owner, and `&"hand_play"` reason;
   - resolve one group at a time;
   - revalidate and execute returned attack requests through the shared single-target attack resolver;
   - aggregate captures, exiles, and events;
   - after each group, stop if the trigger card left its cell, changed instance, or no longer belongs to the summoning owner.
6. In `_apply_play_action()`, run that resolver before `resolve_on_play_effects()` and the card’s standard attack.
7. If the trigger card was interrupted, skip both remaining phases but still call `_finish_turn()`.
8. Keep `_apply_activate_action()` unchanged apart from using the refactored standard attack helper; movement must not discover `TRIGGER_CARD_SUMMONED`.
9. Run `test_duel_simulator.gd` and confirm all old and new state/event assertions pass.

## Task 5: Prove search uses the simulator behavior

**Files:**

- Modify: `tests/test_duel_search.gd`

**Steps:**

1. Add a small deterministic position with two otherwise plausible play choices where one summon is immediately punished by the generic reaction.
2. Assert `Simulator.apply_action()` produces the reaction in the search fixture.
3. Run fixed-depth search twice and assert it:
   - returns the same canonical action both times;
   - evaluates descendants containing the resolved reaction rather than an unreacted board;
   - chooses the safer/better move established by the fixture.
4. Do not add any CangSong card-ID branch to search, move ordering, or evaluation.
5. Run `test_duel_search.gd` twice to check deterministic output and state-key compatibility.

## Task 6: Make live presentation tolerate immediate flip or removal

**Files:**

- Modify: `tests/test_duel_integration.gd`
- Modify: `scripts/duel_controller.gd`

**Steps:**

1. Add production-path integration fixtures for both outcomes:
   - a summoned card is immediately flipped;
   - a summoned card is immediately exiled by a reacting source carrying the generic exile replacement.
2. Assert after each committed action:
   - no null-slot/script error occurs;
   - `board_cards` matches the simulator’s final board;
   - a flip keeps the same view instance and syncs its new owner/effect state;
   - an exile briefly presents the played view, then clears and frees it;
   - existing `card_flipped`, `ability_lost`, or `card_exiled` trace entries occur in transition order;
   - no draw view is spawned when the summon was interrupted.
3. Adjust `_commit_action()` so placement presentation does not blindly cast `duel_state.board[target]` to a dictionary:
   - reparent/register the played view before presenting events;
   - keep its pre-transition owner/effect/ki data while ordered events animate, so a reaction flip changes ownership at the existing flip-animation midpoint;
   - after presentation, reconcile a surviving view with the final logical slot only when the slot still contains the same `instance_id`;
   - if the final slot is empty, let the existing exile event animate and free the registered view without attempting a dictionary cast.
4. Keep all reaction decisions in `DuelSimulator`; the controller only consumes final state and existing events.
5. Run `test_duel_integration.gd` in normal and testing-mode paths.

## Task 7: Update maintainer documentation

**Files:**

- Modify: `docs/ADDING_CARDS_AND_EFFECTS.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/DECISIONS.md`
- Modify: `docs/HANDOFF.md`
- Modify: `docs/KNOWN_ISSUES.md`
- Modify: `docs/REPLACEMENT_AI_PROMPT.md`

**Steps:**

1. Document the typed `conditions` array, AND semantics, summon context, and pure attack-request boundary.
2. Add CangSongYingKe2 under implemented abilities and record its pre-on-play interruption timing.
3. Remove statements that its printed effect is unimplemented.
4. Keep the broader queued-choice/reaction engine listed as deferred; this deterministic automatic reaction does not create that engine.
5. Confirm all documentation describes simulator authority and contains no named-card search logic.

## Task 8: Full verification and focused commit

**Steps:**

1. Run the canonical full suite:

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
   ```

2. If the local shell still exposes duplicate case-variant `Path`/`PATH` entries and `Start-Process` rejects the environment, run every listed suite directly with the same Summer executable and record that environment issue separately; do not change gameplay code to hide it.
3. Run the game at the 540×960 portrait viewport.
4. In testing mode, manually place an enemy card:
   - inside CangSongYingKe2’s valid range and confirm immediate existing flip feedback;
   - outside its range and confirm normal on-play/attack resolution;
   - after CangSongYingKe2 has lost its effect and confirm no reaction.
5. In normal mode, confirm the AI searches and commits through the same reaction path without UI desynchronization.
6. Check fresh runtime diagnostics for script errors, invalid dictionary casts, orphaned card views, and unexpected new audio/VFX.
7. Audit `git diff` and `git status`; preserve unrelated user changes.
8. Commit the implementation and documentation as one focused behavior commit. Do not push.
