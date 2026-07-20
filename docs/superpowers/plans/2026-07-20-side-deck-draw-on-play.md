# Side Deck, Draw-on-Play, and Ink Summon Implementation Plan

**Design:** `docs/superpowers/specs/2026-07-20-side-deck-draw-on-play-design.md`  
**Goal:** Give Fa Zheng and Strategist a catalog-declared draw-two ability backed by shuffled, simulator-visible side decks, a five-card hand cap, stable card-instance identity, and sequential Ink Summon feedback.

## Working Rules

- Treat the current five starting cards as each owner's main deck/starting hand; never draw from it.
- Give each owner an independently shuffled side deck containing one fresh instance of every current catalog card.
- Resolve drawing in copied simulator state before flip/exile attempts so all AI paths see it.
- Keep shuffle randomness at duel construction only; never randomize inside `apply_move` or search branches.
- Keep logical hand order independent from fixed physical slot order and map exclusively by `instance_id`.
- Keep all animation, audio, and delays in controller presentation; simulator transitions remain immediate.
- Write failing focused tests before each production checkpoint.

## Checkpoint 0: Confirm the Baseline

**Files changed:** none.

Run all existing suites before editing:

```powershell
$summer_bin = 'C:\Users\王异\AppData\Local\SummerEngine\current\Summer.exe'
& $summer_bin --headless --path 'C:\mygame' --script 'res://tests/test_card_catalog.gd'
& $summer_bin --headless --path 'C:\mygame' --script 'res://tests/test_duel_rules.gd'
& $summer_bin --headless --path 'C:\mygame' --script 'res://tests/test_duel_simulator.gd'
& $summer_bin --headless --path 'C:\mygame' --script 'res://tests/test_duel_integration.gd'
```

Require the four existing pass markers. Record any unrelated engine warnings separately.

## Checkpoint 1: Declare Draw Effects and Side-Deck Contents

**Modify:**

- `scripts/card_catalog.gd`
- `scripts/duel_decks.gd`
- `tests/test_card_catalog.gd`

### Red

Add catalog assertions requiring:

- `draw_cards_on_play` to be a known effect ID;
- Fa Zheng and Strategist to declare exactly one draw effect with integer `draw_count = 2`;
- those raw definitions to omit `retained_on_flip`;
- runtime instances to normalize missing retention to `false`;
- Gate General and Tiger General to retain their explicit `true` value;
- missing, non-integer, zero, and negative draw counts to be rejected by effect validation;
- the side-deck card-ID list to contain every catalog ID exactly once and return defensive copies.

Expose a focused effect-validation entry point if necessary so invalid fixture dictionaries can be tested without mutating the private catalog.

### Green

Add `EFFECT_DRAW_CARDS_ON_PLAY`. Declare it on Fa Zheng and Strategist with only `id` and `draw_count`.

Normalize every effect while `create_instance` builds `active_effects`: copy the raw declaration and insert `retained_on_flip = false` only when absent. Change validation so retention is optional, but must be Boolean when present. Validate effect-specific fields through a small dispatch rather than adding unrelated conditions to the definition loop.

Add `get_side_deck_card_ids()` to `DuelDecks`, sourced from the catalog's current complete card-ID list. Keep the existing player and opponent main-deck order unchanged.

### Verify

Run `test_card_catalog.gd` and confirm definition-copy isolation still passes.

## Checkpoint 2: Make Side Decks First-Class, Copy-Isolated State

**Modify:**

- `scripts/duel_state.gd`
- `tests/test_duel_simulator.gd`

### Red

Add state assertions requiring constructor-injected player and opponent side decks, index `0` as the top card, and deep-copy isolation across:

- source constructor arrays;
- `duplicate_state()` branches;
- nested card powers and active-effect dictionaries.

Ensure existing constructor call sites remain valid through default deck arguments.

### Green

Extend `DuelState._init` with optional player/opponent side-deck arrays after the existing parameters. Deep-copy them into `decks`; keep `duplicate_state()` copying all zones and metadata exactly once.

Do not shuffle in `DuelState`. The state is a deterministic data container and tests/search must be able to inject exact deck order.

### Verify

Run `test_duel_simulator.gd` before adding draw behavior. Existing move, exile, terminal, and search tests must remain green.

## Checkpoint 3: Resolve Draw-on-Play in the Simulator

**Modify:**

- `scripts/duel_effects.gd`
- `scripts/duel_simulator.gd`
- `tests/test_duel_simulator.gd`

### Red

Build ordered card instances with distinct IDs and add simulator cases for:

- event order: `card_placed`, one or two `card_drawn` events, then flip/exile events;
- playing from five cards drawing only one because the hand returns to the cap of five;
- playing from three cards drawing two and preserving top-deck order;
- drawing only the cards remaining in a partially depleted side deck;
- an empty deck producing no draw event;
- `card_drawn` fields: owner, card ID, instance ID, and resulting logical hand index;
- source-state and sibling-branch isolation after drawing;
- a drawn catalog copy retaining effects independently of a flipped copy that lost them;
- side-deck cards not preventing terminal state when neither owner has a legal hand move;
- greedy and depth search using transitions whose hands and decks include draws.

### Green

Add a pure on-play resolver to `DuelEffects`, separate from `resolve_flip_attempt`. For each active effect in catalog order, draw:

```text
min(draw_count, 5 - current_hand_size, current_side_deck_size)
```

For each actual draw, remove index `0`, append the complete runtime instance to the logical hand, and emit one pure `card_drawn` event.

Call the on-play resolver in `DuelSimulator.apply_move` immediately after `card_placed` and before computing flip targets. Do not add timers, scene references, shuffle calls, or presentation flags to simulator/effect code.

### Verify

Run `test_duel_simulator.gd` twice. Confirm exact event order and deterministic branch behavior.

## Checkpoint 4: Build Shuffled Production Side Decks and Stable Slots

**Modify:**

- `scripts/duel_controller.gd`
- `tests/test_duel_integration.gd`

### Red

Add integration assertions requiring:

- both starting hands to retain their current five catalog IDs and slot sizes;
- both logical side decks to contain all ten IDs once;
- every main- and side-deck instance ID to be unique across the duel;
- independently created duels to use shuffled side-deck construction without relying on an unstable “order differs” assertion;
- an optional nonzero construction-time seed to make integration fixtures repeatable;
- both hand containers to keep exactly five persistent slots before and after draws.

### Green

Create main- and side-deck instances with owner and zone encoded in stable IDs, such as `main_1_0` and `side_1_0`. Use one `RandomNumberGenerator` per duel: randomize it for the production default and honor a nonzero exported seed for deterministic fixtures. Shuffle each owner's side-deck instance array once before constructing `DuelState`.

Refactor hand creation into two operations:

1. Create five persistent styled slot panels for each owner.
2. Spawn each starting card into its corresponding slot.

Replace the current “spawn card and create slot together” helper with slot-aware helpers, including “first empty physical slot.” Preserve the current portrait sizing and face-down rules.

### Verify

Run `test_card_catalog.gd` and `test_duel_integration.gd`. Confirm the current layout and concealment checks stay green.

## Checkpoint 5: Replace Visual-Order Move Mapping with Instance IDs

**Modify:**

- `scripts/duel_controller.gd`
- `tests/test_duel_integration.gd`

### Red

Script a duel in which older cards remain in later physical slots while newly drawn cards fill earlier empty slots. Require:

- drag start/commit to resolve a card view's instance ID to its current logical hand index;
- `debug_commit_move(owner, logical_index, ...)` to find the matching view by logical instance ID;
- AI choice `hand_index` to find the matching opponent view by instance ID;
- invalid drag and focus-loss recovery to preserve the card's physical home slot;
- committing a visually earlier drawn card to place that exact logical card, not the first logical hand entry.

### Green

Add focused helpers for:

- card view → instance ID;
- owner + instance ID → current logical hand index;
- owner + logical hand index → instance ID;
- hand container + instance ID → matching `CardView`.

Use those helpers in drag, debug, manual testing-mode, and AI commit paths. Remove `SIMULATOR_HAND_INDEX_META` and all assumptions that `_get_cards_in_hand()` order equals simulator hand order. Keep physical-slot metadata only for returning an invalid drag.

### Verify

Run `test_duel_integration.gd` twice, including normal AI and manual testing mode.

## Checkpoint 6: Present Draw Events in Empty Slots

**Modify:**

- `scripts/duel_controller.gd`
- `tests/test_duel_integration.gd`

### Red

Add production-transition tests requiring each `card_drawn` event to:

- locate the new logical card by instance ID;
- fill the first empty physical slot without resizing or repacking existing cards;
- appear face-up for the player and testing-mode opponent;
- appear face-down for a normal-mode opponent without leaking powers, glyph, name, tooltip, or effects;
- be presented sequentially in event order;
- complete before playability and turn status are updated.

Add a small read-only presentation trace/debug accessor if needed to assert `draw`, `draw`, and subsequent board-effect ordering without relying on wall-clock timing.

### Green

Handle `card_drawn` inside `_present_transition_events`. Look up its runtime data in the already-applied `duel_state`, spawn into the first empty slot, apply the correct visibility, connect drag signals, and await its arrival before processing the next event.

Track whether draw events were presented. Before the first later `card_flipped` or `card_exiled` event, await the exported post-draw gap exactly once. Never insert that gap into `DuelSimulator` or between draw events beyond their own animations.

### Verify

Run `test_duel_integration.gd`. Confirm fixed slots, concealment, and event ordering.

## Checkpoint 7: Add Sequential Ink Summon Visuals and Audio

**Modify:**

- `scenes/card_view.tscn`
- `scripts/card_view.gd`
- `scenes/duel.tscn`
- `scripts/duel_controller.gd`
- `tests/test_duel_integration.gd`

### Red

Require:

- a reusable ink-bloom overlay on every card view;
- a dedicated `DrawAudio` player in the duel scene;
- `play_draw_summon(bloom_duration, rise_duration, ink_color)` to end with the card fully visible, settled, unrotated, and at unit scale;
- fast mode to zero bloom/rise/post-draw durations and suppress draw audio while preserving the same final views;
- the presentation trace to place the post-draw gap before the first flip/exile feedback.

### Green

Add an Ink Summon overlay that scales/fades like an expanding ink blot while the card rises a short distance and settles with restrained easing. Default exports:

- bloom: `0.12` seconds;
- rise/settle: `0.28` seconds;
- post-draw board-effect gap: `0.20` seconds;
- dark ink color compatible with both owner palettes.

Synthesize one dedicated draw WAV containing a brief textured brush onset and a low plucked confirmation timed near settlement. Play it once per drawn card through `DrawAudio`, separate from placement/capture/removal players. Track fast mode explicitly so draw audio is muted even though headless tests already suppress playback.

### Verify

Run `test_duel_integration.gd` in fast mode, then boot the duel normally and confirm no script errors.

## Checkpoint 8: Full Regression and Manual Portrait Playtest

Run all four suites twice. Verify clean pass markers and no new parser/runtime errors.

Manually play in the portrait window and cover:

1. Normal player draw from a full starting hand: only one card returns, face-up, at fixed size.
2. A scripted or naturally reached two-card draw: Ink Summons occur one after another.
3. A draw followed by a flip: brush/pluck audio finishes clearly before capture audio begins.
4. Normal opponent draw: the summoned card lands face-down with no information leak.
5. Testing mode opponent draw: the same card lands face-up and remains manually draggable.
6. A newly drawn card in an earlier physical slot commits as the correct logical instance.
7. Repeated play of a drawn Fa Zheng or Strategist triggers its own fresh draw effect when hand/deck capacity permits.
8. Empty and depleted side decks resolve without errors or extra feedback.

Restore `TESTING_MODE = false` and any temporary deterministic seed before final verification. Keep generated `.superpowers/` mockups ignored and out of commits.
