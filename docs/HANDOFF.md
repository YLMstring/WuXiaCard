# Wuxia Card Handoff

Updated: 2026-07-26

This is the first document a replacement developer or AI should read. It describes the repository as it exists now, not an aspirational design.

## Current Product

Wuxia Card is a portrait-first Godot/Summer Engine card-duel prototype. The playable scene is `res://main.tscn`, which opens a 3×3 duel. Players drag cards from fixed five-slot hands to the board. Directional power comparisons capture adjacent cards; catalog-driven abilities add draws, removal, movement activations, ki, triggers, and extra turns.

The current opponent uses perfect information and a time-limited iterative-deepening search. Normal play conceals the opponent hand visually. A script-only testing mode reveals both hands and lets one person control both sides.

Not yet present: story/dialogue, result/progression flow, deck-building UI, collection/save data, final content balance, multiplayer, or a release-ready Android package.

## Exact Starting Point

- Engine target: Godot `4.6`, GL Compatibility
- Known working Summer build: Summer Engine `0.5.54`, engine `4.6.1.stable.mono.custom_build.3e132c1e2`
- Main scene: `res://main.tscn`
- Logical viewport: `540×960`; portrait; `canvas_items` stretch
- Production rules: `scripts/duel_simulator.gd`
- Card database: `scripts/card_catalog.gd`
- Encounter hands and side-pool construction: `scripts/duel_decks.gd`
- Runtime/presentation bridge: `scripts/duel_controller.gd`
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
- Each card may have at most one activation. Replacing it keeps passive abilities.
- Runtime card identity is `instance_id`, not a hand child index.
- Main deck currently means the five-card starting hand. The side deck is a separate shuffled draw pile and may contain another copy of a main-hand card.
- Hands are capped at five and always render five fixed physical slots.
- The AI sees both hands and exact deck order.
- Testing mode is fixed when the duel is created and cannot be toggled in-game.

See `docs/DECISIONS.md` for ability-specific behavior.

## Immediate Cautions

- `CangSongYingKe2` resolves `TRIGGER_CARD_SUMMONED` before the summoned card's own `TRIGGER_CARD_AFTER_SUMMONED` rules and standard attack. There is still no general queued player-choice/interrupt engine.
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
