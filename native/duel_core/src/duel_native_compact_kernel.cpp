#include "duel_native_compact_kernel.h"

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <limits>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/char_string.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {
namespace {

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
	result["checksum"] = static_cast<int64_t>(checksum(state) & 0x7fffffffffffffffULL);
	return result;
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

	String support_reason;
	if (!validate_play_support(state, support_reason)) {
		result["reason"] = support_reason;
		return result;
	}
	result["supported"] = true;

	const int32_t moving_owner = state.scalars[0];
	const int32_t hand_zone_index = moving_owner - 1;
	if (hand_zone_index < 0 || hand_zone_index >= static_cast<int32_t>(state.zones.size())) {
		result["reason"] = "Active owner has no compact hand zone";
		return result;
	}
	const std::vector<int32_t> &source_hand = state.zones[hand_zone_index];
	if (hand_index < 0 || hand_index >= static_cast<int64_t>(source_hand.size())) {
		result["reason"] = "Hand index is outside the active owner's hand";
		return result;
	}
	if (target_cell < 0 || target_cell >= static_cast<int64_t>(state.board_card_indices.size())) {
		result["reason"] = "Target cell is outside the board";
		return result;
	}
	if (state.board_card_indices[static_cast<size_t>(target_cell)] != -1) {
		result["reason"] = "Target board cell is occupied";
		return result;
	}
	const int32_t played_card_index = source_hand[static_cast<size_t>(hand_index)];
	if (played_card_index < 0 || played_card_index >= static_cast<int32_t>(state.card_instance_ids.size())) {
		result["reason"] = "Hand references an invalid card index";
		return result;
	}
	const StringName played_instance_id = state.card_instance_ids[played_card_index];
	if (!expected_instance_id.is_empty() && expected_instance_id != played_instance_id) {
		result["reason"] = "Expected instance ID does not match the hand card";
		return result;
	}
	std::vector<int32_t> draw_counts;
	if (!validate_action_rule_support(
			state,
			played_card_index,
			static_cast<int32_t>(target_cell),
			draw_counts,
			support_reason
		)) {
		result["supported"] = false;
		result["reason"] = support_reason;
		return result;
	}

	NativeState next = state;
	next.board_slot_extras = state.board_slot_extras.duplicate(true);
	next.side_payload = state.side_payload.duplicate(true);
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

	Array events;
	Dictionary placed_event;
	placed_event["type"] = StringName("card_placed");
	placed_event["source_cell"] = target_cell;
	placed_event["target_cell"] = target_cell;
	placed_event["owner_id"] = moving_owner;
	placed_event["instance_id"] = played_instance_id;
	events.append(placed_event);

	const int32_t deck_zone_index = moving_owner + 1;
	std::vector<int32_t> &next_deck = next.zones[deck_zone_index];
	for (const int32_t requested_draw_count : draw_counts) {
		Dictionary ability_event;
		ability_event["type"] = StringName("ability_triggered");
		ability_event["source_cell"] = target_cell;
		ability_event["source_instance_id"] = played_instance_id;
		ability_event["source_owner_id"] = moving_owner;
		events.append(ability_event);

		for (int32_t draw_index = 0; draw_index < requested_draw_count; ++draw_index) {
			if (next_hand.size() >= 5) {
				break;
			}
			const int32_t drawn_card_index = next_deck.front();
			next_deck.erase(next_deck.begin());
			const int32_t hand_slot_index = leftmost_empty_hand_slot(next, moving_owner);
			if (hand_slot_index < 0) {
				break;
			}
			next.card_runtime_flags[drawn_card_index] |= static_cast<uint8_t>(1 << 7);
			next.card_hand_slots[drawn_card_index] = hand_slot_index;
			next_hand.push_back(drawn_card_index);
			const int32_t logical_hand_index = static_cast<int32_t>(next_hand.size()) - 1;

			Dictionary draw_event;
			draw_event["type"] = StringName("card_drawn");
			draw_event["source_cell"] = target_cell;
			draw_event["owner_id"] = moving_owner;
			draw_event["card_id"] = next.card_ids[drawn_card_index];
			draw_event["instance_id"] = next.card_instance_ids[drawn_card_index];
			draw_event["logical_hand_index"] = logical_hand_index;
			draw_event["hand_slot_index"] = hand_slot_index;
			draw_event["card"] = restore_runtime_card(next, drawn_card_index);
			events.append(draw_event);
		}
	}

	Array captures;
	if (next.scalars[moving_owner == 1 ? 3 : 4] < 20) {
		static constexpr int32_t opposite[4] = {2, 3, 0, 1};
		std::vector<int32_t> target_cells;
		for (int32_t direction = 0; direction < 4; ++direction) {
			const int32_t attacked_cell = neighbor_index(static_cast<int32_t>(target_cell), direction);
			if (attacked_cell < 0) {
				continue;
			}
			const int32_t attacked_card_index = next.board_card_indices[attacked_cell];
			if (
				attacked_card_index < 0
				|| next.board_owners[attacked_cell] == moving_owner
			) {
				continue;
			}
			const int32_t attacking_power = next.card_powers[played_card_index * 4 + direction];
			const int32_t defending_power = next.card_powers[
				attacked_card_index * 4 + opposite[direction]
			];
			if (attacking_power > defending_power) {
				target_cells.push_back(attacked_cell);
			}
		}
		if (!target_cells.empty()) {
			next.scalars[moving_owner == 1 ? 3 : 4] += 1;
		}
		for (const int32_t attacked_cell : target_cells) {
			const int32_t attacked_card_index = next.board_card_indices[attacked_cell];
			const int32_t attacked_owner = next.board_owners[attacked_cell];
			const StringName attacked_instance_id = next.card_instance_ids[attacked_card_index];

			Dictionary attack_event;
			attack_event["type"] = StringName("attack_started");
			attack_event["source_cell"] = target_cell;
			attack_event["source_instance_id"] = played_instance_id;
			attack_event["source_owner_id"] = moving_owner;
			attack_event["target_cell"] = attacked_cell;
			attack_event["target_instance_id"] = attacked_instance_id;
			attack_event["target_owner_id"] = attacked_owner;
			attack_event["attack_reason"] = StringName("summon_standard_attack");
			events.append(attack_event);

			next.board_owners[attacked_cell] = static_cast<uint8_t>(moving_owner);
			captures.append(attacked_cell);
			Dictionary flip_event;
			flip_event["type"] = StringName("card_flipped");
			flip_event["source_cell"] = target_cell;
			flip_event["target_cell"] = attacked_cell;
			flip_event["owner_id"] = moving_owner;
			flip_event["instance_id"] = attacked_instance_id;
			events.append(flip_event);
		}
	}

	Dictionary last_hand_plays = next.side_payload.get(
		"last_hand_play_by_owner",
		Dictionary()
	);
	last_hand_plays = last_hand_plays.duplicate(true);
	Dictionary last_hand_play;
	last_hand_play["played_by_owner_id"] = moving_owner;
	last_hand_play["card_id"] = next.card_ids[played_card_index];
	last_hand_play["instance_id"] = played_instance_id;
	last_hand_plays[moving_owner] = last_hand_play;
	next.side_payload["last_hand_play_by_owner"] = last_hand_plays;

	next.scalars[1] += 1;
	next.scalars[12] += 1;
	next.scalars[6] = 1;
	complete_owner_turn_boundary(next);
	if (!is_terminal(next)) {
		int32_t previous_owner = moving_owner;
		while (true) {
			const int32_t turn_owner = other_owner(previous_owner);
			next.scalars[0] = turn_owner;
			if (owner_has_legal_play(next, turn_owner)) {
				break;
			}
			next.scalars[6] = 1;
			complete_owner_turn_boundary(next);
			if (is_terminal(next)) {
				break;
			}
			previous_owner = turn_owner;
		}
	}

	result["valid"] = true;
	result["reason"] = String();
	result["captures"] = captures;
	result["events"] = events;
	result["payload"] = to_variant_payload(next);
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
	if (state.scalars.size() != 13) {
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
	return true;
}

void DuelNativeCompactKernel::compile_ability_sets() {
	compiled_ability_sets.clear();
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
			const Variant ability_value = abilities[ability_index];
			if (ability_value.get_type() != Variant::DICTIONARY) {
				compiled.declaration_valid = false;
				continue;
			}
			const Dictionary ability = ability_value;
			if (ability.has("activation")) {
				const Variant activation_value = ability["activation"];
				if (activation_value.get_type() != Variant::DICTIONARY) {
					compiled.declaration_valid = false;
				} else if (!Dictionary(activation_value).is_empty()) {
					compiled.has_activation = true;
				}
			}
			if (ability.has("modifiers")) {
				const Variant modifiers_value = ability["modifiers"];
				if (modifiers_value.get_type() != Variant::ARRAY) {
					compiled.declaration_valid = false;
				} else if (!Array(modifiers_value).is_empty()) {
					compiled.has_modifiers = true;
				}
			}
			const Variant triggers_value = ability.get("triggers", Array());
			if (triggers_value.get_type() != Variant::ARRAY) {
				compiled.declaration_valid = false;
				continue;
			}
			const Array triggers = triggers_value;
			for (int64_t trigger_index = 0; trigger_index < triggers.size(); ++trigger_index) {
				CompiledTriggerRule compiled_rule;
				const Variant rule_value = triggers[trigger_index];
				if (rule_value.get_type() != Variant::DICTIONARY) {
					compiled.declaration_valid = false;
					compiled.triggers.push_back(compiled_rule);
					continue;
				}
				const Dictionary rule = rule_value;
				compiled_rule.event_id = rule.get("event", StringName());
				const Variant conditions_value = rule.get("conditions", Array());
				const Variant actions_value = rule.get("actions", Array());
				if (
					compiled_rule.event_id == StringName("card_after_summoned")
					&& rule.size() == 3
					&& conditions_value.get_type() == Variant::ARRAY
					&& actions_value.get_type() == Variant::ARRAY
				) {
					const Array conditions = conditions_value;
					const Array actions = actions_value;
					if (conditions.size() == 1 && actions.size() == 1) {
						const Variant condition_value = conditions[0];
						const Variant action_value = actions[0];
						if (
							condition_value.get_type() == Variant::DICTIONARY
							&& action_value.get_type() == Variant::DICTIONARY
						) {
							const Dictionary condition = condition_value;
							const Dictionary action = action_value;
							const Variant amount_value = action.get("amount", 0);
							if (
								condition.size() == 1
								&& StringName(condition.get("type", StringName()))
									== StringName("trigger_card_is_self")
								&& action.size() == 2
								&& StringName(action.get("type", StringName()))
									== StringName("draw_cards")
								&& amount_value.get_type() == Variant::INT
								&& static_cast<int64_t>(amount_value) > 0
								&& static_cast<int64_t>(amount_value)
									<= std::numeric_limits<int32_t>::max()
							) {
								compiled_rule.supports_self_after_summoned_draw = true;
								compiled_rule.draw_count = static_cast<int32_t>(
									static_cast<int64_t>(amount_value)
								);
							}
						}
					}
				}
				compiled.triggers.push_back(compiled_rule);
			}
		}
		compiled_ability_sets.push_back(compiled);
	}
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
	if (value.scalars[5] != 0 || value.scalars[6] != 0) {
		reason = "Play transition does not cover extra plays or a partially resolved turn end";
		return false;
	}
	if (value.scalars[8] != 0 || value.scalars[9] != 0) {
		reason = "Play transition does not cover pending hand-play suppression";
		return false;
	}
	if (value.scalars[10] >= 8) {
		reason = "Play transition does not cover difficulty-eight or difficulty-nine hand rules";
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
		for (int32_t direction = 0; direction < 4; ++direction) {
			if (value.card_powers[card_index * 4 + direction] < 0) {
				reason = "Play transition does not cover special negative powers";
				return false;
			}
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
		if ((value.card_runtime_flags[card_index] & (1 << 6)) != 0) {
			const int32_t suppression_index = value.card_suppression_set_indices[card_index];
			if (
				suppression_index < 0
				|| suppression_index >= value.suppression_set_pool.size()
				|| Variant(value.suppression_set_pool[suppression_index]).get_type() != Variant::ARRAY
				|| !Array(value.suppression_set_pool[suppression_index]).is_empty()
			) {
				reason = "Play transition does not cover temporary ability suppression";
				return false;
			}
		}
	}
	return true;
}

bool DuelNativeCompactKernel::validate_action_rule_support(
	const NativeState &value,
	int32_t played_card_index,
	int32_t target_cell,
	std::vector<int32_t> &draw_counts,
	String &reason
) const {
	draw_counts.clear();
	const int32_t moving_owner = value.scalars[0];
	const bool source_enabled = card_effects_enabled(value, played_card_index, moving_owner);
	const int32_t played_set_index = value.card_active_ability_set_indices[played_card_index];
	const CompiledAbilitySet &played_set = compiled_ability_sets[played_set_index];
	if (source_enabled && card_has_enabled_modifiers(value, played_card_index, moving_owner)) {
		reason = "Play transition does not cover active board modifiers";
		return false;
	}
	if (
		source_enabled
		&& card_has_enabled_event(
			value,
			played_card_index,
			moving_owner,
			StringName("card_before_summoned")
		)
	) {
		reason = "Played card has an unsupported before-summoned rule";
		return false;
	}

	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		const int32_t card_index = value.board_card_indices[cell];
		if (card_index < 0) {
			continue;
		}
		const int32_t owner_id = value.board_owners[cell];
		if (card_has_enabled_modifiers(value, card_index, owner_id)) {
			reason = "Play transition does not cover active board modifiers";
			return false;
		}
	}

	if (
		board_has_enabled_event(value, StringName("card_summoned"))
		|| (source_enabled && card_has_enabled_event(
			value,
			played_card_index,
			moving_owner,
			StringName("card_summoned")
		))
	) {
		reason = "Play transition does not cover summoned-event rules";
		return false;
	}

	if (source_enabled) {
		for (const CompiledTriggerRule &rule : played_set.triggers) {
			if (rule.event_id != StringName("card_after_summoned")) {
				continue;
			}
			if (!rule.supports_self_after_summoned_draw) {
				reason = "Played card has an unsupported after-summoned rule";
				return false;
			}
			draw_counts.push_back(rule.draw_count);
		}
	}
	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		const int32_t card_index = value.board_card_indices[cell];
		if (card_index < 0 || !card_effects_enabled(value, card_index, value.board_owners[cell])) {
			continue;
		}
		const CompiledAbilitySet &ability_set = compiled_ability_sets[
			value.card_active_ability_set_indices[card_index]
		];
		for (const CompiledTriggerRule &rule : ability_set.triggers) {
			if (
				rule.event_id == StringName("card_after_summoned")
				&& !rule.supports_self_after_summoned_draw
			) {
				reason = "Board contains an unsupported after-summoned listener";
				return false;
			}
		}
	}

	int32_t requested_draws = 0;
	for (const int32_t amount : draw_counts) {
		requested_draws += amount;
	}
	const int32_t hand_zone_index = moving_owner - 1;
	const int32_t hand_size_after_play = static_cast<int32_t>(value.zones[hand_zone_index].size()) - 1;
	const int32_t actual_draws = std::min(requested_draws, std::max(0, 5 - hand_size_after_play));
	if (actual_draws > 0) {
		const int32_t deck_zone_index = moving_owner + 1;
		if (static_cast<int32_t>(value.zones[deck_zone_index].size()) < actual_draws) {
			reason = "Draw would require the generated empty-deck fallback card";
			return false;
		}
		const Dictionary audiences_by_owner = value.side_payload.get(
			"future_draw_reveal_audiences",
			Dictionary()
		);
		const Variant audiences_value = audiences_by_owner.get(moving_owner, Array());
		if (
			audiences_value.get_type() != Variant::ARRAY
			|| !Array(audiences_value).is_empty()
		) {
			reason = "Draw would emit unsupported future-reveal events";
			return false;
		}
		if (
			board_has_enabled_event(value, StringName("card_after_drawn"))
			|| (source_enabled && card_has_enabled_event(
				value,
				played_card_index,
				moving_owner,
				StringName("card_after_drawn")
			))
		) {
			reason = "Draw would trigger an unsupported after-drawn listener";
			return false;
		}
	}

	std::vector<int32_t> attacked_cells;
	if (value.scalars[moving_owner == 1 ? 3 : 4] < 20) {
		static constexpr int32_t opposite[4] = {2, 3, 0, 1};
		for (int32_t direction = 0; direction < 4; ++direction) {
			const int32_t attacked_cell = neighbor_index(target_cell, direction);
			if (attacked_cell < 0) {
				continue;
			}
			const int32_t attacked_card_index = value.board_card_indices[attacked_cell];
			if (attacked_card_index < 0 || value.board_owners[attacked_cell] == moving_owner) {
				continue;
			}
			if (
				value.card_powers[played_card_index * 4 + direction]
				> value.card_powers[attacked_card_index * 4 + opposite[direction]]
			) {
				attacked_cells.push_back(attacked_cell);
			}
		}
	}
	if (!attacked_cells.empty()) {
		static const StringName attack_events[] = {
			StringName("card_be_attacked"),
			StringName("card_before_flipped"),
			StringName("card_after_flipped"),
			StringName("card_after_attack"),
		};
		for (const StringName &event_id : attack_events) {
			if (
				board_has_enabled_event(value, event_id)
				|| (source_enabled && card_has_enabled_event(
					value,
					played_card_index,
					moving_owner,
					event_id
				))
			) {
				reason = "Attack would trigger an unsupported reaction rule";
				return false;
			}
		}
		for (const int32_t attacked_cell : attacked_cells) {
			if (card_has_abilities(value, value.board_card_indices[attacked_cell])) {
				reason = "Attack would flip an ability-bearing card";
				return false;
			}
		}
	}

	if (
		board_has_enabled_event(value, StringName("end_owner_turn"))
		|| (source_enabled && card_has_enabled_event(
			value,
			played_card_index,
			moving_owner,
			StringName("end_owner_turn")
		))
	) {
		reason = "Play transition does not cover end-turn trigger rules";
		return false;
	}
	if (
		board_has_enabled_event(value, StringName("start_owner_turn"))
		|| (source_enabled && card_has_enabled_event(
			value,
			played_card_index,
			moving_owner,
			StringName("start_owner_turn")
		))
	) {
		reason = "Play transition does not cover start-turn trigger rules";
		return false;
	}
	const int32_t empty_cells_before = static_cast<int32_t>(std::count(
		value.board_card_indices.begin(),
		value.board_card_indices.end(),
		-1
	));
	if (
		empty_cells_before == 1
		&& (
			board_has_enabled_event(value, StringName("before_duel_end"))
			|| (source_enabled && card_has_enabled_event(
				value,
				played_card_index,
				moving_owner,
				StringName("before_duel_end")
			))
		)
	) {
		reason = "Full board would trigger an unsupported before-duel-end rule";
		return false;
	}

	if (empty_cells_before > 1) {
		const int32_t next_owner = other_owner(moving_owner);
		if (
			value.zones[next_owner - 1].empty()
			&& board_has_enabled_activation_for_owner(value, next_owner)
		) {
			reason = "Empty-turn advancement would require activation legality";
			return false;
		}
		if (
			value.zones[next_owner - 1].empty()
			&& hand_size_after_play + actual_draws == 0
			&& board_has_enabled_activation_for_owner(value, moving_owner)
		) {
			reason = "Terminal detection would require activation legality";
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
	if (card_index < 0 || card_index >= static_cast<int32_t>(value.card_active_ability_set_indices.size())) {
		return false;
	}
	const int32_t set_index = value.card_active_ability_set_indices[card_index];
	return (
		set_index >= 0
		&& set_index < value.active_ability_set_pool.size()
		&& !Array(value.active_ability_set_pool[set_index]).is_empty()
	);
}

bool DuelNativeCompactKernel::card_has_enabled_activation(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id
) const {
	if (!card_effects_enabled(value, card_index, owner_id)) {
		return false;
	}
	return compiled_ability_sets[value.card_active_ability_set_indices[card_index]].has_activation;
}

bool DuelNativeCompactKernel::card_has_enabled_modifiers(
	const NativeState &value,
	int32_t card_index,
	int32_t owner_id
) const {
	if (!card_effects_enabled(value, card_index, owner_id)) {
		return false;
	}
	return compiled_ability_sets[value.card_active_ability_set_indices[card_index]].has_modifiers;
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
	const CompiledAbilitySet &ability_set = compiled_ability_sets[
		value.card_active_ability_set_indices[card_index]
	];
	for (const CompiledTriggerRule &rule : ability_set.triggers) {
		if (rule.event_id == event_id) {
			return true;
		}
	}
	return false;
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
		if (
			card_index >= 0
			&& value.board_owners[cell] == owner_id
			&& card_has_enabled_activation(value, card_index, owner_id)
		) {
			return true;
		}
	}
	return false;
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
		const int32_t set_index = value.card_active_ability_set_indices[card_index];
		card["active_abilities"] = Array(value.active_ability_set_pool[set_index]).duplicate();
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
		const int32_t suppression_index = value.card_suppression_set_indices[card_index];
		card["temporary_suppression_batches"] = Array(
			value.suppression_set_pool[suppression_index]
		).duplicate(true);
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

bool DuelNativeCompactKernel::is_terminal(const NativeState &value) const {
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
	return !owner_has_legal_play(value, 1) && !owner_has_legal_play(value, 2);
}

void DuelNativeCompactKernel::complete_owner_turn_boundary(NativeState &value) const {
	value.scalars[2] += 1;
	value.scalars[3] = 0;
	value.scalars[4] = 0;
	value.scalars[6] = 0;
	Array repetition_hashes = value.side_payload.get("repetition_hashes", Array());
	repetition_hashes = repetition_hashes.duplicate(true);
	repetition_hashes.append(board_repetition_signature(value));
	value.side_payload["repetition_hashes"] = repetition_hashes;
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
	payload["card_active_ability_set_indices"] = to_packed_int32_array(
		value.card_active_ability_set_indices
	);
	payload["card_reveal_codes"] = to_packed_byte_array(value.card_reveal_codes);
	payload["card_suppression_set_indices"] = to_packed_int32_array(
		value.card_suppression_set_indices
	);
	payload["card_hand_slots"] = to_packed_int32_array(value.card_hand_slots);
	payload["card_template_pool"] = value.card_template_pool;
	payload["active_ability_set_pool"] = value.active_ability_set_pool;
	payload["suppression_set_pool"] = value.suppression_set_pool;
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
	hash_values(hash, value.card_active_ability_set_indices);
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
