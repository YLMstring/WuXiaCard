#pragma once

#include "duel_native_compact_kernel.h"

#include <cstdint>
#include <memory>
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
	};

	enum class FrameKind : uint8_t {
		EVENT,
		ACTION_SEQUENCE,
		EXILE,
	};

	struct ResolutionFrame {
		FrameKind kind = FrameKind::EVENT;
		EventFrame event;
		ActionSequenceFrame actions;
		ExileFrame exile;
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
	void finish_action(
		DuelNativeCompactKernel::NativeState &state,
		std::vector<int32_t> &exile_stack,
		DuelNativeCompactKernel::ActionOutcome outcome
	);
	void finalize_action(DuelNativeCompactKernel::NativeState &state);
	void complete_action_frame();
	void complete_event_frame();
	void complete_exile_frame(std::vector<int32_t> &exile_stack);

	const DuelNativeCompactKernel &kernel;
	std::vector<RootTransitionFrame> frames;
	std::vector<std::unique_ptr<ResolutionFrame>> resolution_frames;
	DuelNativeCompactKernel::ActionOutcome completed_action_outcome =
		DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
	DuelNativeCompactKernel::ActionExecutionState completed_action_execution_state;
	DuelNativeCompactKernel::Resolution completed_event_resolution;
	bool completed_exile_success = true;
};

} // namespace godot::duel_native_internal
