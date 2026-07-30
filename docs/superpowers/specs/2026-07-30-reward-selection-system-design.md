# Reward Selection System Design

Date: 2026-07-30  
Status: Implemented

## Purpose

After a completed duel, give the player one new card from a small outcome-dependent
choice. The reward flow must reuse the established deck-building presentation,
must not alter the current main deck, and must survive leaving or restarting the
game without losing or rerolling the offer.

## Approved Player Flow

### Abandonment

Pressing the duel return icon before the duel finishes returns directly to the
deck-building scene. It grants no level, enemy, or card reward changes.

### Victory

1. Apply the existing victory progression first.
2. Increase the player level when below the level cap and choose the next enemy.
3. Calculate the player's tier from the resulting new level.
4. Build a reward pool from locked cards whose card tier exactly equals the
   player's new tier.
5. Randomly select up to three distinct cards and persist that exact offer.
6. Open reward selection, or return directly to deck-building if the pool is
   empty.

A threshold victory therefore uses the new tier. For example, a level-4 player
who wins, reaches level 5, and becomes tier 3 receives tier-3 victory rewards.
A victory at the level cap still offers rewards using the current tier.

### Defeat

1. Keep the current level, tier, enemy, and remembered enemy cards unchanged.
2. At player tier 2 or higher, build a reward pool from locked cards with any
   tier lower than the player's tier.
3. At player tier 1, use locked tier-1 cards because tier 0 does not exist.
4. Randomly select up to three distinct cards and persist that exact offer.
5. Open reward selection, or return directly to deck-building if the pool is
   empty.

For example, a tier-4 defeat may offer any mixture of locked tier-1, tier-2,
and tier-3 cards.

## Reward Eligibility and Sampling

- Only card IDs present in the card catalog are eligible.
- Already-unlocked cards are excluded.
- A single offer never repeats a card ID.
- Sampling is uniform without replacement from the complete eligible pool.
- A deterministic random-number generator can be injected by tests.
- The exact chosen IDs, including their order, are saved before the reward scene
  is displayed.
- If fewer than three cards qualify, every unused position displays a
  non-interactive player-colored card back.
- If no cards qualify, no empty reward screen is shown.

## Reward Scene

Create a dedicated reward-selection scene that inherits the established
deck-building presentation rather than adding a reward mode to the normal
deck-builder controller.

It reuses:

- the decorative background and fixed portrait canvas;
- the lacquer top wash, enemy seal, upcoming-enemy name, and return icon;
- the upcoming enemy's five-card preview hand;
- the existing `藏经阁` scroll appearance;
- normal `CardView` rendering and card inspection;
- the player's unchanged five-slot main-deck hand;
- existing drag proxy behavior and hand hit testing.

It does not show:

- the `抢占先机` control;
- the `后发制人` control;
- duel score panels.

The scroll contains one centered row of exactly three reward positions. An
eligible reward is revealed and shows its tier-colored card name below it.
An unused position shows only a face-down card back and cannot be inspected or
dragged.

Tapping a revealed reward opens the existing card inspector. Closing inspection
restores the reward scroll and preserves the offer.

The top return icon may return to the main menu without discarding the pending
offer. Choosing `踏入江湖` later resumes the same reward scene.

## Claim Interaction

The player holds and drags one revealed reward card anywhere over the complete
five-slot player-hand region.

On a valid drop, one atomic profile save:

1. verifies that the selected card belongs to the current pending offer;
2. verifies that the card is still locked;
3. adds the card to `unlocked_card_ids`;
4. inserts the card at the top of the occupied library order;
5. leaves all five `main_deck` entries unchanged;
6. clears the pending reward offer.

After the save succeeds, the flow opens deck-building. The newly unlocked card
is therefore immediately visible at the top of the library.

Dropping outside the hand cancels the drag and leaves the pending offer intact.
If saving fails, the reward scene remains open and displays a retry notice.

## Persistent Profile State

Bump the deck-profile schema and add:

```text
pending_reward_card_ids: Array[String]
```

Profile rules:

- inactive runs must have no pending reward;
- a pending reward is allowed only during an active run;
- it contains between one and three unique, known, currently locked card IDs;
- repair filters unknown, duplicate, or already-unlocked IDs while preserving
  valid order;
- legacy profiles migrate with no pending reward;
- beginning a run, resetting a run, and resetting all progress clear it;
- advancing to another enemy does not independently create a reward—the main
  flow creates and saves the offer immediately after successful victory
  progression.

The pending IDs are sufficient to resume the scene. The originating outcome and
tier need not be stored because eligibility is checked when the offer is
created, while claiming validates only membership and lock state.

## Components and Responsibilities

### `DeckProfileStore`

Add focused operations:

- query pending reward IDs;
- generate and save an offer for victory or defeat;
- atomically claim one pending reward;
- clear or repair pending reward state during lifecycle transitions.

The store owns eligibility, randomness, validation, and persistence so scene
controllers cannot grant arbitrary cards.

### `RewardSelectionController`

Own only presentation and interaction:

- render the saved offer and card-back placeholders;
- render the upcoming enemy preview and current main deck;
- open and close inspection;
- manage reward dragging;
- request an atomic claim from the profile store;
- emit completion or back requests.

### `MainFlowController`

Route outcomes:

- abandoned → deck builder;
- victory → advance progression → create reward → reward scene or deck builder;
- defeat → create reward → reward scene or deck builder.

On `踏入江湖`, a valid pending offer takes priority over the ordinary active-run
deck-builder route.

## Failure Handling

- Progression save failure: return to deck-building without creating a reward
  and log a warning; the unchanged saved profile remains authoritative.
- Offer save failure: do not show an unsaved, rerollable offer; return to
  deck-building and log a warning.
- Claim save failure: keep the same reward scene and offer visible.
- Corrupt or obsolete pending IDs: profile repair removes invalid entries.
- No eligible locked cards: skip reward selection and continue to deck-building.

## Verification

Add focused automated coverage for:

- victory eligibility at the current tier;
- threshold victory eligibility at the newly reached tier;
- defeat eligibility across every lower tier;
- tier-1 defeat fallback;
- exclusion of unlocked cards;
- unique seeded sampling and stable saved order;
- one-, two-, and zero-candidate behavior;
- schema migration, validation, repair, reset, and resume;
- three reward positions with card backs for missing choices;
- inspection of revealed rewards but not placeholders;
- cancelled drops preserving the offer;
- successful drops unlocking without modifying `main_deck`;
- claimed cards entering the top of the library;
- abandonment bypassing rewards;
- victory and defeat routing;
- resuming a pending reward through `踏入江湖`.

Run the full existing regression suite after the focused tests. Playtest the
golden path as:

```text
finish duel → press return → inspect reward → drag reward to hand
→ deck builder opens → chosen card is at library top → main deck is unchanged
```

## Implementation Record

Implemented on 2026-07-30:

- `DeckProfileStore` schema 6 persists exact pending reward IDs and provides
  seeded offer creation plus atomic claims.
- `reward_selection.tscn` inherits the deck-building scene.
- `RewardSelectionController` owns reward presentation, inspection, dragging,
  cancellation, claiming, and return behavior.
- `DeckLibraryGrid` retains its four-column/1000-slot defaults but now supports
  the reward scene's three-column/three-slot configuration.
- `DeckLibrarySlot` supports non-interactive face-down display placeholders.
- `MainFlowController` routes victory, defeat, abandonment, claims, and pending
  reward resume.

Focused reward-profile, reward-scene, main-flow, profile-store, and sect
selection tests pass. The full suite passes 14 of 19 suites; the remaining five
are the established stale card-fixture suites documented by the project
baseline and are unrelated to reward selection.
