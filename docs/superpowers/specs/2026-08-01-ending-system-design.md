# Ending System Design

## Goal

End a run after the player defeats a configurable number of enemies, default
15. When the player presses the duel return icon after the final victory, skip
the reward flow and show a dedicated ending screen. The ending records a
best-per-sect global achievement, closes the completed run, and lets one tap
return to the ordinary main menu.

## Approved Rules

- The default victory target is 15 and is adjustable from the main flow.
- An effective duel is a completed victory or defeat.
- An abandoned duel changes no ending counter.
- Score is `floor(15000 / effective_duel_count)`.
- A run with 15 victories and no defeats therefore scores 1000.
- The final victory offers no reward.
- Achievement data keeps the highest score earned for each sect.
- Completing a run restores the default main deck and closes the run while
  preserving unlocked sects, unlocked cards, and best scores.
- Run reset preserves best scores. Full progress reset deletes them.
- One tap anywhere on the ending returns to the normal main menu.

## Profile Schema

Extend the existing versioned profile with:

```gdscript
"effective_duel_count": 0,
"defeated_enemy_ids": [],
"best_scores_by_sect": {},
```

`effective_duel_count` and `defeated_enemy_ids` are active-run data. For an
inactive run they are reset to zero and an empty array. Each defeated enemy ID
is appended in chronological order.

`best_scores_by_sect` is global progression data. Keys are valid sect IDs and
values are nonnegative integer scores. A completed run adds its selected sect
when absent, or updates it only when the new score is higher than the stored
value.

Profile validation requires:

- a nonnegative integer effective-duel count;
- an array containing only valid enemy IDs;
- effective duels not fewer than recorded victories;
- valid sect IDs and nonnegative integer scores in the achievement dictionary;
  and
- empty active-run counters when `run_active` is false.

Beginning a run initializes both run counters. Run reset clears the counters
and restores the default deck without changing achievements. Full reset uses
the default empty achievement dictionary.

### Legacy Migration

Older profiles cannot truthfully reconstruct losses or past opponents. During
the schema upgrade, any active legacy run is closed and its deck restored to
the default deck. Unlocked cards and sects remain. The new achievement table
starts empty. This avoids granting an inaccurate ending or score.

## Duel Result Transaction

The profile store owns one atomic operation for recording a completed duel. It
accepts the current profile, the outcome, the configurable victory target, and
the existing optional next-enemy override used by deterministic tests.

### Abandon

Abandons do not call the transaction. The flow returns directly to deck
building with all run statistics unchanged.

### Defeat

1. Increment `effective_duel_count`.
2. Keep the current level, enemy, memory, and defeated-enemy list.
3. Save the profile atomically.
4. Continue into the existing lower-tier reward flow.

### Non-final victory

1. Increment `effective_duel_count`.
2. Append the current enemy ID to `defeated_enemy_ids`.
3. Advance level and choose the next same-level enemy exactly as today.
4. Apply tier-crossing unlocks and clear enemy memory.
5. Save atomically.
6. Continue into the existing victory reward flow.

### Final victory

1. Increment `effective_duel_count`.
2. Append the current enemy ID.
3. Build an immutable ending summary before run fields are cleared:
   - selected sect ID;
   - score;
   - effective-duel count;
   - defeated enemy IDs in order; and
   - whether the run was flawless.
4. Update the selected sect's best score only if the new score is higher.
5. Close the run and restore the default main deck while preserving unlocks
   and achievements.
6. Save all changes in one atomic profile write.
7. Return the summary to the scene flow and bypass reward selection.

If validation or saving fails, the operation returns the unchanged profile.
The scene flow must not display an ending or generate a reward from unsaved
state; it reports the existing save warning path and returns to deck building.

The victory target is constrained to the current 1–15 progression. This makes
the default final opponent the first level-15 opponent and also allows short
test or balance runs without inventing post-level-15 progression.

## Scene Flow

Add a dedicated `ending.tscn` and controller. The main flow creates it only
from a successful final-victory transaction and passes the immutable ending
summary directly.

```text
duel return
    |
    +-- abandoned -> deck builder
    |
    +-- defeat -> record duel -> reward or deck builder
    |
    +-- victory -> record duel
                      |
                      +-- ordinary -> reward or deck builder
                      |
                      +-- completed -> ending -> tap -> main menu
```

Because completion already closes the run, pressing `踏入江湖` after the ending
begins a fresh sect selection.

## Ending Presentation

`ending.tscn` instances the existing main-menu scene as its visual foundation.
This reuses the exact:

- phone background art;
- decorative long/wide-screen overflow;
- `九宫论剑` title asset;
- title glow; and
- title breathing animation.

The ending controller hides the three action buttons and normal notice. A
transparent full-screen input surface emits `return_requested` on one tap.

Directly below the title, display a prominent score line:

```text
论剑得分 · 1000
```

Below it, display a longer centered paragraph occupying the former button
area. It uses the selected sect's catalog `glyph` and every defeated enemy
catalog `name`, joined in chronological order. Chinese smart wrapping,
punctuation-safe line breaking, mobile margins, and comfortable line spacing
apply at normal, tall-phone, and wide-PC aspect ratios.

The base prose is:

```text
你立于华山之巅，长风掠过衣袂，回首踏入江湖以来的诸般往事。你本是{sect}门下，先后胜过{all enemy names}。{run-specific passage}而今群雄皆已成为身后旧影，九宫论剑之名亦随你的剑锋传遍四海。自此江湖再论高下，无人能够绕过你的名字。
```

For a flawless run:

```text
一路走来，你连战连捷，剑锋所向，未尝一败；
```

For a run containing one or more defeats:

```text
一路走来，你有过锋芒毕露，也曾折剑再战；
```

The score and prose are derived only from the immutable completion summary and
catalog display data. The ending never reads cleared active-run fields.

## Components and Responsibilities

### DeckProfileStore

- migrate and validate the new schema;
- initialize and clear run statistics;
- record victory/defeat outcomes atomically;
- calculate the integer score;
- update best-per-sect achievements;
- return immutable ending summaries; and
- preserve achievements across run reset but clear them on full reset.

### MainFlowController

- expose the adjustable victory target, default 15;
- route duel outcomes through the profile-store transaction;
- preserve the current abandon and reward behavior;
- bypass the final reward and show the ending; and
- route ending taps to the ordinary main menu.

### EndingController

- configure the instanced main-menu presentation;
- format the score and catalog-backed narrative;
- apply responsive layout and Chinese wrapping; and
- emit a navigation-neutral return request.

The ending controller does not mutate profile data. Completion is already
durable before the screen appears.

## Tests

### Profile tests

- default and migrated schema;
- legacy active-run closure with unlock preservation;
- victory and defeat effective-duel counting;
- abandon leaving counters unchanged through the flow;
- chronological enemy history;
- `floor(15000 / effective_duel_count)` rounding;
- completion at configurable thresholds;
- no final reward state;
- higher score replacing a sect achievement;
- lower score not replacing it;
- independent best scores for different sects;
- run reset preserving achievements; and
- full reset deleting achievements.

### Ending scene tests

- exact reuse of main-menu background and title presentation;
- all three actions and the normal notice hidden;
- score placement and formatting;
- full ordered enemy-name list;
- flawless and comeback prose branches;
- smart wrapping and no clipped text;
- responsive portrait, tall, and wide layouts; and
- one tap emitting exactly one return request.

### Flow tests

- non-final wins retain the reward path;
- losses retain the lower-tier reward path;
- final victory goes directly to ending;
- final victory creates no pending reward;
- completed profile is inactive with a default deck;
- ending tap returns to main menu; and
- the next journey starts at sect selection.

Run focused profile, ending, main-flow, reward, and menu suites before the full
runner. Finally play a threshold-one run through duel return, ending display,
tap return, and fresh journey navigation, then inspect runtime diagnostics.
