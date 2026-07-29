# Main Menu Ink Glyphs and Notice Placement Design

## Goal

Replace the four text glyph groups on the `九宫论剑` main menu with the four
matching transparent PNG assets in `res://inkpics/`, while preserving the
existing interaction behavior. Move confirmation and completion notices below
the illustrated stone grid.

## Visual Mapping

- `九宫论剑.png` replaces the visible title text.
- `踏入江湖.png` replaces the visible journey-button text.
- `闭关重修.png` replaces the visible run-reset-button text.
- `封剑归隐.png` replaces the visible full-reset-button text.

Each image keeps its original aspect ratio and transparent background. The
title and actions retain their current visual centers and responsive scaling.

## Interaction Structure

The existing `Button` nodes remain the interaction boundary. Their text becomes
empty and each receives a non-interactive `TextureRect` child. This preserves
the existing signals, touch areas, confirmation counters, hover behavior, and
pressed-scale feedback.

The title uses a `TextureRect` in place of its visible `Label` content. The
controller preloads and assigns all four textures at runtime so a Summer scene
reserialization cannot silently clear the image references.

## Notice Placement

The notice stays centered inside the square master artwork on every aspect
ratio. Its vertical position is approximately 83 percent down the square,
directly below the stone grid. It does not depend on the decorative bottom band,
because wide screens do not have one.

## Responsive Rules

- The complete square background remains centered and uncropped.
- Ink glyph images scale from the square side length.
- Button hit areas remain at least 54 logical pixels tall and do not overlap.
- The notice remains within the square on portrait, long-phone, and wide
  layouts.

## Verification

- Confirm all four controls use the matching non-null textures.
- Confirm the buttons emit the same signals and retain pressed feedback.
- Confirm the notice is below the grid at 540×960 and 1280×720 layouts.
- Run the focused main-menu test and inspect live portrait and wide frames.
