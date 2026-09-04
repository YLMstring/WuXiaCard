# AI Search

## Current authority

There is one production rules implementation and one production deep-search
implementation: `DuelNativeCompactKernel` in `native/duel_core/`.

- `scripts/duel_simulator.gd` is the public rules facade for human play,
  testing mode, replay, greedy fallback, and AI actions.
- `scripts/duel_native_rules.gd` converts `DuelState` to the compact native
  payload and restores pure-data states and events.
- `scripts/duel_search.gd` normalizes public search results and delegates the
  complete descendant tree to the native kernel.
- `scripts/duel_search_session.gd` owns the worker thread, cancellation, and
  progress transport.

The former independent GDScript rules/search Oracle was retired on 2026-09-02.
Do not add a second transition engine or a fallback that silently resolves a
native rejection through GDScript. The last passing pre-removal seal is
recoverable from commit `e68885d`; it passed 4,812 checks across 56 deterministic
walks and 584 actions. That commit is recovery evidence, not an implementation
to keep synchronized.

## Information model

The opponent has perfect simulation information: both complete hands and exact
deck order. Concealment is presentation-only. Search remains card-agnostic and
may evaluate generic ownership, zones, powers, ki, legal actions, and active
ability counts, but it must never branch on a named `card_id`.

The native kernel loads one isolated root, compiles immutable catalog
declarations, and keeps legal-action enumeration, branch copies, rules
resolution, evaluation, ordering, alpha-beta traversal, and iterative deepening
inside C++. Only completed-depth progress, the chosen action, and the current
owner's principal continuation cross back to GDScript.

Search transitions keep the event skeletons that rules resolution reads, but
do not materialize complete runtime-card dictionaries inside presentation-only
draw/discard/transform/summon/return events. They also skip the final
presentation-only capture/exile index summaries. Public gameplay transitions
still return the complete event payloads. On the same 14 real openings with a
two-second `self_turn` budget, this raised aggregate throughput from `9987.37`
to `10465.11` nodes/s (`+4.78%`), while all 14 opening digests and deepest
completed depth/score/action tuples matched; depth two remained `13/14`.

## Depth and publication

Search depth is measured in authoritative `owner_turn_serial` boundaries, not
action plies. Two selectable modes share the same native search implementation:

- `self_turn` is the production default. Public depth `d` consumes
  `2 × d - 1` boundaries: depth one finishes the current owner's remaining
  turn; depth two additionally finishes the opponent turn and the root owner's
  next turn.
- `complete_round` remains available as an explicit legacy comparison mode.
  Public depth `d` consumes `2 × d` boundaries: depth one finishes the current
  owner's remaining turn and the following opponent turn.

Automatic empty turns consume the boundaries they actually cross and do not
add artificial depth. A granted same-turn extra play adds work but no boundary;
the gameplay rule permits at most one successful grant per owner turn.

Iterative deepening publishes only the deepest fully completed iteration. An
incomplete deeper attempt is diagnostic data and never replaces the last
complete action. Production uses a hard ten-second deadline. Node-limited
Quick and Extended diagnostics use `min_completed_depth = 1`: a nominal node
limit may be exceeded until depth one completes, while deadlines and explicit
cancellation remain hard.

If no iteration completes, the worker fails, or the returned action is stale or
illegal, the controller uses deterministic greedy fallback. Search may finish
early when the position is solved.

## Same-turn continuation

The completed principal line may include additional actions by the same owner
within the current `owner_turn_serial`. `DuelTurnPlan` makes that continuation
eligible only when the producing result completed at least depth two without
fallback, and then reuses it only while all of these still match:

- exact compact state key;
- owner ID;
- owner-turn serial;
- current legality of the next action.

Any mismatch clears the remainder and starts a normal fresh search.

A depth-zero or depth-one action remains valid for the current decision, but
its continuation is discarded. If that action grants an extra play, the
controller searches again from the resulting exact state. New searches and
reused actions share a presentation-only two-second minimum decision time;
actual search time counts toward the minimum, and testing fast mode removes it.

## Native reuse and action ordering

Production enables three card-agnostic search aids:

- internal PV ordering reuses the matching action from the previous fully
  completed iterative-deepening result; hints from interrupted iterations are
  discarded;
- conservative history ordering rewards generic action shapes that actually
  caused cutoffs. Its key contains owner, source location, target shape,
  powers, ki, ability count, and activation index, but never card IDs, names,
  instance IDs, or physical hand-slot identity.
- a fixed two-way native transposition table reuses completed `EXACT`, `LOWER`,
  and `UPPER` entries whose complete state checksum and remaining owner-turn
  boundaries both match. It is scoped to one root search and shared across
  iterative-deepening passes.

The final priority is `PV > transposition move > structural ordering > history
> canonical key`.
Putting history ahead of structural ordering was measured and rejected because
it made several real openings substantially shallower. History is scoped to a
single root search, uses a saturating quadratic cutoff reward, and decays after
each completed public depth. Explicit `false` switches remain available to
controlled benchmarks through `use_internal_pv_ordering` and
`use_history_ordering`; normal production calls default both to `true`.

The table is also independently controlled by `use_transposition_table` and
`transposition_table_mib`. `DuelSearch.find_best_action_iterative()` defaults
it to 8 MiB on both desktop and Android. The direct native entry keeps it off
unless a test or benchmark opts in. Capacity is a strict fixed-array ceiling,
never grows with play time, and is released after each root decision. An
allocation failure degrades to table-off rather than failing the AI action.
Cached compact actions are matched against the current legal-action list before
ordering or same-turn principal-line restoration.

High-frequency timing and ordering counters are gated by
`collect_search_diagnostics`, which defaults to `false`. Enabling diagnostics
is for node-limited probes only and must not be used for production timing.
The same switch can count transposition opportunities without changing search
results: an exact key combines the complete native-state checksum with remaining
owner-turn boundaries; a stricter reusable hit requires that an earlier visit
has already returned. Leaf and internal-node hits are reported separately.
When the real table is enabled, the same diagnostics also report table probes,
exact/bound hits, direct returns, bound cutoffs, stores, updates, replacements,
collisions, compact-move validation, capacity, and allocation fallback.

## Search result contract

`DuelSearch.find_best_action_iterative()` is the public entry point.
`find_best_action_iterative_native()` is retained as an explicit compatibility
alias for native-focused tests, not as a different algorithm.

The result includes at least:

- `action`, `score`, `completed_depth`, and `has_completed_depth`;
- `nodes`, generated/applied transition counts, cutoffs, and root progress;
- completion reason and elapsed time;
- minimum-depth guard/overrun diagnostics;
- completed-depth snapshots and `turn_plan`.

Legacy profile fields may still appear in report schemas, but they no longer
select the removed GDScript PVS, tactics, evaluation cache, or evaluator
variants. Add future native strategies as explicit native features with tests;
do not revive the old backend switch.

## Correctness gates

Rules and search changes require:

1. focused native simulator fixtures for the changed semantics and ordered
   events;
2. catalog declaration coverage and strict unsupported-declaration audits;
3. `test_duel_simulator.gd`, `test_native_production_rules.gd`, and
   `test_duel_search.gd`;
4. controller integration coverage when transition presentation changes;
5. the full canonical suite;
6. a silent production-path playtest.

Native rejection is an integration fault, not permission to approximate a
transition or fall back to another engine.

## Benchmarks

Run the real enemy-catalog benchmark with Dummy audio:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_ai_benchmark.ps1 -Mode Quick
powershell -ExecutionPolicy Bypass -File tools/run_ai_benchmark.ps1 -Mode Extended
powershell -ExecutionPolicy Bypass -File tools/run_ai_benchmark.ps1 -Mode Production
```

- Quick: 7 matchups / 28 games, nominal 1,500 nodes per decision.
- Extended: all 28 matchups / 112 games, nominal 1,500 nodes, one progress
  record written immediately after every game.
- Production: 4 matchups / 16 games using the real ten-second budget.

All seats now run the same native backend. Historical `enhanced` and `baseline`
labels remain in serialized benchmark records only as balanced assignment
labels; match-point percentages are not an A/B strength claim. The Extended
gate checks schedule completeness, terminal completion, and valid execution.

Profile the 14 unique real Quick openings separately with:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_production_opening_profile.ps1
powershell -ExecutionPolicy Bypass -File tools/run_production_opening_profile.ps1 -DepthMode complete_round
powershell -ExecutionPolicy Bypass -File tools/run_production_opening_profile.ps1 -DepthMode self_turn -OpeningSet extra_play_cap -MaxOpenings 4 -UseInternalPvOrdering -UseHistoryOrdering -CollectTranspositionDiagnostics
powershell -ExecutionPolicy Bypass -File tools/run_production_opening_profile.ps1 -DepthMode self_turn -OpeningSet extra_play_cap -MaxOpenings 4 -UseInternalPvOrdering -UseHistoryOrdering -UseTranspositionTable -TranspositionTableMiB 8
```

Reports are written under `.summer/local/ai-benchmarks/` and must not be
committed. Compare measurements from the same engine build, binary type,
machine state, fixture version, limits, and opening digest.

Native performance comparisons on Windows must load a C++ `Release` build
compiled for Godot's `template_debug` ABI:

```powershell
powershell -ExecutionPolicy Bypass -File tools/build_duel_native.ps1 -Configuration Release -GodotCppTarget template_debug
```

A `Debug + template_debug` library is valid for correctness debugging but is
roughly half-speed here and must not be compared with Release benchmark data.

The 2026-09-03 four-opening `self_turn` ordering evaluation used the same real
Quick fixtures and ten-second budget. The optimized final candidate (cached
ordering fields and mobility counts, internal PV, and conservative history)
reached `11666.0` nodes/s versus the phase baseline's `10130.05` (`+15.2%`).
It still completed depth two in 2/4 openings; the two incomplete estimates
improved to `15.20s` and `10.60s`. Strict history priority was rejected after
it reduced depth-two completion to 1/4. These figures are performance evidence,
not a claim that a different equal-score move is strategically stronger.

The 2026-09-04 transposition-opportunity probe used the four extra-play-cap
openings, production PV/history ordering, `self_turn`, and ten seconds per
opening. Across 460,706 visited nodes, 333,262 exact keys had already completed:
a `72.34%` reusable-hit rate. Leaves were `73.74%` (302,657/410,431), while
internal nodes were still `60.88%` (30,605/50,275). State-only matching was
`72.47%`, only 0.13 percentage points above exact remaining-depth matching.
This strongly motivates a bounded native transposition table, but it is an
opportunity rate rather than a predicted speedup: real entries must preserve
exact/lower/upper bound types, requested depth, deadline safety, and memory
limits. Diagnostic hashing and sets are default-off and their measured
throughput must not be compared directly with the ordinary benchmark baseline.

The subsequent real-table Release ablation used those same four openings,
`self_turn`, PV/history ordering, and ten seconds per opening. With the table
off, only 2/4 initial searches completed depth two. Every tested fixed capacity
(4, 8, 16, and 32 MiB) completed depth two in 4/4; larger tables showed no
stable advantage over 8 MiB, so production keeps the shared 8 MiB default. A
longer table-off run confirmed all four depth-two scores and canonical actions
match the 8 MiB result. Per-opening complete-depth-two times changed from
`7.79s`, `6.50s`, `15.48s`, and `11.94s` to `6.25s`, `4.89s`, `0.77s`, and
`0.48s`; visited nodes fell by `21.6%`, `27.8%`, `95.1%`, and `95.8%`.

The separate 8 MiB diagnostic run recorded 424,028 probes and 74,877 real hits
(`17.66%`): 50,425 exact returns and 24,188 bound cutoffs. It used exactly
8,388,608 entry bytes, had no allocation fallback and no illegal cached moves.
Its 19,111 replacements/collisions explain why the earlier unbounded
opportunity percentage is not the real-table hit rate. Diagnostic counters are
still unsuitable for throughput comparison.

The final production-selection ablation kept `self_turn` and the 8 MiB table
fixed. Removing internal PV raised complete-depth-two work by `2.1%` across the
four extra-play-cap openings and cut one opening's unfinished depth-three root
progress from eight completed root actions to four. A broader 14-opening Quick
comparison then measured conservative history: removing it preserved all
same-depth scores/actions and the same `12/14` depth-three completion count, but
raised work at the deepest common completed depths from 674,534 to 754,193
nodes (`+11.81%`) and elapsed time from 65.706 to 70.953 seconds (`+7.99%`).
Production therefore uses `self_turn`, internal PV, conservative history, and
an 8 MiB transposition table together.

The 2026-09-02 ten-second `self_turn` profile completed depth two in all 14
unique real Quick openings and depth three in 9/14. The two previously slow
Dongfang Bubai/Zhang Sanfeng openings completed depth two in 9.46 seconds and
0.84 seconds respectively. This is reachability evidence only; it does not by
itself establish that `self_turn` is stronger than `complete_round`.

The later four-opening extra-play profile with the depth-two reuse gate
completed depth two in 2/4 initial decisions. The two depth-one selected moves
did not actually grant an extra play. Clearly labelled legal-branch probes from
those exact openings then applied the first legal extra-play-granting move and
both fresh ten-second searches completed depth two. Those probes demonstrate
extra-state reachability only; they are not principal-action results.

## Current limitations

- Native transpositions intentionally do not cross independent AI decisions or
  substitute a different remaining-depth request; there is no persistent
  opening book or deeper-entry reuse.
- Android ARM64 correctness is build-covered, but device performance must still
  be measured independently rather than inferred from Windows Release.
- A future declaration outside the compiled vocabulary must fail atomically
  until the native kernel and independent tests support it.
