#pragma once

#include "duel_native_compact_kernel.h"

#include <cstdint>
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

	struct ActionSequenceFrame {
		const std::vector<DuelNativeCompactKernel::CompiledAction> *actions = nullptr;
		DuelNativeCompactKernel::EventGroup group;
		DuelNativeCompactKernel::EventContext event_context;
		DuelNativeCompactKernel::ActionContext action_context;
		DuelNativeCompactKernel::ActionExecutionState execution_state;
		size_t action_index = 0;
		DuelNativeCompactKernel::ActionOutcome aggregate =
			DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
		bool defer_power_change_batch = false;
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

	const DuelNativeCompactKernel &kernel;
	std::vector<RootTransitionFrame> frames;
	std::vector<EventFrame> event_frames;
	std::vector<ActionSequenceFrame> action_frames;
};

} // namespace godot::duel_native_internal
