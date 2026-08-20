# Durable Product and Rules Decisions

These decisions were explicitly established during development and should not be silently changed.

## Match and Layout

- The game is portrait-first and intended for mobile.
- Board cells use row-major order, left-to-right then top-to-bottom.
- Card powers are top, right, bottom, left.
- The center board is visually separated from two five-slot hands. Empty slots remain; cards do not grow or repack as hand size falls.
- Mouse and touch should produce equivalent gameplay behavior.
- Opponent name is shown at top-left and exit at top-right.

## Information and Testing

- Normal mode hides the opponent's hand with card backs.
- Future abilities may reveal hidden cards, so concealment is presentation state, not deletion of card data.
- The AI is allowed perfect information, including both hands and shuffled deck order.
- Testing mode lets the player manually control both sides and reveals both hands.
- Testing mode is a script setting, not an in-game toggle.

## Completed-Duel Replay

- Replay is available only after a duel reaches victory or defeat. Pressing it
  during a live duel or during playback has no gameplay effect.
- The first recorded turn starts immediately; later turns begin after a
  configurable delay that is 2 seconds in production.
- Replay reuses the authoritative simulator and normal VFX path. It is an
  in-memory presentation and never changes progression, rewards, mastery, or
  remembered enemy cards.
- Normal mode keeps the opponent hand concealed during replay. Revealed cards
  may be inspected between actions; inspection pauses the remaining delay.
- Real card play and activation are disabled during replay. The return icon
  remains active, cancels playback, and reports the original duel outcome.
- Playback stops on the recorded final board and may be started repeatedly.

## Turn and Activation Rules

- On a turn, choose exactly one: play a hand card or activate a card already on the board.
- If the next owner has no legal action in a nonterminal position, only that
  owner's action phase is skipped. Their start- and end-owner-turn triggers
  still resolve, and the empty turn does not increment the action counter.
- After every completed owner-turn boundary, record the nine board cells by
  catalog card ID and current owner only. The fifth occurrence of the same
  signature anywhere in that duel ends it by the ordinary board score before
  the next owner-turn start.
- Every activate ability costs one ki.
- A card may have multiple innate catalog activations in listed priority order.
  Receiving a new activation replaces every current activation-bearing ability
  without deleting unrelated passive abilities.
- Ki is independent from abilities and survives ownership flips.
- A zero-ki card with no activate ability does not show a ki bead.
- `card_uses_ki()` intentionally counts activations only. Passive Meng Huo abilities do not make a zero-ki bead appear.

## Ownership and Ability Retention

- A successful flip means ownership actually changes.
- Abilities default to lost on flip. Catalog authors do not need to declare the common default.
- Only an ability with `retained_on_flip = true` survives.
- Once an ability is lost, later ownership changes do not restore it.
- Ki remains on the card when abilities are lost.

## Rule Resolution

- Abilities have no behavior ID; runtime actions identify their source card by `instance_id`.
- Global triggers resolve by row-major board cell, then ability order, then trigger order.
- Every accepted passive trigger emits `ability_triggered` before its actions.
  The controller pulses that source card unless it was the last card pulsed in
  the same move. Pulse memory resets between moves.
- Every initially valid attack emits `attack_started` before
  `CARD_BE_ATTACKED`. This presentation-only cue remains even when a later rule
  exiles or otherwise prevents the target from flipping.
- Activate abilities do not pulse.
- Missing, moved, or replaced context defaults to `NO_EFFECT`, and later actions in that rule continue.
- Only an action explicitly declaring `on_invalid_context = STOP_RULE` stops that rule's remaining actions.
- Stopping one rule never cancels later trigger groups, the enclosing event, or the turn.
- Generic card selection snapshots matching instances in declared zone order.
  Every nested action finishes for one selected card before the next begins.
- A selected card is skipped only when one or more declared selector conditions
  no longer match. Moving between cells or zones does not invalidate it by
  itself.
- The original ability source remains distinct from the selected action
  subject.
- Owner-turn start triggers resolve after active-owner selection and before
  that owner can act. Granted extra card plays remain inside the same owner
  turn and do not repeat start- or end-owner-turn triggers.

## Signed Power Changes

- `ACTION_CHANGE_POWERS` is the only generic stored-power mutation action. It
  requires an explicit exact-card reference and either a nonzero signed integer
  or the validated `VALUE_CARD_COUNT` hand-count value.
- Positive changes have no ceiling. Negative changes floor top, right, bottom,
  and left independently at zero.
- A card reduced to four zeros is removed immediately from its current hand or
  board location and appended to its `original_owner` removed zone. The logical
  order is `powers_changed` then `card_exiled`; only an exact source-target
  identity match uses self-fade presentation.
- One top-level action creates one transition-only power batch. Logical events
  are never discarded, while presentation coalesces repeated exact-instance
  changes. All visible cards hold their previous powers for one shared roughly
  0.12-second pause, then update and animate together for roughly 0.25 seconds.
  Full-zero removals wait for both shared barriers. Hidden cards update without
  animation or delay.

## 万岳朝宗 / 大嵩阳神掌

- Every WanYue tier gains one per current-owner hand card after its own summon,
  after it has left the hand and after global summon reactions. It loses one at
  the start of each owner turn; granted extra card plays do not repeat decay.
- WanYue tiers 2–3 grant an adjacent allied summon `+1`; tier 4 grants `+2`.
- DaSongYang tiers 1–4 grant adjacent allied summons `+1`, `+1`, `+1`, and
  `+2`. Tiers 2–4 reduce adjacent enemy summons by `-1`, `-2`, and `-2`.
- Movement and swaps are not summons. If global reactions remove the summoned
  exact instance, its after-summon rules and standard attack do not run.

## Attack Presentation

- Every attack uses one serialized reveal of `res://inkpics/attack.png` before
  its pre-attack rules resolve.
- The supplied bitmap is not redrawn, recolored, or supplemented with generated
  flecks. It uses a fixed 64 × 22 keep-aspect display box.
- The image's local left side is the attacker side. Reveal always grows
  local-left-to-right, then the whole visual rotates to face right, left, down,
  or up.
- The visual is centered on the first neighboring cell seam beside the
  attacker. A farther orthogonal target does not stretch the image, and the
  neighboring cell may be empty or different from the target.
- Diagonal attacks require their future mechanic to define a first neighboring
  step before using this presentation.
- The cue adds no sound, haptic, bright color, or gameplay state.
- It replaces the former silent pre-flip wait; capture audio and the flip
  animation remain.

## Implemented Abilities

### Gate General and Tiger General

When either would flip a card through any present or future attack/combo source, it removes that card instead.

- This pre-attack trigger survives ownership flips.
- The removed card goes to its original owner's removed zone.
- The removed card keeps its original ownership identity.
- Removal is not a successful flip and does not generate Meng Huo ki.

### Fa Zheng and Strategist

When played, draw the catalog-declared number of cards (`2` currently).

- Draw from the side deck, not the starting/main hand.
- Never exceed five total cards in hand; reduce the draw count as needed.
- Stop if the side deck is empty.
- Cards are drawn/presented sequentially with an Ink Summon visual.
- There is a small post-draw delay so later board effects do not visually clash.
- The dedicated draw sound was deliberately removed because it was noisy.
- Like most abilities, the draw rule is lost on ownership flip; no catalog flag is needed for that default.

### Jiang Wei and Sun Zan

They start with one ki and have a movement activate ability.

- Drag the owned board card to an orthogonally adjacent empty cell.
- Pay one ki.
- Resolve a standard attack from the destination.
- Moving does not emit summon events.

The action/target model should also support future non-movement activations with ally-square, enemy-square, or hand-slot targets.

### Meng Huo

- Whenever Meng Huo is the source of an attack that actually flips a card, that Meng Huo gains one ki.
- Exiling/removing a target does not count.
- At the end of its owner's turn, an eligible Meng Huo spends all its ki to
  request one extra card play.
- If multiple Meng Huos request it together, all eligible Meng Huos spend their
  ki but only one extra card play is granted.
- The grant permits a hand play only, not an activation. If no legal hand play
  remains, it expires and the owner turn closes.
- Extra-card-play grants from ordinary actions stack. End-owner-turn requests
  are resolved once and cannot retrigger from the granted play.
- Ownership flip removes this passive ability, but retained ki remains.
- The presentation uses only a short gold board-outline pulse and the
  `额外出牌` status. Golden convergence beads are deliberately omitted.

### CangSongYingKe2

Whenever an enemy card is summoned into an orthogonally adjacent slot that CangSongYingKe2 can beat by the normal strict power comparison, CangSongYingKe2 immediately attacks that exact card.

- The reaction participates in the full-board `TRIGGER_CARD_AFTER_SUMMONED`
  window after `card_placed` and before the standard attack.
- Every matching source in that window, including the summoned card's own
  entrance abilities, is discovered and resolved in row-major board order.
- If an earlier source flips, removes, or otherwise invalidates a later queued
  source, that later group does not resolve. The turn still ends normally.
- Multiple eligible reactors stop once the summoned card leaves or changes
  ownership.
- Reaction attacks use the existing flip/exile path and successful-flip triggers.
- Movement is not a summon.
- The ability is lost on flip by the default non-retention rule.
- The reaction uses the generic passive-trigger card pulse before its existing
  flip/removal presentation.

### CangSongYingKe3 and CangSongYingKe4

They retain CangSongYingKe2's summon reaction. Immediately before either card
would flip through an attack or any future non-attack effect, it spends exactly
one ki and adds a fresh catalog copy of its own exact card ID to its current
owner's hand.

- The recipient is the owner immediately before the flip.
- The copy has fresh powers, ki, and abilities from the catalog; runtime
  modifications are not copied.
- A full five-card hand still consumes the ki, then the add action has no
  effect.
- The source card flips normally afterward and loses this ability under the
  default non-retention rule.
- If `CARD_BE_ATTACKED` movement takes the exact target outside the exact
  attacker's range, no before-flip event is emitted.
- Once `CARD_BEFORE_FLIPPED` begins, movement alone never cancels that
  committed flip; the exact target is followed to its current cell.
- Removal, source ownership change, or the target already belonging to the
  intended owner still prevents the flip.

### SanQinFeng1–3

At the start of their owner's turn, an eligible card spends exactly one ki and
selects the first one, two, or three allied board cards with weapon `剑法`,
respectively, in row-major order. The source itself is eligible.

- Each selected card performs its normal four-direction standard attack.
- One card's full attack and trigger chain resolves before the next selected
  instance is revalidated.
- A later snapshot member is skipped only if it no longer satisfies one or
  more declared selector conditions.
- The source spends its ki even when no card matches or no selected card has a
  valid attack target.
- Multiple sources resolve in normal row-major passive-trigger order.

### JinZhenDuJie2–4

- After summon, select the first row-major enemy board instance whose
  `original_owner` is the source's current owner.
- Track the exact instance across board movement and recheck only the declared
  ownership conditions immediately before returning it.
- Replace it with a fresh catalog instance in the source owner's hand. A full
  hand exiles the old instance instead.
- Tiers 3–4 also use the existing one-use after-complete-attack counter.

### WanHuaJian1–3

- Before a full board becomes terminal, every nonwinning on-board WanHua exiles
  itself using one shared winner snapshot. A tie treats both owners as not
  winning. If removals open the board, the duel continues normally.
- Tiers 2–3 create a fresh exact-ID copy in the lowest-index adjacent empty
  cell when attacked. It resolves summoned, after-summoned, and standard-attack
  phases before the incoming attack resumes.
- Tier 2 retains the copy trigger on flip; tier 3 loses it. The ending trigger
  is retained on every tier.
- Self-exile and successful return fade without the external exile feedback;
  removal caused by another card keeps the existing ink-slash animation.

### MianLiCangZhen3

- After this card itself flips an enemy, it resummons that exact target only
  when the target's `original_owner` is this card's current owner.
- Follow the target across movement. If it has already left the board, do
  nothing; otherwise replace it in its current cell with a fresh exact-ID
  catalog instance owned currently and originally by the source owner.
- The fresh instance resolves global summoned triggers, its own after-summoned
  triggers, and then a standard attack if it still belongs to that owner.
- The old instance is not exiled. Its board view fades before the fresh
  instance uses the existing ink-summon effect.
- Resummon and the existing one-use HengShan counterattack are both lost when
  MianLiCangZhen3 flips.
- MianLiCangZhen3 is listed in the catalog but deliberately omitted from
  `DEFAULT_LOCKED_IDS`.

## Deck Semantics

- “Main deck” currently means the five cards forming the starting hand. Those cards are not also waiting to be drawn.
- “Side deck” is the separate draw pile.
- The player main deck cannot contain two cards with the same `glyph`, even
  when their IDs or sects differ. Enemy main decks may repeat glyphs and exact
  card IDs.
- Each owner's side deck is derived separately from that owner's actual main
  deck. A non-`江湖` main card contributes every catalog card of the same sect
  at a lower or equal tier; a `江湖` card contributes nothing, including itself.
- Side-deck candidates come from the whole catalog, regardless of player
  unlocks. Duplicate glyphs collapse to the highest-tier candidate; equal-tier
  ties keep the earliest catalog entry. Final order is catalog order before
  each side shuffles independently.
- Both five-card starting hands also shuffle independently when the duel
  begins. Tests may disable or seed each shuffle separately.
- A zero RNG seed means nondeterministic setup; a nonzero seed supports deterministic tests.
- The player's main deck is persisted in a versioned profile and is read by new duel scenes.
- The collection library has 1,000 logical positions. Unlocked cards occupy a compact prefix; all remaining positions are empty slots.
- A persistent card ID exists in exactly one place: the five-card main deck or the occupied library prefix.
- The initial unlocked pool is every catalog card not listed in
  `DeckProfileStore.DEFAULT_LOCKED_IDS`. The default main deck takes five of
  those cards and every remaining unlocked card begins in the library.
- A directly unlocked card is inserted at the library top. If it has
  still-locked lower-tier cards with the same `glyph` and sect, those cards
  unlock in catalog order at the occupied library bottom.
- Reaching character tiers 2–5 unlocks all exact-tier cards of the selected
  sect before reward generation. Tier boundaries are levels 2, 5, 8, and 11;
  tier 5 remains the cap through level 15.
- Unlock expansion and victory progression save atomically. Loading or
  repairing an existing valid profile never retroactively applies the namesake
  cascade.
- Card mastery is a global exact-ID achievement. The ID must belong to the
  main deck captured at duel start, and some hand copy of that same ID must be
  successfully played before a victory. Runtime instance identity does not
  matter, so drawn or freshly created identical copies qualify; a namesake with
  another catalog ID does not.
- Only victory commits mastery. `闭关重修` preserves it and `封剑归隐` clears
  it. Revealed library/reward cards derive blue/red appearance from mastery;
  enemy reveals remain red and reward placeholder backs remain random.

## Run Completion and Score

- A run ends after a configurable number of victories; the production value is
  15.
- Only completed wins and completed losses are effective duels. Abandoning a
  duel changes neither score inputs nor defeated-enemy history.
- Every victory appends the exact current enemy ID in chronological order.
- Final score is `floor(15000 / effective_duel_count)`. Fifteen straight wins
  therefore score 1000; losses lower the result.
- Final victory bypasses reward selection. The ending receives immutable sect,
  score, duel-count, defeated-enemy, and flawless data.
- Completion uses the same card/run reset as `闭关重修`: it restores the two
  base card unlocks, default main deck, empty library, and empty run-only reward
  history. It preserves unlocked sects (including one declared by the final
  defeated enemy), card mastery, and the highest score achieved for each sect.
- `闭关重修` also preserves best scores, unlocked sects, and card mastery.
  `封剑归隐` clears them with all other progress.
- The ending is the main-menu presentation without its three actions. It lists
  every defeated enemy in order and uses a distinct undefeated passage when the
  run contains no losses.
- Score and prose use only the clear upper painting beneath the title. The
  smaller score remains fixed; prose rolls upward inside a clipped viewport
  until no line remains hidden, then stops. Early taps are consumed. The first
  release after completion returns to the normal main menu.

## Deck Builder

- Deck building is a separate scene at `res://scenes/deck_builder.tscn`; it does not run the duel simulator, scores, AI, combat VFX, or audio.
- It reuses the duel's fixed 9:16 presentation, decorative backdrop, top header, five-slot opponent hand, five-slot player hand, CardView, and CardInspector.
- The opponent hand represents the upcoming enemy. It stays face-down in normal mode and is revealed in script-controlled testing mode.
- The center parchment is titled `藏经阁` and displays four standard 3:4 library cards per row with exactly three visible rows.
- Its exterior uses the exact same parchment geometry and shared style code as the card inspector.
- The vertical scrollbar is hidden. Players navigate by swiping up/down; desktop mouse swipes are handled locally without enabling project-wide mouse-to-touch emulation.
- The first card row begins eight pixels below the title-divider content boundary.
- Seven-pixel side insets keep the first and fourth card borders, shadows, and hold lift visible inside the clipped scroll viewport.
- Library card names use tier colors: slate grey for tier 1, forest green for 2, steel blue for 3, muted violet for 4, dark orange for 5, and crimson for every other value.
- The 1,000 logical library slots form 250 rows and are virtualized. Only three visible rows plus one buffer row above and below—20 slot Controls total—are live.
- A short tap on any revealed card opens the existing inspector. Closing it restores the prior library scroll position.
- Immediate pointer movement scrolls the library. Holding a library card for roughly 0.25 seconds arms a drag.
- Dropping an armed library card with a new glyph onto a main-deck slot
  exchanges the two cards. If that glyph already occupies another main slot,
  the incoming card enters the chosen slot, the chosen-slot card moves into the
  old namesake slot, and the old namesake returns to the exact library source.
- Invalid drops and empty library slots do nothing.
- Exchanges save immediately. If persistence fails, the displayed exchange is rolled back.
- The header icon only emits `back_requested`; a future scene router will decide where to navigate.
- The deck builder has no score panels.

## Inspector

- A single tap on a revealed card opens an inspector occupying exactly the board rectangle.
- A face-down card cannot open it or leak metadata.
- The inspector hides the board and score while keeping hands, top bar, and status visible.
- It is modal: gameplay input is blocked.
- It cannot open while an action is resolving.
- AI search may continue while the inspector is open, but a completed AI result must wait to apply until it closes.
- Tap closes; swipe scrolls and does not close.
- Metadata order is sect, tier, weapon; name uses `glyph`; empty content displays a placeholder.

## AI

- Target behavior is near-perfect play within a fixed time budget.
- Current hard-opponent budget is 10 seconds; future easier opponents can use 5 seconds.
- Difficulty changes only the time budget, not the evaluator or intentional move weakening.
- Use the best result from the deepest fully completed iteration.
- Ignore an incomplete deeper iteration.
- If depth one cannot complete, worker search fails, or its action becomes invalid, use deterministic greedy fallback.
- Search can finish early if it proves/solves the position.

## 来鹤清泉 / 岱宗如何

- Revelation is stored per exact runtime instance in
  `revealed_to_owner_ids`; testing mode and AI perfect information never add to
  it. A revealed card remains revealed for the duel.
- LaiHe1 reveals the current enemy hand. LaiHe3 also records a permanent
  audience for later enemy draws, which survives the source flipping or
  leaving play. Each successful draw emits `card_drawn` before
  `card_revealed`.
- LaiHe4/5 reveal only glyphs remembered from earlier duels against the current
  enemy. A revealed enemy summon receives a non-retained modifier that makes
  each defending edge count as 1 without changing its offensive or displayed
  powers. The granted weakness survives the granting source, but is lost when
  the affected card flips.
- LaiHe2/3/5 prevent their own pending flip once per protection window. The
  protection is removed after any enemy card actually flips or at the start of
  the source owner's turn. A prevented attempt does not consume it and emits no
  `CARD_AFTER_FLIPPED` event.
- Weakened presentation changes only the central artwork alpha to 70%; frame,
  powers, ki, ownership color, and interaction remain fully opaque.

## 云雾十三式 / 一剑落九雁 / 天柱云气

- “失去效果直到当前回合结束” removes every currently active non-retained
  ability from the exact card instance. Retained abilities are never removed.
  Later grants remain active unless a later suppression removes them.
- Suppressed abilities restore after end-owner-turn triggers. If the card flips
  first, all stored non-retained abilities are erased permanently.
- YunWu suppression resolves in `TRIGGER_CARD_BEFORE_SUMMONED`, before global
  summon reactions. Tier 3's later swap remains an ordinary adjacent swap.
- YiJian uses the exact direct flip records from the completed standard attack.
  The sole matching card must still be on the board and adjacent. A failed tier
  3 swap stops its follow-up attack; a successful one attacks from the new cell.
- Every swap is orthogonally adjacent at resolution. Both conceptual movement
  legs emit `CARD_BEFORE_MOVED`, revalidate immediately before mutation, then
  emit `CARD_AFTER_MOVED` after the successful mutation.
- TianZhu moves to the lowest row-major adjacent empty cell. Tiers 3–4 draw only
  after that movement succeeds. Tier 4's before-move suppression triggers for
  movement initiated by any card or effect.

## 剑发琴音 / 雁回祝融

- JianFa entry movement chooses the lowest row-major empty cell lying exactly
  between the source and an enemy on the same row or column.
- JianFa tiers 2–3 spend one ki to move to an adjacent empty cell, then grant
  one additional hand-card play. Multiple ordinary grants stack. The extra
  play stays in the current owner turn, accepts no activation, and does not
  repeat turn boundaries.
- JianFa tier 3 suppresses adjacent enemies after any successful movement of
  itself. The suppression remains through granted plays and restores only when
  that owner turn finally closes.
- YanHui's before-flip rule requires exactly one leftmost light-sword hand
  selection. YanHui returns first; a full hand removes it. The exact selected
  hand instance is then summoned into YanHui's original cell, so there is no
  reservation zone and no duplicate view.
- YanHui tier 4 activation cannot target itself. It returns another allied
  board card and summons a fresh YanHui copy into that ally's original cell.
- Generic `ACTION_RETURN_CARD_TO_HAND` resolves an exact card reference and
  declared recipient; generic `ACTION_SUMMON_CARD` accepts either an exact
  selected instance or a fresh-copy specification plus a declared cell rule.

## 太极剑共通效果

- TaiJiSanHuan4/5 and TaiJiDaKui5 snapshot adjacent enemy summon sources and
  redirect the summon standard attack only while source and summoned card remain
  adjacent. The redirected attack targets only the attacker's current allies.
- The shared modifier and its consume trigger occupy one ability entry. After
  any enemy actually starts an attack against at least one card that shared the
  attacker's owner at attack start, `ACTION_REMOVE_THIS_ABILITY` removes that
  entry. The friendly fire may come from this redirect, YiZi, or another effect.
- Every qualifying Taiji source consumes its own effect. Zero-target,
  insufficient-power, and ordinary enemy-versus-source-ally attacks do not
  consume it; a started friendly-fire attack consumes it even without a flip.

## 阴阳掌力

- The special power rule applies only when all four stored powers are exactly
  `[-1, -1, -1, -1]`. Those numbers are hidden, any nonnegative attacker edge
  defeats the corresponding `-1`, and signed power-change actions cannot
  affect or select that card. Limited selectors filter it before counting the
  limit.
- YinYang resolves its own exile, then draws the first two palm cards from the
  side deck, then grants every allied palm currently in hand. Skipped non-palms
  remain in their original relative order. Hand capacity can reduce the count;
  a filtered empty/no-match draw does not create the ordinary TaiZu fallback.
  Both newly drawn palms are included in the later grant.
- Tier 3 palms may attack an orthogonal enemy two cells away only through one
  empty cell. Tier 4 also permits one intervening current ally; an enemy always
  blocks. Ordinary adjacent attacks remain unchanged.
- The granted repeat begins one new complete standard attack after the first
  completes. That attack re-reads the current cell, owner, and legal targets,
  and still fires other after-attack abilities. A `repeat_attack` context flag
  prevents only the same YinYang grant from recursively scheduling a third.
- Exact duplicate grants are idempotent. Tier 4 range is the effective
  superset if both tiers were granted. All YinYang grants are non-retained and
  disappear on flip.

## 寒冰真气 / 天外玉龙 / 翻面清理

- Enemy-hand activations use the opponent's logical hand index only to commit
  an exact `instance_id` snapshot. Costs and later actions reuse that snapshot,
  so a source flip during payment cannot retarget the effect.
- Active targeting may choose a four-`-1` YinYang card. The activation still
  spends ki and reveals it, while its power-change action has no effect.
  Automatic limited selectors reject YinYang before counting their limit.
- HanBin tier 4's transition from positive ki to zero emits the ki change and
  resolves its self-flip before the activation's weaken/reveal actions. The
  observer remains the source owner captured before paying the cost.
- HanBin's self-after-flip grant is an isolated, non-retained ability entry. It
  grants a separate owner-turn-start ability; it does not use
  `retained_on_flip`. The granted rule weakens HanBin and the leftmost two legal
  allied hand cards in one shared power-change batch. A later flip removes it
  permanently and never recreates it.
- Every successful flip first changes ownership. Old non-retained entries other
  than isolated self-after-flip entries are removed next. `CARD_AFTER_FLIPPED`
  then resolves, after which the old isolated entries are removed. Newly
  granted abilities are not part of that final cleanup. A self-after-flip
  trigger must never share its ability entry with other triggers, an
  activation, or modifiers.
- TianWai swaps only with the exact adjacent allied summon that caused its
  trigger. A successful swap moves TianWai into the trigger card's old cell,
  then TianWai performs the follow-up attack there. A failed swap stops the
  attack. Tier 3's preceding `+1` is optional for flow: YinYang ignores it but
  the swap and attack continue.
- Simultaneous TianWai sources are discovered in stable row-major order. Each
  later source revalidates the exact trigger instance and adjacency after all
  earlier swaps and attacks.

## 独孤九剑

- No Form handles its source with ordinary `ACTION_EXILE_SELF` and
  `ACTION_DRAW_CARDS`, then uses the existing adjacent-card selector for exact
  row-major targets. Every removal is followed immediately by the default draw
  for that action subject's pre-removal current owner.
- Each owner records the exact most recent successful hand play. Anticipate
  reads a frozen pre-action copy, so it never selects itself. A target returns
  to the owner who originally played that hand action even after a flip; full
  recipient hands exile it and missing targets do not stop later actions.
- Break All queues persistent per-owner layers. Heart methods neither trigger
  nor consume them. Each later non-heart hand play consumes at most one layer
  before its own before-summon ability discovery, permanently removing every
  non-retained ability while preserving `retained_on_flip` entries.
