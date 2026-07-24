class_name DuelDecks
extends RefCounted

const Catalog = preload("res://scripts/card_catalog.gd")

const PLAYER_CARD_IDS: Array[StringName] = [
	&"CangSongYingKe2",
	&"gate_general",
	&"meng_huo",
	&"jiang_wei",
	&"fa_zheng",
]

const OPPONENT_CARD_IDS: Array[StringName] = [
	&"CangSongYingKe1",
	&"fire_envoy",
	&"tiger_general",
	&"strategist",
	&"sun_zan",
]


static func get_player_card_ids() -> Array[StringName]:
	return PLAYER_CARD_IDS.duplicate()


static func get_opponent_card_ids() -> Array[StringName]:
	return OPPONENT_CARD_IDS.duplicate()


static func get_side_deck_card_ids() -> Array[StringName]:
	return Catalog.get_all_card_ids()
