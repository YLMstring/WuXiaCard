# Dynamic Initiative Evaluation Design

## Problem

The nonterminal evaluator values one point of board-card ownership difference at
`100,000` points and one hand-card difference at `5,000` points. A quiet play
therefore changes the static score by about `95,000` points even though it only
moves a card from hand to board. The current side-to-move term is only two
positional points, so it cannot represent the opponent's imminent reply.

This produces a severe depth-parity effect. In the observed Quick LazyOnly
matchup, depth-three leaves ended immediately after the root owner played a
card and scored `100015` or `99949`; the corresponding depth-two leaves ended
after the opponent acted and had opposite or nearly neutral scores. Fixed-depth
Baseline and Lazy search remain equivalent, so this is an evaluation-horizon
problem rather than a Lazy transition correctness problem.

## Goal

Give the next player a generic, strategically meaningful initiative value so a
quiet normal play and the following ownership of the move have approximately
the same combined evaluation before and after the play.

The change must preserve these rules:

- Terminal evaluation still depends on the real final board score.
- Board captures and ownership flips remain highly valuable.
- Search and evaluation remain card-agnostic.
- A player without a legal hand play receives no fictitious deployment value.
- Active abilities are not treated as if they necessarily place a card.

## Chosen Formula

The current net strategic change of a quiet normal play is:

```text
board card value - hand card value
= 100,000 - 5,000
= 95,000
```

Changing the active player reverses the sign of initiative. To make the score
approximately invariant across a quiet play, one ordinary pending play is worth
half of that net change:

```text
NORMAL_PLAY_NET_VALUE = 95,000
BASE_INITIATIVE_VALUE = 47,500
```

From the root owner's perspective:

- add the initiative value when the root owner is active;
- subtract it when the opponent is active.

For a quiet play with no other state change:

```text
before: +47,500
after:  +95,000 - 47,500 = +47,500
```

This initiative term is strategic and is applied outside the positional
`±499` clamp. Terminal states return before initiative is considered.

## Eligibility and Extra Plays

Initiative is granted only if the active owner has at least one legal action
whose type is a hand play. An empty hand, a full board, or any other state with
no legal hand play receives zero deployment initiative.

Normally the active owner has one pending play opportunity. During an existing
extra-play chain, `extra_card_plays_remaining` is the exact number of forced
hand plays still available before the turn can advance. The number of
consecutive deployable plays is therefore:

```text
normal turn: 1
extra-play chain: extra_card_plays_remaining
```

It is capped by both current hand size and current empty-cell count. The first
pending play contributes `47,500`; each additional guaranteed consecutive play
contributes the full `95,000`, because it is not balanced by an intervening
opponent action:

```text
initiative = 47,500 + (consecutive_plays - 1) * 95,000
```

The sign still follows the active owner. Card effects may alter the actual
result of those plays; deeper search resolves those effects exactly. This term
only values the generic right to deploy cards before control passes.

If the active owner can only activate a board ability, the strategic initiative
term is zero. Existing mobility, ki, active-ability, danger, and positional
features continue to value that state generically.

## Evaluator Changes

`DuelEvaluator` will:

1. Name the existing board and hand strategic weights instead of leaving the
   hand weight as an inline literal.
2. Derive `NORMAL_PLAY_NET_VALUE` and `BASE_INITIATIVE_VALUE` from those weights
   and `STRATEGIC_SCALE`.
3. Reuse generic legal-action information to detect an active legal hand play.
4. Add the signed dynamic initiative after the positional score is clamped and
   before the final nonterminal score is clamped.
5. Remove the existing two-point `TEMPO_WEIGHT` term and the enhanced-only
   four-point extra-play tempo term so initiative is not counted twice.

No simulator rule, action legality rule, terminal rule, controller behavior, or
card declaration changes.

## Expected Effect on the Reproduced Leaves

With one ordinary pending play and no extra-play chain:

- `-38` with the root owner to act becomes approximately `+47,462`.
- `99949` with the opponent to act becomes approximately `+52,449`.
- `100015` with the opponent to act becomes approximately `+52,515`.

The remaining differences represent real hand, board, power, position, and
effect consequences. They are no longer a full `100,000`-point reward merely
for ending the horizon immediately after one side deployed a card.

## Verification

Add focused evaluator and search regressions covering:

1. A quiet legal play followed by an active-player switch leaves the combined
   evaluation approximately invariant, apart from existing bounded positional
   features.
2. No legal hand play produces no strategic initiative.
3. A single pending extra play receives only the base initiative; two or more
   consecutive extra plays add one full net-play value per additional play,
   capped by hand cards and empty cells.
4. Terminal evaluation is unchanged.
5. Board ownership flips still produce a large strategic gain.
6. The two reproduced third-decision states no longer show a roughly
   `100,000`-point depth-parity jump attributable only to the last deployment.
7. Baseline, LazyOnly, and Lazy+PVS retain fixed-depth score/action equivalence.

Run the focused evaluator/search tests, the real-opening equivalence diagnostic,
and the canonical full suite. After correctness passes, rerun the same 1,500-node
real Quick LazyOnly schedule to measure strength; win rate is evidence for
tuning, not a correctness gate for the initiative formula.

## Out of Scope

- Changing search depth from actions to complete turns.
- Accepting only even iterative-deepening depths.
- Adding named-card evaluation knowledge.
- Rebalancing terminal scoring.
- Broadly replacing the existing board, hand, power, ki, danger, or mobility
  feature set.
