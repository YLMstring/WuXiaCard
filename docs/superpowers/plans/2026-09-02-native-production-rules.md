# Native Production Rules Implementation Plan

Date: 2026-09-02
Design: `docs/superpowers/specs/2026-09-02-native-production-rules-design.md`

## 1. Remove dormant vocabulary

- Delete `CONDITION_ATTACK_TARGETED_ATTACKER_ALLY` and
  `ACTION_SPEND_ALL_KI` from `scripts/card_catalog.gd` and their `KNOWN_*`
  arrays.
- Delete the obsolete condition branch from `scripts/duel_triggers.gd` and the
  obsolete payment recognition from `scripts/duel_ability_executor.gd` and the
  native kernel.
- Update the stale Taiji vocabulary test and verify that no declaration still
  refers to either string.

## 2. Compile and execute the two live Dai Zong primitives

- Add `TRIGGER_CARD_REVEALED_TO_SELF` to the native condition opcode, compiler,
  and condition evaluator using the compact reveal code relative to the live
  source owner.
- Add `GRANT_TRIGGER_CARD_ABILITY` to the native action opcode and compiler.
  Reuse the existing immutable granted-ability interning and dynamic-grant
  transaction, with the exact trigger-card instance as recipient.
- Keep activation replacement and passive grant semantics shared with
  `GRANT_ABILITY_TO_SELF` rather than duplicating them.
- Add focused two-owner fixtures for revealed and unrevealed summons by
  `LaiHeQinQuan4` and `LaiHeQinQuan5`, comparing exact Oracle/native state and
  ordered events.

## 3. Add a live-catalog native audit

- Expose a read-only native audit result for compiled ability sets and their
  nested conditions, actions, selectors, modifiers, activations, and granted
  abilities.
- Build a compact state whose immutable pools contain every current catalog
  definition and assert that the audit reports no invalid or unsupported live
  declaration.
- Keep unknown-fixture tests proving reached unsupported declarations are
  rejected atomically.

## 4. Preserve the Oracle behind an explicit API

- Rename the existing GDScript transition body to
  `DuelSimulator.apply_action_oracle()`.
- Leave legality and all pure query APIs on `DuelSimulator` unchanged.
- Update parity and rule-reference tests to call the Oracle explicitly where
  they are specifying or comparing reference semantics.

## 5. Add the mandatory production native adapter

- Add one GDScript adapter responsible only for compact capture, native kernel
  invocation, payload restoration, and transition-shape validation.
- Make `DuelSimulator.apply_action()` validate legality and then call this
  adapter. It must never invoke the Oracle.
- Treat missing extension, unsupported declaration, malformed payload, or
  invalid native result as a fail-fast integration error with the original
  state left untouched.
- Ensure controller, replay, greedy fallback, and search retain their current
  public call sites so all production paths share the same adapter.
- Add integration checks proving production scripts do not call
  `apply_action_oracle()`.

## 6. Verify correctness and production behavior

- Build the Windows Debug GDExtension.
- Run the native compact probe and the focused Dai Zong fixtures.
- Run `tools/run_tests.ps1` in full.
- Run the fixed-depth production search equivalence corpus and record compact
  round-trip performance/completed depth.
- Start the game with audio muted, play one player action, allow one AI action,
  and inspect console/debugger output.
- Update `docs/ARCHITECTURE.md`, `docs/AI_SEARCH.md`, `docs/HANDOFF.md`, and the
  native README with the actual verified boundary and remaining Android gate.

## Commit sequence

1. Remove dormant catalog vocabulary.
2. Implement and verify Dai Zong native primitives plus catalog audit.
3. Add mandatory production native transition adapter and Oracle isolation.
4. Document verified production integration and evidence.
