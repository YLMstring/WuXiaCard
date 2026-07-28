# Sect Selection Scene Design

## Purpose

Add a sect-selection scene before deck building. The player can preview every
sect, inspect sect and card information, and choose an unlocked sect. Choosing
a sect unlocks its tier-1 cards and proceeds to the existing deck-building
scene.

The new scene must look exactly like the deck-building scene except for the
behavioral and content differences defined below.

## Visual Structure

The sect-selection scene reuses the deck-builder's existing presentation:

- the decorative extension, top wash, opponent header, and return icon;
- the upper and lower five-slot hands;
- the central scroll, including the title `藏经阁`;
- the library grid's four-column layout, spacing, empty slots, and swipe
  scrolling;
- the card inspector, status line, and drag layer.

The scene does not display the `抢占先机` or `后发制人` controls. It does not add
replacement controls in those locations.

The scroll displays all entries from `SectCatalog` in catalog order. Sect
entries reuse the normal card presentation because sect definitions deliberately
share the card metadata shape. Power numbers and ki beads are hidden for sect
entries. An unlocked sect uses the normal blue card treatment; a locked sect
uses the red card treatment.

Both preview hands contain five visually empty slots when the scene opens.

## Architecture and Reuse

The sect-selection scene has its own controller. Its interaction rules and
navigation are separate from the deck-builder controller.

Existing focused components are reused:

- The virtualized library grid accepts prepared display definitions rather
  than assuming that every entry must be constructed from `CardCatalog`.
- `CardView` gains a general display option for hiding power numbers, analogous
  to its existing ki-badge display option.
- Existing hand-slot, inspector, drag-proxy, decorative chrome, and responsive
  portrait layout behavior remain shared.

This avoids copying the deck-builder while also avoiding a large shared base
controller whose two consumers have materially different behavior.

## Sect Preview and Inspection

Tapping any sect performs these actions in order:

1. Select the sect and update both preview hands.
2. Open that sect in the existing inspector.

Holding any sect selects it and updates both preview hands. If the sect is
unlocked, continuing the hold may begin a drag. If it is locked, no drag begins.
A hold that becomes a drag must not also open the inspector.

The upper hand shows up to five cards belonging to the selected sect, ordered
from highest tier to lowest tier. The lower hand shows up to five cards ordered
from lowest tier to highest tier. Equal-tier cards retain `CardCatalog` order.
If fewer than five cards exist, the remaining hand positions stay empty.

Both preview hands are always face-up, regardless of testing mode. Preview
cards cannot be dragged. Tapping a preview card opens its normal card
inspection view.

The inspector keeps its existing tap-anywhere-to-close behavior. Closing it
returns to the sect scroll without clearing the selected sect or its preview
hands.

## Dragging and Selection

Only unlocked sects can create a drag proxy. While an unlocked sect is being
dragged, its source position in the scroll looks empty until the drag ends.

The entire lower five-slot hand is one valid drop region; the player does not
need to target a particular slot. Releasing elsewhere cancels the drag and
restores the source entry without changing profile data.

Holding a locked sect still updates the preview hands, but does not create a
drag proxy. The status line reports that the sect has not been unlocked.

On a valid lower-hand drop:

1. Find every tier-1 card belonging to the selected sect in `CardCatalog`
   order.
2. Add cards that are not already unlocked.
3. Insert the newly unlocked batch at the top of the deck-builder library while
   preserving catalog order.
4. Save the profile once.
5. Enter the deck-building scene.

The operation is idempotent: selecting the same sect again creates no duplicate
unlocks or library entries. It does not modify the current main deck. A valid
sect with no tier-1 cards is still selectable and proceeds without adding
cards.

## Profile Data and Migration

The existing deck profile gains `unlocked_sect_ids`.

- A new profile contains only `xuanyue_jianzong`.
- Loading an older profile adds `xuanyue_jianzong` but does not implicitly
  unlock any cards.
- Profile repair removes unknown sect IDs and ensures that
  `xuanyue_jianzong` remains unlocked.
- Card unlocking for a chosen sect is performed by a batch profile-store
  operation so ordering, deduplication, and the single save are deterministic.

If saving fails, the scene does not transition. It restores an interactive
state and reports the failure in the existing status line.

## Navigation

The main flow becomes:

`Game start -> Sect selection -> Deck building -> Duel`

- The application starts on the sect-selection scene.
- A successful sect selection opens deck building.
- Choosing first or second in deck building opens the duel as it does now.
- Returning from a duel opens deck building.
- The return icons in sect selection and deck building emit `back_requested`
  for a future main-menu controller.
- Until that main menu exists, those two back requests cause no scene
  transition.

## Empty and Invalid Data Behavior

- A sect with fewer than five cards leaves unused preview positions empty.
- A sect with no cards leaves both preview hands empty.
- Unknown or removed sect IDs in saved profiles are discarded during repair.
- Catalog validation remains the authority for malformed sect definitions.
- Invalid or stale drag context cancels safely without changing the profile.

## Verification

Automated coverage will verify:

- new-profile defaults and old-profile migration;
- removal of unknown sect IDs and preservation of the default unlocked sect;
- highest- and lowest-tier preview sorting, catalog-order tie breaking, and
  five-slot padding;
- tap-to-preview-and-inspect behavior;
- hold behavior for locked and unlocked sects;
- prevention of inspector activation when a hold becomes a drag;
- drop detection across the full lower hand;
- batch tier-1 unlocking, deduplication, order preservation, and one-save
  behavior;
- cancellation and save-failure behavior;
- startup and navigation among sect selection, deck building, and duel.

A portrait-mode playtest will exercise tapping sects, inspecting sects and
preview cards, holding locked sects, dragging an unlocked sect, canceling a
drag, completing a selection, and returning between scenes.
