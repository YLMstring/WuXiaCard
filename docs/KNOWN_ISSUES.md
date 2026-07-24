# Known Issues, Gaps, and Risks

Updated: 2026-07-24

## Gameplay and Content

- Tier-2 `CangSongYingKe2` has a description promising a reaction attack when an opponent technique enters, but its `effects` array is empty. The rule is not implemented.
- Only ten catalog definitions exist, and most metadata is placeholder/empty.
- Balance is prototype-level.
- No general queued choice/interrupt/reaction engine exists. `effect_queue` and `pending_choice` are scaffolding only.
- Repetition history exists in state, but no repetition-draw policy is enforced.
- Matches use a broad `max_turns = 200` guard.
- No result/progression screen, story/dialogue flow, deck builder, collection, save/load, tutorial, settings, accessibility menu, or formal localization system.
- Testing mode requires editing `GameSettings.TESTING_MODE` and restarting/recreating the duel.

## AI and Performance

- Dictionary-heavy deep copies and full rule transitions make search expensive.
- `build_compact()` is only a compact hash key, not a compact simulation.
- The transposition key uses two hashes plus encoded length and has a theoretical collision risk.
- Evaluation is generic and will need extension as new reusable effect semantics appear.
- Search is perfect-information by design; it is not suitable for a future hidden-information ruleset without a product decision.
- There is no cross-session opening/endgame database.

## UI and Mobile

- Portrait Android behavior requires continued physical-device testing.
- Chinese wrapping has a current device-verified fix, but future text controls could regress if they use word-only wrapping.
- Some UI values are hard-coded in controller/view scripts rather than centralized theme resources.
- Audio is synthesized placeholder feedback. Draw sound is intentionally absent.
- Glyph rendering on cards is intentionally disabled; pictures are the main card face.
- Safe-area/notch handling and broader device matrix coverage are unfinished.

## Android Release

- Package ID is placeholder `com.example.$genname`.
- Only ARM64 is enabled.
- Versioning/release signing/store metadata are unfinished.
- Min/target SDK values are automatic.
- No release checklist or automated build pipeline exists.
- The current JDK/SDK paths are personal machine configuration.

## Assets and Legal

- `pics/` contains 573 PNG files.
- No asset provenance, author, or redistribution-license manifest was found.
- Resolve ownership and distribution rights before any public/commercial release.

## Repository and Automation

- No CI workflow is present.
- The canonical runner is currently Windows PowerShell-specific.
- `project.godot.bak` and several `scenes/duel.tscn*.tmp` files are tracked. They may be useful recovery artifacts, but should be reviewed and deliberately kept or removed.
- `.gitignore` contains a duplicate `.superpowers/` entry.
- `.summer/build-plan.md` and historical `docs/superpowers/` plans can overstate or misstate current behavior.

## Deferred Work Order Recommendation

1. Continue defining reusable gameplay primitives and tests.
2. Add a real queued choice/reaction mechanism when the first ability requires it.
3. Resolve the printed-but-unimplemented CangSong effect intentionally.
4. Revisit compact simulation after effect vocabulary stabilizes.
5. Add deck-building/save/content pipelines.
6. Harden Android/export/legal/CI only when preparing wider distribution.

Do not treat this ordering as authorization to implement features. Confirm the creator's current priority.
