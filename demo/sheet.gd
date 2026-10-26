extends Control
## A full-window layer that dims the page and holds a centered panel.
## Clicking outside the panel or pressing Escape closes it.

signal closed

const Ui := preload("res://demo/ui.gd")

var panel: PanelContainer
var body: VBoxContainer
var title_label: Label
var _scroll: ScrollContainer
var _outer: VBoxContainer
var _width := 560.0


func _init(title: String, width := 560.0) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = PanelContainer.new()
	var st := Ui.box(Ui.PANEL, 24, Ui.LINE, 1, 24, 22)
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 30
	st.shadow_offset = Vector2(0, 12)
	panel.add_theme_stylebox_override("panel", st)
	_width = width
	center.add_child(panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_scroll)
	var outer := Ui.vbox(16)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(outer)
	_outer = outer
	outer.minimum_size_changed.connect(_fit)
	var top := Ui.hbox(8)
	title_label = Ui.heading(title, 22)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_label)
	var x := Button.new()
	x.icon = Ui.icon("x")
	x.flat = true
	x.tooltip_text = "Close"
	x.custom_minimum_size = Vector2(44, 44)
	x.pressed.connect(close)
	top.add_child(x)
	outer.add_child(top)
	body = Ui.vbox(14)
	outer.add_child(body)
	resized.connect(_fit)


func open() -> void:
	visible = true
	move_to_front()
	_fit()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _fit() -> void:
	if not is_inside_tree():
		return
	var avail := size - Vector2(24, 24)
	panel.custom_minimum_size.x = minf(_width, avail.x)
	_scroll.custom_minimum_size.y = minf(_outer.get_combined_minimum_size().y, avail.y - 48)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not panel.get_global_rect().has_point(get_global_transform_with_canvas() * event.position):
			close()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
