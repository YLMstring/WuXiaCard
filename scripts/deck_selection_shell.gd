class_name DeckSelectionShell
extends RefCounted

const DuelBackdropData = preload("res://scripts/duel_backdrop.gd")


static func create_hand_slots(container: HBoxContainer) -> void:
	for existing: Node in container.get_children():
		existing.queue_free()
	for slot_index: int in range(5):
		var slot := PanelContainer.new()
		slot.name = "Slot%d" % slot_index
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = Color(1.0, 1.0, 1.0, 0.06)
		slot_style.border_color = Color(1.0, 1.0, 1.0, 0.10)
		slot_style.set_border_width_all(1)
		slot_style.set_corner_radius_all(5)
		slot.add_theme_stylebox_override("panel", slot_style)
		container.add_child(slot)


static func calculate_layout(viewport_size: Vector2, library_aspect_ratio: float) -> Dictionary:
	var fitted_rect: Rect2 = DuelBackdropData.fit_duel_rect(viewport_size)
	var canvas_size: Vector2 = fitted_rect.size
	var horizontal_margin: float = maxf(12.0, canvas_size.x * 0.03)
	var hand_width: float = canvas_size.x - horizontal_margin * 2.0
	var card_width: float = (hand_width - 16.0) / 5.0
	var hand_height: float = minf(canvas_size.y * 0.14, card_width / 0.75)
	var header_height: float = clampf(canvas_size.y * 0.0625, 56.0, 62.0)
	var header_gap: float = clampf(canvas_size.y * 0.0146, 12.0, 18.0)
	var top_bar_height: float = 44.0
	var opponent_top: float = header_height + header_gap
	var opponent_bottom: float = opponent_top + hand_height
	var status_gap: float = 8.0
	var status_height: float = 26.0
	var bottom_safe_margin: float = 8.0
	var player_bottom_margin: float = maxf(
		canvas_size.y * 0.05,
		status_gap + status_height + bottom_safe_margin
	)
	var player_top: float = canvas_size.y - player_bottom_margin - hand_height
	var interval_height: float = maxf(180.0, player_top - opponent_bottom)
	var minimum_gap: float = maxf(18.0, canvas_size.y * 0.032)
	var desired_width: float = canvas_size.x * 0.72
	var library_height: float = minf(
		desired_width / library_aspect_ratio,
		interval_height - minimum_gap * 2.0
	)
	var library_width: float = library_height * library_aspect_ratio
	var equal_gap: float = (interval_height - library_height) * 0.5
	var library_position := Vector2(
		(canvas_size.x - library_width) * 0.5,
		opponent_bottom + equal_gap
	)
	var desired_status_y: float = player_top + hand_height + status_gap
	var maximum_status_y: float = canvas_size.y - bottom_safe_margin - status_height
	return {
		"fitted_rect": fitted_rect,
		"canvas_size": canvas_size,
		"horizontal_margin": horizontal_margin,
		"hand_width": hand_width,
		"hand_height": hand_height,
		"header_height": header_height,
		"top_bar_height": top_bar_height,
		"opponent_hand_rect": Rect2(
			Vector2(horizontal_margin, opponent_top),
			Vector2(hand_width, hand_height)
		),
		"library_rect": Rect2(
			library_position,
			Vector2(library_width, library_height)
		),
		"player_hand_rect": Rect2(
			Vector2(horizontal_margin, player_top),
			Vector2(hand_width, hand_height)
		),
		"status_rect": Rect2(
			Vector2(horizontal_margin, minf(desired_status_y, maximum_status_y)),
			Vector2(hand_width, status_height)
		),
	}


static func apply_core_layout(
	viewport_size: Vector2,
	library_aspect_ratio: float,
	decor_backdrop: Control,
	duel_canvas: Control,
	top_wash: ColorRect,
	top_bar: HBoxContainer,
	opponent_hand: HBoxContainer,
	library_grid: Control,
	player_hand: HBoxContainer,
	status_label: Label
) -> Dictionary:
	var layout: Dictionary = calculate_layout(viewport_size, library_aspect_ratio)
	var fitted_rect: Rect2 = layout["fitted_rect"]
	var horizontal_margin: float = float(layout["horizontal_margin"])
	var hand_width: float = float(layout["hand_width"])
	var header_height: float = float(layout["header_height"])
	var top_bar_height: float = float(layout["top_bar_height"])
	duel_canvas.position = fitted_rect.position
	duel_canvas.size = fitted_rect.size
	decor_backdrop.call("configure", fitted_rect)
	top_wash.position = Vector2.ZERO
	top_wash.offset_bottom = header_height
	top_bar.position = Vector2(horizontal_margin, (header_height - top_bar_height) * 0.5)
	top_bar.size = Vector2(hand_width, top_bar_height)
	_apply_rect(opponent_hand, layout["opponent_hand_rect"])
	_apply_rect(library_grid, layout["library_rect"])
	_apply_rect(player_hand, layout["player_hand_rect"])
	_apply_rect(status_label, layout["status_rect"])
	return layout


static func style_header(
	top_wash: ColorRect,
	top_wash_tint: TextureRect,
	top_wash_edge: ColorRect,
	top_wash_shadow: ColorRect,
	enemy_seal: PanelContainer,
	enemy_seal_label: Label,
	opponent_name: Label,
	back_button: Button
) -> void:
	top_wash.color = DuelBackdropData.LACQUER_COLOR
	top_wash_edge.color = Color("c29969")
	top_wash_shadow.color = Color(0.08, 0.05, 0.04, 0.22)
	top_wash_shadow.offset_bottom = 3.0
	top_wash_tint.texture = DuelBackdropData.create_lacquer_tint_texture(540)
	var seal_style := StyleBoxFlat.new()
	seal_style.bg_color = Color("9e332f")
	seal_style.border_color = Color("c99261")
	seal_style.set_border_width_all(1)
	seal_style.set_corner_radius_all(2)
	seal_style.shadow_color = Color(0.08, 0.03, 0.02, 0.42)
	seal_style.shadow_size = 2
	seal_style.shadow_offset = Vector2(0.0, 1.0)
	enemy_seal.add_theme_stylebox_override("panel", seal_style)
	enemy_seal_label.add_theme_color_override("font_color", Color("f1d8b1"))
	enemy_seal_label.add_theme_font_size_override("font_size", 14)
	opponent_name.add_theme_color_override("font_color", Color("f2e4c7"))
	opponent_name.add_theme_color_override(
		"font_outline_color",
		Color(0.08, 0.04, 0.03, 0.55)
	)
	opponent_name.add_theme_constant_override("outline_size", 1)
	opponent_name.add_theme_font_size_override("font_size", 22)
	opponent_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	opponent_name.clip_text = true
	var empty_style := StyleBoxEmpty.new()
	for style_name: StringName in [
		&"normal",
		&"hover",
		&"pressed",
		&"hover_pressed",
		&"disabled",
		&"focus",
	]:
		back_button.add_theme_stylebox_override(style_name, empty_style)
	back_button.add_theme_color_override("icon_normal_color", Color("e2c89c"))
	back_button.add_theme_color_override("icon_hover_color", Color("f4ddb2"))
	back_button.add_theme_color_override("icon_pressed_color", Color("cdb387"))


static func _apply_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size
