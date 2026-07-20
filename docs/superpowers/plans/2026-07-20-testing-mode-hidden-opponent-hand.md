# Testing Mode and Hidden Opponent Hand Implementation Plan

**Design:** `docs/superpowers/specs/2026-07-20-testing-mode-hidden-opponent-hand-design.md`  
**Goal:** Add a script-selected manual two-sided testing mode while hiding the opponent's remaining hand behind reusable face-down card presentation in normal play.

## Working Rules

- Keep the simulator, rules, card catalog, and deck definitions unchanged.
- Make visibility a `CardView` presentation concern; never remove or mask logical card data.
- Route both owners through the existing production drag and simulator commit path.
- Read testing mode once when a duel instance is created; provide no runtime UI toggle.
- Write failing integration assertions before each production change.
- Run focused integration tests after every checkpoint and all existing suites before playtesting.

## Checkpoint 0: Confirm the Baseline

**Files changed:** none.

Run the existing suites before editing:

```powershell
$summer_bin = 'C:\Users\王异\AppData\Local\SummerEngine\current\Summer.exe'
& $summer_bin --headless --path 'C:\mygame' --script 'res://tests/test_card_catalog.gd'
& $summer_bin --headless --path 'C:\mygame' --script 'res://tests/test_duel_rules.gd'
& $summer_bin --headless --path 'C:\mygame' --script 'res://tests/test_duel_simulator.gd'
& $summer_bin --headless --path 'C:\mygame' --script 'res://tests/test_duel_integration.gd'
```

Expected markers are `CARD_CATALOG_TESTS_PASSED`, `DUEL_RULE_TESTS_PASSED`, `DUEL_SIMULATOR_TESTS_PASSED`, and `DUEL_INTEGRATION_PASSED`.

## Checkpoint 1: Add Developer Mode Configuration and Face-Down Presentation

**Create:**

- `scripts/game_settings.gd`

**Modify:**

- `scripts/card_view.gd`
- `tests/test_duel_integration.gd`

### Red

Add normal-mode integration assertions requiring each opponent hand card to:

- report itself face-down;
- retain complete private `card_data`;
- hide the glyph and all four power labels;
- expose no tooltip text;
- keep the opponent-colored card-back silhouette and fixed slot size.

Add direct presentation assertions that calling `set_face_down(false)` restores the correct glyph, powers, tooltip, and face style from the retained card data. Calling the same visibility state twice must be harmless.

### Green

Create `GameSettings` with `const TESTING_MODE: bool = false` and a short comment identifying the single edit required to enter testing mode.

Add `face_down: bool` and `set_face_down(value: bool)` to `CardView`. Refactor face-content assignment into one idempotent presentation refresh so configuration, owner changes, resize, and visibility changes cannot leak or lose information. A face-down view must clear its tooltip and hide its face labels; its data remains untouched.

Use deterministic placeholder card-back styling derived from the opponent palette. Do not add an art asset or new scene node.

### Verify

Run `test_duel_integration.gd`. Confirm the new visibility tests pass and existing layout/card-size assertions remain green.

## Checkpoint 2: Generalize Manual Input to the Active Owner

**Modify:**

- `scripts/duel_controller.gd`
- `tests/test_duel_integration.gd`

### Red

Add testing-mode fixtures that assign the controller's construction-time mode field before adding the duel scene to the tree. Require:

- both starting hands to be face-up;
- only the player hand to be playable on the opening turn;
- a committed player move to stop after one transition with no AI reply;
- the opponent hand alone to become playable;
- a real opponent drag to reparent through `DragLayer` and commit through the simulator;
- control to return to the player hand after the opponent transition;
- testing status text to identify the active side;
- invalid top-hand drops and focus loss to restore the card to its original slot.

Keep the existing normal-mode assertion that a player drag produces an automatic AI reply.

### Green

Preload `GameSettings` in the controller and initialize `testing_mode` from its constant. Production code never mutates it.

Connect drag signals for both hands. Replace player-specific drag assumptions with helpers that map a card owner to its hand and expected turn state. At drag start, reject inactive owners, calculate the simulator hand index from the correct hand, and remember the card's own home slot. At drop, commit with `card.owner_id`; invalid drops return through the existing home-parent metadata.

Replace `_set_hand_playable` with a single synchronization method that disables both hands during resolution and enables only the active human-controlled owner. In normal mode, opponent turns remain non-playable and call the existing AI. In testing mode, opponent turns wait for manual input.

Make `_commit_card` reveal every card before placing it on the board, including AI, debug-helper, and future non-drag commits. Update turn-status messages for the two testing-mode sides without changing normal text.

### Verify

Run `test_duel_integration.gd` twice to confirm deterministic ownership, drag restoration, and AI suppression.

## Checkpoint 3: Regression and Configuration Checks

**Modify only if a regression requires it:**

- existing test files related to the failing behavior.

Run all four suites and a clean editor boot. Verify:

- the settings script parses and defaults to normal mode;
- catalog, rules, simulator, exile events, passes, and search behavior are unchanged;
- normal play still completes with AI turns;
- testing mode completes through alternating manual/debug moves without AI;
- no hidden hand information appears in rendered labels or tooltip fields;
- the portrait layout and five persistent slots are unchanged.

## Checkpoint 4: Manual Portrait Playtest

Launch the project twice:

1. With `TESTING_MODE = false`, confirm opponent cards show consistent backs, AI acts, and played opponent cards reveal on the board.
2. With a test-instantiated mode override or temporary pre-launch script edit, confirm both hands are visible and mouse/touch dragging alternates correctly between bottom and top hands.

Restore `TESTING_MODE = false` before final verification and commit. Report project errors separately from known Summer Engine authentication or shutdown warnings.
