extends Node

## Fired at most once per idle flush after one or more logs were added.
signal log_added
## Fired at most once per idle flush if any error-level log was added.
signal error_logged

const MAX_STORED_LOGS := 2000

var _logs: Array[Dictionary] = []
var _logger: CustomLogger
var _notify_pending := false
var _needs_rebuild := false
var _had_error_in_batch := false


# Custom loggers must be thread-safe, as they may be called from non-main threads.
# We use call_deferred() to ensure _logs is modified from the main thread.
class CustomLogger extends Logger:
	var handler: Node

	func _log_message(message: String, error: bool) -> void:
		if handler == null:
			return
		handler.call_deferred("_on_log_capture", "error" if error else "info", message)

	func _log_error(
			function: String,
			file: String,
			line: int,
			code: String,
			rationale: String,
			_editor_notify: bool,
			error_type: int,
			script_backtraces: Array[ScriptBacktrace]
	) -> void:
		if handler == null:
			return

		var prefix: String = ""
		# The column at which to print the trace. Should match the length of the
		# unformatted text above it.
		var trace_indent := 0

		match error_type:
			ERROR_TYPE_ERROR:
				prefix = "[color=#f54][b]ERROR:[/b]"
				trace_indent = 6
			ERROR_TYPE_WARNING:
				prefix = "[color=#fd4][b]WARNING:[/b]"
				trace_indent = 8
			ERROR_TYPE_SCRIPT:
				prefix = "[color=#f4f][b]SCRIPT ERROR:[/b]"
				trace_indent = 13
			ERROR_TYPE_SHADER:
				prefix = "[color=#4bf][b]SHADER ERROR:[/b]"
				trace_indent = 13

		var trace: String = "%*s %s (%s:%s)" % [trace_indent, "at:", function, file, line]
		var script_backtraces_text: String = ""
		for backtrace in script_backtraces:
			script_backtraces_text += _format_limited_backtrace(backtrace, trace_indent - 3)

		var message: String = "%s %s %s[/color]\n[color=#999]%s[/color]\n[color=#999]%s[/color]" % [
			prefix,
			code,
			rationale,
			trace,
			script_backtraces_text,
		]

		var level := "warn" if error_type == ERROR_TYPE_WARNING else "error"
		handler.call_deferred("_on_log_capture", level, message)

	func _format_limited_backtrace(bt: ScriptBacktrace, indent_all: int) -> String:
		if bt.is_empty():
			return ""
		var indent := " ".repeat(maxi(indent_all, 0))
		var frame_indent := " ".repeat(maxi(indent_all, 0) + 4)
		var text := "%s%s backtrace (most recent call first):\n" % [indent, bt.get_language_name()]
		var count := mini(bt.get_frame_count(), 3)
		for i in count:
			text += "%s[%d] %s (%s:%d)\n" % [
				frame_indent,
				i,
				bt.get_frame_function(i),
				bt.get_frame_file(i),
				bt.get_frame_line(i),
			]
		return text


# Use _init() to register the logger as early as possible.
func _init() -> void:
	_logger = CustomLogger.new()
	_logger.handler = self
	OS.add_logger(_logger)


func _exit_tree() -> void:
	if _logger != null:
		OS.remove_logger(_logger)
		_logger.handler = null
		_logger = null


func get_log_count() -> int:
	return _logs.size()


func get_log(index: int) -> Dictionary:
	return _logs[index]


func consume_needs_rebuild() -> bool:
	var value := _needs_rebuild
	_needs_rebuild = false
	return value


func _on_log_capture(level: String, message: String) -> void:
	_add_log(level, message)


func _add_log(type: String, message: String) -> void:
	var t := Time.get_time_dict_from_system()
	_logs.append({
		"type": type,
		"message": message,
		"time": "%02d:%02d:%02d" % [t["hour"], t["minute"], t["second"]],
	})
	if type == "error":
		_had_error_in_batch = true

	while _logs.size() > MAX_STORED_LOGS:
		_logs.remove_at(0)
		_needs_rebuild = true

	if not _notify_pending:
		_notify_pending = true
		call_deferred("_flush_log_added")


func _flush_log_added() -> void:
	_notify_pending = false
	var had_error := _had_error_in_batch
	_had_error_in_batch = false
	log_added.emit()
	if had_error:
		error_logged.emit()


func get_filtered_logs(types: Array[String], filter_text: String, max_logs: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count := 0
	for i in range(_logs.size() - 1, -1, -1):
		if count >= max_logs:
			break
		var entry: Dictionary = _logs[i]
		if not types.has(str(entry["type"])):
			continue
		if filter_text.is_empty() or str(entry["message"]).findn(filter_text) >= 0:
			result.insert(0, entry)
			count += 1
	return result
