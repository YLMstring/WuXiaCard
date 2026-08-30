#include "duel_native_compact_kernel.h"

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdlib>
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
	if (!validate_action_rule_support(
			state,
			played_card_index,
			static_cast<int32_t>(target_cell),
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

	std::vector<int32_t> exile_stack;
	const std::vector<int32_t> summon_attack_redirect_sources =
		snapshot_summon_attack_redirect_sources(
			next,
			static_cast<int32_t>(target_cell),
			moving_owner
		);
	EventContext summon_context;
	summon_context.trigger_cell = static_cast<int32_t>(target_cell);
	summon_context.trigger_card_index = played_card_index;
	summon_context.trigger_owner = moving_owner;
	summon_context.trigger_was_on_board = true;
	Resolution after_summoned = resolve_event(
		next,
		StringName("card_after_summoned"),
		summon_context,
		exile_stack
	);
	if (!after_summoned.supported) {
		result["supported"] = false;
		result["reason"] = after_summoned.reason;
		return result;
	}
	events.append_array(after_summoned.events);

	Array captures;
	Array exiles;
	captures.append_array(after_summoned.captures);
	exiles.append_array(after_summoned.exiles);
	const int32_t initial_attack_cell = find_board_card(
		next,
		played_card_index,
		static_cast<int32_t>(target_cell)
	);
	if (
		initial_attack_cell >= 0
		&& next.board_owners[initial_attack_cell] == moving_owner
		&& next.scalars[moving_owner == 1 ? 3 : 4] < 20
		&& !attack_is_prohibited(next, moving_owner)
	) {
		const AttackPolicy requested_policy = get_summon_attack_policy(
			next,
			initial_attack_cell,
			moving_owner,
			summon_attack_redirect_sources
		);
		const AttackPolicy attack_policy = get_standard_attack_policy(
			next,
			initial_attack_cell,
			played_card_index,
			moving_owner,
			requested_policy
		);
		const std::vector<int32_t> target_cells = get_attack_targets(
			next,
			initial_attack_cell,
			attack_policy
		);
		if (!target_cells.empty()) {
			next.scalars[moving_owner == 1 ? 3 : 4] += 1;
		}
		bool attack_started = false;
		bool attack_flipped_enemy = false;
		for (const int32_t locked_cell : target_cells) {
			const int32_t attacker_cell = find_board_card(next, played_card_index, static_cast<int32_t>(target_cell));
			if (attacker_cell < 0 || next.board_owners[attacker_cell] != moving_owner) break;
			const int32_t attacked_card_index = next.board_card_indices[locked_cell];
			if (attacked_card_index < 0) continue;
			const int32_t attacked_cell = locked_cell;
			if (!can_attack_target(next, attacker_cell, attacked_cell, attack_policy, true)) continue;
			const int32_t attacked_owner = next.board_owners[attacked_cell];
			const StringName attacked_instance_id = next.card_instance_ids[attacked_card_index];

			Dictionary attack_event;
			attack_event["type"] = StringName("attack_started");
			attack_event["source_cell"] = attacker_cell;
			attack_event["source_instance_id"] = played_instance_id;
			attack_event["source_owner_id"] = moving_owner;
			attack_event["target_cell"] = attacked_cell;
			attack_event["target_instance_id"] = attacked_instance_id;
			attack_event["target_owner_id"] = attacked_owner;
			attack_event["attack_reason"] = StringName("summon_standard_attack");
			events.append(attack_event);
			attack_started = true;

			EventContext attack_context;
			attack_context.attacker_cell = attacker_cell;
			attack_context.attacker_card_index = played_card_index;
			attack_context.attacker_owner = moving_owner;
			attack_context.attacked_cell = attacked_cell;
			attack_context.attacked_card_index = attacked_card_index;
			attack_context.attacked_owner = attacked_owner;
			attack_context.trigger_cell = attacked_cell;
			attack_context.trigger_card_index = attacked_card_index;
			attack_context.trigger_owner = attacked_owner;
			attack_context.trigger_was_on_board = true;
			attack_context.attack_reason = StringName("summon_standard_attack");
			Resolution be_attacked = resolve_event(next, StringName("card_be_attacked"), attack_context, exile_stack);
			if (!be_attacked.supported) {
				result["supported"] = false;
				result["reason"] = be_attacked.reason;
				return result;
			}
			events.append_array(be_attacked.events);
			captures.append_array(be_attacked.captures);
			exiles.append_array(be_attacked.exiles);
			const int32_t current_attacker_cell = find_board_card(next, played_card_index, attacker_cell);
			const int32_t current_attacked_cell = find_board_card(next, attacked_card_index, attacked_cell);
			if (current_attacker_cell < 0 || next.board_owners[current_attacker_cell] != moving_owner) break;
			if (current_attacked_cell < 0) continue;
			if (!can_attack_target(next, current_attacker_cell, current_attacked_cell, attack_policy, true)) continue;
			int32_t resolved_capture_owner = moving_owner;
			if (next.board_owners[current_attacked_cell] == moving_owner) {
				resolved_capture_owner = (
					attack_policy.capture_owner_id != 0
					? attack_policy.capture_owner_id
					: other_owner(moving_owner)
				);
			}
			if (resolved_capture_owner == next.board_owners[current_attacked_cell]) continue;
			EventContext before_context = attack_context;
			before_context.attacker_cell = current_attacker_cell;
			before_context.attacked_cell = current_attacked_cell;
			before_context.attacked_owner = next.board_owners[current_attacked_cell];
			before_context.trigger_cell = current_attacked_cell;
			before_context.trigger_owner = next.board_owners[current_attacked_cell];
			before_context.new_owner = resolved_capture_owner;
			before_context.flip_reason = StringName("summon_standard_attack");
			Resolution before_flip = resolve_event(next, StringName("card_before_flipped"), before_context, exile_stack);
			if (!before_flip.supported) {
				result["supported"] = false;
				result["reason"] = before_flip.reason;
				return result;
			}
			events.append_array(before_flip.events);
			captures.append_array(before_flip.captures);
			exiles.append_array(before_flip.exiles);
			if (before_flip.flip_prevented) {
				Dictionary prevented;
				prevented["type"] = StringName("card_flip_prevented");
				prevented["source_cell"] = current_attacker_cell;
				prevented["target_cell"] = current_attacked_cell;
				prevented["owner_id"] = attacked_owner;
				prevented["new_owner_id"] = resolved_capture_owner;
				prevented["instance_id"] = attacked_instance_id;
				events.append(prevented);
				Resolution after_prevented = resolve_event(next, StringName("card_flip_prevented"), before_context, exile_stack);
				if (!after_prevented.supported) {
					result["supported"] = false;
					result["reason"] = after_prevented.reason;
					return result;
				}
				events.append_array(after_prevented.events);
				captures.append_array(after_prevented.captures);
				exiles.append_array(after_prevented.exiles);
				continue;
			}
			Resolution flip_resolution;
			if (!flip_card(next, current_attacker_cell, played_card_index, current_attacked_cell, attacked_card_index, resolved_capture_owner, before_context, exile_stack, flip_resolution)) {
				result["supported"] = false;
				result["reason"] = flip_resolution.reason;
				return result;
			}
			events.append_array(flip_resolution.events);
			captures.append_array(flip_resolution.captures);
			exiles.append_array(flip_resolution.exiles);
			attack_flipped_enemy = attack_flipped_enemy || attacked_owner != moving_owner;
		}
		if (attack_started) {
			EventContext after_attack_context;
			after_attack_context.attacker_cell = find_board_card(next, played_card_index, static_cast<int32_t>(target_cell));
			after_attack_context.attacker_card_index = played_card_index;
			after_attack_context.attacker_owner = moving_owner;
			after_attack_context.attack_flipped_enemy = attack_flipped_enemy;
			Resolution after_attack = resolve_event(next, StringName("card_after_attack"), after_attack_context, exile_stack);
			if (!after_attack.supported) {
				result["supported"] = false;
				result["reason"] = after_attack.reason;
				return result;
			}
			events.append_array(after_attack.events);
			captures.append_array(after_attack.captures);
			exiles.append_array(after_attack.exiles);
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
	result["exiles"] = exiles;
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
			CompiledAbility compiled_ability;
			const Variant ability_value = abilities[ability_index];
			int32_t interned_index = -1;
			for (size_t pool_index = 0; pool_index < ability_declaration_pool.size(); ++pool_index) {
				if (ability_declaration_pool[pool_index] == ability_value) {
					interned_index = static_cast<int32_t>(pool_index);
					break;
				}
			}
			if (interned_index >= 0) {
				compiled.ability_pool_indices.push_back(interned_index);
				if (!compiled_ability_pool[interned_index].declaration_valid) {
					compiled.declaration_valid = false;
				}
				continue;
			}
			if (ability_value.get_type() != Variant::DICTIONARY) {
				compiled.declaration_valid = false;
				compiled_ability.declaration_valid = false;
				compiled.ability_pool_indices.push_back(static_cast<int32_t>(compiled_ability_pool.size()));
				compiled_ability_pool.push_back(compiled_ability);
				ability_declaration_pool.push_back(ability_value);
				continue;
			}
			const Dictionary ability = ability_value;
			compiled_ability.retained_on_flip = static_cast<bool>(
				ability.get("retained_on_flip", false)
			);
			if (ability.has("activation")) {
				const Variant activation_value = ability["activation"];
				if (activation_value.get_type() != Variant::DICTIONARY) {
					compiled.declaration_valid = false;
					compiled_ability.declaration_valid = false;
				} else if (!Dictionary(activation_value).is_empty()) {
					compiled_ability.has_activation = true;
				}
			}
			if (ability.has("modifiers")) {
				const Variant modifiers_value = ability["modifiers"];
				if (modifiers_value.get_type() != Variant::ARRAY) {
					compiled.declaration_valid = false;
					compiled_ability.declaration_valid = false;
				} else {
					const Array modifiers = modifiers_value;
					for (int64_t modifier_index = 0; modifier_index < modifiers.size(); ++modifier_index) {
						CompiledModifier compiled_modifier;
						const Variant modifier_value = modifiers[modifier_index];
						if (modifier_value.get_type() == Variant::DICTIONARY) {
							const Dictionary modifier = modifier_value;
							const StringName type = modifier.get("type", StringName());
							if (
								type == StringName("defending_power_override")
								&& modifier.size() == 2
								&& Variant(modifier.get("value", 0)).get_type() == Variant::INT
							) {
								compiled_modifier.opcode = ModifierOpcode::DEFENDING_POWER_OVERRIDE;
								compiled_modifier.value = static_cast<int32_t>(
									static_cast<int64_t>(modifier.get("value", 0))
								);
							} else if (
								type == StringName("orthogonal_attack_range_two")
								&& (modifier.size() == 2 || modifier.size() == 3)
								&& Variant(modifier.get("allow_intervening_ally", false)).get_type() == Variant::BOOL
								&& (
									!modifier.has("allow_intervening_enemy")
									|| Variant(modifier.get("allow_intervening_enemy", false)).get_type() == Variant::BOOL
								)
							) {
								compiled_modifier.opcode = ModifierOpcode::ORTHOGONAL_ATTACK_RANGE_TWO;
								compiled_modifier.value = (
									(static_cast<bool>(modifier.get("allow_intervening_ally", false)) ? 1 : 0)
									| (static_cast<bool>(modifier.get("allow_intervening_enemy", false)) ? 2 : 0)
								);
							} else if (
								type == StringName("enemy_attacks_all")
								&& modifier.size() == 1
							) {
								compiled_modifier.opcode = ModifierOpcode::ENEMY_ATTACKS_ALL;
							} else if (modifier.size() == 1) {
								if (type == StringName("attack_requires_other_ally")) compiled_modifier.opcode = ModifierOpcode::ATTACK_REQUIRES_OTHER_ALLY;
								else if (type == StringName("defending_power_uses_minimum_side")) compiled_modifier.opcode = ModifierOpcode::DEFENDING_POWER_USES_MINIMUM_SIDE;
								else if (type == StringName("power_comparison_reversed")) compiled_modifier.opcode = ModifierOpcode::POWER_COMPARISON_REVERSED;
								else if (type == StringName("adjacent_enemy_summon_attacks_allies")) compiled_modifier.opcode = ModifierOpcode::ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES;
								else if (type == StringName("unlimited_attack_range")) compiled_modifier.opcode = ModifierOpcode::UNLIMITED_ATTACK_RANGE;
								else if (type == StringName("non_orthogonal_attack_any_axis")) compiled_modifier.opcode = ModifierOpcode::NON_ORTHOGONAL_ATTACK_ANY_AXIS;
								else if (type == StringName("standard_attack_first_legal_target")) compiled_modifier.opcode = ModifierOpcode::STANDARD_ATTACK_FIRST_LEGAL_TARGET;
								else if (type == StringName("enemy_cannot_attack_during_owner_turn")) compiled_modifier.opcode = ModifierOpcode::ENEMY_CANNOT_ATTACK_DURING_OWNER_TURN;
								else if (type == StringName("self_attacks_all")) compiled_modifier.opcode = ModifierOpcode::SELF_ATTACKS_ALL;
							}
						}
						compiled_ability.modifiers.push_back(compiled_modifier);
					}
				}
			}
			const Variant triggers_value = ability.get("triggers", Array());
			if (triggers_value.get_type() != Variant::ARRAY) {
				compiled.declaration_valid = false;
				compiled_ability.declaration_valid = false;
				compiled.ability_pool_indices.push_back(static_cast<int32_t>(compiled_ability_pool.size()));
				compiled_ability_pool.push_back(compiled_ability);
				ability_declaration_pool.push_back(ability_value);
				continue;
			}
			const Array triggers = triggers_value;
			for (int64_t trigger_index = 0; trigger_index < triggers.size(); ++trigger_index) {
				CompiledTriggerRule compiled_rule;
				const Variant rule_value = triggers[trigger_index];
				if (rule_value.get_type() != Variant::DICTIONARY) {
					compiled.declaration_valid = false;
					compiled_ability.declaration_valid = false;
					compiled_ability.triggers.push_back(compiled_rule);
					continue;
				}
				const Dictionary rule = rule_value;
				compiled_rule.event_id = rule.get("event", StringName());
				const Variant conditions_value = rule.get("conditions", Array());
				const Variant actions_value = rule.get("actions", Array());
				if (conditions_value.get_type() == Variant::ARRAY) {
					const Array conditions = conditions_value;
					for (int64_t condition_index = 0; condition_index < conditions.size(); ++condition_index) {
						CompiledCondition compiled_condition;
						const Variant condition_value = conditions[condition_index];
						if (condition_value.get_type() == Variant::DICTIONARY) {
							const Dictionary condition = condition_value;
							const StringName type = condition.get("type", StringName());
							if (condition.size() == 1) {
								if (type == StringName("trigger_card_is_self")) compiled_condition.opcode = ConditionOpcode::TRIGGER_CARD_IS_SELF;
								else if (type == StringName("attacked_card_is_self")) compiled_condition.opcode = ConditionOpcode::ATTACKED_CARD_IS_SELF;
								else if (type == StringName("attacker_card_is_self")) compiled_condition.opcode = ConditionOpcode::ATTACKER_CARD_IS_SELF;
								else if (type == StringName("attacker_card_is_enemy")) compiled_condition.opcode = ConditionOpcode::ATTACKER_CARD_IS_ENEMY;
								else if (type == StringName("trigger_card_was_on_board")) compiled_condition.opcode = ConditionOpcode::TRIGGER_CARD_WAS_ON_BOARD;
								else if (type == StringName("attack_flipped_enemy")) compiled_condition.opcode = ConditionOpcode::ATTACK_FLIPPED_ENEMY;
								else if (type == StringName("trigger_card_powers_could_change")) compiled_condition.opcode = ConditionOpcode::TRIGGER_CARD_POWERS_COULD_CHANGE;
							}
						}
						compiled_rule.conditions.push_back(compiled_condition);
					}
				} else {
					compiled_ability.declaration_valid = false;
				}
				if (actions_value.get_type() == Variant::ARRAY) {
					const Array actions = actions_value;
					for (int64_t action_index = 0; action_index < actions.size(); ++action_index) {
						CompiledAction compiled_action;
						const Variant action_value = actions[action_index];
						if (action_value.get_type() == Variant::DICTIONARY) {
							const Dictionary action = action_value;
							const StringName type = action.get("type", StringName());
							if (type == StringName("draw_cards") && action.size() == 2 && Variant(action.get("amount", 0)).get_type() == Variant::INT && static_cast<int64_t>(action.get("amount", 0)) > 0) {
								compiled_action.opcode = ActionOpcode::DRAW_CARDS;
								compiled_action.amount = static_cast<int32_t>(static_cast<int64_t>(action.get("amount", 0)));
							} else if (type == StringName("exile_card") && action.size() == 2) {
								compiled_action.opcode = ActionOpcode::EXILE_CARD;
							} else if (type == StringName("exile_self") && action.size() == 1) {
								compiled_action.opcode = ActionOpcode::EXILE_SELF;
							} else if (type == StringName("prevent_trigger_flip") && action.size() == 1) {
								compiled_action.opcode = ActionOpcode::PREVENT_TRIGGER_FLIP;
							} else if (type == StringName("remove_this_ability") && action.size() == 1) {
								compiled_action.opcode = ActionOpcode::REMOVE_THIS_ABILITY;
							}
							if (compiled_action.opcode == ActionOpcode::EXILE_CARD) {
								const StringName card_ref = action.get("card", StringName());
								if (card_ref == StringName("trigger_card")) compiled_action.card_ref = CardRefOpcode::TRIGGER_CARD;
								else if (card_ref == StringName("ability_source")) compiled_action.card_ref = CardRefOpcode::ABILITY_SOURCE;
								else if (card_ref == StringName("attacker_card")) compiled_action.card_ref = CardRefOpcode::ATTACKER_CARD;
							}
						}
						compiled_rule.actions.push_back(compiled_action);
					}
				} else {
					compiled_ability.declaration_valid = false;
				}
				compiled_ability.triggers.push_back(compiled_rule);
			}
			compiled_ability.isolated_self_after_flip = (
				!compiled_ability.has_activation
				&& compiled_ability.modifiers.empty()
				&& compiled_ability.triggers.size() == 1
				&& compiled_ability.triggers[0].event_id == StringName("card_after_flipped")
			);
			if (compiled_ability.isolated_self_after_flip) {
				bool has_self_condition = false;
				for (const CompiledCondition &condition : compiled_ability.triggers[0].conditions) {
					has_self_condition = has_self_condition || condition.opcode == ConditionOpcode::TRIGGER_CARD_IS_SELF;
				}
				compiled_ability.isolated_self_after_flip = has_self_condition;
			}
			compiled.ability_pool_indices.push_back(static_cast<int32_t>(compiled_ability_pool.size()));
			compiled_ability_pool.push_back(compiled_ability);
			ability_declaration_pool.push_back(ability_value);
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
	String &reason
) const {
	const int32_t moving_owner = value.scalars[0];
	const bool source_enabled = card_effects_enabled(value, played_card_index, moving_owner);
	if (source_enabled && card_has_unsupported_enabled_modifier(value, played_card_index, moving_owner)) {
		reason = "Played card has an unsupported modifier";
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
		if (card_has_unsupported_enabled_modifier(value, card_index, owner_id)) {
			reason = "Board contains an unsupported active modifier";
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

	const int32_t hand_zone_index = moving_owner - 1;
	const int32_t hand_size_after_play = static_cast<int32_t>(value.zones[hand_zone_index].size()) - 1;

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
			&& hand_size_after_play == 0
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
		if (ability != nullptr && ability->has_activation) return true;
	}
	return false;
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
				matched = context.trigger_card_index == group.source_card_index;
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
			case ConditionOpcode::TRIGGER_CARD_WAS_ON_BOARD:
				matched = context.trigger_was_on_board;
				break;
			case ConditionOpcode::ATTACK_FLIPPED_ENEMY:
				matched = context.attack_flipped_enemy;
				break;
			case ConditionOpcode::TRIGGER_CARD_POWERS_COULD_CHANGE:
				matched = context.trigger_card_index >= 0 && can_change_powers(value, context.trigger_card_index);
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
	for (size_t cell = 0; cell < value.board_card_indices.size(); ++cell) {
		const int32_t card_index = value.board_card_indices[cell];
		if (card_index < 0) continue;
		const int32_t owner_id = value.board_owners[cell];
		if (!card_effects_enabled(value, card_index, owner_id)) continue;
		for (size_t ability_index = 0; ability_index < value.card_runtime_abilities[card_index].size(); ++ability_index) {
			const CompiledAbility *ability = runtime_ability(value, card_index, static_cast<int32_t>(ability_index));
			if (ability == nullptr) continue;
			for (size_t trigger_index = 0; trigger_index < ability->triggers.size(); ++trigger_index) {
				const CompiledTriggerRule &rule = ability->triggers[trigger_index];
				if (rule.event_id != event_id) continue;
				EventGroup group;
				group.source_cell = static_cast<int32_t>(cell);
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
					return groups;
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
		if (
			find_board_card(value, group.source_card_index, group.source_cell) != group.source_cell
			|| value.board_owners[group.source_cell] != group.source_owner
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
		for (const CompiledAction &action : rule.actions) {
			if (!execute_action(value, group, action, context, exile_stack, resolution)) {
				resolution.supported = false;
				if (resolution.reason.is_empty()) resolution.reason = "Relevant event uses an unsupported action";
				return resolution;
			}
		}
	}
	return resolution;
}

bool DuelNativeCompactKernel::draw_cards(
	NativeState &value,
	int32_t owner_id,
	int32_t source_cell,
	int32_t amount,
	Resolution &resolution
) const {
	std::vector<int32_t> &hand = value.zones[owner_id - 1];
	std::vector<int32_t> &deck = value.zones[owner_id + 1];
	const int32_t actual = std::min(amount, std::max(0, 5 - static_cast<int32_t>(hand.size())));
	if (static_cast<int32_t>(deck.size()) < actual) {
		resolution.reason = "Draw would require the generated empty-deck fallback card";
		return false;
	}
	const Dictionary audiences_by_owner = value.side_payload.get("future_draw_reveal_audiences", Dictionary());
	const Variant audiences_value = audiences_by_owner.get(owner_id, Array());
	if (audiences_value.get_type() != Variant::ARRAY || !Array(audiences_value).is_empty()) {
		resolution.reason = "Draw would emit unsupported future-reveal events";
		return false;
	}
	if (actual > 0 && board_has_enabled_event(value, StringName("card_after_drawn"))) {
		resolution.reason = "Draw would trigger an unsupported after-drawn listener";
		return false;
	}
	for (int32_t draw_index = 0; draw_index < actual; ++draw_index) {
		const int32_t card_index = deck.front();
		deck.erase(deck.begin());
		const int32_t slot = leftmost_empty_hand_slot(value, owner_id);
		if (slot < 0) break;
		value.card_runtime_flags[card_index] |= static_cast<uint8_t>(1 << 7);
		value.card_hand_slots[card_index] = slot;
		hand.push_back(card_index);
		Dictionary event;
		event["type"] = StringName("card_drawn");
		event["source_cell"] = source_cell;
		event["owner_id"] = owner_id;
		event["card_id"] = value.card_ids[card_index];
		event["instance_id"] = value.card_instance_ids[card_index];
		event["logical_hand_index"] = static_cast<int32_t>(hand.size()) - 1;
		event["hand_slot_index"] = slot;
		event["card"] = restore_runtime_card(value, card_index);
		resolution.events.append(event);
	}
	return true;
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

bool DuelNativeCompactKernel::execute_action(
	NativeState &value,
	const EventGroup &group,
	const CompiledAction &action,
	const EventContext &context,
	std::vector<int32_t> &exile_stack,
	Resolution &resolution
) const {
	switch (action.opcode) {
		case ActionOpcode::DRAW_CARDS:
			return draw_cards(value, group.source_owner, group.source_cell, action.amount, resolution);
		case ActionOpcode::EXILE_SELF:
			return exile_card(value, group.source_card_index, group.source_cell, group.source_card_index, true, StringName("ability_exile_self"), context, exile_stack, resolution);
		case ActionOpcode::EXILE_CARD: {
			int32_t target = -1;
			if (action.card_ref == CardRefOpcode::TRIGGER_CARD) target = context.trigger_card_index;
			else if (action.card_ref == CardRefOpcode::ABILITY_SOURCE) target = group.source_card_index;
			else if (action.card_ref == CardRefOpcode::ATTACKER_CARD) target = context.attacker_card_index;
			else return false;
			if (target < 0) return true;
			return exile_card(value, target, group.source_cell, group.source_card_index, target == group.source_card_index, StringName("ability_exile_card"), context, exile_stack, resolution);
		}
		case ActionOpcode::PREVENT_TRIGGER_FLIP:
			if (context.trigger_card_index >= 0 && context.new_owner >= 1 && context.new_owner <= 2) resolution.flip_prevented = true;
			return true;
		case ActionOpcode::REMOVE_THIS_ABILITY: {
			const int32_t current_cell = find_board_card(value, group.source_card_index, group.source_cell);
			if (current_cell >= 0 && value.board_owners[current_cell] == group.source_owner) {
				remove_ability_with_event(value, group.source_card_index, group.ability_handle, current_cell, group.source_card_index, current_cell, group.source_owner, resolution.events);
			}
			return true;
		}
		default:
			return false;
	}
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
	Resolution &resolution
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
	if (zone == 0) {
		value.board_card_indices[logical_index] = -1;
		value.board_owners[logical_index] = 0;
		if (logical_index < value.board_slot_extras.size()) value.board_slot_extras[logical_index] = Dictionary();
		resolution.exiles.append(logical_index);
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
	Resolution &resolution
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
	for (const uint64_t ability_handle : remove_before_after_flip) {
		remove_ability_with_event(value, target_card_index, ability_handle, attacker_cell, attacker_card_index, current_target_cell, new_owner, resolution.events);
	}
	resolution.captures.append(current_target_cell);
	EventContext after_context = context;
	after_context.trigger_cell = current_target_cell;
	after_context.trigger_card_index = target_card_index;
	after_context.trigger_owner = new_owner;
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
	payload["card_suppression_set_indices"] = to_packed_int32_array(
		value.card_suppression_set_indices
	);
	payload["card_hand_slots"] = to_packed_int32_array(value.card_hand_slots);
	payload["card_template_pool"] = value.card_template_pool;
	payload["active_ability_set_pool"] = materialized_pool;
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
	for (const std::vector<RuntimeAbilityEntry> &abilities : value.card_runtime_abilities) {
		for (const RuntimeAbilityEntry &entry : abilities) {
			hash ^= static_cast<uint64_t>(entry.compiled_ability_index);
			hash *= 1099511628211ULL;
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
