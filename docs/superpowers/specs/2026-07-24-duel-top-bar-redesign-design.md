# Duel Top-Bar Redesign

**Date:** 2026-07-24
**Status:** Approved design
**Selected direction:** A1 — restrained ink, continuous framed strip

## Goal

Replace the duel scene's flat translucent red top wash and visually generic name/exit controls with a compact, coherent wuxia header. The redesigned header must sit naturally above the existing red-and-gold opponent card backs, remain clear on portrait Android screens, and preserve all current duel behavior.

## Scope

This change affects only the top of `scenes/duel.tscn` and its responsive presentation in `scripts/duel_controller.gd`:

- top wash/header background;
- opponent seal and name;
- exit button;
- responsive spacing between the header and opponent hand;
- integration coverage for the new structure and layout.

It does not change opponent identity data, exit behavior, card backs, gameplay rules, AI, hands, board layout, score layout, or turn status.

## Visual Direction

The header uses a restrained ink palette:

- deep charcoal brown at the outer areas;
- a subtle muted warm-brown tint toward the center;
- a fine antique-gold lower border;
- a soft downward shadow;
- warm ivory opponent-name text;
- a small cinnabar enemy seal;
- a dark inset exit control with an antique-gold border and text.

The header must be materially darker than the opponent card backs. This creates separation while allowing the red-and-gold cards to remain the strongest color block.

The result should feel serious and martial, not glossy, ornate, bright, or modern. Decoration is limited to the seal, hairline border, and restrained shadow.

## Component Structure

Keep the existing top-level responsibilities and responsive container pattern:

```text
Duel
├── TopWash / header background
└── TopBar (HBoxContainer)
    ├── EnemySeal (PanelContainer)
    │   └── Label ("敌")
    ├── OpponentName (Label, expand/fill)
    └── ExitButton (Button)
```

`TopBar` remains an `HBoxContainer` so the seal and exit control keep fixed sizes while the name receives remaining width.

The existing `OpponentName` and `ExitButton` node paths remain stable. The current `pressed` signal connection and `_on_exit_pressed()` behavior remain unchanged.

## Header Background

The existing red `TopWash` becomes the dark continuous header strip. It spans the viewport width and visually contains the inset `TopBar`.

The implementation may use a styled Panel, a gradient-backed TextureRect, or an equivalent native Godot Control arrangement. It must not require a new raster asset. The chosen implementation must provide:

- dark charcoal-brown background;
- subtle warm center variation rather than a perfectly flat fill;
- one-pixel-equivalent antique-gold bottom edge;
- modest shadow below the strip;
- no large rounded outer silhouette;
- no bright red full-width wash.

## Enemy Seal and Name

The seal is a fixed square approximately 26 logical pixels per side at the reference viewport. It contains `敌` in a compact serif-like treatment, using:

- cinnabar background;
- muted gold border;
- warm pale-gold text;
- minimal shadow.

The opponent name follows the seal. At the 540×960 reference viewport it uses approximately 22 logical pixels, reduced from the current oversized presentation. It is vertically centered and uses warm ivory text.

The name label expands horizontally. If future opponent names exceed available width, it truncates with an ellipsis instead of colliding with or shrinking the exit control.

## Exit Button

The exit button remains explicitly labeled `返回`. It uses:

- dark inset background related to the header;
- antique-gold border;
- warm gold text;
- modest corner radius;
- at least 44 logical pixels of touch height;
- distinct but restrained hover, pressed, and focus states.

The control must look interactive without competing with the opponent name or card backs. No icon asset is required.

## Responsive Layout

At the 540×960 reference viewport, the header is compact—approximately 56–62 logical pixels high. The top bar retains responsive horizontal margins consistent with the hands.

`DuelController._layout_duel()` must derive the opponent hand's top position from the actual header bottom plus a small gap. It must not rely on an unrelated hard-coded minimum such as `72.0`.

Required layout behavior:

- header spans the viewport width;
- top-bar content respects left/right safe margins;
- exit touch height remains at least 44 logical pixels;
- seal stays square;
- name consumes flexible space and ellipsizes if necessary;
- opponent hand never overlaps the header;
- the hand/header gap remains visually compact;
- existing equal spacing between board and both hands remains intact;
- 540×960 and 405×720 layouts both remain valid.

This change does not introduce general safe-area/notch handling; it preserves the project's current safe-margin model.

## Styling Ownership

Static structure and default text remain in `scenes/duel.tscn`. Runtime-created style resources and responsive geometry remain in `scripts/duel_controller.gd`, following the existing pattern used for score panels.

Top-bar styling should be grouped into a focused helper or a clearly delimited part of `_style_static_ui()` so later palette tuning does not require searching unrelated duel logic.

No gameplay state enters the new styling code. The header reads only existing display text and viewport geometry.

## Interaction and Failure Behavior

- Exit behavior remains exactly as it is today.
- The header background and seal use `MOUSE_FILTER_IGNORE` so they cannot intercept card or button input.
- The name is noninteractive.
- The exit button remains keyboard/mouse/touch operable under current project conventions.
- Long names degrade through ellipsis, not overlap.
- At unusually narrow widths, the name yields space before the fixed exit target shrinks.

No new asynchronous behavior, animation, audio, or error channel is introduced.

## Tests

Extend `tests/test_duel_integration.gd` to verify:

- the seal, name, and exit controls exist in that order;
- the opponent name is nonempty and expandable;
- the exit label is nonempty and its touch height is at least 44 logical pixels;
- the header uses the approved dark presentation rather than the old red wash;
- top-bar content remains inside responsive horizontal bounds;
- the opponent hand begins below the header with a positive gap;
- existing board/hand equal-spacing invariants still pass;
- the 405×720 and 540×960 layouts do not overlap.

Run the complete test suite through `tools/run_tests.ps1`.

Because automated headless assertions do not prove visual quality, manually play the duel at both reference sizes and inspect:

- hierarchy between header and card backs;
- name legibility;
- exit-button clarity and touch size;
- spacing on a portrait Android-like window;
- no regression to drag/tap interaction.

## Acceptance Criteria

- The full-width translucent red wash is gone.
- The selected A1 dark continuous header is recognizable in the running duel.
- Enemy seal, opponent name, and exit control form one coherent composition.
- Existing card backs remain unchanged and visually stronger than the header.
- Opponent hand and header never overlap at supported portrait sizes.
- Exit behavior is unchanged.
- All automated suites pass.
- Manual portrait review matches the approved visual direction.

## Out of Scope

- opponent portraits or avatars;
- dynamic faction emblems;
- animated ink;
- custom fonts;
- top-bar audio;
- changing opponent names;
- redesigning player-hand, board, score, or status areas;
- general theme-system refactoring;
- Android notch/safe-area infrastructure.
