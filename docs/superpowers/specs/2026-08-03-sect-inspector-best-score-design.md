# Sect Inspector Best Score Design

Date: 2026-08-03

## Goal

When a sect entry is inspected from the sect-selection scene, replace the
location displayed in the inspector's first metadata tag with the sect's global
best score, formatted exactly as `最高分：x`. A sect without a recorded result
shows `最高分：0`.

## Data and Presentation Boundary

`sect_catalog.gd` remains authoritative and keeps the real location in its
`sect` field. `CardInspector` remains generic and unchanged. Immediately before
opening a sect inspection, `sect_selection_controller.gd` duplicates the sect
definition, reads `best_scores_by_sect` from the already-loaded profile by the
definition's exact sect ID, and replaces only the duplicate's `sect` value with
the formatted score. The source catalog definition and profile are never
mutated.

Preview-hand cards continue through the ordinary card-inspection path and keep
showing their actual sect. Locked and unlocked sect entries use the same score
display rule.

## Verification

Sect-selection integration coverage will verify the zero-score fallback, a
persisted nonzero best score, and preservation of ordinary preview-card sect
display. Existing card-inspector and profile tests remain unchanged and the
complete canonical suite must pass.
