@tool
@icon("res://addons/log_pop/icon.svg")
class_name LogPop
extends Node

const LogPopHandlerScript = preload("log_handler.gd")
const LogPopWindowScript = preload("log_window.gd")

## Max number of log lines kept on screen (50–2000).
@export_range(50, 2000, 50) var log_max_count: int = 300
## Overlay text size (16–32). Also applies to bold/mono styles.
@export_range(16, 32, 1) var log_font_size: int = 16
## If enabled, start with the log viewer in a separate OS window (desktop only).
@export var use_detached_window: bool = false
## If enabled, automatically show the overlay when an error is logged (warnings do not trigger this). Turn off to keep the overlay closed until you open it manually.
@export var auto_open_on_error: bool = true
## Keyboard shortcut to show/hide the in-game log.
@export_enum("Ctrl+L", "Ctrl+Alt+L", "Ctrl+Alt+P") var toggle_hotkey: int = 0
## How long three fingers must be held to show/hide the log (seconds).
@export_range(0.3, 1.5, 0.05) var three_finger_hold_seconds: float = 0.8

var _log_window: LogPopWindowScript
var _log_handler: LogPopHandlerScript

var _active_touches: Dictionary = {} # index -> true
var _three_finger_hold_time: float = 0.0
var _three_finger_triggered: bool = false
var _pending_auto_open := false


func _init() -> void:
	if Engine.is_editor_hint():
		return
	_create_log_handler()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_process_input(true)
	set_process(true)
	_create_log_window()


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	if event is InputEventKey and _matches_hotkey(event):
		_toggle_window()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenTouch:
		_handle_screen_touch(event)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _active_touches.size() < 3:
		return
	if _three_finger_triggered:
		return

	_three_finger_hold_time += delta
	if _three_finger_hold_time >= three_finger_hold_seconds:
		_three_finger_triggered = true
		_toggle_window()


func _matches_hotkey(key: InputEventKey) -> bool:
	if not key.pressed or key.echo:
		return false

	match toggle_hotkey:
		0:
			return (
				key.keycode == KEY_L
				and key.ctrl_pressed
				and not key.alt_pressed
				and not key.shift_pressed
				and not key.meta_pressed
			)
		1:
			return (
				key.keycode == KEY_L
				and key.ctrl_pressed
				and key.alt_pressed
				and not key.shift_pressed
				and not key.meta_pressed
			)
		2:
			return (
				key.keycode == KEY_P
				and key.ctrl_pressed
				and key.alt_pressed
				and not key.shift_pressed
				and not key.meta_pressed
			)
		_:
			return false


func _handle_screen_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		_active_touches[touch.index] = true
	else:
		_active_touches.erase(touch.index)

	if _active_touches.size() < 3:
		_three_finger_hold_time = 0.0
		_three_finger_triggered = false


func _create_log_handler() -> void:
	_log_handler = LogPopHandlerScript.new()
	_log_handler.error_logged.connect(_on_error_logged)
	call_deferred("add_child", _log_handler)


func _create_log_window() -> void:
	var packed: PackedScene = load(_get_window_scene_path())
	_log_window = packed.instantiate() as LogPopWindowScript
	_log_window.init_ui(_log_handler)
	_log_window.apply_export_settings(log_max_count, log_font_size, use_detached_window)
	call_deferred("_add_log_window_to_tree")


func _get_window_scene_path() -> String:
	var script_path: String = (get_script() as Script).resource_path
	return script_path.get_base_dir().get_base_dir().path_join("scenes/log_window.tscn")


func _add_log_window_to_tree() -> void:
	add_child(_log_window)
	_log_window.hide()
	_log_window.apply_detached_if_requested()
	if _pending_auto_open:
		_pending_auto_open = false
		_ensure_window_visible()


func _on_error_logged() -> void:
	if not auto_open_on_error:
		return
	if not is_instance_valid(_log_window) or not _log_window.is_inside_tree():
		_pending_auto_open = true
		return
	_ensure_window_visible()


func _ensure_window_visible() -> void:
	if is_instance_valid(_log_window):
		_log_window.ensure_visible()


func _toggle_window() -> void:
	if is_instance_valid(_log_window):
		_log_window.toggle_visibility()
