# Prompt for a Replacement AI

Copy the following into a new coding assistant while its working directory is the repository root.

---

You are maintaining **Wuxia Card**, a portrait-first Godot/Summer Engine project.

Before changing anything:

1. Read `AGENTS.md` completely.
2. Read `docs/HANDOFF.md`, `docs/ARCHITECTURE.md`, and `docs/DECISIONS.md`.
3. Read the focused document relevant to my request.
4. Run `git status --short` and preserve all existing user changes.
5. Run `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1` to establish a fresh baseline.

Important constraints:

- Current code and passing tests outrank historical plans under `.summer/` or `docs/superpowers/`.
- `DuelSimulator` is the sole gameplay rules authority for humans, testing mode, greedy AI, and deep search.
- `DuelController` presents pure-data transition events; do not put independent gameplay rules in UI code.
- Keep `DuelState` and `DuelAction` free of scene/UI objects.
- Keep AI search and evaluation card-agnostic. Never branch on a named card ID in search.
- Add cards in `scripts/card_catalog.gd` and encounter hands in `scripts/duel_decks.gd`.
- Use `instance_id` for physical card identity.
- Effects default to lost on flip; ki survives. Only activate abilities count for ki-bead eligibility.
- Preserve portrait/mobile layout, five fixed hand slots, concealed normal-mode opponent hand, and touch/mouse parity.
- Do not revive discarded glyph display or old inspector/wrapping designs. The current user-edited UI code is authoritative.
- Do not commit secrets, personal SDK paths, keystores, generated Android output, or `.godot/`.
- Do not push, publish, tag, delete tracked artifacts, or change remote state unless I explicitly ask.

For behavioral changes, add a focused failing test first, implement through generic simulator primitives, run the full suite after the final edit, and manually play the affected portrait flow before saying it works.

`CangSongYingKe2` implements its printed summon reaction through generic catalog trigger/condition/action vocabulary. `TRIGGER_CARD_AFTER_SUMMONED` scans the full board in row-major source order, so CangSongYingKe2 and the summoned card's own entrance rules share that window before the normal attack; search inherits it through `DuelSimulator`.

First tell me briefly what files own my requested behavior and any conflict you see between my request and current rules. Then proceed unless a genuinely consequential choice is missing.

My request is:

[PASTE REQUEST HERE]

---

If the replacement tool supports persistent repository instructions, point it to root `AGENTS.md`. Do not paste chat history as a substitute for the repository handoff; the documented code boundaries are safer and easier to update.
