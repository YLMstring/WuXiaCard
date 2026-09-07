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

void ResolutionEngine::push_flip_frame(
	int32_t attacker_cell,
	int32_t attacker_card_index,
	int32_t target_cell,
	int32_t target_card_index,
	int32_t new_owner,
	const DuelNativeCompactKernel::EventContext &context,
	DuelNativeCompactKernel::Resolution &resolution,
	bool record_capture_index,
	int32_t required_attacker_owner
) {
	auto frame = std::make_unique<ResolutionFrame>();
	frame->kind = FrameKind::FLIP;
	frame->flip.attacker_cell = attacker_cell;
	frame->flip.attacker_card_index = attacker_card_index;
	frame->flip.target_cell = target_cell;
	frame->flip.target_card_index = target_card_index;
	frame->flip.new_owner = new_owner;
	frame->flip.context = context;
	frame->flip.resolution = &resolution;
	frame->flip.record_capture_index = record_capture_index;
	frame->flip.required_attacker_owner = required_attacker_owner;
	resolution_frames.push_back(std::move(frame));
}

void ResolutionEngine::push_draw_frame(
	int32_t owner,
	int32_t source_cell,
	int32_t amount,
	const String &weapon_filter,
	const DuelNativeCompactKernel::EventContext &draw_context,
	DuelNativeCompactKernel::Resolution &resolution
) {
	auto frame = std::make_unique<ResolutionFrame>();
	frame->kind = FrameKind::DRAW;
	frame->draw.owner = owner;
	frame->draw.source_cell = source_cell;
	frame->draw.amount = amount;
	frame->draw.weapon_filter = weapon_filter;
	frame->draw.draw_context = draw_context;
	frame->draw.resolution = &resolution;
	resolution_frames.push_back(std::move(frame));
}

void ResolutionEngine::push_discard_frame(
	const DuelNativeCompactKernel::EventGroup &group,
	std::vector<int32_t> locked_cards,
	const DuelNativeCompactKernel::EventContext &event_context,
	const DuelNativeCompactKernel::ActionContext &action_context,
	DuelNativeCompactKernel::ActionExecutionState &execution_state,
	DuelNativeCompactKernel::Resolution &resolution
) {
	auto frame = std::make_unique<ResolutionFrame>();
	frame->kind = FrameKind::DISCARD;
	frame->discard.group = group;
	frame->discard.locked_cards = std::move(locked_cards);
	frame->discard.event_context = event_context;
	frame->discard.action_context = action_context;
	frame->discard.execution_state = &execution_state;
	frame->discard.resolution = &resolution;
	resolution_frames.push_back(std::move(frame));
}

void ResolutionEngine::push_move_frame(
	int32_t source_cell,
	int32_t origin_cell,
	int32_t target_cell,
	int32_t moving_card_index,
	int32_t moving_owner,
	bool resolve_before_event,
	DuelNativeCompactKernel::Resolution &resolution
) {
	auto frame = std::make_unique<ResolutionFrame>();
	frame->kind = FrameKind::MOVE;
	frame->move.source_cell = source_cell;
	frame->move.origin_cell = origin_cell;
	frame->move.target_cell = target_cell;
	frame->move.moving_card_index = moving_card_index;
	frame->move.moving_owner = moving_owner;
	frame->move.resolve_before_event = resolve_before_event;
	frame->move.resolution = &resolution;
	resolution_frames.push_back(std::move(frame));
}

void ResolutionEngine::push_swap_frame(
	int32_t source_card_index,
	int32_t source_owner,
	int32_t source_cell,
	int32_t target_card_index,
	int32_t target_owner,
	int32_t target_cell,
	DuelNativeCompactKernel::Resolution &resolution
) {
	auto frame = std::make_unique<ResolutionFrame>();
	frame->kind = FrameKind::SWAP;
	frame->swap.source_card_index = source_card_index;
	frame->swap.source_owner = source_owner;
	frame->swap.source_cell = source_cell;
	frame->swap.target_card_index = target_card_index;
	frame->swap.target_owner = target_owner;
	frame->swap.target_cell = target_cell;
	frame->swap.resolution = &resolution;
	resolution_frames.push_back(std::move(frame));
}

void ResolutionEngine::push_summon_frame(
	const DuelNativeCompactKernel::SummonRequest &request
) {
	auto frame = std::make_unique<ResolutionFrame>();
	frame->kind = FrameKind::SUMMON;
	frame->summon.request = request;
	resolution_frames.push_back(std::move(frame));
}

void ResolutionEngine::push_attack_frame(
	const DuelNativeCompactKernel::AttackRequest &request
) {
	auto frame = std::make_unique<ResolutionFrame>();
	frame->kind = FrameKind::ATTACK;
	frame->attack.request = request;
	resolution_frames.push_back(std::move(frame));
}

void ResolutionEngine::push_distribute_ki_frame(
	const DuelNativeCompactKernel::EventGroup &group,
	const DuelNativeCompactKernel::CompiledAction &action,
	const DuelNativeCompactKernel::EventContext &event_context,
	const DuelNativeCompactKernel::ActionContext &action_context,
	const DuelNativeCompactKernel::ActionExecutionState &execution_state,
	DuelNativeCompactKernel::Resolution &resolution
) {
	auto frame = std::make_unique<ResolutionFrame>();
	frame->kind = FrameKind::DISTRIBUTE_KI;
	frame->distribute_ki.group = group;
	frame->distribute_ki.action = action;
	frame->distribute_ki.event_context = event_context;
	frame->distribute_ki.action_context = action_context;
	frame->distribute_ki.execution_state = execution_state;
	frame->distribute_ki.resolution = &resolution;
	resolution_frames.push_back(std::move(frame));
}

void ResolutionEngine::push_power_change_frame(
	const DuelNativeCompactKernel::EventGroup &group,
	const DuelNativeCompactKernel::CompiledAction &action,
	const DuelNativeCompactKernel::EventContext &event_context,
	const DuelNativeCompactKernel::ActionContext &action_context,
	int32_t source_cell,
	DuelNativeCompactKernel::Resolution &resolution
) {
	auto frame = std::make_unique<ResolutionFrame>();
	frame->kind = FrameKind::POWER_CHANGE;
	frame->power_change.group = group;
	frame->power_change.action = action;
	frame->power_change.event_context = event_context;
	frame->power_change.action_context = action_context;
	frame->power_change.source_cell = source_cell;
	frame->power_change.resolution = &resolution;
	resolution_frames.push_back(std::move(frame));
}

void ResolutionEngine::push_transfer_resource_frame(
	const DuelNativeCompactKernel::EventGroup &group,
	const DuelNativeCompactKernel::CompiledAction &action,
	const DuelNativeCompactKernel::EventContext &event_context,
	const DuelNativeCompactKernel::ActionContext &action_context,
	int32_t source_cell,
	DuelNativeCompactKernel::Resolution &resolution
) {
	auto frame = std::make_unique<ResolutionFrame>();
	frame->kind = FrameKind::TRANSFER_RESOURCE;
	frame->transfer_resource.group = group;
	frame->transfer_resource.action = action;
	frame->transfer_resource.event_context = event_context;
	frame->transfer_resource.action_context = action_context;
	frame->transfer_resource.source_cell = source_cell;
	frame->transfer_resource.resolution = &resolution;
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
		} else if (resolution_frames.back()->kind == FrameKind::EXILE) {
			step_exile_frame(state, exile_stack);
		} else if (resolution_frames.back()->kind == FrameKind::FLIP) {
			step_flip_frame(state, exile_stack);
		} else if (resolution_frames.back()->kind == FrameKind::DRAW) {
			step_draw_frame(state, exile_stack);
		} else if (resolution_frames.back()->kind == FrameKind::DISCARD) {
			step_discard_frame(state, exile_stack);
		} else if (resolution_frames.back()->kind == FrameKind::MOVE) {
			step_move_frame(state, exile_stack);
		} else if (resolution_frames.back()->kind == FrameKind::SWAP) {
			step_swap_frame(state, exile_stack);
		} else if (resolution_frames.back()->kind == FrameKind::SUMMON) {
			step_summon_frame(state, exile_stack);
		} else if (resolution_frames.back()->kind == FrameKind::ATTACK) {
			step_attack_frame(state, exile_stack);
		} else if (resolution_frames.back()->kind == FrameKind::DISTRIBUTE_KI) {
			step_distribute_ki_frame(state, exile_stack);
		} else if (resolution_frames.back()->kind == FrameKind::POWER_CHANGE) {
			step_power_change_frame(state, exile_stack);
		} else {
			step_transfer_resource_frame(state, exile_stack);
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

void ResolutionEngine::complete_flip_frame() {
	completed_flip_success = resolution_frames.back()->flip.success;
	resolution_frames.pop_back();
}

void ResolutionEngine::complete_draw_frame() {
	completed_draw_success = resolution_frames.back()->draw.success;
	resolution_frames.pop_back();
}

void ResolutionEngine::complete_discard_frame() {
	completed_discard_outcome = resolution_frames.back()->discard.outcome;
	resolution_frames.pop_back();
}

void ResolutionEngine::complete_move_frame() {
	completed_move_outcome = resolution_frames.back()->move.outcome;
	resolution_frames.pop_back();
}

void ResolutionEngine::complete_swap_frame() {
	completed_swap_outcome = resolution_frames.back()->swap.outcome;
	resolution_frames.pop_back();
}

void ResolutionEngine::complete_summon_frame() {
	completed_summon_resolution = std::move(resolution_frames.back()->summon.resolution);
	resolution_frames.pop_back();
}

void ResolutionEngine::complete_attack_frame() {
	completed_attack_resolution = std::move(resolution_frames.back()->attack.resolution);
	resolution_frames.pop_back();
}

void ResolutionEngine::complete_distribute_ki_frame() {
	completed_distribute_ki_outcome = resolution_frames.back()->distribute_ki.outcome;
	resolution_frames.pop_back();
}

void ResolutionEngine::complete_power_change_frame() {
	completed_power_change_outcome = resolution_frames.back()->power_change.outcome;
	resolution_frames.pop_back();
}

void ResolutionEngine::complete_transfer_resource_frame() {
	completed_transfer_resource_outcome =
		resolution_frames.back()->transfer_resource.outcome;
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
	if (frame.stage == ActionStage::WAIT_FLIP) {
		finish_action(
			state,
			exile_stack,
			completed_flip_success
				? DuelNativeCompactKernel::ActionOutcome::APPLIED
				: DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED
		);
		return;
	}
	if (frame.stage == ActionStage::WAIT_POWER_EXILE) {
		finish_action(
			state,
			exile_stack,
			completed_exile_success
				? DuelNativeCompactKernel::ActionOutcome::APPLIED
				: DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED
		);
		return;
	}
	if (frame.stage == ActionStage::WAIT_DRAW) {
		finish_action(
			state,
			exile_stack,
			completed_draw_success
				? DuelNativeCompactKernel::ActionOutcome::APPLIED
				: DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED
		);
		return;
	}
	if (frame.stage == ActionStage::WAIT_DISCARD) {
		finish_action(state, exile_stack, completed_discard_outcome);
		return;
	}
	if (frame.stage == ActionStage::WAIT_MOVE) {
		if (completed_move_outcome == DuelNativeCompactKernel::ActionOutcome::APPLIED) {
			frame.execution_state.current_source_cell = kernel.find_board_card(
				state,
				frame.group.source_card_index,
				frame.child_target_cell
			);
		}
		finish_action(state, exile_stack, completed_move_outcome);
		return;
	}
	if (frame.stage == ActionStage::WAIT_SWAP) {
		if (
			completed_swap_outcome == DuelNativeCompactKernel::ActionOutcome::APPLIED
			&& frame.update_source_after_swap
		) {
			frame.execution_state.current_source_cell = kernel.find_board_card(
				state,
				frame.group.source_card_index,
				frame.child_target_cell
			);
		}
		finish_action(state, exile_stack, completed_swap_outcome);
		return;
	}
	if (frame.stage == ActionStage::WAIT_RETURN_EXILE) {
		DuelNativeCompactKernel::ActionOutcome outcome =
			DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
		if (completed_exile_success) {
			outcome = frame.resolution->events.size() > frame.return_previous_event_count
				? DuelNativeCompactKernel::ActionOutcome::APPLIED
				: DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
		}
		finish_action(state, exile_stack, outcome);
		return;
	}
	if (frame.stage == ActionStage::WAIT_SUMMON) {
		if (!completed_summon_resolution.supported) {
			frame.resolution->reason = completed_summon_resolution.reason;
			finish_action(
				state,
				exile_stack,
				DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED
			);
			return;
		}
		kernel.append_resolution(*frame.resolution, completed_summon_resolution);
		finish_action(
			state,
			exile_stack,
			DuelNativeCompactKernel::ActionOutcome::APPLIED
		);
		return;
	}
	if (frame.stage == ActionStage::WAIT_ATTACK) {
		if (!completed_attack_resolution.supported) {
			frame.resolution->reason = completed_attack_resolution.reason;
			finish_action(
				state,
				exile_stack,
				DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED
			);
			return;
		}
		const bool applied = kernel.resolution_has_output(completed_attack_resolution);
		kernel.append_resolution(*frame.resolution, completed_attack_resolution);
		finish_action(
			state,
			exile_stack,
			applied
				? DuelNativeCompactKernel::ActionOutcome::APPLIED
				: DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
		);
		return;
	}
	if (frame.stage == ActionStage::WAIT_DISTRIBUTE_KI) {
		finish_action(state, exile_stack, completed_distribute_ki_outcome);
		return;
	}
	if (frame.stage == ActionStage::WAIT_POWER_CHANGE) {
		finish_action(state, exile_stack, completed_power_change_outcome);
		return;
	}
	if (frame.stage == ActionStage::WAIT_TRANSFER_RESOURCE) {
		finish_action(state, exile_stack, completed_transfer_resource_outcome);
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
		action.opcode == DuelNativeCompactKernel::ActionOpcode::SUMMON_CARD
		|| action.opcode == DuelNativeCompactKernel::ActionOpcode::RESUMMON_CARD_IN_PLACE
	) {
		DuelNativeCompactKernel::SummonRequest request;
		const DuelNativeCompactKernel::ActionOutcome outcome =
			action.opcode == DuelNativeCompactKernel::ActionOpcode::SUMMON_CARD
			? kernel.prepare_summon_card(
				state,
				frame.group,
				action,
				frame.event_context,
				frame.action_context,
				frame.execution_state,
				exile_stack,
				*frame.resolution,
				request
			)
			: kernel.prepare_resummon_card_in_place(
				state,
				frame.group,
				action,
				frame.event_context,
				frame.action_context,
				frame.execution_state,
				exile_stack,
				*frame.resolution,
				request
			);
		if (outcome != DuelNativeCompactKernel::ActionOutcome::APPLIED) {
			finish_action(state, exile_stack, outcome);
			return;
		}
		frame.stage = ActionStage::WAIT_SUMMON;
		push_summon_frame(request);
		return;
	}
	if (
		action.opcode == DuelNativeCompactKernel::ActionOpcode::ATTACK_TRIGGER_CARD
		|| action.opcode == DuelNativeCompactKernel::ActionOpcode::STANDARD_ATTACK_WITH_SELF
		|| action.opcode == DuelNativeCompactKernel::ActionOpcode::STANDARD_ATTACK_WITH_CARD
	) {
		DuelNativeCompactKernel::AttackRequest request;
		const DuelNativeCompactKernel::ActionOutcome outcome = kernel.prepare_attack_action(
			state,
			action,
			frame.event_context,
			frame.action_context,
			frame.execution_state,
			request
		);
		if (outcome != DuelNativeCompactKernel::ActionOutcome::APPLIED) {
			finish_action(state, exile_stack, outcome);
			return;
		}
		frame.stage = ActionStage::WAIT_ATTACK;
		push_attack_frame(request);
		return;
	}
	if (action.opcode == DuelNativeCompactKernel::ActionOpcode::DISTRIBUTE_KI) {
		frame.stage = ActionStage::WAIT_DISTRIBUTE_KI;
		push_distribute_ki_frame(
			frame.group,
			action,
			frame.event_context,
			frame.action_context,
			frame.execution_state,
			*frame.resolution
		);
		return;
	}
	if (action.opcode == DuelNativeCompactKernel::ActionOpcode::CHANGE_POWERS) {
		frame.stage = ActionStage::WAIT_POWER_CHANGE;
		push_power_change_frame(
			frame.group,
			action,
			frame.event_context,
			frame.action_context,
			frame.execution_state.current_source_cell,
			*frame.resolution
		);
		return;
	}
	if (action.opcode == DuelNativeCompactKernel::ActionOpcode::TRANSFER_CARD_RESOURCE) {
		frame.stage = ActionStage::WAIT_TRANSFER_RESOURCE;
		push_transfer_resource_frame(
			frame.group,
			action,
			frame.event_context,
			frame.action_context,
			frame.execution_state.current_source_cell,
			*frame.resolution
		);
		return;
	}
	if (action.opcode == DuelNativeCompactKernel::ActionOpcode::DRAW_CARDS) {
		DuelNativeCompactKernel::EventContext draw_context = frame.event_context;
		draw_context.ability_source_cell = frame.action_context.ability_source_cell;
		draw_context.ability_source_zone = frame.action_context.ability_source_zone;
		draw_context.ability_source_logical_index =
			frame.action_context.ability_source_logical_index;
		draw_context.ability_source_card_index = frame.action_context.ability_source_card_index;
		draw_context.ability_source_owner = frame.action_context.ability_source_owner;
		frame.stage = ActionStage::WAIT_DRAW;
		push_draw_frame(
			frame.action_context.action_subject_owner,
			frame.execution_state.current_source_cell,
			action.amount,
			action.weapon,
			draw_context,
			*frame.resolution
		);
		return;
	}
	if (action.opcode == DuelNativeCompactKernel::ActionOpcode::RETURN_CARD_TO_HAND) {
		int32_t target = -1;
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
		if (target < 0 || target >= static_cast<int32_t>(state.card_instance_ids.size())) {
			finish_action(
				state,
				exile_stack,
				DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
			);
			return;
		}
		int32_t target_zone = -1;
		int32_t target_owner = 0;
		int32_t target_index = -1;
		if (
			!kernel.locate_card(state, target, target_zone, target_owner, target_index)
			|| (action.preserve_instance ? target_zone != 3 : target_zone != 0)
		) {
			finish_action(
				state,
				exile_stack,
				DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
			);
			return;
		}
		int32_t recipient_owner = 0;
		if (
			action.recipient_owner
			== DuelNativeCompactKernel::RelativeOwnerOpcode::CARD_CURRENT
		) {
			recipient_owner = target_owner;
		} else if (
			action.recipient_owner
			== DuelNativeCompactKernel::RelativeOwnerOpcode::CARD_ORIGINAL
		) {
			recipient_owner = state.card_original_owners[target];
		} else if (
			action.recipient_owner
			== DuelNativeCompactKernel::RelativeOwnerOpcode::ABILITY_SOURCE
		) {
			recipient_owner = frame.action_context.ability_source_owner;
		} else if (
			action.recipient_owner
			== DuelNativeCompactKernel::RelativeOwnerOpcode::OPPONENT_OF_ABILITY_SOURCE
		) {
			recipient_owner = other_owner(frame.action_context.ability_source_owner);
		} else {
			finish_action(
				state,
				exile_stack,
				DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED
			);
			return;
		}
		if (recipient_owner != 1 && recipient_owner != 2) {
			finish_action(
				state,
				exile_stack,
				DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
			);
			return;
		}
		if (state.zones[recipient_owner - 1].size() >= 5) {
			const int32_t current_source = kernel.find_board_card(
				state,
				frame.action_context.ability_source_card_index,
				frame.action_context.ability_source_cell
			);
			const int32_t source_cell = current_source >= 0
				? current_source
				: frame.action_context.ability_source_cell;
			frame.return_previous_event_count = frame.resolution->events.size();
			frame.stage = ActionStage::WAIT_RETURN_EXILE;
			push_exile_frame(
				target,
				source_cell,
				frame.action_context.ability_source_card_index,
				target == frame.action_context.ability_source_card_index,
				StringName("return_to_full_hand"),
				frame.event_context,
				*frame.resolution,
				frame.action_context.record_direct_board_changes
			);
			return;
		}
		const DuelNativeCompactKernel::ActionOutcome outcome = kernel.return_card_to_hand(
			state,
			frame.group,
			action,
			frame.event_context,
			frame.action_context,
			exile_stack,
			*frame.resolution
		);
		finish_action(state, exile_stack, outcome);
		return;
	}
	if (
		action.opcode == DuelNativeCompactKernel::ActionOpcode::DISCARD_CARD
		|| action.opcode == DuelNativeCompactKernel::ActionOpcode::DISCARD_CARDS
	) {
		frame.execution_state.last_discard_batch_size = 0;
		std::vector<int32_t> locked_cards;
		if (action.opcode == DuelNativeCompactKernel::ActionOpcode::DISCARD_CARD) {
			int32_t target = -1;
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
			if (target >= 0) locked_cards.push_back(target);
		} else {
			bool selection_supported = true;
			locked_cards = kernel.snapshot_selected_cards(
				state,
				action.selector,
				frame.action_context,
				selection_supported
			);
			if (!selection_supported) {
				finish_action(
					state,
					exile_stack,
					DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED
				);
				return;
			}
		}
		frame.stage = ActionStage::WAIT_DISCARD;
		push_discard_frame(
			frame.group,
			std::move(locked_cards),
			frame.event_context,
			frame.action_context,
			frame.execution_state,
			*frame.resolution
		);
		return;
	}
	if (
		action.opcode == DuelNativeCompactKernel::ActionOpcode::MOVE_SELF_TO_TARGET
		|| action.opcode
			== DuelNativeCompactKernel::ActionOpcode::MOVE_SELF_TO_FIRST_ADJACENT_EMPTY
		|| action.opcode
			== DuelNativeCompactKernel::ActionOpcode::MOVE_SELF_TO_FIRST_EMPTY_BETWEEN_ENEMY
	) {
		const int32_t moving_card = frame.action_context.action_subject_card_index;
		const int32_t moving_owner = frame.action_context.action_subject_owner;
		int32_t source_zone = -1;
		int32_t source_owner = 0;
		int32_t current_cell = -1;
		if (
			moving_card < 0
			|| !kernel.locate_card(
				state,
				moving_card,
				source_zone,
				source_owner,
				current_cell
			)
			|| source_zone != 0
			|| source_owner != moving_owner
		) {
			finish_action(
				state,
				exile_stack,
				DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
			);
			return;
		}
		int32_t target_cell = -1;
		if (action.opcode == DuelNativeCompactKernel::ActionOpcode::MOVE_SELF_TO_TARGET) {
			if (frame.action_context.activation_target_kind != StringName("board_cell")) {
				finish_action(
					state,
					exile_stack,
					DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
				);
				return;
			}
			target_cell = frame.action_context.activation_target_index;
			if (
				current_cell != frame.execution_state.current_source_cell
				|| target_cell < 0
				|| target_cell >= static_cast<int32_t>(state.board_card_indices.size())
				|| state.board_card_indices[target_cell] >= 0
			) target_cell = -1;
			bool adjacent = false;
			for (int32_t direction = 0; target_cell >= 0 && direction < 4; ++direction) {
				if (neighbor_index(current_cell, direction) == target_cell) {
					adjacent = true;
					break;
				}
			}
			if (!adjacent) target_cell = -1;
		} else if (
			action.opcode
			== DuelNativeCompactKernel::ActionOpcode::MOVE_SELF_TO_FIRST_ADJACENT_EMPTY
		) {
			for (
				int32_t candidate = 0;
				candidate < static_cast<int32_t>(state.board_card_indices.size());
				++candidate
			) {
				if (state.board_card_indices[candidate] >= 0) continue;
				for (int32_t direction = 0; direction < 4; ++direction) {
					if (neighbor_index(current_cell, direction) == candidate) {
						target_cell = candidate;
						break;
					}
				}
				if (target_cell >= 0) break;
			}
		} else {
			for (
				int32_t middle_cell = 0;
				middle_cell < static_cast<int32_t>(state.board_card_indices.size());
				++middle_cell
			) {
				if (state.board_card_indices[middle_cell] >= 0) continue;
				for (int32_t direction = 0; direction < 4; ++direction) {
					if (neighbor_index(current_cell, direction) != middle_cell) continue;
					const int32_t far_cell = neighbor_index(middle_cell, direction);
					if (
						far_cell < 0
						|| state.board_card_indices[far_cell] < 0
						|| state.board_owners[far_cell] == moving_owner
					) continue;
					target_cell = middle_cell;
					break;
				}
				if (target_cell >= 0) break;
			}
		}
		if (target_cell < 0) {
			finish_action(
				state,
				exile_stack,
				DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
			);
			return;
		}
		frame.child_target_cell = target_cell;
		frame.stage = ActionStage::WAIT_MOVE;
		push_move_frame(
			current_cell,
			current_cell,
			target_cell,
			moving_card,
			moving_owner,
			true,
			*frame.resolution
		);
		return;
	}
	if (
		action.opcode
			== DuelNativeCompactKernel::ActionOpcode::SELF_SWAPPED_WITH_ABILITY_SOURCE
		|| action.opcode
			== DuelNativeCompactKernel::ActionOpcode::SWAP_SELF_WITH_TRIGGER_CARD
		|| action.opcode == DuelNativeCompactKernel::ActionOpcode::SWAP_SELF_WITH_TARGET
	) {
		const int32_t source_card = frame.group.source_card_index;
		const int32_t source_owner = frame.action_context.ability_source_owner;
		int32_t target_card = frame.action_context.action_subject_card_index;
		int32_t target_owner = frame.action_context.action_subject_owner;
		int32_t target_cell_hint = frame.action_context.action_subject_logical_index;
		frame.update_source_after_swap = false;
		if (
			action.opcode
			== DuelNativeCompactKernel::ActionOpcode::SWAP_SELF_WITH_TRIGGER_CARD
		) {
			if (frame.event_context.trigger_card_index < 0) {
				finish_action(
					state,
					exile_stack,
					DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
				);
				return;
			}
			target_card = frame.event_context.trigger_card_index;
			target_owner = frame.event_context.trigger_owner;
			target_cell_hint = frame.event_context.trigger_cell;
		} else if (
			action.opcode == DuelNativeCompactKernel::ActionOpcode::SWAP_SELF_WITH_TARGET
		) {
			if (frame.action_context.activation_target_kind != StringName("board_cell")) {
				finish_action(
					state,
					exile_stack,
					DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
				);
				return;
			}
			target_card = frame.action_context.selected_card_index;
			target_owner = frame.action_context.selected_card_owner;
			target_cell_hint = frame.action_context.activation_target_index;
			if (
				target_cell_hint < 0
				|| target_cell_hint >= static_cast<int32_t>(state.board_card_indices.size())
				|| state.board_card_indices[target_cell_hint] != target_card
				|| state.board_owners[target_cell_hint] != target_owner
			) {
				finish_action(
					state,
					exile_stack,
					DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
				);
				return;
			}
			frame.update_source_after_swap = true;
		}
		const int32_t source_cell = kernel.find_board_card(
			state,
			source_card,
			frame.group.source_cell
		);
		const int32_t target_cell = kernel.find_board_card(
			state,
			target_card,
			target_cell_hint
		);
		if (
			source_card < 0
			|| target_card < 0
			|| source_card == target_card
			|| source_cell < 0
			|| target_cell < 0
			|| state.board_owners[source_cell] != source_owner
			|| state.board_owners[target_cell] != target_owner
		) {
			finish_action(
				state,
				exile_stack,
				DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
			);
			return;
		}
		frame.child_target_cell = target_cell;
		frame.stage = ActionStage::WAIT_SWAP;
		push_swap_frame(
			source_card,
			source_owner,
			source_cell,
			target_card,
			target_owner,
			target_cell,
			*frame.resolution
		);
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
	if (action.opcode == DuelNativeCompactKernel::ActionOpcode::CHANGE_POWERS) {
		int32_t target = -1;
		int32_t expected_owner = 0;
		if (action.card_ref == DuelNativeCompactKernel::CardRefOpcode::SELECTED_CARD) {
			target = frame.action_context.selected_card_index;
			expected_owner = frame.action_context.selected_card_owner != 0
				? frame.action_context.selected_card_owner
				: frame.action_context.action_subject_owner;
		} else if (action.card_ref == DuelNativeCompactKernel::CardRefOpcode::ABILITY_SOURCE) {
			target = frame.action_context.ability_source_card_index;
			expected_owner = frame.action_context.ability_source_owner;
		} else if (action.card_ref == DuelNativeCompactKernel::CardRefOpcode::TRIGGER_CARD) {
			target = frame.event_context.trigger_card_index;
			expected_owner = frame.event_context.trigger_owner;
		} else if (action.card_ref == DuelNativeCompactKernel::CardRefOpcode::ATTACKER_CARD) {
			target = frame.event_context.attacker_card_index;
			expected_owner = frame.event_context.attacker_owner;
		} else {
			finish_action(
				state,
				exile_stack,
				DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED
			);
			return;
		}
		int32_t zone = -1;
		int32_t owner = 0;
		int32_t logical_index = -1;
		if (
			target < 0
			|| !kernel.locate_card(state, target, zone, owner, logical_index)
			|| zone == 2
			|| (expected_owner != 0 && owner != expected_owner)
			|| !kernel.can_change_powers(state, target)
		) {
			finish_action(
				state,
				exile_stack,
				DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
			);
			return;
		}
		int32_t amount = action.amount;
		if (action.amount_is_hand_count) {
			int32_t count_owner = 0;
			if (action.amount_owner == DuelNativeCompactKernel::RelativeOwnerOpcode::CARD_CURRENT) {
				count_owner = owner;
			} else if (
				action.amount_owner
				== DuelNativeCompactKernel::RelativeOwnerOpcode::ABILITY_SOURCE
			) {
				int32_t source_zone = -1;
				int32_t source_index = -1;
				if (
					!kernel.locate_card(
						state,
						frame.action_context.ability_source_card_index,
						source_zone,
						count_owner,
						source_index
					)
					|| source_zone == 2
				) {
					finish_action(
						state,
						exile_stack,
						DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
					);
					return;
				}
			} else {
				finish_action(
					state,
					exile_stack,
					DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED
				);
				return;
			}
			amount = static_cast<int32_t>(state.zones[count_owner - 1].size());
		}
		if (amount == 0) {
			finish_action(
				state,
				exile_stack,
				action.amount_is_hand_count
					? DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
					: DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED
			);
			return;
		}
		Array previous_powers;
		Array resulting_powers;
		bool all_zero = true;
		for (int32_t direction = 0; direction < 4; ++direction) {
			const int32_t previous = state.card_powers[target * 4 + direction];
			const int32_t resulting = std::max(0, previous + amount);
			previous_powers.append(previous);
			resulting_powers.append(resulting);
			state.card_powers[target * 4 + direction] = resulting;
			all_zero = all_zero && resulting == 0;
		}
		Dictionary event;
		event["type"] = StringName("powers_changed");
		event["source_cell"] = frame.execution_state.current_source_cell;
		event["target_cell"] = zone == 0 ? logical_index : -1;
		event["owner_id"] = owner;
		event["instance_id"] = state.card_instance_ids[target];
		event["ability_source_instance_id"] =
			state.card_instance_ids[frame.group.source_card_index];
		event["previous_powers"] = previous_powers;
		event["powers"] = resulting_powers;
		event["amount"] = amount;
		event["change_reason"] = StringName("change_powers");
		event["zone"] = zone == 0
			? StringName("board")
			: (zone == 1
				? StringName("hand")
				: (zone == 3 ? StringName("discard") : StringName("removed")));
		event["logical_index"] = logical_index;
		frame.resolution->events.append(event);
		if (amount < 0 && all_zero) {
			frame.stage = ActionStage::WAIT_POWER_EXILE;
			push_exile_frame(
				target,
				frame.execution_state.current_source_cell,
				frame.group.source_card_index,
				target == frame.group.source_card_index,
				StringName("power_reached_zero"),
				frame.event_context,
				*frame.resolution,
				frame.action_context.record_direct_board_changes
			);
			return;
		}
		finish_action(state, exile_stack, DuelNativeCompactKernel::ActionOutcome::APPLIED);
		return;
	}
	if (action.opcode == DuelNativeCompactKernel::ActionOpcode::FLIP_SELF) {
		const int32_t target = frame.action_context.action_subject_card_index;
		const int32_t target_cell = kernel.find_board_card(
			state,
			target,
			frame.action_context.action_subject_logical_index
		);
		if (
			target_cell < 0
			|| state.board_owners[target_cell] != frame.action_context.action_subject_owner
		) {
			finish_action(
				state,
				exile_stack,
				DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
			);
			return;
		}
		const int32_t new_owner = kernel.resolve_relative_owner(
			state,
			action.new_owner,
			frame.action_context,
			target
		);
		if (new_owner != 1 && new_owner != 2) {
			finish_action(
				state,
				exile_stack,
				DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED
			);
			return;
		}
		if (new_owner == state.board_owners[target_cell]) {
			finish_action(
				state,
				exile_stack,
				DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
			);
			return;
		}
		DuelNativeCompactKernel::EventContext flip_context;
		flip_context.trigger_cell = target_cell;
		flip_context.trigger_card_index = target;
		flip_context.trigger_owner = state.board_owners[target_cell];
		flip_context.trigger_was_on_board = true;
		flip_context.new_owner = new_owner;
		flip_context.flip_reason = StringName("ability_non_attack_flip");
		frame.stage = ActionStage::WAIT_FLIP;
		push_flip_frame(
			-1,
			-1,
			target_cell,
			target,
			new_owner,
			flip_context,
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

void ResolutionEngine::step_flip_frame(
	DuelNativeCompactKernel::NativeState &state,
	std::vector<int32_t> &exile_stack
) {
	(void)exile_stack;
	FlipFrame &frame = resolution_frames.back()->flip;
	if (frame.stage == FlipStage::COMPLETE || frame.resolution == nullptr) {
		complete_flip_frame();
		return;
	}
	DuelNativeCompactKernel::Resolution &resolution = *frame.resolution;
	auto append_event_payload = [&](const DuelNativeCompactKernel::Resolution &child) {
		resolution.events.append_array(child.events);
		resolution.captures.append_array(child.captures);
		resolution.exiles.append_array(child.exiles);
	};

	if (frame.stage == FlipStage::START) {
		const int32_t current_target_cell = kernel.find_board_card(
			state,
			frame.target_card_index,
			frame.target_cell
		);
		if (
			current_target_cell < 0
			|| state.board_owners[current_target_cell] == frame.new_owner
		) {
			frame.stage = FlipStage::COMPLETE;
			return;
		}
		frame.target_cell = current_target_cell;
		frame.stage = FlipStage::WAIT_BEFORE;
		push_event_frame(StringName("card_before_flipped"), frame.context);
		return;
	}

	if (frame.stage == FlipStage::WAIT_PREVENTED) {
		if (!completed_event_resolution.supported) {
			resolution.reason = completed_event_resolution.reason;
			frame.success = false;
		} else {
			append_event_payload(completed_event_resolution);
		}
		frame.stage = FlipStage::COMPLETE;
		return;
	}

	if (frame.stage == FlipStage::WAIT_AFTER) {
		if (!completed_event_resolution.supported) {
			resolution.reason = completed_event_resolution.reason;
			frame.success = false;
			frame.stage = FlipStage::COMPLETE;
			return;
		}
		append_event_payload(completed_event_resolution);
		const int32_t post_cell = kernel.find_board_card(
			state,
			frame.target_card_index,
			frame.target_cell
		);
		if (post_cell >= 0) {
			for (const uint64_t ability_handle : frame.remove_after_after_flip) {
				kernel.remove_ability_with_event(
					state,
					frame.target_card_index,
					ability_handle,
					frame.attacker_cell,
					frame.attacker_card_index,
					post_cell,
					frame.new_owner,
					resolution.events
				);
			}
		}
		frame.stage = FlipStage::COMPLETE;
		return;
	}

	if (!completed_event_resolution.supported) {
		resolution.reason = completed_event_resolution.reason;
		frame.success = false;
		frame.stage = FlipStage::COMPLETE;
		return;
	}
	const bool flip_prevented = completed_event_resolution.flip_prevented;
	append_event_payload(completed_event_resolution);
	if (flip_prevented) {
		Dictionary prevented;
		prevented["type"] = StringName("card_flip_prevented");
		prevented["source_cell"] = frame.attacker_cell;
		prevented["target_cell"] = frame.target_cell;
		prevented["owner_id"] = frame.context.trigger_owner;
		prevented["new_owner_id"] = frame.new_owner;
		prevented["instance_id"] = state.card_instance_ids[frame.target_card_index];
		resolution.events.append(prevented);
		frame.stage = FlipStage::WAIT_PREVENTED;
		push_event_frame(StringName("card_flip_prevented"), frame.context);
		return;
	}
	if (frame.required_attacker_owner != 0) {
		const int32_t current_attacker_cell = kernel.find_board_card(
			state,
			frame.attacker_card_index,
			frame.attacker_cell
		);
		if (
			current_attacker_cell < 0
			|| state.board_owners[current_attacker_cell] != frame.required_attacker_owner
		) {
			frame.stage = FlipStage::COMPLETE;
			return;
		}
		frame.attacker_cell = current_attacker_cell;
	}

	const int32_t current_target_cell = kernel.find_board_card(
		state,
		frame.target_card_index,
		frame.target_cell
	);
	if (
		current_target_cell < 0
		|| state.board_owners[current_target_cell] == frame.new_owner
	) {
		frame.stage = FlipStage::COMPLETE;
		return;
	}
	frame.target_cell = current_target_cell;
	for (
		size_t ability_index = 0;
		ability_index < state.card_runtime_abilities[frame.target_card_index].size();
		++ability_index
	) {
		const DuelNativeCompactKernel::CompiledAbility *ability = kernel.runtime_ability(
			state,
			frame.target_card_index,
			static_cast<int32_t>(ability_index)
		);
		if (ability == nullptr || ability->retained_on_flip) continue;
		const uint64_t handle =
			state.card_runtime_abilities[frame.target_card_index][ability_index].handle;
		if (ability->isolated_self_after_flip) {
			frame.remove_after_after_flip.push_back(handle);
		} else {
			frame.remove_before_after_flip.push_back(handle);
		}
	}
	state.board_owners[current_target_cell] = static_cast<uint8_t>(frame.new_owner);
	Dictionary flipped;
	flipped["type"] = StringName("card_flipped");
	flipped["source_cell"] = frame.attacker_cell;
	flipped["target_cell"] = current_target_cell;
	flipped["owner_id"] = frame.new_owner;
	flipped["instance_id"] = state.card_instance_ids[frame.target_card_index];
	resolution.events.append(flipped);
	kernel.clear_runtime_suppression(state, frame.target_card_index);
	for (const uint64_t ability_handle : frame.remove_before_after_flip) {
		kernel.remove_ability_with_event(
			state,
			frame.target_card_index,
			ability_handle,
			frame.attacker_cell,
			frame.attacker_card_index,
			current_target_cell,
			frame.new_owner,
			resolution.events
		);
	}
	if (kernel.include_presentation_payloads && frame.record_capture_index) {
		resolution.captures.append(current_target_cell);
	}
	DuelNativeCompactKernel::EventContext after_context = frame.context;
	after_context.trigger_cell = current_target_cell;
	after_context.trigger_card_index = frame.target_card_index;
	after_context.trigger_previous_owner = frame.context.trigger_owner;
	after_context.trigger_owner = frame.context.trigger_owner;
	after_context.trigger_zone = 0;
	after_context.trigger_logical_index = current_target_cell;
	frame.stage = FlipStage::WAIT_AFTER;
	push_event_frame(StringName("card_after_flipped"), after_context);
}

void ResolutionEngine::step_draw_frame(
	DuelNativeCompactKernel::NativeState &state,
	std::vector<int32_t> &exile_stack
) {
	DrawFrame &frame = resolution_frames.back()->draw;
	if (frame.stage == DrawStage::COMPLETE || frame.resolution == nullptr) {
		complete_draw_frame();
		return;
	}
	DuelNativeCompactKernel::Resolution &resolution = *frame.resolution;
	if (frame.stage == DrawStage::START) {
		if (frame.owner != 1 && frame.owner != 2) {
			frame.stage = DrawStage::COMPLETE;
			return;
		}
		const Dictionary audiences_by_owner = state.side_payload.get(
			"future_draw_reveal_audiences",
			Dictionary()
		);
		const Variant audiences_value = audiences_by_owner.get(frame.owner, Array());
		if (audiences_value.get_type() != Variant::ARRAY) {
			resolution.reason = "Future-draw reveal audiences are not an Array";
			frame.success = false;
			frame.stage = DrawStage::COMPLETE;
			return;
		}
		frame.reveal_audiences = audiences_value;
		frame.stage = DrawStage::NEXT_CARD;
		return;
	}
	if (frame.stage == DrawStage::WAIT_AFTER_DRAWN) {
		if (!completed_event_resolution.supported) {
			resolution.reason = completed_event_resolution.reason;
			frame.success = false;
			frame.stage = DrawStage::COMPLETE;
			return;
		}
		kernel.append_resolution(resolution, completed_event_resolution);
		frame.stage = DrawStage::NEXT_CARD;
		return;
	}

	std::vector<int32_t> &hand = state.zones[frame.owner - 1];
	std::vector<int32_t> &deck = state.zones[frame.owner + 1];
	if (frame.draw_index >= frame.amount || hand.size() >= 5) {
		frame.stage = DrawStage::COMPLETE;
		return;
	}
	int32_t card_index = -1;
	if (!frame.weapon_filter.is_empty()) {
		const auto matching = std::find_if(
			deck.begin(),
			deck.end(),
			[&](const int32_t candidate) {
				if (
					candidate < 0
					|| candidate >= static_cast<int32_t>(state.card_template_indices.size())
				) return false;
				const int32_t template_index = state.card_template_indices[candidate];
				if (
					template_index < 0
					|| template_index >= state.card_template_pool.size()
				) return false;
				const Variant template_value = state.card_template_pool[template_index];
				if (template_value.get_type() != Variant::DICTIONARY) return false;
				return String(Dictionary(template_value).get("weapon", String()))
					== frame.weapon_filter;
			}
		);
		if (matching == deck.end()) {
			frame.stage = DrawStage::COMPLETE;
			return;
		}
		card_index = *matching;
		deck.erase(matching);
	} else if (!deck.empty()) {
		card_index = deck.front();
		deck.erase(deck.begin());
	} else {
		if (
			state.empty_deck_draw_prototype_index < 0
			|| state.empty_deck_draw_prototype_index
				>= static_cast<int32_t>(state.fresh_card_prototypes.size())
		) {
			resolution.reason = "Draw has no generated empty-deck fallback prototype";
			frame.success = false;
			frame.stage = DrawStage::COMPLETE;
			return;
		}
		const StringName fallback_id = state.fresh_card_prototypes[
			state.empty_deck_draw_prototype_index
		].card_id;
		String append_reason;
		card_index = kernel.append_fresh_board_card(
			state,
			fallback_id,
			kernel.make_generated_instance_id(state, fallback_id),
			frame.owner,
			append_reason
		);
		if (card_index < 0) {
			resolution.reason = append_reason;
			frame.success = false;
			frame.stage = DrawStage::COMPLETE;
			return;
		}
	}
	const int32_t slot = kernel.leftmost_empty_hand_slot(state, frame.owner);
	if (slot < 0) {
		frame.stage = DrawStage::COMPLETE;
		return;
	}
	const int32_t previous_hand_size = static_cast<int32_t>(hand.size());
	state.card_runtime_flags[card_index] |= static_cast<uint8_t>(1 << 7);
	state.card_hand_slots[card_index] = slot;
	hand.push_back(card_index);
	const int32_t logical_hand_index = static_cast<int32_t>(hand.size()) - 1;
	Dictionary event;
	event["type"] = StringName("card_drawn");
	event["source_cell"] = frame.source_cell;
	event["owner_id"] = frame.owner;
	event["card_id"] = state.card_ids[card_index];
	event["instance_id"] = state.card_instance_ids[card_index];
	event["logical_hand_index"] = logical_hand_index;
	event["hand_slot_index"] = slot;
	if (kernel.include_presentation_payloads) {
		event["card"] = kernel.restore_runtime_card(state, card_index);
	}
	resolution.events.append(event);
	for (int64_t audience_index = 0; audience_index < frame.reveal_audiences.size(); ++audience_index) {
		const Variant observer_value = frame.reveal_audiences[audience_index];
		if (observer_value.get_type() != Variant::INT) {
			resolution.reason = "Future-draw reveal audience is not an owner integer";
			frame.success = false;
			frame.stage = DrawStage::COMPLETE;
			return;
		}
		const int32_t observer_owner = static_cast<int32_t>(
			static_cast<int64_t>(observer_value)
		);
		if (observer_owner != 1 && observer_owner != 2) continue;
		uint8_t &reveal_code = state.card_reveal_codes[card_index];
		const bool already_revealed = (
			(observer_owner == 1 && (reveal_code == 1 || reveal_code == 3 || reveal_code == 4))
			|| (observer_owner == 2 && (reveal_code == 2 || reveal_code == 3 || reveal_code == 4))
		);
		if (already_revealed) continue;
		if (observer_owner == 1) reveal_code = reveal_code == 2 ? 4 : 1;
		else reveal_code = reveal_code == 1 ? 3 : 2;
		Dictionary revealed;
		revealed["type"] = StringName("card_revealed");
		revealed["source_cell"] = frame.source_cell;
		revealed["owner_id"] = frame.owner;
		revealed["observer_owner_id"] = observer_owner;
		revealed["card_id"] = state.card_ids[card_index];
		revealed["instance_id"] = state.card_instance_ids[card_index];
		revealed["logical_hand_index"] = logical_hand_index;
		resolution.events.append(revealed);
	}

	DuelNativeCompactKernel::Resolution hand_change = kernel.resolve_difficulty_hand_change(
		state,
		frame.owner,
		previous_hand_size,
		static_cast<int32_t>(hand.size()),
		frame.source_cell,
		exile_stack
	);
	if (!hand_change.supported) {
		resolution.reason = hand_change.reason;
		frame.success = false;
		frame.stage = DrawStage::COMPLETE;
		return;
	}
	kernel.append_resolution(resolution, hand_change);
	DuelNativeCompactKernel::EventContext after_draw_context = frame.draw_context;
	after_draw_context.trigger_cell = -1;
	after_draw_context.trigger_card_index = card_index;
	after_draw_context.trigger_owner = frame.owner;
	after_draw_context.trigger_previous_owner = frame.owner;
	after_draw_context.trigger_zone = 1;
	after_draw_context.trigger_logical_index = logical_hand_index;
	after_draw_context.trigger_was_on_board = false;
	++frame.draw_index;
	frame.stage = DrawStage::WAIT_AFTER_DRAWN;
	push_event_frame(StringName("card_after_drawn"), after_draw_context);
}

void ResolutionEngine::step_discard_frame(
	DuelNativeCompactKernel::NativeState &state,
	std::vector<int32_t> &exile_stack
) {
	DiscardFrame &frame = resolution_frames.back()->discard;
	if (
		frame.stage == DiscardStage::COMPLETE
		|| frame.execution_state == nullptr
		|| frame.resolution == nullptr
	) {
		complete_discard_frame();
		return;
	}
	DuelNativeCompactKernel::Resolution &resolution = *frame.resolution;
	auto append_event_payload = [&](const DuelNativeCompactKernel::Resolution &child) {
		resolution.events.append_array(child.events);
		resolution.captures.append_array(child.captures);
		resolution.exiles.append_array(child.exiles);
	};
	if (frame.stage == DiscardStage::WAIT_CARD_EVENT) {
		if (!completed_event_resolution.supported) {
			resolution.reason = completed_event_resolution.reason;
			frame.outcome = DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
			frame.stage = DiscardStage::COMPLETE;
			return;
		}
		append_event_payload(completed_event_resolution);
		frame.stage = DiscardStage::NEXT_CARD_EVENT;
		return;
	}
	if (frame.stage == DiscardStage::WAIT_BATCH_EVENT) {
		if (!completed_event_resolution.supported) {
			resolution.reason = completed_event_resolution.reason;
			frame.outcome = DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
		} else {
			append_event_payload(completed_event_resolution);
			frame.outcome = DuelNativeCompactKernel::ActionOutcome::APPLIED;
		}
		frame.stage = DiscardStage::COMPLETE;
		return;
	}
	if (frame.stage == DiscardStage::NEXT_CARD_EVENT) {
		while (frame.record_index < frame.records.size()) {
			const DiscardRecord &record = frame.records[frame.record_index++];
			int32_t trigger_zone = -1;
			int32_t trigger_owner = 0;
			int32_t trigger_logical_index = -1;
			if (!kernel.locate_card(
				state,
				record.card_index,
				trigger_zone,
				trigger_owner,
				trigger_logical_index
			)) continue;
			DuelNativeCompactKernel::EventContext discard_context = frame.event_context;
			discard_context.ability_source_cell = frame.action_context.ability_source_cell;
			discard_context.ability_source_zone = frame.action_context.ability_source_zone;
			discard_context.ability_source_logical_index =
				frame.action_context.ability_source_logical_index;
			discard_context.ability_source_card_index =
				frame.action_context.ability_source_card_index;
			discard_context.ability_source_owner = frame.action_context.ability_source_owner;
			discard_context.trigger_cell = -1;
			discard_context.trigger_card_index = record.card_index;
			discard_context.trigger_owner = frame.owner;
			discard_context.trigger_zone = trigger_zone;
			discard_context.trigger_logical_index = trigger_logical_index;
			discard_context.discard_owner = frame.owner;
			discard_context.discard_batch_id = frame.batch_id;
			discard_context.discard_batch_size = static_cast<int32_t>(frame.records.size());
			frame.stage = DiscardStage::WAIT_CARD_EVENT;
			push_event_frame(StringName("card_after_discarded"), discard_context);
			return;
		}
		DuelNativeCompactKernel::EventContext batch_context;
		batch_context.ability_source_cell = frame.action_context.ability_source_cell;
		batch_context.ability_source_zone = frame.action_context.ability_source_zone;
		batch_context.ability_source_logical_index =
			frame.action_context.ability_source_logical_index;
		batch_context.ability_source_card_index = frame.action_context.ability_source_card_index;
		batch_context.ability_source_owner = frame.action_context.ability_source_owner;
		batch_context.discard_owner = frame.owner;
		batch_context.discard_batch_id = frame.batch_id;
		batch_context.discard_batch_size = static_cast<int32_t>(frame.records.size());
		frame.stage = DiscardStage::WAIT_BATCH_EVENT;
		push_event_frame(StringName("discard_batch_finished"), batch_context);
		return;
	}

	frame.execution_state->last_discard_batch_size = 0;
	std::vector<int32_t> candidates;
	for (const int32_t card_index : frame.locked_cards) {
		int32_t zone = -1;
		int32_t candidate_owner = 0;
		int32_t logical_index = -1;
		if (!kernel.locate_card(
			state,
			card_index,
			zone,
			candidate_owner,
			logical_index
		) || zone != 1) continue;
		if (frame.owner == 0) frame.owner = candidate_owner;
		if (candidate_owner != frame.owner) continue;
		candidates.push_back(card_index);
	}
	if (frame.owner < 1 || frame.owner > 2 || candidates.empty()) {
		frame.outcome = DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
		frame.stage = DiscardStage::COMPLETE;
		return;
	}
	std::vector<int32_t> &hand = state.zones[frame.owner - 1];
	std::vector<int32_t> &discard_pile = state.zones[frame.owner + 3];
	const int32_t previous_hand_size = static_cast<int32_t>(hand.size());
	const int32_t discard_size_before = static_cast<int32_t>(discard_pile.size());
	frame.source_instance_id = frame.action_context.ability_source_card_index >= 0
		? state.card_instance_ids[frame.action_context.ability_source_card_index]
		: StringName();
	frame.batch_id = StringName(
		String("discard:")
		+ String(frame.source_instance_id)
		+ ":" + String::num_int64(frame.owner)
		+ ":" + String::num_int64(state.scalars[1])
		+ ":" + String::num_int64(discard_size_before)
	);
	std::vector<int32_t> discarded_slots;
	for (const int32_t card_index : candidates) {
		int32_t zone = -1;
		int32_t current_owner = 0;
		int32_t logical_index = -1;
		if (
			!kernel.locate_card(state, card_index, zone, current_owner, logical_index)
			|| zone != 1
			|| current_owner != frame.owner
			|| logical_index < 0
			|| logical_index >= static_cast<int32_t>(hand.size())
			|| hand[logical_index] != card_index
		) continue;
		DiscardRecord record;
		record.card_index = card_index;
		record.logical_hand_index = logical_index;
		record.hand_slot_index = state.card_hand_slots[card_index] >= 0
			? state.card_hand_slots[card_index]
			: logical_index;
		hand.erase(hand.begin() + logical_index);
		state.card_runtime_flags[card_index] &= static_cast<uint8_t>(~(1 << 7));
		state.card_hand_slots[card_index] = -1;
		discard_pile.push_back(card_index);
		frame.records.push_back(record);
		discarded_slots.push_back(record.hand_slot_index);
	}
	frame.execution_state->last_discard_batch_size = static_cast<int32_t>(frame.records.size());
	if (frame.records.empty()) {
		frame.outcome = DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
		frame.stage = DiscardStage::COMPLETE;
		return;
	}
	frame.source_cell = kernel.find_board_card(
		state,
		frame.action_context.ability_source_card_index,
		frame.action_context.ability_source_cell
	);
	if (frame.source_cell < 0) frame.source_cell = frame.execution_state->current_source_cell;
	frame.execution_state->current_source_cell = frame.source_cell;
	for (const DiscardRecord &record : frame.records) {
		Dictionary discarded;
		discarded["type"] = StringName("card_discarded");
		discarded["source_cell"] = frame.source_cell;
		discarded["source_instance_id"] = frame.source_instance_id;
		discarded["owner_id"] = frame.owner;
		discarded["instance_id"] = state.card_instance_ids[record.card_index];
		discarded["zone"] = StringName("hand");
		discarded["logical_hand_index"] = record.logical_hand_index;
		discarded["hand_slot_index"] = record.hand_slot_index;
		discarded["discard_batch_id"] = frame.batch_id;
		discarded["discard_batch_size"] = static_cast<int32_t>(frame.records.size());
		if (kernel.include_presentation_payloads) {
			discarded["card"] = kernel.restore_runtime_card(state, record.card_index);
		}
		resolution.events.append(discarded);
	}
	std::sort(discarded_slots.begin(), discarded_slots.end());
	struct SlotMove {
		int32_t card_index = -1;
		int32_t from_slot = -1;
		int32_t to_slot = -1;
	};
	std::vector<SlotMove> slot_moves;
	for (const int32_t card_index : hand) {
		const int32_t from_slot = state.card_hand_slots[card_index];
		if (from_slot < 0) continue;
		const int32_t removed_before = static_cast<int32_t>(std::count_if(
			discarded_slots.begin(),
			discarded_slots.end(),
			[&](int32_t discarded_slot) { return discarded_slot < from_slot; }
		));
		const int32_t to_slot = from_slot - removed_before;
		if (to_slot == from_slot) continue;
		slot_moves.push_back({card_index, from_slot, to_slot});
		state.card_hand_slots[card_index] = to_slot;
	}
	std::sort(slot_moves.begin(), slot_moves.end(), [](const SlotMove &left, const SlotMove &right) {
		return left.from_slot < right.from_slot;
	});
	if (!slot_moves.empty()) {
		Array moves;
		for (const SlotMove &move : slot_moves) {
			Dictionary move_payload;
			move_payload["instance_id"] = state.card_instance_ids[move.card_index];
			move_payload["from_slot"] = move.from_slot;
			move_payload["to_slot"] = move.to_slot;
			moves.append(move_payload);
		}
		Dictionary shifted;
		shifted["type"] = StringName("hand_cards_shifted");
		shifted["source_cell"] = frame.source_cell;
		shifted["source_instance_id"] = frame.source_instance_id;
		shifted["owner_id"] = frame.owner;
		shifted["moves"] = moves;
		resolution.events.append(shifted);
	}
	DuelNativeCompactKernel::Resolution hand_change = kernel.resolve_difficulty_hand_change(
		state,
		frame.owner,
		previous_hand_size,
		static_cast<int32_t>(hand.size()),
		frame.source_cell,
		exile_stack
	);
	if (!hand_change.supported) {
		resolution.reason = hand_change.reason;
		frame.outcome = DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
		frame.stage = DiscardStage::COMPLETE;
		return;
	}
	kernel.append_resolution(resolution, hand_change);
	frame.stage = DiscardStage::NEXT_CARD_EVENT;
}

void ResolutionEngine::step_move_frame(
	DuelNativeCompactKernel::NativeState &state,
	std::vector<int32_t> &exile_stack
) {
	(void)exile_stack;
	MoveFrame &frame = resolution_frames.back()->move;
	if (frame.stage == MoveStage::COMPLETE || frame.resolution == nullptr) {
		complete_move_frame();
		return;
	}
	DuelNativeCompactKernel::Resolution &resolution = *frame.resolution;
	auto movement_context = [&](int32_t source_cell) {
		DuelNativeCompactKernel::EventContext context;
		context.trigger_cell = source_cell;
		context.trigger_card_index = frame.moving_card_index;
		context.trigger_owner = frame.moving_owner;
		context.trigger_zone = 0;
		context.trigger_logical_index = source_cell;
		context.trigger_was_on_board = true;
		context.moving_source_cell = source_cell;
		context.moving_origin_cell = frame.origin_cell;
		context.moving_target_cell = frame.target_cell;
		context.moving_card_index = frame.moving_card_index;
		context.moving_owner = frame.moving_owner;
		return context;
	};
	if (frame.stage == MoveStage::START) {
		if (
			frame.source_cell < 0
			|| frame.target_cell < 0
			|| frame.source_cell >= static_cast<int32_t>(state.board_card_indices.size())
			|| frame.target_cell >= static_cast<int32_t>(state.board_card_indices.size())
			|| state.board_card_indices[frame.source_cell] != frame.moving_card_index
			|| state.board_owners[frame.source_cell] != frame.moving_owner
			|| state.board_card_indices[frame.target_cell] >= 0
		) {
			frame.stage = MoveStage::COMPLETE;
			return;
		}
		if (frame.resolve_before_event) {
			frame.stage = MoveStage::WAIT_BEFORE;
			push_event_frame(
				StringName("card_before_moved"),
				movement_context(frame.source_cell)
			);
			return;
		}
		frame.stage = MoveStage::MOVE;
		return;
	}
	if (frame.stage == MoveStage::WAIT_BEFORE) {
		if (!completed_event_resolution.supported) {
			resolution.reason = completed_event_resolution.reason;
			frame.outcome = DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
			frame.stage = MoveStage::COMPLETE;
			return;
		}
		kernel.append_resolution(frame.movement_resolution, completed_event_resolution);
		if (
			kernel.find_board_card(state, frame.moving_card_index, frame.source_cell)
				!= frame.source_cell
			|| state.board_owners[frame.source_cell] != frame.moving_owner
			|| state.board_card_indices[frame.target_cell] >= 0
		) {
			kernel.append_resolution(resolution, frame.movement_resolution);
			frame.outcome = kernel.resolution_has_output(frame.movement_resolution)
				? DuelNativeCompactKernel::ActionOutcome::APPLIED
				: DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
			frame.stage = MoveStage::COMPLETE;
			return;
		}
		frame.stage = MoveStage::MOVE;
		return;
	}
	if (frame.stage == MoveStage::MOVE) {
		const Variant moving_extra = state.board_slot_extras[frame.source_cell];
		state.board_card_indices[frame.source_cell] = -1;
		state.board_owners[frame.source_cell] = 0;
		state.board_slot_extras[frame.source_cell] = Dictionary();
		state.board_card_indices[frame.target_cell] = frame.moving_card_index;
		state.board_owners[frame.target_cell] = static_cast<uint8_t>(frame.moving_owner);
		state.board_slot_extras[frame.target_cell] = moving_extra;
		Dictionary moved;
		moved["type"] = StringName("card_moved");
		moved["source_cell"] = frame.source_cell;
		moved["target_cell"] = frame.target_cell;
		moved["owner_id"] = frame.moving_owner;
		moved["instance_id"] = state.card_instance_ids[frame.moving_card_index];
		frame.movement_resolution.events.append(moved);
		frame.stage = MoveStage::WAIT_AFTER;
		push_event_frame(
			StringName("card_after_moved"),
			movement_context(frame.target_cell)
		);
		return;
	}
	if (!completed_event_resolution.supported) {
		resolution.reason = completed_event_resolution.reason;
		frame.outcome = DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
		frame.stage = MoveStage::COMPLETE;
		return;
	}
	kernel.append_resolution(frame.movement_resolution, completed_event_resolution);
	kernel.append_resolution(resolution, frame.movement_resolution);
	frame.outcome = DuelNativeCompactKernel::ActionOutcome::APPLIED;
	frame.stage = MoveStage::COMPLETE;
}

void ResolutionEngine::step_swap_frame(
	DuelNativeCompactKernel::NativeState &state,
	std::vector<int32_t> &exile_stack
) {
	(void)exile_stack;
	SwapFrame &frame = resolution_frames.back()->swap;
	if (frame.stage == SwapStage::COMPLETE || frame.resolution == nullptr) {
		complete_swap_frame();
		return;
	}
	DuelNativeCompactKernel::Resolution &resolution = *frame.resolution;
	auto movement_context = [&](
		int32_t source_cell,
		int32_t origin_cell,
		int32_t target_cell,
		int32_t moving_card,
		int32_t moving_owner
	) {
		DuelNativeCompactKernel::EventContext context;
		context.trigger_cell = source_cell;
		context.trigger_card_index = moving_card;
		context.trigger_owner = moving_owner;
		context.trigger_zone = 0;
		context.trigger_logical_index = source_cell;
		context.trigger_was_on_board = true;
		context.moving_source_cell = source_cell;
		context.moving_origin_cell = origin_cell;
		context.moving_target_cell = target_cell;
		context.moving_card_index = moving_card;
		context.moving_owner = moving_owner;
		return context;
	};
	if (frame.stage == SwapStage::START) {
		if (
			frame.source_card_index < 0
			|| frame.target_card_index < 0
			|| frame.source_card_index == frame.target_card_index
			|| frame.source_cell < 0
			|| frame.target_cell < 0
			|| state.board_owners[frame.source_cell] != frame.source_owner
			|| state.board_owners[frame.target_cell] != frame.target_owner
		) {
			frame.stage = SwapStage::COMPLETE;
			return;
		}
		bool adjacent = false;
		for (int32_t direction = 0; direction < 4; ++direction) {
			if (neighbor_index(frame.source_cell, direction) == frame.target_cell) {
				adjacent = true;
				break;
			}
		}
		if (!adjacent) {
			frame.stage = SwapStage::COMPLETE;
			return;
		}
		frame.stage = SwapStage::WAIT_SOURCE_BEFORE;
		push_event_frame(
			StringName("card_before_moved"),
			movement_context(
				frame.source_cell,
				frame.source_cell,
				frame.target_cell,
				frame.source_card_index,
				frame.source_owner
			)
		);
		return;
	}
	if (frame.stage == SwapStage::WAIT_SOURCE_BEFORE) {
		if (!completed_event_resolution.supported) {
			resolution.reason = completed_event_resolution.reason;
			frame.outcome = DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
			frame.stage = SwapStage::COMPLETE;
			return;
		}
		if (
			kernel.find_board_card(state, frame.source_card_index, frame.source_cell)
				!= frame.source_cell
			|| state.board_owners[frame.source_cell] != frame.source_owner
			|| kernel.find_board_card(state, frame.target_card_index, frame.target_cell)
				!= frame.target_cell
			|| state.board_owners[frame.target_cell] != frame.target_owner
		) {
			kernel.append_resolution(resolution, completed_event_resolution);
			frame.outcome = kernel.resolution_has_output(completed_event_resolution)
				? DuelNativeCompactKernel::ActionOutcome::APPLIED
				: DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
			frame.stage = SwapStage::COMPLETE;
			return;
		}
		frame.reserved_target_extra = state.board_slot_extras[frame.target_cell];
		state.board_card_indices[frame.target_cell] = -1;
		state.board_owners[frame.target_cell] = 0;
		state.board_slot_extras[frame.target_cell] = Dictionary();
		kernel.append_resolution(frame.swap_resolution, completed_event_resolution);
		frame.stage = SwapStage::WAIT_SOURCE_MOVE;
		push_move_frame(
			frame.source_cell,
			frame.source_cell,
			frame.target_cell,
			frame.source_card_index,
			frame.source_owner,
			false,
			frame.swap_resolution
		);
		return;
	}
	if (frame.stage == SwapStage::WAIT_SOURCE_MOVE) {
		if (completed_move_outcome == DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED) {
			resolution.reason = frame.swap_resolution.reason;
			frame.outcome = completed_move_outcome;
			frame.stage = SwapStage::COMPLETE;
			return;
		}
		if (completed_move_outcome != DuelNativeCompactKernel::ActionOutcome::APPLIED) {
			kernel.append_resolution(resolution, frame.swap_resolution);
			frame.outcome = completed_move_outcome;
			frame.stage = SwapStage::COMPLETE;
			return;
		}
		if (
			kernel.find_board_card(state, frame.source_card_index, frame.target_cell)
				!= frame.target_cell
			|| state.board_owners[frame.target_cell] != frame.source_owner
		) {
			resolution.reason = "First swap leg was invalidated after movement";
			frame.outcome = DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
			frame.stage = SwapStage::COMPLETE;
			return;
		}
		frame.reserved_source_extra = state.board_slot_extras[frame.target_cell];
		state.board_card_indices[frame.target_cell] = frame.target_card_index;
		state.board_owners[frame.target_cell] = static_cast<uint8_t>(frame.target_owner);
		state.board_slot_extras[frame.target_cell] = frame.reserved_target_extra;
		frame.stage = SwapStage::WAIT_TARGET_BEFORE;
		push_event_frame(
			StringName("card_before_moved"),
			movement_context(
				frame.target_cell,
				frame.target_cell,
				frame.source_cell,
				frame.target_card_index,
				frame.target_owner
			)
		);
		return;
	}
	if (frame.stage == SwapStage::WAIT_TARGET_BEFORE) {
		if (!completed_event_resolution.supported) {
			resolution.reason = completed_event_resolution.reason;
			frame.outcome = DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
			frame.stage = SwapStage::COMPLETE;
			return;
		}
		if (
			kernel.find_board_card(state, frame.target_card_index, frame.target_cell)
				!= frame.target_cell
			|| state.board_owners[frame.target_cell] != frame.target_owner
		) {
			state.board_card_indices[frame.source_cell] = frame.source_card_index;
			state.board_owners[frame.source_cell] = static_cast<uint8_t>(frame.source_owner);
			state.board_slot_extras[frame.source_cell] = frame.reserved_source_extra;
			state.board_card_indices[frame.target_cell] = frame.target_card_index;
			state.board_owners[frame.target_cell] = static_cast<uint8_t>(frame.target_owner);
			state.board_slot_extras[frame.target_cell] = frame.reserved_target_extra;
			frame.outcome = DuelNativeCompactKernel::ActionOutcome::NO_EFFECT;
			frame.stage = SwapStage::COMPLETE;
			return;
		}
		kernel.append_resolution(frame.swap_resolution, completed_event_resolution);
		frame.stage = SwapStage::WAIT_TARGET_MOVE;
		push_move_frame(
			frame.target_cell,
			frame.target_cell,
			frame.source_cell,
			frame.target_card_index,
			frame.target_owner,
			false,
			frame.swap_resolution
		);
		return;
	}
	if (completed_move_outcome == DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED) {
		resolution.reason = frame.swap_resolution.reason;
		frame.outcome = completed_move_outcome;
		frame.stage = SwapStage::COMPLETE;
		return;
	}
	if (completed_move_outcome != DuelNativeCompactKernel::ActionOutcome::APPLIED) {
		resolution.reason = "Second swap leg could not move its exact instance";
		frame.outcome = DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
		frame.stage = SwapStage::COMPLETE;
		return;
	}
	state.board_card_indices[frame.target_cell] = frame.source_card_index;
	state.board_owners[frame.target_cell] = static_cast<uint8_t>(frame.source_owner);
	state.board_slot_extras[frame.target_cell] = frame.reserved_source_extra;
	kernel.append_resolution(resolution, frame.swap_resolution);
	frame.outcome = DuelNativeCompactKernel::ActionOutcome::APPLIED;
	frame.stage = SwapStage::COMPLETE;
}

void ResolutionEngine::step_summon_frame(
	DuelNativeCompactKernel::NativeState &state,
	std::vector<int32_t> &exile_stack
) {
	SummonFrame &frame = resolution_frames.back()->summon;
	if (frame.stage == SummonStage::COMPLETE) {
		complete_summon_frame();
		return;
	}
	if (frame.stage == SummonStage::START) {
		frame.attack_redirect_source_card_indices =
			frame.request.attack_redirect_snapshot_taken
			? frame.request.attack_redirect_source_card_indices
			: kernel.snapshot_summon_attack_redirect_sources(
				state,
				frame.request.summon_cell,
				frame.request.owner_id
			);
		frame.summon_context.trigger_cell = frame.request.summon_cell;
		frame.summon_context.trigger_card_index = frame.request.card_index;
		frame.summon_context.trigger_owner = frame.request.owner_id;
		frame.summon_context.trigger_previous_owner = frame.request.owner_id;
		frame.summon_context.trigger_zone = 0;
		frame.summon_context.trigger_logical_index = frame.request.summon_cell;
		frame.summon_context.trigger_was_on_board = true;
		frame.stage = SummonStage::WAIT_BEFORE_SUMMONED;
		push_event_frame(StringName("card_before_summoned"), frame.summon_context);
		return;
	}
	if (frame.stage == SummonStage::WAIT_BEFORE_SUMMONED) {
		if (!completed_event_resolution.supported) {
			frame.resolution = std::move(completed_event_resolution);
			frame.stage = SummonStage::COMPLETE;
			return;
		}
		kernel.append_resolution(frame.resolution, completed_event_resolution);
		frame.resolution.events.append_array(frame.request.buffered_placement_events);
		frame.stage = SummonStage::WAIT_SUMMONED;
		push_event_frame(StringName("card_summoned"), frame.summon_context);
		return;
	}
	if (frame.stage == SummonStage::WAIT_SUMMONED) {
		if (!completed_event_resolution.supported) {
			frame.resolution.supported = false;
			frame.resolution.reason = completed_event_resolution.reason;
			frame.stage = SummonStage::COMPLETE;
			return;
		}
		kernel.append_resolution(frame.resolution, completed_event_resolution);
		frame.after_summoned_cell = kernel.find_board_card(
			state,
			frame.request.card_index,
			frame.request.summon_cell
		);
		if (frame.after_summoned_cell < 0) {
			frame.stage = SummonStage::RESOLVE_ATTACK;
			return;
		}
		DuelNativeCompactKernel::EventContext after_context = frame.summon_context;
		after_context.trigger_cell = frame.after_summoned_cell;
		after_context.trigger_owner = state.board_owners[frame.after_summoned_cell];
		after_context.trigger_logical_index = frame.after_summoned_cell;
		frame.stage = SummonStage::WAIT_AFTER_SUMMONED;
		push_event_frame(StringName("card_after_summoned"), after_context);
		return;
	}
	if (frame.stage == SummonStage::WAIT_AFTER_SUMMONED) {
		if (!completed_event_resolution.supported) {
			frame.resolution.supported = false;
			frame.resolution.reason = completed_event_resolution.reason;
			frame.stage = SummonStage::COMPLETE;
			return;
		}
		kernel.append_resolution(frame.resolution, completed_event_resolution);
		frame.stage = SummonStage::RESOLVE_ATTACK;
		return;
	}
	if (frame.stage == SummonStage::WAIT_ATTACK) {
		if (!completed_attack_resolution.supported) {
			frame.resolution = std::move(completed_attack_resolution);
		} else {
			kernel.append_resolution(frame.resolution, completed_attack_resolution);
		}
		frame.stage = SummonStage::COMPLETE;
		return;
	}

	const StringName summoned_instance_id =
		state.card_instance_ids[frame.request.card_index];
	for (int64_t event_index = 0; event_index < frame.resolution.events.size(); ++event_index) {
		if (frame.resolution.events[event_index].get_type() != Variant::DICTIONARY) continue;
		const Dictionary event = frame.resolution.events[event_index];
		if (
			StringName(event.get("type", StringName())) == StringName("card_flipped")
			&& StringName(event.get("instance_id", StringName())) == summoned_instance_id
		) {
			frame.stage = SummonStage::COMPLETE;
			return;
		}
	}

	DuelNativeCompactKernel::AttackRequest attack_request;
	attack_request.attacker_cell = frame.after_summoned_cell;
	attack_request.attacker_card_index = frame.request.card_index;
	attack_request.attacker_owner = frame.request.owner_id;
	const int32_t initial_attack_cell = kernel.find_board_card(
		state,
		frame.request.card_index,
		frame.request.summon_cell
	);
	if (initial_attack_cell >= 0) {
		attack_request.requested_policy = kernel.get_summon_attack_policy(
			state,
			initial_attack_cell,
			frame.request.owner_id,
			frame.attack_redirect_source_card_indices
		);
	}
	attack_request.reason = frame.request.attack_reason.is_empty()
		? StringName("summon_standard_attack")
		: frame.request.attack_reason;
	frame.stage = SummonStage::WAIT_ATTACK;
	push_attack_frame(attack_request);
}

void ResolutionEngine::step_attack_frame(
	DuelNativeCompactKernel::NativeState &state,
	std::vector<int32_t> &exile_stack
) {
	AttackFrame &frame = resolution_frames.back()->attack;
	if (frame.stage == AttackStage::COMPLETE) {
		complete_attack_frame();
		return;
	}
	auto events_flipped_card = [&](const DuelNativeCompactKernel::Resolution &candidate,
		int64_t first_event_index, int32_t card_index) -> bool {
		if (
			card_index < 0
			|| card_index >= static_cast<int32_t>(state.card_instance_ids.size())
		) return false;
		const StringName instance_id = state.card_instance_ids[card_index];
		for (
			int64_t event_index = first_event_index;
			event_index < candidate.events.size();
			++event_index
		) {
			if (candidate.events[event_index].get_type() != Variant::DICTIONARY) continue;
			const Dictionary event = candidate.events[event_index];
			if (
				StringName(event.get("type", StringName())) == StringName("card_flipped")
				&& StringName(event.get("instance_id", StringName())) == instance_id
			) return true;
		}
		return false;
	};
	if (frame.stage == AttackStage::START) {
		const int32_t initial_attack_cell = kernel.find_board_card(
			state,
			frame.request.attacker_card_index,
			frame.request.attacker_cell
		);
		if (
			initial_attack_cell < 0
			|| state.board_owners[initial_attack_cell] != frame.request.attacker_owner
			|| state.scalars[frame.request.attacker_owner == 1 ? 3 : 4] >= 20
			|| kernel.attack_is_prohibited(state, frame.request.attacker_owner)
		) {
			frame.stage = AttackStage::COMPLETE;
			return;
		}
		frame.attack_policy = kernel.get_standard_attack_policy(
			state,
			initial_attack_cell,
			frame.request.attacker_card_index,
			frame.request.attacker_owner,
			frame.request.requested_policy
		);
		if (frame.request.targeted) {
			const int32_t target_cell = kernel.find_board_card(
				state,
				frame.request.locked_target_card_index,
				frame.request.locked_target_cell
			);
			if (
				target_cell == frame.request.locked_target_cell
				&& target_cell >= 0
				&& state.board_owners[target_cell] == frame.request.locked_target_owner
				&& kernel.can_attack_target(
					state,
					initial_attack_cell,
					target_cell,
					frame.attack_policy,
					false
				)
			) frame.target_cells.push_back(target_cell);
		} else {
			frame.target_cells = kernel.get_attack_targets(
				state,
				initial_attack_cell,
				frame.attack_policy
			);
		}
		if (!frame.target_cells.empty()) {
			state.scalars[frame.request.attacker_owner == 1 ? 3 : 4] += 1;
		}
		frame.stage = AttackStage::NEXT_TARGET;
		return;
	}
	if (frame.stage == AttackStage::WAIT_BE_ATTACKED) {
		if (!completed_event_resolution.supported) {
			frame.resolution = std::move(completed_event_resolution);
			frame.stage = AttackStage::COMPLETE;
			return;
		}
		frame.stop_after_current_target = events_flipped_card(
			completed_event_resolution,
			0,
			frame.request.attacker_card_index
		);
		kernel.append_resolution(frame.resolution, completed_event_resolution);
		const int32_t current_attacker_cell = kernel.find_board_card(
			state,
			frame.request.attacker_card_index,
			frame.attacker_cell
		);
		const int32_t current_attacked_cell = kernel.find_board_card(
			state,
			frame.attacked_card_index,
			frame.attacked_cell
		);
		if (
			current_attacker_cell < 0
			|| state.board_owners[current_attacker_cell] != frame.request.attacker_owner
		) {
			frame.target_index = frame.target_cells.size();
			frame.stage = AttackStage::NEXT_TARGET;
			return;
		}
		if (
			current_attacked_cell < 0
			|| !kernel.can_attack_target(
				state,
				current_attacker_cell,
				current_attacked_cell,
				frame.attack_policy,
				true
			)
		) {
			if (frame.stop_after_current_target) frame.target_index = frame.target_cells.size();
			frame.stage = AttackStage::NEXT_TARGET;
			return;
		}
		frame.resolved_capture_owner = frame.request.attacker_owner;
		if (state.board_owners[current_attacked_cell] == frame.request.attacker_owner) {
			frame.resolved_capture_owner = frame.attack_policy.capture_owner_id != 0
				? frame.attack_policy.capture_owner_id
				: other_owner(frame.request.attacker_owner);
		}
		if (frame.resolved_capture_owner == state.board_owners[current_attacked_cell]) {
			if (frame.stop_after_current_target) frame.target_index = frame.target_cells.size();
			frame.stage = AttackStage::NEXT_TARGET;
			return;
		}
		frame.flipped_previous_owner = state.board_owners[current_attacked_cell];
		DuelNativeCompactKernel::EventContext before_context = frame.attack_context;
		before_context.attacker_cell = current_attacker_cell;
		before_context.attacked_cell = current_attacked_cell;
		before_context.attacked_owner = state.board_owners[current_attacked_cell];
		before_context.trigger_cell = current_attacked_cell;
		before_context.trigger_owner = state.board_owners[current_attacked_cell];
		before_context.new_owner = frame.resolved_capture_owner;
		before_context.flip_reason = frame.request.reason;
		frame.flip_event_start = frame.resolution.events.size();
		frame.stage = AttackStage::WAIT_FLIP;
		push_flip_frame(
			current_attacker_cell,
			frame.request.attacker_card_index,
			current_attacked_cell,
			frame.attacked_card_index,
			frame.resolved_capture_owner,
			before_context,
			frame.resolution,
			true,
			frame.request.attacker_owner
		);
		return;
	}
	if (frame.stage == AttackStage::WAIT_FLIP) {
		if (!completed_flip_success) {
			frame.resolution.supported = false;
			frame.stage = AttackStage::COMPLETE;
			return;
		}
		frame.stop_after_current_target = frame.stop_after_current_target
			|| events_flipped_card(
				frame.resolution,
				frame.flip_event_start,
				frame.request.attacker_card_index
			);
		if (events_flipped_card(
			frame.resolution,
			frame.flip_event_start,
			frame.attacked_card_index
		)) {
			frame.attack_flipped_enemy = frame.attack_flipped_enemy
				|| frame.flipped_previous_owner != frame.request.attacker_owner;
			DuelNativeCompactKernel::EventContext::AttackFlipRecord flip_record;
			flip_record.card_index = frame.attacked_card_index;
			flip_record.previous_owner = frame.flipped_previous_owner;
			frame.attack_flips.push_back(flip_record);
		}
		if (frame.stop_after_current_target) frame.target_index = frame.target_cells.size();
		frame.stage = AttackStage::NEXT_TARGET;
		return;
	}
	if (frame.stage == AttackStage::WAIT_AFTER_ATTACK) {
		if (!completed_event_resolution.supported) {
			frame.resolution = std::move(completed_event_resolution);
		} else {
			kernel.append_resolution(frame.resolution, completed_event_resolution);
		}
		frame.stage = AttackStage::COMPLETE;
		return;
	}

	while (frame.target_index < frame.target_cells.size()) {
		const int32_t locked_cell = frame.target_cells[frame.target_index++];
		frame.attacker_cell = kernel.find_board_card(
			state,
			frame.request.attacker_card_index,
			frame.request.attacker_cell
		);
		if (
			frame.attacker_cell < 0
			|| state.board_owners[frame.attacker_cell] != frame.request.attacker_owner
		) {
			frame.target_index = frame.target_cells.size();
			break;
		}
		frame.attacked_card_index = state.board_card_indices[locked_cell];
		if (frame.attacked_card_index < 0) continue;
		frame.attacked_cell = locked_cell;
		if (!kernel.can_attack_target(
			state,
			frame.attacker_cell,
			frame.attacked_cell,
			frame.attack_policy,
			true
		)) continue;
		frame.attacked_owner = state.board_owners[frame.attacked_cell];
		Dictionary attack_event;
		attack_event["type"] = StringName("attack_started");
		attack_event["source_cell"] = frame.attacker_cell;
		attack_event["source_instance_id"] =
			state.card_instance_ids[frame.request.attacker_card_index];
		attack_event["source_owner_id"] = frame.request.attacker_owner;
		attack_event["target_cell"] = frame.attacked_cell;
		attack_event["target_instance_id"] =
			state.card_instance_ids[frame.attacked_card_index];
		attack_event["target_owner_id"] = frame.attacked_owner;
		attack_event["attack_reason"] = frame.request.reason;
		frame.resolution.events.append(attack_event);
		frame.attack_started = true;
		frame.attack_context = DuelNativeCompactKernel::EventContext();
		frame.attack_context.attacker_cell = frame.attacker_cell;
		frame.attack_context.attacker_card_index = frame.request.attacker_card_index;
		frame.attack_context.attacker_owner = frame.request.attacker_owner;
		frame.attack_context.attacked_cell = frame.attacked_cell;
		frame.attack_context.attacked_card_index = frame.attacked_card_index;
		frame.attack_context.attacked_owner = frame.attacked_owner;
		frame.attack_context.trigger_cell = frame.attacked_cell;
		frame.attack_context.trigger_card_index = frame.attacked_card_index;
		frame.attack_context.trigger_owner = frame.attacked_owner;
		frame.attack_context.trigger_previous_owner = frame.attacked_owner;
		frame.attack_context.trigger_zone = 0;
		frame.attack_context.trigger_logical_index = frame.attacked_cell;
		frame.attack_context.trigger_was_on_board = true;
		frame.attack_context.attack_reason = frame.request.reason;
		frame.stop_after_current_target = false;
		frame.stage = AttackStage::WAIT_BE_ATTACKED;
		push_event_frame(StringName("card_be_attacked"), frame.attack_context);
		return;
	}
	if (!frame.attack_started) {
		frame.stage = AttackStage::COMPLETE;
		return;
	}
	DuelNativeCompactKernel::EventContext after_attack_context;
	after_attack_context.attacker_cell = kernel.find_board_card(
		state,
		frame.request.attacker_card_index,
		frame.request.attacker_cell
	);
	after_attack_context.attacker_card_index = frame.request.attacker_card_index;
	after_attack_context.attacker_owner = frame.request.attacker_owner;
	after_attack_context.attack_flipped_enemy = frame.attack_flipped_enemy;
	after_attack_context.attack_flips = frame.attack_flips;
	after_attack_context.repeat_attack = frame.request.repeat_attack;
	frame.stage = AttackStage::WAIT_AFTER_ATTACK;
	push_event_frame(StringName("card_after_attack"), after_attack_context);
}

void ResolutionEngine::step_distribute_ki_frame(
	DuelNativeCompactKernel::NativeState &state,
	std::vector<int32_t> &exile_stack
) {
	DistributeKiFrame &frame = resolution_frames.back()->distribute_ki;
	if (frame.stage == DistributeKiStage::COMPLETE || frame.resolution == nullptr) {
		complete_distribute_ki_frame();
		return;
	}
	DuelNativeCompactKernel::Resolution &resolution = *frame.resolution;
	if (frame.stage == DistributeKiStage::START) {
		frame.distributor = kernel.resolve_action_card_reference(
			frame.action.from_card_ref,
			frame.event_context,
			frame.action_context,
			frame.execution_state
		);
		if (
			frame.distributor < 0
			|| !kernel.locate_card(
				state,
				frame.distributor,
				frame.distributor_zone,
				frame.distributor_owner,
				frame.distributor_logical_index
			)
			|| frame.distributor_zone == 2
		) {
			frame.stage = DistributeKiStage::COMPLETE;
			return;
		}
		frame.selector_context = frame.action_context;
		frame.selector_context.ability_source_card_index = frame.distributor;
		frame.selector_context.ability_source_owner = frame.distributor_owner;
		frame.selector_context.ability_source_zone = frame.distributor_zone;
		frame.selector_context.ability_source_logical_index =
			frame.distributor_logical_index;
		frame.selector_context.ability_source_cell = frame.distributor_zone == 0
			? frame.distributor_logical_index
			: -1;
		bool selection_supported = true;
		frame.selected_cards = kernel.snapshot_selected_cards(
			state,
			frame.action.selector,
			frame.selector_context,
			selection_supported
		);
		if (!selection_supported) {
			frame.outcome = DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
			frame.stage = DistributeKiStage::COMPLETE;
			return;
		}
		frame.stage = DistributeKiStage::NEXT_ROUND;
		return;
	}
	if (frame.stage == DistributeKiStage::WAIT_KI_EVENT) {
		if (!completed_event_resolution.supported) {
			resolution.reason = completed_event_resolution.reason;
			frame.outcome = DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
			frame.stage = DistributeKiStage::COMPLETE;
			return;
		}
		kernel.append_resolution(resolution, completed_event_resolution);
		frame.stage = DistributeKiStage::NEXT_KI_EVENT;
		return;
	}
	if (frame.stage == DistributeKiStage::NEXT_KI_EVENT) {
		while (frame.ki_event_index < frame.ki_event_end) {
			const int64_t event_index = frame.ki_event_index++;
			if (resolution.events[event_index].get_type() != Variant::DICTIONARY) continue;
			Dictionary ki_event = resolution.events[event_index];
			ki_event["ki_trigger_resolved"] = true;
			resolution.events[event_index] = ki_event;
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
			frame.stage = DistributeKiStage::WAIT_KI_EVENT;
			push_event_frame(StringName("card_ki_changed"), ki_context);
			return;
		}
		frame.transferred_in_round = true;
		frame.outcome = DuelNativeCompactKernel::ActionOutcome::APPLIED;
		frame.stage = DistributeKiStage::NEXT_RECIPIENT;
		return;
	}
	if (frame.stage == DistributeKiStage::NEXT_ROUND) {
		if (
			!kernel.locate_card(
				state,
				frame.distributor,
				frame.distributor_zone,
				frame.distributor_owner,
				frame.distributor_logical_index
			)
			|| frame.distributor_zone == 2
			|| state.card_ki[frame.distributor] < frame.action.amount
		) {
			frame.stage = DistributeKiStage::COMPLETE;
			return;
		}
		frame.recipient_index = 0;
		frame.transferred_in_round = false;
		frame.stage = DistributeKiStage::NEXT_RECIPIENT;
		return;
	}

	while (frame.recipient_index < frame.selected_cards.size()) {
		if (
			!kernel.locate_card(
				state,
				frame.distributor,
				frame.distributor_zone,
				frame.distributor_owner,
				frame.distributor_logical_index
			)
			|| frame.distributor_zone == 2
			|| state.card_ki[frame.distributor] < frame.action.amount
		) break;
		const int32_t recipient = frame.selected_cards[frame.recipient_index++];
		int32_t recipient_zone = -1;
		int32_t recipient_owner = 0;
		int32_t recipient_logical_index = -1;
		if (
			!kernel.locate_card(
				state,
				recipient,
				recipient_zone,
				recipient_owner,
				recipient_logical_index
			)
			|| recipient_zone == 2
		) continue;
		frame.selector_context.ability_source_owner = frame.distributor_owner;
		frame.selector_context.ability_source_zone = frame.distributor_zone;
		frame.selector_context.ability_source_logical_index =
			frame.distributor_logical_index;
		frame.selector_context.ability_source_cell = frame.distributor_zone == 0
			? frame.distributor_logical_index
			: -1;
		bool condition_supported = true;
		if (!kernel.selector_conditions_match(
			state,
			recipient,
			recipient_zone,
			recipient_owner,
			recipient_logical_index,
			frame.action.selector,
			frame.selector_context,
			condition_supported
		)) {
			if (!condition_supported) {
				frame.outcome = DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
				frame.stage = DistributeKiStage::COMPLETE;
				return;
			}
			continue;
		}

		frame.ki_event_index = resolution.events.size();
		DuelNativeCompactKernel::CompiledAction donor_action;
		donor_action.opcode = DuelNativeCompactKernel::ActionOpcode::SPEND_KI;
		donor_action.card_ref_explicit = true;
		donor_action.card_ref = DuelNativeCompactKernel::CardRefOpcode::SELECTED_CARD;
		donor_action.amount = frame.action.amount;
		donor_action.change_reason = StringName("transfer_card_resource");
		DuelNativeCompactKernel::ActionContext donor_context = frame.action_context;
		donor_context.selected_card_index = frame.distributor;
		donor_context.selected_card_owner = frame.distributor_owner;
		donor_context.action_subject_owner = frame.distributor_owner;
		const DuelNativeCompactKernel::ActionOutcome donor_outcome = kernel.change_ki(
			state,
			frame.group,
			donor_action,
			frame.event_context,
			donor_context,
			frame.execution_state.current_source_cell,
			exile_stack,
			resolution
		);
		if (donor_outcome != DuelNativeCompactKernel::ActionOutcome::APPLIED) continue;
		DuelNativeCompactKernel::CompiledAction receiver_action = donor_action;
		receiver_action.opcode = DuelNativeCompactKernel::ActionOpcode::GAIN_KI;
		DuelNativeCompactKernel::ActionContext receiver_context = frame.action_context;
		receiver_context.selected_card_index = recipient;
		receiver_context.selected_card_owner = recipient_owner;
		receiver_context.action_subject_owner = recipient_owner;
		const DuelNativeCompactKernel::ActionOutcome receiver_outcome = kernel.change_ki(
			state,
			frame.group,
			receiver_action,
			frame.event_context,
			receiver_context,
			frame.execution_state.current_source_cell,
			exile_stack,
			resolution
		);
		if (receiver_outcome != DuelNativeCompactKernel::ActionOutcome::APPLIED) {
			frame.outcome = receiver_outcome;
			frame.stage = DistributeKiStage::COMPLETE;
			return;
		}
		frame.ki_event_end = resolution.events.size();
		frame.stage = DistributeKiStage::NEXT_KI_EVENT;
		return;
	}
	if (!frame.transferred_in_round) {
		frame.stage = DistributeKiStage::COMPLETE;
		return;
	}
	frame.stage = DistributeKiStage::NEXT_ROUND;
}

void ResolutionEngine::step_power_change_frame(
	DuelNativeCompactKernel::NativeState &state,
	std::vector<int32_t> &exile_stack
) {
	PowerChangeFrame &frame = resolution_frames.back()->power_change;
	if (frame.stage == PowerChangeStage::COMPLETE || frame.resolution == nullptr) {
		complete_power_change_frame();
		return;
	}
	if (frame.stage == PowerChangeStage::WAIT_EXILE) {
		frame.outcome = completed_exile_success
			? DuelNativeCompactKernel::ActionOutcome::APPLIED
			: DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
		frame.stage = PowerChangeStage::COMPLETE;
		return;
	}

	int32_t target = -1;
	int32_t expected_owner = 0;
	if (frame.action.card_ref == DuelNativeCompactKernel::CardRefOpcode::SELECTED_CARD) {
		target = frame.action_context.selected_card_index;
		expected_owner = frame.action_context.selected_card_owner != 0
			? frame.action_context.selected_card_owner
			: frame.action_context.action_subject_owner;
	} else if (
		frame.action.card_ref == DuelNativeCompactKernel::CardRefOpcode::ABILITY_SOURCE
	) {
		target = frame.action_context.ability_source_card_index;
		expected_owner = frame.action_context.ability_source_owner;
	} else if (
		frame.action.card_ref == DuelNativeCompactKernel::CardRefOpcode::TRIGGER_CARD
	) {
		target = frame.event_context.trigger_card_index;
		expected_owner = frame.event_context.trigger_owner;
	} else if (
		frame.action.card_ref == DuelNativeCompactKernel::CardRefOpcode::ATTACKER_CARD
	) {
		target = frame.event_context.attacker_card_index;
		expected_owner = frame.event_context.attacker_owner;
	} else {
		frame.outcome = DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
		frame.stage = PowerChangeStage::COMPLETE;
		return;
	}
	int32_t zone = -1;
	int32_t owner = 0;
	int32_t logical_index = -1;
	if (
		target < 0
		|| !kernel.locate_card(state, target, zone, owner, logical_index)
		|| zone == 2
		|| (expected_owner != 0 && owner != expected_owner)
		|| !kernel.can_change_powers(state, target)
	) {
		frame.stage = PowerChangeStage::COMPLETE;
		return;
	}
	int32_t amount = frame.action.amount;
	if (frame.action.amount_is_hand_count) {
		int32_t count_owner = 0;
		if (
			frame.action.amount_owner
			== DuelNativeCompactKernel::RelativeOwnerOpcode::CARD_CURRENT
		) {
			count_owner = owner;
		} else if (
			frame.action.amount_owner
			== DuelNativeCompactKernel::RelativeOwnerOpcode::ABILITY_SOURCE
		) {
			int32_t source_zone = -1;
			int32_t source_index = -1;
			if (
				!kernel.locate_card(
					state,
					frame.action_context.ability_source_card_index,
					source_zone,
					count_owner,
					source_index
				)
				|| source_zone == 2
			) {
				frame.stage = PowerChangeStage::COMPLETE;
				return;
			}
		} else {
			frame.outcome = DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
			frame.stage = PowerChangeStage::COMPLETE;
			return;
		}
		amount = static_cast<int32_t>(state.zones[count_owner - 1].size());
	}
	if (amount == 0) {
		frame.outcome = frame.action.amount_is_hand_count
			? DuelNativeCompactKernel::ActionOutcome::NO_EFFECT
			: DuelNativeCompactKernel::ActionOutcome::UNSUPPORTED;
		frame.stage = PowerChangeStage::COMPLETE;
		return;
	}
	Array previous_powers;
	Array resulting_powers;
	bool all_zero = true;
	for (int32_t direction = 0; direction < 4; ++direction) {
		const int32_t previous = state.card_powers[target * 4 + direction];
		const int32_t resulting = std::max(0, previous + amount);
		previous_powers.append(previous);
		resulting_powers.append(resulting);
		state.card_powers[target * 4 + direction] = resulting;
		all_zero = all_zero && resulting == 0;
	}
	Dictionary event;
	event["type"] = StringName("powers_changed");
	event["source_cell"] = frame.source_cell;
	event["target_cell"] = zone == 0 ? logical_index : -1;
	event["owner_id"] = owner;
	event["instance_id"] = state.card_instance_ids[target];
	event["ability_source_instance_id"] =
		state.card_instance_ids[frame.group.source_card_index];
	event["previous_powers"] = previous_powers;
	event["powers"] = resulting_powers;
	event["amount"] = amount;
	event["change_reason"] = StringName("change_powers");
	event["zone"] = zone == 0
		? StringName("board")
		: (zone == 1
			? StringName("hand")
			: (zone == 3 ? StringName("discard") : StringName("removed")));
	event["logical_index"] = logical_index;
	frame.resolution->events.append(event);
	frame.outcome = DuelNativeCompactKernel::ActionOutcome::APPLIED;
	if (amount < 0 && all_zero) {
		frame.stage = PowerChangeStage::WAIT_EXILE;
		push_exile_frame(
			target,
			frame.source_cell,
			frame.group.source_card_index,
			target == frame.group.source_card_index,
			StringName("power_reached_zero"),
			frame.event_context,
			*frame.resolution,
			frame.action_context.record_direct_board_changes
		);
		return;
	}
	frame.stage = PowerChangeStage::COMPLETE;
}

void ResolutionEngine::step_transfer_resource_frame(
	DuelNativeCompactKernel::NativeState &state,
	std::vector<int32_t> &exile_stack
) {
	TransferResourceFrame &frame = resolution_frames.back()->transfer_resource;
	if (frame.stage == TransferResourceStage::COMPLETE || frame.resolution == nullptr) {
		complete_transfer_resource_frame();
		return;
	}
	if (frame.stage == TransferResourceStage::WAIT_DONOR_POWERS) {
		if (completed_power_change_outcome != DuelNativeCompactKernel::ActionOutcome::APPLIED) {
			frame.outcome = completed_power_change_outcome;
			frame.stage = TransferResourceStage::COMPLETE;
			return;
		}
		DuelNativeCompactKernel::CompiledAction receiver_action;
		receiver_action.opcode = DuelNativeCompactKernel::ActionOpcode::CHANGE_POWERS;
		receiver_action.card_ref = DuelNativeCompactKernel::CardRefOpcode::SELECTED_CARD;
		receiver_action.amount = frame.action.amount;
		DuelNativeCompactKernel::ActionContext receiver_context = frame.action_context;
		receiver_context.selected_card_index = frame.receiver;
		receiver_context.selected_card_owner = frame.receiver_owner;
		receiver_context.action_subject_owner = frame.receiver_owner;
		frame.stage = TransferResourceStage::WAIT_RECEIVER_POWERS;
		push_power_change_frame(
			frame.group,
			receiver_action,
			frame.event_context,
			receiver_context,
			frame.source_cell,
			*frame.resolution
		);
		return;
	}
	if (frame.stage == TransferResourceStage::WAIT_RECEIVER_POWERS) {
		frame.outcome = completed_power_change_outcome;
		frame.stage = TransferResourceStage::COMPLETE;
		return;
	}

	auto resolve_ref = [&](DuelNativeCompactKernel::CardRefOpcode reference) -> int32_t {
		if (reference == DuelNativeCompactKernel::CardRefOpcode::SELECTED_CARD) {
			return frame.action_context.selected_card_index;
		}
		if (reference == DuelNativeCompactKernel::CardRefOpcode::TRIGGER_CARD) {
			return frame.event_context.trigger_card_index;
		}
		if (reference == DuelNativeCompactKernel::CardRefOpcode::ABILITY_SOURCE) {
			return frame.action_context.ability_source_card_index;
		}
		if (reference == DuelNativeCompactKernel::CardRefOpcode::ATTACKER_CARD) {
			return frame.event_context.attacker_card_index;
		}
		return -1;
	};
	frame.donor = resolve_ref(frame.action.from_card_ref);
	frame.receiver = resolve_ref(frame.action.to_card_ref);
	if (frame.donor < 0 || frame.receiver < 0 || frame.donor == frame.receiver) {
		frame.stage = TransferResourceStage::COMPLETE;
		return;
	}
	int32_t donor_zone = -1;
	int32_t donor_index = -1;
	int32_t receiver_zone = -1;
	int32_t receiver_index = -1;
	if (
		!kernel.locate_card(
			state,
			frame.donor,
			donor_zone,
			frame.donor_owner,
			donor_index
		)
		|| !kernel.locate_card(
			state,
			frame.receiver,
			receiver_zone,
			frame.receiver_owner,
			receiver_index
		)
		|| donor_zone == 2
		|| receiver_zone == 2
	) {
		frame.stage = TransferResourceStage::COMPLETE;
		return;
	}
	auto can_donate = [&](DuelNativeCompactKernel::ResourceOpcode resource) -> bool {
		if (resource == DuelNativeCompactKernel::ResourceOpcode::KI) {
			return state.card_ki[frame.donor] >= frame.action.amount;
		}
		if (
			resource != DuelNativeCompactKernel::ResourceOpcode::POWERS
			|| !kernel.can_change_powers(state, frame.donor)
		) return false;
		for (int32_t direction = 0; direction < 4; ++direction) {
			if (state.card_powers[frame.donor * 4 + direction] > 0) return true;
		}
		return false;
	};
	auto can_receive = [&](DuelNativeCompactKernel::ResourceOpcode resource) -> bool {
		return resource == DuelNativeCompactKernel::ResourceOpcode::KI
			|| (
				resource == DuelNativeCompactKernel::ResourceOpcode::POWERS
				&& kernel.can_change_powers(state, frame.receiver)
			);
	};
	for (const DuelNativeCompactKernel::ResourceOpcode resource : {
		frame.action.resource,
		frame.action.fallback_resource,
	}) {
		if (!can_donate(resource)) continue;
		if (!can_receive(resource)) {
			frame.stage = TransferResourceStage::COMPLETE;
			return;
		}
		if (resource == DuelNativeCompactKernel::ResourceOpcode::KI) {
			DuelNativeCompactKernel::CompiledAction donor_action;
			donor_action.opcode = DuelNativeCompactKernel::ActionOpcode::SPEND_KI;
			donor_action.card_ref_explicit = true;
			donor_action.card_ref = DuelNativeCompactKernel::CardRefOpcode::SELECTED_CARD;
			donor_action.amount = frame.action.amount;
			donor_action.change_reason = StringName("transfer_card_resource");
			DuelNativeCompactKernel::ActionContext donor_context = frame.action_context;
			donor_context.selected_card_index = frame.donor;
			donor_context.selected_card_owner = frame.donor_owner;
			donor_context.action_subject_owner = frame.donor_owner;
			const DuelNativeCompactKernel::ActionOutcome donor_outcome = kernel.change_ki(
				state,
				frame.group,
				donor_action,
				frame.event_context,
				donor_context,
				frame.source_cell,
				exile_stack,
				*frame.resolution
			);
			if (donor_outcome != DuelNativeCompactKernel::ActionOutcome::APPLIED) {
				frame.outcome = donor_outcome;
				frame.stage = TransferResourceStage::COMPLETE;
				return;
			}
			DuelNativeCompactKernel::CompiledAction receiver_action = donor_action;
			receiver_action.opcode = DuelNativeCompactKernel::ActionOpcode::GAIN_KI;
			DuelNativeCompactKernel::ActionContext receiver_context = frame.action_context;
			receiver_context.selected_card_index = frame.receiver;
			receiver_context.selected_card_owner = frame.receiver_owner;
			receiver_context.action_subject_owner = frame.receiver_owner;
			frame.outcome = kernel.change_ki(
				state,
				frame.group,
				receiver_action,
				frame.event_context,
				receiver_context,
				frame.source_cell,
				exile_stack,
				*frame.resolution
			);
			frame.stage = TransferResourceStage::COMPLETE;
			return;
		}
		DuelNativeCompactKernel::CompiledAction donor_action;
		donor_action.opcode = DuelNativeCompactKernel::ActionOpcode::CHANGE_POWERS;
		donor_action.card_ref = DuelNativeCompactKernel::CardRefOpcode::SELECTED_CARD;
		donor_action.amount = -frame.action.amount;
		DuelNativeCompactKernel::ActionContext donor_context = frame.action_context;
		donor_context.selected_card_index = frame.donor;
		donor_context.selected_card_owner = frame.donor_owner;
		donor_context.action_subject_owner = frame.donor_owner;
		frame.stage = TransferResourceStage::WAIT_DONOR_POWERS;
		push_power_change_frame(
			frame.group,
			donor_action,
			frame.event_context,
			donor_context,
			frame.source_cell,
			*frame.resolution
		);
		return;
	}
	frame.stage = TransferResourceStage::COMPLETE;
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
			case RootStage::START: {
				frame.stage = RootStage::COMPLETE;
				if (frame.action.type != DuelNativeCompactKernel::NativeActionType::PLAY) {
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
				}
				const bool previous_payload_setting = kernel.include_presentation_payloads;
				kernel.include_presentation_payloads = frame.materialize_presentation_payloads;
				DuelNativeCompactKernel::SummonRequest summon_request;
				int32_t moving_owner = 0;
				int32_t played_card_index = -1;
				std::vector<int32_t> exile_stack;
				valid = kernel.prepare_play_transition(
					source,
					frame.action,
					next,
					resolution,
					supported,
					reason,
					summon_request,
					moving_owner,
					played_card_index,
					exile_stack
				);
				if (valid) {
					DuelNativeCompactKernel::Resolution summon_resolution = run_summon(
						next,
						summon_request,
						exile_stack
					);
					if (!summon_resolution.supported) {
						supported = false;
						reason = summon_resolution.reason;
						valid = false;
					} else {
						kernel.append_resolution(resolution, summon_resolution);
						DuelNativeCompactKernel::Resolution finish_resolution =
							kernel.finish_action(
								next,
								moving_owner,
								played_card_index,
								resolution.extra_play_requests,
								exile_stack
							);
						if (!finish_resolution.supported) {
							supported = false;
							reason = finish_resolution.reason;
							valid = false;
						} else {
							kernel.append_resolution(resolution, finish_resolution);
						}
					}
				}
				kernel.include_presentation_payloads = previous_payload_setting;
				break;
			}
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

DuelNativeCompactKernel::Resolution ResolutionEngine::run_summon(
	DuelNativeCompactKernel::NativeState &state,
	const DuelNativeCompactKernel::SummonRequest &request,
	std::vector<int32_t> &exile_stack
) {
	resolution_frames.clear();
	push_summon_frame(request);
	run_resolution_stack(state, exile_stack);
	return std::move(completed_summon_resolution);
}

DuelNativeCompactKernel::Resolution ResolutionEngine::run_attack(
	DuelNativeCompactKernel::NativeState &state,
	const DuelNativeCompactKernel::AttackRequest &request,
	std::vector<int32_t> &exile_stack
) {
	resolution_frames.clear();
	push_attack_frame(request);
	run_resolution_stack(state, exile_stack);
	return std::move(completed_attack_resolution);
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

Dictionary DuelNativeCompactKernel::resolve_summon_lifecycle_for_test(
	const Dictionary &request_value,
	bool iterative
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
	SummonRequest request;
	request.summon_cell = static_cast<int32_t>(
		static_cast<int64_t>(request_value.get("summon_cell", -1))
	);
	request.card_index = find_card_by_instance_id(
		next,
		StringName(request_value.get("instance_id", StringName()))
	);
	request.owner_id = static_cast<int32_t>(
		static_cast<int64_t>(request_value.get("owner_id", 0))
	);
	request.summon_reason = StringName(request_value.get(
		"summon_reason",
		StringName("test_summon")
	));
	request.attack_reason = StringName(request_value.get(
		"attack_reason",
		StringName("summon_standard_attack")
	));
	const Variant buffered_events = request_value.get("buffered_placement_events", Array());
	if (buffered_events.get_type() == Variant::ARRAY) {
		request.buffered_placement_events = buffered_events;
	}
	if (
		request.card_index < 0
		|| request.summon_cell < 0
		|| request.summon_cell >= static_cast<int32_t>(next.board_card_indices.size())
		|| request.owner_id < 1
		|| request.owner_id > 2
	) return materialize_direct_transition(next, Resolution(), true);
	std::vector<int32_t> exile_stack;
	Resolution resolution;
	if (iterative) {
		ResolutionEngine engine(*this);
		resolution = engine.run_summon(next, request, exile_stack);
	} else {
		resolution = resolve_summon_lifecycle(next, request, exile_stack);
	}
	return materialize_direct_transition(next, resolution, true);
}

Dictionary DuelNativeCompactKernel::resolve_attack_iterative_for_test(
	const Dictionary &request_value
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
	AttackRequest request;
	request.attacker_cell = static_cast<int32_t>(request_value.get("source_cell", -1));
	const StringName source_instance_id = StringName(
		request_value.get("source_instance_id", StringName())
	);
	request.attacker_card_index = find_card_by_instance_id(next, source_instance_id);
	if (
		source_instance_id.is_empty()
		&& request.attacker_card_index < 0
		&& request.attacker_cell >= 0
		&& request.attacker_cell < static_cast<int32_t>(next.board_card_indices.size())
	) request.attacker_card_index = next.board_card_indices[request.attacker_cell];
	request.attacker_owner = static_cast<int32_t>(
		request_value.get("source_owner_id", 0)
	);
	request.requested_policy = attack_policy_from_dictionary(
		request_value.get("attack_policy", Dictionary())
	);
	request.targeted = StringName(request_value.get("mode", StringName()))
		== StringName("targeted");
	request.locked_target_cell = static_cast<int32_t>(
		request_value.get("target_cell", -1)
	);
	const StringName target_instance_id = StringName(
		request_value.get("target_instance_id", StringName())
	);
	request.locked_target_card_index = find_card_by_instance_id(next, target_instance_id);
	if (
		target_instance_id.is_empty()
		&& request.locked_target_card_index < 0
		&& request.locked_target_cell >= 0
		&& request.locked_target_cell < static_cast<int32_t>(next.board_card_indices.size())
	) request.locked_target_card_index = next.board_card_indices[request.locked_target_cell];
	request.locked_target_owner = static_cast<int32_t>(
		request_value.get("target_owner_id", 0)
	);
	request.repeat_attack = bool(request_value.get("repeat_attack", false));
	request.reason = StringName(request_value.get(
		"reason",
		request.targeted
			? StringName("ability_targeted_attack")
			: StringName("ability_standard_attack")
	));
	if (
		request.attacker_card_index < 0
		|| request.attacker_owner < 1
		|| request.attacker_owner > 2
		|| (request.targeted && request.locked_target_card_index < 0)
	) return materialize_direct_transition(next, Resolution(), true);
	std::vector<int32_t> exile_stack;
	ResolutionEngine engine(*this);
	const Resolution resolution = engine.run_attack(next, request, exile_stack);
	return materialize_direct_transition(next, resolution, true);
}

} // namespace godot
