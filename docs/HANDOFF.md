# Wuxia Card Handoff

Updated: 2026-09-04

This is the first document a replacement developer or AI should read. It describes the repository as it exists now, not an aspirational design.

## Current Product

Wuxia Card is a portrait-first Godot/Summer Engine card-duel prototype. The playable scene is `res://main.tscn`, which opens a 3×3 duel. Players drag cards from fixed five-slot hands to the board. Directional power comparisons capture adjacent cards; catalog-driven abilities add draws, removal, movement activations, ki, triggers, and extra card plays.

The current opponent uses perfect information and a time-limited iterative-deepening search. Normal play conceals the opponent hand visually. A script-only testing mode reveals both hands and lets one person control both sides.

Completed duels can be replayed in memory from the exact initialized state and
successful action log. Playback reuses the simulator/VFX path with a two-second
turn cadence, preserves opponent concealment, and permits inspection between
actions without producing progression side effects.

The main flow routes the main menu, sect selection, deck builder, duel, reward
selection, and a completed-run ending. The deck-building scene persists a
five-card main deck and exposes a virtualized 1,000-slot collection library.

Not yet present: story/dialogue, final content balance, multiplayer, or a
release-ready Android package.

## Exact Starting Point

- Engine target: Godot `4.7`, GL Compatibility
- Known working Summer engine: `4.7.2.stable.mono.custom_build.a8e5ca520`
- Main scene: `res://main.tscn`
- Deck builder scene: `res://scenes/deck_builder.tscn`
- The Godot 4.7 `godot-cpp` generator copies `Dictionary` values during move
  assignment but does not first release the destination. The native build uses
  `native/duel_core/godot_cpp_binding_hooks.py` to add the missing destructor;
  do not remove this hook when changing engine or `godot-cpp` versions without
  first running the repeated-search memory regression.
- Ending scene: `res://scenes/ending.tscn`
- Logical viewport: `540×960`; portrait; `canvas_items` stretch
- Production rules facade: `scripts/duel_simulator.gd`; strict native boundary:
  `scripts/duel_native_rules.gd`; C++ kernel: `native/duel_core/`
- Card database: `scripts/card_catalog.gd`
- Persistent deck profile: `scripts/deck_profile_store.gd`
- Encounter hands and side-pool construction: `scripts/duel_decks.gd`
- Runtime/presentation bridge: `scripts/duel_controller.gd`
- In-memory replay snapshot/log: `scripts/duel_replay_record.gd`
- Deck-builder presentation: `scripts/deck_builder_controller.gd`
- Testing switch: `scripts/game_settings.gd`, `TESTING_MODE`
- Android preset: `export_presets.cfg`
- Windows Release preset: `export_presets.cfg`; one-command build:
  `tools/build_windows_release.ps1`

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
- After the first owner is chosen, `DuelOpeningSetup` normally selects one of
  the 12 orthogonally adjacent unordered cell pairs with exact `1/12`
  probability and places two fresh `BaGuaFangWei` instances for the later
  owner. Difficulty 3 reduces a later player's Bagua to one uniformly random
  cell; difficulty 6 removes it. A later enemy still receives the pair, with
  powers set to 2 from difficulty 4 and 4 from difficulty 7. They are static
  initial state: no summon events, standard attacks, action count, opening
  animation, or power-change animation. Replay snapshots the result instead of
  rerolling.
- Power arrays are `[top, right, bottom, left]`.
- A higher opposing power captures; ties do not.
- Player owner ID is `1`; opponent owner ID is `2`.
- A turn permits either playing one hand card or activating one board card.
- Any activation costs one ki.
- Ki survives ownership flips; abilities are lost unless the catalog ability explicitly declares `retained_on_flip = true`.
- `BaGuaFangWei` retains a locked `CARD_BEFORE_FLIPPED` trigger that exiles the
  exact pending target before ownership can change.
- `JinGangBuHuai1`–`4` use generic physical-leftmost discard and flip
  prevention. Tiers 2–4 then spend one ki and use `ACTION_ADD_CARD_TO_HAND`
  with `CARD_SPEC_FRESH_COPY` to gain a catalog-fresh copy; the discarded
  instance remains in discard unless its own trigger moves it. If that trigger
  refills the hand first, the ki remains spent and adding the copy has no
  effect. Their explicit protection emits global `CARD_FLIP_PREVENTED`; tier 4
  makes every protected friendly gain one point and attack once per tier-4
  source.
- `FuMoQuan3`–`4` reduce every allied moving card before each movement/swap
  leg; multiple sources stack and a four-zero result removes the mover before
  it can relocate. Empty-hand owner-turn endings grant all current allies one
  idempotent, non-retained after-summon counterattack. Tier 4's retained range
  also crosses exactly one intervening enemy, while an ally still blocks.
- `QianShouRuLai5` uses the global post-exile snapshot boundary. A board card
  whose pre-exile powers pass `Rules.can_change_powers()`—including four
  zeroes, excluding four `-1`s—makes each still-valid source try row-major to
  summon a complete runtime perfect copy in the old cell through the normal
  summon/attack pipeline. Its before-flip rule discards the physical-leftmost
  hand card to prevent flipping, then spends one ki to add a new-ID perfect
  runtime copy of that discarded snapshot.
- `BaoCanShouQue2`–`4` and `LiJingRuLai3`–`4` use physical-leftmost discard
  selection. Their point gains occur only after the required discard count.
  Locked prevented-flip reactions exile only the exact target attacked by that
  source. BaoCan's attacked reaction snapshots and exiles both participants;
  tier 4 checks its source owner's hand once after both complete exile chains,
  then attempts two fully resolved fresh-copy summons in former-cell order.
  The generic `ACTION_IF`, `CONDITION_SOURCE_OWNER_HAND_EMPTY`, and
  `CARD_REF_ATTACKER_CARD` declarations support these rules without card-ID
  branches.
- Discard actions now share one generic batch transaction. Exact hand
  instances are snapshotted first, all selected cards enter discard before any
  self-`CARD_AFTER_DISCARDED` chain, those chains resolve in physical hand
  order, and one global `discard_batch_finished` event follows. A batch emits
  one final hand-slot shift and its individual discard views fade together.
  Single-card discard uses the same path as a batch of one. `LiJingRuLai4`
  locks up to two physical-leftmost cards in one batch and gains three only
  when both were actually discarded.
- `YiKongDaoDi4`–`5` exile themselves at `card_summoned` timing, batch-discard
  the remaining allied hand, then draw five one card at a time; therefore they
  emit normal placement but skip after-summoned rules and standard attack.
  Tier 5 then discards the opponent's physical rightmost occupied hand slot.
  `RanMuDaoFa2`–`3` use a locked allied-hand activation to discard the exact
  target, batch-buff every legal allied board card, and grant one extra play;
  tier 3 repeats the board buff only after a real attack. `WuXiangJieZhi3`–`4`
  reuse the locked first-legal unlimited attack modifiers and have a locked
  discard/draw activation. Tier 4 attacks once after each successful discard
  batch owned by its current side; multiple sources resolve row-major.
- `NianhuaWeiXiao3`–`4` return a row-major snapshot of adjacent cards to each
  card's original owner. Tier 4 can react from its own discard entry and reuse
  the same instance in the first enemy-adjacent empty cell. `SanRuDiYu1`–`3`
  transform exact discarded instances through their stages and dynamically
  summon the current discard top once per declared action. Every such summon
  finishes its full entrance and attack chain before the next pile read. Their
  range-two modifiers are locked; their end-turn self-exile is not.
- Runtime ki beads are gold for any flip-prevention ability and light gray for
  semantic self-exile, in that priority order. `BaGuaFangWei` suppresses its
  bead absolutely. Discard presentation reuses the existing fade-out.
- Only cards with an activation count as ki-using for bead display.
- A card may declare multiple catalog activations in priority order. A dynamically
  received activation replaces all current activations while preserving passive
  abilities.
- Runtime card identity is `instance_id`, not a hand child index.
- Main deck means the five-card starting hand. Player main-deck glyphs must be
  unique; enemy decks may repeat glyphs and exact IDs.
- Both five-card starting hands are independently shuffled when a duel begins.
  A zero seed randomizes production; explicit seeds keep tests deterministic.
- The side deck is a separate shuffled draw pile derived independently for each
  owner. Non-`江湖` main cards set same-sect tier ceilings over the full catalog.
  The highest-tier card per glyph survives (catalog order breaks ties);
  `江湖` main cards contribute nothing.
- The player's five-card main deck is loaded from
  `user://wuxia_deck_profile.json`; malformed data is repaired or replaced by a
  valid default.
- The collection library has 1,000 logical entries arranged in four-card rows
  and only 20 live slot views. Library cards retain the standard 3:4 ratio and
  their name color reflects catalog tier.
  Occupied cards are a compact prefix followed by empty slots.
- A library card exchanges with a main-deck slot after a roughly 0.25-second
  hold and drag. When its glyph already exists in another main slot, the
  profile performs the approved three-way rotation without leaving a gap. A
  short tap inspects; immediate movement scrolls.
- Primary unlocks insert at the library top. Still-locked lower-tier cards with
  the same `glyph` and sect append at the library bottom.
- Crossing levels 2, 5, 8, or 11 unlocks all exact-tier cards of the selected
  sect before reward selection. Tier 5 remains the cap through level 15.
- Completed wins and losses increment schema-7 run history atomically. A run
  completes at 13 victories on difficulty 0, 14 on difficulty 1, and 15 on
  difficulties 2–9. Schema
  11 stores a sparse difficulty `0..9` score dictionary for each sect; earlier
  scalar sect scores migrate into difficulties 0, 1, and 2, with difficulties
  0 and 1 capped at 500. A final victory at the configurable threshold (15 by
  default) skips rewards, computes `floor(15000 / effective_duel_count)`, caps
  the actual ending score at 500 on difficulties 0 and 1, and raises the
  selected sect's record for the current difficulty and every lower one. It
  then closes the run and resets card unlocks, the main deck, the library, and
  run-only reward history to their fresh-profile values. Sect unlocks
  (including the final enemy's declared sect), mastery, and all per-difficulty
  best scores are retained.
- Schema 8 stores global mastery by exact card ID. A successful player hand
  play qualifies when that exact ID was in the main deck at duel start; a win
  commits the candidates, while defeat or abandon commits none. `闭关重修`
  preserves mastery and `封剑归隐` clears it.
- Schema 9 also tracks guaranteed reward cards already shown in the active run.
  A catalog-declared defeat guarantee may force a locked card into an eligible
  reward offer once per run; closing and restarting a run clears that history.
- Schema 10 adds global maximum difficulty, persistent last-selected
  difficulty, and active-run difficulty. New profiles start at difficulty 0;
  completing difficulty `n` unlocks `min(n + 1, 9)`. Completion and
  `闭关重修` clear only active-run difficulty, while `封剑归隐` resets all
  difficulty data. Legacy saves unlock and select difficulty 2, and preserved
  active runs migrate as difficulty 2. `DifficultyRules` is the central table
  for all cumulative effects and exact current-tier prompt text.
- Difficulty 5 changes the go-first gate from total tier `<=` to `<` the
  opponent. Difficulty 8 stores a one-use simulator latch: the first atomic
  enemy-hand change ending at one card draws one normally; batches expose only
  their final size. Difficulty 9 statically increases all four powers of one
  uniformly chosen legal enemy opening-hand card, excluding all-four-`-1`
  cards and emitting no animation.
- Sect selection uses `inkpics/arrow.png` on both sides of the parchment. The
  left copy is flipped, both wrap through the unlocked range, and each change
  saves immediately. They remain hidden when only difficulty 0 is unlocked.
- Revealed library and reward cards are blue when mastered and red otherwise.
  Revealed enemy cards stay red; unoccupied reward backs keep random colors.
- The ending instances the production main menu so it shares the exact
  background and animated title. It hides the menu actions, lists the selected
  sect and every defeated enemy, and branches for flawless/comeback prose. Its
  smaller score stays fixed beneath the title while the prose rolls upward in
  a clipped clear-sky viewport. Early taps do nothing; after the last line is
  fully visible, the first tap returns to the normal menu.
- `MainFlowController` owns one persistent presentation-only `MusicDirector`.
  Menu/sect share a continuing `menu1`–`menu3` pool; deck building and normal
  rewards share a continuing fixed, per-track weighted `village`/`story` pool;
  battles use `battle1`–`battle6`. A reward containing `KuiHua0` uses
  `terror`, claiming it consumes a one-entry `lose` override for the next deck
  screen, and completed runs use `bixie` only when normal-mode run unlocks
  included `KuiHua0` before progression reset. All other endings use `lonely`.
  Scene-driven replacements fade out the old track, and natural completion
  reselects from the current context.
- Hands are capped at five and always render five fixed physical slots. Runtime
  hand cards carry `hand_slot_index`; automatic "leftmost" selection follows
  physical slot order rather than compact hand-array order. New draws and
  returns fill the leftmost empty slot. Only discard closes its gap: every card
  physically to its right shifts left one slot in one simultaneous presentation
  batch. Normal play and hand exile/removal leave all other slots unchanged.
- Normal draws retain the existing concealment rules. Every other successful
  effect-driven hand addition is permanently public to the recipient's
  opponent, including created cards, copies, fresh board returns, and the same
  instance returning from discard. Newly public instances emit
  `card_revealed` immediately after their addition/return event.
- The AI sees both hands and exact deck order. Production uses the sole native
  iterative search with deterministic structural ordering and alpha-beta
  pruning; `self_turn` is its default depth mode while explicit
  `complete_round` remains available for legacy comparison. A fixed two-way
  native transposition table is scoped to each root decision and defaults to a
  strict 8 MiB on both desktop and Android. Its exact key includes the complete
  native-state checksum and remaining owner-turn boundaries; cached moves are
  revalidated before ordering or same-turn plan restoration. Historical GDScript
  PVS, tactics, evaluation-cache, and
  alternate-evaluator profiles were removed with the old search backend.
  Search stays card-agnostic and canonical root ordering resolves equal scores.
- Native search transitions retain rule-semantic event skeletons but omit
  complete runtime-card snapshots and capture/exile summaries that are used
  only by presentation. Live gameplay transitions still materialize the full
  payload. The same 14 two-second `self_turn` openings improved from `9987.37`
  to `10465.11` nodes/s (`+4.78%`) with identical deepest completed
  depth/score/actions and unchanged `13/14` depth-two completion.
- The 2026-09-04 four-opening Release transposition-table ablation improved
  ten-second `self_turn` depth-two completion from `2/4` to `4/4` at every
  tested 4/8/16/32 MiB capacity. The selected 8 MiB default preserved all
  complete depth-two scores and canonical actions; per-opening depth-two time
  improved by `1.25x`, `1.33x`, `20.16x`, and `25.09x`. The diagnostic run
  recorded 74,877 real hits from 424,028 probes, with no allocation fallback
  or illegal cached moves.
- The final production-selection ablation kept `self_turn` and the 8 MiB table
  fixed. Removing PV added `2.1%` complete-depth-two work across the four
  extra-play-cap openings and reduced one unfinished depth-three root from
  eight completed actions to four. Across 14 unique Quick openings, removing
  conservative history preserved all same-depth scores/actions and the same
  `12/14` depth-three completion count, but added `11.81%` completed-depth work
  and `7.99%` elapsed time. Production therefore enables self-turn depth, PV,
  conservative history, and the 8 MiB table together.
- Hand-target drag hit testing is owner-aware. Enemy-hand activations such as
  HanBin target only the opponent's physical hand, while allied-hand
  activations such as RanMu and WuXiang target only their current owner's hand;
  the logical slot index is never interpreted against the opposite container.
- Internal modifier checks use read-only views rather than deep-copying every
  modifier dictionary. The public copying API is unchanged. The 2026-08-29
  14-opening production profile reached `547.48` nodes/s versus `490.18`
  previously, with identical depth-one scores, actions, and opening digests;
  mean complete-round depth-one time fell from `0.629s` to `0.572s`.
- Runtime state copies isolate card dictionaries and every mutable card
  container, while sharing immutable normalized ability declarations. The
  2026-08-29 14-opening production profile reached `592.05` nodes/s versus
  `547.48` previously, with identical depth-one scores, actions, and opening
  digests; mean complete-round depth-one time fell from `0.572s` to `0.512s`,
  and complete-round depth two finished in `3/14` openings instead of `2/14`.
- Playing a hand card now moves the already isolated card inside the copied
  state, and trigger groups share immutable ability snapshots. An interleaved
  1,024-action comparison matched every resulting state and event while making
  transitions about `2.8%` faster. The 14-opening production profile showed a
  smaller `+0.92%` throughput change (`592.05` to `597.47` nodes/s), unchanged
  `3/14` depth-two completion, and identical depth-one decisions; treat this as
  a low-complexity cleanup with modest measured benefit.
- Search depth is measured in authoritative `owner_turn_serial` boundaries.
  Production-default `self_turn` consumes `2 × depth - 1`: depth one ends after
  the current owner turn, while depth two also completes the opponent turn and
  the root owner's next turn. Explicit legacy `complete_round` consumes
  `2 × depth` boundaries.
  Same-turn extra
  plays cost no boundary and are searched fully; simulator-resolved empty turns
  consume however many boundaries they actually cross. Only a fully completed
  round iteration is published. The completed principal line also carries the
  AI's remaining same-owner-turn actions. The controller retains them only
  from depth-two-or-deeper non-fallback results and still requires exact state
  key, owner, serial, and legality; shallower or invalid plans make an extra
  play search normally. Every AI hand play or activation has a two-second
  minimum decision window with search time included.
- Node-limited Quick, Pilot, and Extended benchmarks set
  `min_completed_depth = 1`. Their nominal node limit is ignored only until a
  complete depth one exists; total nodes never reset, while cancellation and
  deadlines remain hard. Search and benchmark reports expose guard use and
  node overruns. Production keeps its hard ten-second deadline without this
  benchmark-only guard.
- Extended runs all 112 real enemy-catalog crossover games at the fixed soft
  1,500-node tier. Every completed game is immediately printed and appended to
  a timestamped `.progress.jsonl` checkpoint; the PowerShell wrapper streams
  those lines live. The final JSON shares the same artifact stem and references
  the checkpoint. A partial checkpoint survives interruption but is not a final
  benchmark result, so a separate Pilot is no longer required before Extended.
- Historical GDScript PVS/tactics/evaluator ablations were retired with the
  former search backend. Quick, Extended, and Production now run the same
  native search for every seat; old `enhanced`/`baseline` report fields are
  balanced assignment labels, not different algorithms.
- Production native ordering now defaults to internal previous-completed-depth
  PV hints, a per-root 8 MiB transposition table, and conservative history,
  with final priority `PV > transposition move > structural > history >
  canonical`. Strict history priority was rejected
  because it reduced real-opening depth-two completion. Timing/cutoff counters
  remain behind the default-off `collect_search_diagnostics` switch. The
  2026-09-03 four-opening `self_turn` evaluation reached `11666.0` nodes/s
  versus the phase baseline's `10130.05` (`+15.2%`), retained 2/4 completed
  depth-two openings, and reduced the two incomplete linear estimates to
  `15.20s` and `10.60s`. Use `Release + template_debug` native builds for
  performance comparisons; `Debug + template_debug` is about half-speed.
- Native transposition opportunity diagnostics are available through
  `CollectTranspositionDiagnostics` on the opening profile. The 2026-09-04 four
  extra-play-cap openings produced 333,262 previously completed exact-key hits
  from 460,706 probes (`72.34%`): leaf reuse was `73.74%`, and internal-node
  reuse was `60.88%`. State-only matching was `72.47%`, so almost all observed
  reuse already matched remaining depth. The implemented fixed table's
  diagnostic run recorded a lower real hit rate of `17.66%`, but those hits
  produced 50,425 exact returns and 24,188 bound cutoffs.
- Testing mode is fixed when the duel is created and cannot be toggled in-game.
- After victory or defeat, the black replay icon left of the board reconstructs
  the exact opening state and replays all successful actions. During a live
  duel or between replay actions, it instead opens the ordinary catalog-based
  inspector for owner 2's latest successful hand play, reusing
  `last_hand_play_by_owner`; missing history or an action currently being
  presented leaves it inert. The first replay action is immediate and later
  actions wait two seconds; inspection pauses that wait. Exit cancels the
  replay and returns using the original result. Replay and inspection do not
  run AI or alter revelation, mastery, enemy memory, profiles, rewards, or
  progression.
- ZiXiaGong1–4 use the generic `for_each_selected_card` action. The selector
  supports ordered hand/board snapshots, reusable selected-card conditions,
  optional limits, and source-versus-subject execution context.
- CangSongYingKe3–4 use `CARD_BEFORE_FLIPPED` plus the generic
  `add_card_to_hand` action to spend one ki and create a fresh exact copy for
  the pre-flip owner. Full hands still consume the ki.
- SanQinFeng1–3 use the same selector wrapper to make the first 1/2/3 allied
  board sword cards attack sequentially. Each attack resolves completely
  before the next snapshot member is revalidated.
- Attack flips recheck exact attacker/target range after `CARD_BE_ATTACKED`.
  Once `CARD_BEFORE_FLIPPED` starts, movement alone no longer cancels the
  committed flip; the target instance is followed to its current cell.
- Runtime ki and all four powers can change permanently in hand or on board.
  `ACTION_CHANGE_POWERS` accepts explicit exact-card references plus signed
  literals or a current-owner hand count. Subtraction floors each side at zero;
  four zeros move the card to its original owner's removed zone.
  Each owner can gain at most one extra card play per actual owner turn;
  later requests in that turn do nothing. The grant permits hand plays only
  and does not repeat start-owner-turn or end-owner-turn triggers; those
  boundaries run once per owner turn, and temporary turn-scoped effects restore
  only when it closes.
  The per-turn grant latch is part of compact state and search identity, then
  resets only when the authoritative owner-turn boundary completes.
- WanYueChaoZong1–4 now gain current-hand-count power after their own summon
  and decay at owner-turn start. Tiers 2–4 also strengthen adjacent allied
  summons by `+1/+1/+2`. DaSongYangZhang1–4 strengthen adjacent allied summons
  by `+1/+1/+1/+2`; tiers 2–4 weaken adjacent enemy summons by `-1/-2/-2`.
- YinYangZhang3–4 now hide their four `-1` powers, can be attacked by any
  nonnegative facing power, and cannot be selected by power-changing effects.
  After summoning they exile themselves, draw the first two palm cards from the
  side deck without disturbing skipped non-palms, then grant both the existing
  and newly drawn allied hand palms a nonrecursive repeat attack plus a
  distance-two orthogonal attack. Tier 3 passes only one empty cell; tier 4
  also passes one allied card. All grants are exact-instance, idempotent, and
  non-retained on flip.
- TaiJiSanHuan4/5 and TaiJiDaKui5 redirect an adjacent enemy's summon standard
  attack only while adjacency is preserved. After any enemy really attacks one
  of its own allies, every qualifying Taiji source removes its shared redirect
  ability, including friendly fire caused by YiZi or another effect. Failed or
  zero-target attacks do not consume it.
- HanBinZhenQi3–4 now target an exact enemy hand instance, weaken it, and
  reveal it to the activating owner. An actively chosen YinYang card remains a
  legal target but ignores the power loss. Tier 4 flips immediately when its
  last ki is spent, then finishes resolving the locked target. After flipping,
  HanBin gains a non-retained owner-turn-start decay that weakens itself and
  the leftmost two legal allied hand cards in one presentation batch; automatic
  selection skips YinYang.
- Flip cleanup is staged globally: ownership changes first, ordinary old
  non-retained abilities are lost, isolated old self-`CARD_AFTER_FLIPPED`
  entries resolve, and those isolated old entries are then lost. Abilities
  granted during that event survive. Catalog validation forbids combining a
  self-after-flip trigger with another trigger, activation, or modifier in the
  same ability entry.
- TianWaiYuLong2–3 react to an adjacent allied summon by swapping with that
  exact trigger card and attacking from the new cell. Tier 3 first attempts to
  add one power to the trigger card; YinYang ignores only that change. Multiple
  TianWai sources resolve row-major and revalidate after prior swaps.
- DuGu9Jian1–3 now implement their complete before-summon rules. No Form
  exiles itself, then its snapshotted orthogonal neighbors row-major, drawing
  immediately for each removed card's pre-removal current owner. Anticipate
  returns each player's exact previous successful hand play as a fresh catalog
  instance to its original player, then grants an extra hand play. Break All
  queues persistent suppression layers without revealing the opponent hand; each
  later non-heart hand play consumes one layer before its own before-summon
  discovery and permanently loses only non-retained abilities.
- KuiHua1–4 share the card-level `self_castration` effect gate. Enemy effects
  are always enabled; player effects are enabled from the profile only when
  KuiHua0 is unlocked, and new profiles currently unlock KuiHua0–4. KuiHua1
  grants one extra hand play at owner-turn end. KuiHua2 returns when a real
  attack starts against it, attacks against the defender's minimum side, and
  after a real attack makes enemy standard attacks target both sides; attacked
  old allies flip to the modifier source's current owner. KuiHua3 swaps with
  its sole adjacent enemy after summon and re-enters as a fresh full summon
  only after its completed attack flipped an enemy. KuiHua4 draws, exiles every
  current ally originally owned by the enemy to that original owner's removed
  zone, and creates fully entering fresh copies in their former cells.
- `TRIGGER_CARD_AFTER_ATTACK` now fires only when at least one target passed the
  initial attack legality/power check and emitted `attack_started`. If a later
  reaction moves or removes the target, the completed attack still receives
  its after-attack event; a zero-target or insufficient-power attempt does not.
- One top-level power action emits one transition-only batch. Every visible
  target in that batch keeps its previous powers for one shared roughly
  0.12-second pause, then all update and animate simultaneously for about
  0.25 seconds. Repeated exact-instance changes visually coalesce, zero-power
  removals wait behind both shared barriers, and concealed hand changes add no
  animation delay or leak.
- LaiHeQinQuan1–5 now use generic exact-instance revelation, permanent
  future-draw audiences, flip-prevention requests, granted passive modifiers,
  and indexed self-removal. LaiHe4/5 use the active-run enemy-memory snapshot;
  testing-mode visibility is not gameplay revelation.
- A card carrying `defending_power_override` keeps its stored/displayed powers,
  but attackability treats its facing edge as the modifier value. CardView fades
  only its central picture to 70% while that weakness is active.
- JinZhenDuJie2–4 use a row-major board selector plus generic
  `ACTION_RETURN_CARD_TO_HAND` to return the first enemy that originally
  belonged to the source owner as a fresh catalog hand instance; a full hand
  exiles it instead. Tiers 3–4 also carry the existing one-use complete-attack
  counter.
- WanHuaJian1–3 resolve a retained pre-terminal nonwinner self-exile. Tiers 2–3
  use generic `ACTION_SUMMON_CARD` to create a fresh exact-ID copy in the
  lowest-index adjacent empty cell when attacked; the copy completes summon
  triggers and a standard attack before the original attack resumes. Tier 2
  retains this copy trigger on flip, tier 3 does not. Self-removal and returns
  fade; external exile keeps its ink effect.
- MianLiCangZhen3 resummons an enemy it personally flipped when that exact card
  originally belonged to its current owner. The old instance leaves without
  exile, then a fresh catalog instance enters its current cell, resolves both
  summon phases, and performs a standard attack. Its old view fades before the
  existing ink-summon presentation. The card is intentionally not default-locked.
- YunWu13Shi2–3 use the exact-card `TRIGGER_CARD_BEFORE_SUMMONED` phase to
  suppress every enemy's current non-retained abilities until turn end. Tier 3
  then uses the ordinary adjacent exact-instance swap after summoning.
- YiJianLuo9Yan2–3 select the sole exact enemy directly flipped by the completed
  attack and swap only while it remains adjacent. Tier 3 attacks from its new
  square; failed selection or swap stops that follow-up.
- TianZhuYunQi2–4 react to an adjacent enemy summon by moving to the
  lowest-index adjacent empty cell. Tiers 3–4 draw only after a successful
  move. Tier 4 also suppresses adjacent enemies during `CARD_BEFORE_MOVED`,
  regardless of what effect initiated either movement or swap leg.
- JianFaQinYin1–3 move after summoning into the lowest row-major empty cell
  lying exactly between themselves and an enemy on the same row or column.
  Tiers 2–3 can spend one ki to move to an adjacent empty cell and gain one
  extra hand-card play. Tier 3 reacts on `CARD_AFTER_MOVED`, suppressing all
  adjacent enemies' non-retained abilities through the full owner turn.
- YanHuiZhuRong3–4 replace their pending flip when the current hand contains a
  light sword: the source returns first (or is removed if the hand is full),
  then the exact leftmost matching hand instance is summoned into its original
  cell. Tier 4 can instead target another ally, return it, and summon a fresh
  source copy into that ally's original cell.

See `docs/DECISIONS.md` for ability-specific behavior.

## Immediate Cautions

- `TRIGGER_CARD_AFTER_SUMMONED` scans the full board and resolves matching
  sources in row-major order. `CangSongYingKe2` uses this window, so its order
  relative to the summoned card's own entrance ability depends on their board
  cells; both precede the standard attack. If `CARD_SUMMONED` moves or swaps the
  entering card, discovery finishes first, then the exact entering `instance_id`
  is relocated and `CARD_AFTER_SUMMONED` uses its current cell and owner. There
  is still no general queued
  player-choice/interrupt engine.
- `CARD_BEFORE_FLIPPED` is a committed-flip boundary, not a second attack-range
  check. Future rules that need to cancel a committed flip must do so through a
  non-movement invalidator with explicitly defined semantics.
- `deck_builder.tscn` emits `back_requested` only. Do not add navigation inside
  its controller; connect it from the future scene router.
- Pre-schema-7 active runs cannot reconstruct effective-duel/enemy history.
  Migration deliberately closes those runs and restores the default deck while
  preserving unlocks; do not silently invent completion history.
- Deck-builder tests use isolated `user://` paths. Do not point tests at the
  production profile or a developer's saved deck will make them nondeterministic.
- Nonterminal owners with no legal action still resolve start/end owner-turn
  triggers; only their action phase is skipped. Five occurrences of the same
  nine-cell catalog-ID/current-owner signature end the duel by score at the
  end-to-start boundary. The action-count fallback is `max_turns = 100`.
- The search supports two native depth horizons without duplicating the search
  engine. Production defaults to `self_turn` and consumes `2 × depth - 1`
  owner-turn boundaries; explicit legacy `complete_round` consumes `2 × depth`.
  The 2026-09-02
  14-opening, ten-second `self_turn` profile completed depth two in 14/14 and
  depth three in 9/14; the two Dongfang Bubai/Zhang Sanfeng seats completed
  depth two in 9.46 seconds and 0.84 seconds. This measures reachability, not
  comparative playing strength.
- A focused four-opening `self_turn` profile after imposing the per-owner-turn
  extra-play cap completed depth two for Dongfang Bubai mirror (`8.67s`) and
  Dongfang-first versus Feng Qingyang (`6.83s`). Feng-first versus Dongfang
  completed `14/35` depth-two roots with a `24.94s` linear estimate; Feng mirror
  completed `22/35` with a `15.88s` estimate. The report is
  `production-opening-depth-extra-play-cap-1788338601.json` under the local,
  uncommitted benchmark directory.
- After adding the depth-two continuation-reuse gate, the paired four-opening
  profile again completed depth two in 2/4. Only Dongfang-first versus Feng
  immediately entered an extra play, and its depth-two plan was reused. The
  two depth-one selected actions did not grant an extra play, so they remained
  correctly inapplicable to a real second-search measurement. A separately
  labelled legal-branch probe played each position's first action that really
  grants an extra play; both fresh ten-second searches completed depth two and
  began depth three, at 91,941 and 120,635 nodes. The formal report is
  `production-opening-depth-extra-play-cap-1788350396.json` under the local,
  uncommitted benchmark directory; the legal-branch probe is reachability
  evidence, not an assertion that the AI selected those first actions.
- The search still duplicates Dictionary-based states. `DuelStateKey.build_compact()`
  now uses the complete explicit state payload, Godot native Variant binary
  encoding, and a SHA-256/128 `v2` fingerprint; it is faster but is not a compact
  simulation representation. The 2026-08-29 14-opening production comparison
  improved aggregate throughput from `246.09` to `411.09` nodes/s with unchanged
  depth-one scores/actions and zero fallback. A subsequent Boolean
  legal-action-existence query for terminal and empty-turn checks raised the
  same profile again to `490.18` nodes/s (`+19.24%`) while matching full action
  generation on 1,024 real-state/owner checks. `completed_depth` and benchmark
  depth settings mean the report's declared depth mode, not action plies. Use
  `tools/run_ai_benchmark.ps1` for paired Quick/Extended/Production strength
  evidence rather than judging strength from one game. Node-limited reports must
  include minimum-depth guard and overrun diagnostics instead of describing
  1,500 as a hard cap.
- `DuelNativeCompactKernel` is the sole production rules and deep-search
  backend behind `DuelSimulator`/`DuelSearch`. The kernel compiles immutable ability declarations once per
  compact root and tracks ordered branch-local runtime ability entries with
  stable trigger handles. It implements the generic summon/attack/flip/exile
  lifecycle plus recursive nested actions, all-zone selectors, batched power
  changes/four-zero exile, ki-change dispatch, non-attack flips, dynamic
  passive/activation grants, catalog-fresh board returns, and ordered adjacent
  swaps. It also implements list-local `if` context, single/batch discard,
  discard-only self-trigger discovery, row-major batch-finished listeners,
  transitive transform prototypes, in-place transform, and same-instance
  discard return. It now also covers before-summoned/full-board summoned and
  after-summoned discovery, generated summons from all supported zones and copy
  modes, fresh in-place re-summons, one-at-a-time draw with empty-deck fallback,
  future revelation/after-draw/difficulty-eight handling, and complete
  end/start/empty-turn/full-board terminal boundaries. Fresh board returns append a new compact card index from an
  immutable root prototype and leave the destroyed old index as an unreferenced tombstone;
  preserved discard returns instead move the existing index and reveal it only
  when newly public. Both return modes reuse the normal full-hand exile
  lifecycle. Swaps resolve two
  complete global before/moved/after movement legs and revalidate exact
  instances between them. Its generic attack module compiles all catalog
  attack modifiers, including distance/intervening rules, comparison reversal,
  summon redirection, unlimited/non-orthogonal first-target locking, and both
  indiscriminate target policies. Four-sided `-1` semantics override comparison
  reversal, and locked attacks compare powers only during initial selection.
  It also exposes direct event/attack/non-attack-flip adapters for focused
  semantic tests; these reuse production primitives. Before retirement, the
  migration corpus sealed all 490 real-Quick root hand plays, all 20 catalog
  activation declarations, and 104 activation actions from 136 derived states.
  The final seal passed 4,812 checks across 56 deterministic walks and 584
  actions; commit `e68885d` is the recoverable pre-removal endpoint. Current
  authority comes from native catalog audits, focused rule/card fixtures,
  complete-runtime actions, search contracts, and controller integration.
  Production adds
  structural ordering, alpha-beta, iterative deepening, hard deadline/node
  checks, low-frequency cancellation, completed-depth result restoration, and
  same-turn principal plans. On the 14 real Quick openings at ten seconds it
  completes round depth two in 12/14, versus 3/14 for the last optimized
  all-GDScript baseline and 0/14 for the temporary per-edge native facade.
  Native transpositions and release/Android packaging remain unfinished;
  Android/release are distribution gates rather than desktop production gates.
  See `docs/AI_SEARCH.md` before extending it. Do not restore a second rules or
  search engine as a fallback.
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
