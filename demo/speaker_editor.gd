extends VBoxContainer
## Settings for one character: the bubble's look and the voice. The compact
## version (beside the line) has the main ones; the full version has all.

## Something changed. what: "name", "bubble" or "voice".
signal changed(what: String)
## "All settings" was pressed in the compact version.
signal more_pressed

const Ui := preload("res://demo/ui.gd")
const Cast := preload("res://demo/cast.gd")

## [property, label, min, max, step, format]
const MAIN_SLIDERS := [
	["pitch", "Pitch", 30.0, 1200.0, 1.0, "%d Hz"],
	["formant_scale", "Size", 0.4, 2.5, 0.01, "%.2f×"],
	["speed", "Speed", 0.3, 3.0, 0.01, "%.2f×"],
]
const MORE_SLIDERS := [
	["intonation", "Melody", 0.0, 12.0, 0.1, "%.1f st"],
	["pitch_variation", "Pitch wobble", 0.0, 8.0, 0.1, "%.1f st"],
	["articulation", "Clarity", 0.0, 1.0, 0.01, "%.2f"],
	["sibilance", "Hiss (s, sh)", 0.0, 2.0, 0.01, "%.2f"],
	["tenseness", "Tension", 0.0, 1.0, 0.01, "%.2f"],
	["breathiness", "Breath", 0.0, 1.0, 0.01, "%.2f"],
	["roughness", "Roughness", 0.0, 1.0, 0.01, "%.2f"],
	["growl", "Growl", 0.0, 1.0, 0.01, "%.2f"],
	["jitter", "Shakiness", 0.0, 0.1, 0.001, "%.3f"],
	["vibrato_depth", "Vibrato", 0.0, 2.0, 0.01, "%.2f"],
	["ring_mod_mix", "Robot ring", 0.0, 1.0, 0.01, "%.2f"],
	["volume", "Volume", 0.0, 2.0, 0.01, "%.2f"],
]
## [label, size, x, y, alpha]
const SHADOWS := [["None", 0, 0, 0, 0.0], ["Drop", 1, 0, 6, 0.25], ["Offset", 1, 6, 6, 1.0], ["Glow", 8, 0, 0, 0.3]]

var full := false
var member: Cast.Member

var name_title: Label
var kind_label: Label
var name_edit: LineEdit
var preset_opt: OptionButton
var font_opt: OptionButton
var colors := {}
var corner_buttons: Array = []
var shadow_buttons: Array = []
var sliders := {}
var values := {}
var words_check: CheckButton
var vocab_check: CheckButton
var tail_check: CheckButton
var _syncing := false


func _init(p_full := false) -> void:
	full = p_full


func _ready() -> void:
	add_theme_constant_override("separation", 24)
	if full:
		var who := Ui.vbox(8)
		who.add_child(Ui.eyebrow("Name"))
		name_edit = LineEdit.new()
		name_edit.max_length = BlabberVoiceFile.MAX_NAME
		name_edit.custom_minimum_size.y = 44
		name_edit.text_changed.connect(func(t: String) -> void:
			if _syncing or member == null:
				return
			var clean := BlabberVoiceFile.clean_name(t)
			if clean != "":
				member.speaker.display_name = clean
				changed.emit("name"))
		who.add_child(name_edit)
		add_child(who)
	else:
		var who := Ui.vbox(2)
		who.add_child(Ui.eyebrow("Speaker"))
		name_title = Ui.heading("", 24)
		who.add_child(name_title)
		kind_label = Ui.label("", 14, Ui.DIM)
		who.add_child(kind_label)
		add_child(who)

	# Bubble
	var bubble := Ui.vbox(14)
	bubble.add_child(Ui.heading("Bubble"))
	var frow := Ui.vbox(6)
	frow.add_child(Ui.label("Font", 14, Ui.TEXT_2))
	font_opt = OptionButton.new()
	font_opt.custom_minimum_size.y = 44
	font_opt.fit_to_longest_item = false
	font_opt.clip_text = true
	for k in Cast.FONTS:
		font_opt.add_item(Cast.FONTS[k].label)
		font_opt.set_item_metadata(font_opt.item_count - 1, k)
	font_opt.add_item("Font from a file")
	font_opt.set_item_metadata(font_opt.item_count - 1, "")
	font_opt.set_item_disabled(font_opt.item_count - 1, true)
	font_opt.item_selected.connect(func(i: int) -> void:
		var key: String = font_opt.get_item_metadata(i)
		if key != "":
			Cast.set_font(member.speaker.bubble, key)
			_sync()
			changed.emit("bubble"))
	frow.add_child(font_opt)
	bubble.add_child(frow)
	if full:
		bubble.add_child(_slider_row("font_size", ["", "Text size", 14.0, 48.0, 1.0, "%d px"], _bubble_value))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var swatches := [["bg_color", "Fill"], ["border_color", "Outline"]]
	if full:
		swatches += [["text_color", "Text"], ["muted_color", "Whisper"], ["name_color", "Name tag"], ["name_text_color", "Name text"]]
	for s in swatches:
		grid.add_child(_swatch(s[0], s[1]))
	bubble.add_child(grid)

	var crow := Ui.vbox(6)
	crow.add_child(Ui.label("Corners", 14, Ui.TEXT_2))
	var seg := Ui.segmented(["Round", "Soft", "Square"])
	corner_buttons = seg[1]
	var keys := Cast.CORNERS.keys()
	for i in corner_buttons.size():
		corner_buttons[i].pressed.connect(func() -> void:
			member.speaker.bubble.set_corner_radius_all(Cast.CORNERS[keys[i]])
			changed.emit("bubble"))
	crow.add_child(seg[0])
	bubble.add_child(crow)

	if full:
		bubble.add_child(_slider_row("outline", ["", "Outline width", 0.0, 8.0, 1.0, "%d px"], _bubble_value))
		var srow := Ui.vbox(6)
		srow.add_child(Ui.label("Shadow", 14, Ui.TEXT_2))
		var labels: Array = []
		for s in SHADOWS:
			labels.append(s[0])
		var sseg := Ui.segmented(labels)
		shadow_buttons = sseg[1]
		for i in shadow_buttons.size():
			shadow_buttons[i].pressed.connect(func() -> void:
				var s: Array = SHADOWS[i]
				var b := member.speaker.bubble
				b.shadow_size = s[1]
				b.shadow_offset = Vector2(s[2], s[3])
				var tint := b.border_color if i >= 2 else Color.BLACK
				b.shadow_color = Color(tint, s[4])
				changed.emit("bubble"))
		srow.add_child(sseg[0])
		bubble.add_child(srow)
		tail_check = CheckButton.new()
		tail_check.text = "Tail pointing at the speaker"
		tail_check.toggled.connect(func(on: bool) -> void:
			if not _syncing:
				member.speaker.bubble.tail = on
				changed.emit("bubble"))
		bubble.add_child(tail_check)
	add_child(bubble)

	# Voice
	var voice := Ui.vbox(14)
	voice.add_child(Ui.heading("Voice"))
	if full:
		var prow := Ui.vbox(6)
		prow.add_child(Ui.label("Start from", 14, Ui.TEXT_2))
		preset_opt = OptionButton.new()
		preset_opt.custom_minimum_size.y = 44
		for n in BlabberVoice.PRESET_NAMES:
			preset_opt.add_item(n.capitalize())
		preset_opt.item_selected.connect(_use_preset)
		prow.add_child(preset_opt)
		voice.add_child(prow)
	for spec in MAIN_SLIDERS:
		voice.add_child(_slider_row(spec[0], spec, _voice_value))
	words_check = CheckButton.new()
	words_check.text = "Says real words"
	words_check.tooltip_text = "Off: made-up gibberish in the character's own sounds."
	words_check.toggled.connect(func(on: bool) -> void:
		if _syncing:
			return
		member.speaker.voice.mode = BlabberVoice.Mode.PHONETIC if on else BlabberVoice.Mode.GIBBERISH
		changed.emit("voice"))
	voice.add_child(words_check)
	vocab_check = CheckButton.new()
	vocab_check.text = "Says vocabulary words with their recordings"
	vocab_check.tooltip_text = "Words on the Vocabulary page are spoken with your recordings, in this character's pitch and size."
	vocab_check.toggled.connect(func(on: bool) -> void:
		if _syncing:
			return
		member.set_use_vocabulary(on)
		changed.emit("voice"))
	voice.add_child(vocab_check)
	if full:
		for spec in MORE_SLIDERS:
			voice.add_child(_slider_row(spec[0], spec, _voice_value))
	else:
		var more := Ui.button("All settings", func() -> void: more_pressed.emit(), "right")
		more.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		voice.add_child(more)
	add_child(voice)
	if member:
		_sync()


func set_member(m: Cast.Member) -> void:
	member = m
	if is_node_ready():
		_sync()


## Shows the member's current values.
func refresh() -> void:
	if is_node_ready() and member:
		_sync()


func _sync() -> void:
	_syncing = true
	var sp := member.speaker
	var b := sp.bubble
	var v := sp.voice
	if name_title:
		name_title.text = sp.display_name
		kind_label.text = "%s · saved with each line, ready for games" % member.kind.capitalize()
	if name_edit and name_edit.text != sp.display_name and not name_edit.has_focus():
		name_edit.text = sp.display_name
	var key := member.font_key()
	for i in font_opt.item_count:
		if font_opt.get_item_metadata(i) == key:
			font_opt.select(i)
	for prop in colors:
		var c: Color = b.get(prop)
		colors[prop][0].color = c
		colors[prop][1].text = "#" + c.to_html(false).to_upper()
	var keys := Cast.CORNERS.keys()
	for i in corner_buttons.size():
		corner_buttons[i].set_pressed_no_signal(_closest_corner(b.corner_radius_top_left) == keys[i])
	for i in shadow_buttons.size():
		var s: Array = SHADOWS[i]
		var match_it: bool = (b.shadow_size == 0 or b.shadow_color.a == 0.0) if i == 0 else (b.shadow_size == s[1] and b.shadow_offset == Vector2(s[2], s[3]) and b.shadow_color.a > 0.0)
		shadow_buttons[i].set_pressed_no_signal(match_it)
	if tail_check:
		tail_check.set_pressed_no_signal(b.tail)
	if preset_opt:
		preset_opt.select(BlabberVoice.PRESET_NAMES.find(member.kind))
	for prop in sliders:
		var val: float
		match prop:
			"font_size":
				val = b.font_size
			"outline":
				val = b.border_width_top
			_:
				val = v.get(prop)
		sliders[prop].set_value_no_signal(val)
		values[prop].text = _fmt(prop, val)
	words_check.set_pressed_no_signal(v.mode == BlabberVoice.Mode.PHONETIC)
	vocab_check.set_pressed_no_signal(member.use_vocabulary)
	_syncing = false


static func _closest_corner(r: int) -> String:
	var best := "soft"
	var dist := 1 << 30
	for k in Cast.CORNERS:
		var d := absi(Cast.CORNERS[k] - r)
		if d < dist:
			dist = d
			best = k
	return best


func _swatch(prop: String, title: String) -> Control:
	var cell := PanelContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_stylebox_override("panel", Ui.box(Ui.CLEAR, 12, Ui.LINE, 1, 8, 6))
	var row := Ui.hbox(10)
	cell.add_child(row)
	var pick := ColorPickerButton.new()
	pick.custom_minimum_size = Vector2(32, 32)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := Ui.box(Ui.CLEAR, 8, Ui.LINE, 1, 3, 3)
		if st == "focus":
			sb.draw_center = false
			sb.border_color = Ui.ACCENT
		pick.add_theme_stylebox_override(st, sb)
	pick.edit_alpha = false
	pick.tooltip_text = "Change %s color" % title.to_lower()
	pick.color_changed.connect(func(c: Color) -> void:
		member.speaker.bubble.set(prop, c)
		colors[prop][1].text = "#" + c.to_html(false).to_upper()
		changed.emit("bubble"))
	row.add_child(pick)
	var text := Ui.vbox(0)
	var tl := Ui.label(title, 13, Ui.DIM)
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	text.add_child(tl)
	var hex := Ui.label("", 13, Ui.TEXT)
	hex.autowrap_mode = TextServer.AUTOWRAP_OFF
	hex.add_theme_font_override("font", Ui.FONT_MONO)
	text.add_child(hex)
	row.add_child(text)
	colors[prop] = [pick, hex]
	return cell


func _slider_row(prop: String, spec: Array, apply: Callable) -> Control:
	var box := Ui.vbox(4)
	var top := Ui.hbox(8)
	var l := Ui.label(spec[1], 14, Ui.TEXT_2)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(l)
	var val := Ui.label("", 13, Ui.TEXT)
	val.add_theme_font_override("font", Ui.FONT_MONO)
	val.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(val)
	box.add_child(top)
	var s := HSlider.new()
	s.min_value = spec[2]
	s.max_value = spec[3]
	s.step = spec[4]
	s.custom_minimum_size.y = 28
	s.value_changed.connect(func(x: float) -> void:
		val.text = _fmt(prop, x)
		if not _syncing:
			apply.call(prop, x))
	box.add_child(s)
	sliders[prop] = s
	values[prop] = val
	return box


func _voice_value(prop: String, x: float) -> void:
	var v := member.speaker.voice
	v.set(prop, x)
	if prop == "ring_mod_mix" and x > 0.0 and v.ring_mod_hz <= 0.0:
		v.ring_mod_hz = 70.0
	changed.emit("voice")


func _bubble_value(prop: String, x: float) -> void:
	var b := member.speaker.bubble
	if prop == "font_size":
		b.font_size = int(x)
	elif prop == "outline":
		b.set_border_width_all(int(x))
	changed.emit("bubble")


func _use_preset(i: int) -> void:
	var name: String = BlabberVoice.PRESET_NAMES[i]
	var old := member.speaker.voice
	var v := BlabberVoice.preset(name)
	v.mode = old.mode
	member.speaker.voice = v
	member.kind = name
	member.set_use_recording(member.use_recording)
	_sync()
	changed.emit("voice")


func _fmt(prop: String, x: float) -> String:
	for spec in MAIN_SLIDERS + MORE_SLIDERS:
		if spec[0] == prop:
			return spec[5] % (roundi(x) if "%d" in spec[5] else x)
	return "%d px" % roundi(x)
