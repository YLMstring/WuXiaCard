# Wuxia Card Handoff

Updated: 2026-08-02

This is the first document a replacement developer or AI should read. It describes the repository as it exists now, not an aspirational design.

## Current Product

Wuxia Card is a portrait-first Godot/Summer Engine card-duel prototype. The playable scene is `res://main.tscn`, which opens a 3×3 duel. Players drag cards from fixed five-slot hands to the board. Directional power comparisons capture adjacent cards; catalog-driven abilities add draws, removal, movement activations, ki, triggers, and extra turns.

The current opponent uses perfect information and a time-limited iterative-deepening search. Normal play conceals the opponent hand visually. A script-only testing mode reveals both hands and lets one person control both sides.

Completed duels can be replayed in memory from the exact initialized state and
successful action log. Playback reuses the simulator/VFX path with a two-second
turn cadence, preserves opponent concealment, and permits inspection between
actions without producing progression side effects.

The main flow routes the main menu, sect selection, deck builder, duel, reward
selection, and a completed-run ending. The deck-building scene persists a
five-card main deck and exposes a virtualized 1,000-slot collection library.

Not yet present: story/dialogue, final content balance, multiplayer, or a
release-ready Android package.

## Exact Starting Point

- Engine target: Godot `4.6`, GL Compatibility
- Known working Summer build: Summer Engine `0.5.54`, engine `4.6.1.stable.mono.custom_build.3e132c1e2`
- Main scene: `res://main.tscn`
- Deck builder scene: `res://scenes/deck_builder.tscn`
- Ending scene: `res://scenes/ending.tscn`
- Logical viewport: `540×960`; portrait; `canvas_items` stretch
- Production rules: `scripts/duel_simulator.gd`
- Card database: `scripts/card_catalog.gd`
- Persistent deck profile: `scripts/deck_profile_store.gd`
- Encounter hands and side-pool construction: `scripts/duel_decks.gd`
- Runtime/presentation bridge: `scripts/duel_controller.gd`
- In-memory replay snapshot/log: `scripts/duel_replay_record.gd`
- Deck-builder presentation: `scripts/deck_builder_controller.gd`
- Testing switch: `scripts/game_settings.gd`, `TESTING_MODE`
- Android preset: `export_presets.cfg`

Run all automated checks with:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
```

## Read Next

1. `AGENTS.md` — repository-wide change rules
2. `docs/ARCHITECTURE.md` — ownership and data flow
3. `docs/DECISIONS.md` — durable rules agreed with the creator
4. The focused document for the task:
   - `docs/ADDING_CARDS_AND_ABILITIES.md`
   - `docs/AI_SEARCH.md`
   - `docs/UI_AND_ANDROID.md`
   - `docs/TESTING.md`
   - `docs/KNOWN_ISSUES.md`

Use `docs/REPLACEMENT_AI_PROMPT.md` to initialize a new coding assistant.

## Source of Truth

Current production code and passing tests outrank these notes. The plans under `docs/superpowers/` and the files under `.summer/` preserve design history, but some are stale or describe work that was later changed or discarded. Never implement them automatically.

The creator has made several direct UI and localization edits. Preserve those edits. In particular, the current inspector wrapping behavior and card display code are authoritative even if an older plan describes something else.

## Implemented Rules Snapshot

- Board indices are row-major: `0,1,2` top row; `3,4,5` middle; `6,7,8` bottom.
- Power arrays are `[top, right, bottom, left]`.
- A higher opposing power captures; ties do not.
- Player owner ID is `1`; opponent owner ID is `2`.
- A turn permits either playing one hand card or activating one board card.
- Any activation costs one ki.
- Ki survives ownership flips; abilities are lost unless the catalog ability explicitly declares `retained_on_flip = true`.
- Only cards with an activation count as ki-using for bead display.
- A card may declare multiple catalog activations in priority order. A dynamically
  received activation replaces all current activations while preserving passive
  abilities.
- Runtime card identity is `instance_id`, not a hand child index.
- Main deck means the five-card starting hand. Player main-deck glyphs must be
  unique; enemy decks may repeat glyphs and exact IDs.
- The side deck is a separate shuffled draw pile derived independently for each
  owner. Non-`江湖` main cards set same-sect tier ceilings over the full catalog.
  The highest-tier card per glyph survives (catalog order breaks ties);
  `江湖` main cards contribute nothing.
- The player's five-card main deck is loaded from
  `user://wuxia_deck_profile.json`; malformed data is repaired or replaced by a
  valid default.
- The collection library has 1,000 logical entries arranged in four-card rows
  and only 20 live slot views. Library cards retain the standard 3:4 ratio and
  their name color reflects catalog tier.
  Occupied cards are a compact prefix followed by empty slots.
- A library card exchanges with a main-deck slot after a roughly 0.25-second
  hold and drag. When its glyph already exists in another main slot, the
  profile performs the approved three-way rotation without leaving a gap. A
  short tap inspects; immediate movement scrolls.
- Primary unlocks insert at the library top. Still-locked lower-tier cards with
  the same `glyph` and sect append at the library bottom.
- Crossing levels 2, 5, 8, or 11 unlocks all exact-tier cards of the selected
  sect before reward selection. Tier 5 remains the cap through level 15.
- Completed wins and losses increment schema-7 run history atomically. A final
  victory at the configurable threshold (15 by default) skips rewards, records
  `floor(15000 / effective_duel_count)`, preserves the best score for the
  selected sect, closes the run, and restores the default deck.
- Schema 8 stores global mastery by exact card ID. A successful player hand
  play qualifies when that exact ID was in the main deck at duel start; a win
  commits the candidates, while defeat or abandon commits none. `闭关重修`
  preserves mastery and `封剑归隐` clears it.
- Revealed library and reward cards are blue when mastered and red otherwise.
  Revealed enemy cards stay red; unoccupied reward backs keep random colors.
- The ending instances the production main menu so it shares the exact
  background and animated title. It hides the menu actions, lists the selected
  sect and every defeated enemy, and branches for flawless/comeback prose. Its
  smaller score stays fixed beneath the title while the prose rolls upward in
  a clipped clear-sky viewport. Early taps do nothing; after the last line is
  fully visible, the first tap returns to the normal menu.
- Hands are capped at five and always render five fixed physical slots.
- The AI sees both hands and exact deck order.
- Testing mode is fixed when the duel is created and cannot be toggled in-game.
- After victory or defeat, the black replay icon left of the board reconstructs
  the exact opening state and replays all successful actions. It is inert while
  the duel is active or already replaying. The first action is immediate and
  later actions wait two seconds; inspection pauses that wait. Exit cancels the
  replay and returns using the original result. Replay does not run AI or alter
  mastery, enemy memory, profiles, rewards, or progression.
- ZiXiaGong1–4 use the generic `for_each_selected_card` action. The selector
  supports ordered hand/board snapshots, reusable selected-card conditions,
  optional limits, and source-versus-subject execution context.
- CangSongYingKe3–4 use `CARD_BEFORE_FLIPPED` plus the generic
  `add_card_to_hand` action to spend one ki and create a fresh exact copy for
  the pre-flip owner. Full hands still consume the ki.
- SanQinFeng1–3 use the same selector wrapper to make the first 1/2/3 allied
  board sword cards attack sequentially. Each attack resolves completely
  before the next snapshot member is revalidated.
- Attack flips recheck exact attacker/target range after `CARD_BE_ATTACKED`.
  Once `CARD_BEFORE_FLIPPED` starts, movement alone no longer cancels the
  committed flip; the target instance is followed to its current cell.
- Runtime ki and all four powers can change permanently in hand or on board.
  Start-owner-turn triggers run on ordinary and granted extra turns.

See `docs/DECISIONS.md` for ability-specific behavior.

## Immediate Cautions

- `CangSongYingKe2` resolves `TRIGGER_CARD_SUMMONED` before the summoned card's own `TRIGGER_CARD_AFTER_SUMMONED` rules and standard attack. There is still no general queued player-choice/interrupt engine.
- `CARD_BEFORE_FLIPPED` is a committed-flip boundary, not a second attack-range
  check. Future rules that need to cancel a committed flip must do so through a
  non-movement invalidator with explicitly defined semantics.
- `deck_builder.tscn` emits `back_requested` only. Do not add navigation inside
  its controller; connect it from the future scene router.
- Pre-schema-7 active runs cannot reconstruct effective-duel/enemy history.
  Migration deliberately closes those runs and restores the default deck while
  preserving unlocks; do not silently invent completion history.
- Deck-builder tests use isolated `user://` paths. Do not point tests at the
  production profile or a developer's saved deck will make them nondeterministic.
- Repetition state is stored, but no repetition-draw rule is enforced. The only broad loop guard is `max_turns = 200`.
- The search still duplicates Dictionary-based states. `DuelStateKey.build_compact()` is a hashed canonical string, not a compact simulation representation.
- Android package ID is still `com.example.$genname`; only ARM64 is selected; release signing/store setup is unfinished.
- Hundreds of images exist in `pics/`, but no licensing/provenance manifest was found. Resolve this before distribution.
- Generated backup/temp scene files are tracked. Do not delete them without first confirming they are no longer needed.

## Safe First Actions for a New Maintainer

1. Run `git status --short` and do not overwrite user changes.
2. Run the full automated suite.
3. Open and play `main.tscn` at a portrait viewport.
4. Read the code owning the requested behavior and its nearest tests.
5. For rules changes, add simulator coverage before presentation work.
6. Re-run the full suite and manually play the affected flow.

Do not push, publish, tag, alter signing, or delete tracked artifacts without the creator's explicit approval.
