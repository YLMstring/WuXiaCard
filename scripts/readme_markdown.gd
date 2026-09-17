class_name ReadmeMarkdown
extends RefCounted

const INTERNAL_LINK_PREFIX: String = "section:"
const HEADING_SIZES: Array[int] = [30, 24, 20, 18, 17, 16]
const MEDIUM_EMPHASIS_OPEN: String = "[outline_size=1][outline_color=#38261a]"
const MEDIUM_EMPHASIS_CLOSE: String = "[/outline_color][/outline_size]"


static func convert(markdown: String) -> Dictionary:
	var source: String = markdown.replace("\r\n", "\n").replace("\r", "\n")
	var lines: PackedStringArray = source.split("\n", true)
	var output: Array[String] = []
	var anchors: Dictionary = {}
	var pending_anchors: Array[String] = []
	var rendered_line: int = 0
	var in_code_block: bool = false
	var code_lines: Array[String] = []
	var line_index: int = 0

	while line_index < lines.size():
		var raw_line: String = lines[line_index]
		var stripped: String = raw_line.strip_edges()
		if stripped.begins_with("```"):
			if in_code_block:
				_bind_pending_anchors(anchors, pending_anchors, rendered_line)
				var code_text: String = "\n".join(code_lines)
				output.append(
					"[bgcolor=#ead7ab][font_size=13][color=#3f3024]%s[/color][/font_size][/bgcolor]"
					% _escape_bbcode(code_text)
				)
				rendered_line += maxi(1, code_lines.size())
				code_lines.clear()
				in_code_block = false
			else:
				in_code_block = true
			line_index += 1
			continue
		if in_code_block:
			code_lines.append(raw_line)
			line_index += 1
			continue

		var anchor_id: String = _html_anchor_id(stripped)
		if not anchor_id.is_empty():
			pending_anchors.append(anchor_id)
			line_index += 1
			continue

		var heading_level: int = _heading_level(stripped)
		if heading_level > 0:
			if not output.is_empty() and not output.back().is_empty():
				output.append("")
				rendered_line += 1
			_bind_pending_anchors(anchors, pending_anchors, rendered_line)
			var heading_text: String = stripped.substr(heading_level + 1)
			var font_size: int = HEADING_SIZES[mini(heading_level - 1, HEADING_SIZES.size() - 1)]
			output.append(
				"[font_size=%d]%s[color=#38261a]%s[/color]%s[/font_size]"
				% [
					font_size,
					MEDIUM_EMPHASIS_OPEN,
					_format_inline(heading_text),
					MEDIUM_EMPHASIS_CLOSE,
				]
			)
			rendered_line += 1
			line_index += 1
			continue

		_bind_pending_anchors(anchors, pending_anchors, rendered_line)
		if stripped.is_empty():
			if output.is_empty() or output.back().is_empty():
				line_index += 1
				continue
			output.append("")
			rendered_line += 1
		elif stripped == "---":
			output.append("[color=#98734c]────────────────────────[/color]")
			rendered_line += 1
		elif _is_table_row(stripped):
			if _is_table_separator(stripped):
				line_index += 1
				continue
			var table_text: String = _table_row_text(stripped)
			output.append("[font_size=13][color=#4a3929]%s[/color][/font_size]" % _format_inline(table_text))
			rendered_line += 1
		elif stripped.begins_with("- ") or stripped.begins_with("* "):
			var indentation: int = _leading_space_count(raw_line) / 2
			var prefix: String = ""
			for _depth: int in range(indentation):
				prefix += "　"
			output.append("%s• %s" % [prefix, _format_inline(stripped.substr(2))])
			rendered_line += 1
		elif _is_ordered_list_item(stripped):
			output.append(_format_inline(stripped))
			rendered_line += 1
		else:
			output.append(_format_inline(stripped))
			rendered_line += 1
		line_index += 1

	if in_code_block:
		_bind_pending_anchors(anchors, pending_anchors, rendered_line)
		output.append(
			"[bgcolor=#ead7ab][font_size=13][color=#3f3024]%s[/color][/font_size][/bgcolor]"
			% _escape_bbcode("\n".join(code_lines))
		)
	_bind_pending_anchors(anchors, pending_anchors, rendered_line)
	return {
		"bbcode": "\n".join(output),
		"anchors": anchors,
	}


static func _bind_pending_anchors(
	anchors: Dictionary,
	pending_anchors: Array[String],
	rendered_line: int
) -> void:
	for anchor_id: String in pending_anchors:
		anchors[anchor_id] = rendered_line
	pending_anchors.clear()


static func _html_anchor_id(line: String) -> String:
	const PREFIX: String = "<a id=\""
	if not line.begins_with(PREFIX):
		return ""
	var closing_quote: int = line.find("\"", PREFIX.length())
	if closing_quote < 0:
		return ""
	return line.substr(PREFIX.length(), closing_quote - PREFIX.length())


static func _heading_level(line: String) -> int:
	var level: int = 0
	while level < line.length() and line[level] == "#" and level < 6:
		level += 1
	if level == 0 or level >= line.length() or line[level] != " ":
		return 0
	return level


static func _leading_space_count(line: String) -> int:
	var count: int = 0
	while count < line.length() and line[count] == " ":
		count += 1
	return count


static func _is_ordered_list_item(line: String) -> bool:
	var separator: int = line.find(". ")
	if separator <= 0:
		return false
	return line.substr(0, separator).is_valid_int()


static func _is_table_row(line: String) -> bool:
	return line.begins_with("|") and line.ends_with("|") and line.count("|") >= 2


static func _is_table_separator(line: String) -> bool:
	var residue: String = line
	for removable: String in ["|", "-", ":", " ", "\t"]:
		residue = residue.replace(removable, "")
	return residue.is_empty()


static func _table_row_text(line: String) -> String:
	var cells: PackedStringArray = line.trim_prefix("|").trim_suffix("|").split("|", true)
	var cleaned: Array[String] = []
	for cell: String in cells:
		cleaned.append(cell.strip_edges())
	return "　｜　".join(cleaned)


static func _format_inline(source: String) -> String:
	var result: String = ""
	var cursor: int = 0
	while cursor < source.length():
		if source.substr(cursor, 2) == "**":
			var bold_end: int = source.find("**", cursor + 2)
			if bold_end >= 0:
				result += "%s%s%s" % [
					MEDIUM_EMPHASIS_OPEN,
					_escape_bbcode(source.substr(cursor + 2, bold_end - cursor - 2)),
					MEDIUM_EMPHASIS_CLOSE,
				]
				cursor = bold_end + 2
				continue
		if source[cursor] == "`":
			var code_end: int = source.find("`", cursor + 1)
			if code_end >= 0:
				result += "[color=#6b3d2a]%s[/color]" % _escape_bbcode(source.substr(cursor + 1, code_end - cursor - 1))
				cursor = code_end + 1
				continue
		if source[cursor] == "[":
			var label_end: int = source.find("](", cursor + 1)
			if label_end >= 0:
				var target_end: int = source.find(")", label_end + 2)
				if target_end >= 0:
					var label: String = source.substr(cursor + 1, label_end - cursor - 1)
					var target: String = source.substr(label_end + 2, target_end - label_end - 2)
					if target.begins_with("#"):
						result += "[url=%s%s][color=#7a482d]%s[/color][/url]" % [
							INTERNAL_LINK_PREFIX,
							_escape_bbcode(target.substr(1)),
							_escape_bbcode(label),
						]
					else:
						result += _escape_bbcode(label)
					cursor = target_end + 1
					continue
		result += _escape_bbcode(source[cursor])
		cursor += 1
	return result


static func _escape_bbcode(value: String) -> String:
	return value.replace("[", "\uE000").replace("]", "\uE001").replace("\uE000", "[lb]").replace("\uE001", "[rb]")
