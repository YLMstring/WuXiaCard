class_name CardView
extends PanelContainer

signal drag_started(card: CardView, pointer_position: Vector2)
signal drag_moved(card: CardView, pointer_position: Vector2)
signal drag_ended(card: CardView, pointer_position: Vector2)

@export var touch_drag_offset: float = 48.0

const CARD_BACK_GLYPH: String = "◆"
const Effects = preload("res://scripts/duel_effects.gd")

var card_data: Dictionary = {}
var owner_id: int = 0
var playable: bool = false
var face_down: bool = false

var _dragging: bool = false
var _pointer_id: int = -2
var _pointer_offset: Vector2 = Vector2.ZERO
var _home_parent: Node = null
var _home_index: int = -1

@onready var art_placeholder: Label = $Overlay/ArtPlaceholder
@onready var ink_slash: ColorRect = $Overlay/InkSlash
@onready var ink_bloom: InkBloom = $Overlay/InkBloom
@onready var top_power: Label = $Overlay/TopPower
@onready var right_power: Label = $Overlay/RightPower
@onready var bottom_power: Label = $Overlay/BottomPower
@onready var left_power: Label = $Overlay/LeftPower
@onready var ki_badge: PanelContainer = $Overlay/KiBadge
@onready var ki_value: Label = $Overlay/KiBadge/Value


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	resized.connect(_on_resized)
	_on_resized()
	_style_ki_badge()
	_apply_owner_style()


func configure(new_card_data: Dictionary, new_owner_id: int, is_playable: bool) -> void:
	card_data = new_card_data.duplicate(true)
	owner_id = new_owner_id
	playable = is_playable
	_refresh_face_content()
	_apply_owner_style()
	_update_cursor()


func sync_runtime_data(new_card_data: Dictionary, new_owner_id: int) -> void:
	card_data = new_card_data.duplicate(true)
	owner_id = new_owner_id
	_refresh_face_content()
	_apply_owner_style()
	_update_cursor()


func set_face_down(value: bool) -> void:
	face_down = value
	_refresh_face_content()
	_apply_owner_style()
	_update_cursor()


func is_face_down() -> bool:
	return face_down


func _refresh_face_content() -> void:
	var powers: Array = card_data.get("powers", [0, 0, 0, 0])
	top_power.text = str(powers[DuelRules.TOP])
	right_power.text = str(powers[DuelRules.RIGHT])
	bottom_power.text = str(powers[DuelRules.BOTTOM])
	left_power.text = str(powers[DuelRules.LEFT])
	for power_label: Label in [top_power, right_power, bottom_power, left_power]:
		power_label.visible = not face_down
	var ki: int = int(card_data.get("ki", 0))
	var has_ki_ability: bool = Effects.card_uses_ki(card_data)
	ki_value.text = str(ki)
	ki_badge.visible = not face_down and (ki > 0 or has_ki_ability)
	ki_badge.modulate = Color.WHITE if ki > 0 else Color(0.55, 0.62, 0.59, 0.72)
	art_placeholder.text = CARD_BACK_GLYPH if face_down else str(card_data.get("glyph", "?"))
	if face_down:
		tooltip_text = ""
	else:
		tooltip_text = "%s  ↑%s →%s ↓%s ←%s" % [
			str(card_data.get("name", "Card")),
			top_power.text,
			right_power.text,
			bottom_power.text,
			left_power.text,
		]


func set_playable(value: bool) -> void:
	playable = value
	_update_cursor()


func set_runtime_ki(value: int) -> void:
	card_data["ki"] = maxi(value, 0)
	_refresh_face_content()


func play_ki_gain_pulse(duration: float) -> void:
	if not ki_badge.visible or duration <= 0.0:
		return
	ki_badge.pivot_offset = ki_badge.size * 0.5
	var resting_modulate: Color = ki_badge.modulate
	var pulse_tween: Tween = create_tween()
	pulse_tween.set_parallel(true)
	pulse_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pulse_tween.tween_property(ki_badge, "scale", Vector2(1.22, 1.22), duration * 0.45)
	pulse_tween.tween_property(ki_badge, "modulate", Color(0.65, 1.0, 0.72, 1.0), duration * 0.45)
	await pulse_tween.finished
	var settle_tween: Tween = create_tween()
	settle_tween.set_parallel(true)
	settle_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	settle_tween.tween_property(ki_badge, "scale", Vector2.ONE, duration * 0.55)
	settle_tween.tween_property(ki_badge, "modulate", resting_modulate, duration * 0.55)
	await settle_tween.finished
	ki_badge.scale = Vector2.ONE
	ki_badge.modulate = resting_modulate


func set_card_owner(new_owner_id: int) -> void:
	owner_id = new_owner_id
	_apply_owner_style()


func remove_active_effect(effect_id: StringName) -> bool:
	var active_effects: Array = card_data.get("active_effects", [])
	var retained_effects: Array = []
	var removed: bool = false
	for effect_value: Variant in active_effects:
		var effect: Dictionary = effect_value
		if not removed and StringName(effect.get("id", &"")) == effect_id:
			removed = true
			continue
		retained_effects.append(effect.duplicate(true))
	card_data["active_effects"] = retained_effects
	_refresh_face_content()
	return removed


func get_home_parent() -> Node:
	return _home_parent


func get_home_index() -> int:
	return _home_index


func is_being_dragged() -> bool:
	return _dragging


func finish_drag_state() -> void:
	_dragging = false
	_pointer_id = -2
	scale = Vector2.ONE
	rotation = 0.0
	z_index = 0
	_apply_owner_style()
	_update_cursor()


func play_capture_flip(new_owner_id: int, duration: float) -> void:
	pivot_offset = size * 0.5
	var half_duration: float = maxf(0.01, duration * 0.5)
	var shrink_tween: Tween = create_tween()
	shrink_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	shrink_tween.tween_property(self, "scale:x", 0.05, half_duration)
	await shrink_tween.finished
	set_card_owner(new_owner_id)
	var grow_tween: Tween = create_tween()
	grow_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	grow_tween.tween_property(self, "scale:x", 1.0, half_duration)
	await grow_tween.finished


func play_effect_pulse(duration: float) -> void:
	if duration <= 0.0:
		return
	pivot_offset = size * 0.5
	var pulse_tween: Tween = create_tween()
	pulse_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pulse_tween.tween_property(self, "scale", Vector2(1.08, 1.08), duration * 0.45)
	pulse_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pulse_tween.tween_property(self, "scale", Vector2.ONE, duration * 0.55)
	await pulse_tween.finished


func play_draw_summon(
	bloom_duration: float,
	rise_duration: float,
	ink_color: Color
) -> void:
	pivot_offset = size * 0.5
	var resting_position: Vector2 = position
	ink_bloom.set_ink_color(ink_color)
	ink_bloom.pivot_offset = ink_bloom.size * 0.5
	ink_bloom.scale = Vector2(0.18, 0.18)
	ink_bloom.modulate = Color(1.0, 1.0, 1.0, 0.0)
	ink_bloom.visible = true
	scale = Vector2(0.76, 0.76)
	position = resting_position + Vector2(0.0, minf(26.0, size.y * 0.20))
	if bloom_duration > 0.0:
		var bloom_tween: Tween = create_tween()
		bloom_tween.set_parallel(true)
		bloom_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		bloom_tween.tween_property(ink_bloom, "scale", Vector2(1.15, 1.15), bloom_duration)
		bloom_tween.tween_property(ink_bloom, "modulate", Color.WHITE, bloom_duration * 0.55)
		await bloom_tween.finished
	if rise_duration > 0.0:
		var rise_tween: Tween = create_tween()
		rise_tween.set_parallel(true)
		rise_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		rise_tween.tween_property(self, "scale", Vector2.ONE, rise_duration)
		rise_tween.tween_property(self, "position", resting_position, rise_duration)
		rise_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		rise_tween.tween_property(ink_bloom, "modulate", Color(1.0, 1.0, 1.0, 0.0), rise_duration)
		await rise_tween.finished
	scale = Vector2.ONE
	position = resting_position
	rotation = 0.0
	modulate = Color.WHITE
	ink_bloom.visible = false
	ink_bloom.scale = Vector2.ONE
	ink_bloom.modulate = Color.WHITE


func play_exile(duration: float, ink_color: Color) -> void:
	pivot_offset = size * 0.5
	ink_slash.color = ink_color
	ink_slash.modulate = Color.WHITE
	ink_slash.visible = true
	if duration <= 0.0:
		scale = Vector2(0.05, 0.05)
		modulate = Color(1.0, 1.0, 1.0, 0.0)
		return
	var exile_tween: Tween = create_tween()
	exile_tween.set_parallel(true)
	exile_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	exile_tween.tween_property(self, "scale", Vector2(0.05, 0.05), duration)
	exile_tween.tween_property(self, "modulate", Color(0.35, 0.08, 0.08, 0.0), duration)
	exile_tween.tween_property(ink_slash, "modulate", Color(1.0, 1.0, 1.0, 0.0), duration)
	await exile_tween.finished


func play_ability_lost(effect_id: StringName, duration: float) -> void:
	remove_active_effect(effect_id)
	if duration <= 0.0:
		return
	var loss_tween: Tween = create_tween()
	loss_tween.tween_property(self, "modulate", Color(0.48, 0.48, 0.48, 1.0), duration * 0.5)
	loss_tween.tween_property(self, "modulate", Color.WHITE, duration * 0.5)
	await loss_tween.finished


func play_invalid_shake(duration: float) -> void:
	pivot_offset = size * 0.5
	var shake_tween: Tween = create_tween()
	shake_tween.tween_property(self, "rotation", 0.06, duration * 0.25)
	shake_tween.tween_property(self, "rotation", -0.06, duration * 0.5)
	shake_tween.tween_property(self, "rotation", 0.0, duration * 0.25)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_event.pressed:
			_try_begin_drag(mouse_event.global_position, -1)
		else:
			_try_end_drag(mouse_event.global_position, -1)
		accept_event()
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			_try_begin_drag(touch_event.position, touch_event.index)
		else:
			_try_end_drag(touch_event.position, touch_event.index)
		accept_event()


func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseMotion and _pointer_id == -1:
		_move_drag((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton and _pointer_id == -1:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			_try_end_drag(mouse_event.position, -1)
	elif event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if drag_event.index == _pointer_id:
			_move_drag(drag_event.position)
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.index == _pointer_id and not touch_event.pressed:
			_try_end_drag(touch_event.position, touch_event.index)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _dragging:
		call_deferred("_try_end_drag", get_viewport().get_mouse_position(), _pointer_id)


func _try_begin_drag(pointer_position: Vector2, pointer_id: int) -> void:
	if not playable or _dragging:
		return
	_dragging = true
	_pointer_id = pointer_id
	_home_parent = get_parent()
	_home_index = get_index()
	_pointer_offset = global_position - pointer_position
	if pointer_id >= 0:
		_pointer_offset.y -= touch_drag_offset
	pivot_offset = size * 0.5
	scale = Vector2(1.05, 1.05)
	z_index = 100
	_apply_drag_style()
	drag_started.emit(self, pointer_position)


func _move_drag(pointer_position: Vector2) -> void:
	global_position = pointer_position + _pointer_offset
	drag_moved.emit(self, pointer_position)


func _try_end_drag(pointer_position: Vector2, pointer_id: int) -> void:
	if not _dragging or pointer_id != _pointer_id:
		return
	drag_ended.emit(self, pointer_position)


func _on_resized() -> void:
	pivot_offset = size * 0.5
	var short_side: float = minf(size.x, size.y)
	var power_size: int = maxi(14, int(short_side * 0.2))
	var art_size: int = maxi(18, int(short_side * 0.3))
	for power_label: Label in [top_power, right_power, bottom_power, left_power]:
		power_label.add_theme_font_size_override("font_size", power_size)
	art_placeholder.add_theme_font_size_override("font_size", art_size)


func _update_cursor() -> void:
	mouse_default_cursor_shape = Control.CURSOR_DRAG if playable else Control.CURSOR_ARROW


func _style_ki_badge() -> void:
	var bead_style := StyleBoxFlat.new()
	bead_style.bg_color = Color("2f7664")
	bead_style.border_color = Color("b8dfc9")
	bead_style.set_border_width_all(2)
	bead_style.set_corner_radius_all(13)
	bead_style.shadow_color = Color(0.03, 0.12, 0.09, 0.45)
	bead_style.shadow_size = 2
	bead_style.shadow_offset = Vector2(0.0, 1.0)
	ki_badge.add_theme_stylebox_override("panel", bead_style)


func _apply_owner_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = _get_display_background()
	style.border_color = _get_display_border()
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0.08, 0.06, 0.05, 0.35)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 3)
	add_theme_stylebox_override("panel", style)


func _apply_drag_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = _get_display_background().lightened(0.08)
	style.border_color = Color("d2a63f")
	style.set_border_width_all(4)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0.04, 0.03, 0.02, 0.55)
	style.shadow_size = 9
	style.shadow_offset = Vector2(0, 7)
	add_theme_stylebox_override("panel", style)


func _get_display_background() -> Color:
	if face_down:
		return Color("8c403a")
	return _get_owner_background()


func _get_display_border() -> Color:
	if face_down:
		return Color("d2a63f")
	return _get_owner_border()


func _get_owner_background() -> Color:
	if owner_id == DuelRules.PLAYER_OWNER:
		return Color("79abc4")
	if owner_id == DuelRules.OPPONENT_OWNER:
		return Color("df7a70")
	return Color("e9e0cb")


func _get_owner_border() -> Color:
	if owner_id == DuelRules.PLAYER_OWNER:
		return Color("3f7d9e")
	if owner_id == DuelRules.OPPONENT_OWNER:
		return Color("b61522")
	return Color("8f826d")
