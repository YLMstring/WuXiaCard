class_name DuelAction
extends RefCounted

const TYPE_PLAY: StringName = &"play"
const TYPE_ACTIVATE: StringName = &"activate"

const SOURCE_HAND: StringName = &"hand"
const SOURCE_BOARD: StringName = &"board"

const TARGET_BOARD_CELL: StringName = &"board_cell"
const TARGET_HAND_SLOT: StringName = &"hand_slot"

var action_type: StringName = &""
var source_zone: StringName = &""
var source_index: int = -1
var source_instance_id: StringName = &""
var target_kind: StringName = &""
var target_index: int = -1
var activation_index: int = 0


func _init(
	new_action_type: StringName = &"",
	new_source_zone: StringName = &"",
	new_source_index: int = -1,
	new_source_instance_id: StringName = &"",
	new_target_kind: StringName = &"",
	new_target_index: int = -1,
	new_activation_index: int = 0
) -> void:
	action_type = new_action_type
	source_zone = new_source_zone
	source_index = new_source_index
	source_instance_id = new_source_instance_id
	target_kind = new_target_kind
	target_index = new_target_index
	activation_index = new_activation_index


static func make_play(
	hand_index: int,
	cell_index: int,
	instance_id: StringName = &""
):
	return new(
		TYPE_PLAY,
		SOURCE_HAND,
		hand_index,
		instance_id,
		TARGET_BOARD_CELL,
		cell_index
	)


static func make_activate(
	source_cell: int,
	instance_id: StringName,
	new_target_kind: StringName,
	new_target_index: int,
	new_activation_index: int = 0
):
	return new(
		TYPE_ACTIVATE,
		SOURCE_BOARD,
		source_cell,
		instance_id,
		new_target_kind,
		new_target_index,
		new_activation_index
	)


func duplicate_action():
	return get_script().new(
		action_type,
		source_zone,
		source_index,
		source_instance_id,
		target_kind,
		target_index,
		activation_index
	)


func as_vector2i() -> Vector2i:
	return Vector2i(source_index, target_index)


func is_same_as(other) -> bool:
	return (
		other != null
		and action_type == other.action_type
		and source_zone == other.source_zone
		and source_index == other.source_index
		and source_instance_id == other.source_instance_id
		and target_kind == other.target_kind
		and target_index == other.target_index
		and activation_index == other.activation_index
	)


func canonical_key() -> String:
	return "%s|%s|%010d|%s|%s|%010d|%010d" % [
		String(action_type),
		String(source_zone),
		source_index,
		String(source_instance_id),
		String(target_kind),
		target_index,
		activation_index,
	]
