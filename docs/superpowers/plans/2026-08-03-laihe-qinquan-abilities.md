# LaiHeQinQuan1–5 Implementation Plan

Date: 2026-08-03

Design source:
`docs/superpowers/specs/2026-08-03-laihe-qinquan-abilities-design.md`

## Objective

Implement all five LaiHeQinQuan catalog abilities through reusable simulator
primitives, preserve hidden-information rules and AI determinism, and present
revealed cards plus the approved 70% weakened-art fade in the production duel.

## Execution Rules

- Preserve the user’s current catalog descriptions, card powers, images, and
  unrelated working-tree changes.
- Add failing tests before each behavioral layer.
- Keep `DuelSimulator` authoritative. Do not add named-card branches outside
  `card_catalog.gd`.
- Use stable instance IDs for every reveal, grant, and prevention request.
- Run the focused failing suite after each red/green step and the canonical
  full runner before completion.
- Commit locally only; do not push.

## Task 1: Establish a Clean Baseline and Dedicated Test Suite

Files:

- Create `tests/test_laihe_qinquan_abilities.gd`.
- Modify `tools/run_tests.ps1`.

Steps:

1. Run `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1` and record
   the pre-change suite count and result.
2. Add the dedicated test script to the runner immediately before the broad
   duel integration suite.
3. Give the new suite shared helpers for creating exact catalog instances,
   building a 3×3 board, applying play actions, finding events, and checking
   card reveal audiences.
4. Begin with declaration assertions for all five IDs. These assertions must
   fail while their catalog `abilities` arrays remain empty.
5. Run only the new suite and retain the red result as evidence.

## Task 2: Add and Validate the Catalog Vocabulary

Files:

- Modify `scripts/card_catalog.gd`.
- Modify `tests/test_card_catalog.gd`.
- Extend `tests/test_laihe_qinquan_abilities.gd`.

Steps:

1. Add constants for:
   - reveal hand cards;
   - permanent future-draw revelation;
   - revealed-to-self and pre-flip-enemy conditions;
   - grant-trigger-card ability;
   - prevent-trigger flip;
   - remove-current ability;
   - all/remembered reveal filters;
   - defender-power override modifiers.
2. Extend known-vocabulary arrays and validation. Require exact fields for
   recipient/filter actions, validate nested granted abilities recursively,
   validate positive integer modifier values, and allow modifier-only
   abilities.
3. Reject unsupported modifier types, extra fields, invalid filters,
   malformed nested abilities, and wrong action parameters.
4. Normalize missing `retained_on_flip` inside top-level and nested granted
   abilities without mutating catalog constants.
5. Declare the five production ability arrays exactly as approved:
   - 1: reveal all current enemy hand cards;
   - 2: reveal all plus a separate protection ability;
   - 3: reveal all, enable future reveals, plus protection;
   - 4: reveal remembered glyphs plus grant weakness to revealed summons;
   - 5: the abilities of 4 plus protection.
6. Assert the ability counts, event ordering, action fields, nested modifier,
   and default non-retention in the dedicated suite.
7. Run `test_card_catalog.gd` and the dedicated suite until catalog validation
   is green, while simulator behavior remains red.

## Task 3: Add Clone-Safe Revelation and Knowledge State

Files:

- Modify `scripts/card_catalog.gd`.
- Modify `scripts/duel_rules.gd`.
- Modify `scripts/duel_state.gd`.
- Modify `scripts/duel_state_key.gd`.
- Create `scripts/duel_revelation.gd` if revelation helpers would otherwise be
  duplicated across executor, triggers, and controller.
- Extend `tests/test_laihe_qinquan_abilities.gd`.
- Modify `tests/test_duel_search.gd` or `tests/test_duel_simulator.gd` for key
  differentiation coverage.

Steps:

1. Initialize `revealed_to_owner_ids` on catalog-created cards with their
   starting owner. Normalize the same default for hand fixtures missing it.
2. Add `remembered_glyphs_by_owner` and
   `future_draw_reveal_audiences` to `DuelState` with deep duplication.
3. Include both state fields and per-card reveal arrays in canonical state
   behavior. Card dictionaries are already encoded recursively; explicitly add
   the two new top-level state fields to `DuelStateKey.build()`.
4. Implement small generic helpers to:
   - test whether an owner has revealed an exact card;
   - reveal an exact card idempotently;
   - read remembered glyphs for an observer;
   - enable and query future-draw audiences for a hand owner.
5. Test deep-copy isolation and verify that otherwise-identical states with
   different revelation/knowledge data produce different state keys.
6. Run the dedicated suite plus state/search tests.

## Task 4: Implement Current-Hand and Future-Draw Revelation

Files:

- Modify `scripts/duel_ability_executor.gd`.
- Modify `scripts/duel_triggers.gd` as needed for exact trigger lookup.
- Modify `scripts/duel_simulator.gd` only for typed result/event plumbing.
- Extend `tests/test_laihe_qinquan_abilities.gd`.

Steps:

1. Add executor handlers for `ACTION_REVEAL_HAND_CARDS` and
   `ACTION_ENABLE_FUTURE_DRAW_REVEAL`.
2. Resolve recipients relative to the current action subject’s owner, matching
   existing recipient semantics.
3. For `REVEAL_FILTER_REMEMBERED`, compare card `glyph` against the source
   owner’s duel-start memory snapshot. Emit `card_revealed` only for newly
   revealed exact instances, in logical hand order.
4. Teach the generic draw action to consult permanent audiences after each
   successful draw. Emit `card_drawn` first and `card_revealed` second.
5. Verify:
   - LaiHe1 reveals only the cards currently present;
   - later draws remain concealed after LaiHe1;
   - LaiHe3 reveals current cards and every later draw;
   - LaiHe3’s future reveal persists after source ability loss/removal;
   - remembered filters ignore nonmatching and current-duel-only glyphs;
   - repeats and empty hands are safe no-ops.
6. Run the dedicated suite and simulator suite.

## Task 5: Implement Generic Flip Prevention and Protection Expiration

Files:

- Modify `scripts/duel_ability_executor.gd`.
- Modify `scripts/duel_triggers.gd`.
- Modify `scripts/duel_simulator.gd`.
- Modify `scripts/duel_abilities.gd` if exact indexed ability removal belongs
  in the ability utility.
- Extend `tests/test_laihe_qinquan_abilities.gd`.
- Extend `tests/test_duel_simulator.gd` for generic non-attack flip coverage if
  needed.

Steps:

1. Add typed `flip_prevention_requests` to empty executor, trigger, and
   simulator resolution results and every merge path, including nested
   selected-card/attack resolution.
2. Pass the resolving ability index and structural snapshot into action context
   from `DuelTriggers.resolve_group()`.
3. Implement `ACTION_PREVENT_TRIGGER_FLIP` so it can request prevention only
   for the exact current `CARD_BEFORE_FLIPPED` target and intended new owner.
4. After all before-flip groups resolve, have attack and non-attack flip paths
   match prevention requests. Emit one `card_flip_prevented` event and skip
   ownership change, capture recording, automatic ability loss, and
   `CARD_AFTER_FLIPPED`.
5. Implement `CONDITION_TRIGGER_CARD_WAS_ENEMY` from the completed flip’s
   pre-flip owner context.
6. Implement `ACTION_REMOVE_THIS_ABILITY` using instance ID, owner, current
   cell, ability index, and snapshot. Emit `ability_lost` once when removal
   succeeds.
7. Verify attack and non-attack prevention, repeated attempts, movement during
   before-flip resolution, removed/stale sources, enemy-flip expiration,
   owner-turn expiration, and absence of after-flip triggers when prevented.
8. Run the dedicated suite, simulator suite, CangSong/SanQin suite, and Meng Huo
   regression coverage.

## Task 6: Implement Granted Weakness and Defender Queries

Files:

- Modify `scripts/duel_abilities.gd`.
- Modify `scripts/duel_rules.gd`.
- Modify `scripts/duel_triggers.gd`.
- Modify `scripts/duel_ability_executor.gd`.
- Modify `tests/test_duel_rules.gd`.
- Extend `tests/test_laihe_qinquan_abilities.gd`.

Steps:

1. Add helpers to enumerate active modifier declarations and compute effective
   defending power with last-applicable-override semantics.
2. Change only the target-facing comparison inside
   `DuelRules.can_attack_target()` to use that effective power.
3. Implement `CONDITION_TRIGGER_CARD_REVEALED_TO_SELF` by following the exact
   trigger instance to its current board cell and checking the ability source
   owner’s reveal audience.
4. Implement `ACTION_GRANT_TRIGGER_CARD_ABILITY`. Revalidate the exact board
   instance, deep-copy and normalize the declared ability, deduplicate a
   structurally identical passive, and use existing activation replacement
   behavior for any future activation grant.
5. Emit an `ability_gained` pure-data event for successful grants.
6. Verify LaiHe4/5 grant only to revealed enemy summons; testing-mode visual
   exposure does not qualify; defensive comparisons use 1; attack powers and
   stored/display powers remain original; source loss does not remove the
   granted effect; target flip removes it; duplicate grants are idempotent.
7. Run duel-rules, dedicated ability, simulator, and search tests.

## Task 7: Wire Production Memory and Presentation

Files:

- Modify `scripts/main_flow_controller.gd`.
- Modify `scripts/duel_controller.gd`.
- Modify `scripts/card_view.gd`.
- Modify `tests/test_main_flow.gd`.
- Modify `tests/test_duel_integration.gd` or add focused controller cases to
  `tests/test_laihe_qinquan_abilities.gd`.

Steps:

1. Add a duel-controller input for remembered enemy glyphs. Load the current
   profile snapshot in `_show_duel()` and pass it before adding the duel scene
   to the tree.
2. Copy the snapshot into `DuelState` before `_replay_record.begin()`.
3. Centralize opponent-hand concealment in a helper that returns concealed only
   when normal mode is active and the player has not revealed that exact card.
   Use it for opening hands, drawn/added cards, synchronization, and replay view
   rebuilding.
4. Present `card_revealed` by finding the exact hand view, synchronizing its
   runtime data, turning it face-up, and leaving enemy ownership styling red.
   The now-revealed view must support inspection but not unauthorized play.
5. Add a `CardView` refresh path that checks active defender-power modifiers
   and sets only `Overlay/CardPicture.self_modulate.a` to `0.70`; otherwise use
   `1.0`. Face-down cards still hide the picture completely.
6. Ensure `ability_gained`, `ability_lost`, flip synchronization, replay
   rebuilding, and ordinary runtime synchronization refresh the fade. The
   frame, powers, ki bead, and input remain unaffected.
7. Verify production memory handoff, initial concealment, reveal persistence,
   fixed hand-slot behavior, red styling, inspection, exact 70% picture alpha,
   and restoration after weakness loss.

## Task 8: Replay, Search, Documentation, and Final Verification

Files:

- Modify `tests/test_duel_replay_record.gd` and `tests/test_duel_replay.gd` if
  the new state/presentation needs explicit assertions.
- Modify `docs/HANDOFF.md`, `docs/DECISIONS.md`, and
  `docs/ADDING_CARDS_AND_ABILITIES.md` after behavior is verified.

Steps:

1. Verify replay initial-state duplication preserves remembered glyphs and
   permanent draw audiences without revealing unrelated cards.
2. Verify replayed actions reproduce reveal events and weakened-art state while
   keeping real interactions disabled and inspection enabled.
3. Verify greedy and deep search can clone, key, evaluate, and legally use
   states containing all new fields and modifier-only abilities.
4. Run `git diff --check` and inspect the complete diff for unrelated edits.
5. Run the canonical full test command and require every suite to pass.
6. Clear Summer’s console, launch the production main flow at the portrait
   reference viewport, walk a duel containing LaiHe cards, and inspect:
   - current-hand reveal;
   - permanent future draw reveal;
   - flip prevention and both expiration paths;
   - defender weakness and the 70% central-art fade;
   - restoration after the weakened card flips;
   - replay behavior.
7. Read runtime diagnostics, console, and debugger errors. Fix any new issue and
   rerun focused plus full verification.
8. Update durable documentation with the verified vocabulary and timing.
9. Commit the complete implementation locally with a behavior-focused message;
   do not push.
