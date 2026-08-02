# Replay Button Child Icon Design

Date: 2026-08-02

Keep `ReplayButton` as the existing centered `44×44` interaction target. Remove
its constrained built-in icon and add a centered `55×55` `TextureRect` child
using `res://inkpics/replay.png`. The child ignores mouse/touch input, does not
clip at the button boundary, preserves the image aspect ratio, and inherits the
button's existing scale/opacity press feedback. Existing user-tuned placement
remains unchanged.

Automated UI coverage verifies the separate visual node, its texture and input
filter, the smaller parent hit area, and the oversized centered bounds.
