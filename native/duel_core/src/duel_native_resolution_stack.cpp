#include "duel_native_resolution_stack.h"

#include "duel_native_compact_kernel_internal.h"

namespace godot::duel_native_internal {

ResolutionEngine::ResolutionEngine(const DuelNativeCompactKernel &kernel_value)
	: kernel(kernel_value) {}

DuelNativeCompactKernel::ActionOutcome ResolutionEngine::run_actions(
	DuelNativeCompactKernel::NativeState &state,
	const DuelNativeCompactKernel::EventGroup &group,
	const std::vector<DuelNativeCompactKernel::CompiledAction> &actions,
	const DuelNativeCompactKernel::EventContext &event_context,
	const DuelNativeCompactKernel::ActionContext &action_context,
	DuelNativeCompactKernel::ActionExecutionState execution_state,
	std::vector<int32_t> &exile_stack,
	DuelNativeCompactKernel::Resolution &resolution,
	bool defer_power_change_batch
) {
	action_frames.clear();
	ActionSequenceFrame root;
	root.actions = &actions;
	root.group = group;
	root.event_context = event_context;
	root.action_context = action_context;
	root.execution_state = std::move(execution_state);
	root.defer_power_change_batch = defer_power_change_batch;
	action_frames.push_back(std::move(root));

	while (!action_frames.empty()) {
		ActionSequenceFrame &frame = action_frames.back();
		if (frame.actions == nullptr || frame.action_index >= frame.actions->size()) {
			const DuelNativeCompactKernel::ActionOutcome result = frame.aggregate;
			action_frames.pop_back();
			return result;
		}
		const size_t action_index = frame.action_index++;
		const DuelNativeCompactKernel::CompiledAction &action = (*frame.actions)[action_index];
		const int64_t first_event_index = resolution.events.size();
		const DuelNativeCompactKernel::ActionOutcome outcome = kernel.execute_action(
			state,
			frame.group,
			action,
			frame.event_context,
			frame.action_context,
			frame.execution_state,
			exile_stack,
			resolution
		);
		const int64_t direct_event_end = resolution.events.size();
		if (
			direct_event_end > first_event_index
			&& (
				action.opcode == DuelNativeCompactKernel::ActionOpcode::ATTACK_TRIGGER_CARD
				|| action.opcode == DuelNativeCompactKernel::ActionOpcode::STANDARD_ATTACK_WITH_SELF
				|| action.opcode == DuelNativeCompactKernel::ActionOpcode::STANDARD_ATTACK_WITH_CARD
				|| action.opcode == DuelNativeCompactKernel::ActionOpcode::FLIP_SELF
				|| action.opcode == DuelNativeCompactKernel::ActionOpcode::SUMMON_CARD
				|| action.opcode == DuelNativeCompactKernel::ActionOpcode::RESUMMON_CARD_IN_PLACE
			)
		) {
			resolution.protected_power_batch_ranges.push_back({
				first_event_index,
				direct_event_end,
			});
		}
		for (
			int64_t event_index = first_event_index;
			action.opcode != DuelNativeCompactKernel::ActionOpcode::DISTRIBUTE_KI
				&& event_index < direct_event_end;
			++event_index
		) {
			const Variant event_value = resolution.events[event_index];
			if (event_value.get_type() != Variant::DICTIONARY) continue;
			const Dictionary ki_event = event_value;
			if (StringName(ki_event.get("type", StringName())) != StringName("ki_changed")) {
				continue;
			}
			DuelNativeCompactKernel::EventContext ki_context;
			ki_context.trigger_cell = static_cast<int32_t>(
				static_cast<int64_t>(ki_event.get("target_cell", -1))
			);
			const StringName instance_id = ki_event.get("instance_id", StringName());
			for (size_t card_index = 0; card_index < state.card_instance_ids.size(); ++card_index) {
				if (state.card_instance_ids[card_index] == instance_id) {
					ki_context.trigger_card_index = static_cast<int32_t>(card_index);
					break;
				}
			}
			ki_context.trigger_owner = static_cast<int32_t>(
				static_cast<int64_t>(ki_event.get("owner_id", 0))
			);
			ki_context.previous_ki = static_cast<int32_t>(
				static_cast<int64_t>(ki_event.get("previous_ki", 0))
			);
			ki_context.ki = static_cast<int32_t>(
				static_cast<int64_t>(ki_event.get("ki", -1))
			);
			DuelNativeCompactKernel::Resolution ki_resolution = kernel.resolve_event(
				state,
				StringName("card_ki_changed"),
				ki_context,
				exile_stack
			);
			if (!ki_resolution.supported) {
				resolution.reason = ki_resolution.reason;
				action_frames.clear();
				return DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
			}
			const int64_t ki_resolution_start = resolution.events.size();
			kernel.append_resolution(resolution, ki_resolution);
			const int64_t ki_resolution_end = resolution.events.size();
			if (ki_resolution_end > ki_resolution_start) {
				resolution.protected_power_batch_ranges.push_back({
					ki_resolution_start,
					ki_resolution_end,
				});
			}
		}
		if (!frame.defer_power_change_batch) {
			kernel.assign_power_change_batch(
				state,
				resolution,
				first_event_index,
				frame.group,
				action,
				frame.action_context,
				static_cast<int32_t>(action_index)
			);
		}
		if (outcome == DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED) {
			if (resolution.reason.is_empty()) {
				resolution.reason = String("Unsupported compiled action opcode ")
					+ String::num_int64(static_cast<int64_t>(action.opcode))
					+ String(" type=") + String(action.declaration_type);
			}
			action_frames.clear();
			return outcome;
		}
		if (outcome == DuelNativeCompactKernel::ActionOutcome::INVALID_CONTEXT) {
			action_frames.clear();
			return outcome;
		}
		if (
			outcome == DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
			&& action.stop_rule_on_invalid_context
		) {
			action_frames.clear();
			return DuelNativeCompactKernel::ActionOutcome::INVALID_CONTEXT;
		}
		if (outcome == DuelNativeCompactKernel::ActionOutcome::APPLIED) {
			frame.aggregate = DuelNativeCompactKernel::ActionOutcome::APPLIED;
		}
	}
	return DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
}

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
		DuelNativeCompactKernel::ActionExecutionState execution_state;
		execution_state.current_source_cell = group.source_cell;
		const DuelNativeCompactKernel::ActionOutcome outcome = run_actions(
			state,
			group,
			rule.actions,
			frame.context,
			action_context,
			std::move(execution_state),
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
