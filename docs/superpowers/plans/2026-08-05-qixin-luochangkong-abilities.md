# 七星落长空 2–4 Implementation Plan

**Spec:** `docs/superpowers/specs/2026-08-05-qixin-luochangkong-abilities-design.md`

**Goal:** Implement the three approved cards with two retained generic attack
modifiers, the existing summon-reaction primitive, and the existing temporary
flip-protection primitive without card-ID special cases.

**Architecture:** Static ability modifiers are queried through
`duel_abilities.gd`. `duel_rules.gd` separates power-and-position range from
initial attack permission. The simulator uses full permission for declaration
and range-only validation after `CARD_BE_ATTACKED`. The trigger condition uses
range-only semantics so the tier-three reaction can trigger while an attack is
not permitted.

---

## Task 1: Add a focused failing test suite

**Files:**

- Create: `tests/test_qixin_luochangkong_abilities.gd`
- Modify: `tools/run_tests.ps1`

1. Build helpers for catalog instances, simple cards, board slots, event type
   extraction, and assertions following `test_laihe_qinquan_abilities.gd` and
   `test_taishan_wudafu.gd`.
2. Add catalog assertions for IDs 2–4, ability counts, retained flags, modifier
   types, reaction declarations, and protection declarations.
3. Assert `Catalog.validate_catalog()` is empty.
4. Add the suite to `tools/run_tests.ps1` near the other focused card-ability
   suites.
5. Run the suite and confirm it fails because IDs 3–4 are absent from
   `ALL_CARD_IDS` and the abilities are undeclared. Require the explicit
   `QIXIN_LUOCHANGKONG_TESTS_PASSED` marker for success.

## Task 2: Add and validate the generic modifiers

**Files:**

- Modify: `scripts/card_catalog.gd`
- Modify: `scripts/duel_abilities.gd`
- Extend: `tests/test_qixin_luochangkong_abilities.gd`

1. Add constants:

   ```gdscript
   const MODIFIER_ATTACK_REQUIRES_OTHER_ALLY: StringName = &"attack_requires_other_ally"
   const MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE: StringName = &"defending_power_uses_minimum_side"
   ```

2. Register both in `KNOWN_MODIFIERS`.
3. Refactor `_validate_modifiers()` by modifier type:
   - `defending_power_override` requires only `type` and non-negative integer
     `value`;
   - the two Boolean modifiers require only `type` and reject `value`;
   - unknown fields remain errors for every type.
4. Keep `get_modifiers()` and `has_modifier()` as the generic query API. Add a
   typed helper that returns the minimum of all four calls to
   `get_effective_defending_power()` without mutating stored powers. Return the
   facing fallback for malformed power arrays.
5. Add red/green tests for valid parameterless modifiers, invalid extra
   values, invalid missing override values, modifier detection, minimum
   effective defense, and stored-power immutability.
6. Run the focused suite.

## Task 3: Separate attack range from initial permission

**Files:**

- Modify: `scripts/duel_rules.gd`
- Modify: `scripts/duel_triggers.gd`
- Modify: `scripts/duel_simulator.gd`
- Extend: `tests/test_qixin_luochangkong_abilities.gd`

1. Extract the current adjacency, ownership, direction, power-array, and strict
   comparison work from `can_attack_target()` into
   `is_target_in_attack_range()`.
2. In the range function, choose the defender value as follows:
   - normal attacker: effective value of the facing side;
   - attacker with the minimum-side modifier: minimum of all four effective
     defending sides.
3. Make `can_attack_target()` reject an attacker with
   `attack_requires_other_ally` unless `Rules.count_owned(board, owner) >= 2`,
   then delegate to `is_target_in_attack_range()`.
4. Keep `get_would_flip_indices()` on `can_attack_target()` so ordinary and
   requested standard attacks enforce initial permission.
5. Change `CONDITION_TRIGGER_CARD_IN_RANGE` in `duel_triggers.gd` to call
   `is_target_in_attack_range()`. This preserves reaction triggering and pulse
   while alone.
6. Split simulator validity semantics:
   - the first check in `_resolve_attack_target()` uses full
     `can_attack_target()` permission;
   - the post-`CARD_BE_ATTACKED` check verifies the exact instance IDs and uses
     `is_target_in_attack_range()` only.
7. Add tests showing:
   - the card is in range but cannot attack while alone;
   - every standard/requested attack path produces no `attack_started` or
     flip while alone;
   - another current-owner ally enables the attack;
   - removing that ally makes future declarations illegal;
   - range-only revalidation remains true after the ally is removed, proving
     an already-declared attack is not canceled by this modifier;
   - movement or exact-card loss still fails range/recheck validation; and
   - after ownership flips, the retained modifier counts allies of the new
     owner.
8. Run the focused suite and `tests/test_duel_rules.gd`.

## Task 4: Declare cards 2–4

**Files:**

- Modify: `scripts/card_catalog.gd`
- Extend: `tests/test_qixin_luochangkong_abilities.gd`

1. Add `QiXinLuoChangKong3` and `QiXinLuoChangKong4` immediately after tier 2
   in `ALL_CARD_IDS`.
2. Define one shared declaration constant for the retained pair of modifiers,
   or duplicate the small declaration only if using a shared mutable
   dictionary would risk accidental catalog mutation. Every normalized card
   instance must receive a deep copy.
3. Give all three cards the retained modifier ability.
4. Give tiers 3 and 4 a separate default-non-retained summon-reaction ability
   matching 苍松迎客.
5. Give tier 4 a separate copy of `TEMPORARY_FLIP_PROTECTION`.
6. Run catalog validation and the focused suite.

## Task 5: Verify reaction and protection behavior

**Files:**

- Extend: `tests/test_qixin_luochangkong_abilities.gd`

1. Test tier 3 with a second ally: an enemy summon in range produces
   `ability_triggered`, `attack_started`, and the expected flip.
2. Test tier 3 alone: the same summon produces `ability_triggered` but no
   `attack_started` and no flip.
3. Flip tier 3 through a non-attack flip and assert both modifiers remain while
   the reaction ability is removed.
4. Test tier 4 preventing an attack flip and a non-attack flip.
5. Test an actual enemy flip removing only the protection ability. Confirm a
   later flip succeeds and the retained modifiers remain.
6. Test the protected card's current-owner turn start removing only the
   protection ability.
7. Duplicate simulator state before each destructive branch and assert active
   ability mutations do not leak between copies.
8. Run the focused suite plus:
   - `tests/test_laihe_qinquan_abilities.gd`
   - `tests/test_cangsong_sanqin_abilities.gd`
   - `tests/test_taishan_wudafu.gd`

## Task 6: Final verification

**Files:**

- Review all modified files

1. Run `git diff --check` and inspect `git status --short` to preserve unrelated
   user changes.
2. Run the focused suite in headless Summer Engine and require its pass marker.
3. Run the three reused-primitive regression suites from Task 5.
4. Run any currently green catalog/rules simulator suites. If an older broad
   suite still fails only because it references removed IDs such as
   `strategist` or `fa_zheng`, report that separately and do not change gameplay
   to satisfy stale fixtures.
5. Confirm no card-ID check for 七星落长空 exists outside the catalog and tests.
6. Confirm modifier abilities do not emit presentation pulses, while the
   tier-three trigger continues to use the existing pulse path.
