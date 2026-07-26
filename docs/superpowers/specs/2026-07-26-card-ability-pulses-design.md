# Card Ability Pulses Design

## Goal

Give every successfully triggered passive card ability a short, ordered whole-card
pulse immediately before its actions are presented. Activate abilities do not
pulse. The feedback must reuse the existing restrained scale animation and must
not change simulation outcomes or AI decisions.

## Trigger Event

When a passive trigger group is revalidated and its conditions still match,
`DuelTriggers.resolve_group()` emits one presentation-only `ability_triggered`
event before executing the rule's actions.

The event contains:

- `source_cell`
- `source_instance_id`
- `source_owner_id`

An invalidated group or a group whose conditions no longer match emits no event.
An accepted group emits the event even if one or more of its later actions return
`NO_EFFECT`, because the ability itself still triggered.

Activations use `execute_activation()` rather than the passive trigger resolver
and therefore never emit `ability_triggered`.

## Presentation Order

The existing ordered transition-event presenter handles `ability_triggered` by
finding the board card through `source_instance_id` and awaiting
`CardView.play_effect_pulse()`. Awaiting the animation supplies the short delay
before the next event is presented.

The pulse duration is an exported controller setting and becomes zero in fast
test mode. A missing or freed source view safely skips the animation.

## Consecutive Suppression

Pulse memory is local to one call to `_present_transition_events()`, which is one
completed move. It resets before the next move.

The presenter remembers the instance ID of the last card that actually received
the generic pulse:

- `A -> A`: only the first A pulses.
- `A -> B -> A`: all three pulse.
- A on one move followed by A on the next move: both pulse.

If a source view is unavailable, no pulse occurred and the remembered instance
ID does not change.

## Removing Ability-Specific Card Pulses

The generic event replaces the two existing whole-card pulse paths:

- Gate General and Tiger General no longer pulse through `card_exiled`
  presentation.
- Meng Huo source cards no longer pulse inside the extra-turn convergence
  overlay.

The following result feedback remains because it is not a whole-card
ability-trigger pulse:

- Meng Huo's ki badge pulses when ki increases.
- The board outline pulses when an extra turn is granted.
- Extra-turn beads still converge from their source cards.
- Exile, draw, movement, flip, and ability-loss feedback remain unchanged.

CangSong's summon reaction and draw abilities gain the generic passive-trigger
pulse. Movement and other activate abilities remain unpulsed.

## Simulation and Search

`ability_triggered` is a transition event only. It is not stored in `DuelState`,
does not enter state keys, and does not affect legal actions, evaluation, or
search. The simulator remains deterministic because trigger discovery and
resolution order are unchanged.

## Verification

Automated tests cover:

- `ability_triggered` appearing before a passive rule's action events;
- invalidated and condition-failing groups emitting no trigger event;
- a passive ability that later produces `NO_EFFECT` still emitting the event;
- activations emitting no trigger event;
- consecutive same-card pulses being suppressed within one move;
- different-card pulses resetting the suppression comparison;
- pulse memory resetting between moves;
- Gate/Tiger exile no longer adding a separate source pulse;
- Meng Huo extra-turn convergence retaining beads and the board pulse while
  removing its source-card pulse.

Manual playtesting checks CangSong, draw, exile, and Meng Huo trigger sequences
at normal speed and confirms that activate abilities do not pulse.
