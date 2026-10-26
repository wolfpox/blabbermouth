extends VBoxContainer
## The Characters page: everyone who can speak, and all the settings for
## the one selected. Lines keep a copy of their speaker, so a game gets the
## voice and the look together.

signal picked(index: int)
signal add_pressed
signal duplicate_pressed
signal delete_pressed
signal record_pressed
signal speaker_changed(what: String)

const Ui := preload("res://demo/ui.gd")
const Clickable := preload("res://demo/clickable.gd")
const Sheet := preload("res://demo/sheet.gd")
const Cast := preload("res://demo/cast.gd")
const SpeakerEditor := preload("res://demo/speaker_editor.gd")

var members: Array = []
var current := 0
var grid: HFlowContainer
var preview: BlabberDialogue
var play_button: Button
var record_button: Button
var delete_button: Button
var editor: SpeakerEditor
var columns: BoxContainer
var left: VBoxContainer
var top: BoxContainer


## A small bubble-styled button for a character: name in their font, and kind.
static func card(m: Cast.Member, selected: bool, min_width := 200.0) -> Clickable:
	var b := m.speaker.bubble
	var st := StyleBoxFlat.new()
	st.bg_color = b.bg_color
	st.border_color = b.border_color
	st.set_border_width_all(clampi(b.border_width_top, 1, 3))
	st.set_corner_radius_all(mini(b.corner_radius_top_left, 14))
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	if selected:
		st.shadow_color = Ui.ACCENT
		st.shadow_size = 3
	var hover := st.duplicate() as StyleBoxFlat
	hover.bg_color = b.bg_color.lerp(b.text_color, 0.06)
	var c := Clickable.new(st, hover, st)
	c.custom_minimum_size = Vector2(min_width, 64)
	c.tooltip_text = "%s (%s)" % [m.speaker.display_name, m.kind.capitalize()]
	var v := Ui.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	var n := Label.new()
	n.text = m.speaker.display_name
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if b.font:
		n.add_theme_font_override("font", b.font)
	n.add_theme_font_size_override("font_size", 20 if b.font_size < 32 else 24)
	n.add_theme_color_override("font_color", b.text_color)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	var k := Ui.label(m.kind.capitalize() + ("  · recording" if m.use_recording else ""), 12, b.muted_color)
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(k)
	return c


func _ready() -> void:
	add_theme_constant_override("separation", 20)
	top = BoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	var title := Ui.heading("Characters", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.alignment = FlowContainer.ALIGNMENT_END
	actions.name = "Actions"
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(Ui.button("New", add_pressed.emit, "plus"))
	actions.add_child(Ui.button("Duplicate", duplicate_pressed.emit, "copy"))
	delete_button = Ui.button("Delete", delete_pressed.emit, "trash")
	actions.add_child(delete_button)
	top.add_child(actions)
	add_child(top)
	add_child(Ui.label("Each character has a voice and a speech bubble. Every line keeps a copy of its speaker, so a game that opens the line file gets both, and can choose to use either one.", 14, Ui.DIM))
	grid = HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	add_child(grid)

	columns = BoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	add_child(columns)
	left = Ui.vbox(16)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	columns.add_child(left)
	var stage := Ui.panel(Ui.CARD, 28, 28, 24)
	var sv := Ui.vbox(18)
	stage.add_child(sv)
	sv.add_child(Ui.eyebrow("Preview"))
	var pm := MarginContainer.new()
	pm.add_theme_constant_override("margin_top", 18)
	sv.add_child(pm)
	preview = BlabberDialogue.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pm.add_child(preview)
	preview.finished.connect(func() -> void:
		play_button.text = "Hear them"
		play_button.icon = Ui.icon("play")
		_show_preview())
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 10)
	play_button = Ui.button("Hear them", _play, "play", "Primary")
	row.add_child(play_button)
	record_button = Ui.button("Record their voice", record_pressed.emit, "mic")
	row.add_child(record_button)
	sv.add_child(row)
	left.add_child(stage)
	left.add_child(Ui.label("Tip: the voice's Pitch and Size also fit a recording to the character, so one recording can play a small critter or a giant.", 13, Ui.FAINT))

	var right := Ui.panel(Ui.PANEL, 28, 24, 24)
	right.custom_minimum_size.x = 380
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	columns.add_child(right)
	editor = SpeakerEditor.new(true)
	right.add_child(editor)
	editor.changed.connect(func(what: String) -> void:
		speaker_changed.emit(what)
		_rebuild_grid()
		_show_preview())


func set_narrow(narrow: bool, phone := false) -> void:
	columns.vertical = narrow
	top.vertical = phone
	(top.get_node("Actions") as HFlowContainer).alignment = FlowContainer.ALIGNMENT_BEGIN if phone else FlowContainer.ALIGNMENT_END
	var right: Control = editor.get_parent()
	right.custom_minimum_size.x = 0 if narrow else 380
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_FILL


func show_cast(p_members: Array, p_current: int) -> void:
	members = p_members
	current = p_current
	if preview.is_speaking():
		preview.stop()
	editor.set_member(members[current])
	delete_button.disabled = members.size() <= 1
	_rebuild_grid()
	_show_preview()


func focus_name() -> void:
	if editor.name_edit:
		editor.name_edit.grab_focus()
		editor.name_edit.select_all()


func _rebuild_grid() -> void:
	for c in grid.get_children():
		c.queue_free()
	for i in members.size():
		var c := card(members[i], i == current, 158.0)
		c.pressed.connect(picked.emit.bind(i))
		grid.add_child(c)


func _line() -> BlabberLine:
	var m: Cast.Member = members[current]
	var l := BlabberLine.new()
	l.text = "[bounce]Hello![/bounce] I'm %s. [swell]This is how I sound.[/swell]" % m.speaker.display_name.replace("[", "(").replace("]", ")")
	l.speaker = m.speaker
	return l


func _show_preview() -> void:
	if members.is_empty():
		return
	if preview.is_speaking():
		preview.stop()
		return # finished shows it again.
	var m: Cast.Member = members[current]
	preview.line = _line()
	record_button.text = "Record again" if m.recording else "Record their voice"


func _play() -> void:
	if preview.is_speaking():
		preview.stop()
		return
	preview.say(_line())
	play_button.text = "Stop"
	play_button.icon = Ui.icon("stop")

