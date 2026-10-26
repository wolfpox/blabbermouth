extends PanelContainer
## A panel that acts like a button: pressed on click, tap, Enter or Space.
## Good for buttons whose label is more than text (cards, effect chips).

signal pressed

const Ui := preload("res://demo/ui.gd")

var normal_style: StyleBox
var hover_style: StyleBox
var on_style: StyleBox
var on := false:
	set(v):
		on = v
		_restyle()
var _hover := false


func _init(p_normal: StyleBox = null, p_hover: StyleBox = null, p_on: StyleBox = null) -> void:
	normal_style = p_normal
	hover_style = p_hover if p_hover else p_normal
	on_style = p_on if p_on else p_normal
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void:
		_hover = true
		_restyle())
	mouse_exited.connect(func() -> void:
		_hover = false
		_restyle())
	_restyle()


func _restyle() -> void:
	var s: StyleBox = on_style if on else (hover_style if _hover else normal_style)
	if s:
		add_theme_stylebox_override("panel", s)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if Rect2(Vector2.ZERO, size).has_point(event.position):
			pressed.emit()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		pressed.emit()
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
		queue_redraw()


func _draw() -> void:
	# Only for keyboard focus, like Godot's own buttons.
	if has_focus(true):
		var r := Rect2(Vector2(-3, -3), size + Vector2(6, 6))
		draw_style_box(_focus_box(), r)


static func _focus_box() -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.border_color = Ui.ACCENT
	f.set_border_width_all(2)
	f.set_corner_radius_all(14)
	return f
