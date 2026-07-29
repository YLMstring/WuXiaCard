# Main Menu and Run State Design

## Goal

Add a responsive main menu for **九宫论剑** with three actions:

- `踏入江湖`
- `闭关重修`
- `封剑归隐`

The menu becomes the application's initial screen, resumes an active run at
deck building, starts an inactive profile at sect selection, and provides
deliberately difficult confirmation flows for resetting a run or all progress.

## Scene and Visual Design

Create a dedicated `main_menu.tscn` and `MainMenuController`.

The full square `res://pics/main_menu_background.png` is always visible and is
never stretched or cropped. It is centered at the largest square that fits the
viewport. A focused backdrop control fills the remaining top-and-bottom or
left-and-right bands with non-interactive rice-paper, mist, mountain, and ink
extensions. Extensions contain no unique imagery or controls.

The title `九宫论剑` sits in the calm upper-center region of the square. The
three actions form a centered vertical stack below it and above the arena.
Buttons have no visible rectangular panel. Dark calligraphic text receives
restrained hover emphasis, a small pressed-scale response, and a brief ink
bloom or darkening. Hit areas remain comfortably touch-sized without extending
into adjacent actions.

A single notice label sits below the action stack. It is empty during normal
navigation and reports reset confirmations and completion.

## Component Boundaries

### MainMenuController

The menu is presentation-only. It emits:

- `journey_requested`
- `run_reset_confirmed`
- `progress_reset_confirmed`

It owns the two confirmation counters, their three-second reset timers, button
feedback, responsive layout, and notice text. It does not directly read,
delete, or rewrite save files.

### MainFlowController

The existing application root remains the navigation authority. It:

- starts on the main menu;
- loads the profile when `踏入江湖` is requested;
- opens deck building when `run_active` is true;
- opens sect selection when `run_active` is false;
- handles confirmed reset requests through `DeckProfileStore`;
- returns to the menu from the sect-selection and deck-builder back icons;
- keeps duel-to-deck-builder navigation unchanged.

### DeckProfileStore

The profile schema gains:

- `run_active: bool`
- `selected_sect_id: String`

`selected_sect_id` is empty when no run is active and contains a valid unlocked
sect ID when a run is active.

The store exposes atomic operations for:

- beginning a run with a chosen sect while unlocking that sect's tier-one
  cards;
- resetting only the current run;
- resetting all progress to the default profile.

Save-file mutation remains in the store and continues to use the existing
temporary-file and backup replacement path.

## Profile and Migration Rules

The schema version increments from 2 to 3.

A new profile starts with:

- `run_active = false`;
- `selected_sect_id = ""`;
- only the default `玄岳剑宗` sect unlock;
- the existing default unlocked card pool and default five-card deck.

Schema-2 profiles migrate without losing unlocks, deck order, or library order.
Because old saves do not contain reliable active-run information, they migrate
as inactive with an empty selected sect. The player selects a sect once after
the update to begin the newly explicit run.

Confirming a valid unlocked sect:

1. unlocks its tier-one cards, preserving existing ordering rules;
2. sets `run_active = true`;
3. stores that sect ID in `selected_sect_id`;
4. saves the complete candidate profile atomically;
5. enters deck building only after the save succeeds.

## Menu Behavior

### 踏入江湖

Pressing the action clears both confirmation counters.

- Active run: enter deck building.
- Inactive run: enter sect selection.

### 闭关重修

The first four presses do not mutate the profile. After each press the notice
shows `再按 N 次闭关重修`, where `N` counts down from 4 to 1.

The fifth press emits `run_reset_confirmed`. A successful reset:

- preserves all unlocked sects and cards;
- sets `run_active = false`;
- clears `selected_sect_id`;
- restores `DEFAULT_MAIN_DECK_IDS` as the five-card main deck;
- rebuilds the library from every other unlocked card, preserving the prior
  relative library order where possible;
- keeps the player on the main menu;
- shows `本次江湖历程已重置`.

### 封剑归隐

The first nine presses do not mutate the profile. After each press the notice
shows `再按 N 次封剑归隐`, where `N` counts down from 9 to 1.

The tenth press emits `progress_reset_confirmed`. A successful reset replaces
the save with a new default profile:

- no active run;
- no selected sect;
- only default sect and card unlocks;
- default main deck and library;
- the player remains on the main menu;
- the notice shows `所有进度已清除`.

### Counter Cancellation

Both counters reset to zero:

- three seconds after the most recent destructive-button press;
- when any different menu action is pressed;
- whenever the menu is newly shown.

Resetting a counter clears a countdown notice but does not erase a completion
notice produced by a successful reset.

If a save mutation fails, remain on the menu and show `保存失败，请重试`.

## Navigation

The main flow becomes:

```text
Main Menu
  ├─ 踏入江湖 + inactive run → Sect Selection
  │                              └─ choose sect → Deck Building
  └─ 踏入江湖 + active run   → Deck Building
                                 └─ choose initiative → Duel
                                                        └─ return → Deck Building
```

The sect-selection and deck-builder back icons both return to the main menu.
They do not change run state.

## Testing

Profile-store tests cover:

- schema-3 defaults and validation;
- schema-2 migration preserving permanent data;
- atomic run start;
- run reset preserving unlocks while restoring the default deck;
- full reset restoring the default profile;
- invalid or failed operations leaving the prior profile unchanged.

Menu tests cover:

- exact labels and initial empty notice;
- 5-press and 10-press confirmation thresholds;
- countdown text;
- three-second timeout;
- cancellation by another action;
- counters resetting when shown again;
- touch-sized, non-overlapping action areas.

Main-flow tests cover:

- application startup at the menu;
- inactive-run routing to sect selection;
- active-run routing directly to deck building;
- sect confirmation activating the run;
- sect-selection and deck-builder back navigation;
- successful and failed reset feedback;
- duel return behavior remaining unchanged.

Runtime verification checks the menu at 9:16, 9:20, 16:9, and ultrawide
viewports, including full artwork visibility and readable title/actions.
