# Wuxia Card

A portrait-first Godot/Summer Engine prototype inspired by edge-capture card games and wuxia presentation.

The current build is a single-player 3×3 duel with:

- drag-and-drop play on desktop and mobile;
- four directional powers in top/right/bottom/left order;
- card capture, removal, draws, activate abilities, ki, triggers, and extra turns;
- a deterministic simulator shared by live play and AI;
- perfect-information iterative-deepening alpha-beta AI with a greedy fallback;
- concealed opponent cards in normal mode and manual two-sided testing mode;
- a board-sized parchment card inspector;
- fixed five-slot hands and portrait-responsive UI;
- Android export configuration.

Story/dialogue, deck-building UI, collection progression, and most final card content are not implemented yet.

## Requirements

- Summer Engine `0.5.54` or compatible Godot `4.6.1`
- Windows PowerShell for the included test runner
- Android export: JDK 21 and Android SDK/platform 36

## Run

Open the repository root in Summer Engine or Godot and run `main.tscn`.

The logical viewport is `540×960`, with a `405×720` desktop override. Mobile orientation is portrait.

## Test

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
```

Override engine discovery when needed:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 `
  -EnginePath "C:\path\to\Summer.exe"
```

## Documentation

Start with [docs/HANDOFF.md](docs/HANDOFF.md), then read the root [AGENTS.md](AGENTS.md) before making changes.

Historical feature specs remain under `docs/superpowers/`. They explain prior intent but are not automatically authoritative over current code and tests.

## Repository

The configured remote is `https://github.com/YLMstring/mygame.git`.

Do not commit personal SDK paths, Android keystores, generated `.godot/` data, or `android/` build output.
