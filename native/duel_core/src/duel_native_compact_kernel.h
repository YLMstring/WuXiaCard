#pragma once

#include <cstdint>
#include <vector>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>

namespace godot {

class DuelNativeCompactKernel : public RefCounted {
	GDCLASS(DuelNativeCompactKernel, RefCounted)

	struct NativeState {
		std::vector<int32_t> scalars;
		std::vector<int32_t> board_card_indices;
		std::vector<uint8_t> board_owners;
		std::vector<std::vector<int32_t>> zones;
		std::vector<StringName> card_instance_ids;
		std::vector<int32_t> card_template_indices;
		std::vector<uint8_t> card_runtime_flags;
		std::vector<int32_t> card_powers;
		std::vector<uint8_t> card_original_owners;
		std::vector<int32_t> card_ki;
		std::vector<int32_t> card_active_ability_set_indices;
		std::vector<uint8_t> card_reveal_codes;
		std::vector<int32_t> card_suppression_set_indices;
		std::vector<int32_t> card_hand_slots;
		std::vector<StringName> card_ids;
		Array board_slot_extras;
		Array card_template_pool;
		Array active_ability_set_pool;
		Array suppression_set_pool;
		Dictionary side_payload;
		bool has_rule_metadata = false;
	};

	struct CompiledTriggerRule {
		StringName event_id;
		bool supports_self_after_summoned_draw = false;
		int32_t draw_count = 0;
	};

	struct CompiledAbilitySet {
		bool declaration_valid = true;
		bool has_activation = false;
		bool has_modifiers = false;
		std::vector<CompiledTriggerRule> triggers;
	};

	NativeState state;
	std::vector<CompiledAbilitySet> compiled_ability_sets;
	bool loaded = false;
	String last_error;

protected:
	static void _bind_methods();

public:
	bool load_compact_payload(const Dictionary &payload);
	bool is_loaded() const;
	String get_last_error() const;
	Dictionary inspect_layout() const;
	Dictionary benchmark_core_clone(int64_t iterations) const;
	Dictionary apply_play_transition(
		int64_t hand_index,
		int64_t target_cell,
		const StringName &expected_instance_id = StringName()
	) const;

private:
	bool validate_shape();
	void compile_ability_sets();
	bool validate_play_support(const NativeState &value, String &reason) const;
	bool validate_action_rule_support(
		const NativeState &value,
		int32_t played_card_index,
		int32_t target_cell,
		std::vector<int32_t> &draw_counts,
		String &reason
	) const;
	bool card_effects_enabled(
		const NativeState &value,
		int32_t card_index,
		int32_t owner_id
	) const;
	bool card_has_abilities(const NativeState &value, int32_t card_index) const;
	bool card_has_enabled_activation(
		const NativeState &value,
		int32_t card_index,
		int32_t owner_id
	) const;
	bool card_has_enabled_modifiers(
		const NativeState &value,
		int32_t card_index,
		int32_t owner_id
	) const;
	bool card_has_enabled_event(
		const NativeState &value,
		int32_t card_index,
		int32_t owner_id,
		const StringName &event_id
	) const;
	bool board_has_enabled_event(
		const NativeState &value,
		const StringName &event_id
	) const;
	bool board_has_enabled_activation_for_owner(
		const NativeState &value,
		int32_t owner_id
	) const;
	Dictionary restore_runtime_card(const NativeState &value, int32_t card_index) const;
	int32_t leftmost_empty_hand_slot(const NativeState &value, int32_t owner_id) const;
	bool owner_has_legal_play(const NativeState &value, int32_t owner_id) const;
	bool is_terminal(const NativeState &value) const;
	void complete_owner_turn_boundary(NativeState &value) const;
	String board_repetition_signature(const NativeState &value) const;
	Dictionary to_variant_payload(const NativeState &value) const;
	uint64_t checksum(const NativeState &value) const;
};

} // namespace godot
