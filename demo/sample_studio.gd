extends VBoxContainer
## "My voice" panel: record or load a sound, see it cut into syllables,
## tap pieces to hear or remove them, then speak with it.

## Something changed that the voice needs to pick up.
signal changed

const WaveView := preload("res://demo/wave_view.gd")

const PROMPTS := [
	"ba · dee · go · mah · loo · shee · ka · ti · po",
	"wobba · lee · doo · nah · mi · zo · fee · ga · ru",
	"tika · boo · lah · neh · moh · ree · sha · gu · pi",
	"Make any noises you like: hum, squeak, growl, quack, beep...",
]

## [name, pitch multiplier, size]
const CHARACTERS := [
	["As recorded", 1.0, 1.0],
	["Tiny critter", 2.4, 1.7],
	["Kid", 1.5, 1.25],
	["A bit higher", 1.25, 1.1],
	["A bit lower", 0.8, 0.92],
	["Big brute", 0.6, 0.8],
	["Giant", 0.45, 0.68],
]

var bank: BlabberSampleBank
var use_bank := false
var pitch_mul := 1.0
var size_scale := 1.0
var melody := 0.8
var variety := 3

var recorder: BlabberRecorder
var importer: BlabberAudioImport
var wave: WaveView
var audition: AudioStreamPlayer
var prompt_label: Label
var record_button: Button
var level_bar: ProgressBar
var use_check: CheckButton
var remove_check: CheckButton
var sensitivity_slider: HSlider
var info: Label
var file_dialog: FileDialog
var load_button: Button
var character_opt: OptionButton
var melody_slider: HSlider
var variety_slider: HSlider
var _prompt_i := 0
var _busy := false


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	recorder = BlabberRecorder.new()
	add_child(recorder)
	importer = BlabberAudioImport.new()
	add_child(importer)
	audition = AudioStreamPlayer.new()
	add_child(audition)

	add_child(_label("Read this out loud, or make any sound:", 14, 0.7))
	var prow := HBoxContainer.new()
	prompt_label = _label(PROMPTS[0], 20, 1.0)
	prompt_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(prompt_label)
	prow.add_child(_button("New line", _next_prompt))
	add_child(prow)

	var rrow := HBoxContainer.new()
	record_button = _button("Record", _toggle_record)
	record_button.custom_minimum_size = Vector2(150, 44)
	rrow.add_child(record_button)
	load_button = _button("Load file…", _open_file)
	load_button.custom_minimum_size = Vector2(0, 44)
	rrow.add_child(load_button)
	add_child(rrow)
	level_bar = ProgressBar.new()
	level_bar.max_value = 1.0
	level_bar.show_percentage = false
	level_bar.custom_minimum_size = Vector2(0, 6)
	add_child(level_bar)
	if BlabberWeb.available():
		add_child(_label("Load file works with voice memos and most audio files.", 13, 0.5))
	else:
		add_child(_label("Tip: you can also drop a WAV, OGG or MP3 file on the window.", 13, 0.5))

	wave = WaveView.new()
	wave.custom_minimum_size = Vector2(0, 110)
	wave.slice_pressed.connect(_on_slice_pressed)
	add_child(wave)
	var trow := HBoxContainer.new()
	var tap_label := _label("Tap a piece to hear it.", 13, 0.6)
	tap_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(tap_label)
	remove_check = CheckButton.new()
	remove_check.text = "Tap removes"
	trow.add_child(remove_check)
	add_child(trow)

	sensitivity_slider = _slider("Cut into", 0.0, 1.0, 0.01, 0.5, func(v: float) -> void:
		if bank:
			bank.sensitivity = v
			bank.analyze()
			_show_bank())
	sensitivity_slider.drag_ended.connect(func(_c: bool) -> void: changed.emit())

	var crow := HBoxContainer.new()
	var cl := _label("Character", 14, 1.0)
	cl.custom_minimum_size = Vector2(110, 0)
	crow.add_child(cl)
	var copt := OptionButton.new()
	character_opt = copt
	for c in CHARACTERS:
		copt.add_item(c[0])
	copt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copt.item_selected.connect(func(i: int) -> void:
		pitch_mul = CHARACTERS[i][1]
		size_scale = CHARACTERS[i][2]
		changed.emit())
	crow.add_child(copt)
	add_child(crow)
	melody_slider = _slider("Follow melody", 0.0, 1.0, 0.01, melody, func(v: float) -> void:
		melody = v
		changed.emit())
	variety_slider = _slider("Variety", 1.0, 8.0, 1.0, variety, func(v: float) -> void:
		variety = int(v)
		changed.emit())

	use_check = CheckButton.new()
	use_check.text = "Speak with my voice"
	use_check.disabled = true
	use_check.toggled.connect(func(on: bool) -> void:
		use_bank = on
		changed.emit())
	add_child(use_check)
	info = _label("", 13, 0.6)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(info)
	var problem := BlabberRecorder.problem()
	if problem != "":
		info.text = problem

	recorder.level_changed.connect(func(l: float) -> void: level_bar.value = l)
	recorder.stopped.connect(_finish_recording)
	get_window().files_dropped.connect(func(files: PackedStringArray) -> void:
		# Voice files go to the library panel instead.
		if files[0].get_extension().to_lower() != BlabberVoiceFile.EXTENSION:
			load_path(files[0]))
	# On the web, _process also keeps the file input lined up with its button.
	set_process(BlabberWeb.available())


func _process(_delta: float) -> void:
	if BlabberWeb.available():
		_web_file_input()
	if recorder.recording:
		wave.append_audio(recorder.samples, 0, recorder.rate)
		record_button.text = "Stop  %.1fs" % recorder.seconds()


func _toggle_record() -> void:
	if _busy:
		return
	if recorder.recording:
		recorder.stop() # _finish_recording runs from the stopped signal.
		return
	audition.stop()
	if not recorder.start():
		info.text = BlabberRecorder.problem()
		return
	wave.clear()
	wave.min_seconds = 6.0
	info.text = "Recording… up to %d seconds." % int(BlabberRecorder.MAX_SECONDS)
	set_process(true)


func _finish_recording(result: Dictionary) -> void:
	set_process(BlabberWeb.available())
	record_button.text = "Record"
	level_bar.value = 0.0
	if not result.ok:
		info.text = result.error
		return
	_use_audio(result.samples, result.rate, "your recording")


func _open_file() -> void:
	if BlabberWeb.available():
		_pick_web()
		return
	if file_dialog == null:
		file_dialog = FileDialog.new()
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.use_native_dialog = true
		file_dialog.filters = PackedStringArray(["*.wav, *.ogg, *.mp3 ; Audio files"])
		file_dialog.file_selected.connect(load_path)
		add_child(file_dialog)
	file_dialog.popup_centered_ratio(0.7)


## Web: an invisible file input sits over the Load button (browsers only open
## a file picker from a real tap), and the browser decodes the chosen file.
func _web_file_input() -> void:
	var clip := Rect2()
	var p := get_parent()
	if p is Control:
		clip = (p as Control).get_global_rect()
	BlabberWeb.place_file_input(load_button, load_button.is_visible_in_tree() and not recorder.recording and not _busy, clip)
	if BlabberWeb.file_kind() != "audio":
		return # A voice file for the library panel.
	match BlabberWeb.state():
		"decoding":
			info.text = "Reading %s…" % BlabberWeb.file_name()
		"done":
			var samples := BlabberWeb.take_file()
			_use_audio(samples, BlabberWeb.rate(), BlabberWeb.file_name())
		"error":
			info.text = BlabberWeb.error()
			BlabberWeb.reset()


## Web fallback: open the browser's picker from code. It decodes the file itself, so .m4a voice memos work.
func _pick_web() -> void:
	if recorder.recording:
		return
	info.text = "Choose an audio file…"
	var result: Dictionary = await importer.pick_file_web()
	if not result.ok:
		info.text = result.error if result.error != "" else ""
		return
	_use_audio(result.samples, result.rate, result.name)


func load_path(path: String) -> void:
	if _busy or recorder.recording:
		return
	if not path.get_extension().to_lower() in BlabberAudioImport.EXTENSIONS:
		info.text = "Use a WAV, OGG or MP3 file."
		return
	_busy = true
	info.text = "Loading %s…" % path.get_file()
	if path.get_extension().to_lower() != "wav":
		info.text += " (compressed files take as long as the clip to decode)"
	var result: Dictionary = await importer.load_file(path)
	_busy = false
	if not result.ok:
		info.text = result.error
		return
	_use_audio(result.samples, result.rate, path.get_file())


func _use_audio(samples: PackedFloat32Array, rate: int, source: String) -> void:
	var b := BlabberSampleBank.from_samples(samples, rate, sensitivity_slider.value)
	if b.slice_count() == 0:
		info.text = "Couldn't hear anything in %s. Try recording closer to the mic." % source
		wave.clear()
		return
	bank = b
	_show_bank()
	use_check.disabled = false
	use_check.set_pressed_no_signal(true)
	use_bank = true
	changed.emit()


func _show_bank() -> void:
	wave.min_seconds = 0.5
	wave.set_audio(bank.audio, bank.sample_rate)
	var order := range(bank.slice_count())
	order.sort_custom(func(x, y): return bank.slice_brightness[x] < bank.slice_brightness[y])
	var rank := {}
	for r in order.size():
		rank[order[r]] = float(r) / maxf(1.0, order.size() - 1.0)
	wave.slices = []
	for i in bank.slice_count():
		# Warm colors = dark "oo" sounds, cool colors = bright "ee" sounds.
		var c := Color.from_hsv(lerpf(0.05, 0.6, rank[i]), 0.7, 1.0)
		if bank.slice_pitch[i] <= 0.0:
			c = Color(0.8, 0.8, 0.8)
		wave.slices.append({"a": bank.slice_starts[i] / float(bank.sample_rate),
			"b": bank.slice_ends[i] / float(bank.sample_rate), "color": c, "on": bank.slice_enabled[i] == 1})
	wave.queue_redraw()
	_update_info()


func _update_info() -> void:
	var pitched := 0
	for i in bank.slice_count():
		if bank.slice_enabled[i] and bank.slice_pitch[i] > 0.0:
			pitched += 1
	info.text = "%d pieces (%d in use, %d with a clear pitch). Typical pitch: %s." % [
		bank.slice_count(), bank.active_count(), pitched,
		("%d Hz" % int(bank.base_pitch)) if bank.base_pitch > 0.0 else "none (noises)"]


func _on_slice_pressed(i: int) -> void:
	if remove_check.button_pressed:
		bank.set_slice_enabled(i, bank.slice_enabled[i] == 0)
		wave.slices[i].on = bank.slice_enabled[i] == 1
		_update_info()
		changed.emit()
	else:
		audition.stream = bank.slice_stream(i)
		audition.play()
	wave.highlight = i
	wave.queue_redraw()


## Shows the recording of a voice opened from the library, or switches
## "Speak with my voice" off if it has none.
func show_voice(voice: BlabberVoice) -> void:
	var b := voice.sample_bank
	if b == null or b.slice_count() == 0:
		use_bank = false
		use_check.set_pressed_no_signal(false)
		return
	bank = b
	use_bank = true
	use_check.disabled = false
	use_check.set_pressed_no_signal(true)
	pitch_mul = voice.pitch / bank.reference_pitch()
	size_scale = voice.formant_scale
	melody = voice.sample_melody
	variety = voice.sample_variety
	melody_slider.set_value_no_signal(melody)
	variety_slider.set_value_no_signal(variety)
	sensitivity_slider.set_value_no_signal(bank.sensitivity)
	character_opt.select(-1)
	for i in CHARACTERS.size():
		if is_equal_approx(CHARACTERS[i][1], snappedf(pitch_mul, 0.01)) and is_equal_approx(CHARACTERS[i][2], size_scale):
			character_opt.select(i)
	_show_bank()


## Copies this panel's settings onto a voice.
func apply_to(voice: BlabberVoice) -> void:
	if use_bank and bank != null and bank.active_count() > 0:
		voice.sample_bank = bank
		voice.pitch = bank.reference_pitch() * pitch_mul
		voice.formant_scale = size_scale
		voice.sample_melody = melody
		voice.sample_variety = variety
	else:
		voice.sample_bank = null


func _next_prompt() -> void:
	_prompt_i = (_prompt_i + 1) % PROMPTS.size()
	prompt_label.text = PROMPTS[_prompt_i]


func _label(t: String, font_size: int, alpha: float) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", font_size)
	l.modulate = Color(1, 1, 1, alpha)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	return b


func _slider(title: String, lo: float, hi: float, step: float, value: float, cb: Callable) -> HSlider:
	var row := HBoxContainer.new()
	var l := _label(title, 14, 1.0)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size = Vector2(110, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(cb)
	row.add_child(s)
	add_child(row)
	return s
