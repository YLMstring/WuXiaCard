# Locked Sect Drag Pulse Design

## Purpose

Give immediate restrained feedback when the player holds a locked sect as if
trying to drag it, without making the feedback resemble an ability trigger.

## Behavior

- A short tap behaves exactly as it does now and does not pulse.
- When the hold threshold is reached for a locked sect, the sect remains
  selected, both preview hands update, and the existing locked notice appears.
- The visible card area expands to 103.5% and returns to its normal scale over
  0.18 seconds.
- The pulse changes no color, emits no ink or sound, and does not animate the
  sect-name label.
- The pulse occurs once per recognized hold attempt.
- A repeated hold cleanly restarts the feedback.
- Unlocked sects retain their existing hold lift and drag behavior.
- Scrolling, inspection, drop handling, and profile data are unchanged.

## Architecture

`DeckLibrarySlot` owns a reusable rejected-drag pulse on its `CardHost`. It
tracks the active tween, restarts it safely, and restores the host scale when
the slot is rebound or exits the tree.

`DeckLibraryGrid` exposes a focused operation that asks the currently bound
logical slot to play this feedback. `SectSelectionController` invokes that
operation from the existing locked branch of `hold_recognized`.

The controller does not tween child nodes directly, and the existing larger
`CardView.play_effect_pulse()` remains reserved for triggered abilities.

## Edge Cases

- If the logical slot is no longer visible, the grid request is a no-op.
- Rebinding a pooled slot cancels the tween so another sect cannot inherit it.
- Releasing the pointer may reset gesture state but does not leave the card at
  a non-unit scale.
- Locked entries never become drag-armed and never emit a selection request.

## Verification

Automated checks will verify that:

- a locked hold requests exactly one pulse;
- a second attempt restarts and increments the feedback once;
- a locked tap does not pulse;
- an unlocked hold does not use the rejected-drag pulse;
- rebinding restores `CardHost` to unit scale;
- existing locked status, preview, inspection, scrolling, and drag tests still
  pass.

A runtime playtest will confirm that the pulse is visible but restrained on the
portrait sect-selection screen.
