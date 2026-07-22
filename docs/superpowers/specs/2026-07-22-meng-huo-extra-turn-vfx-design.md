# Meng Huo Extra-Turn VFX Design

## Goal

Make Meng Huo's extra-turn trigger immediately understandable without adding sound, screen shake, or rules changes. The presentation must show that accumulated ki is spent and that the same owner keeps the turn.

## Visual Direction

Use **Ki Convergence**: each card that contributed an extra-turn request emits one temporary golden ki bead. The bead contracts from the card's ki-badge area into the center of that card. Each source card pulses once as the bead arrives. After all beads converge simultaneously, one warm gold outline expands across the board and fades while the existing turn-status label displays `Extra turn` in the same gold.

The complete sequence lasts approximately 0.65 seconds in normal play. It adds no audio and no camera or screen shake. Debug fast mode reduces all new animation durations to zero.

## Architecture

Add a reusable, input-transparent `Control` overlay to the duel scene. It owns temporary bead visuals and a procedural board-outline pulse. The overlay receives source-card rectangles and the board rectangle in its own coordinate space, then performs the full sequence without mutating gameplay state.

The controller's existing ordered event presenter remains the integration point. When it receives `extra_turn_granted`, it resolves the event's `source_instance_ids` to current board-card views and passes their rectangles to the overlay. The presentation depends on event data, not the card name, so future extra-turn effects reuse it automatically.

The live rules event remains unchanged. The controller continues to set the status text and awaits the visual sequence before allowing the next input.

## Event and Timing Flow

1. Existing `ki_changed` events update each source card to zero ki.
2. `extra_turn_granted` resolves all valid `source_instance_ids` to board views.
3. One temporary gold bead per resolved source starts near that card's ki-badge corner.
4. All beads converge into their respective card centers over roughly 0.30 seconds.
5. Each source card performs one restrained scale pulse as its bead arrives.
6. A single gold board outline expands and fades over roughly 0.35 seconds.
7. The status label reads `Extra turn` in gold for the sequence, then returns to white through the existing turn-status flow.

If more than one Meng Huo requests the same extra turn, all source beads animate concurrently, but the board and status pulse occur only once.

## Failure and Edge Handling

- Missing or removed source views are skipped; the board pulse still plays because the extra turn was granted by the rules.
- Duplicate source instance IDs are deduplicated before spawning beads.
- The overlay ignores input at all times and cleans up every temporary visual after completion.
- A zero-duration call immediately restores clean overlay and card state.
- Repeated extra turns run sequentially through the existing ordered event presenter, preventing overlapping pulses.
- The effect works for either owner and does not reveal hidden card information.

## Testing

Automated integration coverage will verify:

- the overlay exists and ignores input;
- `extra_turn_granted` invokes one convergence sequence;
- source instance IDs are resolved and deduplicated;
- multiple Meng Huos create multiple beads but one board pulse;
- missing source views still produce the board pulse;
- fast mode completes without leaving temporary visuals or altered card scales;
- the existing event ordering and extra-turn rules remain unchanged.

Manual playtesting will trigger Meng Huo's ability in a real duel, confirm that bead convergence precedes the board pulse, repeat the trigger across chained extra turns, and inspect the console and debugger for runtime errors.
