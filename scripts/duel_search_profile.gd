class_name DuelSearchProfile
extends RefCounted

const BASELINE: StringName = &"baseline"
const ENHANCED: StringName = &"enhanced"

const DEFAULT_TACTICAL_DEPTH: int = 2
const DEFAULT_TACTICAL_SCAN_LIMIT: int = 12
const DEFAULT_TACTICAL_ACTION_LIMIT: int = 4


static func normalize(limits: Dictionary = {}) -> Dictionary:
	var requested_name := StringName(limits.get("profile", ENHANCED))
	var requested_profile_valid: bool = requested_name in [BASELINE, ENHANCED]
	var profile_name: StringName = requested_name if requested_profile_valid else ENHANCED
	var is_enhanced: bool = profile_name == ENHANCED
	var normalized: Dictionary = {
		"name": profile_name,
		"requested_profile_valid": requested_profile_valid,
		"use_lazy_transitions": is_enhanced,
		"use_pvs": is_enhanced,
		"use_tactical_extension": is_enhanced,
		"use_evaluation_cache": false,
		"evaluator_profile": BASELINE,
		"max_tactical_depth": DEFAULT_TACTICAL_DEPTH if is_enhanced else 0,
		"tactical_scan_limit": DEFAULT_TACTICAL_SCAN_LIMIT if is_enhanced else 0,
		"tactical_action_limit": DEFAULT_TACTICAL_ACTION_LIMIT if is_enhanced else 0,
	}
	for flag: String in [
		"use_lazy_transitions",
		"use_pvs",
		"use_tactical_extension",
		"use_evaluation_cache",
	]:
		if limits.has(flag):
			normalized[flag] = bool(limits[flag])
	if limits.has("evaluator_profile"):
		var evaluator_profile := StringName(limits["evaluator_profile"])
		normalized["evaluator_profile"] = (
			evaluator_profile
			if evaluator_profile in [BASELINE, ENHANCED]
			else normalized["evaluator_profile"]
		)
	for integer_field: String in [
		"max_tactical_depth",
		"tactical_scan_limit",
		"tactical_action_limit",
	]:
		if limits.has(integer_field):
			normalized[integer_field] = maxi(int(limits[integer_field]), 0)
	if int(normalized["max_tactical_depth"]) == 0:
		normalized["use_tactical_extension"] = false
	return normalized
