#include "duel_native_compact_kernel_internal.h"

namespace godot {
using namespace duel_native_internal;

void DuelNativeCompactKernel::_bind_methods() {
	ClassDB::bind_method(
		D_METHOD("load_compact_payload", "payload"),
		&DuelNativeCompactKernel::load_compact_payload
	);
	ClassDB::bind_method(D_METHOD("is_loaded"), &DuelNativeCompactKernel::is_loaded);
	ClassDB::bind_method(D_METHOD("get_last_error"), &DuelNativeCompactKernel::get_last_error);
	ClassDB::bind_method(D_METHOD("inspect_layout"), &DuelNativeCompactKernel::inspect_layout);
	ClassDB::bind_method(
		D_METHOD("benchmark_core_clone", "iterations"),
		&DuelNativeCompactKernel::benchmark_core_clone
	);
	ClassDB::bind_method(
		D_METHOD(
			"apply_play_transition",
			"hand_index",
			"target_cell",
			"expected_instance_id"
		),
		&DuelNativeCompactKernel::apply_play_transition,
		DEFVAL(StringName())
	);
	ClassDB::bind_method(
		D_METHOD("get_legal_actions_for_owner", "owner_id"),
		&DuelNativeCompactKernel::get_legal_actions_for_owner
	);
	ClassDB::bind_method(
		D_METHOD("count_legal_actions_for_owner", "owner_id"),
		&DuelNativeCompactKernel::count_legal_actions_for_owner
	);
	ClassDB::bind_method(
		D_METHOD(
			"inspect_ordered_search_actions_for_owner",
			"owner_id",
			"preferred_action"
		),
		&DuelNativeCompactKernel::inspect_ordered_search_actions_for_owner,
		DEFVAL(Dictionary())
	);
	ClassDB::bind_method(
		D_METHOD("inspect_history_keys_for_owner", "owner_id"),
		&DuelNativeCompactKernel::inspect_history_keys_for_owner
	);
	ClassDB::bind_method(
		D_METHOD(
			"inspect_history_score_policy",
			"initial_score",
			"remaining_owner_turn_boundaries",
			"cutoff_updates",
			"public_depth_decays"
		),
		&DuelNativeCompactKernel::inspect_history_score_policy
	);
	ClassDB::bind_method(
		D_METHOD("inspect_transposition_table_layout", "capacity_mib"),
		&DuelNativeCompactKernel::inspect_transposition_table_layout
	);
	ClassDB::bind_method(
		D_METHOD(
			"inspect_evaluation",
			"root_owner",
			"include_deck_evaluation",
			"include_danger_evaluation",
			"include_tempo_evaluation"
		),
		&DuelNativeCompactKernel::inspect_evaluation,
		DEFVAL(false),
		DEFVAL(false),
		DEFVAL(false)
	);
	ClassDB::bind_method(
		D_METHOD(
			"apply_activate_transition",
			"source_cell",
			"target_kind",
			"target_index",
			"activation_index",
			"expected_instance_id"
		),
		&DuelNativeCompactKernel::apply_activate_transition,
		DEFVAL(0),
		DEFVAL(StringName())
	);
	ClassDB::bind_method(
		D_METHOD("resolve_event_transition", "event_id", "context"),
		&DuelNativeCompactKernel::resolve_event_transition
	);
	ClassDB::bind_method(
		D_METHOD("resolve_attack_transition", "request"),
		&DuelNativeCompactKernel::resolve_attack_transition
	);
	ClassDB::bind_method(
		D_METHOD(
			"resolve_non_attack_flip_transition",
			"target_instance_id",
			"new_owner",
			"reason"
		),
		&DuelNativeCompactKernel::resolve_non_attack_flip_transition,
		DEFVAL(StringName("non_attack_flip"))
	);
	ClassDB::bind_method(
		D_METHOD("search_fixed_round_depth", "root_owner", "round_depth"),
		&DuelNativeCompactKernel::search_fixed_round_depth
	);
	ClassDB::bind_method(
		D_METHOD("search_fixed_depth", "root_owner", "depth", "depth_mode"),
		&DuelNativeCompactKernel::search_fixed_depth
	);
	ClassDB::bind_method(
		D_METHOD(
			"search_iterative_round_depth",
			"root_owner",
			"max_round_depth",
			"budget_usec",
			"max_nodes",
			"min_completed_depth",
			"should_cancel",
			"on_progress",
			"use_internal_pv_ordering",
			"use_history_ordering",
			"collect_search_diagnostics",
			"use_transposition_table",
			"transposition_table_mib",
			"include_deck_evaluation",
			"include_danger_evaluation",
			"include_tempo_evaluation"
		),
		&DuelNativeCompactKernel::search_iterative_round_depth,
		DEFVAL(Callable()),
		DEFVAL(false),
		DEFVAL(false),
		DEFVAL(false),
		DEFVAL(false),
		DEFVAL(0),
		DEFVAL(false),
		DEFVAL(false),
		DEFVAL(false)
	);
	ClassDB::bind_method(
		D_METHOD(
			"search_iterative_depth",
			"root_owner",
			"max_depth",
			"budget_usec",
			"max_nodes",
			"min_completed_depth",
			"depth_mode",
			"should_cancel",
			"on_progress",
			"use_internal_pv_ordering",
			"use_history_ordering",
			"collect_search_diagnostics",
			"use_transposition_table",
			"transposition_table_mib",
			"include_deck_evaluation",
			"include_danger_evaluation",
			"include_tempo_evaluation"
		),
		&DuelNativeCompactKernel::search_iterative_depth,
		DEFVAL(Callable()),
		DEFVAL(false),
		DEFVAL(false),
		DEFVAL(false),
		DEFVAL(false),
		DEFVAL(0),
		DEFVAL(false),
		DEFVAL(false),
		DEFVAL(false)
	);
}

bool DuelNativeCompactKernel::load_compact_payload(const Dictionary &payload) {
	loaded = false;
	last_error = String();
	if (static_cast<int64_t>(payload.get("format_version", 0)) != 1) {
		last_error = "Unsupported compact-state format version";
		return false;
	}

	state.scalars = to_int_vector(payload.get("scalars", PackedInt32Array()));
	state.board_card_indices = to_int_vector(
		payload.get("board_card_indices", PackedInt32Array())
	);
	state.board_owners = to_byte_vector(payload.get("board_owners", PackedByteArray()));
	state.card_template_indices = to_int_vector(
		payload.get("card_template_indices", PackedInt32Array())
	);
	state.card_runtime_flags = to_byte_vector(
		payload.get("card_runtime_flags", PackedByteArray())
	);
	state.card_powers = to_int_vector(payload.get("card_powers", PackedInt32Array()));
	state.card_original_owners = to_byte_vector(
		payload.get("card_original_owners", PackedByteArray())
	);
	state.card_ki = to_int_vector(payload.get("card_ki", PackedInt32Array()));
	state.card_active_ability_set_indices = to_int_vector(
		payload.get("card_active_ability_set_indices", PackedInt32Array())
	);
	state.card_reveal_codes = to_byte_vector(
		payload.get("card_reveal_codes", PackedByteArray())
	);
	state.card_suppression_set_indices = to_int_vector(
		payload.get("card_suppression_set_indices", PackedInt32Array())
	);
	state.card_hand_slots = to_int_vector(
		payload.get("card_hand_slots", PackedInt32Array())
	);
	state.board_slot_extras = payload.get("board_slot_extras", Array());
	state.card_template_pool = payload.get("card_template_pool", Array());
	state.active_ability_set_pool = payload.get("active_ability_set_pool", Array());
	state.suppression_set_pool = payload.get("suppression_set_pool", Array());
	const Variant fresh_prototypes_value = payload.get("fresh_card_prototypes", Array());
	if (fresh_prototypes_value.get_type() != Variant::ARRAY) {
		last_error = "Fresh-card prototype pool is not an Array";
		return false;
	}
	state.fresh_card_prototype_pool = fresh_prototypes_value;
	const Variant fallback_index_value = payload.get("empty_deck_draw_prototype_index", -1);
	if (fallback_index_value.get_type() != Variant::INT) {
		last_error = "Empty-deck fallback prototype index is not an integer";
		return false;
	}
	state.empty_deck_draw_prototype_index = static_cast<int32_t>(
		static_cast<int64_t>(fallback_index_value)
	);
	state.side_payload = payload.get("side_payload", Dictionary());
	state.has_rule_metadata = (
		payload.has("card_template_pool")
		&& payload.has("active_ability_set_pool")
		&& payload.has("suppression_set_pool")
	);

	state.card_instance_ids.clear();
	const Array instance_ids = payload.get("card_instance_ids", Array());
	state.card_instance_ids.reserve(static_cast<size_t>(instance_ids.size()));
	for (int64_t index = 0; index < instance_ids.size(); ++index) {
		state.card_instance_ids.push_back(instance_ids[index]);
	}

	state.zones.clear();
	const Array zones = payload.get("zones", Array());
	state.zones.reserve(static_cast<size_t>(zones.size()));
	for (int64_t index = 0; index < zones.size(); ++index) {
		state.zones.push_back(to_int_vector(zones[index]));
	}

	state.fresh_card_prototypes.clear();
	state.fresh_card_prototypes.reserve(
		static_cast<size_t>(state.fresh_card_prototype_pool.size())
	);
	for (int64_t index = 0; index < state.fresh_card_prototype_pool.size(); ++index) {
		const Variant prototype_value = state.fresh_card_prototype_pool[index];
		if (prototype_value.get_type() != Variant::DICTIONARY) {
			last_error = "Fresh-card prototype pool contains a non-Dictionary value";
			return false;
		}
		const Dictionary prototype = prototype_value;
		const Variant powers_value = prototype.get("powers", Variant());
		if (
			prototype.size() != 5
			|| Variant(prototype.get("card_id", Variant())).get_type() != Variant::STRING_NAME
			|| Variant(prototype.get("template_index", Variant())).get_type() != Variant::INT
			|| powers_value.get_type() != Variant::ARRAY
			|| Variant(prototype.get("ki", Variant())).get_type() != Variant::INT
			|| Variant(prototype.get("active_ability_set_index", Variant())).get_type() != Variant::INT
		) {
			last_error = "Fresh-card prototype has an invalid declaration shape";
			return false;
		}
		const Array powers = powers_value;
		if (powers.size() != 4) {
			last_error = "Fresh-card prototype must have exactly four powers";
			return false;
		}
		FreshCardPrototype compiled;
		compiled.card_id = prototype.get("card_id", StringName());
		compiled.template_index = static_cast<int32_t>(
			static_cast<int64_t>(prototype.get("template_index", -1))
		);
		for (int32_t direction = 0; direction < 4; ++direction) {
			if (Variant(powers[direction]).get_type() != Variant::INT) {
				last_error = "Fresh-card prototype power is not an integer";
				return false;
			}
			compiled.powers[direction] = static_cast<int32_t>(
				static_cast<int64_t>(powers[direction])
			);
		}
		compiled.ki = static_cast<int32_t>(static_cast<int64_t>(prototype.get("ki", 0)));
		compiled.active_ability_set_index = static_cast<int32_t>(
			static_cast<int64_t>(prototype.get("active_ability_set_index", -1))
		);
		for (const FreshCardPrototype &existing : state.fresh_card_prototypes) {
			if (existing.card_id == compiled.card_id) {
				last_error = "Fresh-card prototype IDs must be unique";
				return false;
			}
		}
		state.fresh_card_prototypes.push_back(compiled);
	}

	state.card_ids.clear();
	state.card_ids.resize(state.card_instance_ids.size());
	if (state.has_rule_metadata) {
		for (size_t card_index = 0; card_index < state.card_template_indices.size(); ++card_index) {
			const int32_t template_index = state.card_template_indices[card_index];
			if (template_index < 0 || template_index >= state.card_template_pool.size()) {
				continue;
			}
			const Variant template_value = state.card_template_pool[template_index];
			if (template_value.get_type() != Variant::DICTIONARY) {
				continue;
			}
			const Dictionary card_template = template_value;
			state.card_ids[card_index] = card_template.get("card_id", StringName());
		}
	}

	loaded = validate_shape();
	if (loaded) {
		compile_ability_sets();
		state.next_ability_handle = 1;
		state.card_runtime_abilities.clear();
		state.card_runtime_abilities.reserve(state.card_instance_ids.size());
		for (size_t card_index = 0; card_index < state.card_instance_ids.size(); ++card_index) {
			const int32_t set_index = state.card_active_ability_set_indices[card_index];
			const std::vector<int32_t> *ability_indices = (
				set_index >= 0 && set_index < static_cast<int32_t>(compiled_ability_sets.size())
				? &compiled_ability_sets[set_index].ability_pool_indices
				: nullptr
			);
			std::vector<RuntimeAbilityEntry> runtime_entries;
			if (ability_indices != nullptr) {
				runtime_entries.reserve(ability_indices->size());
				for (const int32_t compiled_index : *ability_indices) {
					RuntimeAbilityEntry entry;
					entry.compiled_ability_index = compiled_index;
					entry.handle = state.next_ability_handle++;
					runtime_entries.push_back(entry);
				}
			}
			state.card_runtime_abilities.push_back(runtime_entries);
		}
		loaded = compile_runtime_suppression_batches();
	}
	return loaded;
}

bool DuelNativeCompactKernel::is_loaded() const {
	return loaded;
}

String DuelNativeCompactKernel::get_last_error() const {
	return last_error;
}

Dictionary DuelNativeCompactKernel::inspect_layout() const {
	Dictionary result;
	result["loaded"] = loaded;
	result["last_error"] = last_error;
	result["scalar_count"] = static_cast<int64_t>(state.scalars.size());
	result["board_cell_count"] = static_cast<int64_t>(state.board_card_indices.size());
	result["zone_count"] = static_cast<int64_t>(state.zones.size());
	result["card_count"] = static_cast<int64_t>(state.card_instance_ids.size());
	result["power_count"] = static_cast<int64_t>(state.card_powers.size());
	result["compiled_ability_set_count"] = static_cast<int64_t>(
		compiled_ability_sets.size()
	);
	int64_t invalid_ability_count = 0;
	Array invalid_ability_declarations;
	Array invalid_ability_diagnostics;
	for (size_t index = 0; index < compiled_ability_pool.size(); ++index) {
		if (!compiled_ability_pool[index].declaration_valid) {
			++invalid_ability_count;
			if (index < ability_declaration_pool.size()) {
				invalid_ability_declarations.append(ability_declaration_pool[index]);
			}
			const CompiledAbility &ability = compiled_ability_pool[index];
			Dictionary diagnostic;
			diagnostic["pool_index"] = static_cast<int64_t>(index);
			diagnostic["activation_valid"] = ability.activation.declaration_valid;
			Array modifier_opcodes;
			for (const CompiledModifier &modifier : ability.modifiers) {
				modifier_opcodes.append(static_cast<int64_t>(modifier.opcode));
			}
			diagnostic["modifier_opcodes"] = modifier_opcodes;
			Array trigger_diagnostics;
			for (const CompiledTriggerRule &trigger : ability.triggers) {
				Dictionary trigger_diagnostic;
				trigger_diagnostic["event"] = trigger.event_id;
				Array condition_opcodes;
				for (const CompiledCondition &condition : trigger.conditions) {
					condition_opcodes.append(static_cast<int64_t>(condition.opcode));
				}
				trigger_diagnostic["condition_opcodes"] = condition_opcodes;
				Array action_diagnostics;
				for (const CompiledAction &action : trigger.actions) {
					Dictionary action_diagnostic;
					action_diagnostic["type"] = action.declaration_type;
					action_diagnostic["opcode"] = static_cast<int64_t>(action.opcode);
					action_diagnostic["valid"] = action.declaration_valid;
					action_diagnostic["selector_valid"] = action.selector.declaration_valid;
					Array child_diagnostics;
					for (const CompiledAction &child : action.child_actions) {
						Dictionary child_diagnostic;
						child_diagnostic["type"] = child.declaration_type;
						child_diagnostic["opcode"] = static_cast<int64_t>(child.opcode);
						child_diagnostic["valid"] = child.declaration_valid;
						child_diagnostic["granted_ability_index"] = child.granted_ability_index;
						child_diagnostics.append(child_diagnostic);
					}
					action_diagnostic["children"] = child_diagnostics;
					action_diagnostics.append(action_diagnostic);
				}
				trigger_diagnostic["actions"] = action_diagnostics;
				trigger_diagnostics.append(trigger_diagnostic);
			}
			diagnostic["triggers"] = trigger_diagnostics;
			invalid_ability_diagnostics.append(diagnostic);
		}
	}
	int64_t invalid_ability_set_count = 0;
	Array invalid_ability_set_indices;
	for (size_t index = 0; index < compiled_ability_sets.size(); ++index) {
		if (!compiled_ability_sets[index].declaration_valid) {
			++invalid_ability_set_count;
			invalid_ability_set_indices.append(static_cast<int64_t>(index));
		}
	}
	result["compiled_ability_count"] = static_cast<int64_t>(compiled_ability_pool.size());
	result["invalid_compiled_ability_count"] = invalid_ability_count;
	result["invalid_compiled_ability_set_count"] = invalid_ability_set_count;
	result["invalid_compiled_ability_declarations"] = invalid_ability_declarations;
	result["invalid_compiled_ability_diagnostics"] = invalid_ability_diagnostics;
	result["invalid_compiled_ability_set_indices"] = invalid_ability_set_indices;
	result["fresh_card_prototype_count"] = static_cast<int64_t>(
		state.fresh_card_prototypes.size()
	);
	result["checksum"] = static_cast<int64_t>(checksum(state) & 0x7fffffffffffffffULL);
	return result;
}


Dictionary DuelNativeCompactKernel::apply_play_transition(
	int64_t hand_index,
	int64_t target_cell,
	const StringName &expected_instance_id
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
	NativeAction action;
	action.type = NativeActionType::PLAY;
	action.source_index = static_cast<int32_t>(hand_index);
	action.source_instance_id = expected_instance_id;
	action.target_index = static_cast<int32_t>(target_cell);
	NativeState next;
	Resolution resolution;
	bool supported = false;
	String reason;
	const bool valid = transition_play(
		state,
		action,
		next,
		resolution,
		supported,
		reason
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

bool DuelNativeCompactKernel::transition_play(
	const NativeState &source,
	const NativeAction &action,
	NativeState &next,
	Resolution &resolution,
	bool &supported,
	String &reason
) const {
	supported = false;
	reason = String();
	if (!validate_play_support(source, reason)) return false;
	supported = true;
	const int32_t hand_index = action.source_index;
	const int32_t target_cell = action.target_index;
	const int32_t moving_owner = source.scalars[0];
	const int32_t hand_zone_index = moving_owner - 1;
	if (hand_zone_index < 0 || hand_zone_index >= static_cast<int32_t>(source.zones.size())) {
		reason = "Active owner has no compact hand zone";
		return false;
	}
	const std::vector<int32_t> &source_hand = source.zones[hand_zone_index];
	if (hand_index < 0 || hand_index >= static_cast<int32_t>(source_hand.size())) {
		reason = "Hand index is outside the active owner's hand";
		return false;
	}
	if (target_cell < 0 || target_cell >= static_cast<int32_t>(source.board_card_indices.size())) {
		reason = "Target cell is outside the board";
		return false;
	}
	if (source.board_card_indices[static_cast<size_t>(target_cell)] != -1) {
		reason = "Target board cell is occupied";
		return false;
	}
	const int32_t played_card_index = source_hand[static_cast<size_t>(hand_index)];
	if (played_card_index < 0 || played_card_index >= static_cast<int32_t>(source.card_instance_ids.size())) {
		reason = "Hand references an invalid card index";
		return false;
	}
	const StringName played_instance_id = source.card_instance_ids[played_card_index];
	if (!action.source_instance_id.is_empty() && action.source_instance_id != played_instance_id) {
		reason = "Expected instance ID does not match the hand card";
		return false;
	}
	const NativeState *support_state = &source;
	NativeState pending_adjusted_state;
	const int32_t pending_scalar_index = moving_owner == 1 ? 8 : 9;
	if (
		source.scalars[pending_scalar_index] > 0
		&& !card_is_heart_method(source, played_card_index)
	) {
		pending_adjusted_state = source;
		std::vector<RuntimeAbilityEntry> retained_entries;
		for (const RuntimeAbilityEntry &entry : pending_adjusted_state.card_runtime_abilities[played_card_index]) {
			if (
				entry.compiled_ability_index >= 0
				&& entry.compiled_ability_index < static_cast<int32_t>(compiled_ability_pool.size())
				&& compiled_ability_pool[entry.compiled_ability_index].retained_on_flip
			) retained_entries.push_back(entry);
		}
		pending_adjusted_state.card_runtime_abilities[played_card_index] = retained_entries;
		clear_runtime_suppression(pending_adjusted_state, played_card_index);
		support_state = &pending_adjusted_state;
	}
	if (!validate_action_rule_support(
			*support_state,
			played_card_index,
			target_cell,
			reason
		)) {
		supported = false;
		return false;
	}

	next = source;
	next.board_slot_extras = source.board_slot_extras.duplicate(true);
	next.side_payload = source.side_payload.duplicate(true);
	if (next.scalars[5] > 0) {
		next.scalars[13] = 1;
		next.scalars[5] -= 1;
	}
	std::vector<int32_t> &next_hand = next.zones[hand_zone_index];
	next_hand.erase(next_hand.begin() + hand_index);
	next.card_runtime_flags[played_card_index] &= static_cast<uint8_t>(~(1 << 7));
	next.card_hand_slots[played_card_index] = -1;
	if (moving_owner == 1) {
		if (next.card_reveal_codes[played_card_index] == 0) {
			next.card_reveal_codes[played_card_index] = 1;
		} else if (next.card_reveal_codes[played_card_index] == 2) {
			next.card_reveal_codes[played_card_index] = 4;
		}
	} else if (moving_owner == 2) {
		if (next.card_reveal_codes[played_card_index] == 0) {
			next.card_reveal_codes[played_card_index] = 2;
		} else if (next.card_reveal_codes[played_card_index] == 1) {
			next.card_reveal_codes[played_card_index] = 3;
		}
	}
	next.board_card_indices[static_cast<size_t>(target_cell)] = played_card_index;
	next.board_owners[static_cast<size_t>(target_cell)] = static_cast<uint8_t>(moving_owner);
	if (target_cell < next.board_slot_extras.size()) {
		next.board_slot_extras[target_cell] = Dictionary();
	}

	resolution = Resolution();
	std::vector<int32_t> exile_stack;
	Dictionary placed_event;
	placed_event["type"] = StringName("card_placed");
	placed_event["source_cell"] = target_cell;
	placed_event["target_cell"] = target_cell;
	placed_event["owner_id"] = moving_owner;
	placed_event["instance_id"] = played_instance_id;
	Resolution hand_change_resolution = resolve_difficulty_hand_change(
		next,
		moving_owner,
		static_cast<int32_t>(source_hand.size()),
		static_cast<int32_t>(next_hand.size()),
		static_cast<int32_t>(target_cell),
		exile_stack
	);
	if (!hand_change_resolution.supported) {
		supported = false;
		reason = hand_change_resolution.reason;
		return false;
	}
	const Array hand_change_events = hand_change_resolution.events;
	hand_change_resolution.events = Array();
	append_resolution(resolution, hand_change_resolution);
	Resolution suppression_resolution = consume_pending_hand_play_suppression(
		next,
		played_card_index,
		moving_owner,
		static_cast<int32_t>(target_cell)
	);
	append_resolution(resolution, suppression_resolution);

	SummonRequest summon_request;
	summon_request.summon_cell = static_cast<int32_t>(target_cell);
	summon_request.card_index = played_card_index;
	summon_request.owner_id = moving_owner;
	summon_request.summon_reason = StringName("hand_play");
	summon_request.attack_reason = StringName("summon_standard_attack");
	summon_request.attack_redirect_source_card_indices =
		snapshot_summon_attack_redirect_sources(
			next,
			static_cast<int32_t>(target_cell),
			moving_owner
		);
	summon_request.attack_redirect_snapshot_taken = true;
	summon_request.buffered_placement_events.append(placed_event);
	summon_request.buffered_placement_events.append_array(hand_change_events);
	Resolution summon_resolution = resolve_summon_lifecycle(
		next,
		summon_request,
		exile_stack
	);
	if (!summon_resolution.supported) {
		supported = false;
		reason = summon_resolution.reason;
		return false;
	}
	append_resolution(resolution, summon_resolution);

	Resolution finish_resolution = finish_action(
		next,
		moving_owner,
		played_card_index,
		resolution.extra_play_requests,
		exile_stack
	);
	if (!finish_resolution.supported) {
		supported = false;
		reason = finish_resolution.reason;
		return false;
	}
	append_resolution(resolution, finish_resolution);
	return true;
}

Dictionary DuelNativeCompactKernel::apply_activate_transition(
	int64_t source_cell_value,
	const StringName &target_kind,
	int64_t target_index_value,
	int64_t activation_index_value,
	const StringName &expected_instance_id
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
	NativeAction action;
	action.type = NativeActionType::ACTIVATE;
	action.source_index = static_cast<int32_t>(source_cell_value);
	action.source_instance_id = expected_instance_id;
	action.target_is_hand_slot = target_kind == StringName("hand_slot");
	action.target_index = static_cast<int32_t>(target_index_value);
	action.activation_index = static_cast<int32_t>(activation_index_value);
	NativeState next;
	Resolution resolution;
	bool supported = false;
	String reason;
	const bool valid = transition_activate(
		state,
		action,
		next,
		resolution,
		supported,
		reason
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

int32_t DuelNativeCompactKernel::find_card_by_instance_id(
	const NativeState &value,
	const StringName &instance_id
) const {
	if (instance_id.is_empty()) return -1;
	for (size_t index = 0; index < value.card_instance_ids.size(); ++index) {
		if (value.card_instance_ids[index] == instance_id) {
			return static_cast<int32_t>(index);
		}
	}
	return -1;
}

DuelNativeCompactKernel::AttackPolicy DuelNativeCompactKernel::attack_policy_from_dictionary(
	const Dictionary &value
) const {
	AttackPolicy policy;
	const StringName target_policy = value.get(
		"attack_target_policy",
		StringName("enemies_only")
	);
	if (target_policy == StringName("allies_only")) {
		policy.target_policy = AttackTargetPolicy::ALLIES_ONLY;
	} else if (target_policy == StringName("all")) {
		policy.target_policy = AttackTargetPolicy::ALL;
	} else {
		policy.target_policy = AttackTargetPolicy::ENEMIES_ONLY;
	}
	policy.capture_owner_id = static_cast<int32_t>(value.get("capture_owner_id", 0));
	policy.specified = value.has("attack_target_policy") || value.has("capture_owner_id");
	return policy;
}

DuelNativeCompactKernel::EventContext DuelNativeCompactKernel::event_context_from_dictionary(
	const NativeState &value,
	const Dictionary &context
) const {
	EventContext result;
	auto zone_kind = [](const StringName &zone) -> int32_t {
		if (zone == StringName("board")) return 0;
		if (zone == StringName("hand")) return 1;
		if (zone == StringName("deck")) return 2;
		if (zone == StringName("discard")) return 3;
		if (zone == StringName("removed")) return 4;
		return -1;
	};
	auto card_from = [&](const char *key) -> int32_t {
		return find_card_by_instance_id(value, StringName(context.get(key, StringName())));
	};

	result.ability_source_cell = static_cast<int32_t>(context.get("ability_source_cell", -1));
	result.ability_source_card_index = card_from("ability_source_instance_id");
	result.ability_source_owner = static_cast<int32_t>(context.get("ability_source_owner_id", 0));
	result.ability_source_zone = zone_kind(StringName(context.get("ability_source_zone", StringName())));
	result.ability_source_logical_index = static_cast<int32_t>(context.get("ability_source_logical_index", -1));
	if (result.ability_source_card_index >= 0) {
		int32_t located_zone = -1;
		int32_t located_owner = 0;
		int32_t located_index = -1;
		if (locate_card(value, result.ability_source_card_index, located_zone, located_owner, located_index)) {
			if (result.ability_source_zone < 0) result.ability_source_zone = located_zone;
			if (result.ability_source_owner == 0) result.ability_source_owner = located_owner;
			if (result.ability_source_logical_index < 0) result.ability_source_logical_index = located_index;
			if (result.ability_source_cell < 0 && located_zone == 0) result.ability_source_cell = located_index;
		}
	}

	result.trigger_cell = static_cast<int32_t>(context.get("trigger_cell", -1));
	result.trigger_card_index = card_from("trigger_instance_id");
	if (
		result.trigger_card_index < 0
		&& result.trigger_cell >= 0
		&& result.trigger_cell < static_cast<int32_t>(value.board_card_indices.size())
	) result.trigger_card_index = value.board_card_indices[result.trigger_cell];
	result.trigger_owner = static_cast<int32_t>(context.get("trigger_owner_id", 0));
	result.trigger_previous_owner = static_cast<int32_t>(context.get(
		"trigger_previous_owner_id",
		result.trigger_owner
	));
	result.trigger_zone = zone_kind(StringName(context.get("trigger_zone", StringName())));
	result.trigger_logical_index = static_cast<int32_t>(context.get("trigger_logical_index", -1));
	if (result.trigger_card_index >= 0) {
		int32_t located_zone = -1;
		int32_t located_owner = 0;
		int32_t located_index = -1;
		if (locate_card(value, result.trigger_card_index, located_zone, located_owner, located_index)) {
			if (result.trigger_zone < 0) result.trigger_zone = located_zone;
			if (result.trigger_owner == 0) result.trigger_owner = located_owner;
			if (result.trigger_previous_owner == 0) result.trigger_previous_owner = result.trigger_owner;
			if (result.trigger_logical_index < 0) result.trigger_logical_index = located_index;
			if (result.trigger_cell < 0 && located_zone == 0) result.trigger_cell = located_index;
		}
	}
	result.trigger_was_on_board = bool(context.get(
		"trigger_was_on_board",
		result.trigger_zone == 0 || result.trigger_cell >= 0
	));

	result.attacker_cell = static_cast<int32_t>(context.get("attacker_cell", -1));
	result.attacker_card_index = card_from("attacker_instance_id");
	if (
		result.attacker_card_index < 0
		&& result.attacker_cell >= 0
		&& result.attacker_cell < static_cast<int32_t>(value.board_card_indices.size())
	) result.attacker_card_index = value.board_card_indices[result.attacker_cell];
	result.attacker_owner = static_cast<int32_t>(context.get("attacker_owner_id", 0));
	if (
		result.attacker_owner == 0
		&& result.attacker_cell >= 0
		&& result.attacker_cell < static_cast<int32_t>(value.board_owners.size())
	) result.attacker_owner = value.board_owners[result.attacker_cell];

	result.attacked_cell = static_cast<int32_t>(context.get("attacked_cell", -1));
	result.attacked_card_index = card_from("attacked_instance_id");
	if (
		result.attacked_card_index < 0
		&& result.attacked_cell >= 0
		&& result.attacked_cell < static_cast<int32_t>(value.board_card_indices.size())
	) result.attacked_card_index = value.board_card_indices[result.attacked_cell];
	result.attacked_owner = static_cast<int32_t>(context.get("attacked_owner_id", 0));
	if (
		result.attacked_owner == 0
		&& result.attacked_cell >= 0
		&& result.attacked_cell < static_cast<int32_t>(value.board_owners.size())
	) result.attacked_owner = value.board_owners[result.attacked_cell];

	result.new_owner = static_cast<int32_t>(context.get("new_owner_id", 0));
	result.previous_ki = static_cast<int32_t>(context.get("previous_ki", 0));
	result.ki = static_cast<int32_t>(context.get("ki", -1));
	result.moving_source_cell = static_cast<int32_t>(context.get("moving_source_cell", -1));
	result.moving_origin_cell = static_cast<int32_t>(context.get("moving_origin_cell", result.moving_source_cell));
	result.moving_target_cell = static_cast<int32_t>(context.get("moving_target_cell", -1));
	result.moving_card_index = card_from("moving_instance_id");
	result.moving_owner = static_cast<int32_t>(context.get("moving_owner_id", 0));
	result.discard_owner = static_cast<int32_t>(context.get("discard_owner_id", 0));
	result.discard_batch_size = static_cast<int32_t>(context.get("discard_batch_size", 0));
	result.turn_owner = static_cast<int32_t>(context.get("turn_owner_id", 0));
	result.activation_owner = static_cast<int32_t>(context.get("activation_owner_id", 0));
	result.activation_source_cell = static_cast<int32_t>(context.get("activation_source_cell", -1));
	result.activation_source_card_index = card_from("activation_source_instance_id");
	if (
		result.activation_source_card_index < 0
		&& result.activation_source_cell >= 0
		&& result.activation_source_cell < static_cast<int32_t>(value.board_card_indices.size())
	) result.activation_source_card_index = value.board_card_indices[result.activation_source_cell];
	result.activation_target_kind = StringName(context.get("activation_target_kind", StringName()));
	result.activation_target_index = static_cast<int32_t>(context.get("activation_target_index", -1));
	result.repeat_attack = bool(context.get("repeat_attack", false));
	result.attack_flipped_enemy = bool(context.get("attack_flipped_enemy", false));
	result.attack_reason = StringName(context.get("attack_reason", StringName()));
	result.flip_reason = StringName(context.get("flip_reason", StringName()));
	result.exile_reason = StringName(context.get("exile_reason", StringName()));
	result.discard_batch_id = StringName(context.get("discard_batch_id", StringName()));

	const Array winning_owners = context.get("winning_owner_ids", Array());
	for (int64_t index = 0; index < winning_owners.size(); ++index) {
		result.winning_owners.push_back(static_cast<int32_t>(winning_owners[index]));
	}
	const Array attack_flips = context.get("attack_flips", Array());
	for (int64_t index = 0; index < attack_flips.size(); ++index) {
		if (attack_flips[index].get_type() != Variant::DICTIONARY) continue;
		const Dictionary record = attack_flips[index];
		EventContext::AttackFlipRecord converted;
		converted.card_index = find_card_by_instance_id(
			value,
			StringName(record.get("instance_id", StringName()))
		);
		converted.previous_owner = static_cast<int32_t>(record.get("previous_owner_id", 0));
		if (converted.card_index >= 0) result.attack_flips.push_back(converted);
	}
	return result;
}

Dictionary DuelNativeCompactKernel::materialize_direct_transition(
	const NativeState &value,
	const Resolution &resolution,
	bool valid,
	const String &reason
) const {
	Dictionary result;
	result["supported"] = resolution.supported;
	result["valid"] = valid && resolution.supported;
	result["reason"] = !reason.is_empty() ? reason : resolution.reason;
	result["captures"] = resolution.captures;
	result["exiles"] = resolution.exiles;
	result["events"] = resolution.events;
	if (valid && resolution.supported) result["payload"] = to_variant_payload(value);
	return result;
}

Dictionary DuelNativeCompactKernel::resolve_event_transition(
	const StringName &event_id,
	const Dictionary &context
) const {
	if (!loaded) {
		Resolution resolution;
		resolution.supported = false;
		return materialize_direct_transition(state, resolution, false, "No compact state is loaded");
	}
	NativeState next = state;
	next.board_slot_extras = state.board_slot_extras.duplicate(true);
	next.side_payload = state.side_payload.duplicate(true);
	std::vector<int32_t> exile_stack;
	const Resolution resolution = resolve_event(
		next,
		event_id,
		event_context_from_dictionary(next, context),
		exile_stack
	);
	return materialize_direct_transition(next, resolution, true);
}

Dictionary DuelNativeCompactKernel::resolve_attack_transition(const Dictionary &request) const {
	if (!loaded) {
		Resolution resolution;
		resolution.supported = false;
		return materialize_direct_transition(state, resolution, false, "No compact state is loaded");
	}
	NativeState next = state;
	next.board_slot_extras = state.board_slot_extras.duplicate(true);
	next.side_payload = state.side_payload.duplicate(true);
	AttackRequest native_request;
	native_request.attacker_cell = static_cast<int32_t>(request.get("source_cell", -1));
	const StringName source_instance_id = StringName(request.get("source_instance_id", StringName()));
	native_request.attacker_card_index = find_card_by_instance_id(
		next,
		source_instance_id
	);
	if (
		source_instance_id.is_empty()
		&&
		native_request.attacker_card_index < 0
		&& native_request.attacker_cell >= 0
		&& native_request.attacker_cell < static_cast<int32_t>(next.board_card_indices.size())
	) native_request.attacker_card_index = next.board_card_indices[native_request.attacker_cell];
	native_request.attacker_owner = static_cast<int32_t>(request.get("source_owner_id", 0));
	native_request.requested_policy = attack_policy_from_dictionary(
		request.get("attack_policy", Dictionary())
	);
	native_request.targeted = StringName(request.get("mode", StringName())) == StringName("targeted");
	native_request.locked_target_cell = static_cast<int32_t>(request.get("target_cell", -1));
	const StringName target_instance_id = StringName(request.get("target_instance_id", StringName()));
	native_request.locked_target_card_index = find_card_by_instance_id(
		next,
		target_instance_id
	);
	if (
		target_instance_id.is_empty()
		&&
		native_request.locked_target_card_index < 0
		&& native_request.locked_target_cell >= 0
		&& native_request.locked_target_cell < static_cast<int32_t>(next.board_card_indices.size())
	) native_request.locked_target_card_index = next.board_card_indices[native_request.locked_target_cell];
	native_request.locked_target_owner = static_cast<int32_t>(request.get("target_owner_id", 0));
	native_request.repeat_attack = bool(request.get("repeat_attack", false));
	native_request.reason = StringName(request.get(
		"reason",
		native_request.targeted
			? StringName("ability_targeted_attack")
			: StringName("ability_standard_attack")
	));
	if (
		native_request.attacker_card_index < 0
		|| native_request.attacker_owner < 1
		|| native_request.attacker_owner > 2
		|| (native_request.targeted && native_request.locked_target_card_index < 0)
	) {
		return materialize_direct_transition(next, Resolution(), true);
	}
	std::vector<int32_t> exile_stack;
	const Resolution resolution = resolve_attack_request(next, native_request, exile_stack);
	return materialize_direct_transition(next, resolution, true);
}

Dictionary DuelNativeCompactKernel::resolve_non_attack_flip_transition(
	const StringName &target_instance_id,
	int64_t new_owner_value,
	const StringName &reason
) const {
	if (!loaded) {
		Resolution resolution;
		resolution.supported = false;
		return materialize_direct_transition(state, resolution, false, "No compact state is loaded");
	}
	NativeState next = state;
	next.board_slot_extras = state.board_slot_extras.duplicate(true);
	next.side_payload = state.side_payload.duplicate(true);
	Resolution resolution;
	const int32_t target_card_index = find_card_by_instance_id(next, target_instance_id);
	const int32_t target_cell = find_board_card(next, target_card_index);
	const int32_t new_owner = static_cast<int32_t>(new_owner_value);
	if (
		target_cell < 0
		|| (new_owner != 1 && new_owner != 2)
		|| next.board_owners[target_cell] == new_owner
	) return materialize_direct_transition(next, resolution, true);

	std::vector<int32_t> exile_stack;
	EventContext flip_context;
	flip_context.trigger_cell = target_cell;
	flip_context.trigger_card_index = target_card_index;
	flip_context.trigger_owner = next.board_owners[target_cell];
	flip_context.trigger_previous_owner = flip_context.trigger_owner;
	flip_context.trigger_zone = 0;
	flip_context.trigger_logical_index = target_cell;
	flip_context.trigger_was_on_board = true;
	flip_context.new_owner = new_owner;
	flip_context.flip_reason = reason;
	Resolution before = resolve_event(
		next,
		StringName("card_before_flipped"),
		flip_context,
		exile_stack
	);
	if (!before.supported) return materialize_direct_transition(next, before, false);
	append_resolution(resolution, before);
	if (before.flip_prevented) {
		Dictionary prevented;
		prevented["type"] = StringName("card_flip_prevented");
		prevented["source_cell"] = -1;
		prevented["target_cell"] = target_cell;
		prevented["owner_id"] = flip_context.trigger_owner;
		prevented["new_owner_id"] = new_owner;
		prevented["instance_id"] = target_instance_id;
		resolution.events.append(prevented);
		Resolution after_prevented = resolve_event(
			next,
			StringName("card_flip_prevented"),
			flip_context,
			exile_stack
		);
		append_resolution(resolution, after_prevented);
		return materialize_direct_transition(next, resolution, true);
	}
	Resolution flipped;
	if (!flip_card(
		next,
		-1,
		-1,
		target_cell,
		target_card_index,
		new_owner,
		flip_context,
		exile_stack,
		flipped
	)) {
		return materialize_direct_transition(next, flipped, false);
	}
	append_resolution(resolution, flipped);
	return materialize_direct_transition(next, resolution, true);
}

bool DuelNativeCompactKernel::transition_activate(
	const NativeState &source,
	const NativeAction &action,
	NativeState &next,
	Resolution &resolution,
	bool &supported,
	String &reason
) const {
	supported = false;
	reason = String();
	if (!validate_play_support(source, reason)) return false;
	supported = true;
	if (source.scalars[5] > 0) {
		reason = "Activation is unavailable during an extra card play";
		return false;
	}
	const int32_t moving_owner = source.scalars[0];
	const int32_t source_cell = action.source_index;
	const int32_t target_index = action.target_index;
	const int32_t requested_activation_index = action.activation_index;
	if (source_cell < 0 || source_cell >= static_cast<int32_t>(source.board_card_indices.size())) {
		reason = "Activation source cell is outside the board";
		return false;
	}
	const int32_t source_card_index = source.board_card_indices[source_cell];
	if (source_card_index < 0 || source.board_owners[source_cell] != moving_owner) {
		reason = "Activation source is not owned by the active player";
		return false;
	}
	if (
		!action.source_instance_id.is_empty()
		&& source.card_instance_ids[source_card_index] != action.source_instance_id
	) {
		reason = "Expected instance ID does not match the activation source";
		return false;
	}
	if (!card_effects_enabled(source, source_card_index, moving_owner)) {
		reason = "Activation source effects are disabled";
		return false;
	}

	const CompiledAbility *ability = nullptr;
	int32_t runtime_ability_index = -1;
	uint64_t ability_handle = 0;
	int32_t current_activation_index = 0;
	for (
		size_t ability_index = 0;
		ability_index < source.card_runtime_abilities[source_card_index].size();
		++ability_index
	) {
		const CompiledAbility *candidate = runtime_ability(
			source,
			source_card_index,
			static_cast<int32_t>(ability_index)
		);
		if (candidate == nullptr || !candidate->has_activation) continue;
		if (current_activation_index == requested_activation_index) {
			ability = candidate;
			runtime_ability_index = static_cast<int32_t>(ability_index);
			ability_handle = source.card_runtime_abilities[source_card_index][ability_index].handle;
			break;
		}
		++current_activation_index;
	}
	if (ability == nullptr || requested_activation_index < 0) {
		reason = "Activation index is no longer available";
		return false;
	}
	if (!ability->activation.declaration_valid) {
		supported = false;
		reason = "Activation declaration is not supported by the native kernel";
		return false;
	}
	const CompiledActivation &activation = ability->activation;
	if (!can_pay_activation_cost(source, source_card_index, activation)) {
		reason = "Activation cost cannot be paid";
		return false;
	}
	const bool expected_hand_slot = activation_targets_hand(activation);
	if (action.target_is_hand_slot != expected_hand_slot) {
		reason = "Activation target kind does not match its declaration";
		return false;
	}
	const std::vector<int32_t> target_indices = get_activation_target_indices(
		source,
		moving_owner,
		source_cell,
		activation
	);
	if (std::find(target_indices.begin(), target_indices.end(), target_index) == target_indices.end()) {
		reason = "Activation target is no longer legal";
		return false;
	}

	int32_t selected_card_index = -1;
	int32_t selected_card_owner = 0;
	if (!action.target_is_hand_slot) {
		selected_card_index = source.board_card_indices[target_index];
		if (selected_card_index >= 0) selected_card_owner = source.board_owners[target_index];
	} else {
		selected_card_owner = activation.target_rule == TargetRuleOpcode::ENEMY_HAND_CARD
			? other_owner(moving_owner)
			: moving_owner;
		selected_card_index = source.zones[selected_card_owner - 1][target_index];
	}

	next = source;
	next.board_slot_extras = source.board_slot_extras.duplicate(true);
	next.side_payload = source.side_payload.duplicate(true);
	resolution = Resolution();
	std::vector<int32_t> exile_stack;
	Dictionary activated;
	activated["type"] = StringName("ability_activated");
	activated["source_cell"] = source_cell;
	activated["target_cell"] = target_index;
	activated["owner_id"] = moving_owner;
	activated["instance_id"] = source.card_instance_ids[source_card_index];
	resolution.events.append(activated);

	EventGroup group;
	group.source_cell = source_cell;
	group.source_zone = 0;
	group.source_logical_index = source_cell;
	group.source_card_index = source_card_index;
	group.source_owner = moving_owner;
	group.ability_index = runtime_ability_index;
	group.ability_handle = ability_handle;
	ActionContext action_context;
	action_context.ability_source_cell = source_cell;
	action_context.ability_source_zone = 0;
	action_context.ability_source_logical_index = source_cell;
	action_context.ability_source_card_index = source_card_index;
	action_context.ability_source_owner = moving_owner;
	action_context.action_subject_card_index = source_card_index;
	action_context.action_subject_owner = moving_owner;
	action_context.action_subject_zone = 0;
	action_context.action_subject_logical_index = source_cell;
	action_context.selected_card_index = selected_card_index;
	action_context.selected_card_owner = selected_card_owner;
	action_context.selected_card_zone = action.target_is_hand_slot ? 1 : 0;
	action_context.selected_card_logical_index = target_index;
	action_context.activation_target_kind = action.target_is_hand_slot
		? StringName("hand_slot")
		: StringName("board_cell");
	action_context.activation_target_index = target_index;
	action_context.record_direct_board_changes = false;
	EventContext activation_context;
	activation_context.ability_source_cell = source_cell;
	activation_context.ability_source_zone = 0;
	activation_context.ability_source_logical_index = source_cell;
	activation_context.ability_source_card_index = source_card_index;
	activation_context.ability_source_owner = moving_owner;
	activation_context.activation_owner = moving_owner;
	activation_context.activation_source_cell = source_cell;
	activation_context.activation_source_card_index = source_card_index;
	activation_context.activation_target_kind = action_context.activation_target_kind;
	activation_context.activation_target_index = target_index;

	const ActionOutcome cost_outcome = execute_actions(
		next,
		group,
		activation.costs,
		activation_context,
		action_context,
		exile_stack,
		resolution
	);
	if (cost_outcome == ActionOutcome::UNSUPPORTED) {
		supported = false;
		reason = resolution.reason.is_empty()
			? String("Activation cost reached unsupported native behavior")
			: resolution.reason;
		return false;
	}
	const ActionOutcome action_outcome = execute_actions(
		next,
		group,
		activation.actions,
		activation_context,
		action_context,
		exile_stack,
		resolution
	);
	if (action_outcome == ActionOutcome::UNSUPPORTED) {
		supported = false;
		reason = resolution.reason.is_empty()
			? String("Activation action reached unsupported native behavior")
			: resolution.reason;
		return false;
	}

	EventContext after_context;
	after_context.activation_owner = moving_owner;
	after_context.activation_source_cell = find_board_card(
		next,
		source_card_index,
		source_cell
	);
	after_context.activation_source_card_index = source_card_index;
	after_context.activation_target_kind = action_context.activation_target_kind;
	after_context.activation_target_index = target_index;
	Resolution after_activation = resolve_event(
		next,
		StringName("card_after_targeted_activation"),
		after_context,
		exile_stack
	);
	if (!after_activation.supported) {
		supported = false;
		reason = after_activation.reason;
		return false;
	}
	append_resolution(resolution, after_activation);

	Resolution finish_resolution = finish_action(
		next,
		moving_owner,
		-1,
		resolution.extra_play_requests,
		exile_stack
	);
	if (!finish_resolution.supported) {
		supported = false;
		reason = finish_resolution.reason;
		return false;
	}
	append_resolution(resolution, finish_resolution);
	return true;
}

bool DuelNativeCompactKernel::transition_action(
	const NativeState &source,
	const NativeAction &action,
	NativeState &next,
	Resolution &resolution,
	bool &supported,
	String &reason,
	bool materialize_presentation_payloads
) const {
	const bool previous_include_presentation_payloads = include_presentation_payloads;
	include_presentation_payloads = materialize_presentation_payloads;
	bool valid = false;
	if (action.type == NativeActionType::PLAY) {
		valid = transition_play(source, action, next, resolution, supported, reason);
	} else {
		valid = transition_activate(source, action, next, resolution, supported, reason);
	}
	include_presentation_payloads = previous_include_presentation_payloads;
	return valid;
}


Dictionary DuelNativeCompactKernel::benchmark_core_clone(int64_t iterations) const {
	Dictionary result;
	if (!loaded || iterations <= 0) {
		result["valid"] = false;
		result["iterations"] = iterations;
		result["elapsed_usec"] = 0;
		result["sink"] = 0;
		return result;
	}

	uint64_t sink = 0;
	const auto started = std::chrono::steady_clock::now();
	for (int64_t iteration = 0; iteration < iterations; ++iteration) {
		NativeState copied = state;
		if (!copied.scalars.empty()) {
			copied.scalars[0] ^= static_cast<int32_t>(iteration & 1);
			sink ^= static_cast<uint64_t>(copied.scalars[0]);
		}
		sink ^= static_cast<uint64_t>(copied.card_powers.size() + copied.card_instance_ids.size());
	}
	const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(
		std::chrono::steady_clock::now() - started
	);
	result["valid"] = true;
	result["iterations"] = iterations;
	result["elapsed_usec"] = static_cast<int64_t>(elapsed.count());
	result["sink"] = static_cast<int64_t>(sink & 0x7fffffffffffffffULL);
	return result;
}


} // namespace godot
