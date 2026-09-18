extends Object


## Matches push_error / push_warning trace chrome in log_handler.
const COLOR_STACK := "#999"
const COLOR_ERROR := "#f54"
const COLOR_WARNING := "#fd4"


## Replace ASCII brackets so RichTextLabel never treats log text as BBCode tags.
static func escape_bbcode(text: String) -> String:
	return text.replace("[", "［").replace("]", "］")


## C# "   at Foo...", Godot push_error "at: func" / indented "at:".
static func is_stack_frame_line(line: String) -> bool:
	var t := line.lstrip(" \t")
	return t.begins_with("at ") or t.begins_with("at:")


## Body lines use accent (empty = leave as-is); contiguous stack frames share one COLOR_STACK wrap.
static func colorize_body_and_stack(text: String, accent: String = "") -> String:
	# Normalize newlines; strip trailing so a final \\n does not become a blank row after [/color].
	text = text.replace("\r\n", "\n").replace("\r", "\n").strip_edges(false, true)
	var lines := text.split("\n")
	var out: PackedStringArray = []
	var i := 0
	while i < lines.size():
		var line: String = lines[i]
		if is_stack_frame_line(line):
			var stack_lines: PackedStringArray = []
			while i < lines.size():
				var s: String = lines[i]
				if is_stack_frame_line(s):
					stack_lines.append(s)
					i += 1
				elif s.is_empty():
					# Drop blank lines between/after frames inside a stack block.
					i += 1
				else:
					break
			out.append("[color=%s]%s[/color]" % [COLOR_STACK, "\n".join(stack_lines)])
			continue
		if line.is_empty() or accent.is_empty():
			out.append(line)
		else:
			out.append("[color=%s]%s[/color]" % [accent, line])
		i += 1
	return "\n".join(out)


## True if BBCode already contains a gray stack block (stream or push_error).
static func has_stack_chrome(bbcode: String) -> bool:
	return bbcode.contains("[color=%s]" % COLOR_STACK)


## If message is a single outer [color=X]...[/color], return [X, inner]; else ["", original].
static func unwrap_outer_color(text: String) -> Array:
	var stripped := text.strip_edges(false, true)
	if not stripped.begins_with("[color="):
		return ["", text]
	var close := stripped.rfind("[/color]")
	if close < 0 or close + "[/color]".length() != stripped.length():
		return ["", text]
	var color_end := stripped.find("]")
	if color_end < 0:
		return ["", text]
	var accent: String = stripped.substr("[color=".length(), color_end - "[color=".length())
	var inner: String = stripped.substr(color_end + 1, close - color_end - 1)
	return [accent, inner]


static func is_warning_accent(accent: String) -> bool:
	var a := accent.to_lower()
	return a in ["yellow", "orange", COLOR_WARNING, "#fd4", "#ff5", "#ff0", "#ffff00"]


## Match push_error / push_warning: bold ERROR:/WARNING: on the first body line.
## Strips a leading plain "Error:"/"Warning:" so GDU.PrintWarn does not double up.
static func apply_stream_level_prefix(body: String, kind: String) -> String:
	var label := "ERROR:" if kind == "error" else "WARNING:"
	body = body.replace("\r\n", "\n").replace("\r", "\n")
	var lines := body.split("\n")
	if lines.is_empty():
		return "[b]%s[/b]" % label
	var first: String = lines[0].strip_edges()
	for p: String in ["WARNING:", "Warning:", "ERROR:", "Error:"]:
		if first.begins_with(p):
			first = first.substr(p.length()).strip_edges()
			break
	lines[0] = ("[b]%s[/b] %s" % [label, first]) if not first.is_empty() else ("[b]%s[/b]" % label)
	return "\n".join(lines)


## printerr / print_rich / plain print: unwrap PrintRich color if present, else ANSI → BBCode,
## then ERROR:/WARNING: prefix when applicable, accent body + gray stack frames.
static func format_stream_message(message: String, default_accent: String = "") -> String:
	var unwrapped: Array = unwrap_outer_color(message)
	var accent := default_accent
	var body: String
	if str(unwrapped[0]) != "":
		accent = str(unwrapped[0])
		body = escape_bbcode(str(unwrapped[1]))
	else:
		body = convert_ansi_to_bbcode(message)

	var kind := ""
	if accent == COLOR_ERROR or default_accent == COLOR_ERROR:
		kind = "error"
		accent = COLOR_ERROR
	else:
		var head := body.strip_edges()
		if is_warning_accent(accent) or head.begins_with("Warning:") or head.begins_with("WARNING:"):
			kind = "warn"
			accent = COLOR_WARNING

	if kind != "":
		body = apply_stream_level_prefix(body, kind)

	return colorize_body_and_stack(body, accent)


static func convert_ansi_to_bbcode(text: String) -> String:
	if text.is_empty():
		return text

	var color_map := {
		"30": "black",
		"31": "red",
		"32": "green",
		"33": "yellow",
		"34": "blue",
		"35": "magenta",
		"36": "cyan",
		"37": "white",
		"90": "#555",
		"91": "#f55",
		"92": "#5f5",
		"93": "#ff5",
		"94": "#55f",
		"95": "#f5f",
		"96": "#5ff",
		"97": "#fff",
		"0": "[/color]",
		"39": "[/color]",
	}
	var style_map := {
		"1": "[b]",
		"22": "[/b]",
	}

	var regex := RegEx.new()
	regex.compile("\u001b\\[([0-9;]+)m")
	var result := ""
	var pos := 0
	for m in regex.search_all(text):
		result += escape_bbcode(text.substr(pos, m.get_start() - pos))
		var first: String = m.get_string(1).split(";")[0]
		if color_map.has(first):
			if first == "0" or first == "39":
				result += str(color_map[first])
			else:
				result += "[color=%s]" % color_map[first]
		elif style_map.has(first):
			result += str(style_map[first])
		pos = m.get_end()
	result += escape_bbcode(text.substr(pos))

	var collapse := RegEx.new()
	collapse.compile("(\\[/color\\])+")
	return collapse.sub(result, "[/color]", true)
