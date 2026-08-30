class_name DuelCompactState
extends RefCounted

## Experimental, lossless compact snapshot of DuelState.
##
## This is deliberately not a second rules engine. It establishes and tests the
## data boundary that a future native simulator can consume. Static card data
## and immutable ability declarations are interned; mutable runtime values use
## packed arrays. The remaining uncommon state-level containers stay in a
## lossless side payload until their concrete native representation is proven.

const Rules = preload("res://scripts/duel_rules.gd")
const StateData = preload("res://scripts/duel_state.gd")

const FORMAT_VERSION: int = 1
const EMPTY_CARD_INDEX: int = -1

const ZONE_PLAYER_HAND: int = 0
const ZONE_OPPONENT_HAND: int = 1
const ZONE_PLAYER_DECK: int = 2
const ZONE_OPPONENT_DECK: int = 3
const ZONE_PLAYER_DISCARD: int = 4
const ZONE_OPPONENT_DISCARD: int = 5
const ZONE_PLAYER_REMOVED: int = 6
const ZONE_OPPONENT_REMOVED: int = 7
const ZONE_COUNT: int = 8

const FLAG_INSTANCE_ID: int = 1 << 0
const FLAG_POWERS: int = 1 << 1
const FLAG_ORIGINAL_OWNER: int = 1 << 2
const FLAG_KI: int = 1 << 3
const FLAG_ACTIVE_ABILITIES: int = 1 << 4
const FLAG_REVEALED_TO: int = 1 << 5
const FLAG_SUPPRESSION_BATCHES: int = 1 << 6
const FLAG_HAND_SLOT: int = 1 << 7

const SCALAR_ACTIVE_PLAYER: int = 0
const SCALAR_TURN_COUNT: int = 1
const SCALAR_OWNER_TURN_SERIAL: int = 2
const SCALAR_PLAYER_ATTACKS: int = 3
const SCALAR_OPPONENT_ATTACKS: int = 4
const SCALAR_EXTRA_CARD_PLAYS: int = 5
const SCALAR_END_TURN_TRIGGERS_RESOLVED: int = 6
const SCALAR_MAX_TURNS: int = 7
const SCALAR_PLAYER_PENDING_SUPPRESSION: int = 8
const SCALAR_OPPONENT_PENDING_SUPPRESSION: int = 9
const SCALAR_RUN_DIFFICULTY: int = 10
const SCALAR_DIFFICULTY_EIGHT_DRAW_CONSUMED: int = 11
const SCALAR_STATE_VERSION: int = 12
const SCALAR_COUNT: int = 13

const MUTABLE_CARD_KEYS: Array[StringName] = [
	&"instance_id",
	&"powers",
	&"original_owner",
	&"ki",
	&"active_abilities",
	&"revealed_to_owner_ids",
	&"temporary_suppression_batches",
	StateData.HAND_SLOT_INDEX_KEY,
]

const SIDE_PAYLOAD_KEYS: Array[StringName] = [
	&"active_abilities",
	&"effect_queue",
	&"pending_choice",
	&"repetition_hashes",
	&"remembered_glyphs_by_owner",
	&"future_draw_reveal_audiences",
	&"last_hand_play_by_owner",
	&"enabled_effect_gates_by_owner",
]

var scalars: PackedInt32Array = PackedInt32Array()
var board_card_indices: PackedInt32Array = PackedInt32Array()
var board_owners: PackedByteArray = PackedByteArray()
var board_slot_extras: Array[Dictionary] = []
var zone_card_indices: Array[PackedInt32Array] = []

var card_instance_ids: Array[StringName] = []
var card_template_indices: PackedInt32Array = PackedInt32Array()
var card_runtime_flags: PackedByteArray = PackedByteArray()
var card_powers: PackedInt32Array = PackedInt32Array()
var card_original_owners: PackedByteArray = PackedByteArray()
var card_ki: PackedInt32Array = PackedInt32Array()
var card_active_ability_set_indices: PackedInt32Array = PackedInt32Array()
var card_reveal_codes: PackedByteArray = PackedByteArray()
var card_suppression_set_indices: PackedInt32Array = PackedInt32Array()
var card_hand_slots: PackedInt32Array = PackedInt32Array()

## These pools are immutable after capture and may be shared by compact copies.
var card_template_pool: Array[Dictionary] = []
var active_ability_set_pool: Array[Array] = []
var suppression_set_pool: Array[Array] = []

## Lossless bridge for uncommon or not-yet-packed state-level containers.
var side_payload: Dictionary = {}
var capture_error: String = ""

var _card_index_by_instance_id: Dictionary = {}
var _template_index_by_bytes: Dictionary = {}
var _ability_set_index_by_bytes: Dictionary = {}
var _suppression_set_index_by_bytes: Dictionary = {}


func capture_state(state: StateData) -> bool:
	if state == null:
		return _fail("Cannot capture a null DuelState")
	return _capture_state(state)


func restore() -> StateData:
	if not is_structurally_valid():
		return null
	var restored := StateData.new()
	var cards: Array[Dictionary] = []
	cards.resize(card_instance_ids.size())
	for card_index: int in range(card_instance_ids.size()):
		cards[card_index] = _restore_card(card_index)

	restored.board = []
	restored.board.resize(board_card_indices.size())
	for cell: int in range(board_card_indices.size()):
		var card_index: int = board_card_indices[cell]
		if card_index == EMPTY_CARD_INDEX:
			continue
		var slot: Dictionary = board_slot_extras[cell].duplicate(true)
		slot["owner"] = int(board_owners[cell])
		slot["card"] = cards[card_index]
		restored.board[cell] = slot

	restored.hands = {
		Rules.PLAYER_OWNER: _restore_zone(ZONE_PLAYER_HAND, cards),
		Rules.OPPONENT_OWNER: _restore_zone(ZONE_OPPONENT_HAND, cards),
	}
	restored.decks = {
		Rules.PLAYER_OWNER: _restore_zone(ZONE_PLAYER_DECK, cards),
		Rules.OPPONENT_OWNER: _restore_zone(ZONE_OPPONENT_DECK, cards),
	}
	restored.discard_piles = {
		Rules.PLAYER_OWNER: _restore_zone(ZONE_PLAYER_DISCARD, cards),
		Rules.OPPONENT_OWNER: _restore_zone(ZONE_OPPONENT_DISCARD, cards),
	}
	restored.removed_cards = {
		Rules.PLAYER_OWNER: _restore_zone(ZONE_PLAYER_REMOVED, cards),
		Rules.OPPONENT_OWNER: _restore_zone(ZONE_OPPONENT_REMOVED, cards),
	}

	restored.active_player = scalars[SCALAR_ACTIVE_PLAYER]
	restored.turn_count = scalars[SCALAR_TURN_COUNT]
	restored.owner_turn_serial = scalars[SCALAR_OWNER_TURN_SERIAL]
	restored.attacks_started_by_owner = {
		Rules.PLAYER_OWNER: scalars[SCALAR_PLAYER_ATTACKS],
		Rules.OPPONENT_OWNER: scalars[SCALAR_OPPONENT_ATTACKS],
	}
	restored.extra_card_plays_remaining = scalars[SCALAR_EXTRA_CARD_PLAYS]
	restored.end_turn_triggers_resolved = bool(
		scalars[SCALAR_END_TURN_TRIGGERS_RESOLVED]
	)
	restored.max_turns = scalars[SCALAR_MAX_TURNS]
	restored.pending_non_retained_suppression_by_owner = {
		Rules.PLAYER_OWNER: scalars[SCALAR_PLAYER_PENDING_SUPPRESSION],
		Rules.OPPONENT_OWNER: scalars[SCALAR_OPPONENT_PENDING_SUPPRESSION],
	}
	restored.run_difficulty = scalars[SCALAR_RUN_DIFFICULTY]
	restored.difficulty_eight_draw_consumed = bool(
		scalars[SCALAR_DIFFICULTY_EIGHT_DRAW_CONSUMED]
	)
	restored.state_version = scalars[SCALAR_STATE_VERSION]

	for key: StringName in SIDE_PAYLOAD_KEYS:
		restored.set(String(key), side_payload.get(key).duplicate(true))
	return restored


func duplicate_compact() -> RefCounted:
	var copied: RefCounted = get_script().new()
	copied.scalars = scalars.duplicate()
	copied.board_card_indices = board_card_indices.duplicate()
	copied.board_owners = board_owners.duplicate()
	copied.board_slot_extras = board_slot_extras.duplicate(true)
	var copied_zones: Array[PackedInt32Array] = []
	for zone: PackedInt32Array in zone_card_indices:
		copied_zones.append(zone.duplicate())
	copied.zone_card_indices = copied_zones
	copied.card_instance_ids = card_instance_ids.duplicate()
	copied.card_template_indices = card_template_indices.duplicate()
	copied.card_runtime_flags = card_runtime_flags.duplicate()
	copied.card_powers = card_powers.duplicate()
	copied.card_original_owners = card_original_owners.duplicate()
	copied.card_ki = card_ki.duplicate()
	copied.card_active_ability_set_indices = card_active_ability_set_indices.duplicate()
	copied.card_reveal_codes = card_reveal_codes.duplicate()
	copied.card_suppression_set_indices = card_suppression_set_indices.duplicate()
	copied.card_hand_slots = card_hand_slots.duplicate()
	copied.card_template_pool = card_template_pool
	copied.active_ability_set_pool = active_ability_set_pool
	copied.suppression_set_pool = suppression_set_pool
	copied.side_payload = side_payload.duplicate(true)
	return copied


func is_structurally_valid() -> bool:
	var card_count: int = card_instance_ids.size()
	return (
		capture_error.is_empty()
		and scalars.size() == SCALAR_COUNT
		and board_card_indices.size() == board_owners.size()
		and board_card_indices.size() == board_slot_extras.size()
		and zone_card_indices.size() == ZONE_COUNT
		and card_template_indices.size() == card_count
		and card_runtime_flags.size() == card_count
		and card_powers.size() == card_count * 4
		and card_original_owners.size() == card_count
		and card_ki.size() == card_count
		and card_active_ability_set_indices.size() == card_count
		and card_reveal_codes.size() == card_count
		and card_suppression_set_indices.size() == card_count
		and card_hand_slots.size() == card_count
	)


func to_variant_payload() -> Dictionary:
	var payload: Dictionary = to_mutable_variant_payload()
	payload["card_template_pool"] = card_template_pool
	payload["active_ability_set_pool"] = active_ability_set_pool
	payload["suppression_set_pool"] = suppression_set_pool
	return payload


func to_mutable_variant_payload() -> Dictionary:
	var zones: Array = []
	for zone: PackedInt32Array in zone_card_indices:
		zones.append(zone)
	return {
		"format_version": FORMAT_VERSION,
		"scalars": scalars,
		"board_card_indices": board_card_indices,
		"board_owners": board_owners,
		"board_slot_extras": board_slot_extras,
		"zones": zones,
		"card_instance_ids": card_instance_ids,
		"card_template_indices": card_template_indices,
		"card_runtime_flags": card_runtime_flags,
		"card_powers": card_powers,
		"card_original_owners": card_original_owners,
		"card_ki": card_ki,
		"card_active_ability_set_indices": card_active_ability_set_indices,
		"card_reveal_codes": card_reveal_codes,
		"card_suppression_set_indices": card_suppression_set_indices,
		"card_hand_slots": card_hand_slots,
		"side_payload": side_payload,
	}


static func exact_state_payload(state: StateData) -> Dictionary:
	return {
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
		"state_version": state.state_version,
	}


func _capture_state(state: StateData) -> bool:
	scalars = PackedInt32Array([
		state.active_player,
		state.turn_count,
		state.owner_turn_serial,
		int(state.attacks_started_by_owner.get(Rules.PLAYER_OWNER, 0)),
		int(state.attacks_started_by_owner.get(Rules.OPPONENT_OWNER, 0)),
		state.extra_card_plays_remaining,
		int(state.end_turn_triggers_resolved),
		state.max_turns,
		int(state.pending_non_retained_suppression_by_owner.get(Rules.PLAYER_OWNER, 0)),
		int(state.pending_non_retained_suppression_by_owner.get(Rules.OPPONENT_OWNER, 0)),
		state.run_difficulty,
		int(state.difficulty_eight_draw_consumed),
		state.state_version,
	])

	board_card_indices.resize(state.board.size())
	board_card_indices.fill(EMPTY_CARD_INDEX)
	board_owners.resize(state.board.size())
	board_owners.fill(0)
	board_slot_extras.resize(state.board.size())
	for cell: int in range(state.board.size()):
		board_slot_extras[cell] = {}
		var slot_value: Variant = state.board[cell]
		if slot_value == null:
			continue
		if not slot_value is Dictionary:
			return _fail("Board cell %d is not a Dictionary" % cell)
		var slot: Dictionary = slot_value
		var card_value: Variant = slot.get("card")
		if not card_value is Dictionary:
			return _fail("Board cell %d has no runtime card" % cell)
		var card_index: int = _capture_card(card_value as Dictionary)
		if card_index < 0:
			return false
		board_card_indices[cell] = card_index
		board_owners[cell] = int(slot.get("owner", 0))
		var extras: Dictionary = slot.duplicate(true)
		extras.erase("owner")
		extras.erase("card")
		board_slot_extras[cell] = extras

	zone_card_indices.resize(ZONE_COUNT)
	var zone_sources: Array[Array] = [
		state.get_hand(Rules.PLAYER_OWNER),
		state.get_hand(Rules.OPPONENT_OWNER),
		state.decks.get(Rules.PLAYER_OWNER, []) as Array,
		state.decks.get(Rules.OPPONENT_OWNER, []) as Array,
		state.discard_piles.get(Rules.PLAYER_OWNER, []) as Array,
		state.discard_piles.get(Rules.OPPONENT_OWNER, []) as Array,
		state.removed_cards.get(Rules.PLAYER_OWNER, []) as Array,
		state.removed_cards.get(Rules.OPPONENT_OWNER, []) as Array,
	]
	for zone_index: int in range(ZONE_COUNT):
		var packed_zone := PackedInt32Array()
		for card_value: Variant in zone_sources[zone_index]:
			if not card_value is Dictionary:
				return _fail("Zone %d contains a non-card value" % zone_index)
			var card_index: int = _capture_card(card_value as Dictionary)
			if card_index < 0:
				return false
			packed_zone.append(card_index)
		zone_card_indices[zone_index] = packed_zone

	for key: StringName in SIDE_PAYLOAD_KEYS:
		side_payload[key] = state.get(String(key)).duplicate(true)
	return is_structurally_valid()


func _capture_card(card: Dictionary) -> int:
	var instance_id := StringName(card.get("instance_id", &""))
	if instance_id == &"":
		_fail("Every compact runtime card requires a non-empty instance_id")
		return -1
	if _card_index_by_instance_id.has(instance_id):
		_fail("Duplicate runtime card instance_id: %s" % instance_id)
		return -1

	var template: Dictionary = card.duplicate(true)
	for key: StringName in MUTABLE_CARD_KEYS:
		template.erase(key)
	var template_index: int = _intern_dictionary(
		template,
		card_template_pool,
		_template_index_by_bytes
	)

	var flags: int = FLAG_INSTANCE_ID
	var powers := PackedInt32Array([0, 0, 0, 0])
	if card.has("powers"):
		var source_powers: Array = card.get("powers", []) as Array
		if source_powers.size() != 4:
			_fail("Card %s does not have exactly four powers" % instance_id)
			return -1
		flags |= FLAG_POWERS
		for direction: int in range(4):
			powers[direction] = int(source_powers[direction])

	var original_owner: int = 0
	if card.has("original_owner"):
		flags |= FLAG_ORIGINAL_OWNER
		original_owner = int(card.get("original_owner", 0))
	var ki: int = 0
	if card.has("ki"):
		flags |= FLAG_KI
		ki = int(card.get("ki", 0))

	var active_set_index: int = -1
	if card.has("active_abilities"):
		flags |= FLAG_ACTIVE_ABILITIES
		active_set_index = _intern_array(
			card.get("active_abilities", []) as Array,
			active_ability_set_pool,
			_ability_set_index_by_bytes
		)

	var reveal_code: int = 0
	if card.has("revealed_to_owner_ids"):
		flags |= FLAG_REVEALED_TO
		reveal_code = _encode_reveal_order(
			card.get("revealed_to_owner_ids", []) as Array
		)
		if reveal_code < 0:
			_fail("Card %s has an invalid reveal audience order" % instance_id)
			return -1

	var suppression_set_index: int = -1
	if card.has("temporary_suppression_batches"):
		flags |= FLAG_SUPPRESSION_BATCHES
		suppression_set_index = _intern_array(
			card.get("temporary_suppression_batches", []) as Array,
			suppression_set_pool,
			_suppression_set_index_by_bytes
		)

	var hand_slot: int = -1
	if card.has(StateData.HAND_SLOT_INDEX_KEY):
		flags |= FLAG_HAND_SLOT
		hand_slot = int(card.get(StateData.HAND_SLOT_INDEX_KEY, -1))

	var card_index: int = card_instance_ids.size()
	_card_index_by_instance_id[instance_id] = card_index
	card_instance_ids.append(instance_id)
	card_template_indices.append(template_index)
	card_runtime_flags.append(flags)
	card_powers.append_array(powers)
	card_original_owners.append(original_owner)
	card_ki.append(ki)
	card_active_ability_set_indices.append(active_set_index)
	card_reveal_codes.append(reveal_code)
	card_suppression_set_indices.append(suppression_set_index)
	card_hand_slots.append(hand_slot)
	return card_index


func _restore_card(card_index: int) -> Dictionary:
	var template_index: int = card_template_indices[card_index]
	var card: Dictionary = card_template_pool[template_index].duplicate(true)
	var flags: int = card_runtime_flags[card_index]
	if flags & FLAG_INSTANCE_ID:
		card["instance_id"] = card_instance_ids[card_index]
	if flags & FLAG_POWERS:
		var offset: int = card_index * 4
		card["powers"] = [
			card_powers[offset],
			card_powers[offset + 1],
			card_powers[offset + 2],
			card_powers[offset + 3],
		]
	if flags & FLAG_ORIGINAL_OWNER:
		card["original_owner"] = int(card_original_owners[card_index])
	if flags & FLAG_KI:
		card["ki"] = card_ki[card_index]
	if flags & FLAG_ACTIVE_ABILITIES:
		var set_index: int = card_active_ability_set_indices[card_index]
		card["active_abilities"] = active_ability_set_pool[set_index].duplicate()
	if flags & FLAG_REVEALED_TO:
		card["revealed_to_owner_ids"] = _decode_reveal_order(
			card_reveal_codes[card_index]
		)
	if flags & FLAG_SUPPRESSION_BATCHES:
		var set_index: int = card_suppression_set_indices[card_index]
		card["temporary_suppression_batches"] = (
			suppression_set_pool[set_index].duplicate(true)
		)
	if flags & FLAG_HAND_SLOT:
		card[StateData.HAND_SLOT_INDEX_KEY] = card_hand_slots[card_index]
	return card


func _restore_zone(zone_index: int, cards: Array[Dictionary]) -> Array:
	var restored: Array = []
	for card_index: int in zone_card_indices[zone_index]:
		restored.append(cards[card_index])
	return restored


func _encode_reveal_order(audiences: Array) -> int:
	match audiences:
		[]:
			return 0
		[Rules.PLAYER_OWNER]:
			return 1
		[Rules.OPPONENT_OWNER]:
			return 2
		[Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
			return 3
		[Rules.OPPONENT_OWNER, Rules.PLAYER_OWNER]:
			return 4
		_:
			return -1


func _decode_reveal_order(code: int) -> Array:
	match code:
		0:
			return []
		1:
			return [Rules.PLAYER_OWNER]
		2:
			return [Rules.OPPONENT_OWNER]
		3:
			return [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]
		4:
			return [Rules.OPPONENT_OWNER, Rules.PLAYER_OWNER]
		_:
			return []


func _intern_dictionary(
	value: Dictionary,
	pool: Array[Dictionary],
	index_by_bytes: Dictionary
) -> int:
	var key: PackedByteArray = var_to_bytes(value)
	var encoded: String = key.hex_encode()
	if index_by_bytes.has(encoded):
		return int(index_by_bytes[encoded])
	var index: int = pool.size()
	pool.append(value.duplicate(true))
	index_by_bytes[encoded] = index
	return index


func _intern_array(
	value: Array,
	pool: Array[Array],
	index_by_bytes: Dictionary
) -> int:
	var key: PackedByteArray = var_to_bytes(value)
	var encoded: String = key.hex_encode()
	if index_by_bytes.has(encoded):
		return int(index_by_bytes[encoded])
	var index: int = pool.size()
	pool.append(value.duplicate(true))
	index_by_bytes[encoded] = index
	return index


func _fail(message: String) -> bool:
	capture_error = message
	push_error("Compact state capture failed: %s" % message)
	return false
