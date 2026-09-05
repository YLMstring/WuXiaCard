#include "duel_native_compact_kernel_internal.h"

namespace godot {
using namespace duel_native_internal;

Array DuelNativeCompactKernel::get_legal_actions_for_owner(int64_t owner_id_value) const {
	Array actions;
	const int32_t owner_id = static_cast<int32_t>(owner_id_value);
	if (!loaded) return actions;
	for (const NativeAction &action : get_legal_native_actions(state, owner_id)) {
		actions.append(materialize_action(action));
	}
	return actions;
}

int64_t DuelNativeCompactKernel::count_legal_actions_for_owner(int64_t owner_id_value) const {
	if (!loaded) return 0;
	return count_legal_native_actions(state, static_cast<int32_t>(owner_id_value));
}


bool DuelNativeCompactKernel::is_action_legal_for_owner(
	const Dictionary &action_value,
	int64_t owner_id_value
) const {
	if (!loaded || action_value.is_empty()) return false;
	const StringName action_type = StringName(
		action_value.get("action_type", StringName())
	);
	const StringName source_zone = StringName(
		action_value.get("source_zone", StringName())
	);
	const StringName target_kind = StringName(
		action_value.get("target_kind", StringName())
	);
	NativeAction requested;
	if (action_type == StringName("play")) {
		if (source_zone != StringName("hand") || target_kind != StringName("board_cell")) {
			return false;
		}
		requested.type = NativeActionType::PLAY;
	} else if (action_type == StringName("activate")) {
		if (
			source_zone != StringName("board")
			|| (target_kind != StringName("board_cell") && target_kind != StringName("hand_slot"))
		) return false;
		requested.type = NativeActionType::ACTIVATE;
	} else {
		return false;
	}
	requested.source_index = static_cast<int32_t>(
		static_cast<int64_t>(action_value.get("source_index", -1))
	);
	requested.source_instance_id = StringName(
		action_value.get("source_instance_id", StringName())
	);
	requested.target_is_hand_slot = target_kind == StringName("hand_slot");
	requested.target_index = static_cast<int32_t>(
		static_cast<int64_t>(action_value.get("target_index", -1))
	);
	requested.activation_index = static_cast<int32_t>(
		static_cast<int64_t>(action_value.get("activation_index", 0))
	);
	for (const NativeAction &legal : get_legal_native_actions(
		state,
		static_cast<int32_t>(owner_id_value)
	)) {
		const bool instance_matches = requested.source_instance_id.is_empty()
			|| requested.source_instance_id == legal.source_instance_id;
		if (
			instance_matches
			&& requested.type == legal.type
			&& requested.source_index == legal.source_index
			&& requested.target_is_hand_slot == legal.target_is_hand_slot
			&& requested.target_index == legal.target_index
			&& requested.activation_index == legal.activation_index
		) return true;
	}
	return false;
}


bool DuelNativeCompactKernel::is_terminal_state() const {
	return !loaded || is_terminal(state);
}


int64_t DuelNativeCompactKernel::score_difference_for_owner(int64_t owner_id_value) const {
	if (!loaded) return 0;
	const int32_t owner_id = static_cast<int32_t>(owner_id_value);
	if (owner_id != 1 && owner_id != 2) return 0;
	const int32_t opponent_owner = owner_id == 1 ? 2 : 1;
	return count_owned(state, owner_id) - count_owned(state, opponent_owner);
}


Dictionary DuelNativeCompactKernel::choose_greedy_action_for_owner(int64_t owner_id_value) const {
	Dictionary result;
	if (!loaded) return result;
	const int32_t owner_id = static_cast<int32_t>(owner_id_value);
	if (owner_id != state.scalars[0]) return result;
	const std::vector<NativeAction> actions = get_legal_native_actions(state, owner_id);
	bool has_best = false;
	NativeAction best;
	int32_t best_score = std::numeric_limits<int32_t>::min();

	auto boundary_power = [&](const NativeAction &action) -> int32_t {
		if (action.type != NativeActionType::PLAY) return 0;
		const int32_t hand_zone = owner_id - 1;
		if (
			hand_zone < 0
			|| hand_zone >= static_cast<int32_t>(state.zones.size())
			|| action.source_index < 0
			|| action.source_index >= static_cast<int32_t>(state.zones[hand_zone].size())
		) return 0;
		const int32_t card_index = state.zones[hand_zone][action.source_index];
		if (card_index < 0) return 0;
		int32_t total = 0;
		for (int32_t direction = 0; direction < 4; ++direction) {
			if (neighbor_index(action.target_index, direction) < 0) {
				total += state.card_powers[card_index * 4 + direction];
			}
		}
		return total;
	};

	auto preferred_tie = [&](const NativeAction &candidate, const NativeAction &incumbent) -> bool {
		if (candidate.type != incumbent.type) return candidate.type == NativeActionType::PLAY;
		if (candidate.type == NativeActionType::PLAY) {
			const int32_t candidate_power = boundary_power(candidate);
			const int32_t incumbent_power = boundary_power(incumbent);
			if (candidate_power != incumbent_power) return candidate_power > incumbent_power;
		}
		if (candidate.source_index != incumbent.source_index) {
			return candidate.source_index < incumbent.source_index;
		}
		return candidate.target_index < incumbent.target_index;
	};

	for (const NativeAction &action : actions) {
		NativeState next;
		Resolution resolution;
		bool supported = false;
		String reason;
		if (!transition_action(state, action, next, resolution, supported, reason, false)) continue;
		const int32_t opponent_owner = owner_id == 1 ? 2 : 1;
		const int32_t score = count_owned(next, owner_id) - count_owned(next, opponent_owner);
		if (!has_best || score > best_score || (score == best_score && preferred_tie(action, best))) {
			has_best = true;
			best = action;
			best_score = score;
		}
	}
	return has_best ? materialize_action(best) : result;
}

Array DuelNativeCompactKernel::get_attack_targets_for_source(
	int64_t source_cell_value,
	const Dictionary &attack_policy
) const {
	Array result;
	if (!loaded) return result;
	const std::vector<int32_t> targets = get_attack_targets(
		state,
		static_cast<int32_t>(source_cell_value),
		attack_policy_from_dictionary(attack_policy)
	);
	for (const int32_t target : targets) result.append(target);
	return result;
}

bool DuelNativeCompactKernel::can_attack_target_cells(
	int64_t source_cell_value,
	int64_t target_cell_value,
	const Dictionary &attack_policy,
	bool skip_power_comparison
) const {
	return loaded && can_attack_target(
		state,
		static_cast<int32_t>(source_cell_value),
		static_cast<int32_t>(target_cell_value),
		attack_policy_from_dictionary(attack_policy),
		skip_power_comparison
	);
}

bool DuelNativeCompactKernel::is_target_in_attack_range_cells(
	int64_t source_cell_value,
	int64_t target_cell_value,
	const Dictionary &attack_policy,
	bool skip_power_comparison
) const {
	return loaded && is_target_in_attack_range(
		state,
		static_cast<int32_t>(source_cell_value),
		static_cast<int32_t>(target_cell_value),
		attack_policy_from_dictionary(attack_policy),
		skip_power_comparison
	);
}

Array DuelNativeCompactKernel::inspect_ordered_search_actions_for_owner(
	int64_t owner_id_value,
	const Dictionary &preferred_action
) const {
	Array result;
	if (!loaded) return result;
	const int32_t owner_id = static_cast<int32_t>(owner_id_value);
	NativeAction preferred;
	const NativeAction *preferred_pointer = nullptr;
	if (!preferred_action.is_empty()) {
		preferred.type = StringName(preferred_action.get("action_type", StringName("play")))
			== StringName("activate")
			? NativeActionType::ACTIVATE
			: NativeActionType::PLAY;
		preferred.source_index = static_cast<int32_t>(
			static_cast<int64_t>(preferred_action.get("source_index", -1))
		);
		preferred.source_instance_id = StringName(
			preferred_action.get("source_instance_id", StringName())
		);
		preferred.target_is_hand_slot = StringName(
			preferred_action.get("target_kind", StringName("board_cell"))
		) == StringName("hand_slot");
		preferred.target_index = static_cast<int32_t>(
			static_cast<int64_t>(preferred_action.get("target_index", -1))
		);
		preferred.activation_index = static_cast<int32_t>(
			static_cast<int64_t>(preferred_action.get("activation_index", 0))
		);
		preferred_pointer = &preferred;
	}
	auto actions = order_search_actions(
		state,
		get_legal_native_actions(state, owner_id),
		preferred_pointer
	);
	for (const NativeAction &action : actions) result.append(materialize_action(action));
	return result;
}

Array DuelNativeCompactKernel::inspect_history_keys_for_owner(int64_t owner_id_value) const {
	Array result;
	if (!loaded) return result;
	for (const NativeAction &action : get_legal_native_actions(
		state,
		static_cast<int32_t>(owner_id_value)
	)) {
		Dictionary item = materialize_action(action);
		item["history_key"] = materialize_history_key(history_key_for_action(state, action));
		result.append(item);
	}
	return result;
}

Dictionary DuelNativeCompactKernel::inspect_history_score_policy(
	int64_t initial_score_value,
	int64_t remaining_owner_turn_boundaries_value,
	int64_t cutoff_updates_value,
	int64_t public_depth_decays_value
) const {
	Dictionary result;
	const int32_t remaining_owner_turn_boundaries = static_cast<int32_t>(std::clamp(
		remaining_owner_turn_boundaries_value,
		static_cast<int64_t>(0),
		static_cast<int64_t>(std::numeric_limits<int32_t>::max())
	));
	int32_t score = static_cast<int32_t>(std::clamp(
		initial_score_value,
		static_cast<int64_t>(0),
		static_cast<int64_t>(HISTORY_SCORE_LIMIT)
	));
	const int64_t cutoff_updates = std::max(cutoff_updates_value, static_cast<int64_t>(0));
	const int64_t public_depth_decays = std::max(
		public_depth_decays_value,
		static_cast<int64_t>(0)
	);
	for (int64_t update = 0; update < cutoff_updates; ++update) {
		score = reward_history_score(score, remaining_owner_turn_boundaries);
	}
	for (int64_t decay = 0; decay < public_depth_decays; ++decay) {
		score = decay_history_score(score);
	}
	result["reward"] = history_reward(remaining_owner_turn_boundaries);
	result["score"] = score;
	result["limit"] = HISTORY_SCORE_LIMIT;
	return result;
}

Dictionary DuelNativeCompactKernel::inspect_transposition_table_layout(
	int64_t capacity_mib
) const {
	TranspositionTable table;
	initialize_transposition_table(table, capacity_mib);
	Dictionary result;
	result["requested_mib"] = std::max(capacity_mib, static_cast<int64_t>(0));
	result["entry_size_bytes"] = static_cast<int64_t>(sizeof(TranspositionEntry));
	result["set_count"] = static_cast<int64_t>(table.set_count);
	result["slot_count"] = static_cast<int64_t>(table.slot_count);
	result["allocated_bytes"] = static_cast<int64_t>(table.allocated_bytes);
	result["enabled"] = table.enabled();
	result["allocation_failed"] = table.allocation_failed;
	return result;
}

Dictionary DuelNativeCompactKernel::inspect_evaluation(
	int64_t root_owner_value,
	bool include_deck_evaluation,
	bool include_danger_evaluation,
	bool include_tempo_evaluation
) const {
	Dictionary result;
	const int32_t root_owner = static_cast<int32_t>(root_owner_value);
	result["valid"] = loaded && (root_owner == 1 || root_owner == 2);
	result["include_deck_evaluation"] = include_deck_evaluation;
	result["include_danger_evaluation"] = include_danger_evaluation;
	result["include_tempo_evaluation"] = include_tempo_evaluation;
	result["score"] = 0;
	if (!static_cast<bool>(result["valid"])) return result;
	NativeSearchLimits limits;
	limits.include_deck_evaluation = include_deck_evaluation;
	limits.include_danger_evaluation = include_danger_evaluation;
	limits.include_tempo_evaluation = include_tempo_evaluation;
	result["score"] = evaluate_baseline(state, root_owner, &limits);
	return result;
}

size_t DuelNativeCompactKernel::HistoryKeyHash::operator()(const HistoryKey &key) const {
	size_t result = 1469598103934665603ULL;
	auto mix = [&result](int64_t value) {
		result ^= static_cast<size_t>(static_cast<uint64_t>(value));
		result *= 1099511628211ULL;
	};
	mix(key.valid ? 1 : 0);
	mix(static_cast<int32_t>(key.type));
	mix(key.actor_owner);
	mix(key.source_board_cell);
	for (const int32_t power : key.source_powers) mix(power);
	mix(key.source_ki);
	mix(key.source_ability_count);
	mix(key.target_is_hand_slot ? 1 : 0);
	mix(key.target_index);
	mix(key.activation_index);
	return result;
}

std::vector<DuelNativeCompactKernel::NativeAction>
DuelNativeCompactKernel::get_legal_native_actions(
	const NativeState &value,
	int32_t owner_id
) const {
	std::vector<NativeAction> actions;
	if (
		(owner_id != 1 && owner_id != 2)
		|| value.board_card_indices.size() != 9
		|| value.zones.size() < 2
	) return actions;
	const int32_t hand_zone_index = owner_id - 1;
	for (size_t hand_index = 0; hand_index < value.zones[hand_zone_index].size(); ++hand_index) {
		const int32_t card_index = value.zones[hand_zone_index][hand_index];
		if (
			card_index < 0
			|| card_index >= static_cast<int32_t>(value.card_instance_ids.size())
		) continue;
		for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
			if (value.board_card_indices[cell] >= 0) continue;
			NativeAction action;
			action.type = NativeActionType::PLAY;
			action.source_index = static_cast<int32_t>(hand_index);
			action.source_instance_id = value.card_instance_ids[card_index];
			action.target_index = static_cast<int32_t>(cell);
			actions.push_back(action);
		}
	}
	if (owner_id == value.scalars[0] && value.scalars[5] > 0) return actions;

	for (size_t source_cell = 0; source_cell < value.board_card_indices.size(); ++source_cell) {
		const int32_t card_index = value.board_card_indices[source_cell];
		if (card_index < 0 || value.board_owners[source_cell] != owner_id) continue;
		if (!card_effects_enabled(value, card_index, owner_id)) continue;
		int32_t activation_index = 0;
		for (
			size_t ability_index = 0;
			ability_index < value.card_runtime_abilities[card_index].size();
			++ability_index
		) {
			const CompiledAbility *ability = runtime_ability(
				value,
				card_index,
				static_cast<int32_t>(ability_index)
			);
			if (ability == nullptr || !ability->has_activation) continue;
			const int32_t current_activation_index = activation_index++;
			const CompiledActivation &activation = ability->activation;
			if (!can_pay_activation_cost(value, card_index, activation)) continue;
			const std::vector<int32_t> targets = get_activation_target_indices(
				value,
				owner_id,
				static_cast<int32_t>(source_cell),
				activation
			);
			for (const int32_t target_index : targets) {
				NativeAction action;
				action.type = NativeActionType::ACTIVATE;
				action.source_index = static_cast<int32_t>(source_cell);
				action.source_instance_id = value.card_instance_ids[card_index];
				action.target_is_hand_slot = activation_targets_hand(activation);
				action.target_index = target_index;
				action.activation_index = current_activation_index;
				actions.push_back(action);
			}
		}
	}
	return actions;
}

int64_t DuelNativeCompactKernel::count_legal_native_actions(
	const NativeState &value,
	int32_t owner_id
) const {
	if (
		(owner_id != 1 && owner_id != 2)
		|| value.board_card_indices.size() != 9
		|| value.zones.size() < 2
	) return 0;
	int64_t empty_cells = 0;
	for (const int32_t card_index : value.board_card_indices) {
		if (card_index < 0) empty_cells += 1;
	}
	const int32_t hand_zone_index = owner_id - 1;
	int64_t valid_hand_cards = 0;
	for (const int32_t card_index : value.zones[hand_zone_index]) {
		if (
			card_index >= 0
			&& card_index < static_cast<int32_t>(value.card_instance_ids.size())
		) valid_hand_cards += 1;
	}
	int64_t action_count = valid_hand_cards * empty_cells;
	if (owner_id == value.scalars[0] && value.scalars[5] > 0) return action_count;
	for (size_t source_cell = 0; source_cell < value.board_card_indices.size(); ++source_cell) {
		const int32_t card_index = value.board_card_indices[source_cell];
		if (card_index < 0 || value.board_owners[source_cell] != owner_id) continue;
		if (!card_effects_enabled(value, card_index, owner_id)) continue;
		for (
			size_t ability_index = 0;
			ability_index < value.card_runtime_abilities[card_index].size();
			++ability_index
		) {
			const CompiledAbility *ability = runtime_ability(
				value,
				card_index,
				static_cast<int32_t>(ability_index)
			);
			if (ability == nullptr || !ability->has_activation) continue;
			const CompiledActivation &activation = ability->activation;
			if (!can_pay_activation_cost(value, card_index, activation)) continue;
			action_count += count_activation_target_indices(
				value,
				owner_id,
				static_cast<int32_t>(source_cell),
				activation
			);
		}
	}
	return action_count;
}

Dictionary DuelNativeCompactKernel::materialize_action(const NativeAction &action) const {
	Dictionary result;
	const bool activation = action.type == NativeActionType::ACTIVATE;
	result["action_type"] = activation ? StringName("activate") : StringName("play");
	result["source_zone"] = activation ? StringName("board") : StringName("hand");
	result["source_index"] = action.source_index;
	result["source_instance_id"] = action.source_instance_id;
	result["target_kind"] = action.target_is_hand_slot
		? StringName("hand_slot")
		: StringName("board_cell");
	result["target_index"] = action.target_index;
	result["activation_index"] = action.activation_index;
	return result;
}

bool DuelNativeCompactKernel::action_canonical_less(
	const NativeAction &left,
	const NativeAction &right
) const {
	if (left.type != right.type) return left.type == NativeActionType::ACTIVATE;
	if (left.source_index != right.source_index) return left.source_index < right.source_index;
	if (left.source_instance_id != right.source_instance_id) {
		return left.source_instance_id < right.source_instance_id;
	}
	if (left.target_is_hand_slot != right.target_is_hand_slot) return !left.target_is_hand_slot;
	if (left.target_index != right.target_index) return left.target_index < right.target_index;
	return left.activation_index < right.activation_index;
}

bool DuelNativeCompactKernel::actions_equal(
	const NativeAction &left,
	const NativeAction &right
) const {
	return left.type == right.type
		&& left.source_index == right.source_index
		&& left.source_instance_id == right.source_instance_id
		&& left.target_is_hand_slot == right.target_is_hand_slot
		&& left.target_index == right.target_index
		&& left.activation_index == right.activation_index;
}

int32_t DuelNativeCompactKernel::action_structural_score(
	const NativeState &value,
	const NativeAction &action
) const {
	if (action.type == NativeActionType::ACTIVATE) return 100;
	const int32_t owner_id = value.scalars[0];
	const int32_t hand_zone = owner_id - 1;
	if (
		hand_zone < 0
		|| hand_zone >= static_cast<int32_t>(value.zones.size())
		|| action.source_index < 0
		|| action.source_index >= static_cast<int32_t>(value.zones[hand_zone].size())
	) return 0;
	const int32_t card_index = value.zones[hand_zone][action.source_index];
	if (card_index < 0) return 0;
	int32_t score = action.target_index == 4
		? 0
		: (action.target_index == 0 || action.target_index == 2
			|| action.target_index == 6 || action.target_index == 8 ? 20 : 10);
	for (int32_t direction = 0; direction < 4; ++direction) {
		const int32_t neighbor = neighbor_index(action.target_index, direction);
		if (neighbor < 0) continue;
		const int32_t neighbor_card = value.board_card_indices[neighbor];
		if (neighbor_card < 0) continue;
		score += 5;
		if (value.board_owners[neighbor] == owner_id) continue;
		const int32_t opposite = (direction + 2) % 4;
		if (
			value.card_powers[static_cast<size_t>(card_index) * 4 + direction]
			> value.card_powers[static_cast<size_t>(neighbor_card) * 4 + opposite]
		) score += 100;
	}
	return score;
}

DuelNativeCompactKernel::HistoryKey DuelNativeCompactKernel::history_key_for_action(
	const NativeState &value,
	const NativeAction &action
) const {
	HistoryKey key;
	key.type = action.type;
	key.actor_owner = value.scalars[0];
	key.target_is_hand_slot = action.target_is_hand_slot;
	key.target_index = action.target_index;
	key.activation_index = action.activation_index;
	int32_t source_card_index = -1;
	if (action.type == NativeActionType::PLAY) {
		const int32_t hand_zone = value.scalars[0] - 1;
		if (
			hand_zone >= 0
			&& hand_zone < static_cast<int32_t>(value.zones.size())
			&& action.source_index >= 0
			&& action.source_index < static_cast<int32_t>(value.zones[hand_zone].size())
		) source_card_index = value.zones[hand_zone][action.source_index];
	} else if (
		action.source_index >= 0
		&& action.source_index < static_cast<int32_t>(value.board_card_indices.size())
	) {
		key.source_board_cell = action.source_index;
		source_card_index = value.board_card_indices[action.source_index];
	}
	if (
		source_card_index < 0
		|| source_card_index >= static_cast<int32_t>(value.card_instance_ids.size())
	) return key;
	key.valid = true;
	const size_t power_offset = static_cast<size_t>(source_card_index) * 4;
	for (size_t direction = 0; direction < key.source_powers.size(); ++direction) {
		key.source_powers[direction] = value.card_powers[power_offset + direction];
	}
	key.source_ki = value.card_ki[source_card_index];
	key.source_ability_count = static_cast<int32_t>(
		value.card_runtime_abilities[source_card_index].size()
	);
	return key;
}

Array DuelNativeCompactKernel::materialize_history_key(const HistoryKey &key) const {
	Array result;
	result.append(key.valid ? 1 : 0);
	result.append(static_cast<int32_t>(key.type));
	result.append(key.actor_owner);
	result.append(key.source_board_cell);
	for (const int32_t power : key.source_powers) result.append(power);
	result.append(key.source_ki);
	result.append(key.source_ability_count);
	result.append(key.target_is_hand_slot ? 1 : 0);
	result.append(key.target_index);
	result.append(key.activation_index);
	return result;
}

int32_t DuelNativeCompactKernel::history_reward(
	int32_t remaining_owner_turn_boundaries
) const {
	const int64_t depth_term = static_cast<int64_t>(
		std::max(remaining_owner_turn_boundaries, 0)
	) + 1;
	return static_cast<int32_t>(std::min(
		depth_term * depth_term,
		static_cast<int64_t>(HISTORY_SCORE_LIMIT)
	));
}

int32_t DuelNativeCompactKernel::reward_history_score(
	int32_t current_score,
	int32_t remaining_owner_turn_boundaries
) const {
	return static_cast<int32_t>(std::min(
		static_cast<int64_t>(std::max(current_score, 0))
			+ history_reward(remaining_owner_turn_boundaries),
		static_cast<int64_t>(HISTORY_SCORE_LIMIT)
	));
}

int32_t DuelNativeCompactKernel::decay_history_score(int32_t score) const {
	return static_cast<int32_t>(
		static_cast<int64_t>(std::max(score, 0)) * 3 / 4
	);
}

std::vector<DuelNativeCompactKernel::NativeAction>
DuelNativeCompactKernel::order_search_actions(
	const NativeState &value,
	std::vector<NativeAction> actions,
	const NativeAction *preferred,
	const NativeAction *transposition_preferred,
	const HistoryTable *history_scores,
	NativeSearchStats *stats,
	bool collect_diagnostics
) const {
	for (NativeAction &action : actions) {
		action.ordering_preferred = preferred != nullptr
			&& actions_equal(action, *preferred);
		action.ordering_transposition_preferred = transposition_preferred != nullptr
			&& actions_equal(action, *transposition_preferred);
		action.ordering_history_score = 0;
		if (history_scores != nullptr) {
			if (collect_diagnostics && stats != nullptr) stats->history_queries += 1;
			const auto found = history_scores->find(history_key_for_action(value, action));
			if (found != history_scores->end()) {
				action.ordering_history_score = found->second;
				if (collect_diagnostics && stats != nullptr) stats->history_hits += 1;
			}
		}
		action.ordering_structural_score = action_structural_score(value, action);
	}
	std::sort(
		actions.begin(),
		actions.end(),
		[this](const NativeAction &left, const NativeAction &right) {
			if (left.ordering_preferred != right.ordering_preferred) {
				return left.ordering_preferred;
			}
			if (
				left.ordering_transposition_preferred
				!= right.ordering_transposition_preferred
			) {
				return left.ordering_transposition_preferred;
			}
			if (left.ordering_structural_score != right.ordering_structural_score) {
				return left.ordering_structural_score > right.ordering_structural_score;
			}
			if (left.ordering_history_score != right.ordering_history_score) {
				return left.ordering_history_score > right.ordering_history_score;
			}
			return action_canonical_less(left, right);
		}
	);
	return actions;
}

bool DuelNativeCompactKernel::initialize_transposition_table(
	TranspositionTable &table,
	int64_t capacity_mib
) const {
	table = TranspositionTable();
	if (capacity_mib <= 0) return false;
	constexpr uint64_t bytes_per_mib = 1024ULL * 1024ULL;
	const uint64_t requested_mib = static_cast<uint64_t>(capacity_mib);
	if (requested_mib > std::numeric_limits<uint64_t>::max() / bytes_per_mib) {
		table.allocation_failed = true;
		return false;
	}
	const uint64_t requested_bytes = requested_mib * bytes_per_mib;
	const uint64_t candidate_sets = requested_bytes
		/ (sizeof(TranspositionEntry) * 2ULL);
	if (candidate_sets == 0) return false;
	size_t set_count = 1;
	while (
		set_count <= std::numeric_limits<size_t>::max() / 2
		&& static_cast<uint64_t>(set_count * 2) <= candidate_sets
	) {
		set_count *= 2;
	}
	if (set_count > std::numeric_limits<size_t>::max() / 2) {
		table.allocation_failed = true;
		return false;
	}
	const size_t slot_count = set_count * 2;
	std::unique_ptr<TranspositionEntry[]> entries(
		new (std::nothrow) TranspositionEntry[slot_count]()
	);
	if (entries == nullptr) {
		table.allocation_failed = true;
		return false;
	}
	table.entries = std::move(entries);
	table.set_count = set_count;
	table.slot_count = slot_count;
	table.allocated_bytes = slot_count * sizeof(TranspositionEntry);
	return true;
}

const DuelNativeCompactKernel::TranspositionEntry *
DuelNativeCompactKernel::probe_transposition_table(
	const TranspositionTable &table,
	uint64_t state_checksum,
	int32_t remaining_owner_turn_boundaries
) const {
	if (!table.enabled()) return nullptr;
	const size_t set_index = static_cast<size_t>(search_position_key_from_checksum(
		state_checksum,
		remaining_owner_turn_boundaries
	)) & (table.set_count - 1);
	const size_t first_slot = set_index * 2;
	for (size_t offset = 0; offset < 2; ++offset) {
		const TranspositionEntry &entry = table.entries[first_slot + offset];
		if (
			entry.occupied
			&& entry.state_checksum == state_checksum
			&& entry.remaining_owner_turn_boundaries == remaining_owner_turn_boundaries
		) return &entry;
	}
	return nullptr;
}

bool DuelNativeCompactKernel::compact_native_action(
	const NativeAction &action,
	CompactNativeAction &compact
) const {
	const auto fits_int16 = [](int32_t value) {
		return value >= std::numeric_limits<int16_t>::min()
			&& value <= std::numeric_limits<int16_t>::max();
	};
	if (
		!fits_int16(action.source_index)
		|| !fits_int16(action.target_index)
		|| !fits_int16(action.activation_index)
	) return false;
	compact.source_index = static_cast<int16_t>(action.source_index);
	compact.target_index = static_cast<int16_t>(action.target_index);
	compact.activation_index = static_cast<int16_t>(action.activation_index);
	compact.type = static_cast<uint8_t>(action.type);
	compact.flags = action.target_is_hand_slot ? 1U : 0U;
	return true;
}

bool DuelNativeCompactKernel::restore_compact_action(
	const CompactNativeAction &compact,
	const std::vector<NativeAction> &legal_actions,
	NativeAction &action
) const {
	for (const NativeAction &candidate : legal_actions) {
		if (
			static_cast<uint8_t>(candidate.type) != compact.type
			|| candidate.source_index != compact.source_index
			|| candidate.target_index != compact.target_index
			|| candidate.activation_index != compact.activation_index
			|| candidate.target_is_hand_slot != ((compact.flags & 1U) != 0)
		) continue;
		action = candidate;
		return true;
	}
	return false;
}

void DuelNativeCompactKernel::store_transposition_entry(
	TranspositionTable &table,
	uint64_t state_checksum,
	int32_t remaining_owner_turn_boundaries,
	int32_t score,
	TranspositionBound bound,
	bool horizon_reached,
	const NativeAction *best_action,
	uint32_t generation,
	NativeSearchStats *stats,
	bool collect_diagnostics
) const {
	if (!table.enabled()) return;
	TranspositionEntry candidate;
	candidate.state_checksum = state_checksum;
	candidate.score = score;
	candidate.remaining_owner_turn_boundaries = remaining_owner_turn_boundaries;
	candidate.generation = generation;
	candidate.bound = bound;
	candidate.occupied = true;
	candidate.horizon_reached = horizon_reached;
	candidate.has_best_action = best_action != nullptr
		&& compact_native_action(*best_action, candidate.best_action);

	const size_t set_index = static_cast<size_t>(search_position_key_from_checksum(
		state_checksum,
		remaining_owner_turn_boundaries
	)) & (table.set_count - 1);
	TranspositionEntry *slots = &table.entries[set_index * 2];
	for (size_t offset = 0; offset < 2; ++offset) {
		if (!slots[offset].occupied) {
			slots[offset] = candidate;
			if (collect_diagnostics && stats != nullptr) stats->transposition_stores += 1;
			return;
		}
		if (
			slots[offset].state_checksum == state_checksum
			&& slots[offset].remaining_owner_turn_boundaries
				== remaining_owner_turn_boundaries
		) {
			slots[offset] = candidate;
			if (collect_diagnostics && stats != nullptr) stats->transposition_updates += 1;
			return;
		}
	}
	if (collect_diagnostics && stats != nullptr) stats->transposition_collisions += 1;
	auto worse_for_retention = [](const TranspositionEntry &left, const TranspositionEntry &right) {
		if (left.generation != right.generation) return left.generation < right.generation;
		if (
			left.remaining_owner_turn_boundaries
			!= right.remaining_owner_turn_boundaries
		) {
			return left.remaining_owner_turn_boundaries
				< right.remaining_owner_turn_boundaries;
		}
		if (left.bound != right.bound) {
			return left.bound != TranspositionBound::EXACT
				&& right.bound == TranspositionBound::EXACT;
		}
		return false;
	};
	const size_t victim = worse_for_retention(slots[1], slots[0]) ? 1 : 0;
	slots[victim] = candidate;
	if (collect_diagnostics && stats != nullptr) {
		stats->transposition_replacements += 1;
		stats->transposition_stores += 1;
	}
}


int32_t DuelNativeCompactKernel::evaluate_baseline(
	const NativeState &value,
	int32_t root_owner,
	const NativeSearchLimits *limits
) const {
	static constexpr int32_t win_score = 1'000'000;
	static constexpr int32_t deck_card_weight = 25;
	static constexpr int32_t ki_weight = 4;
	static constexpr int32_t ability_weight = 4;
	static constexpr int32_t danger_weight = 2;
	static constexpr int32_t tempo_weight = 2;
	static constexpr int32_t positional_limit = 499;
	static constexpr int32_t strategic_scale = 1'000;
	const bool include_deck_evaluation = limits != nullptr
		&& limits->include_deck_evaluation;
	const bool include_danger_evaluation = limits != nullptr
		&& limits->include_danger_evaluation;
	const bool include_tempo_evaluation = limits != nullptr
		&& limits->include_tempo_evaluation;
	const int32_t opponent_owner = other_owner(root_owner);
	const int32_t score_difference = count_owned(value, root_owner)
		- count_owned(value, opponent_owner);
	if (is_terminal(value)) {
		if (score_difference > 0) {
			return win_score + score_difference * 100 - value.scalars[1];
		}
		if (score_difference < 0) {
			return -win_score + score_difference * 100 + value.scalars[1];
		}
		return 0;
	}

	auto card_resource_value = [&value](int32_t card_index) -> int32_t {
		if (card_index < 0 || card_index >= static_cast<int32_t>(value.card_ki.size())) {
			return 0;
		}
		int32_t result = value.card_ki[card_index] * ki_weight;
		const size_t power_offset = static_cast<size_t>(card_index) * 4;
		for (size_t direction = 0; direction < 4; ++direction) {
			result += value.card_powers[power_offset + direction];
		}
		result += static_cast<int32_t>(
			value.card_runtime_abilities[card_index].size()
		) * ability_weight;
		return result;
	};
	auto zone_value = [&value, &card_resource_value](
		int32_t zone_index,
		int32_t card_weight
	) -> int32_t {
		if (zone_index < 0 || zone_index >= static_cast<int32_t>(value.zones.size())) {
			return 0;
		}
		int32_t result = static_cast<int32_t>(value.zones[zone_index].size()) * card_weight;
		for (const int32_t card_index : value.zones[zone_index]) {
			result += card_resource_value(card_index);
		}
		return result;
	};
	auto board_resource_value = [&value, &card_resource_value](int32_t owner_id) -> int32_t {
		int32_t result = 0;
		for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
			if (value.board_owners[cell] != owner_id) continue;
			result += card_resource_value(value.board_card_indices[cell]);
		}
		return result;
	};
	auto danger_value = [&value](int32_t owner_id) -> int32_t {
		int32_t danger = 0;
		for (int32_t cell = 0; cell < static_cast<int32_t>(value.board_card_indices.size()); ++cell) {
			const int32_t card_index = value.board_card_indices[cell];
			if (card_index < 0 || value.board_owners[cell] != owner_id) continue;
			for (int32_t direction = 0; direction < 4; ++direction) {
				const int32_t adjacent = neighbor_index(cell, direction);
				if (adjacent < 0) continue;
				const int32_t enemy_card_index = value.board_card_indices[adjacent];
				if (enemy_card_index < 0 || value.board_owners[adjacent] == owner_id) continue;
				const int32_t opposite = (direction + 2) % 4;
				if (
					value.card_powers[static_cast<size_t>(enemy_card_index) * 4 + opposite]
					> value.card_powers[static_cast<size_t>(card_index) * 4 + direction]
				) danger += danger_weight;
			}
		}
		return danger;
	};

	const int32_t root_hand_zone = root_owner - 1;
	const int32_t opponent_hand_zone = opponent_owner - 1;
	const int32_t root_deck_zone = root_owner + 1;
	const int32_t opponent_deck_zone = opponent_owner + 1;
	int32_t strategic_score = score_difference * 100;
	strategic_score += (
		static_cast<int32_t>(value.zones[root_hand_zone].size())
		- static_cast<int32_t>(value.zones[opponent_hand_zone].size())
	) * 5;
	int32_t positional_score = zone_value(root_hand_zone, 0)
		- zone_value(opponent_hand_zone, 0);
	if (include_deck_evaluation) {
		positional_score += zone_value(root_deck_zone, deck_card_weight)
			- zone_value(opponent_deck_zone, deck_card_weight);
	}
	positional_score += static_cast<int32_t>(
		count_legal_native_actions(value, root_owner)
		- count_legal_native_actions(value, opponent_owner)
	);
	positional_score += board_resource_value(root_owner)
		- board_resource_value(opponent_owner);
	if (include_danger_evaluation) {
		positional_score += danger_value(opponent_owner) - danger_value(root_owner);
	}
	if (include_tempo_evaluation) {
		positional_score += value.scalars[0] == root_owner ? tempo_weight : -tempo_weight;
	}
	positional_score = std::clamp(positional_score, -positional_limit, positional_limit);
	return std::clamp(
		strategic_score * strategic_scale + positional_score,
		-win_score + 1,
		win_score - 1
	);
}

bool DuelNativeCompactKernel::search_should_stop(
	NativeSearchStats &stats,
	const NativeSearchLimits *limits
) const {
	if (stats.aborted) return true;
	if (limits == nullptr) return false;
	if (
		limits->should_cancel.is_valid()
		&& (stats.nodes & 255) == 0
		&& static_cast<bool>(limits->should_cancel.call())
	) {
		stats.aborted = true;
		stats.stop_reason = StringName("cancelled");
		return true;
	}
	if (
		limits->max_nodes > 0
		&& stats.nodes >= limits->max_nodes
		&& !limits->protect_node_limit
	) {
		stats.aborted = true;
		stats.stop_reason = StringName("node_limit");
		return true;
	}
	if (
		limits->has_deadline
		&& std::chrono::steady_clock::now() >= limits->deadline
	) {
		stats.aborted = true;
		stats.stop_reason = StringName("deadline");
		return true;
	}
	return false;
}

uint64_t DuelNativeCompactKernel::search_position_key(
	const NativeState &value,
	int32_t remaining_owner_turn_boundaries
) const {
	return search_position_key_from_checksum(
		checksum(value),
		remaining_owner_turn_boundaries
	);
}

uint64_t DuelNativeCompactKernel::search_position_key_from_checksum(
	uint64_t state_checksum,
	int32_t remaining_owner_turn_boundaries
) const {
	uint64_t key = state_checksum;
	key ^= static_cast<uint64_t>(remaining_owner_turn_boundaries + 1)
		* 0x9e3779b97f4a7c15ULL;
	return key;
}

int32_t DuelNativeCompactKernel::search_minimax(
	const NativeState &value,
	int32_t remaining_owner_turn_boundaries,
	int32_t root_owner,
	int32_t action_ply,
	int32_t alpha,
	int32_t beta,
	NativeSearchStats &stats,
	const NativeSearchLimits *limits
) const {
	if (search_should_stop(stats, limits)) return 0;
	const int32_t original_alpha = alpha;
	const int32_t original_beta = beta;
	const int64_t horizon_visits_before = stats.horizon_visits;
	const bool collect_diagnostics = limits != nullptr
		&& limits->collect_search_diagnostics;
	stats.nodes += 1;
	stats.max_action_ply = std::max(stats.max_action_ply, action_ply);
	uint64_t state_checksum = 0;
	bool has_state_checksum = false;
	uint64_t transposition_exact_key = 0;
	bool has_transposition_exact_key = false;
	bool has_completed_transposition_hit = false;
	bool transposition_probe_classified = false;
	auto ensure_state_checksum = [&]() -> uint64_t {
		if (has_state_checksum) return state_checksum;
		const auto key_started = collect_diagnostics
			? std::chrono::steady_clock::now()
			: std::chrono::steady_clock::time_point();
		state_checksum = checksum(value);
		has_state_checksum = true;
		if (collect_diagnostics) {
			stats.time_key_usec += std::chrono::duration_cast<std::chrono::microseconds>(
				std::chrono::steady_clock::now() - key_started
			).count();
		}
		return state_checksum;
	};
	if (
		collect_diagnostics
		&& limits->transposition_seen_keys != nullptr
		&& limits->transposition_completed_keys != nullptr
		&& limits->transposition_seen_states != nullptr
	) {
		const uint64_t checksum_value = ensure_state_checksum();
		transposition_exact_key = search_position_key_from_checksum(
			checksum_value,
			remaining_owner_turn_boundaries
		);
		has_transposition_exact_key = true;
		stats.transposition_probes += 1;
		if (!limits->transposition_seen_keys->insert(transposition_exact_key).second) {
			stats.transposition_hits += 1;
		}
		if (
			limits->transposition_completed_keys->find(transposition_exact_key)
			!= limits->transposition_completed_keys->end()
		) {
			has_completed_transposition_hit = true;
			stats.transposition_completed_hits += 1;
		}
		if (!limits->transposition_seen_states->insert(checksum_value).second) {
			stats.transposition_state_hits += 1;
		}
		stats.transposition_unique_keys = static_cast<int64_t>(
			limits->transposition_seen_keys->size()
		);
		stats.transposition_unique_states = static_cast<int64_t>(
			limits->transposition_seen_states->size()
		);
	}
	auto mark_transposition_completed = [&]() -> void {
		if (
			!has_transposition_exact_key
			|| limits == nullptr
			|| limits->transposition_completed_keys == nullptr
		) return;
		limits->transposition_completed_keys->insert(transposition_exact_key);
		stats.transposition_completed_keys = static_cast<int64_t>(
			limits->transposition_completed_keys->size()
		);
	};
	auto classify_transposition_probe = [&](bool leaf) -> void {
		if (!has_transposition_exact_key || transposition_probe_classified) return;
		transposition_probe_classified = true;
		if (leaf) {
			stats.transposition_leaf_probes += 1;
			if (has_completed_transposition_hit) {
				stats.transposition_leaf_completed_hits += 1;
			}
		} else {
			stats.transposition_internal_probes += 1;
			if (has_completed_transposition_hit) {
				stats.transposition_internal_completed_hits += 1;
			}
		}
	};
	auto propagate_horizon = [&]() -> void {
		stats.horizon_reached = true;
		stats.horizon_visits += 1;
	};
	auto store_transposition = [&](
		int32_t score,
		TranspositionBound bound,
		const NativeAction *best_action
	) -> void {
		if (
			limits == nullptr
			|| !limits->use_transposition_table
			|| limits->transposition_table == nullptr
			|| !limits->transposition_table->enabled()
			|| stats.aborted
			|| !stats.supported
		) return;
		store_transposition_entry(
			*limits->transposition_table,
			ensure_state_checksum(),
			remaining_owner_turn_boundaries,
			score,
			bound,
			stats.horizon_visits > horizon_visits_before,
			best_action,
			limits->transposition_generation,
			&stats,
			collect_diagnostics
		);
	};

	TranspositionEntry cached_transposition;
	bool has_cached_transposition = false;
	if (
		limits != nullptr
		&& limits->use_transposition_table
		&& limits->transposition_table != nullptr
		&& limits->transposition_table->enabled()
	) {
		if (collect_diagnostics) stats.transposition_table_probes += 1;
		const TranspositionEntry *cached = probe_transposition_table(
			*limits->transposition_table,
			ensure_state_checksum(),
			remaining_owner_turn_boundaries
		);
		if (cached != nullptr) {
			cached_transposition = *cached;
			has_cached_transposition = true;
			if (collect_diagnostics) {
				stats.transposition_table_hits += 1;
				if (cached_transposition.bound == TranspositionBound::EXACT) {
					stats.transposition_exact_hits += 1;
				} else {
					stats.transposition_bound_hits += 1;
				}
			}
			if (cached_transposition.horizon_reached) propagate_horizon();
			if (cached_transposition.bound == TranspositionBound::EXACT) {
				NativeAction cached_action;
				bool has_legal_cached_action = false;
				if (cached_transposition.has_best_action) {
					if (collect_diagnostics) stats.transposition_move_queries += 1;
					const auto legal_started = collect_diagnostics
						? std::chrono::steady_clock::now()
						: std::chrono::steady_clock::time_point();
					const std::vector<NativeAction> legal_actions = get_legal_native_actions(
						value,
						value.scalars[0]
					);
					if (collect_diagnostics) {
						stats.time_legal_actions_usec += std::chrono::duration_cast<
							std::chrono::microseconds
						>(std::chrono::steady_clock::now() - legal_started).count();
					}
					stats.generated_actions += static_cast<int64_t>(legal_actions.size());
					has_legal_cached_action = restore_compact_action(
						cached_transposition.best_action,
						legal_actions,
						cached_action
					);
					if (collect_diagnostics) {
						if (has_legal_cached_action) {
							stats.transposition_move_legal_hits += 1;
						} else {
							stats.transposition_move_illegal_hits += 1;
						}
					}
				}
				if (has_legal_cached_action && limits != nullptr) {
					const uint64_t key = ensure_state_checksum();
					if (limits->current_ordering_hints != nullptr) {
						(*limits->current_ordering_hints)[key] = cached_action;
					}
					if (limits->principal_actions != nullptr) {
						(*limits->principal_actions)[search_position_key_from_checksum(
							key,
							remaining_owner_turn_boundaries
						)] = cached_action;
					}
				}
				if (collect_diagnostics) stats.transposition_exact_returns += 1;
				classify_transposition_probe(
					is_terminal(value)
					|| remaining_owner_turn_boundaries <= 0
					|| !cached_transposition.has_best_action
				);
				mark_transposition_completed();
				return cached_transposition.score;
			}
			if (cached_transposition.bound == TranspositionBound::LOWER) {
				alpha = std::max(alpha, cached_transposition.score);
			} else {
				beta = std::min(beta, cached_transposition.score);
			}
			if (alpha >= beta) {
				if (collect_diagnostics) stats.transposition_bound_cutoffs += 1;
				classify_transposition_probe(
					is_terminal(value) || remaining_owner_turn_boundaries <= 0
				);
				mark_transposition_completed();
				return cached_transposition.score;
			}
		}
	}

	const bool terminal = is_terminal(value);
	if (terminal || remaining_owner_turn_boundaries <= 0) {
		classify_transposition_probe(true);
		stats.leaves += 1;
		if (remaining_owner_turn_boundaries <= 0 && !terminal) {
			propagate_horizon();
		}
		const auto evaluate_started = collect_diagnostics
			? std::chrono::steady_clock::now()
			: std::chrono::steady_clock::time_point();
		const int32_t score = evaluate_baseline(value, root_owner, limits);
		if (collect_diagnostics) {
			stats.time_evaluate_usec += std::chrono::duration_cast<std::chrono::microseconds>(
				std::chrono::steady_clock::now() - evaluate_started
			).count();
		}
		store_transposition(score, TranspositionBound::EXACT, nullptr);
		mark_transposition_completed();
		return score;
	}
	const auto legal_started = collect_diagnostics
		? std::chrono::steady_clock::now()
		: std::chrono::steady_clock::time_point();
	std::vector<NativeAction> legal_actions = get_legal_native_actions(
		value,
		value.scalars[0]
	);
	if (collect_diagnostics) {
		stats.time_legal_actions_usec += std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now() - legal_started
		).count();
	}
	const NativeAction *preferred_action = nullptr;
	if (
		limits != nullptr
		&& limits->use_internal_pv_ordering
		&& limits->previous_ordering_hints != nullptr
	) {
		if (collect_diagnostics) stats.pv_queries += 1;
		const auto found = limits->previous_ordering_hints->find(ensure_state_checksum());
		if (found != limits->previous_ordering_hints->end()) {
			if (collect_diagnostics) stats.pv_hits += 1;
			bool legal_hint = false;
			for (const NativeAction &legal_action : legal_actions) {
				if (!actions_equal(legal_action, found->second)) continue;
				legal_hint = true;
				break;
			}
			if (legal_hint) {
				preferred_action = &found->second;
				if (collect_diagnostics) stats.pv_legal_hits += 1;
			} else if (collect_diagnostics) {
				stats.pv_illegal_hits += 1;
			}
		}
	}
	NativeAction transposition_preferred_action;
	const NativeAction *transposition_preferred = nullptr;
	if (has_cached_transposition && cached_transposition.has_best_action) {
		if (collect_diagnostics) stats.transposition_move_queries += 1;
		if (restore_compact_action(
			cached_transposition.best_action,
			legal_actions,
			transposition_preferred_action
		)) {
			transposition_preferred = &transposition_preferred_action;
			if (collect_diagnostics) stats.transposition_move_legal_hits += 1;
		} else if (collect_diagnostics) {
			stats.transposition_move_illegal_hits += 1;
		}
	}
	const auto order_started = collect_diagnostics
		? std::chrono::steady_clock::now()
		: std::chrono::steady_clock::time_point();
	const std::vector<NativeAction> actions = order_search_actions(
		value,
		std::move(legal_actions),
		preferred_action,
		transposition_preferred,
		(
			limits != nullptr
			&& limits->use_history_ordering
			&& limits->history_scores != nullptr
			? limits->history_scores
			: nullptr
		),
		&stats,
		collect_diagnostics
	);
	if (collect_diagnostics) {
		stats.time_order_usec += std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now() - order_started
		).count();
		stats.ordered_nodes += 1;
	}
	stats.generated_actions += static_cast<int64_t>(actions.size());
	if (actions.empty()) {
		classify_transposition_probe(true);
		stats.leaves += 1;
		const auto evaluate_started = collect_diagnostics
			? std::chrono::steady_clock::now()
			: std::chrono::steady_clock::time_point();
		const int32_t score = evaluate_baseline(value, root_owner, limits);
		if (collect_diagnostics) {
			stats.time_evaluate_usec += std::chrono::duration_cast<std::chrono::microseconds>(
				std::chrono::steady_clock::now() - evaluate_started
			).count();
		}
		store_transposition(score, TranspositionBound::EXACT, nullptr);
		mark_transposition_completed();
		return score;
	}
	classify_transposition_probe(false);
	const bool maximizing = value.scalars[0] == root_owner;
	int32_t best_score = maximizing
		? std::numeric_limits<int32_t>::min()
		: std::numeric_limits<int32_t>::max();
	NativeAction best_action;
	bool has_best_action = false;
	int32_t child_ordinal = 0;
	for (const NativeAction &action : actions) {
		child_ordinal += 1;
		if (collect_diagnostics) stats.visited_children += 1;
		NativeState next;
		Resolution resolution;
		bool transition_supported = false;
		String transition_reason;
		const auto apply_started = collect_diagnostics
			? std::chrono::steady_clock::now()
			: std::chrono::steady_clock::time_point();
		if (!transition_action(
			value,
			action,
			next,
			resolution,
			transition_supported,
			transition_reason,
			false
		)) {
			stats.supported = false;
			stats.reason = transition_reason.is_empty()
				? String("Native search reached an invalid transition")
				: transition_reason;
			return 0;
		}
		if (collect_diagnostics) {
			stats.time_apply_usec += std::chrono::duration_cast<std::chrono::microseconds>(
				std::chrono::steady_clock::now() - apply_started
			).count();
		}
		stats.applied_transitions += 1;
		const int32_t completed_owner_turns = std::max(
			next.scalars[2] - value.scalars[2],
			0
		);
		const int32_t score = search_minimax(
			next,
			remaining_owner_turn_boundaries - completed_owner_turns,
			root_owner,
			action_ply + 1,
			alpha,
			beta,
			stats,
			limits
		);
		if (!stats.supported || stats.aborted) return 0;
		const bool better_score = !has_best_action
			|| (maximizing && score > best_score)
			|| (!maximizing && score < best_score);
		const bool better_tie = has_best_action
			&& score == best_score
			&& action_canonical_less(action, best_action);
		if (better_score || better_tie) {
			best_score = score;
			best_action = action;
			has_best_action = true;
		}
		if (maximizing) {
			alpha = std::max(alpha, best_score);
		} else {
			beta = std::min(beta, best_score);
		}
		if (beta <= alpha) {
			stats.cutoffs += 1;
			if (
				limits != nullptr
				&& limits->use_history_ordering
				&& limits->history_scores != nullptr
			) {
				const HistoryKey history_key = history_key_for_action(value, action);
				if (history_key.valid) {
					int32_t &history_score = (*limits->history_scores)[history_key];
					history_score = reward_history_score(
						history_score,
						remaining_owner_turn_boundaries
					);
					if (collect_diagnostics) stats.history_cutoffs += 1;
				}
			}
			if (collect_diagnostics) {
				if (child_ordinal == 1) stats.cutoff_first_child += 1;
				else if (child_ordinal == 2) stats.cutoff_second_child += 1;
				else if (child_ordinal <= 4) stats.cutoff_third_fourth_child += 1;
				else if (child_ordinal <= 8) stats.cutoff_fifth_eighth_child += 1;
				else stats.cutoff_ninth_or_later_child += 1;
			}
			break;
		}
	}
	if (has_best_action && limits != nullptr && !stats.aborted && stats.supported) {
		const uint64_t ordering_key = ensure_state_checksum();
		if (limits->current_ordering_hints != nullptr) {
			(*limits->current_ordering_hints)[ordering_key] = best_action;
		}
		if (limits->principal_actions != nullptr) {
			(*limits->principal_actions)[search_position_key_from_checksum(
				ordering_key,
				remaining_owner_turn_boundaries
			)] = best_action;
		}
	}
	TranspositionBound transposition_bound = TranspositionBound::EXACT;
	if (best_score <= original_alpha) {
		transposition_bound = TranspositionBound::UPPER;
	} else if (best_score >= original_beta) {
		transposition_bound = TranspositionBound::LOWER;
	}
	store_transposition(
		best_score,
		transposition_bound,
		has_best_action ? &best_action : nullptr
	);
	mark_transposition_completed();
	return best_score;
}

bool DuelNativeCompactKernel::parse_search_depth_mode(
	const StringName &name,
	SearchDepthMode &mode,
	String &reason
) const {
	if (name == StringName("complete_round")) {
		mode = SearchDepthMode::COMPLETE_ROUND;
		return true;
	}
	if (name == StringName("self_turn")) {
		mode = SearchDepthMode::SELF_TURN;
		return true;
	}
	reason = "Search depth mode must be complete_round or self_turn";
	return false;
}

int32_t DuelNativeCompactKernel::search_depth_boundaries(
	int32_t depth,
	SearchDepthMode mode
) const {
	if (depth <= 0) return 0;
	return mode == SearchDepthMode::SELF_TURN
		? depth * 2 - 1
		: depth * 2;
}

Dictionary DuelNativeCompactKernel::search_fixed_round_depth(
	int64_t root_owner_value,
	int64_t round_depth_value
) const {
	return search_fixed_depth(
		root_owner_value,
		round_depth_value,
		StringName("complete_round")
	);
}

Dictionary DuelNativeCompactKernel::search_fixed_depth(
	int64_t root_owner_value,
	int64_t depth_value,
	const StringName &depth_mode_name
) const {
	Dictionary result;
	result["supported"] = false;
	result["valid"] = false;
	result["score"] = 0;
	result["nodes"] = 0;
	result["leaves"] = 0;
	result["max_action_ply"] = 0;
	result["elapsed_usec"] = 0;
	result["depth_mode"] = depth_mode_name;
	if (!loaded) {
		result["reason"] = "No compact state is loaded";
		return result;
	}
	const int32_t root_owner = static_cast<int32_t>(root_owner_value);
	const int32_t depth = static_cast<int32_t>(depth_value);
	SearchDepthMode depth_mode = SearchDepthMode::COMPLETE_ROUND;
	String depth_mode_reason;
	if (!parse_search_depth_mode(depth_mode_name, depth_mode, depth_mode_reason)) {
		result["reason"] = depth_mode_reason;
		return result;
	}
	if (root_owner != 1 && root_owner != 2) {
		result["reason"] = "Root owner must be player 1 or player 2";
		return result;
	}
	if (depth <= 0) {
		result["reason"] = "Search depth must be positive";
		return result;
	}
	const int32_t owner_turn_boundaries = search_depth_boundaries(depth, depth_mode);
	result["owner_turn_boundaries"] = owner_turn_boundaries;
	if (state.scalars[0] != root_owner) {
		result["reason"] = "Root owner must be the active player";
		return result;
	}
	String support_reason;
	if (!validate_play_support(state, support_reason)) {
		result["reason"] = support_reason;
		return result;
	}
	const std::vector<NativeAction> root_actions = get_legal_native_actions(state, root_owner);
	result["supported"] = true;
	if (root_actions.empty()) {
		result["reason"] = "No legal root action";
		return result;
	}

	const auto started = std::chrono::steady_clock::now();
	NativeSearchStats stats;
	stats.root_actions_total = static_cast<int32_t>(root_actions.size());
	stats.generated_actions = static_cast<int64_t>(root_actions.size());
	const bool maximizing = state.scalars[0] == root_owner;
	int32_t best_score = maximizing
		? std::numeric_limits<int32_t>::min()
		: std::numeric_limits<int32_t>::max();
	NativeAction best_action;
	bool has_best_action = false;
	for (const NativeAction &action : root_actions) {
		stats.root_actions_started += 1;
		NativeState next;
		Resolution resolution;
		bool transition_supported = false;
		String transition_reason;
		if (!transition_action(
			state,
			action,
			next,
			resolution,
			transition_supported,
			transition_reason,
			false
		)) {
			stats.supported = false;
			stats.reason = transition_reason.is_empty()
				? String("Native search reached an invalid root transition")
				: transition_reason;
			break;
		}
		stats.applied_transitions += 1;
		const int32_t completed_owner_turns = std::max(next.scalars[2] - state.scalars[2], 0);
		const int32_t score = search_minimax(
			next,
			owner_turn_boundaries - completed_owner_turns,
			root_owner,
			1,
			std::numeric_limits<int32_t>::min(),
			std::numeric_limits<int32_t>::max(),
			stats,
			nullptr
		);
		if (!stats.supported) break;
		stats.root_actions_completed += 1;
		const bool better_score = !has_best_action
			|| (maximizing && score > best_score)
			|| (!maximizing && score < best_score);
		const bool better_tie = has_best_action
			&& score == best_score
			&& action_canonical_less(action, best_action);
		if (better_score || better_tie) {
			best_score = score;
			best_action = action;
			has_best_action = true;
		}
	}
	const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(
		std::chrono::steady_clock::now() - started
	);
	result["supported"] = stats.supported;
	result["reason"] = stats.reason;
	result["nodes"] = stats.nodes;
	result["leaves"] = stats.leaves;
	result["cutoffs"] = stats.cutoffs;
	result["generated_actions"] = stats.generated_actions;
	result["applied_transitions"] = stats.applied_transitions;
	result["max_action_ply"] = stats.max_action_ply;
	result["root_actions_total"] = stats.root_actions_total;
	result["root_actions_started"] = stats.root_actions_started;
	result["root_actions_completed"] = stats.root_actions_completed;
	result["elapsed_usec"] = static_cast<int64_t>(elapsed.count());
	if (!stats.supported || !has_best_action) return result;
	result["valid"] = true;
	result["score"] = best_score;
	result["action"] = materialize_action(best_action);
	return result;
}

Dictionary DuelNativeCompactKernel::search_iterative_round_depth(
	int64_t root_owner_value,
	int64_t max_round_depth_value,
	int64_t budget_usec_value,
	int64_t max_nodes_value,
	int64_t min_completed_depth_value,
	const Callable &should_cancel,
	const Callable &on_progress,
	bool use_internal_pv_ordering,
	bool use_history_ordering,
	bool collect_search_diagnostics,
	bool use_transposition_table,
	int64_t transposition_table_mib,
	bool include_deck_evaluation,
	bool include_danger_evaluation,
	bool include_tempo_evaluation
) const {
	return search_iterative_depth(
		root_owner_value,
		max_round_depth_value,
		budget_usec_value,
		max_nodes_value,
		min_completed_depth_value,
		StringName("complete_round"),
		should_cancel,
		on_progress,
		use_internal_pv_ordering,
		use_history_ordering,
		collect_search_diagnostics,
		use_transposition_table,
		transposition_table_mib,
		include_deck_evaluation,
		include_danger_evaluation,
		include_tempo_evaluation
	);
}

Dictionary DuelNativeCompactKernel::search_iterative_depth(
	int64_t root_owner_value,
	int64_t max_depth_value,
	int64_t budget_usec_value,
	int64_t max_nodes_value,
	int64_t min_completed_depth_value,
	const StringName &depth_mode_name,
	const Callable &should_cancel,
	const Callable &on_progress,
	bool use_internal_pv_ordering,
	bool use_history_ordering,
	bool collect_search_diagnostics,
	bool use_transposition_table,
	int64_t transposition_table_mib,
	bool include_deck_evaluation,
	bool include_danger_evaluation,
	bool include_tempo_evaluation
) const {
	Dictionary result;
	result["supported"] = false;
	result["valid"] = false;
	result["score"] = 0;
	result["completed_depth"] = 0;
	result["nodes"] = 0;
	result["leaves"] = 0;
	result["cutoffs"] = 0;
	result["generated_actions"] = 0;
	result["applied_transitions"] = 0;
	result["time_legal_actions_usec"] = 0;
	result["time_order_usec"] = 0;
	result["time_apply_usec"] = 0;
	result["time_evaluate_usec"] = 0;
	result["time_key_usec"] = 0;
	result["ordered_nodes"] = 0;
	result["visited_children"] = 0;
	result["cutoff_first_child"] = 0;
	result["cutoff_second_child"] = 0;
	result["cutoff_third_fourth_child"] = 0;
	result["cutoff_fifth_eighth_child"] = 0;
	result["cutoff_ninth_or_later_child"] = 0;
	result["pv_queries"] = 0;
	result["pv_hits"] = 0;
	result["pv_legal_hits"] = 0;
	result["pv_illegal_hits"] = 0;
	result["history_queries"] = 0;
	result["history_hits"] = 0;
	result["history_cutoffs"] = 0;
	result["transposition_probes"] = 0;
	result["transposition_hits"] = 0;
	result["transposition_completed_hits"] = 0;
	result["transposition_leaf_probes"] = 0;
	result["transposition_leaf_completed_hits"] = 0;
	result["transposition_internal_probes"] = 0;
	result["transposition_internal_completed_hits"] = 0;
	result["transposition_state_hits"] = 0;
	result["transposition_unique_keys"] = 0;
	result["transposition_completed_keys"] = 0;
	result["transposition_unique_states"] = 0;
	result["transposition_table_probes"] = 0;
	result["transposition_table_hits"] = 0;
	result["transposition_exact_hits"] = 0;
	result["transposition_bound_hits"] = 0;
	result["transposition_exact_returns"] = 0;
	result["transposition_bound_cutoffs"] = 0;
	result["transposition_stores"] = 0;
	result["transposition_updates"] = 0;
	result["transposition_replacements"] = 0;
	result["transposition_collisions"] = 0;
	result["transposition_move_queries"] = 0;
	result["transposition_move_legal_hits"] = 0;
	result["transposition_move_illegal_hits"] = 0;
	result["internal_pv_ordering_enabled"] = use_internal_pv_ordering;
	result["history_ordering_enabled"] = use_history_ordering;
	result["transposition_table_enabled"] = false;
	result["transposition_table_requested_mib"] = use_transposition_table
		? std::max(transposition_table_mib, static_cast<int64_t>(0))
		: 0;
	result["transposition_table_entry_size_bytes"] = static_cast<int64_t>(
		sizeof(TranspositionEntry)
	);
	result["transposition_table_set_count"] = 0;
	result["transposition_table_slot_count"] = 0;
	result["transposition_table_capacity_bytes"] = 0;
	result["transposition_table_allocation_fallback"] = false;
	result["search_diagnostics_enabled"] = collect_search_diagnostics;
	result["deck_evaluation_enabled"] = include_deck_evaluation;
	result["danger_evaluation_enabled"] = include_danger_evaluation;
	result["tempo_evaluation_enabled"] = include_tempo_evaluation;
	result["max_action_ply"] = 0;
	result["root_actions_total"] = 0;
	result["root_actions_started"] = 0;
	result["root_actions_completed"] = 0;
	result["minimum_depth_guard_used"] = false;
	result["nodes_over_limit"] = 0;
	result["elapsed_usec"] = 0;
	result["solved"] = false;
	result["completion_reason"] = StringName("invalid");
	result["iteration_depth"] = 0;
	result["depth_snapshots"] = Array();
	result["principal_actions"] = Array();
	result["depth_mode"] = depth_mode_name;
	if (!loaded) {
		result["reason"] = "No compact state is loaded";
		return result;
	}
	const int32_t root_owner = static_cast<int32_t>(root_owner_value);
	const int32_t max_depth = static_cast<int32_t>(max_depth_value);
	const int32_t min_completed_depth = std::max(
		static_cast<int32_t>(min_completed_depth_value),
		0
	);
	SearchDepthMode depth_mode = SearchDepthMode::COMPLETE_ROUND;
	String depth_mode_reason;
	if (!parse_search_depth_mode(depth_mode_name, depth_mode, depth_mode_reason)) {
		result["reason"] = depth_mode_reason;
		return result;
	}
	if (root_owner != 1 && root_owner != 2) {
		result["reason"] = "Root owner must be player 1 or player 2";
		return result;
	}
	if (max_depth < 0) {
		result["reason"] = "Maximum search depth cannot be negative";
		return result;
	}
	if (state.scalars[0] != root_owner) {
		result["reason"] = "Root owner must be the active player";
		return result;
	}
	String support_reason;
	if (!validate_play_support(state, support_reason)) {
		result["reason"] = support_reason;
		return result;
	}
	NativeSearchStats stats;
	const auto root_legal_started = collect_search_diagnostics
		? std::chrono::steady_clock::now()
		: std::chrono::steady_clock::time_point();
	const std::vector<NativeAction> root_actions = get_legal_native_actions(state, root_owner);
	if (collect_search_diagnostics) {
		stats.time_legal_actions_usec += std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now() - root_legal_started
		).count();
	}
	result["supported"] = true;
	if (root_actions.empty()) {
		result["reason"] = "No legal root action";
		result["completion_reason"] = StringName("no_legal_action");
		return result;
	}

	const auto started = std::chrono::steady_clock::now();
	TranspositionTable transposition_table;
	if (use_transposition_table && transposition_table_mib > 0) {
		initialize_transposition_table(transposition_table, transposition_table_mib);
	}
	result["transposition_table_enabled"] = transposition_table.enabled();
	result["transposition_table_set_count"] = static_cast<int64_t>(
		transposition_table.set_count
	);
	result["transposition_table_slot_count"] = static_cast<int64_t>(
		transposition_table.slot_count
	);
	result["transposition_table_capacity_bytes"] = static_cast<int64_t>(
		transposition_table.allocated_bytes
	);
	result["transposition_table_allocation_fallback"] =
		transposition_table.allocation_failed;
	NativeSearchLimits limits;
	limits.max_nodes = std::max(max_nodes_value, static_cast<int64_t>(0));
	limits.should_cancel = should_cancel;
	limits.use_internal_pv_ordering = use_internal_pv_ordering;
	limits.use_history_ordering = use_history_ordering;
	limits.use_transposition_table = transposition_table.enabled();
	limits.collect_search_diagnostics = collect_search_diagnostics;
	limits.include_deck_evaluation = include_deck_evaluation;
	limits.include_danger_evaluation = include_danger_evaluation;
	limits.include_tempo_evaluation = include_tempo_evaluation;
	limits.transposition_table = transposition_table.enabled()
		? &transposition_table
		: nullptr;
	if (budget_usec_value > 0) {
		limits.has_deadline = true;
		limits.deadline = started + std::chrono::microseconds(budget_usec_value);
	}
	NativeAction completed_best_action;
	bool has_completed_action = false;
	int32_t completed_best_score = 0;
	int32_t completed_depth = 0;
	bool solved = false;
	int32_t depth = 1;
	int32_t iteration_depth = 0;
	Array depth_snapshots;
	std::unordered_map<uint64_t, NativeAction> completed_principal_actions;
	std::unordered_map<uint64_t, NativeAction> completed_ordering_hints;
	HistoryTable history_scores;
	std::unordered_set<uint64_t> transposition_seen_keys;
	std::unordered_set<uint64_t> transposition_completed_keys;
	std::unordered_set<uint64_t> transposition_seen_states;
	limits.history_scores = use_history_ordering ? &history_scores : nullptr;
	limits.transposition_seen_keys = collect_search_diagnostics
		? &transposition_seen_keys
		: nullptr;
	limits.transposition_completed_keys = collect_search_diagnostics
		? &transposition_completed_keys
		: nullptr;
	limits.transposition_seen_states = collect_search_diagnostics
		? &transposition_seen_states
		: nullptr;
	while (max_depth <= 0 || depth <= max_depth) {
		iteration_depth = depth;
		limits.transposition_generation = static_cast<uint32_t>(depth);
		const int32_t owner_turn_boundaries = search_depth_boundaries(depth, depth_mode);
		limits.protect_node_limit = completed_depth < min_completed_depth;
		if (search_should_stop(stats, &limits)) break;
		std::unordered_map<uint64_t, NativeAction> iteration_principal_actions;
		std::unordered_map<uint64_t, NativeAction> iteration_ordering_hints;
		limits.principal_actions = &iteration_principal_actions;
		limits.previous_ordering_hints = use_internal_pv_ordering
			? &completed_ordering_hints
			: nullptr;
		limits.current_ordering_hints = use_internal_pv_ordering
			? &iteration_ordering_hints
			: nullptr;
		if (use_history_ordering) {
			for (auto history = history_scores.begin(); history != history_scores.end();) {
				history->second = decay_history_score(history->second);
				if (history->second <= 0) history = history_scores.erase(history);
				else ++history;
			}
		}
		stats.horizon_reached = false;
		const auto root_order_started = collect_search_diagnostics
			? std::chrono::steady_clock::now()
			: std::chrono::steady_clock::time_point();
		const std::vector<NativeAction> ordered_root_actions = order_search_actions(
			state,
			root_actions,
			has_completed_action ? &completed_best_action : nullptr,
			nullptr,
			use_history_ordering ? &history_scores : nullptr,
			&stats,
			collect_search_diagnostics
		);
		if (collect_search_diagnostics) {
			stats.time_order_usec += std::chrono::duration_cast<std::chrono::microseconds>(
				std::chrono::steady_clock::now() - root_order_started
			).count();
			stats.ordered_nodes += 1;
		}
		stats.root_actions_total = static_cast<int32_t>(ordered_root_actions.size());
		stats.root_actions_started = 0;
		stats.root_actions_completed = 0;
		stats.generated_actions += static_cast<int64_t>(root_actions.size());

		const bool maximizing = state.scalars[0] == root_owner;
		int32_t iteration_best_score = maximizing
			? std::numeric_limits<int32_t>::min()
			: std::numeric_limits<int32_t>::max();
		NativeAction iteration_best_action;
		bool has_iteration_action = false;
		int32_t alpha = std::numeric_limits<int32_t>::min();
		int32_t beta = std::numeric_limits<int32_t>::max();
		for (const NativeAction &action : ordered_root_actions) {
			if (search_should_stop(stats, &limits)) break;
			stats.root_actions_started += 1;
			if (collect_search_diagnostics) stats.visited_children += 1;
			NativeState next;
			Resolution resolution;
			bool transition_supported = false;
			String transition_reason;
			const auto root_apply_started = collect_search_diagnostics
				? std::chrono::steady_clock::now()
				: std::chrono::steady_clock::time_point();
			if (!transition_action(
				state,
				action,
				next,
				resolution,
				transition_supported,
				transition_reason,
				false
			)) {
				stats.supported = false;
				stats.reason = transition_reason.is_empty()
					? String("Native search reached an invalid root transition")
					: transition_reason;
				break;
			}
			if (collect_search_diagnostics) {
				stats.time_apply_usec += std::chrono::duration_cast<std::chrono::microseconds>(
					std::chrono::steady_clock::now() - root_apply_started
				).count();
			}
			stats.applied_transitions += 1;
			const int32_t completed_owner_turns = std::max(
				next.scalars[2] - state.scalars[2],
				0
			);
			int32_t score = search_minimax(
				next,
				owner_turn_boundaries - completed_owner_turns,
				root_owner,
				1,
				alpha,
				beta,
				stats,
				&limits
			);
			if (!stats.supported || stats.aborted) break;
			stats.root_actions_completed += 1;
			bool better_score = !has_iteration_action
				|| (maximizing && score > iteration_best_score)
				|| (!maximizing && score < iteration_best_score);
			bool better_tie = has_iteration_action
				&& score == iteration_best_score
				&& action_canonical_less(action, iteration_best_action);
			if (better_tie) {
				score = search_minimax(
					next,
					owner_turn_boundaries - completed_owner_turns,
					root_owner,
					1,
					std::numeric_limits<int32_t>::min(),
					std::numeric_limits<int32_t>::max(),
					stats,
					&limits
				);
				if (!stats.supported || stats.aborted) break;
				better_score = (maximizing && score > iteration_best_score)
					|| (!maximizing && score < iteration_best_score);
				better_tie = score == iteration_best_score;
			}
			if (better_score || better_tie) {
				iteration_best_score = score;
				iteration_best_action = action;
				has_iteration_action = true;
			}
			if (maximizing) alpha = std::max(alpha, iteration_best_score);
			else beta = std::min(beta, iteration_best_score);
		}
		if (!stats.supported || stats.aborted || !has_iteration_action) break;
		completed_best_action = iteration_best_action;
		completed_best_score = iteration_best_score;
		has_completed_action = true;
		completed_depth = depth;
		completed_principal_actions = std::move(iteration_principal_actions);
		if (use_internal_pv_ordering) {
			iteration_ordering_hints[checksum(state)] = iteration_best_action;
			completed_ordering_hints = std::move(iteration_ordering_hints);
		}
		Dictionary snapshot;
		snapshot["depth"] = depth;
		snapshot["owner_turn_boundaries"] = owner_turn_boundaries;
		snapshot["score"] = completed_best_score;
		snapshot["action"] = materialize_action(completed_best_action);
		snapshot["nodes"] = stats.nodes;
		snapshot["generated_actions"] = stats.generated_actions;
		snapshot["applied_transitions"] = stats.applied_transitions;
		snapshot["cutoffs"] = stats.cutoffs;
		snapshot["time_legal_actions_usec"] = stats.time_legal_actions_usec;
		snapshot["time_order_usec"] = stats.time_order_usec;
		snapshot["time_apply_usec"] = stats.time_apply_usec;
		snapshot["time_evaluate_usec"] = stats.time_evaluate_usec;
		snapshot["time_key_usec"] = stats.time_key_usec;
		snapshot["ordered_nodes"] = stats.ordered_nodes;
		snapshot["visited_children"] = stats.visited_children;
		snapshot["cutoff_first_child"] = stats.cutoff_first_child;
		snapshot["cutoff_second_child"] = stats.cutoff_second_child;
		snapshot["cutoff_third_fourth_child"] = stats.cutoff_third_fourth_child;
		snapshot["cutoff_fifth_eighth_child"] = stats.cutoff_fifth_eighth_child;
		snapshot["cutoff_ninth_or_later_child"] = stats.cutoff_ninth_or_later_child;
		snapshot["pv_queries"] = stats.pv_queries;
		snapshot["pv_hits"] = stats.pv_hits;
		snapshot["pv_legal_hits"] = stats.pv_legal_hits;
		snapshot["pv_illegal_hits"] = stats.pv_illegal_hits;
		snapshot["history_queries"] = stats.history_queries;
		snapshot["history_hits"] = stats.history_hits;
		snapshot["history_cutoffs"] = stats.history_cutoffs;
		snapshot["transposition_probes"] = stats.transposition_probes;
		snapshot["transposition_hits"] = stats.transposition_hits;
		snapshot["transposition_completed_hits"] = stats.transposition_completed_hits;
		snapshot["transposition_leaf_probes"] = stats.transposition_leaf_probes;
		snapshot["transposition_leaf_completed_hits"] = stats.transposition_leaf_completed_hits;
		snapshot["transposition_internal_probes"] = stats.transposition_internal_probes;
		snapshot["transposition_internal_completed_hits"] = stats.transposition_internal_completed_hits;
		snapshot["transposition_state_hits"] = stats.transposition_state_hits;
		snapshot["transposition_unique_keys"] = stats.transposition_unique_keys;
		snapshot["transposition_completed_keys"] = stats.transposition_completed_keys;
		snapshot["transposition_unique_states"] = stats.transposition_unique_states;
		snapshot["transposition_table_probes"] = stats.transposition_table_probes;
		snapshot["transposition_table_hits"] = stats.transposition_table_hits;
		snapshot["transposition_exact_hits"] = stats.transposition_exact_hits;
		snapshot["transposition_bound_hits"] = stats.transposition_bound_hits;
		snapshot["transposition_exact_returns"] = stats.transposition_exact_returns;
		snapshot["transposition_bound_cutoffs"] = stats.transposition_bound_cutoffs;
		snapshot["transposition_stores"] = stats.transposition_stores;
		snapshot["transposition_updates"] = stats.transposition_updates;
		snapshot["transposition_replacements"] = stats.transposition_replacements;
		snapshot["transposition_collisions"] = stats.transposition_collisions;
		snapshot["transposition_move_queries"] = stats.transposition_move_queries;
		snapshot["transposition_move_legal_hits"] = stats.transposition_move_legal_hits;
		snapshot["transposition_move_illegal_hits"] = stats.transposition_move_illegal_hits;
		snapshot["transposition_table_enabled"] = transposition_table.enabled();
		snapshot["transposition_table_requested_mib"] = result[
			"transposition_table_requested_mib"
		];
		snapshot["transposition_table_entry_size_bytes"] = static_cast<int64_t>(
			sizeof(TranspositionEntry)
		);
		snapshot["transposition_table_set_count"] = static_cast<int64_t>(
			transposition_table.set_count
		);
		snapshot["transposition_table_slot_count"] = static_cast<int64_t>(
			transposition_table.slot_count
		);
		snapshot["transposition_table_capacity_bytes"] = static_cast<int64_t>(
			transposition_table.allocated_bytes
		);
		snapshot["transposition_table_allocation_fallback"] =
			transposition_table.allocation_failed;
		snapshot["elapsed_usec"] = static_cast<int64_t>(
			std::chrono::duration_cast<std::chrono::microseconds>(
				std::chrono::steady_clock::now() - started
			).count()
		);
		depth_snapshots.append(snapshot);
		if (on_progress.is_valid()) {
			on_progress.call(snapshot);
		}
		if (
			limits.max_nodes > 0
			&& stats.nodes >= limits.max_nodes
			&& depth <= min_completed_depth
		) {
			stats.minimum_depth_guard_used = true;
		}
		solved = !stats.horizon_reached;
		if (solved) break;
		depth += 1;
	}
	limits.principal_actions = nullptr;
	limits.previous_ordering_hints = nullptr;
	limits.current_ordering_hints = nullptr;
	limits.history_scores = nullptr;
	limits.transposition_table = nullptr;
	limits.transposition_seen_keys = nullptr;
	limits.transposition_completed_keys = nullptr;
	limits.transposition_seen_states = nullptr;
	Array principal_actions;
	if (has_completed_action) {
		NativeState current = state;
		NativeAction current_action = completed_best_action;
		int32_t remaining_boundaries = search_depth_boundaries(completed_depth, depth_mode);
		const int32_t root_owner_turn_serial = state.scalars[2];
		for (int32_t plan_index = 0; plan_index < 20; ++plan_index) {
			principal_actions.append(materialize_action(current_action));
			NativeState next;
			Resolution resolution;
			bool transition_supported = false;
			String transition_reason;
			if (!transition_action(
				current,
				current_action,
				next,
				resolution,
				transition_supported,
				transition_reason,
				false
			)) break;
			remaining_boundaries -= std::max(next.scalars[2] - current.scalars[2], 0);
			current = std::move(next);
			if (
				is_terminal(current)
				|| current.scalars[0] != root_owner
				|| current.scalars[2] != root_owner_turn_serial
			) break;
			const uint64_t position_key = search_position_key(
				current,
				remaining_boundaries
			);
			const auto found = completed_principal_actions.find(position_key);
			if (found != completed_principal_actions.end()) {
				current_action = found->second;
				continue;
			}
			if (!transposition_table.enabled()) break;
			const TranspositionEntry *cached = probe_transposition_table(
				transposition_table,
				checksum(current),
				remaining_boundaries
			);
			if (cached == nullptr || !cached->has_best_action) break;
			const std::vector<NativeAction> legal_actions = get_legal_native_actions(
				current,
				current.scalars[0]
			);
			if (!restore_compact_action(
				cached->best_action,
				legal_actions,
				current_action
			)) break;
		}
	}

	const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(
		std::chrono::steady_clock::now() - started
	);
	result["supported"] = stats.supported;
	result["reason"] = stats.reason;
	result["score"] = completed_best_score;
	result["completed_depth"] = completed_depth;
	result["owner_turn_boundaries"] = search_depth_boundaries(
		completed_depth,
		depth_mode
	);
	result["nodes"] = stats.nodes;
	result["leaves"] = stats.leaves;
	result["cutoffs"] = stats.cutoffs;
	result["generated_actions"] = stats.generated_actions;
	result["applied_transitions"] = stats.applied_transitions;
	result["time_legal_actions_usec"] = stats.time_legal_actions_usec;
	result["time_order_usec"] = stats.time_order_usec;
	result["time_apply_usec"] = stats.time_apply_usec;
	result["time_evaluate_usec"] = stats.time_evaluate_usec;
	result["time_key_usec"] = stats.time_key_usec;
	result["ordered_nodes"] = stats.ordered_nodes;
	result["visited_children"] = stats.visited_children;
	result["cutoff_first_child"] = stats.cutoff_first_child;
	result["cutoff_second_child"] = stats.cutoff_second_child;
	result["cutoff_third_fourth_child"] = stats.cutoff_third_fourth_child;
	result["cutoff_fifth_eighth_child"] = stats.cutoff_fifth_eighth_child;
	result["cutoff_ninth_or_later_child"] = stats.cutoff_ninth_or_later_child;
	result["pv_queries"] = stats.pv_queries;
	result["pv_hits"] = stats.pv_hits;
	result["pv_legal_hits"] = stats.pv_legal_hits;
	result["pv_illegal_hits"] = stats.pv_illegal_hits;
	result["history_queries"] = stats.history_queries;
	result["history_hits"] = stats.history_hits;
	result["history_cutoffs"] = stats.history_cutoffs;
	result["transposition_probes"] = stats.transposition_probes;
	result["transposition_hits"] = stats.transposition_hits;
	result["transposition_completed_hits"] = stats.transposition_completed_hits;
	result["transposition_leaf_probes"] = stats.transposition_leaf_probes;
	result["transposition_leaf_completed_hits"] = stats.transposition_leaf_completed_hits;
	result["transposition_internal_probes"] = stats.transposition_internal_probes;
	result["transposition_internal_completed_hits"] = stats.transposition_internal_completed_hits;
	result["transposition_state_hits"] = stats.transposition_state_hits;
	result["transposition_unique_keys"] = stats.transposition_unique_keys;
	result["transposition_completed_keys"] = stats.transposition_completed_keys;
	result["transposition_unique_states"] = stats.transposition_unique_states;
	result["transposition_table_probes"] = stats.transposition_table_probes;
	result["transposition_table_hits"] = stats.transposition_table_hits;
	result["transposition_exact_hits"] = stats.transposition_exact_hits;
	result["transposition_bound_hits"] = stats.transposition_bound_hits;
	result["transposition_exact_returns"] = stats.transposition_exact_returns;
	result["transposition_bound_cutoffs"] = stats.transposition_bound_cutoffs;
	result["transposition_stores"] = stats.transposition_stores;
	result["transposition_updates"] = stats.transposition_updates;
	result["transposition_replacements"] = stats.transposition_replacements;
	result["transposition_collisions"] = stats.transposition_collisions;
	result["transposition_move_queries"] = stats.transposition_move_queries;
	result["transposition_move_legal_hits"] = stats.transposition_move_legal_hits;
	result["transposition_move_illegal_hits"] = stats.transposition_move_illegal_hits;
	result["max_action_ply"] = stats.max_action_ply;
	result["root_actions_total"] = stats.root_actions_total;
	result["root_actions_started"] = stats.root_actions_started;
	result["root_actions_completed"] = stats.root_actions_completed;
	result["minimum_depth_guard_used"] = stats.minimum_depth_guard_used;
	result["nodes_over_limit"] = limits.max_nodes > 0
		? std::max(stats.nodes - limits.max_nodes, static_cast<int64_t>(0))
		: 0;
	result["elapsed_usec"] = static_cast<int64_t>(elapsed.count());
	result["solved"] = solved;
	result["completion_reason"] = solved
		? StringName("solved")
		: stats.aborted
			? stats.stop_reason
			: StringName("max_depth");
	result["iteration_depth"] = iteration_depth;
	result["depth_snapshots"] = depth_snapshots;
	result["principal_actions"] = principal_actions;
	if (!stats.supported || !has_completed_action) return result;
	result["valid"] = true;
	result["action"] = materialize_action(completed_best_action);
	return result;
}


} // namespace godot
