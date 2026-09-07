#include "duel_native_resolution_stack.h"

#include "duel_native_compact_kernel_internal.h"

namespace godot::duel_native_internal {

ResolutionEngine::ResolutionEngine(const DuelNativeCompactKernel &kernel_value)
	: kernel(kernel_value) {}

bool ResolutionEngine::run_transition(
	const DuelNativeCompactKernel::NativeState &source,
	const DuelNativeCompactKernel::NativeAction &action,
	DuelNativeCompactKernel::NativeState &next,
	DuelNativeCompactKernel::Resolution &resolution,
	bool &supported,
	String &reason,
	bool materialize_presentation_payloads
) {
	frames.clear();
	RootTransitionFrame root;
	root.action = action;
	root.materialize_presentation_payloads = materialize_presentation_payloads;
	frames.push_back(root);

	bool valid = false;
	while (!frames.empty()) {
		RootTransitionFrame &frame = frames.back();
		switch (frame.stage) {
			case RootStage::START:
				frame.stage = RootStage::COMPLETE;
				valid = kernel.transition_action(
					source,
					frame.action,
					next,
					resolution,
					supported,
					reason,
					frame.materialize_presentation_payloads
				);
				break;
			case RootStage::COMPLETE:
				frames.pop_back();
				break;
		}
	}
	return valid;
}

} // namespace godot::duel_native_internal

namespace godot {
using namespace duel_native_internal;

Dictionary DuelNativeCompactKernel::apply_iterative_transition_for_test(
	const Dictionary &action_value
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

	const StringName action_type = StringName(action_value.get("action_type", StringName()));
	const StringName source_zone = StringName(action_value.get("source_zone", StringName()));
	const StringName target_kind = StringName(action_value.get("target_kind", StringName()));
	NativeAction action;
	if (action_type == StringName("play")) {
		if (source_zone != StringName("hand") || target_kind != StringName("board_cell")) {
			result["reason"] = "Malformed play action";
			return result;
		}
		action.type = NativeActionType::PLAY;
	} else if (action_type == StringName("activate")) {
		if (
			source_zone != StringName("board")
			|| (target_kind != StringName("board_cell") && target_kind != StringName("hand_slot"))
		) {
			result["reason"] = "Malformed activation action";
			return result;
		}
		action.type = NativeActionType::ACTIVATE;
	} else {
		result["reason"] = "Unknown action type";
		return result;
	}
	action.source_index = static_cast<int32_t>(
		static_cast<int64_t>(action_value.get("source_index", -1))
	);
	action.source_instance_id = StringName(
		action_value.get("source_instance_id", StringName())
	);
	action.target_is_hand_slot = target_kind == StringName("hand_slot");
	action.target_index = static_cast<int32_t>(
		static_cast<int64_t>(action_value.get("target_index", -1))
	);
	action.activation_index = static_cast<int32_t>(
		static_cast<int64_t>(action_value.get("activation_index", 0))
	);

	NativeState next;
	Resolution resolution;
	bool supported = false;
	String reason;
	ResolutionEngine engine(*this);
	const bool valid = engine.run_transition(
		state,
		action,
		next,
		resolution,
		supported,
		reason,
		true
	);
	result["supported"] = supported;
	result["valid"] = valid;
	result["reason"] = reason;
	if (!valid) return result;
	result["captures"] = resolution.captures;
	result["exiles"] = resolution.exiles;
	result["events"] = resolution.events;
	result["payload"] = to_variant_payload(next);
	return result;
}

} // namespace godot
