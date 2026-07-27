class_name DuelDecks
extends RefCounted

const Catalog = preload("res://scripts/card_catalog.gd")
const ProfileStore = preload("res://scripts/deck_profile_store.gd")

const PLAYER_CARD_IDS: Array[StringName] = ProfileStore.DEFAULT_MAIN_DECK_IDS

const OPPONENT_CARD_IDS: Array[StringName] = [
	&"CangSongYingKe1",
	&"fire_envoy",
	&"tiger_general",
	&"strategist",
	&"sun_zan",
]


static func get_player_card_ids(profile_path: String = ProfileStore.DEFAULT_SAVE_PATH) -> Array[StringName]:
	var store: RefCounted = ProfileStore.new(profile_path)
	return store.get_main_deck_ids(store.load_profile())


static func get_opponent_card_ids() -> Array[StringName]:
	return OPPONENT_CARD_IDS.duplicate()


static func get_side_deck_card_ids() -> Array[StringName]:
	return Catalog.get_all_card_ids()
