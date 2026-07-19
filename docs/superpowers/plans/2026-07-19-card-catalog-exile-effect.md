# Card Catalog and Exile-on-Flip Implementation Plan

**Design:** `docs/superpowers/specs/2026-07-19-card-catalog-exile-effect-design.md`  
**Goal:** Move production card data into a dedicated catalog and implement deterministic, simulator-visible exile-on-flip behavior for Tiger General and Gate General.

## Working Rules

- Keep the simulator and tests free of scene-node dependencies.
- Write the failing test for each checkpoint before its implementation.
- Preserve `DuelRules.make_card` as a lightweight fixture helper; production cards must come from `CardCatalog`.
- Keep current `captures` transition data temporarily for compatibility, but make ordered `events` authoritative for presentation.
- Run the relevant focused test after each checkpoint and the full suite before playtesting.
- Git is currently unavailable in this environment. Keep changes grouped by checkpoint; commit them later when a Git executable is available.

## Checkpoint 0: Confirm the Baseline

**Files changed:** none.

Run the existing suites before editing:

```powershell
$summer_bin = 'C:\Users\王异\AppData\Local\SummerEngine\current\Summer.exe'
& $summer_bin --headless --path 'C:\mygame' --script 'res://tests/test_duel_rules.gd'
& $summer_bin --headless --path 'C:\mygame' --script 'res://tests/test_duel_simulator.gd'
& $summer_bin --headless --path 'C:\mygame' --script 'res://tests/test_duel_integration.gd'
```

Expected baseline markers are `DUEL_RULE_TESTS_PASSED`, `DUEL_SIMULATOR_TESTS_PASSED`, and `DUEL_INTEGRATION_PASSED`. Record any engine-owned shutdown warnings separately from project failures.

## Checkpoint 1: Add the Catalog and Encounter Decks

**Create:**

- `scripts/card_catalog.gd`
- `scripts/duel_decks.gd`
- `tests/test_card_catalog.gd`

**Modify:**

- `scripts/duel_rules.gd`

### Red

Add catalog tests that require:

- Ten unique stable IDs matching the current roster.
- Exactly four integer powers per card.
- Deep-copy isolation from catalog definitions.
- Every declared effect ID to be known and every effect to declare `retained_on_flip`.
- `gate_general` and `tiger_general` to declare `exile_instead_of_flip` with retention enabled.
- Player and opponent encounter deck IDs to resolve successfully.
- Current deck order to remain unchanged so hand-slot behavior is stable.

Run `test_card_catalog.gd` and confirm it fails because the new scripts do not exist.

### Green

Implement `CardCatalog` with:

- Constants for supported effect IDs.
- One immutable dictionary of definitions.
- `validate_catalog() -> Array[String]`.
- `get_definition(card_id: StringName) -> Dictionary`, returning a deep copy.
- `create_instance(card_id, original_owner, instance_id) -> Dictionary`, copying display data, powers, and `active_effects` into a match-local dictionary.

Implement `DuelDecks` with the current player and opponent card-ID arrays. Extend `DuelRules.make_card` only enough to create compatible synthetic test fixtures with optional original owner and active effects; do not put production definitions back into the rules file.

### Verify

Run the new catalog test, followed by the existing rule and simulator tests to prove the fixture helper remains compatible.

## Checkpoint 2: Separate Flip Detection from Mutation

**Modify:**

- `scripts/duel_rules.gd`
- `tests/test_duel_rules.gd`

### Red

Add tests for a pure `get_would_flip_indices(board, source_index)` query:

- Returns top, right, bottom, left targets in that order.
- Does not mutate ownership.
- Ignores allied, empty, tied, and stronger neighbors.
- Handles invalid source indices safely.

### Green

Extract comparison detection from `resolve_captures`. Keep `place_card` and `resolve_captures` as compatibility helpers that call the new query and then perform ordinary ownership changes. This keeps low-level rule tests valid while allowing the simulator to decide whether each attempt flips or is replaced.

### Verify

Run `test_duel_rules.gd` and confirm all legacy capture behavior plus the new non-mutating query passes.

## Checkpoint 3: Implement Effect Resolution and Runtime Retention

**Create:**

- `scripts/duel_effects.gd`

**Modify:**

- `scripts/duel_simulator.gd`
- `scripts/duel_state.gd`
- `tests/test_duel_simulator.gd`

### Red

Add simulator tests for:

- A normal `card_flipped` event and unchanged legacy `captures` output.
- One and four `card_exiled` events in canonical direction order.
- Exiled targets stored under `original_owner`, even after prior ownership changes.
- Exiled board cells becoming `null` and legal for reuse.
- Scores counting neither exiled card.
- A retained effect surviving a flip and working for the new owner.
- A non-retained effect producing `ability_lost`, disappearing permanently, and remaining absent after a flip back.
- Exile not producing `ability_lost` on the removed target.
- Source state, copied `active_effects`, and copied removed zones remaining isolated.

### Green

Implement `DuelEffects.resolve_flip_attempt` against the copied `DuelState`:

- Read the source instance's current `active_effects`.
- Let the first applicable replacement consume the attempt.
- For `exile_instead_of_flip`, append the complete target to the original owner's removed zone, clear the cell, and return `card_exiled`.
- Otherwise perform the normal owner change, remove non-retained target effects, and return `card_flipped` followed by ordered `ability_lost` events.

Change `DuelSimulator.apply_move` to:

1. Copy state and remove the selected hand instance.
2. Fill missing fixture-only runtime fields deterministically without altering valid catalog instances.
3. Place the source card.
4. Ask `DuelRules` for would-be flips.
5. Resolve each attempt through `DuelEffects`.
6. Return ordered `events`, plus compatibility `captures` and explicit `exiles` arrays.

Keep event dictionaries limited to pure values: event type, source/target cell, owner IDs, instance IDs, and lost effect IDs.

### Verify

Run `test_duel_simulator.gd` twice to confirm deterministic results and no cross-run mutation.

## Checkpoint 4: Make Turn Flow and AI Effect-Aware

**Modify:**

- `scripts/duel_simulator.gd`
- `scripts/duel_search.gd` only if a terminal/pass regression requires it
- `tests/test_duel_simulator.gd`

### Red

Add tests that require:

- Terminal state only when neither owner has a legal move, the effect queue is empty, or the turn cap is reached.
- Automatic pass to the owner who can still move.
- A reopened cell to keep the match alive.
- Greedy selection to evaluate moves by simulating their actual result, including exile.
- Existing no-effect greedy fixtures and the four-ply tactical-trap fixture to remain deterministic.
- Alpha-beta search to see removed cards and retained/lost effects through copied simulator state.

### Green

Add owner-specific legal-move queries and make `apply_move` choose the next active owner based on available moves. Reimplement `choose_greedy_move` over `get_legal_moves` plus `apply_move`, ranking actual immediate score improvement first, boundary strength second, then existing card/cell ordering. Remove production dependence on the effect-blind `DuelRules.choose_ai_move`; retain that function only for legacy parity tests until those tests can be retired.

### Verify

Run simulator tests and confirm the established deeper-search fixture still chooses its known stronger move.

## Checkpoint 5: Migrate Production Hands to Card IDs

**Modify:**

- `scripts/duel_controller.gd`
- `scripts/card_view.gd`
- `tests/test_duel_integration.gd`

### Red

Add integration assertions that:

- Production hands resolve from `DuelDecks` and contain stable card IDs.
- Tiger General and Gate General views contain the catalog effect descriptor.
- The controller has no `_get_player_cards` or `_get_opponent_cards` hard-coded definition methods.
- Five persistent slots and existing card sizes remain unchanged.

### Green

Change controller startup to resolve deck IDs into match-local instances first, construct `DuelState`, and then spawn hand views from those logical hands. Use deterministic instance IDs such as owner plus starting slot. Remove hard-coded production card constructors and the temporary hand-to-state scraping path.

Add a focused debug move helper that can commit a specified owner's hand card without automatically chaining the next turn. This is only for deterministic integration fixtures and must still call the production simulator and presentation path.

Update `CardView` so its copied runtime data can remove an active effect when an `ability_lost` event is presented.

Add a minimal event-consumption bridge before enabling the catalog decks in production: normal `card_flipped` events use the existing animation, `ability_lost` updates view data, and `card_exiled` immediately clears `board_cards`, frees the target view, and leaves the cell reusable. Checkpoint 6 replaces the immediate exile with the approved ink/audio presentation. This prevents a temporary logical/visual desynchronization between checkpoints.

### Verify

Run catalog and integration tests. Confirm the approved portrait layout, fixed slots, real drag path, and focus-loss cancellation still pass.

## Checkpoint 6: Present Flip, Exile, and Ability-Loss Events

**Modify:**

- `scenes/duel.tscn`
- `scenes/card_view.tscn`
- `scripts/duel_controller.gd`
- `scripts/card_view.gd`
- `tests/test_duel_integration.gd`

### Red

Create deterministic controller fixtures for:

- Opponent Fire Envoy on cell 5, followed by player Gate General on cell 4, exiling the target.
- Player Xu Shu on cell 4, followed by opponent Tiger General on cell 5, exiling the target.
- The target view being freed, `board_cards[target]` becoming null, score sum matching board occupancy, and the cleared cell being reusable.
- Normal cards still using the existing capture flip.
- Fast mode completing all new animations immediately.

### Green

Add `RemovalAudio` to the duel scene and an `InkSlash` overlay to the card scene. Add exported presentation tunables for source pulse, exile duration, target delay, ink color, and removal volume.

Add focused `CardView` methods:

- `play_effect_pulse(duration)`.
- `play_exile(duration, ink_color)`, which flashes the ink overlay, shrinks/fades the card, and leaves cleanup to the controller.
- `play_ability_lost(effect_id, duration)`, which updates runtime view data and provides a brief visible fade.

Upgrade the checkpoint-5 event bridge to the full ordered presentation. Pulse the source once before the first exile, play the brush/tear cue, animate targets sequentially, clear `board_cards`, and free exiled views. Continue using the existing capture animation for `card_flipped` events. Refresh scores and unlock input only after all events finish.

Generate the prototype removal cue locally in the existing placeholder-audio helper using a low decaying tone plus short deterministic noise, avoiding a new external asset dependency.

### Verify

Run integration tests in fast mode, then boot the main scene headlessly and confirm there are no project script errors.

## Checkpoint 7: Full Regression and Manual Playtest

Run all four focused suites:

```powershell
$summer_bin = 'C:\Users\王异\AppData\Local\SummerEngine\current\Summer.exe'
& $summer_bin --headless --path 'C:\mygame' --script 'res://tests/test_card_catalog.gd'
& $summer_bin --headless --path 'C:\mygame' --script 'res://tests/test_duel_rules.gd'
& $summer_bin --headless --path 'C:\mygame' --script 'res://tests/test_duel_simulator.gd'
& $summer_bin --headless --path 'C:\mygame' --script 'res://tests/test_duel_integration.gd'
& $summer_bin --headless --path 'C:\mygame' --quit-after 3
```

Then launch the portrait build visibly and manually verify:

1. Drag-and-drop still works on the full card surface.
2. Gate General exiles every card it would flip.
3. Tiger General does the same for the opponent AI.
4. Exile uses the distinct ink/dissolve feedback and leaves reusable cells.
5. Scores count only surviving board cards.
6. A match can continue beyond nine placements when removals reopen cells.
7. The match ends cleanly when neither side can move.

Report exact test markers, manual observations, and any engine-owned warnings separately from project errors.
