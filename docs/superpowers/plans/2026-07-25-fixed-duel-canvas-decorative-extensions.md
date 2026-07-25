# Fixed Duel Canvas with Decorative Extensions — Implementation Plan

Date: 2026-07-25

Design specification:
`docs/superpowers/specs/2026-07-25-fixed-duel-canvas-decorative-extensions-design.md`

## Outcome

Keep Godot's expanded full-screen viewport, fit all duel interaction into a
centered 9:16 `DuelCanvas`, and procedurally draw the approved decorative regions:

- Tall viewport: lacquer ornament above, large rounded ink-wash ridges below.
- Wide viewport: mirrored ink diffusion and mist at the sides, without mountains.
- Exact 9:16 viewport: no exposed extension.

No duel rules, AI, card data, effects, or turn behavior change.

## Files

Create:

- `scripts/duel_backdrop.gd`
- `tests/test_duel_backdrop.gd`

Modify:

- `scenes/duel.tscn`
- `scripts/duel_controller.gd`
- `tests/test_duel_integration.gd`
- `tools/run_tests.ps1`

Do not modify:

- `project.godot` — `canvas_items` plus `expand` is already correct.
- Card, simulator, search, rules, catalog, deck, or effect scripts.

## Task 1 — Specify the fitted-canvas geometry with failing tests

### Test changes

Create `tests/test_duel_backdrop.gd` as a small headless `SceneTree` suite. Preload
`res://scripts/duel_backdrop.gd` and test the pure geometry API before the script
exists:

```gdscript
var exact := Backdrop.fit_duel_rect(Vector2(540.0, 960.0))
_check(exact.is_equal_approx(Rect2(0.0, 0.0, 540.0, 960.0)), ...)

var tall := Backdrop.fit_duel_rect(Vector2(405.0, 900.0))
_check(tall.is_equal_approx(Rect2(0.0, 90.0, 405.0, 720.0)), ...)

var wide := Backdrop.fit_duel_rect(Vector2(1280.0, 839.0))
_check(is_equal_approx(wide.size.y, 839.0), ...)
_check(is_equal_approx(wide.size.x / wide.size.y, 9.0 / 16.0), ...)
_check(wide.get_center().is_equal_approx(Vector2(640.0, 419.5)), ...)
```

Define and test three presentation modes:

- `MODE_EXACT`
- `MODE_TALL`
- `MODE_WIDE`

Test the approved visual-feature flags returned by a pure description method:

- Tall: top lacquer enabled, bottom ridges enabled, side wash disabled.
- Wide: side wash enabled, top lacquer and bottom ridges disabled.
- Exact: all extension decoration disabled.

Add `test_duel_backdrop.gd` to the suite list in `tools/run_tests.ps1`.

### Red verification

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1
```

Expected: only `test_duel_backdrop.gd` fails because the backdrop script/API is
not implemented. Preserve the output as the red side of the regression test.

### Commit

Do not commit while the suite is red. Continue directly to Task 2.

## Task 2 — Implement the isolated backdrop geometry and procedural drawing

### Script

Create `scripts/duel_backdrop.gd`:

```gdscript
class_name DuelBackdrop
extends Control

const DUEL_ASPECT: float = 9.0 / 16.0

enum LayoutMode {
    MODE_EXACT,
    MODE_TALL,
    MODE_WIDE,
}
```

Responsibilities:

1. `static func fit_duel_rect(viewport_size: Vector2) -> Rect2`
   - Return an empty rectangle for non-positive dimensions.
   - Compare viewport aspect to `DUEL_ASPECT` using a small epsilon.
   - Fit by width for tall viewports.
   - Fit by height for wide viewports.
   - Center the result on both axes.

2. `static func classify_layout(viewport_size: Vector2) -> LayoutMode`
   - Return exact inside the epsilon.
   - Return tall below the 9:16 aspect.
   - Return wide above it.

3. `static func describe_decoration(viewport_size: Vector2) -> Dictionary`
   - Return explicit booleans used by tests and drawing:
     `top_lacquer`, `bottom_ridges`, `side_wash`.

4. `func configure(duel_rect: Rect2) -> void`
   - Store the fitted rectangle.
   - Recalculate the presentation mode from `size`.
   - Call `queue_redraw()`.

5. `_draw()`
   - Fill the full control with the existing parchment base color.
   - Tall mode:
     - Draw the top extension as dark brown-cinnabar.
     - Draw two thin antique-gold horizontal rules.
     - Draw sparse centered diamond-and-dot ornaments.
     - Draw the bottom extension as a parchment-to-muted-sage wash.
     - Draw two large rounded ridge polygons sampled from smooth quadratic or
       cubic curves; avoid triangular peaks.
     - Overlay low-opacity fog ellipses/soft circles.
   - Wide mode:
     - Draw mirrored parchment-to-sage side washes.
     - Draw mirrored translucent ink and fog ellipses.
     - Do not invoke the ridge-drawing helper.
   - Exact mode:
     - Draw only the base parchment, which will be covered by `DuelCanvas`.

Use named color constants matching the approved mockups. Keep all drawing helpers
private and deterministic. Set `mouse_filter = MOUSE_FILTER_IGNORE` in `_ready()`
as defense in depth in addition to the scene property.

### Green verification

Run the focused suite:

```powershell
& "$env:LOCALAPPDATA\SummerEngine\current\Summer.exe" `
  --headless --path C:\mygame --script res://tests/test_duel_backdrop.gd
```

Expected marker:

```text
DUEL_BACKDROP_TESTS_PASSED
```

### Commit

Commit:

```text
feat: add responsive duel backdrop geometry
```

Files in this commit:

- `scripts/duel_backdrop.gd`
- `tests/test_duel_backdrop.gd`
- `tools/run_tests.ps1`

## Task 3 — Add the fixed 9:16 scene boundary

### Integration test first

Extend `tests/test_duel_integration.gd` with
`_check_duel_canvas_structure(duel)` and call it immediately after the initial
layout checks.

Verify:

- `DecorBackdrop` exists, fills the root, and ignores mouse input.
- `DuelCanvas` exists.
- `DuelCanvas` is drawn after `DecorBackdrop`.
- `TopWash`, `BoardCenter`, both hands, score overlay, status, inspector, drag
  layer, and extra-turn VFX are descendants of `DuelCanvas`.
- The four audio players remain children of `Duel`.

Update existing node lookups in the test from paths such as:

```gdscript
duel.get_node("PlayerHand")
```

to:

```gdscript
duel.get_node("DuelCanvas/PlayerHand")
```

Use a local helper such as `_canvas_node(duel, path)` to avoid repeating the
prefix throughout the large integration test.

Run only the integration suite and confirm it fails for the missing scene
boundary before editing the scene.

### Scene changes

Modify `scenes/duel.tscn`:

1. Add the backdrop script external resource.
2. Replace the current root-level `Background` with `DecorBackdrop`:
   - Full-rect anchors.
   - `mouse_filter = MOUSE_FILTER_IGNORE`.
   - Backdrop script attached.
3. Add `DuelCanvas` as a root child after the backdrop.
4. Reparent these existing nodes under `DuelCanvas` without changing their
   internal child order:
   - `TopWash`
   - `BoardCenter`
   - `TopBar`
   - `OpponentHand`
   - `PlayerHand`
   - `ScoreOverlay`
   - `TurnStatus`
   - `ExtraTurnVfx`
   - `DragLayer`
   - `CardInspector`
5. Leave the four `AudioStreamPlayer` nodes under `Duel`.

Set `DuelCanvas` to clip its visual children only if runtime inspection shows
effects leaking into the decorative area. Default to no clipping so existing
drag and convergence VFX remain intact at the canvas edge.

### Controller path changes

In `scripts/duel_controller.gd`, add typed references:

```gdscript
@onready var decor_backdrop: DuelBackdrop = $DecorBackdrop
@onready var duel_canvas: Control = $DuelCanvas
```

Prefix all visual node paths with `$DuelCanvas/`. Keep audio paths rooted at
`$PlacementAudio`, `$CaptureAudio`, `$RemovalAudio`, and `$MovementAudio`.

Do not change game-state initialization, signal behavior, AI search, or card
construction.

After the scene and path changes compile, continue directly to Task 4. The
integration suite is expected to remain red until the canvas geometry drives the
layout, so do not commit this intermediate state.

## Task 4 — Drive layout from the fitted canvas

### Controller layout

Refactor `_layout_duel()` in `scripts/duel_controller.gd`:

1. Guard on the root viewport size as today.
2. Compute:

```gdscript
var duel_rect: Rect2 = DuelBackdrop.fit_duel_rect(size)
```

3. Assign:

```gdscript
duel_canvas.position = duel_rect.position
duel_canvas.size = duel_rect.size
decor_backdrop.configure(duel_rect)
```

4. Store `var canvas_size: Vector2 = duel_canvas.size`.
5. Replace every layout calculation based on root `size` with `canvas_size`.
6. Keep all child positions local to `DuelCanvas`; do not add `duel_rect.position`
   to hand, board, header, score, or status coordinates.
7. Preserve the approved internal formulas:
   - 3% horizontal margin with a 12-pixel minimum.
   - Five fixed hand slots.
   - 12–18 pixel header-to-opponent-hand gap.
   - Equal board spacing between both hands.
   - Status below the player hand.

Update `_get_board_rect()` to return a rectangle in `DuelCanvas` local
coordinates:

```gdscript
return Rect2(
    board_grid.global_position - duel_canvas.global_position,
    board_grid.size
)
```

This keeps `CardInspector`, now also under `DuelCanvas`, aligned with the board.

### Geometry regression checks

Add `_check_fixed_duel_canvas_geometry(duel)` to
`tests/test_duel_integration.gd`. At each target size `540×960`, `405×900`, and
`1280×839`, verify:

- `DuelCanvas.size.x / DuelCanvas.size.y == 9.0 / 16.0`.
- `DuelCanvas.get_rect().get_center()` matches the root center.
- Exact mode fills the root.
- Tall mode leaves only top/bottom extension space.
- Wide mode leaves only left/right extension space.
- The backdrop reports the expected exact, tall, or wide mode.

### Input regression checks

Extend the existing production drag-path tests:

- Resize to `405×900`, perform a real player drag using global coordinates, and
  verify the intended board cell receives the card.
- Resize to `1280×839`, repeat the drag check.
- Verify a point inside an extension region resolves to no board cell and cannot
  produce a legal target.
- Open the card inspector in tall mode and verify its parchment rectangle equals
  the board rectangle in canvas-local coordinates.
- Verify a simple tap in the extension still closes the inspector through its
  existing global `_input` behavior.

Global pointer logic in `card_view.gd` and global cell hit-testing in
`duel_controller.gd` should continue to work after reparenting; do not convert
them to local coordinates unless a failing regression test proves it necessary.

### Verification

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1
```

Expected: all suites pass, including the new backdrop suite and expanded
integration suite.

### Commit

Commit:

```text
feat: preserve portrait duel across aspect ratios
```

Files:

- `scenes/duel.tscn`
- `scripts/duel_controller.gd`
- `tests/test_duel_integration.gd`

## Task 5 — Visual verification and restrained tuning

### Tall portrait

Run or preview the duel at `405×900`.

Confirm visually:

- The duel is exactly centered and retains its previous proportions.
- Lacquer decoration occupies only the top extension.
- Antique-gold lines and ornaments are visible but quieter than the header.
- Bottom mountains use the large rounded A2 profile.
- Mist softens the ridges.
- No black pixels remain in the drawable viewport.

### Wide PC

Run the game in Summer Engine's wide game panel or preview at approximately
`1280×839`.

Confirm visually:

- Cards are portrait rather than horizontally stretched.
- The board and both hands retain their 9:16 composition.
- Side gutters are mirrored in intensity and placement.
- Side gutters contain ink diffusion and mist only.
- No mountain silhouettes or rotated lacquer motifs appear at the sides.

### Runtime diagnostics

Before play:

```text
summer_get_script_errors res://scripts/duel_backdrop.gd
summer_get_script_errors res://scripts/duel_controller.gd
summer_clear_console
summer_play res://main.tscn
```

After at least two rendered frames:

```text
summer_get_diagnostics
summer_get_debugger_errors
```

Treat the existing `INTEGER_DIVISION` warning in `scripts/duel_rules.gd:104` as
pre-existing. Investigate any new warning or error before proceeding.

Tune only color opacity, ornament spacing, ridge height, and mist opacity during
this task. Do not alter the approved canvas geometry or duel layout.

### Final verification

Run the complete runner again after all visual tuning:

```powershell
powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1
```

Review:

```powershell
git diff --check
git status --short
git diff --stat
```

Ensure only the files listed in this plan changed. Preserve any unrelated user
or editor changes and exclude them from the implementation commit.

### Final commit

If visual verification required tuning changes, commit them separately:

```text
style: tune decorative duel extensions
```

Do not push unless the user explicitly requests it.

## Android Handoff

Desktop and headless checks cannot prove cutout or navigation-area behavior. The
user must re-export and install a new Android build, then verify:

1. No black letterbox areas remain.
2. The lacquer top and rounded-ridge bottom are visible.
3. Interactive controls remain within the safe, centered 9:16 duel canvas.
4. Drag-and-drop still lands on the intended board cells.

If only the physical Android build fails, collect the device resolution, safe
insets, and a screenshot before changing the canvas geometry.
