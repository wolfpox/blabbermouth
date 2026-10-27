extends Node
## Lets a finger scroll from anywhere on the page, even over buttons, chips
## and the speech bubble. A touch is held back until it's clear what it is:
## a drag up or down scrolls, while a tap or a sideways drag (sliders,
## selecting words) goes to whatever is under the finger as usual.
## Mouse input is left alone.

## How far a finger moves (in canvas units) before it counts as a drag.
const SLOP := 10.0
## How quickly a fling slows down (higher stops sooner).
const FRICTION := 5.0

enum { IDLE, PENDING, SCROLLING, PASSING }

## Its children are the layers: the page first, overlays (sheets, menus) last.
var host: Control

var _state := IDLE
var _index := -1
var _queue: Array[InputEvent] = []
var _start := Vector2.ZERO
var _start_scroll := 0.0
var _target: ScrollContainer
var _replaying := false
## A tap that only stopped a fling doesn't press anything.
var _drop_tap := false
var _last_y := 0.0
var _last_t := 0
var _velocity := 0.0
var _fling: ScrollContainer


func _input(e: InputEvent) -> void:
	if _replaying or not _is_touch(e):
		return
	var press: bool = (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed
	var release: bool = (e is InputEventMouseButton or e is InputEventScreenTouch) and not e.pressed
	match _state:
		IDLE:
			if not press:
				return
			_drop_tap = _fling != null and absf(_velocity) > 80.0
			_fling = null
			_target = _scroller_at(e.position)
			_index = e.index if e is InputEventScreenTouch else -1
			if _target == null:
				_state = PASSING
				return
			_state = PENDING
			_start = e.position
			_queue = [e]
			get_viewport().set_input_as_handled()
		PENDING:
			if e is InputEventScreenTouch and _index < 0:
				_index = e.index
			_queue.append(e)
			get_viewport().set_input_as_handled()
			if release:
				_state = IDLE
				if _drop_tap:
					_queue.clear()
				else:
					_replay()
				return
			var d: Vector2 = e.position - _start
			if not press and d.length() > SLOP:
				if absf(d.y) > absf(d.x):
					_state = SCROLLING
					_queue.clear()
					_start = e.position
					_start_scroll = _target.get_v_scroll_bar().value
					_last_y = e.position.y
					_last_t = Time.get_ticks_usec()
					_velocity = 0.0
				else:
					_state = PASSING
					_replay()
		SCROLLING:
			get_viewport().set_input_as_handled()
			if release:
				_state = IDLE
				# A finger that stopped before lifting doesn't fling.
				if Time.get_ticks_usec() - _last_t < 100000:
					_fling = _target
				return
			if press:
				return
			_target.get_v_scroll_bar().value = _start_scroll - (e.position.y - _start.y)
			var now := Time.get_ticks_usec()
			var dt := (now - _last_t) / 1000000.0
			if dt > 0.004:
				_velocity = lerpf(_velocity, (e.position.y - _last_y) / dt, 0.6)
				_last_y = e.position.y
				_last_t = now
		PASSING:
			if release:
				_state = IDLE


func _process(delta: float) -> void:
	if _fling == null:
		return
	if not is_instance_valid(_fling) or not _fling.is_visible_in_tree():
		_fling = null
		return
	var bar := _fling.get_v_scroll_bar()
	var before := bar.value
	bar.value -= _velocity * delta
	_velocity *= exp(-FRICTION * delta)
	if absf(_velocity) < 20.0 or is_equal_approx(bar.value, before):
		_fling = null


func _is_touch(e: InputEvent) -> bool:
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		return _index < 0 or e.index == _index or _state == IDLE
	if e is InputEventMouseButton or e is InputEventMouseMotion:
		return e.device == InputEvent.DEVICE_ID_EMULATION
	return false


## Hands the held-back events to the page, in order.
func _replay() -> void:
	_replaying = true
	for q in _queue:
		get_viewport().push_input(q, true)
	_replaying = false
	_queue.clear()


## The scroll area under a point on the topmost layer there, if it can scroll.
func _scroller_at(p: Vector2) -> ScrollContainer:
	for c in host.get_children():
		if c is Window and c.visible:
			return null
	for i in range(host.get_child_count() - 1, -1, -1):
		var layer := host.get_child(i) as Control
		if layer == null or not layer.visible or layer.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if not layer.get_global_rect().has_point(p):
			continue
		var s := _deepest(layer, p)
		# The scrollbar itself is dragged the usual way.
		if s and s.get_v_scroll_bar().is_visible_in_tree() and s.get_v_scroll_bar().get_global_rect().has_point(p):
			return null
		return s
	return null


func _deepest(c: Control, p: Vector2) -> ScrollContainer:
	var found: ScrollContainer = null
	if c is ScrollContainer:
		var bar: VScrollBar = c.get_v_scroll_bar()
		if bar.max_value - bar.page > 1.0:
			found = c
	for ch in c.get_children():
		if ch is Control and ch.visible and not ch is ScrollBar and ch.get_global_rect().has_point(p):
			var inner := _deepest(ch, p)
			if inner:
				found = inner
	return found
