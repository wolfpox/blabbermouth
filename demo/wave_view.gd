extends Control
## Draws a waveform with colored syllable pieces. Tap a piece to select it.

signal slice_pressed(index: int)

const FRAME_SECONDS := 0.01

## Peak level per 10 ms.
var peaks := PackedFloat32Array()
## Each slice: {a: seconds, b: seconds, color: Color, on: bool}
var slices: Array = []
var highlight := -1
var min_seconds := 4.0


## Rebuilds peaks from samples. Fine for a few seconds of audio.
func set_audio(samples: PackedFloat32Array, rate: int) -> void:
	peaks = PackedFloat32Array()
	var step := maxi(1, int(rate * FRAME_SECONDS))
	var i := 0
	while i < samples.size():
		var p := 0.0
		for k in range(i, mini(i + step, samples.size())):
			p = maxf(p, absf(samples[k]))
		peaks.append(p)
		i += step
	queue_redraw()


## Adds newly recorded samples without redoing the old ones.
func append_audio(samples: PackedFloat32Array, from: int, rate: int) -> void:
	var step := maxi(1, int(rate * FRAME_SECONDS))
	var start := peaks.size() * step
	if from > start:
		start = from
	var i := start
	while i + step <= samples.size():
		var p := 0.0
		for k in range(i, i + step):
			p = maxf(p, absf(samples[k]))
		peaks.append(p)
		i += step
	queue_redraw()


func clear() -> void:
	peaks = PackedFloat32Array()
	slices = []
	highlight = -1
	queue_redraw()


func _seconds() -> float:
	return maxf(min_seconds, peaks.size() * FRAME_SECONDS)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.1))
	var total := _seconds()
	var px := size.x / total
	for i in slices.size():
		var s: Dictionary = slices[i]
		var r := Rect2(s.a * px, 0, (s.b - s.a) * px, size.y)
		var c: Color = s.color if s.on else Color(0.3, 0.3, 0.3)
		c.a = 0.55 if i == highlight else 0.28
		draw_rect(r.grow_individual(-1, 0, -1, 0), c)
		if not s.on:
			draw_line(r.position, r.end, Color(1, 0.3, 0.3, 0.6), 2.0)
	var mid := size.y / 2.0
	var cols := int(size.x)
	if peaks.is_empty() or cols <= 0:
		draw_string(get_theme_default_font(), Vector2(12, mid + 6), "No recording yet", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.35))
		return
	for x in cols:
		var f0 := int(x / px / FRAME_SECONDS)
		var f1 := maxi(f0 + 1, int((x + 1) / px / FRAME_SECONDS))
		if f0 >= peaks.size():
			break
		var p := 0.0
		for f in range(f0, mini(f1, peaks.size())):
			p = maxf(p, peaks[f])
		var h := clampf(p, 0.0, 1.0) * (mid - 4)
		draw_line(Vector2(x, mid - h), Vector2(x, mid + h), Color(0.85, 0.9, 1.0, 0.9))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var t: float = event.position.x / size.x * _seconds()
		for i in slices.size():
			if t >= slices[i].a and t <= slices[i].b:
				slice_pressed.emit(i)
				accept_event()
				return
