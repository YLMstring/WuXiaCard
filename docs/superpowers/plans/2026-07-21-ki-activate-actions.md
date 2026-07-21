# Ki and Activate Actions Implementation Plan

**Design:** `docs/superpowers/specs/2026-07-21-ki-activate-actions-design.md`  
**Scope:** Implement only the new generalized action model, ki state, Jiang Wei/Sun Zan movement activation, drag presentation, and supporting AI/test migration. Existing side-deck, draw, Ink Summon, exile, concealment, and layout behavior are regression targets, not work to rebuild.

## Working Rules

- Keep all legality and state mutation in pure simulator/targeting code.
- Submit one complete `DuelAction` per turn; never mutate state during target selection.
- Identify cards by stable instance ID at the controller boundary.
- Spend ki only inside a fully validated copied-state transition.
- Keep activate ability and ki as separate runtime card fields.
- Preserve existing event ordering for ordinary plays.
- Write focused failing tests before each production checkpoint.
- Do not accept a headless process exit code alone; require explicit pass markers or equivalent Summer verification reports.

## Checkpoint 0: Confirm the Baseline

**Files changed:** none.

Run the current catalog, rules, simulator, and integration suites and record their exact pass markers. Also boot the portrait duel and record current diagnostics. Existing focus and integer-division warnings may be recorded as known warnings; new errors are blockers.

```powershell
$summer_bin = 'C:\Users\王异\AppData\Local\SummerEngine\current\Summer.exe'
& $summer_bin --headless --path 'C:\mygame' --script 'res://tests/test_card_catalog.gd'
& $summer_bin --headless --path 'C:\mygame' --script 'res://tests/test_duel_rules.gd'
& $summer_bin --headless --path 'C:\mygame' --script 'res://tests/test_duel_simulator.gd'
& $summer_bin --headless --path 'C:\mygame' --script 'res://tests/test_duel_integration.gd'
```

If this Summer build performs desktop-session exchange without exposing test output, run equivalent hidden `RunVerification` probes through the open editor and require named Boolean reports plus `errors_seen = []`. Do not describe an unmarked exit as a passing suite.

## Checkpoint 1: Add Catalog Ki and the Single Activate Slot

**Modify:**

- `scripts/card_catalog.gd`
- `scripts/duel_effects.gd`
- `tests/test_card_catalog.gd`

### Red

Add assertions requiring:

- `activate_move_and_attack` and `adjacent_empty_board` to be known IDs;
- Jiang Wei and Sun Zan to declare `starting_ki = 1` and one non-retained activate effect;
- every other current definition to default to zero starting ki;
- every fresh main- or side-deck instance to contain mutable `ki` initialized from the definition;
- missing starting ki to normalize to zero;
- negative and non-integer starting ki to fail validation;
- activate effects to require `activation = true` and a known target rule;
- definitions with two activate effects to fail validation;
- replacing a runtime activate effect to remove only the old activate slot while preserving on-play and replacement effects.

### Green

Add the IDs and definitions exactly as specified. Extend `create_instance` with `ki`. Add focused helpers to identify, retrieve, and replace the sole activate effect in a card's `active_effects` array. Reuse the existing default retention normalization so the new ability is lost on flip without catalog boilerplate.

Keep the global activation cost out of catalog data; define it once in the simulator/action rules at 1.

### Verify

Run the catalog suite twice and a small copy-isolation probe that mutates one Jiang Wei instance's ki and activate effect without affecting another copy or its catalog definition.

## Checkpoint 2: Introduce `DuelAction` and Pure Typed Targeting

**Create:**

- `scripts/duel_action.gd`
- `scripts/duel_targeting.gd`

**Modify:**

- `tests/test_duel_simulator.gd`

### Red

Add tests for:

- play and activate action constructors/factories containing every approved field;
- `duplicate_action()` isolation and full-field equality;
- stable ordering of top, right, bottom, left adjacent empty targets;
- no left/right row wrapping at cells `2`, `3`, `5`, and `6`;
- rejection of occupied, diagonal, source, distant, unsupported-kind, wrong-owner, missing-ability, and zero-ki targets;
- acceptance of adjacent empty movement even when no attack will succeed.

### Green

Implement `DuelAction` with pure typed fields: action type, source zone/index/instance ID, ability ID, target kind/index. Provide focused `make_play` and `make_activate` factories rather than positional constructor calls at call sites.

Implement `DuelTargeting.get_valid_targets` and `is_target_valid`. Dispatch by catalog target-rule ID. Use `DuelRules.get_neighbor_index` and canonical direction order rather than duplicating board-coordinate math.

Do not reference scenes, controls, animation, or AI policy.

### Verify

Run the focused simulator test subset or hidden pure-state probe. Confirm target generation does not mutate state.

## Checkpoint 3: Migrate Simulator Transitions and Turn Flow

**Modify:**

- `scripts/duel_simulator.gd`
- `scripts/duel_effects.gd`
- `tests/test_duel_simulator.gd`

### Red

Add simulator cases requiring:

- `get_legal_actions_for_owner` to return every play plus every valid activation;
- a complete invalid action to return the original state, spend no ki, and emit no event;
- successful movement to spend exactly 1 ki, clear the source, move the same instance, and occupy the destination;
- event order `ability_activated`, `ki_changed`, `card_moved`, then top/right/bottom/left flip/exile results;
- no-capture movement to remain valid and end the turn;
- movement not to invoke `draw_cards_on_play`;
- an existing replacement effect on a future moving fixture to transform attack attempts through the standard resolver;
- flipping Jiang Wei/Sun Zan to remove the activate effect but preserve current ki, including after flipping back;
- deep copy isolation for source/sibling board cards, ki, and effects;
- empty-hand owners with legal activations to retain a turn action;
- a full board or exhausted/lost activate ability not to prevent normal terminal behavior;
- next-owner selection and maximum-turn safeguard to work with generalized actions.

### Green

Replace `get_legal_moves`, `is_move_legal`, and `apply_move` internally with `get_legal_actions`, `is_action_legal`, and `apply_action`.

Split transition execution into focused private paths:

1. `_apply_play_action` preserves current placement, on-play draw, and attack ordering.
2. `_apply_activate_action` validates, spends ki, moves the board slot, and skips on-play resolution.
3. `_resolve_attacks_from_cell` contains the shared standard would-flip loop and existing flip/exile resolver calls.
4. `_finish_action` increments versions and selects the next owner exactly once.

Make `is_terminal` and `_get_next_active_owner` query all legal actions. Keep queued-effect handling unchanged.

After all production and test call sites migrate, delete `scripts/duel_move.gd`; do not keep two competing action representations.

### Verify

Run the simulator suite twice. Require exact event order, zero mutation on invalid paths, and no regression in draw/exile tests.

## Checkpoint 4: Migrate Greedy and Deep Search to Actions

**Modify:**

- `scripts/duel_simulator.gd`
- `scripts/duel_search.gd`
- `tests/test_duel_simulator.gd`

### Red

Add cases requiring:

- greedy AI to choose a scoring activation over a weaker play;
- greedy AI to prefer an equal-score play over spending ki;
- deterministic action choice across repeated calls;
- activation to be chosen when it is the only legal action;
- depth search to return and duplicate a complete activate action without losing source, ability, or target fields;
- search branches to retain independent ki and board locations.

### Green

Migrate search loops and return types from `DuelMove` to `DuelAction`. Preserve current evaluation. Generalize greedy tie-breaking:

1. immediate score difference;
2. play before activate on equal score;
3. boundary power at the selected board destination;
4. stable source index, target kind, and target index.

No new strategic heuristic or time-budget work belongs in this feature.

### Verify

Run simulator/search tests twice and compare repeated best-action equality.

## Checkpoint 5: Migrate the Controller's Existing Play Path

**Modify:**

- `scripts/duel_controller.gd`
- `tests/test_duel_integration.gd`

### Red

Update existing controller tests to submit play actions and require all current behavior to remain unchanged: instance-ID mapping, fixed physical slots, draw order, face-down opponent hand, placement animation, exile, testing mode, and AI continuation.

### Green

Replace `MoveData` references with `DuelAction`. Introduce one `_commit_action(action, card_view, continue_automatically)` coordinator and keep `_commit_play_card` as a small adapter for hand drag/debug calls.

Make transition completion, score update, next-turn selection, and AI continuation common to both action types. Preserve `debug_commit_move` as a compatibility-named test helper only if existing external probes need it; internally it must construct a play action. Add explicit generalized debug helpers before activation tests.

### Verify

Run the unchanged integration scenarios before adding board dragging. This checkpoint must prove the action migration alone did not alter existing gameplay.

## Checkpoint 6: Add Ki Bead State and Concealment

**Modify:**

- `scenes/card_view.tscn`
- `scripts/card_view.gd`
- `tests/test_duel_integration.gd`

### Red

Add card-view assertions for all approved display states:

- face-up `ki > 0`, no activate ability: visible numbered bead;
- face-up activate ability with `ki = 0`: visible dimmed zero bead;
- face-up `ki = 0`, no activate ability: hidden bead;
- face-down card: hidden bead regardless of private ki/ability data;
- configuration, `set_face_down`, `set_card_owner`, `set_card_ki`, and `remove_active_effect` to refresh correctly;
- bead placement to remain in the lower-right corner without overlapping centered right/bottom powers at portrait card sizes.

### Green

Add `Overlay/KiBadge` as a small styled `PanelContainer` with a centered number label. Give `CardView` focused helpers for current ki, active ability presence, ki updates, and badge refresh. Keep private runtime data in concealed opponent views but never expose the bead or tooltip details.

Use jade, gold-rimmed active styling and a dimmed zero state. Do not resize hand or board cards.

### Verify

Run card-view/integration probes at the configured portrait viewport and inspect a rendered screenshot for overlap or concealment leaks.

## Checkpoint 7: Add Board-Card Dragging and Typed Target Highlights

**Modify:**

- `scripts/card_view.gd`
- `scripts/duel_controller.gd`
- `tests/test_duel_integration.gd`

### Red

Add player and testing-mode opponent scenarios requiring:

- only the active owner's eligible board card to become draggable;
- board cards with zero ki, lost ability, no target, or wrong owner to remain inert;
- drag start to preserve the source cell logically while exposing its typed legal target set;
- activate targets to use teal styling distinct from placement highlights;
- invalid/cancelled/focus-loss drops to return to the exact source cell, retain ki, and keep the turn;
- valid drop to submit a complete action with instance ID, ability ID, and board target;
- hand-card dragging to continue using the existing placement flow;
- testing mode to allow manual opponent activation only on the opponent turn.

### Green

Generalize drag context in the controller to distinguish hand source from board source. On board drag start, derive the card's sole activate effect, request typed targets from `DuelTargeting`, reparent the view to `DragLayer`, and retain source-cell metadata for recovery.

On drop, translate the UI hit into a typed target and validate through `DuelSimulator`. Never decide legality with scene-only checks. Extend cell styling with `activate_legal` and `activate_hover` teal variants. Replace `_return_card_to_hand` with source-aware return helpers.

Update `_sync_hand_playability` into action-source playability synchronization for both hands and board cards.

### Verify

Run integration probes for valid, invalid, cancelled, and focus-loss activation drags, followed by an ordinary hand placement.

## Checkpoint 8: Present Movement, Ki Spend, Attacks, and Audio

**Modify:**

- `scenes/duel.tscn`
- `scripts/duel_controller.gd`
- `scripts/card_view.gd`
- `tests/test_duel_integration.gd`

### Red

Require the presentation trace and final scene state to show:

- activation and ki update before movement;
- one card view moving from source cell to destination without reconstruction;
- a brief brush-like trail and one movement cue only on valid activation;
- the ki bead updating to the simulator's resulting value;
- movement settling before flip/exile animation begins;
- no on-play Ink Summon or draw feedback during activation;
- input lock through the entire action and one turn advancement;
- fast mode zeroing movement/trail durations and suppressing movement audio while preserving final state.

### Green

Add exported movement duration, trail color/width/fade, and movement-audio volume tunables. Add `MovementAudio` and synthesize a restrained short brush-whoosh consistent with existing placeholder audio.

Handle `ability_activated`, `ki_changed`, and `card_moved` events in order. Update the existing dragged card's data and board-view mapping, animate it from its current global drag position into the destination, create/fade a transient `Line2D` brush trail under `DragLayer`, then continue through existing flip/exile presentation.

When `ability_lost` removes the sole activate effect, refresh both bead visibility and board-card playability while leaving ki untouched.

### Verify

Run the integration suite in fast mode, then a non-fast hidden gameplay probe that captures a mid-movement frame and confirms no runtime errors or overlapping sounds.

## Checkpoint 9: Opponent AI, Turn Text, and Match Completion

**Modify:**

- `scripts/duel_controller.gd`
- `tests/test_duel_integration.gd`

### Red

Add end-to-end cases requiring:

- normal opponent AI to commit either a play or activate action returned by greedy search;
- activation-only opponent turns not to end the match prematurely;
- testing-mode opponent board activation to remain manual;
- player turn text to say `Your turn · play a card or activate` when either category is legal;
- action availability to update after ki spend, ability loss, movement, exile, and draws;
- matches to complete only when both owners have no legal action.

### Green

Branch opponent presentation by action type while sharing `_commit_action`. Resolve play sources through logical hand instance IDs and activate sources through board instance IDs. Update turn text and completion checks from generalized legal-action queries.

### Verify

Run deterministic player/opponent fixtures covering play-vs-activate choice, activation-only continuation, and eventual completion.

## Checkpoint 10: Full Regression and Portrait Playtest

Run every repository suite twice and require explicit pass markers or equivalent named Summer verification reports. Run per-script diagnostics for every new or modified GDScript. Run `git diff --check` and confirm no stale `DuelMove`, `get_legal_moves`, or `apply_move` production references remain.

Play the portrait game and walk these paths:

1. Player plays an ordinary hand card; existing behavior is unchanged.
2. Player drags Jiang Wei or Sun Zan to an adjacent empty square that captures nothing; 1 ki is spent and the turn ends.
3. Activation produces one or more normal flips in canonical order.
4. Invalid, diagonal, occupied, and focus-loss drops return to the source with no cost.
5. A zero-ki activate card shows a dimmed zero bead and cannot drag.
6. A flipped activate card loses the ability but keeps its ki display when positive.
7. A zero-ki card with no activate ability hides the bead.
8. Face-down opponent hands never expose ki.
9. Opponent AI performs an activation and continues the match correctly.
10. Testing mode permits manual opponent activation.
11. Draw, Ink Summon, exile, fixed hand slots, score counting, and match completion still work.

After the walkthrough, read console, debugger, and aggregate diagnostics. Stop on any new error. Leave `TESTING_MODE = false`, fast mode disabled, and temporary fixture seeds removed before the final commit.
