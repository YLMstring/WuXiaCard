# Sect Selection Preview Card Backs Design

## Goal

Make the two preview hands in the sect-selection scene feel intentional before
and after a sect is selected by filling every slot without a revealed preview
card with the game's normal face-down card back.

## Scope

- Apply only to the upper and lower five-slot preview hands in the
  sect-selection scene.
- Leave the central sect library, deck-building scene, and duel scene
  unchanged.
- Reuse the existing `CardView` face-down presentation instead of introducing
  a second card-back renderer or new artwork.

## Behavior

- When the sect-selection scene first opens, both preview hands show five
  face-down card backs.
- Selecting, tapping, or holding a sect continues to populate the upper hand
  with that sect's highest-tier cards and the lower hand with its lowest-tier
  cards.
- Revealed preview cards replace backs from left to right.
- If a sect supplies fewer than five preview cards, every remaining slot stays
  filled with a face-down card back.
- A placeholder back is decorative only. It cannot be inspected, held, or
  dragged and contains no catalog card identity or metadata.
- Testing mode does not reveal placeholder backs because they are not real
  cards.

## Implementation Shape

Keep preview-hand population owned by `SectSelectionController`. During each
refresh, instantiate the existing `CardView` scene in all five slots. Configure
real preview entries normally and face them up. Configure missing entries as
data-free, face-down placeholders using a focused helper so the controller
does not invent a parallel card-back style.

The existing hand-slot panels remain as layout containers underneath the card
views. No generalized empty-slot mode is added to `DeckSelectionShell`, because
the requested behavior is specific to sect previews.

## Verification

Automated integration coverage will verify:

- ten backs are present before any sect is selected;
- selecting a sect replaces the correct number of backs in both hands;
- unused slots remain face down;
- placeholder backs do not emit inspection requests;
- normal revealed preview cards remain inspectable;
- deck-building and duel hand behavior is unaffected.

Runtime verification will boot the main scene at portrait proportions and
visually check the initial and selected-sect hand states.
