class_name ReadmeHelpController
extends Control

signal back_requested

const README_PATH: String = "res://README.md"
const Markdown = preload("res://scripts/readme_markdown.gd")
const BackdropScript = preload("res://scripts/main_menu_backdrop.gd")
const MENU_ARTWORK: Texture2D = preload("res://pics/main_menu_background_phone.png")
const ARTWORK_CLOTH_UV_RECT: Rect2 = Rect2(
	75.0 / 1024.0,
	129.0 / 1536.0,
	873.0 / 1024.0,
	1281.0 / 1536.0
)

var _anchors: Dictionary = {}

@onready var backdrop: Control = $Backdrop
@onready var background_artwork: TextureRect = $Artwork
@onready var parchment: Control = $Parchment
@onready var parchment_artwork: TextureRect = $Parchment/Artwork
@onready var body: PanelContainer = $Parchment/Body
@onready var document: RichTextLabel = $Parchment/Body/Margin/Layout/Document
@onready var back_button: Button = $BackButton


func _ready() -> void:
	background_artwork.texture = MENU_ARTWORK
	background_artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	body.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	document.meta_clicked.connect(_on_document_meta_clicked)
	back_button.pressed.connect(_on_back_pressed)
	resized.connect(_layout_page)
	_load_readme()
	_layout_page()


func _load_readme() -> void:
	if not FileAccess.file_exists(README_PATH):
		document.text = "[center][font_size=20]说明文件加载失败[/font_size][/center]"
		_anchors.clear()
		return
	var file := FileAccess.open(README_PATH, FileAccess.READ)
	if file == null:
		document.text = "[center][font_size=20]说明文件加载失败[/font_size][/center]"
		_anchors.clear()
		return
	var converted: Dictionary = Markdown.convert(file.get_as_text())
	file.close()
	document.text = String(converted.get("bbcode", ""))
	_anchors = (converted.get("anchors", {}) as Dictionary).duplicate()
	document.scroll_to_line(0)


func _on_document_meta_clicked(meta: Variant) -> void:
	var target: String = String(meta)
	if not target.begins_with(Markdown.INTERNAL_LINK_PREFIX):
		return
	var anchor_id: String = target.trim_prefix(Markdown.INTERNAL_LINK_PREFIX)
	if not _anchors.has(anchor_id):
		return
	document.scroll_to_line(int(_anchors[anchor_id]))


func _on_back_pressed() -> void:
	_vibrate(12)
	back_requested.emit()


func _layout_page() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	var artwork_rect: Rect2 = BackdropScript.fit_phone_artwork_rect(size)
	var safe_rect: Rect2 = BackdropScript.fit_safe_rect(size)
	backdrop.call("configure", artwork_rect)
	background_artwork.position = artwork_rect.position
	background_artwork.size = artwork_rect.size

	var horizontal_inset: float = clampf(safe_rect.size.x * 0.096, 38.0, 54.0)
	var body_rect := Rect2(
		Vector2(
			safe_rect.position.x + horizontal_inset,
			safe_rect.position.y + safe_rect.size.y * 0.115
		),
		Vector2(
			safe_rect.size.x - horizontal_inset * 2.0,
			safe_rect.size.y * 0.775
		)
	)
	var parchment_size := Vector2(
		body_rect.size.x / ARTWORK_CLOTH_UV_RECT.size.x,
		body_rect.size.y / ARTWORK_CLOTH_UV_RECT.size.y
	)
	parchment.position = body_rect.position - parchment_size * ARTWORK_CLOTH_UV_RECT.position
	parchment.size = parchment_size
	body.position = body_rect.position - parchment.position
	body.size = body_rect.size
	parchment_artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var button_size: float = clampf(safe_rect.size.x * 0.085, 42.0, 48.0)
	back_button.size = Vector2(button_size, button_size)
	back_button.position = Vector2(
		safe_rect.end.x - button_size - 14.0,
		safe_rect.position.y + 14.0
	)


func debug_get_document_text() -> String:
	return document.get_parsed_text()


func debug_get_anchor_line(anchor_id: String) -> int:
	return int(_anchors.get(anchor_id, -1))


func _vibrate(duration_ms: int) -> void:
	if duration_ms > 0 and OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms)
