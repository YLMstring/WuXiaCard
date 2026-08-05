# Ability Ki-Bead Presentation Design

## Goal

Reuse the existing ki bead to communicate a revealed card's current runtime
abilities as well as its ki. The bead must update when the card gains or loses
abilities, changes owner, spends ki, or gains ki. It remains presentation-only
and does not change gameplay logic.

## Scope

This feature changes the bead shown by `card_view.gd`. It derives presentation
from the card's current `active_abilities` and `ki` fields. It preserves the
existing `set_ki_badge_enabled(false)` override, face-down concealment, bead
position, and bead size. Library cards therefore continue to hide ki beads.

## Ability Classification

### Temporary flip protection

A card has temporary flip protection when one of its active abilities matches
the semantics of `TEMPORARY_FLIP_PROTECTION`:

- it prevents its own flip during `CARD_BEFORE_FLIPPED`;
- it removes that same ability after an enemy card actually flips; and
- it removes that same ability when its current owner's turn starts.

This classification uses runtime abilities, not the original catalog
definition. Once the protection ability is removed, it no longer affects bead
presentation.

### Activate ability

A card has an activate ability when any active ability contains a non-empty
`activation` declaration. Multiple activate abilities still count as one
presentation category.

### Own-summon-only trigger

A trigger is own-summon-only only when both conditions are true:

1. its event is `TRIGGER_CARD_SUMMONED` or `TRIGGER_CARD_AFTER_SUMMONED`; and
2. its conditions include `CONDITION_TRIGGER_CARD_IS_SELF`.

An ability with one or more triggers earns the light bead if at least one of
those triggers is not own-summon-only. Static modifiers do not earn the light
bead. A trigger ability consisting exclusively of own-summon-only triggers does
not earn the light bead.

## Presentation Rules

Classification is evaluated in this priority order:

| Runtime state | Bead | Number |
| --- | --- | --- |
| Has temporary flip protection | Gold | Show only when ki is positive or the card also has an activate ability |
| Otherwise has an activate ability | Current light bead | Always show, including `0` |
| Otherwise has a qualifying trigger | Current light bead | Show only when ki is positive |
| Otherwise has positive ki | Current dark bead | Show ki |
| Anything else | No bead | No number |

Gold takes priority over light when a card qualifies for both. The presence of
an activate ability controls zero-number visibility independently of bead
color. Therefore a protected card with an activate ability displays a gold
bead with `0`, while a protected passive card at zero ki displays an unnumbered
gold bead.

## Visual Treatment

- **Light:** preserve the current green bead at full brightness.
- **Dark:** preserve the current green bead with its current dimmed treatment.
- **Gold:** use a warm lacquer-gold center, pale-gold rim, and restrained
  dark-gold shadow.
- **None:** hide the bead.

When a number is not required, the value label is hidden. It is not replaced by
an empty string, symbol, or placeholder. Ki-gain presentation may brighten the
bead temporarily but must settle back to the correct current style, including
gold.

## Architecture

`duel_abilities.gd` owns a pure presentation query. Given a runtime card, it
returns:

- bead kind: `gold`, `light`, `dark`, or `none`;
- whether the number is visible; and
- the non-negative ki value.

This keeps ability-schema interpretation out of `card_view.gd` and makes the
classification independently testable. `card_view.gd` consumes the query,
applies the appropriate style, controls bead and value-label visibility, and
keeps the existing explicit badge-disable and face-down gates.

No per-card bead metadata is added to the catalog. New cards inherit the rules
from their runtime ability declarations automatically.

## Runtime Refresh

The existing face-content refresh path recomputes the presentation whenever
card data is configured or synchronized, ki changes, an ability is visibly
removed, or face-down state changes. This ensures retained abilities,
non-retained ability loss, and temporary protection expiry are reflected
without a separate UI state cache.

## Verification

Pure query tests cover:

- every row of the presentation table;
- gold-over-light precedence;
- activate ability zero display;
- passive trigger zero-number suppression;
- positive ki without a qualifying ability;
- exact own-summon-only exclusion;
- mixed and multiple abilities; and
- runtime ability removal.

Card-view tests cover:

- light, dark, gold, and hidden styles;
- value-label visibility and text;
- face-down concealment;
- explicit bead disabling for library use;
- synchronization after ability and ki changes; and
- ki-gain presentation returning to the correct resting style.

Existing activate-card and duel presentation regression tests remain part of
the verification pass.
