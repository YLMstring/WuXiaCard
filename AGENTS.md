# Wuxia Card — Agent Guide

This file applies to the entire repository. It is intentionally tool-neutral: Codex, Claude Code, Cursor, Copilot, Gemini, and human contributors should follow the same rules.

## Start Here

Before changing anything:

1. Read `docs/HANDOFF.md`.
2. Read the relevant architecture or workflow document linked from it.
3. Run `git status --short` and preserve all user-owned changes.
4. Run `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1` before and after behavioral changes.
5. Inspect current code and tests instead of assuming an old plan is already implemented.

## Source-of-Truth Order

When sources disagree, use this order:

1. Current production code and passing tests
2. `docs/HANDOFF.md`, `docs/ARCHITECTURE.md`, and `docs/DECISIONS.md`
3. Focused documents in `docs/`
4. Historical specs and plans under `docs/superpowers/`
5. `.summer/GameSoul.md` and `.summer/build-plan.md` as broad vision/history only
6. Chat transcripts or agent memory

Never implement a historical plan merely because it exists. Confirm that it still matches the user's current request.

## Non-Negotiable Architecture Rules

- `DuelSimulator` is the authoritative gameplay rules path for humans, testing mode, greedy fallback, and deep AI.
- `DuelController` presents simulator transitions. Do not add gameplay-only branches to the controller.
- `DuelState` and `DuelAction` contain pure data only. No scene nodes, Controls, tweens, audio players, or mutable live UI references.
- Search code must remain card-agnostic. It may evaluate generic powers, ownership, zones, ki, legal actions, and active-ability counts; it must not check named card IDs.
- Card definitions live in `scripts/card_catalog.gd`. Encounter hands live in `scripts/duel_decks.gd`.
- Runtime card identity uses `instance_id`. Never rely on visual child order after cards are drawn into fixed hand slots.
- A card can have at most one activation. Replacing its ability entry removes the previous activation while preserving passive abilities.
- Activating any ability costs one ki. Ki is independent state and survives ownership flips.
- Abilities are lost on flip unless the catalog ability explicitly sets `retained_on_flip = true`.
- New abilities must emit pure-data events for presentation and must be covered by simulator tests before UI work.

## Player-Visible Invariants

- Portrait-first mobile layout; reference viewport is 540×960 logical pixels.
- Mouse behavior mirrors touch behavior.
- Hands always contain five fixed physical slots; remaining cards never resize or repack when a slot becomes empty.
- Power order is top, right, bottom, left.
- Board cell order is row-major: left-to-right across each row, then top-to-bottom (`0..8`).
- Normal mode conceals the opponent hand. Testing mode reveals and manually controls both sides.
- Revealed cards can be tapped for inspection. Face-down cards must never leak metadata.
- Chinese UI text that can exceed one line must use smart or arbitrary wrapping, not word-only wrapping.

## Safe Change Workflow

For a new card or ability:

1. Add/validate catalog data.
2. Add a pure simulator fixture that fails without the feature.
3. Implement generic effect, targeting, or trigger primitives.
4. Add transition events.
5. Add controller presentation.
6. Add integration coverage.
7. Run all test suites and play the production path.

For a bug:

1. Reproduce it.
2. Identify the root cause.
3. Add the smallest regression test possible.
4. Make one focused fix.
5. Re-run the failing test and the full suite.

## Repository Hygiene

- Do not rewrite, delete, or revert unrelated user changes.
- Do not use destructive Git commands.
- Keep commits focused and describe behavior, not agent activity.
- Do not commit `.godot/`, `android/`, `.summer/local/`, or `.superpowers/`.
- Do not push, publish, tag, or alter remote state without explicit user approval.
- Never commit keystores, passwords, access tokens, personal SDK settings, or other secrets.

## Verification

The canonical Windows command is:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
```

Current suites:

- `test_card_catalog.gd`
- `test_card_inspector.gd`
- `test_duel_rules.gd`
- `test_duel_simulator.gd`
- `test_duel_search.gd`
- `test_duel_integration.gd`

A feature is not complete merely because scripts compile. For gameplay or visual changes, run the game and walk the affected user flow at a portrait viewport. Android-specific UI fixes need a device or Android build check.

## Handoff Entry Points

- Current state and next steps: `docs/HANDOFF.md`
- Architecture and data flow: `docs/ARCHITECTURE.md`
- Durable product decisions: `docs/DECISIONS.md`
- Adding cards/abilities: `docs/ADDING_CARDS_AND_ABILITIES.md`
- AI search: `docs/AI_SEARCH.md`
- UI and Android: `docs/UI_AND_ANDROID.md`
- Tests and setup: `docs/TESTING.md`
- Known gaps and risks: `docs/KNOWN_ISSUES.md`
- Prompt for a replacement AI: `docs/REPLACEMENT_AI_PROMPT.md`
