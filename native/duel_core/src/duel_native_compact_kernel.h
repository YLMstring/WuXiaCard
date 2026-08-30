#pragma once

#include <cstdint>
#include <vector>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {

class DuelNativeCompactKernel : public RefCounted {
	GDCLASS(DuelNativeCompactKernel, RefCounted)

	struct RuntimeAbilityEntry {
		int32_t compiled_ability_index = -1;
		uint64_t handle = 0;
	};

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
		std::vector<std::vector<RuntimeAbilityEntry>> card_runtime_abilities;
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
		uint64_t next_ability_handle = 1;
	};

	enum class ConditionOpcode : uint8_t {
		TRIGGER_CARD_IS_SELF,
		ATTACKED_CARD_IS_SELF,
		ATTACKER_CARD_IS_SELF,
		ATTACKER_CARD_IS_ENEMY,
		TRIGGER_CARD_WAS_ON_BOARD,
		ATTACK_FLIPPED_ENEMY,
		TRIGGER_CARD_POWERS_COULD_CHANGE,
		UNSUPPORTED,
	};

	enum class ActionOpcode : uint8_t {
		DRAW_CARDS,
		EXILE_CARD,
		EXILE_SELF,
		PREVENT_TRIGGER_FLIP,
		REMOVE_THIS_ABILITY,
		FOR_EACH_SELECTED_CARD,
		CHANGE_POWERS,
		UNSUPPORTED,
	};

	enum class ActionOutcome : uint8_t {
		APPLIED,
		NO_EFFECT,
		INVALID_CONTEXT,
		UNSUPPORTED,
	};

	enum class CardRefOpcode : uint8_t {
		SELECTED_CARD,
		TRIGGER_CARD,
		ABILITY_SOURCE,
		ATTACKER_CARD,
		UNSUPPORTED,
	};

	enum class SelectorZoneOpcode : uint8_t {
		HAND,
		BOARD,
		DISCARD,
		REMOVED,
	};

	enum class SelectorConditionOpcode : uint8_t {
		IS_ALLY,
		IS_ENEMY,
		WEAPON_IS,
		IS_NOT_SOURCE,
		ADJACENT_TO_SOURCE,
		SURROUNDED_BY_ALLIES,
		ORIGINAL_OWNER_IS_SELF,
		ORIGINAL_OWNER_IS_ENEMY,
		FLIPPED_BY_CURRENT_ATTACK,
		POWERS_CAN_CHANGE,
		HAS_NONZERO_POWER,
		IS_PREVIOUS_HAND_PLAY,
		CAN_SPEND_KI,
		CAN_TRANSFER_RESOURCE,
		UNSUPPORTED,
	};

	enum class RelativeOwnerOpcode : uint8_t {
		ABILITY_SOURCE,
		OPPONENT_OF_ABILITY_SOURCE,
		CARD_CURRENT,
		UNSUPPORTED,
	};

	enum class ResourceOpcode : uint8_t {
		KI,
		POWERS,
		NONE,
		UNSUPPORTED,
	};

	enum class ModifierOpcode : uint8_t {
		DEFENDING_POWER_OVERRIDE,
		ATTACK_REQUIRES_OTHER_ALLY,
		DEFENDING_POWER_USES_MINIMUM_SIDE,
		ORTHOGONAL_ATTACK_RANGE_TWO,
		ENEMY_ATTACKS_ALL,
		POWER_COMPARISON_REVERSED,
		ADJACENT_ENEMY_SUMMON_ATTACKS_ALLIES,
		UNLIMITED_ATTACK_RANGE,
		NON_ORTHOGONAL_ATTACK_ANY_AXIS,
		STANDARD_ATTACK_FIRST_LEGAL_TARGET,
		ENEMY_CANNOT_ATTACK_DURING_OWNER_TURN,
		SELF_ATTACKS_ALL,
		UNSUPPORTED,
	};

	enum class AttackTargetPolicy : uint8_t {
		ENEMIES_ONLY,
		ALLIES_ONLY,
		ALL,
	};

	struct CompiledCondition {
		ConditionOpcode opcode = ConditionOpcode::UNSUPPORTED;
	};

	struct CompiledSelectorCondition {
		bool declaration_valid = true;
		SelectorConditionOpcode opcode = SelectorConditionOpcode::UNSUPPORTED;
		String weapon;
		RelativeOwnerOpcode relative_owner = RelativeOwnerOpcode::UNSUPPORTED;
		ResourceOpcode resource = ResourceOpcode::NONE;
		ResourceOpcode fallback_resource = ResourceOpcode::NONE;
		int32_t amount = 0;
	};

	struct CompiledSelector {
		bool declaration_valid = true;
		std::vector<SelectorZoneOpcode> zones;
		std::vector<CompiledSelectorCondition> conditions;
		int32_t limit = 0;
		int32_t required_count = 0;
		bool hand_right_to_left = false;
	};

	struct CompiledAction {
		bool declaration_valid = true;
		ActionOpcode opcode = ActionOpcode::UNSUPPORTED;
		CardRefOpcode card_ref = CardRefOpcode::UNSUPPORTED;
		int32_t amount = 0;
		bool amount_is_hand_count = false;
		RelativeOwnerOpcode amount_owner = RelativeOwnerOpcode::UNSUPPORTED;
		bool stop_rule_on_invalid_context = false;
		StringName power_change_batch_group;
		CompiledSelector selector;
		std::vector<CompiledAction> child_actions;
	};

	struct CompiledModifier {
		ModifierOpcode opcode = ModifierOpcode::UNSUPPORTED;
		int32_t value = 0;
	};

	struct CompiledTriggerRule {
		StringName event_id;
		std::vector<CompiledCondition> conditions;
		std::vector<CompiledAction> actions;
	};

	struct CompiledAbility {
		bool declaration_valid = true;
		bool retained_on_flip = false;
		bool has_activation = false;
		bool isolated_self_after_flip = false;
		std::vector<CompiledTriggerRule> triggers;
		std::vector<CompiledModifier> modifiers;
	};

	struct CompiledAbilitySet {
		bool declaration_valid = true;
		std::vector<int32_t> ability_pool_indices;
	};

	struct AttackPolicy {
		AttackTargetPolicy target_policy = AttackTargetPolicy::ENEMIES_ONLY;
		int32_t capture_owner_id = 0;
		bool specified = false;
	};

	struct EventContext {
		int32_t trigger_cell = -1;
		int32_t trigger_card_index = -1;
		int32_t trigger_owner = 0;
		int32_t trigger_zone = -1;
		int32_t trigger_logical_index = -1;
		int32_t attacker_cell = -1;
		int32_t attacker_card_index = -1;
		int32_t attacker_owner = 0;
		int32_t attacked_cell = -1;
		int32_t attacked_card_index = -1;
		int32_t attacked_owner = 0;
		int32_t new_owner = 0;
		bool trigger_was_on_board = false;
		bool attack_flipped_enemy = false;
		struct AttackFlipRecord {
			int32_t card_index = -1;
			int32_t previous_owner = 0;
		};
		std::vector<AttackFlipRecord> attack_flips;
		StringName attack_reason;
		StringName flip_reason;
		StringName exile_reason;
	};

	struct EventGroup {
		int32_t source_cell = -1;
		int32_t source_card_index = -1;
		int32_t source_owner = 0;
		int32_t ability_index = -1;
		uint64_t ability_handle = 0;
		int32_t trigger_index = -1;
	};

	struct ActionContext {
		int32_t ability_source_cell = -1;
		int32_t ability_source_zone = -1;
		int32_t ability_source_logical_index = -1;
		int32_t ability_source_card_index = -1;
		int32_t ability_source_owner = 0;
		int32_t action_subject_card_index = -1;
		int32_t action_subject_owner = 0;
		int32_t action_subject_zone = -1;
		int32_t action_subject_logical_index = -1;
		int32_t selected_card_index = -1;
		int32_t trigger_card_index = -1;
		int32_t attacker_card_index = -1;
		StringName event_id;
		int32_t discovery_ability_index = -1;
		int32_t trigger_index = -1;
		std::vector<EventContext::AttackFlipRecord> attack_flips;
	};

	struct Resolution {
		bool supported = true;
		String reason;
		Array events;
		Array captures;
		Array exiles;
		bool flip_prevented = false;
	};

	NativeState state;
	std::vector<CompiledAbilitySet> compiled_ability_sets;
	std::vector<CompiledAbility> compiled_ability_pool;
	std::vector<Variant> ability_declaration_pool;
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
	CompiledCondition compile_condition(const Variant &value) const;
	CompiledSelectorCondition compile_selector_condition(const Variant &value) const;
	CompiledSelector compile_selector(const Variant &value) const;
	CompiledAction compile_action(const Variant &value) const;
	CompiledModifier compile_modifier(const Variant &value) const;
	CompiledTriggerRule compile_trigger_rule(const Variant &value, bool &valid) const;
	CompiledAbility compile_ability(const Variant &value) const;
	int32_t intern_compiled_ability(const Variant &value);
	bool validate_play_support(const NativeState &value, String &reason) const;
	bool validate_action_rule_support(
		const NativeState &value,
		int32_t played_card_index,
		int32_t target_cell,
		String &reason
	) const;
	bool card_effects_enabled(
		const NativeState &value,
		int32_t card_index,
		int32_t owner_id
	) const;
	bool card_has_abilities(const NativeState &value, int32_t card_index) const;
	bool ability_enabled(const NativeState &value, int32_t card_index, int32_t ability_index) const;
	const CompiledAbility *runtime_ability(
		const NativeState &value,
		int32_t card_index,
		int32_t ability_index
	) const;
	int32_t find_runtime_ability_index(
		const NativeState &value,
		int32_t card_index,
		uint64_t ability_handle,
		int32_t preferred_index = -1
	) const;
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
	bool card_has_unsupported_enabled_modifier(
		const NativeState &value,
		int32_t card_index,
		int32_t owner_id
	) const;
	bool card_has_modifier(
		const NativeState &value,
		int32_t card_index,
		int32_t owner_id,
		ModifierOpcode opcode,
		int32_t *out_value = nullptr
	) const;
	bool card_modifier_has_flag(
		const NativeState &value,
		int32_t card_index,
		int32_t owner_id,
		ModifierOpcode opcode,
		int32_t flag
	) const;
	int32_t count_owned(const NativeState &value, int32_t owner_id) const;
	bool attack_is_prohibited(const NativeState &value, int32_t attacker_owner) const;
	std::vector<int32_t> snapshot_summon_attack_redirect_sources(
		const NativeState &value,
		int32_t summon_cell,
		int32_t summoning_owner
	) const;
	AttackPolicy get_summon_attack_policy(
		const NativeState &value,
		int32_t summoned_cell,
		int32_t summoning_owner,
		const std::vector<int32_t> &source_card_indices
	) const;
	AttackPolicy get_standard_attack_policy(
		const NativeState &value,
		int32_t attacker_cell,
		int32_t attacker_card_index,
		int32_t attacker_owner,
		const AttackPolicy &requested_policy
	) const;
	std::vector<int32_t> get_attack_targets(
		const NativeState &value,
		int32_t source_cell,
		const AttackPolicy &policy
	) const;
	bool can_attack_target(
		const NativeState &value,
		int32_t source_cell,
		int32_t target_cell,
		const AttackPolicy &policy,
		bool skip_power_comparison
	) const;
	bool is_target_in_attack_range(
		const NativeState &value,
		int32_t source_cell,
		int32_t target_cell,
		const AttackPolicy &policy,
		bool skip_power_comparison
	) const;
	bool power_pair_wins(
		const NativeState &value,
		int32_t source_card_index,
		int32_t source_owner,
		int32_t target_card_index,
		int32_t target_owner,
		int32_t attacking_direction,
		int32_t defending_direction,
		bool comparison_reversed
	) const;
	bool conditions_match(
		const NativeState &value,
		const EventGroup &group,
		const CompiledTriggerRule &rule,
		const EventContext &context,
		bool &supported
	) const;
	std::vector<EventGroup> discover_event(
		const NativeState &value,
		const StringName &event_id,
		const EventContext &context,
		bool &supported,
		String &reason
	) const;
	Resolution resolve_event(
		NativeState &value,
		const StringName &event_id,
		const EventContext &context,
		std::vector<int32_t> &exile_stack
	) const;
	ActionOutcome execute_actions(
		NativeState &value,
		const EventGroup &group,
		const std::vector<CompiledAction> &actions,
		const EventContext &event_context,
		const ActionContext &action_context,
		std::vector<int32_t> &exile_stack,
		Resolution &resolution,
		bool defer_power_change_batch = false
	) const;
	ActionOutcome execute_action(
		NativeState &value,
		const EventGroup &group,
		const CompiledAction &action,
		const EventContext &event_context,
		const ActionContext &action_context,
		std::vector<int32_t> &exile_stack,
		Resolution &resolution
	) const;
	ActionOutcome execute_for_each_selected_card(
		NativeState &value,
		const EventGroup &group,
		const CompiledAction &action,
		const EventContext &event_context,
		const ActionContext &action_context,
		std::vector<int32_t> &exile_stack,
		Resolution &resolution
	) const;
	bool selector_conditions_match(
		const NativeState &value,
		int32_t candidate_card_index,
		int32_t candidate_zone,
		int32_t candidate_owner,
		int32_t candidate_logical_index,
		const CompiledSelector &selector,
		const ActionContext &context,
		bool &supported
	) const;
	std::vector<int32_t> snapshot_selected_cards(
		const NativeState &value,
		const CompiledSelector &selector,
		const ActionContext &context,
		bool &supported
	) const;
	bool resolve_selector_source(
		const NativeState &value,
		const ActionContext &context,
		int32_t &zone,
		int32_t &owner,
		int32_t &logical_index
	) const;
	bool card_declarations_can_spend_ki(const NativeState &value, int32_t card_index) const;
	bool action_declarations_can_spend_ki(const Variant &value) const;
	ActionOutcome change_powers(
		NativeState &value,
		const EventGroup &group,
		const CompiledAction &action,
		const EventContext &event_context,
		const ActionContext &action_context,
		int32_t source_cell,
		std::vector<int32_t> &exile_stack,
		Resolution &resolution
	) const;
	void assign_power_change_batch(
		Resolution &resolution,
		int64_t first_event_index,
		const EventGroup &group,
		const CompiledAction &action,
		const ActionContext &context,
		int32_t action_index
	) const;
	bool draw_cards(
		NativeState &value,
		int32_t owner_id,
		int32_t source_cell,
		int32_t amount,
		Resolution &resolution
	) const;
	bool exile_card(
		NativeState &value,
		int32_t card_index,
		int32_t source_cell,
		int32_t ability_source_card_index,
		bool self_removal,
		const StringName &exile_reason,
		const EventContext &parent_context,
		std::vector<int32_t> &exile_stack,
		Resolution &resolution
	) const;
	int32_t find_board_card(const NativeState &value, int32_t card_index, int32_t hint = -1) const;
	bool locate_card(
		const NativeState &value,
		int32_t card_index,
		int32_t &zone_kind,
		int32_t &owner_id,
		int32_t &logical_index
	) const;
	bool is_special_negative(const NativeState &value, int32_t card_index) const;
	bool powers_supported(const NativeState &value, int32_t card_index) const;
	bool can_change_powers(const NativeState &value, int32_t card_index) const;
	int32_t effective_defending_power(
		const NativeState &value,
		int32_t card_index,
		int32_t owner_id,
		int32_t direction
	) const;
	int32_t minimum_effective_defending_power(
		const NativeState &value,
		int32_t card_index,
		int32_t owner_id
	) const;
	void remove_ability_with_event(
		NativeState &value,
		int32_t card_index,
		uint64_t ability_handle,
		int32_t source_cell,
		int32_t source_card_index,
		int32_t target_cell,
		int32_t owner_id,
		Array &events
	) const;
	bool flip_card(
		NativeState &value,
		int32_t attacker_cell,
		int32_t attacker_card_index,
		int32_t target_cell,
		int32_t target_card_index,
		int32_t new_owner,
		const EventContext &context,
		std::vector<int32_t> &exile_stack,
		Resolution &resolution
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
