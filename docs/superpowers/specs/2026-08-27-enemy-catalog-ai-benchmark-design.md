# Enemy-Catalog AI Benchmark Design

Date: 2026-08-27

## Purpose

Replace the current hand-authored AI strength sample with deterministic matches
between real enemy-catalog decks. The existing synthetic fixtures remain useful
for search correctness and boundary coverage, but their narrow eight-card pool
must no longer be treated as evidence that the enhanced AI is stronger across
the actual game content.

This change affects benchmark construction and shared duel initialization. It
does not change either AI's information model: both baseline and enhanced search
continue to read both complete hands and exact deck order.

## Benchmark Roster

The roster contains 34 decks:

- all 32 enemies currently returned by `EnemyCatalog.get_all_enemy_ids()`;
- benchmark-only 东方不败, with
  `KuiHua1, KuiHua4, KuiHua3, KuiHua2, KuiHua2`;
- benchmark-only 张三丰, with
  `TaiJiLuanHuan5, TaiJiYinYang5, TaiJiSanHuan5, TaiJiDaKui5, DuGu9Jian1`.

The two benchmark-only rows move out of comments into a separate dormant-data
collection owned by `EnemyCatalog`. They are exposed only through a dedicated
benchmark-roster API. They are not returned by normal enemy-ID, level-selection,
or random-selection APIs and therefore cannot appear in an ordinary run.

Catalog validation covers active and benchmark-only rows. Every row must have a
unique ID, a non-empty name, a level from 1 through 15, exactly five known card
IDs, and a Boolean self-castration declaration when that field is present.

## Matchup Manifest

Decks are grouped by enemy level. Every unordered same-level pair is included.
This produces 25 matchups. Level 14 contains only 风清扬, so 风清扬 also fights
each of the three level-15 decks: 东方不败, 张三丰, and 无名老僧. The complete
manifest therefore contains exactly 28 matchups.

Manifest order is deterministic: level first, then enemy-catalog order within
the level, followed by the three level-14/15 bridge matches in level-15 roster
order. Validation asserts the exact count and rejects duplicate unordered pairs.

Each matchup between deck A and deck B contains four games:

| Game | Owner 1 / first | Owner 2 / second | Enhanced profile |
|---|---|---|---|
| 1 | A | B | A |
| 2 | A | B | B |
| 3 | B | A | B |
| 4 | B | A | A |

Across these four games, each search profile uses each deck once as first player
and once as second player. Deck strength, owner identity, and first-player
advantage therefore cannot by themselves create a profile advantage.

## Shared Production Opening Factory

A new pure-data `DuelInitialStateFactory` becomes the single source for initial
duel state construction. `DuelController` and the enemy-deck benchmark both call
it. The factory contains no Nodes, Controls, audio players, tweens, or live UI
references.

Its input includes both five-card main decks, owner 1, difficulty, independent
hand/deck/opening seeds, effect gates, remembered glyphs, and deterministic
instance-ID prefixes. Its output is a complete `DuelState`.

The factory performs the current production setup in this order:

1. create fresh main-hand instances;
2. independently shuffle both five-card hands;
3. derive each side deck through `DeckRules` and create fresh instances;
4. shuffle both side decks;
5. apply the existing difficulty opening-hand adjustment;
6. build the opening board through `DuelOpeningSetup`;
7. construct `DuelState` with turn zero and the chosen first owner;
8. set effect gates and remembered glyphs.

The controller continues to perform mastery capture and presentation setup
around the returned state. Simulation, replay, animation, and action commitment
remain unchanged.

Benchmark games use difficulty 0. The second owner begins with two static Bagua
cards under the existing rules. No Bagua summon event or attack is emitted.
Each deck uses its own enemy definition's self-castration setting; therefore
少镖头·林平之 remains disabled, while other decks and both benchmark-only decks
default to enabled. Each owner remembers the opposing five-card opening deck so
memory-dependent card effects behave symmetrically. Player saves, unlocks,
sects, rewards, and progression are never read or written.

## Deterministic Seeds and Identity

The benchmark declares a fixture version and master seed. A small stable integer
hash owned by the benchmark derives hand, side-deck, opening-layout, and
difficulty-effect seeds from the fixture version, matchup IDs, and deck ID. It
must not rely on unordered Dictionary traversal.

A deck keeps the same main-hand and side-deck permutation when the search
profiles are swapped. When A and B swap owners, each deck still keeps its own
permutation. Opening Bagua cells remain the same for the two games with the same
deck assignment. Runtime instance IDs include matchup, game assignment, owner,
zone, and ordinal, and must be globally unique within a state.

## Benchmark Modes

The old synthetic fixtures remain in a legacy fixture module. The daily full
suite validates fixture schema, deterministic rebuilding, mutable-state
isolation, search exactness, and one tiny runner smoke case. It does not run the
old eight-game Quick match and does not run enemy-deck strength matches.

### Quick

Quick uses 1,500 nodes per decision and these seven four-game matchups, for 28
games total:

- level 1: 少镖头·林平之 vs 江湖武师;
- level 3: 泰山弟子 vs 衡山弟子;
- level 5: 少林弟子 vs 武当弟子;
- level 8: 定闲 vs 天门道人;
- level 10: 君子剑·岳不群 vs 空见;
- level 12: 冲虚 vs 方证;
- level 15: 东方不败 vs 张三丰.

### Pilot

Pilot measures three matchups: level-2 小师妹·岳灵珊 vs 仪琳, level-5
少林弟子 vs 武当弟子, and level-15 东方不败 vs 张三丰. It first runs 10,000
nodes per decision and projects the full 112-game Extended wall time by measured
game time. If the projection exceeds 30 minutes, it repeats at 5,000, then
3,000, then 1,500 nodes. The highest tier projected not to exceed 30 minutes is
written as a fixed Extended constant and documented with the measured pilot
result. Runtime benchmark selection never changes automatically across hosts.

### Extended

Extended runs all 28 matchups and all four crossover games, for 112 games. It
uses the fixed node tier selected by Pilot. Extended is the primary strength
acceptance run.

### Production

Production uses the real ten-second decision deadline and four four-game
matchups, for 16 games total:

- level 2: 小师妹·岳灵珊 vs 仪琳;
- level 5: 少林弟子 vs 武当弟子;
- level 10: 君子剑·岳不群 vs 空见;
- level 15: 东方不败 vs 张三丰.

Production targets no more than 15 minutes on the current development host. It
reports real waiting time, depth, throughput, and fallback behavior. Its small
sample does not independently pass or fail the strength claim.

## Scoring and Acceptance

A win earns the controlling profile one match point and a draw earns one half.
Reports include overall score and breakdowns by level, matchup, deck, deck
assignment, and first/second owner.

Extended Final passes only when all of the following hold:

- enhanced match points are at least 55 percent;
- enhanced initial-decision completed depth is no lower than baseline in at
  least 75 percent of comparable samples;
- enhanced fallback rate is no greater than baseline fallback rate;
- every scheduled game reaches the game's own terminal state;
- no illegal action, invalid transition, missing crossover game, or duplicate
  instance occurs.

The runner has a 256-successful-action watchdog per game. Reaching it is an
incomplete game and fails Extended; it does not invent a score or winner.

## Reports

Every explicit benchmark writes ignored JSON under
`.summer/local/ai-benchmarks/`. The report contains:

- fixture and roster versions plus the ordered 34-deck roster;
- the complete matchup manifest;
- enemy IDs, names, levels, five-card decks, deck assignments, first owner, and
  all deterministic seeds for every game;
- every decision's profile, action key, completed depth, ordinary and tactical
  node counts, generated actions, applied transitions, elapsed time, cutoffs,
  transposition/PVS/cache statistics, completion reason, and fallback use;
- terminal result, score difference, successful-action count, and failure
  reason;
- aggregate match points, fallback rates, depth non-regression, throughput,
  card-ID coverage, and all requested breakdowns.

Console output prints one compact progress line per matchup and one final
summary. It does not dump every transition.

## Tests and Failure Handling

Automated coverage verifies:

- active enemies remain 32 and normal selection excludes both benchmark-only
  enemies;
- the benchmark roster contains exactly 34 valid unique definitions;
- the deterministic manifest contains 28 unique pairs and 112 crossover games;
- for each search profile, deck A and deck B each appear exactly once as owner
  1/first and exactly once as owner 2/second within a matchup;
- repeated factories with the same inputs have equal canonical state keys and
  no mutable aliases;
- a representative `DuelController` opening and direct factory opening have
  identical canonical state keys;
- changed seeds alter the intended hand, side-deck, or Bagua ordering;
- self-castration gates and reciprocal memories follow enemy definitions;
- benchmark-only enemies cannot enter ordinary progression;
- JSON summaries and all aggregate denominators are deterministic;
- the daily legacy smoke path remains lightweight.

Roster errors, unknown cards, duplicate IDs, invalid transitions, illegal AI
actions, missing scheduled games, write failures, and watchdog exhaustion make
the command exit nonzero. The runner preserves the partial JSON report with an
explicit failure reason whenever it can do so safely.

## Documentation

`docs/AI_SEARCH.md`, `docs/TESTING.md`, `docs/HANDOFF.md`, and
`docs/KNOWN_ISSUES.md` will describe the enemy-catalog benchmark, the two
benchmark-only enemies, the calibrated node tier, runtime expectations, and the
fact that the daily suite does not execute formal strength matches.
