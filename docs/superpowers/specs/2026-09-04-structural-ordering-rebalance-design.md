# Structural Ordering Rebalance Design

## Goal

Make native move ordering less biased toward immediate raw-power attacks and
measure the resulting search-speed change on real openings.

## Production behavior

Only `action_structural_score()` changes. Other ordering layers, minimax,
static evaluation, rules, and legal-action generation remain unchanged.

- Every legal activation has structural score `100`.
- A play into center cell `4` starts at `0`.
- A play into edge cells `1`, `3`, `5`, or `7` starts at `10`.
- A play into corner cells `0`, `2`, `6`, or `8` starts at `20`.
- Every occupied orthogonally adjacent cell adds `5`, regardless of owner.
- If an adjacent card is an enemy and the played card's facing raw power is
  greater than that enemy's opposing raw power, add another `100`.

Structural score remains an ordering hint only. A fully completed search still
chooses actions by minimax score and canonical tie-breaking.

## Verification and comparison

Before implementation, run the 14 unique real Quick openings with production
search settings: `self_turn`, ten seconds, internal PV, conservative history,
and an 8 MiB transposition table. After rebuilding the native library, run the
same command again.

Compare the two reports using:

- depth-two and depth-three completion counts;
- per-opening completed-depth time and node count;
- aggregate nodes per second;
- action/score differences at the deepest common completed depth.

Update the frozen structural-order test and run the focused native production
rules and search tests. Per the current task instruction, do not run the full
73-suite test command in this iteration.

## Scope limits

Do not retain a legacy structural-score switch. Do not modify PV, TT, History,
static evaluation, card rules, or production time limits. Do not interpret
higher raw nodes per second alone as better ordering; completed-depth work and
reachability are the primary measures.
