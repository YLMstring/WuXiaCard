# Duel Top-Bar Redesign Implementation Plan

## Objective

Implement the approved A1 header: a restrained charcoal-and-gold continuous strip with a cinnabar enemy seal, warm opponent name, inset exit button, and a visible 12–18 logical-pixel gap above the existing opponent card backs. Preserve all duel behavior and existing card-back presentation.

## Task 1: Add failing integration coverage

**File:** `tests/test_duel_integration.gd`

1. Extend the layout checks to resolve `TopWash`, `TopBar/EnemySeal`, `TopBar/OpponentName`, and `TopBar/ExitButton`.
2. Assert that seal, name, and exit appear in that child order.
3. Assert the seal is square and noninteractive, the name expands horizontally, and long-name overflow uses ellipsis.
4. Assert the exit button remains labeled, accepts focus, and has at least 44 logical pixels of touch height.
5. Inspect the runtime `panel` StyleBox on `TopWash` and assert it is materially darker than the opponent card-back color and has an antique-gold lower border.
6. At both 540×960 and 405×720, call the responsive layout and assert:
   - the header spans the viewport width;
   - top-bar content remains inside the same horizontal margins as the hands;
   - the visible distance from header bottom to opponent-hand top is 12–18 logical pixels;
   - header and hand never overlap;
   - existing board-to-hand equal-spacing assertions still pass.
7. Run the integration suite and confirm the new assertions fail against the old red wash and missing seal before implementation.

## Task 2: Build the native Godot header structure

**File:** `scenes/duel.tscn`

1. Change `TopWash` from a flat red `ColorRect` to a mouse-ignoring `Panel`.
2. Add a full-rect mouse-ignoring `TextureRect` child with a horizontal `GradientTexture2D`. Its transparent outer stops and muted warm-brown center stop provide subtle variation over the dark Panel without a raster asset.
3. Keep the existing full-width top anchoring; responsive height remains controller-owned.
4. Add `TopBar/EnemySeal` as a centered, mouse-ignoring `PanelContainer` with a child Label containing `敌`.
5. Preserve the existing `TopBar/OpponentName` and `TopBar/ExitButton` node paths.
6. Give the seal a fixed square minimum size and shrink-center flags, the name expand/fill flags, and the exit button a fixed minimum of at least 44 logical pixels high.
7. Enable button focus so the approved focus style and keyboard operation are real rather than decorative.

## Task 3: Add focused header styling

**File:** `scripts/duel_controller.gd`

1. Add typed onready references for `TopWash`, the gradient tint, and `EnemySeal`.
2. Split header styling into `_style_duel_header()` and call it from `_style_static_ui()`.
3. Create a `StyleBoxFlat` for the header:
   - charcoal-brown base;
   - one-pixel antique-gold bottom border;
   - restrained downward shadow;
   - no rounded outer silhouette.
4. Style the enemy seal with cinnabar background, muted-gold border, pale-gold text, a small radius, and minimal shadow.
5. Reduce opponent-name typography to approximately 22 logical pixels, use warm ivory, vertically center it, and set ellipsis trimming.
6. Create distinct normal, hover, pressed, and focus StyleBoxFlat resources for the exit button. Keep all states dark and restrained while making interaction visible.
7. Keep the existing `pressed` connection and `_on_exit_pressed()` unchanged.

## Task 4: Make header/hand spacing responsive

**File:** `scripts/duel_controller.gd`

1. In `_layout_duel()`, compute:
   - `header_height = clampf(size.y * 0.0625, 56.0, 62.0)`;
   - `header_gap = clampf(size.y * 0.0146, 12.0, 18.0)`;
   - fixed top-bar content height of at least 44 logical pixels.
2. Size the full-width `TopWash` to `header_height`.
3. Vertically center `TopBar` inside the header and keep its horizontal bounds aligned with both hands.
4. Set `opponent_top = header_height + header_gap`; remove the unrelated `maxf(..., 72.0)` positioning rule.
5. Continue deriving board placement from `opponent_bottom` and `player_top` so the existing equal-gap invariant remains authoritative.
6. Confirm the gradient tint tracks the resized header automatically through full-rect anchors.

## Task 5: Verify behavior and presentation

**Files:** `tests/test_duel_integration.gd`, project runtime

1. Run the integration suite and confirm the new header/layout assertions pass.
2. Run `powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1`.
3. Run `git diff --check` and review the complete scene/script/test diff.
4. Launch the duel at 540×960 and 405×720.
5. Confirm:
   - the old translucent red wash is gone;
   - the header is darker and quieter than the unchanged card backs;
   - the 14-pixel reference gap reads as visible background space;
   - long names cannot collide with the fixed exit control;
   - the exit button remains clear and functional;
   - mouse/touch card interaction below the header is unaffected.
6. Commit the implementation separately from the already committed design and plan documents.
