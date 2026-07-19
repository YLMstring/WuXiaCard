# Build plan — Untitled Wuxia Card Duel

Source: `.summer/GameSoul.md` (2026-07-18)

Target: portrait-first mobile layout, initially verified on desktop at a 9:16 viewport.

## Core scenes

- [ ] `main.tscn` — portrait-safe root UI and story flow coordinator
- [ ] `scenes/duel.tscn` — opponent header, 3×3 board, player hand, score, and turn feedback
- [ ] `scenes/dialogue.tscn` — speaker portrait, dialogue text, and touch-sized branching choices
- [ ] `scenes/card_view.tscn` — reusable card presentation with four edge values and ownership state
- [ ] `scenes/result.tscn` — win/loss resolution and return to the narrative

## Core mechanics (in build order)

1. [ ] **Touch-first edge-capture duel** — select a card, place it on an empty 3×3 cell, compare touching edge values, flip weaker adjacent cards, alternate with a deterministic opponent, and finish when the board is full.
2. [ ] **Branching wuxia dialogue** — present short conversations and two meaningful choices that change the opponent's response and the framing of the duel.
3. [ ] **Complete story outcome loop** — enter dialogue, start the duel, determine win/loss from board ownership, show a matching epilogue, and allow a clean replay.

## First vertical-slice content

- One named rival and one self-contained encounter
- Two prebuilt five-card hands
- One pre-duel choice with two branches
- Win and loss epilogues
- Ink-paper presentation using generated shapes, typography, and restrained red/gold accents

## Mobile and portrait constraints

- Reference viewport: 1080×1920 (9:16), responsive down to common narrow phones
- Touch targets at least 48 logical pixels; no hover-only interaction
- Board and hand remain readable without scrolling during a duel
- Respect safe areas and tolerate tall/aspect-ratio variants
- Mouse input mirrors touch for desktop development

## Cut list (NOT in scope this pass)

- Multiplayer, accounts, leaderboards, or live services
- Deck building, card collection, boosters, rarity, or economy
- Overworld exploration, inventory, quests, or combat outside card duels
- More than one opponent or encounter
- Voice acting, cinematic cutscenes, generated final art, or full audio production
- Save/load, settings, localization, accessibility menu, or mobile store packaging
- Complex card-rule variants, combos, elemental tiles, or special abilities

## Acceptance criteria

- The vertical slice is playable start-to-finish with mouse and touch-style input
- Every dialogue branch reaches the duel and a contextually correct epilogue
- The capture rules and final score are deterministic and testable
- The interface remains usable at a portrait 9:16 viewport
- The project launches without script errors or blocking diagnostics
