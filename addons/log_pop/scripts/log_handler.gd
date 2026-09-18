extends Node

## Fired at most once per idle flush after one or more logs were added.
signal log_added
## Fired at most once per idle flush if any error-level log was added.
signal error_logged

const LogPopUtils = preload("log_utils.gd")
const MAX_STORED_LOGS := 2000

var _logs: Array[Dictionary] = []
var _logger: CustomLogger
var _notify_pending := false
var _needs_rebuild := false
var _had_error_in_batch := false
## True while OS.add_logger is active. Cleared on exit_tree (incl. parent Reparent).
var _logger_registered := false


# Logger callbacks may run off the main thread — never touch Node from here.
# Queue on this RefCounted Logger; handler drains on the main thread.
class CustomLogger extends Logger:
	var _mutex := Mutex.new()
	var _pending: Array = [] # { "level": String, "message": String }

	func steal_pending() -> Array:
		_mutex.lock()
		var batch: Array = _pending.duplicate()
		_pending.clear()
		_mutex.unlock()
		return batch

	func _enqueue(level: String, message: String) -> void:
		_mutex.lock()
		_pending.append({ "level": level, "message": message })
		_mutex.unlock()

	func _log_message(message: String, error: bool) -> void:
		_enqueue("error" if error else "info", message)

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
		var prefix: String = ""
		var trace_indent := 0

		match error_type:
			ERROR_TYPE_ERROR:
				prefix = "[color=%s][b]ERROR:[/b]" % LogPopUtils.COLOR_ERROR
				trace_indent = 6
			ERROR_TYPE_WARNING:
				prefix = "[color=%s][b]WARNING:[/b]" % LogPopUtils.COLOR_WARNING
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
			script_backtraces_text += _format_backtrace(backtrace, trace_indent - 3)

		# Engine errors build their own layout; stack blocks share COLOR_STACK with stream messages.
		var stack := "[color=%s]%s[/color]" % [LogPopUtils.COLOR_STACK, trace]
		if not script_backtraces_text.strip_edges().is_empty():
			stack += "\n[color=%s]%s[/color]" % [LogPopUtils.COLOR_STACK, script_backtraces_text.strip_edges(false, true)]
		var message: String = "%s %s %s[/color]\n%s\n" % [prefix, code, rationale, stack]

		var level := "warn" if error_type == ERROR_TYPE_WARNING else "error"
		_enqueue(level, message)

	func _format_backtrace(bt: ScriptBacktrace, indent_all: int) -> String:
		if bt.is_empty():
			return ""
		var indent := " ".repeat(maxi(indent_all, 0))
		var frame_indent := " ".repeat(maxi(indent_all, 0) + 4)
		var text := "%s%s backtrace (most recent call first):\n" % [indent, bt.get_language_name()]
		for i in bt.get_frame_count():
			text += "%s[%d] %s (%s:%d)\n" % [
				frame_indent,
				i,
				bt.get_frame_function(i),
				bt.get_frame_file(i),
				bt.get_frame_line(i),
			]
		return text


func _init() -> void:
	_register_logger()


func _enter_tree() -> void:
	# Reparent calls exit_tree then enter_tree without _ready — re-register logger.
	_register_logger()
	set_process(true)


func _ready() -> void:
	set_process(true)


func _exit_tree() -> void:
	# Unregister from OS only; keep CustomLogger + pending queue across reparent.
	_unregister_logger_from_os()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_unregister_logger_from_os()
		_logger = null


func _process(_delta: float) -> void:
	_drain_pending_queue()


func _drain_pending_queue() -> void:
	if _logger == null:
		return
	var batch: Array = _logger.steal_pending()
	for item in batch:
		_on_log_capture(str(item["level"]), str(item["message"]))


func _register_logger() -> void:
	if _logger == null:
		_logger = CustomLogger.new()
	if _logger_registered:
		return
	OS.add_logger(_logger)
	_logger_registered = true


func _unregister_logger_from_os() -> void:
	if _logger != null and _logger_registered:
		OS.remove_logger(_logger)
		_logger_registered = false


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


# =============================================================================
# [DISABLED] Heartbeat self-heal / ensure_logger() — optional fallback, off by default.
#
# Purpose: if the engine console still prints but the custom Logger stops receiving
# callbacks, probe during quiet periods and re-register (remove + new + add_logger),
# or call ensure_logger() after known-risky work.
#
# To re-enable: uncomment this block, call _process_heartbeat(delta) from _process,
# and reconnect capture_failed in log_pop.gd if you want the overlay on failure.
#
# signal capture_failed
# const HEARTBEAT_PREFIX := "[LogPopHeartbeat]"
# const HEARTBEAT_INTERVAL_SEC := 15.0
# const HEARTBEAT_MISS_LIMIT := 2
# const REREGISTER_COOLDOWN_SEC := 3.0
# var _capture_count := 0
# var _last_seen_capture_count := 0
# var _heartbeat_timer := 0.0
# var _heartbeat_waiting := false
# var _heartbeat_expect_count := 0
# var _heartbeat_misses := 0
# var _reregister_cooldown := 0.0
# var _capture_failed_emitted := false
# var _self_heal_enabled := true
#
# func _process_heartbeat(delta: float) -> void:
# 	if not _self_heal_enabled:
# 		return
# 	if _reregister_cooldown > 0.0:
# 		_reregister_cooldown = maxf(0.0, _reregister_cooldown - delta)
# 	if _heartbeat_waiting and _capture_count > _heartbeat_expect_count:
# 		_heartbeat_waiting = false
# 		_heartbeat_misses = 0
# 		_capture_failed_emitted = false
# 	_heartbeat_timer += delta
# 	if _heartbeat_timer < HEARTBEAT_INTERVAL_SEC:
# 		return
# 	_heartbeat_timer = 0.0
# 	_on_heartbeat_tick()
#
# func _on_heartbeat_tick() -> void:
# 	if _capture_count > _last_seen_capture_count:
# 		_last_seen_capture_count = _capture_count
# 		_heartbeat_waiting = false
# 		_heartbeat_misses = 0
# 		_capture_failed_emitted = false
# 		return
# 	if _heartbeat_waiting:
# 		_heartbeat_waiting = false
# 		_heartbeat_misses += 1
# 		if _heartbeat_misses >= HEARTBEAT_MISS_LIMIT:
# 			_try_self_heal()
# 		return
# 	_heartbeat_expect_count = _capture_count
# 	_heartbeat_waiting = true
# 	print("%s %d" % [HEARTBEAT_PREFIX, Time.get_ticks_msec()])
#
# func _try_self_heal() -> void:
# 	if _reregister_cooldown > 0.0:
# 		return
# 	_reregister_cooldown = REREGISTER_COOLDOWN_SEC
# 	_reregister_logger()
# 	_heartbeat_expect_count = _capture_count
# 	_heartbeat_waiting = true
# 	_heartbeat_misses = 0
# 	print("%s reregister %d" % [HEARTBEAT_PREFIX, Time.get_ticks_msec()])
# 	call_deferred("_check_heal_result")
#
# func _check_heal_result() -> void:
# 	var tree := get_tree()
# 	if tree == null:
# 		return
# 	await tree.create_timer(0.4).timeout
# 	if not is_inside_tree():
# 		return
# 	if _capture_count > _heartbeat_expect_count:
# 		_heartbeat_waiting = false
# 		_heartbeat_misses = 0
# 		_capture_failed_emitted = false
# 		return
# 	if not _capture_failed_emitted:
# 		_capture_failed_emitted = true
# 		_add_log("warn", "[LogPop] Custom Logger capture appears dead after re-register.")
# 		capture_failed.emit()
#
# func _reregister_logger() -> void:
# 	_unregister_logger_from_os()
# 	_logger = CustomLogger.new()
# 	_register_logger()
#
# func ensure_logger() -> void:
# 	_reregister_logger()
# 	_heartbeat_misses = 0
# 	_heartbeat_waiting = false
# 	_capture_failed_emitted = false
#
# func get_capture_count() -> int:
# 	return _capture_count
#
# # In _on_log_capture, also restore:
# # _capture_count += 1
# # _last_seen_capture_count = _capture_count
# # if message.contains(HEARTBEAT_PREFIX): ... return
# =============================================================================
