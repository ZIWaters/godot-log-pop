extends Object


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
		result += text.substr(pos, m.get_start() - pos)
		var first: String = m.get_string(1).split(";")[0]
		if color_map.has(first):
			if first == "0" or first == "39":
				result += str(color_map[first])
			else:
				result += "[color=%s]" % color_map[first]
		elif style_map.has(first):
			result += str(style_map[first])
		pos = m.get_end()
	result += text.substr(pos)

	var collapse := RegEx.new()
	collapse.compile("(\\[/color\\])+")
	return collapse.sub(result, "[/color]", true)
