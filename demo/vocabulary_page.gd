extends VBoxContainer
## The Vocabulary page: words and phrases that characters say with real
## recordings. Each word has one or more takes; a line picks one each time
## the word comes up, and plays it at the character's pitch and size with
## the line's effects.

## The vocabulary was edited (save it).
signal changed
## Export was pressed: save or download the vocabulary file.
signal export_pressed

const Ui := preload("res://demo/ui.gd")
const Clickable := preload("res://demo/clickable.gd")
const Cast := preload("res://demo/cast.gd")

## Stop recording a take after this long without sound.
const QUIET_STOP := 0.8

var vocab: BlabberVocabulary
## Returns the current character (a Cast.Member), who says the words.
var get_member: Callable
## Returns every character, to count who uses the vocabulary.
var get_members: Callable

var add_edit: LineEdit
var add_button: Button
var fit_check: CheckButton
var users_label: Label
var list: VBoxContainer
var empty_label: Label
var status: Label
var export_button: Button
var top: BoxContainer
var recorder: BlabberRecorder
var importer: BlabberAudioImport
var player: AudioStreamPlayer
var file_dialog: FileDialog
## Key of the word that's open, "" for none.
var open_key := ""

var _record_button: Button
var _load_button: Button
var _level: ProgressBar
var _recording_key := ""
var _loud_seen := 0.0
var _quiet_for := 0.0
var _hear_take := {}
var _busy := false
## Web: the word each Load button (by instance id) adds its file to.
var _load_words := {}


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	recorder = BlabberRecorder.new()
	add_child(recorder)
	recorder.level_changed.connect(func(l: float) -> void:
		if _level:
			_level.value = l)
	recorder.stopped.connect(_finish_recording)
	importer = BlabberAudioImport.new()
	add_child(importer)
	player = AudioStreamPlayer.new()
	add_child(player)

	top = BoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	var title := Ui.heading("Vocabulary", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	export_button = Ui.button("Export vocabulary", export_pressed.emit, "export")
	export_button.tooltip_text = "Every word and its takes as one .blab file, for any voice in a game"
	top.add_child(export_button)
	add_child(top)
	add_child(Ui.label("Words and phrases your characters say with real recordings instead of their voice. Record a take or two of each; whenever a line uses the word, the character plays one of them, at their own pitch and size, with the line's effects.", 14, Ui.DIM))

	var panel := Ui.panel(Ui.CARD, 24, 22, 20)
	var pv := Ui.vbox(14)
	panel.add_child(pv)
	var row := Ui.hbox(10)
	add_edit = LineEdit.new()
	add_edit.placeholder_text = "A word or phrase, like “hello” or “thank you”"
	add_edit.max_length = BlabberVocabulary.MAX_TEXT
	add_edit.custom_minimum_size.y = 46
	add_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_edit.text_submitted.connect(func(_t: String) -> void: _add())
	add_edit.text_changed.connect(func(_t: String) -> void: _update_add())
	row.add_child(add_edit)
	add_button = Ui.button("Add word", _add, "plus", "Primary")
	add_button.custom_minimum_size.y = 46
	row.add_child(add_button)
	pv.add_child(row)
	fit_check = CheckButton.new()
	fit_check.text = "Fit takes to each character"
	fit_check.tooltip_text = "On: takes play at the character's pitch, size and speed.\nOff: takes keep the recorded voice, and only the line's effects change them."
	fit_check.toggled.connect(func(on: bool) -> void:
		vocab.fit_to_voice = on
		changed.emit())
	pv.add_child(fit_check)
	users_label = Ui.label("", 13, Ui.FAINT)
	pv.add_child(users_label)
	add_child(panel)

	status = Ui.label("", 14, Ui.ACCENT)
	status.visible = false
	add_child(status)
	list = Ui.vbox(10)
	add_child(list)
	empty_label = Ui.label("No words yet. Add one above, then record yourself saying it. Phrases of up to %d words work too." % BlabberVocabulary.MAX_PHRASE, 14, Ui.DIM)
	add_child(empty_label)
	set_process(false)


func set_narrow(_narrow: bool, phone := false) -> void:
	top.vertical = phone
	add_button.text = "Add" if phone else "Add word"


## Shows a vocabulary (and who'll say its words).
func show_vocabulary(p_vocab: BlabberVocabulary) -> void:
	if vocab != p_vocab:
		open_key = ""
	vocab = p_vocab
	refresh()


func refresh() -> void:
	if vocab == null or not is_node_ready():
		return
	fit_check.set_pressed_no_signal(vocab.fit_to_voice)
	_update_users()
	_update_add()
	if _load_button and is_instance_valid(_load_button):
		BlabberWeb.place_file_input(_load_button, false) # It's about to go.
	_record_button = null
	_load_button = null
	_level = null
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	var words := vocab.words.duplicate()
	words.sort_custom(func(a, b): return a.key < b.key)
	for w in words:
		list.add_child(_word_card(w))
	empty_label.visible = words.is_empty()
	export_button.disabled = vocab.lookup().is_empty()
	set_process(BlabberWeb.available() or recorder.recording)


func _update_users() -> void:
	var m: Cast.Member = get_member.call()
	var all: Array = get_members.call()
	var n := 0
	for x in all:
		if x.use_vocabulary:
			n += 1
	var who := "Plays as %s." % m.speaker.display_name
	if n == all.size():
		users_label.text = "Every character uses these words. %s Turn it off for one in their settings (Characters)." % who
	else:
		users_label.text = "%d of %d characters use these words (switch it in Characters). %s" % [n, all.size(), who]


func _update_add() -> void:
	add_button.disabled = BlabberVocabulary.key_of(add_edit.text) == ""


func _add() -> void:
	var text := add_edit.text.strip_edges()
	var k := BlabberVocabulary.key_of(text)
	if k == "":
		return
	if k.count(" ") >= BlabberVocabulary.MAX_PHRASE:
		_say("Phrases can have up to %d words." % BlabberVocabulary.MAX_PHRASE)
		return
	var existed := vocab.find(text) != null
	var w := vocab.add_word(text)
	if w == null:
		_say("Couldn't add “%s”." % text)
		return
	add_edit.text = ""
	open_key = w.key
	if not existed:
		changed.emit()
	refresh()
	_say("“%s” is already in the vocabulary." % w.text if existed else "Added “%s”. Now record a take of you saying it." % w.text)


# --- A word -----------------------------------------------------------------------

func _word_card(w: BlabberWord) -> Control:
	var is_open := w.key == open_key
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Ui.box(Ui.PANEL, 20, Ui.ACCENT if is_open else Ui.CLEAR, 1 if is_open else 0, 18, 14))
	var v := Ui.vbox(12)
	card.add_child(v)

	var head := Ui.hbox(12)
	var title := Clickable.new(Ui.box(Ui.CLEAR, 10, Ui.CLEAR, 0, 4, 6), Ui.box(Ui.RAISED, 10, Ui.CLEAR, 0, 4, 6))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.tooltip_text = "Close" if is_open else "Record takes, or remove the word"
	title.pressed.connect(func() -> void:
		open_key = "" if is_open else w.key
		refresh())
	var tv := Ui.hbox(12)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chev := TextureRect.new()
	chev.texture = Ui.icon("down" if is_open else "right")
	chev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chev.custom_minimum_size = Vector2(18, 18)
	chev.modulate = Ui.DIM
	chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(chev)
	var name_l := Ui.label(w.text, 19, Ui.TEXT, true)
	name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(name_l)
	var count := Ui.label(_takes_text(w), 13, Ui.DIM if not w.takes.is_empty() else Ui.REC)
	count.autowrap_mode = TextServer.AUTOWRAP_OFF
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(count)
	title.add_child(tv)
	head.add_child(title)
	var hear := Ui.button("Hear", _hear.bind(w), "play")
	hear.disabled = w.takes.is_empty()
	var who: String = get_member.call().speaker.display_name
	hear.tooltip_text = "Hear %s say it (a different take each time)" % who
	head.add_child(hear)
	v.add_child(head)
	if not is_open:
		return card

	# Takes, as recorded.
	if not w.takes.is_empty():
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		for i in w.takes.size():
			flow.add_child(_take_chip(w, i))
		v.add_child(flow)
	var rows := HFlowContainer.new()
	rows.add_theme_constant_override("h_separation", 10)
	rows.add_theme_constant_override("v_separation", 10)
	var full := w.takes.size() >= BlabberVocabulary.MAX_TAKES
	var recording_this := recorder.recording and _recording_key == w.key
	_record_button = Ui.button("Stop" if recording_this else "Record a take", _toggle_record.bind(w), "stop" if recording_this else "rec")
	if not recording_this:
		_record_button.add_theme_color_override("icon_normal_color", Ui.REC)
		_record_button.add_theme_color_override("icon_hover_color", Ui.REC)
	_record_button.disabled = (full and not recording_this) or _busy or (recorder.recording and not recording_this)
	rows.add_child(_record_button)
	_load_button = Ui.button("Load file…", _open_file.bind(w), "open")
	_load_button.disabled = full or _busy or recorder.recording
	_load_words[str(_load_button.get_instance_id())] = w.key
	rows.add_child(_load_button)
	rows.add_child(Ui.spacer())
	var del := Ui.button("Remove word", _remove.bind(w), "trash")
	rows.add_child(del)
	v.add_child(rows)
	_level = ProgressBar.new()
	_level.max_value = 1.0
	_level.show_percentage = false
	_level.custom_minimum_size.y = 6
	_level.visible = recording_this
	v.add_child(_level)
	var hint := "Say “%s” once. Recording stops by itself when you go quiet." % w.text
	if full:
		hint = "That's the most takes a word can have (%d). Remove one to record another." % BlabberVocabulary.MAX_TAKES
	elif w.takes.is_empty():
		hint += " Until it has a take, the voice says this word as usual."
	else:
		hint += " Tap a take to hear it as recorded."
	if BlabberRecorder.problem() != "":
		hint = BlabberRecorder.problem()
	v.add_child(Ui.label(hint, 13, Ui.FAINT))
	return card


func _takes_text(w: BlabberWord) -> String:
	match w.takes.size():
		0: return "no takes yet"
		1: return "1 take"
	return "%d takes" % w.takes.size()


func _take_chip(w: BlabberWord, i: int) -> Control:
	var clip: BlabberClip = w.takes[i]
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", Ui.box(Ui.RAISED, 12, Ui.LINE, 1, 4, 2))
	var row := Ui.hbox(0)
	chip.add_child(row)
	var play := Button.new()
	play.text = "Take %d · %.1f s" % [i + 1, clip.duration()]
	play.icon = Ui.icon("play")
	play.flat = true
	play.custom_minimum_size.y = 40
	play.tooltip_text = "Hear take %d as recorded%s" % [i + 1, "" if clip.pitch > 0.0 else " (no clear pitch, so it can't follow the melody)"]
	play.pressed.connect(func() -> void:
		player.stream = clip.stream()
		player.play())
	row.add_child(play)
	var x := Button.new()
	x.icon = Ui.icon("x")
	x.flat = true
	x.custom_minimum_size = Vector2(40, 40)
	x.tooltip_text = "Remove take %d" % (i + 1)
	x.pressed.connect(func() -> void:
		w.takes.remove_at(i)
		vocab.emit_changed()
		changed.emit()
		refresh()
		_say("Removed take %d of “%s”." % [i + 1, w.text]))
	row.add_child(x)
	return chip


## Plays the word in the current character's voice, a different take each time.
func _hear(w: BlabberWord) -> void:
	if w.takes.is_empty():
		return
	var m: Cast.Member = get_member.call()
	var voice := m.speaker.voice
	var take: int = (_hear_take.get(w.key, -1) + 1) % w.takes.size()
	_hear_take[w.key] = take
	var had := voice.vocabulary
	voice.vocabulary = vocab # Even if this character has it switched off.
	player.stream = Blabbermouth.bake(w.text, voice, 22050, take)
	voice.vocabulary = had
	player.play()
	if w.takes.size() > 1:
		_say("%s says “%s”, take %d." % [m.speaker.display_name, w.text, take + 1])


func _remove(w: BlabberWord) -> void:
	if recorder.recording:
		return
	vocab.remove_word(w.text)
	open_key = ""
	changed.emit()
	refresh()
	_say("Removed “%s”. Lines say it with the voice again." % w.text)


# --- Recording and loading ------------------------------------------------------------

func _toggle_record(w: BlabberWord) -> void:
	if recorder.recording:
		recorder.stop() # _finish_recording runs from the stopped signal.
		return
	player.stop()
	if not recorder.start():
		_say(BlabberRecorder.problem())
		return
	_recording_key = w.key
	_loud_seen = 0.0
	_quiet_for = 0.0
	refresh()
	_say("Recording… say “%s”." % w.text)


func _process(delta: float) -> void:
	if recorder.recording:
		_watch_quiet(delta)
		if _record_button:
			_record_button.text = "Stop  %.1fs" % recorder.seconds()
	if BlabberWeb.available():
		_web_file_input()


## Stops by itself once the word has been said and it's gone quiet.
func _watch_quiet(delta: float) -> void:
	var s := recorder.samples
	var n := mini(s.size(), int(recorder.rate * 0.05))
	var peak := 0.0
	for i in range(s.size() - n, s.size()):
		peak = maxf(peak, absf(s[i]))
	_loud_seen = maxf(_loud_seen, peak)
	if _loud_seen > 0.05 and peak < _loud_seen * 0.12:
		_quiet_for += delta
	else:
		_quiet_for = 0.0
	if _quiet_for >= QUIET_STOP or recorder.seconds() >= BlabberClip.MAX_SECONDS + QUIET_STOP + 1.0:
		recorder.stop()


func _finish_recording(result: Dictionary) -> void:
	var key := _recording_key
	_recording_key = ""
	if not result.ok:
		refresh()
		_say(result.error)
		return
	_add_audio(key, result.samples, result.rate, "")


func _add_audio(key: String, samples: PackedFloat32Array, rate: int, source: String) -> void:
	var w := vocab.find(key)
	if w == null:
		refresh()
		return
	var long := samples.size() > (BlabberClip.MAX_SECONDS + 1.0) * rate
	var clip := BlabberClip.from_samples(samples, rate)
	if clip.audio.is_empty():
		refresh()
		_say("Couldn't hear anything%s. Try again a little closer to the mic." % ((" in " + source) if source != "" else ""))
		return
	if not vocab.add_clip(w.text, clip):
		refresh()
		_say("“%s” already has %d takes." % [w.text, BlabberVocabulary.MAX_TAKES])
		return
	open_key = w.key
	changed.emit()
	refresh()
	var note := " (kept the first %d seconds)" % int(BlabberClip.MAX_SECONDS) if long else ""
	if clip.pitch <= 0.0:
		note += ". It has no clear pitch, so it plays as it is instead of following the melody"
	_say("Take %d of “%s”: %.1f s%s." % [w.takes.size(), w.text, clip.duration(), note])
	_hear_take[w.key] = w.takes.size() - 2 # So Hear plays the new take next.
	_hear(w)


func _open_file(w: BlabberWord) -> void:
	if BlabberWeb.available():
		return # The file input laid over the button opens the picker.
	if file_dialog:
		file_dialog.queue_free()
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	file_dialog.filters = PackedStringArray(["*.wav, *.ogg, *.mp3 ; Audio files"])
	file_dialog.file_selected.connect(func(path: String) -> void: load_path(w.key, path), CONNECT_ONE_SHOT)
	add_child(file_dialog)
	file_dialog.popup_centered_ratio(0.7)


## Adds a sound file as a take of the word with this key.
func load_path(key: String, path: String) -> void:
	if _busy or recorder.recording:
		return
	if not path.get_extension().to_lower() in BlabberAudioImport.EXTENSIONS:
		_say("Use a WAV, OGG or MP3 file.")
		return
	_busy = true
	refresh()
	_say("Loading %s…" % path.get_file())
	var result: Dictionary = await importer.load_file(path)
	_busy = false
	if not result.ok:
		refresh()
		_say(result.error)
		return
	_add_audio(key, result.samples, result.rate, path.get_file())


## Web: an invisible file input over the open word's Load button.
func _web_file_input() -> void:
	if _load_button and is_instance_valid(_load_button):
		BlabberWeb.place_file_input(_load_button, _load_button.is_visible_in_tree() and not _load_button.disabled)
	var key: String = _load_words.get(BlabberWeb.file_source(), "")
	if BlabberWeb.file_kind() != "audio" or key == "":
		return # Not one of this page's buttons.
	match BlabberWeb.state():
		"decoding":
			_say("Reading %s…" % BlabberWeb.file_name())
		"done":
			var n := BlabberWeb.file_name()
			var samples := BlabberWeb.take_file()
			_add_audio(key, samples, BlabberWeb.rate(), n)
		"error":
			_say(BlabberWeb.error())
			BlabberWeb.reset()


func _say(text: String) -> void:
	status.text = text
	status.visible = text != ""
