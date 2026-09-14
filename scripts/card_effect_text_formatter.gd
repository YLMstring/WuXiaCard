class_name CardEffectTextFormatter
extends RefCounted

const OPEN_TO_CLOSE: Dictionary = {
	"【": "】",
	"（": "）",
	"(": ")",
	"“": "”",
	"‘": "’",
}

const CLOSING_CHARS: Array[String] = ["】", "）", ")", "”", "’"]


static func split_paragraphs(raw_text: String) -> Array[String]:
	var normalized: String = normalize_plain_text(raw_text)
	if normalized.is_empty():
		return []

	var paragraphs: Array[String] = []
	var stack: Array[String] = []
	var current: String = ""
	for index: int in range(normalized.length()):
		var character: String = normalized.substr(index, 1)
		if character == "\n" and stack.is_empty():
			_append_nonempty(paragraphs, current)
			current = ""
			continue
		if not _advance_structure(stack, character):
			return _single_paragraph(normalized)
		current += character
		if character == "。" and stack.is_empty():
			_append_nonempty(paragraphs, current)
			current = ""

	if not stack.is_empty():
		return _single_paragraph(normalized)
	_append_nonempty(paragraphs, current)
	if "".join(paragraphs) != normalized.replace("\n", ""):
		return _single_paragraph(normalized)
	return paragraphs


static func normalize_plain_text(text: String) -> String:
	return text.replace("\r\n", "\n").replace("\r", "\n")


static func _append_nonempty(paragraphs: Array[String], paragraph: String) -> void:
	if not paragraph.is_empty():
		paragraphs.append(paragraph)


static func _single_paragraph(text: String) -> Array[String]:
	var result: Array[String] = [text]
	return result


static func _advance_structure(stack: Array[String], character: String) -> bool:
	if character == "\"":
		if not stack.is_empty() and stack.back() == "\"":
			stack.pop_back()
		else:
			stack.append("\"")
		return true
	if OPEN_TO_CLOSE.has(character):
		stack.append(character)
		return true
	if character not in CLOSING_CHARS:
		return true
	if stack.is_empty():
		return false
	var opening: String = stack.pop_back()
	return String(OPEN_TO_CLOSE.get(opening, "")) == character
