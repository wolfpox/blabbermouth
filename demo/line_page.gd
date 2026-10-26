extends BoxContainer
## The line editor. The speaker's bubble is the center of it: select words
## (drag, or tap a word) and pick an effect from the toolbar. The bubble
## shows the effect and the voice reads it that way.

## The text, effects or anything that's saved changed.
signal edited
## Wants the speaker menu, under the name tag.
signal pick_speaker(anchor: Control)
## Wants to record (or re-record) the speaker's voice.
signal record_pressed
## "All settings" in the side panel.
signal more_pressed
## The speaker's settings changed here.
signal speaker_changed(what: String)
## "Try a sample line".
signal sample_pressed

const Ui := preload("res://demo/ui.gd")
const Clickable := preload("res://demo/clickable.gd")
const Sheet := preload("res://demo/sheet.gd")
const Cast := preload("res://demo/cast.gd")
const LineModel := preload("res://demo/line_model.gd")
const SpeakerEditor := preload("res://demo/speaker_editor.gd")

const TOOL_GROUPS := [["Volume", ["shout", "whisper"]], ["Motion", ["shiver", "wave", "swell", "bounce", "droop", "jolt"]],
	["Pace", ["slow", "fast"]], ["Pitch", ["high", "low"]]]
## How each effect's button shows its effect.
const CHIP_BBCODE := {
	"shout": "[b]%s[/b]", "whisper": "[i]%s[/i]", "wave": "[wave amp=14.0 freq=5.0 connected=1]%s[/wave]",
	"shiver": "[shiver]%s[/shiver]", "swell": "[swell]%s[/swell]", "bounce": "[bounce]%s[/bounce]",
	"droop": "[droop]%s[/droop]", "jolt": "[jolt]%s[/jolt]",
}

var member: Cast.Member
var model: RefCounted = LineModel.new()
## The selected text range; x == y when nothing is selected.
var sel := Vector2i.ZERO

var left: VBoxContainer
var stage: PanelContainer
var sel_label: Label
var chips := {}
var pause_chip: Clickable
var clear_chip: Clickable
var bubble_margin: MarginContainer
var dialogue: BlabberDialogue
var chevron: TextureRect
var text_edit: TextEdit
var synth_button: Button
var rec_button: Button
var source_detail: Label
var record_again: Button
var play_button: Button
var bars: Bars
var duration_label: Label
var tags_button: Button
var tags_view: RichTextLabel
var marks_box: VBoxContainer
var marks_empty: Label
var aside: SpeakerEditor
var aside_panel: PanelContainer

var _map := PackedInt32Array()
var _press_at := Vector2.ZERO
var _tapping := false
var _syncing := false
var _bars_timer: Timer
var _total := 0.0
var _play_started := 0


func _ready() -> void:
	add_theme_constant_override("separation", 24)
	_bars_timer = Timer.new()
	_bars_timer.one_shot = true
	_bars_timer.wait_time = 0.2
	_bars_timer.timeout.connect(_update_bars)
	add_child(_bars_timer)
	left = Ui.vbox(16)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(left)

	# The stage: toolbar, bubble, words and voice source.
	stage = Ui.panel(Ui.CARD, 28, 24, 20)
	left.add_child(stage)
	var sv := Ui.vbox(18)
	stage.add_child(sv)
	sv.add_child(_toolbar())

	bubble_margin = MarginContainer.new()
	bubble_margin.add_theme_constant_override("margin_top", 26)
	bubble_margin.add_theme_constant_override("margin_bottom", 14)
	sv.add_child(bubble_margin)
	dialogue = BlabberDialogue.new()
	dialogue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble_margin.add_child(dialogue)
	_setup_bubble()

	var words := Ui.vbox(8)
	var wtop := Ui.hbox(8)
	var wl := Ui.eyebrow("Words")
	wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wtop.add_child(wl)
	var sample := Ui.button("Try a sample line", sample_pressed.emit, "shuffle", "Link")
	sample.name = "Sample"
	wtop.add_child(sample)
	words.add_child(wtop)
	text_edit = TextEdit.new()
	text_edit.placeholder_text = "Type what the character says, then select words in the bubble to style them."
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_edit.scroll_fit_content_height = true
	text_edit.custom_minimum_size.y = 52
	text_edit.deselect_on_focus_loss_enabled = false
	text_edit.text_changed.connect(_on_text_changed)
	text_edit.caret_changed.connect(_on_caret_changed)
	words.add_child(text_edit)
	sv.add_child(words)
	sv.add_child(_source_row())

	left.add_child(_play_row())
	left.add_child(_reads_card())

	aside_panel = Ui.panel(Ui.PANEL, 28, 24, 24)
	aside_panel.custom_minimum_size.x = 340
	aside_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_child(aside_panel)
	aside = SpeakerEditor.new(false)
	aside_panel.add_child(aside)
	aside.changed.connect(func(what: String) -> void:
		speaker_changed.emit(what)
		_refresh())
	aside.more_pressed.connect(more_pressed.emit)

	set_process(false)
	resized.connect(_fit_bubble)


## Lays out for wide screens (side panel on the right), narrow ones (below)
## or phones (tighter).
func set_narrow(narrow: bool, phone := false) -> void:
	vertical = narrow
	aside_panel.custom_minimum_size.x = 0 if narrow else 340
	aside_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_FILL
	var pad := 14 if phone else 24
	stage.add_theme_stylebox_override("panel", Ui.box(Ui.CARD, 20 if phone else 28, Ui.CLEAR, 0, pad, 20))
	aside_panel.add_theme_stylebox_override("panel", Ui.box(Ui.PANEL, 20 if phone else 28, Ui.CLEAR, 0, 18 if phone else 24, 24))
	play_button.custom_minimum_size.x = 0 if phone else 170
	play_button.add_theme_stylebox_override("normal", Ui.box(Ui.ACCENT, 16, Ui.CLEAR, 0, 18 if phone else 26, 14))
	bars.custom_minimum_size.x = 40 if phone else 80
	_fit_bubble()


func set_member(m: Cast.Member) -> void:
	if dialogue.is_speaking():
		dialogue.stop()
	member = m
	aside.set_member(m)
	_refresh()


## Starts editing tagged text (a sample or an opened line).
func load_source(src: String) -> void:
	if dialogue.is_speaking():
		dialogue.stop()
	model = LineModel.from_source(src)
	sel = Vector2i.ZERO
	_syncing = true
	text_edit.text = model.text
	_syncing = false
	_refresh()


## The line as the game gets it: the text with tags and the live speaker.
func current_line() -> BlabberLine:
	var l := BlabberLine.new()
	l.text = model.to_source()
	l.speaker = member.speaker if member else null
	return l


## Selects a text range (snapped to whole words) and shows it everywhere.
func select_range(r: Vector2i) -> void:
	sel = model.snap(r.x, r.y)
	_select_in_text_edit()
	_refresh()


## A tap at a screen position selects the word under it.
func tap_bubble(global_pos: Vector2) -> void:
	var l := dialogue.text_label
	_tapping = true
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.double_click = pressed
		ev.position = global_pos
		ev.global_position = global_pos
		get_viewport().push_input(ev, true)
	_tapping = false
	_take_bubble_selection(true)
	l.deselect()


func refresh_speaker() -> void:
	aside.refresh()
	_refresh()


# --- Building -------------------------------------------------------------------

func _toolbar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", Ui.box(Ui.RAISED, 18, Ui.LINE, 1, 12, 10))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 8)
	bar.add_child(flow)
	sel_label = Ui.label("", 13, Ui.DIM)
	sel_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	sel_label.custom_minimum_size.x = 150
	sel_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sel_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flow.add_child(sel_label)
	# Group names and buttons all flow, so the bar wraps on narrow screens.
	for g in TOOL_GROUPS + [["Gap", []]]:
		var gl := Ui.eyebrow(g[0])
		gl.add_theme_font_size_override("font_size", 11)
		gl.add_theme_color_override("font_color", Ui.FAINT)
		gl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		flow.add_child(gl)
		for fx in g[1]:
			var chip := _chip(LineModel.FX[fx].label, CHIP_BBCODE.get(fx, "%s"), LineModel.FX[fx].voice)
			chip.pressed.connect(_format.bind(fx))
			chips[fx] = chip
			flow.add_child(chip)
	pause_chip = _chip("Pause", "%s", "half a second of silence after the selection")
	pause_chip.pressed.connect(_toggle_pause)
	flow.add_child(pause_chip)
	clear_chip = _chip("Clear", "%s", "remove the effects from the selection")
	clear_chip.pressed.connect(_clear)
	flow.add_child(clear_chip)
	return bar


func _chip(text: String, bbcode: String, tip: String) -> Clickable:
	var chip := Clickable.new(Ui.box(Ui.CLEAR, 12, Ui.LINE, 1, 12, 0), Ui.box(Ui.BUTTON, 12, Ui.LINE, 1, 12, 0), Ui.box(Ui.ON, 12, Ui.ON, 1, 12, 0))
	chip.custom_minimum_size = Vector2(44, 44)
	chip.tooltip_text = tip[0].to_upper() + tip.substr(1)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	rt.scroll_active = false
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rt.add_theme_font_override("normal_font", Ui.FONT_BOLD)
	rt.add_theme_font_override("bold_font", Ui.FONT_BOLD)
	var it := FontVariation.new()
	it.base_font = Ui.FONT_BOLD
	it.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
	rt.add_theme_font_override("italics_font", it)
	for slot in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		rt.add_theme_font_size_override(slot, 15)
	BlabberTextEffects.install(rt)
	rt.text = bbcode % text
	chip.add_child(rt)
	chip.set_meta("label", rt)
	return chip


func _set_chip_on(chip: Clickable, on: bool) -> void:
	chip.on = on
	var rt: RichTextLabel = chip.get_meta("label")
	rt.add_theme_color_override("default_color", Ui.ON_INK if on else Ui.TEXT)


func _setup_bubble() -> void:
	var l := dialogue.text_label
	l.selection_enabled = true
	l.deselect_on_focus_loss_enabled = false
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	l.gui_input.connect(_on_bubble_input)
	dialogue.custom_minimum_size.y = 120
	dialogue.finished.connect(_on_finished)
	# The name tag opens the speaker menu, so it gets a little arrow.
	var tag := dialogue.name_tag
	var name_label := dialogue.name_label
	tag.remove_child(name_label)
	var row := Ui.hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)
	chevron = TextureRect.new()
	chevron.texture = Ui.icon("down")
	chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chevron.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chevron.custom_minimum_size = Vector2(16, 16)
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chevron)
	tag.add_child(row)
	tag.mouse_filter = Control.MOUSE_FILTER_STOP
	tag.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tag.focus_mode = Control.FOCUS_ALL
	tag.tooltip_text = "Choose who says this line"
	tag.gui_input.connect(func(e: InputEvent) -> void:
		var click: bool = e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed
		if click or e.is_action_pressed("ui_accept"):
			tag.accept_event()
			pick_speaker.emit(tag))


func _source_row() -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 16)
	row.add_theme_constant_override("v_separation", 10)
	var l := Ui.eyebrow("Voice source")
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var seg := Ui.segmented(["Synth voice", "My recording"], ["synth", "mic"])
	synth_button = seg[1][0]
	rec_button = seg[1][1]
	synth_button.pressed.connect(func() -> void: _use_recording(false))
	rec_button.pressed.connect(func() -> void: _use_recording(true))
	row.add_child(seg[0])
	source_detail = Ui.label("", 14, Ui.TEXT_2)
	source_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_detail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	source_detail.custom_minimum_size.x = 200
	row.add_child(source_detail)
	record_again = Ui.button("Record again", record_pressed.emit, "rec")
	record_again.add_theme_color_override("icon_normal_color", Ui.REC)
	record_again.add_theme_color_override("icon_hover_color", Ui.REC)
	row.add_child(record_again)
	return row


func _play_row() -> Control:
	var p := Ui.panel(Ui.PANEL, 24, 18, 16)
	var row := Ui.hbox(18)
	p.add_child(row)
	play_button = Ui.button("Play line", _play, "play", "Primary")
	play_button.custom_minimum_size = Vector2(170, 56)
	row.add_child(play_button)
	bars = Bars.new()
	bars.custom_minimum_size = Vector2(80, 52)
	bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bars.resized.connect(func() -> void: _bars_timer.start())
	row.add_child(bars)
	duration_label = Ui.label("", 14, Ui.TEXT_2)
	duration_label.add_theme_font_override("font", Ui.FONT_MONO)
	duration_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	duration_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(duration_label)
	return p


func _reads_card() -> Control:
	var p := Ui.panel(Ui.PANEL, 24, 22, 20)
	var v := Ui.vbox(10)
	p.add_child(v)
	var top := Ui.hbox(12)
	var h := Ui.heading("How the voice reads it")
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(h)
	tags_button = Ui.button("Show tags", _toggle_tags)
	tags_button.add_theme_font_override("font", Ui.FONT_MONO)
	tags_button.add_theme_font_size_override("font_size", 13)
	tags_button.custom_minimum_size.y = 40
	top.add_child(tags_button)
	v.add_child(top)
	var tags_panel := Ui.panel(Ui.BG, 12, 16, 14)
	tags_panel.visible = false
	tags_view = RichTextLabel.new()
	tags_view.bbcode_enabled = false
	tags_view.fit_content = true
	tags_view.selection_enabled = true
	tags_view.context_menu_enabled = true
	tags_view.add_theme_font_override("normal_font", Ui.FONT_MONO)
	tags_view.add_theme_font_size_override("normal_font_size", 13)
	tags_view.add_theme_color_override("default_color", Ui.TEXT_2)
	tags_panel.add_child(tags_view)
	v.add_child(tags_panel)
	tags_view.set_meta("panel", tags_panel)
	marks_box = Ui.vbox(8)
	v.add_child(marks_box)
	marks_empty = Ui.label("Nothing special yet: the voice reads the whole line plainly. Select some words and pick an effect.", 14, Ui.DIM)
	v.add_child(marks_empty)
	return p


# --- Updating -------------------------------------------------------------------

func _refresh() -> void:
	if member == null or not is_node_ready():
		return
	var b := member.speaker.bubble
	if dialogue.is_speaking():
		dialogue.stop() # Something changed, so the old take is out of date.
	dialogue.line = current_line()
	_show_edit_view()
	chevron.modulate = b.name_text_color
	# Toolbar
	var r: Vector2i = model.range_or_all(sel)
	var has_sel := sel.x < sel.y
	if has_sel:
		sel_label.text = "Selected “%s”" % _short(model.text.substr(sel.x, sel.y - sel.x), 24)
		sel_label.add_theme_color_override("font_color", Ui.TEXT)
	else:
		sel_label.text = "Whole line · or select words"
		sel_label.add_theme_color_override("font_color", Ui.DIM)
	for fx in chips:
		_set_chip_on(chips[fx], r.x < r.y and model.is_on(fx, r.x, r.y))
	_set_chip_on(pause_chip, model.has_pause(r.y))
	# Voice source
	var rec := member.recording
	synth_button.set_pressed_no_signal(not member.use_recording)
	rec_button.set_pressed_no_signal(member.use_recording)
	var v := member.speaker.voice
	var who := member.speaker.display_name
	if member.use_recording and rec:
		source_detail.text = "Your recording · %.1f s, played at %d Hz to fit %s" % [rec.audio.size() / float(rec.sample_rate), roundi(v.pitch), who]
	else:
		source_detail.text = "%s’s synth voice · %d Hz · %s" % [who, roundi(v.pitch), "says real words" if v.mode == BlabberVoice.Mode.PHONETIC else "speaks gibberish"]
	record_again.visible = member.use_recording
	record_again.text = "Record again"
	# What the voice does
	var src: String = model.to_source()
	tags_view.text = src
	for c in marks_box.get_children():
		c.queue_free()
	var marks: Array = model.marks()
	for m in marks:
		marks_box.add_child(_mark_row(m))
	marks_empty.visible = marks.is_empty()
	_bars_timer.start()
	edited.emit()


func _show_edit_view() -> void:
	var b := member.speaker.bubble
	var dark := b.bg_color.get_luminance() < 0.4
	var hl := Color(1.0, 0.82, 0.4, 0.24) if dark else Color(1.0, 0.77, 0.24, 0.45)
	var view: Dictionary = model.edit_view(b.font_size, b.muted_color, sel.x, sel.y, hl, Ui.FONT_MONO.resource_path)
	dialogue.text_label.text = view.bbcode
	dialogue.text_label.visible_characters = -1
	_map = view.map


func _mark_row(m: Dictionary) -> Control:
	var on: bool = sel == Vector2i(m.start, m.end)
	var row := Clickable.new(Ui.box(Ui.CLEAR, 14, Ui.LINE_SOFT, 1, 14, 8), Ui.box(Ui.RAISED, 14, Ui.LINE, 1, 14, 8), Ui.box(Color("2c2f39"), 14, Ui.ACCENT, 1, 14, 8))
	row.on = on
	row.custom_minimum_size.y = 52
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 4)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(flow)
	var t := Ui.label("“%s”" % _short(model.text.substr(m.start, m.end - m.start), 34), 15, Ui.TEXT, true)
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_child(t)
	var chips_row := Ui.hbox(6)
	chips_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var voices: Array = []
	for fx in m.fx:
		chips_row.add_child(_tag_chip(LineModel.FX[fx].label))
		voices.append(LineModel.FX[fx].voice)
	if m.pause > 0.0:
		chips_row.add_child(_tag_chip("Pause %ss" % str(snappedf(m.pause, 0.01)).trim_suffix(".0")))
		voices.append("then silence")
	flow.add_child(chips_row)
	var d := Ui.label(" + ".join(voices), 14, Ui.DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_OFF
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_child(d)
	row.pressed.connect(func() -> void: select_range(Vector2i(m.start, m.end)))
	return row


func _tag_chip(text: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.box(Ui.LINE_SOFT, 8, Ui.CLEAR, 0, 9, 3))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Ui.label(text, 13, Ui.TEXT, true)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


func _update_bars() -> void:
	if member == null:
		return
	var plan := BlabberParser.build(model.to_source(), member.speaker.voice)
	var segs: Array = plan.segments
	_total = 0.0
	for s in segs:
		_total += s.d
	var n := clampi(int(bars.size.x / 6.0), 12, 400)
	var amp := PackedFloat32Array()
	amp.resize(n)
	var kind := PackedByteArray()
	kind.resize(n)
	var t := 0.0
	var top := 0.0001
	for s in segs:
		var e: float = s.a * (s.v + 0.35 * (s.asp + s.fr))
		var i0 := clampi(int(t / _total * n), 0, n - 1)
		var i1 := clampi(int((t + s.d) / _total * n), 0, n - 1)
		var ci: int = s.rev - 1
		var k := 0
		if ci >= 0 and ci < model.text.length():
			if ci >= sel.x and ci < sel.y:
				k = 2
			elif not model.styles[ci].is_empty():
				k = 1
		for i in range(i0, i1 + 1):
			if e > amp[i]:
				amp[i] = e
				kind[i] = k
		top = maxf(top, e)
		t += s.d
	for i in n:
		amp[i] /= top
	bars.amps = amp
	bars.kinds = kind
	bars.queue_redraw()
	duration_label.text = "≈ %.1f s" % _total


func _fit_bubble() -> void:
	# Keep the bubble readable on wide screens: at most 900 px, centered.
	var extra := maxi(0, int(stage.size.x - 48 - 900) / 2)
	bubble_margin.add_theme_constant_override("margin_left", extra)
	bubble_margin.add_theme_constant_override("margin_right", extra)
	if bars:
		_bars_timer.start()


# --- Editing ----------------------------------------------------------------------

func _on_text_changed() -> void:
	if _syncing:
		return
	if dialogue.is_speaking():
		dialogue.stop()
	model.set_text(text_edit.text)
	if model.text != text_edit.text:
		# Brackets became parentheses.
		var line := text_edit.get_caret_line()
		var col := text_edit.get_caret_column()
		_syncing = true
		text_edit.text = model.text
		text_edit.set_caret_line(line)
		text_edit.set_caret_column(col)
		_syncing = false
	sel = Vector2i.ZERO
	_refresh()


func _on_caret_changed() -> void:
	if _syncing:
		return
	if text_edit.has_selection():
		var a := _index_of(text_edit.get_selection_from_line(), text_edit.get_selection_from_column())
		var b := _index_of(text_edit.get_selection_to_line(), text_edit.get_selection_to_column())
		var r: Vector2i = model.snap(a, b)
		if r != sel:
			sel = r
			_refresh()
	elif sel.x < sel.y and text_edit.has_focus():
		sel = Vector2i.ZERO
		_refresh()


func _index_of(line: int, col: int) -> int:
	var i := 0
	for k in line:
		i += text_edit.get_line(k).length() + 1
	return i + col


func _select_in_text_edit() -> void:
	_syncing = true
	if sel.x < sel.y:
		var a := _line_col(sel.x)
		var b := _line_col(sel.y)
		text_edit.select(a.x, a.y, b.x, b.y)
	else:
		text_edit.deselect()
	_syncing = false


func _line_col(i: int) -> Vector2i:
	var line := 0
	while line < text_edit.get_line_count() - 1 and i > text_edit.get_line(line).length():
		i -= text_edit.get_line(line).length() + 1
		line += 1
	return Vector2i(line, i)


func _on_bubble_input(e: InputEvent) -> void:
	if _tapping or dialogue.is_speaking():
		return
	var mb := e as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or mb.double_click:
		return
	if mb.pressed:
		_press_at = mb.position
	else:
		var tap := mb.position.distance_to(_press_at) < 8.0
		var at := dialogue.text_label.get_global_transform_with_canvas() * mb.position
		_after_release.call_deferred(tap, at)


func _after_release(tap: bool, at: Vector2) -> void:
	var l := dialogue.text_label
	if l.get_selection_from() < 0:
		if tap:
			tap_bubble(at)
		return
	_take_bubble_selection(false)
	l.deselect()


func _take_bubble_selection(from_tap: bool) -> void:
	var l := dialogue.text_label
	var a := l.get_selection_from()
	var b := l.get_selection_to()
	if a < 0 or _map.is_empty():
		if from_tap:
			sel = Vector2i.ZERO
			_select_in_text_edit()
			_refresh()
		return
	var ma := _map[clampi(a, 0, _map.size() - 1)]
	var mb := _map[clampi(b, 0, _map.size() - 1)] + 1
	sel = model.snap(ma, mb)
	_select_in_text_edit()
	_refresh()


func _format(fx: String) -> void:
	var r: Vector2i = model.range_or_all(sel)
	if r.x >= r.y:
		return
	model.toggle(fx, r.x, r.y)
	_stop_and_refresh()


func _toggle_pause() -> void:
	var r: Vector2i = model.range_or_all(sel)
	if r.y <= 0:
		return
	model.toggle_pause(r.y)
	_stop_and_refresh()


func _clear() -> void:
	var r: Vector2i = model.range_or_all(sel)
	model.clear(r.x, r.y)
	_stop_and_refresh()


func _stop_and_refresh() -> void:
	if dialogue.is_speaking():
		dialogue.stop()
	_refresh()


func _use_recording(on: bool) -> void:
	if on and member.recording == null:
		synth_button.set_pressed_no_signal(true)
		rec_button.set_pressed_no_signal(false)
		record_pressed.emit()
		return
	member.set_use_recording(on)
	speaker_changed.emit("voice")
	_refresh()


func _toggle_tags() -> void:
	var p: Control = tags_view.get_meta("panel")
	p.visible = not p.visible
	tags_button.text = "Hide tags" if p.visible else "Show tags"


# --- Playing ------------------------------------------------------------------------

func _play() -> void:
	if dialogue.is_speaking():
		dialogue.stop()
		return
	if model.text.strip_edges() == "":
		return
	dialogue.text_label.selection_enabled = false
	dialogue.say(current_line())
	play_button.text = "Stop"
	play_button.icon = Ui.icon("stop")
	_play_started = Time.get_ticks_msec()
	set_process(true)


func _on_finished() -> void:
	play_button.text = "Play line"
	play_button.icon = Ui.icon("play")
	dialogue.text_label.selection_enabled = true
	set_process(false)
	bars.playhead = -1.0
	bars.queue_redraw()
	if member:
		_show_edit_view()


func _process(_delta: float) -> void:
	if _total > 0.0:
		bars.playhead = clampf((Time.get_ticks_msec() - _play_started) / 1000.0 / _total, 0.0, 1.0)
		bars.queue_redraw()


static func _short(t: String, n: int) -> String:
	t = t.replace("\n", " ")
	return t if t.length() <= n else t.left(n - 1).strip_edges() + "…"


## The play bar's waveform: loudness over time, worked out from the line's
## sounds (no audio needed). Effects show lighter, the selection yellow.
class Bars extends Control:
	var amps := PackedFloat32Array()
	var kinds := PackedByteArray()
	var playhead := -1.0

	func _draw() -> void:
		var n := amps.size()
		if n == 0:
			return
		var w := size.x / n
		var bw := clampf(w - 2.0, 2.0, 5.0)
		var colors := [Color("5a5f6c"), Color("c9ccd3"), Color("ffd166")]
		for i in n:
			var h := maxf(3.0, amps[i] * size.y)
			var c: Color = colors[kinds[i]]
			if playhead >= 0.0 and float(i) / n > playhead:
				c = c.darkened(0.45)
			var x := i * w + (w - bw) * 0.5
			draw_rect(Rect2(x, (size.y - h) * 0.5, bw, h), c)
		if playhead >= 0.0:
			draw_rect(Rect2(playhead * size.x - 1.0, 0, 2, size.y), Color("f3f1ec"))
