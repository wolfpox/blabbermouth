extends Control
## Voice designer demo. Pick a preset, tweak sliders, type a line, press Speak.

const LINES := [
	"Hello there, traveler! Have you seen my little lantern? It was right here... I swear.",
	"[emote=scared]W-what was that noise?[/emote] [pause=0.4]Probably nothing. Probably.",
	"[shout]GET OUT OF MY SWAMP![/shout] [emote=sad]...unless you brought snacks.",
	"[whisper]Psst. The king is a frog.[/whisper] [speed=1.6]Don't tell anyone I told you!",
	"The [b]Crystal of Ages[/b] lies beyond the mountains. Will you go, [emote=excited]Hero?",
]

## [property, min, max, step]
const SLIDERS := [
	["pitch", 30.0, 1200.0, 1.0],
	["formant_scale", 0.4, 2.5, 0.01],
	["speed", 0.3, 3.0, 0.01],
	["intonation", 0.0, 12.0, 0.1],
	["pitch_variation", 0.0, 8.0, 0.1],
	["articulation", 0.0, 1.0, 0.01],
	["tenseness", 0.0, 1.0, 0.01],
	["breathiness", 0.0, 1.0, 0.01],
	["roughness", 0.0, 1.0, 0.01],
	["growl", 0.0, 1.0, 0.01],
	["jitter", 0.0, 0.1, 0.001],
	["vibrato_depth", 0.0, 2.0, 0.01],
	["ring_mod_mix", 0.0, 1.0, 0.01],
	["volume", 0.0, 2.0, 0.01],
]

const PRESET_COLORS := {
	"critter": Color(0.98, 0.78, 0.35), "child": Color(0.55, 0.85, 0.95),
	"woman": Color(0.95, 0.55, 0.7), "man": Color(0.5, 0.7, 0.95),
	"elder": Color(0.75, 0.75, 0.7), "goblin": Color(0.55, 0.85, 0.4),
	"monster": Color(0.6, 0.35, 0.75), "robot": Color(0.7, 0.8, 0.85),
}

var blab: Blabbermouth
var voice: BlabberVoice
var preset_name := "man"
var sliders := {}
var value_labels := {}
var preset_opt: OptionButton
var mode_check: CheckButton
var names_check: CheckButton
var text_edit: TextEdit
var speech: RichTextLabel
var status: Label
var face: Face
var playing_all := false


class Face extends Control:
	var openness := 0.0
	var body_color := Color.WHITE
	var blink := 0.0

	func _process(delta: float) -> void:
		blink = maxf(blink - delta, 0.0)
		if randf() < delta * 0.4:
			blink = 0.12
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.42
		draw_circle(c, r, body_color)
		var eye_y := c.y - r * 0.25
		for side in [-1.0, 1.0]:
			var e := Vector2(c.x + side * r * 0.35, eye_y)
			if blink > 0.0:
				draw_line(e - Vector2(r * 0.1, 0), e + Vector2(r * 0.1, 0), Color(0.1, 0.1, 0.12), 4.0)
			else:
				draw_circle(e, r * 0.11, Color.WHITE)
				draw_circle(e + Vector2(0, r * 0.02), r * 0.06, Color(0.1, 0.1, 0.12))
		# Mouth: an ellipse that opens with the voice.
		var mouth_c := Vector2(c.x, c.y + r * 0.35)
		var w := r * (0.42 - openness * 0.1)
		var h := r * (0.04 + openness * 0.3)
		var pts := PackedVector2Array()
		for i in 24:
			var a := TAU * i / 24.0
			pts.append(mouth_c + Vector2(cos(a) * w, sin(a) * h))
		draw_colored_polygon(pts, Color(0.25, 0.05, 0.08))


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.12, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	# Left: voice controls.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)

	panel.add_child(_title("Voice"))
	preset_opt = OptionButton.new()
	for n in BlabberVoice.PRESET_NAMES:
		preset_opt.add_item(n.capitalize())
	preset_opt.item_selected.connect(func(i: int) -> void: _load_preset(BlabberVoice.PRESET_NAMES[i]))
	panel.add_child(preset_opt)

	mode_check = CheckButton.new()
	mode_check.text = "Follow the letters (phonetic)"
	mode_check.toggled.connect(func(on: bool) -> void:
		voice.mode = BlabberVoice.Mode.PHONETIC if on else BlabberVoice.Mode.GIBBERISH)
	panel.add_child(mode_check)
	names_check = CheckButton.new()
	names_check.text = "Say capitalized names clearly"
	names_check.toggled.connect(func(on: bool) -> void: voice.speak_names = on)
	panel.add_child(names_check)

	for spec in SLIDERS:
		var prop: String = spec[0]
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = prop.capitalize()
		name_label.custom_minimum_size = Vector2(130, 0)
		row.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = spec[1]
		slider.max_value = spec[2]
		slider.step = spec[3]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(func(v: float) -> void:
			voice.set(prop, v)
			value_labels[prop].text = _fmt(v))
		row.add_child(slider)
		var vl := Label.new()
		vl.custom_minimum_size = Vector2(52, 0)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(vl)
		sliders[prop] = slider
		value_labels[prop] = vl
		panel.add_child(row)

	var save_row := HBoxContainer.new()
	save_row.add_child(_button("Save voice .tres", _save_voice))
	save_row.add_child(_button("Bake line .wav", _bake_line))
	panel.add_child(save_row)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.modulate = Color(1, 1, 1, 0.6)
	panel.add_child(status)

	# Right: character, speech bubble, input.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	root.add_child(right)

	face = Face.new()
	face.custom_minimum_size = Vector2(0, 220)
	face.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(face)

	speech = RichTextLabel.new()
	speech.bbcode_enabled = true
	speech.fit_content = true
	speech.custom_minimum_size = Vector2(0, 90)
	speech.add_theme_font_size_override("normal_font_size", 22)
	speech.add_theme_font_size_override("bold_font_size", 22)
	right.add_child(speech)

	text_edit = TextEdit.new()
	text_edit.text = LINES[0]
	text_edit.custom_minimum_size = Vector2(0, 90)
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	right.add_child(text_edit)

	var buttons := HBoxContainer.new()
	buttons.add_child(_button("Speak", _speak))
	buttons.add_child(_button("Skip", func() -> void: blab.skip()))
	buttons.add_child(_button("Next sample line", _next_line))
	buttons.add_child(_button("Play every voice", _play_all))
	right.add_child(buttons)

	var help := Label.new()
	help.text = "Tags: [pause=0.5] [speed=1.5] [pitch=1.2] [volume=0.5] [emote=happy|excited|angry|sad|scared] [whisper] [shout] [reset]"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(1, 1, 1, 0.5)
	right.add_child(help)

	blab = Blabbermouth.new()
	blab.label = speech
	add_child(blab)
	blab.mouth_moved.connect(func(o: float) -> void: face.openness = o)

	preset_opt.select(BlabberVoice.PRESET_NAMES.find(preset_name))
	_load_preset(preset_name)


func _title(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 20)
	return l


func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	return b


func _fmt(v: float) -> String:
	return str(snappedf(v, 0.001))


func _load_preset(n: String) -> void:
	preset_name = n
	voice = BlabberVoice.preset(n)
	for prop in sliders:
		sliders[prop].set_value_no_signal(voice.get(prop))
		value_labels[prop].text = _fmt(voice.get(prop))
	mode_check.set_pressed_no_signal(voice.mode == BlabberVoice.Mode.PHONETIC)
	names_check.set_pressed_no_signal(voice.speak_names)
	face.body_color = PRESET_COLORS.get(n, Color.WHITE)


func _speak() -> void:
	blab.speak(text_edit.text, voice)


func _next_line() -> void:
	var i := (LINES.find(text_edit.text) + 1) % LINES.size()
	text_edit.text = LINES[i]
	_speak()


func _play_all() -> void:
	if playing_all:
		return
	playing_all = true
	for n in BlabberVoice.PRESET_NAMES:
		preset_opt.select(BlabberVoice.PRESET_NAMES.find(n))
		_load_preset(n)
		_speak()
		await blab.finished
		await get_tree().create_timer(0.3).timeout
	playing_all = false


func _save_voice() -> void:
	var path := "user://%s_custom.tres" % preset_name
	var err := ResourceSaver.save(voice, path)
	status.text = ("Saved " + ProjectSettings.globalize_path(path)) if err == OK else "Save failed (%d)" % err


func _bake_line() -> void:
	var path := "user://%s_line.wav" % preset_name
	var err := Blabbermouth.bake(text_edit.text, voice).save_to_wav(path)
	status.text = ("Baked " + ProjectSettings.globalize_path(path)) if err == OK else "Bake failed (%d)" % err
