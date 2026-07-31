# Testing

## One-Command Suite

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
```

Optional engine override:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 `
  -EnginePath "C:\path\to\Summer.exe"
```

The runner also recognizes `SUMMER_ENGINE_EXE`, then checks the standard per-user Summer Engine location, then commands available on `PATH`.

## Suites

- `test_card_catalog.gd` — schema, metadata, ability/trigger validation, instance normalization.
- `test_deck_profile_store.gd` — default profile, validation/repair, atomic persistence, exchanges, unlock ordering, and save-failure rollback.
- `test_deck_library_grid.gd` — 1,000-slot sizing, four-column virtualization, 3:4 layout, tier colors, pooled rebinding, and gesture behavior.
- `test_deck_builder_integration.gd` — scene composition, concealment/testing reveal, inspection, real drag hit-testing, exchanges, persistence, back signal, and fixed-aspect layout.
- `test_card_inspector.gd` — modal display data and inspector interaction behavior.
- `test_duel_backdrop.gd` — fixed 9:16 duel canvas and decorative overflow layout.
- `test_duel_rules.gd` — board geometry and baseline capture helpers.
- `test_duel_card_selector.gd` — generic zone ordering, filters, limits,
  movement-tolerant snapshots, and condition revalidation.
- `test_duel_simulator.gd` — legal actions, rules, abilities, triggers, ki, draw/removal/movement/extra turns.
- `test_duel_search.gd` — evaluation/search, deadlines, determinism, fallback, and state keys.
- `test_duel_integration.gd` — scene/controller presentation and live-path synchronization.
- `test_zixia_integration.gd` — hand/board mutable-value presentation and
  face-down concealment for generic selected-card effects.

These are `SceneTree` scripts run with:

```text
--headless --path <project> --script res://tests/<suite>.gd
```

Each suite must emit its `_PASSED` marker, return exit code zero, and produce no `ERROR:`, `SCRIPT ERROR`, `_FAILED`, or `CHECK_FAILED` output.

Summer Engine may print `WARNING: ObjectDB instances leaked at exit` because of its own AuthManager lifecycle. The runner does not fail on warnings alone. Investigate any actual `ERROR:` line.

## Expected Baseline

The full baseline after the persistent deck builder contains ten passing
suites and at least 934 checks:

- catalog: 270
- deck profile: 24
- library grid: 29
- deck-builder integration: 24
- inspector: 17
- backdrop: 19
- rules: 27
- simulator: 174
- search: 37
- integration: at least 313

Treat the fresh runner output as authoritative; counts can change as tests grow and integration paths vary.

## Change-Level Verification

### Catalog-only content

Run catalog tests, simulator tests if abilities changed, full suite, then open the inspector for the card.

### Rules/abilities

Add a failing simulator case first. Verify state plus ordered events. Run simulator, search, integration, then full suite. Play both human and AI paths.

### Search

Run simulator and search suites. Check deterministic action selection and deadline fallback. Play with the production 10-second budget and inspect `AI_SEARCH` logs.

### UI

Run inspector/integration and full suite. Manually test at 540×960 and Android-like aspect ratios with mouse and touch. Automated headless checks do not prove visual correctness.

For deck-builder UI changes, also run the profile, library-grid, and
deck-builder integration suites. Manually verify tap-to-inspect,
hold-then-drag exchange, swipe scrolling, invalid drops, and normal/testing
opponent concealment.

### Android

Export, install, and test on a physical device. Desktop wrapping/layout is not proof of Android behavior.

## Fresh-Evidence Rule

Never report that a change passes based on an earlier run. Run the relevant complete command after the final edit, read its exit status and failure lines, then report the evidence.

Existing editor diagnostics can include stale Summer authentication/setup messages. Clear the editor console before evaluating a fresh run.

## Test Design Rules

- Use stable `instance_id` values.
- Assert catalog declarations separately from simulator behavior.
- Test both owners.
- Test retained and lost abilities across flips.
- Test terminal and no-legal-action states.
- Test event order where presentation depends on it.
- Seed deck shuffles when exact order matters.
- Do not test rules through controller-only shortcuts.
- Keep AI tests deterministic and use explicit deadlines/limits.
