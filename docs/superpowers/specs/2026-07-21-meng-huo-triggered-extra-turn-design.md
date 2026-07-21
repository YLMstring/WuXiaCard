# Meng Huo Triggered Ki and Extra Turn Design

## Goal

Give Meng Huo one non-retained triggered ability: whenever Meng Huo is the source of a flip that actually changes a target card's ownership, Meng Huo gains 1 ki. At the end of his owner's turn, every owned Meng Huo that still has this ability and at least 1 ki spends all of its ki, and their owner receives one extra turn total.

This feature also establishes a small generic trigger, condition, and action framework for future declarative card abilities. The framework implements only the event, condition, and action types required by this feature; it is not a general scripting language.

## Approved Rules

- Meng Huo gains exactly 1 ki for each target that actually changes ownership through a flip caused by that Meng Huo.
- Failed comparisons, prevented flips, exile, removal, and any other replacement that does not change ownership grant no ki.
- Multiple successful flips grant ki separately in canonical top, right, bottom, left resolution order.
- Board-cell iteration is row-major: `0, 1, 2` across the top row from left to right, then `3, 4, 5` across the middle row, then `6, 7, 8` across the bottom row.
- Future combo or effect resolution also grants ki when it identifies Meng Huo as the source of an actual ownership-changing flip.
- Meng Huo does not need to start with ki. His catalog definition continues to default to `starting_ki = 0`.
- At the end of the acting owner's turn, every owned face-up board card with the end-turn trigger, its ability still active, and `ki >= 1` is eligible.
- All eligible cards spend all their current ki.
- Any number of eligible Meng Huos grants exactly one extra turn total, not one extra turn per card.
- An extra turn is a normal turn containing one play or activate action.
- If Meng Huo gains ki during an extra turn, its end-turn trigger may grant another extra turn. Chained extra turns are allowed.
- If the extra-turn owner has no legal action after resolution, the extra turn expires and normal passing chooses the next owner with a legal action.
- Flipping Meng Huo removes the entire triggered ability because it uses the default `retained_on_flip = false` behavior.
- Ability loss does not remove stored ki. A Meng Huo that has lost the ability can neither gain ki from flips nor spend ki for an extra turn.
- `turn_count` continues to count completed actions. Granting an extra turn does not increment it; the action taken during that extra turn does.

## Catalog Schema

Meng Huo declares one ability with generic trigger rules:

```gdscript
{
	"id": &"battle_momentum",
	"triggers": [
		{
			"event": &"after_successful_flip_by_self",
			"actions": [
				{"type": &"gain_ki", "amount": 1},
			],
		},
		{
			"event": &"end_owner_turn",
			"condition": {"ki_at_least": 1},
			"actions": [
				{"type": &"spend_all_ki"},
				{"type": &"request_extra_turn"},
			],
		},
	],
}
```

The ability omits `retained_on_flip`, so runtime normalization sets it to `false`. Both trigger rules live in the same ability dictionary and are therefore lost together.

The initial registries contain:

- events: `after_successful_flip_by_self`, `end_owner_turn`;
- conditions: `ki_at_least` with a nonnegative integer threshold;
- actions: `gain_ki` with a positive integer amount, `spend_all_ki`, and `request_extra_turn`.

Catalog validation rejects unknown event, condition, or action IDs; malformed trigger arrays; missing action arrays; non-integer or invalid thresholds and amounts; and action fields that do not match their registered schema.

## Trigger Architecture

Add a scene-free `DuelTriggers` module. It receives a `DuelState`, a trigger event ID, and a context dictionary. It scans active card abilities, evaluates matching rules, and returns deterministic matched-rule groups. Each group contains one source identity plus that rule's ordered effect commands. Trigger discovery and command resolution remain separate:

1. **Discovery** reads state, evaluates a rule's condition once, and produces a matched-rule group without mutating state.
2. **Resolution** revalidates the group's source identity, owner, active ability, and condition once against the current copied state. If valid, it executes every command in that group sequentially without re-evaluating the condition between commands.

Matched-rule groups and their commands contain pure values:

- action type;
- source owner;
- source board cell;
- source instance ID;
- source ability ID;
- numeric amount when required.

Stable instance IDs prevent stale source cells from applying commands to a replacement card. Unsupported, missing, removed, wrong-owner, ability-lost, or no-longer-condition-matching groups are ignored without mutation. This group-level rule is important at end of turn: `ki_at_least` is checked before `spend_all_ki`, and the following `request_extra_turn` command remains part of the same valid group even though the spend has reduced ki to zero.

For `after_successful_flip_by_self`, discovery examines only the identified source card. For `end_owner_turn`, discovery scans board cells in row-major order—left to right across the top row, then the middle row, then the bottom row—and considers only cards currently owned by the acting owner. This is the existing ascending index order `0` through `8`.

## Successful Flip Resolution

The existing attack pipeline remains authoritative for whether a flip actually occurred. After each `resolve_flip_attempt` call:

1. Append the resulting `card_flipped` event and any target `ability_lost` events.
2. Only if a `card_flipped` event exists, dispatch `after_successful_flip_by_self` with the attacking source's cell, instance ID, and owner.
3. Resolve generated `gain_ki` commands against that source.
4. Increment the source card's ki and emit `ki_changed` with previous and resulting values.
5. Continue to the next attack target.

This preserves top, right, bottom, left ordering. Each target's flip and ability-loss events precede the corresponding source ki gain. Exile and other non-flip results never dispatch the successful-flip trigger.

Future combo/effect code must call the same successful-flip dispatch after an actual `card_flipped` result and supply the real source identity. It must not simulate ki gain directly.

## End-of-Turn Resolution

Every successful play or activate action uses one centralized finish-turn pipeline:

1. Complete all on-play, movement, flip, exile, draw, and triggered ki-gain effects.
2. Dispatch `end_owner_turn` for the acting owner.
3. Discover eligible sources in ascending board-cell order.
4. For each matched source, revalidate its whole rule group once, then execute `spend_all_ki` followed by `request_extra_turn` sequentially. Spending sets that source's ki to `0` and emits `ki_changed` with previous and resulting values.
5. Coalesce the request tokens produced by every valid source group for the acting owner into one request.
6. Emit one `extra_turn_granted` event when at least one request remains valid.
7. Increment `turn_count` and `state_version` once for the completed action.
8. If an extra turn was granted and the acting owner has any legal action, keep that owner active.
9. Otherwise, use the existing legal-action pass logic to choose the next active owner.

All eligible Meng Huos spend their ki even though their duplicate extra-turn requests are coalesced. A source that becomes invalid before command resolution neither spends ki nor contributes a request.

The pipeline repeats normally after an action taken during an extra turn, enabling approved extra-turn chains. The existing maximum-turn safeguard still terminates pathological chains.

## Simulator, Terminal State, and AI

The simulator remains the sole authority for trigger resolution and extra-turn ownership. Controller code only presents emitted events.

Legal actions are unchanged. Extra-turn state is represented by the resulting `active_player`, so no separate pending choice or player input mode is needed.

Terminal evaluation occurs after end-turn triggers resolve. A granted extra turn does not keep a match alive when the granted owner has no legal action. Normal both-owners-stuck and maximum-turn rules remain unchanged.

Greedy AI receives the fully resolved transition, including ki spend and repeated active player. It does not receive a special extra-turn heuristic in this feature. Deep search naturally explores the same owner acting again because it already follows `DuelState.active_player` rather than assuming strict alternation.

State duplication deep-copies all ki, active abilities, queued events, and board data, so trigger resolution in one search branch cannot affect its source or sibling branches.

## Presentation

Presentation remains restrained and uses existing UI elements:

- After the corresponding capture and target ability-loss animation, a `ki_changed` gain event updates Meng Huo's jade bead and plays one brief green bead pulse.
- At end of turn, each eligible Meng Huo's `ki_changed` event drains its bead to `0` in board-cell order.
- One `extra_turn_granted` event briefly changes the turn label to `Extra turn`, then normal player or opponent turn text resumes.
- No new sound is added.
- Face-down cards continue hiding ki.

The controller resolves event sources by stable instance ID, not only by the event's historical board cell. This keeps ki presentation correct after movement and future effects that reposition cards.

Input remains locked while end-turn ki drains and extra-turn feedback are presented. The controller then reads the simulator's resulting `active_player`, restores the appropriate hand and board-card playability, and lets that owner take one normal action.

## Failure and Edge Handling

- Unknown trigger, condition, or action data fails catalog validation.
- Missing or stale source identity produces no command mutation.
- A removed, exiled, wrong-owner, or ability-lost source cannot gain or spend ki.
- Zero-ki sources do not request an extra turn.
- Exile and removal do not masquerade as successful flips.
- Multiple flips by one Meng Huo gain ki once per actual ownership change.
- Multiple eligible Meng Huos all drain but yield one extra turn.
- A Meng Huo with retained ki but no ability displays the resource but does not participate in triggers.
- An owner with no legal action cannot retain an unusable extra turn.
- Repeated extra turns remain bounded by `max_turns`.

## Verification

Catalog tests verify:

- Meng Huo declares `battle_momentum` with both approved triggers;
- the ability normalizes to non-retained;
- all registered event, condition, and action shapes pass validation;
- unknown and malformed trigger data fails validation.

Trigger and simulator tests verify:

- one ki per actual ownership-changing flip;
- multiple flips gain multiple ki in canonical order;
- exile, removal, failed, and prevented flips grant no ki;
- source identity and ability presence are revalidated;
- end-turn resolution spends all ki from every eligible Meng Huo;
- multiple requests coalesce into one extra turn;
- extra-turn actions can generate and spend new ki for another extra turn;
- flipping Meng Huo removes the ability while preserving ki;
- an unusable extra turn expires through normal pass logic;
- invalid trigger commands leave the source state untouched;
- copied search states remain isolated;
- greedy and deep search accept repeated active-player transitions.

Integration and playtesting verify:

- the bead increments after capture presentation and pulses once per gain;
- end-turn drains display in board order;
- the status displays `Extra turn` exactly once for multiple Meng Huos;
- player, AI, and testing-mode repeated turns use the production action path;
- face-down hands leak no ki;
- existing play, activate, draw, exile, ability-loss, score, and match-completion behavior remains intact;
- no runtime errors occur during chained extra-turn play.

## Out of Scope

- A fully expressive condition language, nested Boolean conditions, arbitrary arithmetic, or user-authored scripts.
- Trigger priorities, interrupts, reactions, or player choices during trigger resolution.
- Extra-turn limits beyond the existing maximum-turn safeguard.
- New sounds or card artwork.
- AI evaluation changes beyond resolving and searching the correct resulting state.
