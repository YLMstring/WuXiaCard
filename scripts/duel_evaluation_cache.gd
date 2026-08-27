class_name DuelEvaluationCache
extends RefCounted

const Evaluator = preload("res://scripts/duel_evaluator.gd")
const StateData = preload("res://scripts/duel_state.gd")
const StateKey = preload("res://scripts/duel_state_key.gd")


static func lookup_or_evaluate(
	cache: Dictionary,
	state: StateData,
	root_owner: int,
	evaluator_profile: StringName
) -> Dictionary:
	var key: String = "%s|owner:%d|profile:%s" % [
		StateKey.build_compact(state),
		root_owner,
		String(evaluator_profile),
	]
	if cache.has(key):
		return {"score": int(cache[key]), "hit": true}
	var score: int = Evaluator.evaluate(state, root_owner, evaluator_profile)
	cache[key] = score
	return {"score": score, "hit": false}
