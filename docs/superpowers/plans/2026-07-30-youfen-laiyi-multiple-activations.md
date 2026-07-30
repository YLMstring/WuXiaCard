# 有凤来仪 Multiple Activations Implementation Plan

**Design source:** `docs/superpowers/specs/2026-07-30-youfen-laiyi-multiple-activations-design.md`

**Scope:** Support multiple declarative activate abilities, implement adjacent
ally/enemy targeting and the ordered swap primitive, and give 有凤来仪·三/·四
their cataloged abilities. Preserve current duel rules, activation drag UX,
attack presentation, AI budgets, and dynamic activation replacement semantics.

## Working Rules

- Write focused failing tests before each production checkpoint.
- Keep legality and state mutation in pure simulator/targeting/executor code.
- Treat `activation_index` as the zero-based order among activate abilities,
  not the raw index in `active_abilities`.
- Preserve catalog order everywhere.
- Keep reservation/restoration simulation-only and event-free.
- Emit two real `card_moved` events for a swap: A first, then B.
- Do not add movement-trigger cancellation, redirection, or replacement.
- Do not add swap disappear/reappear animation.
- Preserve unrelated user changes and do not push remote state.

## Checkpoint 0 — Establish the Baseline

**Files changed:** none.

1. Record `git status --short`.
2. Run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 `
     -Tests test_card_catalog.gd,test_duel_simulator.gd,test_duel_search.gd,test_duel_integration.gd
   ```

3. Require every suite's `_PASSED` marker, exit code zero, and no `ERROR:`,
   `SCRIPT ERROR`, `_FAILED`, or `CHECK_FAILED`.
4. If the runner does not accept the focused `-Tests` form, run the complete
   `tools/run_tests.ps1` command instead.

## Checkpoint 1 — Accept and Declare Multiple Catalog Activations

**Modify**

- `tests/test_card_catalog.gd`
- `scripts/card_catalog.gd`
- `scripts/duel_abilities.gd`

**Tests first**

Add assertions requiring:

- the new ally/enemy target rules and swap action to be known vocabulary;
- catalog validation to accept multiple structurally valid activate abilities;
- each activate entry to be validated independently;
- 有凤来仪·二, ·三, and ·四 to expose one, two, and three activate
  abilities in the approved order;
- every 有凤来仪 activation to cost 1 ki and retain on flip;
- `get_activate_abilities` to return all activations in order;
- indexed lookup to return the selected activation and reject invalid indices;
- `card_uses_ki` to be true when any activation exists;
- `replace_activate_ability` to remove all old activate abilities, preserve
  non-activate abilities, and append one replacement.

**Implementation**

- Add:
  - `TARGET_ADJACENT_ALLY_BOARD`;
  - `TARGET_ADJACENT_ENEMY_BOARD`;
  - `ACTION_SWAP_SELF_WITH_TARGET`.
- Register them in the existing known-vocabulary arrays.
- Remove only the validation rule that rejects `activation_count > 1`.
- Add the approved second activation to 有凤来仪·三.
- Add the approved second and third activations to 有凤来仪·四.
- Add an ordered helper returning all activate abilities.
- Keep `get_activate_ability` and `get_activation` compatible with index `0`;
  allow indexed lookup without changing existing callers.
- Preserve the existing replace-all-activations behavior for dynamically
  granted activations.

**Focused verification**

Run `test_card_catalog.gd`.

## Checkpoint 2 — Put Activation Identity in `DuelAction`

**Modify**

- `scripts/duel_action.gd`
- `tests/test_duel_search.gd`
- direct action-construction fixtures in `tests/test_duel_simulator.gd` and
  `tests/test_duel_integration.gd`

**Tests first**

Require:

- `make_activate` to default `activation_index` to `0`;
- explicit nonzero indices to survive duplication;
- action equality to distinguish activation indices;
- canonical keys to distinguish activation indices;
- existing play actions and old single-activation callers to remain unchanged.

**Implementation**

- Add `activation_index: int = 0` to `DuelAction`.
- Add it as the final optional argument of `make_activate`.
- Include it in construction, duplication, equality, and canonical keys.
- Keep play actions at index `0` so their identity remains deterministic.

**Focused verification**

Run `test_duel_search.gd` and the action-focused simulator checks.

## Checkpoint 3 — Add Typed Ally and Enemy Targeting

**Modify**

- `scripts/duel_targeting.gd`
- `tests/test_duel_simulator.gd`

**Tests first**

For both new target rules, cover:

- canonical top/right/bottom/left target order;
- adjacency without row wrapping;
- correct ally/enemy ownership;
- rejection of empty, diagonal, distant, source, and out-of-range cells;
- source ownership validation;
- target legality changing when ownership changes.

**Implementation**

- Dispatch `get_valid_targets` by target-rule constant.
- Reuse `DuelRules.get_neighbor_index`.
- Keep adjacent-empty behavior unchanged.
- For ally/enemy rules, require an occupied target and compare its current slot
  owner with the activating owner's current ownership.
- Keep the returned target shape as `{kind, index}`.

**Focused verification**

Run the targeting/simulator subset.

## Checkpoint 4 — Implement Ordered Swap in the Ability Executor

**Modify**

- `scripts/duel_ability_executor.gd`
- `tests/test_duel_simulator.gd`

**Tests first**

Build pure-state fixtures for allied and enemy swaps and require:

- wrong, empty, stale, or non-adjacent targets to return `NO_EFFECT`;
- no partial board mutation on failed prevalidation;
- B to be reserved first;
- A to move from A-origin to B-origin;
- A to be reserved after its move;
- B to be restored to B-origin and then move to A-origin;
- A to be restored to B-origin;
- final board identity to be A at B-origin and B at A-origin;
- ownership, card dictionaries, abilities, powers, and ki to be preserved;
- exactly two `card_moved` events, ordered A then B;
- no summon, exile, reserve, restore, or extra movement events;
- the returned source cell to be B-origin so the following attack uses A's new
  position;
- the standard attack request to be generated after both movement events.

**Implementation**

- Dispatch `ACTION_SWAP_SELF_WITH_TARGET` in `_execute_action`.
- Add one reusable low-level movement helper used by both ordinary movement and
  swap. It owns the future before/after movement boundary but currently emits
  only the existing `card_moved` event.
- Prevalidate both exact card instances, the board target kind, adjacency, and
  occupancy before mutation.
- Implement the approved sequence:
  1. reserve B;
  2. move A to B-origin;
  3. reserve A;
  4. restore B to B-origin;
  5. move B to A-origin;
  6. restore A to B-origin.
- Reservation/restoration are local bookkeeping only and emit nothing.
- Return A's final cell so the next catalog action requests A's standard
  attack from the correct square.

**Focused verification**

Run the executor/swap simulator cases twice.

## Checkpoint 5 — Enumerate and Execute Indexed Activations

**Modify**

- `scripts/duel_simulator.gd`
- `tests/test_duel_simulator.gd`
- `tests/test_duel_search.gd`

**Tests first**

Require:

- legal action generation to enumerate every payable activation in catalog
  order;
- each generated action to carry its activation index;
- the ally and enemy swap options to appear only for valid targets;
- legality to reject negative, out-of-range, and stale activation indices;
- application to resolve exactly the indexed activation;
- invalid indexed actions to leave the original state untouched and spend no ki;
- every successful activation to spend exactly 1 ki and consume the turn;
- 有凤来仪·三 and ·四 to retain all activations after an ownership flip;
- AI search to preserve and compare distinct activation indices.

**Implementation**

- Replace first-activation-only loops with ordered indexed enumeration.
- Resolve the selected activation in legality and application.
- Pass the selected activation unchanged to the executor.
- Preserve current action ordering and deterministic search tie behavior.
- Keep all single-activation actions at index `0`.

**Focused verification**

Run `test_duel_simulator.gd` and `test_duel_search.gd`.

## Checkpoint 6 — Select the First Listed Player Activation

**Modify**

- `scripts/duel_controller.gd`
- `tests/test_duel_integration.gd`

**Tests first**

Require:

- board drag target highlighting to include targets from every legal activation;
- duplicate target cells to appear once visually;
- dropping on a cell accepted by multiple activations to choose the lowest
  activation index;
- dropping on an ally/enemy-only target to construct the corresponding indexed
  action;
- invalid and cancelled drags to preserve the board and ki;
- testing mode to use the same selection rule for the opponent;
- old single-activation dragging to remain unchanged.

**Implementation**

- Keep the full legal `DuelAction` candidates for the dragged board card.
- Derive the deduplicated cell-highlight list from those actions.
- When creating the drop action, choose the first candidate for that target in
  simulator/catalog order rather than reconstructing activation index `0`.
- Clear both target and action-candidate drag state after completion/cancellation.

**Focused verification**

Run the drag and testing-mode integration cases.

## Checkpoint 7 — Reconcile Both Card Views for Swaps

**Modify**

- `scripts/duel_controller.gd`
- `tests/test_duel_integration.gd`

**Tests first**

Require:

- a normal move to keep its current movement trail and feedback;
- a swap to retain both pre-existing `CardView` instances;
- A's view to end in B-origin and B's view to end in A-origin;
- `board_cards` to match the simulator board before attack presentation;
- no disappear/reappear, summon, exile, or reconstruction presentation;
- both `card_moved` events to appear in the presentation trace in A-then-B order;
- ki feedback to find A after the view exchange;
- the attack VFX source to be A in B-origin;
- final runtime data and owners to synchronize for both cards.

**Implementation**

- Capture source and target views before applying the simulator action.
- If an activation target was empty, preserve the existing movement path.
- If it was occupied, atomically exchange the two existing views and
  `board_cards` mappings to match the final simulator board.
- Do not play reservation/restoration feedback or a second movement trail.
- Let `card_moved` events record logical ordering; they do not reconstruct
  views.
- Replace single-card reconciliation with an instance-based board
  reconciliation that can sync every affected final cell.
- Present the normal attack events only after this mapping is authoritative.

**Focused verification**

Run the swap presentation integration cases in fast mode, then one non-fast
portrait probe.

## Checkpoint 8 — Full Regression and Playtest

1. Run `git diff --check`.
2. Run the complete suite:

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
   ```

3. Require every `_PASSED` marker and no error/failure marker.
4. Search for stale first-activation-only assumptions in production and active
   tests.
5. Play the portrait build and manually verify:
   - 有凤来仪·二 moves to an adjacent empty square and attacks;
   - 有凤来仪·三 can choose empty movement or allied swap;
   - 有凤来仪·四 can choose empty movement, allied swap, or enemy swap;
   - each activation spends 1 ki and ends the turn;
   - a flipped 有凤来仪 card retains all its activations;
   - an allied/enemy swap exchanges both cards and A attacks from its new cell;
   - no card disappears visually and attack VFX originates from A;
   - testing mode can perform the same actions for either side;
   - the opponent AI can search, choose, and execute indexed activations;
   - Jiang Wei, Sun Zan, Meng Huo, draw, exile, summon reactions, inspection,
     scoring, and match completion still behave normally.
6. Review console/debugger diagnostics and stop on any new error.
7. Review `git status --short` and keep unrelated user changes out of the
   implementation commit.

## Commit Boundary

After verification and playtesting pass, commit the gameplay implementation,
tests, and any directly affected current maintainer documentation together.
Do not push or modify remote state.
