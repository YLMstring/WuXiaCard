class_name DeckRules
extends RefCounted

const Catalog = preload("res://scripts/card_catalog.gd")

const WANDERER_SECT: String = "江湖"


static func get_glyph(card_id: StringName) -> String:
	if card_id == &"" or not Catalog.has_card(card_id):
		return ""
	return String(Catalog.get_definition(card_id).get("glyph", ""))


static func has_unique_glyphs(card_ids: Array) -> bool:
	var observed: Dictionary = {}
	for value: Variant in card_ids:
		var card_id := StringName(String(value))
		if card_id == &"":
			continue
		var glyph: String = get_glyph(card_id)
		if glyph.is_empty() or observed.has(glyph):
			return false
		observed[glyph] = true
	return true


static func is_main_deck_complete(main_deck: Array, capacity: int = 5) -> bool:
	if main_deck.size() != capacity:
		return false
	for value: Variant in main_deck:
		if String(value).is_empty():
			return false
	return true


static func find_first_empty_deck_slot(main_deck: Array) -> int:
	for index: int in range(main_deck.size()):
		if String(main_deck[index]).is_empty():
			return index
	return -1


static func find_deck_glyph_slot(main_deck: Array, glyph: String) -> int:
	if glyph.is_empty():
		return -1
	for index: int in range(main_deck.size()):
		if get_glyph(StringName(String(main_deck[index]))) == glyph:
			return index
	return -1


static func build_player_add(
	main_deck: Array,
	library_slots: Array,
	library_index: int
) -> Dictionary:
	if library_index < 0 or library_index >= library_slots.size():
		return {"ok": false}
	var incoming_id := StringName(String(library_slots[library_index]))
	var incoming_glyph: String = get_glyph(incoming_id)
	if incoming_glyph.is_empty():
		return {"ok": false}
	var deck_index: int = find_deck_glyph_slot(main_deck, incoming_glyph)
	if deck_index < 0:
		deck_index = find_first_empty_deck_slot(main_deck)
	if deck_index < 0:
		return {"ok": false, "reason": &"full"}
	return build_player_replace_at(
		main_deck,
		library_slots,
		library_index,
		deck_index
	)


static func build_player_remove(
	main_deck: Array,
	library_slots: Array,
	deck_index: int
) -> Dictionary:
	if deck_index < 0 or deck_index >= main_deck.size():
		return {"ok": false}
	var removed_id := StringName(String(main_deck[deck_index]))
	if get_glyph(removed_id).is_empty():
		return {"ok": false}
	var occupied_library: Array[StringName] = _occupied_card_ids(library_slots)
	if occupied_library.size() >= library_slots.size():
		return {"ok": false}
	occupied_library.push_front(removed_id)
	var result_main: Array = main_deck.duplicate()
	result_main[deck_index] = ""
	return {
		"ok": true,
		"main_deck": result_main,
		"library_slots": _padded_card_ids(occupied_library, library_slots.size()),
		"changed_deck_indices": [deck_index],
	}


static func build_player_replace_at(
	main_deck: Array,
	library_slots: Array,
	library_index: int,
	deck_index: int
) -> Dictionary:
	if (
		library_index < 0
		or library_index >= library_slots.size()
		or deck_index < 0
		or deck_index >= main_deck.size()
	):
		return {"ok": false}
	var incoming_id := StringName(String(library_slots[library_index]))
	var incoming_glyph: String = get_glyph(incoming_id)
	if incoming_glyph.is_empty():
		return {"ok": false}
	var namesake_index: int = find_deck_glyph_slot(main_deck, incoming_glyph)
	if namesake_index >= 0 and namesake_index != deck_index:
		return {"ok": false, "reason": &"duplicate_glyph"}

	var displaced_id := StringName(String(main_deck[deck_index]))
	var occupied_library: Array[StringName] = []
	for index: int in range(library_slots.size()):
		if index == library_index:
			continue
		var card_id := StringName(String(library_slots[index]))
		if card_id != &"":
			occupied_library.append(card_id)
	if displaced_id != &"":
		occupied_library.push_front(displaced_id)
	if occupied_library.size() > library_slots.size():
		return {"ok": false}

	var result_main: Array = main_deck.duplicate()
	result_main[deck_index] = String(incoming_id)
	return {
		"ok": true,
		"main_deck": result_main,
		"library_slots": _padded_card_ids(occupied_library, library_slots.size()),
		"changed_deck_indices": [deck_index],
	}


static func build_player_exchange(
	main_deck: Array,
	library_slots: Array,
	library_index: int,
	deck_index: int
) -> Dictionary:
	var result_main: Array = main_deck.duplicate()
	var result_library: Array = library_slots.duplicate()
	if (
		library_index < 0
		or library_index >= result_library.size()
		or deck_index < 0
		or deck_index >= result_main.size()
	):
		return {"ok": false}
	var incoming_id := StringName(String(result_library[library_index]))
	var displaced_id := StringName(String(result_main[deck_index]))
	var incoming_glyph: String = get_glyph(incoming_id)
	if incoming_glyph.is_empty() or get_glyph(displaced_id).is_empty():
		return {"ok": false}

	var old_namesake_index: int = -1
	for index: int in range(result_main.size()):
		if get_glyph(StringName(String(result_main[index]))) == incoming_glyph:
			old_namesake_index = index
			break

	var changed_indices: Array[int] = [deck_index]
	if old_namesake_index < 0 or old_namesake_index == deck_index:
		result_main[deck_index] = String(incoming_id)
		result_library[library_index] = String(displaced_id)
	else:
		var old_namesake_id := StringName(String(result_main[old_namesake_index]))
		result_main[deck_index] = String(incoming_id)
		result_main[old_namesake_index] = String(displaced_id)
		result_library[library_index] = String(old_namesake_id)
		changed_indices.append(old_namesake_index)

	return {
		"ok": true,
		"main_deck": result_main,
		"library_slots": result_library,
		"changed_deck_indices": changed_indices,
	}


static func repair_player_placement(
	unlocked_ids: Array,
	raw_deck: Array,
	raw_library: Array,
	deck_capacity: int,
	library_capacity: int
) -> Dictionary:
	var catalog_ids: Array[StringName] = Catalog.get_all_card_ids()
	var clean_unlocked: Array[StringName] = []
	for value: Variant in unlocked_ids:
		var card_id := StringName(String(value))
		if card_id != &"" and card_id in catalog_ids and card_id not in clean_unlocked:
			clean_unlocked.append(card_id)

	var winner_by_glyph: Dictionary = {}
	var deck_candidates: Array[Dictionary] = []
	var seen_deck_ids: Dictionary = {}
	for index: int in range(mini(deck_capacity, raw_deck.size())):
		var card_id := StringName(String(raw_deck[index]))
		if card_id == &"" or card_id not in clean_unlocked or seen_deck_ids.has(card_id):
			continue
		seen_deck_ids[card_id] = true
		var glyph: String = get_glyph(card_id)
		if glyph.is_empty():
			continue
		var candidate: Dictionary = {
			"id": card_id,
			"slot": index,
			"tier": _get_tier(card_id),
			"glyph": glyph,
		}
		deck_candidates.append(candidate)
		if (
			not winner_by_glyph.has(glyph)
			or int(candidate["tier"]) > int((winner_by_glyph[glyph] as Dictionary)["tier"])
		):
			winner_by_glyph[glyph] = candidate

	var repaired_deck: Array[StringName] = []
	repaired_deck.resize(deck_capacity)
	repaired_deck.fill(&"")
	var placed_ids: Dictionary = {}
	for glyph: String in winner_by_glyph:
		var winner: Dictionary = winner_by_glyph[glyph]
		var winner_id: StringName = winner["id"]
		var winner_slot: int = int(winner["slot"])
		repaired_deck[winner_slot] = winner_id
		placed_ids[winner_id] = true

	var removed_duplicate_ids: Array[StringName] = []
	for candidate: Dictionary in deck_candidates:
		var candidate_id: StringName = candidate["id"]
		if not placed_ids.has(candidate_id):
			removed_duplicate_ids.append(candidate_id)

	var stable_library: Array[StringName] = []
	var observed_library_ids: Dictionary = {}
	for value: Variant in raw_library:
		var card_id := StringName(String(value))
		if (
			card_id == &""
			or card_id not in clean_unlocked
			or placed_ids.has(card_id)
			or seen_deck_ids.has(card_id)
			or observed_library_ids.has(card_id)
		):
			continue
		observed_library_ids[card_id] = true
		stable_library.append(card_id)

	var repaired_library: Array[StringName] = []
	var library_set: Dictionary = {}
	for card_id: StringName in clean_unlocked:
		if (
			not placed_ids.has(card_id)
			and card_id not in stable_library
			and card_id not in removed_duplicate_ids
		):
			repaired_library.append(card_id)
			library_set[card_id] = true
	for card_id: StringName in stable_library:
		if not library_set.has(card_id):
			repaired_library.append(card_id)
			library_set[card_id] = true
	for card_id: StringName in removed_duplicate_ids:
		if not placed_ids.has(card_id) and not library_set.has(card_id):
			repaired_library.append(card_id)
			library_set[card_id] = true
	if repaired_library.size() > library_capacity:
		return {"ok": false}

	return {
		"ok": true,
		"main_deck": repaired_deck,
		"library_cards": repaired_library,
	}


static func _occupied_card_ids(values: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Variant in values:
		var card_id := StringName(String(value))
		if card_id != &"":
			result.append(card_id)
	return result


static func _padded_card_ids(values: Array[StringName], capacity: int) -> Array:
	var result: Array = []
	for card_id: StringName in values:
		result.append(String(card_id))
	while result.size() < capacity:
		result.append("")
	return result


static func build_side_deck_card_ids(main_deck_ids: Array) -> Array[StringName]:
	var main_definitions: Array[Dictionary] = []
	for value: Variant in main_deck_ids:
		var card_id := StringName(String(value))
		if Catalog.has_card(card_id):
			main_definitions.append(Catalog.get_definition(card_id))
	var catalog_entries: Array[Dictionary] = []
	for card_id: StringName in Catalog.get_all_card_ids():
		catalog_entries.append(Catalog.get_definition(card_id))
	return build_side_deck_from_entries(main_definitions, catalog_entries)


static func build_side_deck_from_entries(
	main_definitions: Array,
	catalog_entries: Array
) -> Array[StringName]:
	var tier_by_sect: Dictionary = {}
	for value: Variant in main_definitions:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var definition: Dictionary = value
		var sect: String = String(definition.get("sect", ""))
		if sect == WANDERER_SECT:
			continue
		var tier: int = int(definition.get("tier", 0))
		if tier > int(tier_by_sect.get(sect, 0)):
			tier_by_sect[sect] = tier

	var best_by_glyph: Dictionary = {}
	for value: Variant in catalog_entries:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = value
		if not is_side_candidate_eligible(candidate, tier_by_sect):
			continue
		var glyph: String = String(candidate.get("glyph", ""))
		if glyph.is_empty():
			continue
		if (
			not best_by_glyph.has(glyph)
			or is_better_side_candidate(
				candidate,
				best_by_glyph[glyph] as Dictionary
			)
		):
			best_by_glyph[glyph] = candidate

	var result: Array[StringName] = []
	for value: Variant in catalog_entries:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = value
		var glyph: String = String(candidate.get("glyph", ""))
		if (
			best_by_glyph.has(glyph)
			and StringName(String(candidate.get("id", "")))
			== StringName(String((best_by_glyph[glyph] as Dictionary).get("id", "")))
		):
			result.append(StringName(String(candidate.get("id", ""))))
	return result


static func is_side_candidate_eligible(
	candidate: Dictionary,
	tier_by_sect: Dictionary
) -> bool:
	var sect: String = String(candidate.get("sect", ""))
	if sect == WANDERER_SECT or not tier_by_sect.has(sect):
		return false
	var tier: int = int(candidate.get("tier", 0))
	return tier > 0 and tier <= int(tier_by_sect[sect])


static func is_better_side_candidate(
	candidate: Dictionary,
	current_best: Dictionary
) -> bool:
	return int(candidate.get("tier", 0)) > int(current_best.get("tier", 0))


static func _get_tier(card_id: StringName) -> int:
	if card_id == &"" or not Catalog.has_card(card_id):
		return 0
	return int(Catalog.get_definition(card_id).get("tier", 0))
