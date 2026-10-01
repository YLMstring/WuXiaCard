# Complete-board swap resolution

Approved by the user on 2026-10-01. This changes the generic native swap path,
not any card declaration, search policy or presentation timing.

## Problem

The old swap path reserved B off-board, moved A and resolved A's after event,
then reserved A off-board while resolving B's before/move/after events. Ordinary
board listeners on the reserved participant were absent from event discovery.
Playing LangJiTianYa then TianLuoDiWang therefore missed the net's enemy-move
minus-two effect even though that ability had already been granted.

## Approved sequence

1. Locate A and B; validate distinct instances, board presence, expected owners
   and adjacency.
2. Resolve A's `CARD_BEFORE_MOVED`.
3. Resolve B's `CARD_BEFORE_MOVED`.
4. Revalidate both original cells, exact instances and owners.
5. Exchange both complete board slots.
6. Resolve A's `CARD_AFTER_MOVED`.
7. Resolve B's `CARD_AFTER_MOVED`.
8. Merge the resolution events and return `APPLIED`.

Both before events run before swap writes. Their own rules can change the board;
B's event is not skipped merely because A's before event disrupted the swap.
Ordinary discovery and source/ability revalidation still apply, so a genuinely
removed card does not retain a board-only listener.

Failure at step 4 returns `NO_EFFECT` without swap movement events, preserving
the effects and events already produced by both before windows. It does not
restore original positions, ownership, powers or abilities. Existing
`STOP_RULE` handling continues to see a failed swap as no effect.

Step 5 swaps instance indices, owners and board-slot extras, with no callback
between writes. Emit the two existing `card_moved` presentation events together,
in A/B order, before either after window. The controller can continue pairing
them as a reciprocal swap. Their schemas and animation timing are unchanged.

After windows use the complete current board and the exact moved instance's
original owner, origin and destination as movement context. A's after effects
can affect B before B's after event is discovered. Post-swap movement, flip or
exile is retained; the swap still returns `APPLIED`. Unsupported nested effects
still propagate the existing native integration failure instead of a fallback.

## Verification

- Actual alternating hand plays for all nine LangJi tiers 1–3 / TianLuo tiers
  2–4 combinations: one minus-two event from the participating net, ordered
  before its independent attack-failure penalties.
- Both participants observe the other's after movement, with both before
  effects preceding the two swap movement events; slot extras follow instances.
- Either participant can move, flip or exile in its before event: both before
  windows resolve, cancellation preserves those changes and emitted events.
- A can move, flip or exile in its after event without being restored or
  cancelling B's after event.
- Existing swap activation, summon, trigger-reference, search and controller
  presentation suites, full suite, and a muted portrait production walkthrough.
- Same-machine interleaved fixed-node Release search comparison using retained
  pre-change source/DLLs. Use unchanged-result fixtures to compare performance;
  the corrected card interaction intentionally changes previously wrong results.

## Recorded validation

The pre-change native library fails the new real-card cases and the generic
ordering/interruption/post-effect fixtures. After rebuilding both Windows
Release-configuration ABIs, all 89 suites pass in 296.00 seconds: simulator
310 checks, GuMu 315 checks, swap controller/presentation 34 checks.

Muted portrait production-controller playback repeats the exact three-play
sequence three times (18 checks, zero failures). Before frame 5855 shows the
enemy at cell 4 with four nines; after frame 7693 shows it at cell 5 with four
sevens and TianLuo at cell 4. The trace contains one 0.28-second reciprocal swap
and the subsequent power change. A real opponent worker search then commits
its selected action without fallback. Post-play runtime diagnostics report
zero errors. This walkthrough uses testing-mode hand setup and controller
commit calls; it is not an Android device test.

The Release A/B used identical script/configuration copies with retained old
and rebuilt new DLLs, order old/new/new/old, one warmup and seven measured
searches per fixture per round. Each of the three fixtures has 14 samples per
version at exactly 5,000 nodes. Median seconds old→new: plain 0.340056→0.338755,
allied swap 0.362687→0.366165, enemy swap with an external net listener
0.433978→0.431296. All measured action, score, depth, node, generated-action,
transition and cutoff signatures match. No repeatable regression was observed
within these samples; no speedup is claimed. Exact source, matching old DLLs,
raw records and summary are retained under
`.summer/local/tianluo-swap-20261001/`.
