# Victory Continuous Drop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the victory emblem centered while it smashes toward the screen depth from `2.0` to `0.92` scale and reaches impact at `0.70` seconds.

**Architecture:** Keep the existing four-second presentation timeline for opacity, light, sound, settle, hold, and fade. Drive emblem/fallback scale with one linear tween spanning `entry_duration + impact_duration`; keep both nodes at their final screen-space positions throughout.

**Latest playtest tuning:** Screen-space descent is removed. The emblem remains centered and scales linearly from `2.0` to `0.92` over `0.70` seconds, producing a depth smash before rebounding to `1.0` at `1.10` seconds. This supersedes the positional-trajectory implementation notes retained below.

**Tech Stack:** Godot/Summer Engine 4.7, typed GDScript, SceneTree integration tests.

**Spec:** `docs/superpowers/specs/2026-09-19-single-duel-victory-vfx-design.md`

**Follow-up tuning:** After hands-on playtesting, the `0.80`-second impact still felt slow. Impact now occurs at `0.70` seconds and the longer rebound still settles at `1.10` seconds.

## Global Constraints

- `0.00–0.25` seconds combines fade-in and continuous depth-smash scaling.
- `0.25–0.70` seconds continues the same linear scale trajectory without a restart.
- Initial emblem and fallback scale is exactly `2.0`; impact scale remains `0.92`.
- Impact remains at `0.70` seconds, settle at `1.10`, fade start at `3.00`, and completion at `4.00`.
- Emblem and fallback positions remain at their final centered coordinates throughout the presentation.
- Victory fallback text must use the same position and scale trajectory as the image.
- Cancel, immediate settle, natural completion, and scene exit must stop both tweens and leave no delayed callbacks.

## Review Focus

- At the start, at `0.25` seconds, and at `0.70` seconds, the scale follows one linear `2.0 → 0.92` trajectory.
- At zero elapsed time, the emblem is centered and begins at `2.0` scale; the test checks both curve data and live node state.
- When immediate settle or cancellation occurs before impact, the independent smash tween cannot overwrite the settled/reset scale afterward; the outcome test checks the live emblem after forced settle.
- When the texture is unavailable and `FallbackGlyph` is used, its position and scale remain identical to `VictoryEmblem`; the same setter updates both nodes and the test compares their relative offsets.

---

### Task 1: Replace the split drop with one continuous accelerating trajectory

**Files:**
- Modify: `tests/test_duel_outcome.gd:40-75`
- Modify: `scripts/victory_vfx.gd:6-220`

**Interfaces:**
- Consumes: existing `entry_duration`, `impact_duration`, `_emblem_rest_position`, `_fallback_rest_position`, `play()`, `cancel()`, and immediate-completion paths.
- Produces: `debug_get_drop_offset_y(elapsed_seconds: float) -> float` and `debug_get_drop_speed_y(elapsed_seconds: float) -> float` for deterministic trajectory assertions; runtime motion remains internal.

- [x] **Step 1: Add failing trajectory and live-state assertions**

In `tests/test_duel_outcome.gd`, immediately after the existing timing assertions, add:

```gdscript
		var drop_duration: float = (
			float(victory_vfx.get("entry_duration"))
			+ float(victory_vfx.get("impact_duration"))
		)
		var boundary_time: float = float(victory_vfx.get("entry_duration"))
		var speed_before_boundary: float = float(
			victory_vfx.call("debug_get_drop_speed_y", boundary_time - 0.001)
		)
		var speed_after_boundary: float = float(
			victory_vfx.call("debug_get_drop_speed_y", boundary_time + 0.001)
		)
		var old_terminal_speed: float = 2.0 * 76.0 / 0.55
		_check(
			float(victory_vfx.call("debug_get_drop_speed_y", 0.0)) > 0.0,
			"Victory emblem starts descending while it fades in"
		)
		_check(
			float(victory_vfx.call("debug_get_drop_offset_y", boundary_time)) > -153.0
			and float(victory_vfx.call("debug_get_drop_offset_y", boundary_time)) < 0.0,
			"Victory emblem is already descending before the old phase boundary"
		)
		_check(
			absf(speed_after_boundary - speed_before_boundary) < 1.0,
			"Victory drop velocity stays continuous across 0.25 seconds"
		)
		_check(
			float(victory_vfx.call("debug_get_drop_speed_y", drop_duration))
			>= old_terminal_speed,
			"Victory drop keeps at least the former terminal impact speed"
		)
		_check(
			victory_emblem.scale.is_equal_approx(Vector2(1.50, 1.50)),
			"Victory emblem begins at the enlarged 1.50 scale"
		)
		var fallback_glyph := victory_vfx.get_node("FallbackGlyph") as Label
		_check(
			is_equal_approx(
				victory_emblem.position.y
				- (victory_vfx.get("_emblem_rest_position") as Vector2).y,
				fallback_glyph.position.y
				- (victory_vfx.get("_fallback_rest_position") as Vector2).y
			),
			"Fallback glyph begins with the same drop offset as the emblem"
		)
```

After `debug_settle_victory_vfx()` and one processed frame, add:

```gdscript
	var settled_emblem := victory_vfx.get_node("VictoryEmblem") as TextureRect
	var settled_emblem_position: Vector2 = settled_emblem.position
	for frame_index: int in range(3):
		await process_frame
	_check(
		settled_emblem.position.is_equal_approx(settled_emblem_position)
		and settled_emblem.scale.is_equal_approx(Vector2.ONE),
		"Forced settle prevents the drop tween from restoring an in-flight visual"
	)
```

- [x] **Step 2: Run the focused test and confirm the new assertions fail**

Run the `test_duel_outcome.gd` SceneTree test with the project engine and Dummy audio.

Expected: FAIL because `debug_get_drop_offset_y()` and `debug_get_drop_speed_y()` do not exist and the live initial scale is still `1.35`.

- [x] **Step 3: Add the continuous trajectory and independent motion tween**

In `scripts/victory_vfx.gd`, add these constants and state:

```gdscript
const DROP_START_OFFSET_Y: float = -153.0
const DROP_INITIAL_SLOPE: float = 0.55
const DROP_INITIAL_SCALE: float = 1.50

var _drop_animation: Tween = null
```

Add the pure curve helpers and runtime setter:

```gdscript
func _drop_duration() -> float:
	return maxf(entry_duration + impact_duration, 0.001)


func _drop_curve_progress(normalized_time: float) -> float:
	var time: float = clampf(normalized_time, 0.0, 1.0)
	return (
		DROP_INITIAL_SLOPE * time
		+ (1.0 - DROP_INITIAL_SLOPE) * time * time
	)


func debug_get_drop_offset_y(elapsed_seconds: float) -> float:
	return lerpf(
		DROP_START_OFFSET_Y,
		0.0,
		_drop_curve_progress(elapsed_seconds / _drop_duration())
	)


func debug_get_drop_speed_y(elapsed_seconds: float) -> float:
	var time: float = clampf(elapsed_seconds / _drop_duration(), 0.0, 1.0)
	var curve_slope: float = (
		DROP_INITIAL_SLOPE
		+ 2.0 * (1.0 - DROP_INITIAL_SLOPE) * time
	)
	return -DROP_START_OFFSET_Y * curve_slope / _drop_duration()


func _set_drop_progress(progress: float) -> void:
	var offset := Vector2(0.0, lerpf(
		DROP_START_OFFSET_Y,
		0.0,
		_drop_curve_progress(progress)
	))
	if victory_emblem != null:
		victory_emblem.position = _emblem_rest_position + offset
	if fallback_glyph != null:
		fallback_glyph.position = _fallback_rest_position + offset


func _start_drop_motion() -> void:
	_set_drop_progress(0.0)
	_drop_animation = create_tween()
	_drop_animation.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	_drop_animation.tween_method(_set_drop_progress, 0.0, 1.0, _drop_duration())
```

Call `_start_drop_motion()` in `play()` after the overlay becomes visible and before constructing the existing presentation tween. Remove both emblem/fallback position tweens from the `0.00–0.25` group and the `0.25–0.80` group. Make the emblem scale tween the sequential anchor of the second group:

```gdscript
	_animation.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_animation.tween_property(victory_emblem, "scale", Vector2(0.92, 0.92), impact_duration)
```

Update `_reset_visuals()`:

```gdscript
	victory_emblem.position = _emblem_rest_position + Vector2(0.0, DROP_START_OFFSET_Y)
	victory_emblem.scale = Vector2.ONE * DROP_INITIAL_SCALE
	fallback_glyph.position = _fallback_rest_position + Vector2(0.0, DROP_START_OFFSET_Y)
	fallback_glyph.scale = Vector2.ONE * DROP_INITIAL_SCALE
```

Extend `_kill_animation()` so every completion and cancellation path stops both timelines:

```gdscript
	if _drop_animation != null and _drop_animation.is_valid():
		_drop_animation.kill()
	_drop_animation = null
```

- [x] **Step 4: Re-run script validation and focused outcome tests**

Run Summer script validation for `res://scripts/victory_vfx.gd` and `res://tests/test_duel_outcome.gd`, then run `test_duel_outcome.gd` with Dummy audio.

Expected: both scripts report zero errors; `DUEL_OUTCOME_TESTS_PASSED` includes the new trajectory checks.

- [x] **Step 5: Perform deterministic frame-by-frame visual verification**

Launch `res://scenes/duel.tscn` as a deterministic offscreen instance at fixed 60 FPS with Dummy audio. Trigger `VictoryVfx.play()` directly and capture/probe at frames corresponding to approximately `0.00`, `0.25`, `0.50`, `0.80`, and `1.10` seconds.

Expected:

- At frame 0 the emblem is transparent, at `1.50` scale, and offset `-153` logical pixels.
- At 0.25 seconds it is partially visible and has moved downward by about `33` logical pixels.
- Position keeps advancing between adjacent samples around 0.25 seconds; no held frame or upward movement appears.
- At 0.80 seconds it reaches the rest position at `0.92` scale and the impact light peaks.
- At 1.10 seconds it has rebounded to normal scale and terminal controls can appear.

- [x] **Step 6: Run regression verification**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
```

Expected: all 84 suites pass. Then run `git diff --check` and Summer diagnostics; no new errors or warnings may originate from the modified files.

- [x] **Step 7: Commit the implementation**

```powershell
git add -- scripts/victory_vfx.gd tests/test_duel_outcome.gd docs/superpowers/plans/2026-09-20-victory-continuous-drop.md
git commit -m "Smooth victory emblem drop"
```
