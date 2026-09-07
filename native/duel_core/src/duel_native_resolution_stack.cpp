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
	resolution_frames.clear();
	push_action_frame(
		group,
		actions,
		event_context,
		action_context,
		std::move(execution_state),
		resolution,
		defer_power_change_batch
	);
	run_resolution_stack(state, exile_stack);
	return completed_action_outcome;
}

void ResolutionEngine::push_event_frame(
	const StringName &event_id,
	const DuelNativeCompactKernel::EventContext &context
) {
	auto frame = std::make_unique<ResolutionFrame>();
	frame->kind = FrameKind::EVENT;
	frame->event.event_id = event_id;
	frame->event.context = context;
	resolution_frames.push_back(std::move(frame));
}

void ResolutionEngine::push_action_frame(
	const DuelNativeCompactKernel::EventGroup &group,
	const std::vector<DuelNativeCompactKernel::CompiledAction> &actions,
	const DuelNativeCompactKernel::EventContext &event_context,
	const DuelNativeCompactKernel::ActionContext &action_context,
	DuelNativeCompactKernel::ActionExecutionState execution_state,
	DuelNativeCompactKernel::Resolution &resolution,
	bool defer_power_change_batch
) {
	auto frame = std::make_unique<ResolutionFrame>();
	frame->kind = FrameKind::ACTION_SEQUENCE;
	frame->actions.actions = &actions;
	frame->actions.group = group;
	frame->actions.event_context = event_context;
	frame->actions.action_context = action_context;
	frame->actions.execution_state = std::move(execution_state);
	frame->actions.resolution = &resolution;
	frame->actions.defer_power_change_batch = defer_power_change_batch;
	resolution_frames.push_back(std::move(frame));
}

void ResolutionEngine::push_exile_frame(
	int32_t card_index,
	int32_t source_cell,
	int32_t ability_source_card_index,
	bool self_removal,
	const StringName &exile_reason,
	const DuelNativeCompactKernel::EventContext &parent_context,
	DuelNativeCompactKernel::Resolution &resolution,
	bool record_exile_index
) {
	auto frame = std::make_unique<ResolutionFrame>();
	frame->kind = FrameKind::EXILE;
	frame->exile.card_index = card_index;
	frame->exile.source_cell = source_cell;
	frame->exile.ability_source_card_index = ability_source_card_index;
	frame->exile.self_removal = self_removal;
	frame->exile.exile_reason = exile_reason;
	frame->exile.parent_context = parent_context;
	frame->exile.resolution = &resolution;
	frame->exile.record_exile_index = record_exile_index;
	resolution_frames.push_back(std::move(frame));
}

void ResolutionEngine::run_resolution_stack(
	DuelNativeCompactKernel::NativeState &state,
	std::vector<int32_t> &exile_stack
) {
	while (!resolution_frames.empty()) {
		if (resolution_frames.back()->kind == FrameKind::EVENT) {
			step_event_frame(state, exile_stack);
		} else if (resolution_frames.back()->kind == FrameKind::ACTION_SEQUENCE) {
			step_action_frame(state, exile_stack);
		} else {
			step_exile_frame(state, exile_stack);
		}
	}
}

void ResolutionEngine::complete_action_frame() {
	ActionSequenceFrame &frame = resolution_frames.back()->actions;
	completed_action_outcome = frame.aggregate;
	completed_action_execution_state = std::move(frame.execution_state);
	resolution_frames.pop_back();
}

void ResolutionEngine::complete_event_frame() {
	completed_event_resolution = std::move(resolution_frames.back()->event.resolution);
	resolution_frames.pop_back();
}

void ResolutionEngine::complete_exile_frame(std::vector<int32_t> &exile_stack) {
	ExileFrame &frame = resolution_frames.back()->exile;
	if (frame.guard_pushed) {
		const auto found = std::find(exile_stack.rbegin(), exile_stack.rend(), frame.card_index);
		if (found != exile_stack.rend()) exile_stack.erase(std::next(found).base());
		frame.guard_pushed = false;
	}
	completed_exile_success = frame.success;
	resolution_frames.pop_back();
}

void ResolutionEngine::finish_action(
	DuelNativeCompactKernel::NativeState &state,
	std::vector<int32_t> &exile_stack,
	DuelNativeCompactKernel::ActionOutcome outcome
) {
	(void)state;
	(void)exile_stack;
	ActionSequenceFrame &frame = resolution_frames.back()->actions;
	if (frame.actions == nullptr || frame.resolution == nullptr) {
		frame.aggregate = DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
		frame.stage = ActionStage::COMPLETE;
		return;
	}
	const DuelNativeCompactKernel::CompiledAction &action =
		(*frame.actions)[frame.active_action_index];
	DuelNativeCompactKernel::Resolution &resolution = *frame.resolution;
	frame.pending_outcome = outcome;
	frame.direct_event_end = resolution.events.size();
	frame.ki_event_index = frame.first_event_index;
	if (
		frame.direct_event_end > frame.first_event_index
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
			frame.first_event_index,
			frame.direct_event_end,
		});
	}
	frame.stage = ActionStage::NEXT_KI_EVENT;
}

void ResolutionEngine::finalize_action(DuelNativeCompactKernel::NativeState &state) {
	ActionSequenceFrame &frame = resolution_frames.back()->actions;
	const DuelNativeCompactKernel::CompiledAction &action =
		(*frame.actions)[frame.active_action_index];
	DuelNativeCompactKernel::Resolution &resolution = *frame.resolution;
	if (!frame.defer_power_change_batch) {
		kernel.assign_power_change_batch(
			state,
			resolution,
			frame.first_event_index,
			frame.group,
			action,
			frame.action_context,
			static_cast<int32_t>(frame.active_action_index)
		);
	}
	if (frame.pending_outcome == DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED) {
		if (resolution.reason.is_empty()) {
			resolution.reason = String("Unsupported compiled action opcode ")
				+ String::num_int64(static_cast<int64_t>(action.opcode))
				+ String(" type=") + String(action.declaration_type);
		}
		frame.aggregate = frame.pending_outcome;
		frame.stage = ActionStage::COMPLETE;
		return;
	}
	if (frame.pending_outcome == DuelNativeCompactKernel::ActionOutcome::INVALID_CONTEXT) {
		frame.aggregate = frame.pending_outcome;
		frame.stage = ActionStage::COMPLETE;
		return;
	}
	if (
		frame.pending_outcome == DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
		&& action.stop_rule_on_invalid_context
	) {
		frame.aggregate = DuelNativeCompactKernel::ActionOutcome::INVALID_CONTEXT;
		frame.stage = ActionStage::COMPLETE;
		return;
	}
	if (frame.pending_outcome == DuelNativeCompactKernel::ActionOutcome::APPLIED) {
		frame.aggregate = DuelNativeCompactKernel::ActionOutcome::APPLIED;
	}
	frame.stage = ActionStage::NEXT_ACTION;
}

void ResolutionEngine::step_action_frame(
	DuelNativeCompactKernel::NativeState &state,
	std::vector<int32_t> &exile_stack
) {
	ActionSequenceFrame &frame = resolution_frames.back()->actions;
	if (frame.stage == ActionStage::COMPLETE || frame.actions == nullptr) {
		complete_action_frame();
		return;
	}
	if (frame.stage == ActionStage::WAIT_EXILE) {
		finish_action(
			state,
			exile_stack,
			completed_exile_success
				? DuelNativeCompactKernel::ActionOutcome::APPLIED
				: DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED
		);
		return;
	}
	if (frame.stage == ActionStage::WAIT_KI_EVENT) {
		DuelNativeCompactKernel::Resolution &resolution = *frame.resolution;
		if (!completed_event_resolution.supported) {
			resolution.reason = completed_event_resolution.reason;
			frame.aggregate = DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
			frame.stage = ActionStage::COMPLETE;
			return;
		}
		kernel.append_resolution(resolution, completed_event_resolution);
		const int64_t ki_resolution_end = resolution.events.size();
		if (ki_resolution_end > frame.ki_resolution_start) {
			resolution.protected_power_batch_ranges.push_back({
				frame.ki_resolution_start,
				ki_resolution_end,
			});
		}
		frame.stage = ActionStage::NEXT_KI_EVENT;
		return;
	}
	if (frame.stage == ActionStage::NEXT_KI_EVENT) {
		const DuelNativeCompactKernel::CompiledAction &action =
			(*frame.actions)[frame.active_action_index];
		DuelNativeCompactKernel::Resolution &resolution = *frame.resolution;
		while (
			action.opcode != DuelNativeCompactKernel::ActionOpcode::DISTRIBUTE_KI
			&& frame.ki_event_index < frame.direct_event_end
		) {
			const Variant event_value = resolution.events[frame.ki_event_index++];
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
			frame.ki_resolution_start = resolution.events.size();
			frame.stage = ActionStage::WAIT_KI_EVENT;
			push_event_frame(StringName("card_ki_changed"), ki_context);
			return;
		}
		finalize_action(state);
		return;
	}

	if (frame.stage == ActionStage::WAIT_IF_ACTIONS) {
		frame.execution_state = std::move(completed_action_execution_state);
		finish_action(state, exile_stack, completed_action_outcome);
		return;
	}
	if (frame.stage == ActionStage::WAIT_SELECTED_CARD_ACTIONS) {
		if (
			completed_action_outcome == DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED
			|| completed_action_outcome == DuelNativeCompactKernel::ActionOutcome::INVALID_CONTEXT
		) {
			finish_action(state, exile_stack, completed_action_outcome);
			return;
		}
		if (completed_action_outcome == DuelNativeCompactKernel::ActionOutcome::APPLIED) {
			frame.selected_aggregate = DuelNativeCompactKernel::ActionOutcome::APPLIED;
		}
		frame.stage = ActionStage::NEXT_SELECTED_CARD;
		return;
	}
	if (frame.stage == ActionStage::NEXT_SELECTED_CARD) {
		const DuelNativeCompactKernel::CompiledAction &action =
			(*frame.actions)[frame.active_action_index];
		while (frame.selected_card_index < frame.selected_cards.size()) {
			const int32_t selected_card = frame.selected_cards[frame.selected_card_index++];
			int32_t zone = -1;
			int32_t owner = 0;
			int32_t logical_index = -1;
			if (!kernel.locate_card(state, selected_card, zone, owner, logical_index) || zone == 2) {
				continue;
			}
			bool condition_supported = true;
			if (!kernel.selector_conditions_match(
				state,
				selected_card,
				zone,
				owner,
				logical_index,
				action.selector,
				frame.action_context,
				condition_supported
			)) {
				if (!condition_supported) {
					finish_action(
						state,
						exile_stack,
						DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED
					);
					return;
				}
				continue;
			}
			DuelNativeCompactKernel::ActionContext nested_context = frame.action_context;
			nested_context.action_subject_card_index = selected_card;
			nested_context.action_subject_owner = owner;
			nested_context.action_subject_zone = zone;
			nested_context.action_subject_logical_index = logical_index;
			nested_context.selected_card_index = selected_card;
			nested_context.selected_card_owner = owner;
			nested_context.selected_card_zone = zone;
			nested_context.selected_card_logical_index = logical_index;
			DuelNativeCompactKernel::ActionExecutionState nested_execution_state =
				frame.execution_state;
			nested_execution_state.current_source_cell = zone == 0 ? logical_index : -1;
			frame.stage = ActionStage::WAIT_SELECTED_CARD_ACTIONS;
			push_action_frame(
				frame.group,
				action.child_actions,
				frame.event_context,
				nested_context,
				std::move(nested_execution_state),
				*frame.resolution,
				true
			);
			return;
		}
		finish_action(state, exile_stack, frame.selected_aggregate);
		return;
	}
	if (frame.action_index >= frame.actions->size()) {
		complete_action_frame();
		return;
	}

	frame.active_action_index = frame.action_index++;
	const DuelNativeCompactKernel::CompiledAction &action =
		(*frame.actions)[frame.active_action_index];
	frame.first_event_index = frame.resolution == nullptr
		? 0
		: frame.resolution->events.size();
	if (!action.declaration_valid) {
		finish_action(state, exile_stack, DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED);
		return;
	}
	if (
		action.opcode == DuelNativeCompactKernel::ActionOpcode::EXILE_SELF
		|| action.opcode == DuelNativeCompactKernel::ActionOpcode::EXILE_CARD
	) {
		int32_t target = frame.action_context.action_subject_card_index;
		bool self_removal = true;
		StringName reason("ability_exile_self");
		if (action.opcode == DuelNativeCompactKernel::ActionOpcode::EXILE_CARD) {
			self_removal = false;
			reason = StringName("ability_exile_card");
			if (action.card_ref == DuelNativeCompactKernel::CardRefOpcode::SELECTED_CARD) {
				target = frame.action_context.selected_card_index;
			} else if (action.card_ref == DuelNativeCompactKernel::CardRefOpcode::TRIGGER_CARD) {
				target = frame.event_context.trigger_card_index;
			} else if (action.card_ref == DuelNativeCompactKernel::CardRefOpcode::ABILITY_SOURCE) {
				target = frame.action_context.ability_source_card_index;
			} else if (action.card_ref == DuelNativeCompactKernel::CardRefOpcode::ATTACKER_CARD) {
				target = frame.event_context.attacker_card_index;
			} else {
				finish_action(
					state,
					exile_stack,
					DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED
				);
				return;
			}
			if (target < 0) {
				finish_action(
					state,
					exile_stack,
					DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
				);
				return;
			}
		}
		frame.stage = ActionStage::WAIT_EXILE;
		push_exile_frame(
			target,
			frame.execution_state.current_source_cell,
			frame.action_context.ability_source_card_index,
			self_removal || target == frame.action_context.ability_source_card_index,
			reason,
			frame.event_context,
			*frame.resolution,
			frame.action_context.record_direct_board_changes
		);
		return;
	}
	if (action.opcode == DuelNativeCompactKernel::ActionOpcode::IF) {
		bool conditions_supported = true;
		if (!kernel.action_conditions_match(
			state,
			action.conditions,
			frame.action_context,
			frame.execution_state,
			conditions_supported
		)) {
			finish_action(
				state,
				exile_stack,
				conditions_supported
					? DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
					: DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED
			);
			return;
		}
		frame.stage = ActionStage::WAIT_IF_ACTIONS;
		push_action_frame(
			frame.group,
			action.child_actions,
			frame.event_context,
			frame.action_context,
			frame.execution_state,
			*frame.resolution,
			false
		);
		return;
	}
	if (action.opcode == DuelNativeCompactKernel::ActionOpcode::FOR_EACH_SELECTED_CARD) {
		bool selection_supported = true;
		frame.selected_cards = kernel.snapshot_selected_cards(
			state,
			action.selector,
			frame.action_context,
			selection_supported
		);
		frame.selected_card_index = 0;
		frame.selected_aggregate = DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
		if (!selection_supported) {
			finish_action(state, exile_stack, DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED);
			return;
		}
		frame.stage = ActionStage::NEXT_SELECTED_CARD;
		return;
	}
	const DuelNativeCompactKernel::ActionOutcome outcome = kernel.execute_action(
		state,
		frame.group,
		action,
		frame.event_context,
		frame.action_context,
		frame.execution_state,
		exile_stack,
		*frame.resolution
	);
	finish_action(state, exile_stack, outcome);
}

void ResolutionEngine::step_exile_frame(
	DuelNativeCompactKernel::NativeState &state,
	std::vector<int32_t> &exile_stack
) {
	ExileFrame &frame = resolution_frames.back()->exile;
	if (frame.stage == ExileStage::COMPLETE || frame.resolution == nullptr) {
		complete_exile_frame(exile_stack);
		return;
	}
	DuelNativeCompactKernel::Resolution &resolution = *frame.resolution;
	auto append_event_payload = [&](const DuelNativeCompactKernel::Resolution &child) {
		resolution.events.append_array(child.events);
		resolution.captures.append_array(child.captures);
		resolution.exiles.append_array(child.exiles);
	};

	if (frame.stage == ExileStage::START) {
		if (
			frame.card_index < 0
			|| frame.card_index >= static_cast<int32_t>(state.card_instance_ids.size())
			|| std::find(exile_stack.begin(), exile_stack.end(), frame.card_index)
				!= exile_stack.end()
			|| !kernel.locate_card(
				state,
				frame.card_index,
				frame.initial_zone,
				frame.initial_owner,
				frame.initial_index
			)
			|| (
				frame.initial_zone != 0
				&& frame.initial_zone != 1
				&& frame.initial_zone != 3
			)
		) {
			frame.stage = ExileStage::COMPLETE;
			return;
		}
		if (frame.initial_zone == 0 || frame.initial_zone == 1) {
			exile_stack.push_back(frame.card_index);
			frame.guard_pushed = true;
			DuelNativeCompactKernel::EventContext before_context = frame.parent_context;
			before_context.trigger_cell = frame.initial_zone == 0 ? frame.initial_index : -1;
			before_context.trigger_card_index = frame.card_index;
			before_context.trigger_owner = frame.initial_owner;
			before_context.trigger_zone = frame.initial_zone;
			before_context.trigger_logical_index = frame.initial_index;
			before_context.trigger_was_on_board = frame.initial_zone == 0;
			before_context.exile_reason = frame.exile_reason;
			frame.stage = ExileStage::WAIT_BEFORE;
			push_event_frame(StringName("card_before_exiled"), before_context);
			return;
		}
		frame.stage = ExileStage::MUTATE;
		return;
	}

	if (frame.stage == ExileStage::WAIT_BEFORE) {
		if (frame.guard_pushed) {
			if (!exile_stack.empty() && exile_stack.back() == frame.card_index) {
				exile_stack.pop_back();
			} else {
				const auto found = std::find(exile_stack.begin(), exile_stack.end(), frame.card_index);
				if (found != exile_stack.end()) exile_stack.erase(found);
			}
			frame.guard_pushed = false;
		}
		if (!completed_event_resolution.supported) {
			resolution.reason = completed_event_resolution.reason;
			frame.success = false;
			frame.stage = ExileStage::COMPLETE;
			return;
		}
		append_event_payload(completed_event_resolution);
		frame.stage = ExileStage::MUTATE;
		return;
	}

	if (frame.stage == ExileStage::MUTATE) {
		int32_t zone = -1;
		int32_t current_owner = 0;
		int32_t logical_index = -1;
		if (
			!kernel.locate_card(state, frame.card_index, zone, current_owner, logical_index)
			|| zone != frame.initial_zone
			|| current_owner != frame.initial_owner
			|| logical_index != frame.initial_index
		) {
			frame.stage = ExileStage::COMPLETE;
			return;
		}
		const int32_t previous_hand_size = zone == 1
			? static_cast<int32_t>(state.zones[current_owner - 1].size())
			: -1;
		if (zone == 0) {
			state.board_card_indices[logical_index] = -1;
			state.board_owners[logical_index] = 0;
			if (logical_index < state.board_slot_extras.size()) {
				state.board_slot_extras[logical_index] = Dictionary();
			}
		} else {
			const int32_t zone_index = zone == 1 ? current_owner - 1 : current_owner + 3;
			std::vector<int32_t> &subject_zone = state.zones[zone_index];
			if (
				logical_index < 0
				|| logical_index >= static_cast<int32_t>(subject_zone.size())
				|| subject_zone[logical_index] != frame.card_index
			) {
				frame.stage = ExileStage::COMPLETE;
				return;
			}
			subject_zone.erase(subject_zone.begin() + logical_index);
			if (zone == 1) {
				state.card_runtime_flags[frame.card_index] &= static_cast<uint8_t>(~(1 << 7));
				state.card_hand_slots[frame.card_index] = -1;
			}
		}
		int32_t original_owner = state.card_original_owners[frame.card_index];
		if (original_owner != 1 && original_owner != 2) original_owner = current_owner;
		state.zones[original_owner + 5].push_back(frame.card_index);

		Dictionary event;
		event["type"] = StringName("card_exiled");
		event["source_cell"] = frame.source_cell;
		event["source_instance_id"] = frame.ability_source_card_index >= 0
			? state.card_instance_ids[frame.ability_source_card_index]
			: StringName();
		event["target_cell"] = zone == 0 ? logical_index : -1;
		event["owner_id"] = current_owner;
		event["original_owner"] = original_owner;
		event["instance_id"] = state.card_instance_ids[frame.card_index];
		event["self_removal"] = frame.self_removal;
		event["zone"] = zone == 0
			? StringName("board")
			: (zone == 1 ? StringName("hand") : StringName("discard"));
		event["logical_index"] = logical_index;
		event["exile_reason"] = frame.exile_reason;
		resolution.events.append(event);
		frame.exiled_cell = zone == 0 ? logical_index : -1;

		if (previous_hand_size >= 0) {
			DuelNativeCompactKernel::Resolution hand_change =
				kernel.resolve_difficulty_hand_change(
					state,
					current_owner,
					previous_hand_size,
					static_cast<int32_t>(state.zones[current_owner - 1].size()),
					frame.source_cell,
					exile_stack
				);
			if (!hand_change.supported) {
				resolution.reason = hand_change.reason;
				frame.success = false;
				frame.stage = ExileStage::COMPLETE;
				return;
			}
			kernel.append_resolution(resolution, hand_change);
		}

		DuelNativeCompactKernel::EventContext after_context = frame.parent_context;
		after_context.trigger_cell = zone == 0 ? logical_index : -1;
		after_context.trigger_card_index = frame.card_index;
		after_context.trigger_owner = current_owner;
		after_context.trigger_zone = zone;
		after_context.trigger_logical_index = logical_index;
		after_context.trigger_was_on_board = zone == 0;
		after_context.exile_reason = frame.exile_reason;
		frame.stage = ExileStage::WAIT_AFTER;
		push_event_frame(StringName("card_after_exiled"), after_context);
		return;
	}

	if (!completed_event_resolution.supported) {
		resolution.reason = completed_event_resolution.reason;
		frame.success = false;
		frame.stage = ExileStage::COMPLETE;
		return;
	}
	append_event_payload(completed_event_resolution);
	if (
		kernel.include_presentation_payloads
		&& frame.record_exile_index
		&& resolution.exiles.find(frame.exiled_cell) < 0
	) {
		resolution.exiles.append(frame.exiled_cell);
	}
	frame.stage = ExileStage::COMPLETE;
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
	resolution_frames.clear();
	push_event_frame(event_id, context);
	run_resolution_stack(state, exile_stack);
	return std::move(completed_event_resolution);
}

void ResolutionEngine::step_event_frame(
	DuelNativeCompactKernel::NativeState &state,
	std::vector<int32_t> &exile_stack
) {
	EventFrame &frame = resolution_frames.back()->event;
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
			return;
		}
		frame.stage = EventStage::NEXT_GROUP;
		return;
	}
	if (frame.stage == EventStage::WAIT_ACTIONS) {
		if (completed_action_outcome == DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED) {
			frame.resolution.supported = false;
			if (frame.resolution.reason.is_empty()) {
				frame.resolution.reason = "Relevant event uses an unsupported action";
			}
			frame.stage = EventStage::COMPLETE;
		} else {
			frame.stage = EventStage::NEXT_GROUP;
		}
		return;
	}
	if (frame.stage == EventStage::COMPLETE || frame.group_index >= frame.groups.size()) {
		complete_event_frame();
		return;
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
		) return;
		const DuelNativeCompactKernel::CompiledAbility *ability = kernel.runtime_ability(
			state,
			group.source_card_index,
			current_ability_index
		);
		if (
			ability == nullptr
			|| group.trigger_index < 0
			|| group.trigger_index >= static_cast<int32_t>(ability->triggers.size())
		) return;
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
			return;
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
		frame.stage = EventStage::WAIT_ACTIONS;
		push_action_frame(
			group,
			rule.actions,
			frame.context,
			action_context,
			std::move(execution_state),
			frame.resolution,
			false
		);
		return;
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
