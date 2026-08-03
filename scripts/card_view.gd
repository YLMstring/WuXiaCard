class_name CardView
extends PanelContainer

signal drag_started(card: CardView, pointer_position: Vector2)
signal drag_moved(card: CardView, pointer_position: Vector2)
signal drag_ended(card: CardView, pointer_position: Vector2)
signal inspection_requested(card_data: Dictionary)

@export var touch_drag_offset: float = 48.0
@export var drag_start_threshold: float = 12.0

const CARD_BACK_GLYPH: String = "◆"
const CARD_PICTURE_SCALE: float = 0.8
const MAX_TITLE_ROWS: int = 4
const FULL_WIDTH_SPACE: String = "　"
const Abilities = preload("res://scripts/duel_abilities.gd")
const Catalog = preload("res://scripts/card_catalog.gd")

var card_data: Dictionary = {}
var owner_id: int = 0
var playable: bool = false
var face_down: bool = false
var ki_badge_enabled: bool = true
var power_numbers_enabled: bool = true

var _dragging: bool = false
var _pointer_id: int = -2
var _pointer_offset: Vector2 = Vector2.ZERO
var _home_parent: Node = null
var _home_index: int = -1
var _pointer_pending: bool = false
var _pending_pointer_id: int = -2
var _pending_pointer_start: Vector2 = Vector2.ZERO

@onready var art_placeholder: Label = $Overlay/ArtPlaceholder
@onready var card_picture: TextureRect = $Overlay/CardPicture
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
	if face_down:
		_reset_pending_pointer()
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
		power_label.visible = power_numbers_enabled and not face_down
	var ki: int = int(card_data.get("ki", 0))
	var has_ki_ability: bool = Abilities.card_uses_ki(card_data)
	ki_value.text = str(ki)
	ki_badge.visible = ki_badge_enabled and not face_down and (ki > 0 or has_ki_ability)
	ki_badge.modulate = Color.WHITE if ki > 0 else Color(0.55, 0.62, 0.59, 0.72)
	art_placeholder.text = CARD_BACK_GLYPH if face_down else ""
	_refresh_picture()
	_update_title_font_size()
	tooltip_text = ""


func _refresh_picture() -> void:
	if face_down:
		card_picture.visible = false
		return
	card_picture.self_modulate = Color(1.0, 1.0, 1.0, 0.30) if Abilities.has_modifier(
		card_data,
		Catalog.MODIFIER_DEFENDING_POWER_OVERRIDE
	) else Color.WHITE
	var picture_path: String = String(card_data.get("picture", ""))
	if picture_path.is_empty() or not ResourceLoader.exists(picture_path):
		card_picture.texture = null
		card_picture.visible = false
		return
	if card_picture.texture == null or card_picture.texture.resource_path != picture_path:
		card_picture.texture = load(picture_path) as Texture2D
	card_picture.visible = card_picture.texture != null


func set_playable(value: bool) -> void:
	playable = value
	_update_cursor()


func set_runtime_ki(value: int) -> void:
	card_data["ki"] = maxi(value, 0)
	_refresh_face_content()


func set_runtime_powers(value: Array) -> void:
	if value.size() != 4:
		return
	card_data["powers"] = value.duplicate()
	_refresh_face_content()


func set_ki_badge_enabled(value: bool) -> void:
	ki_badge_enabled = value
	if is_node_ready():
		_refresh_face_content()


func set_power_numbers_enabled(value: bool) -> void:
	power_numbers_enabled = value
	if is_node_ready():
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


func remove_next_non_retained_ability() -> bool:
	var active_abilities: Array = card_data.get("active_abilities", [])
	var retained_abilities: Array = []
	var removed: bool = false
	for ability_value: Variant in active_abilities:
		var ability: Dictionary = ability_value
		if not removed and not bool(ability.get("retained_on_flip", false)):
			removed = true
			continue
		retained_abilities.append(ability.duplicate(true))
	card_data["active_abilities"] = retained_abilities
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
	_reset_pending_pointer()
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


func play_ability_lost(animation_duration: float) -> void:
	remove_next_non_retained_ability()
	if animation_duration <= 0.0:
		return
	var loss_tween: Tween = create_tween()
	loss_tween.tween_property(
		self,
		"modulate",
		Color(0.48, 0.48, 0.48, 1.0),
		animation_duration * 0.5
	)
	loss_tween.tween_property(self, "modulate", Color.WHITE, animation_duration * 0.5)
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
			_begin_pointer_gesture(mouse_event.global_position, -1)
		else:
			_end_pointer_gesture(mouse_event.global_position, -1)
		accept_event()
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			_begin_pointer_gesture(touch_event.position, touch_event.index)
		else:
			_end_pointer_gesture(touch_event.position, touch_event.index)
		accept_event()


func _input(event: InputEvent) -> void:
	if _pointer_pending:
		if event is InputEventMouseMotion and _pending_pointer_id == -1:
			_update_pointer_gesture((event as InputEventMouseMotion).position)
		elif event is InputEventMouseButton and _pending_pointer_id == -1:
			var pending_mouse_event := event as InputEventMouseButton
			if pending_mouse_event.button_index == MOUSE_BUTTON_LEFT and not pending_mouse_event.pressed:
				_end_pointer_gesture(pending_mouse_event.position, -1)
		elif event is InputEventScreenDrag:
			var pending_drag_event := event as InputEventScreenDrag
			if pending_drag_event.index == _pending_pointer_id:
				_update_pointer_gesture(pending_drag_event.position)
		elif event is InputEventScreenTouch:
			var pending_touch_event := event as InputEventScreenTouch
			if pending_touch_event.index == _pending_pointer_id and not pending_touch_event.pressed:
				_end_pointer_gesture(pending_touch_event.position, pending_touch_event.index)
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
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _pointer_pending:
		_reset_pending_pointer()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _dragging:
		call_deferred("_try_end_drag", get_viewport().get_mouse_position(), _pointer_id)


func _begin_pointer_gesture(pointer_position: Vector2, pointer_id: int) -> void:
	if _pointer_pending or _dragging or face_down:
		return
	_pointer_pending = true
	_pending_pointer_id = pointer_id
	_pending_pointer_start = pointer_position


func _update_pointer_gesture(pointer_position: Vector2) -> void:
	if not _pointer_pending:
		return
	if pointer_position.distance_to(_pending_pointer_start) <= drag_start_threshold:
		return
	var pointer_id: int = _pending_pointer_id
	var pointer_start: Vector2 = _pending_pointer_start
	_reset_pending_pointer()
	if not playable:
		return
	_try_begin_drag(pointer_start, pointer_id)
	if _dragging:
		_move_drag(pointer_position)


func _end_pointer_gesture(pointer_position: Vector2, pointer_id: int) -> void:
	if _dragging:
		_try_end_drag(pointer_position, pointer_id)
		return
	if not _pointer_pending or pointer_id != _pending_pointer_id:
		return
	var is_tap: bool = pointer_position.distance_to(_pending_pointer_start) <= drag_start_threshold
	_reset_pending_pointer()
	if is_tap and not face_down:
		inspection_requested.emit(card_data.duplicate(true))


func _reset_pending_pointer() -> void:
	_pointer_pending = false
	_pending_pointer_id = -2
	_pending_pointer_start = Vector2.ZERO


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
	var picture_side: float = short_side * CARD_PICTURE_SCALE
	card_picture.size = Vector2.ONE * picture_side
	card_picture.position = (size - card_picture.size) * 0.5
	var power_size: int = maxi(14, int(short_side * 0.2))
	for power_label: Label in [top_power, right_power, bottom_power, left_power]:
		power_label.add_theme_font_size_override("font_size", power_size)
	_update_title_font_size()


func _update_title_font_size() -> void:
	if not is_instance_valid(art_placeholder):
		return
	var title_length: int = 1 if face_down else maxi(1, str(card_data.get("glyph", "?")).length())
	var column_count: int = 1 if title_length <= MAX_TITLE_ROWS else 2
	var row_count: int = title_length if column_count == 1 else ceili(title_length / 2.0)
	var short_side: float = maxf(1.0, minf(size.x, size.y))
	var base_size: float = short_side * 0.3
	var width_units: float = 1.0 if column_count == 1 else 3.0
	var width_limited_size: float = maxf(1.0, size.x * 0.72) / width_units
	var height_limited_size: float = maxf(1.0, size.y * 0.72) / (float(row_count) * 1.05)
	var title_size: int = maxi(10, int(floor(minf(base_size, minf(width_limited_size, height_limited_size)))))
	art_placeholder.add_theme_font_size_override("font_size", title_size)


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
	return _get_owner_background()


func _get_display_border() -> Color:
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
