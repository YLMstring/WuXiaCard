class_name CenteredGlyphValue
extends Control

static var _glyph_texture_cache: Dictionary = {}

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
var _uncentered_ink_centroid: Vector2 = Vector2.ZERO
var _has_ink_centroid: bool = false
var _shape_dirty: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
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


func debug_get_centered_ink_centroid() -> Vector2:
	_ensure_shape()
	if not _has_ink_centroid:
		return Vector2.ZERO
	return _uncentered_ink_centroid + _centering_translation()


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
			_draw_glyph_texture(
				text_server,
				record,
				outline_size,
				translation,
				outline_color
			)
	for record: Dictionary in _glyph_records:
		_draw_glyph_texture(
			text_server,
			record,
			0,
			translation,
			font_color
		)


func _draw_glyph_texture(
	text_server: TextServer,
	record: Dictionary,
	cache_outline_size: int,
	translation: Vector2,
	color: Color
) -> void:
	var font_rid: RID = record["font_rid"] as RID
	var glyph_font_size: int = int(record["font_size"])
	var glyph_index: int = int(record["index"])
	var baseline: Vector2 = record["baseline"] as Vector2
	var texture_data: Dictionary = _get_glyph_texture_data(
		text_server,
		font_rid,
		glyph_font_size,
		cache_outline_size,
		glyph_index
	)
	var glyph_texture: Texture2D = texture_data.get("texture") as Texture2D
	if glyph_texture != null:
		var texture_offset: Vector2 = texture_data.get(
			"offset_from_baseline",
			Vector2.ZERO
		) as Vector2
		var texture_size: Vector2 = texture_data.get(
			"texture_size",
			Vector2.ZERO
		) as Vector2
		draw_texture_rect(
			glyph_texture,
			Rect2(translation + baseline + texture_offset, texture_size),
			false,
			color
		)
		return
	if cache_outline_size > 0:
		text_server.font_draw_glyph_outline(
			font_rid,
			get_canvas_item(),
			glyph_font_size,
			cache_outline_size,
			translation + baseline,
			glyph_index,
			color
		)
	else:
		text_server.font_draw_glyph(
			font_rid,
			get_canvas_item(),
			glyph_font_size,
			translation + baseline,
			glyph_index,
			color
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
	_uncentered_ink_centroid = Vector2.ZERO
	_has_ink_centroid = false
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
	var weighted_centroid_sum: Vector2 = Vector2.ZERO
	var total_ink_weight: float = 0.0
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
			var ink_data: Dictionary = _get_glyph_texture_data(
				text_server,
				glyph_rid,
				glyph_font_size,
				0,
				glyph_index
			)
			var ink_weight: float = float(ink_data.get("weight", 0.0))
			if ink_weight > 0.0:
				var centroid_from_baseline: Vector2 = ink_data.get(
					"centroid_from_baseline",
					Vector2.ZERO
				) as Vector2
				weighted_centroid_sum += (
					baseline + centroid_from_baseline
				) * ink_weight
				total_ink_weight += ink_weight
			pen += glyph_advance
	text_server.free_rid(shaped_text)
	if total_ink_weight > 0.0:
		_uncentered_ink_centroid = weighted_centroid_sum / total_ink_weight
		_has_ink_centroid = true


func _get_glyph_texture_data(
	text_server: TextServer,
	font_rid: RID,
	glyph_font_size: int,
	cache_outline_size: int,
	glyph_index: int
) -> Dictionary:
	var cache_key := "%s:%d:%d:%d" % [
		str(font_rid),
		glyph_font_size,
		cache_outline_size,
		glyph_index,
	]
	if _glyph_texture_cache.has(cache_key):
		return _glyph_texture_cache[cache_key] as Dictionary
	var cache_size := Vector2i(glyph_font_size, cache_outline_size)
	text_server.font_get_glyph_texture_rid(font_rid, cache_size, glyph_index)
	var texture_index: int = text_server.font_get_glyph_texture_idx(
		font_rid,
		cache_size,
		glyph_index
	)
	var texture_image: Image = text_server.font_get_texture_image(
		font_rid,
		cache_size,
		texture_index
	)
	var uv_rect: Rect2 = text_server.font_get_glyph_uv_rect(
		font_rid,
		cache_size,
		glyph_index
	)
	var glyph_offset: Vector2 = text_server.font_get_glyph_offset(
		font_rid,
		cache_size,
		glyph_index
	)
	var result: Dictionary = {}
	if not texture_image.is_empty() and uv_rect.has_area():
		var uv_position := Vector2i(roundi(uv_rect.position.x), roundi(uv_rect.position.y))
		var uv_size := Vector2i(roundi(uv_rect.size.x), roundi(uv_rect.size.y))
		var glyph_image: Image = texture_image.get_region(Rect2i(uv_position, uv_size))
		var weighted_sum: Vector2 = Vector2.ZERO
		var total_weight: float = 0.0
		var image_format: int = glyph_image.get_format()
		for local_y: int in uv_size.y:
			for local_x: int in uv_size.x:
				var pixel: Color = glyph_image.get_pixel(local_x, local_y)
				var weight: float = (
					pixel.r if image_format == Image.FORMAT_L8 else pixel.a
				)
				if weight <= 0.0:
					continue
				weighted_sum += Vector2(local_x + 0.5, local_y + 0.5) * weight
				total_weight += weight
		result = {
			"texture": ImageTexture.create_from_image(glyph_image),
			"offset_from_baseline": glyph_offset,
			"texture_size": Vector2(uv_size),
		}
		if total_weight > 0.0:
			result.merge({
				"centroid_from_baseline": glyph_offset + weighted_sum / total_weight,
				"weight": total_weight,
			})
	if result.is_empty():
		var glyph_size: Vector2 = text_server.font_get_glyph_size(
			font_rid,
			cache_size,
			glyph_index
		)
		if glyph_size.x > 0.0 and glyph_size.y > 0.0:
			result = {
				"centroid_from_baseline": glyph_offset + glyph_size * 0.5,
				"weight": glyph_size.x * glyph_size.y,
			}
	_glyph_texture_cache[cache_key] = result
	return result


func _centering_translation() -> Vector2:
	if _has_ink_centroid:
		return size * 0.5 - _uncentered_ink_centroid
	return size * 0.5 - _uncentered_ink_bounds.get_center()
