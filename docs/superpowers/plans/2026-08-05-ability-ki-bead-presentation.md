# Ability Ki-Bead Presentation Implementation Plan

**Goal:** Make the existing ki bead communicate temporary flip protection,
activate abilities, qualifying trigger abilities, and otherwise-unrepresented
positive ki according to the approved precedence and number rules.

**Design:**
`docs/superpowers/specs/2026-08-05-ability-ki-bead-presentation-design.md`

## Constraints

- Derive presentation from each card's current `active_abilities` and `ki`.
- Gold overrides light.
- Own-summon-only triggers do not earn a light bead.
- Static modifiers alone do not earn a bead.
- Existing library suppression and face-down concealment remain authoritative.
- Do not alter gameplay ki or ability-resolution behavior.
- Preserve unrelated working-tree changes.

## Task 1: Add focused failing semantic-query tests

**Files**

- Add: `tests/test_ki_bead_presentation.gd`
- Modify: `tools/run_tests.ps1`

**Steps**

1. Create small runtime-card fixtures containing copied ability dictionaries.
2. Add table-driven checks for:
   - no ability and zero ki => `none`, no number;
   - no qualifying ability and positive ki => `dark`, numbered;
   - activate ability at zero => `light`, numbered `0`;
   - qualifying passive trigger at zero => `light`, unnumbered;
   - qualifying passive trigger with positive ki => `light`, numbered;
   - temporary protection at zero => `gold`, unnumbered;
   - temporary protection plus activation at zero => `gold`, numbered `0`;
   - temporary protection plus positive ki => `gold`, numbered;
   - static modifier only => no ability bead;
   - mixed abilities => highest-priority result.
3. Add exact trigger-classification checks:
   - `TRIGGER_CARD_SUMMONED` plus self condition is excluded;
   - `TRIGGER_CARD_AFTER_SUMMONED` plus self condition is excluded;
   - either summon event without the self condition qualifies;
   - any non-summon trigger qualifies;
   - one qualifying trigger among several makes the card light.
4. Add the focused script to `tools/run_tests.ps1`.
5. Run the new test and confirm it fails because the presentation query does
   not exist yet.

**Command**

```powershell
& 'C:\Users\王异\AppData\Local\SummerEngine\current\Summer.exe' --headless --path 'C:\mygame' --script 'res://tests/test_ki_bead_presentation.gd'
```

## Task 2: Implement reusable runtime classification

**Files**

- Modify: `scripts/duel_abilities.gd`
- Test: `tests/test_ki_bead_presentation.gd`

**Steps**

1. Add stable `StringName` constants for bead kinds: `none`, `dark`, `light`,
   and `gold`.
2. Add a private query that recognizes an own-summon-only trigger from its
   event and `CONDITION_TRIGGER_CARD_IS_SELF` condition.
3. Add a query that detects whether any active trigger is not
   own-summon-only.
4. Add a query that recognizes the complete runtime semantics of
   `TEMPORARY_FLIP_PROTECTION`, including its prevention and two expiry
   triggers, instead of relying on a card ID.
5. Add `get_ki_bead_presentation(card)` returning a dictionary with:
   - `kind`;
   - `show_number`; and
   - non-negative `value`.
6. Apply precedence in one place: gold, then light, then dark, then none.
7. Keep `card_uses_ki()` unchanged because gameplay still defines that helper
   as “has an activate ability.”
8. Run the focused test and confirm all semantic-query checks pass.

## Task 3: Add failing CardView rendering tests

**Files**

- Modify: `tests/test_ki_bead_presentation.gd`
- Reference: `scenes/card_view.tscn`

**Steps**

1. Instantiate `card_view.tscn` with representative cards for every bead kind.
2. Check bead visibility, value-label visibility, and value text separately.
3. Inspect the applied `StyleBoxFlat` to distinguish light and gold palettes;
   check the existing dim modulation for dark.
4. Check gold-over-light rendering on a protected activate card.
5. Synchronize a card after removing temporary protection and confirm its bead
   immediately changes from gold to the remaining category.
6. Synchronize ki changes and confirm number visibility follows the approved
   rules.
7. Check `set_face_down(true)` and `set_ki_badge_enabled(false)` hide the bead.
8. Run the focused test and confirm the new rendering checks fail before the
   CardView implementation.

## Task 4: Render all bead states in CardView

**Files**

- Modify: `scripts/card_view.gd`
- Test: `tests/test_ki_bead_presentation.gd`

**Steps**

1. Replace the direct `ki > 0 or card_uses_ki()` calculation in
   `_refresh_face_content()` with the reusable presentation query.
2. Continue applying `ki_badge_enabled` and `not face_down` as final visibility
   gates.
3. Set `ki_value.visible` independently from bead visibility, and retain the
   numeric text for inspection even while the label is hidden.
4. Split bead styling into reusable light, dark, and gold paths without moving
   or resizing the existing node.
5. Preserve the current green center, rim, shadow, label colors, and full-light
   appearance for `light`.
6. Preserve the current dimmed treatment for `dark`.
7. Add the approved lacquer-gold center, pale-gold rim, dark-gold shadow, and a
   readable warm-light number treatment for `gold`.
8. Make `play_ki_gain_pulse()` choose a kind-appropriate temporary highlight
   and restore the freshly classified resting presentation afterward.
9. Run the focused test until semantic and CardView checks pass together.

## Task 5: Verify runtime transitions and regressions

**Files**

- Modify if necessary: `tests/test_duel_integration.gd`
- Test: `tests/test_ki_bead_presentation.gd`
- Test: `tests/test_laihe_qinquan_abilities.gd`
- Test: `tests/test_qixin_luochangkong_abilities.gd`
- Test: `tests/test_card_catalog.gd`
- Test: `tests/test_deck_builder_integration.gd`

**Steps**

1. Add only the minimal production-scene assertion needed if the focused
   CardView test cannot cover a runtime protection-expiry refresh.
2. Run the focused bead test.
3. Run LaiHe and QiXin suites to cover temporary protection removal and retained
   abilities.
4. Run catalog tests to protect activation detection and schema validity.
5. Run deck-builder integration to confirm library bead suppression remains.
6. Boot the full project headlessly for a scene-load check.
7. Run `git diff --check` and inspect `git status --short` so unrelated changes
   remain untouched.

**Commands**

```powershell
& 'C:\Users\王异\AppData\Local\SummerEngine\current\Summer.exe' --headless --path 'C:\mygame' --script 'res://tests/test_ki_bead_presentation.gd'
& 'C:\Users\王异\AppData\Local\SummerEngine\current\Summer.exe' --headless --path 'C:\mygame' --script 'res://tests/test_laihe_qinquan_abilities.gd'
& 'C:\Users\王异\AppData\Local\SummerEngine\current\Summer.exe' --headless --path 'C:\mygame' --script 'res://tests/test_qixin_luochangkong_abilities.gd'
& 'C:\Users\王异\AppData\Local\SummerEngine\current\Summer.exe' --headless --path 'C:\mygame' --script 'res://tests/test_card_catalog.gd'
& 'C:\Users\王异\AppData\Local\SummerEngine\current\Summer.exe' --headless --path 'C:\mygame' --script 'res://tests/test_deck_builder_integration.gd'
& 'C:\Users\王异\AppData\Local\SummerEngine\current\Summer.exe' --headless --path 'C:\mygame' --quit-after 5
git diff --check
git status --short
```

## Completion Criteria

- All five user rules are represented by focused passing tests.
- Temporary protection is gold and takes priority over all other bead kinds.
- Activate and qualifying trigger abilities use the current light bead.
- Positive ki without a qualifying bead source uses the current dark bead.
- Zero appears only for an activate ability.
- Runtime ability/ki changes refresh immediately.
- Face-down cards and library cards remain concealed.
- No gameplay behavior or unrelated working-tree content changes.
