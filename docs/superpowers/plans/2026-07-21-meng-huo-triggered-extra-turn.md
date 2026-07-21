# Meng Huo Triggered Ki and Extra Turn Implementation Plan

**Design:** `docs/superpowers/specs/2026-07-21-meng-huo-triggered-extra-turn-design.md`  
**Scope:** Implement the minimal generic trigger/condition/action framework selected by the user, Meng Huo's `battle_momentum` ability, deterministic end-turn batching, extra-turn state flow, restrained UI feedback, and supporting tests. Do not build a general-purpose rules language or redesign AI evaluation.

## Working Rules

- Keep trigger discovery and mutation scene-free and simulator-authoritative.
- Evaluate each matched rule's condition once for its entire ordered action list.
- Revalidate stable source identity, ownership, active ability, and condition before resolving a matched rule group.
- Iterate board cells row-major: `0, 1, 2`, then `3, 4, 5`, then `6, 7, 8`.
- Preserve attack resolution order separately as top, right, bottom, left.
- Treat only an emitted `card_flipped` event as a successful-flip trigger.
- Coalesce extra-turn requests per owner while spending every eligible source's ki.
- Use event-carried previous/resulting ki for sequential presentation; do not jump directly to final state when a transition contains both gain and spend events.
- Add no new sound.
- Require explicit test pass markers or named Summer verification reports; an unmarked process exit is not a pass.

## Checkpoint 0: Confirm the Clean Baseline

**Files changed:** none.

Run catalog, rules, simulator, and integration suites. Record exact pass markers. Boot the duel and record diagnostics. Confirm Git status is clean at `65d0d0e` and that the known focus/integer-division warnings are the only pre-existing warnings.

## Checkpoint 1: Add Trigger Schema and Meng Huo Catalog Data

**Modify:**

- `scripts/card_catalog.gd`
- `tests/test_card_catalog.gd`

### Red

Add tests requiring:

- known event IDs `after_successful_flip_by_self` and `end_owner_turn`;
- known action IDs `gain_ki`, `spend_all_ki`, and `request_extra_turn`;
- Meng Huo to declare one `battle_momentum` effect with both approved trigger rules;
- runtime normalization to set the ability's omitted retention flag to false;
- positive integer gain amounts and nonnegative integer `ki_at_least` thresholds;
- unknown event/action/condition IDs, malformed trigger/action arrays, missing fields, invalid numeric types, and invalid numeric ranges to fail validation;
- existing non-trigger effects to retain their current validation behavior.

### Green

Add the trigger constants and registries. Extend effect validation with focused helpers for trigger arrays, condition dictionaries, and action dictionaries. Add `battle_momentum` to Meng Huo exactly as specified, without `starting_ki` or explicit retention metadata.

### Verify

Run the catalog suite and a pure catalog probe. Confirm definition copies and runtime instances remain isolated.

## Checkpoint 2: Implement Pure Matched-Rule Discovery and Resolution

**Create:**

- `scripts/duel_triggers.gd`

**Modify:**

- `scripts/duel_effects.gd`
- `tests/test_duel_simulator.gd`

### Red

Add focused tests for:

- successful-flip discovery examining only the supplied source identity;
- end-turn discovery scanning eligible owned board cards in row-major order;
- conditions evaluated once per matched rule group;
- action order preserved within each group;
- stale cell, wrong instance ID, wrong owner, removed card, lost ability, and failed condition producing no mutation;
- `gain_ki` emitting previous/resulting values;
- `spend_all_ki` draining the full current value;
- request tokens returned separately from presentation events;
- source and sibling state remaining isolated.

### Green

Implement a scene-free `DuelTriggers` API with two layers:

1. `discover(state, event_id, context)` returns deterministic matched-rule group dictionaries.
2. `resolve(state, groups)` revalidates each group once, executes its ordered actions, and returns `{events, extra_turn_requests}`.

Add a public active-effect lookup helper to `DuelEffects` if needed; do not duplicate effect scanning logic. Commands and groups contain only pure values and deep-copied action data.

### Verify

Run the focused simulator tests and hidden pure-state probes. Confirm discovery never mutates state.

## Checkpoint 3: Dispatch Successful-Flip Triggers

**Modify:**

- `scripts/duel_simulator.gd`
- `tests/test_duel_simulator.gd`

### Red

Add scenarios requiring:

- Meng Huo to gain one ki after one actual ownership-changing flip;
- a multi-flip placement to gain one ki per flipped target in top/right/bottom/left order;
- event order for each target to be `card_flipped`, target `ability_lost` events, then source `ki_changed`;
- failed comparisons, exile replacement, removal, and no-flip resolution to grant zero ki;
- lost `battle_momentum` to prevent future gain while preserving stored ki;
- an explicitly identified future-effect source to use the same dispatch path.

### Green

In the shared attack resolver, inspect each target's actual resolution events. Dispatch `after_successful_flip_by_self` only when that batch contains `card_flipped`, then append resolved trigger events before continuing to the next direction. Supply source cell, instance ID, ability owner, and acting owner in the context.

Keep replacement effects and ordinary capture/exile accounting unchanged.

### Verify

Run simulator tests twice and assert exact event arrays and ki values.

## Checkpoint 4: Centralize End-Turn Triggers and Extra Turns

**Modify:**

- `scripts/duel_simulator.gd`
- `tests/test_duel_simulator.gd`

### Red

Add tests requiring:

- a Meng Huo with ki to drain to zero after action resolution and retain the acting owner;
- two eligible Meng Huos to drain in row-major order but emit one `extra_turn_granted` event;
- unequal ki values to be fully drained;
- zero-ki, wrong-owner, removed, and ability-lost Meng Huos to neither drain nor request;
- an action during the extra turn that generates new ki to grant another extra turn;
- a granted owner with no legal action to lose the unusable extra turn through normal pass logic;
- `turn_count` and `state_version` to increment once per completed action, never once for the grant itself;
- terminal and maximum-turn safeguards to remain correct;
- play and activate actions to share identical finish-turn trigger behavior.

### Green

Replace the current void finish helper with one centralized finish-action pipeline that:

1. dispatches and resolves `end_owner_turn` groups;
2. appends row-major ki drain events;
3. coalesces valid requests into one owner-level grant;
4. emits `extra_turn_granted` once;
5. increments action/version counters once;
6. retains the moving owner only when a grant exists and that owner has a legal action;
7. otherwise calls existing legal-action pass selection.

Return finish events to both play and activate transition paths so their ordered event lists include end-turn feedback.

### Verify

Run the full simulator/search suite. Confirm deep search naturally accepts same-owner child states and source states remain unchanged.

## Checkpoint 5: Present Sequential Ki Gain, Drain, and Extra Turn

**Modify:**

- `scripts/card_view.gd`
- `scripts/duel_controller.gd`
- `tests/test_duel_integration.gd`

### Red

Add production-controller tests requiring:

- arbitrary board-card views to be found by stable instance ID;
- each `ki_changed` event to display its own resulting value, even when one transition gains and then spends ki;
- positive gain to play one short green bead pulse;
- drain to update to `0` without a new sound;
- multiple Meng Huos to drain in row-major order;
- one `extra_turn_granted` event to show `Extra turn` briefly, then restore the correct player's normal status;
- input to remain locked until all trigger feedback finishes;
- player, automatic opponent, and testing-mode opponent extra turns to use the existing production action coordinator;
- face-down card views to keep the bead hidden.

### Green

Add `CardView.set_runtime_ki(value)` and a focused `play_ki_gain_pulse(duration)` presentation helper. The setter updates duplicated view data and refreshes bead visibility/text without assuming the simulator's final state.

In the controller, add board-view lookup by instance ID. Handle `ki_changed` by applying the event's resulting value to that view; pulse only when the value increased. Handle `extra_turn_granted` with a brief exported status duration and no audio. After all events, use the simulator's final `active_player` to restore playability and continue AI turns normally.

Fast mode must zero the new status/pulse durations.

### Verify

Run the integration suite with explicit markers. Use a hidden rendered probe to capture the bead at its gained value before drain where possible, then at zero with extra-turn status/state reports.

## Checkpoint 6: AI, Pass, and Chained-Turn Regression

**Modify:**

- `tests/test_duel_simulator.gd`
- `tests/test_duel_integration.gd`

Add deterministic cases proving:

- greedy transitions include trigger gains, drains, and same-owner continuation;
- deep search explores chained same-owner turns without assuming alternation;
- normal opponent AI immediately takes its granted extra turn after presentation;
- testing mode leaves the granted opponent turn under manual control;
- score, draw, exile, movement activation, ability loss, fixed hand slots, concealment, and match completion remain correct.

No special greedy heuristic or evaluation bonus is added.

## Checkpoint 7: Full Verification and Playtest

Run every repository suite and require explicit pass markers or named verification reports. Check every modified/new GDScript for parse errors. Run `git diff --check` and review the full diff for card-specific simulator branches that should live in the trigger module.

Walk these production paths:

1. Play Meng Huo so he flips one target; observe capture, bead gain, bead drain, and one extra turn.
2. Flip multiple targets; verify one ki per actual flip before all ki drains.
3. Use two eligible Meng Huos; verify both drain left-to-right/top-to-bottom and only one extra turn appears.
4. Gain ki during an extra turn; verify a second extra turn chains.
5. Cause exile/no flip; verify no ki gain.
6. Flip Meng Huo; verify the ability is lost while stored ki remains visible and inert.
7. Verify player, AI, and testing-mode repeated turns.
8. Recheck Jiang Wei/Sun Zan activation, draw, Ink Summon, face-down concealment, exile, scoring, and match completion.

After the walkthrough, read console, debugger, and aggregate diagnostics. New errors are blockers. Leave testing mode disabled, fast mode off, and temporary fixtures removed before committing the implementation.
