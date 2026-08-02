# Duel Replay Design

Date: 2026-08-02

## Goal

Add an in-scene replay for a completed duel. A supplied black replay icon sits
to the left of the board at its vertical midpoint. After the duel ends, the
player may press it to watch the exact duel again with a two-second pause
between turns. Pressing it during an active duel or an existing replay does not
start anything.

The replay is temporary presentation state. It does not persist after leaving
the duel scene and cannot affect progression, mastery, enemy memory, rewards,
or the recorded duel result.

## Approved Player Experience

- `res://inkpics/replay.png` is the visible replay artwork.
- The artwork is shown inside a flat, frame-free touch target of approximately
  44 by 44 logical pixels.
- The control is positioned immediately left of the board and vertically
  aligned with the board's center.
- The icon remains visible during active play, after completion, and during
  replay.
- Touch-down scales the icon down slightly and reduces its opacity. Releasing
  restores it with a short spring-like response. This presentation feedback is
  allowed even when replay itself is unavailable.
- During an active duel, pressing the control changes no duel state.
- After completion, pressing it immediately restores the opening position and
  plays the first recorded turn.
- During replay, pressing it changes no replay or duel state.
- After replay finishes, the exact final result remains visible and the replay
  control may be used again.

## Replay Visibility and Interaction

Normal concealment rules remain authoritative during replay. The opponent's
hand stays face-down in normal mode; testing mode retains its usual revealed
hand.

All gameplay interaction is disabled during replay:

- cards cannot be played or activated;
- cards cannot be dragged;
- no AI search or automatic opponent-turn scheduling runs;
- replay cannot record replayed actions into itself.

Inspection is still available for any currently revealed card. A concealed
card remains uninspectable and leaks no metadata. Inspection is accepted only
while the replay is settled between actions or after it has finished, not in
the middle of an attack, movement, draw, or other action presentation. Opening
the inspector pauses the remaining inter-turn delay. Closing it resumes the
same delay from the point where it paused.

The existing return icon remains usable during replay. Pressing it cancels the
replay and emits the victory or defeat already established by the real duel.

## Replay Record

The controller owns one in-memory replay record containing:

1. an immutable duplicate of the exact initialized `DuelState`, captured after
   both starting hands and shuffled side decks are finalized;
2. one immutable copy of every successfully committed player or opponent
   `DuelAction`, in resolution order;
3. an immutable duplicate of the completed final state for recovery;
4. the completed outcome and final status text.

Illegal or rejected actions are never recorded. The record uses exact runtime
`instance_id` values, so drawn cards, created copies, activations, and hand-slot
changes remain unambiguous.

The record is never written to the deck profile or another file. Leaving the
duel discards it.

## Playback Architecture

Replay uses the approved initial-state-plus-action-log approach.

When replay begins, `DuelController`:

1. cancels and joins any opponent search;
2. enters a dedicated replaying state;
3. replaces the live logical state with a duplicate of the recorded initial
   state;
4. clears and rebuilds all card views, fixed hand-slot mappings, board views,
   scores, removed-card presentation, and concealment from that state;
5. applies each recorded action through `DuelSimulator` in order;
6. presents each returned transition through the normal placement and event
   presentation path;
7. waits two seconds after a fully presented action before starting the next
   action, except that no trailing wait is required after the final action;
8. restores the completed result/status and replay availability.

The first action starts immediately after the opening position is rebuilt.
The delay is an exported duration with a production default of `2.0` seconds;
tests may set it to zero.

Playback does not call the normal side-effect boundaries that record mastery,
emit enemy-card memory, start AI, or navigate/progress the run. Simulator
application and visual presentation are reused, but real-duel bookkeeping is
not.

Future stochastic rules must put their resolved randomness into `DuelState` or
the committed action so action-log replay remains deterministic. Randomness
that exists only outside authoritative simulation state is incompatible with
this replay contract.

## Failure Handling

The replay button handler returns immediately unless all of these are true:

- the real duel is complete;
- replay is not already running;
- the initial and final snapshots exist;
- at least one successful action was recorded.

The replay loop validates each recorded action against its reconstructed state.
If an action is unexpectedly invalid or the presentation cannot continue, it
stops replay, restores a duplicate of the recorded final state and its card
views, restores the original result/status, emits no persistence side effects,
and reports a warning for diagnostics.

Repeated presses cannot start overlapping replay coroutines. Exiting the scene
invalidates the active replay so a delayed continuation cannot touch freed
nodes.

## Testing

Focused replay coverage will verify:

- only successful real actions enter the action log;
- the initial snapshot contains the exact shuffled hands and side decks;
- pressing replay during active play is a state-preserving no-op;
- pressing replay while replaying does not start a second loop;
- the supplied image is used in the left-center icon-only control;
- touch-down and release provide scale/opacity feedback;
- normal-mode opponent hands remain concealed throughout replay;
- testing mode retains its normal revealed-hand behavior;
- actions, triggered effects, final board ownership, scores, and outcome match
  the original duel;
- replay suppresses mastery, opponent-memory, AI, and navigation side effects;
- inspection pauses and resumes the remaining inter-turn delay;
- concealed-card inspection remains blocked;
- replay can run repeatedly from the same initial record;
- exiting during replay emits the original outcome;
- an invalid recorded action safely restores the completed final state.

The full automated suite must remain green. Runtime verification will play a
portrait duel to completion, start replay, inspect a revealed card during an
inter-turn gap, observe concealment and the two-second cadence, replay a second
time, and exit during replay while checking the debugger and console.
