#include "duel_native_compact_kernel.h"

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdlib>
#include <limits>
#include <utility>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/char_string.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {
namespace {

constexpr int32_t HISTORY_SCORE_LIMIT = 1'000'000;

std::vector<int32_t> to_int_vector(const PackedInt32Array &source) {
	std::vector<int32_t> result;
	result.resize(source.size());
	for (int64_t index = 0; index < source.size(); ++index) {
		result[static_cast<size_t>(index)] = source[index];
	}
	return result;
}

std::vector<uint8_t> to_byte_vector(const PackedByteArray &source) {
	std::vector<uint8_t> result;
	result.resize(source.size());
	for (int64_t index = 0; index < source.size(); ++index) {
		result[static_cast<size_t>(index)] = source[index];
	}
	return result;
}

PackedInt32Array to_packed_int32_array(const std::vector<int32_t> &source) {
	PackedInt32Array result;
	result.resize(static_cast<int64_t>(source.size()));
	for (size_t index = 0; index < source.size(); ++index) {
		result.set(static_cast<int64_t>(index), source[index]);
	}
	return result;
}

PackedByteArray to_packed_byte_array(const std::vector<uint8_t> &source) {
	PackedByteArray result;
	result.resize(static_cast<int64_t>(source.size()));
	for (size_t index = 0; index < source.size(); ++index) {
		result.set(static_cast<int64_t>(index), source[index]);
	}
	return result;
}

int32_t other_owner(int32_t owner_id) {
	return owner_id == 1 ? 2 : 1;
}

int32_t neighbor_index(int32_t cell, int32_t direction) {
	static constexpr int32_t row_deltas[4] = {-1, 0, 1, 0};
	static constexpr int32_t column_deltas[4] = {0, 1, 0, -1};
	const int32_t row = cell / 3;
	const int32_t column = cell % 3;
	const int32_t target_row = row + row_deltas[direction];
	const int32_t target_column = column + column_deltas[direction];
	if (target_row < 0 || target_row >= 3 || target_column < 0 || target_column >= 3) {
		return -1;
	}
	return target_row * 3 + target_column;
}

String bytes_to_hex(const CharString &bytes) {
	static constexpr char32_t digits[] = U"0123456789abcdef";
	String result;
	for (int64_t index = 0; index < bytes.length(); ++index) {
		const uint8_t byte = static_cast<uint8_t>(bytes[index]);
		result += digits[(byte >> 4) & 0x0f];
		result += digits[byte & 0x0f];
	}
	return result;
}

template <typename T>
void hash_values(uint64_t &hash, const std::vector<T> &values) {
	for (const T &value : values) {
		hash ^= static_cast<uint64_t>(value);
		hash *= 1099511628211ULL;
	}
}

} // namespace

void DuelNativeCompactKernel::_bind_methods() {
	ClassDB::bind_method(
		D_METHOD("load_compact_payload", "payload"),
		&DuelNativeCompactKernel::load_compact_payload
	);
	ClassDB::bind_method(D_METHOD("is_loaded"), &DuelNativeCompactKernel::is_loaded);
	ClassDB::bind_method(D_METHOD("get_last_error"), &DuelNativeCompactKernel::get_last_error);
	ClassDB::bind_method(D_METHOD("inspect_layout"), &DuelNativeCompactKernel::inspect_layout);
	ClassDB::bind_method(
		D_METHOD("benchmark_core_clone", "iterations"),
		&DuelNativeCompactKernel::benchmark_core_clone
	);
	ClassDB::bind_method(
		D_METHOD(
			"apply_play_transition",
			"hand_index",
			"target_cell",
			"expected_instance_id"
		),
		&DuelNativeCompactKernel::apply_play_transition,
		DEFVAL(StringName())
	);
	ClassDB::bind_method(
		D_METHOD("get_legal_actions_for_owner", "owner_id"),
		&DuelNativeCompactKernel::get_legal_actions_for_owner
	);
	ClassDB::bind_method(
		D_METHOD("count_legal_actions_for_owner", "owner_id"),
		&DuelNativeCompactKernel::count_legal_actions_for_owner
	);
	ClassDB::bind_method(
		D_METHOD(
			"inspect_ordered_search_actions_for_owner",
			"owner_id",
			"preferred_action"
		),
		&DuelNativeCompactKernel::inspect_ordered_search_actions_for_owner,
		DEFVAL(Dictionary())
	);
	ClassDB::bind_method(
		D_METHOD("inspect_history_keys_for_owner", "owner_id"),
		&DuelNativeCompactKernel::inspect_history_keys_for_owner
	);
	ClassDB::bind_method(
		D_METHOD(
			"inspect_history_score_policy",
			"initial_score",
			"remaining_owner_turn_boundaries",
			"cutoff_updates",
			"public_depth_decays"
		),
		&DuelNativeCompactKernel::inspect_history_score_policy
	);
	ClassDB::bind_method(
		D_METHOD(
			"apply_activate_transition",
			"source_cell",
			"target_kind",
			"target_index",
			"activation_index",
			"expected_instance_id"
		),
		&DuelNativeCompactKernel::apply_activate_transition,
		DEFVAL(0),
		DEFVAL(StringName())
	);
	ClassDB::bind_method(
		D_METHOD("resolve_event_transition", "event_id", "context"),
		&DuelNativeCompactKernel::resolve_event_transition
	);
	ClassDB::bind_method(
		D_METHOD("resolve_attack_transition", "request"),
		&DuelNativeCompactKernel::resolve_attack_transition
	);
	ClassDB::bind_method(
		D_METHOD(
			"resolve_non_attack_flip_transition",
			"target_instance_id",
			"new_owner",
			"reason"
		),
		&DuelNativeCompactKernel::resolve_non_attack_flip_transition,
		DEFVAL(StringName("non_attack_flip"))
	);
	ClassDB::bind_method(
		D_METHOD("search_fixed_round_depth", "root_owner", "round_depth"),
		&DuelNativeCompactKernel::search_fixed_round_depth
	);
	ClassDB::bind_method(
		D_METHOD("search_fixed_depth", "root_owner", "depth", "depth_mode"),
		&DuelNativeCompactKernel::search_fixed_depth
	);
	ClassDB::bind_method(
		D_METHOD(
			"search_iterative_round_depth",
			"root_owner",
			"max_round_depth",
			"budget_usec",
			"max_nodes",
			"min_completed_depth",
			"should_cancel",
			"on_progress",
			"use_internal_pv_ordering",
			"use_history_ordering",
			"collect_search_diagnostics"
		),
		&DuelNativeCompactKernel::search_iterative_round_depth,
		DEFVAL(Callable()),
		DEFVAL(false),
		DEFVAL(false),
		DEFVAL(false)
	);
	ClassDB::bind_method(
		D_METHOD(
			"search_iterative_depth",
			"root_owner",
			"max_depth",
			"budget_usec",
			"max_nodes",
			"min_completed_depth",
			"depth_mode",
			"should_cancel",
			"on_progress",
			"use_internal_pv_ordering",
			"use_history_ordering",
			"collect_search_diagnostics"
		),
		&DuelNativeCompactKernel::search_iterative_depth,
		DEFVAL(Callable()),
		DEFVAL(false),
		DEFVAL(false),
		DEFVAL(false)
	);
}

bool DuelNativeCompactKernel::load_compact_payload(const Dictionary &payload) {
	loaded = false;
	last_error = String();
	if (static_cast<int64_t>(payload.get("format_version", 0)) != 1) {
		last_error = "Unsupported compact-state format version";
		return false;
	}

	state.scalars = to_int_vector(payload.get("scalars", PackedInt32Array()));
	state.board_card_indices = to_int_vector(
		payload.get("board_card_indices", PackedInt32Array())
	);
	state.board_owners = to_byte_vector(payload.get("board_owners", PackedByteArray()));
	state.card_template_indices = to_int_vector(
		payload.get("card_template_indices", PackedInt32Array())
	);
	state.card_runtime_flags = to_byte_vector(
		payload.get("card_runtime_flags", PackedByteArray())
	);
	state.card_powers = to_int_vector(payload.get("card_powers", PackedInt32Array()));
	state.card_original_owners = to_byte_vector(
		payload.get("card_original_owners", PackedByteArray())
	);
	state.card_ki = to_int_vector(payload.get("card_ki", PackedInt32Array()));
	state.card_active_ability_set_indices = to_int_vector(
		payload.get("card_active_ability_set_indices", PackedInt32Array())
	);
	state.card_reveal_codes = to_byte_vector(
		payload.get("card_reveal_codes", PackedByteArray())
	);
	state.card_suppression_set_indices = to_int_vector(
		payload.get("card_suppression_set_indices", PackedInt32Array())
	);
	state.card_hand_slots = to_int_vector(
		payload.get("card_hand_slots", PackedInt32Array())
	);
	state.board_slot_extras = payload.get("board_slot_extras", Array());
	state.card_template_pool = payload.get("card_template_pool", Array());
	state.active_ability_set_pool = payload.get("active_ability_set_pool", Array());
	state.suppression_set_pool = payload.get("suppression_set_pool", Array());
	const Variant fresh_prototypes_value = payload.get("fresh_card_prototypes", Array());
	if (fresh_prototypes_value.get_type() != Variant::ARRAY) {
		last_error = "Fresh-card prototype pool is not an Array";
		return false;
	}
	state.fresh_card_prototype_pool = fresh_prototypes_value;
	const Variant fallback_index_value = payload.get("empty_deck_draw_prototype_index", -1);
	if (fallback_index_value.get_type() != Variant::INT) {
		last_error = "Empty-deck fallback prototype index is not an integer";
		return false;
	}
	state.empty_deck_draw_prototype_index = static_cast<int32_t>(
		static_cast<int64_t>(fallback_index_value)
	);
	state.side_payload = payload.get("side_payload", Dictionary());
	state.has_rule_metadata = (
		payload.has("card_template_pool")
		&& payload.has("active_ability_set_pool")
		&& payload.has("suppression_set_pool")
	);

	state.card_instance_ids.clear();
	const Array instance_ids = payload.get("card_instance_ids", Array());
	state.card_instance_ids.reserve(static_cast<size_t>(instance_ids.size()));
	for (int64_t index = 0; index < instance_ids.size(); ++index) {
		state.card_instance_ids.push_back(instance_ids[index]);
	}

	state.zones.clear();
	const Array zones = payload.get("zones", Array());
	state.zones.reserve(static_cast<size_t>(zones.size()));
	for (int64_t index = 0; index < zones.size(); ++index) {
		state.zones.push_back(to_int_vector(zones[index]));
	}

	state.fresh_card_prototypes.clear();
	state.fresh_card_prototypes.reserve(
		static_cast<size_t>(state.fresh_card_prototype_pool.size())
	);
	for (int64_t index = 0; index < state.fresh_card_prototype_pool.size(); ++index) {
		const Variant prototype_value = state.fresh_card_prototype_pool[index];
		if (prototype_value.get_type() != Variant::DICTIONARY) {
			last_error = "Fresh-card prototype pool contains a non-Dictionary value";
			return false;
		}
		const Dictionary prototype = prototype_value;
		const Variant powers_value = prototype.get("powers", Variant());
		if (
			prototype.size() != 5
			|| Variant(prototype.get("card_id", Variant())).get_type() != Variant::STRING_NAME
			|| Variant(prototype.get("template_index", Variant())).get_type() != Variant::INT
			|| powers_value.get_type() != Variant::ARRAY
			|| Variant(prototype.get("ki", Variant())).get_type() != Variant::INT
			|| Variant(prototype.get("active_ability_set_index", Variant())).get_type() != Variant::INT
		) {
			last_error = "Fresh-card prototype has an invalid declaration shape";
			return false;
		}
		const Array powers = powers_value;
		if (powers.size() != 4) {
			last_error = "Fresh-card prototype must have exactly four powers";
			return false;
		}
		FreshCardPrototype compiled;
		compiled.card_id = prototype.get("card_id", StringName());
		compiled.template_index = static_cast<int32_t>(
			static_cast<int64_t>(prototype.get("template_index", -1))
		);
		for (int32_t direction = 0; direction < 4; ++direction) {
			if (Variant(powers[direction]).get_type() != Variant::INT) {
				last_error = "Fresh-card prototype power is not an integer";
				return false;
			}
			compiled.powers[direction] = static_cast<int32_t>(
				static_cast<int64_t>(powers[direction])
			);
		}
		compiled.ki = static_cast<int32_t>(static_cast<int64_t>(prototype.get("ki", 0)));
		compiled.active_ability_set_index = static_cast<int32_t>(
			static_cast<int64_t>(prototype.get("active_ability_set_index", -1))
		);
		for (const FreshCardPrototype &existing : state.fresh_card_prototypes) {
			if (existing.card_id == compiled.card_id) {
				last_error = "Fresh-card prototype IDs must be unique";
				return false;
			}
		}
		state.fresh_card_prototypes.push_back(compiled);
	}

	state.card_ids.clear();
	state.card_ids.resize(state.card_instance_ids.size());
	if (state.has_rule_metadata) {
		for (size_t card_index = 0; card_index < state.card_template_indices.size(); ++card_index) {
			const int32_t template_index = state.card_template_indices[card_index];
			if (template_index < 0 || template_index >= state.card_template_pool.size()) {
				continue;
			}
			const Variant template_value = state.card_template_pool[template_index];
			if (template_value.get_type() != Variant::DICTIONARY) {
				continue;
			}
			const Dictionary card_template = template_value;
			state.card_ids[card_index] = card_template.get("card_id", StringName());
		}
	}

	loaded = validate_shape();
	if (loaded) {
		compile_ability_sets();
		state.next_ability_handle = 1;
		state.card_runtime_abilities.clear();
		state.card_runtime_abilities.reserve(state.card_instance_ids.size());
		for (size_t card_index = 0; card_index < state.card_instance_ids.size(); ++card_index) {
			const int32_t set_index = state.card_active_ability_set_indices[card_index];
			const std::vector<int32_t> *ability_indices = (
				set_index >= 0 && set_index < static_cast<int32_t>(compiled_ability_sets.size())
				? &compiled_ability_sets[set_index].ability_pool_indices
				: nullptr
			);
			std::vector<RuntimeAbilityEntry> runtime_entries;
			if (ability_indices != nullptr) {
				runtime_entries.reserve(ability_indices->size());
				for (const int32_t compiled_index : *ability_indices) {
					RuntimeAbilityEntry entry;
					entry.compiled_ability_index = compiled_index;
					entry.handle = state.next_ability_handle++;
					runtime_entries.push_back(entry);
				}
			}
			state.card_runtime_abilities.push_back(runtime_entries);
		}
		loaded = compile_runtime_suppression_batches();
	}
	return loaded;
}

bool DuelNativeCompactKernel::is_loaded() const {
	return loaded;
}

String DuelNativeCompactKernel::get_last_error() const {
	return last_error;
}

Dictionary DuelNativeCompactKernel::inspect_layout() const {
	Dictionary result;
	result["loaded"] = loaded;
	result["last_error"] = last_error;
	result["scalar_count"] = static_cast<int64_t>(state.scalars.size());
	result["board_cell_count"] = static_cast<int64_t>(state.board_card_indices.size());
	result["zone_count"] = static_cast<int64_t>(state.zones.size());
	result["card_count"] = static_cast<int64_t>(state.card_instance_ids.size());
	result["power_count"] = static_cast<int64_t>(state.card_powers.size());
	result["compiled_ability_set_count"] = static_cast<int64_t>(
		compiled_ability_sets.size()
	);
	int64_t invalid_ability_count = 0;
	Array invalid_ability_declarations;
	Array invalid_ability_diagnostics;
	for (size_t index = 0; index < compiled_ability_pool.size(); ++index) {
		if (!compiled_ability_pool[index].declaration_valid) {
			++invalid_ability_count;
			if (index < ability_declaration_pool.size()) {
				invalid_ability_declarations.append(ability_declaration_pool[index]);
			}
			const CompiledAbility &ability = compiled_ability_pool[index];
			Dictionary diagnostic;
			diagnostic["pool_index"] = static_cast<int64_t>(index);
			diagnostic["activation_valid"] = ability.activation.declaration_valid;
			Array modifier_opcodes;
			for (const CompiledModifier &modifier : ability.modifiers) {
				modifier_opcodes.append(static_cast<int64_t>(modifier.opcode));
			}
			diagnostic["modifier_opcodes"] = modifier_opcodes;
			Array trigger_diagnostics;
			for (const CompiledTriggerRule &trigger : ability.triggers) {
				Dictionary trigger_diagnostic;
				trigger_diagnostic["event"] = trigger.event_id;
				Array condition_opcodes;
				for (const CompiledCondition &condition : trigger.conditions) {
					condition_opcodes.append(static_cast<int64_t>(condition.opcode));
				}
				trigger_diagnostic["condition_opcodes"] = condition_opcodes;
				Array action_diagnostics;
				for (const CompiledAction &action : trigger.actions) {
					Dictionary action_diagnostic;
					action_diagnostic["type"] = action.declaration_type;
					action_diagnostic["opcode"] = static_cast<int64_t>(action.opcode);
					action_diagnostic["valid"] = action.declaration_valid;
					action_diagnostic["selector_valid"] = action.selector.declaration_valid;
					Array child_diagnostics;
					for (const CompiledAction &child : action.child_actions) {
						Dictionary child_diagnostic;
						child_diagnostic["type"] = child.declaration_type;
						child_diagnostic["opcode"] = static_cast<int64_t>(child.opcode);
						child_diagnostic["valid"] = child.declaration_valid;
						child_diagnostic["granted_ability_index"] = child.granted_ability_index;
						child_diagnostics.append(child_diagnostic);
					}
					action_diagnostic["children"] = child_diagnostics;
					action_diagnostics.append(action_diagnostic);
				}
				trigger_diagnostic["actions"] = action_diagnostics;
				trigger_diagnostics.append(trigger_diagnostic);
			}
			diagnostic["triggers"] = trigger_diagnostics;
			invalid_ability_diagnostics.append(diagnostic);
		}
	}
	int64_t invalid_ability_set_count = 0;
	Array invalid_ability_set_indices;
	for (size_t index = 0; index < compiled_ability_sets.size(); ++index) {
		if (!compiled_ability_sets[index].declaration_valid) {
			++invalid_ability_set_count;
			invalid_ability_set_indices.append(static_cast<int64_t>(index));
		}
	}
	result["compiled_ability_count"] = static_cast<int64_t>(compiled_ability_pool.size());
	result["invalid_compiled_ability_count"] = invalid_ability_count;
	result["invalid_compiled_ability_set_count"] = invalid_ability_set_count;
	result["invalid_compiled_ability_declarations"] = invalid_ability_declarations;
	result["invalid_compiled_ability_diagnostics"] = invalid_ability_diagnostics;
	result["invalid_compiled_ability_set_indices"] = invalid_ability_set_indices;
	result["fresh_card_prototype_count"] = static_cast<int64_t>(
		state.fresh_card_prototypes.size()
	);
	result["checksum"] = static_cast<int64_t>(checksum(state) & 0x7fffffffffffffffULL);
	return result;
}

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
	if (action.type == NativeActionType::ACTIVATE) return 500;
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
		? 20
		: (action.target_index == 0 || action.target_index == 2
			|| action.target_index == 6 || action.target_index == 8 ? 10 : 0);
	for (int32_t direction = 0; direction < 4; ++direction) {
		const int32_t neighbor = neighbor_index(action.target_index, direction);
		if (neighbor < 0) continue;
		const int32_t neighbor_card = value.board_card_indices[neighbor];
		if (neighbor_card < 0) continue;
		if (value.board_owners[neighbor] == owner_id) {
			score += 5;
			continue;
		}
		score += 25;
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
	const HistoryTable *history_scores,
	NativeSearchStats *stats,
	bool collect_diagnostics
) const {
	for (NativeAction &action : actions) {
		action.ordering_preferred = preferred != nullptr
			&& actions_equal(action, *preferred);
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

Dictionary DuelNativeCompactKernel::apply_play_transition(
	int64_t hand_index,
	int64_t target_cell,
	const StringName &expected_instance_id
) const {
	Dictionary result;
	result["supported"] = false;
	result["valid"] = false;
	result["captures"] = Array();
	result["exiles"] = Array();
	result["events"] = Array();
	if (!loaded) {
		result["reason"] = "No compact state is loaded";
		return result;
	}
	NativeAction action;
	action.type = NativeActionType::PLAY;
	action.source_index = static_cast<int32_t>(hand_index);
	action.source_instance_id = expected_instance_id;
	action.target_index = static_cast<int32_t>(target_cell);
	NativeState next;
	Resolution resolution;
	bool supported = false;
	String reason;
	const bool valid = transition_play(
		state,
		action,
		next,
		resolution,
		supported,
		reason
	);
	result["supported"] = supported;
	result["valid"] = valid;
	result["reason"] = reason;
	if (!valid) return result;
	result["captures"] = resolution.captures;
	result["exiles"] = resolution.exiles;
	result["events"] = resolution.events;
	result["payload"] = to_variant_payload(next);
	return result;
}

bool DuelNativeCompactKernel::transition_play(
	const NativeState &source,
	const NativeAction &action,
	NativeState &next,
	Resolution &resolution,
	bool &supported,
	String &reason
) const {
	supported = false;
	reason = String();
	if (!validate_play_support(source, reason)) return false;
	supported = true;
	const int32_t hand_index = action.source_index;
	const int32_t target_cell = action.target_index;
	const int32_t moving_owner = source.scalars[0];
	const int32_t hand_zone_index = moving_owner - 1;
	if (hand_zone_index < 0 || hand_zone_index >= static_cast<int32_t>(source.zones.size())) {
		reason = "Active owner has no compact hand zone";
		return false;
	}
	const std::vector<int32_t> &source_hand = source.zones[hand_zone_index];
	if (hand_index < 0 || hand_index >= static_cast<int32_t>(source_hand.size())) {
		reason = "Hand index is outside the active owner's hand";
		return false;
	}
	if (target_cell < 0 || target_cell >= static_cast<int32_t>(source.board_card_indices.size())) {
		reason = "Target cell is outside the board";
		return false;
	}
	if (source.board_card_indices[static_cast<size_t>(target_cell)] != -1) {
		reason = "Target board cell is occupied";
		return false;
	}
	const int32_t played_card_index = source_hand[static_cast<size_t>(hand_index)];
	if (played_card_index < 0 || played_card_index >= static_cast<int32_t>(source.card_instance_ids.size())) {
		reason = "Hand references an invalid card index";
		return false;
	}
	const StringName played_instance_id = source.card_instance_ids[played_card_index];
	if (!action.source_instance_id.is_empty() && action.source_instance_id != played_instance_id) {
		reason = "Expected instance ID does not match the hand card";
		return false;
	}
	const NativeState *support_state = &source;
	NativeState pending_adjusted_state;
	const int32_t pending_scalar_index = moving_owner == 1 ? 8 : 9;
	if (
		source.scalars[pending_scalar_index] > 0
		&& !card_is_heart_method(source, played_card_index)
	) {
		pending_adjusted_state = source;
		std::vector<RuntimeAbilityEntry> retained_entries;
		for (const RuntimeAbilityEntry &entry : pending_adjusted_state.card_runtime_abilities[played_card_index]) {
			if (
				entry.compiled_ability_index >= 0
				&& entry.compiled_ability_index < static_cast<int32_t>(compiled_ability_pool.size())
				&& compiled_ability_pool[entry.compiled_ability_index].retained_on_flip
			) retained_entries.push_back(entry);
		}
		pending_adjusted_state.card_runtime_abilities[played_card_index] = retained_entries;
		clear_runtime_suppression(pending_adjusted_state, played_card_index);
		support_state = &pending_adjusted_state;
	}
	if (!validate_action_rule_support(
			*support_state,
			played_card_index,
			target_cell,
			reason
		)) {
		supported = false;
		return false;
	}

	next = source;
	next.board_slot_extras = source.board_slot_extras.duplicate(true);
	next.side_payload = source.side_payload.duplicate(true);
	if (next.scalars[5] > 0) {
		next.scalars[13] = 1;
		next.scalars[5] -= 1;
	}
	std::vector<int32_t> &next_hand = next.zones[hand_zone_index];
	next_hand.erase(next_hand.begin() + hand_index);
	next.card_runtime_flags[played_card_index] &= static_cast<uint8_t>(~(1 << 7));
	next.card_hand_slots[played_card_index] = -1;
	if (moving_owner == 1) {
		if (next.card_reveal_codes[played_card_index] == 0) {
			next.card_reveal_codes[played_card_index] = 1;
		} else if (next.card_reveal_codes[played_card_index] == 2) {
			next.card_reveal_codes[played_card_index] = 4;
		}
	} else if (moving_owner == 2) {
		if (next.card_reveal_codes[played_card_index] == 0) {
			next.card_reveal_codes[played_card_index] = 2;
		} else if (next.card_reveal_codes[played_card_index] == 1) {
			next.card_reveal_codes[played_card_index] = 3;
		}
	}
	next.board_card_indices[static_cast<size_t>(target_cell)] = played_card_index;
	next.board_owners[static_cast<size_t>(target_cell)] = static_cast<uint8_t>(moving_owner);
	if (target_cell < next.board_slot_extras.size()) {
		next.board_slot_extras[target_cell] = Dictionary();
	}

	resolution = Resolution();
	std::vector<int32_t> exile_stack;
	Dictionary placed_event;
	placed_event["type"] = StringName("card_placed");
	placed_event["source_cell"] = target_cell;
	placed_event["target_cell"] = target_cell;
	placed_event["owner_id"] = moving_owner;
	placed_event["instance_id"] = played_instance_id;
	Resolution hand_change_resolution = resolve_difficulty_hand_change(
		next,
		moving_owner,
		static_cast<int32_t>(source_hand.size()),
		static_cast<int32_t>(next_hand.size()),
		static_cast<int32_t>(target_cell),
		exile_stack
	);
	if (!hand_change_resolution.supported) {
		supported = false;
		reason = hand_change_resolution.reason;
		return false;
	}
	const Array hand_change_events = hand_change_resolution.events;
	hand_change_resolution.events = Array();
	append_resolution(resolution, hand_change_resolution);
	Resolution suppression_resolution = consume_pending_hand_play_suppression(
		next,
		played_card_index,
		moving_owner,
		static_cast<int32_t>(target_cell)
	);
	append_resolution(resolution, suppression_resolution);

	SummonRequest summon_request;
	summon_request.summon_cell = static_cast<int32_t>(target_cell);
	summon_request.card_index = played_card_index;
	summon_request.owner_id = moving_owner;
	summon_request.summon_reason = StringName("hand_play");
	summon_request.attack_reason = StringName("summon_standard_attack");
	summon_request.attack_redirect_source_card_indices =
		snapshot_summon_attack_redirect_sources(
			next,
			static_cast<int32_t>(target_cell),
			moving_owner
		);
	summon_request.attack_redirect_snapshot_taken = true;
	summon_request.buffered_placement_events.append(placed_event);
	summon_request.buffered_placement_events.append_array(hand_change_events);
	Resolution summon_resolution = resolve_summon_lifecycle(
		next,
		summon_request,
		exile_stack
	);
	if (!summon_resolution.supported) {
		supported = false;
		reason = summon_resolution.reason;
		return false;
	}
	append_resolution(resolution, summon_resolution);

	Resolution finish_resolution = finish_action(
		next,
		moving_owner,
		played_card_index,
		resolution.extra_play_requests,
		exile_stack
	);
	if (!finish_resolution.supported) {
		supported = false;
		reason = finish_resolution.reason;
		return false;
	}
	append_resolution(resolution, finish_resolution);
	return true;
}

Dictionary DuelNativeCompactKernel::apply_activate_transition(
	int64_t source_cell_value,
	const StringName &target_kind,
	int64_t target_index_value,
	int64_t activation_index_value,
	const StringName &expected_instance_id
) const {
	Dictionary result;
	result["supported"] = false;
	result["valid"] = false;
	result["captures"] = Array();
	result["exiles"] = Array();
	result["events"] = Array();
	if (!loaded) {
		result["reason"] = "No compact state is loaded";
		return result;
	}
	NativeAction action;
	action.type = NativeActionType::ACTIVATE;
	action.source_index = static_cast<int32_t>(source_cell_value);
	action.source_instance_id = expected_instance_id;
	action.target_is_hand_slot = target_kind == StringName("hand_slot");
	action.target_index = static_cast<int32_t>(target_index_value);
	action.activation_index = static_cast<int32_t>(activation_index_value);
	NativeState next;
	Resolution resolution;
	bool supported = false;
	String reason;
	const bool valid = transition_activate(
		state,
		action,
		next,
		resolution,
		supported,
		reason
	);
	result["supported"] = supported;
	result["valid"] = valid;
	result["reason"] = reason;
	if (!valid) return result;
	result["captures"] = resolution.captures;
	result["exiles"] = resolution.exiles;
	result["events"] = resolution.events;
	result["payload"] = to_variant_payload(next);
	return result;
}

int32_t DuelNativeCompactKernel::find_card_by_instance_id(
	const NativeState &value,
	const StringName &instance_id
) const {
	if (instance_id.is_empty()) return -1;
	for (size_t index = 0; index < value.card_instance_ids.size(); ++index) {
		if (value.card_instance_ids[index] == instance_id) {
			return static_cast<int32_t>(index);
		}
	}
	return -1;
}

DuelNativeCompactKernel::AttackPolicy DuelNativeCompactKernel::attack_policy_from_dictionary(
	const Dictionary &value
) const {
	AttackPolicy policy;
	const StringName target_policy = value.get(
		"attack_target_policy",
		StringName("enemies_only")
	);
	if (target_policy == StringName("allies_only")) {
		policy.target_policy = AttackTargetPolicy::ALLIES_ONLY;
	} else if (target_policy == StringName("all")) {
		policy.target_policy = AttackTargetPolicy::ALL;
	} else {
		policy.target_policy = AttackTargetPolicy::ENEMIES_ONLY;
	}
	policy.capture_owner_id = static_cast<int32_t>(value.get("capture_owner_id", 0));
	policy.specified = value.has("attack_target_policy") || value.has("capture_owner_id");
	return policy;
}

DuelNativeCompactKernel::EventContext DuelNativeCompactKernel::event_context_from_dictionary(
	const NativeState &value,
	const Dictionary &context
) const {
	EventContext result;
	auto zone_kind = [](const StringName &zone) -> int32_t {
		if (zone == StringName("board")) return 0;
		if (zone == StringName("hand")) return 1;
		if (zone == StringName("deck")) return 2;
		if (zone == StringName("discard")) return 3;
		if (zone == StringName("removed")) return 4;
		return -1;
	};
	auto card_from = [&](const char *key) -> int32_t {
		return find_card_by_instance_id(value, StringName(context.get(key, StringName())));
	};

	result.ability_source_cell = static_cast<int32_t>(context.get("ability_source_cell", -1));
	result.ability_source_card_index = card_from("ability_source_instance_id");
	result.ability_source_owner = static_cast<int32_t>(context.get("ability_source_owner_id", 0));
	result.ability_source_zone = zone_kind(StringName(context.get("ability_source_zone", StringName())));
	result.ability_source_logical_index = static_cast<int32_t>(context.get("ability_source_logical_index", -1));
	if (result.ability_source_card_index >= 0) {
		int32_t located_zone = -1;
		int32_t located_owner = 0;
		int32_t located_index = -1;
		if (locate_card(value, result.ability_source_card_index, located_zone, located_owner, located_index)) {
			if (result.ability_source_zone < 0) result.ability_source_zone = located_zone;
			if (result.ability_source_owner == 0) result.ability_source_owner = located_owner;
			if (result.ability_source_logical_index < 0) result.ability_source_logical_index = located_index;
			if (result.ability_source_cell < 0 && located_zone == 0) result.ability_source_cell = located_index;
		}
	}

	result.trigger_cell = static_cast<int32_t>(context.get("trigger_cell", -1));
	result.trigger_card_index = card_from("trigger_instance_id");
	if (
		result.trigger_card_index < 0
		&& result.trigger_cell >= 0
		&& result.trigger_cell < static_cast<int32_t>(value.board_card_indices.size())
	) result.trigger_card_index = value.board_card_indices[result.trigger_cell];
	result.trigger_owner = static_cast<int32_t>(context.get("trigger_owner_id", 0));
	result.trigger_previous_owner = static_cast<int32_t>(context.get(
		"trigger_previous_owner_id",
		result.trigger_owner
	));
	result.trigger_zone = zone_kind(StringName(context.get("trigger_zone", StringName())));
	result.trigger_logical_index = static_cast<int32_t>(context.get("trigger_logical_index", -1));
	if (result.trigger_card_index >= 0) {
		int32_t located_zone = -1;
		int32_t located_owner = 0;
		int32_t located_index = -1;
		if (locate_card(value, result.trigger_card_index, located_zone, located_owner, located_index)) {
			if (result.trigger_zone < 0) result.trigger_zone = located_zone;
			if (result.trigger_owner == 0) result.trigger_owner = located_owner;
			if (result.trigger_previous_owner == 0) result.trigger_previous_owner = result.trigger_owner;
			if (result.trigger_logical_index < 0) result.trigger_logical_index = located_index;
			if (result.trigger_cell < 0 && located_zone == 0) result.trigger_cell = located_index;
		}
	}
	result.trigger_was_on_board = bool(context.get(
		"trigger_was_on_board",
		result.trigger_zone == 0 || result.trigger_cell >= 0
	));

	result.attacker_cell = static_cast<int32_t>(context.get("attacker_cell", -1));
	result.attacker_card_index = card_from("attacker_instance_id");
	if (
		result.attacker_card_index < 0
		&& result.attacker_cell >= 0
		&& result.attacker_cell < static_cast<int32_t>(value.board_card_indices.size())
	) result.attacker_card_index = value.board_card_indices[result.attacker_cell];
	result.attacker_owner = static_cast<int32_t>(context.get("attacker_owner_id", 0));
	if (
		result.attacker_owner == 0
		&& result.attacker_cell >= 0
		&& result.attacker_cell < static_cast<int32_t>(value.board_owners.size())
	) result.attacker_owner = value.board_owners[result.attacker_cell];

	result.attacked_cell = static_cast<int32_t>(context.get("attacked_cell", -1));
	result.attacked_card_index = card_from("attacked_instance_id");
	if (
		result.attacked_card_index < 0
		&& result.attacked_cell >= 0
		&& result.attacked_cell < static_cast<int32_t>(value.board_card_indices.size())
	) result.attacked_card_index = value.board_card_indices[result.attacked_cell];
	result.attacked_owner = static_cast<int32_t>(context.get("attacked_owner_id", 0));
	if (
		result.attacked_owner == 0
		&& result.attacked_cell >= 0
		&& result.attacked_cell < static_cast<int32_t>(value.board_owners.size())
	) result.attacked_owner = value.board_owners[result.attacked_cell];

	result.new_owner = static_cast<int32_t>(context.get("new_owner_id", 0));
	result.previous_ki = static_cast<int32_t>(context.get("previous_ki", 0));
	result.ki = static_cast<int32_t>(context.get("ki", -1));
	result.moving_source_cell = static_cast<int32_t>(context.get("moving_source_cell", -1));
	result.moving_origin_cell = static_cast<int32_t>(context.get("moving_origin_cell", result.moving_source_cell));
	result.moving_target_cell = static_cast<int32_t>(context.get("moving_target_cell", -1));
	result.moving_card_index = card_from("moving_instance_id");
	result.moving_owner = static_cast<int32_t>(context.get("moving_owner_id", 0));
	result.discard_owner = static_cast<int32_t>(context.get("discard_owner_id", 0));
	result.discard_batch_size = static_cast<int32_t>(context.get("discard_batch_size", 0));
	result.turn_owner = static_cast<int32_t>(context.get("turn_owner_id", 0));
	result.activation_owner = static_cast<int32_t>(context.get("activation_owner_id", 0));
	result.activation_source_cell = static_cast<int32_t>(context.get("activation_source_cell", -1));
	result.activation_source_card_index = card_from("activation_source_instance_id");
	if (
		result.activation_source_card_index < 0
		&& result.activation_source_cell >= 0
		&& result.activation_source_cell < static_cast<int32_t>(value.board_card_indices.size())
	) result.activation_source_card_index = value.board_card_indices[result.activation_source_cell];
	result.activation_target_kind = StringName(context.get("activation_target_kind", StringName()));
	result.activation_target_index = static_cast<int32_t>(context.get("activation_target_index", -1));
	result.repeat_attack = bool(context.get("repeat_attack", false));
	result.attack_flipped_enemy = bool(context.get("attack_flipped_enemy", false));
	result.attack_reason = StringName(context.get("attack_reason", StringName()));
	result.flip_reason = StringName(context.get("flip_reason", StringName()));
	result.exile_reason = StringName(context.get("exile_reason", StringName()));
	result.discard_batch_id = StringName(context.get("discard_batch_id", StringName()));

	const Array winning_owners = context.get("winning_owner_ids", Array());
	for (int64_t index = 0; index < winning_owners.size(); ++index) {
		result.winning_owners.push_back(static_cast<int32_t>(winning_owners[index]));
	}
	const Array attack_flips = context.get("attack_flips", Array());
	for (int64_t index = 0; index < attack_flips.size(); ++index) {
		if (attack_flips[index].get_type() != Variant::DICTIONARY) continue;
		const Dictionary record = attack_flips[index];
		EventContext::AttackFlipRecord converted;
		converted.card_index = find_card_by_instance_id(
			value,
			StringName(record.get("instance_id", StringName()))
		);
		converted.previous_owner = static_cast<int32_t>(record.get("previous_owner_id", 0));
		if (converted.card_index >= 0) result.attack_flips.push_back(converted);
	}
	return result;
}

Dictionary DuelNativeCompactKernel::materialize_direct_transition(
	const NativeState &value,
	const Resolution &resolution,
	bool valid,
	const String &reason
) const {
	Dictionary result;
	result["supported"] = resolution.supported;
	result["valid"] = valid && resolution.supported;
	result["reason"] = !reason.is_empty() ? reason : resolution.reason;
	result["captures"] = resolution.captures;
	result["exiles"] = resolution.exiles;
	result["events"] = resolution.events;
	if (valid && resolution.supported) result["payload"] = to_variant_payload(value);
	return result;
}

Dictionary DuelNativeCompactKernel::resolve_event_transition(
	const StringName &event_id,
	const Dictionary &context
) const {
	if (!loaded) {
		Resolution resolution;
		resolution.supported = false;
		return materialize_direct_transition(state, resolution, false, "No compact state is loaded");
	}
	NativeState next = state;
	next.board_slot_extras = state.board_slot_extras.duplicate(true);
	next.side_payload = state.side_payload.duplicate(true);
	std::vector<int32_t> exile_stack;
	const Resolution resolution = resolve_event(
		next,
		event_id,
		event_context_from_dictionary(next, context),
		exile_stack
	);
	return materialize_direct_transition(next, resolution, true);
}

Dictionary DuelNativeCompactKernel::resolve_attack_transition(const Dictionary &request) const {
	if (!loaded) {
		Resolution resolution;
		resolution.supported = false;
		return materialize_direct_transition(state, resolution, false, "No compact state is loaded");
	}
	NativeState next = state;
	next.board_slot_extras = state.board_slot_extras.duplicate(true);
	next.side_payload = state.side_payload.duplicate(true);
	AttackRequest native_request;
	native_request.attacker_cell = static_cast<int32_t>(request.get("source_cell", -1));
	const StringName source_instance_id = StringName(request.get("source_instance_id", StringName()));
	native_request.attacker_card_index = find_card_by_instance_id(
		next,
		source_instance_id
	);
	if (
		source_instance_id.is_empty()
		&&
		native_request.attacker_card_index < 0
		&& native_request.attacker_cell >= 0
		&& native_request.attacker_cell < static_cast<int32_t>(next.board_card_indices.size())
	) native_request.attacker_card_index = next.board_card_indices[native_request.attacker_cell];
	native_request.attacker_owner = static_cast<int32_t>(request.get("source_owner_id", 0));
	native_request.requested_policy = attack_policy_from_dictionary(
		request.get("attack_policy", Dictionary())
	);
	native_request.targeted = StringName(request.get("mode", StringName())) == StringName("targeted");
	native_request.locked_target_cell = static_cast<int32_t>(request.get("target_cell", -1));
	const StringName target_instance_id = StringName(request.get("target_instance_id", StringName()));
	native_request.locked_target_card_index = find_card_by_instance_id(
		next,
		target_instance_id
	);
	if (
		target_instance_id.is_empty()
		&&
		native_request.locked_target_card_index < 0
		&& native_request.locked_target_cell >= 0
		&& native_request.locked_target_cell < static_cast<int32_t>(next.board_card_indices.size())
	) native_request.locked_target_card_index = next.board_card_indices[native_request.locked_target_cell];
	native_request.locked_target_owner = static_cast<int32_t>(request.get("target_owner_id", 0));
	native_request.repeat_attack = bool(request.get("repeat_attack", false));
	native_request.reason = StringName(request.get(
		"reason",
		native_request.targeted
			? StringName("ability_targeted_attack")
			: StringName("ability_standard_attack")
	));
	if (
		native_request.attacker_card_index < 0
		|| native_request.attacker_owner < 1
		|| native_request.attacker_owner > 2
		|| (native_request.targeted && native_request.locked_target_card_index < 0)
	) {
		return materialize_direct_transition(next, Resolution(), true);
	}
	std::vector<int32_t> exile_stack;
	const Resolution resolution = resolve_attack_request(next, native_request, exile_stack);
	return materialize_direct_transition(next, resolution, true);
}

Dictionary DuelNativeCompactKernel::resolve_non_attack_flip_transition(
	const StringName &target_instance_id,
	int64_t new_owner_value,
	const StringName &reason
) const {
	if (!loaded) {
		Resolution resolution;
		resolution.supported = false;
		return materialize_direct_transition(state, resolution, false, "No compact state is loaded");
	}
	NativeState next = state;
	next.board_slot_extras = state.board_slot_extras.duplicate(true);
	next.side_payload = state.side_payload.duplicate(true);
	Resolution resolution;
	const int32_t target_card_index = find_card_by_instance_id(next, target_instance_id);
	const int32_t target_cell = find_board_card(next, target_card_index);
	const int32_t new_owner = static_cast<int32_t>(new_owner_value);
	if (
		target_cell < 0
		|| (new_owner != 1 && new_owner != 2)
		|| next.board_owners[target_cell] == new_owner
	) return materialize_direct_transition(next, resolution, true);

	std::vector<int32_t> exile_stack;
	EventContext flip_context;
	flip_context.trigger_cell = target_cell;
	flip_context.trigger_card_index = target_card_index;
	flip_context.trigger_owner = next.board_owners[target_cell];
	flip_context.trigger_previous_owner = flip_context.trigger_owner;
	flip_context.trigger_zone = 0;
	flip_context.trigger_logical_index = target_cell;
	flip_context.trigger_was_on_board = true;
	flip_context.new_owner = new_owner;
	flip_context.flip_reason = reason;
	Resolution before = resolve_event(
		next,
		StringName("card_before_flipped"),
		flip_context,
		exile_stack
	);
	if (!before.supported) return materialize_direct_transition(next, before, false);
	append_resolution(resolution, before);
	if (before.flip_prevented) {
		Dictionary prevented;
		prevented["type"] = StringName("card_flip_prevented");
		prevented["source_cell"] = -1;
		prevented["target_cell"] = target_cell;
		prevented["owner_id"] = flip_context.trigger_owner;
		prevented["new_owner_id"] = new_owner;
		prevented["instance_id"] = target_instance_id;
		resolution.events.append(prevented);
		Resolution after_prevented = resolve_event(
			next,
			StringName("card_flip_prevented"),
			flip_context,
			exile_stack
		);
		append_resolution(resolution, after_prevented);
		return materialize_direct_transition(next, resolution, true);
	}
	Resolution flipped;
	if (!flip_card(
		next,
		-1,
		-1,
		target_cell,
		target_card_index,
		new_owner,
		flip_context,
		exile_stack,
		flipped
	)) {
		return materialize_direct_transition(next, flipped, false);
	}
	append_resolution(resolution, flipped);
	return materialize_direct_transition(next, resolution, true);
}

bool DuelNativeCompactKernel::transition_activate(
	const NativeState &source,
	const NativeAction &action,
	NativeState &next,
	Resolution &resolution,
	bool &supported,
	String &reason
) const {
	supported = false;
	reason = String();
	if (!validate_play_support(source, reason)) return false;
	supported = true;
	if (source.scalars[5] > 0) {
		reason = "Activation is unavailable during an extra card play";
		return false;
	}
	const int32_t moving_owner = source.scalars[0];
	const int32_t source_cell = action.source_index;
	const int32_t target_index = action.target_index;
	const int32_t requested_activation_index = action.activation_index;
	if (source_cell < 0 || source_cell >= static_cast<int32_t>(source.board_card_indices.size())) {
		reason = "Activation source cell is outside the board";
		return false;
	}
	const int32_t source_card_index = source.board_card_indices[source_cell];
	if (source_card_index < 0 || source.board_owners[source_cell] != moving_owner) {
		reason = "Activation source is not owned by the active player";
		return false;
	}
	if (
		!action.source_instance_id.is_empty()
		&& source.card_instance_ids[source_card_index] != action.source_instance_id
	) {
		reason = "Expected instance ID does not match the activation source";
		return false;
	}
	if (!card_effects_enabled(source, source_card_index, moving_owner)) {
		reason = "Activation source effects are disabled";
		return false;
	}

	const CompiledAbility *ability = nullptr;
	int32_t runtime_ability_index = -1;
	uint64_t ability_handle = 0;
	int32_t current_activation_index = 0;
	for (
		size_t ability_index = 0;
		ability_index < source.card_runtime_abilities[source_card_index].size();
		++ability_index
	) {
		const CompiledAbility *candidate = runtime_ability(
			source,
			source_card_index,
			static_cast<int32_t>(ability_index)
		);
		if (candidate == nullptr || !candidate->has_activation) continue;
		if (current_activation_index == requested_activation_index) {
			ability = candidate;
			runtime_ability_index = static_cast<int32_t>(ability_index);
			ability_handle = source.card_runtime_abilities[source_card_index][ability_index].handle;
			break;
		}
		++current_activation_index;
	}
	if (ability == nullptr || requested_activation_index < 0) {
		reason = "Activation index is no longer available";
		return false;
	}
	if (!ability->activation.declaration_valid) {
		supported = false;
		reason = "Activation declaration is not supported by the native kernel";
		return false;
	}
	const CompiledActivation &activation = ability->activation;
	if (!can_pay_activation_cost(source, source_card_index, activation)) {
		reason = "Activation cost cannot be paid";
		return false;
	}
	const bool expected_hand_slot = activation_targets_hand(activation);
	if (action.target_is_hand_slot != expected_hand_slot) {
		reason = "Activation target kind does not match its declaration";
		return false;
	}
	const std::vector<int32_t> target_indices = get_activation_target_indices(
		source,
		moving_owner,
		source_cell,
		activation
	);
	if (std::find(target_indices.begin(), target_indices.end(), target_index) == target_indices.end()) {
		reason = "Activation target is no longer legal";
		return false;
	}

	int32_t selected_card_index = -1;
	int32_t selected_card_owner = 0;
	if (!action.target_is_hand_slot) {
		selected_card_index = source.board_card_indices[target_index];
		if (selected_card_index >= 0) selected_card_owner = source.board_owners[target_index];
	} else {
		selected_card_owner = activation.target_rule == TargetRuleOpcode::ENEMY_HAND_CARD
			? other_owner(moving_owner)
			: moving_owner;
		selected_card_index = source.zones[selected_card_owner - 1][target_index];
	}

	next = source;
	next.board_slot_extras = source.board_slot_extras.duplicate(true);
	next.side_payload = source.side_payload.duplicate(true);
	resolution = Resolution();
	std::vector<int32_t> exile_stack;
	Dictionary activated;
	activated["type"] = StringName("ability_activated");
	activated["source_cell"] = source_cell;
	activated["target_cell"] = target_index;
	activated["owner_id"] = moving_owner;
	activated["instance_id"] = source.card_instance_ids[source_card_index];
	resolution.events.append(activated);

	EventGroup group;
	group.source_cell = source_cell;
	group.source_zone = 0;
	group.source_logical_index = source_cell;
	group.source_card_index = source_card_index;
	group.source_owner = moving_owner;
	group.ability_index = runtime_ability_index;
	group.ability_handle = ability_handle;
	ActionContext action_context;
	action_context.ability_source_cell = source_cell;
	action_context.ability_source_zone = 0;
	action_context.ability_source_logical_index = source_cell;
	action_context.ability_source_card_index = source_card_index;
	action_context.ability_source_owner = moving_owner;
	action_context.action_subject_card_index = source_card_index;
	action_context.action_subject_owner = moving_owner;
	action_context.action_subject_zone = 0;
	action_context.action_subject_logical_index = source_cell;
	action_context.selected_card_index = selected_card_index;
	action_context.selected_card_owner = selected_card_owner;
	action_context.selected_card_zone = action.target_is_hand_slot ? 1 : 0;
	action_context.selected_card_logical_index = target_index;
	action_context.activation_target_kind = action.target_is_hand_slot
		? StringName("hand_slot")
		: StringName("board_cell");
	action_context.activation_target_index = target_index;
	action_context.record_direct_board_changes = false;
	EventContext activation_context;
	activation_context.ability_source_cell = source_cell;
	activation_context.ability_source_zone = 0;
	activation_context.ability_source_logical_index = source_cell;
	activation_context.ability_source_card_index = source_card_index;
	activation_context.ability_source_owner = moving_owner;
	activation_context.activation_owner = moving_owner;
	activation_context.activation_source_cell = source_cell;
	activation_context.activation_source_card_index = source_card_index;
	activation_context.activation_target_kind = action_context.activation_target_kind;
	activation_context.activation_target_index = target_index;

	const ActionOutcome cost_outcome = execute_actions(
		next,
		group,
		activation.costs,
		activation_context,
		action_context,
		exile_stack,
		resolution
	);
	if (cost_outcome == ActionOutcome::UNSUPPORTED) {
		supported = false;
		reason = resolution.reason.is_empty()
			? String("Activation cost reached unsupported native behavior")
			: resolution.reason;
		return false;
	}
	const ActionOutcome action_outcome = execute_actions(
		next,
		group,
		activation.actions,
		activation_context,
		action_context,
		exile_stack,
		resolution
	);
	if (action_outcome == ActionOutcome::UNSUPPORTED) {
		supported = false;
		reason = resolution.reason.is_empty()
			? String("Activation action reached unsupported native behavior")
			: resolution.reason;
		return false;
	}

	EventContext after_context;
	after_context.activation_owner = moving_owner;
	after_context.activation_source_cell = find_board_card(
		next,
		source_card_index,
		source_cell
	);
	after_context.activation_source_card_index = source_card_index;
	after_context.activation_target_kind = action_context.activation_target_kind;
	after_context.activation_target_index = target_index;
	Resolution after_activation = resolve_event(
		next,
		StringName("card_after_targeted_activation"),
		after_context,
		exile_stack
	);
	if (!after_activation.supported) {
		supported = false;
		reason = after_activation.reason;
		return false;
	}
	append_resolution(resolution, after_activation);

	Resolution finish_resolution = finish_action(
		next,
		moving_owner,
		-1,
		resolution.extra_play_requests,
		exile_stack
	);
	if (!finish_resolution.supported) {
		supported = false;
		reason = finish_resolution.reason;
		return false;
	}
	append_resolution(resolution, finish_resolution);
	return true;
}

bool DuelNativeCompactKernel::transition_action(
	const NativeState &source,
	const NativeAction &action,
	NativeState &next,
	Resolution &resolution,
	bool &supported,
	String &reason,
	bool materialize_presentation_payloads
) const {
	const bool previous_include_presentation_payloads = include_presentation_payloads;
	include_presentation_payloads = materialize_presentation_payloads;
	bool valid = false;
	if (action.type == NativeActionType::PLAY) {
		valid = transition_play(source, action, next, resolution, supported, reason);
	} else {
		valid = transition_activate(source, action, next, resolution, supported, reason);
	}
	include_presentation_payloads = previous_include_presentation_payloads;
	return valid;
}

int32_t DuelNativeCompactKernel::evaluate_baseline(
	const NativeState &value,
	int32_t root_owner
) const {
	static constexpr int32_t win_score = 1'000'000;
	static constexpr int32_t deck_card_weight = 25;
	static constexpr int32_t ki_weight = 4;
	static constexpr int32_t ability_weight = 4;
	static constexpr int32_t danger_weight = 2;
	static constexpr int32_t tempo_weight = 2;
	static constexpr int32_t positional_limit = 499;
	static constexpr int32_t strategic_scale = 1'000;
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
		int32_t result = value.card_ki[card_index] * 4;
		const size_t power_offset = static_cast<size_t>(card_index) * 4;
		for (size_t direction = 0; direction < 4; ++direction) {
			result += value.card_powers[power_offset + direction];
		}
		result += static_cast<int32_t>(
			value.card_runtime_abilities[card_index].size()
		) * 4;
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
	positional_score += zone_value(root_deck_zone, deck_card_weight)
		- zone_value(opponent_deck_zone, deck_card_weight);
	positional_score += static_cast<int32_t>(
		count_legal_native_actions(value, root_owner)
		- count_legal_native_actions(value, opponent_owner)
	);
	positional_score += board_resource_value(root_owner)
		- board_resource_value(opponent_owner);
	positional_score += danger_value(opponent_owner) - danger_value(root_owner);
	positional_score += value.scalars[0] == root_owner ? tempo_weight : -tempo_weight;
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
	const bool collect_diagnostics = limits != nullptr
		&& limits->collect_search_diagnostics;
	stats.nodes += 1;
	stats.max_action_ply = std::max(stats.max_action_ply, action_ply);
	uint64_t state_checksum = 0;
	bool has_state_checksum = false;
	uint64_t transposition_exact_key = 0;
	bool has_transposition_exact_key = false;
	bool has_completed_transposition_hit = false;
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
		if (!has_transposition_exact_key) return;
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
	if (is_terminal(value) || remaining_owner_turn_boundaries <= 0) {
		classify_transposition_probe(true);
		stats.leaves += 1;
		if (remaining_owner_turn_boundaries <= 0 && !is_terminal(value)) {
			stats.horizon_reached = true;
		}
		const auto evaluate_started = collect_diagnostics
			? std::chrono::steady_clock::now()
			: std::chrono::steady_clock::time_point();
		const int32_t score = evaluate_baseline(value, root_owner);
		if (collect_diagnostics) {
			stats.time_evaluate_usec += std::chrono::duration_cast<std::chrono::microseconds>(
				std::chrono::steady_clock::now() - evaluate_started
			).count();
		}
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
	const auto order_started = collect_diagnostics
		? std::chrono::steady_clock::now()
		: std::chrono::steady_clock::time_point();
	const std::vector<NativeAction> actions = order_search_actions(
		value,
		std::move(legal_actions),
		preferred_action,
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
		const int32_t score = evaluate_baseline(value, root_owner);
		if (collect_diagnostics) {
			stats.time_evaluate_usec += std::chrono::duration_cast<std::chrono::microseconds>(
				std::chrono::steady_clock::now() - evaluate_started
			).count();
		}
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
	bool collect_search_diagnostics
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
		collect_search_diagnostics
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
	bool collect_search_diagnostics
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
	result["internal_pv_ordering_enabled"] = use_internal_pv_ordering;
	result["history_ordering_enabled"] = use_history_ordering;
	result["search_diagnostics_enabled"] = collect_search_diagnostics;
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
	NativeSearchLimits limits;
	limits.max_nodes = std::max(max_nodes_value, static_cast<int64_t>(0));
	limits.should_cancel = should_cancel;
	limits.use_internal_pv_ordering = use_internal_pv_ordering;
	limits.use_history_ordering = use_history_ordering;
	limits.collect_search_diagnostics = collect_search_diagnostics;
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
			const auto found = completed_principal_actions.find(search_position_key(
				current,
				remaining_boundaries
			));
			if (found == completed_principal_actions.end()) break;
			current_action = found->second;
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

Dictionary DuelNativeCompactKernel::benchmark_core_clone(int64_t iterations) const {
	Dictionary result;
	if (!loaded || iterations <= 0) {
		result["valid"] = false;
		result["iterations"] = iterations;
		result["elapsed_usec"] = 0;
		result["sink"] = 0;
		return result;
	}

	uint64_t sink = 0;
	const auto started = std::chrono::steady_clock::now();
	for (int64_t iteration = 0; iteration < iterations; ++iteration) {
		NativeState copied = state;
		if (!copied.scalars.empty()) {
			copied.scalars[0] ^= static_cast<int32_t>(iteration & 1);
			sink ^= static_cast<uint64_t>(copied.scalars[0]);
		}
		sink ^= static_cast<uint64_t>(copied.card_powers.size() + copied.card_instance_ids.size());
	}
	const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(
		std::chrono::steady_clock::now() - started
	);
	result["valid"] = true;
	result["iterations"] = iterations;
	result["elapsed_usec"] = static_cast<int64_t>(elapsed.count());
	result["sink"] = static_cast<int64_t>(sink & 0x7fffffffffffffffULL);
	return result;
}

bool DuelNativeCompactKernel::validate_shape() {
	const size_t card_count = state.card_instance_ids.size();
	if (state.scalars.size() != 14) {
		last_error = "Compact scalar count must be 13";
		return false;
	}
	if (state.board_card_indices.size() != state.board_owners.size()) {
		last_error = "Board card and owner arrays differ in size";
		return false;
	}
	if (state.zones.size() != 8) {
		last_error = "Compact zone count must be 8";
		return false;
	}
	if (
		state.card_template_indices.size() != card_count
		|| state.card_runtime_flags.size() != card_count
		|| state.card_powers.size() != card_count * 4
		|| state.card_original_owners.size() != card_count
		|| state.card_ki.size() != card_count
		|| state.card_active_ability_set_indices.size() != card_count
		|| state.card_reveal_codes.size() != card_count
		|| state.card_suppression_set_indices.size() != card_count
		|| state.card_hand_slots.size() != card_count
	) {
		last_error = "Compact card arrays differ in length";
		return false;
	}
	for (const FreshCardPrototype &prototype : state.fresh_card_prototypes) {
		if (prototype.card_id.is_empty()) {
			last_error = "Fresh-card prototype card ID cannot be empty";
			return false;
		}
		if (
			prototype.template_index < 0
			|| prototype.template_index >= state.card_template_pool.size()
		) {
			last_error = "Fresh-card prototype template index is out of range";
			return false;
		}
		if (
			prototype.active_ability_set_index < 0
			|| prototype.active_ability_set_index >= state.active_ability_set_pool.size()
		) {
			last_error = "Fresh-card prototype ability-set index is out of range";
			return false;
		}
	}
	if (
		state.empty_deck_draw_prototype_index < -1
		|| state.empty_deck_draw_prototype_index
			>= static_cast<int32_t>(state.fresh_card_prototypes.size())
	) {
		last_error = "Empty-deck fallback prototype index is out of range";
		return false;
	}
	return true;
}

// Native declarations are compiled once at root load. Runtime cards only retain
// small indices into these immutable structures.
DuelNativeCompactKernel::CompiledCondition DuelNativeCompactKernel::compile_condition(
	const Variant &value
) const {
	CompiledCondition compiled;
	if (value.get_type() != Variant::DICTIONARY) return compiled;
	const Dictionary condition = value;
	const StringName type = condition.get("type", StringName());
	if (
		type == StringName("ki_at_least") && condition.size() == 2
		&& Variant(condition.get("amount", 0)).get_type() == Variant::INT
	) {
		compiled.opcode = ConditionOpcode::KI_AT_LEAST;
		compiled.amount = static_cast<int32_t>(static_cast<int64_t>(condition.get("amount", 0)));
		return compiled;
	}
	if (
		type == StringName("last_discard_batch_size_at_least")
		&& condition.size() == 2
		&& Variant(condition.get("amount", 0)).get_type() == Variant::INT
		&& static_cast<int64_t>(condition.get("amount", 0)) > 0
	) {
		compiled.opcode = ConditionOpcode::LAST_DISCARD_BATCH_SIZE_AT_LEAST;
		compiled.amount = static_cast<int32_t>(static_cast<int64_t>(condition.get("amount", 0)));
		return compiled;
	}
	if (condition.size() != 1) return compiled;
	if (type == StringName("trigger_card_is_self")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_IS_SELF;
	else if (type == StringName("trigger_card_is_ally")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_IS_ALLY;
	else if (type == StringName("trigger_card_is_enemy")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_IS_ENEMY;
	else if (type == StringName("trigger_card_in_range")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_IN_RANGE;
	else if (type == StringName("trigger_card_adjacent_to_source")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_ADJACENT_TO_SOURCE;
	else if (type == StringName("trigger_card_outside_source_owner_hand")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_OUTSIDE_SOURCE_OWNER_HAND;
	else if (type == StringName("trigger_card_revealed_to_self")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_REVEALED_TO_SELF;
	else if (type == StringName("trigger_card_was_enemy")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_WAS_ENEMY;
	else if (type == StringName("trigger_card_original_owner_is_self")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_ORIGINAL_OWNER_IS_SELF;
	else if (type == StringName("attacked_card_is_self")) compiled.opcode = ConditionOpcode::ATTACKED_CARD_IS_SELF;
	else if (type == StringName("attacker_card_is_self")) compiled.opcode = ConditionOpcode::ATTACKER_CARD_IS_SELF;
	else if (type == StringName("attacker_card_is_enemy")) compiled.opcode = ConditionOpcode::ATTACKER_CARD_IS_ENEMY;
	else if (type == StringName("attacker_card_is_other_ally")) compiled.opcode = ConditionOpcode::ATTACKER_CARD_IS_OTHER_ALLY;
	else if (type == StringName("attack_is_not_repeat")) compiled.opcode = ConditionOpcode::ATTACK_IS_NOT_REPEAT;
	else if (type == StringName("activation_owner_is_ally")) compiled.opcode = ConditionOpcode::ACTIVATION_OWNER_IS_ALLY;
	else if (type == StringName("trigger_card_was_on_board")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_WAS_ON_BOARD;
	else if (type == StringName("attack_flipped_enemy")) compiled.opcode = ConditionOpcode::ATTACK_FLIPPED_ENEMY;
	else if (type == StringName("attack_flipped_ally_in_range")) compiled.opcode = ConditionOpcode::ATTACK_FLIPPED_ALLY_IN_RANGE;
	else if (type == StringName("trigger_card_powers_could_change")) compiled.opcode = ConditionOpcode::TRIGGER_CARD_POWERS_COULD_CHANGE;
	else if (type == StringName("drawn_card_is_enemy")) compiled.opcode = ConditionOpcode::DRAWN_CARD_IS_ENEMY;
	else if (type == StringName("turn_owner_is_self")) compiled.opcode = ConditionOpcode::TURN_OWNER_IS_SELF;
	else if (type == StringName("owner_did_not_win")) compiled.opcode = ConditionOpcode::OWNER_DID_NOT_WIN;
	else if (type == StringName("ki_changed_card_is_self")) compiled.opcode = ConditionOpcode::KI_CHANGED_CARD_IS_SELF;
	else if (type == StringName("ki_reached_zero")) compiled.opcode = ConditionOpcode::KI_REACHED_ZERO;
	else if (type == StringName("moving_card_is_self")) compiled.opcode = ConditionOpcode::MOVING_CARD_IS_SELF;
	else if (type == StringName("moving_card_is_ally")) compiled.opcode = ConditionOpcode::MOVING_CARD_IS_ALLY;
	else if (type == StringName("source_owner_hand_empty")) compiled.opcode = ConditionOpcode::SOURCE_OWNER_HAND_EMPTY;
	else if (type == StringName("source_has_adjacent_empty_cell")) compiled.opcode = ConditionOpcode::SOURCE_HAS_ADJACENT_EMPTY_CELL;
	else if (type == StringName("source_has_empty_between_enemy")) compiled.opcode = ConditionOpcode::SOURCE_HAS_EMPTY_BETWEEN_ENEMY;
	else if (type == StringName("discard_owner_is_self")) compiled.opcode = ConditionOpcode::DISCARD_OWNER_IS_SELF;
	return compiled;
}

DuelNativeCompactKernel::CompiledSelectorCondition DuelNativeCompactKernel::compile_selector_condition(
	const Variant &value
) const {
	CompiledSelectorCondition compiled;
	if (value.get_type() != Variant::DICTIONARY) {
		compiled.declaration_valid = false;
		return compiled;
	}
	const Dictionary condition = value;
	const StringName type = condition.get("type", StringName());
	if (condition.size() == 1) {
		if (type == StringName("selected_card_is_ally")) compiled.opcode = SelectorConditionOpcode::IS_ALLY;
		else if (type == StringName("selected_card_is_enemy")) compiled.opcode = SelectorConditionOpcode::IS_ENEMY;
		else if (type == StringName("selected_card_is_not_source")) compiled.opcode = SelectorConditionOpcode::IS_NOT_SOURCE;
		else if (type == StringName("selected_card_adjacent_to_source")) compiled.opcode = SelectorConditionOpcode::ADJACENT_TO_SOURCE;
		else if (type == StringName("selected_card_surrounded_by_allies")) compiled.opcode = SelectorConditionOpcode::SURROUNDED_BY_ALLIES;
		else if (type == StringName("selected_card_original_owner_is_self")) compiled.opcode = SelectorConditionOpcode::ORIGINAL_OWNER_IS_SELF;
		else if (type == StringName("selected_card_original_owner_is_enemy")) compiled.opcode = SelectorConditionOpcode::ORIGINAL_OWNER_IS_ENEMY;
		else if (type == StringName("selected_card_flipped_by_current_attack")) compiled.opcode = SelectorConditionOpcode::FLIPPED_BY_CURRENT_ATTACK;
		else if (type == StringName("selected_card_powers_can_change")) compiled.opcode = SelectorConditionOpcode::POWERS_CAN_CHANGE;
		else if (type == StringName("selected_card_has_nonzero_power")) compiled.opcode = SelectorConditionOpcode::HAS_NONZERO_POWER;
		else if (type == StringName("selected_card_can_spend_ki")) compiled.opcode = SelectorConditionOpcode::CAN_SPEND_KI;
	} else if (
		type == StringName("selected_card_weapon_is")
		&& condition.size() == 2
		&& (
			Variant(condition.get("weapon", Variant())).get_type() == Variant::STRING
			|| Variant(condition.get("weapon", Variant())).get_type() == Variant::STRING_NAME
		)
	) {
		compiled.opcode = SelectorConditionOpcode::WEAPON_IS;
		compiled.weapon = String(condition.get("weapon", String()));
	} else if (
		type == StringName("selected_card_is_previous_hand_play")
		&& condition.size() == 2
	) {
		compiled.opcode = SelectorConditionOpcode::IS_PREVIOUS_HAND_PLAY;
		const StringName owner = condition.get("played_by", StringName());
		if (owner == StringName("ability_source")) compiled.relative_owner = RelativeOwnerOpcode::ABILITY_SOURCE;
		else if (owner == StringName("opponent_of_ability_source")) compiled.relative_owner = RelativeOwnerOpcode::OPPONENT_OF_ABILITY_SOURCE;
	} else if (
		type == StringName("selected_card_can_transfer_resource")
		&& (condition.size() == 3 || condition.size() == 4)
		&& Variant(condition.get("amount", 0)).get_type() == Variant::INT
		&& static_cast<int64_t>(condition.get("amount", 0)) > 0
	) {
		compiled.opcode = SelectorConditionOpcode::CAN_TRANSFER_RESOURCE;
		compiled.amount = static_cast<int32_t>(static_cast<int64_t>(condition.get("amount", 0)));
		auto compile_resource = [](const StringName &resource) {
			if (resource == StringName("ki")) return ResourceOpcode::KI;
			if (resource == StringName("powers")) return ResourceOpcode::POWERS;
			if (resource.is_empty()) return ResourceOpcode::NONE;
			return ResourceOpcode::UNSUPPORTED;
		};
		compiled.resource = compile_resource(condition.get("resource", StringName()));
		compiled.fallback_resource = compile_resource(condition.get("fallback_resource", StringName()));
	}
	if (compiled.opcode == SelectorConditionOpcode::UNSUPPORTED) {
		compiled.declaration_valid = false;
	}
	return compiled;
}

DuelNativeCompactKernel::CompiledSelector DuelNativeCompactKernel::compile_selector(
	const Variant &value
) const {
	CompiledSelector compiled;
	if (value.get_type() != Variant::DICTIONARY) {
		compiled.declaration_valid = false;
		return compiled;
	}
	const Dictionary selector = value;
	const Array keys = selector.keys();
	for (int64_t key_index = 0; key_index < keys.size(); ++key_index) {
		const StringName key = keys[key_index];
		if (
			key != StringName("zones") && key != StringName("conditions")
			&& key != StringName("limit") && key != StringName("required_count")
			&& key != StringName("order")
		) {
			compiled.declaration_valid = false;
		}
	}
	const Variant zones_value = selector.get("zones", Array());
	const Variant conditions_value = selector.get("conditions", Array());
	if (zones_value.get_type() != Variant::ARRAY || conditions_value.get_type() != Variant::ARRAY) {
		compiled.declaration_valid = false;
		return compiled;
	}
	const Array zones = zones_value;
	for (int64_t index = 0; index < zones.size(); ++index) {
		const StringName zone = zones[index];
		if (zone == StringName("hand")) compiled.zones.push_back(SelectorZoneOpcode::HAND);
		else if (zone == StringName("board")) compiled.zones.push_back(SelectorZoneOpcode::BOARD);
		else if (zone == StringName("discard")) compiled.zones.push_back(SelectorZoneOpcode::DISCARD);
		else if (zone == StringName("removed")) compiled.zones.push_back(SelectorZoneOpcode::REMOVED);
		else compiled.declaration_valid = false;
	}
	const Array conditions = conditions_value;
	for (int64_t index = 0; index < conditions.size(); ++index) {
		const CompiledSelectorCondition condition = compile_selector_condition(conditions[index]);
		if (!condition.declaration_valid) compiled.declaration_valid = false;
		compiled.conditions.push_back(condition);
	}
	for (const char *field : {"limit", "required_count"}) {
		const Variant field_value = selector.get(field, 0);
		if (field_value.get_type() != Variant::INT || static_cast<int64_t>(field_value) < 0) {
			compiled.declaration_valid = false;
		}
	}
	compiled.limit = static_cast<int32_t>(static_cast<int64_t>(selector.get("limit", 0)));
	compiled.required_count = static_cast<int32_t>(static_cast<int64_t>(selector.get("required_count", 0)));
	const Variant order_value = selector.get("order", StringName());
	if (order_value.get_type() != Variant::STRING_NAME && order_value.get_type() != Variant::STRING) {
		compiled.declaration_valid = false;
	} else {
		const StringName order = order_value;
		if (order == StringName("hand_right_to_left")) compiled.hand_right_to_left = true;
		else if (!order.is_empty()) compiled.declaration_valid = false;
	}
	return compiled;
}

DuelNativeCompactKernel::CompiledAction DuelNativeCompactKernel::compile_action(
	const Variant &value
) {
	CompiledAction compiled;
	if (value.get_type() != Variant::DICTIONARY) {
		compiled.declaration_valid = false;
		return compiled;
	}
	const Dictionary action = value;
	const StringName type = action.get("type", StringName());
	compiled.declaration_type = type;
	const Variant invalid_policy = action.get("on_invalid_context", Variant());
	if (invalid_policy.get_type() != Variant::NIL) {
		if (invalid_policy.get_type() != Variant::STRING_NAME || StringName(invalid_policy) != StringName("stop_rule")) {
			compiled.declaration_valid = false;
			return compiled;
		}
		compiled.stop_rule_on_invalid_context = true;
	}
	const Variant batch_group = action.get("power_change_batch_group", Variant());
	if (batch_group.get_type() != Variant::NIL) {
		if (batch_group.get_type() != Variant::STRING_NAME && batch_group.get_type() != Variant::STRING) {
			compiled.declaration_valid = false;
			return compiled;
		}
		compiled.power_change_batch_group = StringName(batch_group);
	}

	const int64_t generic_field_count = (
		(action.has("on_invalid_context") ? 1 : 0)
		+ (action.has("power_change_batch_group") ? 1 : 0)
	);
	auto compile_card_ref = [](const StringName &card_ref) {
		if (card_ref == StringName("selected_card")) return CardRefOpcode::SELECTED_CARD;
		if (card_ref == StringName("trigger_card")) return CardRefOpcode::TRIGGER_CARD;
		if (card_ref == StringName("ability_source")) return CardRefOpcode::ABILITY_SOURCE;
		if (card_ref == StringName("attacker_card")) return CardRefOpcode::ATTACKER_CARD;
		if (card_ref == StringName("last_summoned_card")) return CardRefOpcode::LAST_SUMMONED_CARD;
		return CardRefOpcode::UNSUPPORTED;
	};
	auto compile_resource = [](const StringName &resource) {
		if (resource == StringName("ki")) return ResourceOpcode::KI;
		if (resource == StringName("powers")) return ResourceOpcode::POWERS;
		if (resource.is_empty()) return ResourceOpcode::NONE;
		return ResourceOpcode::UNSUPPORTED;
	};
	auto compile_relative_owner = [](const StringName &owner) {
		if (owner == StringName("ability_source")) return RelativeOwnerOpcode::ABILITY_SOURCE;
		if (owner == StringName("opponent_of_ability_source")) return RelativeOwnerOpcode::OPPONENT_OF_ABILITY_SOURCE;
		if (owner == StringName("card_current_owner")) return RelativeOwnerOpcode::CARD_CURRENT;
		if (owner == StringName("card_original_owner")) return RelativeOwnerOpcode::CARD_ORIGINAL;
		return RelativeOwnerOpcode::UNSUPPORTED;
	};
	if (
		type == StringName("draw_cards")
		&& (action.size() == 2 + generic_field_count || action.size() == 3 + generic_field_count)
		&& Variant(action.get("amount", 0)).get_type() == Variant::INT
		&& static_cast<int64_t>(action.get("amount", 0)) > 0
		&& (
			!action.has("weapon")
			|| Variant(action.get("weapon", Variant())).get_type() == Variant::STRING
			|| Variant(action.get("weapon", Variant())).get_type() == Variant::STRING_NAME
		)
	) {
		compiled.opcode = ActionOpcode::DRAW_CARDS;
		compiled.amount = static_cast<int32_t>(static_cast<int64_t>(action.get("amount", 0)));
		compiled.weapon = String(action.get("weapon", String()));
	} else if (type == StringName("discard_card") && action.size() == 2 + generic_field_count) {
		compiled.opcode = ActionOpcode::DISCARD_CARD;
		compiled.card_ref = compile_card_ref(action.get("card", StringName()));
	} else if (
		type == StringName("discard_cards")
		&& action.size() == 2 + generic_field_count
		&& Variant(action.get("selector", Variant())).get_type() == Variant::DICTIONARY
	) {
		compiled.opcode = ActionOpcode::DISCARD_CARDS;
		compiled.selector = compile_selector(action.get("selector", Dictionary()));
		if (!compiled.selector.declaration_valid) compiled.declaration_valid = false;
	} else if (type == StringName("exile_card") && action.size() == 2 + generic_field_count) {
		compiled.opcode = ActionOpcode::EXILE_CARD;
		compiled.card_ref = compile_card_ref(action.get("card", StringName()));
	} else if (type == StringName("exile_self") && action.size() == 1 + generic_field_count) {
		compiled.opcode = ActionOpcode::EXILE_SELF;
	} else if (type == StringName("prevent_trigger_flip") && action.size() == 1 + generic_field_count) {
		compiled.opcode = ActionOpcode::PREVENT_TRIGGER_FLIP;
	} else if (type == StringName("remove_this_ability") && action.size() == 1 + generic_field_count) {
		compiled.opcode = ActionOpcode::REMOVE_THIS_ABILITY;
	} else if (
		type == StringName("for_each_selected_card")
		&& action.size() == 3 + generic_field_count
		&& Variant(action.get("selector", Variant())).get_type() == Variant::DICTIONARY
		&& Variant(action.get("actions", Variant())).get_type() == Variant::ARRAY
	) {
		compiled.opcode = ActionOpcode::FOR_EACH_SELECTED_CARD;
		compiled.selector = compile_selector(action.get("selector", Dictionary()));
		if (!compiled.selector.declaration_valid) compiled.declaration_valid = false;
		const Array children = action.get("actions", Array());
		compiled.child_actions.reserve(static_cast<size_t>(children.size()));
		for (int64_t child_index = 0; child_index < children.size(); ++child_index) {
			const CompiledAction child = compile_action(children[child_index]);
			if (!child.declaration_valid) compiled.declaration_valid = false;
			compiled.child_actions.push_back(child);
		}
	} else if (
		type == StringName("if")
		&& action.size() == 3 + generic_field_count
		&& Variant(action.get("conditions", Variant())).get_type() == Variant::ARRAY
		&& Variant(action.get("actions", Variant())).get_type() == Variant::ARRAY
	) {
		compiled.opcode = ActionOpcode::IF;
		const Array conditions = action.get("conditions", Array());
		const Array children = action.get("actions", Array());
		if (conditions.is_empty() || children.is_empty()) compiled.declaration_valid = false;
		compiled.conditions.reserve(static_cast<size_t>(conditions.size()));
		for (int64_t condition_index = 0; condition_index < conditions.size(); ++condition_index) {
			const CompiledCondition condition = compile_condition(conditions[condition_index]);
			if (condition.opcode == ConditionOpcode::UNSUPPORTED) compiled.declaration_valid = false;
			compiled.conditions.push_back(condition);
		}
		compiled.child_actions.reserve(static_cast<size_t>(children.size()));
		for (int64_t child_index = 0; child_index < children.size(); ++child_index) {
			const CompiledAction child = compile_action(children[child_index]);
			if (!child.declaration_valid) compiled.declaration_valid = false;
			compiled.child_actions.push_back(child);
		}
	} else if (type == StringName("change_powers") && action.size() == 3 + generic_field_count) {
		compiled.opcode = ActionOpcode::CHANGE_POWERS;
		compiled.card_ref = compile_card_ref(action.get("card", StringName()));
		const Variant amount = action.get("amount", Variant());
		if (amount.get_type() == Variant::INT && static_cast<int64_t>(amount) != 0) {
			compiled.amount = static_cast<int32_t>(static_cast<int64_t>(amount));
		} else if (amount.get_type() == Variant::DICTIONARY) {
			const Dictionary spec = amount;
			if (
				spec.size() == 3
				&& StringName(spec.get("type", StringName())) == StringName("card_count")
				&& StringName(spec.get("zone", StringName())) == StringName("hand")
			) {
				compiled.amount_is_hand_count = true;
				const StringName owner = spec.get("owner", StringName());
				if (owner == StringName("ability_source")) compiled.amount_owner = RelativeOwnerOpcode::ABILITY_SOURCE;
				else if (owner == StringName("card_current_owner")) compiled.amount_owner = RelativeOwnerOpcode::CARD_CURRENT;
			}
		}
	} else if (
		(type == StringName("gain_ki") || type == StringName("spend_ki"))
		&& (action.size() == 2 + generic_field_count || action.size() == 3 + generic_field_count)
		&& Variant(action.get("amount", 0)).get_type() == Variant::INT
		&& static_cast<int64_t>(action.get("amount", 0)) > 0
	) {
		compiled.opcode = type == StringName("gain_ki") ? ActionOpcode::GAIN_KI : ActionOpcode::SPEND_KI;
		compiled.amount = static_cast<int32_t>(static_cast<int64_t>(action.get("amount", 0)));
		compiled.card_ref_explicit = action.has("card");
		if (compiled.card_ref_explicit) compiled.card_ref = compile_card_ref(action.get("card", StringName()));
	} else if (type == StringName("flip_self") && action.size() == 2 + generic_field_count) {
		compiled.opcode = ActionOpcode::FLIP_SELF;
		const StringName owner = action.get("new_owner", StringName());
		if (owner == StringName("ability_source")) compiled.new_owner = RelativeOwnerOpcode::ABILITY_SOURCE;
		else if (owner == StringName("opponent_of_ability_source")) compiled.new_owner = RelativeOwnerOpcode::OPPONENT_OF_ABILITY_SOURCE;
	} else if (
		(type == StringName("grant_trigger_card_ability") || type == StringName("grant_ability_to_self"))
		&& action.size() == 2 + generic_field_count
	) {
		compiled.opcode = type == StringName("grant_trigger_card_ability")
			? ActionOpcode::GRANT_TRIGGER_CARD_ABILITY
			: ActionOpcode::GRANT_ABILITY_TO_SELF;
		const Variant granted = action.get("ability", Variant());
		if (granted.get_type() == Variant::DICTIONARY && !Dictionary(granted).is_empty()) {
			compiled.granted_ability_index = intern_compiled_ability(granted);
			if (!compiled_ability_pool[compiled.granted_ability_index].declaration_valid) {
				compiled.declaration_valid = false;
			}
		} else {
			compiled.declaration_valid = false;
		}
	} else if (type == StringName("transform_card") && action.size() == 3 + generic_field_count) {
		compiled.opcode = ActionOpcode::TRANSFORM_CARD;
		compiled.card_ref = compile_card_ref(action.get("card", StringName()));
		const Variant card_id_value = action.get("card_id", Variant());
		if (
			card_id_value.get_type() != Variant::STRING_NAME
			&& card_id_value.get_type() != Variant::STRING
		) {
			compiled.declaration_valid = false;
		} else {
			compiled.card_id = StringName(card_id_value);
			if (compiled.card_id.is_empty()) compiled.declaration_valid = false;
		}
	} else if (
		type == StringName("return_card_to_hand")
		&& (
			action.size() == 3 + generic_field_count
			|| action.size() == 4 + generic_field_count
		)
		&& (
			!action.has("preserve_instance")
			|| Variant(action.get("preserve_instance", false)).get_type() == Variant::BOOL
		)
	) {
		compiled.opcode = ActionOpcode::RETURN_CARD_TO_HAND;
		compiled.card_ref = compile_card_ref(action.get("card", StringName()));
		compiled.preserve_instance = static_cast<bool>(action.get("preserve_instance", false));
		const StringName recipient = action.get("recipient", StringName());
		if (recipient == StringName("card_current_owner")) {
			compiled.recipient_owner = RelativeOwnerOpcode::CARD_CURRENT;
		} else if (recipient == StringName("card_original_owner")) {
			compiled.recipient_owner = RelativeOwnerOpcode::CARD_ORIGINAL;
		} else if (recipient == StringName("ability_source")) {
			compiled.recipient_owner = RelativeOwnerOpcode::ABILITY_SOURCE;
		} else if (recipient == StringName("opponent_of_ability_source")) {
			compiled.recipient_owner = RelativeOwnerOpcode::OPPONENT_OF_ABILITY_SOURCE;
		}
	} else if (
		type == StringName("self_swapped_with_ability_source")
		&& action.size() == 1 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::SELF_SWAPPED_WITH_ABILITY_SOURCE;
	} else if (
		type == StringName("swap_self_with_trigger_card")
		&& action.size() == 1 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::SWAP_SELF_WITH_TRIGGER_CARD;
	} else if (
		type == StringName("attack_trigger_card")
		&& action.size() == 1 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::ATTACK_TRIGGER_CARD;
	} else if (
		type == StringName("standard_attack_with_self")
		&& action.size() >= 1 + generic_field_count
		&& action.size() <= 3 + generic_field_count
		&& (
			!action.has("repeat_attack")
			|| Variant(action.get("repeat_attack", false)).get_type() == Variant::BOOL
		)
		&& (
			!action.has("target_policy")
			|| Variant(action.get("target_policy", Variant())).get_type() == Variant::STRING_NAME
			|| Variant(action.get("target_policy", Variant())).get_type() == Variant::STRING
		)
	) {
		compiled.opcode = ActionOpcode::STANDARD_ATTACK_WITH_SELF;
		const Array keys = action.keys();
		for (int64_t key_index = 0; key_index < keys.size(); ++key_index) {
			const StringName key = keys[key_index];
			if (
				key != StringName("type")
				&& key != StringName("repeat_attack")
				&& key != StringName("target_policy")
				&& key != StringName("on_invalid_context")
				&& key != StringName("power_change_batch_group")
			) compiled.declaration_valid = false;
		}
		compiled.repeat_attack = static_cast<bool>(action.get("repeat_attack", false));
		if (action.has("target_policy")) {
			compiled.target_policy_specified = true;
			const StringName policy = action.get("target_policy", StringName());
			if (policy == StringName("enemies_only")) compiled.target_policy = AttackTargetPolicy::ENEMIES_ONLY;
			else if (policy == StringName("allies_only")) compiled.target_policy = AttackTargetPolicy::ALLIES_ONLY;
			else if (policy == StringName("all")) compiled.target_policy = AttackTargetPolicy::ALL;
			else compiled.declaration_valid = false;
		}
	} else if (
		type == StringName("standard_attack_with_card")
		&& action.size() == 2 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::STANDARD_ATTACK_WITH_CARD;
		compiled.card_ref = compile_card_ref(action.get("card", StringName()));
		if (compiled.card_ref == CardRefOpcode::UNSUPPORTED) {
			compiled.declaration_valid = false;
		}
	} else if (
		type == StringName("move_self_to_target")
		&& action.size() == 1 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::MOVE_SELF_TO_TARGET;
	} else if (
		type == StringName("swap_self_with_target")
		&& action.size() == 1 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::SWAP_SELF_WITH_TARGET;
	} else if (
		type == StringName("move_self_to_first_adjacent_empty")
		&& action.size() == 1 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::MOVE_SELF_TO_FIRST_ADJACENT_EMPTY;
	} else if (
		type == StringName("move_self_to_first_empty_between_enemy")
		&& action.size() == 1 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::MOVE_SELF_TO_FIRST_EMPTY_BETWEEN_ENEMY;
	} else if (
		type == StringName("transfer_card_resource")
		&& action.size() == 6 + generic_field_count
		&& Variant(action.get("amount", 0)).get_type() == Variant::INT
		&& static_cast<int64_t>(action.get("amount", 0)) > 0
	) {
		compiled.opcode = ActionOpcode::TRANSFER_CARD_RESOURCE;
		compiled.from_card_ref = compile_card_ref(action.get("from", StringName()));
		compiled.to_card_ref = compile_card_ref(action.get("to", StringName()));
		compiled.amount = static_cast<int32_t>(static_cast<int64_t>(action.get("amount", 0)));
		compiled.resource = compile_resource(action.get("resource", StringName()));
		compiled.fallback_resource = compile_resource(action.get("fallback_resource", StringName()));
		if (
			compiled.from_card_ref == CardRefOpcode::UNSUPPORTED
			|| compiled.to_card_ref == CardRefOpcode::UNSUPPORTED
			|| compiled.resource == ResourceOpcode::NONE
			|| compiled.resource == ResourceOpcode::UNSUPPORTED
			|| compiled.fallback_resource == ResourceOpcode::NONE
			|| compiled.fallback_resource == ResourceOpcode::UNSUPPORTED
			|| compiled.resource == compiled.fallback_resource
		) compiled.declaration_valid = false;
	} else if (
		type == StringName("distribute_ki")
		&& action.size() == 4 + generic_field_count
		&& Variant(action.get("amount", 0)).get_type() == Variant::INT
		&& static_cast<int64_t>(action.get("amount", 0)) > 0
		&& Variant(action.get("selector", Variant())).get_type() == Variant::DICTIONARY
	) {
		compiled.opcode = ActionOpcode::DISTRIBUTE_KI;
		compiled.from_card_ref = compile_card_ref(action.get("from", StringName()));
		compiled.amount = static_cast<int32_t>(static_cast<int64_t>(action.get("amount", 0)));
		compiled.selector = compile_selector(action.get("selector", Dictionary()));
		if (
			compiled.from_card_ref == CardRefOpcode::UNSUPPORTED
			|| !compiled.selector.declaration_valid
		) compiled.declaration_valid = false;
	} else if (
		type == StringName("add_card_to_hand")
		&& action.size() == 3 + generic_field_count
		&& (action.has("card_id") != action.has("card"))
	) {
		compiled.opcode = ActionOpcode::ADD_CARD_TO_HAND;
		const StringName recipient = action.get("recipient", StringName());
		if (recipient == StringName("self")) compiled.recipient = RecipientOpcode::SELF;
		else if (recipient == StringName("opponent")) compiled.recipient = RecipientOpcode::OPPONENT;
		else compiled.declaration_valid = false;
		if (action.has("card_id")) {
			const Variant card_id_value = action.get("card_id", Variant());
			if (
				card_id_value.get_type() != Variant::STRING_NAME
				&& card_id_value.get_type() != Variant::STRING
			) {
				compiled.declaration_valid = false;
			} else {
				compiled.card_id = StringName(card_id_value);
				compiled.card_spec = CardSpecOpcode::FRESH_COPY;
			}
		} else {
			const Variant card_value = action.get("card", Variant());
			if (card_value.get_type() != Variant::DICTIONARY) {
				compiled.declaration_valid = false;
			} else {
				const Dictionary card_spec = card_value;
				const StringName card_spec_type = card_spec.get("type", StringName());
				if (
					(card_spec_type == StringName("fresh_copy") || card_spec_type == StringName("perfect_copy"))
					&& card_spec.size() == 2
				) {
					compiled.card_spec = card_spec_type == StringName("fresh_copy")
						? CardSpecOpcode::FRESH_COPY
						: CardSpecOpcode::PERFECT_COPY;
					compiled.summon_card_ref = compile_card_ref(card_spec.get("of", StringName()));
					if (compiled.summon_card_ref == CardRefOpcode::UNSUPPORTED) {
						compiled.declaration_valid = false;
					}
				} else {
					compiled.declaration_valid = false;
				}
			}
		}
	} else if (
		type == StringName("reveal_hand_cards")
		&& action.size() == 3 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::REVEAL_HAND_CARDS;
		const StringName recipient = action.get("recipient", StringName());
		if (recipient == StringName("self")) compiled.recipient = RecipientOpcode::SELF;
		else if (recipient == StringName("opponent")) compiled.recipient = RecipientOpcode::OPPONENT;
		const StringName filter = action.get("filter", StringName());
		if (filter == StringName("all")) compiled.reveal_filter = RevealFilterOpcode::ALL;
		else if (filter == StringName("remembered")) compiled.reveal_filter = RevealFilterOpcode::REMEMBERED;
		if (
			compiled.recipient == RecipientOpcode::UNSUPPORTED
			|| compiled.reveal_filter == RevealFilterOpcode::UNSUPPORTED
		) compiled.declaration_valid = false;
	} else if (
		type == StringName("reveal_card")
		&& action.size() == 3 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::REVEAL_CARD;
		compiled.card_ref = compile_card_ref(action.get("card", StringName()));
		compiled.recipient_owner = compile_relative_owner(
			action.get("observer", StringName())
		);
		if (
			compiled.card_ref == CardRefOpcode::UNSUPPORTED
			|| compiled.recipient_owner == RelativeOwnerOpcode::UNSUPPORTED
		) compiled.declaration_valid = false;
	} else if (
		type == StringName("grant_extra_card_play")
		&& (action.size() == 2 + generic_field_count || action.size() == 3 + generic_field_count)
		&& Variant(action.get("amount", 0)).get_type() == Variant::INT
		&& static_cast<int64_t>(action.get("amount", 0)) > 0
	) {
		compiled.opcode = ActionOpcode::GRANT_EXTRA_CARD_PLAY;
		compiled.amount = static_cast<int32_t>(static_cast<int64_t>(action.get("amount", 0)));
		compiled.card_ref_explicit = action.has("card");
		if (compiled.card_ref_explicit) {
			compiled.card_ref = compile_card_ref(action.get("card", StringName()));
			if (compiled.card_ref == CardRefOpcode::UNSUPPORTED) compiled.declaration_valid = false;
		}
	} else if (
		type == StringName("add_pending_non_retained_suppression")
		&& action.size() == 3 + generic_field_count
		&& Variant(action.get("amount", 0)).get_type() == Variant::INT
		&& static_cast<int64_t>(action.get("amount", 0)) > 0
	) {
		compiled.opcode = ActionOpcode::ADD_PENDING_NON_RETAINED_SUPPRESSION;
		compiled.amount = static_cast<int32_t>(static_cast<int64_t>(action.get("amount", 0)));
		const StringName recipient = action.get("recipient", StringName());
		if (recipient == StringName("self")) compiled.recipient = RecipientOpcode::SELF;
		else if (recipient == StringName("opponent")) compiled.recipient = RecipientOpcode::OPPONENT;
		else compiled.declaration_valid = false;
	} else if (
		type == StringName("temporarily_remove_non_retained_abilities")
		&& action.size() == 1 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES;
	} else if (
		type == StringName("enable_future_draw_reveal")
		&& action.size() == 2 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::ENABLE_FUTURE_DRAW_REVEAL;
		const StringName recipient = action.get("recipient", StringName());
		if (recipient == StringName("self")) compiled.recipient = RecipientOpcode::SELF;
		else if (recipient == StringName("opponent")) compiled.recipient = RecipientOpcode::OPPONENT;
		else compiled.declaration_valid = false;
	} else if (
		type == StringName("summon_card")
		&& action.size() == 3 + generic_field_count
		&& Variant(action.get("cell", Variant())).get_type() == Variant::DICTIONARY
	) {
		compiled.opcode = ActionOpcode::SUMMON_CARD;
		const Variant card_value = action.get("card", Variant());
		if (card_value.get_type() == Variant::STRING_NAME || card_value.get_type() == Variant::STRING) {
			compiled.card_spec = CardSpecOpcode::EXISTING_REFERENCE;
			compiled.summon_card_ref = compile_card_ref(StringName(card_value));
			if (compiled.summon_card_ref == CardRefOpcode::UNSUPPORTED) compiled.declaration_valid = false;
		} else if (card_value.get_type() == Variant::DICTIONARY) {
			const Dictionary card_spec = card_value;
			const StringName card_spec_type = card_spec.get("type", StringName());
			if (
				(card_spec_type == StringName("fresh_copy") || card_spec_type == StringName("perfect_copy"))
				&& card_spec.size() == 2
			) {
				compiled.card_spec = card_spec_type == StringName("fresh_copy")
					? CardSpecOpcode::FRESH_COPY
					: CardSpecOpcode::PERFECT_COPY;
				compiled.summon_card_ref = compile_card_ref(card_spec.get("of", StringName()));
				if (compiled.summon_card_ref == CardRefOpcode::UNSUPPORTED) compiled.declaration_valid = false;
			} else if (card_spec_type == StringName("top_discard") && card_spec.size() == 2) {
				compiled.card_spec = CardSpecOpcode::TOP_DISCARD;
				compiled.summon_owner = compile_relative_owner(card_spec.get("owner", StringName()));
				if (compiled.summon_owner == RelativeOwnerOpcode::UNSUPPORTED) compiled.declaration_valid = false;
			} else {
				compiled.declaration_valid = false;
			}
		} else {
			compiled.declaration_valid = false;
		}

		const Dictionary cell_spec = action.get("cell", Dictionary());
		const StringName cell_type = cell_spec.get("type", StringName());
		if (cell_type == StringName("initial_card_cell") && cell_spec.size() == 2) {
			compiled.cell_spec = CellSpecOpcode::INITIAL_CARD_CELL;
			compiled.summon_cell_card_ref = compile_card_ref(cell_spec.get("card", StringName()));
		} else if (cell_type == StringName("activation_target") && cell_spec.size() == 1) {
			compiled.cell_spec = CellSpecOpcode::ACTIVATION_TARGET;
		} else if (cell_type == StringName("first_adjacent_empty") && cell_spec.size() == 2) {
			compiled.cell_spec = CellSpecOpcode::FIRST_ADJACENT_EMPTY;
			compiled.summon_cell_card_ref = compile_card_ref(cell_spec.get("card", StringName()));
		} else if (cell_type == StringName("first_adjacent_or_any_empty") && cell_spec.size() == 2) {
			compiled.cell_spec = CellSpecOpcode::FIRST_ADJACENT_OR_ANY_EMPTY;
			compiled.summon_cell_card_ref = compile_card_ref(cell_spec.get("card", StringName()));
		} else if (cell_type == StringName("first_empty_adjacent_to_enemy") && cell_spec.size() == 2) {
			compiled.cell_spec = CellSpecOpcode::FIRST_EMPTY_ADJACENT_TO_ENEMY;
			compiled.summon_owner = compile_relative_owner(cell_spec.get("owner", StringName()));
		} else {
			compiled.declaration_valid = false;
		}
		if (
			(compiled.cell_spec == CellSpecOpcode::INITIAL_CARD_CELL
				|| compiled.cell_spec == CellSpecOpcode::FIRST_ADJACENT_EMPTY
				|| compiled.cell_spec == CellSpecOpcode::FIRST_ADJACENT_OR_ANY_EMPTY)
			&& compiled.summon_cell_card_ref == CardRefOpcode::UNSUPPORTED
		) compiled.declaration_valid = false;
		if (
			compiled.cell_spec == CellSpecOpcode::FIRST_EMPTY_ADJACENT_TO_ENEMY
			&& compiled.summon_owner == RelativeOwnerOpcode::UNSUPPORTED
		) compiled.declaration_valid = false;
	} else if (
		type == StringName("resummon_card_in_place")
		&& action.size() == 2 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::RESUMMON_CARD_IN_PLACE;
		compiled.card_ref = compile_card_ref(action.get("card", StringName()));
		if (compiled.card_ref == CardRefOpcode::UNSUPPORTED) compiled.declaration_valid = false;
	} else if (
		type == StringName("depart_card_for_resummon")
		&& action.size() == 2 + generic_field_count
	) {
		compiled.opcode = ActionOpcode::DEPART_CARD_FOR_RESUMMON;
		compiled.card_ref = compile_card_ref(action.get("card", StringName()));
		if (compiled.card_ref == CardRefOpcode::UNSUPPORTED) compiled.declaration_valid = false;
	}
	if (compiled.opcode == ActionOpcode::UNSUPPORTED) compiled.declaration_valid = false;
	return compiled;
}

DuelNativeCompactKernel::CompiledModifier DuelNativeCompactKernel::compile_modifier(
	const Variant &value
) const {
	CompiledModifier compiled;
	if (value.get_type() != Variant::DICTIONARY) return compiled;
	const Dictionary modifier = value;
	const StringName type = modifier.get("type", StringName());
	if (
		type == StringName("defending_power_override")
		&& modifier.size() == 2
		&& Variant(modifier.get("value", 0)).get_type() == Variant::INT
	) {
		compiled.opcode = ModifierOpcode::DEFENDING_POWER_OVERRIDE;
		compiled.value = static_cast<int32_t>(static_cast<int64_t>(modifier.get("value", 0)));
	} else if (
		type == StringName("orthogonal_attack_range_two")
		&& (modifier.size() == 2 || modifier.size() == 3)
		&& Variant(modifier.get("allow_intervening_ally", false)).get_type() == Variant::BOOL
		&& (
			!modifier.has("allow_intervening_enemy")
			|| Variant(modifier.get("allow_intervening_enemy", false)).get_type() == Variant::BOOL
		)
	) {
		compiled.opcode = ModifierOpcode::ORTHOGONAL_ATTACK_RANGE_TWO;
		compiled.value = (
			(static_cast<bool>(modifier.get("allow_intervening_ally", false)) ? 1 : 0)
			| (static_cast<bool>(modifier.get("allow_intervening_enemy", false)) ? 2 : 0)
		);
	} else if (type == StringName("enemy_attacks_all") && modifier.size() == 1) {
		compiled.opcode = ModifierOpcode::ENEMY_ATTACKS_ALL;
	} else if (modifier.size() == 1) {
		if (type == StringName("attack_requires_other_ally")) compiled.opcode = ModifierOpcode::ATTACK_REQUIRES_OTHER_ALLY;
		else if (type == StringName("defending_power_uses_minimum_side")) compiled.opcode = ModifierOpcode::DEFENDING_POWER_USES_MINIMUM_SIDE;
		else if (type == StringName("power_comparison_reversed")) compiled.opcode = ModifierOpcode::POWER_COMPARISON_REVERSED;
		else if (type == StringName("adjacent_enemy_summon_attacks_allies")) compiled.opcode = ModifierOpcode::ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES;
		else if (type == StringName("unlimited_attack_range")) compiled.opcode = ModifierOpcode::UNLIMITED_ATTACK_RANGE;
		else if (type == StringName("non_orthogonal_attack_any_axis")) compiled.opcode = ModifierOpcode::NON_ORTHOGONAL_ATTACK_ANY_AXIS;
		else if (type == StringName("standard_attack_first_legal_target")) compiled.opcode = ModifierOpcode::STANDARD_ATTACK_FIRST_LEGAL_TARGET;
		else if (type == StringName("enemy_cannot_attack_during_owner_turn")) compiled.opcode = ModifierOpcode::ENEMY_CANNOT_ATTACK_DURING_OWNER_TURN;
		else if (type == StringName("self_attacks_all")) compiled.opcode = ModifierOpcode::SELF_ATTACKS_ALL;
	}
	return compiled;
}

DuelNativeCompactKernel::CompiledTriggerRule DuelNativeCompactKernel::compile_trigger_rule(
	const Variant &value,
	bool &valid
) {
	CompiledTriggerRule compiled;
	if (value.get_type() != Variant::DICTIONARY) {
		valid = false;
		return compiled;
	}
	const Dictionary rule = value;
	compiled.event_id = rule.get("event", StringName());
	const Variant conditions_value = rule.get("conditions", Array());
	const Variant actions_value = rule.get("actions", Array());
	if (conditions_value.get_type() != Variant::ARRAY || actions_value.get_type() != Variant::ARRAY) {
		valid = false;
		return compiled;
	}
	const Array conditions = conditions_value;
	for (int64_t index = 0; index < conditions.size(); ++index) {
		const CompiledCondition condition = compile_condition(conditions[index]);
		if (condition.opcode == ConditionOpcode::UNSUPPORTED) valid = false;
		compiled.conditions.push_back(condition);
	}
	const Array actions = actions_value;
	for (int64_t index = 0; index < actions.size(); ++index) {
		const CompiledAction action = compile_action(actions[index]);
		if (!action.declaration_valid) valid = false;
		compiled.actions.push_back(action);
	}
	return compiled;
}

DuelNativeCompactKernel::CompiledActivation DuelNativeCompactKernel::compile_activation(
	const Variant &value
) {
	CompiledActivation compiled;
	if (value.get_type() != Variant::DICTIONARY) {
		compiled.declaration_valid = false;
		return compiled;
	}
	const Dictionary activation = value;
	if (activation.size() != 4) compiled.declaration_valid = false;
	const Array keys = activation.keys();
	for (int64_t index = 0; index < keys.size(); ++index) {
		const StringName key = keys[index];
		if (
			key != StringName("input")
			&& key != StringName("target_rule")
			&& key != StringName("costs")
			&& key != StringName("actions")
		) {
			compiled.declaration_valid = false;
		}
	}
	if (StringName(activation.get("input", StringName())) != StringName("drag_to_target")) {
		compiled.declaration_valid = false;
	}
	const StringName target_rule = activation.get("target_rule", StringName());
	if (target_rule == StringName("adjacent_empty_board")) {
		compiled.target_rule = TargetRuleOpcode::ADJACENT_EMPTY_BOARD;
	} else if (target_rule == StringName("adjacent_ally_board")) {
		compiled.target_rule = TargetRuleOpcode::ADJACENT_ALLY_BOARD;
	} else if (target_rule == StringName("adjacent_enemy_board")) {
		compiled.target_rule = TargetRuleOpcode::ADJACENT_ENEMY_BOARD;
	} else if (target_rule == StringName("other_ally_board")) {
		compiled.target_rule = TargetRuleOpcode::OTHER_ALLY_BOARD;
	} else if (target_rule == StringName("enemy_hand_card")) {
		compiled.target_rule = TargetRuleOpcode::ENEMY_HAND_CARD;
	} else if (target_rule == StringName("ally_hand_card")) {
		compiled.target_rule = TargetRuleOpcode::ALLY_HAND_CARD;
	} else if (target_rule == StringName("any_empty_board")) {
		compiled.target_rule = TargetRuleOpcode::ANY_EMPTY_BOARD;
	} else if (target_rule == StringName("any_enemy_board")) {
		compiled.target_rule = TargetRuleOpcode::ANY_ENEMY_BOARD;
	} else {
		compiled.declaration_valid = false;
	}

	const Variant costs_value = activation.get("costs", Variant());
	const Variant actions_value = activation.get("actions", Variant());
	if (costs_value.get_type() != Variant::ARRAY || actions_value.get_type() != Variant::ARRAY) {
		compiled.declaration_valid = false;
		return compiled;
	}
	const Array costs = costs_value;
	const Array actions = actions_value;
	if (costs.is_empty() || actions.is_empty()) compiled.declaration_valid = false;
	compiled.costs.reserve(static_cast<size_t>(costs.size()));
	for (int64_t index = 0; index < costs.size(); ++index) {
		const CompiledAction cost = compile_action(costs[index]);
		if (
			!cost.declaration_valid
			|| cost.opcode != ActionOpcode::SPEND_KI
			|| cost.amount <= 0
			|| cost.card_ref_explicit
		) {
			compiled.declaration_valid = false;
		} else {
			compiled.required_ki += cost.amount;
		}
		compiled.costs.push_back(cost);
	}
	compiled.actions.reserve(static_cast<size_t>(actions.size()));
	for (int64_t index = 0; index < actions.size(); ++index) {
		const CompiledAction action = compile_action(actions[index]);
		if (!action.declaration_valid) compiled.declaration_valid = false;
		compiled.actions.push_back(action);
	}
	return compiled;
}

DuelNativeCompactKernel::CompiledAbility DuelNativeCompactKernel::compile_ability(
	const Variant &value
) {
	CompiledAbility compiled;
	if (value.get_type() != Variant::DICTIONARY) {
		compiled.declaration_valid = false;
		return compiled;
	}
	const Dictionary ability = value;
	compiled.retained_on_flip = static_cast<bool>(ability.get("retained_on_flip", false));
	if (ability.has("activation")) {
		const Variant activation = ability["activation"];
		compiled.has_activation = (
			activation.get_type() == Variant::DICTIONARY
			&& !Dictionary(activation).is_empty()
		);
		compiled.activation = compile_activation(activation);
		if (!compiled.activation.declaration_valid) compiled.declaration_valid = false;
	}
	if (ability.has("modifiers")) {
		const Variant modifiers_value = ability["modifiers"];
		if (modifiers_value.get_type() != Variant::ARRAY) {
			compiled.declaration_valid = false;
		} else {
			const Array modifiers = modifiers_value;
			for (int64_t index = 0; index < modifiers.size(); ++index) {
				const CompiledModifier modifier = compile_modifier(modifiers[index]);
				if (modifier.opcode == ModifierOpcode::UNSUPPORTED) {
					compiled.declaration_valid = false;
				}
				compiled.modifiers.push_back(modifier);
			}
		}
	}
	const Variant triggers_value = ability.get("triggers", Array());
	if (triggers_value.get_type() != Variant::ARRAY) {
		compiled.declaration_valid = false;
		return compiled;
	}
	const Array triggers = triggers_value;
	for (int64_t index = 0; index < triggers.size(); ++index) {
		compiled.triggers.push_back(compile_trigger_rule(triggers[index], compiled.declaration_valid));
	}
	compiled.isolated_self_after_flip = (
		!compiled.has_activation
		&& compiled.modifiers.empty()
		&& compiled.triggers.size() == 1
		&& compiled.triggers[0].event_id == StringName("card_after_flipped")
	);
	if (compiled.isolated_self_after_flip) {
		bool has_self_condition = false;
		for (const CompiledCondition &condition : compiled.triggers[0].conditions) {
			has_self_condition = has_self_condition || condition.opcode == ConditionOpcode::TRIGGER_CARD_IS_SELF;
		}
		compiled.isolated_self_after_flip = has_self_condition;
	}
	return compiled;
}

int32_t DuelNativeCompactKernel::intern_compiled_ability(const Variant &value) {
	for (size_t index = 0; index < ability_declaration_pool.size(); ++index) {
		if (ability_declaration_pool[index] == value) return static_cast<int32_t>(index);
	}
	const int32_t index = static_cast<int32_t>(compiled_ability_pool.size());
	ability_declaration_pool.push_back(value);
	compiled_ability_pool.push_back(CompiledAbility());
	compiled_ability_pool[index] = compile_ability(value);
	return index;
}

void DuelNativeCompactKernel::compile_ability_sets() {
	compiled_ability_sets.clear();
	compiled_ability_pool.clear();
	ability_declaration_pool.clear();
	compiled_ability_sets.reserve(static_cast<size_t>(state.active_ability_set_pool.size()));
	for (int64_t set_index = 0; set_index < state.active_ability_set_pool.size(); ++set_index) {
		CompiledAbilitySet compiled;
		const Variant set_value = state.active_ability_set_pool[set_index];
		if (set_value.get_type() != Variant::ARRAY) {
			compiled.declaration_valid = false;
			compiled_ability_sets.push_back(compiled);
			continue;
		}
		const Array abilities = set_value;
		for (int64_t ability_index = 0; ability_index < abilities.size(); ++ability_index) {
			const int32_t pool_index = intern_compiled_ability(abilities[ability_index]);
			compiled.ability_pool_indices.push_back(pool_index);
			if (!compiled_ability_pool[pool_index].declaration_valid) compiled.declaration_valid = false;
		}
		compiled_ability_sets.push_back(compiled);
	}
}

bool DuelNativeCompactKernel::compile_runtime_suppression_batches() {
	state.card_runtime_suppression_batches.clear();
	state.card_runtime_suppression_batches.resize(state.card_instance_ids.size());
	for (size_t card_index = 0; card_index < state.card_instance_ids.size(); ++card_index) {
		if ((state.card_runtime_flags[card_index] & (1 << 6)) == 0) continue;
		const int32_t set_index = state.card_suppression_set_indices[card_index];
		if (
			set_index < 0
			|| set_index >= state.suppression_set_pool.size()
			|| Variant(state.suppression_set_pool[set_index]).get_type() != Variant::ARRAY
		) {
			last_error = "Temporary suppression set reference is invalid";
			return false;
		}
		const Array batches = state.suppression_set_pool[set_index];
		std::vector<RuntimeSuppressionBatch> compiled_batches;
		compiled_batches.reserve(static_cast<size_t>(batches.size()));
		for (int64_t batch_index = 0; batch_index < batches.size(); ++batch_index) {
			const Variant batch_value = batches[batch_index];
			if (batch_value.get_type() != Variant::DICTIONARY) {
				last_error = "Temporary suppression batch is not a Dictionary";
				return false;
			}
			const Dictionary batch = batch_value;
			const Variant expires_value = batch.get("expires_after_turn", Variant());
			const Variant entries_value = batch.get("entries", Variant());
			if (
				batch.size() != 2
				|| expires_value.get_type() != Variant::INT
				|| entries_value.get_type() != Variant::ARRAY
			) {
				last_error = "Temporary suppression batch has an invalid declaration shape";
				return false;
			}
			RuntimeSuppressionBatch compiled_batch;
			compiled_batch.expires_after_turn = static_cast<int32_t>(
				static_cast<int64_t>(expires_value)
			);
			const Array entries = entries_value;
			compiled_batch.entries.reserve(static_cast<size_t>(entries.size()));
			for (int64_t entry_index = 0; entry_index < entries.size(); ++entry_index) {
				const Variant entry_value = entries[entry_index];
				if (entry_value.get_type() != Variant::DICTIONARY) {
					last_error = "Temporary suppression entry is not a Dictionary";
					return false;
				}
				const Dictionary entry = entry_value;
				const Variant index_value = entry.get("index", Variant());
				const Variant ability_value = entry.get("ability", Variant());
				if (
					entry.size() != 2
					|| index_value.get_type() != Variant::INT
					|| static_cast<int64_t>(index_value) < 0
					|| ability_value.get_type() != Variant::DICTIONARY
				) {
					last_error = "Temporary suppression entry has an invalid declaration shape";
					return false;
				}
				RuntimeSuppressionEntry compiled_entry;
				compiled_entry.original_index = static_cast<int32_t>(
					static_cast<int64_t>(index_value)
				);
				compiled_entry.compiled_ability_index = intern_compiled_ability(ability_value);
				compiled_entry.handle = state.next_ability_handle++;
				compiled_batch.entries.push_back(compiled_entry);
			}
			compiled_batches.push_back(compiled_batch);
		}
		state.card_runtime_suppression_batches[card_index] = compiled_batches;
	}
	return true;
}

bool DuelNativeCompactKernel::validate_play_support(
	const NativeState &value,
	String &reason
) const {
	if (!value.has_rule_metadata) {
		reason = "Play transition requires immutable compact metadata pools";
		return false;
	}
	if (value.board_card_indices.size() != 9 || value.board_slot_extras.size() != 9) {
		reason = "Play transition requires the canonical nine-cell board";
		return false;
	}
	const Array state_abilities = value.side_payload.get("active_abilities", Array());
	const Array effect_queue = value.side_payload.get("effect_queue", Array());
	const Dictionary pending_choice = value.side_payload.get("pending_choice", Dictionary());
	if (!state_abilities.is_empty() || !effect_queue.is_empty() || !pending_choice.is_empty()) {
		reason = "Play transition requires no state abilities, queued effects, or pending choice";
		return false;
	}
	if (value.card_ids.size() != value.card_instance_ids.size()) {
		reason = "Play transition is missing card IDs";
		return false;
	}
	for (size_t card_index = 0; card_index < value.card_instance_ids.size(); ++card_index) {
		static constexpr uint8_t required_flags = (
			(1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5)
		);
		if ((value.card_runtime_flags[card_index] & required_flags) != required_flags) {
			reason = "Play transition requires normalized runtime cards";
			return false;
		}
		if (value.card_ids[card_index].is_empty()) {
			reason = "Play transition requires every card to have a card ID";
			return false;
		}
		if (!powers_supported(value, static_cast<int32_t>(card_index))) {
			reason = "Play transition does not cover mixed negative powers";
			return false;
		}
		const int32_t ability_set_index = value.card_active_ability_set_indices[card_index];
		if (
			ability_set_index < 0
			|| ability_set_index >= value.active_ability_set_pool.size()
			|| Variant(value.active_ability_set_pool[ability_set_index]).get_type() != Variant::ARRAY
			|| ability_set_index >= static_cast<int32_t>(compiled_ability_sets.size())
		) {
			reason = "Play transition has an invalid runtime ability-set reference";
			return false;
		}
	}
	return true;
}

bool DuelNativeCompactKernel::validate_action_rule_support(
	const NativeState &value,
	int32_t played_card_index,
	int32_t,
	String &reason
) const {
	const int32_t moving_owner = value.scalars[0];
	const bool source_enabled = card_effects_enabled(value, played_card_index, moving_owner);
	if (source_enabled && card_has_unsupported_enabled_modifier(value, played_card_index, moving_owner)) {
		reason = "Played card has an unsupported modifier";
		return false;
	}
	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		const int32_t card_index = value.board_card_indices[cell];
		if (card_index < 0) {
			continue;
		}
		const int32_t owner_id = value.board_owners[cell];
		if (card_has_unsupported_enabled_modifier(value, card_index, owner_id)) {
			reason = "Board contains an unsupported active modifier";
			return false;
		}
	}
	return true;
}

bool DuelNativeCompactKernel::card_effects_enabled(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id
) const {
	if (card_index < 0 || card_index >= static_cast<int32_t>(value.card_template_indices.size())) {
		return false;
	}
	const int32_t template_index = value.card_template_indices[card_index];
	if (template_index < 0 || template_index >= value.card_template_pool.size()) {
		return false;
	}
	const Dictionary card_template = value.card_template_pool[template_index];
	const StringName gate = card_template.get("effect_gate", StringName());
	if (gate.is_empty()) {
		return true;
	}
	const Dictionary gates_by_owner = value.side_payload.get(
		"enabled_effect_gates_by_owner",
		Dictionary()
	);
	const Variant gates_value = gates_by_owner.get(owner_id, Array());
	if (gates_value.get_type() != Variant::ARRAY) {
		return false;
	}
	const Array gates = gates_value;
	for (int64_t index = 0; index < gates.size(); ++index) {
		if (StringName(gates[index]) == gate) {
			return true;
		}
	}
	return false;
}

bool DuelNativeCompactKernel::card_has_abilities(
	const NativeState &value,
	int32_t card_index
) const {
	return (
		card_index >= 0
		&& card_index < static_cast<int32_t>(value.card_runtime_abilities.size())
		&& !value.card_runtime_abilities[card_index].empty()
	);
}

bool DuelNativeCompactKernel::ability_enabled(
	const NativeState &value,
	int32_t card_index,
	int32_t ability_index
) const {
	return runtime_ability(value, card_index, ability_index) != nullptr;
}

const DuelNativeCompactKernel::CompiledAbility *DuelNativeCompactKernel::runtime_ability(
	const NativeState &value,
	int32_t card_index,
	int32_t ability_index
) const {
	if (
		card_index < 0
		|| card_index >= static_cast<int32_t>(value.card_runtime_abilities.size())
		|| ability_index < 0
		|| ability_index >= static_cast<int32_t>(value.card_runtime_abilities[card_index].size())
	) {
		return nullptr;
	}
	const int32_t compiled_index = value.card_runtime_abilities[card_index][ability_index].compiled_ability_index;
	if (compiled_index < 0 || compiled_index >= static_cast<int32_t>(compiled_ability_pool.size())) {
		return nullptr;
	}
	return &compiled_ability_pool[compiled_index];
}

int32_t DuelNativeCompactKernel::find_runtime_ability_index(
	const NativeState &value,
	int32_t card_index,
	uint64_t ability_handle,
	int32_t preferred_index
) const {
	if (
		card_index < 0
		|| card_index >= static_cast<int32_t>(value.card_runtime_abilities.size())
		|| ability_handle == 0
	) {
		return -1;
	}
	const std::vector<RuntimeAbilityEntry> &entries = value.card_runtime_abilities[card_index];
	if (
		preferred_index >= 0
		&& preferred_index < static_cast<int32_t>(entries.size())
		&& entries[preferred_index].handle == ability_handle
	) {
		return preferred_index;
	}
	for (size_t index = 0; index < entries.size(); ++index) {
		if (entries[index].handle == ability_handle) return static_cast<int32_t>(index);
	}
	return -1;
}

bool DuelNativeCompactKernel::card_has_enabled_activation(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id
) const {
	if (!card_effects_enabled(value, card_index, owner_id)) {
		return false;
	}
	for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[card_index].size(); ++ability_index) {
		const CompiledAbility *ability = runtime_ability(value, card_index, static_cast<int32_t>(ability_index));
		if (
			ability != nullptr
			&& ability->has_activation
			&& ability->activation.declaration_valid
		) return true;
	}
	return false;
}

const DuelNativeCompactKernel::CompiledActivation *DuelNativeCompactKernel::get_activation_at(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id,
	int32_t activation_index
) const {
	if (
		activation_index < 0
		|| !card_effects_enabled(value, card_index, owner_id)
		|| card_index < 0
		|| card_index >= static_cast<int32_t>(value.card_runtime_abilities.size())
	) {
		return nullptr;
	}
	int32_t current_activation_index = 0;
	for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[card_index].size(); ++ability_index) {
		const CompiledAbility *ability = runtime_ability(
			value,
			card_index,
			static_cast<int32_t>(ability_index)
		);
		if (ability == nullptr || !ability->has_activation) continue;
		if (current_activation_index == activation_index) {
			return ability->activation.declaration_valid ? &ability->activation : nullptr;
		}
		++current_activation_index;
	}
	return nullptr;
}

bool DuelNativeCompactKernel::can_pay_activation_cost(
	const NativeState &value,
	int32_t source_card_index,
	const CompiledActivation &activation
) const {
	return (
		activation.declaration_valid
		&& source_card_index >= 0
		&& source_card_index < static_cast<int32_t>(value.card_ki.size())
		&& activation.required_ki > 0
		&& value.card_ki[source_card_index] >= activation.required_ki
	);
}

bool DuelNativeCompactKernel::activation_targets_hand(
	const CompiledActivation &activation
) const {
	return (
		activation.target_rule == TargetRuleOpcode::ENEMY_HAND_CARD
		|| activation.target_rule == TargetRuleOpcode::ALLY_HAND_CARD
	);
}

bool DuelNativeCompactKernel::activation_target_matches(
	const NativeState &value,
	int32_t owner_id,
	int32_t target_cell,
	TargetRuleOpcode target_rule
) const {
	if (
		target_cell < 0
		|| target_cell >= static_cast<int32_t>(value.board_card_indices.size())
	) return false;
	const int32_t target_card_index = value.board_card_indices[target_cell];
	switch (target_rule) {
		case TargetRuleOpcode::ADJACENT_EMPTY_BOARD:
		case TargetRuleOpcode::ANY_EMPTY_BOARD:
			return target_card_index < 0;
		case TargetRuleOpcode::ADJACENT_ALLY_BOARD:
		case TargetRuleOpcode::OTHER_ALLY_BOARD:
			return target_card_index >= 0 && value.board_owners[target_cell] == owner_id;
		case TargetRuleOpcode::ADJACENT_ENEMY_BOARD:
		case TargetRuleOpcode::ANY_ENEMY_BOARD:
			return target_card_index >= 0 && value.board_owners[target_cell] != owner_id;
		default:
			return false;
	}
}

int32_t DuelNativeCompactKernel::count_activation_target_indices(
	const NativeState &value,
	int32_t owner_id,
	int32_t source_cell,
	const CompiledActivation &activation
) const {
	if (
		owner_id < 1 || owner_id > 2
		|| source_cell < 0
		|| source_cell >= static_cast<int32_t>(value.board_card_indices.size())
		|| value.board_card_indices[source_cell] < 0
		|| value.board_owners[source_cell] != owner_id
		|| !activation.declaration_valid
	) return 0;
	if (activation_targets_hand(activation)) {
		const int32_t target_owner = (
			activation.target_rule == TargetRuleOpcode::ENEMY_HAND_CARD
			? other_owner(owner_id)
			: owner_id
		);
		const int32_t zone_index = target_owner - 1;
		return (
			zone_index >= 0 && zone_index < static_cast<int32_t>(value.zones.size())
			? static_cast<int32_t>(value.zones[zone_index].size())
			: 0
		);
	}
	int32_t count = 0;
	if (
		activation.target_rule == TargetRuleOpcode::OTHER_ALLY_BOARD
		|| activation.target_rule == TargetRuleOpcode::ANY_EMPTY_BOARD
		|| activation.target_rule == TargetRuleOpcode::ANY_ENEMY_BOARD
	) {
		for (size_t target_cell = 0; target_cell < value.board_card_indices.size(); ++target_cell) {
			if (
				static_cast<int32_t>(target_cell) != source_cell
				&& activation_target_matches(
					value,
					owner_id,
					static_cast<int32_t>(target_cell),
					activation.target_rule
				)
			) count += 1;
		}
		return count;
	}
	for (int32_t direction = 0; direction < 4; ++direction) {
		if (activation_target_matches(
			value,
			owner_id,
			neighbor_index(source_cell, direction),
			activation.target_rule
		)) count += 1;
	}
	return count;
}

std::vector<int32_t> DuelNativeCompactKernel::get_activation_target_indices(
	const NativeState &value,
	int32_t owner_id,
	int32_t source_cell,
	const CompiledActivation &activation
) const {
	std::vector<int32_t> targets;
	if (
		owner_id < 1 || owner_id > 2
		|| source_cell < 0
		|| source_cell >= static_cast<int32_t>(value.board_card_indices.size())
		|| value.board_card_indices[source_cell] < 0
		|| value.board_owners[source_cell] != owner_id
		|| !activation.declaration_valid
	) {
		return targets;
	}
	if (activation_targets_hand(activation)) {
		const int32_t target_owner = (
			activation.target_rule == TargetRuleOpcode::ENEMY_HAND_CARD
			? other_owner(owner_id)
			: owner_id
		);
		const int32_t zone_index = target_owner - 1;
		if (zone_index < 0 || zone_index >= static_cast<int32_t>(value.zones.size())) {
			return targets;
		}
		targets.reserve(value.zones[zone_index].size());
		for (size_t index = 0; index < value.zones[zone_index].size(); ++index) {
			targets.push_back(static_cast<int32_t>(index));
		}
		return targets;
	}

	if (
		activation.target_rule == TargetRuleOpcode::OTHER_ALLY_BOARD
		|| activation.target_rule == TargetRuleOpcode::ANY_EMPTY_BOARD
		|| activation.target_rule == TargetRuleOpcode::ANY_ENEMY_BOARD
	) {
		for (size_t target_cell = 0; target_cell < value.board_card_indices.size(); ++target_cell) {
			if (
				static_cast<int32_t>(target_cell) != source_cell
				&& activation_target_matches(
					value,
					owner_id,
					static_cast<int32_t>(target_cell),
					activation.target_rule
				)
			) targets.push_back(static_cast<int32_t>(target_cell));
		}
		return targets;
	}
	for (int32_t direction = 0; direction < 4; ++direction) {
		const int32_t target_cell = neighbor_index(source_cell, direction);
		if (activation_target_matches(
			value,
			owner_id,
			target_cell,
			activation.target_rule
		)) targets.push_back(target_cell);
	}
	return targets;
}

bool DuelNativeCompactKernel::card_has_enabled_modifiers(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id
) const {
	if (!card_effects_enabled(value, card_index, owner_id)) {
		return false;
	}
	for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[card_index].size(); ++ability_index) {
		const CompiledAbility *ability = runtime_ability(value, card_index, static_cast<int32_t>(ability_index));
		if (ability != nullptr && !ability->modifiers.empty()) return true;
	}
	return false;
}

bool DuelNativeCompactKernel::card_has_enabled_event(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id,
	const StringName &event_id
) const {
	if (!card_effects_enabled(value, card_index, owner_id)) {
		return false;
	}
	for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[card_index].size(); ++ability_index) {
		const CompiledAbility *ability = runtime_ability(value, card_index, static_cast<int32_t>(ability_index));
		if (ability == nullptr) continue;
		for (const CompiledTriggerRule &rule : ability->triggers) {
			if (rule.event_id == event_id) return true;
		}
	}
	return false;
}

bool DuelNativeCompactKernel::card_has_unsupported_enabled_modifier(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id
) const {
	if (!card_effects_enabled(value, card_index, owner_id)) return false;
	for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[card_index].size(); ++ability_index) {
		const CompiledAbility *ability = runtime_ability(value, card_index, static_cast<int32_t>(ability_index));
		if (ability == nullptr) continue;
		for (const CompiledModifier &modifier : ability->modifiers) {
			if (modifier.opcode == ModifierOpcode::UNSUPPORTED) return true;
		}
	}
	return false;
}

bool DuelNativeCompactKernel::card_has_modifier(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id,
	ModifierOpcode opcode,
	int32_t *out_value
) const {
	if (!card_effects_enabled(value, card_index, owner_id)) return false;
	bool found = false;
	for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[card_index].size(); ++ability_index) {
		const CompiledAbility *ability = runtime_ability(value, card_index, static_cast<int32_t>(ability_index));
		if (ability == nullptr) continue;
		for (const CompiledModifier &modifier : ability->modifiers) {
			if (modifier.opcode == opcode) {
				found = true;
				if (out_value != nullptr) *out_value = modifier.value;
			}
		}
	}
	return found;
}

bool DuelNativeCompactKernel::card_modifier_has_flag(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id,
	ModifierOpcode opcode,
	int32_t flag
) const {
	if (!card_effects_enabled(value, card_index, owner_id)) return false;
	for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[card_index].size(); ++ability_index) {
		const CompiledAbility *ability = runtime_ability(value, card_index, static_cast<int32_t>(ability_index));
		if (ability == nullptr) continue;
		for (const CompiledModifier &modifier : ability->modifiers) {
			if (modifier.opcode == opcode && (modifier.value & flag) != 0) return true;
		}
	}
	return false;
}

int32_t DuelNativeCompactKernel::count_owned(
	const NativeState &value,
	int32_t owner_id
) const {
	int32_t count = 0;
	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		if (value.board_card_indices[cell] >= 0 && value.board_owners[cell] == owner_id) ++count;
	}
	return count;
}

bool DuelNativeCompactKernel::attack_is_prohibited(
	const NativeState &value,
	int32_t attacker_owner
) const {
	if (attacker_owner != 1 && attacker_owner != 2) return true;
	const int32_t turn_owner = value.scalars[0];
	if (turn_owner == attacker_owner) return false;
	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		const int32_t source_card_index = value.board_card_indices[cell];
		if (source_card_index < 0 || value.board_owners[cell] != turn_owner) continue;
		if (card_has_modifier(
			value,
			source_card_index,
			turn_owner,
			ModifierOpcode::ENEMY_CANNOT_ATTACK_DURING_OWNER_TURN
		)) return true;
	}
	return false;
}

std::vector<int32_t> DuelNativeCompactKernel::snapshot_summon_attack_redirect_sources(
	const NativeState &value,
	int32_t summon_cell,
	int32_t summoning_owner
) const {
	std::vector<int32_t> sources;
	for (int32_t direction = 0; direction < 4; ++direction) {
		const int32_t source_cell = neighbor_index(summon_cell, direction);
		if (source_cell < 0) continue;
		const int32_t source_card_index = value.board_card_indices[source_cell];
		const int32_t source_owner = value.board_owners[source_cell];
		if (source_card_index < 0 || source_owner == summoning_owner) continue;
		if (card_has_modifier(
			value,
			source_card_index,
			source_owner,
			ModifierOpcode::ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES
		)) sources.push_back(source_card_index);
	}
	return sources;
}

DuelNativeCompactKernel::AttackPolicy DuelNativeCompactKernel::get_summon_attack_policy(
	const NativeState &value,
	int32_t summoned_cell,
	int32_t summoning_owner,
	const std::vector<int32_t> &source_card_indices
) const {
	AttackPolicy policy;
	for (const int32_t source_card_index : source_card_indices) {
		const int32_t source_cell = find_board_card(value, source_card_index);
		if (source_cell < 0) continue;
		const int32_t row_delta = std::abs(source_cell / 3 - summoned_cell / 3);
		const int32_t column_delta = std::abs(source_cell % 3 - summoned_cell % 3);
		if (row_delta + column_delta != 1) continue;
		const int32_t source_owner = value.board_owners[source_cell];
		if (source_owner == summoning_owner) continue;
		if (!card_has_modifier(
			value,
			source_card_index,
			source_owner,
			ModifierOpcode::ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES
		)) continue;
		policy.target_policy = AttackTargetPolicy::ALLIES_ONLY;
		policy.specified = true;
		return policy;
	}
	return policy;
}

DuelNativeCompactKernel::AttackPolicy DuelNativeCompactKernel::get_standard_attack_policy(
	const NativeState &value,
	int32_t attacker_cell,
	int32_t attacker_card_index,
	int32_t attacker_owner,
	const AttackPolicy &requested_policy
) const {
	if (
		attacker_cell >= 0
		&& attacker_cell < static_cast<int32_t>(value.board_card_indices.size())
		&& value.board_card_indices[attacker_cell] == attacker_card_index
		&& card_has_modifier(
			value,
			attacker_card_index,
			attacker_owner,
			ModifierOpcode::SELF_ATTACKS_ALL
		)
	) {
		AttackPolicy policy;
		policy.target_policy = AttackTargetPolicy::ALL;
		policy.specified = true;
		return policy;
	}
	if (requested_policy.specified) return requested_policy;
	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		const int32_t source_card_index = value.board_card_indices[cell];
		const int32_t source_owner = value.board_owners[cell];
		if (source_card_index < 0 || source_owner == attacker_owner) continue;
		if (!card_has_modifier(
			value,
			source_card_index,
			source_owner,
			ModifierOpcode::ENEMY_ATTACKS_ALL
		)) continue;
		AttackPolicy policy;
		policy.target_policy = AttackTargetPolicy::ALL;
		policy.capture_owner_id = source_owner;
		policy.specified = true;
		return policy;
	}
	return AttackPolicy();
}

std::vector<int32_t> DuelNativeCompactKernel::get_attack_targets(
	const NativeState &value,
	int32_t source_cell,
	const AttackPolicy &policy
) const {
	std::vector<int32_t> targets;
	if (
		source_cell < 0
		|| source_cell >= static_cast<int32_t>(value.board_card_indices.size())
		|| value.board_card_indices[source_cell] < 0
	) return targets;
	const int32_t source_card_index = value.board_card_indices[source_cell];
	const int32_t source_owner = value.board_owners[source_cell];
	const bool unlimited_range = card_has_modifier(
		value,
		source_card_index,
		source_owner,
		ModifierOpcode::UNLIMITED_ATTACK_RANGE
	);
	std::vector<int32_t> candidates;
	if (unlimited_range) {
		for (int32_t cell = 0; cell < static_cast<int32_t>(value.board_card_indices.size()); ++cell) {
			if (cell != source_cell) candidates.push_back(cell);
		}
	} else {
		for (int32_t direction = 0; direction < 4; ++direction) {
			const int32_t adjacent_cell = neighbor_index(source_cell, direction);
			if (adjacent_cell < 0) continue;
			candidates.push_back(adjacent_cell);
			const int32_t distance_two_cell = neighbor_index(adjacent_cell, direction);
			if (distance_two_cell >= 0) candidates.push_back(distance_two_cell);
		}
	}
	const bool first_legal_only = card_has_modifier(
		value,
		source_card_index,
		source_owner,
		ModifierOpcode::STANDARD_ATTACK_FIRST_LEGAL_TARGET
	);
	for (const int32_t target_cell : candidates) {
		if (!can_attack_target(value, source_cell, target_cell, policy, false)) continue;
		targets.push_back(target_cell);
		if (first_legal_only) break;
	}
	return targets;
}

bool DuelNativeCompactKernel::can_attack_target(
	const NativeState &value,
	int32_t source_cell,
	int32_t target_cell,
	const AttackPolicy &policy,
	bool skip_power_comparison
) const {
	if (
		source_cell < 0
		|| source_cell >= static_cast<int32_t>(value.board_card_indices.size())
		|| value.board_card_indices[source_cell] < 0
	) return false;
	const int32_t source_card_index = value.board_card_indices[source_cell];
	const int32_t source_owner = value.board_owners[source_cell];
	if (
		card_has_modifier(
			value,
			source_card_index,
			source_owner,
			ModifierOpcode::ATTACK_REQUIRES_OTHER_ALLY
		)
		&& count_owned(value, source_owner) < 2
	) return false;
	return is_target_in_attack_range(
		value,
		source_cell,
		target_cell,
		policy,
		skip_power_comparison
	);
}

bool DuelNativeCompactKernel::is_target_in_attack_range(
	const NativeState &value,
	int32_t source_cell,
	int32_t target_cell,
	const AttackPolicy &policy,
	bool skip_power_comparison
) const {
	if (
		source_cell < 0
		|| source_cell >= static_cast<int32_t>(value.board_card_indices.size())
		|| target_cell < 0
		|| target_cell >= static_cast<int32_t>(value.board_card_indices.size())
		|| source_cell == target_cell
		|| value.board_card_indices[source_cell] < 0
		|| value.board_card_indices[target_cell] < 0
	) return false;
	const int32_t source_card_index = value.board_card_indices[source_cell];
	const int32_t target_card_index = value.board_card_indices[target_cell];
	const int32_t source_owner = value.board_owners[source_cell];
	const int32_t target_owner = value.board_owners[target_cell];
	if (
		(policy.target_policy == AttackTargetPolicy::ENEMIES_ONLY && source_owner == target_owner)
		|| (policy.target_policy == AttackTargetPolicy::ALLIES_ONLY && source_owner != target_owner)
	) return false;

	const int32_t source_row = source_cell / 3;
	const int32_t source_column = source_cell % 3;
	const int32_t target_row = target_cell / 3;
	const int32_t target_column = target_cell % 3;
	const int32_t row_delta = target_row - source_row;
	const int32_t column_delta = target_column - source_column;
	const bool same_axis = row_delta == 0 || column_delta == 0;
	const bool unlimited_range = card_has_modifier(
		value,
		source_card_index,
		source_owner,
		ModifierOpcode::UNLIMITED_ATTACK_RANGE
	);
	if (!same_axis && !unlimited_range) return false;
	if (
		!same_axis
		&& !card_has_modifier(
			value,
			source_card_index,
			source_owner,
			ModifierOpcode::NON_ORTHOGONAL_ATTACK_ANY_AXIS
		)
	) return false;

	int32_t direction = -1;
	int32_t distance = 0;
	if (same_axis) {
		if (row_delta < 0) direction = 0;
		else if (column_delta > 0) direction = 1;
		else if (row_delta > 0) direction = 2;
		else if (column_delta < 0) direction = 3;
		distance = std::max(std::abs(row_delta), std::abs(column_delta));
	}
	if (!unlimited_range && distance > 2) return false;
	if (!unlimited_range && distance == 2) {
		if (!card_has_modifier(
			value,
			source_card_index,
			source_owner,
			ModifierOpcode::ORTHOGONAL_ATTACK_RANGE_TWO
		)) return false;
		const int32_t intervening_cell = neighbor_index(source_cell, direction);
		const int32_t intervening_card_index = value.board_card_indices[intervening_cell];
		if (intervening_card_index >= 0) {
			const bool intervening_is_ally = value.board_owners[intervening_cell] == source_owner;
			const int32_t required_flag = intervening_is_ally ? 1 : 2;
			if (!card_modifier_has_flag(
				value,
				source_card_index,
				source_owner,
				ModifierOpcode::ORTHOGONAL_ATTACK_RANGE_TWO,
				required_flag
			)) return false;
		}
	}
	if (skip_power_comparison) return true;

	const bool comparison_reversed = (
		card_has_modifier(
			value,
			source_card_index,
			source_owner,
			ModifierOpcode::POWER_COMPARISON_REVERSED
		)
		|| card_has_modifier(
			value,
			target_card_index,
			target_owner,
			ModifierOpcode::POWER_COMPARISON_REVERSED
		)
	);
	static constexpr int32_t opposite[4] = {2, 3, 0, 1};
	if (same_axis) {
		return power_pair_wins(
			value,
			source_card_index,
			source_owner,
			target_card_index,
			target_owner,
			direction,
			opposite[direction],
			comparison_reversed
		);
	}
	const int32_t vertical_direction = row_delta < 0 ? 0 : 2;
	const int32_t horizontal_direction = column_delta < 0 ? 3 : 1;
	return (
		power_pair_wins(
			value,
			source_card_index,
			source_owner,
			target_card_index,
			target_owner,
			vertical_direction,
			opposite[vertical_direction],
			comparison_reversed
		)
		|| power_pair_wins(
			value,
			source_card_index,
			source_owner,
			target_card_index,
			target_owner,
			horizontal_direction,
			opposite[horizontal_direction],
			comparison_reversed
		)
	);
}

bool DuelNativeCompactKernel::power_pair_wins(
	const NativeState &value,
	int32_t source_card_index,
	int32_t source_owner,
	int32_t target_card_index,
	int32_t target_owner,
	int32_t attacking_direction,
	int32_t defending_direction,
	bool comparison_reversed
) const {
	if (is_special_negative(value, source_card_index)) return false;
	const int32_t attacking_power = value.card_powers[source_card_index * 4 + attacking_direction];
	if (is_special_negative(value, target_card_index)) return attacking_power >= 0;
	const int32_t defending_power = (
		card_has_modifier(
			value,
			source_card_index,
			source_owner,
			ModifierOpcode::DEFENDING_POWER_USES_MINIMUM_SIDE
		)
		? minimum_effective_defending_power(value, target_card_index, target_owner)
		: effective_defending_power(value, target_card_index, target_owner, defending_direction)
	);
	return comparison_reversed ? attacking_power < defending_power : attacking_power > defending_power;
}

void DuelNativeCompactKernel::append_resolution(
	Resolution &destination,
	const Resolution &addition
) const {
	if (!addition.supported) {
		destination.supported = false;
		if (destination.reason.is_empty()) destination.reason = addition.reason;
	}
	const int64_t event_offset = destination.events.size();
	destination.events.append_array(addition.events);
	for (const auto &range : addition.protected_power_batch_ranges) {
		destination.protected_power_batch_ranges.push_back({
			range.first + event_offset,
			range.second + event_offset,
		});
	}
	if (include_presentation_payloads) {
		for (int64_t index = 0; index < addition.captures.size(); ++index) {
			const Variant value = addition.captures[index];
			if (destination.captures.find(value) < 0) destination.captures.append(value);
		}
		for (int64_t index = 0; index < addition.exiles.size(); ++index) {
			const Variant value = addition.exiles[index];
			if (destination.exiles.find(value) < 0) destination.exiles.append(value);
		}
	}
	destination.extra_play_requests.insert(
		destination.extra_play_requests.end(),
		addition.extra_play_requests.begin(),
		addition.extra_play_requests.end()
	);
	destination.flip_prevented = destination.flip_prevented || addition.flip_prevented;
}

bool DuelNativeCompactKernel::resolution_has_output(const Resolution &resolution) const {
	return (
		!resolution.events.is_empty()
		|| !resolution.captures.is_empty()
		|| !resolution.exiles.is_empty()
	);
}

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::resolve_attack_request(
	NativeState &value,
	const AttackRequest &request,
	std::vector<int32_t> &exile_stack
) const {
	Resolution resolution;
	const int32_t initial_attack_cell = find_board_card(
		value,
		request.attacker_card_index,
		request.attacker_cell
	);
	if (
		initial_attack_cell < 0
		|| value.board_owners[initial_attack_cell] != request.attacker_owner
		|| value.scalars[request.attacker_owner == 1 ? 3 : 4] >= 20
		|| attack_is_prohibited(value, request.attacker_owner)
	) {
		return resolution;
	}
	const AttackPolicy attack_policy = get_standard_attack_policy(
		value,
		initial_attack_cell,
		request.attacker_card_index,
		request.attacker_owner,
		request.requested_policy
	);
	std::vector<int32_t> target_cells;
	if (request.targeted) {
		const int32_t target_cell = find_board_card(
			value,
			request.locked_target_card_index,
			request.locked_target_cell
		);
		if (
			target_cell == request.locked_target_cell
			&& target_cell >= 0
			&& value.board_owners[target_cell] == request.locked_target_owner
			&& can_attack_target(
				value,
				initial_attack_cell,
				target_cell,
				attack_policy,
				false
			)
		) target_cells.push_back(target_cell);
	} else {
		target_cells = get_attack_targets(
			value,
			initial_attack_cell,
			attack_policy
		);
	}
	if (!target_cells.empty()) {
		value.scalars[request.attacker_owner == 1 ? 3 : 4] += 1;
	}
	bool attack_started = false;
	bool attack_flipped_enemy = false;
	std::vector<EventContext::AttackFlipRecord> attack_flips;
	auto resolution_flipped_attacker = [&](const Resolution &candidate) -> bool {
		const StringName attacker_instance_id = value.card_instance_ids[request.attacker_card_index];
		for (int64_t event_index = 0; event_index < candidate.events.size(); ++event_index) {
			if (candidate.events[event_index].get_type() != Variant::DICTIONARY) continue;
			const Dictionary event = candidate.events[event_index];
			if (
				StringName(event.get("type", StringName())) == StringName("card_flipped")
				&& StringName(event.get("instance_id", StringName())) == attacker_instance_id
			) return true;
		}
		return false;
	};
	for (const int32_t locked_cell : target_cells) {
		bool stop_after_current_target = false;
		const int32_t attacker_cell = find_board_card(
			value,
			request.attacker_card_index,
			request.attacker_cell
		);
		if (
			attacker_cell < 0
			|| value.board_owners[attacker_cell] != request.attacker_owner
		) break;
		const int32_t attacked_card_index = value.board_card_indices[locked_cell];
		if (attacked_card_index < 0) continue;
		const int32_t attacked_cell = locked_cell;
		if (!can_attack_target(value, attacker_cell, attacked_cell, attack_policy, true)) continue;
		const int32_t attacked_owner = value.board_owners[attacked_cell];
		const StringName attacked_instance_id = value.card_instance_ids[attacked_card_index];

		Dictionary attack_event;
		attack_event["type"] = StringName("attack_started");
		attack_event["source_cell"] = attacker_cell;
		attack_event["source_instance_id"] = value.card_instance_ids[request.attacker_card_index];
		attack_event["source_owner_id"] = request.attacker_owner;
		attack_event["target_cell"] = attacked_cell;
		attack_event["target_instance_id"] = attacked_instance_id;
		attack_event["target_owner_id"] = attacked_owner;
		attack_event["attack_reason"] = request.reason;
		resolution.events.append(attack_event);
		attack_started = true;

		EventContext attack_context;
		attack_context.attacker_cell = attacker_cell;
		attack_context.attacker_card_index = request.attacker_card_index;
		attack_context.attacker_owner = request.attacker_owner;
		attack_context.attacked_cell = attacked_cell;
		attack_context.attacked_card_index = attacked_card_index;
		attack_context.attacked_owner = attacked_owner;
		attack_context.trigger_cell = attacked_cell;
		attack_context.trigger_card_index = attacked_card_index;
		attack_context.trigger_owner = attacked_owner;
		attack_context.trigger_previous_owner = attacked_owner;
		attack_context.trigger_zone = 0;
		attack_context.trigger_logical_index = attacked_cell;
		attack_context.trigger_was_on_board = true;
		attack_context.attack_reason = request.reason;
		Resolution be_attacked = resolve_event(
			value,
			StringName("card_be_attacked"),
			attack_context,
			exile_stack
		);
		if (!be_attacked.supported) return be_attacked;
		stop_after_current_target = resolution_flipped_attacker(be_attacked);
		append_resolution(resolution, be_attacked);
		const int32_t current_attacker_cell = find_board_card(
			value,
			request.attacker_card_index,
			attacker_cell
		);
		const int32_t current_attacked_cell = find_board_card(
			value,
			attacked_card_index,
			attacked_cell
		);
		if (
			current_attacker_cell < 0
			|| value.board_owners[current_attacker_cell] != request.attacker_owner
		) break;
		if (current_attacked_cell < 0) {
			if (stop_after_current_target) break;
			continue;
		}
		if (!can_attack_target(
			value,
			current_attacker_cell,
			current_attacked_cell,
			attack_policy,
			true
		)) {
			if (stop_after_current_target) break;
			continue;
		}
		int32_t resolved_capture_owner = request.attacker_owner;
		if (value.board_owners[current_attacked_cell] == request.attacker_owner) {
			resolved_capture_owner = (
				attack_policy.capture_owner_id != 0
				? attack_policy.capture_owner_id
				: other_owner(request.attacker_owner)
			);
		}
		if (resolved_capture_owner == value.board_owners[current_attacked_cell]) {
			if (stop_after_current_target) break;
			continue;
		}
		EventContext before_context = attack_context;
		before_context.attacker_cell = current_attacker_cell;
		before_context.attacked_cell = current_attacked_cell;
		before_context.attacked_owner = value.board_owners[current_attacked_cell];
		before_context.trigger_cell = current_attacked_cell;
		before_context.trigger_owner = value.board_owners[current_attacked_cell];
		before_context.new_owner = resolved_capture_owner;
		before_context.flip_reason = request.reason;
		Resolution before_flip = resolve_event(
			value,
			StringName("card_before_flipped"),
			before_context,
			exile_stack
		);
		if (!before_flip.supported) return before_flip;
		stop_after_current_target = (
			stop_after_current_target || resolution_flipped_attacker(before_flip)
		);
		append_resolution(resolution, before_flip);
		if (before_flip.flip_prevented) {
			Dictionary prevented;
			prevented["type"] = StringName("card_flip_prevented");
			prevented["source_cell"] = current_attacker_cell;
			prevented["target_cell"] = current_attacked_cell;
			prevented["owner_id"] = attacked_owner;
			prevented["new_owner_id"] = resolved_capture_owner;
			prevented["instance_id"] = attacked_instance_id;
			resolution.events.append(prevented);
			Resolution after_prevented = resolve_event(
				value,
				StringName("card_flip_prevented"),
				before_context,
				exile_stack
			);
			if (!after_prevented.supported) return after_prevented;
			stop_after_current_target = (
				stop_after_current_target || resolution_flipped_attacker(after_prevented)
			);
			append_resolution(resolution, after_prevented);
			if (stop_after_current_target) break;
			continue;
		}
		const int32_t post_before_attacker_cell = find_board_card(
			value,
			request.attacker_card_index,
			current_attacker_cell
		);
		const int32_t post_before_attacked_cell = find_board_card(
			value,
			attacked_card_index,
			current_attacked_cell
		);
		if (
			post_before_attacker_cell < 0
			|| value.board_owners[post_before_attacker_cell] != request.attacker_owner
		) break;
		if (
			post_before_attacked_cell < 0
			|| value.board_owners[post_before_attacked_cell] == resolved_capture_owner
		) {
			if (stop_after_current_target) break;
			continue;
		}
		const int32_t flipped_previous_owner = value.board_owners[post_before_attacked_cell];
		Resolution flip_resolution;
		if (!flip_card(
			value,
			post_before_attacker_cell,
			request.attacker_card_index,
			post_before_attacked_cell,
			attacked_card_index,
			resolved_capture_owner,
			before_context,
			exile_stack,
			flip_resolution
		)) return flip_resolution;
		stop_after_current_target = (
			stop_after_current_target || resolution_flipped_attacker(flip_resolution)
		);
		append_resolution(resolution, flip_resolution);
		attack_flipped_enemy = (
			attack_flipped_enemy
			|| flipped_previous_owner != request.attacker_owner
		);
		EventContext::AttackFlipRecord flip_record;
		flip_record.card_index = attacked_card_index;
		flip_record.previous_owner = flipped_previous_owner;
		attack_flips.push_back(flip_record);
		if (stop_after_current_target) break;
	}
	if (attack_started) {
		EventContext after_attack_context;
		after_attack_context.attacker_cell = find_board_card(
			value,
			request.attacker_card_index,
			request.attacker_cell
		);
		after_attack_context.attacker_card_index = request.attacker_card_index;
		after_attack_context.attacker_owner = request.attacker_owner;
		after_attack_context.attack_flipped_enemy = attack_flipped_enemy;
		after_attack_context.attack_flips = attack_flips;
		after_attack_context.repeat_attack = request.repeat_attack;
		Resolution after_attack = resolve_event(
			value,
			StringName("card_after_attack"),
			after_attack_context,
			exile_stack
		);
		if (!after_attack.supported) return after_attack;
		append_resolution(resolution, after_attack);
	}
	return resolution;
}

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::resolve_summon_lifecycle(
	NativeState &value,
	const SummonRequest &request,
	std::vector<int32_t> &exile_stack
) const {
	Resolution resolution;
	const std::vector<int32_t> summon_attack_redirect_sources = (
		request.attack_redirect_snapshot_taken
		? request.attack_redirect_source_card_indices
		: snapshot_summon_attack_redirect_sources(
			value,
			request.summon_cell,
			request.owner_id
		)
	);
	EventContext summon_context;
	summon_context.trigger_cell = request.summon_cell;
	summon_context.trigger_card_index = request.card_index;
	summon_context.trigger_owner = request.owner_id;
	summon_context.trigger_previous_owner = request.owner_id;
	summon_context.trigger_zone = 0;
	summon_context.trigger_logical_index = request.summon_cell;
	summon_context.trigger_was_on_board = true;
	Resolution before_summoned = resolve_event(
		value,
		StringName("card_before_summoned"),
		summon_context,
		exile_stack
	);
	if (!before_summoned.supported) return before_summoned;
	append_resolution(resolution, before_summoned);
	resolution.events.append_array(request.buffered_placement_events);

	Resolution summoned = resolve_event(
		value,
		StringName("card_summoned"),
		summon_context,
		exile_stack
	);
	if (!summoned.supported) return summoned;
	append_resolution(resolution, summoned);

	const int32_t after_cell = find_board_card(value, request.card_index, request.summon_cell);
	if (after_cell >= 0) {
		EventContext after_context = summon_context;
		after_context.trigger_cell = after_cell;
		after_context.trigger_owner = value.board_owners[after_cell];
		after_context.trigger_logical_index = after_cell;
		Resolution after_summoned = resolve_event(
			value,
			StringName("card_after_summoned"),
			after_context,
			exile_stack
		);
		if (!after_summoned.supported) return after_summoned;
		append_resolution(resolution, after_summoned);
	}

	AttackRequest attack_request;
	attack_request.attacker_cell = after_cell;
	attack_request.attacker_card_index = request.card_index;
	attack_request.attacker_owner = request.owner_id;
	const int32_t initial_attack_cell = find_board_card(
		value,
		request.card_index,
		request.summon_cell
	);
	if (initial_attack_cell >= 0) {
		attack_request.requested_policy = get_summon_attack_policy(
			value,
			initial_attack_cell,
			request.owner_id,
			summon_attack_redirect_sources
		);
	}
	attack_request.reason = request.attack_reason.is_empty()
		? StringName("summon_standard_attack")
		: request.attack_reason;
	Resolution attack_resolution = resolve_attack_request(
		value,
		attack_request,
		exile_stack
	);
	if (!attack_resolution.supported) return attack_resolution;
	append_resolution(resolution, attack_resolution);
	return resolution;
}

bool DuelNativeCompactKernel::board_has_enabled_event(
	const NativeState &value,
	const StringName &event_id
) const {
	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		const int32_t card_index = value.board_card_indices[cell];
		if (
			card_index >= 0
			&& card_has_enabled_event(value, card_index, value.board_owners[cell], event_id)
		) {
			return true;
		}
	}
	return false;
}

bool DuelNativeCompactKernel::board_has_enabled_activation_for_owner(
	const NativeState &value,
	int32_t owner_id
) const {
	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		const int32_t card_index = value.board_card_indices[cell];
		if (card_index < 0 || value.board_owners[cell] != owner_id) continue;
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
			if (
				ability == nullptr
				|| !ability->has_activation
				|| !ability->activation.declaration_valid
			) continue;
			const CompiledActivation &activation = ability->activation;
			if (
				can_pay_activation_cost(value, card_index, activation)
				&& count_activation_target_indices(
					value,
					owner_id,
					static_cast<int32_t>(cell),
					activation
				) > 0
			) return true;
		}
	}
	return false;
}

bool DuelNativeCompactKernel::is_special_negative(
	const NativeState &value,
	int32_t card_index
) const {
	if (card_index < 0 || card_index >= static_cast<int32_t>(value.card_instance_ids.size())) return false;
	for (int32_t direction = 0; direction < 4; ++direction) {
		if (value.card_powers[card_index * 4 + direction] != -1) return false;
	}
	return true;
}

bool DuelNativeCompactKernel::powers_supported(
	const NativeState &value,
	int32_t card_index
) const {
	if (is_special_negative(value, card_index)) return true;
	for (int32_t direction = 0; direction < 4; ++direction) {
		if (value.card_powers[card_index * 4 + direction] < 0) return false;
	}
	return true;
}

bool DuelNativeCompactKernel::can_change_powers(
	const NativeState &value,
	int32_t card_index
) const {
	return !is_special_negative(value, card_index);
}

int32_t DuelNativeCompactKernel::effective_defending_power(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id,
	int32_t direction
) const {
	int32_t result = value.card_powers[card_index * 4 + direction];
	card_has_modifier(
		value,
		card_index,
		owner_id,
		ModifierOpcode::DEFENDING_POWER_OVERRIDE,
		&result
	);
	return result;
}

int32_t DuelNativeCompactKernel::minimum_effective_defending_power(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id
) const {
	int32_t result = effective_defending_power(value, card_index, owner_id, 0);
	for (int32_t direction = 1; direction < 4; ++direction) {
		result = std::min(
			result,
			effective_defending_power(value, card_index, owner_id, direction)
		);
	}
	return result;
}

int32_t DuelNativeCompactKernel::find_board_card(
	const NativeState &value,
	int32_t card_index,
	int32_t hint
) const {
	if (
		hint >= 0
		&& hint < static_cast<int32_t>(value.board_card_indices.size())
		&& value.board_card_indices[hint] == card_index
	) return hint;
	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		if (value.board_card_indices[cell] == card_index) return static_cast<int32_t>(cell);
	}
	return -1;
}

bool DuelNativeCompactKernel::locate_card(
	const NativeState &value,
	int32_t card_index,
	int32_t &zone_kind,
	int32_t &owner_id,
	int32_t &logical_index
) const {
	const int32_t board_cell = find_board_card(value, card_index);
	if (board_cell >= 0) {
		zone_kind = 0;
		owner_id = value.board_owners[board_cell];
		logical_index = board_cell;
		return true;
	}
	static constexpr int32_t zone_kinds[8] = {1, 1, 2, 2, 3, 3, 4, 4};
	for (int32_t zone_index = 0; zone_index < static_cast<int32_t>(value.zones.size()); ++zone_index) {
		const std::vector<int32_t> &zone = value.zones[zone_index];
		const auto found = std::find(zone.begin(), zone.end(), card_index);
		if (found == zone.end()) continue;
		zone_kind = zone_kinds[zone_index];
		owner_id = zone_index % 2 + 1;
		logical_index = static_cast<int32_t>(std::distance(zone.begin(), found));
		return true;
	}
	return false;
}

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
				matched = (
					context.trigger_card_index == group.source_card_index
					&& context.trigger_cell == group.source_cell
				);
				break;
			case ConditionOpcode::TRIGGER_CARD_IS_ALLY:
			case ConditionOpcode::TRIGGER_CARD_IS_ENEMY: {
				const int32_t trigger_cell = find_board_card(
					value,
					context.trigger_card_index,
					context.trigger_cell
				);
				matched = (
					trigger_cell == context.trigger_cell
					&& trigger_cell >= 0
					&& (
						(value.board_owners[trigger_cell] == group.source_owner)
						== (condition.opcode == ConditionOpcode::TRIGGER_CARD_IS_ALLY)
					)
				);
				break;
			}
			case ConditionOpcode::TRIGGER_CARD_IN_RANGE: {
				const int32_t trigger_cell = find_board_card(
					value,
					context.trigger_card_index,
					context.trigger_cell
				);
				AttackPolicy policy;
				matched = (
					trigger_cell == context.trigger_cell
					&& trigger_cell >= 0
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
			case ConditionOpcode::TRIGGER_CARD_ADJACENT_TO_SOURCE:
				for (int32_t direction = 0; direction < 4; ++direction) {
					if (neighbor_index(group.source_cell, direction) == context.trigger_cell) {
						matched = true;
						break;
					}
				}
				break;
			case ConditionOpcode::TRIGGER_CARD_OUTSIDE_SOURCE_OWNER_HAND:
				matched = !(context.trigger_zone == 1 && context.trigger_owner == group.source_owner);
				break;
			case ConditionOpcode::TRIGGER_CARD_REVEALED_TO_SELF:
				if (
					context.trigger_card_index >= 0
					&& context.trigger_card_index < static_cast<int32_t>(value.card_reveal_codes.size())
					&& find_board_card(value, context.trigger_card_index, context.trigger_cell)
						== context.trigger_cell
				) {
					const uint8_t reveal_code = value.card_reveal_codes[context.trigger_card_index];
					matched = group.source_owner == 1
						? (reveal_code == 1 || reveal_code == 3 || reveal_code == 4)
						: (reveal_code == 2 || reveal_code == 3 || reveal_code == 4);
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
					&& find_board_card(value, context.trigger_card_index, context.trigger_cell) >= 0
					&& value.card_original_owners[context.trigger_card_index] == group.source_owner
				);
				break;
			case ConditionOpcode::ATTACKED_CARD_IS_SELF:
				matched = context.attacked_card_index == group.source_card_index;
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
				break;
			case ConditionOpcode::KI_CHANGED_CARD_IS_SELF:
				matched = context.trigger_card_index == group.source_card_index && context.trigger_cell == group.source_cell;
				break;
			case ConditionOpcode::KI_REACHED_ZERO:
				matched = context.previous_ki > 0 && context.ki == 0;
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
	std::vector<EventGroup> groups;
	supported = true;
	auto discover_card = [&](int32_t card_index, int32_t owner_id, int32_t source_cell, int32_t source_zone, int32_t logical_index) -> bool {
		if (!card_effects_enabled(value, card_index, owner_id)) return true;
		for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[card_index].size(); ++ability_index) {
			const CompiledAbility *ability = runtime_ability(value, card_index, static_cast<int32_t>(ability_index));
			if (ability == nullptr) continue;
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
	if (event_id == StringName("card_after_discarded")) {
		int32_t zone = -1;
		int32_t owner_id = 0;
		int32_t logical_index = -1;
		if (
			context.trigger_card_index >= 0
			&& locate_card(value, context.trigger_card_index, zone, owner_id, logical_index)
			&& zone == 3
			&& owner_id == context.trigger_owner
		) {
			discover_card(context.trigger_card_index, owner_id, -1, 3, logical_index);
		}
		return groups;
	}
	if (event_id == StringName("card_before_summoned")) {
		const int32_t trigger_cell = find_board_card(
			value,
			context.trigger_card_index,
			context.trigger_cell
		);
		if (trigger_cell == context.trigger_cell && trigger_cell >= 0) {
			discover_card(
				context.trigger_card_index,
				value.board_owners[trigger_cell],
				trigger_cell,
				0,
				trigger_cell
			);
		}
		return groups;
	}
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
	return groups;
}

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::resolve_event(
	NativeState &value,
	const StringName &event_id,
	const EventContext &context,
	std::vector<int32_t> &exile_stack
) const {
	Resolution resolution;
	bool discovery_supported = true;
	String discovery_reason;
	const std::vector<EventGroup> groups = discover_event(
		value,
		event_id,
		context,
		discovery_supported,
		discovery_reason
	);
	if (!discovery_supported) {
		resolution.supported = false;
		resolution.reason = discovery_reason;
		return resolution;
	}
	for (const EventGroup &group : groups) {
		const int32_t current_ability_index = find_runtime_ability_index(
			value,
			group.source_card_index,
			group.ability_handle,
			group.ability_index
		);
		bool source_is_current = false;
		int32_t current_logical_index = group.source_logical_index;
		if (group.source_zone == 3) {
			int32_t current_zone = -1;
			int32_t current_owner = 0;
			source_is_current = (
				locate_card(
					value,
					group.source_card_index,
					current_zone,
					current_owner,
					current_logical_index
				)
				&& current_zone == 3
				&& current_owner == group.source_owner
			);
		} else {
			source_is_current = (
				find_board_card(value, group.source_card_index, group.source_cell) == group.source_cell
				&& value.board_owners[group.source_cell] == group.source_owner
			);
		}
		if (
			!source_is_current
			|| !card_effects_enabled(value, group.source_card_index, group.source_owner)
			|| current_ability_index < 0
		) continue;
		const CompiledAbility *ability = runtime_ability(
			value,
			group.source_card_index,
			current_ability_index
		);
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
		if (context.ability_source_card_index >= 0) {
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

bool DuelNativeCompactKernel::draw_cards(
	NativeState &value,
	int32_t owner_id,
	int32_t source_cell,
	int32_t amount,
	const String &weapon_filter,
	const EventContext &draw_context,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	if (owner_id != 1 && owner_id != 2) return true;
	std::vector<int32_t> &hand = value.zones[owner_id - 1];
	std::vector<int32_t> &deck = value.zones[owner_id + 1];
	const Dictionary audiences_by_owner = value.side_payload.get("future_draw_reveal_audiences", Dictionary());
	const Variant audiences_value = audiences_by_owner.get(owner_id, Array());
	if (audiences_value.get_type() != Variant::ARRAY) {
		resolution.reason = "Future-draw reveal audiences are not an Array";
		return false;
	}
	const Array reveal_audiences = audiences_value;
	for (int32_t draw_index = 0; draw_index < amount; ++draw_index) {
		if (hand.size() >= 5) break;
		int32_t card_index = -1;
		if (!weapon_filter.is_empty()) {
			auto matching = std::find_if(deck.begin(), deck.end(), [&](const int32_t candidate) {
				if (
					candidate < 0
					|| candidate >= static_cast<int32_t>(value.card_template_indices.size())
				) return false;
				const int32_t template_index = value.card_template_indices[candidate];
				if (template_index < 0 || template_index >= value.card_template_pool.size()) return false;
				const Variant template_value = value.card_template_pool[template_index];
				if (template_value.get_type() != Variant::DICTIONARY) return false;
				return String(Dictionary(template_value).get("weapon", String())) == weapon_filter;
			});
			if (matching == deck.end()) break;
			card_index = *matching;
			deck.erase(matching);
		} else if (!deck.empty()) {
			card_index = deck.front();
			deck.erase(deck.begin());
		} else {
			if (
				value.empty_deck_draw_prototype_index < 0
				|| value.empty_deck_draw_prototype_index
					>= static_cast<int32_t>(value.fresh_card_prototypes.size())
			) {
				resolution.reason = "Draw has no generated empty-deck fallback prototype";
				return false;
			}
			const StringName fallback_id = value.fresh_card_prototypes[
				value.empty_deck_draw_prototype_index
			].card_id;
			String append_reason;
			card_index = append_fresh_board_card(
				value,
				fallback_id,
				make_generated_instance_id(value, fallback_id),
				owner_id,
				append_reason
			);
			if (card_index < 0) {
				resolution.reason = append_reason;
				return false;
			}
		}
		const int32_t slot = leftmost_empty_hand_slot(value, owner_id);
		if (slot < 0) break;
		const int32_t previous_hand_size = static_cast<int32_t>(hand.size());
		value.card_runtime_flags[card_index] |= static_cast<uint8_t>(1 << 7);
		value.card_hand_slots[card_index] = slot;
		hand.push_back(card_index);
		const int32_t logical_hand_index = static_cast<int32_t>(hand.size()) - 1;
		Dictionary event;
		event["type"] = StringName("card_drawn");
		event["source_cell"] = source_cell;
		event["owner_id"] = owner_id;
		event["card_id"] = value.card_ids[card_index];
		event["instance_id"] = value.card_instance_ids[card_index];
		event["logical_hand_index"] = logical_hand_index;
		event["hand_slot_index"] = slot;
		if (include_presentation_payloads) {
			event["card"] = restore_runtime_card(value, card_index);
		}
		resolution.events.append(event);
		for (int64_t audience_index = 0; audience_index < reveal_audiences.size(); ++audience_index) {
			const Variant observer_value = reveal_audiences[audience_index];
			if (observer_value.get_type() != Variant::INT) {
				resolution.reason = "Future-draw reveal audience is not an owner integer";
				return false;
			}
			const int32_t observer_owner = static_cast<int32_t>(static_cast<int64_t>(observer_value));
			if (observer_owner != 1 && observer_owner != 2) continue;
			uint8_t &reveal_code = value.card_reveal_codes[card_index];
			const bool already_revealed = (
				(observer_owner == 1 && (reveal_code == 1 || reveal_code == 3 || reveal_code == 4))
				|| (observer_owner == 2 && (reveal_code == 2 || reveal_code == 3 || reveal_code == 4))
			);
			if (already_revealed) continue;
			if (observer_owner == 1) reveal_code = reveal_code == 2 ? 4 : 1;
			else reveal_code = reveal_code == 1 ? 3 : 2;
			Dictionary revealed;
			revealed["type"] = StringName("card_revealed");
			revealed["source_cell"] = source_cell;
			revealed["owner_id"] = owner_id;
			revealed["observer_owner_id"] = observer_owner;
			revealed["card_id"] = value.card_ids[card_index];
			revealed["instance_id"] = value.card_instance_ids[card_index];
			revealed["logical_hand_index"] = logical_hand_index;
			resolution.events.append(revealed);
		}

		Resolution hand_change = resolve_difficulty_hand_change(
			value,
			owner_id,
			previous_hand_size,
			static_cast<int32_t>(hand.size()),
			source_cell,
			exile_stack
		);
		if (!hand_change.supported) {
			resolution.reason = hand_change.reason;
			return false;
		}
		append_resolution(resolution, hand_change);

		EventContext after_draw_context = draw_context;
		after_draw_context.trigger_cell = -1;
		after_draw_context.trigger_card_index = card_index;
		after_draw_context.trigger_owner = owner_id;
		after_draw_context.trigger_previous_owner = owner_id;
		after_draw_context.trigger_zone = 1;
		after_draw_context.trigger_logical_index = logical_hand_index;
		after_draw_context.trigger_was_on_board = false;
		Resolution after_drawn = resolve_event(
			value,
			StringName("card_after_drawn"),
			after_draw_context,
			exile_stack
		);
		if (!after_drawn.supported) {
			resolution.reason = after_drawn.reason;
			return false;
		}
		append_resolution(resolution, after_drawn);
	}
	return true;
}

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::resolve_difficulty_hand_change(
	NativeState &value,
	int32_t owner_id,
	int32_t previous_size,
	int32_t current_size,
	int32_t source_cell,
	std::vector<int32_t> &exile_stack
) const {
	Resolution resolution;
	if (
		owner_id != 2
		|| previous_size == current_size
		|| current_size != 1
		|| value.scalars[11] != 0
		|| value.scalars[10] < 8
	) return resolution;
	value.scalars[11] = 1;
	const std::vector<int32_t> &hand = value.zones[1];
	if (hand.empty()) return resolution;
	const int32_t source_card_index = hand.front();
	EventContext context;
	context.ability_source_cell = -1;
	context.ability_source_zone = 1;
	context.ability_source_logical_index = 0;
	context.ability_source_card_index = source_card_index;
	context.ability_source_owner = owner_id;
	if (!draw_cards(value, owner_id, source_cell, 1, String(), context, exile_stack, resolution)) {
		resolution.supported = false;
	}
	return resolution;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::discard_locked_cards(
	NativeState &value,
	const EventGroup &group,
	const std::vector<int32_t> &locked_card_indices,
	const EventContext &event_context,
	const ActionContext &action_context,
	ActionExecutionState &execution_state,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	execution_state.last_discard_batch_size = 0;
	struct DiscardRecord {
		int32_t card_index = -1;
		int32_t logical_hand_index = -1;
		int32_t hand_slot_index = -1;
	};
	std::vector<int32_t> candidates;
	int32_t owner_id = 0;
	for (const int32_t card_index : locked_card_indices) {
		int32_t zone = -1;
		int32_t candidate_owner = 0;
		int32_t logical_index = -1;
		if (!locate_card(value, card_index, zone, candidate_owner, logical_index) || zone != 1) continue;
		if (owner_id == 0) owner_id = candidate_owner;
		if (candidate_owner != owner_id) continue;
		candidates.push_back(card_index);
	}
	if (owner_id < 1 || owner_id > 2 || candidates.empty()) return ActionOutcome::NO_EFFECT;

	std::vector<int32_t> &hand = value.zones[owner_id - 1];
	std::vector<int32_t> &discard_pile = value.zones[owner_id + 3];
	const int32_t previous_hand_size = static_cast<int32_t>(hand.size());
	const int32_t discard_size_before = static_cast<int32_t>(discard_pile.size());
	const StringName source_instance_id = (
		action_context.ability_source_card_index >= 0
		? value.card_instance_ids[action_context.ability_source_card_index]
		: StringName()
	);
	const StringName batch_id = StringName(
		String("discard:")
		+ String(source_instance_id)
		+ ":" + String::num_int64(owner_id)
		+ ":" + String::num_int64(value.scalars[1])
		+ ":" + String::num_int64(discard_size_before)
	);
	std::vector<DiscardRecord> records;
	std::vector<int32_t> discarded_slots;
	for (const int32_t card_index : candidates) {
		int32_t zone = -1;
		int32_t current_owner = 0;
		int32_t logical_index = -1;
		if (
			!locate_card(value, card_index, zone, current_owner, logical_index)
			|| zone != 1
			|| current_owner != owner_id
			|| logical_index < 0
			|| logical_index >= static_cast<int32_t>(hand.size())
			|| hand[logical_index] != card_index
		) continue;
		DiscardRecord record;
		record.card_index = card_index;
		record.logical_hand_index = logical_index;
		record.hand_slot_index = value.card_hand_slots[card_index] >= 0
			? value.card_hand_slots[card_index]
			: logical_index;
		hand.erase(hand.begin() + logical_index);
		value.card_runtime_flags[card_index] &= static_cast<uint8_t>(~(1 << 7));
		value.card_hand_slots[card_index] = -1;
		discard_pile.push_back(card_index);
		records.push_back(record);
		discarded_slots.push_back(record.hand_slot_index);
	}
	execution_state.last_discard_batch_size = static_cast<int32_t>(records.size());
	if (records.empty()) return ActionOutcome::NO_EFFECT;

	int32_t source_cell = find_board_card(
		value,
		action_context.ability_source_card_index,
		action_context.ability_source_cell
	);
	if (source_cell < 0) source_cell = execution_state.current_source_cell;
	execution_state.current_source_cell = source_cell;
	for (const DiscardRecord &record : records) {
		Dictionary discarded;
		discarded["type"] = StringName("card_discarded");
		discarded["source_cell"] = source_cell;
		discarded["source_instance_id"] = source_instance_id;
		discarded["owner_id"] = owner_id;
		discarded["instance_id"] = value.card_instance_ids[record.card_index];
		discarded["zone"] = StringName("hand");
		discarded["logical_hand_index"] = record.logical_hand_index;
		discarded["hand_slot_index"] = record.hand_slot_index;
		discarded["discard_batch_id"] = batch_id;
		discarded["discard_batch_size"] = static_cast<int32_t>(records.size());
		if (include_presentation_payloads) {
			discarded["card"] = restore_runtime_card(value, record.card_index);
		}
		resolution.events.append(discarded);
	}

	std::sort(discarded_slots.begin(), discarded_slots.end());
	struct SlotMove {
		int32_t card_index = -1;
		int32_t from_slot = -1;
		int32_t to_slot = -1;
	};
	std::vector<SlotMove> slot_moves;
	for (const int32_t card_index : hand) {
		const int32_t from_slot = value.card_hand_slots[card_index];
		if (from_slot < 0) continue;
		const int32_t removed_before = static_cast<int32_t>(std::count_if(
			discarded_slots.begin(),
			discarded_slots.end(),
			[&](int32_t discarded_slot) { return discarded_slot < from_slot; }
		));
		const int32_t to_slot = from_slot - removed_before;
		if (to_slot == from_slot) continue;
		slot_moves.push_back({card_index, from_slot, to_slot});
		value.card_hand_slots[card_index] = to_slot;
	}
	std::sort(slot_moves.begin(), slot_moves.end(), [](const SlotMove &left, const SlotMove &right) {
		return left.from_slot < right.from_slot;
	});
	if (!slot_moves.empty()) {
		Array moves;
		for (const SlotMove &move : slot_moves) {
			Dictionary move_payload;
			move_payload["instance_id"] = value.card_instance_ids[move.card_index];
			move_payload["from_slot"] = move.from_slot;
			move_payload["to_slot"] = move.to_slot;
			moves.append(move_payload);
		}
		Dictionary shifted;
		shifted["type"] = StringName("hand_cards_shifted");
		shifted["source_cell"] = source_cell;
		shifted["source_instance_id"] = source_instance_id;
		shifted["owner_id"] = owner_id;
		shifted["moves"] = moves;
		resolution.events.append(shifted);
	}
	Resolution hand_change = resolve_difficulty_hand_change(
		value,
		owner_id,
		previous_hand_size,
		static_cast<int32_t>(hand.size()),
		source_cell,
		exile_stack
	);
	if (!hand_change.supported) {
		resolution.reason = hand_change.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	append_resolution(resolution, hand_change);

	for (const DiscardRecord &record : records) {
		int32_t trigger_zone = -1;
		int32_t trigger_owner = 0;
		int32_t trigger_logical_index = -1;
		if (!locate_card(
			value,
			record.card_index,
			trigger_zone,
			trigger_owner,
			trigger_logical_index
		)) continue;
		EventContext discard_context = event_context;
		discard_context.ability_source_cell = action_context.ability_source_cell;
		discard_context.ability_source_zone = action_context.ability_source_zone;
		discard_context.ability_source_logical_index = action_context.ability_source_logical_index;
		discard_context.ability_source_card_index = action_context.ability_source_card_index;
		discard_context.ability_source_owner = action_context.ability_source_owner;
		discard_context.trigger_cell = -1;
		discard_context.trigger_card_index = record.card_index;
		discard_context.trigger_owner = owner_id;
		discard_context.trigger_zone = trigger_zone;
		discard_context.trigger_logical_index = trigger_logical_index;
		discard_context.discard_owner = owner_id;
		discard_context.discard_batch_id = batch_id;
		discard_context.discard_batch_size = static_cast<int32_t>(records.size());
		Resolution after_discard = resolve_event(
			value,
			StringName("card_after_discarded"),
			discard_context,
			exile_stack
		);
		if (!after_discard.supported) {
			resolution.reason = after_discard.reason;
			return ActionOutcome::UNSUPPORTED;
		}
		resolution.events.append_array(after_discard.events);
		resolution.captures.append_array(after_discard.captures);
		resolution.exiles.append_array(after_discard.exiles);
	}

	EventContext batch_context;
	batch_context.ability_source_cell = action_context.ability_source_cell;
	batch_context.ability_source_zone = action_context.ability_source_zone;
	batch_context.ability_source_logical_index = action_context.ability_source_logical_index;
	batch_context.ability_source_card_index = action_context.ability_source_card_index;
	batch_context.ability_source_owner = action_context.ability_source_owner;
	batch_context.discard_owner = owner_id;
	batch_context.discard_batch_id = batch_id;
	batch_context.discard_batch_size = static_cast<int32_t>(records.size());
	Resolution batch_finished = resolve_event(
		value,
		StringName("discard_batch_finished"),
		batch_context,
		exile_stack
	);
	if (!batch_finished.supported) {
		resolution.reason = batch_finished.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	resolution.events.append_array(batch_finished.events);
	resolution.captures.append_array(batch_finished.captures);
	resolution.exiles.append_array(batch_finished.exiles);
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::transform_card(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	const ActionExecutionState &execution_state,
	Resolution &resolution
) const {
	int32_t target = -1;
	if (action.card_ref == CardRefOpcode::SELECTED_CARD) target = action_context.selected_card_index;
	else if (action.card_ref == CardRefOpcode::TRIGGER_CARD) target = event_context.trigger_card_index;
	else if (action.card_ref == CardRefOpcode::ABILITY_SOURCE) target = action_context.ability_source_card_index;
	else if (action.card_ref == CardRefOpcode::ATTACKER_CARD) target = event_context.attacker_card_index;
	else return ActionOutcome::UNSUPPORTED;
	if (target < 0) return ActionOutcome::NO_EFFECT;

	const FreshCardPrototype *prototype = nullptr;
	for (const FreshCardPrototype &candidate : value.fresh_card_prototypes) {
		if (candidate.card_id == action.card_id) {
			prototype = &candidate;
			break;
		}
	}
	if (prototype == nullptr) {
		resolution.reason = "Transform target has no reachable fresh-card prototype";
		return ActionOutcome::UNSUPPORTED;
	}
	if (
		prototype->active_ability_set_index < 0
		|| prototype->active_ability_set_index >= static_cast<int32_t>(compiled_ability_sets.size())
		|| !compiled_ability_sets[prototype->active_ability_set_index].declaration_valid
	) {
		resolution.reason = "Transform target has an invalid compiled ability set";
		return ActionOutcome::UNSUPPORTED;
	}

	int32_t zone = -1;
	int32_t owner_id = 0;
	int32_t logical_index = -1;
	if (!locate_card(value, target, zone, owner_id, logical_index)) return ActionOutcome::NO_EFFECT;
	const StringName old_card_id = value.card_ids[target];
	value.card_template_indices[target] = prototype->template_index;
	value.card_ids[target] = prototype->card_id;
	for (int32_t direction = 0; direction < 4; ++direction) {
		value.card_powers[target * 4 + direction] = prototype->powers[direction];
	}
	value.card_ki[target] = prototype->ki;
	value.card_active_ability_set_indices[target] = prototype->active_ability_set_index;
	value.card_runtime_abilities[target].clear();
	for (const int32_t compiled_ability_index : compiled_ability_sets[prototype->active_ability_set_index].ability_pool_indices) {
		RuntimeAbilityEntry entry;
		entry.compiled_ability_index = compiled_ability_index;
		entry.handle = value.next_ability_handle++;
		value.card_runtime_abilities[target].push_back(entry);
	}
	clear_runtime_suppression(value, target);
	uint8_t &reveal_code = value.card_reveal_codes[target];
	if (owner_id == 1 && reveal_code == 0) reveal_code = 1;
	else if (owner_id == 1 && reveal_code == 2) reveal_code = 4;
	else if (owner_id == 2 && reveal_code == 0) reveal_code = 2;
	else if (owner_id == 2 && reveal_code == 1) reveal_code = 3;

	Dictionary transformed;
	transformed["type"] = StringName("card_transformed");
	transformed["source_cell"] = execution_state.current_source_cell;
	transformed["source_instance_id"] = (
		action_context.ability_source_card_index >= 0
		? value.card_instance_ids[action_context.ability_source_card_index]
		: StringName()
	);
	transformed["target_cell"] = zone == 0 ? logical_index : -1;
	transformed["owner_id"] = owner_id;
	transformed["zone"] = (
		zone == 0 ? StringName("board")
		: (zone == 1 ? StringName("hand")
		: (zone == 2 ? StringName("deck")
		: (zone == 3 ? StringName("discard") : StringName("removed"))))
	);
	transformed["logical_index"] = logical_index;
	transformed["instance_id"] = value.card_instance_ids[target];
	transformed["old_card_id"] = old_card_id;
	transformed["card_id"] = prototype->card_id;
	if (include_presentation_payloads) {
		transformed["card"] = restore_runtime_card(value, target);
	}
	resolution.events.append(transformed);
	return ActionOutcome::APPLIED;
}

void DuelNativeCompactKernel::remove_ability_with_event(
	NativeState &value,
	int32_t card_index,
	uint64_t ability_handle,
	int32_t source_cell,
	int32_t source_card_index,
	int32_t target_cell,
	int32_t owner_id,
	Array &events
) const {
	const int32_t ability_index = find_runtime_ability_index(
		value,
		card_index,
		ability_handle
	);
	if (ability_index < 0) return;
	std::vector<RuntimeAbilityEntry> &entries = value.card_runtime_abilities[card_index];
	entries.erase(entries.begin() + ability_index);
	Dictionary event;
	event["type"] = StringName("ability_lost");
	event["source_instance_id"] = source_card_index >= 0 ? value.card_instance_ids[source_card_index] : StringName();
	event["source_cell"] = source_cell;
	event["target_cell"] = target_cell;
	event["owner_id"] = owner_id;
	event["instance_id"] = value.card_instance_ids[card_index];
	events.append(event);
}

void DuelNativeCompactKernel::clear_runtime_suppression(
	NativeState &value,
	int32_t card_index
) const {
	if (
		card_index < 0
		|| card_index >= static_cast<int32_t>(value.card_runtime_suppression_batches.size())
	) return;
	value.card_runtime_suppression_batches[card_index].clear();
	value.card_runtime_flags[card_index] &= static_cast<uint8_t>(~(1 << 6));
	value.card_suppression_set_indices[card_index] = -1;
}

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::consume_pending_hand_play_suppression(
	NativeState &value,
	int32_t card_index,
	int32_t owner_id,
	int32_t cell
) const {
	Resolution resolution;
	if (
		owner_id < 1
		|| owner_id > 2
		|| card_index < 0
		|| card_index >= static_cast<int32_t>(value.card_runtime_abilities.size())
		|| card_is_heart_method(value, card_index)
	) return resolution;
	const int32_t scalar_index = owner_id == 1 ? 8 : 9;
	if (value.scalars[scalar_index] <= 0) return resolution;
	value.scalars[scalar_index] -= 1;

	Dictionary consumed;
	consumed["type"] = StringName("non_retained_suppression_consumed");
	consumed["source_cell"] = cell;
	consumed["target_cell"] = cell;
	consumed["owner_id"] = owner_id;
	consumed["instance_id"] = value.card_instance_ids[card_index];
	consumed["pending_count"] = value.scalars[scalar_index];
	resolution.events.append(consumed);

	std::vector<RuntimeAbilityEntry> retained_entries;
	retained_entries.reserve(value.card_runtime_abilities[card_index].size());
	for (const RuntimeAbilityEntry &entry : value.card_runtime_abilities[card_index]) {
		const bool retained = (
			entry.compiled_ability_index >= 0
			&& entry.compiled_ability_index < static_cast<int32_t>(compiled_ability_pool.size())
			&& compiled_ability_pool[entry.compiled_ability_index].retained_on_flip
		);
		if (retained) {
			retained_entries.push_back(entry);
			continue;
		}
		Dictionary lost;
		lost["type"] = StringName("ability_lost");
		lost["source_instance_id"] = StringName();
		lost["source_cell"] = cell;
		lost["target_cell"] = cell;
		lost["owner_id"] = owner_id;
		lost["instance_id"] = value.card_instance_ids[card_index];
		lost["zone"] = StringName("board");
		lost["logical_index"] = cell;
		lost["permanent"] = true;
		resolution.events.append(lost);
	}
	value.card_runtime_abilities[card_index] = retained_entries;
	clear_runtime_suppression(value, card_index);
	return resolution;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::temporarily_remove_non_retained_abilities(
	NativeState &value,
	const ActionContext &action_context,
	int32_t source_cell,
	Resolution &resolution
) const {
	const int32_t card_index = action_context.action_subject_card_index;
	if (
		card_index < 0
		|| card_index >= static_cast<int32_t>(value.card_runtime_abilities.size())
	) return ActionOutcome::NO_EFFECT;
	int32_t zone = -1;
	int32_t owner_id = 0;
	int32_t logical_index = -1;
	if (
		!locate_card(value, card_index, zone, owner_id, logical_index)
		|| owner_id != action_context.action_subject_owner
	) return ActionOutcome::NO_EFFECT;

	RuntimeSuppressionBatch batch;
	batch.expires_after_turn = value.scalars[2];
	std::vector<RuntimeAbilityEntry> retained_entries;
	const std::vector<RuntimeAbilityEntry> active_entries = value.card_runtime_abilities[card_index];
	retained_entries.reserve(active_entries.size());
	for (size_t ability_index = 0; ability_index < active_entries.size(); ++ability_index) {
		const RuntimeAbilityEntry &entry = active_entries[ability_index];
		const bool retained = (
			entry.compiled_ability_index >= 0
			&& entry.compiled_ability_index < static_cast<int32_t>(compiled_ability_pool.size())
			&& compiled_ability_pool[entry.compiled_ability_index].retained_on_flip
		);
		if (retained) {
			retained_entries.push_back(entry);
			continue;
		}
		RuntimeSuppressionEntry suppressed_entry;
		suppressed_entry.original_index = static_cast<int32_t>(ability_index);
		suppressed_entry.compiled_ability_index = entry.compiled_ability_index;
		suppressed_entry.handle = entry.handle;
		batch.entries.push_back(suppressed_entry);

		const int32_t cell = zone == 0 ? logical_index : -1;
		Dictionary lost;
		lost["type"] = StringName("ability_lost");
		lost["source_instance_id"] = (
			action_context.ability_source_card_index >= 0
			&& action_context.ability_source_card_index
				< static_cast<int32_t>(value.card_instance_ids.size())
			? value.card_instance_ids[action_context.ability_source_card_index]
			: StringName()
		);
		lost["source_cell"] = source_cell;
		lost["target_cell"] = cell;
		lost["owner_id"] = owner_id;
		lost["instance_id"] = value.card_instance_ids[card_index];
		lost["zone"] = (
			zone == 0 ? StringName("board")
			: (zone == 1 ? StringName("hand")
			: (zone == 2 ? StringName("deck")
			: (zone == 3 ? StringName("discard") : StringName("removed"))))
		);
		lost["logical_index"] = logical_index;
		lost["temporary"] = true;
		resolution.events.append(lost);
	}
	if (batch.entries.empty()) return ActionOutcome::NO_EFFECT;
	value.card_runtime_abilities[card_index] = retained_entries;
	value.card_runtime_suppression_batches[card_index].push_back(batch);
	value.card_runtime_flags[card_index] |= static_cast<uint8_t>(1 << 6);
	value.card_suppression_set_indices[card_index] = -1;
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::restore_temporary_abilities(
	NativeState &value,
	int32_t completed_turn
) const {
	Resolution resolution;
	auto restore_card = [&](
		int32_t card_index,
		int32_t owner_id,
		const StringName &zone,
		int32_t logical_index
	) {
		if (
			card_index < 0
			|| card_index >= static_cast<int32_t>(value.card_runtime_suppression_batches.size())
		) return;
		const std::vector<RuntimeSuppressionBatch> batches =
			value.card_runtime_suppression_batches[card_index];
		if (batches.empty()) return;
		std::vector<RuntimeSuppressionBatch> remaining_batches;
		for (int32_t batch_index = static_cast<int32_t>(batches.size()) - 1; batch_index >= 0; --batch_index) {
			const RuntimeSuppressionBatch &batch = batches[batch_index];
			if (batch.expires_after_turn > completed_turn) {
				remaining_batches.insert(remaining_batches.begin(), batch);
				continue;
			}
			std::vector<RuntimeSuppressionEntry> entries = batch.entries;
			std::sort(entries.begin(), entries.end(), [](const RuntimeSuppressionEntry &left, const RuntimeSuppressionEntry &right) {
				return left.original_index < right.original_index;
			});
			std::vector<RuntimeAbilityEntry> &active = value.card_runtime_abilities[card_index];
			for (const RuntimeSuppressionEntry &entry : entries) {
				const int32_t insert_index = std::clamp(
					entry.original_index,
					0,
					static_cast<int32_t>(active.size())
				);
				RuntimeAbilityEntry restored_entry;
				restored_entry.compiled_ability_index = entry.compiled_ability_index;
				restored_entry.handle = entry.handle;
				active.insert(active.begin() + insert_index, restored_entry);

				const int32_t cell = zone == StringName("board") ? logical_index : -1;
				Dictionary gained;
				gained["type"] = StringName("ability_gained");
				gained["source_cell"] = cell;
				gained["target_cell"] = cell;
				gained["owner_id"] = owner_id;
				gained["instance_id"] = value.card_instance_ids[card_index];
				gained["zone"] = zone;
				gained["logical_index"] = logical_index;
				gained["temporary"] = true;
				resolution.events.append(gained);
			}
		}
		value.card_runtime_suppression_batches[card_index] = remaining_batches;
		if (remaining_batches.empty()) {
			clear_runtime_suppression(value, card_index);
		} else {
			value.card_runtime_flags[card_index] |= static_cast<uint8_t>(1 << 6);
		}
	};

	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		const int32_t card_index = value.board_card_indices[cell];
		if (card_index < 0) continue;
		restore_card(
			card_index,
			value.board_owners[cell],
			StringName("board"),
			static_cast<int32_t>(cell)
		);
	}
	for (int32_t owner_id : {1, 2}) {
		const std::array<std::pair<int32_t, StringName>, 4> zones = {{
			{owner_id - 1, StringName("hand")},
			{owner_id + 1, StringName("deck")},
			{owner_id + 3, StringName("discard")},
			{owner_id + 5, StringName("removed")},
		}};
		for (const auto &zone_entry : zones) {
			const std::vector<int32_t> &cards = value.zones[zone_entry.first];
			for (size_t logical_index = 0; logical_index < cards.size(); ++logical_index) {
				restore_card(
					cards[logical_index],
					owner_id,
					zone_entry.second,
					static_cast<int32_t>(logical_index)
				);
			}
		}
	}
	return resolution;
}

Array DuelNativeCompactKernel::materialize_suppression_batches(
	const NativeState &value,
	int32_t card_index
) const {
	Array batches;
	if (
		card_index < 0
		|| card_index >= static_cast<int32_t>(value.card_runtime_suppression_batches.size())
	) return batches;
	for (const RuntimeSuppressionBatch &batch : value.card_runtime_suppression_batches[card_index]) {
		Array entries;
		for (const RuntimeSuppressionEntry &entry : batch.entries) {
			if (
				entry.compiled_ability_index < 0
				|| entry.compiled_ability_index >= static_cast<int32_t>(ability_declaration_pool.size())
			) continue;
			Dictionary materialized_entry;
			materialized_entry["index"] = entry.original_index;
			materialized_entry["ability"] = ability_declaration_pool[entry.compiled_ability_index];
			entries.append(materialized_entry);
		}
		Dictionary materialized_batch;
		materialized_batch["expires_after_turn"] = batch.expires_after_turn;
		materialized_batch["entries"] = entries;
		batches.append(materialized_batch);
	}
	return batches;
}

bool DuelNativeCompactKernel::resolve_selector_source(
	const NativeState &value,
	const ActionContext &context,
	int32_t &zone,
	int32_t &owner,
	int32_t &logical_index
) const {
	int32_t live_zone = -1;
	int32_t live_owner = 0;
	int32_t live_index = -1;
	if (
		locate_card(
			value,
			context.ability_source_card_index,
			live_zone,
			live_owner,
			live_index
		)
		&& live_zone != 2
		&& live_zone != 4
	) {
		zone = live_zone;
		owner = live_owner;
		logical_index = live_index;
		return true;
	}
	if (context.ability_source_owner != 1 && context.ability_source_owner != 2) return false;
	zone = context.ability_source_zone;
	owner = context.ability_source_owner;
	logical_index = context.ability_source_logical_index;
	return zone >= 0;
}

bool DuelNativeCompactKernel::action_declarations_can_spend_ki(const Variant &value) const {
	if (value.get_type() != Variant::ARRAY) return false;
	const Array actions = value;
	for (int64_t index = 0; index < actions.size(); ++index) {
		const Variant action_value = actions[index];
		if (action_value.get_type() != Variant::DICTIONARY) continue;
		const Dictionary action = action_value;
		const StringName type = action.get("type", StringName());
		if (type == StringName("spend_ki")) return true;
		if (action_declarations_can_spend_ki(action.get("actions", Variant()))) return true;
	}
	return false;
}

bool DuelNativeCompactKernel::card_declarations_can_spend_ki(
	const NativeState &value,
	int32_t card_index
) const {
	if (card_index < 0 || card_index >= static_cast<int32_t>(value.card_runtime_abilities.size())) return false;
	for (const RuntimeAbilityEntry &entry : value.card_runtime_abilities[card_index]) {
		if (
			entry.compiled_ability_index < 0
			|| entry.compiled_ability_index >= static_cast<int32_t>(ability_declaration_pool.size())
			|| ability_declaration_pool[entry.compiled_ability_index].get_type() != Variant::DICTIONARY
		) continue;
		const Dictionary ability = ability_declaration_pool[entry.compiled_ability_index];
		const Variant activation_value = ability.get("activation", Variant());
		if (activation_value.get_type() == Variant::DICTIONARY) {
			const Dictionary activation = activation_value;
			if (
				action_declarations_can_spend_ki(activation.get("costs", Variant()))
				|| action_declarations_can_spend_ki(activation.get("actions", Variant()))
			) return true;
		}
		const Variant triggers_value = ability.get("triggers", Variant());
		if (triggers_value.get_type() != Variant::ARRAY) continue;
		const Array triggers = triggers_value;
		for (int64_t trigger_index = 0; trigger_index < triggers.size(); ++trigger_index) {
			if (triggers[trigger_index].get_type() != Variant::DICTIONARY) continue;
			const Dictionary trigger = triggers[trigger_index];
			if (action_declarations_can_spend_ki(trigger.get("actions", Variant()))) return true;
		}
	}
	return false;
}

bool DuelNativeCompactKernel::card_is_heart_method(
	const NativeState &value,
	int32_t card_index
) const {
	if (
		card_index < 0
		|| card_index >= static_cast<int32_t>(value.card_template_indices.size())
	) return false;
	const int32_t template_index = value.card_template_indices[card_index];
	if (template_index < 0 || template_index >= value.card_template_pool.size()) return false;
	const Variant template_value = value.card_template_pool[template_index];
	if (template_value.get_type() != Variant::DICTIONARY) return false;
	const Dictionary card_template = template_value;
	return String(card_template.get("weapon", String())) == String::utf8("心法");
}

bool DuelNativeCompactKernel::selector_conditions_match(
	const NativeState &value,
	int32_t candidate_card_index,
	int32_t candidate_zone,
	int32_t candidate_owner,
	int32_t candidate_logical_index,
	const CompiledSelector &selector,
	const ActionContext &context,
	bool &supported
) const {
	supported = true;
	if (!selector.declaration_valid || candidate_card_index < 0) {
		supported = false;
		return false;
	}
	int32_t source_zone = -1;
	int32_t source_owner = 0;
	int32_t source_index = -1;
	if (!resolve_selector_source(value, context, source_zone, source_owner, source_index)) return false;
	for (const CompiledSelectorCondition &condition : selector.conditions) {
		bool matched = false;
		switch (condition.opcode) {
			case SelectorConditionOpcode::IS_ALLY:
				matched = candidate_owner == source_owner;
				break;
			case SelectorConditionOpcode::IS_ENEMY:
				matched = candidate_owner != source_owner;
				break;
			case SelectorConditionOpcode::WEAPON_IS: {
				const int32_t template_index = value.card_template_indices[candidate_card_index];
				if (template_index < 0 || template_index >= value.card_template_pool.size()) break;
				const Dictionary card_template = value.card_template_pool[template_index];
				matched = String(card_template.get("weapon", String())) == condition.weapon;
				break;
			}
			case SelectorConditionOpcode::IS_NOT_SOURCE:
				matched = candidate_card_index != context.ability_source_card_index;
				break;
			case SelectorConditionOpcode::ADJACENT_TO_SOURCE:
				matched = (
					candidate_zone == 0 && source_zone == 0
					&& (
						neighbor_index(candidate_logical_index, 0) == source_index
						|| neighbor_index(candidate_logical_index, 1) == source_index
						|| neighbor_index(candidate_logical_index, 2) == source_index
						|| neighbor_index(candidate_logical_index, 3) == source_index
					)
				);
				break;
			case SelectorConditionOpcode::SURROUNDED_BY_ALLIES: {
				if (candidate_zone != 0 || source_zone != 0) break;
				int32_t neighbor_count = 0;
				matched = true;
				for (int32_t direction = 0; direction < 4; ++direction) {
					const int32_t cell = neighbor_index(candidate_logical_index, direction);
					if (cell < 0) continue;
					++neighbor_count;
					if (value.board_card_indices[cell] < 0 || value.board_owners[cell] != source_owner) {
						matched = false;
						break;
					}
				}
				matched = matched && neighbor_count > 0;
				break;
			}
			case SelectorConditionOpcode::ORIGINAL_OWNER_IS_SELF:
				matched = value.card_original_owners[candidate_card_index] == source_owner;
				break;
			case SelectorConditionOpcode::ORIGINAL_OWNER_IS_ENEMY:
				matched = value.card_original_owners[candidate_card_index] != source_owner;
				break;
			case SelectorConditionOpcode::FLIPPED_BY_CURRENT_ATTACK:
				for (const EventContext::AttackFlipRecord &record : context.attack_flips) {
					if (record.card_index == candidate_card_index && record.previous_owner != source_owner) {
						matched = true;
						break;
					}
				}
				break;
			case SelectorConditionOpcode::POWERS_CAN_CHANGE:
				matched = can_change_powers(value, candidate_card_index);
				break;
			case SelectorConditionOpcode::HAS_NONZERO_POWER:
				for (int32_t direction = 0; direction < 4; ++direction) {
					if (value.card_powers[candidate_card_index * 4 + direction] != 0) {
						matched = true;
						break;
					}
				}
				break;
			case SelectorConditionOpcode::IS_PREVIOUS_HAND_PLAY: {
				int32_t played_by = 0;
				if (condition.relative_owner == RelativeOwnerOpcode::ABILITY_SOURCE) played_by = source_owner;
				else if (condition.relative_owner == RelativeOwnerOpcode::OPPONENT_OF_ABILITY_SOURCE) played_by = other_owner(source_owner);
				else {
					supported = false;
					return false;
				}
				const Dictionary records = value.side_payload.get("last_hand_play_by_owner", Dictionary());
				const Variant record_value = records.get(played_by, Dictionary());
				if (record_value.get_type() == Variant::DICTIONARY) {
					const Dictionary record = record_value;
					matched = (
						static_cast<int32_t>(static_cast<int64_t>(record.get("played_by_owner_id", 0))) == played_by
						&& StringName(record.get("instance_id", StringName())) == value.card_instance_ids[candidate_card_index]
					);
				}
				break;
			}
			case SelectorConditionOpcode::CAN_SPEND_KI:
				matched = (
					card_effects_enabled(value, candidate_card_index, candidate_owner)
					&& card_declarations_can_spend_ki(value, candidate_card_index)
				);
				break;
			case SelectorConditionOpcode::CAN_TRANSFER_RESOURCE: {
				auto has_resource = [&](ResourceOpcode resource) {
					if (resource == ResourceOpcode::KI) return value.card_ki[candidate_card_index] >= condition.amount;
					if (resource == ResourceOpcode::POWERS) {
						if (!can_change_powers(value, candidate_card_index)) return false;
						for (int32_t direction = 0; direction < 4; ++direction) {
							if (value.card_powers[candidate_card_index * 4 + direction] > 0) return true;
						}
						return false;
					}
					return false;
				};
				if (condition.resource == ResourceOpcode::UNSUPPORTED || condition.fallback_resource == ResourceOpcode::UNSUPPORTED) {
					supported = false;
					return false;
				}
				matched = has_resource(condition.resource) || has_resource(condition.fallback_resource);
				break;
			}
			default:
				supported = false;
				return false;
		}
		if (!matched) return false;
	}
	return true;
}

std::vector<int32_t> DuelNativeCompactKernel::snapshot_selected_cards(
	const NativeState &value,
	const CompiledSelector &selector,
	const ActionContext &context,
	bool &supported
) const {
	std::vector<int32_t> selected;
	supported = selector.declaration_valid;
	if (!supported) return selected;
	int32_t source_zone = -1;
	int32_t source_owner = 0;
	int32_t source_index = -1;
	if (!resolve_selector_source(value, context, source_zone, source_owner, source_index)) return selected;
	std::vector<uint8_t> observed(value.card_instance_ids.size(), 0);
	auto consider = [&](int32_t card_index, int32_t zone, int32_t owner, int32_t logical_index) {
		if (card_index < 0 || card_index >= static_cast<int32_t>(observed.size()) || observed[card_index] != 0) return false;
		observed[card_index] = 1;
		bool condition_supported = true;
		if (!selector_conditions_match(value, card_index, zone, owner, logical_index, selector, context, condition_supported)) {
			if (!condition_supported) supported = false;
			return false;
		}
		selected.push_back(card_index);
		return selector.limit > 0 && static_cast<int32_t>(selected.size()) >= selector.limit;
	};
	bool reached_limit = false;
	for (const SelectorZoneOpcode zone : selector.zones) {
		if (!supported || reached_limit) break;
		if (zone == SelectorZoneOpcode::BOARD) {
			for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
				const int32_t card_index = value.board_card_indices[cell];
				if (card_index >= 0 && consider(card_index, 0, value.board_owners[cell], static_cast<int32_t>(cell))) {
					reached_limit = true;
					break;
				}
			}
			continue;
		}
		const int32_t first_owner = source_owner;
		const int32_t second_owner = other_owner(source_owner);
		for (const int32_t owner : {first_owner, second_owner}) {
			if (!supported || reached_limit) break;
			int32_t zone_index = -1;
			int32_t zone_kind = -1;
			if (zone == SelectorZoneOpcode::HAND) {
				zone_index = owner - 1;
				zone_kind = 1;
			} else if (zone == SelectorZoneOpcode::DISCARD) {
				zone_index = owner + 3;
				zone_kind = 3;
			} else if (zone == SelectorZoneOpcode::REMOVED) {
				zone_index = owner + 5;
				zone_kind = 4;
			}
			if (zone_index < 0 || zone_index >= static_cast<int32_t>(value.zones.size())) continue;
			const std::vector<int32_t> &cards = value.zones[zone_index];
			std::vector<int32_t> logical_indices(cards.size());
			for (size_t index = 0; index < cards.size(); ++index) logical_indices[index] = static_cast<int32_t>(index);
			if (zone == SelectorZoneOpcode::HAND) {
				std::stable_sort(logical_indices.begin(), logical_indices.end(), [&](int32_t first, int32_t second) {
					const int32_t first_slot = value.card_hand_slots[cards[first]] >= 0 ? value.card_hand_slots[cards[first]] : first;
					const int32_t second_slot = value.card_hand_slots[cards[second]] >= 0 ? value.card_hand_slots[cards[second]] : second;
					return first_slot == second_slot ? first < second : first_slot < second_slot;
				});
				if (selector.hand_right_to_left) std::reverse(logical_indices.begin(), logical_indices.end());
			}
			for (const int32_t logical_index : logical_indices) {
				if (consider(cards[logical_index], zone_kind, owner, logical_index)) {
					reached_limit = true;
					break;
				}
			}
		}
	}
	if (selector.required_count > 0 && static_cast<int32_t>(selected.size()) != selector.required_count) {
		selected.clear();
	}
	return selected;
}

void DuelNativeCompactKernel::assign_power_change_batch(
	const NativeState &value,
	Resolution &resolution,
	int64_t first_event_index,
	const EventGroup &group,
	const CompiledAction &action,
	const ActionContext &context,
	int32_t action_index
) const {
	auto event_is_protected = [&](int64_t event_index) {
		for (const auto &range : resolution.protected_power_batch_ranges) {
			if (event_index >= range.first && event_index < range.second) return true;
		}
		return false;
	};
	bool has_power_change = false;
	for (int64_t index = first_event_index; index < resolution.events.size(); ++index) {
		if (event_is_protected(index)) continue;
		const Variant event_value = resolution.events[index];
		if (event_value.get_type() == Variant::DICTIONARY) {
			const Dictionary event = event_value;
			if (StringName(event.get("type", StringName())) == StringName("powers_changed")) {
			has_power_change = true;
			break;
			}
		}
	}
	if (!has_power_change) return;
	const String suffix = (
		action.power_change_batch_group.is_empty()
		? String::num_int64(action_index)
		: String(action.power_change_batch_group)
	);
	const StringName batch_id = StringName(
		String(value.card_instance_ids[group.source_card_index]) + "|"
		+ String(context.event_id.is_empty() ? StringName("direct") : context.event_id) + "|"
		+ String::num_int64(context.discovery_ability_index) + "|"
		+ String::num_int64(context.trigger_index) + "|" + suffix
	);
	for (int64_t index = first_event_index; index < resolution.events.size(); ++index) {
		if (event_is_protected(index)) continue;
		const Variant event_value = resolution.events[index];
		if (event_value.get_type() != Variant::DICTIONARY) continue;
		Dictionary event = event_value;
		const StringName type = event.get("type", StringName());
		if (type == StringName("powers_changed") || type == StringName("card_exiled")) {
			event["power_change_batch_id"] = batch_id;
		}
	}
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::change_powers(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	int32_t source_cell,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	int32_t target_card_index = -1;
	int32_t expected_owner = 0;
	if (action.card_ref == CardRefOpcode::SELECTED_CARD) {
		target_card_index = action_context.selected_card_index;
		expected_owner = action_context.selected_card_owner != 0
			? action_context.selected_card_owner
			: action_context.action_subject_owner;
	} else if (action.card_ref == CardRefOpcode::ABILITY_SOURCE) {
		target_card_index = action_context.ability_source_card_index;
		expected_owner = action_context.ability_source_owner;
	} else if (action.card_ref == CardRefOpcode::TRIGGER_CARD) {
		target_card_index = event_context.trigger_card_index;
		expected_owner = event_context.trigger_owner;
	} else if (action.card_ref == CardRefOpcode::ATTACKER_CARD) {
		target_card_index = event_context.attacker_card_index;
		expected_owner = event_context.attacker_owner;
	} else {
		return ActionOutcome::UNSUPPORTED;
	}
	int32_t zone = -1;
	int32_t owner = 0;
	int32_t logical_index = -1;
	if (
		target_card_index < 0
		|| !locate_card(value, target_card_index, zone, owner, logical_index)
		|| zone == 2
		|| (expected_owner != 0 && owner != expected_owner)
		|| !can_change_powers(value, target_card_index)
	) return ActionOutcome::NO_EFFECT;

	int32_t amount = action.amount;
	if (action.amount_is_hand_count) {
		int32_t count_owner = 0;
		if (action.amount_owner == RelativeOwnerOpcode::CARD_CURRENT) {
			count_owner = owner;
		} else if (action.amount_owner == RelativeOwnerOpcode::ABILITY_SOURCE) {
			int32_t source_zone = -1;
			int32_t source_index = -1;
			if (
				!locate_card(value, action_context.ability_source_card_index, source_zone, count_owner, source_index)
				|| source_zone == 2
			) return ActionOutcome::NO_EFFECT;
		} else {
			return ActionOutcome::UNSUPPORTED;
		}
		amount = static_cast<int32_t>(value.zones[count_owner - 1].size());
	}
	if (amount == 0) {
		return action.amount_is_hand_count ? ActionOutcome::NO_EFFECT : ActionOutcome::UNSUPPORTED;
	}
	Array previous_powers;
	Array resulting_powers;
	bool all_zero = true;
	for (int32_t direction = 0; direction < 4; ++direction) {
		const int32_t previous = value.card_powers[target_card_index * 4 + direction];
		const int32_t resulting = std::max(0, previous + amount);
		previous_powers.append(previous);
		resulting_powers.append(resulting);
		value.card_powers[target_card_index * 4 + direction] = resulting;
		all_zero = all_zero && resulting == 0;
	}
	Dictionary event;
	event["type"] = StringName("powers_changed");
	event["source_cell"] = source_cell;
	event["target_cell"] = zone == 0 ? logical_index : -1;
	event["owner_id"] = owner;
	event["instance_id"] = value.card_instance_ids[target_card_index];
	event["ability_source_instance_id"] = value.card_instance_ids[group.source_card_index];
	event["previous_powers"] = previous_powers;
	event["powers"] = resulting_powers;
	event["amount"] = amount;
	event["change_reason"] = StringName("change_powers");
	event["zone"] = zone == 0 ? StringName("board") : (zone == 1 ? StringName("hand") : (zone == 3 ? StringName("discard") : StringName("removed")));
	event["logical_index"] = logical_index;
	resolution.events.append(event);
	if (amount < 0 && all_zero) {
		if (!exile_card(
			value,
			target_card_index,
			source_cell,
			group.source_card_index,
			target_card_index == group.source_card_index,
			StringName("power_reached_zero"),
			event_context,
			exile_stack,
			resolution,
			action_context.record_direct_board_changes
		)) return ActionOutcome::UNSUPPORTED;
	}
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::change_ki(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	int32_t source_cell,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	(void)group;
	(void)source_cell;
	(void)exile_stack;
	int32_t target = action_context.action_subject_card_index;
	int32_t expected_owner = action_context.action_subject_owner;
	if (action.card_ref_explicit) {
		if (action.card_ref == CardRefOpcode::SELECTED_CARD) {
			target = action_context.selected_card_index;
			expected_owner = action_context.selected_card_owner != 0
				? action_context.selected_card_owner
				: action_context.action_subject_owner;
		} else if (action.card_ref == CardRefOpcode::ABILITY_SOURCE) {
			target = action_context.ability_source_card_index;
			expected_owner = action_context.ability_source_owner;
		} else if (action.card_ref == CardRefOpcode::TRIGGER_CARD) {
			target = event_context.trigger_card_index;
			expected_owner = event_context.trigger_owner;
		} else if (action.card_ref == CardRefOpcode::ATTACKER_CARD) {
			target = event_context.attacker_card_index;
			expected_owner = event_context.attacker_owner;
		} else return ActionOutcome::UNSUPPORTED;
	}
	int32_t zone = -1;
	int32_t owner = 0;
	int32_t logical_index = -1;
	if (
		target < 0 || !locate_card(value, target, zone, owner, logical_index) || zone == 2
		|| (expected_owner != 0 && owner != expected_owner)
	) return ActionOutcome::NO_EFFECT;
	const int32_t previous = value.card_ki[target];
	const int32_t delta = action.opcode == ActionOpcode::SPEND_KI ? -action.amount : action.amount;
	if (delta == 0 || previous + delta < 0) return ActionOutcome::NO_EFFECT;
	value.card_ki[target] = previous + delta;
	const int32_t current_cell = zone == 0 ? logical_index : -1;
	Dictionary event;
	event["type"] = StringName("ki_changed");
	event["source_cell"] = current_cell;
	event["target_cell"] = current_cell;
	event["owner_id"] = owner;
	event["instance_id"] = value.card_instance_ids[target];
	event["previous_ki"] = previous;
	event["ki"] = value.card_ki[target];
	event["change_reason"] = !action.change_reason.is_empty()
		? action.change_reason
		: (action.opcode == ActionOpcode::SPEND_KI ? StringName("spend_ki") : StringName("gain_ki"));
	event["zone"] = zone == 0 ? StringName("board") : (zone == 1 ? StringName("hand") : (zone == 3 ? StringName("discard") : StringName("removed")));
	event["logical_index"] = logical_index;
	resolution.events.append(event);
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::flip_action_subject(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	(void)event_context;
	const int32_t target = action_context.action_subject_card_index;
	const int32_t target_cell = find_board_card(value, target, action_context.action_subject_logical_index);
	if (target_cell < 0 || value.board_owners[target_cell] != action_context.action_subject_owner) return ActionOutcome::NO_EFFECT;
	int32_t new_owner = 0;
	if (action.new_owner == RelativeOwnerOpcode::ABILITY_SOURCE) new_owner = action_context.ability_source_owner;
	else if (action.new_owner == RelativeOwnerOpcode::OPPONENT_OF_ABILITY_SOURCE) new_owner = other_owner(action_context.ability_source_owner);
	else return ActionOutcome::UNSUPPORTED;
	if (new_owner == value.board_owners[target_cell]) return ActionOutcome::NO_EFFECT;
	EventContext flip_context;
	flip_context.trigger_cell = target_cell;
	flip_context.trigger_card_index = target;
	flip_context.trigger_owner = value.board_owners[target_cell];
	flip_context.trigger_was_on_board = true;
	flip_context.new_owner = new_owner;
	flip_context.flip_reason = StringName("ability_non_attack_flip");
	Resolution before = resolve_event(value, StringName("card_before_flipped"), flip_context, exile_stack);
	if (!before.supported) {
		resolution.reason = before.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	resolution.events.append_array(before.events);
	resolution.captures.append_array(before.captures);
	resolution.exiles.append_array(before.exiles);
	if (before.flip_prevented) {
		Dictionary prevented;
		prevented["type"] = StringName("card_flip_prevented");
		prevented["source_cell"] = -1;
		prevented["target_cell"] = target_cell;
		prevented["owner_id"] = flip_context.trigger_owner;
		prevented["new_owner_id"] = new_owner;
		prevented["instance_id"] = value.card_instance_ids[target];
		resolution.events.append(prevented);
		Resolution after_prevented = resolve_event(value, StringName("card_flip_prevented"), flip_context, exile_stack);
		if (!after_prevented.supported) {
			resolution.reason = after_prevented.reason;
			return ActionOutcome::UNSUPPORTED;
		}
		resolution.events.append_array(after_prevented.events);
		resolution.captures.append_array(after_prevented.captures);
		resolution.exiles.append_array(after_prevented.exiles);
		return ActionOutcome::APPLIED;
	}
	Resolution flipped;
	if (!flip_card(
		value,
		-1,
		-1,
		target_cell,
		target,
		new_owner,
		flip_context,
		exile_stack,
		flipped,
		action_context.record_direct_board_changes
	)) {
		resolution.reason = flipped.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	resolution.events.append_array(flipped.events);
	resolution.captures.append_array(flipped.captures);
	resolution.exiles.append_array(flipped.exiles);
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::grant_ability_to_subject(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const ActionContext &action_context,
	int32_t event_source_card_index,
	int32_t source_cell,
	Resolution &resolution
) const {
	if (
		action.granted_ability_index < 0
		|| action.granted_ability_index >= static_cast<int32_t>(compiled_ability_pool.size())
	) {
		resolution.reason = String("Granted native ability index is invalid: ")
			+ String::num_int64(action.granted_ability_index);
		return ActionOutcome::UNSUPPORTED;
	}
	if (
		event_source_card_index < 0
		|| event_source_card_index >= static_cast<int32_t>(value.card_instance_ids.size())
	) {
		resolution.reason = String("Granted ability event source index is invalid: ")
			+ String::num_int64(event_source_card_index);
		return ActionOutcome::UNSUPPORTED;
	}
	const int32_t target = action_context.action_subject_card_index;
	int32_t zone = -1;
	int32_t owner = 0;
	int32_t logical_index = -1;
	if (
		target < 0 || !locate_card(value, target, zone, owner, logical_index) || zone == 2
		|| owner != action_context.action_subject_owner
	) return ActionOutcome::NO_EFFECT;
	std::vector<RuntimeAbilityEntry> &entries = value.card_runtime_abilities[target];
	for (const RuntimeAbilityEntry &entry : entries) {
		if (entry.compiled_ability_index == action.granted_ability_index) return ActionOutcome::NO_EFFECT;
	}
	if (compiled_ability_pool[action.granted_ability_index].has_activation) {
		entries.erase(std::remove_if(entries.begin(), entries.end(), [&](const RuntimeAbilityEntry &entry) {
			return compiled_ability_pool[entry.compiled_ability_index].has_activation;
		}), entries.end());
	}
	RuntimeAbilityEntry entry;
	entry.compiled_ability_index = action.granted_ability_index;
	entry.handle = value.next_ability_handle++;
	entries.push_back(entry);
	Dictionary event;
	event["type"] = StringName("ability_gained");
	event["source_cell"] = source_cell;
	event["source_instance_id"] = value.card_instance_ids[event_source_card_index];
	event["target_cell"] = zone == 0 ? logical_index : -1;
	event["owner_id"] = owner;
	event["instance_id"] = value.card_instance_ids[target];
	event["zone"] = zone == 0 ? StringName("board") : (zone == 1 ? StringName("hand") : (zone == 3 ? StringName("discard") : StringName("removed")));
	event["logical_index"] = logical_index;
	resolution.events.append(event);
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::execute_actions(
	NativeState &value,
	const EventGroup &group,
	const std::vector<CompiledAction> &actions,
	const EventContext &event_context,
	const ActionContext &action_context,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution,
	bool defer_power_change_batch
) const {
	ActionExecutionState execution_state;
	execution_state.current_source_cell = group.source_cell;
	return execute_actions_with_state(
		value,
		group,
		actions,
		event_context,
		action_context,
		execution_state,
		exile_stack,
		resolution,
		defer_power_change_batch
	);
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::execute_actions_with_state(
	NativeState &value,
	const EventGroup &group,
	const std::vector<CompiledAction> &actions,
	const EventContext &event_context,
	const ActionContext &action_context,
	ActionExecutionState &execution_state,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution,
	bool defer_power_change_batch
) const {
	ActionOutcome aggregate = ActionOutcome::NO_EFFECT;
	for (size_t action_index = 0; action_index < actions.size(); ++action_index) {
		const CompiledAction &action = actions[action_index];
		const int64_t first_event_index = resolution.events.size();
		ActionOutcome outcome = execute_action(
			value,
			group,
			action,
			event_context,
			action_context,
			execution_state,
			exile_stack,
			resolution
		);
		const int64_t direct_event_end = resolution.events.size();
		if (
			direct_event_end > first_event_index
			&& (
				action.opcode == ActionOpcode::ATTACK_TRIGGER_CARD
				|| action.opcode == ActionOpcode::STANDARD_ATTACK_WITH_SELF
				|| action.opcode == ActionOpcode::STANDARD_ATTACK_WITH_CARD
				|| action.opcode == ActionOpcode::FLIP_SELF
				|| action.opcode == ActionOpcode::SUMMON_CARD
				|| action.opcode == ActionOpcode::RESUMMON_CARD_IN_PLACE
			)
		) {
			resolution.protected_power_batch_ranges.push_back({
				first_event_index,
				direct_event_end,
			});
		}
		for (int64_t event_index = first_event_index;
			action.opcode != ActionOpcode::DISTRIBUTE_KI && event_index < direct_event_end;
			++event_index
		) {
			const Variant event_value = resolution.events[event_index];
			if (event_value.get_type() != Variant::DICTIONARY) continue;
			const Dictionary ki_event = event_value;
			if (StringName(ki_event.get("type", StringName())) != StringName("ki_changed")) continue;
			EventContext ki_context;
			ki_context.trigger_cell = static_cast<int32_t>(static_cast<int64_t>(ki_event.get("target_cell", -1)));
			const StringName instance_id = ki_event.get("instance_id", StringName());
			for (size_t card_index = 0; card_index < value.card_instance_ids.size(); ++card_index) {
				if (value.card_instance_ids[card_index] == instance_id) {
					ki_context.trigger_card_index = static_cast<int32_t>(card_index);
					break;
				}
			}
			ki_context.trigger_owner = static_cast<int32_t>(static_cast<int64_t>(ki_event.get("owner_id", 0)));
			ki_context.previous_ki = static_cast<int32_t>(static_cast<int64_t>(ki_event.get("previous_ki", 0)));
			ki_context.ki = static_cast<int32_t>(static_cast<int64_t>(ki_event.get("ki", -1)));
			Resolution ki_resolution = resolve_event(value, StringName("card_ki_changed"), ki_context, exile_stack);
			if (!ki_resolution.supported) {
				resolution.reason = ki_resolution.reason;
				return ActionOutcome::UNSUPPORTED;
			}
			const int64_t ki_resolution_start = resolution.events.size();
			append_resolution(resolution, ki_resolution);
			const int64_t ki_resolution_end = resolution.events.size();
			if (ki_resolution_end > ki_resolution_start) {
				resolution.protected_power_batch_ranges.push_back({
					ki_resolution_start,
					ki_resolution_end,
				});
			}
		}
		if (!defer_power_change_batch) {
			assign_power_change_batch(
				value,
				resolution,
				first_event_index,
				group,
				action,
				action_context,
				static_cast<int32_t>(action_index)
			);
		}
		if (outcome == ActionOutcome::UNSUPPORTED) {
			if (resolution.reason.is_empty()) {
				resolution.reason = String("Unsupported compiled action opcode ")
					+ String::num_int64(static_cast<int64_t>(action.opcode))
					+ String(" type=") + String(action.declaration_type);
			}
			return outcome;
		}
		if (outcome == ActionOutcome::INVALID_CONTEXT) return outcome;
		if (outcome == ActionOutcome::NO_EFFECT && action.stop_rule_on_invalid_context) {
			return ActionOutcome::INVALID_CONTEXT;
		}
		if (outcome == ActionOutcome::APPLIED) aggregate = ActionOutcome::APPLIED;
	}
	return aggregate;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::execute_for_each_selected_card(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	ActionExecutionState &execution_state,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	bool selection_supported = true;
	const std::vector<int32_t> selected = snapshot_selected_cards(
		value,
		action.selector,
		action_context,
		selection_supported
	);
	if (!selection_supported) return ActionOutcome::UNSUPPORTED;
	ActionOutcome aggregate = ActionOutcome::NO_EFFECT;
	for (const int32_t selected_card_index : selected) {
		int32_t zone = -1;
		int32_t owner = 0;
		int32_t logical_index = -1;
		if (!locate_card(value, selected_card_index, zone, owner, logical_index) || zone == 2) continue;
		bool condition_supported = true;
		if (!selector_conditions_match(
			value,
			selected_card_index,
			zone,
			owner,
			logical_index,
			action.selector,
			action_context,
			condition_supported
		)) {
			if (!condition_supported) return ActionOutcome::UNSUPPORTED;
			continue;
		}
		ActionContext nested_context = action_context;
		nested_context.action_subject_card_index = selected_card_index;
		nested_context.action_subject_owner = owner;
		nested_context.action_subject_zone = zone;
		nested_context.action_subject_logical_index = logical_index;
		nested_context.selected_card_index = selected_card_index;
		nested_context.selected_card_owner = owner;
		nested_context.selected_card_zone = zone;
		nested_context.selected_card_logical_index = logical_index;
		ActionExecutionState nested_execution_state = execution_state;
		nested_execution_state.current_source_cell = zone == 0 ? logical_index : -1;
		const ActionOutcome outcome = execute_actions_with_state(
			value,
			group,
			action.child_actions,
			event_context,
			nested_context,
			nested_execution_state,
			exile_stack,
			resolution,
			true
		);
		if (outcome == ActionOutcome::UNSUPPORTED || outcome == ActionOutcome::INVALID_CONTEXT) return outcome;
		if (outcome == ActionOutcome::APPLIED) aggregate = ActionOutcome::APPLIED;
	}
	return aggregate;
}

bool DuelNativeCompactKernel::action_conditions_match(
	const NativeState &value,
	const std::vector<CompiledCondition> &conditions,
	const ActionContext &action_context,
	const ActionExecutionState &execution_state,
	bool &supported
) const {
	supported = true;
	if (conditions.empty()) return false;
	for (const CompiledCondition &condition : conditions) {
		bool matched = false;
		switch (condition.opcode) {
			case ConditionOpcode::SOURCE_OWNER_HAND_EMPTY:
				if (
					action_context.ability_source_owner < 1
					|| action_context.ability_source_owner > 2
				) {
					supported = false;
					return false;
				}
				matched = value.zones[action_context.ability_source_owner - 1].empty();
				break;
			case ConditionOpcode::LAST_DISCARD_BATCH_SIZE_AT_LEAST:
				matched = execution_state.last_discard_batch_size >= condition.amount;
				break;
			default:
				supported = false;
				return false;
		}
		if (!matched) return false;
	}
	return true;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::execute_action(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	ActionExecutionState &execution_state,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	if (!action.declaration_valid) return ActionOutcome::UNSUPPORTED;
	const int32_t action_source_cell = execution_state.current_source_cell;
	switch (action.opcode) {
		case ActionOpcode::DRAW_CARDS: {
			EventContext draw_context = event_context;
			draw_context.ability_source_cell = action_context.ability_source_cell;
			draw_context.ability_source_zone = action_context.ability_source_zone;
			draw_context.ability_source_logical_index = action_context.ability_source_logical_index;
			draw_context.ability_source_card_index = action_context.ability_source_card_index;
			draw_context.ability_source_owner = action_context.ability_source_owner;
			return draw_cards(
				value,
				action_context.action_subject_owner,
				action_source_cell,
				action.amount,
				action.weapon,
				draw_context,
				exile_stack,
				resolution
			)
				? ActionOutcome::APPLIED
				: ActionOutcome::UNSUPPORTED;
		}
		case ActionOpcode::DISCARD_CARD: {
			execution_state.last_discard_batch_size = 0;
			int32_t target = -1;
			if (action.card_ref == CardRefOpcode::SELECTED_CARD) target = action_context.selected_card_index;
			else if (action.card_ref == CardRefOpcode::TRIGGER_CARD) target = event_context.trigger_card_index;
			else if (action.card_ref == CardRefOpcode::ABILITY_SOURCE) target = action_context.ability_source_card_index;
			else if (action.card_ref == CardRefOpcode::ATTACKER_CARD) target = event_context.attacker_card_index;
			else return ActionOutcome::UNSUPPORTED;
			return discard_locked_cards(
				value,
				group,
				target >= 0 ? std::vector<int32_t>{target} : std::vector<int32_t>{},
				event_context,
				action_context,
				execution_state,
				exile_stack,
				resolution
			);
		}
		case ActionOpcode::DISCARD_CARDS: {
			execution_state.last_discard_batch_size = 0;
			bool selection_supported = true;
			const std::vector<int32_t> selected = snapshot_selected_cards(
				value,
				action.selector,
				action_context,
				selection_supported
			);
			if (!selection_supported) return ActionOutcome::UNSUPPORTED;
			return discard_locked_cards(
				value,
				group,
				selected,
				event_context,
				action_context,
				execution_state,
				exile_stack,
				resolution
			);
		}
		case ActionOpcode::EXILE_SELF:
			return exile_card(value, action_context.action_subject_card_index, action_source_cell, action_context.action_subject_card_index, true, StringName("ability_exile_self"), event_context, exile_stack, resolution, action_context.record_direct_board_changes)
				? ActionOutcome::APPLIED
				: ActionOutcome::UNSUPPORTED;
		case ActionOpcode::EXILE_CARD: {
			int32_t target = -1;
			if (action.card_ref == CardRefOpcode::SELECTED_CARD) target = action_context.selected_card_index;
			else if (action.card_ref == CardRefOpcode::TRIGGER_CARD) target = event_context.trigger_card_index;
			else if (action.card_ref == CardRefOpcode::ABILITY_SOURCE) target = action_context.ability_source_card_index;
			else if (action.card_ref == CardRefOpcode::ATTACKER_CARD) target = event_context.attacker_card_index;
			else return ActionOutcome::UNSUPPORTED;
			if (target < 0) return ActionOutcome::NO_EFFECT;
			return exile_card(value, target, action_source_cell, action_context.ability_source_card_index, target == action_context.ability_source_card_index, StringName("ability_exile_card"), event_context, exile_stack, resolution, action_context.record_direct_board_changes)
				? ActionOutcome::APPLIED
				: ActionOutcome::UNSUPPORTED;
		}
		case ActionOpcode::PREVENT_TRIGGER_FLIP:
			if (event_context.trigger_card_index < 0 || event_context.new_owner < 1 || event_context.new_owner > 2) {
				return ActionOutcome::NO_EFFECT;
			}
			resolution.flip_prevented = true;
			return ActionOutcome::APPLIED;
		case ActionOpcode::REMOVE_THIS_ABILITY: {
			const int32_t current_cell = find_board_card(value, group.source_card_index, group.source_cell);
			if (current_cell >= 0 && value.board_owners[current_cell] == group.source_owner) {
				const int32_t current_ability_index = find_runtime_ability_index(
					value,
					group.source_card_index,
					group.ability_handle,
					group.ability_index
				);
				if (current_ability_index < 0) return ActionOutcome::NO_EFFECT;
				remove_ability_with_event(value, group.source_card_index, group.ability_handle, current_cell, group.source_card_index, current_cell, group.source_owner, resolution.events);
				return ActionOutcome::APPLIED;
			}
			return ActionOutcome::NO_EFFECT;
		}
		case ActionOpcode::FOR_EACH_SELECTED_CARD:
			return execute_for_each_selected_card(value, group, action, event_context, action_context, execution_state, exile_stack, resolution);
		case ActionOpcode::IF: {
			bool conditions_supported = true;
			if (!action_conditions_match(
				value,
				action.conditions,
				action_context,
				execution_state,
				conditions_supported
			)) {
				return conditions_supported ? ActionOutcome::NO_EFFECT : ActionOutcome::UNSUPPORTED;
			}
			return execute_actions_with_state(
				value,
				group,
				action.child_actions,
				event_context,
				action_context,
				execution_state,
				exile_stack,
				resolution
			);
		}
		case ActionOpcode::CHANGE_POWERS:
			return change_powers(value, group, action, event_context, action_context, action_source_cell, exile_stack, resolution);
		case ActionOpcode::GAIN_KI:
		case ActionOpcode::SPEND_KI: {
			if (action.card_ref_explicit && action.card_ref == CardRefOpcode::LAST_SUMMONED_CARD) {
				const int32_t target = execution_state.last_summoned_card_index;
				int32_t zone = -1;
				int32_t owner = 0;
				int32_t logical_index = -1;
				if (target < 0 || !locate_card(value, target, zone, owner, logical_index)) {
					return ActionOutcome::NO_EFFECT;
				}
				CompiledAction selected_action = action;
				selected_action.card_ref = CardRefOpcode::SELECTED_CARD;
				ActionContext selected_context = action_context;
				selected_context.selected_card_index = target;
				selected_context.selected_card_owner = owner;
				selected_context.action_subject_owner = owner;
				return change_ki(
					value,
					group,
					selected_action,
					event_context,
					selected_context,
					action_source_cell,
					exile_stack,
					resolution
				);
			}
			return change_ki(value, group, action, event_context, action_context, action_source_cell, exile_stack, resolution);
		}
		case ActionOpcode::FLIP_SELF:
			return flip_action_subject(value, group, action, event_context, action_context, exile_stack, resolution);
		case ActionOpcode::GRANT_TRIGGER_CARD_ABILITY: {
			if (event_context.trigger_card_index < 0) return ActionOutcome::NO_EFFECT;
			ActionContext trigger_context = action_context;
			trigger_context.action_subject_card_index = event_context.trigger_card_index;
			trigger_context.action_subject_owner = event_context.trigger_owner;
			trigger_context.action_subject_zone = event_context.trigger_zone;
			trigger_context.action_subject_logical_index = event_context.trigger_logical_index;
			return grant_ability_to_subject(
				value,
				group,
				action,
				trigger_context,
				action_context.action_subject_card_index,
				action_source_cell,
				resolution
			);
		}
		case ActionOpcode::GRANT_ABILITY_TO_SELF:
			return grant_ability_to_subject(
				value,
				group,
				action,
				action_context,
				action_context.action_subject_card_index,
				action_source_cell,
				resolution
			);
		case ActionOpcode::TRANSFORM_CARD:
			return transform_card(value, group, action, event_context, action_context, execution_state, resolution);
		case ActionOpcode::RETURN_CARD_TO_HAND:
			return return_card_to_hand(value, group, action, event_context, action_context, exile_stack, resolution);
		case ActionOpcode::SELF_SWAPPED_WITH_ABILITY_SOURCE:
			return swap_action_subject_with_ability_source(value, group, event_context, action_context, exile_stack, resolution);
		case ActionOpcode::SWAP_SELF_WITH_TRIGGER_CARD: {
			if (event_context.trigger_card_index < 0) return ActionOutcome::NO_EFFECT;
			ActionContext trigger_context = action_context;
			trigger_context.action_subject_card_index = event_context.trigger_card_index;
			trigger_context.action_subject_owner = event_context.trigger_owner;
			trigger_context.action_subject_zone = 0;
			trigger_context.action_subject_logical_index = event_context.trigger_cell;
			return swap_action_subject_with_ability_source(
				value,
				group,
				event_context,
				trigger_context,
				exile_stack,
				resolution
			);
		}
		case ActionOpcode::MOVE_SELF_TO_TARGET: {
			if (action_context.activation_target_kind != StringName("board_cell")) {
				return ActionOutcome::NO_EFFECT;
			}
			const int32_t target_cell = action_context.activation_target_index;
			const int32_t moving_card_index = action_context.action_subject_card_index;
			const int32_t moving_owner = action_context.action_subject_owner;
			if (
				target_cell < 0
				|| target_cell >= static_cast<int32_t>(value.board_card_indices.size())
				|| value.board_card_indices[target_cell] >= 0
			) return ActionOutcome::NO_EFFECT;
			const int32_t current_cell = find_board_card(
				value,
				moving_card_index,
				action_source_cell
			);
			if (
				current_cell != action_source_cell
				|| current_cell < 0
				|| value.board_owners[current_cell] != moving_owner
			) return ActionOutcome::NO_EFFECT;
			bool adjacent = false;
			for (int32_t direction = 0; direction < 4; ++direction) {
				if (neighbor_index(current_cell, direction) == target_cell) {
					adjacent = true;
					break;
				}
			}
			if (!adjacent) return ActionOutcome::NO_EFFECT;
			const ActionOutcome outcome = move_card_between_cells(
				value,
				current_cell,
				current_cell,
				target_cell,
				moving_card_index,
				moving_owner,
				true,
				exile_stack,
				resolution
			);
			if (outcome == ActionOutcome::APPLIED) {
				execution_state.current_source_cell = find_board_card(
					value,
					group.source_card_index,
					target_cell
				);
			}
			return outcome;
		}
		case ActionOpcode::SWAP_SELF_WITH_TARGET: {
			if (action_context.activation_target_kind != StringName("board_cell")) {
				return ActionOutcome::NO_EFFECT;
			}
			const int32_t target_cell = action_context.activation_target_index;
			const int32_t target_card_index = action_context.selected_card_index;
			const int32_t target_owner = action_context.selected_card_owner;
			if (
				target_cell < 0
				|| target_cell >= static_cast<int32_t>(value.board_card_indices.size())
				|| target_card_index < 0
				|| value.board_card_indices[target_cell] != target_card_index
				|| value.board_owners[target_cell] != target_owner
			) return ActionOutcome::NO_EFFECT;
			ActionContext target_context = action_context;
			target_context.action_subject_card_index = target_card_index;
			target_context.action_subject_owner = target_owner;
			target_context.action_subject_zone = 0;
			target_context.action_subject_logical_index = target_cell;
			const ActionOutcome outcome = swap_action_subject_with_ability_source(
				value,
				group,
				event_context,
				target_context,
				exile_stack,
				resolution
			);
			if (outcome == ActionOutcome::APPLIED) {
				execution_state.current_source_cell = find_board_card(
					value,
					group.source_card_index,
					target_cell
				);
			}
			return outcome;
		}
		case ActionOpcode::ATTACK_TRIGGER_CARD:
		case ActionOpcode::STANDARD_ATTACK_WITH_SELF:
		case ActionOpcode::STANDARD_ATTACK_WITH_CARD: {
			int32_t source_zone = -1;
			int32_t source_owner = 0;
			int32_t source_logical_index = -1;
			const int32_t attacker_card_index = action.opcode == ActionOpcode::STANDARD_ATTACK_WITH_CARD
				? resolve_action_card_reference(
					action.card_ref,
					event_context,
					action_context,
					execution_state
				)
				: action_context.action_subject_card_index;
			if (
				attacker_card_index < 0
				|| !locate_card(
					value,
					attacker_card_index,
					source_zone,
					source_owner,
					source_logical_index
				)
				|| source_zone != 0
				|| (
					action.opcode != ActionOpcode::STANDARD_ATTACK_WITH_CARD
					&& source_owner != action_context.action_subject_owner
				)
			) return ActionOutcome::NO_EFFECT;
			AttackRequest request;
			request.attacker_cell = source_logical_index;
			request.attacker_card_index = attacker_card_index;
			request.attacker_owner = source_owner;
			if (action.opcode == ActionOpcode::ATTACK_TRIGGER_CARD) {
				const int32_t target_cell = find_board_card(
					value,
					event_context.trigger_card_index,
					event_context.trigger_cell
				);
				if (target_cell != event_context.trigger_cell || target_cell < 0) {
					return ActionOutcome::NO_EFFECT;
				}
				request.targeted = true;
				request.locked_target_cell = target_cell;
				request.locked_target_card_index = event_context.trigger_card_index;
				request.locked_target_owner = value.board_owners[target_cell];
				request.reason = StringName("card_summoned_reaction");
			} else {
				request.repeat_attack = action.repeat_attack;
				request.reason = StringName("activated_ability");
				if (action.target_policy_specified) {
					request.requested_policy.specified = true;
					request.requested_policy.target_policy = action.target_policy;
				}
			}
			Resolution nested = resolve_attack_request(value, request, exile_stack);
			if (!nested.supported) {
				resolution.reason = nested.reason;
				return ActionOutcome::UNSUPPORTED;
			}
			const bool applied = resolution_has_output(nested);
			append_resolution(resolution, nested);
			return applied ? ActionOutcome::APPLIED : ActionOutcome::NO_EFFECT;
		}
		case ActionOpcode::MOVE_SELF_TO_FIRST_ADJACENT_EMPTY: {
			int32_t source_zone = -1;
			int32_t source_owner = 0;
			int32_t current_cell = -1;
			const int32_t moving_card_index = action_context.action_subject_card_index;
			if (
				moving_card_index < 0
				|| !locate_card(value, moving_card_index, source_zone, source_owner, current_cell)
				|| source_zone != 0
				|| source_owner != action_context.action_subject_owner
			) return ActionOutcome::NO_EFFECT;
			for (int32_t target_cell = 0; target_cell < static_cast<int32_t>(value.board_card_indices.size()); ++target_cell) {
				if (value.board_card_indices[target_cell] >= 0) continue;
				bool adjacent = false;
				for (int32_t direction = 0; direction < 4; ++direction) {
					if (neighbor_index(current_cell, direction) == target_cell) {
						adjacent = true;
						break;
					}
				}
				if (!adjacent) continue;
				const ActionOutcome outcome = move_card_between_cells(
					value,
					current_cell,
					current_cell,
					target_cell,
					moving_card_index,
					source_owner,
					true,
					exile_stack,
					resolution
				);
				if (outcome == ActionOutcome::APPLIED) {
					execution_state.current_source_cell = find_board_card(
						value,
						group.source_card_index,
						target_cell
					);
				}
				return outcome;
			}
			return ActionOutcome::NO_EFFECT;
		}
		case ActionOpcode::MOVE_SELF_TO_FIRST_EMPTY_BETWEEN_ENEMY: {
			int32_t source_zone = -1;
			int32_t source_owner = 0;
			int32_t current_cell = -1;
			const int32_t moving_card_index = action_context.action_subject_card_index;
			if (
				moving_card_index < 0
				|| !locate_card(value, moving_card_index, source_zone, source_owner, current_cell)
				|| source_zone != 0
				|| source_owner != action_context.action_subject_owner
			) return ActionOutcome::NO_EFFECT;
			for (int32_t middle_cell = 0; middle_cell < static_cast<int32_t>(value.board_card_indices.size()); ++middle_cell) {
				if (value.board_card_indices[middle_cell] >= 0) continue;
				for (int32_t direction = 0; direction < 4; ++direction) {
					if (neighbor_index(current_cell, direction) != middle_cell) continue;
					const int32_t far_cell = neighbor_index(middle_cell, direction);
					if (
						far_cell < 0
						|| value.board_card_indices[far_cell] < 0
						|| value.board_owners[far_cell] == source_owner
					) continue;
					const ActionOutcome outcome = move_card_between_cells(
						value,
						current_cell,
						current_cell,
						middle_cell,
						moving_card_index,
						source_owner,
						true,
						exile_stack,
						resolution
					);
					if (outcome == ActionOutcome::APPLIED) {
						execution_state.current_source_cell = find_board_card(value, group.source_card_index, middle_cell);
					}
					return outcome;
				}
			}
			return ActionOutcome::NO_EFFECT;
		}
		case ActionOpcode::TRANSFER_CARD_RESOURCE: {
			auto resolve_ref = [&](CardRefOpcode reference) -> int32_t {
				if (reference == CardRefOpcode::SELECTED_CARD) return action_context.selected_card_index;
				if (reference == CardRefOpcode::TRIGGER_CARD) return event_context.trigger_card_index;
				if (reference == CardRefOpcode::ABILITY_SOURCE) return action_context.ability_source_card_index;
				if (reference == CardRefOpcode::ATTACKER_CARD) return event_context.attacker_card_index;
				return -1;
			};
			const int32_t donor = resolve_ref(action.from_card_ref);
			const int32_t receiver = resolve_ref(action.to_card_ref);
			if (donor < 0 || receiver < 0 || donor == receiver) return ActionOutcome::NO_EFFECT;
			int32_t donor_zone = -1;
			int32_t donor_owner = 0;
			int32_t donor_index = -1;
			int32_t receiver_zone = -1;
			int32_t receiver_owner = 0;
			int32_t receiver_index = -1;
			if (
				!locate_card(value, donor, donor_zone, donor_owner, donor_index)
				|| !locate_card(value, receiver, receiver_zone, receiver_owner, receiver_index)
				|| donor_zone == 2
				|| receiver_zone == 2
			) return ActionOutcome::NO_EFFECT;
			auto can_donate = [&](ResourceOpcode resource) {
				if (resource == ResourceOpcode::KI) return value.card_ki[donor] >= action.amount;
				if (resource != ResourceOpcode::POWERS || !can_change_powers(value, donor)) return false;
				for (int32_t direction = 0; direction < 4; ++direction) {
					if (value.card_powers[donor * 4 + direction] > 0) return true;
				}
				return false;
			};
			auto can_receive = [&](ResourceOpcode resource) {
				return resource == ResourceOpcode::KI
					|| (resource == ResourceOpcode::POWERS && can_change_powers(value, receiver));
			};
			for (const ResourceOpcode resource : {action.resource, action.fallback_resource}) {
				if (!can_donate(resource)) continue;
				if (!can_receive(resource)) return ActionOutcome::NO_EFFECT;
				if (resource == ResourceOpcode::KI) {
					CompiledAction donor_action;
					donor_action.opcode = ActionOpcode::SPEND_KI;
					donor_action.card_ref_explicit = true;
					donor_action.card_ref = CardRefOpcode::SELECTED_CARD;
					donor_action.amount = action.amount;
					donor_action.change_reason = StringName("transfer_card_resource");
					ActionContext donor_context = action_context;
					donor_context.selected_card_index = donor;
					donor_context.selected_card_owner = donor_owner;
					donor_context.action_subject_owner = donor_owner;
					const ActionOutcome donor_outcome = change_ki(
						value, group, donor_action, event_context, donor_context,
						action_source_cell, exile_stack, resolution
					);
					if (donor_outcome != ActionOutcome::APPLIED) return donor_outcome;
					CompiledAction receiver_action = donor_action;
					receiver_action.opcode = ActionOpcode::GAIN_KI;
					ActionContext receiver_context = action_context;
					receiver_context.selected_card_index = receiver;
					receiver_context.selected_card_owner = receiver_owner;
					receiver_context.action_subject_owner = receiver_owner;
					return change_ki(
						value, group, receiver_action, event_context, receiver_context,
						action_source_cell, exile_stack, resolution
					);
				}
				CompiledAction donor_action;
				donor_action.opcode = ActionOpcode::CHANGE_POWERS;
				donor_action.card_ref = CardRefOpcode::SELECTED_CARD;
				donor_action.amount = -action.amount;
				ActionContext donor_context = action_context;
				donor_context.selected_card_index = donor;
				donor_context.selected_card_owner = donor_owner;
				donor_context.action_subject_owner = donor_owner;
				const ActionOutcome donor_outcome = change_powers(
					value, group, donor_action, event_context, donor_context,
					action_source_cell, exile_stack, resolution
				);
				if (donor_outcome != ActionOutcome::APPLIED) return donor_outcome;
				CompiledAction receiver_action = donor_action;
				receiver_action.amount = action.amount;
				ActionContext receiver_context = action_context;
				receiver_context.selected_card_index = receiver;
				receiver_context.selected_card_owner = receiver_owner;
				receiver_context.action_subject_owner = receiver_owner;
				return change_powers(
					value, group, receiver_action, event_context, receiver_context,
					action_source_cell, exile_stack, resolution
				);
			}
			return ActionOutcome::NO_EFFECT;
		}
		case ActionOpcode::DISTRIBUTE_KI: {
			const int32_t distributor = resolve_action_card_reference(
				action.from_card_ref,
				event_context,
				action_context,
				execution_state
			);
			int32_t distributor_zone = -1;
			int32_t distributor_owner = 0;
			int32_t distributor_logical_index = -1;
			if (
				distributor < 0
				|| !locate_card(
					value,
					distributor,
					distributor_zone,
					distributor_owner,
					distributor_logical_index
				)
				|| distributor_zone == 2
			) return ActionOutcome::NO_EFFECT;

			ActionContext selector_context = action_context;
			selector_context.ability_source_card_index = distributor;
			selector_context.ability_source_owner = distributor_owner;
			selector_context.ability_source_zone = distributor_zone;
			selector_context.ability_source_logical_index = distributor_logical_index;
			selector_context.ability_source_cell = distributor_zone == 0
				? distributor_logical_index
				: -1;
			bool selection_supported = true;
			const std::vector<int32_t> selected = snapshot_selected_cards(
				value,
				action.selector,
				selector_context,
				selection_supported
			);
			if (!selection_supported) return ActionOutcome::UNSUPPORTED;

			ActionOutcome aggregate = ActionOutcome::NO_EFFECT;
			while (true) {
				if (
					!locate_card(
						value,
						distributor,
						distributor_zone,
						distributor_owner,
						distributor_logical_index
					)
					|| distributor_zone == 2
					|| value.card_ki[distributor] < action.amount
				) break;
				bool transferred_in_round = false;
				for (const int32_t recipient : selected) {
					if (
						!locate_card(
							value,
							distributor,
							distributor_zone,
							distributor_owner,
							distributor_logical_index
						)
						|| distributor_zone == 2
						|| value.card_ki[distributor] < action.amount
					) break;
					int32_t recipient_zone = -1;
					int32_t recipient_owner = 0;
					int32_t recipient_logical_index = -1;
					if (
						!locate_card(
							value,
							recipient,
							recipient_zone,
							recipient_owner,
							recipient_logical_index
						)
						|| recipient_zone == 2
					) continue;
					selector_context.ability_source_owner = distributor_owner;
					selector_context.ability_source_zone = distributor_zone;
					selector_context.ability_source_logical_index = distributor_logical_index;
					selector_context.ability_source_cell = distributor_zone == 0
						? distributor_logical_index
						: -1;
					bool condition_supported = true;
					if (!selector_conditions_match(
						value,
						recipient,
						recipient_zone,
						recipient_owner,
						recipient_logical_index,
						action.selector,
						selector_context,
						condition_supported
					)) {
						if (!condition_supported) return ActionOutcome::UNSUPPORTED;
						continue;
					}

					const int64_t transfer_event_start = resolution.events.size();
					CompiledAction donor_action;
					donor_action.opcode = ActionOpcode::SPEND_KI;
					donor_action.card_ref_explicit = true;
					donor_action.card_ref = CardRefOpcode::SELECTED_CARD;
					donor_action.amount = action.amount;
					donor_action.change_reason = StringName("transfer_card_resource");
					ActionContext donor_context = action_context;
					donor_context.selected_card_index = distributor;
					donor_context.selected_card_owner = distributor_owner;
					donor_context.action_subject_owner = distributor_owner;
					const ActionOutcome donor_outcome = change_ki(
						value, group, donor_action, event_context, donor_context,
						action_source_cell, exile_stack, resolution
					);
					if (donor_outcome != ActionOutcome::APPLIED) continue;
					CompiledAction receiver_action = donor_action;
					receiver_action.opcode = ActionOpcode::GAIN_KI;
					ActionContext receiver_context = action_context;
					receiver_context.selected_card_index = recipient;
					receiver_context.selected_card_owner = recipient_owner;
					receiver_context.action_subject_owner = recipient_owner;
					const ActionOutcome receiver_outcome = change_ki(
						value, group, receiver_action, event_context, receiver_context,
						action_source_cell, exile_stack, resolution
					);
					if (receiver_outcome != ActionOutcome::APPLIED) return receiver_outcome;

					const int64_t transfer_event_end = resolution.events.size();
					for (
						int64_t event_index = transfer_event_start;
						event_index < transfer_event_end;
						++event_index
					) {
						Dictionary ki_event = resolution.events[event_index];
						ki_event["ki_trigger_resolved"] = true;
						resolution.events[event_index] = ki_event;
						EventContext ki_context;
						ki_context.trigger_cell = static_cast<int32_t>(static_cast<int64_t>(ki_event.get("target_cell", -1)));
						const StringName instance_id = ki_event.get("instance_id", StringName());
						for (size_t card_index = 0; card_index < value.card_instance_ids.size(); ++card_index) {
							if (value.card_instance_ids[card_index] == instance_id) {
								ki_context.trigger_card_index = static_cast<int32_t>(card_index);
								break;
							}
						}
						ki_context.trigger_owner = static_cast<int32_t>(static_cast<int64_t>(ki_event.get("owner_id", 0)));
						ki_context.previous_ki = static_cast<int32_t>(static_cast<int64_t>(ki_event.get("previous_ki", 0)));
						ki_context.ki = static_cast<int32_t>(static_cast<int64_t>(ki_event.get("ki", -1)));
						Resolution ki_resolution = resolve_event(
							value,
							StringName("card_ki_changed"),
							ki_context,
							exile_stack
						);
						if (!ki_resolution.supported) {
							resolution.reason = ki_resolution.reason;
							return ActionOutcome::UNSUPPORTED;
						}
						append_resolution(resolution, ki_resolution);
					}
					transferred_in_round = true;
					aggregate = ActionOutcome::APPLIED;
				}
				if (!transferred_in_round) break;
			}
			return aggregate;
		}
		case ActionOpcode::ADD_CARD_TO_HAND: {
			int32_t source_zone = -1;
			int32_t source_owner = 0;
			int32_t source_logical_index = -1;
			const int32_t source_card_index = action_context.action_subject_card_index;
			if (
				source_card_index < 0
				|| !locate_card(
					value,
					source_card_index,
					source_zone,
					source_owner,
					source_logical_index
				)
				|| source_owner != action_context.action_subject_owner
			) return ActionOutcome::NO_EFFECT;
			if (action.recipient == RecipientOpcode::UNSUPPORTED) return ActionOutcome::UNSUPPORTED;
			const int32_t recipient_owner = action.recipient == RecipientOpcode::SELF
				? source_owner
				: other_owner(source_owner);
			std::vector<int32_t> &hand = value.zones[recipient_owner - 1];
			if (hand.size() >= 5) return ActionOutcome::NO_EFFECT;
			const int32_t hand_slot = leftmost_empty_hand_slot(value, recipient_owner);
			if (hand_slot < 0) return ActionOutcome::NO_EFFECT;

			int32_t copied_card_index = -1;
			StringName card_id = action.card_id;
			if (card_id.is_empty()) {
				copied_card_index = resolve_action_card_reference(
					action.summon_card_ref,
					event_context,
					action_context,
					execution_state
				);
				if (
					copied_card_index < 0
					|| copied_card_index >= static_cast<int32_t>(value.card_ids.size())
				) return ActionOutcome::NO_EFFECT;
				card_id = value.card_ids[copied_card_index];
			}
			const StringName instance_id = make_generated_instance_id(value, card_id);
			String append_reason;
			const int32_t added_card_index = action.card_spec == CardSpecOpcode::PERFECT_COPY
				? append_perfect_copy_board_card(
					value,
					copied_card_index,
					instance_id,
					append_reason
				)
				: append_fresh_board_card(
					value,
					card_id,
					instance_id,
					recipient_owner,
					append_reason
				);
			if (added_card_index < 0) {
				if (
					action.card_spec != CardSpecOpcode::PERFECT_COPY
					&& find_fresh_card_prototype(value, card_id) == nullptr
				) return ActionOutcome::NO_EFFECT;
				resolution.reason = append_reason;
				return ActionOutcome::UNSUPPORTED;
			}
			value.card_runtime_flags[added_card_index] |= static_cast<uint8_t>(1 << 7);
			value.card_hand_slots[added_card_index] = hand_slot;
			const int32_t previous_hand_size = static_cast<int32_t>(hand.size());
			hand.push_back(added_card_index);

			const int32_t observer_owner = other_owner(recipient_owner);
			uint8_t &reveal_code = value.card_reveal_codes[added_card_index];
			const bool already_revealed = (
				(observer_owner == 1 && (reveal_code == 1 || reveal_code == 3 || reveal_code == 4))
				|| (observer_owner == 2 && (reveal_code == 2 || reveal_code == 3 || reveal_code == 4))
			);
			if (!already_revealed) {
				if (observer_owner == 1) reveal_code = reveal_code == 2 ? 4 : 1;
				else reveal_code = reveal_code == 1 ? 3 : 2;
			}
			const int32_t current_source_cell = source_zone == 0 ? source_logical_index : -1;
			Dictionary added;
			added["type"] = StringName("card_added_to_hand");
			added["source_cell"] = current_source_cell;
			added["source_instance_id"] = value.card_instance_ids[source_card_index];
			added["owner_id"] = recipient_owner;
			added["card_id"] = card_id;
			added["instance_id"] = instance_id;
			added["logical_hand_index"] = static_cast<int32_t>(hand.size()) - 1;
			added["hand_slot_index"] = hand_slot;
			if (include_presentation_payloads) {
				added["card"] = restore_runtime_card(value, added_card_index);
			}
			resolution.events.append(added);
			if (!already_revealed) {
				Dictionary revealed;
				revealed["type"] = StringName("card_revealed");
				revealed["source_cell"] = current_source_cell;
				revealed["source_instance_id"] = value.card_instance_ids[source_card_index];
				revealed["owner_id"] = recipient_owner;
				revealed["observer_owner_id"] = observer_owner;
				revealed["card_id"] = card_id;
				revealed["instance_id"] = instance_id;
				revealed["logical_hand_index"] = static_cast<int32_t>(hand.size()) - 1;
				resolution.events.append(revealed);
			}
			Resolution hand_change = resolve_difficulty_hand_change(
				value,
				recipient_owner,
				previous_hand_size,
				static_cast<int32_t>(hand.size()),
				action_source_cell,
				exile_stack
			);
			if (!hand_change.supported) {
				resolution.reason = hand_change.reason;
				return ActionOutcome::UNSUPPORTED;
			}
			append_resolution(resolution, hand_change);
			return ActionOutcome::APPLIED;
		}
		case ActionOpcode::REVEAL_HAND_CARDS: {
			const int32_t observer_owner = action_context.action_subject_owner;
			if (observer_owner != 1 && observer_owner != 2) return ActionOutcome::NO_EFFECT;
			const int32_t hand_owner = action.recipient == RecipientOpcode::SELF
				? observer_owner
				: other_owner(observer_owner);
			if (action.recipient == RecipientOpcode::UNSUPPORTED) return ActionOutcome::UNSUPPORTED;
			Array remembered;
			if (action.reveal_filter == RevealFilterOpcode::REMEMBERED) {
				const Dictionary remembered_by_owner = value.side_payload.get(
					"remembered_glyphs_by_owner",
					Dictionary()
				);
				const Variant remembered_value = remembered_by_owner.get(observer_owner, Array());
				if (remembered_value.get_type() != Variant::ARRAY) return ActionOutcome::UNSUPPORTED;
				remembered = remembered_value;
			} else if (action.reveal_filter != RevealFilterOpcode::ALL) {
				return ActionOutcome::UNSUPPORTED;
			}
			bool applied = false;
			const std::vector<int32_t> &hand = value.zones[hand_owner - 1];
			for (size_t hand_index = 0; hand_index < hand.size(); ++hand_index) {
				const int32_t card_index = hand[hand_index];
				if (action.reveal_filter == RevealFilterOpcode::REMEMBERED) {
					const int32_t template_index = value.card_template_indices[card_index];
					if (
						template_index < 0
						|| template_index >= value.card_template_pool.size()
					) return ActionOutcome::UNSUPPORTED;
					const Dictionary card_template = value.card_template_pool[template_index];
					if (remembered.find(String(card_template.get("glyph", String()))) < 0) continue;
				}
				uint8_t &code = value.card_reveal_codes[card_index];
				const bool already_revealed = (
					(observer_owner == 1 && (code == 1 || code == 3 || code == 4))
					|| (observer_owner == 2 && (code == 2 || code == 3 || code == 4))
				);
				if (already_revealed) continue;
				if (observer_owner == 1) code = code == 2 ? 4 : 1;
				else code = code == 1 ? 3 : 2;
				Dictionary revealed;
				revealed["type"] = StringName("card_revealed");
				revealed["source_cell"] = action_source_cell;
				revealed["owner_id"] = hand_owner;
				revealed["observer_owner_id"] = observer_owner;
				revealed["card_id"] = value.card_ids[card_index];
				revealed["instance_id"] = value.card_instance_ids[card_index];
				revealed["logical_hand_index"] = static_cast<int32_t>(hand_index);
				resolution.events.append(revealed);
				applied = true;
			}
			return applied ? ActionOutcome::APPLIED : ActionOutcome::NO_EFFECT;
		}
		case ActionOpcode::REVEAL_CARD: {
			const int32_t target = resolve_action_card_reference(
				action.card_ref,
				event_context,
				action_context,
				execution_state
			);
			int32_t zone = -1;
			int32_t owner = 0;
			int32_t logical_index = -1;
			if (target < 0 || !locate_card(value, target, zone, owner, logical_index)) {
				return ActionOutcome::NO_EFFECT;
			}
			int32_t expected_owner = 0;
			if (action.card_ref == CardRefOpcode::SELECTED_CARD) {
				expected_owner = action_context.selected_card_owner;
			} else if (action.card_ref == CardRefOpcode::TRIGGER_CARD) {
				expected_owner = event_context.trigger_owner;
			} else if (action.card_ref == CardRefOpcode::ABILITY_SOURCE) {
				expected_owner = action_context.ability_source_owner;
			} else if (action.card_ref == CardRefOpcode::ATTACKER_CARD) {
				expected_owner = event_context.attacker_owner;
			}
			if (expected_owner != 0 && owner != expected_owner) return ActionOutcome::NO_EFFECT;
			const int32_t observer_owner = resolve_relative_owner(
				value,
				action.recipient_owner,
				action_context,
				target
			);
			if (observer_owner != 1 && observer_owner != 2) return ActionOutcome::NO_EFFECT;
			StringName zone_name;
			if (zone == 0) zone_name = StringName("board");
			else if (zone == 1) zone_name = StringName("hand");
			else if (zone == 3) zone_name = StringName("discard");
			else if (zone == 4) zone_name = StringName("removed");
			else return ActionOutcome::NO_EFFECT;
			uint8_t &code = value.card_reveal_codes[target];
			const bool already_revealed = (
				(observer_owner == 1 && (code == 1 || code == 3 || code == 4))
				|| (observer_owner == 2 && (code == 2 || code == 3 || code == 4))
			);
			if (already_revealed) return ActionOutcome::NO_EFFECT;
			if (observer_owner == 1) code = code == 2 ? 4 : 1;
			else code = code == 1 ? 3 : 2;
			Dictionary revealed;
			revealed["type"] = StringName("card_revealed");
			revealed["source_cell"] = action_source_cell;
			revealed["owner_id"] = owner;
			revealed["observer_owner_id"] = observer_owner;
			revealed["card_id"] = value.card_ids[target];
			revealed["instance_id"] = value.card_instance_ids[target];
			revealed["zone"] = zone_name;
			revealed["logical_hand_index"] = zone == 1 ? logical_index : -1;
			revealed["target_cell"] = zone == 0 ? logical_index : -1;
			resolution.events.append(revealed);
			return ActionOutcome::APPLIED;
		}
		case ActionOpcode::GRANT_EXTRA_CARD_PLAY: {
			int32_t source_card_index = action_context.action_subject_card_index;
			int32_t source_owner = action_context.action_subject_owner;
			int32_t source_cell = action_source_cell;
			if (action.card_ref_explicit) {
				if (action.card_ref == CardRefOpcode::SELECTED_CARD) source_card_index = action_context.selected_card_index;
				else if (action.card_ref == CardRefOpcode::TRIGGER_CARD) source_card_index = event_context.trigger_card_index;
				else if (action.card_ref == CardRefOpcode::ABILITY_SOURCE) source_card_index = action_context.ability_source_card_index;
				else if (action.card_ref == CardRefOpcode::ATTACKER_CARD) source_card_index = event_context.attacker_card_index;
				else if (action.card_ref == CardRefOpcode::LAST_SUMMONED_CARD) source_card_index = execution_state.last_summoned_card_index;
				else return ActionOutcome::UNSUPPORTED;
				int32_t zone = -1;
				int32_t logical_index = -1;
				if (!locate_card(value, source_card_index, zone, source_owner, logical_index)) {
					return ActionOutcome::NO_EFFECT;
				}
				source_cell = zone == 0 ? logical_index : action_source_cell;
			}
			if (
				source_card_index < 0
				|| source_card_index >= static_cast<int32_t>(value.card_instance_ids.size())
				|| (source_owner != 1 && source_owner != 2)
				|| action.amount <= 0
			) return ActionOutcome::NO_EFFECT;
			Resolution::ExtraPlayRequest request;
			request.owner_id = source_owner;
			request.source_card_index = source_card_index;
			request.source_cell = source_cell;
			request.amount = action.amount;
			resolution.extra_play_requests.push_back(request);
			return ActionOutcome::APPLIED;
		}
		case ActionOpcode::ADD_PENDING_NON_RETAINED_SUPPRESSION: {
			const int32_t source_owner = action_context.action_subject_owner;
			if (
				(source_owner != 1 && source_owner != 2)
				|| action_context.action_subject_card_index < 0
				|| action_context.action_subject_card_index >= static_cast<int32_t>(value.card_instance_ids.size())
			) return ActionOutcome::NO_EFFECT;
			if (action.recipient == RecipientOpcode::UNSUPPORTED) return ActionOutcome::UNSUPPORTED;
			const int32_t recipient_owner = action.recipient == RecipientOpcode::SELF
				? source_owner
				: other_owner(source_owner);
			const int32_t scalar_index = recipient_owner == 1 ? 8 : 9;
			value.scalars[scalar_index] += action.amount;
			Dictionary added;
			added["type"] = StringName("non_retained_suppression_added");
			added["source_cell"] = action_source_cell;
			added["source_instance_id"] = value.card_instance_ids[action_context.action_subject_card_index];
			added["owner_id"] = recipient_owner;
			added["amount"] = action.amount;
			added["pending_count"] = value.scalars[scalar_index];
			resolution.events.append(added);
			return ActionOutcome::APPLIED;
		}
		case ActionOpcode::TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES:
			return temporarily_remove_non_retained_abilities(
				value,
				action_context,
				action_source_cell,
				resolution
			);
		case ActionOpcode::ENABLE_FUTURE_DRAW_REVEAL: {
			const int32_t observer_owner = action_context.action_subject_owner;
			if (observer_owner != 1 && observer_owner != 2) return ActionOutcome::NO_EFFECT;
			const int32_t hand_owner = action.recipient == RecipientOpcode::SELF
				? observer_owner
				: other_owner(observer_owner);
			if (action.recipient == RecipientOpcode::UNSUPPORTED) return ActionOutcome::UNSUPPORTED;
			Dictionary audiences_by_owner = value.side_payload.get(
				"future_draw_reveal_audiences",
				Dictionary()
			);
			const Variant audiences_value = audiences_by_owner.get(hand_owner, Array());
			if (audiences_value.get_type() != Variant::ARRAY) return ActionOutcome::UNSUPPORTED;
			Array audiences = audiences_value;
			if (audiences.find(observer_owner) >= 0) return ActionOutcome::NO_EFFECT;
			audiences.append(observer_owner);
			audiences_by_owner[hand_owner] = audiences;
			value.side_payload["future_draw_reveal_audiences"] = audiences_by_owner;
			return ActionOutcome::APPLIED;
		}
		case ActionOpcode::SUMMON_CARD:
			return summon_card(
				value,
				group,
				action,
				event_context,
				action_context,
				execution_state,
				exile_stack,
				resolution
			);
		case ActionOpcode::RESUMMON_CARD_IN_PLACE:
			return resummon_card_in_place(
				value,
				group,
				action,
				event_context,
				action_context,
				execution_state,
				exile_stack,
				resolution
			);
		case ActionOpcode::DEPART_CARD_FOR_RESUMMON:
			return depart_card_for_resummon(
				value,
				action,
				event_context,
				action_context,
				execution_state,
				resolution
			);
		default:
			return ActionOutcome::UNSUPPORTED;
	}
}

int32_t DuelNativeCompactKernel::resolve_action_card_reference(
	CardRefOpcode reference,
	const EventContext &event_context,
	const ActionContext &action_context,
	const ActionExecutionState &execution_state
) const {
	if (reference == CardRefOpcode::SELECTED_CARD) return action_context.selected_card_index;
	if (reference == CardRefOpcode::TRIGGER_CARD) return event_context.trigger_card_index;
	if (reference == CardRefOpcode::ABILITY_SOURCE) return action_context.ability_source_card_index;
	if (reference == CardRefOpcode::ATTACKER_CARD) return event_context.attacker_card_index;
	if (reference == CardRefOpcode::LAST_SUMMONED_CARD) return execution_state.last_summoned_card_index;
	return -1;
}

int32_t DuelNativeCompactKernel::initial_cell_for_reference(
	CardRefOpcode reference,
	const EventContext &event_context,
	const ActionContext &action_context,
	const ActionExecutionState &execution_state
) const {
	if (reference == CardRefOpcode::ABILITY_SOURCE) {
		return action_context.ability_source_zone == 0
			? action_context.ability_source_logical_index
			: action_context.ability_source_cell;
	}
	if (reference == CardRefOpcode::SELECTED_CARD) {
		if (action_context.selected_card_zone == 0) {
			return action_context.selected_card_logical_index;
		}
		return action_context.action_subject_card_index == action_context.selected_card_index
			&& action_context.action_subject_zone == 0
			? action_context.action_subject_logical_index
			: -1;
	}
	if (reference == CardRefOpcode::TRIGGER_CARD) {
		return event_context.trigger_zone == 0
			? event_context.trigger_logical_index
			: event_context.trigger_cell;
	}
	if (reference == CardRefOpcode::ATTACKER_CARD) return event_context.attacker_cell;
	if (reference == CardRefOpcode::LAST_SUMMONED_CARD) return execution_state.last_summoned_cell;
	return -1;
}

int32_t DuelNativeCompactKernel::resolve_relative_owner(
	const NativeState &value,
	RelativeOwnerOpcode reference,
	const ActionContext &action_context,
	int32_t referenced_card_index
) const {
	if (reference == RelativeOwnerOpcode::ABILITY_SOURCE) return action_context.ability_source_owner;
	if (reference == RelativeOwnerOpcode::OPPONENT_OF_ABILITY_SOURCE) {
		return action_context.ability_source_owner == 1 || action_context.ability_source_owner == 2
			? other_owner(action_context.ability_source_owner)
			: 0;
	}
	if (referenced_card_index < 0) referenced_card_index = action_context.action_subject_card_index;
	if (
		referenced_card_index < 0
		|| referenced_card_index >= static_cast<int32_t>(value.card_instance_ids.size())
	) return 0;
	if (reference == RelativeOwnerOpcode::CARD_ORIGINAL) {
		return value.card_original_owners[referenced_card_index];
	}
	if (reference == RelativeOwnerOpcode::CARD_CURRENT) {
		int32_t zone = -1;
		int32_t owner = 0;
		int32_t logical_index = -1;
		return locate_card(value, referenced_card_index, zone, owner, logical_index) ? owner : 0;
	}
	return 0;
}

const DuelNativeCompactKernel::FreshCardPrototype *DuelNativeCompactKernel::find_fresh_card_prototype(
	const NativeState &value,
	const StringName &card_id
) const {
	for (const FreshCardPrototype &prototype : value.fresh_card_prototypes) {
		if (prototype.card_id == card_id) return &prototype;
	}
	return nullptr;
}

StringName DuelNativeCompactKernel::make_generated_instance_id(
	const NativeState &value,
	const StringName &card_id
) const {
	auto located = [&](const StringName &candidate) {
		for (const int32_t card_index : value.board_card_indices) {
			if (card_index >= 0 && value.card_instance_ids[card_index] == candidate) return true;
		}
		for (const std::vector<int32_t> &zone : value.zones) {
			for (const int32_t card_index : zone) {
				if (value.card_instance_ids[card_index] == candidate) return true;
			}
		}
		return false;
	};
	for (int64_t serial = 1; ; ++serial) {
		const StringName candidate(
			String("generated_") + String(card_id) + "_" + String::num_int64(serial)
		);
		if (!located(candidate)) return candidate;
	}
}

int32_t DuelNativeCompactKernel::append_fresh_board_card(
	NativeState &value,
	const StringName &card_id,
	const StringName &instance_id,
	int32_t owner_id,
	String &reason
) const {
	const FreshCardPrototype *prototype_pointer = find_fresh_card_prototype(value, card_id);
	if (prototype_pointer == nullptr) {
		reason = "Summoned card has no fresh-card prototype";
		return -1;
	}
	const FreshCardPrototype prototype = *prototype_pointer;
	if (
		prototype.active_ability_set_index < 0
		|| prototype.active_ability_set_index >= static_cast<int32_t>(compiled_ability_sets.size())
	) {
		reason = "Summoned card prototype has no compiled ability set";
		return -1;
	}
	const int32_t card_index = static_cast<int32_t>(value.card_instance_ids.size());
	value.card_instance_ids.push_back(instance_id);
	value.card_template_indices.push_back(prototype.template_index);
	static constexpr uint8_t fresh_runtime_flags = (
		(1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5)
	);
	value.card_runtime_flags.push_back(fresh_runtime_flags);
	for (const int32_t power : prototype.powers) value.card_powers.push_back(power);
	value.card_original_owners.push_back(static_cast<uint8_t>(owner_id));
	value.card_ki.push_back(prototype.ki);
	value.card_active_ability_set_indices.push_back(prototype.active_ability_set_index);
	std::vector<RuntimeAbilityEntry> runtime_entries;
	const std::vector<int32_t> &ability_indices = compiled_ability_sets[
		prototype.active_ability_set_index
	].ability_pool_indices;
	runtime_entries.reserve(ability_indices.size());
	for (const int32_t compiled_ability_index : ability_indices) {
		RuntimeAbilityEntry entry;
		entry.compiled_ability_index = compiled_ability_index;
		entry.handle = value.next_ability_handle++;
		runtime_entries.push_back(entry);
	}
	value.card_runtime_abilities.push_back(runtime_entries);
	value.card_runtime_suppression_batches.push_back({});
	value.card_reveal_codes.push_back(static_cast<uint8_t>(owner_id));
	value.card_suppression_set_indices.push_back(-1);
	value.card_hand_slots.push_back(-1);
	value.card_ids.push_back(card_id);
	return card_index;
}

int32_t DuelNativeCompactKernel::append_perfect_copy_board_card(
	NativeState &value,
	int32_t copied_card_index,
	const StringName &instance_id,
	String &reason
) const {
	if (
		copied_card_index < 0
		|| copied_card_index >= static_cast<int32_t>(value.card_instance_ids.size())
	) {
		reason = "Perfect-copy summon has no copied runtime card";
		return -1;
	}
	const int32_t card_index = static_cast<int32_t>(value.card_instance_ids.size());
	value.card_instance_ids.push_back(instance_id);
	value.card_template_indices.push_back(value.card_template_indices[copied_card_index]);
	value.card_runtime_flags.push_back(
		value.card_runtime_flags[copied_card_index] & static_cast<uint8_t>(~(1 << 7))
	);
	for (int32_t direction = 0; direction < 4; ++direction) {
		value.card_powers.push_back(value.card_powers[copied_card_index * 4 + direction]);
	}
	value.card_original_owners.push_back(value.card_original_owners[copied_card_index]);
	value.card_ki.push_back(value.card_ki[copied_card_index]);
	value.card_active_ability_set_indices.push_back(
		value.card_active_ability_set_indices[copied_card_index]
	);
	std::vector<RuntimeAbilityEntry> runtime_entries;
	runtime_entries.reserve(value.card_runtime_abilities[copied_card_index].size());
	for (const RuntimeAbilityEntry &copied_entry : value.card_runtime_abilities[copied_card_index]) {
		RuntimeAbilityEntry entry;
		entry.compiled_ability_index = copied_entry.compiled_ability_index;
		entry.handle = value.next_ability_handle++;
		runtime_entries.push_back(entry);
	}
	value.card_runtime_abilities.push_back(runtime_entries);
	std::vector<RuntimeSuppressionBatch> suppression_batches;
	suppression_batches.reserve(value.card_runtime_suppression_batches[copied_card_index].size());
	for (const RuntimeSuppressionBatch &copied_batch : value.card_runtime_suppression_batches[copied_card_index]) {
		RuntimeSuppressionBatch batch;
		batch.expires_after_turn = copied_batch.expires_after_turn;
		batch.entries.reserve(copied_batch.entries.size());
		for (const RuntimeSuppressionEntry &copied_entry : copied_batch.entries) {
			RuntimeSuppressionEntry entry;
			entry.original_index = copied_entry.original_index;
			entry.compiled_ability_index = copied_entry.compiled_ability_index;
			entry.handle = value.next_ability_handle++;
			batch.entries.push_back(entry);
		}
		suppression_batches.push_back(batch);
	}
	value.card_runtime_suppression_batches.push_back(suppression_batches);
	value.card_reveal_codes.push_back(value.card_reveal_codes[copied_card_index]);
	value.card_suppression_set_indices.push_back(
		value.card_suppression_set_indices[copied_card_index]
	);
	value.card_hand_slots.push_back(-1);
	value.card_ids.push_back(value.card_ids[copied_card_index]);
	return card_index;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::summon_card(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	ActionExecutionState &execution_state,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	const int32_t source_owner = action_context.ability_source_owner;
	if (source_owner != 1 && source_owner != 2) return ActionOutcome::NO_EFFECT;
	const int32_t source_card_index = action_context.ability_source_card_index;
	int32_t source_cell = find_board_card(value, source_card_index, execution_state.current_source_cell);

	int32_t referenced_card_index = -1;
	int32_t existing_zone = -1;
	int32_t existing_owner = 0;
	int32_t existing_logical_index = -1;
	StringName card_id;
	if (action.card_spec == CardSpecOpcode::TOP_DISCARD) {
		existing_owner = resolve_relative_owner(value, action.summon_owner, action_context);
		if (existing_owner != 1 && existing_owner != 2) return ActionOutcome::NO_EFFECT;
		std::vector<int32_t> &discard = value.zones[existing_owner + 3];
		if (discard.empty()) return ActionOutcome::NO_EFFECT;
		referenced_card_index = discard.back();
		if (!locate_card(value, referenced_card_index, existing_zone, existing_owner, existing_logical_index)) {
			return ActionOutcome::NO_EFFECT;
		}
	} else {
		referenced_card_index = resolve_action_card_reference(
			action.summon_card_ref,
			event_context,
			action_context,
			execution_state
		);
		if (
			referenced_card_index < 0
			|| referenced_card_index >= static_cast<int32_t>(value.card_ids.size())
		) return ActionOutcome::NO_EFFECT;
		if (action.card_spec == CardSpecOpcode::EXISTING_REFERENCE) {
			if (!locate_card(value, referenced_card_index, existing_zone, existing_owner, existing_logical_index)) {
				return ActionOutcome::NO_EFFECT;
			}
		}
	}
	card_id = value.card_ids[referenced_card_index];
	if (card_id.is_empty()) return ActionOutcome::NO_EFFECT;

	int32_t target_cell = -1;
	if (action.cell_spec == CellSpecOpcode::INITIAL_CARD_CELL) {
		target_cell = initial_cell_for_reference(
			action.summon_cell_card_ref,
			event_context,
			action_context,
			execution_state
		);
	} else if (action.cell_spec == CellSpecOpcode::ACTIVATION_TARGET) {
		if (action_context.activation_target_kind != StringName("board_cell")) {
			return ActionOutcome::NO_EFFECT;
		}
		target_cell = action_context.activation_target_index;
	} else if (
		action.cell_spec == CellSpecOpcode::FIRST_ADJACENT_EMPTY
		|| action.cell_spec == CellSpecOpcode::FIRST_ADJACENT_OR_ANY_EMPTY
	) {
		const int32_t anchor_card_index = resolve_action_card_reference(
			action.summon_cell_card_ref,
			event_context,
			action_context,
			execution_state
		);
		const int32_t anchor_cell = find_board_card(value, anchor_card_index);
		if (anchor_cell < 0) return ActionOutcome::NO_EFFECT;
		std::vector<int32_t> empty_neighbors;
		for (int32_t direction = 0; direction < 4; ++direction) {
			const int32_t neighbor = neighbor_index(anchor_cell, direction);
			if (neighbor >= 0 && value.board_card_indices[neighbor] < 0) empty_neighbors.push_back(neighbor);
		}
		if (!empty_neighbors.empty()) {
			std::sort(empty_neighbors.begin(), empty_neighbors.end());
			target_cell = empty_neighbors.front();
		} else if (action.cell_spec == CellSpecOpcode::FIRST_ADJACENT_OR_ANY_EMPTY) {
			for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
				if (value.board_card_indices[cell] < 0) {
					target_cell = static_cast<int32_t>(cell);
					break;
				}
			}
		}
	} else if (action.cell_spec == CellSpecOpcode::FIRST_EMPTY_ADJACENT_TO_ENEMY) {
		const int32_t reference_owner = resolve_relative_owner(
			value,
			action.summon_owner,
			action_context
		);
		if (reference_owner != 1 && reference_owner != 2) return ActionOutcome::NO_EFFECT;
		for (size_t cell = 0; cell < value.board_card_indices.size() && target_cell < 0; ++cell) {
			if (value.board_card_indices[cell] >= 0) continue;
			for (int32_t direction = 0; direction < 4; ++direction) {
				const int32_t neighbor = neighbor_index(static_cast<int32_t>(cell), direction);
				if (
					neighbor >= 0
					&& value.board_card_indices[neighbor] >= 0
					&& value.board_owners[neighbor] != reference_owner
				) {
					target_cell = static_cast<int32_t>(cell);
					break;
				}
			}
		}
	}
	if (
		target_cell < 0
		|| target_cell >= static_cast<int32_t>(value.board_card_indices.size())
		|| value.board_card_indices[target_cell] >= 0
	) return ActionOutcome::NO_EFFECT;

	int32_t summoned_card_index = referenced_card_index;
	StringName instance_id;
	StringName from_hand_instance_id;
	StringName from_removed_instance_id;
	StringName from_discard_instance_id;
	int32_t previous_hand_size = -1;
	if (action.card_spec == CardSpecOpcode::EXISTING_REFERENCE || action.card_spec == CardSpecOpcode::TOP_DISCARD) {
		if (existing_zone != 1 && existing_zone != 3 && existing_zone != 4) return ActionOutcome::NO_EFFECT;
		if ((existing_zone == 1 || existing_zone == 4) && existing_owner != source_owner) {
			return ActionOutcome::NO_EFFECT;
		}
		const int32_t zone_index = existing_zone == 1
			? existing_owner - 1
			: (existing_zone == 3 ? existing_owner + 3 : existing_owner + 5);
		std::vector<int32_t> &zone = value.zones[zone_index];
		if (
			existing_logical_index < 0
			|| existing_logical_index >= static_cast<int32_t>(zone.size())
			|| zone[existing_logical_index] != summoned_card_index
		) return ActionOutcome::NO_EFFECT;
		if (existing_zone == 1) previous_hand_size = static_cast<int32_t>(zone.size());
		zone.erase(zone.begin() + existing_logical_index);
		instance_id = value.card_instance_ids[summoned_card_index];
		if (existing_zone == 1) {
			from_hand_instance_id = instance_id;
			value.card_runtime_flags[summoned_card_index] &= static_cast<uint8_t>(~(1 << 7));
			value.card_hand_slots[summoned_card_index] = -1;
		} else if (existing_zone == 3) {
			from_discard_instance_id = instance_id;
		} else {
			from_removed_instance_id = instance_id;
		}
	} else {
		instance_id = make_generated_instance_id(value, card_id);
		String append_reason;
		summoned_card_index = action.card_spec == CardSpecOpcode::PERFECT_COPY
			? append_perfect_copy_board_card(value, referenced_card_index, instance_id, append_reason)
			: append_fresh_board_card(value, card_id, instance_id, source_owner, append_reason);
		if (summoned_card_index < 0) {
			if (
				action.card_spec != CardSpecOpcode::PERFECT_COPY
				&& find_fresh_card_prototype(value, card_id) == nullptr
			) return ActionOutcome::NO_EFFECT;
			resolution.reason = append_reason;
			return ActionOutcome::UNSUPPORTED;
		}
	}

	value.board_card_indices[target_cell] = summoned_card_index;
	value.board_owners[target_cell] = static_cast<uint8_t>(source_owner);
	if (target_cell < value.board_slot_extras.size()) value.board_slot_extras[target_cell] = Dictionary();
	Dictionary summoned_event;
	summoned_event["type"] = StringName("card_summoned");
	summoned_event["source_cell"] = source_cell;
	summoned_event["source_instance_id"] = source_card_index >= 0
		? value.card_instance_ids[source_card_index]
		: StringName();
	summoned_event["target_cell"] = target_cell;
	summoned_event["owner_id"] = source_owner;
	summoned_event["card_id"] = card_id;
	summoned_event["instance_id"] = instance_id;
	if (include_presentation_payloads) {
		summoned_event["card"] = restore_runtime_card(value, summoned_card_index);
	}
	summoned_event["from_hand_instance_id"] = from_hand_instance_id;
	summoned_event["from_removed_instance_id"] = from_removed_instance_id;
	summoned_event["from_discard_instance_id"] = from_discard_instance_id;
	const StringName summon_reason = from_discard_instance_id.is_empty()
		? StringName("ability_fresh_copy")
		: StringName("ability_discard_summon");
	summoned_event["summon_reason"] = summon_reason;

	SummonRequest request;
	request.summon_cell = target_cell;
	request.card_index = summoned_card_index;
	request.owner_id = source_owner;
	request.summon_reason = summon_reason;
	request.attack_reason = StringName("generated_summon_standard_attack");
	request.buffered_placement_events.append(summoned_event);
	if (previous_hand_size >= 0) {
		Resolution hand_change = resolve_difficulty_hand_change(
			value,
			source_owner,
			previous_hand_size,
			static_cast<int32_t>(value.zones[source_owner - 1].size()),
			target_cell,
			exile_stack
		);
		if (!hand_change.supported) {
			resolution.reason = hand_change.reason;
			return ActionOutcome::UNSUPPORTED;
		}
		request.buffered_placement_events.append_array(hand_change.events);
		hand_change.events = Array();
		append_resolution(resolution, hand_change);
	}
	Resolution nested = resolve_summon_lifecycle(value, request, exile_stack);
	if (!nested.supported) {
		resolution.reason = nested.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	append_resolution(resolution, nested);
	execution_state.last_summoned_card_index = summoned_card_index;
	execution_state.last_summoned_cell = target_cell;
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::resummon_card_in_place(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	ActionExecutionState &execution_state,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	const int32_t source_card_index = action_context.action_subject_card_index;
	const int32_t source_owner = action_context.action_subject_owner;
	const int32_t source_cell = find_board_card(value, source_card_index, execution_state.current_source_cell);
	if (source_cell < 0 || value.board_owners[source_cell] != source_owner) return ActionOutcome::NO_EFFECT;
	const int32_t target_card_index = resolve_action_card_reference(
		action.card_ref,
		event_context,
		action_context,
		execution_state
	);
	const int32_t target_cell = find_board_card(value, target_card_index);
	if (target_cell < 0) return ActionOutcome::NO_EFFECT;
	const StringName card_id = value.card_ids[target_card_index];
	const StringName old_instance_id = value.card_instance_ids[target_card_index];
	const StringName new_instance_id = make_generated_instance_id(value, card_id);
	value.board_card_indices[target_cell] = -1;
	value.board_owners[target_cell] = 0;
	if (target_cell < value.board_slot_extras.size()) value.board_slot_extras[target_cell] = Dictionary();

	Dictionary departed;
	departed["type"] = StringName("card_departed_for_resummon");
	departed["source_cell"] = source_cell;
	departed["source_instance_id"] = value.card_instance_ids[source_card_index];
	departed["target_cell"] = target_cell;
	departed["owner_id"] = source_owner;
	departed["old_instance_id"] = old_instance_id;
	departed["card_id"] = card_id;
	resolution.events.append(departed);

	String append_reason;
	const int32_t new_card_index = append_fresh_board_card(
		value,
		card_id,
		new_instance_id,
		source_owner,
		append_reason
	);
	if (new_card_index < 0) {
		resolution.reason = append_reason;
		return ActionOutcome::UNSUPPORTED;
	}
	value.board_card_indices[target_cell] = new_card_index;
	value.board_owners[target_cell] = static_cast<uint8_t>(source_owner);
	const int32_t summon_source_cell = find_board_card(
		value,
		source_card_index,
		source_cell
	);
	Dictionary summoned_event;
	summoned_event["type"] = StringName("card_summoned");
	summoned_event["source_cell"] = summon_source_cell;
	summoned_event["source_instance_id"] = value.card_instance_ids[source_card_index];
	summoned_event["target_cell"] = target_cell;
	summoned_event["owner_id"] = source_owner;
	summoned_event["card_id"] = card_id;
	summoned_event["instance_id"] = new_instance_id;
	if (include_presentation_payloads) {
		summoned_event["card"] = restore_runtime_card(value, new_card_index);
	}
	summoned_event["from_hand_instance_id"] = StringName();
	summoned_event["from_removed_instance_id"] = StringName();
	summoned_event["from_discard_instance_id"] = StringName();
	summoned_event["summon_reason"] = StringName("ability_resummon_in_place");
	SummonRequest request;
	request.summon_cell = target_cell;
	request.card_index = new_card_index;
	request.owner_id = source_owner;
	request.summon_reason = StringName("ability_resummon_in_place");
	request.attack_reason = StringName("generated_summon_standard_attack");
	request.buffered_placement_events.append(summoned_event);
	Resolution nested = resolve_summon_lifecycle(value, request, exile_stack);
	if (!nested.supported) {
		resolution.reason = nested.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	append_resolution(resolution, nested);
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::depart_card_for_resummon(
	NativeState &value,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	ActionExecutionState &execution_state,
	Resolution &resolution
) const {
	const int32_t target_card_index = resolve_action_card_reference(
		action.card_ref,
		event_context,
		action_context,
		execution_state
	);
	const int32_t target_cell = find_board_card(value, target_card_index);
	if (target_cell < 0) return ActionOutcome::NO_EFFECT;
	const int32_t target_owner = value.board_owners[target_cell];
	value.board_card_indices[target_cell] = -1;
	value.board_owners[target_cell] = 0;
	if (target_cell < value.board_slot_extras.size()) value.board_slot_extras[target_cell] = Dictionary();
	Dictionary departed;
	departed["type"] = StringName("card_departed_for_resummon");
	departed["source_cell"] = action_context.ability_source_cell;
	departed["source_instance_id"] = action_context.ability_source_card_index >= 0
		? value.card_instance_ids[action_context.ability_source_card_index]
		: StringName();
	departed["target_cell"] = target_cell;
	departed["owner_id"] = target_owner;
	departed["old_instance_id"] = value.card_instance_ids[target_card_index];
	departed["card_id"] = value.card_ids[target_card_index];
	resolution.events.append(departed);
	execution_state.current_source_cell = find_board_card(
		value,
		action_context.action_subject_card_index,
		execution_state.current_source_cell
	);
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::return_card_to_hand(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const EventContext &event_context,
	const ActionContext &action_context,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	int32_t target_card_index = -1;
	if (action.card_ref == CardRefOpcode::SELECTED_CARD) {
		target_card_index = action_context.selected_card_index;
	} else if (action.card_ref == CardRefOpcode::TRIGGER_CARD) {
		target_card_index = event_context.trigger_card_index;
	} else if (action.card_ref == CardRefOpcode::ABILITY_SOURCE) {
		target_card_index = action_context.ability_source_card_index;
	} else if (action.card_ref == CardRefOpcode::ATTACKER_CARD) {
		target_card_index = event_context.attacker_card_index;
	} else {
		return ActionOutcome::UNSUPPORTED;
	}
	if (
		target_card_index < 0
		|| target_card_index >= static_cast<int32_t>(value.card_instance_ids.size())
	) {
		return ActionOutcome::NO_EFFECT;
	}

	int32_t target_zone = -1;
	int32_t target_owner = 0;
	int32_t target_cell = -1;
	if (
		!locate_card(value, target_card_index, target_zone, target_owner, target_cell)
		|| (action.preserve_instance ? target_zone != 3 : target_zone != 0)
	) {
		return ActionOutcome::NO_EFFECT;
	}

	int32_t recipient_owner = 0;
	if (action.recipient_owner == RelativeOwnerOpcode::CARD_CURRENT) {
		recipient_owner = target_owner;
	} else if (action.recipient_owner == RelativeOwnerOpcode::CARD_ORIGINAL) {
		recipient_owner = value.card_original_owners[target_card_index];
	} else if (action.recipient_owner == RelativeOwnerOpcode::ABILITY_SOURCE) {
		recipient_owner = action_context.ability_source_owner;
	} else if (action.recipient_owner == RelativeOwnerOpcode::OPPONENT_OF_ABILITY_SOURCE) {
		recipient_owner = other_owner(action_context.ability_source_owner);
	} else {
		return ActionOutcome::UNSUPPORTED;
	}
	if (recipient_owner != 1 && recipient_owner != 2) {
		return ActionOutcome::NO_EFFECT;
	}

	const int32_t source_current_cell = [&]() {
		const int32_t current = find_board_card(
			value,
			action_context.ability_source_card_index,
			action_context.ability_source_cell
		);
		return current >= 0 ? current : action_context.ability_source_cell;
	}();
	std::vector<int32_t> &recipient_hand = value.zones[recipient_owner - 1];
	const int32_t recipient_previous_hand_size = static_cast<int32_t>(recipient_hand.size());
	if (recipient_hand.size() >= 5) {
		const int64_t previous_event_count = resolution.events.size();
		if (!exile_card(
			value,
			target_card_index,
			source_current_cell,
			action_context.ability_source_card_index,
			target_card_index == action_context.ability_source_card_index,
			StringName("return_to_full_hand"),
			event_context,
			exile_stack,
			resolution,
			action_context.record_direct_board_changes
		)) {
			return ActionOutcome::UNSUPPORTED;
		}
		return resolution.events.size() > previous_event_count
			? ActionOutcome::APPLIED
			: ActionOutcome::NO_EFFECT;
	}

	const StringName card_id = value.card_ids[target_card_index];
	if (action.preserve_instance) {
		std::vector<int32_t> &discard_pile = value.zones[target_owner + 3];
		if (
			target_cell < 0
			|| target_cell >= static_cast<int32_t>(discard_pile.size())
			|| discard_pile[target_cell] != target_card_index
		) return ActionOutcome::NO_EFFECT;
		const int32_t hand_slot = leftmost_empty_hand_slot(value, recipient_owner);
		if (hand_slot < 0) return ActionOutcome::NO_EFFECT;
		discard_pile.erase(discard_pile.begin() + target_cell);
		value.card_runtime_flags[target_card_index] |= static_cast<uint8_t>(1 << 7);
		value.card_hand_slots[target_card_index] = hand_slot;
		recipient_hand.push_back(target_card_index);

		const int32_t observer_owner = other_owner(recipient_owner);
		uint8_t &reveal_code = value.card_reveal_codes[target_card_index];
		const bool already_revealed = (
			(observer_owner == 1 && (reveal_code == 1 || reveal_code == 3 || reveal_code == 4))
			|| (observer_owner == 2 && (reveal_code == 2 || reveal_code == 3 || reveal_code == 4))
		);
		if (!already_revealed) {
			if (observer_owner == 1) reveal_code = reveal_code == 2 ? 4 : 1;
			else reveal_code = reveal_code == 1 ? 3 : 2;
		}
		const StringName source_instance_id = (
			action_context.ability_source_card_index >= 0
			? value.card_instance_ids[action_context.ability_source_card_index]
			: StringName()
		);
		Dictionary returned;
		returned["type"] = StringName("card_returned_to_hand");
		returned["source_cell"] = source_current_cell;
		returned["source_instance_id"] = source_instance_id;
		returned["target_cell"] = -1;
		returned["old_instance_id"] = value.card_instance_ids[target_card_index];
		returned["owner_id"] = recipient_owner;
		returned["card_id"] = card_id;
		returned["instance_id"] = value.card_instance_ids[target_card_index];
		returned["logical_hand_index"] = static_cast<int32_t>(recipient_hand.size()) - 1;
		returned["hand_slot_index"] = hand_slot;
		if (include_presentation_payloads) {
			returned["card"] = restore_runtime_card(value, target_card_index);
		}
		resolution.events.append(returned);
		if (!already_revealed) {
			Dictionary revealed;
			revealed["type"] = StringName("card_revealed");
			revealed["source_cell"] = source_current_cell;
			revealed["source_instance_id"] = source_instance_id;
			revealed["owner_id"] = recipient_owner;
			revealed["observer_owner_id"] = observer_owner;
			revealed["card_id"] = card_id;
			revealed["instance_id"] = value.card_instance_ids[target_card_index];
			revealed["logical_hand_index"] = static_cast<int32_t>(recipient_hand.size()) - 1;
			resolution.events.append(revealed);
		}
		Resolution hand_change = resolve_difficulty_hand_change(
			value,
			recipient_owner,
			recipient_previous_hand_size,
			static_cast<int32_t>(recipient_hand.size()),
			source_current_cell,
			exile_stack
		);
		if (!hand_change.supported) {
			resolution.reason = hand_change.reason;
			return ActionOutcome::UNSUPPORTED;
		}
		append_resolution(resolution, hand_change);
		return ActionOutcome::APPLIED;
	}

	const FreshCardPrototype *prototype = nullptr;
	for (const FreshCardPrototype &candidate : value.fresh_card_prototypes) {
		if (candidate.card_id == card_id) {
			prototype = &candidate;
			break;
		}
	}
	if (prototype == nullptr) {
		return ActionOutcome::NO_EFFECT;
	}
	if (
		prototype->active_ability_set_index < 0
		|| prototype->active_ability_set_index >= static_cast<int32_t>(compiled_ability_sets.size())
	) {
		resolution.reason = "Return card prototype has no compiled ability set";
		return ActionOutcome::UNSUPPORTED;
	}

	auto instance_id_is_located = [&](const StringName &candidate) {
		for (const int32_t card_index : value.board_card_indices) {
			if (card_index >= 0 && value.card_instance_ids[card_index] == candidate) return true;
		}
		for (const std::vector<int32_t> &zone : value.zones) {
			for (const int32_t card_index : zone) {
				if (value.card_instance_ids[card_index] == candidate) return true;
			}
		}
		return false;
	};
	StringName new_instance_id;
	for (int64_t serial = 1; ; ++serial) {
		const StringName candidate(
			String("generated_") + String(card_id) + "_" + String::num_int64(serial)
		);
		if (!instance_id_is_located(candidate)) {
			new_instance_id = candidate;
			break;
		}
	}
	const int32_t hand_slot = leftmost_empty_hand_slot(value, recipient_owner);
	if (hand_slot < 0) return ActionOutcome::NO_EFFECT;

	value.board_card_indices[target_cell] = -1;
	value.board_owners[target_cell] = 0;
	if (target_cell < value.board_slot_extras.size()) {
		value.board_slot_extras[target_cell] = Dictionary();
	}

	const int32_t new_card_index = static_cast<int32_t>(value.card_instance_ids.size());
	value.card_instance_ids.push_back(new_instance_id);
	value.card_template_indices.push_back(prototype->template_index);
	static constexpr uint8_t fresh_runtime_flags = (
		(1 << 0) | (1 << 1) | (1 << 2) | (1 << 3)
		| (1 << 4) | (1 << 5) | (1 << 7)
	);
	value.card_runtime_flags.push_back(fresh_runtime_flags);
	for (const int32_t power : prototype->powers) value.card_powers.push_back(power);
	value.card_original_owners.push_back(static_cast<uint8_t>(recipient_owner));
	value.card_ki.push_back(prototype->ki);
	value.card_active_ability_set_indices.push_back(prototype->active_ability_set_index);
	std::vector<RuntimeAbilityEntry> runtime_entries;
	const std::vector<int32_t> &ability_indices = compiled_ability_sets[
		prototype->active_ability_set_index
	].ability_pool_indices;
	runtime_entries.reserve(ability_indices.size());
	for (const int32_t compiled_ability_index : ability_indices) {
		RuntimeAbilityEntry entry;
		entry.compiled_ability_index = compiled_ability_index;
		entry.handle = value.next_ability_handle++;
		runtime_entries.push_back(entry);
	}
	value.card_runtime_abilities.push_back(runtime_entries);
	value.card_runtime_suppression_batches.push_back({});
	value.card_reveal_codes.push_back(static_cast<uint8_t>(recipient_owner == 1 ? 3 : 4));
	value.card_suppression_set_indices.push_back(-1);
	value.card_hand_slots.push_back(hand_slot);
	value.card_ids.push_back(card_id);
	recipient_hand.push_back(new_card_index);

	const StringName source_instance_id = (
		action_context.ability_source_card_index >= 0
		&& action_context.ability_source_card_index < static_cast<int32_t>(value.card_instance_ids.size())
		? value.card_instance_ids[action_context.ability_source_card_index]
		: StringName()
	);
	Dictionary returned;
	returned["type"] = StringName("card_returned_to_hand");
	returned["source_cell"] = source_current_cell;
	returned["source_instance_id"] = source_instance_id;
	returned["target_cell"] = target_cell;
	returned["old_instance_id"] = value.card_instance_ids[target_card_index];
	returned["owner_id"] = recipient_owner;
	returned["card_id"] = card_id;
	returned["instance_id"] = new_instance_id;
	returned["logical_hand_index"] = static_cast<int32_t>(recipient_hand.size()) - 1;
	returned["hand_slot_index"] = hand_slot;
	if (include_presentation_payloads) {
		returned["card"] = restore_runtime_card(value, new_card_index);
	}
	resolution.events.append(returned);

	Dictionary revealed;
	revealed["type"] = StringName("card_revealed");
	revealed["source_cell"] = source_current_cell;
	revealed["source_instance_id"] = source_instance_id;
	revealed["owner_id"] = recipient_owner;
	revealed["observer_owner_id"] = other_owner(recipient_owner);
	revealed["card_id"] = card_id;
	revealed["instance_id"] = new_instance_id;
	revealed["logical_hand_index"] = static_cast<int32_t>(recipient_hand.size()) - 1;
	resolution.events.append(revealed);
	Resolution hand_change = resolve_difficulty_hand_change(
		value,
		recipient_owner,
		recipient_previous_hand_size,
		static_cast<int32_t>(recipient_hand.size()),
		source_current_cell,
		exile_stack
	);
	if (!hand_change.supported) {
		resolution.reason = hand_change.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	append_resolution(resolution, hand_change);
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::resolve_movement_event(
	NativeState &value,
	const StringName &event_id,
	int32_t source_cell,
	int32_t origin_cell,
	int32_t target_cell,
	int32_t moving_card_index,
	int32_t moving_owner,
	std::vector<int32_t> &exile_stack
) const {
	EventContext context;
	context.trigger_cell = source_cell;
	context.trigger_card_index = moving_card_index;
	context.trigger_owner = moving_owner;
	context.trigger_zone = 0;
	context.trigger_logical_index = source_cell;
	context.trigger_was_on_board = true;
	context.moving_source_cell = source_cell;
	context.moving_origin_cell = origin_cell;
	context.moving_target_cell = target_cell;
	context.moving_card_index = moving_card_index;
	context.moving_owner = moving_owner;
	return resolve_event(value, event_id, context, exile_stack);
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::move_card_between_cells(
	NativeState &value,
	int32_t source_cell,
	int32_t origin_cell,
	int32_t target_cell,
	int32_t moving_card_index,
	int32_t moving_owner,
	bool resolve_before_event,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	if (
		source_cell < 0
		|| target_cell < 0
		|| source_cell >= static_cast<int32_t>(value.board_card_indices.size())
		|| target_cell >= static_cast<int32_t>(value.board_card_indices.size())
		|| value.board_card_indices[source_cell] != moving_card_index
		|| value.board_owners[source_cell] != moving_owner
		|| value.board_card_indices[target_cell] >= 0
	) return ActionOutcome::NO_EFFECT;

	Resolution movement_resolution;
	if (resolve_before_event) {
		Resolution before = resolve_movement_event(
			value,
			StringName("card_before_moved"),
			source_cell,
			origin_cell,
			target_cell,
			moving_card_index,
			moving_owner,
			exile_stack
		);
		if (!before.supported) {
			resolution.reason = before.reason;
			return ActionOutcome::UNSUPPORTED;
		}
		append_resolution(movement_resolution, before);
		if (
			find_board_card(value, moving_card_index, source_cell) != source_cell
			|| value.board_owners[source_cell] != moving_owner
			|| value.board_card_indices[target_cell] >= 0
		) {
			append_resolution(resolution, movement_resolution);
			return resolution_has_output(movement_resolution)
				? ActionOutcome::APPLIED
				: ActionOutcome::NO_EFFECT;
		}
	}

	const Variant moving_extra = value.board_slot_extras[source_cell];
	value.board_card_indices[source_cell] = -1;
	value.board_owners[source_cell] = 0;
	value.board_slot_extras[source_cell] = Dictionary();
	value.board_card_indices[target_cell] = moving_card_index;
	value.board_owners[target_cell] = static_cast<uint8_t>(moving_owner);
	value.board_slot_extras[target_cell] = moving_extra;

	Dictionary moved;
	moved["type"] = StringName("card_moved");
	moved["source_cell"] = source_cell;
	moved["target_cell"] = target_cell;
	moved["owner_id"] = moving_owner;
	moved["instance_id"] = value.card_instance_ids[moving_card_index];
	movement_resolution.events.append(moved);
	Resolution after = resolve_movement_event(
		value,
		StringName("card_after_moved"),
		target_cell,
		origin_cell,
		target_cell,
		moving_card_index,
		moving_owner,
		exile_stack
	);
	if (!after.supported) {
		resolution.reason = after.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	append_resolution(movement_resolution, after);
	append_resolution(resolution, movement_resolution);
	return ActionOutcome::APPLIED;
}

DuelNativeCompactKernel::ActionOutcome DuelNativeCompactKernel::swap_action_subject_with_ability_source(
	NativeState &value,
	const EventGroup &group,
	const EventContext &event_context,
	const ActionContext &action_context,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	(void)event_context;
	const int32_t source_card_index = group.source_card_index;
	const int32_t target_card_index = action_context.action_subject_card_index;
	if (
		source_card_index < 0
		|| target_card_index < 0
		|| source_card_index == target_card_index
	) return ActionOutcome::NO_EFFECT;
	const int32_t source_owner = action_context.ability_source_owner;
	const int32_t target_owner = action_context.action_subject_owner;
	int32_t source_cell = find_board_card(value, source_card_index, group.source_cell);
	int32_t target_cell = find_board_card(
		value,
		target_card_index,
		action_context.action_subject_logical_index
	);
	if (
		source_cell < 0
		|| target_cell < 0
		|| value.board_owners[source_cell] != source_owner
		|| value.board_owners[target_cell] != target_owner
	) return ActionOutcome::NO_EFFECT;
	bool adjacent = false;
	for (int32_t direction = 0; direction < 4; ++direction) {
		if (neighbor_index(source_cell, direction) == target_cell) {
			adjacent = true;
			break;
		}
	}
	if (!adjacent) return ActionOutcome::NO_EFFECT;

	Resolution source_before = resolve_movement_event(
		value,
		StringName("card_before_moved"),
		source_cell,
		source_cell,
		target_cell,
		source_card_index,
		source_owner,
		exile_stack
	);
	if (!source_before.supported) {
		resolution.reason = source_before.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	if (
		find_board_card(value, source_card_index, source_cell) != source_cell
		|| value.board_owners[source_cell] != source_owner
		|| find_board_card(value, target_card_index, target_cell) != target_cell
		|| value.board_owners[target_cell] != target_owner
	) {
		append_resolution(resolution, source_before);
		return resolution_has_output(source_before)
			? ActionOutcome::APPLIED
			: ActionOutcome::NO_EFFECT;
	}

	const Variant reserved_target_extra = value.board_slot_extras[target_cell];
	value.board_card_indices[target_cell] = -1;
	value.board_owners[target_cell] = 0;
	value.board_slot_extras[target_cell] = Dictionary();

	Resolution swap_resolution;
	append_resolution(swap_resolution, source_before);
	const ActionOutcome source_move_outcome = move_card_between_cells(
		value,
		source_cell,
		source_cell,
		target_cell,
		source_card_index,
		source_owner,
		false,
		exile_stack,
		swap_resolution
	);
	if (source_move_outcome == ActionOutcome::UNSUPPORTED) {
		resolution.reason = swap_resolution.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	if (source_move_outcome != ActionOutcome::APPLIED) {
		append_resolution(resolution, swap_resolution);
		return source_move_outcome;
	}
	if (
		find_board_card(value, source_card_index, target_cell) != target_cell
		|| value.board_owners[target_cell] != source_owner
	) {
		resolution.reason = "First swap leg was invalidated after movement";
		return ActionOutcome::UNSUPPORTED;
	}

	const Variant reserved_source_extra = value.board_slot_extras[target_cell];
	value.board_card_indices[target_cell] = target_card_index;
	value.board_owners[target_cell] = static_cast<uint8_t>(target_owner);
	value.board_slot_extras[target_cell] = reserved_target_extra;
	Resolution target_before = resolve_movement_event(
		value,
		StringName("card_before_moved"),
		target_cell,
		target_cell,
		source_cell,
		target_card_index,
		target_owner,
		exile_stack
	);
	if (!target_before.supported) {
		resolution.reason = target_before.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	if (
		find_board_card(value, target_card_index, target_cell) != target_cell
		|| value.board_owners[target_cell] != target_owner
	) {
		value.board_card_indices[source_cell] = source_card_index;
		value.board_owners[source_cell] = static_cast<uint8_t>(source_owner);
		value.board_slot_extras[source_cell] = reserved_source_extra;
		value.board_card_indices[target_cell] = target_card_index;
		value.board_owners[target_cell] = static_cast<uint8_t>(target_owner);
		value.board_slot_extras[target_cell] = reserved_target_extra;
		return ActionOutcome::NO_EFFECT;
	}
	append_resolution(swap_resolution, target_before);

	const ActionOutcome target_move_outcome = move_card_between_cells(
		value,
		target_cell,
		target_cell,
		source_cell,
		target_card_index,
		target_owner,
		false,
		exile_stack,
		swap_resolution
	);
	if (target_move_outcome == ActionOutcome::UNSUPPORTED) {
		resolution.reason = swap_resolution.reason;
		return ActionOutcome::UNSUPPORTED;
	}
	if (target_move_outcome != ActionOutcome::APPLIED) {
		resolution.reason = "Second swap leg could not move its exact instance";
		return ActionOutcome::UNSUPPORTED;
	}

	value.board_card_indices[target_cell] = source_card_index;
	value.board_owners[target_cell] = static_cast<uint8_t>(source_owner);
	value.board_slot_extras[target_cell] = reserved_source_extra;
	append_resolution(resolution, swap_resolution);
	return ActionOutcome::APPLIED;
}

bool DuelNativeCompactKernel::exile_card(
	NativeState &value,
	int32_t card_index,
	int32_t source_cell,
	int32_t ability_source_card_index,
	bool self_removal,
	const StringName &exile_reason,
	const EventContext &parent_context,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution,
	bool record_exile_index
) const {
	if (card_index < 0 || card_index >= static_cast<int32_t>(value.card_instance_ids.size())) return true;
	if (std::find(exile_stack.begin(), exile_stack.end(), card_index) != exile_stack.end()) return true;
	int32_t initial_zone = -1;
	int32_t initial_owner = 0;
	int32_t initial_index = -1;
	if (!locate_card(value, card_index, initial_zone, initial_owner, initial_index)) return true;
	if (initial_zone != 0 && initial_zone != 1 && initial_zone != 3) return true;

	if (initial_zone == 0 || initial_zone == 1) {
		exile_stack.push_back(card_index);
		EventContext before_context = parent_context;
		before_context.trigger_cell = initial_zone == 0 ? initial_index : -1;
		before_context.trigger_card_index = card_index;
		before_context.trigger_owner = initial_owner;
		before_context.trigger_zone = initial_zone;
		before_context.trigger_logical_index = initial_index;
		before_context.trigger_was_on_board = initial_zone == 0;
		before_context.exile_reason = exile_reason;
		Resolution before = resolve_event(value, StringName("card_before_exiled"), before_context, exile_stack);
		exile_stack.pop_back();
		if (!before.supported) {
			resolution.reason = before.reason;
			return false;
		}
		resolution.events.append_array(before.events);
		resolution.captures.append_array(before.captures);
		resolution.exiles.append_array(before.exiles);
	}

	int32_t zone = -1;
	int32_t current_owner = 0;
	int32_t logical_index = -1;
	if (!locate_card(value, card_index, zone, current_owner, logical_index)) return true;
	if (zone != initial_zone || current_owner != initial_owner || logical_index != initial_index) return true;
	const int32_t previous_hand_size = zone == 1
		? static_cast<int32_t>(value.zones[current_owner - 1].size())
		: -1;
	if (zone == 0) {
		value.board_card_indices[logical_index] = -1;
		value.board_owners[logical_index] = 0;
		if (logical_index < value.board_slot_extras.size()) value.board_slot_extras[logical_index] = Dictionary();
	} else {
		const int32_t zone_index = zone == 1 ? current_owner - 1 : current_owner + 3;
		std::vector<int32_t> &subject_zone = value.zones[zone_index];
		if (logical_index < 0 || logical_index >= static_cast<int32_t>(subject_zone.size()) || subject_zone[logical_index] != card_index) return true;
		subject_zone.erase(subject_zone.begin() + logical_index);
		if (zone == 1) {
			value.card_runtime_flags[card_index] &= static_cast<uint8_t>(~(1 << 7));
			value.card_hand_slots[card_index] = -1;
		}
	}
	int32_t original_owner = value.card_original_owners[card_index];
	if (original_owner != 1 && original_owner != 2) original_owner = current_owner;
	value.zones[original_owner + 5].push_back(card_index);

	Dictionary event;
	event["type"] = StringName("card_exiled");
	event["source_cell"] = source_cell;
	event["source_instance_id"] = ability_source_card_index >= 0 ? value.card_instance_ids[ability_source_card_index] : StringName();
	event["target_cell"] = zone == 0 ? logical_index : -1;
	event["owner_id"] = current_owner;
	event["original_owner"] = original_owner;
	event["instance_id"] = value.card_instance_ids[card_index];
	event["self_removal"] = self_removal;
	event["zone"] = zone == 0 ? StringName("board") : (zone == 1 ? StringName("hand") : StringName("discard"));
	event["logical_index"] = logical_index;
	event["exile_reason"] = exile_reason;
	resolution.events.append(event);
	const int32_t exiled_cell = zone == 0 ? logical_index : -1;
	if (previous_hand_size >= 0) {
		Resolution hand_change = resolve_difficulty_hand_change(
			value,
			current_owner,
			previous_hand_size,
			static_cast<int32_t>(value.zones[current_owner - 1].size()),
			source_cell,
			exile_stack
		);
		if (!hand_change.supported) {
			resolution.reason = hand_change.reason;
			return false;
		}
		append_resolution(resolution, hand_change);
	}

	EventContext after_context = parent_context;
	after_context.trigger_cell = zone == 0 ? logical_index : -1;
	after_context.trigger_card_index = card_index;
	after_context.trigger_owner = current_owner;
	after_context.trigger_zone = zone;
	after_context.trigger_logical_index = logical_index;
	after_context.trigger_was_on_board = zone == 0;
	after_context.exile_reason = exile_reason;
	Resolution after = resolve_event(value, StringName("card_after_exiled"), after_context, exile_stack);
	if (!after.supported) {
		resolution.reason = after.reason;
		return false;
	}
	resolution.events.append_array(after.events);
	resolution.captures.append_array(after.captures);
	resolution.exiles.append_array(after.exiles);
	if (
		include_presentation_payloads
		&& record_exile_index
		&& resolution.exiles.find(exiled_cell) < 0
	) {
		resolution.exiles.append(exiled_cell);
	}
	return true;
}

bool DuelNativeCompactKernel::flip_card(
	NativeState &value,
	int32_t attacker_cell,
	int32_t attacker_card_index,
	int32_t target_cell,
	int32_t target_card_index,
	int32_t new_owner,
	const EventContext &context,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution,
	bool record_capture_index
) const {
	const int32_t current_target_cell = find_board_card(value, target_card_index, target_cell);
	if (current_target_cell < 0 || value.board_owners[current_target_cell] == new_owner) return true;
	std::vector<uint64_t> remove_before_after_flip;
	std::vector<uint64_t> remove_after_after_flip;
	for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[target_card_index].size(); ++ability_index) {
		const CompiledAbility *ability = runtime_ability(value, target_card_index, static_cast<int32_t>(ability_index));
		if (ability == nullptr || ability->retained_on_flip) continue;
		const uint64_t handle = value.card_runtime_abilities[target_card_index][ability_index].handle;
		if (ability->isolated_self_after_flip) {
			remove_after_after_flip.push_back(handle);
		} else {
			remove_before_after_flip.push_back(handle);
		}
	}
	value.board_owners[current_target_cell] = static_cast<uint8_t>(new_owner);
	Dictionary flipped;
	flipped["type"] = StringName("card_flipped");
	flipped["source_cell"] = attacker_cell;
	flipped["target_cell"] = current_target_cell;
	flipped["owner_id"] = new_owner;
	flipped["instance_id"] = value.card_instance_ids[target_card_index];
	resolution.events.append(flipped);
	clear_runtime_suppression(value, target_card_index);
	for (const uint64_t ability_handle : remove_before_after_flip) {
		remove_ability_with_event(value, target_card_index, ability_handle, attacker_cell, attacker_card_index, current_target_cell, new_owner, resolution.events);
	}
	if (include_presentation_payloads && record_capture_index) {
		resolution.captures.append(current_target_cell);
	}
	EventContext after_context = context;
	after_context.trigger_cell = current_target_cell;
	after_context.trigger_card_index = target_card_index;
	after_context.trigger_previous_owner = context.trigger_owner;
	after_context.trigger_owner = context.trigger_owner;
	after_context.trigger_zone = 0;
	after_context.trigger_logical_index = current_target_cell;
	Resolution after = resolve_event(value, StringName("card_after_flipped"), after_context, exile_stack);
	if (!after.supported) {
		resolution.reason = after.reason;
		return false;
	}
	resolution.events.append_array(after.events);
	resolution.captures.append_array(after.captures);
	resolution.exiles.append_array(after.exiles);
	const int32_t post_cell = find_board_card(value, target_card_index, current_target_cell);
	if (post_cell >= 0) {
		for (const uint64_t ability_handle : remove_after_after_flip) {
			remove_ability_with_event(value, target_card_index, ability_handle, attacker_cell, attacker_card_index, post_cell, new_owner, resolution.events);
		}
	}
	return true;
}

Dictionary DuelNativeCompactKernel::restore_runtime_card(
	const NativeState &value,
	int32_t card_index
) const {
	const int32_t template_index = value.card_template_indices[card_index];
	Dictionary card = Dictionary(value.card_template_pool[template_index]).duplicate(true);
	const uint8_t flags = value.card_runtime_flags[card_index];
	if ((flags & (1 << 0)) != 0) {
		card["instance_id"] = value.card_instance_ids[card_index];
	}
	if ((flags & (1 << 1)) != 0) {
		Array powers;
		for (int32_t direction = 0; direction < 4; ++direction) {
			powers.append(value.card_powers[card_index * 4 + direction]);
		}
		card["powers"] = powers;
	}
	if ((flags & (1 << 2)) != 0) {
		card["original_owner"] = value.card_original_owners[card_index];
	}
	if ((flags & (1 << 3)) != 0) {
		card["ki"] = value.card_ki[card_index];
	}
	if ((flags & (1 << 4)) != 0) {
		Array active_abilities;
		for (const RuntimeAbilityEntry &entry : value.card_runtime_abilities[card_index]) {
			if (
				entry.compiled_ability_index >= 0
				&& entry.compiled_ability_index < static_cast<int32_t>(ability_declaration_pool.size())
			) {
				active_abilities.append(ability_declaration_pool[entry.compiled_ability_index]);
			}
		}
		card["active_abilities"] = active_abilities;
	}
	if ((flags & (1 << 5)) != 0) {
		Array audiences;
		switch (value.card_reveal_codes[card_index]) {
			case 1:
				audiences.append(1);
				break;
			case 2:
				audiences.append(2);
				break;
			case 3:
				audiences.append(1);
				audiences.append(2);
				break;
			case 4:
				audiences.append(2);
				audiences.append(1);
				break;
			default:
				break;
		}
		card["revealed_to_owner_ids"] = audiences;
	}
	if ((flags & (1 << 6)) != 0) {
		card["temporary_suppression_batches"] = materialize_suppression_batches(
			value,
			card_index
		);
	}
	if ((flags & (1 << 7)) != 0) {
		card["hand_slot_index"] = value.card_hand_slots[card_index];
	}
	return card;
}

int32_t DuelNativeCompactKernel::leftmost_empty_hand_slot(
	const NativeState &value,
	int32_t owner_id
) const {
	bool occupied[5] = {false, false, false, false, false};
	for (const int32_t card_index : value.zones[owner_id - 1]) {
		const int32_t slot = value.card_hand_slots[card_index];
		if (slot >= 0 && slot < 5) {
			occupied[slot] = true;
		}
	}
	for (int32_t slot = 0; slot < 5; ++slot) {
		if (!occupied[slot]) {
			return slot;
		}
	}
	return -1;
}

bool DuelNativeCompactKernel::owner_has_legal_play(
	const NativeState &value,
	int32_t owner_id
) const {
	const int32_t hand_zone_index = owner_id - 1;
	if (
		hand_zone_index < 0
		|| hand_zone_index >= static_cast<int32_t>(value.zones.size())
		|| value.zones[hand_zone_index].empty()
	) {
		return false;
	}
	return std::find(
		value.board_card_indices.begin(),
		value.board_card_indices.end(),
		-1
	) != value.board_card_indices.end();
}

bool DuelNativeCompactKernel::owner_has_legal_action(
	const NativeState &value,
	int32_t owner_id
) const {
	if (owner_has_legal_play(value, owner_id)) return true;
	if (owner_id == value.scalars[0] && value.scalars[5] > 0) return false;
	return board_has_enabled_activation_for_owner(value, owner_id);
}

bool DuelNativeCompactKernel::is_terminal(const NativeState &value) const {
	if (value.scalars[5] > 0 && owner_has_legal_play(value, value.scalars[0])) {
		return false;
	}
	if (value.scalars[1] >= value.scalars[7]) {
		return true;
	}
	const Array repetition_hashes = value.side_payload.get("repetition_hashes", Array());
	Dictionary counts;
	for (int64_t index = 0; index < repetition_hashes.size(); ++index) {
		const String signature = repetition_hashes[index];
		const int64_t count = static_cast<int64_t>(counts.get(signature, 0)) + 1;
		if (count >= 5) {
			return true;
		}
		counts[signature] = count;
	}
	if (std::find(value.board_card_indices.begin(), value.board_card_indices.end(), -1)
		== value.board_card_indices.end()) {
		return true;
	}
	return !owner_has_legal_action(value, 1) && !owner_has_legal_action(value, 2);
}

void DuelNativeCompactKernel::apply_extra_card_play_requests(
	NativeState &value,
	int32_t moving_owner,
	const std::vector<Resolution::ExtraPlayRequest> &requests,
	Resolution &resolution
) const {
	if (value.scalars[13] != 0) return;
	Array source_instance_ids;
	for (const Resolution::ExtraPlayRequest &request : requests) {
		if (
			request.owner_id != moving_owner
			|| request.amount <= 0
			|| request.source_card_index < 0
			|| request.source_card_index >= static_cast<int32_t>(value.card_instance_ids.size())
		) continue;
		source_instance_ids.append(value.card_instance_ids[request.source_card_index]);
	}
	if (source_instance_ids.is_empty()) return;
	value.scalars[13] = 1;
	value.scalars[5] = std::max(value.scalars[5], 1);
	Dictionary granted;
	granted["type"] = StringName("extra_card_play_granted");
	granted["owner_id"] = moving_owner;
	granted["amount"] = 1;
	granted["request_count"] = source_instance_ids.size();
	granted["source_instance_ids"] = source_instance_ids;
	resolution.events.append(granted);
}

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::resolve_before_full_board_end(
	NativeState &value,
	std::vector<int32_t> &exile_stack
) const {
	Resolution resolution;
	if (
		std::find(value.board_card_indices.begin(), value.board_card_indices.end(), -1)
		!= value.board_card_indices.end()
	) return resolution;
	int32_t owner_one_count = 0;
	int32_t owner_two_count = 0;
	for (const uint8_t owner : value.board_owners) {
		if (owner == 1) owner_one_count += 1;
		else if (owner == 2) owner_two_count += 1;
	}
	EventContext context;
	if (owner_one_count > owner_two_count) context.winning_owners.push_back(1);
	else if (owner_two_count > owner_one_count) context.winning_owners.push_back(2);
	return resolve_event(value, StringName("before_duel_end"), context, exile_stack);
}

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::finish_action(
	NativeState &value,
	int32_t moving_owner,
	int32_t played_card_index,
	const std::vector<Resolution::ExtraPlayRequest> &extra_play_requests,
	std::vector<int32_t> &exile_stack
) const {
	Resolution resolution;
	if (
		played_card_index >= 0
		&& played_card_index < static_cast<int32_t>(value.card_instance_ids.size())
	) {
		Dictionary last_hand_plays = value.side_payload.get(
			"last_hand_play_by_owner",
			Dictionary()
		);
		last_hand_plays = last_hand_plays.duplicate(true);
		Dictionary last_hand_play;
		last_hand_play["played_by_owner_id"] = moving_owner;
		last_hand_play["card_id"] = value.card_ids[played_card_index];
		last_hand_play["instance_id"] = value.card_instance_ids[played_card_index];
		last_hand_plays[moving_owner] = last_hand_play;
		value.side_payload["last_hand_play_by_owner"] = last_hand_plays;
	}

	value.scalars[1] += 1;
	value.scalars[12] += 1;
	apply_extra_card_play_requests(
		value,
		moving_owner,
		extra_play_requests,
		resolution
	);
	if (value.scalars[5] > 0 && owner_has_legal_play(value, moving_owner)) {
		value.scalars[0] = moving_owner;
		return resolution;
	}
	value.scalars[5] = 0;

	if (value.scalars[6] == 0) {
		EventContext end_context;
		end_context.turn_owner = moving_owner;
		Resolution end_resolution = resolve_event(
			value,
			StringName("end_owner_turn"),
			end_context,
			exile_stack
		);
		if (!end_resolution.supported) return end_resolution;
		append_resolution(resolution, end_resolution);
		value.scalars[6] = 1;
		apply_extra_card_play_requests(
			value,
			moving_owner,
			end_resolution.extra_play_requests,
			resolution
		);
	}

	Resolution before_end = resolve_before_full_board_end(value, exile_stack);
	if (!before_end.supported) return before_end;
	append_resolution(resolution, before_end);
	if (value.scalars[5] > 0 && owner_has_legal_play(value, moving_owner)) {
		value.scalars[0] = moving_owner;
		return resolution;
	}
	value.scalars[5] = 0;

	append_resolution(resolution, complete_owner_turn_boundary(value));
	if (is_terminal(value)) return resolution;

	int32_t previous_owner = moving_owner;
	while (true) {
		const int32_t turn_owner = other_owner(previous_owner);
		value.scalars[0] = turn_owner;
		EventContext start_context;
		start_context.turn_owner = turn_owner;
		Resolution start_resolution = resolve_event(
			value,
			StringName("start_owner_turn"),
			start_context,
			exile_stack
		);
		if (!start_resolution.supported) return start_resolution;
		append_resolution(resolution, start_resolution);
		if (owner_has_legal_action(value, turn_owner)) return resolution;

		EventContext empty_end_context;
		empty_end_context.turn_owner = turn_owner;
		Resolution empty_end_resolution = resolve_event(
			value,
			StringName("end_owner_turn"),
			empty_end_context,
			exile_stack
		);
		if (!empty_end_resolution.supported) return empty_end_resolution;
		append_resolution(resolution, empty_end_resolution);
		value.scalars[6] = 1;
		apply_extra_card_play_requests(
			value,
			turn_owner,
			empty_end_resolution.extra_play_requests,
			resolution
		);
		Resolution empty_before_end = resolve_before_full_board_end(value, exile_stack);
		if (!empty_before_end.supported) return empty_before_end;
		append_resolution(resolution, empty_before_end);
		if (value.scalars[5] > 0 && owner_has_legal_play(value, turn_owner)) {
			return resolution;
		}
		value.scalars[5] = 0;
		append_resolution(resolution, complete_owner_turn_boundary(value));
		if (is_terminal(value)) return resolution;
		previous_owner = turn_owner;
	}
	return resolution;
}

DuelNativeCompactKernel::Resolution DuelNativeCompactKernel::complete_owner_turn_boundary(
	NativeState &value
) const {
	Resolution resolution = restore_temporary_abilities(value, value.scalars[2]);
	value.scalars[2] += 1;
	value.scalars[3] = 0;
	value.scalars[4] = 0;
	value.scalars[6] = 0;
	value.scalars[13] = 0;
	Array repetition_hashes = value.side_payload.get("repetition_hashes", Array());
	repetition_hashes = repetition_hashes.duplicate(true);
	repetition_hashes.append(board_repetition_signature(value));
	value.side_payload["repetition_hashes"] = repetition_hashes;
	return resolution;
}

String DuelNativeCompactKernel::board_repetition_signature(const NativeState &value) const {
	String result;
	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		if (cell > 0) {
			result += "|";
		}
		const int32_t card_index = value.board_card_indices[cell];
		if (card_index < 0) {
			result += "empty";
			continue;
		}
		const String card_id = String(value.card_ids[card_index]);
		const CharString card_id_bytes = card_id.utf8();
		result += "card:";
		result += String::num_int64(card_id_bytes.length());
		result += ":";
		result += bytes_to_hex(card_id_bytes);
		result += ":owner:";
		result += String::num_int64(value.board_owners[cell]);
	}
	return result;
}

Dictionary DuelNativeCompactKernel::to_variant_payload(const NativeState &value) const {
	Dictionary payload;
	payload["format_version"] = 1;
	payload["scalars"] = to_packed_int32_array(value.scalars);
	payload["board_card_indices"] = to_packed_int32_array(value.board_card_indices);
	payload["board_owners"] = to_packed_byte_array(value.board_owners);
	payload["board_slot_extras"] = value.board_slot_extras;
	Array zones;
	for (const std::vector<int32_t> &zone : value.zones) {
		zones.append(to_packed_int32_array(zone));
	}
	payload["zones"] = zones;
	Array instance_ids;
	for (const StringName &instance_id : value.card_instance_ids) {
		instance_ids.append(instance_id);
	}
	payload["card_instance_ids"] = instance_ids;
	payload["card_template_indices"] = to_packed_int32_array(value.card_template_indices);
	payload["card_runtime_flags"] = to_packed_byte_array(value.card_runtime_flags);
	payload["card_powers"] = to_packed_int32_array(value.card_powers);
	payload["card_original_owners"] = to_packed_byte_array(value.card_original_owners);
	payload["card_ki"] = to_packed_int32_array(value.card_ki);
	Array materialized_pool = value.active_ability_set_pool.duplicate();
	std::vector<int32_t> materialized_indices = value.card_active_ability_set_indices;
	for (size_t card_index = 0; card_index < value.card_instance_ids.size(); ++card_index) {
		Array derived;
		for (const RuntimeAbilityEntry &entry : value.card_runtime_abilities[card_index]) {
			if (
				entry.compiled_ability_index >= 0
				&& entry.compiled_ability_index < static_cast<int32_t>(ability_declaration_pool.size())
			) {
				derived.append(ability_declaration_pool[entry.compiled_ability_index]);
			}
		}
		int32_t derived_index = -1;
		for (int64_t pool_index = 0; pool_index < materialized_pool.size(); ++pool_index) {
			if (Variant(materialized_pool[pool_index]) == Variant(derived)) {
				derived_index = static_cast<int32_t>(pool_index);
				break;
			}
		}
		if (derived_index < 0) {
			derived_index = static_cast<int32_t>(materialized_pool.size());
			materialized_pool.append(derived);
		}
		materialized_indices[card_index] = derived_index;
	}
	payload["card_active_ability_set_indices"] = to_packed_int32_array(materialized_indices);
	payload["card_reveal_codes"] = to_packed_byte_array(value.card_reveal_codes);
	Array materialized_suppression_pool = value.suppression_set_pool.duplicate();
	std::vector<int32_t> materialized_suppression_indices = value.card_suppression_set_indices;
	for (size_t card_index = 0; card_index < value.card_instance_ids.size(); ++card_index) {
		if ((value.card_runtime_flags[card_index] & (1 << 6)) == 0) {
			materialized_suppression_indices[card_index] = -1;
			continue;
		}
		const Array derived = materialize_suppression_batches(
			value,
			static_cast<int32_t>(card_index)
		);
		int32_t derived_index = -1;
		for (int64_t pool_index = 0; pool_index < materialized_suppression_pool.size(); ++pool_index) {
			if (Variant(materialized_suppression_pool[pool_index]) == Variant(derived)) {
				derived_index = static_cast<int32_t>(pool_index);
				break;
			}
		}
		if (derived_index < 0) {
			derived_index = static_cast<int32_t>(materialized_suppression_pool.size());
			materialized_suppression_pool.append(derived);
		}
		materialized_suppression_indices[card_index] = derived_index;
	}
	payload["card_suppression_set_indices"] = to_packed_int32_array(
		materialized_suppression_indices
	);
	payload["card_hand_slots"] = to_packed_int32_array(value.card_hand_slots);
	payload["card_template_pool"] = value.card_template_pool;
	payload["active_ability_set_pool"] = materialized_pool;
	payload["suppression_set_pool"] = materialized_suppression_pool;
	payload["fresh_card_prototypes"] = value.fresh_card_prototype_pool;
	payload["empty_deck_draw_prototype_index"] = value.empty_deck_draw_prototype_index;
	payload["side_payload"] = value.side_payload;
	return payload;
}

uint64_t DuelNativeCompactKernel::checksum(const NativeState &value) const {
	uint64_t hash = 1469598103934665603ULL;
	hash_values(hash, value.scalars);
	hash_values(hash, value.board_card_indices);
	hash_values(hash, value.board_owners);
	for (const std::vector<int32_t> &zone : value.zones) {
		hash_values(hash, zone);
	}
	hash_values(hash, value.card_template_indices);
	hash_values(hash, value.card_runtime_flags);
	hash_values(hash, value.card_powers);
	hash_values(hash, value.card_original_owners);
	hash_values(hash, value.card_ki);
	for (const std::vector<RuntimeAbilityEntry> &abilities : value.card_runtime_abilities) {
		for (const RuntimeAbilityEntry &entry : abilities) {
			hash ^= static_cast<uint64_t>(entry.compiled_ability_index);
			hash *= 1099511628211ULL;
		}
	}
	for (const std::vector<RuntimeSuppressionBatch> &batches : value.card_runtime_suppression_batches) {
		for (const RuntimeSuppressionBatch &batch : batches) {
			hash ^= static_cast<uint64_t>(batch.expires_after_turn);
			hash *= 1099511628211ULL;
			for (const RuntimeSuppressionEntry &entry : batch.entries) {
				hash ^= static_cast<uint64_t>(entry.original_index);
				hash *= 1099511628211ULL;
				hash ^= static_cast<uint64_t>(entry.compiled_ability_index);
				hash *= 1099511628211ULL;
			}
		}
	}
	hash_values(hash, value.card_reveal_codes);
	hash_values(hash, value.card_suppression_set_indices);
	hash_values(hash, value.card_hand_slots);
	for (const StringName &instance_id : value.card_instance_ids) {
		hash ^= static_cast<uint64_t>(instance_id.hash());
		hash *= 1099511628211ULL;
	}
	return hash;
}

} // namespace godot
