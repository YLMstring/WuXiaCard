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
		var glyph: String = get_glyph(StringName(String(value)))
		if glyph.is_empty() or observed.has(glyph):
			return false
		observed[glyph] = true
	return true


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
	var used_glyphs: Dictionary = {}
	for glyph: String in winner_by_glyph:
		var winner: Dictionary = winner_by_glyph[glyph]
		var winner_id: StringName = winner["id"]
		var winner_slot: int = int(winner["slot"])
		repaired_deck[winner_slot] = winner_id
		placed_ids[winner_id] = true
		used_glyphs[glyph] = true

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

	for slot_index: int in range(deck_capacity):
		if repaired_deck[slot_index] != &"":
			continue
		var filler_index: int = _find_first_unused_glyph_index(stable_library, used_glyphs)
		if filler_index >= 0:
			var filler_id: StringName = stable_library.pop_at(filler_index)
			repaired_deck[slot_index] = filler_id
			placed_ids[filler_id] = true
			used_glyphs[get_glyph(filler_id)] = true
			continue
		for unlocked_id: StringName in clean_unlocked:
			var glyph: String = get_glyph(unlocked_id)
			if (
				not placed_ids.has(unlocked_id)
				and unlocked_id not in stable_library
				and unlocked_id not in removed_duplicate_ids
				and not glyph.is_empty()
				and not used_glyphs.has(glyph)
			):
				repaired_deck[slot_index] = unlocked_id
				placed_ids[unlocked_id] = true
				used_glyphs[glyph] = true
				break
		if repaired_deck[slot_index] == &"":
			return {"ok": false}

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


static func _find_first_unused_glyph_index(
	card_ids: Array[StringName],
	used_glyphs: Dictionary
) -> int:
	for index: int in range(card_ids.size()):
		var glyph: String = get_glyph(card_ids[index])
		if not glyph.is_empty() and not used_glyphs.has(glyph):
			return index
	return -1
