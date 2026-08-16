class_name DuelDecks
extends RefCounted

const ProfileStore = preload("res://scripts/deck_profile_store.gd")
const DeckRules = preload("res://scripts/deck_rules.gd")
const Catalog = preload("res://scripts/card_catalog.gd")

const PLAYER_CARD_IDS: Array[StringName] = ProfileStore.DEFAULT_MAIN_DECK_IDS

const OPPONENT_CARD_IDS: Array[StringName] = [
	&"CangSongYingKe1",
	&"TaiZuChangQuan",
	&"HuZhuaJueHuSHou2",
	&"TuNaShu1",
	&"TuNaShu1",
]


static func get_player_card_ids(
	profile_path: String = ProfileStore.DEFAULT_SAVE_PATH,
	testing_mode: bool = false
) -> Array[StringName]:
	var store: RefCounted = ProfileStore.new(profile_path)
	var profile: Dictionary = (
		store.load_profile_read_only()
		if testing_mode
		else store.load_profile()
	)
	if testing_mode:
		profile = store.create_testing_profile(profile)
		if profile_path == ProfileStore.DEFAULT_SAVE_PATH:
			return ProfileStore.TESTING_MAIN_DECK_IDS.duplicate()
	return store.get_main_deck_ids(profile)


static func get_player_enabled_effect_gates(
	profile_path: String = ProfileStore.DEFAULT_SAVE_PATH,
	testing_mode: bool = false
) -> Array[StringName]:
	var store: RefCounted = ProfileStore.new(profile_path)
	var profile: Dictionary = (
		store.load_profile_read_only()
		if testing_mode
		else store.load_profile()
	)
	if testing_mode:
		profile = store.create_testing_profile(profile)
	var result: Array[StringName] = []
	for card_id: StringName in store.get_unlocked_ids(profile):
		if not Catalog.has_card(card_id):
			continue
		var gate := StringName(
			Catalog.get_definition(card_id).get("unlocks_effect_gate", &"")
		)
		if gate != &"" and gate not in result:
			result.append(gate)
	return result


static func get_opponent_card_ids() -> Array[StringName]:
	return OPPONENT_CARD_IDS.duplicate()


static func get_side_deck_card_ids(main_deck_ids: Array) -> Array[StringName]:
	return DeckRules.build_side_deck_card_ids(main_deck_ids)
