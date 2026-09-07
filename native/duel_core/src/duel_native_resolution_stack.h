#pragma once

#include "duel_native_compact_kernel.h"

#include <cstdint>
#include <memory>
#include <unordered_map>
#include <utility>
#include <vector>

namespace godot::duel_native_internal {

class ResolutionEngine {
public:
	explicit ResolutionEngine(const DuelNativeCompactKernel &kernel_value);

	bool run_transition(
		const DuelNativeCompactKernel::NativeState &source,
		const DuelNativeCompactKernel::NativeAction &action,
		DuelNativeCompactKernel::NativeState &next,
		DuelNativeCompactKernel::Resolution &resolution,
		bool &supported,
		String &reason,
		bool materialize_presentation_payloads
	);
	DuelNativeCompactKernel::Resolution run_event(
		DuelNativeCompactKernel::NativeState &state,
		const StringName &event_id,
		const DuelNativeCompactKernel::EventContext &context,
		std::vector<int32_t> &exile_stack
	);
	DuelNativeCompactKernel::Resolution run_summon(
		DuelNativeCompactKernel::NativeState &state,
		const DuelNativeCompactKernel::SummonRequest &request,
		std::vector<int32_t> &exile_stack
	);
	DuelNativeCompactKernel::Resolution run_attack(
		DuelNativeCompactKernel::NativeState &state,
		const DuelNativeCompactKernel::AttackRequest &request,
		std::vector<int32_t> &exile_stack
	);
	DuelNativeCompactKernel::Resolution run_finish_action(
		DuelNativeCompactKernel::NativeState &state,
		int32_t moving_owner,
		int32_t played_card_index,
		const std::vector<DuelNativeCompactKernel::Resolution::ExtraPlayRequest> &
			extra_play_requests,
		std::vector<int32_t> &exile_stack
	);
	std::pair<uint64_t, uint64_t> inspect_loop_key_for_test(
		const DuelNativeCompactKernel::NativeState &state,
		const StringName &event_id,
		const DuelNativeCompactKernel::EventContext &context
	);

private:
	enum class RootStage : uint8_t {
		START,
		COMPLETE,
	};

	struct RootTransitionFrame {
		RootStage stage = RootStage::START;
		DuelNativeCompactKernel::NativeAction action;
		bool materialize_presentation_payloads = true;
	};

	enum class EventStage : uint8_t {
		DISCOVER,
		NEXT_GROUP,
		WAIT_ACTIONS,
		COMPLETE,
	};

	struct EventFrame {
		EventStage stage = EventStage::DISCOVER;
		StringName event_id;
		DuelNativeCompactKernel::EventContext context;
		std::vector<DuelNativeCompactKernel::EventGroup> groups;
		size_t group_index = 0;
		DuelNativeCompactKernel::Resolution resolution;
	};

	enum class ActionStage : uint8_t {
		NEXT_ACTION,
		WAIT_IF_ACTIONS,
		NEXT_SELECTED_CARD,
		WAIT_SELECTED_CARD_ACTIONS,
		WAIT_EXILE,
		WAIT_FLIP,
		WAIT_POWER_EXILE,
		WAIT_POWER_CHANGE,
		WAIT_DRAW,
		WAIT_DISCARD,
		WAIT_MOVE,
		WAIT_SWAP,
		WAIT_RETURN_EXILE,
		WAIT_SUMMON,
		WAIT_ATTACK,
		WAIT_DISTRIBUTE_KI,
		WAIT_TRANSFER_RESOURCE,
		NEXT_KI_EVENT,
		WAIT_KI_EVENT,
		COMPLETE,
	};

	enum class ExileStage : uint8_t {
		START,
		WAIT_BEFORE,
		MUTATE,
		WAIT_AFTER,
		COMPLETE,
	};

	struct ExileFrame {
		ExileStage stage = ExileStage::START;
		int32_t card_index = -1;
		int32_t source_cell = -1;
		int32_t ability_source_card_index = -1;
		bool self_removal = false;
		StringName exile_reason;
		DuelNativeCompactKernel::EventContext parent_context;
		DuelNativeCompactKernel::Resolution *resolution = nullptr;
		bool record_exile_index = false;
		bool guard_pushed = false;
		int32_t initial_zone = -1;
		int32_t initial_owner = 0;
		int32_t initial_index = -1;
		int32_t exiled_cell = -1;
		bool success = true;
	};

	enum class FlipStage : uint8_t {
		START,
		WAIT_BEFORE,
		WAIT_PREVENTED,
		WAIT_AFTER,
		COMPLETE,
	};

	struct FlipFrame {
		FlipStage stage = FlipStage::START;
		int32_t attacker_cell = -1;
		int32_t attacker_card_index = -1;
		int32_t target_cell = -1;
		int32_t target_card_index = -1;
		int32_t new_owner = 0;
		DuelNativeCompactKernel::EventContext context;
		DuelNativeCompactKernel::Resolution *resolution = nullptr;
		bool record_capture_index = false;
		int32_t required_attacker_owner = 0;
		std::vector<uint64_t> remove_before_after_flip;
		std::vector<uint64_t> remove_after_after_flip;
		bool success = true;
	};

	enum class AttackStage : uint8_t {
		START,
		NEXT_TARGET,
		WAIT_BE_ATTACKED,
		WAIT_FLIP,
		WAIT_AFTER_ATTACK,
		COMPLETE,
	};

	struct AttackFrame {
		AttackStage stage = AttackStage::START;
		DuelNativeCompactKernel::AttackRequest request;
		DuelNativeCompactKernel::AttackPolicy attack_policy;
		std::vector<int32_t> target_cells;
		size_t target_index = 0;
		DuelNativeCompactKernel::Resolution resolution;
		bool attack_started = false;
		bool attack_flipped_enemy = false;
		std::vector<DuelNativeCompactKernel::EventContext::AttackFlipRecord> attack_flips;
		int32_t attacker_cell = -1;
		int32_t attacked_cell = -1;
		int32_t attacked_card_index = -1;
		int32_t attacked_owner = 0;
		int32_t resolved_capture_owner = 0;
		int32_t flipped_previous_owner = 0;
		bool stop_after_current_target = false;
		int64_t flip_event_start = 0;
		DuelNativeCompactKernel::EventContext attack_context;
	};

	enum class DistributeKiStage : uint8_t {
		START,
		NEXT_ROUND,
		NEXT_RECIPIENT,
		NEXT_KI_EVENT,
		WAIT_KI_EVENT,
		COMPLETE,
	};

	struct DistributeKiFrame {
		DistributeKiStage stage = DistributeKiStage::START;
		DuelNativeCompactKernel::EventGroup group;
		DuelNativeCompactKernel::CompiledAction action;
		DuelNativeCompactKernel::EventContext event_context;
		DuelNativeCompactKernel::ActionContext action_context;
		DuelNativeCompactKernel::ActionExecutionState execution_state;
		DuelNativeCompactKernel::Resolution *resolution = nullptr;
		DuelNativeCompactKernel::ActionContext selector_context;
		std::vector<int32_t> selected_cards;
		int32_t distributor = -1;
		int32_t distributor_zone = -1;
		int32_t distributor_owner = 0;
		int32_t distributor_logical_index = -1;
		size_t recipient_index = 0;
		bool transferred_in_round = false;
		int64_t ki_event_index = 0;
		int64_t ki_event_end = 0;
		DuelNativeCompactKernel::ActionOutcome outcome =
			DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
	};

	enum class PowerChangeStage : uint8_t {
		START,
		WAIT_EXILE,
		COMPLETE,
	};

	struct PowerChangeFrame {
		PowerChangeStage stage = PowerChangeStage::START;
		DuelNativeCompactKernel::EventGroup group;
		DuelNativeCompactKernel::CompiledAction action;
		DuelNativeCompactKernel::EventContext event_context;
		DuelNativeCompactKernel::ActionContext action_context;
		int32_t source_cell = -1;
		DuelNativeCompactKernel::Resolution *resolution = nullptr;
		DuelNativeCompactKernel::ActionOutcome outcome =
			DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
	};

	enum class TransferResourceStage : uint8_t {
		START,
		WAIT_DONOR_POWERS,
		WAIT_RECEIVER_POWERS,
		COMPLETE,
	};

	struct TransferResourceFrame {
		TransferResourceStage stage = TransferResourceStage::START;
		DuelNativeCompactKernel::EventGroup group;
		DuelNativeCompactKernel::CompiledAction action;
		DuelNativeCompactKernel::EventContext event_context;
		DuelNativeCompactKernel::ActionContext action_context;
		int32_t source_cell = -1;
		DuelNativeCompactKernel::Resolution *resolution = nullptr;
		int32_t donor = -1;
		int32_t donor_owner = 0;
		int32_t receiver = -1;
		int32_t receiver_owner = 0;
		DuelNativeCompactKernel::ActionOutcome outcome =
			DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
	};

	enum class FinishActionStage : uint8_t {
		START,
		WAIT_END_OWNER_TURN,
		CHECK_BEFORE_END,
		WAIT_BEFORE_END,
		NEXT_OWNER,
		WAIT_START_OWNER_TURN,
		WAIT_EMPTY_END_OWNER_TURN,
		CHECK_EMPTY_BEFORE_END,
		WAIT_EMPTY_BEFORE_END,
		COMPLETE,
	};

	struct FinishActionFrame {
		FinishActionStage stage = FinishActionStage::START;
		int32_t moving_owner = 0;
		int32_t played_card_index = -1;
		std::vector<DuelNativeCompactKernel::Resolution::ExtraPlayRequest>
			extra_play_requests;
		DuelNativeCompactKernel::Resolution resolution;
		int32_t previous_owner = 0;
		int32_t turn_owner = 0;
	};

	enum class DrawStage : uint8_t {
		START,
		NEXT_CARD,
		WAIT_AFTER_DRAWN,
		COMPLETE,
	};

	struct DrawFrame {
		DrawStage stage = DrawStage::START;
		int32_t owner = 0;
		int32_t source_cell = -1;
		int32_t amount = 0;
		String weapon_filter;
		DuelNativeCompactKernel::EventContext draw_context;
		DuelNativeCompactKernel::Resolution *resolution = nullptr;
		Array reveal_audiences;
		int32_t draw_index = 0;
		bool success = true;
	};

	enum class DiscardStage : uint8_t {
		START,
		NEXT_CARD_EVENT,
		WAIT_CARD_EVENT,
		WAIT_BATCH_EVENT,
		COMPLETE,
	};

	struct DiscardRecord {
		int32_t card_index = -1;
		int32_t logical_hand_index = -1;
		int32_t hand_slot_index = -1;
	};

	struct DiscardFrame {
		DiscardStage stage = DiscardStage::START;
		DuelNativeCompactKernel::EventGroup group;
		std::vector<int32_t> locked_cards;
		DuelNativeCompactKernel::EventContext event_context;
		DuelNativeCompactKernel::ActionContext action_context;
		DuelNativeCompactKernel::ActionExecutionState *execution_state = nullptr;
		DuelNativeCompactKernel::Resolution *resolution = nullptr;
		std::vector<DiscardRecord> records;
		size_t record_index = 0;
		int32_t owner = 0;
		int32_t source_cell = -1;
		StringName source_instance_id;
		StringName batch_id;
		DuelNativeCompactKernel::ActionOutcome outcome =
			DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
	};

	enum class MoveStage : uint8_t {
		START,
		WAIT_BEFORE,
		MOVE,
		WAIT_AFTER,
		COMPLETE,
	};

	struct MoveFrame {
		MoveStage stage = MoveStage::START;
		int32_t source_cell = -1;
		int32_t origin_cell = -1;
		int32_t target_cell = -1;
		int32_t moving_card_index = -1;
		int32_t moving_owner = 0;
		bool resolve_before_event = true;
		DuelNativeCompactKernel::Resolution movement_resolution;
		DuelNativeCompactKernel::Resolution *resolution = nullptr;
		DuelNativeCompactKernel::ActionOutcome outcome =
			DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
	};

	enum class SwapStage : uint8_t {
		START,
		WAIT_SOURCE_BEFORE,
		WAIT_SOURCE_MOVE,
		WAIT_TARGET_BEFORE,
		WAIT_TARGET_MOVE,
		COMPLETE,
	};

	struct SwapFrame {
		SwapStage stage = SwapStage::START;
		int32_t source_card_index = -1;
		int32_t source_owner = 0;
		int32_t source_cell = -1;
		int32_t target_card_index = -1;
		int32_t target_owner = 0;
		int32_t target_cell = -1;
		Variant reserved_target_extra;
		Variant reserved_source_extra;
		DuelNativeCompactKernel::Resolution swap_resolution;
		DuelNativeCompactKernel::Resolution *resolution = nullptr;
		DuelNativeCompactKernel::ActionOutcome outcome =
			DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
	};

	enum class SummonStage : uint8_t {
		START,
		WAIT_BEFORE_SUMMONED,
		WAIT_SUMMONED,
		WAIT_AFTER_SUMMONED,
		RESOLVE_ATTACK,
		WAIT_ATTACK,
		COMPLETE,
	};

	struct SummonFrame {
		SummonStage stage = SummonStage::START;
		DuelNativeCompactKernel::SummonRequest request;
		std::vector<int32_t> attack_redirect_source_card_indices;
		DuelNativeCompactKernel::EventContext summon_context;
		DuelNativeCompactKernel::Resolution resolution;
		int32_t after_summoned_cell = -1;
	};

	struct ActionSequenceFrame {
		ActionStage stage = ActionStage::NEXT_ACTION;
		const std::vector<DuelNativeCompactKernel::CompiledAction> *actions = nullptr;
		DuelNativeCompactKernel::EventGroup group;
		DuelNativeCompactKernel::EventContext event_context;
		DuelNativeCompactKernel::ActionContext action_context;
		DuelNativeCompactKernel::ActionExecutionState execution_state;
		DuelNativeCompactKernel::Resolution *resolution = nullptr;
		size_t action_index = 0;
		DuelNativeCompactKernel::ActionOutcome aggregate =
			DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
		bool defer_power_change_batch = false;
		size_t active_action_index = 0;
		int64_t first_event_index = 0;
		std::vector<int32_t> selected_cards;
		size_t selected_card_index = 0;
		DuelNativeCompactKernel::ActionOutcome selected_aggregate =
			DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
		DuelNativeCompactKernel::ActionOutcome pending_outcome =
			DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
		int64_t direct_event_end = 0;
		int64_t ki_event_index = 0;
		int64_t ki_resolution_start = 0;
		int32_t child_target_cell = -1;
		bool update_source_after_swap = false;
		int64_t return_previous_event_count = 0;
	};

	enum class FrameKind : uint8_t {
		EVENT,
		ACTION_SEQUENCE,
		EXILE,
		FLIP,
		DRAW,
		DISCARD,
		MOVE,
		SWAP,
		SUMMON,
		ATTACK,
		DISTRIBUTE_KI,
		POWER_CHANGE,
		TRANSFER_RESOURCE,
		FINISH_ACTION,
	};

	struct ResolutionFrame {
		FrameKind kind = FrameKind::EVENT;
		uint64_t causal_board_first = 0;
		uint64_t causal_board_second = 0;
		bool causal_board_initialized = false;
		EventFrame event;
		ActionSequenceFrame actions;
		ExileFrame exile;
		FlipFrame flip;
		DrawFrame draw;
		DiscardFrame discard;
		MoveFrame move;
		SwapFrame swap;
		SummonFrame summon;
		AttackFrame attack;
		DistributeKiFrame distribute_ki;
		PowerChangeFrame power_change;
		TransferResourceFrame transfer_resource;
		FinishActionFrame finish_action;
	};

	struct LoopFingerprint {
		uint64_t first = 0;
		uint64_t second = 0;

		bool operator==(const LoopFingerprint &other) const {
			return first == other.first && second == other.second;
		}
	};

	struct LoopFingerprintHash {
		size_t operator()(const LoopFingerprint &value) const {
			return static_cast<size_t>(
				value.first ^ (value.second + 0x9e3779b97f4a7c15ULL
					+ (value.first << 6) + (value.first >> 2))
			);
		}
	};

	DuelNativeCompactKernel::ActionOutcome run_actions(
		DuelNativeCompactKernel::NativeState &state,
		const DuelNativeCompactKernel::EventGroup &group,
		const std::vector<DuelNativeCompactKernel::CompiledAction> &actions,
		const DuelNativeCompactKernel::EventContext &event_context,
		const DuelNativeCompactKernel::ActionContext &action_context,
		DuelNativeCompactKernel::ActionExecutionState execution_state,
		std::vector<int32_t> &exile_stack,
		DuelNativeCompactKernel::Resolution &resolution,
		bool defer_power_change_batch = false
	);
	void push_event_frame(
		const StringName &event_id,
		const DuelNativeCompactKernel::EventContext &context
	);
	void push_action_frame(
		const DuelNativeCompactKernel::EventGroup &group,
		const std::vector<DuelNativeCompactKernel::CompiledAction> &actions,
		const DuelNativeCompactKernel::EventContext &event_context,
		const DuelNativeCompactKernel::ActionContext &action_context,
		DuelNativeCompactKernel::ActionExecutionState execution_state,
		DuelNativeCompactKernel::Resolution &resolution,
		bool defer_power_change_batch
	);
	void push_exile_frame(
		int32_t card_index,
		int32_t source_cell,
		int32_t ability_source_card_index,
		bool self_removal,
		const StringName &exile_reason,
		const DuelNativeCompactKernel::EventContext &parent_context,
		DuelNativeCompactKernel::Resolution &resolution,
		bool record_exile_index
	);
	void push_flip_frame(
		int32_t attacker_cell,
		int32_t attacker_card_index,
		int32_t target_cell,
		int32_t target_card_index,
		int32_t new_owner,
		const DuelNativeCompactKernel::EventContext &context,
		DuelNativeCompactKernel::Resolution &resolution,
		bool record_capture_index,
		int32_t required_attacker_owner = 0
	);
	void push_draw_frame(
		int32_t owner,
		int32_t source_cell,
		int32_t amount,
		const String &weapon_filter,
		const DuelNativeCompactKernel::EventContext &draw_context,
		DuelNativeCompactKernel::Resolution &resolution
	);
	void push_discard_frame(
		const DuelNativeCompactKernel::EventGroup &group,
		std::vector<int32_t> locked_cards,
		const DuelNativeCompactKernel::EventContext &event_context,
		const DuelNativeCompactKernel::ActionContext &action_context,
		DuelNativeCompactKernel::ActionExecutionState &execution_state,
		DuelNativeCompactKernel::Resolution &resolution
	);
	void push_move_frame(
		int32_t source_cell,
		int32_t origin_cell,
		int32_t target_cell,
		int32_t moving_card_index,
		int32_t moving_owner,
		bool resolve_before_event,
		DuelNativeCompactKernel::Resolution &resolution
	);
	void push_swap_frame(
		int32_t source_card_index,
		int32_t source_owner,
		int32_t source_cell,
		int32_t target_card_index,
		int32_t target_owner,
		int32_t target_cell,
		DuelNativeCompactKernel::Resolution &resolution
	);
	void push_summon_frame(const DuelNativeCompactKernel::SummonRequest &request);
	void push_attack_frame(const DuelNativeCompactKernel::AttackRequest &request);
	void push_distribute_ki_frame(
		const DuelNativeCompactKernel::EventGroup &group,
		const DuelNativeCompactKernel::CompiledAction &action,
		const DuelNativeCompactKernel::EventContext &event_context,
		const DuelNativeCompactKernel::ActionContext &action_context,
		const DuelNativeCompactKernel::ActionExecutionState &execution_state,
		DuelNativeCompactKernel::Resolution &resolution
	);
	void push_power_change_frame(
		const DuelNativeCompactKernel::EventGroup &group,
		const DuelNativeCompactKernel::CompiledAction &action,
		const DuelNativeCompactKernel::EventContext &event_context,
		const DuelNativeCompactKernel::ActionContext &action_context,
		int32_t source_cell,
		DuelNativeCompactKernel::Resolution &resolution
	);
	void push_transfer_resource_frame(
		const DuelNativeCompactKernel::EventGroup &group,
		const DuelNativeCompactKernel::CompiledAction &action,
		const DuelNativeCompactKernel::EventContext &event_context,
		const DuelNativeCompactKernel::ActionContext &action_context,
		int32_t source_cell,
		DuelNativeCompactKernel::Resolution &resolution
	);
	void push_finish_action_frame(
		int32_t moving_owner,
		int32_t played_card_index,
		const std::vector<DuelNativeCompactKernel::Resolution::ExtraPlayRequest> &
			extra_play_requests
	);
	void run_resolution_stack(
		DuelNativeCompactKernel::NativeState &state,
		std::vector<int32_t> &exile_stack
	);
	void step_event_frame(
		DuelNativeCompactKernel::NativeState &state,
		std::vector<int32_t> &exile_stack
	);
	void step_action_frame(
		DuelNativeCompactKernel::NativeState &state,
		std::vector<int32_t> &exile_stack
	);
	void step_exile_frame(
		DuelNativeCompactKernel::NativeState &state,
		std::vector<int32_t> &exile_stack
	);
	void step_flip_frame(
		DuelNativeCompactKernel::NativeState &state,
		std::vector<int32_t> &exile_stack
	);
	void step_draw_frame(
		DuelNativeCompactKernel::NativeState &state,
		std::vector<int32_t> &exile_stack
	);
	void step_discard_frame(
		DuelNativeCompactKernel::NativeState &state,
		std::vector<int32_t> &exile_stack
	);
	void step_move_frame(
		DuelNativeCompactKernel::NativeState &state,
		std::vector<int32_t> &exile_stack
	);
	void step_swap_frame(
		DuelNativeCompactKernel::NativeState &state,
		std::vector<int32_t> &exile_stack
	);
	void step_summon_frame(
		DuelNativeCompactKernel::NativeState &state,
		std::vector<int32_t> &exile_stack
	);
	void step_attack_frame(
		DuelNativeCompactKernel::NativeState &state,
		std::vector<int32_t> &exile_stack
	);
	void step_distribute_ki_frame(
		DuelNativeCompactKernel::NativeState &state,
		std::vector<int32_t> &exile_stack
	);
	void step_power_change_frame(
		DuelNativeCompactKernel::NativeState &state,
		std::vector<int32_t> &exile_stack
	);
	void step_transfer_resource_frame(
		DuelNativeCompactKernel::NativeState &state,
		std::vector<int32_t> &exile_stack
	);
	void step_finish_action_frame(
		DuelNativeCompactKernel::NativeState &state,
		std::vector<int32_t> &exile_stack
	);
	void finish_action(
		DuelNativeCompactKernel::NativeState &state,
		std::vector<int32_t> &exile_stack,
		DuelNativeCompactKernel::ActionOutcome outcome
	);
	void finalize_action(DuelNativeCompactKernel::NativeState &state);
	void complete_action_frame();
	void complete_event_frame();
	void complete_exile_frame(std::vector<int32_t> &exile_stack);
	void complete_flip_frame();
	void complete_draw_frame();
	void complete_discard_frame();
	void complete_move_frame();
	void complete_swap_frame();
	void complete_summon_frame();
	void complete_attack_frame();
	void complete_distribute_ki_frame();
	void complete_power_change_frame();
	void complete_transfer_resource_frame();
	void complete_finish_action_frame();
	void reset_loop_detection();
	bool detect_resolution_loop(DuelNativeCompactKernel::NativeState &state);
	LoopFingerprint fingerprint_frame_range(
		const DuelNativeCompactKernel::NativeState &state,
		size_t begin,
		size_t end,
		bool causal
	) const;
	LoopFingerprint fingerprint_loop_key(
		const DuelNativeCompactKernel::NativeState &state
	) const;
	LoopFingerprint fingerprint_board_turn(
		const DuelNativeCompactKernel::NativeState &state
	) const;
	bool has_repeated_causal_suffix(
		const DuelNativeCompactKernel::NativeState &state
	) const;
	DuelNativeCompactKernel::Resolution collect_partial_resolution() const;

	const DuelNativeCompactKernel &kernel;
	std::vector<RootTransitionFrame> frames;
	std::vector<std::unique_ptr<ResolutionFrame>> resolution_frames;
	DuelNativeCompactKernel::ActionOutcome completed_action_outcome =
		DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
	DuelNativeCompactKernel::ActionExecutionState completed_action_execution_state;
	DuelNativeCompactKernel::Resolution completed_event_resolution;
	bool completed_exile_success = true;
	bool completed_flip_success = true;
	bool completed_draw_success = true;
	DuelNativeCompactKernel::ActionOutcome completed_discard_outcome =
		DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
	DuelNativeCompactKernel::ActionOutcome completed_move_outcome =
		DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
	DuelNativeCompactKernel::ActionOutcome completed_swap_outcome =
		DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
	DuelNativeCompactKernel::Resolution completed_summon_resolution;
	DuelNativeCompactKernel::Resolution completed_attack_resolution;
	DuelNativeCompactKernel::ActionOutcome completed_distribute_ki_outcome =
		DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
	DuelNativeCompactKernel::ActionOutcome completed_power_change_outcome =
		DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
	DuelNativeCompactKernel::ActionOutcome completed_transfer_resource_outcome =
		DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
	DuelNativeCompactKernel::Resolution completed_finish_action_resolution;
	std::unordered_map<LoopFingerprint, uint8_t, LoopFingerprintHash>
		loop_occurrences;
	bool loop_detection_active = false;
	bool resolution_loop_detected = false;
	bool resolution_aborted = false;
	DuelNativeCompactKernel::Resolution resolution_loop_output;
	uint64_t resolution_step_count = 0;
};

} // namespace godot::duel_native_internal
