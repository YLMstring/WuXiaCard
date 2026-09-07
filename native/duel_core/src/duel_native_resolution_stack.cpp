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

DuelNativeCompactKernel::Resolution ResolutionEngine::run_event(
	DuelNativeCompactKernel::NativeState &state,
	const StringName &event_id,
	const DuelNativeCompactKernel::EventContext &context,
	std::vector<int32_t> &exile_stack
) {
	event_frames.clear();
	EventFrame root;
	root.event_id = event_id;
	root.context = context;
	event_frames.push_back(std::move(root));

	while (!event_frames.empty()) {
		EventFrame &frame = event_frames.back();
		if (frame.stage == EventStage::DISCOVER) {
			bool discovery_supported = true;
			String discovery_reason;
			frame.groups = kernel.discover_event(
				state,
				frame.event_id,
				frame.context,
				discovery_supported,
				discovery_reason
			);
			if (!discovery_supported) {
				frame.resolution.supported = false;
				frame.resolution.reason = discovery_reason;
				frame.stage = EventStage::COMPLETE;
				continue;
			}
			frame.stage = EventStage::NEXT_GROUP;
			continue;
		}
		if (frame.stage == EventStage::COMPLETE || frame.group_index >= frame.groups.size()) {
			DuelNativeCompactKernel::Resolution result = std::move(frame.resolution);
			event_frames.pop_back();
			return result;
		}

		DuelNativeCompactKernel::EventGroup group = frame.groups[frame.group_index++];
		const int32_t current_ability_index = kernel.find_runtime_ability_index(
			state,
			group.source_card_index,
			group.ability_handle,
			group.ability_index
		);
		bool source_is_current = false;
		int32_t current_logical_index = group.source_logical_index;
		if (group.source_zone == 3) {
			int32_t current_zone = -1;
			int32_t current_owner = 0;
			source_is_current = (
				kernel.locate_card(
					state,
					group.source_card_index,
					current_zone,
					current_owner,
					current_logical_index
				)
				&& current_zone == 3
				&& current_owner == group.source_owner
			);
		} else {
			const int32_t current_source_cell = kernel.find_board_card(
				state,
				group.source_card_index,
				group.source_cell
			);
			if (
				current_source_cell >= 0
				&& current_source_cell != group.source_cell
				&& group.source_card_index == frame.context.trigger_card_index
			) {
				group.source_cell = current_source_cell;
				group.source_logical_index = current_source_cell;
				current_logical_index = current_source_cell;
			}
			source_is_current = (
				kernel.find_board_card(state, group.source_card_index, group.source_cell)
					== group.source_cell
				&& state.board_owners[group.source_cell] == group.source_owner
			);
		}
		if (
			!source_is_current
			|| !kernel.card_effects_enabled(
				state,
				group.source_card_index,
				group.source_owner
			)
			|| current_ability_index < 0
		) continue;
		const DuelNativeCompactKernel::CompiledAbility *ability = kernel.runtime_ability(
			state,
			group.source_card_index,
			current_ability_index
		);
		if (
			ability == nullptr
			|| group.trigger_index < 0
			|| group.trigger_index >= static_cast<int32_t>(ability->triggers.size())
		) continue;
		const DuelNativeCompactKernel::CompiledTriggerRule &rule =
			ability->triggers[group.trigger_index];
		bool condition_supported = true;
		if (!kernel.conditions_match(
			state,
			group,
			rule,
			frame.context,
			condition_supported
		)) {
			if (!condition_supported) {
				frame.resolution.supported = false;
				frame.resolution.reason =
					"Relevant event uses an unsupported trigger condition";
				frame.stage = EventStage::COMPLETE;
			}
			continue;
		}

		Dictionary triggered;
		triggered["type"] = StringName("ability_triggered");
		triggered["source_cell"] = group.source_cell;
		triggered["source_instance_id"] = state.card_instance_ids[group.source_card_index];
		triggered["source_owner_id"] = group.source_owner;
		frame.resolution.events.append(triggered);

		DuelNativeCompactKernel::ActionContext action_context;
		if (frame.context.ability_source_card_index >= 0) {
			action_context.ability_source_cell = frame.context.ability_source_cell;
			action_context.ability_source_zone = frame.context.ability_source_zone;
			action_context.ability_source_logical_index =
				frame.context.ability_source_logical_index;
			action_context.ability_source_card_index = frame.context.ability_source_card_index;
			action_context.ability_source_owner = frame.context.ability_source_owner;
		} else {
			action_context.ability_source_cell = group.source_cell;
			action_context.ability_source_zone = group.source_zone;
			action_context.ability_source_logical_index = current_logical_index;
			action_context.ability_source_card_index = group.source_card_index;
			action_context.ability_source_owner = group.source_owner;
		}
		action_context.action_subject_card_index = group.source_card_index;
		action_context.action_subject_owner = group.source_owner;
		action_context.action_subject_zone = group.source_zone;
		action_context.action_subject_logical_index = current_logical_index;
		action_context.trigger_card_index = frame.context.trigger_card_index;
		action_context.attacker_card_index = frame.context.attacker_card_index;
		action_context.activation_target_kind = frame.context.activation_target_kind;
		action_context.activation_target_index = frame.context.activation_target_index;
		action_context.event_id = frame.event_id;
		action_context.discovery_ability_index = group.ability_index;
		action_context.trigger_index = group.trigger_index;
		action_context.attack_flips = frame.context.attack_flips;
		const DuelNativeCompactKernel::ActionOutcome outcome = kernel.execute_actions(
			state,
			group,
			rule.actions,
			frame.context,
			action_context,
			exile_stack,
			frame.resolution
		);
		if (outcome == DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED) {
			frame.resolution.supported = false;
			if (frame.resolution.reason.is_empty()) {
				frame.resolution.reason = "Relevant event uses an unsupported action";
			}
			frame.stage = EventStage::COMPLETE;
		}
	}
	return DuelNativeCompactKernel::Resolution();
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

Dictionary DuelNativeCompactKernel::resolve_event_iterative_for_test(
	const StringName &event_id,
	const Dictionary &context
) const {
	if (!loaded) {
		Resolution resolution;
		resolution.supported = false;
		return materialize_direct_transition(
			state,
			resolution,
			false,
			"No compact state is loaded"
		);
	}
	NativeState next = state;
	next.board_slot_extras = state.board_slot_extras.duplicate(true);
	next.side_payload = state.side_payload.duplicate(true);
	std::vector<int32_t> exile_stack;
	ResolutionEngine engine(*this);
	const Resolution resolution = engine.run_event(
		next,
		event_id,
		event_context_from_dictionary(next, context),
		exile_stack
	);
	return materialize_direct_transition(next, resolution, true);
}

} // namespace godot
