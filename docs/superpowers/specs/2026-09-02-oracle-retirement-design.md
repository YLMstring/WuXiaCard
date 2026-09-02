# Oracle Retirement Design

Date: 2026-09-02

## Goal

Retire the independently maintained GDScript rules and search Oracle after
transferring its useful regression coverage to the strict native production
path. The player, replay, greedy fallback, AI, and automated rules tests will
then have one authoritative rules implementation.

## Boundary

`DuelSimulator` and `DuelSearch` remain public facades. Shared responsibilities
such as public action validation, terminal checks, scoring, result conversion,
and same-turn plan materialization remain in GDScript where production still
uses them. Only the alternate transition engine, alternate tree search, their
test switches, and code used exclusively by those paths are removed.

The native kernel remains strict: unsupported declarations and malformed
results are integration failures. There is no compatibility fallback.

## Test Authority Transfer

Fine-grained rules and card suites must exercise `DuelSimulator.apply_action()`
directly and keep their explicit state and ordered-event assertions. Search
tests must exercise the native production entry and assert product semantics:
deterministic choices, complete-round depth, deadlines, cancellation, minimum
depth guards, canonical ties, and same-turn principal-action reuse.

Oracle-only experiments such as the historical GDScript PVS, tactical
extension, evaluation cache, and Lazy profile ablations are removed from the
active suite. Their measured conclusions remain in history and documentation;
they do not justify retaining a second search implementation.

The native catalog audit remains mandatory and must reject every unknown
reachable declaration, including nested and dynamically granted abilities.
Catalog-wide fixtures continue to prove that every current hand play and legal
activation can execute through production, but they assert validity and
coverage rather than equality with a deleted engine.

## Final Differential Seal

Before deletion, run one last deterministic lockstep corpus through both
engines. The corpus uses real enemy-catalog decks, both initiative directions,
fixed seeds, and an external canonical legal-action policy so both engines
receive the same action. After every action it compares:

- exact canonical state payload;
- captures and exiles;
- ordered presentation events;
- terminal status and legal canonical action keys.

It also includes deterministic varied-action walks so the seal is not limited
to whichever branch one AI happens to choose. Any mismatch is adjudicated
against current catalog declarations and focused rule tests; the Oracle is not
automatically presumed correct.

The seal is temporary migration evidence. Once it passes, it and the Oracle
comparison-only test plumbing may be deleted. A concise result is recorded in
the handoff documentation and the pre-removal Git commit remains the recovery
point.

## Removal

Remove:

- `apply_action_oracle()`, Oracle greedy helpers, and exclusive transition
  implementation code;
- `find_best_action_oracle()`, `find_best_action_iterative_oracle()`, the
  `_oracle_test_backend` switch, and exclusive GDScript tree-search code;
- Oracle parity probes and historical benchmark modes that require the old
  backend;
- obsolete documentation instructing maintainers to run Oracle comparisons.

Do not remove facade APIs or helper modules merely because the Oracle used
them. A call-site audit must first prove that production, legal-action
generation, catalog validation, presentation, and native state conversion do
not depend on them.

## Verification

The retirement is complete only when:

1. the final lockstep seal passes before deletion;
2. no executable code or active test references Oracle entry points or the
   Oracle backend flag;
3. every fine-grained rule/card suite runs through native production;
4. the native catalog and search regression suites pass independently;
5. the full canonical suite passes after deletion;
6. a muted production duel completes with a player action, AI response,
   presentation events, and same-turn continuation behavior intact.

Windows Debug is the current verified platform. Android ARM64 remains a
separate distribution gate and does not block deleting the unused Oracle.

## Non-Goals

- No gameplay, card text, evaluation, or AI-strength change.
- No rewrite of shared legal-action or UI code into C++.
- No attempt at exhaustive state-space equivalence.
- No permanent maintenance of golden traces duplicating focused semantic
  tests.
