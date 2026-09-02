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
- `test_deck_profile_store.gd` — default profile, validation/repair, schema
  migration through per-difficulty score schema 11, difficulty persistence,
  atomic saves, exchanges, unlock ordering, and save-failure rollback.
- `test_ending_profile.gd` — effective-duel history, atomic completion,
  difficulty-specific score caps and downward propagation, per-sect isolation,
  difficulty unlock/reset behavior, and legacy migration.
- `test_deck_library_grid.gd` — 1,000-slot sizing, four-column virtualization, 3:4 layout, tier colors, pooled rebinding, and gesture behavior.
- `test_deck_builder_integration.gd` — scene composition, concealment/testing reveal, inspection, real drag hit-testing, exchanges, persistence, back signal, and fixed-aspect layout.
- `test_sect_selection_integration.gd` — sect previews and selection plus
  difficulty-arrow assets, layout, wrapping, Chinese text, immediate
  persistence, and run-start propagation.
- `test_card_inspector.gd` — modal display data and inspector interaction behavior.
- `test_ending_scene.gd` — reused menu presentation, compact clear-sky layout,
  dynamic prose branches, Chinese wrapping, measured clipped roll, early-tap
  lock, exact final stop, and single post-roll return.
- `test_ending_flow.gd` — threshold-one final-victory routing, reward bypass,
  persistent completion, early-tap gating, and fresh-journey navigation.
- `test_music_director.gd` — fixed-resource loading, exact fixed per-track weights,
  pool continuation, special tracks, natural `lose` expiry, fade-before-start
  ordering, and latest-request-wins cancellation.
- `test_music_flow.gd` — production screen-to-context routing, bidirectional
  menu/sect and deck/reward continuation, exact reward-ID propagation,
  `terror`/one-shot `lose`, battle selection, `bixie`, and testing-mode
  `lonely` exclusion.
- `test_duel_backdrop.gd` — fixed 9:16 duel canvas and decorative overflow layout.
- `test_duel_rules.gd` — board geometry and baseline capture helpers.
- `test_duel_opening_setup.gd` — the exact 12-pair Bagua layout space, seeded
  reproducibility, later-owner identity, untouched turn/deck data, and retained
  pre-flip exile behavior.
- `test_duel_card_selector.gd` — generic zone ordering, filters, limits,
  movement-tolerant snapshots, and condition revalidation.
- `test_duel_simulator.gd` — legal actions, rules, abilities, triggers, ki,
  draw/removal/movement, extra-card-play allowances, and turn boundaries.
- `test_native_production_rules.gd` — independent complete-runtime fixtures for
  every catalog hand play and legal catalog activation, exact native/Oracle
  state and ordered-event parity, native fixed-depth score/action parity,
  node-budget semantics, production routing, cancellation, and same-turn
  principal-action reuse. Historical fine-grained rule/card suites call the
  Oracle explicitly and are not counted as native coverage.
- `test_duel_search.gd` — evaluation/search, deadlines, minimum completed-depth
  node guards, deterministic ordering,
  lazy-transition/PVS exactness, bounded tactical extension,
  opt-in evaluation caching, fallback, and state keys.
- `test_duel_ai_benchmark.gd` — versioned enemy roster/manifest validation,
  deterministic rebuilds, mutable-state isolation, minimum-depth mode wiring,
  per-game progress/checkpoint serialization, and a tiny four-game runner
  smoke. Formal matches are intentionally excluded from the daily full suite.
- `test_duel_integration.gd` — scene/controller presentation and live-path synchronization.
- `test_duel_replay_record.gd` — independent initial/final state snapshots,
  immutable ordered action copies, readiness, access isolation, and reset.
- `test_duel_replay.gd` — terminal replay gating, live/current-replay opponent
  hand-play inspection, supplied icon and touch feedback, exact state
  reconstruction, repeated playback, side-effect suppression, concealment,
  inspection-paused timing, recovery, and exit.
- `test_card_mastery.gd` — exact-ID eligibility, successful-play capture,
  identical-copy qualification, namesake exclusion, and deduplication.
- `test_zixia_integration.gd` — hand/board mutable-value presentation and
  face-down concealment for generic selected-card effects.
- `test_wanyue_dasongyang_abilities.gd` — signed literals, dynamic hand count,
  zero-floor removal, original-owner zones, batch metadata, all eight card
  declarations, summon timing, and lethal global reactions.
- `test_power_change_integration.gd` — parallel visible batch starts, one
  shared pre-change pause and duration, old/final four-side values,
  repeated-instance visual coalescing, gain/loss styling, and hidden-card
  no-wait concealment.
- `test_yinyang_zhangli_abilities.gd` — four-side `-1` presentation and
  immunity, limited-selector skipping, tiered distance-two attacks,
  exile/draw/grant ordering, newly drawn palm inclusion, nonrecursive repeat
  attacks, duplicate-grant handling, and flip cleanup.
- `test_fumo_qianshou_abilities.gd` — movement-before power loss and stacking,
  empty-hand idempotent grants, enemy-intervening range, after-exile snapshots,
  zero-power and four-`-1` filtering, complete runtime perfect copies,
  competing original-cell summons, and discard-based flip prevention.
- `test_hanbin_tianwai_abilities.gd` — enemy-hand target snapshots, active
  YinYang no-effect/reveal behavior, last-ki flip ordering, staged
  self-after-flip cleanup, automatic YinYang skipping, shared power batches,
  permanent granted-ability loss, trigger-card swaps, tier-3 power changes,
  and multi-source row-major revalidation.
- `test_dugu_nine_swords_abilities.gd` — exact declarations, state-copy/key
  coverage, source/adjacent exile-draw order and ownership, previous-play
  return order/full-hand fallback, reveal events, heart-method skipping,
  retained-ability survival, permanent suppression, and queued layers.
- `test_activation_targeting_swap_presentation.gd` — anchored board activation
  traces, fixed enemy-hand-slot hit testing, logical hand target commits,
  exact-card reveal presentation, and ordinary move/swap view identity.
- `test_cangsong_sanqin_abilities.gd` — before-flip timing, fresh catalog hand
  additions, full-hand behavior, non-attack flips, sequential selected-card
  attacks, and normal-mode concealment.
- `test_hengshan_three_families.gd` — before-summon suppression and restoration,
  exact attack-flip swaps, failed-swap attack cancellation, movement-triggered
  suppression, lowest-index movement/draw, retention, and flip cleanup.
- `test_jianfa_yanhui_abilities.gd` — lowest-index entry movement,
  activation-only movement plus extra-card-play restrictions, turn-scoped
  suppression, exact leftmost replacement, and other-ally fresh-copy activation.
- `test_jianfa_yanhui_integration.gd` — production-scene exact hand-view reuse,
  return-before-summon ordering, and simulator/view identity synchronization.
- `test_jinzhen_wanhua_abilities.gd` — fresh returns, full-hand exile,
  revalidation, generated summon/attack ordering, retention, and pre-terminal
  board reopening.
- `test_jinzhen_wanhua_integration.gd` — generated board views plus return and
  self-removal fade ordering through the production controller.
- `test_mianli_cangzhen3.gd` — trigger ownership, fresh in-place identity,
  movement following, no-effect handling, full summon/attack ordering, and
  flip-loss behavior.
- `test_mianli_cangzhen3_integration.gd` — production-controller old-view fade
  before fresh ink summon and final simulator/view identity synchronization.

These are `SceneTree` scripts run with:

```text
--headless --path <project> --script res://tests/<suite>.gd
```

Each suite must emit its `_PASSED` marker, return exit code zero, and produce no `ERROR:`, `SCRIPT ERROR`, `_FAILED`, or `CHECK_FAILED` output.

Agent-run visible or device playtests must be silent. Start them with a dummy
audio driver or mute the master audio bus before entering the game. Do not
change production music or sound-effect defaults for test convenience.

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

For before-flip effects, separately assert the post-`CARD_BE_ATTACKED` range
recheck, absence of both flip events when it fails, target relocation after
`CARD_BEFORE_FLIPPED`, and non-movement cancellation. For selector-driven
attacks, assert that each complete attack chain precedes revalidation of the
next snapshot member.

### Search

Run simulator and search suites. Check deterministic action selection and deadline fallback. Play with the production 10-second budget and inspect `AI_SEARCH` logs.

Run paired AI strength samples separately with:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_ai_benchmark.ps1 -Mode Quick
```

`Quick` uses 7 enemy matchups/28 games and `Extended` uses all 28
matchups/112 games. Both use a nominal 1,500 nodes per decision and protect
complete-round depth one with `min_completed_depth = 1`; nodes are not reset
after depth one, so reports must inspect guard-use and overrun diagnostics.
`Production` uses 4 matchups/16 games with the real 10-second decision budget,
no minimum-depth guard, and Dummy audio. Each matchup is a balanced four-game
crossover of deck, owner/initiative, and enhanced/baseline profile. Pilot is
optional and is not required before Extended.

Extended emits one `AI_BENCHMARK_GAME` line per completed game. It also appends
one independently parseable record to a sibling `.progress.jsonl` checkpoint;
an interrupted run retains completed lines, but that partial file is not a
final strength result. The final JSON references the checkpoint. Extended Final
requires at least 55% match points, 75% initial-depth non-regression, no worse
fallback rate, and no incomplete games. All results live under
`.summer/local/ai-benchmarks/` and must not be committed.

For the isolated PVS ablation, first run the search suite and the real-opening
fixed-depth oracle. The oracle script is
`res://tests/benchmarks/real_quick_search_equivalence.gd`; run it headless with
Dummy audio after the ordinary suite. It must report identical fixed-depth
scores/actions for LazyOnly and Lazy+PVS across all 14 openings.

Then run:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_ai_benchmark.ps1 -Mode Extended -Variant LazyPVS
```

This variant configures both sides identically except for PVS and goes directly
to all 112 games; do not insert Quick or Pilot. Production PVS stays disabled
until the creator reviews the final evidence.

Profile production LazyOnly complete-round opening depth separately with:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_production_opening_profile.ps1
```

This runs the 14 unique real Quick openings with the production ten-second
budget, Dummy audio, per-complete-round-depth and partial-root diagnostics,
plus three node-limited timing probes. The current target is complete-round
depth two; the JSON report explicitly records `depth_unit = complete_round` so
it cannot be compared as if it were an old action-ply result. Its report is written under
`.summer/local/ai-benchmarks/` and must not be committed.

Run the 512-state/1,024-action simulator transition microbenchmark with Dummy
audio through:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_transition_microbenchmark.ps1
```

### UI

Run inspector/integration and full suite. Manually test at 540×960 and Android-like aspect ratios with mouse and touch. Automated headless checks do not prove visual correctness.

For deck-builder UI changes, also run the profile, library-grid, and
deck-builder integration suites. Manually verify tap-to-inspect,
hold-then-drag exchange, swipe scrolling, invalid drops, and normal/testing
opponent concealment.

For background-music changes, run `test_music_director.gd`,
`test_music_flow.gd`, `test_reward_selection_integration.gd`,
`test_main_flow.gd`, and `test_ending_flow.gd`. Then listen through the
production main scene: menu/sect continuation, deck/ordinary-reward
continuation, battle replacement, `terror`, one-time `lose`, ordinary
`lonely`, and qualifying `bixie`. Confirm a mid-track scene switch fades rather
than cutting abruptly.

For mastery changes, run `test_card_mastery.gd`, `test_deck_profile_store.gd`,
`test_ending_profile.gd`, `test_deck_builder_integration.gd`,
`test_reward_selection_integration.gd`, `test_main_flow.gd`, and
`test_ending_flow.gd`. Verify abandon/defeat do not commit, ordinary/final wins
do commit, run reset preserves, full reset clears, and reward placeholders
remain random.

For replay changes, run `test_duel_replay_record.gd`, `test_duel_replay.gd`,
`test_duel_outcome.gd`, `test_card_mastery.gd`, `test_enemy_memory.gd`,
`test_card_inspector.gd`, `test_duel_backdrop.gd`, and
`test_duel_integration.gd`. Manually complete a normal-mode duel, replay it
twice at the production two-second cadence, confirm the enemy hand stays
concealed, use the replay button to inspect the latest opponent hand play in
both live play and a replay gap, verify the gap pauses and touch feedback
remains, and exit during playback to confirm original-result routing.

For ending changes, run `test_ending_profile.gd`, `test_ending_scene.gd`,
`test_ending_flow.gd`, and `test_main_flow.gd`. Manually verify both flawless
and loss prose, all enemy names, portrait safe-area wrapping, fixed score,
clipped constant-speed rolling, early-tap rejection, final reward bypass,
post-roll tap-to-menu, and a fresh sect-selection journey afterward.

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
- Disable or seed both starting-hand and side-deck shuffles when exact order
  matters.
- Do not test rules through controller-only shortcuts.
- Keep AI tests deterministic and use explicit deadlines/limits.
