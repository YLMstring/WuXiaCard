class_name DuelStateKey
extends RefCounted

const StateData = preload("res://scripts/duel_state.gd")


static func build(state: StateData) -> String:
	if state == null:
		return "nil"
	return _encode({
		"board": state.board,
		"hands": state.hands,
		"decks": state.decks,
		"discard_piles": state.discard_piles,
		"removed_cards": state.removed_cards,
		"active_player": state.active_player,
		"turn_count": state.turn_count,
		"owner_turn_serial": state.owner_turn_serial,
		"attacks_started_by_owner": state.attacks_started_by_owner,
		"extra_card_plays_remaining": state.extra_card_plays_remaining,
		"end_turn_triggers_resolved": state.end_turn_triggers_resolved,
		"max_turns": state.max_turns,
		"active_abilities": state.active_abilities,
		"effect_queue": state.effect_queue,
		"pending_choice": state.pending_choice,
		"repetition_hashes": state.repetition_hashes,
		"remembered_glyphs_by_owner": state.remembered_glyphs_by_owner,
		"future_draw_reveal_audiences": state.future_draw_reveal_audiences,
		"last_hand_play_by_owner": state.last_hand_play_by_owner,
		"pending_non_retained_suppression_by_owner": state.pending_non_retained_suppression_by_owner,
		"enabled_effect_gates_by_owner": state.enabled_effect_gates_by_owner,
		"run_difficulty": state.run_difficulty,
		"difficulty_eight_draw_consumed": state.difficulty_eight_draw_consumed,
	})


static func build_compact(state: StateData) -> String:
	var canonical: String = build(state)
	return "%d:%d:%d" % [canonical.length(), canonical.hash(), canonical.reverse().hash()]


static func _encode(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "z"
		TYPE_BOOL:
			return "b1" if bool(value) else "b0"
		TYPE_INT:
			return "i%s" % int(value)
		TYPE_FLOAT:
			return "f%s" % float(value)
		TYPE_STRING:
			return "s%s" % _encode_text(String(value))
		TYPE_STRING_NAME:
			return "n%s" % _encode_text(String(value))
		TYPE_ARRAY:
			var parts: Array[String] = []
			for item: Variant in value as Array:
				parts.append(_encode(item))
			return "a[%s]" % ",".join(parts)
		TYPE_DICTIONARY:
			var entries: Array[Dictionary] = []
			for key: Variant in (value as Dictionary).keys():
				entries.append({"key": _encode(key), "value": (value as Dictionary)[key]})
			entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
				return String(left["key"]) < String(right["key"])
			)
			var parts: Array[String] = []
			for entry: Dictionary in entries:
				parts.append("%s=%s" % [entry["key"], _encode(entry["value"])])
			return "d{%s}" % ",".join(parts)
		_:
			return "v%s:%s" % [typeof(value), _encode_text(str(value))]


static func _encode_text(value: String) -> String:
	var bytes: PackedByteArray = value.to_utf8_buffer()
	return "%d:%s" % [bytes.size(), bytes.hex_encode()]
