extends CanvasLayer

const LogPopHandlerScript = preload("log_handler.gd")
const LogPopUtils = preload("log_utils.gd")

const DEFAULT_HISTORY_SIZE := 300

var _log_handler: LogPopHandlerScript

var _bg_rect: ColorRect
var _main_container: Control
var _type_selector: OptionButton
var _filter_input: LineEdit
var _close_btn: Button
var _open_logs_folder_btn: Button
var _cb_new_window: CheckButton
var _history_slider: HSlider
var _history_label: Label
var _font_slider: HSlider
var _font_label: Label
var _log_text: RichTextLabel

var _external_window: Window
var _prev_embed_subwindows := true

var _ui_ready := false
var _displayed_log_count := 0
var _refresh_pending := false


func init_ui(log_handler: LogPopHandlerScript) -> void:
	if _ui_ready:
		return
	_log_handler = log_handler
	_bind_nodes()
	_apply_default_settings()
	_connect_signals()
	_ui_ready = true
	_rebuild_display()


func _exit_tree() -> void:
	if _log_handler != null and _log_handler.log_added.is_connected(_on_log_added):
		_log_handler.log_added.disconnect(_on_log_added)


func _bind_nodes() -> void:
	_bg_rect = %BgRect
	_main_container = %MainContainer
	_type_selector = %TypeSelector
	_filter_input = %FilterInput
	_history_label = %HistoryLabel
	_history_slider = %HistorySlider
	_font_label = %FontLabel
	_font_slider = %FontSlider
	_cb_new_window = %DetachWindow
	_close_btn = %CloseBtn
	_open_logs_folder_btn = %OpenLogsFolderBtn
	_log_text = %LogText


func _apply_default_settings() -> void:
	_type_selector.selected = 0
	_history_slider.value = DEFAULT_HISTORY_SIZE
	_font_slider.value = 16
	_cb_new_window.set_pressed_no_signal(false)
	_apply_font_size(16)

	if not _is_desktop_platform():
		_cb_new_window.disabled = true
		_cb_new_window.tooltip_text = "Detach window mode is only supported on Windows, macOS and Linux"


func apply_export_settings(history_size: int, font_size: int, use_new_window: bool) -> void:
	_history_slider.value = history_size
	_history_label.text = "Max Logs: %d" % history_size
	_font_slider.value = font_size
	_font_label.text = "Font Size: %dpx" % font_size
	_apply_font_size(font_size)
	_cb_new_window.set_pressed_no_signal(use_new_window)


func apply_detached_if_requested() -> void:
	if _cb_new_window.button_pressed and _is_desktop_platform():
		_switch_to_window_mode()


func _apply_font_size(font_size: int) -> void:
	_log_text.add_theme_font_size_override("normal_font_size", font_size)
	_log_text.add_theme_font_size_override("bold_font_size", font_size)
	_log_text.add_theme_font_size_override("italics_font_size", font_size)
	_log_text.add_theme_font_size_override("bold_italics_font_size", font_size)
	_log_text.add_theme_font_size_override("mono_font_size", font_size)


func has_external_window() -> bool:
	return is_instance_valid(_external_window)


func toggle_visibility() -> void:
	if _should_use_external():
		if not is_instance_valid(_external_window):
			_switch_to_window_mode()
		else:
			_external_window.visible = not _external_window.visible
	else:
		visible = not visible


func ensure_visible() -> void:
	if _should_use_external():
		if not is_instance_valid(_external_window):
			_switch_to_window_mode()
		else:
			_external_window.visible = true
	else:
		visible = true


func _should_use_external() -> bool:
	return _cb_new_window != null and _cb_new_window.button_pressed and _is_desktop_platform()


func _is_desktop_platform() -> bool:
	return OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linux")


func _connect_signals() -> void:
	_close_btn.pressed.connect(_on_close_pressed)
	_open_logs_folder_btn.pressed.connect(_on_open_logs_folder_pressed)
	_cb_new_window.toggled.connect(_on_new_window_toggled)
	_history_slider.value_changed.connect(_on_history_changed)
	_font_slider.value_changed.connect(_on_font_changed)
	_filter_input.text_changed.connect(_on_filter_changed)
	_type_selector.item_selected.connect(func(_i: int) -> void: _rebuild_display())
	if _log_handler != null:
		_log_handler.log_added.connect(_on_log_added)


func _on_close_pressed() -> void:
	if is_instance_valid(_external_window):
		_external_window.hide()
	else:
		visible = false


func _on_open_logs_folder_pressed() -> void:
	var log_path := str(ProjectSettings.get_setting_with_override(&"debug/file_logging/log_path"))
	var log_dir := log_path.get_base_dir()
	OS.shell_open(ProjectSettings.globalize_path(log_dir))


func _on_new_window_toggled(pressed: bool) -> void:
	if not _is_desktop_platform():
		return
	if pressed:
		_switch_to_window_mode()
	else:
		_switch_to_overlay_mode()


func _switch_to_window_mode() -> void:
	if is_instance_valid(_external_window):
		_external_window.show()
		return
	_external_window = null

	var main_size := DisplayServer.window_get_size(DisplayServer.MAIN_WINDOW_ID)
	var new_size := Vector2i(int(main_size.x * 0.9), int(main_size.y * 0.9))
	new_size = new_size.max(Vector2i(800, 600))

	_prev_embed_subwindows = get_tree().root.gui_embed_subwindows
	get_tree().root.gui_embed_subwindows = false

	_external_window = Window.new()
	_external_window.title = "LogPop - Log Viewer"
	_external_window.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	_external_window.size = new_size
	_external_window.unresizable = false
	_external_window.always_on_top = false
	_external_window.close_requested.connect(_on_external_window_close)

	remove_child(_main_container)
	_bg_rect.hide()
	_external_window.add_child(_main_container)
	get_tree().root.add_child(_external_window)
	_external_window.show()


func _switch_to_overlay_mode() -> void:
	if not is_instance_valid(_external_window):
		_external_window = null
		return

	var win := _external_window
	_external_window = null

	if _main_container.get_parent() == win:
		win.remove_child(_main_container)

	# Hide first — Godot forbids changing gui_embed_subwindows while a child window is shown.
	win.hide()
	get_tree().root.gui_embed_subwindows = _prev_embed_subwindows
	win.queue_free()

	add_child(_main_container)
	_bg_rect.show()


func _on_external_window_close() -> void:
	# Keep detach mode; just hide so Ctrl+L / hotkey can reopen the same window.
	if is_instance_valid(_external_window):
		_external_window.hide()


func _on_history_changed(value: float) -> void:
	var int_val := int(value)
	_history_label.text = "Max Logs: %d" % int_val
	_rebuild_display()


func _on_font_changed(value: float) -> void:
	var int_val := int(value)
	_font_label.text = "Font Size: %dpx" % int_val
	_apply_font_size(int_val)


func _on_filter_changed(_text: String) -> void:
	_rebuild_display()


func _on_log_added() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_flush_pending_refresh")


func _flush_pending_refresh() -> void:
	_refresh_pending = false
	_handle_log_added()


func _handle_log_added() -> void:
	if not is_instance_valid(_log_text) or _log_handler == null:
		return
	if _is_filter_active() or _log_handler.consume_needs_rebuild() or _log_handler.get_log_count() > _get_max_log_count():
		_rebuild_display()
	else:
		_append_new_logs()


func _is_filter_active() -> bool:
	if _type_selector != null and _type_selector.selected != 0:
		return true
	return _filter_input != null and not _filter_input.text.is_empty()


func _get_max_log_count() -> int:
	return int(_history_slider.value) if _history_slider != null else DEFAULT_HISTORY_SIZE


func _format_log_entry(entry: Dictionary) -> String:
	var message := str(entry["message"])
	var type := str(entry["type"])
	if type == "info":
		message = LogPopUtils.convert_ansi_to_bbcode(message)
	elif type == "error" and not message.begins_with("[color="):
		message = LogPopUtils.convert_ansi_to_bbcode(message)
	return "[color=#fff][%s][/color] %s" % [entry["time"], message]


func _append_new_logs() -> void:
	if _log_handler == null:
		return

	var max_logs := _get_max_log_count()
	if _log_handler.get_log_count() > max_logs:
		_rebuild_display()
		return

	if _displayed_log_count >= _log_handler.get_log_count():
		return

	var bbcode := ""
	for i in range(_displayed_log_count, _log_handler.get_log_count()):
		bbcode += _format_log_entry(_log_handler.get_log(i))

	if not bbcode.is_empty():
		_log_text.append_text(bbcode)

	_displayed_log_count = _log_handler.get_log_count()


func _rebuild_display() -> void:
	if not is_instance_valid(_log_text) or _log_handler == null:
		return

	_log_text.clear()

	var types := _get_selected_types()
	var filter_text := _filter_input.text if _filter_input != null else ""
	var entries := _log_handler.get_filtered_logs(types, filter_text, _get_max_log_count())

	var bbcode := ""
	for entry in entries:
		bbcode += _format_log_entry(entry)

	if not bbcode.is_empty():
		_log_text.append_text(bbcode)

	_displayed_log_count = _log_handler.get_log_count()


func _get_selected_types() -> Array[String]:
	var types: Array[String] = []
	var selected := _type_selector.selected if _type_selector != null else 0
	match selected:
		0:
			types.assign(["info", "warn", "error"])
		1:
			types.assign(["error"])
		2:
			types.assign(["warn"])
		3:
			types.assign(["info"])
		4:
			types.assign(["warn", "error"])
		5:
			types.assign(["info", "error"])
		6:
			types.assign(["info", "warn"])
	return types
