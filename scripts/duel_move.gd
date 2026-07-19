class_name DuelMove
extends RefCounted

var hand_index: int = -1
var cell_index: int = -1
var effect_choice: Dictionary = {}


func _init(
	new_hand_index: int = -1,
	new_cell_index: int = -1,
	new_effect_choice: Dictionary = {}
) -> void:
	hand_index = new_hand_index
	cell_index = new_cell_index
	effect_choice = new_effect_choice.duplicate(true)


func duplicate_move():
	return get_script().new(hand_index, cell_index, effect_choice)


func as_vector2i() -> Vector2i:
	return Vector2i(hand_index, cell_index)


func is_same_as(other: Object) -> bool:
	return (
		other != null
		and hand_index == other.hand_index
		and cell_index == other.cell_index
		and effect_choice == other.effect_choice
	)
