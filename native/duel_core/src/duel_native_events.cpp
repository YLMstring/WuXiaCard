#include "duel_native_compact_kernel_internal.h"

namespace godot {
using namespace duel_native_internal;

// 本模块负责触发的发现、条件匹配与顺序结算。
// 发现阶段保存语义快照，结算阶段再确认能力条目仍然有效。

bool DuelNativeCompactKernel::conditions_match(
	const NativeState &value,
	const EventGroup &group,
	const CompiledTriggerRule &rule,
	const EventContext &context,
	bool &supported
) const {
	supported = true;
	for (const CompiledCondition &condition : rule.conditions) {
		bool matched = false;
		switch (condition.opcode) {
			case ConditionOpcode::TRIGGER_CARD_IS_SELF:
				matched = context.trigger_card_index == group.source_card_index;
				break;
			case ConditionOpcode::TRIGGER_CARD_IS_ALLY:
			case ConditionOpcode::TRIGGER_CARD_IS_ENEMY: {
				const bool expects_ally = condition.opcode == ConditionOpcode::TRIGGER_CARD_IS_ALLY;
				const bool is_summon_event = (
					rule.event_id == StringName("card_before_summoned")
					|| rule.event_id == StringName("card_summoned")
					|| rule.event_id == StringName("card_after_summoned")
				);
				if (!is_summon_event) {
					// 普通事件的敌我关系是事件快照；触发牌随后移区、换格或离场，
					// 都不改变已经发生的“某方卡牌触发了此事件”。
					matched = (
						(context.trigger_owner == 1 || context.trigger_owner == 2)
						&& ((context.trigger_owner == group.source_owner) == expects_ally)
					);
					break;
				}
				const int32_t trigger_cell = find_board_card(value, context.trigger_card_index, -1);
				const bool entered_as_ally = context.trigger_previous_owner == group.source_owner;
				// 进场阵营条件同时要求“最初如此”和“现在仍如此”。精确实例可以在
				// 进场连锁中换格，但离场或翻成另一方都会使该条件失效。
				matched = (
					trigger_cell >= 0
					&& (context.trigger_previous_owner == 1 || context.trigger_previous_owner == 2)
					&& entered_as_ally == expects_ally
					&& ((value.board_owners[trigger_cell] == group.source_owner) == expects_ally)
				);
				break;
			}
			case ConditionOpcode::TRIGGER_CARD_IN_RANGE: {
				const int32_t trigger_cell = find_board_card(value, context.trigger_card_index, -1);
				AttackPolicy policy;
				matched = (
					trigger_cell >= 0
					&& is_target_in_attack_range(
						value,
						group.source_cell,
						trigger_cell,
						policy,
						false
					)
				);
				break;
			}
			case ConditionOpcode::TRIGGER_CARD_ADJACENT_TO_SOURCE: {
				const int32_t trigger_cell = find_board_card(value, context.trigger_card_index, -1);
				for (int32_t direction = 0; trigger_cell >= 0 && direction < 4; ++direction) {
					if (neighbor_index(group.source_cell, direction) == trigger_cell) {
						matched = true;
						break;
					}
				}
				break;
			}
			case ConditionOpcode::EXILE_EFFECT_SOURCE_IS_ALLY:
				matched = (
					context.exile_effect_source_owner != 0
					&& context.exile_effect_source_owner == group.source_owner
				);
				break;
			case ConditionOpcode::TRIGGER_CARD_REVEALED_TO_SELF:
				if (
					context.trigger_card_index >= 0
					&& context.trigger_card_index < static_cast<int32_t>(value.card_reveal_codes.size())
				) {
					matched = reveal_code_contains(
						value.card_reveal_codes[context.trigger_card_index],
						group.source_owner
					);
				}
				break;
			case ConditionOpcode::TRIGGER_CARD_WAS_ENEMY: {
				const int32_t previous_owner = (
					context.trigger_previous_owner != 0
					? context.trigger_previous_owner
					: context.trigger_owner
				);
				matched = previous_owner != 0 && previous_owner != group.source_owner;
				break;
			}
			case ConditionOpcode::TRIGGER_CARD_ORIGINAL_OWNER_IS_SELF:
				matched = (
					context.trigger_card_index >= 0
					&& context.trigger_card_index < static_cast<int32_t>(value.card_original_owners.size())
					&& value.card_original_owners[context.trigger_card_index] == group.source_owner
				);
				break;
			case ConditionOpcode::ATTACKER_CARD_IS_SELF:
				matched = context.attacker_card_index == group.source_card_index;
				break;
			case ConditionOpcode::ATTACKER_CARD_IS_ENEMY:
				matched = context.attacker_owner != 0 && context.attacker_owner != group.source_owner;
				break;
			case ConditionOpcode::ATTACKER_CARD_IS_OTHER_ALLY:
				matched = (
					context.attacker_card_index >= 0
					&& context.attacker_card_index != group.source_card_index
					&& context.attacker_owner == group.source_owner
				);
				break;
			case ConditionOpcode::ATTACK_IS_NOT_REPEAT:
				matched = !context.repeat_attack;
				break;
			case ConditionOpcode::ACTIVATION_OWNER_IS_ALLY:
				matched = (
					(context.activation_owner == 1 || context.activation_owner == 2)
					&& context.activation_owner == group.source_owner
				);
				break;
			case ConditionOpcode::TRIGGER_CARD_WAS_ON_BOARD:
				matched = context.trigger_was_on_board;
				break;
			case ConditionOpcode::ATTACK_FLIPPED_ENEMY:
				matched = context.attack_flipped_enemy;
				break;
			case ConditionOpcode::ATTACK_FLIPPED_ANY_CARD:
				matched = condition.inverted
					? !context.attack_flipped_any_card
					: context.attack_flipped_any_card;
				break;
			case ConditionOpcode::ATTACK_FLIPPED_ALLY_IN_RANGE: {
				AttackPolicy policy;
				for (const EventContext::AttackFlipRecord &record : context.attack_flips) {
					if (record.previous_owner != group.source_owner) continue;
					const int32_t target_cell = find_board_card(value, record.card_index, -1);
					if (
						target_cell >= 0
						&& is_target_in_attack_range(
							value,
							group.source_cell,
							target_cell,
							policy,
							false
						)
					) {
						matched = true;
						break;
					}
				}
				break;
			}
			case ConditionOpcode::TRIGGER_CARD_POWERS_COULD_CHANGE:
				matched = context.trigger_card_index >= 0 && can_change_powers(value, context.trigger_card_index);
				break;
			case ConditionOpcode::POWER_INCREASE_BATCH_INCLUDES_ALLY:
				matched = (
					group.source_owner >= 1
					&& group.source_owner <= 2
					&& (context.power_increase_owner_mask & (1u << (group.source_owner - 1))) != 0
				);
				break;
			case ConditionOpcode::TRIGGER_CARD_WEAPON:
				if (
					context.trigger_card_index >= 0
					&& context.trigger_card_index < static_cast<int32_t>(value.card_template_indices.size())
				) {
					const int32_t template_index = value.card_template_indices[context.trigger_card_index];
					if (template_index >= 0 && template_index < value.card_template_pool.size()) {
						const Variant template_value = value.card_template_pool[template_index];
						if (template_value.get_type() == Variant::DICTIONARY) {
							const Dictionary card_template = template_value;
							const bool weapon_matches = (
								String(card_template.get("weapon", String())) == condition.weapon
							);
							matched = condition.inverted ? !weapon_matches : weapon_matches;
						}
					}
				}
				break;
			case ConditionOpcode::DRAWN_CARD_IS_ENEMY:
				matched = context.trigger_owner != 0 && context.trigger_owner != group.source_owner;
				break;
			case ConditionOpcode::TURN_OWNER_IS_SELF:
				matched = context.turn_owner != 0 && context.turn_owner == group.source_owner;
				break;
			case ConditionOpcode::OWNER_DID_NOT_WIN:
				matched = std::find(
					context.winning_owners.begin(),
					context.winning_owners.end(),
					group.source_owner
				) == context.winning_owners.end();
				break;
			case ConditionOpcode::KI_AT_LEAST:
				matched = value.card_ki[group.source_card_index] >= condition.amount;
				if (condition.inverted) matched = !matched;
				break;
			case ConditionOpcode::MOVING_CARD_IS_SELF:
				matched = (
					context.moving_card_index == group.source_card_index
					&& context.moving_source_cell == group.source_cell
				);
				break;
			case ConditionOpcode::MOVING_CARD_IS_ALLY:
				matched = (
					context.moving_card_index >= 0
					&& (context.moving_owner == 1 || context.moving_owner == 2)
					&& context.moving_owner == group.source_owner
				);
				break;
			case ConditionOpcode::DISCARD_OWNER_IS_SELF:
				matched = context.discard_owner != 0 && context.discard_owner == group.source_owner;
				break;
			case ConditionOpcode::ABILITY_SOURCE_IN_ZONE: {
				int32_t current_zone = -1;
				int32_t current_owner = 0;
				int32_t current_logical_index = -1;
				matched = locate_card(
					value,
					group.source_card_index,
					current_zone,
					current_owner,
					current_logical_index
				) && current_zone == condition.amount;
				if (condition.inverted) matched = !matched;
				break;
			}
			case ConditionOpcode::SOURCE_HAS_ADJACENT_EMPTY_CELL:
				for (int32_t direction = 0; direction < 4; ++direction) {
					const int32_t candidate = neighbor_index(group.source_cell, direction);
					if (candidate >= 0 && value.board_card_indices[candidate] < 0) {
						matched = true;
						break;
					}
				}
				break;
			case ConditionOpcode::SOURCE_HAS_EMPTY_BETWEEN_ENEMY:
				for (int32_t direction = 0; direction < 4; ++direction) {
					const int32_t middle = neighbor_index(group.source_cell, direction);
					if (middle < 0 || value.board_card_indices[middle] >= 0) continue;
					const int32_t far = neighbor_index(middle, direction);
					if (
						far >= 0
						&& value.board_card_indices[far] >= 0
						&& value.board_owners[far] != group.source_owner
					) {
						matched = true;
						break;
					}
				}
				break;
			default:
				supported = false;
				return false;
		}
		if (!matched) return false;
	}
	return true;
}

std::vector<DuelNativeCompactKernel::EventGroup> DuelNativeCompactKernel::discover_event(
	const NativeState &value,
	const StringName &event_id,
	const EventContext &context,
	bool &supported,
	String &reason
) const {
	// 普通事件只扫描场上九格；唯有对局开始扫描双方手牌，弃牌后只检查那张弃牌，
	// 进场前只检查正在进场的牌。CARD_AFTER_SUMMONED 属于普通事件，必须扫描全场。
	std::vector<EventGroup> groups;
	supported = true;
	auto discover_card = [&](int32_t card_index, int32_t owner_id, int32_t source_cell, int32_t source_zone, int32_t logical_index, bool enforce_active_zone = true) -> bool {
		if (!card_effects_enabled(value, card_index, owner_id)) return true;
		for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[card_index].size(); ++ability_index) {
			const CompiledAbility *ability = runtime_ability(value, card_index, static_cast<int32_t>(ability_index));
			if (
				ability == nullptr
				|| (enforce_active_zone && !ability_active_in_zone(*ability, source_zone))
			) continue;
			for (size_t trigger_index = 0; trigger_index < ability->triggers.size(); ++trigger_index) {
				const CompiledTriggerRule &rule = ability->triggers[trigger_index];
				if (rule.event_id != event_id) continue;
				EventGroup group;
				group.source_cell = source_cell;
				group.source_zone = source_zone;
				group.source_logical_index = logical_index;
				group.source_card_index = card_index;
				group.source_owner = owner_id;
				group.ability_index = static_cast<int32_t>(ability_index);
				group.ability_handle = value.card_runtime_abilities[card_index][ability_index].handle;
				group.trigger_index = static_cast<int32_t>(trigger_index);
				bool condition_supported = true;
				if (conditions_match(value, group, rule, context, condition_supported)) {
					groups.push_back(group);
				} else if (!condition_supported) {
					supported = false;
					reason = "Relevant event uses an unsupported trigger condition";
					return false;
				}
			}
		}
		return true;
	};
	auto physical_hand_indices = [&](int32_t owner_id) {
		std::vector<int32_t> logical_indices;
		const std::vector<int32_t> &hand = value.zones[owner_id - 1];
		logical_indices.reserve(hand.size());
		for (size_t index = 0; index < hand.size(); ++index) {
			logical_indices.push_back(static_cast<int32_t>(index));
		}
		std::stable_sort(logical_indices.begin(), logical_indices.end(), [&](int32_t first, int32_t second) {
			const int32_t first_card = hand[first];
			const int32_t second_card = hand[second];
			const int32_t first_slot = value.card_hand_slots[first_card] >= 0
				? value.card_hand_slots[first_card]
				: first;
			const int32_t second_slot = value.card_hand_slots[second_card] >= 0
				? value.card_hand_slots[second_card]
				: second;
			return first_slot == second_slot ? first < second : first_slot < second_slot;
		});
		return logical_indices;
	};
	bool used_exact_card_entry = false;
	if (event_id == StringName("card_after_discarded")) {
		used_exact_card_entry = true;
		int32_t zone = -1;
		int32_t owner_id = 0;
		int32_t logical_index = -1;
		if (
			context.trigger_card_index >= 0
			&& locate_card(value, context.trigger_card_index, zone, owner_id, logical_index)
			&& zone == 3
			&& owner_id == context.trigger_owner
		) discover_card(context.trigger_card_index, owner_id, -1, 3, logical_index, false);
	} else if (event_id == StringName("card_before_summoned")) {
		used_exact_card_entry = true;
		const int32_t trigger_cell = find_board_card(value, context.trigger_card_index, context.trigger_cell);
		if (trigger_cell == context.trigger_cell && trigger_cell >= 0) {
			discover_card(
				context.trigger_card_index,
				value.board_owners[trigger_cell],
				trigger_cell,
				0,
				trigger_cell
			);
		}
	} else if (event_id == StringName("duel_started")) {
		used_exact_card_entry = true;
		for (int32_t owner_id = 1; owner_id <= 2; ++owner_id) {
			const std::vector<int32_t> &hand = value.zones[owner_id - 1];
			for (const int32_t logical_index : physical_hand_indices(owner_id)) {
				discover_card(hand[logical_index], owner_id, -1, 1, logical_index, false);
				if (!supported) return groups;
			}
		}
	}
	if (!used_exact_card_entry) {
		for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
			const int32_t card_index = value.board_card_indices[cell];
			if (card_index < 0) continue;
			discover_card(
				card_index,
				value.board_owners[cell],
				static_cast<int32_t>(cell),
				0,
				static_cast<int32_t>(cell)
			);
			if (!supported) return groups;
		}
	}
	for (int32_t aura_owner = 1; aura_owner <= 2; ++aura_owner) {
		// 光环是牌手的运行时状态，不属于来源牌的能力列表。来源牌引用只用于显示
		// 和 action 语义；来源牌翻面、移区或失去能力不会让已授予的牌手光环失效。
		for (const RuntimeOwnerAuraEntry &entry : value.owner_auras[aura_owner - 1]) {
			if (
				entry.compiled_ability_index < 0
				|| entry.compiled_ability_index >= static_cast<int32_t>(compiled_ability_pool.size())
			) continue;
			const CompiledAbility &aura = compiled_ability_pool[entry.compiled_ability_index];
			for (size_t trigger_index = 0; trigger_index < aura.triggers.size(); ++trigger_index) {
				const CompiledTriggerRule &rule = aura.triggers[trigger_index];
				if (rule.event_id != event_id) continue;
				EventGroup group;
				group.source_card_index = entry.source_card_index;
				group.source_owner = aura_owner;
				group.trigger_index = static_cast<int32_t>(trigger_index);
				group.owner_aura_owner = aura_owner;
				group.owner_aura_source_card_index = entry.source_card_index;
				group.owner_aura_handle = entry.handle;
				int32_t located_owner = 0;
				locate_card(value, entry.source_card_index, group.source_zone, located_owner, group.source_logical_index);
				group.source_cell = group.source_zone == 0 ? group.source_logical_index : -1;
				bool condition_supported = true;
				if (conditions_match(value, group, rule, context, condition_supported)) {
					groups.push_back(group);
				} else if (!condition_supported) {
					supported = false;
					reason = "Owner aura event uses an unsupported trigger condition";
					return groups;
				}
			}
		}
	}
	for (size_t recipient_cell = 0; recipient_cell < value.board_card_indices.size(); ++recipient_cell) {
		const int32_t recipient_card = value.board_card_indices[recipient_cell];
		if (recipient_card < 0) continue;
		const int32_t recipient_owner = value.board_owners[recipient_cell];
		for (int32_t provider_owner = 1; provider_owner <= 2; ++provider_owner) {
			for (const RuntimeOwnerAuraEntry &provider_entry : value.owner_auras[provider_owner - 1]) {
				if (
					provider_entry.compiled_ability_index < 0
					|| provider_entry.compiled_ability_index >= static_cast<int32_t>(compiled_ability_pool.size())
				) continue;
				const CompiledAbility &provider_ability = compiled_ability_pool[provider_entry.compiled_ability_index];
				for (size_t nested_index = 0; nested_index < provider_ability.auras.size(); ++nested_index) {
					const CompiledAura &aura = provider_ability.auras[nested_index];
						if (
							aura.ability_pool_index < 0
							|| aura.ability_pool_index >= static_cast<int32_t>(compiled_ability_pool.size())
							|| std::find(
								aura.selector.zones.begin(),
								aura.selector.zones.end(),
								SelectorZoneOpcode::BOARD
							) == aura.selector.zones.end()
						) continue;
						ActionContext selector_context;
						int32_t provider_zone = -1;
						int32_t provider_current_owner = 0;
						int32_t provider_logical_index = -1;
						locate_card(value, provider_entry.source_card_index, provider_zone, provider_current_owner, provider_logical_index);
						selector_context.ability_source_cell = provider_zone == 0 ? provider_logical_index : -1;
						selector_context.ability_source_zone = provider_zone;
						selector_context.ability_source_logical_index = provider_logical_index;
						selector_context.ability_source_card_index = provider_entry.source_card_index;
						selector_context.ability_source_owner = provider_owner;
						selector_context.action_subject_card_index = provider_entry.source_card_index;
						selector_context.action_subject_owner = provider_owner;
						selector_context.action_subject_zone = provider_zone;
						selector_context.action_subject_logical_index = provider_logical_index;
						bool selector_supported = true;
						if (!selector_conditions_match(
							value,
							recipient_card,
							0,
							recipient_owner,
							static_cast<int32_t>(recipient_cell),
							aura.selector,
							selector_context,
							selector_supported
						)) {
							if (!selector_supported) {
								supported = false;
								reason = "Aura selector uses an unsupported condition";
								return groups;
							}
							continue;
						}
						const CompiledAbility &granted = compiled_ability_pool[aura.ability_pool_index];
						for (size_t trigger_index = 0; trigger_index < granted.triggers.size(); ++trigger_index) {
							const CompiledTriggerRule &rule = granted.triggers[trigger_index];
							if (rule.event_id != event_id) continue;
							EventGroup group;
							group.source_cell = static_cast<int32_t>(recipient_cell);
							group.source_zone = 0;
							group.source_logical_index = static_cast<int32_t>(recipient_cell);
							group.source_card_index = recipient_card;
							group.source_owner = recipient_owner;
							group.trigger_index = static_cast<int32_t>(trigger_index);
							group.virtual_ability_pool_index = aura.ability_pool_index;
							group.owner_aura_owner = provider_owner;
							group.owner_aura_source_card_index = provider_entry.source_card_index;
							group.owner_aura_handle = provider_entry.handle;
							group.owner_aura_nested_index = static_cast<int32_t>(nested_index);
							bool condition_supported = true;
							if (conditions_match(value, group, rule, context, condition_supported)) {
								groups.push_back(group);
							} else if (!condition_supported) {
								supported = false;
								reason = "Aura event uses an unsupported trigger condition";
								return groups;
							}
						}
				}
			}
		}
	}
	return groups;
}

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::resolve_event(
	NativeState &value,
	const StringName &event_id,
	const EventContext &context,
	std::vector<int32_t> &exile_stack
) const {
	// 先一次性发现全部触发，再按发现顺序执行。前一条触发可以改变后续来源位置、
	// 所属方或能力列表，但不会重新扫描并把新出现的能力插入本次事件。
	ScopedTransitionTiming event_timing(
		active_transition_timing,
		TransitionTimingBucket::EVENT_DISPATCH
	);
	Resolution resolution;
	bool discovery_supported = true;
	String discovery_reason;
	std::vector<EventGroup> groups;
	{
		ScopedTransitionTiming discovery_timing(
			active_transition_timing,
			TransitionTimingBucket::EVENT_DISCOVERY
		);
		groups = discover_event(
			value,
			event_id,
			context,
			discovery_supported,
			discovery_reason
		);
	}
	if (!discovery_supported) {
		resolution.supported = false;
		resolution.reason = discovery_reason;
		return resolution;
	}
	for (const EventGroup &discovered_group : groups) {
		EventGroup group = discovered_group;
		const bool virtual_ability = group.virtual_ability_pool_index >= 0;
		const bool owner_aura = group.owner_aura_handle != 0;
		int32_t current_ability_index = -1;
		int32_t current_logical_index = group.source_logical_index;
		const CompiledAbility *ability = nullptr;
		if (owner_aura) {
			const RuntimeOwnerAuraEntry *entry = owner_aura_by_handle(
				value,
				group.owner_aura_owner,
				group.owner_aura_handle
			);
			if (
				entry == nullptr
				|| entry->compiled_ability_index < 0
				|| entry->compiled_ability_index >= static_cast<int32_t>(compiled_ability_pool.size())
			) continue;
			if (virtual_ability) {
				const CompiledAbility &provider = compiled_ability_pool[entry->compiled_ability_index];
				if (
					group.owner_aura_nested_index < 0
					|| group.owner_aura_nested_index >= static_cast<int32_t>(provider.auras.size())
				) continue;
				const CompiledAura &nested = provider.auras[group.owner_aura_nested_index];
				if (nested.ability_pool_index != group.virtual_ability_pool_index) continue;
				int32_t current_zone = -1;
				int32_t current_owner = 0;
				if (
					!locate_card(value, group.source_card_index, current_zone, current_owner, current_logical_index)
					|| current_zone != group.source_zone
				) continue;
				group.source_owner = current_owner;
				group.source_logical_index = current_logical_index;
				group.source_cell = current_zone == 0 ? current_logical_index : -1;
				ActionContext selector_context;
				int32_t provider_zone = -1;
				int32_t provider_current_owner = 0;
				int32_t provider_logical_index = -1;
				locate_card(value, entry->source_card_index, provider_zone, provider_current_owner, provider_logical_index);
				selector_context.ability_source_cell = provider_zone == 0 ? provider_logical_index : -1;
				selector_context.ability_source_zone = provider_zone;
				selector_context.ability_source_logical_index = provider_logical_index;
				selector_context.ability_source_card_index = entry->source_card_index;
				selector_context.ability_source_owner = group.owner_aura_owner;
				selector_context.action_subject_card_index = entry->source_card_index;
				selector_context.action_subject_owner = group.owner_aura_owner;
				selector_context.action_subject_zone = provider_zone;
				selector_context.action_subject_logical_index = provider_logical_index;
				selector_context.selected_card_index = group.source_card_index;
				selector_context.selected_card_owner = current_owner;
				selector_context.selected_card_zone = current_zone;
				selector_context.selected_card_logical_index = current_logical_index;
				bool selector_supported = true;
				if (!selector_conditions_match(
					value,
					group.source_card_index,
					current_zone,
					current_owner,
					current_logical_index,
					nested.selector,
					selector_context,
					selector_supported
				)) {
					if (!selector_supported) {
						resolution.supported = false;
						resolution.reason = "Aura selector uses an unsupported condition";
						return resolution;
					}
					continue;
				}
				ability = &compiled_ability_pool[group.virtual_ability_pool_index];
			} else {
				group.source_card_index = entry->source_card_index;
				group.source_owner = group.owner_aura_owner;
				int32_t current_zone = -1;
				int32_t ignored_owner = 0;
				if (locate_card(value, entry->source_card_index, current_zone, ignored_owner, current_logical_index)) {
					group.source_zone = current_zone;
					group.source_logical_index = current_logical_index;
					group.source_cell = current_zone == 0 ? current_logical_index : -1;
				}
				ability = &compiled_ability_pool[entry->compiled_ability_index];
			}
		} else {
			// 普通卡牌触发只重新确认两件事：来源实例仍在发现时的同一区域，且原
			// ability_handle 仍存在。场上换格合法；所属方以结算时为准；效果门控
			// 不再复查。这样前序效果不会仅因换位或翻面而取消已发现触发。
			int32_t current_zone = -1;
			int32_t current_owner = 0;
			if (!locate_card(
				value,
				group.source_card_index,
				current_zone,
				current_owner,
				current_logical_index
			) || current_zone != group.source_zone) continue;
			group.source_owner = current_owner;
			group.source_logical_index = current_logical_index;
			group.source_cell = current_zone == 0 ? current_logical_index : -1;
			current_ability_index = find_runtime_ability_index(
				value,
				group.source_card_index,
				group.ability_handle,
				group.ability_index
			);
			if (current_ability_index < 0) continue;
			ability = runtime_ability(value, group.source_card_index, current_ability_index);
		}
		if (
			ability == nullptr
			|| group.trigger_index < 0
			|| group.trigger_index >= static_cast<int32_t>(ability->triggers.size())
		) continue;
		const CompiledTriggerRule &rule = ability->triggers[group.trigger_index];
		bool condition_supported = true;
		if (!conditions_match(value, group, rule, context, condition_supported)) {
			if (!condition_supported) {
				resolution.supported = false;
				resolution.reason = "Relevant event uses an unsupported trigger condition";
				return resolution;
			}
			continue;
		}
		Dictionary triggered;
		triggered["type"] = StringName("ability_triggered");
		triggered["source_cell"] = group.source_cell;
		triggered["source_instance_id"] = value.card_instance_ids[group.source_card_index];
		triggered["source_owner_id"] = group.source_owner;
		resolution.events.append(triggered);
		ActionContext action_context;
		if (!owner_aura && context.ability_source_card_index >= 0) {
			action_context.ability_source_cell = context.ability_source_cell;
			action_context.ability_source_zone = context.ability_source_zone;
			action_context.ability_source_logical_index = context.ability_source_logical_index;
			action_context.ability_source_card_index = context.ability_source_card_index;
			action_context.ability_source_owner = context.ability_source_owner;
		} else {
			action_context.ability_source_cell = group.source_cell;
			action_context.ability_source_zone = group.source_zone;
			action_context.ability_source_logical_index = current_logical_index;
			action_context.ability_source_card_index = group.source_card_index;
			action_context.ability_source_owner = group.source_owner;
		}
		action_context.action_subject_card_index = group.source_card_index;
		action_context.action_subject_owner = group.source_owner;
		action_context.action_subject_zone = group.source_zone;
		action_context.action_subject_logical_index = current_logical_index;
		action_context.trigger_card_index = context.trigger_card_index;
		action_context.attacker_card_index = context.attacker_card_index;
		action_context.activation_target_kind = context.activation_target_kind;
		action_context.activation_target_index = context.activation_target_index;
		action_context.event_id = event_id;
		action_context.discovery_ability_index = group.ability_index;
		action_context.trigger_index = group.trigger_index;
		action_context.attack_flips = context.attack_flips;
		const ActionOutcome outcome = execute_actions(
			value,
			group,
			rule.actions,
			context,
			action_context,
			exile_stack,
			resolution
		);
		if (outcome == ActionOutcome::UNSUPPORTED) {
			resolution.supported = false;
			if (resolution.reason.is_empty()) resolution.reason = "Relevant event uses an unsupported action";
			return resolution;
		}
	}
	return resolution;
}


} // namespace godot
