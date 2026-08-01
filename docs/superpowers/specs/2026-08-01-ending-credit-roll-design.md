# Compact Ending Credit Roll Design

## Goal

Confine the ending score and story to the clear painted sky beneath the title
and above the arena. Keep the score fixed, roll only the story upward, and
prevent the player from leaving until the complete story has been revealed.

## Layout

The production main-menu instance, background artwork, title, glow, and title
animation remain unchanged. Ending content uses a compact rectangle derived
from the main menu's fixed 9:16 safe rectangle, never from decorative overflow
on long or wide displays.

The content rectangle has three vertical parts:

1. breathing room below the title;
2. a fixed score row; and
3. a clipped story viewport below the score.

The title-to-score gap must remain visibly clear at every supported aspect
ratio. The score uses approximately 60 percent of its current font size. Story
text is slightly smaller than its current size, retains Chinese smart wrapping,
and uses comfortable line spacing. Neither label may render outside the compact
rectangle.

## Story Roll

The score never moves. The story starts at its natural first-line position in
the story viewport. If the rendered story is taller than the viewport, it moves
upward at a constant, inspector-tunable logical-pixel speed. Its maximum offset
is exactly:

```text
max(rendered_story_height - story_viewport_height, 0)
```

The roll stops when the final line is fully visible at the bottom of the
viewport. It never continues until the last line leaves the screen. If the
whole story already fits, the roll is complete immediately and no movement is
played.

Motion is driven by elapsed time rather than a fixed duration, so longer text
takes proportionally longer. A resize recomputes the available rectangle,
rendered height, and maximum offset, then clamps current progress to the new
valid range. No scrollbar, swipe handling, fading mask, or manual scrolling is
introduced.

## Input and Navigation

Tap-to-menu remains the only ending input, but it is locked while any story
text remains hidden below the viewport. Mouse and touch releases during the
roll are consumed and do nothing. Once the roll reaches its maximum offset—or
immediately when no overflow exists—tapping anywhere emits the existing
`return_requested` signal exactly once. Reaching the end never returns to the
main menu automatically.

## Component Changes

`ending.tscn` gains a dedicated clipping Control for the story. The fixed score
remains a sibling above that clipping Control. The story Label becomes a child
of the clip so its local vertical position can move without changing the score.

`ending_controller.gd` continues to own summary rendering and navigation. It
adds tunable scroll speed, measured story overflow, current offset, completion
state, and a small per-frame update used only while rolling. Existing sect and
enemy prose generation is unchanged.

No profile, score, progression, reward, main-flow, or achievement behavior
changes.

## Verification

Automated ending-scene coverage will verify:

- the compact rectangle remains inside the main-menu safe area;
- a visible title-to-score gap exists;
- score and story fonts are smaller;
- the story parent clips child drawing;
- short text completes without movement;
- long text advances upward and clamps exactly at its overflow;
- an early mouse/touch release emits no return request;
- a release after completion emits one return request; and
- resizing cannot expose text outside the compact rectangle.

The running scene will be inspected at portrait and wide sizes. The check must
confirm that only the clear sky area carries ending text, the arena remains
unobstructed, the score is stationary, the last line stops fully visible, and
the inherited main-menu runtime warning baseline does not gain new errors.
