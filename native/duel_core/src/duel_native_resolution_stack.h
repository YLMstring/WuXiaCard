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
		COMPLETE,
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
	};

	enum class FrameKind : uint8_t {
		EVENT,
		ACTION_SEQUENCE,
	};

	struct ResolutionFrame {
		FrameKind kind = FrameKind::EVENT;
		EventFrame event;
		ActionSequenceFrame actions;
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
	void finish_action(
		DuelNativeCompactKernel::NativeState &state,
		std::vector<int32_t> &exile_stack,
		DuelNativeCompactKernel::ActionOutcome outcome
	);
	void complete_action_frame();
	void complete_event_frame();

	const DuelNativeCompactKernel &kernel;
	std::vector<RootTransitionFrame> frames;
	std::vector<std::unique_ptr<ResolutionFrame>> resolution_frames;
	DuelNativeCompactKernel::ActionOutcome completed_action_outcome =
		DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
	DuelNativeCompactKernel::ActionExecutionState completed_action_execution_state;
	DuelNativeCompactKernel::Resolution completed_event_resolution;
};

} // namespace godot::duel_native_internal
