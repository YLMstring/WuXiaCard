# Empty Turns and Fivefold Board Repetition

## Goal

Preserve owner-turn start and end trigger boundaries when only the next owner
has no legal action, and end the duel by score when the same board ownership
layout has appeared at five completed turn boundaries.

## Authoritative Path

`DuelSimulator` owns both behaviors. The controller, AI search, testing mode,
and replay consume the resulting state and pure-data events without adding
their own pass or repetition rules.

No `PASS` action is added. A turn with no action is a simulator-resolved empty
owner turn, not a recorded action. It does not increment `turn_count`, consume
an extra card play, or add an entry to the replay action log.

## Empty Owner Turns

After an acting owner's end-turn triggers, pending extra card plays, and
temporary-effect restoration have finished, the simulator performs the normal
terminal check. A terminal duel stops before the next owner's start trigger.

If the duel is not terminal, ownership passes to the other owner without
skipping that owner based on legal-action availability. The simulator resolves
that owner's `TRIGGER_START_OWNER_TURN` rules. It then checks legal actions:

- If at least one legal action exists, resolution stops and that owner may act.
- If no legal action exists, only the action phase is skipped. The simulator
  resolves that owner's `TRIGGER_END_OWNER_TURN` rules, services any legal
  extra card plays they grant, restores effects expiring at that owner-turn
  boundary, records the completed board position, and checks for terminal
  state before another owner-turn start.
- If a start-turn rule creates a legal action, the owner turn is not skipped.
- If an end-turn rule grants an extra card play but the owner still has no
  legal hand play, the grant expires under the existing rule and the empty
  owner turn closes.

The simulator repeats this boundary loop until it reaches a terminal state or
an owner has a legal action. Fivefold board repetition guarantees termination
for an otherwise endless sequence of empty turns whose start/end effects do
not produce a playable state.

Existing terminal conditions keep their approved timing: they are evaluated
after an owner turn ends and before the next owner turn starts. In particular,
a full board, both owners having no legal actions, or a completed action count
at the maximum ends the duel at that boundary. The simulator does not start an
additional doomed empty turn after a terminal condition is already true.

## Fivefold Board Repetition

The simulator records one board signature after every completed owner-turn
boundary, including an empty owner turn. The initial position before any turn
has ended is not recorded.

The signature contains exactly nine ordered cells in row-major order. Each
cell contributes either:

- an empty marker; or
- the occupying card's catalog `card_id` and its current `owner`.

The signature deliberately ignores runtime `instance_id`, original owner,
stored powers, ki, abilities and modifiers, hands, decks, removed zones,
active owner, counters, and pending effects. Two boards are therefore the same
exact position for this rule only when every cell is empty in both or contains
the same catalog card ID under the same current owner in both.

Signatures remain in `DuelState.repetition_hashes`, which is already cloned and
included in the search state key. Each boundary appends its current signature.
When that signature has appeared five times anywhere in the recorded history,
the duel becomes terminal immediately at that boundary. Intervening different
positions do not reset the count. Four occurrences are nonterminal.

The ordinary board-card count decides victory, defeat, or tie through the
existing scoring path. No separate repetition outcome or score formula is
introduced.

## Events and Presentation

Empty turns resolve the same catalog start/end trigger nodes as ordinary owner
turns and merge their existing pure-data transition events in resolution
order. No new card-specific event or controller-only gameplay event is needed.
If no ability accepts a boundary trigger, there is no additional visual event;
the semantic boundary still occurred in simulator state.

The controller presents the combined transition normally, then either enables
the owner that can act or displays the existing scored terminal result.

## Search, Replay, and State Copies

Search applies actions through the simulator and receives a state already
advanced across any empty owner turns. It does not branch on synthetic pass
actions. The repetition history remains part of cloned states and the
transposition key so speculative searches cannot share or lose occurrence
counts.

Replay records only actual player/enemy actions. Reapplying those actions
through the simulator deterministically regenerates the same empty-turn
triggers, repetition history, and terminal boundary.

## Tests

Simulator coverage will prove that:

- an owner with no legal action still resolves start-turn then end-turn rules;
- an empty turn does not increment `turn_count` or create an action;
- a start-turn effect that creates a legal action stops the empty-turn loop;
- control reaches the following owner when the empty turn stays unplayable;
- the fourth matching boundary signature is nonterminal and the fifth is
  terminal;
- matching uses catalog `card_id` and current owner, not runtime instance ID;
- changing any occupied cell's current owner prevents a match;
- different intervening positions do not reset earlier occurrences;
- full-board, both-stuck, maximum-action, pending-effect, and extra-card-play
  terminal timing remains unchanged;
- state duplication, AI search, replay, and production controller integration
  preserve the new simulator behavior.

The full repository suite and a production runtime check are required after
implementation.
