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

	const DuelNativeCompactKernel &kernel;
	std::vector<RootTransitionFrame> frames;
};

} // namespace godot::duel_native_internal
