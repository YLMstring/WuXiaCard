class_name TutorialController
extends Control

signal completion_requested

const TUTORIAL_TEXTURE_PATHS: Array[String] = [
	"res://pics/tutorial/tutorial_01.png",
	"res://pics/tutorial/tutorial_02.png",
	"res://pics/tutorial/tutorial_03.png",
	"res://pics/tutorial/tutorial_04.png",
	"res://pics/tutorial/tutorial_05.png",
	"res://pics/tutorial/tutorial_06.png",
	"res://pics/tutorial/tutorial_07.png",
	"res://pics/tutorial/tutorial_08.png",
	"res://pics/tutorial/tutorial_09.png",
	"res://pics/tutorial/tutorial_10.png",
]

@onready var page_texture: TextureRect = $PageTexture
@onready var advance_button: Button = $AdvanceButton
@onready var notice_label: Label = $Notice

var _current_page_index: int = 0
var _completion_request_pending: bool = false
var _page_textures: Array[Texture2D] = []


func _ready() -> void:
	_load_page_textures()
	advance_button.pressed.connect(_on_advance_pressed)
	_show_page(0)


func show_save_error(message: String = "保存失败，请重试") -> void:
	_completion_request_pending = false
	advance_button.disabled = false
	notice_label.text = message
	notice_label.visible = not message.is_empty()


func debug_get_current_page_index() -> int:
	return _current_page_index


func debug_get_page_count() -> int:
	return TUTORIAL_TEXTURE_PATHS.size()


func debug_get_current_texture() -> Texture2D:
	return page_texture.texture


func debug_is_completion_request_pending() -> bool:
	return _completion_request_pending


func _on_advance_pressed() -> void:
	if _completion_request_pending:
		return
	notice_label.visible = false
	if _current_page_index < _page_textures.size() - 1:
		_show_page(_current_page_index + 1)
		return
	_completion_request_pending = true
	advance_button.disabled = true
	completion_requested.emit()


func _show_page(page_index: int) -> void:
	if _page_textures.is_empty():
		return
	_current_page_index = clampi(page_index, 0, _page_textures.size() - 1)
	page_texture.texture = _page_textures[_current_page_index]


func _load_page_textures() -> void:
	_page_textures.clear()
	for path: String in TUTORIAL_TEXTURE_PATHS:
		var texture := ResourceLoader.load(path) as Texture2D
		if texture == null:
			push_error("Tutorial page could not be loaded: %s" % path)
			continue
		_page_textures.append(texture)
