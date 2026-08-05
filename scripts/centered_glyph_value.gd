class_name CenteredGlyphValue
extends Control

@export var text: String = "":
	set(value):
		if text == value:
			return
		text = value
		_invalidate_shape()
@export var font_size: int = 14:
	set(value):
		var next_size: int = maxi(1, value)
		if font_size == next_size:
			return
		font_size = next_size
		_invalidate_shape()
@export var outline_size: int = 2:
	set(value):
		var next_size: int = maxi(0, value)
		if outline_size == next_size:
			return
		outline_size = next_size
		_invalidate_shape()
@export var font_color: Color = Color.WHITE:
	set(value):
		font_color = value
		queue_redraw()
@export var outline_color: Color = Color.BLACK:
	set(value):
		outline_color = value
		queue_redraw()

var _font: Font = null
var _glyph_records: Array[Dictionary] = []
var _uncentered_ink_bounds: Rect2 = Rect2()
var _shape_dirty: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_theme_font()
	resized.connect(_on_resized)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_refresh_theme_font()


func set_value_text(value: String) -> void:
	text = value


func set_value_font_size(value: int) -> void:
	font_size = value


func set_value_outline_size(value: int) -> void:
	outline_size = value


func set_value_colors(next_font_color: Color, next_outline_color: Color) -> void:
	font_color = next_font_color
	outline_color = next_outline_color
	queue_redraw()


func debug_get_centered_ink_bounds() -> Rect2:
	_ensure_shape()
	if not _uncentered_ink_bounds.has_area():
		return Rect2()
	return Rect2(
		_uncentered_ink_bounds.position + _centering_translation(),
		_uncentered_ink_bounds.size
	)


func debug_get_glyph_count() -> int:
	_ensure_shape()
	return _glyph_records.size()


func _draw() -> void:
	_ensure_shape()
	if _glyph_records.is_empty() or not _uncentered_ink_bounds.has_area():
		return
	var text_server: TextServer = TextServerManager.get_primary_interface()
	var translation: Vector2 = _centering_translation()
	if outline_size > 0:
		for record: Dictionary in _glyph_records:
			text_server.font_draw_glyph_outline(
				record["font_rid"] as RID,
				get_canvas_item(),
				int(record["font_size"]),
				outline_size,
				translation + (record["baseline"] as Vector2),
				int(record["index"]),
				outline_color
			)
	for record: Dictionary in _glyph_records:
		text_server.font_draw_glyph(
			record["font_rid"] as RID,
			get_canvas_item(),
			int(record["font_size"]),
			translation + (record["baseline"] as Vector2),
			int(record["index"]),
			font_color
		)


func _refresh_theme_font() -> void:
	var next_font: Font = get_theme_font(&"font", &"Label")
	if next_font == null:
		next_font = ThemeDB.fallback_font
	if _font == next_font:
		return
	_font = next_font
	_invalidate_shape()


func _invalidate_shape() -> void:
	_shape_dirty = true
	queue_redraw()


func _on_resized() -> void:
	queue_redraw()


func _ensure_shape() -> void:
	if not _shape_dirty:
		return
	_shape_dirty = false
	_glyph_records.clear()
	_uncentered_ink_bounds = Rect2()
	if text.is_empty() or _font == null:
		return
	var font_rids: Array[RID] = _font.get_rids()
	if font_rids.is_empty():
		return
	var text_server: TextServer = TextServerManager.get_primary_interface()
	var shaped_text: RID = text_server.create_shaped_text()
	var added: bool = text_server.shaped_text_add_string(
		shaped_text,
		text,
		font_rids,
		font_size,
		{},
		""
	)
	if not added or not text_server.shaped_text_shape(shaped_text):
		text_server.free_rid(shaped_text)
		return
	var pen: Vector2 = Vector2.ZERO
	var has_visible_bounds: bool = false
	var shaped_glyphs: Array = text_server.shaped_text_get_glyphs(shaped_text)
	for glyph_value: Variant in shaped_glyphs:
		var glyph: Dictionary = glyph_value as Dictionary
		var glyph_rid: RID = glyph.get("font_rid", RID()) as RID
		var glyph_index: int = int(glyph.get("index", 0))
		var glyph_font_size: int = int(glyph.get("font_size", font_size))
		var glyph_offset: Vector2 = glyph.get("offset", Vector2.ZERO) as Vector2
		var glyph_advance := Vector2(float(glyph.get("advance", 0.0)), 0.0)
		var repeat_count: int = maxi(1, int(glyph.get("repeat", 1)))
		var cache_size := Vector2i(glyph_font_size, outline_size)
		for repeat_index: int in repeat_count:
			var baseline: Vector2 = pen + glyph_offset
			_glyph_records.append({
				"font_rid": glyph_rid,
				"font_size": glyph_font_size,
				"index": glyph_index,
				"baseline": baseline,
			})
			var visible_size: Vector2 = text_server.font_get_glyph_size(
				glyph_rid,
				cache_size,
				glyph_index
			)
			if visible_size.x > 0.0 and visible_size.y > 0.0:
				var visible_offset: Vector2 = text_server.font_get_glyph_offset(
					glyph_rid,
					cache_size,
					glyph_index
				)
				var glyph_bounds := Rect2(baseline + visible_offset, visible_size)
				_uncentered_ink_bounds = (
					glyph_bounds
					if not has_visible_bounds
					else _uncentered_ink_bounds.merge(glyph_bounds)
				)
				has_visible_bounds = true
			pen += glyph_advance
	text_server.free_rid(shaped_text)


func _centering_translation() -> Vector2:
	return size * 0.5 - _uncentered_ink_bounds.get_center()
