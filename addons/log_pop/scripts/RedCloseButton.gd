@tool
class_name RedCloseButton
extends Button
## 红叉关闭钮基底：默认最小 70×70；只画矢量叉，不改主题底（可用在非斜切 Button 上）。

## 叉相对方钮短边的比例（0.6×70%）。
const CROSS_SCALE := 0.42
## 标准红 ≈ #E84D3D
const CROSS_RED := Color(0.91, 0.30, 0.24, 1.0)

var hover: bool = false
var press: bool = false
var _wired: bool = false


func _ready() -> void:
	text = ""
	ensure_min_size()
	wire_input_redraw()
	if Engine.is_editor_hint():
		set_process(true)
	queue_redraw()


func ensure_min_size() -> void:
	if custom_minimum_size.x < 1.0 or custom_minimum_size.y < 1.0:
		custom_minimum_size = Vector2(70, 70)


func wire_input_redraw() -> void:
	if _wired:
		return
	_wired = true
	button_down.connect(func() -> void:
		press = true
		queue_redraw()
	)
	button_up.connect(func() -> void:
		press = false
		queue_redraw()
	)
	mouse_entered.connect(func() -> void:
		hover = true
		queue_redraw()
	)
	mouse_exited.connect(func() -> void:
		hover = false
		press = false
		queue_redraw()
	)


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		set_process(false)
		return
	queue_redraw()


func _get_minimum_size() -> Vector2:
	var m := custom_minimum_size
	if m.x < 1.0:
		m.x = 70.0
	if m.y < 1.0:
		m.y = 70.0
	return m


func resolve_draw_size() -> Vector2:
	var sz := size
	if sz.x < 1.0 or sz.y < 1.0:
		sz = get_combined_minimum_size()
	return sz


func _draw() -> void:
	var sz := resolve_draw_size()
	if sz.x < 1.0 or sz.y < 1.0:
		return
	if press:
		draw_set_transform(sz * 0.015, 0.0, Vector2(0.97, 0.97))
	draw_cross(sz, CROSS_RED)


## 居中矢量叉：外接方边长 = 短边 × CROSS_SCALE。
func draw_cross(sz: Vector2, color: Color) -> void:
	var side := minf(sz.x, sz.y) * CROSS_SCALE
	var half := side * 0.5
	var c := sz * 0.5
	var stroke := clampf(minf(sz.x, sz.y) * 0.045, 2.0, 5.0)
	draw_line(c + Vector2(-half, -half), c + Vector2(half, half), color, stroke, true)
	draw_line(c + Vector2(half, -half), c + Vector2(-half, half), color, stroke, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
