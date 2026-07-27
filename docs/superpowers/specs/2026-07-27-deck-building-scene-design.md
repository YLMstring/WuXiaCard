# Deck-Building Scene Design

Date: 2026-07-27  
Project: Wuxia Card  
Status: Approved for specification

## Objective

Add a portrait-oriented deck-building scene that reuses the duel's established visual language and card interactions. The scene shows the upcoming enemy's hand, a scrollable `藏经阁` library, and the player's five-card main deck. Players exchange library cards with main-deck cards by dragging.

This feature establishes persistent deck selection and a scalable 1,000-slot collection view without adding navigation, progression rewards, or changes to side-deck behavior.

## Approved User Experience

### Fixed frame and shared chrome

The scene retains the duel's fixed 9:16 gameplay canvas and decorative extensions for taller or wider displays. It reuses the current:

- Decorative backdrop
- Lacquer topwash and gold ornament treatment
- Upcoming enemy name placement
- Back icon
- Opponent-hand and player-hand geometry
- Card visuals
- Card-inspection scroll

The back icon emits `back_requested`. The deck-building scene does not decide which scene should open next.

The opponent's five cards represent the upcoming enemy's main deck. They are face-down in normal mode and revealed when `Settings.TESTING_MODE` is enabled. The score panels are absent.

### Library scroll

The central board is replaced by a parchment scroll matching the existing card inspector. Its title is `藏经阁`.

The scroll shows:

- Five slots per row
- Three complete rows in the visible area
- Card artwork and power values using the existing card view
- The card's catalog `glyph` below each occupied slot
- Empty-card-slot visuals for unoccupied positions
- Continuous vertical scrolling through 1,000 logical library positions

The 1,000 slots form 200 rows. The initial profile has four library cards followed by 996 empty slots.

The grid is virtualized. It instantiates only the three visible rows plus a small row buffer and rebinds those controls as the scroll position changes. This avoids constructing 1,000 card controls on Android.

### Main deck

The bottom hand contains five fixed main-deck slots. Card size and slot position do not change. A bottom status line displays the normal instruction, `拖动藏经阁卡牌以替换主牌组`, and may temporarily display persistence errors.

## Interaction Rules

### Library-to-deck exchange

Only an occupied library slot can start a deck-building drag. The player must
hold it briefly before dragging; the initial hold threshold is 0.25 seconds and
is exposed as a deck-builder tuning value.

Dragging a library card onto one of the five main-deck slots performs a literal exchange:

1. Record the dragged card's logical library index.
2. Put the library card into the chosen main-deck position.
3. Put the displaced main-deck card into the recorded library position.
4. Save the updated profile immediately.
5. Refresh the affected visible controls without changing scroll position.

The player's five-card deck and library therefore contain each owned card in exactly one place.

Dropping anywhere other than a main-deck slot cancels the operation. A cancelled drag restores the original visual state and does not save. Empty slots neither drag nor inspect.

The drag layer uses a visual proxy, while the logical library index remains authoritative. Virtualized controls may be rebound only after the drag completes or is cancelled.

### Tap, drag, and scroll separation

The library resolves its three competing gestures as follows:

- Releasing an occupied revealed card before the hold threshold, without
  meaningful movement, requests inspection.
- Moving before the hold threshold scrolls the library.
- Holding an occupied card through the threshold arms it for dragging; movement
  after that point starts the library-to-deck drag.
- Empty slots can start scrolling but cannot arm a drag or request inspection.

The armed card receives a restrained lift cue so the player knows that dragging
is ready. An interaction resolves to only one of tap, drag, or scroll.
Scrolling cannot accidentally inspect a card or begin a deck swap.

### Card inspection

A revealed library card or main-deck card opens the existing card inspector. A revealed opponent card can also be inspected in testing mode.

While the inspector is open:

- Library scrolling is disabled.
- Card dragging is disabled.
- The inspector occupies the same central area as the library scroll.
- The previous library scroll offset is preserved.
- A tap outside or the inspector's existing close behavior returns to deck building at the preserved offset.

Face-down opponent cards cannot be inspected.

## Scene and Component Boundaries

### `deck_builder.tscn`

A separately runnable scene containing the shared-looking chrome, opponent hand, library scroll, player hand, drag layer, status line, and reusable card inspector.

It does not inherit from or add a mode to `DuelController`. This avoids coupling deck editing to turn state, AI, scoring, board simulation, and duel effects.

The scene exposes:

- `back_requested`
- Configuration for the upcoming enemy's display name and five card IDs

For standalone testing, it may default to the current opponent name and `DuelDecks.get_opponent_card_ids()`. A future parent scene will supply navigation and upcoming-enemy context.

### `DeckBuilderController`

Owns scene-level coordination:

- Loads the deck profile.
- Builds opponent and main-deck card views.
- Connects library, drag, inspection, and back signals.
- Applies testing-mode visibility.
- Commits valid swaps.
- Rolls back a swap if persistence fails.

It does not contain profile validation internals or virtual-grid layout internals.

### `DeckProfileStore`

Owns persistent collection data independently from UI:

- Creates the default profile.
- Loads and validates saved data.
- Repairs recoverable data.
- Saves atomically under `user://`.
- Inserts newly unlocked cards.
- Exchanges a library position with a main-deck position.
- Supplies the saved main-deck IDs to duel setup.

### `DeckLibraryGrid`

Owns the virtualized five-column library:

- Maps scroll offset to logical row indices.
- Maintains three visible rows plus a small buffer.
- Rebinds reusable slot controls.
- Resolves tap, pre-hold scrolling, and hold-then-drag gestures.
- Emits inspection and drag requests with logical slot indices.
- Displays occupied and empty slot states.
- Preserves scroll offset through swaps and inspection.

It does not mutate the deck profile directly.

### Reused components

The feature reuses:

- `scenes/card_view.tscn` and `scripts/card_view.gd`
- `scenes/card_inspector.tscn` and `scripts/card_inspector.gd`
- `scripts/duel_backdrop.gd`
- Existing topwash, ornament, card-back, hand-slot, and back-icon assets and styles
- `scripts/game_settings.gd` for testing mode
- `scripts/duel_decks.gd` for the current opponent and default decks

No broad refactor of the working duel scene is included.

## Persistent Profile

The profile is stored as versioned JSON under `user://`. Its logical fields are:

- `schema_version`
- `unlocked_card_ids`
- `main_deck`: five ordered card IDs
- `library_slots`: exactly 1,000 card IDs or empty values

The initial unlocked set contains every current catalog card except `CangSongYingKe1`.

The initial main deck uses the current player main-deck defaults:

1. `CangSongYingKe2`
2. `gate_general`
3. `meng_huo`
4. `jiang_wei`
5. `fa_zheng`

The other four unlocked cards occupy library positions 1–4 in catalog order. Positions 5–1,000 are empty.

### Unlock insertion

When a valid locked card becomes unlocked:

1. Reject the request if the card ID is unknown or already unlocked.
2. Reject the request if all 1,000 library positions are occupied.
3. Insert the new card at library position 1.
4. Shift all existing library contents forward one position while preserving order.
5. Drop the final empty value displaced from position 1,000.
6. Add the card to `unlocked_card_ids` and save.

The five-card main deck is unaffected. Newly unlocked cards therefore always appear at the top of `藏经阁`.

## Validation and Recovery

Loading validates these invariants:

- `main_deck` contains exactly five valid catalog IDs.
- Main-deck IDs are unlocked and unique.
- `library_slots` contains exactly 1,000 values.
- Every occupied library value is a valid, unlocked catalog ID.
- Occupied library positions form one contiguous prefix followed only by empty positions.
- A card appears at most once across the main deck and library.
- Every unlocked card appears in exactly one of those locations.

Recoverable problems are repaired in this order:

1. Remove unknown and locked card IDs from placements.
2. Remove duplicates, preferring the main-deck occurrence and then the first library occurrence.
3. Preserve remaining valid main-deck positions and compact the valid library cards toward position 1 without changing their relative order.
4. Fill missing main-deck positions from valid owned cards, then from valid defaults.
5. Insert unlocked but unplaced cards at the top of the library.
6. Pad or trim the library representation to exactly 1,000 positions without discarding an occupied position.

If the profile cannot be repaired while satisfying all invariants, the store returns the default profile and logs a clear warning instead of preventing the game from booting.

Saving uses a temporary file followed by replacement so an interrupted write cannot corrupt the last valid profile. If a swap cannot be saved, the controller restores the pre-swap profile and displays a brief save-failure message.

## Duel Integration

`DuelDecks.get_player_card_ids()` reads the validated saved main deck and falls back to its existing constants if no valid profile exists. The order of the five saved IDs is preserved.

The player's side deck, opponent decks, AI, simulation, turn rules, scoring, and card abilities do not change.

## Testing

### Profile tests

- Missing save creates the expected defaults.
- Initial profile contains five deck cards, four library cards, and 996 empty slots.
- `CangSongYingKe1` starts locked.
- Valid swaps preserve uniqueness and exact source placement.
- Save and reload preserve deck order and all library positions.
- A new unlock enters position 1 and shifts existing library contents in order.
- Duplicate unlock and unknown-ID unlock requests have no effect.
- A full library rejects another unlock without data loss.
- Unknown IDs, duplicates, malformed lengths, and catalog changes are repaired.
- Gaps between occupied library positions are compacted without reordering cards.
- Unrecoverable data falls back safely.
- Failed saves roll back swaps.

### Virtual-grid tests

- Exactly five logical columns are used.
- Three full rows are visible at the reference 9:16 layout.
- The visible controls map correctly at the top, middle, and final row.
- Slot 1,000 is reachable.
- Recycled controls clear old card artwork, names, power values, ki beads, and input state when rebound to empty slots.
- Scroll offset remains stable after swap and inspection.

### Interaction tests

- Revealed card taps inspect.
- Face-down and empty slots do not inspect.
- Vertical gestures scroll without tapping or dragging.
- Releasing before the hold threshold inspects an occupied card.
- Holding through the threshold arms drag and shows the lift cue.
- Moving before the hold threshold scrolls instead of dragging.
- Library cards drag only to main-deck slots.
- Valid drops exchange cards and save.
- Cancelled and invalid drops preserve data.
- Testing mode reveals and enables inspection of opponent cards.
- Normal mode keeps the opponent hand hidden.
- The back icon emits `back_requested` and performs no navigation.

### Integration and visual tests

- The duel starts with the saved main deck.
- Side-deck contents remain unchanged.
- The deck builder contains no score panels and starts no AI.
- The scene remains at the established 9:16 proportions.
- Tall Android displays and wide PC displays use the existing decorative extensions without stretching the central UI.
- Android touch scrolling remains smooth across all 200 logical rows.

## Non-Goals

This feature does not include:

- A world, stage-select, or navigation scene
- In-game toggling of testing mode
- Unlock reward presentation
- Sorting, filtering, searching, or manual empty-slot rearrangement
- Dragging main-deck cards into arbitrary empty library slots
- Card quantities or duplicate owned copies
- Side-deck editing
- Deck legality rules beyond five unique unlocked cards
- AI, board simulation, card effects, or score changes

## Acceptance Criteria

The feature is accepted when the standalone deck-building scene:

1. Matches the duel's established chrome and fixed-canvas behavior.
2. Shows the upcoming enemy hand with correct privacy behavior.
3. Displays `藏经阁` with three visible five-slot rows and a smooth 1,000-slot vertical scroll.
4. Shows four initial library cards followed by empty slots.
5. Exchanges an occupied library card with any main-deck position through the
   approved hold-then-drag interaction.
6. Persists and reloads the exact resulting deck and library arrangement.
7. Opens the existing inspector for every revealed occupied card.
8. Emits `back_requested` without navigating.
9. Causes the duel to use the saved main deck.
10. Passes profile, interaction, virtualization, integration, and Android-oriented visual checks.
