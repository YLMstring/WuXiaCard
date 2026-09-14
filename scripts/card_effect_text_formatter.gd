class_name CardEffectTextFormatter
extends RefCounted

const EMPHASIS_COLOR: String = "#8c5e33"

const EXACT_PREFIXES: Array[String] = [
	"锁定，指定：",
	"锁定、指定：",
	"对局开始时，",
	"双方回合开始时，",
	"双方回合结束时，",
	"回合开始和结束时，",
	"回合开始时，",
	"回合结束时，",
	"对手招式进场后，",
	"对手招式进场时，",
	"敌方进场后，",
	"敌方进场时，",
	"其它友方进场后，",
	"其它友方进场时，",
	"友方进场后，",
	"友方进场时，",
	"我进场前，",
	"我进场时，",
	"我进场后，",
	"进场前，",
	"进场时，",
	"进场后，",
	"敌方攻击后，",
	"其它友方攻击后，",
	"友方攻击后，",
	"我攻击时，",
	"我攻击后，",
	"攻击时，",
	"攻击后，",
	"我被攻击时，",
	"友方被攻击时，",
	"被攻击时，",
	"我翻面前，",
	"我翻面后，",
	"友方翻面前，",
	"友方翻面后，",
	"敌方翻面后，",
	"翻面前，",
	"翻面后，",
	"我被丢弃后，",
	"被丢弃后，",
	"我被移除前，",
	"我被移除后，",
	"被移除前，",
	"被移除后，",
	"锁定：",
	"指定：",
]

const OPEN_TO_CLOSE: Dictionary = {
	"【": "】",
	"（": "）",
	"(": ")",
	"“": "”",
	"‘": "’",
}

const CLOSING_CHARS: Array[String] = ["】", "）", ")", "”", "’"]


static func format_bbcode(raw_text: String) -> String:
	var normalized: String = normalize_plain_text(raw_text)
	if normalized.is_empty():
		return ""
	var split_result: Dictionary = _split_outer_paragraphs(normalized)
	if not bool(split_result.get("valid", false)):
		return _escape_bbcode(normalized)
	var paragraphs: Array = split_result.get("paragraphs", [])
	var formatted_parts: PackedStringArray = []
	for paragraph_value: Variant in paragraphs:
		var paragraph: String = String(paragraph_value)
		if paragraph.is_empty():
			continue
		formatted_parts.append("[p]%s[/p]" % _format_paragraph_content(paragraph))
	var formatted: String = "".join(formatted_parts)
	if not _markup_preserves_source(formatted, normalized):
		return _escape_bbcode(normalized)
	return formatted


static func normalize_plain_text(text: String) -> String:
	return text.replace("\r\n", "\n").replace("\r", "\n")


static func _split_outer_paragraphs(text: String) -> Dictionary:
	var paragraphs: Array[String] = []
	var stack: Array[String] = []
	var current: String = ""
	var pending_parenthetical_boundary: bool = false
	var index: int = 0
	while index < text.length():
		var character: String = text.substr(index, 1)
		if not _advance_structure(stack, character):
			return {"valid": false, "paragraphs": []}
		current += character
		if character == "\n" and stack.is_empty():
			if current == "\n" and not paragraphs.is_empty():
				paragraphs[paragraphs.size() - 1] += current
			else:
				paragraphs.append(current)
			current = ""
			pending_parenthetical_boundary = false
		elif character == "。" and stack.is_empty():
			var next_character: String = (
				text.substr(index + 1, 1)
				if index + 1 < text.length()
				else ""
			)
			if next_character in ["（", "("]:
				pending_parenthetical_boundary = true
			else:
				paragraphs.append(current)
				current = ""
				pending_parenthetical_boundary = false
		elif (
			pending_parenthetical_boundary
			and character in ["）", ")"]
			and stack.is_empty()
		):
			paragraphs.append(current)
			current = ""
			pending_parenthetical_boundary = false
		index += 1
	if not stack.is_empty():
		return {"valid": false, "paragraphs": []}
	if not current.is_empty():
		paragraphs.append(current)
	return {"valid": true, "paragraphs": paragraphs}


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


static func _format_paragraph_content(paragraph: String) -> String:
	var formatted: String = ""
	var bracket_depth: int = 0
	var at_segment_start: bool = true
	var index: int = 0
	while index < paragraph.length():
		if at_segment_start:
			var prefix: String = _matching_prefix(paragraph, index)
			if not prefix.is_empty():
				formatted += _emphasize(prefix)
				index += prefix.length()
				continue
			at_segment_start = false
		var character: String = paragraph.substr(index, 1)
		if character == "【":
			formatted += "【[br][indent]"
			bracket_depth += 1
			at_segment_start = true
		elif character == "】":
			if bracket_depth > 0:
				formatted += "[/indent]】"
				bracket_depth -= 1
			else:
				formatted += "】"
			at_segment_start = false
		elif character == "。" and bracket_depth > 0:
			formatted += "。"
			var next_character: String = (
				paragraph.substr(index + 1, 1)
				if index + 1 < paragraph.length()
				else ""
			)
			if next_character != "】":
				formatted += "[br]"
				at_segment_start = true
		else:
			formatted += _escape_character(character)
		index += 1
	while bracket_depth > 0:
		formatted += "[/indent]"
		bracket_depth -= 1
	return formatted


static func _matching_prefix(text: String, start_index: int) -> String:
	for prefix: String in EXACT_PREFIXES:
		if text.substr(start_index, prefix.length()) == prefix:
			return prefix
	return ""


static func _emphasize(text: String) -> String:
	return "[color=%s][b]%s[/b][/color]" % [EMPHASIS_COLOR, _escape_bbcode(text)]


static func _escape_bbcode(text: String) -> String:
	var escaped: String = ""
	for index: int in range(text.length()):
		escaped += _escape_character(text.substr(index, 1))
	return escaped


static func _escape_character(character: String) -> String:
	if character == "[":
		return "[lb]"
	if character == "]":
		return "[rb]"
	return character


static func _markup_preserves_source(bbcode: String, source: String) -> bool:
	var rich_text := RichTextLabel.new()
	rich_text.bbcode_enabled = true
	rich_text.text = bbcode
	var parsed: String = rich_text.get_parsed_text()
	rich_text.free()
	return _remove_generated_layout(parsed) == normalize_plain_text(source)


static func _remove_generated_layout(text: String) -> String:
	return text.replace("\r", "").replace("\t", "")
