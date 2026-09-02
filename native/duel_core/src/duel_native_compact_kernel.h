#pragma once

#include <array>
#include <chrono>
#include <cstdint>
#include <unordered_map>
#include <vector>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/callable.hpp>
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

	struct RuntimeSuppressionEntry {
		int32_t original_index = -1;
		int32_t compiled_ability_index = -1;
		uint64_t handle = 0;
	};

	struct RuntimeSuppressionBatch {
		int32_t expires_after_turn = 0;
		std::vector<RuntimeSuppressionEntry> entries;
	};

	struct FreshCardPrototype {
		StringName card_id;
		int32_t template_index = -1;
		std::array<int32_t, 4> powers = {0, 0, 0, 0};
		int32_t ki = 0;
		int32_t active_ability_set_index = -1;
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
		std::vector<std::vector<RuntimeSuppressionBatch>> card_runtime_suppression_batches;
		std::vector<uint8_t> card_reveal_codes;
		std::vector<int32_t> card_suppression_set_indices;
		std::vector<int32_t> card_hand_slots;
		std::vector<StringName> card_ids;
		Array board_slot_extras;
		Array card_template_pool;
		Array active_ability_set_pool;
		Array suppression_set_pool;
		Array fresh_card_prototype_pool;
		std::vector<FreshCardPrototype> fresh_card_prototypes;
		int32_t empty_deck_draw_prototype_index = -1;
		Dictionary side_payload;
		bool has_rule_metadata = false;
		uint64_t next_ability_handle = 1;
	};

	enum class ConditionOpcode : uint8_t {
		TRIGGER_CARD_IS_SELF,
		TRIGGER_CARD_IS_ALLY,
		TRIGGER_CARD_IS_ENEMY,
		TRIGGER_CARD_IN_RANGE,
		TRIGGER_CARD_ADJACENT_TO_SOURCE,
		TRIGGER_CARD_OUTSIDE_SOURCE_OWNER_HAND,
		TRIGGER_CARD_REVEALED_TO_SELF,
		TRIGGER_CARD_WAS_ENEMY,
		TRIGGER_CARD_ORIGINAL_OWNER_IS_SELF,
		ATTACKED_CARD_IS_SELF,
		ATTACKER_CARD_IS_SELF,
		ATTACKER_CARD_IS_ENEMY,
		ATTACKER_CARD_IS_OTHER_ALLY,
		ATTACK_IS_NOT_REPEAT,
		ACTIVATION_OWNER_IS_ALLY,
		TRIGGER_CARD_WAS_ON_BOARD,
		ATTACK_FLIPPED_ENEMY,
		ATTACK_FLIPPED_ALLY_IN_RANGE,
		TRIGGER_CARD_POWERS_COULD_CHANGE,
		DRAWN_CARD_IS_ENEMY,
		TURN_OWNER_IS_SELF,
		OWNER_DID_NOT_WIN,
		KI_AT_LEAST,
		KI_CHANGED_CARD_IS_SELF,
		KI_REACHED_ZERO,
		MOVING_CARD_IS_SELF,
		MOVING_CARD_IS_ALLY,
		SOURCE_OWNER_HAND_EMPTY,
		SOURCE_HAS_ADJACENT_EMPTY_CELL,
		SOURCE_HAS_EMPTY_BETWEEN_ENEMY,
		LAST_DISCARD_BATCH_SIZE_AT_LEAST,
		DISCARD_OWNER_IS_SELF,
		UNSUPPORTED,
	};

	enum class ActionOpcode : uint8_t {
		DRAW_CARDS,
		DISCARD_CARD,
		DISCARD_CARDS,
		EXILE_CARD,
		EXILE_SELF,
		PREVENT_TRIGGER_FLIP,
		REMOVE_THIS_ABILITY,
		FOR_EACH_SELECTED_CARD,
		IF,
		CHANGE_POWERS,
		GAIN_KI,
		SPEND_KI,
		FLIP_SELF,
		GRANT_TRIGGER_CARD_ABILITY,
		GRANT_ABILITY_TO_SELF,
		TRANSFORM_CARD,
		RETURN_CARD_TO_HAND,
		SELF_SWAPPED_WITH_ABILITY_SOURCE,
		SWAP_SELF_WITH_TRIGGER_CARD,
		ATTACK_TRIGGER_CARD,
		STANDARD_ATTACK_WITH_SELF,
		STANDARD_ATTACK_WITH_CARD,
		MOVE_SELF_TO_TARGET,
		SWAP_SELF_WITH_TARGET,
		MOVE_SELF_TO_FIRST_ADJACENT_EMPTY,
		MOVE_SELF_TO_FIRST_EMPTY_BETWEEN_ENEMY,
		TRANSFER_CARD_RESOURCE,
		DISTRIBUTE_KI,
		ADD_CARD_TO_HAND,
		REVEAL_HAND_CARDS,
		REVEAL_CARD,
		GRANT_EXTRA_CARD_PLAY,
		ADD_PENDING_NON_RETAINED_SUPPRESSION,
		TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES,
		ENABLE_FUTURE_DRAW_REVEAL,
		SUMMON_CARD,
		RESUMMON_CARD_IN_PLACE,
		DEPART_CARD_FOR_RESUMMON,
		UNSUPPORTED,
	};

	enum class TargetRuleOpcode : uint8_t {
		ADJACENT_EMPTY_BOARD,
		ADJACENT_ALLY_BOARD,
		ADJACENT_ENEMY_BOARD,
		OTHER_ALLY_BOARD,
		ENEMY_HAND_CARD,
		ALLY_HAND_CARD,
		ANY_EMPTY_BOARD,
		ANY_ENEMY_BOARD,
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
		LAST_SUMMONED_CARD,
		UNSUPPORTED,
	};

	enum class RecipientOpcode : uint8_t {
		SELF,
		OPPONENT,
		UNSUPPORTED,
	};

	enum class RevealFilterOpcode : uint8_t {
		ALL,
		REMEMBERED,
		UNSUPPORTED,
	};

	enum class CardSpecOpcode : uint8_t {
		EXISTING_REFERENCE,
		FRESH_COPY,
		PERFECT_COPY,
		TOP_DISCARD,
		UNSUPPORTED,
	};

	enum class CellSpecOpcode : uint8_t {
		INITIAL_CARD_CELL,
		ACTIVATION_TARGET,
		FIRST_ADJACENT_EMPTY,
		FIRST_ADJACENT_OR_ANY_EMPTY,
		FIRST_EMPTY_ADJACENT_TO_ENEMY,
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
		CARD_ORIGINAL,
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
		int32_t amount = 0;
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
		StringName declaration_type;
		ActionOpcode opcode = ActionOpcode::UNSUPPORTED;
		CardRefOpcode card_ref = CardRefOpcode::UNSUPPORTED;
		CardRefOpcode from_card_ref = CardRefOpcode::UNSUPPORTED;
		CardRefOpcode to_card_ref = CardRefOpcode::UNSUPPORTED;
		bool card_ref_explicit = false;
		int32_t amount = 0;
		bool amount_is_hand_count = false;
		RelativeOwnerOpcode amount_owner = RelativeOwnerOpcode::UNSUPPORTED;
		RelativeOwnerOpcode new_owner = RelativeOwnerOpcode::UNSUPPORTED;
		RelativeOwnerOpcode recipient_owner = RelativeOwnerOpcode::UNSUPPORTED;
		int32_t granted_ability_index = -1;
		bool preserve_instance = false;
		bool repeat_attack = false;
		bool target_policy_specified = false;
		AttackTargetPolicy target_policy = AttackTargetPolicy::ENEMIES_ONLY;
		ResourceOpcode resource = ResourceOpcode::NONE;
		ResourceOpcode fallback_resource = ResourceOpcode::NONE;
		RecipientOpcode recipient = RecipientOpcode::UNSUPPORTED;
		RevealFilterOpcode reveal_filter = RevealFilterOpcode::UNSUPPORTED;
		CardSpecOpcode card_spec = CardSpecOpcode::UNSUPPORTED;
		CellSpecOpcode cell_spec = CellSpecOpcode::UNSUPPORTED;
		CardRefOpcode summon_card_ref = CardRefOpcode::UNSUPPORTED;
		CardRefOpcode summon_cell_card_ref = CardRefOpcode::UNSUPPORTED;
		RelativeOwnerOpcode summon_owner = RelativeOwnerOpcode::UNSUPPORTED;
		StringName change_reason;
		String weapon;
		bool stop_rule_on_invalid_context = false;
		StringName power_change_batch_group;
		StringName card_id;
		CompiledSelector selector;
		std::vector<CompiledCondition> conditions;
		std::vector<CompiledAction> child_actions;
	};

	struct CompiledActivation {
		bool declaration_valid = true;
		TargetRuleOpcode target_rule = TargetRuleOpcode::UNSUPPORTED;
		int32_t required_ki = 0;
		std::vector<CompiledAction> costs;
		std::vector<CompiledAction> actions;
	};

	struct ActionExecutionState {
		int32_t last_discard_batch_size = 0;
		int32_t current_source_cell = -1;
		int32_t last_summoned_card_index = -1;
		int32_t last_summoned_cell = -1;
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
		CompiledActivation activation;
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

	struct AttackRequest {
		int32_t attacker_cell = -1;
		int32_t attacker_card_index = -1;
		int32_t attacker_owner = 0;
		AttackPolicy requested_policy;
		bool targeted = false;
		int32_t locked_target_cell = -1;
		int32_t locked_target_card_index = -1;
		int32_t locked_target_owner = 0;
		bool repeat_attack = false;
		StringName reason;
	};

	struct SummonRequest {
		int32_t summon_cell = -1;
		int32_t card_index = -1;
		int32_t owner_id = 0;
		StringName summon_reason;
		StringName attack_reason;
		std::vector<int32_t> attack_redirect_source_card_indices;
		bool attack_redirect_snapshot_taken = false;
		Array buffered_placement_events;
	};

	struct EventContext {
		int32_t ability_source_cell = -1;
		int32_t ability_source_zone = -1;
		int32_t ability_source_logical_index = -1;
		int32_t ability_source_card_index = -1;
		int32_t ability_source_owner = 0;
		int32_t trigger_cell = -1;
		int32_t trigger_card_index = -1;
		int32_t trigger_owner = 0;
		int32_t trigger_previous_owner = 0;
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
		int32_t previous_ki = 0;
		int32_t ki = -1;
		int32_t moving_source_cell = -1;
		int32_t moving_origin_cell = -1;
		int32_t moving_target_cell = -1;
		int32_t moving_card_index = -1;
		int32_t moving_owner = 0;
		int32_t discard_owner = 0;
		int32_t discard_batch_size = 0;
		int32_t turn_owner = 0;
		int32_t activation_owner = 0;
		int32_t activation_source_cell = -1;
		int32_t activation_source_card_index = -1;
		StringName activation_target_kind;
		int32_t activation_target_index = -1;
		bool repeat_attack = false;
		std::vector<int32_t> winning_owners;
		struct AttackFlipRecord {
			int32_t card_index = -1;
			int32_t previous_owner = 0;
		};
		std::vector<AttackFlipRecord> attack_flips;
		StringName attack_reason;
		StringName flip_reason;
		StringName exile_reason;
		StringName discard_batch_id;
	};

	struct EventGroup {
		int32_t source_cell = -1;
		int32_t source_zone = 0;
		int32_t source_logical_index = -1;
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
		int32_t selected_card_owner = 0;
		int32_t selected_card_zone = -1;
		int32_t selected_card_logical_index = -1;
		StringName activation_target_kind;
		int32_t activation_target_index = -1;
		bool record_direct_board_changes = true;
		int32_t trigger_card_index = -1;
		int32_t attacker_card_index = -1;
		StringName event_id;
		int32_t discovery_ability_index = -1;
		int32_t trigger_index = -1;
		std::vector<EventContext::AttackFlipRecord> attack_flips;
	};

	struct Resolution {
		struct ExtraPlayRequest {
			int32_t owner_id = 0;
			int32_t source_card_index = -1;
			int32_t source_cell = -1;
			int32_t amount = 0;
		};
		bool supported = true;
		String reason;
		Array events;
		Array captures;
		Array exiles;
		std::vector<std::pair<int64_t, int64_t>> protected_power_batch_ranges;
		std::vector<ExtraPlayRequest> extra_play_requests;
		bool flip_prevented = false;
	};

	enum class NativeActionType : uint8_t {
		PLAY,
		ACTIVATE,
	};

	struct NativeAction {
		NativeActionType type = NativeActionType::PLAY;
		int32_t source_index = -1;
		StringName source_instance_id;
		bool target_is_hand_slot = false;
		int32_t target_index = -1;
		int32_t activation_index = 0;
	};

	struct NativeSearchStats {
		int64_t nodes = 0;
		int64_t leaves = 0;
		int64_t cutoffs = 0;
		int64_t generated_actions = 0;
		int64_t applied_transitions = 0;
		int32_t max_action_ply = 0;
		int32_t root_actions_total = 0;
		int32_t root_actions_started = 0;
		int32_t root_actions_completed = 0;
		bool horizon_reached = false;
		bool aborted = false;
		bool minimum_depth_guard_used = false;
		bool supported = true;
		StringName stop_reason;
		String reason;
	};

	struct NativeSearchLimits {
		int64_t max_nodes = 0;
		bool has_deadline = false;
		std::chrono::steady_clock::time_point deadline;
		bool protect_node_limit = false;
		Callable should_cancel;
		std::unordered_map<uint64_t, NativeAction> *principal_actions = nullptr;
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
	Dictionary apply_activate_transition(
		int64_t source_cell,
		const StringName &target_kind,
		int64_t target_index,
		int64_t activation_index = 0,
		const StringName &expected_instance_id = StringName()
	) const;
	Array get_legal_actions_for_owner(int64_t owner_id) const;
	Dictionary search_fixed_round_depth(int64_t root_owner, int64_t round_depth) const;
	Dictionary search_iterative_round_depth(
		int64_t root_owner,
		int64_t max_round_depth,
		int64_t budget_usec,
		int64_t max_nodes,
		int64_t min_completed_depth,
		const Callable &should_cancel
	) const;

private:
	bool validate_shape();
	std::vector<NativeAction> get_legal_native_actions(
		const NativeState &value,
		int32_t owner_id
	) const;
	Dictionary materialize_action(const NativeAction &action) const;
	bool action_canonical_less(const NativeAction &left, const NativeAction &right) const;
	int32_t action_structural_score(
		const NativeState &value,
		const NativeAction &action
	) const;
	std::vector<NativeAction> order_search_actions(
		const NativeState &value,
		const std::vector<NativeAction> &actions,
		const NativeAction *preferred = nullptr
	) const;
	bool transition_action(
		const NativeState &source,
		const NativeAction &action,
		NativeState &next,
		Resolution &resolution,
		bool &supported,
		String &reason
	) const;
	bool transition_play(
		const NativeState &source,
		const NativeAction &action,
		NativeState &next,
		Resolution &resolution,
		bool &supported,
		String &reason
	) const;
	bool transition_activate(
		const NativeState &source,
		const NativeAction &action,
		NativeState &next,
		Resolution &resolution,
		bool &supported,
		String &reason
	) const;
	int32_t evaluate_baseline(const NativeState &value, int32_t root_owner) const;
	int32_t search_minimax(
		const NativeState &value,
		int32_t remaining_owner_turn_boundaries,
		int32_t root_owner,
		int32_t action_ply,
		int32_t alpha,
		int32_t beta,
		NativeSearchStats &stats,
		const NativeSearchLimits *limits
	) const;
	bool search_should_stop(
		NativeSearchStats &stats,
		const NativeSearchLimits *limits
	) const;
	uint64_t search_position_key(
		const NativeState &value,
		int32_t remaining_owner_turn_boundaries
	) const;
	void compile_ability_sets();
	bool compile_runtime_suppression_batches();
	CompiledCondition compile_condition(const Variant &value) const;
	CompiledSelectorCondition compile_selector_condition(const Variant &value) const;
	CompiledSelector compile_selector(const Variant &value) const;
	CompiledAction compile_action(const Variant &value);
	CompiledModifier compile_modifier(const Variant &value) const;
	CompiledTriggerRule compile_trigger_rule(const Variant &value, bool &valid);
	CompiledActivation compile_activation(const Variant &value);
	CompiledAbility compile_ability(const Variant &value);
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
	const CompiledActivation *get_activation_at(
		const NativeState &value,
		int32_t card_index,
		int32_t owner_id,
		int32_t activation_index
	) const;
	bool can_pay_activation_cost(
		const NativeState &value,
		int32_t source_card_index,
		const CompiledActivation &activation
	) const;
	std::vector<int32_t> get_activation_target_indices(
		const NativeState &value,
		int32_t owner_id,
		int32_t source_cell,
		const CompiledActivation &activation
	) const;
	bool activation_targets_hand(const CompiledActivation &activation) const;
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
	void append_resolution(Resolution &destination, const Resolution &addition) const;
	bool resolution_has_output(const Resolution &resolution) const;
	Resolution resolve_attack_request(
		NativeState &value,
		const AttackRequest &request,
		std::vector<int32_t> &exile_stack
	) const;
	Resolution resolve_summon_lifecycle(
		NativeState &value,
		const SummonRequest &request,
		std::vector<int32_t> &exile_stack
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
	ActionOutcome execute_actions_with_state(
		NativeState &value,
		const EventGroup &group,
		const std::vector<CompiledAction> &actions,
		const EventContext &event_context,
		const ActionContext &action_context,
		ActionExecutionState &execution_state,
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
		ActionExecutionState &execution_state,
		std::vector<int32_t> &exile_stack,
		Resolution &resolution
	) const;
	ActionOutcome execute_for_each_selected_card(
		NativeState &value,
		const EventGroup &group,
		const CompiledAction &action,
		const EventContext &event_context,
		const ActionContext &action_context,
		ActionExecutionState &execution_state,
		std::vector<int32_t> &exile_stack,
		Resolution &resolution
	) const;
	bool action_conditions_match(
		const NativeState &value,
		const std::vector<CompiledCondition> &conditions,
		const ActionContext &action_context,
		const ActionExecutionState &execution_state,
		bool &supported
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
	bool card_is_heart_method(const NativeState &value, int32_t card_index) const;
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
		const NativeState &value,
		Resolution &resolution,
		int64_t first_event_index,
		const EventGroup &group,
		const CompiledAction &action,
		const ActionContext &context,
		int32_t action_index
	) const;
	ActionOutcome change_ki(
		NativeState &value,
		const EventGroup &group,
		const CompiledAction &action,
		const EventContext &event_context,
		const ActionContext &action_context,
		int32_t source_cell,
		std::vector<int32_t> &exile_stack,
		Resolution &resolution
	) const;
	ActionOutcome flip_action_subject(
		NativeState &value,
		const EventGroup &group,
		const CompiledAction &action,
		const EventContext &event_context,
		const ActionContext &action_context,
		std::vector<int32_t> &exile_stack,
		Resolution &resolution
	) const;
	ActionOutcome grant_ability_to_subject(
		NativeState &value,
		const EventGroup &group,
		const CompiledAction &action,
		const ActionContext &action_context,
		int32_t event_source_card_index,
		int32_t source_cell,
		Resolution &resolution
	) const;
	ActionOutcome return_card_to_hand(
		NativeState &value,
		const EventGroup &group,
		const CompiledAction &action,
		const EventContext &event_context,
		const ActionContext &action_context,
		std::vector<int32_t> &exile_stack,
		Resolution &resolution
	) const;
	ActionOutcome swap_action_subject_with_ability_source(
		NativeState &value,
		const EventGroup &group,
		const EventContext &event_context,
		const ActionContext &action_context,
		std::vector<int32_t> &exile_stack,
		Resolution &resolution
	) const;
	ActionOutcome move_card_between_cells(
		NativeState &value,
		int32_t source_cell,
		int32_t origin_cell,
		int32_t target_cell,
		int32_t moving_card_index,
		int32_t moving_owner,
		bool resolve_before_event,
		std::vector<int32_t> &exile_stack,
		Resolution &resolution
	) const;
	Resolution resolve_movement_event(
		NativeState &value,
		const StringName &event_id,
		int32_t source_cell,
		int32_t origin_cell,
		int32_t target_cell,
		int32_t moving_card_index,
		int32_t moving_owner,
		std::vector<int32_t> &exile_stack
	) const;
	bool draw_cards(
		NativeState &value,
		int32_t owner_id,
		int32_t source_cell,
		int32_t amount,
		const String &weapon_filter,
		const EventContext &draw_context,
		std::vector<int32_t> &exile_stack,
		Resolution &resolution
	) const;
	Resolution resolve_difficulty_hand_change(
		NativeState &value,
		int32_t owner_id,
		int32_t previous_size,
		int32_t current_size,
		int32_t source_cell,
		std::vector<int32_t> &exile_stack
	) const;
	ActionOutcome discard_locked_cards(
		NativeState &value,
		const EventGroup &group,
		const std::vector<int32_t> &locked_card_indices,
		const EventContext &event_context,
		const ActionContext &action_context,
		ActionExecutionState &execution_state,
		std::vector<int32_t> &exile_stack,
		Resolution &resolution
	) const;
	ActionOutcome transform_card(
		NativeState &value,
		const EventGroup &group,
		const CompiledAction &action,
		const EventContext &event_context,
		const ActionContext &action_context,
		const ActionExecutionState &execution_state,
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
		Resolution &resolution,
		bool record_exile_index = true
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
	void clear_runtime_suppression(NativeState &value, int32_t card_index) const;
	Resolution consume_pending_hand_play_suppression(
		NativeState &value,
		int32_t card_index,
		int32_t owner_id,
		int32_t cell
	) const;
	ActionOutcome temporarily_remove_non_retained_abilities(
		NativeState &value,
		const ActionContext &action_context,
		int32_t source_cell,
		Resolution &resolution
	) const;
	int32_t resolve_action_card_reference(
		CardRefOpcode reference,
		const EventContext &event_context,
		const ActionContext &action_context,
		const ActionExecutionState &execution_state
	) const;
	int32_t initial_cell_for_reference(
		CardRefOpcode reference,
		const EventContext &event_context,
		const ActionContext &action_context,
		const ActionExecutionState &execution_state
	) const;
	int32_t resolve_relative_owner(
		const NativeState &value,
		RelativeOwnerOpcode reference,
		const ActionContext &action_context,
		int32_t referenced_card_index = -1
	) const;
	const FreshCardPrototype *find_fresh_card_prototype(
		const NativeState &value,
		const StringName &card_id
	) const;
	StringName make_generated_instance_id(
		const NativeState &value,
		const StringName &card_id
	) const;
	int32_t append_fresh_board_card(
		NativeState &value,
		const StringName &card_id,
		const StringName &instance_id,
		int32_t owner_id,
		String &reason
	) const;
	int32_t append_perfect_copy_board_card(
		NativeState &value,
		int32_t copied_card_index,
		const StringName &instance_id,
		String &reason
	) const;
	ActionOutcome summon_card(
		NativeState &value,
		const EventGroup &group,
		const CompiledAction &action,
		const EventContext &event_context,
		const ActionContext &action_context,
		ActionExecutionState &execution_state,
		std::vector<int32_t> &exile_stack,
		Resolution &resolution
	) const;
	ActionOutcome resummon_card_in_place(
		NativeState &value,
		const EventGroup &group,
		const CompiledAction &action,
		const EventContext &event_context,
		const ActionContext &action_context,
		ActionExecutionState &execution_state,
		std::vector<int32_t> &exile_stack,
		Resolution &resolution
	) const;
	ActionOutcome depart_card_for_resummon(
		NativeState &value,
		const CompiledAction &action,
		const EventContext &event_context,
		const ActionContext &action_context,
		ActionExecutionState &execution_state,
		Resolution &resolution
	) const;
	Resolution restore_temporary_abilities(
		NativeState &value,
		int32_t completed_turn
	) const;
	Array materialize_suppression_batches(
		const NativeState &value,
		int32_t card_index
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
		Resolution &resolution,
		bool record_capture_index = true
	) const;
	Dictionary restore_runtime_card(const NativeState &value, int32_t card_index) const;
	int32_t leftmost_empty_hand_slot(const NativeState &value, int32_t owner_id) const;
	bool owner_has_legal_play(const NativeState &value, int32_t owner_id) const;
	bool owner_has_legal_action(const NativeState &value, int32_t owner_id) const;
	bool is_terminal(const NativeState &value) const;
	void apply_extra_card_play_requests(
		NativeState &value,
		int32_t moving_owner,
		const std::vector<Resolution::ExtraPlayRequest> &requests,
		Resolution &resolution,
		bool coalesce
	) const;
	Resolution resolve_before_full_board_end(
		NativeState &value,
		std::vector<int32_t> &exile_stack
	) const;
	Resolution finish_action(
		NativeState &value,
		int32_t moving_owner,
		int32_t played_card_index,
		const std::vector<Resolution::ExtraPlayRequest> &extra_play_requests,
		std::vector<int32_t> &exile_stack
	) const;
	Resolution complete_owner_turn_boundary(NativeState &value) const;
	String board_repetition_signature(const NativeState &value) const;
	Dictionary to_variant_payload(const NativeState &value) const;
	uint64_t checksum(const NativeState &value) const;
};

} // namespace godot
