class_name DuelVariantFingerprint
extends RefCounted

const MASK_32: int = 0xFFFFFFFF

const TYPE_NIL_TOKEN: int = 1
const TYPE_BOOL_TOKEN: int = 2
const TYPE_INT_TOKEN: int = 3
const TYPE_FLOAT_TOKEN: int = 4
const TYPE_STRING_TOKEN: int = 5
const TYPE_STRING_NAME_TOKEN: int = 6
const TYPE_ARRAY_TOKEN: int = 7
const TYPE_DICTIONARY_TOKEN: int = 8
const TYPE_FALLBACK_TOKEN: int = 9

const PRIME_A_LOW: int = 16_777_619
const PRIME_A_HIGH: int = 16_777_633
const PRIME_B_LOW: int = 16_777_639
const PRIME_B_HIGH: int = 16_777_669


class FingerprintAccumulator:
	var a_low: int = 0x811C9DC5
	var a_high: int = 0x9E3779B9
	var b_low: int = 0x85EBCA6B
	var b_high: int = 0xC2B2AE35
	var element_count: int = 0
	var token_index: int = 0


static func build(value: Variant, dictionary_key_encoder: Callable) -> String:
	var accumulator := FingerprintAccumulator.new()
	_absorb_value(accumulator, value, dictionary_key_encoder)
	return "v2:%d:%08x%08x:%08x%08x" % [
		accumulator.element_count,
		accumulator.a_high,
		accumulator.a_low,
		accumulator.b_high,
		accumulator.b_low,
	]


static func _absorb_value(
	accumulator: FingerprintAccumulator,
	value: Variant,
	dictionary_key_encoder: Callable
) -> void:
	accumulator.element_count += 1
	match typeof(value):
		TYPE_NIL:
			_absorb_token(accumulator, TYPE_NIL_TOKEN)
		TYPE_BOOL:
			_absorb_token(accumulator, TYPE_BOOL_TOKEN)
			_absorb_token(accumulator, 1 if bool(value) else 0)
		TYPE_INT:
			_absorb_token(accumulator, TYPE_INT_TOKEN)
			_absorb_token(accumulator, int(value))
		TYPE_FLOAT:
			_absorb_token(accumulator, TYPE_FLOAT_TOKEN)
			_absorb_token(accumulator, hash(value))
		TYPE_STRING:
			_absorb_text(accumulator, TYPE_STRING_TOKEN, String(value))
		TYPE_STRING_NAME:
			_absorb_text(accumulator, TYPE_STRING_NAME_TOKEN, String(value))
		TYPE_ARRAY:
			var array_value: Array = value as Array
			_absorb_token(accumulator, TYPE_ARRAY_TOKEN)
			_absorb_token(accumulator, array_value.size())
			for item: Variant in array_value:
				_absorb_value(accumulator, item, dictionary_key_encoder)
		TYPE_DICTIONARY:
			_absorb_dictionary(
				accumulator,
				value as Dictionary,
				dictionary_key_encoder
			)
		_:
			_absorb_token(accumulator, TYPE_FALLBACK_TOKEN)
			_absorb_token(accumulator, typeof(value))
			_absorb_text(accumulator, TYPE_STRING_TOKEN, str(value))


static func _absorb_dictionary(
	accumulator: FingerprintAccumulator,
	value: Dictionary,
	dictionary_key_encoder: Callable
) -> void:
	_absorb_token(accumulator, TYPE_DICTIONARY_TOKEN)
	_absorb_token(accumulator, value.size())
	var entries: Array[Dictionary] = []
	for key: Variant in value.keys():
		entries.append({
			"key": key,
			"sort_key": String(dictionary_key_encoder.call(key)),
		})
	entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["sort_key"]) < String(right["sort_key"])
	)
	for entry: Dictionary in entries:
		var key: Variant = entry["key"]
		_absorb_value(accumulator, key, dictionary_key_encoder)
		_absorb_value(accumulator, value[key], dictionary_key_encoder)


static func _absorb_text(
	accumulator: FingerprintAccumulator,
	type_token: int,
	value: String
) -> void:
	var bytes: PackedByteArray = value.to_utf8_buffer()
	var forward_hash: int = hash(bytes)
	bytes.reverse()
	var reverse_hash: int = hash(bytes)
	_absorb_token(accumulator, type_token)
	_absorb_token(accumulator, bytes.size())
	_absorb_token(accumulator, forward_hash, reverse_hash)


static func _absorb_token(
	accumulator: FingerprintAccumulator,
	primary: int,
	secondary: int = 0
) -> void:
	var position: int = accumulator.token_index & MASK_32
	var primary_low: int = primary & MASK_32
	var primary_high: int = (primary >> 32) & MASK_32
	var secondary_low: int = secondary & MASK_32
	var secondary_high: int = (secondary >> 32) & MASK_32
	accumulator.a_low = _mix_lane(
		accumulator.a_low,
		primary_low ^ position,
		PRIME_A_LOW
	)
	accumulator.a_high = _mix_lane(
		accumulator.a_high,
		primary_high ^ secondary_low ^ position,
		PRIME_A_HIGH
	)
	accumulator.b_low = _mix_lane(
		accumulator.b_low,
		secondary_low ^ primary_high ^ position,
		PRIME_B_LOW
	)
	accumulator.b_high = _mix_lane(
		accumulator.b_high,
		secondary_high ^ primary_low ^ position,
		PRIME_B_HIGH
	)
	accumulator.token_index += 1


static func _mix_lane(current: int, token: int, prime: int) -> int:
	return ((current ^ (token & MASK_32)) * prime) & MASK_32
