#include "duel_native_compact_kernel_internal.h"

namespace godot {
using namespace duel_native_internal;

// 本文件负责 Godot API 边界和一次动作的顶层路由：载入紧凑状态、校验调用参数、
// 复制根局面、调用纯原生规则，再把新状态与有序事件物化为 Dictionary。
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
		D_METHOD("get_board_defending_power_override_flags"),
		&DuelNativeCompactKernel::get_board_defending_power_override_flags
	);
	ClassDB::bind_method(
		D_METHOD("get_hand_play_danger_flags", "owner_id"),
		&DuelNativeCompactKernel::get_hand_play_danger_flags
	);
	ClassDB::bind_method(
		D_METHOD("count_legal_actions_for_owner", "owner_id"),
		&DuelNativeCompactKernel::count_legal_actions_for_owner
	);
	ClassDB::bind_method(
		D_METHOD("is_action_legal_for_owner", "action", "owner_id"),
		&DuelNativeCompactKernel::is_action_legal_for_owner
	);
	ClassDB::bind_method(
		D_METHOD("is_terminal_state"),
		&DuelNativeCompactKernel::is_terminal_state
	);
	ClassDB::bind_method(
		D_METHOD("score_difference_for_owner", "owner_id"),
		&DuelNativeCompactKernel::score_difference_for_owner
	);
	ClassDB::bind_method(
		D_METHOD("choose_greedy_action_for_owner", "owner_id"),
		&DuelNativeCompactKernel::choose_greedy_action_for_owner
	);
	ClassDB::bind_method(
		D_METHOD("get_attack_targets_for_source", "source_cell", "attack_policy"),
		&DuelNativeCompactKernel::get_attack_targets_for_source,
		DEFVAL(Dictionary())
	);
	ClassDB::bind_method(
		D_METHOD(
			"can_attack_target_cells",
			"source_cell",
			"target_cell",
			"attack_policy",
			"skip_power_comparison"
		),
		&DuelNativeCompactKernel::can_attack_target_cells,
		DEFVAL(Dictionary()),
		DEFVAL(false)
	);
	ClassDB::bind_method(
		D_METHOD(
			"is_target_in_attack_range_cells",
			"source_cell",
			"target_cell",
			"attack_policy",
			"skip_power_comparison"
		),
		&DuelNativeCompactKernel::is_target_in_attack_range_cells,
		DEFVAL(Dictionary()),
		DEFVAL(false)
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
		D_METHOD(
			"resolve_actions_transition",
			"source_cell",
			"source_instance_id",
			"expected_owner",
			"actions",
			"context"
		),
		&DuelNativeCompactKernel::resolve_actions_transition
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
	// 载入是 GDScript 与原生内核的信任边界：先复制并校验全部纯数据，随后一次性
	// 编译能力池。任一步失败都保持 loaded=false，避免搜索落入半编译状态。
	loaded = false;
	last_error = String();
	fresh_card_prototypes.clear();
	empty_deck_draw_prototype_index = -1;
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
	empty_deck_draw_prototype_index = static_cast<int32_t>(
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

	fresh_card_prototypes.clear();
	fresh_card_prototypes.reserve(
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
		for (const FreshCardPrototype &existing : fresh_card_prototypes) {
			if (existing.card_id == compiled.card_id) {
				last_error = "Fresh-card prototype IDs must be unique";
				return false;
			}
		}
		fresh_card_prototypes.push_back(compiled);
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
		for (std::vector<RuntimeOwnerAuraEntry> &auras : state.owner_auras) auras.clear();
		const Variant owner_auras_value = state.side_payload.get("owner_auras_by_owner", Dictionary());
		const Variant next_aura_handle_value = state.side_payload.get("next_owner_aura_handle", 1);
		if (
			owner_auras_value.get_type() != Variant::DICTIONARY
			|| next_aura_handle_value.get_type() != Variant::INT
			|| static_cast<int64_t>(next_aura_handle_value) < 1
		) {
			last_error = "Owner aura runtime state has an invalid shape";
			loaded = false;
		} else {
			state.next_owner_aura_handle = static_cast<uint64_t>(
				static_cast<int64_t>(next_aura_handle_value)
			);
			const Dictionary owner_auras = owner_auras_value;
			std::unordered_set<uint64_t> aura_handles;
			for (int32_t owner_id = 1; loaded && owner_id <= 2; ++owner_id) {
				const Variant entries_value = owner_auras.get(owner_id, Array());
				if (entries_value.get_type() != Variant::ARRAY) {
					last_error = "Owner aura list is not an Array";
					loaded = false;
					break;
				}
				const Array entries = entries_value;
				state.owner_auras[owner_id - 1].reserve(static_cast<size_t>(entries.size()));
				for (int64_t entry_index = 0; entry_index < entries.size(); ++entry_index) {
					const Variant entry_value = entries[entry_index];
					if (entry_value.get_type() != Variant::DICTIONARY) {
						last_error = "Owner aura entry is not a Dictionary";
						loaded = false;
						break;
					}
					const Dictionary entry = entry_value;
					const Variant handle_value = entry.get("handle", Variant());
					const Variant source_value = entry.get("source_instance_id", Variant());
					const Variant aura_value = entry.get("aura", Variant());
					if (
						entry.size() != 3
						|| handle_value.get_type() != Variant::INT
						|| static_cast<int64_t>(handle_value) < 1
						|| (source_value.get_type() != Variant::STRING_NAME && source_value.get_type() != Variant::STRING)
						|| aura_value.get_type() != Variant::DICTIONARY
					) {
						last_error = "Owner aura entry has an invalid declaration shape";
						loaded = false;
						break;
					}
					const uint64_t handle = static_cast<uint64_t>(static_cast<int64_t>(handle_value));
					if (!aura_handles.insert(handle).second || handle >= state.next_owner_aura_handle) {
						last_error = "Owner aura handle is duplicated or outside the next-handle range";
						loaded = false;
						break;
					}
					const StringName source_instance_id = source_value;
					int32_t source_card_index = -1;
					for (size_t card_index = 0; card_index < state.card_instance_ids.size(); ++card_index) {
						if (state.card_instance_ids[card_index] == source_instance_id) {
							source_card_index = static_cast<int32_t>(card_index);
							break;
						}
					}
					if (source_card_index < 0) {
						last_error = "Owner aura source instance is unknown";
						loaded = false;
						break;
					}
					RuntimeOwnerAuraEntry compiled_entry;
					compiled_entry.handle = handle;
					compiled_entry.source_card_index = source_card_index;
					compiled_entry.compiled_ability_index = intern_compiled_ability(aura_value, true);
					if (!compiled_ability_pool[compiled_entry.compiled_ability_index].declaration_valid) {
						last_error = "Owner aura declaration is unsupported";
						loaded = false;
						break;
					}
					state.owner_auras[owner_id - 1].push_back(compiled_entry);
				}
			}
		}
		if (loaded) loaded = compile_runtime_suppression_batches();
		if (loaded) {
			for (size_t ability_index = 0; ability_index < compiled_ability_pool.size(); ++ability_index) {
				if (compiled_ability_pool[ability_index].declaration_valid) continue;
				last_error = String("Unsupported compiled ability declaration at index ")
					+ String::num_int64(static_cast<int64_t>(ability_index));
				loaded = false;
				break;
			}
		}
		if (loaded) {
			for (size_t set_index = 0; set_index < compiled_ability_sets.size(); ++set_index) {
				if (compiled_ability_sets[set_index].declaration_valid) continue;
				last_error = String("Unsupported compiled ability-set declaration at index ")
					+ String::num_int64(static_cast<int64_t>(set_index));
				loaded = false;
				break;
			}
		}
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
		fresh_card_prototypes.size()
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
	// 手牌下标只用于本次输入校验；真正身份由稳定 card_index/instance_id 追踪。
	// 这样固定手牌槽出现空洞时，也不会把视觉顺序误当成运行时顺序。
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
	{
		// 大数组由 C++ 值语义复制；仍含可变嵌套 Variant 的两个字段必须显式隔离，
		// 否则搜索子节点会反向污染父局面。
		ScopedTransitionTiming timing(
			active_transition_timing,
			TransitionTimingBucket::STATE_COPY
		);
		next = source;
		next.board_slot_extras = source.board_slot_extras.duplicate(true);
		next.side_payload = source.side_payload.duplicate(true);
	}
	if (next.scalars[5] > 0) {
		next.scalars[13] = 1;
		next.scalars[5] -= 1;
	}
	std::vector<int32_t> &next_hand = next.zones[hand_zone_index];
	next_hand.erase(next_hand.begin() + hand_index);
	next.card_runtime_flags[played_card_index] &= static_cast<uint8_t>(~(1 << 7));
	next.card_hand_slots[played_card_index] = -1;
	add_reveal_observer(next.card_reveal_codes[played_card_index], moving_owner);
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
	Resolution suppression_resolution = consume_pending_hand_play_suppression(
		next,
		played_card_index,
		moving_owner,
		static_cast<int32_t>(target_cell)
	);
	append_resolution(resolution, suppression_resolution);

	SummonRequest summon_request;
	// 普通出牌先静态落位，再统一进入 summon 生命周期。重定向来源在进场时快照，
	// 真正攻击前仍会确认来源实例仍在场、相邻、敌对且能力有效。
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
	result.exile_effect_source_owner = static_cast<int32_t>(context.get(
		"exile_effect_source_owner_id",
		0
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
	result.attack_flipped_any_card = bool(context.get("attack_flipped_any_card", false));
	const Variant used_directions_value = context.get("used_attacker_power_directions", Variant());
	if (used_directions_value.get_type() == Variant::INT) {
		result.used_attacker_power_directions = static_cast<uint8_t>(
			static_cast<int64_t>(used_directions_value) & 0x0f
		);
	} else if (used_directions_value.get_type() == Variant::ARRAY) {
		const Array used_directions = used_directions_value;
		for (int64_t index = 0; index < used_directions.size(); ++index) {
			const int32_t direction = static_cast<int32_t>(static_cast<int64_t>(used_directions[index]));
			if (direction >= 0 && direction < 4) {
				result.used_attacker_power_directions |= static_cast<uint8_t>(1 << direction);
			}
		}
	}
	result.attack_reason = StringName(context.get("attack_reason", StringName()));
	result.flip_reason = StringName(context.get("flip_reason", StringName()));
	result.exile_reason = StringName(context.get("exile_reason", StringName()));
	result.discard_batch_id = StringName(context.get("discard_batch_id", StringName()));
	result.power_increase_owner_zone_mask = static_cast<uint8_t>(
		static_cast<int64_t>(context.get("power_increase_owner_zone_mask", 0)) & 0xff
	);

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

Dictionary DuelNativeCompactKernel::resolve_actions_transition(
	int64_t source_cell_value,
	const StringName &source_instance_id,
	int64_t expected_owner_value,
	const Array &actions,
	const Dictionary &context
) {
	if (!loaded) {
		Resolution resolution;
		resolution.supported = false;
		return materialize_direct_transition(state, resolution, false, "No compact state is loaded");
	}
	std::vector<CompiledAction> compiled_actions;
	compiled_actions.reserve(static_cast<size_t>(actions.size()));
	for (int64_t index = 0; index < actions.size(); ++index) {
		CompiledAction action = compile_action(actions[index]);
		if (!action.declaration_valid) {
			Resolution resolution;
			resolution.supported = false;
			return materialize_direct_transition(
				state,
				resolution,
				false,
				"Direct action declaration is unsupported"
			);
		}
		compiled_actions.push_back(std::move(action));
	}

	NativeState next = state;
	next.board_slot_extras = state.board_slot_extras.duplicate(true);
	next.side_payload = state.side_payload.duplicate(true);
	EventGroup group;
	group.source_cell = static_cast<int32_t>(source_cell_value);
	group.source_card_index = find_card_by_instance_id(next, source_instance_id);
	group.source_owner = static_cast<int32_t>(expected_owner_value);
	if (group.source_card_index >= 0) {
		int32_t logical_index = -1;
		locate_card(
			next,
			group.source_card_index,
			group.source_zone,
			group.source_owner,
			logical_index
		);
		group.source_logical_index = logical_index;
		if (group.source_zone == 0) group.source_cell = logical_index;
	}

	const EventContext event_context = event_context_from_dictionary(next, context);
	ActionContext action_context;
	action_context.ability_source_cell = group.source_cell;
	action_context.ability_source_zone = group.source_zone;
	action_context.ability_source_logical_index = group.source_logical_index;
	action_context.ability_source_card_index = group.source_card_index;
	action_context.ability_source_owner = group.source_owner;
	action_context.action_subject_card_index = group.source_card_index;
	action_context.action_subject_owner = group.source_owner;
	action_context.action_subject_zone = group.source_zone;
	action_context.action_subject_logical_index = group.source_logical_index;
	action_context.trigger_card_index = event_context.trigger_card_index;
	action_context.attacker_card_index = event_context.attacker_card_index;
	action_context.activation_target_kind = StringName(context.get(
		"activation_target_kind",
		context.get("target_kind", StringName())
	));
	action_context.activation_target_index = static_cast<int32_t>(context.get(
		"activation_target_index",
		context.get("target_index", -1)
	));
	action_context.event_id = StringName(context.get("event_id", StringName()));
	action_context.attack_flips = event_context.attack_flips;
	action_context.selected_card_index = find_card_by_instance_id(
		next,
		StringName(context.get("selected_card_instance_id", StringName()))
	);
	if (action_context.selected_card_index >= 0) {
		locate_card(
			next,
			action_context.selected_card_index,
			action_context.selected_card_zone,
			action_context.selected_card_owner,
			action_context.selected_card_logical_index
		);
	}

	std::vector<int32_t> exile_stack;
	Resolution resolution;
	const ActionOutcome outcome = execute_actions(
		next,
		group,
		compiled_actions,
		event_context,
		action_context,
		exile_stack,
		resolution
	);
	if (outcome == ActionOutcome::UNSUPPORTED) resolution.supported = false;
	Dictionary result = materialize_direct_transition(next, resolution, true);
	result["source_cell"] = group.source_cell;
	result["result"] = outcome == ActionOutcome::APPLIED
		? StringName("applied")
		: (outcome == ActionOutcome::INVALID_CONTEXT
			? StringName("invalid_context")
			: StringName("no_effect"));
	return result;
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
	const int32_t new_owner = static_cast<int32_t>(new_owner_value);
	std::vector<int32_t> exile_stack;
	const ActionOutcome outcome = resolve_non_attack_flip(
		next,
		target_card_index,
		new_owner,
		reason,
		true,
		exile_stack,
		resolution
	);
	return materialize_direct_transition(
		next,
		resolution,
		outcome != ActionOutcome::UNSUPPORTED
	);
}

bool DuelNativeCompactKernel::transition_activate(
	const NativeState &source,
	const NativeAction &action,
	NativeState &next,
	Resolution &resolution,
	bool &supported,
	String &reason
) const {
	// 主动能力是一次完整行动；额外出牌阶段只能继续出牌，不能夹入主动能力。
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
	// activation_index 只枚举当前仍带主动能力的条目；ability_handle 则跨越 vector
	// 换位保持身份，用于后续能力可能被前序效果删除的情况。
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

	{
		ScopedTransitionTiming timing(
			active_transition_timing,
			TransitionTimingBucket::STATE_COPY
		);
		next = source;
		next.board_slot_extras = source.board_slot_extras.duplicate(true);
		next.side_payload = source.side_payload.duplicate(true);
	}
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
	// 费用先完整结算，再结算正文。费用途中移除来源也不会回滚已经支付的内容；
	// 后续 action 是否有效由各原语自己的上下文规则决定。
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
	bool materialize_presentation_payloads,
	NativeSearchStats *search_stats
) const {
	// 玩家、测试模式、贪心回退和深度搜索全部从这里进入同一套规则。搜索可以省略
	// UI 专用嵌套载荷，但不能省略会影响语义、状态键或后续触发的事件骨架。
	const bool previous_include_presentation_payloads = include_presentation_payloads;
	TransitionTimingContext timing_context;
	TransitionTimingContext *previous_transition_timing = active_transition_timing;
	if (search_stats != nullptr) {
		timing_context.begin();
		active_transition_timing = &timing_context;
	}
	include_presentation_payloads = materialize_presentation_payloads;
	bool valid = false;
	if (action.type == NativeActionType::PLAY) {
		valid = transition_play(source, action, next, resolution, supported, reason);
	} else {
		valid = transition_activate(source, action, next, resolution, supported, reason);
	}
	include_presentation_payloads = previous_include_presentation_payloads;
	if (search_stats != nullptr) {
		timing_context.finish();
		search_stats->time_apply_nsec += timing_context.total_nsec();
		for (size_t bucket = 0; bucket < timing_context.elapsed_nsec.size(); ++bucket) {
			search_stats->time_apply_bucket_nsec[bucket] += timing_context.elapsed_nsec[bucket];
			search_stats->time_apply_bucket_entries[bucket] += timing_context.entries[bucket];
		}
	}
	active_transition_timing = previous_transition_timing;
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
